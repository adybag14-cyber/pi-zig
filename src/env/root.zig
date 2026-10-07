pub const frame = @import("frame.zig");
pub const ssh = @import("ssh.zig");
pub const deploy = @import("deploy.zig");
pub const ssh_process = @import("ssh_process.zig");
pub const metadata = @import("metadata.zig");
pub const files = @import("files.zig");
pub const connection = @import("connection.zig");
pub const info = @import("info.zig");
pub const daemon_output = @import("daemon_output.zig");
pub const lazy_connection = @import("lazy_connection.zig");
pub const ssh_remote = @import("ssh_remote.zig");
pub const ssh_connection = @import("ssh_connection.zig");
pub const remote_path = @import("remote_path.zig");
pub const remote_env = @import("remote_env.zig");
pub const RemoteExecutionEnv = remote_env.RemoteExecutionEnv;
test {
    _ = frame;
    _ = ssh;
    _ = deploy;
    _ = ssh_process;
    _ = metadata;
    _ = files;
    _ = connection;
    _ = info;
    _ = daemon_output;
    _ = lazy_connection;
    _ = ssh_remote;
    _ = ssh_connection;
    _ = remote_path;
    _ = remote_env;
    _ = @import("file_workers_test.zig");
    _ = @import("../durable/watch.zig");
    _ = @import("watch_test.zig");
}
test "native environment contracts match independent captured upstream Node bytes and arguments" {
    const std = @import("std");
    const gpa = std.testing.allocator;
    const captured = try std.json.parseFromSlice(std.json.Value, gpa, @embedFile("fixtures/node-b7df-contracts.json"), .{});
    defer captured.deinit();
    const sources = [_]ssh.Target{
        .{ .host = "gpu-box", .known_hosts_file = "C:\\private space\\known_hosts", .host_key_alias = "pi-env-gpu", .user = "owner", .port = 2222, .identity_file = "id with space", .config_file = "config with space" },
        .{ .host = "gpu", .known_hosts_file = "real", .host_key_alias = "fixed" },
    };
    for (sources, captured.value.object.get("args").?.array.items, 0..) |source, expected, index| {
        var native = try ssh.arguments(gpa, source, index == 0, if (index == 0) null else "temporary");
        defer native.deinit();
        try std.testing.expectEqual(expected.array.items.len, native.values.items.len);
        for (expected.array.items, native.values.items) |wanted, actual| try std.testing.expectEqualStrings(wanted.string, actual);
    }
    const bytes = try frame.encode(gpa, .result, 7, .{ .a = 1 }, &.{ 0, 255, 10 });
    defer gpa.free(bytes);
    const hex = try gpa.alloc(u8, bytes.len * 2);
    defer gpa.free(hex);
    const table = "0123456789abcdef";
    for (bytes, 0..) |byte, index| {
        hex[index * 2] = table[byte >> 4];
        hex[index * 2 + 1] = table[byte & 15];
    }
    try std.testing.expectEqualStrings(captured.value.object.get("goldenHex").?.string, hex);
    for (captured.value.object.get("invalidRejected").?.array.items) |rejected| try std.testing.expect(rejected.bool);
}
