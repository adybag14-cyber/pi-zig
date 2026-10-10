//! Validate a JSON wire envelope without decoding opaque guest UTF16 strings.
//! ECMA JSON permits isolated \u surrogate escapes. Unescaped bytes must still
//! be valid UTF8, and every nested value is checked before any header is used.
const std = @import("std");
pub const Envelope = struct {
    kind: ?[]const u8 = null,
    ok: ?[]const u8 = null,
    result: ?[]const u8 = null,
    invocation_id: ?[]const u8 = null,
};
const Frame = enum { array_first, array_more, array_after, object_first, object_more, object_after };
const Scanner = struct {
    bytes: []const u8,
    index: usize = 0,
    gpa: std.mem.Allocator,
    stack: std.ArrayList(Frame) = .empty,
    fn whitespace(self: *Scanner) void {
        while (self.index < self.bytes.len) switch (self.bytes[self.index]) {
            ' ', '\t', '\r', '\n' => self.index += 1,
            else => return,
        };
    }
    fn take(self: *Scanner, byte: u8) bool {
        if (self.index == self.bytes.len or self.bytes[self.index] != byte) return false;
        self.index += 1;
        return true;
    }
    fn expect(self: *Scanner, byte: u8) !void {
        if (!self.take(byte)) return error.SyntaxError;
    }
    fn string(self: *Scanner) ![]const u8 {
        const start = self.index;
        try self.expect('"');
        var chunk = self.index;
        while (self.index < self.bytes.len) {
            const byte = self.bytes[self.index];
            if (byte == '"' or byte == '\\') {
                if (!std.unicode.utf8ValidateSlice(self.bytes[chunk..self.index])) return error.SyntaxError;
                self.index += 1;
                if (byte == '"') return self.bytes[start..self.index];
                if (self.index == self.bytes.len) return error.SyntaxError;
                const escaped = self.bytes[self.index];
                self.index += 1;
                if (escaped == 'u') {
                    if (self.bytes.len - self.index < 4) return error.SyntaxError;
                    for (self.bytes[self.index..][0..4]) |digit| if (hex(digit) == null) return error.SyntaxError;
                    self.index += 4;
                } else switch (escaped) {
                    '"', '\\', '/', 'b', 'f', 'n', 'r', 't' => {},
                    else => return error.SyntaxError,
                }
                chunk = self.index;
            } else {
                if (byte < 0x20) return error.SyntaxError;
                self.index += 1;
            }
        }
        return error.SyntaxError;
    }
    fn digits(self: *Scanner) bool {
        const start = self.index;
        while (self.index < self.bytes.len and self.bytes[self.index] >= '0' and self.bytes[self.index] <= '9') self.index += 1;
        return self.index != start;
    }
    fn number(self: *Scanner) !void {
        _ = self.take('-');
        if (!self.take('0')) {
            if (self.index == self.bytes.len or self.bytes[self.index] < '1' or self.bytes[self.index] > '9') return error.SyntaxError;
            _ = self.digits();
        }
        if (self.take('.') and !self.digits()) return error.SyntaxError;
        if (self.take('e') or self.take('E')) {
            if (!self.take('+')) _ = self.take('-');
            if (!self.digits()) return error.SyntaxError;
        }
    }
    fn literal(self: *Scanner, expected: []const u8) !void {
        if (!std.mem.startsWith(u8, self.bytes[self.index..], expected)) return error.SyntaxError;
        self.index += expected.len;
    }
    fn atom(self: *Scanner) !void {
        if (self.index == self.bytes.len) return error.SyntaxError;
        switch (self.bytes[self.index]) {
            '"' => _ = try self.string(),
            '{' => {
                self.index += 1;
                try self.stack.append(self.gpa, .object_first);
            },
            '[' => {
                self.index += 1;
                try self.stack.append(self.gpa, .array_first);
            },
            't' => try self.literal("true"),
            'f' => try self.literal("false"),
            'n' => try self.literal("null"),
            '-', '0'...'9' => try self.number(),
            else => return error.SyntaxError,
        }
    }
    fn value(self: *Scanner) ![]const u8 {
        const start = self.index;
        try self.atom();
        while (self.stack.items.len != 0) {
            self.whitespace();
            const frame = &self.stack.items[self.stack.items.len - 1];
            switch (frame.*) {
                .array_first, .array_more => {
                    if (frame.* == .array_first and self.take(']')) {
                        _ = self.stack.pop();
                    } else {
                        frame.* = .array_after;
                        try self.atom();
                    }
                },
                .array_after => {
                    if (self.take(',')) frame.* = .array_more else if (self.take(']')) {
                        _ = self.stack.pop();
                    } else return error.SyntaxError;
                },
                .object_first, .object_more => {
                    if (frame.* == .object_first and self.take('}')) {
                        _ = self.stack.pop();
                    } else {
                        _ = try self.string();
                        self.whitespace();
                        try self.expect(':');
                        self.whitespace();
                        frame.* = .object_after;
                        try self.atom();
                    }
                },
                .object_after => {
                    if (self.take(',')) frame.* = .object_more else if (self.take('}')) {
                        _ = self.stack.pop();
                    } else return error.SyntaxError;
                },
            }
        }
        return self.bytes[start..self.index];
    }
};
fn hex(byte: u8) ?u16 {
    return switch (byte) {
        '0'...'9' => byte - '0',
        'a'...'f' => byte - 'a' + 10,
        'A'...'F' => byte - 'A' + 10,
        else => null,
    };
}
/// Compare an already validated JSON string with an ASCII protocol field.
/// Surrogate/other Unicode keys remain valid JSON but cannot equal these keys.
pub fn stringEquals(raw: []const u8, expected: []const u8) bool {
    if (raw.len < 2 or raw[0] != '"' or raw[raw.len - 1] != '"') return false;
    var index: usize = 1;
    var matched: usize = 0;
    while (index < raw.len - 1) {
        var unit: u16 = raw[index];
        index += 1;
        if (unit == '\\') {
            const escaped = raw[index];
            index += 1;
            if (escaped == 'u') {
                unit = 0;
                for (raw[index..][0..4]) |digit| unit = unit * 16 + hex(digit).?;
                index += 4;
            } else unit = switch (escaped) {
                '"', '\\', '/' => escaped,
                'b' => 8,
                'f' => 12,
                'n' => 10,
                'r' => 13,
                't' => 9,
                else => unreachable,
            };
        }
        if (matched == expected.len or unit != expected[matched]) return false;
        matched += 1;
    }
    return matched == expected.len;
}
pub fn parse(gpa: std.mem.Allocator, bytes: []const u8) !Envelope {
    var scan: Scanner = .{ .bytes = bytes, .gpa = gpa };
    defer scan.stack.deinit(gpa);
    scan.whitespace();
    if (!scan.take('{')) {
        _ = try scan.value();
        scan.whitespace();
        if (scan.index != bytes.len) return error.SyntaxError;
        return error.NotJsonObject;
    }
    var result: Envelope = .{};
    scan.whitespace();
    if (!scan.take('}')) while (true) {
        const key = try scan.string();
        scan.whitespace();
        try scan.expect(':');
        scan.whitespace();
        const value = try scan.value();
        if (stringEquals(key, "type")) result.kind = value else if (stringEquals(key, "ok")) result.ok = value else if (stringEquals(key, "result")) result.result = value else if (stringEquals(key, "invocationId")) result.invocation_id = value;
        scan.whitespace();
        if (scan.take('}')) break;
        try scan.expect(',');
        scan.whitespace();
    };
    scan.whitespace();
    if (scan.index != bytes.len) return error.SyntaxError;
    return result;
}

