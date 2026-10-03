const std = @import("std");
const builtin = @import("builtin");
const client_mod = @import("client.zig");

test "native MCP stdio preserves buffered notifications through handshake pagination and call" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    const executable = try std.fs.path.resolve(gpa, &.{ "zig-out", "bin", if (builtin.os.tag == .windows) "pi-mcp-fixture.exe" else "pi-mcp-fixture" });
    defer gpa.free(executable);
    var client = client_mod.McpClient{ .gpa = gpa, .io = io };
    defer client.deinit();
    try client.connect(&.{executable});
    try std.testing.expectEqualStrings(client_mod.latest_protocol_version, client.protocol_version.?);
    try client.listTools();
    try std.testing.expectEqual(@as(usize, 2), client.tools.items.len);
    const result = try client.callTool("one", "{}");
    defer gpa.free(result);
    try std.testing.expect(std.mem.indexOf(u8, result, "real-pipe") != null);
    try std.testing.expectEqual(@as(usize, 2), client.notification_count);
    try std.testing.expectEqual(@as(usize, 0), client.unknown_response_count);
    // Close the pipe to let our owned server exit; no global process operations.
    client.child.?.stdin.?.close(io);
    client.child.?.stdin = null;
    const status = try client.child.?.wait(io);
    client.child = null;
    try std.testing.expect(status == .exited and status.exited == 0);
}
