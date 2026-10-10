//! JavaScript object-key order for language-neutral provider JSON projections.
const std = @import("std");

pub fn arrayIndex(key: []const u8) ?u32 {
    if (key.len == 0 or (key.len > 1 and key[0] == '0')) return null;
    for (key) |byte| if (byte < '0' or byte > '9') return null;
    const index = std.fmt.parseInt(u32, key, 10) catch return null;
    return if (index == std.math.maxInt(u32)) null else index;
}

fn less(_: void, left: []const u8, right: []const u8) bool {
    return arrayIndex(left).? < arrayIndex(right).?;
}

/// The array is owned; strings remain borrowed from the input map.
pub fn keys(gpa: std.mem.Allocator, map: std.json.ObjectMap) ![][]const u8 {
    const output = try gpa.alloc([]const u8, map.count());
    var indices: usize = 0;
    var iterator = map.iterator();
    while (iterator.next()) |entry| if (arrayIndex(entry.key_ptr.*) != null) {
        output[indices] = entry.key_ptr.*;
        indices += 1;
    };
    std.mem.sort([]const u8, output[0..indices], {}, less);
    var offset = indices;
    iterator = map.iterator();
    while (iterator.next()) |entry| if (arrayIndex(entry.key_ptr.*) == null) {
        output[offset] = entry.key_ptr.*;
        offset += 1;
    };
    return output;
}

/// Ordered structural copy for prompt serialization. The caller uses an arena;
/// scalar strings stay borrowed from the parsed context owned by that arena.
pub fn copy(gpa: std.mem.Allocator, value: std.json.Value) anyerror!std.json.Value {
    switch (value) {
        .object => |map| {
            var output: std.json.ObjectMap = .empty;
            for (try keys(gpa, map)) |key| try output.put(gpa, key, try copy(gpa, map.get(key).?));
            return .{ .object = output };
        },
        .array => |items| {
            var output: std.json.Array = .init(gpa);
            for (items.items) |item| try output.append(try copy(gpa, item));
            return .{ .array = output };
        },
        else => return value,
    }
}

test "classifier JSON ordering handles integer names zero padding and uint32 boundary" {
    const gpa = std.testing.allocator;
    var map: std.json.ObjectMap = .empty;
    defer map.deinit(gpa);
    for ([_][]const u8{ "other", "2", "01", "0", "4294967295", "1", "__proto__", "4294967294" }) |key| try map.put(gpa, key, .null);
    const ordered = try keys(gpa, map);
    defer gpa.free(ordered);
    const expected = [_][]const u8{ "0", "1", "2", "4294967294", "other", "01", "4294967295", "__proto__" };
    for (ordered, expected) |actual, wanted| try std.testing.expectEqualStrings(wanted, actual);
}
