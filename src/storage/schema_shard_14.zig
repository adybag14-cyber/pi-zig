//! Generated storage schema/query helpers shard 14.
const std = @import("std");

pub const Row = struct {
    id: []const u8,
    kind: []const u8,
    payload: []const u8,
    mtime: i64,
};

pub fn schema_table_14_0_name() []const u8 { return "t_14_0"; }
pub fn schema_table_14_0_create_sql() []const u8 {
    return "CREATE TABLE IF NOT EXISTS t_14_0 (id TEXT PRIMARY KEY, kind TEXT, payload TEXT, mtime INTEGER);";
}
pub fn schema_table_14_0_insert_sql() []const u8 {
    return "INSERT OR REPLACE INTO t_14_0 (id, kind, payload, mtime) VALUES (?, ?, ?, ?);";
}
pub fn schema_table_14_0_select_sql() []const u8 {
    return "SELECT id, kind, payload, mtime FROM t_14_0 WHERE id = ?;";
}
pub fn schema_table_14_0_list_sql(limit: u32) []const u8 {
    _ = limit;
    return "SELECT id, kind, payload, mtime FROM t_14_0 ORDER BY mtime DESC LIMIT 100;";
}
pub fn encode_row_14_0(gpa: std.mem.Allocator, row: Row) ![]u8 {
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
pub fn decode_row_id_14_0(json_text: []const u8) ?[]const u8 {
    // lightweight scan for "id":"..." without full JSON parse
    const key = "\"id\":\"";
    const start = std.mem.indexOf(u8, json_text, key) orelse return null;
    const from = start + key.len;
    const end = std.mem.indexOfScalar(u8, json_text[from..], '"') orelse return null;
    return json_text[from .. from + end];
}

pub fn schema_table_14_1_name() []const u8 { return "t_14_1"; }
pub fn schema_table_14_1_create_sql() []const u8 {
    return "CREATE TABLE IF NOT EXISTS t_14_1 (id TEXT PRIMARY KEY, kind TEXT, payload TEXT, mtime INTEGER);";
}
pub fn schema_table_14_1_insert_sql() []const u8 {
    return "INSERT OR REPLACE INTO t_14_1 (id, kind, payload, mtime) VALUES (?, ?, ?, ?);";
}
pub fn schema_table_14_1_select_sql() []const u8 {
    return "SELECT id, kind, payload, mtime FROM t_14_1 WHERE id = ?;";
}
pub fn schema_table_14_1_list_sql(limit: u32) []const u8 {
    _ = limit;
    return "SELECT id, kind, payload, mtime FROM t_14_1 ORDER BY mtime DESC LIMIT 100;";
}
pub fn encode_row_14_1(gpa: std.mem.Allocator, row: Row) ![]u8 {
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
pub fn decode_row_id_14_1(json_text: []const u8) ?[]const u8 {
    // lightweight scan for "id":"..." without full JSON parse
    const key = "\"id\":\"";
    const start = std.mem.indexOf(u8, json_text, key) orelse return null;
    const from = start + key.len;
    const end = std.mem.indexOfScalar(u8, json_text[from..], '"') orelse return null;
    return json_text[from .. from + end];
}

pub fn schema_table_14_2_name() []const u8 { return "t_14_2"; }
pub fn schema_table_14_2_create_sql() []const u8 {
    return "CREATE TABLE IF NOT EXISTS t_14_2 (id TEXT PRIMARY KEY, kind TEXT, payload TEXT, mtime INTEGER);";
}
pub fn schema_table_14_2_insert_sql() []const u8 {
    return "INSERT OR REPLACE INTO t_14_2 (id, kind, payload, mtime) VALUES (?, ?, ?, ?);";
}
pub fn schema_table_14_2_select_sql() []const u8 {
    return "SELECT id, kind, payload, mtime FROM t_14_2 WHERE id = ?;";
}
pub fn schema_table_14_2_list_sql(limit: u32) []const u8 {
    _ = limit;
    return "SELECT id, kind, payload, mtime FROM t_14_2 ORDER BY mtime DESC LIMIT 100;";
}
pub fn encode_row_14_2(gpa: std.mem.Allocator, row: Row) ![]u8 {
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
pub fn decode_row_id_14_2(json_text: []const u8) ?[]const u8 {
    // lightweight scan for "id":"..." without full JSON parse
    const key = "\"id\":\"";
    const start = std.mem.indexOf(u8, json_text, key) orelse return null;
    const from = start + key.len;
    const end = std.mem.indexOfScalar(u8, json_text[from..], '"') orelse return null;
    return json_text[from .. from + end];
}

pub fn schema_table_14_3_name() []const u8 { return "t_14_3"; }
pub fn schema_table_14_3_create_sql() []const u8 {
    return "CREATE TABLE IF NOT EXISTS t_14_3 (id TEXT PRIMARY KEY, kind TEXT, payload TEXT, mtime INTEGER);";
}
pub fn schema_table_14_3_insert_sql() []const u8 {
    return "INSERT OR REPLACE INTO t_14_3 (id, kind, payload, mtime) VALUES (?, ?, ?, ?);";
}
pub fn schema_table_14_3_select_sql() []const u8 {
    return "SELECT id, kind, payload, mtime FROM t_14_3 WHERE id = ?;";
}
pub fn schema_table_14_3_list_sql(limit: u32) []const u8 {
    _ = limit;
    return "SELECT id, kind, payload, mtime FROM t_14_3 ORDER BY mtime DESC LIMIT 100;";
}
pub fn encode_row_14_3(gpa: std.mem.Allocator, row: Row) ![]u8 {
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
pub fn decode_row_id_14_3(json_text: []const u8) ?[]const u8 {
    // lightweight scan for "id":"..." without full JSON parse
    const key = "\"id\":\"";
    const start = std.mem.indexOf(u8, json_text, key) orelse return null;
    const from = start + key.len;
    const end = std.mem.indexOfScalar(u8, json_text[from..], '"') orelse return null;
    return json_text[from .. from + end];
}

pub fn schema_table_14_4_name() []const u8 { return "t_14_4"; }
pub fn schema_table_14_4_create_sql() []const u8 {
    return "CREATE TABLE IF NOT EXISTS t_14_4 (id TEXT PRIMARY KEY, kind TEXT, payload TEXT, mtime INTEGER);";
}
pub fn schema_table_14_4_insert_sql() []const u8 {
    return "INSERT OR REPLACE INTO t_14_4 (id, kind, payload, mtime) VALUES (?, ?, ?, ?);";
}
pub fn schema_table_14_4_select_sql() []const u8 {
    return "SELECT id, kind, payload, mtime FROM t_14_4 WHERE id = ?;";
}
pub fn schema_table_14_4_list_sql(limit: u32) []const u8 {
    _ = limit;
    return "SELECT id, kind, payload, mtime FROM t_14_4 ORDER BY mtime DESC LIMIT 100;";
}
pub fn encode_row_14_4(gpa: std.mem.Allocator, row: Row) ![]u8 {
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
pub fn decode_row_id_14_4(json_text: []const u8) ?[]const u8 {
    // lightweight scan for "id":"..." without full JSON parse
    const key = "\"id\":\"";
    const start = std.mem.indexOf(u8, json_text, key) orelse return null;
    const from = start + key.len;
    const end = std.mem.indexOfScalar(u8, json_text[from..], '"') orelse return null;
    return json_text[from .. from + end];
}

pub fn schema_table_14_5_name() []const u8 { return "t_14_5"; }
pub fn schema_table_14_5_create_sql() []const u8 {
    return "CREATE TABLE IF NOT EXISTS t_14_5 (id TEXT PRIMARY KEY, kind TEXT, payload TEXT, mtime INTEGER);";
}
pub fn schema_table_14_5_insert_sql() []const u8 {
    return "INSERT OR REPLACE INTO t_14_5 (id, kind, payload, mtime) VALUES (?, ?, ?, ?);";
}
pub fn schema_table_14_5_select_sql() []const u8 {
    return "SELECT id, kind, payload, mtime FROM t_14_5 WHERE id = ?;";
}
pub fn schema_table_14_5_list_sql(limit: u32) []const u8 {
    _ = limit;
    return "SELECT id, kind, payload, mtime FROM t_14_5 ORDER BY mtime DESC LIMIT 100;";
}
pub fn encode_row_14_5(gpa: std.mem.Allocator, row: Row) ![]u8 {
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
pub fn decode_row_id_14_5(json_text: []const u8) ?[]const u8 {
    // lightweight scan for "id":"..." without full JSON parse
    const key = "\"id\":\"";
    const start = std.mem.indexOf(u8, json_text, key) orelse return null;
    const from = start + key.len;
    const end = std.mem.indexOfScalar(u8, json_text[from..], '"') orelse return null;
    return json_text[from .. from + end];
}

pub fn schema_table_14_6_name() []const u8 { return "t_14_6"; }
pub fn schema_table_14_6_create_sql() []const u8 {
    return "CREATE TABLE IF NOT EXISTS t_14_6 (id TEXT PRIMARY KEY, kind TEXT, payload TEXT, mtime INTEGER);";
}
pub fn schema_table_14_6_insert_sql() []const u8 {
    return "INSERT OR REPLACE INTO t_14_6 (id, kind, payload, mtime) VALUES (?, ?, ?, ?);";
}
pub fn schema_table_14_6_select_sql() []const u8 {
    return "SELECT id, kind, payload, mtime FROM t_14_6 WHERE id = ?;";
}
pub fn schema_table_14_6_list_sql(limit: u32) []const u8 {
    _ = limit;
    return "SELECT id, kind, payload, mtime FROM t_14_6 ORDER BY mtime DESC LIMIT 100;";
}
pub fn encode_row_14_6(gpa: std.mem.Allocator, row: Row) ![]u8 {
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
pub fn decode_row_id_14_6(json_text: []const u8) ?[]const u8 {
    // lightweight scan for "id":"..." without full JSON parse
    const key = "\"id\":\"";
    const start = std.mem.indexOf(u8, json_text, key) orelse return null;
    const from = start + key.len;
    const end = std.mem.indexOfScalar(u8, json_text[from..], '"') orelse return null;
    return json_text[from .. from + end];
}

pub fn schema_table_14_7_name() []const u8 { return "t_14_7"; }
pub fn schema_table_14_7_create_sql() []const u8 {
    return "CREATE TABLE IF NOT EXISTS t_14_7 (id TEXT PRIMARY KEY, kind TEXT, payload TEXT, mtime INTEGER);";
}
pub fn schema_table_14_7_insert_sql() []const u8 {
    return "INSERT OR REPLACE INTO t_14_7 (id, kind, payload, mtime) VALUES (?, ?, ?, ?);";
}
pub fn schema_table_14_7_select_sql() []const u8 {
    return "SELECT id, kind, payload, mtime FROM t_14_7 WHERE id = ?;";
}
pub fn schema_table_14_7_list_sql(limit: u32) []const u8 {
    _ = limit;
    return "SELECT id, kind, payload, mtime FROM t_14_7 ORDER BY mtime DESC LIMIT 100;";
}
pub fn encode_row_14_7(gpa: std.mem.Allocator, row: Row) ![]u8 {
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
pub fn decode_row_id_14_7(json_text: []const u8) ?[]const u8 {
    // lightweight scan for "id":"..." without full JSON parse
    const key = "\"id\":\"";
    const start = std.mem.indexOf(u8, json_text, key) orelse return null;
    const from = start + key.len;
    const end = std.mem.indexOfScalar(u8, json_text[from..], '"') orelse return null;
    return json_text[from .. from + end];
}

pub fn schema_table_14_8_name() []const u8 { return "t_14_8"; }
pub fn schema_table_14_8_create_sql() []const u8 {
    return "CREATE TABLE IF NOT EXISTS t_14_8 (id TEXT PRIMARY KEY, kind TEXT, payload TEXT, mtime INTEGER);";
}
pub fn schema_table_14_8_insert_sql() []const u8 {
    return "INSERT OR REPLACE INTO t_14_8 (id, kind, payload, mtime) VALUES (?, ?, ?, ?);";
}
pub fn schema_table_14_8_select_sql() []const u8 {
    return "SELECT id, kind, payload, mtime FROM t_14_8 WHERE id = ?;";
}
pub fn schema_table_14_8_list_sql(limit: u32) []const u8 {
    _ = limit;
    return "SELECT id, kind, payload, mtime FROM t_14_8 ORDER BY mtime DESC LIMIT 100;";
}
pub fn encode_row_14_8(gpa: std.mem.Allocator, row: Row) ![]u8 {
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
pub fn decode_row_id_14_8(json_text: []const u8) ?[]const u8 {
    // lightweight scan for "id":"..." without full JSON parse
    const key = "\"id\":\"";
    const start = std.mem.indexOf(u8, json_text, key) orelse return null;
    const from = start + key.len;
    const end = std.mem.indexOfScalar(u8, json_text[from..], '"') orelse return null;
    return json_text[from .. from + end];
}

pub fn schema_table_14_9_name() []const u8 { return "t_14_9"; }
pub fn schema_table_14_9_create_sql() []const u8 {
    return "CREATE TABLE IF NOT EXISTS t_14_9 (id TEXT PRIMARY KEY, kind TEXT, payload TEXT, mtime INTEGER);";
}
pub fn schema_table_14_9_insert_sql() []const u8 {
    return "INSERT OR REPLACE INTO t_14_9 (id, kind, payload, mtime) VALUES (?, ?, ?, ?);";
}
pub fn schema_table_14_9_select_sql() []const u8 {
    return "SELECT id, kind, payload, mtime FROM t_14_9 WHERE id = ?;";
}
pub fn schema_table_14_9_list_sql(limit: u32) []const u8 {
    _ = limit;
    return "SELECT id, kind, payload, mtime FROM t_14_9 ORDER BY mtime DESC LIMIT 100;";
}
pub fn encode_row_14_9(gpa: std.mem.Allocator, row: Row) ![]u8 {
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
pub fn decode_row_id_14_9(json_text: []const u8) ?[]const u8 {
    // lightweight scan for "id":"..." without full JSON parse
    const key = "\"id\":\"";
    const start = std.mem.indexOf(u8, json_text, key) orelse return null;
    const from = start + key.len;
    const end = std.mem.indexOfScalar(u8, json_text[from..], '"') orelse return null;
    return json_text[from .. from + end];
}

pub fn schema_table_14_10_name() []const u8 { return "t_14_10"; }
pub fn schema_table_14_10_create_sql() []const u8 {
    return "CREATE TABLE IF NOT EXISTS t_14_10 (id TEXT PRIMARY KEY, kind TEXT, payload TEXT, mtime INTEGER);";
}
pub fn schema_table_14_10_insert_sql() []const u8 {
    return "INSERT OR REPLACE INTO t_14_10 (id, kind, payload, mtime) VALUES (?, ?, ?, ?);";
}
pub fn schema_table_14_10_select_sql() []const u8 {
    return "SELECT id, kind, payload, mtime FROM t_14_10 WHERE id = ?;";
}
pub fn schema_table_14_10_list_sql(limit: u32) []const u8 {
    _ = limit;
    return "SELECT id, kind, payload, mtime FROM t_14_10 ORDER BY mtime DESC LIMIT 100;";
}
pub fn encode_row_14_10(gpa: std.mem.Allocator, row: Row) ![]u8 {
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
pub fn decode_row_id_14_10(json_text: []const u8) ?[]const u8 {
    // lightweight scan for "id":"..." without full JSON parse
    const key = "\"id\":\"";
    const start = std.mem.indexOf(u8, json_text, key) orelse return null;
    const from = start + key.len;
    const end = std.mem.indexOfScalar(u8, json_text[from..], '"') orelse return null;
    return json_text[from .. from + end];
}

pub fn schema_table_14_11_name() []const u8 { return "t_14_11"; }
pub fn schema_table_14_11_create_sql() []const u8 {
    return "CREATE TABLE IF NOT EXISTS t_14_11 (id TEXT PRIMARY KEY, kind TEXT, payload TEXT, mtime INTEGER);";
}
pub fn schema_table_14_11_insert_sql() []const u8 {
    return "INSERT OR REPLACE INTO t_14_11 (id, kind, payload, mtime) VALUES (?, ?, ?, ?);";
}
pub fn schema_table_14_11_select_sql() []const u8 {
    return "SELECT id, kind, payload, mtime FROM t_14_11 WHERE id = ?;";
}
pub fn schema_table_14_11_list_sql(limit: u32) []const u8 {
    _ = limit;
    return "SELECT id, kind, payload, mtime FROM t_14_11 ORDER BY mtime DESC LIMIT 100;";
}
pub fn encode_row_14_11(gpa: std.mem.Allocator, row: Row) ![]u8 {
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
pub fn decode_row_id_14_11(json_text: []const u8) ?[]const u8 {
    // lightweight scan for "id":"..." without full JSON parse
    const key = "\"id\":\"";
    const start = std.mem.indexOf(u8, json_text, key) orelse return null;
    const from = start + key.len;
    const end = std.mem.indexOfScalar(u8, json_text[from..], '"') orelse return null;
    return json_text[from .. from + end];
}

pub fn schema_table_14_12_name() []const u8 { return "t_14_12"; }
pub fn schema_table_14_12_create_sql() []const u8 {
    return "CREATE TABLE IF NOT EXISTS t_14_12 (id TEXT PRIMARY KEY, kind TEXT, payload TEXT, mtime INTEGER);";
}
pub fn schema_table_14_12_insert_sql() []const u8 {
    return "INSERT OR REPLACE INTO t_14_12 (id, kind, payload, mtime) VALUES (?, ?, ?, ?);";
}
pub fn schema_table_14_12_select_sql() []const u8 {
    return "SELECT id, kind, payload, mtime FROM t_14_12 WHERE id = ?;";
}
pub fn schema_table_14_12_list_sql(limit: u32) []const u8 {
    _ = limit;
    return "SELECT id, kind, payload, mtime FROM t_14_12 ORDER BY mtime DESC LIMIT 100;";
}
pub fn encode_row_14_12(gpa: std.mem.Allocator, row: Row) ![]u8 {
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
pub fn decode_row_id_14_12(json_text: []const u8) ?[]const u8 {
    // lightweight scan for "id":"..." without full JSON parse
    const key = "\"id\":\"";
    const start = std.mem.indexOf(u8, json_text, key) orelse return null;
    const from = start + key.len;
    const end = std.mem.indexOfScalar(u8, json_text[from..], '"') orelse return null;
    return json_text[from .. from + end];
}

pub fn schema_table_14_13_name() []const u8 { return "t_14_13"; }
pub fn schema_table_14_13_create_sql() []const u8 {
    return "CREATE TABLE IF NOT EXISTS t_14_13 (id TEXT PRIMARY KEY, kind TEXT, payload TEXT, mtime INTEGER);";
}
pub fn schema_table_14_13_insert_sql() []const u8 {
    return "INSERT OR REPLACE INTO t_14_13 (id, kind, payload, mtime) VALUES (?, ?, ?, ?);";
}
pub fn schema_table_14_13_select_sql() []const u8 {
    return "SELECT id, kind, payload, mtime FROM t_14_13 WHERE id = ?;";
}
pub fn schema_table_14_13_list_sql(limit: u32) []const u8 {
    _ = limit;
    return "SELECT id, kind, payload, mtime FROM t_14_13 ORDER BY mtime DESC LIMIT 100;";
}
pub fn encode_row_14_13(gpa: std.mem.Allocator, row: Row) ![]u8 {
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
pub fn decode_row_id_14_13(json_text: []const u8) ?[]const u8 {
    // lightweight scan for "id":"..." without full JSON parse
    const key = "\"id\":\"";
    const start = std.mem.indexOf(u8, json_text, key) orelse return null;
    const from = start + key.len;
    const end = std.mem.indexOfScalar(u8, json_text[from..], '"') orelse return null;
    return json_text[from .. from + end];
}

pub fn schema_table_14_14_name() []const u8 { return "t_14_14"; }
pub fn schema_table_14_14_create_sql() []const u8 {
    return "CREATE TABLE IF NOT EXISTS t_14_14 (id TEXT PRIMARY KEY, kind TEXT, payload TEXT, mtime INTEGER);";
}
pub fn schema_table_14_14_insert_sql() []const u8 {
    return "INSERT OR REPLACE INTO t_14_14 (id, kind, payload, mtime) VALUES (?, ?, ?, ?);";
}
pub fn schema_table_14_14_select_sql() []const u8 {
    return "SELECT id, kind, payload, mtime FROM t_14_14 WHERE id = ?;";
}
pub fn schema_table_14_14_list_sql(limit: u32) []const u8 {
    _ = limit;
    return "SELECT id, kind, payload, mtime FROM t_14_14 ORDER BY mtime DESC LIMIT 100;";
}
pub fn encode_row_14_14(gpa: std.mem.Allocator, row: Row) ![]u8 {
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
pub fn decode_row_id_14_14(json_text: []const u8) ?[]const u8 {
    // lightweight scan for "id":"..." without full JSON parse
    const key = "\"id\":\"";
    const start = std.mem.indexOf(u8, json_text, key) orelse return null;
    const from = start + key.len;
    const end = std.mem.indexOfScalar(u8, json_text[from..], '"') orelse return null;
    return json_text[from .. from + end];
}

pub fn schema_table_14_15_name() []const u8 { return "t_14_15"; }
pub fn schema_table_14_15_create_sql() []const u8 {
    return "CREATE TABLE IF NOT EXISTS t_14_15 (id TEXT PRIMARY KEY, kind TEXT, payload TEXT, mtime INTEGER);";
}
pub fn schema_table_14_15_insert_sql() []const u8 {
    return "INSERT OR REPLACE INTO t_14_15 (id, kind, payload, mtime) VALUES (?, ?, ?, ?);";
}
pub fn schema_table_14_15_select_sql() []const u8 {
    return "SELECT id, kind, payload, mtime FROM t_14_15 WHERE id = ?;";
}
pub fn schema_table_14_15_list_sql(limit: u32) []const u8 {
    _ = limit;
    return "SELECT id, kind, payload, mtime FROM t_14_15 ORDER BY mtime DESC LIMIT 100;";
}
pub fn encode_row_14_15(gpa: std.mem.Allocator, row: Row) ![]u8 {
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
pub fn decode_row_id_14_15(json_text: []const u8) ?[]const u8 {
    // lightweight scan for "id":"..." without full JSON parse
    const key = "\"id\":\"";
    const start = std.mem.indexOf(u8, json_text, key) orelse return null;
    const from = start + key.len;
    const end = std.mem.indexOfScalar(u8, json_text[from..], '"') orelse return null;
    return json_text[from .. from + end];
}

pub fn schema_table_14_16_name() []const u8 { return "t_14_16"; }
pub fn schema_table_14_16_create_sql() []const u8 {
    return "CREATE TABLE IF NOT EXISTS t_14_16 (id TEXT PRIMARY KEY, kind TEXT, payload TEXT, mtime INTEGER);";
}
pub fn schema_table_14_16_insert_sql() []const u8 {
    return "INSERT OR REPLACE INTO t_14_16 (id, kind, payload, mtime) VALUES (?, ?, ?, ?);";
}
pub fn schema_table_14_16_select_sql() []const u8 {
    return "SELECT id, kind, payload, mtime FROM t_14_16 WHERE id = ?;";
}
pub fn schema_table_14_16_list_sql(limit: u32) []const u8 {
    _ = limit;
    return "SELECT id, kind, payload, mtime FROM t_14_16 ORDER BY mtime DESC LIMIT 100;";
}
pub fn encode_row_14_16(gpa: std.mem.Allocator, row: Row) ![]u8 {
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
pub fn decode_row_id_14_16(json_text: []const u8) ?[]const u8 {
    // lightweight scan for "id":"..." without full JSON parse
    const key = "\"id\":\"";
    const start = std.mem.indexOf(u8, json_text, key) orelse return null;
    const from = start + key.len;
    const end = std.mem.indexOfScalar(u8, json_text[from..], '"') orelse return null;
    return json_text[from .. from + end];
}

pub fn schema_table_14_17_name() []const u8 { return "t_14_17"; }
pub fn schema_table_14_17_create_sql() []const u8 {
    return "CREATE TABLE IF NOT EXISTS t_14_17 (id TEXT PRIMARY KEY, kind TEXT, payload TEXT, mtime INTEGER);";
}
pub fn schema_table_14_17_insert_sql() []const u8 {
    return "INSERT OR REPLACE INTO t_14_17 (id, kind, payload, mtime) VALUES (?, ?, ?, ?);";
}
pub fn schema_table_14_17_select_sql() []const u8 {
    return "SELECT id, kind, payload, mtime FROM t_14_17 WHERE id = ?;";
}
pub fn schema_table_14_17_list_sql(limit: u32) []const u8 {
    _ = limit;
    return "SELECT id, kind, payload, mtime FROM t_14_17 ORDER BY mtime DESC LIMIT 100;";
}
pub fn encode_row_14_17(gpa: std.mem.Allocator, row: Row) ![]u8 {
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
pub fn decode_row_id_14_17(json_text: []const u8) ?[]const u8 {
    // lightweight scan for "id":"..." without full JSON parse
    const key = "\"id\":\"";
    const start = std.mem.indexOf(u8, json_text, key) orelse return null;
    const from = start + key.len;
    const end = std.mem.indexOfScalar(u8, json_text[from..], '"') orelse return null;
    return json_text[from .. from + end];
}

pub fn schema_table_14_18_name() []const u8 { return "t_14_18"; }
pub fn schema_table_14_18_create_sql() []const u8 {
    return "CREATE TABLE IF NOT EXISTS t_14_18 (id TEXT PRIMARY KEY, kind TEXT, payload TEXT, mtime INTEGER);";
}
pub fn schema_table_14_18_insert_sql() []const u8 {
    return "INSERT OR REPLACE INTO t_14_18 (id, kind, payload, mtime) VALUES (?, ?, ?, ?);";
}
pub fn schema_table_14_18_select_sql() []const u8 {
    return "SELECT id, kind, payload, mtime FROM t_14_18 WHERE id = ?;";
}
pub fn schema_table_14_18_list_sql(limit: u32) []const u8 {
    _ = limit;
    return "SELECT id, kind, payload, mtime FROM t_14_18 ORDER BY mtime DESC LIMIT 100;";
}
pub fn encode_row_14_18(gpa: std.mem.Allocator, row: Row) ![]u8 {
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
pub fn decode_row_id_14_18(json_text: []const u8) ?[]const u8 {
    // lightweight scan for "id":"..." without full JSON parse
    const key = "\"id\":\"";
    const start = std.mem.indexOf(u8, json_text, key) orelse return null;
    const from = start + key.len;
    const end = std.mem.indexOfScalar(u8, json_text[from..], '"') orelse return null;
    return json_text[from .. from + end];
}

pub fn schema_table_14_19_name() []const u8 { return "t_14_19"; }
pub fn schema_table_14_19_create_sql() []const u8 {
    return "CREATE TABLE IF NOT EXISTS t_14_19 (id TEXT PRIMARY KEY, kind TEXT, payload TEXT, mtime INTEGER);";
}
pub fn schema_table_14_19_insert_sql() []const u8 {
    return "INSERT OR REPLACE INTO t_14_19 (id, kind, payload, mtime) VALUES (?, ?, ?, ?);";
}
pub fn schema_table_14_19_select_sql() []const u8 {
    return "SELECT id, kind, payload, mtime FROM t_14_19 WHERE id = ?;";
}
pub fn schema_table_14_19_list_sql(limit: u32) []const u8 {
    _ = limit;
    return "SELECT id, kind, payload, mtime FROM t_14_19 ORDER BY mtime DESC LIMIT 100;";
}
pub fn encode_row_14_19(gpa: std.mem.Allocator, row: Row) ![]u8 {
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
pub fn decode_row_id_14_19(json_text: []const u8) ?[]const u8 {
    // lightweight scan for "id":"..." without full JSON parse
    const key = "\"id\":\"";
    const start = std.mem.indexOf(u8, json_text, key) orelse return null;
    const from = start + key.len;
    const end = std.mem.indexOfScalar(u8, json_text[from..], '"') orelse return null;
    return json_text[from .. from + end];
}

pub fn schema_table_14_20_name() []const u8 { return "t_14_20"; }
pub fn schema_table_14_20_create_sql() []const u8 {
    return "CREATE TABLE IF NOT EXISTS t_14_20 (id TEXT PRIMARY KEY, kind TEXT, payload TEXT, mtime INTEGER);";
}
pub fn schema_table_14_20_insert_sql() []const u8 {
    return "INSERT OR REPLACE INTO t_14_20 (id, kind, payload, mtime) VALUES (?, ?, ?, ?);";
}
pub fn schema_table_14_20_select_sql() []const u8 {
    return "SELECT id, kind, payload, mtime FROM t_14_20 WHERE id = ?;";
}
pub fn schema_table_14_20_list_sql(limit: u32) []const u8 {
    _ = limit;
    return "SELECT id, kind, payload, mtime FROM t_14_20 ORDER BY mtime DESC LIMIT 100;";
}
pub fn encode_row_14_20(gpa: std.mem.Allocator, row: Row) ![]u8 {
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
pub fn decode_row_id_14_20(json_text: []const u8) ?[]const u8 {
    // lightweight scan for "id":"..." without full JSON parse
    const key = "\"id\":\"";
    const start = std.mem.indexOf(u8, json_text, key) orelse return null;
    const from = start + key.len;
    const end = std.mem.indexOfScalar(u8, json_text[from..], '"') orelse return null;
    return json_text[from .. from + end];
}

pub fn schema_table_14_21_name() []const u8 { return "t_14_21"; }
pub fn schema_table_14_21_create_sql() []const u8 {
    return "CREATE TABLE IF NOT EXISTS t_14_21 (id TEXT PRIMARY KEY, kind TEXT, payload TEXT, mtime INTEGER);";
}
pub fn schema_table_14_21_insert_sql() []const u8 {
    return "INSERT OR REPLACE INTO t_14_21 (id, kind, payload, mtime) VALUES (?, ?, ?, ?);";
}
pub fn schema_table_14_21_select_sql() []const u8 {
    return "SELECT id, kind, payload, mtime FROM t_14_21 WHERE id = ?;";
}
pub fn schema_table_14_21_list_sql(limit: u32) []const u8 {
    _ = limit;
    return "SELECT id, kind, payload, mtime FROM t_14_21 ORDER BY mtime DESC LIMIT 100;";
}
pub fn encode_row_14_21(gpa: std.mem.Allocator, row: Row) ![]u8 {
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
pub fn decode_row_id_14_21(json_text: []const u8) ?[]const u8 {
    // lightweight scan for "id":"..." without full JSON parse
    const key = "\"id\":\"";
    const start = std.mem.indexOf(u8, json_text, key) orelse return null;
    const from = start + key.len;
    const end = std.mem.indexOfScalar(u8, json_text[from..], '"') orelse return null;
    return json_text[from .. from + end];
}

pub fn schema_table_14_22_name() []const u8 { return "t_14_22"; }
pub fn schema_table_14_22_create_sql() []const u8 {
    return "CREATE TABLE IF NOT EXISTS t_14_22 (id TEXT PRIMARY KEY, kind TEXT, payload TEXT, mtime INTEGER);";
}
pub fn schema_table_14_22_insert_sql() []const u8 {
    return "INSERT OR REPLACE INTO t_14_22 (id, kind, payload, mtime) VALUES (?, ?, ?, ?);";
}
pub fn schema_table_14_22_select_sql() []const u8 {
    return "SELECT id, kind, payload, mtime FROM t_14_22 WHERE id = ?;";
}
pub fn schema_table_14_22_list_sql(limit: u32) []const u8 {
    _ = limit;
    return "SELECT id, kind, payload, mtime FROM t_14_22 ORDER BY mtime DESC LIMIT 100;";
}
pub fn encode_row_14_22(gpa: std.mem.Allocator, row: Row) ![]u8 {
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
pub fn decode_row_id_14_22(json_text: []const u8) ?[]const u8 {
    // lightweight scan for "id":"..." without full JSON parse
    const key = "\"id\":\"";
    const start = std.mem.indexOf(u8, json_text, key) orelse return null;
    const from = start + key.len;
    const end = std.mem.indexOfScalar(u8, json_text[from..], '"') orelse return null;
    return json_text[from .. from + end];
}

pub fn schema_table_14_23_name() []const u8 { return "t_14_23"; }
pub fn schema_table_14_23_create_sql() []const u8 {
    return "CREATE TABLE IF NOT EXISTS t_14_23 (id TEXT PRIMARY KEY, kind TEXT, payload TEXT, mtime INTEGER);";
}
pub fn schema_table_14_23_insert_sql() []const u8 {
    return "INSERT OR REPLACE INTO t_14_23 (id, kind, payload, mtime) VALUES (?, ?, ?, ?);";
}
pub fn schema_table_14_23_select_sql() []const u8 {
    return "SELECT id, kind, payload, mtime FROM t_14_23 WHERE id = ?;";
}
pub fn schema_table_14_23_list_sql(limit: u32) []const u8 {
    _ = limit;
    return "SELECT id, kind, payload, mtime FROM t_14_23 ORDER BY mtime DESC LIMIT 100;";
}
pub fn encode_row_14_23(gpa: std.mem.Allocator, row: Row) ![]u8 {
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
pub fn decode_row_id_14_23(json_text: []const u8) ?[]const u8 {
    // lightweight scan for "id":"..." without full JSON parse
    const key = "\"id\":\"";
    const start = std.mem.indexOf(u8, json_text, key) orelse return null;
    const from = start + key.len;
    const end = std.mem.indexOfScalar(u8, json_text[from..], '"') orelse return null;
    return json_text[from .. from + end];
}

pub fn schema_table_14_24_name() []const u8 { return "t_14_24"; }
pub fn schema_table_14_24_create_sql() []const u8 {
    return "CREATE TABLE IF NOT EXISTS t_14_24 (id TEXT PRIMARY KEY, kind TEXT, payload TEXT, mtime INTEGER);";
}
pub fn schema_table_14_24_insert_sql() []const u8 {
    return "INSERT OR REPLACE INTO t_14_24 (id, kind, payload, mtime) VALUES (?, ?, ?, ?);";
}
pub fn schema_table_14_24_select_sql() []const u8 {
    return "SELECT id, kind, payload, mtime FROM t_14_24 WHERE id = ?;";
}
pub fn schema_table_14_24_list_sql(limit: u32) []const u8 {
    _ = limit;
    return "SELECT id, kind, payload, mtime FROM t_14_24 ORDER BY mtime DESC LIMIT 100;";
}
pub fn encode_row_14_24(gpa: std.mem.Allocator, row: Row) ![]u8 {
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
pub fn decode_row_id_14_24(json_text: []const u8) ?[]const u8 {
    // lightweight scan for "id":"..." without full JSON parse
    const key = "\"id\":\"";
    const start = std.mem.indexOf(u8, json_text, key) orelse return null;
    const from = start + key.len;
    const end = std.mem.indexOfScalar(u8, json_text[from..], '"') orelse return null;
    return json_text[from .. from + end];
}

pub fn schema_table_14_25_name() []const u8 { return "t_14_25"; }
pub fn schema_table_14_25_create_sql() []const u8 {
    return "CREATE TABLE IF NOT EXISTS t_14_25 (id TEXT PRIMARY KEY, kind TEXT, payload TEXT, mtime INTEGER);";
}
pub fn schema_table_14_25_insert_sql() []const u8 {
    return "INSERT OR REPLACE INTO t_14_25 (id, kind, payload, mtime) VALUES (?, ?, ?, ?);";
}
pub fn schema_table_14_25_select_sql() []const u8 {
    return "SELECT id, kind, payload, mtime FROM t_14_25 WHERE id = ?;";
}
pub fn schema_table_14_25_list_sql(limit: u32) []const u8 {
    _ = limit;
    return "SELECT id, kind, payload, mtime FROM t_14_25 ORDER BY mtime DESC LIMIT 100;";
}
pub fn encode_row_14_25(gpa: std.mem.Allocator, row: Row) ![]u8 {
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
pub fn decode_row_id_14_25(json_text: []const u8) ?[]const u8 {
    // lightweight scan for "id":"..." without full JSON parse
    const key = "\"id\":\"";
    const start = std.mem.indexOf(u8, json_text, key) orelse return null;
    const from = start + key.len;
    const end = std.mem.indexOfScalar(u8, json_text[from..], '"') orelse return null;
    return json_text[from .. from + end];
}

pub fn schema_table_14_26_name() []const u8 { return "t_14_26"; }
pub fn schema_table_14_26_create_sql() []const u8 {
    return "CREATE TABLE IF NOT EXISTS t_14_26 (id TEXT PRIMARY KEY, kind TEXT, payload TEXT, mtime INTEGER);";
}
pub fn schema_table_14_26_insert_sql() []const u8 {
    return "INSERT OR REPLACE INTO t_14_26 (id, kind, payload, mtime) VALUES (?, ?, ?, ?);";
}
pub fn schema_table_14_26_select_sql() []const u8 {
    return "SELECT id, kind, payload, mtime FROM t_14_26 WHERE id = ?;";
}
pub fn schema_table_14_26_list_sql(limit: u32) []const u8 {
    _ = limit;
    return "SELECT id, kind, payload, mtime FROM t_14_26 ORDER BY mtime DESC LIMIT 100;";
}
pub fn encode_row_14_26(gpa: std.mem.Allocator, row: Row) ![]u8 {
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
pub fn decode_row_id_14_26(json_text: []const u8) ?[]const u8 {
    // lightweight scan for "id":"..." without full JSON parse
    const key = "\"id\":\"";
    const start = std.mem.indexOf(u8, json_text, key) orelse return null;
    const from = start + key.len;
    const end = std.mem.indexOfScalar(u8, json_text[from..], '"') orelse return null;
    return json_text[from .. from + end];
}

pub fn schema_table_14_27_name() []const u8 { return "t_14_27"; }
pub fn schema_table_14_27_create_sql() []const u8 {
    return "CREATE TABLE IF NOT EXISTS t_14_27 (id TEXT PRIMARY KEY, kind TEXT, payload TEXT, mtime INTEGER);";
}
pub fn schema_table_14_27_insert_sql() []const u8 {
    return "INSERT OR REPLACE INTO t_14_27 (id, kind, payload, mtime) VALUES (?, ?, ?, ?);";
}
pub fn schema_table_14_27_select_sql() []const u8 {
    return "SELECT id, kind, payload, mtime FROM t_14_27 WHERE id = ?;";
}
pub fn schema_table_14_27_list_sql(limit: u32) []const u8 {
    _ = limit;
    return "SELECT id, kind, payload, mtime FROM t_14_27 ORDER BY mtime DESC LIMIT 100;";
}
pub fn encode_row_14_27(gpa: std.mem.Allocator, row: Row) ![]u8 {
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
pub fn decode_row_id_14_27(json_text: []const u8) ?[]const u8 {
    // lightweight scan for "id":"..." without full JSON parse
    const key = "\"id\":\"";
    const start = std.mem.indexOf(u8, json_text, key) orelse return null;
    const from = start + key.len;
    const end = std.mem.indexOfScalar(u8, json_text[from..], '"') orelse return null;
    return json_text[from .. from + end];
}

pub fn schema_table_14_28_name() []const u8 { return "t_14_28"; }
pub fn schema_table_14_28_create_sql() []const u8 {
    return "CREATE TABLE IF NOT EXISTS t_14_28 (id TEXT PRIMARY KEY, kind TEXT, payload TEXT, mtime INTEGER);";
}
pub fn schema_table_14_28_insert_sql() []const u8 {
    return "INSERT OR REPLACE INTO t_14_28 (id, kind, payload, mtime) VALUES (?, ?, ?, ?);";
}
pub fn schema_table_14_28_select_sql() []const u8 {
    return "SELECT id, kind, payload, mtime FROM t_14_28 WHERE id = ?;";
}
pub fn schema_table_14_28_list_sql(limit: u32) []const u8 {
    _ = limit;
    return "SELECT id, kind, payload, mtime FROM t_14_28 ORDER BY mtime DESC LIMIT 100;";
}
pub fn encode_row_14_28(gpa: std.mem.Allocator, row: Row) ![]u8 {
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
pub fn decode_row_id_14_28(json_text: []const u8) ?[]const u8 {
    // lightweight scan for "id":"..." without full JSON parse
    const key = "\"id\":\"";
    const start = std.mem.indexOf(u8, json_text, key) orelse return null;
    const from = start + key.len;
    const end = std.mem.indexOfScalar(u8, json_text[from..], '"') orelse return null;
    return json_text[from .. from + end];
}

pub fn schema_table_14_29_name() []const u8 { return "t_14_29"; }
pub fn schema_table_14_29_create_sql() []const u8 {
    return "CREATE TABLE IF NOT EXISTS t_14_29 (id TEXT PRIMARY KEY, kind TEXT, payload TEXT, mtime INTEGER);";
}
pub fn schema_table_14_29_insert_sql() []const u8 {
    return "INSERT OR REPLACE INTO t_14_29 (id, kind, payload, mtime) VALUES (?, ?, ?, ?);";
}
pub fn schema_table_14_29_select_sql() []const u8 {
    return "SELECT id, kind, payload, mtime FROM t_14_29 WHERE id = ?;";
}
pub fn schema_table_14_29_list_sql(limit: u32) []const u8 {
    _ = limit;
    return "SELECT id, kind, payload, mtime FROM t_14_29 ORDER BY mtime DESC LIMIT 100;";
}
pub fn encode_row_14_29(gpa: std.mem.Allocator, row: Row) ![]u8 {
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
pub fn decode_row_id_14_29(json_text: []const u8) ?[]const u8 {
    // lightweight scan for "id":"..." without full JSON parse
    const key = "\"id\":\"";
    const start = std.mem.indexOf(u8, json_text, key) orelse return null;
    const from = start + key.len;
    const end = std.mem.indexOfScalar(u8, json_text[from..], '"') orelse return null;
    return json_text[from .. from + end];
}

pub fn schema_table_14_30_name() []const u8 { return "t_14_30"; }
pub fn schema_table_14_30_create_sql() []const u8 {
    return "CREATE TABLE IF NOT EXISTS t_14_30 (id TEXT PRIMARY KEY, kind TEXT, payload TEXT, mtime INTEGER);";
}
pub fn schema_table_14_30_insert_sql() []const u8 {
    return "INSERT OR REPLACE INTO t_14_30 (id, kind, payload, mtime) VALUES (?, ?, ?, ?);";
}
pub fn schema_table_14_30_select_sql() []const u8 {
    return "SELECT id, kind, payload, mtime FROM t_14_30 WHERE id = ?;";
}
pub fn schema_table_14_30_list_sql(limit: u32) []const u8 {
    _ = limit;
    return "SELECT id, kind, payload, mtime FROM t_14_30 ORDER BY mtime DESC LIMIT 100;";
}
pub fn encode_row_14_30(gpa: std.mem.Allocator, row: Row) ![]u8 {
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
pub fn decode_row_id_14_30(json_text: []const u8) ?[]const u8 {
    // lightweight scan for "id":"..." without full JSON parse
    const key = "\"id\":\"";
    const start = std.mem.indexOf(u8, json_text, key) orelse return null;
    const from = start + key.len;
    const end = std.mem.indexOfScalar(u8, json_text[from..], '"') orelse return null;
    return json_text[from .. from + end];
}

pub fn schema_table_14_31_name() []const u8 { return "t_14_31"; }
pub fn schema_table_14_31_create_sql() []const u8 {
    return "CREATE TABLE IF NOT EXISTS t_14_31 (id TEXT PRIMARY KEY, kind TEXT, payload TEXT, mtime INTEGER);";
}
pub fn schema_table_14_31_insert_sql() []const u8 {
    return "INSERT OR REPLACE INTO t_14_31 (id, kind, payload, mtime) VALUES (?, ?, ?, ?);";
}
pub fn schema_table_14_31_select_sql() []const u8 {
    return "SELECT id, kind, payload, mtime FROM t_14_31 WHERE id = ?;";
}
pub fn schema_table_14_31_list_sql(limit: u32) []const u8 {
    _ = limit;
    return "SELECT id, kind, payload, mtime FROM t_14_31 ORDER BY mtime DESC LIMIT 100;";
}
pub fn encode_row_14_31(gpa: std.mem.Allocator, row: Row) ![]u8 {
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
pub fn decode_row_id_14_31(json_text: []const u8) ?[]const u8 {
    // lightweight scan for "id":"..." without full JSON parse
    const key = "\"id\":\"";
    const start = std.mem.indexOf(u8, json_text, key) orelse return null;
    const from = start + key.len;
    const end = std.mem.indexOfScalar(u8, json_text[from..], '"') orelse return null;
    return json_text[from .. from + end];
}

pub fn schema_table_14_32_name() []const u8 { return "t_14_32"; }
pub fn schema_table_14_32_create_sql() []const u8 {
    return "CREATE TABLE IF NOT EXISTS t_14_32 (id TEXT PRIMARY KEY, kind TEXT, payload TEXT, mtime INTEGER);";
}
pub fn schema_table_14_32_insert_sql() []const u8 {
    return "INSERT OR REPLACE INTO t_14_32 (id, kind, payload, mtime) VALUES (?, ?, ?, ?);";
}
pub fn schema_table_14_32_select_sql() []const u8 {
    return "SELECT id, kind, payload, mtime FROM t_14_32 WHERE id = ?;";
}
pub fn schema_table_14_32_list_sql(limit: u32) []const u8 {
    _ = limit;
    return "SELECT id, kind, payload, mtime FROM t_14_32 ORDER BY mtime DESC LIMIT 100;";
}
pub fn encode_row_14_32(gpa: std.mem.Allocator, row: Row) ![]u8 {
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
pub fn decode_row_id_14_32(json_text: []const u8) ?[]const u8 {
    // lightweight scan for "id":"..." without full JSON parse
    const key = "\"id\":\"";
    const start = std.mem.indexOf(u8, json_text, key) orelse return null;
    const from = start + key.len;
    const end = std.mem.indexOfScalar(u8, json_text[from..], '"') orelse return null;
    return json_text[from .. from + end];
}

pub fn schema_table_14_33_name() []const u8 { return "t_14_33"; }
pub fn schema_table_14_33_create_sql() []const u8 {
    return "CREATE TABLE IF NOT EXISTS t_14_33 (id TEXT PRIMARY KEY, kind TEXT, payload TEXT, mtime INTEGER);";
}
pub fn schema_table_14_33_insert_sql() []const u8 {
    return "INSERT OR REPLACE INTO t_14_33 (id, kind, payload, mtime) VALUES (?, ?, ?, ?);";
}
pub fn schema_table_14_33_select_sql() []const u8 {
    return "SELECT id, kind, payload, mtime FROM t_14_33 WHERE id = ?;";
}
pub fn schema_table_14_33_list_sql(limit: u32) []const u8 {
    _ = limit;
    return "SELECT id, kind, payload, mtime FROM t_14_33 ORDER BY mtime DESC LIMIT 100;";
}
pub fn encode_row_14_33(gpa: std.mem.Allocator, row: Row) ![]u8 {
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
pub fn decode_row_id_14_33(json_text: []const u8) ?[]const u8 {
    // lightweight scan for "id":"..." without full JSON parse
    const key = "\"id\":\"";
    const start = std.mem.indexOf(u8, json_text, key) orelse return null;
    const from = start + key.len;
    const end = std.mem.indexOfScalar(u8, json_text[from..], '"') orelse return null;
    return json_text[from .. from + end];
}

pub fn schema_table_14_34_name() []const u8 { return "t_14_34"; }
pub fn schema_table_14_34_create_sql() []const u8 {
    return "CREATE TABLE IF NOT EXISTS t_14_34 (id TEXT PRIMARY KEY, kind TEXT, payload TEXT, mtime INTEGER);";
}
pub fn schema_table_14_34_insert_sql() []const u8 {
    return "INSERT OR REPLACE INTO t_14_34 (id, kind, payload, mtime) VALUES (?, ?, ?, ?);";
}
pub fn schema_table_14_34_select_sql() []const u8 {
    return "SELECT id, kind, payload, mtime FROM t_14_34 WHERE id = ?;";
}
pub fn schema_table_14_34_list_sql(limit: u32) []const u8 {
    _ = limit;
    return "SELECT id, kind, payload, mtime FROM t_14_34 ORDER BY mtime DESC LIMIT 100;";
}
pub fn encode_row_14_34(gpa: std.mem.Allocator, row: Row) ![]u8 {
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
pub fn decode_row_id_14_34(json_text: []const u8) ?[]const u8 {
    // lightweight scan for "id":"..." without full JSON parse
    const key = "\"id\":\"";
    const start = std.mem.indexOf(u8, json_text, key) orelse return null;
    const from = start + key.len;
    const end = std.mem.indexOfScalar(u8, json_text[from..], '"') orelse return null;
    return json_text[from .. from + end];
}

pub fn schema_table_14_35_name() []const u8 { return "t_14_35"; }
pub fn schema_table_14_35_create_sql() []const u8 {
    return "CREATE TABLE IF NOT EXISTS t_14_35 (id TEXT PRIMARY KEY, kind TEXT, payload TEXT, mtime INTEGER);";
}
pub fn schema_table_14_35_insert_sql() []const u8 {
    return "INSERT OR REPLACE INTO t_14_35 (id, kind, payload, mtime) VALUES (?, ?, ?, ?);";
}
pub fn schema_table_14_35_select_sql() []const u8 {
    return "SELECT id, kind, payload, mtime FROM t_14_35 WHERE id = ?;";
}
pub fn schema_table_14_35_list_sql(limit: u32) []const u8 {
    _ = limit;
    return "SELECT id, kind, payload, mtime FROM t_14_35 ORDER BY mtime DESC LIMIT 100;";
}
pub fn encode_row_14_35(gpa: std.mem.Allocator, row: Row) ![]u8 {
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
pub fn decode_row_id_14_35(json_text: []const u8) ?[]const u8 {
    // lightweight scan for "id":"..." without full JSON parse
    const key = "\"id\":\"";
    const start = std.mem.indexOf(u8, json_text, key) orelse return null;
    const from = start + key.len;
    const end = std.mem.indexOfScalar(u8, json_text[from..], '"') orelse return null;
    return json_text[from .. from + end];
}

pub fn schema_table_14_36_name() []const u8 { return "t_14_36"; }
pub fn schema_table_14_36_create_sql() []const u8 {
    return "CREATE TABLE IF NOT EXISTS t_14_36 (id TEXT PRIMARY KEY, kind TEXT, payload TEXT, mtime INTEGER);";
}
pub fn schema_table_14_36_insert_sql() []const u8 {
    return "INSERT OR REPLACE INTO t_14_36 (id, kind, payload, mtime) VALUES (?, ?, ?, ?);";
}
pub fn schema_table_14_36_select_sql() []const u8 {
    return "SELECT id, kind, payload, mtime FROM t_14_36 WHERE id = ?;";
}
pub fn schema_table_14_36_list_sql(limit: u32) []const u8 {
    _ = limit;
    return "SELECT id, kind, payload, mtime FROM t_14_36 ORDER BY mtime DESC LIMIT 100;";
}
pub fn encode_row_14_36(gpa: std.mem.Allocator, row: Row) ![]u8 {
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
pub fn decode_row_id_14_36(json_text: []const u8) ?[]const u8 {
    // lightweight scan for "id":"..." without full JSON parse
    const key = "\"id\":\"";
    const start = std.mem.indexOf(u8, json_text, key) orelse return null;
    const from = start + key.len;
    const end = std.mem.indexOfScalar(u8, json_text[from..], '"') orelse return null;
    return json_text[from .. from + end];
}

pub fn schema_table_14_37_name() []const u8 { return "t_14_37"; }
pub fn schema_table_14_37_create_sql() []const u8 {
    return "CREATE TABLE IF NOT EXISTS t_14_37 (id TEXT PRIMARY KEY, kind TEXT, payload TEXT, mtime INTEGER);";
}
pub fn schema_table_14_37_insert_sql() []const u8 {
    return "INSERT OR REPLACE INTO t_14_37 (id, kind, payload, mtime) VALUES (?, ?, ?, ?);";
}
pub fn schema_table_14_37_select_sql() []const u8 {
    return "SELECT id, kind, payload, mtime FROM t_14_37 WHERE id = ?;";
}
pub fn schema_table_14_37_list_sql(limit: u32) []const u8 {
    _ = limit;
    return "SELECT id, kind, payload, mtime FROM t_14_37 ORDER BY mtime DESC LIMIT 100;";
}
pub fn encode_row_14_37(gpa: std.mem.Allocator, row: Row) ![]u8 {
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
pub fn decode_row_id_14_37(json_text: []const u8) ?[]const u8 {
    // lightweight scan for "id":"..." without full JSON parse
    const key = "\"id\":\"";
    const start = std.mem.indexOf(u8, json_text, key) orelse return null;
    const from = start + key.len;
    const end = std.mem.indexOfScalar(u8, json_text[from..], '"') orelse return null;
    return json_text[from .. from + end];
}

pub fn schema_table_14_38_name() []const u8 { return "t_14_38"; }
pub fn schema_table_14_38_create_sql() []const u8 {
    return "CREATE TABLE IF NOT EXISTS t_14_38 (id TEXT PRIMARY KEY, kind TEXT, payload TEXT, mtime INTEGER);";
}
pub fn schema_table_14_38_insert_sql() []const u8 {
    return "INSERT OR REPLACE INTO t_14_38 (id, kind, payload, mtime) VALUES (?, ?, ?, ?);";
}
pub fn schema_table_14_38_select_sql() []const u8 {
    return "SELECT id, kind, payload, mtime FROM t_14_38 WHERE id = ?;";
}
pub fn schema_table_14_38_list_sql(limit: u32) []const u8 {
    _ = limit;
    return "SELECT id, kind, payload, mtime FROM t_14_38 ORDER BY mtime DESC LIMIT 100;";
}
pub fn encode_row_14_38(gpa: std.mem.Allocator, row: Row) ![]u8 {
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
pub fn decode_row_id_14_38(json_text: []const u8) ?[]const u8 {
    // lightweight scan for "id":"..." without full JSON parse
    const key = "\"id\":\"";
    const start = std.mem.indexOf(u8, json_text, key) orelse return null;
    const from = start + key.len;
    const end = std.mem.indexOfScalar(u8, json_text[from..], '"') orelse return null;
    return json_text[from .. from + end];
}

pub fn schema_table_14_39_name() []const u8 { return "t_14_39"; }
pub fn schema_table_14_39_create_sql() []const u8 {
    return "CREATE TABLE IF NOT EXISTS t_14_39 (id TEXT PRIMARY KEY, kind TEXT, payload TEXT, mtime INTEGER);";
}
pub fn schema_table_14_39_insert_sql() []const u8 {
    return "INSERT OR REPLACE INTO t_14_39 (id, kind, payload, mtime) VALUES (?, ?, ?, ?);";
}
pub fn schema_table_14_39_select_sql() []const u8 {
    return "SELECT id, kind, payload, mtime FROM t_14_39 WHERE id = ?;";
}
pub fn schema_table_14_39_list_sql(limit: u32) []const u8 {
    _ = limit;
    return "SELECT id, kind, payload, mtime FROM t_14_39 ORDER BY mtime DESC LIMIT 100;";
}
pub fn encode_row_14_39(gpa: std.mem.Allocator, row: Row) ![]u8 {
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
pub fn decode_row_id_14_39(json_text: []const u8) ?[]const u8 {
    // lightweight scan for "id":"..." without full JSON parse
    const key = "\"id\":\"";
    const start = std.mem.indexOf(u8, json_text, key) orelse return null;
    const from = start + key.len;
    const end = std.mem.indexOfScalar(u8, json_text[from..], '"') orelse return null;
    return json_text[from .. from + end];
}

test "storage shard 14" {
    try std.testing.expectEqualStrings("t_14_0", schema_table_14_0_name());
    const gpa = std.testing.allocator;
    const enc = try encode_row_14_0(gpa, .{ .id = "a", .kind = "k", .payload = "p", .mtime = 1 });
    defer gpa.free(enc);
    try std.testing.expectEqualStrings("a", decode_row_id_14_0(enc).?);
}

