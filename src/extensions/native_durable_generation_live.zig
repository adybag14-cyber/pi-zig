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
const awaiting = @import("native_durable_await.zig");
pub fn startRun(engine: *Engine, intrinsics: *awaiting.Intrinsics, tx: c.JSValue, conversation: c.JSValue, live: c.JSValue, inputs: c.JSValue, generation_token: c.JSValue) !c.JSValue {
    if (c.JS_IsUndefined(generation_token)) return error.GenerationTaskUnavailable;
    const state = try vm.object(engine);
    defer engine.freeValue(state);
    try @import("native_tool_info.zig").putData(engine, state, "live", c.JS_DupValue(engine.context, live));
    try @import("native_tool_info.zig").putData(engine, state, "inputs", c.JS_DupValue(engine.context, inputs));
    const input = try vm.object(engine);
    defer engine.freeValue(input);
    const options = try vm.object(engine);
    defer engine.freeValue(options);
    const ownership = try vm.object(engine);
    defer engine.freeValue(ownership);
    try @import("native_tool_info.zig").putData(engine, ownership, "kind", try engine.checked(c.JS_NewString(engine.context, "conversation")));
    try @import("native_tool_info.zig").putData(engine, options, "ownership", c.JS_DupValue(engine.context, ownership));
    try @import("native_tool_info.zig").putData(engine, options, "conversationId", c.JS_DupValue(engine.context, conversation));
    const pending = try vm.invoke(engine, tx, "createTask", &.{ generation_token, input, options });
    defer engine.freeValue(pending);
    return awaiting.continueWith(started, engine, intrinsics, state, pending, 0);
}
fn started(engine: *Engine, state: c.JSValue, value: c.JSValue, rejected: bool, _: c_int) !c.JSValue {
    if (rejected) return engine.checked(c.JS_Throw(engine.context, c.JS_DupValue(engine.context, value)));
    const live = try vm.get(engine, state, "live");
    defer engine.freeValue(live);
    const inputs = try vm.get(engine, state, "inputs");
    defer engine.freeValue(inputs);
    const run = try vm.object(engine);
    defer engine.freeValue(run);
    try @import("native_tool_info.zig").putData(engine, run, "taskId", c.JS_DupValue(engine.context, value));
    try @import("native_tool_info.zig").putData(engine, run, "inputs", c.JS_DupValue(engine.context, inputs));
    try @import("native_tool_info.zig").putData(engine, live, "run", c.JS_DupValue(engine.context, run));
    return c.pi_js_undefined();
}
