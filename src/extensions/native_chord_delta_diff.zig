//! Native port of chord/src/delta/diff.ts at e6220e1316f86af818a0ccbfe1c09d7e918b41cf.
//! Operates on live VM values; identity matching never serializes its inputs.
const std = @import("std");
const values = @import("native_chord_values.zig");
const js = values.js;
const c = js.c;
const utf16 = @import("native_utf16.zig");
const vm = @import("native_values.zig");
const Match = struct { before: usize, after: usize };
const Candidate = struct { match: Match, previous: ?usize };
const List = std.ArrayList(Match);
const View = struct {
    value: c.JSValue,
    len: usize,
    fn at(self: View, state: *State, index: usize) !c.JSValue {
        return state.scope.at(self.value, index);
    }
};

pub fn diffRevisions(engine: *js.Engine, before: c.JSValue, after: c.JSValue) !c.JSValue {
    var state: State = .{ .scope = .{ .engine = engine }, .operations = undefined };
    defer state.scope.deinit();
    state.operations = try state.scope.list();
    const path = try state.scope.list();
    try state.diffValue(before, after, path);
    if (state.overflow) return state.replacement(after);
    if (state.count == 0) return state.scope.result(state.operations);
    const first = try state.scope.at(state.operations, 0);
    if (try state.scope.equal(try state.scope.at(first, 0), "r")) return state.scope.result(state.operations);
    var cost: usize = 2;
    for (0..state.count) |index| cost +|= (try state.operationCost(try state.scope.at(state.operations, index))) +| 1;
    if (cost >= 65536 and cost >= (try state.jsonCost(after)) +| 6) return state.replacement(after);
    return state.scope.result(state.operations);
}

pub fn function(engine: *js.Engine) !c.JSValue {
    return @import("native_node_function.zig").create(engine, "diffRevisions", 2, callback, &.{});
}
fn callback(engine: *js.Engine, _: c.JSValue, args: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
    return diffRevisions(engine, if (args.len > 0) args[0] else c.pi_js_undefined(), if (args.len > 1) args[1] else c.pi_js_undefined());
}

