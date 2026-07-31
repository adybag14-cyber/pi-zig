//! Generated storage schema/query helpers shard 6.
const std = @import("std");

pub const Row = struct {
    id: []const u8,
    kind: []const u8,
    payload: []const u8,
    mtime: i64,
};

pub fn schema_table_6_0_name() []const u8 { return "t_6_0"; }
pub fn schema_table_6_0_create_sql() []const u8 {
    return "CREATE TABLE IF NOT EXISTS t_6_0 (id TEXT PRIMARY KEY, kind TEXT, payload TEXT, mtime INTEGER);";
}
pub fn schema_table_6_0_insert_sql() []const u8 {
    return "INSERT OR REPLACE INTO t_6_0 (id, kind, payload, mtime) VALUES (?, ?, ?, ?);";
}
pub fn schema_table_6_0_select_sql() []const u8 {
    return "SELECT id, kind, payload, mtime FROM t_6_0 WHERE id = ?;";
}
pub fn schema_table_6_0_list_sql(limit: u32) []const u8 {
    _ = limit;
    return "SELECT id, kind, payload, mtime FROM t_6_0 ORDER BY mtime DESC LIMIT 100;";
}
pub fn encode_row_6_0(gpa: std.mem.Allocator, row: Row) ![]u8 {
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
pub fn decode_row_id_6_0(json_text: []const u8) ?[]const u8 {
    // lightweight scan for "id":"..." without full JSON parse
    const key = "\"id\":\"";
    const start = std.mem.indexOf(u8, json_text, key) orelse return null;
    const from = start + key.len;
    const end = std.mem.indexOfScalar(u8, json_text[from..], '"') orelse return null;
    return json_text[from .. from + end];
}

pub fn schema_table_6_1_name() []const u8 { return "t_6_1"; }
pub fn schema_table_6_1_create_sql() []const u8 {
    return "CREATE TABLE IF NOT EXISTS t_6_1 (id TEXT PRIMARY KEY, kind TEXT, payload TEXT, mtime INTEGER);";
}
pub fn schema_table_6_1_insert_sql() []const u8 {
    return "INSERT OR REPLACE INTO t_6_1 (id, kind, payload, mtime) VALUES (?, ?, ?, ?);";
}
pub fn schema_table_6_1_select_sql() []const u8 {
    return "SELECT id, kind, payload, mtime FROM t_6_1 WHERE id = ?;";
}
pub fn schema_table_6_1_list_sql(limit: u32) []const u8 {
    _ = limit;
    return "SELECT id, kind, payload, mtime FROM t_6_1 ORDER BY mtime DESC LIMIT 100;";
}
pub fn encode_row_6_1(gpa: std.mem.Allocator, row: Row) ![]u8 {
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
pub fn decode_row_id_6_1(json_text: []const u8) ?[]const u8 {
    // lightweight scan for "id":"..." without full JSON parse
    const key = "\"id\":\"";
    const start = std.mem.indexOf(u8, json_text, key) orelse return null;
    const from = start + key.len;
    const end = std.mem.indexOfScalar(u8, json_text[from..], '"') orelse return null;
    return json_text[from .. from + end];
}

pub fn schema_table_6_2_name() []const u8 { return "t_6_2"; }
pub fn schema_table_6_2_create_sql() []const u8 {
    return "CREATE TABLE IF NOT EXISTS t_6_2 (id TEXT PRIMARY KEY, kind TEXT, payload TEXT, mtime INTEGER);";
}
pub fn schema_table_6_2_insert_sql() []const u8 {
    return "INSERT OR REPLACE INTO t_6_2 (id, kind, payload, mtime) VALUES (?, ?, ?, ?);";
}
pub fn schema_table_6_2_select_sql() []const u8 {
    return "SELECT id, kind, payload, mtime FROM t_6_2 WHERE id = ?;";
}
pub fn schema_table_6_2_list_sql(limit: u32) []const u8 {
    _ = limit;
    return "SELECT id, kind, payload, mtime FROM t_6_2 ORDER BY mtime DESC LIMIT 100;";
}
pub fn encode_row_6_2(gpa: std.mem.Allocator, row: Row) ![]u8 {
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
pub fn decode_row_id_6_2(json_text: []const u8) ?[]const u8 {
    // lightweight scan for "id":"..." without full JSON parse
    const key = "\"id\":\"";
    const start = std.mem.indexOf(u8, json_text, key) orelse return null;
    const from = start + key.len;
    const end = std.mem.indexOfScalar(u8, json_text[from..], '"') orelse return null;
    return json_text[from .. from + end];
}

pub fn schema_table_6_3_name() []const u8 { return "t_6_3"; }
pub fn schema_table_6_3_create_sql() []const u8 {
    return "CREATE TABLE IF NOT EXISTS t_6_3 (id TEXT PRIMARY KEY, kind TEXT, payload TEXT, mtime INTEGER);";
}
pub fn schema_table_6_3_insert_sql() []const u8 {
    return "INSERT OR REPLACE INTO t_6_3 (id, kind, payload, mtime) VALUES (?, ?, ?, ?);";
}
pub fn schema_table_6_3_select_sql() []const u8 {
    return "SELECT id, kind, payload, mtime FROM t_6_3 WHERE id = ?;";
}
pub fn schema_table_6_3_list_sql(limit: u32) []const u8 {
    _ = limit;
    return "SELECT id, kind, payload, mtime FROM t_6_3 ORDER BY mtime DESC LIMIT 100;";
}
pub fn encode_row_6_3(gpa: std.mem.Allocator, row: Row) ![]u8 {
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
pub fn decode_row_id_6_3(json_text: []const u8) ?[]const u8 {
    // lightweight scan for "id":"..." without full JSON parse
    const key = "\"id\":\"";
    const start = std.mem.indexOf(u8, json_text, key) orelse return null;
    const from = start + key.len;
    const end = std.mem.indexOfScalar(u8, json_text[from..], '"') orelse return null;
    return json_text[from .. from + end];
}

pub fn schema_table_6_4_name() []const u8 { return "t_6_4"; }
pub fn schema_table_6_4_create_sql() []const u8 {
    return "CREATE TABLE IF NOT EXISTS t_6_4 (id TEXT PRIMARY KEY, kind TEXT, payload TEXT, mtime INTEGER);";
}
pub fn schema_table_6_4_insert_sql() []const u8 {
    return "INSERT OR REPLACE INTO t_6_4 (id, kind, payload, mtime) VALUES (?, ?, ?, ?);";
}
pub fn schema_table_6_4_select_sql() []const u8 {
    return "SELECT id, kind, payload, mtime FROM t_6_4 WHERE id = ?;";
}
pub fn schema_table_6_4_list_sql(limit: u32) []const u8 {
    _ = limit;
    return "SELECT id, kind, payload, mtime FROM t_6_4 ORDER BY mtime DESC LIMIT 100;";
}
pub fn encode_row_6_4(gpa: std.mem.Allocator, row: Row) ![]u8 {
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
pub fn decode_row_id_6_4(json_text: []const u8) ?[]const u8 {
    // lightweight scan for "id":"..." without full JSON parse
    const key = "\"id\":\"";
    const start = std.mem.indexOf(u8, json_text, key) orelse return null;
    const from = start + key.len;
    const end = std.mem.indexOfScalar(u8, json_text[from..], '"') orelse return null;
    return json_text[from .. from + end];
}

pub fn schema_table_6_5_name() []const u8 { return "t_6_5"; }
pub fn schema_table_6_5_create_sql() []const u8 {
    return "CREATE TABLE IF NOT EXISTS t_6_5 (id TEXT PRIMARY KEY, kind TEXT, payload TEXT, mtime INTEGER);";
}
pub fn schema_table_6_5_insert_sql() []const u8 {
    return "INSERT OR REPLACE INTO t_6_5 (id, kind, payload, mtime) VALUES (?, ?, ?, ?);";
}
pub fn schema_table_6_5_select_sql() []const u8 {
    return "SELECT id, kind, payload, mtime FROM t_6_5 WHERE id = ?;";
}
pub fn schema_table_6_5_list_sql(limit: u32) []const u8 {
    _ = limit;
    return "SELECT id, kind, payload, mtime FROM t_6_5 ORDER BY mtime DESC LIMIT 100;";
}
pub fn encode_row_6_5(gpa: std.mem.Allocator, row: Row) ![]u8 {
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
pub fn decode_row_id_6_5(json_text: []const u8) ?[]const u8 {
    // lightweight scan for "id":"..." without full JSON parse
    const key = "\"id\":\"";
    const start = std.mem.indexOf(u8, json_text, key) orelse return null;
    const from = start + key.len;
    const end = std.mem.indexOfScalar(u8, json_text[from..], '"') orelse return null;
    return json_text[from .. from + end];
}

pub fn schema_table_6_6_name() []const u8 { return "t_6_6"; }
pub fn schema_table_6_6_create_sql() []const u8 {
    return "CREATE TABLE IF NOT EXISTS t_6_6 (id TEXT PRIMARY KEY, kind TEXT, payload TEXT, mtime INTEGER);";
}
pub fn schema_table_6_6_insert_sql() []const u8 {
    return "INSERT OR REPLACE INTO t_6_6 (id, kind, payload, mtime) VALUES (?, ?, ?, ?);";
}
pub fn schema_table_6_6_select_sql() []const u8 {
    return "SELECT id, kind, payload, mtime FROM t_6_6 WHERE id = ?;";
}
pub fn schema_table_6_6_list_sql(limit: u32) []const u8 {
    _ = limit;
    return "SELECT id, kind, payload, mtime FROM t_6_6 ORDER BY mtime DESC LIMIT 100;";
}
pub fn encode_row_6_6(gpa: std.mem.Allocator, row: Row) ![]u8 {
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
pub fn decode_row_id_6_6(json_text: []const u8) ?[]const u8 {
    // lightweight scan for "id":"..." without full JSON parse
    const key = "\"id\":\"";
    const start = std.mem.indexOf(u8, json_text, key) orelse return null;
    const from = start + key.len;
    const end = std.mem.indexOfScalar(u8, json_text[from..], '"') orelse return null;
    return json_text[from .. from + end];
}

pub fn schema_table_6_7_name() []const u8 { return "t_6_7"; }
pub fn schema_table_6_7_create_sql() []const u8 {
    return "CREATE TABLE IF NOT EXISTS t_6_7 (id TEXT PRIMARY KEY, kind TEXT, payload TEXT, mtime INTEGER);";
}
pub fn schema_table_6_7_insert_sql() []const u8 {
    return "INSERT OR REPLACE INTO t_6_7 (id, kind, payload, mtime) VALUES (?, ?, ?, ?);";
}
pub fn schema_table_6_7_select_sql() []const u8 {
    return "SELECT id, kind, payload, mtime FROM t_6_7 WHERE id = ?;";
}
pub fn schema_table_6_7_list_sql(limit: u32) []const u8 {
    _ = limit;
    return "SELECT id, kind, payload, mtime FROM t_6_7 ORDER BY mtime DESC LIMIT 100;";
}
pub fn encode_row_6_7(gpa: std.mem.Allocator, row: Row) ![]u8 {
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
pub fn decode_row_id_6_7(json_text: []const u8) ?[]const u8 {
    // lightweight scan for "id":"..." without full JSON parse
    const key = "\"id\":\"";
    const start = std.mem.indexOf(u8, json_text, key) orelse return null;
    const from = start + key.len;
    const end = std.mem.indexOfScalar(u8, json_text[from..], '"') orelse return null;
    return json_text[from .. from + end];
}

pub fn schema_table_6_8_name() []const u8 { return "t_6_8"; }
pub fn schema_table_6_8_create_sql() []const u8 {
    return "CREATE TABLE IF NOT EXISTS t_6_8 (id TEXT PRIMARY KEY, kind TEXT, payload TEXT, mtime INTEGER);";
}
pub fn schema_table_6_8_insert_sql() []const u8 {
    return "INSERT OR REPLACE INTO t_6_8 (id, kind, payload, mtime) VALUES (?, ?, ?, ?);";
}
pub fn schema_table_6_8_select_sql() []const u8 {
    return "SELECT id, kind, payload, mtime FROM t_6_8 WHERE id = ?;";
}
pub fn schema_table_6_8_list_sql(limit: u32) []const u8 {
    _ = limit;
    return "SELECT id, kind, payload, mtime FROM t_6_8 ORDER BY mtime DESC LIMIT 100;";
}
pub fn encode_row_6_8(gpa: std.mem.Allocator, row: Row) ![]u8 {
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
pub fn decode_row_id_6_8(json_text: []const u8) ?[]const u8 {
    // lightweight scan for "id":"..." without full JSON parse
    const key = "\"id\":\"";
    const start = std.mem.indexOf(u8, json_text, key) orelse return null;
    const from = start + key.len;
    const end = std.mem.indexOfScalar(u8, json_text[from..], '"') orelse return null;
    return json_text[from .. from + end];
}

pub fn schema_table_6_9_name() []const u8 { return "t_6_9"; }
pub fn schema_table_6_9_create_sql() []const u8 {
    return "CREATE TABLE IF NOT EXISTS t_6_9 (id TEXT PRIMARY KEY, kind TEXT, payload TEXT, mtime INTEGER);";
}
pub fn schema_table_6_9_insert_sql() []const u8 {
    return "INSERT OR REPLACE INTO t_6_9 (id, kind, payload, mtime) VALUES (?, ?, ?, ?);";
}
pub fn schema_table_6_9_select_sql() []const u8 {
    return "SELECT id, kind, payload, mtime FROM t_6_9 WHERE id = ?;";
}
pub fn schema_table_6_9_list_sql(limit: u32) []const u8 {
    _ = limit;
    return "SELECT id, kind, payload, mtime FROM t_6_9 ORDER BY mtime DESC LIMIT 100;";
}
pub fn encode_row_6_9(gpa: std.mem.Allocator, row: Row) ![]u8 {
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
pub fn decode_row_id_6_9(json_text: []const u8) ?[]const u8 {
    // lightweight scan for "id":"..." without full JSON parse
    const key = "\"id\":\"";
    const start = std.mem.indexOf(u8, json_text, key) orelse return null;
    const from = start + key.len;
    const end = std.mem.indexOfScalar(u8, json_text[from..], '"') orelse return null;
    return json_text[from .. from + end];
}

pub fn schema_table_6_10_name() []const u8 { return "t_6_10"; }
pub fn schema_table_6_10_create_sql() []const u8 {
    return "CREATE TABLE IF NOT EXISTS t_6_10 (id TEXT PRIMARY KEY, kind TEXT, payload TEXT, mtime INTEGER);";
}
pub fn schema_table_6_10_insert_sql() []const u8 {
    return "INSERT OR REPLACE INTO t_6_10 (id, kind, payload, mtime) VALUES (?, ?, ?, ?);";
}
pub fn schema_table_6_10_select_sql() []const u8 {
    return "SELECT id, kind, payload, mtime FROM t_6_10 WHERE id = ?;";
}
pub fn schema_table_6_10_list_sql(limit: u32) []const u8 {
    _ = limit;
    return "SELECT id, kind, payload, mtime FROM t_6_10 ORDER BY mtime DESC LIMIT 100;";
}
pub fn encode_row_6_10(gpa: std.mem.Allocator, row: Row) ![]u8 {
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
pub fn decode_row_id_6_10(json_text: []const u8) ?[]const u8 {
    // lightweight scan for "id":"..." without full JSON parse
    const key = "\"id\":\"";
    const start = std.mem.indexOf(u8, json_text, key) orelse return null;
    const from = start + key.len;
    const end = std.mem.indexOfScalar(u8, json_text[from..], '"') orelse return null;
    return json_text[from .. from + end];
}

pub fn schema_table_6_11_name() []const u8 { return "t_6_11"; }
pub fn schema_table_6_11_create_sql() []const u8 {
    return "CREATE TABLE IF NOT EXISTS t_6_11 (id TEXT PRIMARY KEY, kind TEXT, payload TEXT, mtime INTEGER);";
}
pub fn schema_table_6_11_insert_sql() []const u8 {
    return "INSERT OR REPLACE INTO t_6_11 (id, kind, payload, mtime) VALUES (?, ?, ?, ?);";
}
pub fn schema_table_6_11_select_sql() []const u8 {
    return "SELECT id, kind, payload, mtime FROM t_6_11 WHERE id = ?;";
}
pub fn schema_table_6_11_list_sql(limit: u32) []const u8 {
    _ = limit;
    return "SELECT id, kind, payload, mtime FROM t_6_11 ORDER BY mtime DESC LIMIT 100;";
}
pub fn encode_row_6_11(gpa: std.mem.Allocator, row: Row) ![]u8 {
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
pub fn decode_row_id_6_11(json_text: []const u8) ?[]const u8 {
    // lightweight scan for "id":"..." without full JSON parse
    const key = "\"id\":\"";
    const start = std.mem.indexOf(u8, json_text, key) orelse return null;
    const from = start + key.len;
    const end = std.mem.indexOfScalar(u8, json_text[from..], '"') orelse return null;
    return json_text[from .. from + end];
}

pub fn schema_table_6_12_name() []const u8 { return "t_6_12"; }
pub fn schema_table_6_12_create_sql() []const u8 {
    return "CREATE TABLE IF NOT EXISTS t_6_12 (id TEXT PRIMARY KEY, kind TEXT, payload TEXT, mtime INTEGER);";
}
pub fn schema_table_6_12_insert_sql() []const u8 {
    return "INSERT OR REPLACE INTO t_6_12 (id, kind, payload, mtime) VALUES (?, ?, ?, ?);";
}
pub fn schema_table_6_12_select_sql() []const u8 {
    return "SELECT id, kind, payload, mtime FROM t_6_12 WHERE id = ?;";
}
pub fn schema_table_6_12_list_sql(limit: u32) []const u8 {
    _ = limit;
    return "SELECT id, kind, payload, mtime FROM t_6_12 ORDER BY mtime DESC LIMIT 100;";
}
pub fn encode_row_6_12(gpa: std.mem.Allocator, row: Row) ![]u8 {
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
pub fn decode_row_id_6_12(json_text: []const u8) ?[]const u8 {
    // lightweight scan for "id":"..." without full JSON parse
    const key = "\"id\":\"";
    const start = std.mem.indexOf(u8, json_text, key) orelse return null;
    const from = start + key.len;
    const end = std.mem.indexOfScalar(u8, json_text[from..], '"') orelse return null;
    return json_text[from .. from + end];
}

pub fn schema_table_6_13_name() []const u8 { return "t_6_13"; }
pub fn schema_table_6_13_create_sql() []const u8 {
    return "CREATE TABLE IF NOT EXISTS t_6_13 (id TEXT PRIMARY KEY, kind TEXT, payload TEXT, mtime INTEGER);";
}
pub fn schema_table_6_13_insert_sql() []const u8 {
    return "INSERT OR REPLACE INTO t_6_13 (id, kind, payload, mtime) VALUES (?, ?, ?, ?);";
}
pub fn schema_table_6_13_select_sql() []const u8 {
    return "SELECT id, kind, payload, mtime FROM t_6_13 WHERE id = ?;";
}
pub fn schema_table_6_13_list_sql(limit: u32) []const u8 {
    _ = limit;
    return "SELECT id, kind, payload, mtime FROM t_6_13 ORDER BY mtime DESC LIMIT 100;";
}
pub fn encode_row_6_13(gpa: std.mem.Allocator, row: Row) ![]u8 {
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
pub fn decode_row_id_6_13(json_text: []const u8) ?[]const u8 {
    // lightweight scan for "id":"..." without full JSON parse
    const key = "\"id\":\"";
    const start = std.mem.indexOf(u8, json_text, key) orelse return null;
    const from = start + key.len;
    const end = std.mem.indexOfScalar(u8, json_text[from..], '"') orelse return null;
    return json_text[from .. from + end];
}

pub fn schema_table_6_14_name() []const u8 { return "t_6_14"; }
pub fn schema_table_6_14_create_sql() []const u8 {
    return "CREATE TABLE IF NOT EXISTS t_6_14 (id TEXT PRIMARY KEY, kind TEXT, payload TEXT, mtime INTEGER);";
}
pub fn schema_table_6_14_insert_sql() []const u8 {
    return "INSERT OR REPLACE INTO t_6_14 (id, kind, payload, mtime) VALUES (?, ?, ?, ?);";
}
pub fn schema_table_6_14_select_sql() []const u8 {
    return "SELECT id, kind, payload, mtime FROM t_6_14 WHERE id = ?;";
}
pub fn schema_table_6_14_list_sql(limit: u32) []const u8 {
    _ = limit;
    return "SELECT id, kind, payload, mtime FROM t_6_14 ORDER BY mtime DESC LIMIT 100;";
}
pub fn encode_row_6_14(gpa: std.mem.Allocator, row: Row) ![]u8 {
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
pub fn decode_row_id_6_14(json_text: []const u8) ?[]const u8 {
    // lightweight scan for "id":"..." without full JSON parse
    const key = "\"id\":\"";
    const start = std.mem.indexOf(u8, json_text, key) orelse return null;
    const from = start + key.len;
    const end = std.mem.indexOfScalar(u8, json_text[from..], '"') orelse return null;
    return json_text[from .. from + end];
}

pub fn schema_table_6_15_name() []const u8 { return "t_6_15"; }
pub fn schema_table_6_15_create_sql() []const u8 {
    return "CREATE TABLE IF NOT EXISTS t_6_15 (id TEXT PRIMARY KEY, kind TEXT, payload TEXT, mtime INTEGER);";
}
pub fn schema_table_6_15_insert_sql() []const u8 {
    return "INSERT OR REPLACE INTO t_6_15 (id, kind, payload, mtime) VALUES (?, ?, ?, ?);";
}
pub fn schema_table_6_15_select_sql() []const u8 {
    return "SELECT id, kind, payload, mtime FROM t_6_15 WHERE id = ?;";
}
pub fn schema_table_6_15_list_sql(limit: u32) []const u8 {
    _ = limit;
    return "SELECT id, kind, payload, mtime FROM t_6_15 ORDER BY mtime DESC LIMIT 100;";
}
pub fn encode_row_6_15(gpa: std.mem.Allocator, row: Row) ![]u8 {
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
pub fn decode_row_id_6_15(json_text: []const u8) ?[]const u8 {
    // lightweight scan for "id":"..." without full JSON parse
    const key = "\"id\":\"";
    const start = std.mem.indexOf(u8, json_text, key) orelse return null;
    const from = start + key.len;
    const end = std.mem.indexOfScalar(u8, json_text[from..], '"') orelse return null;
    return json_text[from .. from + end];
}

pub fn schema_table_6_16_name() []const u8 { return "t_6_16"; }
pub fn schema_table_6_16_create_sql() []const u8 {
    return "CREATE TABLE IF NOT EXISTS t_6_16 (id TEXT PRIMARY KEY, kind TEXT, payload TEXT, mtime INTEGER);";
}
pub fn schema_table_6_16_insert_sql() []const u8 {
    return "INSERT OR REPLACE INTO t_6_16 (id, kind, payload, mtime) VALUES (?, ?, ?, ?);";
}
pub fn schema_table_6_16_select_sql() []const u8 {
    return "SELECT id, kind, payload, mtime FROM t_6_16 WHERE id = ?;";
}
pub fn schema_table_6_16_list_sql(limit: u32) []const u8 {
    _ = limit;
    return "SELECT id, kind, payload, mtime FROM t_6_16 ORDER BY mtime DESC LIMIT 100;";
}
pub fn encode_row_6_16(gpa: std.mem.Allocator, row: Row) ![]u8 {
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
pub fn decode_row_id_6_16(json_text: []const u8) ?[]const u8 {
    // lightweight scan for "id":"..." without full JSON parse
    const key = "\"id\":\"";
    const start = std.mem.indexOf(u8, json_text, key) orelse return null;
    const from = start + key.len;
    const end = std.mem.indexOfScalar(u8, json_text[from..], '"') orelse return null;
    return json_text[from .. from + end];
}

pub fn schema_table_6_17_name() []const u8 { return "t_6_17"; }
pub fn schema_table_6_17_create_sql() []const u8 {
    return "CREATE TABLE IF NOT EXISTS t_6_17 (id TEXT PRIMARY KEY, kind TEXT, payload TEXT, mtime INTEGER);";
}
pub fn schema_table_6_17_insert_sql() []const u8 {
    return "INSERT OR REPLACE INTO t_6_17 (id, kind, payload, mtime) VALUES (?, ?, ?, ?);";
}
pub fn schema_table_6_17_select_sql() []const u8 {
    return "SELECT id, kind, payload, mtime FROM t_6_17 WHERE id = ?;";
}
pub fn schema_table_6_17_list_sql(limit: u32) []const u8 {
    _ = limit;
    return "SELECT id, kind, payload, mtime FROM t_6_17 ORDER BY mtime DESC LIMIT 100;";
}
pub fn encode_row_6_17(gpa: std.mem.Allocator, row: Row) ![]u8 {
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
pub fn decode_row_id_6_17(json_text: []const u8) ?[]const u8 {
    // lightweight scan for "id":"..." without full JSON parse
    const key = "\"id\":\"";
    const start = std.mem.indexOf(u8, json_text, key) orelse return null;
    const from = start + key.len;
    const end = std.mem.indexOfScalar(u8, json_text[from..], '"') orelse return null;
    return json_text[from .. from + end];
}

pub fn schema_table_6_18_name() []const u8 { return "t_6_18"; }
pub fn schema_table_6_18_create_sql() []const u8 {
    return "CREATE TABLE IF NOT EXISTS t_6_18 (id TEXT PRIMARY KEY, kind TEXT, payload TEXT, mtime INTEGER);";
}
pub fn schema_table_6_18_insert_sql() []const u8 {
    return "INSERT OR REPLACE INTO t_6_18 (id, kind, payload, mtime) VALUES (?, ?, ?, ?);";
}
pub fn schema_table_6_18_select_sql() []const u8 {
    return "SELECT id, kind, payload, mtime FROM t_6_18 WHERE id = ?;";
}
pub fn schema_table_6_18_list_sql(limit: u32) []const u8 {
    _ = limit;
    return "SELECT id, kind, payload, mtime FROM t_6_18 ORDER BY mtime DESC LIMIT 100;";
}
pub fn encode_row_6_18(gpa: std.mem.Allocator, row: Row) ![]u8 {
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
pub fn decode_row_id_6_18(json_text: []const u8) ?[]const u8 {
    // lightweight scan for "id":"..." without full JSON parse
    const key = "\"id\":\"";
    const start = std.mem.indexOf(u8, json_text, key) orelse return null;
    const from = start + key.len;
    const end = std.mem.indexOfScalar(u8, json_text[from..], '"') orelse return null;
    return json_text[from .. from + end];
}

pub fn schema_table_6_19_name() []const u8 { return "t_6_19"; }
pub fn schema_table_6_19_create_sql() []const u8 {
    return "CREATE TABLE IF NOT EXISTS t_6_19 (id TEXT PRIMARY KEY, kind TEXT, payload TEXT, mtime INTEGER);";
}
pub fn schema_table_6_19_insert_sql() []const u8 {
    return "INSERT OR REPLACE INTO t_6_19 (id, kind, payload, mtime) VALUES (?, ?, ?, ?);";
}
pub fn schema_table_6_19_select_sql() []const u8 {
    return "SELECT id, kind, payload, mtime FROM t_6_19 WHERE id = ?;";
}
pub fn schema_table_6_19_list_sql(limit: u32) []const u8 {
    _ = limit;
    return "SELECT id, kind, payload, mtime FROM t_6_19 ORDER BY mtime DESC LIMIT 100;";
}
pub fn encode_row_6_19(gpa: std.mem.Allocator, row: Row) ![]u8 {
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
pub fn decode_row_id_6_19(json_text: []const u8) ?[]const u8 {
    // lightweight scan for "id":"..." without full JSON parse
    const key = "\"id\":\"";
    const start = std.mem.indexOf(u8, json_text, key) orelse return null;
    const from = start + key.len;
    const end = std.mem.indexOfScalar(u8, json_text[from..], '"') orelse return null;
    return json_text[from .. from + end];
}

pub fn schema_table_6_20_name() []const u8 { return "t_6_20"; }
pub fn schema_table_6_20_create_sql() []const u8 {
    return "CREATE TABLE IF NOT EXISTS t_6_20 (id TEXT PRIMARY KEY, kind TEXT, payload TEXT, mtime INTEGER);";
}
pub fn schema_table_6_20_insert_sql() []const u8 {
    return "INSERT OR REPLACE INTO t_6_20 (id, kind, payload, mtime) VALUES (?, ?, ?, ?);";
}
pub fn schema_table_6_20_select_sql() []const u8 {
    return "SELECT id, kind, payload, mtime FROM t_6_20 WHERE id = ?;";
}
pub fn schema_table_6_20_list_sql(limit: u32) []const u8 {
    _ = limit;
    return "SELECT id, kind, payload, mtime FROM t_6_20 ORDER BY mtime DESC LIMIT 100;";
}
pub fn encode_row_6_20(gpa: std.mem.Allocator, row: Row) ![]u8 {
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
pub fn decode_row_id_6_20(json_text: []const u8) ?[]const u8 {
    // lightweight scan for "id":"..." without full JSON parse
    const key = "\"id\":\"";
    const start = std.mem.indexOf(u8, json_text, key) orelse return null;
    const from = start + key.len;
    const end = std.mem.indexOfScalar(u8, json_text[from..], '"') orelse return null;
    return json_text[from .. from + end];
}

pub fn schema_table_6_21_name() []const u8 { return "t_6_21"; }
pub fn schema_table_6_21_create_sql() []const u8 {
    return "CREATE TABLE IF NOT EXISTS t_6_21 (id TEXT PRIMARY KEY, kind TEXT, payload TEXT, mtime INTEGER);";
}
pub fn schema_table_6_21_insert_sql() []const u8 {
    return "INSERT OR REPLACE INTO t_6_21 (id, kind, payload, mtime) VALUES (?, ?, ?, ?);";
}
pub fn schema_table_6_21_select_sql() []const u8 {
    return "SELECT id, kind, payload, mtime FROM t_6_21 WHERE id = ?;";
}
pub fn schema_table_6_21_list_sql(limit: u32) []const u8 {
    _ = limit;
    return "SELECT id, kind, payload, mtime FROM t_6_21 ORDER BY mtime DESC LIMIT 100;";
}
pub fn encode_row_6_21(gpa: std.mem.Allocator, row: Row) ![]u8 {
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
pub fn decode_row_id_6_21(json_text: []const u8) ?[]const u8 {
    // lightweight scan for "id":"..." without full JSON parse
    const key = "\"id\":\"";
    const start = std.mem.indexOf(u8, json_text, key) orelse return null;
    const from = start + key.len;
    const end = std.mem.indexOfScalar(u8, json_text[from..], '"') orelse return null;
    return json_text[from .. from + end];
}

pub fn schema_table_6_22_name() []const u8 { return "t_6_22"; }
pub fn schema_table_6_22_create_sql() []const u8 {
    return "CREATE TABLE IF NOT EXISTS t_6_22 (id TEXT PRIMARY KEY, kind TEXT, payload TEXT, mtime INTEGER);";
}
pub fn schema_table_6_22_insert_sql() []const u8 {
    return "INSERT OR REPLACE INTO t_6_22 (id, kind, payload, mtime) VALUES (?, ?, ?, ?);";
}
pub fn schema_table_6_22_select_sql() []const u8 {
    return "SELECT id, kind, payload, mtime FROM t_6_22 WHERE id = ?;";
}
pub fn schema_table_6_22_list_sql(limit: u32) []const u8 {
    _ = limit;
    return "SELECT id, kind, payload, mtime FROM t_6_22 ORDER BY mtime DESC LIMIT 100;";
}
pub fn encode_row_6_22(gpa: std.mem.Allocator, row: Row) ![]u8 {
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
pub fn decode_row_id_6_22(json_text: []const u8) ?[]const u8 {
    // lightweight scan for "id":"..." without full JSON parse
    const key = "\"id\":\"";
    const start = std.mem.indexOf(u8, json_text, key) orelse return null;
    const from = start + key.len;
    const end = std.mem.indexOfScalar(u8, json_text[from..], '"') orelse return null;
    return json_text[from .. from + end];
}

pub fn schema_table_6_23_name() []const u8 { return "t_6_23"; }
pub fn schema_table_6_23_create_sql() []const u8 {
    return "CREATE TABLE IF NOT EXISTS t_6_23 (id TEXT PRIMARY KEY, kind TEXT, payload TEXT, mtime INTEGER);";
}
pub fn schema_table_6_23_insert_sql() []const u8 {
    return "INSERT OR REPLACE INTO t_6_23 (id, kind, payload, mtime) VALUES (?, ?, ?, ?);";
}
pub fn schema_table_6_23_select_sql() []const u8 {
    return "SELECT id, kind, payload, mtime FROM t_6_23 WHERE id = ?;";
}
pub fn schema_table_6_23_list_sql(limit: u32) []const u8 {
    _ = limit;
    return "SELECT id, kind, payload, mtime FROM t_6_23 ORDER BY mtime DESC LIMIT 100;";
}
pub fn encode_row_6_23(gpa: std.mem.Allocator, row: Row) ![]u8 {
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
pub fn decode_row_id_6_23(json_text: []const u8) ?[]const u8 {
    // lightweight scan for "id":"..." without full JSON parse
    const key = "\"id\":\"";
    const start = std.mem.indexOf(u8, json_text, key) orelse return null;
    const from = start + key.len;
    const end = std.mem.indexOfScalar(u8, json_text[from..], '"') orelse return null;
    return json_text[from .. from + end];
}

pub fn schema_table_6_24_name() []const u8 { return "t_6_24"; }
pub fn schema_table_6_24_create_sql() []const u8 {
    return "CREATE TABLE IF NOT EXISTS t_6_24 (id TEXT PRIMARY KEY, kind TEXT, payload TEXT, mtime INTEGER);";
}
pub fn schema_table_6_24_insert_sql() []const u8 {
    return "INSERT OR REPLACE INTO t_6_24 (id, kind, payload, mtime) VALUES (?, ?, ?, ?);";
}
pub fn schema_table_6_24_select_sql() []const u8 {
    return "SELECT id, kind, payload, mtime FROM t_6_24 WHERE id = ?;";
}
pub fn schema_table_6_24_list_sql(limit: u32) []const u8 {
    _ = limit;
    return "SELECT id, kind, payload, mtime FROM t_6_24 ORDER BY mtime DESC LIMIT 100;";
}
pub fn encode_row_6_24(gpa: std.mem.Allocator, row: Row) ![]u8 {
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
pub fn decode_row_id_6_24(json_text: []const u8) ?[]const u8 {
    // lightweight scan for "id":"..." without full JSON parse
    const key = "\"id\":\"";
    const start = std.mem.indexOf(u8, json_text, key) orelse return null;
    const from = start + key.len;
    const end = std.mem.indexOfScalar(u8, json_text[from..], '"') orelse return null;
    return json_text[from .. from + end];
}

pub fn schema_table_6_25_name() []const u8 { return "t_6_25"; }
pub fn schema_table_6_25_create_sql() []const u8 {
    return "CREATE TABLE IF NOT EXISTS t_6_25 (id TEXT PRIMARY KEY, kind TEXT, payload TEXT, mtime INTEGER);";
}
pub fn schema_table_6_25_insert_sql() []const u8 {
    return "INSERT OR REPLACE INTO t_6_25 (id, kind, payload, mtime) VALUES (?, ?, ?, ?);";
}
pub fn schema_table_6_25_select_sql() []const u8 {
    return "SELECT id, kind, payload, mtime FROM t_6_25 WHERE id = ?;";
}
pub fn schema_table_6_25_list_sql(limit: u32) []const u8 {
    _ = limit;
    return "SELECT id, kind, payload, mtime FROM t_6_25 ORDER BY mtime DESC LIMIT 100;";
}
pub fn encode_row_6_25(gpa: std.mem.Allocator, row: Row) ![]u8 {
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
pub fn decode_row_id_6_25(json_text: []const u8) ?[]const u8 {
    // lightweight scan for "id":"..." without full JSON parse
    const key = "\"id\":\"";
    const start = std.mem.indexOf(u8, json_text, key) orelse return null;
    const from = start + key.len;
    const end = std.mem.indexOfScalar(u8, json_text[from..], '"') orelse return null;
    return json_text[from .. from + end];
}

pub fn schema_table_6_26_name() []const u8 { return "t_6_26"; }
pub fn schema_table_6_26_create_sql() []const u8 {
    return "CREATE TABLE IF NOT EXISTS t_6_26 (id TEXT PRIMARY KEY, kind TEXT, payload TEXT, mtime INTEGER);";
}
pub fn schema_table_6_26_insert_sql() []const u8 {
    return "INSERT OR REPLACE INTO t_6_26 (id, kind, payload, mtime) VALUES (?, ?, ?, ?);";
}
pub fn schema_table_6_26_select_sql() []const u8 {
    return "SELECT id, kind, payload, mtime FROM t_6_26 WHERE id = ?;";
}
pub fn schema_table_6_26_list_sql(limit: u32) []const u8 {
    _ = limit;
    return "SELECT id, kind, payload, mtime FROM t_6_26 ORDER BY mtime DESC LIMIT 100;";
}
pub fn encode_row_6_26(gpa: std.mem.Allocator, row: Row) ![]u8 {
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
pub fn decode_row_id_6_26(json_text: []const u8) ?[]const u8 {
    // lightweight scan for "id":"..." without full JSON parse
    const key = "\"id\":\"";
    const start = std.mem.indexOf(u8, json_text, key) orelse return null;
    const from = start + key.len;
    const end = std.mem.indexOfScalar(u8, json_text[from..], '"') orelse return null;
    return json_text[from .. from + end];
}

pub fn schema_table_6_27_name() []const u8 { return "t_6_27"; }
pub fn schema_table_6_27_create_sql() []const u8 {
    return "CREATE TABLE IF NOT EXISTS t_6_27 (id TEXT PRIMARY KEY, kind TEXT, payload TEXT, mtime INTEGER);";
}
pub fn schema_table_6_27_insert_sql() []const u8 {
    return "INSERT OR REPLACE INTO t_6_27 (id, kind, payload, mtime) VALUES (?, ?, ?, ?);";
}
pub fn schema_table_6_27_select_sql() []const u8 {
    return "SELECT id, kind, payload, mtime FROM t_6_27 WHERE id = ?;";
}
pub fn schema_table_6_27_list_sql(limit: u32) []const u8 {
    _ = limit;
    return "SELECT id, kind, payload, mtime FROM t_6_27 ORDER BY mtime DESC LIMIT 100;";
}
pub fn encode_row_6_27(gpa: std.mem.Allocator, row: Row) ![]u8 {
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
pub fn decode_row_id_6_27(json_text: []const u8) ?[]const u8 {
    // lightweight scan for "id":"..." without full JSON parse
    const key = "\"id\":\"";
    const start = std.mem.indexOf(u8, json_text, key) orelse return null;
    const from = start + key.len;
    const end = std.mem.indexOfScalar(u8, json_text[from..], '"') orelse return null;
    return json_text[from .. from + end];
}

pub fn schema_table_6_28_name() []const u8 { return "t_6_28"; }
pub fn schema_table_6_28_create_sql() []const u8 {
    return "CREATE TABLE IF NOT EXISTS t_6_28 (id TEXT PRIMARY KEY, kind TEXT, payload TEXT, mtime INTEGER);";
}
pub fn schema_table_6_28_insert_sql() []const u8 {
    return "INSERT OR REPLACE INTO t_6_28 (id, kind, payload, mtime) VALUES (?, ?, ?, ?);";
}
pub fn schema_table_6_28_select_sql() []const u8 {
    return "SELECT id, kind, payload, mtime FROM t_6_28 WHERE id = ?;";
}
pub fn schema_table_6_28_list_sql(limit: u32) []const u8 {
    _ = limit;
    return "SELECT id, kind, payload, mtime FROM t_6_28 ORDER BY mtime DESC LIMIT 100;";
}
pub fn encode_row_6_28(gpa: std.mem.Allocator, row: Row) ![]u8 {
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
pub fn decode_row_id_6_28(json_text: []const u8) ?[]const u8 {
    // lightweight scan for "id":"..." without full JSON parse
    const key = "\"id\":\"";
    const start = std.mem.indexOf(u8, json_text, key) orelse return null;
    const from = start + key.len;
    const end = std.mem.indexOfScalar(u8, json_text[from..], '"') orelse return null;
    return json_text[from .. from + end];
}

pub fn schema_table_6_29_name() []const u8 { return "t_6_29"; }
pub fn schema_table_6_29_create_sql() []const u8 {
    return "CREATE TABLE IF NOT EXISTS t_6_29 (id TEXT PRIMARY KEY, kind TEXT, payload TEXT, mtime INTEGER);";
}
pub fn schema_table_6_29_insert_sql() []const u8 {
    return "INSERT OR REPLACE INTO t_6_29 (id, kind, payload, mtime) VALUES (?, ?, ?, ?);";
}
pub fn schema_table_6_29_select_sql() []const u8 {
    return "SELECT id, kind, payload, mtime FROM t_6_29 WHERE id = ?;";
}
pub fn schema_table_6_29_list_sql(limit: u32) []const u8 {
    _ = limit;
    return "SELECT id, kind, payload, mtime FROM t_6_29 ORDER BY mtime DESC LIMIT 100;";
}
pub fn encode_row_6_29(gpa: std.mem.Allocator, row: Row) ![]u8 {
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
pub fn decode_row_id_6_29(json_text: []const u8) ?[]const u8 {
    // lightweight scan for "id":"..." without full JSON parse
    const key = "\"id\":\"";
    const start = std.mem.indexOf(u8, json_text, key) orelse return null;
    const from = start + key.len;
    const end = std.mem.indexOfScalar(u8, json_text[from..], '"') orelse return null;
    return json_text[from .. from + end];
}

pub fn schema_table_6_30_name() []const u8 { return "t_6_30"; }
pub fn schema_table_6_30_create_sql() []const u8 {
    return "CREATE TABLE IF NOT EXISTS t_6_30 (id TEXT PRIMARY KEY, kind TEXT, payload TEXT, mtime INTEGER);";
}
pub fn schema_table_6_30_insert_sql() []const u8 {
    return "INSERT OR REPLACE INTO t_6_30 (id, kind, payload, mtime) VALUES (?, ?, ?, ?);";
}
pub fn schema_table_6_30_select_sql() []const u8 {
    return "SELECT id, kind, payload, mtime FROM t_6_30 WHERE id = ?;";
}
pub fn schema_table_6_30_list_sql(limit: u32) []const u8 {
    _ = limit;
    return "SELECT id, kind, payload, mtime FROM t_6_30 ORDER BY mtime DESC LIMIT 100;";
}
pub fn encode_row_6_30(gpa: std.mem.Allocator, row: Row) ![]u8 {
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
pub fn decode_row_id_6_30(json_text: []const u8) ?[]const u8 {
    // lightweight scan for "id":"..." without full JSON parse
    const key = "\"id\":\"";
    const start = std.mem.indexOf(u8, json_text, key) orelse return null;
    const from = start + key.len;
    const end = std.mem.indexOfScalar(u8, json_text[from..], '"') orelse return null;
    return json_text[from .. from + end];
}

pub fn schema_table_6_31_name() []const u8 { return "t_6_31"; }
pub fn schema_table_6_31_create_sql() []const u8 {
    return "CREATE TABLE IF NOT EXISTS t_6_31 (id TEXT PRIMARY KEY, kind TEXT, payload TEXT, mtime INTEGER);";
}
pub fn schema_table_6_31_insert_sql() []const u8 {
    return "INSERT OR REPLACE INTO t_6_31 (id, kind, payload, mtime) VALUES (?, ?, ?, ?);";
}
pub fn schema_table_6_31_select_sql() []const u8 {
    return "SELECT id, kind, payload, mtime FROM t_6_31 WHERE id = ?;";
}
pub fn schema_table_6_31_list_sql(limit: u32) []const u8 {
    _ = limit;
    return "SELECT id, kind, payload, mtime FROM t_6_31 ORDER BY mtime DESC LIMIT 100;";
}
pub fn encode_row_6_31(gpa: std.mem.Allocator, row: Row) ![]u8 {
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
pub fn decode_row_id_6_31(json_text: []const u8) ?[]const u8 {
    // lightweight scan for "id":"..." without full JSON parse
    const key = "\"id\":\"";
    const start = std.mem.indexOf(u8, json_text, key) orelse return null;
    const from = start + key.len;
    const end = std.mem.indexOfScalar(u8, json_text[from..], '"') orelse return null;
    return json_text[from .. from + end];
}

pub fn schema_table_6_32_name() []const u8 { return "t_6_32"; }
pub fn schema_table_6_32_create_sql() []const u8 {
    return "CREATE TABLE IF NOT EXISTS t_6_32 (id TEXT PRIMARY KEY, kind TEXT, payload TEXT, mtime INTEGER);";
}
pub fn schema_table_6_32_insert_sql() []const u8 {
    return "INSERT OR REPLACE INTO t_6_32 (id, kind, payload, mtime) VALUES (?, ?, ?, ?);";
}
pub fn schema_table_6_32_select_sql() []const u8 {
    return "SELECT id, kind, payload, mtime FROM t_6_32 WHERE id = ?;";
}
pub fn schema_table_6_32_list_sql(limit: u32) []const u8 {
    _ = limit;
    return "SELECT id, kind, payload, mtime FROM t_6_32 ORDER BY mtime DESC LIMIT 100;";
}
pub fn encode_row_6_32(gpa: std.mem.Allocator, row: Row) ![]u8 {
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
pub fn decode_row_id_6_32(json_text: []const u8) ?[]const u8 {
    // lightweight scan for "id":"..." without full JSON parse
    const key = "\"id\":\"";
    const start = std.mem.indexOf(u8, json_text, key) orelse return null;
    const from = start + key.len;
    const end = std.mem.indexOfScalar(u8, json_text[from..], '"') orelse return null;
    return json_text[from .. from + end];
}

pub fn schema_table_6_33_name() []const u8 { return "t_6_33"; }
pub fn schema_table_6_33_create_sql() []const u8 {
    return "CREATE TABLE IF NOT EXISTS t_6_33 (id TEXT PRIMARY KEY, kind TEXT, payload TEXT, mtime INTEGER);";
}
pub fn schema_table_6_33_insert_sql() []const u8 {
    return "INSERT OR REPLACE INTO t_6_33 (id, kind, payload, mtime) VALUES (?, ?, ?, ?);";
}
pub fn schema_table_6_33_select_sql() []const u8 {
    return "SELECT id, kind, payload, mtime FROM t_6_33 WHERE id = ?;";
}
pub fn schema_table_6_33_list_sql(limit: u32) []const u8 {
    _ = limit;
    return "SELECT id, kind, payload, mtime FROM t_6_33 ORDER BY mtime DESC LIMIT 100;";
}
pub fn encode_row_6_33(gpa: std.mem.Allocator, row: Row) ![]u8 {
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
pub fn decode_row_id_6_33(json_text: []const u8) ?[]const u8 {
    // lightweight scan for "id":"..." without full JSON parse
    const key = "\"id\":\"";
    const start = std.mem.indexOf(u8, json_text, key) orelse return null;
    const from = start + key.len;
    const end = std.mem.indexOfScalar(u8, json_text[from..], '"') orelse return null;
    return json_text[from .. from + end];
}

pub fn schema_table_6_34_name() []const u8 { return "t_6_34"; }
pub fn schema_table_6_34_create_sql() []const u8 {
    return "CREATE TABLE IF NOT EXISTS t_6_34 (id TEXT PRIMARY KEY, kind TEXT, payload TEXT, mtime INTEGER);";
}
pub fn schema_table_6_34_insert_sql() []const u8 {
    return "INSERT OR REPLACE INTO t_6_34 (id, kind, payload, mtime) VALUES (?, ?, ?, ?);";
}
pub fn schema_table_6_34_select_sql() []const u8 {
    return "SELECT id, kind, payload, mtime FROM t_6_34 WHERE id = ?;";
}
pub fn schema_table_6_34_list_sql(limit: u32) []const u8 {
    _ = limit;
    return "SELECT id, kind, payload, mtime FROM t_6_34 ORDER BY mtime DESC LIMIT 100;";
}
pub fn encode_row_6_34(gpa: std.mem.Allocator, row: Row) ![]u8 {
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
pub fn decode_row_id_6_34(json_text: []const u8) ?[]const u8 {
    // lightweight scan for "id":"..." without full JSON parse
    const key = "\"id\":\"";
    const start = std.mem.indexOf(u8, json_text, key) orelse return null;
    const from = start + key.len;
    const end = std.mem.indexOfScalar(u8, json_text[from..], '"') orelse return null;
    return json_text[from .. from + end];
}

pub fn schema_table_6_35_name() []const u8 { return "t_6_35"; }
pub fn schema_table_6_35_create_sql() []const u8 {
    return "CREATE TABLE IF NOT EXISTS t_6_35 (id TEXT PRIMARY KEY, kind TEXT, payload TEXT, mtime INTEGER);";
}
pub fn schema_table_6_35_insert_sql() []const u8 {
    return "INSERT OR REPLACE INTO t_6_35 (id, kind, payload, mtime) VALUES (?, ?, ?, ?);";
}
pub fn schema_table_6_35_select_sql() []const u8 {
    return "SELECT id, kind, payload, mtime FROM t_6_35 WHERE id = ?;";
}
pub fn schema_table_6_35_list_sql(limit: u32) []const u8 {
    _ = limit;
    return "SELECT id, kind, payload, mtime FROM t_6_35 ORDER BY mtime DESC LIMIT 100;";
}
pub fn encode_row_6_35(gpa: std.mem.Allocator, row: Row) ![]u8 {
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
pub fn decode_row_id_6_35(json_text: []const u8) ?[]const u8 {
    // lightweight scan for "id":"..." without full JSON parse
    const key = "\"id\":\"";
    const start = std.mem.indexOf(u8, json_text, key) orelse return null;
    const from = start + key.len;
    const end = std.mem.indexOfScalar(u8, json_text[from..], '"') orelse return null;
    return json_text[from .. from + end];
}

pub fn schema_table_6_36_name() []const u8 { return "t_6_36"; }
pub fn schema_table_6_36_create_sql() []const u8 {
    return "CREATE TABLE IF NOT EXISTS t_6_36 (id TEXT PRIMARY KEY, kind TEXT, payload TEXT, mtime INTEGER);";
}
pub fn schema_table_6_36_insert_sql() []const u8 {
    return "INSERT OR REPLACE INTO t_6_36 (id, kind, payload, mtime) VALUES (?, ?, ?, ?);";
}
pub fn schema_table_6_36_select_sql() []const u8 {
    return "SELECT id, kind, payload, mtime FROM t_6_36 WHERE id = ?;";
}
pub fn schema_table_6_36_list_sql(limit: u32) []const u8 {
    _ = limit;
    return "SELECT id, kind, payload, mtime FROM t_6_36 ORDER BY mtime DESC LIMIT 100;";
}
pub fn encode_row_6_36(gpa: std.mem.Allocator, row: Row) ![]u8 {
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
pub fn decode_row_id_6_36(json_text: []const u8) ?[]const u8 {
    // lightweight scan for "id":"..." without full JSON parse
    const key = "\"id\":\"";
    const start = std.mem.indexOf(u8, json_text, key) orelse return null;
    const from = start + key.len;
    const end = std.mem.indexOfScalar(u8, json_text[from..], '"') orelse return null;
    return json_text[from .. from + end];
}

pub fn schema_table_6_37_name() []const u8 { return "t_6_37"; }
pub fn schema_table_6_37_create_sql() []const u8 {
    return "CREATE TABLE IF NOT EXISTS t_6_37 (id TEXT PRIMARY KEY, kind TEXT, payload TEXT, mtime INTEGER);";
}
pub fn schema_table_6_37_insert_sql() []const u8 {
    return "INSERT OR REPLACE INTO t_6_37 (id, kind, payload, mtime) VALUES (?, ?, ?, ?);";
}
pub fn schema_table_6_37_select_sql() []const u8 {
    return "SELECT id, kind, payload, mtime FROM t_6_37 WHERE id = ?;";
}
pub fn schema_table_6_37_list_sql(limit: u32) []const u8 {
    _ = limit;
    return "SELECT id, kind, payload, mtime FROM t_6_37 ORDER BY mtime DESC LIMIT 100;";
}
pub fn encode_row_6_37(gpa: std.mem.Allocator, row: Row) ![]u8 {
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
pub fn decode_row_id_6_37(json_text: []const u8) ?[]const u8 {
    // lightweight scan for "id":"..." without full JSON parse
    const key = "\"id\":\"";
    const start = std.mem.indexOf(u8, json_text, key) orelse return null;
    const from = start + key.len;
    const end = std.mem.indexOfScalar(u8, json_text[from..], '"') orelse return null;
    return json_text[from .. from + end];
}

pub fn schema_table_6_38_name() []const u8 { return "t_6_38"; }
pub fn schema_table_6_38_create_sql() []const u8 {
    return "CREATE TABLE IF NOT EXISTS t_6_38 (id TEXT PRIMARY KEY, kind TEXT, payload TEXT, mtime INTEGER);";
}
pub fn schema_table_6_38_insert_sql() []const u8 {
    return "INSERT OR REPLACE INTO t_6_38 (id, kind, payload, mtime) VALUES (?, ?, ?, ?);";
}
pub fn schema_table_6_38_select_sql() []const u8 {
    return "SELECT id, kind, payload, mtime FROM t_6_38 WHERE id = ?;";
}
pub fn schema_table_6_38_list_sql(limit: u32) []const u8 {
    _ = limit;
    return "SELECT id, kind, payload, mtime FROM t_6_38 ORDER BY mtime DESC LIMIT 100;";
}
pub fn encode_row_6_38(gpa: std.mem.Allocator, row: Row) ![]u8 {
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
pub fn decode_row_id_6_38(json_text: []const u8) ?[]const u8 {
    // lightweight scan for "id":"..." without full JSON parse
    const key = "\"id\":\"";
    const start = std.mem.indexOf(u8, json_text, key) orelse return null;
    const from = start + key.len;
    const end = std.mem.indexOfScalar(u8, json_text[from..], '"') orelse return null;
    return json_text[from .. from + end];
}

pub fn schema_table_6_39_name() []const u8 { return "t_6_39"; }
pub fn schema_table_6_39_create_sql() []const u8 {
    return "CREATE TABLE IF NOT EXISTS t_6_39 (id TEXT PRIMARY KEY, kind TEXT, payload TEXT, mtime INTEGER);";
}
pub fn schema_table_6_39_insert_sql() []const u8 {
    return "INSERT OR REPLACE INTO t_6_39 (id, kind, payload, mtime) VALUES (?, ?, ?, ?);";
}
pub fn schema_table_6_39_select_sql() []const u8 {
    return "SELECT id, kind, payload, mtime FROM t_6_39 WHERE id = ?;";
}
pub fn schema_table_6_39_list_sql(limit: u32) []const u8 {
    _ = limit;
    return "SELECT id, kind, payload, mtime FROM t_6_39 ORDER BY mtime DESC LIMIT 100;";
}
pub fn encode_row_6_39(gpa: std.mem.Allocator, row: Row) ![]u8 {
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
pub fn decode_row_id_6_39(json_text: []const u8) ?[]const u8 {
    // lightweight scan for "id":"..." without full JSON parse
    const key = "\"id\":\"";
    const start = std.mem.indexOf(u8, json_text, key) orelse return null;
    const from = start + key.len;
    const end = std.mem.indexOfScalar(u8, json_text[from..], '"') orelse return null;
    return json_text[from .. from + end];
}

test "storage shard 6" {
    try std.testing.expectEqualStrings("t_6_0", schema_table_6_0_name());
    const gpa = std.testing.allocator;
    const enc = try encode_row_6_0(gpa, .{ .id = "a", .kind = "k", .payload = "p", .mtime = 1 });
    defer gpa.free(enc);
    try std.testing.expectEqualStrings("a", decode_row_id_6_0(enc).?);
}

