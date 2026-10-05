//! Bounded running output with exact decoded counts and legal omission support.
const std = @import("std");
const decode = @import("decode.zig");
pub const Retention = enum { head, tail };
pub const Limits = struct { maxBytes: usize = 50 * 1024, maxLines: usize = 2000, retain: Retention = .tail };
pub const ShellOutputWindow = struct { maxBytes: usize, maxLines: usize, minIntervalMs: u64, bytesPerSecond: u64 };
pub const ShellOutputSkip = struct { bytes: u64, newlines: u64, endsWithNewline: bool };
pub const Snapshot = struct {
    text: []u8,
    droppedBytes: u64,
    droppedLines: u64,
    pub fn deinit(self: *Snapshot, gpa: std.mem.Allocator) void {
        gpa.free(self.text);
        self.* = undefined;
    }
};
pub const Slice = struct { text: []u8, bytes: usize, droppedBytes: usize, droppedLines: u64 };
fn newlines(text: []const u8) u64 {
    return std.mem.count(u8, text, "\n");
}
fn lines(text: []const u8) u64 {
    return newlines(text) + @as(u64, @intFromBool(text.len != 0 and text[text.len - 1] != '\n'));
}
pub fn measure(text: []const u8) ShellOutputSkip {
    return .{ .bytes = text.len, .newlines = newlines(text), .endsWithNewline = text.len != 0 and text[text.len - 1] == '\n' };
}
fn characterEnd(text: []const u8, input: usize) usize {
    var index = @min(input, text.len);
    while (index > 0 and index < text.len and text[index] & 0xc0 == 0x80) : (index -= 1) {}
    return index;
}
fn characterStart(text: []const u8, input: usize) usize {
    var index = @min(input, text.len);
    while (index < text.len and text[index] & 0xc0 == 0x80) : (index += 1) {}
    return index;
}
fn range(text: []const u8, limits: Limits) struct { from: usize, to: usize } {
    if (limits.maxBytes == 0 or limits.maxLines == 0) return if (limits.retain == .head) .{ .from = 0, .to = 0 } else .{ .from = text.len, .to = text.len };
    if (limits.retain == .head) {
        var end = text.len;
        var count: usize = 0;
        for (text, 0..) |byte, index| if (byte == '\n') {
            count += 1;
            if (count == limits.maxLines) {
                end = index + 1;
                break;
            }
        };
        if (end > limits.maxBytes) end = if (std.mem.lastIndexOfScalar(u8, text[0..limits.maxBytes], '\n')) |index| index + 1 else characterEnd(text, limits.maxBytes);
        return .{ .from = 0, .to = end };
    }
    var start: usize = 0;
    var count: usize = 1;
    var cursor = if (text.len != 0 and text[text.len - 1] == '\n') text.len - 1 else text.len;
    while (cursor > 0) {
        cursor -= 1;
        if (text[cursor] != '\n') continue;
        if (count == limits.maxLines) {
            start = cursor + 1;
            break;
        }
        count += 1;
    }
    if (text.len - start > limits.maxBytes) {
        const from = text.len - limits.maxBytes;
        const newline = std.mem.indexOfScalarPos(u8, text, from - 1, '\n');
        start = if (newline != null and newline.? + 1 < text.len) newline.? + 1 else characterStart(text, from);
    }
    return .{ .from = start, .to = text.len };
}
pub fn boundOutput(gpa: std.mem.Allocator, text: []const u8, limits: Limits) !Slice {
    if (!std.unicode.utf8ValidateSlice(text)) return error.InvalidUtf8Text;
    const selected = range(text, limits);
    const kept = text[selected.from..selected.to];
    return .{ .text = try gpa.dupe(u8, kept), .bytes = kept.len, .droppedBytes = text.len - kept.len, .droppedLines = lines(text) - lines(kept) };
}
/// Retain the shortest suffix exceeding a byte or newline window, preserving
/// the information that locates a future window's first line.
pub fn tailMargin(text: []const u8, limits: Limits) usize {
    const byte_start = if (text.len > limits.maxBytes) characterEnd(text, text.len - limits.maxBytes - 1) else 0;
    var line_start: usize = 0;
    var count: usize = 0;
    var index = text.len;
    while (index > 0) {
        index -= 1;
        if (text[index] != '\n') continue;
        count += 1;
        if (count > limits.maxLines) {
            line_start = index;
            break;
        }
    }
    return @max(byte_start, line_start);
}
pub fn sanitizeOutput(gpa: std.mem.Allocator, text: []const u8) ![]u8 {
    var result: std.ArrayList(u8) = .empty;
    defer result.deinit(gpa);
    var points = (try std.unicode.Utf8View.init(text)).iterator();
    while (points.nextCodepointSlice()) |bytes| {
        const point = try std.unicode.utf8Decode(bytes);
        if (point <= 8 or (point >= 11 and point <= 31) or (point >= 0xfff9 and point <= 0xfffb)) continue;
        try result.appendSlice(gpa, bytes);
    }
    return result.toOwnedSlice(gpa);
}

