//! Bounded OSC 52 clipboard framing shared by retained and coding-agent UI.
//! The 100,000-byte encoded ceiling matches upstream Pi and prevents very
//! large terminal control strings from desynchronizing renderers.
const std = @import("std");
const Io = std.Io;

pub const max_encoded_length: usize = 100_000;

pub fn sequenceAlloc(gpa: std.mem.Allocator, text: []const u8) !?[]u8 {
    const Encoder = std.base64.standard.Encoder;
    const encoded_len = Encoder.calcSize(text.len);
    if (encoded_len > max_encoded_length) return null;
    const encoded = try gpa.alloc(u8, encoded_len);
    defer gpa.free(encoded);
    _ = Encoder.encode(encoded, text);
    return try std.fmt.allocPrint(gpa, "\x1b]52;c;{s}\x07", .{encoded});
}

pub fn write(gpa: std.mem.Allocator, io: Io, text: []const u8) !bool {
    const sequence = try sequenceAlloc(gpa, text) orelse return false;
    defer gpa.free(sequence);
    try std.Io.File.stdout().writeStreamingAll(io, sequence);
    return true;
}

test "OSC 52 framing is deterministic and bounded" {
    const gpa = std.testing.allocator;
    const sequence = (try sequenceAlloc(gpa, "hello")).?;
    defer gpa.free(sequence);
    try std.testing.expectEqualStrings("\x1b]52;c;aGVsbG8=\x07", sequence);

    const too_large = try gpa.alloc(u8, (max_encoded_length / 4) * 3 + 4);
    defer gpa.free(too_large);
    @memset(too_large, 'x');
    try std.testing.expect((try sequenceAlloc(gpa, too_large)) == null);
}
