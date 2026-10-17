//! Consumed yoctocolors2.1.2 base.js exports. MIT, Sindre Sorhus.
//! Actual tty namespace and VM strings/methods; no inferred color capability.
const v = @import("native_ai_provider_values.zig");
const c = v.c;
const Scope = v.Scope;
const functions = @import("native_node_module_callable.zig");
fn put(engine: *v.em.Engine, object: c.JSValue, name: [*:0]const u8, value: c.JSValue) !void {
    if (c.JS_DefinePropertyValueStr(engine.context, object, name, c.JS_DupValue(engine.context, value), c.JS_PROP_C_W_E | c.JS_PROP_THROW) < 0) return v.js.capture(engine);
}
fn nil(value: c.JSValue) bool { return c.JS_IsNull(value) or c.JS_IsUndefined(value); }
fn initializationValue(engine: *v.em.Engine, owned: c.JSValue) !c.JSValue {
    if (c.JS_HasException(engine.context)) {
        // Capture the actual pending event BEFORE releasing guest success.
        // No input flag/name or historical diagnostic slot is classified.
        const pending_reason = c.JS_GetException(engine.context);
        engine.freeValue(owned);
        return engine.checked(c.JS_Throw(engine.context, pending_reason));
    }
    return owned;
}
fn initializationGet(s: *Scope, receiver: c.JSValue, name: [*:0]const u8) !c.JSValue {
    return s.own(try initializationValue(s.engine, try v.js.get(s.engine, receiver, name)));
}
fn colorsEnabled(s: *Scope, tty: c.JSValue) !c.JSValue {
    if (nil(tty)) return c.pi_js_bool(s.engine.context, 0);
    const stream = try initializationGet(s, tty, "WriteStream");
    if (nil(stream)) return c.pi_js_bool(s.engine.context, 0);
    const prototype = try initializationGet(s, stream, "prototype");
    if (nil(prototype)) return c.pi_js_bool(s.engine.context, 0);
    const function = try initializationGet(s, prototype, "hasColors");
    if (nil(function)) return c.pi_js_bool(s.engine.context, 0);
    const value = try s.own(try initializationValue(s.engine, try v.js.call(s.engine, function, prototype, &.{})));
    return if (nil(value)) c.pi_js_bool(s.engine.context, 0) else value;
}
/// Caller supplies the actual imported node:tty default namespace. Missing
/// optional links follow Source; fabricated hasColors metadata is not supplied.
pub fn create(engine: *v.em.Engine, actual_tty: c.JSValue) !c.JSValue {
    engine.native_exception_diagnostics_suppressed += 1;
    defer engine.native_exception_diagnostics_suppressed -= 1;
    if (c.JS_HasException(engine.context)) return v.js.capture(engine);
    var s: Scope = .{ .engine = engine }; defer s.deinit();
    const enabled = try colorsEnabled(&s, actual_tty);
    const result = try s.object();
    inline for (.{ .{ "red", "31" }, .{ "green", "32" }, .{ "yellow", "33" }, .{ "blue", "34" }, .{ "cyan", "36" }, .{ "gray", "90" } }) |entry| {
        const open = if (s.truthy(enabled)) try s.text("\x1b[" ++ entry[1] ++ "m") else c.pi_js_undefined();
        const close = if (s.truthy(enabled)) try s.text("\x1b[39m") else c.pi_js_undefined();
        const function = try s.own(try functions.create(engine, "", 1, false, format, &.{ enabled, open, close }));
        try put(engine, result, entry[0], function);
    }
    return c.JS_DupValue(engine.context, result);
}
fn replace(engine: *v.em.Engine, target: *c.JSValue, owned: c.JSValue) void { engine.freeValue(target.*); target.* = owned; }
fn plus(engine: *v.em.Engine, left: c.JSValue, right: c.JSValue) !c.JSValue { return engine.checked(c.JS_PiBinaryOperator(engine.context, 0, left, right)); }
fn format(engine: *v.em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    const input = if (args.len > 0) args[0] else c.pi_js_undefined();
    // This identity branch is the real Source body when actual hasColors is
    // falsy. Enabled formatting below never substitutes an identity helper.
    if (c.JS_ToBool(engine.context, roots[0]) == 0) return c.JS_DupValue(engine.context, input);
    const empty = try engine.checked(c.JS_NewString(engine.context, "")); defer engine.freeValue(empty);
    const string = try plus(engine, input, empty); defer engine.freeValue(string);
    var index = try v.js.invoke(engine, string, "indexOf", &.{roots[2]}); defer engine.freeValue(index);
    const minus_one = c.JS_NewInt32(engine.context, -1);
    if (c.JS_IsStrictEqual(engine.context, index, minus_one)) {
        const prefix = try plus(engine, roots[1], string); defer engine.freeValue(prefix);
        return plus(engine, prefix, roots[2]);
    }
    // These six consumed colors close with39, never22. Preserve live indexOf,
    // slice, + coercion and UTF16 positions rather than copying bytes in Zig.
    var result = c.JS_DupValue(engine.context, roots[1]); defer engine.freeValue(result);
    var last = c.JS_NewInt32(engine.context, 0); defer engine.freeValue(last);
    var iterations: usize = 0;
    while (!c.JS_IsStrictEqual(engine.context, index, minus_one)) {
        iterations +|= 1; try @import("native_jiti_budget.zig").check(engine, iterations);
        const piece = try v.js.invoke(engine, string, "slice", &.{ last, index }); defer engine.freeValue(piece);
        const reopened = try plus(engine, piece, roots[1]); defer engine.freeValue(reopened);
        replace(engine, &result, try plus(engine, result, reopened));
        replace(engine, &last, try plus(engine, index, c.JS_NewInt32(engine.context, 5)));
        replace(engine, &index, try v.js.invoke(engine, string, "indexOf", &.{ roots[2], last }));
    }
    const tail = try v.js.invoke(engine, string, "slice", &.{last}); defer engine.freeValue(tail);
    const closed = try plus(engine, tail, roots[2]); defer engine.freeValue(closed);
    return plus(engine, result, closed);
}
