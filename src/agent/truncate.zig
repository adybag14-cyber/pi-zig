//! Output truncation aligned with upstream pi-coding-agent harness tools.
//! Limits: max 2000 lines OR 50KB (whichever first).
const std = @import("std");

pub const DEFAULT_MAX_LINES: usize = 2000;
pub const DEFAULT_MAX_BYTES: usize = 50 * 1024;

pub const TruncationResult = struct {
    content: []u8,
    truncated: bool,
    truncated_by: ?[]const u8,
    output_lines: usize,
    output_bytes: usize,

    pub fn deinit(self: *TruncationResult, gpa: std.mem.Allocator) void {
        gpa.free(self.content);
        self.* = undefined;
    }
};

pub const Options = struct {
    max_lines: usize = DEFAULT_MAX_LINES,
    max_bytes: usize = DEFAULT_MAX_BYTES,
};

/// Keep the head of content within line/byte limits. Caller owns result.content.
pub fn truncateHead(gpa: std.mem.Allocator, content: []const u8, options: Options) !TruncationResult {
    if (content.len == 0) {
        return .{
            .content = try gpa.dupe(u8, ""),
            .truncated = false,
            .truncated_by = null,
            .output_lines = 0,
            .output_bytes = 0,
        };
    }

    // Split into lines keeping newline terminators where present
    var lines: std.ArrayList([]const u8) = .empty;
    defer lines.deinit(gpa);
    var start: usize = 0;
    var i: usize = 0;
    while (i < content.len) : (i += 1) {
        if (content[i] == '\n') {
            try lines.append(gpa, content[start .. i + 1]);
            start = i + 1;
        }
    }
    if (start < content.len) {
        try lines.append(gpa, content[start..]);
    }

    // Under both limits
    if (lines.items.len <= options.max_lines and content.len <= options.max_bytes) {
        return .{
            .content = try gpa.dupe(u8, content),
            .truncated = false,
            .truncated_by = null,
            .output_lines = lines.items.len,
            .output_bytes = content.len,
        };
    }

    // First line alone exceeds bytes
    if (lines.items.len > 0 and lines.items[0].len > options.max_bytes) {
        const cut = @min(options.max_bytes, lines.items[0].len);
        const suffix = "\n... [truncated: first line exceeds byte limit]";
        var out: std.ArrayList(u8) = .empty;
        errdefer out.deinit(gpa);
        try out.appendSlice(gpa, lines.items[0][0..cut]);
        try out.appendSlice(gpa, suffix);
        return .{
            .content = try out.toOwnedSlice(gpa),
            .truncated = true,
            .truncated_by = "bytes",
            .output_lines = 1,
            .output_bytes = cut,
        };
    }

    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(gpa);
    var bytes: usize = 0;
    var kept: usize = 0;
    var truncated_by: []const u8 = "lines";

    for (lines.items) |line| {
        if (kept >= options.max_lines) {
            truncated_by = "lines";
            break;
        }
        if (bytes + line.len > options.max_bytes) {
            truncated_by = "bytes";
            break;
        }
        try out.appendSlice(gpa, line);
        bytes += line.len;
        kept += 1;
    }

    const total = lines.items.len;
    const notice = try std.fmt.allocPrint(
        gpa,
        "... [truncated: showing {d}/{d} lines, limit {s}]\n",
        .{ kept, total, truncated_by },
    );
    defer gpa.free(notice);
    if (out.items.len == 0 or out.items[out.items.len - 1] != '\n') {
        try out.append(gpa, '\n');
    }
    try out.appendSlice(gpa, notice);

    return .{
        .content = try out.toOwnedSlice(gpa),
        .truncated = true,
        .truncated_by = truncated_by,
        .output_lines = kept,
        .output_bytes = bytes,
    };
}

pub fn apply(gpa: std.mem.Allocator, content: []const u8) ![]u8 {
    const r = try truncateHead(gpa, content, .{});
    return r.content;
}

test "truncateHead leaves small content intact" {
    const gpa = std.testing.allocator;
    var r = try truncateHead(gpa, "hello\nworld\n", .{});
    defer r.deinit(gpa);
    try std.testing.expect(!r.truncated);
    try std.testing.expectEqualStrings("hello\nworld\n", r.content);
}

test "truncateHead hits line limit" {
    const gpa = std.testing.allocator;
    var buf: std.ArrayList(u8) = .empty;
    defer buf.deinit(gpa);
    var i: usize = 0;
    while (i < 50) : (i += 1) {
        try buf.appendSlice(gpa, "line\n");
    }
    var r = try truncateHead(gpa, buf.items, .{ .max_lines = 10, .max_bytes = 1024 * 1024 });
    defer r.deinit(gpa);
    try std.testing.expect(r.truncated);
    try std.testing.expectEqualStrings("lines", r.truncated_by.?);
    try std.testing.expect(std.mem.indexOf(u8, r.content, "truncated") != null);
    try std.testing.expectEqual(@as(usize, 10), r.output_lines);
}

test "truncateHead hits byte limit" {
    const gpa = std.testing.allocator;
    var buf: std.ArrayList(u8) = .empty;
    defer buf.deinit(gpa);
    var i: usize = 0;
    while (i < 100) : (i += 1) {
        try buf.appendSlice(gpa, "abcdefghijklmnopqrstuvwxyz\n");
    }
    var r = try truncateHead(gpa, buf.items, .{ .max_lines = 2000, .max_bytes = 100 });
    defer r.deinit(gpa);
    try std.testing.expect(r.truncated);
    try std.testing.expectEqualStrings("bytes", r.truncated_by.?);
    try std.testing.expect(r.output_bytes <= 100);
}
