//! Main catalog source; SDK callers resolve their own actual retained session.
const std = @import("std");
const json = @import("../durable/backend/json.zig");
const snapshots = @import("native_catalog_snapshot.zig");
const publisher = @import("native_catalog_publisher.zig");
const configured = @import("../mcp/configured.zig");
pub const State = struct {
    gpa: std.mem.Allocator,
    io: std.Io,
    mutex: std.Io.Mutex = .init,
    subscribers: std.ArrayList(*std.Io.Event) = .empty,
    service: ?*configured.Service = null,
    allowed_names: ?[]const []const u8 = null,
    excluded_names: []const []const u8 = &.{},
    pub fn source(self: *State) publisher.Source {
        return .{ .context = self, .build = build, .subscribe = subscribe, .unsubscribe = unsubscribe, .registration_allowed = registrationAllowed, .native_tool_activatable = nativeToolActivatable };
    }
    fn registrationAllowed(raw: ?*anyopaque, name: []const u8) bool {
        const self: *State = @ptrCast(@alignCast(raw.?));
        const matches = @import("../mcp/config.zig").matches;
        for (self.excluded_names) |pattern| if (matches(pattern, name)) return false;
        const allowed = self.allowed_names orelse return true;
        var filters_mcp = allowed.len == 0;
        for (allowed) |pattern| {
            if (matches(pattern, name)) return true;
            filters_mcp = filters_mcp or std.mem.startsWith(u8, pattern, "mcp__");
        }
        const mcp = std.mem.startsWith(u8, name, "mcp__") or std.mem.eql(u8, name, "list_mcp_resources") or std.mem.eql(u8, name, "list_mcp_resource_templates") or std.mem.eql(u8, name, "read_mcp_resource");
        return !filters_mcp and mcp;
    }
    fn nativeToolActivatable(raw: ?*anyopaque, name: []const u8) bool {
        const self: *State = @ptrCast(@alignCast(raw.?));
        for ([_][]const u8{ "read", "bash", "powershell", "edit", "write", "grep", "find", "ls", "codemode", "tool_search" }) |builtin| if (std.mem.eql(u8, name, builtin)) return true;
        self.mutex.lockUncancelable(self.io);
        const service = self.service;
        self.mutex.unlock(self.io);
        if (service) |mcp| if (mcp.exposureOf(name)) |exposure| return exposure != .hidden;
        return false;
    }
    pub fn deinit(self: *State) void {
        std.debug.assert(self.subscribers.items.len == 0);
        self.subscribers.deinit(self.gpa);
    }
    pub fn bindMcp(self: *State, service: *configured.Service) void {
        service.catalog_mutex.lockUncancelable(service.io);
        service.catalog_changed_context = self;
        service.catalog_changed_fn = changed;
        service.catalog_mutex.unlock(service.io);
        self.mutex.lockUncancelable(self.io);
        self.service = service;
        self.mutex.unlock(self.io);
        changed(self);
    }
    pub fn unbindMcp(self: *State) void {
        self.mutex.lockUncancelable(self.io);
        self.service = null;
        self.mutex.unlock(self.io);
    }
    fn changed(raw: ?*anyopaque) void {
        const self: *State = @ptrCast(@alignCast(raw.?));
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);
        for (self.subscribers.items) |wake| wake.set(self.io);
    }
    fn subscribe(raw: ?*anyopaque, wake: *std.Io.Event) !void {
        const self: *State = @ptrCast(@alignCast(raw.?));
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);
        try self.subscribers.append(self.gpa, wake);
    }
    fn unsubscribe(raw: ?*anyopaque, wake: *std.Io.Event) void {
        const self: *State = @ptrCast(@alignCast(raw.?));
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);
        for (self.subscribers.items, 0..) |candidate, index| if (candidate == wake) {
            _ = self.subscribers.swapRemove(index);
            return;
        };
    }
    fn build(raw: ?*anyopaque, gpa: std.mem.Allocator, features: publisher.Features) !json.Owned {
        const self: *State = @ptrCast(@alignCast(raw.?));
        self.mutex.lockUncancelable(self.io);
        const service = self.service;
        self.mutex.unlock(self.io);
        var snapshot = try snapshots.init(gpa);
        errdefer snapshot.deinit();
        var policy: std.json.Value = .{ .object = .empty };
        const a = snapshot.arena.allocator();
        try policy.object.put(a, "allowed", if (self.allowed_names) |names| try namesValue(a, names) else .null);
        try policy.object.put(a, "excluded", try namesValue(a, self.excluded_names));
        try snapshot.value.object.put(a, "registrationPolicy", policy);
        try snapshots.appendBuiltins(&snapshot, .{ .key = 1, .generation = 1 });
        try appendCore(&snapshot, features);
        if (features.mcp) if (service) |mcp| try snapshots.appendMcp(&snapshot, mcp, .{ .key = 3, .generation = 1 }, .{ .key = 4, .generation = 1 });
        return snapshot;
    }
};
fn namesValue(a: std.mem.Allocator, names: []const []const u8) !std.json.Value {
    var result: std.json.Value = .{ .array = .init(a) };
    for (names) |name| try result.array.append(.{ .string = try a.dupe(u8, name) });
    return result;
}
fn appendCore(snapshot: *json.Owned, features: publisher.Features) !void {
    const a = snapshot.arena.allocator();
    const destination = try snapshots.owner(snapshot, .{ .key = 2, .generation = 1 });
    for ([_][]const u8{ "codemode", "tool_search" }, 0..) |name, index| {
        if ((index == 0 and !features.codemode) or (index == 1 and !features.tool_search)) continue;
        var record: std.json.Value = .{ .object = .empty };
        try record.object.put(a, "definitionId", .{ .integer = @intCast(index + 1) });
        try record.object.put(a, "parameterIdentity", .{ .string = name });
        try record.object.put(a, "parameters", .null);
        var metadata: std.json.Value = .{ .object = .empty };
        try metadata.object.put(a, "name", .{ .string = name });
        try metadata.object.put(a, "label", .{ .string = name });
        try metadata.object.put(a, "exposure", .{ .string = "model-only" });
        const description = if (index == 0) try @import("../mcp/codemode_loadout.zig").description(a, &.{}, .{}) else @import("../mcp/tool_search.zig").description;
        try metadata.object.put(a, "description", .{ .string = description });
        if (index == 0) {
            var guidelines: std.json.Value = .{ .array = .init(a) };
            try guidelines.array.append(.{ .string = "Use codemode to batch independent tool calls (Promise.allSettled), chain them, or filter large output, instead of many separate calls." });
            try metadata.object.put(a, "promptGuidelines", guidelines);
            try record.object.put(a, "promptGuidelinesId", .{ .integer = 1 });
        }
        try record.object.put(a, "metadata", metadata);
        var info: std.json.Value = .{ .object = .empty };
        try info.object.put(a, "path", .{ .string = if (index == 0) "builtin:codemode" else "builtin:tool-search" });
        inline for (.{ .{ "source", "builtin" }, .{ "scope", "temporary" }, .{ "origin", "top-level" } }) |field| try info.object.put(a, field[0], .{ .string = field[1] });
        try record.object.put(a, "sourceInfo", info);
        try record.object.put(a, "sourceInfoId", .{ .integer = @intCast(index + 1) });
        try destination.object.getPtr("records").?.array.append(record);
    }
}
