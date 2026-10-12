//! Original post-run retry/compaction and pre-settlement boundary orchestration.
//! Dependencies are invoked on the live session; no missing policy is replaced.
const em = @import("engine.zig");
const sdk = @import("native_sdk.zig");
const js = @import("native_js_values.zig");
const Scope = @import("native_sdk_prompt_scope.zig").Scope;
const flow = @import("native_agent_async.zig");
const c = em.c;
const Stage = enum(c_int) { retry, compaction, boundary };

pub fn install(engine: *em.Engine, prototype: c.JSValue) !void {
    inline for (.{ "_handlePostAgentRun", "_runBeforeSettleBoundary" }, 0..) |name, index| {
        const method = try engine.checked(c.pi_js_function_magic(engine.context, dispatch, name, 0, @intCast(index)));
        defer engine.freeValue(method);
        const parent = try engine.checked(c.JS_GetAsyncFunctionPrototype(engine.context));
        defer engine.freeValue(parent);
        if (c.JS_SetPrototype(engine.context, method, parent) < 0) return js.capture(engine);
        if (c.JS_DefinePropertyValueStr(engine.context, prototype, name, c.JS_DupValue(engine.context, method), c.JS_PROP_WRITABLE | c.JS_PROP_CONFIGURABLE) < 0) return js.capture(engine);
    }
}
fn dispatch(context: ?*c.JSContext, receiver: c.JSValue, _: c_int, _: [*c]c.JSValue, magic: c_int) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    return begin(engine, receiver, magic != 0) catch |err| sdk.fail(engine, err);
}
fn begin(engine: *em.Engine, receiver: c.JSValue, boundary: bool) !c.JSValue {
    const pending = try flow.create(engine, receiver);
    defer engine.freeValue(pending.owner);
    errdefer engine.freeValue(pending.promise);
    if (boundary) {
        boundaryStart(engine, pending.owner) catch |err| try fail(engine, pending.owner, err);
    } else postStart(engine, pending.owner) catch |err| try flow.rejectError(engine, pending.owner, err);
    return pending.promise;
}
fn finish(engine: *em.Engine, owner: c.JSValue, value: c.JSValue) !void {
    try flow.settle(engine, owner, false, value);
}
fn aborted(scope: *Scope, receiver: c.JSValue) !bool {
    return scope.truthy(try scope.get(receiver, "_agentRunAbortRequested"));
}
fn cancelled(scope: *Scope, owner: c.JSValue, receiver: c.JSValue) !void {
    _ = try scope.invoke(receiver, "_finishCancelledRetry", &.{});
    try finish(scope.engine, owner, c.pi_js_bool(scope.engine.context, 0));
}
fn postStart(engine: *em.Engine, owner: c.JSValue) !void {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const receiver = try scope.get(owner, "agent");
    const message = try scope.get(receiver, "_lastAssistantMessage");
    const results = try scope.get(receiver, "_lastAssistantToolResults");
    try scope.set(receiver, "_lastAssistantMessage", c.pi_js_undefined());
    try scope.set(receiver, "_lastAssistantToolResults", try scope.array());
    if (try aborted(&scope, receiver)) return cancelled(&scope, owner, receiver);
    if (!scope.truthy(message)) return finish(engine, owner, try scope.invoke(try scope.get(receiver, "agent"), "hasQueuedMessages", &.{}));
    try scope.put(owner, "message", message);
    try scope.put(owner, "results", results);
    if (scope.truthy(try scope.invoke(receiver, "_isRetryableError", &.{message}))) {
        return flow.wait(continuation, engine, owner, try scope.invoke(receiver, "_prepareRetry", &.{message}), @intFromEnum(Stage.retry));
    }
    try afterRetry(engine, owner);
}
fn afterRetry(engine: *em.Engine, owner: c.JSValue) !void {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const receiver = try scope.get(owner, "agent");
    if (try aborted(&scope, receiver)) return cancelled(&scope, owner, receiver);
    const message = try scope.get(owner, "message");
    if (scope.equal(try scope.get(message, "stopReason"), try scope.text("error")) and try scope.positive(try scope.get(receiver, "_retryAttempt"))) {
        const emit = try scope.get(receiver, "_emit");
        const event = try scope.object();
        try scope.put(event, "type", try scope.text("auto_retry_end"));
        try scope.put(event, "success", c.pi_js_bool(engine.context, 0));
        try scope.put(event, "attempt", try scope.get(receiver, "_retryAttempt"));
        try scope.put(event, "finalError", try scope.get(message, "errorMessage"));
        _ = try scope.call(emit, receiver, &.{event});
        try scope.set(receiver, "_retryAttempt", c.JS_NewInt32(engine.context, 0));
    }
    const result = try scope.invoke(receiver, "_checkCompaction", &.{ message, c.pi_js_bool(engine.context, 1), try scope.get(owner, "results") });
    try flow.wait(continuation, engine, owner, result, @intFromEnum(Stage.compaction));
}
fn boundaryStart(engine: *em.Engine, owner: c.JSValue) !void {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const receiver = try scope.get(owner, "agent");
    const runner = try scope.get(receiver, "_extensionRunner");
    if (!scope.truthy(try scope.invoke(runner, "hasHandlers", &.{try scope.text("agent_before_settle")}))) return finish(engine, owner, try scope.invoke(try scope.get(receiver, "agent"), "hasQueuedMessages", &.{}));
    try scope.set(receiver, "_isBeforeSettle", c.pi_js_bool(engine.context, 1));
    try scope.set(receiver, "_abortDuringBeforeSettle", c.pi_js_bool(engine.context, 0));
    try scope.put(owner, "boundaryTry", c.pi_js_bool(engine.context, 1));
    const emit = try scope.get(runner, "emitBoundary");
    const event = try scope.object();
    try scope.put(event, "type", try scope.text("agent_before_settle"));
    try scope.put(event, "outcome", try scope.get(receiver, "_lastActivityOutcome"));
    var roots = [_]c.JSValue{receiver};
    const callback = try scope.own(try engine.checked(c.JS_NewCFunctionData2(engine.context, buildContext, "", 1, 0, roots.len, &roots)));
    const result = try scope.call(emit, runner, &.{ event, callback });
    try flow.wait(continuation, engine, owner, result, @intFromEnum(Stage.boundary));
}
fn buildContext(context: ?*c.JSContext, _: c.JSValue, argc: c_int, args: [*c]c.JSValue, _: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const result = scope.invoke(roots[0], "_buildBoundaryContext", &.{ if (argc > 0) args[0] else c.pi_js_undefined(), scope.text("agent_before_settle") catch |err| return sdk.fail(engine, err) }) catch |err| return sdk.fail(engine, err);
    return c.JS_DupValue(context, result);
}
fn fail(engine: *em.Engine, owner: c.JSValue, err: anyerror) !void {
    const reason = flow.reason(engine, err);
    defer engine.freeValue(reason);
    try clearBoundary(engine, owner);
    try flow.settle(engine, owner, true, reason);
}
fn clearBoundary(engine: *em.Engine, owner: c.JSValue) !void {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    if (!scope.truthy(try scope.get(owner, "boundaryTry"))) return;
    try scope.put(owner, "boundaryTry", c.pi_js_bool(engine.context, 0));
    try scope.set(try scope.get(owner, "agent"), "_isBeforeSettle", c.pi_js_bool(engine.context, 0));
}
fn continuation(engine: *em.Engine, owner: c.JSValue, value: c.JSValue, rejected: bool, magic: c_int) !void {
    const stage: Stage = @enumFromInt(magic);
    if (stage == .boundary) {
        if (rejected) {
            try clearBoundary(engine, owner);
            return flow.settle(engine, owner, true, value);
        }
        boundaryEnd(engine, owner, value) catch |err| try fail(engine, owner, err);
        return;
    }
    if (rejected) return flow.settle(engine, owner, true, value);
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const receiver = try scope.get(owner, "agent");
    if (stage == .retry) {
        if (!scope.truthy(value)) return afterRetry(engine, owner);
        if (try aborted(&scope, receiver)) _ = try scope.invoke(receiver, "_finishCancelledRetry", &.{});
        try scope.set(receiver, "_failedResponse", try scope.get(owner, "message"));
        return finish(engine, owner, c.pi_js_bool(engine.context, @intFromBool(!try aborted(&scope, receiver))));
    }
    const keep_running = !try aborted(&scope, receiver);
    if (scope.truthy(value)) return finish(engine, owner, c.pi_js_bool(engine.context, @intFromBool(keep_running)));
    if (!keep_running) return finish(engine, owner, c.pi_js_bool(engine.context, 0));
    try finish(engine, owner, try scope.invoke(try scope.get(receiver, "agent"), "hasQueuedMessages", &.{}));
}
fn boundaryEnd(engine: *em.Engine, owner: c.JSValue, result: c.JSValue) !void {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const receiver = try scope.get(owner, "agent");
    _ = try scope.invoke(receiver, "_commitBoundaryDrafts", &.{try scope.get(result, "entries")});
    _ = try scope.invoke(receiver, "_flushPendingCustomMessages", &.{});
    const final_context = try scope.invoke(receiver, "_buildBoundaryContext", &.{ try scope.array(), try scope.text("agent_before_settle") });
    var should_continue = c.pi_js_bool(engine.context, 0);
    if (!scope.truthy(try scope.get(receiver, "_abortDuringBeforeSettle"))) {
        const requested = try scope.get(result, "continue");
        should_continue = if (scope.truthy(requested)) requested else try scope.invoke(try scope.get(receiver, "agent"), "hasQueuedMessages", &.{});
        if (scope.truthy(should_continue) and !scope.truthy(try scope.get(final_context, "canContinue"))) {
            if (scope.truthy(try scope.get(result, "continue"))) _ = try scope.invoke(receiver, "_reportInvalidBoundaryContinuation", &.{try scope.text("agent_before_settle")});
            should_continue = c.pi_js_bool(engine.context, 0);
        }
    }
    try clearBoundary(engine, owner);
    try finish(engine, owner, should_continue);
}
