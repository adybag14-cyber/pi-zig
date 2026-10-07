//! Source-compatible WWW-Authenticate fields owned by the native connection.
const std = @import("std");
const json = @import("protocol.zig").json;
const urls = @import("../extensions/url_parser.zig");
fn whitespace(byte: u8) bool {
    return std.mem.indexOfScalar(u8, " \t\r\n\x0b\x0c", byte) != null;
}
fn field(header: []const u8, name: []const u8) ?[]const u8 {
    for (0..header.len) |index| {
        if (index != 0 and header[index - 1] != ',' and !whitespace(header[index - 1])) continue;
        if (header.len - index < name.len + 1 or !std.ascii.eqlIgnoreCase(header[index..][0..name.len], name) or header[index + name.len] != '=') continue;
        const value = header[index + name.len + 1 ..];
        if (value.len == 0) continue;
        if (value[0] == '"') {
            const end = std.mem.indexOfScalar(u8, value[1..], '"') orelse continue;
            if (end == 0) return null;
            return value[1..][0..end];
        }
        var end: usize = 0;
        while (end < value.len and value[end] != ',' and !whitespace(value[end])) end += 1;
        if (end != 0) return value[0..end];
    }
    return null;
}
pub fn parse(gpa: std.mem.Allocator, header: ?[]const u8) !json.Owned {
    var result = try json.Owned.empty(gpa);
    errdefer result.deinit();
    result.value = .{ .object = .empty };
    const raw = header orelse return result;
    const trimmed = std.mem.trimStart(u8, raw, " \t\r\n\x0b\x0c");
    var end: usize = 0;
    while (end < trimmed.len and !whitespace(trimmed[end])) end += 1;
    if (!std.ascii.eqlIgnoreCase(trimmed[0..end], "bearer") and !std.ascii.eqlIgnoreCase(trimmed[0..end], "dpop")) return result;
    const a = result.arena.allocator();
    for ([_]struct { input: []const u8, output: []const u8 }{ .{ .input = "scope", .output = "scope" }, .{ .input = "error", .output = "error" }, .{ .input = "error_description", .output = "errorDescription" } }) |item| if (field(raw, item.input)) |value| {
        try result.value.object.put(a, item.output, .{ .string = try a.dupe(u8, value) });
    };
    if (field(raw, "resource_metadata")) |value| {
        if (urls.parse(gpa, value, null)) |parsed_value| {
            var parsed = parsed_value;
            defer parsed.deinit(gpa);
            const normalized = try urls.serialize(gpa, parsed);
            defer gpa.free(normalized);
            try result.value.object.put(a, "resourceMetadataUrl", .{ .string = try a.dupe(u8, normalized) });
        } else |cause| if (cause == error.OutOfMemory) return cause;
    }
    return result;
}

test "mcp.runtime OAuth challenge parser matches actual original cases including quoted boundary quirks" {
    const gpa = std.testing.allocator;
    var original = try json.Owned.parse(gpa, @embedFile("fixtures/oauth-challenge-7fb.json"));
    defer original.deinit();
    for (original.value.array.items) |row| {
        const header = json.get(row, "header").?;
        var result = try parse(gpa, if (header == .null) null else try json.asString(header));
        defer result.deinit();
        try std.testing.expect(json.equal(json.get(row, "result").?, result.value));
    }
}
