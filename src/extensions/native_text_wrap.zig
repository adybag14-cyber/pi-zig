//! Pi text token wrapping over the existing native grapheme and width engine.
const std = @import("std");
const engine_mod = @import("engine.zig");
const text = @import("../tui/terminal_text.zig");
const c = engine_mod.c;
const Style = struct {
    gpa: std.mem.Allocator,
    flags: [8]bool = @splat(false),
    fg: [64]u8 = undefined,
    bg: [64]u8 = undefined,
    fg_len: usize = 0,
    bg_len: usize = 0,
    hyperlink: ?[]u8 = null,
    fn deinit(self: *Style) void {
        if (self.hyperlink) |value| self.gpa.free(value);
    }
    fn color(self: *Style, foreground: bool, value: []const u8) !void {
        if (value.len > 64) return error.NativeAnsiColorLimit;
        if (foreground) {
            @memcpy(self.fg[0..value.len], value);
            self.fg_len = value.len;
        } else {
            @memcpy(self.bg[0..value.len], value);
            self.bg_len = value.len;
        }
    }
    fn process(self: *Style, sequence: []const u8) !void {
        if (std.mem.startsWith(u8, sequence, "\x1b]8;")) {
            const ending: usize = if (std.mem.endsWith(u8, sequence, "\x1b\\")) 2 else if (std.mem.endsWith(u8, sequence, "\x07")) 1 else return;
            const body = sequence[4 .. sequence.len - ending];
            const split = std.mem.indexOfScalar(u8, body, ';') orelse return;
            const replacement = if (body[split + 1 ..].len > 0) try self.gpa.dupe(u8, sequence) else null;
            if (self.hyperlink) |old| self.gpa.free(old);
            self.hyperlink = replacement;
            return;
        }
        if (!std.mem.startsWith(u8, sequence, "\x1b[") or !std.mem.endsWith(u8, sequence, "m")) return;
        const body = sequence[2 .. sequence.len - 1];
        var parts = std.mem.splitScalar(u8, body, ';');
        while (parts.next()) |part| {
            const value = std.fmt.parseInt(u16, if (part.len == 0) "0" else part, 10) catch continue;
            if (value == 38 or value == 48) {
                const begin = @intFromPtr(part.ptr) - @intFromPtr(body.ptr);
                const mode = parts.next() orelse continue;
                const count: usize = if (std.mem.eql(u8, mode, "5")) 1 else if (std.mem.eql(u8, mode, "2")) 3 else continue;
                var end = begin + part.len;
                for (0..count) |_| {
                    const parameter = parts.next() orelse break;
                    end = @intFromPtr(parameter.ptr) - @intFromPtr(body.ptr) + parameter.len;
                }
                try self.color(value == 38, body[begin..end]);
                continue;
            }
            switch (value) {
                0 => {
                    self.flags = @splat(false);
                    self.fg_len = 0;
                    self.bg_len = 0;
                },
                1...5 => self.flags[value - 1] = true,
                7...9 => self.flags[value - 2] = true,
                21 => self.flags[0] = false,
                22 => {
                    self.flags[0] = false;
                    self.flags[1] = false;
                },
                23...25 => self.flags[value - 21] = false,
                27...29 => self.flags[value - 22] = false,
                39 => self.fg_len = 0,
                49 => self.bg_len = 0,
                30...37, 90...97, 40...47, 100...107 => {
                    var buffer: [5]u8 = undefined;
                    try self.color(value < 40 or (value >= 90 and value <= 97), try std.fmt.bufPrint(&buffer, "{d}", .{value}));
                },
                else => {},
            }
        }
    }
    fn update(self: *Style, bytes: []const u8) !void {
        var index: usize = 0;
        while (index < bytes.len) {
            if (text.extractSequence(bytes, index)) |sequence| {
                try self.process(sequence.bytes);
                index = sequence.end;
            } else index += 1;
        }
    }
    fn active(self: *const Style, target: *std.ArrayList(u8)) !void {
        var codes: std.ArrayList(u8) = .empty;
        defer codes.deinit(self.gpa);
        for (self.flags, [_]u8{ 1, 2, 3, 4, 5, 7, 8, 9 }) |enabled, number| if (enabled) {
            if (codes.items.len > 0) try codes.append(self.gpa, ';');
            try codes.append(self.gpa, '0' + @as(u8, @intCast(number)));
        };
        for ([_][]const u8{ self.fg[0..self.fg_len], self.bg[0..self.bg_len] }) |color_code| if (color_code.len > 0) {
            if (codes.items.len > 0) try codes.append(self.gpa, ';');
            try codes.appendSlice(self.gpa, color_code);
        };
        if (codes.items.len > 0) {
            try target.appendSlice(self.gpa, "\x1b[");
            try target.appendSlice(self.gpa, codes.items);
            try target.append(self.gpa, 'm');
        }
        if (self.hyperlink) |link| try target.appendSlice(self.gpa, link);
    }
    fn closeLine(self: *const Style, target: *std.ArrayList(u8)) !void {
        if (self.flags[3]) try target.appendSlice(self.gpa, "\x1b[24m");
        if (self.hyperlink) |link| try target.appendSlice(self.gpa, if (std.mem.endsWith(u8, link, "\x07")) "\x1b]8;;\x07" else "\x1b]8;;\x1b\\");
    }
};
fn whitespace(point: u21) bool {
    return switch (point) {
        0x9...0xd, 0x20, 0xa0, 0x1680, 0x2000...0x200a, 0x2028, 0x2029, 0x202f, 0x205f, 0x3000, 0xfeff => true,
        else => false,
    };
}
fn trimEnd(bytes: []const u8) []const u8 {
    var iterator = std.unicode.Wtf8View.initUnchecked(bytes).iterator();
    var last: usize = 0;
    while (iterator.nextCodepoint()) |point| if (!whitespace(point)) {
        last = iterator.i;
    };
    return bytes[0..last];
}
fn isWhitespace(bytes: []const u8) bool {
    var iterator = std.unicode.Wtf8View.initUnchecked(bytes).iterator();
    while (iterator.nextCodepoint()) |point| if (!whitespace(point)) return false;
    return true;
}
fn emit(gpa: std.mem.Allocator, lines: *std.ArrayList([]u8), bytes: []const u8) !void {
    if (lines.items.len >= 4096) return error.NativeComponentFrameLimit;
    var allocated: usize = 0;
    for (lines.items) |line| allocated += line.len;
    if (bytes.len > 1024 * 1024 - allocated) return error.NativeComponentFrameLimit;
    const owned = try gpa.dupe(u8, trimEnd(bytes));
    errdefer gpa.free(owned);
    try lines.append(gpa, owned);
}
fn cjk(engine: *engine_mod.Engine, bytecode: [*]const u8, cluster: []const u8) !bool {
    if (cluster.len == 0 or cluster[0] < 0x80) return false;
    const utf16 = try std.unicode.wtf8ToWtf16LeAlloc(engine.gpa, cluster);
    defer engine.gpa.free(utf16);
    var captures: [2][*c]u8 = @splat(null);
    const matched = c.lre_exec(&captures, bytecode, @ptrCast(utf16.ptr), 0, @intCast(utf16.len), 1, engine.context);
    return switch (matched) {
        0 => false,
        1 => true,
        c.LRE_RET_MEMORY_ERROR => error.OutOfMemory,
        else => error.NativeUnicodeWrapFailure,
    };
}
fn tokenize(engine: *engine_mod.Engine, bytecode: [*]const u8, source: []const u8) ![][]u8 {
    const gpa = engine.gpa;
    var tokens: std.ArrayList([]u8) = .empty;
    errdefer {
        for (tokens.items) |token| gpa.free(token);
        tokens.deinit(gpa);
    }
    var current: std.ArrayList(u8) = .empty;
    defer current.deinit(gpa);
    var pending: std.ArrayList(u8) = .empty;
    defer pending.deinit(gpa);
    var kind: ?bool = null;
    var index: usize = 0;
    while (index < source.len) {
        if (text.extractSequence(source, index)) |sequence| {
            try pending.appendSlice(gpa, sequence.bytes);
            index = sequence.end;
            continue;
        }
        const cluster = text.nextCluster(source, index) orelse break;
        const space = std.mem.eql(u8, cluster.bytes, " ");
        const standalone = !space and try cjk(engine, bytecode, cluster.bytes);
        if (current.items.len > 0 and (standalone or (kind != null and kind.? != space))) {
            const owned = try current.toOwnedSlice(gpa);
            errdefer gpa.free(owned);
            try tokens.append(gpa, owned);
            kind = null;
        }
        try current.appendSlice(gpa, pending.items);
        pending.clearRetainingCapacity();
        try current.appendSlice(gpa, cluster.bytes);
        kind = space;
        if (standalone) {
            const owned = try current.toOwnedSlice(gpa);
            errdefer gpa.free(owned);
            try tokens.append(gpa, owned);
            kind = null;
        }
        index = cluster.end;
    }
    if (pending.items.len > 0 and current.items.len == 0 and tokens.items.len > 0) {
        const last = tokens.items.len - 1;
        const joined = try std.mem.concat(gpa, u8, &.{ tokens.items[last], pending.items });
        gpa.free(tokens.items[last]);
        tokens.items[last] = joined;
    } else try current.appendSlice(gpa, pending.items);
    if (current.items.len > 0) {
        const owned = try current.toOwnedSlice(gpa);
        errdefer gpa.free(owned);
        try tokens.append(gpa, owned);
    }
    return tokens.toOwnedSlice(gpa);
}
fn single(engine: *engine_mod.Engine, bytecode: [*]const u8, source: []const u8, width: usize, lines: *std.ArrayList([]u8)) !void {
    const gpa = engine.gpa;
    if (text.visibleWidth(source) <= width) {
        const exact = try gpa.dupe(u8, source);
        errdefer gpa.free(exact);
        try lines.append(gpa, exact);
        return;
    }
    const tokens = try tokenize(engine, bytecode, source);
    defer {
        for (tokens) |token| gpa.free(token);
        gpa.free(tokens);
    }
    var style: Style = .{ .gpa = gpa };
    defer style.deinit();
    var current: std.ArrayList(u8) = .empty;
    defer current.deinit(gpa);
    var visible: usize = 0;
    for (tokens) |token| {
        const token_width = text.visibleWidth(token);
        const space = isWhitespace(token);
        if (token_width > width and !space) {
            if (current.items.len > 0) {
                try style.closeLine(&current);
                try emit(gpa, lines, current.items);
                current.clearRetainingCapacity();
                visible = 0;
            }
            try style.active(&current);
            var index: usize = 0;
            while (index < token.len) {
                if (text.extractSequence(token, index)) |sequence| {
                    try current.appendSlice(gpa, sequence.bytes);
                    try style.process(sequence.bytes);
                    index = sequence.end;
                    continue;
                }
                const cluster = text.nextCluster(token, index) orelse break;
                if (visible + cluster.width > width) {
                    try style.closeLine(&current);
                    try emit(gpa, lines, current.items);
                    current.clearRetainingCapacity();
                    try style.active(&current);
                    visible = 0;
                }
                try current.appendSlice(gpa, cluster.bytes);
                visible += cluster.width;
                index = cluster.end;
            }
            continue;
        }
        if (visible + token_width > width and visible > 0) {
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
}
pub fn wrap(engine: *engine_mod.Engine, source: []const u8, width: usize) ![][]u8 {
    const pattern = "[\\p{Script_Extensions=Han}\\p{Script_Extensions=Hiragana}\\p{Script_Extensions=Katakana}\\p{Script_Extensions=Hangul}\\p{Script_Extensions=Bopomofo}]";
    var bytecode_len: c_int = 0;
    var diagnostic: [256]u8 = undefined;
    const bytecode = c.lre_compile(&bytecode_len, &diagnostic, diagnostic.len, pattern, pattern.len, c.LRE_FLAG_UNICODE, engine.context) orelse return error.NativeUnicodeWrapFailure;
    defer c.js_free(engine.context, bytecode);
    const gpa = engine.gpa;
    var lines: std.ArrayList([]u8) = .empty;
    errdefer {
        for (lines.items) |line| gpa.free(line);
        lines.deinit(gpa);
    }
    var style: Style = .{ .gpa = gpa };
    defer style.deinit();
    var start: usize = 0;
    while (start <= source.len) {
        const end = if (std.mem.indexOfAny(u8, source[start..], "\r\n")) |relative| start + relative else source.len;
        const paragraph = source[start..end];
        var prefixed: std.ArrayList(u8) = .empty;
        defer prefixed.deinit(gpa);
        if (lines.items.len > 0) try style.active(&prefixed);
        try prefixed.appendSlice(gpa, paragraph);
        try single(engine, bytecode, prefixed.items, @max(1, width), &lines);
        try style.update(paragraph);
        if (end == source.len) break;
        start = end + 1;
        if (source[end] == '\r' and start < source.len and source[start] == '\n') start += 1;
    }
    return lines.toOwnedSlice(gpa);
}
