//! Structural argument comparison for replay and nested-call identity.
const engine_mod = @import("engine.zig");
const vm = @import("native_values.zig");
const js = @import("native_js_values.zig");
const c = engine_mod.c;
const Engine = engine_mod.Engine;
pub fn equal(engine: *Engine, left: c.JSValue, right: c.JSValue) !bool {
    if (c.JS_IsStrictEqual(engine.context, left, right)) return true;
    if (!c.JS_IsObject(left) or !c.JS_IsObject(right) or c.JS_IsFunction(engine.context, left) or c.JS_IsFunction(engine.context, right)) return false;
    const array = try js.global(engine, "Array");
    defer engine.freeValue(array);
    const left_array = try vm.invoke(engine, array, "isArray", &.{left});
    defer engine.freeValue(left_array);
    const lhs_is_array = c.JS_ToBool(engine.context, left_array) != 0;
    const right_array = if (lhs_is_array) c.pi_js_bool(engine.context, 0) else try vm.invoke(engine, array, "isArray", &.{right});
    defer engine.freeValue(right_array);
    if (lhs_is_array or c.JS_ToBool(engine.context, right_array) != 0) {
        const checked_left = try vm.invoke(engine, array, "isArray", &.{left});
        defer engine.freeValue(checked_left);
        if (c.JS_ToBool(engine.context, checked_left) == 0) return false;
        const checked_right = try vm.invoke(engine, array, "isArray", &.{right});
        defer engine.freeValue(checked_right);
        if (c.JS_ToBool(engine.context, checked_right) == 0) return false;
        const left_length = try vm.get(engine, left, "length");
        defer engine.freeValue(left_length);
        const right_length = try vm.get(engine, right, "length");
        defer engine.freeValue(right_length);
        if (!c.JS_IsStrictEqual(engine.context, left_length, right_length)) return false;
        var captures = [_]c.JSValue{right};
        const predicate = try engine.checked(c.JS_NewCFunctionData2(engine.context, arrayItem, "", 2, 0, captures.len, &captures));
        defer engine.freeValue(predicate);
        const matched = try vm.invoke(engine, left, "every", &.{predicate});
        defer engine.freeValue(matched);
        return c.JS_ToBool(engine.context, matched) != 0;
    }
    const object = try js.global(engine, "Object");
    defer engine.freeValue(object);
    const keys = try vm.invoke(engine, object, "keys", &.{left});
    defer engine.freeValue(keys);
    const key_count = try vm.get(engine, keys, "length");
    defer engine.freeValue(key_count);
    const other_keys = try vm.invoke(engine, object, "keys", &.{right});
    defer engine.freeValue(other_keys);
    const other_count = try vm.get(engine, other_keys, "length");
    defer engine.freeValue(other_count);
    if (!c.JS_IsStrictEqual(engine.context, key_count, other_count)) return false;
    var captures = [_]c.JSValue{ left, right };
    const predicate = try engine.checked(c.JS_NewCFunctionData2(engine.context, objectItem, "", 1, 0, captures.len, &captures));
    defer engine.freeValue(predicate);
    const matched = try vm.invoke(engine, keys, "every", &.{predicate});
    defer engine.freeValue(matched);
    return c.JS_ToBool(engine.context, matched) != 0;
}
fn arrayItem(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, data: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = Engine.fromContext(context.?);
    const value = if (argc > 0) argv[0] else c.pi_js_undefined();
    const index = if (argc > 1) argv[1] else c.pi_js_undefined();
    const other = js.getKey(engine, data[0], index) catch |err| return @import("native_durable.zig").reject(engine, err);
    defer engine.freeValue(other);
    const result = equal(engine, value, other) catch |err| return @import("native_durable.zig").reject(engine, err);
    return c.pi_js_bool(engine.context, @intFromBool(result));
}
fn objectItem(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, data: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = Engine.fromContext(context.?);
    return objectEqual(engine, data[0], data[1], if (argc > 0) argv[0] else c.pi_js_undefined()) catch |err| @import("native_durable.zig").reject(engine, err);
}
fn objectEqual(engine: *Engine, left: c.JSValue, right: c.JSValue, key: c.JSValue) !c.JSValue {
    const object = try js.global(engine, "Object");
    defer engine.freeValue(object);
    const own = try vm.invoke(engine, object, "hasOwn", &.{ right, key });
    defer engine.freeValue(own);
    if (c.JS_ToBool(engine.context, own) == 0) return c.pi_js_bool(engine.context, 0);
    const a = try js.getKey(engine, left, key);
    defer engine.freeValue(a);
    const b = try js.getKey(engine, right, key);
    defer engine.freeValue(b);
    return c.pi_js_bool(engine.context, @intFromBool(try equal(engine, a, b)));
}

