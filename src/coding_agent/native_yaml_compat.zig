//! Source461 proves literal NUL inside a double-quoted scalar is accepted by
//! yaml2.9.0. libfyaml treats it as end of scalar. The grammar adapter changes
//! only same-width temporary parse bytes, verifies each change lies in an
//! actual quoted scalar AST node, and decodes that node from original bytes.
//! Unrelated syntax, anchor names and the original input are never rewritten.
const std = @import("std");
pub fn Prepared(comptime c: type) type {
    return struct { document: *c.pi_yaml_document, parse_input: []const u8 };
}
pub fn prepare(comptime c: type, allocator: std.mem.Allocator, input: []const u8) !Prepared(c) {
    const original = c.pi_yaml_parse(input.ptr, input.len) orelse return error.OutOfMemory;
    errdefer c.pi_yaml_destroy(original);
    if (std.mem.indexOfScalar(u8, input, 0) == null) return .{ .document = original, .parse_input = input };
    var diagnostic: c.pi_yaml_error = undefined;
    if (c.pi_yaml_error_get(original, &diagnostic) <= 0) return .{ .document = original, .parse_input = input };
    const temporary = try allocator.dupe(u8, input);
    var positions: std.ArrayList(usize) = .empty;
    defer positions.deinit(allocator);
    for (temporary, 0..) |*byte, index| if (byte.* == 0) {
        byte.* = 'X';
        try positions.append(allocator, index);
    };
    const adapted = c.pi_yaml_parse(temporary.ptr, temporary.len) orelse return error.OutOfMemory;
    var accepted = false;
    defer if (!accepted) c.pi_yaml_destroy(adapted);
    if (c.pi_yaml_error_get(adapted, &diagnostic) != 0) return .{ .document = original, .parse_input = input };
    const covered = try allocator.alloc(bool, positions.items.len);
    defer allocator.free(covered);
    @memset(covered, false);
    cover(c, c.pi_yaml_root(adapted), positions.items, covered);
    for (covered) |value| if (!value) return .{ .document = original, .parse_input = input };
    accepted = true;
    c.pi_yaml_destroy(original);
    return .{ .document = adapted, .parse_input = temporary };
}
fn cover(comptime c: type, maybe: ?*c.pi_yaml_node, positions: []const usize, covered: []bool) void {
    const node = maybe orelse return;
    if (c.pi_yaml_kind(node) == 0 and c.pi_yaml_double_quoted(node) != 0) {
        const start = c.pi_yaml_offset(node);
        const end = c.pi_yaml_end(node);
        for (positions, covered) |position, *matched| if (position > start and position < end) {
            matched.* = true;
        };
    }
    var iterator: ?*anyopaque = null;
    if (c.pi_yaml_kind(node) == 1) {
        while (c.pi_yaml_sequence_next(node, &iterator)) |child| cover(c, child, positions, covered);
    } else if (c.pi_yaml_kind(node) == 2) {
        var key: ?*c.pi_yaml_node = null;
        var value: ?*c.pi_yaml_node = null;
        while (c.pi_yaml_mapping_next(node, &iterator, &key, &value) != 0) {
            cover(c, key, positions, covered);
            cover(c, value, positions, covered);
        }
    }
}
