//! Optional SQLite-backed Pi session administration executable.
const std = @import("std");
const sqlite_cli = @import("storage/sqlite_cli.zig");

pub fn main(init: std.process.Init) !void {
    const args = try init.minimal.args.toSlice(init.arena.allocator());
    var buffer: [8192]u8 = undefined;
    var stdout: std.Io.File.Writer = .init(.stdout(), init.io, &buffer);
    const result = sqlite_cli.execute(init.gpa, init.io, if (args.len > 0) args[1..] else &.{}, &stdout.interface) catch |err| {
        try stdout.interface.print("pi-sqlite failed: {s}\n", .{@errorName(err)});
        try stdout.interface.flush();
        std.process.exit(1);
    };
    try stdout.interface.flush();
    if (result.exit_code != 0) std.process.exit(result.exit_code);
}

test {
    std.testing.refAllDecls(sqlite_cli);
}
