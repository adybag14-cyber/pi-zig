//! Owned native child used to verify legacy environment inheritance without global mutation.
const std = @import("std");
const client_mod = @import("mcp/client.zig");
pub fn main(init: std.process.Init) !void {
    const args = try init.minimal.args.toSlice(init.arena.allocator());
    if (args.len != 2) return error.InvalidProbeArguments;
    var client = client_mod.McpClient{ .gpa = init.gpa, .io = init.io };
    defer client.deinit();
    try client.connect(&.{args[1]});
    try client.listTools();
    if (client.tools.items.len != 2) return error.InvalidProbeTools;
    try std.Io.File.stdout().writeStreamingAll(init.io, "inherited PATH: 2 tools\n");
}
