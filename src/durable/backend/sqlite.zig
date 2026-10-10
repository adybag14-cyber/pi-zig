//! Dedicated numeric durable schema over the existing stable SQLite C ABI.
const std = @import("std");
const ffi = @import("../../storage/sqlite/ffi.zig");
const memory = @import("memory.zig");
const query = @import("query.zig");
const json = memory.json;
extern fn sqlite3_exec(db: ?*anyopaque, sql: [*:0]const u8, callback: ?*const anyopaque, context: ?*anyopaque, message: ?*?[*:0]u8) c_int;
fn rollback(db: *ffi.Database) void {
    _ = sqlite3_exec(@ptrCast(db.handle), "ROLLBACK", null, null, null);
}
fn run(db: *ffi.Database, sql: []const u8, values: []const ffi.Value) !i64 {
    var statement = try db.prepare(sql);
    defer statement.deinit();
    try statement.bindAll(values);
    return statement.run();
}
const schema =
    \\CREATE TABLE IF NOT EXISTS pi_durable_metadata(singleton INTEGER PRIMARY KEY CHECK(singleton=1),schema_version INTEGER NOT NULL,next_id INTEGER NOT NULL,next_seq INTEGER NOT NULL,writer_fence INTEGER NOT NULL) STRICT;
    \\INSERT  or  IGNORE INTO pi_durable_metadata VALUES(1,1,2,1,0);
    \\CREATE TABLE IF NOT EXISTS pi_durable_records(id INTEGER PRIMARY KEY,record_type TEXT NOT NULL CHECK(record_type IN ('conversation','entry','task','submission','document')),commit_seq INTEGER NOT NULL,record TEXT NOT NULL CHECK(json_valid(record))) STRICT;
    \\CREATE TABLE IF NOT EXISTS pi_durable_documents(id INTEGER PRIMARY KEY,record TEXT NOT NULL CHECK(json_valid(record))) STRICT;
    \\CREATE TABLE IF NOT EXISTS pi_durable_revisions(document_id INTEGER NOT NULL,seq INTEGER NOT NULL,content TEXT NOT NULL CHECK(json_valid(content)),PRIMARY KEY(document_id,seq)) STRICT;
