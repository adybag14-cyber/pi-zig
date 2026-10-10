//! MCP (Model Context Protocol) JSON-RPC client over stdio pipes.
//! Implements initialize, tools/list, tools/call for external MCP servers.
const std = @import("std");
const Io = std.Io;
const framing = @import("framing.zig");
const Adapter = @import("client_adapter.zig").Adapter;
pub const latest_protocol_version = "2025-11-25";
pub const supported_protocol_versions = [_][]const u8{ latest_protocol_version, "2025-06-18", "2025-03-26", "2024-11-05" };

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
    child: ?*std.process.Child = null,
    adapter: ?*Adapter = null,
    environ: ?*const std.process.Environ.Map = null,
    tools: std.ArrayList(McpTool) = .empty,
    /// Offline test inject: last written line (owned).
    last_write: []u8 = &.{},
    /// Offline test inject: canned read responses (not owned).
    inject_reads: []const []const u8 = &.{},
    inject_idx: usize = 0,
    input: framing.LineBuffer = .{},
    protocol_version: ?[]u8 = null,
    notification_count: usize = 0,
    unknown_response_count: usize = 0,
    request_timeout_ms: u32 = 30_000,

    pub fn deinit(self: *McpClient) void {
        for (self.tools.items) |*t| t.deinit(self.gpa);
        self.tools.deinit(self.gpa);
        if (self.last_write.len > 0) self.gpa.free(self.last_write);
        self.input.deinit(self.gpa);
        if (self.protocol_version) |version| self.gpa.free(version);
        if (self.adapter) |adapter| adapter.deinit();
        self.* = undefined;
    }

    /// Spawn MCP server with inherited environment unless an explicit map is supplied.
    pub fn connect(self: *McpClient, argv: []const []const u8) !void {
        if (self.adapter != null) return error.AlreadyConnected;
        const adapter = try Adapter.openStdio(self.gpa, self.io, argv, self.environ, self.request_timeout_ms);
        errdefer adapter.deinit();
        try self.adopt(adapter);
    }
    /// Explicit Streamable HTTP transport; argv strings are never guessed as URLs.
    pub fn connectHttp(self: *McpClient, url: []const u8) !void {
        if (self.adapter != null) return error.AlreadyConnected;
        const adapter = try Adapter.openHttp(self.gpa, self.io, url, self.request_timeout_ms);
        errdefer adapter.deinit();
        try self.adopt(adapter);
    }
    fn adopt(self: *McpClient, adapter: *Adapter) !void {
        const version = try self.gpa.dupe(u8, adapter.protocolVersion());
        if (self.protocol_version) |old| self.gpa.free(old);
        self.protocol_version = version;
        self.input.bytes.clearRetainingCapacity();
        self.next_id = 2;
        self.adapter = adapter;
        self.child = adapter.childPointer();
        self.refreshCounters();
    }
    fn refreshCounters(self: *McpClient) void {
        if (self.adapter) |adapter| {
            self.notification_count = adapter.notifications.load(.acquire);
            self.unknown_response_count = adapter.client.?.unknown_responses.load(.acquire);
        }
    }
    pub fn close(self: *McpClient) void {
        self.refreshCounters();
        if (self.adapter) |adapter| adapter.deinit();
        self.adapter = null;
        self.child = null;
    }

    fn initialize(self: *McpClient) !void {
        const init_req =
            \\{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-11-25","capabilities":{},"clientInfo":{"name":"pi-zig","version":"1.1.0"}}}
        ;
        const init_line = try self.exchange(init_req, 1);
        defer self.gpa.free(init_line);
        const parsed = try std.json.parseFromSlice(std.json.Value, self.gpa, init_line, .{});
        defer parsed.deinit();
        const result = parsed.value.object.get("result").?;
        if (result != .object) return error.InvalidMcpInitialize;
        const version = result.object.get("protocolVersion") orelse return error.InvalidMcpInitialize;
        const capabilities = result.object.get("capabilities") orelse return error.InvalidMcpInitialize;
        const info = result.object.get("serverInfo") orelse return error.InvalidMcpInitialize;
        if (version != .string or capabilities != .object or info != .object) return error.InvalidMcpInitialize;
        const name = info.object.get("name") orelse return error.InvalidMcpInitialize;
        const server_version = info.object.get("version") orelse return error.InvalidMcpInitialize;
        if (name != .string or server_version != .string) return error.InvalidMcpInitialize;
        if (result.object.get("instructions")) |instructions| if (instructions != .string) return error.InvalidMcpInitialize;
        var supported = false;
        for (supported_protocol_versions) |candidate| if (std.mem.eql(u8, version.string, candidate)) {
            supported = true;
            break;
        };
        if (!supported) return error.UnsupportedMcpProtocol;
        const owned_version = try self.gpa.dupe(u8, version.string);
        if (self.protocol_version) |old| self.gpa.free(old);
        self.protocol_version = owned_version;
        try self.writeLine(
            \\{"jsonrpc":"2.0","method":"notifications/initialized"}
        );
        self.next_id = 2;
    }

    pub fn listTools(self: *McpClient) !void {
        var arena: std.heap.ArenaAllocator = .init(self.gpa);
        defer arena.deinit();
        const allocator = arena.allocator();
        var cursors: std.StringHashMapUnmanaged(void) = .empty;
        var cursor: ?[]const u8 = null;
        // Stage the entire refresh; a later bad page must not replace good tools.
        var staged = McpClient{ .gpa = self.gpa, .io = self.io };
        defer staged.deinit();
        for (0..1000) |_| {
            if (self.next_id > 9_007_199_254_740_991) return error.McpRequestIdExhausted;
            const id = self.next_id;
            self.next_id += 1;
            var request: std.Io.Writer.Allocating = .init(allocator);
            request.writer.print("{{\"jsonrpc\":\"2.0\",\"id\":{d},\"method\":\"tools/list\"", .{id}) catch return error.OutOfMemory;
            if (cursor) |value| {
                request.writer.writeAll(",\"params\":{\"cursor\":") catch return error.OutOfMemory;
                std.json.Stringify.value(value, .{}, &request.writer) catch return error.OutOfMemory;
                request.writer.writeByte('}') catch return error.OutOfMemory;
            }
            request.writer.writeByte('}') catch return error.OutOfMemory;
            const line = try self.exchange(request.written(), id);
            defer self.gpa.free(line);
            try staged.parseToolsList(line);
            const parsed = try std.json.parseFromSlice(std.json.Value, allocator, line, .{ .allocate = .alloc_always });
            const result = parsed.value.object.get("result").?;
            const next = result.object.get("nextCursor") orelse std.json.Value.null;
            if (next == .null or (next == .string and next.string.len == 0)) {
                for (self.tools.items) |*tool| tool.deinit(self.gpa);
                self.tools.deinit(self.gpa);
                self.tools = staged.tools;
                staged.tools = .empty;
                return;
            }
            if (next != .string) return error.InvalidMcpCursor;
            if (cursors.contains(next.string)) return error.DuplicateMcpCursor;
            try cursors.put(allocator, next.string, {});
            cursor = next.string;
        }
        return error.TooManyMcpPages;
    }

    pub fn callTool(self: *McpClient, name: []const u8, args_json: []const u8) ![]u8 {
        if (self.next_id > 9_007_199_254_740_991) return error.McpRequestIdExhausted;
        const arguments = try std.json.parseFromSlice(std.json.Value, self.gpa, if (args_json.len > 0) args_json else "{}", .{});
        defer arguments.deinit();
        if (arguments.value != .object) return error.InvalidMcpArguments;
        const id = self.next_id;
        self.next_id += 1;
        var name_q: std.Io.Writer.Allocating = .init(self.gpa);
        defer name_q.deinit();
        std.json.Stringify.value(name, .{}, &name_q.writer) catch return error.OutOfMemory;
        const req = try std.fmt.allocPrint(self.gpa,
            \\{{"jsonrpc":"2.0","id":{d},"method":"tools/call","params":{{"name":{s},"arguments":{s}}}}}
        , .{
            id,
            name_q.written(),
            if (args_json.len > 0) args_json else "{}",
        });
        defer self.gpa.free(req);
        return try self.exchange(req, id); // caller frees
    }

    fn parseToolsList(self: *McpClient, line: []const u8) !void {
        var parsed = try std.json.parseFromSlice(std.json.Value, self.gpa, line, .{});
        defer parsed.deinit();
        if (parsed.value != .object) return error.InvalidMcpTools;
        const result = parsed.value.object.get("result") orelse return error.InvalidMcpTools;
        if (result != .object) return error.InvalidMcpTools;
        const tools = result.object.get("tools") orelse return error.InvalidMcpTools;
        if (tools != .array) return error.InvalidMcpTools;
        for (tools.array.items) |item| {
            if (item != .object) return error.InvalidMcpTools;
            const name = if (item.object.get("name")) |n| (if (n == .string) n.string else return error.InvalidMcpTools) else return error.InvalidMcpTools;
            const schema = item.object.get("inputSchema") orelse return error.InvalidMcpTools;
            if (schema != .object) return error.InvalidMcpTools;
            const desc = if (item.object.get("description")) |d| (if (d == .string) d.string else "") else "";
            var schema_aw: std.Io.Writer.Allocating = .init(self.gpa);
            defer schema_aw.deinit();
            if (item.object.get("inputSchema")) |s| {
                std.json.Stringify.value(s, .{}, &schema_aw.writer) catch return error.OutOfMemory;
            } else {
                schema_aw.writer.writeAll("{}") catch return error.OutOfMemory;
            }
            const owned_name = try self.gpa.dupe(u8, name);
            errdefer self.gpa.free(owned_name);
            const owned_description = try self.gpa.dupe(u8, desc);
            errdefer self.gpa.free(owned_description);
            const owned_schema = try schema_aw.toOwnedSlice();
            errdefer self.gpa.free(owned_schema);
            try self.tools.append(self.gpa, .{ .name = owned_name, .description = owned_description, .input_schema_json = owned_schema });
        }
    }

    fn writeLine(self: *McpClient, line: []const u8) !void {
        const owned = try self.gpa.dupe(u8, line);
        if (self.last_write.len > 0) self.gpa.free(self.last_write);
        self.last_write = owned;
    }

    fn exchange(self: *McpClient, request: []const u8, expected_id: u64) ![]u8 {
        if (self.adapter) |adapter| {
            defer self.refreshCounters();
            return adapter.exchange(request, expected_id, self.request_timeout_ms) catch |cause| {
                // Legacy sequential client treated a deadline as a terminal connection.
                if (cause == error.McpTimeout) self.close();
                return cause;
            };
        }
        try self.writeLine(request);
        return self.readResponse(expected_id);
    }

    fn readResponse(self: *McpClient, expected_id: u64) ![]u8 {
        while (true) {
            const line = try self.readLine();
            errdefer self.gpa.free(line);
            const parsed = try std.json.parseFromSlice(std.json.Value, self.gpa, line, .{});
            defer parsed.deinit();
            if (parsed.value != .object) return error.InvalidMcpMessage;
            const object = parsed.value.object;
            const version = object.get("jsonrpc") orelse return error.InvalidMcpMessage;
            if (version != .string or !std.mem.eql(u8, version.string, "2.0")) return error.InvalidMcpMessage;
            const id = object.get("id");
            if (object.get("method")) |method| {
                if (method != .string) return error.InvalidMcpMessage;
                if (id) |request_id| {
                    if (!validId(request_id)) return error.InvalidMcpMessage;
                    // Unsupported server requests must be answered, never mistaken
                    // for the response awaited by the synchronous caller.
                    var response: std.Io.Writer.Allocating = .init(self.gpa);
                    defer response.deinit();
                    try response.writer.writeAll("{\"jsonrpc\":\"2.0\",\"id\":");
                    try std.json.Stringify.value(request_id, .{}, &response.writer);
                    try response.writer.writeAll(",\"error\":{\"code\":-32601,\"message\":\"Method not found\"}}");
                    try self.writeLine(response.written());
                } else self.notification_count += 1;
                self.gpa.free(line);
                continue;
            }
            const response_id = id orelse return error.InvalidMcpMessage;
            if (!validId(response_id)) return error.InvalidMcpMessage;
            const result = object.get("result");
            const rpc_error = object.get("error");
            if (result != null) {
                if (rpc_error != null) return error.InvalidMcpMessage;
            } else {
                const failure = rpc_error orelse return error.InvalidMcpMessage;
                if (failure != .object) return error.InvalidMcpMessage;
                const code = failure.object.get("code") orelse return error.InvalidMcpMessage;
                const message = failure.object.get("message") orelse return error.InvalidMcpMessage;
                if ((code != .integer and code != .float) or message != .string) return error.InvalidMcpMessage;
            }
            const matches = switch (response_id) {
                .integer => |value| value >= 0 and @as(u64, @intCast(value)) == expected_id,
                .float => |value| value == @as(f64, @floatFromInt(expected_id)),
                else => false,
            };
            if (!matches) {
                self.unknown_response_count += 1;
                self.gpa.free(line);
                continue;
            }
            if (rpc_error != null) return error.McpRemoteError;
            return line;
        }
    }

    fn readLine(self: *McpClient) ![]u8 {
        // Injected responses for unit tests / offline
        if (self.inject_idx < self.inject_reads.len) {
            const line = self.inject_reads[self.inject_idx];
            self.inject_idx += 1;
            return try self.gpa.dupe(u8, line);
        }
        try self.input.finish();
        return error.McpConnectionClosed;
    }
};

