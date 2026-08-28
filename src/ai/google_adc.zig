//! Minimal Google Application Default Credentials support for Vertex AI.
//! Supports the two common JSON ADC forms without depending on gcloud or a
//! Google SDK: authorized_user refresh credentials and service_account keys.
const std = @import("std");
const bootstrap_http = @import("bootstrap_http.zig");
const Io = std.Io;

pub const Kind = enum { authorized_user, service_account };

pub const Credential = struct {
    kind: Kind,
    client_id: ?[]u8 = null,
    client_secret: ?[]u8 = null,
    refresh_token: ?[]u8 = null,
    client_email: ?[]u8 = null,
    private_key: ?[]u8 = null,
    token_uri: []u8,
    quota_project_id: ?[]u8 = null,
    project_id: ?[]u8 = null,

    pub fn deinit(self: *Credential, gpa: std.mem.Allocator) void {
        if (self.client_id) |v| gpa.free(v);
        if (self.client_secret) |v| gpa.free(v);
        if (self.refresh_token) |v| gpa.free(v);
        if (self.client_email) |v| gpa.free(v);
        if (self.private_key) |v| gpa.free(v);
        gpa.free(self.token_uri);
        if (self.quota_project_id) |v| gpa.free(v);
        if (self.project_id) |v| gpa.free(v);
        self.* = undefined;
    }
};

pub const AccessToken = struct {
    token: []u8,
    expiration_unix: i64,

    pub fn deinit(self: *AccessToken, gpa: std.mem.Allocator) void {
        gpa.free(self.token);
        self.* = undefined;
    }
};

fn dupField(gpa: std.mem.Allocator, obj: std.json.ObjectMap, name: []const u8) !?[]u8 {
    const value = obj.get(name) orelse return null;
    if (value != .string or value.string.len == 0) return null;
    return try gpa.dupe(u8, value.string);
}

pub fn parse(gpa: std.mem.Allocator, raw: []const u8) !Credential {
    var parsed = try std.json.parseFromSlice(std.json.Value, gpa, raw, .{});
    defer parsed.deinit();
    if (parsed.value != .object) return error.InvalidGoogleCredentials;
    const obj = parsed.value.object;
    const type_value = obj.get("type") orelse return error.InvalidGoogleCredentials;
    if (type_value != .string) return error.InvalidGoogleCredentials;
    const kind: Kind = if (std.mem.eql(u8, type_value.string, "authorized_user")) .authorized_user else if (std.mem.eql(u8, type_value.string, "service_account")) .service_account else return error.UnsupportedGoogleCredentialType;

    var out: Credential = .{
        .kind = kind,
        .token_uri = (try dupField(gpa, obj, "token_uri")) orelse try gpa.dupe(u8, "https://oauth2.googleapis.com/token"),
    };
    errdefer out.deinit(gpa);
    out.quota_project_id = try dupField(gpa, obj, "quota_project_id");
    out.project_id = try dupField(gpa, obj, "project_id");
    switch (kind) {
        .authorized_user => {
            out.client_id = (try dupField(gpa, obj, "client_id")) orelse return error.InvalidGoogleCredentials;
            out.client_secret = (try dupField(gpa, obj, "client_secret")) orelse return error.InvalidGoogleCredentials;
            out.refresh_token = (try dupField(gpa, obj, "refresh_token")) orelse return error.InvalidGoogleCredentials;
        },
        .service_account => {
            out.client_email = (try dupField(gpa, obj, "client_email")) orelse return error.InvalidGoogleCredentials;
            out.private_key = (try dupField(gpa, obj, "private_key")) orelse return error.InvalidGoogleCredentials;
        },
    }
    return out;
}

pub fn credentialsPath(gpa: std.mem.Allocator, environ: *const std.process.Environ.Map) !?[]u8 {
    if (environ.get("GOOGLE_APPLICATION_CREDENTIALS")) |path| {
        if (path.len == 0) return null;
        return try gpa.dupe(u8, path);
    }
    const home = environ.get("HOME") orelse environ.get("USERPROFILE") orelse return null;
    return try std.fs.path.join(gpa, &.{ home, ".config", "gcloud", "application_default_credentials.json" });
}