/// Update compatible containers leaf by leaf so the durable draft records
/// changed leaves and appends rather than replacing the complete details tree.
pub fn assign(engine: *Engine, target: c.JSValue, key: c.JSValue, value: c.JSValue, iterator_symbol: c.JSValue) !void {
    const current = try js.getKey(engine, target, key);
    defer engine.freeValue(current);
    if (try isRecord(engine, current) and try isRecord(engine, value)) {
        const object = try js.global(engine, "Object");
        defer engine.freeValue(object);
        const keys = try vm.invoke(engine, object, "keys", &.{current});
        defer engine.freeValue(keys);
        var key_iterator = try js.Iterator.init(engine, keys, iterator_symbol);
        defer key_iterator.deinit();
        errdefer key_iterator.closePreserving();
        while (try key_iterator.next()) |name| {
            defer engine.freeValue(name);
            const own = try vm.invoke(engine, object, "hasOwn", &.{ value, name });
            defer engine.freeValue(own);
            if (c.JS_ToBool(engine.context, own) == 0) {
                const atom = try js.atom(engine, name);
                defer c.JS_FreeAtom(engine.context, atom);
                if (c.JS_DeleteProperty(engine.context, current, atom, c.JS_PROP_THROW) < 0) return js.capture(engine);
            }
        }
        const entries = try vm.invoke(engine, object, "entries", &.{value});
        defer engine.freeValue(entries);
        var entry_iterator = try js.Iterator.init(engine, entries, iterator_symbol);
        defer entry_iterator.deinit();
        errdefer entry_iterator.closePreserving();
        while (try entry_iterator.next()) |entry| {
            defer engine.freeValue(entry);
            // Object.entries returns actual two-element arrays. Read through
            // their iterator to retain the Source destructuring boundary.
            var pair = try js.Iterator.init(engine, entry, iterator_symbol);
            defer pair.deinit();
            errdefer pair.closePreserving();
            const name = try pair.next() orelse c.pi_js_undefined();
            defer engine.freeValue(name);
            const child = try pair.next() orelse c.pi_js_undefined();
            defer engine.freeValue(child);
            try pair.close();
            try assign(engine, current, name, child, iterator_symbol);
        }
        return;
    }
    const array = try js.global(engine, "Array");
    defer engine.freeValue(array);
    const current_array = try vm.invoke(engine, array, "isArray", &.{current});
    defer engine.freeValue(current_array);
    if (c.JS_ToBool(engine.context, current_array) != 0) {
        const value_array = try vm.invoke(engine, array, "isArray", &.{value});
        defer engine.freeValue(value_array);
        if (c.JS_ToBool(engine.context, value_array) != 0 and try vm.length(engine, current) <= try vm.length(engine, value)) {
            var index: u32 = 0;
            while (index < try vm.length(engine, value)) : (index += 1) {
                const item = try engine.checked(c.JS_GetPropertyUint32(engine.context, value, index));
                defer engine.freeValue(item);
                if (index < try vm.length(engine, current)) try assign(engine, current, c.JS_NewInt64(engine.context, index), item, iterator_symbol) else try js.push(engine, current, item);
            }
            return;
        }
    }
    if (!c.JS_IsStrictEqual(engine.context, current, value)) try js.setKey(engine, target, key, value);
}
fn isRecord(engine: *Engine, value: c.JSValue) !bool {
    if (!c.JS_IsObject(value) or c.JS_IsFunction(engine.context, value)) return false;
    const array = try js.global(engine, "Array");
    defer engine.freeValue(array);
    const result = try vm.invoke(engine, array, "isArray", &.{value});
    defer engine.freeValue(result);
    return c.JS_ToBool(engine.context, result) == 0;
}
