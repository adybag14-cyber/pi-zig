//! JSON ownership boundary with JavaScript-compatible UTF-16 string contents.
//! Strings use WTF-8 internally so escaped lone surrogates remain lossless.
const std = @import("std");
pub const Value = std.json.Value;
pub const max_depth = 512;
pub const Parser = struct {
    gpa: std.mem.Allocator,
    input: []const u8,
    position: usize = 0,
    fn space(self: *Parser) void {
        while (self.position < self.input.len and std.mem.indexOfScalar(u8, " \r\n\t", self.input[self.position]) != null) self.position += 1;
    }
    fn consume(self: *Parser, byte: u8) bool {
        self.space();
        if (self.position < self.input.len and self.input[self.position] == byte) {
            self.position += 1;
            return true;
        }
        return false;
    }
    fn hex(self: *Parser) !u16 {
        if (self.position + 4 > self.input.len) return error.InvalidJSON;
        const value = std.fmt.parseInt(u16, self.input[self.position..][0..4], 16) catch return error.InvalidJSON;
        self.position += 4;
        return value;
    }
    fn string(self: *Parser) ![]const u8 {
        if (!self.consume('"')) return error.InvalidJSON;
        var output: std.ArrayList(u8) = .empty;
        defer output.deinit(self.gpa);
        while (self.position < self.input.len) {
            const byte = self.input[self.position];
            self.position += 1;
            if (byte == '"') return output.toOwnedSlice(self.gpa);
            if (byte < 32) return error.InvalidJSON;
            if (byte != '\\') {
                try output.append(self.gpa, byte);
                continue;
            }
            if (self.position == self.input.len) return error.InvalidJSON;
            const escaped = self.input[self.position];
            self.position += 1;
            switch (escaped) {
                '"', '\\', '/' => try output.append(self.gpa, escaped),
                'b' => try output.append(self.gpa, 8),
                'f' => try output.append(self.gpa, 12),
                'n' => try output.append(self.gpa, '\n'),
                'r' => try output.append(self.gpa, '\r'),
                't' => try output.append(self.gpa, '\t'),
                'u' => {
                    const first = try self.hex();
                    var point: u21 = first;
                    if (std.unicode.utf16IsHighSurrogate(first) and self.position + 6 <= self.input.len and std.mem.startsWith(u8, self.input[self.position..], "\\u")) {
                        const saved = self.position;
                        self.position += 2;
                        const second = try self.hex();
                        if (std.unicode.utf16IsLowSurrogate(second)) point = try std.unicode.utf16DecodeSurrogatePair(&.{ first, second }) else self.position = saved;
                    }
                    var bytes: [4]u8 = undefined;
                    const count = try std.unicode.wtf8Encode(point, &bytes);
                    try output.appendSlice(self.gpa, bytes[0..count]);
                },
                else => return error.InvalidJSON,
            }
        }
        return error.InvalidJSON;
    }
    fn number(self: *Parser) !Value {
        const from = self.position;
        if (self.input[self.position] == '-') self.position += 1;
        if (self.position == self.input.len) return error.InvalidJSON;
        if (self.input[self.position] == '0') self.position += 1 else {
            if (self.input[self.position] < '1' or self.input[self.position] > '9') return error.InvalidJSON;
            while (self.position < self.input.len and std.ascii.isDigit(self.input[self.position])) self.position += 1;
        }
        if (self.position < self.input.len and self.input[self.position] == '.') {
            self.position += 1;
            const digits = self.position;
            while (self.position < self.input.len and std.ascii.isDigit(self.input[self.position])) self.position += 1;
            if (digits == self.position) return error.InvalidJSON;
        }
        if (self.position < self.input.len and (self.input[self.position] == 'e' or self.input[self.position] == 'E')) {
            self.position += 1;
            if (self.position < self.input.len and (self.input[self.position] == '+' or self.input[self.position] == '-')) self.position += 1;
            const digits = self.position;
            while (self.position < self.input.len and std.ascii.isDigit(self.input[self.position])) self.position += 1;
            if (digits == self.position) return error.InvalidJSON;
        }
        const value = std.fmt.parseFloat(f64, self.input[from..self.position]) catch return error.InvalidJSON;
        if (!std.math.isFinite(value)) return error.NonfiniteJSONNumber;
        return .{ .float = value };
    }
    fn parseValue(self: *Parser, depth: usize) anyerror!Value {
        if (depth > max_depth) return error.JSONDepthExceeded;
        self.space();
        if (self.position == self.input.len) return error.InvalidJSON;
        switch (self.input[self.position]) {
            '"' => return .{ .string = try self.string() },
            '{' => {
                self.position += 1;
                var object: std.json.ObjectMap = .empty;
                if (self.consume('}')) return .{ .object = object };
                while (true) {
                    const key = try self.string();
                    if (!self.consume(':')) return error.InvalidJSON;
                    const child = try self.parseValue(depth + 1);
                    try object.put(self.gpa, key, child);
                    if (self.consume('}')) break;
                    if (!self.consume(',')) return error.InvalidJSON;
                }
                return .{ .object = object };
            },
            '[' => {
                self.position += 1;
                var array: std.array_list.Managed(Value) = .init(self.gpa);
                if (self.consume(']')) return .{ .array = array };
                while (true) {
                    try array.append(try self.parseValue(depth + 1));
                    if (self.consume(']')) break;
                    if (!self.consume(',')) return error.InvalidJSON;
                }
                return .{ .array = array };
            },
            't', 'f', 'n' => {
                const literal: []const u8 = switch (self.input[self.position]) {
                    't' => "true",
                    'f' => "false",
                    else => "null",
                };
                if (!std.mem.startsWith(u8, self.input[self.position..], literal)) return error.InvalidJSON;
                self.position += literal.len;
                return switch (literal[0]) {
                    't' => .{ .bool = true },
                    'f' => .{ .bool = false },
                    else => .null,
                };
            },
            '-', '0'...'9' => return self.number(),
            else => return error.InvalidJSON,
        }
    }
};
/// Parser allocations belong to an arena or another allocation scope supplied
/// by the caller. Failed parses may have allocated partial container trees.
pub fn parseLeaky(gpa: std.mem.Allocator, input: []const u8) !Value {
    if (!std.unicode.utf8ValidateSlice(input)) return error.InvalidJSON;
    var parser: Parser = .{ .gpa = gpa, .input = input };
    const value = try parser.parseValue(0);
    parser.space();
    if (parser.position != input.len) return error.InvalidJSON;
    return value;
}
/// TextEncoder's USV conversion for tool output, while stored JSON stays lossless.
pub fn usv(gpa: std.mem.Allocator, input: []const u8) ![]u8 {
    if (std.unicode.utf8ValidateSlice(input)) return gpa.dupe(u8, input);
    const units = try std.unicode.wtf8ToWtf16LeAlloc(gpa, input);
    defer gpa.free(units);
    var output: std.ArrayList(u8) = .empty;
    defer output.deinit(gpa);
    var index: usize = 0;
    var bytes: [4]u8 = undefined;
    while (index < units.len) : (index += 1) {
        const unit = std.mem.littleToNative(u16, units[index]);
        var point: u21 = unit;
        if (std.unicode.utf16IsHighSurrogate(unit)) {
            if (index + 1 < units.len and std.unicode.utf16IsLowSurrogate(std.mem.littleToNative(u16, units[index + 1]))) {
                point = try std.unicode.utf16DecodeSurrogatePair(&.{ unit, std.mem.littleToNative(u16, units[index + 1]) });
                index += 1;
            } else point = 0xfffd;
        } else if (std.unicode.utf16IsLowSurrogate(unit)) point = 0xfffd;
        const count = try std.unicode.utf8Encode(point, &bytes);
        try output.appendSlice(gpa, bytes[0..count]);
    }
    return output.toOwnedSlice(gpa);
}
pub const Owned = struct {
    arena: *std.heap.ArenaAllocator,
    value: Value,
    pub fn parse(gpa: std.mem.Allocator, input: []const u8) !Owned {
        var owned = try empty(gpa);
        errdefer owned.deinit();
        owned.value = try parseLeaky(owned.arena.allocator(), input);
        return owned;
    }
    pub fn empty(gpa: std.mem.Allocator) !Owned {
        const arena = try gpa.create(std.heap.ArenaAllocator);
        arena.* = std.heap.ArenaAllocator.init(gpa);
        return .{ .arena = arena, .value = .null };
    }
    pub fn deinit(self: *Owned) void {
        const gpa = self.arena.child_allocator;
        self.arena.deinit();
        gpa.destroy(self.arena);
        self.* = undefined;
    }
};
pub fn clone(gpa: std.mem.Allocator, value: Value) anyerror!Value {
    return switch (value) {
        .string => |string| .{ .string = try gpa.dupe(u8, string) },
        .array => |array| blk: {
            var copy: std.array_list.Managed(Value) = .init(gpa);
            for (array.items) |item| try copy.append(try clone(gpa, item));
            break :blk .{ .array = copy };
        },
        .object => |object| blk: {
            var copy: std.json.ObjectMap = .empty;
            var iterator = object.iterator();
            while (iterator.next()) |item| try copy.put(gpa, try gpa.dupe(u8, item.key_ptr.*), try clone(gpa, item.value_ptr.*));
            break :blk .{ .object = copy };
        },
        else => value,
    };
}
fn quote(gpa: std.mem.Allocator, output: *std.ArrayList(u8), string: []const u8) !void {
    try output.append(gpa, '"');
    var iterator = (try std.unicode.Wtf8View.init(string)).iterator();
    var bytes: [8]u8 = undefined;
    while (iterator.nextCodepoint()) |point| {
        if (point == '"' or point == '\\') {
            try output.append(gpa, '\\');
            try output.append(gpa, @intCast(point));
        } else if (point < 32 or (point >= 0xd800 and point <= 0xdfff)) {
            const escape = try std.fmt.bufPrint(&bytes, "\\u{x:0>4}", .{point});
            try output.appendSlice(gpa, escape);
        } else {
            const count = try std.unicode.utf8Encode(point, &bytes);
            try output.appendSlice(gpa, bytes[0..count]);
        }
    }
    try output.append(gpa, '"');
}
fn encode(gpa: std.mem.Allocator, output: *std.ArrayList(u8), value: Value) anyerror!void {
    switch (value) {
        .null => try output.appendSlice(gpa, "null"),
        .bool => |boolean| try output.appendSlice(gpa, if (boolean) "true" else "false"),
        .integer => |number| {
            var bytes: [32]u8 = undefined;
            try output.appendSlice(gpa, try std.fmt.bufPrint(&bytes, "{d}", .{number}));
        },
        .float => |number| {
            if (!std.math.isFinite(number)) return error.NonfiniteJSONNumber;
            const text = try std.fmt.allocPrint(gpa, "{d}", .{if (number == 0) @as(f64, 0) else number});
            defer gpa.free(text);
            try output.appendSlice(gpa, text);
        },
        .number_string => |number| try output.appendSlice(gpa, number),
        .string => |string| try quote(gpa, output, string),
        .array => |array| {
            try output.append(gpa, '[');
            for (array.items, 0..) |item, index| {
                if (index != 0) try output.append(gpa, ',');
                try encode(gpa, output, item);
            }
            try output.append(gpa, ']');
        },
        .object => |object| {
            try output.append(gpa, '{');
            var iterator = object.iterator();
            var index: usize = 0;
            while (iterator.next()) |item| {
                if (index != 0) try output.append(gpa, ',');
                try quote(gpa, output, item.key_ptr.*);
                try output.append(gpa, ':');
                try encode(gpa, output, item.value_ptr.*);
                index += 1;
            }
            try output.append(gpa, '}');
        },
    }
}
pub fn stringify(gpa: std.mem.Allocator, value: Value) ![]u8 {
    var output: std.ArrayList(u8) = .empty;
    defer output.deinit(gpa);
    try encode(gpa, &output, value);
    return output.toOwnedSlice(gpa);
}
pub fn asNumber(value: Value) !f64 {
    return switch (value) {
        .integer => |integer| @floatFromInt(integer),
        .float => |float| float,
        else => error.ExpectedNumber,
    };
}
pub fn asInteger(value: Value) !u64 {
    const result = try asNumber(value);
    if (!std.math.isFinite(result) or result < 0 or result > 9007199254740991 or result != @trunc(result)) return error.InvalidSafeInteger;
    return @intFromFloat(result);
}
pub fn get(value: Value, key: []const u8) ?Value {
    return if (value == .object) value.object.get(key) else null;
}
pub fn required(value: Value, key: []const u8) !Value {
    return get(value, key) orelse error.MissingField;
}
pub fn asString(value: Value) ![]const u8 {
    return if (value == .string) value.string else error.ExpectedString;
}
pub fn equal(a: Value, b: Value) bool {
    if ((a == .integer or a == .float) and (b == .integer or b == .float)) return (asNumber(a) catch unreachable) == (asNumber(b) catch unreachable);
    if (std.meta.activeTag(a) != std.meta.activeTag(b)) return false;
    return switch (a) {
        .null => true,
        .bool => a.bool == b.bool,
        .string => std.mem.eql(u8, a.string, b.string),
        .integer => a.integer == b.integer,
        .float => a.float == b.float,
        .number_string => std.mem.eql(u8, a.number_string, b.number_string),
        .array => blk: {
            if (a.array.items.len != b.array.items.len) break :blk false;
            for (a.array.items, b.array.items) |x, y| if (!equal(x, y)) break :blk false;
            break :blk true;
        },
        .object => blk: {
            if (a.object.count() != b.object.count()) break :blk false;
            var iterator = a.object.iterator();
            while (iterator.next()) |item| {
                const child = b.object.get(item.key_ptr.*) orelse break :blk false;
                if (!equal(item.value_ptr.*, child)) break :blk false;
            }
            break :blk true;
        },
    };
}

test "durable JSON owns escaped lone surrogate values keys and numeric rounding" {
    const gpa = std.testing.allocator;
    var owned = try Owned.parse(gpa, "{\"\\ud800\":\"x\\udfff\",\"big\":9007199254740993,\"pair\":\"\\ud83d\\ude00\"}");
    defer owned.deinit();
    try std.testing.expectEqual(@as(f64, 9007199254740992), try asNumber(owned.value.object.get("big").?));
    const encoded = try stringify(gpa, owned.value);
    defer gpa.free(encoded);
    var again = try Owned.parse(gpa, encoded);
    defer again.deinit();
    try std.testing.expect(equal(owned.value, again.value));
    try std.testing.expect(std.mem.indexOf(u8, encoded, "\\ud800") != null);
    try std.testing.expect(std.mem.indexOf(u8, encoded, "\\udfff") != null);
}
