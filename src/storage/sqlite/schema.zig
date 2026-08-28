//! Schema and migrations for the canonical SQLite session repository.
const std = @import("std");
const ffi = @import("ffi.zig");

pub const migration_id = "001_initial.sql";

pub const initial_schema =
    \\CREATE TABLE IF NOT EXISTS sessions (
    \\  id TEXT PRIMARY KEY,
    \\  created_at INTEGER NOT NULL,
    \\  cwd TEXT NOT NULL,
    \\  parent_session_id TEXT NULL,
    \\  metadata TEXT NULL
    \\) WITHOUT ROWID;
    \\CREATE INDEX IF NOT EXISTS idx_sessions_created_at ON sessions(created_at DESC);
    \\CREATE INDEX IF NOT EXISTS idx_sessions_cwd_created_at ON sessions(cwd, created_at DESC);
    \\CREATE TABLE IF NOT EXISTS entries (
    \\  session_id TEXT NOT NULL,
    \\  seq INTEGER NOT NULL,
    \\  id TEXT NOT NULL,
    \\  parent_id TEXT NULL,
    \\  type TEXT NOT NULL,
    \\  timestamp INTEGER NOT NULL,
    \\  payload TEXT NOT NULL,
    \\  PRIMARY KEY (session_id, id),
    \\  UNIQUE (session_id, seq)
    \\);
    \\CREATE INDEX IF NOT EXISTS idx_entries_session_parent ON entries(session_id, parent_id);
    \\CREATE INDEX IF NOT EXISTS idx_entries_session_type_seq ON entries(session_id, type, seq);
    \\CREATE TABLE IF NOT EXISTS session_sequences (
    \\  session_id TEXT PRIMARY KEY,
    \\  next_seq INTEGER NOT NULL
    \\) WITHOUT ROWID;
    \\CREATE TABLE IF NOT EXISTS session_stats (
    \\  session_id TEXT PRIMARY KEY,
    \\  message_count INTEGER NOT NULL,
    \\  cached_tokens REAL NOT NULL,
    \\  uncached_tokens REAL NOT NULL,
    \\  total_tokens REAL NOT NULL,
    \\  cost_total REAL NOT NULL
    \\) WITHOUT ROWID;
    \\CREATE TABLE IF NOT EXISTS branch_entries (
    \\  session_id TEXT NOT NULL,
    \\  branch_id TEXT NOT NULL,
    \\  entry_id TEXT NOT NULL,
    \\  entry_seq INTEGER NOT NULL,
    \\  entry_type TEXT NULL,
    \\  custom_type TEXT NULL,
    \\  PRIMARY KEY (session_id, branch_id, entry_id)
    \\) WITHOUT ROWID;
    \\CREATE INDEX IF NOT EXISTS idx_branch_entries_session_branch_seq ON branch_entries(session_id, branch_id, entry_seq);
    \\CREATE INDEX IF NOT EXISTS idx_branch_entries_session_entry ON branch_entries(session_id, entry_id, branch_id, entry_seq);
    \\CREATE INDEX IF NOT EXISTS idx_branch_entries_session_branch_type_seq ON branch_entries(session_id, branch_id, entry_type, entry_seq);
    \\CREATE INDEX IF NOT EXISTS idx_branch_entries_session_branch_custom_seq ON branch_entries(session_id, branch_id, custom_type, entry_seq);
    \\CREATE TABLE IF NOT EXISTS lanes (
    \\  session_id TEXT NOT NULL,
    \\  lane TEXT NOT NULL,
    \\  leaf_id TEXT NULL,
    \\  open_operation_id TEXT NULL,
    \\  PRIMARY KEY (session_id, lane)
    \\) WITHOUT ROWID;
    \\CREATE TABLE IF NOT EXISTS records (
    \\  session_id TEXT NOT NULL,
    \\  seq INTEGER NOT NULL,
    \\  id TEXT NOT NULL,
    \\  lane TEXT NOT NULL,
    \\  run_id TEXT NULL,
    \\  type TEXT NOT NULL,
    \\  op_kind TEXT NULL,
    \\  timestamp INTEGER NOT NULL,
    \\  payload TEXT NOT NULL,
    \\  PRIMARY KEY (session_id, id),
    \\  UNIQUE (session_id, seq)
    \\) WITHOUT ROWID;
    \\CREATE INDEX IF NOT EXISTS idx_records_session_lane_seq ON records(session_id, lane, seq);
    \\CREATE INDEX IF NOT EXISTS idx_records_session_type_seq ON records(session_id, type, seq);
    \\CREATE INDEX IF NOT EXISTS idx_records_session_type_op_kind_seq ON records(session_id, type, op_kind, seq);
    \\CREATE INDEX IF NOT EXISTS idx_records_session_lane_type_seq ON records(session_id, lane, type, seq);
    \\CREATE INDEX IF NOT EXISTS idx_records_session_lane_type_op_kind_seq ON records(session_id, lane, type, op_kind, seq);
    \\CREATE INDEX IF NOT EXISTS idx_records_session_run_id_seq ON records(session_id, run_id, seq);
    \\CREATE TABLE IF NOT EXISTS lane_moves (
    \\  session_id TEXT NOT NULL,
    \\  seq INTEGER NOT NULL,
    \\  lane TEXT NOT NULL,
    \\  leaf_id TEXT NULL,
    \\  PRIMARY KEY (session_id, seq)
    \\) WITHOUT ROWID;
    \\CREATE TABLE IF NOT EXISTS facts (
    \\  session_id TEXT NOT NULL,
    \\  seq INTEGER NOT NULL,
    \\  kind TEXT NOT NULL,
    \\  key TEXT NULL,
    \\  value TEXT NULL,
    \\  PRIMARY KEY (session_id, seq)
    \\) WITHOUT ROWID;
    \\CREATE INDEX IF NOT EXISTS idx_facts_session_kind_key_seq ON facts(session_id, kind, key, seq);
    \\CREATE TABLE IF NOT EXISTS branch_tips (
    \\  session_id TEXT NOT NULL,
    \\  branch_id TEXT NOT NULL,
    \\  tip_id TEXT NOT NULL,
    \\  PRIMARY KEY (session_id, tip_id),
    \\  UNIQUE (session_id, branch_id)
    \\) WITHOUT ROWID;
    \\CREATE TABLE IF NOT EXISTS writer_leases (
    \\  session_id TEXT PRIMARY KEY,
    \\  owner_id TEXT NOT NULL,
    \\  fence INTEGER NOT NULL,
    \\  expires_at_ms INTEGER NOT NULL
    \\) WITHOUT ROWID;
