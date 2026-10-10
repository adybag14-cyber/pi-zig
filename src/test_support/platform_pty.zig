//! Platform fixtures share actual byte capture; no emulated frontend.
const std = @import("std");
const builtin = @import("builtin");
const linux_pty = @import("pty.zig");
const backend = switch (builtin.os.tag) {
    .windows => @import("windows_conpty.zig"),
    .macos => @import("macos_pty.zig"),
    else => linux_pty,
};
pub const Session = backend.Session;
pub const executablePath = linux_pty.executablePath;
pub fn supported() bool {
    return builtin.os.tag == .linux or builtin.os.tag == .windows or builtin.os.tag == .macos;
}
pub fn spawn(gpa: std.mem.Allocator, io: std.Io, options: std.process.SpawnOptions, timeout_ms: u32) !Session {
    if (comptime builtin.os.tag == .windows) {
        const configured = if (options.environ_map) |map| map.get("PI_TEST_CONPTY_LAUNCHER") else null;
        const launcher = try executablePath(gpa, io, configured orelse "zig-out/bin/pi-conpty-launcher.exe");
        defer gpa.free(launcher);
        return backend.Session.spawn(gpa, io, launcher, options, timeout_ms);
    }
    return backend.Session.spawn(gpa, io, options, timeout_ms);
}
pub const Scratch = struct {
    gpa: std.mem.Allocator,
    io: std.Io,
    tmp: std.testing.TmpDir,
    dir: std.Io.Dir,
    path: []u8,
    pub fn init(gpa: std.mem.Allocator, io: std.Io, _: []const u8) !Scratch {
        if (!supported()) return error.SkipZigTest;
        var tmp = std.testing.tmpDir(.{});
        errdefer tmp.cleanup();
        var buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
        const length = try tmp.dir.realPath(io, &buffer);
        return .{ .gpa = gpa, .io = io, .tmp = tmp, .dir = tmp.dir, .path = try gpa.dupe(u8, buffer[0..length]) };
    }
    pub fn deinit(self: *Scratch) void {
        self.tmp.cleanup();
        self.gpa.free(self.path);
    }
};
