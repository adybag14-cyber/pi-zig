//! Generated storage schema/query helpers shard 2.
const std = @import("std");

pub const Row = struct {
    id: []const u8,
    kind: []const u8,
    payload: []const u8,
    mtime: i64,
};

pub fn schema_table_2_0_name() []const u8 { return "t_2_0"; }
pub fn schema_table_2_0_create_sql() []const u8 {
    return "CREATE TABLE IF NOT EXISTS t_2_0 (id TEXT PRIMARY KEY, kind TEXT, payload TEXT, mtime INTEGER);";
}
pub fn schema_table_2_0_insert_sql() []const u8 {
    return "INSERT OR REPLACE INTO t_2_0 (id, kind, payload, mtime) VALUES (?, ?, ?, ?);";
}
pub fn schema_table_2_0_select_sql() []const u8 {
    return "SELECT id, kind, payload, mtime FROM t_2_0 WHERE id = ?;";
}
pub fn schema_table_2_0_list_sql(limit: u32) []const u8 {
    _ = limit;
    return "SELECT id, kind, payload, mtime FROM t_2_0 ORDER BY mtime DESC LIMIT 100;";
}
pub fn encode_row_2_0(gpa: std.mem.Allocator, row: Row) ![]u8 {
    var aw: std.Io.Writer.Allocating = .init(gpa);
    errdefer aw.deinit();
    try aw.writer.writeAll("{\"id\":");
    try std.json.Stringify.value(row.id, .{}, &aw.writer);
    try aw.writer.writeAll(",\"kind\":");
    try std.json.Stringify.value(row.kind, .{}, &aw.writer);
    try aw.writer.writeAll(",\"payload\":");
    try std.json.Stringify.value(row.payload, .{}, &aw.writer);
    try aw.writer.writeAll(",\"mtime\":");
    try aw.writer.print("{d}", .{row.mtime});
    try aw.writer.writeAll("}");
    return try aw.toOwnedSlice();
}
pub fn decode_row_id_2_0(json_text: []const u8) ?[]const u8 {
    // lightweight scan for "id":"..." without full JSON parse
    const key = "\"id\":\"";
    const start = std.mem.indexOf(u8, json_text, key) orelse return null;
    const from = start + key.len;
    const end = std.mem.indexOfScalar(u8, json_text[from..], '"') orelse return null;
    return json_text[from .. from + end];
}

pub fn schema_table_2_1_name() []const u8 { return "t_2_1"; }
pub fn schema_table_2_1_create_sql() []const u8 {
    return "CREATE TABLE IF NOT EXISTS t_2_1 (id TEXT PRIMARY KEY, kind TEXT, payload TEXT, mtime INTEGER);";
}
pub fn schema_table_2_1_insert_sql() []const u8 {
    return "INSERT OR REPLACE INTO t_2_1 (id, kind, payload, mtime) VALUES (?, ?, ?, ?);";
}
pub fn schema_table_2_1_select_sql() []const u8 {
    return "SELECT id, kind, payload, mtime FROM t_2_1 WHERE id = ?;";
}
pub fn schema_table_2_1_list_sql(limit: u32) []const u8 {
    _ = limit;
    return "SELECT id, kind, payload, mtime FROM t_2_1 ORDER BY mtime DESC LIMIT 100;";
}
pub fn encode_row_2_1(gpa: std.mem.Allocator, row: Row) ![]u8 {
    var aw: std.Io.Writer.Allocating = .init(gpa);
    errdefer aw.deinit();
    try aw.writer.writeAll("{\"id\":");
    try std.json.Stringify.value(row.id, .{}, &aw.writer);
    try aw.writer.writeAll(",\"kind\":");
    try std.json.Stringify.value(row.kind, .{}, &aw.writer);
    try aw.writer.writeAll(",\"payload\":");
    try std.json.Stringify.value(row.payload, .{}, &aw.writer);
    try aw.writer.writeAll(",\"mtime\":");
    try aw.writer.print("{d}", .{row.mtime});
    try aw.writer.writeAll("}");
    return try aw.toOwnedSlice();
}
pub fn decode_row_id_2_1(json_text: []const u8) ?[]const u8 {
    // lightweight scan for "id":"..." without full JSON parse
    const key = "\"id\":\"";
    const start = std.mem.indexOf(u8, json_text, key) orelse return null;
    const from = start + key.len;
    const end = std.mem.indexOfScalar(u8, json_text[from..], '"') orelse return null;
    return json_text[from .. from + end];
}

pub fn schema_table_2_2_name() []const u8 { return "t_2_2"; }
pub fn schema_table_2_2_create_sql() []const u8 {
    return "CREATE TABLE IF NOT EXISTS t_2_2 (id TEXT PRIMARY KEY, kind TEXT, payload TEXT, mtime INTEGER);";
}
pub fn schema_table_2_2_insert_sql() []const u8 {
    return "INSERT OR REPLACE INTO t_2_2 (id, kind, payload, mtime) VALUES (?, ?, ?, ?);";
}
pub fn schema_table_2_2_select_sql() []const u8 {
    return "SELECT id, kind, payload, mtime FROM t_2_2 WHERE id = ?;";
}
pub fn schema_table_2_2_list_sql(limit: u32) []const u8 {
    _ = limit;
    return "SELECT id, kind, payload, mtime FROM t_2_2 ORDER BY mtime DESC LIMIT 100;";
}
pub fn encode_row_2_2(gpa: std.mem.Allocator, row: Row) ![]u8 {
    var aw: std.Io.Writer.Allocating = .init(gpa);
    errdefer aw.deinit();
    try aw.writer.writeAll("{\"id\":");
    try std.json.Stringify.value(row.id, .{}, &aw.writer);
    try aw.writer.writeAll(",\"kind\":");
    try std.json.Stringify.value(row.kind, .{}, &aw.writer);
    try aw.writer.writeAll(",\"payload\":");
    try std.json.Stringify.value(row.payload, .{}, &aw.writer);
    try aw.writer.writeAll(",\"mtime\":");
    try aw.writer.print("{d}", .{row.mtime});
    try aw.writer.writeAll("}");
    return try aw.toOwnedSlice();
}
pub fn decode_row_id_2_2(json_text: []const u8) ?[]const u8 {
    // lightweight scan for "id":"..." without full JSON parse
    const key = "\"id\":\"";
    const start = std.mem.indexOf(u8, json_text, key) orelse return null;
    const from = start + key.len;
    const end = std.mem.indexOfScalar(u8, json_text[from..], '"') orelse return null;
    return json_text[from .. from + end];
}

pub fn schema_table_2_3_name() []const u8 { return "t_2_3"; }
pub fn schema_table_2_3_create_sql() []const u8 {
    return "CREATE TABLE IF NOT EXISTS t_2_3 (id TEXT PRIMARY KEY, kind TEXT, payload TEXT, mtime INTEGER);";
}
pub fn schema_table_2_3_insert_sql() []const u8 {
    return "INSERT OR REPLACE INTO t_2_3 (id, kind, payload, mtime) VALUES (?, ?, ?, ?);";
}
pub fn schema_table_2_3_select_sql() []const u8 {
    return "SELECT id, kind, payload, mtime FROM t_2_3 WHERE id = ?;";
}
pub fn schema_table_2_3_list_sql(limit: u32) []const u8 {
    _ = limit;
    return "SELECT id, kind, payload, mtime FROM t_2_3 ORDER BY mtime DESC LIMIT 100;";
}
pub fn encode_row_2_3(gpa: std.mem.Allocator, row: Row) ![]u8 {
    var aw: std.Io.Writer.Allocating = .init(gpa);
    errdefer aw.deinit();
    try aw.writer.writeAll("{\"id\":");
    try std.json.Stringify.value(row.id, .{}, &aw.writer);
    try aw.writer.writeAll(",\"kind\":");
    try std.json.Stringify.value(row.kind, .{}, &aw.writer);
    try aw.writer.writeAll(",\"payload\":");
    try std.json.Stringify.value(row.payload, .{}, &aw.writer);
    try aw.writer.writeAll(",\"mtime\":");
    try aw.writer.print("{d}", .{row.mtime});
    try aw.writer.writeAll("}");
    return try aw.toOwnedSlice();
}
pub fn decode_row_id_2_3(json_text: []const u8) ?[]const u8 {
    // lightweight scan for "id":"..." without full JSON parse
    const key = "\"id\":\"";
    const start = std.mem.indexOf(u8, json_text, key) orelse return null;
    const from = start + key.len;
    const end = std.mem.indexOfScalar(u8, json_text[from..], '"') orelse return null;
    return json_text[from .. from + end];
}

pub fn schema_table_2_4_name() []const u8 { return "t_2_4"; }
pub fn schema_table_2_4_create_sql() []const u8 {
    return "CREATE TABLE IF NOT EXISTS t_2_4 (id TEXT PRIMARY KEY, kind TEXT, payload TEXT, mtime INTEGER);";
}
pub fn schema_table_2_4_insert_sql() []const u8 {
    return "INSERT OR REPLACE INTO t_2_4 (id, kind, payload, mtime) VALUES (?, ?, ?, ?);";
}
pub fn schema_table_2_4_select_sql() []const u8 {
    return "SELECT id, kind, payload, mtime FROM t_2_4 WHERE id = ?;";
}
pub fn schema_table_2_4_list_sql(limit: u32) []const u8 {
    _ = limit;
    return "SELECT id, kind, payload, mtime FROM t_2_4 ORDER BY mtime DESC LIMIT 100;";
}
pub fn encode_row_2_4(gpa: std.mem.Allocator, row: Row) ![]u8 {
    var aw: std.Io.Writer.Allocating = .init(gpa);
    errdefer aw.deinit();
    try aw.writer.writeAll("{\"id\":");
    try std.json.Stringify.value(row.id, .{}, &aw.writer);
    try aw.writer.writeAll(",\"kind\":");
    try std.json.Stringify.value(row.kind, .{}, &aw.writer);
    try aw.writer.writeAll(",\"payload\":");
    try std.json.Stringify.value(row.payload, .{}, &aw.writer);
    try aw.writer.writeAll(",\"mtime\":");
    try aw.writer.print("{d}", .{row.mtime});
    try aw.writer.writeAll("}");
    return try aw.toOwnedSlice();
}
pub fn decode_row_id_2_4(json_text: []const u8) ?[]const u8 {
    // lightweight scan for "id":"..." without full JSON parse
    const key = "\"id\":\"";
    const start = std.mem.indexOf(u8, json_text, key) orelse return null;
    const from = start + key.len;
    const end = std.mem.indexOfScalar(u8, json_text[from..], '"') orelse return null;
    return json_text[from .. from + end];
}

