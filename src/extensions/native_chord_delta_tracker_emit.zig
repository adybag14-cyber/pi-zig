//! Source tracker dirty-node ordering, safe folds, dense regions and operations.
const std = @import("std");
const t = @import("native_chord_delta_tracker.zig");
const o = @import("native_chord_delta_tracker_overlay.zig");
const a = @import("native_chord_delta_tracker_array.zig");
const delta = @import("native_chord_delta_diff.zig");
const js = t.js;
const c = t.c;
const Scope = t.Scope;
const Region = struct { start: usize, length: usize };
const Dense = struct { node: *t.Node, indices: std.ArrayList(usize) = .empty, bits: ?[]bool = null, length: usize, regions: std.ArrayList(Region) = .empty };
const PathMap = std.AutoArrayHashMapUnmanaged(usize, c.JSValue);
fn putPath(engine: *js.Engine, map: *PathMap, index: usize, value: c.JSValue) !void {
    if (map.getPtr(index)) |slot| {
        t.replace(engine, slot, value);
        return;
    }
    const owned = c.JS_DupValue(engine.context, value);
    errdefer engine.freeValue(owned);
    try map.put(engine.gpa, index, owned);
}
fn freePaths(engine: *js.Engine, map: *PathMap) void {
    for (map.values()) |value| engine.freeValue(value);
    map.deinit(engine.gpa);
}
fn length(engine: *js.Engine, value: c.JSValue) !usize {
    return @import("native_values.zig").length(engine, value);
}
fn appendPath(scope: *Scope, path: c.JSValue, key: c.JSValue) !c.JSValue {
    const next = try scope.keep(try js.invoke(scope.engine, path, "slice", &.{}));
    try js.push(scope.engine, next, key);
    return next;
}
fn operation(scope: *Scope, ops: c.JSValue, tag: []const u8, args: []const c.JSValue) !void {
    const op = try scope.list();
    try js.push(scope.engine, op, try scope.text(tag));
    for (args) |value| try js.push(scope.engine, op, value);
    try js.push(scope.engine, ops, op);
}
fn set(scope: *Scope, ops: c.JSValue, path: c.JSValue, value: c.JSValue) !void {
    if (try length(scope.engine, path) == 0) return operation(scope, ops, "r", &.{value});
    return operation(scope, ops, "s", &.{ path, value });
}
pub fn resolvePath(node: *t.Node) anyerror!?c.JSValue {
    const engine = node.context.engine();
    try t.readable(node.context);
    if (!c.JS_IsUndefined(node.path)) return node.path;
    const parent = o.parent(node) orelse {
        node.path = try js.array(engine);
        return node.path;
    };
    const parent_path = (try resolvePath(parent)) orelse return null;
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    var key = node.parent_key;
    if (node.parent_kind == .object) {
        if (!try o.objectHas(parent, key)) return null;
        const current = try scope.keep(try o.objectValue(parent, key));
        try t.readable(node.context);
        if (!c.JS_IsStrictEqual(engine.context, current, node.base)) return null;
    } else {
        const data = try a.getArray(parent);
        var source_index: u32 = 0;
        if (c.JS_ToUint32(engine.context, &source_index, key) < 0) return js.capture(engine);
        const logical = data.pieces.find(if (node.parent_kind == .base) null else node.parent_source, source_index) orelse return null;
        const location = try data.pieces.locate(logical);
        const current = try scope.keep(try a.entry(parent, location.piece, source_index));
        try t.readable(node.context);
        if (!c.JS_IsStrictEqual(engine.context, current, node.base)) return null;
        key = c.JS_NewFloat64(engine.context, @floatFromInt(logical));
    }
    node.path = scope.result(try appendPath(&scope, parent_path, key));
    return node.path;
}
fn reserved(scope: *Scope, key: c.JSValue) !bool {
    return c.JS_IsString(key) and (try scope.equal(key, "__proto__") or try scope.equal(key, "constructor") or try scope.equal(key, "prototype"));
}
fn reservedAt(scope: *Scope, path: c.JSValue) !?usize {
    for (0..try length(scope.engine, path)) |index| if (try reserved(scope, try scope.at(path, index))) return index;
    return null;
}
fn reservedMutation(scope: *Scope, node: *t.Node) !bool {
    if (try reserved(scope, node.write_key) or try reserved(scope, node.delete_key)) return true;
    const writes = try o.collectionValues(scope, node.writes, "keys");
    for (0..try length(scope.engine, writes)) |index| if (try reserved(scope, try scope.at(writes, index))) return true;
    const deletes = try o.collectionValues(scope, node.deletes, "values");
    for (0..try length(scope.engine, deletes)) |index| if (try reserved(scope, try scope.at(deletes, index))) return true;
    return false;
}
fn placementAncestor(node: *t.Node) bool {
    var current: ?*t.Node = node;
    while (current) |n| : (current = o.parent(n)) if (n.parent != null and n.placement) return true;
    return false;
}
fn changed(scope: *Scope, operations: c.JSValue, path: c.JSValue, before: c.JSValue, after: c.JSValue) !bool {
    const batch = try scope.keep(try delta.changedValueOperations(scope.engine, before, after, path));
    const count = try length(scope.engine, batch);
    for (0..count) |index| try js.push(scope.engine, operations, try scope.at(batch, index));
    return count != 0;
}
fn objectWrite(scope: *Scope, node: *t.Node, path: c.JSValue, ops: c.JSValue, key: c.JSValue, stored: c.JSValue) !bool {
    const engine = scope.engine;
    const stored_owner = try scope.keep(c.JS_DupValue(engine.context, stored));
    const next_path = try appendPath(scope, path, key);
    const before = if (try o.collectionHas(engine, node.readded, key) or !try o.hasOwn(engine, node.base, key)) c.pi_js_undefined() else try scope.key(node.base, key);
    const after = try scope.keep(try o.cloneStored(node.context, stored_owner, false));
    try t.readable(node.context);
    const emitted = try changed(scope, ops, next_path, before, after);
    return o.container(engine, before) and o.container(engine, after) and !emitted;
}
fn objectOperations(scope: *Scope, node: *t.Node, path: c.JSValue, ops: c.JSValue) !bool {
    const engine = scope.engine;
    const readded = try o.collectionValues(scope, node.readded, "values");
    for (0..try length(engine, readded)) |index| {
        const key = try scope.at(readded, index);
        if (try o.hasOwn(engine, node.base, key)) try operation(scope, ops, "d", &.{try appendPath(scope, path, key)});
    }
    var normalized = false;
    if (!c.JS_IsUndefined(node.write_key)) normalized = try objectWrite(scope, node, path, ops, node.write_key, node.write_value);
    const writes = try o.collectionValues(scope, node.writes, "entries");
    for (0..try length(engine, writes)) |index| {
        if (try length(engine, ops) > 4096) return normalized;
        const pair = try scope.at(writes, index);
        if (try objectWrite(scope, node, path, ops, try scope.at(pair, 0), try scope.at(pair, 1))) normalized = true;
    }
    if (!c.JS_IsUndefined(node.delete_key) and try o.hasOwn(engine, node.base, node.delete_key)) try operation(scope, ops, "d", &.{try appendPath(scope, path, node.delete_key)});
    const deletes = try o.collectionValues(scope, node.deletes, "values");
    for (0..try length(engine, deletes)) |index| {
        if (try length(engine, ops) > 4096) return normalized;
        const key = try scope.at(deletes, index);
        if (try o.hasOwn(engine, node.base, key)) try operation(scope, ops, "d", &.{try appendPath(scope, path, key)});
    }
    return normalized;
}
fn rootReplacement(scope: *Scope, context: *t.Context) !c.JSValue {
    const result = try scope.list();
    try operation(scope, result, "r", &.{try scope.keep(try o.cloneNode(context.root.?, false))});
    return result;
}
fn simple(scope: *Scope, context: *t.Context) !?c.JSValue {
    var nodes: std.ArrayList(*t.Node) = .empty;
    defer nodes.deinit(scope.engine.gpa);
    for (context.dirty.items) |node| {
        if (try o.isArray(scope.engine, node.base) or try reservedMutation(scope, node) or placementAncestor(node)) return null;
        var ancestor = o.parent(node);
        while (ancestor) |parent| : (ancestor = o.parent(parent)) if (try o.isArray(scope.engine, parent.base)) return null;
        const path = (try resolvePath(node)) orelse continue;
        if (try reservedAt(scope, path) != null) return null;
        try nodes.append(scope.engine.gpa, node);
        if (nodes.items.len > 128) return null;
    }
    for (1..@max(1, nodes.items.len)) |index| {
        const node = nodes.items[index];
        const depth = try length(scope.engine, node.path);
        var at = index;
        while (at > 0 and try length(scope.engine, nodes.items[at - 1].path) > depth) : (at -= 1) nodes.items[at] = nodes.items[at - 1];
        nodes.items[at] = node;
    }
    const operations = try scope.list();
    var direct = true;
    for (nodes.items) |node| {
        if (try objectOperations(scope, node, node.path, operations)) direct = false;
        if (try length(scope.engine, operations) > 4096) return try rootReplacement(scope, context);
    }
    context.simple_materialization = direct;
    return operations;
}
fn locateDense(node: *t.Node) anyerror!?struct { node: *t.Node, index: usize } {
    var child = node;
    while (o.parent(child)) |parent| : (child = parent) {
        if (!try o.isArray(node.context.engine(), parent.base)) continue;
        const data = try a.getArray(parent);
        if (child.parent_kind != .base or data.pieces.structural) return null;
        var index: u32 = 0;
        if (c.JS_ToUint32(node.context.engine().context, &index, child.parent_key) < 0) return js.capture(node.context.engine());
        const current = try a.entry(parent, .{ .start = 0, .length = data.pieces.length() }, index);
        defer node.context.engine().freeValue(current);
        if (!c.JS_IsStrictEqual(node.context.engine().context, current, child.base)) return null;
        return .{ .node = parent, .index = index };
    }
    return null;
}
fn addDense(allocator: std.mem.Allocator, group: *Dense, index: usize) !void {
    if (group.bits) |bits| {
        bits[index] = true;
        return;
    }
    try group.indices.append(allocator, index);
    if (group.indices.items.len < 256) return;
    const bits = try allocator.alloc(bool, group.length);
    @memset(bits, false);
    for (group.indices.items) |existing| bits[existing] = true;
    group.indices.clearRetainingCapacity();
    group.bits = bits;
}
fn denseGroup(scope: *Scope, groups: *std.ArrayList(Dense), node: *t.Node) !*Dense {
    for (groups.items) |*group| if (group.node == node) return group;
    try groups.append(scope.engine.gpa, .{ .node = node, .length = try length(scope.engine, node.base) });
    return &groups.items[groups.items.len - 1];
}
fn buildRegions(allocator: std.mem.Allocator, group: *Dense) !void {
    const bits = group.bits orelse return;
    var at: usize = 0;
    while (at < bits.len) {
        while (at < bits.len and !bits[at]) at += 1;
        if (at == bits.len) break;
        const start = at;
        var end = at;
        var count: usize = 0;
        var gap: usize = 0;
        while (at < bits.len) {
            if (bits[at]) {
                count += 1;
                end = at;
                gap = 0;
            } else {
                gap += 1;
                if (gap > 1) break;
            }
            at += 1;
        }
        const span = end - start + 1;
        if (count >= 256 and count * 2 >= span) try group.regions.append(allocator, .{ .start = start, .length = span });
    }
}
fn regionsFor(groups: []const Dense, node: *t.Node) []const Region {
    for (groups) |group| if (group.node == node) return group.regions.items;
    return &.{};
}
fn contains(regions: []const Region, index: usize) bool {
    for (regions) |region| if (index >= region.start and index < region.start + region.length) return true;
    return false;
}
fn covered(scope: *Scope, node: *t.Node, path: c.JSValue, groups: []const Dense) !bool {
    var ancestor = o.parent(node);
    while (ancestor) |parent| : (ancestor = o.parent(parent)) {
        const regions = regionsFor(groups, parent);
        if (regions.len == 0) continue;
        const parent_path = (try resolvePath(parent)) orelse continue;
        const depth = try length(scope.engine, parent_path);
        if (try length(scope.engine, path) <= depth) continue;
        var matches = true;
        for (0..depth) |index| if (!c.JS_IsStrictEqual(scope.engine.context, try scope.at(path, index), try scope.at(parent_path, index))) {
            matches = false;
            break;
        };
        if (!matches) continue;
        const index = try scope.at(path, depth);
        if (!c.JS_IsNumber(index)) continue;
        var numeric: u32 = 0;
        if (c.JS_ToUint32(scope.engine.context, &numeric, index) < 0) return js.capture(scope.engine);
        if (contains(regions, numeric)) return true;
    }
    return false;
}
fn cloneRegion(scope: *Scope, node: *t.Node, start: usize, count: usize) !c.JSValue {
    const result = try scope.list();
    for (start..start + count) |index| {
        const data = try a.getArray(node);
        const location = try data.pieces.locate(index);
        const value = try scope.keep(try a.entry(node, location.piece, location.piece.index(location.offset)));
        const cloned = try scope.keep(try o.cloneStored(node.context, value, false));
        try t.readable(node.context);
        try js.push(scope.engine, result, cloned);
    }
    return result;
}
fn arrayOperations(scope: *Scope, node: *t.Node, path: c.JSValue, ops: c.JSValue, regions: []const Region) !void {
    const engine = scope.engine;
    const data = try a.getArray(node);
    for (regions) |region| {
        if (try length(engine, ops) > 4096) return;
        try operation(scope, ops, "p", &.{ path, c.JS_NewFloat64(engine.context, @floatFromInt(region.start)), c.JS_NewFloat64(engine.context, @floatFromInt(region.length)), try cloneRegion(scope, node, region.start, region.length) });
    }
    if (data.pieces.structural) {
        var plan = try data.pieces.plan(try length(engine, node.base));
        defer plan.deinit();
        for (plan.removes.items) |remove| {
            if (try length(engine, ops) > 4096) return;
            try operation(scope, ops, "p", &.{ path, c.JS_NewFloat64(engine.context, @floatFromInt(remove.start)), c.JS_NewFloat64(engine.context, @floatFromInt(remove.length)), try scope.list() });
        }
        if (plan.permutation) |permutation| {
            const order = try scope.list();
            for (permutation) |index| try js.push(engine, order, c.JS_NewFloat64(engine.context, @floatFromInt(index)));
            try operation(scope, ops, "m", &.{ path, order });
        }
        const pieces = try data.pieces.pieces();
        defer engine.gpa.free(pieces);
        for (plan.inserts.items) |insert| {
            if (try length(engine, ops) > 4096) return;
            const items = try scope.list();
            for (pieces[insert.first..insert.end]) |piece| for (0..piece.length) |offset| {
                const value = try scope.keep(try a.entry(node, piece, piece.index(offset)));
                const cloned = try scope.keep(try o.cloneStored(node.context, value, false));
                try t.readable(node.context);
                try js.push(engine, items, cloned);
            };
            try operation(scope, ops, "p", &.{ path, c.JS_NewFloat64(engine.context, @floatFromInt(insert.logical)), c.JS_NewInt32(engine.context, 0), items });
        }
    }
    for (data.overrides.keys(), data.overrides.values()) |base_index, stored| {
        if (try length(engine, ops) > 4096) return;
        const logical = data.pieces.find(null, base_index) orelse continue;
        if (contains(regions, logical)) continue;
        const stored_owner = try scope.keep(c.JS_DupValue(engine.context, stored));
        const before = try scope.at(node.base, base_index);
        try t.readable(node.context);
        const after = try scope.keep(try o.cloneStored(node.context, stored_owner, false));
        try t.readable(node.context);
        _ = try changed(scope, ops, try appendPath(scope, path, c.JS_NewFloat64(engine.context, @floatFromInt(logical))), before, after);
    }
}
fn general(scope: *Scope, context: *t.Context) !c.JSValue {
    const allocator = scope.engine.gpa;
    var dense: std.ArrayList(Dense) = .empty;
    defer {
        for (dense.items) |*group| {
            group.indices.deinit(allocator);
            if (group.bits) |bits| allocator.free(bits);
            group.regions.deinit(allocator);
        }
        dense.deinit(allocator);
    }
    for (context.dirty.items) |node| {
        if (try locateDense(node)) |found| try addDense(allocator, try denseGroup(scope, &dense, found.node), found.index);
        if (try o.isArray(scope.engine, node.base)) {
            const data = try a.getArray(node);
            if (!data.pieces.structural and data.overrides.count() > 0) {
                const group = try denseGroup(scope, &dense, node);
                for (data.overrides.keys()) |index| try addDense(allocator, group, index);
            }
        }
    }
    for (dense.items) |*group| {
        const path = (try resolvePath(group.node)) orelse continue;
        if (try reservedAt(scope, path) != null) continue;
        try buildRegions(allocator, group);
    }
    var forced: PathMap = .empty;
    defer freePaths(scope.engine, &forced);
    var paths: PathMap = .empty;
    defer freePaths(scope.engine, &paths);
    for (context.dirty.items) |node| {
        const path = (try resolvePath(node)) orelse continue;
        if (try covered(scope, node, path, dense.items)) continue;
        try putPath(scope.engine, &paths, node.index, path);
        if (!try o.isArray(scope.engine, node.base) and try reservedMutation(scope, node)) try putPath(scope.engine, &forced, node.index, path);
        if (try reservedAt(scope, path)) |at| {
            var ancestor = node;
            var depth = try length(scope.engine, path);
            while (depth > at) : (depth -= 1) ancestor = o.parent(ancestor).?;
            const prefix = try scope.keep(try js.invoke(scope.engine, path, "slice", &.{ c.JS_NewInt32(scope.engine.context, 0), c.JS_NewFloat64(scope.engine.context, @floatFromInt(at)) }));
            try putPath(scope.engine, &forced, ancestor.index, prefix);
        }
    }
    for (forced.keys(), forced.values()) |index, path| try putPath(scope.engine, &paths, index, path);
    for (dense.items) |group| {
        if (group.regions.items.len == 0) continue;
        const path = (try resolvePath(group.node)) orelse continue;
        if (!try covered(scope, group.node, path, dense.items)) try putPath(scope.engine, &paths, group.node.index, path);
    }
    var order: std.ArrayList(usize) = .empty;
    defer order.deinit(allocator);
    try order.appendSlice(allocator, paths.keys());
    var max_depth: usize = 0;
    for (paths.values()) |path| max_depth = @max(max_depth, try length(scope.engine, path));
    const buckets = try allocator.alloc(std.ArrayList(usize), max_depth + 1);
    @memset(buckets, .empty);
    defer {
        for (buckets) |*bucket| bucket.deinit(allocator);
        allocator.free(buckets);
    }
    for (paths.keys(), paths.values()) |index, path| try buckets[try length(scope.engine, path)].append(allocator, index);
    order.clearRetainingCapacity();
    for (buckets) |bucket| try order.appendSlice(allocator, bucket.items);
    var folded: std.AutoHashMapUnmanaged(usize, void) = .empty;
    defer folded.deinit(allocator);
    const operations = try scope.list();
    for (order.items) |index| {
        try t.readable(context);
        const node = context.nodes.items[index];
        if (placementAncestor(node)) continue;
        var ancestor = o.parent(node);
        var covered_fold = false;
        while (ancestor) |parent| : (ancestor = o.parent(parent)) if (folded.contains(parent.index)) {
            covered_fold = true;
            break;
        };
        if (covered_fold) continue;
        const path = paths.get(index).?;
        if (forced.contains(index)) {
            try set(scope, operations, path, try scope.keep(try o.cloneNode(node, false)));
            try folded.put(allocator, index, {});
            continue;
        }
        if (try o.isArray(scope.engine, node.base)) try arrayOperations(scope, node, path, operations, regionsFor(dense.items, node)) else _ = try objectOperations(scope, node, path, operations);
        try t.readable(context);
        if (try length(scope.engine, operations) > 4096) return rootReplacement(scope, context);
    }
    return operations;
}
pub fn ensureOperations(context: *t.Context) !c.JSValue {
    const engine = context.engine();
    if (!c.JS_IsUndefined(context.ops)) return c.JS_DupValue(engine.context, context.ops);
    try t.readable(context);
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    var result: c.JSValue = undefined;
    if (context.replacement) {
        const tracker_value = try scope.keep(try js.invoke(engine, context.tracker, "deref", &.{}));
        var base = c.pi_js_undefined();
        if (!c.JS_IsUndefined(tracker_value)) {
            const tracker = &(try t.getInstance(engine, tracker_value, context.binding(), .tracker)).data.tracker;
            if (tracker.revision == context.base_revision) base = tracker.value;
        }
        context.replacement_noop = !c.JS_IsUndefined(base) and try delta.equalTrustedJson(engine, base, context.root.?.base);
        result = try scope.list();
        if (!context.replacement_noop) try operation(&scope, result, "r", &.{context.root.?.base});
    } else if (context.dirty.items.len == 0) result = try scope.list() else result = (try simple(&scope, context)) orelse try general(&scope, context);
    t.replace(engine, &context.ops, result);
    return scope.result(result);
}
