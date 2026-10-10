//! Native URL records, host parsing and serialization; no host-language source.
const std = @import("std");
const unicode = @cImport({
    @cInclude("libunicode.h");
    @cInclude("stdlib.h");
});
pub const Part = enum { path, query, special_query, fragment, userinfo, opaque_path, opaque_host };
pub const Record = struct {
    scheme: []u8,
    username: []u8,
    password: []u8,
    host: ?[]u8 = null,
    port: ?u16 = null,
    path: []u8,
    query: ?[]u8 = null,
    fragment: ?[]u8 = null,
    opaque_path: bool = false,
    pub fn deinit(self: *Record, gpa: std.mem.Allocator) void {
        gpa.free(self.scheme);
        gpa.free(self.username);
        gpa.free(self.password);
        gpa.free(self.path);
        if (self.host) |value| gpa.free(value);
        if (self.query) |value| gpa.free(value);
        if (self.fragment) |value| gpa.free(value);
        self.* = undefined;
    }
    pub fn clone(self: Record, gpa: std.mem.Allocator) !Record {
        var result = try empty(gpa, self.scheme);
        errdefer result.deinit(gpa);
        replace(gpa, &result.username, try gpa.dupe(u8, self.username));
        replace(gpa, &result.password, try gpa.dupe(u8, self.password));
        replace(gpa, &result.path, try gpa.dupe(u8, self.path));
        result.host = if (self.host) |value| try gpa.dupe(u8, value) else null;
        result.query = if (self.query) |value| try gpa.dupe(u8, value) else null;
        result.fragment = if (self.fragment) |value| try gpa.dupe(u8, value) else null;
        result.port = self.port;
        result.opaque_path = self.opaque_path;
        return result;
    }
};
pub fn replace(gpa: std.mem.Allocator, target: *[]u8, value: []u8) void {
    gpa.free(target.*);
    target.* = value;
}
fn empty(gpa: std.mem.Allocator, scheme: []const u8) !Record {
    const name = try std.ascii.allocLowerString(gpa, scheme);
    errdefer gpa.free(name);
    const username = try gpa.dupe(u8, "");
    errdefer gpa.free(username);
    const password = try gpa.dupe(u8, "");
    errdefer gpa.free(password);
    return .{ .scheme = name, .username = username, .password = password, .path = try gpa.dupe(u8, "") };
}
pub fn special(scheme: []const u8) bool {
    return std.mem.eql(u8, scheme, "file") or defaultPort(scheme) != null;
}
pub fn defaultPort(scheme: []const u8) ?u16 {
    if (std.mem.eql(u8, scheme, "ftp")) return 21;
    if (std.mem.eql(u8, scheme, "http") or std.mem.eql(u8, scheme, "ws")) return 80;
    if (std.mem.eql(u8, scheme, "https") or std.mem.eql(u8, scheme, "wss")) return 443;
    return null;
}
pub fn encode(gpa: std.mem.Allocator, input: []const u8, part: Part) ![]u8 {
    var output: std.ArrayList(u8) = .empty;
    defer output.deinit(gpa);
    const hex = "0123456789ABCDEF";
    for (input) |byte| {
        const excluded = switch (part) {
            .opaque_path, .opaque_host => byte <= 31 or byte > 126,
            .fragment => byte <= 32 or byte > 126 or byte == 0x60 or std.mem.indexOfScalar(u8, "\"<>", byte) != null,
            .query => byte <= 32 or byte > 126 or std.mem.indexOfScalar(u8, "\"<>#", byte) != null,
            .special_query => byte <= 32 or byte > 126 or std.mem.indexOfScalar(u8, "\"<>#'", byte) != null,
            .path => byte <= 32 or byte > 126 or byte == 0x60 or std.mem.indexOfScalar(u8, "\"<>#?{}", byte) != null,
            .userinfo => byte <= 32 or byte > 126 or byte == 0x60 or std.mem.indexOfScalar(u8, "\"<>#?{}/:;=@[\\]^|", byte) != null,
        };
        if (excluded) try output.appendSlice(gpa, &.{ '%', hex[byte >> 4], hex[byte & 15] }) else try output.append(gpa, byte);
    }
    return output.toOwnedSlice(gpa);
}
fn percentDecode(gpa: std.mem.Allocator, input: []const u8) ![]u8 {
    var output: std.ArrayList(u8) = .empty;
    defer output.deinit(gpa);
    var index: usize = 0;
    while (index < input.len) : (index += 1) {
        if (input[index] == '%' and index + 2 < input.len) {
            const high = std.fmt.charToDigit(input[index + 1], 16) catch null;
            const low = std.fmt.charToDigit(input[index + 2], 16) catch null;
            if (high != null and low != null) {
                try output.append(gpa, (high.? << 4) | low.?);
                index += 2;
                continue;
            }
        }
        try output.append(gpa, input[index]);
    }
    return output.toOwnedSlice(gpa);
}
fn ipv4Number(text: []const u8) !u64 {
    var value = text;
    var radix: u8 = 10;
    if (std.ascii.startsWithIgnoreCase(value, "0x")) {
        radix = 16;
        value = value[2..];
    } else if (value.len >= 2 and value[0] == '0') {
        radix = 8;
        value = value[1..];
    }
    if (value.len == 0) return 0;
    for (value) |byte| {
        _ = std.fmt.charToDigit(byte, radix) catch return error.InvalidURLHost;
    }
    return std.fmt.parseInt(u64, value, radix) catch error.InvalidURLHost;
}
fn numericHost(input: []const u8) bool {
    const value = if (std.mem.endsWith(u8, input, ".")) input[0 .. input.len - 1] else input;
    const last = if (std.mem.lastIndexOfScalar(u8, value, '.')) |index| value[index + 1 ..] else value;
    if (last.len == 0) return false;
    _ = ipv4Number(last) catch return allDigits(last);
    return true;
}
fn allDigits(value: []const u8) bool {
    if (value.len == 0) return false;
    for (value) |byte| if (!std.ascii.isDigit(byte)) return false;
    return true;
}
fn ipv4(gpa: std.mem.Allocator, input: []const u8) ![]u8 {
    const value = if (std.mem.endsWith(u8, input, ".")) input[0 .. input.len - 1] else input;
    var iterator = std.mem.splitScalar(u8, value, '.');
    var parts: [4]u64 = undefined;
    var count: usize = 0;
    while (iterator.next()) |part| {
        if (part.len == 0 or count == 4) return error.InvalidURLHost;
        parts[count] = try ipv4Number(part);
        count += 1;
    }
    if (count == 0) return error.InvalidURLHost;
    for (parts[0 .. count - 1]) |part| if (part > 255) return error.InvalidURLHost;
    const limit: u64 = @as(u64, 1) << @as(u6, @intCast(8 * (5 - count)));
    if (parts[count - 1] >= limit) return error.InvalidURLHost;
    var address = parts[count - 1];
    for (parts[0 .. count - 1], 0..) |part, index| address += part << @as(u6, @intCast(8 * (3 - index)));
    return std.fmt.allocPrint(gpa, "{d}.{d}.{d}.{d}", .{ (address >> 24) & 255, (address >> 16) & 255, (address >> 8) & 255, address & 255 });
}
fn ipv6(gpa: std.mem.Allocator, input: []const u8) ![]u8 {
    if (std.mem.indexOfScalar(u8, input, '%') != null) return error.InvalidURLHost;
    // The standard library parser requires compression for embedded IPv4.
    // Validate WHATWG's four decimal bytes and turn them into two hex pieces.
    var rewritten: ?[]u8 = null;
    defer if (rewritten) |value| gpa.free(value);
    if (std.mem.indexOfScalar(u8, input, '.') != null) {
        const colon = std.mem.lastIndexOfScalar(u8, input, ':') orelse return error.InvalidURLHost;
        var bytes: [4]u8 = undefined;
        var count: usize = 0;
        var parts = std.mem.splitScalar(u8, input[colon + 1 ..], '.');
        while (parts.next()) |part| {
            if (count == 4 or !allDigits(part) or (part.len > 1 and part[0] == '0')) return error.InvalidURLHost;
            bytes[count] = std.fmt.parseInt(u8, part, 10) catch return error.InvalidURLHost;
            count += 1;
        }
        if (count != 4) return error.InvalidURLHost;
        rewritten = try std.fmt.allocPrint(gpa, "{s}{x}:{x}", .{ input[0 .. colon + 1], (@as(u16, bytes[0]) << 8) | bytes[1], (@as(u16, bytes[2]) << 8) | bytes[3] });
    }
    const text = rewritten orelse input;
    if (text.len < 2) return error.InvalidURLHost;
    var words: [8]u16 = @splat(0);
    var count: usize = 0;
    var compression: ?usize = null;
    var cursor: usize = 0;
    if (std.mem.startsWith(u8, text, "::")) {
        compression = 0;
        cursor = 2;
    } else if (text[0] == ':') return error.InvalidURLHost;
    while (cursor < text.len) {
        if (count == 8) return error.InvalidURLHost;
        var digits: usize = 0;
        var word: u16 = 0;
        while (cursor < text.len and text[cursor] != ':') : (cursor += 1) {
            if (digits == 4) return error.InvalidURLHost;
            const number = std.fmt.charToDigit(text[cursor], 16) catch return error.InvalidURLHost;
            word = (word << 4) | number;
            digits += 1;
        }
        if (digits == 0) return error.InvalidURLHost;
        words[count] = word;
        count += 1;
        if (cursor == text.len) break;
        cursor += 1;
        if (cursor == text.len) return error.InvalidURLHost;
        if (text[cursor] == ':') {
            if (compression != null) return error.InvalidURLHost;
            compression = count;
            cursor += 1;
        }
    }
    if (compression) |start| {
        if (count == 8) return error.InvalidURLHost;
        const tail = count - start;
        @memmove(words[8 - tail ..], words[start..count]);
        @memset(words[start .. 8 - tail], 0);
    } else if (count != 8) return error.InvalidURLHost;
    var longest_start: usize = 8;
    var longest_len: usize = 1;
    var index: usize = 0;
    while (index < 8) {
        if (words[index] != 0) {
            index += 1;
            continue;
        }
        const start = index;
        while (index < 8 and words[index] == 0) : (index += 1) {}
        if (index - start > longest_len) {
            longest_start = start;
            longest_len = index - start;
        }
    }
    var writer: std.Io.Writer.Allocating = .init(gpa);
    defer writer.deinit();
    writer.writer.writeByte('[') catch return error.OutOfMemory;
    index = 0;
    while (index < 8) {
        if (index == longest_start) {
            writer.writer.writeAll("::") catch return error.OutOfMemory;
            index += longest_len;
            continue;
        }
        if (index != 0 and index != longest_start + longest_len) writer.writer.writeByte(':') catch return error.OutOfMemory;
        writer.writer.print("{x}", .{words[index]}) catch return error.OutOfMemory;
        index += 1;
    }
    writer.writer.writeByte(']') catch return error.OutOfMemory;
    return writer.toOwnedSlice();
}
fn adapt(initial: u64, points: u64, first: bool) u64 {
    var delta = if (first) initial / 700 else initial / 2;
    delta += delta / points;
    var k: u64 = 0;
    while (delta > 455) {
        delta /= 35;
        k += 36;
    }
    return k + (36 * delta) / (delta + 38);
}
fn digit(value: u64) u8 {
    return if (value < 26) @as(u8, @intCast(value)) + 'a' else @as(u8, @intCast(value - 26)) + '0';
}
fn punycode(gpa: std.mem.Allocator, input: []const u32) ![]u8 {
    var out: std.ArrayList(u8) = .empty;
    defer out.deinit(gpa);
    try out.appendSlice(gpa, "xn--");
    var basic: u64 = 0;
    for (input) |point| if (point < 128) {
        try out.append(gpa, @intCast(point));
        basic += 1;
    };
    var handled = basic;
    if (basic != 0) try out.append(gpa, '-');
    var n: u64 = 128;
    var delta: u64 = 0;
    var bias: u64 = 72;
    while (handled < input.len) {
        var minimum: u64 = 0x110000;
        for (input) |point| if (point >= n and point < minimum) {
            minimum = point;
        };
        delta = std.math.add(u64, delta, std.math.mul(u64, minimum - n, handled + 1) catch return error.InvalidURLHost) catch return error.InvalidURLHost;
        n = minimum;
        for (input) |point| {
            if (point < n) delta = std.math.add(u64, delta, 1) catch return error.InvalidURLHost;
            if (point != n) continue;
            var q = delta;
            var k: u64 = 36;
            while (true) : (k += 36) {
                const t: u64 = if (k <= bias) 1 else if (k >= bias + 26) 26 else k - bias;
                if (q < t) break;
                try out.append(gpa, digit(t + (q - t) % (36 - t)));
                q = (q - t) / (36 - t);
            }
            try out.append(gpa, digit(q));
            bias = adapt(delta, handled + 1, handled == basic);
            delta = 0;
            handled += 1;
        }
        delta += 1;
        n += 1;
        if (out.items.len > 4096) return error.InvalidURLHost;
    }
    return out.toOwnedSlice(gpa);
}
fn decodePunycode(gpa: std.mem.Allocator, input: []const u8) ![]u32 {
    var output: std.ArrayList(u32) = .empty;
    defer output.deinit(gpa);
    var position: usize = 0;
    if (std.mem.lastIndexOfScalar(u8, input, '-')) |index| {
        for (input[0..index]) |byte| {
            if (byte >= 128) return error.InvalidURLHost;
            try output.append(gpa, byte);
        }
        position = index + 1;
    }
    var n: u64 = 128;
    var i: u64 = 0;
    var bias: u64 = 72;
    while (position < input.len) {
        const old = i;
        var weight: u64 = 1;
        var k: u64 = 36;
        while (true) : (k += 36) {
            if (position >= input.len) return error.InvalidURLHost;
            const byte = std.ascii.toLower(input[position]);
            position += 1;
            const d: u64 = if (byte >= 'a' and byte <= 'z') byte - 'a' else if (byte >= '0' and byte <= '9') byte - '0' + 26 else return error.InvalidURLHost;
            i = std.math.add(u64, i, std.math.mul(u64, d, weight) catch return error.InvalidURLHost) catch return error.InvalidURLHost;
            const t: u64 = if (k <= bias) 1 else if (k >= bias + 26) 26 else k - bias;
            if (d < t) break;
            weight = std.math.mul(u64, weight, 36 - t) catch return error.InvalidURLHost;
        }
        const count = output.items.len + 1;
        bias = adapt(i - old, count, old == 0);
        n = std.math.add(u64, n, i / count) catch return error.InvalidURLHost;
        if (n > 0x10ffff or (n >= 0xd800 and n <= 0xdfff)) return error.InvalidURLHost;
        i %= count;
        try output.insert(gpa, @intCast(i), @intCast(n));
        i += 1;
    }
    if (output.items.len == 0) return error.InvalidURLHost;
    return output.toOwnedSlice(gpa);
}
fn domain(gpa: std.mem.Allocator, input: []const u8) ![]u8 {
    const decoded = try percentDecode(gpa, input);
    defer gpa.free(decoded);
    if (decoded.len == 0) return gpa.dupe(u8, "");
    const view = std.unicode.Utf8View.init(decoded) catch return error.InvalidURLHost;
    var source: std.ArrayList(u32) = .empty;
    defer source.deinit(gpa);
    var points = view.iterator();
    while (points.nextCodepoint()) |point| {
        // Contextual joiner/bidi validation requires a further IDNA layer.
        // Reject these domains rather than serialize a plausible wrong host.
        if (point == 0x200c or point == 0x200d or (point >= 0x590 and point <= 0x8ff)) return error.UnsupportedIDNContext;
        try validateDomainPoint(point);
        if (ignoredDomainPoint(point)) continue;
        try source.append(gpa, if (point == 0x3002 or point == 0xff0e or point == 0xff61) '.' else point);
    }
    if (source.items.len == 0) return error.InvalidURLHost;
    var normalized: [*c]u32 = null;
    const length = unicode.unicode_normalize(&normalized, source.items.ptr, @intCast(source.items.len), unicode.UNICODE_NFKC, null, null);
    if (length < 0) return error.OutOfMemory;
    defer unicode.free(normalized);
    var mapped: std.ArrayList(u32) = .empty;
    defer mapped.deinit(gpa);
    for (normalized[0..@intCast(length)]) |point| {
        var lower: [3]u32 = undefined;
        const count = unicode.lre_case_conv(&lower, point, 1);
        for (lower[0..@intCast(count)]) |value| {
            if (value <= 32 or value == 127 or (value < 128 and std.mem.indexOfScalar(u8, "#%/:<>?@[\\]^|", @intCast(value)) != null)) return error.InvalidURLHost;
            try mapped.append(gpa, value);
        }
    }
    var output: std.ArrayList(u8) = .empty;
    defer output.deinit(gpa);
    var start: usize = 0;
    for (0..mapped.items.len + 1) |index| {
        if (index != mapped.items.len and mapped.items[index] != '.') continue;
        const label = mapped.items[start..index];
        var ascii = true;
        for (label) |value| if (value >= 128) {
            ascii = false;
        };
        if (ascii) {
            for (label) |value| try output.append(gpa, @intCast(value));
            if (label.len >= 4 and label[0] == 'x' and label[1] == 'n' and label[2] == '-' and label[3] == '-') {
                const raw = try gpa.alloc(u8, label.len - 4);
                defer gpa.free(raw);
                for (label[4..], raw) |value, *byte| byte.* = @intCast(value);
                const decoded_label = try decodePunycode(gpa, raw);
                defer gpa.free(decoded_label);
                var non_ascii = false;
                for (decoded_label) |point| {
                    try validateDomainPoint(point);
                    if (point == 0x200c or point == 0x200d or (point >= 0x590 and point <= 0x8ff)) return error.UnsupportedIDNContext;
                    if (ignoredDomainPoint(point)) return error.InvalidURLHost;
                    if (point >= 128) non_ascii = true;
                }
                if (!non_ascii or (decoded_label[0] >= 0x300 and decoded_label[0] <= 0x36f)) return error.InvalidURLHost;
                const roundtrip = try punycode(gpa, decoded_label);
                defer gpa.free(roundtrip);
                if (!std.mem.eql(u8, roundtrip, output.items[output.items.len - label.len ..])) return error.InvalidURLHost;
            }
        } else {
            const encoded = try punycode(gpa, label);
            defer gpa.free(encoded);
            try output.appendSlice(gpa, encoded);
        }
        if (index != mapped.items.len) try output.append(gpa, '.');
        start = index + 1;
    }
    const result = try output.toOwnedSlice(gpa);
    if (numericHost(result)) {
        defer gpa.free(result);
        return ipv4(gpa, result);
    }
    return result;
}
fn ignoredDomainPoint(point: u32) bool {
    return point == 0xad or point == 0x34f or point == 0x180e or point == 0x200b or point == 0x2060 or point == 0xfeff or (point >= 0xfe00 and point <= 0xfe0f);
}
fn validateDomainPoint(point: u32) !void {
    if ((point >= 0x80 and point <= 0x9f) or point == 0xfffd or point == 0x2028 or point == 0x2029 or (point >= 0xe000 and point <= 0xf8ff) or (point >= 0xfdd0 and point <= 0xfdef) or point & 0xffff >= 0xfffe) return error.InvalidURLHost;
}
pub fn parseHost(gpa: std.mem.Allocator, input: []const u8, is_special: bool) ![]u8 {
    if (std.mem.startsWith(u8, input, "[")) {
        if (!std.mem.endsWith(u8, input, "]")) return error.InvalidURLHost;
        return ipv6(gpa, input[1 .. input.len - 1]);
    }
    if (is_special) return domain(gpa, input);
    for (input) |byte| if (byte <= 32 or byte == 127 or std.mem.indexOfScalar(u8, "#/:<>?@[\\]^|", byte) != null) return error.InvalidURLHost;
    return encode(gpa, input, .opaque_host);
}
/// Unicode spelling of an already valid domain, used for Windows UNC paths.
pub fn domainUnicode(gpa: std.mem.Allocator, input: []const u8) ![]u8 {
    const ascii = try parseHost(gpa, input, true);
    defer gpa.free(ascii);
    var output: std.ArrayList(u8) = .empty;
    defer output.deinit(gpa);
    var labels = std.mem.splitScalar(u8, ascii, '.');
    var first = true;
    while (labels.next()) |label| {
        if (!first) try output.append(gpa, '.');
        first = false;
        if (std.mem.startsWith(u8, label, "xn--")) {
            const points = try decodePunycode(gpa, label[4..]);
            defer gpa.free(points);
            for (points) |point| {
                var bytes: [4]u8 = undefined;
                const length = std.unicode.utf8Encode(@intCast(point), &bytes) catch return error.InvalidURLHost;
                try output.appendSlice(gpa, bytes[0..length]);
            }
        } else try output.appendSlice(gpa, label);
    }
    return output.toOwnedSlice(gpa);
}
pub fn drive(value: []const u8) bool {
    return value.len == 2 and std.ascii.isAlphabetic(value[0]) and (value[1] == ':' or value[1] == '|');
}
fn dot(value: []const u8) bool {
    return std.mem.eql(u8, value, ".") or std.ascii.eqlIgnoreCase(value, "%2e");
}
fn dotdot(value: []const u8) bool {
    return std.mem.eql(u8, value, "..") or std.ascii.eqlIgnoreCase(value, ".%2e") or std.ascii.eqlIgnoreCase(value, "%2e.") or std.ascii.eqlIgnoreCase(value, "%2e%2e");
}
pub fn normalizePath(gpa: std.mem.Allocator, input: []const u8, file: bool) ![]u8 {
    var segments: std.ArrayList([]const u8) = .empty;
    defer segments.deinit(gpa);
    var parts = std.mem.splitScalar(u8, if (std.mem.startsWith(u8, input, "/")) input[1..] else input, '/');
    while (parts.next()) |part| {
        const last = parts.index == null;
        if (dot(part)) {
            if (last) try segments.append(gpa, "");
            continue;
        }
        if (dotdot(part)) {
            if (segments.items.len > 0 and !(file and segments.items.len == 1 and drive(segments.items[0]))) _ = segments.pop();
            if (last) try segments.append(gpa, "");
            continue;
        }
        try segments.append(gpa, part);
    }
    var out: std.ArrayList(u8) = .empty;
    defer out.deinit(gpa);
    for (segments.items, 0..) |part, index| {
        try out.append(gpa, '/');
        if (file and index == 0 and drive(part)) try out.appendSlice(gpa, &.{ part[0], ':' }) else {
            const encoded = try encode(gpa, part, .path);
            defer gpa.free(encoded);
            try out.appendSlice(gpa, encoded);
        }
    }
    if (segments.items.len == 0) try out.append(gpa, '/');
    return out.toOwnedSlice(gpa);
}
pub fn authority(gpa: std.mem.Allocator, record: *Record, input: []const u8) !void {
    var address = input;
    const file = std.mem.eql(u8, record.scheme, "file");
    if (std.mem.lastIndexOfScalar(u8, input, '@')) |index| {
        if (file) return error.InvalidURL;
        const userinfo = input[0..index];
        const separator = std.mem.indexOfScalar(u8, userinfo, ':') orelse userinfo.len;
        const username = try encode(gpa, userinfo[0..separator], .userinfo);
        var credentials_transferred = false;
        errdefer if (!credentials_transferred) gpa.free(username);
        const password = try encode(gpa, if (separator < userinfo.len) userinfo[separator + 1 ..] else "", .userinfo);
        replace(gpa, &record.username, username);
        replace(gpa, &record.password, password);
        credentials_transferred = true;
        address = input[index + 1 ..];
    }
    var host = address;
    var port: ?[]const u8 = null;
    if (std.mem.startsWith(u8, address, "[")) {
        const closing = std.mem.indexOfScalar(u8, address, ']') orelse return error.InvalidURLHost;
        host = address[0 .. closing + 1];
        if (closing + 1 < address.len) {
            if (address[closing + 1] != ':') return error.InvalidURLHost;
            port = address[closing + 2 ..];
        }
    } else if (std.mem.lastIndexOfScalar(u8, address, ':')) |index| {
        host = address[0..index];
        port = address[index + 1 ..];
    }
    if (file and port != null) return error.InvalidURL;
    if (host.len == 0 and special(record.scheme) and !file) return error.InvalidURLHost;
    const parsed = try parseHost(gpa, host, special(record.scheme));
    if (record.host) |old| gpa.free(old);
    record.host = parsed;
    if (file and std.ascii.eqlIgnoreCase(parsed, "localhost")) {
        const local = try gpa.dupe(u8, "");
        gpa.free(parsed);
        record.host = local;
    }
    if (port) |text| if (text.len > 0) {
        if (!allDigits(text)) return error.InvalidURLPort;
        const number = std.fmt.parseInt(u16, text, 10) catch return error.InvalidURLPort;
        record.port = if (defaultPort(record.scheme) == number) null else number;
    };
}
fn splitSuffix(gpa: std.mem.Allocator, record: *Record, input: []const u8) ![]const u8 {
    var path = input;
    if (std.mem.indexOfScalar(u8, path, '#')) |index| {
        record.fragment = try encode(gpa, path[index + 1 ..], .fragment);
        path = path[0..index];
    }
    if (std.mem.indexOfScalar(u8, path, '?')) |index| {
        record.query = try encode(gpa, path[index + 1 ..], if (special(record.scheme)) .special_query else .query);
        path = path[0..index];
    }
    return path;
}
fn cleaned(gpa: std.mem.Allocator, input: []const u8) ![]u8 {
    var start: usize = 0;
    var end = input.len;
    while (start < end and input[start] <= 32) : (start += 1) {}
    while (end > start and input[end - 1] <= 32) : (end -= 1) {}
    var output: std.ArrayList(u8) = .empty;
    defer output.deinit(gpa);
    for (input[start..end]) |byte| if (byte != '\t' and byte != '\r' and byte != '\n') {
        try output.append(gpa, byte);
    };
    return output.toOwnedSlice(gpa);
}
fn schemeEnd(input: []const u8) ?usize {
    if (input.len == 0 or !std.ascii.isAlphabetic(input[0])) return null;
    for (input[1..], 1..) |byte, index| {
        if (byte == ':') return index;
        if (!std.ascii.isAlphanumeric(byte) and byte != '+' and byte != '-' and byte != '.') return null;
    }
    return null;
}
pub fn parse(gpa: std.mem.Allocator, input: []const u8, base: ?*const Record) !Record {
    const text = try cleaned(gpa, input);
    defer gpa.free(text);
    if (schemeEnd(text)) |colon| {
        const scheme = text[0..colon];
        if (base) |parent| {
            if (special(parent.scheme) and std.ascii.eqlIgnoreCase(scheme, parent.scheme) and !std.mem.startsWith(u8, text[colon + 1 ..], "//") and !std.ascii.eqlIgnoreCase(scheme, "file")) return relative(gpa, text[colon + 1 ..], parent);
            if (std.ascii.eqlIgnoreCase(scheme, "file") and std.mem.eql(u8, parent.scheme, "file") and !std.mem.startsWith(u8, text[colon + 1 ..], "//")) return relative(gpa, text[colon + 1 ..], parent);
        }
        var record = try empty(gpa, scheme);
        errdefer record.deinit(gpa);
        const rest = text[colon + 1 ..];
        const path_end = std.mem.indexOfAny(u8, rest, "?#") orelse rest.len;
        if (special(record.scheme)) for (rest[0..path_end]) |*byte| if (byte.* == '\\') {
            byte.* = '/';
        };
        if (std.mem.eql(u8, record.scheme, "file")) {
            var body = try splitSuffix(gpa, &record, rest);
            record.host = try gpa.dupe(u8, "");
            if (std.mem.startsWith(u8, body, "//")) {
                body = body[2..];
                const end = std.mem.indexOfScalar(u8, body, '/') orelse body.len;
                if (drive(body[0..end])) {
                    const path = try std.fmt.allocPrint(gpa, "/{s}", .{body});
                    defer gpa.free(path);
                    replace(gpa, &record.path, try normalizePath(gpa, path, true));
                    return record;
                }
                try authority(gpa, &record, body[0..end]);
                body = body[end..];
            }
            replace(gpa, &record.path, try normalizePath(gpa, body, true));
            return record;
        }
        if (special(record.scheme) or std.mem.startsWith(u8, rest, "//")) {
            var body = if (special(record.scheme)) std.mem.trimStart(u8, rest, "/") else rest[2..];
            const end = std.mem.indexOfAny(u8, body, "/?#") orelse body.len;
            try authority(gpa, &record, body[0..end]);
            body = try splitSuffix(gpa, &record, body[end..]);
            replace(gpa, &record.path, if (!special(record.scheme) and body.len == 0) try gpa.dupe(u8, "") else try normalizePath(gpa, body, false));
        } else {
            const body = try splitSuffix(gpa, &record, rest);
            record.opaque_path = !std.mem.startsWith(u8, body, "/");
            replace(gpa, &record.path, if (record.opaque_path) try encode(gpa, body, .opaque_path) else try normalizePath(gpa, body, false));
            if (record.opaque_path and (record.query != null or record.fragment != null)) {
                const end = std.mem.trimEnd(u8, record.path, " ").len;
                var encoded: std.ArrayList(u8) = .empty;
                defer encoded.deinit(gpa);
                try encoded.appendSlice(gpa, record.path[0..end]);
                for (end..record.path.len) |_| try encoded.appendSlice(gpa, "%20");
                replace(gpa, &record.path, try encoded.toOwnedSlice(gpa));
            }
        }
        return record;
    }
    return relative(gpa, text, base orelse return error.InvalidURL);
}
fn relative(gpa: std.mem.Allocator, input: []const u8, base: *const Record) !Record {
    if (base.opaque_path and !std.mem.startsWith(u8, input, "#")) return error.InvalidURL;
    var record = try base.clone(gpa);
    errdefer record.deinit(gpa);
    if (record.fragment) |old| gpa.free(old);
    record.fragment = null;
    if (std.mem.startsWith(u8, input, "#")) {
        record.fragment = try encode(gpa, input[1..], .fragment);
        return record;
    }
    if (std.mem.startsWith(u8, input, "?")) {
        if (record.query) |old| gpa.free(old);
        record.query = null;
        _ = try splitSuffix(gpa, &record, input);
        return record;
    }
    if (input.len == 0) return record;
    if (record.query) |old| gpa.free(old);
    record.query = null;
    const working = try gpa.dupe(u8, input);
    defer gpa.free(working);
    const end = std.mem.indexOfAny(u8, working, "?#") orelse working.len;
    if (special(record.scheme)) for (working[0..end]) |*byte| if (byte.* == '\\') {
        byte.* = '/';
    };
    var body = try splitSuffix(gpa, &record, working);
    if (std.mem.startsWith(u8, body, "//")) {
        body = if (special(record.scheme) and !std.mem.eql(u8, record.scheme, "file")) std.mem.trimStart(u8, body, "/") else body[2..];
        const end_authority = std.mem.indexOfScalar(u8, body, '/') orelse body.len;
        replace(gpa, &record.username, try gpa.dupe(u8, ""));
        replace(gpa, &record.password, try gpa.dupe(u8, ""));
        record.port = null;
        if (std.mem.eql(u8, record.scheme, "file") and drive(body[0..end_authority])) {
            if (record.host) |value| gpa.free(value);
            record.host = null;
            record.host = try gpa.dupe(u8, "");
            replace(gpa, &record.path, try normalizePath(gpa, body, true));
            return record;
        }
        try authority(gpa, &record, body[0..end_authority]);
        replace(gpa, &record.path, if (!special(record.scheme) and end_authority == body.len) try gpa.dupe(u8, "") else try normalizePath(gpa, body[end_authority..], std.mem.eql(u8, record.scheme, "file")));
        return record;
    }
    const file = std.mem.eql(u8, record.scheme, "file");
    var combined: ?[]u8 = null;
    defer if (combined) |value| gpa.free(value);
    if (!std.mem.startsWith(u8, body, "/")) {
        const first = body[0 .. std.mem.indexOfScalar(u8, body, '/') orelse body.len];
        if (file and drive(first)) combined = try std.fmt.allocPrint(gpa, "/{s}", .{body}) else {
            const slash = std.mem.lastIndexOfScalar(u8, record.path, '/') orelse 0;
            combined = try std.fmt.allocPrint(gpa, "{s}/{s}", .{ record.path[0..slash], body });
        }
    } else if (file and record.path.len >= 3 and drive(record.path[1..3])) {
        const first = body[1 .. std.mem.indexOfScalarPos(u8, body, 1, '/') orelse body.len];
        if (!drive(first)) combined = try std.fmt.allocPrint(gpa, "/{s}{s}", .{ record.path[1..3], body });
    }
    replace(gpa, &record.path, try normalizePath(gpa, combined orelse body, file));
    return record;
}
pub fn serialize(gpa: std.mem.Allocator, record: Record) ![]u8 {
    var out: std.Io.Writer.Allocating = .init(gpa);
    defer out.deinit();
    out.writer.print("{s}:", .{record.scheme}) catch return error.OutOfMemory;
    if (record.host) |host| {
        out.writer.writeAll("//") catch return error.OutOfMemory;
        if (record.username.len != 0 or record.password.len != 0) {
            out.writer.writeAll(record.username) catch return error.OutOfMemory;
            if (record.password.len != 0) out.writer.print(":{s}", .{record.password}) catch return error.OutOfMemory;
            out.writer.writeByte('@') catch return error.OutOfMemory;
        }
        out.writer.writeAll(host) catch return error.OutOfMemory;
        if (record.port) |port| out.writer.print(":{d}", .{port}) catch return error.OutOfMemory;
    } else if (!record.opaque_path and std.mem.startsWith(u8, record.path, "//")) out.writer.writeAll("/.") catch return error.OutOfMemory;
    out.writer.writeAll(record.path) catch return error.OutOfMemory;
    if (record.query) |query| out.writer.print("?{s}", .{query}) catch return error.OutOfMemory;
    if (record.fragment) |fragment| out.writer.print("#{s}", .{fragment}) catch return error.OutOfMemory;
    return out.toOwnedSlice();
}
pub fn origin(gpa: std.mem.Allocator, record: Record) ![]u8 {
    if (std.mem.eql(u8, record.scheme, "blob")) {
        var child = parse(gpa, record.path, null) catch |err| {
            if (err == error.OutOfMemory) return err;
            return gpa.dupe(u8, "null");
        };
        defer child.deinit(gpa);
        if (std.mem.eql(u8, child.scheme, "http") or std.mem.eql(u8, child.scheme, "https")) return origin(gpa, child);
        return gpa.dupe(u8, "null");
    }
    if (!special(record.scheme) or std.mem.eql(u8, record.scheme, "file") or record.host == null) return gpa.dupe(u8, "null");
    return if (record.port) |port| std.fmt.allocPrint(gpa, "{s}://{s}:{d}", .{ record.scheme, record.host.?, port }) else std.fmt.allocPrint(gpa, "{s}://{s}", .{ record.scheme, record.host.? });
}

