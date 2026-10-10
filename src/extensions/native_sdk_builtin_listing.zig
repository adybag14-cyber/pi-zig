//! Source SDK directory listing over the retained native filesystem owner.
const std = @import("std");
const environment = @import("../durable/execution_env.zig");
const types = @import("../durable/types.zig");
const tools = @import("../agent/tools.zig");
fn failure(gpa: std.mem.Allocator, comptime format: []const u8, args: anytype) !tools.ToolResult {
    return .{ .content = try std.fmt.allocPrint(gpa, format, args), .is_error = true };
}
fn limitValue(value: std.json.Value) f64 {
    return switch (value) {
        .integer => |number| @floatFromInt(number),
        .float => |number| number,
        else => 500,
    };
}
fn less(_: void, left: []u8, right: []u8) bool {
    const count = @min(left.len, right.len);
    for (0..count) |index| {
        const a = std.ascii.toLower(left[index]);
        const b = std.ascii.toLower(right[index]);
        if (a != b) return a < b;
    }
    return left.len < right.len;
}
pub fn execute(gpa: std.mem.Allocator, io: std.Io, cwd: []const u8, input: []const u8, environ: *const std.process.Environ.Map, context: types.Context) !tools.ToolResult {
    var parsed = try std.json.parseFromSlice(std.json.Value, gpa, input, .{});
    defer parsed.deinit();
    if (parsed.value != .object) return error.InvalidBuiltinArguments;
    const requested = if (parsed.value.object.get("path")) |value| if (value == .string and value.string.len != 0) value.string else "." else ".";
    const limit = if (parsed.value.object.get("limit")) |value| limitValue(value) else 500;
    if (context.aborted()) return failure(gpa, "Operation aborted", .{});
    var env = try environment.ExecutionEnv.init(gpa, io, .{ .cwd = cwd, .environ = environ });
    defer env.deinit();
    const absolute_result = try env.absolutePath(requested, context);
    if (absolute_result == .failure) {
        var error_info = absolute_result.failure;
        defer error_info.deinit(gpa);
        return failure(gpa, "{s}", .{error_info.message});
    }
    const absolute = absolute_result.value;
    defer gpa.free(absolute);
    const root_info = std.Io.Dir.cwd().statFile(io, absolute, .{ .follow_symlinks = true }) catch return failure(gpa, "Path not found: {s}", .{absolute});
    if (root_info.kind != .directory) return failure(gpa, "Not a directory: {s}", .{absolute});
    var directory = std.Io.Dir.cwd().openDir(io, absolute, .{ .iterate = true }) catch |err| return failure(gpa, "Cannot read directory: {s}", .{@errorName(err)});
    defer directory.close(io);
    var entries: std.ArrayList([]u8) = .empty;
    defer {
        for (entries.items) |entry| gpa.free(entry);
        entries.deinit(gpa);
    }
    var iterator = directory.iterate();
    while (try iterator.next(io)) |entry| {
        const name = try gpa.dupe(u8, entry.name);
        entries.append(gpa, name) catch |err| {
            gpa.free(name);
            return err;
        };
    }
    std.mem.sort([]u8, entries.items, {}, less);
    var output: std.Io.Writer.Allocating = .init(gpa);
    defer output.deinit();
    var count: usize = 0;
    var limit_reached = false;
    for (entries.items) |entry| {
        if (context.aborted()) return failure(gpa, "Operation aborted", .{});
        if (@as(f64, @floatFromInt(count)) >= limit) {
            limit_reached = true;
            break;
        }
        const full = try std.fs.path.join(gpa, &.{ absolute, entry });
        defer gpa.free(full);
        const info = std.Io.Dir.cwd().statFile(io, full, .{ .follow_symlinks = true }) catch continue;
        if (count != 0) try output.writer.writeByte('\n');
        try output.writer.writeAll(entry);
        if (info.kind == .directory) try output.writer.writeByte('/');
        count += 1;
    }
    if (count == 0) return .{ .content = try gpa.dupe(u8, "(empty directory)"), .is_error = false };
    const bytes_limit = 50 * 1024;
    const truncated = output.written().len > bytes_limit;
    const raw = output.written();
    const end = if (!truncated) raw.len else if (std.mem.lastIndexOfScalar(u8, raw[0..bytes_limit], '\n')) |index| index else 0;
    var formatted: std.Io.Writer.Allocating = .init(gpa);
    defer formatted.deinit();
    try formatted.writer.writeAll(raw[0..end]);
    if (limit_reached or truncated) {
        try formatted.writer.writeAll("\n\n[");
        if (limit_reached) try formatted.writer.print("{d} entries limit reached. Use limit={d} for more", .{ limit, limit * 2 });
        if (truncated) {
            if (limit_reached) try formatted.writer.writeAll(". ");
            try formatted.writer.writeAll("50.0KB limit reached");
        }
        try formatted.writer.writeByte(']');
    }
    const content = try formatted.toOwnedSlice();
    errdefer gpa.free(content);
    const details = if (limit_reached and !truncated) try std.json.Stringify.valueAlloc(gpa, .{ .entryLimitReached = limit }, .{}) else if (truncated) blk: {
        const total_lines = std.mem.count(u8, raw, "\n") + 1;
        const output_lines = if (end == 0) 0 else std.mem.count(u8, raw[0..end], "\n") + 1;
        break :blk try std.json.Stringify.valueAlloc(gpa, .{
            .entryLimitReached = if (limit_reached) @as(?f64, limit) else null,
            .truncation = .{ .truncated = true, .truncatedBy = "bytes", .totalLines = total_lines, .totalBytes = raw.len, .outputLines = output_lines, .outputBytes = end, .lastLinePartial = false, .firstLineExceedsLimit = end == 0, .maxLines = @as(u64, 9_007_199_254_740_991), .maxBytes = bytes_limit },
        }, .{ .emit_null_optional_fields = false });
    } else null;
    return .{ .content = content, .is_error = false, .details_json = details };
}
