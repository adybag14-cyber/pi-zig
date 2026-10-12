//! AgentLoop's real tool preparation, execution and after-hook pipeline.
const em = @import("engine.zig");
const sdk = @import("native_sdk.zig");
const js = @import("native_js_values.zig");
const temp = @import("native_sdk_prompt_scope.zig");
const Scope = temp.Scope;
const flow = @import("native_agent_async.zig");
const c = em.c;

pub fn errorResult(engine: *em.Engine, message: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const result = try scope.object();
    const content = try scope.array();
    const text = try scope.object();
    try scope.put(text, "type", try scope.text("text"));
    try scope.put(text, "text", message);
    try scope.index(content, 0, text);
    try scope.put(result, "content", content);
    try scope.put(result, "details", try scope.object());
    return c.JS_DupValue(engine.context, result);
}
fn errorMessage(scope: *Scope, error_value: c.JSValue) !c.JSValue {
    const constructor = try scope.global("Error");
    const instance = c.JS_IsInstanceOf(scope.engine.context, error_value, constructor);
    if (instance < 0) return js.capture(scope.engine);
    if (instance != 0) return scope.get(error_value, "message");
    return scope.call(try scope.global("String"), c.pi_js_undefined(), &.{error_value});
}
fn aborted(scope: *Scope, signal: c.JSValue) !bool {
    return !temp.nullish(signal) and scope.truthy(try scope.get(signal, "aborted"));
}
fn immediate(scope: *Scope, result: c.JSValue) !c.JSValue {
    const value = try scope.object();
    try scope.put(value, "kind", try scope.text("immediate"));
    try scope.put(value, "result", result);
    try scope.put(value, "isError", c.pi_js_bool(scope.engine.context, 1));
    return value;
}
fn immediateText(scope: *Scope, owner: c.JSValue, text: []const u8) !void {
    const result = try scope.own(try errorResult(scope.engine, try scope.text(text)));
    try flow.settle(scope.engine, owner, false, try immediate(scope, result));
}
pub fn prepare(engine: *em.Engine, context: c.JSValue, assistant: c.JSValue, call: c.JSValue, config: c.JSValue, signal: c.JSValue, explicit_tools: ?c.JSValue) !c.JSValue {
    const pending = try flow.create(engine, c.pi_js_undefined());
    defer engine.freeValue(pending.owner);
    errdefer engine.freeValue(pending.promise);
    beginPrepare(engine, pending.owner, context, assistant, call, config, signal, explicit_tools) catch |err| try flow.rejectError(engine, pending.owner, err);
    return pending.promise;
}
fn findTool(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    return matches(engine, if (argc > 0) argv[0] else c.pi_js_undefined(), roots[0]) catch |err| sdk.fail(engine, err);
}
fn matches(engine: *em.Engine, tool: c.JSValue, call: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const name = try scope.get(tool, "name");
    return c.pi_js_bool(engine.context, @intFromBool(scope.equal(name, try scope.get(call, "name"))));
}
fn beginPrepare(engine: *em.Engine, owner: c.JSValue, context: c.JSValue, assistant: c.JSValue, call: c.JSValue, config: c.JSValue, signal: c.JSValue, explicit_tools: ?c.JSValue) !void {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    inline for (.{ .{ "context", context }, .{ "assistant", assistant }, .{ "call", call }, .{ "config", config }, .{ "signal", signal } }) |field| try scope.put(owner, field[0], field[1]);
    const supplied = explicit_tools orelse c.pi_js_undefined();
    const tools = if (c.JS_IsUndefined(supplied)) default: {
        const live = try scope.get(context, "tools");
        break :default if (temp.nullish(live)) try scope.array() else live;
    } else supplied;
    const find = try scope.get(tools, "find");
    var roots = [_]c.JSValue{call};
    const predicate = try scope.own(try engine.checked(c.JS_NewCFunctionData2(engine.context, findTool, "", 1, 0, roots.len, &roots)));
    const tool = try scope.call(find, tools, &.{predicate});
    if (!scope.truthy(tool)) {
        const name = try scope.stringify(try scope.get(call, "name"));
        const text = try scope.concat(try scope.concat(try scope.text("Tool "), name), try scope.text(" not found"));
        const result = try scope.own(try errorResult(engine, text));
        return flow.settle(engine, owner, false, try immediate(&scope, result));
    }
    try scope.put(owner, "tool", tool);
    prepareBody(engine, owner) catch |err| try prepareError(engine, owner, err);
}
fn prepareBody(engine: *em.Engine, owner: c.JSValue) !void {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const tool = try scope.get(owner, "tool");
    const call = try scope.get(owner, "call");
    var prepared_call = call;
    if (scope.truthy(try scope.get(tool, "prepareArguments"))) {
        const prepare_args = try scope.get(tool, "prepareArguments");
        const arguments = try scope.call(prepare_args, tool, &.{try scope.get(call, "arguments")});
        if (!scope.equal(arguments, try scope.get(call, "arguments"))) {
            prepared_call = try scope.own(try js.spread(engine, call));
            try scope.put(prepared_call, "arguments", arguments);
        }
    }
    const validated = try scope.own(try @import("native_tool_arguments.zig").validateArguments(engine, tool, prepared_call));
    try scope.put(owner, "args", validated);
    const config = try scope.get(owner, "config");
    if (scope.truthy(try scope.get(config, "beforeToolCall"))) {
        const hook = try scope.get(config, "beforeToolCall");
        const request = try scope.object();
        try scope.put(request, "assistantMessage", try scope.get(owner, "assistant"));
        try scope.put(request, "toolCall", call);
        try scope.put(request, "args", validated);
        try scope.put(request, "context", try scope.get(owner, "context"));
        const value = try scope.call(hook, config, &.{ request, try scope.get(owner, "signal") });
        return flow.wait(preparedHook, engine, owner, value, 0);
    }
    try finishPrepare(engine, owner);
}
fn prepareError(engine: *em.Engine, owner: c.JSValue, err: anyerror) !void {
    const raw = flow.reason(engine, err);
    defer engine.freeValue(raw);
    try prepareRawError(engine, owner, raw);
}
fn prepareRawError(engine: *em.Engine, owner: c.JSValue, raw: c.JSValue) !void {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const result = try scope.own(try errorResult(engine, try errorMessage(&scope, raw)));
    try flow.settle(engine, owner, false, try immediate(&scope, result));
}
fn preparedHook(engine: *em.Engine, owner: c.JSValue, value: c.JSValue, rejected: bool, _: c_int) !void {
    if (rejected) return prepareRawError(engine, owner, value);
    afterBefore(engine, owner, value) catch |err| try prepareError(engine, owner, err);
}
fn afterBefore(engine: *em.Engine, owner: c.JSValue, value: c.JSValue) !void {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    if (try aborted(&scope, try scope.get(owner, "signal"))) return immediateText(&scope, owner, "Operation aborted");
    if (!temp.nullish(value) and scope.truthy(try scope.get(value, "block"))) {
        const reason = try scope.get(value, "reason");
        const result = try scope.own(try errorResult(engine, if (scope.truthy(reason)) reason else try scope.text("Tool execution was blocked")));
        if (scope.equal(try scope.get(value, "terminate"), c.pi_js_bool(engine.context, 1))) try scope.set(result, "terminate", c.pi_js_bool(engine.context, 1));
        return flow.settle(engine, owner, false, try immediate(&scope, result));
    }
    try finishPrepare(engine, owner);
}
fn finishPrepare(engine: *em.Engine, owner: c.JSValue) !void {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    if (try aborted(&scope, try scope.get(owner, "signal"))) return immediateText(&scope, owner, "Operation aborted");
    const result = try scope.object();
    try scope.put(result, "kind", try scope.text("prepared"));
    inline for (.{ .{ "toolCall", "call" }, .{ "tool", "tool" }, .{ "args", "args" } }) |field| try scope.put(result, field[0], try scope.get(owner, field[1]));
    try flow.settle(engine, owner, false, result);
}

