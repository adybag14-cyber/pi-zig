//! Native ES256 DPoP proof for login refresh. Secret DER and signing noise are retired.
const std = @import("std");
const Ecdsa = std.crypto.sign.ecdsa.EcdsaP256Sha256;
fn base64(a: std.mem.Allocator, value: []const u8) ![]u8 {
    const codec = std.base64.url_safe_no_pad.Encoder;
    const result = try a.alloc(u8, codec.calcSize(value.len));
    return @constCast(codec.encode(result, value));
}
const Der = struct {
    input: []const u8,
    offset: usize = 0,
    fn read(self: *Der, tag: u8) ![]const u8 {
        if (self.input.len - self.offset < 2 or self.input[self.offset] != tag) return error.InvalidDpopPrivateKey;
        self.offset += 1;
        const first = self.input[self.offset];
        self.offset += 1;
        var length: usize = first;
        if (first >= 128) {
            const count = first & 127;
            if (count == 0 or count > @sizeOf(usize) or count > self.input.len - self.offset) return error.InvalidDpopPrivateKey;
            length = 0;
            for (self.input[self.offset..][0..count]) |byte| length = std.math.add(usize, std.math.mul(usize, length, 256) catch return error.InvalidDpopPrivateKey, byte) catch return error.InvalidDpopPrivateKey;
            self.offset += count;
        }
        if (length > self.input.len - self.offset) return error.InvalidDpopPrivateKey;
        const value = self.input[self.offset..][0..length];
        self.offset += length;
        return value;
    }
};
fn key(a: std.mem.Allocator, pem: []const u8) !Ecdsa.KeyPair {
    const begin_label = if (std.mem.indexOf(u8, pem, "-----BEGIN EC PRIVATE KEY-----") != null) "-----BEGIN EC PRIVATE KEY-----" else "-----BEGIN PRIVATE KEY-----";
    const begin = (std.mem.indexOf(u8, pem, begin_label) orelse return error.InvalidDpopPrivateKey) + begin_label.len;
    const end = std.mem.indexOfPos(u8, pem, begin, "-----END ") orelse return error.InvalidDpopPrivateKey;
    var encoded: std.ArrayList(u8) = .empty;
    defer {
        @memset(encoded.items, 0);
        encoded.deinit(a);
    }
    for (pem[begin..end]) |byte| if (!std.ascii.isWhitespace(byte)) try encoded.append(a, byte);
    const decoder = std.base64.standard.Decoder;
    const der = try a.alloc(u8, try decoder.calcSizeForSlice(encoded.items));
    defer {
        @memset(der, 0);
        a.free(der);
    }
    try decoder.decode(der, encoded.items);
    var root = Der{ .input = der };
    var sequence = Der{ .input = try root.read(0x30) };
    const version = try sequence.read(2);
    if (version.len != 1) return error.InvalidDpopPrivateKey;
    if (version[0] == 0) {
        var algorithm = Der{ .input = try sequence.read(0x30) };
        if (!std.mem.eql(u8, try algorithm.read(6), &.{ 0x2a, 0x86, 0x48, 0xce, 0x3d, 2, 1 })) return error.InvalidDpopPrivateKey;
        if (!std.mem.eql(u8, try algorithm.read(6), &.{ 0x2a, 0x86, 0x48, 0xce, 0x3d, 3, 1, 7 })) return error.InvalidDpopPrivateKey;
        var inner = Der{ .input = try sequence.read(4) };
        sequence = .{ .input = try inner.read(0x30) };
        const inner_version = try sequence.read(2);
        if (!std.mem.eql(u8, inner_version, &.{1})) return error.InvalidDpopPrivateKey;
    } else if (version[0] != 1) return error.InvalidDpopPrivateKey;
    const scalar = try sequence.read(4);
    if (scalar.len > 32 or scalar.len == 0) return error.InvalidDpopPrivateKey;
    if (sequence.offset < sequence.input.len and sequence.input[sequence.offset] == 0xa0) {
        var curve = Der{ .input = try sequence.read(0xa0) };
        if (!std.mem.eql(u8, try curve.read(6), &.{ 0x2a, 0x86, 0x48, 0xce, 0x3d, 3, 1, 7 })) return error.InvalidDpopPrivateKey;
    }
    var bytes: [32]u8 = @splat(0);
    defer @memset(&bytes, 0);
    @memcpy(bytes[32 - scalar.len ..], scalar);
    return Ecdsa.KeyPair.fromSecretKey(try Ecdsa.SecretKey.fromBytes(bytes));
}
pub fn proof(a: std.mem.Allocator, io: std.Io, pem: []const u8, method: []const u8, url: []const u8, now: i64) ![]u8 {
    var pair = try key(a, pem);
    defer @memset(&pair.secret_key.bytes, 0);
    const public = pair.public_key.toUncompressedSec1();
    const x = try base64(a, public[1..33]);
    defer a.free(x);
    const y = try base64(a, public[33..65]);
    defer a.free(y);
    const header = try std.json.Stringify.valueAlloc(a, .{ .alg = "ES256", .typ = "dpop+jwt", .jwk = .{ .kty = "EC", .crv = "P-256", .x = x, .y = y } }, .{});
    defer a.free(header);
    var random: [16]u8 = undefined;
    try io.randomSecure(&random);
    random[6] = (random[6] & 15) | 0x40;
    random[8] = (random[8] & 63) | 0x80;
    const hex = std.fmt.bytesToHex(random, .lower);
    const uuid = try std.fmt.allocPrint(a, "{s}-{s}-{s}-{s}-{s}", .{ hex[0..8], hex[8..12], hex[12..16], hex[16..20], hex[20..32] });
    defer a.free(uuid);
    const payload = try std.json.Stringify.valueAlloc(a, .{ .jti = uuid, .htm = method, .htu = url, .iat = now }, .{});
    defer a.free(payload);
    const header64 = try base64(a, header);
    defer a.free(header64);
    const payload64 = try base64(a, payload);
    defer a.free(payload64);
    const message = try std.fmt.allocPrint(a, "{s}.{s}", .{ header64, payload64 });
    defer a.free(message);
    var noise: [Ecdsa.noise_length]u8 = undefined;
    defer @memset(&noise, 0);
    try io.randomSecure(&noise);
    const signature = (try pair.sign(message, noise)).toBytes();
    const signature64 = try base64(a, &signature);
    defer a.free(signature64);
    return std.fmt.allocPrint(a, "{s}.{s}", .{ message, signature64 });
}
test "native login DPoP proves the method and exact URI with a verifiable ES256 signature" {
    const a = std.testing.allocator;
    const pem = "-----BEGIN EC PRIVATE KEY-----\nMDECAQEEIAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAABoAoGCCqGSM49AwEH\n-----END EC PRIVATE KEY-----\n";
    const token = try proof(a, std.testing.io, pem, "POST", "http://127.0.0.1:1977/v1/token", 1893456000);
    defer a.free(token);
    const dot = std.mem.lastIndexOfScalar(u8, token, '.').?;
    var raw: [64]u8 = undefined;
    try std.base64.url_safe_no_pad.Decoder.decode(&raw, token[dot + 1 ..]);
    const pair = try key(a, pem);
    try Ecdsa.Signature.fromBytes(raw).verify(token[0..dot], pair.public_key);
    const first = std.mem.indexOfScalar(u8, token, '.').?;
    const payload64 = token[first + 1 .. dot];
    const bytes = try a.alloc(u8, try std.base64.url_safe_no_pad.Decoder.calcSizeForSlice(payload64));
    defer a.free(bytes);
    try std.base64.url_safe_no_pad.Decoder.decode(bytes, payload64);
    var payload = try std.json.parseFromSlice(std.json.Value, a, bytes, .{});
    defer payload.deinit();
    try std.testing.expectEqualStrings("POST", payload.value.object.get("htm").?.string);
    try std.testing.expectEqualStrings("http://127.0.0.1:1977/v1/token", payload.value.object.get("htu").?.string);
    try std.testing.expectEqual(@as(i64, 1893456000), payload.value.object.get("iat").?.integer);
    const uuid = payload.value.object.get("jti").?.string;
    try std.testing.expectEqual(@as(usize, 36), uuid.len);
    try std.testing.expectEqual(@as(u8, '4'), uuid[14]);
    try std.testing.expect(std.mem.indexOfScalar(u8, "89ab", uuid[19]) != null);
}
