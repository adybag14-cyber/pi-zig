//! AgentLoop's exported runToolCall, using the genuine native pipeline stages.
const em = @import("engine.zig");
const sdk = @import("native_sdk.zig");
const temp = @import("native_sdk_prompt_scope.zig");
const Scope = temp.Scope;
const flow = @import("native_agent_async.zig");
const pipeline = @import("native_agent_tool_call.zig");
const c = em.c;
pub fn create(engine: *em.Engine) !c.JSValue {
    const function = try engine.checked(c.JS_NewCFunction(engine.context, dispatch, "runToolCall", 2));
    errdefer engine.freeValue(function);
    const parent = try engine.checked(c.JS_GetAsyncFunctionPrototype(engine.context));
    defer engine.freeValue(parent);
    if (c.JS_SetPrototype(engine.context, function, parent) < 0) return @import("native_js_values.zig").capture(engine);
    return function;
}
fn dispatch(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    return run(engine, if (argc > 0) argv[0] else c.pi_js_undefined(), if (argc > 1) argv[1] else c.pi_js_undefined()) catch |err| sdk.fail(engine, err);
}
pub fn run(engine: *em.Engine, tool_call: c.JSValue, options: c.JSValue) !c.JSValue {
    const pending = try flow.create(engine, c.pi_js_undefined());
    defer engine.freeValue(pending.owner);
    errdefer engine.freeValue(pending.promise);
    start(engine, pending.owner, tool_call, options) catch |err| try flow.rejectError(engine, pending.owner, err);
    return pending.promise;
}
fn start(engine: *em.Engine, owner: c.JSValue, tool_call: c.JSValue, options: c.JSValue) !void {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const assistant = try scope.get(options, "assistantMessage");
    const context = try scope.get(options, "context");
    const signal = try scope.get(options, "signal");
    inline for (.{ .{ "toolCall", tool_call }, .{ "options", options }, .{ "assistant", assistant }, .{ "context", context }, .{ "signal", signal } }) |field| try scope.put(owner, field[0], field[1]);
    const preparation = try scope.own(try pipeline.prepare(engine, context, assistant, tool_call, options, signal, try scope.get(options, "tools")));
    try flow.wait(step, engine, owner, preparation, 0);
}
fn noop(_: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue) callconv(.c) c.JSValue {
    return c.pi_js_undefined();
}
fn step(engine: *em.Engine, owner: c.JSValue, value: c.JSValue, rejected: bool, stage: c_int) !void {
    if (rejected) return flow.settle(engine, owner, true, value);
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    if (stage == 0) {
        if (scope.equal(try scope.get(value, "kind"), try scope.text("immediate"))) {
            const result = try scope.object();
            try scope.put(result, "toolCall", try scope.get(owner, "toolCall"));
            try scope.put(result, "result", try scope.get(value, "result"));
            try scope.put(result, "isError", try scope.get(value, "isError"));
            return flow.settle(engine, owner, false, result);
        }
        try scope.put(owner, "prepared", value);
        var update = try scope.get(try scope.get(owner, "options"), "onUpdate");
        if (temp.nullish(update)) update = try scope.own(try engine.checked(c.JS_NewCFunction(engine.context, noop, "", 0)));
        const executed = try scope.own(try pipeline.execute(engine, value, try scope.get(owner, "signal"), update));
        return flow.wait(step, engine, owner, executed, 1);
    }
    const finalized = try scope.own(try pipeline.finalize(engine, try scope.get(owner, "context"), try scope.get(owner, "assistant"), try scope.get(owner, "prepared"), value, try scope.get(owner, "options"), try scope.get(owner, "signal")));
    try flow.settle(engine, owner, false, finalized);
}
