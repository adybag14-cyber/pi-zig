//! Source terminal column slices, OSC8 lookup and line composition over lossless UTF16.
const std = @import("std");
const js = @import("native_js_values.zig");
const c = js.c;
const v = @import("native_select_list.zig");
const utf16 = @import("native_utf16.zig");
const terminal = @import("../tui/utf16_terminal.zig");
const graphemes = @import("../tui/utf16_graphemes.zig");
const List = std.ArrayList(u16);
const sgr_start = std.unicode.utf8ToUtf16LeStringLiteral("\x1b[");
const osc_start = std.unicode.utf8ToUtf16LeStringLiteral("\x1b]8;");
const Style = struct {
    gpa: std.mem.Allocator,
    flags: [8]bool = @splat(false),
    fg: ?[]u16 = null,
    bg: ?[]u16 = null,
    hyperlink: ?[]u16 = null,
    fn reset(self: *Style) void {
        self.flags = @splat(false);
        if (self.fg) |value| self.gpa.free(value);
        if (self.bg) |value| self.gpa.free(value);
        self.fg = null;
        self.bg = null;
    }
    fn deinit(self: *Style) void {
        self.reset();
        if (self.hyperlink) |value| self.gpa.free(value);
    }
    fn replace(self: *Style, slot: *?[]u16, value: ?[]const u16) !void {
        const owned = if (value) |units| try self.gpa.dupe(u16, units) else null;
        if (slot.*) |old| self.gpa.free(old);
        slot.* = owned;
    }
    fn process(self: *Style, sequence: []const u16) !void {
        if (std.mem.startsWith(u16, sequence, osc_start)) {
            const ending: usize = if (sequence[sequence.len - 1] == 7) 1 else 2;
            const body = sequence[4 .. sequence.len - ending];
            const split = std.mem.indexOfScalar(u16, body, ';') orelse return;
            try self.replace(&self.hyperlink, if (split + 1 < body.len) sequence else null);
            return;
        }
        if (!std.mem.startsWith(u16, sequence, sgr_start) or sequence[sequence.len - 1] != 'm') return;
        const body = sequence[2 .. sequence.len - 1];
        for (body) |unit| if (unit != ';' and (unit < '0' or unit > '9')) return;
        if (body.len == 0 or std.mem.eql(u16, body, &.{'0'})) {
            self.reset();
            return;
        }
        var parts: std.ArrayList([]const u16) = .empty;
        defer parts.deinit(self.gpa);
        var splitter = std.mem.splitScalar(u16, body, ';');
        while (splitter.next()) |part| try parts.append(self.gpa, part);
        var index: usize = 0;
        while (index < parts.items.len) : (index += 1) {
            const code = number(parts.items[index]) orelse continue;
            if ((code == 38 or code == 48) and index + 2 < parts.items.len) {
                const mode = parts.items[index + 1];
                const count: usize = if (std.mem.eql(u16, mode, &.{'5'})) 3 else if (std.mem.eql(u16, mode, &.{'2'}) and index + 4 < parts.items.len) 5 else 0;
                if (count != 0) {
                    const first = parts.items[index];
                    const last = parts.items[index + count - 1];
                    const length = (@intFromPtr(last.ptr) - @intFromPtr(first.ptr)) / @sizeOf(u16) + last.len;
                    try self.replace(if (code == 38) &self.fg else &self.bg, first.ptr[0..length]);
                    index += count - 1;
                    continue;
                }
            }
            switch (code) {
                0 => self.reset(),
                1...5 => self.flags[code - 1] = true,
                7...9 => self.flags[code - 2] = true,
                21 => self.flags[0] = false,
                22 => {
                    self.flags[0] = false;
                    self.flags[1] = false;
                },
                23...25 => self.flags[code - 21] = false,
                27...29 => self.flags[code - 22] = false,
                39 => try self.replace(&self.fg, null),
                49 => try self.replace(&self.bg, null),
                30...37, 90...97, 40...47, 100...107 => {
                    var buffer: [5]u8 = undefined;
                    const bytes = try std.fmt.bufPrint(&buffer, "{d}", .{code});
                    var units: [5]u16 = undefined;
                    for (bytes, 0..) |byte, at| units[at] = byte;
                    try self.replace(if (code < 40 or (code >= 90 and code <= 97)) &self.fg else &self.bg, units[0..bytes.len]);
                },
                else => {},
            }
        }
    }
    fn update(self: *Style, units: []const u16) !void {
        var index: usize = 0;
        while (index < units.len) {
            const count = terminal.ansiLength(units, index);
            if (count != 0) {
                try self.process(units[index..][0..count]);
                index += count;
            } else index += 1;
        }
    }
    fn active(self: *const Style, target: *List) !void {
        var codes: List = .empty;
        defer codes.deinit(self.gpa);
        for (self.flags, [_]u16{ 1, 2, 3, 4, 5, 7, 8, 9 }) |enabled, code| if (enabled) {
            if (codes.items.len > 0) try codes.append(self.gpa, ';');
            try codes.append(self.gpa, '0' + code);
        };
        for ([_]?[]u16{ self.fg, self.bg }) |value| if (value) |color| {
            if (codes.items.len > 0) try codes.append(self.gpa, ';');
            try codes.appendSlice(self.gpa, color);
        };
        if (codes.items.len > 0) {
            try target.appendSlice(self.gpa, sgr_start);
            try target.appendSlice(self.gpa, codes.items);
            try target.append(self.gpa, 'm');
        }
        if (self.hyperlink) |link| try target.appendSlice(self.gpa, link);
    }
    fn closeLine(self: *const Style, target: *List) !void {
        if (self.flags[3]) try target.appendSlice(self.gpa, std.unicode.utf8ToUtf16LeStringLiteral("\x1b[24m"));
        if (self.hyperlink) |link| try target.appendSlice(self.gpa, if (link[link.len - 1] == 7) std.unicode.utf8ToUtf16LeStringLiteral("\x1b]8;;\x07") else std.unicode.utf8ToUtf16LeStringLiteral("\x1b]8;;\x1b\\"));
    }
};
fn number(units: []const u16) ?usize {
    if (units.len == 0) return null;
    var value: usize = 0;
    for (units) |unit| {
        if (unit < '0' or unit > '9') return null;
        value = std.math.mul(usize, value, 10) catch return null;
        value = std.math.add(usize, value, unit - '0') catch return null;
    }
    return value;
}
const Fragment = struct {
    text: []u16,
    width: f64,
    fn deinit(self: Fragment, gpa: std.mem.Allocator) void {
        gpa.free(self.text);
    }
};
fn slice(engine: *js.Engine, line: []const u16, start: f64, length: f64, strict: bool) !Fragment {
    const gpa = engine.gpa;
    if (length <= 0) return .{ .text = try gpa.dupe(u16, &.{}), .width = 0 };
    const end = start + length;
    var output: List = .empty;
    errdefer output.deinit(gpa);
    var pending: List = .empty;
    defer pending.deinit(gpa);
    var current: f64 = 0;
    var visible: f64 = 0;
    var index: usize = 0;
    while (index < line.len) {
        const ansi = terminal.ansiLength(line, index);
        if (ansi != 0) {
            if (current >= start and current < end) {
                try output.appendSlice(gpa, pending.items);
                pending.clearRetainingCapacity();
                try output.appendSlice(gpa, line[index..][0..ansi]);
            } else if (current < start) try pending.appendSlice(gpa, line[index..][0..ansi]);
            index += ansi;
            continue;
        }
        var text_end = index;
        while (text_end < line.len and terminal.ansiLength(line, text_end) == 0) : (text_end += 1) {}
        var iterator: graphemes.Iterator = .{ .text = line[index..text_end] };
        while (iterator.next()) |segment| {
            const cluster = line[index + segment.start .. index + segment.end];
            const width: f64 = @floatFromInt(try terminal.graphemeWidth(gpa, cluster));
            if (current >= start and current < end and (!strict or current + width <= end)) {
                try output.appendSlice(gpa, pending.items);
                pending.clearRetainingCapacity();
                try output.appendSlice(gpa, cluster);
                visible += width;
            }
            current += width;
            if (current >= end) break;
        }
        index = text_end;
        if (current >= end) break;
    }
    return .{ .text = try output.toOwnedSlice(gpa), .width = visible };
}
const Segments = struct {
    before: List = .empty,
    after: List = .empty,
    before_width: f64 = 0,
    after_width: f64 = 0,
    fn deinit(self: *Segments, gpa: std.mem.Allocator) void {
        self.before.deinit(gpa);
        self.after.deinit(gpa);
    }
};
fn extract(engine: *js.Engine, line: []const u16, before_end: f64, after_start: f64, after_length: f64) !Segments {
    const gpa = engine.gpa;
    var result: Segments = .{};
    errdefer result.deinit(gpa);
    var pending: List = .empty;
    defer pending.deinit(gpa);
    var tracker: Style = .{ .gpa = gpa };
    defer tracker.deinit();
    var current: f64 = 0;
    var index: usize = 0;
    var after_started = false;
    const after_end = after_start + after_length;
    while (index < line.len) {
        const ansi = terminal.ansiLength(line, index);
        if (ansi != 0) {
            const code = line[index..][0..ansi];
            try tracker.process(code);
            if (current < before_end) try pending.appendSlice(gpa, code) else if (current >= after_start and current < after_end and (after_started or std.mem.startsWith(u16, code, &.{ 0x1b, '_' }))) try result.after.appendSlice(gpa, code);
            index += ansi;
            continue;
        }
        var text_end = index;
        while (text_end < line.len and terminal.ansiLength(line, text_end) == 0) : (text_end += 1) {}
        var iterator: graphemes.Iterator = .{ .text = line[index..text_end] };
        while (iterator.next()) |segment| {
            const cluster = line[index + segment.start .. index + segment.end];
            const width: f64 = @floatFromInt(try terminal.graphemeWidth(gpa, cluster));
            if (current < before_end and current + width <= before_end) {
                try result.before.appendSlice(gpa, pending.items);
                pending.clearRetainingCapacity();
                try result.before.appendSlice(gpa, cluster);
                result.before_width += width;
            } else if (current >= after_start and current < after_end and current + width <= after_end) {
                if (!after_started) {
                    try tracker.active(&result.after);
                    after_started = true;
                }
                try result.after.appendSlice(gpa, cluster);
                result.after_width += width;
            }
            current += width;
            if (if (after_length <= 0) current >= before_end else current >= after_end) break;
        }
        index = text_end;
        if (if (after_length <= 0) current >= before_end else current >= after_end) break;
    }
    return result;
}
fn appendSpaces(engine: *js.Engine, target: *List, count: f64) !void {
    const space = try v.text(engine, " ");
    defer engine.freeValue(space);
    const repeated = try js.invoke(engine, space, "repeat", &.{v.numeric(engine, count)});
    defer engine.freeValue(repeated);
    const units = try utf16.unitsAlloc(engine, repeated);
    defer engine.gpa.free(units);
    try target.appendSlice(engine.gpa, units);
}
pub fn composite(engine: *js.Engine, base: []const u16, overlay: []const u16, start: f64, overlay_width: f64, total: f64) !c.JSValue {
    const after_start = start + overlay_width;
    var segments = try extract(engine, base, start, after_start, total - after_start);
    defer segments.deinit(engine.gpa);
    const foreground = try slice(engine, overlay, 0, overlay_width, true);
    defer foreground.deinit(engine.gpa);
    const before_pad = v.maximum(0, start - segments.before_width);
    const overlay_pad = v.maximum(0, overlay_width - foreground.width);
    const actual_before = v.maximum(start, segments.before_width);
    const actual_overlay = v.maximum(overlay_width, foreground.width);
    const after_target = v.maximum(0, total - actual_before - actual_overlay);
    const after_pad = v.maximum(0, after_target - segments.after_width);
    var output: List = .empty;
    defer output.deinit(engine.gpa);
    const reset = std.unicode.utf8ToUtf16LeStringLiteral("\x1b[0m\x1b]8;;\x07");
    try output.appendSlice(engine.gpa, segments.before.items);
    try appendSpaces(engine, &output, before_pad);
    try output.appendSlice(engine.gpa, reset);
    try output.appendSlice(engine.gpa, foreground.text);
    try appendSpaces(engine, &output, overlay_pad);
    try output.appendSlice(engine.gpa, reset);
    try output.appendSlice(engine.gpa, segments.after.items);
    try appendSpaces(engine, &output, after_pad);
    if (@as(f64, @floatFromInt(try terminal.visibleWidth(engine.gpa, output.items))) <= total) return utf16.string(engine, output.items);
    const clipped = try slice(engine, output.items, 0, total, true);
    defer clipped.deinit(engine.gpa);
    return utf16.string(engine, clipped.text);
}
const Method = enum(c_int) { stripTerminalSequences, getOsc8LinkAtColumn, sliceByColumn, compositeTuiLine };
fn fail(engine: *js.Engine, err: anyerror) c.JSValue {
    if (err == error.JavaScriptException) return engine.throwCaptured();
    if (err == error.OutOfMemory) return c.JS_ThrowOutOfMemory(engine.context);
    return c.JS_ThrowTypeError(engine.context, "Native TUI columns: %s", @as([*:0]const u8, @errorName(err)));
}
fn operation(engine: *js.Engine, method: Method, args: []const c.JSValue, exports: c.JSValue) !c.JSValue {
    const first = v.arg(args, 0);
    if (method == .stripTerminalSequences) {
        const escape = try v.text(engine, "\x1b");
        defer engine.freeValue(escape);
        const included = try js.invoke(engine, first, "includes", &.{escape});
        defer engine.freeValue(included);
        if (!v.truthy(engine, included)) return c.JS_DupValue(engine.context, first);
    }
    if (method == .compositeTuiLine) {
        const image = try js.invoke(engine, exports, "isImageLine", &.{first});
        defer engine.freeValue(image);
        if (v.truthy(engine, image)) return c.JS_DupValue(engine.context, first);
    }
    const length = if (method == .sliceByColumn) try v.number(engine, v.arg(args, 2)) else 0;
    if (method == .sliceByColumn and length <= 0) return v.text(engine, "");
    const source_length = try js.get(engine, first, "length");
    defer engine.freeValue(source_length);
    if (c.JS_IsUndefined(source_length)) return if (method == .getOsc8LinkAtColumn) c.pi_js_undefined() else try v.text(engine, "");
    const line = try utf16.unitsAlloc(engine, first);
    defer engine.gpa.free(line);
    switch (method) {
        .stripTerminalSequences => {
            var output: List = .empty;
            defer output.deinit(engine.gpa);
            var index: usize = 0;
            while (index < line.len) {
                const ansi = terminal.ansiLength(line, index);
                if (ansi != 0) index += ansi else {
                    try output.append(engine.gpa, line[index]);
                    index += 1;
                }
            }
            return utf16.string(engine, output.items);
        },
        .sliceByColumn => {
            const result = try slice(engine, line, try v.number(engine, v.arg(args, 1)), length, v.truthy(engine, v.arg(args, 3)));
            defer result.deinit(engine.gpa);
            return utf16.string(engine, result.text);
        },
        .getOsc8LinkAtColumn => {
            const column = try v.number(engine, v.arg(args, 1));
            var active: ?[]const u16 = null;
            var current: f64 = 0;
            var index: usize = 0;
            while (index < line.len) {
                const ansi = terminal.ansiLength(line, index);
                if (ansi != 0) {
                    const code = line[index..][0..ansi];
                    if (std.mem.startsWith(u16, code, osc_start)) {
                        const end = code.len - @as(usize, if (code[code.len - 1] == 7) 1 else 2);
                        if (std.mem.indexOfScalarPos(u16, code, osc_start.len, ';')) |separator| {
                            const url = code[separator + 1 .. end];
                            var valid = true;
                            for (url) |unit| if (unit == 7 or unit == 0x1b) {
                                valid = false;
                                break;
                            };
                            if (valid) active = if (url.len > 0) url else null;
                        }
                    }
                    index += ansi;
                    continue;
                }
                var text_end = index;
                while (text_end < line.len and terminal.ansiLength(line, text_end) == 0) : (text_end += 1) {}
                var iterator: graphemes.Iterator = .{ .text = line[index..text_end] };
                while (iterator.next()) |segment| {
                    const cluster = line[index + segment.start .. index + segment.end];
                    const width: f64 = if (std.mem.eql(u16, cluster, &.{'\t'})) 3 else @floatFromInt(try terminal.graphemeWidth(engine.gpa, cluster));
                    if (column >= current and column < current + width) return if (active) |url| try utf16.string(engine, url) else c.pi_js_undefined();
                    current += width;
                }
                index = text_end;
            }
            return c.pi_js_undefined();
        },
        .compositeTuiLine => {
            const overlay = try utf16.unitsAlloc(engine, v.arg(args, 1));
            defer engine.gpa.free(overlay);
            return composite(engine, line, overlay, try v.number(engine, v.arg(args, 2)), try v.number(engine, v.arg(args, 3)), try v.number(engine, v.arg(args, 4)));
        },
    }
}
fn methodCall(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, magic: c_int, data: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = js.Engine.fromContext(context.?);
    return operation(engine, @enumFromInt(magic), if (argc > 0) argv[0..@intCast(argc)] else &.{}, data[0]) catch |err| fail(engine, err);
}
pub fn install(engine: *js.Engine, exports: c.JSValue) !void {
    var data = [_]c.JSValue{exports};
    inline for (std.meta.fields(Method)) |field| {
        const name: [:0]const u8 = field.name;
        const length: c_int = switch (@as(Method, @enumFromInt(field.value))) {
            .stripTerminalSequences => 1,
            .getOsc8LinkAtColumn => 2,
            .sliceByColumn => 3,
            .compositeTuiLine => 5,
        };
        try js.define(engine, exports, name.ptr, try engine.checked(c.JS_NewCFunctionData2(engine.context, methodCall, name.ptr, length, @intCast(field.value), data.len, &data)));
    }
}
