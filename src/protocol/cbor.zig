//! Strict definite-length RFC 8949 subset used by upstream Pi protocol.
//! Ported from packages/protocol/src/cbor/{encoder,decoder,options}.ts.
const std = @import("std");

pub const DEFAULT_MAX_BYTE_LENGTH: usize = 16 * 1024 * 1024;
pub const DEFAULT_MAX_CONTAINER_LENGTH: usize = 1_000_000;
pub const DEFAULT_MAX_DEPTH: usize = 64;

pub const Options = struct {
    max_byte_length: usize = DEFAULT_MAX_BYTE_LENGTH,
    max_container_length: usize = DEFAULT_MAX_CONTAINER_LENGTH,
    max_depth: usize = DEFAULT_MAX_DEPTH,
};

pub const Error = error{
    TooLarge,
    TooDeep,
    InvalidUtf8,
    UnsupportedValue,
    NonFiniteNumber,
    Truncated,
    TrailingData,
    IndefiniteLength,
    UnsupportedTag,
    UnsupportedSimpleValue,
    InvalidMapKey,
    DuplicateMapKey,
    IntegerOverflow,
};

pub fn encode(gpa: std.mem.Allocator, value: std.json.Value, options: Options) ![]u8 {
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(gpa);
    try encodeValue(gpa, &out, value, options, 0);
    if (out.items.len > options.max_byte_length) return Error.TooLarge;
    return try out.toOwnedSlice(gpa);
}

fn encodeValue(gpa: std.mem.Allocator, out: *std.ArrayList(u8), value: std.json.Value, options: Options, depth: usize) !void {
    if (depth > options.max_depth) return Error.TooDeep;
    switch (value) {
        .null => try putByte(gpa, out, 0xf6, options),
        .bool => |b| try putByte(gpa, out, if (b) 0xf5 else 0xf4, options),
        .integer => |n| {
            if (n >= 0) try writeArgument(gpa, out, 0, @intCast(n), options) else try writeArgument(gpa, out, 1, @intCast(-1 - n), options);
        },
        .float => |f| {
            if (!std.math.isFinite(f)) return Error.NonFiniteNumber;
            try putByte(gpa, out, 0xfb, options);
            const bits: u64 = @bitCast(f);
            try putU64(gpa, out, bits, options);
        },
        .number_string => return Error.UnsupportedValue,
        .string => |s| {
            if (!std.unicode.utf8ValidateSlice(s)) return Error.InvalidUtf8;
            if (s.len > options.max_byte_length) return Error.TooLarge;
            try writeArgument(gpa, out, 3, s.len, options);
            try putSlice(gpa, out, s, options);
        },
        .array => |array| {
            if (array.items.len > options.max_container_length) return Error.TooLarge;
            try writeArgument(gpa, out, 4, array.items.len, options);
            for (array.items) |item| try encodeValue(gpa, out, item, options, depth + 1);
        },
        .object => |object| {
            if (object.count() > options.max_container_length) return Error.TooLarge;
            try writeArgument(gpa, out, 5, object.count(), options);
            var it = object.iterator();
            while (it.next()) |entry| {
                const key = entry.key_ptr.*;
                if (!std.unicode.utf8ValidateSlice(key)) return Error.InvalidUtf8;
                try writeArgument(gpa, out, 3, key.len, options);
                try putSlice(gpa, out, key, options);
                try encodeValue(gpa, out, entry.value_ptr.*, options, depth + 1);
            }
        },
    }
}

fn writeArgument(gpa: std.mem.Allocator, out: *std.ArrayList(u8), major: u8, value: usize, options: Options) !void {
    const prefix: u8 = major << 5;
    if (value < 24) return putByte(gpa, out, prefix | @as(u8, @intCast(value)), options);
    if (value <= 0xff) {
        try putByte(gpa, out, prefix | 24, options);
        return putByte(gpa, out, @intCast(value), options);
    }
    if (value <= 0xffff) {
        try putByte(gpa, out, prefix | 25, options);
        return putU16(gpa, out, @intCast(value), options);
    }
    if (value <= 0xffff_ffff) {
        try putByte(gpa, out, prefix | 26, options);
        return putU32(gpa, out, @intCast(value), options);
    }
    try putByte(gpa, out, prefix | 27, options);
    try putU64(gpa, out, @intCast(value), options);
}