pub fn schema_table_2_5_name() []const u8 { return "t_2_5"; }
pub fn schema_table_2_5_create_sql() []const u8 {
    return "CREATE TABLE IF NOT EXISTS t_2_5 (id TEXT PRIMARY KEY, kind TEXT, payload TEXT, mtime INTEGER);";
}
pub fn schema_table_2_5_insert_sql() []const u8 {
    return "INSERT OR REPLACE INTO t_2_5 (id, kind, payload, mtime) VALUES (?, ?, ?, ?);";
}
pub fn schema_table_2_5_select_sql() []const u8 {
    return "SELECT id, kind, payload, mtime FROM t_2_5 WHERE id = ?;";
}
pub fn schema_table_2_5_list_sql(limit: u32) []const u8 {
    _ = limit;
    return "SELECT id, kind, payload, mtime FROM t_2_5 ORDER BY mtime DESC LIMIT 100;";
}
pub fn encode_row_2_5(gpa: std.mem.Allocator, row: Row) ![]u8 {
    var aw: std.Io.Writer.Allocating = .init(gpa);
    errdefer aw.deinit();
    try aw.writer.writeAll("{\"id\":");
    try std.json.Stringify.value(row.id, .{}, &aw.writer);
    try aw.writer.writeAll(",\"kind\":");
    try std.json.Stringify.value(row.kind, .{}, &aw.writer);
    try aw.writer.writeAll(",\"payload\":");
    try std.json.Stringify.value(row.payload, .{}, &aw.writer);
    try aw.writer.writeAll(",\"mtime\":");
    try aw.writer.print("{d}", .{row.mtime});
    try aw.writer.writeAll("}");
    return try aw.toOwnedSlice();
}
pub fn decode_row_id_2_5(json_text: []const u8) ?[]const u8 {
    // lightweight scan for "id":"..." without full JSON parse
    const key = "\"id\":\"";
    const start = std.mem.indexOf(u8, json_text, key) orelse return null;
    const from = start + key.len;
    const end = std.mem.indexOfScalar(u8, json_text[from..], '"') orelse return null;
    return json_text[from .. from + end];
}

pub fn schema_table_2_6_name() []const u8 { return "t_2_6"; }
pub fn schema_table_2_6_create_sql() []const u8 {
    return "CREATE TABLE IF NOT EXISTS t_2_6 (id TEXT PRIMARY KEY, kind TEXT, payload TEXT, mtime INTEGER);";
}
pub fn schema_table_2_6_insert_sql() []const u8 {
    return "INSERT OR REPLACE INTO t_2_6 (id, kind, payload, mtime) VALUES (?, ?, ?, ?);";
}
pub fn schema_table_2_6_select_sql() []const u8 {
    return "SELECT id, kind, payload, mtime FROM t_2_6 WHERE id = ?;";
}
pub fn schema_table_2_6_list_sql(limit: u32) []const u8 {
    _ = limit;
    return "SELECT id, kind, payload, mtime FROM t_2_6 ORDER BY mtime DESC LIMIT 100;";
}
pub fn encode_row_2_6(gpa: std.mem.Allocator, row: Row) ![]u8 {
    var aw: std.Io.Writer.Allocating = .init(gpa);
    errdefer aw.deinit();
    try aw.writer.writeAll("{\"id\":");
    try std.json.Stringify.value(row.id, .{}, &aw.writer);
    try aw.writer.writeAll(",\"kind\":");
    try std.json.Stringify.value(row.kind, .{}, &aw.writer);
    try aw.writer.writeAll(",\"payload\":");
    try std.json.Stringify.value(row.payload, .{}, &aw.writer);
    try aw.writer.writeAll(",\"mtime\":");
    try aw.writer.print("{d}", .{row.mtime});
    try aw.writer.writeAll("}");
    return try aw.toOwnedSlice();
}
pub fn decode_row_id_2_6(json_text: []const u8) ?[]const u8 {
    // lightweight scan for "id":"..." without full JSON parse
    const key = "\"id\":\"";
    const start = std.mem.indexOf(u8, json_text, key) orelse return null;
    const from = start + key.len;
    const end = std.mem.indexOfScalar(u8, json_text[from..], '"') orelse return null;
    return json_text[from .. from + end];
}

pub fn schema_table_2_7_name() []const u8 { return "t_2_7"; }
pub fn schema_table_2_7_create_sql() []const u8 {
    return "CREATE TABLE IF NOT EXISTS t_2_7 (id TEXT PRIMARY KEY, kind TEXT, payload TEXT, mtime INTEGER);";
}
pub fn schema_table_2_7_insert_sql() []const u8 {
    return "INSERT OR REPLACE INTO t_2_7 (id, kind, payload, mtime) VALUES (?, ?, ?, ?);";
}
pub fn schema_table_2_7_select_sql() []const u8 {
    return "SELECT id, kind, payload, mtime FROM t_2_7 WHERE id = ?;";
}
pub fn schema_table_2_7_list_sql(limit: u32) []const u8 {
    _ = limit;
    return "SELECT id, kind, payload, mtime FROM t_2_7 ORDER BY mtime DESC LIMIT 100;";
}
pub fn encode_row_2_7(gpa: std.mem.Allocator, row: Row) ![]u8 {
    var aw: std.Io.Writer.Allocating = .init(gpa);
    errdefer aw.deinit();
    try aw.writer.writeAll("{\"id\":");
    try std.json.Stringify.value(row.id, .{}, &aw.writer);
    try aw.writer.writeAll(",\"kind\":");
    try std.json.Stringify.value(row.kind, .{}, &aw.writer);
    try aw.writer.writeAll(",\"payload\":");
    try std.json.Stringify.value(row.payload, .{}, &aw.writer);
    try aw.writer.writeAll(",\"mtime\":");
    try aw.writer.print("{d}", .{row.mtime});
    try aw.writer.writeAll("}");
    return try aw.toOwnedSlice();
}
pub fn decode_row_id_2_7(json_text: []const u8) ?[]const u8 {
    // lightweight scan for "id":"..." without full JSON parse
    const key = "\"id\":\"";
    const start = std.mem.indexOf(u8, json_text, key) orelse return null;
    const from = start + key.len;
    const end = std.mem.indexOfScalar(u8, json_text[from..], '"') orelse return null;
    return json_text[from .. from + end];
}

pub fn schema_table_2_8_name() []const u8 { return "t_2_8"; }
pub fn schema_table_2_8_create_sql() []const u8 {
    return "CREATE TABLE IF NOT EXISTS t_2_8 (id TEXT PRIMARY KEY, kind TEXT, payload TEXT, mtime INTEGER);";
}
pub fn schema_table_2_8_insert_sql() []const u8 {
    return "INSERT OR REPLACE INTO t_2_8 (id, kind, payload, mtime) VALUES (?, ?, ?, ?);";
}
pub fn schema_table_2_8_select_sql() []const u8 {
    return "SELECT id, kind, payload, mtime FROM t_2_8 WHERE id = ?;";
}
pub fn schema_table_2_8_list_sql(limit: u32) []const u8 {
    _ = limit;
    return "SELECT id, kind, payload, mtime FROM t_2_8 ORDER BY mtime DESC LIMIT 100;";
}
pub fn encode_row_2_8(gpa: std.mem.Allocator, row: Row) ![]u8 {
    var aw: std.Io.Writer.Allocating = .init(gpa);
    errdefer aw.deinit();
    try aw.writer.writeAll("{\"id\":");
    try std.json.Stringify.value(row.id, .{}, &aw.writer);
    try aw.writer.writeAll(",\"kind\":");
    try std.json.Stringify.value(row.kind, .{}, &aw.writer);
    try aw.writer.writeAll(",\"payload\":");
    try std.json.Stringify.value(row.payload, .{}, &aw.writer);
    try aw.writer.writeAll(",\"mtime\":");
    try aw.writer.print("{d}", .{row.mtime});
    try aw.writer.writeAll("}");
    return try aw.toOwnedSlice();
}
pub fn decode_row_id_2_8(json_text: []const u8) ?[]const u8 {
    // lightweight scan for "id":"..." without full JSON parse
    const key = "\"id\":\"";
    const start = std.mem.indexOf(u8, json_text, key) orelse return null;
    const from = start + key.len;
    const end = std.mem.indexOfScalar(u8, json_text[from..], '"') orelse return null;
    return json_text[from .. from + end];
}

pub fn schema_table_2_9_name() []const u8 { return "t_2_9"; }
pub fn schema_table_2_9_create_sql() []const u8 {
    return "CREATE TABLE IF NOT EXISTS t_2_9 (id TEXT PRIMARY KEY, kind TEXT, payload TEXT, mtime INTEGER);";
}
pub fn schema_table_2_9_insert_sql() []const u8 {
    return "INSERT OR REPLACE INTO t_2_9 (id, kind, payload, mtime) VALUES (?, ?, ?, ?);";
}
pub fn schema_table_2_9_select_sql() []const u8 {
    return "SELECT id, kind, payload, mtime FROM t_2_9 WHERE id = ?;";
}
pub fn schema_table_2_9_list_sql(limit: u32) []const u8 {
    _ = limit;
    return "SELECT id, kind, payload, mtime FROM t_2_9 ORDER BY mtime DESC LIMIT 100;";
}
pub fn encode_row_2_9(gpa: std.mem.Allocator, row: Row) ![]u8 {
    var aw: std.Io.Writer.Allocating = .init(gpa);
    errdefer aw.deinit();
    try aw.writer.writeAll("{\"id\":");
    try std.json.Stringify.value(row.id, .{}, &aw.writer);
    try aw.writer.writeAll(",\"kind\":");
    try std.json.Stringify.value(row.kind, .{}, &aw.writer);
    try aw.writer.writeAll(",\"payload\":");
    try std.json.Stringify.value(row.payload, .{}, &aw.writer);
    try aw.writer.writeAll(",\"mtime\":");
    try aw.writer.print("{d}", .{row.mtime});
    try aw.writer.writeAll("}");
    return try aw.toOwnedSlice();
}
pub fn decode_row_id_2_9(json_text: []const u8) ?[]const u8 {
    // lightweight scan for "id":"..." without full JSON parse
    const key = "\"id\":\"";
    const start = std.mem.indexOf(u8, json_text, key) orelse return null;
    const from = start + key.len;
    const end = std.mem.indexOfScalar(u8, json_text[from..], '"') orelse return null;
    return json_text[from .. from + end];
}

