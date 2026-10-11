//! Rust String::from_utf8_lossy semantics for the macOS proc_name byte buffer.
const std = @import("std");
pub fn convert(gpa: std.mem.Allocator, bytes: []const u8) ![]u8 {
    var output: std.ArrayList(u8) = .empty;
    errdefer output.deinit(gpa);
    var offset: usize = 0;
    while (offset < bytes.len) {
        const lead = bytes[offset];
        if (lead < 0x80) {
            try output.append(gpa, lead);
            offset += 1;
            continue;
        }
        const needed: usize = if (lead >= 0xc2 and lead <= 0xdf) 2 else if (lead >= 0xe0 and lead <= 0xef) 3 else if (lead >= 0xf0 and lead <= 0xf4) 4 else 0;
        var prefix: usize = 1;
        while (prefix < needed and offset + prefix < bytes.len) : (prefix += 1) {
            const byte = bytes[offset + prefix];
            if (byte < 0x80 or byte > 0xbf) break;
            if (prefix == 1) {
                if ((lead == 0xe0 and byte < 0xa0) or (lead == 0xed and byte > 0x9f) or (lead == 0xf0 and byte < 0x90) or (lead == 0xf4 and byte > 0x8f)) break;
            }
        }
        if (needed != 0 and prefix == needed) {
            try output.appendSlice(gpa, bytes[offset .. offset + needed]);
        } else try output.appendSlice(gpa, "\xef\xbf\xbd");
        offset += prefix;
    }
    return output.toOwnedSlice(gpa);
}
test "native macOS terminal names match exhaustive short and boundary Rust lossy UTF8 captures" {
    const gpa = std.testing.allocator;
    var captured = try std.json.parseFromSlice(std.json.Value, gpa, @embedFile("fixtures/utf8-lossy-rust-source.json"), .{});
    defer captured.deinit();
    for (captured.value.object.get("cases").?.array.items) |row| {
        var input: [4]u8 = undefined;
        var expected: [12]u8 = undefined;
        const bytes = try std.fmt.hexToBytes(&input, row.array.items[0].string);
        const value = try convert(gpa, bytes);
        defer gpa.free(value);
        try std.testing.expectEqualStrings(try std.fmt.hexToBytes(&expected, row.array.items[1].string), value);
    }
}
