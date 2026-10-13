//! Source overlay nodes, ordinary-object writes and all proxy traps.
const std = @import("std");
const t = @import("native_chord_delta_tracker.zig");
const a = @import("native_chord_delta_tracker_array.zig");
const js = t.js;
const c = t.c;
const Scope = t.Scope;
pub fn container(engine: *js.Engine, value: c.JSValue) bool {
    return c.JS_IsObject(value) and !c.JS_IsFunction(engine.context, value);
}
pub fn isArray(engine: *js.Engine, value: c.JSValue) !bool {
    const owner = try js.global(engine, "Array");
    defer engine.freeValue(owner);
    const result = try js.invoke(engine, owner, "isArray", &.{value});
    defer engine.freeValue(result);
    return c.JS_ToBool(engine.context, result) != 0;
}
pub fn hasOwn(engine: *js.Engine, value: c.JSValue, key: c.JSValue) !bool {
    const object = try js.global(engine, "Object");
    defer engine.freeValue(object);
    const result = try js.invoke(engine, object, "hasOwn", &.{ value, key });
    defer engine.freeValue(result);
    return c.JS_ToBool(engine.context, result) != 0;
}
pub fn collectionHas(engine: *js.Engine, collection: c.JSValue, key: c.JSValue) !bool {
    if (c.JS_IsUndefined(collection)) return false;
    const result = try js.invoke(engine, collection, "has", &.{key});
    defer engine.freeValue(result);
    return c.JS_ToBool(engine.context, result) != 0;
}
pub fn collectionDelete(engine: *js.Engine, collection: c.JSValue, key: c.JSValue) !void {
    if (c.JS_IsUndefined(collection)) return;
    const ignored = try js.invoke(engine, collection, "delete", &.{key});
    engine.freeValue(ignored);
}
pub fn createNode(context: *t.Context, base: c.JSValue, parent_node: ?*t.Node, kind: t.ParentKind, key: c.JSValue, source: ?usize, placement: bool) anyerror!*t.Node {
    try t.readable(context);
    const engine = context.engine();
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const existing = try scope.keep(try js.invoke(engine, context.raw_nodes, "get", &.{base}));
    if (!c.JS_IsUndefined(existing)) return t.nodeOf(engine, existing, context.binding());
    const target = try scope.keep(if (try isArray(engine, base)) try js.array(engine) else try js.object(engine));
    const reference = try scope.keep(try t.createInstance(engine, context.binding(), .node_ref, c.pi_js_null(), .{ .node_ref = .{ .context = c.JS_DupValue(engine.context, context.self), .index = context.nodes.items.len } }));
    const proxy = try scope.keep(try engine.checked(c.JS_NewProxy(engine.context, target, context.binding().handler)));
    const node = try engine.gpa.create(t.Node);
    var attached = false;
    node.* = .{ .context = context, .index = context.nodes.items.len, .base = c.JS_DupValue(engine.context, base), .parent = if (parent_node) |p| p.index else null, .parent_kind = kind, .parent_key = c.JS_DupValue(engine.context, key), .parent_source = source, .placement = placement, .target = c.JS_DupValue(engine.context, target), .proxy = c.JS_DupValue(engine.context, proxy), .reference = c.JS_DupValue(engine.context, reference), .write_key = c.pi_js_undefined(), .write_value = c.pi_js_undefined(), .writes = c.pi_js_undefined(), .delete_key = c.pi_js_undefined(), .deletes = c.pi_js_undefined(), .readded = c.pi_js_undefined(), .path = c.pi_js_undefined() };
    errdefer if (!attached) freeNode(engine.runtime, engine.gpa, node);
    try context.nodes.append(engine.gpa, node);
    attached = true;
    // The target owns its node marker, just as Source target[NODE] = node.
    try js.setKey(engine, target, context.binding().node_symbol, reference);
    const ignored = try js.invoke(engine, context.raw_nodes, "set", &.{ base, reference });
    engine.freeValue(ignored);
    return node;
}
pub fn parent(node: *t.Node) ?*t.Node {
    return if (node.parent) |index| node.context.nodes.items[index] else null;
}
pub fn markDirty(node: *t.Node) !void {
    if (node.dirty) return;
    try node.context.dirty.append(node.context.engine().gpa, node);
    node.dirty = true;
    var ancestor = parent(node);
    while (ancestor) |current| : (ancestor = parent(current)) current.subtree_dirty = true;
}
pub fn reserveDirty(node: *t.Node) !void {
    if (!node.dirty) try node.context.dirty.ensureUnusedCapacity(node.context.engine().gpa, 1);
}
pub fn hasWrite(node: *t.Node, key: c.JSValue) !bool {
    const engine = node.context.engine();
    return c.JS_IsStrictEqual(engine.context, node.write_key, key) or try collectionHas(engine, node.writes, key);
}
pub fn deleted(node: *t.Node, key: c.JSValue) !bool {
    const engine = node.context.engine();
    return c.JS_IsStrictEqual(engine.context, node.delete_key, key) or try collectionHas(engine, node.deletes, key);
}
pub fn objectHas(node: *t.Node, key: c.JSValue) !bool {
    return !try deleted(node, key) and (try hasWrite(node, key) or try hasOwn(node.context.engine(), node.base, key));
}
pub fn objectValue(node: *t.Node, key: c.JSValue) !c.JSValue {
    const engine = node.context.engine();
    if (c.JS_IsStrictEqual(engine.context, node.write_key, key)) return c.JS_DupValue(engine.context, node.write_value);
    if (try collectionHas(engine, node.writes, key)) return js.invoke(engine, node.writes, "get", &.{key});
    return js.getKey(engine, node.base, key);
}
fn setWrite(node: *t.Node, key: c.JSValue, value: c.JSValue) !void {
    const engine = node.context.engine();
    if (!c.JS_IsUndefined(node.writes)) {
        const ignored = try js.invoke(engine, node.writes, "set", &.{ key, value });
        engine.freeValue(ignored);
        return;
    }
    if (c.JS_IsUndefined(node.write_key) or c.JS_IsStrictEqual(engine.context, node.write_key, key)) {
        t.replace(engine, &node.write_key, key);
        t.replace(engine, &node.write_value, value);
        return;
    }
    const writes = try js.builtin(engine, "Map", &.{});
    defer engine.freeValue(writes);
    const first = try js.invoke(engine, writes, "set", &.{ node.write_key, node.write_value });
    engine.freeValue(first);
    const second = try js.invoke(engine, writes, "set", &.{ key, value });
    engine.freeValue(second);
    t.replace(engine, &node.writes, writes);
    t.replace(engine, &node.write_key, c.pi_js_undefined());
    t.replace(engine, &node.write_value, c.pi_js_undefined());
}
fn setDeletion(node: *t.Node, key: c.JSValue) !void {
    const engine = node.context.engine();
    if (!c.JS_IsUndefined(node.deletes)) {
        const ignored = try js.invoke(engine, node.deletes, "add", &.{key});
        engine.freeValue(ignored);
        return;
    }
    if (c.JS_IsUndefined(node.delete_key) or c.JS_IsStrictEqual(engine.context, node.delete_key, key)) {
        t.replace(engine, &node.delete_key, key);
        return;
    }
    const deletes = try js.builtin(engine, "Set", &.{});
    defer engine.freeValue(deletes);
    const first = try js.invoke(engine, deletes, "add", &.{node.delete_key});
    engine.freeValue(first);
    const second = try js.invoke(engine, deletes, "add", &.{key});
    engine.freeValue(second);
    t.replace(engine, &node.deletes, deletes);
    t.replace(engine, &node.delete_key, c.pi_js_undefined());
}
fn removeDeletion(node: *t.Node, key: c.JSValue) !void {
    const engine = node.context.engine();
    if (c.JS_IsStrictEqual(engine.context, node.delete_key, key)) t.replace(engine, &node.delete_key, c.pi_js_undefined());
    try collectionDelete(engine, node.deletes, key);
}
pub fn indexOf(engine: *js.Engine, key: c.JSValue) !?usize {
    if (!c.JS_IsString(key)) return null;
    const text = try engine.toString(key);
    defer engine.gpa.free(text);
    return t.tree.arrayIndex(text);
}
fn named(engine: *js.Engine, value: c.JSValue, name: []const u8) !bool {
    const expected = try engine.checked(c.JS_NewStringLen(engine.context, name.ptr, name.len));
    defer engine.freeValue(expected);
    return c.JS_IsStrictEqual(engine.context, value, expected);
}
pub fn property(node: *t.Node, key: c.JSValue) anyerror!c.JSValue {
    const engine = node.context.engine();
    try t.readable(node.context);
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    if (try isArray(engine, node.base)) {
        const array = try a.getArray(node);
        if (try named(engine, key, "length")) return c.JS_NewFloat64(engine.context, @floatFromInt(array.pieces.length()));
        if (try a.mutatorName(engine, key)) return js.getKey(engine, node.context.binding().mutators, key);
        if (try indexOf(engine, key)) |index| return a.getIndex(node, index);
        const prototype = try scope.get(try scope.keep(try js.global(engine, "Array")), "prototype");
        return scope.result(try scope.builtin("Reflect", "get", &.{ prototype, key, node.proxy }));
    }
    if (c.JS_IsSymbol(key)) return scope.result(try scope.builtin("Reflect", "get", &.{ node.base, key, node.proxy }));
    if (!try objectHas(node, key)) {
        if (try deleted(node, key) or try hasOwn(engine, node.base, key)) return c.pi_js_undefined();
        return scope.result(try scope.builtin("Reflect", "get", &.{ node.base, key, node.proxy }));
    }
    const value = try scope.keep(try objectValue(node, key));
    if (!container(engine, value)) return scope.result(value);
    return c.JS_DupValue(engine.context, (try createNode(node.context, value, node, .object, key, null, try hasWrite(node, key))).proxy);
}
pub fn clonePlacement(context: *t.Context, value: c.JSValue) anyerror!c.JSValue {
    const engine = context.engine();
    if (container(engine, value)) {
        const reference = try js.getKey(engine, value, context.binding().node_symbol);
        defer engine.freeValue(reference);
        if (!c.JS_IsUndefined(reference)) return cloneNode(try t.nodeOf(engine, reference, context.binding()), true);
    }
    return @import("native_chord_json.zig").copyJson(engine, value, c.pi_js_undefined());
}
pub fn cloneStored(context: *t.Context, value: c.JSValue, placement: bool) anyerror!c.JSValue {
    const engine = context.engine();
    const value_owner = c.JS_DupValue(engine.context, value);
    defer engine.freeValue(value_owner);
    try t.tick(context);
    if (!container(engine, value)) return if (placement) @import("native_chord_json.zig").copyJson(engine, value, c.pi_js_undefined()) else c.JS_DupValue(engine.context, value);
    const reference = try js.invoke(engine, context.raw_nodes, "get", &.{value});
    defer engine.freeValue(reference);
    if (c.JS_IsUndefined(reference)) return if (placement) @import("native_chord_json.zig").copyJson(engine, value, c.pi_js_undefined()) else c.JS_DupValue(engine.context, value);
    const node = try t.nodeOf(engine, reference, context.binding());
    if (!placement and !node.dirty and !node.subtree_dirty) return c.JS_DupValue(engine.context, value);
    return cloneNode(node, placement);
}
pub fn cloneNode(node: *t.Node, placement: bool) anyerror!c.JSValue {
    try t.readable(node.context);
    const engine = node.context.engine();
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    if (try isArray(engine, node.base)) {
        const result = try scope.list();
        const array = try a.getArray(node);
        const pieces = try array.pieces.pieces();
        defer engine.gpa.free(pieces);
        for (pieces) |piece| for (0..piece.length) |offset| {
            const value = try scope.keep(try a.entry(node, piece, piece.index(offset)));
            const cloned = try scope.keep(try cloneStored(node.context, value, placement));
            try js.push(engine, result, cloned);
        };
        return scope.result(result);
    }
    const prototype = try scope.keep(try engine.checked(c.JS_GetPrototype(engine.context, node.base)));
    const result = try scope.keep(try engine.checked(c.JS_NewObjectProto(engine.context, prototype)));
    const keys = try scope.keep(try ownKeys(node));
    for (0..try @import("native_values.zig").length(engine, keys)) |index| {
        const key = try scope.at(keys, index);
        const value = try scope.keep(try objectValue(node, key));
        const cloned = try scope.keep(try cloneStored(node.context, value, placement));
        try defineData(engine, result, key, cloned);
    }
    return scope.result(result);
}
pub fn defineData(engine: *js.Engine, object: c.JSValue, key: c.JSValue, value: c.JSValue) !void {
    const atom = try js.atom(engine, key);
    defer c.JS_FreeAtom(engine.context, atom);
    if (c.JS_DefinePropertyValue(engine.context, object, atom, c.JS_DupValue(engine.context, value), c.JS_PROP_C_W_E) < 0) return js.capture(engine);
}
fn setProperty(node: *t.Node, key: c.JSValue, supplied: c.JSValue) !void {
    const engine = node.context.engine();
    try t.writable(node.context);
    if (c.JS_IsSymbol(key)) return js.typeError(engine, "Symbol writes are not supported");
    if (try isArray(engine, node.base)) {
        if (try named(engine, key, "length")) return a.setLength(node, try a.toArrayLength(engine, supplied));
        const index = (try indexOf(engine, key)) orelse return js.typeError(engine, "Only array indices and length can be written");
        if (index > (try a.getArray(node)).pieces.length()) return js.typeError(engine, "Overlay arrays cannot contain holes");
        const value = try clonePlacement(node.context, supplied);
        defer engine.freeValue(value);
        return a.setIndex(node, index, value);
    }
    if (c.JS_IsUndefined(supplied)) return deleteProperty(node, key);
    const stored = try clonePlacement(node.context, supplied);
    defer engine.freeValue(stored);
    const current = try objectValue(node, key);
    defer engine.freeValue(current);
    const was_deleted = try deleted(node, key);
    if (!was_deleted and !container(engine, stored) and c.JS_IsStrictEqual(engine.context, current, stored)) return;
    try reserveDirty(node);
    try setWrite(node, key, stored);
    if (was_deleted and try hasOwn(engine, node.base, key)) {
        if (c.JS_IsUndefined(node.readded)) node.readded = try js.builtin(engine, "Set", &.{});
        const ignored = try js.invoke(engine, node.readded, "add", &.{key});
        engine.freeValue(ignored);
    }
    try removeDeletion(node, key);
    try markDirty(node);
}
fn deleteProperty(node: *t.Node, key: c.JSValue) !void {
    const engine = node.context.engine();
    try t.writable(node.context);
    if (c.JS_IsSymbol(key)) return js.typeError(engine, "Symbol writes are not supported");
    if (try isArray(engine, node.base)) return js.typeError(engine, "Overlay arrays cannot contain holes");
    if (!try objectHas(node, key)) return;
    try reserveDirty(node);
    if (c.JS_IsStrictEqual(engine.context, node.write_key, key)) {
        t.replace(engine, &node.write_key, c.pi_js_undefined());
        t.replace(engine, &node.write_value, c.pi_js_undefined());
    } else try collectionDelete(engine, node.writes, key);
    try collectionDelete(engine, node.readded, key);
    try setDeletion(node, key);
    try markDirty(node);
}
pub fn collectionValues(scope: *Scope, collection: c.JSValue, method: [*:0]const u8) !c.JSValue {
    const result = try scope.list();
    if (c.JS_IsUndefined(collection)) return result;
    const iterable = try scope.keep(try js.invoke(scope.engine, collection, method, &.{}));
    const symbol = try scope.get(try scope.keep(try js.global(scope.engine, "Symbol")), "iterator");
    var iterator = try js.Iterator.init(scope.engine, iterable, symbol);
    defer iterator.deinit();
    errdefer iterator.closePreserving();
    while (try iterator.next()) |item| {
        defer scope.engine.freeValue(item);
        try js.push(scope.engine, result, item);
    }
    return result;
}
pub fn ownKeys(node: *t.Node) !c.JSValue {
    try t.readable(node.context);
    const engine = node.context.engine();
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const keys = try scope.list();
    if (try isArray(engine, node.base)) {
        for (0..(try a.getArray(node)).pieces.length()) |index| {
            const number = c.JS_NewFloat64(engine.context, @floatFromInt(index));
            const text = try scope.keep(try engine.checked(c.JS_ToString(engine.context, number)));
            try js.push(engine, keys, text);
        }
        try js.push(engine, keys, try scope.text("length"));
        return scope.result(keys);
    }
    const base_keys = try scope.keys(node.base);
    const write_keys = try collectionValues(&scope, node.writes, "keys");
    var existing_only = c.JS_IsUndefined(node.delete_key) and c.JS_IsUndefined(node.deletes) and c.JS_IsUndefined(node.readded) and (c.JS_IsUndefined(node.write_key) or try hasOwn(engine, node.base, node.write_key));
    if (existing_only) for (0..try @import("native_values.zig").length(engine, write_keys)) |index| {
        if (!try hasOwn(engine, node.base, try scope.at(write_keys, index))) {
            existing_only = false;
            break;
        }
    };
    if (existing_only) return scope.result(base_keys);
    const seen = try scope.keep(try js.builtin(engine, "Set", &.{}));
    for (0..try @import("native_values.zig").length(engine, base_keys)) |index| {
        const key = try scope.at(base_keys, index);
        if (try deleted(node, key) or try collectionHas(engine, node.readded, key)) continue;
        try js.push(engine, keys, key);
        engine.freeValue(try js.invoke(engine, seen, "add", &.{key}));
    }
    if (!c.JS_IsUndefined(node.write_key) and !try collectionHas(engine, seen, node.write_key)) {
        try js.push(engine, keys, node.write_key);
        engine.freeValue(try js.invoke(engine, seen, "add", &.{node.write_key}));
    }
    for (0..try @import("native_values.zig").length(engine, write_keys)) |index| {
        const key = try scope.at(write_keys, index);
        if (try collectionHas(engine, seen, key)) continue;
        try js.push(engine, keys, key);
        engine.freeValue(try js.invoke(engine, seen, "add", &.{key}));
    }
    var indices: std.ArrayList(usize) = .empty;
    defer indices.deinit(engine.gpa);
    const strings = try scope.list();
    for (0..try @import("native_values.zig").length(engine, keys)) |index| {
        const key = try scope.at(keys, index);
        if (try indexOf(engine, key)) |number| try indices.append(engine.gpa, number) else try js.push(engine, strings, key);
    }
    std.mem.sort(usize, indices.items, {}, struct {
        fn less(_: void, left: usize, right: usize) bool {
            return left < right;
        }
    }.less);
    const sorted = try scope.list();
    for (indices.items) |index| try js.push(engine, sorted, try scope.keep(try engine.checked(c.JS_ToString(engine.context, c.JS_NewFloat64(engine.context, @floatFromInt(index))))));
    for (0..try @import("native_values.zig").length(engine, strings)) |index| try js.push(engine, sorted, try scope.at(strings, index));
    return scope.result(sorted);
}
const Trap = enum(c_int) { get, set, delete, define, descriptor, prototype, has, extensible, keys, prevent, set_prototype };
fn callback(ctx: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, magic: c_int, captures: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = js.Engine.fromContext(ctx.?);
    const binding: *t.Binding = @ptrCast(@alignCast(c.JS_GetOpaque(captures[0], c.JS_GetClassID(captures[0])).?));
    return trap(engine, binding, if (argc > 0) argv[0..@intCast(argc)] else &.{}, @enumFromInt(magic)) catch |err| @import("native_durable.zig").reject(engine, err);
}
fn trap(engine: *js.Engine, binding: *t.Binding, args: []const c.JSValue, operation: Trap) !c.JSValue {
    const target = t.arg(args, 0);
    const key = t.arg(args, 1);
    const reference = try js.getKey(engine, target, binding.node_symbol);
    defer engine.freeValue(reference);
    if (operation == .get and try named(engine, key, "then")) {
        if (c.JS_IsUndefined(reference)) return c.pi_js_undefined();
        const state = try t.getInstance(engine, reference, binding, .node_ref);
        if (t.settled(try t.contextOf(engine, state.data.node_ref.context, binding))) return c.pi_js_undefined();
    }
    const node = try t.nodeOf(engine, reference, binding);
    var lease = t.Lease.init(node.context);
    defer lease.deinit();
    if (operation == .get and c.JS_IsStrictEqual(engine.context, key, binding.node_symbol)) return c.JS_DupValue(engine.context, reference);
    switch (operation) {
        .get => return property(node, key),
        .set => {
            try setProperty(node, key, t.arg(args, 2));
            return c.pi_js_bool(engine.context, 1);
        },
        .delete => {
            try deleteProperty(node, key);
            return c.pi_js_bool(engine.context, 1);
        },
        .define => {
            try t.writable(node.context);
            return js.typeError(engine, "Defining overlay properties is not supported");
        },
        .prevent => {
            try t.writable(node.context);
            return js.typeError(engine, "Overlays cannot be made non-extensible");
        },
        .set_prototype => {
            try t.writable(node.context);
            return js.typeError(engine, "Changing an overlay prototype is not supported");
        },
        .prototype => return engine.checked(c.JS_GetPrototype(engine.context, node.base)),
        .extensible => return c.pi_js_bool(engine.context, 1),
        .keys => return ownKeys(node),
        .has => {
            var found: bool = undefined;
            if (try isArray(engine, node.base)) {
                if (try named(engine, key, "length")) found = true else if (try indexOf(engine, key)) |index| found = index < (try a.getArray(node)).pieces.length() else {
                    const ctor = try js.global(engine, "Array");
                    defer engine.freeValue(ctor);
                    const proto = try js.get(engine, ctor, "prototype");
                    defer engine.freeValue(proto);
                    found = try js.hasKey(engine, proto, key);
                }
            } else found = if (c.JS_IsSymbol(key)) try js.hasKey(engine, node.base, key) else try objectHas(node, key);
            return c.pi_js_bool(engine.context, @intFromBool(found));
        },
        .descriptor => {
            var scope: Scope = .{ .engine = engine };
            defer scope.deinit();
            if (try isArray(engine, node.base)) {
                if (try named(engine, key, "length")) {
                    try js.setKey(engine, node.target, key, c.JS_NewFloat64(engine.context, @floatFromInt((try a.getArray(node)).pieces.length())));
                    return scope.result(try scope.builtin("Reflect", "getOwnPropertyDescriptor", &.{ node.target, key }));
                }
                const index = (try indexOf(engine, key)) orelse return c.pi_js_undefined();
                if (index >= (try a.getArray(node)).pieces.length()) return c.pi_js_undefined();
            } else if (c.JS_IsSymbol(key) or !try objectHas(node, key)) return c.pi_js_undefined();
            const result = try scope.record();
            try js.define(engine, result, "configurable", c.pi_js_bool(engine.context, 1));
            try js.define(engine, result, "enumerable", c.pi_js_bool(engine.context, 1));
            try js.define(engine, result, "writable", c.pi_js_bool(engine.context, @intFromBool(node.context.status == .open)));
            try js.define(engine, result, "value", try property(node, key));
            return scope.result(result);
        },
    }
}
pub fn handler(engine: *js.Engine, binding: *t.Binding) !c.JSValue {
    const result = try js.object(engine);
    errdefer engine.freeValue(result);
    inline for (.{ .{ "get", Trap.get }, .{ "set", Trap.set }, .{ "deleteProperty", Trap.delete }, .{ "defineProperty", Trap.define }, .{ "getOwnPropertyDescriptor", Trap.descriptor }, .{ "getPrototypeOf", Trap.prototype }, .{ "has", Trap.has }, .{ "isExtensible", Trap.extensible }, .{ "ownKeys", Trap.keys }, .{ "preventExtensions", Trap.prevent }, .{ "setPrototypeOf", Trap.set_prototype } }) |entry_| {
        var captures = [_]c.JSValue{binding.self};
        const function_value = try engine.checked(c.JS_NewCFunctionData2(engine.context, callback, entry_[0], 0, @intFromEnum(entry_[1]), 1, &captures));
        try js.define(engine, result, entry_[0], function_value);
    }
    return result;
}
pub fn clear(context: *t.Context, targets: bool) !void {
    const engine = context.engine();
    if (targets) for (context.nodes.items) |node| {
        if (c.JS_IsArray(node.target)) {
            if (c.JS_SetPropertyStr(engine.context, node.target, "length", c.JS_NewInt32(engine.context, 0)) < 0) return js.capture(engine);
        }
        const atom = try js.atom(engine, context.binding().node_symbol);
        defer c.JS_FreeAtom(engine.context, atom);
        if (c.JS_DeleteProperty(engine.context, node.target, atom, 0) < 0) return js.capture(engine);
    };
    for (context.nodes.items) |node| {
        releaseNodeValues(engine.runtime, engine.gpa, node);
        if (context.active_depth > 0) {
            node.retired_next = context.retired_nodes;
            context.retired_nodes = node;
        } else engine.gpa.destroy(node);
    }
    context.nodes.clearRetainingCapacity();
    context.dirty.clearRetainingCapacity();
    if (context.active_depth == 0) freeRetired(engine.gpa, context);
}
fn freeNode(runtime: ?*c.JSRuntime, allocator: std.mem.Allocator, node: *t.Node) void {
    releaseNodeValues(runtime, allocator, node);
    allocator.destroy(node);
}
fn releaseNodeValues(runtime: ?*c.JSRuntime, allocator: std.mem.Allocator, node: *t.Node) void {
    inline for (.{ "base", "parent_key", "target", "proxy", "reference", "write_key", "write_value", "writes", "delete_key", "deletes", "readded", "path" }) |field| {
        c.JS_FreeValueRT(runtime, @field(node, field));
        @field(node, field) = c.pi_js_undefined();
    }
    if (node.array) |*array| a.deinit(runtime, allocator, array);
    node.array = null;
}
pub fn freeRetired(allocator: std.mem.Allocator, context: *t.Context) void {
    var next = context.retired_nodes;
    context.retired_nodes = null;
    while (next) |node| {
        const following = node.retired_next;
        allocator.destroy(node);
        next = following;
    }
    if (context.released) {
        context.nodes.deinit(allocator);
        context.nodes = .empty;
        context.dirty.deinit(allocator);
        context.dirty = .empty;
    }
}
pub fn deinit(runtime: ?*c.JSRuntime, allocator: std.mem.Allocator, context: *t.Context) void {
    for (context.nodes.items) |node| freeNode(runtime, allocator, node);
    context.nodes.deinit(allocator);
    context.nodes = .empty;
    context.dirty.deinit(allocator);
    context.dirty = .empty;
    freeRetired(allocator, context);
}
pub fn mark(runtime: ?*c.JSRuntime, context: *t.Context, visitor: ?*const c.JS_MarkFunc) void {
    for (context.nodes.items) |node| {
        inline for (.{ "base", "parent_key", "target", "proxy", "reference", "write_key", "write_value", "writes", "delete_key", "deletes", "readded", "path" }) |field| c.JS_MarkValue(runtime, @field(node, field), visitor);
        if (node.array) |*array| a.mark(runtime, array, visitor);
    }
}