fn ensure(out: *std.ArrayList(u8), add: usize, options: Options) !void {
    if (add > options.max_byte_length or out.items.len > options.max_byte_length - add) return Error.TooLarge;
}
fn putByte(gpa: std.mem.Allocator, out: *std.ArrayList(u8), b: u8, options: Options) !void {
    try ensure(out, 1, options);
    try out.append(gpa, b);
}
fn putSlice(gpa: std.mem.Allocator, out: *std.ArrayList(u8), s: []const u8, options: Options) !void {
    try ensure(out, s.len, options);
    try out.appendSlice(gpa, s);
}
fn putU16(gpa: std.mem.Allocator, out: *std.ArrayList(u8), n: u16, options: Options) !void {
    try putByte(gpa, out, @truncate(n >> 8), options);
    try putByte(gpa, out, @truncate(n), options);
}
fn putU32(gpa: std.mem.Allocator, out: *std.ArrayList(u8), n: u32, options: Options) !void {
    inline for (.{ 24, 16, 8, 0 }) |shift| try putByte(gpa, out, @truncate(n >> shift), options);
}
fn putU64(gpa: std.mem.Allocator, out: *std.ArrayList(u8), n: u64, options: Options) !void {
    inline for (.{ 56, 48, 40, 32, 24, 16, 8, 0 }) |shift| try putByte(gpa, out, @truncate(n >> shift), options);
}

pub fn decode(gpa: std.mem.Allocator, bytes: []const u8, options: Options) !std.json.Value {
    if (bytes.len > options.max_byte_length) return Error.TooLarge;
    var reader = Reader{ .gpa = gpa, .bytes = bytes, .options = options };
    const value = try reader.readItem(0);
    errdefer deinitValue(gpa, value);
    if (reader.offset != bytes.len) return Error.TrailingData;
    return value;
}

const Reader = struct {
    gpa: std.mem.Allocator,
    bytes: []const u8,
    offset: usize = 0,
    options: Options,

    fn readItem(self: *Reader, depth: usize) !std.json.Value {
        if (depth > self.options.max_depth) return Error.TooDeep;
        const initial = try self.readByte();
        const major = initial >> 5;
        const ai = initial & 0x1f;
        return switch (major) {
            0 => blk: {
                const n = try self.readArgument(ai);
                if (n > std.math.maxInt(i64)) return Error.IntegerOverflow;
                break :blk .{ .integer = @intCast(n) };
            },
            1 => blk: {
                const n = try self.readArgument(ai);
                if (n > @as(u64, std.math.maxInt(i64))) return Error.IntegerOverflow;
                const i: i64 = @intCast(n);
                break :blk .{ .integer = -1 - i };
            },
            2 => blk: {
                const len = try self.readLength(ai, self.options.max_byte_length);
                const raw = try self.readBytes(len);
                // std.json.Value has no byte-string variant. Pi protocol schemas do not
                // currently use raw byte strings, so reject rather than silently coerce.
                _ = raw;
                break :blk Error.UnsupportedValue;
            },
            3 => blk: {
                const len = try self.readLength(ai, self.options.max_byte_length);
                const raw = try self.readBytes(len);
                if (!std.unicode.utf8ValidateSlice(raw)) return Error.InvalidUtf8;
                break :blk .{ .string = try self.gpa.dupe(u8, raw) };
            },
            4 => blk: {
                const len = try self.readLength(ai, self.options.max_container_length);
                var arr = std.json.Array.init(self.gpa);
                errdefer {
                    for (arr.items) |v| deinitValue(self.gpa, v);
                    arr.deinit();
                }
                var i: usize = 0;
                while (i < len) : (i += 1) try arr.append(try self.readItem(depth + 1));
                break :blk .{ .array = arr };
            },
            5 => blk: {
                const len = try self.readLength(ai, self.options.max_container_length);
                var obj: std.json.ObjectMap = .empty;
                errdefer deinitObject(self.gpa, &obj);
                var i: usize = 0;
                while (i < len) : (i += 1) {
                    const key_value = try self.readItem(depth + 1);
                    if (key_value != .string) {
                        deinitValue(self.gpa, key_value);
                        return Error.InvalidMapKey;
                    }
                    const key = key_value.string;
                    if (obj.get(key) != null) {
                        self.gpa.free(key);
                        return Error.DuplicateMapKey;
                    }
                    const value = self.readItem(depth + 1) catch |err| {
                        self.gpa.free(key);
                        return err;
                    };
                    try obj.put(self.gpa, key, value);
                }
                break :blk .{ .object = obj };
            },
            6 => Error.UnsupportedTag,
            7 => try self.readSimple(ai),
            else => unreachable,
        };
    }

    fn readSimple(self: *Reader, ai: u8) !std.json.Value {
        return switch (ai) {
            20 => .{ .bool = false },
            21 => .{ .bool = true },
            22 => .null,
            27 => blk: {
                const raw = try self.readU64();
                const f: f64 = @bitCast(raw);
                if (!std.math.isFinite(f)) return Error.NonFiniteNumber;
                break :blk .{ .float = f };
            },
            31 => Error.IndefiniteLength,
            else => Error.UnsupportedSimpleValue,
        };
    }

    fn readLength(self: *Reader, ai: u8, limit: usize) !usize {
        if (ai == 31) return Error.IndefiniteLength;
        const n = try self.readArgument(ai);
        if (n > limit) return Error.TooLarge;
        return @intCast(n);
    }

    fn readArgument(self: *Reader, ai: u8) !u64 {
        if (ai < 24) return ai;
        return switch (ai) {
            24 => try self.readByte(),
            25 => try self.readU16(),
            26 => try self.readU32(),
            27 => try self.readU64(),
            31 => Error.IndefiniteLength,
            else => Error.UnsupportedSimpleValue,
        };
    }

    fn readByte(self: *Reader) !u8 {
        if (self.offset >= self.bytes.len) return Error.Truncated;
        defer self.offset += 1;
        return self.bytes[self.offset];
    }
    fn readBytes(self: *Reader, len: usize) ![]const u8 {
        if (len > self.bytes.len - self.offset) return Error.Truncated;
        const slice = self.bytes[self.offset .. self.offset + len];
        self.offset += len;
        return slice;
    }
    fn readU16(self: *Reader) !u16 {
        const b = try self.readBytes(2);
        return (@as(u16, b[0]) << 8) | b[1];
    }
    fn readU32(self: *Reader) !u32 {
        const b = try self.readBytes(4);
        return (@as(u32, b[0]) << 24) | (@as(u32, b[1]) << 16) | (@as(u32, b[2]) << 8) | b[3];
    }
    fn readU64(self: *Reader) !u64 {
        const b = try self.readBytes(8);
        var n: u64 = 0;
        for (b) |x| n = (n << 8) | x;
        return n;
    }
};

