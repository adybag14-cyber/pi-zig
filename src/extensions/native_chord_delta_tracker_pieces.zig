//! Source tracker.ts array identity tree and structural operation plans.
//! Insert source IDs index the owning overlay's GC-marked StoredRef sources.
//! Path copying preserves the previous tree if native allocation fails mid-edit.
const std = @import("std");
pub const Piece = struct {
    source: ?usize = null,
    start: usize,
    length: usize,
    step: i8 = 1,
    pub fn index(self: Piece, offset: usize) usize {
        return if (self.step == 1) self.start + offset else self.start - offset;
    }
    fn sameSource(self: Piece, other: Piece) bool {
        return self.source == other.source;
    }
};
const Node = struct {
    piece: Piece,
    left: ?*const Node = null,
    right: ?*const Node = null,
    priority: u32,
    elements: usize,
};
pub const Location = struct { piece: Piece, offset: usize };
pub const Remove = struct { start: usize, length: usize };
pub const Insert = struct { logical: usize, first: usize, end: usize };
pub const Plan = struct {
    allocator: std.mem.Allocator,
    removes: std.ArrayList(Remove) = .empty,
    permutation: ?[]usize = null,
    inserts: std.ArrayList(Insert) = .empty,
    pub fn deinit(self: *Plan) void {
        self.removes.deinit(self.allocator);
        if (self.permutation) |p| self.allocator.free(p);
        self.inserts.deinit(self.allocator);
    }
};
pub const Tree = struct {
    allocator: std.mem.Allocator,
    root: ?*const Node = null,
    allocated: std.ArrayList(*Node) = .empty,
    seed: u32 = 0x9e3779b9,
    structural: bool = false,
    generation: usize = 0,
    pub fn init(allocator: std.mem.Allocator, base_length: usize) !Tree {
        var self: Tree = .{ .allocator = allocator };
        errdefer self.deinit();
        if (base_length > 0) self.root = try self.new(.{ .start = 0, .length = base_length });
        return self;
    }
    pub fn deinit(self: *Tree) void {
        for (self.allocated.items) |node| self.allocator.destroy(node);
        self.allocated.deinit(self.allocator);
    }
    pub fn length(self: *const Tree) usize {
        return elements(self.root);
    }
    fn priority(self: *Tree) u32 {
        var value = self.seed;
        value ^= value << 13;
        value ^= value >> 17;
        value ^= value << 5;
        self.seed = value;
        return value;
    }
    fn allocate(self: *Tree, node: Node) !*const Node {
        const owned = try self.allocator.create(Node);
        errdefer self.allocator.destroy(owned);
        owned.* = node;
        try self.allocated.append(self.allocator, owned);
        return owned;
    }
    fn new(self: *Tree, piece: Piece) !*const Node {
        return self.allocate(.{ .piece = piece, .priority = self.priority(), .elements = piece.length });
    }
    fn copy(self: *Tree, node: *const Node, left: ?*const Node, right: ?*const Node) !*const Node {
        var next = node.*;
        next.left = left;
        next.right = right;
        next.elements = elements(left) + node.piece.length + elements(right);
        return self.allocate(next);
    }
    fn merge(self: *Tree, left: ?*const Node, right: ?*const Node) anyerror!?*const Node {
        const l = left orelse return right;
        const r = right orelse return left;
        if (l.priority >= r.priority) return try self.copy(l, l.left, try self.merge(l.right, right));
        return try self.copy(r, try self.merge(left, r.left), r.right);
    }
    fn split(self: *Tree, root: ?*const Node, index: usize) anyerror![2]?*const Node {
        const node = root orelse return .{ null, null };
        const left_length = elements(node.left);
        if (index < left_length) {
            const halves = try self.split(node.left, index);
            return .{ halves[0], try self.copy(node, halves[1], node.right) };
        }
        const piece_end = left_length + node.piece.length;
        if (index > piece_end) {
            const halves = try self.split(node.right, index - piece_end);
            return .{ try self.copy(node, node.left, halves[0]), halves[1] };
        }
        if (index == left_length) return .{ node.left, try self.copy(node, null, node.right) };
        if (index == piece_end) return .{ try self.copy(node, node.left, null), node.right };
        const offset = index - left_length;
        var first = node.piece;
        first.length = offset;
        var second = node.piece;
        second.start = node.piece.index(offset);
        second.length -= offset;
        return .{ try self.merge(node.left, try self.new(first)), try self.merge(try self.new(second), node.right) };
    }
    fn join(self: *Tree, left: ?*const Node, right: ?*const Node) anyerror!?*const Node {
        const l = left orelse return right;
        const r = right orelse return left;
        const lp = rightmost(l).piece;
        const rp = leftmost(r).piece;
        if (!mergeable(lp, rp)) return self.merge(left, right);
        const left_rest = (try self.split(left, elements(left) - lp.length))[0];
        const right_rest = (try self.split(right, rp.length))[1];
        var combined = lp;
        combined.length += rp.length;
        if (lp.length == 1) combined.step = if (rp.start > lp.start) 1 else -1;
        return self.join(try self.join(left_rest, try self.new(combined)), right_rest);
    }
    fn fromPieces(self: *Tree, input: []const Piece) !?*const Node {
        var normalized: std.ArrayList(Piece) = .empty;
        defer normalized.deinit(self.allocator);
        for (input) |piece| {
            if (piece.length == 0) continue;
            if (normalized.items.len > 0 and mergeable(normalized.items[normalized.items.len - 1], piece)) {
                const previous = &normalized.items[normalized.items.len - 1];
                if (previous.length == 1 and piece.length == 1) previous.step = if (piece.start > previous.start) 1 else -1;
                previous.length += piece.length;
            } else try normalized.append(self.allocator, piece);
        }
        var root: ?*const Node = null;
        for (normalized.items) |piece| root = try self.merge(root, try self.new(piece));
        return root;
    }
    /// No visible tree, generation, seed or ownership changes survive an error.
    pub fn replace(self: *Tree, index: usize, remove: usize, inserted: []const Piece) !void {
        if (index > self.length() or remove > self.length() - index) return error.ArrayOverlayIndexOutOfRange;
        if (remove == 0 and inserted.len == 0) return;
        const old_seed = self.seed;
        const checkpoint = self.allocated.items.len;
        errdefer self.rollback(checkpoint, old_seed);
        const left = try self.split(self.root, index);
        const right = try self.split(left[1], remove);
        const middle = try self.fromPieces(inserted);
        const next = try self.join(try self.join(left[0], middle), right[1]);
        self.root = next;
        self.structural = true;
        self.generation += 1;
    }
    pub fn replaceAll(self: *Tree, input: []const Piece) !void {
        const old_seed = self.seed;
        const checkpoint = self.allocated.items.len;
        errdefer self.rollback(checkpoint, old_seed);
        self.root = try self.fromPieces(input);
    }
    fn rollback(self: *Tree, checkpoint: usize, seed: u32) void {
        for (self.allocated.items[checkpoint..]) |node| self.allocator.destroy(node);
        self.allocated.shrinkRetainingCapacity(checkpoint);
        self.seed = seed;
    }
    pub fn locate(self: *const Tree, index: usize) !Location {
        var remaining = index;
        var next = self.root;
        while (next) |node| {
            const left_length = elements(node.left);
            if (remaining < left_length) next = node.left else if (remaining >= left_length + node.piece.length) {
                remaining -= left_length + node.piece.length;
                next = node.right;
            } else return .{ .piece = node.piece, .offset = remaining - left_length };
        }
        return error.ArrayOverlayIndexOutOfRange;
    }
    pub fn pieces(self: *const Tree) ![]Piece {
        var result: std.ArrayList(Piece) = .empty;
        errdefer result.deinit(self.allocator);
        try flatten(self.allocator, self.root, &result);
        return result.toOwnedSlice(self.allocator);
    }
    pub fn reverse(self: *Tree) !void {
        if (self.length() < 2) return;
        const current = try self.pieces();
        defer self.allocator.free(current);
        std.mem.reverse(Piece, current);
        for (current) |*piece| {
            piece.start = piece.index(piece.length - 1);
            piece.step = -piece.step;
        }
        try self.replaceAll(current);
        self.structural = true;
        self.generation += 1;
    }
    /// Current logical index for a Source parentKind/sourceIndex/source tuple.
    pub fn find(self: *const Tree, source: ?usize, source_index: usize) ?usize {
        if (source == null and !self.structural) return if (source_index < self.length()) source_index else null;
        return findNode(self.root, source, source_index, 0);
    }
    pub fn plan(self: *const Tree, base_length: usize) !Plan {
        const current = try self.pieces();
        defer self.allocator.free(current);
        return buildPlan(self.allocator, base_length, current);
    }
};
fn elements(node: ?*const Node) usize {
    return if (node) |n| n.elements else 0;
}
fn leftmost(input: *const Node) *const Node {
    var node = input;
    while (node.left) |left| node = left;
    return node;
}
fn rightmost(input: *const Node) *const Node {
    var node = input;
    while (node.right) |right| node = right;
    return node;
}
fn mergeable(left: Piece, right: Piece) bool {
    if (!left.sameSource(right)) return false;
    if (left.length == 1 and right.length == 1) return if (left.start > right.start) left.start - right.start == 1 else right.start - left.start == 1;
    if (left.step != right.step) return false;
    if (left.step == 1) return left.start + left.length == right.start;
    return left.start >= left.length and left.start - left.length == right.start;
}
fn flatten(allocator: std.mem.Allocator, node: ?*const Node, output: *std.ArrayList(Piece)) anyerror!void {
    const n = node orelse return;
    try flatten(allocator, n.left, output);
    try output.append(allocator, n.piece);
    try flatten(allocator, n.right, output);
}
fn findNode(input: ?*const Node, source: ?usize, source_index: usize, logical: usize) ?usize {
    const node = input orelse return null;
    if (findNode(node.left, source, source_index, logical)) |found| return found;
    const at = logical + elements(node.left);
    const piece = node.piece;
    if (piece.source == source) {
        const last = piece.index(piece.length - 1);
        if (source_index >= @min(piece.start, last) and source_index <= @max(piece.start, last)) return at + (if (piece.step == 1) source_index - piece.start else piece.start - source_index);
    }
    return findNode(node.right, source, source_index, at + piece.length);
}
pub fn arrayIndex(property: []const u8) ?usize {
    if (property.len == 0 or property.len > 10) return null;
    if (std.mem.eql(u8, property, "0")) return 0;
    if (property[0] < '1' or property[0] > '9') return null;
    var result: usize = property[0] - '0';
    for (property[1..]) |digit| {
        if (digit < '0' or digit > '9') return null;
        result = result * 10 + digit - '0';
        if (result >= 4294967295) return null;
    }
    return result;
}
pub fn integerOrInfinity(value: f64) f64 {
    if (std.math.isNan(value) or value == 0) return 0;
    return if (std.math.isFinite(value)) @trunc(value) else value;
}
pub fn clampIndex(value: f64, length: usize) usize {
    const count: f64 = @floatFromInt(length);
    if (value < 0) return @intFromFloat(@max(count + value, 0));
    return @intFromFloat(@min(value, count));
}
pub fn buildPlan(allocator: std.mem.Allocator, base_length: usize, pieces: []const Piece) !Plan {
    var result: Plan = .{ .allocator = allocator };
    errdefer result.deinit();
    var ordered = true;
    var previous_end: ?usize = null;
    for (pieces) |piece| {
        if (piece.source != null or piece.length == 0) continue;
        if ((piece.step != 1 and piece.length > 1) or (previous_end != null and piece.start <= previous_end.?)) {
            ordered = false;
            break;
        }
        previous_end = piece.start + piece.length - 1;
    }
    if (ordered) {
        var end = base_length;
        var index = pieces.len;
        while (index > 0) {
            index -= 1;
            const piece = pieces[index];
            if (piece.source != null or piece.length == 0) continue;
            const start = piece.start + piece.length;
            if (end > start) try result.removes.append(allocator, .{ .start = start, .length = end - start });
            end = piece.start;
        }
        if (end > 0) try result.removes.append(allocator, .{ .start = 0, .length = end });
    } else {
        const retained = try allocator.alloc(bool, base_length);
        defer allocator.free(retained);
        @memset(retained, false);
        var target: std.ArrayList(usize) = .empty;
        defer target.deinit(allocator);
        for (pieces) |piece| {
            if (piece.source != null) continue;
            for (0..piece.length) |offset| {
                const index = piece.index(offset);
                if (index >= base_length) return error.ArrayOverlayIndexOutOfRange;
                retained[index] = true;
                try target.append(allocator, index);
            }
        }
        var end = base_length;
        while (end > 0) {
            if (retained[end - 1]) {
                end -= 1;
                continue;
            }
            var start = end - 1;
            while (start > 0 and !retained[start - 1]) start -= 1;
            try result.removes.append(allocator, .{ .start = start, .length = end - start });
            end = start;
        }
        const positions = try allocator.alloc(usize, base_length);
        defer allocator.free(positions);
        var count: usize = 0;
        for (retained, 0..) |keep, index| if (keep) {
            positions[index] = count;
            count += 1;
        };
        var moved = false;
        for (target.items, 0..) |index, at| if (positions[index] != at) {
            moved = true;
            break;
        };
        if (moved) {
            const permutation = try allocator.alloc(usize, target.items.len);
            result.permutation = permutation;
            for (target.items, permutation) |index, *slot| slot.* = positions[index];
        }
    }
    var logical: usize = 0;
    var index: usize = 0;
    while (index < pieces.len) {
        if (pieces[index].source == null) {
            logical += pieces[index].length;
            index += 1;
            continue;
        }
        const first = index;
        const start = logical;
        while (index < pieces.len and pieces[index].source != null) : (index += 1) logical += pieces[index].length;
        try result.inserts.append(allocator, .{ .logical = start, .first = first, .end = index });
    }
    return result;
}

