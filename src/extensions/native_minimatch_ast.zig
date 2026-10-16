//! Native AST order from minimatch 10.2.6: parse, flatten, fill negative tails,
//! then render. Resource limits below are native admission limits, not proofs.
const std = @import("std");
pub const Result = struct { source: []const u8, body: []const u8, magic: bool = false, unicode: bool = false };
pub const Plain = *const fn (std.mem.Allocator, []const u8, bool) anyerror!Result;
const Buffer = std.ArrayList(u8);
const Part = union(enum) { text: []const u8, node: *Node };
const Node = struct {
    tree: *Tree,
    kind: ?u8,
    parent: ?*Node,
    parent_index: usize,
    parts: *std.ArrayList(Part),
    magic: bool,
    unicode: bool = false,
    empty_ext: bool = false,
    cached_text: ?[]const u8 = null,
};
const Tree = struct {
    a: std.mem.Allocator,
    plain: Plain,
    root: *Node = undefined,
    negatives: std.ArrayList(*Node) = .empty,
    filled_negatives: bool = false,
    nodes: usize = 0,

    fn list(self: *Tree) !*std.ArrayList(Part) {
        const parts = try self.a.create(std.ArrayList(Part));
        parts.* = .empty;
        return parts;
    }
    fn append(self: *Tree, out: *Buffer, text: []const u8) !void {
        if (out.items.len + text.len > 4_000_000) return error.MinimatchAstTextLimitUnsupported;
        try out.appendSlice(self.a, text);
    }
    fn concat(self: *Tree, texts: []const []const u8) ![]const u8 {
        var out: Buffer = .empty;
        for (texts) |text| try self.append(&out, text);
        return out.items;
    }

    fn node(self: *Tree, kind: ?u8, parent: ?*Node) !*Node {
        if (self.nodes == 16_384) return error.MinimatchAstNodeLimitUnsupported;
        self.nodes += 1;
        const result = try self.a.create(Node);
        result.* = .{ .tree = self, .kind = kind, .parent = parent, .parent_index = if (parent) |p| p.parts.items.len else 0, .parts = try self.list(), .magic = kind != null };
        if (kind == '!' and !self.filled_negatives) try self.negatives.append(self.a, result);
        return result;
    }
    fn push(self: *Tree, destination: *Node, part: Part) !void {
        if (part == .text and part.text.len == 0) return;
        try destination.parts.append(self.a, part);
    }
    fn copyIn(self: *Tree, destination: *Node, part: Part, depth: usize) anyerror!void {
        if (depth > 64) return error.MinimatchAstDepthUnsupported;
        switch (part) {
            .text => try self.push(destination, part),
            .node => |original| {
                const copied = try self.node(original.kind, destination);
                for (original.parts.items) |child| try self.copyIn(copied, child, depth + 1);
                try self.push(destination, .{ .node = copied });
            },
        }
    }
    fn parse(self: *Tree, text: []const u8, current: *Node, position: usize, ext_depth: usize, physical_depth: usize) anyerror!usize {
        if (physical_depth > 64) return error.MinimatchAstDepthUnsupported;
        var escaped = false;
        var in_class = false;
        var class_start: usize = 0;
        var class_negate = false;
        var acc: Buffer = .empty;
        var i = if (current.kind == null) position else position + 1;
        var part = if (current.kind == null) current else try self.node(null, current);
        var alternatives: std.ArrayList(*Node) = .empty;
        while (i < text.len) {
            const ch = text[i];
            i += 1;
            if (escaped or ch == '\\') {
                escaped = !escaped;
                try acc.append(self.a, ch);
                continue;
            }
            if (in_class) {
                if (i == class_start + 1) {
                    if (ch == '^' or ch == '!') class_negate = true;
                } else if (ch == ']' and !(i == class_start + 2 and class_negate)) in_class = false;
                try acc.append(self.a, ch);
                continue;
            } else if (ch == '[') {
                in_class = true;
                class_start = i;
                class_negate = false;
                try acc.append(self.a, ch);
                continue;
            }
            const adoptable = if (current.kind) |kind| canAdoptType(kind, ch, .any) else false;
            const recurse = isType(ch) and i < text.len and text[i] == '(' and (ext_depth <= 2 or adoptable);
            if (recurse) {
                try self.push(part, .{ .text = acc.items });
                acc = .empty;
                const child = try self.node(ch, part);
                const increase: usize = if (current.kind == null or !adoptable) 1 else 0;
                i = try self.parse(text, child, i, ext_depth + increase, physical_depth + 1);
                try self.push(part, .{ .node = child });
                continue;
            }
            if (current.kind != null and ch == '|') {
                try self.push(part, .{ .text = acc.items });
                acc = .empty;
                try alternatives.append(self.a, part);
                part = try self.node(null, current);
                continue;
            }
            if (current.kind != null and ch == ')') {
                if (acc.items.len == 0 and current.parts.items.len == 0) current.empty_ext = true;
                try self.push(part, .{ .text = acc.items });
                for (alternatives.items) |alternative| try self.push(current, .{ .node = alternative });
                try self.push(current, .{ .node = part });
                return i;
            }
            try acc.append(self.a, ch);
        }
        if (current.kind == null) {
            try self.push(current, .{ .text = acc.items });
        } else {
            // The source discards an unfinished extglob tree and parses the
            // entire original suffix as ordinary glob text during rendering.
            current.kind = null;
            current.magic = false;
            current.parts = try self.list();
            try current.parts.append(self.a, .{ .text = text[position - 1..] });
        }
        return i;
    }
    fn string(self: *Tree, current: *Node, depth: usize) anyerror![]const u8 {
        if (depth > 64) return error.MinimatchAstDepthUnsupported;
        if (current.cached_text) |cached| return cached;
        var out: Buffer = .empty;
        if (current.kind) |kind| { try self.append(&out, &.{ kind, '(' }); }
        for (current.parts.items, 0..) |part, index| {
            if (current.kind != null and index > 0) try self.append(&out, "|");
            try self.append(&out, switch (part) { .text => |value| value, .node => |child| try self.string(child, depth + 1) });
        }
        if (current.kind != null) try self.append(&out, ")");
        current.cached_text = out.items;
        return out.items;
    }
    fn grandchild(current: *Node, child: Part) ?*Node {
        if (current.kind == null or child != .node) return null;
        const alternative = child.node;
        if (alternative.kind != null or alternative.parts.items.len != 1 or alternative.parts.items[0] != .node) return null;
        const grand = alternative.parts.items[0].node;
        return if (grand.kind != null) grand else null;
    }
    fn adopt(self: *Tree, current: *Node, grand: *Node, index: usize) !void {
        var replacement: std.ArrayList(Part) = .empty;
        try replacement.appendSlice(self.a, current.parts.items[0..index]);
        try replacement.appendSlice(self.a, grand.parts.items);
        try replacement.appendSlice(self.a, current.parts.items[index + 1..]);
        for (grand.parts.items) |part| if (part == .node) { part.node.parent = current; };
        current.parts.* = replacement;
        current.cached_text = null;
    }
    fn flatten(self: *Tree, current: *Node, depth: usize) anyerror!void {
        if (depth > 64) return error.MinimatchAstDepthUnsupported;
        if (current.kind == null) {
            for (current.parts.items) |part| if (part == .node) try self.flatten(part.node, depth + 1);
        } else {
            var iterations: usize = 0;
            while (true) {
                var done = true;
                var i: usize = 0;
                while (i < current.parts.items.len) : (i += 1) {
                    const child = current.parts.items[i];
                    if (child != .node) continue;
                    try self.flatten(child.node, depth + 1);
                    const grand = grandchild(current, child) orelse continue;
                    if (canAdoptType(current.kind.?, grand.kind.?, .direct)) {
                        done = false;
                        try self.adopt(current, grand, i);
                    } else if (canAdoptType(current.kind.?, grand.kind.?, .space)) {
                        done = false;
                        const blank = try self.node(null, grand);
                        // Source inserts this empty text directly, bypassing
                        // push's normal empty-string removal.
                        try blank.parts.append(self.a, .{ .text = "" });
                        try self.push(grand, .{ .node = blank });
                        try self.adopt(current, grand, i);
                    } else if (current.parts.items.len == 1) {
                        if (usurpType(current.kind.?, grand.kind.?)) |kind| {
                            done = false;
                            current.parts = grand.parts;
                            for (current.parts.items) |part| if (part == .node) { part.node.parent = current; };
                            current.kind = kind;
                            current.cached_text = null;
                            current.empty_ext = false;
                        }
                    }
                }
                if (done) break;
                iterations += 1;
                if (iterations == 10) break;
            }
        }
        current.cached_text = null;
    }
    fn fillNegatives(self: *Tree) !void {
        if (self.filled_negatives) return;
        _ = try self.string(self.root, 0);
        self.filled_negatives = true;
        while (self.negatives.pop()) |negative| {
            if (negative.kind != '!') continue;
            var child = negative;
            var parent = child.parent;
            while (parent) |ancestor| {
                var i = child.parent_index + 1;
                while (ancestor.kind == null and i < ancestor.parts.items.len) : (i += 1) {
                    const tail = ancestor.parts.items[i];
                    for (negative.parts.items) |alternative| {
                        if (alternative != .node) return error.MinimatchAstInvalidNegativePart;
                        try self.copyIn(alternative.node, tail, 0);
                    }
                }
                child = ancestor;
                parent = ancestor.parent;
            }
        }
    }
    fn alternatives(self: *Tree, current: *Node, dot: bool, depth: usize) anyerror![]const u8 {
        var out: Buffer = .empty;
        var count: usize = 0;
        for (current.parts.items) |part| {
            if (part != .node) return error.MinimatchAstInvalidAlternative;
            const result = try self.render(part.node, dot, depth + 1);
            current.unicode = current.unicode or result.unicode;
            if (isStart(current) and isEnd(current) and result.source.len == 0) continue;
            if (count > 0) try self.append(&out, "|");
            try self.append(&out, result.source);
            count += 1;
        }
        return out.items;
    }
    fn render(self: *Tree, current: *Node, allow_dot: ?bool, depth: usize) anyerror!Result {
        if (depth > 64) return error.MinimatchAstDepthUnsupported;
        const dot = allow_dot orelse false;
        if (current == self.root) {
            try self.flatten(current, 0);
            try self.fillNegatives();
        }
        if (current.kind == null) {
            var no_empty = isStart(current) and isEnd(current);
            for (current.parts.items) |part| if (part == .node) { no_empty = false; };
            var out: Buffer = .empty;
            for (current.parts.items) |part| {
                const result = switch (part) { .text => |value| try self.plain(self.a, value, no_empty), .node => |child| try self.render(child, allow_dot, depth + 1) };
                current.magic = current.magic or result.magic;
                current.unicode = current.unicode or result.unicode;
                try self.append(&out, result.source);
            }
            const source = out.items;
            var start: []const u8 = "";
            if (isStart(current) and current.parts.items.len > 0 and current.parts.items[0] == .text) {
                const first = current.parts.items[0].text;
                const dot_traversal = current.parts.items.len == 1 and (std.mem.eql(u8, first, ".") or std.mem.eql(u8, first, ".."));
                if (!dot_traversal) {
                    const no_traversal = (dot and startCharacter(source, 0)) or (std.mem.startsWith(u8, source, "\\.") and startCharacter(source, 2)) or (std.mem.startsWith(u8, source, "\\.\\.") and startCharacter(source, 4));
                    const no_dot = !dot and !(allow_dot orelse false) and startCharacter(source, 0);
                    start = if (no_traversal) "(?!(?:^|/)\\.\\.?(?:$|/))" else if (no_dot) "(?!\\.)" else "";
                }
            }
            const end: []const u8 = if (isEnd(current) and self.filled_negatives and current.parent != null and current.parent.?.kind == '!') "(?:$|\\/)" else "";
            return .{ .source = try self.concat(&.{ start, source, end }), .body = try unescape(self.a, source), .magic = current.magic, .unicode = current.unicode };
        }
        const kind = current.kind.?;
        const repeated = kind == '*' or kind == '+';
        const start: []const u8 = if (kind == '!') "(?:(?!(?:" else "(?:";
        var body = try self.alternatives(current, dot, depth);
        if (isStart(current) and isEnd(current) and body.len == 0 and kind != '!') {
            const text = try self.string(current, 0);
            current.parts = try self.list();
            try current.parts.append(self.a, .{ .text = text });
            current.kind = null;
            current.magic = false;
            return .{ .source = text, .body = try unescape(self.a, try self.string(current, 0)) };
        }
        var body_dot: []const u8 = if (!repeated or (allow_dot orelse false) or dot) "" else try self.alternatives(current, true, depth);
        if (std.mem.eql(u8, body_dot, body)) body_dot = "";
        if (body_dot.len > 0) body = try self.concat(&.{ "(?:", body, ")(?:", body_dot, ")*?" });
        var final: []const u8 = undefined;
        if (kind == '!' and current.empty_ext) {
            final = try self.concat(&.{ if (isStart(current) and !dot) "(?!\\.)" else "", "[^/]+?" });
        } else {
            const close: []const u8 = if (kind == '!') try self.concat(&.{ "))", if (isStart(current) and !dot and !(allow_dot orelse false)) "(?!\\.)" else "", "[^/]*?)" })
                else if (kind == '@') ")" else if (kind == '?') ")?" else if (kind == '+' and body_dot.len > 0) ")" else if (kind == '*' and body_dot.len > 0) ")?" else try self.concat(&.{ ")", &.{kind} });
            final = try self.concat(&.{ start, body, close });
        }
        return .{ .source = final, .body = try unescape(self.a, body), .magic = current.magic, .unicode = current.unicode };
    }
};

