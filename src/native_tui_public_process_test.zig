const std = @import("std");
const builtin = @import("builtin");
test "native worker public TUI components loaders image and actual callbacks run without Node" {
    try runWorker(@embedFile("extensions/fixtures/tui-public-worker-original-6fb.input.txt"), @embedFile("extensions/fixtures/tui-public-worker-original-6fb.json"));
}
test "native worker genuine Stack ScrollView layout state and transient timer run without Node" {
    try runWorker(@embedFile("extensions/fixtures/stack-scroll-worker-original-6fb.input.txt"), @embedFile("extensions/fixtures/stack-scroll-worker-original-6fb.json"));
}
test "native worker genuine StdinBuffer EventEmitter fragments paste and real Escape timer run without Node" {
    try runWorker(@embedFile("extensions/fixtures/stdin-worker-original-6fb.input.txt"), @embedFile("extensions/fixtures/stdin-worker-original-6fb.json"));
}
fn runWorker(input: []const u8, expected: []const u8) !void {
    return runWorkerWarnings(input, expected, "");
}
test "native worker actual event warning producer retains queued identity stdout and stderr order" {
    try runWorkerWarnings(@embedFile("extensions/fixtures/node-warning-worker-24.input.txt"), @embedFile("extensions/fixtures/node-warning-worker-24.json"), @embedFile("extensions/fixtures/node-warning-worker-24.stderr.txt"));
}
test "native worker async event iterator once resource binding backpressure and deprecation run without Node" {
    try runWorkerWarnings(@embedFile("extensions/fixtures/node-events-async-worker-24.input.txt"), @embedFile("extensions/fixtures/node-events-async-worker-24.json"), @embedFile("extensions/fixtures/node-events-async-worker-24.stderr.txt"));
}
test "native worker warning trace flags and deprecation suppression match actual Node output" {
    try runWorkerWarnings(@embedFile("extensions/fixtures/node-warning-flags-worker-24.input.txt"), @embedFile("extensions/fixtures/node-warning-flags-worker-24.json"), @embedFile("extensions/fixtures/node-warning-flags-worker-24.stderr.txt"));
}
fn normalizeWarningHost(gpa: std.mem.Allocator, input: []const u8) ![]u8 {
    var result: std.ArrayList(u8) = .empty;
    errdefer result.deinit(gpa);
    var lines = std.mem.splitScalar(u8, input, '\n');
    var first = true;
    while (lines.next()) |line| {
        if (!first) try result.append(gpa, '\n');
        first = false;
        if (std.mem.startsWith(u8, line, "(pi:") or std.mem.startsWith(u8, line, "(node:")) {
            const end = std.mem.indexOf(u8, line, ") ") orelse return error.InvalidNativeWarningPrefix;
            try result.appendSlice(gpa, "(HOST:PID) ");
            try result.appendSlice(gpa, line[end + 2 ..]);
        } else if (std.mem.startsWith(u8, line, "(Use `")) {
            const end = std.mem.indexOfScalarPos(u8, line, 6, ' ') orelse return error.InvalidNativeWarningHint;
            try result.appendSlice(gpa, "(Use `HOST");
            try result.appendSlice(gpa, line[end..]);
        } else try result.appendSlice(gpa, line);
    }
    return result.toOwnedSlice(gpa);
}
fn runWorkerWarnings(input: []const u8, expected: []const u8, expected_stderr: []const u8) !void {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    try temporary.dir.createDir(io, "agent", .default_dir);
    try temporary.dir.createDir(io, "home", .default_dir);
    var buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const length = try temporary.dir.realPath(io, &buffer);
    const agent = try std.fs.path.join(gpa, &.{ buffer[0..length], "agent" });
    defer gpa.free(agent);
    const home = try std.fs.path.join(gpa, &.{ buffer[0..length], "home" });
    defer gpa.free(home);
    const script = try std.fs.path.join(gpa, &.{ buffer[0..length], "entry.mjs" });
    defer gpa.free(script);
    try temporary.dir.writeFile(io, .{ .sub_path = "entry.mjs", .data = input });
    var root_buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const cwd = try std.Io.Dir.cwd().openDir(io, ".", .{});
    defer cwd.close(io);
    const root_length = try cwd.realPath(io, &root_buffer);
    const binary = try std.fs.path.join(gpa, &.{ root_buffer[0..root_length], "zig-out", "bin", if (builtin.os.tag == .windows) "pi-sdk-embedder.exe" else "pi-sdk-embedder" });
    defer gpa.free(binary);
    var environment: std.process.Environ.Map = .init(gpa);
    defer environment.deinit();
    try environment.put("PATH", std.fs.path.dirname(binary).?);
    try environment.put("SystemRoot", "C:/Windows");
    try environment.put("WINDIR", "C:/Windows");
    try environment.put("PI_AGENT_DIR", agent);
    try environment.put("HOME", home);
    try environment.put("USERPROFILE", home);
    try environment.put("PI_OFFLINE", "1");
    const result = try std.process.run(gpa, io, .{ .argv = &.{ binary, script }, .cwd = .{ .path = buffer[0..length] }, .environ_map = &environment, .stdout_limit = .limited(65536), .stderr_limit = .limited(65536), .timeout = .{ .duration = .{ .raw = .fromSeconds(30), .clock = .awake } } });
    defer gpa.free(result.stdout);
    defer gpa.free(result.stderr);
    if (result.term != .exited or result.term.exited != 0) std.debug.print("TUI real-worker failure:\n{s}\n{s}\n", .{ result.stdout, result.stderr });
    try std.testing.expect(result.term == .exited and result.term.exited == 0);
    const stderr = try normalizeWarningHost(gpa, result.stderr);
    defer gpa.free(stderr);
    try std.testing.expectEqualStrings(std.mem.trim(u8, expected_stderr, "\r\n"), std.mem.trim(u8, stderr, "\r\n"));
    try std.testing.expectEqualStrings(std.mem.trim(u8, expected, "\r\n"), std.mem.trim(u8, result.stdout, "\r\n"));
}
