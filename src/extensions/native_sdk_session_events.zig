//! Source AgentSession event ordering over ordinary live session fields.
//! attach retains the real receiver in the own arrow-equivalent callback.
const std = @import("std");
const em = @import("engine.zig");
const sdk = @import("native_sdk.zig");
const js = @import("native_js_values.zig");
const temp = @import("native_sdk_prompt_scope.zig");
const Scope = temp.Scope;
const flow = @import("native_agent_async.zig");
const c = em.c;
const Method = enum(c_int) { _emitExtensionEvent, _willRetryAfterAgentEnd, _replaceMessageInPlace, _emit, _emitQueueUpdate, subscribe, _findPersistedMessageEntryId, _limitsModel };

pub fn install(engine: *em.Engine, prototype: c.JSValue) !void {
    inline for (std.meta.fields(Method)) |field| {
        const function = try engine.checked(c.pi_js_function_magic(engine.context, methodCallback, field.name, switch (@as(Method, @enumFromInt(field.value))) {
            ._replaceMessageInPlace => 2,
            ._emitQueueUpdate, ._limitsModel => 0,
            else => 1,
        }, @intCast(field.value)));
        defer engine.freeValue(function);
        if (field.value == 0) {
            const parent = try engine.checked(c.JS_GetAsyncFunctionPrototype(engine.context));
            defer engine.freeValue(parent);
            if (c.JS_SetPrototype(engine.context, function, parent) < 0) return js.capture(engine);
        }
        if (c.JS_DefinePropertyValueStr(engine.context, prototype, field.name, c.JS_DupValue(engine.context, function), c.JS_PROP_WRITABLE | c.JS_PROP_CONFIGURABLE) < 0) return js.capture(engine);
    }
}

pub fn attach(engine: *em.Engine, session: c.JSValue) !void {
    _ = engine;
    _ = session;
    return error.RequiredNativeSessionHookDependencies;
}
pub fn attachWithDependencies(engine: *em.Engine, session: c.JSValue, dependencies: c.JSValue) !void {
    try @import("native_sdk_session_hooks.zig").validateDependencies(engine, dependencies);
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    var roots = [_]c.JSValue{session};
    const function = try scope.own(try engine.checked(c.JS_NewCFunctionData2(engine.context, handleCallback, "_handleAgentEvent", 1, 0, roots.len, &roots)));
    const parent = try scope.own(try engine.checked(c.JS_GetAsyncFunctionPrototype(engine.context)));
    if (c.JS_SetPrototype(engine.context, function, parent) < 0) return js.capture(engine);
    try scope.set(session, "_handleAgentEvent", function);
    try scope.set(session, "_unsubscribeAgent", try scope.invoke(try scope.get(session, "agent"), "subscribe", &.{function}));
    try @import("native_sdk_session_hooks.zig").attachWithDependencies(engine, session, dependencies);
}

