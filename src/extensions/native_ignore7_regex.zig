//! Exact ignore 7.0.8 pattern compiler. Native control flow, genuine VM regex.
//! Authority index.js SHA643735013BDCF86DFECA4D38FB74D9A4FAFA7A640AD2D251077862F18B2556FE.
const std = @import("std");
const v = @import("native_ai_provider_values.zig");
pub const Scope = v.Scope;
const c = v.c;
const Units = std.ArrayList(u16);
const marker = "\u{e000}";
fn ascii(out: *Units, gpa: std.mem.Allocator, value: []const u8) !void {
    for (value) |byte| try out.append(gpa, byte);
}
pub fn units(scope: *Scope, value: c.JSValue) ![]u16 {
    var length: usize = 0;
    const bytes = c.JS_ToCStringLen2(scope.engine.context, &length, value, true);
    if (bytes == null) return v.js.capture(scope.engine);
    defer c.JS_FreeCString(scope.engine.context, bytes);
    var out: Units = .empty;
    errdefer out.deinit(scope.engine.gpa);
    var index: usize = 0;
    // QuickJS CESU-8 is valid encoded UTF-16, including lone surrogate units.
    while (index < length) {
        const lead = bytes[index];
        if (lead < 0x80) {
            try out.append(scope.engine.gpa, lead);
            index += 1;
        } else if (lead < 0xe0) {
            try out.append(scope.engine.gpa, (@as(u16, lead & 0x1f) << 6) | (bytes[index + 1] & 0x3f));
            index += 2;
        } else {
            try out.append(scope.engine.gpa, (@as(u16, lead & 0x0f) << 12) | (@as(u16, bytes[index + 1] & 0x3f) << 6) | (bytes[index + 2] & 0x3f));
            index += 3;
        }
    }
    return out.toOwnedSlice(scope.engine.gpa);
}
pub fn text(scope: *Scope, value: []const u16) !c.JSValue {
    return scope.own(try scope.engine.checked(c.JS_NewStringUTF16(scope.engine.context, value.ptr, value.len)));
}
pub fn regex(scope: *Scope, source: c.JSValue, flags: []const u8) !c.JSValue {
    var args = [_]c.JSValue{ source, try scope.text(flags) };
    return scope.own(try scope.engine.checked(c.JS_CallConstructor(scope.engine.context, scope.engine.intrinsic_regexp_constructor, args.len, &args)));
}
pub fn matches(scope: *Scope, source: []const u8, flags: []const u8, value: c.JSValue) !bool {
    return scope.truthy(try scope.invoke(try regex(scope, try scope.text(source), flags), "test", &.{value}));
}
fn member(out: *Units, gpa: std.mem.Allocator, char: u16) !void {
    if (char < 128 and std.mem.indexOfScalar(u8, "\\]^-[", @intCast(char)) != null) try out.append(gpa, '\\');
    try out.append(gpa, char);
}
fn posix(name: []const u16) ?[]const u8 {
    const names = .{ "alnum", "alpha", "blank", "cntrl", "digit", "graph", "lower", "print", "punct", "space", "upper", "xdigit" };
    const bodies = .{ "0-9A-Za-z", "A-Za-z", " \\t", "\\x00-\\x1f\\x7f", "0-9", "!-.0-~", "a-z", " -.0-~", "!-.:-@\\[-`{-~", " \\t\\n\\r", "A-Z", "0-9A-Fa-f" };
    inline for (names, bodies) |key, body| {
        if (name.len == key.len) {
            var same = true;
            for (name, key) |left, right| if (left != right) { same = false; break; };
            if (same) return body;
        }
    }
    return null;
}
const Bracket = struct { end: usize, source: c.JSValue };
fn bracket(scope: *Scope, pattern: []const u16, start: usize) !?Bracket {
    const gpa = scope.engine.gpa;
    var index = start + 1;
    var negated = false;
    if (index < pattern.len and (pattern[index] == '!' or pattern[index] == '^')) { negated = true; index += 1; }
    var body: Units = .empty;
    defer body.deinit(gpa);
    var previous: ?u16 = null;
    while (true) {
        if (index >= pattern.len) return null;
        const char = pattern[index];
        if (char == '\\') {
            if (index + 1 == pattern.len) return null;
            index += 1;
            try member(&body, gpa, pattern[index]);
            previous = pattern[index];
        } else if (char == '-' and previous != null and index + 1 < pattern.len and pattern[index + 1] != ']') {
            index += 1;
            if (pattern[index] == '\\') {
                index += 1;
                // Source compares the previous member with undefined (false),
                // then its next scan iteration returns null for this bracket.
                if (index >= pattern.len) return null;
            }
            const to = pattern[index];
            if (previous.? <= to) { try body.append(gpa, '-'); try member(&body, gpa, to); }
            previous = null;
        } else if (char == '[' and index + 1 < pattern.len and pattern[index + 1] == ':') {
            const name_start = index + 2;
            var end = name_start;
            while (end < pattern.len and pattern[end] != ']') : (end += 1) {}
            if (end == pattern.len) return null;
            if (end > name_start and pattern[end - 1] == ':') {
                try ascii(&body, gpa, posix(pattern[name_start .. end - 1]) orelse return null);
                previous = null;
                index = end;
            } else {
                try member(&body, gpa, '[');
                previous = '[';
                index = name_start - 2;
            }
        } else {
            try member(&body, gpa, char);
            previous = char;
        }
        index += 1;
        if (index < pattern.len and pattern[index] == ']') {
            var source: Units = .empty;
            defer source.deinit(gpa);
            try ascii(&source, gpa, if (negated) "[^\\/" else "[");
            try source.appendSlice(gpa, body.items);
            try source.append(gpa, ']');
            const value = try text(scope, source.items);
            const guarded = !negated and scope.truthy(try scope.invoke(try regex(scope, value, ""), "test", &.{try scope.text("/")}));
            return .{ .end = index, .source = if (guarded) try scope.concat(try scope.text("(?!\\/)"), value) else value };
        }
    }
}
fn hold(scope: *Scope, out: *Units, sources: c.JSValue, source: c.JSValue) !void {
    const index = try v.length(scope, sources);
    _ = try scope.invoke(sources, "push", &.{source});
    try out.append(scope.engine.gpa, 0);
    const number = try std.fmt.allocPrint(scope.engine.gpa, "{d}", .{index});
    defer scope.engine.gpa.free(number);
    try ascii(out, scope.engine.gpa, number);
    try out.append(scope.engine.gpa, 0);
}
const Extracted = struct { source: c.JSValue, sources: c.JSValue };
fn extract(scope: *Scope, value: c.JSValue) !Extracted {
    const pattern = try units(scope, value);
    defer scope.engine.gpa.free(pattern);
    var out: Units = .empty;
    defer out.deinit(scope.engine.gpa);
    const sources = try scope.array();
    var index: usize = 0;
    while (index < pattern.len) {
        const char = pattern[index];
        if (char == '\\') {
            // checkPattern admits odd trailing runs >=3, and a pattern getter
            // can change after checking. Source holds its undefined next unit;
            // the eventual genuine replace callback performs the coercion.
            if (index + 1 >= pattern.len) {
                try hold(scope, &out, sources, c.pi_js_undefined());
                index += 2;
                continue;
            }
            const escaped = pattern[index + 1];
            if (escaped == '*' or escaped == '[' or escaped == ' ' or escaped == '\\') {
                try out.appendSlice(scope.engine.gpa, pattern[index .. index + 2]);
            } else {
                var literal: Units = .empty;
                defer literal.deinit(scope.engine.gpa);
                if (escaped < 128 and std.mem.indexOfScalar(u8, ".*+?()[]{}^$|\\/", @intCast(escaped)) != null) try literal.append(scope.engine.gpa, '\\');
                try literal.append(scope.engine.gpa, escaped);
                try hold(scope, &out, sources, try text(scope, literal.items));
            }
            index += 2;
        } else if (char == 0) {
            const literal = [_]u16{ '[', 0, ']' };
            try hold(scope, &out, sources, try text(scope, &literal));
            index += 1;
        } else if (char == '[') {
            if (try bracket(scope, pattern, index)) |scanned| {
                try hold(scope, &out, sources, scanned.source);
                index = scanned.end + 1;
            } else {
                try hold(scope, &out, sources, try scope.text("[]"));
                index = pattern.len;
            }
        } else {
            try out.append(scope.engine.gpa, char);
            index += 1;
        }
    }
    return .{ .source = try text(scope, out.items), .sources = sources };
}
const Replace = enum { literal, trim_spaces, escaped_space, meta, globstar, wildcard, trailing, escaped_bracket, restore };
const Step = struct { pattern: []const u8, flags: []const u8 = "", kind: Replace = .literal, replacement: []const u8 = "" };
const steps = [_]Step{
    .{ .pattern = "^\\uFEFF", .flags = "", .kind = .literal, .replacement = "" },
    .{ .pattern = "[\\r\\n]+$", .flags = "", .kind = .literal, .replacement = "" },
    .{ .pattern = "((?:\\\\\\\\)*?)(\\\\? +)$", .flags = "", .kind = .trim_spaces, .replacement = "" },
    .{ .pattern = "(\\\\+?) ", .flags = "g", .kind = .escaped_space, .replacement = "" },
    .{ .pattern = "[\\\\$.|*+(){^]", .flags = "g", .kind = .meta, .replacement = "" },
    .{ .pattern = "(?!\\\\)\\?", .flags = "g", .kind = .literal, .replacement = "[^/]" },
    .{ .pattern = "^\\/", .flags = "", .kind = .literal, .replacement = "^" },
    .{ .pattern = "\\/", .flags = "g", .kind = .literal, .replacement = "\\/" },
    .{ .pattern = "^\\^*(?:\\\\\\*\\\\\\*\\\\\\/)+", .flags = "", .kind = .literal, .replacement = "^(?:.*\\/)?" },
};
const remaining = [_]Step{
    .{ .pattern = "\\\\\\/\\\\\\*\\\\\\*(?=\\\\\\/|$)", .flags = "g", .kind = .globstar, .replacement = "" },
    .{ .pattern = "(^|[^\\\\]+)(\\\\\\*)+(?=.+)", .flags = "g", .kind = .wildcard, .replacement = "" },
    .{ .pattern = "(^|[^\\\\])((?:\\\\\\\\)*)\\\\\\*$", .flags = "", .kind = .trailing, .replacement = "" },
    .{ .pattern = "\\\\\\\\\\\\(?=[$.|*+(){^])", .flags = "g", .kind = .literal, .replacement = "\\" },
    .{ .pattern = "\\\\\\\\", .flags = "g", .kind = .literal, .replacement = "\\" },
    .{ .pattern = "\\\\\\[([^\\]/]*?)(\\\\*)($|\\])", .flags = "g", .kind = .escaped_bracket, .replacement = "" },
};
fn slice(scope: *Scope, value: c.JSValue, start: u32, end: ?u32) !c.JSValue {
    return scope.invoke(value, "slice", if (end) |last| &.{ c.JS_NewUint32(scope.engine.context, start), c.JS_NewUint32(scope.engine.context, last) } else &.{c.JS_NewUint32(scope.engine.context, start)});
}
fn replaceCallback(engine: *v.em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    var raw_kind: u32 = 0;
    if (c.JS_ToUint32(engine.context, &raw_kind, roots[0]) < 0) return v.js.capture(engine);
    const kind: Replace = @enumFromInt(raw_kind);
    const result = switch (kind) {
        .literal => roots[1],
        .trim_spaces => try scope.concat(args[1], if (scope.truthy(try scope.invoke(args[2], "startsWith", &.{try scope.text("\\")}))) try scope.text(" ") else try scope.text("")),
        .escaped_space => try scope.concat(try slice(&scope, args[1], 0, (try v.length(&scope, args[1])) & ~@as(u32, 1)), try scope.text(" ")),
        .meta => try scope.concat(try scope.text("\\"), args[0]),
        .globstar => block: {
            var index: u32 = 0;
            if (c.JS_ToUint32(engine.context, &index, args[1]) < 0) return v.js.capture(engine);
            break :block try scope.text(if (index + 6 < try v.length(&scope, args[2])) if (try v.eq(&scope, try slice(&scope, args[2], index + 6, null), "\\/")) "(?:\\/[^\\/]+)+" else "(?:\\/[^\\/]+)*" else "\\/.+");
        },
        .wildcard => block: {
            const star = try regex(&scope, try scope.text("\\\\\\*"), "g");
            break :block try scope.concat(args[1], try scope.invoke(args[2], "replace", &.{ star, try scope.text("[^\\/]*") }));
        },
        .trailing => if (((try v.length(&scope, args[2])) / 2) % 2 == 0) try scope.concat(try scope.concat(args[1], args[2]), try scope.text(marker)) else args[0],
        .escaped_bracket => try scope.concat(try scope.concat(try scope.concat(try scope.text("\\["), args[1]), try slice(&scope, args[2], 0, (try v.length(&scope, args[2])) & ~@as(u32, 1))), args[3]),
        .restore => block: {
            var index: u32 = 0;
            if (c.JS_ToUint32(engine.context, &index, args[1]) < 0) return v.js.capture(engine);
            break :block try v.at(&scope, roots[1], index);
        },
    };
    return c.JS_DupValue(engine.context, result);
}
fn replace(scope: *Scope, value: c.JSValue, step: Step, extra: ?c.JSValue) !c.JSValue {
    const expression = try regex(scope, try scope.text(step.pattern), step.flags);
    if (!scope.truthy(try scope.invoke(expression, "test", &.{value}))) return value;
    const function = try scope.own(try @import("native_node_function.zig").createArrow(scope.engine, "", 0, replaceCallback, &.{ c.JS_NewUint32(scope.engine.context, @intFromEnum(step.kind)), extra orelse try scope.text(step.replacement) }));
    return scope.invoke(value, "replace", &.{ expression, function });
}
pub fn prefix(scope: *Scope, pattern: c.JSValue) !c.JSValue {
    const extracted = try extract(scope, pattern);
    var source = extracted.source;
    for (steps) |step| source = try replace(scope, source, step, null);
    if (try v.length(scope, source) > 0 and !scope.truthy(try scope.invoke(source, "startsWith", &.{try scope.text("^")}))) {
        source = try scope.concat(try scope.text(if (try matches(scope, "/(?!$)", "", pattern)) "^" else "(?:^|\\/)"), source);
    }
    for (remaining) |step| source = try replace(scope, source, step, null);
    const length = try v.length(scope, source);
    if (length > 0) {
        const last = try slice(scope, source, length - 1, null);
        if (!try v.eq(scope, last, marker)) source = try scope.concat(source, try scope.text(if (try v.eq(scope, last, "/")) "$" else "(?=$|\\/$)"));
    }
    if (try v.length(scope, extracted.sources) > 0) source = try replace(scope, source, .{ .pattern = "\x00(\\d+)\x00", .flags = "g", .kind = .restore }, extracted.sources);
    return source;
}
const Token = struct { start: usize, end: usize, wildcard: bool = false, boundary: bool = false };
fn starts(value: []const u16, index: usize, wanted: []const u8) bool {
    if (wanted.len > value.len - index) return false;
    for (value[index..][0..wanted.len], wanted) |left, right| if (left != right) return false;
    return true;
}
fn flush(gpa: std.mem.Allocator, out: *Units, source: []const u16, run: []const Token) !void {
    var last: ?usize = null;
    for (run, 0..) |token, index| if (token.wildcard) { last = index; };
    for (run, 0..) |token, index| {
        if (!token.wildcard or (last != null and index == last.?)) {
            try out.appendSlice(gpa, source[token.start..token.end]);
        } else {
            try ascii(out, gpa, "(?:(?!");
            try out.appendSlice(gpa, source[run[index + 1].start..run[index + 1].end]);
            try ascii(out, gpa, ")[^\\/])*");
        }
    }
}
fn pin(scope: *Scope, value: c.JSValue) !c.JSValue {
    const source = try units(scope, value);
    defer scope.engine.gpa.free(source);
    var run: std.ArrayList(Token) = .empty;
    defer run.deinit(scope.engine.gpa);
    var out: Units = .empty;
    defer out.deinit(scope.engine.gpa);
    var index: usize = 0;
    while (index < source.len) {
        var token: Token = .{ .start = index, .end = index + 1 };
        const char = source[index];
        if (starts(source, index, "[^\\/]*")) {
            token.wildcard = true;
            token.end = index + 6;
        } else if (char == '[') {
            var end = index + 1;
            if (end < source.len and source[end] == '^') end += 1;
            if (end < source.len and source[end] == ']') end += 1;
            while (end < source.len and source[end] != ']') end += if (source[end] == '\\') @as(usize, 2) else 1;
            token.end = @min(end + 1, source.len);
        } else if (char == '\\') {
            token.end = @min(index + 2, source.len);
        } else if (char == '(') {
            var depth: usize = 0;
            var end = index;
            while (true) {
                if (source[end] == '\\') { end += 1; } else if (source[end] == '(') { depth += 1; } else if (source[end] == ')') { depth -= 1; }
                end += 1;
                if (end >= source.len or depth == 0) break;
            }
            if (end < source.len and (source[end] == '*' or source[end] == '+' or source[end] == '?')) end += 1;
            // Source's slice(index,end) clamps an off-end escape to length.
            token.end = @min(end, source.len);
            token.boundary = true;
        } else if (char == '^' or char == '$') token.boundary = true;
        if (token.boundary) {
            try flush(scope.engine.gpa, &out, source, run.items);
            run.clearRetainingCapacity();
            try out.appendSlice(scope.engine.gpa, source[token.start..token.end]);
        } else try run.append(scope.engine.gpa, token);
        index = token.end;
    }
    try flush(scope.engine.gpa, &out, source, run.items);
    return text(scope, out.items);
}
pub fn compile(scope: *Scope, prefix_value: c.JSValue, ignore_case: bool, check: bool) !c.JSValue {
    const length = try v.length(scope, prefix_value);
    var source = prefix_value;
    if (length > 0 and try v.eq(scope, try slice(scope, source, length - 1, null), marker)) {
        const before = try slice(scope, source, 0, length - 1);
        const leading = try v.eq(scope, before, "");
        const slash = scope.truthy(try scope.invoke(before, "endsWith", &.{try scope.text("\\/")}));
        source = try scope.concat(before, try scope.text(if ((leading or slash) and !check) "[^/]+(?=$|\\/$)" else "[^/]*(?=$|\\/$)"));
    }
    return regex(scope, try pin(scope, source), if (ignore_case) "i" else "");
}