pub fn deinitValue(gpa: std.mem.Allocator, value: std.json.Value) void {
    switch (value) {
        .string, .number_string => |s| gpa.free(s),
        .array => |arr_const| {
            var arr = arr_const;
            for (arr.items) |v| deinitValue(gpa, v);
            arr.deinit();
        },
        .object => |obj_const| {
            var obj = obj_const;
            deinitObject(gpa, &obj);
        },
        else => {},
    }
}

fn deinitObject(gpa: std.mem.Allocator, obj: *std.json.ObjectMap) void {
    var it = obj.iterator();
    while (it.next()) |entry| {
        gpa.free(entry.key_ptr.*);
        deinitValue(gpa, entry.value_ptr.*);
    }
    obj.deinit(gpa);
}

test "CBOR primitives match RFC encodings" {
    const gpa = std.testing.allocator;
    const one = try encode(gpa, .{ .integer = 1 }, .{});
    defer gpa.free(one);
    try std.testing.expectEqualSlices(u8, &[_]u8{0x01}, one);
    const neg = try encode(gpa, .{ .integer = -1 }, .{});
    defer gpa.free(neg);
    try std.testing.expectEqualSlices(u8, &[_]u8{0x20}, neg);
    const text = try encode(gpa, .{ .string = "hi" }, .{});
    defer gpa.free(text);
    try std.testing.expectEqualSlices(u8, &[_]u8{ 0x62, 'h', 'i' }, text);
}

test "CBOR object roundtrip" {
    const gpa = std.testing.allocator;
    var obj: std.json.ObjectMap = .empty;
    defer obj.deinit(gpa);
    try obj.put(gpa, "type", .{ .string = "hello" });
    try obj.put(gpa, "version", .{ .integer = 1 });
    const bytes = try encode(gpa, .{ .object = obj }, .{});
    defer gpa.free(bytes);
    const decoded = try decode(gpa, bytes, .{});
    defer deinitValue(gpa, decoded);
    try std.testing.expect(decoded == .object);
    try std.testing.expectEqualStrings("hello", decoded.object.get("type").?.string);
    try std.testing.expectEqual(@as(i64, 1), decoded.object.get("version").?.integer);
}

test "CBOR multi-byte integers do not trap while narrowing" {
    const gpa = std.testing.allocator;
    const v = std.json.Value{ .integer = 4_294_967_296 };
    const encoded = try encode(gpa, v, .{});
    defer gpa.free(encoded);
    const decoded = try decode(gpa, encoded, .{});
    defer deinitValue(gpa, decoded);
    try std.testing.expect(decoded == .integer);
    try std.testing.expectEqual(@as(i64, 4_294_967_296), decoded.integer);
}
