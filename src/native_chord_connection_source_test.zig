const std = @import("std");
const em = @import("extensions/engine.zig");
const js = @import("extensions/native_js_values.zig");
test "native Chord connection compiled inventory records actual selected Source GC and allocation gates" {
    const functions = @import("builtin").test_functions;
    const names = try std.testing.allocator.alloc([]const u8, functions.len);
    defer std.testing.allocator.free(names);
    for (functions, names) |function, *name| name.* = function.name;
    const encoded = try std.json.Stringify.valueAlloc(std.testing.allocator, names, .{});
    defer std.testing.allocator.free(encoded);
    std.debug.print("CHORD_CONNECTION_COMPILED_INVENTORY={s}\n", .{encoded});
}
fn setup(gpa: std.mem.Allocator) !*em.Engine {
    const engine = try em.Engine.init(gpa, .{ .host_await_timeout_ms = 10000 });
    errdefer engine.deinit();
    engine.native_io = std.testing.io;
    try @import("extensions/timers.zig").install(engine, std.testing.io);
    const classes = try @import("extensions/native_chord_host.zig").classes(engine);
    defer engine.freeValue(classes.bindings);
    defer engine.freeValue(classes.exports);
    try @import("extensions/native_chord_connection.zig").install(engine, classes.bindings);
    const api = try js.object(engine);
    defer engine.freeValue(api);
    inline for (.{ "Connection", "RemoteHandle" }) |name| try js.define(engine, api, name, try js.get(engine, classes.bindings, name));
    inline for (.{ "remote", "method", "memoryLinkPair" }) |name| try js.define(engine, api, name, try js.get(engine, classes.exports, name));
    const codec = try js.get(engine, classes.bindings, "DeltaCodec");
    defer engine.freeValue(codec);
    try js.define(engine, api, "encoder", try js.get(engine, codec, "encoder"));
    const root = em.c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(root);
    try js.define(engine, root, "nativeConnectionApi", em.c.JS_DupValue(engine.context, api));
    return engine;
}
test "native Chord connection actual Source21 constructor protocol control and12negative outcomes" {
    const engine = try setup(std.testing.allocator);
    defer engine.deinit();
    const original = @embedFile("extensions/fixtures/chord-connection-original-e622.json");
    const root = em.c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(root);
    try js.define(engine, root, "connectionSource", try engine.checked(em.c.JS_ParseJSON(engine.context, original.ptr, original.len, "connection-original.json")));
    const result = engine.evalModule("const api=nativeConnectionApi;await(async()=>{\n" ++ @embedFile("extensions/fixtures/chord-connection-original-e622.input.txt") ++ "\n})();const actual=chordConnectionCases;if(actual.length!==connectionSource.cases.length)throw Error('Connection Source count');for(let i=0;i<actual.length;i++)if(JSON.stringify(actual[i])!==JSON.stringify(connectionSource.cases[i]))throw Error(JSON.stringify({case:i,actual:actual[i],expected:connectionSource.cases[i]}));", "chord-connection-source.mjs") catch |err| {
        std.debug.print("Native Chord connection Source: {s}\n", .{engine.last_error orelse "no diagnostic"});
        return err;
    };
    engine.freeValue(result);
}
test "native Chord connection latest Source2 already closed ends notify once and initialize no keepalive" {
    const engine = try setup(std.testing.allocator);
    defer engine.deinit();
    const original = @embedFile("extensions/fixtures/chord-connection-closed-original-e622.json");
    const root = em.c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(root);
    try js.define(engine, root, "connectionClosedSource", try engine.checked(em.c.JS_ParseJSON(engine.context, original.ptr, original.len, "connection-closed-original.json")));
    const result = engine.evalModule("const api=nativeConnectionApi;await(async()=>{\n" ++ @embedFile("extensions/fixtures/chord-connection-closed-original-e622.input.txt") ++ "\n})();if(JSON.stringify(chordConnectionClosedCases)!==JSON.stringify(connectionClosedSource.cases))throw Error(JSON.stringify({actual:chordConnectionClosedCases,expected:connectionClosedSource.cases}));", "chord-connection-closed-source.mjs") catch |err| {
        std.debug.print("Native Chord connection closed Source: {s}\n", .{engine.last_error orelse "no diagnostic"});
        return err;
    };
    engine.freeValue(result);
}
const retained_start =
    \\const api=nativeConnectionApi,log=[],sent=[],states=[],[a,b]=api.memoryLinkPair(),host={name:'server',kind:'host',current:{id:1},report(error){throw error},rootSent(id,connection){log.push(['root',id,connection===conn])},connectionClosed(connection){log.push(['closed',connection===conn])}};b.receive(frame=>sent.push(frame));const conn=new api.Connection(host,a,{role:'downstream',principal:{user:'a'},peer:{kind:'client',name:undefined},pingInterval:1000000,pingTimeout:45000}),controller=new AbortController(),pending=conn.call(7,'run',{n:1},{rootId:'r',epoch:1},controller.signal),sub=conn.sub(7,'count',frame=>states.push(frame));globalThis.connectionPending={conn,a,b,host,pending,sub,sent,states,log};
