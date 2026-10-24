// Copyright Joyent, Inc. and other Node contributors. MIT; retained Node LICENSE.
//! Complete original ERR_OUT_OF_RANGE message and validateInteger bodies.
//! Registration remains in the single actual argument-error owner. Primordials
//! come from that owner's early message capture, never from late guest globals.
const a = @import("native_node_argument_values.zig");
const functions = @import("native_node_module_callable.zig");
const registration = @import("native_node_argument_error_registration.zig");
const sync = @import("native_sync_arguments.zig");
const arithmetic = @import("native_image_arithmetic.zig");
const c = a.c;
const Scope = a.Scope;
const RangeFrame = a.frames.Frame(enum { message, received });
const SeparatorFrame = a.frames.Frame(enum { result, position, start });

fn number(s: *Scope, value: i32) c.JSValue { return c.JS_NewInt32(s.engine.context, value); }
fn binary(s: *Scope, operation: arithmetic.Operation, left: c.JSValue, right: c.JSValue) !c.JSValue {
    return s.binary(@intFromEnum(operation), left, right);
}
fn literal(s: *Scope, value: []const u8) !c.JSValue {
    return a.duplicate(s.engine, try s.text(value));
}
fn primordial(s: *Scope, roots: c.JSValue, name: [*:0]const u8, receiver: c.JSValue, args: []const c.JSValue) !c.JSValue {
    return a.duplicate(s.engine, try s.call(try s.get(roots, name), receiver, args));
}
fn integerCondition(s: *Scope, is_integer: c.JSValue, value: c.JSValue) !c.JSValue {
    return a.boolean(s, s.truthy(try s.call(is_integer, c.pi_js_undefined(), &.{value})));
}
fn separatorStart(s: *Scope, value: c.JSValue) !c.JSValue {
    return number(s, if (s.equal(try s.getKey(value, number(s, 0)), try s.text("-"))) 1 else 0);
}
fn separatorMore(s: *Scope, frame: *SeparatorFrame) !c.JSValue {
    return a.duplicate(s.engine, try binary(s, .greater_equal, frame.get(.position),
        try binary(s, .add, frame.get(.start), number(s, 4))));
}
fn separatorPart(s: *Scope, roots: c.JSValue, value: c.JSValue, frame: *SeparatorFrame) !c.JSValue {
    const part = try s.own(try primordial(s, roots, "stringSlice", value,
        &.{try binary(s, .subtract, frame.get(.position), number(s, 3)), frame.get(.position)}));
    var result = try a.add(s, try s.text("_"), try s.toString(part));
    result = try a.add(s, result, try s.toString(frame.get(.result)));
    return a.duplicate(s.engine, result);
}
fn separatorStep(s: *Scope, frame: *SeparatorFrame) !c.JSValue {
    return a.duplicate(s.engine, try binary(s, .subtract, frame.get(.position), number(s, 3)));
}
fn separatorResult(s: *Scope, roots: c.JSValue, value: c.JSValue, frame: *SeparatorFrame) !c.JSValue {
    const part = try s.own(try primordial(s, roots, "stringSlice", value,
        &.{number(s, 0), frame.get(.position)}));
    const prefix = try s.toString(part);
    return a.duplicate(s.engine, try a.add(s, prefix, try s.toString(frame.get(.result))));
}
fn separatorCallback(engine: *a.v.em.Engine, _: c.JSValue, args: *sync.Arguments, roots: []const c.JSValue) !c.JSValue {
    var s = Scope.init(engine);
    const frame = args.createFrame(&s.values, SeparatorFrame) catch |err| return s.finish(err);
    return s.finish(separatorBody(&s, args, roots[0], frame));
}
fn separatorBody(s: *Scope, args: *sync.Arguments, roots: c.JSValue, frame: *SeparatorFrame) !c.JSValue {
    try frame.take(.result, a.expression(s.engine, literal, .{@as([]const u8, "")}));
    try frame.take(.position, a.field(s.engine, args.get(0), "length"));
    try frame.take(.start, a.expression(s.engine, separatorStart, .{args.get(0)}));
    while (try a.condition(s.engine, separatorMore, .{frame})) {
        try frame.take(.result, a.expression(s.engine, separatorPart, .{roots, args.get(0), frame}));
        try frame.take(.position, a.expression(s.engine, separatorStep, .{frame}));
    }
    return a.expression(s.engine, separatorResult, .{roots, args.get(0), frame});
}
fn assertRange(s: *Scope, roots: c.JSValue, range: c.JSValue) !c.JSValue {
    _ = try s.own(try primordial(s, roots, "assert", c.pi_js_undefined(),
        &.{range, try s.text("Missing \"range\" argument")}));
    return c.pi_js_undefined();
}
fn initialMessage(s: *Scope, name: c.JSValue) !c.JSValue {
    var message = try a.add(s, try s.text("The value of \""), try s.toString(name));
    message = try a.add(s, message, try s.text("\" is out of range."));
    return a.duplicate(s.engine, message);
}
fn largeNumber(s: *Scope, roots: c.JSValue, input: c.JSValue) !c.JSValue {
    const absolute = try s.own(try primordial(s, roots, "MathAbs", c.pi_js_undefined(), &.{input}));
    // Pure numeric literal 2 ** 32; no caller value or coercion is folded.
    return a.duplicate(s.engine, try binary(s, .greater, absolute,
        c.JS_NewFloat64(s.engine.context, 4294967296)));
}
fn inputString(s: *Scope, roots: c.JSValue, input: c.JSValue) !c.JSValue {
    return primordial(s, roots, "String", c.pi_js_undefined(), &.{input});
}
fn separatedInput(s: *Scope, roots: c.JSValue, separator: c.JSValue, input: c.JSValue) !c.JSValue {
    const value = try s.own(try a.expression(s.engine, inputString, .{roots, input}));
    return a.duplicate(s.engine, try s.call(separator, c.pi_js_undefined(), &.{value}));
}
fn bigIntBound(s: *Scope, input: c.JSValue, negative: bool) !c.JSValue {
    // These are the two exact, closed BigInt literal expressions 2n ** 32n
    // and -(2n ** 32n); the input retains the real VM relational operator.
    const generation = try s.beforeAllocation();
    const bound = try s.checkedAllocation(c.JS_NewBigInt64(s.engine.context,
        if (negative) -4294967296 else 4294967296), generation);
    return a.duplicate(s.engine, try binary(s, if (negative) .less else .greater, input, bound));
}
fn separatorCall(s: *Scope, separator: c.JSValue, received: c.JSValue) !c.JSValue {
    return a.duplicate(s.engine, try s.call(separator, c.pi_js_undefined(), &.{received}));
}
fn appendBigIntSuffix(s: *Scope, received: c.JSValue) !c.JSValue {
    return a.duplicate(s.engine, try a.add(s, received, try s.text("n")));
}
fn inspectInput(s: *Scope, roots: c.JSValue, input: c.JSValue) !c.JSValue {
    const module = try s.get(roots, "inspect");
    return a.duplicate(s.engine, try s.call(try s.get(module, "inspect"), module, &.{input}));
}
fn finalMessage(s: *Scope, message: c.JSValue, range: c.JSValue, received: c.JSValue) !c.JSValue {
    var suffix = try a.add(s, try s.text(" It must be "), try s.toString(range));
    suffix = try a.add(s, suffix, try s.text(". Received "));
    suffix = try a.add(s, suffix, try s.toString(received));
    // Compound assignment reads the old message first but only coerces it
    // after every RHS template substitution has completed.
    return a.duplicate(s.engine, try a.add(s, message, suffix));
}
fn messageCallback(engine: *a.v.em.Engine, _: c.JSValue, args: *sync.Arguments, roots: []const c.JSValue) !c.JSValue {
    var s = Scope.init(engine);
    const frame = args.createFrame(&s.values, RangeFrame) catch |err| return s.finish(err);
    return s.finish(messageBody(&s, args, roots[0], roots[1], frame));
}
fn messageBody(s: *Scope, args: *sync.Arguments, roots: c.JSValue, separator: c.JSValue, frame: *RangeFrame) !c.JSValue {
    if (c.JS_IsUndefined(args.get(3))) try args.copy(3, a.boolean(s, false));
    _ = try a.expression(s.engine, assertRange, .{roots, args.get(1)});
    if (s.truthy(args.get(3))) try frame.copy(.message, args.get(0))
    else try frame.take(.message, a.expression(s.engine, initialMessage, .{args.get(0)}));
    const is_integer = try s.get(roots, "NumberIsInteger");
    if (try a.condition(s.engine, integerCondition, .{is_integer, args.get(2)}) and
        try a.condition(s.engine, largeNumber, .{roots, args.get(2)}))
    {
        try frame.take(.received, a.expression(s.engine, separatedInput, .{roots, separator, args.get(2)}));
    } else if (c.JS_IsBigInt(args.get(2))) {
        try frame.take(.received, a.expression(s.engine, inputString, .{roots, args.get(2)}));
        if (try a.condition(s.engine, bigIntBound, .{args.get(2), false}) or
            try a.condition(s.engine, bigIntBound, .{args.get(2), true}))
            try frame.take(.received, a.expression(s.engine, separatorCall, .{separator, frame.get(.received)}));
        try frame.take(.received, a.expression(s.engine, appendBigIntSuffix, .{frame.get(.received)}));
    } else {
        try frame.take(.received, a.expression(s.engine, inspectInput, .{roots, args.get(2)}));
    }
    try frame.take(.message, a.expression(s.engine, finalMessage,
        .{frame.get(.message), args.get(1), frame.get(.received)}));
    return a.duplicate(s.engine, frame.get(.message));
}
/// The complete function-message callback has Source length three because the
/// fourth formal has a default. The private separator is one original function.
pub fn makeMessage(s: *Scope, roots: c.JSValue) !c.JSValue {
    inline for (.{ "NumberIsInteger", "MathAbs", "String", "stringSlice", "assert" }) |name|
        if (!c.JS_IsFunction(s.engine.context, try s.get(roots, name)))
            return error.ActualOutOfRangePrimordialsRequired;
    const separator = try s.own(try functions.createWithArguments(s.engine, "addNumericalSeparator", 1, true,
        .{ .formal_count = 1, .callback = separatorCallback, .hooks = sync.frameHooks(SeparatorFrame) }, &.{roots}));
    return functions.createWithArguments(s.engine, "", 3, false,
        .{ .formal_count = 4, .callback = messageCallback, .hooks = sync.frameHooks(RangeFrame) }, &.{roots, separator});
}
fn comparison(s: *Scope, operation: arithmetic.Operation, value: c.JSValue, bound: c.JSValue) !c.JSValue {
    return a.duplicate(s.engine, try binary(s, operation, value, bound));
}
fn integerRangeText(s: *Scope, minimum: c.JSValue, maximum: c.JSValue) !c.JSValue {
    var result = try a.add(s, try s.text(">= "), try s.toString(minimum));
    result = try a.add(s, result, try s.text(" && <= "));
    return a.duplicate(s.engine, try a.add(s, result, try s.toString(maximum)));
}
fn invalidInteger(s: *Scope, error_class: c.JSValue, name: c.JSValue, expected: c.JSValue, value: c.JSValue) !c.JSValue {
    return a.raise(s, try s.construct(error_class, &.{name, expected, value}));
}
fn integerCallback(engine: *a.v.em.Engine, _: c.JSValue, args: *sync.Arguments, roots: []const c.JSValue) !c.JSValue {
    return a.expression(engine, integerBody, .{args, roots});
}
fn integerBody(s: *Scope, args: *sync.Arguments, roots: []const c.JSValue) !c.JSValue {
    // Actual formal initialization precedes the body and never coerces bounds.
    if (c.JS_IsUndefined(args.get(2))) try args.copy(2, roots[3]);
    if (c.JS_IsUndefined(args.get(3))) try args.copy(3, roots[4]);
    if (!c.JS_IsNumber(args.get(0)))
        return invalidInteger(s, roots[0], args.get(1), try s.text("number"), args.get(0));
    if (!try a.condition(s.engine, integerCondition, .{roots[2], args.get(0)}))
        return invalidInteger(s, roots[1], args.get(1), try s.text("an integer"), args.get(0));
    if (try a.condition(s.engine, comparison, .{arithmetic.Operation.less, args.get(0), args.get(2)}) or
        try a.condition(s.engine, comparison, .{arithmetic.Operation.greater, args.get(0), args.get(3)}))
    {
        const expected = try s.own(try a.expression(s.engine, integerRangeText, .{args.get(2), args.get(3)}));
        return invalidInteger(s, roots[1], args.get(1), expected, args.get(0));
    }
    return c.pi_js_undefined();
}
/// Full original default bounds, type/integer/range order, relational coercions
/// and real hideStackFrames wrapper; this is not a count-only validator.
pub fn makeValidateInteger(s: *Scope, hidden_type: c.JSValue, hidden_range: c.JSValue,
    error_class: c.JSValue, capture: c.JSValue, apply: c.JSValue, roots: c.JSValue) !c.JSValue
{
    const is_integer = try s.get(roots, "NumberIsInteger");
    if (!c.JS_IsFunction(s.engine.context, is_integer)) return error.ActualNumberIsIntegerRequired;
    const raw = try s.own(try functions.createWithArguments(s.engine, "", 2, false,
        .{ .formal_count = 4, .callback = integerCallback },
        &.{hidden_type, hidden_range, is_integer, try s.get(roots, "NumberMIN_SAFE_INTEGER"), try s.get(roots, "NumberMAX_SAFE_INTEGER")}));
    return registration.wrap(s, raw, error_class, capture, apply);
}
