//! Owned native child used to verify legacy environment inheritance without global mutation.
const std = @import("std");
const client_mod = @import("mcp/client.zig");
pub fn main(init: std.process.Init) !void {
    const args = try init.minimal.args.toSlice(init.arena.allocator());
    if (args.len > 1 and std.mem.eql(u8, args[1], "mcp")) return runAdapterProbe(init, args[2..]);
    if (args.len != 2) return error.InvalidProbeArguments;
    var client = client_mod.McpClient{ .gpa = init.gpa, .io = init.io };
    defer client.deinit();
    try client.connect(&.{args[1]});
    try client.listTools();
    if (client.tools.items.len != 2) return error.InvalidProbeTools;
    try std.Io.File.stdout().writeStreamingAll(init.io, "inherited PATH: 2 tools\n");
}

/// The historical low-level adapter CLI is a test fixture. Production `pi mcp`
/// follows upstream's configured server management commands.
fn runAdapterProbe(init: std.process.Init, args: []const []const u8) !void {
    const http = args.len > 0 and std.mem.eql(u8, args[0], "--url");
    if (args.len == 0 or (http and args.len != 2)) {
        try std.Io.File.stdout().writeStreamingAll(init.io, "usage: pi mcp <server-command> [args...] | pi mcp --url <http(s)-url>\n");
        std.process.exit(2);
    }
    var client = client_mod.McpClient{ .gpa = init.gpa, .io = init.io, .environ = init.environ_map };
    defer client.deinit();
    const connected = if (http) client.connectHttp(args[1]) else client.connect(args);
    connected catch |cause| {
        const message = try std.fmt.allocPrint(init.arena.allocator(), "mcp connect failed: {s}\n", .{@errorName(cause)});
        try std.Io.File.stdout().writeStreamingAll(init.io, message);
        std.process.exit(2);
    };
    client.listTools() catch |cause| {
        client.close();
        const message = try std.fmt.allocPrint(init.arena.allocator(), "mcp tools/list failed: {s}\n", .{@errorName(cause)});
        try std.Io.File.stdout().writeStreamingAll(init.io, message);
        std.process.exit(2);
    };
    for (client.tools.items) |tool| {
        const line = try std.fmt.allocPrint(init.arena.allocator(), "{s}\t{s}\n", .{ tool.name, tool.description });
        try std.Io.File.stdout().writeStreamingAll(init.io, line);
    }
}