;
const retained_finish =
    \\const p=connectionPending;await Promise.resolve();await Promise.resolve();const call=p.sent.find(frame=>frame.t==='call');if(!call)throw Error('retained call missing');p.b.send({t:'result',id:call.id,value:{n:4}});const result=await p.pending;p.b.send({t:'state',id:p.sub,snap:9});await Promise.resolve();await Promise.resolve();if(result.n!==4||p.states[0]?.snap!==9||p.conn.calls.size!==0)throw Error('retained connection graph lost');p.conn.unsub(p.sub);p.conn.release(7);p.a.close('complete');if(p.conn.open||p.conn.subs.size||p.log.at(-1)?.[0]!=='closed')throw Error('connection ownership did not close');delete globalThis.connectionPending;
;
test "native Chord connection unresolved calls subscriptions timer and channels survive GC" {
    const engine = try setup(std.testing.allocator);
    defer engine.deinit();
    const started = try engine.evalModule(retained_start, "chord-connection-gc-start.mjs");
    engine.freeValue(started);
    em.c.JS_RunGC(engine.runtime);
    const completed = try engine.evalModule(retained_finish, "chord-connection-gc-finish.mjs");
    engine.freeValue(completed);
    em.c.JS_RunGC(engine.runtime);
}
test "native Chord connection complete constructor call subscription timer and teardown allocation sweep" {
    const Probe = struct {
        fn run(gpa: std.mem.Allocator) !void {
            const engine = try setup(gpa);
            defer engine.deinit();
            const generation = engine.native_allocation_generation;
            engine.native_exception_diagnostics_suppressed += 1;
            defer engine.native_exception_diagnostics_suppressed -= 1;
            const result = engine.evalModule(retained_start ++ "\n" ++ retained_finish, "chord-connection-allocation.mjs") catch |err| {
                const mapped = engine.nativeAllocationError(err, generation);
                if (mapped != error.OutOfMemory) {
                    const failed: *std.testing.FailingAllocator = @ptrCast(@alignCast(gpa.ptr));
                    std.debug.print("Connection GPA index{d} error={s} generation={d}->{d}: {s}\n{f}\n", .{ failed.fail_index, @errorName(mapped), generation, engine.native_allocation_generation, engine.last_error orelse "no diagnostic", std.debug.FormatStackTrace{ .stack_trace = failed.getStackTrace() } });
                }
                return mapped;
            };
            engine.freeValue(result);
        }
    };
    try std.testing.checkAllAllocationFailures(std.testing.allocator, Probe.run, .{});
}
fn observeGuestRejection(ctx: ?*em.c.JSContext, _: em.c.JSValue, reason: em.c.JSValue, handled: bool, raw: ?*anyopaque) callconv(.c) void {
    if (handled) return;
    const recorded: *?em.c.JSValue = @ptrCast(@alignCast(raw.?));
    if (recorded.* == null) recorded.* = em.c.JS_DupValue(ctx, reason);
}
test "native Chord connection private delivery OOM escapes then trusted classification clears only its propagation flag" {
    var failing = std.testing.FailingAllocator.init(std.testing.allocator, .{});
    const engine = try setup(failing.allocator());
    defer engine.deinit();
    engine.native_exception_diagnostics_suppressed += 1;
    defer engine.native_exception_diagnostics_suppressed -= 1;
    const queued = try engine.eval(
        \\globalThis.deliveryPair=nativeConnectionApi.memoryLinkPair();deliveryPair[1].receive(()=>{});deliveryPair[0].send({t:'ping',n:1});globalThis.deliveryWait=new Promise(()=>{});
    , "delivery-private-native-oom.js", em.c.JS_EVAL_TYPE_GLOBAL);
    engine.freeValue(queued);
    const root = em.c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(root);
    const waiting = try js.get(engine, root, "deliveryWait");
    defer engine.freeValue(waiting);
    const generation = engine.native_allocation_generation;
    // Fail the actual queued native delivery's first allocation, independently
    // of the constructor's allocation count or any hard-coded sweep index.
    failing.fail_index = failing.alloc_index;
    const result = engine.awaitValueOnly(waiting);
    failing.fail_index = std.math.maxInt(usize);
    if (result) |value| {
        engine.freeValue(value);
        return error.NativeDeliveryFailureDidNotEscape;
    } else |err| try std.testing.expectEqual(error.JavaScriptException, err);
    try std.testing.expect(failing.has_induced_failure);
    const original = em.c.JS_DupValue(engine.context, engine.captured_exception orelse return error.MissingNativeDeliveryFailure);
    defer engine.freeValue(original);
    try std.testing.expect(em.c.JS_IsUncatchableError(original));
    try std.testing.expectEqual(error.OutOfMemory, engine.nativeAllocationError(error.JavaScriptException, generation));
    try std.testing.expect(!em.c.JS_IsUncatchableError(original));
    try std.testing.expect(em.c.JS_IsStrictEqual(engine.context, original, engine.captured_exception.?));
    try js.define(engine, root, "savedNativeDeliveryOom", em.c.JS_DupValue(engine.context, original));
    const caught = try engine.eval("try{throw savedNativeDeliveryOom}catch(error){if(error!==savedNativeDeliveryOom)throw Error('retained identity changed')}", "delivery-old-native-caught.js", em.c.JS_EVAL_TYPE_GLOBAL);
    engine.freeValue(caught);
    const later_generation = engine.native_allocation_generation;
    try std.testing.expectError(error.JavaScriptException, engine.eval("throw savedNativeDeliveryOom", "delivery-old-native-rethrow.js", em.c.JS_EVAL_TYPE_GLOBAL));
    try std.testing.expectEqual(error.JavaScriptException, engine.nativeAllocationError(error.JavaScriptException, later_generation));
    try std.testing.expect(em.c.JS_IsStrictEqual(engine.context, original, engine.captured_exception.?));
    var rejected: ?em.c.JSValue = null;
    defer if (rejected) |value| engine.freeValue(value);
    em.c.JS_SetHostPromiseRejectionTracker(engine.runtime, observeGuestRejection, &rejected);
    defer em.c.JS_SetHostPromiseRejectionTracker(engine.runtime, null, null);
    const guest = try engine.eval(
        \\globalThis.deliveryLookalike={name:'OutOfMemory',message:'out of memory'};globalThis.guestDeliveryPair=nativeConnectionApi.memoryLinkPair();guestDeliveryPair[1].receive(()=>{throw deliveryLookalike});guestDeliveryPair[0].send({t:'ping',n:1});
    , "delivery-ordinary-guest.js", em.c.JS_EVAL_TYPE_GLOBAL);
    engine.freeValue(guest);
    _ = try engine.drainReadyJobs();
    const expected = try js.get(engine, root, "deliveryLookalike");
    defer engine.freeValue(expected);
    const observed = rejected orelse return error.MissingOrdinaryGuestRejection;
    try std.testing.expect(em.c.JS_IsStrictEqual(engine.context, expected, observed));
    try std.testing.expect(!em.c.JS_IsUncatchableError(observed));
    try std.testing.expectEqual(@as(u64, 0), em.c.pi_js_native_allocation_error_generation(observed));
    try std.testing.expectEqual(later_generation, engine.native_allocation_generation);
}
