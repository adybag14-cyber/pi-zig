//! Source TuiBase field initialization after the genuine Container constructor.
//! This module is a source-only draft until the complete screen classes qualify.
const js = @import("native_js_values.zig");
const c = js.c;
const v = @import("native_select_list.zig");
fn emptySet(engine: *js.Engine) !c.JSValue {
    const constructor = try js.global(engine, "Set");
    defer engine.freeValue(constructor);
    return engine.checked(c.JS_CallConstructor(engine.context, constructor, 0, null));
}
pub fn initialize(engine: *js.Engine, receiver: c.JSValue, args: []const c.JSValue) !void {
    // Source class field definitions create these own writable enumerable
    // properties before its constructor assignments. Keep the observed order.
    try js.define(engine, receiver, "terminal", c.pi_js_undefined());
    try js.define(engine, receiver, "focusedComponent", c.pi_js_null());
    try js.define(engine, receiver, "inputListeners", try emptySet(engine));
    try js.define(engine, receiver, "onDebug", c.pi_js_undefined());
    try js.define(engine, receiver, "renderRequested", c.pi_js_bool(engine.context, 0));
    try js.define(engine, receiver, "immediateRenderScheduled", c.pi_js_bool(engine.context, 0));
    try js.define(engine, receiver, "renderTimer", c.pi_js_undefined());
    try js.define(engine, receiver, "lastRenderAt", c.JS_NewInt32(engine.context, 0));
    try js.define(engine, receiver, "showHardwareCursor", c.pi_js_bool(engine.context, 0));
    try js.define(engine, receiver, "clearOnShrink", c.pi_js_bool(engine.context, 0));
    try js.define(engine, receiver, "fullRedrawCount", c.JS_NewInt32(engine.context, 0));
    try js.define(engine, receiver, "stopped", c.pi_js_bool(engine.context, 0));
    try js.define(engine, receiver, "pendingTerminalColorQueries", try js.array(engine));
    try js.define(engine, receiver, "terminalColorSchemeListeners", try emptySet(engine));
    try js.define(engine, receiver, "terminalColorSchemeNotificationsEnabled", c.pi_js_bool(engine.context, 0));
    try js.define(engine, receiver, "logDirectory", c.pi_js_undefined());
    try js.define(engine, receiver, "focusOrderCounter", c.JS_NewInt32(engine.context, 0));
    try js.define(engine, receiver, "overlayStack", try js.array(engine));
    try js.define(engine, receiver, "renderedOverlayLayouts", try js.array(engine));
    const restore = try inactiveRestore(engine);
    defer engine.freeValue(restore);
    try js.define(engine, receiver, "overlayFocusRestore", c.JS_DupValue(engine.context, restore));
    try v.set(engine, receiver, "terminal", c.JS_DupValue(engine.context, v.arg(args, 0)));
    try v.set(engine, receiver, "logDirectory", c.JS_DupValue(engine.context, v.arg(args, 2)));
    if (!c.JS_IsUndefined(v.arg(args, 1))) try v.set(engine, receiver, "showHardwareCursor", c.JS_DupValue(engine.context, v.arg(args, 1)));
}
pub fn inactiveRestore(engine: *js.Engine) !c.JSValue {
    const value = try js.object(engine);
    errdefer engine.freeValue(value);
    try js.define(engine, value, "status", try v.text(engine, "inactive"));
    return value;
}
