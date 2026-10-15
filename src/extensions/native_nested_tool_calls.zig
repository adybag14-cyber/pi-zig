//! Actual NestedToolCallRunner. Queue releases and retained update closures are
//! VM-owned graphs, including the finally path when hooks reject with raw values.
const em = @import("engine.zig");
const sdk = @import("native_sdk.zig");
const js = @import("native_js_values.zig");
const temp = @import("native_sdk_prompt_scope.zig");
const Scope = temp.Scope;
const flow = @import("native_agent_async.zig");
const c = em.c;
const Method = enum(c_int) { execute, takeRecord, clear };
const Stage = enum(c_int) { started, exclusive, outcome, ended };
const Callback = enum(c_int) { find, update, release, text, textBlock };
pub fn constructor(engine: *em.Engine) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const prototype = try scope.object();
    const recorder = try scope.own(try @import("native_nested_call_recorder.zig").constructor(engine));
    var roots = [_]c.JSValue{recorder};
    inline for (.{ Method.execute, Method.takeRecord, Method.clear }) |method| {
        const function = try scope.own(try engine.checked(if (method == .execute) c.JS_NewCFunctionData2(engine.context, executeDispatch, "execute", 3, 0, roots.len, &roots) else c.pi_js_function_magic(engine.context, dispatch, @tagName(method), if (method == .clear) 0 else 1, @intFromEnum(method))));
        if (method == .execute) {
            const parent = try scope.own(try engine.checked(c.JS_GetAsyncFunctionPrototype(engine.context)));
            if (c.JS_SetPrototype(engine.context, function, parent) < 0) return js.capture(engine);
        }
        if (c.JS_DefinePropertyValueStr(engine.context, prototype, @tagName(method), c.JS_DupValue(engine.context, function), c.JS_PROP_WRITABLE | c.JS_PROP_CONFIGURABLE) < 0) return js.capture(engine);
    }
    return @import("native_class.zig").constructor(engine, "NestedToolCallRunner", 1, prototype, construct, &.{});
}
fn construct(engine: *em.Engine, target: c.JSValue, args: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const result = try scope.own(try @import("native_class.zig").object(engine, target));
    try scope.put(result, "host", c.pi_js_undefined());
    try scope.put(result, "scopes", try scope.own(try js.builtin(engine, "Map", &.{})));
    try scope.put(result, "queueTail", try scope.invoke(try scope.global("Promise"), "resolve", &.{}));
    try scope.set(result, "host", arg(args, 0));
    return c.JS_DupValue(engine.context, result);
}
fn arg(args: []const c.JSValue, index: usize) c.JSValue {
    return if (index < args.len) args[index] else c.pi_js_undefined();
}
fn dispatch(context: ?*c.JSContext, runner: c.JSValue, argc: c_int, argv: [*c]c.JSValue, magic: c_int) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    const args = if (argc > 0) argv[0..@intCast(argc)] else &.{};
    return ordinary(engine, runner, @enumFromInt(magic), arg(args, 0)) catch |err| sdk.fail(engine, err);
}
fn ordinary(engine: *em.Engine, runner: c.JSValue, method: Method, id: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    if (method == .clear) {
        _ = try scope.invoke(try scope.get(runner, "scopes"), "clear", &.{});
        return c.pi_js_undefined();
    }
    const found = try scope.invoke(try scope.get(runner, "scopes"), "get", &.{id});
    _ = try scope.invoke(try scope.get(runner, "scopes"), "delete", &.{id});
    if (!scope.truthy(found)) return c.pi_js_undefined();
    const result = try scope.object();
    try scope.put(result, "calls", try scope.invoke(try scope.get(found, "recorder"), "snapshot", &.{}));
    try scope.put(result, "usage", try scope.get(try scope.get(found, "recorder"), "totalUsage"));
    return c.JS_DupValue(engine.context, result);
}
fn executeDispatch(context: ?*c.JSContext, runner: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    return execute(engine, runner, if (argc > 0) argv[0..@intCast(argc)] else &.{}, roots[0]) catch |err| sdk.fail(engine, err);
}
fn execute(engine: *em.Engine, runner: c.JSValue, args: []const c.JSValue, recorder: c.JSValue) !c.JSValue {
    const pending = try flow.create(engine, runner);
    defer engine.freeValue(pending.owner);
    errdefer engine.freeValue(pending.promise);
    start(engine, pending.owner, args, recorder) catch |err| try flow.rejectError(engine, pending.owner, err);
    return pending.promise;
}
fn callback(scope: *Scope, kind: Callback, roots: []const c.JSValue) !c.JSValue {
    const function = try scope.own(try scope.engine.checked(c.JS_NewCFunctionData2(scope.engine.context, callbackDispatch, "", 1, @intFromEnum(kind), @intCast(roots.len), @constCast(roots.ptr))));
    if (kind == .update) {
        const parent = try scope.own(try scope.engine.checked(c.JS_GetAsyncFunctionPrototype(scope.engine.context)));
        if (c.JS_SetPrototype(scope.engine.context, function, parent) < 0) return js.capture(scope.engine);
    }
    return function;
}
fn callbackDispatch(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, magic: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    return callbackBody(engine, @enumFromInt(magic), if (argc > 0) argv[0] else c.pi_js_undefined(), roots) catch |err| sdk.fail(engine, err);
}
fn callbackBody(engine: *em.Engine, kind: Callback, value: c.JSValue, roots: [*c]c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    switch (kind) {
        .find => return c.pi_js_bool(engine.context, @intFromBool(scope.equal(try scope.get(value, "name"), roots[0]))),
        .text => return c.JS_DupValue(engine.context, try scope.get(value, "text")),
        .textBlock => return c.pi_js_bool(engine.context, @intFromBool(scope.equal(try scope.get(value, "type"), try scope.text("text")))),
        .release => {
            try scope.put(roots[0], "release", value);
            return c.pi_js_undefined();
        },
        .update => return update(engine, roots[0], value),
    }
}
fn start(engine: *em.Engine, owner: c.JSValue, args: []const c.JSValue, recorder_class: c.JSValue) !void {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const runner = try scope.get(owner, "agent");
    inline for (.{ .{ "callerId", arg(args, 0) }, .{ "name", arg(args, 1) } }) |field| try scope.put(owner, field[0], field[1]);
    var options = arg(args, 3);
    if (c.JS_IsUndefined(options)) options = try scope.object();
    try scope.put(owner, "options", options);
    var call_scope = try scope.invoke(try scope.get(runner, "scopes"), "get", &.{arg(args, 0)});
    if (!scope.truthy(call_scope)) {
        call_scope = try scope.object();
        try scope.put(call_scope, "recorder", try scope.own(try engine.checked(c.JS_CallConstructor(engine.context, recorder_class, 0, null))));
        try scope.put(call_scope, "nextId", c.JS_NewInt32(engine.context, 1));
        try scope.put(call_scope, "holdsQueue", c.pi_js_bool(engine.context, 0));
        _ = try scope.invoke(try scope.get(runner, "scopes"), "set", &.{ arg(args, 0), call_scope });
    }
    try scope.put(owner, "scope", call_scope);
    const call = try scope.object();
    try scope.put(call, "type", try scope.text("toolCall"));
    const caller_text = try scope.stringify(arg(args, 0));
    const next = try scope.get(call_scope, "nextId");
    // Postincrement applies ToNumeric even when a caller mutates the scope.
    const numeric = try scope.own(try engine.checked(c.JS_PiToNumeric(engine.context, next)));
    const incremented = try scope.own(try engine.checked(c.JS_PiIncrement(engine.context, numeric)));
    try scope.set(call_scope, "nextId", incremented);
    const id = try scope.concat(try scope.concat(caller_text, try scope.text("/")), try scope.stringify(numeric));
    try scope.put(call, "id", id);
    try scope.put(call, "name", arg(args, 1));
    var call_args = arg(args, 2);
    if (temp.nullish(call_args)) call_args = try scope.object();
    try scope.put(call, "arguments", call_args);
    try scope.put(owner, "toolCall", call);
    try scope.put(owner, "record", try scope.invoke(try scope.get(call_scope, "recorder"), "start", &.{call}));
    const host = try scope.get(runner, "host");
    const emit = try scope.get(host, "emit");
    const event = try scope.object();
    try scope.put(event, "type", try scope.text("tool_execution_start"));
    try scope.put(event, "toolCallId", try scope.get(call, "id"));
    try scope.put(event, "toolName", arg(args, 1));
    try scope.put(event, "args", try scope.get(call, "arguments"));
    try scope.put(event, "parentToolCallId", arg(args, 0));
    try flow.wait(step, engine, owner, try scope.call(emit, host, &.{event}), @intFromEnum(Stage.started));
}
fn step(engine: *em.Engine, owner: c.JSValue, value: c.JSValue, rejected: bool, stage_number: c_int) !void {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const stage: Stage = @enumFromInt(stage_number);
    if (stage == .outcome) {
        // JS finally runs on both raw rejection and fulfillment, before records.
        try finishScope(&scope, owner);
        if (rejected) return flow.settle(engine, owner, true, value);
        return finishOutcome(engine, owner, value);
    }
    if (rejected) return flow.settle(engine, owner, true, value);
    switch (stage) {
        .started => {
            const runner = try scope.get(owner, "agent");
            const call_scope = try scope.get(owner, "scope");
            var exclusive = false;
            if (!scope.truthy(try scope.get(call_scope, "holdsQueue"))) {
                exclusive = scope.truthy(try scope.invoke(try scope.get(runner, "host"), "isSequential", &.{}));
                if (!exclusive) {
                    const tools = try scope.invoke(try scope.get(runner, "host"), "getTools", &.{});
                    const tool = try scope.invoke(tools, "find", &.{try callback(&scope, .find, &.{try scope.get(owner, "name")})});
                    exclusive = scope.equal(if (temp.nullish(tool)) c.pi_js_undefined() else try scope.get(tool, "executionMode"), try scope.text("sequential"));
                }
            }
            try scope.put(owner, "exclusive", c.pi_js_bool(engine.context, @intFromBool(exclusive)));
            try scope.put(owner, "release", c.pi_js_undefined());
            if (exclusive) {
                const previous = try scope.get(runner, "queueTail");
                const promise_class = try scope.global("Promise");
                var inputs = [_]c.JSValue{try callback(&scope, .release, &.{owner})};
                try scope.set(runner, "queueTail", try scope.own(try engine.checked(c.JS_CallConstructor(engine.context, promise_class, inputs.len, &inputs))));
                return flow.wait(step, engine, owner, previous, @intFromEnum(Stage.exclusive));
            }
            try runCall(engine, owner);
        },
        .exclusive => try runCall(engine, owner),
        .ended => try flow.settle(engine, owner, false, try scope.get(owner, "outcome")),
        .outcome => unreachable,
    }
}
fn runCall(engine: *em.Engine, owner: c.JSValue) !void {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const runner = try scope.get(owner, "agent");
    const tool_call = try scope.get(owner, "toolCall");
    const call_scope = try scope.get(owner, "scope");
    const scopes = try scope.get(runner, "scopes");
    const set = try scope.get(scopes, "set");
    const id = try scope.get(tool_call, "id");
    const nested = try scope.object();
    try scope.put(nested, "recorder", try scope.get(call_scope, "recorder"));
    try scope.put(nested, "nextId", c.JS_NewInt32(engine.context, 1));
    const holds = try scope.get(call_scope, "holdsQueue");
    try scope.put(nested, "holdsQueue", if (scope.truthy(holds)) holds else try scope.get(owner, "exclusive"));
    _ = try scope.call(set, scopes, &.{ id, nested });
    runAttempt(engine, owner) catch |err| {
        // Retain the original rejection before finally can change captured state.
        const reason = flow.reason(engine, err);
        defer engine.freeValue(reason);
        try finishScope(&scope, owner);
        try flow.settle(engine, owner, true, reason);
    };
}
fn runAttempt(engine: *em.Engine, owner: c.JSValue) !void {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const host = try scope.get(try scope.get(owner, "agent"), "host");
    const run = try scope.get(host, "runToolCall");
    const result = try scope.call(run, host, &.{ try scope.get(owner, "toolCall"), try scope.get(owner, "callerId"), try scope.get(try scope.get(owner, "options"), "signal"), try callback(&scope, .update, &.{owner}) });
    try flow.wait(step, engine, owner, result, @intFromEnum(Stage.outcome));
}
fn finishScope(scope: *Scope, owner: c.JSValue) !void {
    const scopes = try scope.get(try scope.get(owner, "agent"), "scopes");
    const remove = try scope.get(scopes, "delete");
    _ = try scope.call(remove, scopes, &.{try scope.get(try scope.get(owner, "toolCall"), "id")});
    const release = try scope.get(owner, "release");
    if (!temp.nullish(release)) _ = try scope.call(release, c.pi_js_undefined(), &.{});
}
fn textOf(scope: *Scope, result: c.JSValue) !c.JSValue {
    var content = try scope.get(result, "content");
    if (temp.nullish(content)) content = try scope.array();
    const filtered = try scope.invoke(content, "filter", &.{try callback(scope, .textBlock, &.{})});
    const mapped = try scope.invoke(filtered, "map", &.{try callback(scope, .text, &.{})});
    return scope.invoke(mapped, "join", &.{try scope.text("\n")});
}
fn finishOutcome(engine: *em.Engine, owner: c.JSValue, outcome: c.JSValue) !void {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const call_scope = try scope.get(owner, "scope");
    const recorder = try scope.get(call_scope, "recorder");
    const finish = try scope.get(recorder, "finish");
    _ = try scope.call(finish, recorder, &.{ try scope.get(owner, "record"), try scope.get(outcome, "isError"), try textOf(&scope, try scope.get(outcome, "result")) });
    if (scope.truthy(try scope.get(try scope.get(outcome, "result"), "usage"))) {
        const usage_recorder = try scope.get(call_scope, "recorder");
        const add = try scope.get(usage_recorder, "addUsage");
        _ = try scope.call(add, usage_recorder, &.{try scope.get(try scope.get(outcome, "result"), "usage")});
    }
    try scope.put(owner, "outcome", outcome);
    const host = try scope.get(try scope.get(owner, "agent"), "host");
    const emit = try scope.get(host, "emit");
    const call = try scope.get(owner, "toolCall");
    const event = try scope.object();
    try scope.put(event, "type", try scope.text("tool_execution_end"));
    try scope.put(event, "toolCallId", try scope.get(call, "id"));
    try scope.put(event, "toolName", try scope.get(owner, "name"));
    try scope.put(event, "result", try scope.get(outcome, "result"));
    try scope.put(event, "isError", try scope.get(outcome, "isError"));
    if (!c.JS_IsUndefined(try scope.get(outcome, "durationMs"))) try scope.put(event, "durationMs", try scope.get(outcome, "durationMs"));
    try scope.put(event, "parentToolCallId", try scope.get(owner, "callerId"));
    try flow.wait(step, engine, owner, try scope.call(emit, host, &.{event}), @intFromEnum(Stage.ended));
}
fn update(engine: *em.Engine, original: c.JSValue, partial: c.JSValue) !c.JSValue {
    const pending = try flow.create(engine, original);
    defer engine.freeValue(pending.owner);
    errdefer engine.freeValue(pending.promise);
    updateStart(engine, pending.owner, original, partial) catch |err| try flow.rejectError(engine, pending.owner, err);
    return pending.promise;
}
fn updateStart(engine: *em.Engine, owner: c.JSValue, original: c.JSValue, partial: c.JSValue) !void {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const options = try scope.get(original, "options");
    const on_update = try scope.get(options, "onUpdate");
    if (!temp.nullish(on_update)) _ = try scope.call(on_update, options, &.{partial});
    const host = try scope.get(try scope.get(original, "agent"), "host");
    const emit = try scope.get(host, "emit");
    const call = try scope.get(original, "toolCall");
    const event = try scope.object();
    try scope.put(event, "type", try scope.text("tool_execution_update"));
    try scope.put(event, "toolCallId", try scope.get(call, "id"));
    try scope.put(event, "toolName", try scope.get(original, "name"));
    try scope.put(event, "args", try scope.get(call, "arguments"));
    try scope.put(event, "partialResult", partial);
    try scope.put(event, "parentToolCallId", try scope.get(original, "callerId"));
    try flow.wait(updateDone, engine, owner, try scope.call(emit, host, &.{event}), 0);
}
fn updateDone(engine: *em.Engine, owner: c.JSValue, value: c.JSValue, rejected: bool, _: c_int) !void {
    try flow.settle(engine, owner, rejected, if (rejected) value else c.pi_js_undefined());
}
