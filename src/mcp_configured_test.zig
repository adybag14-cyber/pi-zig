//! Native configured MCP cases use actual files, retained children, sockets and agent runs.
const std = @import("std");
const configured = @import("mcp/configured.zig");
const projection = @import("mcp/agent_tools.zig");
const protocol = @import("mcp/protocol.zig");
const json = protocol.json;
const Value = protocol.Value;
const agent = @import("agent/loop.zig");
const tools = @import("agent/tools.zig");
const mock = @import("ai/mock.zig");
const Session = @import("agent/session.zig").Session;
const gpa = std.testing.allocator;
const io = std.testing.io;
const Root = struct {
    tmp: std.testing.TmpDir,
    path: []u8,
    fn init() !Root {
        var tmp = std.testing.tmpDir(.{ .iterate = true });
        errdefer tmp.cleanup();
        var buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
        const n = try tmp.dir.realPath(io, &buffer);
        try tmp.dir.createDir(io, ".pi", .default_dir);
        return .{ .tmp = tmp, .path = try gpa.dupe(u8, buffer[0..n]) };
    }
    fn deinit(self: *Root) void {
        self.tmp.cleanup();
        gpa.free(self.path);
    }
    fn write(self: *Root, project: bool, config: Value) !void {
        const bytes = try json.stringify(gpa, config);
        defer gpa.free(bytes);
        try self.tmp.dir.writeFile(io, .{ .sub_path = if (project) ".pi/mcp.json" else "mcp.json", .data = bytes });
    }
};
fn fixturePath() ![]u8 {
    var env = try std.testing.environ.createMap(gpa);
    defer env.deinit();
    return gpa.dupe(u8, env.get("PI_MCP_CONFIGURED_FIXTURE") orelse return error.MissingFixture);
}
fn map(a: std.mem.Allocator, pairs: []const struct { []const u8, Value }) !Value {
    var value: Value = .{ .object = .empty };
    for (pairs) |pair| try value.object.put(a, pair[0], pair[1]);
    return value;
}
fn stdioConfig(a: std.mem.Allocator, program: []const u8, exposure: []const u8) !Value {
    return map(a, &.{ .{ "command", .{ .string = program } }, .{ "exposure", .{ .string = exposure } }, .{ "toolExposure", try map(a, &.{.{ "hidden", .{ .string = "hidden" } }}) } });
}
fn document(a: std.mem.Allocator, name: []const u8, value: Value) !Value {
    return map(a, &.{.{ "mcpServers", try map(a, &.{.{ name, value }}) }});
}
fn discard(_: ?*anyopaque, _: agent.ExternalToolUpdate) void {}
fn create(root: *Root, env: *const std.process.Environ.Map, trusted: bool) !*configured.Service {
    return configured.Service.create(gpa, io, .{ .agent_dir = root.path, .cwd = root.path, .project_trusted = trusted, .environ = env, .output_root = root.path });
}
fn execute(service: *configured.Service, name: []const u8, args: []const u8) !tools.ToolResult {
    return (try configured.Service.execute(service, gpa, "owned-call", name, args, discard, null, null)) orelse error.MissingConfiguredTool;
}

test "mcp.configured trusted project overrides and untrusted files never execute" {
    const program = try fixturePath();
    defer gpa.free(program);
    var root = try Root.init();
    defer root.deinit();
    var arena: std.heap.ArenaAllocator = .init(gpa);
    defer arena.deinit();
    const a = arena.allocator();
    try root.write(false, try document(a, "fixture", try stdioConfig(a, program, "direct")));
    try root.write(true, try document(a, "fixture", try map(a, &.{.{ "enabled", .{ .bool = false } }})));
    var env = try std.testing.environ.createMap(gpa);
    defer env.deinit();
    const untrusted = try create(&root, &env, false);
    defer untrusted.deinit();
    try untrusted.start();
    try std.testing.expect(untrusted.owns("mcp__fixture__double"));
    try std.testing.expect(!untrusted.owns("mcp__fixture__hidden"));
    const trusted = try create(&root, &env, true);
    defer trusted.deinit();
    try trusted.start();
    try std.testing.expectEqual(@as(usize, 0), trusted.servers.items.len);
    try std.testing.expectEqual(@as(usize, 0), trusted.descriptors.items.len);
    var result = try execute(untrusted, "mcp__fixture__double", "{\"value\":3}");
    defer result.deinit(gpa);
    try std.testing.expectEqualStrings("6", result.content);
}
test "mcp.configured callable exposure attempts admit OAuth and report actual connection failures" {
    var root = try Root.init();
    defer root.deinit();
    var arena: std.heap.ArenaAllocator = .init(gpa);
    defer arena.deinit();
    const a = arena.allocator();
    const servers = try map(a, &.{ .{ "codemode", try map(a, &.{.{ "command", .{ .string = "must-not-start" } }}) }, .{ "deferred", try stdioConfig(a, "must-not-start", "deferred") }, .{ "oauth", try map(a, &.{ .{ "url", .{ .string = "http://127.0.0.1:1/mcp" } }, .{ "exposure", .{ .string = "direct" } } }) }, .{ "disabled", try map(a, &.{ .{ "command", .{ .string = "must-not-start" } }, .{ "exposure", .{ .string = "direct" } }, .{ "enabled", .{ .bool = false } } }) } });
    try root.write(false, try map(a, &.{.{ "mcpServers", servers }}));
    var env = try std.testing.environ.createMap(gpa);
    defer env.deinit();
    const service = try create(&root, &env, true);
    defer service.deinit();
    try service.start();
    try std.testing.expectEqual(@as(usize, 3), service.servers.items.len);
    try std.testing.expectEqual(@as(usize, 3), service.diagnostics.items.len);
    var oauth = false;
    for (service.servers.items) |server| if (std.mem.eql(u8, server.name, "oauth")) {
        oauth = server.auth_provider != null;
    };
    try std.testing.expect(oauth);
    for (service.diagnostics.items) |message| try std.testing.expect(std.mem.indexOf(u8, message, "McpOAuthUnsupported") == null);
}

