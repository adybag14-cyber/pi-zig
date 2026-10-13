//! Original AgentSession public getters and value-oriented methods over live
//! ordinary fields. No opaque SDK state or cached aliases participate.
const std = @import("std");
const em = @import("engine.zig");
const sdk = @import("native_sdk.zig");
const js = @import("native_js_values.zig");
const temp = @import("native_sdk_prompt_scope.zig");
const Scope = temp.Scope;
const arithmetic = @import("native_image_arithmetic.zig");
const c = em.c;
const Getter = enum(c_int) {
    modelRuntime,
    state,
    cacheWarmingStatus,
    model,
    thinkingLevel,
    routedModel,
    isStreaming,
    isIdle,
    systemPrompt,
    retryAttempt,
    isCompacting,
    messages,
    steeringMode,
    followUpMode,
    sessionFile,
    sessionId,
    sessionName,
    scopedModels,
    promptTemplates,
    pendingMessageCount,
    resourceLoader,
    autoCompactionEnabled,
    isRetrying,
    autoRetryEnabled,
    isBashRunning,
    hasPendingBashMessages,
    extensionRunner,
};
const Method = enum(c_int) { setCacheWarmingMode, setScopedModels, getSteeringMessages, getFollowUpMessages, getToolDefinition, getAllTools };
pub fn install(engine: *em.Engine, prototype: c.JSValue) !void {
    try @import("native_sdk_prompt_render.zig").initialize(engine);
    inline for (std.meta.fields(Getter)) |field| {
        const getter = try engine.checked(c.pi_js_function_magic(engine.context, getCallback, "get " ++ field.name, 0, field.value));
        const atom = c.JS_NewAtom(engine.context, field.name);
        if (atom == c.JS_ATOM_NULL) {
            engine.freeValue(getter);
            return error.OutOfMemory;
        }
        defer c.JS_FreeAtom(engine.context, atom);
        if (c.JS_DefinePropertyGetSet(engine.context, prototype, atom, getter, c.pi_js_undefined(), c.JS_PROP_CONFIGURABLE) < 0) return js.capture(engine);
    }
    inline for (std.meta.fields(Method)) |field| {
        const function = try engine.checked(c.pi_js_function_magic(engine.context, methodCallback, field.name, if (field.value < 2 or field.value == 4) 1 else 0, field.value));
        if (c.JS_DefinePropertyValueStr(engine.context, prototype, field.name, function, c.JS_PROP_WRITABLE | c.JS_PROP_CONFIGURABLE) < 0) return js.capture(engine);
    }
}
fn getCallback(context: ?*c.JSContext, receiver: c.JSValue, _: c_int, _: [*c]c.JSValue, magic: c_int) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    return get(engine, receiver, @enumFromInt(magic)) catch |err| sdk.fail(engine, err);
}
fn copy(scope: *Scope, target: c.JSValue, name: [*:0]const u8) !c.JSValue {
    return c.JS_DupValue(scope.engine.context, try scope.get(target, name));
}
fn boolean(engine: *em.Engine, value: bool) c.JSValue {
    return c.pi_js_bool(engine.context, @intFromBool(value));
}
fn get(engine: *em.Engine, session: c.JSValue, which: Getter) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    switch (which) {
        .modelRuntime => return copy(&scope, session, "_modelRuntime"),
        .state => return copy(&scope, try scope.get(session, "agent"), "state"),
        .cacheWarmingStatus => {
            const warmer = try scope.get(session, "_cacheWarmer");
            return if (temp.nullish(warmer)) c.pi_js_undefined() else copy(&scope, warmer, "status");
        },
        .model, .thinkingLevel, .messages => return copy(&scope, try scope.get(try scope.get(session, "agent"), "state"), @tagName(which)),
        .routedModel => return routed(&scope, session),
        .isStreaming => return copy(&scope, session, "_isAgentRunActive"),
        .isIdle => return boolean(engine, !scope.truthy(try scope.get(session, "_isAgentRunActive")) and !scope.truthy(try scope.get(session, "isCompacting"))),
        .systemPrompt => {
            const active = try scope.get(session, "_runSystemPromptOptions");
            return @import("native_sdk_prompt_render.zig").render(engine, if (temp.nullish(active)) try scope.get(session, "_baseSystemPromptOptions") else active);
        },
        .retryAttempt => return copy(&scope, session, "_retryAttempt"),
        .isCompacting => return boolean(engine, !c.JS_IsUndefined(try scope.get(session, "_autoCompactionAbortController")) or
            !c.JS_IsUndefined(try scope.get(session, "_compactionAbortController")) or
            !c.JS_IsUndefined(try scope.get(session, "_branchSummaryAbortController"))),
        .steeringMode, .followUpMode => return copy(&scope, try scope.get(session, "agent"), @tagName(which)),
        .sessionFile, .sessionId, .sessionName => return js.invoke(engine, try scope.get(session, "sessionManager"), switch (which) {
            .sessionFile => "getSessionFile",
            .sessionId => "getSessionId",
            else => "getSessionName",
        }, &.{}),
        .scopedModels => return copy(&scope, session, "_scopedModels"),
        .promptTemplates => return copy(&scope, try scope.invoke(try scope.get(session, "_resourceLoader"), "getPrompts", &.{}), "prompts"),
        .pendingMessageCount => return arithmetic.binary(engine, .add, try scope.get(try scope.get(session, "_steeringMessages"), "length"), try scope.get(try scope.get(session, "_followUpMessages"), "length")),
        .resourceLoader => return copy(&scope, session, "_resourceLoader"),
        .autoCompactionEnabled => return js.invoke(engine, try scope.get(session, "settingsManager"), "getCompactionEnabled", &.{}),
        .isRetrying => return boolean(engine, !c.JS_IsUndefined(try scope.get(session, "_retryAbortController"))),
        .autoRetryEnabled => return js.invoke(engine, try scope.get(session, "settingsManager"), "getRetryEnabled", &.{}),
        .isBashRunning => return boolean(engine, try arithmetic.compare(engine, .greater, try scope.get(try scope.get(session, "_bashAbortControllers"), "size"), c.JS_NewInt32(engine.context, 0))),
        .hasPendingBashMessages => return boolean(engine, try arithmetic.compare(engine, .greater, try scope.get(try scope.get(session, "_pendingBashMessages"), "length"), c.JS_NewInt32(engine.context, 0))),
        .extensionRunner => return copy(&scope, session, "_extensionRunner"),
    }
}
fn latestResponse(engine: *em.Engine, messages: c.JSValue) !c.JSValue {
    const length = try sdk.get(engine, messages, "length");
    defer engine.freeValue(length);
    var index = try arithmetic.binary(engine, .subtract, length, c.JS_NewInt32(engine.context, 1));
    defer engine.freeValue(index);
    while (try arithmetic.compare(engine, .greater_equal, index, c.JS_NewInt32(engine.context, 0))) {
        var scope: Scope = .{ .engine = engine };
        defer scope.deinit();
        const message = try scope.own(try js.getKey(engine, messages, index));
        if (scope.equal(try scope.get(message, "role"), try scope.text("assistant")) and
            !scope.equal(try scope.get(message, "stopReason"), try scope.text("error")) and
            !scope.equal(try scope.get(message, "stopReason"), try scope.text("aborted"))) return c.JS_DupValue(engine.context, message);
        const next = try arithmetic.binary(engine, .subtract, index, c.JS_NewInt32(engine.context, 1));
        engine.freeValue(index);
        index = next;
    }
    return c.pi_js_undefined();
}
fn routed(scope: *Scope, session: c.JSValue) !c.JSValue {
    const engine = scope.engine;
    if (!scope.truthy(try scope.get(session, "model"))) return c.pi_js_undefined();
    if (!scope.equal(try scope.get(try scope.get(session, "model"), "api"), try scope.text("pi-virtual"))) return c.pi_js_undefined();
    const latest = try scope.own(try latestResponse(engine, try scope.get(try scope.get(try scope.get(session, "agent"), "state"), "messages")));
    const model = if (scope.truthy(latest)) blk: {
        const runtime = try scope.get(session, "_modelRuntime");
        const lookup = try scope.get(runtime, "getPhysicalModel");
        break :blk try scope.call(lookup, runtime, &.{ try scope.get(latest, "provider"), try scope.get(latest, "model") });
    } else latest;
    if (!scope.truthy(model)) return c.JS_DupValue(engine.context, model);
    const result = try scope.object();
    try scope.put(result, "model", model);
    try scope.put(result, "thinkingLevel", if (temp.nullish(latest)) c.pi_js_undefined() else try scope.get(latest, "thinkingLevel"));
    return c.JS_DupValue(engine.context, result);
}
fn methodCallback(context: ?*c.JSContext, session: c.JSValue, argc: c_int, args: [*c]c.JSValue, magic: c_int) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    return method(engine, session, @enumFromInt(magic), if (argc > 0) args[0] else c.pi_js_undefined()) catch |err| sdk.fail(engine, err);
}
fn method(engine: *em.Engine, session: c.JSValue, which: Method, first: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    switch (which) {
        .setCacheWarmingMode => {
            _ = try scope.invoke(try scope.get(session, "settingsManager"), "setCacheWarmingMode", &.{first});
            const warmer = try scope.get(session, "_cacheWarmer");
            if (!temp.nullish(warmer)) _ = try scope.invoke(warmer, "onModeChanged", &.{});
        },
        .setScopedModels => try scope.set(session, "_scopedModels", first),
        .getSteeringMessages => return copy(&scope, session, "_steeringMessages"),
        .getFollowUpMessages => return copy(&scope, session, "_followUpMessages"),
        .getToolDefinition => {
            const entry = try scope.invoke(try scope.get(session, "_toolDefinitions"), "get", &.{first});
            return if (temp.nullish(entry)) c.pi_js_undefined() else copy(&scope, entry, "definition");
        },
        .getAllTools => return allTools(&scope, session),
    }
    return c.pi_js_undefined();
}
fn allTools(scope: *Scope, session: c.JSValue) !c.JSValue {
    const array = try scope.global("Array");
    const from = try scope.get(array, "from");
    const entries = try scope.call(from, array, &.{try scope.invoke(try scope.get(session, "_toolDefinitions"), "values", &.{})});
    const map = try scope.get(entries, "map");
    var roots = [_]c.JSValue{session};
    const mapper = try scope.own(try scope.engine.checked(c.JS_NewCFunctionData2(scope.engine.context, toolInfo, "", 1, 0, roots.len, &roots)));
    return js.call(scope.engine, map, entries, &.{mapper});
}
fn toolInfo(context: ?*c.JSContext, _: c.JSValue, argc: c_int, args: [*c]c.JSValue, _: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    return info(engine, roots[0], if (argc > 0) args[0] else c.pi_js_undefined()) catch |err| sdk.fail(engine, err);
}
fn info(engine: *em.Engine, session: c.JSValue, entry: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const definition = try scope.get(entry, "definition");
    const source = try scope.get(entry, "sourceInfo");
    const output = try scope.object();
    inline for (.{ "name", "description", "parameters", "promptGuidelines" }) |name| try scope.put(output, name, try scope.get(definition, name));
    const exposure = try scope.get(session, "_getToolExposure");
    try scope.put(output, "exposure", try scope.call(exposure, session, &.{try scope.get(definition, "name")}));
    if (scope.truthy(try scope.get(definition, "namespace"))) try scope.put(output, "namespace", try scope.get(definition, "namespace"));
    if (scope.truthy(try scope.get(definition, "annotations"))) try scope.put(output, "annotations", try scope.own(try js.spread(engine, try scope.get(definition, "annotations"))));
    if (scope.truthy(try scope.get(definition, "reachesTools"))) try scope.put(output, "reachesTools", try scope.get(definition, "reachesTools"));
    try scope.put(output, "sourceInfo", source);
    return c.JS_DupValue(engine.context, output);
}
