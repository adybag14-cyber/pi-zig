// Copyright Joyent, Inc. and other Node contributors. MIT; retained Node LICENSE.
//! Native field extraction for Node24 node_modules.cc PackageConfig. Preserve
//! ordered duplicate-field checks and raw object/array imports/exports; parsing
//! a final JS object first would erase those actual source distinctions.
const std = @import("std");
pub const Fields = struct {
    name: ?[]u8 = null,
    main: ?[]u8 = null,
    kind: enum { none, commonjs, module } = .none,
    imports: ?[]u8 = null,
    exports: ?[]u8 = null,
    pub fn deinit(self: *Fields, gpa: std.mem.Allocator) void {
        inline for (.{ "name", "main", "imports", "exports" }) |field| if (@field(self, field)) |value| {
            @field(self, field) = null;
            gpa.free(value);
        };
    }
};
const Parser = struct {
    bytes: []const u8,
    cursor: usize = 0,
    fn whitespace(self: *Parser) void {
        while (self.cursor < self.bytes.len and switch (self.bytes[self.cursor]) { ' ', '\t', '\r', '\n' => true, else => false }) self.cursor += 1;
    }
    fn byte(self: *Parser, expected: u8) !void {
        self.whitespace();
        if (self.cursor >= self.bytes.len or self.bytes[self.cursor] != expected) return error.InvalidNativePackageJson;
        self.cursor += 1;
    }
    fn string(self: *Parser) ![]const u8 {
        self.whitespace();
        const start = self.cursor;
        try self.byte('"');
        while (self.cursor < self.bytes.len) {
            const character = self.bytes[self.cursor]; self.cursor += 1;
            if (character == '"') return self.bytes[start..self.cursor];
            if (character < 0x20) return error.InvalidNativePackageJson;
            if (character == '\\') {
                if (self.cursor == self.bytes.len) return error.InvalidNativePackageJson;
                const escape = self.bytes[self.cursor]; self.cursor += 1;
                switch (escape) {
                    '"', '\\', '/', 'b', 'f', 'n', 'r', 't' => {},
                    'u' => {
                        if (self.bytes.len - self.cursor < 4) return error.InvalidNativePackageJson;
                        for (self.bytes[self.cursor..][0..4]) |digit| if (!std.ascii.isHex(digit)) return error.InvalidNativePackageJson;
                        self.cursor += 4;
                    },
                    else => return error.InvalidNativePackageJson,
                }
            }
        }
        return error.InvalidNativePackageJson;
    }
    fn digits(self: *Parser) usize {
        const start = self.cursor;
        while (self.cursor < self.bytes.len and std.ascii.isDigit(self.bytes[self.cursor])) self.cursor += 1;
        return self.cursor - start;
    }
    fn value(self: *Parser, depth: usize) anyerror![]const u8 {
        self.whitespace();
        const start = self.cursor;
        if (start == self.bytes.len) return error.InvalidNativePackageJson;
        if (depth > 1024 and (self.bytes[start] == '{' or self.bytes[start] == '[')) return error.InvalidNativePackageJson;
        switch (self.bytes[start]) {
            '"' => return self.string(),
            '{', '[' => |opening| {
                self.cursor += 1; self.whitespace();
                const closing: u8 = if (opening == '{') '}' else ']';
                if (self.cursor < self.bytes.len and self.bytes[self.cursor] == closing) { self.cursor += 1; return self.bytes[start..self.cursor]; }
                while (true) {
                    if (opening == '{') { _ = try self.string(); try self.byte(':'); }
                    _ = try self.value(depth + 1);
                    self.whitespace();
                    if (self.cursor == self.bytes.len) return error.InvalidNativePackageJson;
                    if (self.bytes[self.cursor] == closing) { self.cursor += 1; break; }
                    try self.byte(',');
                }
            },
            't', 'f', 'n' => |initial| {
                const literal: []const u8 = if (initial == 't') "true" else if (initial == 'f') "false" else "null";
                if (!std.mem.startsWith(u8, self.bytes[start..], literal)) return error.InvalidNativePackageJson;
                self.cursor += literal.len;
            },
            '-', '0'...'9' => {
                if (self.bytes[self.cursor] == '-') self.cursor += 1;
                if (self.cursor == self.bytes.len) return error.InvalidNativePackageJson;
                if (self.bytes[self.cursor] == '0') self.cursor += 1 else if (self.digits() == 0) return error.InvalidNativePackageJson;
                if (self.cursor < self.bytes.len and self.bytes[self.cursor] == '.') {
                    self.cursor += 1; if (self.digits() == 0) return error.InvalidNativePackageJson;
                }
                if (self.cursor < self.bytes.len and (self.bytes[self.cursor] == 'e' or self.bytes[self.cursor] == 'E')) {
                    self.cursor += 1;
                    if (self.cursor < self.bytes.len and (self.bytes[self.cursor] == '+' or self.bytes[self.cursor] == '-')) self.cursor += 1;
                    if (self.digits() == 0) return error.InvalidNativePackageJson;
                }
            },
            else => return error.InvalidNativePackageJson,
        }
        return self.bytes[start..self.cursor];
    }
};
fn decoded(gpa: std.mem.Allocator, literal: []const u8) ![]u8 {
    const parsed = std.json.parseFromSlice([]const u8, gpa, literal, .{ .allocate = .alloc_always }) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        else => return error.InvalidNativePackageJson,
    };
    defer parsed.deinit();
    return gpa.dupe(u8, parsed.value);
}
fn replace(gpa: std.mem.Allocator, slot: *?[]u8, value: []u8) void {
    if (slot.*) |old| gpa.free(old);
    slot.* = value;
}
pub fn parse(gpa: std.mem.Allocator, input: []const u8) anyerror!Fields {
    const bytes = if (std.mem.startsWith(u8, input, "\xef\xbb\xbf")) input[3..] else input;
    if (!std.unicode.utf8ValidateSlice(bytes)) return error.InvalidNativePackageJson;
    var result: Fields = .{};
    errdefer result.deinit(gpa);
    var parser: Parser = .{ .bytes = bytes };
    try parser.byte('{'); parser.whitespace();
    if (parser.cursor < bytes.len and bytes[parser.cursor] == '}') parser.cursor += 1 else while (true) {
        const key_literal = try parser.string();
        // node_modules.cc compares raw_json_string keys, not unescaped JS keys.
        const key = key_literal[1 .. key_literal.len - 1];
        try parser.byte(':');
        const raw = try parser.value(2);
        if (std.mem.eql(u8, key, "name") or std.mem.eql(u8, key, "type")) {
            if (raw.len == 0 or raw[0] != '"') return error.InvalidNativePackageJson;
            const text = try decoded(gpa, raw);
            if (std.mem.eql(u8, key, "name")) replace(gpa, &result.name, text) else {
                defer gpa.free(text);
                if (std.mem.eql(u8, text, "commonjs")) result.kind = .commonjs else if (std.mem.eql(u8, text, "module")) result.kind = .module;
            }
        } else if (std.mem.eql(u8, key, "main")) {
            if (raw.len != 0 and raw[0] == '"') {
                const text: ?[]u8 = decoded(gpa, raw) catch |err| switch (err) { error.OutOfMemory => return error.OutOfMemory, else => null };
                if (text) |value| replace(gpa, &result.main, value);
            }
        } else if (std.mem.eql(u8, key, "imports") or std.mem.eql(u8, key, "exports")) {
            const slot = if (std.mem.eql(u8, key, "imports")) &result.imports else &result.exports;
            if (raw[0] == '"') replace(gpa, slot, try decoded(gpa, raw))
            else if (raw[0] == '{' or raw[0] == '[') replace(gpa, slot, try gpa.dupe(u8, raw));
        }
        parser.whitespace();
        if (parser.cursor == bytes.len) return error.InvalidNativePackageJson;
        if (bytes[parser.cursor] == '}') { parser.cursor += 1; break; }
        try parser.byte(',');
    };
    parser.whitespace();
    if (parser.cursor != bytes.len) return error.InvalidNativePackageJson;
    return result;
}
