//! Extract interactive `@file` references without treating ordinary mentions as
//! attachments. Quoted paths and escaped spaces are supported; missing paths
//! stay in the prompt verbatim, and `@@name` becomes a literal `@name`.
const std = @import("std");
const Io = std.Io;
const path_utils = @import("path_utils.zig");

pub const Result = struct {
    message: []u8,
    paths: []const []const u8,

    pub fn deinit(self: *Result, gpa: std.mem.Allocator) void {
        gpa.free(self.message);
        for (self.paths) |path| gpa.free(path);
        gpa.free(self.paths);
        self.* = undefined;
    }
};

const Token = struct {
    start: usize,
    end: usize,
    decoded: []u8,
};

fn nextToken(gpa: std.mem.Allocator, line: []const u8, from: usize) !?Token {
    var start = from;
    while (start < line.len and std.ascii.isWhitespace(line[start])) : (start += 1) {}
    if (start >= line.len) return null;

    var decoded: std.ArrayList(u8) = .empty;
    errdefer decoded.deinit(gpa);
    var quote: ?u8 = null;
    var index = start;
    while (index < line.len) {
        const byte = line[index];
        if (quote == null and std.ascii.isWhitespace(byte)) break;
        if (byte == '\'' or byte == '"') {
            if (quote == null) {
                quote = byte;
                index += 1;
                continue;
            }
            if (quote.? == byte) {
                quote = null;
                index += 1;
                continue;
            }
        }
        if (byte == '\\' and index + 1 < line.len) {
            const next = line[index + 1];
            if (std.ascii.isWhitespace(next) or next == '\'' or next == '"' or next == '\\') {
                try decoded.append(gpa, next);
                index += 2;
                continue;
            }
        }
        try decoded.append(gpa, byte);
        index += 1;
    }
    return .{ .start = start, .end = index, .decoded = try decoded.toOwnedSlice(gpa) };
}

pub fn extract(
    gpa: std.mem.Allocator,
    io: Io,
    environ: *const std.process.Environ.Map,
    cwd: []const u8,
    line: []const u8,
) !Result {
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(gpa);
    var paths: std.ArrayList([]const u8) = .empty;
    errdefer {
        for (paths.items) |path| gpa.free(path);
        paths.deinit(gpa);
    }

    var scan: usize = 0;
    var emitted_until: usize = 0;
    while (try nextToken(gpa, line, scan)) |token_value| {
        var token = token_value;
        defer gpa.free(token.decoded);
        scan = token.end;

        if (std.mem.startsWith(u8, token.decoded, "@@")) {
            try out.appendSlice(gpa, line[emitted_until..token.start]);
            try out.appendSlice(gpa, token.decoded[1..]);
            emitted_until = token.end;
            continue;
        }
        if (token.decoded.len <= 1 or token.decoded[0] != '@') continue;

        const resolved = path_utils.resolveReadPath(gpa, io, environ, token.decoded[1..], cwd) catch continue;
        const stat = std.Io.Dir.cwd().statFile(io, resolved, .{}) catch {
            gpa.free(resolved);
            continue;
        };
        if (stat.kind != .file) {
            gpa.free(resolved);
            continue;
        }

        try out.appendSlice(gpa, line[emitted_until..token.start]);
        emitted_until = token.end;
        try paths.append(gpa, resolved);
    }
    try out.appendSlice(gpa, line[emitted_until..]);

    const trimmed = std.mem.trim(u8, out.items, " \t\r\n");
    const message = try gpa.dupe(u8, trimmed);
    out.deinit(gpa);
    return .{ .message = message, .paths = try paths.toOwnedSlice(gpa) };
}

test "interactive file extraction supports quotes spaces and literal at" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    var env = std.process.Environ.Map.init(gpa);
    defer env.deinit();
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.writeFile(io, .{ .sub_path = "notes one.txt", .data = "one" });
    try tmp.dir.writeFile(io, .{ .sub_path = "two.txt", .data = "two" });
    var root_buf: [std.fs.max_path_bytes]u8 = undefined;
    const root_len = try tmp.dir.realPath(io, &root_buf);
    const root = root_buf[0..root_len];

    var result = try extract(gpa, io, &env, root, "review @\"notes one.txt\" and @two.txt then @@literal @missing.txt");
    defer result.deinit(gpa);
    try std.testing.expectEqual(@as(usize, 2), result.paths.len);
    try std.testing.expect(std.mem.endsWith(u8, result.paths[0], "notes one.txt"));
    try std.testing.expect(std.mem.endsWith(u8, result.paths[1], "two.txt"));
    try std.testing.expect(std.mem.indexOf(u8, result.message, "@literal") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.message, "@missing.txt") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.message, "notes one") == null);
}

test "interactive file extraction preserves Windows backslashes and ordinary mentions" {
    const gpa = std.testing.allocator;
    var env = std.process.Environ.Map.init(gpa);
    defer env.deinit();
    var result = try extract(gpa, std.testing.io, &env, ".", "email user@example.com and @C:\\missing\\file.txt");
    defer result.deinit(gpa);
    try std.testing.expectEqual(@as(usize, 0), result.paths.len);
    try std.testing.expectEqualStrings("email user@example.com and @C:\\missing\\file.txt", result.message);
}
