//! Original Agent constructor and implemented bodies, privately assembled for
//! component qualification. Public pi-agent-core activation remains disabled
//! until the native AgentLoop imports and compat stream default are complete.
const std = @import("std");
const em = @import("engine.zig");
const sdk = @import("native_sdk.zig");
const js = @import("native_js_values.zig");
const Scope = @import("native_sdk_prompt_scope.zig").Scope;
const pure = @import("native_agent_methods.zig");
const c = em.c;

/// The caller supplies a genuine native ModelRuntime. This private qualification
/// namespace is not registered as pi-agent-core and supplies no missing loop
/// methods. All installed methods below have actual native bodies.
pub fn installFoundations(engine: *em.Engine, exports: c.JSValue, runtime: c.JSValue) !void {
    if (engine.native_agent_core_cache) |cache| return sdk.put(engine, exports, "Agent", try sdk.get(engine, cache, "constructor"));
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const cache = try scope.object();
    const prototype = try scope.object();
    const queue = try scope.own(try @import("native_agent_queue.zig").constructor(engine));
    try scope.put(cache, "queue", queue);
    try scope.put(cache, "converter", try scope.own(try @import("native_agent_construct.zig").defaultConverter(engine)));
    const usage = try scope.own(try sdk.jsonObject(engine, "{\"input\":0,\"output\":0,\"cacheRead\":0,\"cacheWrite\":0,\"totalTokens\":0,\"cost\":{\"input\":0,\"output\":0,\"cacheRead\":0,\"cacheWrite\":0,\"total\":0}}"));
    try scope.put(cache, "usage", usage);
    var runtime_roots = [_]c.JSValue{runtime};
    const stream = try scope.own(try engine.checked(c.JS_NewCFunctionData2(engine.context, streamSimple, "streamSimple", 3, 0, runtime_roots.len, &runtime_roots)));
    try scope.put(cache, "defaultStream", stream);
    const getter = try scope.own(try engine.checked(c.JS_NewCFunction(engine.context, defaultStream, "getDefaultStreamFn", 0)));
    try scope.put(cache, "defaultGetter", getter);
    const constructor = try scope.own(try engine.checked(c.JS_NewCFunction2(engine.context, construct, "Agent", 1, c.JS_CFUNC_constructor, 0)));
    if (c.JS_SetConstructor(engine.context, constructor, prototype) < 0) return js.capture(engine);
    try scope.put(cache, "constructor", constructor);
    inline for (methods) |entry| {
        const callback = try scope.own(if (comptime entry.async_body) try switch (entry.body) {
            .prompt => @import("native_agent_prompt_async.zig").create(engine, .prompt),
            .continueRun => @import("native_agent_prompt_async.zig").create(engine, .continue_run),
            .runWithLifecycle => @import("native_agent_lifecycle_async.zig").create(engine),
            .handleRunFailure => @import("native_agent_failure_async.zig").create(engine, usage),
            .processEvents => @import("native_agent_events_async.zig").create(engine),
            else => @compileError("Agent async method requires its Source resumable body"),
        } else try engine.checked(c.pi_js_function_magic(engine.context, method, entry.name, entry.length, @intFromEnum(entry.body))));
        if (c.JS_DefinePropertyValueStr(engine.context, prototype, entry.name, c.JS_DupValue(engine.context, callback), c.JS_PROP_WRITABLE | c.JS_PROP_CONFIGURABLE) < 0) return js.capture(engine);
    }
    try accessor(engine, prototype, "state", .state, null);
    try accessor(engine, prototype, "steeringMode", .steeringMode, .setSteeringMode);
    try accessor(engine, prototype, "followUpMode", .followUpMode, .setFollowUpMode);
    try accessor(engine, prototype, "signal", .signal, null);
    engine.native_agent_core_cache = c.JS_DupValue(engine.context, cache);
    try scope.put(exports, "Agent", constructor);
}

fn construct(context: ?*c.JSContext, target: c.JSValue, argc: c_int, argv: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    return create(engine, target, if (argc > 0) argv[0] else c.pi_js_undefined()) catch |err| sdk.fail(engine, err);
}

