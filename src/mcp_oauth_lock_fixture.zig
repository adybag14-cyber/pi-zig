const std = @import("std");
const lock = @import("mcp/oauth_lock.zig");
pub fn main(init: std.process.Init) !void {
    const args = try init.minimal.args.toSlice(init.arena.allocator());
    if (args.len != 4) return error.InvalidFixtureArguments;
    const lease = try lock.Lease.acquire(init.gpa, init.io, args[1], .{ .wait_ms = 10_000, .heartbeat_ms = 500 }, null);
    defer lease.close(init.io);
    const ready = try std.Io.Dir.cwd().createFile(init.io, args[2], .{});
    try ready.writeStreamingAll(init.io, "owned-lock-ready");
    ready.close(init.io);
    const deadline = std.Io.Clock.awake.now(init.io).toMilliseconds() + 30_000;
    while (std.Io.Clock.awake.now(init.io).toMilliseconds() < deadline) {
        std.Io.Dir.cwd().access(init.io, args[3], .{}) catch |cause| switch (cause) {
            error.FileNotFound => {
                try init.io.sleep(.fromMilliseconds(10), .awake);
                continue;
            },
            else => return cause,
        };
        return;
    }
    return error.OwnedFixtureReleaseTimedOut;
}