test "mcp.configured real deferred discovery stays callable while model declarations load ranked matches" {
    const program = try fixturePath();
    defer gpa.free(program);
    var root = try Root.init();
    defer root.deinit();
    var arena: std.heap.ArenaAllocator = .init(gpa);
    defer arena.deinit();
    try root.write(false, try document(arena.allocator(), "fixture", try stdioConfig(arena.allocator(), program, "deferred")));
    var env = try std.testing.environ.createMap(gpa);
    defer env.deinit();
    const service = try create(&root, &env, false);
    defer service.deinit();
    try service.start();
    try std.testing.expect(service.owns("mcp__fixture__double"));
    try std.testing.expect(!service.owns("mcp__fixture__hidden"));
    const initial = try service.schemasJson();
    defer gpa.free(initial);
    var initial_parsed = try json.Owned.parse(gpa, initial);
    defer initial_parsed.deinit();
    try std.testing.expectEqual(@as(usize, 1), initial_parsed.value.array.items.len);
    try std.testing.expectEqualStrings("tool_search", try protocol.text(try protocol.field(initial_parsed.value.array.items[0], "function"), "name"));
    const registry = try service.registrySchemasJson();
    defer gpa.free(registry);
    try std.testing.expect(std.mem.indexOf(u8, registry, "mcp__fixture__double") != null);
    const names = try service.searchAndLoad("double value", 1);
    defer gpa.free(names);
    try std.testing.expectEqual(@as(usize, 1), names.len);
    try std.testing.expectEqualStrings("mcp__fixture__double", names[0]);
    const active = try service.schemasJson();
    defer gpa.free(active);
    var parsed = try json.Owned.parse(gpa, active);
    defer parsed.deinit();
    try std.testing.expectEqual(@as(usize, 2), parsed.value.array.items.len);
    const repeated = try service.searchAndLoad("double value", 1);
    defer gpa.free(repeated);
    try std.testing.expectEqual(@as(usize, 0), repeated.len);
}
test "mcp.configured real agent tool_search loads only the next model declaration and persists transcript discovery" {
    const program = try fixturePath();
    defer gpa.free(program);
    var root = try Root.init();
    defer root.deinit();
    var arena: std.heap.ArenaAllocator = .init(gpa);
    defer arena.deinit();
    try root.write(false, try document(arena.allocator(), "fixture", try stdioConfig(arena.allocator(), program, "deferred")));
    var env = try std.testing.environ.createMap(gpa);
    defer env.deinit();
    const service = try create(&root, &env, false);
    defer service.deinit();
    try service.start();
    var model = try mock.MockModel.loadFromJson(gpa, "[{\"content\":\"search\",\"tool_calls\":[{\"id\":\"search\",\"name\":\"tool_search\",\"arguments\":\"{\\\"query\\\":\\\"double value\\\",\\\"limit\\\":1}\"}]},{\"content\":\"call\",\"tool_calls\":[{\"id\":\"double\",\"name\":\"mcp__fixture__double\",\"arguments\":\"{\\\"value\\\":4}\"}]},{\"content\":\"done\"}]");
    defer model.deinit(gpa);
    const Probe = struct {
        model: *mock.MockModel,
        calls: usize = 0,
        fn complete(raw: *anyopaque, allocator: std.mem.Allocator, messages: []const @import("ai/root.zig").ChatMessage, schema: []const u8) anyerror!@import("ai/root.zig").ModelResponse {
            const self: *@This() = @ptrCast(@alignCast(raw));
            try std.testing.expect(std.mem.indexOf(u8, schema, "tool_search") != null);
            try std.testing.expectEqual(self.calls != 0, std.mem.indexOf(u8, schema, "mcp__fixture__double") != null);
            self.calls += 1;
            return self.model.client().complete(allocator, messages, schema);
        }
    };
    var probe = Probe{ .model = &model };
    var session = try Session.init(gpa, "mcp-discovery", root.path);
    defer session.deinit();
    var result = try agent.run(gpa, io, root.path, .{ .ptr = &probe, .completeFn = Probe.complete }, &session, "discover", .{ .disable_builtin_tools = true, .configured_tool_ctx = service, .configured_tools_json_fn = configured.Service.dynamicSchemas, .configured_tool_fn = configured.Service.execute, .configured_tool_exists_fn = configured.Service.exists }, null, null);
    defer result.deinit(gpa);
    try std.testing.expectEqual(@as(usize, 3), probe.calls);
    var loaded = false;
    var executed = false;
    for (session.entries.items) |entry| if (std.mem.eql(u8, entry.role, "tool")) {
        if (std.mem.eql(u8, entry.tool_name.?, "tool_search")) {
            try std.testing.expectEqual(@as(usize, 1), entry.added_tool_names.len);
            try std.testing.expectEqualStrings("mcp__fixture__double", entry.added_tool_names[0]);
            loaded = !entry.tool_is_error;
        } else if (std.mem.eql(u8, entry.tool_name.?, "mcp__fixture__double")) {
            try std.testing.expectEqualStrings("8", entry.content);
            executed = !entry.tool_is_error;
        }
    };
    try std.testing.expect(loaded and executed);
}

test "mcp.configured deferred search validates source query and limit diagnostics without mutating loadout" {
    const program = try fixturePath();
    defer gpa.free(program);
    var root = try Root.init();
    defer root.deinit();
    var arena: std.heap.ArenaAllocator = .init(gpa);
    defer arena.deinit();
    try root.write(false, try document(arena.allocator(), "fixture", try stdioConfig(arena.allocator(), program, "deferred")));
    var env = try std.testing.environ.createMap(gpa);
    defer env.deinit();
    const service = try create(&root, &env, false);
    defer service.deinit();
    try service.start();
    const Progress = struct {
        fn update(_: ?*anyopaque, _: agent.ExternalToolUpdate) void {}
    };
    const cases = [_]struct { args: []const u8, message: []const u8 }{
        .{ .args = "{\"query\":\"\\u00a0\\ufeff\"}", .message = "query must not be empty" },
        .{ .args = "{\"query\":\"double\",\"limit\":0}", .message = "limit must be a positive integer" },
        .{ .args = "{\"query\":\"double\",\"limit\":1.5}", .message = "limit must be a positive integer" },
    };
    for (cases) |case| {
        var result = (try configured.Service.execute(service, gpa, "invalid-search", "tool_search", case.args, Progress.update, null, null)).?;
        defer result.deinit(gpa);
        try std.testing.expect(result.is_error);
        try std.testing.expectEqualStrings(case.message, result.content);
        for (service.descriptors.items) |descriptor| try std.testing.expect(!descriptor.loaded);
    }
    var empty = (try configured.Service.execute(service, gpa, "empty-search", "tool_search", "{\"query\":\"missing-word\"}", Progress.update, null, null)).?;
    defer empty.deinit(gpa);
    try std.testing.expectEqualStrings("No matching tools found.", empty.content);
    try std.testing.expectEqual(@as(usize, 0), empty.added_tool_names.len);
}

