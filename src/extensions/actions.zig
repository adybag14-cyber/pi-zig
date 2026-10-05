//! Ordered, allocator-owned side effects produced by extension invocations.
//!
//! Script extensions execute in persistent workers and may call Pi APIs from
//! lifecycle hooks, tool handlers, commands, and shortcuts. Those calls are
//! synchronous in the upstream runner, but the native agent can execute tool
//! handlers on worker threads. This module therefore separates capture from
//! application: every action is canonicalized while the invocation result is
//! owned, then moved through a mutex-protected FIFO and applied on the agent
//! thread at deterministic safe points.
const std = @import("std");
const Io = std.Io;

pub const max_actions_per_invocation: usize = 1024;
pub const max_action_kind_bytes: usize = 96;

pub const Record = struct {
    sequence: u64 = 0,
    extension_name: []u8,
    invocation: []u8,
    kind: []u8,
    json: []u8,

    pub fn deinit(self: *Record, gpa: std.mem.Allocator) void {
        gpa.free(self.extension_name);
        gpa.free(self.invocation);
        gpa.free(self.kind);
        gpa.free(self.json);
        self.* = undefined;
    }

    pub fn clone(self: Record, gpa: std.mem.Allocator) !Record {
        const extension_name = try gpa.dupe(u8, self.extension_name);
        errdefer gpa.free(extension_name);
        const invocation = try gpa.dupe(u8, self.invocation);
        errdefer gpa.free(invocation);
        const kind = try gpa.dupe(u8, self.kind);
        errdefer gpa.free(kind);
        return .{
            .sequence = self.sequence,
            .extension_name = extension_name,
            .invocation = invocation,
            .kind = kind,
            .json = try gpa.dupe(u8, self.json),
        };
    }
};

pub const Batch = struct {
    items: []Record = &.{},

    pub fn deinit(self: *Batch, gpa: std.mem.Allocator) void {
        for (self.items) |*item| item.deinit(gpa);
        if (self.items.len > 0) gpa.free(self.items);
        self.* = undefined;
    }

    pub fn isEmpty(self: Batch) bool {
        return self.items.len == 0;
    }

    /// Parse the optional `actionQueue` array from a complete invocation result.
    /// Unknown action kinds remain intact for forwards-compatible isolation; the
    /// native applier decides whether it understands a particular kind.
    pub fn parse(
        gpa: std.mem.Allocator,
        extension_name: []const u8,
        invocation: []const u8,
        result_json: []const u8,
    ) !Batch {
        return parseMode(gpa, extension_name, invocation, result_json, false);
    }

    pub fn parseNative(gpa: std.mem.Allocator, extension_name: []const u8, invocation: []const u8, result_json: []const u8) !Batch {
        return parseMode(gpa, extension_name, invocation, result_json, true);
    }

    fn parseMode(gpa: std.mem.Allocator, extension_name: []const u8, invocation: []const u8, result_json: []const u8, native_origins: bool) !Batch {
        var parsed = try std.json.parseFromSlice(std.json.Value, gpa, result_json, .{});
        defer parsed.deinit();
        if (parsed.value != .object) return error.InvalidExtensionActionEnvelope;
        const value = parsed.value.object.get("actionQueue") orelse return .{};
        if (value == .null) return .{};
        if (value != .array or value.array.items.len > max_actions_per_invocation)
            return error.InvalidExtensionActionQueue;

        var records: std.ArrayList(Record) = .empty;
        errdefer {
            for (records.items) |*record| record.deinit(gpa);
            records.deinit(gpa);
        }
        for (value.array.items) |action_value| {
            if (action_value != .object) return error.InvalidExtensionAction;
            const kind_value = action_value.object.get("type") orelse return error.InvalidExtensionAction;
            if (kind_value != .string or kind_value.string.len == 0 or kind_value.string.len > max_action_kind_bytes)
                return error.InvalidExtensionAction;
            for (kind_value.string) |byte| {
                if (!(std.ascii.isAlphanumeric(byte) or byte == '_' or byte == '-'))
                    return error.InvalidExtensionAction;
            }

            const origin_name = if (native_origins) name: {
                const supplied = action_value.object.get("sourceExtensionName") orelse break :name extension_name;
                if (supplied != .string or supplied.string.len == 0 or supplied.string.len > 4096) return error.InvalidExtensionActionOrigin;
                break :name supplied.string;
            } else extension_name;
            const owned_extension = try gpa.dupe(u8, origin_name);
            errdefer gpa.free(owned_extension);
            const owned_invocation = try gpa.dupe(u8, invocation);
            errdefer gpa.free(owned_invocation);
            const owned_kind = try gpa.dupe(u8, kind_value.string);
            errdefer gpa.free(owned_kind);
            const owned_json = try stringify(gpa, action_value);
            errdefer gpa.free(owned_json);
            try records.append(gpa, .{
                .extension_name = owned_extension,
                .invocation = owned_invocation,
                .kind = owned_kind,
                .json = owned_json,
            });
        }
        return .{ .items = try records.toOwnedSlice(gpa) };
    }
};

