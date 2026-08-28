//! Repair provider-emitted tool arguments before they become durable session data.
//!
//! Providers occasionally emit malformed JSON string literals (raw control bytes,
//! invalid escapes) or terminate a tool call mid-object. The agent expects a JSON
//! object string, so normalize once at the ModelClient boundary.
const std = @import("std");

fn isHex(c: u8) bool {
    return (c >= '0' and c <= '9') or (c >= 'a' and c <= 'f') or (c >= 'A' and c <= 'F');
}

fn isValidEscape(c: u8) bool {
    return switch (c) {
        '"', '\\', '/', 'b', 'f', 'n', 'r', 't' => true,
        else => false,
    };
}

fn writeControl(writer: *std.Io.Writer, c: u8) !void {
    switch (c) {
        '\x08' => try writer.writeAll("\\b"),
        '\x0c' => try writer.writeAll("\\f"),
        '\n' => try writer.writeAll("\\n"),
        '\r' => try writer.writeAll("\\r"),
        '\t' => try writer.writeAll("\\t"),
        else => try writer.print("\\u{x:0>4}", .{@as(u16, c)}),
    }
}

/// Mirrors upstream repairJson(): escape raw control characters inside JSON
/// strings and preserve invalid backslashes as literal backslashes.
pub fn repairMalformed(gpa: std.mem.Allocator, input: []const u8) ![]u8 {
    var out: std.Io.Writer.Allocating = .init(gpa);
    errdefer out.deinit();
    var in_string = false;
    var i: usize = 0;
    while (i < input.len) {
        const c = input[i];
        if (!in_string) {
            try out.writer.writeByte(c);
            if (c == '"') in_string = true;
            i += 1;
            continue;
        }
        if (c == '"') {
            try out.writer.writeByte(c);
            in_string = false;
            i += 1;
            continue;
        }
        if (c == '\\') {
            if (i + 1 >= input.len) {
                try out.writer.writeAll("\\\\");
                i += 1;
                continue;
            }
            const next = input[i + 1];
            if (next == 'u' and i + 5 < input.len and
                isHex(input[i + 2]) and isHex(input[i + 3]) and isHex(input[i + 4]) and isHex(input[i + 5]))
            {
                try out.writer.writeAll(input[i .. i + 6]);
                i += 6;
                continue;
            }
            if (isValidEscape(next)) {
                try out.writer.writeAll(input[i .. i + 2]);
                i += 2;
                continue;
            }
            // Do not consume the following byte. The doubled slash makes the
            // original slash literal and the following byte is processed next.
            try out.writer.writeAll("\\\\");
            i += 1;
            continue;
        }
        if (c <= 0x1f) {
            try writeControl(&out.writer, c);
        } else {
            try out.writer.writeByte(c);
        }
        i += 1;
    }
    return out.toOwnedSlice();
}

fn isValidObject(gpa: std.mem.Allocator, input: []const u8) bool {
    var parsed = std.json.parseFromSlice(std.json.Value, gpa, input, .{}) catch return false;
    defer parsed.deinit();
    return parsed.value == .object;
}

/// Close an otherwise syntactically-complete prefix by terminating a dangling
/// string and every still-open array/object. Returns null for mismatched closers.
fn closePrefix(gpa: std.mem.Allocator, input: []const u8) !?[]u8 {
    const trimmed = std.mem.trimEnd(u8, input, " \t\r\n");
    var stack: std.ArrayList(u8) = .empty;
    defer stack.deinit(gpa);
    var in_string = false;
    var i: usize = 0;
    while (i < trimmed.len) : (i += 1) {
        const c = trimmed[i];
        if (in_string) {
            if (c == '\\') {
                if (i + 1 < trimmed.len) i += 1;
            } else if (c == '"') {
                in_string = false;
            }
            continue;
        }
        switch (c) {
            '"' => in_string = true,
            '{', '[' => try stack.append(gpa, c),
            '}' => {
                const top = stack.pop() orelse return null;
                if (top != '{') return null;
            },
            ']' => {
                const top = stack.pop() orelse return null;
                if (top != '[') return null;
            },
            else => {},
        }
    }

    var out: std.Io.Writer.Allocating = .init(gpa);
    errdefer out.deinit();
    try out.writer.writeAll(trimmed);
    if (in_string) try out.writer.writeByte('"');
    while (stack.pop()) |open| try out.writer.writeByte(if (open == '{') '}' else ']');
    return try out.toOwnedSlice();
}