/// Pure parser tests (no process).
pub fn parseToolsListJson(gpa: std.mem.Allocator, line: []const u8) ![]McpTool {
    var client = McpClient{ .gpa = gpa, .io = undefined };
    defer client.deinit();
    try client.parseToolsList(line);
    return try client.tools.toOwnedSlice(gpa);
}

fn validId(value: std.json.Value) bool {
    return switch (value) {
        .string, .integer => true,
        .float => |number| std.math.isFinite(number),
        else => false,
    };
}

/// Validate a method against the real MCP method vocabulary used by this client.
pub fn isKnownMcpMethod(method: []const u8) bool {
    return @import("methods.zig").isKnown(method);
}

/// Build a tools/list request.
pub fn buildToolsListRequest(gpa: std.mem.Allocator, id: u64) ![]u8 {
    if (!isKnownMcpMethod("tools/list")) return error.UnknownMethod;
    return try std.fmt.allocPrint(gpa, "{{\"jsonrpc\":\"2.0\",\"id\":{d},\"method\":\"tools/list\"}}", .{id});
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

test "MCP method registry rejects synthetic methods" {
    try std.testing.expect(isKnownMcpMethod("tools/list"));
    try std.testing.expect(isKnownMcpMethod("initialize"));
    try std.testing.expect(!isKnownMcpMethod("ext/method_14_0"));
    const gpa = std.testing.allocator;
    const req = try buildToolsListRequest(gpa, 7);
    defer gpa.free(req);
    try std.testing.expect(std.mem.indexOf(u8, req, "tools/list") != null);
}

test "MCP correlates responses through notifications requests and unknown IDs" {
    const responses = [_][]const u8{
        "{\"jsonrpc\":\"2.0\",\"method\":\"notifications/progress\",\"params\":{\"progress\":1}}",
        "{\"jsonrpc\":\"2.0\",\"id\":\"server-request\",\"method\":\"unsupported\"}",
        "{\"jsonrpc\":\"2.0\",\"id\":\"7\",\"result\":{}}",
        "{\"jsonrpc\":\"2.0\",\"id\":7,\"result\":{\"marker\":42}}",
    };
    var client = McpClient{ .gpa = std.testing.allocator, .io = std.testing.io, .inject_reads = &responses };
    defer client.deinit();
    const response = try client.readResponse(7);
    defer client.gpa.free(response);
    try std.testing.expectEqualStrings(responses[3], response);
    try std.testing.expectEqual(@as(usize, 1), client.notification_count);
    try std.testing.expectEqual(@as(usize, 1), client.unknown_response_count);
    try std.testing.expect(std.mem.indexOf(u8, client.last_write, "-32601") != null);
    try std.testing.expect(std.mem.indexOf(u8, client.last_write, "server-request") != null);
}

test "MCP errors malformed envelopes and EOF do not fabricate successful responses" {
    const responses = [_][]const u8{
        "{\"jsonrpc\":\"2.0\",\"id\":1,\"result\":{},\"error\":{\"code\":-1,\"message\":\"bad\"}}",
        "{\"jsonrpc\":\"2.0\",\"id\":1,\"error\":{\"code\":-1,\"message\":\"bad\"}}",
    };
    var client = McpClient{ .gpa = std.testing.allocator, .io = std.testing.io, .inject_reads = &responses };
    defer client.deinit();
    try std.testing.expectError(error.InvalidMcpMessage, client.readResponse(1));
    try std.testing.expectError(error.McpRemoteError, client.readResponse(1));
    try std.testing.expectError(error.McpConnectionClosed, client.readResponse(1));
}

test "MCP tools refresh follows escaped cursors and replaces rather than duplicates" {
    const responses = [_][]const u8{
        "{\"jsonrpc\":\"2.0\",\"id\":1,\"result\":{\"tools\":[{\"name\":\"first\",\"inputSchema\":{}}],\"nextCursor\":\"a\\\"b\"}}",
        "{\"jsonrpc\":\"2.0\",\"id\":2,\"result\":{\"tools\":[{\"name\":\"second\",\"inputSchema\":{}}],\"nextCursor\":null}}",
        "{\"jsonrpc\":\"2.0\",\"id\":3,\"result\":{\"tools\":[{\"name\":\"new\",\"inputSchema\":{}}],\"nextCursor\":\"\"}}",
    };
    var client = McpClient{ .gpa = std.testing.allocator, .io = std.testing.io, .inject_reads = &responses };
    defer client.deinit();
    try client.listTools();
    try std.testing.expectEqual(@as(usize, 2), client.tools.items.len);
    try std.testing.expect(std.mem.indexOf(u8, client.last_write, "a\\\"b") != null);
    try client.listTools();
    try std.testing.expectEqual(@as(usize, 1), client.tools.items.len);
    try std.testing.expectEqualStrings("new", client.tools.items[0].name);
}

test "MCP pagination failures preserve previous tools and release staged allocations" {
    const responses = [_][]const u8{
        "{\"jsonrpc\":\"2.0\",\"id\":1,\"result\":{\"tools\":[{\"name\":\"first\",\"inputSchema\":{}}],\"nextCursor\":\"again\"}}",
        "{\"jsonrpc\":\"2.0\",\"id\":2,\"result\":{\"tools\":[],\"nextCursor\":\"again\"}}",
        "{\"jsonrpc\":\"2.0\",\"id\":3,\"result\":{\"tools\":[{\"name\":\"bad\",\"inputSchema\":[]}]}}",
    };
    var client = McpClient{ .gpa = std.testing.allocator, .io = std.testing.io, .inject_reads = &responses };
    defer client.deinit();
    try client.parseToolsList("{\"result\":{\"tools\":[{\"name\":\"existing\",\"inputSchema\":{}}]}}");
    try std.testing.expectError(error.DuplicateMcpCursor, client.listTools());
    try std.testing.expectError(error.InvalidMcpTools, client.listTools());
    try std.testing.expectEqual(@as(usize, 1), client.tools.items.len);
    try std.testing.expectEqualStrings("existing", client.tools.items[0].name);
}

test "MCP initialize negotiates known older protocols and rejects unknown versions" {
    const responses = [_][]const u8{
        "{\"jsonrpc\":\"2.0\",\"id\":1,\"result\":{\"protocolVersion\":\"2024-11-05\",\"capabilities\":{},\"serverInfo\":{\"name\":\"fixture\",\"version\":\"1\"}}}",
        "{\"jsonrpc\":\"2.0\",\"id\":1,\"result\":{\"protocolVersion\":\"2099-01-01\",\"capabilities\":{},\"serverInfo\":{\"name\":\"fixture\",\"version\":\"1\"}}}",
    };
    var client = McpClient{ .gpa = std.testing.allocator, .io = std.testing.io, .inject_reads = &responses };
    defer client.deinit();
    try client.initialize();
    try std.testing.expectEqualStrings("2024-11-05", client.protocol_version.?);
    try std.testing.expectEqual(@as(u64, 2), client.next_id);
    try std.testing.expectError(error.UnsupportedMcpProtocol, client.initialize());
    try std.testing.expectEqualStrings("2024-11-05", client.protocol_version.?);
    try std.testing.expectError(error.InvalidMcpArguments, client.callTool("fixture", "[]"));
}
