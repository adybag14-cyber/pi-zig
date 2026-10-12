const std = @import("std");
const em = @import("extensions/engine.zig");
const controlled = @import("extensions/native_codemode_controlled.zig");
const json = @import("mcp/protocol.zig").json;
const c = em.c;
fn nativeStart(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    const result = controlled.start(engine, if (argc > 0) argv[0] else c.pi_js_undefined(), if (argc > 1) argv[1] else c.pi_js_undefined(), 64 * 1024 * 1024) catch |err| {
        if (err == error.JavaScriptException) return engine.throwCaptured();
        if (err == error.OutOfMemory) return engine.throwNativeOutOfMemory();
        return c.JS_ThrowInternalError(context, "%s", @as([*:0]const u8, @errorName(err)));
    };
    return result;
}
fn prepare(gpa: std.mem.Allocator) !*em.Engine {
    const engine = try em.Engine.init(gpa, .{});
    errdefer engine.deinit();
    try @import("extensions/timers.zig").install(engine, std.testing.io);
    try @import("extensions/abort_signal.zig").install(engine);
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    if (c.JS_SetPropertyStr(engine.context, global, "nativeStart", try engine.checked(c.JS_NewCFunction(engine.context, nativeStart, "nativeStart", 2))) < 0) return error.JavaScriptException;
    return engine;
}

test "native CodeMode JavaScript owner preserves all eleven genuine callback reply abort outcomes through real worker threads" {
    const engine = try prepare(std.testing.allocator);
    defer engine.deinit();
    const raw = @embedFile("mcp/fixtures/codemode-run-ee409-edges-source.json");
    const input = try engine.checked(c.JS_ParseJSON(engine.context, raw.ptr, raw.len, "actual-source.json"));
    defer engine.freeValue(input);
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    if (c.JS_SetPropertyStr(engine.context, global, "sourceInput", c.JS_DupValue(engine.context, input)) < 0) return error.JavaScriptException;
    const program =
        \\(async()=>{globalThis.actualRows=[];for(const row of sourceInput.rows){
        \\ const events=[],calls=[],abort=new AbortController();let run,seq=0;
        \\ run=nativeStart(row.code,{startedAt:1768471200000,seed:1,signal:abort.signal,
        \\ tools:[{name:'echo'},{name:'wait'}],
        \\ onStarted(){events.push('started');if(row.mode==='throw-started')throw Error('started original')},
        \\ onCall(call){calls.push(call);events.push('call '+call.id);if(row.mode==='throw-call')throw Error('call original');if(row.mode==='throw-idle')return;
        \\ queueMicrotask(()=>{if(row.mode==='abort-gap'){if(call.id===2){run.deliver(2,1768471202000,2,{ok:true,value:'second'});abort.abort(Error('actual gap abort'))}return}
        \\ run.deliver(++seq,1768471200000+seq,call.id,row.mode==='success'?{ok:true,value:JSON.parse(row.serialized)}:{ok:false,message:'actual failure',properties:{toJSON(){return JSON.parse(row.serialized)}}})})},
        \\ onIdle(seq,issued){events.push(['idle',seq,issued]);if(row.mode==='throw-idle')throw Error('idle original')}
        \\ });const result=await run.result;actualRows.push({result,events,calls,finished:run.finished});run.deliver(NaN,NaN,{},null);
        \\ }return actualRows})()
    ;
    engine.host_await_deadline_ms = std.Io.Clock.awake.now(std.testing.io).toMilliseconds() + 10000;
    const began = std.Io.Clock.awake.now(std.testing.io).toMilliseconds();
    const promise = try engine.eval(program, "actual-controlled-owner.js", c.JS_EVAL_TYPE_GLOBAL);
    defer engine.freeValue(promise);
    const result = try engine.awaitValue(promise);
    defer engine.freeValue(result);
    const bytes = try engine.stringify(result);
    defer std.testing.allocator.free(bytes);
    var actual = try json.Owned.parse(std.testing.allocator, bytes);
    defer actual.deinit();
    var source = try json.Owned.parse(std.testing.allocator, raw);
    defer source.deinit();
    const rows = source.value.object.get("rows").?.array.items;
    try std.testing.expectEqual(@as(usize, 11), actual.value.array.items.len);
    const elapsed = std.Io.Clock.awake.now(std.testing.io).toMilliseconds() - began;
    for (actual.value.array.items, rows) |*observed, expected| {
        var original = try json.Owned.empty(std.testing.allocator);
        defer original.deinit();
        original.value = try json.clone(original.arena.allocator(), expected.object.get("result").?);
        const native_result = observed.object.getPtr("result").?;
        for (native_result.object.getPtr("calls").?.array.items) |*call| {
            const duration = try json.asNumber(call.object.get("durationMs").?);
            try std.testing.expect(std.math.isFinite(duration) and duration >= 0 and duration == @floor(duration) and duration <= @as(f64, @floatFromInt(elapsed + 1)));
            _ = call.object.orderedRemove("durationMs");
        }
        for (original.value.object.getPtr("calls").?.array.items) |*call| {
            const duration = try json.asNumber(call.object.get("durationMs").?);
            try std.testing.expect(std.math.isFinite(duration) and duration >= 0 and duration <= try json.asNumber(expected.object.get("elapsedMs").?));
            _ = call.object.orderedRemove("durationMs");
        }
        if (!json.equal(original.value, native_result.*)) {
            const trace = try json.stringify(std.testing.allocator, observed.*);
            defer std.testing.allocator.free(trace);
            std.debug.print("JS owner Source row {s} actual={s}\n", .{ expected.object.get("name").?.string, trace });
        }
        try std.testing.expect(json.equal(original.value, native_result.*));
        inline for (.{ "events", "calls", "finished" }) |key| try std.testing.expect(json.equal(expected.object.get(key).?, observed.object.get(key).?));
    }
}

test "native CodeMode JavaScript owner releases failed owner allocations before and after actual worker publication and promise settlement" {
    const Lifecycle = struct {
        fn exercise(gpa: std.mem.Allocator) !void {
            const engine = try prepare(gpa);
            defer engine.deinit();
            engine.host_await_deadline_ms = std.Io.Clock.awake.now(std.testing.io).toMilliseconds() + 10000;
            const generation = engine.native_allocation_generation;
            const promise = engine.eval("nativeStart('return 7',{startedAt:0,seed:1,onCall(){throw Error('unexpected call')}}).result", "owner-allocation.js", c.JS_EVAL_TYPE_GLOBAL) catch |err| return engine.nativeAllocationError(err, generation);
            defer engine.freeValue(promise);
            const result = engine.awaitValue(promise) catch |err| return engine.nativeAllocationError(err, generation);
            defer engine.freeValue(result);
            const ok = try engine.checked(c.JS_GetPropertyStr(engine.context, result, "ok"));
            defer engine.freeValue(ok);
            try std.testing.expect(c.JS_ToBool(engine.context, ok) != 0);
            const value = try engine.checked(c.JS_GetPropertyStr(engine.context, result, "value"));
            defer engine.freeValue(value);
            var number: i32 = 0;
            if (c.JS_ToInt32(engine.context, &number, value) < 0) return error.JavaScriptException;
            try std.testing.expectEqual(@as(i32, 7), number);
        }
    };
    try std.testing.checkAllAllocationFailures(std.testing.allocator, Lifecycle.exercise, .{});
}
