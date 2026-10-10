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
    if (!std.mem.eql(u8, diagnostic.name, "YAMLParseError")) return allocator.dupe(u8, diagnostic.message);
    const offset = @min(source.len, diagnostic.offset);
    var line: usize = 1;
    var start: usize = 0;
    var previous: usize = 0;
    for (source[0..offset], 0..) |byte, index| if (byte == '\n') {
        line += 1;
        previous = start;
        start = index + 1;
    };
    const line_end = if (std.mem.indexOfScalarPos(u8, source, start, '\n')) |end| end else source.len;
    const prefix = try std.unicode.utf8ToUtf16LeAlloc(allocator, source[start..offset]);
    defer allocator.free(prefix);
    const column = prefix.len + 1;
    var out: std.Io.Writer.Allocating = .init(allocator);
    defer out.deinit();
    try out.writer.print("{s} at line {d}, column {d}", .{ diagnostic.message, line, column });
    const line_text = source[start..line_end];
    if (std.mem.trim(u8, line_text, " ").len == 0) return out.toOwnedSlice();
    try out.writer.writeAll(":\n\n");
    if (line > 1 and std.mem.trim(u8, source[start..offset], " ").len == 0) try out.writer.writeAll(source[previous..start]);
    try out.writer.writeAll(line_text);
    try out.writer.writeByte('\n');
    try out.writer.splatByteAll(' ', column - 1);
    const end = @max(offset + 1, @min(line_end, diagnostic.end));
    const highlighted = try std.unicode.utf8ToUtf16LeAlloc(allocator, source[offset..@min(source.len, end)]);
    defer allocator.free(highlighted);
    try out.writer.splatByteAll('^', @max(1, highlighted.len));
    try out.writer.writeByte('\n');
    return out.toOwnedSlice();
}
