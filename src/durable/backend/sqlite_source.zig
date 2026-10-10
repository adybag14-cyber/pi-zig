//! Original durable SQLite format over the direct SQLite C ABI.
const std = @import("std");
const ffi = @import("../../storage/sqlite/ffi.zig");
const memory = @import("memory.zig");
const query = @import("query.zig");
const json = memory.json;
extern fn sqlite3_exec(db: ?*anyopaque, sql: [*:0]const u8, callback: ?*const anyopaque, context: ?*anyopaque, message: ?*?[*:0]u8) c_int;
fn rollback(db: *ffi.Database) void {
    _ = sqlite3_exec(@ptrCast(db.handle), "ROLLBACK", null, null, null);
}
fn run(db: *ffi.Database, sql: []const u8, values: []const ffi.Value) !void {
    var statement = try db.prepare(sql);
    defer statement.deinit();
    try statement.bindAll(values);
    _ = try statement.run();
}
pub const Options = struct { busy_timeout_ms: u31 = 5000, wal_auto_checkpoint_pages: u31 = 1000 };
pub const Sqlite = struct {
    gpa: std.mem.Allocator,
    io: std.Io,
    db: ffi.Database,
    model: memory.Memory,
    next_id: u64,
    mutex: std.Io.Mutex = .init,
    pub fn open(gpa: std.mem.Allocator, io: std.Io, path: []const u8, options: Options) !*Sqlite {
        if (!std.mem.eql(u8, path, ":memory:")) if (std.fs.path.dirname(path)) |parent| try std.Io.Dir.cwd().createDirPath(io, parent);
        const self = try gpa.create(Sqlite);
        errdefer gpa.destroy(self);
        self.* = .{ .gpa = gpa, .io = io, .db = try ffi.Database.open(gpa, path), .model = undefined, .next_id = 2 };
        errdefer self.db.close();
        try self.db.busyTimeout(options.busy_timeout_ms);
        try self.db.exec("PRAGMA journal_mode=WAL; PRAGMA synchronous=NORMAL");
        const checkpoint = try std.fmt.allocPrint(gpa, "PRAGMA wal_autocheckpoint={d}", .{options.wal_auto_checkpoint_pages});
        defer gpa.free(checkpoint);
        try self.db.exec(checkpoint);
        try self.db.beginImmediate();
        var active = true;
        defer if (active) rollback(&self.db);
        try self.db.exec("CREATE TABLE IF NOT EXISTS durable_schema(singleton INTEGER PRIMARY KEY CHECK(singleton=1),version INTEGER NOT NULL CHECK(version>=0)) STRICT; INSERT OR IGNORE INTO durable_schema VALUES(1,0)");
        var schema = try self.db.prepare("SELECT version FROM durable_schema WHERE singleton=1");
        defer schema.deinit();
        if (try schema.step() != .row) return error.MissingSourceSqliteSchema;
        const version = try schema.columnInt(0);
        if (try schema.step() != .done or version < 0 or version > 1) return error.UnsupportedSourceSqliteSchema;
        if (version == 0) {
            // Do not reinterpret a previous private backend as an empty database.
            var legacy = try self.db.prepare("SELECT count(*) FROM sqlite_master WHERE type='table' AND name='pi_durable_metadata'");
            defer legacy.deinit();
            if (try legacy.step() != .row) return error.InvalidSourceSqliteSchema;
            const import_private = try legacy.columnInt(0) != 0;
            const private_state = if (import_private) try self.loadPrivateState() else null;
            defer if (private_state) |value| value.destroy(gpa);
            try self.db.exec(@embedFile("sqlite_source_schema.sql"));
            if (private_state) |value| {
                try self.persist(value);
                // The prior private writer's next mutation must observe lost ownership.
                try self.db.exec("UPDATE pi_durable_metadata SET writer_fence=writer_fence+1 WHERE singleton=1");
            }
            try self.db.exec("UPDATE durable_schema SET version=1 WHERE singleton=1");
        }
        self.model = try memory.Memory.init(gpa);
        errdefer self.model.deinit();
        const loaded = try self.loadState();
        self.model.state.destroy(gpa);
        self.model.state = loaded;
        self.next_id = loaded.nextId;
        try self.db.commit();
        active = false;
        return self;
    }
    pub fn deinit(self: *Sqlite) void {
        _ = sqlite3_exec(@ptrCast(self.db.handle), "PRAGMA wal_checkpoint(TRUNCATE)", null, null, null);
        self.model.deinit();
        self.db.close();
        self.gpa.destroy(self);
    }
    fn loadState(self: *Sqlite) !*memory.State {
        const state = try memory.State.create(self.gpa);
        errdefer state.destroy(self.gpa);
        const a = state.arena.allocator();
        var metadata = try self.db.prepare("SELECT next_id,next_seq FROM durable_metadata WHERE singleton=1");
        defer metadata.deinit();
        if (try metadata.step() != .row) return error.InvalidSourceSqliteMetadata;
        state.nextId = try std.fmt.parseInt(u64, (try metadata.columnText(0)).?, 10);
        const seq = try metadata.columnInt(1);
        if (state.nextId < 2 or state.nextId > memory.max_integer + 1 or seq < 1 or seq > memory.max_integer) return error.InvalidSourceSqliteMetadata;
        state.nextId = @max(state.nextId, self.next_id);
        state.nextSeq = @intCast(seq);
        inline for ([_]memory.Table{ .conversation, .entry, .task, .submission, .document }) |table| {
            const sql = switch (table) {
                .conversation => "SELECT id,record,0 FROM conversations ORDER BY id",
                .entry => "SELECT id,record,commit_seq FROM entries ORDER BY id",
                .task => "SELECT id,record,0 FROM tasks ORDER BY id",
                .submission => "SELECT id,record,0 FROM submissions ORDER BY id",
                .document => "SELECT id,record,created_at FROM documents ORDER BY id",
            };
            var rows = try self.db.prepare(sql);
            defer rows.deinit();
            while (try rows.step() == .row) {
                const id: u64 = @intCast(try rows.columnInt(0));
                const record = try json.parseLeaky(a, (try rows.columnText(1)).?);
                if (try memory.idOf(record) != id) return error.InvalidSourceSqliteRecord;
                try state.rows.put(id, .{ .table = table, .record = record, .commitSeq = @intCast(try rows.columnInt(2)) });
                if (table == .document) try state.documents.put(id, .{ .record = record, .revisions = .init(a) });
            }
        }
        var revisions = try self.db.prepare("SELECT document_id,seq,kind,version,content FROM document_revisions ORDER BY document_id,seq");
        defer revisions.deinit();
        while (try revisions.step() == .row) {
            const id: u64 = @intCast(try revisions.columnInt(0));
            const doc = state.documents.getPtr(id) orelse return error.InvalidSourceSqliteRevision;
            const kind = (try revisions.columnText(2)).?;
            const base = std.mem.eql(u8, kind, "base");
            if (!base and !std.mem.eql(u8, kind, "delta")) return error.InvalidSourceSqliteRevision;
            var content: json.Value = .{ .object = .empty };
            try content.object.put(a, "kind", .{ .string = try a.dupe(u8, kind) });
            try content.object.put(a, "version", .{ .integer = try revisions.columnInt(3) });
            try content.object.put(a, if (base) "value" else "ops", try json.parseLeaky(a, (try revisions.columnText(4)).?));
            try doc.revisions.append(.{ .seq = @intCast(try revisions.columnInt(1)), .content = content });
        }
        var ids = try self.db.prepare("SELECT id,record_type FROM record_ids ORDER BY id");
        defer ids.deinit();
        var count: usize = 0;
        while (try ids.step() == .row) {
            const row = state.rows.get(@intCast(try ids.columnInt(0))) orelse return error.InvalidSourceGlobalId;
            if (!std.mem.eql(u8, @tagName(row.table), (try ids.columnText(1)).?)) return error.InvalidSourceGlobalId;
            count += 1;
        }
        if (count != state.rows.count()) return error.InvalidSourceGlobalId;
        return state;
    }
    fn loadPrivateState(self: *Sqlite) !*memory.State {
        const state = try memory.State.create(self.gpa);
        errdefer state.destroy(self.gpa);
        const a = state.arena.allocator();
        var metadata = try self.db.prepare("SELECT schema_version,next_id,next_seq FROM pi_durable_metadata WHERE singleton=1");
        defer metadata.deinit();
        if (try metadata.step() != .row or try metadata.columnInt(0) != 1) return error.UnsupportedPrivateDurableSchema;
        const next_id = try metadata.columnInt(1);
        const next_seq = try metadata.columnInt(2);
        if (next_id < 2 or next_id > memory.max_integer + 1 or next_seq < 1 or next_seq > memory.max_integer) return error.InvalidPrivateDurableMetadata;
        state.nextId = @intCast(next_id);
        state.nextSeq = @intCast(next_seq);
        var rows = try self.db.prepare("SELECT id,record_type,commit_seq,record FROM pi_durable_records ORDER BY id");
        defer rows.deinit();
        while (try rows.step() == .row) {
            const id: u64 = @intCast(try rows.columnInt(0));
            const table = std.meta.stringToEnum(memory.Table, (try rows.columnText(1)).?) orelse return error.InvalidPrivateDurableRecord;
            const record = try json.parseLeaky(a, (try rows.columnText(3)).?);
            if (try memory.idOf(record) != id) return error.InvalidPrivateDurableRecord;
            try state.rows.put(id, .{ .table = table, .record = record, .commitSeq = @intCast(try rows.columnInt(2)) });
        }
        var docs = try self.db.prepare("SELECT id,record FROM pi_durable_documents ORDER BY id");
        defer docs.deinit();
        while (try docs.step() == .row) {
            const id: u64 = @intCast(try docs.columnInt(0));
            const record = try json.parseLeaky(a, (try docs.columnText(1)).?);
            const row = state.rows.get(id) orelse return error.InvalidPrivateDurableDocument;
            if (row.table != .document or !json.equal(row.record, record)) return error.InvalidPrivateDurableDocument;
            try state.documents.put(id, .{ .record = record, .revisions = .init(a) });
        }
        var revisions = try self.db.prepare("SELECT document_id,seq,content FROM pi_durable_revisions ORDER BY document_id,seq");
        defer revisions.deinit();
        while (try revisions.step() == .row) {
            const doc = state.documents.getPtr(@intCast(try revisions.columnInt(0))) orelse return error.InvalidPrivateDurableRevision;
            try doc.revisions.append(.{ .seq = @intCast(try revisions.columnInt(1)), .content = try json.parseLeaky(a, (try revisions.columnText(2)).?) });
        }
        return state;
    }
    fn refresh(self: *Sqlite) !void {
        const value = try self.loadState();
        const old = self.model.state;
        self.model.state = value;
        self.model.generation += 1;
        old.destroy(self.gpa);
    }
    fn optionalNumber(record: json.Value, key: []const u8) !ffi.Value {
        const value = json.get(record, key) orelse return .null;
        return .{ .integer = @intCast(try json.asInteger(value)) };
    }
    fn persist(self: *Sqlite, state: *const memory.State) !void {
        try self.db.exec("DELETE FROM document_revisions; DELETE FROM documents; DELETE FROM conversations; DELETE FROM entries; DELETE FROM tasks; DELETE FROM submissions; DELETE FROM record_ids");
        var rows = state.rows.iterator();
        while (rows.next()) |item| {
            const id: ffi.Value = .{ .integer = @intCast(item.key_ptr.*) };
            const row = item.value_ptr.*;
            const record = row.record;
            const encoded = try json.stringify(self.gpa, record);
            defer self.gpa.free(encoded);
            try run(&self.db, "INSERT INTO record_ids(id,record_type) VALUES(?,?)", &.{ id, .{ .text = @tagName(row.table) } });
            switch (row.table) {
                .conversation => {
                    const owner = json.get(record, "owner");
                    try run(&self.db, "INSERT INTO conversations(id,owner_conversation_id,owner_task_id,record) VALUES(?,?,?,?)", &.{ id, if (owner) |value| try optionalNumber(value, "conversationId") else .null, if (owner) |value| try optionalNumber(value, "taskId") else .null, .{ .text = encoded } });
                },
                .entry => try run(&self.db, "INSERT INTO entries(id,conversation_id,head,commit_seq,record) VALUES(?,?,?,?,?)", &.{ id, try optionalNumber(record, "conversationId"), try optionalNumber(record, "head"), .{ .integer = @intCast(row.commitSeq) }, .{ .text = encoded } }),
                .task => {
                    const kind = try json.stringify(self.gpa, try json.required(record, "kind"));
                    defer self.gpa.free(kind);
                    const task_state = try json.required(record, "state");
                    try run(&self.db, "INSERT INTO tasks(id,conversation_id,kind,status,abort_requested,background,record) VALUES(?,?,?,?,?,?,?)", &.{ id, try optionalNumber(record, "conversationId"), .{ .text = kind }, .{ .text = try json.asString(try json.required(task_state, "status")) }, .{ .integer = @intFromBool((try json.required(record, "abortRequested")).bool) }, .{ .integer = @intFromBool((try json.required(record, "background")).bool) }, .{ .text = encoded } });
                },
                .submission => {
                    const request = if (json.get(record, "requestId")) |value| try json.stringify(self.gpa, value) else null;
                    defer if (request) |value| self.gpa.free(value);
                    try run(&self.db, "INSERT INTO submissions(id,conversation_id,request_id,status,record) VALUES(?,?,?,?,?)", &.{ id, try optionalNumber(record, "conversationId"), if (request) |value| .{ .text = value } else .null, .{ .text = try json.asString(try json.required(record, "status")) }, .{ .text = encoded } });
                },
                .document => {
                    const scope = try json.required(record, "scope");
                    const scope_kind = try json.asString(try json.required(scope, "kind"));
                    const kind = try json.stringify(self.gpa, try json.required(record, "kind"));
                    defer self.gpa.free(kind);
                    const key = if (json.get(record, "key")) |value| try json.stringify(self.gpa, value) else null;
                    defer if (key) |value| self.gpa.free(value);
                    const owner: ffi.Value = if (std.mem.eql(u8, scope_kind, "session")) .{ .integer = 0 } else try optionalNumber(scope, if (std.mem.eql(u8, scope_kind, "conversation")) "conversationId" else "taskId");
                    try run(&self.db, "INSERT INTO documents(id,kind,family,key_value,scope_kind,owner_id,created_at,retired_at,record) VALUES(?,?,?,?,?,?,?,?,?)", &.{ id, .{ .text = kind }, .{ .integer = @intFromBool(key != null) }, .{ .text = key orelse "" }, .{ .text = scope_kind }, owner, try optionalNumber(record, "createdAt"), try optionalNumber(record, "retiredAt"), .{ .text = encoded } });
                },
            }
        }
        var docs = state.documents.iterator();
        while (docs.next()) |item| for (item.value_ptr.revisions.items) |revision| {
            const kind = try json.asString(try json.required(revision.content, "kind"));
            const value = try json.stringify(self.gpa, try json.required(revision.content, if (std.mem.eql(u8, kind, "base")) "value" else "ops"));
            defer self.gpa.free(value);
            try run(&self.db, "INSERT INTO document_revisions(document_id,seq,kind,version,content) VALUES(?,?,?,?,?)", &.{ .{ .integer = @intCast(item.key_ptr.*) }, .{ .integer = @intCast(revision.seq) }, .{ .text = kind }, .{ .integer = @intCast(try json.asInteger(try json.required(revision.content, "version"))) }, .{ .text = value } });
        };
        const next_id = try std.fmt.allocPrint(self.gpa, "{d}", .{state.nextId});
        defer self.gpa.free(next_id);
        try run(&self.db, "UPDATE durable_metadata SET next_id=?,next_seq=? WHERE singleton=1", &.{ .{ .text = next_id }, .{ .integer = @intCast(state.nextSeq) } });
    }
    pub fn commitAt(self: *Sqlite, writes: json.Value, sequence: ?u64) !u64 {
        try self.mutex.lock(self.io);
        defer self.mutex.unlock(self.io);
        try self.model.assertOpen();
        try self.db.beginImmediate();
        var active = true;
        defer if (active) rollback(&self.db);
        try self.refresh();
        var prepared = try self.model.prepare(writes, sequence);
        defer prepared.deinit();
        try self.persist(prepared.state.?);
        try self.db.commit();
        active = false;
        const result = try prepared.apply();
        self.next_id = @max(self.next_id, self.model.state.nextId);
        return result;
    }
    pub fn mintId(self: *Sqlite) !u64 {
        try self.mutex.lock(self.io);
        defer self.mutex.unlock(self.io);
        try self.model.assertOpen();
        if (self.next_id > memory.max_integer) return error.IdSpaceExhausted;
        const id = self.next_id;
        self.next_id += 1;
        return id;
    }
    fn readStart(self: *Sqlite) !void {
        try self.model.assertOpen();
        try self.db.begin();
        self.refresh() catch |err| {
            rollback(&self.db);
            return err;
        };
    }
    pub fn snapshot(self: *Sqlite, gpa: std.mem.Allocator) !*memory.State {
        try self.mutex.lock(self.io);
        defer self.mutex.unlock(self.io);
        try self.readStart();
        defer rollback(&self.db);
        return self.model.state.duplicate(gpa);
    }
    pub fn readRecord(self: *Sqlite, gpa: std.mem.Allocator, id: u64) !?json.Owned {
        try self.mutex.lock(self.io);
        defer self.mutex.unlock(self.io);
        try self.readStart();
        defer rollback(&self.db);
        return self.model.readRecord(gpa, id);
    }
    pub fn readTableRecord(self: *Sqlite, gpa: std.mem.Allocator, table: memory.Table, id: u64) !?json.Owned {
        try self.mutex.lock(self.io);
        defer self.mutex.unlock(self.io);
        try self.readStart();
        defer rollback(&self.db);
        const row = self.model.state.rows.get(id) orelse return null;
        if (row.table != table) return null;
        return self.model.readRecord(gpa, id);
    }
    pub fn readEntry(self: *Sqlite, gpa: std.mem.Allocator, id: u64, conversation: ?u64) !?json.Owned {
        try self.mutex.lock(self.io);
        defer self.mutex.unlock(self.io);
        try self.readStart();
        defer rollback(&self.db);
        return query.entry(gpa, &self.model, id, conversation);
    }
    pub fn readDocument(self: *Sqlite, gpa: std.mem.Allocator, id: u64, point: memory.Point) !?json.Owned {
        try self.mutex.lock(self.io);
        defer self.mutex.unlock(self.io);
        try self.readStart();
        defer rollback(&self.db);
        return self.model.readDocument(gpa, id, point);
    }
    pub fn scan(self: *Sqlite, gpa: std.mem.Allocator, parameters: query.Query) !json.Owned {
        try self.mutex.lock(self.io);
        defer self.mutex.unlock(self.io);
        try self.readStart();
        defer rollback(&self.db);
        return query.scan(gpa, &self.model, parameters);
    }
};