/// Thread-safe FIFO. Ownership moves from Batch into Queue and from Queue into
/// the returned drain slice; no action payload is copied on the hot path.
pub const Queue = struct {
    gpa: std.mem.Allocator,
    io: Io,
    mutex: std.Io.Mutex = .init,
    items: std.ArrayList(Record) = .empty,
    next_sequence: u64 = 1,

    pub fn init(gpa: std.mem.Allocator, io: Io) Queue {
        return .{ .gpa = gpa, .io = io };
    }

    pub fn deinit(self: *Queue) void {
        self.mutex.lockUncancelable(self.io);
        for (self.items.items) |*record| record.deinit(self.gpa);
        self.items.deinit(self.gpa);
        self.mutex.unlock(self.io);
        self.* = undefined;
    }

    pub fn enqueue(self: *Queue, batch: *Batch) !void {
        if (batch.items.len == 0) return;
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);

        try self.items.ensureUnusedCapacity(self.gpa, batch.items.len);
        for (batch.items) |*record| {
            record.sequence = self.next_sequence;
            self.next_sequence +%= 1;
            if (self.next_sequence == 0) self.next_sequence = 1;
            self.items.appendAssumeCapacity(record.*);
            record.* = undefined;
        }
        self.gpa.free(batch.items);
        batch.items = &.{};
    }

    pub fn drain(self: *Queue) ![]Record {
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);
        if (self.items.items.len == 0) return &.{};
        const result = try self.items.toOwnedSlice(self.gpa);
        self.items = .empty;
        return result;
    }

    pub fn count(self: *Queue) usize {
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);
        return self.items.items.len;
    }

    /// Move a source FIFO into its sole downstream FIFO. Reserve before
    /// publishing any move so allocation failure leaves every source record.
    /// Callers use one direction (Host capture -> Bridge) to order the locks.
    pub fn transferTo(self: *Queue, destination: *Queue) !void {
        if (self == destination) return;
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);
        destination.mutex.lockUncancelable(destination.io);
        defer destination.mutex.unlock(destination.io);
        try destination.items.ensureUnusedCapacity(destination.gpa, self.items.items.len);
        for (self.items.items) |record| {
            var moved = record;
            moved.sequence = destination.next_sequence;
            destination.next_sequence +%= 1;
            if (destination.next_sequence == 0) destination.next_sequence = 1;
            destination.items.appendAssumeCapacity(moved);
        }
        self.items.clearRetainingCapacity();
    }
};

pub fn freeRecords(gpa: std.mem.Allocator, records: []Record) void {
    for (records) |*record| record.deinit(gpa);
    if (records.len > 0) gpa.free(records);
}

fn stringify(gpa: std.mem.Allocator, value: std.json.Value) ![]u8 {
    var out: std.Io.Writer.Allocating = .init(gpa);
    errdefer out.deinit();
    try std.json.Stringify.value(value, .{}, &out.writer);
    return try out.toOwnedSlice();
}

