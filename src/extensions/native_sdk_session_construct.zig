//! Ordinary Source AgentSession declarations and constructor body.
//! Private assembly must supply the complete original prototype, including
//! actual runtime and transcript restoration methods, before using this class.
const std = @import("std");
const em = @import("engine.zig");
const sdk = @import("native_sdk.zig");
const js = @import("native_js_values.zig");
const temp = @import("native_sdk_prompt_scope.zig");
const Scope = temp.Scope;
const c = em.c;
const fields = .{
    "agent",                      "sessionManager",                "settingsManager",                 "_scopedModels",
    "_unsubscribeAgent",          "_eventListeners",               "_isAgentRunActive",               "_agentRunAbortRequested",
    "_idleWaitPromise",           "_resolveIdleWait",              "_steeringMessages",               "_followUpMessages",
    "_pendingNextTurnMessages",   "_pendingCustomMessages",        "_compactionAbortController",      "_autoCompactionAbortController",
    "_overflowRecoveryAttempted", "_branchSummaryAbortController", "_retryAbortController",           "_retryAttempt",
    "_failedResponse",            "_bashAbortControllers",         "_pendingBashMessages",            "_extensionRunner",
    "_turnIndex",                 "_entryIdsByMessage",            "_boundaryDispatchedMessages",     "_lastAssistantMessage",
    "_lastAssistantToolResults",  "_lastActivityOutcome",          "_isBeforeSettle",                 "_abortDuringBeforeSettle",
    "_isEmittingAgentSettled",    "_deferredSettledActions",       "_resourceLoader",                 "_customTools",
    "_baseToolDefinitions",       "_cwd",                          "_extensionRunnerRef",             "_initialActiveToolNames",
    "_pendingToolNames",          "_usesDefaultTools",             "_defaultToolModifiers",           "_allowedTools",
    "_allowlistFiltersMcp",       "_excludedTools",                "_baseToolsOverride",              "_sessionStartEvent",
    "_extensionUIContext",        "_extensionMode",                "_extensionCommandContextActions", "_extensionAbortHandler",
    "_extensionShutdownHandler",  "_extensionErrorListener",       "_extensionErrorUnsubscriber",     "_modelRuntime",
    "_cacheWarmer",               "_toolRegistry",                 "_nestedToolCalls",                "_hiddenDeclarations",
    "_toolDefinitions",           "_toolPromptSnippets",           "_toolPromptGuidelines",           "_baseSystemPromptOptions",
    "_runSystemPromptOptions",
};
fn among(comptime name: []const u8, comptime names: anytype) bool {
    inline for (names) |candidate| if (comptime std.mem.eql(u8, name, candidate)) return true;
    return false;
}
pub fn constructor(engine: *em.Engine, prototype: c.JSValue) !c.JSValue {
    return @import("native_class.zig").constructor(engine, "AgentSession", 1, prototype, construct, &.{});
}
fn construct(engine: *em.Engine, target: c.JSValue, args: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
    const session = try @import("native_class.zig").object(engine, target);
    errdefer engine.freeValue(session);
    try initializeDeclarations(engine, session);
    try initializeConfig(engine, session, if (args.len > 0) args[0] else c.pi_js_undefined());
    try prepareRuntime(engine, session);
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const builder = try scope.get(session, "_buildRuntime");
    const options = try scope.object();
    try scope.put(options, "activeToolNames", try scope.get(session, "_initialActiveToolNames"));
    try scope.put(options, "includeAllExtensionTools", c.pi_js_bool(engine.context, 1));
    _ = try scope.call(builder, session, &.{options});
    if (scope.truthy(try scope.get(session, "_usesDefaultTools"))) {
        const restore = try scope.get(session, "_restoreToolsFromTranscript");
        _ = try scope.call(restore, session, &.{try scope.get(session, "_defaultToolModifiers")});
    }
    return session;
}
pub fn prepareRuntime(engine: *em.Engine, session: c.JSValue) !void {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    try scope.set(session, "_unsubscribeAgent", try scope.invoke(try scope.get(session, "agent"), "subscribe", &.{try scope.get(session, "_handleAgentEvent")}));
    inline for (.{ "_installAgentToolHooks", "_installAgentNextTurnRefresh", "_installAgentRequestProjection", "_installAgentBoundaryHooks", "_installHiddenDeclarationsProjection", "_installAgentForcedPromptProjection" }) |name| {
        _ = try scope.invoke(session, name, &.{});
    }
}
pub fn initializeDeclarations(engine: *em.Engine, session: c.JSValue) !void {
    @setEvalBranchQuota(200000);
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    inline for (fields) |name| {
        const value = if (comptime among(name, .{ "_eventListeners", "_steeringMessages", "_followUpMessages", "_pendingNextTurnMessages", "_pendingCustomMessages", "_pendingBashMessages", "_lastAssistantToolResults", "_deferredSettledActions" }))
            try scope.array()
        else if (comptime among(name, .{ "_isAgentRunActive", "_agentRunAbortRequested", "_overflowRecoveryAttempted", "_isBeforeSettle", "_abortDuringBeforeSettle", "_isEmittingAgentSettled", "_allowlistFiltersMcp" }))
            c.pi_js_bool(engine.context, 0)
        else if (comptime among(name, .{ "_retryAttempt", "_turnIndex" }))
            c.JS_NewInt32(engine.context, 0)
        else if (comptime among(name, .{ "_bashAbortControllers", "_pendingToolNames", "_hiddenDeclarations" }))
            try scope.own(try js.builtin(engine, "Set", &.{}))
        else if (comptime among(name, .{ "_baseToolDefinitions", "_toolRegistry", "_toolDefinitions", "_toolPromptSnippets", "_toolPromptGuidelines" }))
            try scope.own(try js.builtin(engine, "Map", &.{}))
        else if (comptime std.mem.eql(u8, name, "_entryIdsByMessage"))
            try scope.own(try js.builtin(engine, "WeakMap", &.{}))
        else if (comptime std.mem.eql(u8, name, "_boundaryDispatchedMessages"))
            try scope.own(try js.builtin(engine, "WeakSet", &.{}))
        else if (comptime std.mem.eql(u8, name, "_lastActivityOutcome"))
            try scope.text("completed")
        else if (comptime std.mem.eql(u8, name, "_extensionMode"))
            try scope.text("print")
        else
            c.pi_js_undefined();
        try scope.put(session, name, value);
    }
    try scope.put(session, "_handleAgentEvent", try scope.own(try @import("native_sdk_session_events.zig").createHandleAgentEvent(engine, session)));
}
fn copy(scope: *Scope, session: c.JSValue, config: c.JSValue, target: [*:0]const u8, source: [*:0]const u8) !void {
    try scope.set(session, target, try scope.get(config, source));
}
fn copyArray(scope: *Scope, session: c.JSValue, config: c.JSValue, target: [*:0]const u8, source: [*:0]const u8) !void {
    const value = try scope.get(config, source);
    try scope.set(session, target, if (temp.nullish(value)) try scope.array() else value);
}
pub fn initializeConfig(engine: *em.Engine, session: c.JSValue, config: c.JSValue) !void {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    inline for (.{ "agent", "sessionManager", "settingsManager" }) |name| try copy(&scope, session, config, name, name);
    try copyArray(&scope, session, config, "_scopedModels", "scopedModels");
    try copy(&scope, session, config, "_resourceLoader", "resourceLoader");
    try copyArray(&scope, session, config, "_customTools", "customTools");
    try copy(&scope, session, config, "_cwd", "cwd");
    try copy(&scope, session, config, "_modelRuntime", "modelRuntime");
    try copy(&scope, session, config, "_cacheWarmer", "cacheWarmer");
    if (scope.truthy(try scope.get(session, "_cacheWarmer"))) {
        const warmer = try scope.get(session, "_cacheWarmer");
        var roots = [_]c.JSValue{session};
        const callback = try scope.own(try engine.checked(c.JS_NewCFunctionData2(engine.context, warmed, "", 1, 0, roots.len, &roots)));
        try scope.set(warmer, "onWarmed", callback);
    }
    try copy(&scope, session, config, "_extensionRunnerRef", "extensionRunnerRef");
    try copy(&scope, session, config, "_initialActiveToolNames", "initialActiveToolNames");
    const uses_default = try scope.get(config, "usesDefaultTools");
    try scope.set(session, "_usesDefaultTools", if (temp.nullish(uses_default)) c.pi_js_bool(engine.context, 0) else uses_default);
    try copyArray(&scope, session, config, "_defaultToolModifiers", "defaultToolModifiers");
    if (scope.truthy(try scope.get(config, "allowedToolNames"))) {
        try scope.set(session, "_allowedTools", try scope.own(try @import("native_sdk_tool_name_matcher.zig").matcher(engine, try scope.get(config, "allowedToolNames"))));
        const empty = scope.equal(try scope.get(try scope.get(config, "allowedToolNames"), "length"), c.JS_NewInt32(engine.context, 0));
        const filters_mcp = if (empty) c.pi_js_bool(engine.context, 1) else try scope.invoke(try scope.get(config, "allowedToolNames"), "some", &.{try scope.own(try engine.checked(c.JS_NewCFunction(engine.context, mcpPrefix, "", 1)))});
        try scope.set(session, "_allowlistFiltersMcp", filters_mcp);
    }
    const excluded = if (scope.truthy(try scope.get(config, "excludedToolNames"))) try scope.own(try @import("native_sdk_tool_name_matcher.zig").matcher(engine, try scope.get(config, "excludedToolNames"))) else c.pi_js_undefined();
    try scope.set(session, "_excludedTools", excluded);
    try copy(&scope, session, config, "_baseToolsOverride", "baseToolsOverride");
    const supplied_start = try scope.get(config, "sessionStartEvent");
    const start = if (temp.nullish(supplied_start)) blk: {
        const event = try scope.object();
        try scope.put(event, "type", try scope.text("session_start"));
        try scope.put(event, "reason", try scope.text("startup"));
        break :blk event;
    } else supplied_start;
    try scope.set(session, "_sessionStartEvent", start);
}
fn mcpPrefix(context: ?*c.JSContext, _: c.JSValue, argc: c_int, args: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const prefix = scope.text("mcp__") catch |err| return sdk.fail(engine, err);
    return js.invoke(engine, if (argc > 0) args[0] else c.pi_js_undefined(), "startsWith", &.{prefix}) catch |err| sdk.fail(engine, err);
}
fn warmed(context: ?*c.JSContext, _: c.JSValue, argc: c_int, args: [*c]c.JSValue, _: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    return emitWarmed(engine, roots[0], if (argc > 0) args[0] else c.pi_js_undefined()) catch |err| sdk.fail(engine, err);
}
fn emitWarmed(engine: *em.Engine, session: c.JSValue, entry: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const emit = try scope.get(session, "_emit");
    const event = try scope.object();
    try scope.put(event, "type", try scope.text("entry_appended"));
    try scope.put(event, "entry", entry);
    return js.call(engine, emit, session, &.{event});
}
