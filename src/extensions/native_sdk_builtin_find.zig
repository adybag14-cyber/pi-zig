//! Source fd policy over the native owned-process and acquisition boundaries.
const std = @import("std");
const tools = @import("../agent/tools.zig");
const manager = @import("../agent/tool_manager.zig");
const env_mod = @import("../durable/execution_env.zig");
const shell = @import("../durable/shell.zig");
const types = @import("../durable/types.zig");
const truncation = @import("native_sdk_search_truncation.zig");
const Capture = struct {
    stdout: std.Io.Writer.Allocating,
    stderr: std.Io.Writer.Allocating,
    fn receive(raw: ?*anyopaque, bytes: []const u8, _: types.Context, info: shell.OutputInfo) !void {
        const self: *Capture = @ptrCast(@alignCast(raw.?));
        const target = if (info.stream == .stdout) &self.stdout else &self.stderr;
        if (target.written().len + bytes.len > 16 * 1024 * 1024) return error.NativeSearchOutputLimit;
        try target.writer.writeAll(bytes);
    }
};
fn failed(gpa: std.mem.Allocator, message: []const u8) !tools.ToolResult {
    return .{ .content = try gpa.dupe(u8, message), .is_error = true };
}
pub fn execute(ctx: tools.ToolContext, input: []const u8) !tools.ToolResult {
    const gpa = ctx.gpa;
    var parsed = try std.json.parseFromSlice(std.json.Value, gpa, input, .{});
    defer parsed.deinit();
    const args = parsed.value;
    if (args != .object) return error.InvalidBuiltinArguments;
    const pattern = args.object.get("pattern") orelse return error.InvalidBuiltinArguments;
    if (pattern != .string) return error.InvalidBuiltinArguments;
    const limit: f64 = if (args.object.get("limit")) |value| switch (value) {
        .integer => |number| @floatFromInt(number),
        .float => |number| number,
        else => return error.InvalidBuiltinArguments,
    } else 1000;
    const search = if (args.object.get("path")) |value| if (value == .string and value.string.len != 0) value.string else "." else ".";
    var empty: std.process.Environ.Map = .init(gpa);
    defer empty.deinit();
    const environment = ctx.environ orelse &empty;
    var env = try env_mod.ExecutionEnv.init(gpa, ctx.io, .{ .cwd = ctx.cwd, .environ = environment });
    defer env.deinit();
    const context: types.Context = .{ .abort_flag = if (ctx.abort_flag) |flag| @ptrCast(flag) else null };
    const absolute = try env.absolutePath(search, context);
    if (absolute == .failure) {
        var failure = absolute.failure;
        defer failure.deinit(gpa);
        return failed(gpa, failure.message);
    }
    defer gpa.free(absolute.value);
    if (context.aborted()) return failed(gpa, "Operation aborted");
    const executable = (try manager.ensure(gpa, ctx.io, environment, .fd, .{})) orelse return failed(gpa, "fd is not available and could not be downloaded");
    defer gpa.free(executable);
    if (context.aborted()) return failed(gpa, "Operation aborted");
    var argv: std.ArrayList([]const u8) = .empty;
    defer argv.deinit(gpa);
    try argv.appendSlice(gpa, &.{ executable, "--glob", "--color=never", "--hidden" });
    var directory: []const u8 = absolute.value;
    var inside_git = false;
    while (true) {
        const marker = try std.fs.path.join(gpa, &.{ directory, ".git" });
        defer gpa.free(marker);
        if (std.Io.Dir.cwd().access(ctx.io, marker, .{})) |_| {
            inside_git = true;
            break;
        } else |_| {}
        const parent = std.fs.path.dirname(directory) orelse break;
        if (std.mem.eql(u8, parent, directory)) break;
        directory = parent;
    }
    if (!inside_git) try argv.append(gpa, "--no-require-git");
    const limit_string = try std.fmt.allocPrint(gpa, "{d}", .{limit});
    defer gpa.free(limit_string);
    try argv.appendSlice(gpa, &.{ "--max-results", limit_string });
    const full_path = std.mem.indexOfScalar(u8, pattern.string, '/') != null;
    const prefixed = if (full_path and !std.mem.startsWith(u8, pattern.string, "/") and !std.mem.startsWith(u8, pattern.string, "**/") and !std.mem.eql(u8, pattern.string, "**")) try std.fmt.allocPrint(gpa, "**/{s}", .{pattern.string}) else try gpa.dupe(u8, pattern.string);
    defer gpa.free(prefixed);
    const effective = if (@import("builtin").os.tag == .windows and full_path) try std.mem.replaceOwned(u8, gpa, prefixed, "/", "[/\\\\]") else try gpa.dupe(u8, prefixed);
    defer gpa.free(effective);
    if (full_path) try argv.append(gpa, "--full-path");
    try argv.appendSlice(gpa, &.{ "--", effective, absolute.value });
    var capture: Capture = .{ .stdout = .init(gpa), .stderr = .init(gpa) };
    defer capture.stdout.deinit();
    defer capture.stderr.deinit();
    var executed = try env.exec(.{ .argv = argv.items }, .{ .onOutput = Capture.receive, .output_context = &capture }, context);
    defer switch (executed) {
        .value => |*value| value.deinit(gpa),
        .failure => |*failure| failure.deinit(gpa),
    };
    if (executed == .failure) return failed(gpa, if (executed.failure.code == .aborted) "Operation aborted" else executed.failure.message);
    var output: std.Io.Writer.Allocating = .init(gpa);
    defer output.deinit();
    var lines = std.mem.splitScalar(u8, capture.stdout.written(), '\n');
    var count: usize = 0;
    while (lines.next()) |bytes| {
        const line = std.mem.trim(u8, bytes, " \t\r\n");
        if (line.len == 0) continue;
        const path = if (std.fs.path.isAbsolute(line)) try std.fs.path.relative(gpa, ".", null, absolute.value, line) else try gpa.dupe(u8, line);
        defer gpa.free(path);
        for (path) |*byte| if (byte.* == '\\') {
            byte.* = '/';
        };
        if (count != 0) try output.writer.writeByte('\n');
        try output.writer.writeAll(path);
        if ((std.mem.endsWith(u8, line, "/") or std.mem.endsWith(u8, line, "\\")) and !std.mem.endsWith(u8, path, "/")) try output.writer.writeByte('/');
        count += 1;
    }
    if (count == 0) {
        if (executed.value.exitCode != 0) {
            const message = std.mem.trim(u8, capture.stderr.written(), " \t\r\n");
            if (message.len != 0) return failed(gpa, message);
            return .{ .content = try std.fmt.allocPrint(gpa, "fd exited with code {d}", .{executed.value.exitCode}), .is_error = true };
        }
        return .{ .content = try gpa.dupe(u8, "No files found matching pattern"), .is_error = false };
    }
    const cut = truncation.head(output.written());
    const limited = @as(f64, @floatFromInt(count)) >= limit;
    var formatted: std.Io.Writer.Allocating = .init(gpa);
    defer formatted.deinit();
    try formatted.writer.writeAll(cut.content);
    if (limited or cut.truncated) {
        try formatted.writer.writeAll("\n\n[");
        if (limited) try formatted.writer.print("{d} results limit reached. Use limit={d} for more, or refine pattern", .{ limit, limit * 2 });
        if (cut.truncated) {
            if (limited) try formatted.writer.writeAll(". ");
            try formatted.writer.writeAll("50.0KB limit reached");
        }
        try formatted.writer.writeByte(']');
    }
    const content = try formatted.toOwnedSlice();
    errdefer gpa.free(content);
    const details = if (limited or cut.truncated) try std.json.Stringify.valueAlloc(gpa, .{ .resultLimitReached = if (limited) @as(?f64, limit) else null, .truncation = if (cut.truncated) @as(?truncation.Result, cut) else null }, .{ .emit_null_optional_fields = false }) else null;
    return .{ .content = content, .is_error = false, .details_json = details };
}
