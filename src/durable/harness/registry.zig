//! Immutable native extension metadata snapshots  and  retained tool capabilities.
const std = @import("std");
pub const json = @import("../backend/json.zig");
const types = @import("../types.zig");
const output = @import("../output_window.zig");
const values = @import("../tool_types.zig");
pub const builtin_tasks = [_][]const u8{ "pi.generation", "pi.tool", "pi.compaction" };
pub const Resource = struct {
    context: ?*anyopaque = null,
    retain: ?*const fn (?*anyopaque) void = null,
    release: ?*const fn (?*anyopaque) void = null,
};
pub const Prepare = *const fn (?*anyopaque, std.mem.Allocator, json.Value, types.Context) anyerror!json.Value;
pub const Execution = struct { result: values.Result, contentProvided: bool = false, content: ?json.Value = null, details: ?json.Value = null, control: ?json.Value = null };
pub const Execute = *const fn (?*anyopaque, json.Value, *anyopaque, types.Context) anyerror!Execution;
pub const Tool = struct { name: []const u8, description: []const u8 = "", parameters: json.Value, prepare: ?Prepare = null, execute: Execute, resource: Resource = .{}, limits: output.Limits = .{ .retain = .head }, replaySafe: bool = false, sequential: bool = false };
pub const Extension = struct { name: []const u8, tools: []const Tool = &.{}, sections: []const []const u8 = &.{}, tasks: []const []const u8 = &.{} };
pub const ToolRef = struct { extension: []const u8, tool: Tool };
pub const Snapshot = struct {
    gpa: std.mem.Allocator,
    arena: std.heap.ArenaAllocator,
    extensions: []Extension,
    refs: std.atomic.Value(usize) = .init(1),
    resourcesRetained: bool = false,
    pub fn retain(self: *Snapshot) *Snapshot {
        _ = self.refs.fetchAdd(1, .monotonic);
        return self;
    }
    pub fn release(self: *Snapshot) void {
        if (self.refs.fetchSub(1, .acq_rel) != 1) return;
        if (self.resourcesRetained) for (self.extensions) |extension| for (extension.tools) |tool| if (tool.resource.release) |release_resource| release_resource(tool.resource.context);
        const gpa = self.gpa;
        self.arena.deinit();
        gpa.destroy(self);
    }
    pub fn getExtension(self: *const Snapshot, name: []const u8) ?Extension {
        for (self.extensions) |item| if (std.mem.eql(u8, item.name, name)) return item;
        return null;
    }
    pub fn findTool(self: *const Snapshot, name: []const u8, selectedExtensions: ?[]const []const u8) ?ToolRef {
        var selected: ?ToolRef = null;
        if (selectedExtensions) |names| {
            for (names, 0..) |extension_name, index| {
                var duplicate = false;
                for (names[0..index]) |earlier| if (std.mem.eql(u8, earlier, extension_name)) {
                    duplicate = true;
                    break;
                };
                if (duplicate) continue;
                if (self.getExtension(extension_name)) |item| for (item.tools) |implementation| if (std.mem.eql(u8, implementation.name, name)) {
                    selected = .{ .extension = item.name, .tool = implementation };
                };
            }
        } else for (self.extensions) |item| for (item.tools) |implementation| if (std.mem.eql(u8, implementation.name, name)) {
            selected = .{ .extension = item.name, .tool = implementation };
        };
        return selected;
    }
    pub fn taskNames(self: *const Snapshot, gpa: std.mem.Allocator) ![]const []const u8 {
        var names: std.ArrayList([]const u8) = .empty;
        defer names.deinit(gpa);
        try names.appendSlice(gpa, &builtin_tasks);
        for (self.extensions) |item| try names.appendSlice(gpa, item.tasks);
        return names.toOwnedSlice(gpa);
    }
    fn create(gpa: std.mem.Allocator, input: []const Extension) !*Snapshot {
        const self = try gpa.create(Snapshot);
        self.* = .{ .gpa = gpa, .arena = std.heap.ArenaAllocator.init(gpa), .extensions = &.{} };
        errdefer self.release();
        const allocator = self.arena.allocator();
        var seen_tasks: std.StringHashMap(void) = .init(allocator);
        for (builtin_tasks) |name| try seen_tasks.put(name, {});
        const extensions = try allocator.alloc(Extension, input.len);
        for (input, extensions) |source, *destination| {
            destination.* = .{ .name = try allocator.dupe(u8, source.name) };
            const tools = try allocator.alloc(Tool, source.tools.len);
            var seen_tools: std.StringHashMap(void) = .init(allocator);
            for (source.tools, tools) |implementation, *copy| {
                if (seen_tools.contains(implementation.name)) return error.DuplicateExtensionTool;
                try seen_tools.put(implementation.name, {});
                copy.* = implementation;
                copy.name = try allocator.dupe(u8, implementation.name);
                copy.description = try allocator.dupe(u8, implementation.description);
                copy.parameters = try json.clone(allocator, implementation.parameters);
            }
            destination.tools = tools;
            const sections = try allocator.alloc([]const u8, source.sections.len);
            var seen_sections: std.StringHashMap(void) = .init(allocator);
            for (source.sections, sections) |name, *copy| {
                if (!validSection(name)) return error.InvalidSectionKey;
                if (std.mem.eql(u8, name, "instructions")) return error.ReservedSectionKey;
                if (seen_sections.contains(name)) return error.DuplicateExtensionSection;
                try seen_sections.put(name, {});
                copy.* = try allocator.dupe(u8, name);
            }
            destination.sections = sections;
            const tasks = try allocator.alloc([]const u8, source.tasks.len);
            for (source.tasks, tasks) |name, *copy| {
                if (seen_tasks.contains(name)) return error.DuplicateTaskDefinition;
                try seen_tasks.put(name, {});
                copy.* = try allocator.dupe(u8, name);
            }
            destination.tasks = tasks;
        }
        self.extensions = extensions;
        for (extensions) |item| for (item.tools) |implementation| if (implementation.resource.retain) |retain_resource| retain_resource(implementation.resource.context);
        self.resourcesRetained = true;
        return self;
    }
};
fn validSection(name: []const u8) bool {
    if (name.len == 0 or name[0] < 'a' or name[0] > 'z') return false;
    for (name[1..]) |byte| if (!((byte >= 'a' and byte <= 'z') or std.ascii.isDigit(byte) or byte == '_' or byte == '-')) return false;
    return true;
}
pub const Listener = *const fn (?*anyopaque) anyerror!void;
const Subscription = struct { id: u64, callback: Listener, context: ?*anyopaque };
pub const Registry = struct {
    gpa: std.mem.Allocator,
    io: std.Io,
    current: *Snapshot,
    mutex: std.Io.Mutex = .init,
    listeners: std.ArrayList(Subscription) = .empty,
    nextSubscription: u64 = 1,
    lastRejection: ?[]u8 = null,
    pub fn init(gpa: std.mem.Allocator, io: std.Io) !Registry {
        return .{ .gpa = gpa, .io = io, .current = try Snapshot.create(gpa, &.{}) };
    }
    pub fn deinit(self: *Registry) void {
        self.current.release();
        self.listeners.deinit(self.gpa);
        if (self.lastRejection) |message| self.gpa.free(message);
        self.* = undefined;
    }
    pub fn snapshot(self: *Registry) *Snapshot {
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);
        return self.current.retain();
    }
    pub fn subscribe(self: *Registry, callback: Listener, context: ?*anyopaque) !u64 {
        try self.mutex.lock(self.io);
        defer self.mutex.unlock(self.io);
        const id = self.nextSubscription;
        try self.listeners.append(self.gpa, .{ .id = id, .callback = callback, .context = context });
        self.nextSubscription += 1;
        return id;
    }
    pub fn unsubscribe(self: *Registry, id: u64) void {
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);
        for (self.listeners.items, 0..) |item, index| if (item.id == id) {
            _ = self.listeners.orderedRemove(index);
            return;
        };
    }
    pub fn install(self: *Registry, extension: Extension) !void {
        try self.replace(extension.name, extension);
    }
    pub fn uninstall(self: *Registry, name: []const u8) !void {
        try self.replace(name, null);
    }
    fn replace(self: *Registry, name: []const u8, replacement: ?Extension) !void {
        try self.mutex.lock(self.io);
        var locked = true;
        defer if (locked) self.mutex.unlock(self.io);
        var next: std.ArrayList(Extension) = .empty;
        defer next.deinit(self.gpa);
        var found = false;
        for (self.current.extensions) |item| {
            if (std.mem.eql(u8, item.name, name)) {
                found = true;
                if (replacement) |new| try next.append(self.gpa, new);
            } else try next.append(self.gpa, item);
        }
        if (!found) {
            if (replacement) |new| try next.append(self.gpa, new) else return;
        }
        const built = Snapshot.create(self.gpa, next.items) catch |err| {
            if (err == error.OutOfMemory) return err;
            if (replacement) |extension| {
                const message = try rejectionMessage(self.gpa, extension, err, next.items);
                if (self.lastRejection) |old| self.gpa.free(old);
                self.lastRejection = message;
            }
            return err;
        };
        var adopted = false;
        defer if (!adopted) built.release();
        const listeners = try self.gpa.dupe(Subscription, self.listeners.items);
        defer self.gpa.free(listeners);
        const old = self.current;
        self.current = built;
        adopted = true;
        self.mutex.unlock(self.io);
        locked = false;
        old.release();
        // Listener errors occur after publication, as in the source registry.
        for (listeners) |listener| try listener.callback(listener.context);
    }
};
fn rejectionMessage(gpa: std.mem.Allocator, extension: Extension, err: anyerror, all: []const Extension) ![]u8 {
    if (err == error.DuplicateExtensionTool) {
        for (extension.tools, 0..) |tool, index| for (extension.tools[0..index]) |earlier| if (std.mem.eql(u8, tool.name, earlier.name)) return std.fmt.allocPrint(gpa, "Extension {s} has two tools named {s}", .{ extension.name, tool.name });
    }
    if (err == error.ReservedSectionKey) return gpa.dupe(u8, "Section key instructions is reserved for the agent's instructions");
    if (err == error.InvalidSectionKey) {
        for (extension.sections) |name| if (!validSection(name)) {
            const quoted = try json.stringify(gpa, .{ .string = name });
            defer gpa.free(quoted);
            return std.fmt.allocPrint(gpa, "Section key {s} must match /^[a-z][a-z0-9_-]*$/", .{quoted});
        };
    }
    if (err == error.DuplicateExtensionSection) {
        for (extension.sections, 0..) |name, index| for (extension.sections[0..index]) |earlier| if (std.mem.eql(u8, name, earlier)) return std.fmt.allocPrint(gpa, "Extension {s} has two sections with key {s}", .{ extension.name, name });
    }
    if (err == error.DuplicateTaskDefinition) {
        var seen: std.StringHashMap(void) = .init(gpa);
        defer seen.deinit();
        for (builtin_tasks) |name| try seen.put(name, {});
        for (all) |item| for (item.tasks) |name| {
            if (seen.contains(name)) return std.fmt.allocPrint(gpa, "Task {s} of extension {s} is already installed", .{ name, item.name });
            try seen.put(name, {});
        };
    }
    return gpa.dupe(u8, @errorName(err));
}

