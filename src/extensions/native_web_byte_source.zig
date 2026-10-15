//! Native HTTP byte-event iterator to the genuine shared ReadableStream graph.
//! The source callbacks own demand/cancellation; they do not implement streams.
const em = @import("engine.zig");
const js = @import("native_js_values.zig");
const Scope = @import("native_models_stream_scope.zig").Scope;
const body = @import("native_web_body.zig");
const c = em.c;
pub const Options = struct { cancel: ?c.JSValue = null, signal: ?c.JSValue = null };
fn cleanup(scope: *Scope, state: c.JSValue) !void {
    const signal = try scope.get(state, "signal");
    const listener = try scope.get(state, "listener");
    if (!c.JS_IsUndefined(signal) and !c.JS_IsNull(signal) and !c.JS_IsUndefined(listener)) _ = try scope.invoke(signal, "removeEventListener", &.{ try scope.text("abort"), listener });
    try scope.set(state, "listener", c.pi_js_undefined());
    try scope.set(state, "signal", c.pi_js_undefined());
}
fn invokeCancel(scope: *Scope, state: c.JSValue, reason: c.JSValue) !c.JSValue {
    const callback = try scope.get(state, "cancel");
    return if (c.JS_IsFunction(scope.engine.context, callback)) scope.call(callback, c.pi_js_undefined(), &.{reason}) else c.pi_js_undefined();
}
fn start(engine: *em.Engine, _: c.JSValue, args: []const c.JSValue, captures: []const c.JSValue) anyerror!c.JSValue {
    engine.native_exception_diagnostics_suppressed += 1;
    defer engine.native_exception_diagnostics_suppressed -= 1;
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    try scope.set(captures[0], "controller", if (args.len > 0) args[0] else c.pi_js_undefined());
    return c.pi_js_undefined();
}
fn cancel(engine: *em.Engine, _: c.JSValue, args: []const c.JSValue, captures: []const c.JSValue) anyerror!c.JSValue {
    engine.native_exception_diagnostics_suppressed += 1;
    defer engine.native_exception_diagnostics_suppressed -= 1;
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const state = captures[0];
    try scope.set(state, "done", c.JS_NewBool(engine.context, true));
    try cleanup(&scope, state);
    return c.JS_DupValue(engine.context, try invokeCancel(&scope, state, if (args.len > 0) args[0] else c.pi_js_undefined()));
}
fn rejected(engine: *em.Engine, _: c.JSValue, args: []const c.JSValue, captures: []const c.JSValue) anyerror!c.JSValue {
    engine.native_exception_diagnostics_suppressed += 1;
    defer engine.native_exception_diagnostics_suppressed -= 1;
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    try scope.set(captures[0], "done", c.JS_NewBool(engine.context, true));
    try cleanup(&scope, captures[0]);
    _ = try engine.checked(c.JS_Throw(engine.context, c.JS_DupValue(engine.context, if (args.len > 0) args[0] else c.pi_js_undefined())));
    unreachable;
}
fn fulfilled(engine: *em.Engine, _: c.JSValue, args: []const c.JSValue, captures: []const c.JSValue) anyerror!c.JSValue {
    engine.native_exception_diagnostics_suppressed += 1;
    defer engine.native_exception_diagnostics_suppressed -= 1;
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const state = captures[0];
    if (scope.truthy(try scope.get(state, "done"))) return c.pi_js_undefined();
    const row = if (args.len > 0) args[0] else c.pi_js_undefined();
    const controller = try scope.get(state, "controller");
    if (scope.truthy(try scope.get(row, "done"))) {
        try scope.set(state, "done", c.JS_NewBool(engine.context, true));
        try cleanup(&scope, state);
        try body.closeController(&scope, controller);
        return c.pi_js_undefined();
    }
    const event = try scope.get(row, "value");
    if (!scope.equal(try scope.get(event, "type"), try scope.text("bytes"))) return error.NativeWebByteEventProtocolMismatch;
    const bytes = try scope.get(event, "data");
    if (c.JS_GetTypedArrayType(bytes) != c.JS_TYPED_ARRAY_UINT8) return error.NativeWebByteEventBrandMismatch;
    var size: usize = 0;
    if (c.JS_GetUint8Array(engine.context, &size, bytes) == null and c.JS_HasException(engine.context)) return js.capture(engine);
    if (size == 0) return pull(engine, c.pi_js_undefined(), &.{controller}, captures);
    _ = try scope.invoke(controller, "enqueue", &.{bytes});
    return c.pi_js_undefined();
}
fn pull(engine: *em.Engine, _: c.JSValue, _: []const c.JSValue, captures: []const c.JSValue) anyerror!c.JSValue {
    engine.native_exception_diagnostics_suppressed += 1;
    defer engine.native_exception_diagnostics_suppressed -= 1;
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const state = captures[0];
    if (scope.truthy(try scope.get(state, "done"))) return c.pi_js_undefined();
    const next = scope.invoke(try scope.get(state, "iterator"), "next", &.{}) catch |err| {
        try cleanup(&scope, state);
        return err;
    };
    const yes = try scope.own(try @import("native_node_function.zig").createArrow(engine, "", 1, fulfilled, &.{state}));
    const no = try scope.own(try @import("native_node_function.zig").createArrow(engine, "", 1, rejected, &.{state}));
    return c.JS_DupValue(engine.context, try scope.invoke(next, "then", &.{ yes, no }));
}
fn abort(engine: *em.Engine, _: c.JSValue, _: []const c.JSValue, captures: []const c.JSValue) anyerror!c.JSValue {
    engine.native_exception_diagnostics_suppressed += 1;
    defer engine.native_exception_diagnostics_suppressed -= 1;
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const state = captures[0];
    if (scope.truthy(try scope.get(state, "done"))) return c.pi_js_undefined();
    const reason = try scope.get(try scope.get(state, "signal"), "reason");
    try scope.set(state, "done", c.JS_NewBool(engine.context, true));
    try cleanup(&scope, state);
    _ = try scope.invoke(try scope.get(state, "controller"), "error", &.{reason});
    // The original abort reason has already reached the actual stream. Native
    // cancellation cannot replace it with another rejection or diagnostic.
    const canceled = invokeCancel(&scope, state, reason) catch |err| {
        if (err == error.OutOfMemory) return err;
        if (engine.captured_exception) |exception| {
            engine.captured_exception = null;
            engine.freeValue(exception);
        }
        return c.pi_js_undefined();
    };
    if (c.JS_PromiseState(engine.context, canceled) >= 0) c.JS_PromiseMarkAsHandled(engine.context, canceled);
    return c.pi_js_undefined();
}
/// Returns an owned real stream. Existing provider framing is not accepted as
/// bytes: callers must opt into raw_header_pairs/all-status stream_error_bytes.
pub fn fromEvents(engine: *em.Engine, iterator: c.JSValue, options: Options) !c.JSValue {
    try body.require(engine);
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const state = try scope.object();
    try scope.set(state, "iterator", iterator);
    try scope.set(state, "cancel", options.cancel orelse c.pi_js_undefined());
    try scope.set(state, "signal", options.signal orelse c.pi_js_undefined());
    try scope.set(state, "listener", c.pi_js_undefined());
    try scope.set(state, "done", c.JS_NewBool(engine.context, false));
    const source = try scope.object();
    inline for (.{ .{ "start", 1, start }, .{ "pull", 1, pull }, .{ "cancel", 1, cancel } }) |spec| try scope.set(source, spec[0], try scope.own(try @import("native_node_function.zig").createArrow(engine, spec[0], spec[1], spec[2], &.{state})));
    try scope.set(source, "type", try scope.text("bytes"));
    var args = [_]c.JSValue{source};
    const stream = try scope.own(try engine.checked(c.JS_CallConstructor(engine.context, try body.streamConstructor(&scope), 1, &args)));
    if (options.signal) |signal| if (!c.JS_IsUndefined(signal) and !c.JS_IsNull(signal)) {
        const listener = try scope.own(try @import("native_node_function.zig").createArrow(engine, "", 0, abort, &.{state}));
        try scope.set(state, "listener", listener);
        if (scope.truthy(try scope.get(signal, "aborted"))) _ = try abort(engine, c.pi_js_undefined(), &.{}, &.{state}) else {
            const once = try scope.object();
            try scope.set(once, "once", c.JS_NewBool(engine.context, true));
            _ = try scope.invoke(signal, "addEventListener", &.{ try scope.text("abort"), listener, once });
        }
    };
    return c.JS_DupValue(engine.context, stream);
}
