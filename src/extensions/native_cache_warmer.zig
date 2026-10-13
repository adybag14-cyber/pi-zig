//! Complete Source CacheWarmer scheduling and ordinary observable class state.
//! Async refresh continuations live in native_cache_warmer_refresh.zig.
const std = @import("std");
const em = @import("engine.zig");
const js = @import("native_js_values.zig");
const sdk = @import("native_sdk.zig");
const values = @import("native_cache_warming_values.zig");
const temp = @import("native_sdk_prompt_scope.zig");
const Scope = temp.Scope;
const c = em.c;
const Method = enum(c_int) { status, start, onAgentSettled, onModeChanged, cancel, clearRun, stop, schedule, refresh, refreshDeadlineMissed, validateRun, getModeStopReason, evaluate };
const Export = enum(c_int) { getCacheWarmingDelayMs, getPromptCacheTtlMs, isReplayable, formatCacheWarmingStatus, formatCacheWarmingUsage };
pub fn createBindings(engine: *em.Engine) !c.JSValue {
    if (engine.native_cache_warmer_bindings) |bindings| return c.JS_DupValue(engine.context, bindings);
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const exports = try scope.object();
    const env = try scope.own(try @import("native_provider_env.zig").create(engine));
    inline for (std.meta.fields(Export)) |field| {
        const function = try scope.own(try @import("native_node_function.zig").create(engine, field.name, if (field.value == 1 or field.value == 2) 2 else 1, exported, &.{ c.JS_NewInt32(engine.context, field.value), env }));
        try scope.put(exports, field.name, function);
    }
    const prototype = try scope.object();
    const constructor = try scope.own(try @import("native_class.zig").constructor(engine, "CacheWarmer", 3, prototype, construct, &.{env}));
    inline for (std.meta.fields(Method)) |field| {
        const operation: Method = @enumFromInt(field.value);
        var roots = [_]c.JSValue{env};
        const function = try scope.own(try engine.checked(c.JS_NewCFunctionData2(engine.context, method, if (operation == .status) "get status" else field.name, switch (operation) {
            .status, .onAgentSettled, .onModeChanged, .cancel, .clearRun => 0,
            .start, .stop => 2,
            else => 1,
        }, field.value, roots.len, &roots)));
        if (operation == .status) {
            const atom = c.JS_NewAtom(engine.context, "status");
            defer c.JS_FreeAtom(engine.context, atom);
            if (c.JS_DefinePropertyGetSet(engine.context, prototype, atom, c.JS_DupValue(engine.context, function), c.pi_js_undefined(), c.JS_PROP_CONFIGURABLE) < 0) return js.capture(engine);
        } else {
            if (operation == .refresh) {
                const parent = try scope.own(try engine.checked(c.JS_GetAsyncFunctionPrototype(engine.context)));
                if (c.JS_SetPrototype(engine.context, function, parent) < 0) return js.capture(engine);
            }
            if (c.JS_DefinePropertyValueStr(engine.context, prototype, field.name, c.JS_DupValue(engine.context, function), c.JS_PROP_CONFIGURABLE | c.JS_PROP_WRITABLE) < 0) return js.capture(engine);
        }
    }
    try scope.put(exports, "CacheWarmer", constructor);
    engine.native_cache_warmer_bindings = c.JS_DupValue(engine.context, exports);
    return c.JS_DupValue(engine.context, exports);
}
fn arg(args: []const c.JSValue, index: usize) c.JSValue {
    return if (index < args.len) args[index] else c.pi_js_undefined();
}
fn exported(engine: *em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    var mode: i32 = 0;
    if (c.JS_ToInt32(engine.context, &mode, roots[0]) < 0) return js.capture(engine);
    const value = switch (@as(Export, @enumFromInt(mode))) {
        .getCacheWarmingDelayMs => try values.delay(&scope, arg(args, 0)),
        .getPromptCacheTtlMs => try values.ttl(&scope, arg(args, 0), arg(args, 1), roots[1]),
        .isReplayable => c.pi_js_bool(engine.context, @intFromBool(try values.replayable(&scope, arg(args, 0), arg(args, 1)))),
        .formatCacheWarmingStatus => try @import("native_cache_warming_format.zig").status(&scope, arg(args, 0), if (c.JS_IsUndefined(arg(args, 1))) try values.now(&scope) else arg(args, 1)),
        .formatCacheWarmingUsage => try @import("native_cache_warming_format.zig").usage(&scope, arg(args, 0)),
    };
    return c.JS_DupValue(engine.context, value);
}
fn defaultDecide(context: ?*c.JSContext, _: c.JSValue, argc: c_int, args: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    return defaultDecision(engine, if (argc > 0) args[0] else c.pi_js_undefined()) catch |err| sdk.fail(engine, err);
}
fn defaultDecision(engine: *em.Engine, event: c.JSValue) !c.JSValue {
    const flow = @import("native_agent_async.zig");
    const pending = try flow.create(engine, c.pi_js_undefined());
    defer engine.freeValue(pending.owner);
    errdefer engine.freeValue(pending.promise);
    const action = sdk.get(engine, event, "action") catch |err| {
        try flow.rejectError(engine, pending.owner, err);
        return pending.promise;
    };
    defer engine.freeValue(action);
    try flow.settle(engine, pending.owner, false, action);
    return pending.promise;
}
fn construct(engine: *em.Engine, target: c.JSValue, args: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const receiver = try scope.own(try @import("native_class.zig").object(engine, target));
    inline for (.{ "run", "inactive", "models", "sessionManager", "getMode", "decide", "onWarmed" }) |name| try scope.put(receiver, name, c.pi_js_undefined());
    try scope.set(receiver, "models", arg(args, 0));
    try scope.set(receiver, "sessionManager", arg(args, 1));
    try scope.set(receiver, "getMode", arg(args, 2));
    var decide = arg(args, 3);
    if (c.JS_IsUndefined(decide)) {
        decide = try scope.own(try engine.checked(c.JS_NewCFunction(engine.context, defaultDecide, "decide", 1)));
        const parent = try scope.own(try engine.checked(c.JS_GetAsyncFunctionPrototype(engine.context)));
        if (c.JS_SetPrototype(engine.context, decide, parent) < 0) return js.capture(engine);
    }
    try scope.set(receiver, "decide", decide);
    try scope.set(receiver, "inactive", try inactive(&scope, "waiting for first request"));
    return c.JS_DupValue(engine.context, receiver);
}
fn inactive(scope: *Scope, reason: []const u8) !c.JSValue {
    const result = try scope.object();
    try scope.put(result, "state", try scope.text("inactive"));
    try scope.put(result, "reason", try scope.text(reason));
    return result;
}
fn method(context: ?*c.JSContext, receiver: c.JSValue, argc: c_int, args: [*c]c.JSValue, magic: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    const arguments = if (argc > 0) args[0..@intCast(argc)] else &.{};
    const operation: Method = @enumFromInt(magic);
    if (operation == .refresh) return @import("native_cache_warmer_refresh.zig").begin(engine, receiver, arg(arguments, 0)) catch |err| sdk.fail(engine, err);
    return dispatch(engine, receiver, arguments, roots[0], operation) catch |err| sdk.fail(engine, err);
}
fn stopped(scope: *Scope, receiver: c.JSValue, reason: []const u8) !void {
    _ = try scope.invoke(receiver, "stop", &.{try scope.text(reason)});
}
fn dispatch(engine: *em.Engine, receiver: c.JSValue, args: []const c.JSValue, env: c.JSValue, operation: Method) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    switch (operation) {
        .start => try start(&scope, receiver, arg(args, 0), arg(args, 1), env),
        .cancel => try stopped(&scope, receiver, "inactive"),
        .clearRun => {
            const run = try scope.get(receiver, "run");
            if (scope.truthy(run)) {
                try scope.set(receiver, "run", c.pi_js_undefined());
                const timer = try scope.get(run, "timer");
                if (scope.truthy(timer)) _ = try scope.call(try scope.global("clearTimeout"), c.pi_js_undefined(), &.{timer});
                _ = try scope.invoke(try scope.get(run, "controller"), "abort", &.{});
            }
        },
        .stop => {
            _ = try scope.invoke(receiver, "clearRun", &.{});
            const stopped_status = try scope.object();
            try scope.put(stopped_status, "state", try scope.text("inactive"));
            try scope.put(stopped_status, "reason", arg(args, 0));
            try js.spreadInto(engine, stopped_status, arg(args, 1));
            try scope.set(receiver, "inactive", stopped_status);
        },
        .schedule => try schedule(&scope, receiver, arg(args, 0)),
        .onAgentSettled => {
            const run = try scope.get(receiver, "run");
            if (!scope.truthy(run)) return c.pi_js_undefined();
            if (try values.is(&scope, try scope.invoke(receiver, "getMode", &.{}), "streaming")) {
                try stopped(&scope, receiver, "agent run settled");
            } else {
                try scope.set(run, "phase", try scope.text("idle"));
                const deadline = try values.binary(&scope, .add, try scope.get(run, "startedAt"), c.JS_NewInt32(engine.context, 1800000));
                if (try values.compare(&scope, .greater, try scope.get(run, "nextWarmAt"), deadline) or try values.compare(&scope, .greater_equal, try values.now(&scope), deadline)) try stopped(&scope, receiver, "30-minute idle safety limit reached");
            }
        },
        .onModeChanged => {
            const run = try scope.get(receiver, "run");
            if (!scope.truthy(run)) return c.pi_js_undefined();
            const reason = try scope.invoke(receiver, "getModeStopReason", &.{run});
            if (scope.truthy(reason)) _ = try scope.invoke(receiver, "stop", &.{reason});
        },
        .getModeStopReason => {
            const mode = try scope.invoke(receiver, "getMode", &.{});
            if (try values.is(&scope, mode, "off")) return sdk.text(engine, "cache warming disabled");
            if (try values.is(&scope, mode, "streaming") and try values.is(&scope, try scope.get(arg(args, 0), "phase"), "idle")) return sdk.text(engine, "agent run settled");
        },
        .refreshDeadlineMissed => {
            if (try values.compare(&scope, .less_equal, try values.now(&scope), try scope.get(arg(args, 0), "refreshDeadlineAt"))) return c.pi_js_bool(engine.context, 0);
            try stopped(&scope, receiver, "cache refresh deadline missed");
            return c.pi_js_bool(engine.context, 1);
        },
        .validateRun => {
            const run = arg(args, 0);
            if (!scope.equal(try scope.get(receiver, "run"), run)) return c.pi_js_bool(engine.context, 0);
            var reason = try scope.invoke(receiver, "getModeStopReason", &.{run});
            if (temp.nullish(reason)) reason = if (!scope.truthy(try scope.invoke(run, "isCurrent", &.{}))) try scope.text("conversation context changed") else c.pi_js_undefined();
            if (!scope.truthy(reason)) return c.pi_js_bool(engine.context, 1);
            _ = try scope.invoke(receiver, "stop", &.{reason});
            return c.pi_js_bool(engine.context, 0);
        },
        .evaluate => return c.JS_DupValue(engine.context, try values.evaluate(&scope, receiver, arg(args, 0))),
        .status => return status(&scope, receiver),
        .refresh => unreachable,
    }
    return c.pi_js_undefined();
}
fn status(scope: *Scope, receiver: c.JSValue) !c.JSValue {
    const engine = scope.engine;
    if (try values.is(scope, try scope.invoke(receiver, "getMode", &.{}), "off")) return c.JS_DupValue(engine.context, try inactive(scope, "cache warming disabled"));
    const run = try scope.get(receiver, "run");
    if (!scope.truthy(run)) return c.JS_DupValue(engine.context, try scope.get(receiver, "inactive"));
    if (!scope.truthy(try scope.invoke(run, "isCurrent", &.{}))) return c.JS_DupValue(engine.context, try inactive(scope, "conversation context changed"));
    const decision = try scope.invoke(receiver, "evaluate", &.{run});
    const refreshing = c.JS_IsUndefined(try scope.get(run, "timer"));
    if (!scope.truthy(try scope.get(decision, "economicsAvailable")) and !refreshing) return c.JS_DupValue(engine.context, try inactive(scope, "cache economics unavailable"));
    const result = try scope.object();
    try scope.put(result, "state", try scope.text(if (refreshing) "refreshing" else "scheduled"));
    try scope.put(result, "nextWarmAt", try scope.get(run, "nextWarmAt"));
    try scope.put(result, "decision", decision);
    try scope.put(result, "extensionOverride", try scope.get(run, "extensionOverride"));
    return c.JS_DupValue(engine.context, result);
}
fn start(scope: *Scope, receiver: c.JSValue, request: c.JSValue, is_current: c.JSValue, env: c.JSValue) !void {
    const engine = scope.engine;
    _ = try scope.invoke(receiver, "clearRun", &.{});
    const mode = try scope.invoke(receiver, "getMode", &.{});
    if (try values.is(scope, mode, "off")) return stopped(scope, receiver, "cache warming disabled");
    if (!try values.replayable(scope, try scope.get(request, "model"), try scope.get(request, "options"))) return stopped(scope, receiver, "request cannot be replayed safely");
    const lifetime = try values.ttl(scope, try scope.get(request, "model"), try scope.get(request, "options"), env);
    if (c.JS_IsUndefined(lifetime)) return stopped(scope, receiver, if (try values.is(scope, try scope.get(try scope.get(request, "options"), "cacheRetention"), "none")) "request disabled prompt caching" else "cache lifetime unavailable");
    const delay = try values.delay(scope, lifetime);
    if (c.JS_IsUndefined(delay)) return stopped(scope, receiver, "cache lifetime unavailable");
    const run = try scope.own(try js.spread(engine, request));
    try scope.put(run, "isCurrent", is_current);
    try scope.put(run, "ttlMs", lifetime);
    try scope.put(run, "delayMs", delay);
    try scope.put(run, "refreshDeadlineAt", c.JS_NewInt32(engine.context, 0));
    try scope.put(run, "startedAt", try values.now(scope));
    try scope.put(run, "controller", try scope.own(try js.builtin(engine, "AbortController", &.{})));
    try scope.put(run, "phase", try scope.text("streaming"));
    try scope.put(run, "nextWarmAt", c.JS_NewInt32(engine.context, 0));
    try scope.put(run, "extensionOverride", c.pi_js_bool(engine.context, 0));
    try scope.set(receiver, "run", run);
    _ = try scope.invoke(receiver, "schedule", &.{try scope.get(receiver, "run")});
}
fn scheduled(context: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue, _: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    const pending = js.invoke(engine, roots[0], "refresh", &.{roots[1]}) catch |err| return sdk.fail(engine, err);
    engine.freeValue(pending);
    return c.pi_js_undefined();
}
fn schedule(scope: *Scope, receiver: c.JSValue, run: c.JSValue) !void {
    const engine = scope.engine;
    try scope.set(run, "extensionOverride", c.pi_js_bool(engine.context, 0));
    try scope.set(run, "nextWarmAt", try values.binary(scope, .add, try values.now(scope), try scope.get(run, "delayMs")));
    const next = try scope.get(run, "nextWarmAt");
    const math = try scope.global("Math");
    const floor = try scope.get(math, "floor");
    const remaining = try values.binary(scope, .subtract, try scope.get(run, "ttlMs"), try scope.get(run, "delayMs"));
    const half = try scope.call(floor, math, &.{try values.binary(scope, .divide, remaining, c.JS_NewInt32(engine.context, 2))});
    try scope.set(run, "refreshDeadlineAt", try values.binary(scope, .add, next, half));
    const idle = try values.is(scope, try scope.get(run, "phase"), "idle");
    const deadline = try values.binary(scope, .add, try scope.get(run, "startedAt"), c.JS_NewInt32(engine.context, if (idle) 1800000 else 3600000));
    if (try values.compare(scope, .greater, try scope.get(run, "nextWarmAt"), deadline) or try values.compare(scope, .greater_equal, try values.now(scope), deadline)) return stopped(scope, receiver, if (try values.is(scope, try scope.get(run, "phase"), "idle")) "30-minute idle safety limit reached" else "one-hour safety limit reached");
    const set_timeout = try scope.global("setTimeout");
    var roots = [_]c.JSValue{ receiver, run };
    const callback = try scope.own(try engine.checked(c.JS_NewCFunctionData2(engine.context, scheduled, "", 0, 0, roots.len, &roots)));
    const delay_math = try scope.global("Math");
    const max = try scope.get(delay_math, "max");
    const delay = try scope.call(max, delay_math, &.{ c.JS_NewInt32(engine.context, 0), try values.binary(scope, .subtract, try scope.get(run, "nextWarmAt"), try values.now(scope)) });
    try scope.set(run, "timer", try scope.call(set_timeout, c.pi_js_undefined(), &.{ callback, delay }));
    const timer = try scope.get(run, "timer");
    const unref = try scope.get(timer, "unref");
    if (!temp.nullish(unref)) _ = try scope.call(unref, timer, &.{});
}
