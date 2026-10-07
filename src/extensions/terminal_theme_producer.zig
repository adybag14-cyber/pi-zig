//! CLI-owned cached terminal reports. C VM snapshots consume Controller's
//! owned ThemeState; no reader or terminal handle crosses the worker boundary.
const std = @import("std");
const reports = @import("../tui/terminal_colors.zig");
const ui = @import("ui.zig");
const state_mod = @import("theme_state.zig");
const Query = struct { collection: reports.Cache, deadline_ms: ?i64, delivery: enum { initial, late, none } = .initial };
pub const Producer = struct {
    gpa: std.mem.Allocator,
    io: std.Io,
    controller: *ui.Controller,
    mutex: std.Io.Mutex = .init,
    colors: reports.Cache = .{},
    queries: std.ArrayList(Query) = .empty,
    query_active: bool = false,
    mode: state_mod.ColorMode,
    stdout_is_tty: bool,
    resource: ?[]u8 = null,
    identity: ?[]u8 = null,
    pub fn init(gpa: std.mem.Allocator, io: std.Io, controller: *ui.Controller, mode: state_mod.ColorMode, tty: bool) !Producer {
        var value: Producer = .{ .gpa = gpa, .io = io, .controller = controller, .mode = mode, .stdout_is_tty = tty };
        try value.publish(value.colors, null, null);
        return value;
    }
    pub fn deinit(self: *Producer) void {
        self.queries.deinit(self.gpa);
        if (self.resource) |value| self.gpa.free(value);
        if (self.identity) |value| self.gpa.free(value);
    }
    fn publish(self: *Producer, cache: reports.Cache, resource: ?[]const u8, identity: ?[]const u8) !void {
        try self.controller.setThemeState(.{
            .revision = cache.revision,
            .color_mode = self.mode,
            .stdout_is_tty = self.stdout_is_tty,
            .terminal_colors = .{ .foreground = cache.foreground, .background = cache.background, .palette = if (cache.has_palette) &cache.palette else &.{} },
            .terminal_colors_pending = cache.pending,
            .terminal_color_scheme = if (cache.scheme) |scheme| switch (scheme) {
                .dark => .dark,
                .light => .light,
            } else null,
            .resource_json = resource,
            .resource_identity = identity,
        });
    }
    pub fn select(self: *Producer, resource: ?[]const u8, identity: ?[]const u8) !void {
        try self.mutex.lock(self.io);
        defer self.mutex.unlock(self.io);
        if (equal(self.resource, resource) and equal(self.identity, identity)) return;
        const copied_resource = if (resource) |value| try self.gpa.dupe(u8, value) else null;
        errdefer if (copied_resource) |value| self.gpa.free(value);
        const copied_identity = if (identity) |value| try self.gpa.dupe(u8, value) else null;
        errdefer if (copied_identity) |value| self.gpa.free(value);
        var next = self.colors;
        if (next.revision == std.math.maxInt(u64)) return error.TerminalColorRevisionOverflow;
        next.revision += 1;
        try self.publish(next, copied_resource, copied_identity);
        if (self.resource) |value| self.gpa.free(value);
        if (self.identity) |value| self.gpa.free(value);
        self.resource = copied_resource;
        self.identity = copied_identity;
        self.colors = next;
    }
    pub fn begin(self: *Producer) !void {
        try self.mutex.lock(self.io);
        defer self.mutex.unlock(self.io);
        var next = self.colors;
        try next.begin();
        var collection: reports.Cache = .{};
        try collection.begin();
        try self.queries.ensureUnusedCapacity(self.gpa, 1);
        try self.publish(next, self.resource, self.identity);
        self.colors = next;
        self.queries.appendAssumeCapacity(.{ .collection = collection, .deadline_ms = std.Io.Clock.awake.now(self.io).toMilliseconds() + 100 });
        self.query_active = true;
    }
    pub fn request(self: *Producer) !void {
        if (!self.stdout_is_tty) return;
        try self.begin();
        var output: std.Io.Writer.Allocating = .init(self.gpa);
        defer output.deinit();
        try output.writer.writeAll("\x1b]10;?\x07\x1b]11;?\x07");
        for (0..16) |index| try output.writer.print("\x1b]4;{d};?\x07", .{index});
        try output.writer.writeAll("\x1b[c");
        std.Io.File.stdout().writeStreamingAll(self.io, output.written()) catch {
            try self.expire();
        };
    }
    pub fn pump(raw: ?*anyopaque) !bool {
        const self: *Producer = @ptrCast(@alignCast(raw.?));
        try self.mutex.lock(self.io);
        defer self.mutex.unlock(self.io);
        const previous = self.colors.revision;
        const now = std.Io.Clock.awake.now(self.io).toMilliseconds();
        for (0..self.queries.items.len) |index| {
            if (self.queries.items[index].deadline_ms) |end| if (now >= end) {
                try self.deliver(index, true);
            };
        }
        return self.colors.revision != previous;
    }
    pub fn finish(self: *Producer) !void {
        try self.mutex.lock(self.io);
        defer self.mutex.unlock(self.io);
        if (self.queries.items.len == 0) return;
        try self.deliver(0, false);
        _ = self.queries.orderedRemove(0);
        self.query_active = self.queries.items.len != 0;
    }
    pub fn expire(self: *Producer) !void {
        try self.mutex.lock(self.io);
        defer self.mutex.unlock(self.io);
        if (self.queries.items.len > 0) try self.deliver(0, true);
    }
    fn deliver(self: *Producer, index: usize, keep_late: bool) !void {
        const query = &self.queries.items[index];
        if (query.delivery == .none) return;
        const collection = query.collection;
        var next = self.colors;
        var changed = next.pending;
        if (collection.foreground) |rgb| if (next.foreground == null or !std.meta.eql(next.foreground.?, rgb)) {
            next.foreground = rgb;
            changed = true;
        };
        if (collection.background) |rgb| if (next.background == null or !std.meta.eql(next.background.?, rgb)) {
            next.background = rgb;
            changed = true;
        };
        if (collection.has_palette and (!next.has_palette or !std.meta.eql(next.palette, collection.palette))) {
            next.palette = collection.palette;
            next.has_palette = true;
            changed = true;
        }
        next.pending = false;
        if (changed) {
            if (next.revision == std.math.maxInt(u64)) return error.TerminalColorRevisionOverflow;
            next.revision += 1;
            try self.publish(next, self.resource, self.identity);
        }
        self.colors = next;
        query.delivery = if (keep_late) .late else .none;
        query.deadline_ms = null;
    }
    pub fn report(raw: ?*anyopaque, data: []const u8) !bool {
        const self: *Producer = @ptrCast(@alignCast(raw.?));
        const osc = reports.parseOsc(data);
        const scheme = reports.parseScheme(data);
        const attributes = @import("../tui/terminal.zig").parseKeyboardProtocolNegotiationSequence(data);
        const end = if (attributes) |value| value == .device_attributes else false;
        if (osc == null and scheme == null and !end) return false;
        try self.mutex.lock(self.io);
        defer self.mutex.unlock(self.io);
        if (scheme) |value| {
            var next = self.colors;
            if (try next.setScheme(value)) try self.publish(next, self.resource, self.identity);
            self.colors = next;
            return true;
        }
        if (!self.query_active) return false;
        if (end) {
            try self.deliver(0, false);
            _ = self.queries.orderedRemove(0);
            self.query_active = self.queries.items.len != 0;
            return true;
        }
        const query = &self.queries.items[0];
        if (query.delivery == .none) return true;
        const value = osc.?;
        const duplicate = switch (value.target) {
            .foreground => query.collection.seen_foreground,
            .background => query.collection.seen_background,
            .palette => |index| if (index < query.collection.seen_palette.len) query.collection.seen_palette[index] else false,
        };
        if (duplicate) return true;
        _ = try query.collection.report(value);
        if (!query.collection.pending) try self.deliver(0, false);
        return true;
    }
};
fn equal(first: ?[]const u8, second: ?[]const u8) bool {
    if (first == null or second == null) return first == null and second == null;
    return std.mem.eql(u8, first.?, second.?);
}
