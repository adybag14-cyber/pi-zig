//! Native glob planning for the minimatch 10.2.6 calls used by Pi.
//! Zig owns brace expansion, glob parsing, and path traversal. The caller uses
//! the linked VM's RegExp primitive for segment matching and Unicode case rules.
const std = @import("std");

pub const Options = struct { nocase: bool = false, windows: bool = false };
pub const Part = union(enum) { globstar, regex: Regex };
pub const Fast = enum { none, star, suffix, qmarks, dot_star, star_dot_star };
pub const Regex = struct { source: []const u8, unicode: bool = false, nocase: bool = false, literal: ?[]const u8 = null, fast: Fast = .none, suffix: []const u8 = "", length: usize = 0 };
pub const Pattern = []const Part;
pub const Plan = struct { patterns: []const Pattern, negate: bool = false, comment: bool = false, empty: bool = false };
const Strings = std.ArrayList([]const u8);
const Buffer = std.ArrayList(u8);
const expansion_max = 100_000;
const expansion_max_length = 4_000_000;

fn add(a: std.mem.Allocator, out: *Buffer, value: []const u8) !void {
    try out.appendSlice(a, value);
}
pub const Units = struct { values: []const u16, ends: []const usize };
/// Accept ordinary UTF8 and code-unit WTF8. Keeping the consumed byte offsets
/// lets the class parser use JS charAt units without changing the glob parser.
pub fn decodeUnits(a: std.mem.Allocator, text: []const u8) !Units {
    var values: std.ArrayList(u16) = .empty;
    errdefer values.deinit(a);
    var ends: std.ArrayList(usize) = .empty;
    errdefer ends.deinit(a);
    var i: usize = 0;
    while (i < text.len) {
        const first = text[i];
        const width: usize = if (first < 0x80) 1 else if (first >= 0xc2 and first <= 0xdf) 2 else if (first >= 0xe0 and first <= 0xef) 3 else if (first >= 0xf0 and first <= 0xf4) 4 else return error.MinimatchInvalidWtf8;
        if (i + width > text.len) return error.MinimatchInvalidWtf8;
        var value: u32 = first & (switch (width) { 1 => @as(u8, 0x7f), 2 => 0x1f, 3 => 0x0f, else => 0x07 });
        for (text[i + 1..i + width]) |byte| {
            if (byte & 0xc0 != 0x80) return error.MinimatchInvalidWtf8;
            value = (value << 6) | (byte & 0x3f);
        }
        if ((width == 2 and value < 0x80) or (width == 3 and value < 0x800) or (width == 4 and value < 0x10000) or value > 0x10ffff) return error.MinimatchInvalidWtf8;
        i += width;
        if (value > 0xffff) {
            const scalar = value - 0x10000;
            try values.append(a, @intCast(0xd800 + (scalar >> 10)));
            try ends.append(a, i);
            try values.append(a, @intCast(0xdc00 + (scalar & 0x3ff)));
            try ends.append(a, i);
        } else {
            try values.append(a, @intCast(value));
            try ends.append(a, i);
        }
    }
    return .{ .values = values.items, .ends = ends.items };
}
fn appendUnit(a: std.mem.Allocator, out: *Buffer, value: u16) !void {
    if (value < 0x80) try out.append(a, @intCast(value))
    else if (value < 0x800) try out.appendSlice(a, &.{ @as(u8, @intCast(0xc0 | (value >> 6))), @as(u8, @intCast(0x80 | (value & 0x3f))) })
    else try out.appendSlice(a, &.{ @as(u8, @intCast(0xe0 | (value >> 12))), @as(u8, @intCast(0x80 | ((value >> 6) & 0x3f))), @as(u8, @intCast(0x80 | (value & 0x3f))) });
}
pub fn encodeUnits(a: std.mem.Allocator, units: []const u16) ![]u8 {
    var out: Buffer = .empty;
    errdefer out.deinit(a);
    for (units) |value| try appendUnit(a, &out, value);
    return out.toOwnedSlice(a);
}
fn characterWidth(bytes: []const u8) usize {
    const width = std.unicode.utf8ByteSequenceLength(bytes[0]) catch return 1;
    return if (width <= bytes.len) width else 1;
}
fn whitespace(bytes: []const u8) bool {
    const value = std.unicode.utf8Decode(bytes) catch return false;
    return switch (value) {
        0x09...0x0d, 0x20, 0x00a0, 0x1680, 0x2000...0x200a,
        0x2028, 0x2029, 0x202f, 0x205f, 0x3000, 0xfeff => true,
        else => false,
    };
}
fn literalMode(a: std.mem.Allocator, out: *Buffer, value: []const u8, escaped_mode: bool) !void {
    var i: usize = 0;
    while (i < value.len) {
        const width = characterWidth(value[i..]);
        const character = value[i..i + width];
        const specials: []const u8 = if (escaped_mode) "().*{}+?[]^$\\!" else "-[]{}()*+?.,\\^$|#";
        if ((width == 1 and std.mem.indexOfScalar(u8, specials, character[0]) != null) or (!escaped_mode and whitespace(character))) try out.append(a, '\\');
        try out.appendSlice(a, character);
        i += width;
    }
}
fn literal(a: std.mem.Allocator, out: *Buffer, value: []const u8) !void {
    return literalMode(a, out, value, false);
}

