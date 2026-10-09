const std = @import("std");
const engine_mod = @import("extensions/engine.zig");
const c = engine_mod.c;
fn collect(context: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = engine_mod.Engine.fromContext(context.?);
    c.JS_RunGC(engine.runtime);
    return c.pi_js_undefined();
}
fn nestedCheckpoint(context: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = engine_mod.Engine.fromContext(context.?);
    engine.finishJob();
    c.JS_RunGC(engine.runtime);
    return c.pi_js_undefined();
}
fn install(engine: *engine_mod.Engine) !void {
    try @import("extensions/timers.zig").install(engine, std.testing.io);
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    if (c.JS_SetPropertyStr(engine.context, global, "gc", try engine.checked(c.JS_NewCFunction(engine.context, collect, "gc", 0))) < 0) return error.JavaScriptException;
    if (c.JS_SetPropertyStr(engine.context, global, "nestedCheckpoint", try engine.checked(c.JS_NewCFunction(engine.context, nestedCheckpoint, "nestedCheckpoint", 0))) < 0) return error.JavaScriptException;
}
test "native WeakRef constructor deref and symbol kept objects match actual V8 job microtask and event-loop fixture" {
    const gpa = std.testing.allocator;
    const engine = try engine_mod.Engine.init(gpa, .{});
    defer engine.deinit();
    try install(engine);
    const pending = try engine.eval(source, "weakref-v8-fixture.js", c.JS_EVAL_TYPE_GLOBAL);
    defer engine.freeValue(pending);
    const result = try engine.awaitValue(pending);
    defer engine.freeValue(result);
    const text = try engine.stringify(result);
    defer gpa.free(text);
    var expected = try std.json.parseFromSlice(std.json.Value, gpa, @embedFile("extensions/fixtures/weakref-kept-objects-v8-20261009.json"), .{});
    defer expected.deinit();
    var actual = try std.json.parseFromSlice(std.json.Value, gpa, text, .{});
    defer actual.deinit();
    try std.testing.expect(@import("mcp/protocol.zig").json.equal(expected.value.object.get("results").?, actual.value));
}
test "native WeakRef kept cycle is a GC root through nested C callbacks and releases at the host checkpoint" {
    const engine = try engine_mod.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    try install(engine);
    const result = try engine.eval("globalThis.ref=(()=>{const target={marker:42};target.self=target;return new WeakRef(target)})();nestedCheckpoint();gc();if(ref.deref()?.marker!==42)throw Error('lost current job cycle');Promise.resolve().then(()=>{gc();if(ref.deref()?.marker!==42)throw Error('lost queued microtask cycle')});", "weak-cycle-root.js", c.JS_EVAL_TYPE_GLOBAL);
    engine.freeValue(result);
    // Even an explicit boundary cannot clear while the microtask queue is live.
    engine.finishJob();
    _ = try engine.drainReadyJobs();
    c.JS_RunGC(engine.runtime);
    const collected = try engine.eval("ref.deref()===undefined", "weak-cycle-collected.js", c.JS_EVAL_TYPE_GLOBAL);
    defer engine.freeValue(collected);
    try std.testing.expectEqual(@as(c_int, 1), c.JS_ToBool(engine.context, collected));
}
test "native WeakRef partial kept roots release after C heap exhaustion and keep runtime reusable" {
    const engine = try engine_mod.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    const baseline = c.pi_js_native_memory_used(engine.native_memory_owner);
    c.JS_SetMemoryLimit(engine.runtime, baseline + 256 * 1024);
    try std.testing.expectError(error.JavaScriptException, engine.eval("globalThis.keptProgress=0;for(let i=0;i<100000;i++){new WeakRef({marker:i});keptProgress++}", "weakref-c-allocation-pressure.js", c.JS_EVAL_TYPE_GLOBAL));
    c.JS_SetMemoryLimit(engine.runtime, engine.options.memory_limit);
    const progress = try engine.eval("keptProgress", "weakref-progress.js", c.JS_EVAL_TYPE_GLOBAL);
    defer engine.freeValue(progress);
    var count: i64 = 0;
    try std.testing.expectEqual(@as(c_int, 0), c.JS_ToInt64(engine.context, &count, progress));
    try std.testing.expect(count >= 16 and count < 100000);
    engine.beginInvocation();
    c.JS_RunGC(engine.runtime);
    // All temporary targets and the retained-list contents have gone. The
    // empty retained-list allocation is reusable capacity owned by Runtime.
    var capacity: usize = 16;
    while (capacity <= @as(usize, @intCast(count))) capacity *= 2;
    const allowed = baseline + capacity * @sizeOf(c.JSValue) + 16 * 1024;
    const remaining = c.pi_js_native_memory_used(engine.native_memory_owner);
    if (remaining >= allowed) std.debug.print("WeakRef retained heap baseline={d} remaining={d} targets={d} capacity={d} allowed={d}\n", .{ baseline, remaining, count, capacity, allowed });
    try std.testing.expect(remaining < allowed);
    const reusable = try engine.eval("new WeakRef({marker:7}).deref().marker", "weakref-after-allocation-pressure.js", c.JS_EVAL_TYPE_GLOBAL);
    defer engine.freeValue(reusable);
    try std.testing.expectEqual(@as(c_int, 0), c.JS_ToInt64(engine.context, &count, reusable));
    try std.testing.expectEqual(@as(i64, 7), count);
}
const source =
    \\(async()=>{
    \\const collect=()=>{for(let i=0;i<4;i++)gc()};
    \\const turn=()=>new Promise(resolve=>setTimeout(resolve,0));
    \\const results={};
    \\let first={marker:'constructor'};
    \\const created=new WeakRef(first);first=null;
    \\collect();results.constructorSameJob=created.deref()?.marker==='constructor';
    \\await Promise.resolve();collect();results.constructorMicrotask=created.deref()?.marker==='constructor';
    \\for(let i=0;i<16;i++){await turn();collect()}
    \\await turn();results.constructorAfterTurns=created.deref()===undefined;
    \\let second={marker:'deref'};const read=new WeakRef(second);
    \\await turn();let dereferenced=read.deref();second=null;dereferenced=null;
    \\collect();results.derefSameJob=read.deref()?.marker==='deref';
    \\await Promise.resolve();collect();results.derefMicrotask=read.deref()?.marker==='deref';
    \\for(let i=0;i<16;i++){await turn();collect()}
    \\await turn();results.derefAfterTurns=read.deref()===undefined;
    \\const symbol=Symbol('weak-key');const symbolRef=new WeakRef(symbol);collect();results.symbolSameJob=symbolRef.deref()===symbol;
    \\return results;
    \\})()
;
