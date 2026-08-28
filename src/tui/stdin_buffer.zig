//! Incremental terminal stdin framing.
//!
//! Data events from terminals are not message boundaries: CSI, mouse, Kitty,
//! OSC, DCS, APC, UTF-8, and bracketed-paste input can all be fragmented or
//! coalesced. This parser preserves complete sequences and exposes an explicit
//! clock hook so callers can implement the Escape/incomplete-sequence timeout
//! with any event loop.
const std = @import("std");

pub const bracketed_paste_start = "\x1b[200~";
pub const bracketed_paste_end = "\x1b[201~";

pub const Options = struct {
    sequence_timeout_ms: u64 = 50,
    escape_timeout_ms: u64 = 10,
    convert_single_high_byte_to_meta: bool = true,
};

pub const Event = union(enum) {
    data: []u8,
    paste: []u8,

    pub fn deinit(self: Event, allocator: std.mem.Allocator) void {
        switch (self) {
            .data, .paste => |payload| allocator.free(payload),
        }
    }

    pub fn bytes(self: Event) []const u8 {
        return switch (self) {
            .data, .paste => |value| value,
        };
    }
};

pub const StdinBuffer = struct {
    allocator: std.mem.Allocator,
    options: Options,
    buffer: std.ArrayList(u8) = .empty,
    paste_mode: bool = false,
    paste_buffer: std.ArrayList(u8) = .empty,
    pending_kitty_printable: ?u21 = null,
    elapsed_ms: u64 = 0,

    pub fn init(allocator: std.mem.Allocator, options: Options) StdinBuffer {
        return .{ .allocator = allocator, .options = options };
    }

    pub fn deinit(self: *StdinBuffer) void {
        self.buffer.deinit(self.allocator);
        self.paste_buffer.deinit(self.allocator);
        self.* = undefined;
    }

    pub fn getBuffer(self: *const StdinBuffer) []const u8 {
        return self.buffer.items;
    }

    pub fn getPasteBuffer(self: *const StdinBuffer) []const u8 {
        return self.paste_buffer.items;
    }

    pub fn isPasteMode(self: *const StdinBuffer) bool {
        return self.paste_mode;
    }

    pub fn pendingTimeoutMs(self: *const StdinBuffer) ?u64 {
        if (self.buffer.items.len == 0) return null;
        return if (std.mem.eql(u8, self.buffer.items, "\x1b")) self.options.escape_timeout_ms else self.options.sequence_timeout_ms;
    }

    /// Feed one transport chunk and append newly completed events to `events`.
    /// Event payloads are owned by the caller and must be deinitialized.
    pub fn process(self: *StdinBuffer, data: []const u8, events: *std.ArrayList(Event)) anyerror!void {
        self.elapsed_ms = 0;

        if (data.len == 0 and self.buffer.items.len == 0 and !self.paste_mode) {
            try self.emitData("", events);
            return;
        }

        if (self.options.convert_single_high_byte_to_meta and data.len == 1 and data[0] > 127) {
            try self.buffer.append(self.allocator, 0x1b);
            try self.buffer.append(self.allocator, data[0] - 128);
        } else {
            try self.buffer.appendSlice(self.allocator, data);
        }

        if (self.paste_mode) {
            try self.consumePaste(events);
            return;
        }

        if (std.mem.indexOf(u8, self.buffer.items, bracketed_paste_start)) |start| {
            if (start > 0) {
                _ = try self.extractComplete(self.buffer.items[0..start], events);
            }
            const after = start + bracketed_paste_start.len;
            const suffix = try self.allocator.dupe(u8, self.buffer.items[after..]);
            defer self.allocator.free(suffix);
            self.buffer.clearRetainingCapacity();
            self.pending_kitty_printable = null;
            self.paste_mode = true;
            try self.paste_buffer.appendSlice(self.allocator, suffix);
            try self.consumePaste(events);
            return;
        }

        const consumed = try self.extractComplete(self.buffer.items, events);
        if (consumed > 0) self.discardBufferPrefix(consumed);
    }

    /// Advance the parser's timeout clock. Returns true when buffered bytes
    /// were flushed as a data event.
    pub fn advance(self: *StdinBuffer, milliseconds: u64, events: *std.ArrayList(Event)) !bool {
        const timeout = self.pendingTimeoutMs() orelse return false;
        self.elapsed_ms +|= milliseconds;
        if (self.elapsed_ms < timeout) return false;
        return try self.flushInto(events);
    }

    pub fn flushInto(self: *StdinBuffer, events: *std.ArrayList(Event)) !bool {
        if (self.buffer.items.len == 0) return false;
        try self.emitData(self.buffer.items, events);
        self.buffer.clearRetainingCapacity();
        self.pending_kitty_printable = null;
        self.elapsed_ms = 0;
        return true;
    }

    /// Return an owned copy of an incomplete sequence, matching the original
    /// `flush()` API. Paste payloads intentionally remain in paste mode.
    pub fn flush(self: *StdinBuffer) !?[]u8 {
        if (self.buffer.items.len == 0) return null;
        const owned = try self.allocator.dupe(u8, self.buffer.items);
        self.buffer.clearRetainingCapacity();
        self.pending_kitty_printable = null;
        self.elapsed_ms = 0;
        return owned;
    }

    pub fn clear(self: *StdinBuffer) void {
        self.buffer.clearRetainingCapacity();
        self.paste_buffer.clearRetainingCapacity();
        self.paste_mode = false;
        self.pending_kitty_printable = null;
        self.elapsed_ms = 0;
    }

    fn consumePaste(self: *StdinBuffer, events: *std.ArrayList(Event)) anyerror!void {
        if (self.buffer.items.len > 0) {
            try self.paste_buffer.appendSlice(self.allocator, self.buffer.items);
            self.buffer.clearRetainingCapacity();
        }
        const end = std.mem.indexOf(u8, self.paste_buffer.items, bracketed_paste_end) orelse return;
        const pasted = try self.allocator.dupe(u8, self.paste_buffer.items[0..end]);
        errdefer self.allocator.free(pasted);
        const remaining_start = end + bracketed_paste_end.len;
        const remaining = try self.allocator.dupe(u8, self.paste_buffer.items[remaining_start..]);
        defer self.allocator.free(remaining);

        self.paste_buffer.clearRetainingCapacity();
        self.paste_mode = false;
        self.pending_kitty_printable = null;
        try events.append(self.allocator, .{ .paste = pasted });
        if (remaining.len > 0) try self.process(remaining, events);
    }

    /// Extract complete sequences from a prefix. Returns the byte count
    /// consumed; an incomplete suffix is left to the caller.
    fn extractComplete(self: *StdinBuffer, bytes: []const u8, events: *std.ArrayList(Event)) !usize {
        var position: usize = 0;
        while (position < bytes.len) {
            const remaining = bytes[position..];
            if (remaining[0] == 0x1b) {
                const length = completeEscapeLength(remaining) orelse break;
                // WezTerm can concatenate a raw Escape press with a Kitty
                // release sequence. Do not consume the second ESC as Meta-ESC.
                if (length == 2 and remaining.len > 2 and remaining[1] == 0x1b and isEscapeIntroducer(remaining[2])) {
                    try self.emitData(remaining[0..1], events);
                    position += 1;
                    continue;
                }
                try self.emitData(remaining[0..length], events);
                position += length;
                continue;
            }

            const length = completeUtf8Length(remaining) orelse break;
            try self.emitData(remaining[0..length], events);
            position += length;
        }
        return position;
    }

    fn emitData(self: *StdinBuffer, sequence: []const u8, events: *std.ArrayList(Event)) !void {
        const raw_codepoint = singleCodepoint(sequence);
        if (raw_codepoint != null and raw_codepoint == self.pending_kitty_printable) {
            self.pending_kitty_printable = null;
            return;
        }
        self.pending_kitty_printable = unmodifiedKittyPrintable(sequence);
        const owned = try self.allocator.dupe(u8, sequence);
        errdefer self.allocator.free(owned);
        try events.append(self.allocator, .{ .data = owned });
    }

    fn discardBufferPrefix(self: *StdinBuffer, count: usize) void {
        std.debug.assert(count <= self.buffer.items.len);
        const remaining = self.buffer.items.len - count;
        if (remaining > 0) std.mem.copyForwards(u8, self.buffer.items[0..remaining], self.buffer.items[count..]);
        self.buffer.items.len = remaining;
    }
};

