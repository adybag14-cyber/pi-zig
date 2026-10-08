const std = @import("std");
const agent = @import("agent/loop.zig");
const tools = @import("agent/tools.zig");
const builtin = @import("mcp/codemode_builtin.zig");
test "native codemode nested pipeline MCP discovery metadata matches selected original namespace and schemas" {
    const gpa = std.testing.allocator;
    const json = @import("mcp/protocol.zig").json;
    var captured = try json.Owned.parse(gpa, @embedFile("mcp/fixtures/codemode-mcp-metadata-6fb.json"));
    defer captured.deinit();
    for (json.get(captured.value, "rows").?.array.items) |row| {
        var result = try json.Owned.empty(gpa);
        defer result.deinit();
        result.value = try @import("mcp/agent_tools.zig").codemodeMetadata(result.arena.allocator(), json.get(row, "server").?.string, json.get(row, "configuration").?, json.get(row, "initialized").?, json.get(row, "tool").?);
        const expected = try json.stringify(gpa, json.get(row, "expected").?);
        defer gpa.free(expected);
        const actual = try json.stringify(gpa, result.value);
        defer gpa.free(actual);
        if (!json.equal(json.get(row, "expected").?, result.value)) std.debug.print("Expected metadata: {s}\nActual metadata: {s}\n", .{ expected, actual });
        try std.testing.expect(json.equal(json.get(row, "expected").?, result.value));
    }
}

test "native codemode nested pipeline builtin activation requires explicit selection retains modifiers and no-tools" {
    var config: agent.AgentConfig = .{};
    try std.testing.expect(!builtin.Runtime.isActive(&config));
    config.tool_filter.allow = &.{"codemode"};
    try std.testing.expect(builtin.Runtime.isActive(&config));
    config.tool_filter.no_tools = true;
    try std.testing.expect(!builtin.Runtime.isActive(&config));
    config.tool_filter = .{ .modifiers = &.{"+codemode"} };
    try std.testing.expect(builtin.Runtime.isActive(&config));
    config.tool_filter.modifiers = &.{ "+codemode", "-codemode" };
    try std.testing.expect(!builtin.Runtime.isActive(&config));
    config.tool_filter = .{ .builtin_allow = &.{ "read", "codemode" } };
    try std.testing.expect(builtin.Runtime.isActive(&config));
    config.tool_filter.exclude = &.{"codemode"};
    try std.testing.expect(!builtin.Runtime.isActive(&config));
}

test "native codemode nested pipeline real builtin runtime executes current agent hook pipeline and persists branch store" {
    const gpa = std.testing.allocator;
    const Session = @import("agent/session.zig").Session;
    var session = try Session.init(gpa, "builtin", ".");
    defer session.deinit();
    var runtime: builtin.Runtime = .{ .io = std.testing.io, .cwd = ".", .session = &session };
    const State = struct {
        calls: usize = 0,
        before_calls: usize = 0,
        fn exists(_: ?*anyopaque, name: []const u8) bool {
            return std.mem.eql(u8, name, "echo");
        }
        fn execute(raw: ?*anyopaque, allocator: std.mem.Allocator, _: []const u8, _: []const u8) !?tools.ToolResult {
            const self: *@This() = @ptrCast(@alignCast(raw.?));
            self.calls += 1;
            return .{ .content = try allocator.dupe(u8, "owned nested result"), .is_error = false };
        }
        fn before(raw: ?*anyopaque, _: std.mem.Allocator, name: []const u8, id: []const u8, _: []const u8) !?agent.BeforeToolResult {
            const self: *@This() = @ptrCast(@alignCast(raw.?));
            if (std.mem.eql(u8, name, "echo")) {
                self.before_calls += 1;
                try std.testing.expectEqualStrings("outer/1", id);
            }
            return null;
        }
    };
    var state: State = .{};
    var config: agent.AgentConfig = .{ .hook_ctx = &state, .auto_compaction_enabled = false, .disable_builtin_tools = true, .tool_filter = .{ .allow = &.{ "codemode", "echo" } }, .extra_tools_json = "[{\"type\":\"function\",\"function\":{\"name\":\"echo\",\"parameters\":{\"type\":\"object\",\"properties\":{}}}}]", .external_tool_exists_fn = State.exists, .external_tool_fn = State.execute, .before_tool_fn = State.before };
    config.builtin_extension_ctx = &runtime;
    config.builtin_extension_runtime_fn = builtin.Runtime.execute;
    config.builtin_extension_exists_fn = builtin.Runtime.exists;
    config.builtin_extension_schemas_fn = builtin.Runtime.declareSchemas;
    var mock = try @import("ai/mock.zig").MockModel.loadFromJson(gpa, "[{\"content\":\"run\",\"tool_calls\":[{\"id\":\"outer\",\"name\":\"codemode\",\"arguments\":\"{\\\"code\\\":\\\"const listed=await searchTools('echo');if(listed.length!==1||listed[0].name!=='echo')throw Error('discovery');const doc=await describeTool('echo');if(!doc.includes('echo(args:'))throw Error('declaration');store('persisted', await tools.echo({})); return load('persisted');\\\"}\"}]},{\"content\":\"done\"}]");
    defer mock.deinit(gpa);
    var result = try agent.run(gpa, std.testing.io, ".", mock.client(), &session, "run", config, null, null);
    defer result.deinit(gpa);
    try std.testing.expectEqual(@as(usize, 1), state.calls);
    try std.testing.expectEqual(@as(usize, 1), state.before_calls);
    var store = try @import("mcp/codemode_tool.zig").loadBranchStore(gpa, &session);
    defer store.deinit();
    try std.testing.expectEqualStrings("owned nested result", @import("mcp/protocol.zig").json.get(store.value, "persisted").?.string);
}

