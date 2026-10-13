//! Source sort token snapshots, comparator override restoration and deduplication.
const std = @import("std");
const t = @import("native_chord_delta_tracker.zig");
const o = @import("native_chord_delta_tracker_overlay.zig");
const a = @import("native_chord_delta_tracker_array.zig");
const js = t.js;
const c = t.c;
const Token = struct { id: i64, piece: t.tree.Piece, value: c.JSValue };
const State = struct {
    engine: *js.Engine,
    reference: c.JSValue,
    comparator: c.JSValue,
    tokens: std.ArrayList(Token) = .empty,
    positions: std.AutoHashMapUnmanaged(i64, usize) = .empty,
    base_snapshot: t.OverrideMap = .empty,
    insert_snapshots: std.ArrayList(t.OverrideMap) = .empty,
};
fn freeMap(runtime: ?*c.JSRuntime, allocator: std.mem.Allocator, map: *t.OverrideMap) void {
    for (map.values()) |value| c.JS_FreeValueRT(runtime, value);
    map.deinit(allocator);
}
fn finalizer(runtime: ?*c.JSRuntime, object: c.JSValue) callconv(.c) void {
    const state: *State = @ptrCast(@alignCast(c.JS_GetOpaque(object, c.JS_GetClassID(object)) orelse return));
    const allocator = state.engine.gpa;
    c.JS_FreeValueRT(runtime, state.reference);
    c.JS_FreeValueRT(runtime, state.comparator);
    for (state.tokens.items) |token| c.JS_FreeValueRT(runtime, token.value);
    state.tokens.deinit(allocator);
    state.positions.deinit(allocator);
    freeMap(runtime, allocator, &state.base_snapshot);
    for (state.insert_snapshots.items) |*map| freeMap(runtime, allocator, map);
    state.insert_snapshots.deinit(allocator);
    allocator.destroy(state);
}
fn mark(runtime: ?*c.JSRuntime, object: c.JSValue, visit: ?*const c.JS_MarkFunc) callconv(.c) void {
    const state: *State = @ptrCast(@alignCast(c.JS_GetOpaque(object, c.JS_GetClassID(object)) orelse return));
    c.JS_MarkValue(runtime, state.reference, visit);
    c.JS_MarkValue(runtime, state.comparator, visit);
    for (state.tokens.items) |token| c.JS_MarkValue(runtime, token.value, visit);
    for (state.base_snapshot.values()) |value| c.JS_MarkValue(runtime, value, visit);
    for (state.insert_snapshots.items) |map| for (map.values()) |value| c.JS_MarkValue(runtime, value, visit);
}
fn cloneMap(engine: *js.Engine, input: *const t.OverrideMap) !t.OverrideMap {
    var result: t.OverrideMap = .empty;
    errdefer freeMap(engine.runtime, engine.gpa, &result);
    for (input.keys(), input.values()) |key, value| try a.putOverride(engine, &result, key, value);
    return result;
}
fn publicValue(node: *t.Node, piece: t.tree.Piece, index: usize) !c.JSValue {
    const engine = node.context.engine();
    const value = try a.entry(node, piece, index);
    defer engine.freeValue(value);
    try t.readable(node.context);
    if (!o.container(engine, value)) return c.JS_DupValue(engine.context, value);
    const data = try a.getArray(node);
    const child = try o.createNode(node.context, value, node, if (piece.source == null) .base else .insert, c.JS_NewFloat64(engine.context, @floatFromInt(index)), piece.source, piece.source != null or a.hasOverride(data, piece, index));
    return c.JS_DupValue(engine.context, child.proxy);
}
fn tokenId(engine: *js.Engine, value: c.JSValue) !i64 {
    var result: i64 = 0;
    if (c.JS_ToInt64(engine.context, &result, value) < 0) return js.capture(engine);
    return result;
}
fn tokenValue(state: *State, id: i64) c.JSValue {
    return if (state.positions.get(id)) |index| state.tokens.items[index].value else c.pi_js_undefined();
}
fn comparison(ctx: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, captures: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = js.Engine.fromContext(ctx.?);
    const state: *State = @ptrCast(@alignCast(c.JS_GetOpaque(captures[0], c.JS_GetClassID(captures[0])).?));
    return compare(state, if (argc > 0) argv[0..@intCast(argc)] else &.{}) catch |err| @import("native_durable.zig").reject(engine, err);
}
fn compare(state: *State, args: []const c.JSValue) !c.JSValue {
    const engine = state.engine;
    const left = tokenValue(state, try tokenId(engine, t.arg(args, 0)));
    const right = tokenValue(state, try tokenId(engine, t.arg(args, 1)));
    if (c.JS_IsFunction(engine.context, state.comparator)) {
        const result = try js.call(engine, state.comparator, c.pi_js_undefined(), &.{ left, right });
        defer engine.freeValue(result);
        return c.JS_NewFloat64(engine.context, try a.toNumber(engine, result));
    }
    const string_function = try js.global(engine, "String");
    defer engine.freeValue(string_function);
    const left_string = try js.call(engine, string_function, c.pi_js_undefined(), &.{left});
    defer engine.freeValue(left_string);
    const right_string = try js.call(engine, string_function, c.pi_js_undefined(), &.{right});
    defer engine.freeValue(right_string);
    const left_units = try @import("native_utf16.zig").unitsAlloc(engine, left_string);
    defer engine.gpa.free(left_units);
    const right_units = try @import("native_utf16.zig").unitsAlloc(engine, right_string);
    defer engine.gpa.free(right_units);
    return c.JS_NewInt32(engine.context, switch (std.mem.order(u16, left_units, right_units)) {
        .lt => -1,
        .eq => 0,
        .gt => 1,
    });
}
fn restore(node: *t.Node, piece: t.tree.Piece, state: *State) !void {
    const engine = node.context.engine();
    const data = try a.getArray(node);
    const current = if (piece.source) |source| &data.sources.items[source].overrides else &data.overrides;
    const snapshot = if (piece.source) |source| &state.insert_snapshots.items[source] else &state.base_snapshot;
    if (snapshot.get(piece.start)) |value| try a.putOverride(engine, current, piece.start, value) else a.removeOverride(engine, current, piece.start);
}
const Identity = struct { source: ?usize, index: usize };
fn deduplicate(node: *t.Node) !void {
    const engine = node.context.engine();
    const data = try a.getArray(node);
    const current = try data.pieces.pieces();
    defer engine.gpa.free(current);
    var seen: std.AutoHashMapUnmanaged(Identity, void) = .empty;
    defer seen.deinit(engine.gpa);
    var next: std.ArrayList(t.tree.Piece) = .empty;
    defer next.deinit(engine.gpa);
    var duplicated = false;
    for (current) |piece| for (0..piece.length) |offset| {
        const index = piece.index(offset);
        const identity: Identity = .{ .source = piece.source, .index = index };
        if (seen.contains(identity)) {
            duplicated = true;
            const value = try a.entry(node, piece, index);
            defer engine.freeValue(value);
            const cloned = try o.cloneStored(node.context, value, true);
            defer engine.freeValue(cloned);
            try t.readable(node.context);
            const source = try a.insertSource(node, &.{cloned}, false);
            try next.append(engine.gpa, .{ .source = source, .start = 0, .length = 1 });
        } else {
            try seen.put(engine.gpa, identity, {});
            try next.append(engine.gpa, .{ .source = piece.source, .start = index, .length = 1, .step = piece.step });
        }
    };
    if (!duplicated) return;
    try o.reserveDirty(node);
    try data.pieces.replaceAll(next.items);
    data.pieces.structural = true;
    data.pieces.generation += 1;
    try o.markDirty(node);
}
pub fn sort(node: *t.Node, comparator: c.JSValue) anyerror!c.JSValue {
    const engine = node.context.engine();
    if (!c.JS_IsUndefined(comparator) and !c.JS_IsFunction(engine.context, comparator)) return js.typeError(engine, "Comparator must be a function");
    const binding = node.context.binding();
    if (binding.sort_class == 0) {
        var id: c.JSClassID = 0;
        _ = c.JS_NewClassID(engine.runtime, &id);
        const definition: c.JSClassDef = .{ .class_name = "Native Chord Sort Snapshot", .finalizer = finalizer, .gc_mark = mark };
        if (c.JS_NewClass(engine.runtime, id, &definition) < 0) return error.OutOfMemory;
        binding.sort_class = id;
    }
    var scope: t.Scope = .{ .engine = engine };
    defer scope.deinit();
    const owner = try scope.keep(try engine.checked(c.JS_NewObjectClass(engine.context, binding.sort_class)));
    const state = try engine.gpa.create(State);
    state.* = .{ .engine = engine, .reference = c.JS_DupValue(engine.context, node.reference), .comparator = c.JS_DupValue(engine.context, comparator) };
    _ = c.JS_SetOpaque(owner, state);
    const data = try a.getArray(node);
    const current = try data.pieces.pieces();
    defer engine.gpa.free(current);
    const order = try scope.list();
    var inserted_count: usize = 0;
    for (current) |piece| for (0..piece.length) |offset| {
        const index = piece.index(offset);
        const id: i64 = if (piece.source == null) @intCast(index) else blk: {
            inserted_count += 1;
            break :blk -@as(i64, @intCast(inserted_count));
        };
        const value = try publicValue(node, piece, index);
        var attached = false;
        errdefer if (!attached) engine.freeValue(value);
        try state.positions.put(engine.gpa, id, state.tokens.items.len);
        try state.tokens.append(engine.gpa, .{ .id = id, .piece = .{ .source = piece.source, .start = index, .length = 1, .step = piece.step }, .value = value });
        attached = true;
        try js.push(engine, order, c.JS_NewInt64(engine.context, id));
        try t.readable(node.context);
    };
    state.base_snapshot = try cloneMap(engine, &data.overrides);
    for (data.sources.items) |source| {
        var snapshot = try cloneMap(engine, &source.overrides);
        var attached = false;
        errdefer if (!attached) freeMap(engine.runtime, engine.gpa, &snapshot);
        try state.insert_snapshots.append(engine.gpa, snapshot);
        attached = true;
    }
    const generation = data.pieces.generation;
    var captures = [_]c.JSValue{owner};
    const compare_function = try scope.keep(try engine.checked(c.JS_NewCFunctionData2(engine.context, comparison, "", 2, 0, 1, &captures)));
    const ignored = try js.invoke(engine, order, "sort", &.{compare_function});
    engine.freeValue(ignored);
    try t.readable(node.context);
    const count = try @import("native_values.zig").length(engine, order);
    var sorted: std.ArrayList(t.tree.Piece) = .empty;
    defer sorted.deinit(engine.gpa);
    for (0..count) |index| {
        const token_value = try scope.at(order, index);
        const position = state.positions.get(try tokenId(engine, token_value)) orelse return js.typeError(engine, "Invalid array sort token");
        const piece = state.tokens.items[position].piece;
        try restore(node, piece, state);
        try sorted.append(engine.gpa, piece);
    }
    const comparator_structural = data.pieces.generation != generation;
    const length = data.pieces.length();
    var same_prefix = length >= sorted.items.len;
    if (same_prefix) for (sorted.items, 0..) |piece, index| {
        const location = try data.pieces.locate(index);
        if (location.piece.source != piece.source or location.piece.index(location.offset) != piece.start) {
            same_prefix = false;
            break;
        }
    };
    if (!same_prefix) {
        try o.reserveDirty(node);
        try data.pieces.replace(0, @min(sorted.items.len, length), sorted.items);
        try o.markDirty(node);
    }
    if (comparator_structural) try deduplicate(node);
    return c.JS_DupValue(engine.context, node.proxy);
}