pub fn execute(engine: *em.Engine, prepared: c.JSValue, signal: c.JSValue, update: c.JSValue) !c.JSValue {
    const pending = try flow.create(engine, c.pi_js_undefined());
    defer engine.freeValue(pending.owner);
    errdefer engine.freeValue(pending.promise);
    beginExecution(engine, pending.owner, prepared, signal, update) catch |err| try flow.rejectError(engine, pending.owner, err);
    return pending.promise;
}
fn beginExecution(engine: *em.Engine, owner: c.JSValue, prepared: c.JSValue, signal: c.JSValue, update: c.JSValue) !void {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    inline for (.{ .{ "prepared", prepared }, .{ "signal", signal }, .{ "update", update } }) |field| try scope.put(owner, field[0], field[1]);
    try scope.put(owner, "updates", try scope.array());
    try scope.put(owner, "accepting", c.pi_js_bool(engine.context, 1));
    try scope.put(owner, "started", try scope.invoke(try scope.global("performance"), "now", &.{}));
    executionBody(engine, owner) catch |err| try executionError(engine, owner, err);
}
fn updateCall(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    return updateValue(engine, roots[0], if (argc > 0) argv[0] else c.pi_js_undefined()) catch |err| sdk.fail(engine, err);
}
fn updateValue(engine: *em.Engine, owner: c.JSValue, value: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    if (!scope.truthy(try scope.get(owner, "accepting"))) return c.pi_js_undefined();
    const updates = try scope.get(owner, "updates");
    const push = try scope.get(updates, "push");
    const promise = try scope.global("Promise");
    const resolve = try scope.get(promise, "resolve");
    const returned = try scope.call(try scope.get(owner, "update"), c.pi_js_undefined(), &.{value});
    _ = try scope.call(push, updates, &.{try scope.call(resolve, promise, &.{returned})});
    return c.pi_js_undefined();
}
fn executionBody(engine: *em.Engine, owner: c.JSValue) !void {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const prepared = try scope.get(owner, "prepared");
    const tool = try scope.get(prepared, "tool");
    const method = try scope.get(tool, "execute");
    const id = try scope.get(try scope.get(prepared, "toolCall"), "id");
    const args = try scope.get(prepared, "args");
    const signal = try scope.get(owner, "signal");
    var roots = [_]c.JSValue{owner};
    const callback = try scope.own(try engine.checked(c.JS_NewCFunctionData2(engine.context, updateCall, "", 1, 0, roots.len, &roots)));
    const result = try scope.call(method, tool, &.{ id, args, signal, callback });
    try flow.wait(executed, engine, owner, result, 0);
}
fn elapsed(scope: *Scope, owner: c.JSValue) !c.JSValue {
    const math = try scope.global("Math");
    const round = try scope.get(math, "round");
    const now = try scope.invoke(try scope.global("performance"), "now", &.{});
    const duration = try scope.own(try scope.engine.checked(c.JS_PiBinaryOperator(scope.engine.context, 1, now, try scope.get(owner, "started"))));
    return scope.call(round, math, &.{duration});
}
fn executed(engine: *em.Engine, owner: c.JSValue, value: c.JSValue, rejected: bool, _: c_int) !void {
    if (rejected) return executionRawError(engine, owner, value);
    executionSuccess(engine, owner, value) catch |err| try executionError(engine, owner, err);
}
fn waitUpdates(engine: *em.Engine, owner: c.JSValue, caught: bool) !void {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const promise = try scope.global("Promise");
    const all = try scope.get(promise, "all");
    const updates = try scope.get(owner, "updates");
    try flow.wait(updatesSettled, engine, owner, try scope.call(all, promise, &.{updates}), @intFromBool(caught));
}
fn executionSuccess(engine: *em.Engine, owner: c.JSValue, value: c.JSValue) !void {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    try scope.put(owner, "duration", try elapsed(&scope, owner));
    try scope.put(owner, "accepting", c.pi_js_bool(engine.context, 0));
    try scope.put(owner, "result", value);
    try waitUpdates(engine, owner, false);
}
fn executionError(engine: *em.Engine, owner: c.JSValue, err: anyerror) !void {
    const value = flow.reason(engine, err);
    defer engine.freeValue(value);
    try executionRawError(engine, owner, value);
}
fn executionRawError(engine: *em.Engine, owner: c.JSValue, value: c.JSValue) !void {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    // The catch's elapsed/Promise.all errors escape through the actual finally.
    defer sdk.put(engine, owner, "accepting", c.pi_js_bool(engine.context, 0)) catch {};
    try scope.put(owner, "duration", try elapsed(&scope, owner));
    try scope.put(owner, "accepting", c.pi_js_bool(engine.context, 0));
    try scope.put(owner, "caught", value);
    try waitUpdates(engine, owner, true);
}
fn updatesSettled(engine: *em.Engine, owner: c.JSValue, value: c.JSValue, rejected: bool, caught: c_int) !void {
    updatesSettledBody(engine, owner, value, rejected, caught) catch |err| {
        if (caught != 0) return flow.rejectError(engine, owner, err);
        return executionError(engine, owner, err);
    };
}
fn updatesSettledBody(engine: *em.Engine, owner: c.JSValue, value: c.JSValue, rejected: bool, caught: c_int) !void {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    defer sdk.put(engine, owner, "accepting", c.pi_js_bool(engine.context, 0)) catch {};
    if (rejected) {
        if (caught != 0) return flow.settle(engine, owner, true, value);
        return executionRawError(engine, owner, value);
    }
    const outcome = try scope.object();
    if (caught != 0) {
        const result = try scope.own(try errorResult(engine, try errorMessage(&scope, try scope.get(owner, "caught"))));
        try scope.put(outcome, "result", result);
        try scope.put(outcome, "isError", c.pi_js_bool(engine.context, 1));
    } else {
        const result = try scope.get(owner, "result");
        try scope.put(outcome, "result", result);
        try scope.put(outcome, "isError", c.pi_js_bool(engine.context, @intFromBool(scope.equal(try scope.get(result, "isError"), c.pi_js_bool(engine.context, 1)))));
    }
    try scope.put(outcome, "durationMs", try scope.get(owner, "duration"));
    try flow.settle(engine, owner, false, outcome);
}

