//! Four-byte big-endian length framing compatible with packages/protocol/src/framing.ts.
const std = @import("std");

pub const DEFAULT_MAX_FRAME_LENGTH: usize = 16 * 1024 * 1024;
pub const Error = error{ FrameTooLarge, InvalidFrame, TruncatedFrame, DecoderEnded, DecoderFailed };

pub fn encodeFrame(gpa: std.mem.Allocator, payload: []const u8) ![]u8 {
    if (payload.len > std.math.maxInt(u32)) return Error.FrameTooLarge;
    const out = try gpa.alloc(u8, payload.len + 4);
    const n: u32 = @intCast(payload.len);
    out[0] = @truncate(n >> 24);
    out[1] = @truncate(n >> 16);
    out[2] = @truncate(n >> 8);
    out[3] = @truncate(n);
    @memcpy(out[4..], payload);
    return out;
}

pub fn assertCompleteFrame(frame: []const u8, max_frame_length: usize) !void {
    if (frame.len < 4) return Error.TruncatedFrame;
    const n = decodeLength(frame[0..4]);
    if (n > max_frame_length) return Error.FrameTooLarge;
    if (frame.len != n + 4) return Error.InvalidFrame;
}

fn decodeLength(h: []const u8) usize {
    return (@as(usize, h[0]) << 24) | (@as(usize, h[1]) << 16) | (@as(usize, h[2]) << 8) | @as(usize, h[3]);
}

pub const Decoder = struct {
    gpa: std.mem.Allocator,
    max_frame_length: usize = DEFAULT_MAX_FRAME_LENGTH,
    buffer: std.ArrayList(u8) = .empty,
    failed: bool = false,
    ended: bool = false,

    pub fn deinit(self: *Decoder) void {
        self.buffer.deinit(self.gpa);
        self.* = undefined;
    }

    pub fn push(self: *Decoder, chunk: []const u8) ![][]u8 {
        if (self.failed) return Error.DecoderFailed;
        if (self.ended) return Error.DecoderEnded;
        try self.buffer.appendSlice(self.gpa, chunk);
        var frames: std.ArrayList([]u8) = .empty;
        errdefer {
            for (frames.items) |f| self.gpa.free(f);
            frames.deinit(self.gpa);
        }
        var consumed: usize = 0;
        while (self.buffer.items.len - consumed >= 4) {
            const len = decodeLength(self.buffer.items[consumed..][0..4]);
            if (len > self.max_frame_length) {
                self.failed = true;
                return Error.FrameTooLarge;
            }
            if (self.buffer.items.len - consumed < len + 4) break;
            try frames.append(self.gpa, try self.gpa.dupe(u8, self.buffer.items[consumed + 4 .. consumed + 4 + len]));
            consumed += 4 + len;
        }
        if (consumed > 0) {
            const remain = self.buffer.items.len - consumed;
            std.mem.copyForwards(u8, self.buffer.items[0..remain], self.buffer.items[consumed..]);
            self.buffer.shrinkRetainingCapacity(remain);
        }
        return try frames.toOwnedSlice(self.gpa);
    }

    pub fn end(self: *Decoder) !void {
        if (self.failed) return Error.DecoderFailed;
        if (self.ended) return Error.DecoderEnded;
        if (self.buffer.items.len != 0) {
            self.failed = true;
            return Error.TruncatedFrame;
        }
        self.ended = true;
    }
};

test "frame encode and fragmented decode" {
    const gpa = std.testing.allocator;
    const f = try encodeFrame(gpa, "hello");
    defer gpa.free(f);
    try assertCompleteFrame(f, DEFAULT_MAX_FRAME_LENGTH);
    var d = Decoder{ .gpa = gpa };
    defer d.deinit();
    const a = try d.push(f[0..2]);
    defer {
        for (a) |x| gpa.free(x);
        gpa.free(a);
    }
    try std.testing.expectEqual(@as(usize, 0), a.len);
    const b = try d.push(f[2..]);
    defer {
        for (b) |x| gpa.free(x);
        gpa.free(b);
    }
    try std.testing.expectEqual(@as(usize, 1), b.len);
    try std.testing.expectEqualStrings("hello", b[0]);
    try d.end();
}

test "frame prefix handles multi-byte lengths without narrowing traps" {
    const gpa = std.testing.allocator;
    const payload = try gpa.alloc(u8, 70_000);
    defer gpa.free(payload);
    @memset(payload, 0xaa);
    const frame = try encodeFrame(gpa, payload);
    defer gpa.free(frame);
    try std.testing.expectEqual(@as(usize, 70_000), decodeLength(frame[0..4]));
    try assertCompleteFrame(frame, 100_000);
}