/// Slash runs collapse, except the extra leading empty UNC segment on Windows.
pub fn split(a: std.mem.Allocator, path: []const u8, windows: bool) ![]const []const u8 {
    var parts: Strings = .empty;
    if (windows and std.mem.startsWith(u8, path, "//") and path.len > 2 and path[2] != '/') try parts.append(a, "");
    var start: usize = 0;
    var i: usize = 0;
    while (i < path.len) {
        if (path[i] != '/') { i += 1; continue; }
        try parts.append(a, path[start..i]);
        while (i < path.len and path[i] == '/') : (i += 1) {}
        start = i;
    }
    try parts.append(a, path[start..]);
    return parts.items;
}

fn escaped(pattern: []const u8, i: usize) bool {
    var n: usize = 0;
    var j = i;
    while (j > 0 and pattern[j - 1] == '\\') { n += 1; j -= 1; }
    return n % 2 == 1;
}
const Group = struct { start: usize, end: usize };
fn braceGroup(pattern: []const u8, from: usize) !?Group {
    var starts: [65]usize = undefined;
    var depth: usize = 0;
    var fallback: ?Group = null;
    for (pattern[from..], from..) |ch, i| {
        if (escaped(pattern, i)) continue;
        if (ch == '{') {
            if (depth == starts.len) return error.MinimatchBraceDepthUnsupported;
            starts[depth] = i;
            depth += 1;
        }
        if (ch == '}' and depth > 0) {
            depth -= 1;
            const group: Group = .{ .start = starts[depth], .end = i };
            if (depth == 0) return group;
            if (fallback == null or group.start < fallback.?.start) fallback = group;
        }
    }
    return fallback;
}
fn commaParts(a: std.mem.Allocator, body: []const u8) ![]const []const u8 {
    var out: Strings = .empty;
    var depth: usize = 0;
    var begin: usize = 0;
    for (body, 0..) |ch, i| {
        if (escaped(body, i)) continue;
        if (ch == '{') depth += 1;
        if (ch == '}' and depth > 0) depth -= 1;
        if (ch == ',' and depth == 0) { try out.append(a, body[begin..i]); begin = i + 1; }
    }
    try out.append(a, body[begin..]);
    return out.items;
}
fn numericSyntax(value: []const u8) bool {
    if (value.len == 0) return false;
    const start: usize = if (value[0] == '-') 1 else 0;
    if (start == value.len) return false;
    for (value[start..]) |ch| if (!std.ascii.isDigit(ch)) return false;
    return true;
}
fn decimal(value: []const u8) ?i64 {
    if (!numericSyntax(value)) return null;
    return std.fmt.parseInt(i64, value, 10) catch null;
}
fn padded(value: []const u8) bool {
    const start: usize = if (value.len > 0 and value[0] == '-') 1 else 0;
    return value.len > start + 1 and value[start] == '0';
}
fn sequence(a: std.mem.Allocator, body: []const u8) !?[]const []const u8 {
    var fields = std.mem.splitSequence(u8, body, "..");
    const first = fields.next().?;
    const last = fields.next() orelse return null;
    const step_text = fields.next();
    if (fields.next() != null) return null;
    const alpha = first.len == 1 and last.len == 1 and std.ascii.isAlphabetic(first[0]) and std.ascii.isAlphabetic(last[0]);
    if (!alpha and (!numericSyntax(first) or !numericSyntax(last))) return null;
    if (step_text) |text| if (!numericSyntax(text)) return null;
    const from: i64 = if (alpha) first[0] else decimal(first) orelse return error.MinimatchRangeOverflow;
    const to: i64 = if (alpha) last[0] else decimal(last) orelse return error.MinimatchRangeOverflow;
    const raw_step = if (step_text) |text| decimal(text) orelse return error.MinimatchRangeOverflow else 1;
    const max_safe_integer: i64 = 9_007_199_254_740_991;
    if (from < -max_safe_integer or from > max_safe_integer or to < -max_safe_integer or to > max_safe_integer or raw_step < -max_safe_integer or raw_step > max_safe_integer) return error.MinimatchRangePrecisionUnsupported;
    if (raw_step == std.math.minInt(i64)) return error.MinimatchRangeOverflow;
    const step: i64 = @max(if (raw_step < 0) -raw_step else raw_step, 1);
    const width = @max(first.len, last.len);
    const pad = padded(first) or padded(last) or (if (step_text) |text| padded(text) else false);
    var out: Strings = .empty;
    var total: usize = 0;
    var n = from;
    while (if (from <= to) n <= to else n >= to) {
        var rendered: []const u8 = undefined;
        if (alpha) {
            rendered = if (n == '\\') "" else try a.dupe(u8, &.{@intCast(n)});
        } else {
            const text = try std.fmt.allocPrint(a, "{d}", .{n});
            if (pad and text.len < width) {
                const bytes = try a.alloc(u8, width);
                @memset(bytes, '0');
                if (n < 0) {
                    bytes[0] = '-';
                    @memcpy(bytes[width - (text.len - 1)..], text[1..]);
                } else @memcpy(bytes[width - text.len..], text);
                rendered = bytes;
            } else rendered = text;
        }
        if (out.items.len == expansion_max or total + rendered.len > expansion_max_length) return error.MinimatchExpansionLimitUnsupported;
        try out.append(a, rendered);
        total += rendered.len;
        const increment: i64 = if (from <= to) step else -step;
        n = std.math.add(i64, n, increment) catch break;
    }
    return out.items;
}
fn combine(a: std.mem.Allocator, before: []const u8, value: []const u8, after: []const u8) ![]const u8 {
    return std.mem.concat(a, u8, &.{ before, value, after });
}
const BraceExpander = struct {
    a: std.mem.Allocator,
    tokens: [5][]const u8,
    fn init(a: std.mem.Allocator, input: []const u8) !BraceExpander {
        var prefix: []const u8 = "\x00native-minimatch\x00";
        while (std.mem.indexOf(u8, input, prefix) != null) prefix = try combine(a, prefix, "_", "");
        var tokens: [5][]const u8 = undefined;
        for (&tokens, "SOCMP") |*slot, suffix| slot.* = try combine(a, prefix, &.{suffix}, "\x00");
        return .{ .a = a, .tokens = tokens };
    }
    fn escape(self: BraceExpander, input: []const u8) ![]const u8 {
        var out: Buffer = .empty;
        var i: usize = 0;
        if (std.mem.startsWith(u8, input, "{}")) {
            try add(self.a, &out, self.tokens[1]);
            try add(self.a, &out, self.tokens[2]);
            i = 2;
        }
        while (i < input.len) : (i += 1) {
            if (input[i] == '\\' and i + 1 < input.len) {
                if (std.mem.indexOfScalar(u8, "\\{},.", input[i + 1])) |index| {
                    try add(self.a, &out, self.tokens[index]);
                    i += 1;
                    continue;
                }
            }
            try out.append(self.a, input[i]);
        }
        return out.items;
    }
    fn unescape(self: BraceExpander, input: []const u8) ![]const u8 {
        var out: Buffer = .empty;
        var i: usize = 0;
        outer: while (i < input.len) {
            for (self.tokens, "\\{},.") |token, replacement| {
                if (!std.mem.startsWith(u8, input[i..], token)) continue;
                try out.append(self.a, replacement);
                i += token.len;
                continue :outer;
            }
            try out.append(self.a, input[i]);
            i += 1;
        }
        return out.items;
    }
    fn product(self: BraceExpander, prefixes: []const []const u8, pre: []const u8, values: []const []const u8, drop_empty: bool) ![]const []const u8 {
        var out: Strings = .empty;
        var length: usize = 0;
        for (prefixes) |prefix| for (values) |value| {
            const text = try combine(self.a, prefix, pre, value);
            if (drop_empty and text.len == 0) continue;
            if (out.items.len == expansion_max or length + text.len > expansion_max_length) return error.MinimatchExpansionLimitUnsupported;
            try out.append(self.a, text);
            length += text.len;
        };
        return out.items;
    }
    fn rewritePossible(post: []const u8) bool {
        for (post, 0..) |ch, i| {
            if (ch == ',' and i + 1 < post.len and post[i + 1] != ',' and std.mem.indexOfScalar(u8, post[i + 1..], '}') != null) return true;
        }
        return false;
    }
    fn inner(self: BraceExpander, initial: []const u8, depth: usize, top: bool) anyerror![]const []const u8 {
        if (depth > 64) return error.MinimatchBraceDepthUnsupported;
        var pattern = initial;
        var acc: []const []const u8 = &.{""};
        var first = true;
        var drop_empty = false;
        var rewrites: usize = 0;
        while (true) {
            const group = (try braceGroup(pattern, 0)) orelse return self.product(acc, pattern, &.{""}, drop_empty);
            const pre = pattern[0..group.start];
            const body = pattern[group.start + 1..group.end];
            const post = pattern[group.end + 1..];
            if (pre.len > 0 and pre[pre.len - 1] == '$') {
                acc = try self.product(acc, pattern[0..group.end + 1], &.{""}, drop_empty and post.len == 0);
                first = false;
                if (post.len == 0) return acc;
                pattern = post;
                continue;
            }
            const range = try sequence(self.a, body);
            const has_options = std.mem.indexOfScalar(u8, body, ',') != null;
            if (range == null and !has_options) {
                if (rewritePossible(post)) {
                    if (rewrites == 1000) return error.MinimatchBraceRewriteLimitUnsupported;
                    rewrites += 1;
                    pattern = try std.mem.concat(self.a, u8, &.{ pre, "{", body, self.tokens[2], post });
                    continue;
                }
                return self.product(acc, pattern, &.{""}, drop_empty);
            }
            if (first) { drop_empty = top and range == null; first = false; }
            var values: []const []const u8 = undefined;
            if (range) |items| values = items else {
                var members = try commaParts(self.a, body);
                if (members.len == 1) {
                    var wrapped: Strings = .empty;
                    for (try self.inner(members[0], depth + 1, false)) |item| try wrapped.append(self.a, try combine(self.a, "{", item, "}"));
                    members = wrapped.items;
                }
                var expanded: Strings = .empty;
                for (members) |member| {
                    for (try self.inner(member, depth + 1, false)) |item| {
                        if (expanded.items.len == expansion_max) return error.MinimatchExpansionLimitUnsupported;
                        try expanded.append(self.a, item);
                    }
                }
                values = expanded.items;
            }
            acc = try self.product(acc, pre, values, drop_empty and post.len == 0);
            if (post.len == 0) return acc;
            pattern = post;
        }
    }
    fn run(self: BraceExpander, input: []const u8) ![]const []const u8 {
        const escaped_input = try self.escape(input);
        const values = try self.inner(escaped_input, 0, true);
        var out: Strings = .empty;
        for (values) |value| try out.append(self.a, try self.unescape(value));
        return out.items;
    }
};

