//! Detached native durable state. A prepared commit publishes without allocation.
const std = @import("std");
pub const json = @import("json.zig");
const delta = @import("delta.zig");
pub const Value = json.Value;
pub const max_integer = 9007199254740991;
pub fn requestKey(gpa: std.mem.Allocator, conversation: Value, request: Value) ![]u8 {
    var tuple = [_]Value{ conversation, request };
    return json.stringify(gpa, .{ .array = std.array_list.Managed(Value).fromOwnedSlice(gpa, &tuple) });
}
pub const Table = enum { conversation, entry, task, submission, document };
pub const Point = union(enum) { current, seq: u64 };
pub const Row = struct { table: Table, record: Value, commitSeq: u64 };
pub const Revision = struct { seq: u64, content: Value };
pub const Document = struct { record: Value, revisions: std.array_list.Managed(Revision) };
pub const State = struct {
    arena: std.heap.ArenaAllocator,
    rows: std.AutoHashMap(u64, Row),
    documents: std.AutoHashMap(u64, Document),
    submissionRequests: std.StringHashMap(u64),
    nextId: u64 = 2,
    nextSeq: u64 = 1,
    pub fn create(gpa: std.mem.Allocator) !*State {
        const state = try gpa.create(State);
        state.arena = std.heap.ArenaAllocator.init(gpa);
        const allocator = state.arena.allocator();
        state.rows = .init(allocator);
        state.documents = .init(allocator);
        state.submissionRequests = .init(allocator);
        state.nextId = 2;
        state.nextSeq = 1;
        return state;
    }
    pub fn destroy(self: *State, gpa: std.mem.Allocator) void {
        self.arena.deinit();
        gpa.destroy(self);
    }
    pub fn duplicate(self: *const State, gpa: std.mem.Allocator) !*State {
        const copy = try create(gpa);
        errdefer copy.destroy(gpa);
        const allocator = copy.arena.allocator();
        copy.nextId = self.nextId;
        copy.nextSeq = self.nextSeq;
        var rows = self.rows.iterator();
        while (rows.next()) |item| try copy.rows.put(item.key_ptr.*, .{ .table = item.value_ptr.table, .record = try json.clone(allocator, item.value_ptr.record), .commitSeq = item.value_ptr.commitSeq });
        var docs = self.documents.iterator();
        while (docs.next()) |item| {
            var document: Document = .{ .record = try json.clone(allocator, item.value_ptr.record), .revisions = .init(allocator) };
            for (item.value_ptr.revisions.items) |revision| try document.revisions.append(.{ .seq = revision.seq, .content = try json.clone(allocator, revision.content) });
            try copy.documents.put(item.key_ptr.*, document);
        }
        var requests = self.submissionRequests.iterator();
        while (requests.next()) |entry| try copy.submissionRequests.put(try allocator.dupe(u8, entry.key_ptr.*), entry.value_ptr.*);
        return copy;
    }
};
pub const Prepared = struct {
    owner: *Memory,
    state: ?*State,
    generation: u64,
    seq: u64,
    /// Detached, resolved writes used by portable publication backends.
    writes: Value = .null,
    applied: bool = false,
    pub fn deinit(self: *Prepared) void {
        if (self.state) |state| state.destroy(self.owner.gpa);
        self.* = undefined;
    }
    pub fn apply(self: *Prepared) !u64 {
        if (self.applied) return self.seq;
        try self.owner.assertOpen();
        if (self.generation != self.owner.generation) return error.StalePreparedCommit;
        const old = self.owner.state;
        const replacement = self.state.?;
        replacement.nextId = @max(replacement.nextId, old.nextId);
        self.owner.state = replacement;
        self.owner.generation += 1;
        self.state = null;
        self.applied = true;
        old.destroy(self.owner.gpa);
        return self.seq;
    }
};
const Action = struct { create: ?Value = null, content: ?Value = null, retire: bool = false };
pub const Materialized = struct { record: Value, version: u64, value: Value, deltasSinceBase: u64 };
pub fn field(value: Value, name: []const u8) !Value {
    return json.required(value, name);
}
pub fn idOf(value: Value) !u64 {
    return json.asInteger(try field(value, "id"));
}
pub fn currentOnly(record: Value) !bool {
    return !std.mem.eql(u8, try json.asString(try field(try field(record, "scope"), "kind")), "conversation") or (if (json.get(record, "history")) |history| std.mem.eql(u8, try json.asString(history), "latest") else false);
}
pub fn alive(record: Value, point: Point) !bool {
    const retired = json.get(record, "retiredAt");
    return switch (point) {
        .current => retired == null,
        .seq => |seq| (try json.asInteger(try field(record, "createdAt"))) <= seq and (retired == null or seq < try json.asInteger(retired.?)),
    };
}
pub fn sameAddress(a: Value, b: Value) !bool {
    const akey = json.get(a, "key");
    const bkey = json.get(b, "key");
    return json.equal(try field(a, "kind"), try field(b, "kind")) and json.equal(try field(a, "scope"), try field(b, "scope")) and ((akey == null and bkey == null) or (akey != null and bkey != null and json.equal(akey.?, bkey.?)));
}
pub fn materialize(gpa: std.mem.Allocator, state: *const State, id: u64, point: Point) !?Materialized {
    const stored = state.documents.get(id) orelse return null;
    if (point == .seq and try currentOnly(stored.record)) return error.DocumentDoesNotRetainHistory;
    if (!try alive(stored.record, point)) return null;
    var last: usize = stored.revisions.items.len;
    if (point == .seq) {
        last = 0;
        for (stored.revisions.items) |revision| {
            if (revision.seq <= point.seq) last += 1 else break;
        }
    }
    var base = last;
    while (base > 0) {
        base -= 1;
        if (std.mem.eql(u8, try json.asString(try field(stored.revisions.items[base].content, "kind")), "base")) break;
    }
    if (last == 0 or !std.mem.eql(u8, try json.asString(try field(stored.revisions.items[base].content, "kind")), "base")) return error.DocumentMissingBase;
    const revision = stored.revisions.items[base].content;
    const version = try json.asInteger(try field(revision, "version"));
    var value = try json.clone(gpa, try field(revision, "value"));
    for (stored.revisions.items[base + 1 .. last]) |item| {
        if (!std.mem.eql(u8, try json.asString(try field(item.content, "kind")), "delta") or try json.asInteger(try field(item.content, "version")) != version) return error.DocumentVersionBoundary;
        try delta.apply(gpa, &value, try field(item.content, "ops"));
    }
    return .{ .record = try json.clone(gpa, stored.record), .version = version, .value = value, .deltasSinceBase = last - base - 1 };
}
pub const Memory = struct {
    gpa: std.mem.Allocator,
    state: *State,
    generation: u64 = 0,
    closed: bool = false,
    lastRejection: ?[]u8 = null,
    lastCause: ?anyerror = null,
    lastCauseMessage: ?[]u8 = null,
    pub fn init(gpa: std.mem.Allocator) !Memory {
        return .{ .gpa = gpa, .state = try State.create(gpa) };
    }
    pub fn deinit(self: *Memory) void {
        self.state.destroy(self.gpa);
        if (self.lastRejection) |message| self.gpa.free(message);
        if (self.lastCauseMessage) |message| self.gpa.free(message);
        self.* = undefined;
    }
    pub fn close(self: *Memory) void {
        self.closed = true;
    }
    pub fn assertOpen(self: *const Memory) !void {
        if (self.closed) return error.StorageClosed;
    }
    fn reject(self: *Memory, comptime fmt: []const u8, args: anytype) anyerror {
        const message = std.fmt.allocPrint(self.gpa, fmt, args) catch return error.OutOfMemory;
        if (self.lastRejection) |old| self.gpa.free(old);
        self.lastRejection = message;
        if (self.lastCauseMessage) |old| self.gpa.free(old);
        self.lastCauseMessage = null;
        self.lastCause = null;
        return error.StorageRejected;
    }
    fn rejectCopy(self: *Memory, id: u64, comptime cause_fmt: []const u8, args: anytype, cause: anyerror) anyerror {
        const cause_message = std.fmt.allocPrint(self.gpa, cause_fmt, args) catch return error.OutOfMemory;
        const message = std.fmt.allocPrint(self.gpa, "Document copy {d} was rejected", .{id}) catch {
            self.gpa.free(cause_message);
            return error.OutOfMemory;
        };
        if (self.lastRejection) |old| self.gpa.free(old);
        if (self.lastCauseMessage) |old| self.gpa.free(old);
        self.lastRejection = message;
        self.lastCause = cause;
        self.lastCauseMessage = cause_message;
        return error.StorageRejected;
    }
    pub fn mintId(self: *Memory) !u64 {
        try self.assertOpen();
        if (self.state.nextId > max_integer) return error.IdSpaceExhausted;
        const id = self.state.nextId;
        self.state.nextId += 1;
        return id;
    }
    pub fn prepare(self: *Memory, input: Value, sequence: ?u64) !Prepared {
        try self.assertOpen();
        const seq = sequence orelse self.state.nextSeq;
        if (seq > max_integer or seq < self.state.nextSeq) return self.reject("Commit sequence {d} does not strictly increase", .{seq});
        if (input != .array) return error.ExpectedStorageWriteArray;
        const next = try self.state.duplicate(self.gpa);
        errdefer next.destroy(self.gpa);
        const allocator = next.arena.allocator();
        const writes = try json.clone(allocator, input);
        const normalized = try json.clone(allocator, input);
        var claimed: std.AutoHashMap(u64, Table) = .init(allocator);
        var actions: std.AutoHashMap(u64, Action) = .init(allocator);
        // IDs  and  document actions are checked before touching any staged tables.
        for (writes.array.items) |write| {
            const tag = try json.asString(try field(write, "type"));
            if (std.mem.eql(u8, tag, "document.change") or std.mem.eql(u8, tag, "document.retire")) continue;
            const is_document = std.mem.eql(u8, tag, "document.create") or std.mem.eql(u8, tag, "document.copy");
            const table = if (is_document) Table.document else std.meta.stringToEnum(Table, tag) orelse return error.UnknownStorageWrite;
            const record = try field(write, if (is_document) "record" else "value");
            const id = try idOf(record);
            const existing = self.state.rows.get(id);
            const earlier = claimed.get(id);
            if (table == .conversation or table == .entry or table == .document) {
                if (existing) |row| return self.reject("ID {d} already belongs to {s}", .{ id, @tagName(row.table) });
                if (earlier != null) return self.reject("ID {d} is written more than once", .{id});
            } else {
                if (existing) |row| if (row.table != table) return self.reject("ID {d} already belongs to {s}", .{ id, @tagName(row.table) });
                if (earlier) |kind| if (kind != table) return self.reject("ID {d} is written as two record types", .{id});
            }
            try claimed.put(id, table);
        }
        for (writes.array.items, 0..) |*write, write_index| {
            const tag = try json.asString(try field(write.*, "type"));
            if (!std.mem.startsWith(u8, tag, "document.")) continue;
            const create = std.mem.eql(u8, tag, "document.create") or std.mem.eql(u8, tag, "document.copy");
            const record = if (create) try field(write.*, "record") else null;
            const id = if (record) |value| try idOf(value) else try json.asInteger(try field(write.*, "id"));
            const entry = try actions.getOrPut(id);
            if (!entry.found_existing) entry.value_ptr.* = .{};
            const action = entry.value_ptr;
            if (create) {
                if (action.create != null or action.content != null) return self.reject("Document {d} has more than one content command", .{id});
                action.create = record.?;
                if (std.mem.eql(u8, tag, "document.copy")) {
                    const source = try field(write.*, "source");
                    const source_id = try json.asInteger(try field(source, "id"));
                    for (writes.array.items) |other| {
                        const other_tag = try json.asString(try field(other, "type"));
                        if (std.mem.startsWith(u8, other_tag, "document.")) {
                            const changed_id = if (json.get(other, "record")) |r| try idOf(r) else try json.asInteger(try field(other, "id"));
                            if (changed_id == source_id) return self.rejectCopy(id, "Fork source document {d} is changed in the copy batch", .{source_id}, error.DocumentCopySourceChanged);
                        }
                    }
                    const point_value = try field(source, "at");
                    const point: Point = if (point_value == .string and std.mem.eql(u8, point_value.string, "current")) .current else .{ .seq = try json.asInteger(point_value) };
                    const contents = (materialize(allocator, self.state, source_id, point) catch |err| {
                        if (err == error.OutOfMemory) return err;
                        return self.rejectCopy(id, "Document {d} cannot be read: {s}", .{ source_id, @errorName(err) }, err);
                    }) orelse return self.rejectCopy(id, "Fork source document {d} cannot be read", .{source_id}, error.DocumentCopySourceMissing);
                    const source_scope = try json.asString(try field(try field(contents.record, "scope"), "kind"));
                    const target_scope = try json.asString(try field(try field(record.?, "scope"), "kind"));
                    var compatible = std.mem.eql(u8, source_scope, "conversation") and std.mem.eql(u8, target_scope, "conversation");
                    for ([_][]const u8{ "kind", "key", "history", "fork" }) |name| {
                        const a = json.get(contents.record, name);
                        const b = json.get(record.?, name);
                        if ((a == null) != (b == null) or (a != null and b != null and !json.equal(a.?, b.?))) compatible = false;
                    }
                    if (!compatible) return self.rejectCopy(id, "Fork source document {d} does not match the copied record", .{source_id}, error.DocumentCopyRecordMismatch);
                    var base: Value = .{ .object = .empty };
                    try base.object.put(allocator, "kind", .{ .string = "base" });
                    try base.object.put(allocator, "version", .{ .integer = @intCast(contents.version) });
                    try base.object.put(allocator, "value", contents.value);
                    action.content = base;
                    var resolved: Value = .{ .object = .empty };
                    try resolved.object.put(allocator, "type", .{ .string = "document.create" });
                    try resolved.object.put(allocator, "record", try json.clone(allocator, record.?));
                    try resolved.object.put(allocator, "content", try json.clone(allocator, base));
                    normalized.array.items[write_index] = resolved;
                } else action.content = try field(write.*, "content");
            } else if (std.mem.eql(u8, tag, "document.change")) {
                if (action.content != null) return self.reject("Document {d} has more than one content command", .{id});
                action.content = try field(write.*, "content");
            } else if (std.mem.eql(u8, tag, "document.retire")) {
                if (action.retire) return self.reject("Document {d} is retired more than once", .{id});
                action.retire = true;
            } else return error.UnknownStorageWrite;
        }
        var action_iterator = actions.iterator();
        while (action_iterator.next()) |item| {
            const id = item.key_ptr.*;
            const action = item.value_ptr.*;
            const existing = self.state.documents.get(id);
            if (action.create == null and existing == null) return self.reject("Unknown document: {d}", .{id});
            if (existing) |doc| {
                if (json.get(doc.record, "retiredAt") != null) return self.reject("Document {d} is retired", .{id});
            }
            if (action.content) |content| {
                const kind = try json.asString(try field(content, "kind"));
                _ = try json.asInteger(try field(content, "version"));
                if (std.mem.eql(u8, kind, "delta")) {
                    if (existing == null or existing.?.revisions.items.len == 0) return self.reject("Document {d} delta has no base", .{id});
                    const previous = existing.?.revisions.items[existing.?.revisions.items.len - 1].content;
                    if (!json.equal(try field(previous, "version"), try field(content, "version"))) return self.reject("Document {d} version transition requires a base", .{id});
                } else if (!std.mem.eql(u8, kind, "base") or (try field(content, "value")) != .object) return error.InvalidDocumentContent;
            }
            if (action.create) |record| {
                if (action.retire) continue;
                var docs = self.state.documents.iterator();
                while (docs.next()) |doc| {
                    if (!try alive(doc.value_ptr.record, .current)) continue;
                    const retiring = actions.get(doc.key_ptr.*);
                    if (retiring != null and retiring.?.retire) continue;
                    if (try sameAddress(record, doc.value_ptr.record)) return self.reject("Document address already has a current incarnation", .{});
                }
                var others = actions.iterator();
                while (others.next()) |other| {
                    if (other.key_ptr.* == id or other.value_ptr.retire or other.value_ptr.create == null) continue;
                    if (try sameAddress(record, other.value_ptr.create.?)) return self.reject("Document address already has a current incarnation", .{});
                }
            }
        }
        for (writes.array.items) |write| {
            const tag = try json.asString(try field(write, "type"));
            if (std.mem.startsWith(u8, tag, "document.")) continue;
            const table = std.meta.stringToEnum(Table, tag) orelse return error.UnknownStorageWrite;
            const record = try field(write, "value");
            const id = try idOf(record);
            if (table == .submission) {
                if (next.rows.get(id)) |previous| if (json.get(previous.record, "requestId")) |request| {
                    const key = try requestKey(allocator, try field(previous.record, "conversationId"), request);
                    if (next.submissionRequests.get(key)) |current| if (current == id) {
                        _ = next.submissionRequests.remove(key);
                    };
                };
                if (json.get(record, "requestId")) |request| {
                    const key = try requestKey(allocator, try field(record, "conversationId"), request);
                    try next.submissionRequests.put(key, id);
                }
            }
            try next.rows.put(id, .{ .table = table, .record = record, .commitSeq = seq });
            next.nextId = @max(next.nextId, id + 1);
        }
        action_iterator = actions.iterator();
        while (action_iterator.next()) |item| {
            const id = item.key_ptr.*;
            const action = item.value_ptr.*;
            if (action.create) |record| {
                var created = record;
                try created.object.put(allocator, "createdAt", .{ .integer = @intCast(seq) });
                var doc: Document = .{ .record = created, .revisions = .init(allocator) };
                try doc.revisions.append(.{ .seq = seq, .content = action.content.? });
                try next.documents.put(id, doc);
                next.nextId = @max(next.nextId, id + 1);
            }
            const doc = next.documents.getPtr(id).?;
            if (action.create == null) {
                if (action.content) |content| {
                    if (std.mem.eql(u8, try json.asString(try field(content, "kind")), "base") and try currentOnly(doc.record)) doc.revisions.clearRetainingCapacity();
                    try doc.revisions.append(.{ .seq = seq, .content = content });
                }
            }
            if (action.retire) {
                try doc.record.object.put(allocator, "retiredAt", .{ .integer = @intCast(seq) });
                if (try currentOnly(doc.record)) doc.revisions.clearRetainingCapacity();
            }
            try next.rows.put(id, .{ .table = .document, .record = doc.record, .commitSeq = seq });
        }
        next.nextSeq = seq + 1;
        return .{ .owner = self, .state = next, .generation = self.generation, .seq = seq, .writes = normalized };
    }
    pub fn commit(self: *Memory, writes: Value) !u64 {
        var prepared = try self.prepare(writes, null);
        defer prepared.deinit();
        return prepared.apply();
    }
    pub fn readRecord(self: *const Memory, gpa: std.mem.Allocator, id: u64) !?json.Owned {
        try self.assertOpen();
        const row = self.state.rows.get(id) orelse return null;
        var owned = try json.Owned.empty(gpa);
        errdefer owned.deinit();
        owned.value = try json.clone(owned.arena.allocator(), row.record);
        return owned;
    }
    pub fn readDocument(self: *Memory, gpa: std.mem.Allocator, id: u64, point: Point) !?json.Owned {
        try self.assertOpen();
        var owned = try json.Owned.empty(gpa);
        errdefer owned.deinit();
        const allocator = owned.arena.allocator();
        const contents = (materialize(allocator, self.state, id, point) catch |err| {
            if (err == error.DocumentDoesNotRetainHistory) return self.reject("Document {d} does not retain historical content", .{id});
            return err;
        }) orelse {
            owned.deinit();
            return null;
        };
        var value: Value = .{ .object = .empty };
        try value.object.put(allocator, "record", contents.record);
        try value.object.put(allocator, "version", .{ .integer = @intCast(contents.version) });
        try value.object.put(allocator, "value", contents.value);
        try value.object.put(allocator, "deltasSinceBase", .{ .integer = @intCast(contents.deltasSinceBase) });
        owned.value = value;
        return owned;
    }
};

