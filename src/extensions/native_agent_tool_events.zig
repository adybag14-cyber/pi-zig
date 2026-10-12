//! Actual nested async helpers for tool-end and tool-result emissions.
const em = @import("engine.zig");
const sdk = @import("native_sdk.zig");
const js = @import("native_js_values.zig");
const temp = @import("native_sdk_prompt_scope.zig");
const Scope = temp.Scope;
const flow = @import("native_agent_async.zig");
const c = em.c;
pub fn end(engine: *em.Engine, finalized: c.JSValue, emit: c.JSValue) !c.JSValue {
    return begin(engine, finalized, emit, false);
}
pub fn message(engine: *em.Engine, value: c.JSValue, emit: c.JSValue) !c.JSValue {
    return begin(engine, value, emit, true);
}
fn begin(engine: *em.Engine, value: c.JSValue, emit: c.JSValue, is_message: bool) !c.JSValue {
    const pending = try flow.create(engine, c.pi_js_undefined());
    defer engine.freeValue(pending.owner);
    errdefer engine.freeValue(pending.promise);
    start(engine, pending.owner, value, emit, is_message) catch |err| try flow.rejectError(engine, pending.owner, err);
    return pending.promise;
}
fn start(engine: *em.Engine, owner: c.JSValue, value: c.JSValue, emit: c.JSValue, is_message: bool) !void {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    try scope.put(owner, "value", value);
    try scope.put(owner, "emit", emit);
    const event = if (is_message) event: {
        const result = try scope.object();
        try scope.put(result, "type", try scope.text("message_start"));
        try scope.put(result, "message", value);
        break :event result;
    } else try scope.own(try @import("native_agent_tool_call.zig").endEvent(engine, value));
    const returned = try scope.call(emit, c.pi_js_undefined(), &.{event});
    try flow.wait(continueAwait, engine, owner, returned, if (is_message) 1 else 0);
}
fn continueAwait(engine: *em.Engine, owner: c.JSValue, value: c.JSValue, rejected: bool, stage: c_int) !void {
    if (rejected) return flow.settle(engine, owner, true, value);
    if (stage == 0) return flow.settle(engine, owner, false, c.pi_js_undefined());
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const event = try scope.object();
    try scope.put(event, "type", try scope.text("message_end"));
    try scope.put(event, "message", try scope.get(owner, "value"));
    const returned = try scope.call(try scope.get(owner, "emit"), c.pi_js_undefined(), &.{event});
    try flow.wait(continueAwait, engine, owner, returned, 0);
}