;

pub fn configure(db: *ffi.Database) !void {
    try db.exec("PRAGMA journal_mode=WAL");
    try db.exec("PRAGMA synchronous=FULL");
    try db.exec("PRAGMA foreign_keys=ON");
    try db.busyTimeout(5000);
}

pub fn applyMigrations(db: *ffi.Database) !void {
    try db.exec(
        \\CREATE TABLE IF NOT EXISTS migrations (
        \\  id TEXT PRIMARY KEY,
        \\  applied_at TEXT NOT NULL
        \\) WITHOUT ROWID;
    );

    var check = try db.prepare("SELECT 1 FROM migrations WHERE id = ? LIMIT 1");
    defer check.deinit();
    try check.bind(1, .{ .text = migration_id });
    if (try check.step() == .row) return;

    try db.beginImmediate();
    errdefer db.rollback();
    try db.exec(initial_schema);
    var insert = try db.prepare("INSERT INTO migrations(id, applied_at) VALUES(?, strftime('%Y-%m-%dT%H:%M:%fZ', 'now'))");
    defer insert.deinit();
    try insert.bind(1, .{ .text = migration_id });
    _ = try insert.run();
    try db.commit();
}

pub fn tableExists(db: *ffi.Database, name: []const u8) !bool {
    var stmt = try db.prepare("SELECT 1 FROM sqlite_master WHERE (type = 'table' OR type = 'view') AND name = ? LIMIT 1");
    defer stmt.deinit();
    try stmt.bind(1, .{ .text = name });
    return (try stmt.step()) == .row;
}

