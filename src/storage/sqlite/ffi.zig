//! Dependency-free binding to SQLite's stable C ABI.
const std = @import("std");

const sqlite3 = opaque {};
const sqlite3_stmt = opaque {};

extern fn sqlite3_open_v2(filename: [*:0]const u8, pp_db: *?*sqlite3, flags: c_int, vfs: ?[*:0]const u8) c_int;
extern fn sqlite3_close_v2(db: ?*sqlite3) c_int;
extern fn sqlite3_errmsg(db: ?*sqlite3) [*:0]const u8;
extern fn sqlite3_extended_errcode(db: ?*sqlite3) c_int;
extern fn sqlite3_exec(db: ?*sqlite3, sql: [*:0]const u8, callback: ?*const anyopaque, context: ?*anyopaque, errmsg: ?*?[*:0]u8) c_int;
extern fn sqlite3_free(value: ?*anyopaque) void;
extern fn sqlite3_prepare_v2(db: ?*sqlite3, sql: [*]const u8, byte_count: c_int, statement: *?*sqlite3_stmt, tail: ?*?[*]const u8) c_int;
extern fn sqlite3_finalize(statement: ?*sqlite3_stmt) c_int;
extern fn sqlite3_reset(statement: ?*sqlite3_stmt) c_int;
extern fn sqlite3_clear_bindings(statement: ?*sqlite3_stmt) c_int;
extern fn sqlite3_step(statement: ?*sqlite3_stmt) c_int;
extern fn sqlite3_bind_parameter_count(statement: ?*sqlite3_stmt) c_int;
extern fn sqlite3_bind_null(statement: ?*sqlite3_stmt, index: c_int) c_int;
extern fn sqlite3_bind_int64(statement: ?*sqlite3_stmt, index: c_int, value: i64) c_int;
extern fn sqlite3_bind_double(statement: ?*sqlite3_stmt, index: c_int, value: f64) c_int;
extern fn sqlite3_bind_text(statement: ?*sqlite3_stmt, index: c_int, value: [*]const u8, byte_count: c_int, destructor: ?*const anyopaque) c_int;
extern fn sqlite3_bind_blob(statement: ?*sqlite3_stmt, index: c_int, value: ?*const anyopaque, byte_count: c_int, destructor: ?*const anyopaque) c_int;
extern fn sqlite3_column_count(statement: ?*sqlite3_stmt) c_int;
extern fn sqlite3_column_type(statement: ?*sqlite3_stmt, column: c_int) c_int;
extern fn sqlite3_column_int64(statement: ?*sqlite3_stmt, column: c_int) i64;
extern fn sqlite3_column_double(statement: ?*sqlite3_stmt, column: c_int) f64;
extern fn sqlite3_column_text(statement: ?*sqlite3_stmt, column: c_int) ?[*]const u8;
extern fn sqlite3_column_blob(statement: ?*sqlite3_stmt, column: c_int) ?*const anyopaque;
extern fn sqlite3_column_bytes(statement: ?*sqlite3_stmt, column: c_int) c_int;
extern fn sqlite3_changes64(db: ?*sqlite3) i64;
extern fn sqlite3_last_insert_rowid(db: ?*sqlite3) i64;
extern fn sqlite3_busy_timeout(db: ?*sqlite3, milliseconds: c_int) c_int;
extern fn sqlite3_libversion() [*:0]const u8;

pub const SQLITE_OK: c_int = 0;
pub const SQLITE_ERROR: c_int = 1;
pub const SQLITE_BUSY: c_int = 5;
pub const SQLITE_LOCKED: c_int = 6;
pub const SQLITE_NOMEM: c_int = 7;
pub const SQLITE_READONLY: c_int = 8;
pub const SQLITE_INTERRUPT: c_int = 9;
pub const SQLITE_IOERR: c_int = 10;
pub const SQLITE_CORRUPT: c_int = 11;
pub const SQLITE_NOTFOUND: c_int = 12;
pub const SQLITE_FULL: c_int = 13;
pub const SQLITE_CANTOPEN: c_int = 14;
pub const SQLITE_PROTOCOL: c_int = 15;
pub const SQLITE_SCHEMA: c_int = 17;
pub const SQLITE_TOOBIG: c_int = 18;
pub const SQLITE_CONSTRAINT: c_int = 19;
pub const SQLITE_MISMATCH: c_int = 20;
pub const SQLITE_MISUSE: c_int = 21;
pub const SQLITE_RANGE: c_int = 25;
pub const SQLITE_NOTADB: c_int = 26;
pub const SQLITE_ROW: c_int = 100;
pub const SQLITE_DONE: c_int = 101;

