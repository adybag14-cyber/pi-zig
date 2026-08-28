//! Pi protocol codec: schema validation + CBOR + four-byte framing.
const std = @import("std");
const framing = @import("framing.zig");
const cbor = @import("cbor.zig");
const json_protocol = @import("json.zig");
const messages = @import("messages.zig");
const server_json = @import("server_json.zig");

pub const DEFAULT_MAX_FRAME_LENGTH = framing.DEFAULT_MAX_FRAME_LENGTH;

/// Validate a JSON representation of a client message, encode it using the
/// same CBOR subset as upstream, then prefix it with the four-byte frame size.
pub fn encodeClientJsonFrame(gpa: std.mem.Allocator, json_text: []const u8) ![]u8 {
    var validated = try json_protocol.parseClientMessage(gpa, json_text);
    defer json_protocol.deinitClientMessage(gpa, &validated);

    var parsed = try std.json.parseFromSlice(std.json.Value, gpa, json_text, .{});
    defer parsed.deinit();
    const payload = try cbor.encode(gpa, parsed.value, .{ .max_byte_length = DEFAULT_MAX_FRAME_LENGTH });
    defer gpa.free(payload);
    return try framing.encodeFrame(gpa, payload);
}

/// Encode any protocol-shaped JSON object to a framed CBOR message. This is
/// used by the server side after it has constructed a validated response.
pub fn encodeJsonFrame(gpa: std.mem.Allocator, json_text: []const u8) ![]u8 {
    var parsed = try std.json.parseFromSlice(std.json.Value, gpa, json_text, .{});
    defer parsed.deinit();
    const payload = try cbor.encode(gpa, parsed.value, .{ .max_byte_length = DEFAULT_MAX_FRAME_LENGTH });
    defer gpa.free(payload);
    return try framing.encodeFrame(gpa, payload);
}

/// Decode one complete framed client message and validate it against the real
/// Pi command schema. The returned message owns its strings.
pub fn decodeClientFrame(gpa: std.mem.Allocator, frame: []const u8) !messages.ClientMessage {
    try framing.assertCompleteFrame(frame, DEFAULT_MAX_FRAME_LENGTH);
    const payload = frame[4..];
    const value = try cbor.decode(gpa, payload, .{ .max_byte_length = DEFAULT_MAX_FRAME_LENGTH });
    defer cbor.deinitValue(gpa, value);

    var out: std.Io.Writer.Allocating = .init(gpa);
    defer out.deinit();
    try std.json.Stringify.value(value, .{}, &out.writer);
    return try json_protocol.parseClientMessage(gpa, out.written());
}

/// Decode and validate one complete framed server message. Nested strings,
/// snapshots and JSON values are owned by the returned arena.
pub fn decodeServerFrame(gpa: std.mem.Allocator, frame: []const u8) !server_json.ParsedServerMessage {
    const json_text = try decodeFrameToJson(gpa, frame);
    defer gpa.free(json_text);
    return try server_json.parseServerMessage(gpa, json_text);
}

/// Decode one raw CBOR frame payload to JSON. Incremental transports already
/// remove the four-byte frame prefix before delivering payloads.
pub fn decodePayloadToJson(gpa: std.mem.Allocator, payload: []const u8) ![]u8 {
    const value = try cbor.decode(gpa, payload, .{ .max_byte_length = DEFAULT_MAX_FRAME_LENGTH });
    defer cbor.deinitValue(gpa, value);
    var out: std.Io.Writer.Allocating = .init(gpa);
    errdefer out.deinit();
    try std.json.Stringify.value(value, .{}, &out.writer);
    return try out.toOwnedSlice();
}

pub fn decodeServerPayload(gpa: std.mem.Allocator, payload: []const u8) !server_json.ParsedServerMessage {
    const json_text = try decodePayloadToJson(gpa, payload);
    defer gpa.free(json_text);
    return try server_json.parseServerMessage(gpa, json_text);
}

/// Decode one complete frame to JSON for diagnostics/interoperability tests.
pub fn decodeFrameToJson(gpa: std.mem.Allocator, frame: []const u8) ![]u8 {
    try framing.assertCompleteFrame(frame, DEFAULT_MAX_FRAME_LENGTH);
    const value = try cbor.decode(gpa, frame[4..], .{ .max_byte_length = DEFAULT_MAX_FRAME_LENGTH });
    defer cbor.deinitValue(gpa, value);
    var out: std.Io.Writer.Allocating = .init(gpa);
    errdefer out.deinit();
    try std.json.Stringify.value(value, .{}, &out.writer);
    return try out.toOwnedSlice();
}

test "client hello CBOR frame roundtrip" {
    const gpa = std.testing.allocator;
    const frame = try encodeClientJsonFrame(gpa, "{\"type\":\"hello\",\"version\":1}");
    defer gpa.free(frame);
    var decoded = try decodeClientFrame(gpa, frame);
    defer json_protocol.deinitClientMessage(gpa, &decoded);
    try std.testing.expect(decoded == .hello);
    try std.testing.expectEqual(@as(u32, 1), decoded.hello.version);
}

test "prompt frame roundtrip" {
    const gpa = std.testing.allocator;
    const input = "{\"type\":\"request\",\"id\":\"r1\",\"request\":{\"command\":\"prompt\",\"sessionId\":\"s1\",\"text\":\"hello\"}}";
    const frame = try encodeClientJsonFrame(gpa, input);
    defer gpa.free(frame);
    var decoded = try decodeClientFrame(gpa, frame);
    defer json_protocol.deinitClientMessage(gpa, &decoded);
    try std.testing.expect(decoded == .request);
    try std.testing.expect(decoded.request.request == .prompt);
    try std.testing.expectEqualStrings("hello", decoded.request.request.prompt.text);
}
