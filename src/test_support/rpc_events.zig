//! Bounded owned JSON event selection for real native CLI processes.
const std = @import("std");
const rpc = @import("rpc_process.zig");
const Io = std.Io;

pub fn event(gpa: std.mem.Allocator, process: *rpc.Process, kind: []const u8, id: ?[]const u8) !std.json.Parsed(std.json.Value) {
    const end = Io.Clock.awake.now(process.io).toMilliseconds() + 30_000;
    while (true) {
        const remaining = end - Io.Clock.awake.now(process.io).toMilliseconds();
        if (remaining <= 0) return error.TreeRpcTimeout;
        const line = try process.line(@intCast(remaining));
        defer gpa.free(line);
        const parsed = std.json.parseFromSlice(std.json.Value, gpa, line, .{ .allocate = .alloc_always }) catch continue;
        if (parsed.value == .object) {
            const actual = parsed.value.object.get("type");
            const actual_id = parsed.value.object.get("id");
            const matches = if (actual) |v| v == .string and std.mem.eql(u8, v.string, kind) else false;
            const matches_id = if (id) |wanted| if (actual_id) |v| v == .string and std.mem.eql(u8, v.string, wanted) else false else true;
            if (matches and matches_id) return parsed;
        }
        parsed.deinit();
    }
}

pub fn response(gpa: std.mem.Allocator, process: *rpc.Process, id: []const u8) !std.json.Parsed(std.json.Value) {
    const parsed = try event(gpa, process, "response", id);
    errdefer parsed.deinit();
    try std.testing.expectEqual(std.json.Value{ .bool = true }, parsed.value.object.get("success").?);
    return parsed;
}
