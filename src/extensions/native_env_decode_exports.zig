//! Original public rangeDecoder and startsWithBom exports.
const js = @import("native_js_values.zig");
const h = @import("native_env_remote_helpers.zig");
const c = js.c;
fn invoke(engine: *js.Engine, args: []const c.JSValue, method: c_int) !c.JSValue {
    var scope: h.Scope = .{ .engine = engine };
    defer scope.deinit();
    if (method == 0) {
        const decoder = try scope.global("TextDecoder");
        const options = try scope.object();
        try scope.put(options, "ignoreBOM", c.pi_js_bool(engine.context, 1));
        const values = [_]c.JSValue{ try scope.text("utf-8"), options };
        return engine.checked(c.JS_CallConstructor(engine.context, decoder, values.len, @constCast(&values)));
    }
    inline for (.{ 0xef, 0xbb, 0xbf }, 0..) |expected, index| {
        const value = try scope.own(try engine.checked(c.JS_GetPropertyUint32(engine.context, h.arg(args, 0), index)));
        if (!scope.equal(value, c.JS_NewInt32(engine.context, expected))) return c.pi_js_bool(engine.context, 0);
    }
    return c.pi_js_bool(engine.context, 1);
}
fn dispatch(engine: *js.Engine, _: c.JSValue, args: []const c.JSValue, constants: []const c.JSValue) !c.JSValue {
    var method: i32 = undefined;
    if (c.JS_ToInt32(engine.context, &method, constants[0]) < 0) return js.capture(engine);
    return invoke(engine, args, method);
}
pub fn install(engine: *js.Engine, exports: c.JSValue) !void {
    if (engine.text_decoder_class == 0) try @import("text_decoder.zig").install(engine);
    inline for (.{ .{ "rangeDecoder", 0 }, .{ "startsWithBom", 1 } }) |entry| {
        const function = try @import("native_node_function.zig").create(engine, entry[0], entry[1], dispatch, &.{c.JS_NewInt32(engine.context, entry[1])});
        if (c.JS_DefinePropertyValueStr(engine.context, exports, entry[0], function, c.JS_PROP_C_W_E) < 0) return js.capture(engine);
    }
}