test "native durable VM original SQLite file preserves source records history indexed UTF16 and commit-only allocation" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.writeFile(io, .{ .sub_path = "source.sqlite", .data = @embedFile("../fixtures/original-sqlite-source-v1.sqlite") });
    var buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const count = try tmp.dir.realPath(io, &buffer);
    const path = try std.fs.path.join(gpa, &.{ buffer[0..count], "source.sqlite" });
    defer gpa.free(path);
    var store = try Sqlite.open(gpa, io, path, .{});
    var document = (try store.readDocument(gpa, 5, .current)).?;
    defer document.deinit();
    try std.testing.expectEqual(@as(u64, 1), try json.asInteger(try json.required(document.value, "deltasSinceBase")));
    try std.testing.expectEqualStrings("A😀BΩ", try json.asString(try json.required(try json.required(document.value, "value"), "s")));
    var historical = (try store.readDocument(gpa, 5, .{ .seq = 1 })).?;
    defer historical.deinit();
    try std.testing.expectEqual(@as(u64, 1), try json.asInteger(try json.required(try json.required(historical.value, "value"), "n")));
    var task = (try store.readTableRecord(gpa, .task, 3)).?;
    defer task.deinit();
    var expected_task = try json.Owned.parse(gpa, "{\"id\":3,\"kind\":\"fixture.Ω\\ud800\",\"version\":1,\"conversationId\":1,\"input\":{\"n\":1},\"background\":false,\"abortRequested\":false,\"state\":{\"status\":\"pending\",\"checkpoint\":{\"phase\":\"go\"}}}");
    defer expected_task.deinit();
    try std.testing.expect(json.equal(expected_task.value, task.value));
    try std.testing.expectEqual(@as(u64, 6), try store.mintId());
    store.deinit();
    store = try Sqlite.open(gpa, io, path, .{});
    try std.testing.expectEqual(@as(u64, 6), try store.mintId());
    var empty = try json.Owned.parse(gpa, "[]");
    defer empty.deinit();
    try std.testing.expectEqual(@as(u64, 3), try store.commitAt(empty.value, null));
    store.deinit();
    store = try Sqlite.open(gpa, io, path, .{});
    defer store.deinit();
    try std.testing.expectEqual(@as(u64, 7), try store.mintId());
    var metadata = try store.db.prepare("SELECT typeof(next_id),next_id,next_seq FROM durable_metadata WHERE singleton=1");
    defer metadata.deinit();
    try std.testing.expect(try metadata.step() == .row);
    try std.testing.expectEqualStrings("text", (try metadata.columnText(0)).?);
    try std.testing.expectEqualStrings("7", (try metadata.columnText(1)).?);
    try std.testing.expectEqual(@as(i64, 4), try metadata.columnInt(2));
    var kind = try store.db.prepare("SELECT kind FROM tasks WHERE id=3");
    defer kind.deinit();
    try std.testing.expect(try kind.step() == .row);
    try std.testing.expectEqualStrings("\"fixture.Ω\\ud800\"", (try kind.columnText(0)).?);
}