test "durable memory commits detach validate global ids  and  atomically publish document incarnations" {
    const gpa = std.testing.allocator;
    var store = try Memory.init(gpa);
    defer store.deinit();
    var root = try json.Owned.parse(gpa, "[{\"type\":\"conversation\",\"value\":{\"id\":1}}]");
    defer root.deinit();
    try std.testing.expectEqual(@as(u64, 1), try store.commit(root.value));
    var create = try json.Owned.parse(gpa, "[{\"type\":\"entry\",\"value\":{\"id\":2,\"conversationId\":1,\"kind\":\"test\",\"data\":{\"x\":[1]}}},{\"type\":\"document.create\",\"record\":{\"id\":3,\"kind\":\"state\",\"scope\":{\"kind\":\"conversation\",\"conversationId\":1},\"history\":\"rewindable\",\"fork\":\"asOf\"},\"content\":{\"kind\":\"base\",\"version\":1,\"value\":{\"n\":1}}}]");
    defer create.deinit();
    try std.testing.expectEqual(@as(u64, 2), try store.commit(create.value));
    create.value.array.items[0].object.getPtr("value").?.object.getPtr("data").?.object.getPtr("x").?.array.items[0] = .{ .integer = 99 };
    var detached = (try store.readRecord(gpa, 2)).?;
    defer detached.deinit();
    try std.testing.expectEqual(@as(f64, 1), try json.asNumber((try field(try field(detached.value, "data"), "x")).array.items[0]));
    var invalid = try json.Owned.parse(gpa, "[{\"type\":\"entry\",\"value\":{\"id\":9,\"conversationId\":1,\"kind\":\"test\"}},{\"type\":\"task\",\"value\":{\"id\":2}}]");
    defer invalid.deinit();
    try std.testing.expectError(error.StorageRejected, store.commit(invalid.value));
    try std.testing.expect(store.state.rows.get(9) == null);
    try std.testing.expectEqual(@as(u64, 3), store.state.nextSeq);
    var changed = try json.Owned.parse(gpa, "[{\"type\":\"document.change\",\"id\":3,\"content\":{\"kind\":\"delta\",\"version\":1,\"ops\":[[\"s\",[\"n\"],2]]}}]");
    defer changed.deinit();
    try std.testing.expectEqual(@as(u64, 3), try store.commit(changed.value));
    var historical = (try store.readDocument(gpa, 3, .{ .seq = 2 })).?;
    defer historical.deinit();
    var current = (try store.readDocument(gpa, 3, .current)).?;
    defer current.deinit();
    try std.testing.expectEqual(@as(f64, 1), try json.asNumber(try field(try field(historical.value, "value"), "n")));
    try std.testing.expectEqual(@as(f64, 2), try json.asNumber(try field(try field(current.value, "value"), "n")));
}