;
pub const Options = struct { claim_writer: bool = true };
pub const Sqlite = struct {
    gpa: std.mem.Allocator,
    io: std.Io,
    db: ffi.Database,
    model: memory.Memory,
    fence: ?i64,
    mutex: std.Io.Mutex = .init,
    pub fn open(gpa: std.mem.Allocator, io: std.Io, path: []const u8, options: Options) !*Sqlite {
        const self = try gpa.create(Sqlite);
        errdefer gpa.destroy(self);
        self.* = .{ .gpa = gpa, .io = io, .db = try ffi.Database.open(gpa, path), .model = undefined, .fence = null };
        errdefer self.db.close();
        try self.db.busyTimeout(5000);
        // Never migrate  or  reinterpret the existing CLI session repository.
        var legacy = try self.db.prepare("SELECT count(*) FROM sqlite_master WHERE type='table'  and  name IN ('sessions','entries')");
        defer legacy.deinit();
        if (try legacy.step() != .row) return error.InvalidStorageSchema;
        if (try legacy.columnInt(0) != 0) return error.LegacyDatabaseFormat;
        try self.db.beginImmediate();
        var transaction = true;
        defer if (transaction) rollback(&self.db);
        try self.db.exec(schema);
        var metadata = try self.db.prepare("SELECT schema_version FROM pi_durable_metadata WHERE singleton=1");
        defer metadata.deinit();
        if (try metadata.step() != .row or try metadata.columnInt(0) != 1) return error.UnsupportedDurableSchema;
        if (options.claim_writer) {
            var claim = try self.db.prepare("UPDATE pi_durable_metadata SET writer_fence=writer_fence+1 WHERE singleton=1 RETURNING writer_fence");
            defer claim.deinit();
            if (try claim.step() != .row) return error.InvalidStorageSchema;
            self.fence = try claim.columnInt(0);
            if (try claim.step() != .done) return error.UnexpectedStep;
        }
        self.model = try memory.Memory.init(gpa);
        errdefer self.model.deinit();
        const loaded = try self.loadState();
        self.model.state.destroy(gpa);
        self.model.state = loaded;
        try self.db.commit();
        transaction = false;
        return self;
    }
    pub fn deinit(self: *Sqlite) void {
        self.model.deinit();
        self.db.close();
        const gpa = self.gpa;
        gpa.destroy(self);
    }
    fn loadState(self: *Sqlite) !*memory.State {
        const state = try memory.State.create(self.gpa);
        errdefer state.destroy(self.gpa);
        const allocator = state.arena.allocator();
        var metadata = try self.db.prepare("SELECT next_id,next_seq FROM pi_durable_metadata WHERE singleton=1");
        defer metadata.deinit();
        if (try metadata.step() != .row) return error.InvalidStorageSchema;
        const id = try metadata.columnInt(0);
        const seq = try metadata.columnInt(1);
        if (id < 2 or seq < 1) return error.InvalidStorageSchema;
        state.nextId = @intCast(id);
        state.nextSeq = @intCast(seq);
        var rows = try self.db.prepare("SELECT id,record_type,commit_seq,record FROM pi_durable_records ORDER BY id");
        defer rows.deinit();
        while (try rows.step() == .row) {
            const row_id: u64 = @intCast(try rows.columnInt(0));
            const tag = (try rows.columnText(1)).?;
            const record_type = std.meta.stringToEnum(memory.Table, tag) orelse return error.InvalidStorageSchema;
            const commit_seq: u64 = @intCast(try rows.columnInt(2));
            const record = try json.parseLeaky(allocator, (try rows.columnText(3)).?);
            if (try memory.idOf(record) != row_id) return error.InvalidStorageSchema;
            try state.rows.put(row_id, .{ .table = record_type, .commitSeq = commit_seq, .record = record });
        }
        var documents = try self.db.prepare("SELECT id,record FROM pi_durable_documents ORDER BY id");
        defer documents.deinit();
        while (try documents.step() == .row) {
            const doc_id: u64 = @intCast(try documents.columnInt(0));
            const record = try json.parseLeaky(allocator, (try documents.columnText(1)).?);
            const row = state.rows.get(doc_id) orelse return error.InvalidStorageSchema;
            if (row.table != .document or !json.equal(record, row.record)) return error.InvalidStorageSchema;
            try state.documents.put(doc_id, .{ .record = record, .revisions = .init(allocator) });
        }
        var revisions = try self.db.prepare("SELECT document_id,seq,content FROM pi_durable_revisions ORDER BY document_id,seq");
        defer revisions.deinit();
        while (try revisions.step() == .row) {
            const doc_id: u64 = @intCast(try revisions.columnInt(0));
            const doc = state.documents.getPtr(doc_id) orelse return error.InvalidStorageSchema;
            try doc.revisions.append(.{ .seq = @intCast(try revisions.columnInt(1)), .content = try json.parseLeaky(allocator, (try revisions.columnText(2)).?) });
        }
        return state;
    }
    fn refreshLocked(self: *Sqlite) !void {
        const state = try self.loadState();
        const old = self.model.state;
        self.model.state = state;
        self.model.generation += 1;
        old.destroy(self.gpa);
    }
    fn checkFence(self: *Sqlite) !void {
        const fence = self.fence orelse return error.ReadOnlyStorage;
        var statement = try self.db.prepare("SELECT writer_fence FROM pi_durable_metadata WHERE singleton=1");
        defer statement.deinit();
        if (try statement.step() != .row) return error.InvalidStorageSchema;
        if (try statement.columnInt(0) != fence) return error.LostWriterFence;
    }
    fn persist(self: *Sqlite, state: *const memory.State) !void {
        _ = try run(&self.db, "DELETE FROM pi_durable_revisions", &.{});
        _ = try run(&self.db, "DELETE FROM pi_durable_documents", &.{});
        _ = try run(&self.db, "DELETE FROM pi_durable_records", &.{});
        var statement = try self.db.prepare("INSERT INTO pi_durable_records(id,record_type,commit_seq,record) VALUES(?,?,?,?)");
        defer statement.deinit();
        var rows = state.rows.iterator();
        while (rows.next()) |item| {
            const encoded = try json.stringify(self.gpa, item.value_ptr.record);
            defer self.gpa.free(encoded);
            try statement.bindAll(&.{ .{ .integer = @intCast(item.key_ptr.*) }, .{ .text = @tagName(item.value_ptr.table) }, .{ .integer = @intCast(item.value_ptr.commitSeq) }, .{ .text = encoded } });
            _ = try statement.run();
            try statement.reset();
        }
        var docs = try self.db.prepare("INSERT INTO pi_durable_documents(id,record) VALUES(?,?)");
        defer docs.deinit();
        var revisions = try self.db.prepare("INSERT INTO pi_durable_revisions(document_id,seq,content) VALUES(?,?,?)");
        defer revisions.deinit();
        var documents = state.documents.iterator();
        while (documents.next()) |item| {
            const encoded = try json.stringify(self.gpa, item.value_ptr.record);
            defer self.gpa.free(encoded);
            try docs.bindAll(&.{ .{ .integer = @intCast(item.key_ptr.*) }, .{ .text = encoded } });
            _ = try docs.run();
            try docs.reset();
            for (item.value_ptr.revisions.items) |revision| {
                const content = try json.stringify(self.gpa, revision.content);
                defer self.gpa.free(content);
                try revisions.bindAll(&.{ .{ .integer = @intCast(item.key_ptr.*) }, .{ .integer = @intCast(revision.seq) }, .{ .text = content } });
                _ = try revisions.run();
                try revisions.reset();
            }
        }
        _ = try run(&self.db, "UPDATE pi_durable_metadata SET next_id=?,next_seq=? WHERE singleton=1", &.{ .{ .integer = @intCast(state.nextId) }, .{ .integer = @intCast(state.nextSeq) } });
    }
    pub fn commit(self: *Sqlite, writes: json.Value) !u64 {
        return self.commitAt(writes, null);
    }
    pub fn commitAt(self: *Sqlite, writes: json.Value, sequence: ?u64) !u64 {
        try self.mutex.lock(self.io);
        defer self.mutex.unlock(self.io);
        try self.model.assertOpen();
        try self.db.beginImmediate();
        var transaction = true;
        defer if (transaction) rollback(&self.db);
        try self.checkFence();
        try self.refreshLocked();
        var prepared = try self.model.prepare(writes, sequence);
        defer prepared.deinit();
        try self.persist(prepared.state.?);
        try self.db.commit();
        transaction = false;
        // Every fallible allocation  and  database effect finished before publish.
        return prepared.apply();
    }
    pub fn mintId(self: *Sqlite) !u64 {
        try self.mutex.lock(self.io);
        defer self.mutex.unlock(self.io);
        try self.model.assertOpen();
        try self.db.beginImmediate();
        var transaction = true;
        defer if (transaction) rollback(&self.db);
        try self.checkFence();
        try self.refreshLocked();
        const id = self.model.state.nextId;
        if (id > memory.max_integer) return error.IdSpaceExhausted;
        _ = try run(&self.db, "UPDATE pi_durable_metadata SET next_id=? WHERE singleton=1", &.{.{ .integer = @intCast(id + 1) }});
        try self.db.commit();
        transaction = false;
        self.model.state.nextId = id + 1;
        return id;
    }
    pub fn readRecord(self: *Sqlite, gpa: std.mem.Allocator, id: u64) !?json.Owned {
        try self.mutex.lock(self.io);
        defer self.mutex.unlock(self.io);
        try self.model.assertOpen();
        try self.refreshLocked();
        return self.model.readRecord(gpa, id);
    }
    pub fn readDocument(self: *Sqlite, gpa: std.mem.Allocator, id: u64, point: memory.Point) !?json.Owned {
        try self.mutex.lock(self.io);
        defer self.mutex.unlock(self.io);
        try self.model.assertOpen();
        try self.refreshLocked();
        return self.model.readDocument(gpa, id, point);
    }
    pub fn scan(self: *Sqlite, gpa: std.mem.Allocator, parameters: query.Query) !json.Owned {
        try self.mutex.lock(self.io);
        defer self.mutex.unlock(self.io);
        try self.model.assertOpen();
        try self.refreshLocked();
        return query.scan(gpa, &self.model, parameters);
    }
    pub fn readEntry(self: *Sqlite, gpa: std.mem.Allocator, id: u64, conversation: ?u64) !?json.Owned {
        try self.mutex.lock(self.io);
        defer self.mutex.unlock(self.io);
        try self.model.assertOpen();
        try self.refreshLocked();
        return query.entry(gpa, &self.model, id, conversation);
    }
    pub fn findDocument(self: *Sqlite, gpa: std.mem.Allocator, address: json.Value, point: memory.Point) !?json.Owned {
        try self.mutex.lock(self.io);
        defer self.mutex.unlock(self.io);
        try self.model.assertOpen();
        try self.refreshLocked();
        return query.findDocument(gpa, &self.model, address, point);
    }
    pub fn snapshot(self: *Sqlite, gpa: std.mem.Allocator) !*memory.State {
        try self.mutex.lock(self.io);
        defer self.mutex.unlock(self.io);
        try self.model.assertOpen();
        try self.refreshLocked();
        return self.model.state.duplicate(gpa);
    }
    pub fn readTableRecord(self: *Sqlite, gpa: std.mem.Allocator, table: memory.Table, id: u64) !?json.Owned {
        try self.mutex.lock(self.io);
        defer self.mutex.unlock(self.io);
        try self.model.assertOpen();
        try self.refreshLocked();
        const row = self.model.state.rows.get(id) orelse return null;
        if (row.table != table) return null;
        return self.model.readRecord(gpa, id);
    }
};

