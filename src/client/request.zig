//! Typed client-command encoder for protocol-v1 JSON -> CBOR framing.
const std = @import("std");
const protocol = @import("../protocol/root.zig");
const msg = protocol.messages;

pub fn encodeRequestFrame(
    gpa: std.mem.Allocator,
    request_id: []const u8,
    command: msg.Command,
    max_frame_length: usize,
) ![]u8 {
    if (request_id.len == 0) return error.InvalidRequestId;
    var json: std.Io.Writer.Allocating = .init(gpa);
    defer json.deinit();
    const writer = &json.writer;
    try writer.writeAll("{\"type\":\"request\",\"id\":");
    try writeJson(writer, request_id);
    try writer.writeAll(",\"request\":{");
    try writeCommand(writer, command);
    try writer.writeAll("}}");
    const frame = try protocol.codec.encodeClientJsonFrame(gpa, json.written());
    errdefer gpa.free(frame);
    if (frame.len - 4 > max_frame_length) return protocol.framing.Error.FrameTooLarge;
    return frame;
}

fn writeCommand(writer: *std.Io.Writer, command: msg.Command) !void {
    try writer.writeAll("\"command\":");
    try writeJson(writer, @tagName(command));
    switch (command) {
        .list => {},
        .create => |create| {
            if (create.cwd) |cwd| {
                try writer.writeAll(",\"cwd\":");
                try writeJson(writer, cwd);
            }
            if (create.name) |name| {
                try writer.writeAll(",\"name\":");
                try writeJson(writer, name);
            }
            if (create.model) |model| {
                try writer.writeAll(",\"model\":");
                try writeModelRef(writer, model);
            }
            if (create.thinking_level) |level| {
                try writer.writeAll(",\"thinkingLevel\":");
                try writeJson(writer, @tagName(level));
            }
        },
        .attach => |value| try writeSessionId(writer, value.session_id),
        .detach => |value| try writeSessionId(writer, value.session_id),
        .prompt => |value| {
            try writeSessionId(writer, value.session_id);
            try writer.writeAll(",\"text\":");
            try writeJson(writer, value.text);
        },
        .steer => |value| {
            try writeSessionId(writer, value.session_id);
            try writer.writeAll(",\"text\":");
            try writeJson(writer, value.text);
        },
        .abort => |value| try writeSessionId(writer, value.session_id),
        .set_model => |value| {
            try writeSessionId(writer, value.session_id);
            try writer.writeAll(",\"model\":");
            try writeModelRef(writer, value.model);
        },
        .set_thinking => |value| {
            try writeSessionId(writer, value.session_id);
            try writer.writeAll(",\"thinkingLevel\":");
            try writeJson(writer, @tagName(value.thinking_level));
        },
    }
}

fn writeSessionId(writer: *std.Io.Writer, session_id: []const u8) !void {
    try writer.writeAll(",\"sessionId\":");
    try writeJson(writer, session_id);
}

fn writeModelRef(writer: *std.Io.Writer, model: msg.ModelRef) !void {
    try writer.writeAll("{\"provider\":");
    try writeJson(writer, model.provider);
    try writer.writeAll(",\"id\":");
    try writeJson(writer, model.id);
    try writer.writeByte('}');
}

fn writeJson(writer: *std.Io.Writer, value: []const u8) !void {
    try std.json.Stringify.value(value, .{}, writer);
}

fn expectRoundTrip(command: msg.Command) !void {
    const gpa = std.testing.allocator;
    const frame = try encodeRequestFrame(gpa, "request-1", command, protocol.framing.DEFAULT_MAX_FRAME_LENGTH);
    defer gpa.free(frame);
    var decoded = try protocol.codec.decodeClientFrame(gpa, frame);
    defer protocol.json.deinitClientMessage(gpa, &decoded);
    try std.testing.expect(decoded == .request);
    try std.testing.expectEqualStrings("request-1", decoded.request.id);
    try std.testing.expectEqual(@as(msg.CommandName, command), @as(msg.CommandName, decoded.request.request));
}

test "typed request encoder covers every protocol command" {
    try expectRoundTrip(.{ .list = {} });
    try expectRoundTrip(.{ .create = .{
        .cwd = "/tmp/a b",
        .name = "quoted \"name\"",
        .model = .{ .provider = "openai", .id = "gpt" },
        .thinking_level = .high,
    } });
    try expectRoundTrip(.{ .attach = .{ .session_id = "s" } });
    try expectRoundTrip(.{ .detach = .{ .session_id = "s" } });
    try expectRoundTrip(.{ .prompt = .{ .session_id = "s", .text = "line 1\nline 2" } });
    try expectRoundTrip(.{ .steer = .{ .session_id = "s", .text = "" } });
    try expectRoundTrip(.{ .abort = .{ .session_id = "s" } });
    try expectRoundTrip(.{ .set_model = .{ .session_id = "s", .model = .{ .provider = "p", .id = "m" } } });
    try expectRoundTrip(.{ .set_thinking = .{ .session_id = "s", .thinking_level = .xhigh } });
}

test "typed request encoder rejects empty ids and enforces configured frame limit" {
    const gpa = std.testing.allocator;
    try std.testing.expectError(error.InvalidRequestId, encodeRequestFrame(gpa, "", .{ .list = {} }, 1024));
    try std.testing.expectError(protocol.framing.Error.FrameTooLarge, encodeRequestFrame(
        gpa,
        "r",
        .{ .prompt = .{ .session_id = "s", .text = "012345678901234567890123456789" } },
        8,
    ));
}
