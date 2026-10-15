//! Actual jsdiff8.0.4 default synchronous Myers path used privately by edit.
//! Native code only. Public jsdiff classes/options/async callbacks are not bound.
//! Word postprocessing and line/word tokenization follow the installed authority.
const std = @import("std");
const em = @import("engine.zig");
const js = @import("native_js_values.zig");
const Scope = @import("native_sdk_prompt_scope.zig").Scope;
const c = em.c;
const Mode = enum { lines, words };
const Kind = enum { keep, add, remove };
const Node = struct { count: usize, kind: Kind, previous: ?usize };
const Path = struct { old_pos: isize = -1, last: ?usize = null };
const Work = struct {
    s: *Scope,
    mode: Mode,
    nodes: std.ArrayList(Node) = .empty,
    ticks: usize = 0,
    fn tick(self: *Work) !void {
        self.ticks +|= 1;
        if (self.s.engine.cancelled.load(.acquire) or (self.ticks % 256 == 0 and blocked: {
            self.s.engine.interrupts +|= 1;
            break :blocked self.s.engine.interrupts > self.s.engine.options.interrupt_budget;
        })) {
            _ = try self.s.engine.checked(c.JS_ThrowInternalError(self.s.engine.context, "interrupted"));
            unreachable;
        }
    }
    fn add(self: *Work, path: Path, kind: Kind) !Path {
        var node: Node = .{ .count = 1, .kind = kind, .previous = path.last };
        if (path.last) |last| if (self.nodes.items[last].kind == kind) {
            node.count = self.nodes.items[last].count + 1;
            node.previous = self.nodes.items[last].previous;
        };
        try self.nodes.append(self.s.engine.gpa, node);
        return .{ .old_pos = path.old_pos + @as(isize, if (kind == .remove) 1 else 0), .last = self.nodes.items.len - 1 };
    }
    fn equal(self: *Work, left: c.JSValue, right: c.JSValue) !bool {
        return if (self.mode == .words) self.s.equal(try self.s.invoke(left, "trim", &.{}), try self.s.invoke(right, "trim", &.{})) else self.s.equal(left, right);
    }
    fn common(self: *Work, path: *Path, newer: []const c.JSValue, older: []const c.JSValue, diagonal: isize) !isize {
        var new_pos = path.old_pos - diagonal;
        var count: usize = 0;
        while (new_pos + 1 < @as(isize, @intCast(newer.len)) and path.old_pos + 1 < @as(isize, @intCast(older.len))) {
            try self.tick();
            if (!try self.equal(older[@intCast(path.old_pos + 1)], newer[@intCast(new_pos + 1)])) break;
            path.old_pos += 1;
            new_pos += 1;
            count += 1;
        }
        if (count != 0) {
            try self.nodes.append(self.s.engine.gpa, .{ .count = count, .kind = .keep, .previous = path.last });
            path.last = self.nodes.items.len - 1;
        }
        return new_pos;
    }
    fn values(self: *Work, last: ?usize, newer: []const c.JSValue, older: []const c.JSValue) !c.JSValue {
        var order: std.ArrayList(usize) = .empty;
        defer order.deinit(self.s.engine.gpa);
        var next = last;
        while (next) |index| {
            try self.tick();
            try order.append(self.s.engine.gpa, index);
            next = self.nodes.items[index].previous;
        }
        std.mem.reverse(usize, order.items);
        const out = try self.s.array();
        var old_pos: usize = 0;
        var new_pos: usize = 0;
        for (order.items, 0..) |index, position| {
            const node = self.nodes.items[index];
            const value = try self.s.object();
            try self.s.put(value, "count", c.JS_NewFloat64(self.s.engine.context, @floatFromInt(node.count)));
            try self.s.put(value, "added", c.pi_js_bool(self.s.engine.context, @intFromBool(node.kind == .add)));
            try self.s.put(value, "removed", c.pi_js_bool(self.s.engine.context, @intFromBool(node.kind == .remove)));
            const tokens = if (node.kind == .remove) older[old_pos..][0..node.count] else newer[new_pos..][0..node.count];
            try self.s.put(value, "value", try join(self.s, self.mode, tokens));
            if (node.kind != .remove) new_pos += node.count;
            if (node.kind != .add) old_pos += node.count;
            try self.s.index(out, @intCast(position), value);
        }
        if (self.mode == .words) try postProcess(self.s, out);
        return out;
    }
};
fn number(s: *Scope, value: isize) c.JSValue {
    return c.JS_NewFloat64(s.engine.context, @floatFromInt(value));
}
fn length(s: *Scope, value: c.JSValue) !usize {
    var out: u32 = 0;
    if (c.JS_ToUint32(s.engine.context, &out, try s.get(value, "length")) < 0) return js.capture(s.engine);
    return out;
}
fn at(s: *Scope, value: c.JSValue, index: usize) !c.JSValue {
    return s.own(try s.engine.checked(c.JS_GetPropertyUint32(s.engine.context, value, @intCast(index))));
}
fn regex(s: *Scope, pattern: []const u8, flags: []const u8) !c.JSValue {
    var args = [_]c.JSValue{ try s.text(pattern), try s.text(flags) };
    return s.own(try s.engine.checked(c.JS_CallConstructor(s.engine.context, s.engine.intrinsic_regexp_constructor, args.len, &args)));
}
fn slice(s: *Scope, text: c.JSValue, start: isize, end: ?isize) !c.JSValue {
    return if (end) |stop| s.invoke(text, "slice", &.{ number(s, start), number(s, stop) }) else s.invoke(text, "slice", &.{number(s, start)});
}
fn tokenize(s: *Scope, mode: Mode, text: c.JSValue) ![]c.JSValue {
    var tokens: std.ArrayList(c.JSValue) = .empty;
    errdefer tokens.deinit(s.engine.gpa);
    if (mode == .lines) {
        const pieces = try s.invoke(text, "split", &.{try regex(s, "(\n|\r\n)", "")});
        var count = try length(s, pieces);
        if (count != 0 and !s.truthy(try at(s, pieces, count - 1))) count -= 1;
        for (0..count) |index| {
            const line = try at(s, pieces, index);
            if (index % 2 != 0) {
                tokens.items[tokens.items.len - 1] = try s.concat(tokens.items[tokens.items.len - 1], line);
            } else try tokens.append(s.engine.gpa, line);
        }
    } else {
        const chars = "a-zA-Z0-9_\\u{AD}\\u{C0}-\\u{D6}\\u{D8}-\\u{F6}\\u{F8}-\\u{2C6}\\u{2C8}-\\u{2D7}\\u{2DE}-\\u{2FF}\\u{1E00}-\\u{1EFF}";
        const pieces = try s.invoke(text, "match", &.{try regex(s, "[" ++ chars ++ "]+|\\s+|[^" ++ chars ++ "]", "ug")});
        const whitespace = try regex(s, "\\s", "");
        var previous = c.pi_js_null();
        const count = if (s.truthy(pieces)) try length(s, pieces) else 0;
        for (0..count) |index| {
            const part = try at(s, pieces, index);
            if (s.truthy(try s.invoke(whitespace, "test", &.{part}))) {
                if (c.JS_IsNull(previous)) try tokens.append(s.engine.gpa, part) else tokens.items[tokens.items.len - 1] = try s.concat(tokens.items[tokens.items.len - 1], part);
            } else if (!c.JS_IsNull(previous) and s.truthy(try s.invoke(whitespace, "test", &.{previous}))) {
                if (s.equal(tokens.items[tokens.items.len - 1], previous)) tokens.items[tokens.items.len - 1] = try s.concat(tokens.items[tokens.items.len - 1], part) else try tokens.append(s.engine.gpa, try s.concat(previous, part));
            } else try tokens.append(s.engine.gpa, part);
            previous = part;
        }
    }
    var destination: usize = 0;
    for (tokens.items) |token| if (s.truthy(token)) {
        tokens.items[destination] = token;
        destination += 1;
    };
    tokens.shrinkRetainingCapacity(destination);
    return tokens.toOwnedSlice(s.engine.gpa);
}
fn join(s: *Scope, mode: Mode, tokens: []const c.JSValue) !c.JSValue {
    var out = try s.text("");
    const leading_pattern = if (mode == .words) try regex(s, "^\\s+", "") else c.pi_js_undefined();
    for (tokens, 0..) |token, index| out = try s.concat(out, if (mode == .words and index != 0) try s.invoke(token, "replace", &.{ leading_pattern, try s.text("") }) else token);
    return out;
}
fn diff(engine: *em.Engine, mode: Mode, old: c.JSValue, newer: c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    const older_tokens = try tokenize(&s, mode, old);
    defer engine.gpa.free(older_tokens);
    const newer_tokens = try tokenize(&s, mode, newer);
    defer engine.gpa.free(newer_tokens);
    var work: Work = .{ .s = &s, .mode = mode };
    defer work.nodes.deinit(engine.gpa);
    var best: std.AutoHashMap(isize, Path) = .init(engine.gpa);
    defer best.deinit();
    const abort_after = try s.own(try engine.checked(c.JS_PiBinaryOperator(engine.context, 0, try s.invoke(try s.global("Date"), "now", &.{}), c.JS_NewFloat64(engine.context, std.math.inf(f64)))));
    var first: Path = .{};
    const initial_new = try work.common(&first, newer_tokens, older_tokens, 0);
    try best.put(0, first);
    const old_len: isize = @intCast(older_tokens.len);
    const new_len: isize = @intCast(newer_tokens.len);
    if (first.old_pos + 1 >= old_len and initial_new + 1 >= new_len) return c.JS_DupValue(engine.context, try work.values(first.last, newer_tokens, older_tokens));
    var min_diagonal: isize = std.math.minInt(isize);
    var max_diagonal: isize = std.math.maxInt(isize);
    var edits: isize = 1;
    while (edits <= old_len + new_len) : (edits += 1) {
        const now = try s.invoke(try s.global("Date"), "now", &.{});
        if (!s.truthy(try s.own(try engine.checked(c.JS_PiBinaryOperator(engine.context, 5, now, abort_after))))) break;
        try work.tick();
        var diagonal = @max(min_diagonal, -edits);
        while (diagonal <= @min(max_diagonal, edits)) : (diagonal += 2) {
            try work.tick();
            const remove = best.get(diagonal - 1);
            const add = best.get(diagonal + 1);
            if (remove != null) _ = best.remove(diagonal - 1);
            const can_add = if (add) |path| path.old_pos - diagonal >= 0 and path.old_pos - diagonal < new_len else false;
            const can_remove = if (remove) |path| path.old_pos + 1 < old_len else false;
            if (!can_add and !can_remove) {
                _ = best.remove(diagonal);
                continue;
            }
            var path = if (!can_remove or (can_add and remove.?.old_pos < add.?.old_pos)) try work.add(add.?, .add) else try work.add(remove.?, .remove);
            const new_pos = try work.common(&path, newer_tokens, older_tokens, diagonal);
            if (path.old_pos + 1 >= old_len and new_pos + 1 >= new_len) return c.JS_DupValue(engine.context, try work.values(path.last, newer_tokens, older_tokens));
            try best.put(diagonal, path);
            if (path.old_pos + 1 >= old_len) max_diagonal = @min(max_diagonal, diagonal - 1);
            if (new_pos + 1 >= new_len) min_diagonal = @max(min_diagonal, diagonal + 1);
        }
    }
    return c.pi_js_undefined();
}
pub fn diffLines(engine: *em.Engine, old: c.JSValue, newer: c.JSValue) !c.JSValue {
    return diff(engine, .lines, old, newer);
}
pub fn diffWords(engine: *em.Engine, old: c.JSValue, newer: c.JSValue) !c.JSValue {
    return diff(engine, .words, old, newer);
}

