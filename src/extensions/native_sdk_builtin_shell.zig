//! SDK shell tools use the native owned-process boundary and Source shell
//! selection, rather than the CLI's text formatter or Windows cmd adapter.
const std = @import("std");
const builtin = @import("builtin");
const shell = @import("../durable/shell.zig");
const startup = @import("../durable/startup.zig");
const output = @import("../durable/output_window.zig");
const types = @import("../durable/types.zig");
const tools = @import("../agent/tools.zig");
pub const Options = struct { shell_path: ?[]const u8 = null, command_prefix: ?[]const u8 = null };
pub const Result = struct {
    result: tools.ToolResult,
    structured_json: ?[]u8 = null,
    reject_result: bool = false,
};
const Capture = struct {
    gpa: std.mem.Allocator,
    display: output.OutputBuffer,
    structured: output.OutputBuffer,
    progress: ?tools.ToolProgressFn,
    progress_context: ?*anyopaque,
    fn accept(raw: ?*anyopaque, text: []const u8, _: types.Context, info: shell.OutputInfo) !void {
        const self: *Capture = @ptrCast(@alignCast(raw.?));
        _ = try self.display.pushText(text, info.skipped);
        _ = try self.structured.pushText(text, null);
        if (self.progress) |progress| {
            var snapshot = try self.display.snapshot();
            defer snapshot.deinit(self.gpa);
            progress(self.progress_context, snapshot.text);
        }
    }
};
pub fn execute(gpa: std.mem.Allocator, io: std.Io, cwd: []const u8, name: []const u8, input: []const u8, environment: *const std.process.Environ.Map, options: Options, abort_flag: *const std.atomic.Value(bool), progress: ?tools.ToolProgressFn, progress_context: ?*anyopaque) !Result {
    var parsed = try std.json.parseFromSlice(std.json.Value, gpa, input, .{});
    defer parsed.deinit();
    if (parsed.value != .object) return error.InvalidBuiltinArguments;
    const command_value = parsed.value.object.get("command") orelse return error.InvalidBuiltinArguments;
    if (command_value != .string) return error.InvalidBuiltinArguments;
    const timeout: ?f64 = if (parsed.value.object.get("timeout")) |value| switch (value) {
        .integer => |number| @floatFromInt(number),
        .float => |number| number,
        else => return error.InvalidBuiltinArguments,
    } else null;
    const powershell = std.mem.eql(u8, name, "powershell");
    if (powershell and builtin.os.tag != .windows) return .{ .result = .{ .content = try gpa.dupe(u8, "The powershell tool is only available on Windows."), .is_error = true }, .reject_result = true };
    const prefixed = if (options.command_prefix) |prefix| if (prefix.len != 0) try std.fmt.allocPrint(gpa, "{s}\n{s}", .{ prefix, command_value.string }) else null else null;
    defer if (prefixed) |text| gpa.free(text);
    const command = prefixed orelse command_value.string;
    const temp_dir = try startup.tempDirectory(gpa, environment);
    defer gpa.free(temp_dir);
    // Source prefers /bin/bash on Unix. The durable default remains its own
    // environment policy, so this explicit SDK choice stays local to factories.
    var owned_shell: ?[]u8 = null;
    defer if (owned_shell) |path| gpa.free(path);
    var selected_shell = options.shell_path;
    if (!powershell and selected_shell == null and builtin.os.tag != .windows) {
        const bin_bash = exists: {
            std.Io.Dir.cwd().access(io, "/bin/bash", .{}) catch break :exists false;
            break :exists true;
        };
        owned_shell = if (bin_bash) try gpa.dupe(u8, "/bin/bash") else startup.resolveProgram(gpa, io, "bash", cwd, environment) catch null;
        selected_shell = owned_shell;
    }
    var runner = try shell.Shell.init(gpa, io, cwd, environment, null, selected_shell, temp_dir);
    defer runner.deinit();
    var capture: Capture = .{
        .gpa = gpa,
        .display = output.OutputBuffer.init(gpa, .{}),
        .structured = output.OutputBuffer.init(gpa, .{ .maxBytes = 1024 * 1024, .maxLines = std.math.maxInt(usize), .retain = .head }),
        .progress = progress,
        .progress_context = progress_context,
    };
    defer capture.display.deinit();
    defer capture.structured.deinit();
    const context: types.Context = .{ .abort_flag = abort_flag };
    const exec_options: shell.Options = .{ .timeout = timeout, .onOutput = Capture.accept, .output_context = &capture, .spill = .{ .afterBytes = 50 * 1024, .afterLines = 2000 } };
    const began = std.Io.Clock.awake.now(io).toMilliseconds();
    var execution = if (!powershell) try runner.exec(.{ .text = command }, exec_options, context) else blk: {
        var executable: ?[]u8 = null;
        for ([_][]const u8{ "pwsh.exe", "powershell.exe" }) |candidate| {
            executable = startup.resolveProgram(gpa, io, candidate, cwd, environment) catch continue;
            break;
        }
        const program = executable orelse return .{ .result = .{ .content = try gpa.dupe(u8, "No PowerShell executable found. Install PowerShell or add powershell.exe/pwsh.exe to PATH."), .is_error = true }, .reject_result = true };
        defer gpa.free(program);
        const script = try std.fmt.allocPrint(gpa, "try {{ [Console]::OutputEncoding=[System.Text.Encoding]::UTF8 }} catch {{}}\n{s}", .{command});
        defer gpa.free(script);
        break :blk try runner.exec(.{ .argv = &.{ program, "-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass", "-Command", script } }, exec_options, context);
    };
    defer switch (execution) {
        .value => |*done| done.deinit(gpa),
        .failure => |*failed| failed.deinit(gpa),
    };
    try capture.display.end();
    try capture.structured.end();
    var display = try capture.display.snapshot();
    defer display.deinit(gpa);
    var full = try capture.structured.snapshot();
    defer full.deinit(gpa);
    if (execution == .failure) {
        const failure = execution.failure;
        const status = switch (failure.code) {
            .aborted => try gpa.dupe(u8, "Command aborted"),
            .timeout => if (timeout) |seconds| try std.fmt.allocPrint(gpa, "Command timed out after {d} seconds", .{seconds}) else try gpa.dupe(u8, failure.message),
            else => try gpa.dupe(u8, failure.message),
        };
        defer gpa.free(status);
        return .{ .result = .{ .content = if (display.text.len == 0) try gpa.dupe(u8, status) else try std.fmt.allocPrint(gpa, "{s}\n\n{s}", .{ display.text, status }), .is_error = true }, .reject_result = true };
    }
    const done = execution.value;
    const text = if (display.text.len == 0) "(no output)" else display.text;
    const content = if (done.exitCode != 0) try std.fmt.allocPrint(gpa, "{s}\n\nCommand exited with code {d}", .{ text, done.exitCode }) else try gpa.dupe(u8, text);
    errdefer gpa.free(content);
    const elapsed = @as(f64, @floatFromInt(std.Io.Clock.awake.now(io).toMilliseconds() - began)) / 1000;
    const structured = try std.json.Stringify.valueAlloc(gpa, .{ .output = full.text, .truncated = full.droppedBytes != 0, .full_output_path = if (full.droppedBytes != 0) done.spillPath else null, .exit_code = done.exitCode, .wall_time_seconds = @round(elapsed * 10) / 10 }, .{ .emit_null_optional_fields = false });
    return .{ .result = .{ .content = content, .is_error = done.exitCode != 0 }, .structured_json = structured };
}
