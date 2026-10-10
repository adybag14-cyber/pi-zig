//! Long-lived native watch request; change records share the stdout owner.
const std = @import("std");
const input = @import("daemon_input.zig");
const output = @import("daemon_output.zig");
const watch = @import("../durable/watch.zig");
const filesystem = @import("../durable/filesystem.zig");
const gpa = std.heap.page_allocator;
pub const Task = struct {
    input: *input.Input,
    output: *output.Output,
    pending: *input.Pending,
    cwd: []const u8,
    home: []const u8,
    fn sendChange(raw: ?*anyopaque, change: watch.Change) !void {
        const self: *Task = @ptrCast(@alignCast(raw.?));
        if (self.pending.aborted.load(.acquire)) return;
        switch (change) {
            .paths => |paths| try self.output.send(.event, self.pending.frame.id, .{ .kind = "change", .paths = paths }, ""),
            .overflow => try self.output.send(.event, self.pending.frame.id, .{ .kind = "change", .overflow = true, .mode = "polling" }, ""),
            .@"error" => |err| try self.output.send(.event, self.pending.frame.id, .{ .kind = "error", .code = @tagName(err.code), .message = err.message }, ""),
        }
    }
    pub fn run(self: *Task) void {
        defer {
            self.input.complete(self.pending);
            gpa.destroy(self);
        }
        self.respond() catch |err| {
            if (err == error.Canceled) return;
            self.output.send(.remote_error, self.pending.frame.id, .{ .code = "EINVAL", .message = @errorName(err) }, "") catch {};
        };
    }
    fn respond(self: *Task) !void {
        const io = self.input.io;
        const json = self.pending.frame.json.value;
        var targets: std.ArrayList(watch.Target) = .empty;
        defer targets.deinit(gpa);
        var names: std.ArrayList([]const []const u8) = .empty;
        defer {
            for (names.items) |values| gpa.free(values);
            names.deinit(gpa);
        }
        const target_values = json.object.get("targets") orelse return error.WatchNeedsTargets;
        if (target_values != .array) return error.WatchNeedsTargets;
        for (target_values.array.items) |value| {
            if (value != .object) return error.WatchNeedsTargets;
            const path = value.object.get("path") orelse return error.WatchNeedsTargets;
            if (path != .string) return error.WatchNeedsTargets;
            const recursive = value.object.get("recursive");
            var target: watch.Target = .{ .path = path.string, .recursive = recursive != null and recursive.? == .bool and recursive.?.bool };
            if (value.object.get("exclude")) |exclude| if (exclude == .object) {
                const hidden = exclude.object.get("hidden");
                target.exclude.hidden = hidden != null and hidden.? == .bool and hidden.?.bool;
                if (exclude.object.get("names")) |values| if (values == .array) {
                    var owned: std.ArrayList([]const u8) = .empty;
                    defer owned.deinit(gpa);
                    for (values.array.items) |name| if (name == .string) try owned.append(gpa, name.string);
                    const slice = try owned.toOwnedSlice(gpa);
                    errdefer gpa.free(slice);
                    try names.append(gpa, slice);
                    target.exclude.names = slice;
                };
            };
            try targets.append(gpa, target);
        }
        var options: watch.Options = .{};
        if (json.object.get("mode")) |mode| if (mode == .string) {
            if (std.mem.eql(u8, mode.string, "native")) options.mode = .native else if (std.mem.eql(u8, mode.string, "polling")) options.mode = .polling;
        };
        if (json.object.get("pollIntervalMs")) |value| if (value == .integer and value.integer >= 0) {
            options.pollIntervalMs = @intCast(value.integer);
        };
        if (json.object.get("maxDirectories")) |value| if (value == .integer and value.integer >= 0) {
            options.maxDirectories = @intCast(value.integer);
        };
        var fs = try filesystem.FileSystem.init(gpa, io, self.cwd, self.home);
        defer fs.deinit();
        const opened = try watch.Watcher.open(&fs, targets.items, options, sendChange, self, .{ .abort_flag = &self.pending.aborted });
        if (opened == .failure) {
            var failure = opened.failure;
            defer failure.deinit(gpa);
            try self.output.send(.remote_error, self.pending.frame.id, .{ .code = if (failure.code == .permission_denied) "EACCES" else if (failure.code == .aborted) "aborted" else "EINVAL", .message = failure.message, .path = failure.path }, "");
            return;
        }
        const watcher = opened.value;
        defer watcher.deinit();
        try self.output.send(.event, self.pending.frame.id, .{ .kind = "ready", .mode = @tagName(watcher.mode.load(.acquire)) }, "");
        while (!self.pending.aborted.load(.acquire) and !watcher.closed.load(.acquire)) try io.sleep(.fromMilliseconds(20), .awake);
        watcher.close(.{});
        try self.output.send(.result, self.pending.frame.id, std.json.Value{ .object = .empty }, "");
    }
};