pub fn schema_table_2_10_name() []const u8 { return "t_2_10"; }
pub fn schema_table_2_10_create_sql() []const u8 {
    return "CREATE TABLE IF NOT EXISTS t_2_10 (id TEXT PRIMARY KEY, kind TEXT, payload TEXT, mtime INTEGER);";
}
pub fn schema_table_2_10_insert_sql() []const u8 {
    return "INSERT OR REPLACE INTO t_2_10 (id, kind, payload, mtime) VALUES (?, ?, ?, ?);";
}
pub fn schema_table_2_10_select_sql() []const u8 {
    return "SELECT id, kind, payload, mtime FROM t_2_10 WHERE id = ?;";
}
pub fn schema_table_2_10_list_sql(limit: u32) []const u8 {
    _ = limit;
    return "SELECT id, kind, payload, mtime FROM t_2_10 ORDER BY mtime DESC LIMIT 100;";
}
pub fn encode_row_2_10(gpa: std.mem.Allocator, row: Row) ![]u8 {
    var aw: std.Io.Writer.Allocating = .init(gpa);
    errdefer aw.deinit();
    try aw.writer.writeAll("{\"id\":");
    try std.json.Stringify.value(row.id, .{}, &aw.writer);
    try aw.writer.writeAll(",\"kind\":");
    try std.json.Stringify.value(row.kind, .{}, &aw.writer);
    try aw.writer.writeAll(",\"payload\":");
    try std.json.Stringify.value(row.payload, .{}, &aw.writer);
    try aw.writer.writeAll(",\"mtime\":");
    try aw.writer.print("{d}", .{row.mtime});
    try aw.writer.writeAll("}");
    return try aw.toOwnedSlice();
}
pub fn decode_row_id_2_10(json_text: []const u8) ?[]const u8 {
    // lightweight scan for "id":"..." without full JSON parse
    const key = "\"id\":\"";
    const start = std.mem.indexOf(u8, json_text, key) orelse return null;
    const from = start + key.len;
    const end = std.mem.indexOfScalar(u8, json_text[from..], '"') orelse return null;
    return json_text[from .. from + end];
}

pub fn schema_table_2_11_name() []const u8 { return "t_2_11"; }
pub fn schema_table_2_11_create_sql() []const u8 {
    return "CREATE TABLE IF NOT EXISTS t_2_11 (id TEXT PRIMARY KEY, kind TEXT, payload TEXT, mtime INTEGER);";
}
pub fn schema_table_2_11_insert_sql() []const u8 {
    return "INSERT OR REPLACE INTO t_2_11 (id, kind, payload, mtime) VALUES (?, ?, ?, ?);";
}
pub fn schema_table_2_11_select_sql() []const u8 {
    return "SELECT id, kind, payload, mtime FROM t_2_11 WHERE id = ?;";
}
pub fn schema_table_2_11_list_sql(limit: u32) []const u8 {
    _ = limit;
    return "SELECT id, kind, payload, mtime FROM t_2_11 ORDER BY mtime DESC LIMIT 100;";
}
pub fn encode_row_2_11(gpa: std.mem.Allocator, row: Row) ![]u8 {
    var aw: std.Io.Writer.Allocating = .init(gpa);
    errdefer aw.deinit();
    try aw.writer.writeAll("{\"id\":");
    try std.json.Stringify.value(row.id, .{}, &aw.writer);
    try aw.writer.writeAll(",\"kind\":");
    try std.json.Stringify.value(row.kind, .{}, &aw.writer);
    try aw.writer.writeAll(",\"payload\":");
    try std.json.Stringify.value(row.payload, .{}, &aw.writer);
    try aw.writer.writeAll(",\"mtime\":");
    try aw.writer.print("{d}", .{row.mtime});
    try aw.writer.writeAll("}");
    return try aw.toOwnedSlice();
}
pub fn decode_row_id_2_11(json_text: []const u8) ?[]const u8 {
    // lightweight scan for "id":"..." without full JSON parse
    const key = "\"id\":\"";
    const start = std.mem.indexOf(u8, json_text, key) orelse return null;
    const from = start + key.len;
    const end = std.mem.indexOfScalar(u8, json_text[from..], '"') orelse return null;
    return json_text[from .. from + end];
}

pub fn schema_table_2_12_name() []const u8 { return "t_2_12"; }
pub fn schema_table_2_12_create_sql() []const u8 {
    return "CREATE TABLE IF NOT EXISTS t_2_12 (id TEXT PRIMARY KEY, kind TEXT, payload TEXT, mtime INTEGER);";
}
pub fn schema_table_2_12_insert_sql() []const u8 {
    return "INSERT OR REPLACE INTO t_2_12 (id, kind, payload, mtime) VALUES (?, ?, ?, ?);";
}
pub fn schema_table_2_12_select_sql() []const u8 {
    return "SELECT id, kind, payload, mtime FROM t_2_12 WHERE id = ?;";
}
pub fn schema_table_2_12_list_sql(limit: u32) []const u8 {
    _ = limit;
    return "SELECT id, kind, payload, mtime FROM t_2_12 ORDER BY mtime DESC LIMIT 100;";
}
pub fn encode_row_2_12(gpa: std.mem.Allocator, row: Row) ![]u8 {
    var aw: std.Io.Writer.Allocating = .init(gpa);
    errdefer aw.deinit();
    try aw.writer.writeAll("{\"id\":");
    try std.json.Stringify.value(row.id, .{}, &aw.writer);
    try aw.writer.writeAll(",\"kind\":");
    try std.json.Stringify.value(row.kind, .{}, &aw.writer);
    try aw.writer.writeAll(",\"payload\":");
    try std.json.Stringify.value(row.payload, .{}, &aw.writer);
    try aw.writer.writeAll(",\"mtime\":");
    try aw.writer.print("{d}", .{row.mtime});
    try aw.writer.writeAll("}");
    return try aw.toOwnedSlice();
}
pub fn decode_row_id_2_12(json_text: []const u8) ?[]const u8 {
    // lightweight scan for "id":"..." without full JSON parse
    const key = "\"id\":\"";
    const start = std.mem.indexOf(u8, json_text, key) orelse return null;
    const from = start + key.len;
    const end = std.mem.indexOfScalar(u8, json_text[from..], '"') orelse return null;
    return json_text[from .. from + end];
}

pub fn schema_table_2_13_name() []const u8 { return "t_2_13"; }
pub fn schema_table_2_13_create_sql() []const u8 {
    return "CREATE TABLE IF NOT EXISTS t_2_13 (id TEXT PRIMARY KEY, kind TEXT, payload TEXT, mtime INTEGER);";
}
pub fn schema_table_2_13_insert_sql() []const u8 {
    return "INSERT OR REPLACE INTO t_2_13 (id, kind, payload, mtime) VALUES (?, ?, ?, ?);";
}
pub fn schema_table_2_13_select_sql() []const u8 {
    return "SELECT id, kind, payload, mtime FROM t_2_13 WHERE id = ?;";
}
pub fn schema_table_2_13_list_sql(limit: u32) []const u8 {
    _ = limit;
    return "SELECT id, kind, payload, mtime FROM t_2_13 ORDER BY mtime DESC LIMIT 100;";
}
pub fn encode_row_2_13(gpa: std.mem.Allocator, row: Row) ![]u8 {
    var aw: std.Io.Writer.Allocating = .init(gpa);
    errdefer aw.deinit();
    try aw.writer.writeAll("{\"id\":");
    try std.json.Stringify.value(row.id, .{}, &aw.writer);
    try aw.writer.writeAll(",\"kind\":");
    try std.json.Stringify.value(row.kind, .{}, &aw.writer);
    try aw.writer.writeAll(",\"payload\":");
    try std.json.Stringify.value(row.payload, .{}, &aw.writer);
    try aw.writer.writeAll(",\"mtime\":");
    try aw.writer.print("{d}", .{row.mtime});
    try aw.writer.writeAll("}");
    return try aw.toOwnedSlice();
}
pub fn decode_row_id_2_13(json_text: []const u8) ?[]const u8 {
    // lightweight scan for "id":"..." without full JSON parse
    const key = "\"id\":\"";
    const start = std.mem.indexOf(u8, json_text, key) orelse return null;
    const from = start + key.len;
    const end = std.mem.indexOfScalar(u8, json_text[from..], '"') orelse return null;
    return json_text[from .. from + end];
}

pub fn schema_table_2_14_name() []const u8 { return "t_2_14"; }
pub fn schema_table_2_14_create_sql() []const u8 {
    return "CREATE TABLE IF NOT EXISTS t_2_14 (id TEXT PRIMARY KEY, kind TEXT, payload TEXT, mtime INTEGER);";
}
pub fn schema_table_2_14_insert_sql() []const u8 {
    return "INSERT OR REPLACE INTO t_2_14 (id, kind, payload, mtime) VALUES (?, ?, ?, ?);";
}
pub fn schema_table_2_14_select_sql() []const u8 {
    return "SELECT id, kind, payload, mtime FROM t_2_14 WHERE id = ?;";
}
pub fn schema_table_2_14_list_sql(limit: u32) []const u8 {
    _ = limit;
    return "SELECT id, kind, payload, mtime FROM t_2_14 ORDER BY mtime DESC LIMIT 100;";
}
pub fn encode_row_2_14(gpa: std.mem.Allocator, row: Row) ![]u8 {
    var aw: std.Io.Writer.Allocating = .init(gpa);
    errdefer aw.deinit();
    try aw.writer.writeAll("{\"id\":");
    try std.json.Stringify.value(row.id, .{}, &aw.writer);
    try aw.writer.writeAll(",\"kind\":");
    try std.json.Stringify.value(row.kind, .{}, &aw.writer);
    try aw.writer.writeAll(",\"payload\":");
    try std.json.Stringify.value(row.payload, .{}, &aw.writer);
    try aw.writer.writeAll(",\"mtime\":");
    try aw.writer.print("{d}", .{row.mtime});
    try aw.writer.writeAll("}");
    return try aw.toOwnedSlice();
}
pub fn decode_row_id_2_14(json_text: []const u8) ?[]const u8 {
    // lightweight scan for "id":"..." without full JSON parse
    const key = "\"id\":\"";
    const start = std.mem.indexOf(u8, json_text, key) orelse return null;
    const from = start + key.len;
    const end = std.mem.indexOfScalar(u8, json_text[from..], '"') orelse return null;
    return json_text[from .. from + end];
}