pub fn load(gpa: std.mem.Allocator, io: Io, environ: *const std.process.Environ.Map) !?Credential {
    const path = (try credentialsPath(gpa, environ)) orelse return null;
    defer gpa.free(path);
    const raw = std.Io.Dir.cwd().readFileAlloc(io, path, gpa, .limited(1024 * 1024)) catch |err| switch (err) {
        error.FileNotFound => return null,
        else => return err,
    };
    defer gpa.free(raw);
    return try parse(gpa, raw);
}

pub fn isAuthMarker(value: []const u8) bool {
    const trimmed = std.mem.trim(u8, value, " \t\r\n");
    return std.mem.eql(u8, trimmed, "gcp-vertex-credentials") or
        (trimmed.len >= 2 and trimmed[0] == '<' and trimmed[trimmed.len - 1] == '>');
}

fn appendFormEncoded(w: *std.Io.Writer, value: []const u8) !void {
    const hex = "0123456789ABCDEF";
    for (value) |c| {
        if (std.ascii.isAlphanumeric(c) or c == '-' or c == '_' or c == '.' or c == '~') {
            try w.writeByte(c);
        } else {
            try w.writeByte('%');
            try w.writeByte(hex[c >> 4]);
            try w.writeByte(hex[c & 0x0f]);
        }
    }
}

pub fn buildAuthorizedUserForm(gpa: std.mem.Allocator, credential: *const Credential) ![]u8 {
    if (credential.kind != .authorized_user) return error.WrongGoogleCredentialType;
    var out: std.Io.Writer.Allocating = .init(gpa);
    errdefer out.deinit();
    try out.writer.writeAll("grant_type=refresh_token&client_id=");
    try appendFormEncoded(&out.writer, credential.client_id.?);
    try out.writer.writeAll("&client_secret=");
    try appendFormEncoded(&out.writer, credential.client_secret.?);
    try out.writer.writeAll("&refresh_token=");
    try appendFormEncoded(&out.writer, credential.refresh_token.?);
    return out.toOwnedSlice();
}

pub fn parseTokenResponse(gpa: std.mem.Allocator, raw: []const u8, now_unix: i64) !AccessToken {
    var parsed = try std.json.parseFromSlice(std.json.Value, gpa, raw, .{});
    defer parsed.deinit();
    if (parsed.value != .object) return error.InvalidGoogleTokenResponse;
    const token_value = parsed.value.object.get("access_token") orelse return error.InvalidGoogleTokenResponse;
    if (token_value != .string or token_value.string.len == 0) return error.InvalidGoogleTokenResponse;
    const expires_value = parsed.value.object.get("expires_in");
    const expires_in: i64 = if (expires_value) |v| switch (v) {
        .integer => |n| n,
        .float => |n| @intFromFloat(n),
        else => 3600,
    } else 3600;
    return .{ .token = try gpa.dupe(u8, token_value.string), .expiration_unix = now_unix + @max(@as(i64, 1), expires_in) };
}

pub fn refreshAuthorizedUser(gpa: std.mem.Allocator, io: Io, credential: *const Credential) !AccessToken {
    return refreshAuthorizedUserWithOptions(gpa, io, credential, .{});
}

pub fn refreshAuthorizedUserWithOptions(gpa: std.mem.Allocator, io: Io, credential: *const Credential, options: bootstrap_http.Options) !AccessToken {
    const body = try buildAuthorizedUserForm(gpa, credential);
    defer gpa.free(body);
    var response = try bootstrap_http.request(gpa, io, .{
        .url = credential.token_uri,
        .method = .POST,
        .payload = body,
        .headers = &.{.{ .name = "content-type", .value = "application/x-www-form-urlencoded" }},
        .options = options,
    });
    defer response.deinit(gpa);
    if (response.status < 200 or response.status >= 300) return error.GoogleOAuthRefreshFailed;
    return parseTokenResponse(gpa, response.body, Io.Clock.real.now(io).toSeconds());
}

const RsaParts = struct {
    modulus: []const u8,
    public_exponent: []const u8,
    private_exponent: []const u8,
};