test "native codemode nested pipeline preserves preparation validation permissions result hooks and cancellation" {
    const State = struct {
        before_calls: usize = 0,
        after_calls: usize = 0,
        execute_calls: usize = 0,
        blocked: bool = false,
        fn exists(_: ?*anyopaque, name: []const u8) bool {
            return std.mem.eql(u8, name, "echo");
        }
        fn prepare(_: ?*anyopaque, gpa: std.mem.Allocator, _: []const u8, _: []const u8) !?[]u8 {
            return try gpa.dupe(u8, "{\"value\":\"prepared\"}");
        }
        fn before(raw: ?*anyopaque, gpa: std.mem.Allocator, _: []const u8, id: []const u8, args: []const u8) !?agent.BeforeToolResult {
            const self: *@This() = @ptrCast(@alignCast(raw.?));
            self.before_calls += 1;
            try std.testing.expectEqualStrings("outer/1", id);
            try std.testing.expectEqualStrings("{\"value\":\"prepared\"}", args);
            return if (self.blocked) .{ .block = true, .reason = try gpa.dupe(u8, "denied by original hook") } else null;
        }
        fn execute(raw: ?*anyopaque, gpa: std.mem.Allocator, _: []const u8, _: []const u8) !?tools.ToolResult {
            const self: *@This() = @ptrCast(@alignCast(raw.?));
            self.execute_calls += 1;
            return .{ .content = try gpa.dupe(u8, "native answer"), .is_error = false };
        }
        fn after(raw: ?*anyopaque, gpa: std.mem.Allocator, _: []const u8, _: []const u8, _: []const u8, _: *const tools.ToolResult) !?agent.ToolResultOverride {
            const self: *@This() = @ptrCast(@alignCast(raw.?));
            self.after_calls += 1;
            return .{ .content = try gpa.dupe(u8, "result hook answer"), .is_error = false };
        }
    };
    var state: State = .{};
    const config: agent.AgentConfig = .{ .hook_ctx = &state, .external_tool_exists_fn = State.exists, .external_prepare_arguments_fn = State.prepare, .before_tool_fn = State.before, .after_tool_fn = State.after, .external_tool_fn = State.execute };
    const schema = "[{\"type\":\"function\",\"function\":{\"name\":\"echo\",\"parameters\":{\"type\":\"object\",\"properties\":{\"value\":{\"type\":\"string\"}},\"required\":[\"value\"]}}}]";
    var successful = try agent.executeNestedTool(std.testing.allocator, std.testing.io, ".", &config, schema, "outer/1", "echo", "{}", null);
    defer successful.deinit(std.testing.allocator);
    try std.testing.expectEqualStrings("result hook answer", successful.content);
    try std.testing.expect(successful.duration_ms != null);
    state.blocked = true;
    var denied = try agent.executeNestedTool(std.testing.allocator, std.testing.io, ".", &config, schema, "outer/1", "echo", "{}", null);
    defer denied.deinit(std.testing.allocator);
    try std.testing.expect(denied.is_error and denied.duration_ms == null);
    try std.testing.expectEqual(@as(usize, 1), state.execute_calls);
    try std.testing.expectEqual(@as(usize, 1), state.after_calls);
}

test "native codemode nested pipeline builtin callbacks declare and execute in the real agent loop" {
    const Mock = @import("ai/mock.zig").MockModel;
    const Session = @import("agent/session.zig").Session;
    const State = struct {
        calls: usize = 0,
        fn schemas(_: ?*anyopaque, gpa: std.mem.Allocator) ![]u8 {
            return gpa.dupe(u8, "[{\"type\":\"function\",\"function\":{\"name\":\"codemode\",\"parameters\":{\"type\":\"object\",\"properties\":{\"code\":{\"type\":\"string\"}},\"required\":[\"code\"]}}}]");
        }
        fn exists(_: ?*anyopaque, name: []const u8) bool {
            return std.mem.eql(u8, name, "codemode");
        }
        fn execute(raw: ?*anyopaque, gpa: std.mem.Allocator, _: []const u8, _: []const u8, _: []const u8, _: agent.ExternalToolProgressFn, _: ?*anyopaque, _: ?*bool) !?tools.ToolResult {
            const self: *@This() = @ptrCast(@alignCast(raw.?));
            self.calls += 1;
            return .{ .content = try gpa.dupe(u8, "Script completed"), .is_error = false };
        }
    };
    const gpa = std.testing.allocator;
    var state: State = .{};
    var mock = try Mock.loadFromJson(gpa, "[{\"content\":\"run\",\"tool_calls\":[{\"id\":\"outer\",\"name\":\"codemode\",\"arguments\":\"{\\\"code\\\":\\\"return 1;\\\"}\"}]},{\"content\":\"done\"}]");
    defer mock.deinit(gpa);
    var session = try Session.init(gpa, "codemode", ".");
    defer session.deinit();
    var config: agent.AgentConfig = .{ .auto_compaction_enabled = false, .disable_builtin_tools = true };
    config.builtin_extension_ctx = &state;
    config.builtin_extension_tool_fn = State.execute;
    config.builtin_extension_exists_fn = State.exists;
    config.builtin_extension_schemas_fn = State.schemas;
    var result = try agent.run(gpa, std.testing.io, ".", mock.client(), &session, "run", config, null, null);
    defer result.deinit(gpa);
    try std.testing.expectEqual(@as(usize, 1), state.calls);
    var found = false;
    for (session.entries.items) |entry| if (std.mem.eql(u8, entry.role, "tool") and std.mem.eql(u8, entry.content, "Script completed")) {
        found = true;
    };
    try std.testing.expect(found);
}