fn isEscapeIntroducer(byte: u8) bool {
    return byte == '[' or byte == ']' or byte == 'O' or byte == 'P' or byte == '_';
}

fn completeEscapeLength(data: []const u8) ?usize {
    if (data.len == 0 or data[0] != 0x1b) return null;
    if (data.len == 1) return null;
    return switch (data[1]) {
        '[' => completeCsiLength(data),
        ']' => completeControlStringLength(data, true),
        'P', '_' => completeControlStringLength(data, false),
        'O' => if (data.len >= 3) 3 else null,
        else => 2,
    };
}

fn completeCsiLength(data: []const u8) ?usize {
    if (data.len < 3) return null;
    if (std.mem.startsWith(u8, data, "\x1b[M")) return if (data.len >= 6) 6 else null;

    // Linux console's double-bracket function-key form is one sequence.
    const start: usize = if (data.len >= 3 and data[2] == '[') 3 else 2;
    var index = start;
    while (index < data.len) : (index += 1) {
        const byte = data[index];
        if (byte < 0x40 or byte > 0x7e) continue;
        const candidate = data[0 .. index + 1];
        if (data[2] == '<') {
            if ((byte == 'M' or byte == 'm') and validSgrMouse(candidate[3 .. candidate.len - 1])) return candidate.len;
            // A malformed or still-fragmented SGR mouse sequence must not be
            // split merely because a terminator-looking byte appeared.
            return null;
        }
        return candidate.len;
    }
    return null;
}