test "native raw JSON envelope preserves Source UTF16 escapes and only selects top-level protocol fields" {
    const source = "{\"ok\":true,\"result\":{\"type\":\"native_metadata\",\"invocationId\":\"999\",\"keys\":[\"\\ud83e\",\"\\udd8a\"]},\"invocationId\":\"7\"}";
    const envelope = try parse(std.testing.allocator, source);
    try std.testing.expect(envelope.kind == null);
    try std.testing.expectEqualStrings("true", envelope.ok.?);
    try std.testing.expectEqualStrings("\"7\"", envelope.invocation_id.?);
    try std.testing.expectEqualStrings("{\"type\":\"native_metadata\",\"invocationId\":\"999\",\"keys\":[\"\\ud83e\",\"\\udd8a\"]}", envelope.result.?);
}
test "native raw JSON envelope handles escaped header keys and last duplicate like JSON.parse" {
    const envelope = try parse(std.testing.allocator, "{\"ok\":false,\"\\u006fk\":true,\"\\u0074ype\":\"native\\u005fmetadata\",\"result\":{},\"\\ud800\":\"valid unknown key\"}");
    try std.testing.expectEqualStrings("true", envelope.ok.?);
    try std.testing.expect(stringEquals(envelope.kind.?, "native_metadata"));
}
test "native raw JSON envelope rejects malformed grammar and invalid unescaped UTF8" {
    for ([_][]const u8{ "", "{", "{\"x\":}", "{\"x\":01}", "{\"x\":1.}", "{\"x\":1e+}", "{\"x\":truefalse}", "{\"x\":[],,\"ok\":true}", "{\"x\":[1,]}", "{\"x\":{\"a\":1,}}", "{\"x\":\"\\u12\"}", "{\"x\":\"\\uZZZZ\"}", "{\"x\":\"\\q\"}", "{\"x\":\"\n\"}", "{\"x\":\"\xed\xa0\x80\"}", "{\"x\":\"\xff\"}", "{}false" }) |source| try std.testing.expectError(error.SyntaxError, parse(std.testing.allocator, source));
}
fn allocationCase(gpa: std.mem.Allocator) !void {
    const envelope = try parse(gpa, "{\"ok\":true,\"result\":[[[[[[[[[[[[[[[[[[[[[[[[\"\\ud800\"]]]]]]]]]]]]]]]]]]]]]]]]}");
    try std.testing.expectEqualStrings("true", envelope.ok.?);
}
test "native raw JSON envelope releases nesting storage after every allocation failure" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, allocationCase, .{});
}
