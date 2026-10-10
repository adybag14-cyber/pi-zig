//! Source utils wrapping over the pinned Unicode 17 UTF16 grapheme/width engine.
const std = @import("std");
const engine_mod = @import("engine.zig");
const Engine = engine_mod.Engine;
const c = engine_mod.c;
const terminal = @import("../tui/utf16_terminal.zig");
const graphemes = @import("../tui/utf16_graphemes.zig");
const List = std.ArrayList(u16);
const Lines = std.ArrayList([]u16);
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
fn whitespace(unit: u16) bool {
    return switch (unit) {
        0x9...0xd, 0x20, 0xa0, 0x1680, 0x2000...0x200a, 0x2028, 0x2029, 0x202f, 0x205f, 0x3000, 0xfeff => true,
        else => false,
    };
}
fn trimEnd(units: []const u16) []const u16 {
    var end = units.len;
    while (end > 0 and whitespace(units[end - 1])) end -= 1;
    return units[0..end];
}
fn isWhitespace(units: []const u16) bool {
    for (units) |unit| if (!whitespace(unit)) return false;
    return true;
}
fn emit(gpa: std.mem.Allocator, lines: *Lines, units: []const u16) !void {
    if (lines.items.len >= 4096) return error.NativeComponentFrameLimit;
    const owned = try gpa.dupe(u16, units);
    errdefer gpa.free(owned);
    try lines.append(gpa, owned);
}
fn cjk(engine: *Engine, bytecode: [*]const u8, cluster: []const u16) !bool {
    if (cluster.len == 0 or cluster[0] < 0x80) return false;
    var captures: [2][*c]u8 = @splat(null);
    const matched = c.lre_exec(&captures, bytecode, @ptrCast(cluster.ptr), 0, @intCast(cluster.len), 1, engine.context);
    return switch (matched) {
        0 => false,
        1 => true,
        c.LRE_RET_MEMORY_ERROR => error.OutOfMemory,
        else => error.NativeUnicodeWrapFailure,
    };
}
fn tokenize(engine: *Engine, bytecode: [*]const u8, source: []const u16) ![][]u16 {
    const gpa = engine.gpa;
    var tokens: Lines = .empty;
    errdefer {
        for (tokens.items) |token| gpa.free(token);
        tokens.deinit(gpa);
    }
    var current: List = .empty;
    defer current.deinit(gpa);
    var pending: List = .empty;
    defer pending.deinit(gpa);
    var kind: ?bool = null;
    var index: usize = 0;
    while (index < source.len) {
        const count = terminal.ansiLength(source, index);
        if (count != 0) {
            try pending.appendSlice(gpa, source[index..][0..count]);
            index += count;
            continue;
        }
        var end = index + 1;
        while (end < source.len and terminal.ansiLength(source, end) == 0) end += 1;
        var iterator: graphemes.Iterator = .{ .text = source[index..end] };
        while (iterator.next()) |part| {
            const cluster = source[index + part.start .. index + part.end];
            const space = std.mem.eql(u16, cluster, &.{' '});
            const standalone = !space and try cjk(engine, bytecode, cluster);
            if (current.items.len > 0 and (standalone or (kind != null and kind.? != space))) {
                try emit(gpa, &tokens, current.items);
                current.clearRetainingCapacity();
                kind = null;
            }
            try current.appendSlice(gpa, pending.items);
            pending.clearRetainingCapacity();
            try current.appendSlice(gpa, cluster);
            kind = space;
            if (standalone) {
                try emit(gpa, &tokens, current.items);
                current.clearRetainingCapacity();
                kind = null;
            }
        }
        index = end;
    }
    if (pending.items.len > 0 and current.items.len == 0 and tokens.items.len > 0) {
        const last = tokens.items.len - 1;
        const joined = try std.mem.concat(gpa, u16, &.{ tokens.items[last], pending.items });
        gpa.free(tokens.items[last]);
        tokens.items[last] = joined;
    } else try current.appendSlice(gpa, pending.items);
    if (current.items.len > 0) try emit(gpa, &tokens, current.items);
    return tokens.toOwnedSlice(gpa);
}
fn single(engine: *Engine, bytecode: [*]const u8, source: []const u16, width: f64, lines: *Lines) !void {
    const gpa = engine.gpa;
    if (@as(f64, @floatFromInt(try terminal.visibleWidth(gpa, source))) <= width) return emit(gpa, lines, source);
    const original_count = lines.items.len;
    const tokens = try tokenize(engine, bytecode, source);
    defer {
        for (tokens) |token| gpa.free(token);
        gpa.free(tokens);
    }
    var style: Style = .{ .gpa = gpa };
    defer style.deinit();
    var current: List = .empty;
    defer current.deinit(gpa);
    var visible: usize = 0;
    for (tokens) |token| {
        const token_width = try terminal.visibleWidth(gpa, token);
        const space = isWhitespace(token);
        if (@as(f64, @floatFromInt(token_width)) > width and !space) {
            if (current.items.len > 0) {
                try style.closeLine(&current);
                try emit(gpa, lines, current.items);
                current.clearRetainingCapacity();
                visible = 0;
            }
            try style.active(&current);
            var index: usize = 0;
            while (index < token.len) {
                const count = terminal.ansiLength(token, index);
                if (count != 0) {
                    try current.appendSlice(gpa, token[index..][0..count]);
                    try style.process(token[index..][0..count]);
                    index += count;
                    continue;
                }
                var end = index + 1;
                while (end < token.len and terminal.ansiLength(token, end) == 0) end += 1;
                var iterator: graphemes.Iterator = .{ .text = token[index..end] };
                while (iterator.next()) |part| {
                    const cluster = token[index + part.start .. index + part.end];
                    const cluster_width = try terminal.graphemeWidth(gpa, cluster);
                    if (@as(f64, @floatFromInt(visible + cluster_width)) > width) {
                        try style.closeLine(&current);
                        try emit(gpa, lines, current.items);
                        current.clearRetainingCapacity();
                        try style.active(&current);
                        visible = 0;
                    }
                    try current.appendSlice(gpa, cluster);
                    visible += cluster_width;
                }
                index = end;
            }
            // breakLongWord returns its final line for the caller to continue.
            visible = try terminal.visibleWidth(gpa, current.items);
            continue;
        }
        if (@as(f64, @floatFromInt(visible + token_width)) > width and visible > 0) {
            current.items.len = trimEnd(current.items).len;
            try style.closeLine(&current);
            try emit(gpa, lines, current.items);
            current.clearRetainingCapacity();
            try style.active(&current);
            if (space) visible = 0 else {
                try current.appendSlice(gpa, token);
                visible = token_width;
            }
        } else {
            try current.appendSlice(gpa, token);
            visible += token_width;
        }
        try style.update(token);
    }
    if (current.items.len > 0) try emit(gpa, lines, current.items);
    if (lines.items.len == original_count) try emit(gpa, lines, &.{});
    for (lines.items[original_count..]) |*line| {
        const trimmed = trimEnd(line.*);
        if (trimmed.len != line.*.len) {
            const replacement = try gpa.dupe(u16, trimmed);
            gpa.free(line.*);
            line.* = replacement;
        }
    }
}
test "Source6fb public SelectList wrapping CJK tokenizer matches every original codepoint including Script Extensions" {
    const gpa = std.testing.allocator;
    const engine = try Engine.init(gpa, .{});
    defer engine.deinit();
    const pattern = "[\\p{Script_Extensions=Han}\\p{Script_Extensions=Hiragana}\\p{Script_Extensions=Katakana}\\p{Script_Extensions=Hangul}\\p{Script_Extensions=Bopomofo}]";
    var bytecode_len: c_int = 0;
    var diagnostic: [256]u8 = undefined;
    const bytecode = c.lre_compile(&bytecode_len, &diagnostic, diagnostic.len, pattern, pattern.len, c.LRE_FLAG_UNICODE, engine.context) orelse return error.NativeUnicodeWrapFailure;
    defer c.js_free(engine.context, bytecode);
    const fixture = try std.json.parseFromSlice(std.json.Value, gpa, @embedFile("fixtures/wrap-cjk-original-6fb.json"), .{});
    defer fixture.deinit();
    const ranges = fixture.value.object.get("ranges").?.array.items;
    var range_index: usize = 0;
    for (0..0x110000) |cp| {
        while (range_index < ranges.len and cp > ranges[range_index].array.items[1].integer) range_index += 1;
        const expected = range_index < ranges.len and cp >= ranges[range_index].array.items[0].integer;
        var units: [2]u16 = undefined;
        const count: usize = if (cp <= 0xffff) value: {
            units[0] = @intCast(cp);
            break :value 1;
        } else value: {
            units[0] = @intCast(0xd800 + ((cp - 0x10000) >> 10));
            units[1] = @intCast(0xdc00 + ((cp - 0x10000) & 0x3ff));
            break :value 2;
        };
        std.testing.expectEqual(expected, try cjk(engine, bytecode, units[0..count])) catch |err| {
            std.debug.print("Source CJK Script_Extensions U+{X}\n", .{cp});
            return err;
        };
    }
}
pub fn wrap(engine: *Engine, source: []const u16, width: f64) ![][]u16 {
    const pattern = "[\\p{Script_Extensions=Han}\\p{Script_Extensions=Hiragana}\\p{Script_Extensions=Katakana}\\p{Script_Extensions=Hangul}\\p{Script_Extensions=Bopomofo}]";
    var bytecode_len: c_int = 0;
    var diagnostic: [256]u8 = undefined;
    const bytecode = c.lre_compile(&bytecode_len, &diagnostic, diagnostic.len, pattern, pattern.len, c.LRE_FLAG_UNICODE, engine.context) orelse return error.NativeUnicodeWrapFailure;
    defer c.js_free(engine.context, bytecode);
    const gpa = engine.gpa;
    var lines: Lines = .empty;
    errdefer {
        for (lines.items) |line| gpa.free(line);
        lines.deinit(gpa);
    }
    var style: Style = .{ .gpa = gpa };
    defer style.deinit();
    var start: usize = 0;
    while (start <= source.len) {
        const end = if (std.mem.indexOfAny(u16, source[start..], &.{ '\r', '\n' })) |relative| start + relative else source.len;
        const paragraph = source[start..end];
        var prefixed: List = .empty;
        defer prefixed.deinit(gpa);
        if (lines.items.len > 0) try style.active(&prefixed);
        try prefixed.appendSlice(gpa, paragraph);
        try single(engine, bytecode, prefixed.items, width, &lines);
        try style.update(paragraph);
        if (end == source.len) break;
        start = end + 1;
        if (source[end] == '\r' and start < source.len and source[start] == '\n') start += 1;
    }
    return lines.toOwnedSlice(gpa);
}
fn fixtureUnits(gpa: std.mem.Allocator, value: std.json.Value) ![]u16 {
    const units = try gpa.alloc(u16, value.array.items.len);
    for (units, value.array.items) |*unit, item| unit.* = @intCast(item.integer);
    return units;
}
test "Source6fb public SelectList shared wrapping preserves original UTF16 clusters ANSI hyperlinks and zero width" {
    const gpa = std.testing.allocator;
    const engine = try Engine.init(gpa, .{});
    defer engine.deinit();
    const fixture = try std.json.parseFromSlice(std.json.Value, gpa, @embedFile("../tui/fixtures/terminal-layout-original-6fb.json"), .{});
    defer fixture.deinit();
    for (fixture.value.object.get("wrapping").?.array.items, 0..) |entry, index| {
        const text = try fixtureUnits(gpa, entry.object.get("text").?);
        defer gpa.free(text);
        const width: f64 = @floatFromInt(entry.object.get("width").?.integer);
        const actual = try wrap(engine, text, width);
        defer {
            for (actual) |line| gpa.free(line);
            gpa.free(actual);
        }
        const expected = entry.object.get("lines").?.array.items;
        std.testing.expectEqual(expected.len, actual.len) catch |err| {
            std.debug.print("Source wrapping case {d} width {d}\n", .{ index, width });
            return err;
        };
        for (expected, actual) |expected_line, actual_line| {
            const units = try fixtureUnits(gpa, expected_line);
            defer gpa.free(units);
            std.testing.expectEqualSlices(u16, units, actual_line) catch |err| {
                std.debug.print("Source wrapping case {d} width {d}\n", .{ index, width });
                return err;
            };
        }
    }
}
test "Source6fb public SelectList public wrapping and truncation helpers replay every original layout and function arity" {
    const engine = try Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    try @import("native_tui.zig").install(engine);
    const root = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(root);
    const bytes = @embedFile("../tui/fixtures/terminal-layout-original-6fb.json");
    try @import("native_js_values.zig").define(engine, root, "layoutFixture", try engine.checked(c.JS_ParseJSON(engine.context, bytes.ptr, bytes.len, "terminal-layout-original-6fb.json")));
    const result = engine.evalModule(
        \\import{wrapTextWithAnsi,truncateToWidth}from'pi-tui';const string=units=>String.fromCharCode(...units),units=text=>Array.from({length:text.length},(_,i)=>text.charCodeAt(i));for(const[index,item]of layoutFixture.truncation.entries()){const actual=units(truncateToWidth(string(item.text),item.width,string(item.ellipsis),item.pad));if(JSON.stringify(actual)!==JSON.stringify(item.result))throw Error(JSON.stringify({index,actual,expected:item.result}));}for(const[index,item]of layoutFixture.wrapping.entries()){const actual=wrapTextWithAnsi(string(item.text),item.width).map(units);if(JSON.stringify(actual)!==JSON.stringify(item.lines))throw Error(JSON.stringify({index,actual,expected:item.lines}));}if(wrapTextWithAnsi.length!==2||truncateToWidth.length!==2)throw Error('helper arity');
    , "public-terminal-layout.mjs") catch |err| {
        if (engine.last_error) |message| std.debug.print("Public layout: {s}\n", .{message});
        return err;
    };
    engine.freeValue(result);
}
