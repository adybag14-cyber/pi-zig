//! Pure owned availability values; this module has no VM dependencies.
const std = @import("std");
pub const Model = struct { provider: []const u8, id: []const u8 };
pub const Snapshot = struct {
    arena: std.heap.ArenaAllocator,
    owner_generation: u64 = 0,
    runtime_id: u64 = 0,
    revision: u64,
    all: []const Model,
    available: []const Model,
    all_json: []const u8,
    available_json: []const u8,
    pub fn deinit(self: *Snapshot) void {
        self.arena.deinit();
        self.* = undefined;
    }
    pub fn copy(self: *const Snapshot, gpa: std.mem.Allocator) !Snapshot {
        var result = try fromJson(gpa, self.revision, self.all_json, self.available_json);
        result.owner_generation = self.owner_generation;
        result.runtime_id = self.runtime_id;
        return result;
    }
    pub fn encode(self: *const Snapshot, gpa: std.mem.Allocator) ![]u8 {
        return std.json.Stringify.valueAlloc(gpa, Wire{ .version = 1, .ownerGeneration = self.owner_generation, .runtimeId = self.runtime_id, .revision = self.revision, .all = self.all, .available = self.available }, .{});
    }
};
const Wire = struct { version: u32, ownerGeneration: u64, runtimeId: u64, revision: u64, all: []const Model, available: []const Model };
pub fn fromJson(gpa: std.mem.Allocator, revision: u64, all: []const u8, available: []const u8) !Snapshot {
    var arena = std.heap.ArenaAllocator.init(gpa);
    errdefer arena.deinit();
    const allocator = arena.allocator();
    const all_json = try allocator.dupe(u8, all);
    const available_json = try allocator.dupe(u8, available);
    const all_models = try std.json.parseFromSliceLeaky([]const Model, allocator, all_json, .{ .ignore_unknown_fields = true });
    const available_models = try std.json.parseFromSliceLeaky([]const Model, allocator, available_json, .{ .ignore_unknown_fields = true });
    if (all_models.len > 65536 or available_models.len > 65536) return error.NativeSDKModelLimit;
    return .{ .arena = arena, .revision = revision, .all = all_models, .available = available_models, .all_json = all_json, .available_json = available_json };
}
pub fn decode(gpa: std.mem.Allocator, raw: []const u8) !?Snapshot {
    if (std.mem.eql(u8, std.mem.trim(u8, raw, " \r\n\t"), "null")) return null;
    var parsed = try std.json.parseFromSlice(Wire, gpa, raw, .{});
    defer parsed.deinit();
    return try fromWire(gpa, parsed.value);
}
pub fn decodeResponse(gpa: std.mem.Allocator, raw: []const u8) !?Snapshot {
    var parsed = try std.json.parseFromSlice(struct { snapshot: ?Wire }, gpa, raw, .{});
    defer parsed.deinit();
    return if (parsed.value.snapshot) |wire| try fromWire(gpa, wire) else null;
}
fn fromWire(gpa: std.mem.Allocator, wire: Wire) !Snapshot {
    if (wire.version != 1 or wire.runtimeId == 0 or wire.runtimeId > 9007199254740991 or wire.ownerGeneration == 0 or wire.revision == 0) return error.InvalidNativeSDKAvailability;
    const all = try std.json.Stringify.valueAlloc(gpa, wire.all, .{});
    defer gpa.free(all);
    const available = try std.json.Stringify.valueAlloc(gpa, wire.available, .{});
    defer gpa.free(available);
    var result = try fromJson(gpa, wire.revision, all, available);
    result.runtime_id = wire.runtimeId;
    result.owner_generation = wire.ownerGeneration;
    return result;
}

/// Mutated only by the VM owner. Prepared copies allocate before publication.
pub const Store = struct {
    values: std.AutoHashMapUnmanaged(u64, Snapshot) = .empty,
    latest: u64 = 0,
    pub fn deinit(self: *Store, gpa: std.mem.Allocator) void {
        var iterator = self.values.valueIterator();
        while (iterator.next()) |value| value.deinit();
        self.values.deinit(gpa);
        self.* = .{};
    }
    pub fn prepare(self: *Store, gpa: std.mem.Allocator, source: *const Snapshot) !Snapshot {
        if (source.runtime_id == 0) return error.InvalidNativeSDKAvailability;
        if (!self.values.contains(source.runtime_id) and self.values.count() >= 4096) return error.NativeSDKRuntimeLimit;
        try self.values.ensureUnusedCapacity(gpa, 1);
        return source.copy(gpa);
    }
    pub fn commit(self: *Store, value: Snapshot) void {
        if (self.values.getPtr(value.runtime_id)) |old| {
            old.deinit();
            old.* = value;
        } else self.values.putAssumeCapacityNoClobber(value.runtime_id, value);
        self.latest = value.runtime_id;
    }
    pub fn retire(self: *Store, id: u64) void {
        if (self.values.fetchRemove(id)) |removed| {
            var value = removed.value;
            value.deinit();
        }
        if (self.latest == id) {
            self.latest = 0;
            var iterator = self.values.keyIterator();
            while (iterator.next()) |key| self.latest = @max(self.latest, key.*);
        }
    }
    pub fn encode(self: *const Store, gpa: std.mem.Allocator, id: u64) ![]u8 {
        const value = self.values.get(if (id == 0) self.latest else id) orelse return gpa.dupe(u8, "null");
        return value.encode(gpa);
    }
};
test "availability owner store replacement retirement and wire copies" {
    var store: Store = .{};
    defer store.deinit(std.testing.allocator);
    var value = try fromJson(std.testing.allocator, 1, "[{\"provider\":\"p\",\"id\":\"a\"}]", "[]");
    defer value.deinit();
    value.runtime_id = 7;
    value.owner_generation = 23;
    store.commit(try store.prepare(std.testing.allocator, &value));
    var failed = std.testing.FailingAllocator.init(std.testing.allocator, .{ .fail_index = 0 });
    try std.testing.expectError(error.OutOfMemory, store.prepare(failed.allocator(), &value));
    try std.testing.expectEqual(@as(u64, 1), store.values.get(7).?.revision);
    const wire = try store.encode(std.testing.allocator, 0);
    defer std.testing.allocator.free(wire);
    var copied = (try decode(std.testing.allocator, wire)).?;
    defer copied.deinit();
    store.retire(7);
    try std.testing.expectEqualStrings("a", copied.all[0].id);
    try std.testing.expectEqual(@as(u64, 23), copied.owner_generation);
    const empty = try store.encode(std.testing.allocator, 0);
    defer std.testing.allocator.free(empty);
    try std.testing.expectEqualStrings("null", empty);
}
