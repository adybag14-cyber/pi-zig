//! Exact upstream frontmatter extraction followed by full YAML validation.
const std = @import("std");
pub const yaml = @import("native_yaml.zig");
pub const Parsed = struct {
    allocator: std.mem.Allocator,
    normalized: []u8,
    body: []const u8,
    yaml_source: ?[]const u8,
    frontmatter: yaml.Owned,
    pub fn deinit(self: *Parsed) void {
        self.frontmatter.deinit();
        self.allocator.free(self.normalized);
        self.* = undefined;
    }
};
pub fn whitespace(scalar: u21) bool {
    return switch (scalar) {
        0x09...0x0d, 0x20, 0xa0, 0x1680, 0x2000...0x200a, 0x2028, 0x2029, 0x202f, 0x205f, 0x3000, 0xfeff => true,
        else => false,
    };
}
pub fn trim(input: []const u8) []const u8 {
    var first: ?usize = null;
    var end: usize = 0;
    var index: usize = 0;
    while (index < input.len) {
        const count = std.unicode.utf8ByteSequenceLength(input[index]) catch 1;
        const limit = @min(input.len, index + count);
        const scalar = std.unicode.utf8Decode(input[index..limit]) catch input[index];
        if (!whitespace(scalar)) {
            if (first == null) first = index;
            end = limit;
        }
        index = limit;
    }
    return input[first orelse input.len .. endOfTrim(first, end, input.len)];
}
fn endOfTrim(first: ?usize, end: usize, length: usize) usize {
    return if (first == null) length else end;
}
pub fn parse(allocator: std.mem.Allocator, input: []const u8) !Parsed {
    var normalized: std.ArrayList(u8) = .empty;
    errdefer normalized.deinit(allocator);
    const bytes = if (std.mem.startsWith(u8, input, "\xef\xbb\xbf")) input[3..] else input;
    var index: usize = 0;
    while (index < bytes.len) : (index += 1) {
        if (bytes[index] == '\r') {
            try normalized.append(allocator, '\n');
            if (index + 1 < bytes.len and bytes[index + 1] == '\n') index += 1;
        } else try normalized.append(allocator, bytes[index]);
    }
    const content = try normalized.toOwnedSlice(allocator);
    errdefer allocator.free(content);
    var body: []const u8 = content;
    var source: ?[]const u8 = null;
    if (std.mem.startsWith(u8, content, "---")) {
        if (std.mem.indexOfPos(u8, content, 3, "\n---")) |closing| {
            // JS slice(4,3) is empty when adjacent fence lines meet.
            source = content[@min(4, closing)..closing];
            body = trim(content[closing + 4 ..]);
        }
    }
    const parsed = try yaml.parse(allocator, source orelse "");
    // parseFrontmatter returns {} for absent/empty YAML and parsed null, but
    // preserves scalar false/zero, sequences and every non-null value.
    if (parsed.root) |root| {
        if (root.data == .null) root.data = .{ .mapping = &.{} };
    }
    return .{ .allocator = allocator, .normalized = content, .body = body, .yaml_source = source, .frontmatter = parsed };
}
pub fn strip(allocator: std.mem.Allocator, input: []const u8) ![]u8 {
    var parsed = try parse(allocator, input);
    defer parsed.deinit();
    if (parsed.frontmatter.diagnostic != null) return error.InvalidYaml;
    return allocator.dupe(u8, parsed.body);
}

/// yaml2.9.0 errors.js: location plus one source line and previous line when
/// the pointer lies in the indentation. Source lines count UTF16 code units.
pub fn pretty(allocator: std.mem.Allocator, source: []const u8, diagnostic: yaml.Diagnostic) ![]u8 {
    const units = try prettyUnits(allocator, source, diagnostic);
    defer allocator.free(units);
    return std.unicode.wtf16LeToWtf8Alloc(allocator, units);
}
fn spacesOnly(units: []const u16) bool {
    for (units) |unit| if (unit != ' ') return false;
    return true;
}
pub fn prettyUnits(allocator: std.mem.Allocator, source: []const u8, diagnostic: yaml.Diagnostic) ![]u16 {
    if (!std.mem.eql(u8, diagnostic.name, "YAMLParseError")) return std.unicode.wtf8ToWtf16LeAlloc(allocator, diagnostic.message);
    const offset = @min(source.len, diagnostic.offset);
    const units = try std.unicode.wtf8ToWtf16LeAlloc(allocator, source);
    defer allocator.free(units);
    const before = try std.unicode.wtf8ToWtf16LeAlloc(allocator, source[0..offset]);
    defer allocator.free(before);
    const position = before.len;
    var line: usize = 1;
    var start: usize = 0;
    var previous: usize = 0;
    for (units[0..position], 0..) |unit, index| if (unit == '\n') {
        line += 1;
        previous = start;
        start = index + 1;
    };
    var line_end = std.mem.indexOfScalarPos(u16, units, start, '\n') orelse units.len;
    while (line_end > start and (units[line_end - 1] == '\r' or units[line_end - 1] == '\n')) line_end -= 1;
    const column = position - start + 1;
    var ci = column - 1;
    var line_text: std.ArrayList(u16) = .empty;
    defer line_text.deinit(allocator);
    const original = units[start..line_end];
    if (ci >= 60 and original.len > 80) {
        const trim_start = @min(ci - 39, original.len - 79);
        try line_text.append(allocator, 0x2026);
        try line_text.appendSlice(allocator, original[trim_start..]);
        ci = ci - trim_start + 1;
    } else try line_text.appendSlice(allocator, original);
    if (line_text.items.len > 80) {
        line_text.shrinkRetainingCapacity(79);
        try line_text.append(allocator, 0x2026);
    }
    var context: std.ArrayList(u16) = .empty;
    defer context.deinit(allocator);
    if (line > 1 and spacesOnly(line_text.items[0..@min(ci, line_text.items.len)])) {
        const prior = units[previous..start];
        if (prior.len > 80) {
            try context.appendSlice(allocator, prior[0..79]);
            try context.appendSlice(allocator, &.{ 0x2026, '\n' });
        } else try context.appendSlice(allocator, prior);
    }
    try context.appendSlice(allocator, line_text.items);
    const header = try std.fmt.allocPrint(allocator, "{s} at line {d}, column {d}", .{ diagnostic.message, line, column });
    defer allocator.free(header);
    var out: std.ArrayList(u16) = .empty;
    errdefer out.deinit(allocator);
    const heading = try std.unicode.wtf8ToWtf16LeAlloc(allocator, header);
    defer allocator.free(heading);
    try out.appendSlice(allocator, heading);
    if (!spacesOnly(context.items)) {
        try out.appendSlice(allocator, &.{ ':', '\n', '\n' });
        try out.appendSlice(allocator, context.items);
        try out.append(allocator, '\n');
        try out.appendNTimes(allocator, ' ', ci);
        var count: usize = 1;
        if (diagnostic.end > offset + 1) {
            const endpoint = try std.unicode.wtf8ToWtf16LeAlloc(allocator, source[0..@min(source.len, diagnostic.end)]);
            defer allocator.free(endpoint);
            if (std.mem.indexOfScalar(u16, units[position..@min(units.len, endpoint.len)], '\n') == null and endpoint.len > position)
                count = @max(1, @min(endpoint.len - position, 80 -| ci));
        }
        try out.appendNTimes(allocator, '^', count);
        try out.append(allocator, '\n');
    }
    return out.toOwnedSlice(allocator);
}