test "native Chord tracker piece tree retains base identity through splice reverse and plan" {
    var tree = try Tree.init(std.testing.allocator, 8);
    defer tree.deinit();
    try tree.replace(2, 3, &.{.{ .source = 0, .start = 0, .length = 2 }});
    try std.testing.expectEqual(@as(usize, 7), tree.length());
    try std.testing.expectEqual(@as(?usize, 4), tree.find(null, 5));
    try std.testing.expectEqual(@as(?usize, null), tree.find(null, 3));
    try tree.reverse();
    try std.testing.expectEqual(@as(?usize, 2), tree.find(null, 5));
    try std.testing.expectEqual(@as(?usize, 3), tree.find(0, 1));
    var plan = try tree.plan(8);
    defer plan.deinit();
    try std.testing.expectEqualSlices(Remove, &.{.{ .start = 2, .length = 3 }}, plan.removes.items);
    try std.testing.expectEqualSlices(usize, &.{ 4, 3, 2, 1, 0 }, plan.permutation.?);
    try std.testing.expectEqualSlices(Insert, &.{.{ .logical = 3, .first = 1, .end = 2 }}, plan.inserts.items);
}
test "native Chord tracker piece allocation rollback preserves authority generation and seed" {
    const Probe = struct {
        fn run(allocator: std.mem.Allocator) !void {
            var tree = try Tree.init(allocator, 20);
            defer tree.deinit();
            const seed = tree.seed;
            tree.replace(3, 4, &.{.{ .source = 0, .start = 0, .length = 8 }}) catch |err| {
                try std.testing.expectEqual(@as(usize, 20), tree.length());
                try std.testing.expectEqual(@as(usize, 0), tree.generation);
                try std.testing.expectEqual(seed, tree.seed);
                for (0..20) |index| {
                    const location = try tree.locate(index);
                    try std.testing.expectEqual(index, location.piece.index(location.offset));
                }
                return err;
            };
            try std.testing.expectEqual(@as(usize, 24), tree.length());
        }
    };
    try std.testing.checkAllAllocationFailures(std.testing.allocator, Probe.run, .{});
}
