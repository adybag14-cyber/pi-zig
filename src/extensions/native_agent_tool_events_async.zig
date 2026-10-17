//! Actual tool-event AF helpers and synchronous result-message construction.
const p = @import("native_agent_af_values.zig");
const em = @import("engine.zig");
const c = p.c;
const af = p.af;
const nullish = @import("native_sdk_prompt_scope.zig").nullish;
pub fn create(engine: *em.Engine, comptime is_message: bool) !c.JSValue {
    const Adapter = struct {
        fn call(host: *em.Engine, _: c.JSValue, args: []const c.JSValue, _: []const c.JSValue, state: *c.JSValue, completion: af.Completion, input: c.JSValue) anyerror!af.Action { return run(host, is_message, args, state, completion, input) catch |err| p.failure(host, err); }
    };
    return af.createResumable(engine, if (is_message) "emitToolResultMessage" else "emitToolExecutionEnd", 2, Adapter.call, &.{});
}
fn run(engine: *em.Engine, comptime is_message: bool, args: []const c.JSValue, state: *c.JSValue, completion: af.Completion, input: c.JSValue) !af.Action {
    var s: p.Scope = .{ .engine = engine }; defer s.deinit();
    if (completion == .rejected) { try p.rejected(&s, state.*, input); return .{ .thrown = c.JS_DupValue(engine.context, input) }; }
    if (completion == .fulfilled) {
        if (is_message and try p.stage(&s, state.*) == 0) return p.wait(&s, state.*, try s.get(state.*, "emit"), c.pi_js_undefined(), &.{try messageEvent(&s, "message_end", try s.get(state.*, "message"))}, 1);
        return .{ .returned = c.pi_js_undefined() };
    }
    const owner = try p.init(&s, state); const value = if (args.len > 0) args[0] else c.pi_js_undefined(); const emit = if (args.len > 1) args[1] else c.pi_js_undefined();
    try s.put(owner, "message", value); try s.put(owner, "emit", emit);
    return p.wait(&s, owner, emit, c.pi_js_undefined(), &.{if (is_message) try messageEvent(&s, "message_start", value) else try endEvent(&s, value)}, 0);
}
pub fn event(s: *p.Scope, kind: []const u8) !c.JSValue { const value = try s.object(); try s.put(value, "type", try s.text(kind)); return value; }
pub fn messageEvent(s: *p.Scope, kind: []const u8, message: c.JSValue) !c.JSValue { const value = try event(s, kind); try s.put(value, "message", message); return value; }
pub fn startEvent(s: *p.Scope, call: c.JSValue) !c.JSValue { const value = try event(s, "tool_execution_start"); try s.put(value, "toolCallId", try p.get(s, call, "id")); try s.put(value, "toolName", try p.get(s, call, "name")); try s.put(value, "args", try p.get(s, call, "arguments")); return value; }
fn duration(s: *p.Scope, value: c.JSValue, finalized: c.JSValue) !void { if (!c.JS_IsUndefined(try p.get(s, finalized, "durationMs"))) try s.put(value, "durationMs", try p.get(s, finalized, "durationMs")); }
pub fn endEvent(s: *p.Scope, finalized: c.JSValue) !c.JSValue {
    const value = try event(s, "tool_execution_end");
    try s.put(value, "toolCallId", try p.get(s, try p.get(s, finalized, "toolCall"), "id")); try s.put(value, "toolName", try p.get(s, try p.get(s, finalized, "toolCall"), "name"));
    try s.put(value, "result", try p.get(s, finalized, "result")); try s.put(value, "isError", try p.get(s, finalized, "isError")); try duration(s, value, finalized); return value;
}
pub fn resultMessage(s: *p.Scope, finalized: c.JSValue) !c.JSValue {
    const value = try s.object(); try s.put(value, "role", try s.text("toolResult"));
    try s.put(value, "toolCallId", try p.get(s, try p.get(s, finalized, "toolCall"), "id")); try s.put(value, "toolName", try p.get(s, try p.get(s, finalized, "toolCall"), "name"));
    const content = try p.get(s, try p.get(s, finalized, "result"), "content"); try s.put(value, "content", if (nullish(content)) try s.array() else content);
    inline for (.{ "details", "usage" }) |name| try s.put(value, name, try p.get(s, try p.get(s, finalized, "result"), name));
    try s.put(value, "isError", try p.get(s, finalized, "isError")); try duration(s, value, finalized);
    try s.put(value, "timestamp", try p.invoke(s, try p.global(s, "Date"), "now", &.{})); return value;
}