test "durable registry replacement is atomic and listeners can reenter after snapshot publication" {
    const gpa = std.testing.allocator;
    var owner = try Registry.init(gpa, std.testing.io);
    defer owner.deinit();
    const Handler = struct {
        owner: *Registry,
        called: usize = 0,
        fn callback(state: ?*anyopaque) !void {
            const self: *@This() = @ptrCast(@alignCast(state.?));
            self.called += 1;
            const snapshot = self.owner.snapshot();
            defer snapshot.release();
            try std.testing.expect(snapshot.getExtension("one") != null);
        }
        fn execute(_: ?*anyopaque, _: json.Value, _: *anyopaque, _: types.Context) !Execution {
            return .{ .result = .{ .value = .{} } };
        }
    };
    var handler: Handler = .{ .owner = &owner };
    _ = try owner.subscribe(Handler.callback, &handler);
    const tool: Tool = .{ .name = "tool", .parameters = .{ .object = .empty }, .execute = Handler.execute };
    try owner.install(.{ .name = "one", .tools = &.{tool}, .tasks = &.{"custom"}, .sections = &.{"valid-key"} });
    const before = owner.snapshot();
    defer before.release();
    try std.testing.expectError(error.DuplicateExtensionTool, owner.install(.{ .name = "one", .tools = &.{ tool, tool } }));
    try std.testing.expectError(error.DuplicateTaskDefinition, owner.install(.{ .name = "two", .tasks = &.{"custom"} }));
    try std.testing.expectError(error.ReservedSectionKey, owner.install(.{ .name = "two", .sections = &.{"instructions"} }));
    const after = owner.snapshot();
    defer after.release();
    try std.testing.expect(before == after);
    try std.testing.expectEqual(@as(usize, 1), handler.called);
    const listener = struct {
        fn fail(_: ?*anyopaque) !void {
            return error.OriginalRegistryListener;
        }
    };
    _ = try owner.subscribe(listener.fail, null);
    try std.testing.expectError(error.OriginalRegistryListener, owner.install(.{ .name = "two" }));
    const published = owner.snapshot();
    defer published.release();
    try std.testing.expect(published.getExtension("two") != null);
}

