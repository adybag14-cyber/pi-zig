//! Cross-platform path normalization used by CLI attachments and resource flags.
//!
//! This ports the non-runtime-specific parts of upstream `utils/paths.ts` and
//! `core/tools/path-utils.ts`: Unicode-space normalization, optional `@`
//! stripping, tilde/file-URL expansion, lexical resolution, Windows shell path
//! conversion, and common macOS screenshot filename fallbacks.
const std = @import("std");
const Io = std.Io;
const builtin = @import("builtin");
const config = @import("../config.zig");

pub const NormalizeOptions = struct {
    trim: bool = false,
    expand_tilde: bool = true,
    strip_at_prefix: bool = false,
    normalize_unicode_spaces: bool = false,
};

pub fn normalizePath(
    gpa: std.mem.Allocator,
    environ: *const std.process.Environ.Map,
    input: []const u8,
    options: NormalizeOptions,
) ![]u8 {
    var current = if (options.trim) std.mem.trim(u8, input, " \t\r\n") else input;
    if (options.strip_at_prefix and current.len > 0 and current[0] == '@') current = current[1..];

    var normalized_spaces: ?[]u8 = null;
    defer if (normalized_spaces) |owned| gpa.free(owned);
    if (options.normalize_unicode_spaces) {
        normalized_spaces = try replaceUnicodeSpaces(gpa, current);
        current = normalized_spaces.?;
    }

    var file_url: ?[]u8 = null;
    defer if (file_url) |owned| gpa.free(owned);
    if (std.mem.startsWith(u8, current, "file://")) {
        file_url = try fileUrlToPath(gpa, current);
        current = file_url.?;
    }

    var tilde_expanded: ?[]u8 = null;
    defer if (tilde_expanded) |owned| gpa.free(owned);
    if (options.expand_tilde and (std.mem.eql(u8, current, "~") or std.mem.startsWith(u8, current, "~/") or std.mem.startsWith(u8, current, "~\\"))) {
        const home = config.homeDir(environ) orelse return error.NoHomeDir;
        tilde_expanded = if (current.len == 1)
            try gpa.dupe(u8, home)
        else
            try std.fs.path.join(gpa, &.{ home, current[2..] });
        current = tilde_expanded.?;
    }

    if (comptime builtin.os.tag == .windows) {
        const converted = try normalizeWindowsShellPath(gpa, current);
        if (converted) |owned| return owned;
    }
    return try gpa.dupe(u8, current);
}

pub fn resolvePath(
    gpa: std.mem.Allocator,
    environ: *const std.process.Environ.Map,
    input: []const u8,
    base_dir: []const u8,
    options: NormalizeOptions,
) ![]u8 {
    const normalized = try normalizePath(gpa, environ, input, options);
    defer gpa.free(normalized);
    const normalized_base = try normalizePath(gpa, environ, base_dir, .{});
    defer gpa.free(normalized_base);
    if (std.fs.path.isAbsolute(normalized)) return std.fs.path.resolve(gpa, &.{normalized});
    return std.fs.path.resolve(gpa, &.{ normalized_base, normalized });
}

/// Resolve an input path and try the filename variants used by macOS screen
/// captures. Every returned path is owned, including the ordinary path.
pub fn resolveReadPath(
    gpa: std.mem.Allocator,
    io: Io,
    environ: *const std.process.Environ.Map,
    input: []const u8,
    cwd: []const u8,
) ![]u8 {
    const resolved = try resolvePath(gpa, environ, input, cwd, .{
        .normalize_unicode_spaces = true,
        .strip_at_prefix = true,
    });
    if (pathExists(io, resolved)) return resolved;

    const am_pm = try macOsAmPmVariant(gpa, resolved);
    if (am_pm) |candidate| {
        if (pathExists(io, candidate)) {
            gpa.free(resolved);
            return candidate;
        }
        gpa.free(candidate);
    }

    const curly = try curlyQuoteVariant(gpa, resolved);
    if (curly) |candidate| {
        if (pathExists(io, candidate)) {
            gpa.free(resolved);
            return candidate;
        }
        gpa.free(candidate);
    }
    return resolved;
}

pub fn pathExists(io: Io, path: []const u8) bool {
    std.Io.Dir.cwd().access(io, path, .{}) catch return false;
    return true;
}

fn replaceUnicodeSpaces(gpa: std.mem.Allocator, input: []const u8) ![]u8 {
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(gpa);
    var i: usize = 0;
    while (i < input.len) {
        const consumed: usize = if (i + 2 <= input.len and input[i] == 0xc2 and input[i + 1] == 0xa0)
            2 // U+00A0
        else if (i + 3 <= input.len and input[i] == 0xe2 and input[i + 1] == 0x80 and ((input[i + 2] >= 0x80 and input[i + 2] <= 0x8a) or input[i + 2] == 0xaf))
            3 // U+2000..U+200A or U+202F
        else if (i + 3 <= input.len and input[i] == 0xe2 and input[i + 1] == 0x81 and input[i + 2] == 0x9f)
            3 // U+205F
        else if (i + 3 <= input.len and input[i] == 0xe3 and input[i + 1] == 0x80 and input[i + 2] == 0x80)
            3 // U+3000
        else
            0;
        if (consumed > 0) {
            try out.append(gpa, ' ');
            i += consumed;
        } else {
            try out.append(gpa, input[i]);
            i += 1;
        }
    }
    return try out.toOwnedSlice(gpa);
}