fn methodCallback(context: ?*c.JSContext, receiver: c.JSValue, argc: c_int, args: [*c]c.JSValue, magic: c_int) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    const event = if (argc > 0) args[0] else c.pi_js_undefined();
    return switch (@as(Method, @enumFromInt(magic))) {
        ._emitExtensionEvent => emitExtension(engine, receiver, event) catch |err| sdk.fail(engine, err),
        ._willRetryAfterAgentEnd => willRetry(engine, receiver, event) catch |err| sdk.fail(engine, err),
        ._replaceMessageInPlace => replace(engine, event, if (argc > 1) args[1] else c.pi_js_undefined()) catch |err| sdk.fail(engine, err),
        else => synchronous(engine, receiver, event, @enumFromInt(magic)) catch |err| sdk.fail(engine, err),
    };
}
fn handleCallback(context: ?*c.JSContext, _: c.JSValue, argc: c_int, args: [*c]c.JSValue, _: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    return handle(engine, roots[0], if (argc > 0) args[0] else c.pi_js_undefined()) catch |err| sdk.fail(engine, err);
}
fn is(scope: *Scope, value: c.JSValue, expected: []const u8) !bool {
    return scope.equal(value, try scope.text(expected));
}
fn handle(engine: *em.Engine, receiver: c.JSValue, event: c.JSValue) !c.JSValue {
    const pending = try flow.create(engine, receiver);
    defer engine.freeValue(pending.owner);
    errdefer engine.freeValue(pending.promise);
    sdk.put(engine, pending.owner, "event", c.JS_DupValue(engine.context, event)) catch |err| {
        try flow.rejectError(engine, pending.owner, err);
        return pending.promise;
    };
    prelude(engine, pending.owner) catch |err| try flow.rejectError(engine, pending.owner, err);
    return pending.promise;
}
fn prelude(engine: *em.Engine, owner: c.JSValue) !void {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const receiver = try scope.get(owner, "agent");
    const event = try scope.get(owner, "event");
    const typ = try scope.get(event, "type");
    if (try is(&scope, typ, "agent_start") and scope.truthy(try scope.get(receiver, "_agentRunAbortRequested"))) _ = try scope.invoke(try scope.get(receiver, "agent"), "abort", &.{});
    const nested = try scope.get(receiver, "_nestedToolCalls");
    if (scope.truthy(nested)) {
        if (try is(&scope, typ, "message_start")) {
            const message = try scope.get(event, "message");
            if (try is(&scope, try scope.get(message, "role"), "toolResult")) {
                const summary = try scope.invoke(nested, "takeRecord", &.{try scope.get(message, "toolCallId")});
                if (!temp.nullish(summary)) {
                    const calls = try scope.get(summary, "calls");
                    if (scope.truthy(calls)) try scope.set(message, "nestedCalls", calls);
                    const usage = try scope.get(summary, "usage");
                    if (scope.truthy(usage)) {
                        const current = try scope.get(message, "usage");
                        const combined = if (scope.truthy(current)) try scope.own(try @import("native_sdk_session_hooks.zig").combineUsage(engine, current, usage)) else usage;
                        try scope.set(message, "usage", combined);
                    }
                }
            }
        } else if (try is(&scope, typ, "agent_end")) _ = try scope.invoke(nested, "clear", &.{});
    }
    if (try is(&scope, typ, "message_start")) {
        const message = try scope.get(event, "message");
        if (try is(&scope, try scope.get(message, "role"), "user")) {
            try scope.set(receiver, "_overflowRecoveryAttempted", c.pi_js_bool(engine.context, 0));
            const text = try contentText(&scope, try scope.get(message, "content"));
            if (scope.truthy(text)) {
                inline for (.{ "_steeringMessages", "_followUpMessages" }) |name| {
                    const queue = try scope.get(receiver, name);
                    const index = try scope.invoke(queue, "indexOf", &.{text});
                    if (!scope.equal(index, c.JS_NewInt32(engine.context, -1))) {
                        _ = try scope.invoke(queue, "splice", &.{ index, c.JS_NewInt32(engine.context, 1) });
                        _ = try scope.invoke(receiver, "_emitQueueUpdate", &.{});
                        break;
                    }
                }
            }
        }
    }
    try flow.wait(afterExtension, engine, owner, try scope.invoke(receiver, "_emitExtensionEvent", &.{event}), 0);
}
fn contentText(scope: *Scope, content: c.JSValue) !c.JSValue {
    if (c.JS_IsString(content)) return content;
    const parts = try scope.array();
    if (c.JS_IsArray(content)) {
        for (0..try sdk.length(scope.engine, content)) |index| {
            const part = try scope.own(try scope.engine.checked(c.JS_GetPropertyUint32(scope.engine.context, content, @intCast(index))));
            if (try is(scope, try scope.get(part, "type"), "text")) _ = try scope.invoke(parts, "push", &.{try scope.get(part, "text")});
        }
    }
    return scope.invoke(parts, "join", &.{try scope.text("")});
}
fn afterExtension(engine: *em.Engine, owner: c.JSValue, value: c.JSValue, rejected: bool, _: c_int) !void {
    if (rejected) return flow.settle(engine, owner, true, value);
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const receiver = try scope.get(owner, "agent");
    const event = try scope.get(owner, "event");
    const typ = try scope.get(event, "type");
    var public = event;
    if (try is(&scope, typ, "agent_end")) {
        public = try scope.own(try js.spread(engine, event));
        try scope.put(public, "willRetry", try scope.invoke(receiver, "_willRetryAfterAgentEnd", &.{event}));
    }
    _ = try scope.invoke(receiver, "_emit", &.{public});
    if (try is(&scope, typ, "message_end")) {
        const message = try scope.get(event, "message");
        const role = try scope.get(message, "role");
        const manager = try scope.get(receiver, "sessionManager");
        var entry = c.pi_js_undefined();
        if (try is(&scope, role, "custom")) {
            entry = try scope.invoke(manager, "appendCustomMessageEntry", &.{ try scope.get(message, "customType"), try scope.get(message, "content"), try scope.get(message, "display"), try scope.get(message, "details") });
        } else if (try is(&scope, role, "system") or try is(&scope, role, "user") or try is(&scope, role, "assistant") or try is(&scope, role, "toolResult")) {
            entry = try scope.invoke(manager, "appendMessage", &.{message});
        }
        if (scope.truthy(entry)) _ = try scope.invoke(try scope.get(receiver, "_entryIdsByMessage"), "set", &.{ message, entry });
        if (try is(&scope, role, "assistant")) {
            try scope.set(receiver, "_lastAssistantMessage", message);
            const stop = try scope.get(message, "stopReason");
            if (!try is(&scope, stop, "error") and !try is(&scope, stop, "length")) try scope.set(receiver, "_overflowRecoveryAttempted", c.pi_js_bool(engine.context, 0));
            const retry = try scope.get(receiver, "_retryAttempt");
            if (!try is(&scope, stop, "error") and try scope.positive(retry)) {
                const retry_event = try scope.object();
                try scope.put(retry_event, "type", try scope.text("auto_retry_end"));
                try scope.put(retry_event, "success", c.pi_js_bool(engine.context, 1));
                try scope.put(retry_event, "attempt", retry);
                _ = try scope.invoke(receiver, "_emit", &.{retry_event});
                try scope.set(receiver, "_retryAttempt", c.JS_NewInt32(engine.context, 0));
            }
        }
    }
    if (try is(&scope, typ, "turn_end")) {
        try scope.set(receiver, "_lastAssistantToolResults", try scope.get(event, "toolResults"));
        _ = try scope.invoke(receiver, "_flushPendingCustomMessages", &.{});
    }
    try flow.settle(engine, owner, false, c.pi_js_undefined());
}
fn emitExtension(engine: *em.Engine, receiver: c.JSValue, event: c.JSValue) !c.JSValue {
    const pending = try flow.create(engine, receiver);
    defer engine.freeValue(pending.owner);
    errdefer engine.freeValue(pending.promise);
    sdk.put(engine, pending.owner, "event", c.JS_DupValue(engine.context, event)) catch |err| {
        try flow.rejectError(engine, pending.owner, err);
        return pending.promise;
    };
    extensionStart(engine, pending.owner) catch |err| try flow.rejectError(engine, pending.owner, err);
    return pending.promise;
}
fn extensionStart(engine: *em.Engine, owner: c.JSValue) !void {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const receiver = try scope.get(owner, "agent");
    const event = try scope.get(owner, "event");
    const typ = try scope.get(event, "type");
    const projected = try scope.object();
    try scope.put(projected, "type", typ);
    var stage: c_int = 0;
    var method: [*:0]const u8 = "emit";
    if (try is(&scope, typ, "agent_start")) {
        try scope.set(receiver, "_turnIndex", c.JS_NewInt32(engine.context, 0));
    } else if (try is(&scope, typ, "agent_end")) {
        try scope.put(projected, "messages", try scope.get(event, "messages"));
    } else if (try is(&scope, typ, "turn_start")) {
        try scope.put(projected, "turnIndex", try scope.get(receiver, "_turnIndex"));
        try scope.put(projected, "timestamp", try scope.invoke(try scope.global("Date"), "now", &.{}));
    } else if (try is(&scope, typ, "turn_end")) {
        const message = try scope.get(event, "message");
        if (try is(&scope, try scope.get(message, "role"), "assistant") and !scope.truthy(try scope.invoke(try scope.get(receiver, "_boundaryDispatchedMessages"), "delete", &.{message}))) {
            return flow.wait(extensionDone, engine, owner, try scope.invoke(receiver, "_dispatchTurnEndBoundary", &.{ message, try scope.get(event, "toolResults") }), 2);
        }
        return extensionDone(engine, owner, c.pi_js_undefined(), false, 2);
    } else if (try is(&scope, typ, "message_start") or try is(&scope, typ, "message_update") or try is(&scope, typ, "message_end")) {
        try scope.put(projected, "message", try scope.get(event, "message"));
        if (try is(&scope, typ, "message_update")) try scope.put(projected, "assistantMessageEvent", try scope.get(event, "assistantMessageEvent"));
        if (try is(&scope, typ, "message_end")) {
            method = "emitMessageEnd";
            stage = 1;
        }
    } else if (try is(&scope, typ, "tool_execution_start") or try is(&scope, typ, "tool_execution_update") or try is(&scope, typ, "tool_execution_end")) {
        inline for (.{ "toolCallId", "toolName" }) |key| try scope.put(projected, key, try scope.get(event, key));
        if (try is(&scope, typ, "tool_execution_end")) {
            inline for (.{ "result", "isError" }) |key| try scope.put(projected, key, try scope.get(event, key));
            const duration = try scope.get(event, "durationMs");
            if (!c.JS_IsUndefined(duration)) try scope.put(projected, "durationMs", duration);
        } else {
            try scope.put(projected, "args", try scope.get(event, "args"));
            if (try is(&scope, typ, "tool_execution_update")) try scope.put(projected, "partialResult", try scope.get(event, "partialResult"));
        }
    } else return flow.settle(engine, owner, false, c.pi_js_undefined());
    try flow.wait(extensionDone, engine, owner, try scope.invoke(try scope.get(receiver, "_extensionRunner"), method, &.{projected}), stage);
}
fn extensionDone(engine: *em.Engine, owner: c.JSValue, value: c.JSValue, rejected: bool, stage: c_int) !void {
    if (rejected) return flow.settle(engine, owner, true, value);
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const receiver = try scope.get(owner, "agent");
    if (stage == 1 and scope.truthy(value)) {
        const role = try scope.get(value, "role");
        var normalized = value;
        if ((try is(&scope, role, "user") or try is(&scope, role, "assistant") or try is(&scope, role, "toolResult") or try is(&scope, role, "custom")) and temp.nullish(try scope.get(value, "content"))) {
            normalized = try scope.own(try js.spread(engine, value));
            try scope.put(normalized, "content", try scope.array());
        }
        _ = try scope.invoke(receiver, "_replaceMessageInPlace", &.{ try scope.get(try scope.get(owner, "event"), "message"), normalized });
    }
    if (stage == 2) {
        const next = try scope.own(try engine.checked(c.JS_PiIncrement(engine.context, try scope.get(receiver, "_turnIndex"))));
        try scope.set(receiver, "_turnIndex", next);
    }
    try flow.settle(engine, owner, false, c.pi_js_undefined());
}
fn willRetry(engine: *em.Engine, receiver: c.JSValue, event: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    if (scope.truthy(try scope.get(receiver, "_agentRunAbortRequested"))) return c.pi_js_bool(engine.context, 0);
    const settings = try scope.invoke(try scope.get(receiver, "settingsManager"), "getRetrySettings", &.{});
    if (!scope.truthy(try scope.get(settings, "enabled"))) return c.pi_js_bool(engine.context, 0);
    const exhausted = try scope.own(try engine.checked(c.JS_PiBinaryOperator(engine.context, 7, try scope.get(receiver, "_retryAttempt"), try scope.get(settings, "maxRetries"))));
    if (scope.truthy(exhausted)) return c.pi_js_bool(engine.context, 0);
    const messages = try scope.get(event, "messages");
    var length = try sdk.length(engine, messages);
    while (length > 0) {
        length -= 1;
        const message = try scope.own(try engine.checked(c.JS_GetPropertyUint32(engine.context, messages, @intCast(length))));
        if (try is(&scope, try scope.get(message, "role"), "assistant")) return c.JS_DupValue(engine.context, try scope.invoke(receiver, "_isRetryableError", &.{message}));
    }
    return c.pi_js_bool(engine.context, 0);
}
fn replace(engine: *em.Engine, target: c.JSValue, replacement: c.JSValue) !c.JSValue {
    // Source deletes stale own keys before Object.assign while preserving identity.
    if (c.JS_IsStrictEqual(engine.context, target, replacement)) return c.pi_js_undefined();
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const keys = try scope.own(try js.objectMethod(engine, "keys", target));
    for (0..try sdk.length(engine, keys)) |index| {
        const key = try scope.own(try engine.checked(c.JS_GetPropertyUint32(engine.context, keys, @intCast(index))));
        const atom = try js.atom(engine, key);
        defer c.JS_FreeAtom(engine.context, atom);
        if (c.JS_DeleteProperty(engine.context, target, atom, c.JS_PROP_THROW) < 0) return js.capture(engine);
    }
    _ = try scope.invoke(try scope.global("Object"), "assign", &.{ target, replacement });
    return c.pi_js_undefined();
}
fn synchronous(engine: *em.Engine, receiver: c.JSValue, argument: c.JSValue, method: Method) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    switch (method) {
        ._emit => {
            const listeners = try scope.get(receiver, "_eventListeners");
            var index: u32 = 0;
            while (index < try sdk.length(engine, listeners)) : (index += 1) {
                const listener = try scope.own(try engine.checked(c.JS_GetPropertyUint32(engine.context, listeners, index)));
                _ = try scope.call(listener, c.pi_js_undefined(), &.{argument});
            }
        },
        ._emitQueueUpdate => {
            const event = try scope.object();
            try scope.put(event, "type", try scope.text("queue_update"));
            try scope.put(event, "steering", try scope.invoke(try scope.get(receiver, "_steeringMessages"), "slice", &.{}));
            try scope.put(event, "followUp", try scope.invoke(try scope.get(receiver, "_followUpMessages"), "slice", &.{}));
            _ = try scope.invoke(receiver, "_emit", &.{event});
        },
        .subscribe => {
            _ = try scope.invoke(try scope.get(receiver, "_eventListeners"), "push", &.{argument});
            var roots = [_]c.JSValue{ receiver, argument };
            return engine.checked(c.JS_NewCFunctionData2(engine.context, unsubscribe, "", 0, 0, roots.len, &roots));
        },
        ._findPersistedMessageEntryId => return c.JS_DupValue(engine.context, try persistedId(&scope, receiver, argument)),
        ._limitsModel => {
            const routed = try scope.get(receiver, "routedModel");
            const model = if (temp.nullish(routed)) c.pi_js_undefined() else try scope.get(routed, "model");
            return c.JS_DupValue(engine.context, if (temp.nullish(model)) try scope.get(receiver, "model") else model);
        },
        else => unreachable,
    }
    return c.pi_js_undefined();
}
fn unsubscribe(context: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue, _: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    unsubscribeBody(&scope, roots[0], roots[1]) catch |err| return sdk.fail(engine, err);
    return c.pi_js_undefined();
}
fn unsubscribeBody(scope: *Scope, receiver: c.JSValue, listener: c.JSValue) !void {
    const listeners = try scope.get(receiver, "_eventListeners");
    const index = try scope.invoke(listeners, "indexOf", &.{listener});
    if (!scope.equal(index, c.JS_NewInt32(scope.engine.context, -1))) _ = try scope.invoke(listeners, "splice", &.{ index, c.JS_NewInt32(scope.engine.context, 1) });
}
fn persistedId(scope: *Scope, receiver: c.JSValue, message: c.JSValue) !c.JSValue {
    const mapped = try scope.invoke(try scope.get(receiver, "_entryIdsByMessage"), "get", &.{message});
    if (scope.truthy(mapped)) return mapped;
    const manager = try scope.get(receiver, "sessionManager");
    const branch = try scope.invoke(manager, "getBranch", &.{});
    var index = try sdk.length(scope.engine, branch);
    while (index > 0) {
        index -= 1;
        const entry = try scope.own(try scope.engine.checked(c.JS_GetPropertyUint32(scope.engine.context, branch, index)));
        if (try is(scope, try scope.get(entry, "type"), "message") and scope.equal(try scope.get(entry, "message"), message)) return scope.get(entry, "id");
    }
    const messages = try scope.get(try scope.get(try scope.get(receiver, "agent"), "state"), "messages");
    const target_index = try scope.invoke(messages, "indexOf", &.{message});
    if (scope.equal(target_index, c.JS_NewInt32(scope.engine.context, -1))) return c.pi_js_undefined();
    const projection = try scope.invoke(manager, "buildSessionProjection", &.{});
    const entries = try scope.get(projection, "entries");
    var projected_index: u32 = 0;
    for (0..try sdk.length(scope.engine, entries)) |entry_index| {
        const entry = try scope.own(try scope.engine.checked(c.JS_GetPropertyUint32(scope.engine.context, entries, @intCast(entry_index))));
        for (0..try sdk.length(scope.engine, try scope.get(entry, "messages"))) |_| {
            if (scope.equal(c.JS_NewUint32(scope.engine.context, projected_index), target_index)) {
                const id = try scope.get(try scope.get(entry, "sourceEntry"), "id");
                _ = try scope.invoke(try scope.get(receiver, "_entryIdsByMessage"), "set", &.{ message, id });
                return id;
            }
            projected_index += 1;
        }
    }
    return c.pi_js_undefined();
}
