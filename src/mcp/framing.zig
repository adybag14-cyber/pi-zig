//! Stateful newline framing: bytes after a complete record survive the next read.
const std = @import("std");

pub const LineBuffer = struct {
    bytes: std.ArrayList(u8) = .empty,
    max_message_bytes: usize = 16 * 1024 * 1024,

    pub fn deinit(self: *LineBuffer, gpa: std.mem.Allocator) void {
        self.bytes.deinit(gpa);
        self.* = undefined;
    }

    pub fn append(self: *LineBuffer, gpa: std.mem.Allocator, chunk: []const u8) !void {
        // Check each record separately: a batch of short messages is permitted.
        var size = if (std.mem.lastIndexOfScalar(u8, self.bytes.items, '\n')) |index| self.bytes.items.len - index - 1 else self.bytes.items.len;
        for (chunk) |byte| {
            if (byte == '\n') {
                size = 0;
            } else {
                if (size >= self.max_message_bytes) return error.McpMessageTooLarge;
                size += 1;
            }
        }
        try self.bytes.appendSlice(gpa, chunk);
    }

    pub fn next(self: *LineBuffer, gpa: std.mem.Allocator) !?[]u8 {
        const end = std.mem.indexOfScalar(u8, self.bytes.items, '\n') orelse return null;
        const content = std.mem.trimEnd(u8, self.bytes.items[0..end], "\r");
        const line = try gpa.dupe(u8, content);
        const remaining = self.bytes.items.len - end - 1;
        std.mem.copyForwards(u8, self.bytes.items[0..remaining], self.bytes.items[end + 1 ..]);
        self.bytes.items.len = remaining;
        return line;
    }

    pub fn finish(self: *const LineBuffer) !void {
        if (std.mem.trim(u8, self.bytes.items, " \t\r\n").len > 0) return error.IncompleteMcpMessage;
    }
};

test "MCP framing retains coalesced records and fragmented UTF8" {
    const gpa = std.testing.allocator;
    var buffer: LineBuffer = .{};
    defer buffer.deinit(gpa);
    try buffer.append(gpa, "first\r\nsecond\n\xc3");
    const first = (try buffer.next(gpa)).?;
    defer gpa.free(first);
    const second = (try buffer.next(gpa)).?;
    defer gpa.free(second);
    try std.testing.expectEqualStrings("first", first);
    try std.testing.expectEqualStrings("second", second);
    try std.testing.expect((try buffer.next(gpa)) == null);
    try buffer.append(gpa, "\xa9\n");
    const unicode = (try buffer.next(gpa)).?;
    defer gpa.free(unicode);
    try std.testing.expectEqualStrings("é", unicode);
    try buffer.finish();
}

test "MCP framing bounds individual messages and rejects truncated EOF" {
    const gpa = std.testing.allocator;
    var buffer: LineBuffer = .{ .max_message_bytes = 3 };
    defer buffer.deinit(gpa);
    try buffer.append(gpa, "abc\nabc\n");
    try std.testing.expectError(error.McpMessageTooLarge, buffer.append(gpa, "abcd\n"));
    try buffer.append(gpa, "{");
    try std.testing.expectError(error.IncompleteMcpMessage, buffer.finish());
}