const SQLITE_INTEGER: c_int = 1;
const SQLITE_FLOAT: c_int = 2;
const SQLITE_TEXT: c_int = 3;
const SQLITE_BLOB: c_int = 4;
const SQLITE_NULL: c_int = 5;

const SQLITE_OPEN_READONLY: c_int = 0x00000001;
const SQLITE_OPEN_READWRITE: c_int = 0x00000002;
const SQLITE_OPEN_CREATE: c_int = 0x00000004;
const SQLITE_OPEN_URI: c_int = 0x00000040;
const SQLITE_OPEN_FULLMUTEX: c_int = 0x00010000;

pub const Error = error{
    OpenFailed,
    SqliteError,
    Busy,
    Locked,
    OutOfMemory,
    ReadOnly,
    Interrupted,
    Io,
    Corrupt,
    NotFound,
    Full,
    CannotOpen,
    Protocol,
    SchemaChanged,
    TooBig,
    Constraint,
    TypeMismatch,
    Misuse,
    ParameterRange,
    NotDatabase,
    UnexpectedStep,
    ColumnRange,
    InvalidText,
};

pub const Value = union(enum) {
    null,
    integer: i64,
    float: f64,
    text: []const u8,
    blob: []const u8,
};

pub const ColumnType = enum { integer, float, text, blob, null };
pub const Step = enum { row, done };

fn errorFromCode(code_raw: c_int) Error {
    return switch (code_raw & 0xff) {
        SQLITE_BUSY => error.Busy,
        SQLITE_LOCKED => error.Locked,
        SQLITE_NOMEM => error.OutOfMemory,
        SQLITE_READONLY => error.ReadOnly,
        SQLITE_INTERRUPT => error.Interrupted,
        SQLITE_IOERR => error.Io,
        SQLITE_CORRUPT => error.Corrupt,
        SQLITE_NOTFOUND => error.NotFound,
        SQLITE_FULL => error.Full,
        SQLITE_CANTOPEN => error.CannotOpen,
        SQLITE_PROTOCOL => error.Protocol,
        SQLITE_SCHEMA => error.SchemaChanged,
        SQLITE_TOOBIG => error.TooBig,
        SQLITE_CONSTRAINT => error.Constraint,
        SQLITE_MISMATCH => error.TypeMismatch,
        SQLITE_MISUSE => error.Misuse,
        SQLITE_RANGE => error.ParameterRange,
        SQLITE_NOTADB => error.NotDatabase,
        else => error.SqliteError,
    };
}

pub const Database = struct {
    gpa: std.mem.Allocator,
    handle: ?*sqlite3,

    pub fn open(gpa: std.mem.Allocator, path: []const u8) !Database {
        return openWithFlags(gpa, path, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_URI | SQLITE_OPEN_FULLMUTEX);
    }

    pub fn openReadOnly(gpa: std.mem.Allocator, path: []const u8) !Database {
        return openWithFlags(gpa, path, SQLITE_OPEN_READONLY | SQLITE_OPEN_URI | SQLITE_OPEN_FULLMUTEX);
    }

    fn openWithFlags(gpa: std.mem.Allocator, path: []const u8, flags: c_int) !Database {
        const path_z = try gpa.dupeZ(u8, path);
        defer gpa.free(path_z);
        var handle: ?*sqlite3 = null;
        const rc = sqlite3_open_v2(path_z.ptr, &handle, flags, null);
        if (rc != SQLITE_OK or handle == null) {
            if (handle != null) _ = sqlite3_close_v2(handle);
            return error.OpenFailed;
        }
        return .{ .gpa = gpa, .handle = handle };
    }

    pub fn close(self: *Database) void {
        if (self.handle) |handle| _ = sqlite3_close_v2(handle);
        self.handle = null;
    }

    pub fn deinit(self: *Database) void {
        self.close();
        self.* = undefined;
    }

    pub fn version() []const u8 {
        return std.mem.span(sqlite3_libversion());
    }

    pub fn errorCode(self: *const Database) c_int {
        return sqlite3_extended_errcode(self.handle);
    }

    pub fn errorMessage(self: *const Database) []const u8 {
        return std.mem.span(sqlite3_errmsg(self.handle));
    }

    pub fn busyTimeout(self: *Database, milliseconds: u31) !void {
        try self.check(sqlite3_busy_timeout(self.handle, @intCast(milliseconds)));
    }

    pub fn exec(self: *Database, sql: []const u8) !void {
        const sql_z = try self.gpa.dupeZ(u8, sql);
        defer self.gpa.free(sql_z);
        var message: ?[*:0]u8 = null;
        const rc = sqlite3_exec(self.handle, sql_z.ptr, null, null, &message);
        if (message) |ptr| sqlite3_free(@ptrCast(ptr));
        try self.check(rc);
    }

    pub fn prepare(self: *Database, sql: []const u8) !Statement {
        if (sql.len > std.math.maxInt(c_int)) return error.TooBig;
        var handle: ?*sqlite3_stmt = null;
        const rc = sqlite3_prepare_v2(self.handle, sql.ptr, @intCast(sql.len), &handle, null);
        try self.check(rc);
        if (handle == null) return error.SqliteError;
        return .{ .db = self, .handle = handle };
    }

    pub fn changes(self: *const Database) i64 {
        return sqlite3_changes64(self.handle);
    }

    pub fn lastInsertRowId(self: *const Database) i64 {
        return sqlite3_last_insert_rowid(self.handle);
    }

    pub fn begin(self: *Database) !void {
        try self.exec("BEGIN");
    }

    pub fn beginImmediate(self: *Database) !void {
        try self.exec("BEGIN IMMEDIATE");
    }

    pub fn commit(self: *Database) !void {
        try self.exec("COMMIT");
    }

    pub fn rollback(self: *Database) void {
        self.exec("ROLLBACK") catch {};
    }

    pub fn savepoint(self: *Database, comptime name: []const u8) !void {
        try self.exec("SAVEPOINT " ++ name);
    }

    pub fn release(self: *Database, comptime name: []const u8) !void {
        try self.exec("RELEASE SAVEPOINT " ++ name);
    }

    pub fn rollbackTo(self: *Database, comptime name: []const u8) void {
        self.exec("ROLLBACK TO SAVEPOINT " ++ name) catch {};
        self.exec("RELEASE SAVEPOINT " ++ name) catch {};
    }

    fn check(self: *const Database, code: c_int) Error!void {
        _ = self;
        if (code != SQLITE_OK) return errorFromCode(code);
    }
};