fn trimInteger(bytes: []const u8) []const u8 {
    var i: usize = 0;
    while (i + 1 < bytes.len and bytes[i] == 0) : (i += 1) {}
    return bytes[i..];
}

fn parsePkcs1RsaPrivateKey(der_bytes: []const u8) !RsaParts {
    const der = std.crypto.Certificate.der;
    const seq = try der.Element.parse(der_bytes, 0);
    if (seq.identifier.tag != .sequence) return error.InvalidRsaPrivateKey;
    var index = seq.slice.start;
    const version = try der.Element.parse(der_bytes, index);
    if (version.identifier.tag != .integer) return error.InvalidRsaPrivateKey;
    index = version.slice.end;
    const modulus = try der.Element.parse(der_bytes, index);
    if (modulus.identifier.tag != .integer) return error.InvalidRsaPrivateKey;
    index = modulus.slice.end;
    const public_exponent = try der.Element.parse(der_bytes, index);
    if (public_exponent.identifier.tag != .integer) return error.InvalidRsaPrivateKey;
    index = public_exponent.slice.end;
    const private_exponent = try der.Element.parse(der_bytes, index);
    if (private_exponent.identifier.tag != .integer) return error.InvalidRsaPrivateKey;
    return .{
        .modulus = trimInteger(der_bytes[modulus.slice.start..modulus.slice.end]),
        .public_exponent = trimInteger(der_bytes[public_exponent.slice.start..public_exponent.slice.end]),
        .private_exponent = trimInteger(der_bytes[private_exponent.slice.start..private_exponent.slice.end]),
    };
}

fn unwrapPkcs8(der_bytes: []const u8) ![]const u8 {
    const der = std.crypto.Certificate.der;
    const seq = try der.Element.parse(der_bytes, 0);
    if (seq.identifier.tag != .sequence) return error.InvalidRsaPrivateKey;
    var index = seq.slice.start;
    const version = try der.Element.parse(der_bytes, index);
    if (version.identifier.tag != .integer) return error.InvalidRsaPrivateKey;
    index = version.slice.end;
    const algorithm = try der.Element.parse(der_bytes, index);
    if (algorithm.identifier.tag != .sequence) return error.InvalidRsaPrivateKey;
    index = algorithm.slice.end;
    const private_key = try der.Element.parse(der_bytes, index);
    if (private_key.identifier.tag != .octetstring) return error.InvalidRsaPrivateKey;
    return der_bytes[private_key.slice.start..private_key.slice.end];
}

fn decodePrivateKeyPem(gpa: std.mem.Allocator, pem: []const u8) ![]u8 {
    const pkcs8_begin = "-----BEGIN PRIVATE KEY-----";
    const pkcs8_end = "-----END PRIVATE KEY-----";
    const pkcs1_begin = "-----BEGIN RSA PRIVATE KEY-----";
    const pkcs1_end = "-----END RSA PRIVATE KEY-----";
    const begin, const end = if (std.mem.indexOf(u8, pem, pkcs8_begin)) |start|
        .{ start + pkcs8_begin.len, std.mem.indexOfPos(u8, pem, start + pkcs8_begin.len, pkcs8_end) orelse return error.InvalidPrivateKeyPem }
    else if (std.mem.indexOf(u8, pem, pkcs1_begin)) |start|
        .{ start + pkcs1_begin.len, std.mem.indexOfPos(u8, pem, start + pkcs1_begin.len, pkcs1_end) orelse return error.InvalidPrivateKeyPem }
    else
        return error.InvalidPrivateKeyPem;

    var filtered: std.ArrayList(u8) = .empty;
    defer filtered.deinit(gpa);
    for (pem[begin..end]) |c| if (!std.ascii.isWhitespace(c)) try filtered.append(gpa, c);
    const decoded_len = try std.base64.standard.Decoder.calcSizeForSlice(filtered.items);
    const decoded = try gpa.alloc(u8, decoded_len);
    errdefer gpa.free(decoded);
    try std.base64.standard.Decoder.decode(decoded, filtered.items);
    return decoded;
}

