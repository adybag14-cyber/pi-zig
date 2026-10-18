//! Source executeToolCallsParallel's per-tool async arrow. Each Source Await
//! is an actual native AF suspension; no promise-pipeline wrapper is used.
const em = @import("engine.zig");
const p = @import("native_agent_af_values.zig");
const completion = @import("native_agent_af_completion.zig");
const functions = @import("native_node_function.zig");
const pipeline = @import("native_agent_tool_call.zig");
const events = @import("native_agent_tool_events.zig");
const af = p.af;
const c = p.c;
const Stage = enum(i32) { aborted_end, executed, finalized, ended };

pub fn create(engine: *em.Engine, context: c.JSValue, assistant: c.JSValue, prepared: c.JSValue, config: c.JSValue, signal: c.JSValue, emit: c.JSValue, tool_call: c.JSValue) !c.JSValue {
    return af.createResumableArrow(engine, "", 0, invoke, &.{ context, assistant, prepared, config, signal, emit, tool_call }, c.pi_js_undefined());
}
fn invoke(engine: *em.Engine, _: c.JSValue, _: []const c.JSValue, roots: []const c.JSValue, state: *c.JSValue, resumed: af.Completion, input: c.JSValue) anyerror!af.Action {
    var s: p.Scope = .{ .engine = engine };
    return completion.finishAction(&s, step(&s, roots, state, resumed, input));
}
fn step(s: *p.Scope, roots: []const c.JSValue, state: *c.JSValue, resumed: af.Completion, input: c.JSValue) !af.Action {
    const engine = s.engine;
    if (resumed == .rejected) {
        try p.rejected(s, state.*, input);
        return .{ .thrown = c.JS_DupValue(engine.context, input) };
    }
    if (resumed == .start) {
        const owner = try p.init(s, state);
        if (!nullish(roots[4]) and s.truthy(try p.get(s, roots[4], "aborted"))) {
            const finalized = try s.object();
            try s.put(finalized, "toolCall", roots[6]);
            try s.put(finalized, "result", try s.own(try pipeline.errorResult(engine, try s.text("Operation aborted"))));
            try s.put(finalized, "isError", c.pi_js_bool(engine.context, 1));
            try s.put(owner, "finalized", finalized);
            try setStage(s, owner, .aborted_end);
            return .{ .awaited = try events.end(engine, finalized, roots[5]) };
        }
        const update = try s.own(try functions.createArrow(engine, "", 1, updateCall, &.{ roots[6], roots[5] }));
        try setStage(s, owner, .executed);
        return .{ .awaited = try pipeline.execute(engine, roots[2], roots[4], update) };
    }
    const owner = state.*;
    const stage: Stage = @enumFromInt(try p.stage(s, owner));
    return switch (stage) {
        .aborted_end, .ended => .{ .returned = c.JS_DupValue(engine.context, try s.get(owner, "finalized")) },
        .executed => blk: {
            try setStage(s, owner, .finalized);
            break :blk .{ .awaited = try pipeline.finalize(engine, roots[0], roots[1], roots[2], input, roots[3], roots[4]) };
        },
        .finalized => blk: {
            try s.put(owner, "finalized", input);
            try setStage(s, owner, .ended);
            break :blk .{ .awaited = try events.end(engine, input, roots[5]) };
        },
    };
}
fn setStage(s: *p.Scope, owner: c.JSValue, stage: Stage) !void { try s.put(owner, "stage", c.JS_NewInt32(s.engine.context, @intFromEnum(stage))); }
fn nullish(value: c.JSValue) bool { return c.JS_IsNull(value) or c.JS_IsUndefined(value); }
fn updateCall(engine: *em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    var s: p.Scope = .{ .engine = engine };
    return completion.finishValue(&s, updateValue(&s, args, roots));
}
fn updateValue(s: *p.Scope, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    const event = try s.object();
    try s.put(event, "type", try s.text("tool_execution_update"));
    try s.put(event, "toolCallId", try p.get(s, roots[0], "id"));
    try s.put(event, "toolName", try p.get(s, roots[0], "name"));
    try s.put(event, "args", try p.get(s, roots[0], "arguments"));
    try s.put(event, "partialResult", if (args.len > 0) args[0] else c.pi_js_undefined());
    return c.JS_DupValue(s.engine.context, try p.call(s, roots[1], c.pi_js_undefined(), &.{event}));
}