const Class = struct { source: []const u8, consumed: usize, unicode: bool, magic: bool };
fn classLiteral(a: std.mem.Allocator, out: *Buffer, value: u16) !void {
    if (value < 0x80 and std.mem.indexOfScalar(u8, "[]\\-", @intCast(value)) != null) try out.append(a, '\\');
    if (value >= 0xd800 and value <= 0xdfff) {
        try add(a, out, try std.fmt.allocPrint(a, "\\u{x:0>4}", .{value}));
    } else try appendUnit(a, out, value);
}
fn startsWithUnits(text: []const u16, ascii: []const u8) bool {
    if (text.len < ascii.len) return false;
    for (ascii, text[0..ascii.len]) |byte, value| if (byte != value) return false;
    return true;
}
fn parseClass(a: std.mem.Allocator, glob: []const u8) !?Class {
    const decoded = try decodeUnits(a, glob);
    const units = decoded.values;
    var positive: Buffer = .empty;
    var negative: Buffer = .empty;
    var unicode = false;
    var saw = false;
    var negate = false;
    var pending: ?u16 = null;
    var i: usize = 1;
    var end: usize = 0;
    var count: usize = 0;
    var singleton: ?u16 = null;
    const names = [_][]const u8{ "alnum", "alpha", "ascii", "blank", "cntrl", "digit", "graph", "lower", "print", "punct", "space", "upper", "word", "xdigit" };
    const sources = [_][]const u8{ "\\p{L}\\p{Nl}\\p{Nd}", "\\p{L}\\p{Nl}", "\\x00-\\x7f", "\\p{Zs}\\t", "\\p{Cc}", "\\p{Nd}", "\\p{Z}\\p{C}", "\\p{Ll}", "\\p{C}", "\\p{P}", "\\p{Z}\\t\\r\\n\\v\\f", "\\p{Lu}", "\\p{L}\\p{Nl}\\p{Nd}\\p{Pc}", "A-Fa-f0-9" };
    while (i < units.len) {
        var ch = units[i];
        if (i == 1 and (ch == '!' or ch == '^')) { negate = true; i += 1; continue; }
        if (ch == ']' and saw) { end = i + 1; break; }
        saw = true;
        var is_escaped = false;
        if (ch == '\\' and i + 1 < units.len) { i += 1; ch = units[i]; is_escaped = true; }
        var posix = false;
        if (ch == '[' and !is_escaped) {
            for (names, sources, 0..) |name, source, ni| {
                const token = try std.mem.concat(a, u8, &.{ "[:", name, ":]" });
                if (!startsWithUnits(units[i..], token)) continue;
                if (pending != null) return .{ .source = "$.", .consumed = glob.len, .unicode = false, .magic = true };
                try add(a, if (ni == 6) &negative else &positive, source);
                unicode = unicode or (ni != 2 and ni != 13);
                i += token.len;
                count += 2;
                singleton = null;
                posix = true;
                break;
            }
        }
        if (posix) continue;
        if (pending) |first| {
            if (ch >= first) {
                try classLiteral(a, &positive, first);
                if (ch > first) { try positive.append(a, '-'); try classLiteral(a, &positive, ch); count += 2; singleton = null; }
                else { count += 1; singleton = ch; }
            }
            pending = null;
            i += 1;
            continue;
        }
        const next = i + 1;
        if (next + 1 < units.len and units[next] == '-' and units[next + 1] == ']') {
            try classLiteral(a, &positive, ch);
            try classLiteral(a, &positive, '-');
            count += 2;
            singleton = null;
            i = next + 1;
            continue;
        }
        if (next < units.len and units[next] == '-') { pending = ch; i = next + 1; continue; }
        try classLiteral(a, &positive, ch);
        count += 1;
        singleton = ch;
        i = next;
    }
    if (end == 0) return null;
    if (positive.items.len == 0 and negative.items.len == 0) return .{ .source = "$.", .consumed = glob.len, .unicode = false, .magic = true };
    if (!negate and count == 1 and singleton != null and negative.items.len == 0) {
        var out: Buffer = .empty;
        const text = try encodeUnits(a, &.{singleton.?});
        try literal(a, &out, text);
        return .{ .source = out.items, .consumed = decoded.ends[end - 1], .unicode = false, .magic = false };
    }
    var out: Buffer = .empty;
    if (positive.items.len > 0 and negative.items.len > 0) try add(a, &out, "(?:");
    if (positive.items.len > 0) {
        try add(a, &out, if (negate) "[^" else "[");
        try add(a, &out, positive.items);
        try out.append(a, ']');
    }
    if (positive.items.len > 0 and negative.items.len > 0) try out.append(a, '|');
    if (negative.items.len > 0) {
        try add(a, &out, if (negate) "[" else "[^");
        try add(a, &out, negative.items);
        try out.append(a, ']');
    }
    if (positive.items.len > 0 and negative.items.len > 0) try out.append(a, ')');
    return .{ .source = out.items, .consumed = decoded.ends[end - 1], .unicode = unicode, .magic = true };
}

