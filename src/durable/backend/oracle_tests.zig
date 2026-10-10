//! Captured pinned upstream MemoryStorage calls; fixture files are data only.
const std = @import("std");
const memory = @import("memory.zig");
const query = @import("query.zig");
const sqlite = @import("sqlite.zig");
const json = memory.json;
fn point(input: json.Value) !memory.Point {
    const at = json.get(input, "at") orelse return .current;
    return if (at == .string and std.mem.eql(u8, at.string, "current")) .current else .{ .seq = try json.asInteger(at) };
}

fn executeSqlite(store: *sqlite.Sqlite, input: json.Value, gpa: std.mem.Allocator) !?json.Owned {
    const op = try json.asString(try memory.field(input, "op"));
    if (std.mem.eql(u8, op, "mint") or std.mem.eql(u8, op, "commit")) {
        const result = if (std.mem.eql(u8, op, "mint")) try store.mintId() else try store.commitAt(try memory.field(input, "writes"), try optionalInt(input, "seq"));
        var owned = try json.Owned.empty(gpa);
        owned.value = .{ .integer = @intCast(result) };
        return owned;
    }
    if (std.mem.eql(u8, op, "record")) return store.readRecord(gpa, try json.asInteger(try memory.field(input, "id")));
    if (std.mem.eql(u8, op, "entry")) return store.readEntry(gpa, try json.asInteger(try memory.field(input, "id")), try optionalInt(input, "conversationId"));
    if (std.mem.eql(u8, op, "document")) return store.readDocument(gpa, try json.asInteger(try memory.field(input, "id")), try point(input));
    if (std.mem.eql(u8, op, "findDocument")) return store.findDocument(gpa, try memory.field(input, "address"), try point(input));
    if (std.mem.eql(u8, op, "scan")) {
        const filters = try memory.field(input, "query");
        return try store.scan(gpa, .{ .table = std.meta.stringToEnum(memory.Table, try json.asString(try memory.field(input, "table"))).?, .filters = filters, .limit = try json.asInteger(try memory.field(input, "limit")), .after = try optionalInt(input, "after"), .conversationId = try optionalInt(filters, "conversationId"), .minEntryId = try optionalInt(filters, "minEntryId"), .maxEntryId = try optionalInt(filters, "maxEntryId"), .at = try point(filters) });
    }
    return error.UnknownOracleOperation;
}
test "durable SQLite replay and reopen preserve all 36 upstream backend trace results" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    var fixture = try json.Owned.parse(gpa, @embedFile("../fixtures/storage_b78.json"));
    defer fixture.deinit();
    var scratch = std.testing.tmpDir(.{});
    defer scratch.cleanup();
    var buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const length = try scratch.dir.realPath(io, &buffer);
    const path = try std.fs.path.join(gpa, &.{ buffer[0..length], "trace.sqlite" });
    defer gpa.free(path);
    var store = try sqlite.Sqlite.open(gpa, io, path, .{});
    defer store.deinit();
    for ((try memory.field(fixture.value, "events")).array.items, 0..) |event, index| {
        var result = executeSqlite(store, try memory.field(event, "input"), gpa) catch |err| {
            const expected = json.get(event, "error") orelse {
                std.debug.print("SQLite oracle event {d} unexpected {s}\n", .{ index, @errorName(err) });
                return err;
            };
            try std.testing.expectEqualStrings(try json.asString(try memory.field(expected, "message")), store.model.lastRejection orelse @errorName(err));
            continue;
        };
        defer if (result) |*owned| owned.deinit();
        if (json.get(event, "error") != null) return error.ExpectedStorageRejection;
        try std.testing.expect(json.equal(try memory.field(event, "result"), if (result) |owned| owned.value else .null));
        // Reopen each accepted write, proving the in-memory result is durable.
        const op = try json.asString(try memory.field(try memory.field(event, "input"), "op"));
        if (std.mem.eql(u8, op, "commit")) {
            const replacement = try sqlite.Sqlite.open(gpa, io, path, .{});
            store.deinit();
            store = replacement;
        }
    }
}
fn optionalInt(input: json.Value, key: []const u8) !?u64 {
    return if (json.get(input, key)) |value| try json.asInteger(value) else null;
}
fn execute(store: *memory.Memory, input: json.Value, gpa: std.mem.Allocator) !?json.Owned {
    const op = try json.asString(try memory.field(input, "op"));
    if (std.mem.eql(u8, op, "mint") or std.mem.eql(u8, op, "commit")) {
        const result = if (std.mem.eql(u8, op, "mint")) try store.mintId() else blk: {
            var prepared = try store.prepare(try memory.field(input, "writes"), try optionalInt(input, "seq"));
            defer prepared.deinit();
            break :blk try prepared.apply();
        };
        var owned = try json.Owned.empty(gpa);
        owned.value = .{ .integer = @intCast(result) };
        return owned;
    }
    if (std.mem.eql(u8, op, "record")) return store.readRecord(gpa, try json.asInteger(try memory.field(input, "id")));
    if (std.mem.eql(u8, op, "entry")) return query.entry(gpa, store, try json.asInteger(try memory.field(input, "id")), try optionalInt(input, "conversationId"));
    if (std.mem.eql(u8, op, "document")) return store.readDocument(gpa, try json.asInteger(try memory.field(input, "id")), try point(input));
    if (std.mem.eql(u8, op, "findDocument")) return query.findDocument(gpa, store, try memory.field(input, "address"), try point(input));
    if (std.mem.eql(u8, op, "scan")) {
        const filters = try memory.field(input, "query");
        return try query.scan(gpa, store, .{ .table = std.meta.stringToEnum(memory.Table, try json.asString(try memory.field(input, "table"))).?, .filters = filters, .limit = try json.asInteger(try memory.field(input, "limit")), .after = try optionalInt(input, "after"), .conversationId = try optionalInt(filters, "conversationId"), .minEntryId = try optionalInt(filters, "minEntryId"), .maxEntryId = try optionalInt(filters, "maxEntryId"), .at = try point(filters) });
    }
    return error.UnknownOracleOperation;
}
test "durable memory  and  query calls match 36 source backed upstream events" {
    const gpa = std.testing.allocator;
    var fixture = try json.Owned.parse(gpa, @embedFile("../fixtures/storage_b78.json"));
    defer fixture.deinit();
    var store = try memory.Memory.init(gpa);
    defer store.deinit();
    const events = (try memory.field(fixture.value, "events")).array.items;
    try std.testing.expectEqual(@as(usize, 36), events.len);
    for (events, 0..) |event, index| {
        const input = try memory.field(event, "input");
        var result = execute(&store, input, gpa) catch |err| {
            const expected = json.get(event, "error") orelse {
                std.debug.print("Storage oracle event {d} unexpected {s}\n", .{ index, @errorName(err) });
                return err;
            };
            const message = store.lastRejection orelse @errorName(err);
            std.testing.expectEqualStrings(try json.asString(try memory.field(expected, "message")), message) catch |failure| {
                std.debug.print("Storage oracle event {d}\n", .{index});
                return failure;
            };
            continue;
        };
        defer if (result) |*owned| owned.deinit();
        if (json.get(event, "error")) |expected| {
            std.debug.print("Storage oracle event {d} expected error {s}\n", .{ index, try json.asString(try memory.field(expected, "message")) });
            return error.ExpectedStorageRejection;
        }
        const expected = try memory.field(event, "result");
        const actual = if (result) |owned| owned.value else json.Value.null;
        if (!json.equal(expected, actual)) {
            const encoded = try json.stringify(gpa, actual);
            defer gpa.free(encoded);
            const wanted = try json.stringify(gpa, expected);
            defer gpa.free(wanted);
            std.debug.print("Storage oracle event {d} expected {s}\nactual {s}\n", .{ index, wanted, encoded });
            return error.StorageOracleMismatch;
        }
    }
}
