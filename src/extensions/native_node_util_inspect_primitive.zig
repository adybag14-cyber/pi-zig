//! Node24 internal/util/inspect primitive algorithms. Independent of the event
//! diagnostic formatter; no live global String or guest numeric conversion.
const std = @import("std");
const v = @import("native_ai_provider_values.zig");
const c = v.c;
const h = @import("native_node_tty_values.zig");
const utf16 = @import("native_utf16.zig");
pub const Options = struct {
    numeric_separator: bool = false,
    max_string_length: ?usize = 10000,
    compact_true: bool = false,
    break_length: f64 = 80,
    indentation: usize = 0,
};
fn owned(s: *v.Scope, units: []const u16) !c.JSValue { return s.own(try h.success(s.engine, try utf16.string(s.engine, units))); }
fn text(s: *v.Scope, value: c.JSValue) !c.JSValue { return s.own(try h.success(s.engine, try s.engine.checked(c.JS_ToString(s.engine.context, value)))); }
fn escaped(out: *std.ArrayList(u16), allocator: std.mem.Allocator, units: []const u16) !void {
    var single = false; var double = false; var backtick = false; var interpolation = false;
    for (units, 0..) |unit, i| {
        single = single or unit == '\''; double = double or unit == '"'; backtick = backtick or unit == '`';
        interpolation = interpolation or (unit == '$' and i + 1 < units.len and units[i + 1] == '{');
    }
    const delimiter: u16 = if (!single) '\'' else if (!double) '"' else if (!backtick and !interpolation) '`' else '\'';
    try out.append(allocator, delimiter);
    const hex = "0123456789abcdef";
    var i: usize = 0;
    while (i < units.len) : (i += 1) {
        const unit = units[i];
        if (unit >= 0xd800 and unit <= 0xdbff and i + 1 < units.len and units[i + 1] >= 0xdc00 and units[i + 1] <= 0xdfff) {
            try out.appendSlice(allocator, units[i .. i + 2]); i += 1; continue;
        }
        if (unit == delimiter or unit == '\\') {
            try out.appendSlice(allocator, &.{ '\\', unit });
        } else if (unit == 8 or unit == 9 or unit == 10 or unit == 11 or unit == 12 or unit == 13) {
            try out.appendSlice(allocator, &.{ '\\', switch (unit) { 8 => 'b', 9 => 't', 10 => 'n', 11 => 'v', 12 => 'f', 13 => 'r', else => unreachable } });
        } else if (unit < 32 or (unit >= 127 and unit < 160)) {
            try out.appendSlice(allocator, &.{ '\\', 'x', hex[(unit >> 4) & 15], hex[unit & 15] });
        } else if (unit >= 0xd800 and unit <= 0xdfff) {
            try out.appendSlice(allocator, &.{ '\\', 'u', hex[(unit >> 12) & 15], hex[(unit >> 8) & 15], hex[(unit >> 4) & 15], hex[unit & 15] });
        } else try out.append(allocator, unit);
    }
    try out.append(allocator, delimiter);
}
pub fn quote(s: *v.Scope, value: c.JSValue) !c.JSValue {
    const units = try utf16.unitsAlloc(s.engine, value); defer s.engine.gpa.free(units);
    var out: std.ArrayList(u16) = .empty; defer out.deinit(s.engine.gpa);
    try escaped(&out, s.engine.gpa, units); return owned(s, out.items);
}
fn separator(out: *std.ArrayList(u16), allocator: std.mem.Allocator, units: []const u16, from_end: bool) !void {
    const start: usize = if (units.len > 0 and units[0] == '-') 1 else 0;
    for (units, 0..) |unit, i| {
        if (i > start and (if (from_end) (units.len - i) % 3 == 0 else (i - start) % 3 == 0)) try out.append(allocator, '_');
        try out.append(allocator, unit);
    }
}
pub fn number(s: *v.Scope, value: c.JSValue, numeric_separator: bool) !c.JSValue {
    var numeric: f64 = 0; if (c.JS_ToFloat64(s.engine.context, &numeric, value) < 0) return v.js.capture(s.engine);
    if (!numeric_separator and numeric == 0 and std.math.signbit(numeric)) return s.text("-0");
    const formatted = try text(s, value);
    if (!numeric_separator) return formatted;
    const units = try utf16.unitsAlloc(s.engine, formatted); defer s.engine.gpa.free(units);
    var out: std.ArrayList(u16) = .empty; defer out.deinit(s.engine.gpa);
    if (@trunc(numeric) == numeric) {
        if (!std.math.isFinite(numeric) or std.mem.indexOfScalar(u16, units, 'e') != null) return formatted;
        try separator(&out, s.engine.gpa, units, true);
    } else {
        if (std.math.isNan(numeric)) return formatted;
        // Exact slice behavior when decimalIndex is -1 is intentional: Source
        // does not special-case a nonintegral exponential representation.
        const index = std.mem.indexOfScalar(u16, units, '.');
        const integer_end = index orelse (units.len -| 1);
        const fraction_start = if (index) |at| at + 1 else 0;
        try separator(&out, s.engine.gpa, units[0..integer_end], true);
        try out.append(s.engine.gpa, '.');
        try separator(&out, s.engine.gpa, units[fraction_start..], false);
    }
    return owned(s, out.items);
}
pub fn bigint(s: *v.Scope, value: c.JSValue, numeric_separator: bool) !c.JSValue {
    const formatted = try text(s, value);
    if (!numeric_separator) return h.binary(s, .add, formatted, try s.text("n"));
    const units = try utf16.unitsAlloc(s.engine, formatted); defer s.engine.gpa.free(units);
    var out: std.ArrayList(u16) = .empty; defer out.deinit(s.engine.gpa);
    try separator(&out, s.engine.gpa, units, true); try out.append(s.engine.gpa, 'n'); return owned(s, out.items);
}
pub fn string(s: *v.Scope, value: c.JSValue, options: Options, stylize: c.JSValue) !c.JSValue {
    const units = try utf16.unitsAlloc(s.engine, value); defer s.engine.gpa.free(units);
    const take = if (options.max_string_length) |limit| @min(limit, units.len) else units.len;
    const body = units[0..take];
    var out: std.ArrayList(u16) = .empty; defer out.deinit(s.engine.gpa);
    var result: c.JSValue = undefined;
    if (!options.compact_true and body.len > 16 and @as(f64, @floatFromInt(body.len)) > options.break_length - @as(f64, @floatFromInt(options.indentation)) - 4) {
        var lines: std.ArrayList(c.JSValue) = .empty; defer lines.deinit(s.engine.gpa);
        var start: usize = 0; var i: usize = 0;
        while (i < body.len) : (i += 1) if (body[i] == '\n' and i + 1 < body.len) {
            out.clearRetainingCapacity(); try escaped(&out, s.engine.gpa, body[start .. i + 1]);
            try lines.append(s.engine.gpa, try h.call(s, stylize, c.pi_js_undefined(), &.{ try owned(s, out.items), try s.text("string") }));
            start = i + 1;
        };
        out.clearRetainingCapacity(); try escaped(&out, s.engine.gpa, body[start..]);
        try lines.append(s.engine.gpa, try h.call(s, stylize, c.pi_js_undefined(), &.{ try owned(s, out.items), try s.text("string") }));
        out.clearRetainingCapacity(); try out.appendSlice(s.engine.gpa, &.{ ' ', '+', '\n' }); try out.appendNTimes(s.engine.gpa, ' ', options.indentation + 2);
        const join = try owned(s, out.items); result = try s.text("");
        // Array.map finishes every stylize call before Array.join performs its
        // string-hint coercions. Retained return values belong to Scope.
        for (lines.items, 0..) |line, index| {
            if (index != 0) result = try h.binary(s, .add, result, join);
            if (!v.nullish(line)) result = try h.binary(s, .add, result, try text(s, line));
        }
    } else {
        try escaped(&out, s.engine.gpa, body);
        result = try h.call(s, stylize, c.pi_js_undefined(), &.{ try owned(s, out.items), try s.text("string") });
    }
    if (take < units.len) {
        const count = units.len - take;
        const trailer = try std.fmt.allocPrint(s.engine.gpa, "... {d} more character{s}", .{ count, if (count > 1) "s" else "" }); defer s.engine.gpa.free(trailer);
        result = try h.binary(s, .add, result, try s.text(trailer));
    } else result = try h.binary(s, .add, result, try s.text(""));
    return result;
}
