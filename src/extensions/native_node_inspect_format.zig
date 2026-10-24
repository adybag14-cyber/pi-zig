// Copyright Joyent, Inc. and other Node contributors. MIT; retained Node LICENSE.
//! Actual Node internal/util/inspect format and formatWithOptions entries.
//! Shared option flow is the original formatWithOptionsInternal. The rest Array and
//! inner lexical slots are real VM owners. All primordial callables are
//! captured during the genuine inspector bootstrap.
const a = @import("native_node_argument_values.zig");
const c = a.c;
const Scope = a.Scope;
const ops = @import("native_node_inspect_operations.zig");
const primitive = @import("native_node_util_inspect_primitive.zig");
const arithmetic = @import("native_image_arithmetic.zig");
const caught = @import("native_agent_af_values.zig").caught;
const RestFrame = a.frames.Frame(enum { rest });
const OptionsFrame = a.frames.Frame(enum { inspect_options, rest });
const StringifyFrame = a.frames.Frame(enum { reason, cycle, circular_error });
const FormatFrame = a.frames.Frame(enum {
    first, str, join, temp_str, temp_arg, temp_num, temp_integer, temp_float,
    trailing_value,
});

fn dup(s: *Scope, value: c.JSValue) c.JSValue { return a.duplicate(s.engine, value); }
fn number(s: *Scope, value: usize) c.JSValue { return c.JS_NewFloat64(s.engine.context, @floatFromInt(value)); }
fn member(s: *Scope, owner: c.JSValue, name: [*:0]const u8) anyerror!c.JSValue {
    return s.get(try s.get(owner, "captured"), name);
}
fn expr(s: *Scope, comptime body: anytype, args: anytype) anyerror!c.JSValue {
    return s.own(try a.expression(s.engine, body, args));
}
pub fn capture(engine: *a.v.em.Engine, global: c.JSValue) anyerror!c.JSValue {
    return a.expression(engine, captureBody, .{global});
}
fn captureBody(s: *Scope, global: c.JSValue) anyerror!c.JSValue {
    const result = try s.objectProto(c.pi_js_null());
    const string = try s.get(global, "String");
    const string_prototype = try s.get(string, "prototype");
    try s.define(result, "String", string, c.JS_PROP_C_W_E);
    inline for (.{ "charCodeAt", "slice", "split" }) |name|
        try s.define(result, name, try s.get(string_prototype, name), c.JS_PROP_C_W_E);
    const numeric = try s.get(global, "Number");
    try s.define(result, "Number", numeric, c.JS_PROP_C_W_E);
    try s.define(result, "parseInt", try s.get(numeric, "parseInt"), c.JS_PROP_C_W_E);
    try s.define(result, "parseFloat", try s.get(numeric, "parseFloat"), c.JS_PROP_C_W_E);
    try s.define(result, "stringify", try s.get(try s.get(global, "JSON"), "stringify"), c.JS_PROP_C_W_E);
    return dup(s, result);
}
pub fn create(engine: *a.v.em.Engine, captured: c.JSValue, inspect: c.JSValue,
    classifier: c.JSValue, defaults: c.JSValue, no_color: c.JSValue) anyerror!c.JSValue
{
    return a.expression(engine, createBody, .{ captured, inspect, classifier, defaults, no_color });
}
fn createBody(s: *Scope, captured: c.JSValue, inspect: c.JSValue,
    classifier: c.JSValue, defaults: c.JSValue, no_color: c.JSValue) anyerror!c.JSValue
{
    if (!c.JS_IsObject(captured) or !c.JS_IsFunction(s.engine.context, inspect) or
        !c.JS_IsFunction(s.engine.context, classifier) or !c.JS_IsObject(defaults) or
        !c.JS_IsFunction(s.engine.context, no_color))
        return error.RequiredActualInspectFormatterImports;
    const owner = try s.objectProto(c.pi_js_null());
    try s.define(owner, "captured", captured, c.JS_PROP_C_W_E);
    try s.define(owner, "inspect", inspect, c.JS_PROP_C_W_E);
    try s.define(owner, "classifier", classifier, c.JS_PROP_C_W_E);
    try s.define(owner, "defaults", defaults, c.JS_PROP_C_W_E);
    try s.define(owner, "noColor", no_color, c.JS_PROP_C_W_E);
    try s.define(owner, "circularMessage", c.pi_js_undefined(), c.JS_PROP_C_W_E);
    return dup(s, owner);
}
fn restBody(s: *Scope, argv: []const c.JSValue) anyerror!c.JSValue {
    const generation = try s.beforeAllocation();
    return dup(s, try s.checkedAllocation(c.JS_PiCreateRestArray(s.engine.context,
        @intCast(argv.len), @constCast(argv.ptr)), generation));
}
pub fn call(engine: *a.v.em.Engine, argv: []const c.JSValue,
    lexical: c.JSValue) anyerror!c.JSValue
{
    var s = Scope.init(engine);
    const frame = RestFrame.create(&s.values) catch |err|
        return s.finish(@as(anyerror!c.JSValue, err));
    return a.finishFrame(&s, frame, restCallBody(&s, frame, argv, lexical));
}
fn restCallBody(s: *Scope, frame: *RestFrame, argv: []const c.JSValue,
    lexical: c.JSValue) anyerror!c.JSValue
{
    // This producer precedes the first statement, including args[0] when the
    // actual rest Array is empty and its prototype supplies an inherited key.
    try frame.take(.rest, a.expression(s.engine, restBody, .{argv}));
    const owner = try s.get(lexical, "formatter");
    return internal(s.engine, owner, frame.get(.rest), c.pi_js_undefined());
}
/// Original formatWithOptions formal option and actual rest Array owners.
/// The real completed internal/errors graph supplies the same stable validator.
pub fn callWithOptions(engine: *a.v.em.Engine, argv: []const c.JSValue,
    lexical: c.JSValue) anyerror!c.JSValue
{
    var s = Scope.init(engine);
    const frame = OptionsFrame.create(&s.values) catch |err|
        return s.finish(@as(anyerror!c.JSValue, err));
    return a.finishFrame(&s, frame, optionsCallBody(&s, frame, argv, lexical));
}
fn optionsCallBody(s: *Scope, frame: *OptionsFrame, argv: []const c.JSValue,
    lexical: c.JSValue) anyerror!c.JSValue
{
    try frame.copy(.inspect_options, a.arg(argv, 0));
    const rest = if (argv.len > 0) argv[1..] else argv;
    try frame.take(.rest, a.expression(s.engine, restBody, .{rest}));
    _ = try a.expression(s.engine, validateOptions, .{frame.get(.inspect_options)});
    const owner = try s.get(lexical, "formatter");
    return internal(s.engine, owner, frame.get(.rest), frame.get(.inspect_options));
}
fn validateOptions(s: *Scope, inspect_options: c.JSValue) anyerror!c.JSValue {
    const validator = try s.own(try @import("native_node_argument_errors.zig").validateObject(s.engine));
    _ = try s.call(validator, c.pi_js_undefined(),
        &.{ inspect_options, try s.text("inspectOptions"), c.JS_NewInt32(s.engine.context, 2) });
    return c.pi_js_undefined();
}
fn internal(engine: *a.v.em.Engine, owner: c.JSValue, args: c.JSValue,
    inspect_options: c.JSValue) anyerror!c.JSValue {
    var s = Scope.init(engine);
    const frame = FormatFrame.create(&s.values) catch |err|
        return s.finish(@as(anyerror!c.JSValue, err));
    return a.finishFrame(&s, frame, internalBody(&s, frame, owner, args, inspect_options));
}
fn indexed(s: *Scope, array: c.JSValue, index: usize) anyerror!c.JSValue {
    return dup(s, try s.getKey(array, number(s, index)));
}
fn stringValue(s: *Scope, text: []const u8) anyerror!c.JSValue { return dup(s, try s.text(text)); }
fn lengthEqual(s: *Scope, array: c.JSValue, expected: usize) anyerror!c.JSValue {
    return a.boolean(s, s.equal(try s.get(array, "length"), number(s, expected)));
}
fn lessThanLength(s: *Scope, array: c.JSValue, index: usize) anyerror!c.JSValue {
    return a.boolean(s, s.truthy(try s.binary(@intFromEnum(arithmetic.Operation.less), number(s, index), try s.get(array, "length"))));
}
fn moreCharacters(s: *Scope, first: c.JSValue, index: usize) anyerror!c.JSValue {
    const limit = try s.binary(@intFromEnum(arithmetic.Operation.subtract), try s.get(first, "length"), number(s, 1));
    return a.boolean(s, s.truthy(try s.binary(@intFromEnum(arithmetic.Operation.less), number(s, index), limit)));
}
fn codeAt(s: *Scope, owner: c.JSValue, first: c.JSValue, index: usize) anyerror!c.JSValue {
    const method = try member(s, owner, "charCodeAt");
    return dup(s, try s.call(method, first, &.{number(s, index)}));
}
fn charCode(engine: *a.v.em.Engine, owner: c.JSValue, first: c.JSValue, index: usize) anyerror!u32 {
    var s = Scope.init(engine);
    const value = codeAt(&s, owner, first, index) catch |err| {
        _ = s.finish(@as(anyerror!c.JSValue, err)) catch |failure| return failure;
        unreachable;
    };
    const held = s.own(value) catch |err| {
        _ = s.finish(@as(anyerror!c.JSValue, err)) catch |failure| return failure;
        unreachable;
    };
    const result = ops.uint32(&s.values, held) catch |err| {
        _ = s.finish(@as(anyerror!c.JSValue, err)) catch |failure| return failure;
        unreachable;
    };
    _ = try s.finish(c.pi_js_undefined());
    return result;
}
fn appendValue(s: *Scope, current: c.JSValue, value: c.JSValue) anyerror!c.JSValue {
    return dup(s, try a.add(s, current, value));
}
fn appendSlice(s: *Scope, owner: c.JSValue, current: c.JSValue,
    first: c.JSValue, start: usize, end: ?usize) anyerror!c.JSValue
{
    // The compound-assignment old string is selected before the RHS call.
    const slice = try member(s, owner, "slice");
    const piece = if (end) |limit|
        try s.call(slice, first, &.{ number(s, start), number(s, limit) })
    else
        try s.call(slice, first, &.{number(s, start)});
    return dup(s, try a.add(s, current, piece));
}
fn numericBody(s: *Scope, owner: c.JSValue, value: c.JSValue, bigint: bool,
    inspect_options: c.JSValue) anyerror!c.JSValue
{
    // Original optional Get and nullish fallback occur after value conversion.
    // Falsy nonnull values suppress the shared default; no options are copied.
    const no_color = try s.get(owner, "noColor");
    const selected = if (c.JS_IsNull(inspect_options) or c.JS_IsUndefined(inspect_options))
        c.pi_js_undefined() else try s.get(inspect_options, "numericSeparator");
    const separator = if (c.JS_IsNull(selected) or c.JS_IsUndefined(selected))
        try s.get(try s.get(owner, "defaults"), "numericSeparator") else selected;
    const formatted = if (bigint) try primitive.bigint(&s.values, value, s.truthy(separator))
        else try primitive.number(&s.values, value, s.truthy(separator));
    return dup(s, try s.call(no_color, c.pi_js_undefined(),
        &.{ formatted, try s.text(if (bigint) "bigint" else "number") }));
}
fn convertedNumber(s: *Scope, owner: c.JSValue, value: c.JSValue,
    conversion: [*:0]const u8, inspect_options: c.JSValue) anyerror!c.JSValue
{
    const function = try member(s, owner, conversion);
    const converted = try expr(s, a.callBody, .{ function, c.pi_js_undefined(), @as([]const c.JSValue, &.{value}) });
    return dup(s, try expr(s, numericBody, .{ owner, converted, false, inspect_options }));
}
fn builtIn(s: *Scope, owner: c.JSValue, value: c.JSValue) anyerror!c.JSValue {
    const function = try s.get(owner, "classifier");
    return a.boolean(s, s.truthy(try s.call(function, c.pi_js_undefined(), &.{value})));
}
fn plainString(s: *Scope, owner: c.JSValue, value: c.JSValue) anyerror!c.JSValue {
    const function = try member(s, owner, "String");
    return dup(s, try s.call(function, c.pi_js_undefined(), &.{value}));
}
const Inspection = enum { ordinary, string, hidden };
fn inspection(s: *Scope, owner: c.JSValue, value: c.JSValue,
    mode: Inspection, inspect_options: c.JSValue) anyerror!c.JSValue
{
    const inspect = try s.get(owner, "inspect");
    var options = inspect_options;
    if (mode != .ordinary) {
        // Real CopyDataProperties includes symbols and per-key descriptor/Get
        // order. Overrides remain own data definitions, not inherited setters.
        options = try ops.spread(&s.values, inspect_options);
        if (mode == .string) {
            try s.define(options, "compact", number(s, 3), c.JS_PROP_C_W_E);
            try s.define(options, "colors", a.boolean(s, false), c.JS_PROP_C_W_E);
            try s.define(options, "depth", number(s, 0), c.JS_PROP_C_W_E);
        } else {
            try s.define(options, "showHidden", a.boolean(s, true), c.JS_PROP_C_W_E);
            try s.define(options, "showProxy", a.boolean(s, true), c.JS_PROP_C_W_E);
            try s.define(options, "depth", number(s, 4), c.JS_PROP_C_W_E);
        }
    }
    return dup(s, try s.call(inspect, c.pi_js_undefined(), &.{ value, options }));
}
fn stringArgument(s: *Scope, owner: c.JSValue, value: c.JSValue, inspect_options: c.JSValue) anyerror!c.JSValue {
    if (c.JS_IsNumber(value)) return numericBody(s, owner, value, false, inspect_options);
    if (c.JS_IsBigInt(value)) return numericBody(s, owner, value, true, inspect_options);
    if (!c.JS_IsObject(value) or c.JS_IsFunction(s.engine.context, value) or c.JS_IsNull(value) or
        !try a.condition(s.engine, builtIn, .{ owner, value }))
        return plainString(s, owner, value);
    return inspection(s, owner, value, .string, inspect_options);
}
fn numericArgument(s: *Scope, owner: c.JSValue, value: c.JSValue,
    kind: enum { decimal, integer, float }, inspect_options: c.JSValue) anyerror!c.JSValue
{
    if (kind != .float and c.JS_IsBigInt(value)) return numericBody(s, owner, value, true, inspect_options);
    if (c.JS_IsSymbol(value)) return dup(s, try s.text("NaN"));
    return convertedNumber(s, owner, value, switch (kind) {
        .decimal => "Number", .integer => "parseInt", .float => "parseFloat",
    }, inspect_options);
}
fn stringifyCall(s: *Scope, owner: c.JSValue, value: c.JSValue) anyerror!c.JSValue {
    const function = try member(s, owner, "stringify");
    return dup(s, try s.call(function, c.pi_js_undefined(), &.{value}));
}
fn splitErrorLine(s: *Scope, owner: c.JSValue, reason: c.JSValue) anyerror!c.JSValue {
    const split = try member(s, owner, "split");
    const message = try s.get(reason, "message");
    return dup(s, try s.call(split, message, &.{ try s.text("\n"), number(s, 1) }));
}
fn firstErrorLine(s: *Scope, owner: c.JSValue, reason: c.JSValue) anyerror!c.JSValue {
    const lines = try expr(s, splitErrorLine, .{ owner, reason });
    return dup(s, try s.getKey(lines, number(s, 0)));
}
fn cycleObject(s: *Scope) anyerror!c.JSValue { return dup(s, try s.object()); }
fn linkCycle(s: *Scope, value: c.JSValue) anyerror!c.JSValue {
    try s.put(value, "a", value);
    return c.pi_js_undefined();
}
fn calibrateCircular(s: *Scope, frame: *StringifyFrame, owner: c.JSValue) anyerror!c.JSValue {
    // This is the original try-block const a. An ordinary thrown call does
    // not erase its uncaptured local slot on entry to the matching catch.
    try frame.take(.cycle, a.expression(s.engine, cycleObject, .{}));
    _ = try a.expression(s.engine, linkCycle, .{frame.get(.cycle)});
    return a.expression(s.engine, stringifyCall, .{ owner, frame.get(.cycle) });
}
fn circularReady(s: *Scope, owner: c.JSValue) anyerror!c.JSValue {
    return a.boolean(s, s.truthy(try s.get(owner, "circularMessage")));
}
fn storeCircularLine(s: *Scope, owner: c.JSValue, reason: c.JSValue) anyerror!c.JSValue {
    const line = try expr(s, firstErrorLine, .{ owner, reason });
    try s.put(owner, "circularMessage", line);
    return c.pi_js_undefined();
}
fn typeErrorName(s: *Scope, reason: c.JSValue) anyerror!c.JSValue {
    const name = try s.get(reason, "name");
    return a.boolean(s, s.equal(name, try s.text("TypeError")));
}
fn sameCircularLine(s: *Scope, owner: c.JSValue, reason: c.JSValue) anyerror!c.JSValue {
    const line = try expr(s, firstErrorLine, .{ owner, reason });
    return a.boolean(s, s.equal(line, try s.get(owner, "circularMessage")));
}
fn stringifyAfterThrow(s: *Scope, frame: *StringifyFrame, owner: c.JSValue) anyerror!c.JSValue {
    if (!try a.condition(s.engine, circularReady, .{owner})) {
        const attempted = calibrateCircular(s, frame, owner);
        if (attempted) |value| {
            // The real toJSON/Set paths may make this call succeed. Its result
            // is discarded and the lazy message remains unchanged.
            var completion = a.owned.Completion.initVoid(s.engine, {});
            completion.release(value);
            try completion.finishVoid();
        } else |err| {
            try frame.take(.circular_error, caught(s.engine, err));
            _ = try a.expression(s.engine, storeCircularLine, .{ owner, frame.get(.circular_error) });
        }
    }
    if (try a.condition(s.engine, typeErrorName, .{frame.get(.reason)}) and
        try a.condition(s.engine, sameCircularLine, .{ owner, frame.get(.reason) }))
        return dup(s, try s.text("[Circular]"));
    return a.raise(s, frame.get(.reason));
}
fn stringifyBody(s: *Scope, frame: *StringifyFrame, owner: c.JSValue,
    value: c.JSValue) anyerror!c.JSValue
{
    return a.expression(s.engine, stringifyCall, .{ owner, value }) catch |err| {
        try frame.take(.reason, caught(s.engine, err));
        return stringifyAfterThrow(s, frame, owner);
    };
}
fn stringify(engine: *a.v.em.Engine, owner: c.JSValue, value: c.JSValue) anyerror!c.JSValue {
    var s = Scope.init(engine);
    const frame = StringifyFrame.create(&s.values) catch |err|
        return s.finish(@as(anyerror!c.JSValue, err));
    return a.finishFrame(&s, frame, stringifyBody(&s, frame, owner, value));
}
fn indexedStringify(s: *Scope, owner: c.JSValue, args: c.JSValue, index: usize) anyerror!c.JSValue {
    const value = try s.getKey(args, number(s, index));
    return stringify(s.engine, owner, value);
}
fn indexedInspection(s: *Scope, owner: c.JSValue, args: c.JSValue, index: usize,
    mode: Inspection, inspect_options: c.JSValue) anyerror!c.JSValue
{
    // The Source inspect callee is selected before the indexed argument and
    // before its following options literal.
    const inspect = try s.get(owner, "inspect");
    const value = try s.getKey(args, number(s, index));
    var options = inspect_options;
    if (mode == .hidden) {
        options = try ops.spread(&s.values, inspect_options);
        try s.define(options, "showHidden", a.boolean(s, true), c.JS_PROP_C_W_E);
        try s.define(options, "showProxy", a.boolean(s, true), c.JS_PROP_C_W_E);
        try s.define(options, "depth", number(s, 4), c.JS_PROP_C_W_E);
    }
    return dup(s, try s.call(inspect, c.pi_js_undefined(), &.{ value, options }));
}
fn appendTrailing(s: *Scope, owner: c.JSValue, current: c.JSValue,
    value: c.JSValue, inspect_options: c.JSValue) anyerror!c.JSValue
{
    const text = if (c.JS_IsString(value)) value else
        try expr(s, inspection, .{ owner, value, Inspection.ordinary, inspect_options });
    return dup(s, try a.add(s, current, text));
}
fn internalBody(s: *Scope, frame: *FormatFrame, owner: c.JSValue,
    args: c.JSValue, inspect_options: c.JSValue) anyerror!c.JSValue
{
    try frame.take(.first, a.expression(s.engine, indexed, .{ args, @as(usize, 0) }));
    var argument: usize = 0;
    try frame.take(.str, a.expression(s.engine, stringValue, .{""}));
    try frame.take(.join, a.expression(s.engine, stringValue, .{""}));
    if (c.JS_IsString(frame.get(.first))) {
        if (try a.condition(s.engine, lengthEqual, .{ args, @as(usize, 1) }))
            return dup(s, frame.get(.first));
        var last_position: usize = 0;
        var position: usize = 0;
        while (try a.condition(s.engine, moreCharacters, .{ frame.get(.first), position })) : (position += 1) {
            if (try charCode(s.engine, owner, frame.get(.first), position) != 37) continue;
            position += 1;
            const next = try charCode(s.engine, owner, frame.get(.first), position);
            if (!try a.condition(s.engine, lengthEqual, .{ args, argument + 1 })) {
                switch (next) {
                    115 => {
                        try frame.clear(.temp_arg);
                        argument += 1;
                        try frame.take(.temp_arg, a.expression(s.engine, indexed, .{ args, argument }));
                        try frame.take(.temp_str, a.expression(s.engine, stringArgument, .{ owner, frame.get(.temp_arg), inspect_options }));
                    },
                    106 => {
                        argument += 1;
                        try frame.take(.temp_str, a.expression(s.engine, indexedStringify, .{ owner, args, argument }));
                    },
                    100 => {
                        try frame.clear(.temp_num);
                        argument += 1;
                        try frame.take(.temp_num, a.expression(s.engine, indexed, .{ args, argument }));
                        try frame.take(.temp_str, a.expression(s.engine, numericArgument, .{ owner, frame.get(.temp_num), .decimal, inspect_options }));
                    },
                    79, 111 => {
                        argument += 1;
                        try frame.take(.temp_str, a.expression(s.engine, indexedInspection,
                            .{ owner, args, argument, if (next == 79) Inspection.ordinary else Inspection.hidden, inspect_options }));
                    },
                    105 => {
                        try frame.clear(.temp_integer);
                        argument += 1;
                        try frame.take(.temp_integer, a.expression(s.engine, indexed, .{ args, argument }));
                        try frame.take(.temp_str, a.expression(s.engine, numericArgument, .{ owner, frame.get(.temp_integer), .integer, inspect_options }));
                    },
                    102 => {
                        try frame.clear(.temp_float);
                        argument += 1;
                        try frame.take(.temp_float, a.expression(s.engine, indexed, .{ args, argument }));
                        try frame.take(.temp_str, a.expression(s.engine, numericArgument, .{ owner, frame.get(.temp_float), .float, inspect_options }));
                    },
                    99 => {
                        argument += 1;
                        try frame.take(.temp_str, a.expression(s.engine, stringValue, .{""}));
                    },
                    37 => {
                        try frame.take(.str, a.expression(s.engine, appendSlice,
                            .{ owner, frame.get(.str), frame.get(.first), last_position, @as(?usize, position) }));
                        last_position = position + 1;
                        continue;
                    },
                    else => continue,
                }
                if (last_position != position - 1)
                    try frame.take(.str, a.expression(s.engine, appendSlice,
                        .{ owner, frame.get(.str), frame.get(.first), last_position, @as(?usize, position - 1) }));
                try frame.take(.str, a.expression(s.engine, appendValue, .{ frame.get(.str), frame.get(.temp_str) }));
                last_position = position + 1;
            } else if (next == 37) {
                try frame.take(.str, a.expression(s.engine, appendSlice,
                    .{ owner, frame.get(.str), frame.get(.first), last_position, @as(?usize, position) }));
                last_position = position + 1;
            }
        }
        if (last_position != 0) {
            argument += 1;
            try frame.take(.join, a.expression(s.engine, stringValue, .{" "}));
            if (try a.condition(s.engine, lessThanLength, .{ frame.get(.first), last_position }))
                try frame.take(.str, a.expression(s.engine, appendSlice,
                    .{ owner, frame.get(.str), frame.get(.first), last_position, @as(?usize, null) }));
        }
    }
    while (try a.condition(s.engine, lessThanLength, .{ args, argument })) {
        // Plain loop lexical slots reset on actual body entry; the final
        // initialized value survives the false condition and terminal cleanup.
        try frame.clear(.trailing_value);
        try frame.take(.trailing_value, a.expression(s.engine, indexed, .{ args, argument }));
        try frame.take(.str, a.expression(s.engine, appendValue, .{ frame.get(.str), frame.get(.join) }));
        try frame.take(.str, a.expression(s.engine, appendTrailing,
            .{ owner, frame.get(.str), frame.get(.trailing_value), inspect_options }));
        try frame.take(.join, a.expression(s.engine, stringValue, .{" "}));
        argument += 1;
    }
    return dup(s, frame.get(.str));
}
