//! Native MCP test server. Its wire contract is exercised by real transports.
const std = @import("std");
const protocol = @import("protocol.zig");
fn emit(io: std.Io, gpa: std.mem.Allocator, value: protocol.Value) !void {
    const bytes = try protocol.json.stringify(gpa, value);
    defer gpa.free(bytes);
    try std.Io.File.stdout().writeStreamingAll(io, bytes);
    try std.Io.File.stdout().writeStreamingAll(io, "\n");
}
pub fn main(init: std.process.Init) !void {
    const args = try init.minimal.args.toSlice(init.arena.allocator());
    if (args.len > 1 and std.mem.eql(u8, args[1], "--stall")) {
        try init.io.sleep(.fromSeconds(3600), .awake);
        return;
    }
    var read_buffer: [8192]u8 = undefined;
    var input = std.Io.File.stdin().readerStreaming(init.io, &read_buffer);
    while (true) {
        const record = input.interface.takeDelimiterInclusive('\n') catch |cause| switch (cause) {
            error.EndOfStream => return,
            else => return cause,
        };
        const line = std.mem.trimEnd(u8, record, "\r\n");
        var message = try protocol.json.Owned.parse(init.gpa, line);
        defer message.deinit();
        const kind = try protocol.kind(message.value);
        const method = try protocol.text(message.value, "method");
        if (kind == .notification) {
            if (std.mem.eql(u8, method, "notifications/cancelled")) {
                var notice = try protocol.request(init.gpa, null, "notifications/message", protocol.json.get(message.value, "params"));
                defer notice.deinit();
                try emit(init.io, init.gpa, notice.value);
            }
            continue;
        }
        if (kind != .request) continue;
        const id = try protocol.field(message.value, "id");
        const params = protocol.json.get(message.value, "params");
        if (std.mem.eql(u8, method, "never")) continue;
        if (std.mem.eql(u8, method, "progress")) {
            const meta = try protocol.field(params.?, "_meta");
            const token = try protocol.field(meta, "progressToken");
            for (0..5) |number| {
                var data: protocol.Value = .{ .object = .empty };
                const a = message.arena.allocator();
                try data.object.put(a, "progressToken", token);
                try data.object.put(a, "progress", .{ .integer = @intCast(number) });
                var progress = try protocol.request(init.gpa, null, "notifications/progress", data);
                defer progress.deinit();
                try emit(init.io, init.gpa, progress.value);
                try init.io.sleep(.fromMilliseconds(25), .awake);
            }
        }
        const literal: []const u8 = if (std.mem.eql(u8, method, "initialize")) "{\"protocolVersion\":\"2025-11-25\",\"capabilities\":{\"tools\":{},\"resources\":{},\"prompts\":{}},\"serverInfo\":{\"name\":\"reference\",\"version\":\"1\"},\"instructions\":\"Native contract\"}" else if (std.mem.eql(u8, method, "tools/list")) if (params != null and protocol.json.get(params.?, "cursor") != null) "{\"tools\":[{\"name\":\"second\",\"inputSchema\":{}}],\"nextCursor\":null}" else "{\"tools\":[{\"name\":\"first\",\"inputSchema\":{\"type\":\"object\"}}],\"nextCursor\":\"next\"}" else if (std.mem.eql(u8, method, "resources/list")) "{\"resources\":[{\"uri\":\"file:///resource\"}]}" else if (std.mem.eql(u8, method, "resources/templates/list")) "{\"resourceTemplates\":[{\"uriTemplate\":\"file:///{name}\"}]}" else if (std.mem.eql(u8, method, "resources/read")) "{\"contents\":[{\"uri\":\"file:///resource\",\"text\":\"resource-text\"}]}" else if (std.mem.eql(u8, method, "tools/call")) "{\"structuredContent\":{\"ok\":true},\"isError\":false}" else if (std.mem.eql(u8, method, "prompts/list")) "{\"prompts\":[{\"name\":\"welcome\",\"arguments\":[{\"name\":\"name\",\"required\":true}]}]}" else if (std.mem.eql(u8, method, "prompts/get")) "{\"messages\":[{\"role\":\"user\",\"content\":{\"type\":\"text\",\"text\":\"welcome\"}}]}" else if (std.mem.eql(u8, method, "failure")) "{\"code\":-32042,\"message\":\"Original remote message\",\"data\":{\"detail\":7}}" else if (std.mem.eql(u8, method, "progress")) "{\"done\":true}" else "{}";
        var value = try protocol.json.Owned.parse(init.gpa, literal);
        defer value.deinit();
        var response = try protocol.response(init.gpa, id, value.value, std.mem.eql(u8, method, "failure"));
        defer response.deinit();
        try emit(init.io, init.gpa, response.value);
    }
}
