//! Generated storage schema/query helpers shard 13.
const std = @import("std");

pub const Row = struct {
    id: []const u8,
    kind: []const u8,
    payload: []const u8,
    mtime: i64,
};

pub fn schema_table_13_0_name() []const u8 { return "t_13_0"; }
pub fn schema_table_13_0_create_sql() []const u8 {
    return "CREATE TABLE IF NOT EXISTS t_13_0 (id TEXT PRIMARY KEY, kind TEXT, payload TEXT, mtime INTEGER);";
}
pub fn schema_table_13_0_insert_sql() []const u8 {
    return "INSERT OR REPLACE INTO t_13_0 (id, kind, payload, mtime) VALUES (?, ?, ?, ?);";
}
pub fn schema_table_13_0_select_sql() []const u8 {
    return "SELECT id, kind, payload, mtime FROM t_13_0 WHERE id = ?;";
}
pub fn schema_table_13_0_list_sql(limit: u32) []const u8 {
    _ = limit;
    return "SELECT id, kind, payload, mtime FROM t_13_0 ORDER BY mtime DESC LIMIT 100;";
}
pub fn encode_row_13_0(gpa: std.mem.Allocator, row: Row) ![]u8 {
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
pub fn decode_row_id_13_0(json_text: []const u8) ?[]const u8 {
    // lightweight scan for "id":"..." without full JSON parse
    const key = "\"id\":\"";
    const start = std.mem.indexOf(u8, json_text, key) orelse return null;
    const from = start + key.len;
    const end = std.mem.indexOfScalar(u8, json_text[from..], '"') orelse return null;
    return json_text[from .. from + end];
}

pub fn schema_table_13_1_name() []const u8 { return "t_13_1"; }
pub fn schema_table_13_1_create_sql() []const u8 {
    return "CREATE TABLE IF NOT EXISTS t_13_1 (id TEXT PRIMARY KEY, kind TEXT, payload TEXT, mtime INTEGER);";
}
pub fn schema_table_13_1_insert_sql() []const u8 {
    return "INSERT OR REPLACE INTO t_13_1 (id, kind, payload, mtime) VALUES (?, ?, ?, ?);";
}
pub fn schema_table_13_1_select_sql() []const u8 {
    return "SELECT id, kind, payload, mtime FROM t_13_1 WHERE id = ?;";
}
pub fn schema_table_13_1_list_sql(limit: u32) []const u8 {
    _ = limit;
    return "SELECT id, kind, payload, mtime FROM t_13_1 ORDER BY mtime DESC LIMIT 100;";
}
pub fn encode_row_13_1(gpa: std.mem.Allocator, row: Row) ![]u8 {
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
pub fn decode_row_id_13_1(json_text: []const u8) ?[]const u8 {
    // lightweight scan for "id":"..." without full JSON parse
    const key = "\"id\":\"";
    const start = std.mem.indexOf(u8, json_text, key) orelse return null;
    const from = start + key.len;
    const end = std.mem.indexOfScalar(u8, json_text[from..], '"') orelse return null;
    return json_text[from .. from + end];
}

pub fn schema_table_13_2_name() []const u8 { return "t_13_2"; }
pub fn schema_table_13_2_create_sql() []const u8 {
    return "CREATE TABLE IF NOT EXISTS t_13_2 (id TEXT PRIMARY KEY, kind TEXT, payload TEXT, mtime INTEGER);";
}
pub fn schema_table_13_2_insert_sql() []const u8 {
    return "INSERT OR REPLACE INTO t_13_2 (id, kind, payload, mtime) VALUES (?, ?, ?, ?);";
}
pub fn schema_table_13_2_select_sql() []const u8 {
    return "SELECT id, kind, payload, mtime FROM t_13_2 WHERE id = ?;";
}
pub fn schema_table_13_2_list_sql(limit: u32) []const u8 {
    _ = limit;
    return "SELECT id, kind, payload, mtime FROM t_13_2 ORDER BY mtime DESC LIMIT 100;";
}
pub fn encode_row_13_2(gpa: std.mem.Allocator, row: Row) ![]u8 {
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
pub fn decode_row_id_13_2(json_text: []const u8) ?[]const u8 {
    // lightweight scan for "id":"..." without full JSON parse
    const key = "\"id\":\"";
    const start = std.mem.indexOf(u8, json_text, key) orelse return null;
    const from = start + key.len;
    const end = std.mem.indexOfScalar(u8, json_text[from..], '"') orelse return null;
    return json_text[from .. from + end];
}

pub fn schema_table_13_3_name() []const u8 { return "t_13_3"; }
pub fn schema_table_13_3_create_sql() []const u8 {
    return "CREATE TABLE IF NOT EXISTS t_13_3 (id TEXT PRIMARY KEY, kind TEXT, payload TEXT, mtime INTEGER);";
}
pub fn schema_table_13_3_insert_sql() []const u8 {
    return "INSERT OR REPLACE INTO t_13_3 (id, kind, payload, mtime) VALUES (?, ?, ?, ?);";
}
pub fn schema_table_13_3_select_sql() []const u8 {
    return "SELECT id, kind, payload, mtime FROM t_13_3 WHERE id = ?;";
}
pub fn schema_table_13_3_list_sql(limit: u32) []const u8 {
    _ = limit;
    return "SELECT id, kind, payload, mtime FROM t_13_3 ORDER BY mtime DESC LIMIT 100;";
}
pub fn encode_row_13_3(gpa: std.mem.Allocator, row: Row) ![]u8 {
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
pub fn decode_row_id_13_3(json_text: []const u8) ?[]const u8 {
    // lightweight scan for "id":"..." without full JSON parse
    const key = "\"id\":\"";
    const start = std.mem.indexOf(u8, json_text, key) orelse return null;
    const from = start + key.len;
    const end = std.mem.indexOfScalar(u8, json_text[from..], '"') orelse return null;
    return json_text[from .. from + end];
}

pub fn schema_table_13_4_name() []const u8 { return "t_13_4"; }
pub fn schema_table_13_4_create_sql() []const u8 {
    return "CREATE TABLE IF NOT EXISTS t_13_4 (id TEXT PRIMARY KEY, kind TEXT, payload TEXT, mtime INTEGER);";
}
pub fn schema_table_13_4_insert_sql() []const u8 {
    return "INSERT OR REPLACE INTO t_13_4 (id, kind, payload, mtime) VALUES (?, ?, ?, ?);";
}
pub fn schema_table_13_4_select_sql() []const u8 {
    return "SELECT id, kind, payload, mtime FROM t_13_4 WHERE id = ?;";
}
pub fn schema_table_13_4_list_sql(limit: u32) []const u8 {
    _ = limit;
    return "SELECT id, kind, payload, mtime FROM t_13_4 ORDER BY mtime DESC LIMIT 100;";
}
pub fn encode_row_13_4(gpa: std.mem.Allocator, row: Row) ![]u8 {
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
pub fn decode_row_id_13_4(json_text: []const u8) ?[]const u8 {
    // lightweight scan for "id":"..." without full JSON parse
    const key = "\"id\":\"";
    const start = std.mem.indexOf(u8, json_text, key) orelse return null;
    const from = start + key.len;
    const end = std.mem.indexOfScalar(u8, json_text[from..], '"') orelse return null;
    return json_text[from .. from + end];
}

pub fn schema_table_13_5_name() []const u8 { return "t_13_5"; }
pub fn schema_table_13_5_create_sql() []const u8 {
    return "CREATE TABLE IF NOT EXISTS t_13_5 (id TEXT PRIMARY KEY, kind TEXT, payload TEXT, mtime INTEGER);";
}
pub fn schema_table_13_5_insert_sql() []const u8 {
    return "INSERT OR REPLACE INTO t_13_5 (id, kind, payload, mtime) VALUES (?, ?, ?, ?);";
}
pub fn schema_table_13_5_select_sql() []const u8 {
    return "SELECT id, kind, payload, mtime FROM t_13_5 WHERE id = ?;";
}
pub fn schema_table_13_5_list_sql(limit: u32) []const u8 {
    _ = limit;
    return "SELECT id, kind, payload, mtime FROM t_13_5 ORDER BY mtime DESC LIMIT 100;";
}
pub fn encode_row_13_5(gpa: std.mem.Allocator, row: Row) ![]u8 {
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
pub fn decode_row_id_13_5(json_text: []const u8) ?[]const u8 {
    // lightweight scan for "id":"..." without full JSON parse
    const key = "\"id\":\"";
    const start = std.mem.indexOf(u8, json_text, key) orelse return null;
    const from = start + key.len;
    const end = std.mem.indexOfScalar(u8, json_text[from..], '"') orelse return null;
    return json_text[from .. from + end];
}

pub fn schema_table_13_6_name() []const u8 { return "t_13_6"; }
pub fn schema_table_13_6_create_sql() []const u8 {
    return "CREATE TABLE IF NOT EXISTS t_13_6 (id TEXT PRIMARY KEY, kind TEXT, payload TEXT, mtime INTEGER);";
}
pub fn schema_table_13_6_insert_sql() []const u8 {
    return "INSERT OR REPLACE INTO t_13_6 (id, kind, payload, mtime) VALUES (?, ?, ?, ?);";
}
pub fn schema_table_13_6_select_sql() []const u8 {
    return "SELECT id, kind, payload, mtime FROM t_13_6 WHERE id = ?;";
}
pub fn schema_table_13_6_list_sql(limit: u32) []const u8 {
    _ = limit;
    return "SELECT id, kind, payload, mtime FROM t_13_6 ORDER BY mtime DESC LIMIT 100;";
}
pub fn encode_row_13_6(gpa: std.mem.Allocator, row: Row) ![]u8 {
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
pub fn decode_row_id_13_6(json_text: []const u8) ?[]const u8 {
    // lightweight scan for "id":"..." without full JSON parse
    const key = "\"id\":\"";
    const start = std.mem.indexOf(u8, json_text, key) orelse return null;
    const from = start + key.len;
    const end = std.mem.indexOfScalar(u8, json_text[from..], '"') orelse return null;
    return json_text[from .. from + end];
}

pub fn schema_table_13_7_name() []const u8 { return "t_13_7"; }
pub fn schema_table_13_7_create_sql() []const u8 {
    return "CREATE TABLE IF NOT EXISTS t_13_7 (id TEXT PRIMARY KEY, kind TEXT, payload TEXT, mtime INTEGER);";
}
pub fn schema_table_13_7_insert_sql() []const u8 {
    return "INSERT OR REPLACE INTO t_13_7 (id, kind, payload, mtime) VALUES (?, ?, ?, ?);";
}
pub fn schema_table_13_7_select_sql() []const u8 {
    return "SELECT id, kind, payload, mtime FROM t_13_7 WHERE id = ?;";
}
pub fn schema_table_13_7_list_sql(limit: u32) []const u8 {
    _ = limit;
    return "SELECT id, kind, payload, mtime FROM t_13_7 ORDER BY mtime DESC LIMIT 100;";
}
pub fn encode_row_13_7(gpa: std.mem.Allocator, row: Row) ![]u8 {
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
pub fn decode_row_id_13_7(json_text: []const u8) ?[]const u8 {
    // lightweight scan for "id":"..." without full JSON parse
    const key = "\"id\":\"";
    const start = std.mem.indexOf(u8, json_text, key) orelse return null;
    const from = start + key.len;
    const end = std.mem.indexOfScalar(u8, json_text[from..], '"') orelse return null;
    return json_text[from .. from + end];
}

pub fn schema_table_13_8_name() []const u8 { return "t_13_8"; }
pub fn schema_table_13_8_create_sql() []const u8 {
    return "CREATE TABLE IF NOT EXISTS t_13_8 (id TEXT PRIMARY KEY, kind TEXT, payload TEXT, mtime INTEGER);";
}
pub fn schema_table_13_8_insert_sql() []const u8 {
    return "INSERT OR REPLACE INTO t_13_8 (id, kind, payload, mtime) VALUES (?, ?, ?, ?);";
}
pub fn schema_table_13_8_select_sql() []const u8 {
    return "SELECT id, kind, payload, mtime FROM t_13_8 WHERE id = ?;";
}
pub fn schema_table_13_8_list_sql(limit: u32) []const u8 {
    _ = limit;
    return "SELECT id, kind, payload, mtime FROM t_13_8 ORDER BY mtime DESC LIMIT 100;";
}
pub fn encode_row_13_8(gpa: std.mem.Allocator, row: Row) ![]u8 {
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
pub fn decode_row_id_13_8(json_text: []const u8) ?[]const u8 {
    // lightweight scan for "id":"..." without full JSON parse
    const key = "\"id\":\"";
    const start = std.mem.indexOf(u8, json_text, key) orelse return null;
    const from = start + key.len;
    const end = std.mem.indexOfScalar(u8, json_text[from..], '"') orelse return null;
    return json_text[from .. from + end];
}

pub fn schema_table_13_9_name() []const u8 { return "t_13_9"; }
pub fn schema_table_13_9_create_sql() []const u8 {
    return "CREATE TABLE IF NOT EXISTS t_13_9 (id TEXT PRIMARY KEY, kind TEXT, payload TEXT, mtime INTEGER);";
}
pub fn schema_table_13_9_insert_sql() []const u8 {
    return "INSERT OR REPLACE INTO t_13_9 (id, kind, payload, mtime) VALUES (?, ?, ?, ?);";
}
pub fn schema_table_13_9_select_sql() []const u8 {
    return "SELECT id, kind, payload, mtime FROM t_13_9 WHERE id = ?;";
}
pub fn schema_table_13_9_list_sql(limit: u32) []const u8 {
    _ = limit;
    return "SELECT id, kind, payload, mtime FROM t_13_9 ORDER BY mtime DESC LIMIT 100;";
}
pub fn encode_row_13_9(gpa: std.mem.Allocator, row: Row) ![]u8 {
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
pub fn decode_row_id_13_9(json_text: []const u8) ?[]const u8 {
    // lightweight scan for "id":"..." without full JSON parse
    const key = "\"id\":\"";
    const start = std.mem.indexOf(u8, json_text, key) orelse return null;
    const from = start + key.len;
    const end = std.mem.indexOfScalar(u8, json_text[from..], '"') orelse return null;
    return json_text[from .. from + end];
}

pub fn schema_table_13_10_name() []const u8 { return "t_13_10"; }
pub fn schema_table_13_10_create_sql() []const u8 {
    return "CREATE TABLE IF NOT EXISTS t_13_10 (id TEXT PRIMARY KEY, kind TEXT, payload TEXT, mtime INTEGER);";
}
pub fn schema_table_13_10_insert_sql() []const u8 {
    return "INSERT OR REPLACE INTO t_13_10 (id, kind, payload, mtime) VALUES (?, ?, ?, ?);";
}
pub fn schema_table_13_10_select_sql() []const u8 {
    return "SELECT id, kind, payload, mtime FROM t_13_10 WHERE id = ?;";
}
pub fn schema_table_13_10_list_sql(limit: u32) []const u8 {
    _ = limit;
    return "SELECT id, kind, payload, mtime FROM t_13_10 ORDER BY mtime DESC LIMIT 100;";
}
pub fn encode_row_13_10(gpa: std.mem.Allocator, row: Row) ![]u8 {
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
pub fn decode_row_id_13_10(json_text: []const u8) ?[]const u8 {
    // lightweight scan for "id":"..." without full JSON parse
    const key = "\"id\":\"";
    const start = std.mem.indexOf(u8, json_text, key) orelse return null;
    const from = start + key.len;
    const end = std.mem.indexOfScalar(u8, json_text[from..], '"') orelse return null;
    return json_text[from .. from + end];
}

pub fn schema_table_13_11_name() []const u8 { return "t_13_11"; }
pub fn schema_table_13_11_create_sql() []const u8 {
    return "CREATE TABLE IF NOT EXISTS t_13_11 (id TEXT PRIMARY KEY, kind TEXT, payload TEXT, mtime INTEGER);";
}
pub fn schema_table_13_11_insert_sql() []const u8 {
    return "INSERT OR REPLACE INTO t_13_11 (id, kind, payload, mtime) VALUES (?, ?, ?, ?);";
}
pub fn schema_table_13_11_select_sql() []const u8 {
    return "SELECT id, kind, payload, mtime FROM t_13_11 WHERE id = ?;";
}
pub fn schema_table_13_11_list_sql(limit: u32) []const u8 {
    _ = limit;
    return "SELECT id, kind, payload, mtime FROM t_13_11 ORDER BY mtime DESC LIMIT 100;";
}
pub fn encode_row_13_11(gpa: std.mem.Allocator, row: Row) ![]u8 {
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
pub fn decode_row_id_13_11(json_text: []const u8) ?[]const u8 {
    // lightweight scan for "id":"..." without full JSON parse
    const key = "\"id\":\"";
    const start = std.mem.indexOf(u8, json_text, key) orelse return null;
    const from = start + key.len;
    const end = std.mem.indexOfScalar(u8, json_text[from..], '"') orelse return null;
    return json_text[from .. from + end];
}

pub fn schema_table_13_12_name() []const u8 { return "t_13_12"; }
pub fn schema_table_13_12_create_sql() []const u8 {
    return "CREATE TABLE IF NOT EXISTS t_13_12 (id TEXT PRIMARY KEY, kind TEXT, payload TEXT, mtime INTEGER);";
}
pub fn schema_table_13_12_insert_sql() []const u8 {
    return "INSERT OR REPLACE INTO t_13_12 (id, kind, payload, mtime) VALUES (?, ?, ?, ?);";
}
pub fn schema_table_13_12_select_sql() []const u8 {
    return "SELECT id, kind, payload, mtime FROM t_13_12 WHERE id = ?;";
}
pub fn schema_table_13_12_list_sql(limit: u32) []const u8 {
    _ = limit;
    return "SELECT id, kind, payload, mtime FROM t_13_12 ORDER BY mtime DESC LIMIT 100;";
}
pub fn encode_row_13_12(gpa: std.mem.Allocator, row: Row) ![]u8 {
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
pub fn decode_row_id_13_12(json_text: []const u8) ?[]const u8 {
    // lightweight scan for "id":"..." without full JSON parse
    const key = "\"id\":\"";
    const start = std.mem.indexOf(u8, json_text, key) orelse return null;
    const from = start + key.len;
    const end = std.mem.indexOfScalar(u8, json_text[from..], '"') orelse return null;
    return json_text[from .. from + end];
}

pub fn schema_table_13_13_name() []const u8 { return "t_13_13"; }
pub fn schema_table_13_13_create_sql() []const u8 {
    return "CREATE TABLE IF NOT EXISTS t_13_13 (id TEXT PRIMARY KEY, kind TEXT, payload TEXT, mtime INTEGER);";
}
pub fn schema_table_13_13_insert_sql() []const u8 {
    return "INSERT OR REPLACE INTO t_13_13 (id, kind, payload, mtime) VALUES (?, ?, ?, ?);";
}
pub fn schema_table_13_13_select_sql() []const u8 {
    return "SELECT id, kind, payload, mtime FROM t_13_13 WHERE id = ?;";
}
pub fn schema_table_13_13_list_sql(limit: u32) []const u8 {
    _ = limit;
    return "SELECT id, kind, payload, mtime FROM t_13_13 ORDER BY mtime DESC LIMIT 100;";
}
pub fn encode_row_13_13(gpa: std.mem.Allocator, row: Row) ![]u8 {
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
pub fn decode_row_id_13_13(json_text: []const u8) ?[]const u8 {
    // lightweight scan for "id":"..." without full JSON parse
    const key = "\"id\":\"";
    const start = std.mem.indexOf(u8, json_text, key) orelse return null;
    const from = start + key.len;
    const end = std.mem.indexOfScalar(u8, json_text[from..], '"') orelse return null;
    return json_text[from .. from + end];
}

pub fn schema_table_13_14_name() []const u8 { return "t_13_14"; }
pub fn schema_table_13_14_create_sql() []const u8 {
    return "CREATE TABLE IF NOT EXISTS t_13_14 (id TEXT PRIMARY KEY, kind TEXT, payload TEXT, mtime INTEGER);";
}
pub fn schema_table_13_14_insert_sql() []const u8 {
    return "INSERT OR REPLACE INTO t_13_14 (id, kind, payload, mtime) VALUES (?, ?, ?, ?);";
}
pub fn schema_table_13_14_select_sql() []const u8 {
    return "SELECT id, kind, payload, mtime FROM t_13_14 WHERE id = ?;";
}
pub fn schema_table_13_14_list_sql(limit: u32) []const u8 {
    _ = limit;
    return "SELECT id, kind, payload, mtime FROM t_13_14 ORDER BY mtime DESC LIMIT 100;";
}
pub fn encode_row_13_14(gpa: std.mem.Allocator, row: Row) ![]u8 {
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
pub fn decode_row_id_13_14(json_text: []const u8) ?[]const u8 {
    // lightweight scan for "id":"..." without full JSON parse
    const key = "\"id\":\"";
    const start = std.mem.indexOf(u8, json_text, key) orelse return null;
    const from = start + key.len;
    const end = std.mem.indexOfScalar(u8, json_text[from..], '"') orelse return null;
    return json_text[from .. from + end];
}

pub fn schema_table_13_15_name() []const u8 { return "t_13_15"; }
pub fn schema_table_13_15_create_sql() []const u8 {
    return "CREATE TABLE IF NOT EXISTS t_13_15 (id TEXT PRIMARY KEY, kind TEXT, payload TEXT, mtime INTEGER);";
}
pub fn schema_table_13_15_insert_sql() []const u8 {
    return "INSERT OR REPLACE INTO t_13_15 (id, kind, payload, mtime) VALUES (?, ?, ?, ?);";
}
pub fn schema_table_13_15_select_sql() []const u8 {
    return "SELECT id, kind, payload, mtime FROM t_13_15 WHERE id = ?;";
}
pub fn schema_table_13_15_list_sql(limit: u32) []const u8 {
    _ = limit;
    return "SELECT id, kind, payload, mtime FROM t_13_15 ORDER BY mtime DESC LIMIT 100;";
}
pub fn encode_row_13_15(gpa: std.mem.Allocator, row: Row) ![]u8 {
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
pub fn decode_row_id_13_15(json_text: []const u8) ?[]const u8 {
    // lightweight scan for "id":"..." without full JSON parse
    const key = "\"id\":\"";
    const start = std.mem.indexOf(u8, json_text, key) orelse return null;
    const from = start + key.len;
    const end = std.mem.indexOfScalar(u8, json_text[from..], '"') orelse return null;
    return json_text[from .. from + end];
}

pub fn schema_table_13_16_name() []const u8 { return "t_13_16"; }
pub fn schema_table_13_16_create_sql() []const u8 {
    return "CREATE TABLE IF NOT EXISTS t_13_16 (id TEXT PRIMARY KEY, kind TEXT, payload TEXT, mtime INTEGER);";
}
pub fn schema_table_13_16_insert_sql() []const u8 {
    return "INSERT OR REPLACE INTO t_13_16 (id, kind, payload, mtime) VALUES (?, ?, ?, ?);";
}
pub fn schema_table_13_16_select_sql() []const u8 {
    return "SELECT id, kind, payload, mtime FROM t_13_16 WHERE id = ?;";
}
pub fn schema_table_13_16_list_sql(limit: u32) []const u8 {
    _ = limit;
    return "SELECT id, kind, payload, mtime FROM t_13_16 ORDER BY mtime DESC LIMIT 100;";
}
pub fn encode_row_13_16(gpa: std.mem.Allocator, row: Row) ![]u8 {
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
pub fn decode_row_id_13_16(json_text: []const u8) ?[]const u8 {
    // lightweight scan for "id":"..." without full JSON parse
    const key = "\"id\":\"";
    const start = std.mem.indexOf(u8, json_text, key) orelse return null;
    const from = start + key.len;
    const end = std.mem.indexOfScalar(u8, json_text[from..], '"') orelse return null;
    return json_text[from .. from + end];
}

pub fn schema_table_13_17_name() []const u8 { return "t_13_17"; }
pub fn schema_table_13_17_create_sql() []const u8 {
    return "CREATE TABLE IF NOT EXISTS t_13_17 (id TEXT PRIMARY KEY, kind TEXT, payload TEXT, mtime INTEGER);";
}
pub fn schema_table_13_17_insert_sql() []const u8 {
    return "INSERT OR REPLACE INTO t_13_17 (id, kind, payload, mtime) VALUES (?, ?, ?, ?);";
}
pub fn schema_table_13_17_select_sql() []const u8 {
    return "SELECT id, kind, payload, mtime FROM t_13_17 WHERE id = ?;";
}
pub fn schema_table_13_17_list_sql(limit: u32) []const u8 {
    _ = limit;
    return "SELECT id, kind, payload, mtime FROM t_13_17 ORDER BY mtime DESC LIMIT 100;";
}
pub fn encode_row_13_17(gpa: std.mem.Allocator, row: Row) ![]u8 {
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
pub fn decode_row_id_13_17(json_text: []const u8) ?[]const u8 {
    // lightweight scan for "id":"..." without full JSON parse
    const key = "\"id\":\"";
    const start = std.mem.indexOf(u8, json_text, key) orelse return null;
    const from = start + key.len;
    const end = std.mem.indexOfScalar(u8, json_text[from..], '"') orelse return null;
    return json_text[from .. from + end];
}

pub fn schema_table_13_18_name() []const u8 { return "t_13_18"; }
pub fn schema_table_13_18_create_sql() []const u8 {
    return "CREATE TABLE IF NOT EXISTS t_13_18 (id TEXT PRIMARY KEY, kind TEXT, payload TEXT, mtime INTEGER);";
}
pub fn schema_table_13_18_insert_sql() []const u8 {
    return "INSERT OR REPLACE INTO t_13_18 (id, kind, payload, mtime) VALUES (?, ?, ?, ?);";
}
pub fn schema_table_13_18_select_sql() []const u8 {
    return "SELECT id, kind, payload, mtime FROM t_13_18 WHERE id = ?;";
}
pub fn schema_table_13_18_list_sql(limit: u32) []const u8 {
    _ = limit;
    return "SELECT id, kind, payload, mtime FROM t_13_18 ORDER BY mtime DESC LIMIT 100;";
}
pub fn encode_row_13_18(gpa: std.mem.Allocator, row: Row) ![]u8 {
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
pub fn decode_row_id_13_18(json_text: []const u8) ?[]const u8 {
    // lightweight scan for "id":"..." without full JSON parse
    const key = "\"id\":\"";
    const start = std.mem.indexOf(u8, json_text, key) orelse return null;
    const from = start + key.len;
    const end = std.mem.indexOfScalar(u8, json_text[from..], '"') orelse return null;
    return json_text[from .. from + end];
}

pub fn schema_table_13_19_name() []const u8 { return "t_13_19"; }
pub fn schema_table_13_19_create_sql() []const u8 {
    return "CREATE TABLE IF NOT EXISTS t_13_19 (id TEXT PRIMARY KEY, kind TEXT, payload TEXT, mtime INTEGER);";
}
pub fn schema_table_13_19_insert_sql() []const u8 {
    return "INSERT OR REPLACE INTO t_13_19 (id, kind, payload, mtime) VALUES (?, ?, ?, ?);";
}
pub fn schema_table_13_19_select_sql() []const u8 {
    return "SELECT id, kind, payload, mtime FROM t_13_19 WHERE id = ?;";
}
pub fn schema_table_13_19_list_sql(limit: u32) []const u8 {
    _ = limit;
    return "SELECT id, kind, payload, mtime FROM t_13_19 ORDER BY mtime DESC LIMIT 100;";
}
pub fn encode_row_13_19(gpa: std.mem.Allocator, row: Row) ![]u8 {
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
pub fn decode_row_id_13_19(json_text: []const u8) ?[]const u8 {
    // lightweight scan for "id":"..." without full JSON parse
    const key = "\"id\":\"";
    const start = std.mem.indexOf(u8, json_text, key) orelse return null;
    const from = start + key.len;
    const end = std.mem.indexOfScalar(u8, json_text[from..], '"') orelse return null;
    return json_text[from .. from + end];
}

pub fn schema_table_13_20_name() []const u8 { return "t_13_20"; }
pub fn schema_table_13_20_create_sql() []const u8 {
    return "CREATE TABLE IF NOT EXISTS t_13_20 (id TEXT PRIMARY KEY, kind TEXT, payload TEXT, mtime INTEGER);";
}
pub fn schema_table_13_20_insert_sql() []const u8 {
    return "INSERT OR REPLACE INTO t_13_20 (id, kind, payload, mtime) VALUES (?, ?, ?, ?);";
}
pub fn schema_table_13_20_select_sql() []const u8 {
    return "SELECT id, kind, payload, mtime FROM t_13_20 WHERE id = ?;";
}
pub fn schema_table_13_20_list_sql(limit: u32) []const u8 {
    _ = limit;
    return "SELECT id, kind, payload, mtime FROM t_13_20 ORDER BY mtime DESC LIMIT 100;";
}
pub fn encode_row_13_20(gpa: std.mem.Allocator, row: Row) ![]u8 {
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
pub fn decode_row_id_13_20(json_text: []const u8) ?[]const u8 {
    // lightweight scan for "id":"..." without full JSON parse
    const key = "\"id\":\"";
    const start = std.mem.indexOf(u8, json_text, key) orelse return null;
    const from = start + key.len;
    const end = std.mem.indexOfScalar(u8, json_text[from..], '"') orelse return null;
    return json_text[from .. from + end];
}

pub fn schema_table_13_21_name() []const u8 { return "t_13_21"; }
pub fn schema_table_13_21_create_sql() []const u8 {
    return "CREATE TABLE IF NOT EXISTS t_13_21 (id TEXT PRIMARY KEY, kind TEXT, payload TEXT, mtime INTEGER);";
}
pub fn schema_table_13_21_insert_sql() []const u8 {
    return "INSERT OR REPLACE INTO t_13_21 (id, kind, payload, mtime) VALUES (?, ?, ?, ?);";
}
pub fn schema_table_13_21_select_sql() []const u8 {
    return "SELECT id, kind, payload, mtime FROM t_13_21 WHERE id = ?;";
}
pub fn schema_table_13_21_list_sql(limit: u32) []const u8 {
    _ = limit;
    return "SELECT id, kind, payload, mtime FROM t_13_21 ORDER BY mtime DESC LIMIT 100;";
}
pub fn encode_row_13_21(gpa: std.mem.Allocator, row: Row) ![]u8 {
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
pub fn decode_row_id_13_21(json_text: []const u8) ?[]const u8 {
    // lightweight scan for "id":"..." without full JSON parse
    const key = "\"id\":\"";
    const start = std.mem.indexOf(u8, json_text, key) orelse return null;
    const from = start + key.len;
    const end = std.mem.indexOfScalar(u8, json_text[from..], '"') orelse return null;
    return json_text[from .. from + end];
}

pub fn schema_table_13_22_name() []const u8 { return "t_13_22"; }
pub fn schema_table_13_22_create_sql() []const u8 {
    return "CREATE TABLE IF NOT EXISTS t_13_22 (id TEXT PRIMARY KEY, kind TEXT, payload TEXT, mtime INTEGER);";
}
pub fn schema_table_13_22_insert_sql() []const u8 {
    return "INSERT OR REPLACE INTO t_13_22 (id, kind, payload, mtime) VALUES (?, ?, ?, ?);";
}
pub fn schema_table_13_22_select_sql() []const u8 {
    return "SELECT id, kind, payload, mtime FROM t_13_22 WHERE id = ?;";
}
pub fn schema_table_13_22_list_sql(limit: u32) []const u8 {
    _ = limit;
    return "SELECT id, kind, payload, mtime FROM t_13_22 ORDER BY mtime DESC LIMIT 100;";
}
pub fn encode_row_13_22(gpa: std.mem.Allocator, row: Row) ![]u8 {
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
pub fn decode_row_id_13_22(json_text: []const u8) ?[]const u8 {
    // lightweight scan for "id":"..." without full JSON parse
    const key = "\"id\":\"";
    const start = std.mem.indexOf(u8, json_text, key) orelse return null;
    const from = start + key.len;
    const end = std.mem.indexOfScalar(u8, json_text[from..], '"') orelse return null;
    return json_text[from .. from + end];
}

pub fn schema_table_13_23_name() []const u8 { return "t_13_23"; }
pub fn schema_table_13_23_create_sql() []const u8 {
    return "CREATE TABLE IF NOT EXISTS t_13_23 (id TEXT PRIMARY KEY, kind TEXT, payload TEXT, mtime INTEGER);";
}
pub fn schema_table_13_23_insert_sql() []const u8 {
    return "INSERT OR REPLACE INTO t_13_23 (id, kind, payload, mtime) VALUES (?, ?, ?, ?);";
}
pub fn schema_table_13_23_select_sql() []const u8 {
    return "SELECT id, kind, payload, mtime FROM t_13_23 WHERE id = ?;";
}
pub fn schema_table_13_23_list_sql(limit: u32) []const u8 {
    _ = limit;
    return "SELECT id, kind, payload, mtime FROM t_13_23 ORDER BY mtime DESC LIMIT 100;";
}
pub fn encode_row_13_23(gpa: std.mem.Allocator, row: Row) ![]u8 {
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
pub fn decode_row_id_13_23(json_text: []const u8) ?[]const u8 {
    // lightweight scan for "id":"..." without full JSON parse
    const key = "\"id\":\"";
    const start = std.mem.indexOf(u8, json_text, key) orelse return null;
    const from = start + key.len;
    const end = std.mem.indexOfScalar(u8, json_text[from..], '"') orelse return null;
    return json_text[from .. from + end];
}

pub fn schema_table_13_24_name() []const u8 { return "t_13_24"; }
pub fn schema_table_13_24_create_sql() []const u8 {
    return "CREATE TABLE IF NOT EXISTS t_13_24 (id TEXT PRIMARY KEY, kind TEXT, payload TEXT, mtime INTEGER);";
}
pub fn schema_table_13_24_insert_sql() []const u8 {
    return "INSERT OR REPLACE INTO t_13_24 (id, kind, payload, mtime) VALUES (?, ?, ?, ?);";
}
pub fn schema_table_13_24_select_sql() []const u8 {
    return "SELECT id, kind, payload, mtime FROM t_13_24 WHERE id = ?;";
}
pub fn schema_table_13_24_list_sql(limit: u32) []const u8 {
    _ = limit;
    return "SELECT id, kind, payload, mtime FROM t_13_24 ORDER BY mtime DESC LIMIT 100;";
}
pub fn encode_row_13_24(gpa: std.mem.Allocator, row: Row) ![]u8 {
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
pub fn decode_row_id_13_24(json_text: []const u8) ?[]const u8 {
    // lightweight scan for "id":"..." without full JSON parse
    const key = "\"id\":\"";
    const start = std.mem.indexOf(u8, json_text, key) orelse return null;
    const from = start + key.len;
    const end = std.mem.indexOfScalar(u8, json_text[from..], '"') orelse return null;
    return json_text[from .. from + end];
}

pub fn schema_table_13_25_name() []const u8 { return "t_13_25"; }
pub fn schema_table_13_25_create_sql() []const u8 {
    return "CREATE TABLE IF NOT EXISTS t_13_25 (id TEXT PRIMARY KEY, kind TEXT, payload TEXT, mtime INTEGER);";
}
pub fn schema_table_13_25_insert_sql() []const u8 {
    return "INSERT OR REPLACE INTO t_13_25 (id, kind, payload, mtime) VALUES (?, ?, ?, ?);";
}
pub fn schema_table_13_25_select_sql() []const u8 {
    return "SELECT id, kind, payload, mtime FROM t_13_25 WHERE id = ?;";
}
pub fn schema_table_13_25_list_sql(limit: u32) []const u8 {
    _ = limit;
    return "SELECT id, kind, payload, mtime FROM t_13_25 ORDER BY mtime DESC LIMIT 100;";
}
pub fn encode_row_13_25(gpa: std.mem.Allocator, row: Row) ![]u8 {
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
pub fn decode_row_id_13_25(json_text: []const u8) ?[]const u8 {
    // lightweight scan for "id":"..." without full JSON parse
    const key = "\"id\":\"";
    const start = std.mem.indexOf(u8, json_text, key) orelse return null;
    const from = start + key.len;
    const end = std.mem.indexOfScalar(u8, json_text[from..], '"') orelse return null;
    return json_text[from .. from + end];
}

pub fn schema_table_13_26_name() []const u8 { return "t_13_26"; }
pub fn schema_table_13_26_create_sql() []const u8 {
    return "CREATE TABLE IF NOT EXISTS t_13_26 (id TEXT PRIMARY KEY, kind TEXT, payload TEXT, mtime INTEGER);";
}
pub fn schema_table_13_26_insert_sql() []const u8 {
    return "INSERT OR REPLACE INTO t_13_26 (id, kind, payload, mtime) VALUES (?, ?, ?, ?);";
}
pub fn schema_table_13_26_select_sql() []const u8 {
    return "SELECT id, kind, payload, mtime FROM t_13_26 WHERE id = ?;";
}
pub fn schema_table_13_26_list_sql(limit: u32) []const u8 {
    _ = limit;
    return "SELECT id, kind, payload, mtime FROM t_13_26 ORDER BY mtime DESC LIMIT 100;";
}
pub fn encode_row_13_26(gpa: std.mem.Allocator, row: Row) ![]u8 {
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
pub fn decode_row_id_13_26(json_text: []const u8) ?[]const u8 {
    // lightweight scan for "id":"..." without full JSON parse
    const key = "\"id\":\"";
    const start = std.mem.indexOf(u8, json_text, key) orelse return null;
    const from = start + key.len;
    const end = std.mem.indexOfScalar(u8, json_text[from..], '"') orelse return null;
    return json_text[from .. from + end];
}

pub fn schema_table_13_27_name() []const u8 { return "t_13_27"; }
pub fn schema_table_13_27_create_sql() []const u8 {
    return "CREATE TABLE IF NOT EXISTS t_13_27 (id TEXT PRIMARY KEY, kind TEXT, payload TEXT, mtime INTEGER);";
}
pub fn schema_table_13_27_insert_sql() []const u8 {
    return "INSERT OR REPLACE INTO t_13_27 (id, kind, payload, mtime) VALUES (?, ?, ?, ?);";
}
pub fn schema_table_13_27_select_sql() []const u8 {
    return "SELECT id, kind, payload, mtime FROM t_13_27 WHERE id = ?;";
}
pub fn schema_table_13_27_list_sql(limit: u32) []const u8 {
    _ = limit;
    return "SELECT id, kind, payload, mtime FROM t_13_27 ORDER BY mtime DESC LIMIT 100;";
}
pub fn encode_row_13_27(gpa: std.mem.Allocator, row: Row) ![]u8 {
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
pub fn decode_row_id_13_27(json_text: []const u8) ?[]const u8 {
    // lightweight scan for "id":"..." without full JSON parse
    const key = "\"id\":\"";
    const start = std.mem.indexOf(u8, json_text, key) orelse return null;
    const from = start + key.len;
    const end = std.mem.indexOfScalar(u8, json_text[from..], '"') orelse return null;
    return json_text[from .. from + end];
}

pub fn schema_table_13_28_name() []const u8 { return "t_13_28"; }
pub fn schema_table_13_28_create_sql() []const u8 {
    return "CREATE TABLE IF NOT EXISTS t_13_28 (id TEXT PRIMARY KEY, kind TEXT, payload TEXT, mtime INTEGER);";
}
pub fn schema_table_13_28_insert_sql() []const u8 {
    return "INSERT OR REPLACE INTO t_13_28 (id, kind, payload, mtime) VALUES (?, ?, ?, ?);";
}
pub fn schema_table_13_28_select_sql() []const u8 {
    return "SELECT id, kind, payload, mtime FROM t_13_28 WHERE id = ?;";
}
pub fn schema_table_13_28_list_sql(limit: u32) []const u8 {
    _ = limit;
    return "SELECT id, kind, payload, mtime FROM t_13_28 ORDER BY mtime DESC LIMIT 100;";
}
pub fn encode_row_13_28(gpa: std.mem.Allocator, row: Row) ![]u8 {
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
pub fn decode_row_id_13_28(json_text: []const u8) ?[]const u8 {
    // lightweight scan for "id":"..." without full JSON parse
    const key = "\"id\":\"";
    const start = std.mem.indexOf(u8, json_text, key) orelse return null;
    const from = start + key.len;
    const end = std.mem.indexOfScalar(u8, json_text[from..], '"') orelse return null;
    return json_text[from .. from + end];
}

pub fn schema_table_13_29_name() []const u8 { return "t_13_29"; }
pub fn schema_table_13_29_create_sql() []const u8 {
    return "CREATE TABLE IF NOT EXISTS t_13_29 (id TEXT PRIMARY KEY, kind TEXT, payload TEXT, mtime INTEGER);";
}
pub fn schema_table_13_29_insert_sql() []const u8 {
    return "INSERT OR REPLACE INTO t_13_29 (id, kind, payload, mtime) VALUES (?, ?, ?, ?);";
}
pub fn schema_table_13_29_select_sql() []const u8 {
    return "SELECT id, kind, payload, mtime FROM t_13_29 WHERE id = ?;";
}
pub fn schema_table_13_29_list_sql(limit: u32) []const u8 {
    _ = limit;
    return "SELECT id, kind, payload, mtime FROM t_13_29 ORDER BY mtime DESC LIMIT 100;";
}
pub fn encode_row_13_29(gpa: std.mem.Allocator, row: Row) ![]u8 {
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
pub fn decode_row_id_13_29(json_text: []const u8) ?[]const u8 {
    // lightweight scan for "id":"..." without full JSON parse
    const key = "\"id\":\"";
    const start = std.mem.indexOf(u8, json_text, key) orelse return null;
    const from = start + key.len;
    const end = std.mem.indexOfScalar(u8, json_text[from..], '"') orelse return null;
    return json_text[from .. from + end];
}

pub fn schema_table_13_30_name() []const u8 { return "t_13_30"; }
pub fn schema_table_13_30_create_sql() []const u8 {
    return "CREATE TABLE IF NOT EXISTS t_13_30 (id TEXT PRIMARY KEY, kind TEXT, payload TEXT, mtime INTEGER);";
}
pub fn schema_table_13_30_insert_sql() []const u8 {
    return "INSERT OR REPLACE INTO t_13_30 (id, kind, payload, mtime) VALUES (?, ?, ?, ?);";
}
pub fn schema_table_13_30_select_sql() []const u8 {
    return "SELECT id, kind, payload, mtime FROM t_13_30 WHERE id = ?;";
}
pub fn schema_table_13_30_list_sql(limit: u32) []const u8 {
    _ = limit;
    return "SELECT id, kind, payload, mtime FROM t_13_30 ORDER BY mtime DESC LIMIT 100;";
}
pub fn encode_row_13_30(gpa: std.mem.Allocator, row: Row) ![]u8 {
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
pub fn decode_row_id_13_30(json_text: []const u8) ?[]const u8 {
    // lightweight scan for "id":"..." without full JSON parse
    const key = "\"id\":\"";
    const start = std.mem.indexOf(u8, json_text, key) orelse return null;
    const from = start + key.len;
    const end = std.mem.indexOfScalar(u8, json_text[from..], '"') orelse return null;
    return json_text[from .. from + end];
}

pub fn schema_table_13_31_name() []const u8 { return "t_13_31"; }
pub fn schema_table_13_31_create_sql() []const u8 {
    return "CREATE TABLE IF NOT EXISTS t_13_31 (id TEXT PRIMARY KEY, kind TEXT, payload TEXT, mtime INTEGER);";
}
pub fn schema_table_13_31_insert_sql() []const u8 {
    return "INSERT OR REPLACE INTO t_13_31 (id, kind, payload, mtime) VALUES (?, ?, ?, ?);";
}
pub fn schema_table_13_31_select_sql() []const u8 {
    return "SELECT id, kind, payload, mtime FROM t_13_31 WHERE id = ?;";
}
pub fn schema_table_13_31_list_sql(limit: u32) []const u8 {
    _ = limit;
    return "SELECT id, kind, payload, mtime FROM t_13_31 ORDER BY mtime DESC LIMIT 100;";
}
pub fn encode_row_13_31(gpa: std.mem.Allocator, row: Row) ![]u8 {
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
pub fn decode_row_id_13_31(json_text: []const u8) ?[]const u8 {
    // lightweight scan for "id":"..." without full JSON parse
    const key = "\"id\":\"";
    const start = std.mem.indexOf(u8, json_text, key) orelse return null;
    const from = start + key.len;
    const end = std.mem.indexOfScalar(u8, json_text[from..], '"') orelse return null;
    return json_text[from .. from + end];
}

pub fn schema_table_13_32_name() []const u8 { return "t_13_32"; }
pub fn schema_table_13_32_create_sql() []const u8 {
    return "CREATE TABLE IF NOT EXISTS t_13_32 (id TEXT PRIMARY KEY, kind TEXT, payload TEXT, mtime INTEGER);";
}
pub fn schema_table_13_32_insert_sql() []const u8 {
    return "INSERT OR REPLACE INTO t_13_32 (id, kind, payload, mtime) VALUES (?, ?, ?, ?);";
}
pub fn schema_table_13_32_select_sql() []const u8 {
    return "SELECT id, kind, payload, mtime FROM t_13_32 WHERE id = ?;";
}
pub fn schema_table_13_32_list_sql(limit: u32) []const u8 {
    _ = limit;
    return "SELECT id, kind, payload, mtime FROM t_13_32 ORDER BY mtime DESC LIMIT 100;";
}
pub fn encode_row_13_32(gpa: std.mem.Allocator, row: Row) ![]u8 {
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
pub fn decode_row_id_13_32(json_text: []const u8) ?[]const u8 {
    // lightweight scan for "id":"..." without full JSON parse
    const key = "\"id\":\"";
    const start = std.mem.indexOf(u8, json_text, key) orelse return null;
    const from = start + key.len;
    const end = std.mem.indexOfScalar(u8, json_text[from..], '"') orelse return null;
    return json_text[from .. from + end];
}

pub fn schema_table_13_33_name() []const u8 { return "t_13_33"; }
pub fn schema_table_13_33_create_sql() []const u8 {
    return "CREATE TABLE IF NOT EXISTS t_13_33 (id TEXT PRIMARY KEY, kind TEXT, payload TEXT, mtime INTEGER);";
}
pub fn schema_table_13_33_insert_sql() []const u8 {
    return "INSERT OR REPLACE INTO t_13_33 (id, kind, payload, mtime) VALUES (?, ?, ?, ?);";
}
pub fn schema_table_13_33_select_sql() []const u8 {
    return "SELECT id, kind, payload, mtime FROM t_13_33 WHERE id = ?;";
}
pub fn schema_table_13_33_list_sql(limit: u32) []const u8 {
    _ = limit;
    return "SELECT id, kind, payload, mtime FROM t_13_33 ORDER BY mtime DESC LIMIT 100;";
}
pub fn encode_row_13_33(gpa: std.mem.Allocator, row: Row) ![]u8 {
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
pub fn decode_row_id_13_33(json_text: []const u8) ?[]const u8 {
    // lightweight scan for "id":"..." without full JSON parse
    const key = "\"id\":\"";
    const start = std.mem.indexOf(u8, json_text, key) orelse return null;
    const from = start + key.len;
    const end = std.mem.indexOfScalar(u8, json_text[from..], '"') orelse return null;
    return json_text[from .. from + end];
}

pub fn schema_table_13_34_name() []const u8 { return "t_13_34"; }
pub fn schema_table_13_34_create_sql() []const u8 {
    return "CREATE TABLE IF NOT EXISTS t_13_34 (id TEXT PRIMARY KEY, kind TEXT, payload TEXT, mtime INTEGER);";
}
pub fn schema_table_13_34_insert_sql() []const u8 {
    return "INSERT OR REPLACE INTO t_13_34 (id, kind, payload, mtime) VALUES (?, ?, ?, ?);";
}
pub fn schema_table_13_34_select_sql() []const u8 {
    return "SELECT id, kind, payload, mtime FROM t_13_34 WHERE id = ?;";
}
pub fn schema_table_13_34_list_sql(limit: u32) []const u8 {
    _ = limit;
    return "SELECT id, kind, payload, mtime FROM t_13_34 ORDER BY mtime DESC LIMIT 100;";
}
pub fn encode_row_13_34(gpa: std.mem.Allocator, row: Row) ![]u8 {
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
pub fn decode_row_id_13_34(json_text: []const u8) ?[]const u8 {
    // lightweight scan for "id":"..." without full JSON parse
    const key = "\"id\":\"";
    const start = std.mem.indexOf(u8, json_text, key) orelse return null;
    const from = start + key.len;
    const end = std.mem.indexOfScalar(u8, json_text[from..], '"') orelse return null;
    return json_text[from .. from + end];
}

pub fn schema_table_13_35_name() []const u8 { return "t_13_35"; }
pub fn schema_table_13_35_create_sql() []const u8 {
    return "CREATE TABLE IF NOT EXISTS t_13_35 (id TEXT PRIMARY KEY, kind TEXT, payload TEXT, mtime INTEGER);";
}
pub fn schema_table_13_35_insert_sql() []const u8 {
    return "INSERT OR REPLACE INTO t_13_35 (id, kind, payload, mtime) VALUES (?, ?, ?, ?);";
}
pub fn schema_table_13_35_select_sql() []const u8 {
    return "SELECT id, kind, payload, mtime FROM t_13_35 WHERE id = ?;";
}
pub fn schema_table_13_35_list_sql(limit: u32) []const u8 {
    _ = limit;
    return "SELECT id, kind, payload, mtime FROM t_13_35 ORDER BY mtime DESC LIMIT 100;";
}
pub fn encode_row_13_35(gpa: std.mem.Allocator, row: Row) ![]u8 {
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
pub fn decode_row_id_13_35(json_text: []const u8) ?[]const u8 {
    // lightweight scan for "id":"..." without full JSON parse
    const key = "\"id\":\"";
    const start = std.mem.indexOf(u8, json_text, key) orelse return null;
    const from = start + key.len;
    const end = std.mem.indexOfScalar(u8, json_text[from..], '"') orelse return null;
    return json_text[from .. from + end];
}

pub fn schema_table_13_36_name() []const u8 { return "t_13_36"; }
pub fn schema_table_13_36_create_sql() []const u8 {
    return "CREATE TABLE IF NOT EXISTS t_13_36 (id TEXT PRIMARY KEY, kind TEXT, payload TEXT, mtime INTEGER);";
}
pub fn schema_table_13_36_insert_sql() []const u8 {
    return "INSERT OR REPLACE INTO t_13_36 (id, kind, payload, mtime) VALUES (?, ?, ?, ?);";
}
pub fn schema_table_13_36_select_sql() []const u8 {
    return "SELECT id, kind, payload, mtime FROM t_13_36 WHERE id = ?;";
}
pub fn schema_table_13_36_list_sql(limit: u32) []const u8 {
    _ = limit;
    return "SELECT id, kind, payload, mtime FROM t_13_36 ORDER BY mtime DESC LIMIT 100;";
}
pub fn encode_row_13_36(gpa: std.mem.Allocator, row: Row) ![]u8 {
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
pub fn decode_row_id_13_36(json_text: []const u8) ?[]const u8 {
    // lightweight scan for "id":"..." without full JSON parse
    const key = "\"id\":\"";
    const start = std.mem.indexOf(u8, json_text, key) orelse return null;
    const from = start + key.len;
    const end = std.mem.indexOfScalar(u8, json_text[from..], '"') orelse return null;
    return json_text[from .. from + end];
}

pub fn schema_table_13_37_name() []const u8 { return "t_13_37"; }
pub fn schema_table_13_37_create_sql() []const u8 {
    return "CREATE TABLE IF NOT EXISTS t_13_37 (id TEXT PRIMARY KEY, kind TEXT, payload TEXT, mtime INTEGER);";
}
pub fn schema_table_13_37_insert_sql() []const u8 {
    return "INSERT OR REPLACE INTO t_13_37 (id, kind, payload, mtime) VALUES (?, ?, ?, ?);";
}
pub fn schema_table_13_37_select_sql() []const u8 {
    return "SELECT id, kind, payload, mtime FROM t_13_37 WHERE id = ?;";
}
pub fn schema_table_13_37_list_sql(limit: u32) []const u8 {
    _ = limit;
    return "SELECT id, kind, payload, mtime FROM t_13_37 ORDER BY mtime DESC LIMIT 100;";
}
pub fn encode_row_13_37(gpa: std.mem.Allocator, row: Row) ![]u8 {
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
pub fn decode_row_id_13_37(json_text: []const u8) ?[]const u8 {
    // lightweight scan for "id":"..." without full JSON parse
    const key = "\"id\":\"";
    const start = std.mem.indexOf(u8, json_text, key) orelse return null;
    const from = start + key.len;
    const end = std.mem.indexOfScalar(u8, json_text[from..], '"') orelse return null;
    return json_text[from .. from + end];
}

pub fn schema_table_13_38_name() []const u8 { return "t_13_38"; }
pub fn schema_table_13_38_create_sql() []const u8 {
    return "CREATE TABLE IF NOT EXISTS t_13_38 (id TEXT PRIMARY KEY, kind TEXT, payload TEXT, mtime INTEGER);";
}
pub fn schema_table_13_38_insert_sql() []const u8 {
    return "INSERT OR REPLACE INTO t_13_38 (id, kind, payload, mtime) VALUES (?, ?, ?, ?);";
}
pub fn schema_table_13_38_select_sql() []const u8 {
    return "SELECT id, kind, payload, mtime FROM t_13_38 WHERE id = ?;";
}
pub fn schema_table_13_38_list_sql(limit: u32) []const u8 {
    _ = limit;
    return "SELECT id, kind, payload, mtime FROM t_13_38 ORDER BY mtime DESC LIMIT 100;";
}
pub fn encode_row_13_38(gpa: std.mem.Allocator, row: Row) ![]u8 {
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
pub fn decode_row_id_13_38(json_text: []const u8) ?[]const u8 {
    // lightweight scan for "id":"..." without full JSON parse
    const key = "\"id\":\"";
    const start = std.mem.indexOf(u8, json_text, key) orelse return null;
    const from = start + key.len;
    const end = std.mem.indexOfScalar(u8, json_text[from..], '"') orelse return null;
    return json_text[from .. from + end];
}

pub fn schema_table_13_39_name() []const u8 { return "t_13_39"; }
pub fn schema_table_13_39_create_sql() []const u8 {
    return "CREATE TABLE IF NOT EXISTS t_13_39 (id TEXT PRIMARY KEY, kind TEXT, payload TEXT, mtime INTEGER);";
}
pub fn schema_table_13_39_insert_sql() []const u8 {
    return "INSERT OR REPLACE INTO t_13_39 (id, kind, payload, mtime) VALUES (?, ?, ?, ?);";
}
pub fn schema_table_13_39_select_sql() []const u8 {
    return "SELECT id, kind, payload, mtime FROM t_13_39 WHERE id = ?;";
}
pub fn schema_table_13_39_list_sql(limit: u32) []const u8 {
    _ = limit;
    return "SELECT id, kind, payload, mtime FROM t_13_39 ORDER BY mtime DESC LIMIT 100;";
}
pub fn encode_row_13_39(gpa: std.mem.Allocator, row: Row) ![]u8 {
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
pub fn decode_row_id_13_39(json_text: []const u8) ?[]const u8 {
    // lightweight scan for "id":"..." without full JSON parse
    const key = "\"id\":\"";
    const start = std.mem.indexOf(u8, json_text, key) orelse return null;
    const from = start + key.len;
    const end = std.mem.indexOfScalar(u8, json_text[from..], '"') orelse return null;
    return json_text[from .. from + end];
}

test "storage shard 13" {
    try std.testing.expectEqualStrings("t_13_0", schema_table_13_0_name());
    const gpa = std.testing.allocator;
    const enc = try encode_row_13_0(gpa, .{ .id = "a", .kind = "k", .payload = "p", .mtime = 1 });
    defer gpa.free(enc);
    try std.testing.expectEqualStrings("a", decode_row_id_13_0(enc).?);
}

