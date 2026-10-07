const std = @import("std");
const storage = @import("backend/jsonl.zig");
const json = storage.json;
const session = @import("session.zig");
const local = @import("execution_env.zig");
const types = @import("types.zig");
test "durable.session JSONL backend publishes only committed transactions and reopens physical records" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    var environ = try std.process.Environ.createMap(std.testing.environ, gpa);
    defer environ.deinit();
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const length = try tmp.dir.realPath(io, &buffer);
    var provider = try local.ExecutionEnv.init(gpa, io, .{ .cwd = buffer[0..length], .environ = &environ, .temp_dir = buffer[0..length] });
    defer provider.deinit();
    var store = try storage.Jsonl.open(gpa, ".", &provider, .{}, .{ .fsync = true });
    defer store.deinit();
    var owner = session.Session.init(gpa, io, .{ .jsonl = &store });
    defer owner.deinit();
    const Calls = struct {
        fn root(_: ?*anyopaque, tx: *session.Transaction, _: types.Context) !json.Value {
            return tx.createRootConversation();
        }
        fn failed(_: ?*anyopaque, tx: *session.Transaction, _: types.Context) !json.Value {
            _ = try tx.appendEntry(1, .{ .object = .empty });
            return error.OriginalJsonlCallback;
        }
        fn entry(_: ?*anyopaque, tx: *session.Transaction, _: types.Context) !json.Value {
            var value = try json.Owned.empty(tx.gpa);
            defer value.deinit();
            value.value = .{ .object = .empty };
            try value.value.object.put(value.arena.allocator(), "kind", .{ .string = "entry" });
            try value.value.object.put(value.arena.allocator(), "data", .{ .string = "persisted-through-Session" });
            return tx.appendEntry(1, value.value);
        }
    };
    var root = try owner.commit(Calls.root, null, .{}, .{});
    defer root.deinit();
    try std.testing.expectEqual(@as(?u64, 1), root.seq);
    try std.testing.expectError(error.OriginalJsonlCallback, owner.commit(Calls.failed, null, .{}, .{}));
    var committed = try owner.commit(Calls.entry, null, .{}, .{});
    defer committed.deinit();
    try std.testing.expectEqual(@as(?u64, 2), committed.seq);
    const id = try json.asInteger(committed.value.value.object.get("id").?);
    var reopened = try storage.Jsonl.open(gpa, ".", &provider, .{}, .{});
    defer reopened.deinit();
    var record = (try reopened.readEntry(gpa, id, 1)).?;
    defer record.deinit();
    try std.testing.expectEqualStrings("persisted-through-Session", record.value.object.get("entry").?.object.get("data").?.string);
    const physical = try tmp.dir.readFileAlloc(io, "main.jsonl", gpa, .limited(1024 * 1024));
    defer gpa.free(physical);
    try std.testing.expectEqual(@as(usize, 2), std.mem.count(u8, physical, "\n"));
}