pub fn schema_table_2_15_name() []const u8 { return "t_2_15"; }
pub fn schema_table_2_15_create_sql() []const u8 {
    return "CREATE TABLE IF NOT EXISTS t_2_15 (id TEXT PRIMARY KEY, kind TEXT, payload TEXT, mtime INTEGER);";
}
pub fn schema_table_2_15_insert_sql() []const u8 {
    return "INSERT OR REPLACE INTO t_2_15 (id, kind, payload, mtime) VALUES (?, ?, ?, ?);";
}
pub fn schema_table_2_15_select_sql() []const u8 {
    return "SELECT id, kind, payload, mtime FROM t_2_15 WHERE id = ?;";
}
pub fn schema_table_2_15_list_sql(limit: u32) []const u8 {
    _ = limit;
    return "SELECT id, kind, payload, mtime FROM t_2_15 ORDER BY mtime DESC LIMIT 100;";
}
pub fn encode_row_2_15(gpa: std.mem.Allocator, row: Row) ![]u8 {
    var aw: std.Io.Writer.Allocating = .init(gpa);
    errdefer aw.deinit();
    try aw.writer.writeAll("{\"id\":");
    try std.json.Stringify.value(row.id, .{}, &aw.writer);
    try aw.writer.writeAll(",\"kind\":");
    try std.json.Stringify.value(row.kind, .{}, &aw.writer);
    try aw.writer.writeAll(",\"payload\":");
    try std.json.Stringify.value(row.payload, .{}, &aw.writer);
    try aw.writer.writeAll(",\"mtime\":");
    try aw.writer.print("{d}", .{row.mtime});
    try aw.writer.writeAll("}");
    return try aw.toOwnedSlice();
}
pub fn decode_row_id_2_15(json_text: []const u8) ?[]const u8 {
    // lightweight scan for "id":"..." without full JSON parse
    const key = "\"id\":\"";
    const start = std.mem.indexOf(u8, json_text, key) orelse return null;
    const from = start + key.len;
    const end = std.mem.indexOfScalar(u8, json_text[from..], '"') orelse return null;
    return json_text[from .. from + end];
}

pub fn schema_table_2_16_name() []const u8 { return "t_2_16"; }
pub fn schema_table_2_16_create_sql() []const u8 {
    return "CREATE TABLE IF NOT EXISTS t_2_16 (id TEXT PRIMARY KEY, kind TEXT, payload TEXT, mtime INTEGER);";
}
pub fn schema_table_2_16_insert_sql() []const u8 {
    return "INSERT OR REPLACE INTO t_2_16 (id, kind, payload, mtime) VALUES (?, ?, ?, ?);";
}
pub fn schema_table_2_16_select_sql() []const u8 {
    return "SELECT id, kind, payload, mtime FROM t_2_16 WHERE id = ?;";
}
pub fn schema_table_2_16_list_sql(limit: u32) []const u8 {
    _ = limit;
    return "SELECT id, kind, payload, mtime FROM t_2_16 ORDER BY mtime DESC LIMIT 100;";
}
pub fn encode_row_2_16(gpa: std.mem.Allocator, row: Row) ![]u8 {
    var aw: std.Io.Writer.Allocating = .init(gpa);
    errdefer aw.deinit();
    try aw.writer.writeAll("{\"id\":");
    try std.json.Stringify.value(row.id, .{}, &aw.writer);
    try aw.writer.writeAll(",\"kind\":");
    try std.json.Stringify.value(row.kind, .{}, &aw.writer);
    try aw.writer.writeAll(",\"payload\":");
    try std.json.Stringify.value(row.payload, .{}, &aw.writer);
    try aw.writer.writeAll(",\"mtime\":");
    try aw.writer.print("{d}", .{row.mtime});
    try aw.writer.writeAll("}");
    return try aw.toOwnedSlice();
}
pub fn decode_row_id_2_16(json_text: []const u8) ?[]const u8 {
    // lightweight scan for "id":"..." without full JSON parse
    const key = "\"id\":\"";
    const start = std.mem.indexOf(u8, json_text, key) orelse return null;
    const from = start + key.len;
    const end = std.mem.indexOfScalar(u8, json_text[from..], '"') orelse return null;
    return json_text[from .. from + end];
}

pub fn schema_table_2_17_name() []const u8 { return "t_2_17"; }
pub fn schema_table_2_17_create_sql() []const u8 {
    return "CREATE TABLE IF NOT EXISTS t_2_17 (id TEXT PRIMARY KEY, kind TEXT, payload TEXT, mtime INTEGER);";
}
pub fn schema_table_2_17_insert_sql() []const u8 {
    return "INSERT OR REPLACE INTO t_2_17 (id, kind, payload, mtime) VALUES (?, ?, ?, ?);";
}
pub fn schema_table_2_17_select_sql() []const u8 {
    return "SELECT id, kind, payload, mtime FROM t_2_17 WHERE id = ?;";
}
pub fn schema_table_2_17_list_sql(limit: u32) []const u8 {
    _ = limit;
    return "SELECT id, kind, payload, mtime FROM t_2_17 ORDER BY mtime DESC LIMIT 100;";
}
pub fn encode_row_2_17(gpa: std.mem.Allocator, row: Row) ![]u8 {
    var aw: std.Io.Writer.Allocating = .init(gpa);
    errdefer aw.deinit();
    try aw.writer.writeAll("{\"id\":");
    try std.json.Stringify.value(row.id, .{}, &aw.writer);
    try aw.writer.writeAll(",\"kind\":");
    try std.json.Stringify.value(row.kind, .{}, &aw.writer);
    try aw.writer.writeAll(",\"payload\":");
    try std.json.Stringify.value(row.payload, .{}, &aw.writer);
    try aw.writer.writeAll(",\"mtime\":");
    try aw.writer.print("{d}", .{row.mtime});
    try aw.writer.writeAll("}");
    return try aw.toOwnedSlice();
}
pub fn decode_row_id_2_17(json_text: []const u8) ?[]const u8 {
    // lightweight scan for "id":"..." without full JSON parse
    const key = "\"id\":\"";
    const start = std.mem.indexOf(u8, json_text, key) orelse return null;
    const from = start + key.len;
    const end = std.mem.indexOfScalar(u8, json_text[from..], '"') orelse return null;
    return json_text[from .. from + end];
}

pub fn schema_table_2_18_name() []const u8 { return "t_2_18"; }
pub fn schema_table_2_18_create_sql() []const u8 {
    return "CREATE TABLE IF NOT EXISTS t_2_18 (id TEXT PRIMARY KEY, kind TEXT, payload TEXT, mtime INTEGER);";
}
pub fn schema_table_2_18_insert_sql() []const u8 {
    return "INSERT OR REPLACE INTO t_2_18 (id, kind, payload, mtime) VALUES (?, ?, ?, ?);";
}
pub fn schema_table_2_18_select_sql() []const u8 {
    return "SELECT id, kind, payload, mtime FROM t_2_18 WHERE id = ?;";
}
pub fn schema_table_2_18_list_sql(limit: u32) []const u8 {
    _ = limit;
    return "SELECT id, kind, payload, mtime FROM t_2_18 ORDER BY mtime DESC LIMIT 100;";
}
pub fn encode_row_2_18(gpa: std.mem.Allocator, row: Row) ![]u8 {
    var aw: std.Io.Writer.Allocating = .init(gpa);
    errdefer aw.deinit();
    try aw.writer.writeAll("{\"id\":");
    try std.json.Stringify.value(row.id, .{}, &aw.writer);
    try aw.writer.writeAll(",\"kind\":");
    try std.json.Stringify.value(row.kind, .{}, &aw.writer);
    try aw.writer.writeAll(",\"payload\":");
    try std.json.Stringify.value(row.payload, .{}, &aw.writer);
    try aw.writer.writeAll(",\"mtime\":");
    try aw.writer.print("{d}", .{row.mtime});
    try aw.writer.writeAll("}");
    return try aw.toOwnedSlice();
}
pub fn decode_row_id_2_18(json_text: []const u8) ?[]const u8 {
    // lightweight scan for "id":"..." without full JSON parse
    const key = "\"id\":\"";
    const start = std.mem.indexOf(u8, json_text, key) orelse return null;
    const from = start + key.len;
    const end = std.mem.indexOfScalar(u8, json_text[from..], '"') orelse return null;
    return json_text[from .. from + end];
}

pub fn schema_table_2_19_name() []const u8 { return "t_2_19"; }
pub fn schema_table_2_19_create_sql() []const u8 {
    return "CREATE TABLE IF NOT EXISTS t_2_19 (id TEXT PRIMARY KEY, kind TEXT, payload TEXT, mtime INTEGER);";
}
pub fn schema_table_2_19_insert_sql() []const u8 {
    return "INSERT OR REPLACE INTO t_2_19 (id, kind, payload, mtime) VALUES (?, ?, ?, ?);";
}
pub fn schema_table_2_19_select_sql() []const u8 {
    return "SELECT id, kind, payload, mtime FROM t_2_19 WHERE id = ?;";
}
pub fn schema_table_2_19_list_sql(limit: u32) []const u8 {
    _ = limit;
    return "SELECT id, kind, payload, mtime FROM t_2_19 ORDER BY mtime DESC LIMIT 100;";
}
pub fn encode_row_2_19(gpa: std.mem.Allocator, row: Row) ![]u8 {
    var aw: std.Io.Writer.Allocating = .init(gpa);
    errdefer aw.deinit();
    try aw.writer.writeAll("{\"id\":");
    try std.json.Stringify.value(row.id, .{}, &aw.writer);
    try aw.writer.writeAll(",\"kind\":");
    try std.json.Stringify.value(row.kind, .{}, &aw.writer);
    try aw.writer.writeAll(",\"payload\":");
    try std.json.Stringify.value(row.payload, .{}, &aw.writer);
    try aw.writer.writeAll(",\"mtime\":");
    try aw.writer.print("{d}", .{row.mtime});
    try aw.writer.writeAll("}");
    return try aw.toOwnedSlice();
}
pub fn decode_row_id_2_19(json_text: []const u8) ?[]const u8 {
    // lightweight scan for "id":"..." without full JSON parse
    const key = "\"id\":\"";
    const start = std.mem.indexOf(u8, json_text, key) orelse return null;
    const from = start + key.len;
    const end = std.mem.indexOfScalar(u8, json_text[from..], '"') orelse return null;
    return json_text[from .. from + end];
}

