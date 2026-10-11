//! Source document-cache bookkeeping. The caller owns the Session mutation line,
//! actual cached trackers, clock/settings evaluation and unreferenced VM timers.
const std = @import("std");
const json = @import("backend/json.zig");

pub const default_ms: f64 = 600_000;
pub const max_timer_delay_ms: f64 = 2_147_483_647;

/// Pass null for any non-number JS value; never coerce a supplied object/string.
/// NaN and negative numbers select the default; positive Infinity stays Infinity.
pub fn duration(number: ?f64) f64 {
    const value = number orelse return default_ms;
    return if (value >= 0) value else default_ms;
}

pub const Idle = struct { address: json.Owned, record_id: u64, since: f64 };
pub const Index = struct {
    gpa: std.mem.Allocator,
    idle: std.ArrayList(Idle) = .empty,
    attached: std.AutoHashMapUnmanaged(u64, usize) = .empty,

    pub fn init(gpa: std.mem.Allocator) Index {
        return .{ .gpa = gpa };
    }
    pub fn deinit(self: *Index) void {
        self.clearIdle();
        self.idle.deinit(self.gpa);
        self.attached.deinit(self.gpa);
        self.* = undefined;
    }
    /// Explicit unload drops trackers and idle entries; observers still pin their
    /// own record incarnations until disposal, retirement or Session close.
    pub fn clearIdle(self: *Index) void {
        for (self.idle.items) |*item| item.address.deinit();
        self.idle.clearRetainingCapacity();
    }
    fn position(self: *const Index, address: json.Value) ?usize {
        for (self.idle.items, 0..) |item, index| if (json.equal(item.address.value, address)) return index;
        return null;
    }
    pub fn lastUse(self: *const Index, address: json.Value) ?f64 {
        return if (self.position(address)) |index| self.idle.items[index].since else null;
    }
    pub fn drop(self: *Index, address: json.Value) void {
        if (self.position(address)) |index| {
            var removed = self.idle.orderedRemove(index);
            removed.address.deinit();
        }
    }
    pub fn isPinned(self: *const Index, record_id: u64) bool {
        return self.attached.contains(record_id);
    }
    /// Source's Map insertion order is the eviction order, including equal clock
    /// values. Do not sort by timestamp or touch more often than its granule.
    pub fn touch(self: *Index, address: json.Value, record_id: u64, now: f64, retention: f64) !void {
        if (self.isPinned(record_id)) return;
        const prior = self.position(address);
        if (prior) |index| {
            const since = self.idle.items[index].since;
            if (now - since < @min(1_000, retention / 10)) return;
        }
        try self.move(address, record_id, now);
    }
    pub fn move(self: *Index, address: json.Value, record_id: u64, now: f64) !void {
        const prior = self.position(address);
        // Prepare all allocations before replacing an existing idle entry.
        var copy = try json.Owned.empty(self.gpa);
        errdefer copy.deinit();
        copy.value = try json.clone(copy.arena.allocator(), address);
        try self.idle.ensureUnusedCapacity(self.gpa, if (prior == null) 1 else 0);
        if (prior) |index| {
            var removed = self.idle.orderedRemove(index);
            removed.address.deinit();
        }
        self.idle.appendAssumeCapacity(.{ .address = copy, .record_id = record_id, .since = now });
    }
    /// Attach pins the record incarnation, not its address. A later record at the
    /// same address has an independent count and may be evicted independently.
    pub fn pin(self: *Index, address: json.Value, record_id: u64) !void {
        const entry = try self.attached.getOrPut(self.gpa, record_id);
        if (!entry.found_existing) entry.value_ptr.* = 0;
        entry.value_ptr.* += 1;
        self.drop(address);
    }
    /// Returns true only when the last pin was released. An observer must guard
    /// its release once; the caller touches only if this is still the cached ID.
    pub fn unpin(self: *Index, record_id: u64) bool {
        const count = self.attached.getPtr(record_id) orelse return false;
        if (count.* > 1) {
            count.* -= 1;
            return false;
        }
        _ = self.attached.remove(record_id);
        return true;
    }
    pub fn nextDeadline(self: *const Index, retention: f64) ?f64 {
        if (self.idle.items.len == 0) return null;
        return self.idle.items[0].since + retention;
    }
    /// Query and removal run on the Session line. The caller removes the actual
    /// tracker, then drops this exact address, before querying another oldest.
    pub fn oldestExpired(self: *const Index, now: f64, retention: f64) ?*const Idle {
        if (self.idle.items.len == 0) return null;
        const oldest = &self.idle.items[0];
        return if (oldest.since > now - retention) null else oldest;
    }
};

test "document retention preserves numeric normalization and Infinity" {
    try std.testing.expectEqual(default_ms, duration(null));
    try std.testing.expectEqual(default_ms, duration(std.math.nan(f64)));
    try std.testing.expectEqual(default_ms, duration(-1));
    try std.testing.expectEqual(default_ms, duration(-std.math.inf(f64)));
    try std.testing.expectEqual(@as(f64, 0), duration(0));
    try std.testing.expectEqual(std.math.inf(f64), duration(std.math.inf(f64)));
}

test "document retention uses insertion order granules and actual incarnation pins" {
    var index = Index.init(std.testing.allocator);
    defer index.deinit();
    const a: json.Value = .{ .string = "a" };
    const b: json.Value = .{ .string = "b" };
    try index.touch(a, 1, 100, 1_000);
    try index.touch(b, 2, 100, 1_000);
    try index.touch(a, 1, 199, 1_000);
    try std.testing.expect(json.equal(a, index.idle.items[0].address.value));
    try index.touch(a, 1, 200, 1_000);
    try std.testing.expect(json.equal(b, index.idle.items[0].address.value));
    try std.testing.expect(index.oldestExpired(1_099, 1_000) == null);
    try std.testing.expectEqual(@as(u64, 2), index.oldestExpired(1_100, 1_000).?.record_id);
    try index.pin(a, 1);
    try index.pin(a, 1);
    try index.touch(a, 1, 500, 0);
    try std.testing.expectEqual(@as(usize, 1), index.idle.items.len);
    try std.testing.expect(!index.unpin(1));
    try index.touch(a, 3, 500, 0);
    try std.testing.expect(index.unpin(1));
    try std.testing.expectEqual(@as(u64, 3), index.idle.items[1].record_id);
    index.clearIdle();
    try index.pin(a, 3);
    index.clearIdle();
    try std.testing.expect(index.isPinned(3));
    try std.testing.expect(index.unpin(3));
    try index.touch(a, 3, 500, std.math.inf(f64));
    try std.testing.expect(index.oldestExpired(1e15, std.math.inf(f64)) == null);
    try std.testing.expectEqual(std.math.inf(f64), index.nextDeadline(std.math.inf(f64)).?);
    try std.testing.expectEqual(@as(u64, 3), index.oldestExpired(500, 0).?.record_id);
}
