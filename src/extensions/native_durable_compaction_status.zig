//! Compaction task live status mutations shared by its native phases.
const std = @import("std");
const engine_mod = @import("engine.zig");
const vm = @import("native_values.zig");
const c = engine_mod.c;
const Engine = engine_mod.Engine;
pub fn find(engine: *Engine, live: c.JSValue, task_id: c.JSValue) !c.JSValue {
    const statuses = try vm.get(engine, live, "compactions");
    defer engine.freeValue(statuses);
    if (c.JS_IsUndefined(statuses)) return c.pi_js_undefined();
    for (0..try vm.length(engine, statuses)) |index| {
        const status = try engine.checked(c.JS_GetPropertyUint32(engine.context, statuses, @intCast(index)));
        errdefer engine.freeValue(status);
        const id = try vm.get(engine, status, "taskId");
        defer engine.freeValue(id);
        if (c.JS_IsStrictEqual(engine.context, id, task_id)) return status;
        engine.freeValue(status);
    }
    return c.pi_js_undefined();
}
pub fn remove(engine: *Engine, live: c.JSValue, task_id: c.JSValue) !void {
    const statuses = try vm.get(engine, live, "compactions");
    defer engine.freeValue(statuses);
    if (c.JS_IsUndefined(statuses)) return;
    for (0..try vm.length(engine, statuses)) |index| {
        const status = try engine.checked(c.JS_GetPropertyUint32(engine.context, statuses, @intCast(index)));
        defer engine.freeValue(status);
        const id = try vm.get(engine, status, "taskId");
        defer engine.freeValue(id);
        if (!c.JS_IsStrictEqual(engine.context, id, task_id)) continue;
        const result = try vm.invoke(engine, statuses, "splice", &.{ c.JS_NewFloat64(engine.context, @floatFromInt(index)), c.JS_NewInt32(engine.context, 1) });
        engine.freeValue(result);
        break;
    }
    if (try vm.length(engine, statuses) == 0) {
        const key = c.JS_NewAtom(engine.context, "compactions");
        defer c.JS_FreeAtom(engine.context, key);
        if (c.JS_DeleteProperty(engine.context, live, key, c.JS_PROP_THROW) < 0) return @import("native_js_values.zig").capture(engine);
    }
}
pub fn add(engine: *Engine, live: c.JSValue, status: c.JSValue) !void {
    var statuses = try vm.get(engine, live, "compactions");
    defer engine.freeValue(statuses);
    if (c.JS_IsUndefined(statuses) or c.JS_IsNull(statuses)) {
        engine.freeValue(statuses);
        statuses = try vm.array(engine);
        try @import("native_tool_info.zig").putData(engine, live, "compactions", c.JS_DupValue(engine.context, statuses));
    }
    try @import("native_js_values.zig").push(engine, statuses, status);
}
