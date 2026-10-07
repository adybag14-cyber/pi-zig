const std = @import("std");
const builtin = @import("builtin");
const rpc = @import("test_support/rpc_process.zig");
const pty = @import("test_support/pty.zig");

test "latest user bash real RPC sanitizes split ANSI UTF8 updates result and persisted session" {
    if (builtin.os.tag != .linux) return error.SkipZigTest;
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    var environment = try std.testing.environ.createMap(gpa);
    defer environment.deinit();
    const binary = try pty.executablePath(gpa, io, environment.get("PI_TEST_BINARY") orelse "zig-out/bin/pi");
    defer gpa.free(binary);
    var scratch = std.testing.tmpDir(.{});
    defer scratch.cleanup();
    try scratch.dir.createDirPath(io, "agent");
    try scratch.dir.createDirPath(io, "workspace");
    try scratch.dir.writeFile(io, .{ .sub_path = "workspace/mock.json", .data = "[]" });
    var root_buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const count = try scratch.dir.realPath(io, &root_buffer);
    const agent_dir = try std.fs.path.join(gpa, &.{ root_buffer[0..count], "agent" });
    defer gpa.free(agent_dir);
    const workspace = try std.fs.path.join(gpa, &.{ root_buffer[0..count], "workspace" });
    defer gpa.free(workspace);
    const session = try std.fs.path.join(gpa, &.{ root_buffer[0..count], "bash.jsonl" });
    defer gpa.free(session);
    try environment.put("PI_AGENT_DIR", agent_dir);
    try environment.put("PI_OFFLINE", "1");
    const errors_file = try scratch.dir.createFile(io, "stderr.log", .{});
    defer errors_file.close(io);
    var child = try rpc.Process.spawn(gpa, io, .{ .argv = &.{ binary, "--mock-script", "mock.json", "--mode", "rpc", "--offline", "--session", session }, .cwd = .{ .path = workspace }, .environ_map = &environment, .stdin = .pipe, .stderr = .{ .file = errors_file } }, 60_000);
    defer child.deinit();
    const command = "printf 'before\\033[3'; sleep 0.05; printf '1mred\\033[0'; sleep 0.05; printf 'm\\033]0;title\\033'; sleep 0.05; printf '\\\\after\\r\\n\\360\\237'; sleep 0.05; printf '\\214\\215'";
    const encoded_command = try std.json.Stringify.valueAlloc(gpa, command, .{});
    defer gpa.free(encoded_command);
    const request = try std.fmt.allocPrint(gpa, "{{\"id\":\"bash\",\"type\":\"bash\",\"command\":{s}}}\n", .{encoded_command});
    defer gpa.free(request);
    try child.send(request);
    var updates: std.ArrayList(u8) = .empty;
    defer updates.deinit(gpa);
    var complete = false;
    for (0..64) |_| {
        const line = child.line(15_000) catch |cause| {
            const errors = try scratch.dir.readFileAlloc(io, "stderr.log", gpa, .limited(1024 * 1024));
            defer gpa.free(errors);
            std.debug.print("User bash RPC ended: {s}; stderr={s}; stdout={s}\n", .{ @errorName(cause), errors, child.output.items });
            return cause;
        };
        defer gpa.free(line);
        const item = std.json.parseFromSlice(std.json.Value, gpa, line, .{}) catch |cause| {
            std.debug.print("User bash RPC non-JSON line: {s}\n", .{line});
            return cause;
        };
        defer item.deinit();
        const kind = item.value.object.get("type") orelse continue;
        if (kind != .string) continue;
        if (std.mem.eql(u8, kind.string, "bash_execution_update")) {
            const delta = item.value.object.get("delta") orelse return error.MissingBashProgressDelta;
            try updates.appendSlice(gpa, delta.string);
        } else if (std.mem.eql(u8, kind.string, "response")) {
            try std.testing.expect(item.value.object.get("success").?.bool);
            const data = item.value.object.get("data").?;
            try std.testing.expectEqualStrings("beforeredafter\n🌍", data.object.get("output").?.string);
            complete = true;
            break;
        }
    }
    try std.testing.expect(complete);
    try std.testing.expectEqualStrings("beforeredafter\n🌍", updates.items);
    try child.send("{\"id\":\"quit\",\"type\":\"quit\"}\n");
    child.closeInput();
    const term = try child.wait(15_000);
    try std.testing.expect(term == .exited and term.exited == 0);
    const persisted = try scratch.dir.readFileAlloc(io, "bash.jsonl", gpa, .limited(1024 * 1024));
    defer gpa.free(persisted);
    try std.testing.expect(std.mem.indexOf(u8, persisted, "beforeredafter\\n🌍") != null);
    try std.testing.expect(std.mem.indexOf(u8, persisted, "\\u001b") == null);
}