pub const Statement = struct {
    db: *Database,
    handle: ?*sqlite3_stmt,

    pub fn finalize(self: *Statement) void {
        if (self.handle) |handle| _ = sqlite3_finalize(handle);
        self.handle = null;
    }

    pub fn deinit(self: *Statement) void {
        self.finalize();
        self.* = undefined;
    }

    pub fn parameterCount(self: *const Statement) usize {
        return @intCast(sqlite3_bind_parameter_count(self.handle));
    }

    pub fn bind(self: *Statement, index: usize, value: Value) !void {
        if (index == 0 or index > std.math.maxInt(c_int)) return error.ParameterRange;
        const i: c_int = @intCast(index);
        const rc = switch (value) {
            .null => sqlite3_bind_null(self.handle, i),
            .integer => |v| sqlite3_bind_int64(self.handle, i, v),
            .float => |v| sqlite3_bind_double(self.handle, i, v),
            .text => |v| blk: {
                if (v.len > std.math.maxInt(c_int)) return error.TooBig;
                break :blk sqlite3_bind_text(self.handle, i, v.ptr, @intCast(v.len), null);
            },
            .blob => |v| blk: {
                if (v.len > std.math.maxInt(c_int)) return error.TooBig;
                const ptr: ?*const anyopaque = if (v.len == 0) null else @ptrCast(v.ptr);
                break :blk sqlite3_bind_blob(self.handle, i, ptr, @intCast(v.len), null);
            },
        };
        try self.db.check(rc);
    }

    pub fn bindAll(self: *Statement, values: []const Value) !void {
        if (values.len != self.parameterCount()) return error.ParameterRange;
        for (values, 1..) |value, index| try self.bind(index, value);
    }

    pub fn reset(self: *Statement) !void {
        const rc = sqlite3_reset(self.handle);
        if (rc != SQLITE_OK) try self.db.check(rc);
        try self.db.check(sqlite3_clear_bindings(self.handle));
    }

    pub fn step(self: *Statement) !Step {
        return switch (sqlite3_step(self.handle)) {
            SQLITE_ROW => .row,
            SQLITE_DONE => .done,
            else => |rc| errorFromCode(rc),
        };
    }

    pub fn run(self: *Statement) !i64 {
        if (try self.step() != .done) return error.UnexpectedStep;
        return self.db.changes();
    }

    pub fn columnCount(self: *const Statement) usize {
        return @intCast(sqlite3_column_count(self.handle));
    }

    fn checkColumn(self: *const Statement, index: usize) !c_int {
        if (index >= self.columnCount() or index > std.math.maxInt(c_int)) return error.ColumnRange;
        return @intCast(index);
    }

    pub fn columnType(self: *const Statement, index: usize) !ColumnType {
        const i = try self.checkColumn(index);
        return switch (sqlite3_column_type(self.handle, i)) {
            SQLITE_INTEGER => .integer,
            SQLITE_FLOAT => .float,
            SQLITE_TEXT => .text,
            SQLITE_BLOB => .blob,
            SQLITE_NULL => .null,
            else => error.TypeMismatch,
        };
    }

    pub fn columnIsNull(self: *const Statement, index: usize) !bool {
        return (try self.columnType(index)) == .null;
    }

    pub fn columnInt(self: *const Statement, index: usize) !i64 {
        return sqlite3_column_int64(self.handle, try self.checkColumn(index));
    }

    pub fn columnFloat(self: *const Statement, index: usize) !f64 {
        return sqlite3_column_double(self.handle, try self.checkColumn(index));
    }

    pub fn columnText(self: *const Statement, index: usize) !?[]const u8 {
        const i = try self.checkColumn(index);
        if (sqlite3_column_type(self.handle, i) == SQLITE_NULL) return null;
        const ptr = sqlite3_column_text(self.handle, i) orelse return error.InvalidText;
        const count = sqlite3_column_bytes(self.handle, i);
        if (count < 0) return error.InvalidText;
        return ptr[0..@intCast(count)];
    }

    pub fn columnTextAlloc(self: *const Statement, gpa: std.mem.Allocator, index: usize) !?[]u8 {
        const value = try self.columnText(index) orelse return null;
        return try gpa.dupe(u8, value);
    }

    pub fn columnBlob(self: *const Statement, index: usize) !?[]const u8 {
        const i = try self.checkColumn(index);
        if (sqlite3_column_type(self.handle, i) == SQLITE_NULL) return null;
        const count = sqlite3_column_bytes(self.handle, i);
        if (count < 0) return error.TypeMismatch;
        if (count == 0) return &.{};
        const ptr = sqlite3_column_blob(self.handle, i) orelse return error.TypeMismatch;
        return @as([*]const u8, @ptrCast(ptr))[0..@intCast(count)];
    }

    pub fn columnBlobAlloc(self: *const Statement, gpa: std.mem.Allocator, index: usize) !?[]u8 {
        const value = try self.columnBlob(index) orelse return null;
        return try gpa.dupe(u8, value);
    }
};

