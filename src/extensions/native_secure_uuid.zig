//! Shared secure UUID v4 primitive for the existing WebCrypto actor and
//! the coding-agent's actual zero-option node:crypto randomUUID import.
const std = @import("std");
pub fn generate(io: std.Io) ![36]u8 {
    var bytes: [16]u8 = undefined;
    try std.Io.randomSecure(io, &bytes);
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    const hex = std.fmt.bytesToHex(bytes, .lower);
    var result: [36]u8 = undefined;
    _ = try std.fmt.bufPrint(&result, "{s}-{s}-{s}-{s}-{s}", .{ hex[0..8], hex[8..12], hex[12..16], hex[16..20], hex[20..32] });
    return result;
}