test "mcp.configured direct exact override wins glob without downgrading other exposures" {
    const program = try fixturePath();
    defer gpa.free(program);
    var root = try Root.init();
    defer root.deinit();
    var arena: std.heap.ArenaAllocator = .init(gpa);
    defer arena.deinit();
    const a = arena.allocator();
    var value = try stdioConfig(a, program, "codemode");
    try value.object.put(a, "toolExposure", try map(a, &.{ .{ "*", .{ .string = "hidden" } }, .{ "double", .{ .string = "direct" } } }));
    try root.write(false, try document(a, "fixture", value));
    var env = try std.testing.environ.createMap(gpa);
    defer env.deinit();
    const service = try create(&root, &env, false);
    defer service.deinit();
    try service.start();
    try std.testing.expectEqual(@as(usize, 1), service.descriptors.items.len);
    try std.testing.expectEqualStrings("mcp__fixture__double", service.descriptors.items[0].name);
}
test "mcp.configured real agent schema validation dispatch and separate extension hook context" {
    const program = try fixturePath();
    defer gpa.free(program);
    var root = try Root.init();
    defer root.deinit();
    var arena: std.heap.ArenaAllocator = .init(gpa);
    defer arena.deinit();
    const a = arena.allocator();
    try root.write(false, try document(a, "fixture", try stdioConfig(a, program, "direct")));
    var env = try std.testing.environ.createMap(gpa);
    defer env.deinit();
    const service = try create(&root, &env, false);
    defer service.deinit();
    try service.start();
    const schemas = try service.schemasJson();
    defer gpa.free(schemas);
    var model = try mock.MockModel.loadFromJson(gpa, "[{\"content\":\"calls\",\"tool_calls\":[{\"id\":\"mcp-call\",\"name\":\"mcp__fixture__double\",\"arguments\":\"{\\\"value\\\":3}\"},{\"id\":\"extension-call\",\"name\":\"ordinary\",\"arguments\":\"{}\"}]},{\"content\":\"done\"}]");
    defer model.deinit(gpa);
    const Hook = struct {
        before_count: usize = 0,
        prepare_count: usize = 0,
        fn before(raw: ?*anyopaque, _: std.mem.Allocator, _: []const u8, _: []const u8, _: []const u8) !?agent.BeforeToolResult {
            const self: *@This() = @ptrCast(@alignCast(raw.?));
            self.before_count += 1;
            return null;
        }
        fn exists(_: ?*anyopaque, name: []const u8) bool {
            return std.mem.eql(u8, name, "ordinary");
        }
        fn prepare(raw: ?*anyopaque, _: std.mem.Allocator, _: []const u8, _: []const u8) !?[]u8 {
            const self: *@This() = @ptrCast(@alignCast(raw.?));
            self.prepare_count += 1;
            return null;
        }
        fn executeExtension(_: ?*anyopaque, allocator: std.mem.Allocator, name: []const u8, _: []const u8) !?tools.ToolResult {
            if (!std.mem.eql(u8, name, "ordinary")) return null;
            return .{ .content = try allocator.dupe(u8, "extension-result"), .is_error = false };
        }
    };
    var hook: Hook = .{};
    var session = try Session.init(gpa, "mcp-agent", root.path);
    defer session.deinit();
    var result = try agent.run(gpa, io, root.path, model.client(), &session, "run", .{ .disable_builtin_tools = true, .auto_compaction_enabled = false, .hook_ctx = &hook, .before_tool_fn = Hook.before, .external_tool_fn = Hook.executeExtension, .external_tool_exists_fn = Hook.exists, .external_prepare_arguments_fn = Hook.prepare, .extra_tools_json = "[{\"type\":\"function\",\"function\":{\"name\":\"ordinary\",\"parameters\":{\"type\":\"object\"}}}]", .configured_tools_json = schemas, .configured_tool_ctx = service, .configured_tool_fn = configured.Service.execute, .configured_tool_exists_fn = configured.Service.exists }, null, null);
    defer result.deinit(gpa);
    var seen: usize = 0;
    for (session.entries.items) |entry| if (std.mem.eql(u8, entry.role, "tool")) {
        if (std.mem.eql(u8, entry.tool_name orelse "", "mcp__fixture__double")) try std.testing.expectEqualStrings("6", entry.content) else try std.testing.expectEqualStrings("extension-result", entry.content);
        try std.testing.expect(!entry.tool_is_error);
        seen += 1;
    };
    try std.testing.expectEqual(@as(usize, 2), seen);
    try std.testing.expectEqual(@as(usize, 2), hook.before_count);
    try std.testing.expectEqual(@as(usize, 1), hook.prepare_count);
}
test "mcp.configured actual stdio progress abort and error projection" {
    const program = try fixturePath();
    defer gpa.free(program);
    var root = try Root.init();
    defer root.deinit();
    var arena: std.heap.ArenaAllocator = .init(gpa);
    defer arena.deinit();
    const a = arena.allocator();
    try root.write(false, try document(a, "fixture", try stdioConfig(a, program, "direct")));
    var env = try std.testing.environ.createMap(gpa);
    defer env.deinit();
    const service = try create(&root, &env, false);
    defer service.deinit();
    try service.start();
    const Capture = struct {
        count: usize = 0,
        abort: ?*bool = null,
        fn progress(raw: ?*anyopaque, update: agent.ExternalToolUpdate) void {
            const self: *@This() = @ptrCast(@alignCast(raw.?));
            std.testing.expectEqualStrings("Progress 1/2", update.content) catch @panic("wrong progress");
            self.count += 1;
            if (self.abort) |flag| @atomicStore(bool, flag, true, .release);
        }
    };
    var capture: Capture = .{};
    var result = (try configured.Service.execute(service, gpa, "progress-call", "mcp__fixture__progress", "{}", Capture.progress, &capture, null)).?;
    defer result.deinit(gpa);
    try std.testing.expectEqual(@as(usize, 1), capture.count);
    var failure = try execute(service, "mcp__fixture__error", "{}");
    defer failure.deinit(gpa);
    try std.testing.expect(failure.is_error);
    try std.testing.expectEqualStrings("\nMCP tool fixture/error returned an error", failure.content);
    var remote = try execute(service, "mcp__fixture__remote", "{}");
    defer remote.deinit(gpa);
    try std.testing.expectEqualStrings("Original remote message", remote.content);
    try std.testing.expect(remote.is_error);
    var details = try json.Owned.parse(gpa, remote.details_json.?);
    defer details.deinit();
    const original_error = try protocol.field(details.value, "remoteError");
    try std.testing.expectEqual(@as(f64, -32042), try json.asNumber(try protocol.field(original_error, "code")));
    try std.testing.expectEqual(@as(f64, 7), try json.asNumber(try protocol.field(try protocol.field(original_error, "data"), "detail")));
    var aborted = false;
    capture.abort = &aborted;
    try std.testing.expectError(error.McpRequestAborted, configured.Service.execute(service, gpa, "slow-call", "mcp__fixture__slow", "{}", Capture.progress, &capture, &aborted));
    try service.close();
    try std.testing.expectEqual(@as(usize, 0), service.servers.items[0].connection.borrowers);
}
test "mcp.configured static HTTP direct tool actual agent POST GET and DELETE ownership" {
    const fixture = @import("mcp/configured_http_fixture.zig");
    const server = try fixture.Server.init(gpa, io);
    defer server.deinit();
    const url = try server.url(gpa);
    defer gpa.free(url);
    var root = try Root.init();
    defer root.deinit();
    var arena: std.heap.ArenaAllocator = .init(gpa);
    defer arena.deinit();
    const a = arena.allocator();
    const config = try map(a, &.{ .{ "url", .{ .string = url } }, .{ "exposure", .{ .string = "direct" } }, .{ "headers", try map(a, &.{.{ "Authorization", .{ .string = "Bearer ${FIXTURE_TOKEN}" } }}) } });
    try root.write(false, try document(a, "http", config));
    var env = try std.testing.environ.createMap(gpa);
    defer env.deinit();
    try env.put("FIXTURE_TOKEN", "owned-token");
    const service = try create(&root, &env, false);
    defer service.deinit();
    try service.start();
    try server.get_seen.waitTimeout(io, .{ .duration = .{ .raw = .fromSeconds(5), .clock = .awake } });
    const schemas = try service.schemasJson();
    defer gpa.free(schemas);
    var model = try mock.MockModel.loadFromJson(gpa, "[{\"content\":\"call\",\"tool_calls\":[{\"id\":\"http-call\",\"name\":\"mcp__http__echo\",\"arguments\":\"{\\\"message\\\":\\\"native HTTP\\\"}\"}]},{\"content\":\"done\"}]");
    defer model.deinit(gpa);
    var session = try Session.init(gpa, "http-agent", root.path);
    defer session.deinit();
    var result = try agent.run(gpa, io, root.path, model.client(), &session, "run", .{ .disable_builtin_tools = true, .auto_compaction_enabled = false, .configured_tools_json = schemas, .configured_tool_ctx = service, .configured_tool_fn = configured.Service.execute, .configured_tool_exists_fn = configured.Service.exists }, null, null);
    defer result.deinit(gpa);
    var seen = false;
    for (session.entries.items) |entry| if (std.mem.eql(u8, entry.role, "tool")) {
        try std.testing.expectEqualStrings("native HTTP", entry.content);
        seen = true;
    };
    try std.testing.expect(seen);
    try service.close();
    try server.finish();
    var deletes: usize = 0;
    for (server.records.items) |record| {
        try std.testing.expectEqualStrings("Bearer owned-token", record.authorization);
        if (record.method == .DELETE) deletes += 1;
    }
    try std.testing.expectEqual(@as(usize, 1), deletes);
}
test "mcp.configured MCP allowlist keeps direct tools unless MCP selectors filter them" {
    try std.testing.expect((tools.ToolFilter{ .allow = &.{ "read", "bash" } }).isEnabled("mcp__fixture__double"));
    try std.testing.expect(!(tools.ToolFilter{ .allow = &.{} }).isEnabled("mcp__fixture__double"));
    try std.testing.expect((tools.ToolFilter{ .allow = &.{"mcp__fixture__*"} }).isEnabled("mcp__fixture__double"));
    try std.testing.expect(!(tools.ToolFilter{ .allow = &.{"mcp__other__*"} }).isEnabled("mcp__fixture__double"));
    try std.testing.expect(!(tools.ToolFilter{ .exclude = &.{"mcp__*__double"} }).isEnabled("mcp__fixture__double"));
    try std.testing.expect(!(tools.ToolFilter{ .no_tools = true }).isEnabled("mcp__fixture__double"));
}
test "mcp.configured naming Unicode collision and long hash plus schema defaults" {
    const name = try projection.toolName(gpa, "server-a", "é😀", false);
    defer gpa.free(name);
    try std.testing.expectEqualStrings("mcp__server_a_____", name);
    const hashed = try projection.toolName(gpa, "a", "a-b", true);
    defer gpa.free(hashed);
    try std.testing.expect(hashed.len <= 64 and std.mem.startsWith(u8, hashed, "mcp__a__a_b_"));
    var tool = try json.Owned.parse(gpa, "{\"name\":\"test\",\"inputSchema\":{},\"description\":\"  \"}");
    defer tool.deinit();
    const schema = try projection.schema(tool.arena.allocator(), "server", "model", tool.value);
    const function = try protocol.field(schema, "function");
    try std.testing.expectEqualStrings("MCP tool test from server server", try protocol.text(function, "description"));
    const parameters = try protocol.field(function, "parameters");
    try std.testing.expectEqualStrings("object", try protocol.text(parameters, "type"));
    try std.testing.expect((try protocol.field(parameters, "properties")) == .object);
}
fn sameValue(expected: Value, actual: Value) !void {
    if ((expected == .integer or expected == .float) and (actual == .integer or actual == .float)) {
        try std.testing.expectEqual(try json.asNumber(expected), try json.asNumber(actual));
        return;
    }
    try std.testing.expectEqual(std.meta.activeTag(expected), std.meta.activeTag(actual));
    switch (expected) {
        .object => |value| {
            try std.testing.expectEqual(value.count(), actual.object.count());
            var iterator = value.iterator();
            while (iterator.next()) |entry| try sameValue(entry.value_ptr.*, actual.object.get(entry.key_ptr.*) orelse return error.MissingOracleField);
        },
        .array => |value| {
            try std.testing.expectEqual(value.items.len, actual.array.items.len);
            for (value.items, actual.array.items) |first, second| try sameValue(first, second);
        },
        .string => |value| try std.testing.expectEqualStrings(value, actual.string),
        .bool => |value| try std.testing.expectEqual(value, actual.bool),
        .null => {},
        else => return error.UnsupportedOracleValue,
    }
}
fn replaceSaved(allocator: std.mem.Allocator, text: []const u8, path: []const u8) ![]u8 {
    const at = std.mem.indexOf(u8, text, path) orelse return allocator.dupe(u8, text);
    return std.fmt.allocPrint(allocator, "{s}[SAVED_PATH]{s}", .{ text[0..at], text[at + path.len ..] });
}
test "mcp.configured authentic original tool name schema projection and output-file byte oracle" {
    var captured = try json.Owned.parse(gpa, @embedFile("mcp/fixtures/configured_tools_28dc.json"));
    defer captured.deinit();
    var root = try Root.init();
    defer root.deinit();
    for ((try protocol.field(captured.value, "names")).array.items) |item| {
        const name = try projection.toolName(gpa, try protocol.text(item, "server"), try protocol.text(item, "tool"), (try protocol.field(item, "taken")).bool);
        defer gpa.free(name);
        try std.testing.expectEqualStrings(try protocol.text(item, "result"), name);
    }
    for ((try protocol.field(captured.value, "schemas")).array.items) |item| {
        var arena: std.heap.ArenaAllocator = .init(gpa);
        defer arena.deinit();
        const schema = try projection.schema(arena.allocator(), "fixture", try protocol.text(item, "name"), try protocol.field(item, "tool"));
        const function = try protocol.field(schema, "function");
        try std.testing.expectEqualStrings(try protocol.text(item, "description"), try protocol.text(function, "description"));
        try sameValue(try protocol.field(item, "parameters"), try protocol.field(function, "parameters"));
    }
    const saved = (try protocol.field(captured.value, "saved")).array.items;
    var next_saved: usize = 0;
    for ((try protocol.field(captured.value, "conversions")).array.items) |item| {
        var actual = try projection.convert(gpa, io, root.path, "fixture", "tool", try protocol.field(item, "input"));
        defer actual.deinit(gpa);
        const expected = try protocol.field(item, "result");
        const content = (try protocol.field(expected, "content")).array.items;
        var text: std.ArrayList(u8) = .empty;
        defer text.deinit(gpa);
        var text_count: usize = 0;
        var images: usize = 0;
        for (content) |block| {
            const kind = try protocol.text(block, "type");
            if (std.mem.eql(u8, kind, "text")) {
                if (text_count > 0) try text.append(gpa, '\n');
                try text.appendSlice(gpa, try protocol.text(block, "text"));
                text_count += 1;
            } else if (std.mem.eql(u8, kind, "image")) {
                try std.testing.expectEqualStrings(try protocol.text(block, "data"), actual.images[images].data_b64);
                try std.testing.expectEqualStrings(try protocol.text(block, "mimeType"), actual.images[images].mime_type);
                images += 1;
            }
        }
        try std.testing.expectEqual(images, actual.images.len);
        var details = try json.Owned.parse(gpa, actual.details_json.?);
        defer details.deinit();
        try sameValue(try protocol.field(expected, "structuredContent"), try protocol.field(details.value, "structuredContent"));
        var actual_path: ?[]const u8 = null;
        if (json.get(details.value, "fullOutputPath")) |path| actual_path = try json.asString(path) else if (std.mem.indexOf(u8, actual.content, " saved to ")) |at| actual_path = actual.content[at + 10 .. actual.content.len - 1];
        if (actual_path) |path| {
            const original_path = try protocol.text(saved[next_saved], "path");
            const normalized_expected = try replaceSaved(gpa, text.items, original_path);
            defer gpa.free(normalized_expected);
            const normalized_actual = try replaceSaved(gpa, actual.content, path);
            defer gpa.free(normalized_actual);
            try std.testing.expectEqualStrings(normalized_expected, normalized_actual);
            const bytes = try std.Io.Dir.cwd().readFileAlloc(io, path, gpa, .limited(128 * 1024));
            defer gpa.free(bytes);
            try std.testing.expectEqual(@as(f64, @floatFromInt(bytes.len)), try json.asNumber(try protocol.field(saved[next_saved], "bytes")));
            var digest: [32]u8 = undefined;
            std.crypto.hash.sha2.Sha256.hash(bytes, &digest, .{});
            const hex = std.fmt.bytesToHex(digest, .lower);
            try std.testing.expectEqualStrings(try protocol.text(saved[next_saved], "sha256"), &hex);
            next_saved += 1;
        } else try std.testing.expectEqualStrings(text.items, actual.content);
        const expected_error = if (json.get(expected, "isError")) |value| value.bool else false;
        try std.testing.expectEqual(expected_error, actual.is_error);
    }
    try std.testing.expectEqual(saved.len, next_saved);
}
test "mcp.configured close cancels pending startup and never admits another child" {
    const program = try fixturePath();
    defer gpa.free(program);
    var root = try Root.init();
    defer root.deinit();
    var arena: std.heap.ArenaAllocator = .init(gpa);
    defer arena.deinit();
    const a = arena.allocator();
    var value = try stdioConfig(a, program, "direct");
    var args: Value = .{ .array = .init(a) };
    try args.array.append(.{ .string = "--stall" });
    try value.object.put(a, "args", args);
    try value.object.put(a, "timeout", .{ .integer = 2 });
    try root.write(false, try document(a, "fixture", value));
    var env = try std.testing.environ.createMap(gpa);
    defer env.deinit();
    const service = try create(&root, &env, false);
    defer service.deinit();
    const Open = struct {
        service: *configured.Service,
        cause: ?anyerror = null,
        fn run(self: *@This()) void {
            self.service.start() catch |cause| {
                self.cause = cause;
            };
        }
    };
    var opening: Open = .{ .service = service };
    const owner = try std.Thread.spawn(.{}, Open.run, .{&opening});
    var joined = false;
    defer {
        service.close() catch {};
        if (!joined) owner.join();
    }
    const connection = &service.servers.items[0].connection;
    var observed = false;
    for (0..2000) |_| {
        connection.mutex.lockUncancelable(io);
        if (connection.opening_client) |client| {
            observed = client.pendingCount() > 0;
        }
        connection.mutex.unlock(io);
        if (observed) break;
        try io.sleep(.fromMilliseconds(1), .awake);
    }
    try std.testing.expect(observed);
    try service.close();
    owner.join();
    joined = true;
    try std.testing.expectEqual(error.McpConnectionClosed, opening.cause.?);
    try std.testing.expectEqual(@as(usize, 1), connection.attempts);
    try std.testing.expectError(error.McpConnectionClosed, connection.acquire());
    try std.testing.expect(connection.opening_client == null and !connection.opening);
}
test "mcp.configured close active handler joins borrower and rejects late execution" {
    const program = try fixturePath();
    defer gpa.free(program);
    var root = try Root.init();
    defer root.deinit();
    var arena: std.heap.ArenaAllocator = .init(gpa);
    defer arena.deinit();
    const a = arena.allocator();
    try root.write(false, try document(a, "fixture", try stdioConfig(a, program, "direct")));
    var env = try std.testing.environ.createMap(gpa);
    defer env.deinit();
    const service = try create(&root, &env, false);
    defer service.deinit();
    try service.start();
    const Call = struct {
        service: *configured.Service,
        entered: std.Io.Event = .unset,
        cause: ?anyerror = null,
        fn progress(raw: ?*anyopaque, _: agent.ExternalToolUpdate) void {
            const self: *@This() = @ptrCast(@alignCast(raw.?));
            self.entered.set(io);
        }
        fn run(self: *@This()) void {
            var result = configured.Service.execute(self.service, gpa, "active", "mcp__fixture__slow", "{}", progress, self, null) catch |cause| {
                self.cause = cause;
                return;
            };
            if (result) |*value| value.deinit(gpa);
        }
    };
    var call: Call = .{ .service = service };
    const owner = try std.Thread.spawn(.{}, Call.run, .{&call});
    var joined = false;
    defer {
        service.close() catch {};
        if (!joined) owner.join();
    }
    try call.entered.waitTimeout(io, .{ .duration = .{ .raw = .fromSeconds(5), .clock = .awake } });
    try service.close();
    owner.join();
    joined = true;
    try std.testing.expectEqual(error.McpConnectionClosed, call.cause.?);
    try std.testing.expectError(error.McpConnectionClosed, execute(service, "mcp__fixture__double", "{\"value\":3}"));
    try std.testing.expectEqual(@as(usize, 0), service.servers.items[0].connection.borrowers);
    try service.close();
}
test "mcp.configured progress callback self close is rejected without deadlock" {
    const program = try fixturePath();
    defer gpa.free(program);
    var root = try Root.init();
    defer root.deinit();
    var arena: std.heap.ArenaAllocator = .init(gpa);
    defer arena.deinit();
    const a = arena.allocator();
    try root.write(false, try document(a, "fixture", try stdioConfig(a, program, "direct")));
    var env = try std.testing.environ.createMap(gpa);
    defer env.deinit();
    const service = try create(&root, &env, false);
    defer service.deinit();
    try service.start();
    const Call = struct {
        service: *configured.Service,
        cause: ?anyerror = null,
        fn progress(raw: ?*anyopaque, _: agent.ExternalToolUpdate) void {
            const self: *@This() = @ptrCast(@alignCast(raw.?));
            self.service.close() catch |cause| {
                self.cause = cause;
            };
        }
    };
    var call: Call = .{ .service = service };
    var result = (try configured.Service.execute(service, gpa, "reentrant", "mcp__fixture__progress", "{}", Call.progress, &call, null)).?;
    defer result.deinit(gpa);
    try std.testing.expectEqual(error.ReentrantMcpConfiguredClose, call.cause.?);
    try std.testing.expect(!service.closing.load(.acquire));
}
test "mcp.configured actual create discover schema call allocation failures clean retained ownership" {
    const program = try fixturePath();
    defer gpa.free(program);
    var root = try Root.init();
    defer root.deinit();
    var arena: std.heap.ArenaAllocator = .init(gpa);
    defer arena.deinit();
    try root.write(false, try document(arena.allocator(), "fixture", try stdioConfig(arena.allocator(), program, "direct")));
    var env = try std.testing.environ.createMap(gpa);
    defer env.deinit();
    const Allocate = struct {
        fn run(allocator: std.mem.Allocator, path: []const u8, environment: *const std.process.Environ.Map) !void {
            const service = try configured.Service.create(allocator, io, .{ .agent_dir = path, .cwd = path, .environ = environment, .output_root = path });
            defer service.deinit();
            try service.start();
            const schema = try service.schemasJson();
            defer allocator.free(schema);
            var result = (try configured.Service.execute(service, allocator, "gpa", "mcp__fixture__double", "{\"value\":3}", discard, null, null)) orelse return error.MissingConfiguredTool;
            defer result.deinit(allocator);
            try std.testing.expectEqualStrings("6", result.content);
            try service.close();
        }
    };
    try std.testing.checkAllAllocationFailures(gpa, Allocate.run, .{ root.path, &env });
}
test "mcp.configured projection failure after output save removes only unpublished owned file" {
    var root = try Root.init();
    defer root.deinit();
    var captured = try json.Owned.parse(gpa, @embedFile("mcp/fixtures/configured_tools_28dc.json"));
    defer captured.deinit();
    const input = (try protocol.field(captured.value, "conversions")).array.items[6].object.get("input").?;
    const Allocate = struct {
        fn run(allocator: std.mem.Allocator, path: []const u8, value: Value) !void {
            var result = try projection.convert(allocator, io, path, "fixture", "tool", value);
            defer result.deinit(allocator);
            var details = try json.Owned.parse(gpa, result.details_json.?);
            defer details.deinit();
            const output_path = try protocol.text(details.value, "fullOutputPath");
            try std.Io.Dir.cwd().deleteFile(io, output_path);
            try std.Io.Dir.cwd().deleteDir(io, std.fs.path.dirname(output_path).?);
        }
    };
    try std.testing.checkAllAllocationFailures(gpa, Allocate.run, .{ root.path, input });
    var iterator = root.tmp.dir.iterate();
    try std.testing.expectEqualStrings(".pi", (try iterator.next(io)).?.name);
    if (try iterator.next(io)) |entry| {
        std.debug.print("MCP unpublished orphan after allocation sweep: {s}\n", .{entry.name});
        return error.UnpublishedOutputRemains;
    }
}
fn runConfiguredCli(root: *Root, environment: *const std.process.Environ.Map, tool_name: []const u8, arguments: []const u8) ![]u8 {
    var env = try environment.clone(gpa);
    defer env.deinit();
    const cli = env.get("PI_MCP_CONFIGURED_CLI") orelse return error.MissingCliFixture;
    const program = try gpa.dupe(u8, cli);
    defer gpa.free(program);
    try env.put("PI_AGENT_DIR", root.path);
    try env.put("PI_OFFLINE", "1");
    try env.put("PATH", std.fs.path.dirname(program).?);
    var arena: std.heap.ArenaAllocator = .init(gpa);
    defer arena.deinit();
    const a = arena.allocator();
    const call = try map(a, &.{ .{ "id", .{ .string = "cli-call" } }, .{ "name", .{ .string = tool_name } }, .{ "arguments", .{ .string = arguments } } });
    var calls: Value = .{ .array = .init(a) };
    try calls.array.append(call);
    var script: Value = .{ .array = .init(a) };
    try script.array.append(try map(a, &.{ .{ "content", .{ .string = "call" } }, .{ "tool_calls", calls } }));
    try script.array.append(try map(a, &.{.{ "content", .{ .string = "done" } }}));
    const bytes = try json.stringify(gpa, script);
    defer gpa.free(bytes);
    try root.tmp.dir.writeFile(io, .{ .sub_path = "mock.json", .data = bytes });
    const result = try std.process.run(gpa, io, .{ .argv = &.{ program, "--mode", "json", "--mock-script", "mock.json", "--offline", "--no-session", "--tools", "read,bash", "-p", "run" }, .cwd = .{ .path = root.path }, .environ_map = &env, .stdout_limit = .limited(4 * 1024 * 1024), .stderr_limit = .limited(65536), .timeout = .{ .duration = .{ .raw = .fromSeconds(20), .clock = .awake } } });
    defer gpa.free(result.stderr);
    errdefer gpa.free(result.stdout);
    if (result.term != .exited or result.term.exited != 0) std.debug.print("configured CLI {any}: stdout={s}; stderr={s}\n", .{ result.term, result.stdout, result.stderr });
    try std.testing.expect(result.term == .exited and result.term.exited == 0);
    return result.stdout;
}
test "mcp.configured actual standalone CLI runs global direct stdio tool without Node or shell PATH" {
    const program = try fixturePath();
    defer gpa.free(program);
    var root = try Root.init();
    defer root.deinit();
    var arena: std.heap.ArenaAllocator = .init(gpa);
    defer arena.deinit();
    const a = arena.allocator();
    try root.write(false, try document(a, "fixture", try stdioConfig(a, program, "direct")));
    var env = try std.testing.environ.createMap(gpa);
    defer env.deinit();
    const output = try runConfiguredCli(&root, &env, "mcp__fixture__double", "{\"value\":3}");
    defer gpa.free(output);
    try std.testing.expect(std.mem.indexOf(u8, output, "mcp__fixture__double") != null);
    var lines = std.mem.splitScalar(u8, output, '\n');
    var saw_result = false;
    while (lines.next()) |line| {
        if (line.len == 0) continue;
        var event = try json.Owned.parse(gpa, line);
        defer event.deinit();
        if (json.get(event.value, "type")) |kind| if (kind == .string and std.mem.eql(u8, kind.string, "tool_execution_end")) {
            const result = try protocol.field(event.value, "result");
            const content = (try protocol.field(result, "content")).array.items;
            try std.testing.expectEqualStrings("6", try protocol.text(content[0], "text"));
            saw_result = true;
        };
    }
    try std.testing.expect(saw_result);
}

