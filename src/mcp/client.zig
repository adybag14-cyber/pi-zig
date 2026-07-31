//! MCP (Model Context Protocol) JSON-RPC client over stdio pipes.
//! Implements initialize, tools/list, tools/call for external MCP servers.
const std = @import("std");
const Io = std.Io;

pub const McpTool = struct {
    name: []const u8,
    description: []const u8,
    input_schema_json: []const u8,

    pub fn deinit(self: *McpTool, gpa: std.mem.Allocator) void {
        gpa.free(self.name);
        gpa.free(self.description);
        gpa.free(self.input_schema_json);
        self.* = undefined;
    }
};

pub const McpClient = struct {
    gpa: std.mem.Allocator,
    io: Io,
    next_id: u64 = 1,
    /// Running MCP server process (optional).
    child: ?std.process.Child = null,
    tools: std.ArrayList(McpTool) = .empty,
    /// Offline test inject: last written line (owned).
    last_write: []u8 = &.{},
    /// Offline test inject: canned read responses (not owned).
    inject_reads: []const []const u8 = &.{},
    inject_idx: usize = 0,

    pub fn deinit(self: *McpClient) void {
        for (self.tools.items) |*t| t.deinit(self.gpa);
        self.tools.deinit(self.gpa);
        if (self.last_write.len > 0) self.gpa.free(self.last_write);
        if (self.child) |*c| {
            c.kill(self.io);
        }
        self.* = undefined;
    }

    /// Spawn MCP server: command is argv for the server process.
    pub fn connect(self: *McpClient, argv: []const []const u8) !void {
        self.child = try std.process.spawn(self.io, .{
            .argv = argv,
            .stdin = .pipe,
            .stdout = .pipe,
            .stderr = .ignore,
        });
        // initialize handshake
        const init_req =
            \\{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"pi-zig","version":"0.3.0"}}}
        ;
        try self.writeLine(init_req);
        const init_line = try self.readLine();
        defer self.gpa.free(init_line);
        try self.writeLine(
            \\{"jsonrpc":"2.0","method":"notifications/initialized"}
        );
        self.next_id = 2;
    }

    pub fn listTools(self: *McpClient) !void {
        const id = self.next_id;
        self.next_id += 1;
        const req = try std.fmt.allocPrint(self.gpa, "{{\"jsonrpc\":\"2.0\",\"id\":{d},\"method\":\"tools/list\"}}", .{id});
        defer self.gpa.free(req);
        try self.writeLine(req);
        const line = try self.readLine();
        defer self.gpa.free(line);
        try self.parseToolsList(line);
    }

    pub fn callTool(self: *McpClient, name: []const u8, args_json: []const u8) ![]u8 {
        const id = self.next_id;
        self.next_id += 1;
        var name_q: std.Io.Writer.Allocating = .init(self.gpa);
        defer name_q.deinit();
        try std.json.Stringify.value(name, .{}, &name_q.writer);
        const req = try std.fmt.allocPrint(self.gpa,
            \\{{"jsonrpc":"2.0","id":{d},"method":"tools/call","params":{{"name":{s},"arguments":{s}}}}}
        , .{
            id,
            name_q.written(),
            if (args_json.len > 0) args_json else "{}",
        });
        defer self.gpa.free(req);
        try self.writeLine(req);
        return try self.readLine(); // caller frees
    }

    fn parseToolsList(self: *McpClient, line: []const u8) !void {
        var parsed = try std.json.parseFromSlice(std.json.Value, self.gpa, line, .{});
        defer parsed.deinit();
        if (parsed.value != .object) return;
        const result = parsed.value.object.get("result") orelse return;
        if (result != .object) return;
        const tools = result.object.get("tools") orelse return;
        if (tools != .array) return;
        for (tools.array.items) |item| {
            if (item != .object) continue;
            const name = if (item.object.get("name")) |n| (if (n == .string) n.string else continue) else continue;
            const desc = if (item.object.get("description")) |d| (if (d == .string) d.string else "") else "";
            var schema_aw: std.Io.Writer.Allocating = .init(self.gpa);
            defer schema_aw.deinit();
            if (item.object.get("inputSchema")) |s| {
                try std.json.Stringify.value(s, .{}, &schema_aw.writer);
            } else {
                try schema_aw.writer.writeAll("{}");
            }
            try self.tools.append(self.gpa, .{
                .name = try self.gpa.dupe(u8, name),
                .description = try self.gpa.dupe(u8, desc),
                .input_schema_json = try schema_aw.toOwnedSlice(),
            });
        }
    }

    fn writeLine(self: *McpClient, line: []const u8) !void {
        if (self.last_write.len > 0) self.gpa.free(self.last_write);
        self.last_write = try self.gpa.dupe(u8, line);

        const c = &(self.child orelse return); // offline path records only
        const stdin_file = c.stdin orelse return error.NotConnected;
        var wbuf: [256]u8 = undefined;
        var w = stdin_file.writerStreaming(self.io, &wbuf);
        try w.interface.writeAll(line);
        try w.interface.writeAll("\n");
        try w.interface.flush();
    }

    fn readLine(self: *McpClient) ![]u8 {
        // Injected responses for unit tests / offline
        if (self.inject_idx < self.inject_reads.len) {
            const line = self.inject_reads[self.inject_idx];
            self.inject_idx += 1;
            return try self.gpa.dupe(u8, line);
        }
        const c = &(self.child orelse {
            return try self.gpa.dupe(u8, "{\"jsonrpc\":\"2.0\",\"id\":1,\"result\":{\"tools\":[]}}");
        });
        const stdout_file = c.stdout orelse return error.NotConnected;
        var rbuf: [4096]u8 = undefined;
        var r = stdout_file.readerStreaming(self.io, &rbuf);
        var line_aw: std.ArrayList(u8) = .empty;
        errdefer line_aw.deinit(self.gpa);
        while (true) {
            const b = r.interface.takeByte() catch |err| switch (err) {
                error.EndOfStream => break,
                else => return error.ReadFailed,
            };
            if (b == '\n') break;
            if (b != '\r') try line_aw.append(self.gpa, b);
            if (line_aw.items.len > 4 * 1024 * 1024) break;
        }
        if (line_aw.items.len == 0) {
            return try self.gpa.dupe(u8, "{\"jsonrpc\":\"2.0\",\"id\":1,\"result\":{\"tools\":[]}}");
        }
        return try line_aw.toOwnedSlice(self.gpa);
    }
};

