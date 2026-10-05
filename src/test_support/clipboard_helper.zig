//! Native stand-in for wl-copy/wl-paste with task-owned capture paths.
const std = @import("std");
const Io = std.Io;
pub fn main(init: std.process.Init) !void {
    var args = try std.process.Args.Iterator.initAllocator(init.minimal.args, init.gpa);
    defer args.deinit();
    const name = std.fs.path.basename(args.next() orelse return error.MissingHelperName);
    if (std.mem.eql(u8, name, "wl-copy")) {
        var buffer: [4096]u8 = undefined;
        var input = Io.File.stdin().readerStreaming(init.io, &buffer);
        const bytes = try input.interface.allocRemaining(init.gpa, .limited(1024 * 1024));
        defer init.gpa.free(bytes);
        const output = init.environ_map.get("PI_COPY_E2E_OUTPUT") orelse return error.MissingCopyOutput;
        const file = try Io.Dir.createFileAbsolute(init.io, output, .{});
        defer file.close(init.io);
        try file.writeStreamingAll(init.io, bytes);
        const calls = init.environ_map.get("PI_COPY_E2E_CALLS") orelse return error.MissingCopyCalls;
        const log = try Io.Dir.createFileAbsolute(init.io, calls, .{ .truncate = false });
        defer log.close(init.io);
        const stat = try log.stat(init.io);
        try log.writePositionalAll(init.io, "call\n", stat.size);
        return;
    }
    const mode_path = init.environ_map.get("PI_CLIPBOARD_E2E_MODE") orelse return error.MissingPasteMode;
    const mode = try Io.Dir.cwd().readFileAlloc(init.io, mode_path, init.gpa, .limited(1024));
    defer init.gpa.free(mode);
    const image_mode = std.mem.eql(u8, mode, "image");
    var selected: ?[]const u8 = null;
    var listing = false;
    while (args.next()) |arg| {
        if (std.mem.eql(u8, arg, "--list-types")) listing = true;
        if (std.mem.eql(u8, arg, "--type")) selected = args.next();
    }
    if (listing) return Io.File.stdout().writeStreamingAll(init.io, if (image_mode) "text/plain\nimage/png\n" else "text/plain\n");
    const wanted = selected orelse return error.MissingPasteType;
    if (image_mode and std.mem.eql(u8, wanted, "image/png")) {
        const image_path = init.environ_map.get("PI_CLIPBOARD_E2E_IMAGE") orelse return error.MissingPasteImage;
        const bytes = try Io.Dir.cwd().readFileAlloc(init.io, image_path, init.gpa, .limited(1024 * 1024));
        defer init.gpa.free(bytes);
        return Io.File.stdout().writeStreamingAll(init.io, bytes);
    }
    if (std.mem.eql(u8, wanted, "text") or std.mem.eql(u8, wanted, "text/plain;charset=utf-8")) return Io.File.stdout().writeStreamingAll(init.io, init.environ_map.get("PI_CLIPBOARD_E2E_TEXT") orelse return error.MissingPasteText);
    std.process.exit(3);
}
