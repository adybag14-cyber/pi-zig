//! Native encodings used by Buffer and binary filesystem results.
const std = @import("std");
pub const Encoding = enum { utf8, utf16le, latin1, ascii, hex, base64, base64url };

pub fn parse(name: []const u8) ?Encoding {
    if (std.ascii.eqlIgnoreCase(name, "utf8") or std.ascii.eqlIgnoreCase(name, "utf-8")) return .utf8;
    if (std.ascii.eqlIgnoreCase(name, "utf16le") or std.ascii.eqlIgnoreCase(name, "utf-16le") or std.ascii.eqlIgnoreCase(name, "ucs2") or std.ascii.eqlIgnoreCase(name, "ucs-2")) return .utf16le;
    if (std.ascii.eqlIgnoreCase(name, "latin1") or std.ascii.eqlIgnoreCase(name, "binary")) return .latin1;
    if (std.ascii.eqlIgnoreCase(name, "ascii")) return .ascii;
    if (std.ascii.eqlIgnoreCase(name, "hex")) return .hex;
    if (std.ascii.eqlIgnoreCase(name, "base64")) return .base64;
    if (std.ascii.eqlIgnoreCase(name, "base64url")) return .base64url;
    return null;
}

fn codepoint(output: *std.ArrayList(u8), gpa: std.mem.Allocator, point: u21) !void {
    var buffer: [4]u8 = undefined;
    const length = try std.unicode.wtf8Encode(point, &buffer);
    try output.appendSlice(gpa, buffer[0..length]);
}

fn unit(output: *std.ArrayList(u8), gpa: std.mem.Allocator, value: u16, encoding: Encoding) !void {
    if (encoding == .utf16le) try output.appendSlice(gpa, &.{ @truncate(value), @truncate(value >> 8) }) else try output.append(gpa, @truncate(value));
}

/// JS input strings use WTF-8 so isolated UTF-16 surrogates stay observable.
pub fn encode(gpa: std.mem.Allocator, text: []const u8, encoding: Encoding) ![]u8 {
    var output: std.ArrayList(u8) = .empty;
    defer output.deinit(gpa);
    if (encoding == .hex) {
        var index: usize = 0;
        while (index + 1 < text.len) : (index += 2) {
            const high = std.fmt.charToDigit(text[index], 16) catch break;
            const low = std.fmt.charToDigit(text[index + 1], 16) catch break;
            try output.append(gpa, (high << 4) | low);
        }
    } else if (encoding == .base64 or encoding == .base64url) {
        var pending: u32 = 0;
        var bits: u5 = 0;
        for (text) |byte| {
            if (byte == '=') break;
            const value: u8 = if (byte >= 'A' and byte <= 'Z') byte - 'A' else if (byte >= 'a' and byte <= 'z') byte - 'a' + 26 else if (byte >= '0' and byte <= '9') byte - '0' + 52 else if (byte == '+' or byte == '-') 62 else if (byte == '/' or byte == '_') 63 else continue;
            pending = (pending << 6) | value;
            bits += 6;
            if (bits >= 8) {
                bits -= 8;
                try output.append(gpa, @truncate(pending >> bits));
            }
        }
    } else {
        var iterator = (try std.unicode.Wtf8View.init(text)).iterator();
        while (iterator.nextCodepoint()) |point| {
            if (encoding == .utf8) {
                try codepoint(&output, gpa, if (point >= 0xd800 and point <= 0xdfff) 0xfffd else point);
            } else if (point > 0xffff) {
                const supplementary = point - 0x10000;
                try unit(&output, gpa, @intCast(0xd800 + (supplementary >> 10)), encoding);
                try unit(&output, gpa, @intCast(0xdc00 + (supplementary & 1023)), encoding);
            } else try unit(&output, gpa, @intCast(point), encoding);
        }
    }
    return output.toOwnedSlice(gpa);
}