fn allocationExercise(gpa: std.mem.Allocator) !void {
    const store = try Sqlite.open(gpa, std.testing.io, ":memory:", .{});
    defer store.deinit();
    var writes = try json.Owned.parse(gpa, "[{\"type\":\"conversation\",\"value\":{\"id\":1}},{\"type\":\"document.create\",\"record\":{\"id\":3,\"kind\":\"gpa\",\"scope\":{\"kind\":\"conversation\",\"conversationId\":1},\"history\":\"rewindable\",\"fork\":\"asOf\"},\"content\":{\"kind\":\"base\",\"version\":1,\"value\":{\"n\":1}}}]");
    defer writes.deinit();
    _ = try store.commitAt(writes.value, null);
    var next = try json.Owned.parse(gpa, "[{\"type\":\"document.change\",\"id\":3,\"content\":{\"kind\":\"delta\",\"version\":1,\"ops\":[[\"s\",[\"n\"],2]]}}]");
    defer next.deinit();
    _ = try store.commitAt(next.value, null);
    var snapshot = try store.snapshot(gpa);
    defer snapshot.destroy(gpa);
    var document = (try store.readDocument(gpa, 3, .current)).?;
    defer document.deinit();
}
test "native durable VM source SQLite schema loading indexed persistence and reads unwind every GPA failure" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, allocationExercise, .{});
}