pub const OutputBuffer = struct {
    gpa: std.mem.Allocator,
    limits: Limits,
    decoder: decode.Decoder = decode.streamDecoder(),
    stored: std.ArrayList(u8) = .empty,
    stored_newlines: u64 = 0,
    full: bool = false,
    total_bytes: u64 = 0,
    total_newlines: u64 = 0,
    ends_with_newline: bool = true,
    pub fn init(gpa: std.mem.Allocator, limits: Limits) OutputBuffer {
        return .{ .gpa = gpa, .limits = limits };
    }
    pub fn deinit(self: *OutputBuffer) void {
        self.stored.deinit(self.gpa);
        self.* = undefined;
    }
    pub fn storedBytes(self: *const OutputBuffer) usize {
        return self.stored.items.len;
    }
    fn accept(self: *OutputBuffer, text: []const u8) void {
        if (text.len == 0) return;
        const count = newlines(text);
        self.total_bytes += text.len;
        self.total_newlines += count;
        self.ends_with_newline = text[text.len - 1] == '\n';
        if (self.full) return;
        self.stored.appendSliceAssumeCapacity(text);
        self.stored_newlines += count;
        if (self.limits.retain == .head) {
            self.full = self.stored.items.len > self.limits.maxBytes or self.stored_newlines >= self.limits.maxLines;
        } else {
            const start = tailMargin(self.stored.items, self.limits);
            if (start != 0) {
                self.stored_newlines -= newlines(self.stored.items[0..start]);
                const tail = self.stored.items[start..];
                @memmove(self.stored.items[0..tail.len], tail);
                self.stored.items.len = tail.len;
            }
        }
    }
    fn acceptPrepared(self: *OutputBuffer, pending: []const u8, text: []const u8, skipped: ?ShellOutputSkip) !bool {
        if (skipped != null and self.limits.retain != .tail) return error.SkippedOutputRequiresTail;
        const added = std.math.add(u64, pending.len, text.len) catch return error.OutputSizeOverflow;
        const extra = if (skipped) |skip| skip.bytes else 0;
        _ = std.math.add(u64, self.total_bytes, std.math.add(u64, added, extra) catch return error.OutputSizeOverflow) catch return error.OutputSizeOverflow;
        const added_lines = std.math.add(u64, newlines(pending), newlines(text)) catch return error.OutputSizeOverflow;
        _ = std.math.add(u64, self.total_newlines, std.math.add(u64, added_lines, if (skipped) |skip| skip.newlines else 0) catch return error.OutputSizeOverflow) catch return error.OutputSizeOverflow;
        if (!self.full) {
            const capacity = std.math.add(usize, self.stored.items.len, @intCast(added)) catch return error.OutputSizeOverflow;
            try self.stored.ensureTotalCapacity(self.gpa, capacity);
        }
        self.accept(pending);
        if (skipped) |skip| if (skip.bytes != 0) {
            self.total_bytes += skip.bytes;
            self.total_newlines += skip.newlines;
            self.ends_with_newline = skip.endsWithNewline;
            self.stored.clearRetainingCapacity();
            self.stored_newlines = 0;
        };
        self.accept(text);
        return skipped != null or pending.len != 0 or text.len != 0;
    }
    pub fn pushText(self: *OutputBuffer, text: []const u8, skipped: ?ShellOutputSkip) !bool {
        if (!std.unicode.utf8ValidateSlice(text)) return error.InvalidUtf8Text;
        if (skipped != null and self.limits.retain != .tail) return error.SkippedOutputRequiresTail;
        var decoder = self.decoder;
        var pending: std.ArrayList(u8) = .empty;
        defer pending.deinit(self.gpa);
        try decoder.finish(decode.Text{ .gpa = self.gpa, .output = &pending });
        const accepted = try self.acceptPrepared(pending.items, text, skipped);
        self.decoder = decode.streamDecoder();
        return accepted;
    }
    pub fn pushBytes(self: *OutputBuffer, bytes: []const u8, skipped: ?ShellOutputSkip) !bool {
        if (skipped != null and self.limits.retain != .tail) return error.SkippedOutputRequiresTail;
        var decoder = self.decoder;
        var pending: std.ArrayList(u8) = .empty;
        defer pending.deinit(self.gpa);
        if (skipped != null) {
            try decoder.finish(decode.Text{ .gpa = self.gpa, .output = &pending });
            decoder = decode.streamDecoder();
        }
        var text: std.ArrayList(u8) = .empty;
        defer text.deinit(self.gpa);
        try decoder.push(bytes, decode.Text{ .gpa = self.gpa, .output = &text });
        const accepted = try self.acceptPrepared(pending.items, text.items, skipped);
        self.decoder = decoder;
        return accepted;
    }
    pub fn end(self: *OutputBuffer) !void {
        _ = try self.pushText("", null);
    }
    /// Sampling never changes the stored margin or a later retained window.
    pub fn snapshot(self: *const OutputBuffer) !Snapshot {
        const selected = range(self.stored.items, self.limits);
        const kept = self.stored.items[selected.from..selected.to];
        const total_lines = self.total_newlines + @as(u64, @intFromBool(!self.ends_with_newline));
        return .{ .text = try sanitizeOutput(self.gpa, kept), .droppedBytes = self.total_bytes - kept.len, .droppedLines = total_lines - lines(kept) };
    }
};