test "durable SQLite rolls back every injected native allocation failure and remains readable" {
    const io = std.testing.io;
    const gpa = std.testing.allocator;
    var scratch = std.testing.tmpDir(.{});
    defer scratch.cleanup();
    var buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const length = try scratch.dir.realPath(io, &buffer);
    const Fixture = struct {
        root: []const u8,
        iteration: u64 = 0,
        fn run(allocator: std.mem.Allocator, self: *@This()) !void {
            const path = try std.fmt.allocPrint(std.testing.allocator, "{s}/failure-{d}.sqlite", .{ self.root, self.iteration });
            defer std.testing.allocator.free(path);
            self.iteration += 1;
            var store = try Sqlite.open(allocator, std.testing.io, path, .{});
            defer store.deinit();
            var writes = try json.Owned.parse(allocator, "[{\"type\":\"conversation\",\"value\":{\"id\":1}},{\"type\":\"entry\",\"value\":{\"id\":2,\"conversationId\":1,\"kind\":\"test\",\"data\":{\"nested\":[1,2]}}}]");
            defer writes.deinit();
            _ = store.commit(writes.value) catch |err| {
                if (err == error.OutOfMemory) {
                    // The allocator's one injected failure has fired. Read the
                    // DB through a fresh handle to detect partial persistence.
                    var reader = try Sqlite.open(std.testing.allocator, std.testing.io, path, .{ .claim_writer = false });
                    defer reader.deinit();
                    try std.testing.expect((try reader.readRecord(std.testing.allocator, 1)) == null);
                    var check = try store.db.prepare("SELECT next_seq FROM pi_durable_metadata WHERE singleton=1");
                    defer check.deinit();
                    try std.testing.expect(try check.step() == .row);
                    try std.testing.expectEqual(@as(i64, 1), try check.columnInt(0));
                }
                return err;
            };
            try std.testing.expectEqual(@as(u64, 3), try store.mintId());
            var row = (try store.readRecord(allocator, 2)).?;
            defer row.deinit();
        }
    };
    var fixture: Fixture = .{ .root = buffer[0..length] };
    try std.testing.checkAllAllocationFailures(gpa, Fixture.run, .{&fixture});
}

