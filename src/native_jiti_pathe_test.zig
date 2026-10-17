//! Prepared controls, unrun. Original expected JSON must come from the pinned
//! pathe2.0.3 package, never an authored golden or node:path substitution.
const std = @import("std");
const em = @import("extensions/engine.zig");
const js = @import("extensions/native_js_values.zig");
const pathe = @import("extensions/native_pathe.zig");
const c = em.c;
fn install(engine: *em.Engine) !void {
    const bindings = try pathe.create(engine); defer engine.freeValue(bindings);
    const subject = try js.object(engine); defer engine.freeValue(subject);
    try js.define(engine, subject, "path", c.JS_DupValue(engine.context, bindings));
    try js.define(engine, subject, "utils", c.JS_DupValue(engine.context, bindings));
    const global = c.JS_GetGlobalObject(engine.context); defer engine.freeValue(global);
    try js.define(engine, global, "nativePatheSubject", c.JS_DupValue(engine.context, subject));
}
test "native jiti pathe compares every genuine pinned path alias and observation row" {
    const expected = try std.Io.Dir.cwd().readFileAlloc(std.testing.io, "src/extensions/fixtures/jiti-pathe-2.0.3.json", std.testing.allocator, .limited(4 * 1024 * 1024)); defer std.testing.allocator.free(expected);
    const engine = try em.Engine.init(std.testing.allocator, .{ .host_await_timeout_ms = 10000 }); defer engine.deinit();
    try install(engine);
    const terminated = try engine.gpa.dupeZ(u8, expected); defer engine.gpa.free(terminated);
    const global = c.JS_GetGlobalObject(engine.context); defer engine.freeValue(global);
    try js.define(engine, global, "originalPatheExpected", try engine.checked(c.JS_ParseJSON(engine.context, terminated.ptr, expected.len, "actual-pathe2.0.3.json")));
    const result = try engine.evalModule(@embedFile("extensions/fixtures/jiti-pathe-2.0.3.input.mjs") ++
        \\if(nativePatheObservation.count!==originalPatheExpected.count)throw Error('Exact full pathe subject census required');for(let i=0;i<nativePatheObservation.rows.length;i++)if(JSON.stringify(nativePatheObservation.rows[i])!==JSON.stringify(originalPatheExpected.rows[i]))throw Error(JSON.stringify({index:i,actual:nativePatheObservation.rows[i],original:originalPatheExpected.rows[i]}));
    , "native-jiti-pathe-original.mjs"); engine.freeValue(result);
}
test "native jiti pathe imported function roots retain private regex and alias symbol through GC" {
    const engine = try em.Engine.init(std.testing.allocator, .{}); defer engine.deinit(); try install(engine);
    const first = try engine.evalModule(
        \\globalThis.keptPatheJoin=nativePatheSubject.path.join;globalThis.keptPatheAliases=nativePatheSubject.utils.normalizeAliases;delete globalThis.nativePatheSubject;
    , "native-jiti-pathe-retain.mjs"); engine.freeValue(first); c.JS_RunGC(engine.runtime);
    const result = try engine.evalModule(
        \\if(keptPatheJoin('a','b','..','c')!=='a/c')throw Error('retained lexical path operation');const a=keptPatheAliases({a:'b/x',b:'/root'});if(a.a!=='/root/x'||keptPatheAliases(a)!==a||!a[Symbol.for('pathe:normalizedAlias')])throw Error('retained alias roots');delete globalThis.keptPatheJoin;delete globalThis.keptPatheAliases;
    , "native-jiti-pathe-after-gc.mjs"); engine.freeValue(result); c.JS_RunGC(engine.runtime);
}
fn raiseAllocation(context: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?); _ = engine.throwNativeOutOfMemory(); const reason = c.JS_GetException(context);
    const global = c.JS_GetGlobalObject(context); defer engine.freeValue(global);
    if (c.JS_DefinePropertyValueStr(context, global, "ownedPatheFatalReason", c.JS_DupValue(context, reason), c.JS_PROP_C_W_E) < 0) { engine.freeValue(reason); return c.JS_Throw(context, c.JS_GetException(context)); }
    return c.JS_Throw(context, reason);
}
test "native jiti pathe retains exact fatal reason through attempted source iterator cleanup" {
    const engine = try em.Engine.init(std.testing.allocator, .{}); defer engine.deinit(); try install(engine);
    const global = c.JS_GetGlobalObject(engine.context); defer engine.freeValue(global);
    try js.define(engine, global, "raiseOwnedPatheAllocation", try engine.checked(c.JS_NewCFunction(engine.context, raiseAllocation, "raiseOwnedPatheAllocation", 0)));
    try std.testing.expectError(error.JavaScriptException, engine.evalModule(
        \\globalThis.patheGuestCaught=false;globalThis.patheCleanupEntered=false;const original=Array.prototype[Symbol.iterator];Array.prototype[Symbol.iterator]=function(){let done=false;return{next(){if(done)return{done:true};done=true;return{done:false,value:{toString:raiseOwnedPatheAllocation}}},return(){globalThis.patheCleanupEntered=true;throw {ordinaryCleanup:true}}}};try{try{nativePatheSubject.path.join('x')}catch{globalThis.patheGuestCaught=true}}finally{Array.prototype[Symbol.iterator]=original}
    , "native-jiti-pathe-fatal-cleanup.mjs"));
    const original = try js.get(engine, global, "ownedPatheFatalReason"); defer engine.freeValue(original);
    const actual = engine.captured_exception orelse return error.MissingPatheFatalReason;
    try std.testing.expect(c.JS_IsStrictEqual(engine.context, original, actual)); try std.testing.expect(c.JS_IsUncatchableError(actual));
    const caught = try js.get(engine, global, "patheGuestCaught"); defer engine.freeValue(caught); try std.testing.expectEqual(@as(c_int, 0), c.JS_ToBool(engine.context, caught));
    const entered = try js.get(engine, global, "patheCleanupEntered"); defer engine.freeValue(entered); try std.testing.expectEqual(@as(c_int, 1), c.JS_ToBool(engine.context, entered));
}
test "native jiti pathe cleanup native allocation bypasses an ordinary primary rejection" {
    const engine = try em.Engine.init(std.testing.allocator, .{}); defer engine.deinit(); try install(engine);
    const global = c.JS_GetGlobalObject(engine.context); defer engine.freeValue(global);
    try js.define(engine, global, "raiseOwnedPatheAllocation", try engine.checked(c.JS_NewCFunction(engine.context, raiseAllocation, "raiseOwnedPatheAllocation", 0)));
    try std.testing.expectError(error.JavaScriptException, engine.evalModule(
        \\globalThis.patheGuestCaught=false;globalThis.patheCleanupEntered=false;const original=Array.prototype[Symbol.iterator];Array.prototype[Symbol.iterator]=function(){let done=false;return{next(){if(done)return{done:true};done=true;return{done:false,value:{toString(){throw {ordinaryPrimary:true}}}}},return(){globalThis.patheCleanupEntered=true;raiseOwnedPatheAllocation()}}};try{try{nativePatheSubject.path.join('x')}catch{globalThis.patheGuestCaught=true}}finally{Array.prototype[Symbol.iterator]=original}
    , "native-jiti-pathe-cleanup-fatal.mjs"));
    const original = try js.get(engine, global, "ownedPatheFatalReason"); defer engine.freeValue(original);
    const actual = engine.captured_exception orelse return error.MissingPatheFatalReason;
    try std.testing.expect(c.JS_IsStrictEqual(engine.context, original, actual)); try std.testing.expect(c.JS_IsUncatchableError(actual));
    const caught = try js.get(engine, global, "patheGuestCaught"); defer engine.freeValue(caught); try std.testing.expectEqual(@as(c_int, 0), c.JS_ToBool(engine.context, caught));
    const entered = try js.get(engine, global, "patheCleanupEntered"); defer engine.freeValue(entered); try std.testing.expectEqual(@as(c_int, 1), c.JS_ToBool(engine.context, entered));
}
test "native jiti pathe every Zig allocation releases partial namespace and iterator roots" {
    const Probe = struct { fn run(gpa: std.mem.Allocator) !void {
        const engine = try em.Engine.init(gpa, .{}); defer engine.deinit();
        const generation = engine.native_allocation_generation;
        install(engine) catch |err| return engine.nativeAllocationError(err, generation);
        const result = engine.evalModule(
            \\nativePatheSubject.path.join('c:\\a','..','é🌍');nativePatheSubject.utils.resolveAlias('a/x',{a:'b',b:'/root'});
        , "native-jiti-pathe-gpa.mjs") catch |err| return engine.nativeAllocationError(err, generation);
        engine.freeValue(result); c.JS_RunGC(engine.runtime);
    } };
    try std.testing.checkAllAllocationFailures(std.testing.allocator, Probe.run, .{});
}
