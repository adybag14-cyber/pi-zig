//! Pi 97195ec3 terminal request validation. Borrowed fields stay with the frame.
const std = @import("std");
pub const Failure = struct { code: []const u8, message: []const u8 };
pub const Request = struct {
    argv: ?std.json.Array,
    cwd: []const u8,
    env: ?std.json.ObjectMap,
    inherit_env: bool,
    cols: u16,
    rows: u16,
};
pub const Parsed = union(enum) { request: Request, failure: Failure };
fn field(json: std.json.Value, name: []const u8) std.json.Value {
    return if (json == .object) json.object.get(name) orelse .null else .null;
}
fn unsigned(value: std.json.Value) ?u64 {
    return switch (value) {
        .integer => |number| if (number >= 0) @intCast(number) else null,
        .number_string => |bytes| std.fmt.parseInt(u64, bytes, 10) catch null,
        else => null,
    };
}
pub fn size(json: std.json.Value, name: []const u8) ?u16 {
    const number = unsigned(field(json, name)) orelse return null;
    return if (number >= 1 and number <= 4096) @intCast(number) else null;
}
pub fn target(json: std.json.Value) ?u32 {
    return @truncate(unsigned(field(json, "target")) orelse return null);
}
pub fn parse(json: std.json.Value) Parsed {
    const raw_argv = field(json, "argv");
    const argv: ?std.json.Array = if (raw_argv == .null) null else blk: {
        const invalid: Parsed = .{ .failure = .{ .code = "EINVAL", .message = "argv must be a non-empty array of strings" } };
        if (raw_argv != .array or raw_argv.array.items.len == 0) return invalid;
        for (raw_argv.array.items) |item| if (item != .string) return invalid;
        break :blk raw_argv.array;
    };
    const cwd = field(json, "cwd");
    if (cwd != .string) return .{ .failure = .{ .code = "EINVAL", .message = "pty needs cwd" } };
    const cols = size(json, "cols") orelse return .{ .failure = .{ .code = "EINVAL", .message = "cols must be between 1 and 4096" } };
    const rows = size(json, "rows") orelse return .{ .failure = .{ .code = "EINVAL", .message = "rows must be between 1 and 4096" } };
    const env = field(json, "env");
    const inherit = field(json, "inheritEnv");
    return .{ .request = .{
        .argv = argv,
        .cwd = cwd.string,
        .env = if (env == .object) env.object else null,
        .inherit_env = if (inherit == .bool) inherit.bool else true,
        .cols = cols,
        .rows = rows,
    } };
}
/// Upstream Windows has no running terminal registry. Validation still precedes
/// ENOTSUP, and control requests check target before resize dimensions.
pub fn windowsFailure(json: std.json.Value) ?Failure {
    const op = field(json, "op");
    if (op != .string) return null;
    if (std.mem.eql(u8, op.string, "pty")) return switch (parse(json)) {
        .failure => |failure| failure,
        .request => .{ .code = "ENOTSUP", .message = "Terminals are not supported on this system yet" },
    };
    if (std.mem.eql(u8, op.string, "ptyWrite") or std.mem.eql(u8, op.string, "ptyResize") or std.mem.eql(u8, op.string, "ptyForeground")) {
        if (unsigned(field(json, "target")) == null) return .{ .code = "EINVAL", .message = "missing field target" };
        return .{ .code = "EBADF", .message = "no running terminal with this id" };
    }
    return null;
}
test "terminal971 validates ordered request fields and Windows control lookup before resize" {
    const cases = .{
        .{ "{\"op\":\"pty\"}", "EINVAL", "pty needs cwd" },
        .{ "{\"op\":\"pty\",\"argv\":[]}", "EINVAL", "argv must be a non-empty array of strings" },
        .{ "{\"op\":\"pty\",\"argv\":[1]}", "EINVAL", "argv must be a non-empty array of strings" },
        .{ "{\"op\":\"pty\",\"argv\":null,\"cwd\":\"\"}", "EINVAL", "cols must be between 1 and 4096" },
        .{ "{\"op\":\"pty\",\"cwd\":\".\",\"cols\":1.0,\"rows\":1}", "EINVAL", "cols must be between 1 and 4096" },
        .{ "{\"op\":\"pty\",\"cwd\":\".\",\"cols\":1,\"rows\":4097}", "EINVAL", "rows must be between 1 and 4096" },
        .{ "{\"op\":\"pty\",\"cwd\":\".\",\"cols\":4096,\"rows\":1}", "ENOTSUP", "Terminals are not supported on this system yet" },
        .{ "{\"op\":\"ptyResize\",\"cols\":0}", "EINVAL", "missing field target" },
        .{ "{\"op\":\"ptyResize\",\"target\":0,\"cols\":0}", "EBADF", "no running terminal with this id" },
        .{ "{\"op\":\"ptyWrite\",\"target\":18446744073709551615}", "EBADF", "no running terminal with this id" },
        .{ "{\"op\":\"ptyForeground\",\"target\":18446744073709551616}", "EINVAL", "missing field target" },
        .{ "{\"op\":\"ptyForeground\",\"target\":1.0}", "EINVAL", "missing field target" },
        .{ "{\"op\":\"ptyForeground\",\"target\":-1}", "EINVAL", "missing field target" },
    };
    inline for (cases) |row| {
        const json = try std.json.parseFromSlice(std.json.Value, std.testing.allocator, row[0], .{});
        defer json.deinit();
        const failure = windowsFailure(json.value).?;
        try std.testing.expectEqualStrings(row[1], failure.code);
        try std.testing.expectEqualStrings(row[2], failure.message);
    }
}
test "terminal971 retains borrowed argv environment and Source fallback defaults" {
    const json = try std.json.parseFromSlice(std.json.Value, std.testing.allocator, "{\"argv\":[\"\"],\"cwd\":\"\",\"cols\":1,\"rows\":4096,\"env\":{\"x\":null},\"inheritEnv\":false}", .{});
    defer json.deinit();
    const request = parse(json.value).request;
    try std.testing.expectEqualStrings("", request.argv.?.items[0].string);
    try std.testing.expect(request.env.?.get("x").? == .null);
    try std.testing.expect(!request.inherit_env);
    try std.testing.expectEqual(@as(u16, 4096), request.rows);
    const fallback = try std.json.parseFromSlice(std.json.Value, std.testing.allocator, "{\"cwd\":\".\",\"cols\":1,\"rows\":1,\"env\":false,\"inheritEnv\":0}", .{});
    defer fallback.deinit();
    const default = parse(fallback.value).request;
    try std.testing.expect(default.inherit_env and default.argv == null and default.env == null);
}
test "terminal971 actual upstream Windows daemon errors replay through the native framed daemon" {
    if (@import("builtin").os.tag != .windows) return error.SkipZigTest;
    const gpa = std.testing.allocator;
    var environ = try std.process.Environ.createMap(std.testing.environ, gpa);
    defer environ.deinit();
    const program = environ.get("PI_TEST_ENV_DAEMON") orelse return error.SkipZigTest;
    const connection = try @import("connection.zig").Connection.start(gpa, std.testing.io, &.{program}, 971);
    defer connection.deinit();
    const captured = try std.json.parseFromSlice(std.json.Value, gpa, @embedFile("fixtures/terminal-971-windows-source.json"), .{});
    defer captured.deinit();
    try std.testing.expectEqual(@as(usize, 21), captured.value.array.items.len);
    for (captured.value.array.items) |row| {
        var object: std.json.ObjectMap = .empty;
        defer object.deinit(gpa);
        var fields = row.object.get("input").?.object.iterator();
        while (fields.next()) |entry| try object.put(gpa, entry.key_ptr.*, entry.value_ptr.*);
        try object.put(gpa, "op", row.object.get("op").?);
        var ticket = try connection.begin(std.json.Value{ .object = object }, "", 971);
        defer ticket.deinit();
        var reply = try ticket.next(10_000);
        defer reply.deinit();
        try std.testing.expectEqual(@import("frame.zig").Kind.remote_error, reply.kind);
        try std.testing.expectEqual(@as(usize, 0), reply.payload.len);
        const expected = row.object.get("failure").?.object;
        try std.testing.expectEqual(expected.count(), reply.json.value.object.count());
        var wanted = expected.iterator();
        while (wanted.next()) |entry| try std.testing.expectEqualStrings(entry.value_ptr.string, reply.json.value.object.get(entry.key_ptr.*).?.string);
    }
}
