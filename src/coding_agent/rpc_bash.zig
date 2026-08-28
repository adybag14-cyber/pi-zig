//! Conversion between the built-in bash tool's durable text result and RPC data.
const std = @import("std");

pub const ParsedResult = struct {
    output: []u8,
    exit_code: i32,
    cancelled: bool,
    truncated: bool,

    pub fn deinit(self: *ParsedResult, gpa: std.mem.Allocator) void {
        gpa.free(self.output);
        self.* = undefined;
    }
};

fn parseExitCode(content: []const u8) ?i32 {
    if (!std.mem.startsWith(u8, content, "exit=")) return null;
    const end = std.mem.indexOfScalar(u8, content, '\n') orelse content.len;
    return std.fmt.parseInt(i32, content["exit=".len..end], 10) catch null;
}

/// Parse the native bash tool's `exit=N\nstdout:\n...\nstderr:\n...` envelope.
/// Abort/spawn/timeout errors are preserved as output and mapped to a non-zero exit.
pub fn parse(gpa: std.mem.Allocator, content: []const u8, is_error: bool) !ParsedResult {
    const cancelled = std.mem.indexOf(u8, content, "aborted") != null;
    const truncated = std.mem.indexOf(u8, content, "[truncated:") != null;
    const exit_code = parseExitCode(content) orelse if (is_error) @as(i32, 1) else @as(i32, 0);

    const stdout_marker = "\nstdout:\n";
    const stderr_marker = "\nstderr:\n";
    const stdout_at = std.mem.indexOf(u8, content, stdout_marker);
    if (stdout_at) |stdout_index| {
        const stdout_start = stdout_index + stdout_marker.len;
        if (std.mem.indexOfPos(u8, content, stdout_start, stderr_marker)) |stderr_index| {
            const stdout = content[stdout_start..stderr_index];
            const stderr = content[stderr_index + stderr_marker.len ..];
            var out: std.ArrayList(u8) = .empty;
            errdefer out.deinit(gpa);
            try out.appendSlice(gpa, stdout);
            if (stderr.len > 0) {
                if (out.items.len > 0 and out.items[out.items.len - 1] != '\n') try out.append(gpa, '\n');
                try out.appendSlice(gpa, stderr);
            }
            return .{
                .output = try out.toOwnedSlice(gpa),
                .exit_code = exit_code,
                .cancelled = cancelled,
                .truncated = truncated,
            };
        }
    }

    return .{
        .output = try gpa.dupe(u8, content),
        .exit_code = exit_code,
        .cancelled = cancelled,
        .truncated = truncated,
    };
}

pub fn formatJson(gpa: std.mem.Allocator, result: ParsedResult) ![]u8 {
    var out: std.Io.Writer.Allocating = .init(gpa);
    errdefer out.deinit();
    try out.writer.writeAll("{\"output\":");
    try std.json.Stringify.value(result.output, .{}, &out.writer);
    try out.writer.print(",\"exitCode\":{d},\"cancelled\":{s},\"truncated\":{s}}}", .{
        result.exit_code,
        if (result.cancelled) "true" else "false",
        if (result.truncated) "true" else "false",
    });
    return try out.toOwnedSlice();
}

test "RPC bash parser combines stdout and stderr" {
    const gpa = std.testing.allocator;
    var parsed = try parse(gpa, "exit=7\nstdout:\nhello\nstderr:\nwarning", true);
    defer parsed.deinit(gpa);
    try std.testing.expectEqual(@as(i32, 7), parsed.exit_code);
    try std.testing.expectEqualStrings("hello\nwarning", parsed.output);
    try std.testing.expect(!parsed.cancelled);
}

test "RPC bash parser recognizes cancellation and truncation" {
    const gpa = std.testing.allocator;
    var cancelled = try parse(gpa, "bash: aborted (process killed)", true);
    defer cancelled.deinit(gpa);
    try std.testing.expect(cancelled.cancelled);
    try std.testing.expectEqual(@as(i32, 1), cancelled.exit_code);

    var truncated = try parse(gpa, "exit=0\nstdout:\nx\n... [truncated: showing 1/2 lines, limit lines]\nstderr:\n", false);
    defer truncated.deinit(gpa);
    try std.testing.expect(truncated.truncated);
}

test "RPC bash JSON contract uses camel-case fields" {
    const gpa = std.testing.allocator;
    var parsed = try parse(gpa, "exit=0\nstdout:\nok\nstderr:\n", false);
    defer parsed.deinit(gpa);
    const json = try formatJson(gpa, parsed);
    defer gpa.free(json);
    try std.testing.expectEqualStrings("{\"output\":\"ok\",\"exitCode\":0,\"cancelled\":false,\"truncated\":false}", json);
}
