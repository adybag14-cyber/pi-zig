//! Canonical native SQLite session repository.
//!
//! This ports the original session-backend package's durable sessions,
//! sequences, lanes, parent-linked entries, branch cache, facts, records,
//! statistics, writer fencing and FTS search.  All writes are serialized and
//! transactional; leases are verified in the same transaction as mutations.
const std = @import("std");
const Io = std.Io;
const ffi = @import("ffi.zig");
const schema = @import("schema.zig");
const types = @import("types.zig");

pub const RepositoryError = error{
    SessionNotFound,
    SessionAlreadyExists,
    EntryNotFound,
    EntryAlreadyExists,
    InvalidEntry,
    InvalidPayload,
    InvalidMetadata,
    InvalidName,
    MissingSequence,
    InvalidLane,
    LaneAlreadyExists,
    OpenOperation,
    LostWriterLease,
    ActiveWriter,
    InvalidForkTarget,
    SearchUnavailable,
};

fn lockMutex(mutex: *std.atomic.Mutex) void {
    while (!mutex.tryLock()) std.atomic.spinLoopHint();
}

fn bindNullableText(statement: *ffi.Statement, index: usize, value: ?[]const u8) !void {
    if (value) |text| try statement.bind(index, .{ .text = text }) else try statement.bind(index, .null);
}

fn run(db: *ffi.Database, sql: []const u8, values: []const ffi.Value) !i64 {
    var statement = try db.prepare(sql);
    defer statement.deinit();
    try statement.bindAll(values);
    return statement.run();
}

fn validateJson(gpa: std.mem.Allocator, raw: []const u8, object_only: bool) !void {
    var parsed = std.json.parseFromSlice(std.json.Value, gpa, raw, .{ .allocate = .alloc_always }) catch return error.InvalidPayload;
    defer parsed.deinit();
    if (object_only and parsed.value != .object) return error.InvalidPayload;
}

fn jsonStringAlloc(gpa: std.mem.Allocator, value: []const u8) ![]u8 {
    var writer: std.Io.Writer.Allocating = .init(gpa);
    errdefer writer.deinit();
    try std.json.Stringify.value(value, .{}, &writer.writer);
    return writer.toOwnedSlice();
}

fn decodeJsonStringAlloc(gpa: std.mem.Allocator, raw: []const u8) ![]u8 {
    var parsed = std.json.parseFromSlice(std.json.Value, gpa, raw, .{ .allocate = .alloc_always }) catch return error.InvalidName;
    defer parsed.deinit();
    if (parsed.value != .string) return error.InvalidName;
    return gpa.dupe(u8, parsed.value.string);
}

fn customTypeFromPayloadAlloc(gpa: std.mem.Allocator, raw: []const u8) ![]u8 {
    var parsed = std.json.parseFromSlice(std.json.Value, gpa, raw, .{ .allocate = .alloc_always }) catch return error.InvalidPayload;
    defer parsed.deinit();
    if (parsed.value != .object) return error.InvalidPayload;
    const value = parsed.value.object.get("customType") orelse return error.InvalidPayload;
    if (value != .string or value.string.len == 0) return error.InvalidPayload;
    return gpa.dupe(u8, value.string);
}

fn appendOwnedText(gpa: std.mem.Allocator, statement: *const ffi.Statement, index: usize) !?[]u8 {
    return statement.columnTextAlloc(gpa, index);
}

fn freeEntries(gpa: std.mem.Allocator, entries: []types.Entry) void {
    for (entries) |*entry| entry.deinit(gpa);
    gpa.free(entries);
}

fn freeRecords(gpa: std.mem.Allocator, records: []types.Record) void {
    for (records) |*record| record.deinit(gpa);
    gpa.free(records);
}

fn cloneEntry(gpa: std.mem.Allocator, source: *const types.Entry) !types.Entry {
    return .{
        .id = try gpa.dupe(u8, source.id),
        .seq = source.seq,
        .parent_id = if (source.parent_id) |value| try gpa.dupe(u8, value) else null,
        .entry_type = source.entry_type,
        .timestamp_ms = source.timestamp_ms,
        .payload_json = try gpa.dupe(u8, source.payload_json),
        .custom_type = if (source.custom_type) |value| try gpa.dupe(u8, value) else null,
    };
}

fn cloneRecord(gpa: std.mem.Allocator, source: *const types.Record) !types.Record {
    return .{
        .id = try gpa.dupe(u8, source.id),
        .seq = source.seq,
        .lane = try gpa.dupe(u8, source.lane),
        .run_id = if (source.run_id) |value| try gpa.dupe(u8, value) else null,
        .record_type = try gpa.dupe(u8, source.record_type),
        .op_kind = if (source.op_kind) |value| try gpa.dupe(u8, value) else null,
        .timestamp_ms = source.timestamp_ms,
        .payload_json = try gpa.dupe(u8, source.payload_json),
    };
}

fn jsonNumber(value: std.json.Value) ?f64 {
    return switch (value) {
        .integer => |number| @floatFromInt(number),
        .float => |number| number,
        else => null,
    };
}

fn usageFromPayload(gpa: std.mem.Allocator, raw: []const u8) !types.Usage {
    var parsed = std.json.parseFromSlice(std.json.Value, gpa, raw, .{ .allocate = .alloc_always }) catch return error.InvalidPayload;
    defer parsed.deinit();
    if (parsed.value != .object) return error.InvalidPayload;
    const root = parsed.value.object;
    const usage_value = root.get("usage") orelse parsed.value;
    if (usage_value != .object) return error.InvalidPayload;
    const object = usage_value.object;
    const input = if (object.get("input")) |value| jsonNumber(value) orelse 0 else 0;
    const cache_read = if (object.get("cacheRead")) |value| jsonNumber(value) orelse 0 else if (object.get("cache_read")) |value| jsonNumber(value) orelse 0 else 0;
    const cache_write = if (object.get("cacheWrite")) |value| jsonNumber(value) orelse 0 else if (object.get("cache_write")) |value| jsonNumber(value) orelse 0 else 0;
    const total_tokens = if (object.get("totalTokens")) |value| jsonNumber(value) orelse 0 else if (object.get("total_tokens")) |value| jsonNumber(value) orelse 0 else 0;
    var cost_total: f64 = 0;
    if (object.get("costTotal")) |value| {
        cost_total = jsonNumber(value) orelse 0;
    } else if (object.get("cost_total")) |value| {
        cost_total = jsonNumber(value) orelse 0;
    } else if (object.get("cost")) |cost| {
        if (cost == .object) {
            if (cost.object.get("total")) |value| cost_total = jsonNumber(value) orelse 0;
        }
    }
    return .{ .input = input, .cache_read = cache_read, .cache_write = cache_write, .total_tokens = total_tokens, .cost_total = cost_total };
}

fn ftsQuotedAlloc(gpa: std.mem.Allocator, text: []const u8) ![]u8 {
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(gpa);
    try out.append(gpa, '"');
    for (text) |byte| {
        if (byte == '"') try out.append(gpa, '"');
        try out.append(gpa, byte);
    }
    try out.append(gpa, '"');
    return out.toOwnedSlice(gpa);
}

