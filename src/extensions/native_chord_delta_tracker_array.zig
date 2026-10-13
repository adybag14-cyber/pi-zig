//! Source dense-array overlays and shared array mutators over identity pieces.
const std = @import("std");
const t = @import("native_chord_delta_tracker.zig");
const o = @import("native_chord_delta_tracker_overlay.zig");
const js = t.js;
const c = t.c;
const Scope = t.Scope;
pub fn getArray(node: *t.Node) !*t.Array {
    if (node.array == null) node.array = .{ .pieces = try t.tree.Tree.init(node.context.engine().gpa, try @import("native_values.zig").length(node.context.engine(), node.base)) };
    return &node.array.?;
}
pub fn entry(node: *t.Node, piece: t.tree.Piece, source_index: usize) !c.JSValue {
    const engine = node.context.engine();
    const data = try getArray(node);
    if (piece.source) |source| {
        const stored = &data.sources.items[source];
        return c.JS_DupValue(engine.context, stored.overrides.get(source_index) orelse stored.values[source_index]);
    }
    if (data.overrides.get(source_index)) |value| return c.JS_DupValue(engine.context, value);
    return engine.checked(c.JS_GetPropertyUint32(engine.context, node.base, @intCast(source_index)));
}
pub fn hasOverride(data: *t.Array, piece: t.tree.Piece, source_index: usize) bool {
    return if (piece.source) |source| data.sources.items[source].overrides.contains(source_index) else data.overrides.contains(source_index);
}
pub fn getIndex(node: *t.Node, index: usize) anyerror!c.JSValue {
    const engine = node.context.engine();
    const data = try getArray(node);
    if (index >= data.pieces.length()) return c.pi_js_undefined();
    const location = try data.pieces.locate(index);
    const source_index = location.piece.index(location.offset);
    const value = try entry(node, location.piece, source_index);
    defer engine.freeValue(value);
    if (!o.container(engine, value)) return c.JS_DupValue(engine.context, value);
    const child = try o.createNode(node.context, value, node, if (location.piece.source == null) .base else .insert, c.JS_NewFloat64(engine.context, @floatFromInt(source_index)), location.piece.source, location.piece.source != null or hasOverride(data, location.piece, source_index));
    return c.JS_DupValue(engine.context, child.proxy);
}
pub fn putOverride(engine: *js.Engine, map: *t.OverrideMap, index: usize, value: c.JSValue) !void {
    if (map.getPtr(index)) |slot| {
        t.replace(engine, slot, value);
        return;
    }
    const owned = c.JS_DupValue(engine.context, value);
    errdefer engine.freeValue(owned);
    try map.put(engine.gpa, index, owned);
}
pub fn removeOverride(engine: *js.Engine, map: *t.OverrideMap, index: usize) void {
    if (map.fetchOrderedRemove(index)) |removed| engine.freeValue(removed.value);
}
/// All placement copies finish before any source or piece becomes authoritative.
pub fn insertSource(node: *t.Node, supplied: []const c.JSValue, placement: bool) anyerror!usize {
    const engine = node.context.engine();
    const cloned = try engine.gpa.alloc(c.JSValue, supplied.len);
    var count: usize = 0;
    errdefer {
        for (cloned[0..count]) |value| engine.freeValue(value);
        engine.gpa.free(cloned);
    }
    for (supplied, cloned) |value, *destination| {
        destination.* = if (placement) try o.clonePlacement(node.context, value) else c.JS_DupValue(engine.context, value);
        count += 1;
    }
    const data = try getArray(node);
    const id = data.sources.items.len;
    try data.sources.append(engine.gpa, .{ .values = cloned });
    return id;
}
pub fn replaceRange(node: *t.Node, index: usize, remove: usize, supplied: []const c.JSValue, placement: bool) anyerror!void {
    if (remove == 0 and supplied.len == 0) return;
    const engine = node.context.engine();
    try o.reserveDirty(node);
    const data = try getArray(node);
    if (supplied.len == 0) {
        try data.pieces.replace(index, remove, &.{});
    } else {
        const id = try insertSource(node, supplied, placement);
        data.pieces.replace(index, remove, &.{.{ .source = id, .start = 0, .length = supplied.len }}) catch |err| {
            var source = data.sources.pop().?;
            deinitSource(engine.runtime, engine.gpa, &source);
            return err;
        };
    }
    try o.markDirty(node);
}
pub fn setIndex(node: *t.Node, index: usize, stored: c.JSValue) !void {
    const engine = node.context.engine();
    const data = try getArray(node);
    if (index == data.pieces.length()) return replaceRange(node, index, 0, &.{stored}, false);
    const location = try data.pieces.locate(index);
    const source_index = location.piece.index(location.offset);
    const current = try entry(node, location.piece, source_index);
    defer engine.freeValue(current);
    if (!o.container(engine, stored) and c.JS_IsStrictEqual(engine.context, current, stored)) return;
    try o.reserveDirty(node);
    if (location.piece.source) |source| {
        const original = data.sources.items[source].values[source_index];
        if (!o.container(engine, stored) and c.JS_IsStrictEqual(engine.context, original, stored)) removeOverride(engine, &data.sources.items[source].overrides, source_index) else try putOverride(engine, &data.sources.items[source].overrides, source_index, stored);
    } else {
        const original = try engine.checked(c.JS_GetPropertyUint32(engine.context, node.base, @intCast(source_index)));
        defer engine.freeValue(original);
        if (!o.container(engine, stored) and c.JS_IsStrictEqual(engine.context, original, stored)) removeOverride(engine, &data.overrides, source_index) else try putOverride(engine, &data.overrides, source_index, stored);
    }
    try o.markDirty(node);
}
pub fn setLength(node: *t.Node, next: usize) !void {
    const engine = node.context.engine();
    const data = try getArray(node);
    const current = data.pieces.length();
    if (next == current) return;
    if (next < current) return replaceRange(node, next, current - next, &.{}, false);
    const values = try engine.gpa.alloc(c.JSValue, next - current);
    defer engine.gpa.free(values);
    @memset(values, c.pi_js_null());
    try replaceRange(node, current, 0, values, false);
}
pub fn toNumber(engine: *js.Engine, value: c.JSValue) !f64 {
    const function = try js.global(engine, "Number");
    defer engine.freeValue(function);
    const number = try js.call(engine, function, c.pi_js_undefined(), &.{value});
    defer engine.freeValue(number);
    var result: f64 = 0;
    if (c.JS_ToFloat64(engine.context, &result, number) < 0) return js.capture(engine);
    return result;
}
pub fn toArrayLength(engine: *js.Engine, value: c.JSValue) !usize {
    const number = try toNumber(engine, value);
    if (!std.math.isFinite(number) or number != @trunc(number) or number < 0 or number >= 4294967296) {
        _ = try engine.checked(c.JS_ThrowRangeError(engine.context, "Invalid array length"));
        unreachable;
    }
    return @intFromFloat(number);
}
fn clamped(engine: *js.Engine, value: c.JSValue, length: usize) !usize {
    return t.tree.clampIndex(t.tree.integerOrInfinity(try toNumber(engine, value)), length);
}
const Mutator = enum(c_int) { push, pop, shift, unshift, splice, reverse, sort, fill, copyWithin };
const names = [_][*:0]const u8{ "push", "pop", "shift", "unshift", "splice", "reverse", "sort", "fill", "copyWithin" };
pub fn mutatorName(engine: *js.Engine, key: c.JSValue) !bool {
    if (!c.JS_IsString(key)) return false;
    const text = try engine.toString(key);
    defer engine.gpa.free(text);
    for (names) |name| if (std.mem.eql(u8, text, std.mem.span(name))) return true;
    return false;
}
fn callback(ctx: ?*c.JSContext, receiver: c.JSValue, argc: c_int, argv: [*c]c.JSValue, magic: c_int, captures: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = js.Engine.fromContext(ctx.?);
    const binding: *t.Binding = @ptrCast(@alignCast(c.JS_GetOpaque(captures[0], c.JS_GetClassID(captures[0])).?));
    return invoke(engine, binding, receiver, if (argc > 0) argv[0..@intCast(argc)] else &.{}, @enumFromInt(magic)) catch |err| @import("native_durable.zig").reject(engine, err);
}
fn fallback(engine: *js.Engine, receiver: c.JSValue, args: []const c.JSValue, operation: Mutator) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const prototype = try scope.get(try scope.keep(try js.global(engine, "Array")), "prototype");
    const method = try scope.get(prototype, names[@intCast(@intFromEnum(operation))]);
    return switch (operation) {
        .pop, .shift, .reverse => js.call(engine, method, receiver, &.{}),
        .sort => js.call(engine, method, receiver, &.{t.arg(args, 0)}),
        .fill, .copyWithin => js.call(engine, method, receiver, &.{ t.arg(args, 0), t.arg(args, 1), t.arg(args, 2) }),
        else => js.call(engine, method, receiver, args),
    };
}
fn invoke(engine: *js.Engine, binding: *t.Binding, receiver: c.JSValue, args: []const c.JSValue, operation: Mutator) anyerror!c.JSValue {
    if (!o.container(engine, receiver)) return fallback(engine, receiver, args, operation);
    const reference = try js.getKey(engine, receiver, binding.node_symbol);
    defer engine.freeValue(reference);
    if (c.JS_IsUndefined(reference)) return fallback(engine, receiver, args, operation);
    const node = try t.nodeOf(engine, reference, binding);
    var lease = t.Lease.init(node.context);
    defer lease.deinit();
    if (!try o.isArray(engine, node.base)) return js.typeError(engine, "Array mutator called on incompatible receiver");
    try t.writable(node.context);
    const data = try getArray(node);
    const length = data.pieces.length();
    switch (operation) {
        .push, .unshift => {
            try replaceRange(node, if (operation == .push) length else 0, 0, args, true);
            return c.JS_NewFloat64(engine.context, @floatFromInt(if (operation == .push) length + args.len else (try getArray(node)).pieces.length()));
        },
        .pop, .shift => {
            if (length == 0) return c.pi_js_undefined();
            const at = if (operation == .pop) length - 1 else 0;
            const value = try getIndex(node, at);
            errdefer engine.freeValue(value);
            try replaceRange(node, at, 1, &.{}, false);
            return value;
        },
        .splice => {
            const start = if (args.len == 0) 0 else try clamped(engine, args[0], length);
            const count = if (args.len == 0) 0 else if (args.len == 1) length - start else @as(usize, @intFromFloat(@min(@max(t.tree.integerOrInfinity(try toNumber(engine, args[1])), 0), @as(f64, @floatFromInt(length - start)))));
            const removed = try js.array(engine);
            errdefer engine.freeValue(removed);
            for (0..count) |offset| {
                const value = try getIndex(node, start + offset);
                defer engine.freeValue(value);
                try js.push(engine, removed, value);
            }
            const inserted = args[@min(2, args.len)..];
            try replaceRange(node, start, count, inserted, true);
            try setLength(node, length - count + inserted.len);
            return removed;
        },
        .reverse => {
            if (length >= 2) {
                try o.reserveDirty(node);
                try data.pieces.reverse();
                try o.markDirty(node);
            }
            return c.JS_DupValue(engine.context, node.proxy);
        },
        .sort => return @import("native_chord_delta_tracker_sort.zig").sort(node, t.arg(args, 0)),
        .fill => {
            const start = if (c.JS_IsUndefined(t.arg(args, 1))) 0 else try clamped(engine, args[1], length);
            const end = if (c.JS_IsUndefined(t.arg(args, 2))) length else try clamped(engine, args[2], length);
            if (end <= start) return c.JS_DupValue(engine.context, node.proxy);
            const supplied = try engine.gpa.alloc(c.JSValue, end - start);
            defer engine.gpa.free(supplied);
            @memset(supplied, t.arg(args, 0));
            try replaceRange(node, start, end - start, supplied, true);
            return c.JS_DupValue(engine.context, node.proxy);
        },
        .copyWithin => {
            const target = try clamped(engine, t.arg(args, 0), length);
            const start = try clamped(engine, t.arg(args, 1), length);
            const end = if (c.JS_IsUndefined(t.arg(args, 2))) length else try clamped(engine, args[2], length);
            const count = @min(end -| start, length - target);
            const values = try engine.gpa.alloc(c.JSValue, count);
            var prepared: usize = 0;
            defer {
                for (values[0..prepared]) |value| engine.freeValue(value);
                engine.gpa.free(values);
            }
            for (values, 0..) |*slot, offset| {
                const value = try getIndex(node, start + offset);
                defer engine.freeValue(value);
                slot.* = try o.clonePlacement(node.context, value);
                prepared += 1;
            }
            try replaceRange(node, target, count, values, false);
            return c.JS_DupValue(engine.context, node.proxy);
        },
    }
}
pub fn functions(engine: *js.Engine, binding: *t.Binding) !c.JSValue {
    const result = try js.object(engine);
    errdefer engine.freeValue(result);
    for (names, 0..) |name, index| {
        var captures = [_]c.JSValue{binding.self};
        const length: c_int = if (index == @intFromEnum(Mutator.sort)) 1 else if (index == @intFromEnum(Mutator.fill) or index == @intFromEnum(Mutator.copyWithin)) 3 else 0;
        const function_value = try engine.checked(c.JS_NewCFunctionData2(engine.context, callback, name, length, @intCast(index), 1, &captures));
        try js.define(engine, result, name, function_value);
    }
    return result;
}
fn deinitSource(runtime: ?*c.JSRuntime, allocator: std.mem.Allocator, source: *t.Source) void {
    for (source.values) |value| c.JS_FreeValueRT(runtime, value);
    allocator.free(source.values);
    for (source.overrides.values()) |value| c.JS_FreeValueRT(runtime, value);
    source.overrides.deinit(allocator);
}
pub fn deinit(runtime: ?*c.JSRuntime, allocator: std.mem.Allocator, data: *t.Array) void {
    data.pieces.deinit();
    for (data.sources.items) |*source| deinitSource(runtime, allocator, source);
    data.sources.deinit(allocator);
    for (data.overrides.values()) |value| c.JS_FreeValueRT(runtime, value);
    data.overrides.deinit(allocator);
}
pub fn mark(runtime: ?*c.JSRuntime, data: *t.Array, visitor: ?*const c.JS_MarkFunc) void {
    for (data.sources.items) |source| {
        for (source.values) |value| c.JS_MarkValue(runtime, value, visitor);
        for (source.overrides.values()) |value| c.JS_MarkValue(runtime, value, visitor);
    }
    for (data.overrides.values()) |value| c.JS_MarkValue(runtime, value, visitor);
}
