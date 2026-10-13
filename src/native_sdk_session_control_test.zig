const std = @import("std");
const em = @import("extensions/engine.zig");
const sdk = @import("extensions/native_sdk.zig");
const js = @import("extensions/native_js_values.zig");
const c = em.c;
fn reportSwallowedAllocation(gpa: std.mem.Allocator) void {
    const failing: *std.testing.FailingAllocator = @ptrCast(@alignCast(gpa.ptr));
    if (failing.has_induced_failure) {
        std.debug.print("Session control swallowed host allocation index={d}\n", .{failing.fail_index});
        const trace = failing.getStackTrace();
        std.debug.dumpStackTrace(&trace);
    }
}
fn setup(engine: *em.Engine, environment: *std.process.Environ.Map) !void {
    try @import("native_sdk_session_prompt_handlers_test.zig").setup(engine, environment);
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    const namespace = try sdk.get(engine, global, "constructorPhaseSDK");
    defer engine.freeValue(namespace);
    const constructor = try sdk.get(engine, namespace, "AgentSession");
    defer engine.freeValue(constructor);
    const prototype = try sdk.get(engine, constructor, "prototype");
    defer engine.freeValue(prototype);
    try @import("extensions/native_sdk_custom_message.zig").install(engine, prototype);
    try @import("extensions/native_sdk_session_control.zig").install(engine, prototype);
    try sdk.put(engine, global, "sessionResourceAPI", try @import("extensions/native_ai_session_resources.zig").bindings(engine));
    const source = @embedFile("extensions/fixtures/sdk-session-control-e622.json");
    try sdk.put(engine, global, "sessionControlSource", try engine.checked(c.JS_ParseJSON(engine.context, source.ptr, source.len, "sdk-session-control-e622.json")));
    const adapter = try engine.evalModule(
        \\globalThis.createControlCase=async()=>{const state=createNativeConstructorPhase(),unsubscribe=state.session._unsubscribeAgent,warmer=state.warmer;state.session._extensionRunner={invalidate(){}};return{...state,dispose(){unsubscribe();warmer.cancel();}}};
    , "native-sdk-session-control-adapter.mjs");
    engine.freeValue(adapter);
}
test "native SDK session control matches33 original factory idle abort disposal queue settings and AI cleanup cases" {
    const engine = try em.Engine.init(std.testing.allocator, .{ .host_await_timeout_ms = 10000 });
    defer engine.deinit();
    var environment: std.process.Environ.Map = .init(std.testing.allocator);
    defer environment.deinit();
    try setup(engine, &environment);
    const result = engine.evalModule(@embedFile("extensions/fixtures/sdk-session-control-e622.input.txt") ++
        "\nif(sessionControlRows.length!==33||sessionControlSource.rows.length!==33)throw Error('33 original factory cases required');for(let i=0;i<33;i++)if(JSON.stringify(sessionControlRows[i])!==JSON.stringify(sessionControlSource.rows[i]))throw Error(JSON.stringify({case:i,actual:sessionControlRows[i],expected:sessionControlSource.rows[i]}));", "native-sdk-session-control-source.mjs") catch |err| {
        std.debug.print("Session control Source: {s}\n", .{engine.last_error orelse "no diagnostic"});
        return err;
    };
    engine.freeValue(result);
    c.JS_RunGC(engine.runtime);
}
test "native SDK session control retains idle waiters and shared cleanup callbacks through collection" {
    const engine = try em.Engine.init(std.testing.allocator, .{ .host_await_timeout_ms = 10000 });
    defer engine.deinit();
    var environment: std.process.Environ.Map = .init(std.testing.allocator);
    defer environment.deinit();
    try setup(engine, &environment);
    const prepared = try engine.evalModule(
        \\const state=await createControlCase();state.session._isAgentRunActive=true;const wait=state.session.waitForIdle();globalThis.controlRetained={state,wait,calls:0,off:sessionResourceAPI.registerSessionResourceCleanup(id=>{if(id!==controlRetained.state.session.sessionId)throw Error('session id lost');controlRetained.calls++;})};export const prepared=true;
    , "native-sdk-session-control-gc-prepare.mjs");
    engine.freeValue(prepared);
    c.JS_RunGC(engine.runtime);
    const completed = try engine.evalModule(
        \\controlRetained.state.session._isAgentRunActive=false;controlRetained.state.session._resolveIdleWaitIfIdle();await controlRetained.wait;controlRetained.state.session.dispose();if(controlRetained.calls!==1||controlRetained.state.session._unsubscribeAgent!==undefined)throw Error('control graph lost');controlRetained.off();delete globalThis.controlRetained;export const completed=true;
    , "native-sdk-session-control-gc-complete.mjs");
    engine.freeValue(completed);
    c.JS_RunGC(engine.runtime);
}
test "native SDK session control all allocation failures release idle cancellation disposal and cleanup registry graphs" {
    const Probe = struct {
        fn run(gpa: std.mem.Allocator) !void {
            var succeeded = false;
            defer if (succeeded) reportSwallowedAllocation(gpa);
            const engine = try em.Engine.init(gpa, .{ .host_await_timeout_ms = 10000 });
            defer engine.deinit();
            var environment: std.process.Environ.Map = .init(gpa);
            defer environment.deinit();
            try setup(engine, &environment);
            const generation = engine.native_allocation_generation;
            const result = engine.evalModule(
                \\const state=await createControlCase();state.session._isAgentRunActive=true;const wait=state.session.waitForIdle(),first=state.session._getIdleWaitPromise();if(first!==state.session._getIdleWaitPromise())throw Error('waiter changed');state.session._isAgentRunActive=false;state.session._resolveIdleWaitIfIdle();await wait;state.session.setSteeringMode('all');state.session.setAutoRetryEnabled(false);let calls=0;const off=sessionResourceAPI.registerSessionResourceCleanup(id=>{if(id!==state.session.sessionId)throw Error('cleanup id');calls++;});state.session.dispose();if(calls!==1||state.session._unsubscribeAgent!==undefined)throw Error('dispose mismatch');off();export const proof=true;
            , "native-sdk-session-control-allocations.mjs") catch |err| return engine.nativeAllocationError(err, generation);
            engine.freeValue(result);
            c.JS_RunGC(engine.runtime);
            succeeded = true;
        }
    };
    try std.testing.checkAllAllocationFailures(std.testing.allocator, Probe.run, .{});
}
test "native SDK session control cleanup aggregate errors retain original identity across every allocation failure" {
    const Probe = struct {
        fn run(gpa: std.mem.Allocator) !void {
            var succeeded = false;
            defer if (succeeded) reportSwallowedAllocation(gpa);
            const engine = try em.Engine.init(gpa, .{ .host_await_timeout_ms = 10000 });
            defer engine.deinit();
            var environment: std.process.Environ.Map = .init(gpa);
            defer environment.deinit();
            try setup(engine, &environment);
            const generation = engine.native_allocation_generation;
            const prepared = engine.evalModule(
                \\globalThis.cleanupMarker={tag:'original'};globalThis.cleanupRelease=sessionResourceAPI.registerSessionResourceCleanup(()=>{throw cleanupMarker;});export const prepared=true;
            , "native-sdk-session-cleanup-aggregate-prepare.mjs") catch |err| return engine.nativeAllocationError(err, generation);
            engine.freeValue(prepared);
            c.JS_RunGC(engine.runtime);
            const global = c.JS_GetGlobalObject(engine.context);
            defer engine.freeValue(global);
            const namespace = try sdk.get(engine, global, "sessionResourceAPI");
            defer engine.freeValue(namespace);
            const cleanup = try sdk.get(engine, namespace, "cleanupSessionResources");
            defer engine.freeValue(cleanup);
            if (js.call(engine, cleanup, c.pi_js_undefined(), &.{})) |unexpected| {
                engine.freeValue(unexpected);
                return error.ExpectedCleanupAggregate;
            } else |raw| {
                const failure = engine.nativeAllocationError(raw, generation);
                if (failure == error.OutOfMemory) return failure;
                try std.testing.expectEqual(error.JavaScriptException, failure);
                const reason = @import("extensions/native_agent_async.zig").reason(engine, failure);
                defer engine.freeValue(reason);
                const errors = try sdk.get(engine, reason, "errors");
                defer engine.freeValue(errors);
                try std.testing.expectEqual(@as(usize, 1), try sdk.length(engine, errors));
                const first = try engine.checked(c.JS_GetPropertyUint32(engine.context, errors, 0));
                defer engine.freeValue(first);
                const marker = try sdk.get(engine, global, "cleanupMarker");
                defer engine.freeValue(marker);
                try std.testing.expect(c.JS_IsStrictEqual(engine.context, first, marker));
            }
            const ignored = try sdk.invoke(engine, global, "cleanupRelease", &.{});
            engine.freeValue(ignored);
            c.JS_RunGC(engine.runtime);
            succeeded = true;
        }
    };
    try std.testing.checkAllAllocationFailures(std.testing.allocator, Probe.run, .{});
}
