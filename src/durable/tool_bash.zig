//! Shared native command-tool preparation, output, diagnostics, and fallback semantics.
const std = @import("std");
const types = @import("types.zig");
const shell = @import("shell.zig");
const values = @import("tool_types.zig");
const output = @import("output_window.zig");
pub const Input = struct { command: []const u8, timeout: ?f64 = null };
pub const Execution = struct { command: []const u8, cwd: []const u8, env: ?*const std.process.Environ.Map, inheritEnv: bool };
pub const Prepare = *const fn (?*anyopaque, *Execution, types.Context) anyerror!void;
pub const Options = struct {
    commandPrefix: ?[]const u8 = null,
    cwd: ?[]const u8 = null,
    env: ?*const std.process.Environ.Map = null,
    inheritEnv: bool = true,
    onOutput: ?shell.OutputFn = null,
    output_context: ?*anyopaque = null,
    outputWindow: ?output.ShellOutputWindow = null,
    prepare: ?Prepare = null,
    prepare_context: ?*anyopaque = null,
};
pub const utf8_output = "try { [Console]::OutputEncoding=[System.Text.Encoding]::UTF8 } catch {}";
pub const powershell_arguments = [_][]const u8{ "-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass", "-Command" };
pub fn execute(gpa: std.mem.Allocator, env: anytype, input: Input, options: Options, programs: ?[]const []const u8, context: types.Context) !values.Result {
    if (input.timeout) |timeout| {
        if (!std.math.isFinite(timeout) or timeout <= 0) return values.messageFailure(gpa, "Invalid timeout: must be a finite number of seconds", error.InvalidTimeout);
        if (timeout > 2147483647.0 / 1000.0) return values.messageFailure(gpa, "Invalid timeout: maximum is 2147483.647 seconds", error.InvalidTimeout);
    }
    const prefixed = if (options.commandPrefix) |prefix| if (prefix.len != 0) try std.fmt.allocPrint(gpa, "{s}\n{s}", .{ prefix, input.command }) else null else null;
    defer if (prefixed) |text| gpa.free(text);
    var execution: Execution = .{ .command = prefixed orelse input.command, .cwd = options.cwd orelse env.cwd(), .env = options.env, .inheritEnv = options.inheritEnv };
    if (options.prepare) |prepare| prepare(options.prepare_context, &execution, context) catch |err| {
        if (err == error.OutOfMemory) return err;
        return values.messageFailure(gpa, @errorName(err), err);
    };
    const script = if (programs != null) try std.fmt.allocPrint(gpa, "{s}\n{s}", .{ utf8_output, execution.command }) else null;
    defer if (script) |text| gpa.free(text);
    const count = if (programs) |program_list| program_list.len else 1;
    if (count == 0) return values.messageFailure(gpa, "No command to run", error.NoCommandToRun);
    const exec_options: shell.Options = .{ .cwd = execution.cwd, .env = execution.env, .inheritEnv = execution.inheritEnv, .timeout = input.timeout, .onOutput = options.onOutput, .output_context = options.output_context, .spill = .{ .afterBytes = 50 * 1024, .afterLines = 2000 }, .window = options.outputWindow };
    var executed: shell.Result = undefined;
    for (0..count) |index| {
        var argv: [7][]const u8 = undefined;
        const command: shell.Command = if (programs) |program_list| blk: {
            argv[0] = program_list[index];
            @memcpy(argv[1..6], &powershell_arguments);
            argv[6] = script.?;
            break :blk .{ .argv = &argv };
        } else .{ .text = execution.command };
        executed = try env.exec(command, exec_options, context);
        if (executed == .value or executed.failure.code != .spawn_error or index + 1 == count) break;
        executed.failure.deinit(gpa);
    }
    var transferred = false;
    defer if (!transferred) switch (executed) {
        .value => |*done| done.deinit(gpa),
        .failure => |*failed| failed.deinit(gpa),
    };
    var value: values.ToolResult = .{};
    errdefer value.deinit(gpa);
    const spill_path = switch (executed) {
        .value => |done| done.spillPath,
        .failure => |failed| failed.spillPath,
    };
    if (spill_path) |path| try value.diagnostic(gpa, .info, "full_output", try std.fmt.allocPrint(gpa, "Full output: {s}", .{path}));
    if (executed == .failure) {
        const failure = executed.failure;
        const message = switch (failure.code) {
            .timeout => try std.fmt.allocPrint(gpa, "Command timed out after {d} seconds", .{input.timeout.?}),
            .aborted => try gpa.dupe(u8, if (context.aborted()) failure.message else "Command aborted"),
            else => if (programs != null and failure.code == .spawn_error and failure.cause != null and (failure.cause.? == error.ProgramNotFound or failure.cause.? == error.FileNotFound)) try std.fmt.allocPrint(gpa, "spawn {s} ENOENT", .{programs.?[programs.?.len - 1]}) else try gpa.dupe(u8, failure.message),
        };
        const diagnostics = value.diagnostics;
        value.diagnostics = .empty;
        transferred = true;
        return .{ .failure = .{ .message = message, .cause = failure.cause, .execution = failure, .diagnostics = diagnostics } };
    }
    if (executed.value.exitCode != 0) {
        const message = try std.fmt.allocPrint(gpa, "Command exited with code {d}", .{executed.value.exitCode});
        const diagnostics = value.diagnostics;
        value.diagnostics = .empty;
        return .{ .failure = .{ .message = message, .diagnostics = diagnostics } };
    }
    return .{ .value = value };
}
