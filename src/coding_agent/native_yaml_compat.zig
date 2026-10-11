//! Source461/481/489 prove literal NUL, raw UTF16 halves and surrogate escapes inside a
//! double-quoted scalar are accepted by yaml2.9.0. libfyaml rejects them. This adapter changes
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
    var diagnostic: c.pi_yaml_error = undefined;
    if (c.pi_yaml_error_get(original, &diagnostic) <= 0) return .{ .document = original, .parse_input = input };
    var positions: std.ArrayList(usize) = .empty;
    defer positions.deinit(allocator);
    // Find only same-width replacements. Their lexical role is deliberately
    // not guessed here: the accepted AST must cover every changed byte with
    // a double-quoted scalar before original scalar decoding can run.
    var index: usize = 0;
    while (index < input.len) : (index += 1) {
        if (input[index] == 0) {
            try positions.append(allocator, index);
        } else if (index + 2 < input.len and input[index] == 0xed and input[index + 1] >= 0xa0 and input[index + 1] <= 0xbf and input[index + 2] >= 0x80 and input[index + 2] <= 0xbf) {
            // Lossless JS strings use WTF8 for an isolated UTF16 unit. The
            // temporary grammar bytes retain its exact byte width.
            for (0..3) |byte| try positions.append(allocator, index + byte);
            index += 2;
        } else if (surrogateEscape(input[index..])) |digits| {
            for (0..digits) |digit| try positions.append(allocator, index + 2 + digit);
            index += digits + 1;
        }
    }
    if (positions.items.len == 0) return .{ .document = original, .parse_input = input };
    const temporary = try allocator.dupe(u8, input);
    for (positions.items) |position| temporary[position] = if (input[position] == 0) 'X' else '0';
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
fn surrogateEscape(input: []const u8) ?usize {
    if (input.len < 2 or input[0] != '\\') return null;
    const count: usize = if (input[1] == 'u') 4 else if (input[1] == 'U') 8 else return null;
    if (input.len < count + 2) return null;
    var point: u32 = 0;
    for (input[2 .. count + 2]) |byte| {
        const digit = std.fmt.charToDigit(byte, 16) catch return null;
        point = (point << 4) | digit;
    }
    return if (point >= 0xd800 and point <= 0xdfff) count else null;
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
