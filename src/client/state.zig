//! Authoritative client-side reduction of Pi server and session snapshots.
//! Mirrors packages/client/src/state.ts while keeping listener failures isolated.
const std = @import("std");
const msg = @import("../protocol/messages.zig");

pub const ListenerId = u64;

pub const ServerSnapshotListener = struct {
    context: ?*anyopaque = null,
    callback: *const fn (?*anyopaque, *const msg.ServerSnapshot) anyerror!void,
};
pub const EventListener = struct {
    context: ?*anyopaque = null,
    callback: *const fn (?*anyopaque, *const msg.ServerEvent) anyerror!void,
};
pub const SessionSnapshotListener = struct {
    context: ?*anyopaque = null,
    callback: *const fn (?*anyopaque, *const msg.SessionSnapshot) anyerror!void,
};
pub const ListenerErrorHandler = struct {
    context: ?*anyopaque = null,
    callback: *const fn (?*anyopaque, anyerror) void,
};

const SnapshotSubscription = struct { id: ListenerId, listener: ServerSnapshotListener };
const EventSubscription = struct { id: ListenerId, listener: EventListener };
const SessionSnapshotSubscription = struct {
    id: ListenerId,
    session_id: []u8,
    listener: SessionSnapshotListener,
};
const SessionEventSubscription = struct {
    id: ListenerId,
    session_id: []u8,
    listener: EventListener,
};

