//! Generation live-run cleanup and ownership transfer, implemented in Zig.
const engine_mod = @import("engine.zig");
const vm = @import("native_values.zig");
const js = @import("native_js_values.zig");
const c = engine_mod.c;
const Engine = engine_mod.Engine;
fn delete(engine: *Engine, object: c.JSValue, key: [:0]const u8) !void {
    const atom = c.JS_NewAtom(engine.context, key);
    defer c.JS_FreeAtom(engine.context, atom);
    if (c.JS_DeleteProperty(engine.context, object, atom, c.JS_PROP_THROW) < 0) return js.capture(engine);
}
pub fn endRun(engine: *Engine, tx: c.JSValue, live: c.JSValue, task_id: c.JSValue, settlement: c.JSValue) !void {
    const run = try vm.get(engine, live, "run");
    defer engine.freeValue(run);
    if (!c.JS_IsUndefined(run) and !c.JS_IsNull(run)) {
        const owner = try vm.get(engine, run, "taskId");
        defer engine.freeValue(owner);
        if (c.JS_IsStrictEqual(engine.context, owner, task_id)) {
            const inputs = try vm.get(engine, run, "inputs");
            defer engine.freeValue(inputs);
            for (0..try vm.length(engine, inputs)) |index| {
                const id = try engine.checked(c.JS_GetPropertyUint32(engine.context, inputs, @intCast(index)));
                defer engine.freeValue(id);
                const ignored = try vm.invoke(engine, tx, "settleSubmission", &.{ id, settlement });
                engine.freeValue(ignored);
            }
            try delete(engine, live, "run");
        }
    }
    inline for (.{ "generation", "tools", "nestedTools" }) |key| try delete(engine, live, key);
}
pub fn handOver(engine: *Engine, live: c.JSValue, from: c.JSValue, to: c.JSValue) !void {
    const run = try vm.get(engine, live, "run");
    defer engine.freeValue(run);
    if (c.JS_IsUndefined(run) or c.JS_IsNull(run)) return;
    const owner = try vm.get(engine, run, "taskId");
    defer engine.freeValue(owner);
    if (c.JS_IsStrictEqual(engine.context, owner, from)) try @import("native_tool_info.zig").putData(engine, run, "taskId", c.JS_DupValue(engine.context, to));
}
