//! jsonc-parser 3.3.1 parse() default scanner and recovery, used by get-tsconfig.
//! Diagnostics are discarded by the original caller, not turned into JSON errors.
//! Copyright Microsoft Corporation; MIT authority is retained with this port.
const std = @import("std");
const v = @import("native_ai_provider_values.zig");
const c = v.c;
const Kind = enum { object, end_object, array, end_array, comma, colon, string, number, yes, no, nil, eof };
const Parser = struct {
    engine: *v.em.Engine, text: []const u16, pos: usize = 0,
    token: Kind = .eof, value: c.JSValue, steps: usize = 0,
    fn unit(self: *Parser, at: usize) u16 { return if (at < self.text.len) self.text[at] else 0xffff; }
    fn pulse(self: *Parser) !void {
        self.steps +|= 1;
        if (self.engine.cancelled.load(.acquire) or (self.steps % 256 == 0 and blk: { self.engine.interrupts +|= 1; break :blk self.engine.interrupts > self.engine.options.interrupt_budget; })) {
            _ = c.JS_ThrowInternalError(self.engine.context, "interrupted");
            const reason = c.JS_GetException(self.engine.context); c.JS_SetUncatchableError(self.engine.context, reason);
            _ = try self.engine.checked(c.JS_Throw(self.engine.context, reason)); unreachable;
        }
    }
    fn string(self: *Parser) !c.JSValue {
        var decoded: std.ArrayList(u16) = .empty; defer decoded.deinit(self.engine.gpa);
        while (self.pos < self.text.len) {
            try self.pulse();
            const char = self.text[self.pos];
            if (char == '"') { self.pos += 1; break; }
            if (char == '\r' or char == '\n') break;
            self.pos += 1;
            if (char != '\\') { try decoded.append(self.engine.gpa, char); continue; }
            if (self.pos == self.text.len) break;
            const escaped = self.text[self.pos]; self.pos += 1;
            switch (escaped) {
                '"', '\\', '/' => try decoded.append(self.engine.gpa, escaped),
                'b' => try decoded.append(self.engine.gpa, 8), 'f' => try decoded.append(self.engine.gpa, 12),
                'n' => try decoded.append(self.engine.gpa, 10), 'r' => try decoded.append(self.engine.gpa, 13),
                't' => try decoded.append(self.engine.gpa, 9),
                'u' => {
                    var code: u16 = 0; var count: usize = 0;
                    while (count < 4) : (count += 1) {
                        const digit = hex(self.unit(self.pos)) orelse break;
                        code = code * 16 + digit; self.pos += 1;
                    }
                    if (count == 4) try decoded.append(self.engine.gpa, code);
                },
                else => {}, // Scanner records InvalidEscapeCharacter and drops it.
            }
        }
        return self.engine.checked(c.JS_NewStringUTF16(self.engine.context, decoded.items.ptr, decoded.items.len));
    }
    fn next(self: *Parser) !void {
        self.engine.freeValue(self.value); self.value = c.pi_js_undefined();
        while (true) {
            try self.pulse();
            if (self.pos >= self.text.len) { self.token = .eof; return; }
            const ch = self.text[self.pos]; self.pos += 1;
            switch (ch) {
                ' ', '\t', '\r', '\n' => continue,
                '{' => self.token = .object, '}' => self.token = .end_object,
                '[' => self.token = .array, ']' => self.token = .end_array,
                ',' => self.token = .comma, ':' => self.token = .colon,
                '"' => { self.token = .string; self.value = try self.string(); },
                '/' => {
                    if (self.unit(self.pos) == '/') {
                        self.pos += 1;
                        while (self.pos < self.text.len and self.unit(self.pos) != '\r' and self.unit(self.pos) != '\n') : (self.pos += 1) try self.pulse();
                    } else if (self.unit(self.pos) == '*') {
                        self.pos += 1;
                        while (self.pos < self.text.len) {
                            try self.pulse();
                            if (self.unit(self.pos) == '*' and self.unit(self.pos + 1) == '/') { self.pos += 2; break; }
                            self.pos += 1;
                        }
                    }
                    continue;
                },
                '-', '0'...'9' => {
                    const start = self.pos - 1;
                    if (ch == '-' and !digit(self.unit(self.pos))) continue;
                    if (ch == '-') self.pos += 1;
                    const first = if (ch == '-') self.text[start + 1] else ch;
                    if (first != '0') while (digit(self.unit(self.pos))) : (self.pos += 1) try self.pulse();
                    if (self.unit(self.pos) == '.') {
                        self.pos += 1;
                        if (!digit(self.unit(self.pos))) {
                            try self.number(start, self.pos); return;
                        }
                        while (digit(self.unit(self.pos))) : (self.pos += 1) try self.pulse();
                    }
                    var end = self.pos;
                    if (self.unit(self.pos) == 'e' or self.unit(self.pos) == 'E') {
                        self.pos += 1;
                        if (self.unit(self.pos) == '+' or self.unit(self.pos) == '-') self.pos += 1;
                        if (digit(self.unit(self.pos))) {
                            while (digit(self.unit(self.pos))) : (self.pos += 1) try self.pulse();
                            end = self.pos;
                        }
                    }
                    try self.number(start, end);
                },
                else => {
                    const start = self.pos - 1;
                    while (self.pos < self.text.len and unknown(self.unit(self.pos))) : (self.pos += 1) try self.pulse();
                    const word = self.text[start..self.pos];
                    if (equal(word, "null")) self.token = .nil else if (equal(word, "true")) self.token = .yes else if (equal(word, "false")) self.token = .no else continue;
                },
            }
            return;
        }
    }
    fn number(self: *Parser, start: usize, end: usize) !void {
        const raw = try self.engine.checked(c.JS_NewStringUTF16(self.engine.context, self.text[start..end].ptr, end - start)); defer self.engine.freeValue(raw);
        var value: f64 = 0;
        if (c.JS_ToFloat64(self.engine.context, &value, raw) < 0) return v.js.capture(self.engine);
        if (std.math.isNan(value)) value = 0;
        self.value = c.JS_NewFloat64(self.engine.context, value); self.token = .number;
    }
    fn recover(self: *Parser, closing: Kind) !void {
        while (self.token != .eof and self.token != closing and self.token != .comma) try self.next();
    }
    fn parseValue(self: *Parser, depth: usize) anyerror!?c.JSValue {
        try self.pulse();
        if (depth > 256) {
            _ = c.JS_ThrowRangeError(self.engine.context, "Native tsconfig JSONC nesting quota exceeded");
            const reason = c.JS_GetException(self.engine.context); c.JS_SetUncatchableError(self.engine.context, reason);
            _ = try self.engine.checked(c.JS_Throw(self.engine.context, reason)); unreachable;
        }
        switch (self.token) {
            .object, .array => {
                const array = self.token == .array;
                const closing: Kind = if (array) .end_array else .end_object;
                const result = if (array) try v.js.array(self.engine) else try v.js.object(self.engine);
                errdefer self.engine.freeValue(result);
                try self.next();
                var index: u32 = 0;
                while (self.token != closing and self.token != .eof) {
                    if (self.token == .comma) try self.next();
                    if (array) {
                        if (try self.parseValue(depth + 1)) |item| {
                            if (c.JS_DefinePropertyValueUint32(self.engine.context, result, index, item, c.JS_PROP_C_W_E) < 0) return v.js.capture(self.engine);
                            index += 1;
                        } else try self.recover(closing);
                    } else if (self.token == .string) {
                        const name = c.JS_DupValue(self.engine.context, self.value); defer self.engine.freeValue(name);
                        try self.next();
                        if (self.token == .colon) {
                            try self.next();
                            if (try self.parseValue(depth + 1)) |item| {
                                defer self.engine.freeValue(item);
                                try v.js.setKey(self.engine, result, name, item);
                            } else try self.recover(closing);
                        } else try self.recover(closing);
                    } else try self.recover(closing);
                }
                if (self.token == closing) try self.next();
                return result;
            },
            .string, .number => { const result = c.JS_DupValue(self.engine.context, self.value); errdefer self.engine.freeValue(result); try self.next(); return result; },
            .nil, .yes, .no => { const result = if (self.token == .nil) c.pi_js_null() else c.pi_js_bool(self.engine.context, @intFromBool(self.token == .yes)); try self.next(); return result; },
            else => return null,
        }
    }
};
fn digit(ch: u16) bool { return ch >= '0' and ch <= '9'; }
fn hex(ch: u16) ?u16 { return if (digit(ch)) ch - '0' else if (ch >= 'a' and ch <= 'f') ch - 'a' + 10 else if (ch >= 'A' and ch <= 'F') ch - 'A' + 10 else null; }
fn equal(units: []const u16, ascii: []const u8) bool { if (units.len != ascii.len) return false; for (units, ascii) |a, b| if (a != b) return false; return true; }
fn unknown(ch: u16) bool { return switch (ch) { ' ', '\t', '\r', '\n', '{', '}', '[', ']', '"', ':', ',', '/' => false, else => true }; }
pub fn parse(engine: *v.em.Engine, text: c.JSValue) !c.JSValue {
    var length: usize = 0; const units = c.JS_ToCStringLenUTF16(engine.context, &length, text);
    if (units == null) return v.js.capture(engine);
    defer c.JS_FreeCStringUTF16(engine.context, units);
    var parser: Parser = .{ .engine = engine, .text = units[0..length], .value = c.pi_js_undefined() };
    defer engine.freeValue(parser.value);
    try parser.next(); return (try parser.parseValue(0)) orelse c.pi_js_undefined();
}
