//! Native stand-in for an owned package manager or managed ripgrep executable.
const std = @import("std");
const Io = std.Io;
pub fn main(init: std.process.Init) !void {
    var args = try std.process.Args.Iterator.initAllocator(init.minimal.args, init.gpa);
    defer args.deinit();
    _ = args.next();
    var output: Io.Writer.Allocating = .init(init.gpa);
    defer output.deinit();
    var first = true;
    var version = false;
    while (args.next()) |arg| {
        if (!first) try output.writer.writeByte(' ');
        try output.writer.writeAll(arg);
        version = version or std.mem.eql(u8, arg, "--version");
        first = false;
    }
    try output.writer.writeByte('\n');
    if (init.environ_map.get("PI_MANAGER_FIXTURE_LOG")) |path| {
        const file = try Io.Dir.createFileAbsolute(init.io, path, .{ .truncate = false });
        defer file.close(init.io);
        const stat = try file.stat(init.io);
        return file.writePositionalAll(init.io, output.written(), stat.size);
    }
    if (version) return Io.File.stdout().writeStreamingAll(init.io, "ripgrep 14.1.1\n");
    try Io.File.stdout().writeStreamingAll(init.io, "managed-rg-188:");
    try Io.File.stdout().writeStreamingAll(init.io, output.written());
}