pub fn schema_table_2_20_name() []const u8 { return "t_2_20"; }
pub fn schema_table_2_20_create_sql() []const u8 {
    return "CREATE TABLE IF NOT EXISTS t_2_20 (id TEXT PRIMARY KEY, kind TEXT, payload TEXT, mtime INTEGER);";
}
pub fn schema_table_2_20_insert_sql() []const u8 {
    return "INSERT OR REPLACE INTO t_2_20 (id, kind, payload, mtime) VALUES (?, ?, ?, ?);";
}
pub fn schema_table_2_20_select_sql() []const u8 {
    return "SELECT id, kind, payload, mtime FROM t_2_20 WHERE id = ?;";
}
pub fn schema_table_2_20_list_sql(limit: u32) []const u8 {
    _ = limit;
    return "SELECT id, kind, payload, mtime FROM t_2_20 ORDER BY mtime DESC LIMIT 100;";
}
pub fn encode_row_2_20(gpa: std.mem.Allocator, row: Row) ![]u8 {
    var aw: std.Io.Writer.Allocating = .init(gpa);
    errdefer aw.deinit();
    try aw.writer.writeAll("{\"id\":");
    try std.json.Stringify.value(row.id, .{}, &aw.writer);
    try aw.writer.writeAll(",\"kind\":");
    try std.json.Stringify.value(row.kind, .{}, &aw.writer);
    try aw.writer.writeAll(",\"payload\":");
    try std.json.Stringify.value(row.payload, .{}, &aw.writer);
    try aw.writer.writeAll(",\"mtime\":");
    try aw.writer.print("{d}", .{row.mtime});
    try aw.writer.writeAll("}");
    return try aw.toOwnedSlice();
}
pub fn decode_row_id_2_20(json_text: []const u8) ?[]const u8 {
    // lightweight scan for "id":"..." without full JSON parse
    const key = "\"id\":\"";
    const start = std.mem.indexOf(u8, json_text, key) orelse return null;
    const from = start + key.len;
    const end = std.mem.indexOfScalar(u8, json_text[from..], '"') orelse return null;
    return json_text[from .. from + end];
}

pub fn schema_table_2_21_name() []const u8 { return "t_2_21"; }
pub fn schema_table_2_21_create_sql() []const u8 {
    return "CREATE TABLE IF NOT EXISTS t_2_21 (id TEXT PRIMARY KEY, kind TEXT, payload TEXT, mtime INTEGER);";
}
pub fn schema_table_2_21_insert_sql() []const u8 {
    return "INSERT OR REPLACE INTO t_2_21 (id, kind, payload, mtime) VALUES (?, ?, ?, ?);";
}
pub fn schema_table_2_21_select_sql() []const u8 {
    return "SELECT id, kind, payload, mtime FROM t_2_21 WHERE id = ?;";
}
pub fn schema_table_2_21_list_sql(limit: u32) []const u8 {
    _ = limit;
    return "SELECT id, kind, payload, mtime FROM t_2_21 ORDER BY mtime DESC LIMIT 100;";
}
pub fn encode_row_2_21(gpa: std.mem.Allocator, row: Row) ![]u8 {
    var aw: std.Io.Writer.Allocating = .init(gpa);
    errdefer aw.deinit();
    try aw.writer.writeAll("{\"id\":");
    try std.json.Stringify.value(row.id, .{}, &aw.writer);
    try aw.writer.writeAll(",\"kind\":");
    try std.json.Stringify.value(row.kind, .{}, &aw.writer);
    try aw.writer.writeAll(",\"payload\":");
    try std.json.Stringify.value(row.payload, .{}, &aw.writer);
    try aw.writer.writeAll(",\"mtime\":");
    try aw.writer.print("{d}", .{row.mtime});
    try aw.writer.writeAll("}");
    return try aw.toOwnedSlice();
}
pub fn decode_row_id_2_21(json_text: []const u8) ?[]const u8 {
    // lightweight scan for "id":"..." without full JSON parse
    const key = "\"id\":\"";
    const start = std.mem.indexOf(u8, json_text, key) orelse return null;
    const from = start + key.len;
    const end = std.mem.indexOfScalar(u8, json_text[from..], '"') orelse return null;
    return json_text[from .. from + end];
}

pub fn schema_table_2_22_name() []const u8 { return "t_2_22"; }
pub fn schema_table_2_22_create_sql() []const u8 {
    return "CREATE TABLE IF NOT EXISTS t_2_22 (id TEXT PRIMARY KEY, kind TEXT, payload TEXT, mtime INTEGER);";
}
pub fn schema_table_2_22_insert_sql() []const u8 {
    return "INSERT OR REPLACE INTO t_2_22 (id, kind, payload, mtime) VALUES (?, ?, ?, ?);";
}
pub fn schema_table_2_22_select_sql() []const u8 {
    return "SELECT id, kind, payload, mtime FROM t_2_22 WHERE id = ?;";
}
pub fn schema_table_2_22_list_sql(limit: u32) []const u8 {
    _ = limit;
    return "SELECT id, kind, payload, mtime FROM t_2_22 ORDER BY mtime DESC LIMIT 100;";
}
pub fn encode_row_2_22(gpa: std.mem.Allocator, row: Row) ![]u8 {
    var aw: std.Io.Writer.Allocating = .init(gpa);
    errdefer aw.deinit();
    try aw.writer.writeAll("{\"id\":");
    try std.json.Stringify.value(row.id, .{}, &aw.writer);
    try aw.writer.writeAll(",\"kind\":");
    try std.json.Stringify.value(row.kind, .{}, &aw.writer);
    try aw.writer.writeAll(",\"payload\":");
    try std.json.Stringify.value(row.payload, .{}, &aw.writer);
    try aw.writer.writeAll(",\"mtime\":");
    try aw.writer.print("{d}", .{row.mtime});
    try aw.writer.writeAll("}");
    return try aw.toOwnedSlice();
}
pub fn decode_row_id_2_22(json_text: []const u8) ?[]const u8 {
    // lightweight scan for "id":"..." without full JSON parse
    const key = "\"id\":\"";
    const start = std.mem.indexOf(u8, json_text, key) orelse return null;
    const from = start + key.len;
    const end = std.mem.indexOfScalar(u8, json_text[from..], '"') orelse return null;
    return json_text[from .. from + end];
}

pub fn schema_table_2_23_name() []const u8 { return "t_2_23"; }
pub fn schema_table_2_23_create_sql() []const u8 {
    return "CREATE TABLE IF NOT EXISTS t_2_23 (id TEXT PRIMARY KEY, kind TEXT, payload TEXT, mtime INTEGER);";
}
pub fn schema_table_2_23_insert_sql() []const u8 {
    return "INSERT OR REPLACE INTO t_2_23 (id, kind, payload, mtime) VALUES (?, ?, ?, ?);";
}
pub fn schema_table_2_23_select_sql() []const u8 {
    return "SELECT id, kind, payload, mtime FROM t_2_23 WHERE id = ?;";
}
pub fn schema_table_2_23_list_sql(limit: u32) []const u8 {
    _ = limit;
    return "SELECT id, kind, payload, mtime FROM t_2_23 ORDER BY mtime DESC LIMIT 100;";
}
pub fn encode_row_2_23(gpa: std.mem.Allocator, row: Row) ![]u8 {
    var aw: std.Io.Writer.Allocating = .init(gpa);
    errdefer aw.deinit();
    try aw.writer.writeAll("{\"id\":");
    try std.json.Stringify.value(row.id, .{}, &aw.writer);
    try aw.writer.writeAll(",\"kind\":");
    try std.json.Stringify.value(row.kind, .{}, &aw.writer);
    try aw.writer.writeAll(",\"payload\":");
    try std.json.Stringify.value(row.payload, .{}, &aw.writer);
    try aw.writer.writeAll(",\"mtime\":");
    try aw.writer.print("{d}", .{row.mtime});
    try aw.writer.writeAll("}");
    return try aw.toOwnedSlice();
}
pub fn decode_row_id_2_23(json_text: []const u8) ?[]const u8 {
    // lightweight scan for "id":"..." without full JSON parse
    const key = "\"id\":\"";
    const start = std.mem.indexOf(u8, json_text, key) orelse return null;
    const from = start + key.len;
    const end = std.mem.indexOfScalar(u8, json_text[from..], '"') orelse return null;
    return json_text[from .. from + end];
}

pub fn schema_table_2_24_name() []const u8 { return "t_2_24"; }
pub fn schema_table_2_24_create_sql() []const u8 {
    return "CREATE TABLE IF NOT EXISTS t_2_24 (id TEXT PRIMARY KEY, kind TEXT, payload TEXT, mtime INTEGER);";
}
pub fn schema_table_2_24_insert_sql() []const u8 {
    return "INSERT OR REPLACE INTO t_2_24 (id, kind, payload, mtime) VALUES (?, ?, ?, ?);";
}
pub fn schema_table_2_24_select_sql() []const u8 {
    return "SELECT id, kind, payload, mtime FROM t_2_24 WHERE id = ?;";
}
pub fn schema_table_2_24_list_sql(limit: u32) []const u8 {
    _ = limit;
    return "SELECT id, kind, payload, mtime FROM t_2_24 ORDER BY mtime DESC LIMIT 100;";
}
pub fn encode_row_2_24(gpa: std.mem.Allocator, row: Row) ![]u8 {
    var aw: std.Io.Writer.Allocating = .init(gpa);
    errdefer aw.deinit();
    try aw.writer.writeAll("{\"id\":");
    try std.json.Stringify.value(row.id, .{}, &aw.writer);
    try aw.writer.writeAll(",\"kind\":");
    try std.json.Stringify.value(row.kind, .{}, &aw.writer);
    try aw.writer.writeAll(",\"payload\":");
    try std.json.Stringify.value(row.payload, .{}, &aw.writer);
    try aw.writer.writeAll(",\"mtime\":");
    try aw.writer.print("{d}", .{row.mtime});
    try aw.writer.writeAll("}");
    return try aw.toOwnedSlice();
}
pub fn decode_row_id_2_24(json_text: []const u8) ?[]const u8 {
    // lightweight scan for "id":"..." without full JSON parse
    const key = "\"id\":\"";
    const start = std.mem.indexOf(u8, json_text, key) orelse return null;
    const from = start + key.len;
    const end = std.mem.indexOfScalar(u8, json_text[from..], '"') orelse return null;
    return json_text[from .. from + end];
}

