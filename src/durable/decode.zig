//! Streaming WHATWG UTF-8 decoding, with explicit leading BOM handling.
const std = @import("std");

pub fn startsWithBom(bytes: []const u8) bool {
    return bytes.len >= 3 and std.mem.eql(u8, bytes[0..3], &.{ 0xef, 0xbb, 0xbf });
}

/// Sink implements `codepoint(u21) !void`. No allocation is required by the
/// decoder, so counting and line scanning remain independent of input size.
pub const Decoder = struct {
    drop_initial_bom: bool = false,
    started: bool = false,
    remaining: u3 = 0,
    scalar: u21 = 0,
    lower: u8 = 0x80,
    upper: u8 = 0xbf,

    fn emit(self: *Decoder, point: u21, sink: anytype) !void {
        if (!self.started) {
            self.started = true;
            if (self.drop_initial_bom and point == 0xfeff) return;
        }
        try sink.codepoint(point);
    }

    pub fn push(self: *Decoder, bytes: []const u8, sink: anytype) !void {
        var index: usize = 0;
        while (index < bytes.len) {
            const byte = bytes[index];
            if (self.remaining != 0) {
                if (byte < self.lower or byte > self.upper) {
                    self.remaining = 0;
                    self.scalar = 0;
                    self.lower = 0x80;
                    self.upper = 0xbf;
                    try self.emit(0xfffd, sink);
                    continue; // Reprocess the byte as a new sequence.
                }
                self.lower = 0x80;
                self.upper = 0xbf;
                self.scalar = (self.scalar << 6) | @as(u21, byte & 0x3f);
                self.remaining -= 1;
                if (self.remaining == 0) try self.emit(self.scalar, sink);
            } else if (byte < 0x80) {
                try self.emit(byte, sink);
            } else if (byte >= 0xc2 and byte <= 0xdf) {
                self.scalar = byte & 0x1f;
                self.remaining = 1;
            } else if (byte >= 0xe0 and byte <= 0xef) {
                self.scalar = byte & 0x0f;
                self.remaining = 2;
                self.lower = if (byte == 0xe0) 0xa0 else 0x80;
                self.upper = if (byte == 0xed) 0x9f else 0xbf;
            } else if (byte >= 0xf0 and byte <= 0xf4) {
                self.scalar = byte & 7;
                self.remaining = 3;
                self.lower = if (byte == 0xf0) 0x90 else 0x80;
                self.upper = if (byte == 0xf4) 0x8f else 0xbf;
            } else try self.emit(0xfffd, sink);
            index += 1;
        }
    }

    pub fn finish(self: *Decoder, sink: anytype) !void {
        if (self.remaining != 0) {
            self.remaining = 0;
            self.scalar = 0;
            self.lower = 0x80;
            self.upper = 0xbf;
            try self.emit(0xfffd, sink);
        }
    }
};

pub const StreamDecoder = Decoder;
pub fn rangeDecoder() Decoder {
    return .{};
}
pub fn streamDecoder() Decoder {
    return .{ .drop_initial_bom = true };
}

pub const Count = struct {
    bytes: *u64,
    pub fn codepoint(self: Count, point: u21) !void {
        const size: u64 = if (point < 0x80) 1 else if (point < 0x800) 2 else if (point < 0x10000) 3 else 4;
        self.bytes.* = std.math.add(u64, self.bytes.*, size) catch return error.DecodedSizeOverflow;
    }
};
pub const Text = struct {
    gpa: std.mem.Allocator,
    output: *std.ArrayList(u8),
    pub fn codepoint(self: Text, point: u21) !void {
        var bytes: [4]u8 = undefined;
        const length = try std.unicode.utf8Encode(point, &bytes);
        try self.output.appendSlice(self.gpa, bytes[0..length]);
    }
};
pub fn decode(gpa: std.mem.Allocator, bytes: []const u8, ignore_bom: bool) ![]u8 {
    var output: std.ArrayList(u8) = .empty;
    defer output.deinit(gpa);
    var decoder: Decoder = .{ .drop_initial_bom = !ignore_bom };
    const sink: Text = .{ .gpa = gpa, .output = &output };
    try decoder.push(bytes, sink);
    try decoder.finish(sink);
    return output.toOwnedSlice(gpa);
}

test "durable stream decoding preserves a noninitial BOM after malformed split UTF8" {
    const bytes = [_]u8{ 0xef, 0xbb, 0xbf, 0xe2, 0x82, 0xef, 0xbb, 0xbf, 0x61, 0xf0, 0x9f };
    var output: std.ArrayList(u8) = .empty;
    defer output.deinit(std.testing.allocator);
    var decoder = streamDecoder();
    const sink: Text = .{ .gpa = std.testing.allocator, .output = &output };
    for (bytes) |byte| try decoder.push(&.{byte}, sink);
    try decoder.finish(sink);
    try std.testing.expectEqualStrings("\xef\xbf\xbd\xef\xbb\xbfa\xef\xbf\xbd", output.items);
    const complete = try decode(std.testing.allocator, &bytes, false);
    defer std.testing.allocator.free(complete);
    try std.testing.expectEqualStrings(complete, output.items);
}