fn collectSafeCutoffs(gpa: std.mem.Allocator, input: []const u8) ![]usize {
    var cuts: std.ArrayList(usize) = .empty;
    errdefer cuts.deinit(gpa);
    var in_string = false;
    var i: usize = 0;
    while (i < input.len) : (i += 1) {
        const c = input[i];
        if (in_string) {
            if (c == '\\') {
                if (i + 1 < input.len) i += 1;
            } else if (c == '"') in_string = false;
            continue;
        }
        switch (c) {
            '"' => in_string = true,
            // Before a comma preserves all complete values before the current
            // incomplete member/item. Immediately after an opener permits an
            // empty object/array as the final fallback for that nesting level.
            ',' => try cuts.append(gpa, i),
            '{', '[' => try cuts.append(gpa, i + 1),
            else => {},
        }
    }
    return cuts.toOwnedSlice(gpa);
}

/// Return an allocator-owned valid JSON object. Valid input is preserved byte for
/// byte; malformed string literals are repaired; truncated structures retain the
/// longest valid prefix possible. Unrecoverable/scalar input becomes `{}`.
pub fn normalize(gpa: std.mem.Allocator, input: []const u8) ![]u8 {
    const trimmed = std.mem.trim(u8, input, " \t\r\n");
    if (trimmed.len == 0) return gpa.dupe(u8, "{}");
    if (isValidObject(gpa, trimmed)) return gpa.dupe(u8, trimmed);

    const repaired = try repairMalformed(gpa, trimmed);
    defer gpa.free(repaired);
    if (isValidObject(gpa, repaired)) return gpa.dupe(u8, repaired);

    if (try closePrefix(gpa, repaired)) |candidate| {
        if (isValidObject(gpa, candidate)) return candidate;
        gpa.free(candidate);
    }

    const cuts = try collectSafeCutoffs(gpa, repaired);
    defer gpa.free(cuts);
    var n = cuts.len;
    while (n > 0) {
        n -= 1;
        const cutoff = cuts[n];
        if (try closePrefix(gpa, repaired[0..cutoff])) |candidate| {
            if (isValidObject(gpa, candidate)) return candidate;
            gpa.free(candidate);
        }
    }
    return gpa.dupe(u8, "{}");
}

test "repair malformed escapes and raw controls" {
    const gpa = std.testing.allocator;
    const input = "{\"path\":\"C:\\q\",\"line\":\"a\tb\"}";
    const got = try normalize(gpa, input);
    defer gpa.free(got);
    try std.testing.expectEqualStrings("{\"path\":\"C:\\\\q\",\"line\":\"a\\tb\"}", got);
    try std.testing.expect(isValidObject(gpa, got));
}

test "complete truncated object string and nested array" {
    const gpa = std.testing.allocator;
    const string_cut = try normalize(gpa, "{\"value\":\"hel");
    defer gpa.free(string_cut);
    try std.testing.expectEqualStrings("{\"value\":\"hel\"}", string_cut);

    const nested_cut = try normalize(gpa, "{\"values\":[1,2,");
    defer gpa.free(nested_cut);
    try std.testing.expectEqualStrings("{\"values\":[1,2]}", nested_cut);
}

test "drop incomplete final member and reject scalar" {
    const gpa = std.testing.allocator;
    const member_cut = try normalize(gpa, "{\"ok\":1,\"missing\":");
    defer gpa.free(member_cut);
    try std.testing.expectEqualStrings("{\"ok\":1}", member_cut);

    const scalar = try normalize(gpa, "true");
    defer gpa.free(scalar);
    try std.testing.expectEqualStrings("{}", scalar);
}