pub fn schema_table_2_25_name() []const u8 { return "t_2_25"; }
pub fn schema_table_2_25_create_sql() []const u8 {
    return "CREATE TABLE IF NOT EXISTS t_2_25 (id TEXT PRIMARY KEY, kind TEXT, payload TEXT, mtime INTEGER);";
}
pub fn schema_table_2_25_insert_sql() []const u8 {
    return "INSERT OR REPLACE INTO t_2_25 (id, kind, payload, mtime) VALUES (?, ?, ?, ?);";
}
pub fn schema_table_2_25_select_sql() []const u8 {
    return "SELECT id, kind, payload, mtime FROM t_2_25 WHERE id = ?;";
}
pub fn schema_table_2_25_list_sql(limit: u32) []const u8 {
    _ = limit;
    return "SELECT id, kind, payload, mtime FROM t_2_25 ORDER BY mtime DESC LIMIT 100;";
}
pub fn encode_row_2_25(gpa: std.mem.Allocator, row: Row) ![]u8 {
    var aw: std.Io.Writer.Allocating = .init(gpa);
    errdefer aw.deinit();
    try aw.writer.writeAll("{\"id\":");
    try std.json.Stringify.value(row.id, .{}, &aw.writer);
    try aw.writer.writeAll(",\"kind\":");
    try std.json.Stringify.value(row.kind, .{}, &aw.writer);
    try aw.writer.writeAll(",\"payload\":");
    try std.json.Stringify.value(row.payload, .{}, &aw.writer);
    try aw.writer.writeAll(",\"mtime\":");
    try aw.writer.print("{d}", .{row.mtime});
    try aw.writer.writeAll("}");
    return try aw.toOwnedSlice();
}
pub fn decode_row_id_2_25(json_text: []const u8) ?[]const u8 {
    // lightweight scan for "id":"..." without full JSON parse
    const key = "\"id\":\"";
    const start = std.mem.indexOf(u8, json_text, key) orelse return null;
    const from = start + key.len;
    const end = std.mem.indexOfScalar(u8, json_text[from..], '"') orelse return null;
    return json_text[from .. from + end];
}

pub fn schema_table_2_26_name() []const u8 { return "t_2_26"; }
pub fn schema_table_2_26_create_sql() []const u8 {
    return "CREATE TABLE IF NOT EXISTS t_2_26 (id TEXT PRIMARY KEY, kind TEXT, payload TEXT, mtime INTEGER);";
}
pub fn schema_table_2_26_insert_sql() []const u8 {
    return "INSERT OR REPLACE INTO t_2_26 (id, kind, payload, mtime) VALUES (?, ?, ?, ?);";
}
pub fn schema_table_2_26_select_sql() []const u8 {
    return "SELECT id, kind, payload, mtime FROM t_2_26 WHERE id = ?;";
}
pub fn schema_table_2_26_list_sql(limit: u32) []const u8 {
    _ = limit;
    return "SELECT id, kind, payload, mtime FROM t_2_26 ORDER BY mtime DESC LIMIT 100;";
}
pub fn encode_row_2_26(gpa: std.mem.Allocator, row: Row) ![]u8 {
    var aw: std.Io.Writer.Allocating = .init(gpa);
    errdefer aw.deinit();
    try aw.writer.writeAll("{\"id\":");
    try std.json.Stringify.value(row.id, .{}, &aw.writer);
    try aw.writer.writeAll(",\"kind\":");
    try std.json.Stringify.value(row.kind, .{}, &aw.writer);
    try aw.writer.writeAll(",\"payload\":");
    try std.json.Stringify.value(row.payload, .{}, &aw.writer);
    try aw.writer.writeAll(",\"mtime\":");
    try aw.writer.print("{d}", .{row.mtime});
    try aw.writer.writeAll("}");
    return try aw.toOwnedSlice();
}
pub fn decode_row_id_2_26(json_text: []const u8) ?[]const u8 {
    // lightweight scan for "id":"..." without full JSON parse
    const key = "\"id\":\"";
    const start = std.mem.indexOf(u8, json_text, key) orelse return null;
    const from = start + key.len;
    const end = std.mem.indexOfScalar(u8, json_text[from..], '"') orelse return null;
    return json_text[from .. from + end];
}

pub fn schema_table_2_27_name() []const u8 { return "t_2_27"; }
pub fn schema_table_2_27_create_sql() []const u8 {
    return "CREATE TABLE IF NOT EXISTS t_2_27 (id TEXT PRIMARY KEY, kind TEXT, payload TEXT, mtime INTEGER);";
}
pub fn schema_table_2_27_insert_sql() []const u8 {
    return "INSERT OR REPLACE INTO t_2_27 (id, kind, payload, mtime) VALUES (?, ?, ?, ?);";
}
pub fn schema_table_2_27_select_sql() []const u8 {
    return "SELECT id, kind, payload, mtime FROM t_2_27 WHERE id = ?;";
}
pub fn schema_table_2_27_list_sql(limit: u32) []const u8 {
    _ = limit;
    return "SELECT id, kind, payload, mtime FROM t_2_27 ORDER BY mtime DESC LIMIT 100;";
}
pub fn encode_row_2_27(gpa: std.mem.Allocator, row: Row) ![]u8 {
    var aw: std.Io.Writer.Allocating = .init(gpa);
    errdefer aw.deinit();
    try aw.writer.writeAll("{\"id\":");
    try std.json.Stringify.value(row.id, .{}, &aw.writer);
    try aw.writer.writeAll(",\"kind\":");
    try std.json.Stringify.value(row.kind, .{}, &aw.writer);
    try aw.writer.writeAll(",\"payload\":");
    try std.json.Stringify.value(row.payload, .{}, &aw.writer);
    try aw.writer.writeAll(",\"mtime\":");
    try aw.writer.print("{d}", .{row.mtime});
    try aw.writer.writeAll("}");
    return try aw.toOwnedSlice();
}
pub fn decode_row_id_2_27(json_text: []const u8) ?[]const u8 {
    // lightweight scan for "id":"..." without full JSON parse
    const key = "\"id\":\"";
    const start = std.mem.indexOf(u8, json_text, key) orelse return null;
    const from = start + key.len;
    const end = std.mem.indexOfScalar(u8, json_text[from..], '"') orelse return null;
    return json_text[from .. from + end];
}

pub fn schema_table_2_28_name() []const u8 { return "t_2_28"; }
pub fn schema_table_2_28_create_sql() []const u8 {
    return "CREATE TABLE IF NOT EXISTS t_2_28 (id TEXT PRIMARY KEY, kind TEXT, payload TEXT, mtime INTEGER);";
}
pub fn schema_table_2_28_insert_sql() []const u8 {
    return "INSERT OR REPLACE INTO t_2_28 (id, kind, payload, mtime) VALUES (?, ?, ?, ?);";
}
pub fn schema_table_2_28_select_sql() []const u8 {
    return "SELECT id, kind, payload, mtime FROM t_2_28 WHERE id = ?;";
}
pub fn schema_table_2_28_list_sql(limit: u32) []const u8 {
    _ = limit;
    return "SELECT id, kind, payload, mtime FROM t_2_28 ORDER BY mtime DESC LIMIT 100;";
}
pub fn encode_row_2_28(gpa: std.mem.Allocator, row: Row) ![]u8 {
    var aw: std.Io.Writer.Allocating = .init(gpa);
    errdefer aw.deinit();
    try aw.writer.writeAll("{\"id\":");
    try std.json.Stringify.value(row.id, .{}, &aw.writer);
    try aw.writer.writeAll(",\"kind\":");
    try std.json.Stringify.value(row.kind, .{}, &aw.writer);
    try aw.writer.writeAll(",\"payload\":");
    try std.json.Stringify.value(row.payload, .{}, &aw.writer);
    try aw.writer.writeAll(",\"mtime\":");
    try aw.writer.print("{d}", .{row.mtime});
    try aw.writer.writeAll("}");
    return try aw.toOwnedSlice();
}
pub fn decode_row_id_2_28(json_text: []const u8) ?[]const u8 {
    // lightweight scan for "id":"..." without full JSON parse
    const key = "\"id\":\"";
    const start = std.mem.indexOf(u8, json_text, key) orelse return null;
    const from = start + key.len;
    const end = std.mem.indexOfScalar(u8, json_text[from..], '"') orelse return null;
    return json_text[from .. from + end];
}

pub fn schema_table_2_29_name() []const u8 { return "t_2_29"; }
pub fn schema_table_2_29_create_sql() []const u8 {
    return "CREATE TABLE IF NOT EXISTS t_2_29 (id TEXT PRIMARY KEY, kind TEXT, payload TEXT, mtime INTEGER);";
}
pub fn schema_table_2_29_insert_sql() []const u8 {
    return "INSERT OR REPLACE INTO t_2_29 (id, kind, payload, mtime) VALUES (?, ?, ?, ?);";
}
pub fn schema_table_2_29_select_sql() []const u8 {
    return "SELECT id, kind, payload, mtime FROM t_2_29 WHERE id = ?;";
}
pub fn schema_table_2_29_list_sql(limit: u32) []const u8 {
    _ = limit;
    return "SELECT id, kind, payload, mtime FROM t_2_29 ORDER BY mtime DESC LIMIT 100;";
}
pub fn encode_row_2_29(gpa: std.mem.Allocator, row: Row) ![]u8 {
    var aw: std.Io.Writer.Allocating = .init(gpa);
    errdefer aw.deinit();
    try aw.writer.writeAll("{\"id\":");
    try std.json.Stringify.value(row.id, .{}, &aw.writer);
    try aw.writer.writeAll(",\"kind\":");
    try std.json.Stringify.value(row.kind, .{}, &aw.writer);
    try aw.writer.writeAll(",\"payload\":");
    try std.json.Stringify.value(row.payload, .{}, &aw.writer);
    try aw.writer.writeAll(",\"mtime\":");
    try aw.writer.print("{d}", .{row.mtime});
    try aw.writer.writeAll("}");
    return try aw.toOwnedSlice();
}
pub fn decode_row_id_2_29(json_text: []const u8) ?[]const u8 {
    // lightweight scan for "id":"..." without full JSON parse
    const key = "\"id\":\"";
    const start = std.mem.indexOf(u8, json_text, key) orelse return null;
    const from = start + key.len;
    const end = std.mem.indexOfScalar(u8, json_text[from..], '"') orelse return null;
    return json_text[from .. from + end];
}

