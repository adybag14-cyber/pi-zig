//! Source state.ts shared value, error and asynchronous reporting operations.
pub const h = @import("native_chord_host_values.zig");
pub const js = h.js;
pub const c = h.c;
pub const Scope = h.Scope;
pub fn binary(s: *Scope, op: c_int, a: c.JSValue, b: c.JSValue) !c.JSValue {
    return s.keep(try s.engine.checked(c.JS_PiBinaryOperator(s.engine.context, op, a, b)));
}
pub fn promiseLike(s: *Scope, value: c.JSValue) !bool {
    return c.JS_IsObject(value) and c.JS_IsFunction(s.engine.context, try s.get(value, "then"));
}
pub fn toError(s: *Scope, value: c.JSValue) !c.JSValue {
    const error_type = try s.keep(try js.global(s.engine, "Error"));
    const instance = c.JS_IsInstanceOf(s.engine.context, value, error_type);
    if (instance < 0) return js.capture(s.engine);
    if (instance != 0) return value;
    const constructor = try s.keep(try js.global(s.engine, "Error"));
    const text = try s.keep(try js.call(s.engine, try s.keep(try js.global(s.engine, "String")), c.pi_js_undefined(), &.{value}));
    return s.keep(try s.engine.checked(c.JS_CallConstructor(s.engine.context, constructor, 1, @constCast(@as([]const c.JSValue, &.{text}).ptr))));
}
fn throwLater(ctx: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue, _: c_int, captures: [*c]c.JSValue) callconv(.c) c.JSValue {
    return c.JS_Throw(ctx, c.JS_DupValue(ctx, captures[0]));
}
pub fn reportAsync(s: *Scope, value: c.JSValue) !void {
    var captures = [_]c.JSValue{value};
    const callback = try s.keep(try s.engine.checked(c.JS_NewCFunctionData2(s.engine.context, throwLater, "", 0, 0, 1, &captures)));
    _ = try s.keep(try js.call(s.engine, try s.keep(try js.global(s.engine, "queueMicrotask")), c.pi_js_undefined(), &.{callback}));
}
pub fn report(s: *Scope, receiver: c.JSValue, reporter: c.JSValue, value: c.JSValue) !void {
    const generation = s.engine.native_allocation_generation;
    const result = js.call(s.engine, reporter, receiver, &.{try toError(s, value)}) catch |err| {
        const mapped = s.engine.nativeAllocationError(err, generation);
        if (mapped != error.JavaScriptException) return mapped;
        try reportAsync(s, try toError(s, s.engine.captured_exception orelse return err));
        return;
    };
    s.engine.freeValue(result);
}
pub fn own(s: *Scope, receiver: c.JSValue, bindings: c.JSValue, kind: h.Kind) !c.JSValue {
    return (try h.actor(s, receiver, bindings, kind)).data;
}
