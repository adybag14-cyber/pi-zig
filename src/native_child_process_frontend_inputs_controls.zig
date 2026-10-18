//! Prepared actual-bootstrap controls. No replacement process, Stream, signal
//! namespace, pipe, descriptor, CJS require or completed child is manufactured.
//! Caller supplies the genuine already-initialized same-process native frontend.
const std = @import("std");
const js = @import("extensions/native_js_values.zig");
const c = js.c;
const factory = @import("extensions/native_child_process_frontend_inputs.zig");
const local = @import("extensions/native_node_socket_scope.zig");
const Frontend = @import("extensions/native_stdio_frontend.zig").Frontend;

pub fn actualGraph(engine: *js.Engine, frontend: *Frontend, host: factory.Host) anyerror!void {
    var owner = try factory.capture(engine, frontend, host);
    var live = true;
    defer if (live) owner.deinit() catch @panic("actual frontend input root retirement failed");
    const inputs = try owner.view(engine);
    var scope: local.Scope = .{ .engine = engine };
    defer scope.deinit();
    errdefer |err| scope.captureUnwind(err);
    try std.testing.expect(scope.equal(inputs.process, try scope.global("process")));
    const stream_record = engine.native_module_values.get("node:stream") orelse return error.RequiredActualControlStream;
    const actual_streams = try scope.get(stream_record, "default");
    try std.testing.expect(scope.equal(inputs.streams, actual_streams));
    const shared = try @import("extensions/native_node_net_socket_provider.zig").acquire(engine, actual_streams, inputs.process);
    try std.testing.expect(inputs.socket_provider.? == &shared.provider);
    try std.testing.expect(scope.equal(inputs.socket_provider.?.constructor, try scope.get(shared.net, "Socket")));
    const os_record = engine.native_module_values.get("node:os") orelse return error.RequiredActualControlOs;
    try std.testing.expect(scope.equal(inputs.signals, try scope.get(try scope.get(try scope.get(os_record, "default"), "constants"), "signals")));
    try std.testing.expect(inputs.stdio_source.?.generation == frontend.lease.?.generation);
    try std.testing.expect(inputs.stdio_source.?.context == frontend.lease.?.context);
    // A scalar stale-generation view must fail before any borrowed bridge use.
    const saved = owner.captured.source;
    owner.captured.source.generation +%= 1;
    const stale = owner.view(engine);
    owner.captured.source = saved;
    if (stale) |_| return error.NativeChildFrontendControlAcceptedStaleLease else |_| {}
    _ = try owner.view(engine);
    live = false;
    try owner.deinit();
    try std.testing.expectError(error.NativeChildFrontendInputsRetired, owner.view(engine));
}

pub fn actualIncomingPending(engine: *js.Engine, frontend: *Frontend, host: factory.Host) anyerror!void {
    // The genuine existing graph is passed unchanged; the actual event must
    // reject before module/getter/canonical/Hub/map/descriptor capture effects.
    const reason = try engine.checked(c.JS_NewObject(engine.context));
    defer engine.freeValue(reason);
    const old_env = engine.native_env_context;
    const old_diagnostics = engine.native_exception_diagnostics_suppressed;
    _ = c.JS_Throw(engine.context, c.JS_DupValue(engine.context, reason));
    try std.testing.expectError(error.JavaScriptException, factory.capture(engine, frontend, host));
    try std.testing.expect(engine.native_env_context == old_env);
    try std.testing.expect(engine.native_exception_diagnostics_suppressed == old_diagnostics);
    const actual = engine.captured_exception orelse return error.NativeChildFrontendControlLostPending;
    try std.testing.expect(c.JS_IsStrictEqual(engine.context, reason, actual));
    engine.captured_exception = null;
    engine.freeValue(actual);
}

pub fn actualAuthComposition(
    engine: *js.Engine,
    frontend: *Frontend,
    host: factory.Host,
    physical_config_url: c.JSValue,
) anyerror!void {
    // Only enabled when the separately reviewed real Auth owner is composed.
    // This invokes its actual inMemory factory, then genuine AuthStorage class.
    var inputs = try factory.capture(engine, frontend, host);
    defer inputs.deinit() catch @panic("actual frontend input cleanup failed");
    var auth = try @import("extensions/native_sdk_auth_runtime_owner.zig").create(engine, .{
        .frontend = try inputs.view(engine), .config_module_url = physical_config_url,
    });
    defer auth.deinit() catch @panic("actual Auth owner cleanup failed");
    const memory = try auth.inMemory();
    defer engine.freeValue(memory);
    try std.testing.expect(c.JS_IsObject(memory));
}

pub fn actualOwnedCompletionRetirement(engine: *js.Engine, frontend: *Frontend, host: factory.Host) anyerror!void {
    // Only the real already-bound graph is captured. A genuine ordinary A is
    // recorded BEFORE any temporary input root retires into SDK completion.
    var inputs = try factory.capture(engine, frontend, host);
    var live = true;
    defer if (live) inputs.deinit() catch @panic("actual completion control input cleanup failed");
    const reason = try engine.checked(c.JS_NewObject(engine.context));
    defer engine.freeValue(reason);
    _ = c.JS_Throw(engine.context, c.JS_DupValue(engine.context, reason));
    var completion = @import("extensions/native_sdk_owned_completion.zig").Completion.initVoid(engine, error.JavaScriptException);
    live = false;
    inputs.retireInto(&completion);
    try std.testing.expectError(error.JavaScriptException, completion.finishVoid());
    try std.testing.expectError(error.NativeChildFrontendInputsRetired, inputs.view(engine));
    const actual = engine.captured_exception orelse return error.NativeChildFrontendCompletionLostReason;
    try std.testing.expect(c.JS_IsStrictEqual(engine.context, actual, reason));
    engine.captured_exception = null;
    engine.freeValue(actual);
}