test "durable SQLite preserves numeric ids  and  documents across reopen  and  fences a replaced writer" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    var scratch = std.testing.tmpDir(.{});
    defer scratch.cleanup();
    var buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const length = try scratch.dir.realPath(io, &buffer);
    const path = try std.fs.path.join(gpa, &.{ buffer[0..length], "durable.sqlite" });
    defer gpa.free(path);
    var first = try Sqlite.open(gpa, io, path, .{});
    defer first.deinit();
    var writes = try json.Owned.parse(gpa, "[{\"type\":\"conversation\",\"value\":{\"id\":1}},{\"type\":\"document.create\",\"record\":{\"id\":3,\"kind\":\"test\",\"scope\":{\"kind\":\"conversation\",\"conversationId\":1},\"history\":\"rewindable\",\"fork\":\"asOf\",\"key\":\"\\ud800\"},\"content\":{\"kind\":\"base\",\"version\":1,\"value\":{\"text\":\"\\udfff\"}}}]");
    defer writes.deinit();
    try std.testing.expectEqual(@as(u64, 1), try first.commit(writes.value));
    try std.testing.expectEqual(@as(u64, 4), try first.mintId());
    var second = try Sqlite.open(gpa, io, path, .{});
    defer second.deinit();
    try std.testing.expectEqual(@as(u64, 5), try second.mintId());
    var empty = try json.Owned.parse(gpa, "[]");
    defer empty.deinit();
    try std.testing.expectError(error.LostWriterFence, first.commit(empty.value));
    var document = (try second.readDocument(gpa, 3, .current)).?;
    defer document.deinit();
    const encoded = try json.stringify(gpa, document.value);
    defer gpa.free(encoded);
    try std.testing.expect(std.mem.indexOf(u8, encoded, "\\ud800") != null);
    try std.testing.expect(std.mem.indexOf(u8, encoded, "\\udfff") != null);
    var reader = try Sqlite.open(gpa, io, path, .{ .claim_writer = false });
    defer reader.deinit();
    try std.testing.expectError(error.ReadOnlyStorage, reader.mintId());
    try std.testing.expectEqual(@as(u64, 2), try second.commit(empty.value));
}