pub const Repository = struct {
    gpa: std.mem.Allocator,
    io: Io,
    path: []u8,
    db: ffi.Database,
    mutex: std.atomic.Mutex = .unlocked,
    logical_ms: i64,

    pub fn open(gpa: std.mem.Allocator, io: Io, path: []const u8) !Repository {
        if (!std.mem.eql(u8, path, ":memory:") and !std.mem.startsWith(u8, path, "file:")) {
            if (std.fs.path.dirname(path)) |parent| {
                if (parent.len > 0) try std.Io.Dir.cwd().createDirPath(io, parent);
            }
        }
        var db = try ffi.Database.open(gpa, path);
        errdefer db.deinit();
        try schema.configure(&db);
        try schema.applyMigrations(&db);
        const now = std.Io.Clock.real.now(io).toMilliseconds();
        return .{
            .gpa = gpa,
            .io = io,
            .path = try gpa.dupe(u8, path),
            .db = db,
            .logical_ms = @max(now, 1_720_000_000_000),
        };
    }

    pub fn deinit(self: *Repository) void {
        self.db.deinit();
        self.gpa.free(self.path);
        self.* = undefined;
    }

    fn nowUnlocked(self: *Repository) i64 {
        const wall = std.Io.Clock.real.now(self.io).toMilliseconds();
        self.logical_ms = @max(self.logical_ms + 1, wall);
        return self.logical_ms;
    }

    fn generateIdUnlocked(self: *Repository) ![]u8 {
        var bytes: [16]u8 = undefined;
        try std.Io.randomSecure(self.io, &bytes);
        const timestamp: u64 = @intCast(@max(self.nowUnlocked(), 0));
        bytes[0] = @intCast((timestamp >> 40) & 0xff);
        bytes[1] = @intCast((timestamp >> 32) & 0xff);
        bytes[2] = @intCast((timestamp >> 24) & 0xff);
        bytes[3] = @intCast((timestamp >> 16) & 0xff);
        bytes[4] = @intCast((timestamp >> 8) & 0xff);
        bytes[5] = @intCast(timestamp & 0xff);
        bytes[6] = (bytes[6] & 0x0f) | 0x70;
        bytes[8] = (bytes[8] & 0x3f) | 0x80;
        const hex = std.fmt.bytesToHex(bytes, .lower);
        return std.fmt.allocPrint(self.gpa, "{s}-{s}-{s}-{s}-{s}", .{ hex[0..8], hex[8..12], hex[12..16], hex[16..20], hex[20..32] });
    }

    fn sessionExistsUnlocked(self: *Repository, session_id: []const u8) !bool {
        var statement = try self.db.prepare("SELECT 1 FROM sessions WHERE id = ? LIMIT 1");
        defer statement.deinit();
        try statement.bind(1, .{ .text = session_id });
        return (try statement.step()) == .row;
    }

    fn requireSessionUnlocked(self: *Repository, session_id: []const u8) !void {
        if (!try self.sessionExistsUnlocked(session_id)) return error.SessionNotFound;
    }

    fn nextSequenceUnlocked(self: *Repository, session_id: []const u8) !i64 {
        var statement = try self.db.prepare("SELECT next_seq FROM session_sequences WHERE session_id = ?");
        defer statement.deinit();
        try statement.bind(1, .{ .text = session_id });
        if (try statement.step() != .row) return error.MissingSequence;
        return statement.columnInt(0);
    }

    fn setNextSequenceUnlocked(self: *Repository, session_id: []const u8, next: i64) !void {
        const changed = try run(&self.db, "UPDATE session_sequences SET next_seq = ? WHERE session_id = ?", &.{ .{ .integer = next }, .{ .text = session_id } });
        if (changed != 1) return error.MissingSequence;
    }

    fn allocateSequenceUnlocked(self: *Repository, session_id: []const u8) !i64 {
        const seq = try self.nextSequenceUnlocked(session_id);
        try self.setNextSequenceUnlocked(session_id, seq + 1);
        return seq;
    }

    fn parseSessionRowUnlocked(self: *Repository, statement: *const ffi.Statement) !types.SessionMetadata {
        var metadata = types.SessionMetadata{
            .id = (try appendOwnedText(self.gpa, statement, 0)).?,
            .created_at_ms = try statement.columnInt(1),
            .cwd = (try appendOwnedText(self.gpa, statement, 2)).?,
            .path = try self.gpa.dupe(u8, self.path),
            .parent_session_id = try appendOwnedText(self.gpa, statement, 3),
            .metadata_json = try appendOwnedText(self.gpa, statement, 4),
        };
        errdefer metadata.deinit(self.gpa);
        if (try statement.columnText(5)) |raw_name| metadata.name = try decodeJsonStringAlloc(self.gpa, raw_name);
        return metadata;
    }

    const session_select =
        \\SELECT s.id, s.created_at, s.cwd, s.parent_session_id, s.metadata,
        \\  (SELECT f.value FROM facts AS f
        \\   WHERE f.session_id = s.id AND f.kind = 'name' AND f.key IS NULL
        \\   ORDER BY f.seq DESC LIMIT 1) AS session_name
        \\FROM sessions AS s
    ;

    pub fn createSession(self: *Repository, options: types.CreateSessionOptions) !types.SessionMetadata {
        lockMutex(&self.mutex);
        defer self.mutex.unlock();
        if (options.metadata_json) |raw| {
            validateJson(self.gpa, raw, true) catch return error.InvalidMetadata;
        }
        if (options.parent_session_id) |parent| try self.requireSessionUnlocked(parent);
        const generated = if (options.id == null) try self.generateIdUnlocked() else null;
        defer if (generated) |id| self.gpa.free(id);
        const id = options.id orelse generated.?;
        if (try self.sessionExistsUnlocked(id)) return error.SessionAlreadyExists;
        const created_at = options.created_at_ms orelse self.nowUnlocked();

        try self.db.beginImmediate();
        errdefer self.db.rollback();
        var insert = try self.db.prepare(
            "INSERT INTO sessions(id, created_at, cwd, parent_session_id, metadata) VALUES(?, ?, ?, ?, ?)",
        );
        defer insert.deinit();
        try insert.bind(1, .{ .text = id });
        try insert.bind(2, .{ .integer = created_at });
        try insert.bind(3, .{ .text = options.cwd });
        try bindNullableText(&insert, 4, options.parent_session_id);
        try bindNullableText(&insert, 5, options.metadata_json);
        _ = insert.run() catch |err| switch (err) {
            error.Constraint => return error.SessionAlreadyExists,
            else => return err,
        };
        _ = try run(&self.db, "INSERT INTO session_sequences(session_id, next_seq) VALUES(?, 1)", &.{.{ .text = id }});
        _ = try run(
            &self.db,
            "INSERT INTO session_stats(session_id, message_count, cached_tokens, uncached_tokens, total_tokens, cost_total) VALUES(?, 0, 0, 0, 0, 0)",
            &.{.{ .text = id }},
        );
        _ = try run(&self.db, "INSERT INTO lanes(session_id, lane, leaf_id, open_operation_id) VALUES(?, 'main', NULL, NULL)", &.{.{ .text = id }});
        try self.db.commit();
        return self.getSessionUnlocked(id);
    }

    fn getSessionUnlocked(self: *Repository, session_id: []const u8) !types.SessionMetadata {
        var statement = try self.db.prepare(session_select ++ " WHERE s.id = ?");
        defer statement.deinit();
        try statement.bind(1, .{ .text = session_id });
        if (try statement.step() != .row) return error.SessionNotFound;
        return self.parseSessionRowUnlocked(&statement);
    }

    pub fn getSession(self: *Repository, session_id: []const u8) !types.SessionMetadata {
        lockMutex(&self.mutex);
        defer self.mutex.unlock();
        return self.getSessionUnlocked(session_id);
    }

    pub fn listSessions(self: *Repository, cwd: ?[]const u8) ![]types.SessionMetadata {
        lockMutex(&self.mutex);
        defer self.mutex.unlock();
        const sql = if (cwd == null)
            session_select ++ " ORDER BY s.created_at DESC"
        else
            session_select ++ " WHERE s.cwd = ? ORDER BY s.created_at DESC";
        var statement = try self.db.prepare(sql);
        defer statement.deinit();
        if (cwd) |value| try statement.bind(1, .{ .text = value });
        var sessions: std.ArrayList(types.SessionMetadata) = .empty;
        errdefer {
            for (sessions.items) |*metadata| metadata.deinit(self.gpa);
            sessions.deinit(self.gpa);
        }
        while (try statement.step() == .row) try sessions.append(self.gpa, try self.parseSessionRowUnlocked(&statement));
        return sessions.toOwnedSlice(self.gpa);
    }

    pub fn deleteSession(self: *Repository, session_id: []const u8) !bool {
        lockMutex(&self.mutex);
        defer self.mutex.unlock();
        if (!try self.sessionExistsUnlocked(session_id)) {
            _ = try run(&self.db, "DELETE FROM writer_leases WHERE session_id = ?", &.{.{ .text = session_id }});
            return false;
        }
        try self.db.beginImmediate();
        errdefer self.db.rollback();
        const tables = [_][]const u8{
            "branch_tips", "branch_entries", "facts", "lane_moves", "lanes", "records", "entries", "writer_leases", "session_stats", "session_sequences",
        };
        inline for (tables) |table| {
            _ = try run(&self.db, "DELETE FROM " ++ table ++ " WHERE session_id = ?", &.{.{ .text = session_id }});
        }
        _ = try run(&self.db, "DELETE FROM sessions WHERE id = ?", &.{.{ .text = session_id }});
        try self.db.commit();
        return true;
    }

    pub fn acquireWriterLease(self: *Repository, session_id: []const u8, owner_id: []const u8, now_ms: i64, ttl_ms: i64) !?types.WriterLease {
        lockMutex(&self.mutex);
        defer self.mutex.unlock();
        try self.requireSessionUnlocked(session_id);
        if (ttl_ms <= 0) return error.InvalidPayload;
        const expires = now_ms + ttl_ms;
        try self.db.beginImmediate();
        errdefer self.db.rollback();
        var statement = try self.db.prepare(
            \\INSERT INTO writer_leases(session_id, owner_id, fence, expires_at_ms)
            \\VALUES(?, ?, 1, ?)
            \\ON CONFLICT(session_id) DO UPDATE SET
            \\  owner_id = excluded.owner_id,
            \\  fence = writer_leases.fence + 1,
            \\  expires_at_ms = excluded.expires_at_ms
            \\WHERE writer_leases.expires_at_ms <= ?
            \\RETURNING owner_id, fence, expires_at_ms
        );
        errdefer statement.deinit();
        try statement.bindAll(&.{ .{ .text = session_id }, .{ .text = owner_id }, .{ .integer = expires }, .{ .integer = now_ms } });
        if (try statement.step() != .row) {
            statement.deinit();
            try self.db.commit();
            return null;
        }
        var lease = types.WriterLease{
            .session_id = try self.gpa.dupe(u8, session_id),
            .owner_id = (try statement.columnTextAlloc(self.gpa, 0)).?,
            .fence = try statement.columnInt(1),
            .expires_at_ms = try statement.columnInt(2),
        };
        errdefer lease.deinit(self.gpa);
        statement.deinit();
        try self.db.commit();
        return lease;
    }

    pub fn renewWriterLease(self: *Repository, lease: *types.WriterLease, now_ms: i64, ttl_ms: i64) !bool {
        lockMutex(&self.mutex);
        defer self.mutex.unlock();
        if (ttl_ms <= 0) return false;
        const expires = now_ms + ttl_ms;
        const changed = try run(&self.db,
            \\UPDATE writer_leases SET expires_at_ms = ?
            \\WHERE session_id = ? AND owner_id = ? AND fence = ? AND expires_at_ms > ?
        , &.{ .{ .integer = expires }, .{ .text = lease.session_id }, .{ .text = lease.owner_id }, .{ .integer = lease.fence }, .{ .integer = now_ms } });
        if (changed == 1) lease.expires_at_ms = expires;
        return changed == 1;
    }

    pub fn releaseWriterLease(self: *Repository, lease: *const types.WriterLease) !bool {
        lockMutex(&self.mutex);
        defer self.mutex.unlock();
        return (try run(
            &self.db,
            "DELETE FROM writer_leases WHERE session_id = ? AND owner_id = ? AND fence = ?",
            &.{ .{ .text = lease.session_id }, .{ .text = lease.owner_id }, .{ .integer = lease.fence } },
        )) == 1;
    }

    fn verifyLeaseUnlocked(self: *Repository, session_id: []const u8, lease: *const types.WriterLease, now_ms: i64) !void {
        if (!std.mem.eql(u8, session_id, lease.session_id)) return error.LostWriterLease;
        var statement = try self.db.prepare(
            "SELECT 1 FROM writer_leases WHERE session_id = ? AND owner_id = ? AND fence = ? AND expires_at_ms > ?",
        );
        defer statement.deinit();
        try statement.bindAll(&.{ .{ .text = session_id }, .{ .text = lease.owner_id }, .{ .integer = lease.fence }, .{ .integer = now_ms } });
        if (try statement.step() != .row) return error.LostWriterLease;
    }

    fn entryExistsUnlocked(self: *Repository, session_id: []const u8, entry_id: []const u8) !bool {
        var statement = try self.db.prepare("SELECT 1 FROM entries WHERE session_id = ? AND id = ? LIMIT 1");
        defer statement.deinit();
        try statement.bindAll(&.{ .{ .text = session_id }, .{ .text = entry_id } });
        return (try statement.step()) == .row;
    }

    fn recordExistsUnlocked(self: *Repository, session_id: []const u8, record_id: []const u8) !bool {
        var statement = try self.db.prepare("SELECT 1 FROM records WHERE session_id = ? AND id = ? LIMIT 1");
        defer statement.deinit();
        try statement.bindAll(&.{ .{ .text = session_id }, .{ .text = record_id } });
        return (try statement.step()) == .row;
    }

    fn requireUnusedIdUnlocked(self: *Repository, session_id: []const u8, id: []const u8) !void {
        if (try self.entryExistsUnlocked(session_id, id) or try self.recordExistsUnlocked(session_id, id)) return error.EntryAlreadyExists;
    }

    fn laneHeadUnlocked(self: *Repository, session_id: []const u8, lane: []const u8) !?[]u8 {
        var statement = try self.db.prepare("SELECT leaf_id FROM lanes WHERE session_id = ? AND lane = ?");
        defer statement.deinit();
        try statement.bindAll(&.{ .{ .text = session_id }, .{ .text = lane } });
        if (try statement.step() != .row) return error.InvalidLane;
        const leaf = try statement.columnTextAlloc(self.gpa, 0);
        if (leaf) |id| {
            errdefer self.gpa.free(id);
            if (!try self.entryExistsUnlocked(session_id, id)) return error.InvalidEntry;
        }
        return leaf;
    }

    fn laneExistsUnlocked(self: *Repository, session_id: []const u8, lane: []const u8) !bool {
        var statement = try self.db.prepare("SELECT 1 FROM lanes WHERE session_id = ? AND lane = ? LIMIT 1");
        defer statement.deinit();
        try statement.bindAll(&.{ .{ .text = session_id }, .{ .text = lane } });
        return (try statement.step()) == .row;
    }

    pub fn listLanes(self: *Repository, session_id: []const u8) ![]types.Lane {
        lockMutex(&self.mutex);
        defer self.mutex.unlock();
        try self.requireSessionUnlocked(session_id);
        var statement = try self.db.prepare("SELECT lane, leaf_id, open_operation_id FROM lanes WHERE session_id = ? ORDER BY lane");
        defer statement.deinit();
        try statement.bind(1, .{ .text = session_id });
        var lanes: std.ArrayList(types.Lane) = .empty;
        errdefer {
            for (lanes.items) |*lane| lane.deinit(self.gpa);
            lanes.deinit(self.gpa);
        }
        while (try statement.step() == .row) {
            var lane = types.Lane{
                .name = (try statement.columnTextAlloc(self.gpa, 0)).?,
                .leaf_id = try statement.columnTextAlloc(self.gpa, 1),
                .open_operation_id = try statement.columnTextAlloc(self.gpa, 2),
            };
            errdefer lane.deinit(self.gpa);
            if (lane.leaf_id) |leaf| if (!try self.entryExistsUnlocked(session_id, leaf)) return error.InvalidEntry;
            try lanes.append(self.gpa, lane);
        }
        return lanes.toOwnedSlice(self.gpa);
    }

    pub fn createLane(self: *Repository, session_id: []const u8, lane: []const u8, at: ?[]const u8, lease: ?*const types.WriterLease) !void {
        lockMutex(&self.mutex);
        defer self.mutex.unlock();
        try self.requireSessionUnlocked(session_id);
        if (lane.len == 0) return error.InvalidLane;
        if (try self.laneExistsUnlocked(session_id, lane)) return error.LaneAlreadyExists;
        if (at) |entry_id| if (!try self.entryExistsUnlocked(session_id, entry_id)) return error.EntryNotFound;
        const now = self.nowUnlocked();
        try self.db.beginImmediate();
        errdefer self.db.rollback();
        if (lease) |claim| try self.verifyLeaseUnlocked(session_id, claim, now);
        const seq = try self.nextSequenceUnlocked(session_id);
        var insert = try self.db.prepare("INSERT INTO lanes(session_id, lane, leaf_id, open_operation_id) VALUES(?, ?, ?, NULL)");
        defer insert.deinit();
        try insert.bind(1, .{ .text = session_id });
        try insert.bind(2, .{ .text = lane });
        try bindNullableText(&insert, 3, at);
        _ = insert.run() catch |err| switch (err) {
            error.Constraint => return error.LaneAlreadyExists,
            else => return err,
        };
        var move = try self.db.prepare("INSERT INTO lane_moves(session_id, seq, lane, leaf_id) VALUES(?, ?, ?, ?)");
        defer move.deinit();
        try move.bind(1, .{ .text = session_id });
        try move.bind(2, .{ .integer = seq });
        try move.bind(3, .{ .text = lane });
        try bindNullableText(&move, 4, at);
        _ = try move.run();
        try self.setNextSequenceUnlocked(session_id, seq + 1);
        try self.db.commit();
    }

    pub fn moveLane(self: *Repository, session_id: []const u8, lane: []const u8, to: ?[]const u8, lease: ?*const types.WriterLease) !void {
        lockMutex(&self.mutex);
        defer self.mutex.unlock();
        try self.requireSessionUnlocked(session_id);
        if (!try self.laneExistsUnlocked(session_id, lane)) return error.InvalidLane;
        if (to) |entry_id| if (!try self.entryExistsUnlocked(session_id, entry_id)) return error.EntryNotFound;
        const now = self.nowUnlocked();
        try self.db.beginImmediate();
        errdefer self.db.rollback();
        if (lease) |claim| try self.verifyLeaseUnlocked(session_id, claim, now);
        const seq = try self.nextSequenceUnlocked(session_id);
        var update = try self.db.prepare("UPDATE lanes SET leaf_id = ? WHERE session_id = ? AND lane = ?");
        defer update.deinit();
        try bindNullableText(&update, 1, to);
        try update.bind(2, .{ .text = session_id });
        try update.bind(3, .{ .text = lane });
        if (try update.run() != 1) return error.InvalidLane;
        var move = try self.db.prepare("INSERT INTO lane_moves(session_id, seq, lane, leaf_id) VALUES(?, ?, ?, ?)");
        defer move.deinit();
        try move.bind(1, .{ .text = session_id });
        try move.bind(2, .{ .integer = seq });
        try move.bind(3, .{ .text = lane });
        try bindNullableText(&move, 4, to);
        _ = try move.run();
        try self.setNextSequenceUnlocked(session_id, seq + 1);
        try self.db.commit();
    }

    fn insertBranchMembershipUnlocked(
        self: *Repository,
        session_id: []const u8,
        branch_id: []const u8,
        entry_id: []const u8,
        seq: i64,
        entry_type: types.EntryType,
        custom_type: ?[]const u8,
    ) !void {
        var statement = try self.db.prepare(
            "INSERT INTO branch_entries(session_id, branch_id, entry_id, entry_seq, entry_type, custom_type) VALUES(?, ?, ?, ?, ?, ?)",
        );
        defer statement.deinit();
        try statement.bind(1, .{ .text = session_id });
        try statement.bind(2, .{ .text = branch_id });
        try statement.bind(3, .{ .text = entry_id });
        try statement.bind(4, .{ .integer = seq });
        try statement.bind(5, .{ .text = entry_type.wireName() });
        try bindNullableText(&statement, 6, custom_type);
        _ = try statement.run();
    }

    fn appendBranchCacheUnlocked(
        self: *Repository,
        session_id: []const u8,
        entry_id: []const u8,
        seq: i64,
        entry_type: types.EntryType,
        custom_type: ?[]const u8,
        parent_id: ?[]const u8,
    ) !void {
        if (parent_id == null) {
            const branch_id = try self.generateIdUnlocked();
            defer self.gpa.free(branch_id);
            try self.insertBranchMembershipUnlocked(session_id, branch_id, entry_id, seq, entry_type, custom_type);
            _ = try run(&self.db, "INSERT INTO branch_tips(session_id, branch_id, tip_id) VALUES(?, ?, ?)", &.{ .{ .text = session_id }, .{ .text = branch_id }, .{ .text = entry_id } });
            return;
        }
        const parent = parent_id.?;
        var tip = try self.db.prepare("SELECT branch_id FROM branch_tips WHERE session_id = ? AND tip_id = ?");
        defer tip.deinit();
        try tip.bindAll(&.{ .{ .text = session_id }, .{ .text = parent } });
        if (try tip.step() == .row) {
            const branch_id = (try tip.columnText(0)).?;
            try self.insertBranchMembershipUnlocked(session_id, branch_id, entry_id, seq, entry_type, custom_type);
            const changed = try run(
                &self.db,
                "UPDATE branch_tips SET tip_id = ? WHERE session_id = ? AND branch_id = ? AND tip_id = ?",
                &.{ .{ .text = entry_id }, .{ .text = session_id }, .{ .text = branch_id }, .{ .text = parent } },
            );
            if (changed != 1) return error.InvalidEntry;
            return;
        }

        var source = try self.db.prepare(
            "SELECT branch_id, entry_seq FROM branch_entries WHERE session_id = ? AND entry_id = ? ORDER BY branch_id LIMIT 1",
        );
        defer source.deinit();
        try source.bindAll(&.{ .{ .text = session_id }, .{ .text = parent } });
        if (try source.step() != .row) return error.InvalidEntry;
        const source_branch = try self.gpa.dupe(u8, (try source.columnText(0)).?);
        defer self.gpa.free(source_branch);
        const through_seq = try source.columnInt(1);
        const branch_id = try self.generateIdUnlocked();
        defer self.gpa.free(branch_id);
        _ = try run(&self.db,
            \\INSERT INTO branch_entries(session_id, branch_id, entry_id, entry_seq, entry_type, custom_type)
            \\SELECT session_id, ?, entry_id, entry_seq, entry_type, custom_type
            \\FROM branch_entries WHERE session_id = ? AND branch_id = ? AND entry_seq <= ?
        , &.{ .{ .text = branch_id }, .{ .text = session_id }, .{ .text = source_branch }, .{ .integer = through_seq } });
        try self.insertBranchMembershipUnlocked(session_id, branch_id, entry_id, seq, entry_type, custom_type);
        _ = try run(&self.db, "INSERT INTO branch_tips(session_id, branch_id, tip_id) VALUES(?, ?, ?)", &.{ .{ .text = session_id }, .{ .text = branch_id }, .{ .text = entry_id } });
    }

    fn parseEntryRowUnlocked(self: *Repository, statement: *const ffi.Statement) !types.Entry {
        const type_text = (try statement.columnText(3)).?;
        const entry_type = types.EntryType.parse(type_text) orelse return error.InvalidEntry;
        var entry = types.Entry{
            .id = (try statement.columnTextAlloc(self.gpa, 0)).?,
            .seq = try statement.columnInt(1),
            .parent_id = try statement.columnTextAlloc(self.gpa, 2),
            .entry_type = entry_type,
            .timestamp_ms = try statement.columnInt(4),
            .payload_json = (try statement.columnTextAlloc(self.gpa, 5)).?,
            .custom_type = try statement.columnTextAlloc(self.gpa, 6),
        };
        errdefer entry.deinit(self.gpa);
        if (entry.entry_type == .custom and entry.custom_type == null) {
            entry.custom_type = customTypeFromPayloadAlloc(self.gpa, entry.payload_json) catch return error.InvalidEntry;
        }
        return entry;
    }

    fn getEntryUnlocked(self: *Repository, session_id: []const u8, entry_id: []const u8) !?types.Entry {
        var statement = try self.db.prepare(
            \\SELECT e.id, e.seq, e.parent_id, e.type, e.timestamp, e.payload,
            \\  (SELECT b.custom_type FROM branch_entries AS b
            \\   WHERE b.session_id = e.session_id AND b.entry_id = e.id LIMIT 1)
            \\FROM entries AS e WHERE e.session_id = ? AND e.id = ?
        );
        defer statement.deinit();
        try statement.bindAll(&.{ .{ .text = session_id }, .{ .text = entry_id } });
        if (try statement.step() != .row) return null;
        return try self.parseEntryRowUnlocked(&statement);
    }

    pub fn getEntry(self: *Repository, session_id: []const u8, entry_id: []const u8) !?types.Entry {
        lockMutex(&self.mutex);
        defer self.mutex.unlock();
        try self.requireSessionUnlocked(session_id);
        return self.getEntryUnlocked(session_id, entry_id);
    }

    pub fn appendEntry(
        self: *Repository,
        session_id: []const u8,
        lane: []const u8,
        options: types.AppendEntry,
        lease: ?*const types.WriterLease,
    ) !types.Entry {
        lockMutex(&self.mutex);
        defer self.mutex.unlock();
        try self.requireSessionUnlocked(session_id);
        try validateJson(self.gpa, options.payload_json, true);
        const derived_custom = if (options.entry_type == .custom and options.custom_type == null)
            try customTypeFromPayloadAlloc(self.gpa, options.payload_json)
        else
            null;
        defer if (derived_custom) |value| self.gpa.free(value);
        const custom_type = if (options.entry_type == .custom) options.custom_type orelse derived_custom.? else null;
        if (options.entry_type != .custom and options.custom_type != null) return error.InvalidPayload;

        const generated = if (options.id == null) try self.generateIdUnlocked() else null;
        defer if (generated) |id| self.gpa.free(id);
        const id = options.id orelse generated.?;
        try self.requireUnusedIdUnlocked(session_id, id);
        const parent_owned = try self.laneHeadUnlocked(session_id, lane);
        defer if (parent_owned) |parent| self.gpa.free(parent);
        const parent_id: ?[]const u8 = if (parent_owned) |parent| parent else null;
        const now = options.timestamp_ms orelse self.nowUnlocked();

        try self.db.beginImmediate();
        errdefer self.db.rollback();
        if (lease) |claim| try self.verifyLeaseUnlocked(session_id, claim, now);
        const seq = try self.nextSequenceUnlocked(session_id);
        var insert = try self.db.prepare(
            "INSERT INTO entries(session_id, seq, id, parent_id, type, timestamp, payload) VALUES(?, ?, ?, ?, ?, ?, ?)",
        );
        defer insert.deinit();
        try insert.bind(1, .{ .text = session_id });
        try insert.bind(2, .{ .integer = seq });
        try insert.bind(3, .{ .text = id });
        try bindNullableText(&insert, 4, parent_id);
        try insert.bind(5, .{ .text = options.entry_type.wireName() });
        try insert.bind(6, .{ .integer = now });
        try insert.bind(7, .{ .text = options.payload_json });
        _ = insert.run() catch |err| switch (err) {
            error.Constraint => return error.EntryAlreadyExists,
            else => return err,
        };
        const moved = try run(&self.db, "UPDATE lanes SET leaf_id = ? WHERE session_id = ? AND lane = ?", &.{ .{ .text = id }, .{ .text = session_id }, .{ .text = lane } });
        if (moved != 1) return error.InvalidLane;
        try self.appendBranchCacheUnlocked(session_id, id, seq, options.entry_type, custom_type, parent_id);
        if (options.entry_type == .message) {
            const changed = try run(&self.db, "UPDATE session_stats SET message_count = message_count + 1 WHERE session_id = ?", &.{.{ .text = session_id }});
            if (changed != 1) return error.InvalidEntry;
        }
        try self.setNextSequenceUnlocked(session_id, seq + 1);
        try self.db.commit();
        return .{
            .id = try self.gpa.dupe(u8, id),
            .seq = seq,
            .parent_id = if (parent_id) |parent| try self.gpa.dupe(u8, parent) else null,
            .entry_type = options.entry_type,
            .timestamp_ms = now,
            .payload_json = try self.gpa.dupe(u8, options.payload_json),
            .custom_type = if (custom_type) |value| try self.gpa.dupe(u8, value) else null,
        };
    }

    fn findEntriesUnlocked(self: *Repository, session_id: []const u8, query: types.EntryQuery) ![]types.Entry {
        const effective_type = query.entry_type orelse if (query.custom_type != null) types.EntryType.custom else null;
        const base_sql = "SELECT e.id, e.seq, e.parent_id, e.type, e.timestamp, e.payload, " ++
            "(SELECT b.custom_type FROM branch_entries AS b WHERE b.session_id = e.session_id AND b.entry_id = e.id LIMIT 1) " ++
            "FROM entries AS e WHERE e.session_id = ? AND (? IS NULL OR e.type = ?)";
        const sql = if (query.order == .oldest_first)
            base_sql ++ " AND (? IS NULL OR e.seq > ?) ORDER BY e.seq ASC LIMIT ?"
        else
            base_sql ++ " AND (? IS NULL OR e.seq < ?) ORDER BY e.seq DESC LIMIT ?";
        var statement = try self.db.prepare(sql);
        defer statement.deinit();
        try statement.bind(1, .{ .text = session_id });
        if (effective_type) |entry_type| {
            try statement.bind(2, .{ .text = entry_type.wireName() });
            try statement.bind(3, .{ .text = entry_type.wireName() });
        } else {
            try statement.bind(2, .null);
            try statement.bind(3, .null);
        }
        if (query.after_seq) |cursor| {
            try statement.bind(4, .{ .integer = cursor });
            try statement.bind(5, .{ .integer = cursor });
        } else {
            try statement.bind(4, .null);
            try statement.bind(5, .null);
        }
        const sql_limit: i64 = if (query.custom_type == null and query.limit != null)
            @intCast(@min(query.limit.?, @as(usize, @intCast(std.math.maxInt(i64)))))
        else
            -1;
        try statement.bind(6, .{ .integer = sql_limit });

        var entries: std.ArrayList(types.Entry) = .empty;
        errdefer {
            for (entries.items) |*entry| entry.deinit(self.gpa);
            entries.deinit(self.gpa);
        }
        while (try statement.step() == .row) {
            var entry = try self.parseEntryRowUnlocked(&statement);
            if (query.custom_type) |custom_type| {
                if (entry.custom_type == null or !std.mem.eql(u8, entry.custom_type.?, custom_type)) {
                    entry.deinit(self.gpa);
                    continue;
                }
            }
            try entries.append(self.gpa, entry);
            if (query.limit) |limit| if (entries.items.len >= limit) break;
        }
        return entries.toOwnedSlice(self.gpa);
    }

    pub fn findEntries(self: *Repository, session_id: []const u8, query: types.EntryQuery) ![]types.Entry {
        lockMutex(&self.mutex);
        defer self.mutex.unlock();
        try self.requireSessionUnlocked(session_id);
        if (query.limit == 0) return self.gpa.alloc(types.Entry, 0);
        return self.findEntriesUnlocked(session_id, query);
    }

    pub fn findEntriesOnBranch(self: *Repository, session_id: []const u8, start: []const u8, query: types.EntryQuery) ![]types.Entry {
        lockMutex(&self.mutex);
        defer self.mutex.unlock();
        try self.requireSessionUnlocked(session_id);
        if (query.limit == 0) return self.gpa.alloc(types.Entry, 0);

        var path: std.ArrayList(types.Entry) = .empty;
        defer {
            for (path.items) |*entry| entry.deinit(self.gpa);
            path.deinit(self.gpa);
        }
        var seen: std.StringHashMapUnmanaged(void) = .empty;
        defer seen.deinit(self.gpa);
        var current_id = try self.gpa.dupe(u8, start);
        defer self.gpa.free(current_id);
        while (true) {
            const result = try seen.getOrPut(self.gpa, current_id);
            if (result.found_existing) return error.InvalidEntry;
            const entry = (try self.getEntryUnlocked(session_id, current_id)) orelse {
                if (path.items.len == 0) return error.EntryNotFound;
                return error.InvalidEntry;
            };
            try path.append(self.gpa, entry);
            const by_id = if (query.stop_at_id) |id| std.mem.eql(u8, id, entry.id) else false;
            const by_type = if (query.stop_at_type) |entry_type| entry.entry_type == entry_type else false;
            if (by_id or by_type) break;
            const parent = entry.parent_id orelse break;
            const replacement = try self.gpa.dupe(u8, parent);
            self.gpa.free(current_id);
            current_id = replacement;
        }
        var output: std.ArrayList(types.Entry) = .empty;
        errdefer {
            for (output.items) |*entry| entry.deinit(self.gpa);
            output.deinit(self.gpa);
        }
        var index: usize = if (query.order == .oldest_first) path.items.len else 0;
        while (if (query.order == .oldest_first) index > 0 else index < path.items.len) {
            if (query.order == .oldest_first) index -= 1;
            const entry = &path.items[index];
            const cursor_match = if (query.after_seq) |cursor|
                if (query.order == .oldest_first) entry.seq > cursor else entry.seq < cursor
            else
                true;
            const type_match = query.entry_type == null or entry.entry_type == query.entry_type.?;
            const custom_match = if (query.custom_type) |custom_type|
                entry.custom_type != null and std.mem.eql(u8, entry.custom_type.?, custom_type)
            else
                true;
            if (cursor_match and type_match and custom_match) try output.append(self.gpa, try cloneEntry(self.gpa, entry));
            if (query.limit) |limit| if (output.items.len >= limit) break;
            if (query.order == .newest_first) index += 1;
        }
        return output.toOwnedSlice(self.gpa);
    }

    fn parseRecordRowUnlocked(self: *Repository, statement: *const ffi.Statement) !types.Record {
        return .{
            .seq = try statement.columnInt(0),
            .id = (try statement.columnTextAlloc(self.gpa, 1)).?,
            .lane = (try statement.columnTextAlloc(self.gpa, 2)).?,
            .run_id = try statement.columnTextAlloc(self.gpa, 3),
            .record_type = (try statement.columnTextAlloc(self.gpa, 4)).?,
            .op_kind = try statement.columnTextAlloc(self.gpa, 5),
            .timestamp_ms = try statement.columnInt(6),
            .payload_json = (try statement.columnTextAlloc(self.gpa, 7)).?,
        };
    }

    fn findRecordsUnlocked(self: *Repository, session_id: []const u8, query: types.RecordQuery) ![]types.Record {
        const base_sql = "SELECT seq, id, lane, run_id, type, op_kind, timestamp, payload FROM records " ++
            "WHERE session_id = ? AND (? IS NULL OR lane = ?) AND (? IS NULL OR type = ?) " ++
            "AND (? IS NULL OR op_kind = ?) AND (? IS NULL OR run_id = ?) AND (? IS NULL OR seq > ?) ";
        const sql = if (query.order == .oldest_first)
            base_sql ++ "ORDER BY seq ASC LIMIT ?"
        else
            base_sql ++ "ORDER BY seq DESC LIMIT ?";
        var statement = try self.db.prepare(sql);
        defer statement.deinit();
        try statement.bind(1, .{ .text = session_id });
        const optionals = [_]?[]const u8{ query.lane, query.record_type, query.op_kind, query.run_id };
        var bind_index: usize = 2;
        for (optionals) |value| {
            if (value) |text| {
                try statement.bind(bind_index, .{ .text = text });
                try statement.bind(bind_index + 1, .{ .text = text });
            } else {
                try statement.bind(bind_index, .null);
                try statement.bind(bind_index + 1, .null);
            }
            bind_index += 2;
        }
        if (query.after_seq) |cursor| {
            try statement.bind(bind_index, .{ .integer = cursor });
            try statement.bind(bind_index + 1, .{ .integer = cursor });
        } else {
            try statement.bind(bind_index, .null);
            try statement.bind(bind_index + 1, .null);
        }
        bind_index += 2;
        const limit: i64 = if (query.limit) |value| @intCast(@min(value, @as(usize, @intCast(std.math.maxInt(i64))))) else -1;
        try statement.bind(bind_index, .{ .integer = limit });

        var records: std.ArrayList(types.Record) = .empty;
        errdefer {
            for (records.items) |*record| record.deinit(self.gpa);
            records.deinit(self.gpa);
        }
        while (try statement.step() == .row) try records.append(self.gpa, try self.parseRecordRowUnlocked(&statement));
        return records.toOwnedSlice(self.gpa);
    }

    pub fn findRecords(self: *Repository, session_id: []const u8, query: types.RecordQuery) ![]types.Record {
        lockMutex(&self.mutex);
        defer self.mutex.unlock();
        try self.requireSessionUnlocked(session_id);
        if (query.limit == 0) return self.gpa.alloc(types.Record, 0);
        return self.findRecordsUnlocked(session_id, query);
    }

    pub fn appendRecord(
        self: *Repository,
        session_id: []const u8,
        options: types.AppendRecord,
        lease: ?*const types.WriterLease,
    ) !types.Record {
        lockMutex(&self.mutex);
        defer self.mutex.unlock();
        try self.requireSessionUnlocked(session_id);
        if (!try self.laneExistsUnlocked(session_id, options.lane)) return error.InvalidLane;
        try validateJson(self.gpa, options.payload_json, true);
        if (options.record_type.len == 0) return error.InvalidPayload;
        const generated = if (options.id == null) try self.generateIdUnlocked() else null;
        defer if (generated) |id| self.gpa.free(id);
        const id = options.id orelse generated.?;
        try self.requireUnusedIdUnlocked(session_id, id);
        const now = options.timestamp_ms orelse self.nowUnlocked();
        const run_id = if (std.mem.eql(u8, options.record_type, "operation_started")) id else options.run_id;
        if (std.mem.eql(u8, options.record_type, "operation_finished") and run_id == null) return error.InvalidPayload;
        const parsed_usage = if (std.mem.eql(u8, options.record_type, "usage") and options.usage == null)
            try usageFromPayload(self.gpa, options.payload_json)
        else
            null;
        const usage = options.usage orelse parsed_usage;

        try self.db.beginImmediate();
        errdefer self.db.rollback();
        if (lease) |claim| try self.verifyLeaseUnlocked(session_id, claim, now);
        const seq = try self.nextSequenceUnlocked(session_id);
        if (std.mem.eql(u8, options.record_type, "operation_started")) {
            const changed = try run(
                &self.db,
                "UPDATE lanes SET open_operation_id = ? WHERE session_id = ? AND lane = ? AND open_operation_id IS NULL",
                &.{ .{ .text = id }, .{ .text = session_id }, .{ .text = options.lane } },
            );
            if (changed != 1) return error.OpenOperation;
        }
        var insert = try self.db.prepare(
            "INSERT INTO records(session_id, seq, id, lane, run_id, type, op_kind, timestamp, payload) VALUES(?, ?, ?, ?, ?, ?, ?, ?, ?)",
        );
        defer insert.deinit();
        try insert.bind(1, .{ .text = session_id });
        try insert.bind(2, .{ .integer = seq });
        try insert.bind(3, .{ .text = id });
        try insert.bind(4, .{ .text = options.lane });
        try bindNullableText(&insert, 5, run_id);
        try insert.bind(6, .{ .text = options.record_type });
        try bindNullableText(&insert, 7, options.op_kind);
        try insert.bind(8, .{ .integer = now });
        try insert.bind(9, .{ .text = options.payload_json });
        _ = insert.run() catch |err| switch (err) {
            error.Constraint => return error.EntryAlreadyExists,
            else => return err,
        };
        if (std.mem.eql(u8, options.record_type, "operation_finished")) {
            _ = try run(
                &self.db,
                "UPDATE lanes SET open_operation_id = NULL WHERE session_id = ? AND lane = ? AND open_operation_id = ?",
                &.{ .{ .text = session_id }, .{ .text = options.lane }, .{ .text = run_id.? } },
            );
        }
        if (std.mem.eql(u8, options.record_type, "usage")) try self.addUsageUnlocked(session_id, usage.?);
        try self.setNextSequenceUnlocked(session_id, seq + 1);
        try self.db.commit();
        return .{
            .id = try self.gpa.dupe(u8, id),
            .seq = seq,
            .lane = try self.gpa.dupe(u8, options.lane),
            .run_id = if (run_id) |value| try self.gpa.dupe(u8, value) else null,
            .record_type = try self.gpa.dupe(u8, options.record_type),
            .op_kind = if (options.op_kind) |value| try self.gpa.dupe(u8, value) else null,
            .timestamp_ms = now,
            .payload_json = try self.gpa.dupe(u8, options.payload_json),
        };
    }

    pub fn findOpenOperations(self: *Repository, session_id: []const u8, lane: []const u8) ![]types.Record {
        lockMutex(&self.mutex);
        defer self.mutex.unlock();
        try self.requireSessionUnlocked(session_id);
        var pointer = try self.db.prepare("SELECT open_operation_id FROM lanes WHERE session_id = ? AND lane = ?");
        defer pointer.deinit();
        try pointer.bindAll(&.{ .{ .text = session_id }, .{ .text = lane } });
        if (try pointer.step() != .row) return error.InvalidLane;
        const operation_id = try pointer.columnText(0) orelse return self.gpa.alloc(types.Record, 0);
        var statement = try self.db.prepare(
            "SELECT seq, id, lane, run_id, type, op_kind, timestamp, payload FROM records WHERE session_id = ? AND id = ?",
        );
        defer statement.deinit();
        try statement.bindAll(&.{ .{ .text = session_id }, .{ .text = operation_id } });
        if (try statement.step() != .row) return error.InvalidEntry;
        var record = try self.parseRecordRowUnlocked(&statement);
        errdefer record.deinit(self.gpa);
        if (!std.mem.eql(u8, record.lane, lane) or !std.mem.eql(u8, record.record_type, "operation_started")) return error.InvalidEntry;
        const records = try self.gpa.alloc(types.Record, 1);
        records[0] = record;
        return records;
    }

    fn addUsageUnlocked(self: *Repository, session_id: []const u8, usage: types.Usage) !void {
        const changed = try run(&self.db, "UPDATE session_stats SET cached_tokens = cached_tokens + ?, " ++
            "uncached_tokens = uncached_tokens + ?, total_tokens = total_tokens + ?, " ++
            "cost_total = cost_total + ? WHERE session_id = ?", &.{
            .{ .float = usage.cache_read },
            .{ .float = usage.input + usage.cache_write },
            .{ .float = usage.total_tokens },
            .{ .float = usage.cost_total },
            .{ .text = session_id },
        });
        if (changed != 1) return error.SessionNotFound;
    }

    pub fn addUsage(self: *Repository, session_id: []const u8, usage: types.Usage, lease: ?*const types.WriterLease) !void {
        lockMutex(&self.mutex);
        defer self.mutex.unlock();
        try self.requireSessionUnlocked(session_id);
        const now = self.nowUnlocked();
        try self.db.beginImmediate();
        errdefer self.db.rollback();
        if (lease) |claim| try self.verifyLeaseUnlocked(session_id, claim, now);
        try self.addUsageUnlocked(session_id, usage);
        try self.db.commit();
    }

    pub fn getStats(self: *Repository, session_id: []const u8) !types.Stats {
        lockMutex(&self.mutex);
        defer self.mutex.unlock();
        try self.requireSessionUnlocked(session_id);
        var statement = try self.db.prepare(
            "SELECT message_count, cached_tokens, uncached_tokens, total_tokens, cost_total FROM session_stats WHERE session_id = ?",
        );
        defer statement.deinit();
        try statement.bind(1, .{ .text = session_id });
        if (try statement.step() != .row) return error.SessionNotFound;
        return .{
            .message_count = try statement.columnInt(0),
            .cached_tokens = try statement.columnFloat(1),
            .uncached_tokens = try statement.columnFloat(2),
            .total_tokens = try statement.columnFloat(3),
            .cost_total = try statement.columnFloat(4),
        };
    }

    fn appendFactUnlocked(
        self: *Repository,
        session_id: []const u8,
        kind: []const u8,
        key: ?[]const u8,
        value_json: ?[]const u8,
        lease: ?*const types.WriterLease,
    ) !i64 {
        if (kind.len == 0) return error.InvalidPayload;
        if (value_json) |raw| try validateJson(self.gpa, raw, false);
        const now = self.nowUnlocked();
        try self.db.beginImmediate();
        errdefer self.db.rollback();
        if (lease) |claim| try self.verifyLeaseUnlocked(session_id, claim, now);
        const seq = try self.nextSequenceUnlocked(session_id);
        var statement = try self.db.prepare("INSERT INTO facts(session_id, seq, kind, key, value) VALUES(?, ?, ?, ?, ?)");
        defer statement.deinit();
        try statement.bind(1, .{ .text = session_id });
        try statement.bind(2, .{ .integer = seq });
        try statement.bind(3, .{ .text = kind });
        try bindNullableText(&statement, 4, key);
        try bindNullableText(&statement, 5, value_json);
        _ = try statement.run();
        try self.setNextSequenceUnlocked(session_id, seq + 1);
        try self.db.commit();
        return seq;
    }

    fn parseFactRowUnlocked(self: *Repository, statement: *const ffi.Statement) !types.Fact {
        return .{
            .seq = try statement.columnInt(0),
            .kind = (try statement.columnTextAlloc(self.gpa, 1)).?,
            .key = try statement.columnTextAlloc(self.gpa, 2),
            .value_json = try statement.columnTextAlloc(self.gpa, 3),
        };
    }

    fn latestFactUnlocked(self: *Repository, session_id: []const u8, kind: []const u8, key: ?[]const u8) !?types.Fact {
        var statement = try self.db.prepare(
            "SELECT seq, kind, key, value FROM facts INDEXED BY idx_facts_session_kind_key_seq " ++
                "WHERE session_id = ? AND kind = ? AND key IS ? ORDER BY seq DESC LIMIT 1",
        );
        defer statement.deinit();
        try statement.bind(1, .{ .text = session_id });
        try statement.bind(2, .{ .text = kind });
        try bindNullableText(&statement, 3, key);
        if (try statement.step() != .row) return null;
        return @as(?types.Fact, try self.parseFactRowUnlocked(&statement));
    }

    pub fn appendFact(
        self: *Repository,
        session_id: []const u8,
        kind: []const u8,
        key: ?[]const u8,
        value_json: ?[]const u8,
        lease: ?*const types.WriterLease,
    ) !i64 {
        lockMutex(&self.mutex);
        defer self.mutex.unlock();
        try self.requireSessionUnlocked(session_id);
        return self.appendFactUnlocked(session_id, kind, key, value_json, lease);
    }

    pub fn listFacts(self: *Repository, session_id: []const u8, after_seq: ?i64, limit: ?usize) ![]types.Fact {
        lockMutex(&self.mutex);
        defer self.mutex.unlock();
        try self.requireSessionUnlocked(session_id);
        if (limit == 0) return self.gpa.alloc(types.Fact, 0);
        var statement = try self.db.prepare(
            "SELECT seq, kind, key, value FROM facts WHERE session_id = ? AND (? IS NULL OR seq > ?) ORDER BY seq LIMIT ?",
        );
        defer statement.deinit();
        try statement.bind(1, .{ .text = session_id });
        if (after_seq) |cursor| {
            try statement.bind(2, .{ .integer = cursor });
            try statement.bind(3, .{ .integer = cursor });
        } else {
            try statement.bind(2, .null);
            try statement.bind(3, .null);
        }
        try statement.bind(4, .{ .integer = if (limit) |value| @intCast(value) else -1 });
        var facts: std.ArrayList(types.Fact) = .empty;
        errdefer {
            for (facts.items) |*fact| fact.deinit(self.gpa);
            facts.deinit(self.gpa);
        }
        while (try statement.step() == .row) try facts.append(self.gpa, try self.parseFactRowUnlocked(&statement));
        return facts.toOwnedSlice(self.gpa);
    }

    pub fn getName(self: *Repository, session_id: []const u8) !?[]u8 {
        lockMutex(&self.mutex);
        defer self.mutex.unlock();
        try self.requireSessionUnlocked(session_id);
        var fact = try self.latestFactUnlocked(session_id, "name", null) orelse return null;
        defer fact.deinit(self.gpa);
        const value = fact.value_json orelse return null;
        return @as(?[]u8, try decodeJsonStringAlloc(self.gpa, value));
    }

    pub fn setName(self: *Repository, session_id: []const u8, name: ?[]const u8, lease: ?*const types.WriterLease) !void {
        lockMutex(&self.mutex);
        defer self.mutex.unlock();
        try self.requireSessionUnlocked(session_id);
        const encoded = if (name) |value| try jsonStringAlloc(self.gpa, value) else null;
        defer if (encoded) |value| self.gpa.free(value);
        _ = try self.appendFactUnlocked(session_id, "name", null, encoded, lease);
    }

    pub fn getLabel(self: *Repository, session_id: []const u8, entry_id: []const u8) !?[]u8 {
        lockMutex(&self.mutex);
        defer self.mutex.unlock();
        try self.requireSessionUnlocked(session_id);
        var fact = try self.latestFactUnlocked(session_id, "label", entry_id) orelse return null;
        defer fact.deinit(self.gpa);
        const value = fact.value_json orelse return null;
        return @as(?[]u8, try decodeJsonStringAlloc(self.gpa, value));
    }

    pub fn setLabel(
        self: *Repository,
        session_id: []const u8,
        entry_id: []const u8,
        label: ?[]const u8,
        lease: ?*const types.WriterLease,
    ) !void {
        lockMutex(&self.mutex);
        defer self.mutex.unlock();
        try self.requireSessionUnlocked(session_id);
        if (!try self.entryExistsUnlocked(session_id, entry_id)) return error.EntryNotFound;
        const encoded = if (label) |value| try jsonStringAlloc(self.gpa, value) else null;
        defer if (encoded) |value| self.gpa.free(value);
        _ = try self.appendFactUnlocked(session_id, "label", entry_id, encoded, lease);
    }

    fn readLaneMovesUnlocked(self: *Repository, session_id: []const u8, after_seq: i64, limit: ?usize) ![]types.LaneMove {
        var statement = try self.db.prepare(
            "SELECT seq, lane, leaf_id FROM lane_moves WHERE session_id = ? AND seq > ? ORDER BY seq LIMIT ?",
        );
        defer statement.deinit();
        try statement.bindAll(&.{ .{ .text = session_id }, .{ .integer = after_seq }, .{ .integer = if (limit) |value| @intCast(value) else -1 } });
        var moves: std.ArrayList(types.LaneMove) = .empty;
        errdefer {
            for (moves.items) |*move| move.deinit(self.gpa);
            moves.deinit(self.gpa);
        }
        while (try statement.step() == .row) {
            try moves.append(self.gpa, .{
                .seq = try statement.columnInt(0),
                .lane = (try statement.columnTextAlloc(self.gpa, 1)).?,
                .leaf_id = try statement.columnTextAlloc(self.gpa, 2),
            });
        }
        return moves.toOwnedSlice(self.gpa);
    }

    fn readFactsUnlocked(self: *Repository, session_id: []const u8, after_seq: i64, limit: ?usize) ![]types.Fact {
        var statement = try self.db.prepare(
            "SELECT seq, kind, key, value FROM facts WHERE session_id = ? AND seq > ? ORDER BY seq LIMIT ?",
        );
        defer statement.deinit();
        try statement.bindAll(&.{ .{ .text = session_id }, .{ .integer = after_seq }, .{ .integer = if (limit) |value| @intCast(value) else -1 } });
        var facts: std.ArrayList(types.Fact) = .empty;
        errdefer {
            for (facts.items) |*fact| fact.deinit(self.gpa);
            facts.deinit(self.gpa);
        }
        while (try statement.step() == .row) try facts.append(self.gpa, try self.parseFactRowUnlocked(&statement));
        return facts.toOwnedSlice(self.gpa);
    }

    pub fn getLog(self: *Repository, session_id: []const u8, options: types.LogOptions) ![]types.LogItem {
        lockMutex(&self.mutex);
        defer self.mutex.unlock();
        try self.requireSessionUnlocked(session_id);
        if (options.limit == 0) return self.gpa.alloc(types.LogItem, 0);
        const per_source_limit = options.limit;
        const entries = try self.findEntriesUnlocked(session_id, .{ .after_seq = options.after_seq, .order = .oldest_first, .limit = per_source_limit });
        defer self.gpa.free(entries);
        const records = try self.findRecordsUnlocked(session_id, .{ .after_seq = options.after_seq, .order = .oldest_first, .limit = per_source_limit });
        defer self.gpa.free(records);
        const moves = try self.readLaneMovesUnlocked(session_id, options.after_seq, per_source_limit);
        defer self.gpa.free(moves);
        const facts = try self.readFactsUnlocked(session_id, options.after_seq, per_source_limit);
        defer self.gpa.free(facts);

        var items: std.ArrayList(types.LogItem) = .empty;
        errdefer {
            for (items.items) |*item| item.deinit(self.gpa);
            items.deinit(self.gpa);
        }
        for (entries) |entry| try items.append(self.gpa, .{ .entry = entry });
        for (records) |record| try items.append(self.gpa, .{ .record = record });
        for (moves) |move| try items.append(self.gpa, .{ .lane = move });
        for (facts) |fact| try items.append(self.gpa, .{ .fact = fact });
        std.mem.sort(types.LogItem, items.items, {}, struct {
            fn lessThan(_: void, left: types.LogItem, right: types.LogItem) bool {
                return left.seq() < right.seq();
            }
        }.lessThan);
        if (options.limit) |limit| {
            if (items.items.len > limit) {
                for (items.items[limit..]) |*item| item.deinit(self.gpa);
                items.shrinkRetainingCapacity(limit);
            }
        }
        return items.toOwnedSlice(self.gpa);
    }

    fn rebuildBranchCacheUnlocked(self: *Repository, session_id: []const u8) !void {
        var count_statement = try self.db.prepare("SELECT COUNT(*) FROM entries WHERE session_id = ?");
        defer count_statement.deinit();
        try count_statement.bind(1, .{ .text = session_id });
        _ = try count_statement.step();
        const entry_count = try count_statement.columnInt(0);

        var leaf_statement = try self.db.prepare(
            "SELECT leaf.id FROM entries AS leaf WHERE leaf.session_id = ? AND NOT EXISTS (" ++
                "SELECT 1 FROM entries AS child WHERE child.session_id = leaf.session_id AND child.parent_id = leaf.id) " ++
                "ORDER BY leaf.seq",
        );
        defer leaf_statement.deinit();
        try leaf_statement.bind(1, .{ .text = session_id });
        var leaves: std.ArrayList([]u8) = .empty;
        defer {
            for (leaves.items) |leaf| self.gpa.free(leaf);
            leaves.deinit(self.gpa);
        }
        while (try leaf_statement.step() == .row) try leaves.append(self.gpa, (try leaf_statement.columnTextAlloc(self.gpa, 0)).?);
        if (entry_count > 0 and leaves.items.len == 0) return error.InvalidEntry;

        _ = try run(&self.db, "DELETE FROM branch_tips WHERE session_id = ?", &.{.{ .text = session_id }});
        _ = try run(&self.db, "DELETE FROM branch_entries WHERE session_id = ?", &.{.{ .text = session_id }});

        for (leaves.items) |leaf_id| {
            const branch_id = try self.generateIdUnlocked();
            defer self.gpa.free(branch_id);
            var path: std.ArrayList(types.Entry) = .empty;
            defer {
                for (path.items) |*entry| entry.deinit(self.gpa);
                path.deinit(self.gpa);
            }
            var seen: std.StringHashMapUnmanaged(void) = .empty;
            defer seen.deinit(self.gpa);
            var current = try self.gpa.dupe(u8, leaf_id);
            defer self.gpa.free(current);
            while (true) {
                const seen_result = try seen.getOrPut(self.gpa, current);
                if (seen_result.found_existing) return error.InvalidEntry;
                const entry = (try self.getEntryUnlocked(session_id, current)) orelse return error.InvalidEntry;
                try path.append(self.gpa, entry);
                const parent = entry.parent_id orelse break;
                const next = try self.gpa.dupe(u8, parent);
                self.gpa.free(current);
                current = next;
            }
            var index = path.items.len;
            while (index > 0) {
                index -= 1;
                const entry = &path.items[index];
                try self.insertBranchMembershipUnlocked(session_id, branch_id, entry.id, entry.seq, entry.entry_type, entry.custom_type);
            }
            _ = try run(&self.db, "INSERT INTO branch_tips(session_id, branch_id, tip_id) VALUES(?, ?, ?)", &.{
                .{ .text = session_id }, .{ .text = branch_id }, .{ .text = leaf_id },
            });
        }
    }

    pub fn repairBranchCache(self: *Repository, session_id: []const u8, lease: ?*const types.WriterLease) !void {
        lockMutex(&self.mutex);
        defer self.mutex.unlock();
        try self.requireSessionUnlocked(session_id);
        const now = self.nowUnlocked();
        try self.db.beginImmediate();
        errdefer self.db.rollback();
        if (lease) |claim| try self.verifyLeaseUnlocked(session_id, claim, now);
        try self.rebuildBranchCacheUnlocked(session_id);
        try self.db.commit();
    }

    pub fn search(self: *Repository, text: []const u8, options: types.SearchOptions) ![]types.SearchHit {
        lockMutex(&self.mutex);
        defer self.mutex.unlock();
        const trimmed = std.mem.trim(u8, text, " \t\r\n");
        if (trimmed.len == 0 or options.limit == 0) return self.gpa.alloc(types.SearchHit, 0);
        if (options.entry_types) |entry_types| if (entry_types.len == 0) return self.gpa.alloc(types.SearchHit, 0);
        schema.ensureSearchSchema(&self.db) catch return error.SearchUnavailable;
        const query_text = try ftsQuotedAlloc(self.gpa, trimmed);
        defer self.gpa.free(query_text);
        var statement = self.db.prepare(
            "SELECT s.id, se.id, se.timestamp, bm25(session_search_fts), " ++
                "(SELECT f.value FROM facts AS f WHERE f.session_id = s.id AND f.kind = 'name' AND f.key IS NULL " ++
                "ORDER BY f.seq DESC LIMIT 1), s.cwd, se.type " ++
                "FROM session_search_fts JOIN entries AS se ON se.rowid = session_search_fts.rowid " ++
                "JOIN sessions AS s ON s.id = se.session_id WHERE session_search_fts MATCH ? " ++
                "ORDER BY bm25(session_search_fts), se.timestamp DESC LIMIT ?",
        ) catch return error.SearchUnavailable;
        defer statement.deinit();
        try statement.bind(1, .{ .text = query_text });
        const sql_limit: i64 = if (options.entry_types == null and options.limit != null) @intCast(options.limit.?) else -1;
        try statement.bind(2, .{ .integer = sql_limit });

        var hits: std.ArrayList(types.SearchHit) = .empty;
        errdefer {
            for (hits.items) |*hit| hit.deinit(self.gpa);
            hits.deinit(self.gpa);
        }
        while ((statement.step() catch return error.SearchUnavailable) == .row) {
            const type_text = (try statement.columnText(6)).?;
            const entry_type = types.EntryType.parse(type_text) orelse return error.InvalidEntry;
            if (options.entry_types) |allowed| {
                var matched = false;
                for (allowed) |candidate| if (candidate == entry_type) {
                    matched = true;
                    break;
                };
                if (!matched) continue;
            }
            var hit = types.SearchHit{
                .session_id = (try statement.columnTextAlloc(self.gpa, 0)).?,
                .entry_id = (try statement.columnTextAlloc(self.gpa, 1)).?,
                .timestamp_ms = try statement.columnInt(2),
                .score = try statement.columnFloat(3),
                .name = null,
                .cwd = (try statement.columnTextAlloc(self.gpa, 5)).?,
            };
            errdefer hit.deinit(self.gpa);
            if (try statement.columnText(4)) |raw_name| hit.name = try decodeJsonStringAlloc(self.gpa, raw_name);
            try hits.append(self.gpa, hit);
            if (options.limit) |limit| if (hits.items.len >= limit) break;
        }
        return hits.toOwnedSlice(self.gpa);
    }

    pub fn forkSession(
        self: *Repository,
        source_id: []const u8,
        options: types.ForkOptions,
        source_lease: ?*const types.WriterLease,
    ) !types.SessionMetadata {
        lockMutex(&self.mutex);
        defer self.mutex.unlock();
        try self.requireSessionUnlocked(source_id);
        if (options.metadata_json) |raw| validateJson(self.gpa, raw, true) catch return error.InvalidMetadata;
        if (options.parent_session_id) |parent| try self.requireSessionUnlocked(parent);
        const source_metadata = try self.getSessionUnlocked(source_id);
        defer {
            var metadata = source_metadata;
            metadata.deinit(self.gpa);
        }
        const generated = if (options.id == null) try self.generateIdUnlocked() else null;
        defer if (generated) |id| self.gpa.free(id);
        const new_id = options.id orelse generated.?;
        if (try self.sessionExistsUnlocked(new_id)) return error.SessionAlreadyExists;

        var entries: []types.Entry = &.{};
        defer if (entries.len > 0) freeEntries(self.gpa, entries);
        var branch_target: ?[]u8 = null;
        defer if (branch_target) |value| self.gpa.free(value);

        var lanes: std.ArrayList(types.Lane) = .empty;
        defer {
            for (lanes.items) |*lane| lane.deinit(self.gpa);
            lanes.deinit(self.gpa);
        }

        if (options.scope == .tree) {
            entries = try self.findEntriesUnlocked(source_id, .{ .order = .oldest_first });
            var lane_statement = try self.db.prepare(
                "SELECT lane, leaf_id, open_operation_id FROM lanes WHERE session_id = ? ORDER BY lane",
            );
            defer lane_statement.deinit();
            try lane_statement.bind(1, .{ .text = source_id });
            while (try lane_statement.step() == .row) {
                try lanes.append(self.gpa, .{
                    .name = (try lane_statement.columnTextAlloc(self.gpa, 0)).?,
                    .leaf_id = try lane_statement.columnTextAlloc(self.gpa, 1),
                    .open_operation_id = null,
                });
            }
        } else {
            const main_leaf = try self.laneHeadUnlocked(source_id, "main");
            defer if (main_leaf) |value| self.gpa.free(value);
            const selected_id: ?[]const u8 = options.entry_id orelse if (main_leaf) |value| value else null;
            if (selected_id) |selected| {
                var target = (try self.getEntryUnlocked(source_id, selected)) orelse return error.EntryNotFound;
                defer target.deinit(self.gpa);
                if (target.entry_type != .message) return error.InvalidForkTarget;
                const position = options.position orelse if (options.entry_id == null) types.ForkPosition.at else types.ForkPosition.before;
                branch_target = switch (position) {
                    .at => try self.gpa.dupe(u8, target.id),
                    .before => if (target.parent_id) |parent| try self.gpa.dupe(u8, parent) else null,
                };
            }
            if (branch_target) |leaf| {
                var path: std.ArrayList(types.Entry) = .empty;
                defer {
                    for (path.items) |*entry| entry.deinit(self.gpa);
                    path.deinit(self.gpa);
                }
                var seen: std.StringHashMapUnmanaged(void) = .empty;
                defer seen.deinit(self.gpa);
                var current = try self.gpa.dupe(u8, leaf);
                defer self.gpa.free(current);
                while (true) {
                    const found = try seen.getOrPut(self.gpa, current);
                    if (found.found_existing) return error.InvalidEntry;
                    const entry = (try self.getEntryUnlocked(source_id, current)) orelse return error.InvalidEntry;
                    try path.append(self.gpa, entry);
                    const parent = entry.parent_id orelse break;
                    const next = try self.gpa.dupe(u8, parent);
                    self.gpa.free(current);
                    current = next;
                }
                const copied = try self.gpa.alloc(types.Entry, path.items.len);
                errdefer self.gpa.free(copied);
                var copied_count: usize = 0;
                errdefer for (copied[0..copied_count]) |*entry| entry.deinit(self.gpa);
                var index = path.items.len;
                while (index > 0) {
                    index -= 1;
                    copied[copied_count] = try cloneEntry(self.gpa, &path.items[index]);
                    copied_count += 1;
                }
                entries = copied;
            }
            try lanes.append(self.gpa, .{
                .name = try self.gpa.dupe(u8, "main"),
                .leaf_id = if (branch_target) |value| try self.gpa.dupe(u8, value) else null,
                .open_operation_id = null,
            });
        }

        var copied_ids: std.StringHashMapUnmanaged(void) = .empty;
        defer copied_ids.deinit(self.gpa);
        for (entries) |entry| try copied_ids.put(self.gpa, entry.id, {});

        const name_fact = try self.latestFactUnlocked(source_id, "name", null);
        defer if (name_fact) |value| {
            var copy = value;
            copy.deinit(self.gpa);
        };
        const LabelCopy = struct { key: []u8, value: []u8 };
        var labels: std.ArrayList(LabelCopy) = .empty;
        defer {
            for (labels.items) |label| {
                self.gpa.free(label.key);
                self.gpa.free(label.value);
            }
            labels.deinit(self.gpa);
        }
        var label_statement = try self.db.prepare(
            "SELECT f.key, f.value FROM facts AS f INDEXED BY idx_facts_session_kind_key_seq " ++
                "WHERE f.session_id = ? AND f.kind = 'label' AND f.key IS NOT NULL AND f.value IS NOT NULL " ++
                "AND f.seq = (SELECT MAX(candidate.seq) FROM facts AS candidate INDEXED BY idx_facts_session_kind_key_seq " ++
                "WHERE candidate.session_id = f.session_id AND candidate.kind = f.kind AND candidate.key IS f.key) ORDER BY f.key",
        );
        defer label_statement.deinit();
        try label_statement.bind(1, .{ .text = source_id });
        while (try label_statement.step() == .row) {
            const key = (try label_statement.columnText(0)).?;
            if (options.scope == .branch and !copied_ids.contains(key)) continue;
            try labels.append(self.gpa, .{
                .key = try self.gpa.dupe(u8, key),
                .value = (try label_statement.columnTextAlloc(self.gpa, 1)).?,
            });
        }

        const created_at = self.nowUnlocked();
        try self.db.beginImmediate();
        errdefer self.db.rollback();
        if (source_lease) |claim| try self.verifyLeaseUnlocked(source_id, claim, created_at);
        var insert_session = try self.db.prepare(
            "INSERT INTO sessions(id, created_at, cwd, parent_session_id, metadata) VALUES(?, ?, ?, ?, ?)",
        );
        defer insert_session.deinit();
        try insert_session.bind(1, .{ .text = new_id });
        try insert_session.bind(2, .{ .integer = created_at });
        try insert_session.bind(3, .{ .text = options.cwd });
        try bindNullableText(&insert_session, 4, options.parent_session_id orelse source_id);
        try bindNullableText(&insert_session, 5, options.metadata_json orelse source_metadata.metadata_json);
        _ = insert_session.run() catch |err| switch (err) {
            error.Constraint => return error.SessionAlreadyExists,
            else => return err,
        };
        _ = try run(&self.db, "INSERT INTO session_sequences(session_id, next_seq) VALUES(?, 1)", &.{.{ .text = new_id }});
        var message_count: i64 = 0;
        for (entries) |entry| if (entry.entry_type == .message) {
            message_count += 1;
        };
        _ = try run(
            &self.db,
            "INSERT INTO session_stats(session_id, message_count, cached_tokens, uncached_tokens, total_tokens, cost_total) VALUES(?, ?, 0, 0, 0, 0)",
            &.{ .{ .text = new_id }, .{ .integer = message_count } },
        );

        var next_seq: i64 = 1;
        for (entries) |entry| {
            var insert_entry = try self.db.prepare(
                "INSERT INTO entries(session_id, seq, id, parent_id, type, timestamp, payload) VALUES(?, ?, ?, ?, ?, ?, ?)",
            );
            defer insert_entry.deinit();
            try insert_entry.bind(1, .{ .text = new_id });
            try insert_entry.bind(2, .{ .integer = next_seq });
            try insert_entry.bind(3, .{ .text = entry.id });
            try bindNullableText(&insert_entry, 4, entry.parent_id);
            try insert_entry.bind(5, .{ .text = entry.entry_type.wireName() });
            try insert_entry.bind(6, .{ .integer = entry.timestamp_ms });
            try insert_entry.bind(7, .{ .text = entry.payload_json });
            _ = try insert_entry.run();
            next_seq += 1;
        }

        if (options.scope == .tree) {
            for (lanes.items) |lane| {
                _ = try run(
                    &self.db,
                    "INSERT INTO lanes(session_id, lane, leaf_id, open_operation_id) VALUES(?, ?, ?, NULL)",
                    &.{ .{ .text = new_id }, .{ .text = lane.name }, if (lane.leaf_id) |leaf| .{ .text = leaf } else .null },
                );
                _ = try run(
                    &self.db,
                    "INSERT INTO lane_moves(session_id, seq, lane, leaf_id) VALUES(?, ?, ?, ?)",
                    &.{ .{ .text = new_id }, .{ .integer = next_seq }, .{ .text = lane.name }, if (lane.leaf_id) |leaf| .{ .text = leaf } else .null },
                );
                next_seq += 1;
            }
        } else {
            const leaf_value: ffi.Value = if (branch_target) |leaf| .{ .text = leaf } else .null;
            _ = try run(
                &self.db,
                "INSERT INTO lanes(session_id, lane, leaf_id, open_operation_id) VALUES(?, 'main', ?, NULL)",
                &.{ .{ .text = new_id }, leaf_value },
            );
        }

        if (name_fact) |fact| if (fact.value_json) |value| {
            _ = try run(&self.db, "INSERT INTO facts(session_id, seq, kind, key, value) VALUES(?, ?, 'name', NULL, ?)", &.{
                .{ .text = new_id }, .{ .integer = next_seq }, .{ .text = value },
            });
            next_seq += 1;
        };
        for (labels.items) |label| {
            _ = try run(&self.db, "INSERT INTO facts(session_id, seq, kind, key, value) VALUES(?, ?, 'label', ?, ?)", &.{
                .{ .text = new_id }, .{ .integer = next_seq }, .{ .text = label.key }, .{ .text = label.value },
            });
            next_seq += 1;
        }
        try self.setNextSequenceUnlocked(new_id, next_seq);
        try self.rebuildBranchCacheUnlocked(new_id);
        try self.db.commit();
        return self.getSessionUnlocked(new_id);
    }
};

