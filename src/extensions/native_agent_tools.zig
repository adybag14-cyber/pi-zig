//! Original sequential/parallel AgentLoop tool batches and truncated failures.
const em = @import("engine.zig");
const sdk = @import("native_sdk.zig");
const js = @import("native_js_values.zig");
const temp = @import("native_sdk_prompt_scope.zig");
const Scope = temp.Scope;
const flow = @import("native_agent_async.zig");
const call = @import("native_agent_tool_call.zig");
const c = em.c;
extern "c" fn JS_GetIteratorSymbol(context: ?*c.JSContext) c.JSValue;
const Mode = enum(c_int) { sequential, parallel, truncated };
const Stage = enum(c_int) { started, prepared, executed, finalized, ended, message_ended, ordered };

fn predicate(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    return predicateValue(engine, if (argc > 0) argv[0] else c.pi_js_undefined()) catch |err| sdk.fail(engine, err);
}
fn predicateValue(engine: *em.Engine, value: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    return c.pi_js_bool(engine.context, @intFromBool(scope.equal(try scope.get(value, "type"), try scope.text("toolCall"))));
}
fn find(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    return findValue(engine, if (argc > 0) argv[0] else c.pi_js_undefined(), roots[0]) catch |err| sdk.fail(engine, err);
}
fn findValue(engine: *em.Engine, tool: c.JSValue, tool_call: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    return c.pi_js_bool(engine.context, @intFromBool(scope.equal(try scope.get(tool, "name"), try scope.get(tool_call, "name"))));
}
fn sequential(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    return sequentialValue(engine, roots[0], if (argc > 0) argv[0] else c.pi_js_undefined()) catch |err| sdk.fail(engine, err);
}
fn sequentialValue(engine: *em.Engine, context: c.JSValue, tool_call: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const tools = try scope.get(context, "tools");
    var tool = c.pi_js_undefined();
    if (!temp.nullish(tools)) {
        const method = try scope.get(tools, "find");
        var roots = [_]c.JSValue{tool_call};
        const callback = try scope.own(try engine.checked(c.JS_NewCFunctionData2(engine.context, find, "", 1, 0, roots.len, &roots)));
        tool = try scope.call(method, tools, &.{callback});
    }
    const mode = if (temp.nullish(tool)) c.pi_js_undefined() else try scope.get(tool, "executionMode");
    return c.pi_js_bool(engine.context, @intFromBool(scope.equal(mode, try scope.text("sequential"))));
}
pub fn execute(engine: *em.Engine, context: c.JSValue, assistant: c.JSValue, config: c.JSValue, signal: c.JSValue, emit: c.JSValue) !c.JSValue {
    const pending = try flow.create(engine, c.pi_js_undefined());
    defer engine.freeValue(pending.owner);
    errdefer engine.freeValue(pending.promise);
    select(engine, pending.owner, context, assistant, config, signal, emit) catch |err| try flow.rejectError(engine, pending.owner, err);
    return pending.promise;
}
fn select(engine: *em.Engine, owner: c.JSValue, context: c.JSValue, assistant: c.JSValue, config: c.JSValue, signal: c.JSValue, emit: c.JSValue) !void {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const content = try scope.get(assistant, "content");
    const filter = try scope.get(content, "filter");
    const callback = try scope.own(try engine.checked(c.JS_NewCFunction(engine.context, predicate, "", 1)));
    const calls = try scope.call(filter, content, &.{callback});
    const some = try scope.get(calls, "some");
    var roots = [_]c.JSValue{context};
    const check = try scope.own(try engine.checked(c.JS_NewCFunctionData2(engine.context, sequential, "", 1, 0, roots.len, &roots)));
    const has_sequential = try scope.call(some, calls, &.{check});
    const mode: Mode = if (scope.equal(try scope.get(config, "toolExecution"), try scope.text("sequential")) or scope.truthy(has_sequential)) .sequential else .parallel;
    const result = try scope.own(try batch(engine, mode, context, assistant, calls, config, signal, emit));
    try flow.settle(engine, owner, false, result);
}
pub fn truncated(engine: *em.Engine, calls: c.JSValue, emit: c.JSValue) !c.JSValue {
    return batch(engine, .truncated, c.pi_js_undefined(), c.pi_js_undefined(), calls, c.pi_js_undefined(), c.pi_js_undefined(), emit);
}
fn batch(engine: *em.Engine, mode: Mode, context: c.JSValue, assistant: c.JSValue, calls: c.JSValue, config: c.JSValue, signal: c.JSValue, emit: c.JSValue) !c.JSValue {
    const pending = try flow.create(engine, c.pi_js_undefined());
    defer engine.freeValue(pending.owner);
    errdefer engine.freeValue(pending.promise);
    begin(engine, pending.owner, mode, context, assistant, calls, config, signal, emit) catch |err| try flow.rejectError(engine, pending.owner, err);
    return pending.promise;
}
fn begin(engine: *em.Engine, owner: c.JSValue, mode: Mode, context: c.JSValue, assistant: c.JSValue, calls: c.JSValue, config: c.JSValue, signal: c.JSValue, emit: c.JSValue) !void {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    inline for (.{ .{ "context", context }, .{ "assistant", assistant }, .{ "calls", calls }, .{ "config", config }, .{ "signal", signal }, .{ "emit", emit } }) |field| try scope.put(owner, field[0], field[1]);
    try scope.put(owner, "mode", c.JS_NewInt32(engine.context, @intFromEnum(mode)));
    try scope.put(owner, "finalizedCalls", try scope.array());
    if (mode != .parallel) try scope.put(owner, "messages", try scope.array());
    try scope.put(owner, "collecting", c.pi_js_bool(engine.context, 0));
    try setIterator(&scope, owner, calls);
    try advance(engine, owner);
}
fn modeOf(scope: *Scope, owner: c.JSValue) !Mode {
    var value: i32 = 0;
    if (c.JS_ToInt32(scope.engine.context, &value, try scope.get(owner, "mode")) < 0) return js.capture(scope.engine);
    return @enumFromInt(value);
}
fn setIterator(scope: *Scope, owner: c.JSValue, iterable: c.JSValue) !void {
    const symbol = try scope.own(try scope.engine.checked(JS_GetIteratorSymbol(scope.engine.context)));
    var iterator = try js.Iterator.init(scope.engine, iterable, symbol);
    defer iterator.deinit();
    try scope.put(owner, "iterator", iterator.iterator);
    try scope.put(owner, "next", iterator.next_function);
    try scope.put(owner, "steps", c.JS_NewInt32(scope.engine.context, 0));
    try scope.put(owner, "body", c.pi_js_bool(scope.engine.context, 0));
}
fn restore(engine: *em.Engine, owner: c.JSValue) !js.Iterator {
    const iterator = try sdk.get(engine, owner, "iterator");
    errdefer engine.freeValue(iterator);
    const next = try sdk.get(engine, owner, "next");
    errdefer engine.freeValue(next);
    const raw = try sdk.get(engine, owner, "steps");
    defer engine.freeValue(raw);
    var steps: i64 = 0;
    if (c.JS_ToInt64(engine.context, &steps, raw) < 0) return js.capture(engine);
    return .{ .engine = engine, .iterator = iterator, .next_function = next, .native_steps = @intCast(steps) };
}
fn event(scope: *Scope, kind: []const u8) !c.JSValue {
    const result = try scope.object();
    try scope.put(result, "type", try scope.text(kind));
    return result;
}
fn emitEvent(engine: *em.Engine, owner: c.JSValue, value: c.JSValue, stage: Stage) !void {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const result = try scope.call(try scope.get(owner, "emit"), c.pi_js_undefined(), &.{value});
    try wait(engine, owner, result, stage);
}
fn wait(engine: *em.Engine, owner: c.JSValue, pending: c.JSValue, stage: Stage) !void {
    return flow.wait(continueAwait, engine, owner, pending, @intFromEnum(stage));
}
fn advance(engine: *em.Engine, owner: c.JSValue) !void {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    try scope.put(owner, "body", c.pi_js_bool(engine.context, 0));
    var iterator = try restore(engine, owner);
    defer iterator.deinit();
    const item = (try iterator.next()) orelse return planned(engine, owner);
    defer engine.freeValue(item);
    try scope.put(owner, "steps", c.JS_NewFloat64(engine.context, @floatFromInt(iterator.native_steps)));
    try scope.put(owner, "body", c.pi_js_bool(engine.context, 1));
    if (scope.truthy(try scope.get(owner, "collecting"))) {
        try scope.put(owner, "finalized", item);
        return startMessage(engine, owner);
    }
    try scope.put(owner, "call", item);
    const start = try event(&scope, "tool_execution_start");
    try scope.put(start, "toolCallId", try scope.get(item, "id"));
    try scope.put(start, "toolName", try scope.get(item, "name"));
    try scope.put(start, "args", try scope.get(item, "arguments"));
    try emitEvent(engine, owner, start, .started);
}
fn immediateFinalized(scope: *Scope, tool_call: c.JSValue, result: c.JSValue, is_error: c.JSValue) !c.JSValue {
    const finalized = try scope.object();
    try scope.put(finalized, "toolCall", tool_call);
    try scope.put(finalized, "result", result);
    try scope.put(finalized, "isError", is_error);
    return finalized;
}
fn prepare(engine: *em.Engine, owner: c.JSValue) !void {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const tool_call = try scope.get(owner, "call");
    if (try modeOf(&scope, owner) == .truncated) {
        const name = try scope.stringify(try scope.get(tool_call, "name"));
        const text = try scope.concat(try scope.concat(try scope.text("Tool call \""), name), try scope.text("\" was not executed: the response hit the output token limit, so its arguments may be truncated. Re-issue the tool call with complete arguments."));
        const result = try scope.own(try call.errorResult(engine, text));
        const finalized = try immediateFinalized(&scope, tool_call, result, c.pi_js_bool(engine.context, 1));
        try scope.put(owner, "finalized", finalized);
        return emitEnd(engine, owner, finalized);
    }
    const pending = try scope.own(try call.prepare(engine, try scope.get(owner, "context"), try scope.get(owner, "assistant"), tool_call, try scope.get(owner, "config"), try scope.get(owner, "signal"), null));
    try wait(engine, owner, pending, .prepared);
}
fn updateCall(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    return updateEvent(engine, roots[0], roots[1], if (argc > 0) argv[0] else c.pi_js_undefined()) catch |err| sdk.fail(engine, err);
}
fn updateEvent(engine: *em.Engine, tool_call: c.JSValue, sink: c.JSValue, value: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const result = try event(&scope, "tool_execution_update");
    try scope.put(result, "toolCallId", try scope.get(tool_call, "id"));
    try scope.put(result, "toolName", try scope.get(tool_call, "name"));
    try scope.put(result, "args", try scope.get(tool_call, "arguments"));
    try scope.put(result, "partialResult", value);
    return js.call(engine, sink, c.pi_js_undefined(), &.{result});
}
fn updater(scope: *Scope, owner: c.JSValue) !c.JSValue {
    var roots = [_]c.JSValue{ try scope.get(owner, "call"), try scope.get(owner, "emit") };
    return scope.own(try scope.engine.checked(c.JS_NewCFunctionData2(scope.engine.context, updateCall, "", 1, 0, roots.len, &roots)));
}
fn startExecution(engine: *em.Engine, owner: c.JSValue) !void {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const pending = try scope.own(try call.execute(engine, try scope.get(owner, "prepared"), try scope.get(owner, "signal"), try updater(&scope, owner)));
    try wait(engine, owner, pending, .executed);
}
fn finalize(engine: *em.Engine, owner: c.JSValue, executed: c.JSValue) !void {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const pending = try scope.own(try call.finalize(engine, try scope.get(owner, "context"), try scope.get(owner, "assistant"), try scope.get(owner, "prepared"), executed, try scope.get(owner, "config"), try scope.get(owner, "signal")));
    try wait(engine, owner, pending, .finalized);
}
fn startMessage(engine: *em.Engine, owner: c.JSValue) !void {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const message = try scope.own(try call.toolResultMessage(engine, try scope.get(owner, "finalized")));
    try scope.put(owner, "message", message);
    const pending = try scope.own(try @import("native_agent_tool_events.zig").message(engine, message, try scope.get(owner, "emit")));
    try wait(engine, owner, pending, .message_ended);
}
fn emitEnd(engine: *em.Engine, owner: c.JSValue, finalized: c.JSValue) !void {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const pending = try scope.own(try @import("native_agent_tool_events.zig").end(engine, finalized, try scope.get(owner, "emit")));
    try wait(engine, owner, pending, .ended);
}
fn signalAborted(scope: *Scope, owner: c.JSValue) !bool {
    const signal = try scope.get(owner, "signal");
    return !temp.nullish(signal) and scope.truthy(try scope.get(signal, "aborted"));
}
fn nextOrStop(engine: *em.Engine, owner: c.JSValue) !void {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    if (try modeOf(&scope, owner) != .truncated and try signalAborted(&scope, owner)) {
        var iterator = try restore(engine, owner);
        defer iterator.deinit();
        try iterator.close();
        try scope.put(owner, "body", c.pi_js_bool(engine.context, 0));
        return planned(engine, owner);
    }
    try advance(engine, owner);
}
fn invokeEntry(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    return invokeEntryValue(engine, if (argc > 0) argv[0] else c.pi_js_undefined()) catch |err| sdk.fail(engine, err);
}
fn invokeEntryValue(engine: *em.Engine, entry: c.JSValue) !c.JSValue {
    if (c.JS_IsFunction(engine.context, entry)) return js.call(engine, entry, c.pi_js_undefined(), &.{});
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    return js.invoke(engine, try scope.global("Promise"), "resolve", &.{entry});
}
fn planned(engine: *em.Engine, owner: c.JSValue) !void {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    if (try modeOf(&scope, owner) == .parallel and !scope.truthy(try scope.get(owner, "collecting"))) {
        const promise = try scope.global("Promise");
        const all = try scope.get(promise, "all");
        const finalized = try scope.get(owner, "finalizedCalls");
        const map = try scope.get(finalized, "map");
        const callback = try scope.own(try engine.checked(c.JS_NewCFunction(engine.context, invokeEntry, "", 1)));
        return wait(engine, owner, try scope.call(all, promise, &.{try scope.call(map, finalized, &.{callback})}), .ordered);
    }
    const result = try scope.object();
    try scope.put(result, "messages", try scope.get(owner, "messages"));
    const terminated = try modeOf(&scope, owner) != .truncated and try shouldTerminate(&scope, try scope.get(owner, "finalizedCalls"));
    try scope.put(result, "terminate", c.pi_js_bool(engine.context, @intFromBool(terminated)));
    try flow.settle(engine, owner, false, result);
}
fn everyTerminated(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    return terminatedValue(engine, if (argc > 0) argv[0] else c.pi_js_undefined()) catch |err| sdk.fail(engine, err);
}
fn terminatedValue(engine: *em.Engine, finalized: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const terminate = try scope.get(try scope.get(finalized, "result"), "terminate");
    return c.pi_js_bool(engine.context, @intFromBool(scope.equal(terminate, c.pi_js_bool(engine.context, 1))));
}
fn shouldTerminate(scope: *Scope, finalized: c.JSValue) !bool {
    if (!try scope.positive(try scope.get(finalized, "length"))) return false;
    const every = try scope.get(finalized, "every");
    const callback = try scope.own(try scope.engine.checked(c.JS_NewCFunction(scope.engine.context, everyTerminated, "", 1)));
    return scope.truthy(try scope.call(every, finalized, &.{callback}));
}
fn parallelEntry(context: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue, _: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    return parallelRun(engine, roots[0], roots[1], roots[2]) catch |err| sdk.fail(engine, err);
}
fn parallelRun(engine: *em.Engine, batch_owner: c.JSValue, prepared: c.JSValue, tool_call: c.JSValue) !c.JSValue {
    const pending = try flow.create(engine, c.pi_js_undefined());
    defer engine.freeValue(pending.owner);
    errdefer engine.freeValue(pending.promise);
    beginParallel(engine, pending.owner, batch_owner, prepared, tool_call) catch |err| try flow.rejectError(engine, pending.owner, err);
    return pending.promise;
}
fn beginParallel(engine: *em.Engine, owner: c.JSValue, batch_owner: c.JSValue, prepared: c.JSValue, tool_call: c.JSValue) !void {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    inline for (.{ "context", "assistant", "config", "signal", "emit" }) |field| try scope.put(owner, field, try scope.get(batch_owner, field));
    try scope.put(owner, "call", tool_call);
    try scope.put(owner, "prepared", prepared);
    try scope.put(owner, "entry", c.pi_js_bool(engine.context, 1));
    try scope.put(owner, "body", c.pi_js_bool(engine.context, 0));
    if (try signalAborted(&scope, owner)) {
        const error_result = try scope.own(try call.errorResult(engine, try scope.text("Operation aborted")));
        const finalized = try immediateFinalized(&scope, tool_call, error_result, c.pi_js_bool(engine.context, 1));
        try scope.put(owner, "finalized", finalized);
        return emitEnd(engine, owner, finalized);
    }
    try startExecution(engine, owner);
}
fn closeReject(engine: *em.Engine, owner: c.JSValue, value: c.JSValue) !void {
    const body = try sdk.get(engine, owner, "body");
    defer engine.freeValue(body);
    if (c.JS_ToBool(engine.context, body) != 0) {
        var iterator = try restore(engine, owner);
        defer iterator.deinit();
        const prior = engine.captured_exception;
        engine.captured_exception = c.JS_DupValue(engine.context, value);
        iterator.closePreserving();
        if (engine.captured_exception) |captured| engine.freeValue(captured);
        engine.captured_exception = prior;
    }
    try flow.settle(engine, owner, true, value);
}
fn continueAwait(engine: *em.Engine, owner: c.JSValue, value: c.JSValue, rejected: bool, stage_int: c_int) !void {
    if (rejected) return closeReject(engine, owner, value);
    resumeCore(engine, owner, value, @enumFromInt(stage_int)) catch |err| {
        const raw = flow.reason(engine, err);
        defer engine.freeValue(raw);
        return closeReject(engine, owner, raw);
    };
}
fn resumeCore(engine: *em.Engine, owner: c.JSValue, value: c.JSValue, stage: Stage) !void {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    switch (stage) {
        .started => try prepare(engine, owner),
        .prepared => {
            const kind = try scope.get(value, "kind");
            if (scope.equal(kind, try scope.text("immediate"))) {
                const finalized = try immediateFinalized(&scope, try scope.get(owner, "call"), try scope.get(value, "result"), try scope.get(value, "isError"));
                try scope.put(owner, "finalized", finalized);
                return emitEnd(engine, owner, finalized);
            }
            try scope.put(owner, "prepared", value);
            if (try modeOf(&scope, owner) == .parallel) {
                const finalized = try scope.get(owner, "finalizedCalls");
                const push = try scope.get(finalized, "push");
                var roots = [_]c.JSValue{ owner, value, try scope.get(owner, "call") };
                const entry = try scope.own(try engine.checked(c.JS_NewCFunctionData2(engine.context, parallelEntry, "", 0, 0, roots.len, &roots)));
                const parent = try scope.own(try engine.checked(c.JS_GetAsyncFunctionPrototype(engine.context)));
                if (c.JS_SetPrototype(engine.context, entry, parent) < 0) return js.capture(engine);
                _ = try scope.call(push, finalized, &.{entry});
                return nextOrStop(engine, owner);
            }
            try startExecution(engine, owner);
        },
        .executed => try finalize(engine, owner, value),
        .finalized => {
            try scope.put(owner, "finalized", value);
            try emitEnd(engine, owner, value);
        },
        .ended => {
            const finalized = try scope.get(owner, "finalized");
            if (scope.truthy(try scope.get(owner, "entry"))) return flow.settle(engine, owner, false, finalized);
            if (try modeOf(&scope, owner) == .parallel) {
                _ = try scope.invoke(try scope.get(owner, "finalizedCalls"), "push", &.{finalized});
                return nextOrStop(engine, owner);
            }
            try startMessage(engine, owner);
        },
        .message_ended => {
            if (!scope.truthy(try scope.get(owner, "collecting")) and try modeOf(&scope, owner) == .sequential) _ = try scope.invoke(try scope.get(owner, "finalizedCalls"), "push", &.{try scope.get(owner, "finalized")});
            _ = try scope.invoke(try scope.get(owner, "messages"), "push", &.{try scope.get(owner, "message")});
            if (scope.truthy(try scope.get(owner, "collecting"))) return advance(engine, owner);
            try nextOrStop(engine, owner);
        },
        .ordered => {
            try scope.put(owner, "finalizedCalls", value);
            try scope.put(owner, "messages", try scope.array());
            try scope.put(owner, "collecting", c.pi_js_bool(engine.context, 1));
            try setIterator(&scope, owner, value);
            try advance(engine, owner);
        },
    }
}
