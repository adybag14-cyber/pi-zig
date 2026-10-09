//! Generation error-overflow classifier uses actual Source pattern data.
const engine_mod = @import("engine.zig");
const vm = @import("native_values.zig");
const js = @import("native_js_values.zig");
const c = engine_mod.c;
const Engine = engine_mod.Engine;
fn matches(engine: *Engine, text: c.JSValue, pattern: []const u8) !bool {
    const source = try engine.checked(c.JS_NewStringLen(engine.context, pattern.ptr, pattern.len));
    defer engine.freeValue(source);
    const flags = try engine.checked(c.JS_NewString(engine.context, "i"));
    defer engine.freeValue(flags);
    var args = [_]c.JSValue{ source, flags };
    const regexp = try engine.checked(c.JS_CallConstructor(engine.context, engine.intrinsic_regexp_constructor, 2, &args));
    defer engine.freeValue(regexp);
    const result = try vm.invoke(engine, regexp, "test", &.{text});
    defer engine.freeValue(result);
    return c.JS_ToBool(engine.context, result) != 0;
}
pub fn errorOverflow(engine: *Engine, message: c.JSValue) !bool {
    const reason = try vm.get(engine, message, "stopReason");
    defer engine.freeValue(reason);
    const error_reason = try engine.checked(c.JS_NewString(engine.context, "error"));
    defer engine.freeValue(error_reason);
    if (!c.JS_IsStrictEqual(engine.context, reason, error_reason)) return false;
    const text = try vm.get(engine, message, "errorMessage");
    defer engine.freeValue(text);
    if (c.JS_ToBool(engine.context, text) == 0 or try matches(engine, text, @embedFile("nonoverflow-pattern.txt"))) return false;
    if (try matches(engine, text, @embedFile("overflow-pattern.txt"))) return true;
    const provider = try vm.get(engine, message, "provider");
    defer engine.freeValue(provider);
    const cerebras = try engine.checked(c.JS_NewString(engine.context, "cerebras"));
    defer engine.freeValue(cerebras);
    return c.JS_IsStrictEqual(engine.context, provider, cerebras) and try matches(engine, text, "^4(?:00|13)\\s*(?:status code)?\\s*\\(no body\\)");
}