fn requireRepositoryIntegrationTests() !void {
    const value = std.process.Environ.getAlloc(
        std.testing.environ,
        std.testing.allocator,
        "PI_SQLITE_REPOSITORY_TESTS",
    ) catch |err| switch (err) {
        error.EnvironmentVariableMissing => return,
        else => return err,
    };
    defer std.testing.allocator.free(value);
    if (std.mem.eql(u8, value, "0")) return error.SkipZigTest;
}

fn deinitLanesForTest(gpa: std.mem.Allocator, lanes: []types.Lane) void {
    for (lanes) |*lane| lane.deinit(gpa);
    gpa.free(lanes);
}

fn deinitFactsForTest(gpa: std.mem.Allocator, facts: []types.Fact) void {
    for (facts) |*fact| fact.deinit(gpa);
    gpa.free(facts);
}

fn deinitHitsForTest(gpa: std.mem.Allocator, hits: []types.SearchHit) void {
    for (hits) |*hit| hit.deinit(gpa);
    gpa.free(hits);
}

fn deinitLogForTest(gpa: std.mem.Allocator, log: []types.LogItem) void {
    for (log) |*item| item.deinit(gpa);
    gpa.free(log);
}

test "SQLite repository sessions facts stats and durable reopen" {
    try requireRepositoryIntegrationTests();
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buf: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const root_len = try tmp.dir.realPath(io, &path_buf);
    const path = try std.fs.path.join(gpa, &.{ path_buf[0..root_len], "sessions.sqlite" });
    defer gpa.free(path);

    {
        var repo = try Repository.open(gpa, io, path);
        defer repo.deinit();
        var metadata = try repo.createSession(.{ .id = "session-a", .cwd = "/project", .metadata_json = "{\"team\":\"pi\"}" });
        defer metadata.deinit(gpa);
        try repo.setName("session-a", "Native SQLite", null);
        var entry = try repo.appendEntry("session-a", "main", .{
            .id = "entry-a",
            .entry_type = .message,
            .payload_json = "{\"message\":{\"role\":\"user\",\"content\":\"needle alpha\"}}",
        }, null);
        defer entry.deinit(gpa);
        try repo.setLabel("session-a", "entry-a", "important", null);
        var usage_record = try repo.appendRecord("session-a", .{
            .id = "usage-a",
            .record_type = "usage",
            .payload_json = "{\"usage\":{\"input\":4,\"cacheRead\":2,\"cacheWrite\":1,\"totalTokens\":8,\"cost\":{\"total\":0.25}}}",
        }, null);
        defer usage_record.deinit(gpa);
        const stats = try repo.getStats("session-a");
        try std.testing.expectEqual(@as(i64, 1), stats.message_count);
        try std.testing.expectApproxEqAbs(@as(f64, 2), stats.cached_tokens, 0.0001);
        try std.testing.expectApproxEqAbs(@as(f64, 5), stats.uncached_tokens, 0.0001);
        try std.testing.expectApproxEqAbs(@as(f64, 8), stats.total_tokens, 0.0001);
        try std.testing.expectApproxEqAbs(@as(f64, 0.25), stats.cost_total, 0.0001);
        const name = (try repo.getName("session-a")).?;
        defer gpa.free(name);
        try std.testing.expectEqualStrings("Native SQLite", name);
        const label = (try repo.getLabel("session-a", "entry-a")).?;
        defer gpa.free(label);
        try std.testing.expectEqualStrings("important", label);
    }

    var reopened = try Repository.open(gpa, io, path);
    defer reopened.deinit();
    const sessions = try reopened.listSessions("/project");
    defer {
        for (sessions) |*metadata| metadata.deinit(gpa);
        gpa.free(sessions);
    }
    try std.testing.expectEqual(@as(usize, 1), sessions.len);
    try std.testing.expectEqualStrings("session-a", sessions[0].id);
    try std.testing.expectEqualStrings("Native SQLite", sessions[0].name.?);
    try std.testing.expect(try reopened.deleteSession("session-a"));
    try std.testing.expect(!try reopened.deleteSession("session-a"));
}