fn parseRsaPrivateKeyPem(gpa: std.mem.Allocator, pem: []const u8) !struct { der: []u8, parts: RsaParts } {
    const decoded = try decodePrivateKeyPem(gpa, pem);
    errdefer gpa.free(decoded);
    const is_pkcs8 = std.mem.indexOf(u8, pem, "-----BEGIN PRIVATE KEY-----") != null;
    const pkcs1 = if (is_pkcs8) try unwrapPkcs8(decoded) else decoded;
    return .{ .der = decoded, .parts = try parsePkcs1RsaPrivateKey(pkcs1) };
}

fn rsaSha256Sign(gpa: std.mem.Allocator, private_key_pem: []const u8, message: []const u8) ![]u8 {
    const parsed = try parseRsaPrivateKeyPem(gpa, private_key_pem);
    defer gpa.free(parsed.der);
    const parts = parsed.parts;
    if (parts.modulus.len < 64 or parts.modulus.len > 512) return error.UnsupportedRsaModulus;

    var digest: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(message, &digest, .{});
    const digest_info_prefix = [_]u8{
        0x30, 0x31, 0x30, 0x0d, 0x06, 0x09, 0x60, 0x86, 0x48, 0x01,
        0x65, 0x03, 0x04, 0x02, 0x01, 0x05, 0x00, 0x04, 0x20,
    };
    const trailer_len = digest_info_prefix.len + digest.len;
    if (parts.modulus.len < trailer_len + 11) return error.UnsupportedRsaModulus;
    const encoded = try gpa.alloc(u8, parts.modulus.len);
    defer gpa.free(encoded);
    encoded[0] = 0;
    encoded[1] = 1;
    const separator = parts.modulus.len - trailer_len - 1;
    @memset(encoded[2..separator], 0xff);
    encoded[separator] = 0;
    @memcpy(encoded[separator + 1 ..][0..digest_info_prefix.len], &digest_info_prefix);
    @memcpy(encoded[separator + 1 + digest_info_prefix.len ..], &digest);

    const Modulus = std.crypto.ff.Modulus(4096);
    const modulus = try Modulus.fromBytes(parts.modulus, .big);
    const message_fe = try Modulus.Fe.fromBytes(modulus, encoded, .big);
    const signature_fe = try modulus.powWithEncodedExponent(message_fe, parts.private_exponent, .big);
    const signature = try gpa.alloc(u8, parts.modulus.len);
    errdefer gpa.free(signature);
    try signature_fe.toBytes(signature, .big);
    return signature;
}

fn appendBase64Url(gpa: std.mem.Allocator, bytes: []const u8) ![]u8 {
    const size = std.base64.url_safe_no_pad.Encoder.calcSize(bytes.len);
    const out = try gpa.alloc(u8, size);
    _ = std.base64.url_safe_no_pad.Encoder.encode(out, bytes);
    return out;
}

pub fn buildServiceAccountAssertion(gpa: std.mem.Allocator, credential: *const Credential, now_unix: i64) ![]u8 {
    if (credential.kind != .service_account) return error.WrongGoogleCredentialType;
    const header = "{\"alg\":\"RS256\",\"typ\":\"JWT\"}";
    var claims: std.Io.Writer.Allocating = .init(gpa);
    defer claims.deinit();
    try claims.writer.writeAll("{\"iss\":");
    try std.json.Stringify.value(credential.client_email.?, .{}, &claims.writer);
    try claims.writer.writeAll(",\"scope\":\"https://www.googleapis.com/auth/cloud-platform\",\"aud\":");
    try std.json.Stringify.value(credential.token_uri, .{}, &claims.writer);
    try claims.writer.print(",\"iat\":{d},\"exp\":{d}}}", .{ now_unix, now_unix + 3600 });

    const h64 = try appendBase64Url(gpa, header);
    defer gpa.free(h64);
    const c64 = try appendBase64Url(gpa, claims.written());
    defer gpa.free(c64);
    const signing_input = try std.fmt.allocPrint(gpa, "{s}.{s}", .{ h64, c64 });
    defer gpa.free(signing_input);
    const signature = try rsaSha256Sign(gpa, credential.private_key.?, signing_input);
    defer gpa.free(signature);
    const s64 = try appendBase64Url(gpa, signature);
    defer gpa.free(s64);
    return std.fmt.allocPrint(gpa, "{s}.{s}", .{ signing_input, s64 });
}