fn validSgrMouse(payload: []const u8) bool {
    var fields = std.mem.splitScalar(u8, payload, ';');
    var count: usize = 0;
    while (fields.next()) |field| {
        if (field.len == 0) return false;
        for (field) |byte| if (!std.ascii.isDigit(byte)) return false;
        count += 1;
    }
    return count == 3;
}

fn completeControlStringLength(data: []const u8, allow_bel: bool) ?usize {
    var index: usize = 2;
    while (index < data.len) : (index += 1) {
        if (allow_bel and data[index] == 0x07) return index + 1;
        if (data[index] == 0x1b and index + 1 < data.len and data[index + 1] == '\\') return index + 2;
    }
    return null;
}

fn completeUtf8Length(data: []const u8) ?usize {
    if (data.len == 0) return null;
    const expected = std.unicode.utf8ByteSequenceLength(data[0]) catch return 1;
    if (data.len < expected) return null;
    _ = std.unicode.utf8Decode(data[0..expected]) catch return 1;
    return expected;
}

fn singleCodepoint(bytes: []const u8) ?u21 {
    const length = completeUtf8Length(bytes) orelse return null;
    if (length != bytes.len) return null;
    return std.unicode.utf8Decode(bytes) catch null;
}

fn unmodifiedKittyPrintable(sequence: []const u8) ?u21 {
    if (!std.mem.startsWith(u8, sequence, "\x1b[") or !std.mem.endsWith(u8, sequence, "u")) return null;
    const payload = sequence[2 .. sequence.len - 1];
    if (std.mem.indexOfScalar(u8, payload, ';') != null) return null;
    var fields = std.mem.splitScalar(u8, payload, ':');
    const codepoint = std.fmt.parseUnsigned(u21, fields.next() orelse return null, 10) catch return null;
    if (codepoint < 32) return null;
    // Optional shifted/base fields are allowed, but must be numeric/empty.
    var count: usize = 1;
    while (fields.next()) |field| {
        count += 1;
        if (count > 3) return null;
        if (field.len > 0) _ = std.fmt.parseUnsigned(u21, field, 10) catch return null;
    }
    return codepoint;
}

fn deinitEvents(allocator: std.mem.Allocator, events: *std.ArrayList(Event)) void {
    for (events.items) |event| event.deinit(allocator);
    events.deinit(allocator);
}

test "regular UTF-8 and complete terminal sequences are framed" {
    const allocator = std.testing.allocator;
    var buffer = StdinBuffer.init(allocator, .{});
    defer buffer.deinit();
    var events: std.ArrayList(Event) = .empty;
    defer deinitEvents(allocator, &events);
    try buffer.process("a世界\x1b[A\x1bOP\x1b]0;title\x07", &events);
    try std.testing.expectEqual(@as(usize, 6), events.items.len);
    try std.testing.expectEqualStrings("a", events.items[0].data);
    try std.testing.expectEqualStrings("世", events.items[1].data);
    try std.testing.expectEqualStrings("界", events.items[2].data);
    try std.testing.expectEqualStrings("\x1b[A", events.items[3].data);
    try std.testing.expectEqualStrings("\x1bOP", events.items[4].data);
    try std.testing.expectEqualStrings("\x1b]0;title\x07", events.items[5].data);
}

test "fragmented CSI SGR mouse OSC DCS and APC stay buffered" {
    const allocator = std.testing.allocator;
    var buffer = StdinBuffer.init(allocator, .{});
    defer buffer.deinit();
    var events: std.ArrayList(Event) = .empty;
    defer deinitEvents(allocator, &events);
    try buffer.process("\x1b[<35", &events);
    try std.testing.expectEqual(@as(usize, 0), events.items.len);
    try buffer.process(";15;10m\x1bP>|pi", &events);
    try std.testing.expectEqual(@as(usize, 1), events.items.len);
    try buffer.process("\x1b\\\x1b_Gi=1;OK", &events);
    try std.testing.expectEqual(@as(usize, 2), events.items.len);
    try buffer.process("\x1b\\", &events);
    try std.testing.expectEqual(@as(usize, 3), events.items.len);
    try std.testing.expectEqualStrings("\x1b[<35;15;10m", events.items[0].data);
    try std.testing.expectEqualStrings("\x1bP>|pi\x1b\\", events.items[1].data);
    try std.testing.expectEqualStrings("\x1b_Gi=1;OK\x1b\\", events.items[2].data);
}