pub fn schema_table_2_30_name() []const u8 { return "t_2_30"; }
pub fn schema_table_2_30_create_sql() []const u8 {
    return "CREATE TABLE IF NOT EXISTS t_2_30 (id TEXT PRIMARY KEY, kind TEXT, payload TEXT, mtime INTEGER);";
}
pub fn schema_table_2_30_insert_sql() []const u8 {
    return "INSERT OR REPLACE INTO t_2_30 (id, kind, payload, mtime) VALUES (?, ?, ?, ?);";
}
pub fn schema_table_2_30_select_sql() []const u8 {
    return "SELECT id, kind, payload, mtime FROM t_2_30 WHERE id = ?;";
}
pub fn schema_table_2_30_list_sql(limit: u32) []const u8 {
    _ = limit;
    return "SELECT id, kind, payload, mtime FROM t_2_30 ORDER BY mtime DESC LIMIT 100;";
}
pub fn encode_row_2_30(gpa: std.mem.Allocator, row: Row) ![]u8 {
    var aw: std.Io.Writer.Allocating = .init(gpa);
    errdefer aw.deinit();
    try aw.writer.writeAll("{\"id\":");
    try std.json.Stringify.value(row.id, .{}, &aw.writer);
    try aw.writer.writeAll(",\"kind\":");
    try std.json.Stringify.value(row.kind, .{}, &aw.writer);
    try aw.writer.writeAll(",\"payload\":");
    try std.json.Stringify.value(row.payload, .{}, &aw.writer);
    try aw.writer.writeAll(",\"mtime\":");
    try aw.writer.print("{d}", .{row.mtime});
    try aw.writer.writeAll("}");
    return try aw.toOwnedSlice();
}
pub fn decode_row_id_2_30(json_text: []const u8) ?[]const u8 {
    // lightweight scan for "id":"..." without full JSON parse
    const key = "\"id\":\"";
    const start = std.mem.indexOf(u8, json_text, key) orelse return null;
    const from = start + key.len;
    const end = std.mem.indexOfScalar(u8, json_text[from..], '"') orelse return null;
    return json_text[from .. from + end];
}

pub fn schema_table_2_31_name() []const u8 { return "t_2_31"; }
pub fn schema_table_2_31_create_sql() []const u8 {
    return "CREATE TABLE IF NOT EXISTS t_2_31 (id TEXT PRIMARY KEY, kind TEXT, payload TEXT, mtime INTEGER);";
}
pub fn schema_table_2_31_insert_sql() []const u8 {
    return "INSERT OR REPLACE INTO t_2_31 (id, kind, payload, mtime) VALUES (?, ?, ?, ?);";
}
pub fn schema_table_2_31_select_sql() []const u8 {
    return "SELECT id, kind, payload, mtime FROM t_2_31 WHERE id = ?;";
}
pub fn schema_table_2_31_list_sql(limit: u32) []const u8 {
    _ = limit;
    return "SELECT id, kind, payload, mtime FROM t_2_31 ORDER BY mtime DESC LIMIT 100;";
}
pub fn encode_row_2_31(gpa: std.mem.Allocator, row: Row) ![]u8 {
    var aw: std.Io.Writer.Allocating = .init(gpa);
    errdefer aw.deinit();
    try aw.writer.writeAll("{\"id\":");
    try std.json.Stringify.value(row.id, .{}, &aw.writer);
    try aw.writer.writeAll(",\"kind\":");
    try std.json.Stringify.value(row.kind, .{}, &aw.writer);
    try aw.writer.writeAll(",\"payload\":");
    try std.json.Stringify.value(row.payload, .{}, &aw.writer);
    try aw.writer.writeAll(",\"mtime\":");
    try aw.writer.print("{d}", .{row.mtime});
    try aw.writer.writeAll("}");
    return try aw.toOwnedSlice();
}
pub fn decode_row_id_2_31(json_text: []const u8) ?[]const u8 {
    // lightweight scan for "id":"..." without full JSON parse
    const key = "\"id\":\"";
    const start = std.mem.indexOf(u8, json_text, key) orelse return null;
    const from = start + key.len;
    const end = std.mem.indexOfScalar(u8, json_text[from..], '"') orelse return null;
    return json_text[from .. from + end];
}

pub fn schema_table_2_32_name() []const u8 { return "t_2_32"; }
pub fn schema_table_2_32_create_sql() []const u8 {
    return "CREATE TABLE IF NOT EXISTS t_2_32 (id TEXT PRIMARY KEY, kind TEXT, payload TEXT, mtime INTEGER);";
}
pub fn schema_table_2_32_insert_sql() []const u8 {
    return "INSERT OR REPLACE INTO t_2_32 (id, kind, payload, mtime) VALUES (?, ?, ?, ?);";
}
pub fn schema_table_2_32_select_sql() []const u8 {
    return "SELECT id, kind, payload, mtime FROM t_2_32 WHERE id = ?;";
}
pub fn schema_table_2_32_list_sql(limit: u32) []const u8 {
    _ = limit;
    return "SELECT id, kind, payload, mtime FROM t_2_32 ORDER BY mtime DESC LIMIT 100;";
}
pub fn encode_row_2_32(gpa: std.mem.Allocator, row: Row) ![]u8 {
    var aw: std.Io.Writer.Allocating = .init(gpa);
    errdefer aw.deinit();
    try aw.writer.writeAll("{\"id\":");
    try std.json.Stringify.value(row.id, .{}, &aw.writer);
    try aw.writer.writeAll(",\"kind\":");
    try std.json.Stringify.value(row.kind, .{}, &aw.writer);
    try aw.writer.writeAll(",\"payload\":");
    try std.json.Stringify.value(row.payload, .{}, &aw.writer);
    try aw.writer.writeAll(",\"mtime\":");
    try aw.writer.print("{d}", .{row.mtime});
    try aw.writer.writeAll("}");
    return try aw.toOwnedSlice();
}
pub fn decode_row_id_2_32(json_text: []const u8) ?[]const u8 {
    // lightweight scan for "id":"..." without full JSON parse
    const key = "\"id\":\"";
    const start = std.mem.indexOf(u8, json_text, key) orelse return null;
    const from = start + key.len;
    const end = std.mem.indexOfScalar(u8, json_text[from..], '"') orelse return null;
    return json_text[from .. from + end];
}

pub fn schema_table_2_33_name() []const u8 { return "t_2_33"; }
pub fn schema_table_2_33_create_sql() []const u8 {
    return "CREATE TABLE IF NOT EXISTS t_2_33 (id TEXT PRIMARY KEY, kind TEXT, payload TEXT, mtime INTEGER);";
}
pub fn schema_table_2_33_insert_sql() []const u8 {
    return "INSERT OR REPLACE INTO t_2_33 (id, kind, payload, mtime) VALUES (?, ?, ?, ?);";
}
pub fn schema_table_2_33_select_sql() []const u8 {
    return "SELECT id, kind, payload, mtime FROM t_2_33 WHERE id = ?;";
}
pub fn schema_table_2_33_list_sql(limit: u32) []const u8 {
    _ = limit;
    return "SELECT id, kind, payload, mtime FROM t_2_33 ORDER BY mtime DESC LIMIT 100;";
}
pub fn encode_row_2_33(gpa: std.mem.Allocator, row: Row) ![]u8 {
    var aw: std.Io.Writer.Allocating = .init(gpa);
    errdefer aw.deinit();
    try aw.writer.writeAll("{\"id\":");
    try std.json.Stringify.value(row.id, .{}, &aw.writer);
    try aw.writer.writeAll(",\"kind\":");
    try std.json.Stringify.value(row.kind, .{}, &aw.writer);
    try aw.writer.writeAll(",\"payload\":");
    try std.json.Stringify.value(row.payload, .{}, &aw.writer);
    try aw.writer.writeAll(",\"mtime\":");
    try aw.writer.print("{d}", .{row.mtime});
    try aw.writer.writeAll("}");
    return try aw.toOwnedSlice();
}
pub fn decode_row_id_2_33(json_text: []const u8) ?[]const u8 {
    // lightweight scan for "id":"..." without full JSON parse
    const key = "\"id\":\"";
    const start = std.mem.indexOf(u8, json_text, key) orelse return null;
    const from = start + key.len;
    const end = std.mem.indexOfScalar(u8, json_text[from..], '"') orelse return null;
    return json_text[from .. from + end];
}

pub fn schema_table_2_34_name() []const u8 { return "t_2_34"; }
pub fn schema_table_2_34_create_sql() []const u8 {
    return "CREATE TABLE IF NOT EXISTS t_2_34 (id TEXT PRIMARY KEY, kind TEXT, payload TEXT, mtime INTEGER);";
}
pub fn schema_table_2_34_insert_sql() []const u8 {
    return "INSERT OR REPLACE INTO t_2_34 (id, kind, payload, mtime) VALUES (?, ?, ?, ?);";
}
pub fn schema_table_2_34_select_sql() []const u8 {
    return "SELECT id, kind, payload, mtime FROM t_2_34 WHERE id = ?;";
}
pub fn schema_table_2_34_list_sql(limit: u32) []const u8 {
    _ = limit;
    return "SELECT id, kind, payload, mtime FROM t_2_34 ORDER BY mtime DESC LIMIT 100;";
}
pub fn encode_row_2_34(gpa: std.mem.Allocator, row: Row) ![]u8 {
    var aw: std.Io.Writer.Allocating = .init(gpa);
    errdefer aw.deinit();
    try aw.writer.writeAll("{\"id\":");
    try std.json.Stringify.value(row.id, .{}, &aw.writer);
    try aw.writer.writeAll(",\"kind\":");
    try std.json.Stringify.value(row.kind, .{}, &aw.writer);
    try aw.writer.writeAll(",\"payload\":");
    try std.json.Stringify.value(row.payload, .{}, &aw.writer);
    try aw.writer.writeAll(",\"mtime\":");
    try aw.writer.print("{d}", .{row.mtime});
    try aw.writer.writeAll("}");
    return try aw.toOwnedSlice();
}
pub fn decode_row_id_2_34(json_text: []const u8) ?[]const u8 {
    // lightweight scan for "id":"..." without full JSON parse
    const key = "\"id\":\"";
    const start = std.mem.indexOf(u8, json_text, key) orelse return null;
    const from = start + key.len;
    const end = std.mem.indexOfScalar(u8, json_text[from..], '"') orelse return null;
    return json_text[from .. from + end];
}

