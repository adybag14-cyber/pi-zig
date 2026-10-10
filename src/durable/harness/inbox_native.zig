//! The canonical InboxDoc withdrawal used by native scheduler commits.
//! This callback contains owned JSON and backend operations only; workers never
//! enter the guest VM, its document proxies, or its listener callbacks.
const std = @import("std");
const backend = @import("../backend/root.zig");
const session = @import("../session.zig");
const json = backend.json;
const Value = json.Value;
pub fn withdraw(_: ?*anyopaque, tx: *session.Transaction, conversation: u64) !void {
    const a = tx.owned.arena.allocator();
    var scope: Value = .{ .object = .empty };
    try scope.object.put(a, "kind", .{ .string = "conversation" });
    try scope.object.put(a, "conversationId", .{ .integer = @intCast(conversation) });
    var address: Value = .{ .object = .empty };
    try address.object.put(a, "kind", .{ .string = "pi.inbox" });
    try address.object.put(a, "scope", scope);
    var view: backend.memory.Memory = .{ .gpa = tx.gpa, .state = try tx.session.storage.snapshot(tx.gpa) };
    defer view.deinit();
    var found = try backend.query.findDocument(tx.gpa, &view, address, .current);
    defer if (found) |*record| record.deinit();
    var value: Value = undefined;
    var id: u64 = undefined;
    var record: Value = undefined;
    const created = found == null;
    if (found) |existing| {
        id = try json.asInteger(try json.required(existing.value, "id"));
        record = existing.value;
        var contents = (try tx.session.storage.readDocument(tx.gpa, id, .current)) orelse return error.InboxDocumentMissing;
        defer contents.deinit();
        if (try json.asInteger(try json.required(contents.value, "version")) != 1) return error.InboxDocumentVersionMismatch;
        value = try json.clone(a, try json.required(contents.value, "value"));
    } else {
        if ((try tx.currentRecord(conversation, .conversation)) == null) return error.UnknownConversation;
        id = try tx.session.storage.mintId();
        record = try json.clone(a, address);
        try record.object.put(a, "id", .{ .integer = @intCast(id) });
        try record.object.put(a, "history", .{ .string = "latest" });
        try record.object.put(a, "fork", .{ .string = "initial" });
        value = .{ .object = .empty };
        try value.object.put(a, "items", .{ .array = .init(a) });
    }
    const items = value.object.getPtr("items") orelse return error.MissingField;
    if (items.* != .array) return error.InvalidInboxItems;
    var operations: Value = .{ .array = .init(a) };
    var index = items.array.items.len;
    while (index > 0) {
        index -= 1;
        const item = items.array.items[index];
        if (std.mem.eql(u8, try json.asString(try json.required(item, "mode")), "write")) continue;
        var settlement: Value = .{ .object = .empty };
        try settlement.object.put(a, "status", .{ .string = "unanswered" });
        try settlement.object.put(a, "reason", .{ .string = "aborted" });
        try tx.changeSubmission(try json.asInteger(try json.required(item, "id")), settlement);
        // Preserve the actual Source splice sequence, including indices before
        // each removal, rather than replacing it with an equivalent final diff.
        var operation: Value = .{ .array = .init(a) };
        try operation.array.append(.{ .string = "p" });
        var path: Value = .{ .array = .init(a) };
        try path.array.append(.{ .string = "items" });
        try operation.array.append(path);
        try operation.array.append(.{ .integer = @intCast(index) });
        try operation.array.append(.{ .integer = 1 });
        try operation.array.append(.{ .array = .init(a) });
        try operations.array.append(operation);
        _ = items.array.orderedRemove(index);
    }
    if (!created and operations.array.items.len == 0) return;
    var content: Value = .{ .object = .empty };
    try content.object.put(a, "version", .{ .integer = 1 });
    const checkpoint = created or items.array.items.len == 0;
    try content.object.put(a, "kind", .{ .string = if (checkpoint) "base" else "delta" });
    try content.object.put(a, if (checkpoint) "value" else "ops", if (checkpoint) value else operations);
    var write: Value = .{ .object = .empty };
    try write.object.put(a, "type", .{ .string = if (created) "document.create" else "document.change" });
    try write.object.put(a, if (created) "record" else "id", if (created) record else Value{ .integer = @intCast(id) });
    try write.object.put(a, "content", content);
    if (!created) try tx.documentPublicationOps(id, operations);
    try tx.documentCommand(write);
}
fn exercise(gpa: std.mem.Allocator, keep_write: bool) !void {
    var store = try backend.memory.Memory.init(gpa);
    defer store.deinit();
    var owner = session.Session.init(gpa, std.testing.io, .{ .memory = &store });
    defer owner.deinit();
    var scheduler = try @import("../scheduler.zig").Scheduler.init(gpa, std.testing.io, &owner, .{ .withdraw_inputs = withdraw });
    defer scheduler.deinit();
    const Seed = struct {
        keep: bool,
        ids: [3]u64 = undefined,
        count: usize = 0,
        doc: u64 = 0,
        fn root(_: ?*anyopaque, tx: *session.Transaction, _: @import("../types.zig").Context) !Value {
            return tx.createRootConversation();
        }
        fn seed(raw: ?*anyopaque, tx: *session.Transaction, _: @import("../types.zig").Context) !Value {
            const self: *@This() = @ptrCast(@alignCast(raw.?));
            const a = tx.owned.arena.allocator();
            var items: Value = .{ .array = .init(a) };
            for (0..if (self.keep) @as(usize, 3) else 2) |index| {
                const is_write = self.keep and index == 1;
                var create: Value = .{ .object = .empty };
                try create.object.put(a, "conversationId", .{ .integer = 1 });
                try create.object.put(a, "type", .{ .string = if (is_write) "write" else "input" });
                try create.object.put(a, "status", .{ .string = "queued" });
                const record = try tx.createSubmission(create);
                const id = try json.asInteger(try json.required(record, "id"));
                self.ids[index] = id;
                self.count += 1;
                var item: Value = .{ .object = .empty };
                try item.object.put(a, "id", .{ .integer = @intCast(id) });
                try item.object.put(a, "mode", .{ .string = if (is_write) "write" else if (index == 0) "steer" else "followUp" });
                if (is_write) {
                    var entry: Value = .{ .object = .empty };
                    try entry.object.put(a, "kind", .{ .string = "fixture.queued-write" });
                    try item.object.put(a, "entry", entry);
                } else try item.object.put(a, "content", .{ .string = if (index == 0) "one" else "two" });
                try items.array.append(item);
            }
            self.doc = try tx.session.storage.mintId();
            var scope: Value = .{ .object = .empty };
            try scope.object.put(a, "kind", .{ .string = "conversation" });
            try scope.object.put(a, "conversationId", .{ .integer = 1 });
            var record: Value = .{ .object = .empty };
            try record.object.put(a, "id", .{ .integer = @intCast(self.doc) });
            try record.object.put(a, "kind", .{ .string = "pi.inbox" });
            try record.object.put(a, "scope", scope);
            try record.object.put(a, "history", .{ .string = "latest" });
            try record.object.put(a, "fork", .{ .string = "initial" });
            var value: Value = .{ .object = .empty };
            try value.object.put(a, "items", items);
            var content: Value = .{ .object = .empty };
            try content.object.put(a, "kind", .{ .string = "base" });
            try content.object.put(a, "version", .{ .integer = 1 });
            try content.object.put(a, "value", value);
            var write: Value = .{ .object = .empty };
            try write.object.put(a, "type", .{ .string = "document.create" });
            try write.object.put(a, "record", record);
            try write.object.put(a, "content", content);
            try tx.documentCommand(write);
            return .null;
        }
    };
    var seed: Seed = .{ .keep = keep_write };
    var root = try owner.commit(Seed.root, null, .{}, .{});
    root.deinit();
    var seeded = try owner.commit(Seed.seed, &seed, .{}, .{});
    seeded.deinit();
    const Capture = struct {
        ids: [3]u64,
        count: usize,
        order: [3]usize = undefined,
        observed: usize = 0,
        fn receive(raw: ?*anyopaque, event: *const session.Publication, _: @import("../types.zig").Context) !void {
            const self: *@This() = @ptrCast(@alignCast(raw.?));
            for (event.changes.array.items) |change| {
                if (self.observed >= 3) return error.UnexpectedPublication;
                const kind = try json.asString(try json.required(change, "type"));
                if (std.mem.eql(u8, kind, "document")) {
                    self.order[self.observed] = 3;
                } else {
                    const id = try json.asInteger(try json.required(try json.required(change, "value"), "id"));
                    self.order[self.observed] = std.mem.indexOfScalar(u64, self.ids[0..self.count], id) orelse return error.UnexpectedPublication;
                }
                self.observed += 1;
            }
        }
    };
    var capture: Capture = .{ .ids = seed.ids, .count = seed.count };
    _ = try owner.subscribe(Capture.receive, &capture);
    const reached = (try scheduler.tryAbortConversation(gpa, 1, false, .{})).?;
    defer gpa.free(reached);
    try std.testing.expectEqual(@as(usize, 0), reached.len);
    try std.testing.expectEqual(@as(usize, 3), capture.observed);
    try std.testing.expectEqual(seed.count - 1, capture.order[0]);
    try std.testing.expectEqual(@as(usize, 0), capture.order[1]);
    try std.testing.expectEqual(@as(usize, 3), capture.order[2]);
    var source = try json.Owned.parse(gpa, @embedFile("../fixtures/durable-withdraw-inbox-source.json"));
    defer source.deinit();
    const expected = (try json.required(source.value, "cases")).array.items[if (keep_write) @as(usize, 0) else 1];
    const expected_content = try json.required((try json.required(expected, "writes")).array.items[0].array.items[2], "content");
    const revisions = store.state.documents.get(seed.doc).?.revisions.items;
    try std.testing.expect(json.equal(expected_content, revisions[revisions.len - 1].content));
    var contents = (try store.readDocument(gpa, seed.doc, .current)).?;
    defer contents.deinit();
    const items = try json.required(try json.required(contents.value, "value"), "items");
    try std.testing.expectEqual(if (keep_write) @as(usize, 1) else 0, items.array.items.len);
    if (keep_write) try std.testing.expectEqual(seed.ids[1], try json.asInteger(try json.required(items.array.items[0], "id")));
    for (seed.ids[0..seed.count], 0..) |id, index| {
        var row = (try store.readRecord(gpa, id)).?;
        defer row.deinit();
        try std.testing.expectEqualStrings(if (keep_write and index == 1) "queued" else "unanswered", try json.asString(try json.required(row.value, "status")));
    }
}
test "durable.scheduler canonical native inbox withdrawal preserves actual Source splice checkpoint and publication order" {
    try exercise(std.testing.allocator, true);
    try exercise(std.testing.allocator, false);
}
test "durable.scheduler canonical native inbox withdrawal unwinds every allocation failure" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, exercise, .{true});
    try std.testing.checkAllAllocationFailures(std.testing.allocator, exercise, .{false});
}