pub const ProgressGate = struct {
    minIntervalMs: u64 = 100,
    bytesPerSecond: u64 = 100 * 1024,
    dirty: bool = false,
    in_flight: bool = false,
    stopped: bool = false,
    next_at_ms: f64 = 0,
    started_at_ms: f64 = 0,
    pub fn mark(self: *ProgressGate) void {
        self.dirty = true;
    }
    pub fn begin(self: *ProgressGate, now_ms: f64) bool {
        if (!std.math.isFinite(now_ms) or self.stopped or self.in_flight or !self.dirty or now_ms < self.next_at_ms) return false;
        self.dirty = false;
        self.in_flight = true;
        self.started_at_ms = now_ms;
        return true;
    }
    pub fn complete(self: *ProgressGate, bytes: u64, success: bool) void {
        std.debug.assert(self.in_flight);
        const size_pause = if (success and self.bytesPerSecond != 0) @as(f64, @floatFromInt(bytes)) * 1000 / @as(f64, @floatFromInt(self.bytesPerSecond)) else 0;
        self.next_at_ms = self.started_at_ms + @max(@as(f64, @floatFromInt(self.minIntervalMs)), size_pause);
        self.in_flight = false;
    }
    pub fn stop(self: *ProgressGate) void {
        self.stopped = true;
    }
};

