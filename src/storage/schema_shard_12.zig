//! Generated storage schema/query helpers shard 12.
const std = @import("std");

pub const Row = struct {
    id: []const u8,
    kind: []const u8,
    payload: []const u8,
    mtime: i64,
};

pub fn schema_table_12_0_name() []const u8 { return "t_12_0"; }
pub fn schema_table_12_0_create_sql() []const u8 {
    return "CREATE TABLE IF NOT EXISTS t_12_0 (id TEXT PRIMARY KEY, kind TEXT, payload TEXT, mtime INTEGER);";
}
pub fn schema_table_12_0_insert_sql() []const u8 {
    return "INSERT OR REPLACE INTO t_12_0 (id, kind, payload, mtime) VALUES (?, ?, ?, ?);";
}
pub fn schema_table_12_0_select_sql() []const u8 {
    return "SELECT id, kind, payload, mtime FROM t_12_0 WHERE id = ?;";
}
pub fn schema_table_12_0_list_sql(limit: u32) []const u8 {
    _ = limit;
    return "SELECT id, kind, payload, mtime FROM t_12_0 ORDER BY mtime DESC LIMIT 100;";
}
pub fn encode_row_12_0(gpa: std.mem.Allocator, row: Row) ![]u8 {
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
pub fn decode_row_id_12_0(json_text: []const u8) ?[]const u8 {
    // lightweight scan for "id":"..." without full JSON parse
    const key = "\"id\":\"";
    const start = std.mem.indexOf(u8, json_text, key) orelse return null;
    const from = start + key.len;
    const end = std.mem.indexOfScalar(u8, json_text[from..], '"') orelse return null;
    return json_text[from .. from + end];
}

pub fn schema_table_12_1_name() []const u8 { return "t_12_1"; }
pub fn schema_table_12_1_create_sql() []const u8 {
    return "CREATE TABLE IF NOT EXISTS t_12_1 (id TEXT PRIMARY KEY, kind TEXT, payload TEXT, mtime INTEGER);";
}
pub fn schema_table_12_1_insert_sql() []const u8 {
    return "INSERT OR REPLACE INTO t_12_1 (id, kind, payload, mtime) VALUES (?, ?, ?, ?);";
}
pub fn schema_table_12_1_select_sql() []const u8 {
    return "SELECT id, kind, payload, mtime FROM t_12_1 WHERE id = ?;";
}
pub fn schema_table_12_1_list_sql(limit: u32) []const u8 {
    _ = limit;
    return "SELECT id, kind, payload, mtime FROM t_12_1 ORDER BY mtime DESC LIMIT 100;";
}
pub fn encode_row_12_1(gpa: std.mem.Allocator, row: Row) ![]u8 {
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
pub fn decode_row_id_12_1(json_text: []const u8) ?[]const u8 {
    // lightweight scan for "id":"..." without full JSON parse
    const key = "\"id\":\"";
    const start = std.mem.indexOf(u8, json_text, key) orelse return null;
    const from = start + key.len;
    const end = std.mem.indexOfScalar(u8, json_text[from..], '"') orelse return null;
    return json_text[from .. from + end];
}

pub fn schema_table_12_2_name() []const u8 { return "t_12_2"; }
pub fn schema_table_12_2_create_sql() []const u8 {
    return "CREATE TABLE IF NOT EXISTS t_12_2 (id TEXT PRIMARY KEY, kind TEXT, payload TEXT, mtime INTEGER);";
}
pub fn schema_table_12_2_insert_sql() []const u8 {
    return "INSERT OR REPLACE INTO t_12_2 (id, kind, payload, mtime) VALUES (?, ?, ?, ?);";
}
pub fn schema_table_12_2_select_sql() []const u8 {
    return "SELECT id, kind, payload, mtime FROM t_12_2 WHERE id = ?;";
}
pub fn schema_table_12_2_list_sql(limit: u32) []const u8 {
    _ = limit;
    return "SELECT id, kind, payload, mtime FROM t_12_2 ORDER BY mtime DESC LIMIT 100;";
}
pub fn encode_row_12_2(gpa: std.mem.Allocator, row: Row) ![]u8 {
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
pub fn decode_row_id_12_2(json_text: []const u8) ?[]const u8 {
    // lightweight scan for "id":"..." without full JSON parse
    const key = "\"id\":\"";
    const start = std.mem.indexOf(u8, json_text, key) orelse return null;
    const from = start + key.len;
    const end = std.mem.indexOfScalar(u8, json_text[from..], '"') orelse return null;
    return json_text[from .. from + end];
}

pub fn schema_table_12_3_name() []const u8 { return "t_12_3"; }
pub fn schema_table_12_3_create_sql() []const u8 {
    return "CREATE TABLE IF NOT EXISTS t_12_3 (id TEXT PRIMARY KEY, kind TEXT, payload TEXT, mtime INTEGER);";
}
pub fn schema_table_12_3_insert_sql() []const u8 {
    return "INSERT OR REPLACE INTO t_12_3 (id, kind, payload, mtime) VALUES (?, ?, ?, ?);";
}
pub fn schema_table_12_3_select_sql() []const u8 {
    return "SELECT id, kind, payload, mtime FROM t_12_3 WHERE id = ?;";
}
pub fn schema_table_12_3_list_sql(limit: u32) []const u8 {
    _ = limit;
    return "SELECT id, kind, payload, mtime FROM t_12_3 ORDER BY mtime DESC LIMIT 100;";
}
pub fn encode_row_12_3(gpa: std.mem.Allocator, row: Row) ![]u8 {
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
pub fn decode_row_id_12_3(json_text: []const u8) ?[]const u8 {
    // lightweight scan for "id":"..." without full JSON parse
    const key = "\"id\":\"";
    const start = std.mem.indexOf(u8, json_text, key) orelse return null;
    const from = start + key.len;
    const end = std.mem.indexOfScalar(u8, json_text[from..], '"') orelse return null;
    return json_text[from .. from + end];
}

pub fn schema_table_12_4_name() []const u8 { return "t_12_4"; }
pub fn schema_table_12_4_create_sql() []const u8 {
    return "CREATE TABLE IF NOT EXISTS t_12_4 (id TEXT PRIMARY KEY, kind TEXT, payload TEXT, mtime INTEGER);";
}
pub fn schema_table_12_4_insert_sql() []const u8 {
    return "INSERT OR REPLACE INTO t_12_4 (id, kind, payload, mtime) VALUES (?, ?, ?, ?);";
}
pub fn schema_table_12_4_select_sql() []const u8 {
    return "SELECT id, kind, payload, mtime FROM t_12_4 WHERE id = ?;";
}
pub fn schema_table_12_4_list_sql(limit: u32) []const u8 {
    _ = limit;
    return "SELECT id, kind, payload, mtime FROM t_12_4 ORDER BY mtime DESC LIMIT 100;";
}
pub fn encode_row_12_4(gpa: std.mem.Allocator, row: Row) ![]u8 {
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
pub fn decode_row_id_12_4(json_text: []const u8) ?[]const u8 {
    // lightweight scan for "id":"..." without full JSON parse
    const key = "\"id\":\"";
    const start = std.mem.indexOf(u8, json_text, key) orelse return null;
    const from = start + key.len;
    const end = std.mem.indexOfScalar(u8, json_text[from..], '"') orelse return null;
    return json_text[from .. from + end];
}

pub fn schema_table_12_5_name() []const u8 { return "t_12_5"; }
pub fn schema_table_12_5_create_sql() []const u8 {
    return "CREATE TABLE IF NOT EXISTS t_12_5 (id TEXT PRIMARY KEY, kind TEXT, payload TEXT, mtime INTEGER);";
}
pub fn schema_table_12_5_insert_sql() []const u8 {
    return "INSERT OR REPLACE INTO t_12_5 (id, kind, payload, mtime) VALUES (?, ?, ?, ?);";
}
pub fn schema_table_12_5_select_sql() []const u8 {
    return "SELECT id, kind, payload, mtime FROM t_12_5 WHERE id = ?;";
}
pub fn schema_table_12_5_list_sql(limit: u32) []const u8 {
    _ = limit;
    return "SELECT id, kind, payload, mtime FROM t_12_5 ORDER BY mtime DESC LIMIT 100;";
}
pub fn encode_row_12_5(gpa: std.mem.Allocator, row: Row) ![]u8 {
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
pub fn decode_row_id_12_5(json_text: []const u8) ?[]const u8 {
    // lightweight scan for "id":"..." without full JSON parse
    const key = "\"id\":\"";
    const start = std.mem.indexOf(u8, json_text, key) orelse return null;
    const from = start + key.len;
    const end = std.mem.indexOfScalar(u8, json_text[from..], '"') orelse return null;
    return json_text[from .. from + end];
}

pub fn schema_table_12_6_name() []const u8 { return "t_12_6"; }
pub fn schema_table_12_6_create_sql() []const u8 {
    return "CREATE TABLE IF NOT EXISTS t_12_6 (id TEXT PRIMARY KEY, kind TEXT, payload TEXT, mtime INTEGER);";
}
pub fn schema_table_12_6_insert_sql() []const u8 {
    return "INSERT OR REPLACE INTO t_12_6 (id, kind, payload, mtime) VALUES (?, ?, ?, ?);";
}
pub fn schema_table_12_6_select_sql() []const u8 {
    return "SELECT id, kind, payload, mtime FROM t_12_6 WHERE id = ?;";
}
pub fn schema_table_12_6_list_sql(limit: u32) []const u8 {
    _ = limit;
    return "SELECT id, kind, payload, mtime FROM t_12_6 ORDER BY mtime DESC LIMIT 100;";
}
pub fn encode_row_12_6(gpa: std.mem.Allocator, row: Row) ![]u8 {
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
pub fn decode_row_id_12_6(json_text: []const u8) ?[]const u8 {
    // lightweight scan for "id":"..." without full JSON parse
    const key = "\"id\":\"";
    const start = std.mem.indexOf(u8, json_text, key) orelse return null;
    const from = start + key.len;
    const end = std.mem.indexOfScalar(u8, json_text[from..], '"') orelse return null;
    return json_text[from .. from + end];
}

pub fn schema_table_12_7_name() []const u8 { return "t_12_7"; }
pub fn schema_table_12_7_create_sql() []const u8 {
    return "CREATE TABLE IF NOT EXISTS t_12_7 (id TEXT PRIMARY KEY, kind TEXT, payload TEXT, mtime INTEGER);";
}
pub fn schema_table_12_7_insert_sql() []const u8 {
    return "INSERT OR REPLACE INTO t_12_7 (id, kind, payload, mtime) VALUES (?, ?, ?, ?);";
}
pub fn schema_table_12_7_select_sql() []const u8 {
    return "SELECT id, kind, payload, mtime FROM t_12_7 WHERE id = ?;";
}
pub fn schema_table_12_7_list_sql(limit: u32) []const u8 {
    _ = limit;
    return "SELECT id, kind, payload, mtime FROM t_12_7 ORDER BY mtime DESC LIMIT 100;";
}
pub fn encode_row_12_7(gpa: std.mem.Allocator, row: Row) ![]u8 {
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
pub fn decode_row_id_12_7(json_text: []const u8) ?[]const u8 {
    // lightweight scan for "id":"..." without full JSON parse
    const key = "\"id\":\"";
    const start = std.mem.indexOf(u8, json_text, key) orelse return null;
    const from = start + key.len;
    const end = std.mem.indexOfScalar(u8, json_text[from..], '"') orelse return null;
    return json_text[from .. from + end];
}

pub fn schema_table_12_8_name() []const u8 { return "t_12_8"; }
pub fn schema_table_12_8_create_sql() []const u8 {
    return "CREATE TABLE IF NOT EXISTS t_12_8 (id TEXT PRIMARY KEY, kind TEXT, payload TEXT, mtime INTEGER);";
}
pub fn schema_table_12_8_insert_sql() []const u8 {
    return "INSERT OR REPLACE INTO t_12_8 (id, kind, payload, mtime) VALUES (?, ?, ?, ?);";
}
pub fn schema_table_12_8_select_sql() []const u8 {
    return "SELECT id, kind, payload, mtime FROM t_12_8 WHERE id = ?;";
}
pub fn schema_table_12_8_list_sql(limit: u32) []const u8 {
    _ = limit;
    return "SELECT id, kind, payload, mtime FROM t_12_8 ORDER BY mtime DESC LIMIT 100;";
}
pub fn encode_row_12_8(gpa: std.mem.Allocator, row: Row) ![]u8 {
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
pub fn decode_row_id_12_8(json_text: []const u8) ?[]const u8 {
    // lightweight scan for "id":"..." without full JSON parse
    const key = "\"id\":\"";
    const start = std.mem.indexOf(u8, json_text, key) orelse return null;
    const from = start + key.len;
    const end = std.mem.indexOfScalar(u8, json_text[from..], '"') orelse return null;
    return json_text[from .. from + end];
}

pub fn schema_table_12_9_name() []const u8 { return "t_12_9"; }
pub fn schema_table_12_9_create_sql() []const u8 {
    return "CREATE TABLE IF NOT EXISTS t_12_9 (id TEXT PRIMARY KEY, kind TEXT, payload TEXT, mtime INTEGER);";
}
pub fn schema_table_12_9_insert_sql() []const u8 {
    return "INSERT OR REPLACE INTO t_12_9 (id, kind, payload, mtime) VALUES (?, ?, ?, ?);";
}
pub fn schema_table_12_9_select_sql() []const u8 {
    return "SELECT id, kind, payload, mtime FROM t_12_9 WHERE id = ?;";
}
pub fn schema_table_12_9_list_sql(limit: u32) []const u8 {
    _ = limit;
    return "SELECT id, kind, payload, mtime FROM t_12_9 ORDER BY mtime DESC LIMIT 100;";
}
pub fn encode_row_12_9(gpa: std.mem.Allocator, row: Row) ![]u8 {
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
pub fn decode_row_id_12_9(json_text: []const u8) ?[]const u8 {
    // lightweight scan for "id":"..." without full JSON parse
    const key = "\"id\":\"";
    const start = std.mem.indexOf(u8, json_text, key) orelse return null;
    const from = start + key.len;
    const end = std.mem.indexOfScalar(u8, json_text[from..], '"') orelse return null;
    return json_text[from .. from + end];
}

pub fn schema_table_12_10_name() []const u8 { return "t_12_10"; }
pub fn schema_table_12_10_create_sql() []const u8 {
    return "CREATE TABLE IF NOT EXISTS t_12_10 (id TEXT PRIMARY KEY, kind TEXT, payload TEXT, mtime INTEGER);";
}
pub fn schema_table_12_10_insert_sql() []const u8 {
    return "INSERT OR REPLACE INTO t_12_10 (id, kind, payload, mtime) VALUES (?, ?, ?, ?);";
}
pub fn schema_table_12_10_select_sql() []const u8 {
    return "SELECT id, kind, payload, mtime FROM t_12_10 WHERE id = ?;";
}
pub fn schema_table_12_10_list_sql(limit: u32) []const u8 {
    _ = limit;
    return "SELECT id, kind, payload, mtime FROM t_12_10 ORDER BY mtime DESC LIMIT 100;";
}
pub fn encode_row_12_10(gpa: std.mem.Allocator, row: Row) ![]u8 {
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
pub fn decode_row_id_12_10(json_text: []const u8) ?[]const u8 {
    // lightweight scan for "id":"..." without full JSON parse
    const key = "\"id\":\"";
    const start = std.mem.indexOf(u8, json_text, key) orelse return null;
    const from = start + key.len;
    const end = std.mem.indexOfScalar(u8, json_text[from..], '"') orelse return null;
    return json_text[from .. from + end];
}

pub fn schema_table_12_11_name() []const u8 { return "t_12_11"; }
pub fn schema_table_12_11_create_sql() []const u8 {
    return "CREATE TABLE IF NOT EXISTS t_12_11 (id TEXT PRIMARY KEY, kind TEXT, payload TEXT, mtime INTEGER);";
}
pub fn schema_table_12_11_insert_sql() []const u8 {
    return "INSERT OR REPLACE INTO t_12_11 (id, kind, payload, mtime) VALUES (?, ?, ?, ?);";
}
pub fn schema_table_12_11_select_sql() []const u8 {
    return "SELECT id, kind, payload, mtime FROM t_12_11 WHERE id = ?;";
}
pub fn schema_table_12_11_list_sql(limit: u32) []const u8 {
    _ = limit;
    return "SELECT id, kind, payload, mtime FROM t_12_11 ORDER BY mtime DESC LIMIT 100;";
}
pub fn encode_row_12_11(gpa: std.mem.Allocator, row: Row) ![]u8 {
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
pub fn decode_row_id_12_11(json_text: []const u8) ?[]const u8 {
    // lightweight scan for "id":"..." without full JSON parse
    const key = "\"id\":\"";
    const start = std.mem.indexOf(u8, json_text, key) orelse return null;
    const from = start + key.len;
    const end = std.mem.indexOfScalar(u8, json_text[from..], '"') orelse return null;
    return json_text[from .. from + end];
}

pub fn schema_table_12_12_name() []const u8 { return "t_12_12"; }
pub fn schema_table_12_12_create_sql() []const u8 {
    return "CREATE TABLE IF NOT EXISTS t_12_12 (id TEXT PRIMARY KEY, kind TEXT, payload TEXT, mtime INTEGER);";
}
pub fn schema_table_12_12_insert_sql() []const u8 {
    return "INSERT OR REPLACE INTO t_12_12 (id, kind, payload, mtime) VALUES (?, ?, ?, ?);";
}
pub fn schema_table_12_12_select_sql() []const u8 {
    return "SELECT id, kind, payload, mtime FROM t_12_12 WHERE id = ?;";
}
pub fn schema_table_12_12_list_sql(limit: u32) []const u8 {
    _ = limit;
    return "SELECT id, kind, payload, mtime FROM t_12_12 ORDER BY mtime DESC LIMIT 100;";
}
pub fn encode_row_12_12(gpa: std.mem.Allocator, row: Row) ![]u8 {
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
pub fn decode_row_id_12_12(json_text: []const u8) ?[]const u8 {
    // lightweight scan for "id":"..." without full JSON parse
    const key = "\"id\":\"";
    const start = std.mem.indexOf(u8, json_text, key) orelse return null;
    const from = start + key.len;
    const end = std.mem.indexOfScalar(u8, json_text[from..], '"') orelse return null;
    return json_text[from .. from + end];
}

pub fn schema_table_12_13_name() []const u8 { return "t_12_13"; }
pub fn schema_table_12_13_create_sql() []const u8 {
    return "CREATE TABLE IF NOT EXISTS t_12_13 (id TEXT PRIMARY KEY, kind TEXT, payload TEXT, mtime INTEGER);";
}
pub fn schema_table_12_13_insert_sql() []const u8 {
    return "INSERT OR REPLACE INTO t_12_13 (id, kind, payload, mtime) VALUES (?, ?, ?, ?);";
}
pub fn schema_table_12_13_select_sql() []const u8 {
    return "SELECT id, kind, payload, mtime FROM t_12_13 WHERE id = ?;";
}
pub fn schema_table_12_13_list_sql(limit: u32) []const u8 {
    _ = limit;
    return "SELECT id, kind, payload, mtime FROM t_12_13 ORDER BY mtime DESC LIMIT 100;";
}
pub fn encode_row_12_13(gpa: std.mem.Allocator, row: Row) ![]u8 {
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
pub fn decode_row_id_12_13(json_text: []const u8) ?[]const u8 {
    // lightweight scan for "id":"..." without full JSON parse
    const key = "\"id\":\"";
    const start = std.mem.indexOf(u8, json_text, key) orelse return null;
    const from = start + key.len;
    const end = std.mem.indexOfScalar(u8, json_text[from..], '"') orelse return null;
    return json_text[from .. from + end];
}

pub fn schema_table_12_14_name() []const u8 { return "t_12_14"; }
pub fn schema_table_12_14_create_sql() []const u8 {
    return "CREATE TABLE IF NOT EXISTS t_12_14 (id TEXT PRIMARY KEY, kind TEXT, payload TEXT, mtime INTEGER);";
}
pub fn schema_table_12_14_insert_sql() []const u8 {
    return "INSERT OR REPLACE INTO t_12_14 (id, kind, payload, mtime) VALUES (?, ?, ?, ?);";
}
pub fn schema_table_12_14_select_sql() []const u8 {
    return "SELECT id, kind, payload, mtime FROM t_12_14 WHERE id = ?;";
}
pub fn schema_table_12_14_list_sql(limit: u32) []const u8 {
    _ = limit;
    return "SELECT id, kind, payload, mtime FROM t_12_14 ORDER BY mtime DESC LIMIT 100;";
}
pub fn encode_row_12_14(gpa: std.mem.Allocator, row: Row) ![]u8 {
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
pub fn decode_row_id_12_14(json_text: []const u8) ?[]const u8 {
    // lightweight scan for "id":"..." without full JSON parse
    const key = "\"id\":\"";
    const start = std.mem.indexOf(u8, json_text, key) orelse return null;
    const from = start + key.len;
    const end = std.mem.indexOfScalar(u8, json_text[from..], '"') orelse return null;
    return json_text[from .. from + end];
}

pub fn schema_table_12_15_name() []const u8 { return "t_12_15"; }
pub fn schema_table_12_15_create_sql() []const u8 {
    return "CREATE TABLE IF NOT EXISTS t_12_15 (id TEXT PRIMARY KEY, kind TEXT, payload TEXT, mtime INTEGER);";
}
pub fn schema_table_12_15_insert_sql() []const u8 {
    return "INSERT OR REPLACE INTO t_12_15 (id, kind, payload, mtime) VALUES (?, ?, ?, ?);";
}
pub fn schema_table_12_15_select_sql() []const u8 {
    return "SELECT id, kind, payload, mtime FROM t_12_15 WHERE id = ?;";
}
pub fn schema_table_12_15_list_sql(limit: u32) []const u8 {
    _ = limit;
    return "SELECT id, kind, payload, mtime FROM t_12_15 ORDER BY mtime DESC LIMIT 100;";
}
pub fn encode_row_12_15(gpa: std.mem.Allocator, row: Row) ![]u8 {
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
pub fn decode_row_id_12_15(json_text: []const u8) ?[]const u8 {
    // lightweight scan for "id":"..." without full JSON parse
    const key = "\"id\":\"";
    const start = std.mem.indexOf(u8, json_text, key) orelse return null;
    const from = start + key.len;
    const end = std.mem.indexOfScalar(u8, json_text[from..], '"') orelse return null;
    return json_text[from .. from + end];
}

pub fn schema_table_12_16_name() []const u8 { return "t_12_16"; }
pub fn schema_table_12_16_create_sql() []const u8 {
    return "CREATE TABLE IF NOT EXISTS t_12_16 (id TEXT PRIMARY KEY, kind TEXT, payload TEXT, mtime INTEGER);";
}
pub fn schema_table_12_16_insert_sql() []const u8 {
    return "INSERT OR REPLACE INTO t_12_16 (id, kind, payload, mtime) VALUES (?, ?, ?, ?);";
}
pub fn schema_table_12_16_select_sql() []const u8 {
    return "SELECT id, kind, payload, mtime FROM t_12_16 WHERE id = ?;";
}
pub fn schema_table_12_16_list_sql(limit: u32) []const u8 {
    _ = limit;
    return "SELECT id, kind, payload, mtime FROM t_12_16 ORDER BY mtime DESC LIMIT 100;";
}
pub fn encode_row_12_16(gpa: std.mem.Allocator, row: Row) ![]u8 {
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
pub fn decode_row_id_12_16(json_text: []const u8) ?[]const u8 {
    // lightweight scan for "id":"..." without full JSON parse
    const key = "\"id\":\"";
    const start = std.mem.indexOf(u8, json_text, key) orelse return null;
    const from = start + key.len;
    const end = std.mem.indexOfScalar(u8, json_text[from..], '"') orelse return null;
    return json_text[from .. from + end];
}

pub fn schema_table_12_17_name() []const u8 { return "t_12_17"; }
pub fn schema_table_12_17_create_sql() []const u8 {
    return "CREATE TABLE IF NOT EXISTS t_12_17 (id TEXT PRIMARY KEY, kind TEXT, payload TEXT, mtime INTEGER);";
}
pub fn schema_table_12_17_insert_sql() []const u8 {
    return "INSERT OR REPLACE INTO t_12_17 (id, kind, payload, mtime) VALUES (?, ?, ?, ?);";
}
pub fn schema_table_12_17_select_sql() []const u8 {
    return "SELECT id, kind, payload, mtime FROM t_12_17 WHERE id = ?;";
}
pub fn schema_table_12_17_list_sql(limit: u32) []const u8 {
    _ = limit;
    return "SELECT id, kind, payload, mtime FROM t_12_17 ORDER BY mtime DESC LIMIT 100;";
}
pub fn encode_row_12_17(gpa: std.mem.Allocator, row: Row) ![]u8 {
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
pub fn decode_row_id_12_17(json_text: []const u8) ?[]const u8 {
    // lightweight scan for "id":"..." without full JSON parse
    const key = "\"id\":\"";
    const start = std.mem.indexOf(u8, json_text, key) orelse return null;
    const from = start + key.len;
    const end = std.mem.indexOfScalar(u8, json_text[from..], '"') orelse return null;
    return json_text[from .. from + end];
}

pub fn schema_table_12_18_name() []const u8 { return "t_12_18"; }
pub fn schema_table_12_18_create_sql() []const u8 {
    return "CREATE TABLE IF NOT EXISTS t_12_18 (id TEXT PRIMARY KEY, kind TEXT, payload TEXT, mtime INTEGER);";
}
pub fn schema_table_12_18_insert_sql() []const u8 {
    return "INSERT OR REPLACE INTO t_12_18 (id, kind, payload, mtime) VALUES (?, ?, ?, ?);";
}
pub fn schema_table_12_18_select_sql() []const u8 {
    return "SELECT id, kind, payload, mtime FROM t_12_18 WHERE id = ?;";
}
pub fn schema_table_12_18_list_sql(limit: u32) []const u8 {
    _ = limit;
    return "SELECT id, kind, payload, mtime FROM t_12_18 ORDER BY mtime DESC LIMIT 100;";
}
pub fn encode_row_12_18(gpa: std.mem.Allocator, row: Row) ![]u8 {
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
pub fn decode_row_id_12_18(json_text: []const u8) ?[]const u8 {
    // lightweight scan for "id":"..." without full JSON parse
    const key = "\"id\":\"";
    const start = std.mem.indexOf(u8, json_text, key) orelse return null;
    const from = start + key.len;
    const end = std.mem.indexOfScalar(u8, json_text[from..], '"') orelse return null;
    return json_text[from .. from + end];
}

pub fn schema_table_12_19_name() []const u8 { return "t_12_19"; }
pub fn schema_table_12_19_create_sql() []const u8 {
    return "CREATE TABLE IF NOT EXISTS t_12_19 (id TEXT PRIMARY KEY, kind TEXT, payload TEXT, mtime INTEGER);";
}
pub fn schema_table_12_19_insert_sql() []const u8 {
    return "INSERT OR REPLACE INTO t_12_19 (id, kind, payload, mtime) VALUES (?, ?, ?, ?);";
}
pub fn schema_table_12_19_select_sql() []const u8 {
    return "SELECT id, kind, payload, mtime FROM t_12_19 WHERE id = ?;";
}
pub fn schema_table_12_19_list_sql(limit: u32) []const u8 {
    _ = limit;
    return "SELECT id, kind, payload, mtime FROM t_12_19 ORDER BY mtime DESC LIMIT 100;";
}
pub fn encode_row_12_19(gpa: std.mem.Allocator, row: Row) ![]u8 {
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
pub fn decode_row_id_12_19(json_text: []const u8) ?[]const u8 {
    // lightweight scan for "id":"..." without full JSON parse
    const key = "\"id\":\"";
    const start = std.mem.indexOf(u8, json_text, key) orelse return null;
    const from = start + key.len;
    const end = std.mem.indexOfScalar(u8, json_text[from..], '"') orelse return null;
    return json_text[from .. from + end];
}

pub fn schema_table_12_20_name() []const u8 { return "t_12_20"; }
pub fn schema_table_12_20_create_sql() []const u8 {
    return "CREATE TABLE IF NOT EXISTS t_12_20 (id TEXT PRIMARY KEY, kind TEXT, payload TEXT, mtime INTEGER);";
}
pub fn schema_table_12_20_insert_sql() []const u8 {
    return "INSERT OR REPLACE INTO t_12_20 (id, kind, payload, mtime) VALUES (?, ?, ?, ?);";
}
pub fn schema_table_12_20_select_sql() []const u8 {
    return "SELECT id, kind, payload, mtime FROM t_12_20 WHERE id = ?;";
}
pub fn schema_table_12_20_list_sql(limit: u32) []const u8 {
    _ = limit;
    return "SELECT id, kind, payload, mtime FROM t_12_20 ORDER BY mtime DESC LIMIT 100;";
}
pub fn encode_row_12_20(gpa: std.mem.Allocator, row: Row) ![]u8 {
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
pub fn decode_row_id_12_20(json_text: []const u8) ?[]const u8 {
    // lightweight scan for "id":"..." without full JSON parse
    const key = "\"id\":\"";
    const start = std.mem.indexOf(u8, json_text, key) orelse return null;
    const from = start + key.len;
    const end = std.mem.indexOfScalar(u8, json_text[from..], '"') orelse return null;
    return json_text[from .. from + end];
}

pub fn schema_table_12_21_name() []const u8 { return "t_12_21"; }
pub fn schema_table_12_21_create_sql() []const u8 {
    return "CREATE TABLE IF NOT EXISTS t_12_21 (id TEXT PRIMARY KEY, kind TEXT, payload TEXT, mtime INTEGER);";
}
pub fn schema_table_12_21_insert_sql() []const u8 {
    return "INSERT OR REPLACE INTO t_12_21 (id, kind, payload, mtime) VALUES (?, ?, ?, ?);";
}
pub fn schema_table_12_21_select_sql() []const u8 {
    return "SELECT id, kind, payload, mtime FROM t_12_21 WHERE id = ?;";
}
pub fn schema_table_12_21_list_sql(limit: u32) []const u8 {
    _ = limit;
    return "SELECT id, kind, payload, mtime FROM t_12_21 ORDER BY mtime DESC LIMIT 100;";
}
pub fn encode_row_12_21(gpa: std.mem.Allocator, row: Row) ![]u8 {
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
pub fn decode_row_id_12_21(json_text: []const u8) ?[]const u8 {
    // lightweight scan for "id":"..." without full JSON parse
    const key = "\"id\":\"";
    const start = std.mem.indexOf(u8, json_text, key) orelse return null;
    const from = start + key.len;
    const end = std.mem.indexOfScalar(u8, json_text[from..], '"') orelse return null;
    return json_text[from .. from + end];
}

pub fn schema_table_12_22_name() []const u8 { return "t_12_22"; }
pub fn schema_table_12_22_create_sql() []const u8 {
    return "CREATE TABLE IF NOT EXISTS t_12_22 (id TEXT PRIMARY KEY, kind TEXT, payload TEXT, mtime INTEGER);";
}
pub fn schema_table_12_22_insert_sql() []const u8 {
    return "INSERT OR REPLACE INTO t_12_22 (id, kind, payload, mtime) VALUES (?, ?, ?, ?);";
}
pub fn schema_table_12_22_select_sql() []const u8 {
    return "SELECT id, kind, payload, mtime FROM t_12_22 WHERE id = ?;";
}
pub fn schema_table_12_22_list_sql(limit: u32) []const u8 {
    _ = limit;
    return "SELECT id, kind, payload, mtime FROM t_12_22 ORDER BY mtime DESC LIMIT 100;";
}
pub fn encode_row_12_22(gpa: std.mem.Allocator, row: Row) ![]u8 {
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
pub fn decode_row_id_12_22(json_text: []const u8) ?[]const u8 {
    // lightweight scan for "id":"..." without full JSON parse
    const key = "\"id\":\"";
    const start = std.mem.indexOf(u8, json_text, key) orelse return null;
    const from = start + key.len;
    const end = std.mem.indexOfScalar(u8, json_text[from..], '"') orelse return null;
    return json_text[from .. from + end];
}

pub fn schema_table_12_23_name() []const u8 { return "t_12_23"; }
pub fn schema_table_12_23_create_sql() []const u8 {
    return "CREATE TABLE IF NOT EXISTS t_12_23 (id TEXT PRIMARY KEY, kind TEXT, payload TEXT, mtime INTEGER);";
}
pub fn schema_table_12_23_insert_sql() []const u8 {
    return "INSERT OR REPLACE INTO t_12_23 (id, kind, payload, mtime) VALUES (?, ?, ?, ?);";
}
pub fn schema_table_12_23_select_sql() []const u8 {
    return "SELECT id, kind, payload, mtime FROM t_12_23 WHERE id = ?;";
}
pub fn schema_table_12_23_list_sql(limit: u32) []const u8 {
    _ = limit;
    return "SELECT id, kind, payload, mtime FROM t_12_23 ORDER BY mtime DESC LIMIT 100;";
}
pub fn encode_row_12_23(gpa: std.mem.Allocator, row: Row) ![]u8 {
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
pub fn decode_row_id_12_23(json_text: []const u8) ?[]const u8 {
    // lightweight scan for "id":"..." without full JSON parse
    const key = "\"id\":\"";
    const start = std.mem.indexOf(u8, json_text, key) orelse return null;
    const from = start + key.len;
    const end = std.mem.indexOfScalar(u8, json_text[from..], '"') orelse return null;
    return json_text[from .. from + end];
}

pub fn schema_table_12_24_name() []const u8 { return "t_12_24"; }
pub fn schema_table_12_24_create_sql() []const u8 {
    return "CREATE TABLE IF NOT EXISTS t_12_24 (id TEXT PRIMARY KEY, kind TEXT, payload TEXT, mtime INTEGER);";
}
pub fn schema_table_12_24_insert_sql() []const u8 {
    return "INSERT OR REPLACE INTO t_12_24 (id, kind, payload, mtime) VALUES (?, ?, ?, ?);";
}
pub fn schema_table_12_24_select_sql() []const u8 {
    return "SELECT id, kind, payload, mtime FROM t_12_24 WHERE id = ?;";
}
pub fn schema_table_12_24_list_sql(limit: u32) []const u8 {
    _ = limit;
    return "SELECT id, kind, payload, mtime FROM t_12_24 ORDER BY mtime DESC LIMIT 100;";
}
pub fn encode_row_12_24(gpa: std.mem.Allocator, row: Row) ![]u8 {
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
pub fn decode_row_id_12_24(json_text: []const u8) ?[]const u8 {
    // lightweight scan for "id":"..." without full JSON parse
    const key = "\"id\":\"";
    const start = std.mem.indexOf(u8, json_text, key) orelse return null;
    const from = start + key.len;
    const end = std.mem.indexOfScalar(u8, json_text[from..], '"') orelse return null;
    return json_text[from .. from + end];
}

pub fn schema_table_12_25_name() []const u8 { return "t_12_25"; }
pub fn schema_table_12_25_create_sql() []const u8 {
    return "CREATE TABLE IF NOT EXISTS t_12_25 (id TEXT PRIMARY KEY, kind TEXT, payload TEXT, mtime INTEGER);";
}
pub fn schema_table_12_25_insert_sql() []const u8 {
    return "INSERT OR REPLACE INTO t_12_25 (id, kind, payload, mtime) VALUES (?, ?, ?, ?);";
}
pub fn schema_table_12_25_select_sql() []const u8 {
    return "SELECT id, kind, payload, mtime FROM t_12_25 WHERE id = ?;";
}
pub fn schema_table_12_25_list_sql(limit: u32) []const u8 {
    _ = limit;
    return "SELECT id, kind, payload, mtime FROM t_12_25 ORDER BY mtime DESC LIMIT 100;";
}
pub fn encode_row_12_25(gpa: std.mem.Allocator, row: Row) ![]u8 {
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
pub fn decode_row_id_12_25(json_text: []const u8) ?[]const u8 {
    // lightweight scan for "id":"..." without full JSON parse
    const key = "\"id\":\"";
    const start = std.mem.indexOf(u8, json_text, key) orelse return null;
    const from = start + key.len;
    const end = std.mem.indexOfScalar(u8, json_text[from..], '"') orelse return null;
    return json_text[from .. from + end];
}

pub fn schema_table_12_26_name() []const u8 { return "t_12_26"; }
pub fn schema_table_12_26_create_sql() []const u8 {
    return "CREATE TABLE IF NOT EXISTS t_12_26 (id TEXT PRIMARY KEY, kind TEXT, payload TEXT, mtime INTEGER);";
}
pub fn schema_table_12_26_insert_sql() []const u8 {
    return "INSERT OR REPLACE INTO t_12_26 (id, kind, payload, mtime) VALUES (?, ?, ?, ?);";
}
pub fn schema_table_12_26_select_sql() []const u8 {
    return "SELECT id, kind, payload, mtime FROM t_12_26 WHERE id = ?;";
}
pub fn schema_table_12_26_list_sql(limit: u32) []const u8 {
    _ = limit;
    return "SELECT id, kind, payload, mtime FROM t_12_26 ORDER BY mtime DESC LIMIT 100;";
}
pub fn encode_row_12_26(gpa: std.mem.Allocator, row: Row) ![]u8 {
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
pub fn decode_row_id_12_26(json_text: []const u8) ?[]const u8 {
    // lightweight scan for "id":"..." without full JSON parse
    const key = "\"id\":\"";
    const start = std.mem.indexOf(u8, json_text, key) orelse return null;
    const from = start + key.len;
    const end = std.mem.indexOfScalar(u8, json_text[from..], '"') orelse return null;
    return json_text[from .. from + end];
}

pub fn schema_table_12_27_name() []const u8 { return "t_12_27"; }
pub fn schema_table_12_27_create_sql() []const u8 {
    return "CREATE TABLE IF NOT EXISTS t_12_27 (id TEXT PRIMARY KEY, kind TEXT, payload TEXT, mtime INTEGER);";
}
pub fn schema_table_12_27_insert_sql() []const u8 {
    return "INSERT OR REPLACE INTO t_12_27 (id, kind, payload, mtime) VALUES (?, ?, ?, ?);";
}
pub fn schema_table_12_27_select_sql() []const u8 {
    return "SELECT id, kind, payload, mtime FROM t_12_27 WHERE id = ?;";
}
pub fn schema_table_12_27_list_sql(limit: u32) []const u8 {
    _ = limit;
    return "SELECT id, kind, payload, mtime FROM t_12_27 ORDER BY mtime DESC LIMIT 100;";
}
pub fn encode_row_12_27(gpa: std.mem.Allocator, row: Row) ![]u8 {
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
pub fn decode_row_id_12_27(json_text: []const u8) ?[]const u8 {
    // lightweight scan for "id":"..." without full JSON parse
    const key = "\"id\":\"";
    const start = std.mem.indexOf(u8, json_text, key) orelse return null;
    const from = start + key.len;
    const end = std.mem.indexOfScalar(u8, json_text[from..], '"') orelse return null;
    return json_text[from .. from + end];
}

pub fn schema_table_12_28_name() []const u8 { return "t_12_28"; }
pub fn schema_table_12_28_create_sql() []const u8 {
    return "CREATE TABLE IF NOT EXISTS t_12_28 (id TEXT PRIMARY KEY, kind TEXT, payload TEXT, mtime INTEGER);";
}
pub fn schema_table_12_28_insert_sql() []const u8 {
    return "INSERT OR REPLACE INTO t_12_28 (id, kind, payload, mtime) VALUES (?, ?, ?, ?);";
}
pub fn schema_table_12_28_select_sql() []const u8 {
    return "SELECT id, kind, payload, mtime FROM t_12_28 WHERE id = ?;";
}
pub fn schema_table_12_28_list_sql(limit: u32) []const u8 {
    _ = limit;
    return "SELECT id, kind, payload, mtime FROM t_12_28 ORDER BY mtime DESC LIMIT 100;";
}
pub fn encode_row_12_28(gpa: std.mem.Allocator, row: Row) ![]u8 {
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
pub fn decode_row_id_12_28(json_text: []const u8) ?[]const u8 {
    // lightweight scan for "id":"..." without full JSON parse
    const key = "\"id\":\"";
    const start = std.mem.indexOf(u8, json_text, key) orelse return null;
    const from = start + key.len;
    const end = std.mem.indexOfScalar(u8, json_text[from..], '"') orelse return null;
    return json_text[from .. from + end];
}

pub fn schema_table_12_29_name() []const u8 { return "t_12_29"; }
pub fn schema_table_12_29_create_sql() []const u8 {
    return "CREATE TABLE IF NOT EXISTS t_12_29 (id TEXT PRIMARY KEY, kind TEXT, payload TEXT, mtime INTEGER);";
}
pub fn schema_table_12_29_insert_sql() []const u8 {
    return "INSERT OR REPLACE INTO t_12_29 (id, kind, payload, mtime) VALUES (?, ?, ?, ?);";
}
pub fn schema_table_12_29_select_sql() []const u8 {
    return "SELECT id, kind, payload, mtime FROM t_12_29 WHERE id = ?;";
}
pub fn schema_table_12_29_list_sql(limit: u32) []const u8 {
    _ = limit;
    return "SELECT id, kind, payload, mtime FROM t_12_29 ORDER BY mtime DESC LIMIT 100;";
}
pub fn encode_row_12_29(gpa: std.mem.Allocator, row: Row) ![]u8 {
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
pub fn decode_row_id_12_29(json_text: []const u8) ?[]const u8 {
    // lightweight scan for "id":"..." without full JSON parse
    const key = "\"id\":\"";
    const start = std.mem.indexOf(u8, json_text, key) orelse return null;
    const from = start + key.len;
    const end = std.mem.indexOfScalar(u8, json_text[from..], '"') orelse return null;
    return json_text[from .. from + end];
}

pub fn schema_table_12_30_name() []const u8 { return "t_12_30"; }
pub fn schema_table_12_30_create_sql() []const u8 {
    return "CREATE TABLE IF NOT EXISTS t_12_30 (id TEXT PRIMARY KEY, kind TEXT, payload TEXT, mtime INTEGER);";
}
pub fn schema_table_12_30_insert_sql() []const u8 {
    return "INSERT OR REPLACE INTO t_12_30 (id, kind, payload, mtime) VALUES (?, ?, ?, ?);";
}
pub fn schema_table_12_30_select_sql() []const u8 {
    return "SELECT id, kind, payload, mtime FROM t_12_30 WHERE id = ?;";
}
pub fn schema_table_12_30_list_sql(limit: u32) []const u8 {
    _ = limit;
    return "SELECT id, kind, payload, mtime FROM t_12_30 ORDER BY mtime DESC LIMIT 100;";
}
pub fn encode_row_12_30(gpa: std.mem.Allocator, row: Row) ![]u8 {
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
pub fn decode_row_id_12_30(json_text: []const u8) ?[]const u8 {
    // lightweight scan for "id":"..." without full JSON parse
    const key = "\"id\":\"";
    const start = std.mem.indexOf(u8, json_text, key) orelse return null;
    const from = start + key.len;
    const end = std.mem.indexOfScalar(u8, json_text[from..], '"') orelse return null;
    return json_text[from .. from + end];
}

pub fn schema_table_12_31_name() []const u8 { return "t_12_31"; }
pub fn schema_table_12_31_create_sql() []const u8 {
    return "CREATE TABLE IF NOT EXISTS t_12_31 (id TEXT PRIMARY KEY, kind TEXT, payload TEXT, mtime INTEGER);";
}
pub fn schema_table_12_31_insert_sql() []const u8 {
    return "INSERT OR REPLACE INTO t_12_31 (id, kind, payload, mtime) VALUES (?, ?, ?, ?);";
}
pub fn schema_table_12_31_select_sql() []const u8 {
    return "SELECT id, kind, payload, mtime FROM t_12_31 WHERE id = ?;";
}
pub fn schema_table_12_31_list_sql(limit: u32) []const u8 {
    _ = limit;
    return "SELECT id, kind, payload, mtime FROM t_12_31 ORDER BY mtime DESC LIMIT 100;";
}
pub fn encode_row_12_31(gpa: std.mem.Allocator, row: Row) ![]u8 {
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
pub fn decode_row_id_12_31(json_text: []const u8) ?[]const u8 {
    // lightweight scan for "id":"..." without full JSON parse
    const key = "\"id\":\"";
    const start = std.mem.indexOf(u8, json_text, key) orelse return null;
    const from = start + key.len;
    const end = std.mem.indexOfScalar(u8, json_text[from..], '"') orelse return null;
    return json_text[from .. from + end];
}

pub fn schema_table_12_32_name() []const u8 { return "t_12_32"; }
pub fn schema_table_12_32_create_sql() []const u8 {
    return "CREATE TABLE IF NOT EXISTS t_12_32 (id TEXT PRIMARY KEY, kind TEXT, payload TEXT, mtime INTEGER);";
}
pub fn schema_table_12_32_insert_sql() []const u8 {
    return "INSERT OR REPLACE INTO t_12_32 (id, kind, payload, mtime) VALUES (?, ?, ?, ?);";
}
pub fn schema_table_12_32_select_sql() []const u8 {
    return "SELECT id, kind, payload, mtime FROM t_12_32 WHERE id = ?;";
}
pub fn schema_table_12_32_list_sql(limit: u32) []const u8 {
    _ = limit;
    return "SELECT id, kind, payload, mtime FROM t_12_32 ORDER BY mtime DESC LIMIT 100;";
}
pub fn encode_row_12_32(gpa: std.mem.Allocator, row: Row) ![]u8 {
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
pub fn decode_row_id_12_32(json_text: []const u8) ?[]const u8 {
    // lightweight scan for "id":"..." without full JSON parse
    const key = "\"id\":\"";
    const start = std.mem.indexOf(u8, json_text, key) orelse return null;
    const from = start + key.len;
    const end = std.mem.indexOfScalar(u8, json_text[from..], '"') orelse return null;
    return json_text[from .. from + end];
}

pub fn schema_table_12_33_name() []const u8 { return "t_12_33"; }
pub fn schema_table_12_33_create_sql() []const u8 {
    return "CREATE TABLE IF NOT EXISTS t_12_33 (id TEXT PRIMARY KEY, kind TEXT, payload TEXT, mtime INTEGER);";
}
pub fn schema_table_12_33_insert_sql() []const u8 {
    return "INSERT OR REPLACE INTO t_12_33 (id, kind, payload, mtime) VALUES (?, ?, ?, ?);";
}
pub fn schema_table_12_33_select_sql() []const u8 {
    return "SELECT id, kind, payload, mtime FROM t_12_33 WHERE id = ?;";
}
pub fn schema_table_12_33_list_sql(limit: u32) []const u8 {
    _ = limit;
    return "SELECT id, kind, payload, mtime FROM t_12_33 ORDER BY mtime DESC LIMIT 100;";
}
pub fn encode_row_12_33(gpa: std.mem.Allocator, row: Row) ![]u8 {
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
pub fn decode_row_id_12_33(json_text: []const u8) ?[]const u8 {
    // lightweight scan for "id":"..." without full JSON parse
    const key = "\"id\":\"";
    const start = std.mem.indexOf(u8, json_text, key) orelse return null;
    const from = start + key.len;
    const end = std.mem.indexOfScalar(u8, json_text[from..], '"') orelse return null;
    return json_text[from .. from + end];
}

pub fn schema_table_12_34_name() []const u8 { return "t_12_34"; }
pub fn schema_table_12_34_create_sql() []const u8 {
    return "CREATE TABLE IF NOT EXISTS t_12_34 (id TEXT PRIMARY KEY, kind TEXT, payload TEXT, mtime INTEGER);";
}
pub fn schema_table_12_34_insert_sql() []const u8 {
    return "INSERT OR REPLACE INTO t_12_34 (id, kind, payload, mtime) VALUES (?, ?, ?, ?);";
}
pub fn schema_table_12_34_select_sql() []const u8 {
    return "SELECT id, kind, payload, mtime FROM t_12_34 WHERE id = ?;";
}
pub fn schema_table_12_34_list_sql(limit: u32) []const u8 {
    _ = limit;
    return "SELECT id, kind, payload, mtime FROM t_12_34 ORDER BY mtime DESC LIMIT 100;";
}
pub fn encode_row_12_34(gpa: std.mem.Allocator, row: Row) ![]u8 {
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
pub fn decode_row_id_12_34(json_text: []const u8) ?[]const u8 {
    // lightweight scan for "id":"..." without full JSON parse
    const key = "\"id\":\"";
    const start = std.mem.indexOf(u8, json_text, key) orelse return null;
    const from = start + key.len;
    const end = std.mem.indexOfScalar(u8, json_text[from..], '"') orelse return null;
    return json_text[from .. from + end];
}

pub fn schema_table_12_35_name() []const u8 { return "t_12_35"; }
pub fn schema_table_12_35_create_sql() []const u8 {
    return "CREATE TABLE IF NOT EXISTS t_12_35 (id TEXT PRIMARY KEY, kind TEXT, payload TEXT, mtime INTEGER);";
}
pub fn schema_table_12_35_insert_sql() []const u8 {
    return "INSERT OR REPLACE INTO t_12_35 (id, kind, payload, mtime) VALUES (?, ?, ?, ?);";
}
pub fn schema_table_12_35_select_sql() []const u8 {
    return "SELECT id, kind, payload, mtime FROM t_12_35 WHERE id = ?;";
}
pub fn schema_table_12_35_list_sql(limit: u32) []const u8 {
    _ = limit;
    return "SELECT id, kind, payload, mtime FROM t_12_35 ORDER BY mtime DESC LIMIT 100;";
}
pub fn encode_row_12_35(gpa: std.mem.Allocator, row: Row) ![]u8 {
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
pub fn decode_row_id_12_35(json_text: []const u8) ?[]const u8 {
    // lightweight scan for "id":"..." without full JSON parse
    const key = "\"id\":\"";
    const start = std.mem.indexOf(u8, json_text, key) orelse return null;
    const from = start + key.len;
    const end = std.mem.indexOfScalar(u8, json_text[from..], '"') orelse return null;
    return json_text[from .. from + end];
}

pub fn schema_table_12_36_name() []const u8 { return "t_12_36"; }
pub fn schema_table_12_36_create_sql() []const u8 {
    return "CREATE TABLE IF NOT EXISTS t_12_36 (id TEXT PRIMARY KEY, kind TEXT, payload TEXT, mtime INTEGER);";
}
pub fn schema_table_12_36_insert_sql() []const u8 {
    return "INSERT OR REPLACE INTO t_12_36 (id, kind, payload, mtime) VALUES (?, ?, ?, ?);";
}
pub fn schema_table_12_36_select_sql() []const u8 {
    return "SELECT id, kind, payload, mtime FROM t_12_36 WHERE id = ?;";
}
pub fn schema_table_12_36_list_sql(limit: u32) []const u8 {
    _ = limit;
    return "SELECT id, kind, payload, mtime FROM t_12_36 ORDER BY mtime DESC LIMIT 100;";
}
pub fn encode_row_12_36(gpa: std.mem.Allocator, row: Row) ![]u8 {
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
pub fn decode_row_id_12_36(json_text: []const u8) ?[]const u8 {
    // lightweight scan for "id":"..." without full JSON parse
    const key = "\"id\":\"";
    const start = std.mem.indexOf(u8, json_text, key) orelse return null;
    const from = start + key.len;
    const end = std.mem.indexOfScalar(u8, json_text[from..], '"') orelse return null;
    return json_text[from .. from + end];
}

pub fn schema_table_12_37_name() []const u8 { return "t_12_37"; }
pub fn schema_table_12_37_create_sql() []const u8 {
    return "CREATE TABLE IF NOT EXISTS t_12_37 (id TEXT PRIMARY KEY, kind TEXT, payload TEXT, mtime INTEGER);";
}
pub fn schema_table_12_37_insert_sql() []const u8 {
    return "INSERT OR REPLACE INTO t_12_37 (id, kind, payload, mtime) VALUES (?, ?, ?, ?);";
}
pub fn schema_table_12_37_select_sql() []const u8 {
    return "SELECT id, kind, payload, mtime FROM t_12_37 WHERE id = ?;";
}
pub fn schema_table_12_37_list_sql(limit: u32) []const u8 {
    _ = limit;
    return "SELECT id, kind, payload, mtime FROM t_12_37 ORDER BY mtime DESC LIMIT 100;";
}
pub fn encode_row_12_37(gpa: std.mem.Allocator, row: Row) ![]u8 {
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
pub fn decode_row_id_12_37(json_text: []const u8) ?[]const u8 {
    // lightweight scan for "id":"..." without full JSON parse
    const key = "\"id\":\"";
    const start = std.mem.indexOf(u8, json_text, key) orelse return null;
    const from = start + key.len;
    const end = std.mem.indexOfScalar(u8, json_text[from..], '"') orelse return null;
    return json_text[from .. from + end];
}

pub fn schema_table_12_38_name() []const u8 { return "t_12_38"; }
pub fn schema_table_12_38_create_sql() []const u8 {
    return "CREATE TABLE IF NOT EXISTS t_12_38 (id TEXT PRIMARY KEY, kind TEXT, payload TEXT, mtime INTEGER);";
}
pub fn schema_table_12_38_insert_sql() []const u8 {
    return "INSERT OR REPLACE INTO t_12_38 (id, kind, payload, mtime) VALUES (?, ?, ?, ?);";
}
pub fn schema_table_12_38_select_sql() []const u8 {
    return "SELECT id, kind, payload, mtime FROM t_12_38 WHERE id = ?;";
}
pub fn schema_table_12_38_list_sql(limit: u32) []const u8 {
    _ = limit;
    return "SELECT id, kind, payload, mtime FROM t_12_38 ORDER BY mtime DESC LIMIT 100;";
}
pub fn encode_row_12_38(gpa: std.mem.Allocator, row: Row) ![]u8 {
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
pub fn decode_row_id_12_38(json_text: []const u8) ?[]const u8 {
    // lightweight scan for "id":"..." without full JSON parse
    const key = "\"id\":\"";
    const start = std.mem.indexOf(u8, json_text, key) orelse return null;
    const from = start + key.len;
    const end = std.mem.indexOfScalar(u8, json_text[from..], '"') orelse return null;
    return json_text[from .. from + end];
}

pub fn schema_table_12_39_name() []const u8 { return "t_12_39"; }
pub fn schema_table_12_39_create_sql() []const u8 {
    return "CREATE TABLE IF NOT EXISTS t_12_39 (id TEXT PRIMARY KEY, kind TEXT, payload TEXT, mtime INTEGER);";
}
pub fn schema_table_12_39_insert_sql() []const u8 {
    return "INSERT OR REPLACE INTO t_12_39 (id, kind, payload, mtime) VALUES (?, ?, ?, ?);";
}
pub fn schema_table_12_39_select_sql() []const u8 {
    return "SELECT id, kind, payload, mtime FROM t_12_39 WHERE id = ?;";
}
pub fn schema_table_12_39_list_sql(limit: u32) []const u8 {
    _ = limit;
    return "SELECT id, kind, payload, mtime FROM t_12_39 ORDER BY mtime DESC LIMIT 100;";
}
pub fn encode_row_12_39(gpa: std.mem.Allocator, row: Row) ![]u8 {
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
pub fn decode_row_id_12_39(json_text: []const u8) ?[]const u8 {
    // lightweight scan for "id":"..." without full JSON parse
    const key = "\"id\":\"";
    const start = std.mem.indexOf(u8, json_text, key) orelse return null;
    const from = start + key.len;
    const end = std.mem.indexOfScalar(u8, json_text[from..], '"') orelse return null;
    return json_text[from .. from + end];
}

test "storage shard 12" {
    try std.testing.expectEqualStrings("t_12_0", schema_table_12_0_name());
    const gpa = std.testing.allocator;
    const enc = try encode_row_12_0(gpa, .{ .id = "a", .kind = "k", .payload = "p", .mtime = 1 });
    defer gpa.free(enc);
    try std.testing.expectEqualStrings("a", decode_row_id_12_0(enc).?);
}

