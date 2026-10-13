//! Globset 0.4.20 token semantics, compiled to a native acyclic state graph with wildcard self loops.
//! Alternates retain their token boundaries: expanding text first would incorrectly promote embedded **.
const std = @import("std");
const builtin = @import("builtin");
const Bits = [4]u64;
const Token = union(enum) { literal: u8, any, star, prefix, zero, suffix, class: Bits, alternatives: []Sequence };
const Sequence = struct {
    tokens: std.ArrayList(Token) = .empty,
    fn deinit(self: *Sequence, gpa: std.mem.Allocator) void {
        for (self.tokens.items) |token| if (token == .alternatives) {
            for (token.alternatives) |*branch| branch.deinit(gpa);
            gpa.free(token.alternatives);
        };
        self.tokens.deinit(gpa);
    }
    fn nonempty(self: Sequence) bool {
        for (self.tokens.items) |token| {
            if (token != .alternatives) return true;
            for (token.alternatives) |branch| if (branch.nonempty()) return true;
        }
        return false;
    }
};
fn separator(byte: u8) bool {
    return byte == '/' or (builtin.os.tag == .windows and byte == '\\');
}
const Parser = struct {
    gpa: std.mem.Allocator,
    pattern: []const u8,
    cursor: usize = 0,
    unclosed_class: bool = false,
    fn sequence(self: *Parser, alternate: bool) anyerror!Sequence {
        var result: Sequence = .{};
        errdefer result.deinit(self.gpa);
        while (self.cursor < self.pattern.len) {
            const position = self.cursor;
            const byte = self.pattern[self.cursor];
            if (alternate and (byte == ',' or byte == '}')) break;
            self.cursor += 1;
            switch (byte) {
                '\\' => {
                    if (self.cursor == self.pattern.len) return error.InvalidGlob;
                    try result.tokens.append(self.gpa, .{ .literal = self.pattern[self.cursor] });
                    self.cursor += 1;
                },
                '?' => try result.tokens.append(self.gpa, .any),
                '*' => {
                    if (self.cursor == self.pattern.len or self.pattern[self.cursor] != '*') {
                        try result.tokens.append(self.gpa, .star);
                        continue;
                    }
                    self.cursor += 1;
                    const next: ?u8 = if (self.cursor < self.pattern.len) self.pattern[self.cursor] else null;
                    if (result.tokens.items.len == 0) {
                        if (next == null or separator(next.?)) {
                            try result.tokens.append(self.gpa, .prefix);
                            if (next != null) self.cursor += 1;
                        } else {
                            try result.tokens.append(self.gpa, .star);
                            try result.tokens.append(self.gpa, .star);
                        }
                        continue;
                    }
                    const previous: ?u8 = if (position > 0) self.pattern[position - 1] else null;
                    if ((previous == null or !separator(previous.?)) and !(alternate and (previous.? == ',' or previous.? == '{'))) {
                        try result.tokens.append(self.gpa, .star);
                        try result.tokens.append(self.gpa, .star);
                        continue;
                    }
                    const suffix = next == null or (alternate and (next.? == ',' or next.? == '}'));
                    if (!suffix and !separator(next.?)) {
                        try result.tokens.append(self.gpa, .star);
                        try result.tokens.append(self.gpa, .star);
                        continue;
                    }
                    if (!suffix) self.cursor += 1;
                    const prior = result.tokens.pop().?;
                    try result.tokens.append(self.gpa, if (prior == .prefix or prior == .suffix) prior else if (suffix) .suffix else .zero);
                },
                '[' => {
                    if (self.unclosed_class) {
                        try result.tokens.append(self.gpa, .{ .literal = byte });
                        continue;
                    }
                    const saved = self.cursor;
                    const bits = self.characterClass() catch |err| {
                        if (err != error.UnclosedClass) return err;
                        self.cursor = saved;
                        self.unclosed_class = true;
                        try result.tokens.append(self.gpa, .{ .literal = byte });
                        continue;
                    };
                    try result.tokens.append(self.gpa, .{ .class = bits });
                },
                '{' => {
                    var branches: std.ArrayList(Sequence) = .empty;
                    var transferred = false;
                    defer if (!transferred) {
                        for (branches.items) |*branch| branch.deinit(self.gpa);
                        branches.deinit(self.gpa);
                    };
                    while (true) {
                        var branch = try self.sequence(true);
                        errdefer branch.deinit(self.gpa);
                        try branches.append(self.gpa, branch);
                        branch = .{};
                        if (self.cursor == self.pattern.len) return error.InvalidGlob;
                        const delimiter = self.pattern[self.cursor];
                        self.cursor += 1;
                        if (delimiter == '}') break;
                    }
                    const owned = try branches.toOwnedSlice(self.gpa);
                    errdefer {
                        for (owned) |*branch| branch.deinit(self.gpa);
                        self.gpa.free(owned);
                    }
                    try result.tokens.append(self.gpa, .{ .alternatives = owned });
                    transferred = true;
                },
                '}' => return error.InvalidGlob,
                else => try result.tokens.append(self.gpa, .{ .literal = byte }),
            }
        }
        return result;
    }
    fn scalar(self: *Parser) !u21 {
        if (self.cursor == self.pattern.len) return error.UnclosedClass;
        const length = std.unicode.utf8ByteSequenceLength(self.pattern[self.cursor]) catch return error.InvalidGlob;
        if (length > self.pattern.len - self.cursor) return error.InvalidGlob;
        const value = std.unicode.utf8Decode(self.pattern[self.cursor..][0..length]) catch return error.InvalidGlob;
        self.cursor += length;
        return value;
    }
    fn characterClass(self: *Parser) !Bits {
        var bits: Bits = @splat(0);
        var negate = false;
        if (self.cursor < self.pattern.len and (self.pattern[self.cursor] == '!' or self.pattern[self.cursor] == '^')) {
            negate = true;
            self.cursor += 1;
        }
        var first = true;
        var in_range = false;
        var current: ?struct { low: u21, high: u21 } = null;
        while (true) {
            const value = try self.scalar();
            if (value == ']' and !first) break;
            if (value == '-' and !first and !in_range) {
                in_range = true;
                first = false;
                continue;
            }
            if (in_range) {
                if (value < current.?.low) return error.InvalidGlob;
                current.?.high = value;
                in_range = false;
            } else {
                if (current) |range| addRange(&bits, range.low, range.high);
                current = .{ .low = value, .high = value };
            }
            first = false;
        }
        if (current) |range| addRange(&bits, range.low, range.high);
        if (in_range) addRange(&bits, '-', '-');
        if (negate) for (&bits) |*word| {
            word.* = ~word.*;
        };
        return bits;
    }
};
fn addByte(bits: *Bits, byte: u8) void {
    bits[byte / 64] |= @as(u64, 1) << @as(u6, @intCast(byte % 64));
}
fn addRange(bits: *Bits, low: u21, high: u21) void {
    var low_utf8: [4]u8 = undefined;
    var high_utf8: [4]u8 = undefined;
    const low_length = std.unicode.utf8Encode(low, &low_utf8) catch unreachable;
    const high_length = std.unicode.utf8Encode(high, &high_utf8) catch unreachable;
    // globset emits UTF-8 escaped bytes into a non-Unicode regex class.
    if (low == high) {
        for (low_utf8[0..low_length]) |byte| addByte(bits, byte);
        return;
    }
    for (low_utf8[0 .. low_length - 1]) |byte| addByte(bits, byte);
    var byte: u16 = low_utf8[low_length - 1];
    while (byte <= high_utf8[0]) : (byte += 1) addByte(bits, @intCast(byte));
    for (high_utf8[1..high_length]) |rest| addByte(bits, rest);
}
const State = union(enum) { accept, literal: struct { byte: u8, next: usize }, any: usize, star: usize, star_any: usize, scan_slash: usize, class: struct { bits: Bits, next: usize }, split: struct { a: usize, b: usize } };
const Graph = struct {
    gpa: std.mem.Allocator,
    states: std.ArrayList(State) = .empty,
    fn add(self: *Graph, state: State) !usize {
        const index = self.states.items.len;
        try self.states.append(self.gpa, state);
        return index;
    }
    fn prefix(self: *Graph, next: usize) !usize {
        const scan = try self.add(.{ .scan_slash = next });
        return self.add(.{ .split = .{ .a = next, .b = scan } });
    }
    fn sequence(self: *Graph, input: Sequence, following: usize) anyerror!usize {
        var next = following;
        var index = input.tokens.items.len;
        while (index > 0) {
            index -= 1;
            next = switch (input.tokens.items[index]) {
                .literal => |byte| try self.add(.{ .literal = .{ .byte = byte, .next = next } }),
                .any => try self.add(.{ .any = next }),
                .star => try self.add(.{ .star = next }),
                .prefix => try self.prefix(next),
                .zero => try self.add(.{ .literal = .{ .byte = '/', .next = try self.prefix(next) } }),
                .suffix => try self.add(.{ .literal = .{ .byte = '/', .next = try self.add(.{ .star_any = next }) } }),
                .class => |bits| try self.add(.{ .class = .{ .bits = bits, .next = next } }),
                .alternatives => |branches| alternatives: {
                    var selected: ?usize = null;
                    for (branches) |branch| {
                        if (!branch.nonempty()) continue;
                        const start = try self.sequence(branch, next);
                        selected = if (selected) |prior| try self.add(.{ .split = .{ .a = prior, .b = start } }) else start;
                    }
                    break :alternatives selected orelse next;
                },
            };
        }
        return next;
    }
};
pub fn matches(gpa: std.mem.Allocator, pattern: []const u8, text: []const u8) !bool {
    var parser: Parser = .{ .gpa = gpa, .pattern = pattern };
    var tokens = parser.sequence(false) catch |err| switch (err) {
        error.InvalidGlob, error.UnclosedClass => return false,
        else => return err,
    };
    defer tokens.deinit(gpa);
    var graph: Graph = .{ .gpa = gpa };
    defer graph.states.deinit(gpa);
    _ = try graph.add(.accept);
    const start = if (tokens.tokens.items.len == 1 and tokens.tokens.items[0] == .prefix) try graph.add(.{ .star_any = 0 }) else try graph.sequence(tokens, 0);
    const count = graph.states.items.len;
    const size = std.math.mul(usize, count, text.len + 1) catch return error.OutOfMemory;
    const table = try gpa.alloc(bool, size);
    defer gpa.free(table);
    var position = text.len + 1;
    while (position > 0) {
        position -= 1;
        const row = table[position * count ..][0..count];
        const after = if (position < text.len) table[(position + 1) * count ..][0..count] else null;
        for (graph.states.items, 0..) |state, index| row[index] = switch (state) {
            .accept => position == text.len,
            .literal => |literal| after != null and text[position] == literal.byte and after.?[literal.next],
            .any => |next| after != null and text[position] != '/' and after.?[next],
            .star => |next| row[next] or (after != null and text[position] != '/' and after.?[index]),
            .star_any => |next| row[next] or (after != null and after.?[index]),
            .scan_slash => |next| after != null and ((text[position] == '/' and after.?[next]) or after.?[index]),
            .class => |class| after != null and class.bits[text[position] / 64] & (@as(u64, 1) << @as(u6, @intCast(text[position] % 64))) != 0 and after.?[class.next],
            .split => |split| row[split.a] or row[split.b],
        };
    }
    return table[start];
}
