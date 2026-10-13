//! Actual SDK factory lexical callbacks over native collaborators.
//! The private agent box represents the factory's once-initialized Agent binding.
const std = @import("std");
const em = @import("engine.zig");
const js = @import("native_js_values.zig");
const sdk = @import("native_sdk.zig");
const temp = @import("native_sdk_prompt_scope.zig");
const Scope = temp.Scope;
const flow = @import("native_agent_async.zig");
const c = em.c;
const Body = enum(c_int) { buildRequestOptions, cacheContextIsCurrent, onPayload, onResponse, onProviderStreamEvent, transformContext, streamFn, getCacheMode, decideCacheWarming };
pub fn create(engine: *em.Engine, settings: c.JSValue, models: c.JSValue, manager: c.JSValue, runner_ref: c.JSValue, agent_box: c.JSValue, warmer: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const exports = try scope.object();
    var roots = [_]c.JSValue{ settings, models, manager, runner_ref, agent_box, warmer };
    inline for (std.meta.fields(Body)) |field| {
        const body: Body = @enumFromInt(field.value);
        const name: [:0]const u8 = switch (body) {
            .onPayload => "transformProviderPayload",
            .onResponse => "handleProviderResponse",
            .onProviderStreamEvent => "handleProviderStreamEvent",
            .getCacheMode, .decideCacheWarming => "",
            else => field.name,
        };
        const function = try scope.own(try engine.checked(c.JS_NewCFunctionData2(engine.context, callback, name, switch (body) {
            .onProviderStreamEvent => 2,
            .streamFn => 3,
            .getCacheMode => 0,
            else => 1,
        }, field.value, roots.len, &roots)));
        if (asynchronous(body)) {
            const parent = try scope.own(try engine.checked(c.JS_GetAsyncFunctionPrototype(engine.context)));
            if (c.JS_SetPrototype(engine.context, function, parent) < 0) return js.capture(engine);
        }
        try scope.put(exports, field.name, function);
    }
    return c.JS_DupValue(engine.context, exports);
}
fn asynchronous(body: Body) bool {
    return body != .buildRequestOptions and body != .cacheContextIsCurrent and body != .getCacheMode;
}
fn argument(args: []const c.JSValue, index: usize) c.JSValue {
    return if (index < args.len) args[index] else c.pi_js_undefined();
}
fn callback(context: ?*c.JSContext, _: c.JSValue, argc: c_int, args: [*c]c.JSValue, magic: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    const body: Body = @enumFromInt(magic);
    const arguments = if (argc > 0) args[0..@intCast(argc)] else &.{};
    if (asynchronous(body)) return begin(engine, arguments, roots[0..6], body) catch |err| sdk.fail(engine, err);
    return run(engine, arguments, roots[0..6], body, null) catch |err| sdk.fail(engine, err);
}
fn begin(engine: *em.Engine, args: []const c.JSValue, roots: []const c.JSValue, body: Body) !c.JSValue {
    const pending = try flow.create(engine, c.pi_js_undefined());
    defer engine.freeValue(pending.owner);
    errdefer engine.freeValue(pending.promise);
    var await_void = false;
    const value = run(engine, args, roots, body, &await_void) catch |err| {
        try flow.rejectError(engine, pending.owner, err);
        return pending.promise;
    };
    defer engine.freeValue(value);
    if (await_void) {
        try flow.wait(completedVoid, engine, pending.owner, value, 0);
    } else try flow.settle(engine, pending.owner, false, value);
    return pending.promise;
}
fn completedVoid(engine: *em.Engine, owner: c.JSValue, value: c.JSValue, rejected: bool, _: c_int) !void {
    try flow.settle(engine, owner, rejected, if (rejected) value else c.pi_js_undefined());
}
fn handler(scope: *Scope, runner: c.JSValue, name: []const u8) !bool {
    return !temp.nullish(runner) and scope.truthy(try scope.invoke(runner, "hasHandlers", &.{try scope.text(name)}));
}
fn run(engine: *em.Engine, args: []const c.JSValue, roots: []const c.JSValue, body: Body, await_void: ?*bool) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const first = argument(args, 0);
    const second = argument(args, 1);
    switch (body) {
        .buildRequestOptions => return buildOptions(engine, roots[0], roots[3], first, second),
        .cacheContextIsCurrent => return currentClosure(&scope, roots[4], first),
        .getCacheMode => return js.invoke(engine, roots[0], "getCacheWarmingMode", &.{}),
        .decideCacheWarming => {
            const runner = try scope.get(roots[3], "current");
            const chosen = if (temp.nullish(runner)) c.pi_js_undefined() else try scope.invoke(runner, "emitCacheWarmingDecision", &.{first});
            return c.JS_DupValue(engine.context, if (temp.nullish(chosen)) try scope.get(first, "action") else chosen);
        },
        .onPayload => {
            const runner = try scope.get(roots[3], "current");
            if (!try handler(&scope, runner, "before_provider_request")) return c.JS_DupValue(engine.context, first);
            return js.invoke(engine, runner, "emitBeforeProviderRequest", &.{first});
        },
        .transformContext => {
            const runner = try scope.get(roots[3], "current");
            if (!scope.truthy(runner)) return c.JS_DupValue(engine.context, first);
            return js.invoke(engine, runner, "emitContext", &.{first});
        },
        .onResponse, .onProviderStreamEvent => {
            const runner = try scope.get(roots[3], "current");
            if (!try handler(&scope, runner, if (body == .onResponse) "after_provider_response" else "provider_stream_event")) return c.pi_js_undefined();
            const emit = try scope.get(runner, "emit");
            const event = try scope.object();
            if (body == .onResponse) {
                try scope.put(event, "type", try scope.text("after_provider_response"));
                try scope.put(event, "status", try scope.get(first, "status"));
                try scope.put(event, "headers", try scope.get(first, "headers"));
            } else {
                try scope.put(event, "data", first);
                try scope.put(event, "type", try scope.text("provider_stream_event"));
                try scope.put(event, "provider", try scope.get(second, "provider"));
                try scope.put(event, "api", try scope.get(second, "api"));
                try scope.put(event, "model", try scope.get(second, "id"));
            }
            if (await_void) |flag| flag.* = true;
            return js.call(engine, emit, runner, &.{event});
        },
        .streamFn => {
            const options = argument(args, 2);
            const configured = try scope.own(try buildOptions(engine, roots[0], roots[3], first, options));
            const session_id = if (temp.nullish(options)) c.pi_js_undefined() else try scope.get(options, "sessionId");
            if (scope.equal(session_id, try scope.invoke(roots[2], "getSessionId", &.{}))) {
                const start = try scope.get(roots[5], "start");
                const request = try scope.object();
                try scope.put(request, "model", first);
                try scope.put(request, "context", second);
                try scope.put(request, "options", configured);
                const prefix_matches = try scope.own(try currentClosure(&scope, roots[4], first));
                _ = try scope.call(start, roots[5], &.{ request, prefix_matches });
            }
            return js.invoke(engine, roots[1], "streamSimple", &.{ first, second, configured });
        },
    }
}
fn nullishDefault(scope: *Scope, target: c.JSValue, name: [*:0]const u8, fallback: c.JSValue) !c.JSValue {
    const value = try scope.get(target, name);
    return if (temp.nullish(value)) fallback else value;
}
fn buildOptions(engine: *em.Engine, settings: c.JSValue, runner_ref: c.JSValue, model: c.JSValue, supplied: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const options = if (c.JS_IsUndefined(supplied)) try scope.object() else supplied;
    const retry = try scope.invoke(settings, "getProviderRetrySettings", &.{});
    const idle = try scope.invoke(settings, "getHttpIdleTimeoutMs", &.{});
    const effective = if (scope.equal(idle, c.JS_NewInt32(engine.context, 0))) c.JS_NewInt32(engine.context, 2147483647) else idle;
    const runner = try scope.get(runner_ref, "current");
    const result = try scope.own(try js.spread(engine, options));
    var timeout = try scope.get(options, "timeoutMs");
    if (temp.nullish(timeout)) timeout = try nullishDefault(&scope, retry, "timeoutMs", effective);
    try scope.put(result, "timeoutMs", timeout);
    var websocket = try scope.get(options, "websocketConnectTimeoutMs");
    if (temp.nullish(websocket)) websocket = try scope.invoke(settings, "getWebSocketConnectTimeoutMs", &.{});
    try scope.put(result, "websocketConnectTimeoutMs", websocket);
    var retries = try scope.get(options, "maxRetries");
    if (temp.nullish(retries)) retries = try scope.get(retry, "maxRetries");
    try scope.put(result, "maxRetries", retries);
    var maximum = try scope.get(options, "maxRetryDelayMs");
    if (temp.nullish(maximum)) maximum = try scope.get(retry, "maxRetryDelayMs");
    try scope.put(result, "maxRetryDelayMs", maximum);
    var roots = [_]c.JSValue{ model, settings, options, runner };
    const transform = try scope.own(try engine.checked(c.JS_NewCFunctionData2(engine.context, transformHeaders, "transformHeaders", 1, 0, roots.len, &roots)));
    const parent = try scope.own(try engine.checked(c.JS_GetAsyncFunctionPrototype(engine.context)));
    if (c.JS_SetPrototype(engine.context, transform, parent) < 0) return js.capture(engine);
    try scope.put(result, "transformHeaders", transform);
    return c.JS_DupValue(engine.context, result);
}
fn transformHeaders(context: ?*c.JSContext, _: c.JSValue, argc: c_int, args: [*c]c.JSValue, _: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    return headersPromise(engine, if (argc > 0) args[0] else c.pi_js_undefined(), roots[0..4]) catch |err| sdk.fail(engine, err);
}
fn headersPromise(engine: *em.Engine, headers: c.JSValue, roots: []const c.JSValue) !c.JSValue {
    const pending = try flow.create(engine, c.pi_js_undefined());
    defer engine.freeValue(pending.owner);
    errdefer engine.freeValue(pending.promise);
    const value = headersValue(engine, headers, roots) catch |err| {
        try flow.rejectError(engine, pending.owner, err);
        return pending.promise;
    };
    defer engine.freeValue(value);
    try flow.settle(engine, pending.owner, false, value);
    return pending.promise;
}
fn headersValue(engine: *em.Engine, request: c.JSValue, roots: []const c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const session_id = try scope.get(roots[2], "sessionId");
    const merged = try scope.own(try @import("native_provider_attribution.zig").merge(engine, roots[0], roots[1], session_id, &.{request}));
    if (try handler(&scope, roots[3], "before_provider_headers")) {
        const function = try scope.get(roots[3], "emitBeforeProviderHeaders");
        return js.call(engine, function, roots[3], &.{if (temp.nullish(merged)) try scope.object() else merged});
    }
    return c.JS_DupValue(engine.context, if (temp.nullish(merged)) try scope.object() else merged);
}
fn currentClosure(scope: *Scope, agent_box: c.JSValue, model: c.JSValue) !c.JSValue {
    const agent = try scope.get(agent_box, "value");
    const messages = try scope.get(try scope.get(agent, "state"), "messages");
    var roots = [_]c.JSValue{ agent, model, messages };
    return scope.engine.checked(c.JS_NewCFunctionData2(scope.engine.context, current, "", 0, 0, roots.len, &roots));
}
fn current(context: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue, _: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    const result = isCurrent(engine, roots[0..3]) catch |err| return sdk.fail(engine, err);
    return c.pi_js_bool(engine.context, @intFromBool(result));
}
fn isCurrent(engine: *em.Engine, roots: []const c.JSValue) !bool {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const agent = roots[0];
    const selected = try scope.get(try scope.get(agent, "state"), "model");
    const messages = try scope.get(try scope.get(agent, "state"), "messages");
    if (!scope.equal(try scope.get(selected, "provider"), try scope.get(roots[1], "provider")) or
        !scope.equal(try scope.get(selected, "id"), try scope.get(roots[1], "id"))) return false;
    const bound = try scope.own(try engine.checked(c.JS_PiBinaryOperator(engine.context, 5, try scope.get(roots[2], "length"), try scope.get(messages, "length"))));
    if (!scope.truthy(bound)) return false;
    const every = try scope.get(roots[2], "every");
    var captures = [_]c.JSValue{messages};
    const match = try scope.own(try engine.checked(c.JS_NewCFunctionData2(engine.context, messageMatches, "", 2, 0, captures.len, &captures)));
    return scope.truthy(try scope.call(every, roots[2], &.{match}));
}
fn messageMatches(context: ?*c.JSContext, _: c.JSValue, argc: c_int, args: [*c]c.JSValue, _: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    const indexed = js.getKey(engine, roots[0], if (argc > 1) args[1] else c.pi_js_undefined()) catch |err| return sdk.fail(engine, err);
    defer engine.freeValue(indexed);
    return c.pi_js_bool(engine.context, @intFromBool(c.JS_IsStrictEqual(engine.context, indexed, if (argc > 0) args[0] else c.pi_js_undefined())));
}