test "native URL parser special opaque IPv4 IPv6 IDN credentials percent paths and file records" {
    const gpa = std.testing.allocator;
    inline for (.{
        .{ "https://EXAMPLE.com:443/a/../b?x=hello world#f", "https://example.com/b?x=hello%20world#f" },
        .{ "https://user:p:a@EXAMPLE.com:444/a", "https://user:p%3Aa@example.com:444/a" },
        .{ "http://127.1/", "http://127.0.0.1/" },
        .{ "http://0x7f.1/", "http://127.0.0.1/" },
        .{ "http://2130706433/", "http://127.0.0.1/" },
        .{ "http://[2001:0db8:0:0:0:0:0:1]:80/a", "http://[2001:db8::1]/a" },
        .{ "https://bücher.example/a", "https://xn--bcher-kva.example/a" },
        .{ "https://💩.example/", "https://xn--ls8h.example/" },
        .{ "mailto:user@example.com", "mailto:user@example.com" },
        .{ "data:text/plain,hello world#f", "data:text/plain,hello world#f" },
        .{ "file:///C:/a/../b", "file:///C:/b" },
        .{ "file://localhost/C|/a", "file:///C:/a" },
        .{ "https://a.b/%2e%2e/x", "https://a.b/x" },
    }) |pair| {
        var record = try parse(gpa, pair[0], null);
        defer record.deinit(gpa);
        const result = try serialize(gpa, record);
        defer gpa.free(result);
        try std.testing.expectEqualStrings(pair[1], result);
        var again = try parse(gpa, result, null);
        defer again.deinit(gpa);
        const second = try serialize(gpa, again);
        defer gpa.free(second);
        try std.testing.expectEqualStrings(result, second);
    }
}
test "native URL parser resolves relative URLs and preserves query fragment and special scheme semantics" {
    const gpa = std.testing.allocator;
    var base = try parse(gpa, "https://host/a/b/c?q=old#f", null);
    defer base.deinit(gpa);
    inline for (.{ .{ "../d?x=1", "https://host/a/d?x=1" }, .{ "?q=1", "https://host/a/b/c?q=1" }, .{ "#new", "https://host/a/b/c?q=old#new" }, .{ "https:relative", "https://host/a/b/relative" } }) |pair| {
        var record = try parse(gpa, pair[0], &base);
        defer record.deinit(gpa);
        const result = try serialize(gpa, record);
        defer gpa.free(result);
        try std.testing.expectEqualStrings(pair[1], result);
    }
}

test "native URL parser rejects bounded malformed IPv6 and unsupported contextual IDN in Unicode and A labels" {
    const gpa = std.testing.allocator;
    inline for (.{ "http://[:::]/", "http://[1:2:3:4:5:6:7:8::]/", "http://[1:2:3:4:5:6:7:8:9]/", "http://[::ffff:192.168.001.1]/", "http://[::ffff:256.0.0.1]/", "http://[::ffff:192.0.2]/", "https://xn--a/", "https://xn--abc-/" }) |input| try std.testing.expectError(error.InvalidURLHost, parse(gpa, input, null));
    const long = "http://[" ++ "ffff:" ** 100 ++ "1]/";
    try std.testing.expectError(error.InvalidURLHost, parse(gpa, long, null));
    inline for (.{ "https://א.example/", "https://a\u{200d}b.example/", "https://xn--4db.example/" }) |input| try std.testing.expectError(error.UnsupportedIDNContext, parse(gpa, input, null));
}