test "native durable VM source SQLite failed publication rolls back SQL effects and permits healthy retry" {
    const io = std.testing.io;
    const gpa = std.testing.allocator;
    var first = try json.Owned.parse(gpa, "[{\"type\":\"conversation\",\"value\":{\"id\":1}}]");
    defer first.deinit();
    var second = try json.Owned.parse(gpa, "[{\"type\":\"entry\",\"value\":{\"id\":2,\"kind\":\"native\",\"conversationId\":1,\"head\":2}}]");
    defer second.deinit();
    var reached_success = false;
    var failed: usize = 0;
    for (0..300) |offset| {
        var failing = std.testing.FailingAllocator.init(gpa, .{});
        const store = try Sqlite.open(failing.allocator(), io, ":memory:", .{});
        defer store.deinit();
        _ = try store.commitAt(first.value, null);
        failing.fail_index = failing.alloc_index + offset;
        const result = store.commitAt(second.value, null);
        failing.fail_index = std.math.maxInt(usize);
        if (result) |seq| {
            try std.testing.expectEqual(@as(u64, 2), seq);
            reached_success = true;
            break;
        } else |err| {
            try std.testing.expectEqual(error.OutOfMemory, err);
            failed += 1;
            var statement = try store.db.prepare("SELECT (SELECT count(*) FROM entries),(SELECT next_seq FROM durable_metadata WHERE singleton=1),(SELECT count(*) FROM conversations)");
            defer statement.deinit();
            try std.testing.expect(try statement.step() == .row);
            try std.testing.expectEqual(@as(i64, 0), try statement.columnInt(0));
            try std.testing.expectEqual(@as(i64, 2), try statement.columnInt(1));
            try std.testing.expectEqual(@as(i64, 1), try statement.columnInt(2));
            try std.testing.expect(try statement.step() == .done);
            try std.testing.expectEqual(@as(u64, 2), try store.commitAt(second.value, null));
        }
    }
    try std.testing.expect(reached_success and failed > 0);
}