pub const ClientState = struct {
    gpa: std.mem.Allocator,
    server_snapshot: ?msg.ServerSnapshot = null,
    session_snapshots: std.StringHashMap(msg.SessionSnapshot),
    snapshot_listeners: std.ArrayList(SnapshotSubscription) = .empty,
    event_listeners: std.ArrayList(EventSubscription) = .empty,
    session_snapshot_listeners: std.ArrayList(SessionSnapshotSubscription) = .empty,
    session_event_listeners: std.ArrayList(SessionEventSubscription) = .empty,
    listener_error_handler: ?ListenerErrorHandler = null,
    next_listener_id: ListenerId = 1,

    pub fn init(gpa: std.mem.Allocator, listener_error_handler: ?ListenerErrorHandler) ClientState {
        return .{
            .gpa = gpa,
            .session_snapshots = std.StringHashMap(msg.SessionSnapshot).init(gpa),
            .listener_error_handler = listener_error_handler,
        };
    }

    pub fn deinit(self: *ClientState) void {
        self.reset();
        self.session_snapshots.deinit();
        self.snapshot_listeners.deinit(self.gpa);
        self.event_listeners.deinit(self.gpa);
        for (self.session_snapshot_listeners.items) |entry| self.gpa.free(entry.session_id);
        self.session_snapshot_listeners.deinit(self.gpa);
        for (self.session_event_listeners.items) |entry| self.gpa.free(entry.session_id);
        self.session_event_listeners.deinit(self.gpa);
        self.* = undefined;
    }

    pub fn reset(self: *ClientState) void {
        self.server_snapshot = null;
        var iterator = self.session_snapshots.iterator();
        while (iterator.next()) |entry| self.gpa.free(entry.key_ptr.*);
        self.session_snapshots.clearRetainingCapacity();
    }

    /// Disconnects make every local session lease inactive without discarding
    /// the last authoritative snapshot, matching the upstream client.
    pub fn clearAttachments(self: *ClientState) void {
        var iterator = self.session_snapshots.iterator();
        while (iterator.next()) |entry| entry.value_ptr.attached = false;
    }

    pub fn snapshot(self: *const ClientState) ?*const msg.ServerSnapshot {
        return if (self.server_snapshot) |*value| value else null;
    }

    pub fn getSessionSnapshot(self: *const ClientState, session_id: []const u8) ?*const msg.SessionSnapshot {
        return self.session_snapshots.getPtr(session_id);
    }

    pub fn getSessionSnapshotMut(self: *ClientState, session_id: []const u8) ?*msg.SessionSnapshot {
        return self.session_snapshots.getPtr(session_id);
    }

    pub fn isSessionAttached(self: *const ClientState, session_id: []const u8) bool {
        const snapshot_value = self.session_snapshots.get(session_id) orelse return false;
        return snapshot_value.attached;
    }

    /// Removes a session snapshot while preserving its borrowed contents in the
    /// return value. The caller may restore it if an attach attempt fails.
    pub fn forgetSessionSnapshot(self: *ClientState, session_id: []const u8) ?msg.SessionSnapshot {
        const removed = self.session_snapshots.fetchRemove(session_id) orelse return null;
        self.gpa.free(removed.key);
        return removed.value;
    }

    pub fn restoreSessionSnapshot(self: *ClientState, value: msg.SessionSnapshot) !void {
        if (self.session_snapshots.contains(value.id)) return;
        try self.session_snapshots.put(try self.gpa.dupe(u8, value.id), value);
    }

    pub fn subscribe(self: *ClientState, listener: ServerSnapshotListener) !ListenerId {
        const id = self.allocateListenerId();
        try self.snapshot_listeners.append(self.gpa, .{ .id = id, .listener = listener });
        return id;
    }

    pub fn onEvent(self: *ClientState, listener: EventListener) !ListenerId {
        const id = self.allocateListenerId();
        try self.event_listeners.append(self.gpa, .{ .id = id, .listener = listener });
        return id;
    }

    pub fn subscribeSession(self: *ClientState, session_id: []const u8, listener: SessionSnapshotListener) !ListenerId {
        const id = self.allocateListenerId();
        const owned_id = try self.gpa.dupe(u8, session_id);
        errdefer self.gpa.free(owned_id);
        try self.session_snapshot_listeners.append(self.gpa, .{ .id = id, .session_id = owned_id, .listener = listener });
        return id;
    }

    pub fn onSessionEvent(self: *ClientState, session_id: []const u8, listener: EventListener) !ListenerId {
        const id = self.allocateListenerId();
        const owned_id = try self.gpa.dupe(u8, session_id);
        errdefer self.gpa.free(owned_id);
        try self.session_event_listeners.append(self.gpa, .{ .id = id, .session_id = owned_id, .listener = listener });
        return id;
    }

    pub fn unsubscribe(self: *ClientState, id: ListenerId) bool {
        for (self.snapshot_listeners.items, 0..) |entry, index| {
            if (entry.id == id) {
                _ = self.snapshot_listeners.orderedRemove(index);
                return true;
            }
        }
        for (self.event_listeners.items, 0..) |entry, index| {
            if (entry.id == id) {
                _ = self.event_listeners.orderedRemove(index);
                return true;
            }
        }
        for (self.session_snapshot_listeners.items, 0..) |entry, index| {
            if (entry.id == id) {
                const removed = self.session_snapshot_listeners.orderedRemove(index);
                self.gpa.free(removed.session_id);
                return true;
            }
        }
        for (self.session_event_listeners.items, 0..) |entry, index| {
            if (entry.id == id) {
                const removed = self.session_event_listeners.orderedRemove(index);
                self.gpa.free(removed.session_id);
                return true;
            }
        }
        return false;
    }

    /// Returns true when the server snapshot was accepted. Older revisions are
    /// deliberately ignored so delayed traffic cannot roll state backwards.
    pub fn applyServerSnapshot(self: *ClientState, value: msg.ServerSnapshot) bool {
        if (self.server_snapshot) |current| {
            if (value.revision < current.revision) return false;
        }
        self.server_snapshot = value;
        for (self.snapshot_listeners.items) |entry| {
            entry.listener.callback(entry.listener.context, &value) catch |err| self.reportListenerError(err);
        }
        return true;
    }

    pub fn applySessionSnapshot(self: *ClientState, value: msg.SessionSnapshot, force: bool) !bool {
        if (self.session_snapshots.getPtr(value.id)) |current| {
            if (!force and value.revision < current.revision) return false;
            current.* = value;
        } else {
            try self.session_snapshots.put(try self.gpa.dupe(u8, value.id), value);
        }
        for (self.session_snapshot_listeners.items) |entry| {
            if (!std.mem.eql(u8, entry.session_id, value.id)) continue;
            entry.listener.callback(entry.listener.context, &value) catch |err| self.reportListenerError(err);
        }
        return true;
    }

    pub fn applyResult(self: *ClientState, result: msg.CommandResult) !void {
        switch (result) {
            .list => {},
            .detach => |detached| {
                if (self.session_snapshots.getPtr(detached.session_id)) |current| {
                    current.attached = false;
                    const value = current.*;
                    for (self.session_snapshot_listeners.items) |entry| {
                        if (!std.mem.eql(u8, entry.session_id, detached.session_id)) continue;
                        entry.listener.callback(entry.listener.context, &value) catch |err| self.reportListenerError(err);
                    }
                }
            },
            .create => |value| _ = try self.applySessionSnapshot(value, false),
            .attach => |value| _ = try self.applySessionSnapshot(value, false),
            .prompt => |value| _ = try self.applySessionSnapshot(value, false),
            .steer => |value| _ = try self.applySessionSnapshot(value, false),
            .abort => |value| _ = try self.applySessionSnapshot(value, false),
            .set_model => |value| _ = try self.applySessionSnapshot(value, false),
            .set_thinking => |value| _ = try self.applySessionSnapshot(value, false),
        }
    }

    pub fn applyEvent(self: *ClientState, event: msg.ServerEvent) !void {
        switch (event) {
            .server_snapshot => |value| _ = self.applyServerSnapshot(value),
            .session_snapshot => |value| _ = try self.applySessionSnapshot(value, false),
            .session_progress => {},
            .session_removed => |removed| {
                if (self.session_snapshots.fetchRemove(removed.session_id)) |entry| self.gpa.free(entry.key);
            },
        }
        for (self.event_listeners.items) |entry| {
            entry.listener.callback(entry.listener.context, &event) catch |err| self.reportListenerError(err);
        }
        if (eventSessionId(event)) |session_id| {
            for (self.session_event_listeners.items) |entry| {
                if (!std.mem.eql(u8, entry.session_id, session_id)) continue;
                entry.listener.callback(entry.listener.context, &event) catch |err| self.reportListenerError(err);
            }
        }
    }

    fn allocateListenerId(self: *ClientState) ListenerId {
        const id = self.next_listener_id;
        self.next_listener_id +%= 1;
        if (self.next_listener_id == 0) self.next_listener_id = 1;
        return id;
    }

    fn reportListenerError(self: *ClientState, err: anyerror) void {
        if (self.listener_error_handler) |handler| handler.callback(handler.context, err);
    }
};

