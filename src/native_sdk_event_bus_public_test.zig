//! Actual c268 EventBus factory over the genuine installed EventEmitter.
//! Separate Source/native Engines; actual VM async Await and C holder controls.
//! Authored only: native build, metadata and runtime require Root's grant.
const std = @import("std");
const h = @import("extensions/native_sdk_session_locals.zig");
const v = h.v;
const c = v.c;
const bus = @import("extensions/native_sdk_event_bus.zig");
const retirement = @import("native_sdk_initial_model_retirement_controls.zig");
const observer = @embedFile("extensions/fixtures/sdk-event-bus-observer.mjs");
fn publish(s: *h.Scope, name: [*:0]const u8, input: c.JSValue) !void {
    try v.put(s, try v.own(s, c.JS_GetGlobalObject(s.engine.context)), name, input);
}
fn asyncBrand(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue) callconv(.c) c.JSValue {
    return c.pi_js_bool(context, @intFromBool(argc > 0 and c.JS_IsAsyncFunction(argv[0])));
}
fn prepare(engine: *h.Engine) !void {
    return h.statement(engine, prepareBody, .{});
}
fn prepareBody(s: *h.Scope) !void {
    const engine = s.engine;
    engine.native_io = std.testing.io;
    const native = try v.own(s, try bus.exports(engine));
    const repeated = try v.own(s, try bus.exports(engine));
    try std.testing.expect(v.equal(s, native, repeated));
    const events = engine.native_module_values.get("node:events") orelse return error.ActualNodeEventEmitterRequired;
    const emitter = try v.get(s, events, "EventEmitter");
    const factory = try v.own(s, try engine.eval(
        @embedFile("extensions/fixtures/sdk-event-bus-c268-source.mjs"),
        "actual-c268-event-bus-factory.js", c.JS_EVAL_TYPE_GLOBAL));
    const reference = try v.call(s, factory, c.pi_js_undefined(), &.{emitter});
    try publish(s, "eventBusNative", try v.get(s, native, "createEventBus"));
    try publish(s, "eventBusSource", try v.get(s, reference, "createEventBus"));
    try publish(s, "eventBusEmitter", emitter);
    try publish(s, "eventBusHooks", try v.own(s, try retirement.createNativeRetirementHooks(engine)));
    try publish(s, "eventBusIsAsync", try v.own(s, try engine.checked(
        c.JS_NewCFunction(engine.context, asyncBrand, "eventBusIsAsync", 1))));
}
fn run(engine: *h.Engine, source: []const u8) !void {
    engine.freeValue(try engine.evalModule(source, "actual-sdk-event-bus-control.mjs"));
}
fn clean(engine: *h.Engine) !void {
    try std.testing.expect(!c.JS_HasException(engine.context));
    try std.testing.expect(!c.JS_IsJobPending(engine.runtime));
    try std.testing.expect(engine.native_fatal_invocation == null);
    try std.testing.expectEqual(@as(usize, 0), engine.native_exception_diagnostics_suppressed);
}
fn both(comptime name: []const u8, comptime argument: []const u8) !void {
    inline for (.{ "eventBusSource", "eventBusNative" }) |subject| {
        const engine = try h.Engine.init(std.testing.allocator, .{ .interrupt_budget = 2_000_000 });
        defer engine.deinit(); try prepare(engine);
        try run(engine, observer ++ "\nawait " ++ name ++ "(" ++ subject ++ ",eventBusEmitter,eventBusHooks" ++ argument ++ ");\n");
        try clean(engine);
    }
}
fn record(engine: *h.Engine) !c.JSValue {
    return h.expression(engine, recordBody, .{});
}
fn recordBody(s: *h.Scope) !c.JSValue {
    return v.duplicate(s, try v.get(s, try v.global(s, "eventBusHooks"), "record"));
}
test "SDK EventBus actual ordinary factory arrow shapes and retained emitter import" {
    try both("observeEventBusShapes", "");
}
test "SDK EventBus genuine EventEmitter dispatch unsubscribe and clear" {
    try both("observeEventBusDispatch", "");
}
test "SDK EventBus live emitter methods discard or transfer their actual results" {
    try both("observeEventBusLiveMethods", "");
}
test "SDK EventBus intrinsic async Await retains the actual unused argument until terminal" {
    try both("observeEventBusAwait", "");
}
test "SDK EventBus synchronous handler failure enters ordinary catch before returning" {
    try both("observeEventBusCatch", ",false");
}
test "SDK EventBus genuine awaited rejection enters the same live ordinary catch" {
    try both("observeEventBusCatch", ",true");
}
test "SDK EventBus logger failure is the real rejection before and after Await" {
    try both("observeEventBusLogFailure", ",false");
    try both("observeEventBusLogFailure", ",true");
}
test "SDK EventBus error template uses intrinsic eager string conversion after logger lookup" {
    try both("observeEventBusTemplates", "");
}
test "SDK EventBus same-operation private DATA stays ordinary before Await" {
    try both("observeEventBusPrivateData", ",false");
}
test "SDK EventBus private DATA stays an ordinary rejected Await reason" {
    try both("observeEventBusPrivateData", ",true");
}
test "SDK EventBus actual current B prevents catch logging and guest rejection handling" {
    const engine = try h.Engine.init(std.testing.allocator, .{}); defer engine.deinit(); try prepare(engine);
    const original = try record(engine); defer engine.freeValue(original);
    try std.testing.expectError(error.JavaScriptException, run(engine, observer ++
        "\nawait observeEventBusCurrentFatal(eventBusNative,eventBusEmitter,eventBusHooks);"));
    try retirement.verifyRecordedActualNativeFatal(engine, original);
    try retirement.verifyNoVisits(original, .{1,2});
    try std.testing.expect(engine.native_fatal_invocation == null);
}
test "SDK EventBus actual post-Await B stops template conversion and logger call" {
    const engine = try h.Engine.init(std.testing.allocator, .{}); defer engine.deinit(); try prepare(engine);
    const original = try record(engine); defer engine.freeValue(original);
    try std.testing.expectError(error.JavaScriptException, run(engine, observer ++
        "\nawait observeEventBusAfterAwaitFatal(eventBusNative,eventBusEmitter,eventBusHooks);"));
    try retirement.verifyRecordedActualNativeFatal(engine, original);
    try retirement.verifyNoVisits(original, .{1,2});
    try std.testing.expect(engine.native_fatal_invocation == null);
}
test "SDK EventBus actual console receiver retirement B prevents ordinary completion" {
    const engine = try h.Engine.init(std.testing.allocator, .{}); defer engine.deinit(); try prepare(engine);
    const original = try record(engine); defer engine.freeValue(original);
    try std.testing.expectError(error.JavaScriptException, run(engine, observer ++
        "\nawait observeEventBusCleanupFailure(eventBusNative,eventBusEmitter,eventBusHooks,false);"));
    try retirement.verifyActualRetirementFatal(engine, original, 0);
    try retirement.verifyNoVisits(original, .{1,2});
    try std.testing.expect(engine.native_fatal_invocation == null);
}
test "SDK EventBus actual console receiver retirement cancellation prevents guest continuation" {
    const engine = try h.Engine.init(std.testing.allocator, .{}); defer engine.deinit(); try prepare(engine);
    const original = try record(engine); defer engine.freeValue(original);
    try std.testing.expectError(error.JavaScriptException, run(engine, observer ++
        "\nawait observeEventBusCleanupFailure(eventBusNative,eventBusEmitter,eventBusHooks,true);"));
    try retirement.verifyActualCancellationNoGuestClose(engine, original);
    try std.testing.expect(engine.native_fatal_invocation == null);
}