const State = struct {
    scope: values.Scope,
    operations: c.JSValue,
    count: usize = 0,
    overflow: bool = false,
    steps: usize = 0,
    fn tick(self: *State) !void {
        self.steps +|= 1;
        const engine = self.scope.engine;
        if (engine.cancelled.load(.acquire) or (self.steps % 256 == 0 and blk: {
            engine.interrupts +|= 1;
            break :blk engine.interrupts > engine.options.interrupt_budget;
        })) {
            _ = try engine.checked(c.JS_ThrowInternalError(engine.context, "interrupted"));
        }
    }
    fn number(self: *State, n: usize) c.JSValue {
        return c.JS_NewFloat64(self.scope.engine.context, @floatFromInt(n));
    }
    fn len(self: *State, value: c.JSValue) !usize {
        return vm.length(self.scope.engine, value);
    }
    fn strict(self: *State, left: c.JSValue, right: c.JSValue) bool {
        return c.JS_IsStrictEqual(self.scope.engine.context, left, right);
    }
    fn container(self: *State, value: c.JSValue) bool {
        return c.JS_IsObject(value) and !c.JS_IsFunction(self.scope.engine.context, value);
    }
    fn isArray(self: *State, value: c.JSValue) !bool {
        // QuickJS-NG JS_IsArray deliberately does not inspect proxy targets.
        // The Source uses Array.isArray, including revoked-proxy exceptions.
        const result = try self.scope.builtin("Array", "isArray", &.{value});
        return c.JS_ToBool(self.scope.engine.context, result) != 0;
    }
    fn hasOwn(self: *State, object: c.JSValue, key: c.JSValue) !bool {
        const result = try self.scope.builtin("Object", "hasOwn", &.{ object, key });
        return c.JS_ToBool(self.scope.engine.context, result) != 0;
    }
    fn equalJson(self: *State, left: c.JSValue, right: c.JSValue) anyerror!bool {
        try self.tick();
        if (self.strict(left, right)) return true;
        if (!self.container(left) or !self.container(right) or try self.isArray(left) != try self.isArray(right)) return false;
        if (try self.isArray(left)) {
            const count = try self.len(left);
            if (count != try self.len(right)) return false;
            for (0..count) |index| if (!try self.equalJson(try self.scope.at(left, index), try self.scope.at(right, index))) return false;
            return true;
        }
        const keys = try self.scope.keys(left);
        const count = try self.len(keys);
        if (count != try self.len(try self.scope.keys(right))) return false;
        for (0..count) |index| {
            const key = try self.scope.at(keys, index);
            if (!try self.hasOwn(right, key) or !try self.equalJson(try self.scope.key(left, key), try self.scope.key(right, key))) return false;
        }
        return true;
    }
    fn same(self: *State, left: c.JSValue, right: c.JSValue) !bool {
        return self.strict(left, right) or try self.equalJson(left, right);
    }
    fn emit(self: *State, tag: []const u8, args: []const c.JSValue) !void {
        if (self.overflow) return;
        if (self.count >= 4096) {
            self.overflow = true;
            return;
        }
        const op = try self.scope.list();
        try js.push(self.scope.engine, op, try self.scope.text(tag));
        for (args) |arg| try js.push(self.scope.engine, op, arg);
        try js.push(self.scope.engine, self.operations, op);
        self.count += 1;
    }
    fn replacement(self: *State, value: c.JSValue) !c.JSValue {
        const batch = try self.scope.list();
        const op = try self.scope.list();
        try js.push(self.scope.engine, op, try self.scope.text("r"));
        try js.push(self.scope.engine, op, value);
        try js.push(self.scope.engine, batch, op);
        return self.scope.result(batch);
    }
    fn emitSet(self: *State, path: c.JSValue, value: c.JSValue) !void {
        if (try self.len(path) == 0) return self.emit("r", &.{value});
        return self.emit("s", &.{ path, value });
    }
    fn childPath(self: *State, path: c.JSValue, key: c.JSValue) !c.JSValue {
        const result = try self.scope.keep(try js.invoke(self.scope.engine, path, "slice", &.{}));
        try js.push(self.scope.engine, result, key);
        return result;
    }
    fn emitString(self: *State, before: c.JSValue, after: c.JSValue, path: c.JSValue) !void {
        const engine = self.scope.engine;
        const a = try utf16.unitsAlloc(engine, before);
        defer engine.gpa.free(a);
        const b = try utf16.unitsAlloc(engine, after);
        defer engine.gpa.free(b);
        if (b.len > a.len and std.mem.eql(u16, a, b[0..a.len])) {
            const suffix = try self.scope.keep(try utf16.string(engine, b[a.len..]));
            return self.emit("a", &.{ path, suffix });
        }
        const shared = overlap(a, b);
        if (shared == 0) return self.emit("s", &.{ path, after });
        try self.emit("t", &.{ path, self.number(a.len - shared) });
        if (b.len > shared) try self.emit("a", &.{ path, try self.scope.keep(try utf16.string(engine, b[shared..])) });
    }
    fn diffValue(self: *State, before: c.JSValue, after: c.JSValue, path: c.JSValue) anyerror!void {
        try self.tick();
        if (self.strict(before, after) or self.overflow) return;
        if (c.JS_IsString(before) and c.JS_IsString(after) and try self.len(path) > 0) return self.emitString(before, after, path);
        if (try self.isArray(before) and try self.isArray(after)) return self.diffArray(before, after, path);
        if (self.container(before) and self.container(after) and !try self.isArray(before) and !try self.isArray(after)) return self.diffObject(before, after, path);
        return self.emitSet(path, after);
    }
    fn reserved(self: *State, keys: c.JSValue) !bool {
        for (0..try self.len(keys)) |index| {
            const key = try self.scope.at(keys, index);
            if (try self.scope.equal(key, "__proto__") or try self.scope.equal(key, "constructor") or try self.scope.equal(key, "prototype")) return true;
        }
        return false;
    }
    fn diffObject(self: *State, before: c.JSValue, after: c.JSValue, path: c.JSValue) !void {
        const before_keys = try self.scope.keys(before);
        const after_keys = try self.scope.keys(after);
        if (try self.reserved(before_keys) or try self.reserved(after_keys)) {
            if (!try self.equalJson(before, after)) try self.emitSet(path, after);
            return;
        }
        for (0..try self.len(after_keys)) |index| {
            if (self.overflow) return;
            const key = try self.scope.at(after_keys, index);
            const child = try self.childPath(path, key);
            const value = try self.scope.key(after, key);
            if (try self.hasOwn(before, key)) try self.diffValue(try self.scope.key(before, key), value, child) else try self.emitSet(child, value);
        }
        for (0..try self.len(before_keys)) |index| {
            if (self.overflow) return;
            const key = try self.scope.at(before_keys, index);
            if (!try self.hasOwn(after, key)) try self.emit("d", &.{try self.childPath(path, key)});
        }
    }
    fn view(self: *State, value: c.JSValue) !View {
        return .{ .value = value, .len = try self.len(value) };
    }
    fn slice(self: *State, value: View, start: usize, end: usize) !View {
        return self.view(try self.scope.keep(try js.invoke(self.scope.engine, value.value, "slice", &.{ self.number(start), self.number(end) })));
    }
    fn diffArray(self: *State, before: c.JSValue, after: c.JSValue, path: c.JSValue) !void {
        if (try self.equalJson(before, after)) return;
        const a = try self.view(before);
        const b = try self.view(after);
        if (a.len == b.len and a.len > 1 and !try self.same(try a.at(self, 0), try b.at(self, 0)) and !try self.same(try a.at(self, a.len - 1), try b.at(self, b.len - 1))) {
            if (try self.permutation(a, b)) |order| {
                try self.emit("m", &.{ path, order });
                return;
            }
        }
        return self.region(a, b, path, 0, a.len, 0, b.len, 0);
    }
    fn permutation(self: *State, a: View, b: View) !?c.JSValue {
        var positions = try Positions.init(self, a, 0, a.len);
        defer positions.deinit();
        const result = try self.scope.list();
        for (0..b.len) |index| {
            const bucket = (try positions.get(try b.at(self, index))) orelse return null;
            if (bucket.used == bucket.indices.items.len) return null;
            try js.push(self.scope.engine, result, self.number(bucket.indices.items[bucket.used]));
            bucket.used += 1;
        }
        return result;
    }
    fn semantic(self: *State, a: c.JSValue, b: c.JSValue) !bool {
        if (try self.same(a, b)) return true;
        if (!self.container(a) or !self.container(b) or try self.isArray(a) != try self.isArray(b)) return false;
        if (try self.isArray(a)) {
            const count = try self.len(a);
            if (count != try self.len(b)) return false;
            for (0..count) |index| {
                const child = try self.scope.at(a, index);
                if (self.container(child) and self.strict(child, try self.scope.at(b, index))) return true;
            }
            return false;
        }
        const keys = try self.scope.keys(a);
        for (0..try self.len(keys)) |index| {
            const key = try self.scope.at(keys, index);
            const child = try self.scope.key(a, key);
            if (self.container(child) and try self.hasOwn(b, key) and self.strict(child, try self.scope.key(b, key))) return true;
        }
        return false;
    }
    fn lcs(self: *State, a: View, b: View, astart: usize, aend: usize, bstart: usize, bend: usize) !List {
        var result: List = .empty;
        errdefer result.deinit(self.scope.engine.gpa);
        const n = aend - astart;
        const m = bend - bstart;
        if (n == 0 or m == 0 or n > 65536 / m) return result;
        const width = m + 1;
        const lengths = try self.scope.engine.gpa.alloc(u32, (n + 1) * width);
        defer self.scope.engine.gpa.free(lengths);
        @memset(lengths, 0);
        var left = n;
        while (left > 0) {
            left -= 1;
            var right = m;
            while (right > 0) {
                right -= 1;
                const at = left * width + right;
                lengths[at] = if (try self.semantic(try a.at(self, astart + left), try b.at(self, bstart + right))) lengths[(left + 1) * width + right + 1] + 1 else @max(lengths[(left + 1) * width + right], lengths[left * width + right + 1]);
            }
        }
        left = 0;
        var right: usize = 0;
        while (left < n and right < m) {
            if (try self.semantic(try a.at(self, astart + left), try b.at(self, bstart + right)) and lengths[left * width + right] == lengths[(left + 1) * width + right + 1] + 1) {
                try result.append(self.scope.engine.gpa, .{ .before = astart + left, .after = bstart + right });
                left += 1;
                right += 1;
            } else if (lengths[(left + 1) * width + right] >= lengths[left * width + right + 1]) left += 1 else right += 1;
        }
        return result;
    }
    fn subsequence(self: *State, a: View, b: View, astart: usize, aend: usize, bstart: usize, bend: usize) !List {
        var result: List = .empty;
        errdefer result.deinit(self.scope.engine.gpa);
        if (bend - bstart < aend - astart) {
            var i = astart;
            for (bstart..bend) |j| {
                while (i < aend and !self.strict(try a.at(self, i), try b.at(self, j))) : (i += 1) {}
                if (i == aend) {
                    result.clearRetainingCapacity();
                    return result;
                }
                try result.append(self.scope.engine.gpa, .{ .before = i, .after = j });
                i += 1;
            }
        } else if (aend - astart < bend - bstart) {
            var j = bstart;
            for (astart..aend) |i| {
                while (j < bend and !self.strict(try a.at(self, i), try b.at(self, j))) : (j += 1) {}
                if (j == bend) {
                    result.clearRetainingCapacity();
                    return result;
                }
                try result.append(self.scope.engine.gpa, .{ .before = i, .after = j });
                j += 1;
            }
        }
        return result;
    }
    fn anchors(self: *State, a: View, b: View, astart: usize, aend: usize, bstart: usize, bend: usize) !List {
        const allocator = self.scope.engine.gpa;
        var result: List = .empty;
        errdefer result.deinit(allocator);
        var positions = try Positions.init(self, a, astart, aend);
        defer positions.deinit();
        var count: usize = 0;
        for (bstart..bend) |count_index| {
            if (try positions.get(try b.at(self, count_index))) |bucket| count +|= bucket.indices.items.len;
            if (count > 200000) {
                var previous: ?usize = null;
                for (bstart..bend) |j| {
                    const bucket = (try positions.get(try b.at(self, j))) orelse continue;
                    const at = lowerBound(bucket.indices.items, if (previous) |p| p + 1 else 0);
                    if (at == bucket.indices.items.len) continue;
                    const i = bucket.indices.items[at];
                    try result.append(allocator, .{ .before = i, .after = j });
                    previous = i;
                }
                return result;
            }
        }
        if (count == 0) return result;
        var candidates: std.ArrayList(Candidate) = .empty;
        defer candidates.deinit(allocator);
        var tails: std.ArrayList(usize) = .empty;
        defer tails.deinit(allocator);
        var tail_values: std.ArrayList(usize) = .empty;
        defer tail_values.deinit(allocator);
        for (bstart..bend) |j| {
            const bucket = (try positions.get(try b.at(self, j))) orelse continue;
            var n = bucket.indices.items.len;
            while (n > 0) {
                n -= 1;
                const i = bucket.indices.items[n];
                const at = lowerBound(tail_values.items, i);
                const ci = candidates.items.len;
                try candidates.append(allocator, .{ .match = .{ .before = i, .after = j }, .previous = if (at == 0) null else tails.items[at - 1] });
                if (at == tails.items.len) {
                    try tails.append(allocator, ci);
                    try tail_values.append(allocator, i);
                } else {
                    tails.items[at] = ci;
                    tail_values.items[at] = i;
                }
            }
        }
        var ci: ?usize = if (tails.items.len == 0) null else tails.items[tails.items.len - 1];
        while (ci) |index| {
            try result.append(allocator, candidates.items[index].match);
            ci = candidates.items[index].previous;
        }
        std.mem.reverse(Match, result.items);
        return result;
    }
    fn matches(self: *State, a: View, b: View, path: c.JSValue, astart: usize, aend: usize, bstart: usize, bend: usize, output: usize, pairs: []const Match) anyerror!void {
        var ai = astart;
        var bi = bstart;
        var out = output;
        for (pairs) |pair| {
            if (self.overflow) return;
            try self.region(a, b, path, ai, pair.before, bi, pair.after, out);
            out += pair.after - bi;
            if (!try self.same(try a.at(self, pair.before), try b.at(self, pair.after))) try self.diffValue(try a.at(self, pair.before), try b.at(self, pair.after), try self.childPath(path, self.number(out)));
            out += 1;
            ai = pair.before + 1;
            bi = pair.after + 1;
        }
        if (!self.overflow) try self.region(a, b, path, ai, aend, bi, bend, out);
    }
    fn splice(self: *State, b: View, start: usize, end: usize, path: c.JSValue, output: usize, remove: usize) !void {
        const inserted = try self.slice(b, start, end);
        try self.emit("p", &.{ path, self.number(output), self.number(remove), inserted.value });
    }
    fn region(self: *State, a: View, b: View, path: c.JSValue, astart: usize, aend: usize, bstart: usize, bend: usize, output: usize) anyerror!void {
        if (self.overflow) return;
        var ai = astart;
        var ae = aend;
        var bi = bstart;
        var be = bend;
        var out = output;
        while (ai < ae and bi < be and try self.same(try a.at(self, ai), try b.at(self, bi))) {
            ai += 1;
            bi += 1;
            out += 1;
        }
        while (ai < ae and bi < be and try self.same(try a.at(self, ae - 1), try b.at(self, be - 1))) {
            ae -= 1;
            be -= 1;
        }
        const n = ae - ai;
        const m = be - bi;
        if (n == 0 and m == 0) return;
        if (n == 0 or m == 0) return self.splice(b, bi, be, path, out, n);
        const allocator = self.scope.engine.gpa;
        if (n == m) {
            var positional: List = .empty;
            defer positional.deinit(allocator);
            for (0..n) |offset| if (try self.same(try a.at(self, ai + offset), try b.at(self, bi + offset))) try positional.append(allocator, .{ .before = ai + offset, .after = bi + offset });
            if (positional.items.len > 0) return self.matches(a, b, path, ai, ae, bi, be, out, positional.items);
        }
        var sub = try self.subsequence(a, b, ai, ae, bi, be);
        defer sub.deinit(allocator);
        if (sub.items.len > 0) return self.matches(a, b, path, ai, ae, bi, be, out, sub.items);
        var identity = try self.anchors(a, b, ai, ae, bi, be);
        defer identity.deinit(allocator);
        if (identity.items.len > 0) return self.matches(a, b, path, ai, ae, bi, be, out, identity.items);
        const semantic_a = try self.slice(a, ai, ae);
        const semantic_b = try self.slice(b, bi, be);
        var semantic_matches = try self.lcs(semantic_a, semantic_b, 0, n, 0, m);
        defer semantic_matches.deinit(allocator);
        for (semantic_matches.items) |*pair| {
            pair.before += ai;
            pair.after += bi;
        }
        if (semantic_matches.items.len > 0) return self.matches(a, b, path, ai, ae, bi, be, out, semantic_matches.items);
        if (n == 1 and m == 1) return self.diffValue(try a.at(self, ai), try b.at(self, bi), try self.childPath(path, self.number(out)));
        return self.splice(b, bi, be, path, out, n);
    }
    fn stringCost(self: *State, value: c.JSValue) !usize {
        const text = try self.scope.keep(try self.scope.engine.checked(c.JS_ToString(self.scope.engine.context, value)));
        const units = try utf16.unitsAlloc(self.scope.engine, text);
        defer self.scope.engine.gpa.free(units);
        return units.len;
    }
    fn jsonCost(self: *State, value: c.JSValue) anyerror!usize {
        try self.tick();
        if (c.JS_IsNull(value)) return 4;
        if (c.JS_IsString(value)) return (try self.stringCost(value)) +| 2;
        if (c.JS_IsNumber(value)) return self.stringCost(value);
        if (c.JS_IsBool(value)) return if (c.JS_ToBool(self.scope.engine.context, value) != 0) 4 else 5;
        var cost: usize = 2;
        if (try self.isArray(value)) {
            for (0..try self.len(value)) |index| cost +|= (try self.jsonCost(try self.scope.at(value, index))) +| @intFromBool(index != 0);
            return cost;
        }
        const keys = try self.scope.keys(value);
        for (0..try self.len(keys)) |index| {
            const key = try self.scope.at(keys, index);
            cost +|= (try self.stringCost(key)) +| 3 +| (try self.jsonCost(try self.scope.key(value, key))) +| @intFromBool(index != 0);
        }
        return cost;
    }
    fn pathCost(self: *State, path: c.JSValue) !usize {
        var cost: usize = 2;
        for (0..try self.len(path)) |index| {
            const segment = try self.scope.at(path, index);
            cost +|= (try self.stringCost(segment)) +| (if (c.JS_IsString(segment)) @as(usize, 2) else 0) +| @intFromBool(index != 0);
        }
        return cost;
    }
    fn operationCost(self: *State, op: c.JSValue) !usize {
        const tag = try self.scope.at(op, 0);
        const path = try self.scope.at(op, 1);
        if (try self.scope.equal(tag, "r")) return 6 +| try self.jsonCost(path);
        const pc = try self.pathCost(path);
        if (try self.scope.equal(tag, "d")) return 6 +| pc;
        const operand = try self.scope.at(op, 2);
        if (try self.scope.equal(tag, "s") or try self.scope.equal(tag, "m")) return 7 +| pc +| try self.jsonCost(operand);
        if (try self.scope.equal(tag, "a")) return 9 +| pc +| try self.stringCost(operand);
        if (try self.scope.equal(tag, "t")) return 7 +| pc +| try self.stringCost(operand);
        return 10 +| pc +| (try self.stringCost(operand)) +| (try self.stringCost(try self.scope.at(op, 3))) +| (try self.jsonCost(try self.scope.at(op, 4)));
    }
};

