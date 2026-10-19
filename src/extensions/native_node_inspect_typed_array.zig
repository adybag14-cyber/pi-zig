// Copyright Joyent, Inc. and other Node contributors. MIT; retained Node LICENSE.
//! Actual Node 24.13 inspect typed-array helpers. The owner retains the original
//! primordial getters/constructors and the real formatter output is an Array.
//! Captured imports are supplied by the inspector's genuine early bootstrap.
const std = @import("std");
const a = @import("native_node_argument_values.zig");
const v = a.v;
const c = a.c;
const Scope = a.Scope;
const ops = @import("native_node_inspect_operations.zig");
const h = @import("native_node_tty_values.zig");
const f = @import("native_node_module_callable.zig");
const primitive = @import("native_node_util_inspect_primitive.zig");
const utf16 = @import("native_utf16.zig");
const arithmetic = @import("native_image_arithmetic.zig");
fn dup(s: *Scope, value: c.JSValue) c.JSValue { return a.duplicate(s.engine, value); }
fn expr(s: *Scope, comptime body: anytype, args: anytype) !c.JSValue { return s.own(try a.expression(s.engine, body, args)); }
fn binary(s: *Scope, operation: arithmetic.Operation, left: c.JSValue, right: c.JSValue) !c.JSValue { return s.binary(@intFromEnum(operation), left, right); }
fn imports(s: *Scope, owner: c.JSValue) !c.JSValue { return s.get(owner, "captured"); }
fn member(s: *Scope, owner: c.JSValue, name: [*:0]const u8) !c.JSValue { return s.get(try imports(s, owner), name); }
fn fieldCall(s: *Scope, owner: c.JSValue, name: [*:0]const u8, receiver: c.JSValue, args: []const c.JSValue) !c.JSValue {
    return s.call(try member(s, owner, name), receiver, args);
}
fn getterBody(s: *Scope, target: c.JSValue, property: c.JSValue) !c.JSValue {
    var item = try s.descriptor(target, property) orelse return error.RequiredActualInspectTypedArrayGetter;
    defer s.releaseDescriptor(&item);
    errdefer |err| ops.recordFailure(s.engine, err);
    if (!c.JS_IsFunction(s.engine.context, item.getter)) return error.RequiredActualInspectTypedArrayGetter;
    return dup(s, item.getter);
}
pub fn capture(engine: *v.em.Engine, global: c.JSValue) !c.JSValue { return a.expression(engine, captureBody, .{global}); }
fn captureBody(s: *Scope, global: c.JSValue) !c.JSValue {
    const result = try s.objectProto(c.pi_js_null());
    const uint8 = try s.get(global, "Uint8Array");
    const typed_prototype = try s.prototype(try s.get(uint8, "prototype"));
    const symbol = try s.get(global, "Symbol");
    const length = try expr(s, getterBody, .{typed_prototype, try s.text("length")});
    const tag = try expr(s, getterBody, .{typed_prototype, try s.get(symbol, "toStringTag")});
    try s.define(result, "length", length, c.JS_PROP_C_W_E);
    try s.define(result, "tag", tag, c.JS_PROP_C_W_E);
    const array = try s.get(global, "Array");
    try s.define(result, "Array", array, c.JS_PROP_C_W_E);
    try s.define(result, "push", try s.get(try s.get(array, "prototype"), "push"), c.JS_PROP_C_W_E);
    const math = try s.get(global, "Math");
    try s.define(result, "min", try s.get(math, "min"), c.JS_PROP_C_W_E);
    try s.define(result, "max", try s.get(math, "max"), c.JS_PROP_C_W_E);
    const string_prototype = try s.get(try s.get(global, "String"), "prototype");
    inline for (.{ "slice", "includes", "repeat", "replace" }) |name| try s.define(result, name, try s.get(string_prototype, name), c.JS_PROP_C_W_E);
    // The actual internal/util literal is created at the same early capture.
    const colors = try s.construct(s.engine.intrinsic_regexp_constructor, &.{ try s.text("\\u001b\\[\\d\\d?m"), try s.text("g") });
    try s.define(result, "colorRegExp", colors, c.JS_PROP_C_W_E);
    const constructors = try s.objectProto(c.pi_js_null());
    inline for (.{ "Uint8ClampedArray", "Uint8Array", "Int8Array", "Uint16Array", "Int16Array", "Uint32Array", "Int32Array", "Float16Array", "Float32Array", "Float64Array", "BigInt64Array", "BigUint64Array" }) |name| {
        try s.define(constructors, name, try s.get(global, name), c.JS_PROP_C_W_E);
    }
    try s.define(result, "constructors", constructors, c.JS_PROP_C_W_E);
    return dup(s, result);
}
pub fn create(engine: *v.em.Engine, captured: c.JSValue) !c.JSValue { return a.expression(engine, createBody, .{captured}); }
fn createBody(s: *Scope, captured: c.JSValue) !c.JSValue {
    if (!c.JS_IsObject(captured)) return error.RequiredActualInspectTypedArrayPrimordials;
    const result = try s.objectProto(c.pi_js_null());
    try s.define(result, "captured", captured, c.JS_PROP_C_W_E);
    try s.define(result, "formatNumber", try s.own(try f.create(s.engine, "formatNumber", 3, true, numberCall, &.{})), c.JS_PROP_C_W_E);
    try s.define(result, "formatBigInt", try s.own(try f.create(s.engine, "formatBigInt", 3, true, bigintCall, &.{})), c.JS_PROP_C_W_E);
    return dup(s, result);
}
fn numberCall(engine: *v.em.Engine, _: c.JSValue, args: []const c.JSValue, _: []const c.JSValue) !c.JSValue { return a.expression(engine, formattedBody, .{a.arg(args, 0), a.arg(args, 1), a.arg(args, 2), false}); }
fn bigintCall(engine: *v.em.Engine, _: c.JSValue, args: []const c.JSValue, _: []const c.JSValue) !c.JSValue { return a.expression(engine, formattedBody, .{a.arg(args, 0), a.arg(args, 1), a.arg(args, 2), true}); }
fn formattedBody(s: *Scope, stylizer: c.JSValue, value: c.JSValue, separator: c.JSValue, bigint: bool) !c.JSValue {
    const formatted = if (bigint) try primitive.bigint(&s.values, value, s.truthy(separator)) else try primitive.number(&s.values, value, s.truthy(separator));
    return dup(s, try s.call(stylizer, c.pi_js_undefined(), &.{formatted, try s.text(if (bigint) "bigint" else "number")}));
}
pub fn intrinsic(engine: *v.em.Engine, owner: c.JSValue, comptime name: [*:0]const u8, value: c.JSValue) !c.JSValue { return a.expression(engine, intrinsicBody, .{owner, name, value}); }
fn intrinsicBody(s: *Scope, owner: c.JSValue, name: [*:0]const u8, value: c.JSValue) !c.JSValue { return dup(s, try fieldCall(s, owner, name, value, &.{})); }
pub fn reconstruct(engine: *v.em.Engine, owner: c.JSValue, fallback: c.JSValue, value: c.JSValue) !c.JSValue { return a.expression(engine, reconstructBody, .{owner, fallback, value}); }
fn reconstructBody(s: *Scope, owner: c.JSValue, fallback: c.JSValue, value: c.JSValue) !c.JSValue {
    const constructors = try member(s, owner, "constructors");
    const constructor = try s.getKey(constructors, fallback);
    return dup(s, try s.construct(constructor, &.{value}));
}
pub fn prefix(engine: *v.em.Engine, constructor: c.JSValue, tag: c.JSValue, fallback: c.JSValue, size: c.JSValue) !c.JSValue { return a.expression(engine, prefixBody, .{constructor, tag, fallback, size}); }
fn positionBody(s: *Scope, constructor: c.JSValue, tag: c.JSValue) !c.JSValue {
    const method = try s.get(constructor, "indexOf");
    return dup(s, try s.call(method, constructor, &.{tag}));
}
fn lowerSuffixBody(s: *Scope, constructor: c.JSValue, end: c.JSValue) !c.JSValue {
    const second = try s.getKey(constructor, end);
    const method = try s.get(second, "toLowerCase");
    return dup(s, try s.call(method, second, &.{}));
}
fn tagSuffixBody(s: *Scope, constructor: c.JSValue, end: c.JSValue) !c.JSValue {
    if (s.equal(end, try s.get(constructor, "length"))) return a.boolean(s, false);
    const first = try s.getKey(constructor, end);
    const lowered = try expr(s, lowerSuffixBody, .{constructor, end});
    return a.boolean(s, s.equal(first, lowered));
}
fn prefixBody(s: *Scope, constructor: c.JSValue, tag: c.JSValue, fallback: c.JSValue, size: c.JSValue) !c.JSValue {
    const empty = try s.text("");
    if (c.JS_IsNull(constructor)) {
        var result = try a.add(s, try s.text("["), try s.toString(fallback));
        result = try a.add(s, result, try s.toString(size));
        result = try a.add(s, result, try s.text(": null prototype] "));
        if (!s.equal(tag, empty) and !s.equal(fallback, tag)) result = try a.add(s, result, try expr(s, tagTextBody, .{tag}));
        return dup(s, result);
    }
    var result = try a.add(s, try s.toString(constructor), try s.toString(size));
    result = try a.add(s, result, try s.text(" "));
    if (!s.equal(tag, empty)) {
        const position = try expr(s, positionBody, .{constructor, tag});
        var append_tag = s.equal(position, c.JS_NewInt32(s.engine.context, -1));
        if (!append_tag) {
            const end = try a.add(s, position, try s.get(tag, "length"));
            append_tag = try a.condition(s.engine, tagSuffixBody, .{constructor, end});
        }
        if (append_tag) result = try a.add(s, result, try expr(s, tagTextBody, .{tag}));
    }
    return dup(s, result);
}
fn tagTextBody(s: *Scope, tag: c.JSValue) !c.JSValue {
    return dup(s, try a.add(s, try a.add(s, try s.text("["), try s.toString(tag)), try s.text("] ")));
}
pub fn sizeText(engine: *v.em.Engine, size: c.JSValue) !c.JSValue { return a.expression(engine, sizeTextBody, .{size}); }
fn sizeTextBody(s: *Scope, size: c.JSValue) !c.JSValue { return dup(s, try a.add(s, try a.add(s, try s.text("("), try s.toString(size)), try s.text(")"))); }
pub fn lengthIsZero(engine: *v.em.Engine, value: c.JSValue) !bool { return a.condition(engine, lengthZeroBody, .{value}); }
fn lengthZeroBody(s: *Scope, value: c.JSValue) !c.JSValue { return a.boolean(s, s.equal(try s.get(value, "length"), c.JS_NewInt32(s.engine.context, 0))); }
pub fn beyondDepth(engine: *v.em.Engine, options: c.JSValue, recurse: usize) !bool { return a.condition(engine, depthBody, .{options, recurse}); }
fn greaterDepthBody(s: *Scope, options: c.JSValue, recurse: usize) !c.JSValue {
    return a.boolean(s, s.truthy(try binary(s, .greater, c.JS_NewFloat64(s.engine.context, @floatFromInt(recurse)), try s.get(options, "depth"))));
}
fn depthBody(s: *Scope, options: c.JSValue, recurse: usize) !c.JSValue {
    if (!try a.condition(s.engine, greaterDepthBody, .{options, recurse})) return a.boolean(s, false);
    return a.boolean(s, !c.JS_IsNull(try s.get(options, "depth")));
}
pub fn depthStyle(engine: *v.em.Engine, owner: c.JSValue, constructor: c.JSValue, tag: c.JSValue, actual_name: c.JSValue) !c.JSValue {
    return a.expression(engine, depthStyleBody, .{owner, constructor, tag, actual_name});
}
fn depthStyleBody(s: *Scope, owner: c.JSValue, constructor: c.JSValue, tag: c.JSValue, actual_name: c.JSValue) !c.JSValue {
    const fallback = if (c.JS_IsNull(constructor)) (if (s.equal(actual_name, tag)) try s.text("Object") else actual_name) else try s.text("");
    const style = try s.own(try prefix(s.engine, constructor, tag, fallback, try s.text("")));
    var name = try fieldCall(s, owner, "slice", style, &.{c.JS_NewInt32(s.engine.context, 0), c.JS_NewInt32(s.engine.context, -1)});
    if (!c.JS_IsNull(constructor)) name = try a.add(s, try a.add(s, try s.text("["), name), try s.text("]"));
    return dup(s, name);
}
/// V8's selected binding skips canonical array-index keys, preserving every
/// non-index string and Symbol in its original own-property order.
pub fn isIndex(engine: *v.em.Engine, atom: c.JSAtom) !bool {
    var s = Scope.init(engine);
    const result = indexBody(&s, atom);
    return c.JS_ToBool(engine.context, try s.finish(result)) == 1;
}
fn indexBody(s: *Scope, atom: c.JSAtom) !c.JSValue {
    const key = try ops.atomValue(&s.values, atom);
    if (!c.JS_IsString(key)) return a.boolean(s, false);
    const units = try utf16.unitsAlloc(s.engine, key); defer s.engine.gpa.free(units);
    if (units.len == 0 or (units.len > 1 and units[0] == '0')) return a.boolean(s, false);
    var index: u64 = 0;
    for (units) |unit| {
        if (unit < '0' or unit > '9' or index > std.math.maxInt(u32)) return a.boolean(s, false);
        index = index * 10 + unit - '0';
    }
    return a.boolean(s, index < std.math.maxInt(u32));
}
pub fn elements(engine: *v.em.Engine, owner: c.JSValue, options: c.JSValue, value: c.JSValue, length: c.JSValue) !c.JSValue {
    return a.expression(engine, elementsBody, .{owner, options, value, length});
}
fn maximumBody(s: *Scope, owner: c.JSValue, options: c.JSValue, length: c.JSValue) !c.JSValue {
    const minimum = try member(s, owner, "min");
    const maximum = try member(s, owner, "max");
    const low = try s.call(maximum, c.pi_js_undefined(), &.{c.JS_NewInt32(s.engine.context, 0), try s.get(options, "maxArrayLength")});
    return dup(s, try s.call(minimum, c.pi_js_undefined(), &.{low, length}));
}
fn remainingBody(s: *Scope, value: c.JSValue, maximum: c.JSValue) !c.JSValue { return dup(s, try binary(s, .subtract, try s.get(value, "length"), maximum)); }
fn positiveLengthBody(s: *Scope, value: c.JSValue) !c.JSValue {
    return a.boolean(s, s.truthy(try binary(s, .greater, try s.get(value, "length"), c.JS_NewInt32(s.engine.context, 0))));
}
fn numberElementBody(s: *Scope, value: c.JSValue) !c.JSValue { return a.boolean(s, c.JS_IsNumber(try s.getKey(value, c.JS_NewInt32(s.engine.context, 0)))); }
fn itemBody(s: *Scope, formatter: c.JSValue, options: c.JSValue, value: c.JSValue, index: u32) !c.JSValue {
    const stylize = try s.get(options, "stylize");
    const item = try s.getKey(value, c.JS_NewUint32(s.engine.context, index));
    const separator = try s.get(options, "numericSeparator");
    return dup(s, try s.call(formatter, c.pi_js_undefined(), &.{stylize, item, separator}));
}
fn setIndex(s: *Scope, output: c.JSValue, index: u32, value: c.JSValue) !void {
    try s.pending();
    const status = c.JS_SetPropertyUint32(s.engine.context, output, index, dup(s, value));
    try s.pending();
    if (status < 0) return error.MissingActualInspectTypedOutputReason;
}
fn writeItem(s: *Scope, output: c.JSValue, formatter: c.JSValue, options: c.JSValue, value: c.JSValue, index: u32) !c.JSValue {
    const formatted = try expr(s, itemBody, .{formatter, options, value, index});
    try setIndex(s, output, index, formatted);
    return c.pi_js_undefined();
}
fn remainderText(s: *Scope, remaining: c.JSValue) !c.JSValue {
    var result = try a.add(s, try s.text("... "), try s.toString(remaining));
    result = try a.add(s, result, try s.text(" more item"));
    result = try a.add(s, result, try s.text(if (s.truthy(try binary(s, .greater, remaining, c.JS_NewInt32(s.engine.context, 1)))) "s" else ""));
    return dup(s, result);
}
fn writeRemainder(s: *Scope, output: c.JSValue, index: u32, remaining: c.JSValue) !c.JSValue {
    try setIndex(s, output, index, try expr(s, remainderText, .{remaining}));
    return c.pi_js_undefined();
}
fn elementsBody(s: *Scope, owner: c.JSValue, options: c.JSValue, value: c.JSValue, length: c.JSValue) !c.JSValue {
    const maximum = try expr(s, maximumBody, .{owner, options, length});
    const remaining = try expr(s, remainingBody, .{value, maximum});
    const output = try s.construct(try member(s, owner, "Array"), &.{maximum});
    const numeric = try a.condition(s.engine, positiveLengthBody, .{value}) and try a.condition(s.engine, numberElementBody, .{value});
    const formatter = try s.get(owner, if (numeric) "formatNumber" else "formatBigInt");
    const take = try ops.float64(&s.values, maximum);
    var index: u32 = 0;
    while (@as(f64, @floatFromInt(index)) < take) : (index += 1) {
        _ = try a.expression(s.engine, writeItem, .{output, formatter, options, value, index});
    }
    if (s.truthy(try binary(s, .greater, remaining, c.JS_NewInt32(s.engine.context, 0)))) {
        _ = try a.expression(s.engine, writeRemainder, .{output, index, remaining});
    }
    return dup(s, output);
}
pub fn append(engine: *v.em.Engine, owner: c.JSValue, output: c.JSValue, formatted: c.JSValue) !void { _ = try a.expression(engine, appendBody, .{owner, output, formatted}); }
fn appendBody(s: *Scope, owner: c.JSValue, output: c.JSValue, formatted: c.JSValue) !c.JSValue { _ = try fieldCall(s, owner, "push", output, &.{formatted}); return c.pi_js_undefined(); }

