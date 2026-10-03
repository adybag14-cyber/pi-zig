//! Offline MCP server used only by the native transport integration test.
const std = @import("std");

pub fn main(init: std.process.Init) !void {
    var read_buffer: [4096]u8 = undefined;
    var input = std.Io.File.stdin().readerStreaming(init.io, &read_buffer);
    var write_buffer: [4096]u8 = undefined;
    var output = std.Io.File.stdout().writerStreaming(init.io, &write_buffer);
    var page: usize = 0;
    while (true) {
        const record = input.interface.takeDelimiterInclusive('\n') catch |err| switch (err) {
            error.EndOfStream => return,
            else => return err,
        };
        const line = std.mem.trimEnd(u8, record, "\r\n");
        const parsed = try std.json.parseFromSlice(std.json.Value, init.gpa, line, .{});
        defer parsed.deinit();
        const object = parsed.value.object;
        const id = object.get("id") orelse continue;
        const method = object.get("method").?.string;
        try output.interface.writeAll("{\"jsonrpc\":\"2.0\",\"id\":");
        try std.json.Stringify.value(id, .{}, &output.interface);
        if (std.mem.eql(u8, method, "initialize")) {
            try output.interface.writeAll(",\"result\":{\"protocolVersion\":\"2025-11-25\",\"capabilities\":{\"tools\":{}},\"serverInfo\":{\"name\":\"native-fixture\",\"version\":\"1\"}}}\n");
            // Coalesced with the response, before the next request is received.
            try output.interface.writeAll("{\"jsonrpc\":\"2.0\",\"method\":\"notifications/tools/list_changed\"}\n");
        } else if (std.mem.eql(u8, method, "tools/list")) {
            if (page == 0) {
                try output.interface.writeAll(",\"result\":{\"tools\":[{\"name\":\"one\",\"inputSchema\":{}}],\"nextCursor\":\"next\"}}\n");
            } else {
                const cursor = object.get("params").?.object.get("cursor").?.string;
                if (!std.mem.eql(u8, cursor, "next")) return error.InvalidFixtureCursor;
                try output.interface.writeAll(",\"result\":{\"tools\":[{\"name\":\"two\",\"inputSchema\":{}}]}}\n");
                try output.interface.writeAll("{\"jsonrpc\":\"2.0\",\"method\":\"notifications/progress\",\"params\":{\"progress\":1}}\n");
            }
            page += 1;
        } else if (std.mem.eql(u8, method, "tools/call")) {
            try output.interface.writeAll(",\"result\":{\"content\":[{\"type\":\"text\",\"text\":\"real-pipe\"}]}}\n");
        } else return error.UnexpectedFixtureMethod;
        try output.interface.flush();
    }
}