const Bucket = struct { indices: std.ArrayList(usize) = .empty, used: usize = 0 };
const Positions = struct {
    state: *State,
    map: c.JSValue,
    buckets: std.ArrayList(Bucket) = .empty,
    fn init(state: *State, input: View, start: usize, end: usize) !Positions {
        var self: Positions = .{ .state = state, .map = try state.scope.keep(try js.builtin(state.scope.engine, "Map", &.{})) };
        errdefer self.deinit();
        for (start..end) |index| {
            const value = try input.at(state, index);
            if (try self.get(value)) |bucket| {
                try bucket.indices.append(state.scope.engine.gpa, index);
            } else {
                const id = self.buckets.items.len;
                try self.buckets.append(state.scope.engine.gpa, .{});
                try self.buckets.items[id].indices.append(state.scope.engine.gpa, index);
                const ignored = try js.invoke(state.scope.engine, self.map, "set", &.{ value, state.number(id) });
                state.scope.engine.freeValue(ignored);
            }
        }
        return self;
    }
    fn deinit(self: *Positions) void {
        for (self.buckets.items) |*bucket| bucket.indices.deinit(self.state.scope.engine.gpa);
        self.buckets.deinit(self.state.scope.engine.gpa);
    }
    fn get(self: *Positions, key: c.JSValue) !?*Bucket {
        const engine = self.state.scope.engine;
        const id = try js.invoke(engine, self.map, "get", &.{key});
        defer engine.freeValue(id);
        if (c.JS_IsUndefined(id)) return null;
        var index: u32 = 0;
        if (c.JS_ToUint32(engine.context, &index, id) < 0) return js.capture(engine);
        return &self.buckets.items[index];
    }
};
fn lowerBound(values_: []const usize, value: usize) usize {
    var low: usize = 0;
    var high = values_.len;
    while (low < high) {
        const middle = (low + high) / 2;
        if (values_[middle] < value) low = middle + 1 else high = middle;
    }
    return low;
}
fn overlap(a: []const u16, b: []const u16) usize {
    if (a.len == 0 or b.len == 0) return 0;
    const tail = a[a.len - @min(a.len, 65536) ..];
    for ([_]usize{ @min(64, b.len), 1 }) |head_length| {
        var tried: usize = 0;
        var start: usize = 0;
        while (std.mem.indexOfPos(u16, tail, start, b[0..head_length])) |at| {
            tried += 1;
            if (tried > 8) break;
            const n = tail.len - at;
            if (n <= b.len and std.mem.eql(u16, tail[at..], b[0..n])) return n;
            start = at + 1;
        }
        if (head_length == 1) break;
    }
    return 0;
}
