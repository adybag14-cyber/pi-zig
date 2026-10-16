//! Genuine shared Web dependency bootstrap. There is no replacement Request or
//! Response object here: each native facade owns its actual constructor.
const em = @import("engine.zig");
const js = @import("native_js_values.zig");
const Scope = @import("native_models_stream_scope.zig").Scope;
const idl = @import("native_web_idl.zig");
const body = @import("native_web_body.zig");
const streams = @import("native_readable_stream.zig");
const c = em.c;
const cache_key = "\x00native-web-Platform";
fn disturbed(scope: *Scope, _: c.JSValue, stream: c.JSValue) anyerror!bool {
    return streams.isDisturbed(scope.engine, stream);
}
fn errored(scope: *Scope, _: c.JSValue, stream: c.JSValue) anyerror!bool {
    return streams.isErrored(scope.engine, stream);
}
fn close(scope: *Scope, _: c.JSValue, controller: c.JSValue) anyerror!void {
    return streams.closeController(scope.engine, controller);
}
fn fromBytes(engine: *em.Engine, _: c.JSValue, bytes: c.JSValue) anyerror!c.JSValue {
    return streams.fromBytes(engine, bytes);
}
/// Returned constructor references are Scope-owned. Native facade owners
/// duplicate/mark their captures and never substitute fake missing classes.
pub fn prepare(scope: *Scope) !idl.Interfaces {
    const engine = scope.engine;
    if (engine.native_module_values.get(cache_key)) |cached| return fromCache(scope, cached);
    if (engine.url_class == 0) try @import("native_url.zig").install(engine);
    if (engine.abort_signal_class == 0) try @import("abort_signal.zig").install(engine);
    try @import("native_headers.zig").install(engine);
    try @import("native_web_blob.zig").install(engine);
    try @import("native_web_form_data.zig").install(engine);
    try streams.install(engine);
    const retained = engine.native_readable_stream_bindings orelse return error.NativeWebReadableStreamUnavailable;
    const constructor = try scope.get(retained, "fileHandleReadableStream");
    try body.install(engine, .{ .bindings = retained, .constructor = constructor, .is_disturbed = disturbed, .is_errored = errored, .close_controller = close });
    try @import("native_web_blob.zig").bindStreams(engine, .{ .owner = retained, .create = fromBytes });
    const cached = try scope.object();
    const symbol = try scope.get(try scope.global("Symbol"), "hasInstance");
    try scope.put(cached, "has_instance", try scope.own(try js.getKey(engine, try scope.get(try scope.global("Function"), "prototype"), symbol)));
    try scope.put(cached, "readable", constructor);
    try scope.put(cached, "blob", try scope.global("Blob"));
    try scope.put(cached, "form_data", try scope.global("FormData"));
    try scope.put(cached, "url_params", try scope.global("URLSearchParams"));
    try scope.put(cached, "abort_signal", try scope.global("AbortSignal"));
    // Request may legitimately be absent during the independent Response
    // bootstrap. The actual Request installer commits its real constructor.
    try scope.put(cached, "request", try scope.global("Request"));
    try engine.native_module_values.ensureUnusedCapacity(engine.gpa, 1);
    engine.native_module_values.putAssumeCapacity(cache_key, c.JS_DupValue(engine.context, cached));
    return fromCache(scope, cached);
}
fn fromCache(scope: *Scope, cached: c.JSValue) !idl.Interfaces {
    return .{ .has_instance = try scope.get(cached, "has_instance"), .readable = try scope.get(cached, "readable"), .blob = try scope.get(cached, "blob"), .form_data = try scope.get(cached, "form_data"), .url_params = try scope.get(cached, "url_params"), .abort_signal = try scope.get(cached, "abort_signal"), .request = try scope.get(cached, "request") };
}
pub fn setRequest(engine: *em.Engine, constructor: c.JSValue) !void {
    if (!c.JS_IsFunction(engine.context, constructor) or !c.JS_IsConstructor(engine.context, constructor)) return error.NativeWebRequestConstructorRequired;
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const cached = engine.native_module_values.get(cache_key) orelse return error.NativeWebPlatformUnavailable;
    try scope.set(cached, "request", constructor);
}
