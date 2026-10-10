//! SDK search results retain Source path/line and limit formatting. Process
//! execution uses the native owned shell boundary and never enters the VM.
const std = @import("std");
const tools = @import("../agent/tools.zig");
const manager = @import("../agent/tool_manager.zig");
const env_mod = @import("../durable/execution_env.zig");
const shell = @import("../durable/shell.zig");
const types = @import("../durable/types.zig");
const truncation = @import("native_sdk_search_truncation.zig");
const Capture = struct {
    gpa: std.mem.Allocator,
    stdout: std.Io.Writer.Allocating,
    stderr: std.Io.Writer.Allocating,
    fn receive(raw: ?*anyopaque, text: []const u8, _: types.Context, info: shell.OutputInfo) !void {
        const self: *Capture = @ptrCast(@alignCast(raw.?));
        const target = if (info.stream == .stdout) &self.stdout else &self.stderr;
        if (target.written().len + text.len > 16 * 1024 * 1024) return error.NativeSearchOutputLimit;
        try target.writer.writeAll(text);
    }
};
fn field(input: std.json.Value, name: []const u8) ?std.json.Value {
    return if (input == .object) input.object.get(name) else null;
}
fn textField(input: std.json.Value, name: []const u8) ?[]const u8 {
    const value = field(input, name) orelse return null;
    return if (value == .string) value.string else null;
}
fn numberField(input: std.json.Value, name: []const u8, default: f64) f64 {
    return if (field(input, name)) |value| switch (value) {
        .integer => |number| @floatFromInt(number),
        .float => |number| number,
        else => default,
    } else default;
}
fn flag(input: std.json.Value, name: []const u8) bool {
    const value = field(input, name) orelse return false;
    return value == .bool and value.bool;
}
fn failed(gpa: std.mem.Allocator, text: []const u8) !tools.ToolResult {
    return .{ .content = try gpa.dupe(u8, text), .is_error = true };
}
fn relative(gpa: std.mem.Allocator, root: []const u8, path: []const u8, directory: bool) ![]u8 {
    const result = if (directory) try std.fs.path.relative(gpa, ".", null, root, path) else try gpa.dupe(u8, std.fs.path.basename(path));
    for (result) |*byte| if (byte.* == '\\') {
        byte.* = '/';
    };
    return result;
}
fn appendLine(out: *std.Io.Writer.Allocating, path: []const u8, line: u64, separator: u8, text: []const u8, truncated: *bool) !void {
    if (out.written().len != 0) try out.writer.writeByte('\n');
    var units: usize = 0;
    var end: usize = 0;
    var half: ?u16 = null;
    while (end < text.len and units < 500) {
        const size = try std.unicode.utf8ByteSequenceLength(text[end]);
        const codepoint = try std.unicode.utf8Decode(text[end..][0..size]);
        if (codepoint > 0xffff and units == 499) {
            // String.slice can retain a lone high surrogate. WTF-8 carries
            // it to the owner VM's JSON string boundary without replacement.
            half = @intCast(0xd800 + ((codepoint - 0x10000) >> 10));
            break;
        }
        units += if (codepoint > 0xffff) @as(usize, 2) else 1;
        end += size;
    }
    try out.writer.print("{s}{c}{d}{c} {s}", .{ path, separator, line, separator, text[0..end] });
    if (half) |surrogate| {
        const bytes = [_]u8{ @intCast(0xe0 | (surrogate >> 12)), @intCast(0x80 | ((surrogate >> 6) & 0x3f)), @intCast(0x80 | (surrogate & 0x3f)) };
        try out.writer.writeAll(&bytes);
    }
    if (end < text.len) {
        try out.writer.writeAll("... [truncated]");
        truncated.* = true;
    }
}
pub fn grep(ctx: tools.ToolContext, input: []const u8) !tools.ToolResult {
    const gpa = ctx.gpa;
    var parsed = try std.json.parseFromSlice(std.json.Value, gpa, input, .{});
    defer parsed.deinit();
    const args = parsed.value;
    const pattern = textField(args, "pattern") orelse return error.InvalidBuiltinArguments;
    const limit = @max(1, numberField(args, "limit", 100));
    const context_lines: usize = @intFromFloat(@max(0, @min(100000, numberField(args, "context", 0))));
    if (ctx.abort_flag) |abort| if (@atomicLoad(bool, abort, .acquire)) return failed(gpa, "Operation aborted");
    const executable = (try manager.ensure(gpa, ctx.io, ctx.environ, .rg, .{})) orelse return failed(gpa, "ripgrep (rg) is not available and could not be downloaded");
    defer gpa.free(executable);
    var empty_environment: std.process.Environ.Map = .init(gpa);
    defer empty_environment.deinit();
    var env = try env_mod.ExecutionEnv.init(gpa, ctx.io, .{ .cwd = ctx.cwd, .environ = ctx.environ orelse &empty_environment });
    defer env.deinit();
    const context: types.Context = .{ .abort_flag = if (ctx.abort_flag) |abort| @ptrCast(abort) else null };
    const absolute = try env.absolutePath(textField(args, "path") orelse ".", context);
    if (absolute == .failure) {
        var err = absolute.failure;
        defer err.deinit(gpa);
        return failed(gpa, err.message);
    }
    const root = absolute.value;
    defer gpa.free(root);
    const stat = std.Io.Dir.cwd().statFile(ctx.io, root, .{ .follow_symlinks = true }) catch {
        const message = try std.fmt.allocPrint(gpa, "Path not found: {s}", .{root});
        return .{ .content = message, .is_error = true };
    };
    var argv: std.ArrayList([]const u8) = .empty;
    defer argv.deinit(gpa);
    try argv.appendSlice(gpa, &.{ executable, "--json", "--line-number", "--color=never", "--hidden" });
    if (flag(args, "ignoreCase")) try argv.append(gpa, "--ignore-case");
    if (flag(args, "literal")) try argv.append(gpa, "--fixed-strings");
    if (textField(args, "glob")) |glob| try argv.appendSlice(gpa, &.{ "--glob", glob });
    try argv.appendSlice(gpa, &.{ "--", pattern, root });
    var capture: Capture = .{ .gpa = gpa, .stdout = .init(gpa), .stderr = .init(gpa) };
    defer capture.stdout.deinit();
    defer capture.stderr.deinit();
    var executed = try env.exec(.{ .argv = argv.items }, .{ .onOutput = Capture.receive, .output_context = &capture }, context);
    defer switch (executed) {
        .value => |*result| result.deinit(gpa),
        .failure => |*err| err.deinit(gpa),
    };
    if (executed == .failure) return failed(gpa, if (executed.failure.code == .aborted) "Operation aborted" else executed.failure.message);
    if (executed.value.exitCode != 0 and executed.value.exitCode != 1) return failed(gpa, std.mem.trim(u8, capture.stderr.written(), " \r\n\t"));
    var formatted: std.Io.Writer.Allocating = .init(gpa);
    defer formatted.deinit();
    var count: usize = 0;
    var lines_truncated = false;
    var events = std.mem.splitScalar(u8, capture.stdout.written(), '\n');
    while (events.next()) |event_json| {
        if (@as(f64, @floatFromInt(count)) >= limit) break;
        var event = std.json.parseFromSlice(std.json.Value, gpa, event_json, .{}) catch continue;
        defer event.deinit();
        if (!std.mem.eql(u8, textField(event.value, "type") orelse "", "match")) continue;
        const data = field(event.value, "data") orelse continue;
        const path = textField(field(data, "path") orelse continue, "text") orelse continue;
        const line_number = field(data, "line_number") orelse continue;
        if (line_number != .integer or line_number.integer <= 0) continue;
        const number: u64 = @intCast(line_number.integer);
        const display = try relative(gpa, root, path, stat.kind == .directory);
        defer gpa.free(display);
        count += 1;
        if (context_lines == 0) {
            const source = textField(field(data, "lines") orelse continue, "text") orelse continue;
            const clean = try std.mem.replaceOwned(u8, gpa, std.mem.trimEnd(u8, source, "\n"), "\r", "");
            defer gpa.free(clean);
            try appendLine(&formatted, display, number, ':', clean, &lines_truncated);
        } else {
            const bytes = std.Io.Dir.cwd().readFileAlloc(ctx.io, path, gpa, .limited(16 * 1024 * 1024)) catch {
                try appendLine(&formatted, display, number, ':', "(unable to read file)", &lines_truncated);
                continue;
            };
            defer gpa.free(bytes);
            const clean = try std.mem.replaceOwned(u8, gpa, bytes, "\r", "");
            defer gpa.free(clean);
            var lines = std.mem.splitScalar(u8, clean, '\n');
            var index: u64 = 1;
            const first = number - @min(number - 1, context_lines);
            const last = number +| context_lines;
            while (lines.next()) |line| : (index += 1) {
                if (index < first) continue;
                if (index > last) break;
                try appendLine(&formatted, display, index, if (index == number) ':' else '-', line, &lines_truncated);
            }
        }
    }
    if (count == 0) return .{ .content = try gpa.dupe(u8, "No matches found"), .is_error = false };
    const cut = truncation.head(formatted.written());
    var output: std.Io.Writer.Allocating = .init(gpa);
    defer output.deinit();
    try output.writer.writeAll(cut.content);
    const limited = @as(f64, @floatFromInt(count)) >= limit;
    if (limited or cut.truncated or lines_truncated) {
        try output.writer.writeAll("\n\n[");
        if (limited) try output.writer.print("{d} matches limit reached. Use limit={d} for more, or refine pattern", .{ limit, limit * 2 });
        if (cut.truncated) {
            if (limited) try output.writer.writeAll(". ");
            try output.writer.writeAll("50.0KB limit reached");
        }
        if (lines_truncated) {
            if (limited or cut.truncated) try output.writer.writeAll(". ");
            try output.writer.writeAll("Some lines truncated to 500 chars. Use read tool to see full lines");
        }
        try output.writer.writeByte(']');
    }
    const content = try output.toOwnedSlice();
    errdefer gpa.free(content);
    const details = if (limited or cut.truncated or lines_truncated) try std.json.Stringify.valueAlloc(gpa, .{ .matchLimitReached = if (limited) @as(?f64, limit) else null, .truncation = if (cut.truncated) @as(?truncation.Result, cut) else null, .linesTruncated = if (lines_truncated) @as(?bool, true) else null }, .{ .emit_null_optional_fields = false }) else null;
    return .{ .content = content, .is_error = false, .details_json = details };
}

pub fn find(ctx: tools.ToolContext, input: []const u8) !tools.ToolResult {
    return @import("native_sdk_builtin_find.zig").execute(ctx, input);
}
