//! Real native MCP server for configured direct-tools ownership and agent gates.
const std = @import("std");
const protocol = @import("protocol.zig");
const json = protocol.json;
const Value = protocol.Value;
fn emit(io: std.Io, gpa: std.mem.Allocator, value: Value) !void {
    const bytes = try json.stringify(gpa, value);
    defer gpa.free(bytes);
    try std.Io.File.stdout().writeStreamingAll(io, bytes);
    try std.Io.File.stdout().writeStreamingAll(io, "\n");
}
pub fn main(init: std.process.Init) !void {
    const args = try init.minimal.args.toSlice(init.arena.allocator());
    const resource_mode = args.len > 1 and (std.mem.eql(u8, args[1], "--resources") or std.mem.eql(u8, args[1], "--resources-no-templates"));
    const no_templates = args.len > 1 and std.mem.eql(u8, args[1], "--resources-no-templates");
    if (args.len > 1 and std.mem.eql(u8, args[1], "--stall")) {
        try init.io.sleep(.fromSeconds(3600), .awake);
        return;
    }
    var buffer: [8192]u8 = undefined;
    var reader = std.Io.File.stdin().readerStreaming(init.io, &buffer);
    while (true) {
        const line = reader.interface.takeDelimiterInclusive('\n') catch |cause| switch (cause) {
            error.EndOfStream => return,
            else => return cause,
        };
        var request = try json.Owned.parse(init.gpa, std.mem.trimEnd(u8, line, "\r\n"));
        defer request.deinit();
        if (try protocol.kind(request.value) != .request) continue;
        const method = try protocol.text(request.value, "method");
        const id = try protocol.field(request.value, "id");
        const a = request.arena.allocator();
        var result: Value = undefined;
        if (std.mem.eql(u8, method, "initialize")) {
            var value = try json.Owned.parse(init.gpa, if (resource_mode) "{\"protocolVersion\":\"2025-11-25\",\"capabilities\":{\"resources\":{}},\"serverInfo\":{\"name\":\"resources\",\"version\":\"1\"}}" else "{\"protocolVersion\":\"2025-11-25\",\"capabilities\":{\"tools\":{}},\"serverInfo\":{\"name\":\"configured\",\"version\":\"1\"}}");
            defer value.deinit();
            result = try json.clone(a, value.value);
        } else if (std.mem.eql(u8, method, "resources/templates/list") and no_templates) {
            var remote = try json.Owned.parse(init.gpa, "{\"code\":-32601,\"message\":\"Templates are not implemented\"}");
            defer remote.deinit();
            var response = try protocol.response(init.gpa, id, remote.value, true);
            defer response.deinit();
            try emit(init.io, init.gpa, response.value);
            continue;
        } else if (std.mem.eql(u8, method, "resources/list")) {
            const params = json.get(request.value, "params") orelse Value{ .object = .empty };
            const next = json.get(params, "cursor") != null;
            var value = try json.Owned.parse(init.gpa, if (next) "{\"resources\":[{\"uri\":\"file:///second\"}]}" else "{\"resources\":[{\"uri\":\"file:///first\",\"name\":\"First\",\"icons\":[{}],\"_meta\":{\"private\":true}},{\"uri\":\"ui://app\",\"name\":\"App\"}],\"nextCursor\":\"second\"}");
            defer value.deinit();
            result = try json.clone(a, value.value);
        } else if (std.mem.eql(u8, method, "resources/templates/list")) {
            var value = try json.Owned.parse(init.gpa, "{\"resourceTemplates\":[{\"uriTemplate\":\"file:///{name}\",\"name\":\"Template\"},{\"uriTemplate\":\"ui://{name}\",\"name\":\"App\"}]}");
            defer value.deinit();
            result = try json.clone(a, value.value);
        } else if (std.mem.eql(u8, method, "resources/read")) {
            const params = try protocol.field(request.value, "params");
            const uri = try protocol.text(params, "uri");
            if (std.mem.eql(u8, uri, "slow")) continue;
            if (std.mem.eql(u8, uri, "fail")) {
                var remote = try json.Owned.parse(init.gpa, "{\"code\":-32042,\"message\":\"Original resource failure\"}");
                defer remote.deinit();
                var response = try protocol.response(init.gpa, id, remote.value, true);
                defer response.deinit();
                try emit(init.io, init.gpa, response.value);
                continue;
            }
            var item: Value = .{ .object = .empty };
            try item.object.put(a, "uri", .{ .string = uri });
            try item.object.put(a, "text", .{ .string = "Native resource contents" });
            var contents: Value = .{ .array = .init(a) };
            try contents.array.append(item);
            result = .{ .object = .empty };
            try result.object.put(a, "contents", contents);
        } else if (std.mem.eql(u8, method, "tools/list")) {
            var value = try json.Owned.parse(init.gpa, "{\"tools\":[{\"name\":\"double\",\"description\":\"Double a value\",\"inputSchema\":{\"type\":\"object\",\"properties\":{\"value\":{\"type\":\"number\"}},\"required\":[\"value\"],\"additionalProperties\":false}},{\"name\":\"hidden\",\"inputSchema\":{}},{\"name\":\"progress\",\"inputSchema\":{}},{\"name\":\"error\",\"inputSchema\":{}},{\"name\":\"slow\",\"inputSchema\":{}},{\"name\":\"remote\",\"inputSchema\":{}}]}");
            defer value.deinit();
            result = try json.clone(a, value.value);
        } else if (std.mem.eql(u8, method, "tools/call")) {
            const params = try protocol.field(request.value, "params");
            const name = try protocol.text(params, "name");
            var contents: Value = .{ .array = .init(a) };
            var text: []const u8 = "ok";
            var failure = false;
            if (std.mem.eql(u8, name, "remote")) {
                var remote = try json.Owned.parse(init.gpa, "{\"code\":-32042,\"message\":\"Original remote message\",\"data\":{\"detail\":7}}");
                defer remote.deinit();
                var response = try protocol.response(init.gpa, id, remote.value, true);
                defer response.deinit();
                try emit(init.io, init.gpa, response.value);
                continue;
            }
            if (std.mem.eql(u8, name, "double")) {
                const arguments = try protocol.field(params, "arguments");
                const number = try json.asNumber(try protocol.field(arguments, "value"));
                text = try std.fmt.allocPrint(a, "{d}", .{number * 2});
            } else if (std.mem.eql(u8, name, "error")) {
                text = "";
                failure = true;
            } else if (std.mem.eql(u8, name, "progress") or std.mem.eql(u8, name, "slow")) {
                const meta = try protocol.field(params, "_meta");
                var update: Value = .{ .object = .empty };
                try update.object.put(a, "progressToken", try protocol.field(meta, "progressToken"));
                try update.object.put(a, "progress", .{ .integer = 1 });
                try update.object.put(a, "total", .{ .integer = 2 });
                var notice = try protocol.request(init.gpa, null, "notifications/progress", update);
                defer notice.deinit();
                try emit(init.io, init.gpa, notice.value);
                if (std.mem.eql(u8, name, "slow")) continue;
            }
            var block: Value = .{ .object = .empty };
            try block.object.put(a, "type", .{ .string = "text" });
            try block.object.put(a, "text", .{ .string = text });
            try contents.array.append(block);
            result = .{ .object = .empty };
            try result.object.put(a, "content", contents);
            if (failure) try result.object.put(a, "isError", .{ .bool = true });
        } else result = .{ .object = .empty };
        var response = try protocol.response(init.gpa, id, result, false);
        defer response.deinit();
        try emit(init.io, init.gpa, response.value);
    }
}
