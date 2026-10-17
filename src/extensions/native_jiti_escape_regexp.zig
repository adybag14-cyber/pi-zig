//! Actual escape-string-regexp5.0.0, used by pinned jiti2.7. Two real fresh
//! regex literals and live replace methods; no UTF8 regexp-escape approximation.
//! MIT, Copyright Sindre Sorhus (retained primary license).
const v = @import("native_ai_provider_values.zig");
const c = v.c;
const functions = @import("native_node_module_callable.zig");
pub fn create(engine: *v.em.Engine) !c.JSValue {
    return functions.create(engine, "escapeStringRegexp", 1, true, invoke, &.{});
}
fn invoke(engine: *v.em.Engine, _: c.JSValue, args: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
    return escape(engine, if (args.len > 0) args[0] else c.pi_js_undefined());
}
fn literal(engine: *v.em.Engine, pattern: [*:0]const u8) !c.JSValue {
    const text = try engine.checked(c.JS_NewString(engine.context, pattern)); defer engine.freeValue(text);
    const flags = try engine.checked(c.JS_NewString(engine.context, "g")); defer engine.freeValue(flags);
    var arguments = [_]c.JSValue{ text, flags };
    return engine.checked(c.JS_CallConstructor(engine.context, engine.intrinsic_regexp_constructor, 2, &arguments));
}
fn replace(engine: *v.em.Engine, receiver: c.JSValue, pattern: [*:0]const u8, replacement: [*:0]const u8) !c.JSValue {
    // Source reads receiver.replace before creating the literal argument.
    const method = try v.js.get(engine, receiver, "replace"); defer engine.freeValue(method);
    const expression = try literal(engine, pattern); defer engine.freeValue(expression);
    const text = try engine.checked(c.JS_NewString(engine.context, replacement)); defer engine.freeValue(text);
    return v.js.call(engine, method, receiver, &.{ expression, text });
}
pub fn escape(engine: *v.em.Engine, value: c.JSValue) !c.JSValue {
    engine.native_exception_diagnostics_suppressed += 1;
    defer engine.native_exception_diagnostics_suppressed -= 1;
    if (!c.JS_IsString(value)) {
        const constructor = try v.js.global(engine, "TypeError"); defer engine.freeValue(constructor);
        const text = try engine.checked(c.JS_NewString(engine.context, "Expected a string")); defer engine.freeValue(text);
        var arguments = [_]c.JSValue{text};
        const reason = try engine.checked(c.JS_CallConstructor(engine.context, constructor, 1, &arguments));
        return engine.checked(c.JS_Throw(engine.context, reason));
    }
    const first = try replace(engine, value, "[|\\\\{}()[\\]^$+*?.]", "\\$&"); defer engine.freeValue(first);
    return replace(engine, first, "-", "\\x2d");
}
