//! Actual Main frontend theme selection and owned native settings persistence.
const std = @import("std");
const ui = @import("ui.zig");
const terminal = @import("terminal_theme_producer.zig");
const settings = @import("../coding_agent/settings.zig");
const themes = @import("../themes/theme.zig");
const render = @import("../tui/render.zig");
pub const Producer = struct {
    const PendingWrite = struct { id: u64, name: []u8 };
    gpa: std.mem.Allocator,
    io: std.Io,
    controller: *ui.Controller,
    terminal: *terminal.Producer,
    agent_dir: ?[]const u8,
    cwd: []const u8,
    trust_project: bool,
    mutex: std.Io.Mutex = .init,
    published: std.ArrayList(*themes.Theme) = .empty,
    setting: ?[]u8 = null,
    project_setting: ?[]u8 = null,
    global_load_failed: bool = false,
    writes: std.ArrayList(PendingWrite) = .empty,
    write_clock: u64 = 0,
    errors: std.ArrayList(settings.Diagnostic) = .empty,
    pub fn init(gpa: std.mem.Allocator, io: std.Io, controller: *ui.Controller, reports: *terminal.Producer, agent_dir: ?[]const u8, cwd: []const u8, trust_project: bool, initial_setting: ?[]const u8) !Producer {
        var self: Producer = .{ .gpa = gpa, .io = io, .controller = controller, .terminal = reports, .agent_dir = agent_dir, .cwd = cwd, .trust_project = trust_project };
        errdefer {
            if (self.setting) |value| gpa.free(value);
            if (self.project_setting) |value| gpa.free(value);
        }
        self.setting = if (initial_setting) |value| try gpa.dupe(u8, value) else null;
        try self.readSettingsScopes();
        return self;
    }
    fn readSettingsScopes(self: *Producer) !void {
        if (self.agent_dir) |directory| {
            const path = try std.fs.path.join(self.gpa, &.{ directory, "settings.json" });
            defer self.gpa.free(path);
            const loaded = settings.loadFile(self.gpa, self.io, path) catch |err| {
                if (err == error.OutOfMemory) return err;
                self.global_load_failed = true;
                return self.readProjectScope();
            };
            var owned = loaded;
            owned.deinit(self.gpa);
            self.global_load_failed = false;
        }
        try self.readProjectScope();
    }
    fn readProjectScope(self: *Producer) !void {
        if (!self.trust_project) return;
        const path = try std.fs.path.join(self.gpa, &.{ self.cwd, ".pi", "settings.json" });
        defer self.gpa.free(path);
        var loaded = settings.loadFile(self.gpa, self.io, path) catch |err| {
            if (err == error.OutOfMemory) return err;
            return;
        };
        defer loaded.deinit(self.gpa);
        const next = if (loaded.theme) |value| try self.gpa.dupe(u8, value) else null;
        if (self.project_setting) |old| self.gpa.free(old);
        self.project_setting = next;
    }
    pub fn attach(self: *Producer) void {
        self.controller.state_mutex.lockUncancelable(self.io);
        defer self.controller.state_mutex.unlock(self.io);
        self.controller.theme_request_fn = request;
        self.controller.theme_request_context = self;
    }
    pub fn syncSetting(self: *Producer, value: ?[]const u8) !void {
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);
        const next = if (value) |text| try self.gpa.dupe(u8, text) else null;
        if (self.setting) |old| self.gpa.free(old);
        self.setting = next;
        try self.readSettingsScopes();
    }
    pub fn deinit(self: *Producer) void {
        // Settings writes belong to the Main settings manager and survive
        // retirement of their originating extension service.
        self.persistThrough(self.write_clock) catch {};
        self.controller.state_mutex.lockUncancelable(self.io);
        self.controller.theme_request_fn = null;
        self.controller.theme_request_context = null;
        self.controller.state_mutex.unlock(self.io);
        // Call only after the owning frontend and all Runtime callback tasks
        // have stopped. Earlier selections can still be borrowed by a paint.
        render.resetTheme();
        for (self.published.items) |value| {
            value.deinit(self.gpa);
            self.gpa.destroy(value);
        }
        self.published.deinit(self.gpa);
        if (self.setting) |value| self.gpa.free(value);
        if (self.project_setting) |value| self.gpa.free(value);
        for (self.writes.items) |value| self.gpa.free(value.name);
        self.writes.deinit(self.gpa);
        for (self.errors.items) |*value| value.deinit(self.gpa);
        self.errors.deinit(self.gpa);
    }
    fn persistThrough(self: *Producer, id: u64) !void {
        while (self.writes.items.len > 0 and self.writes.items[0].id <= id) {
            const pending = self.writes.items[0];
            const directory = self.agent_dir orelse return error.NativeSettingsDirectoryUnavailable;
            settings.setEditableScoped(self.gpa, self.io, directory, self.cwd, self.trust_project, .global, .theme, .{ .string = pending.name }) catch |err| {
                if (err == error.OutOfMemory) return err;
                const path = try std.fs.path.join(self.gpa, &.{ directory, "settings.json" });
                errdefer self.gpa.free(path);
                const message = try std.fmt.allocPrint(self.gpa, "settings could not be saved: {s}", .{@errorName(err)});
                errdefer self.gpa.free(message);
                try self.errors.append(self.gpa, .{ .path = path, .message = message });
            };
            _ = self.writes.orderedRemove(0);
            self.gpa.free(pending.name);
        }
    }
    pub fn reportErrors(self: *Producer) !void {
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);
        for (self.errors.items) |value| {
            const message = try std.fmt.allocPrint(self.gpa, "warning: {s}: {s}", .{ value.path, value.message });
            defer self.gpa.free(message);
            try render.printLine(self.io, message);
        }
        for (self.errors.items) |*value| value.deinit(self.gpa);
        self.errors.clearRetainingCapacity();
    }
    fn request(raw: ?*anyopaque, allocator: std.mem.Allocator, object: *const std.json.ObjectMap) ![]u8 {
        const self: *Producer = @ptrCast(@alignCast(raw.?));
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);
        if (object.get("persistWriteId")) |id| {
            const serial = try @import("component_protocol.zig").identifier(id);
            if (serial == 0 or serial > self.write_clock) return error.InvalidExtensionUiRequest;
            try self.persistThrough(serial);
            return allocator.dupe(u8, "null");
        }
        const resource = object.get("resource") orelse return error.InvalidExtensionUiRequest;
        const identity = object.get("resourceIdentity") orelse return error.InvalidExtensionUiRequest;
        if (identity != .null and identity != .string) return error.InvalidExtensionUiRequest;
        if (resource == .null) {
            try self.terminal.select(null, null);
            render.resetTheme();
        } else {
            if (resource != .object) return error.InvalidExtensionUiRequest;
            const encoded = try std.json.Stringify.valueAlloc(self.gpa, resource, .{});
            defer self.gpa.free(encoded);
            const owned = try self.gpa.create(themes.Theme);
            var parsed = false;
            var published = false;
            defer if (!published) {
                if (parsed) owned.deinit(self.gpa);
                self.gpa.destroy(owned);
            };
            owned.* = try themes.parse(self.gpa, encoded);
            parsed = true;
            try self.published.ensureUnusedCapacity(self.gpa, 1);
            try self.terminal.select(encoded, if (identity == .string) identity.string else null);
            self.published.appendAssumeCapacity(owned);
            published = true;
            render.setTheme(owned);
        }
        // Source updates effective settings now and queues storage writes for
        // after the current JS stack. Project settings retain precedence.
        const requested = object.get("settingName") orelse return error.InvalidExtensionUiRequest;
        var queued: ?u64 = null;
        if (requested != .null) {
            if (requested != .string) return error.InvalidExtensionUiRequest;
            if (self.setting == null or !std.mem.eql(u8, self.setting.?, requested.string)) {
                const next = try self.gpa.dupe(u8, self.project_setting orelse requested.string);
                errdefer self.gpa.free(next);
                if (!self.global_load_failed) {
                    if (self.write_clock >= 9_007_199_254_740_991) return error.NativeThemeWriteClockExhausted;
                    const name = try self.gpa.dupe(u8, requested.string);
                    errdefer self.gpa.free(name);
                    try self.writes.append(self.gpa, .{ .id = self.write_clock + 1, .name = name });
                    self.write_clock += 1;
                    queued = self.write_clock;
                }
                try self.controller.setThemeSetting(next);
                if (self.setting) |value| self.gpa.free(value);
                self.setting = next;
            }
        }
        try self.controller.flush();
        return std.json.Stringify.valueAlloc(allocator, .{ .hasThemeSetting = self.setting != null, .themeSetting = self.setting, .queuedWriteId = queued }, .{});
    }
};
