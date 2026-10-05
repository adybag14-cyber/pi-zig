//! Actual process and loopback gates for the legacy facade's native ownership adapter.
const std = @import("std");
const builtin = @import("builtin");
const client_mod = @import("mcp/client.zig");
const fixture = @import("ai/http_fixture.zig");
const gpa = std.testing.allocator;
const io = std.testing.io;
const handshake = "{\"jsonrpc\":\"2.0\",\"id\":1,\"result\":{\"protocolVersion\":\"2025-11-25\",\"capabilities\":{\"tools\":{}},\"serverInfo\":{\"name\":\"adapter\",\"version\":\"1\"}}}";
const session_header: []const std.http.Header = &.{.{ .name = "mcp-session-id", .value = "adapter-session" }};
fn executable(name: []const u8) ![]u8 {
    var env = try std.testing.environ.createMap(gpa);
    defer env.deinit();
    return gpa.dupe(u8, env.get(name) orelse return error.MissingAdapterFixture);
}
fn expectRun(argv: []const []const u8, env: ?*const std.process.Environ.Map, code: u8, output: []const u8) !void {
    const result = try std.process.run(gpa, io, .{
        .argv = argv,
        .environ_map = env,
        .stdout_limit = .limited(65536),
        .stderr_limit = .limited(65536),
        .timeout = .{ .duration = .{ .raw = .fromSeconds(15), .clock = .awake } },
    });
    defer gpa.free(result.stdout);
    defer gpa.free(result.stderr);
    if (result.term != .exited or result.term.exited != code) std.debug.print("adapter subprocess {any}: stdout={s}; stderr={s}\n", .{ result.term, result.stdout, result.stderr });
    try std.testing.expect(result.term == .exited and result.term.exited == code);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, output) != null);
}
test "mcp.adapter actual inherited PATH bare command and explicit PATH precedence" {
    const program = try executable("PI_MCP_ADAPTER_SERVER");
    defer gpa.free(program);
    const probe = try executable("PI_MCP_ADAPTER_PROBE");
    defer gpa.free(probe);
    var environment: std.process.Environ.Map = .init(gpa);
    defer environment.deinit();
    try environment.put("PATH", std.fs.path.dirname(program).?);
    const bare = std.fs.path.stem(program);
    // The probe's own environment is replaced, but connect(argv) receives no map.
    try expectRun(&.{ probe, bare }, &environment, 0, "inherited PATH: 2 tools");
    var client = client_mod.McpClient{ .gpa = gpa, .io = io, .environ = &environment };
    defer client.deinit();
    try client.connect(&.{bare});
    try client.listTools();
    try std.testing.expectEqual(@as(usize, 2), client.tools.items.len);
    client.close();
    client.close();
    try std.testing.expect(client.child == null);
    try environment.put("PATH", "");
    var empty = client_mod.McpClient{ .gpa = gpa, .io = io, .environ = &environment };
    defer empty.deinit();
    try std.testing.expectError(error.ProgramNotFound, empty.connect(&.{bare}));
    try std.testing.expect(empty.child == null and empty.adapter == null);
}
test "mcp.adapter exact child identity external wait and repeated close without double wait" {
    const program = try executable("PI_MCP_ADAPTER_SERVER");
    defer gpa.free(program);
    var client = client_mod.McpClient{ .gpa = gpa, .io = io };
    defer client.deinit();
    try client.connect(&.{program});
    const captured = try std.json.parseFromSlice(std.json.Value, gpa, @embedFile("mcp/fixtures/adapter_stdio_28dc.json"), .{});
    defer captured.deinit();
    const original = captured.value.object;
    try std.testing.expectEqualStrings(original.get("initialized").?.object.get("protocolVersion").?.string, client.protocol_version.?);
    try std.testing.expect(client.child.? == &client.adapter.?.stdio.?.child.?);
    try client.listTools();
    const expected_tools = original.get("tools").?.array.items;
    try std.testing.expectEqual(expected_tools.len, client.tools.items.len);
    for (expected_tools, client.tools.items) |expected, actual| try std.testing.expectEqualStrings(expected.object.get("name").?.string, actual.name);
    const response = try client.callTool("one", "{}");
    defer gpa.free(response);
    const parsed = try std.json.parseFromSlice(std.json.Value, gpa, response, .{});
    defer parsed.deinit();
    const json = @import("mcp/protocol.zig").json;
    const actual_json = try json.stringify(gpa, parsed.value.object.get("result").?);
    defer gpa.free(actual_json);
    const expected_json = try json.stringify(gpa, original.get("tool").?);
    defer gpa.free(expected_json);
    try std.testing.expectEqualStrings(expected_json, actual_json);
    try std.testing.expectEqual(original.get("notifications").?.array.items.len, client.notification_count);
    client.child.?.stdin.?.close(io);
    client.child.?.stdin = null;
    const status = try client.child.?.wait(io);
    try std.testing.expect(status == .exited and status.exited == 0);
    client.child = null;
    client.close();
    client.close();
    try std.testing.expect(client.adapter == null);
    try client.connect(&.{program});
    try client.listTools();
    client.close();
}
test "mcp.adapter actual CLI stdio syntax tool output and explicit HTTP usage" {
    const cli = try executable("PI_MCP_ADAPTER_CLI");
    defer gpa.free(cli);
    const program = try executable("PI_MCP_ADAPTER_SERVER");
    defer gpa.free(program);
    try expectRun(&.{ cli, "mcp", program }, null, 0, "one\t\ntwo\t\n");
    try expectRun(&.{ cli, "mcp", "--url" }, null, 2, "usage: pi mcp");
    try expectRun(&.{ cli, "mcp", "--url", "ftp://127.0.0.1/mcp" }, null, 2, "mcp connect failed: UnsupportedMcpUrl");
}
test "mcp.adapter actual CLI HTTP handshake pagination session headers and DELETE" {
    const cli = try executable("PI_MCP_ADAPTER_CLI");
    defer gpa.free(cli);
    const server = try fixture.PlanServer.init(gpa, io, &.{
        .{ .path = "/mcp", .body = handshake, .headers = session_header, .payload_contains = "initialize" },
        .{ .path = "/mcp", .body = "", .status = .accepted, .payload_contains = "notifications/initialized", .expected_request_headers = session_header },
        .{ .path = "/mcp", .body = "{\"jsonrpc\":\"2.0\",\"id\":2,\"result\":{\"tools\":[{\"name\":\"first\",\"description\":\"HTTP tool\",\"inputSchema\":{}}],\"nextCursor\":\"next\"}}", .payload_contains = "tools/list", .expected_request_headers = &.{.{ .name = "mcp-protocol-version", .value = "2025-11-25" }} },
        .{ .path = "/mcp", .body = "{\"jsonrpc\":\"2.0\",\"id\":3,\"result\":{\"tools\":[{\"name\":\"second\",\"inputSchema\":{}}]}}", .payload_contains = "next" },
        .{ .path = "/mcp", .body = "", .status = .no_content, .expected_request_headers = session_header },
    });
    defer server.deinit();
    const url = try server.url(gpa, "/mcp");
    defer gpa.free(url);
    try expectRun(&.{ cli, "mcp", "--url", url }, null, 0, "first\tHTTP tool\nsecond\t\n");
    try server.finish();
    try std.testing.expectEqual(@as(usize, 5), server.captured.items.len);
}
test "mcp.adapter real HTTP call keeps owned legacy envelope and remote errors" {
    const server = try fixture.PlanServer.init(gpa, io, &.{
        .{ .path = "/mcp", .body = handshake, .headers = session_header },
        .{ .path = "/mcp", .body = "", .status = .accepted },
        .{ .path = "/mcp", .body = "{\"jsonrpc\":\"2.0\",\"id\":2,\"result\":{\"content\":[{\"type\":\"text\",\"text\":\"hé😀\"}]}}", .payload_contains = "a\\\"b" },
        .{ .path = "/mcp", .body = "{\"jsonrpc\":\"2.0\",\"id\":3,\"error\":{\"code\":-32042,\"message\":\"remote\",\"data\":{\"detail\":7}}}", .payload_contains = "failure" },
        .{ .path = "/mcp", .body = "", .status = .no_content },
    });
    defer server.deinit();
    const url = try server.url(gpa, "/mcp");
    defer gpa.free(url);
    var client = client_mod.McpClient{ .gpa = gpa, .io = io };
    defer client.deinit();
    try client.connectHttp(url);
    try std.testing.expect(client.child == null);
    const response = try client.callTool("a\"b", "{}");
    defer gpa.free(response);
    const parsed = try std.json.parseFromSlice(std.json.Value, gpa, response, .{});
    defer parsed.deinit();
    try std.testing.expectEqual(@as(i64, 2), parsed.value.object.get("id").?.integer);
    try std.testing.expectEqualStrings("hé😀", parsed.value.object.get("result").?.object.get("content").?.array.items[0].object.get("text").?.string);
    try std.testing.expectError(error.McpRemoteError, client.callTool("failure", "{}"));
    client.close();
    try server.finish();
}
test "mcp.adapter actual child initialize list call allocation failures clean native ownership" {
    const program = try executable("PI_MCP_ADAPTER_ALLOC_SERVER");
    defer gpa.free(program);
    const Allocate = struct {
        fn run(allocator: std.mem.Allocator, path: []const u8) !void {
            var env: std.process.Environ.Map = .init(allocator);
            defer env.deinit();
            var client = client_mod.McpClient{ .gpa = allocator, .io = io, .environ = &env, .request_timeout_ms = 1000 };
            defer client.deinit();
            try client.connect(&.{path});
            try std.testing.expect(client.child != null);
            try client.listTools();
            const response = try client.callTool("first", "{}");
            defer allocator.free(response);
            client.close();
            try std.testing.expect(client.child == null);
        }
    };
    try std.testing.checkAllAllocationFailures(gpa, Allocate.run, .{program});
}
test "mcp.adapter HTTP bad later page preserves previous owned tool snapshot" {
    const server = try fixture.PlanServer.init(gpa, io, &.{
        .{ .path = "/mcp", .body = handshake, .headers = session_header },
        .{ .path = "/mcp", .body = "", .status = .accepted },
        .{ .path = "/mcp", .body = "{\"jsonrpc\":\"2.0\",\"id\":2,\"result\":{\"tools\":[{\"name\":\"previous\",\"inputSchema\":{}}]}}" },
        .{ .path = "/mcp", .body = "{\"jsonrpc\":\"2.0\",\"id\":3,\"result\":{\"tools\":[{\"name\":\"staged\",\"inputSchema\":{}}],\"nextCursor\":\"bad\"}}" },
        .{ .path = "/mcp", .body = "{\"jsonrpc\":\"2.0\",\"id\":4,\"result\":{\"tools\":[{\"name\":\"invalid\",\"inputSchema\":false}]}}" },
        .{ .path = "/mcp", .body = "", .status = .no_content },
    });
    defer server.deinit();
    const url = try server.url(gpa, "/mcp");
    defer gpa.free(url);
    var client = client_mod.McpClient{ .gpa = gpa, .io = io };
    defer client.deinit();
    try client.connectHttp(url);
    try client.listTools();
    try std.testing.expectError(error.InvalidMcpTools, client.listTools());
    try std.testing.expectEqual(@as(usize, 1), client.tools.items.len);
    try std.testing.expectEqualStrings("previous", client.tools.items[0].name);
    client.close();
    try server.finish();
}