test "native durable VM source SQLite imports private data atomically retains original tables and fences prior writer" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const count = try tmp.dir.realPath(io, &buffer);
    const path = try std.fs.path.join(gpa, &.{ buffer[0..count], "private.sqlite" });
    defer gpa.free(path);
    const private = try @import("sqlite.zig").Sqlite.open(gpa, io, path, .{});
    defer private.deinit();
    var writes = try json.Owned.parse(gpa, "[{\"type\":\"conversation\",\"value\":{\"id\":1}},{\"type\":\"document.create\",\"record\":{\"id\":3,\"kind\":\"migration\",\"scope\":{\"kind\":\"conversation\",\"conversationId\":1},\"history\":\"rewindable\",\"fork\":\"asOf\"},\"content\":{\"kind\":\"base\",\"version\":1,\"value\":{\"n\":1}}}]");
    defer writes.deinit();
    _ = try private.commitAt(writes.value, null);
    const public = try Sqlite.open(gpa, io, path, .{});
    defer public.deinit();
    var document = (try public.readDocument(gpa, 3, .current)).?;
    defer document.deinit();
    try std.testing.expectEqual(@as(u64, 1), try json.asInteger(try json.required(try json.required(document.value, "value"), "n")));
    var empty = try json.Owned.parse(gpa, "[]");
    defer empty.deinit();
    try std.testing.expectError(error.LostWriterFence, private.commitAt(empty.value, null));
    var statement = try public.db.prepare("SELECT (SELECT count(*) FROM pi_durable_records),(SELECT count(*) FROM record_ids),(SELECT next_id FROM durable_metadata),(SELECT next_seq FROM durable_metadata)");
    defer statement.deinit();
    try std.testing.expect(try statement.step() == .row);
    try std.testing.expectEqual(@as(i64, 2), try statement.columnInt(0));
    try std.testing.expectEqual(@as(i64, 2), try statement.columnInt(1));
    try std.testing.expectEqualStrings("4", (try statement.columnText(2)).?);
    try std.testing.expectEqual(@as(i64, 2), try statement.columnInt(3));
}