test "durable registry allocator failures retain the previously published snapshot" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, struct {
        fn run(gpa: std.mem.Allocator) !void {
            var owner = try Registry.init(gpa, std.testing.io);
            defer owner.deinit();
            try owner.install(.{ .name = "first", .tasks = &.{"first-task"} });
            const before = owner.snapshot();
            defer before.release();
            owner.install(.{ .name = "second", .tasks = &.{"second-task"}, .sections = &.{"section"} }) catch |err| {
                const actual = owner.snapshot();
                defer actual.release();
                try std.testing.expect(before == actual);
                return err;
            };
            try std.testing.expectEqual(@as(usize, 1), before.extensions.len);
            const after = owner.snapshot();
            defer after.release();
            try std.testing.expectEqual(@as(usize, 2), after.extensions.len);
        }
    }.run, .{});
}

test "durable registry metadata resolution and rejection messages match actual b7df classes" {
    const gpa = std.testing.allocator;
    var fixture = try json.Owned.parse(gpa, @embedFile("../fixtures/session_harness_b7df.json"));
    defer fixture.deinit();
    const expected = try json.required(fixture.value, "registry");
    var owner = try Registry.init(gpa, std.testing.io);
    defer owner.deinit();
    const Handler = struct {
        fn execute(_: ?*anyopaque, _: json.Value, _: *anyopaque, _: types.Context) !Execution {
            return .{ .result = .{ .value = .{} } };
        }
    };
    const a: Tool = .{ .name = "shared", .description = "A", .parameters = .{ .object = .empty }, .execute = Handler.execute };
    const b: Tool = .{ .name = "shared", .description = "B", .parameters = .{ .object = .empty }, .execute = Handler.execute };
    try owner.install(.{ .name = "a", .tools = &.{a} });
    const previous = owner.snapshot();
    defer previous.release();
    try owner.install(.{ .name = "b", .tools = &.{b} });
    const current = owner.snapshot();
    defer current.release();
    try std.testing.expectEqualStrings(try json.asString(try json.required(expected, "winner")), current.findTool("shared", null).?.tool.description);
    try std.testing.expectEqualStrings(try json.asString(try json.required(expected, "deduplicatedWinner")), current.findTool("shared", &.{ "a", "b", "a" }).?.tool.description);
    const same: Tool = .{ .name = "same", .parameters = .{ .object = .empty }, .execute = Handler.execute };
    const errors = (try json.required(expected, "errors")).array.items;
    try std.testing.expectError(error.DuplicateExtensionTool, owner.install(.{ .name = "dup", .tools = &.{ same, same } }));
    try std.testing.expectEqualStrings(errors[0].string, owner.lastRejection.?);
    try std.testing.expectError(error.ReservedSectionKey, owner.install(.{ .name = "section", .sections = &.{"instructions"} }));
    try std.testing.expectEqualStrings(errors[1].string, owner.lastRejection.?);
    try std.testing.expectError(error.DuplicateTaskDefinition, owner.install(.{ .name = "task", .tasks = &.{"pi.tool"} }));
    try std.testing.expectEqualStrings(errors[2].string, owner.lastRejection.?);
    try owner.uninstall("a");
    const after = owner.snapshot();
    defer after.release();
    try std.testing.expectEqualStrings((try json.required(expected, "currentNames")).array.items[0].string, after.extensions[0].name);
    try std.testing.expectEqualStrings((try json.required(expected, "previousNames")).array.items[0].string, previous.extensions[0].name);
    const names = try after.taskNames(gpa);
    defer gpa.free(names);
    const builtins = (try json.required(expected, "builtins")).array.items;
    try std.testing.expectEqual(names.len, builtins.len);
    for (names, builtins) |name, value| try std.testing.expectEqualStrings(value.string, name);
}