test "SQLite repository branch queries lanes custom types and cache repair" {
    try requireRepositoryIntegrationTests();
    const gpa = std.testing.allocator;
    var repo = try Repository.open(gpa, std.testing.io, ":memory:");
    defer repo.deinit();
    var metadata = try repo.createSession(.{ .id = "branch-session", .cwd = "/" });
    defer metadata.deinit(gpa);
    var root = try repo.appendEntry("branch-session", "main", .{ .id = "root", .entry_type = .message, .payload_json = "{\"message\":{}}" }, null);
    defer root.deinit(gpa);
    var left = try repo.appendEntry("branch-session", "main", .{ .id = "left", .entry_type = .message, .payload_json = "{\"message\":{}}" }, null);
    defer left.deinit(gpa);
    try repo.createLane("branch-session", "side", "root", null);
    var right = try repo.appendEntry("branch-session", "side", .{
        .id = "right",
        .entry_type = .custom,
        .payload_json = "{\"customType\":\"marker\",\"data\":1}",
    }, null);
    defer right.deinit(gpa);

    const left_path = try repo.findEntriesOnBranch("branch-session", "left", .{ .order = .oldest_first });
    defer freeEntries(gpa, left_path);
    try std.testing.expectEqual(@as(usize, 2), left_path.len);
    try std.testing.expectEqualStrings("root", left_path[0].id);
    try std.testing.expectEqualStrings("left", left_path[1].id);
    const right_path = try repo.findEntriesOnBranch("branch-session", "right", .{ .order = .newest_first, .stop_at_id = "root" });
    defer freeEntries(gpa, right_path);
    try std.testing.expectEqual(@as(usize, 2), right_path.len);
    try std.testing.expectEqualStrings("right", right_path[0].id);
    try std.testing.expectEqualStrings("root", right_path[1].id);
    const customs = try repo.findEntries("branch-session", .{ .custom_type = "marker" });
    defer freeEntries(gpa, customs);
    try std.testing.expectEqual(@as(usize, 1), customs.len);
    try std.testing.expectEqualStrings("right", customs[0].id);

    _ = try run(&repo.db, "DELETE FROM branch_entries WHERE session_id = ?", &.{.{ .text = "branch-session" }});
    _ = try run(&repo.db, "DELETE FROM branch_tips WHERE session_id = ?", &.{.{ .text = "branch-session" }});
    try repo.repairBranchCache("branch-session", null);
    const repaired = try repo.findEntries("branch-session", .{ .custom_type = "marker" });
    defer freeEntries(gpa, repaired);
    try std.testing.expectEqual(@as(usize, 1), repaired.len);
    const lanes = try repo.listLanes("branch-session");
    defer deinitLanesForTest(gpa, lanes);
    try std.testing.expectEqual(@as(usize, 2), lanes.len);
}