pub fn buildServiceAccountForm(gpa: std.mem.Allocator, assertion: []const u8) ![]u8 {
    var out: std.Io.Writer.Allocating = .init(gpa);
    errdefer out.deinit();
    try out.writer.writeAll("grant_type=urn%3Aietf%3Aparams%3Aoauth%3Agrant-type%3Ajwt-bearer&assertion=");
    try appendFormEncoded(&out.writer, assertion);
    return out.toOwnedSlice();
}

pub fn refreshServiceAccount(gpa: std.mem.Allocator, io: Io, credential: *const Credential) !AccessToken {
    return refreshServiceAccountWithOptions(gpa, io, credential, .{});
}

pub fn refreshServiceAccountWithOptions(gpa: std.mem.Allocator, io: Io, credential: *const Credential, options: bootstrap_http.Options) !AccessToken {
    const now_unix = Io.Clock.real.now(io).toSeconds();
    const assertion = try buildServiceAccountAssertion(gpa, credential, now_unix);
    defer gpa.free(assertion);
    const body = try buildServiceAccountForm(gpa, assertion);
    defer gpa.free(body);
    var response = try bootstrap_http.request(gpa, io, .{
        .url = credential.token_uri,
        .method = .POST,
        .payload = body,
        .headers = &.{.{ .name = "content-type", .value = "application/x-www-form-urlencoded" }},
        .options = options,
    });
    defer response.deinit(gpa);
    if (response.status < 200 or response.status >= 300) return error.GoogleOAuthRefreshFailed;
    return parseTokenResponse(gpa, response.body, now_unix);
}

test "authorized_user ADC parses and forms refresh request" {
    const gpa = std.testing.allocator;
    var c = try parse(gpa,
        \\{"type":"authorized_user","client_id":"a+b","client_secret":"s/e","refresh_token":"r t","quota_project_id":"quota"}
    );
    defer c.deinit(gpa);
    try std.testing.expectEqual(Kind.authorized_user, c.kind);
    try std.testing.expectEqualStrings("quota", c.quota_project_id.?);
    const form = try buildAuthorizedUserForm(gpa, &c);
    defer gpa.free(form);
    try std.testing.expectEqualStrings("grant_type=refresh_token&client_id=a%2Bb&client_secret=s%2Fe&refresh_token=r%20t", form);
}

test "ADC token response owns token and expiration" {
    const gpa = std.testing.allocator;
    var token = try parseTokenResponse(gpa, "{\"access_token\":\"ya29.test\",\"expires_in\":120}", 1000);
    defer token.deinit(gpa);
    try std.testing.expectEqualStrings("ya29.test", token.token);
    try std.testing.expectEqual(@as(i64, 1120), token.expiration_unix);
}

test "Vertex auth markers are never literal bearer tokens" {
    try std.testing.expect(isAuthMarker("<authenticated>"));
    try std.testing.expect(isAuthMarker("gcp-vertex-credentials"));
    try std.testing.expect(!isAuthMarker("AIza-real"));
}

test "service account ADC parses owned identity and quota metadata" {
    const gpa = std.testing.allocator;
    var c = try parse(gpa, "{\"type\":\"service_account\",\"client_email\":\"svc@example.iam.gserviceaccount.com\",\"private_key\":\"-----BEGIN PRIVATE KEY-----\\nAA==\\n-----END PRIVATE KEY-----\\n\",\"project_id\":\"proj\",\"quota_project_id\":\"billing\"}");
    defer c.deinit(gpa);
    try std.testing.expectEqual(Kind.service_account, c.kind);
    try std.testing.expectEqualStrings("svc@example.iam.gserviceaccount.com", c.client_email.?);
    try std.testing.expectEqualStrings("proj", c.project_id.?);
    try std.testing.expectEqualStrings("billing", c.quota_project_id.?);
}

