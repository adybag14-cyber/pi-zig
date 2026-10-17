//! Source message functions for the actual TTY error registrations. Genuine
//! internal inspect/format/type helpers are retained inputs, not canned errors.
const std = @import("std");
const v = @import("native_ai_provider_values.zig");
const c = v.c;
const h = @import("native_node_tty_values.zig");
const f = @import("native_node_module_callable.zig");
pub const Inputs = struct {
    /// Actual internal/util/inspect exports object; format/inspect are selected
    /// live for each Source call. Public util property copies are not aliases.
    internal_inspect: c.JSValue,
    /// Bootstrap primordial methods, never late guest global lookups.
    string: c.JSValue,
    number_is_integer: c.JSValue,
    json_stringify: c.JSValue,
    string_slice: c.JSValue,
    string_index_of: c.JSValue,
};
pub const Exports = struct {
    invalid_fd: c.JSValue, invalid_arg_type: c.JSValue, out_of_range: c.JSValue, determine_specific_type: c.JSValue,
    pub fn deinit(self: Exports, engine: *v.em.Engine) void { engine.freeValue(self.invalid_fd); engine.freeValue(self.invalid_arg_type); engine.freeValue(self.out_of_range); engine.freeValue(self.determine_specific_type); }
};
pub fn create(engine: *v.em.Engine, inputs: Inputs) !Exports {
    engine.native_exception_diagnostics_suppressed += 1; defer engine.native_exception_diagnostics_suppressed -= 1;
    try h.pending(engine);
    if (!c.JS_IsObject(inputs.internal_inspect)) return error.RequiredActualInternalInspectExports;
    inline for (.{ inputs.string, inputs.number_is_integer, inputs.json_stringify, inputs.string_slice, inputs.string_index_of }) |function| if (!c.JS_IsFunction(engine.context, function)) return error.RequiredActualTtyMessagePrimordial;
    var s: v.Scope = .{ .engine = engine }; defer s.deinit();
    const specific = try s.own(try f.create(engine, "determineSpecificType", 1, true, determineSpecificType, &.{ inputs.internal_inspect, inputs.string, inputs.json_stringify, inputs.string_slice, inputs.string_index_of }));
    const roots = [_]c.JSValue{ inputs.internal_inspect, specific, inputs.string, inputs.number_is_integer };
    const fd = try s.own(try f.create(engine, "", 1, false, invalidFd, &roots));
    const argument = try s.own(try f.create(engine, "", 3, false, invalidArgType, &roots));
    const range = try s.own(try f.create(engine, "", 3, false, outOfRange, &roots));
    return .{ .invalid_fd = c.JS_DupValue(engine.context, fd), .invalid_arg_type = c.JS_DupValue(engine.context, argument), .out_of_range = c.JS_DupValue(engine.context, range), .determine_specific_type = c.JS_DupValue(engine.context, specific) };
}
fn concat(s: *v.Scope, left: c.JSValue, right: c.JSValue) !c.JSValue { return h.binary(s, .add, left, right); }
fn stringify(s: *v.Scope, value: c.JSValue) !c.JSValue { return s.own(try h.success(s.engine, try s.engine.checked(c.JS_ToString(s.engine.context, value)))); }
fn determineSpecificType(engine: *v.em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    var s: v.Scope = .{ .engine = engine }; defer s.deinit();
    var value = h.arg(args, 0);
    if (c.JS_IsNull(value)) return c.JS_DupValue(engine.context, try s.text("null"));
    if (c.JS_IsUndefined(value)) return c.JS_DupValue(engine.context, try s.text("undefined"));
    if (c.JS_IsBigInt(value)) {
        var result = try concat(&s, try s.text("type bigint ("), try stringify(&s, value));
        result = try concat(&s, result, try s.text("n)")); return c.JS_DupValue(engine.context, result);
    }
    if (c.JS_IsNumber(value)) {
        var number: f64 = 0; if (c.JS_ToFloat64(engine.context, &number, value) < 0) return v.js.capture(engine);
        const text = if (number == 0 and std.math.signbit(number)) try s.text("-0") else try stringify(&s, value);
        const result = try concat(&s, try concat(&s, try s.text("type number ("), text), try s.text(")"));
        return c.JS_DupValue(engine.context, result);
    }
    if (c.JS_IsBool(value)) return c.JS_DupValue(engine.context, try s.text(if (s.truthy(value)) "type boolean (true)" else "type boolean (false)"));
    if (c.JS_IsSymbol(value)) {
        const text = try h.call(&s, roots[1], c.pi_js_undefined(), &.{value});
        return c.JS_DupValue(engine.context, try concat(&s, try concat(&s, try s.text("type symbol ("), text), try s.text(")")));
    }
    if (c.JS_IsFunction(engine.context, value)) return c.JS_DupValue(engine.context, try concat(&s, try s.text("function "), try stringify(&s, try h.get(&s, value, "name"))));
    if (c.JS_IsObject(value)) {
        if (s.truthy(try h.get(&s, value, "constructor"))) {
            const second = try h.get(&s, value, "constructor");
            const present = try v.js.hasKey(engine, second, try s.text("name")); try h.pending(engine);
            if (present) return c.JS_DupValue(engine.context, try concat(&s, try s.text("an instance of "), try stringify(&s, try h.get(&s, try h.get(&s, value, "constructor"), "name"))));
        }
        const inspect = try h.get(&s, roots[0], "inspect");
        const options = try s.object(); try h.put(engine, options, "depth", c.JS_NewInt32(engine.context, -1));
        return c.JS_DupValue(engine.context, try stringify(&s, try h.call(&s, inspect, roots[0], &.{ value, options })));
    }
    if (c.JS_IsString(value)) {
        const units = try @import("native_utf16.zig").unitsAlloc(engine, value); defer engine.gpa.free(units);
        if (units.len > 28) value = try concat(&s, try h.call(&s, roots[3], value, &.{ c.JS_NewInt32(engine.context, 0), c.JS_NewInt32(engine.context, 25) }), try s.text("..."));
        const index = try h.call(&s, roots[4], value, &.{try s.text("'")});
        const quoted = if (s.equal(index, c.JS_NewInt32(engine.context, -1))) try concat(&s, try concat(&s, try s.text("'"), value), try s.text("'")) else try h.call(&s, roots[2], c.pi_js_undefined(), &.{value});
        return c.JS_DupValue(engine.context, try concat(&s, try concat(&s, try s.text("type string ("), quoted), try s.text(")")));
    }
    return error.RequiredAdditionalJavaScriptTypeDiagnostic;
}
fn invalidFd(engine: *v.em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    var s: v.Scope = .{ .engine = engine }; defer s.deinit();
    const format = try h.get(&s, roots[0], "format");
    // Actual getMessage static%s branch invokes format with null receiver.
    return c.JS_DupValue(engine.context, try h.call(&s, format, c.pi_js_null(), &.{ try s.text("\"fd\" must be a positive integer: %s"), h.arg(args, 0) }));
}
fn invalidArgType(engine: *v.em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    var s: v.Scope = .{ .engine = engine }; defer s.deinit();
    // Every actual TTY validateInteger caller passes expected='number'. Other
    // internal/errors registrations are not mislabeled as this finite profile.
    if (!try h.same(&s, h.arg(args, 1), "number")) return error.RequiredAdditionalInvalidArgumentTypeProfile;
    const name = h.arg(args, 0);
    if (!c.JS_IsString(name)) return error.RequiredStringErrorArgumentName;
    const units = try @import("native_utf16.zig").unitsAlloc(engine, name); defer engine.gpa.free(units);
    const suffix = [_]u16{ ' ', 'a', 'r', 'g', 'u', 'm', 'e', 'n', 't' };
    const ends_argument = std.mem.endsWith(u16, units, &suffix);
    const dotted = std.mem.indexOfScalar(u16, units, '.') != null;
    var message = try s.text("The ");
    if (ends_argument) {
        message = try concat(&s, message, name); message = try concat(&s, message, try s.text(" "));
    } else {
        message = try concat(&s, message, try s.text("\"")); message = try concat(&s, message, name);
        message = try concat(&s, message, try s.text(if (dotted) "\" property " else "\" argument "));
    }
    message = try concat(&s, message, try s.text("must be of type number. Received "));
    const received = try h.call(&s, roots[1], c.pi_js_undefined(), &.{h.arg(args, 2)});
    message = try concat(&s, message, received);
    return c.JS_DupValue(engine.context, message);
}
fn separated(s: *v.Scope, text: c.JSValue) !c.JSValue {
    const units = try @import("native_utf16.zig").unitsAlloc(s.engine, text); defer s.engine.gpa.free(units);
    var bytes: std.ArrayList(u16) = .empty; defer bytes.deinit(s.engine.gpa);
    const start: usize = if (units.len != 0 and units[0] == '-') 1 else 0;
    var end = units.len;
    while (end >= start + 4) : (end -= 3) {}
    try bytes.appendSlice(s.engine.gpa, units[0..end]);
    while (end < units.len) : (end += 3) { try bytes.append(s.engine.gpa, '_'); try bytes.appendSlice(s.engine.gpa, units[end .. end + 3]); }
    return s.own(try @import("native_utf16.zig").string(s.engine, bytes.items));
}
fn outOfRange(engine: *v.em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    var s: v.Scope = .{ .engine = engine }; defer s.deinit();
    const label = h.arg(args, 0); const range = h.arg(args, 1); const input = h.arg(args, 2);
    var message: c.JSValue = undefined;
    if (s.truthy(h.arg(args, 3))) message = label else {
        message = try concat(&s, try s.text("The value of \""), try stringify(&s, label));
        message = try concat(&s, message, try s.text("\" is out of range."));
    }
    var received: c.JSValue = undefined;
    var large_integer = false;
    if (s.truthy(try h.call(&s, roots[3], c.pi_js_undefined(), &.{input}))) {
        var number: f64 = 0; if (c.JS_ToFloat64(engine.context, &number, input) < 0) return v.js.capture(engine);
        large_integer = @abs(number) > 4294967296;
    }
    if (large_integer) {
        received = try separated(&s, try h.call(&s, roots[2], c.pi_js_undefined(), &.{input}));
    } else if (c.JS_IsBigInt(input)) {
        received = try h.call(&s, roots[2], c.pi_js_undefined(), &.{input});
        const limit = try s.own(try engine.checked(c.JS_NewBigInt64(engine.context, 4294967296)));
        const lower = try s.own(try engine.checked(c.JS_NewBigInt64(engine.context, -4294967296)));
        const greater = s.truthy(try h.binary(&s, .greater, input, limit));
        if (greater or s.truthy(try h.binary(&s, .less, input, lower))) received = try separated(&s, received);
        received = try concat(&s, received, try s.text("n"));
    } else {
        const inspect = try h.get(&s, roots[0], "inspect");
        received = try h.call(&s, inspect, roots[0], &.{input});
    }
    message = try concat(&s, message, try s.text(" It must be ")); message = try concat(&s, message, try stringify(&s, range));
    message = try concat(&s, message, try s.text(". Received ")); message = try concat(&s, message, received);
    return c.JS_DupValue(engine.context, message);
}
