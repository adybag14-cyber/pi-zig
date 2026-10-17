//! Actual handleRunFailure message and four direct Source Awaits.
const p = @import("native_agent_af_values.zig");
const em = @import("engine.zig");
const c = p.c;
const af = p.af;
pub fn create(engine: *em.Engine, actual_empty_usage: c.JSValue) !c.JSValue { return af.createResumable(engine, "handleRunFailure", 2, invoke, &.{actual_empty_usage}); }
fn invoke(engine: *em.Engine, agent: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue, state: *c.JSValue, completion: af.Completion, input: c.JSValue) anyerror!af.Action {
    return run(engine, agent, args, roots[0], state, completion, input) catch |err| p.failure(engine, err);
}
fn run(engine: *em.Engine, agent: c.JSValue, args: []const c.JSValue, usage: c.JSValue, state: *c.JSValue, completion: af.Completion, input: c.JSValue) !af.Action {
    var s: p.Scope = .{ .engine = engine }; defer s.deinit();
    if (completion == .rejected) { try p.rejected(&s, state.*, input); return .{ .thrown = c.JS_DupValue(engine.context, input) }; }
    if (completion == .fulfilled) {
        const stage = try p.stage(&s, state.*);
        if (stage < 3) return advance(&s, agent, state.*, stage + 1);
        return .{ .returned = c.pi_js_undefined() };
    }
    const owner = try p.init(&s, state);
    const error_value = if (args.len > 0) args[0] else c.pi_js_undefined();
    const aborted = if (args.len > 1) args[1] else c.pi_js_undefined();
    const message = try s.object();
    try s.put(message, "role", try s.text("assistant"));
    const content = try s.array(); const text = try s.object();
    try s.put(text, "type", try s.text("text")); try s.put(text, "text", try s.text(""));
    try s.index(content, 0, text); try s.put(message, "content", content);
    inline for (.{ "api", "provider", "id" }, .{ "api", "provider", "model" }) |source, target| try s.put(message, target, try p.get(&s, try p.get(&s, try p.get(&s, agent, "_state"), "model"), source));
    try s.put(message, "usage", usage);
    try s.put(message, "stopReason", try s.text(if (s.truthy(aborted)) "aborted" else "error"));
    const error_constructor = try p.global(&s, "Error");
    const generation = engine.native_allocation_generation;
    const instance = c.JS_IsInstanceOf(engine.context, error_value, error_constructor);
    if (instance < 0) { _ = try p.guard(engine, generation, @import("native_js_values.zig").capture(engine)); unreachable; }
    const error_message = if (instance != 0) try p.get(&s, error_value, "message") else try p.call(&s, try p.global(&s, "String"), c.pi_js_undefined(), &.{error_value});
    try s.put(message, "errorMessage", error_message);
    try s.put(message, "timestamp", try p.invoke(&s, try p.global(&s, "Date"), "now", &.{}));
    try s.put(owner, "failureMessage", message);
    return advance(&s, agent, owner, 0);
}
fn advance(s: *p.Scope, agent: c.JSValue, owner: c.JSValue, stage: i32) !af.Action {
    const handler = try p.get(s, agent, "processEvents");
    const event = try s.object();
    try s.put(event, "type", try s.text(switch (stage) { 0 => "message_start", 1 => "message_end", 2 => "turn_end", else => "agent_end" }));
    const message = try s.get(owner, "failureMessage");
    if (stage == 3) { const messages = try s.array(); try s.index(messages, 0, message); try s.put(event, "messages", messages); }
    else { try s.put(event, "message", message); if (stage == 2) try s.put(event, "toolResults", try s.array()); }
    return p.wait(s, owner, handler, agent, &.{event}, stage);
}