test "SQLite writer leases fence expired owners transactionally" {
    try requireRepositoryIntegrationTests();
    const gpa = std.testing.allocator;
    var repo = try Repository.open(gpa, std.testing.io, ":memory:");
    defer repo.deinit();
    var metadata = try repo.createSession(.{ .id = "lease-session", .cwd = "/" });
    defer metadata.deinit(gpa);
    const base: i64 = 2_000_000_000_000;
    var first = (try repo.acquireWriterLease("lease-session", "owner-a", base, 100)).?;
    defer first.deinit(gpa);
    try std.testing.expect((try repo.acquireWriterLease("lease-session", "owner-b", base + 50, 100)) == null);
    var second = (try repo.acquireWriterLease("lease-session", "owner-b", base + 100, 100)).?;
    defer second.deinit(gpa);
    try std.testing.expect(second.fence > first.fence);
    try std.testing.expectError(error.LostWriterLease, repo.appendEntry("lease-session", "main", .{
        .id = "stale",
        .timestamp_ms = base + 101,
        .entry_type = .message,
        .payload_json = "{\"message\":{}}",
    }, &first));
    var committed = try repo.appendEntry("lease-session", "main", .{
        .id = "fresh",
        .timestamp_ms = base + 101,
        .entry_type = .message,
        .payload_json = "{\"message\":{}}",
    }, &second);
    defer committed.deinit(gpa);
    try std.testing.expect(try repo.renewWriterLease(&second, base + 120, 200));
    try std.testing.expect(try repo.releaseWriterLease(&second));
    try std.testing.expect(!try repo.releaseWriterLease(&second));
}

