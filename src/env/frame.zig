//! Pi-env protocol v1: bounded big-endian frames and owned JSON/payload data.
const std = @import("std");
pub const protocol = 1;
pub const maximum_frame = 16 * 1024 * 1024;
pub const maximum_payload = maximum_frame - 64 * 1024;
pub const Kind = enum(u8) { request = 1, result = 2, remote_error = 3, event = 4, cancel = 5, ping = 6, _ };
pub const Frame = struct {
    gpa: std.mem.Allocator,
    kind: Kind,
    id: u32,
    json: std.json.Parsed(std.json.Value),
    payload: []u8,
    wire_bytes: usize,
    pub fn deinit(self: *Frame) void {
        self.json.deinit();
        self.gpa.free(self.payload);
        self.* = undefined;
    }
};
pub fn encode(gpa: std.mem.Allocator, kind: Kind, id: u32, value: anytype, payload: []const u8) ![]u8 {
    const json = try std.json.Stringify.valueAlloc(gpa, value, .{ .emit_null_optional_fields = false });
    defer gpa.free(json);
    return encodeJson(gpa, kind, id, json, payload);
}
pub fn encodeJson(gpa: std.mem.Allocator, kind: Kind, id: u32, json: []const u8, payload: []const u8) ![]u8 {
    if (json.len > maximum_frame - 9 or payload.len > maximum_frame - 9 - json.len) return error.FrameTooLarge;
    const body_length = 9 + json.len + payload.len;
    const bytes = try gpa.alloc(u8, 4 + body_length);
    std.mem.writeInt(u32, bytes[0..4], @intCast(body_length), .big);
    bytes[4] = @intFromEnum(kind);
    std.mem.writeInt(u32, bytes[5..9], id, .big);
    std.mem.writeInt(u32, bytes[9..13], @intCast(json.len), .big);
    @memcpy(bytes[13..][0..json.len], json);
    @memcpy(bytes[13 + json.len ..], payload);
    return bytes;
}
pub fn decode(gpa: std.mem.Allocator, bytes: []const u8) !Frame {
    if (bytes.len < 4) return error.TruncatedFrame;
    const length = std.mem.readInt(u32, bytes[0..4], .big);
    if (length < 9 or length > maximum_frame) return error.InvalidFrameLength;
    if (bytes.len != 4 + @as(usize, length)) return error.TruncatedFrame;
    const json_length = std.mem.readInt(u32, bytes[9..13], .big);
    if (json_length > length - 9) return error.InvalidJsonLength;
    const json_bytes = bytes[13..][0..json_length];
    var parsed = std.json.parseFromSlice(std.json.Value, gpa, if (json_bytes.len == 0) "{}" else json_bytes, .{ .allocate = .alloc_always, .duplicate_field_behavior = .use_last }) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        else => try std.json.parseFromSlice(std.json.Value, gpa, "null", .{}),
    };
    errdefer parsed.deinit();
    const payload = try gpa.dupe(u8, bytes[13 + json_length ..]);
    return .{ .gpa = gpa, .kind = @enumFromInt(bytes[4]), .id = std.mem.readInt(u32, bytes[5..9], .big), .json = parsed, .payload = payload, .wire_bytes = bytes.len };
}
/// Append partial frames and drain before accepting another complete-frame batch.
/// receive() retains one frame at most; unconsumed input is returned to the caller.
pub const Decoder = struct {
    gpa: std.mem.Allocator,
    bytes: std.ArrayList(u8) = .empty,
    pub fn init(gpa: std.mem.Allocator) Decoder {
        return .{ .gpa = gpa };
    }
    pub fn deinit(self: *Decoder) void {
        self.bytes.deinit(self.gpa);
    }
    pub fn receive(self: *Decoder, input: []const u8) !usize {
        var consumed: usize = 0;
        if (self.bytes.items.len < 4) {
            const take = @min(4 - self.bytes.items.len, input.len);
            try self.bytes.appendSlice(self.gpa, input[0..take]);
            consumed = take;
        }
        if (self.bytes.items.len < 4) return consumed;
        const length = std.mem.readInt(u32, self.bytes.items[0..4], .big);
        if (length < 9 or length > maximum_frame) return error.InvalidFrameLength;
        const total = 4 + @as(usize, length);
        const take = @min(total - self.bytes.items.len, input.len - consumed);
        try self.bytes.appendSlice(self.gpa, input[consumed..][0..take]);
        return consumed + take;
    }
    pub fn next(self: *Decoder) !?Frame {
        if (self.bytes.items.len < 4) return null;
        const length = std.mem.readInt(u32, self.bytes.items[0..4], .big);
        if (length < 9 or length > maximum_frame) return error.InvalidFrameLength;
        if (self.bytes.items.len < 4 + @as(usize, length)) return null;
        const frame = try decode(self.gpa, self.bytes.items);
        self.bytes.clearRetainingCapacity();
        return frame;
    }
    pub fn end(self: *const Decoder) !void {
        if (self.bytes.items.len != 0) return error.TruncatedFrame;
    }
};
/// Streaming sync marker matcher retains only the token-sized suffix of banners.
pub const Sync = struct {
    marker: [72]u8 = undefined,
    length: usize,
    matched: usize = 0,
    ready: bool = false,
    pub fn init(token: []const u8) !Sync {
        if (token.len == 0 or token.len > 64) return error.InvalidSyncToken;
        for (token) |byte| if (!std.ascii.isHex(byte)) return error.InvalidSyncToken;
        var self: Sync = .{ .length = 8 + token.len };
        @memcpy(self.marker[0..7], "PI-ENV ");
        @memcpy(self.marker[7..][0..token.len], token);
        self.marker[7 + token.len] = '\n';
        return self;
    }
    pub fn receive(self: *Sync, bytes: []const u8) usize {
        if (self.ready) return 0;
        for (bytes, 0..) |byte, index| {
            if (byte == self.marker[self.matched]) self.matched += 1 else self.matched = if (byte == 'P') 1 else 0;
            if (self.matched == self.length) {
                self.ready = true;
                return index + 1;
            }
        }
        return bytes.len;
    }
};
test "Pi-env golden framing matches Node and Rust big-endian protocol bytes" {
    const gpa = std.testing.allocator;
    const golden = [_]u8{ 0, 0, 0, 19, 2, 0, 0, 0, 7, 0, 0, 0, 7, '{', '"', 'a', '"', ':', '1', '}', 0, 255, 10 };
    const encoded = try encode(gpa, .result, 7, .{ .a = 1 }, &.{ 0, 255, 10 });
    defer gpa.free(encoded);
    try std.testing.expectEqualSlices(u8, &golden, encoded);
    var frame = try decode(gpa, &golden);
    defer frame.deinit();
    try std.testing.expectEqual(Kind.result, frame.kind);
    try std.testing.expectEqual(@as(u32, 7), frame.id);
    try std.testing.expectEqual(@as(i64, 1), frame.json.value.object.get("a").?.integer);
    try std.testing.expectEqualSlices(u8, &.{ 0, 255, 10 }, frame.payload);
}
test "Pi-env fragmented batches drain without retaining later frames" {
    const gpa = std.testing.allocator;
    const bytes = try encode(gpa, .event, 0xffffffff, .{ .kind = "output", .stream = "stderr" }, "🚀\x00\xff");
    defer gpa.free(bytes);
    for (0..bytes.len + 1) |split| {
        var decoder = Decoder.init(gpa);
        defer decoder.deinit();
        try std.testing.expectEqual(split, try decoder.receive(bytes[0..split]));
        if (split != bytes.len) try std.testing.expect((try decoder.next()) == null);
        try std.testing.expectEqual(bytes.len - split, try decoder.receive(bytes[split..]));
        var frame = (try decoder.next()).?;
        defer frame.deinit();
        try std.testing.expectEqualSlices(u8, "🚀\x00\xff", frame.payload);
        try std.testing.expectEqual(@as(u32, 0xffffffff), frame.id);
        try decoder.end();
    }
    var decoder = Decoder.init(gpa);
    defer decoder.deinit();
    const combined = try std.mem.concat(gpa, u8, &.{ bytes, bytes });
    defer gpa.free(combined);
    try std.testing.expectEqual(bytes.len, try decoder.receive(combined));
    var first = (try decoder.next()).?;
    defer first.deinit();
    try std.testing.expectEqual(bytes.len, try decoder.receive(combined[bytes.len..]));
    var second = (try decoder.next()).?;
    defer second.deinit();
}
test "Pi-env rejects lengths malformed JSON and truncated input before payload allocation" {
    const gpa = std.testing.allocator;
    try std.testing.expectError(error.InvalidFrameLength, decode(gpa, &.{ 0, 0, 0, 8 }));
    try std.testing.expectError(error.InvalidFrameLength, decode(gpa, &.{ 1, 0, 0, 1 }));
    try std.testing.expectError(error.InvalidJsonLength, decode(gpa, &.{ 0, 0, 0, 9, 1, 0, 0, 0, 1, 0, 0, 0, 1 }));
    var invalid_json = try decode(gpa, &.{ 0, 0, 0, 10, 1, 0, 0, 0, 1, 0, 0, 0, 1, '{' });
    defer invalid_json.deinit();
    try std.testing.expect(invalid_json.json.value == .null);
    var empty = try decode(gpa, &.{ 0, 0, 0, 9, 6, 0, 0, 0, 0, 0, 0, 0, 0 });
    defer empty.deinit();
    try std.testing.expectEqual(@as(usize, 0), empty.json.value.object.count());
    var decoder = Decoder.init(gpa);
    defer decoder.deinit();
    _ = try decoder.receive(&.{ 0, 0 });
    try std.testing.expectError(error.TruncatedFrame, decoder.end());
}
test "Pi-env sync survives arbitrary fragmentation wrong tokens and overlapping banner prefixes" {
    const bytes = "PPI-ENPI-ENV wrong\nPI-ENV ab12\nfollowing";
    for (0..bytes.len + 1) |split| {
        var sync = try Sync.init("ab12");
        var consumed = sync.receive(bytes[0..split]);
        if (!sync.ready) consumed += sync.receive(bytes[split..]);
        try std.testing.expect(sync.ready);
        try std.testing.expectEqualStrings("following", bytes[consumed..]);
    }
    try std.testing.expectError(error.InvalidSyncToken, Sync.init("ab\ncd"));
}
fn allocationCase(gpa: std.mem.Allocator) !void {
    const encoded = try encode(gpa, .request, 12, .{ .op = "write", .path = "/tmp/🚀" }, "binary\x00\xff");
    defer gpa.free(encoded);
    var decoder = Decoder.init(gpa);
    defer decoder.deinit();
    _ = try decoder.receive(encoded);
    var frame = (try decoder.next()).?;
    defer frame.deinit();
}
test "Pi-env frame allocation failures release encoder decoder JSON and payload" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, allocationCase, .{});
}
