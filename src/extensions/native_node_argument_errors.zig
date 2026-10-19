//! One completed internal/errors argument graph shared by filesystem, CJS
//! and the new TTY composition. The existing Node marker remains authoritative.
const std = @import("std");
const a = @import("native_node_argument_values.zig");
const v = a.v;
const c = a.c;
const Scope = a.Scope;
const registration = @import("native_node_argument_error_registration.zig");
const key = "pi-native:private/argument-error-owner";
pub const Inputs = struct {
    error_constructor: c.JSValue,
    type_error: c.JSValue,
    range_error: c.JSValue,
    marker: c.JSValue,
    assert_function: c.JSValue,
    capture_stack_trace: c.JSValue,
    reflect_apply: c.JSValue,
    array_unshift: c.JSValue,
    invalid_arg_type_message: c.JSValue,
    invalid_arg_value_message: c.JSValue,
    internal_assertion_message: c.JSValue,
};
pub const Exports = struct {
    invalid_arg_type: c.JSValue,
    hidden_invalid_arg_type: c.JSValue,
    invalid_arg_value: c.JSValue,
    internal_assertion: c.JSValue,
    validate_string: c.JSValue,
    pub fn deinit(self: Exports, engine: *v.em.Engine) void {
        var completion = a.owned.Completion.initVoid(engine, {});
        inline for (std.meta.fields(Exports)) |field| completion.release(@field(self, field.name));
        completion.finishVoid() catch {};
    }
};
fn exports(values: [5]c.JSValue) Exports {
    return .{ .invalid_arg_type = values[0], .hidden_invalid_arg_type = values[1],
        .invalid_arg_value = values[2], .internal_assertion = values[3], .validate_string = values[4] };
}
fn view(s: *Scope, record: c.JSValue) ![5]c.JSValue {
    var output = [_]c.JSValue{c.pi_js_undefined()} ** 5;
    inline for (.{ "type", "hidden", "value", "assertion", "validateString" }, 0..) |name, position|
        output[position] = try s.get(record, name);
    for (&output) |*slot| slot.* = a.duplicate(s.engine, slot.*);
    return output;
}
fn ready(s: *Scope, record: c.JSValue) !void {
    if (!s.truthy(try s.get(record, "ready"))) return error.ArgumentErrorOwnerReentry;
}
pub fn acquire(engine: *v.em.Engine) !?Exports {
    var s = Scope.init(engine);
    var values = [_]c.JSValue{c.pi_js_undefined()} ** 5;
    var failure: ?anyerror = null;
    var present = false;
    if (engine.native_module_values.get(key)) |record| {
        if (acquireBody(&s, record)) |result| { values = result; present = true; }
        else |err| failure = err;
    }
    try s.boundary.finishMany(failure, &s.values, &values);
    return if (present) exports(values) else null;
}
fn acquireBody(s: *Scope, record: c.JSValue) ![5]c.JSValue {
    try s.pending(); try ready(s, record); return view(s, record);
}
fn removeAttempt(s: *Scope, attempt: c.JSValue) void {
    if (s.engine.native_module_values.get(key)) |known| {
        if (s.equal(known, attempt)) {
            var removed = s.engine.native_module_values.fetchRemove(key).?.value;
            s.boundary.release(&removed);
        }
    }
}
pub fn create(engine: *v.em.Engine, inputs: Inputs) !Exports {
    var s = Scope.init(engine);
    var values = [_]c.JSValue{c.pi_js_undefined()} ** 5;
    var failure: ?anyerror = null;
    var attempt: ?c.JSValue = null; // The private map owns this comparison token.
    if (body(&s, inputs, &attempt)) |result| values = result else |err| failure = err;
    // Finish staging/retirement while ready is still false. A finalizer may
    // reenter, but it cannot acquire an incompletely retired owner.
    s.boundary.retire(failure, &s.values, &values);
    if (s.boundary.failed(failure)) {
        if (attempt) |created| { attempt = null; removeAttempt(&s, created); }
    } else if (attempt) |created| {
        // This exact private, pre-existing writable data slot cannot invoke a
        // guest setter. Preserve its allocation producer separately if needed.
        const generation = s.boundary.beforeAllocation() catch |err| failed: { failure = err; break :failed 0; };
        if (failure == null) {
            const status = c.JS_SetPropertyStr(engine.context, created, "ready", c.pi_js_bool(engine.context, 1));
            s.boundary.checkPendingSince(generation) catch |err| { failure = err; };
            if (status < 0 and failure == null) failure = error.MissingActualArgumentOwnerReadyReason;
        }
        if (s.boundary.failed(failure)) { attempt = null; removeAttempt(&s, created); }
    }
    try s.boundary.finishRetired(failure, &values);
    return exports(values);
}
fn publishPending(s: *Scope, record: c.JSValue) !void {
    const retained = a.duplicate(s.engine, record);
    s.engine.native_module_values.put(s.engine.gpa, key, retained) catch |err| {
        // Materialize the actual typed allocator failure before this incoming
        // root can retire and run a later producer.
        var completion = a.owned.Completion.initVoid(s.engine, err);
        completion.release(retained);
        return completion.finishVoid();
    };
}
fn body(s: *Scope, inputs: Inputs, attempt: *?c.JSValue) ![5]c.JSValue {
    try s.pending();
    if (s.engine.native_module_values.get(key)) |known| {
        try ready(s, known);
        inline for (std.meta.fields(Inputs)) |field| {
            if (!s.equal(try s.get(known, field.name), @field(inputs, field.name))) return error.ArgumentErrorOwnerConflict;
        }
        return view(s, known);
    }
    if (!c.JS_IsSymbol(inputs.marker)) return error.ActualNodeErrorMarkerRequired;
    inline for (std.meta.fields(Inputs)) |field| {
        if (comptime !std.mem.eql(u8, field.name, "marker")) {
            if (!c.JS_IsFunction(s.engine.context, @field(inputs, field.name))) return error.ActualArgumentErrorAuthorityRequired;
        }
    }
    const record = try s.objectProto(c.pi_js_null());
    try s.put(record, "ready", a.boolean(s, false));
    inline for (std.meta.fields(Inputs)) |field| try s.put(record, field.name, @field(inputs, field.name));
    try publishPending(s, record);
    attempt.* = record;
    const argument = try registration.register(s, inputs.type_error, "ERR_INVALID_ARG_TYPE", inputs.invalid_arg_type_message, inputs.marker, inputs.assert_function, inputs.reflect_apply);
    const hidden = try registration.hide(s, argument, inputs.type_error, inputs.error_constructor);
    const value = try registration.register(s, inputs.type_error, "ERR_INVALID_ARG_VALUE", inputs.invalid_arg_value_message, inputs.marker, inputs.assert_function, inputs.reflect_apply);
    // Source E supplies the actual RangeError specialization and both Hide
    // subclasses for ERR_INVALID_ARG_VALUE, all within this same owner.
    const range = try registration.register(s, inputs.range_error, "ERR_INVALID_ARG_VALUE", inputs.invalid_arg_value_message, inputs.marker, inputs.assert_function, inputs.reflect_apply);
    try s.put(value, "RangeError", range);
    const hidden_range = try registration.hide(s, range, inputs.range_error, inputs.error_constructor);
    const hidden_value = try registration.hide(s, value, inputs.type_error, inputs.error_constructor);
    const assertion_class = try registration.register(s, inputs.error_constructor, "ERR_INTERNAL_ASSERTION", inputs.internal_assertion_message, inputs.marker, inputs.assert_function, inputs.reflect_apply);
    const validate_string = try registration.makeValidateString(s, hidden, inputs.error_constructor, inputs.capture_stack_trace, inputs.reflect_apply);
    const validate_abort = try registration.makeValidateAbortSignal(s, hidden, inputs.error_constructor, inputs.capture_stack_trace, inputs.reflect_apply);
    try s.put(record, "type", argument); try s.put(record, "hidden", hidden); try s.put(record, "value", value);
    try s.put(record, "hiddenValue", hidden_value); try s.put(record, "rangeValue", range); try s.put(record, "hiddenRangeValue", hidden_range);
    try s.put(record, "assertion", assertion_class); try s.put(record, "validateString", validate_string); try s.put(record, "validateAbortSignal", validate_abort);
    return view(s, record);
}
fn memberBody(s: *Scope, name: [*:0]const u8) !c.JSValue {
    try s.pending();
    const record = s.engine.native_module_values.get(key) orelse return error.ActualInternalErrorsNotInitialized;
    try ready(s, record);
    return a.duplicate(s.engine, try s.get(record, name));
}
pub fn assertion(engine: *v.em.Engine) !c.JSValue { return a.expression(engine, memberBody, .{@as([*:0]const u8, "assertion")}); }
pub fn hiddenValue(engine: *v.em.Engine) !c.JSValue { return a.expression(engine, memberBody, .{@as([*:0]const u8, "hiddenValue")}); }
pub fn rangeValue(engine: *v.em.Engine) !c.JSValue { return a.expression(engine, memberBody, .{@as([*:0]const u8, "rangeValue")}); }
pub fn hiddenRangeValue(engine: *v.em.Engine) !c.JSValue { return a.expression(engine, memberBody, .{@as([*:0]const u8, "hiddenRangeValue")}); }
pub fn validateAbortSignal(engine: *v.em.Engine) !c.JSValue { return a.expression(engine, memberBody, .{@as([*:0]const u8, "validateAbortSignal")}); }

/// Original primordial functions retained by the completed internal/errors owner.
pub fn reflectApply(engine: *v.em.Engine) !c.JSValue { return a.expression(engine, memberBody, .{@as([*:0]const u8, "reflect_apply")}); }
pub fn arrayUnshift(engine: *v.em.Engine) !c.JSValue { return a.expression(engine, memberBody, .{@as([*:0]const u8, "array_unshift")}); }
