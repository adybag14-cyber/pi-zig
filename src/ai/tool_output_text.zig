//! Source4dd tool-output presence for typed UTF-8 providers. Inspect whitespace
//! without altering the original bytes later serialized as nonempty text.
const std = @import("std");
pub fn hasText(text: []const u8) bool {
    var offset: usize = 0;
    while (offset < text.len) {
        const width = std.unicode.utf8ByteSequenceLength(text[offset]) catch return true;
        if (width > text.len - offset) return true;
        const point = std.unicode.utf8Decode(text[offset..][0..width]) catch return true;
        switch (point) {
            0x09...0x0d, 0x20, 0xa0, 0x1680, 0x2000...0x200a, 0x2028, 0x2029, 0x202f, 0x205f, 0x3000, 0xfeff => {},
            else => return true,
        }
        offset += width;
    }
    return false;
}
test "typed tool output follows ECMAScript trim whitespace without discarding text" {
    try std.testing.expect(!hasText(""));
    const whitespace = [_]u21{ 0x09, 0x0a, 0x0b, 0x0c, 0x0d, 0x20, 0xa0, 0x1680, 0x2000, 0x2001, 0x2002, 0x2003, 0x2004, 0x2005, 0x2006, 0x2007, 0x2008, 0x2009, 0x200a, 0x2028, 0x2029, 0x202f, 0x205f, 0x3000, 0xfeff };
    for (whitespace) |point| {
        var encoded: [4]u8 = undefined;
        const length = try std.unicode.utf8Encode(point, &encoded);
        try std.testing.expect(!hasText(encoded[0..length]));
    }
    const non_whitespace = [_]u21{ 0, 0x85, 0x180e, 0x200b, 0x200d, 'x', 0x1f600 };
    for (non_whitespace) |point| {
        var encoded: [4]u8 = undefined;
        const length = try std.unicode.utf8Encode(point, &encoded);
        try std.testing.expect(hasText(encoded[0..length]));
    }
    try std.testing.expect(hasText(" \t\u{feff} original \r\n"));
    try std.testing.expect(hasText("\xff"));
    try std.testing.expect(hasText("\xe2\x80"));
}