fn fileUrlToPath(gpa: std.mem.Allocator, input: []const u8) ![]u8 {
    var rest = input["file://".len..];
    if (std.mem.startsWith(u8, rest, "localhost/")) rest = rest["localhost".len..];
    const decoded = try percentDecode(gpa, rest);
    errdefer gpa.free(decoded);
    if (comptime builtin.os.tag == .windows) {
        if (decoded.len >= 3 and decoded[0] == '/' and std.ascii.isAlphabetic(decoded[1]) and decoded[2] == ':') {
            const native = try gpa.dupe(u8, decoded[1..]);
            gpa.free(decoded);
            for (native) |*c| {
                if (c.* == '/') c.* = '\\';
            }
            return native;
        }
    }
    // `file:///tmp/x` leaves `/tmp/x`; a non-local host remains `host/path`
    // and is converted to `//host/path` for UNC-like semantics.
    if (rest.len > 0 and rest[0] != '/' and !std.mem.startsWith(u8, rest, "localhost/")) {
        const with_host = try std.fmt.allocPrint(gpa, "//{s}", .{decoded});
        gpa.free(decoded);
        return with_host;
    }
    return decoded;
}

fn percentDecode(gpa: std.mem.Allocator, input: []const u8) ![]u8 {
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(gpa);
    var i: usize = 0;
    while (i < input.len) {
        if (input[i] == '%') {
            if (i + 2 >= input.len) return error.InvalidFileUrl;
            const hi = std.fmt.charToDigit(input[i + 1], 16) catch return error.InvalidFileUrl;
            const lo = std.fmt.charToDigit(input[i + 2], 16) catch return error.InvalidFileUrl;
            try out.append(gpa, @intCast(hi * 16 + lo));
            i += 3;
        } else {
            try out.append(gpa, input[i]);
            i += 1;
        }
    }
    return try out.toOwnedSlice(gpa);
}

fn normalizeWindowsShellPath(gpa: std.mem.Allocator, input: []const u8) !?[]u8 {
    if (input.len < 3 or input[0] != '/' or (input.len >= 2 and input[1] == '/') or std.mem.indexOfScalar(u8, input, '\\') != null) return null;
    var rest = input[1..];
    if (std.mem.startsWith(u8, rest, "mnt/")) rest = rest[4..] else if (std.mem.startsWith(u8, rest, "cygdrive/")) rest = rest[9..];
    if (rest.len == 0 or !std.ascii.isAlphabetic(rest[0]) or (rest.len > 1 and rest[1] != '/')) return null;
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(gpa);
    try out.append(gpa, std.ascii.toUpper(rest[0]));
    try out.appendSlice(gpa, ":\\");
    if (rest.len > 2) {
        for (rest[2..]) |c| try out.append(gpa, if (c == '/') '\\' else c);
    }
    return try out.toOwnedSlice(gpa);
}

fn macOsAmPmVariant(gpa: std.mem.Allocator, input: []const u8) !?[]u8 {
    var found = false;
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(gpa);
    var i: usize = 0;
    while (i < input.len) {
        if (i + 4 <= input.len and input[i] == ' ' and
            ((std.ascii.toUpper(input[i + 1]) == 'A' or std.ascii.toUpper(input[i + 1]) == 'P') and std.ascii.toUpper(input[i + 2]) == 'M' and input[i + 3] == '.'))
        {
            try out.appendSlice(gpa, "\u{202f}");
            try out.append(gpa, input[i + 1]);
            try out.append(gpa, input[i + 2]);
            try out.append(gpa, '.');
            i += 4;
            found = true;
        } else {
            try out.append(gpa, input[i]);
            i += 1;
        }
    }
    if (!found) {
        out.deinit(gpa);
        return null;
    }
    return try out.toOwnedSlice(gpa);
}

fn curlyQuoteVariant(gpa: std.mem.Allocator, input: []const u8) !?[]u8 {
    if (std.mem.indexOfScalar(u8, input, '\'') == null) return null;
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(gpa);
    for (input) |c| {
        if (c == '\'') try out.appendSlice(gpa, "\u{2019}") else try out.append(gpa, c);
    }
    return try out.toOwnedSlice(gpa);
}

test "normalize path strips at, expands tilde, and normalizes Unicode spaces" {
    const gpa = std.testing.allocator;
    var env = std.process.Environ.Map.init(gpa);
    defer env.deinit();
    if (builtin.os.tag == .windows) {
        try env.put("USERPROFILE", "C:\\Users\\tester");
    } else {
        try env.put("HOME", "/home/tester");
    }
    const out = try normalizePath(gpa, &env, "@~/Screen\u{202f}Shot.png", .{
        .strip_at_prefix = true,
        .normalize_unicode_spaces = true,
    });
    defer gpa.free(out);
    try std.testing.expectEqualStrings(if (builtin.os.tag == .windows) "C:\\Users\\tester\\Screen Shot.png" else "/home/tester/Screen Shot.png", out);
}

test "resolve path is lexical and relative to cwd" {
    const gpa = std.testing.allocator;
    var env = std.process.Environ.Map.init(gpa);
    defer env.deinit();
    const out = try resolvePath(gpa, &env, "a/../b.txt", if (builtin.os.tag == .windows) "C:\\tmp\\project" else "/tmp/project", .{});
    defer gpa.free(out);
    try std.testing.expectEqualStrings(if (builtin.os.tag == .windows) "C:\\tmp\\project\\b.txt" else "/tmp/project/b.txt", out);
}

test "file URL percent decoding" {
    const gpa = std.testing.allocator;
    var env = std.process.Environ.Map.init(gpa);
    defer env.deinit();
    const out = try normalizePath(gpa, &env, "file:///tmp/hello%20world.txt", .{});
    defer gpa.free(out);
    try std.testing.expectEqualStrings("/tmp/hello world.txt", out);
}
