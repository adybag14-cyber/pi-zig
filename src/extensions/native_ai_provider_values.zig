//! Shared owner-thread value operations for actual native provider algorithms.
pub const em = @import("engine.zig");
pub const js = @import("native_js_values.zig");
pub const Scope = @import("native_models_stream_scope.zig").Scope;
pub const c = em.c;
pub fn eq(scope: *Scope, value: c.JSValue, expected: []const u8) !bool {
    return scope.equal(value, try scope.text(expected));
}
pub fn at(scope: *Scope, value: c.JSValue, index: u32) !c.JSValue {
    return scope.own(try scope.engine.checked(c.JS_GetPropertyUint32(scope.engine.context, value, index)));
}
pub fn optional(scope: *Scope, value: c.JSValue, key: [*:0]const u8) !c.JSValue {
    return if (nullish(value)) c.pi_js_undefined() else scope.get(value, key);
}
pub fn nullish(value: c.JSValue) bool {
    return c.JS_IsNull(value) or c.JS_IsUndefined(value);
}
pub fn array(scope: *Scope, value: c.JSValue) !bool {
    return scope.truthy(try scope.invoke(try scope.global("Array"), "isArray", &.{value}));
}
pub fn length(scope: *Scope, value: c.JSValue) !u32 {
    var count: u32 = 0;
    if (c.JS_ToUint32(scope.engine.context, &count, try scope.get(value, "length")) < 0) return js.capture(scope.engine);
    return count;
}
pub fn iterator(scope: *Scope, value: c.JSValue) !js.Iterator {
    return js.Iterator.init(scope.engine, value, try scope.own(try scope.engine.checked(c.JS_GetIteratorSymbol(scope.engine.context))));
}
pub fn spread(scope: *Scope, value: c.JSValue) !c.JSValue {
    return scope.own(try js.spread(scope.engine, value));
}
pub fn sanitize(scope: *Scope, text: c.JSValue) !c.JSValue {
    var regex_args = [_]c.JSValue{ try scope.text("[\\uD800-\\uDBFF](?![\\uDC00-\\uDFFF])|(?<![\\uD800-\\uDBFF])[\\uDC00-\\uDFFF]"), try scope.text("g") };
    const regex = try scope.own(try scope.engine.checked(c.JS_CallConstructor(scope.engine.context, scope.engine.intrinsic_regexp_constructor, regex_args.len, &regex_args)));
    return scope.invoke(text, "replace", &.{ regex, try scope.text("") });
}
pub fn remove(scope: *Scope, value: c.JSValue, key: [*:0]const u8) !void {
    const atom = c.JS_NewAtom(scope.engine.context, key);
    if (atom == c.JS_ATOM_NULL) return js.capture(scope.engine);
    defer c.JS_FreeAtom(scope.engine.context, atom);
    if (c.JS_DeleteProperty(scope.engine.context, value, atom, c.JS_PROP_THROW) < 0) return js.capture(scope.engine);
}
pub fn errorText(scope: *Scope, text: c.JSValue) anyerror {
    const reason = scope.own(js.builtin(scope.engine, "Error", &.{text}) catch |err| return err) catch |err| return err;
    _ = scope.engine.checked(c.JS_Throw(scope.engine.context, c.JS_DupValue(scope.engine.context, reason))) catch |err| return err;
    unreachable;
}