pub fn finalize(engine: *em.Engine, context: c.JSValue, assistant: c.JSValue, prepared: c.JSValue, executed_value: c.JSValue, config: c.JSValue, signal: c.JSValue) !c.JSValue {
    const pending = try flow.create(engine, c.pi_js_undefined());
    defer engine.freeValue(pending.owner);
    errdefer engine.freeValue(pending.promise);
    beginFinalize(engine, pending.owner, context, assistant, prepared, executed_value, config, signal) catch |err| try flow.rejectError(engine, pending.owner, err);
    return pending.promise;
}
fn beginFinalize(engine: *em.Engine, owner: c.JSValue, context: c.JSValue, assistant: c.JSValue, prepared: c.JSValue, executed_value: c.JSValue, config: c.JSValue, signal: c.JSValue) !void {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    inline for (.{ .{ "context", context }, .{ "assistant", assistant }, .{ "prepared", prepared }, .{ "executed", executed_value }, .{ "config", config }, .{ "signal", signal } }) |field| try scope.put(owner, field[0], field[1]);
    try scope.put(owner, "result", try scope.get(executed_value, "result"));
    try scope.put(owner, "isError", try scope.get(executed_value, "isError"));
    // Source's initial hook-presence getter is outside the try block.
    if (!scope.truthy(try scope.get(config, "afterToolCall"))) return finishFinalize(engine, owner);
    finalizeBody(engine, owner) catch |err| try finalizeError(engine, owner, err);
}
fn finalizeBody(engine: *em.Engine, owner: c.JSValue) !void {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const config = try scope.get(owner, "config");
    const hook = try scope.get(config, "afterToolCall");
    const request = try scope.object();
    const prepared = try scope.get(owner, "prepared");
    try scope.put(request, "assistantMessage", try scope.get(owner, "assistant"));
    try scope.put(request, "toolCall", try scope.get(prepared, "toolCall"));
    try scope.put(request, "args", try scope.get(prepared, "args"));
    try scope.put(request, "result", try scope.get(owner, "result"));
    try scope.put(request, "isError", try scope.get(owner, "isError"));
    try scope.put(request, "context", try scope.get(owner, "context"));
    const pending = try scope.call(hook, config, &.{ request, try scope.get(owner, "signal") });
    try flow.wait(afterFinalized, engine, owner, pending, 0);
}
fn finalizeError(engine: *em.Engine, owner: c.JSValue, err: anyerror) !void {
    const value = flow.reason(engine, err);
    defer engine.freeValue(value);
    try finalizeRawError(engine, owner, value);
}
fn finalizeRawError(engine: *em.Engine, owner: c.JSValue, value: c.JSValue) !void {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    try scope.put(owner, "result", try scope.own(try errorResult(engine, try errorMessage(&scope, value))));
    try scope.put(owner, "isError", c.pi_js_bool(engine.context, 1));
    try finishFinalize(engine, owner);
}
fn afterFinalized(engine: *em.Engine, owner: c.JSValue, value: c.JSValue, rejected: bool, _: c_int) !void {
    if (rejected) return finalizeRawError(engine, owner, value);
    applyAfter(engine, owner, value) catch |err| return finalizeError(engine, owner, err);
    try finishFinalize(engine, owner);
}
fn applyAfter(engine: *em.Engine, owner: c.JSValue, value: c.JSValue) !void {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    if (scope.truthy(value)) {
        const prior = try scope.get(owner, "result");
        var structured = try scope.get(value, "structuredContent");
        if (temp.nullish(structured)) structured = if (scope.truthy(try scope.get(value, "content"))) c.pi_js_undefined() else try scope.get(prior, "structuredContent");
        const result = try scope.own(try js.spread(engine, prior));
        inline for (.{ "content", "details", "usage", "terminate" }) |field| {
            const replacement = try scope.get(value, field);
            try scope.put(result, field, if (temp.nullish(replacement)) try scope.get(prior, field) else replacement);
        }
        try scope.put(owner, "result", result);
        if (c.JS_IsUndefined(structured)) {
            const atom = c.JS_NewAtom(engine.context, "structuredContent");
            if (atom == c.JS_ATOM_NULL) return error.OutOfMemory;
            defer c.JS_FreeAtom(engine.context, atom);
            if (c.JS_DeleteProperty(engine.context, result, atom, c.JS_PROP_THROW) < 0) return js.capture(engine);
        } else try scope.set(result, "structuredContent", structured);
        const is_error = try scope.get(value, "isError");
        if (!temp.nullish(is_error)) try scope.put(owner, "isError", is_error);
    }
}
fn finishFinalize(engine: *em.Engine, owner: c.JSValue) !void {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const result = try scope.object();
    try scope.put(result, "toolCall", try scope.get(try scope.get(owner, "prepared"), "toolCall"));
    try scope.put(result, "result", try scope.get(owner, "result"));
    try scope.put(result, "isError", try scope.get(owner, "isError"));
    try scope.put(result, "durationMs", try scope.get(try scope.get(owner, "executed"), "durationMs"));
    try flow.settle(engine, owner, false, result);
}
pub fn toolResultMessage(engine: *em.Engine, finalized: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const message = try scope.object();
    try scope.put(message, "role", try scope.text("toolResult"));
    try scope.put(message, "toolCallId", try scope.get(try scope.get(finalized, "toolCall"), "id"));
    try scope.put(message, "toolName", try scope.get(try scope.get(finalized, "toolCall"), "name"));
    const content = try scope.get(try scope.get(finalized, "result"), "content");
    try scope.put(message, "content", if (temp.nullish(content)) try scope.array() else content);
    inline for (.{ "details", "usage" }) |field| try scope.put(message, field, try scope.get(try scope.get(finalized, "result"), field));
    try scope.put(message, "isError", try scope.get(finalized, "isError"));
    if (!c.JS_IsUndefined(try scope.get(finalized, "durationMs"))) try scope.put(message, "durationMs", try scope.get(finalized, "durationMs"));
    try scope.put(message, "timestamp", try scope.invoke(try scope.global("Date"), "now", &.{}));
    return c.JS_DupValue(engine.context, message);
}
pub fn endEvent(engine: *em.Engine, finalized: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const event = try scope.object();
    try scope.put(event, "type", try scope.text("tool_execution_end"));
    try scope.put(event, "toolCallId", try scope.get(try scope.get(finalized, "toolCall"), "id"));
    try scope.put(event, "toolName", try scope.get(try scope.get(finalized, "toolCall"), "name"));
    try scope.put(event, "result", try scope.get(finalized, "result"));
    try scope.put(event, "isError", try scope.get(finalized, "isError"));
    if (!c.JS_IsUndefined(try scope.get(finalized, "durationMs"))) try scope.put(event, "durationMs", try scope.get(finalized, "durationMs"));
    return c.JS_DupValue(engine.context, event);
}