/// Add the co-located FTS5 index used by the original session search package.
/// Trigram tokenization gives substring behavior; distributions without the
/// trigram tokenizer fall back to Unicode word search while retaining the same
/// triggers and API.
pub fn ensureSearchSchema(db: *ffi.Database) !void {
    if (try tableExists(db, "session_search_fts")) return;

    const trigram =
        \\CREATE VIRTUAL TABLE session_search_fts USING fts5(
        \\  payload,
        \\  content = 'entries',
        \\  content_rowid = 'rowid',
        \\  tokenize = 'trigram remove_diacritics 1'
        \\);
    ;
    db.exec(trigram) catch |err| switch (err) {
        error.SqliteError => try db.exec(
            \\CREATE VIRTUAL TABLE session_search_fts USING fts5(
            \\  payload,
            \\  content = 'entries',
            \\  content_rowid = 'rowid',
            \\  tokenize = 'unicode61 remove_diacritics 2'
            \\);
        ),
        else => return err,
    };

    try db.exec(
        \\CREATE TRIGGER IF NOT EXISTS session_search_fts_ai AFTER INSERT ON entries BEGIN
        \\  INSERT INTO session_search_fts(rowid, payload) VALUES (new.rowid, new.payload);
        \\END;
        \\CREATE TRIGGER IF NOT EXISTS session_search_fts_ad AFTER DELETE ON entries BEGIN
        \\  INSERT INTO session_search_fts(session_search_fts, rowid, payload) VALUES('delete', old.rowid, old.payload);
        \\END;
        \\CREATE TRIGGER IF NOT EXISTS session_search_fts_au AFTER UPDATE OF payload ON entries BEGIN
        \\  INSERT INTO session_search_fts(session_search_fts, rowid, payload) VALUES('delete', old.rowid, old.payload);
        \\  INSERT INTO session_search_fts(rowid, payload) VALUES (new.rowid, new.payload);
        \\END;
    );
    try db.exec("INSERT INTO session_search_fts(session_search_fts) VALUES('rebuild')");
}

test "SQLite schema applies idempotently and exposes canonical tables" {
    const gpa = std.testing.allocator;
    var db = try ffi.Database.open(gpa, ":memory:");
    defer db.deinit();
    try configure(&db);
    try applyMigrations(&db);
    try applyMigrations(&db);
    try std.testing.expect(try tableExists(&db, "sessions"));
    try std.testing.expect(try tableExists(&db, "entries"));
    try std.testing.expect(try tableExists(&db, "writer_leases"));
    try std.testing.expect(try tableExists(&db, "branch_entries"));

    var count = try db.prepare("SELECT COUNT(*) FROM migrations");
    defer count.deinit();
    try std.testing.expectEqual(ffi.Step.row, try count.step());
    try std.testing.expectEqual(@as(i64, 1), try count.columnInt(0));
}

test "SQLite search schema creates triggers and indexes existing entries" {
    const gpa = std.testing.allocator;
    var db = try ffi.Database.open(gpa, ":memory:");
    defer db.deinit();
    try applyMigrations(&db);
    try db.exec("INSERT INTO sessions VALUES('s', 1, '/', NULL, NULL)");
    try db.exec("INSERT INTO entries VALUES('s', 1, 'e', NULL, 'message', 1, '{\"message\":\"needle phrase\"}')");
    try ensureSearchSchema(&db);
    try ensureSearchSchema(&db);
    try std.testing.expect(try tableExists(&db, "session_search_fts"));

    var query = try db.prepare("SELECT COUNT(*) FROM session_search_fts WHERE session_search_fts MATCH ?");
    defer query.deinit();
    try query.bind(1, .{ .text = "needle" });
    try std.testing.expectEqual(ffi.Step.row, try query.step());
    try std.testing.expectEqual(@as(i64, 1), try query.columnInt(0));
}
