//! Source-only draft. Pinned Node24/V8 JSON diagnostic grammar over UTF-16.
//! Does not parse values, execute revivers, or replace application JSON.parse.
//! Authority: nodejs/node v24.14.0 deps/v8/src/json/json-parser.{cc,h}
//! and deps/v8/src/common/message-template.h. Qualification pending.
const std = @import("std");
pub const Kind = enum {
    unexpected,
    object_first_key,
    object_next_key,
    colon,
    object_end,
    array_end,
    unterminated_string,
    control,
    escape,
    unicode,
    minus,
    fraction,
    exponent,
    trailing,
};
pub const Failure = struct { kind: Kind, position: usize };
const Phase = enum { value, object_first, object_next, object_colon, object_value, object_after, array_first, array_next, array_after, done };
const Lexer = struct {
    text: []const u16,
    position: usize = 0,
    fn current(self: *Lexer) ?u16 {
        return if (self.position < self.text.len) self.text[self.position] else null;
    }
    fn skip(self: *Lexer) void {
        while (self.current()) |char| {
            switch (char) {
                0x09, 0x0a, 0x0d, 0x20 => self.position += 1,
                else => return,
            }
        }
    }
    fn fail(self: *Lexer, kind: Kind) Failure {
        return .{ .kind = kind, .position = self.position };
    }
    fn string(self: *Lexer) ?Failure {
        self.position += 1;
        while (self.current()) |char| {
            if (char == '"') {
                self.position += 1;
                return null;
            }
            if (char < 0x20) return self.fail(.control);
            if (char == '\\') {
                self.position += 1;
                const escaped = self.current() orelse return self.fail(.unterminated_string);
                switch (escaped) {
                    '"', '\\', '/', 'b', 'f', 'n', 'r', 't' => self.position += 1,
                    'u' => {
                        self.position += 1;
                        for (0..4) |_| {
                            const digit = self.current() orelse return self.fail(.unicode);
                            if (!hex(digit)) return self.fail(.unicode);
                            self.position += 1;
                        }
                    },
                    else => return self.fail(.escape),
                }
            } else self.position += 1;
        }
        return self.fail(.unterminated_string);
    }
    fn literal(self: *Lexer, word: []const u8) ?Failure {
        for (word) |char| {
            if (self.current() != char) return self.fail(.unexpected);
            self.position += 1;
        }
        return null;
    }
    fn number(self: *Lexer) ?Failure {
        if (self.current() == '-') {
            self.position += 1;
            if (!decimal(self.current())) return self.fail(.minus);
        }
        if (self.current() == '0') {
            self.position += 1;
            if (decimal(self.current())) return self.fail(.unexpected);
        } else while (decimal(self.current())) self.position += 1;
        if (self.current() == '.') {
            self.position += 1;
            if (!decimal(self.current())) return self.fail(.fraction);
            while (decimal(self.current())) self.position += 1;
        }
        if (self.current() == 'e' or self.current() == 'E') {
            self.position += 1;
            if (self.current() == '+' or self.current() == '-') self.position += 1;
            if (!decimal(self.current())) return self.fail(.exponent);
            while (decimal(self.current())) self.position += 1;
        }
        return null;
    }
};
fn decimal(char: ?u16) bool {
    return if (char) |value| value >= '0' and value <= '9' else false;
}
fn hex(char: u16) bool {
    return decimal(char) or (char >= 'a' and char <= 'f') or (char >= 'A' and char <= 'F');
}
pub fn diagnose(gpa: std.mem.Allocator, text: []const u16) !?Failure {
    var lexer: Lexer = .{ .text = text };
    var stack: std.ArrayList(Phase) = .empty;
    defer stack.deinit(gpa);
    try stack.append(gpa, .done);
    var phase: Phase = .value;
    while (true) {
        lexer.skip();
        switch (phase) {
            .done => return if (lexer.current() != null) lexer.fail(.trailing) else null,
            .value, .object_value, .array_next, .array_first => {
                if (phase == .array_first and lexer.current() == ']') {
                    lexer.position += 1;
                    phase = stack.pop().?;
                    continue;
                }
                if (phase == .array_first) try stack.append(gpa, .array_after);
                const char = lexer.current() orelse return lexer.fail(.unexpected);
                switch (char) {
                    '{' => {
                        lexer.position += 1;
                        phase = .object_first;
                    },
                    '[' => {
                        lexer.position += 1;
                        phase = .array_first;
                    },
                    '"' => {
                        if (lexer.string()) |failure| return failure;
                        phase = stack.pop().?;
                    },
                    '-', '0'...'9' => {
                        if (lexer.number()) |failure| return failure;
                        phase = stack.pop().?;
                    },
                    't', 'f', 'n' => {
                        if (lexer.literal(switch (char) {
                            't' => "true",
                            'f' => "false",
                            else => "null",
                        })) |failure| return failure;
                        phase = stack.pop().?;
                    },
                    else => return lexer.fail(.unexpected),
                }
            },
            .object_first, .object_next => {
                if (phase == .object_first and lexer.current() == '}') {
                    lexer.position += 1;
                    phase = stack.pop().?;
                    continue;
                }
                if (lexer.current() != '"') return lexer.fail(if (phase == .object_first) .object_first_key else .object_next_key);
                if (lexer.string()) |failure| return failure;
                phase = .object_colon;
            },
            .object_colon => {
                if (lexer.current() != ':') return lexer.fail(.colon);
                lexer.position += 1;
                try stack.append(gpa, .object_after);
                phase = .object_value;
            },
            .object_after => switch (lexer.current() orelse 0) {
                '}' => {
                    lexer.position += 1;
                    phase = stack.pop().?;
                },
                ',' => {
                    lexer.position += 1;
                    phase = .object_next;
                },
                else => return lexer.fail(.object_end),
            },
            .array_after => switch (lexer.current() orelse 0) {
                ']' => {
                    lexer.position += 1;
                    phase = stack.pop().?;
                },
                ',' => {
                    lexer.position += 1;
                    try stack.append(gpa, .array_after);
                    phase = .array_next;
                },
                else => return lexer.fail(.array_end),
            },
        }
    }
}
fn ascii(output: *std.ArrayList(u16), gpa: std.mem.Allocator, value: []const u8) !void {
    for (value) |byte| try output.append(gpa, byte);
}
fn numeric(output: *std.ArrayList(u16), gpa: std.mem.Allocator, value: usize) !void {
    var buffer: [32]u8 = undefined;
    try ascii(output, gpa, try std.fmt.bufPrint(&buffer, "{d}", .{value}));
}
pub fn render(gpa: std.mem.Allocator, text: []const u16, failure: Failure) ![]u16 {
    var output: std.ArrayList(u16) = .empty;
    errdefer output.deinit(gpa);
    const pos = failure.position;
    if (failure.kind == .unexpected) {
        if (pos == text.len) {
            try ascii(&output, gpa, "Unexpected end of JSON input");
            return output.toOwnedSlice(gpa);
        }
        const char = text[pos];
        if (!decimal(char) and char != '-' and char != '"') {
            var special = false;
            for ([_][]const u8{ "undefined", "NaN", "Infinity", "[object Object]" }) |word| {
                if (text.len != word.len) continue;
                special = for (text, word) |left, right| {
                    if (left != right) break false;
                } else true;
                if (special) break;
            }
            if (special) {
                try ascii(&output, gpa, "\"");
                try output.appendSlice(gpa, text);
                try ascii(&output, gpa, "\" is not valid JSON");
            } else {
                try ascii(&output, gpa, "Unexpected token '");
                try output.append(gpa, char);
                try ascii(&output, gpa, "', ");
                const context = text.len >= 21;
                if (context and pos >= 10) try ascii(&output, gpa, "...");
                try ascii(&output, gpa, "\"");
                const start = if (context and pos >= 10) pos - 10 else 0;
                const end = if (context and pos < text.len - 10) pos + 10 else text.len;
                try output.appendSlice(gpa, text[start..end]);
                try ascii(&output, gpa, "\"");
                if (context and pos < text.len - 10) try ascii(&output, gpa, "...");
                try ascii(&output, gpa, " is not valid JSON");
            }
            return output.toOwnedSlice(gpa);
        }
        try ascii(&output, gpa, if (char == '"') "Unexpected string in JSON" else "Unexpected number in JSON");
    } else try ascii(&output, gpa, switch (failure.kind) {
        .object_first_key => "Expected property name or '}' in JSON",
        .object_next_key => "Expected double-quoted property name in JSON",
        .colon => "Expected ':' after property name in JSON",
        .object_end => "Expected ',' or '}' after property value in JSON",
        .array_end => "Expected ',' or ']' after array element in JSON",
        .unterminated_string => "Unterminated string in JSON",
        .control => "Bad control character in string literal in JSON",
        .escape => "Bad escaped character in JSON",
        .unicode => "Bad Unicode escape in JSON",
        .minus => "No number after minus sign in JSON",
        .fraction => "Unterminated fractional number in JSON",
        .exponent => "Exponent part is missing a number in JSON",
        .trailing => "Unexpected non-whitespace character after JSON",
        .unexpected => unreachable,
    });
    var line: usize = 1;
    var last: usize = 0;
    var index: usize = 0;
    while (index < pos) : (index += 1) {
        if (text[index] == '\r' and index + 1 < pos and text[index + 1] == '\n') index += 1;
        if (text[index] == '\r' or text[index] == '\n') {
            line += 1;
            last = index + 1;
        }
    }
    try ascii(&output, gpa, " at position ");
    try numeric(&output, gpa, pos);
    try ascii(&output, gpa, " (line ");
    try numeric(&output, gpa, line);
    try ascii(&output, gpa, " column ");
    try numeric(&output, gpa, 1 + pos - last);
    try ascii(&output, gpa, ")");
    return output.toOwnedSlice(gpa);
}
