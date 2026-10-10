//! Native child program for argv, stream, cancellation and spill contracts.
const std = @import("std");
const builtin = @import("builtin");
fn pause(io: std.Io, milliseconds: i64) !void {
    try std.Io.Timeout.sleep(.{ .duration = .{ .raw = .fromMilliseconds(milliseconds), .clock = .awake } }, io);
}
pub fn main(init: std.process.Init) !void {
    var arguments = try std.process.Args.Iterator.initAllocator(init.minimal.args, init.gpa);
    defer arguments.deinit();
    const executable = arguments.next().?;
    const mode = arguments.next() orelse return error.MissingFixtureMode;
    const stdout = std.Io.File.stdout();
    const stderr = std.Io.File.stderr();
    if (std.mem.eql(u8, mode, "args")) {
        var argv: std.ArrayList([]const u8) = .empty;
        defer argv.deinit(init.gpa);
        while (arguments.next()) |argument| try argv.append(init.gpa, argument);
        const text = try std.json.Stringify.valueAlloc(init.gpa, argv.items, .{});
        defer init.gpa.free(text);
        try stdout.writeStreamingAll(init.io, text);
        return;
    }
    if (std.mem.eql(u8, mode, "environment")) {
        const values = .{ .parent = init.environ_map.get("PI_DURABLE_PARENT"), .base = init.environ_map.get("PI_DURABLE_BASE"), .request = init.environ_map.get("PI_DURABLE_REQUEST"), .shared = init.environ_map.get("PI_DURABLE_SHARED") };
        const text = try std.json.Stringify.valueAlloc(init.gpa, values, .{});
        defer init.gpa.free(text);
        try stdout.writeStreamingAll(init.io, text);
        return;
    }
    if (std.mem.eql(u8, mode, "streams")) {
        try stdout.writeStreamingAll(init.io, &.{0xef});
        try pause(init.io, 30);
        try stdout.writeStreamingAll(init.io, &.{ 0xbb, 0xbf, 'a', 0xf0, 0x9f });
        try pause(init.io, 30);
        try stderr.writeStreamingAll(init.io, &.{ 0xef, 0xbb });
        try pause(init.io, 30);
        try stdout.writeStreamingAll(init.io, &.{ 0x98, 0x80, '\n' });
        try pause(init.io, 30);
        try stderr.writeStreamingAll(init.io, &.{ 0xbf, 'e', 0xe2, 0x82 });
        try pause(init.io, 30);
        try stderr.writeStreamingAll(init.io, &.{ 0xef, 0xbb, 0xbf, '\n' });
        try pause(init.io, 30);
        std.process.exit(7);
    }
    if (std.mem.eql(u8, mode, "large")) {
        var bytes: [32768]u8 = undefined;
        for (&bytes, 0..) |*byte, index| byte.* = if (index % 2 == 0) 'L' else '\n';
        for (0..64) |_| {
            try stdout.writeStreamingAll(init.io, &bytes);
            try stderr.writeStreamingAll(init.io, &bytes);
        }
        return;
    }
    if (std.mem.eql(u8, mode, "sleep")) {
        try stdout.writeStreamingAll(init.io, "before\n");
        try pause(init.io, 5000);
        try stdout.writeStreamingAll(init.io, "after\n");
        return;
    }
    if (std.mem.eql(u8, mode, "sentinel")) {
        try pause(init.io, 400);
        const path = arguments.next() orelse return error.MissingSentinelPath;
        try std.Io.Dir.cwd().writeFile(init.io, .{ .sub_path = path, .data = "survived" });
        return;
    }
    if (std.mem.eql(u8, mode, "tree")) {
        try stdout.writeStreamingAll(init.io, "tree-before\n");
        var child = try std.process.spawn(init.io, .{ .argv = &.{ executable, "sleep" }, .stdin = .ignore, .stdout = .inherit, .stderr = .ignore, .create_no_window = true });
        defer child.kill(init.io);
        try pause(init.io, 5000);
        _ = try child.wait(init.io);
        return;
    }
    if (std.mem.eql(u8, mode, "exit1000")) {
        if (builtin.os.tag == .windows) {
            const win = struct {
                extern "kernel32" fn ExitProcess(code: std.os.windows.UINT) callconv(.winapi) noreturn;
            };
            win.ExitProcess(1000);
        }
        std.process.exit(232);
    }
    return error.UnknownFixtureMode;
}
