//! Original session idle/cancellation/disposal and ordinary queue-mode control.
const std = @import("std");
const em = @import("engine.zig");
const sdk = @import("native_sdk.zig");
const js = @import("native_js_values.zig");
const temp = @import("native_sdk_prompt_scope.zig");
const Scope = temp.Scope;
const async_body = @import("native_async_body.zig");
const native = async_body.native;
const c = em.c;
const Method = enum(c_int) { _getIdleWaitPromise, _resolveIdleWaitIfIdle, _disconnectFromAgent, dispose, refreshContext, clearQueue, abort, waitForIdle, syncQueueModesFromSettings, setSteeringMode, setFollowUpMode, abortCompaction, abortBranchSummary, abortRetry, abortBash, _flushPendingBashMessages, setSessionName, setAutoRetryEnabled, setAutoCompactionEnabled };
pub fn install(engine: *em.Engine, prototype: c.JSValue) !void {
    const resources = try @import("native_ai_session_resources.zig").bindings(engine);
    defer engine.freeValue(resources);
    const cleanup = try sdk.get(engine, resources, "cleanupSessionResources");
    defer engine.freeValue(cleanup);
    inline for (std.meta.fields(Method)) |field| {
        const method: Method = @enumFromInt(field.value);
        if (method == .abort or method == .waitForIdle) {
            const Adapter = struct {
                fn body(host: *em.Engine, session: c.JSValue, _: []const c.JSValue, _: []const c.JSValue, state: *c.JSValue, completion: native.Completion, input: c.JSValue) !native.Action {
                    const generation = host.native_allocation_generation;
                    return asyncBody(host, session, method, state, completion, input) catch |err| {
                        try trustedBoundary(host, err, generation);
                        return async_body.failureSince(host, err, generation);
                    };
                }
            };
            const function = try native.createResumable(engine, field.name, 0, Adapter.body, &.{});
            defer engine.freeValue(function);
            if (c.JS_DefinePropertyValueStr(engine.context, prototype, field.name, c.JS_DupValue(engine.context, function), c.JS_PROP_WRITABLE | c.JS_PROP_CONFIGURABLE) < 0) return js.capture(engine);
            continue;
        }
        var roots = [_]c.JSValue{cleanup};
        const function = try engine.checked(c.JS_NewCFunctionData2(engine.context, dispatch, field.name, switch (method) {
            .setSteeringMode, .setFollowUpMode, .setSessionName, .setAutoRetryEnabled, .setAutoCompactionEnabled => 1,
            else => 0,
        }, field.value, roots.len, &roots));
        defer engine.freeValue(function);
        if (c.JS_DefinePropertyValueStr(engine.context, prototype, field.name, c.JS_DupValue(engine.context, function), c.JS_PROP_WRITABLE | c.JS_PROP_CONFIGURABLE) < 0) return js.capture(engine);
    }
}
fn dispatch(context: ?*c.JSContext, session: c.JSValue, argc: c_int, argv: [*c]c.JSValue, magic: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    engine.native_exception_diagnostics_suppressed += 1;
    defer engine.native_exception_diagnostics_suppressed -= 1;
    const method: Method = @enumFromInt(magic);
    return invoke(engine, session, method, if (argc > 0) argv[0] else c.pi_js_undefined(), roots[0]) catch |err| sdk.fail(engine, err);
}
fn invoke(engine: *em.Engine, session: c.JSValue, method: Method, value: c.JSValue, cleanup: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    switch (method) {
        ._getIdleWaitPromise => {
            if (!scope.truthy(try scope.get(session, "_idleWaitPromise"))) {
                const constructor = try scope.global("Promise");
                var roots = [_]c.JSValue{session};
                var args = [_]c.JSValue{try scope.own(try engine.checked(c.JS_NewCFunctionData2(engine.context, idleExecutor, "", 1, 0, roots.len, &roots)))};
                const promise = try scope.own(try engine.checked(c.JS_CallConstructor(engine.context, constructor, args.len, &args)));
                try scope.set(session, "_idleWaitPromise", promise);
            }
            return sdk.get(engine, session, "_idleWaitPromise");
        },
        ._resolveIdleWaitIfIdle => {
            if (!scope.truthy(try scope.get(session, "isIdle")) or !scope.truthy(try scope.get(session, "_resolveIdleWait"))) return c.pi_js_undefined();
            const resolve = try scope.get(session, "_resolveIdleWait");
            try scope.set(session, "_idleWaitPromise", c.pi_js_undefined());
            try scope.set(session, "_resolveIdleWait", c.pi_js_undefined());
            _ = try scope.call(resolve, c.pi_js_undefined(), &.{});
        },
        ._disconnectFromAgent => {
            if (scope.truthy(try scope.get(session, "_unsubscribeAgent"))) {
                _ = try scope.invoke(session, "_unsubscribeAgent", &.{});
                try scope.set(session, "_unsubscribeAgent", c.pi_js_undefined());
            }
        },
        .dispose => try dispose(&scope, session, cleanup),
        .refreshContext => {
            _ = try scope.invoke(session, "_refreshFinalizedContext", &.{});
        },
        .clearQueue => {
            const steering = try scope.own(try @import("native_iterator_spread.zig").snapshot(engine, try scope.get(session, "_steeringMessages")));
            const follow_up = try scope.own(try @import("native_iterator_spread.zig").snapshot(engine, try scope.get(session, "_followUpMessages")));
            try scope.set(session, "_steeringMessages", try scope.array());
            try scope.set(session, "_followUpMessages", try scope.array());
            _ = try scope.invoke(try scope.get(session, "agent"), "clearAllQueues", &.{});
            _ = try scope.invoke(session, "_emitQueueUpdate", &.{});
            const result = try scope.object();
            try scope.put(result, "steering", steering);
            try scope.put(result, "followUp", follow_up);
            return c.JS_DupValue(engine.context, result);
        },
        .syncQueueModesFromSettings => {
            inline for (.{ "steeringMode", "followUpMode" }, .{ "getSteeringMode", "getFollowUpMode" }) |property, getter| {
                const agent = try scope.get(session, "agent");
                const setting = try scope.invoke(try scope.get(session, "settingsManager"), getter, &.{});
                try scope.set(agent, property, setting);
            }
        },
        .setSteeringMode, .setFollowUpMode => {
            try scope.set(try scope.get(session, "agent"), if (method == .setSteeringMode) "steeringMode" else "followUpMode", value);
            _ = try scope.invoke(try scope.get(session, "settingsManager"), if (method == .setSteeringMode) "setSteeringMode" else "setFollowUpMode", &.{value});
        },
        .abortCompaction => {
            try optionalAbort(&scope, try scope.get(session, "_compactionAbortController"));
            try optionalAbort(&scope, try scope.get(session, "_autoCompactionAbortController"));
        },
        .abortBranchSummary, .abortRetry => try optionalAbort(&scope, try scope.get(session, if (method == .abortBranchSummary) "_branchSummaryAbortController" else "_retryAbortController")),
        .abortBash => {
            const controllers = try scope.own(try @import("native_iterator_spread.zig").snapshot(engine, try scope.get(session, "_bashAbortControllers")));
            const count = try sdk.length(engine, controllers);
            for (0..count) |index| {
                const controller = try scope.own(try engine.checked(c.JS_GetPropertyUint32(engine.context, controllers, @intCast(index))));
                _ = try scope.invoke(controller, "abort", &.{});
            }
        },
        ._flushPendingBashMessages => {
            const count = try scope.get(try scope.get(session, "_pendingBashMessages"), "length");
            if (scope.equal(count, c.JS_NewInt32(engine.context, 0))) return c.pi_js_undefined();
            const messages = try scope.get(session, "_pendingBashMessages");
            const symbol = try scope.own(try engine.checked(c.JS_GetIteratorSymbol(engine.context)));
            var iterator = try js.Iterator.init(engine, messages, symbol);
            defer iterator.deinit();
            errdefer iterator.closePreserving();
            while (try iterator.next()) |message| {
                defer engine.freeValue(message);
                _ = try scope.invoke(try scope.get(session, "sessionManager"), "appendMessage", &.{message});
            }
            try scope.set(session, "_pendingBashMessages", try scope.array());
            _ = try scope.invoke(session, "_refreshFinalizedContext", &.{});
        },
        .setSessionName => {
            _ = try scope.invoke(try scope.get(session, "sessionManager"), "appendSessionInfo", &.{value});
            const event = try scope.object();
            try scope.put(event, "type", try scope.text("session_info_changed"));
            try scope.put(event, "name", try scope.invoke(try scope.get(session, "sessionManager"), "getSessionName", &.{}));
            _ = try scope.invoke(session, "_emit", &.{event});
            _ = try scope.invoke(try scope.get(session, "_extensionRunner"), "emit", &.{event});
        },
        .setAutoRetryEnabled, .setAutoCompactionEnabled => {
            _ = try scope.invoke(try scope.get(session, "settingsManager"), if (method == .setAutoRetryEnabled) "setRetryEnabled" else "setCompactionEnabled", &.{value});
        },
        .abort, .waitForIdle => unreachable,
    }
    return c.pi_js_undefined();
}
fn optionalAbort(scope: *Scope, controller: c.JSValue) !void {
    if (!temp.nullish(controller)) _ = try scope.invoke(controller, "abort", &.{});
}
fn idleExecutor(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    if (c.JS_SetPropertyStr(engine.context, roots[0], "_resolveIdleWait", if (argc > 0) c.JS_DupValue(engine.context, argv[0]) else c.pi_js_undefined()) < 0) return sdk.fail(engine, js.capture(engine));
    return c.pi_js_undefined();
}
fn dispose(scope: *Scope, session: c.JSValue, cleanup: c.JSValue) !void {
    const engine = scope.engine;
    const generation = engine.native_allocation_generation;
    disposeAbort(scope, session) catch |err| {
        if (engine.nativeAllocationError(err, generation) == error.OutOfMemory) return error.OutOfMemory;
    };
    const stale = "This extension ctx is stale after session replacement or reload. Do not use a captured pi or command ctx after ctx.newSession(), ctx.fork(), ctx.switchSession(), or ctx.reload(). For newSession, fork, and switchSession, move post-replacement work into withSession and use the ctx passed to withSession. For reload, do not use the old ctx after await ctx.reload().";
    _ = try scope.invoke(try scope.get(session, "_extensionRunner"), "invalidate", &.{try scope.text(stale)});
    _ = try scope.invoke(session, "_disconnectFromAgent", &.{});
    try scope.set(session, "_eventListeners", try scope.array());
    if (scope.truthy(try scope.get(session, "_cacheWarmer"))) {
        try scope.set(try scope.get(session, "_cacheWarmer"), "onWarmed", c.pi_js_undefined());
        _ = try scope.invoke(try scope.get(session, "_cacheWarmer"), "cancel", &.{});
    }
    _ = try scope.call(cleanup, c.pi_js_undefined(), &.{try scope.get(session, "sessionId")});
}
fn disposeAbort(scope: *Scope, session: c.JSValue) !void {
    inline for (.{ "abortRetry", "abortCompaction", "abortBranchSummary", "abortBash" }) |name| _ = try scope.invoke(session, name, &.{});
    _ = try scope.invoke(try scope.get(session, "agent"), "abort", &.{});
}
fn trustedBoundary(engine: *em.Engine, err: anyerror, generation: u64) !void {
    if (err == error.OutOfMemory) return err;
    if (err == error.JavaScriptException) if (engine.captured_exception) |reason| {
        try async_body.rethrowRecognizedAllocation(engine, reason, generation);
    };
}
fn asyncBody(engine: *em.Engine, session: c.JSValue, method: Method, state: *c.JSValue, completion: native.Completion, input: c.JSValue) !native.Action {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    if (completion != .start) {
        if (completion == .rejected) {
            try async_body.enterRejectedContinuation(engine);
            return .{ .thrown = c.JS_DupValue(engine.context, input) };
        }
        return .{ .returned = c.pi_js_undefined() };
    }
    _ = try async_body.init(&scope, state);
    if (method == .abort) {
        if (scope.truthy(try scope.get(session, "_isAgentRunActive"))) try scope.set(session, "_agentRunAbortRequested", c.pi_js_bool(engine.context, 1));
        inline for (.{ "abortRetry", "abortCompaction", "abortBranchSummary" }) |name| _ = try scope.invoke(session, name, &.{});
        if (scope.truthy(try scope.get(session, "_isBeforeSettle"))) try scope.set(session, "_abortDuringBeforeSettle", c.pi_js_bool(engine.context, 1));
        _ = try scope.invoke(try scope.get(session, "agent"), "abort", &.{});
        const result = try scope.invoke(session, "waitForIdle", &.{});
        return .{ .awaited = c.JS_DupValue(engine.context, result) };
    }
    if (scope.truthy(try scope.get(session, "isIdle"))) return .{ .returned = c.pi_js_undefined() };
    const result = try scope.invoke(session, "_getIdleWaitPromise", &.{});
    return .{ .awaited = c.JS_DupValue(engine.context, result) };
}