pub fn decode(gpa: std.mem.Allocator, bytes: []const u8, encoding: Encoding) ![]u8 {
    if (encoding == .hex) {
        const result = try gpa.alloc(u8, try std.math.mul(usize, bytes.len, 2));
        const hex = "0123456789abcdef";
        for (bytes, 0..) |byte, index| {
            result[index * 2] = hex[byte >> 4];
            result[index * 2 + 1] = hex[byte & 15];
        }
        return result;
    }
    if (encoding == .base64 or encoding == .base64url) {
        const encoder = if (encoding == .base64) std.base64.standard.Encoder else std.base64.url_safe_no_pad.Encoder;
        const output = try gpa.alloc(u8, encoder.calcSize(bytes.len));
        _ = encoder.encode(output, bytes);
        return output;
    }
    var output: std.ArrayList(u8) = .empty;
    defer output.deinit(gpa);
    var index: usize = 0;
    if (encoding == .utf16le) {
        while (index + 1 < bytes.len) : (index += 2) {
            const first = std.mem.readInt(u16, bytes[index..][0..2], .little);
            if (first >= 0xd800 and first <= 0xdbff and index + 3 < bytes.len) {
                const second = std.mem.readInt(u16, bytes[index + 2 ..][0..2], .little);
                if (second >= 0xdc00 and second <= 0xdfff) {
                    try codepoint(&output, gpa, 0x10000 + (@as(u21, first - 0xd800) << 10) + second - 0xdc00);
                    index += 2;
                    continue;
                }
            }
            try codepoint(&output, gpa, first);
        }
    } else if (encoding == .latin1 or encoding == .ascii) {
        for (bytes) |byte| try codepoint(&output, gpa, if (encoding == .ascii) byte & 127 else byte);
    } else {
        while (index < bytes.len) {
            const first = bytes[index];
            if (first < 0x80) {
                try output.append(gpa, first);
                index += 1;
                continue;
            }
            const expected: usize = if (first >= 0xc2 and first <= 0xdf) 2 else if (first >= 0xe0 and first <= 0xef) 3 else if (first >= 0xf0 and first <= 0xf4) 4 else {
                try codepoint(&output, gpa, 0xfffd);
                index += 1;
                continue;
            };
            var consumed: usize = 1;
            while (consumed < expected and index + consumed < bytes.len) {
                const next = bytes[index + consumed];
                if (next & 0xc0 != 0x80) break;
                if (consumed == 1 and ((first == 0xe0 and next < 0xa0) or (first == 0xed and next >= 0xa0) or (first == 0xf0 and next < 0x90) or (first == 0xf4 and next >= 0x90))) break;
                consumed += 1;
            }
            if (consumed == expected) {
                const point = try std.unicode.utf8Decode(bytes[index .. index + consumed]);
                try codepoint(&output, gpa, point);
            } else try codepoint(&output, gpa, 0xfffd);
            index += consumed;
        }
    }
    return output.toOwnedSlice(gpa);
}

test "native Buffer encodings preserve surrogate units permissive hex/base64 and invalid UTF8" {
    const gpa = std.testing.allocator;
    const latin = try encode(gpa, "\xf0\x9f\x8c\x8d", .latin1);
    defer gpa.free(latin);
    try std.testing.expectEqualSlices(u8, &.{ 0x3c, 0x0d }, latin);
    const hex = try encode(gpa, "ab12xz34", .hex);
    defer gpa.free(hex);
    try std.testing.expectEqualSlices(u8, &.{ 0xab, 0x12 }, hex);
    const base64 = try encode(gpa, "aG V?sbG8=ignored", .base64);
    defer gpa.free(base64);
    try std.testing.expectEqualStrings("hello", base64);
    const invalid = try decode(gpa, &.{ 0xef, 0xbb, 0x41, 0xed, 0xa0, 0x80 }, .utf8);
    defer gpa.free(invalid);
    try std.testing.expectEqualStrings("\xef\xbf\xbdA\xef\xbf\xbd\xef\xbf\xbd\xef\xbf\xbd", invalid);
    const surrogate = try decode(gpa, &.{ 0x00, 0xd8 }, .utf16le);
    defer gpa.free(surrogate);
    try std.testing.expectEqualStrings("\xed\xa0\x80", surrogate);
}

test "native binary encodings match independently captured Node Buffer results" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();
    const fixture = try std.json.parseFromSliceLeaky(std.json.Value, gpa, @embedFile("fixtures/buffer_encoding.json"), .{});
    for (fixture.object.get("cases").?.array.items) |sample| {
        const object = sample.object;
        const encoding = parse(object.get("encoding").?.string).?;
        if (std.mem.eql(u8, object.get("operation").?.string, "encode")) {
            const input = try fromJsonUnits(gpa, object.get("inputUnits").?.array.items);
            const actual = try encode(gpa, input, encoding);
            const expected = object.get("expected").?.array.items;
            if (actual.len != expected.len) {
                std.debug.print("Encoding oracle length mismatch {s} {any}: actual {any}; expected {s}\n", .{ @tagName(encoding), input, actual, try std.json.Stringify.valueAlloc(gpa, object.get("expected").?, .{}) });
                return error.NativeBufferEncodingMismatch;
            }
            for (actual, expected) |byte, value| try std.testing.expectEqual(@as(u8, @intCast(value.integer)), byte);
        } else {
            const input = object.get("input").?.array.items;
            const bytes = try gpa.alloc(u8, input.len);
            for (bytes, input) |*byte, value| byte.* = @intCast(value.integer);
            const actual = try decode(gpa, bytes, encoding);
            const expected = try fromJsonUnits(gpa, object.get("expectedUnits").?.array.items);
            if (!std.mem.eql(u8, actual, expected)) {
                std.debug.print("Decoding oracle mismatch {s} {any}: actual {any}; expected {any}\n", .{ @tagName(encoding), bytes, actual, expected });
                return error.NativeBufferEncodingMismatch;
            }
        }
    }
}

fn fromJsonUnits(gpa: std.mem.Allocator, units: []const std.json.Value) ![]u8 {
    var output: std.ArrayList(u8) = .empty;
    defer output.deinit(gpa);
    var index: usize = 0;
    while (index < units.len) : (index += 1) {
        const first: u16 = @intCast(units[index].integer);
        if (first >= 0xd800 and first <= 0xdbff and index + 1 < units.len) {
            const second: u16 = @intCast(units[index + 1].integer);
            if (second >= 0xdc00 and second <= 0xdfff) {
                try codepoint(&output, gpa, 0x10000 + (@as(u21, first - 0xd800) << 10) + second - 0xdc00);
                index += 1;
                continue;
            }
        }
        try codepoint(&output, gpa, first);
    }
    return output.toOwnedSlice(gpa);
}
