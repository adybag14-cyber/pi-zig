//! Local owner-thread operations: success with a pending guest event is failure.
//! No shared Engine/Scope policy changes. All returned values enter Scope once.
const v = @import("native_ai_provider_values.zig");
pub const c = v.c;
pub const Scope = v.Scope;
pub fn pending(engine: *v.em.Engine) !void {
    if (c.JS_HasException(engine.context)) return v.js.capture(engine);
}
pub fn success(engine: *v.em.Engine, owned: c.JSValue) !c.JSValue {
    if (c.JS_HasException(engine.context)) {
        const reason = c.JS_GetException(engine.context);
        engine.freeValue(owned);
        return engine.checked(c.JS_Throw(engine.context, reason));
    }
    return owned;
}
pub fn get(s: *Scope, receiver: c.JSValue, name: [*:0]const u8) !c.JSValue {
    return s.own(try success(s.engine, try v.js.get(s.engine, receiver, name)));
}
pub fn call(s: *Scope, function: c.JSValue, receiver: c.JSValue, args: []const c.JSValue) !c.JSValue {
    return s.own(try success(s.engine, try v.js.call(s.engine, function, receiver, args)));
}
pub fn invoke(s: *Scope, receiver: c.JSValue, name: [*:0]const u8, args: []const c.JSValue) !c.JSValue {
    return call(s, try get(s, receiver, name), receiver, args);
}
pub fn put(engine: *v.em.Engine, target: c.JSValue, name: [*:0]const u8, value: c.JSValue) !void {
    if (c.JS_DefinePropertyValueStr(engine.context, target, name, c.JS_DupValue(engine.context, value), c.JS_PROP_C_W_E | c.JS_PROP_THROW) < 0) return v.js.capture(engine);
    try pending(engine);
}
pub fn set(s: *Scope, target: c.JSValue, name: [*:0]const u8, value: c.JSValue) !void {
    try s.set(target, name, value);
    try pending(s.engine);
}
pub fn arg(args: []const c.JSValue, index: usize) c.JSValue {
    return if (index < args.len) args[index] else c.pi_js_undefined();
}
/// Normalize arithmetic's actual pending event before Scope can allocate its
/// overflow root array. Coercion may invoke a real host callback.
pub fn binary(s: *Scope, operation: @import("native_image_arithmetic.zig").Operation, left: c.JSValue, right: c.JSValue) !c.JSValue {
    return s.own(try success(s.engine, try @import("native_image_arithmetic.zig").binary(s.engine, operation, left, right)));
}
pub fn same(s: *Scope, value: c.JSValue, text: []const u8) !bool {
    return s.equal(value, try s.text(text));
}
pub fn construct(s: *Scope, function: c.JSValue, args: []const c.JSValue) !c.JSValue {
    return s.own(try success(s.engine, try s.engine.checked(c.JS_CallConstructor(s.engine.context, function, @intCast(args.len), @constCast(args.ptr)))));
}
pub fn throwValue(engine: *v.em.Engine, reason: c.JSValue) anyerror {
    _ = engine.checked(c.JS_Throw(engine.context, c.JS_DupValue(engine.context, reason))) catch |err| return err;
    unreachable;
}