// Whitespace cleanup is authored below against util/string and word.js.
fn postProcess(s: *Scope, changes: c.JSValue) !void {
    var last_keep = c.pi_js_null();
    var insertion = c.pi_js_null();
    var deletion = c.pi_js_null();
    for (0..try length(s, changes)) |index| {
        const change = try at(s, changes, index);
        if (s.truthy(try s.get(change, "added"))) insertion = change else if (s.truthy(try s.get(change, "removed"))) deletion = change else {
            if (s.truthy(insertion) or s.truthy(deletion)) try dedupe(s, last_keep, deletion, insertion, change);
            last_keep = change;
            insertion = c.pi_js_null();
            deletion = c.pi_js_null();
        }
    }
    if (s.truthy(insertion) or s.truthy(deletion)) try dedupe(s, last_keep, deletion, insertion, c.pi_js_null());
}
fn leading(s: *Scope, value: c.JSValue) !c.JSValue {
    const matched = try s.invoke(value, "match", &.{try regex(s, "^\\s*", "")});
    return if (s.truthy(matched)) at(s, matched, 0) else s.text("");
}
fn trailing(s: *Scope, value: c.JSValue) !c.JSValue {
    const whitespace = try regex(s, "\\s", "");
    var start = try length(s, value);
    while (start != 0 and s.truthy(try s.invoke(whitespace, "test", &.{try at(s, value, start - 1)}))) start -= 1;
    return slice(s, value, @intCast(start), null);
}
fn commonEdge(s: *Scope, left: c.JSValue, right: c.JSValue, suffix: bool) !c.JSValue {
    const left_len = try length(s, left);
    const right_len = try length(s, right);
    var count: usize = 0;
    while (count < left_len and count < right_len and s.equal(try at(s, left, if (suffix) left_len - count - 1 else count), try at(s, right, if (suffix) right_len - count - 1 else count))) count += 1;
    return if (suffix) slice(s, left, @intCast(left_len - count), null) else slice(s, left, 0, @intCast(count));
}
fn replaceEdge(s: *Scope, text: c.JSValue, old: c.JSValue, replacement: c.JSValue, suffix: bool) !c.JSValue {
    const old_len = try length(s, old);
    const text_len = try length(s, text);
    const existing = if (suffix) try slice(s, text, @intCast(text_len -| old_len), null) else try slice(s, text, 0, @intCast(old_len));
    if (!s.equal(existing, old) and !(suffix and old_len == 0)) {
        _ = try s.engine.checked(c.JS_ThrowInternalError(s.engine.context, "jsdiff whitespace edge invariant failed"));
        unreachable;
    }
    return if (suffix) s.concat(try slice(s, text, 0, @intCast(text_len - old_len)), replacement) else s.concat(replacement, try slice(s, text, @intCast(old_len), null));
}
fn removeEdge(s: *Scope, text: c.JSValue, old: c.JSValue, suffix: bool) !c.JSValue {
    return replaceEdge(s, text, old, try s.text(""), suffix);
}
fn overlap(s: *Scope, left: c.JSValue, right: c.JSValue) !c.JSValue {
    // Source's actual KMP overlapCount, in VM UTF16 units.
    const right_len = try length(s, right);
    const left_len = try length(s, left);
    const end = @min(left_len, right_len);
    const map = try s.engine.gpa.alloc(usize, @max(end, 1));
    defer s.engine.gpa.free(map);
    map[0] = 0;
    var k: usize = 0;
    for (1..@max(end, 1)) |j| {
        map[j] = if (s.equal(try at(s, right, j), try at(s, right, k))) map[k] else k;
        while (k > 0 and !s.equal(try at(s, right, j), try at(s, right, k))) k = map[k];
        if (s.equal(try at(s, right, j), try at(s, right, k))) k += 1;
    }
    k = 0;
    for (left_len - end..left_len) |index| {
        while (k > 0 and !s.equal(try at(s, left, index), try at(s, right, k))) k = map[k];
        if (s.equal(try at(s, left, index), try at(s, right, k))) k += 1;
    }
    return slice(s, right, 0, @intCast(k));
}
fn partValue(s: *Scope, object: c.JSValue) !c.JSValue {
    return s.get(object, "value");
}
fn dedupe(s: *Scope, start: c.JSValue, deleted: c.JSValue, inserted: c.JSValue, end: c.JSValue) !void {
    if (s.truthy(deleted) and s.truthy(inserted)) {
        const old_prefix = try leading(s, try partValue(s, deleted));
        const old_suffix = try trailing(s, try partValue(s, deleted));
        const new_prefix = try leading(s, try partValue(s, inserted));
        const new_suffix = try trailing(s, try partValue(s, inserted));
        if (s.truthy(start)) {
            const common = try commonEdge(s, old_prefix, new_prefix, false);
            try s.set(start, "value", try replaceEdge(s, try partValue(s, start), new_prefix, common, true));
            try s.set(deleted, "value", try removeEdge(s, try partValue(s, deleted), common, false));
            try s.set(inserted, "value", try removeEdge(s, try partValue(s, inserted), common, false));
        }
        if (s.truthy(end)) {
            const common = try commonEdge(s, old_suffix, new_suffix, true);
            try s.set(end, "value", try replaceEdge(s, try partValue(s, end), new_suffix, common, false));
            try s.set(deleted, "value", try removeEdge(s, try partValue(s, deleted), common, true));
            try s.set(inserted, "value", try removeEdge(s, try partValue(s, inserted), common, true));
        }
    } else if (s.truthy(inserted)) {
        if (s.truthy(start)) {
            const ws = try leading(s, try partValue(s, inserted));
            try s.set(inserted, "value", try slice(s, try partValue(s, inserted), @intCast(try length(s, ws)), null));
        }
        if (s.truthy(end)) {
            const ws = try leading(s, try partValue(s, end));
            try s.set(end, "value", try slice(s, try partValue(s, end), @intCast(try length(s, ws)), null));
        }
    } else if (s.truthy(start) and s.truthy(end)) {
        const full = try leading(s, try partValue(s, end));
        const del_start = try leading(s, try partValue(s, deleted));
        const del_end = try trailing(s, try partValue(s, deleted));
        const ws_start = try commonEdge(s, full, del_start, false);
        try s.set(deleted, "value", try removeEdge(s, try partValue(s, deleted), ws_start, false));
        const ws_end = try commonEdge(s, try removeEdge(s, full, ws_start, false), del_end, true);
        try s.set(deleted, "value", try removeEdge(s, try partValue(s, deleted), ws_end, true));
        try s.set(end, "value", try replaceEdge(s, try partValue(s, end), full, ws_end, false));
        const remainder = try slice(s, full, 0, @intCast((try length(s, full)) - (try length(s, ws_end))));
        try s.set(start, "value", try replaceEdge(s, try partValue(s, start), full, remainder, true));
    } else if (s.truthy(end)) {
        const prefix = try leading(s, try partValue(s, end));
        const suffix = try trailing(s, try partValue(s, deleted));
        try s.set(deleted, "value", try removeEdge(s, try partValue(s, deleted), try overlap(s, suffix, prefix), true));
    } else if (s.truthy(start)) {
        const suffix = try trailing(s, try partValue(s, start));
        const prefix = try leading(s, try partValue(s, deleted));
        try s.set(deleted, "value", try removeEdge(s, try partValue(s, deleted), try overlap(s, suffix, prefix), false));
    }
}
