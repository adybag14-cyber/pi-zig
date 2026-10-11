//! Owner-thread state for host-answered CodeMode runs. VM clock, execution and
//! transport bindings are separate; this module never executes a host tool.
const std = @import("std");
const json = @import("protocol.zig").json;
pub const Outcome = union(enum) {
    success: ?[]const u8,
    failure: struct {
        message: []const u8,
        properties: ?[]const u8 = null,
        /// Classify the original owner value before invoking its serializer.
        /// An object may legitimately serialize to null, a string or an array.
        properties_was_object: bool = true,
    },
};
pub const Reply = struct {
    gpa: std.mem.Allocator,
    seq: f64,
    now: f64,
    id: u64,
    ok: bool,
    payload: ?[]u8,
    properties: ?[]u8,
    pub fn deinit(self: *Reply) void {
        if (self.payload) |bytes| self.gpa.free(bytes);
        if (self.properties) |bytes| self.gpa.free(bytes);
        self.* = undefined;
    }
    pub fn wire(self: Reply, gpa: std.mem.Allocator) !json.Owned {
        var result = try json.Owned.empty(gpa);
        errdefer result.deinit();
        const a = result.arena.allocator();
        result.value = .{ .object = .empty };
        try result.value.object.put(a, "type", .{ .string = "result" });
        try result.value.object.put(a, "id", .{ .float = @floatFromInt(self.id) });
        try result.value.object.put(a, "ok", .{ .bool = self.ok });
        if (self.payload) |bytes| try result.value.object.put(a, "payload", .{ .string = try a.dupe(u8, bytes) });
        try result.value.object.put(a, "seq", .{ .float = self.seq });
        try result.value.object.put(a, "now", .{ .float = self.now });
        if (self.properties) |bytes| try result.value.object.put(a, "properties", .{ .string = try a.dupe(u8, bytes) });
        return result;
    }
};
pub const Host = struct {
    gpa: std.mem.Allocator,
    clock: f64,
    seed: u32,
    issued: f64 = 0,
    current: f64 = 0,
    finished: bool = false,
    waiting: std.AutoHashMapUnmanaged(u64, void) = .empty,
    delivered: std.AutoHashMapUnmanaged(u64, void) = .empty,
    early: std.AutoHashMapUnmanaged(u64, Reply) = .empty,

    pub fn init(gpa: std.mem.Allocator, started_at: f64, seed: f64) !Host {
        if (!std.math.isFinite(started_at) or started_at < 0) return error.InvalidStartedAt;
        if (!std.math.isFinite(seed) or @floor(seed) != seed or seed < 0 or seed > 0xffffffff) return error.InvalidSeed;
        return .{ .gpa = gpa, .clock = started_at, .seed = @intFromFloat(seed) };
    }
    pub fn deinit(self: *Host) void {
        var values = self.early.valueIterator();
        while (values.next()) |value| value.deinit();
        self.early.deinit(self.gpa);
        self.waiting.deinit(self.gpa);
        self.delivered.deinit(self.gpa);
        self.* = undefined;
    }
    /// Register before publishing onCall, so a synchronous answer can find it.
    pub fn issue(self: *Host, id: u64) !void {
        if (self.finished) return error.RunFinished;
        if (self.waiting.contains(id)) return error.DuplicateCallId;
        try self.waiting.put(self.gpa, id, {});
        self.issued += 1;
    }
    /// Payloads are already JSON-serialized by the owner bridge. All copying
    /// and validation finish before recording an answer; a failed serialization
    /// or allocation leaves the call and sequence available for a retry.
    pub fn deliver(self: *Host, seq_number: f64, now: f64, id: u64, outcome: Outcome) !void {
        if (self.finished) return;
        if (!std.math.isFinite(now)) return error.InvalidClock;
        if (!std.math.isFinite(seq_number) or @floor(seq_number) != seq_number or seq_number < 1) return error.InvalidResultNumber;
        const seq_key: u64 = @bitCast(seq_number);
        if (self.delivered.contains(seq_key)) return error.InvalidResultNumber;
        if (!self.waiting.contains(id)) return error.CallNotWaiting;
        var reply: Reply = .{ .gpa = self.gpa, .seq = seq_number, .now = now, .id = id, .ok = outcome == .success, .payload = null, .properties = null };
        errdefer reply.deinit();
        switch (outcome) {
            .success => |value| if (value) |bytes| {
                var parsed = try json.Owned.parse(self.gpa, bytes);
                defer parsed.deinit();
                reply.payload = try self.gpa.dupe(u8, bytes);
            },
            .failure => |failure| {
                if (failure.properties) |bytes| {
                    if (!failure.properties_was_object) return error.InvalidProperties;
                    var parsed = try json.Owned.parse(self.gpa, bytes);
                    defer parsed.deinit();
                    reply.properties = try self.gpa.dupe(u8, bytes);
                }
                reply.payload = try self.gpa.dupe(u8, failure.message);
            },
        }
        try self.delivered.ensureUnusedCapacity(self.gpa, 1);
        try self.early.ensureUnusedCapacity(self.gpa, 1);
        self.delivered.putAssumeCapacity(seq_key, {});
        self.early.putAssumeCapacity(seq_key, reply);
        _ = self.waiting.remove(id);
    }
    /// A later result cannot advance the VM past a missing result number.
    /// The original finite clock value may move backwards; virtual time cannot.
    pub fn next(self: *Host) ?Reply {
        const seq = self.current + 1;
        const entry = self.early.fetchRemove(@bitCast(seq)) orelse return null;
        self.current = seq;
        self.clock = @max(self.clock, entry.value.now);
        return entry.value;
    }
    pub fn finish(self: *Host) void {
        self.finished = true;
        self.waiting.clearRetainingCapacity();
        var values = self.early.valueIterator();
        while (values.next()) |value| value.deinit();
        self.early.clearRetainingCapacity();
    }
};