test "mcp.configured native MCP commands list actual hidden tools and dispatch standalone without Node" {
    const fixture = try fixturePath();
    defer gpa.free(fixture);
    var root = try Root.init();
    defer root.deinit();
    var arena: std.heap.ArenaAllocator = .init(gpa);
    defer arena.deinit();
    try root.write(false, try document(arena.allocator(), "fixture", try stdioConfig(arena.allocator(), fixture, "hidden")));
    var env = try std.testing.environ.createMap(gpa);
    defer env.deinit();
    const cli = try gpa.dupe(u8, env.get("PI_MCP_CONFIGURED_CLI") orelse return error.MissingCliFixture);
    defer gpa.free(cli);
    try env.put("PI_AGENT_DIR", root.path);
    try env.put("PI_OFFLINE", "1");
    try env.put("PATH", std.fs.path.dirname(cli).?);
    const output = try std.process.run(gpa, io, .{ .argv = &.{ cli, "mcp", "list", "--json" }, .cwd = .{ .path = root.path }, .environ_map = &env, .stdout_limit = .limited(65536), .stderr_limit = .limited(65536), .timeout = .{ .duration = .{ .raw = .fromSeconds(20), .clock = .awake } } });
    defer gpa.free(output.stdout);
    defer gpa.free(output.stderr);
    if (output.term != .exited or output.term.exited != 0) std.debug.print("MCP command {any}: {s} {s}\n", .{ output.term, output.stdout, output.stderr });
    try std.testing.expect(output.term == .exited and output.term.exited == 0);
    var report = try json.Owned.parse(gpa, output.stdout);
    defer report.deinit();
    const server = json.get(report.value, "servers").?.array.items[0];
    try std.testing.expectEqualStrings("connected", try protocol.text(server, "state"));
    const names = json.get(server, "tools").?.array.items;
    try std.testing.expect(names.len > 0);
    var saw_hidden = false;
    for (names) |name| if (std.mem.eql(u8, name.string, "hidden")) {
        saw_hidden = true;
    };
    try std.testing.expect(saw_hidden);
    var native = try @import("mcp/cli.zig").run(gpa, .{ .context = .{ .io = io, .agent_dir = root.path, .cwd = root.path }, .environment = &env }, &.{ "login", "fixture" });
    defer native.deinit();
    try std.testing.expectEqual(@as(u64, 1), try json.asInteger(json.get(native.data.value, "code").?));
    try std.testing.expect(std.mem.indexOf(u8, json.get(native.data.value, "errors").?.array.items[0].string, "does not use OAuth") != null);
}
test "mcp.configured actual standalone CLI static-auth HTTP direct tool and DELETE" {
    const fixture = @import("mcp/configured_http_fixture.zig");
    const server = try fixture.Server.init(gpa, io);
    defer server.deinit();
    const url = try server.url(gpa);
    defer gpa.free(url);
    var root = try Root.init();
    defer root.deinit();
    var arena: std.heap.ArenaAllocator = .init(gpa);
    defer arena.deinit();
    const a = arena.allocator();
    try root.write(false, try document(a, "http", try map(a, &.{ .{ "url", .{ .string = url } }, .{ "exposure", .{ .string = "direct" } }, .{ "headers", try map(a, &.{.{ "Authorization", .{ .string = "Bearer owned-token" } }}) } })));
    var env = try std.testing.environ.createMap(gpa);
    defer env.deinit();
    const output = try runConfiguredCli(&root, &env, "mcp__http__echo", "{\"message\":\"cli HTTP\"}");
    defer gpa.free(output);
    try std.testing.expect(std.mem.indexOf(u8, output, "cli HTTP") != null);
    try server.finish();
    var deletes: usize = 0;
    for (server.records.items) |record| if (record.method == .DELETE) {
        deletes += 1;
    };
    try std.testing.expectEqual(@as(usize, 1), deletes);
}