const ast = @import("native_minimatch_ast.zig");
fn plainGlob(a: std.mem.Allocator, glob: []const u8, no_empty: bool) anyerror!ast.Result {
    var out: Buffer = .empty;
    var magic = false;
    var unicode = false;
    var i: usize = 0;
    while (i < glob.len) {
        const ch = glob[i];
        if (ch == '\\') {
            const next = if (i + 1 < glob.len) i + 1 else i;
            const width = characterWidth(glob[next..]);
            try literalMode(a, &out, glob[next..next + width], true);
            i = next + width;
            continue;
        }
        if (ch == '*') {
            magic = true;
            try add(a, &out, if (no_empty and allStars(glob)) "[^/]+?" else "[^/]*?");
            while (i < glob.len and glob[i] == '*') : (i += 1) {}
            continue;
        }
        if (ch == '?') {
            magic = true;
            try add(a, &out, "[^/]");
            i += 1;
            continue;
        }
        if (ch == '[') {
            if (try parseClass(a, glob[i..])) |parsed| {
                magic = magic or parsed.magic;
                unicode = unicode or parsed.unicode;
                try add(a, &out, parsed.source);
                i += parsed.consumed;
                continue;
            }
        }
        const width = characterWidth(glob[i..]);
        try literal(a, &out, glob[i..i + width]);
        i += width;
    }
    return .{ .source = out.items, .body = glob, .magic = magic, .unicode = unicode };
}
pub fn segment(a: std.mem.Allocator, glob: []const u8, nocase: bool) !Regex {
    const rendered = try ast.compile(a, glob, plainGlob);
    const source = try std.mem.concat(a, u8, &.{ "^", rendered.source, "$" });
    if (!rendered.magic) return .{ .source = source, .literal = rendered.body, .nocase = nocase };
    const only_stars = allStars(glob);
    var result: Regex = .{ .source = source, .unicode = rendered.unicode, .nocase = nocase };
    // Original minimatch installs specialized test functions on these regexes.
    // Preserve their endsWith/includes/UTF16-length behavior, including their
    // Unicode lowercase behavior under nocase, rather than assuming /i agrees.
    if (only_stars) { result.fast = .star; return result; }
    var prefix: usize = 0;
    while (prefix < glob.len and glob[prefix] == '*') : (prefix += 1) {}
    if (prefix > 0 and std.mem.indexOfAny(u8, glob[prefix..], "+@!?*[(") == null) {
        result.fast = .suffix;
        result.suffix = glob[prefix..];
        return result;
    }
    prefix = 0;
    while (prefix < glob.len and glob[prefix] == '?') : (prefix += 1) {}
    if (prefix > 0 and std.mem.indexOfAny(u8, glob[prefix..], "+@!?*[(") == null) {
        result.fast = .qmarks;
        result.suffix = glob[prefix..];
        result.length = utf16Length(glob);
        return result;
    }
    if (glob.len > 1 and glob[0] == '.' and allStars(glob[1..])) result.fast = .dot_star;
    prefix = 0;
    while (prefix < glob.len and glob[prefix] == '*') : (prefix += 1) {}
    if (prefix > 0 and prefix + 1 < glob.len and glob[prefix] == '.' and allStars(glob[prefix + 1..])) result.fast = .star_dot_star;
    return result;
}
fn allStars(text: []const u8) bool {
    if (text.len == 0) return false;
    for (text) |ch| if (ch != '*') return false;
    return true;
}
pub fn utf16Length(text: []const u8) usize {
    var count: usize = 0;
    for (text) |ch| {
        if (ch & 0xc0 == 0x80) continue;
        count += if (ch >= 0xf0) @as(usize, 2) else 1;
    }
    return count;
}
fn drive(value: []const u8) bool {
    return value.len == 2 and std.ascii.isAlphabetic(value[0]) and value[1] == ':';
}
fn rootMagic(text: []const u8) bool {
    if (std.mem.indexOfAny(u8, text, "?*[]") != null) return true;
    for (text, 0..) |ch, i| {
        if (std.mem.indexOfScalar(u8, "+@!", ch) == null or i + 1 == text.len or text[i + 1] != '(') continue;
        var j = i + 2;
        while (j < text.len) : (j += 1) {
            if (text[j] == '\r' or text[j] == '\n' or std.mem.startsWith(u8, text[j..], "\xe2\x80\xa8") or std.mem.startsWith(u8, text[j..], "\xe2\x80\xa9")) break;
            if (text[j] == ')') return true;
        }
    }
    return false;
}
fn hasBraceCandidate(pattern: []const u8) bool {
    var open = false;
    var i: usize = 0;
    while (i < pattern.len) : (i += 1) {
        const ch = pattern[i];
        if (std.mem.startsWith(u8, pattern[i..], "\xe2\x80\xa8") or std.mem.startsWith(u8, pattern[i..], "\xe2\x80\xa9")) open = false;
        if (ch == '{') open = true;
        if (ch == '\n' or ch == '\r') open = false;
        if (ch == '}' and open) return true;
    }
    return false;
}

