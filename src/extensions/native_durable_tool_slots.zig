//! Durable v2 live tool slots. Nested lookup stays logarithmic so draft
//! tracking and updates do not grow quadratically with nested-call batches.
const engine_mod = @import("engine.zig");
const vm = @import("native_values.zig");
const js = @import("native_js_values.zig");
const c = engine_mod.c;
const Engine = engine_mod.Engine;

pub fn find(engine: *Engine, live: c.JSValue, task_id: c.JSValue) !c.JSValue {
    const tools = try vm.get(engine, live, "tools");
    defer engine.freeValue(tools);
    const slot = if (c.JS_IsUndefined(tools) or c.JS_IsNull(tools)) c.pi_js_undefined() else value: {
        var captures = [_]c.JSValue{task_id};
        const predicate = try engine.checked(c.JS_NewCFunctionData2(engine.context, matchesTask, "", 1, 0, captures.len, &captures));
        defer engine.freeValue(predicate);
        break :value try vm.invoke(engine, tools, "find", &.{predicate});
    };
    errdefer engine.freeValue(slot);
    if (!c.JS_IsUndefined(slot)) return slot;
    const checked_nested = try vm.get(engine, live, "nestedTools");
    defer engine.freeValue(checked_nested);
    if (c.JS_IsUndefined(checked_nested)) return slot;
    // Source reads this property again after the existence test.
    const nested = try vm.get(engine, live, "nestedTools");
    defer engine.freeValue(nested);
    var low: i64 = 0;
    var high: i64 = @as(i64, @intCast(try vm.length(engine, nested))) - 1;
    while (low <= high) {
        const middle: u32 = @as(u32, @truncate(@as(u64, @intCast(low + high)))) >> 1;
        const candidate = try engine.checked(c.JS_GetPropertyUint32(engine.context, nested, middle));
        defer engine.freeValue(candidate);
        const id = try vm.get(engine, candidate, "taskId");
        defer engine.freeValue(id);
        if (c.JS_IsStrictEqual(engine.context, id, task_id)) return c.JS_DupValue(engine.context, candidate);
        const compared_id = try vm.get(engine, candidate, "taskId");
        defer engine.freeValue(compared_id);
        const comparison = try @import("native_schema_numeric.zig").compare(engine, compared_id, task_id);
        if (comparison == .lt) low = @as(i64, middle) + 1 else high = @as(i64, middle) - 1;
    }
    return c.pi_js_undefined();
}
fn matchesTask(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, data: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = Engine.fromContext(context.?);
    const slot = if (argc > 0) argv[0] else c.pi_js_undefined();
    const id = vm.get(engine, slot, "taskId") catch |err| return @import("native_durable.zig").reject(engine, err);
    defer engine.freeValue(id);
    return c.pi_js_bool(engine.context, @intFromBool(c.JS_IsStrictEqual(engine.context, id, data[0])));
}
pub fn clearProgress(engine: *Engine, slot: c.JSValue) !void {
    inline for (.{ "output", "droppedBytes", "droppedLines", "details", "diagnostics" }) |property| {
        try deleteProperty(engine, slot, property);
    }
}
pub fn finish(engine: *Engine, slot: c.JSValue) !void {
    try vm.put(engine, slot, "status", try engine.checked(c.JS_NewString(engine.context, "done")));
    try clearProgress(engine, slot);
}
pub fn removeBelow(engine: *Engine, live: c.JSValue, task_id: c.JSValue, iterator_symbol: c.JSValue) !void {
    const nested = try vm.get(engine, live, "nestedTools");
    defer engine.freeValue(nested);
    if (c.JS_IsUndefined(nested)) return;
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    const set_constructor = try vm.get(engine, global, "Set");
    defer engine.freeValue(set_constructor);
    const initial = try vm.array(engine);
    defer engine.freeValue(initial);
    if (c.JS_SetPropertyUint32(engine.context, initial, 0, c.JS_DupValue(engine.context, task_id)) < 0) return error.JavaScriptException;
    var args = [_]c.JSValue{initial};
    const removed = try engine.checked(c.JS_CallConstructor(engine.context, set_constructor, args.len, &args));
    defer engine.freeValue(removed);
    var iterator = try js.Iterator.init(engine, nested, iterator_symbol);
    defer iterator.deinit();
    errdefer iterator.closePreserving();
    while (try iterator.next()) |slot| {
        defer engine.freeValue(slot);
        const has = try vm.get(engine, removed, "has");
        defer engine.freeValue(has);
        const parent = try vm.get(engine, slot, "parentTaskId");
        defer engine.freeValue(parent);
        var lookup_args = [_]c.JSValue{parent};
        const found = try engine.checked(c.JS_Call(engine.context, has, removed, lookup_args.len, &lookup_args));
        defer engine.freeValue(found);
        if (c.JS_ToBool(engine.context, found) == 0) continue;
        const add = try vm.get(engine, removed, "add");
        defer engine.freeValue(add);
        const id = try vm.get(engine, slot, "taskId");
        defer engine.freeValue(id);
        var add_args = [_]c.JSValue{id};
        const added = try engine.checked(c.JS_Call(engine.context, add, removed, add_args.len, &add_args));
        engine.freeValue(added);
    }
    var index = try vm.length(engine, nested);
    while (index != 0) {
        index -= 1;
        const slot = try engine.checked(c.JS_GetPropertyUint32(engine.context, nested, @intCast(index)));
        defer engine.freeValue(slot);
        const has = try vm.get(engine, removed, "has");
        defer engine.freeValue(has);
        const parent = try vm.get(engine, slot, "parentTaskId");
        defer engine.freeValue(parent);
        var lookup_args = [_]c.JSValue{parent};
        const found = try engine.checked(c.JS_Call(engine.context, has, removed, lookup_args.len, &lookup_args));
        defer engine.freeValue(found);
        if (c.JS_ToBool(engine.context, found) == 0) continue;
        const removed_slot = try vm.invoke(engine, nested, "splice", &.{ c.JS_NewInt64(engine.context, @intCast(index)), c.JS_NewInt32(engine.context, 1) });
        engine.freeValue(removed_slot);
    }
    if (try vm.length(engine, nested) == 0) {
        try deleteProperty(engine, live, "nestedTools");
    }
}
fn deleteProperty(engine: *Engine, receiver: c.JSValue, name: [:0]const u8) !void {
    const atom = c.JS_NewAtom(engine.context, name);
    defer c.JS_FreeAtom(engine.context, atom);
    if (c.JS_DeleteProperty(engine.context, receiver, atom, c.JS_PROP_THROW) < 0) {
        _ = try engine.checked(c.JS_Throw(engine.context, c.JS_GetException(engine.context)));
        unreachable;
    }
}