test "native durable VM source SQLite migration allocation failures preserve private writer and data until admission" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    var writes = try json.Owned.parse(gpa, "[{\"type\":\"conversation\",\"value\":{\"id\":1}}]");
    defer writes.deinit();
    var empty = try json.Owned.parse(gpa, "[]");
    defer empty.deinit();
    var reached_success = false;
    var failures: usize = 0;
    for (0..300) |offset| {
        var tmp = std.testing.tmpDir(.{});
        defer tmp.cleanup();
        var buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
        const count = try tmp.dir.realPath(io, &buffer);
        const path = try std.fs.path.join(gpa, &.{ buffer[0..count], "migration.sqlite" });
        defer gpa.free(path);
        const private = try @import("sqlite.zig").Sqlite.open(gpa, io, path, .{});
        defer private.deinit();
        _ = try private.commitAt(writes.value, null);
        var failing = std.testing.FailingAllocator.init(gpa, .{ .fail_index = offset });
        const result = Sqlite.open(failing.allocator(), io, path, .{});
        failing.fail_index = std.math.maxInt(usize);
        if (result) |public| {
            defer public.deinit();
            try std.testing.expectError(error.LostWriterFence, private.commitAt(empty.value, null));
            reached_success = true;
            break;
        } else |err| {
            try std.testing.expectEqual(error.OutOfMemory, err);
            failures += 1;
            var metadata = try private.db.prepare("SELECT (SELECT writer_fence FROM pi_durable_metadata),(SELECT count(*) FROM pi_durable_records),(SELECT count(*) FROM sqlite_master WHERE name='durable_metadata')");
            defer metadata.deinit();
            try std.testing.expect(try metadata.step() == .row);
            try std.testing.expectEqual(private.fence.?, try metadata.columnInt(0));
            try std.testing.expectEqual(@as(i64, 1), try metadata.columnInt(1));
            try std.testing.expectEqual(@as(i64, 0), try metadata.columnInt(2));
            try std.testing.expect(try metadata.step() == .done);
            try std.testing.expectEqual(@as(u64, 2), try private.commitAt(empty.value, null));
        }
    }
    try std.testing.expect(reached_success and failures > 0);
}

