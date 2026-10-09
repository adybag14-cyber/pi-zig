const std = @import("std");
const loader = @import("coding_agent/project_context.zig");
const json = @import("durable/backend/json.zig");
comptime {
    _ = @import("coding_agent/context.zig");
}
test "Source f1 project context precedence ordering and nested worktree symlink identity" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    const fixture = if (@import("builtin").os.tag == .windows) @embedFile("coding_agent/fixtures/context-files-f1-windows.json") else @embedFile("coding_agent/fixtures/context-files-f1-linux.json");
    var original = try json.Owned.parse(gpa, fixture);
    defer original.deinit();
    for (original.value.object.get("rows").?.array.items) |row| {
        if (row.object.get("skipped") != null) continue;
        var scratch = std.testing.tmpDir(.{});
        defer scratch.cleanup();
        var buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
        const length = try scratch.dir.realPath(io, &buffer);
        const root = buffer[0..length];
        const cwd = try std.fs.path.join(gpa, &.{ root, row.object.get("cwd").?.string });
        defer gpa.free(cwd);
        const agent_dir = try std.fs.path.join(gpa, &.{ root, row.object.get("agentDir").?.string });
        defer gpa.free(agent_dir);
        try std.Io.Dir.cwd().createDirPath(io, cwd);
        try std.Io.Dir.cwd().createDirPath(io, agent_dir);
        for (row.object.get("nodes").?.array.items) |node| {
            if (node.object.get("target") != null) continue;
            const path = try std.fs.path.join(gpa, &.{ root, node.object.get("path").?.string });
            defer gpa.free(path);
            try std.Io.Dir.cwd().createDirPath(io, std.fs.path.dirname(path).?);
            if (node.object.get("directory") != null) try std.Io.Dir.cwd().createDirPath(io, path) else try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = path, .data = node.object.get("data").?.string });
        }
        for (row.object.get("nodes").?.array.items) |node| if (node.object.get("target")) |target| {
            const path = try std.fs.path.join(gpa, &.{ root, node.object.get("path").?.string });
            defer gpa.free(path);
            try std.Io.Dir.cwd().createDirPath(io, std.fs.path.dirname(path).?);
            try std.Io.Dir.cwd().symLink(io, target.string, path, .{});
        };
        var loaded = try loader.load(gpa, io, cwd, agent_dir, true);
        defer loaded.deinit(gpa);
        var owned: std.ArrayList(loader.File) = .empty;
        defer owned.deinit(gpa);
        for (loaded.items) |item| if (std.mem.startsWith(u8, item.path, root)) try owned.append(gpa, item);
        const expected = row.object.get("expected").?.array.items;
        if (owned.items.len != expected.len) std.debug.print("Context scenario{s} expected{} actual{}\n", .{ row.object.get("name").?.string, expected.len, owned.items.len });
        try std.testing.expectEqual(expected.len, owned.items.len);
        for (owned.items, expected) |item, prior| {
            const path = try std.fs.path.resolve(gpa, &.{ root, prior.object.get("path").?.string });
            defer gpa.free(path);
            try std.testing.expectEqualStrings(path, item.path);
            try std.testing.expectEqualStrings(prior.object.get("content").?.string, item.content);
        }
    }
}
test "Source f1 context file allocation failures retain complete path and content ownership" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    var scratch = std.testing.tmpDir(.{});
    defer scratch.cleanup();
    var buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const length = try scratch.dir.realPath(io, &buffer);
    try scratch.dir.createDirPath(io, "agent");
    try scratch.dir.createDirPath(io, "project/src");
    try scratch.dir.writeFile(io, .{ .sub_path = "agent/AGENTS.md", .data = "global" });
    try scratch.dir.writeFile(io, .{ .sub_path = "project/AGENTS.md", .data = "parent" });
    const cwd = try std.fs.path.join(gpa, &.{ buffer[0..length], "project/src" });
    defer gpa.free(cwd);
    const agent_dir = try std.fs.path.join(gpa, &.{ buffer[0..length], "agent" });
    defer gpa.free(agent_dir);
    const Probe = struct {
        fn run(a: std.mem.Allocator, directory: []const u8, global: []const u8) !void {
            var loaded = try loader.load(a, std.testing.io, directory, global, true);
            defer loaded.deinit(a);
        }
    };
    try std.testing.checkAllAllocationFailures(gpa, Probe.run, .{ cwd, agent_dir });
}
