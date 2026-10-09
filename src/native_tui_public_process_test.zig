const std = @import("std");
const builtin = @import("builtin");
test "native worker public TUI components loaders image and actual callbacks run without Node" {
    try runWorker(@embedFile("extensions/fixtures/tui-public-worker-original-6fb.input.js"), @embedFile("extensions/fixtures/tui-public-worker-original-6fb.json"));
}
test "native worker genuine Stack ScrollView layout state and transient timer run without Node" {
    try runWorker(@embedFile("extensions/fixtures/stack-scroll-worker-original-6fb.input.js"), @embedFile("extensions/fixtures/stack-scroll-worker-original-6fb.json"));
}
fn runWorker(input: []const u8, expected: []const u8) !void {
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
    try std.testing.expectEqualStrings("", result.stderr);
    try std.testing.expectEqualStrings(std.mem.trim(u8, expected, "\r\n"), std.mem.trim(u8, result.stdout, "\r\n"));
}
