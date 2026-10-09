//! SDK read formatting. The durable reader owns path resolution; the SDK
//! facade keeps continuation notices in the returned text, as Source does.
const std = @import("std");
const env_mod = @import("../durable/execution_env.zig");
const types = @import("../durable/types.zig");
const read = @import("../durable/tool_read.zig");
const trunc = @import("../durable/truncate.zig");
const tools = @import("../agent/tools.zig");
fn number(value: std.json.Value) f64 {
    return switch (value) {
        .integer => |n| @floatFromInt(n),
        .float => |n| n,
        else => 0,
    };
}
fn index(value: f64, length: usize) usize {
    if (std.math.isNan(value)) return 0;
    const n = @trunc(value);
    const size: f64 = @floatFromInt(length);
    return @intFromFloat(if (n < 0) @max(size + n, 0) else @min(n, size));
}
pub fn execute(ctx: tools.ToolContext, input: []const u8) !tools.ToolResult {
    const gpa = ctx.gpa;
    var parsed = try std.json.parseFromSlice(std.json.Value, gpa, input, .{});
    defer parsed.deinit();
    const path = parsed.value.object.get("path").?.string;
    var empty_environ: std.process.Environ.Map = .init(gpa);
    defer empty_environ.deinit();
    var env = try env_mod.ExecutionEnv.init(gpa, ctx.io, .{ .cwd = ctx.cwd, .environ = ctx.environ orelse &empty_environ });
    defer env.deinit();
    const context: types.Context = .{ .abort_flag = if (ctx.abort_flag) |flag| @ptrCast(flag) else null };
    const resolved = try read.resolvePath(gpa, &env, path, context);
    if (resolved == .failure) {
        var failure = resolved.failure;
        defer failure.deinit(gpa);
        return .{ .content = try gpa.dupe(u8, failure.message), .is_error = true };
    }
    defer gpa.free(resolved.value);
    const read_result = try env.readBinaryFile(resolved.value, context);
    if (read_result == .failure) {
        var failure = read_result.failure;
        defer failure.deinit(gpa);
        return .{ .content = try gpa.dupe(u8, failure.message), .is_error = true };
    }
    const bytes = read_result.value;
    defer gpa.free(bytes);
    if (@import("../ai/images.zig").detectSupportedMime(bytes) != null)
        return tools.execute(ctx, "read", input);
    const text = try @import("../durable/decode.zig").decode(gpa, bytes, true);
    defer gpa.free(text);
    var lines: std.ArrayList([]const u8) = .empty;
    defer lines.deinit(gpa);
    var iter = std.mem.splitScalar(u8, text, '\n');
    while (iter.next()) |line| try lines.append(gpa, line);
    const offset = if (parsed.value.object.get("offset")) |v| number(v) else 0;
    const start: f64 = if (offset == 0 or std.math.isNan(offset)) 0 else @max(0, offset - 1);
    const total: f64 = @floatFromInt(lines.items.len);
    if (start >= total) return .{ .content = try std.fmt.allocPrint(gpa, "Offset {d} is beyond end of file ({d} lines total)", .{ offset, lines.items.len }), .is_error = true };
    const end = if (parsed.value.object.get("limit")) |v| @min(start + number(v), total) else total;
    const from = index(start, lines.items.len);
    const to = @max(from, index(end, lines.items.len));
    const selected = try std.mem.join(gpa, "\n", lines.items[from..to]);
    defer gpa.free(selected);
    const line_count = if (selected.len == 0) 0 else std.mem.count(u8, selected, "\n") + @as(usize, @intFromBool(!std.mem.endsWith(u8, selected, "\n")));
    const cut = trunc.headOf(selected, line_count, selected.len);
    var output: std.Io.Writer.Allocating = .init(gpa);
    defer output.deinit();
    if (cut.details.firstLineExceedsLimit) {
        const first = lines.items[from];
        const size = try trunc.formatSize(gpa, first.len);
        defer gpa.free(size);
        try output.writer.print("[Line {d} is {s}, exceeds 50.0KB limit. Use bash: sed -n '{d}p' {s} | head -c 51200]", .{ start + 1, size, start + 1, path });
    } else {
        try output.writer.writeAll(cut.content);
        if (cut.details.truncated) {
            const last = start + @as(f64, @floatFromInt(cut.details.outputLines));
            try output.writer.print("\n\n[Showing lines {d}-{d} of {d}{s}. Use offset={d} to continue.]", .{ start + 1, last, lines.items.len, if (cut.details.truncatedBy == .lines) "" else " (50.0KB limit)", last + 1 });
        } else if (parsed.value.object.contains("limit") and end < total) {
            try output.writer.print("\n\n[{d} more lines in file. Use offset={d} to continue.]", .{ total - end, end + 1 });
        }
    }
    const content = try gpa.dupe(u8, output.written());
    errdefer gpa.free(content);
    const details = if (cut.details.truncated) try std.json.Stringify.valueAlloc(gpa, .{ .truncation = .{
        .content = cut.content,
        .truncated = cut.details.truncated,
        .truncatedBy = cut.details.truncatedBy,
        .totalLines = cut.details.totalLines,
        .totalBytes = cut.details.totalBytes,
        .outputLines = cut.details.outputLines,
        .outputBytes = cut.details.outputBytes,
        .lastLinePartial = false,
        .firstLineExceedsLimit = cut.details.firstLineExceedsLimit,
        .maxLines = 2000,
        .maxBytes = 51200,
    } }, .{}) else null;
    return .{ .content = content, .is_error = false, .details_json = details };
}