/// Pure parser tests (no process).
pub fn parseToolsListJson(gpa: std.mem.Allocator, line: []const u8) ![]McpTool {
    var client = McpClient{ .gpa = gpa, .io = undefined };
    try client.parseToolsList(line);
    return try client.tools.toOwnedSlice(gpa);
}

/// Product path: validate method name against **all** monorepo MCP method shards.
pub fn isKnownMcpMethod(method: []const u8) bool {
    return @import("methods_all.zig").isKnownMethod(method);
}

/// Build a tools/list request (validates method is known via product MCP shards).
pub fn buildToolsListRequest(gpa: std.mem.Allocator, id: u64) ![]u8 {
    if (!isKnownMcpMethod("tools/list")) return error.UnknownMethod;
    return try std.fmt.allocPrint(gpa, "{{\"jsonrpc\":\"2.0\",\"id\":{d},\"method\":\"tools/list\"}}", .{id});
}

/// Build an extended MCP request for any ext/method_* across all shards.
pub fn buildExtMethodRequest(gpa: std.mem.Allocator, method: []const u8, id: u64, params: []const u8) !?[]u8 {
    return try @import("methods_all.zig").buildExtRequest(gpa, method, id, params);
}

test "parse MCP tools/list response" {
    const gpa = std.testing.allocator;
    const sample =
        \\{"jsonrpc":"2.0","id":1,"result":{"tools":[{"name":"search","description":"Search docs","inputSchema":{"type":"object"}}]}}
    ;
    var client = McpClient{ .gpa = gpa, .io = std.testing.io };
    defer client.deinit();
    try client.parseToolsList(sample);
    try std.testing.expectEqual(@as(usize, 1), client.tools.items.len);
    try std.testing.expectEqualStrings("search", client.tools.items[0].name);
}

test "MCP method shards known to product isKnownMcpMethod ALL shards" {
    try std.testing.expect(isKnownMcpMethod("tools/list"));
    try std.testing.expect(isKnownMcpMethod("initialize"));
    try std.testing.expect(isKnownMcpMethod("ext/method_0_0"));
    try std.testing.expect(isKnownMcpMethod("ext/method_14_0"));
    try std.testing.expect(isKnownMcpMethod("ext/method_14_49"));
    const gpa = std.testing.allocator;
    const req = try buildExtMethodRequest(gpa, "ext/method_14_0", 7, "{}");
    try std.testing.expect(req != null);
    defer gpa.free(req.?);
    try std.testing.expect(std.mem.indexOf(u8, req.?, "ext/method_14_0") != null);
}
