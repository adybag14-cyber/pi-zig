//! Explicit Node-host numeric diagnostics. Inner VMs retain original BigInt.
const js = @import("native_js_values.zig");
const c = js.c;
fn bigint(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue) callconv(.c) c.JSValue {
    return c.JS_PiBigIntNode(context, if (argc > 0) argv[0] else c.pi_js_undefined());
}
pub fn install(engine: *js.Engine) !void {
    const original = try js.global(engine, "BigInt");
    defer engine.freeValue(original);
    const replacement = try engine.checked(c.JS_NewCFunction(engine.context, bigint, "BigInt", 1));
    defer engine.freeValue(replacement);
    inline for (.{ "prototype", "asIntN", "asUintN" }) |name| {
        const atom = c.JS_NewAtom(engine.context, name);
        if (atom == c.JS_ATOM_NULL) return error.OutOfMemory;
        defer c.JS_FreeAtom(engine.context, atom);
        var descriptor: c.JSPropertyDescriptor = undefined;
        const found = c.JS_GetOwnProperty(engine.context, &descriptor, original, atom);
        if (found < 0) return js.capture(engine);
        if (found == 0) return error.NativeBigIntPropertyMissing;
        defer engine.freeValue(descriptor.value);
        defer engine.freeValue(descriptor.getter);
        defer engine.freeValue(descriptor.setter);
        if (c.JS_DefineProperty(engine.context, replacement, atom, descriptor.value, descriptor.getter, descriptor.setter, descriptor.flags | c.JS_PROP_HAS_VALUE | c.JS_PROP_HAS_WRITABLE | c.JS_PROP_HAS_ENUMERABLE | c.JS_PROP_HAS_CONFIGURABLE) < 0) return js.capture(engine);
    }
    const prototype = try js.get(engine, replacement, "prototype");
    defer engine.freeValue(prototype);
    if (c.JS_DefinePropertyValueStr(engine.context, prototype, "constructor", c.JS_DupValue(engine.context, replacement), c.JS_PROP_WRITABLE | c.JS_PROP_CONFIGURABLE) < 0) return js.capture(engine);
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    if (c.JS_SetPropertyStr(engine.context, global, "BigInt", c.JS_DupValue(engine.context, replacement)) < 0) return js.capture(engine);
}
