//! Source screen lifecycle and subscription closures. No SDK token is captured
//! by these plain class callbacks; retained capabilities keep their own guards.
const js = @import("native_js_values.zig");
const c = js.c;
const v = @import("native_select_list.zig");
pub const Method = enum { start, stop, addInputListener, removeInputListener, onTerminalColorSchemeChange, setTerminalColorSchemeNotifications };
const Callback = enum(c_int) { input, resize, removeInput, removeScheme };
fn fail(engine: *js.Engine, err: anyerror) c.JSValue {
    if (err == error.JavaScriptException) return engine.throwCaptured();
    if (err == error.OutOfMemory) return c.JS_ThrowOutOfMemory(engine.context);
    return c.JS_ThrowTypeError(engine.context, "Native TuiBase lifecycle: %s", @as([*:0]const u8, @errorName(err)));
}
fn makeCallback(engine: *js.Engine, kind: Callback, screen: c.JSValue, listener: c.JSValue) !c.JSValue {
    var data = [_]c.JSValue{ screen, listener };
    return engine.checked(c.JS_NewCFunctionData2(engine.context, callbackCall, "", if (kind == .input) 1 else 0, @intFromEnum(kind), 2, &data));
}
fn callbackCall(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, magic: c_int, data: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = js.Engine.fromContext(context.?);
    return callbackBody(engine, @enumFromInt(magic), data[0], data[1], if (argc > 0) argv[0] else c.pi_js_undefined()) catch |err| fail(engine, err);
}
fn callbackBody(engine: *js.Engine, kind: Callback, screen: c.JSValue, listener: c.JSValue, input: c.JSValue) !c.JSValue {
    switch (kind) {
        .input => return js.invoke(engine, screen, "handleTerminalInput", &.{input}),
        .resize => return js.invoke(engine, screen, "requestRender", &.{}),
        .removeInput, .removeScheme => {
            const listeners = try js.get(engine, screen, if (kind == .removeInput) "inputListeners" else "terminalColorSchemeListeners");
            defer engine.freeValue(listeners);
            try v.invokeVoid(engine, listeners, "delete", &.{listener});
            return c.pi_js_undefined();
        },
    }
}
fn terminalCall(engine: *js.Engine, screen: c.JSValue, method: [*:0]const u8, args: []const c.JSValue) !void {
    const terminal = try js.get(engine, screen, "terminal");
    defer engine.freeValue(terminal);
    try v.invokeVoid(engine, terminal, method, args);
}
fn notifications(engine: *js.Engine, screen: c.JSValue) !bool {
    const enabled = try js.get(engine, screen, "terminalColorSchemeNotificationsEnabled");
    defer engine.freeValue(enabled);
    return v.truthy(engine, enabled);
}
fn writeNotifications(engine: *js.Engine, screen: c.JSValue, enabled: bool) !void {
    const sequence = try v.text(engine, if (enabled) "\x1b[?2031h" else "\x1b[?2031l");
    defer engine.freeValue(sequence);
    try terminalCall(engine, screen, "write", &.{sequence});
}
pub fn invoke(engine: *js.Engine, screen: c.JSValue, method: Method, args: []const c.JSValue) !c.JSValue {
    switch (method) {
        .start => {
            try v.set(engine, screen, "stopped", c.pi_js_bool(engine.context, 0));
            try v.invokeVoid(engine, screen, "beforeTerminalStart", &.{});
            const terminal = try js.get(engine, screen, "terminal");
            defer engine.freeValue(terminal);
            const start = try js.get(engine, terminal, "start");
            defer engine.freeValue(start);
            const input = try makeCallback(engine, .input, screen, c.pi_js_undefined());
            defer engine.freeValue(input);
            const resize = try makeCallback(engine, .resize, screen, c.pi_js_undefined());
            defer engine.freeValue(resize);
            const started = try js.call(engine, start, terminal, &.{ input, resize });
            engine.freeValue(started);
            try v.invokeVoid(engine, screen, "afterTerminalStart", &.{});
            try terminalCall(engine, screen, "hideCursor", &.{});
            if (try notifications(engine, screen)) try writeNotifications(engine, screen, true);
            try v.invokeVoid(engine, screen, "queryCellSize", &.{});
            try v.invokeVoid(engine, screen, "requestRender", &.{});
        },
        .stop => {
            const options = if (c.JS_IsUndefined(v.arg(args, 0))) try js.object(engine) else c.JS_DupValue(engine.context, args[0]);
            defer engine.freeValue(options);
            try v.set(engine, screen, "stopped", c.pi_js_bool(engine.context, 1));
            try v.invokeVoid(engine, screen, "cancelRenderTimer", &.{});
            if (try notifications(engine, screen)) try writeNotifications(engine, screen, false);
            try v.invokeVoid(engine, screen, "beforeTerminalStop", &.{options});
            try terminalCall(engine, screen, "showCursor", &.{});
            try terminalCall(engine, screen, "stop", &.{});
            try v.invokeVoid(engine, screen, "afterTerminalStop", &.{options});
        },
        .addInputListener, .onTerminalColorSchemeChange => {
            const listeners = try js.get(engine, screen, if (method == .addInputListener) "inputListeners" else "terminalColorSchemeListeners");
            defer engine.freeValue(listeners);
            try v.invokeVoid(engine, listeners, "add", &.{v.arg(args, 0)});
            return makeCallback(engine, if (method == .addInputListener) .removeInput else .removeScheme, screen, v.arg(args, 0));
        },
        .removeInputListener => {
            const listeners = try js.get(engine, screen, "inputListeners");
            defer engine.freeValue(listeners);
            try v.invokeVoid(engine, listeners, "delete", &.{v.arg(args, 0)});
        },
        .setTerminalColorSchemeNotifications => {
            const enabled = v.arg(args, 0);
            const current = try js.get(engine, screen, "terminalColorSchemeNotificationsEnabled");
            defer engine.freeValue(current);
            if (c.JS_IsStrictEqual(engine.context, current, enabled)) return c.pi_js_undefined();
            try v.set(engine, screen, "terminalColorSchemeNotificationsEnabled", c.JS_DupValue(engine.context, enabled));
            const stopped = try js.get(engine, screen, "stopped");
            defer engine.freeValue(stopped);
            if (!v.truthy(engine, stopped)) try writeNotifications(engine, screen, v.truthy(engine, enabled));
        },
    }
    return c.pi_js_undefined();
}