test "service account JWT is RS256 and verifies against embedded RSA key" {
    const gpa = std.testing.allocator;
    const private_key =
        \\-----BEGIN PRIVATE KEY-----
        \\MIICdgIBADANBgkqhkiG9w0BAQEFAASCAmAwggJcAgEAAoGBAKcY3nivG1hfzoMY
        \\vt0H5DRrXUkshZdkR2CB/h8IZqmNLInEyewrVE1ZwWEBl3M7mwY3LZwzM4Zjm34J
        \\vHYv+XWYeldoXlCfxeOVzTUDyqMKLpGGCeJfSd40s7NdNJtDINIOZq9YkjylQffN
        \\v3ktDk7OwRqkAd3H1N0Ste0cdJ8fAgMBAAECgYBGcSl4Xvl8LAd3JLtxmp4NqyVM
        \\b8RxqgidGq/yjSwaVjVsbtVhBnMnmKr5Jh6eqYYU/LXxn3QdN2iZnakheeADkLsW
        \\uP/zNLOWiTLy/ASZsCEereRnQyIxTLW6nv4zZuE2Vhefg0ZRvszdOsGaUigi/rw3
        \\ZFnwAiH1IGtn+3HYIQJBANE+C16Qt39YQ0baXeyjUtQ+XDo21adB+pQF3MhI0uaI
        \\j/9fonYSSSwlvHsvfutW2YRZvEZZX9j3Vw7EJ4MYzWsCQQDMb9ufcTIxv4tcKqga
        \\YcjFy026/MXbac7O1SHQjJScTURAfVfgCV/WYDTgfZ74fiWTpjWNpL7B0IVdAQBb
        \\HI4dAkEAg0DeNOWmlXUyToGwJT6WOJkdlU7MWuziWHQM+H3l/cJwQYsmB9aUm+LY
        \\BpXWkZ2bOJBpr99kZl9Q9uxItM2cHQJAUQbYniYoRc1sN7h0bhhpkfOVOFJtPRx/
        \\qjyRLW46jISXU5QaWyJ8CKSS8JL5ifW9gPq0aRJtxLWX1hfKg1IbBQJAIRZi7E6V
        \\m++G/ZX82XzsDuyOiy99kKRYOmZ9JFK7rbI5MaZ1Mm9YRm6/S9x+hFKeR6xjfcUf
        \\wo4+CXRE6i01GA==
        \\-----END PRIVATE KEY-----
    ;
    var c: Credential = .{
        .kind = .service_account,
        .client_email = try gpa.dupe(u8, "svc@example.iam.gserviceaccount.com"),
        .private_key = try gpa.dupe(u8, private_key),
        .token_uri = try gpa.dupe(u8, "https://oauth2.googleapis.com/token"),
    };
    defer c.deinit(gpa);
    const assertion = try buildServiceAccountAssertion(gpa, &c, 1_700_000_000);
    defer gpa.free(assertion);
    var parts = std.mem.splitScalar(u8, assertion, '.');
    const h = parts.next().?;
    const claims = parts.next().?;
    const sig64 = parts.next().?;
    try std.testing.expect(parts.next() == null);
    try std.testing.expect(h.len > 0 and claims.len > 0);
    const sig_len = try std.base64.url_safe_no_pad.Decoder.calcSizeForSlice(sig64);
    try std.testing.expectEqual(@as(usize, 128), sig_len);
    var sig: [128]u8 = undefined;
    try std.base64.url_safe_no_pad.Decoder.decode(&sig, sig64);
    const parsed_key = try parseRsaPrivateKeyPem(gpa, private_key);
    defer gpa.free(parsed_key.der);
    const public_key = try std.crypto.Certificate.rsa.PublicKey.fromBytes(parsed_key.parts.public_exponent, parsed_key.parts.modulus);
    const input = try std.fmt.allocPrint(gpa, "{s}.{s}", .{ h, claims });
    defer gpa.free(input);
    try std.crypto.Certificate.rsa.PKCS1v1_5Signature.verify(128, sig, input, public_key, std.crypto.hash.sha2.Sha256);
}