pub fn schema_table_2_35_name() []const u8 { return "t_2_35"; }
pub fn schema_table_2_35_create_sql() []const u8 {
    return "CREATE TABLE IF NOT EXISTS t_2_35 (id TEXT PRIMARY KEY, kind TEXT, payload TEXT, mtime INTEGER);";
}
pub fn schema_table_2_35_insert_sql() []const u8 {
    return "INSERT OR REPLACE INTO t_2_35 (id, kind, payload, mtime) VALUES (?, ?, ?, ?);";
}
pub fn schema_table_2_35_select_sql() []const u8 {
    return "SELECT id, kind, payload, mtime FROM t_2_35 WHERE id = ?;";
}
pub fn schema_table_2_35_list_sql(limit: u32) []const u8 {
    _ = limit;
    return "SELECT id, kind, payload, mtime FROM t_2_35 ORDER BY mtime DESC LIMIT 100;";
}
pub fn encode_row_2_35(gpa: std.mem.Allocator, row: Row) ![]u8 {
    var aw: std.Io.Writer.Allocating = .init(gpa);
    errdefer aw.deinit();
    try aw.writer.writeAll("{\"id\":");
    try std.json.Stringify.value(row.id, .{}, &aw.writer);
    try aw.writer.writeAll(",\"kind\":");
    try std.json.Stringify.value(row.kind, .{}, &aw.writer);
    try aw.writer.writeAll(",\"payload\":");
    try std.json.Stringify.value(row.payload, .{}, &aw.writer);
    try aw.writer.writeAll(",\"mtime\":");
    try aw.writer.print("{d}", .{row.mtime});
    try aw.writer.writeAll("}");
    return try aw.toOwnedSlice();
}
pub fn decode_row_id_2_35(json_text: []const u8) ?[]const u8 {
    // lightweight scan for "id":"..." without full JSON parse
    const key = "\"id\":\"";
    const start = std.mem.indexOf(u8, json_text, key) orelse return null;
    const from = start + key.len;
    const end = std.mem.indexOfScalar(u8, json_text[from..], '"') orelse return null;
    return json_text[from .. from + end];
}

pub fn schema_table_2_36_name() []const u8 { return "t_2_36"; }
pub fn schema_table_2_36_create_sql() []const u8 {
    return "CREATE TABLE IF NOT EXISTS t_2_36 (id TEXT PRIMARY KEY, kind TEXT, payload TEXT, mtime INTEGER);";
}
pub fn schema_table_2_36_insert_sql() []const u8 {
    return "INSERT OR REPLACE INTO t_2_36 (id, kind, payload, mtime) VALUES (?, ?, ?, ?);";
}
pub fn schema_table_2_36_select_sql() []const u8 {
    return "SELECT id, kind, payload, mtime FROM t_2_36 WHERE id = ?;";
}
pub fn schema_table_2_36_list_sql(limit: u32) []const u8 {
    _ = limit;
    return "SELECT id, kind, payload, mtime FROM t_2_36 ORDER BY mtime DESC LIMIT 100;";
}
pub fn encode_row_2_36(gpa: std.mem.Allocator, row: Row) ![]u8 {
    var aw: std.Io.Writer.Allocating = .init(gpa);
    errdefer aw.deinit();
    try aw.writer.writeAll("{\"id\":");
    try std.json.Stringify.value(row.id, .{}, &aw.writer);
    try aw.writer.writeAll(",\"kind\":");
    try std.json.Stringify.value(row.kind, .{}, &aw.writer);
    try aw.writer.writeAll(",\"payload\":");
    try std.json.Stringify.value(row.payload, .{}, &aw.writer);
    try aw.writer.writeAll(",\"mtime\":");
    try aw.writer.print("{d}", .{row.mtime});
    try aw.writer.writeAll("}");
    return try aw.toOwnedSlice();
}
pub fn decode_row_id_2_36(json_text: []const u8) ?[]const u8 {
    // lightweight scan for "id":"..." without full JSON parse
    const key = "\"id\":\"";
    const start = std.mem.indexOf(u8, json_text, key) orelse return null;
    const from = start + key.len;
    const end = std.mem.indexOfScalar(u8, json_text[from..], '"') orelse return null;
    return json_text[from .. from + end];
}

pub fn schema_table_2_37_name() []const u8 { return "t_2_37"; }
pub fn schema_table_2_37_create_sql() []const u8 {
    return "CREATE TABLE IF NOT EXISTS t_2_37 (id TEXT PRIMARY KEY, kind TEXT, payload TEXT, mtime INTEGER);";
}
pub fn schema_table_2_37_insert_sql() []const u8 {
    return "INSERT OR REPLACE INTO t_2_37 (id, kind, payload, mtime) VALUES (?, ?, ?, ?);";
}
pub fn schema_table_2_37_select_sql() []const u8 {
    return "SELECT id, kind, payload, mtime FROM t_2_37 WHERE id = ?;";
}
pub fn schema_table_2_37_list_sql(limit: u32) []const u8 {
    _ = limit;
    return "SELECT id, kind, payload, mtime FROM t_2_37 ORDER BY mtime DESC LIMIT 100;";
}
pub fn encode_row_2_37(gpa: std.mem.Allocator, row: Row) ![]u8 {
    var aw: std.Io.Writer.Allocating = .init(gpa);
    errdefer aw.deinit();
    try aw.writer.writeAll("{\"id\":");
    try std.json.Stringify.value(row.id, .{}, &aw.writer);
    try aw.writer.writeAll(",\"kind\":");
    try std.json.Stringify.value(row.kind, .{}, &aw.writer);
    try aw.writer.writeAll(",\"payload\":");
    try std.json.Stringify.value(row.payload, .{}, &aw.writer);
    try aw.writer.writeAll(",\"mtime\":");
    try aw.writer.print("{d}", .{row.mtime});
    try aw.writer.writeAll("}");
    return try aw.toOwnedSlice();
}
pub fn decode_row_id_2_37(json_text: []const u8) ?[]const u8 {
    // lightweight scan for "id":"..." without full JSON parse
    const key = "\"id\":\"";
    const start = std.mem.indexOf(u8, json_text, key) orelse return null;
    const from = start + key.len;
    const end = std.mem.indexOfScalar(u8, json_text[from..], '"') orelse return null;
    return json_text[from .. from + end];
}

pub fn schema_table_2_38_name() []const u8 { return "t_2_38"; }
pub fn schema_table_2_38_create_sql() []const u8 {
    return "CREATE TABLE IF NOT EXISTS t_2_38 (id TEXT PRIMARY KEY, kind TEXT, payload TEXT, mtime INTEGER);";
}
pub fn schema_table_2_38_insert_sql() []const u8 {
    return "INSERT OR REPLACE INTO t_2_38 (id, kind, payload, mtime) VALUES (?, ?, ?, ?);";
}
pub fn schema_table_2_38_select_sql() []const u8 {
    return "SELECT id, kind, payload, mtime FROM t_2_38 WHERE id = ?;";
}
pub fn schema_table_2_38_list_sql(limit: u32) []const u8 {
    _ = limit;
    return "SELECT id, kind, payload, mtime FROM t_2_38 ORDER BY mtime DESC LIMIT 100;";
}
pub fn encode_row_2_38(gpa: std.mem.Allocator, row: Row) ![]u8 {
    var aw: std.Io.Writer.Allocating = .init(gpa);
    errdefer aw.deinit();
    try aw.writer.writeAll("{\"id\":");
    try std.json.Stringify.value(row.id, .{}, &aw.writer);
    try aw.writer.writeAll(",\"kind\":");
    try std.json.Stringify.value(row.kind, .{}, &aw.writer);
    try aw.writer.writeAll(",\"payload\":");
    try std.json.Stringify.value(row.payload, .{}, &aw.writer);
    try aw.writer.writeAll(",\"mtime\":");
    try aw.writer.print("{d}", .{row.mtime});
    try aw.writer.writeAll("}");
    return try aw.toOwnedSlice();
}
pub fn decode_row_id_2_38(json_text: []const u8) ?[]const u8 {
    // lightweight scan for "id":"..." without full JSON parse
    const key = "\"id\":\"";
    const start = std.mem.indexOf(u8, json_text, key) orelse return null;
    const from = start + key.len;
    const end = std.mem.indexOfScalar(u8, json_text[from..], '"') orelse return null;
    return json_text[from .. from + end];
}

pub fn schema_table_2_39_name() []const u8 { return "t_2_39"; }
pub fn schema_table_2_39_create_sql() []const u8 {
    return "CREATE TABLE IF NOT EXISTS t_2_39 (id TEXT PRIMARY KEY, kind TEXT, payload TEXT, mtime INTEGER);";
}
pub fn schema_table_2_39_insert_sql() []const u8 {
    return "INSERT OR REPLACE INTO t_2_39 (id, kind, payload, mtime) VALUES (?, ?, ?, ?);";
}
pub fn schema_table_2_39_select_sql() []const u8 {
    return "SELECT id, kind, payload, mtime FROM t_2_39 WHERE id = ?;";
}
pub fn schema_table_2_39_list_sql(limit: u32) []const u8 {
    _ = limit;
    return "SELECT id, kind, payload, mtime FROM t_2_39 ORDER BY mtime DESC LIMIT 100;";
}
pub fn encode_row_2_39(gpa: std.mem.Allocator, row: Row) ![]u8 {
    var aw: std.Io.Writer.Allocating = .init(gpa);
    errdefer aw.deinit();
    try aw.writer.writeAll("{\"id\":");
    try std.json.Stringify.value(row.id, .{}, &aw.writer);
    try aw.writer.writeAll(",\"kind\":");
    try std.json.Stringify.value(row.kind, .{}, &aw.writer);
    try aw.writer.writeAll(",\"payload\":");
    try std.json.Stringify.value(row.payload, .{}, &aw.writer);
    try aw.writer.writeAll(",\"mtime\":");
    try aw.writer.print("{d}", .{row.mtime});
    try aw.writer.writeAll("}");
    return try aw.toOwnedSlice();
}
pub fn decode_row_id_2_39(json_text: []const u8) ?[]const u8 {
    // lightweight scan for "id":"..." without full JSON parse
    const key = "\"id\":\"";
    const start = std.mem.indexOf(u8, json_text, key) orelse return null;
    const from = start + key.len;
    const end = std.mem.indexOfScalar(u8, json_text[from..], '"') orelse return null;
    return json_text[from .. from + end];
}

test "storage shard 2" {
    try std.testing.expectEqualStrings("t_2_0", schema_table_2_0_name());
    const gpa = std.testing.allocator;
    const enc = try encode_row_2_0(gpa, .{ .id = "a", .kind = "k", .payload = "p", .mtime = 1 });
    defer gpa.free(enc);
    try std.testing.expectEqualStrings("a", decode_row_id_2_0(enc).?);
}