test "SQLite records track open operations usage and merged log order" {
    try requireRepositoryIntegrationTests();
    const gpa = std.testing.allocator;
    var repo = try Repository.open(gpa, std.testing.io, ":memory:");
    defer repo.deinit();
    var metadata = try repo.createSession(.{ .id = "record-session", .cwd = "/" });
    defer metadata.deinit(gpa);
    var entry = try repo.appendEntry("record-session", "main", .{ .id = "message", .entry_type = .message, .payload_json = "{\"message\":{}}" }, null);
    defer entry.deinit(gpa);
    var started = try repo.appendRecord("record-session", .{
        .id = "run-1",
        .record_type = "operation_started",
        .op_kind = "turn",
        .payload_json = "{\"type\":\"operation_started\"}",
    }, null);
    defer started.deinit(gpa);
    try std.testing.expectError(error.OpenOperation, repo.appendRecord("record-session", .{
        .id = "run-2",
        .record_type = "operation_started",
        .payload_json = "{\"type\":\"operation_started\"}",
    }, null));
    const open = try repo.findOpenOperations("record-session", "main");
    defer freeRecords(gpa, open);
    try std.testing.expectEqual(@as(usize, 1), open.len);
    try std.testing.expectEqualStrings("run-1", open[0].id);
    var finished = try repo.appendRecord("record-session", .{
        .id = "finish-1",
        .run_id = "run-1",
        .record_type = "operation_finished",
        .payload_json = "{\"type\":\"operation_finished\",\"runId\":\"run-1\"}",
    }, null);
    defer finished.deinit(gpa);
    const after = try repo.findOpenOperations("record-session", "main");
    defer freeRecords(gpa, after);
    try std.testing.expectEqual(@as(usize, 0), after.len);
    try repo.setName("record-session", "recorded", null);
    const log = try repo.getLog("record-session", .{});
    defer deinitLogForTest(gpa, log);
    try std.testing.expect(log.len >= 4);
    for (log[1..], 1..) |item, index| try std.testing.expect(log[index - 1].seq() < item.seq());
}