fn create(engine: *em.Engine, target: c.JSValue, options: c.JSValue) !c.JSValue {
    const cache = engine.native_agent_core_cache orelse return error.NativeAgentCoreNotInitialized;
    const queue = try sdk.get(engine, cache, "queue");
    defer engine.freeValue(queue);
    const getter = try sdk.get(engine, cache, "defaultGetter");
    defer engine.freeValue(getter);
    const converter = try sdk.get(engine, cache, "converter");
    defer engine.freeValue(converter);
    return @import("native_agent_construct.zig").create(engine, target, options, queue, getter, converter);
}

fn defaultStream(context: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    return sdk.get(engine, engine.native_agent_core_cache orelse return sdk.fail(engine, error.NativeAgentCoreNotInitialized), "defaultStream") catch |err| sdk.fail(engine, err);
}

fn streamSimple(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    return js.invoke(engine, roots[0], "streamSimple", if (argc > 0) argv[0..@intCast(argc)] else &.{}) catch |err| sdk.fail(engine, err);
}

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
    createLoopConfig,
    runWithLifecycle,
    processEvents,
    handleRunFailure,
};
const Entry = struct { name: [:0]const u8, body: Body, length: c_int, async_body: bool = false };
const methods = [_]Entry{
    .{ .name = "subscribe", .body = .subscribe, .length = 1 },
    .{ .name = "steer", .body = .steer, .length = 1 },
    .{ .name = "followUp", .body = .followUp, .length = 1 },
    .{ .name = "clearSteeringQueue", .body = .clearSteeringQueue, .length = 0 },
    .{ .name = "clearFollowUpQueue", .body = .clearFollowUpQueue, .length = 0 },
    .{ .name = "clearAllQueues", .body = .clearAllQueues, .length = 0 },
    .{ .name = "hasQueuedMessages", .body = .hasQueuedMessages, .length = 0 },
    .{ .name = "peekQueuedMessages", .body = .peekQueuedMessages, .length = 0 },
    .{ .name = "abort", .body = .abort, .length = 0 },
    .{ .name = "waitForIdle", .body = .waitForIdle, .length = 0 },
    .{ .name = "reset", .body = .reset, .length = 0 },
    .{ .name = "prompt", .body = .prompt, .length = 2, .async_body = true },
    .{ .name = "continue", .body = .continueRun, .length = 0, .async_body = true },
    .{ .name = "normalizePromptInput", .body = .normalizePromptInput, .length = 2 },
    .{ .name = "createContextSnapshot", .body = .createContextSnapshot, .length = 0 },
    .{ .name = "createLoopConfig", .body = .createLoopConfig, .length = 0 },
    .{ .name = "runWithLifecycle", .body = .runWithLifecycle, .length = 1, .async_body = true },
    .{ .name = "handleRunFailure", .body = .handleRunFailure, .length = 2, .async_body = true },
    .{ .name = "finishRun", .body = .finishRun, .length = 0 },
    .{ .name = "processEvents", .body = .processEvents, .length = 1, .async_body = true },
};

fn accessor(engine: *em.Engine, prototype: c.JSValue, name: [:0]const u8, get: Body, set: ?Body) !void {
    const getter_name = try std.fmt.allocPrintSentinel(engine.gpa, "get {s}", .{name}, 0);
    defer engine.gpa.free(getter_name);
    const getter = try engine.checked(c.pi_js_function_magic(engine.context, method, getter_name, 0, @intFromEnum(get)));
    var consumed = false;
    errdefer if (!consumed) engine.freeValue(getter);
    const setter = if (set) |body| blk: {
        const setter_name = try std.fmt.allocPrintSentinel(engine.gpa, "set {s}", .{name}, 0);
        defer engine.gpa.free(setter_name);
        break :blk try engine.checked(c.pi_js_function_magic(engine.context, method, setter_name, 1, @intFromEnum(body)));
    } else c.pi_js_undefined();
    const atom = c.JS_NewAtom(engine.context, name);
    if (atom == c.JS_ATOM_NULL) {
        engine.freeValue(setter);
        return js.capture(engine);
    }
    defer c.JS_FreeAtom(engine.context, atom);
    consumed = true;
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
        .handleRunFailure => blk: {
            const cache = engine.native_agent_core_cache orelse return error.NativeAgentCoreNotInitialized;
            const usage = try sdk.get(engine, cache, "usage");
            defer engine.freeValue(usage);
            break :blk @import("native_agent_failure.zig").run(engine, agent, first, second, usage);
        },
        else => unreachable,
    };
}
