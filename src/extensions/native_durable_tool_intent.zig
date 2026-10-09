//! Record execution intent, or clear the interrupted attempt before safe replay.
const engine_mod = @import("engine.zig");
const vm = @import("native_values.zig");
const awaiting = @import("native_durable_await.zig");
const c = engine_mod.c;
const Engine = engine_mod.Engine;
fn put(engine: *Engine, state: c.JSValue, key: [:0]const u8, value: c.JSValue) !void {
    try @import("native_tool_info.zig").putData(engine, state, key, c.JS_DupValue(engine.context, value));
}
pub fn commit(engine: *Engine, intrinsics: *awaiting.Intrinsics, live_token: c.JSValue, task: c.JSValue, runtime: c.JSValue, prepared: c.JSValue, context: c.JSValue, replay: bool) !c.JSValue {
    const state = try vm.object(engine);
    defer engine.freeValue(state);
    inline for (.{ .{ "task", task }, .{ "runtime", runtime }, .{ "prepared", prepared }, .{ "liveToken", live_token }, .{ "promiseConstructor", intrinsics.constructor }, .{ "promiseResolve", intrinsics.resolve }, .{ "promiseThen", intrinsics.then_function } }) |field| try put(engine, state, field[0], field[1]);
    try put(engine, state, "replay", c.pi_js_bool(engine.context, @intFromBool(replay)));
    var captures = [_]c.JSValue{state};
    const callback = try engine.checked(c.JS_NewCFunctionData2(engine.context, transaction, "", 1, 0, captures.len, &captures));
    defer engine.freeValue(callback);
    return vm.invoke(engine, runtime, "commit", &.{ callback, context });
}
fn transaction(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, data: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = Engine.fromContext(context.?);
    return start(engine, data[0], if (argc > 0) argv[0] else c.pi_js_undefined()) catch |err| @import("native_durable.zig").rejectedPromise(engine, err);
}
fn start(engine: *Engine, state: c.JSValue, tx: c.JSValue) !c.JSValue {
    const runtime = try vm.get(engine, state, "runtime");
    defer engine.freeValue(runtime);
    const token = try vm.get(engine, state, "liveToken");
    defer engine.freeValue(token);
    const conversation = try vm.get(engine, runtime, "conversationId");
    defer engine.freeValue(conversation);
    const pending = try vm.invoke(engine, tx, "doc", &.{ token, conversation });
    defer engine.freeValue(pending);
    const constructor = try vm.get(engine, state, "promiseConstructor");
    defer engine.freeValue(constructor);
    const resolve = try vm.get(engine, state, "promiseResolve");
    defer engine.freeValue(resolve);
    const then_function = try vm.get(engine, state, "promiseThen");
    defer engine.freeValue(then_function);
    var intrinsics: awaiting.Intrinsics = .{ .constructor = constructor, .resolve = resolve, .then_function = then_function };
    return awaiting.continueWith(finish, engine, &intrinsics, state, pending, 0);
}
fn finish(engine: *Engine, state: c.JSValue, live: c.JSValue, rejected: bool, _: c_int) !c.JSValue {
    if (rejected) return engine.checked(c.JS_Throw(engine.context, c.JS_DupValue(engine.context, live)));
    const runtime = try vm.get(engine, state, "runtime");
    defer engine.freeValue(runtime);
    const task_id = try vm.get(engine, runtime, "taskId");
    defer engine.freeValue(task_id);
    const slot = try @import("native_durable_tool_slots.zig").find(engine, live, task_id);
    defer engine.freeValue(slot);
    const replay = try vm.get(engine, state, "replay");
    defer engine.freeValue(replay);
    if (c.JS_ToBool(engine.context, replay) != 0) {
        if (!c.JS_IsUndefined(slot)) try @import("native_durable_tool_slots.zig").clearProgress(engine, slot);
        return c.pi_js_undefined();
    }
    if (!c.JS_IsUndefined(slot)) try vm.put(engine, slot, "status", try engine.checked(c.JS_NewString(engine.context, "running")));
    const task = try vm.get(engine, state, "task");
    defer engine.freeValue(task);
    const input = try vm.get(engine, task, "input");
    defer engine.freeValue(input);
    const kind = try vm.get(engine, input, "kind");
    defer engine.freeValue(kind);
    const prepared = try vm.get(engine, state, "prepared");
    defer engine.freeValue(prepared);
    const final = try vm.get(engine, prepared, "arguments");
    defer engine.freeValue(final);
    if (try @import("native_durable_tool_call.zig").equalsString(engine, kind, "nested")) {
        const call = try vm.get(engine, input, "call");
        defer engine.freeValue(call);
        const original = try vm.get(engine, call, "arguments");
        defer engine.freeValue(original);
        const changed = !try @import("native_durable_tool_json.zig").equal(engine, original, final);
        if (changed and !c.JS_IsUndefined(slot)) {
            const atom = c.JS_NewAtom(engine.context, "parentTaskId");
            defer c.JS_FreeAtom(engine.context, atom);
            const parent = c.JS_HasProperty(engine.context, slot, atom);
            if (parent < 0) return @import("native_js_values.zig").capture(engine);
            if (parent != 0) try vm.put(engine, slot, "arguments", c.JS_DupValue(engine.context, final));
        }
    }
    const checkpoint = try vm.object(engine);
    defer engine.freeValue(checkpoint);
    try @import("native_tool_info.zig").putData(engine, checkpoint, "phase", try engine.checked(c.JS_NewString(engine.context, "execute")));
    try put(engine, checkpoint, "arguments", final);
    const tool = try vm.get(engine, prepared, "tool");
    defer engine.freeValue(tool);
    const policy = try vm.get(engine, tool, "replay");
    defer engine.freeValue(policy);
    if (c.JS_IsUndefined(policy) or c.JS_IsNull(policy)) try @import("native_tool_info.zig").putData(engine, checkpoint, "replay", try engine.checked(c.JS_NewString(engine.context, "unsafe"))) else try put(engine, checkpoint, "replay", policy);
    const result = try vm.object(engine);
    errdefer engine.freeValue(result);
    try @import("native_tool_info.zig").putData(engine, result, "status", try engine.checked(c.JS_NewString(engine.context, "running")));
    try put(engine, result, "checkpoint", checkpoint);
    return result;
}
