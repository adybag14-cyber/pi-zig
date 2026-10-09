//! Native port of the pinned TypeBox template-pattern grammar and finite
//! expansion. This deliberately follows its grammar, including group unions
//! and its String fallback, rather than interpreting arbitrary regexes.
const std = @import("std");
const engine_mod = @import("engine.zig");
const vm = @import("native_values.zig");
const c = engine_mod.c;
const Engine = engine_mod.Engine;
const Node = struct { finite: bool, values: []const []const u8 };
const sentinels = [_][]const u8{ "-?(?:0|[1-9][0-9]*)n", ".*", "-?(?:0|[1-9][0-9]*)(?:\\.[0-9]+)?", "-?(?:0|[1-9][0-9]*)", "(?!)", "(", ")", "$", "|" };
pub fn literals(engine: *Engine, pattern: c.JSValue) !?c.JSValue {
    if (!c.JS_IsString(pattern)) {
        const ignored = try vm.invoke(engine, pattern, "trimStart", &.{});
        engine.freeValue(ignored);
        return null;
    }
    const input = try engine.toString(pattern);
    defer engine.gpa.free(input);
    var arena = std.heap.ArenaAllocator.init(engine.gpa);
    defer arena.deinit();
    var parser: Parser = .{ .a = arena.allocator(), .input = input };
    if (!parser.take("^")) return null;
    const nodes = try parser.body();
    if (!parser.take("$") or nodes.len == 0) return null;
    for (nodes) |node| if (!node.finite) return null;
    var values: std.ArrayList([]const u8) = .empty;
    try values.append(parser.a, "");
    for (nodes) |node| {
        var next: std.ArrayList([]const u8) = .empty;
        for (node.values) |suffix| for (values.items) |prefix| try next.append(parser.a, try std.fmt.allocPrint(parser.a, "{s}{s}", .{ prefix, suffix }));
        values = next;
    }
    const output = try vm.array(engine);
    errdefer engine.freeValue(output);
    for (values.items, 0..) |value, index| {
        const string = try engine.checked(c.JS_NewStringLen(engine.context, value.ptr, value.len));
        if (c.JS_SetPropertyUint32(engine.context, output, @intCast(index), string) < 0) return error.JavaScriptException;
    }
    return output;
}
const Parser = struct {
    a: std.mem.Allocator,
    input: []const u8,
    index: usize = 0,
    fn space(input: []const u8) usize {
        if (input.len == 0) return 0;
        if (std.mem.indexOfScalar(u8, " \t\n\r\x0b\x0c", input[0]) != null) return 1;
        for ([_][]const u8{ "\xc2\xa0", "\xe1\x9a\x80", "\xe2\x80\x80", "\xe2\x80\x81", "\xe2\x80\x82", "\xe2\x80\x83", "\xe2\x80\x84", "\xe2\x80\x85", "\xe2\x80\x86", "\xe2\x80\x87", "\xe2\x80\x88", "\xe2\x80\x89", "\xe2\x80\x8a", "\xe2\x80\xa8", "\xe2\x80\xa9", "\xe2\x80\xaf", "\xe2\x81\x9f", "\xe3\x80\x80", "\xef\xbb\xbf" }) |value| if (std.mem.startsWith(u8, input, value)) return value.len;
        return 0;
    }
    fn trimmed(self: *Parser) usize {
        var index = self.index;
        while (true) {
            while (index < self.input.len) {
                const length = space(self.input[index..]);
                if (length == 0) break;
                index += length;
            }
            if (std.mem.startsWith(u8, self.input[index..], "/*")) {
                const end = std.mem.indexOf(u8, self.input[index + 2 ..], "*/") orelse return self.input.len;
                index += end + 4;
            } else if (std.mem.startsWith(u8, self.input[index..], "//")) {
                index = if (std.mem.indexOfScalar(u8, self.input[index + 2 ..], '\n')) |end| index + end + 2 else return self.input.len;
            } else return index;
        }
    }
    fn take(self: *Parser, token: []const u8) bool {
        const index = self.trimmed();
        if (!std.mem.startsWith(u8, self.input[index..], token)) return false;
        self.index = index + token.len;
        return true;
    }
    fn base(self: *Parser) anyerror!?Node {
        const initial = self.index;
        for (sentinels[0..5]) |token| if (self.take(token)) return .{ .finite = false, .values = &.{} };
        if (self.take("(")) {
            const nodes = try self.body();
            if (self.take(")")) {
                var values: std.ArrayList([]const u8) = .empty;
                var finite = nodes.len != 0;
                for (nodes) |node| {
                    finite = finite and node.finite;
                    try values.appendSlice(self.a, node.values);
                }
                return .{ .finite = finite, .values = values.items };
            }
            self.index = initial;
        }
        var end = initial;
        outer: while (end < self.input.len) : (end += 1) {
            for (sentinels) |token| if (std.mem.startsWith(u8, self.input[end..], token)) break :outer;
        }
        if (end == initial or end == self.input.len) return null;
        self.index = end;
        const values = try self.a.alloc([]const u8, 1);
        values[0] = self.input[initial..end];
        return .{ .finite = true, .values = values };
    }
    fn term(self: *Parser) anyerror!?[]const Node {
        const initial = self.index;
        const node = try self.base() orelse {
            self.index = initial;
            return null;
        };
        const rest = try self.body();
        const output = try self.a.alloc(Node, rest.len + 1);
        output[0] = node;
        @memcpy(output[1..], rest);
        return output;
    }
    fn body(self: *Parser) anyerror![]const Node {
        const initial = self.index;
        const first = try self.term() orelse {
            self.index = initial;
            return &.{};
        };
        if (!self.take("|")) return first;
        const rest = try self.body();
        const output = try self.a.alloc(Node, first.len + rest.len);
        @memcpy(output[0..first.len], first);
        @memcpy(output[first.len..], rest);
        return output;
    }
};