test "durable memory preparation is allocation atomic stale safe and detached reads remain mutable" {
    const gpa = std.testing.allocator;
    try std.testing.checkAllAllocationFailures(gpa, struct {
        fn run(allocator: std.mem.Allocator) !void {
            var store = try Memory.init(allocator);
            defer store.deinit();
            var input = try json.Owned.parse(allocator, "[{\"type\":\"conversation\",\"value\":{\"id\":1}},{\"type\":\"entry\",\"value\":{\"id\":2,\"conversationId\":1,\"kind\":\"user\",\"data\":{\"a\":[1]}}}]");
            defer input.deinit();
            var prepared = store.prepare(input.value, null) catch |err| {
                try std.testing.expect(store.state.rows.count() == 0);
                try std.testing.expectEqual(@as(u64, 1), store.state.nextSeq);
                return err;
            };
            defer prepared.deinit();
            try std.testing.expectEqual(@as(u64, 1), try prepared.apply());
            try std.testing.expectEqual(@as(u64, 1), try prepared.apply());
            var read = (try store.readRecord(allocator, 2)).?;
            defer read.deinit();
            try read.value.object.getPtr("data").?.object.getPtr("a").?.array.append(.{ .integer = 99 });
            var again = (try store.readRecord(allocator, 2)).?;
            defer again.deinit();
            try std.testing.expectEqual(@as(usize, 1), again.value.object.getPtr("data").?.object.getPtr("a").?.array.items.len);
            var empty = try json.Owned.parse(allocator, "[]");
            defer empty.deinit();
            var first = try store.prepare(empty.value, null);
            defer first.deinit();
            var second = try store.prepare(empty.value, null);
            defer second.deinit();
            _ = try first.apply();
            try std.testing.expectError(error.StalePreparedCommit, second.apply());
        }
    }.run, .{});
}