test "native durable VM source SQLite reopens original append to a native file without rewriting history" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.writeFile(io, .{ .sub_path = "roundtrip.sqlite", .data = @embedFile("../fixtures/sqlite-source-native-roundtrip.sqlite") });
    var buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const length = try tmp.dir.realPath(io, &buffer);
    const path = try std.fs.path.join(gpa, &.{ buffer[0..length], "roundtrip.sqlite" });
    defer gpa.free(path);
    const store = try Sqlite.open(gpa, io, path, .{});
    defer store.deinit();
    var doc = (try store.readDocument(gpa, 5, .current)).?;
    defer doc.deinit();
    try std.testing.expectEqual(@as(u64, 11), try json.asInteger(try json.required(try json.required(doc.value, "value"), "n")));
    try std.testing.expectEqual(@as(u64, 2), try json.asInteger(try json.required(doc.value, "deltasSinceBase")));
    var old = (try store.readDocument(gpa, 5, .{ .seq = 2 })).?;
    defer old.deinit();
    try std.testing.expectEqual(@as(u64, 2), try json.asInteger(try json.required(try json.required(old.value, "value"), "n")));
    var entry = (try store.readEntry(gpa, 6, 1)).?;
    defer entry.deinit();
    try std.testing.expectEqualStrings("original-after-native", try json.asString(try json.required(try json.required(entry.value, "entry"), "kind")));
    try std.testing.expectEqual(@as(u64, 3), try json.asInteger(try json.required(entry.value, "commitSeq")));
    try std.testing.expectEqual(@as(u64, 7), try store.mintId());
}