pub fn compile(a: std.mem.Allocator, original: []const u8, options: Options) !Plan {
    if (original.len == 0) return .{ .patterns = &.{}, .empty = true };
    if (original[0] == '#') return .{ .patterns = &.{}, .comment = true };
    var pattern = original;
    var negate = false;
    while (pattern.len > 0 and pattern[0] == '!') { negate = !negate; pattern = pattern[1..]; }
    var expanded: Strings = .empty;
    if (!hasBraceCandidate(pattern)) try expanded.append(a, pattern)
    else {
        const expander = try BraceExpander.init(a, pattern);
        try expanded.appendSlice(a, try expander.run(pattern));
    }
    var patterns: std.ArrayList(Pattern) = .empty;
    for (expanded.items) |value| {
        const raw = try split(a, value, options.windows);
        var optimized: Strings = .empty;
        for (raw) |part| {
            const prev = if (optimized.items.len > 0) optimized.items[optimized.items.len - 1] else "";
            if (std.mem.eql(u8, part, "**") and std.mem.eql(u8, prev, "**")) continue;
            if (std.mem.eql(u8, part, "..") and prev.len > 0 and !std.mem.eql(u8, prev, "..") and !std.mem.eql(u8, prev, ".") and !std.mem.eql(u8, prev, "**")) { _ = optimized.pop(); continue; }
            try optimized.append(a, part);
        }
        if (optimized.items.len == 0) try optimized.append(a, "");
        const unc_no_magic = options.windows and options.nocase and optimized.items.len > 3 and optimized.items[0].len == 0 and optimized.items[1].len == 0 and (std.mem.eql(u8, optimized.items[2], "?") or !rootMagic(optimized.items[2])) and !rootMagic(optimized.items[3]);
        var parts: std.ArrayList(Part) = .empty;
        for (optimized.items, 0..) |part, pi| {
            if (std.mem.eql(u8, part, "**")) { try parts.append(a, .globstar); continue; }
            const windows_root = options.windows and options.nocase and ((pi == 0 and drive(part)) or (unc_no_magic and pi >= 2 and pi < 4));
            const unc_question = options.windows and pi == 2 and optimized.items.len > 3 and optimized.items[0].len == 0 and optimized.items[1].len == 0 and std.mem.eql(u8, part, "?") and drive(optimized.items[3]);
            try parts.append(a, .{ .regex = if (windows_root or unc_question) .{ .source = "", .literal = part } else try segment(a, part, options.nocase) });
        }
        try patterns.append(a, parts.items);
    }
    return .{ .patterns = patterns.items, .negate = negate };
}

