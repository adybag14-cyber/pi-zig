//! Native execution tasks with owner-local process groups and framed output.
const std = @import("std");
const commands = @import("../durable/shell.zig");
const windows = @import("../durable/output_window.zig");
const transport = @import("daemon_input.zig");
const Io = std.Io;
pub const Output = @import("daemon_output.zig").Output;
pub const Task = struct {
    input: *transport.Input,
    output: *Output,
    pending: *transport.Pending,
    environ: *const std.process.Environ.Map,
    cwd: []const u8,
    tmpdir: []const u8,
    parent_owner: *@import("../durable/process_ownership.zig").ParentJob,
    done: std.atomic.Value(bool) = .init(false),
    shell: ?commands.Shell = null,
    const gpa = std.heap.page_allocator;
    fn text(object: std.json.ObjectMap, name: []const u8) ![]const u8 {
        const value = object.get(name) orelse return error.InvalidExecutionRequest;
        if (value != .string) return error.InvalidExecutionRequest;
        return value.string;
    }
    fn outputText(raw: ?*anyopaque, text_value: []const u8, _: @import("../durable/types.zig").Context, info: commands.OutputInfo) !void {
        const self: *Task = @ptrCast(@alignCast(raw.?));
        try self.output.waitForRoom(&self.pending.aborted, &self.pending.killed);
        try self.output.sendBulk(.event, self.pending.frame.id, .{ .kind = "output", .stream = @tagName(info.stream), .skipped = info.skipped }, text_value);
    }
    fn monitor(self: *Task) anyerror!void {
        while (!self.done.load(.acquire)) {
            try self.input.io.sleep(.fromMilliseconds(5), .awake);
            if (self.pending.killed.load(.acquire)) self.shell.?.cleanup(.{});
        }
    }
    pub fn run(self: *Task) void {
        defer {
            self.input.complete(self.pending);
            gpa.destroy(self);
        }
        self.execute() catch |err| self.output.sendBulk(.remote_error, self.pending.frame.id, .{ .code = "spawn_error", .message = @errorName(err) }, "") catch {};
    }
    fn execute(self: *Task) !void {
        const io = self.input.io;
        const object = self.pending.frame.json.value.object;
        const cwd = if (object.get("cwd")) |value| if (value == .string) value.string else return error.InvalidExecutionRequest else self.cwd;
        var environment: std.process.Environ.Map = .init(gpa);
        defer environment.deinit();
        if (object.get("env")) |value| {
            if (value != .object) return error.InvalidExecutionRequest;
            var iterator = value.object.iterator();
            while (iterator.next()) |entry| {
                if (entry.value_ptr.* == .null) continue;
                if (entry.value_ptr.* != .string) return error.InvalidExecutionRequest;
                try environment.put(entry.key_ptr.*, entry.value_ptr.string);
            }
        }
        const shell_path: ?[]const u8 = if (object.get("shellPath")) |value| if (value == .string) value.string else return error.InvalidExecutionRequest else null;
        self.shell = try commands.Shell.init(gpa, io, cwd, self.environ, null, shell_path, self.tmpdir);
        defer self.shell.?.deinit();
        var argv: std.ArrayList([]const u8) = .empty;
        defer argv.deinit(gpa);
        const command: commands.Command = if (object.get("argv")) |value| blk: {
            if (value != .array or value.array.items.len == 0) return error.InvalidExecutionRequest;
            for (value.array.items) |argument| {
                if (argument != .string) return error.InvalidExecutionRequest;
                try argv.append(gpa, argument.string);
            }
            break :blk .{ .argv = argv.items };
        } else .{ .text = try text(object, "command") };
        var options: commands.Options = .{ .cwd = cwd, .env = &environment, .onOutput = outputText, .output_context = self, .parent_owner = self.parent_owner };
        if (object.get("inheritEnv")) |value| {
            if (value != .bool) return error.InvalidExecutionRequest;
            options.inheritEnv = value.bool;
        }
        if (object.get("timeoutMs")) |value| options.timeout = switch (value) {
            .integer => |number| @as(f64, @floatFromInt(number)) / 1000,
            .float => |number| number / 1000,
            else => return error.InvalidExecutionRequest,
        };
        var spill: ?std.json.Parsed(commands.SpillOptions) = null;
        defer if (spill) |parsed| parsed.deinit();
        if (object.get("spill")) |value| if (value != .null) {
            spill = try std.json.parseFromValue(commands.SpillOptions, gpa, value, .{ .ignore_unknown_fields = true });
            options.spill = spill.?.value;
        };
        var window: ?std.json.Parsed(windows.ShellOutputWindow) = null;
        defer if (window) |parsed| parsed.deinit();
        if (object.get("window")) |value| if (value != .null) {
            window = try std.json.parseFromValue(windows.ShellOutputWindow, gpa, value, .{ .ignore_unknown_fields = true });
            options.window = window.?.value;
        };
        var killer = try io.concurrent(monitor, .{self});
        defer {
            self.done.store(true, .release);
            _ = killer.cancel(io) catch {};
        }
        var result = try self.shell.?.exec(command, options, .{ .abort_flag = &self.pending.aborted });
        switch (result) {
            .value => |*value| {
                defer value.deinit(gpa);
                try self.output.sendBulk(.result, self.pending.frame.id, .{ .exitCode = value.exitCode, .spillPath = value.spillPath }, "");
            },
            .failure => |*failure| {
                defer failure.deinit(gpa);
                try self.output.sendBulk(.remote_error, self.pending.frame.id, .{ .code = @tagName(failure.code), .message = failure.message, .spillPath = failure.spillPath }, "");
            },
        }
    }
};