test "CodeMode host answers preserve Source validation retry order and buffered result sequence" {
    var host = try Host.init(std.testing.allocator, 1234.5, 0xffffffff);
    defer host.deinit();
    try host.issue(1);
    try host.issue(2);
    try std.testing.expectError(error.InvalidClock, host.deliver(1, std.math.nan(f64), 1, .{ .success = "1" }));
    try std.testing.expectError(error.InvalidResultNumber, host.deliver(0, 1, 1, .{ .success = "1" }));
    try std.testing.expectError(error.InvalidResultNumber, host.deliver(1.5, 1, 1, .{ .success = "1" }));
    try std.testing.expectError(error.CallNotWaiting, host.deliver(1, 1, 99, .{ .success = "1" }));
    try std.testing.expectError(error.InvalidProperties, host.deliver(1, 1, 1, .{ .failure = .{ .message = "bad", .properties = "[]", .properties_was_object = false } }));
    try std.testing.expectError(error.InvalidJSON, host.deliver(1, 1, 1, .{ .success = "invalid JSON" }));
    try host.deliver(2, 1200, 2, .{ .failure = .{ .message = "actual reject", .properties = "{\"structuredOutput\":{\"x\":2},\"name\":\"ignored\",\"message\":\"ignored\",\"stack\":\"ignored\"}" } });
    try std.testing.expect(host.next() == null);
    try host.deliver(1, 1235, 1, .{ .success = "{\"done\":true}" });
    try std.testing.expectError(error.InvalidResultNumber, host.deliver(1, 2000, 1, .{ .success = "0" }));
    try std.testing.expectError(error.CallNotWaiting, host.deliver(3, 2000, 1, .{ .success = "0" }));
    var first = host.next().?;
    defer first.deinit();
    try std.testing.expectEqual(@as(f64, 1), first.seq);
    try std.testing.expectEqual(@as(f64, 1235), host.clock);
    var second = host.next().?;
    defer second.deinit();
    try std.testing.expectEqual(@as(f64, 2), second.seq);
    try std.testing.expectEqual(@as(f64, 1235), host.clock);
    try std.testing.expectEqualStrings("actual reject", second.payload.?);
    host.finish();
    try host.deliver(std.math.nan(f64), std.math.nan(f64), 999, .{ .success = "invalid JSON" });
}
test "CodeMode host ordered delivery preserves both actual Source host wire records" {
    var source = try json.Owned.parse(std.testing.allocator, @embedFile("fixtures/codemode-host-8a9-source.json"));
    defer source.deinit();
    const rows = source.value.object.get("rows").?.array.items;
    var captured_packets: ?json.Value = null;
    for (rows) |row| if (std.mem.eql(u8, row.object.get("name").?.string, "actual-host-wire")) {
        captured_packets = row.object.get("posts").?;
        break;
    } else continue;
    const packets = captured_packets orelse return error.MissingSourceHostWire;
    var host = try Host.init(std.testing.allocator, 1234.5, 0xffffffff);
    defer host.deinit();
    try host.issue(1);
    try host.issue(2);
    for (packets.array.items) |packet| {
        const ok = packet.object.get("ok").?.bool;
        const payload = packet.object.get("payload");
        const properties = packet.object.get("properties");
        try host.deliver(try json.asNumber(packet.object.get("seq").?), try json.asNumber(packet.object.get("now").?), try json.asInteger(packet.object.get("id").?), if (ok) .{ .success = if (payload) |value| value.string else null } else .{ .failure = .{ .message = payload.?.string, .properties = if (properties) |value| value.string else null } });
    }
    for ([_]usize{ 1, 0 }) |index| {
        var reply = host.next().?;
        defer reply.deinit();
        var actual = try reply.wire(std.testing.allocator);
        defer actual.deinit();
        try std.testing.expect(json.equal(packets.array.items[index], actual.value));
    }
    try std.testing.expectEqual(@as(f64, 2), host.current);
    try std.testing.expectEqual(@as(f64, 1235), host.clock);
}
test "CodeMode host allocation failure never consumes an answer or leaks a queued payload" {
    const Check = struct {
        fn run(gpa: std.mem.Allocator) !void {
            var host = try Host.init(gpa, 0, 1);
            defer host.deinit();
            try host.issue(7);
            host.deliver(1, 5, 7, .{ .failure = .{ .message = "actual failure", .properties = "{\"structuredOutput\":{\"x\":2}}" } }) catch |err| {
                try std.testing.expect(host.waiting.contains(7));
                try std.testing.expect(host.delivered.count() == 0 and host.early.count() == 0);
                return err;
            };
            var reply = host.next().?;
            defer reply.deinit();
            var wire = try reply.wire(gpa);
            defer wire.deinit();
            try std.testing.expectEqualStrings("actual failure", wire.value.object.get("payload").?.string);
        }
    };
    try std.testing.checkAllAllocationFailures(std.testing.allocator, Check.run, .{});
}