fn patternLiteral(pattern: Pattern, index: usize) ?[]const u8 {
    if (index >= pattern.len) return null;
    return switch (pattern[index]) { .globstar => null, .regex => |regex| regex.literal };
}
fn driveIndex(path: []const []const u8) ?usize {
    if (path.len > 0 and drive(path[0])) return 0;
    if (path.len > 3 and path[0].len == 0 and path[1].len == 0 and std.mem.eql(u8, path[2], "?") and drive(path[3])) return 3;
    return null;
}
pub fn match(context: anytype, pattern: Pattern, path: []const []const u8, windows: bool) !bool {
    if (windows) {
        const pdi: ?usize = blk: {
            if (patternLiteral(pattern, 0)) |first| if (drive(first)) break :blk 0;
            if (pattern.len > 3 and std.mem.eql(u8, patternLiteral(pattern, 0) orelse "?", "") and std.mem.eql(u8, patternLiteral(pattern, 1) orelse "?", "") and std.mem.eql(u8, patternLiteral(pattern, 2) orelse "", "?")) {
                if (patternLiteral(pattern, 3)) |letter| if (drive(letter)) break :blk 3;
            }
            break :blk null;
        };
        if (pdi) |pi| if (driveIndex(path)) |fi| {
            if (std.ascii.eqlIgnoreCase(patternLiteral(pattern, pi).?, path[fi])) return walk(context, pattern, path, pi + 1, fi + 1);
        };
    }
    return walk(context, pattern, path, 0, 0);
}

/// The adapter supplies a compiled VM regex test for the part index. Zig owns
/// globstar backtracking and the special allowance for a trailing empty path.
pub fn walk(context: anytype, pattern: Pattern, path: []const []const u8, pattern_start: usize, file_start: usize) anyerror!bool {
    var pi = pattern_start;
    var fi = file_start;
    while (pi < pattern.len) {
        if (pattern[pi] != .globstar) {
            if (fi == path.len or !try context.@"test"(pi, path[fi])) return false;
            pi += 1;
            fi += 1;
            continue;
        }
        // minimatch 10.2.6 requires a remaining segment for a terminal
        // globstar, even an empty trailing-slash segment. Thus a/** matches
        // a/ but not a; a/**/b can still consume zero middle segments.
        if (pi + 1 == pattern.len and fi == path.len) return false;
        if (try walk(context, pattern, path, pi + 1, fi)) return true;
        var i = fi;
        while (i < path.len) : (i += 1) {
            if (path[i].len > 0 and path[i][0] == '.') break;
            if (try walk(context, pattern, path, pi + 1, i + 1)) return true;
        }
        return false;
    }
    return fi == path.len or (fi + 1 == path.len and path[fi].len == 0);
}
