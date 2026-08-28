//! Shared/exclusive session ownership and failure-safe release bookkeeping.
//! This is the native equivalent of PiClient's session-lease maps/generations.
const std = @import("std");

pub const LeaseId = u64;
pub const Mode = enum { shared, exclusive };
pub const State = enum { active, releasing, released, invalidated };
pub const ReleaseAction = enum { none, released_locally, detach_required };

pub const Error = error{
    SessionAlreadyLeased,
    SessionExclusivelyLeased,
    UnknownLease,
    LeaseNotActive,
    LeaseNotReleasing,
};

pub const Lease = struct {
    id: LeaseId,
    session_id: []u8,
    mode: Mode,
    generation: u64,
    state: State = .active,
    counted: bool = true,
};

pub const Manager = struct {
    gpa: std.mem.Allocator,
    leases: std.AutoHashMap(LeaseId, Lease),
    counts: std.StringHashMap(usize),
    exclusive: std.StringHashMap(LeaseId),
    generations: std.StringHashMap(u64),
    cleanup_required: std.StringHashMap(void),
    next_id: LeaseId = 1,

    pub fn init(gpa: std.mem.Allocator) Manager {
        return .{
            .gpa = gpa,
            .leases = std.AutoHashMap(LeaseId, Lease).init(gpa),
            .counts = std.StringHashMap(usize).init(gpa),
            .exclusive = std.StringHashMap(LeaseId).init(gpa),
            .generations = std.StringHashMap(u64).init(gpa),
            .cleanup_required = std.StringHashMap(void).init(gpa),
        };
    }

    pub fn deinit(self: *Manager) void {
        var lease_iterator = self.leases.iterator();
        while (lease_iterator.next()) |entry| self.gpa.free(entry.value_ptr.session_id);
        self.leases.deinit();
        freeStringMapKeys(usize, self.gpa, &self.counts);
        self.counts.deinit();
        freeStringMapKeys(LeaseId, self.gpa, &self.exclusive);
        self.exclusive.deinit();
        freeStringMapKeys(u64, self.gpa, &self.generations);
        self.generations.deinit();
        freeStringMapKeys(void, self.gpa, &self.cleanup_required);
        self.cleanup_required.deinit();
        self.* = undefined;
    }

    pub fn reserve(self: *Manager, session_id: []const u8, mode: Mode) !LeaseId {
        const count = self.counts.get(session_id) orelse 0;
        if (mode == .exclusive and count > 0) return Error.SessionAlreadyLeased;
        if (mode == .shared and self.exclusive.contains(session_id)) return Error.SessionExclusivelyLeased;

        const id = self.allocateId();
        const owned_session_id = try self.gpa.dupe(u8, session_id);
        errdefer self.gpa.free(owned_session_id);
        const generation = self.generations.get(session_id) orelse 0;
        try self.leases.put(id, .{
            .id = id,
            .session_id = owned_session_id,
            .mode = mode,
            .generation = generation,
        });
        errdefer _ = self.leases.remove(id);
        try incrementStringCount(self.gpa, &self.counts, session_id);
        if (mode == .exclusive) try putOwnedIfAbsent(LeaseId, self.gpa, &self.exclusive, session_id, id);
        return id;
    }

    pub fn state(self: *Manager, id: LeaseId) ?State {
        const lease = self.leases.getPtr(id) orelse return null;
        self.refresh(lease);
        return lease.state;
    }

    pub fn sessionId(self: *Manager, id: LeaseId) ?[]const u8 {
        const lease = self.leases.getPtr(id) orelse return null;
        self.refresh(lease);
        return lease.session_id;
    }

    pub fn isActive(self: *Manager, id: LeaseId, session_attached: bool) bool {
        const lease = self.leases.getPtr(id) orelse return false;
        self.refresh(lease);
        return lease.state == .active and session_attached;
    }

    pub fn beginRelease(self: *Manager, id: LeaseId) !ReleaseAction {
        const lease = self.leases.getPtr(id) orelse return Error.UnknownLease;
        self.refresh(lease);
        switch (lease.state) {
            .released, .invalidated => return .none,
            .releasing => return .detach_required,
            .active => {},
        }
        lease.state = .releasing;
        const count = self.counts.get(lease.session_id) orelse 0;
        if (count <= 1) return .detach_required;
        self.relinquish(lease);
        lease.state = .released;
        return .released_locally;
    }

    /// Completes the final-lease detach. Explicit detach failures restore the
    /// lease; disposal failures relinquish it and schedule reconciliation.
    pub fn finishRelease(self: *Manager, id: LeaseId, success: bool, relinquish_on_failure: bool) !void {
        const lease = self.leases.getPtr(id) orelse return Error.UnknownLease;
        self.refresh(lease);
        if (lease.state == .invalidated or lease.state == .released) return;
        if (lease.state != .releasing) return Error.LeaseNotReleasing;
        if (success) {
            self.relinquish(lease);
            lease.state = .released;
            return;
        }
        if (relinquish_on_failure) {
            const session_id = try self.gpa.dupe(u8, lease.session_id);
            errdefer self.gpa.free(session_id);
            self.relinquish(lease);
            lease.state = .released;
            if (self.cleanup_required.contains(session_id)) self.gpa.free(session_id) else try self.cleanup_required.put(session_id, {});
        } else {
            lease.state = .active;
        }
    }

    pub fn requiresCleanup(self: *const Manager, session_id: []const u8) bool {
        return self.cleanup_required.contains(session_id);
    }

    pub fn markReconciled(self: *Manager, session_id: []const u8) bool {
        const removed = self.cleanup_required.fetchRemove(session_id) orelse return false;
        self.gpa.free(removed.key);
        return true;
    }

    pub fn invalidateSession(self: *Manager, session_id: []const u8) !void {
        removeOwned(usize, self.gpa, &self.counts, session_id);
        removeOwned(LeaseId, self.gpa, &self.exclusive, session_id);
        removeOwned(void, self.gpa, &self.cleanup_required, session_id);
        const next = (self.generations.get(session_id) orelse 0) +% 1;
        if (self.generations.getPtr(session_id)) |value| value.* = next else try self.generations.put(try self.gpa.dupe(u8, session_id), next);
        var iterator = self.leases.iterator();
        while (iterator.next()) |entry| {
            if (std.mem.eql(u8, entry.value_ptr.session_id, session_id)) {
                entry.value_ptr.counted = false;
                entry.value_ptr.state = .invalidated;
            }
        }
    }

    pub fn invalidateAll(self: *Manager) !void {
        // Collect ids first because invalidateSession mutates auxiliary maps.
        var ids: std.ArrayList([]u8) = .empty;
        defer {
            for (ids.items) |id| self.gpa.free(id);
            ids.deinit(self.gpa);
        }
        var iterator = self.counts.iterator();
        while (iterator.next()) |entry| try ids.append(self.gpa, try self.gpa.dupe(u8, entry.key_ptr.*));
        for (ids.items) |id| try self.invalidateSession(id);
        clearOwnedMap(void, self.gpa, &self.cleanup_required);
    }

    pub fn removeLease(self: *Manager, id: LeaseId) bool {
        const removed = self.leases.fetchRemove(id) orelse return false;
        var lease = removed.value;
        self.refresh(&lease);
        if (lease.counted) self.relinquish(&lease);
        self.gpa.free(lease.session_id);
        return true;
    }

    fn refresh(self: *Manager, lease: *Lease) void {
        if (lease.state != .active and lease.state != .releasing) return;
        if ((self.generations.get(lease.session_id) orelse 0) != lease.generation) {
            lease.counted = false;
            lease.state = .invalidated;
        }
    }

    fn relinquish(self: *Manager, lease: *Lease) void {
        if (!lease.counted) return;
        lease.counted = false;
        if (self.counts.getPtr(lease.session_id)) |count| {
            if (count.* <= 1) removeOwned(usize, self.gpa, &self.counts, lease.session_id) else count.* -= 1;
        }
        if (self.exclusive.get(lease.session_id)) |exclusive_id| {
            if (exclusive_id == lease.id) removeOwned(LeaseId, self.gpa, &self.exclusive, lease.session_id);
        }
    }

    fn allocateId(self: *Manager) LeaseId {
        while (true) {
            const id = self.next_id;
            self.next_id +%= 1;
            if (self.next_id == 0) self.next_id = 1;
            if (id != 0 and !self.leases.contains(id)) return id;
        }
    }
};

