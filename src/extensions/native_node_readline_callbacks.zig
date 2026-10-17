//! Actual Node24 internal/readline/callbacks used by the four TTY methods.
//! This exports those functions, not a fake Interface/promises implementation.
const std = @import("std");
const v = @import("native_ai_provider_values.zig");
const c = v.c;
const h = @import("native_node_tty_values.zig");
const f = @import("native_node_module_callable.zig");
pub const Inputs = struct { validate_function: c.JSValue, invalid_arg_value: c.JSValue, invalid_cursor_pos: c.JSValue };
pub fn create(engine: *v.em.Engine, inputs: Inputs) !c.JSValue {
    engine.native_exception_diagnostics_suppressed += 1; defer engine.native_exception_diagnostics_suppressed -= 1;
    try h.pending(engine);
    inline for (.{ inputs.validate_function, inputs.invalid_arg_value, inputs.invalid_cursor_pos }) |function| if (!c.JS_IsFunction(engine.context, function)) return error.RequiredActualReadlineDependencies;
    var s: v.Scope = .{ .engine = engine }; defer s.deinit();
    const roots = [_]c.JSValue{ inputs.validate_function, inputs.invalid_arg_value, inputs.invalid_cursor_pos };
    const exports = try s.object();
    inline for (.{ .{ "clearLine", 3, clearLine }, .{ "clearScreenDown", 2, clearScreenDown }, .{ "cursorTo", 4, cursorTo }, .{ "moveCursor", 4, moveCursor } }) |entry| try h.put(engine, exports, entry[0], try s.own(try f.create(engine, entry[0], entry[1], true, entry[2], &roots)));
    return c.JS_DupValue(engine.context, exports);
}
fn validate(s: *v.Scope, callback: c.JSValue, roots: []const c.JSValue) !void {
    if (!c.JS_IsUndefined(callback)) _ = try h.call(s, roots[0], c.pi_js_undefined(), &.{ callback, try s.text("callback") });
}
fn noWrite(s: *v.Scope, callback: c.JSValue) !c.JSValue {
    if (c.JS_IsFunction(s.engine.context, callback)) {
        const process = try s.own(try h.success(s.engine, try v.js.global(s.engine, "process")));
        _ = try h.invoke(s, process, "nextTick", &.{ callback, c.pi_js_null() });
    }
    return c.pi_js_bool(s.engine.context, 1);
}
fn isNaN(engine: *v.em.Engine, value: c.JSValue) !bool {
    if (!c.JS_IsNumber(value)) return false;
    var number: f64 = 0; if (c.JS_ToFloat64(engine.context, &number, value) < 0) return v.js.capture(engine); return std.math.isNan(number);
}
fn csi(s: *v.Scope, value: c.JSValue, suffix: []const u8) !c.JSValue {
    // Original CSI tag appends raw arguments with += (default ToPrimitive),
    // not pre-coercion, String() or a template string's string-hint coercion.
    return h.binary(s, .add, try h.binary(s, .add, try s.text("\x1b["), value), try s.text(suffix));
}
fn negate(s: *v.Scope, value: c.JSValue) !c.JSValue {
    const numeric = try s.own(try h.success(s.engine, try s.engine.checked(c.JS_PiToNumeric(s.engine.context, value))));
    const minus_one = if (c.JS_IsBigInt(numeric)) try s.own(try s.engine.checked(c.JS_NewBigInt64(s.engine.context, -1))) else c.JS_NewInt32(s.engine.context, -1);
    return h.binary(s, .multiply, numeric, minus_one);
}
fn cursorTo(engine: *v.em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    try h.pending(engine); var s: v.Scope = .{ .engine = engine }; defer s.deinit();
    const stream = h.arg(args, 0); const x = h.arg(args, 1); var y = h.arg(args, 2); var callback = h.arg(args, 3);
    try validate(&s, callback, roots);
    if (c.JS_IsFunction(engine.context, y)) { callback = y; y = c.pi_js_undefined(); }
    if (try isNaN(engine, x)) return h.throwValue(engine, try h.construct(&s, roots[1], &.{ try s.text("x"), x }));
    if (try isNaN(engine, y)) return h.throwValue(engine, try h.construct(&s, roots[1], &.{ try s.text("y"), y }));
    if (v.nullish(stream) or (!c.JS_IsNumber(x) and !c.JS_IsNumber(y))) return noWrite(&s, callback);
    if (!c.JS_IsNumber(x)) return h.throwValue(engine, try h.construct(&s, roots[2], &.{}));
    var data: c.JSValue = undefined;
    if (!c.JS_IsNumber(y)) data = try csi(&s, try h.binary(&s, .add, x, c.JS_NewInt32(engine.context, 1)), "G") else {
        const first = try h.binary(&s, .add, y, c.JS_NewInt32(engine.context, 1));
        const second = try h.binary(&s, .add, x, c.JS_NewInt32(engine.context, 1));
        data = try h.binary(&s, .add, try h.binary(&s, .add, try csi(&s, first, ";"), second), try s.text("H"));
    }
    return c.JS_DupValue(engine.context, try h.invoke(&s, stream, "write", &.{ data, callback }));
}
fn moveCursor(engine: *v.em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    try h.pending(engine); var s: v.Scope = .{ .engine = engine }; defer s.deinit();
    const stream = h.arg(args, 0); const dx = h.arg(args, 1); const dy = h.arg(args, 2); const callback = h.arg(args, 3);
    try validate(&s, callback, roots);
    if (v.nullish(stream) or !(s.truthy(dx) or s.truthy(dy))) return noWrite(&s, callback);
    var data = try s.text("");
    const zero = c.JS_NewInt32(engine.context, 0);
    if (s.truthy(try h.binary(&s, .less, dx, zero))) data = try h.binary(&s, .add, data, try csi(&s, try negate(&s, dx), "D")) else if (s.truthy(try h.binary(&s, .greater, dx, zero))) data = try h.binary(&s, .add, data, try csi(&s, dx, "C"));
    if (s.truthy(try h.binary(&s, .less, dy, zero))) data = try h.binary(&s, .add, data, try csi(&s, try negate(&s, dy), "A")) else if (s.truthy(try h.binary(&s, .greater, dy, zero))) data = try h.binary(&s, .add, data, try csi(&s, dy, "B"));
    return c.JS_DupValue(engine.context, try h.invoke(&s, stream, "write", &.{ data, callback }));
}
fn clearLine(engine: *v.em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    try h.pending(engine); var s: v.Scope = .{ .engine = engine }; defer s.deinit();
    const stream = h.arg(args, 0); const direction = h.arg(args, 1); const callback = h.arg(args, 2);
    try validate(&s, callback, roots);
    if (v.nullish(stream)) return noWrite(&s, callback);
    const zero = c.JS_NewInt32(engine.context, 0);
    const data = if (s.truthy(try h.binary(&s, .less, direction, zero))) try s.text("\x1b[1K") else if (s.truthy(try h.binary(&s, .greater, direction, zero))) try s.text("\x1b[0K") else try s.text("\x1b[2K");
    return c.JS_DupValue(engine.context, try h.invoke(&s, stream, "write", &.{ data, callback }));
}
fn clearScreenDown(engine: *v.em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    try h.pending(engine); var s: v.Scope = .{ .engine = engine }; defer s.deinit();
    const stream = h.arg(args, 0); const callback = h.arg(args, 1);
    try validate(&s, callback, roots);
    if (v.nullish(stream)) return noWrite(&s, callback);
    return c.JS_DupValue(engine.context, try h.invoke(&s, stream, "write", &.{ try s.text("\x1b[0J"), callback }));
}
