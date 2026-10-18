//! Actual exported runToolCall: two Source Await boundaries followed by
//! direct return adoption of finalizeExecutedToolCall. Pipeline helper bodies
//! retain their existing implementation; this is not their qualification.
const em = @import("engine.zig");
const p = @import("native_agent_af_values.zig");
const af = p.af;
const functions = @import("native_node_function.zig");
const pipeline = @import("native_agent_tool_call.zig");
const c = em.c;

pub fn create(engine: *em.Engine) !c.JSValue {
    return af.createResumable(engine, "runToolCall", 2, dispatch, &.{});
}

/// Native callers enter the same actual VM function as the exported callable.
pub fn run(engine: *em.Engine, tool_call: c.JSValue, options: c.JSValue) !c.JSValue {
    const function = try create(engine);
    defer engine.freeValue(function);
    var args = [_]c.JSValue{ tool_call, options };
    return engine.checked(c.JS_Call(engine.context, function, c.pi_js_undefined(), args.len, &args));
}

fn dispatch(engine: *em.Engine, _: c.JSValue, args: []const c.JSValue, _: []const c.JSValue, state: *c.JSValue, completion: af.Completion, input: c.JSValue) anyerror!af.Action {
    var s: p.Scope = .{ .engine = engine };
    return @import("native_agent_af_completion.zig").finishAction(&s, step(&s, args, state, completion, input));
}

fn step(s: *p.Scope, args: []const c.JSValue, state: *c.JSValue, completion: af.Completion, input: c.JSValue) !af.Action {
    const engine = s.engine;
    if (completion == .rejected) {
        try p.rejected(s, state.*, input);
        return .{ .thrown = c.JS_DupValue(engine.context, input) };
    }
    if (completion == .start) {
        const owner = try p.init(s, state);
        const tool_call = if (args.len > 0) args[0] else c.pi_js_undefined();
        const options = if (args.len > 1) args[1] else c.pi_js_undefined();
        // Source destructuring evaluates these getters once and in this order.
        const assistant = try p.get(s, options, "assistantMessage");
        const context = try p.get(s, options, "context");
        const signal = try p.get(s, options, "signal");
        inline for (.{ .{ "toolCall", tool_call }, .{ "options", options }, .{ "assistant", assistant }, .{ "context", context }, .{ "signal", signal } }) |field| try s.put(owner, field[0], field[1]);
        const tools = try p.get(s, options, "tools");
        try s.put(owner, "stage", c.JS_NewInt32(engine.context, 0));
        return .{ .awaited = try pipeline.prepare(engine, context, assistant, tool_call, options, signal, tools) };
    }
    const owner = state.*;
    const stage = try p.stage(s, owner);
    const options = try s.get(owner, "options");
    if (stage == 0) {
        if (s.equal(try p.get(s, input, "kind"), try s.text("immediate"))) {
            const result = try s.object();
            try s.put(result, "toolCall", try s.get(owner, "toolCall"));
            try s.put(result, "result", try p.get(s, input, "result"));
            try s.put(result, "isError", try p.get(s, input, "isError"));
            return .{ .returned = c.JS_DupValue(engine.context, result) };
        }
        try s.put(owner, "prepared", input);
        var update = try p.get(s, options, "onUpdate");
        if (c.JS_IsNull(update) or c.JS_IsUndefined(update)) update = try s.own(try functions.createArrow(engine, "", 0, noop, &.{}));
        try s.put(owner, "stage", c.JS_NewInt32(engine.context, 1));
        return .{ .awaited = try pipeline.execute(engine, input, try s.get(owner, "signal"), update) };
    }
    if (stage != 1) return error.UnexpectedRunToolCallStage;
    // Source says return finalize(...), not return await finalize(...).
    return .{ .returned = try pipeline.finalize(engine, try s.get(owner, "context"), try s.get(owner, "assistant"), try s.get(owner, "prepared"), input, options, try s.get(owner, "signal")) };
}

fn noop(_: *em.Engine, _: c.JSValue, _: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
    return c.pi_js_undefined();
}
