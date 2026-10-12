//! Node-host JSON error behavior. Inner CodeMode VMs retain QuickJS JSON.
const js = @import("native_js_values.zig");
const c = js.c;
fn stringify(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue) callconv(.c) c.JSValue {
    return c.JS_PiJSONStringifyNode(context, if (argc > 0) argv[0] else c.pi_js_undefined(), if (argc > 1) argv[1] else c.pi_js_undefined(), if (argc > 2) argv[2] else c.pi_js_undefined());
}
pub fn install(engine: *js.Engine) !void {
    const json = try js.global(engine, "JSON");
    defer engine.freeValue(json);
    const function = try engine.checked(c.JS_NewCFunction(engine.context, stringify, "stringify", 3));
    if (c.JS_DefinePropertyValueStr(engine.context, json, "stringify", function, c.JS_PROP_CONFIGURABLE | c.JS_PROP_WRITABLE) < 0) return js.capture(engine);
}