test "durable output tail skips preserve exact totals sanitization and snapshot-independent margins" {
    const gpa = std.testing.allocator;
    const limits: Limits = .{ .maxBytes = 1000, .maxLines = 2 };
    var full = OutputBuffer.init(gpa, limits);
    defer full.deinit();
    var skipped = OutputBuffer.init(gpa, limits);
    defer skipped.deinit();
    _ = try full.pushText("one\ntwo\nthree\nfour\nfive\nsix", null);
    _ = try skipped.pushText("ee\nfour\nfive\nsix", measure("one\ntwo\nthr"));
    var a = try full.snapshot();
    defer a.deinit(gpa);
    var b = try skipped.snapshot();
    defer b.deinit(gpa);
    try std.testing.expectEqualStrings("five\nsix", a.text);
    try std.testing.expectEqualStrings(a.text, b.text);
    try std.testing.expectEqual(@as(u64, 19), b.droppedBytes);
    try std.testing.expectEqual(@as(u64, 4), b.droppedLines);
    var head = OutputBuffer.init(gpa, .{ .retain = .head });
    defer head.deinit();
    try std.testing.expectError(error.SkippedOutputRequiresTail, head.pushText("x\ny\nz\n", measure("a\n")));
    var gate: ProgressGate = .{};
    gate.mark();
    try std.testing.expect(gate.begin(10));
    gate.mark();
    try std.testing.expect(!gate.begin(20));
    gate.complete(200 * 1024, true);
    try std.testing.expect(!gate.begin(2009));
    try std.testing.expect(gate.begin(2010));
    gate.complete(0, false);
    gate.stop();
    gate.mark();
    try std.testing.expect(!gate.begin(9999));
}

fn allocationProbe(gpa: std.mem.Allocator) !void {
    var buffer = OutputBuffer.init(gpa, .{ .maxBytes = 24, .maxLines = 2 });
    defer buffer.deinit();
    _ = try buffer.pushBytes(&.{ 0xef, 0xbb }, null);
    _ = try buffer.pushBytes(&.{ 0xbf, 0xf0, 0x9f, 0x98, 0x80 }, null);
    _ = try buffer.pushText("first\nsecond\n", null);
    var before = try buffer.snapshot();
    defer before.deinit(gpa);
    _ = try buffer.pushText("oversized\nprefix\nthird\nfourth\nfifth", measure("discarded\nold"));
    var after = try buffer.snapshot();
    defer after.deinit(gpa);
    try std.testing.expectEqualStrings("fourth\nfifth", after.text);
}
test "durable output allocations clean up and failed decoding can be retried atomically" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, allocationProbe, .{});
    var failures: usize = 0;
    for (0..12) |offset| {
        var failing = std.testing.FailingAllocator.init(std.testing.allocator, .{});
        const gpa = failing.allocator();
        var buffer = OutputBuffer.init(gpa, .{ .maxBytes = 24, .maxLines = 2 });
        defer buffer.deinit();
        _ = try buffer.pushText("original\n", null);
        _ = try buffer.pushBytes(&.{ 0xf0, 0x9f }, null);
        const old_bytes = buffer.total_bytes;
        const old_newlines = buffer.total_newlines;
        failing.fail_index = failing.alloc_index + offset;
        _ = buffer.pushBytes(&.{ 0x98, 0x80, 'n', 'e', 'x', 't' }, null) catch |err| {
            failing.fail_index = std.math.maxInt(usize);
            try std.testing.expectEqual(error.OutOfMemory, err);
            try std.testing.expect(failing.has_induced_failure);
            try std.testing.expectEqual(old_bytes, buffer.total_bytes);
            try std.testing.expectEqual(old_newlines, buffer.total_newlines);
            try std.testing.expectEqual(@as(u3, 2), buffer.decoder.remaining);
            _ = try buffer.pushBytes(&.{ 0x98, 0x80, 'n', 'e', 'x', 't' }, null);
            var snapshot = try buffer.snapshot();
            defer snapshot.deinit(gpa);
            try std.testing.expectEqualStrings("original\n😀next", snapshot.text);
            failures += 1;
            continue;
        };
        failing.fail_index = std.math.maxInt(usize);
        break;
    }
    try std.testing.expect(failures > 0);
}