test "action batches preserve invocation order and canonical payloads" {
    const gpa = std.testing.allocator;
    var batch = try Batch.parse(
        gpa,
        "sample",
        "after_tool",
        "{\"actionQueue\":[{\"type\":\"set_session_name\",\"name\":\"one\"},{\"type\":\"append_entry\",\"customType\":\"state\",\"data\":{\"n\":2}}]}",
    );
    defer batch.deinit(gpa);
    try std.testing.expectEqual(@as(usize, 2), batch.items.len);
    try std.testing.expectEqualStrings("sample", batch.items[0].extension_name);
    try std.testing.expectEqualStrings("after_tool", batch.items[0].invocation);
    try std.testing.expectEqualStrings("set_session_name", batch.items[0].kind);
    try std.testing.expect(std.mem.indexOf(u8, batch.items[1].json, "\"n\":2") != null);
}

test "native action provenance is admitted only by the native parsing boundary" {
    const gpa = std.testing.allocator;
    const raw = "{\"actionQueue\":[{\"type\":\"abort\",\"sourceExtensionName\":\"actual-owner\"}]}";
    var legacy = try Batch.parse(gpa, "legacy-target", "hook", raw);
    defer legacy.deinit(gpa);
    try std.testing.expectEqualStrings("legacy-target", legacy.items[0].extension_name);
    var native = try Batch.parseNative(gpa, "native-target", "hook", raw);
    defer native.deinit(gpa);
    try std.testing.expectEqualStrings("actual-owner", native.items[0].extension_name);
    try std.testing.expectError(error.InvalidExtensionActionOrigin, Batch.parseNative(gpa, "target", "hook", "{\"actionQueue\":[{\"type\":\"abort\",\"sourceExtensionName\":null}]}"));
}

test "queue moves batches atomically and assigns monotonic sequence numbers" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    var queue = Queue.init(gpa, io);
    defer queue.deinit();

    var first = try Batch.parse(gpa, "a", "hook", "{\"actionQueue\":[{\"type\":\"abort\"},{\"type\":\"shutdown\"}]}");
    defer first.deinit(gpa);
    try queue.enqueue(&first);
    try std.testing.expect(first.isEmpty());
    try std.testing.expectEqual(@as(usize, 2), queue.count());

    const drained = try queue.drain();
    defer freeRecords(gpa, drained);
    try std.testing.expectEqual(@as(u64, 1), drained[0].sequence);
    try std.testing.expectEqual(@as(u64, 2), drained[1].sequence);
    try std.testing.expectEqual(@as(usize, 0), queue.count());
}

test "malformed action queues are rejected without leaking" {
    const gpa = std.testing.allocator;
    try std.testing.expectError(
        error.InvalidExtensionAction,
        Batch.parse(gpa, "x", "hook", "{\"actionQueue\":[{\"type\":\"bad kind\"}]}"),
    );
    try std.testing.expectError(
        error.InvalidExtensionActionQueue,
        Batch.parse(gpa, "x", "hook", "{\"actionQueue\":{}}"),
    );
}

test "FIFO downstream allocation failure retains all source records and order for retry" {
    const gpa = std.testing.allocator;
    var source = Queue.init(gpa, std.testing.io);
    defer source.deinit();
    var batch = try Batch.parseNative(gpa, "owner", "renderer", "{\"actionQueue\":[{\"type\":\"abort\"},{\"type\":\"shutdown\"}]}");
    defer batch.deinit(gpa);
    try source.enqueue(&batch);
    var failing = std.testing.FailingAllocator.init(gpa, .{ .fail_index = 0 });
    var destination = Queue.init(failing.allocator(), std.testing.io);
    defer destination.deinit();
    try std.testing.expectError(error.OutOfMemory, source.transferTo(&destination));
    try std.testing.expectEqual(@as(usize, 2), source.count());
    try std.testing.expectEqual(@as(usize, 0), destination.count());
    failing.fail_index = std.math.maxInt(usize);
    try source.transferTo(&destination);
    try std.testing.expectEqual(@as(usize, 0), source.count());
    const records = try destination.drain();
    defer freeRecords(failing.allocator(), records);
    try std.testing.expectEqualStrings("abort", records[0].kind);
    try std.testing.expectEqualStrings("shutdown", records[1].kind);
    try std.testing.expectEqual(@as(u64, 1), records[0].sequence);
    try std.testing.expectEqual(@as(u64, 2), records[1].sequence);
}