fn isType(ch: u8) bool { return std.mem.indexOfScalar(u8, "!?@*+", ch) != null; }
const Adoption = enum { direct, space, any };
fn canAdoptType(parent: u8, child: u8, mode: Adoption) bool {
    const direct: []const u8 = switch (parent) { '!' => "@", '?' => "?@", '@' => "@", '*' => "*+?@", '+' => "+@", else => "" };
    const space: []const u8 = switch (parent) { '!', '@' => "?", '+' => "?*", else => "" };
    return (mode != .space and std.mem.indexOfScalar(u8, direct, child) != null) or (mode != .direct and std.mem.indexOfScalar(u8, space, child) != null);
}
fn usurpType(parent: u8, child: u8) ?u8 {
    return switch (parent) { '!' => if (child == '!') '@' else null, '?' => if (child == '*' or child == '+') '*' else null, '@' => if (isType(child)) child else null, '+' => if (child == '?' or child == '*') '*' else null, else => null };
}
fn isStart(current: *Node) bool {
    const parent = current.parent orelse return true;
    if (!isStart(parent)) return false;
    if (current.parent_index == 0) return true;
    for (parent.parts.items[0..@min(current.parent_index, parent.parts.items.len)]) |part| if (part != .node or part.node.kind != '!') return false;
    return current.parent_index <= parent.parts.items.len;
}
fn isEnd(current: *Node) bool {
    const parent = current.parent orelse return true;
    if (parent.kind == '!') return true;
    if (!isEnd(parent)) return false;
    if (current.kind == null) return isEnd(parent);
    return parent.parts.items.len > 0 and current.parent_index == parent.parts.items.len - 1;
}
fn startCharacter(source: []const u8, at: usize) bool { return at < source.len and (source[at] == '[' or source[at] == '.'); }
fn unitWidth(text: []const u8) usize {
    const width: usize = if (text[0] < 0x80) 1 else if (text[0] < 0xe0) 2 else if (text[0] < 0xf0) 3 else 4;
    return @min(width, text.len);
}
fn lineTerminator(text: []const u8) bool {
    return text[0] == '\n' or text[0] == '\r' or std.mem.startsWith(u8, text, "\xe2\x80\xa8") or std.mem.startsWith(u8, text, "\xe2\x80\xa9");
}
fn bracketUnit(text: []const u8, start: usize) ?usize {
    if (start + 2 >= text.len or text[start] != '[' or text[start + 1] == '/' or text[start + 1] == '\\') return null;
    const end = start + 1 + unitWidth(text[start + 1..]);
    return if (end < text.len and text[end] == ']') end else null;
}
fn unescape(a: std.mem.Allocator, text: []const u8) ![]const u8 {
    // Preserve both original default-mode replacements and their global,
    // nonoverlapping prefix consumption, including UTF16 singleton classes.
    var brackets: Buffer = .empty;
    var i: usize = 0;
    while (i < text.len) {
        const width = unitWidth(text[i..]);
        if (text[i] != '\\' and !lineTerminator(text[i..])) {
            if (bracketUnit(text, i + width)) |end| {
                try brackets.appendSlice(a, text[i..i + width]);
                try brackets.appendSlice(a, text[i + width + 1..end]);
                i = end + 1;
                continue;
            }
        }
        if (i == 0) {
            if (bracketUnit(text, i)) |end| {
                try brackets.appendSlice(a, text[i + 1..end]);
                i = end + 1;
                continue;
            }
        }
        try brackets.appendSlice(a, text[i..i + width]);
        i += width;
    }
    var out: Buffer = .empty;
    i = 0;
    while (i < brackets.items.len) {
        if (brackets.items[i] == '\\' and i + 1 < brackets.items.len and brackets.items[i + 1] != '/') i += 1;
        const width = unitWidth(brackets.items[i..]);
        try out.appendSlice(a, brackets.items[i..i + width]);
        i += width;
    }
    return out.items;
}
pub fn compile(a: std.mem.Allocator, text: []const u8, plain: Plain) !Result {
    var tree: Tree = .{ .a = a, .plain = plain };
    tree.root = try tree.node(null, null);
    _ = try tree.parse(text, tree.root, 0, 0, 0);
    _ = try tree.string(tree.root, 0);
    return tree.render(tree.root, null, 0);
}