test "SQLite FTS search indexes existing and newly inserted entries" {
    try requireRepositoryIntegrationTests();
    const gpa = std.testing.allocator;
    var repo = try Repository.open(gpa, std.testing.io, ":memory:");
    defer repo.deinit();
    var metadata = try repo.createSession(.{ .id = "search-session", .cwd = "/search" });
    defer metadata.deinit(gpa);
    try repo.setName("search-session", "Searchable", null);
    var first = try repo.appendEntry("search-session", "main", .{
        .id = "before-fts",
        .entry_type = .message,
        .payload_json = "{\"message\":{\"content\":\"needle constellation\"}}",
    }, null);
    defer first.deinit(gpa);
    const initial = try repo.search("needle", .{});
    defer deinitHitsForTest(gpa, initial);
    try std.testing.expectEqual(@as(usize, 1), initial.len);
    try std.testing.expectEqualStrings("Searchable", initial[0].name.?);
    var second = try repo.appendEntry("search-session", "main", .{
        .id = "after-fts",
        .entry_type = .custom,
        .payload_json = "{\"customType\":\"note\",\"text\":\"needle nebula\"}",
    }, null);
    defer second.deinit(gpa);
    const allowed = [_]types.EntryType{.message};
    const filtered = try repo.search("needle", .{ .entry_types = &allowed, .limit = 10 });
    defer deinitHitsForTest(gpa, filtered);
    try std.testing.expectEqual(@as(usize, 1), filtered.len);
    try std.testing.expectEqualStrings("before-fts", filtered[0].entry_id);
}

