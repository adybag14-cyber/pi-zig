//! PowerShell runs directly through argv; the environment's shell never parses the script.
const std = @import("std");
const bash = @import("tool_bash.zig");
const types = @import("types.zig");
const shell = @import("shell.zig");
const output = @import("output_window.zig");
pub const Input = bash.Input;
pub const Options = struct {
    commandPrefix: ?[]const u8 = null,
    cwd: ?[]const u8 = null,
    env: ?*const std.process.Environ.Map = null,
    inheritEnv: bool = true,
    onOutput: ?shell.OutputFn = null,
    output_context: ?*anyopaque = null,
    outputWindow: ?output.ShellOutputWindow = null,
    prepare: ?bash.Prepare = null,
    prepare_context: ?*anyopaque = null,
    programs: []const []const u8 = &.{ "pwsh", "powershell" },
};
pub fn execute(gpa: std.mem.Allocator, env: anytype, input: Input, options: Options, context: types.Context) !@import("tool_types.zig").Result {
    return bash.execute(gpa, env, input, .{ .commandPrefix = options.commandPrefix, .cwd = options.cwd, .env = options.env, .inheritEnv = options.inheritEnv, .onOutput = options.onOutput, .output_context = options.output_context, .outputWindow = options.outputWindow, .prepare = options.prepare, .prepare_context = options.prepare_context }, options.programs, context);
}
