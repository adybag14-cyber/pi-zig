//! Original Agent synchronous methods; ordinary this and live field lookups.
//! The complete core class installer selects these bodies directly. Nothing
//! here installs absent Agent methods or substitutes a prompt/loop execution.
const em = @import("engine.zig");
const sdk = @import("native_sdk.zig");
const js = @import("native_js_values.zig");
const temp = @import("native_sdk_prompt_scope.zig");
const Scope = temp.Scope;
const c = em.c;

pub const Operation = enum {
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
};

pub fn apply(engine: *em.Engine, receiver: c.JSValue, operation: Operation, args: []const c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const argument = if (args.len > 0) args[0] else c.pi_js_undefined();
    switch (operation) {
        .subscribe => {
            _ = try scope.invoke(try scope.get(receiver, "listeners"), "add", &.{argument});
            var roots = [_]c.JSValue{ receiver, argument };
            return engine.checked(c.JS_NewCFunctionData2(engine.context, unsubscribe, "", 0, 0, roots.len, &roots));
        },
        .state => return c.JS_DupValue(engine.context, try scope.get(receiver, "_state")),
        .steeringMode, .followUpMode => return c.JS_DupValue(engine.context, try scope.get(try scope.get(receiver, if (operation == .steeringMode) "steeringQueue" else "followUpQueue"), "mode")),
        .setSteeringMode, .setFollowUpMode => try scope.set(try scope.get(receiver, if (operation == .setSteeringMode) "steeringQueue" else "followUpQueue"), "mode", argument),
        .steer, .followUp => {
            _ = try scope.invoke(try scope.get(receiver, if (operation == .steer) "steeringQueue" else "followUpQueue"), "enqueue", &.{argument});
        },
        .clearSteeringQueue, .clearFollowUpQueue => {
            _ = try scope.invoke(try scope.get(receiver, if (operation == .clearSteeringQueue) "steeringQueue" else "followUpQueue"), "clear", &.{});
        },
        .clearAllQueues => {
            _ = try scope.invoke(receiver, "clearSteeringQueue", &.{});
            _ = try scope.invoke(receiver, "clearFollowUpQueue", &.{});
        },
        .hasQueuedMessages => {
            const steering = try scope.invoke(try scope.get(receiver, "steeringQueue"), "hasItems", &.{});
            return c.JS_DupValue(engine.context, if (scope.truthy(steering)) steering else try scope.invoke(try scope.get(receiver, "followUpQueue"), "hasItems", &.{}));
        },
        .peekQueuedMessages => {
            const steering = try scope.invoke(try scope.get(receiver, "steeringQueue"), "peek", &.{});
            return c.JS_DupValue(engine.context, if (try scope.positive(try scope.get(steering, "length"))) steering else try scope.invoke(try scope.get(receiver, "followUpQueue"), "peek", &.{}));
        },
        .signal, .abort, .waitForIdle => {
            const active = try scope.get(receiver, "activeRun");
            if (operation == .waitForIdle) {
                const idle = if (temp.nullish(active)) c.pi_js_undefined() else try scope.get(active, "promise");
                return c.JS_DupValue(engine.context, if (temp.nullish(idle)) try scope.invoke(try scope.global("Promise"), "resolve", &.{}) else idle);
            }
            if (temp.nullish(active)) return c.pi_js_undefined();
            const controller = try scope.get(active, "abortController");
            if (operation == .signal) return c.JS_DupValue(engine.context, try scope.get(controller, "signal"));
            _ = try scope.invoke(controller, "abort", &.{});
        },
        .reset => {
            if (scope.truthy(try scope.get(receiver, "activeRun"))) return raise(&scope, "Agent is already processing. Wait for completion before resetting.");
            const initial = try scope.get(try scope.get(receiver, "_state"), "messages");
            const baseline = try scope.own(try @import("native_sdk_transcript_replay.zig").currentSystemMessage(engine, initial));
            const messages = try scope.array();
            if (scope.truthy(baseline)) try scope.index(messages, 0, baseline);
            try scope.set(try scope.get(receiver, "_state"), "messages", messages);
            try scope.set(try scope.get(receiver, "_state"), "isStreaming", c.pi_js_bool(engine.context, 0));
            try scope.set(try scope.get(receiver, "_state"), "streamingMessage", c.pi_js_undefined());
            try scope.set(try scope.get(receiver, "_state"), "pendingToolCalls", try scope.own(try js.builtin(engine, "Set", &.{})));
            try scope.set(try scope.get(receiver, "_state"), "errorMessage", c.pi_js_undefined());
            _ = try scope.invoke(receiver, "clearFollowUpQueue", &.{});
            _ = try scope.invoke(receiver, "clearSteeringQueue", &.{});
        },
        .normalizePromptInput => {
            if (scope.truthy(try scope.invoke(try scope.global("Array"), "isArray", &.{argument}))) return c.JS_DupValue(engine.context, argument);
            const result = try scope.array();
            if (!c.JS_IsString(argument)) {
                try scope.index(result, 0, argument);
                return c.JS_DupValue(engine.context, result);
            }
            const content = try scope.array();
            const text = try scope.object();
            try scope.put(text, "type", try scope.text("text"));
            try scope.put(text, "text", argument);
            try scope.index(content, 0, text);
            const images = if (args.len > 1) args[1] else c.pi_js_undefined();
            if (scope.truthy(images) and try scope.positive(try scope.get(images, "length"))) {
                const push = try scope.get(content, "push");
                const symbol = try scope.own(try engine.checked(JS_GetIteratorSymbol(engine.context)));
                var iterator = try js.Iterator.init(engine, images, symbol);
                defer iterator.deinit();
                errdefer iterator.closePreserving();
                var spread: @import("std").ArrayList(c.JSValue) = .empty;
                defer spread.deinit(engine.gpa);
                while (try iterator.next()) |image| {
                    const owned = try scope.own(image);
                    try spread.append(engine.gpa, owned);
                }
                _ = try scope.call(push, content, spread.items);
            }
            const message = try scope.object();
            try scope.put(message, "role", try scope.text("user"));
            try scope.put(message, "content", content);
            try scope.put(message, "timestamp", try scope.invoke(try scope.global("Date"), "now", &.{}));
            try scope.index(result, 0, message);
            return c.JS_DupValue(engine.context, result);
        },
        .createContextSnapshot => {
            const snapshot = try scope.object();
            try scope.put(snapshot, "messages", try scope.invoke(try scope.get(try scope.get(receiver, "_state"), "messages"), "slice", &.{}));
            try scope.put(snapshot, "tools", try scope.invoke(try scope.get(try scope.get(receiver, "_state"), "tools"), "slice", &.{}));
            return c.JS_DupValue(engine.context, snapshot);
        },
        .finishRun => {
            try scope.set(try scope.get(receiver, "_state"), "isStreaming", c.pi_js_bool(engine.context, 0));
            try scope.set(try scope.get(receiver, "_state"), "streamingMessage", c.pi_js_undefined());
            try scope.set(try scope.get(receiver, "_state"), "pendingToolCalls", try scope.own(try js.builtin(engine, "Set", &.{})));
            const active = try scope.get(receiver, "activeRun");
            if (!temp.nullish(active)) _ = try scope.invoke(active, "resolve", &.{});
            try scope.set(receiver, "activeRun", c.pi_js_undefined());
        },
    }
    return c.pi_js_undefined();
}

extern "c" fn JS_GetIteratorSymbol(context: ?*c.JSContext) c.JSValue;

fn unsubscribe(context: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue, _: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    return remove(engine, roots[0], roots[1]) catch |err| sdk.fail(engine, err);
}

fn remove(engine: *em.Engine, agent: c.JSValue, listener: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    return c.JS_DupValue(engine.context, try scope.invoke(try scope.get(agent, "listeners"), "delete", &.{listener}));
}

pub fn raise(scope: *Scope, message: []const u8) !c.JSValue {
    const constructor = try scope.global("Error");
    var args = [_]c.JSValue{try scope.text(message)};
    return scope.engine.checked(c.JS_Throw(scope.engine.context, try scope.engine.checked(c.JS_CallConstructor(scope.engine.context, constructor, args.len, &args))));
}
