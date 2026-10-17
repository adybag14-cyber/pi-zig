//! Private complete Agent class assembly over the actual low-level loop.
//! This namespace is intentionally not registered as public pi-agent-core.
const em = @import("engine.zig");
const sdk = @import("native_sdk.zig");
const js = @import("native_js_values.zig");
const temp = @import("native_sdk_prompt_scope.zig");
const Scope = temp.Scope;
const pure = @import("native_agent_methods.zig");
const c = em.c;
const Body = enum(c_int) {
    subscribe,
    state,
    steeringMode,
    setSteeringMode,
    followUpMode,
    setFollowUpMode,
    steer,
    followUp,
    clearSteeringQueue,
    clearFollowUpQueue,
    clearAllQueues,
    hasQueuedMessages,
    peekQueuedMessages,
    signal,
    abort,
    waitForIdle,
    reset,
    normalizePromptInput,
    createContextSnapshot,
    finishRun,
    prompt,
    continueRun,
    runPromptMessages,
    runContinuation,
    createLoopConfig,
    runWithLifecycle,
    handleRunFailure,
    processEvents,
};
const Entry = struct { name: [:0]const u8, body: Body, length: c_int, async_body: bool = false, get: bool = false, set: ?Body = null };
// Actual Source641 complete class declaration order, including private bodies.
const entries = [_]Entry{
    .{ .name = "subscribe", .body = .subscribe, .length = 1 },
    .{ .name = "state", .body = .state, .length = 0, .get = true },
    .{ .name = "steeringMode", .body = .steeringMode, .length = 0, .get = true, .set = .setSteeringMode },
    .{ .name = "followUpMode", .body = .followUpMode, .length = 0, .get = true, .set = .setFollowUpMode },
    .{ .name = "steer", .body = .steer, .length = 1 },
    .{ .name = "followUp", .body = .followUp, .length = 1 },
    .{ .name = "clearSteeringQueue", .body = .clearSteeringQueue, .length = 0 },
    .{ .name = "clearFollowUpQueue", .body = .clearFollowUpQueue, .length = 0 },
    .{ .name = "clearAllQueues", .body = .clearAllQueues, .length = 0 },
    .{ .name = "hasQueuedMessages", .body = .hasQueuedMessages, .length = 0 },
    .{ .name = "peekQueuedMessages", .body = .peekQueuedMessages, .length = 0 },
    .{ .name = "signal", .body = .signal, .length = 0, .get = true },
    .{ .name = "abort", .body = .abort, .length = 0 },
    .{ .name = "waitForIdle", .body = .waitForIdle, .length = 0 },
    .{ .name = "reset", .body = .reset, .length = 0 },
    .{ .name = "prompt", .body = .prompt, .length = 2, .async_body = true },
    .{ .name = "continue", .body = .continueRun, .length = 0, .async_body = true },
    .{ .name = "normalizePromptInput", .body = .normalizePromptInput, .length = 2 },
    .{ .name = "runPromptMessages", .body = .runPromptMessages, .length = 1, .async_body = true },
    .{ .name = "runContinuation", .body = .runContinuation, .length = 0, .async_body = true },
    .{ .name = "createContextSnapshot", .body = .createContextSnapshot, .length = 0 },
    .{ .name = "createLoopConfig", .body = .createLoopConfig, .length = 0 },
    .{ .name = "runWithLifecycle", .body = .runWithLifecycle, .length = 1, .async_body = true },
    .{ .name = "handleRunFailure", .body = .handleRunFailure, .length = 2, .async_body = true },
    .{ .name = "finishRun", .body = .finishRun, .length = 0 },
    .{ .name = "processEvents", .body = .processEvents, .length = 1, .async_body = true },
};
pub fn install(engine: *em.Engine, exports: c.JSValue) !void {
    if (engine.native_agent_complete_cache) |cache| {
        try sdk.put(engine, exports, "Agent", try sdk.get(engine, cache, "constructor"));
        return sdk.put(engine, exports, "setDefaultStreamFn", try sdk.get(engine, cache, "setter"));
    }
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const cache = try scope.object();
    const prototype = try scope.object();
    try scope.put(cache, "queue", try scope.own(try @import("native_agent_queue.zig").constructor(engine)));
    try scope.put(cache, "converter", try scope.own(try @import("native_agent_construct.zig").defaultConverter(engine)));
    try scope.put(cache, "getter", try scope.own(try engine.checked(c.JS_NewCFunction(engine.context, @import("native_agent_default_stream.zig").getter, "getDefaultStreamFn", 0))));
    try scope.put(cache, "loop", try scope.own(try @import("native_agent_loop.zig").loopFunction(engine, false)));
    try scope.put(cache, "continuation", try scope.own(try @import("native_agent_loop.zig").loopFunction(engine, true)));
    try scope.put(cache, "usage", try scope.own(try sdk.jsonObject(engine, "{\"input\":0,\"output\":0,\"cacheRead\":0,\"cacheWrite\":0,\"totalTokens\":0,\"cost\":{\"input\":0,\"output\":0,\"cacheRead\":0,\"cacheWrite\":0,\"total\":0}}")));
    const constructor = try scope.own(try @import("native_class.zig").constructor(engine, "Agent", 1, prototype, construct, &.{cache}));
    try scope.put(cache, "constructor", constructor);
    inline for (entries) |entry| {
        if (entry.get) {
            try accessor(engine, prototype, entry);
        } else {
            const callback = try scope.own(if (comptime entry.async_body) try switch (entry.body) {
                .prompt => @import("native_agent_prompt_async.zig").create(engine, .prompt),
                .continueRun => @import("native_agent_prompt_async.zig").create(engine, .continue_run),
                .runPromptMessages => @import("native_agent_execution_async.zig").create(engine, false, try scope.get(cache, "loop")),
                .runContinuation => @import("native_agent_execution_async.zig").create(engine, true, try scope.get(cache, "continuation")),
                .runWithLifecycle => @import("native_agent_lifecycle_async.zig").create(engine),
                .handleRunFailure => @import("native_agent_failure_async.zig").create(engine, try scope.get(cache, "usage")),
                .processEvents => @import("native_agent_events_async.zig").create(engine),
                else => @compileError("Actual Agent async method requires its direct native AF body"),
            } else try engine.checked(c.pi_js_function_magic(engine.context, method, entry.name, entry.length, @intFromEnum(entry.body))));
            if (c.JS_DefinePropertyValueStr(engine.context, prototype, entry.name, c.JS_DupValue(engine.context, callback), c.JS_PROP_WRITABLE | c.JS_PROP_CONFIGURABLE) < 0) return js.capture(engine);
        }
    }
    const setter = try scope.own(try @import("native_node_function.zig").create(engine, "setDefaultStreamFn", 1, setDefault, &.{}));
    try scope.put(cache, "setter", setter);
    engine.native_agent_complete_cache = c.JS_DupValue(engine.context, cache);
    try scope.put(exports, "Agent", constructor);
    try scope.put(exports, "setDefaultStreamFn", setter);
}
fn construct(engine: *em.Engine, target: c.JSValue, args: []const c.JSValue, values: []const c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const cache = values[0];
    return @import("native_agent_construct.zig").create(engine, target, if (args.len > 0) args[0] else c.pi_js_undefined(), try scope.get(cache, "queue"), try scope.get(cache, "getter"), try scope.get(cache, "converter"));
}
fn setDefault(engine: *em.Engine, _: c.JSValue, args: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
    @import("native_agent_default_stream.zig").set(engine, if (args.len > 0) args[0] else c.pi_js_undefined());
    return c.pi_js_undefined();
}
fn accessor(engine: *em.Engine, prototype: c.JSValue, comptime entry: Entry) !void {
    const getter = try engine.checked(c.pi_js_function_magic(engine.context, method, "get " ++ entry.name, 0, @intFromEnum(entry.body)));
    const setter = if (entry.set) |body| engine.checked(c.pi_js_function_magic(engine.context, method, "set " ++ entry.name, 1, @intFromEnum(body))) catch |err| {
        engine.freeValue(getter);
        return err;
    } else c.pi_js_undefined();
    const atom = c.JS_NewAtom(engine.context, entry.name);
    if (atom == c.JS_ATOM_NULL) {
        engine.freeValue(getter);
        engine.freeValue(setter);
        return error.OutOfMemory;
    }
    defer c.JS_FreeAtom(engine.context, atom);
    if (c.JS_DefinePropertyGetSet(engine.context, prototype, atom, getter, setter, c.JS_PROP_CONFIGURABLE) < 0) return js.capture(engine);
}
fn method(context: ?*c.JSContext, receiver: c.JSValue, argc: c_int, argv: [*c]c.JSValue, magic: c_int) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    return apply(engine, receiver, @enumFromInt(magic), if (argc > 0) argv[0..@intCast(argc)] else &.{}) catch |err| sdk.fail(engine, err);
}
fn apply(engine: *em.Engine, agent: c.JSValue, body: Body, args: []const c.JSValue) !c.JSValue {
    if (@intFromEnum(body) <= @intFromEnum(Body.finishRun)) return pure.apply(engine, agent, @enumFromInt(@intFromEnum(body)), args);
    const first = if (args.len > 0) args[0] else c.pi_js_undefined();
    const second = if (args.len > 1) args[1] else c.pi_js_undefined();
    return switch (body) {
        .prompt => @import("native_agent_run.zig").prompt(engine, agent, first, second),
        .continueRun => @import("native_agent_run.zig").continueRun(engine, agent),
        .createLoopConfig => @import("native_agent_loop_config.zig").create(engine, agent, first),
        .runWithLifecycle => @import("native_agent_lifecycle.zig").run(engine, agent, first),
        .processEvents => @import("native_agent_events.zig").process(engine, agent, first),
        .handleRunFailure, .runPromptMessages, .runContinuation => selected: {
            const cache = engine.native_agent_complete_cache orelse return error.NativeAgentCompleteNotInitialized;
            const value = try sdk.get(engine, cache, if (body == .handleRunFailure) "usage" else if (body == .runContinuation) "continuation" else "loop");
            defer engine.freeValue(value);
            break :selected if (body == .handleRunFailure) @import("native_agent_failure.zig").run(engine, agent, first, second, value) else @import("native_agent_run.zig").runMessages(engine, agent, first, second, value, body == .runContinuation);
        },
        else => unreachable,
    };
}