test "mcp.configured default OAuth reads stored grant refreshes once and initializes native HTTP connection" {
    var root = try Root.init();
    defer root.deinit();
    const fixture = @import("ai/http_fixture.zig");
    const server = try fixture.PlanServer.init(gpa, io, &.{
        .{ .path = "/token", .body = "{\"access_token\":\"fresh\",\"refresh_token\":\"rotated\",\"token_type\":\"Bearer\",\"expires_in\":3600}", .payload_contains = "refresh_token=old-refresh" },
        .{ .path = "/mcp", .body = "{\"jsonrpc\":\"2.0\",\"id\":1,\"result\":{\"protocolVersion\":\"2025-11-25\",\"capabilities\":{},\"serverInfo\":{\"name\":\"oauth\",\"version\":\"1\"}}}", .headers = &.{.{ .name = "content-type", .value = "application/json" }}, .expected_request_headers = &.{.{ .name = "authorization", .value = "Bearer fresh" }} },
        .{ .path = "/mcp", .status = .accepted, .body = "", .expected_request_headers = &.{.{ .name = "authorization", .value = "Bearer fresh" }} },
    });
    defer server.deinit();
    const url = try server.url(gpa, "/mcp");
    defer gpa.free(url);
    const endpoint = try server.url(gpa, "/token");
    defer gpa.free(endpoint);
    const issuer = try server.url(gpa, "/authorize");
    defer gpa.free(issuer);
    var arena: std.heap.ArenaAllocator = .init(gpa);
    defer arena.deinit();
    const a = arena.allocator();
    try root.write(false, try document(a, "oauth", try map(a, &.{ .{ "url", .{ .string = url } }, .{ "exposure", .{ .string = "direct" } } })));
    var store = try @import("mcp/oauth_store.zig").Store.init(gpa, io, root.path);
    defer store.deinit();
    const serialized = try std.json.Stringify.valueAlloc(gpa, .{
        .tokens = .{ .access_token = "old-access", .refresh_token = "old-refresh", .token_type = "Bearer" },
        .tokensExpireAt = 0,
        .clientInformation = .{ .client_id = "client", .redirect_uris = [_][]const u8{"http://127.0.0.1/callback"} },
        .discovery = .{ .authorizationServerUrl = issuer, .authorizationServerMetadata = .{ .issuer = issuer, .authorization_endpoint = issuer, .token_endpoint = endpoint, .response_types_supported = [_][]const u8{"code"}, .token_endpoint_auth_methods_supported = [_][]const u8{"none"} } },
    }, .{});
    defer gpa.free(serialized);
    var state = try json.Owned.parse(gpa, serialized);
    defer state.deinit();
    try store.save("oauth", url, state.value, null);
    var environment = try std.testing.environ.createMap(gpa);
    defer environment.deinit();
    const service = try create(&root, &environment, false);
    defer service.deinit();
    try service.start();
    try std.testing.expectEqual(@as(usize, 1), service.servers.items.len);
    try std.testing.expectEqual(@as(usize, 0), service.diagnostics.items.len);
    var saved = (try store.load("oauth", url, null)).?;
    defer saved.deinit();
    try std.testing.expectEqualStrings("rotated", try protocol.text(json.get(saved.value, "tokens").?, "refresh_token"));
    try service.close();
    try server.finish();
    try std.testing.expectEqual(@as(usize, 3), server.captured.items.len);
}

