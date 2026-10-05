//! Actual argument/environment recorder. It does not interpret shell scripts.
const std = @import("std");
pub fn main(init: std.process.Init) !void {
    const args = try init.minimal.args.toSlice(init.arena.allocator());
    var environment = try init.minimal.environ.createMap(init.gpa);
    defer environment.deinit();
    const mode = environment.get("PI_COMMAND_FIXTURE_MODE") orelse "args";
    if (std.mem.eql(u8, mode, "sleep")) {
        try init.io.sleep(.fromSeconds(30), .awake);
        return;
    }
    if (std.mem.eql(u8, mode, "output")) {
        try std.Io.File.stdout().writeStreamingAll(init.io, "native-output");
    } else if (std.mem.eql(u8, mode, "large")) {
        var bytes: [60000]u8 = undefined;
        for (&bytes, 0..) |*byte, index| byte.* = if (index % 2 == 0) 'L' else '\n';
        try std.Io.File.stdout().writeStreamingAll(init.io, &bytes);
    } else {
        const cwd = try std.process.currentPathAlloc(init.io, init.gpa);
        defer init.gpa.free(cwd);
        const wire = try std.json.Stringify.valueAlloc(init.gpa, .{ .argv = args[1..], .cwd = cwd, .marker = environment.get("PI_NATIVE_ARG_MARKER"), .inherited = environment.get("PI_NATIVE_PARENT_MARKER") }, .{});
        defer init.gpa.free(wire);
        try std.Io.File.stdout().writeStreamingAll(init.io, wire);
    }
    if (environment.get("PI_COMMAND_FIXTURE_EXIT")) |code| std.process.exit(try std.fmt.parseInt(u8, code, 10));
}