// The selected ungrouped reduceToSingleString path uses the real output Array;
// repeated element reads and the internal util.join additions remain visible.
fn lengthLessBody(s: *Scope, output: c.JSValue, index: u32) !c.JSValue {
    return a.boolean(s, s.truthy(try binary(s, .less, c.JS_NewUint32(s.engine.context, index), try s.get(output, "length"))));
}
fn itemLengthBody(s: *Scope, output: c.JSValue, index: u32) !c.JSValue {
    const item = try s.getKey(output, c.JS_NewUint32(s.engine.context, index));
    return dup(s, try s.get(item, "length"));
}
fn removeColorsBody(s: *Scope, owner: c.JSValue, output: c.JSValue, index: u32) !c.JSValue {
    const item = try s.getKey(output, c.JS_NewUint32(s.engine.context, index));
    return dup(s, try fieldCall(s, owner, "replace", item, &.{try member(s, owner, "colorRegExp"), try s.text("")}));
}
fn colorLengthBody(s: *Scope, owner: c.JSValue, output: c.JSValue, index: u32) !c.JSValue {
    const stripped = try expr(s, removeColorsBody, .{owner, output, index});
    return dup(s, try s.get(stripped, "length"));
}
fn addItemLengthBody(s: *Scope, total: c.JSValue, owner: c.JSValue, options: c.JSValue, output: c.JSValue, index: u32) !c.JSValue {
    const length = if (try a.condition(s.engine, a.fieldTruthy, .{options, "colors"}))
        try expr(s, colorLengthBody, .{owner, output, index})
    else
        try expr(s, itemLengthBody, .{output, index});
    return dup(s, try a.add(s, total, length));
}
fn exceedsBody(s: *Scope, total: c.JSValue, options: c.JSValue) !c.JSValue {
    return a.boolean(s, s.truthy(try binary(s, .greater, total, try s.get(options, "breakLength"))));
}
fn exceedsInitialBody(s: *Scope, total: c.JSValue, output: c.JSValue, options: c.JSValue) !c.JSValue {
    return a.boolean(s, s.truthy(try binary(s, .greater, try a.add(s, total, try s.get(output, "length")), try s.get(options, "breakLength"))));
}
fn belowBody(s: *Scope, owner: c.JSValue, options: c.JSValue, output: c.JSValue, start: c.JSValue) !c.JSValue {
    var total = try a.add(s, try s.get(output, "length"), start);
    if (try a.condition(s.engine, exceedsInitialBody, .{total, output, options})) return a.boolean(s, false);
    var index: u32 = 0;
    while (try a.condition(s.engine, lengthLessBody, .{output, index})) : (index += 1) {
        total = try expr(s, addItemLengthBody, .{total, owner, options, output, index});
        if (try a.condition(s.engine, exceedsBody, .{total, options})) return a.boolean(s, false);
    }
    // This typed-array formatter has the Source empty base string.
    return a.boolean(s, true);
}
fn joinItemBody(s: *Scope, previous: c.JSValue, output: c.JSValue, index: c.JSValue) !c.JSValue {
    return dup(s, try a.add(s, previous, try s.getKey(output, index)));
}
fn joinBody(s: *Scope, output: c.JSValue, separator: c.JSValue) !c.JSValue {
    var string = try s.text("");
    if (!s.equal(try s.get(output, "length"), c.JS_NewInt32(s.engine.context, 0))) {
        const last = try binary(s, .subtract, try s.get(output, "length"), c.JS_NewInt32(s.engine.context, 1));
        var index: u32 = 0;
        while (s.truthy(try binary(s, .less, c.JS_NewUint32(s.engine.context, index), last))) : (index += 1) {
            string = try expr(s, joinItemBody, .{string, output, c.JS_NewUint32(s.engine.context, index)});
            string = try a.add(s, string, separator);
        }
        string = try expr(s, joinItemBody, .{string, output, last});
    }
    return dup(s, string);
}
fn includesNewlineBody(s: *Scope, owner: c.JSValue, joined: c.JSValue) !c.JSValue {
    return a.boolean(s, s.truthy(try fieldCall(s, owner, "includes", joined, &.{try s.text("\n")})));
}
fn compactTrueBody(s: *Scope, options: c.JSValue) !c.JSValue {
    return a.boolean(s, s.equal(try s.get(options, "compact"), c.pi_js_bool(s.engine.context, 1)));
}
fn compactNumericBody(s: *Scope, options: c.JSValue) !c.JSValue {
    if (!c.JS_IsNumber(try s.get(options, "compact"))) return a.boolean(s, false);
    return a.boolean(s, s.truthy(try binary(s, .greater_equal, try s.get(options, "compact"), c.JS_NewInt32(s.engine.context, 1))));
}
fn withinCompactBody(s: *Scope, options: c.JSValue, output: c.JSValue, entries: c.JSValue, current_depth: usize, recurse: usize) !c.JSValue {
    const difference = try binary(s, .subtract, c.JS_NewFloat64(s.engine.context, @floatFromInt(current_depth)), c.JS_NewFloat64(s.engine.context, @floatFromInt(recurse)));
    if (!s.truthy(try binary(s, .less, difference, try s.get(options, "compact")))) return a.boolean(s, false);
    return a.boolean(s, s.equal(entries, try s.get(output, "length")));
}
fn startBody(s: *Scope, output: c.JSValue, open: c.JSValue, indentation: usize) !c.JSValue {
    var result = try a.add(s, try s.get(output, "length"), c.JS_NewFloat64(s.engine.context, @floatFromInt(indentation)));
    result = try a.add(s, result, try s.get(open, "length"));
    result = try a.add(s, result, c.JS_NewInt32(s.engine.context, 0));
    return dup(s, try a.add(s, result, c.JS_NewInt32(s.engine.context, 10)));
}
fn sameLineBody(s: *Scope, open: c.JSValue, joined: c.JSValue, close: c.JSValue) !c.JSValue {
    var result = try a.add(s, try s.toString(open), try s.text(" "));
    result = try a.add(s, result, try s.toString(joined));
    result = try a.add(s, result, try s.text(" "));
    return dup(s, try a.add(s, result, try s.toString(close)));
}
fn repeatedIndentBody(s: *Scope, owner: c.JSValue, indentation: usize) !c.JSValue {
    const count = c.JS_NewFloat64(s.engine.context, @floatFromInt(indentation));
    return dup(s, try fieldCall(s, owner, "repeat", try s.text(" "), &.{count}));
}
pub fn layout(engine: *v.em.Engine, owner: c.JSValue, options: c.JSValue, output: c.JSValue, open: c.JSValue, close: c.JSValue, indentation: usize, current_depth: usize, recurse: usize) !c.JSValue {
    return a.expression(engine, layoutBody, .{owner, options, output, open, close, indentation, current_depth, recurse});
}
fn layoutBody(s: *Scope, owner: c.JSValue, options: c.JSValue, output: c.JSValue, open: c.JSValue, close: c.JSValue, indentation: usize, current_depth: usize, recurse: usize) !c.JSValue {
    if (try a.condition(s.engine, a.fieldTruthy, .{options, "sorted"})) return error.RequiredActualInspectSortedLayout;
    if (!try a.condition(s.engine, compactTrueBody, .{options})) {
        if (try a.condition(s.engine, compactNumericBody, .{options})) {
            const entries = try s.get(output, "length");
            if (s.truthy(try binary(s, .greater, entries, c.JS_NewInt32(s.engine.context, 6)))) return error.RequiredActualInspectGroupedArrayLayout;
            if (try a.condition(s.engine, withinCompactBody, .{options, output, entries, current_depth, recurse})) {
                const start = try expr(s, startBody, .{output, open, indentation});
                if (try a.condition(s.engine, belowBody, .{owner, options, output, start})) {
                    const joined = try expr(s, joinBody, .{output, try s.text(", ")});
                    if (!try a.condition(s.engine, includesNewlineBody, .{owner, joined})) return sameLineBody(s, open, joined, close);
                }
            }
        }
        const indent = try a.add(s, try s.text("\n"), try expr(s, repeatedIndentBody, .{owner, indentation}));
        var result = try a.add(s, try s.toString(open), try s.toString(indent));
        result = try a.add(s, result, try s.text("  "));
        const separator = try a.add(s, try a.add(s, try s.text(","), try s.toString(indent)), try s.text("  "));
        const joined = try expr(s, joinBody, .{output, separator});
        var tail = try a.add(s, try s.toString(joined), try s.toString(indent));
        tail = try a.add(s, tail, try s.toString(close));
        return dup(s, try a.add(s, result, tail));
    }
    if (try a.condition(s.engine, belowBody, .{owner, options, output, c.JS_NewInt32(s.engine.context, 0)})) {
        const joined = try expr(s, joinBody, .{output, try s.text(", ")});
        return sameLineBody(s, open, joined, close);
    }
    const indent = try expr(s, repeatedIndentBody, .{owner, indentation});
    const line = if (s.equal(try s.get(open, "length"), c.JS_NewInt32(s.engine.context, 1))) try s.text(" ") else try a.add(s, try a.add(s, try s.text("\n"), try s.toString(indent)), try s.text("  "));
    var result = try a.add(s, try s.toString(open), try s.toString(line));
    const separator = try a.add(s, try a.add(s, try s.text(",\n"), try s.toString(indent)), try s.text("  "));
    result = try a.add(s, result, try s.toString(try expr(s, joinBody, .{output, separator})));
    result = try a.add(s, result, try s.text(" "));
    return dup(s, try a.add(s, result, try s.toString(close)));
}
