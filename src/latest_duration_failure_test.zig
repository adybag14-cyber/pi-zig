const std = @import("std");
const loop = @import("agent/loop.zig");
const tools = @import("agent/tools.zig");
const session = @import("agent/session.zig");
const mock = @import("ai/mock.zig");
test "latest tool duration records thrown execution and omits rejected invocations in both modes" {
    const gpa = std.testing.allocator;
    const schema = "[{\"type\":\"function\",\"function\":{\"name\":\"duration_failure\",\"parameters\":{\"type\":\"object\",\"required\":[\"value\"],\"properties\":{\"value\":{\"type\":\"string\"}}}}}]";
    const script =
        \\[{"content":"calls","tool_calls":[{"id":"executed","name":"duration_failure","arguments":"{\"value\":\"yes\"}"},{"id":"rejected","name":"duration_failure","arguments":"{}"}]},{"content":"done","tool_calls":[]}]
    ;
    const Probe = struct {
        executed: bool = false,
        rejected: bool = false,
        valid: bool = true,
        fn execute(_: ?*anyopaque, _: std.mem.Allocator, _: []const u8, _: []const u8) anyerror!?tools.ToolResult {
            return error.SourceExecutionFailure;
        }
        fn event(raw: ?*anyopaque, value: loop.AgentEvent) void {
            const self: *@This() = @ptrCast(@alignCast(raw.?));
            if (value.kind != .tool_execution_end) return;
            if (std.mem.eql(u8, value.id, "executed")) {
                self.executed = true;
                self.valid = self.valid and value.duration_ms != null and value.is_error;
            } else if (std.mem.eql(u8, value.id, "rejected")) {
                self.rejected = true;
                self.valid = self.valid and value.duration_ms == null and value.is_error;
            }
        }
    };
    for ([_]loop.ToolExecutionMode{ .parallel, .sequential }) |mode| {
        var probe: Probe = .{};
        var model = try mock.MockModel.loadFromJson(gpa, script);
        defer model.deinit(gpa);
        var sess = try session.Session.init(gpa, "duration-errors", ".");
        defer sess.deinit();
        var result = try loop.run(gpa, std.testing.io, ".", model.client(), &sess, "run", .{
            .extra_tools_json = schema, .external_tool_fn = Probe.execute,
            .hook_ctx = &probe, .tool_execution = mode,
        }, Probe.event, &probe);
        defer result.deinit(gpa);
        try std.testing.expect(probe.executed and probe.rejected and probe.valid);
        for (sess.entries.items) |entry| if (std.mem.eql(u8, entry.role, "tool")) {
            try std.testing.expectEqual(std.mem.eql(u8, entry.tool_call_id.?, "executed"), entry.tool_duration_ms != null);
        };
    }
}