fn incrementStringCount(gpa: std.mem.Allocator, map: *std.StringHashMap(usize), key: []const u8) !void {
    if (map.getPtr(key)) |value| {
        value.* += 1;
        return;
    }
    try map.put(try gpa.dupe(u8, key), 1);
}

fn putOwnedIfAbsent(comptime V: type, gpa: std.mem.Allocator, map: *std.StringHashMap(V), key: []const u8, value: V) !void {
    if (map.getPtr(key)) |existing| {
        existing.* = value;
        return;
    }
    try map.put(try gpa.dupe(u8, key), value);
}

fn removeOwned(comptime V: type, gpa: std.mem.Allocator, map: *std.StringHashMap(V), key: []const u8) void {
    if (map.fetchRemove(key)) |removed| gpa.free(removed.key);
}

fn clearOwnedMap(comptime V: type, gpa: std.mem.Allocator, map: *std.StringHashMap(V)) void {
    var iterator = map.iterator();
    while (iterator.next()) |entry| gpa.free(entry.key_ptr.*);
    map.clearRetainingCapacity();
}

fn freeStringMapKeys(comptime V: type, gpa: std.mem.Allocator, map: *std.StringHashMap(V)) void {
    var iterator = map.iterator();
    while (iterator.next()) |entry| gpa.free(entry.key_ptr.*);
}

