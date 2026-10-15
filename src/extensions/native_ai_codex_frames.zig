//! Incremental RFC6455 server frames. Partial framing remains owned while a
//! command wakes the worker and cancels a non-consuming network peek.
const std = @import("std");
const socket = @import("../ai/codex_websocket.zig");
pub const Frame = struct { fin: bool, opcode: socket.Opcode, data: []u8 };
pub const Decoder = struct {
    buffer: std.ArrayList(u8) = .empty,
    pub fn deinit(self: *Decoder, allocator: std.mem.Allocator) void {
        self.buffer.deinit(allocator);
    }
    pub fn append(self: *Decoder, allocator: std.mem.Allocator, bytes: []const u8) !void {
        try self.buffer.appendSlice(allocator, bytes);
    }
    pub fn next(self: *Decoder, allocator: std.mem.Allocator) !?Frame {
        const bytes = self.buffer.items;
        if (bytes.len < 2) return null;
        const fin = bytes[0] & 0x80 != 0;
        if (bytes[0] & 0x70 != 0) return error.WebSocketReservedBits;
        if (bytes[1] & 0x80 != 0) return error.WebSocketServerFrameMasked;
        const opcode: socket.Opcode = @enumFromInt(bytes[0] & 0x0f);
        var prefix: usize = 2;
        const length: u64 = switch (bytes[1] & 0x7f) {
            126 => value: {
                if (bytes.len < 4) return null;
                prefix = 4;
                const extended = std.mem.readInt(u16, bytes[2..4], .big);
                if (extended < 126) return error.WebSocketNonMinimalLength;
                break :value extended;
            },
            127 => value: {
                if (bytes.len < 10) return null;
                prefix = 10;
                if (bytes[2] & 0x80 != 0) return error.WebSocketMessageTooLarge;
                const extended = std.mem.readInt(u64, bytes[2..10], .big);
                if (extended <= 65535) return error.WebSocketNonMinimalLength;
                break :value extended;
            },
            else => bytes[1] & 0x7f,
        };
        const size = std.math.cast(usize, length) orelse return error.WebSocketMessageTooLarge;
        if (@intFromEnum(opcode) & 8 != 0 and (!fin or size > 125)) return error.WebSocketInvalidControlFrame;
        const total = std.math.add(usize, prefix, size) catch return error.WebSocketMessageTooLarge;
        if (bytes.len < total) return null;
        const payload = try allocator.dupe(u8, bytes[prefix..total]);
        std.mem.copyForwards(u8, self.buffer.items[0 .. bytes.len - total], bytes[total..]);
        self.buffer.items.len -= total;
        return .{ .fin = fin, .opcode = opcode, .data = payload };
    }
};

test "native Codex socket incremental frames preserve partial headers and payloads across command boundaries" {
    const allocator = std.testing.allocator;
    var decoder: Decoder = .{};
    defer decoder.deinit(allocator);
    try decoder.append(allocator, &.{0x01});
    try std.testing.expect(try decoder.next(allocator) == null);
    try decoder.append(allocator, &.{ 3, 'a' });
    try std.testing.expect(try decoder.next(allocator) == null);
    try decoder.append(allocator, &.{ 'b', 'c', 0x89, 1, 'p', 0x80, 2, 'd' });
    const first = (try decoder.next(allocator)).?;
    defer allocator.free(first.data);
    try std.testing.expect(!first.fin and first.opcode == .text);
    try std.testing.expectEqualStrings("abc", first.data);
    const ping = (try decoder.next(allocator)).?;
    defer allocator.free(ping.data);
    try std.testing.expect(ping.fin and ping.opcode == .ping);
    try std.testing.expectEqualStrings("p", ping.data);
    try std.testing.expect(try decoder.next(allocator) == null);
    try decoder.append(allocator, "e");
    const last = (try decoder.next(allocator)).?;
    defer allocator.free(last.data);
    try std.testing.expect(last.fin and last.opcode == .continuation);
    try std.testing.expectEqualStrings("de", last.data);
    try std.testing.expect(try decoder.next(allocator) == null);
}

test "native Codex socket incremental frames reject masked nonminimal and fragmented control frames" {
    const allocator = std.testing.allocator;
    inline for (.{
        .{ &[_]u8{ 0x81, 0x80 }, error.WebSocketServerFrameMasked },
        .{ &[_]u8{ 0x81, 126, 0, 1 }, error.WebSocketNonMinimalLength },
        .{ &[_]u8{ 0x81, 127, 0, 0, 0, 0, 0, 0, 0, 2 }, error.WebSocketNonMinimalLength },
        .{ &[_]u8{ 0x09, 0 }, error.WebSocketInvalidControlFrame },
    }) |row| {
        var decoder: Decoder = .{};
        defer decoder.deinit(allocator);
        try decoder.append(allocator, row[0]);
        try std.testing.expectError(row[1], decoder.next(allocator));
    }
}