fn eventSessionId(event: msg.ServerEvent) ?[]const u8 {
    return switch (event) {
        .session_snapshot => |value| value.id,
        .session_progress => |value| value.session_id,
        .session_removed => |value| value.session_id,
        .server_snapshot => null,
    };
}

fn sampleSession(id: []const u8, revision: u64, attached: bool) msg.SessionSnapshot {
    return .{
        .id = id,
        .cwd = "/tmp",
        .created_at = 1,
        .updated_at = 1,
        .phase = .idle,
        .model = .{ .provider = "test", .id = "model" },
        .thinking_level = .off,
        .attached = attached,
        .locked = false,
        .revision = revision,
        .transcript = &.{},
        .queued_steer = &.{},
        .queued_steer_count = 0,
    };
}

fn sampleServer(revision: u64) msg.ServerSnapshot {
    return .{ .server_id = "server", .revision = revision, .sessions = &.{}, .models = &.{} };
}

test "client state rejects stale server and session snapshots" {
    const gpa = std.testing.allocator;
    var state = ClientState.init(gpa, null);
    defer state.deinit();
    try std.testing.expect(state.applyServerSnapshot(sampleServer(3)));
    try std.testing.expect(!state.applyServerSnapshot(sampleServer(2)));
    try std.testing.expectEqual(@as(u64, 3), state.snapshot().?.revision);

    try std.testing.expect(try state.applySessionSnapshot(sampleSession("s", 5, true), false));
    try std.testing.expect(!try state.applySessionSnapshot(sampleSession("s", 4, false), false));
    try std.testing.expect(state.isSessionAttached("s"));
}

test "client state detach is forced while reacquisition can accept lower revisions" {
    const gpa = std.testing.allocator;
    var state = ClientState.init(gpa, null);
    defer state.deinit();
    _ = try state.applySessionSnapshot(sampleSession("s", 10, true), false);
    try state.applyResult(.{ .detach = .{ .session_id = "s" } });
    try std.testing.expect(!state.isSessionAttached("s"));
    _ = state.forgetSessionSnapshot("s");
    _ = try state.applySessionSnapshot(sampleSession("s", 0, true), false);
    try std.testing.expectEqual(@as(u64, 0), state.getSessionSnapshot("s").?.revision);
}

test "client state listeners unsubscribe and failures are isolated" {
    const Context = struct {
        calls: usize = 0,
        errors: usize = 0,
        fn onSnapshot(raw: ?*anyopaque, _: *const msg.ServerSnapshot) anyerror!void {
            const self: *@This() = @ptrCast(@alignCast(raw.?));
            self.calls += 1;
            return error.ConsumerFailure;
        }
        fn onError(raw: ?*anyopaque, err: anyerror) void {
            const self: *@This() = @ptrCast(@alignCast(raw.?));
            if (err == error.ConsumerFailure) self.errors += 1;
        }
    };
    var context: Context = .{};
    var state = ClientState.init(std.testing.allocator, .{ .context = &context, .callback = Context.onError });
    defer state.deinit();
    const id = try state.subscribe(.{ .context = &context, .callback = Context.onSnapshot });
    _ = state.applyServerSnapshot(sampleServer(1));
    try std.testing.expectEqual(@as(usize, 1), context.calls);
    try std.testing.expectEqual(@as(usize, 1), context.errors);
    try std.testing.expect(state.unsubscribe(id));
    _ = state.applyServerSnapshot(sampleServer(2));
    try std.testing.expectEqual(@as(usize, 1), context.calls);
}