test "mcp.configured native login timeout aborts discovery before browser prompt and joins HTTP owner" {
    var root = try Root.init();
    defer root.deinit();
    var observed: std.Io.Event = .unset;
    var release: std.Io.Event = .unset;
    const server = try @import("ai/http_fixture.zig").PlanServer.init(gpa, io, &.{
        .{ .path = "/mcp", .status = .unauthorized, .body = "unauthorized" },
        .{ .path = "/.well-known/oauth-protected-resource/mcp", .body = "{}", .request_observed = &observed, .response_release = &release },
    });
    defer server.deinit();
    defer release.set(io);
    const url = try server.url(gpa, "/mcp");
    defer gpa.free(url);
    var arena: std.heap.ArenaAllocator = .init(gpa);
    defer arena.deinit();
    try root.write(false, try document(arena.allocator(), "oauth", try map(arena.allocator(), &.{.{ "url", .{ .string = url } }})));
    var environment = try std.testing.environ.createMap(gpa);
    defer environment.deinit();
    const Prompt = struct {
        fn show(_: ?*anyopaque, _: []const u8) !void {
            return error.UnexpectedPrompt;
        }
        fn read(_: ?*anyopaque, _: std.mem.Allocator, _: *bool) !?[]u8 {
            return error.UnexpectedPrompt;
        }
    };
    const started = std.Io.Clock.awake.now(io).toMilliseconds();
    var result = try @import("mcp/cli.zig").run(gpa, .{ .context = .{ .io = io, .agent_dir = root.path, .cwd = root.path }, .environment = &environment, .prompt = .{ .context = null, .show = Prompt.show, .read = Prompt.read } }, &.{ "login", "oauth", "--timeout", "0.05" });
    defer result.deinit();
    try std.testing.expectEqual(@as(u64, 1), try json.asInteger(json.get(result.data.value, "code").?));
    try std.testing.expectEqualStrings("Sign-in to MCP server \"oauth\" was cancelled or not completed within 0 seconds.", json.get(result.data.value, "errors").?.array.items[0].string);
    try std.testing.expect(std.Io.Clock.awake.now(io).toMilliseconds() - started < 1000);
    release.set(io);
}

