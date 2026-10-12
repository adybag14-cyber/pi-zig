//! Actual Agent.handleRunFailure message construction and four awaited events.
const em = @import("engine.zig");
const sdk = @import("native_sdk.zig");
const js = @import("native_js_values.zig");
const Scope = @import("native_sdk_prompt_scope.zig").Scope;
const flow = @import("native_agent_async.zig");
const c = em.c;

pub fn run(engine: *em.Engine, agent: c.JSValue, error_value: c.JSValue, aborted: c.JSValue, shared_usage: c.JSValue) !c.JSValue {
    const pending = try flow.create(engine, agent);
    defer engine.freeValue(pending.owner);
    errdefer engine.freeValue(pending.promise);
    begin(engine, pending.owner, error_value, aborted, shared_usage) catch |err| try flow.rejectError(engine, pending.owner, err);
    return pending.promise;
}

fn begin(engine: *em.Engine, owner: c.JSValue, error_value: c.JSValue, aborted: c.JSValue, shared_usage: c.JSValue) !void {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const agent = try scope.get(owner, "agent");
    const message = try scope.object();
    try scope.put(message, "role", try scope.text("assistant"));
    const content = try scope.array();
    const text = try scope.object();
    try scope.put(text, "type", try scope.text("text"));
    try scope.put(text, "text", try scope.text(""));
    try scope.index(content, 0, text);
    try scope.put(message, "content", content);
    inline for (.{ "api", "provider", "id" }, .{ "api", "provider", "model" }) |source, target| try scope.put(message, target, try scope.get(try scope.get(try scope.get(agent, "_state"), "model"), source));
    try scope.put(message, "usage", shared_usage);
    try scope.put(message, "stopReason", try scope.text(if (scope.truthy(aborted)) "aborted" else "error"));
    const error_constructor = try scope.global("Error");
    const instance = c.JS_IsInstanceOf(engine.context, error_value, error_constructor);
    if (instance < 0) return js.capture(engine);
    const error_message = if (instance != 0) try scope.get(error_value, "message") else try scope.call(try scope.global("String"), c.pi_js_undefined(), &.{error_value});
    try scope.put(message, "errorMessage", error_message);
    try scope.put(message, "timestamp", try scope.invoke(try scope.global("Date"), "now", &.{}));
    try scope.put(owner, "message", message);
    try advance(engine, owner, 0);
}

fn advance(engine: *em.Engine, owner: c.JSValue, stage: c_int) !void {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const agent = try scope.get(owner, "agent");
    const handler = try scope.get(agent, "processEvents");
    const event = try scope.object();
    try scope.put(event, "type", try scope.text(switch (stage) {
        0 => "message_start",
        1 => "message_end",
        2 => "turn_end",
        else => "agent_end",
    }));
    const message = try scope.get(owner, "message");
    if (stage == 3) {
        const messages = try scope.array();
        try scope.index(messages, 0, message);
        try scope.put(event, "messages", messages);
    } else {
        try scope.put(event, "message", message);
        if (stage == 2) try scope.put(event, "toolResults", try scope.array());
    }
    const pending = try scope.call(handler, agent, &.{event});
    try flow.wait(continuation, engine, owner, pending, stage);
}

fn continuation(engine: *em.Engine, owner: c.JSValue, value: c.JSValue, rejected: bool, stage: c_int) !void {
    if (rejected) return flow.settle(engine, owner, true, value);
    if (stage < 3) return advance(engine, owner, stage + 1);
    return flow.settle(engine, owner, false, c.pi_js_undefined());
}