test "Kitty batches split WezTerm escape and suppress duplicate printable" {
    const allocator = std.testing.allocator;
    var buffer = StdinBuffer.init(allocator, .{});
    defer buffer.deinit();
    var events: std.ArrayList(Event) = .empty;
    defer deinitEvents(allocator, &events);
    try buffer.process("\x1b\x1b[27;129:3u\x1b[224uà\x1b[64u", &events);
    try buffer.process("@", &events);
    try std.testing.expectEqual(@as(usize, 4), events.items.len);
    try std.testing.expectEqualStrings("\x1b", events.items[0].data);
    try std.testing.expectEqualStrings("\x1b[27;129:3u", events.items[1].data);
    try std.testing.expectEqualStrings("\x1b[224u", events.items[2].data);
    try std.testing.expectEqualStrings("\x1b[64u", events.items[3].data);
}

test "modified Kitty printable does not suppress following raw character" {
    const allocator = std.testing.allocator;
    var buffer = StdinBuffer.init(allocator, .{});
    defer buffer.deinit();
    var events: std.ArrayList(Event) = .empty;
    defer deinitEvents(allocator, &events);
    try buffer.process("\x1b[64;3u@", &events);
    try std.testing.expectEqual(@as(usize, 2), events.items.len);
}

test "old style mouse consumes exactly three payload bytes" {
    const allocator = std.testing.allocator;
    var buffer = StdinBuffer.init(allocator, .{});
    defer buffer.deinit();
    var events: std.ArrayList(Event) = .empty;
    defer deinitEvents(allocator, &events);
    try buffer.process("\x1b[M abc", &events);
    try std.testing.expectEqual(@as(usize, 2), events.items.len);
    try std.testing.expectEqualStrings("\x1b[M ab", events.items[0].data);
    try std.testing.expectEqualStrings("c", events.items[1].data);
}

test "bracketed paste is emitted atomically across chunks with trailing input" {
    const allocator = std.testing.allocator;
    var buffer = StdinBuffer.init(allocator, .{});
    defer buffer.deinit();
    var events: std.ArrayList(Event) = .empty;
    defer deinitEvents(allocator, &events);
    try buffer.process("a\x1b[200~hello ", &events);
    try buffer.process("世界\nline2\x1b[201~b", &events);
    try std.testing.expectEqual(@as(usize, 3), events.items.len);
    try std.testing.expectEqualStrings("a", events.items[0].data);
    try std.testing.expectEqualStrings("hello 世界\nline2", events.items[1].paste);
    try std.testing.expectEqualStrings("b", events.items[2].data);
}

test "separate escape and sequence timeouts flush deterministically" {
    const allocator = std.testing.allocator;
    var buffer = StdinBuffer.init(allocator, .{ .sequence_timeout_ms = 50, .escape_timeout_ms = 10 });
    defer buffer.deinit();
    var events: std.ArrayList(Event) = .empty;
    defer deinitEvents(allocator, &events);
    try buffer.process("\x1b", &events);
    try std.testing.expectEqual(@as(?u64, 10), buffer.pendingTimeoutMs());
    try std.testing.expect(!try buffer.advance(9, &events));
    try std.testing.expect(try buffer.advance(1, &events));
    try buffer.process("\x1b[<35", &events);
    try std.testing.expectEqual(@as(?u64, 50), buffer.pendingTimeoutMs());
    try std.testing.expect(try buffer.advance(50, &events));
    try std.testing.expectEqualStrings("\x1b[<35", events.items[1].data);
}

test "Linux double bracket and split UTF-8 are preserved" {
    const allocator = std.testing.allocator;
    var buffer = StdinBuffer.init(allocator, .{ .convert_single_high_byte_to_meta = false });
    defer buffer.deinit();
    var events: std.ArrayList(Event) = .empty;
    defer deinitEvents(allocator, &events);
    try buffer.process("\x1b[[5~\xc3", &events);
    try std.testing.expectEqual(@as(usize, 1), events.items.len);
    try std.testing.expectEqualStrings("\x1b[[5~", events.items[0].data);
    try buffer.process("\xa0", &events);
    try std.testing.expectEqualStrings("à", events.items[1].data);
}

test "clear discards all parser state" {
    const allocator = std.testing.allocator;
    var buffer = StdinBuffer.init(allocator, .{});
    defer buffer.deinit();
    var events: std.ArrayList(Event) = .empty;
    defer deinitEvents(allocator, &events);
    try buffer.process("\x1b[200~unfinished", &events);
    try std.testing.expect(buffer.isPasteMode());
    buffer.clear();
    try std.testing.expect(!buffer.isPasteMode());
    try std.testing.expectEqual(@as(usize, 0), buffer.getBuffer().len);
    try std.testing.expectEqual(@as(usize, 0), buffer.getPasteBuffer().len);
}
