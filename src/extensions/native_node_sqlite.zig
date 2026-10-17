//! Real SQLite C capability consumed by Chord's Node adapter. No durable facade.
//! Scope: DatabaseSync constructor/open/exec/prepare/close and Statement run/get/all.
const std = @import("std");
const em = @import("engine.zig");
const v = @import("native_chord_sqlite_node_values.zig");
const c = v.c;
const functions = @import("native_node_function.zig");
const classes = @import("native_class.zig");
const js = @import("native_js_values.zig");
const Db = opaque {};
const Stmt = opaque {};
extern fn sqlite3_open_v2([*:0]const u8, *?*Db, c_int, ?[*:0]const u8) c_int;
extern fn sqlite3_close_v2(?*Db) c_int;
extern fn sqlite3_db_config(?*Db, c_int, ...) c_int;
extern fn sqlite3_busy_timeout(?*Db, c_int) c_int;
extern fn sqlite3_exec(?*Db, [*:0]const u8, ?*const anyopaque, ?*anyopaque, ?*?[*:0]u8) c_int;
extern fn sqlite3_prepare_v2(?*Db, [*:0]const u8, c_int, *?*Stmt, ?*?[*]const u8) c_int;
extern fn sqlite3_finalize(?*Stmt) c_int;
extern fn sqlite3_reset(?*Stmt) c_int;
extern fn sqlite3_clear_bindings(?*Stmt) c_int;
extern fn sqlite3_step(?*Stmt) c_int;
extern fn sqlite3_errmsg(?*Db) [*:0]const u8;
extern fn sqlite3_errstr(c_int) [*:0]const u8;
extern fn sqlite3_extended_errcode(?*Db) c_int;
extern fn sqlite3_bind_parameter_count(?*Stmt) c_int;
extern fn sqlite3_bind_parameter_name(?*Stmt, c_int) ?[*:0]const u8;
extern fn sqlite3_bind_parameter_index(?*Stmt, [*:0]const u8) c_int;
extern fn sqlite3_bind_null(?*Stmt, c_int) c_int;
extern fn sqlite3_bind_double(?*Stmt, c_int, f64) c_int;
extern fn sqlite3_bind_int64(?*Stmt, c_int, i64) c_int;
extern fn sqlite3_bind_text(?*Stmt, c_int, [*]const u8, c_int, ?*const anyopaque) c_int;
extern fn sqlite3_bind_blob(?*Stmt, c_int, *const anyopaque, c_int, ?*const anyopaque) c_int;
extern fn sqlite3_column_count(?*Stmt) c_int;
extern fn sqlite3_column_name(?*Stmt, c_int) ?[*:0]const u8;
extern fn sqlite3_column_type(?*Stmt, c_int) c_int;
extern fn sqlite3_column_int64(?*Stmt, c_int) i64;
extern fn sqlite3_column_double(?*Stmt, c_int) f64;
extern fn sqlite3_column_text(?*Stmt, c_int) ?[*:0]const u8;
extern fn sqlite3_column_blob(?*Stmt, c_int) ?[*]const u8;
extern fn sqlite3_column_bytes(?*Stmt, c_int) c_int;
extern fn sqlite3_changes64(?*Db) i64;
extern fn sqlite3_last_insert_rowid(?*Db) i64;
extern fn sqlite3_get_autocommit(?*Db) c_int;
const transient: ?*const anyopaque = @ptrFromInt(std.math.maxInt(usize));
const Module = struct { engine: *em.Engine, database: c.JSClassID, statement: c.JSClassID };
const Database = struct {
    engine: *em.Engine, handle: ?*Db = null, path: [:0]u8,
    statement_prototype: c.JSValue, statements: std.ArrayList(*Statement) = .empty,
    references: usize = 1,
    read_only: bool = false, foreign_keys: bool = true, dqs: bool = false,
    defensive: bool = true, extensions: bool = false, timeout: i32 = 0,
    bigints: bool = false, arrays: bool = false, bare_names: bool = true, unknown_names: bool = false,
};
const Statement = struct { engine: *em.Engine, database: *Database, owner: c.JSValue, handle: ?*Stmt, bigints: bool, arrays: bool, allow_bare: bool, allow_unknown: bool, bare_initialized: bool = false, bare_names: std.StringHashMapUnmanaged([:0]u8) = .empty };
fn module(value: c.JSValue) *Module { return @ptrCast(@alignCast(c.JS_GetOpaque(value, c.JS_GetClassID(value)).?)); }
fn moduleFinal(_: ?*c.JSRuntime, value: c.JSValue) callconv(.c) void { const raw = c.JS_GetOpaque(value, c.JS_GetClassID(value)) orelse return; const m: *Module = @ptrCast(@alignCast(raw)); m.engine.gpa.destroy(m); }
fn releaseDatabase(db: *Database) void { db.references -= 1; if (db.references == 0) { db.statements.deinit(db.engine.gpa); db.engine.gpa.free(db.path); db.engine.gpa.destroy(db); } }
fn databaseFinal(runtime: ?*c.JSRuntime, value: c.JSValue) callconv(.c) void {
    const db: *Database = @ptrCast(@alignCast(c.JS_GetOpaque(value, c.JS_GetClassID(value)) orelse return));
    for (db.statements.items) |stmt| { _ = sqlite3_finalize(stmt.handle); stmt.handle = null; }
    db.statements.clearRetainingCapacity();
    _ = sqlite3_close_v2(db.handle); db.handle = null;
    c.JS_FreeValueRT(runtime, db.statement_prototype);
    releaseDatabase(db);
}
fn databaseMark(runtime: ?*c.JSRuntime, value: c.JSValue, visit: ?*const c.JS_MarkFunc) callconv(.c) void {
    const db: *Database = @ptrCast(@alignCast(c.JS_GetOpaque(value, c.JS_GetClassID(value)) orelse return));
    c.JS_MarkValue(runtime, db.statement_prototype, visit);
}
fn statementFinal(runtime: ?*c.JSRuntime, value: c.JSValue) callconv(.c) void {
    const stmt: *Statement = @ptrCast(@alignCast(c.JS_GetOpaque(value, c.JS_GetClassID(value)) orelse return));
    _ = sqlite3_finalize(stmt.handle);
    for (stmt.database.statements.items, 0..) |item, index| if (item == stmt) { _ = stmt.database.statements.swapRemove(index); break; };
    var values = stmt.bare_names.valueIterator(); while (values.next()) |full| stmt.engine.gpa.free(full.*); stmt.bare_names.deinit(stmt.engine.gpa);
    const db = stmt.database;
    c.JS_FreeValueRT(runtime, stmt.owner); stmt.engine.gpa.destroy(stmt);
    releaseDatabase(db);
}
fn statementMark(runtime: ?*c.JSRuntime, value: c.JSValue, visit: ?*const c.JS_MarkFunc) callconv(.c) void {
    const stmt: *Statement = @ptrCast(@alignCast(c.JS_GetOpaque(value, c.JS_GetClassID(value)) orelse return));
    c.JS_MarkValue(runtime, stmt.owner, visit);
}
fn throwError(s: *v.Scope, kind: enum { type_error, range_error, error_value }, code: []const u8, message: []const u8) anyerror {
    const text = s.engine.gpa.dupeZ(u8, message) catch |err| return err; defer s.engine.gpa.free(text);
    const reason = if (kind == .error_value) s.own(v.checked(s.engine, c.JS_NewError(s.engine.context)) catch |err| return err) catch |err| return err else blk: {
        _ = if (kind == .type_error) c.JS_ThrowTypeError(s.engine.context, "%s", text.ptr) else c.JS_ThrowRangeError(s.engine.context, "%s", text.ptr);
        break :blk s.own(c.JS_GetException(s.engine.context)) catch |err| return err;
    };
    if (kind == .error_value) {
        const message_value = s.text(message) catch |err| return err;
        if (c.JS_DefinePropertyValueStr(s.engine.context, reason, "message", c.JS_DupValue(s.engine.context, message_value), c.JS_PROP_CONFIGURABLE | c.JS_PROP_WRITABLE) < 0) return js.capture(s.engine);
    }
    s.put(reason, "code", s.text(code) catch |err| return err) catch |err| return err;
    _ = v.checked(s.engine, c.JS_Throw(s.engine.context, c.JS_DupValue(s.engine.context, reason))) catch |err| return err;
    unreachable;
}
fn sqlError(s: *v.Scope, db: ?*Db) anyerror {
    const reason = s.own(v.checked(s.engine, c.JS_NewError(s.engine.context)) catch |err| return err) catch |err| return err;
    const code = sqlite3_extended_errcode(db);
    const message = s.text(std.mem.span(sqlite3_errmsg(db))) catch |err| return err;
    if (c.JS_DefinePropertyValueStr(s.engine.context, reason, "message", c.JS_DupValue(s.engine.context, message), c.JS_PROP_CONFIGURABLE | c.JS_PROP_WRITABLE) < 0) return js.capture(s.engine);
    s.put(reason, "code", s.text("ERR_SQLITE_ERROR") catch |err| return err) catch |err| return err;
    s.put(reason, "errcode", c.JS_NewInt32(s.engine.context, code)) catch |err| return err;
    s.put(reason, "errstr", s.text(std.mem.span(sqlite3_errstr(code))) catch |err| return err) catch |err| return err;
    _ = v.checked(s.engine, c.JS_Throw(s.engine.context, c.JS_DupValue(s.engine.context, reason))) catch |err| return err; unreachable;
}
fn check(s: *v.Scope, db: ?*Db, result: c_int) !void { if (result != 0) return sqlError(s, db); }
fn string(s: *v.Scope, value: c.JSValue, field: []const u8) ![:0]u8 {
    if (!c.JS_IsString(value)) { const message = try std.fmt.allocPrint(s.engine.gpa, "The \"{s}\" argument must be a string.", .{field}); defer s.engine.gpa.free(message); return throwError(s, .type_error, "ERR_INVALID_ARG_TYPE", message); }
    var len: usize = 0; const ptr = c.JS_ToCStringLen(s.engine.context, &len, value) orelse return js.capture(s.engine); defer c.JS_FreeCString(s.engine.context, ptr);
    return s.engine.gpa.dupeZ(u8, ptr[0..len]);
}
fn boolOption(s: *v.Scope, options: c.JSValue, key: [*:0]const u8, fallback: bool) !bool { const value = try v.get(s, options, key); if (c.JS_IsUndefined(value)) return fallback; if (!c.JS_IsBool(value)) return throwError(s, .type_error, "ERR_INVALID_ARG_TYPE", "SQLite option must be a boolean."); return s.truthy(value); }
fn openDatabase(s: *v.Scope, db: *Database) !void {
    if (db.handle != null) return throwError(s, .error_value, "ERR_INVALID_STATE", "database is already open");
    const opened = sqlite3_open_v2(db.path.ptr, &db.handle, @as(c_int, 0x40) | @as(c_int, if (db.read_only) 1 else 6), null);
    try check(s, db.handle, opened);
    try check(s, db.handle, sqlite3_db_config(db.handle, 1013, @as(c_int, @intFromBool(db.dqs)), @as(?*c_int, null)));
    try check(s, db.handle, sqlite3_db_config(db.handle, 1014, @as(c_int, @intFromBool(db.dqs)), @as(?*c_int, null)));
    var actual: c_int = 0;
    try check(s, db.handle, sqlite3_db_config(db.handle, 1002, @as(c_int, @intFromBool(db.foreign_keys)), &actual));
    try check(s, db.handle, sqlite3_db_config(db.handle, 1010, @as(c_int, @intFromBool(db.defensive)), &actual));
    _ = sqlite3_busy_timeout(db.handle, db.timeout);
    if (db.extensions) try check(s, db.handle, sqlite3_db_config(db.handle, 1005, @as(c_int, 1), @as(?*c_int, null)));
}
fn constructDatabase(engine: *em.Engine, target: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    var s: v.Scope = .{ .engine = engine }; defer s.deinit(); errdefer |err| s.captureUnwind(err); const m = module(roots[0]);
    const prototype = try v.get(&s, target, "prototype");
    const object = try s.own(try v.checked(engine, c.JS_NewObjectProtoClass(engine.context, if (c.JS_IsObject(prototype)) prototype else try v.objectPrototype(&s), m.database)));
    const path = try string(&s, v.at(args, 0), "path");
    var path_owned = true; errdefer if (path_owned) engine.gpa.free(path);
    if (std.mem.indexOfScalar(u8, path, 0) != null) return throwError(&s, .type_error, "ERR_INVALID_ARG_VALUE", "The argument 'path' must be a string without null bytes.");
    const db = try engine.gpa.create(Database);
    db.* = .{ .engine = engine, .path = path, .statement_prototype = c.JS_DupValue(engine.context, roots[1]) };
    _ = c.JS_SetOpaque(object, db); path_owned = false;
    const options = v.at(args, 1); var open = true;
    if (!c.JS_IsUndefined(options)) {
        if (!c.JS_IsObject(options)) return throwError(&s, .type_error, "ERR_INVALID_ARG_TYPE", "The \"options\" argument must be an object.");
        open = try boolOption(&s, options, "open", true);
        db.read_only = try boolOption(&s, options, "readOnly", false);
        db.foreign_keys = try boolOption(&s, options, "enableForeignKeyConstraints", true);
        db.dqs = try boolOption(&s, options, "enableDoubleQuotedStringLiterals", false);
        db.extensions = try boolOption(&s, options, "allowExtension", false);
        const timeout = try v.get(&s, options, "timeout");
        if (!c.JS_IsUndefined(timeout)) { var number: f64 = 0; if (!c.JS_IsNumber(timeout)) return throwError(&s, .type_error, "ERR_INVALID_ARG_TYPE", "The \"options.timeout\" argument must be an integer."); if (c.JS_ToFloat64(engine.context, &number, timeout) < 0) return js.capture(engine); if (!std.math.isFinite(number) or @trunc(number) != number or number < std.math.minInt(i32) or number > std.math.maxInt(i32)) return throwError(&s, .type_error, "ERR_INVALID_ARG_TYPE", "The \"options.timeout\" argument must be an integer."); db.timeout = @intFromFloat(number); }
        db.bigints = try boolOption(&s, options, "readBigInts", false);
        db.arrays = try boolOption(&s, options, "returnArrays", false);
        db.bare_names = try boolOption(&s, options, "allowBareNamedParameters", true);
        db.unknown_names = try boolOption(&s, options, "allowUnknownNamedParameters", false);
        db.defensive = try boolOption(&s, options, "defensive", true);
    }
    if (open) try openDatabase(&s, db);
    return c.JS_DupValue(engine.context, object);
}
fn database(s: *v.Scope, receiver: c.JSValue, owner: c.JSValue) !*Database { const m = module(owner); const raw = c.JS_GetOpaque(receiver, m.database) orelse return throwError(s, .type_error, "ERR_INVALID_THIS", "Illegal invocation"); return @ptrCast(@alignCast(raw)); }
fn statement(s: *v.Scope, receiver: c.JSValue, owner: c.JSValue) !*Statement { const m = module(owner); const raw = c.JS_GetOpaque(receiver, m.statement) orelse return throwError(s, .type_error, "ERR_INVALID_THIS", "Illegal invocation"); const stmt: *Statement = @ptrCast(@alignCast(raw)); if (stmt.handle == null) return throwError(s, .error_value, "ERR_INVALID_STATE", "statement has been finalized"); return stmt; }
fn dbMethod(engine: *em.Engine, comptime name: []const u8, receiver: c.JSValue, args: []const c.JSValue, owner: c.JSValue) !c.JSValue {
    var s: v.Scope = .{ .engine = engine }; defer s.deinit(); errdefer |err| s.captureUnwind(err); const db = try database(&s, receiver, owner);
    if (comptime std.mem.eql(u8, name, "open")) { try openDatabase(&s, db); return c.pi_js_undefined(); }
    if (db.handle == null) return throwError(&s, .error_value, "ERR_INVALID_STATE", "database is not open");
    if (comptime std.mem.eql(u8, name, "close")) {
        for (db.statements.items) |stmt| { _ = sqlite3_finalize(stmt.handle); stmt.handle = null; }
        db.statements.clearRetainingCapacity(); try check(&s, db.handle, sqlite3_close_v2(db.handle)); db.handle = null; return c.pi_js_undefined();
    }
    const sql = try string(&s, v.at(args, 0), "sql"); defer engine.gpa.free(sql);
    if (comptime std.mem.eql(u8, name, "exec")) { try check(&s, db.handle, sqlite3_exec(db.handle, sql.ptr, null, null, null)); return c.pi_js_undefined(); }
    var handle: ?*Stmt = null; try check(&s, db.handle, sqlite3_prepare_v2(db.handle, sql.ptr, -1, &handle, null));
    var owned = true; errdefer if (owned) { _ = sqlite3_finalize(handle); };
    const object = try s.own(try v.checked(engine, c.JS_NewObjectProtoClass(engine.context, db.statement_prototype, module(owner).statement)));
    const stmt = try engine.gpa.create(Statement);
    stmt.* = .{ .engine = engine, .database = db, .owner = c.JS_DupValue(engine.context, receiver), .handle = handle, .bigints = db.bigints, .arrays = db.arrays, .allow_bare = db.bare_names, .allow_unknown = db.unknown_names };
    db.references += 1;
    _ = c.JS_SetOpaque(object, stmt); owned = false; try db.statements.append(engine.gpa, stmt);
    return c.JS_DupValue(engine.context, object);
}
fn bind(s: *v.Scope, stmt: *Statement, index: c_int, value: c.JSValue) !void {
    const result = if (c.JS_IsNull(value)) sqlite3_bind_null(stmt.handle, index) else if (c.JS_IsNumber(value)) blk: { var n: f64 = 0; if (c.JS_ToFloat64(s.engine.context, &n, value) < 0) return js.capture(s.engine); break :blk sqlite3_bind_double(stmt.handle, index, n); } else if (c.JS_IsString(value)) blk: { var len: usize = 0; const bytes = c.JS_ToCStringLen(s.engine.context, &len, value) orelse return js.capture(s.engine); defer c.JS_FreeCString(s.engine.context, bytes); if (len > std.math.maxInt(c_int)) return throwError(s, .range_error, "ERR_OUT_OF_RANGE", "SQLite parameter is too large"); break :blk sqlite3_bind_text(stmt.handle, index, bytes, @intCast(len), transient); } else if (c.JS_IsBigInt(value)) blk: { var n: i64 = 0; if (c.JS_ToBigInt64(s.engine.context, &n, value) < 0) return js.capture(s.engine); const exact = try s.own(try v.checked(s.engine, c.JS_NewBigInt64(s.engine.context, n))); if (!s.equal(exact, value)) return throwError(s, .type_error, "ERR_INVALID_ARG_VALUE", "BigInt value is too large to bind."); break :blk sqlite3_bind_int64(stmt.handle, index, n); } else if ((c.JS_GetTypedArrayType(value) >= 0 or c.JS_IsDataView(value))) blk: { var offset: usize = 0; var len: usize = 0; var element: usize = 0; const backing = try s.own(try v.checked(s.engine, c.JS_PiGetArrayBufferViewBuffer(s.engine.context, value, &offset, &len, &element))); var total: usize = 0; const observed = c.JS_GetArrayBuffer(s.engine.context, &total, backing); try v.pending(s.engine); const bytes: [*]const u8 = if (observed != null) @ptrCast(observed) else if (total == 0 and offset == 0 and len == 0) "".ptr else return error.SqliteInvalidArrayBufferSpan; if (offset > total or len > total - offset or len > std.math.maxInt(c_int)) return throwError(s, .range_error, "ERR_OUT_OF_RANGE", "SQLite parameter is too large"); break :blk sqlite3_bind_blob(stmt.handle, index, @ptrCast(if (len == 0) "".ptr else bytes + offset), @intCast(len), transient); } else { const message = try std.fmt.allocPrint(s.engine.gpa, "Provided value cannot be bound to SQLite parameter {d}.", .{index}); defer s.engine.gpa.free(message); return throwError(s, .type_error, "ERR_INVALID_ARG_TYPE", message); };
    try check(s, stmt.database.handle, result);
}
fn bindParams(s: *v.Scope, stmt: *Statement, args: []const c.JSValue) !void {
    try check(s, stmt.database.handle, sqlite3_clear_bindings(stmt.handle));
    var start: usize = 0;
    if (args.len > 0 and c.JS_IsObject(args[0]) and c.JS_GetTypedArrayType(args[0]) < 0 and !c.JS_IsDataView(args[0])) {
        var names: [*c]c.JSPropertyEnum = null; var count: u32 = 0;
        try v.pending(s.engine);
        const keys_generation = s.engine.native_allocation_generation;
        const own_keys = c.JS_GetOwnPropertyNames(s.engine.context, &names, &count, args[0], c.JS_GPN_STRING_MASK);
        defer c.JS_FreePropertyEnum(s.engine.context, names, count);
        try v.statusSince(s.engine, own_keys < 0, keys_generation);
        if (stmt.allow_bare and !stmt.bare_initialized) {
            stmt.bare_initialized = true;
            var candidate: c_int = 1;
            while (candidate <= sqlite3_bind_parameter_count(stmt.handle)) : (candidate += 1) if (sqlite3_bind_parameter_name(stmt.handle, candidate)) |name| {
                const full = std.mem.span(name); const bare = full[1..];
                if (stmt.bare_names.get(bare)) |existing| {
                    if (!std.mem.eql(u8, existing, full)) {
                        const message = try std.fmt.allocPrint(s.engine.gpa, "Cannot create bare named parameter '{s}' because of conflicting names '{s}' and '{s}'.", .{ bare, existing, full }); defer s.engine.gpa.free(message);
                        return throwError(s, .error_value, "ERR_INVALID_STATE", message);
                    }
                } else {
                    const owned_full = try s.engine.gpa.dupeZ(u8, full);
                    stmt.bare_names.put(s.engine.gpa, owned_full[1..], owned_full) catch |err| { s.engine.gpa.free(owned_full); return err; };
                }
            };
        }
        for (names[0..count]) |key| {
            const text = try s.own(try v.checked(s.engine, c.JS_AtomToString(s.engine.context, key.atom))); const name = try string(s, text, "parameter"); defer s.engine.gpa.free(name);
            var index = sqlite3_bind_parameter_index(stmt.handle, name.ptr);
            if (index == 0 and stmt.allow_bare) if (stmt.bare_names.get(std.mem.span(name.ptr))) |full| { index = sqlite3_bind_parameter_index(stmt.handle, full.ptr); };
            if (index == 0) {
                if (stmt.allow_unknown) continue;
                const message = try std.fmt.allocPrint(s.engine.gpa, "Unknown named parameter '{s}'", .{std.mem.span(name.ptr)}); defer s.engine.gpa.free(message);
                return throwError(s, .error_value, "ERR_INVALID_STATE", message);
            }
            const value_generation = s.engine.native_allocation_generation;
            const value = try s.own(try v.checkedSince(s.engine, c.JS_GetProperty(s.engine.context, args[0], key.atom), value_generation));
            try bind(s, stmt, index, value);
        }
        start = 1;
    }
    var index: c_int = 1;
    for (args[start..]) |value| {
        while (sqlite3_bind_parameter_name(stmt.handle, index)) |name| { if (name[0] == '?') break; index += 1; }
        try bind(s, stmt, index, value); index += 1;
    }
}
fn row(s: *v.Scope, stmt: *Statement) !c.JSValue {
    const output = if (stmt.arrays) try s.array() else try s.own(try v.checked(s.engine, c.JS_NewObjectProto(s.engine.context, c.pi_js_null())));
    const count = sqlite3_column_count(stmt.handle);
    var column: c_int = 0;
    while (column < count) : (column += 1) {
        const value: c.JSValue = switch (sqlite3_column_type(stmt.handle, column)) {
            1 => blk: { const n = sqlite3_column_int64(stmt.handle, column); if (stmt.bigints) break :blk try s.own(try v.checked(s.engine, c.JS_NewBigInt64(s.engine.context, n))); if (n < -9007199254740991 or n > 9007199254740991) { const message = try std.fmt.allocPrint(s.engine.gpa, "Value is too large to be represented as a JavaScript number: {d}", .{n}); defer s.engine.gpa.free(message); return throwError(s, .range_error, "ERR_OUT_OF_RANGE", message); } break :blk c.JS_NewFloat64(s.engine.context, @floatFromInt(n)); },
            2 => c.JS_NewFloat64(s.engine.context, sqlite3_column_double(stmt.handle, column)),
            3 => try s.text(std.mem.span(sqlite3_column_text(stmt.handle, column) orelse return sqlError(s, stmt.database.handle))),
            4 => blk: { const len = sqlite3_column_bytes(stmt.handle, column); if (len < 0) return sqlError(s, stmt.database.handle); const bytes = sqlite3_column_blob(stmt.handle, column); break :blk try s.own(try v.checked(s.engine, c.JS_NewUint8ArrayCopy(s.engine.context, if (len == 0) "".ptr else bytes orelse return sqlError(s, stmt.database.handle), @intCast(len)))); },
            5 => c.pi_js_null(), else => return sqlError(s, stmt.database.handle),
        };
        if (stmt.arrays) try s.index(output, @intCast(column), value) else {
            const key = sqlite3_column_name(stmt.handle, column) orelse return sqlError(s, stmt.database.handle);
            if (c.JS_DefinePropertyValueStr(s.engine.context, output, key, c.JS_DupValue(s.engine.context, value), c.JS_PROP_C_W_E) < 0) return js.capture(s.engine);
        }
    }
    return output;
}
fn stmtMethod(engine: *em.Engine, comptime name: []const u8, receiver: c.JSValue, args: []const c.JSValue, owner: c.JSValue) !c.JSValue {
    var s: v.Scope = .{ .engine = engine }; defer s.deinit(); errdefer |err| s.captureUnwind(err); const stmt = try statement(&s, receiver, owner);
    if (comptime std.mem.eql(u8, name, "setReadBigInts") or std.mem.eql(u8, name, "setReturnArrays") or std.mem.eql(u8, name, "setAllowBareNamedParameters") or std.mem.eql(u8, name, "setAllowUnknownNamedParameters")) { const flag = v.at(args, 0); if (!c.JS_IsBool(flag)) return throwError(&s, .type_error, "ERR_INVALID_ARG_TYPE", "SQLite statement option must be a boolean"); if (comptime std.mem.eql(u8, name, "setReadBigInts")) stmt.bigints = s.truthy(flag) else if (comptime std.mem.eql(u8, name, "setReturnArrays")) stmt.arrays = s.truthy(flag) else if (comptime std.mem.eql(u8, name, "setAllowBareNamedParameters")) stmt.allow_bare = s.truthy(flag) else stmt.allow_unknown = s.truthy(flag); return c.pi_js_undefined(); }
    try check(&s, stmt.database.handle, sqlite3_reset(stmt.handle)); try bindParams(&s, stmt, args);
    if (comptime std.mem.eql(u8, name, "run")) {
        _ = sqlite3_step(stmt.handle); try check(&s, stmt.database.handle, sqlite3_reset(stmt.handle));
        const output = try s.object(); const changes = sqlite3_changes64(stmt.database.handle); const id = sqlite3_last_insert_rowid(stmt.database.handle);
        try s.put(output, "changes", if (stmt.bigints) try s.own(try v.checked(engine, c.JS_NewBigInt64(engine.context, changes))) else c.JS_NewFloat64(engine.context, @floatFromInt(changes)));
        try s.put(output, "lastInsertRowid", if (stmt.bigints) try s.own(try v.checked(engine, c.JS_NewBigInt64(engine.context, id))) else c.JS_NewFloat64(engine.context, @floatFromInt(id)));
        return c.JS_DupValue(engine.context, output);
    } else if (comptime std.mem.eql(u8, name, "get")) {
        defer _ = sqlite3_reset(stmt.handle);
        const rc = sqlite3_step(stmt.handle); if (rc == 101) return c.pi_js_undefined(); if (rc != 100) return sqlError(&s, stmt.database.handle);
        return c.JS_DupValue(engine.context, try row(&s, stmt));
    } else {
        // Node StatementSync::All resets on every post-bind exit, including
        // row conversion/range/OOM/SQL failures. Bind failures precede this.
        defer _ = sqlite3_reset(stmt.handle);
        const output = try s.array(); var index: u32 = 0;
        while (true) { const rc = sqlite3_step(stmt.handle); if (rc == 101) break; if (rc != 100) return sqlError(&s, stmt.database.handle); try s.index(output, index, try row(&s, stmt)); index = std.math.add(u32, index, 1) catch return error.OutOfMemory; }
        return c.JS_DupValue(engine.context, output);
    }
}
fn illegal(engine: *em.Engine, _: c.JSValue, _: []const c.JSValue, _: []const c.JSValue) !c.JSValue { var s: v.Scope = .{ .engine = engine }; defer s.deinit(); errdefer |err| s.captureUnwind(err); return throwError(&s, .type_error, "ERR_ILLEGAL_CONSTRUCTOR", "Illegal constructor"); }
fn property(engine: *em.Engine, receiver: c.JSValue, _: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    var s: v.Scope = .{ .engine = engine }; defer s.deinit(); errdefer |err| s.captureUnwind(err);
    var kind: i32 = 0; if (c.JS_ToInt32(engine.context, &kind, roots[1]) < 0) return js.capture(engine);
    const db = try database(&s, receiver, roots[0]);
    if (kind == 0) return c.pi_js_bool(engine.context, @intFromBool(db.handle != null));
    if (db.handle == null) return throwError(&s, .error_value, "ERR_INVALID_STATE", "database is not open");
    return c.pi_js_bool(engine.context, @intFromBool(sqlite3_get_autocommit(db.handle) == 0));
}
pub fn create(engine: *em.Engine) !c.JSValue {
    try v.pending(engine);
    const cache_key = "\x00native-node-sqlite-consumer-module";
    if (engine.native_module_values.get(cache_key)) |cached| return c.JS_DupValue(engine.context, cached);
    var s: v.Scope = .{ .engine = engine }; defer s.deinit(); errdefer |err| s.captureUnwind(err);
    var owner_class: c.JSClassID = 0; var db_class: c.JSClassID = 0; var stmt_class: c.JSClassID = 0;
    _ = c.JS_NewClassID(engine.runtime, &owner_class); _ = c.JS_NewClassID(engine.runtime, &db_class); _ = c.JS_NewClassID(engine.runtime, &stmt_class);
    const owner_definition: c.JSClassDef = .{ .class_name = "Private SQLite module", .finalizer = moduleFinal };
    const db_definition: c.JSClassDef = .{ .class_name = "DatabaseSync", .finalizer = databaseFinal, .gc_mark = databaseMark };
    const stmt_definition: c.JSClassDef = .{ .class_name = "StatementSync", .finalizer = statementFinal, .gc_mark = statementMark };
    if (c.JS_NewClass(engine.runtime, owner_class, &owner_definition) < 0 or c.JS_NewClass(engine.runtime, db_class, &db_definition) < 0 or c.JS_NewClass(engine.runtime, stmt_class, &stmt_definition) < 0) return error.OutOfMemory;
    const owner = try s.own(try v.checked(engine, c.JS_NewObjectClass(engine.context, owner_class))); const m = try engine.gpa.create(Module); m.* = .{ .engine = engine, .database = db_class, .statement = stmt_class }; _ = c.JS_SetOpaque(owner, m);
    const db_proto = try s.object(); const stmt_proto = try s.object();
    inline for (.{ "isOpen", "isTransaction" }, 0..) |name, index| {
        const getter = try s.own(try functions.createMethod(engine, "get " ++ name, 0, v.callback(property), &.{ owner, c.JS_NewInt32(engine.context, @intCast(index)) }));
        const atom = c.JS_NewAtom(engine.context, name); if (atom == c.JS_ATOM_NULL) return js.capture(engine); defer c.JS_FreeAtom(engine.context, atom);
        if (c.JS_DefinePropertyGetSet(engine.context, db_proto, atom, c.JS_DupValue(engine.context, getter), c.pi_js_undefined(), c.JS_PROP_CONFIGURABLE | c.JS_PROP_ENUMERABLE) < 0) return js.capture(engine);
    }
    inline for (.{ "open", "exec", "prepare", "close" }) |name| { const Adapter = struct { fn call(host: *em.Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue { return dbMethod(host, name, receiver, args, roots[0]); } }; const fnc = try s.own(try functions.createMethod(engine, name, 0, v.callback(Adapter.call), &.{owner})); if (c.JS_DefinePropertyValueStr(engine.context, db_proto, name, c.JS_DupValue(engine.context, fnc), c.JS_PROP_WRITABLE | c.JS_PROP_CONFIGURABLE) < 0) return js.capture(engine); }
    inline for (.{ "run", "get", "all", "setReadBigInts", "setReturnArrays", "setAllowBareNamedParameters", "setAllowUnknownNamedParameters" }) |name| { const Adapter = struct { fn call(host: *em.Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue { return stmtMethod(host, name, receiver, args, roots[0]); } }; const fnc = try s.own(try functions.createMethod(engine, name, 0, v.callback(Adapter.call), &.{owner})); if (c.JS_DefinePropertyValueStr(engine.context, stmt_proto, name, c.JS_DupValue(engine.context, fnc), c.JS_PROP_WRITABLE | c.JS_PROP_CONFIGURABLE) < 0) return js.capture(engine); }
    const carrier = try s.object();
    try s.put(carrier, "DatabaseSync", try s.own(try classes.constructor(engine, "DatabaseSync", 0, db_proto, v.callback(constructDatabase), &.{ owner, stmt_proto })));
    try s.put(carrier, "StatementSync", try s.own(try classes.constructor(engine, "StatementSync", 0, stmt_proto, v.callback(illegal), &.{})));
    const retained = c.JS_DupValue(engine.context, carrier); engine.native_module_values.put(engine.gpa, cache_key, retained) catch |err| { engine.freeValue(retained); return err; };
    return c.JS_DupValue(engine.context, carrier);
}