test "mcp.configured close aborts active sign-in and joins discovery before releasing credentials" {
    var root = try Root.init();
    defer root.deinit();
    var observed: std.Io.Event = .unset;
    var release: std.Io.Event = .unset;
    const server = try @import("ai/http_fixture.zig").PlanServer.init(gpa, io, &.{.{ .path = "/.well-known/oauth-protected-resource/mcp", .body = "{}", .request_observed = &observed, .response_release = &release }});
    defer server.deinit();
    const url = try server.url(gpa, "/mcp");
    defer gpa.free(url);
    var arena: std.heap.ArenaAllocator = .init(gpa);
    defer arena.deinit();
    const a = arena.allocator();
    try root.write(false, try document(a, "oauth", try map(a, &.{.{ "url", .{ .string = url } }})));
    var environment = try std.testing.environ.createMap(gpa);
    defer environment.deinit();
    const service = try create(&root, &environment, false);
    defer service.deinit();
    const Prompt = struct {
        fn show(_: ?*anyopaque, _: []const u8) !void {
            return error.UnexpectedPrompt;
        }
        fn read(_: ?*anyopaque, _: std.mem.Allocator, _: *bool) !?[]u8 {
            return error.UnexpectedPrompt;
        }
    };
    const Work = struct {
        owner: *configured.Service,
        fn run(work: *@This()) !void {
            try work.owner.signIn("oauth", .{ .context = null, .show = Prompt.show, .read = Prompt.read }, null, 5000);
        }
    };
    var work: Work = .{ .owner = service };
    var future = try io.concurrent(Work.run, .{&work});
    var joined = false;
    defer if (!joined) {
        service.close() catch {};
        release.set(io);
        future.cancel(io) catch {};
    };
    try observed.wait(io);
    const started = std.Io.Clock.awake.now(io).toMilliseconds();
    try service.close();
    const result = future.await(io);
    joined = true;
    try std.testing.expectError(error.McpSignInCancelled, result);
    try std.testing.expect(!service.servers.items[0].sign_in_active);
    try std.testing.expect(std.Io.Clock.awake.now(io).toMilliseconds() - started < 1000);
    release.set(io);
}