test "lease manager shares attachment and detaches only the final lease" {
    const gpa = std.testing.allocator;
    var manager = Manager.init(gpa);
    defer manager.deinit();
    const first = try manager.reserve("s", .shared);
    const second = try manager.reserve("s", .shared);
    try std.testing.expectEqual(ReleaseAction.released_locally, try manager.beginRelease(first));
    try std.testing.expectEqual(State.released, manager.state(first).?);
    try std.testing.expectEqual(ReleaseAction.detach_required, try manager.beginRelease(second));
    try manager.finishRelease(second, true, false);
    try std.testing.expectEqual(State.released, manager.state(second).?);
}

test "lease manager enforces shared and exclusive ownership" {
    const gpa = std.testing.allocator;
    var manager = Manager.init(gpa);
    defer manager.deinit();
    const shared = try manager.reserve("s", .shared);
    try std.testing.expectError(Error.SessionAlreadyLeased, manager.reserve("s", .exclusive));
    _ = try manager.beginRelease(shared);
    try manager.finishRelease(shared, true, false);
    const exclusive = try manager.reserve("s", .exclusive);
    try std.testing.expectError(Error.SessionExclusivelyLeased, manager.reserve("s", .shared));
    try std.testing.expect(manager.isActive(exclusive, true));
}

test "explicit release failure restores while disposal failure schedules cleanup" {
    const gpa = std.testing.allocator;
    var manager = Manager.init(gpa);
    defer manager.deinit();
    const explicit = try manager.reserve("explicit", .exclusive);
    _ = try manager.beginRelease(explicit);
    try manager.finishRelease(explicit, false, false);
    try std.testing.expectEqual(State.active, manager.state(explicit).?);

    const disposal = try manager.reserve("dispose", .exclusive);
    _ = try manager.beginRelease(disposal);
    try manager.finishRelease(disposal, false, true);
    try std.testing.expectEqual(State.released, manager.state(disposal).?);
    try std.testing.expect(manager.requiresCleanup("dispose"));
    try std.testing.expect(manager.markReconciled("dispose"));
}

test "disconnect invalidates leases without requiring protocol cleanup" {
    const gpa = std.testing.allocator;
    var manager = Manager.init(gpa);
    defer manager.deinit();
    const lease = try manager.reserve("s", .exclusive);
    try manager.invalidateAll();
    try std.testing.expectEqual(State.invalidated, manager.state(lease).?);
    try std.testing.expectEqual(ReleaseAction.none, try manager.beginRelease(lease));
    try std.testing.expect(!manager.requiresCleanup("s"));
}