test "SQLite ABI wrapper executes parameterized statements" {
    const gpa = std.testing.allocator;
    var db = try Database.open(gpa, ":memory:");
    defer db.deinit();
    try db.exec("CREATE TABLE sample(id INTEGER PRIMARY KEY, name TEXT, score REAL, payload BLOB)");

    var insert = try db.prepare("INSERT INTO sample(name, score, payload) VALUES(?, ?, ?)");
    defer insert.deinit();
    try insert.bindAll(&.{ .{ .text = "alpha" }, .{ .float = 1.5 }, .{ .blob = "abc" } });
    try std.testing.expectEqual(@as(i64, 1), try insert.run());
    try std.testing.expectEqual(@as(i64, 1), db.lastInsertRowId());

    var query = try db.prepare("SELECT name, score, payload FROM sample WHERE id = ?");
    defer query.deinit();
    try query.bind(1, .{ .integer = 1 });
    try std.testing.expectEqual(Step.row, try query.step());
    try std.testing.expectEqualStrings("alpha", (try query.columnText(0)).?);
    try std.testing.expectApproxEqAbs(@as(f64, 1.5), try query.columnFloat(1), 0.00001);
    try std.testing.expectEqualSlices(u8, "abc", (try query.columnBlob(2)).?);
    try std.testing.expectEqual(Step.done, try query.step());
}

test "SQLite wrapper reports transactions and rollbacks" {
    const gpa = std.testing.allocator;
    var db = try Database.open(gpa, ":memory:");
    defer db.deinit();
    try db.exec("CREATE TABLE values_table(value TEXT UNIQUE)");
    try db.beginImmediate();
    var insert = try db.prepare("INSERT INTO values_table(value) VALUES(?)");
    defer insert.deinit();
    try insert.bind(1, .{ .text = "x" });
    _ = try insert.run();
    db.rollback();

    var count = try db.prepare("SELECT COUNT(*) FROM values_table");
    defer count.deinit();
    try std.testing.expectEqual(Step.row, try count.step());
    try std.testing.expectEqual(@as(i64, 0), try count.columnInt(0));
    try std.testing.expect(std.mem.indexOfScalar(u8, Database.version(), '.') != null);
}