test "SQLite branch and tree forks preserve canonical scope facts and lanes" {
    try requireRepositoryIntegrationTests();
    const gpa = std.testing.allocator;
    var repo = try Repository.open(gpa, std.testing.io, ":memory:");
    defer repo.deinit();
    var source = try repo.createSession(.{ .id = "source", .cwd = "/src", .metadata_json = "{\"origin\":true}" });
    defer source.deinit(gpa);
    try repo.setName("source", "Fork Source", null);
    var first = try repo.appendEntry("source", "main", .{ .id = "m1", .entry_type = .message, .payload_json = "{\"message\":{}}" }, null);
    defer first.deinit(gpa);
    try repo.setLabel("source", "m1", "keep", null);
    var second = try repo.appendEntry("source", "main", .{ .id = "m2", .entry_type = .message, .payload_json = "{\"message\":{}}" }, null);
    defer second.deinit(gpa);
    try repo.setLabel("source", "m2", "drop-on-before", null);
    try repo.createLane("source", "side", "m1", null);
    var side = try repo.appendEntry("source", "side", .{ .id = "c1", .entry_type = .custom, .payload_json = "{\"customType\":\"side\"}" }, null);
    defer side.deinit(gpa);

    var branch = try repo.forkSession("source", .{ .id = "branch-fork", .cwd = "/branch", .entry_id = "m2", .position = .before }, null);
    defer branch.deinit(gpa);
    const branch_entries = try repo.findEntries("branch-fork", .{ .order = .oldest_first });
    defer freeEntries(gpa, branch_entries);
    try std.testing.expectEqual(@as(usize, 1), branch_entries.len);
    try std.testing.expectEqualStrings("m1", branch_entries[0].id);
    const branch_name = (try repo.getName("branch-fork")).?;
    defer gpa.free(branch_name);
    try std.testing.expectEqualStrings("Fork Source", branch_name);
    const kept_label = (try repo.getLabel("branch-fork", "m1")).?;
    defer gpa.free(kept_label);
    try std.testing.expectEqualStrings("keep", kept_label);
    try std.testing.expect((try repo.getLabel("branch-fork", "m2")) == null);

    var tree = try repo.forkSession("source", .{ .id = "tree-fork", .cwd = "/tree", .scope = .tree }, null);
    defer tree.deinit(gpa);
    const tree_entries = try repo.findEntries("tree-fork", .{ .order = .oldest_first });
    defer freeEntries(gpa, tree_entries);
    try std.testing.expectEqual(@as(usize, 3), tree_entries.len);
    const tree_lanes = try repo.listLanes("tree-fork");
    defer deinitLanesForTest(gpa, tree_lanes);
    try std.testing.expectEqual(@as(usize, 2), tree_lanes.len);
    try std.testing.expectEqualStrings("source", tree.parent_session_id.?);
}
