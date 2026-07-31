//! Minimal eval harness: run scripted prompts against mock model and score.
const std = @import("std");
const Io = std.Io;
const mock = @import("../ai/mock.zig");
const agent_loop = @import("../agent/loop.zig");
const session_mod = @import("../agent/session.zig");

pub const EvalCase = struct {
    name: []const u8,
    prompt: []const u8,
    /// Substring that must appear in final assistant text.
    expect_contains: []const u8,
};

pub const EvalResult = struct {
    name: []const u8,
    passed: bool,
    detail: []const u8,

    pub fn deinit(self: *EvalResult, gpa: std.mem.Allocator) void {
        gpa.free(self.name);
        gpa.free(self.detail);
        self.* = undefined;
    }
};

pub fn runCase(gpa: std.mem.Allocator, io: Io, cwd: []const u8, case: EvalCase, script_json: []const u8) !EvalResult {
    var m = try mock.MockModel.loadFromJson(gpa, script_json);
    defer m.deinit(gpa);
    var sess = try session_mod.Session.init(gpa, "eval", cwd);
    defer sess.deinit();
    var result = try agent_loop.run(gpa, io, cwd, m.client(), &sess, case.prompt, .{ .max_turns = 8 }, null, null);
    defer result.deinit(gpa);
    const passed = std.mem.indexOf(u8, result.final_text, case.expect_contains) != null;
    return .{
        .name = try gpa.dupe(u8, case.name),
        .passed = passed,
        .detail = try gpa.dupe(u8, result.final_text),
    };
}

test "eval case passes with mock" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buf: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const n = try tmp.dir.realPath(io, &path_buf);
    const cwd = path_buf[0..n];
    const script =
        \\[{"content":"hello eval world","tool_calls":[]}]
    ;
    var r = try runCase(gpa, io, cwd, .{
        .name = "hello",
        .prompt = "say hi",
        .expect_contains = "eval world",
    }, script);
    defer r.deinit(gpa);
    try std.testing.expect(r.passed);
}
