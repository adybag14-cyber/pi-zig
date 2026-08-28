//! Shared RFC 7636 PKCE helpers for native OAuth flows.
const std = @import("std");

pub const Pkce = struct {
    verifier: []u8,
    challenge: []u8,

    pub fn deinit(self: *Pkce, gpa: std.mem.Allocator) void {
        gpa.free(self.verifier);
        gpa.free(self.challenge);
        self.* = undefined;
    }
};

pub fn base64UrlNoPadAlloc(gpa: std.mem.Allocator, bytes: []const u8) ![]u8 {
    const size = std.base64.url_safe_no_pad.Encoder.calcSize(bytes.len);
    const out = try gpa.alloc(u8, size);
    _ = std.base64.url_safe_no_pad.Encoder.encode(out, bytes);
    return out;
}

/// Generate a 32-byte verifier and S256 challenge as required by RFC 7636.
pub fn generate(gpa: std.mem.Allocator, io: std.Io) !Pkce {
    var verifier_bytes: [32]u8 = undefined;
    try io.randomSecure(&verifier_bytes);
    const verifier = try base64UrlNoPadAlloc(gpa, &verifier_bytes);
    errdefer gpa.free(verifier);

    var digest: [std.crypto.hash.sha2.Sha256.digest_length]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(verifier, &digest, .{});
    return .{
        .verifier = verifier,
        .challenge = try base64UrlNoPadAlloc(gpa, &digest),
    };
}

/// Generate a UUIDv4 using the shared secure RNG. OpenRouter uses this for a
/// one-shot callback path so concurrent login attempts never share a route.
pub fn generateUuidV4(gpa: std.mem.Allocator, io: std.Io) ![]u8 {
    var raw: [16]u8 = undefined;
    try io.randomSecure(&raw);
    raw[6] = (raw[6] & 0x0f) | 0x40;
    raw[8] = (raw[8] & 0x3f) | 0x80;
    return std.fmt.allocPrint(gpa, "{x:0>2}{x:0>2}{x:0>2}{x:0>2}-{x:0>2}{x:0>2}-{x:0>2}{x:0>2}-{x:0>2}{x:0>2}-{x:0>2}{x:0>2}{x:0>2}{x:0>2}{x:0>2}{x:0>2}", .{ raw[0], raw[1], raw[2], raw[3], raw[4], raw[5], raw[6], raw[7], raw[8], raw[9], raw[10], raw[11], raw[12], raw[13], raw[14], raw[15] });
}

/// OpenAI Codex uses randomBytes(16).toString("hex") for OAuth state.
pub fn generateHexState(gpa: std.mem.Allocator, io: std.Io) ![]u8 {
    var raw: [16]u8 = undefined;
    try io.randomSecure(&raw);
    const out = try gpa.alloc(u8, raw.len * 2);
    const hex = "0123456789abcdef";
    for (raw, 0..) |b, i| {
        out[i * 2] = hex[b >> 4];
        out[i * 2 + 1] = hex[b & 0x0f];
    }
    return out;
}

test "PKCE verifier and S256 challenge are base64url without padding" {
    const gpa = std.testing.allocator;
    var pair = try generate(gpa, std.testing.io);
    defer pair.deinit(gpa);
    try std.testing.expectEqual(@as(usize, 43), pair.verifier.len);
    try std.testing.expectEqual(@as(usize, 43), pair.challenge.len);
    try std.testing.expect(std.mem.indexOfScalar(u8, pair.verifier, '=') == null);
    try std.testing.expect(std.mem.indexOfScalar(u8, pair.challenge, '=') == null);

    var digest: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(pair.verifier, &digest, .{});
    const expected = try base64UrlNoPadAlloc(gpa, &digest);
    defer gpa.free(expected);
    try std.testing.expectEqualStrings(expected, pair.challenge);
}

test "OpenAI state is 16 random bytes rendered as lowercase hex" {
    const gpa = std.testing.allocator;
    const state = try generateHexState(gpa, std.testing.io);
    defer gpa.free(state);
    try std.testing.expectEqual(@as(usize, 32), state.len);
    for (state) |c| try std.testing.expect((c >= '0' and c <= '9') or (c >= 'a' and c <= 'f'));
}

test "shared UUIDv4 generator sets version and variant" {
    const gpa = std.testing.allocator;
    const value = try generateUuidV4(gpa, std.testing.io);
    defer gpa.free(value);
    try std.testing.expectEqual(@as(usize, 36), value.len);
    try std.testing.expectEqual(@as(u8, '4'), value[14]);
    try std.testing.expect(std.mem.indexOfScalar(u8, "89ab", value[19]) != null);
    try std.testing.expectEqual(@as(u8, '-'), value[8]);
    try std.testing.expectEqual(@as(u8, '-'), value[13]);
    try std.testing.expectEqual(@as(u8, '-'), value[18]);
    try std.testing.expectEqual(@as(u8, '-'), value[23]);
}