test "mcp.configured reconnect retires old session before new handshake and fresh GET lifetime" {
    var root = try Root.init();
    defer root.deinit();
    var first_get: std.Io.Event = .unset;
    var second_get: std.Io.Event = .unset;
    const handshake = "{\"jsonrpc\":\"2.0\",\"id\":1,\"result\":{\"protocolVersion\":\"2025-11-25\",\"capabilities\":{},\"serverInfo\":{\"name\":\"reconnect\",\"version\":\"1\"}}}";
    const server = try @import("ai/http_fixture.zig").PlanServer.init(gpa, io, &.{
        .{ .path = "/mcp", .body = handshake, .headers = &.{ .{ .name = "content-type", .value = "application/json" }, .{ .name = "mcp-session-id", .value = "first" } } },
        .{ .path = "/mcp", .body = "", .status = .accepted, .payload_contains = "notifications/initialized" },
        .{ .path = "/mcp", .body = "", .status = .method_not_allowed, .request_observed = &first_get },
        .{ .path = "/mcp", .body = "", .status = .no_content, .expected_request_headers = &.{.{ .name = "mcp-session-id", .value = "first" }} },
        .{ .path = "/mcp", .body = handshake, .headers = &.{ .{ .name = "content-type", .value = "application/json" }, .{ .name = "mcp-session-id", .value = "second" } } },
        .{ .path = "/mcp", .body = "", .status = .accepted, .payload_contains = "notifications/initialized" },
        .{ .path = "/mcp", .body = "", .status = .method_not_allowed, .request_observed = &second_get },
        .{ .path = "/mcp", .body = "", .status = .no_content, .expected_request_headers = &.{.{ .name = "mcp-session-id", .value = "second" }} },
    });
    defer server.deinit();
    const url = try server.url(gpa, "/mcp");
    defer gpa.free(url);
    var arena: std.heap.ArenaAllocator = .init(gpa);
    defer arena.deinit();
    const a = arena.allocator();
    try root.write(false, try document(a, "http", try map(a, &.{ .{ "url", .{ .string = url } }, .{ "headers", try map(a, &.{.{ "Authorization", .{ .string = "Bearer static" } }}) } })));
    var environment = try std.testing.environ.createMap(gpa);
    defer environment.deinit();
    const service = try create(&root, &environment, false);
    defer service.deinit();
    try service.start();
    try first_get.wait(io);
    try service.reconnect("http");
    try second_get.wait(io);
    try std.testing.expect(service.servers.items[0].connection.connectionState() == .ready);
    try service.close();
    try server.finish();
    try std.testing.expectEqual(@as(usize, 8), server.captured.items.len);
}
