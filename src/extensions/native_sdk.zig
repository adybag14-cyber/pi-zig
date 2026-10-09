//! Programmatic coding-agent SDK objects, implemented through the C ABI.
const std = @import("std");
const engine_mod = @import("engine.zig");
const c = engine_mod.c;
const Kind = enum(c_int) { session_manager, settings_manager, resource_loader, model_runtime, agent_session, session_runtime, model_registry };
pub const State = struct {
    engine: *engine_mod.Engine,
    kind: Kind,
    data: c.JSValue,
    listeners: std.ArrayList(c.JSValue) = .empty,
    disposed: bool = false,
    running: bool = false,
    aborted: bool = false,
    next_entry: u64 = 1,
    persisted_count: u32 = 0,
    session_flushed: bool = false,
    availability_sequence: u64 = 0,
    availability_error_sequence: u64 = 0,
    runtime_id: u64 = 0,
    model_lease_anchor: ?c.JSValue = null,
    tool_catalog: ?*@import("native_sdk_tool_catalog.zig").State = null,
    availability_snapshot: ?@import("native_sdk_availability.zig").Snapshot = null,
};
const Method = enum(c_int) {
    getCwd,
    getSessionDir,
    usesDefaultSessionDir,
    getSessionId,
    getSessionName,
    getSessionFile,
    getHeader,
    getEntries,
    getEntryCount,
    getLeafId,
    getLeafEntry,
    getEntry,
    getChildren,
    getBranch,
    getLabel,
    getTree,
    appendMessage,
    appendCustomEntry,
    appendSessionInfo,
    appendModelChange,
    appendThinkingLevelChange,
    appendLabelChange,
    branch,
    resetLeaf,
    buildSessionContext,
    buildContextEntries,
    buildSessionProjection,
    newSession,
    isPersisted,
    switchSession,
    setRebindSession,
    setBeforeSessionInvalidate,
    setSessionFile,
    getGlobalSettings,
    getProjectSettings,
    applyOverrides,
    reload,
    flush,
    drainErrors,
    getDefaultProvider,
    getDefaultModel,
    getDefaultThinkingLevel,
    setDefaultThinkingLevel,
    getCompactionSettings,
    getRetrySettings,
    getDefaultTools,
    getTransport,
    getExtensions,
    getSkills,
    getPrompts,
    getThemes,
    getAgentsFiles,
    getSystemPrompt,
    getAppendSystemPrompt,
    getSystemPromptSource,
    getAppendSystemPromptSources,
    extendResources,
    registerProvider,
    registerNativeProvider,
    unregisterProvider,
    registerVirtualModel,
    unregisterVirtualModel,
    resolveModel,
    getPhysicalModel,
    getProviders,
    getModels,
    getAll,
    getAvailable,
    getModel,
    getModelsOfType,
    getModelOfType,
    getAllModels,
    getAllAvailable,
    getAvailableOfType,
    checkAuth,
    getAuth,
    getAvailableSnapshot,
    setRuntimeApiKey,
    removeRuntimeApiKey,
    hasConfiguredAuth,
    clearRuntimeApiKey,
    refresh,
    streamSimple,
    completeSimple,
    stream,
    complete,
    streamDeferred,
    fetchDeferred,
    cancelDeferred,
    classify,
    generateImages,
    subscribe,
    unsubscribe,
    dispose,
    prompt,
    abort,
    bindExtensions,
    getActiveToolNames,
    setActiveToolsByName,
    getAllTools,
    getToolDefinition,
    setSessionName,
    setThinkingLevel,
    getAvailableThinkingLevels,
    cycleThinkingLevel,
    supportsThinking,
    setScopedModels,
    waitForIdle,
    getLastAssistantText,
    setModel,
    getSessionStats,
    clearQueue,
    steer,
    followUp,
    getProvider,
    getError,
    getProviderAuthStatus,
    isUsingOAuth,
    isUsingSubscription,
    getRegisteredProviderIds,
    getRegisteredNativeProvider,
    getRegisteredProviderConfig,
    listCredentials,
};
const Getter = enum(c_int) { sessionId, sessionFile, sessionManager, settingsManager, modelRuntime, resourceLoader, model, thinkingLevel, messages, agent, systemPrompt, isStreaming, sessionName, session, services, cwd, diagnostics, state, isIdle, scopedModels, promptTemplates };

pub fn get(engine: *engine_mod.Engine, target: c.JSValue, name: [*:0]const u8) !c.JSValue {
    return engine.checked(c.JS_GetPropertyStr(engine.context, target, name));
}
pub fn put(engine: *engine_mod.Engine, target: c.JSValue, name: [*:0]const u8, value: c.JSValue) !void {
    if (c.JS_DefinePropertyValueStr(engine.context, target, name, value, c.JS_PROP_C_W_E) < 0) return error.JavaScriptException;
}
pub fn object(engine: *engine_mod.Engine) !c.JSValue {
    return engine.checked(c.JS_NewObject(engine.context));
}
pub fn array(engine: *engine_mod.Engine) !c.JSValue {
    return engine.checked(c.JS_NewArray(engine.context));
}
pub fn text(engine: *engine_mod.Engine, value: []const u8) !c.JSValue {
    return engine.checked(c.JS_NewStringLen(engine.context, value.ptr, value.len));
}
pub fn clone(engine: *engine_mod.Engine, value: c.JSValue) !c.JSValue {
    if (c.JS_IsUndefined(value) or c.JS_IsNull(value)) return c.JS_DupValue(engine.context, value);
    const raw = try engine.stringify(value);
    defer engine.gpa.free(raw);
    const terminated = try engine.gpa.dupeZ(u8, raw);
    defer engine.gpa.free(terminated);
    return engine.checked(c.JS_ParseJSON(engine.context, terminated, raw.len, "native-sdk-clone"));
}
pub fn invoke(engine: *engine_mod.Engine, receiver: c.JSValue, name: [*:0]const u8, args: []const c.JSValue) !c.JSValue {
    const function = try get(engine, receiver, name);
    defer engine.freeValue(function);
    if (!c.JS_IsFunction(engine.context, function)) return error.NativeSDKMethodUnavailable;
    return engine.checked(c.JS_Call(engine.context, function, receiver, @intCast(args.len), @constCast(args.ptr)));
}
pub fn promise(engine: *engine_mod.Engine, value: c.JSValue) !c.JSValue {
    var functions: [2]c.JSValue = undefined;
    const result = try engine.checked(c.JS_NewPromiseCapability(engine.context, &functions));
    errdefer engine.freeValue(result);
    defer for (functions) |function| engine.freeValue(function);
    var args = [_]c.JSValue{value};
    const ignored = try engine.checked(c.JS_Call(engine.context, functions[0], c.pi_js_undefined(), 1, &args));
    engine.freeValue(ignored);
    return result;
}
pub fn fail(engine: *engine_mod.Engine, err: anyerror) c.JSValue {
    if (err == error.JavaScriptException) return engine.throwCaptured();
    if (err == error.OutOfMemory) return c.JS_ThrowOutOfMemory(engine.context);
    return c.JS_ThrowTypeError(engine.context, "Native coding SDK: %s", @as([*:0]const u8, @errorName(err)));
}
pub fn sourceError(engine: *engine_mod.Engine, message: []const u8) !c.JSValue {
    const value = try engine.checked(c.JS_NewError(engine.context));
    defer engine.freeValue(value);
    try put(engine, value, "message", try text(engine, message));
    return engine.checked(c.JS_Throw(engine.context, c.JS_DupValue(engine.context, value)));
}
fn missingEntry(self: *State, id: c.JSValue) !c.JSValue {
    const raw = try self.engine.toString(id);
    defer self.engine.gpa.free(raw);
    const message = try std.fmt.allocPrint(self.engine.gpa, "Entry {s} not found", .{raw});
    defer self.engine.gpa.free(message);
    return sourceError(self.engine, message);
}
pub fn state(engine: *engine_mod.Engine, value: c.JSValue) !*State {
    return @ptrCast(@alignCast(c.JS_GetOpaque2(engine.context, value, engine.native_sdk_class) orelse return error.InvalidNativeSDKReceiver));
}
fn finalizer(runtime: ?*c.JSRuntime, value: c.JSValue) callconv(.c) void {
    const engine: *engine_mod.Engine = @ptrCast(@alignCast(c.JS_GetRuntimeOpaque(runtime)));
    const self: *State = @ptrCast(@alignCast(c.JS_GetOpaque(value, engine.native_sdk_class) orelse return));
    if (self.model_lease_anchor) |anchor| {
        @import("native_sdk_model_bridge.zig").invalidateAnchorRT(engine, runtime, anchor);
        c.JS_FreeValueRT(runtime, anchor);
    }
    if (self.tool_catalog) |catalog| catalog.deinit(runtime);
    c.JS_FreeValueRT(runtime, self.data);
    for (self.listeners.items) |listener| c.JS_FreeValueRT(runtime, listener);
    self.listeners.deinit(engine.gpa);
    if (engine.native_sdk_extension_group) |group_pointer| {
        const group: *@import("native_group.zig").Group = @ptrCast(@alignCast(group_pointer));
        group.sdk_availability.retire(self.runtime_id);
    }
    if (self.availability_snapshot) |*cached| cached.deinit();
    engine.gpa.destroy(self);
}
fn mark(runtime: ?*c.JSRuntime, value: c.JSValue, marker: ?*const c.JS_MarkFunc) callconv(.c) void {
    const engine: *engine_mod.Engine = @ptrCast(@alignCast(c.JS_GetRuntimeOpaque(runtime)));
    const self: *State = @ptrCast(@alignCast(c.JS_GetOpaque(value, engine.native_sdk_class) orelse return));
    c.JS_MarkValue(runtime, self.data, marker);
    if (self.tool_catalog) |catalog| catalog.mark(runtime, marker);
    if (self.model_lease_anchor) |anchor| c.JS_MarkValue(runtime, anchor, marker);
    for (self.listeners.items) |listener| c.JS_MarkValue(runtime, listener, marker);
}
/// Read only while the actual SDK State is owned/live on this Engine. Capture
/// the returned POD in a private binding callback; never keep an unrooted State
/// pointer or treat a user-editable context JSON value as admission authority.
pub fn sessionModelLease(self: *State) !@import("native_sdk_model_bridge.zig").Lease {
    if (self.kind != .agent_session) return error.InvalidNativeSDKSession;
    if (self.disposed) return error.NativeSDKDisposed;
    return @import("native_sdk_model_bridge.zig").anchorLease(self.engine, self.model_lease_anchor orelse return error.NativeSDKModelLeaseUnavailable);
}
/// Only trusted private State.data from the SDK factory/emit path is accepted
/// here. This is not a decoder for extension/transport context snapshots.
pub fn sessionDataModelLease(engine: *engine_mod.Engine, data: c.JSValue) !@import("native_sdk_model_bridge.zig").Lease {
    const anchor = try get(engine, data, "_sdkModelLeaseAnchor");
    defer engine.freeValue(anchor);
    return @import("native_sdk_model_bridge.zig").anchorLease(engine, anchor);
}
/// Trusted factory State.data only. Caller owns the returned session root.
pub fn sessionDataSessionValue(engine: *engine_mod.Engine, data: c.JSValue) !c.JSValue {
    const value = try get(engine, data, "_sdkSessionValue");
    errdefer engine.freeValue(value);
    const owner = try state(engine, value);
    if (owner.kind != .agent_session) return error.InvalidNativeSDKSession;
    return value;
}
pub fn modelRegistryLease(engine: *engine_mod.Engine, value: c.JSValue) !@import("native_sdk_model_bridge.zig").Lease {
    const owner = try state(engine, value);
    if (owner.kind != .model_registry) return error.InvalidNativeSDKModelRegistry;
    return @import("native_sdk_model_bridge.zig").anchorLease(engine, owner.model_lease_anchor orelse return error.NativeSDKModelLeaseUnavailable);
}
pub fn newModelRegistry(engine: *engine_mod.Engine, runtime: c.JSValue) !c.JSValue {
    const data = try object(engine);
    defer engine.freeValue(data);
    try put(engine, data, "modelRuntime", c.JS_DupValue(engine.context, runtime));
    const value = try new(engine, .model_registry, data);
    errdefer engine.freeValue(value);
    try put(engine, value, "runtime", c.JS_DupValue(engine.context, runtime));
    try attachSessionModelLease(try state(engine, value));
    return value;
}
fn attachSessionModelLease(self: *State) !void {
    const engine = self.engine;
    const runtime = try get(engine, self.data, "modelRuntime");
    defer engine.freeValue(runtime);
    const pointer = c.JS_GetOpaque(runtime, engine.native_sdk_class) orelse return;
    const owner: *State = @ptrCast(@alignCast(pointer));
    // Preserve ordinary SDK construction for supplied unbranded runtimes, but
    // leave the owner bridge unavailable instead of choosing another runtime.
    if (owner.kind != .model_runtime) return;
    const bridge = @import("native_sdk_model_bridge.zig");
    var generation: u64 = 0;
    while (true) {
        generation = engine.native_sdk_next_session_generation;
        if (generation > 9007199254740991) return error.NativeSDKSessionLimit;
        engine.native_sdk_next_session_generation += 1;
        if (try bridge.generationAvailable(engine, runtime, generation)) break;
    }
    const anchor = try bridge.admitAnchored(engine, runtime, generation);
    errdefer {
        bridge.invalidateAnchorRT(engine, engine.runtime, anchor.value);
        engine.freeValue(anchor.value);
    }
    try put(engine, self.data, "_sdkModelLeaseAnchor", c.JS_DupValue(engine.context, anchor.value));
    self.model_lease_anchor = anchor.value;
}
fn retireSessionModelLease(self: *State) !void {
    try @import("native_sdk_resource_owners.zig").invalidateSessionRuntime(self);
    if (self.tool_catalog) |catalog| catalog.retire();
    const anchor = self.model_lease_anchor orelse return;
    const bridge = @import("native_sdk_model_bridge.zig");
    const lease = bridge.anchorLease(self.engine, anchor) catch null;
    // Invalidate before any allocation or owner Map call can fail.
    bridge.invalidateAnchorRT(self.engine, self.engine.runtime, anchor);
    self.model_lease_anchor = null;
    defer self.engine.freeValue(anchor);
    try put(self.engine, self.data, "_sdkModelLeaseAnchor", c.pi_js_undefined());
    if (lease) |value| try bridge.retire(self.engine, value);
}
fn retireNativeSessionValue(engine: *engine_mod.Engine, value: c.JSValue) !void {
    const pointer = c.JS_GetOpaque(value, engine.native_sdk_class) orelse return;
    const owner: *State = @ptrCast(@alignCast(pointer));
    if (owner.kind == .agent_session) try retireSessionModelLease(owner);
}
fn method(context: ?*c.JSContext, receiver: c.JSValue, argc: c_int, argv: [*c]c.JSValue, magic: c_int) callconv(.c) c.JSValue {
    const engine = engine_mod.Engine.fromContext(context.?);
    const self = state(engine, receiver) catch |err| return fail(engine, err);
    return dispatch(self, receiver, @enumFromInt(magic), if (argc > 0) argv[0..@intCast(argc)] else &.{}) catch |err| fail(engine, err);
}
fn new(engine: *engine_mod.Engine, kind: Kind, data: c.JSValue) !c.JSValue {
    const value = try engine.checked(c.JS_NewObjectProtoClass(engine.context, engine.native_sdk_prototypes[@as(usize, @intCast(@intFromEnum(kind)))] orelse c.pi_js_null(), engine.native_sdk_class));
    errdefer engine.freeValue(value);
    const self = try engine.gpa.create(State);
    self.* = .{ .engine = engine, .kind = kind, .data = c.JS_DupValue(engine.context, data) };
    _ = c.JS_SetOpaque(value, self);
    if (kind == .model_runtime) {
        if (engine.native_sdk_next_runtime_id > 9007199254740991) return error.NativeSDKRuntimeLimit;
        self.runtime_id = engine.native_sdk_next_runtime_id;
        engine.native_sdk_next_runtime_id += 1;
    }
    const methods: []const Method = switch (kind) {
        .session_manager => &.{},
        .settings_manager => &.{},
        .model_registry => &.{},
        .resource_loader => &.{ .reload, .getExtensions, .getSkills, .getPrompts, .getThemes, .getAgentsFiles, .getSystemPrompt, .getAppendSystemPrompt, .getSystemPromptSource, .getAppendSystemPromptSources, .extendResources },
        .model_runtime => &.{ .registerProvider, .registerNativeProvider, .unregisterProvider, .registerVirtualModel, .unregisterVirtualModel, .resolveModel, .getPhysicalModel, .getProviders, .getProvider, .getModels, .getAll, .getAvailable, .getModel, .getModelsOfType, .getModelOfType, .getAllModels, .getAllAvailable, .getAvailableOfType, .checkAuth, .getAuth, .getAvailableSnapshot, .setRuntimeApiKey, .removeRuntimeApiKey, .hasConfiguredAuth, .clearRuntimeApiKey, .refresh, .streamSimple, .completeSimple, .stream, .complete, .streamDeferred, .fetchDeferred, .cancelDeferred, .classify, .generateImages, .getError, .getProviderAuthStatus, .isUsingOAuth, .isUsingSubscription, .getRegisteredProviderIds, .getRegisteredNativeProvider, .getRegisteredProviderConfig, .listCredentials },
        .agent_session => &.{ .subscribe, .unsubscribe, .dispose, .prompt, .abort, .bindExtensions, .getActiveToolNames, .setActiveToolsByName, .getAllTools, .getToolDefinition, .setSessionName, .setThinkingLevel, .getAvailableThinkingLevels, .cycleThinkingLevel, .supportsThinking, .setScopedModels, .waitForIdle, .getLastAssistantText, .setModel, .getSessionStats, .clearQueue, .steer, .followUp, .newSession },
        .session_runtime => &.{ .newSession, .switchSession, .dispose, .setRebindSession, .setBeforeSessionInvalidate },
    };
    for (methods) |operation| {
        const name = try engine.gpa.dupeZ(u8, @tagName(operation));
        defer engine.gpa.free(name);
        const arity: c_int = if (kind == .agent_session) switch (operation) {
            .getActiveToolNames, .getAllTools, .getAvailableThinkingLevels, .cycleThinkingLevel, .supportsThinking, .waitForIdle, .getLastAssistantText, .dispose, .abort, .getSessionStats, .clearQueue => 0,
            else => 1,
        } else 1;
        try put(engine, value, name, try engine.checked(c.pi_js_function_magic(engine.context, method, name, arity, @intFromEnum(operation))));
    }
    if (kind == .agent_session or kind == .session_runtime) inline for (std.meta.fields(Getter)) |field| {
        if (kind != .session_runtime or (field.value != @intFromEnum(Getter.state) and field.value != @intFromEnum(Getter.isIdle) and field.value != @intFromEnum(Getter.scopedModels) and field.value != @intFromEnum(Getter.promptTemplates))) {
            const atom = c.JS_NewAtom(engine.context, field.name);
            defer c.JS_FreeAtom(engine.context, atom);
            const read = try engine.checked(c.pi_js_function_magic(engine.context, getter, field.name, 0, @intCast(field.value)));
            if (c.JS_DefinePropertyGetSet(engine.context, value, atom, read, c.pi_js_undefined(), c.JS_PROP_CONFIGURABLE | c.JS_PROP_ENUMERABLE) < 0) return error.JavaScriptException;
        }
    };
    return value;
}
fn getter(context: ?*c.JSContext, receiver: c.JSValue, _: c_int, _: [*c]c.JSValue, magic: c_int) callconv(.c) c.JSValue {
    const engine = engine_mod.Engine.fromContext(context.?);
    const self = state(engine, receiver) catch |err| return fail(engine, err);
    return getterValue(self, @enumFromInt(magic)) catch |err| fail(engine, err);
}
fn getterValue(self: *State, which: Getter) !c.JSValue {
    const engine = self.engine;
    if (self.kind == .session_runtime) {
        if (which == .cwd) {
            const service = try get(engine, self.data, "services");
            defer engine.freeValue(service);
            return get(engine, service, "cwd");
        }
        return get(engine, self.data, @tagName(which));
    }
    if (self.kind == .agent_session) {
        if (which == .model or which == .thinkingLevel or which == .messages) return agentField(self, @tagName(which));
        if (which == .state) {
            const agent = try get(engine, self.data, "agent");
            defer engine.freeValue(agent);
            return get(engine, agent, "state");
        }
        if (which == .isIdle) return c.pi_js_bool(engine.context, @intFromBool(!self.running));
        if (which == .promptTemplates) {
            const loader = try get(engine, self.data, "resourceLoader");
            defer engine.freeValue(loader);
            const prompts = try invoke(engine, loader, "getPrompts", &.{});
            defer engine.freeValue(prompts);
            return get(engine, prompts, "prompts");
        }
    }
    if (which == .isStreaming) return c.pi_js_bool(engine.context, @intFromBool(self.running and !self.disposed));
    if (which == .sessionId or which == .sessionFile or which == .sessionName) {
        const manager = try get(engine, self.data, "sessionManager");
        defer engine.freeValue(manager);
        if (which == .sessionName) {
            const rows = try invoke(engine, manager, "getBranch", &.{});
            defer engine.freeValue(rows);
            var i = try length(engine, rows);
            while (i > 0) {
                i -= 1;
                const row = try engine.checked(c.JS_GetPropertyUint32(engine.context, rows, i));
                defer engine.freeValue(row);
                const typ = try get(engine, row, "type");
                defer engine.freeValue(typ);
                const label = try engine.toString(typ);
                defer engine.gpa.free(label);
                if (std.mem.eql(u8, label, "session_info")) return get(engine, row, "name");
            }
            return c.pi_js_undefined();
        }
        return invoke(engine, manager, if (which == .sessionId) "getSessionId" else "getSessionFile", &.{});
    }
    return get(engine, self.data, @tagName(which));
}
pub fn agentField(self: *State, name: [*:0]const u8) !c.JSValue {
    const agent = try get(self.engine, self.data, "agent");
    defer self.engine.freeValue(agent);
    if (!c.JS_IsObject(agent)) return get(self.engine, self.data, name);
    const view = try get(self.engine, agent, "state");
    defer self.engine.freeValue(view);
    return get(self.engine, view, name);
}
pub fn setAgentField(self: *State, name: [*:0]const u8, value: c.JSValue) !void {
    const agent = try get(self.engine, self.data, "agent");
    defer self.engine.freeValue(agent);
    const state_value = try get(self.engine, agent, "state");
    defer self.engine.freeValue(state_value);
    if (c.JS_SetPropertyStr(self.engine.context, state_value, name, c.JS_DupValue(self.engine.context, value)) < 0) return @import("native_js_values.zig").capture(self.engine);
    try put(self.engine, self.data, name, c.JS_DupValue(self.engine.context, value));
}
pub fn emit(self: *State, notification: c.JSValue) !void {
    var listeners: std.ArrayList(c.JSValue) = .empty;
    defer {
        for (listeners.items) |listener| self.engine.freeValue(listener);
        listeners.deinit(self.engine.gpa);
    }
    try listeners.ensureTotalCapacity(self.engine.gpa, self.listeners.items.len);
    for (self.listeners.items) |listener| listeners.appendAssumeCapacity(c.JS_DupValue(self.engine.context, listener));
    for (listeners.items) |listener| {
        if (self.disposed) break;
        var args = [_]c.JSValue{notification};
        const value = try self.engine.checked(c.JS_Call(self.engine.context, listener, c.pi_js_undefined(), 1, &args));
        self.engine.freeValue(value);
    }
}
fn event(self: *State, name: []const u8) !c.JSValue {
    const value = try object(self.engine);
    errdefer self.engine.freeValue(value);
    try put(self.engine, value, "type", try text(self.engine, name));
    return value;
}
fn unsubscribeCallback(context: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue, _: c_int, data: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = engine_mod.Engine.fromContext(context.?);
    const self = state(engine, data[0]) catch return c.pi_js_undefined();
    for (self.listeners.items, 0..) |listener, i| if (c.JS_IsStrictEqual(engine.context, listener, data[1])) {
        engine.freeValue(self.listeners.orderedRemove(i));
        break;
    };
    return c.pi_js_undefined();
}
fn promptJob(context: ?*c.JSContext, argc: c_int, args: [*c]c.JSValue) callconv(.c) c.JSValue {
    _ = argc;
    const engine = engine_mod.Engine.fromContext(context.?);
    const self = state(engine, args[0]) catch return c.pi_js_undefined();
    var rejection: ?c.JSValue = null;
    runPrompt(self, args[1], args[2]) catch |err| {
        const raised = fail(engine, err);
        _ = raised;
        rejection = c.JS_GetException(context);
    };
    self.running = false;
    const idle_resolve = get(engine, self.data, "promptIdleResolve") catch return c.JS_ThrowOutOfMemory(context);
    defer engine.freeValue(idle_resolve);
    const idle_result = c.JS_Call(context, idle_resolve, c.pi_js_undefined(), 0, null);
    engine.freeValue(idle_result);
    const value = rejection orelse c.pi_js_undefined();
    defer if (rejection) |held| engine.freeValue(held);
    var values = [_]c.JSValue{value};
    const result = c.JS_Call(context, if (rejection == null) args[3] else args[4], c.pi_js_undefined(), 1, &values);
    return result;
}
fn startPrompt(self: *State, receiver: c.JSValue, args: []const c.JSValue) !c.JSValue {
    if (self.running) return error.NativeSDKPromptAlreadyRunning;
    if (args.len == 0 or !c.JS_IsString(args[0])) return error.NativeSDKMissingPrompt;
    const engine = self.engine;
    var functions: [2]c.JSValue = undefined;
    const result = try engine.checked(c.JS_NewPromiseCapability(engine.context, &functions));
    errdefer engine.freeValue(result);
    defer for (functions) |function| engine.freeValue(function);
    if (!engine.abort_signals_ready) try @import("abort_signal.zig").install(engine);
    const signal = try @import("abort_signal.zig").create(engine);
    defer engine.freeValue(signal);
    try put(engine, self.data, "promptSignal", c.JS_DupValue(engine.context, signal));
    var idle_functions: [2]c.JSValue = undefined;
    const idle = try engine.checked(c.JS_NewPromiseCapability(engine.context, &idle_functions));
    defer engine.freeValue(idle);
    defer for (idle_functions) |function| engine.freeValue(function);
    try put(engine, self.data, "promptIdle", c.JS_DupValue(engine.context, idle));
    try put(engine, self.data, "promptIdleResolve", c.JS_DupValue(engine.context, idle_functions[0]));
    var task = [_]c.JSValue{ receiver, args[0], if (args.len > 1) args[1] else c.pi_js_undefined(), functions[0], functions[1] };
    if (c.JS_EnqueueJob(engine.context, promptJob, task.len, &task) < 0) return error.OutOfMemory;
    self.running = true;
    self.aborted = false;
    return result;
}
fn runPrompt(self: *State, prompt_text: c.JSValue, _: c.JSValue) !void {
    const engine = self.engine;
    if (self.disposed) return error.NativeSDKDisposed;
    const model = try agentField(self, "model");
    defer engine.freeValue(model);
    if (!c.JS_IsObject(model)) return error.NativeSDKNoModelSelected;
    const runtime = try get(engine, self.data, "modelRuntime");
    defer engine.freeValue(runtime);
    const manager = try get(engine, self.data, "sessionManager");
    defer engine.freeValue(manager);
    const messages = try agentField(self, "messages");
    defer engine.freeValue(messages);
    const start = try event(self, "agent_start");
    defer engine.freeValue(start);
    try emit(self, start);
    const turn_start = try event(self, "turn_start");
    defer engine.freeValue(turn_start);
    try emit(self, turn_start);
    if (try length(engine, messages) == 0) {
        const system = try object(engine);
        defer engine.freeValue(system);
        try put(engine, system, "role", try text(engine, "system"));
        try put(engine, system, "content", try text(engine, ""));
        const sections = try object(engine);
        defer engine.freeValue(sections);
        try put(engine, sections, "preamble", try get(engine, self.data, "systemPrompt"));
        const working_value = try invoke(engine, manager, "getCwd", &.{});
        defer engine.freeValue(working_value);
        const working = try engine.toString(working_value);
        defer engine.gpa.free(working);
        std.mem.replaceScalar(u8, working, '\\', '/');
        const section_cwd = try std.fmt.allocPrint(engine.gpa, "<cwd>\n{s}\n</cwd>", .{working});
        defer engine.gpa.free(section_cwd);
        try put(engine, sections, "cwd", try text(engine, section_cwd));
        try put(engine, system, "sections", c.JS_DupValue(engine.context, sections));
        try put(engine, system, "timestamp", c.JS_NewInt64(engine.context, if (engine.native_io) |io| std.Io.Clock.real.now(io).toMilliseconds() else 0));
        try emitMessage(self, "message_start", system);
        try append(engine, messages, c.JS_DupValue(engine.context, system));
        const system_id = try invoke(engine, manager, "appendMessage", &.{system});
        engine.freeValue(system_id);
        try emitMessage(self, "message_end", system);
    }
    const user = try object(engine);
    defer engine.freeValue(user);
    try put(engine, user, "role", try text(engine, "user"));
    const contents = try array(engine);
    const block = try object(engine);
    defer engine.freeValue(block);
    try put(engine, block, "type", try text(engine, "text"));
    try put(engine, block, "text", c.JS_DupValue(engine.context, prompt_text));
    try append(engine, contents, c.JS_DupValue(engine.context, block));
    try put(engine, user, "content", contents);
    try put(engine, user, "timestamp", c.JS_NewInt64(engine.context, if (engine.native_io) |io| std.Io.Clock.real.now(io).toMilliseconds() else 0));
    try emitMessage(self, "message_start", user);
    try append(engine, messages, c.JS_DupValue(engine.context, user));
    const user_id = try invoke(engine, manager, "appendMessage", &.{user});
    engine.freeValue(user_id);
    try emitMessage(self, "message_end", user);
    for (0..64) |_| {
        if (self.aborted or self.disposed) break;
        const ctx = try object(engine);
        defer engine.freeValue(ctx);
        try put(engine, ctx, "messages", c.JS_DupValue(engine.context, messages));
        try put(engine, ctx, "systemPrompt", try get(engine, self.data, "systemPrompt"));
        try put(engine, ctx, "tools", try @import("native_sdk_tool_catalog.zig").activeDefinitions(self));
        const options = try object(engine);
        defer engine.freeValue(options);
        const selected_level = try agentField(self, "thinkingLevel");
        defer engine.freeValue(selected_level);
        const signal = try get(engine, self.data, "promptSignal");
        defer engine.freeValue(signal);
        var routing_error: ?anyerror = null;
        const projection = if (try @import("native_sdk_virtual.zig").isVirtual(engine, model)) projected: {
            break :projected @import("native_sdk_virtual.zig").sessionProjection(engine, runtime, manager, model, messages, selected_level, signal) catch |err| {
                routing_error = err;
                break :projected c.pi_js_undefined();
            };
        } else c.pi_js_undefined();
        defer engine.freeValue(projection);
        const request_model = if (c.JS_IsObject(projection)) try get(engine, projection, "model") else c.JS_DupValue(engine.context, model);
        defer engine.freeValue(request_model);
        const request_level = if (c.JS_IsObject(projection)) try get(engine, projection, "thinkingLevel") else c.JS_DupValue(engine.context, selected_level);
        defer engine.freeValue(request_level);
        if (c.JS_IsObject(projection)) {
            const state_entry = try get(engine, projection, "stateEntry");
            defer engine.freeValue(state_entry);
            if (c.JS_IsObject(state_entry)) {
                const appended = try event(self, "entry_appended");
                defer engine.freeValue(appended);
                try put(engine, appended, "entry", c.JS_DupValue(engine.context, state_entry));
                try emit(self, appended);
            }
        }
        try put(engine, options, "reasoning", c.JS_DupValue(engine.context, request_level));
        try put(engine, options, "signal", c.JS_DupValue(engine.context, signal));
        const streamed = if (routing_error) |err| failed: {
            const exports = engine.native_module_values.get("pi-ai") orelse return error.NativeSDKModelModuleUnavailable;
            const output = try invoke(engine, exports, "createAssistantMessageEventStream", &.{});
            errdefer engine.freeValue(output);
            try @import("native_sdk_chat.zig").finishError(engine, model, output, err);
            break :failed output;
        } else try invoke(engine, runtime, "streamSimple", &.{ request_model, ctx, options });
        defer engine.freeValue(streamed);
        const stream = try engine.awaitValue(streamed);
        defer engine.freeValue(stream);
        const iterator_fn = try engine.checked(c.JS_GetProperty(engine.context, stream, engine.event_stream_async_atom));
        defer engine.freeValue(iterator_fn);
        if (!c.JS_IsFunction(engine.context, iterator_fn)) return error.NativeSDKProviderStreamNotIterable;
        const iterator = try engine.checked(c.JS_Call(engine.context, iterator_fn, stream, 0, null));
        defer engine.freeValue(iterator);
        var final = c.pi_js_undefined();
        defer engine.freeValue(final);
        for (0..100000) |_| {
            const pending = try invoke(engine, iterator, "next", &.{});
            defer engine.freeValue(pending);
            const step = try engine.awaitValue(pending);
            defer engine.freeValue(step);
            const done = try get(engine, step, "done");
            defer engine.freeValue(done);
            if (c.JS_ToBool(engine.context, done) == 1) break;
            const update = try get(engine, step, "value");
            defer engine.freeValue(update);
            const typ = try get(engine, update, "type");
            defer engine.freeValue(typ);
            const kind = try engine.toString(typ);
            defer engine.gpa.free(kind);
            if (std.mem.eql(u8, kind, "start")) {
                const partial = try get(engine, update, "partial");
                defer engine.freeValue(partial);
                try emitMessage(self, "message_start", partial);
            } else if (!std.mem.eql(u8, kind, "done") and !std.mem.eql(u8, kind, "error")) {
                const emitted = try event(self, "message_update");
                defer engine.freeValue(emitted);
                try put(engine, emitted, "assistantMessageEvent", c.JS_DupValue(engine.context, update));
                try put(engine, emitted, "message", try get(engine, update, "partial"));
                try emit(self, emitted);
            }
            if (std.mem.eql(u8, kind, "done") or std.mem.eql(u8, kind, "error")) {
                engine.freeValue(final);
                final = try get(engine, update, if (std.mem.eql(u8, kind, "done")) "message" else "error");
            }
            if (self.aborted or self.disposed) {
                const returned = try invoke(engine, iterator, "return", &.{});
                defer engine.freeValue(returned);
                const settled = try engine.awaitValue(returned);
                engine.freeValue(settled);
                break;
            }
        }
        if (c.JS_IsUndefined(final)) {
            const get_result = try get(engine, stream, "result");
            defer engine.freeValue(get_result);
            if (c.JS_IsFunction(engine.context, get_result)) {
                const pending = try invoke(engine, stream, "result", &.{});
                defer engine.freeValue(pending);
                engine.freeValue(final);
                final = try engine.awaitValue(pending);
            }
        }
        if (!c.JS_IsObject(final)) {
            if (self.aborted or self.disposed) break;
            return error.NativeSDKProviderStreamMissingMessage;
        }
        if (c.JS_IsObject(projection)) try put(engine, final, "thinkingLevel", c.JS_DupValue(engine.context, request_level));
        try append(engine, messages, c.JS_DupValue(engine.context, final));
        const assistant_id = try invoke(engine, manager, "appendMessage", &.{final});
        engine.freeValue(assistant_id);
        const ended = try event(self, "message_end");
        defer engine.freeValue(ended);
        try put(engine, ended, "message", c.JS_DupValue(engine.context, final));
        try emit(self, ended);
        const content = try get(engine, final, "content");
        defer engine.freeValue(content);
        var invoked = false;
        const definitions = try @import("native_sdk_tool_catalog.zig").activeDefinitions(self);
        defer engine.freeValue(definitions);
        for (0..try length(engine, content)) |i| {
            const call = try engine.checked(c.JS_GetPropertyUint32(engine.context, content, @intCast(i)));
            defer engine.freeValue(call);
            const typ = try get(engine, call, "type");
            defer engine.freeValue(typ);
            const label = try engine.toString(typ);
            defer engine.gpa.free(label);
            if (!std.mem.eql(u8, label, "toolCall")) continue;
            const name = try get(engine, call, "name");
            defer engine.freeValue(name);
            const id = try get(engine, call, "id");
            defer engine.freeValue(id);
            const arguments = try get(engine, call, "arguments");
            defer engine.freeValue(arguments);
            var found = false;
            for (0..try length(engine, definitions)) |j| {
                const tool = try engine.checked(c.JS_GetPropertyUint32(engine.context, definitions, @intCast(j)));
                defer engine.freeValue(tool);
                const candidate = try get(engine, tool, "name");
                defer engine.freeValue(candidate);
                if (!c.JS_IsStrictEqual(engine.context, name, candidate)) continue;
                found = true;
                const context_value = try object(engine);
                defer engine.freeValue(context_value);
                try put(engine, context_value, "sessionManager", c.JS_DupValue(engine.context, manager));
                try put(engine, context_value, "model", c.JS_DupValue(engine.context, model));
                try put(engine, context_value, "cwd", try get(engine, self.data, "_sdkToolCwd"));
                const prepare = try get(engine, tool, "prepareArguments");
                defer engine.freeValue(prepare);
                const prepared = if (c.JS_IsFunction(engine.context, prepare)) try invoke(engine, tool, "prepareArguments", &.{arguments}) else c.JS_DupValue(engine.context, arguments);
                defer engine.freeValue(prepared);
                const validation_call = try object(engine);
                defer engine.freeValue(validation_call);
                try put(engine, validation_call, "name", c.JS_DupValue(engine.context, name));
                try put(engine, validation_call, "arguments", c.JS_DupValue(engine.context, prepared));
                const validated = try @import("native_tool_arguments.zig").validateArguments(engine, tool, validation_call);
                defer engine.freeValue(validated);
                const pending = try invoke(engine, tool, "execute", &.{ id, validated, signal, c.pi_js_undefined(), context_value });
                defer engine.freeValue(pending);
                const result = try engine.awaitValue(pending);
                defer engine.freeValue(result);
                const message = try object(engine);
                defer engine.freeValue(message);
                try put(engine, message, "role", try text(engine, "toolResult"));
                try put(engine, message, "toolCallId", c.JS_DupValue(engine.context, id));
                try put(engine, message, "toolName", c.JS_DupValue(engine.context, name));
                try put(engine, message, "content", try get(engine, result, "content"));
                const result_error = try get(engine, result, "isError");
                defer engine.freeValue(result_error);
                try put(engine, message, "isError", c.pi_js_bool(engine.context, @intFromBool(c.JS_ToBool(engine.context, result_error) == 1)));
                try put(engine, message, "details", try get(engine, result, "details"));
                const structured = try get(engine, result, "structuredContent");
                defer engine.freeValue(structured);
                if (!c.JS_IsUndefined(structured)) try put(engine, message, "structuredContent", c.JS_DupValue(engine.context, structured));
                try append(engine, messages, c.JS_DupValue(engine.context, message));
                const result_id = try invoke(engine, manager, "appendMessage", &.{message});
                engine.freeValue(result_id);
                break;
            }
            if (!found) return error.NativeSDKToolUnavailable;
            invoked = true;
        }
        const turn_end = try event(self, "turn_end");
        defer engine.freeValue(turn_end);
        try put(engine, turn_end, "message", c.JS_DupValue(engine.context, final));
        try put(engine, turn_end, "toolResults", try array(engine));
        try emit(self, turn_end);
        if (!invoked) break;
        try emit(self, turn_start);
    }
    const end = try event(self, "agent_end");
    defer engine.freeValue(end);
    try put(engine, end, "messages", c.JS_DupValue(engine.context, messages));
    try emit(self, end);
    const settled = try event(self, "agent_settled");
    defer engine.freeValue(settled);
    try put(engine, settled, "aborted", c.pi_js_bool(engine.context, @intFromBool(self.aborted)));
    try emit(self, settled);
}
fn emitMessage(self: *State, kind: []const u8, message: c.JSValue) !void {
    const value = try event(self, kind);
    defer self.engine.freeValue(value);
    try put(self.engine, value, "message", c.JS_DupValue(self.engine.context, message));
    try emit(self, value);
}
pub fn cwd(engine: *engine_mod.Engine) ![]u8 {
    if (engine.native_io) |io| {
        var buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
        const directory = try std.Io.Dir.cwd().openDir(io, ".", .{});
        defer directory.close(io);
        const count = try directory.realPath(io, &buffer);
        return engine.gpa.dupe(u8, buffer[0..count]);
    }
    return engine.gpa.dupe(u8, ".");
}
pub fn agentDir(engine: *engine_mod.Engine) ![]u8 {
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    const process = try get(engine, global, "process");
    defer engine.freeValue(process);
    if (c.JS_IsObject(process)) {
        const env = try get(engine, process, "env");
        defer engine.freeValue(env);
        if (c.JS_IsObject(env)) {
            inline for (.{ "PI_CODING_AGENT_DIR", "PI_AGENT_DIR" }) |name| {
                const configured = try get(engine, env, name);
                defer engine.freeValue(configured);
                if (c.JS_IsString(configured) and c.JS_ToBool(engine.context, configured) != 0) {
                    const normalized = try @import("native_sdk_settings.zig").normalizePath(engine, configured);
                    defer engine.freeValue(normalized);
                    return engine.toString(normalized);
                }
            }
            const home = try get(engine, env, if (@import("builtin").os.tag == .windows) "USERPROFILE" else "HOME");
            defer engine.freeValue(home);
            if (c.JS_IsString(home)) {
                const path = try engine.toString(home);
                defer engine.gpa.free(path);
                return std.fs.path.join(engine.gpa, &.{ path, ".pi", "agent" });
            }
        }
    }
    const base = try cwd(engine);
    defer engine.gpa.free(base);
    return std.fs.path.join(engine.gpa, &.{ base, ".pi", "agent" });
}
var ids = std.atomic.Value(u64).init(1);
pub fn identifier(engine: *engine_mod.Engine, prefix: []const u8) !c.JSValue {
    if (std.mem.eql(u8, prefix, "session")) {
        var bytes: [16]u8 = undefined;
        if (engine.native_io) |io| std.Io.random(io, &bytes) else {
            var random = std.Random.DefaultPrng.init(ids.fetchAdd(1, .monotonic));
            random.random().bytes(&bytes);
        }
        const milliseconds: u64 = if (engine.native_io) |io| @intCast(std.Io.Clock.real.now(io).toMilliseconds()) else ids.fetchAdd(1, .monotonic);
        for (0..6) |index| bytes[index] = @truncate(milliseconds >> @as(u6, @intCast((5 - index) * 8)));
        bytes[6] = (bytes[6] & 15) | 112;
        bytes[8] = (bytes[8] & 63) | 128;
        const hex = std.fmt.bytesToHex(bytes, .lower);
        const raw = try std.fmt.allocPrint(engine.gpa, "{s}-{s}-{s}-{s}-{s}", .{ hex[0..8], hex[8..12], hex[12..16], hex[16..20], hex[20..32] });
        defer engine.gpa.free(raw);
        return text(engine, raw);
    }
    var bytes: [4]u8 = undefined;
    if (engine.native_io) |io| std.Io.random(io, &bytes) else std.mem.writeInt(u32, &bytes, @truncate(ids.fetchAdd(1, .monotonic)), .big);
    const raw = std.fmt.bytesToHex(bytes, .lower);
    return text(engine, &raw);
}
fn timestamp(engine: *engine_mod.Engine) !c.JSValue {
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    const date_ctor = try get(engine, global, "Date");
    defer engine.freeValue(date_ctor);
    const date = try engine.checked(c.JS_CallConstructor(engine.context, date_ctor, 0, null));
    defer engine.freeValue(date);
    return invoke(engine, date, "toISOString", &.{});
}
pub fn length(engine: *engine_mod.Engine, value: c.JSValue) !u32 {
    const len = try get(engine, value, "length");
    defer engine.freeValue(len);
    var result: u32 = 0;
    if (c.JS_ToUint32(engine.context, &result, len) < 0) return error.JavaScriptException;
    return result;
}
pub fn append(engine: *engine_mod.Engine, values: c.JSValue, value: c.JSValue) !void {
    if (c.JS_SetPropertyUint32(engine.context, values, try length(engine, values), value) < 0) return error.JavaScriptException;
}
pub fn resolveSdkPath(engine: *engine_mod.Engine, value: c.JSValue) ![]u8 {
    const normalized = try @import("native_sdk_settings.zig").normalizePath(engine, value);
    defer engine.freeValue(normalized);
    const path = try engine.toString(normalized);
    defer engine.gpa.free(path);
    const base = try cwd(engine);
    defer engine.gpa.free(base);
    return @import("node_path.zig").resolve(engine.gpa, base, &.{path}, if (@import("builtin").os.tag == .windows) .win32 else .posix);
}
pub fn initManager(engine: *engine_mod.Engine, args: []const c.JSValue, persistent: bool) !c.JSValue {
    const data = try object(engine);
    defer engine.freeValue(data);
    var has_imported_header = false;
    if (!persistent and args.len > 2 and c.JS_IsArray(args[2])) {
        for (0..try length(engine, args[2])) |index| {
            const row = try engine.checked(c.JS_GetPropertyUint32(engine.context, args[2], @intCast(index)));
            defer engine.freeValue(row);
            const typ = try get(engine, row, "type");
            defer engine.freeValue(typ);
            const label = try text(engine, "session");
            defer engine.freeValue(label);
            if (c.JS_IsStrictEqual(engine.context, typ, label)) {
                has_imported_header = true;
                break;
            }
        }
        if (has_imported_header) _ = try @import("native_sdk_session_projection.zig").migrate(engine, args[2]);
    }
    const current = if (args.len > 0 and c.JS_IsString(args[0])) if (engine.native_io != null) try resolveSdkPath(engine, args[0]) else try engine.toString(args[0]) else try cwd(engine);
    defer engine.gpa.free(current);
    try put(engine, data, "cwd", try text(engine, current));
    const directory = if (!persistent) try engine.gpa.dupe(u8, "") else if (args.len > 1 and c.JS_IsString(args[1]) and c.JS_ToBool(engine.context, args[1]) == 1) try engine.toString(args[1]) else blk: {
        const root = try agentDir(engine);
        defer engine.gpa.free(root);
        const encoded = try encodeCwd(engine, current);
        defer engine.gpa.free(encoded);
        break :blk try std.fs.path.join(engine.gpa, &.{ root, "sessions", encoded });
    };
    defer engine.gpa.free(directory);
    try put(engine, data, "sessionDir", try text(engine, directory));
    try put(engine, data, "persistent", c.pi_js_bool(engine.context, @intFromBool(persistent)));
    try put(engine, data, "entries", try array(engine));
    try put(engine, data, "leafId", c.pi_js_null());
    const header = try object(engine);
    defer engine.freeValue(header);
    try put(engine, header, "type", try text(engine, "session"));
    try put(engine, header, "version", c.JS_NewInt32(engine.context, 3));
    try put(engine, header, "id", try identifier(engine, "session"));
    const options_index: usize = if (persistent) 2 else 1;
    if (!has_imported_header and args.len > options_index and c.JS_IsObject(args[options_index])) {
        const chosen = try get(engine, args[options_index], "id");
        defer engine.freeValue(chosen);
        if (!c.JS_IsUndefined(chosen)) {
            const raw = try engine.toString(chosen);
            defer engine.gpa.free(raw);
            var valid = raw.len > 0 and std.ascii.isAlphanumeric(raw[0]) and std.ascii.isAlphanumeric(raw[raw.len - 1]);
            for (raw) |byte| if (!std.ascii.isAlphanumeric(byte) and byte != '.' and byte != '_' and byte != '-') {
                valid = false;
                break;
            };
            if (!valid) {
                const ignored = try sourceError(engine, "Session id must be non-empty, contain only alphanumeric characters, '-', '_', and '.', and start and end with an alphanumeric character");
                engine.freeValue(ignored);
            }
            if (!c.JS_IsNull(chosen)) try put(engine, header, "id", c.JS_DupValue(engine.context, chosen));
        }
    }
    try put(engine, header, "timestamp", try timestamp(engine));
    try put(engine, header, "cwd", try text(engine, current));
    try put(engine, header, "parentSession", if (args.len > options_index and c.JS_IsObject(args[options_index])) try get(engine, args[options_index], "parentSession") else c.pi_js_undefined());
    try put(engine, data, "header", c.JS_DupValue(engine.context, header));
    if (!persistent and args.len > 2 and c.JS_IsArray(args[2])) {
        const imported = try array(engine);
        defer engine.freeValue(imported);
        var loaded_header = false;
        for (0..try length(engine, args[2])) |index| {
            const row = try engine.checked(c.JS_GetPropertyUint32(engine.context, args[2], @intCast(index)));
            defer engine.freeValue(row);
            const typ = try get(engine, row, "type");
            defer engine.freeValue(typ);
            const kind = try engine.toString(typ);
            defer engine.gpa.free(kind);
            if (std.mem.eql(u8, kind, "session")) {
                if (!loaded_header) {
                    try put(engine, data, "header", c.JS_DupValue(engine.context, row));
                    loaded_header = true;
                }
            } else {
                try append(engine, imported, c.JS_DupValue(engine.context, row));
                try put(engine, data, "leafId", try get(engine, row, "id"));
            }
        }
        try put(engine, data, "entries", c.JS_DupValue(engine.context, imported));
    }
    if (persistent) {
        const id = try get(engine, header, "id");
        defer engine.freeValue(id);
        const id_text = try engine.toString(id);
        defer engine.gpa.free(id_text);
        const created = try get(engine, header, "timestamp");
        defer engine.freeValue(created);
        const stamp = try engine.toString(created);
        defer engine.gpa.free(stamp);
        for (stamp) |*byte| if (byte.* == ':' or byte.* == '.') {
            byte.* = '-';
        };
        const name = try std.fmt.allocPrint(engine.gpa, "{s}_{s}.jsonl", .{ stamp, id_text });
        defer engine.gpa.free(name);
        const path = try std.fs.path.join(engine.gpa, &.{ directory, name });
        defer engine.gpa.free(path);
        try put(engine, data, "sessionFile", try text(engine, path));
        if (engine.native_io) |io| try std.Io.Dir.cwd().createDirPath(io, directory);
    }
    try rebuildSessionIndex(engine, data);
    return new(engine, .session_manager, data);
}
fn indexSessionEntry(engine: *engine_mod.Engine, data: c.JSValue, row: c.JSValue) !void {
    const index = try get(engine, data, "entryIndex");
    defer engine.freeValue(index);
    const id = try get(engine, row, "id");
    defer engine.freeValue(id);
    const added = try invoke(engine, index, "set", &.{ id, row });
    engine.freeValue(added);
    const typ = try get(engine, row, "type");
    defer engine.freeValue(typ);
    const label_type = try text(engine, "label");
    defer engine.freeValue(label_type);
    if (c.JS_IsStrictEqual(engine.context, typ, label_type)) {
        const target = try get(engine, row, "targetId");
        defer engine.freeValue(target);
        const label = try get(engine, row, "label");
        defer engine.freeValue(label);
        const stamp = try get(engine, row, "timestamp");
        defer engine.freeValue(stamp);
        inline for (.{ .{ "sessionLabels", label }, .{ "sessionLabelTimes", stamp } }) |field| {
            const map = try get(engine, data, field[0]);
            defer engine.freeValue(map);
            const result = if (c.JS_ToBool(engine.context, label) == 1) try invoke(engine, map, "set", &.{ target, field[1] }) else try invoke(engine, map, "delete", &.{target});
            engine.freeValue(result);
        }
    }
}
pub fn rebuildSessionIndex(engine: *engine_mod.Engine, data: c.JSValue) !void {
    inline for (.{ "entryIndex", "sessionLabels", "sessionLabelTimes" }) |field| try put(engine, data, field, try @import("native_sdk_auth_snapshot.zig").collection(engine, "Map"));
    const entries = try get(engine, data, "entries");
    defer engine.freeValue(entries);
    for (0..try length(engine, entries)) |i| {
        const row = try engine.checked(c.JS_GetPropertyUint32(engine.context, entries, @intCast(i)));
        defer engine.freeValue(row);
        try indexSessionEntry(engine, data, row);
    }
}
pub fn encodeCwd(engine: *engine_mod.Engine, input: []const u8) ![]u8 {
    const start: usize = if (input.len > 0 and (input[0] == '/' or input[0] == '\\')) 1 else 0;
    const result = try std.fmt.allocPrint(engine.gpa, "--{s}--", .{input[start..]});
    for (result) |*byte| if (byte.* == '/' or byte.* == '\\' or byte.* == ':') {
        byte.* = '-';
    };
    return result;
}
pub fn entry(self: *State, kind: []const u8) !c.JSValue {
    const engine = self.engine;
    const result = try object(engine);
    errdefer engine.freeValue(result);
    try put(engine, result, "type", try text(engine, kind));
    if (std.mem.eql(u8, kind, "custom") or std.mem.eql(u8, kind, "custom_message")) {
        try put(engine, result, "customType", c.pi_js_undefined());
        if (std.mem.eql(u8, kind, "custom")) try put(engine, result, "data", c.pi_js_undefined()) else {
            inline for (.{ "content", "display", "details" }) |field| try put(engine, result, field, c.pi_js_undefined());
        }
    }
    try put(engine, result, "id", try identifier(engine, "entry"));
    try put(engine, result, "parentId", try get(engine, self.data, "leafId"));
    try put(engine, result, "timestamp", try timestamp(engine));
    return result;
}
pub fn commitEntry(self: *State, value: c.JSValue) !c.JSValue {
    const engine = self.engine;
    const entries = try get(engine, self.data, "entries");
    defer engine.freeValue(entries);
    const id = try get(engine, value, "id");
    errdefer engine.freeValue(id);
    try append(engine, entries, c.JS_DupValue(engine.context, value));
    try indexSessionEntry(engine, self.data, value);
    try put(engine, self.data, "leafId", c.JS_DupValue(engine.context, id));
    try persist(self);
    return id;
}
fn persist(self: *State) !void {
    const engine = self.engine;
    const enabled = try get(engine, self.data, "persistent");
    defer engine.freeValue(enabled);
    if (c.JS_ToBool(engine.context, enabled) != 1) return;
    const path = try get(engine, self.data, "sessionFile");
    defer engine.freeValue(path);
    if (!c.JS_IsString(path)) return;
    const entries = try get(engine, self.data, "entries");
    defer engine.freeValue(entries);
    var has_assistant = false;
    for (0..try length(engine, entries)) |i| {
        const row = try engine.checked(c.JS_GetPropertyUint32(engine.context, entries, @intCast(i)));
        defer engine.freeValue(row);
        const message = try get(engine, row, "message");
        defer engine.freeValue(message);
        if (!c.JS_IsObject(message)) continue;
        const role = try get(engine, message, "role");
        defer engine.freeValue(role);
        const name = try engine.toString(role);
        defer engine.gpa.free(name);
        if (std.mem.eql(u8, name, "assistant") or std.mem.eql(u8, name, "user")) has_assistant = true;
    }
    if (!self.session_flushed and !has_assistant) return;
    var output: std.Io.Writer.Allocating = .init(engine.gpa);
    defer output.deinit();
    const header = try get(engine, self.data, "header");
    defer engine.freeValue(header);
    if (!self.session_flushed) {
        const raw_header = try engine.stringify(header);
        defer engine.gpa.free(raw_header);
        try output.writer.writeAll(raw_header);
        try output.writer.writeByte('\n');
    }
    const count = try length(engine, entries);
    for (self.persisted_count..count) |i| {
        const row = try engine.checked(c.JS_GetPropertyUint32(engine.context, entries, @intCast(i)));
        defer engine.freeValue(row);
        const raw = try engine.stringify(row);
        defer engine.gpa.free(raw);
        try output.writer.writeAll(raw);
        try output.writer.writeByte('\n');
    }
    const filename = try engine.toString(path);
    defer engine.gpa.free(filename);
    const io = engine.native_io orelse return error.NativeSDKRequiresIO;
    if (!self.session_flushed) {
        const file = try std.Io.Dir.cwd().createFile(io, filename, .{ .exclusive = true });
        defer file.close(io);
        try file.writeStreamingAll(io, output.written());
    } else {
        const file = try std.Io.Dir.cwd().openFile(io, filename, .{ .mode = .read_write });
        defer file.close(io);
        const info = try file.stat(io);
        try file.writePositionalAll(io, output.written(), info.size);
    }
    self.persisted_count = count;
    self.session_flushed = true;
}
pub fn findEntry(self: *State, id: c.JSValue) !c.JSValue {
    const engine = self.engine;
    const index = try get(engine, self.data, "entryIndex");
    defer engine.freeValue(index);
    return invoke(engine, index, "get", &.{id});
}
pub fn branchEntries(self: *State, from: c.JSValue) !c.JSValue {
    const engine = self.engine;
    var held: std.ArrayList(c.JSValue) = .empty;
    defer {
        for (held.items) |row| engine.freeValue(row);
        held.deinit(engine.gpa);
    }
    var current = c.JS_DupValue(engine.context, from);
    defer engine.freeValue(current);
    for (0..65536) |_| {
        if (!c.JS_IsString(current)) break;
        const row = try findEntry(self, current);
        defer engine.freeValue(row);
        if (c.JS_IsUndefined(row)) break;
        try held.ensureUnusedCapacity(engine.gpa, 1);
        held.appendAssumeCapacity(c.JS_DupValue(engine.context, row));
        const parent = try get(engine, row, "parentId");
        engine.freeValue(current);
        current = parent;
    }
    const result = try array(engine);
    errdefer engine.freeValue(result);
    for (0..held.items.len) |i| try append(engine, result, c.JS_DupValue(engine.context, held.items[held.items.len - 1 - i]));
    return result;
}
fn labelFor(self: *State, id: c.JSValue) !c.JSValue {
    const engine = self.engine;
    const labels = try get(engine, self.data, "sessionLabels");
    defer engine.freeValue(labels);
    return invoke(engine, labels, "get", &.{id});
}
fn sessionTree(self: *State) !c.JSValue {
    const engine = self.engine;
    const rows = try get(engine, self.data, "entries");
    defer engine.freeValue(rows);
    const nodes = try array(engine);
    defer engine.freeValue(nodes);
    for (0..try length(engine, rows)) |i| {
        const row = try engine.checked(c.JS_GetPropertyUint32(engine.context, rows, @intCast(i)));
        defer engine.freeValue(row);
        const node = try object(engine);
        defer engine.freeValue(node);
        try put(engine, node, "entry", c.JS_DupValue(engine.context, row));
        try put(engine, node, "children", try array(engine));
        const id = try get(engine, row, "id");
        defer engine.freeValue(id);
        const label = try labelFor(self, id);
        defer engine.freeValue(label);
        try put(engine, node, "label", c.JS_DupValue(engine.context, label));
        const times = try get(engine, self.data, "sessionLabelTimes");
        defer engine.freeValue(times);
        try put(engine, node, "labelTimestamp", try invoke(engine, times, "get", &.{id}));
        try append(engine, nodes, c.JS_DupValue(engine.context, node));
    }
    const roots = try array(engine);
    errdefer engine.freeValue(roots);
    for (0..try length(engine, nodes)) |i| {
        const node = try engine.checked(c.JS_GetPropertyUint32(engine.context, nodes, @intCast(i)));
        defer engine.freeValue(node);
        const row = try get(engine, node, "entry");
        defer engine.freeValue(row);
        const parent = try get(engine, row, "parentId");
        defer engine.freeValue(parent);
        const self_id = try get(engine, row, "id");
        defer engine.freeValue(self_id);
        var attached = false;
        if (c.JS_IsString(parent) and !c.JS_IsStrictEqual(engine.context, self_id, parent)) for (0..try length(engine, nodes)) |j| {
            const other = try engine.checked(c.JS_GetPropertyUint32(engine.context, nodes, @intCast(j)));
            defer engine.freeValue(other);
            const other_entry = try get(engine, other, "entry");
            defer engine.freeValue(other_entry);
            const id = try get(engine, other_entry, "id");
            defer engine.freeValue(id);
            if (!c.JS_IsStrictEqual(engine.context, id, parent)) continue;
            const children = try get(engine, other, "children");
            defer engine.freeValue(children);
            try append(engine, children, c.JS_DupValue(engine.context, node));
            attached = true;
            break;
        };
        if (!attached) try append(engine, roots, c.JS_DupValue(engine.context, node));
    }
    const compare = try engine.checked(c.JS_NewCFunction(engine.context, compareSessionNodes, "compareSessionNodes", 2));
    defer engine.freeValue(compare);
    for (0..try length(engine, nodes)) |index| {
        const node = try engine.checked(c.JS_GetPropertyUint32(engine.context, nodes, @intCast(index)));
        defer engine.freeValue(node);
        const children = try get(engine, node, "children");
        defer engine.freeValue(children);
        const sorted = try invoke(engine, children, "sort", &.{compare});
        engine.freeValue(sorted);
    }
    return roots;
}
fn compareSessionNodes(context: ?*c.JSContext, _: c.JSValue, argc: c_int, args: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = engine_mod.Engine.fromContext(context.?);
    if (argc < 2) return c.JS_NewInt32(engine.context, 0);
    var numbers: [2]f64 = undefined;
    for (0..2) |index| {
        const row = get(engine, args[index], "entry") catch |err| return fail(engine, err);
        defer engine.freeValue(row);
        const stamp = get(engine, row, "timestamp") catch |err| return fail(engine, err);
        defer engine.freeValue(stamp);
        const number = @import("native_sdk_session_projection.zig").dateTime(engine, stamp) catch |err| return fail(engine, err);
        defer engine.freeValue(number);
        if (c.JS_ToFloat64(engine.context, &numbers[index], number) < 0) return c.JS_Throw(engine.context, c.JS_GetException(engine.context));
    }
    return c.JS_NewFloat64(engine.context, numbers[0] - numbers[1]);
}

pub fn jsonObject(engine: *engine_mod.Engine, source: []const u8) !c.JSValue {
    const raw = try engine.gpa.dupeZ(u8, source);
    defer engine.gpa.free(raw);
    return engine.checked(c.JS_ParseJSON(engine.context, raw, source.len, "native-sdk-data"));
}
fn mergeJson(allocator: std.mem.Allocator, base: std.json.Value, updates: std.json.Value) !std.json.Value {
    if (base != .object or updates != .object) return updates;
    var result = base;
    var fields = updates.object.iterator();
    while (fields.next()) |field| {
        const previous = result.object.get(field.key_ptr.*) orelse std.json.Value.null;
        try result.object.put(allocator, field.key_ptr.*, try mergeJson(allocator, previous, field.value_ptr.*));
    }
    return result;
}
fn merge(engine: *engine_mod.Engine, base: c.JSValue, updates: c.JSValue) !c.JSValue {
    const raw_base = try engine.stringify(base);
    defer engine.gpa.free(raw_base);
    const raw_updates = try engine.stringify(updates);
    defer engine.gpa.free(raw_updates);
    var arena: std.heap.ArenaAllocator = .init(engine.gpa);
    defer arena.deinit();
    const old = try std.json.parseFromSliceLeaky(std.json.Value, arena.allocator(), raw_base, .{ .allocate = .alloc_always });
    const delta = try std.json.parseFromSliceLeaky(std.json.Value, arena.allocator(), raw_updates, .{ .allocate = .alloc_always });
    return engine.fromJsonValue(try mergeJson(arena.allocator(), old, delta));
}
fn optional(engine: *engine_mod.Engine, value: c.JSValue, key: [*:0]const u8, fallback: c.JSValue) !c.JSValue {
    const candidate = try get(engine, value, key);
    if (!c.JS_IsUndefined(candidate)) return candidate;
    engine.freeValue(candidate);
    return c.JS_DupValue(engine.context, fallback);
}
fn loadJsonFile(engine: *engine_mod.Engine, path: []const u8) !c.JSValue {
    const io = engine.native_io orelse return error.NativeSDKRequiresIO;
    const raw = std.Io.Dir.cwd().readFileAlloc(io, path, engine.gpa, .limited(1024 * 1024)) catch |err| switch (err) {
        error.FileNotFound => return object(engine),
        else => return err,
    };
    defer engine.gpa.free(raw);
    return jsonObject(engine, raw);
}
fn initSettings(engine: *engine_mod.Engine, args: []const c.JSValue, persistent: bool) !c.JSValue {
    const data = try object(engine);
    defer engine.freeValue(data);
    var global = try object(engine);
    defer engine.freeValue(global);
    const project = try object(engine);
    defer engine.freeValue(project);
    if (persistent) {
        const working = if (args.len > 0 and c.JS_IsString(args[0])) try engine.toString(args[0]) else try cwd(engine);
        defer engine.gpa.free(working);
        const directory = if (args.len > 1 and c.JS_IsString(args[1])) try engine.toString(args[1]) else try agentDir(engine);
        defer engine.gpa.free(directory);
        const global_path = try std.fs.path.join(engine.gpa, &.{ directory, "settings.json" });
        defer engine.gpa.free(global_path);
        const project_path = try std.fs.path.join(engine.gpa, &.{ working, ".pi", "settings.json" });
        defer engine.gpa.free(project_path);
        try put(engine, data, "settingsPath", try text(engine, global_path));
        try put(engine, data, "projectPath", try text(engine, project_path));
    } else if (args.len > 0 and c.JS_IsObject(args[0])) {
        const loaded_global = try @import("native_sdk_settings.zig").clone(engine, args[0]);
        engine.freeValue(global);
        global = loaded_global;
    }
    try put(engine, data, "global", c.JS_DupValue(engine.context, global));
    try put(engine, data, "project", c.JS_DupValue(engine.context, project));
    try put(engine, data, "settings", try @import("native_sdk_settings.zig").deepMerge(engine, global, project, 0));
    try put(engine, data, "errors", try array(engine));
    try @import("native_sdk_settings_storage.zig").initialize(engine, data, c.pi_js_undefined(), if (persistent and args.len > 2) args[2] else if (!persistent and args.len > 1) args[1] else c.pi_js_undefined(), global);
    return new(engine, .settings_manager, data);
}
fn initSettingsFromStorage(engine: *engine_mod.Engine, args: []const c.JSValue) !c.JSValue {
    if (args.len == 0 or !c.JS_IsObject(args[0])) return error.NativeSDKMissingArgument;
    const data = try object(engine);
    defer engine.freeValue(data);
    try @import("native_sdk_settings_storage.zig").initialize(engine, data, args[0], if (args.len > 1) args[1] else c.pi_js_undefined(), c.pi_js_undefined());
    return new(engine, .settings_manager, data);
}
fn initResources(engine: *engine_mod.Engine, options: c.JSValue) !c.JSValue {
    const data = try object(engine);
    defer engine.freeValue(data);
    try put(engine, data, "options", if (c.JS_IsObject(options)) c.JS_DupValue(engine.context, options) else try object(engine));
    try put(engine, data, "extensions", try jsonObject(engine, "{\"extensions\":[],\"errors\":[],\"warnings\":[]}"));
    inline for (.{ "skills", "prompts", "themes" }) |name| {
        const value = try object(engine);
        defer engine.freeValue(value);
        try put(engine, value, name, try array(engine));
        try put(engine, value, "diagnostics", try array(engine));
        try put(engine, data, name, c.JS_DupValue(engine.context, value));
    }
    try put(engine, data, "agentsFiles", try jsonObject(engine, "{\"agentsFiles\":[]}"));
    try put(engine, data, "appendSystemPrompt", try array(engine));
    return new(engine, .resource_loader, data);
}
fn resourcesReload(self: *State) !c.JSValue {
    const engine = self.engine;
    try @import("native_sdk_resources.zig").reload(engine, self.data);
    try @import("native_sdk_resources.zig").factories(engine, self.data);
    const options = try get(engine, self.data, "options");
    defer engine.freeValue(options);
    inline for (.{ .{ "skills", "skillsOverride" }, .{ "prompts", "promptsOverride" }, .{ "themes", "themesOverride" }, .{ "agentsFiles", "agentsFilesOverride" } }) |names| {
        const function = try get(engine, options, names[1]);
        defer engine.freeValue(function);
        if (c.JS_IsFunction(engine.context, function)) {
            const current = try get(engine, self.data, names[0]);
            defer engine.freeValue(current);
            var args = [_]c.JSValue{current};
            const result = try engine.checked(c.JS_Call(engine.context, function, options, 1, &args));
            defer engine.freeValue(result);
            const settled = try engine.awaitValue(result);
            defer engine.freeValue(settled);
            try put(engine, self.data, names[0], try clone(engine, settled));
        }
    }
    const override = try get(engine, options, "systemPromptOverride");
    defer engine.freeValue(override);
    if (c.JS_IsFunction(engine.context, override)) {
        const base = try get(engine, self.data, "systemPrompt");
        defer engine.freeValue(base);
        var args = [_]c.JSValue{base};
        const result = try engine.checked(c.JS_Call(engine.context, override, options, 1, &args));
        defer engine.freeValue(result);
        try put(engine, self.data, "systemPrompt", c.JS_DupValue(engine.context, result));
    }
    return promise(engine, c.pi_js_undefined());
}

fn settingsDispatch(self: *State, operation: Method, args: []const c.JSValue) !c.JSValue {
    const engine = self.engine;
    if (operation == .flush) return @import("native_sdk_settings_storage.zig").flush(engine, self.data);
    if (operation == .reload) return @import("native_sdk_settings_storage.zig").reload(engine, self.data);
    const first = if (args.len > 0) args[0] else c.pi_js_undefined();
    if (operation == .getGlobalSettings or operation == .getProjectSettings) {
        const value = try get(engine, self.data, if (operation == .getGlobalSettings) "global" else "project");
        defer engine.freeValue(value);
        return clone(engine, value);
    }
    if (operation == .applyOverrides) {
        const old = try get(engine, self.data, "settings");
        defer engine.freeValue(old);
        try put(engine, self.data, "settings", try @import("native_sdk_settings.zig").deepMerge(engine, old, first, 0));
        return c.pi_js_undefined();
    }
    if (operation == .setDefaultThinkingLevel) {
        inline for (.{ "global", "settings" }) |name| {
            const target = try get(engine, self.data, name);
            defer engine.freeValue(target);
            try put(engine, target, "defaultThinkingLevel", c.JS_DupValue(engine.context, first));
        }
        return c.pi_js_undefined();
    }
    if (operation == .flush) {
        const path = try get(engine, self.data, "settingsPath");
        defer engine.freeValue(path);
        if (c.JS_IsString(path)) {
            const filename = try engine.toString(path);
            defer engine.gpa.free(filename);
            const data = try get(engine, self.data, "global");
            defer engine.freeValue(data);
            const raw = try engine.stringify(data);
            defer engine.gpa.free(raw);
            const io = engine.native_io orelse return error.NativeSDKRequiresIO;
            if (std.fs.path.dirname(filename)) |dir| try std.Io.Dir.cwd().createDirPath(io, dir);
            try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = filename, .data = raw });
        }
        return promise(engine, c.pi_js_undefined());
    }
    if (operation == .drainErrors) {
        const values = try get(engine, self.data, "errors");
        try put(engine, self.data, "errors", try array(engine));
        return values;
    }
    if (operation == .reload) {
        inline for (.{ .{ "settingsPath", "global" }, .{ "projectPath", "project" } }) |names| {
            const path = try get(engine, self.data, names[0]);
            defer engine.freeValue(path);
            if (c.JS_IsString(path)) {
                const filename = try engine.toString(path);
                defer engine.gpa.free(filename);
                try put(engine, self.data, names[1], try loadJsonFile(engine, filename));
            }
        }
        const global = try get(engine, self.data, "global");
        defer engine.freeValue(global);
        const project = try get(engine, self.data, "project");
        defer engine.freeValue(project);
        try put(engine, self.data, "settings", try @import("native_sdk_settings.zig").deepMerge(engine, global, project, 0));
        return promise(engine, c.pi_js_undefined());
    }
    const data = try get(engine, self.data, "settings");
    defer engine.freeValue(data);
    const key: ?[*:0]const u8 = switch (operation) {
        .getDefaultProvider => "defaultProvider",
        .getDefaultModel => "defaultModel",
        .getDefaultThinkingLevel => "defaultThinkingLevel",
        .getDefaultTools => "defaultTools",
        .getTransport => "transport",
        else => null,
    };
    if (key) |name| {
        const value = try get(engine, data, name);
        if (operation == .getTransport and c.JS_IsUndefined(value)) {
            engine.freeValue(value);
            return text(engine, "sse");
        }
        return value;
    }
    if (operation == .getCompactionSettings or operation == .getRetrySettings) {
        const defaults = try jsonObject(engine, if (operation == .getCompactionSettings) "{\"enabled\":true,\"reserveTokens\":16384,\"keepRecentTokens\":20000}" else "{\"enabled\":true,\"maxRetries\":3,\"baseDelayMs\":2000,\"maxAgentDelayMs\":60000}");
        defer engine.freeValue(defaults);
        const override = try get(engine, data, if (operation == .getCompactionSettings) "compaction" else "retry");
        defer engine.freeValue(override);
        if (c.JS_IsObject(override)) return merge(engine, defaults, override);
        return clone(engine, defaults);
    }
    return error.NativeSDKMethodUnavailable;
}

fn initModelRuntime(engine: *engine_mod.Engine, options: c.JSValue) !c.JSValue {
    const data = try object(engine);
    defer engine.freeValue(data);
    const exports = engine.native_module_values.get("pi-ai") orelse return error.NativeSDKModelModuleUnavailable;
    try put(engine, data, "keys", try object(engine));
    try put(engine, data, "available", try array(engine));
    try @import("native_sdk_auth_snapshot.zig").initialize(engine, data);
    try put(engine, data, "options", if (c.JS_IsObject(options)) c.JS_DupValue(engine.context, options) else try object(engine));
    const configured = try get(engine, data, "options");
    defer engine.freeValue(configured);
    const auth_path = try get(engine, configured, "authPath");
    defer engine.freeValue(auth_path);
    if (c.JS_IsString(auth_path)) {
        try put(engine, data, "authPath", c.JS_DupValue(engine.context, auth_path));
    } else {
        const directory = try agentDir(engine);
        defer engine.gpa.free(directory);
        const filename = try std.fs.path.join(engine.gpa, &.{ directory, "auth.json" });
        defer engine.gpa.free(filename);
        try put(engine, data, "authPath", try text(engine, filename));
    }
    const catalog_options = try object(engine);
    defer engine.freeValue(catalog_options);
    try @import("native_sdk_models.zig").copy(engine, catalog_options, configured);
    try put(engine, catalog_options, "credentials", try @import("native_sdk_models.zig").credentials(engine, data));
    const catalog = try invoke(engine, exports, "createModels", &.{catalog_options});
    defer engine.freeValue(catalog);
    try put(engine, data, "models", c.JS_DupValue(engine.context, catalog));
    try @import("native_sdk_models.zig").seedBuiltins(engine, catalog);
    try @import("native_sdk_provider_composer.zig").initialize(engine, data);
    return new(engine, .model_runtime, data);
}
fn providerModels(context: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue, _: c_int, data: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = engine_mod.Engine.fromContext(context.?);
    return normalizedModels(engine, data[0], data[1]) catch |err| fail(engine, err);
}
fn normalizedModels(engine: *engine_mod.Engine, models: c.JSValue, provider: c.JSValue) !c.JSValue {
    const result = try array(engine);
    errdefer engine.freeValue(result);
    for (0..try length(engine, models)) |i| {
        const source = try engine.checked(c.JS_GetPropertyUint32(engine.context, models, @intCast(i)));
        defer engine.freeValue(source);
        const value = try clone(engine, source);
        defer engine.freeValue(value);
        try put(engine, value, "provider", c.JS_DupValue(engine.context, provider));
        const typ = try get(engine, value, "type");
        defer engine.freeValue(typ);
        if (c.JS_IsUndefined(typ)) try put(engine, value, "type", try text(engine, "chat"));
        try append(engine, result, c.JS_DupValue(engine.context, value));
    }
    return result;
}

fn factory(engine: *engine_mod.Engine, options: c.JSValue) !c.JSValue {
    const opts = if (c.JS_IsObject(options)) c.JS_DupValue(engine.context, options) else try object(engine);
    defer engine.freeValue(opts);
    var manager = try get(engine, opts, "sessionManager");
    defer engine.freeValue(manager);
    const desired_cwd = try get(engine, opts, "cwd");
    defer engine.freeValue(desired_cwd);
    const desired_dir = try get(engine, opts, "agentDir");
    defer engine.freeValue(desired_dir);
    if (c.JS_IsUndefined(manager)) {
        engine.freeValue(manager);
        const work = if (c.JS_IsString(desired_cwd)) try engine.toString(desired_cwd) else try cwd(engine);
        defer engine.gpa.free(work);
        const root = if (c.JS_IsString(desired_dir)) try engine.toString(desired_dir) else try agentDir(engine);
        defer engine.gpa.free(root);
        const dir = try std.fs.path.join(engine.gpa, &.{ root, "sessions" });
        defer engine.gpa.free(dir);
        const work_value = try text(engine, work);
        defer engine.freeValue(work_value);
        const dir_value = try text(engine, dir);
        defer engine.freeValue(dir_value);
        manager = try initManager(engine, &.{ work_value, dir_value }, true);
    }
    _ = try state(engine, manager);
    var settings = try get(engine, opts, "settingsManager");
    defer engine.freeValue(settings);
    if (c.JS_IsUndefined(settings)) {
        engine.freeValue(settings);
        settings = try initSettings(engine, &.{ desired_cwd, desired_dir }, engine.native_io != null);
    }
    var runtime = try get(engine, opts, "modelRuntime");
    defer engine.freeValue(runtime);
    if (c.JS_IsUndefined(runtime)) {
        engine.freeValue(runtime);
        runtime = try initModelRuntime(engine, c.pi_js_undefined());
    }
    var resources = try get(engine, opts, "resourceLoader");
    defer engine.freeValue(resources);
    if (c.JS_IsUndefined(resources)) {
        engine.freeValue(resources);
        resources = try initResources(engine, opts);
        const ready = try invoke(engine, resources, "reload", &.{});
        defer engine.freeValue(ready);
        const settled = try engine.awaitValue(ready);
        engine.freeValue(settled);
    }
    const data = try object(engine);
    defer engine.freeValue(data);
    inline for (.{ .{ "sessionManager", manager }, .{ "settingsManager", settings }, .{ "modelRuntime", runtime }, .{ "resourceLoader", resources } }) |field| try put(engine, data, field[0], c.JS_DupValue(engine.context, field[1]));
    var model = try get(engine, opts, "model");
    defer engine.freeValue(model);
    if (!c.JS_IsObject(model)) {
        const provider = try invoke(engine, settings, "getDefaultProvider", &.{});
        defer engine.freeValue(provider);
        const id = try invoke(engine, settings, "getDefaultModel", &.{});
        defer engine.freeValue(id);
        if (c.JS_IsString(provider) and c.JS_IsString(id)) {
            const candidate = try invoke(engine, runtime, "getModel", &.{ provider, id });
            defer engine.freeValue(candidate);
            const configured = try invoke(engine, runtime, "hasConfiguredAuth", &.{provider});
            defer engine.freeValue(configured);
            if (c.JS_IsObject(candidate) and c.JS_ToBool(engine.context, configured) == 1) {
                engine.freeValue(model);
                model = c.JS_DupValue(engine.context, candidate);
            }
        }
        if (!c.JS_IsObject(model)) {
            const available = try invoke(engine, runtime, "getAvailable", &.{});
            defer engine.freeValue(available);
            const rows = try engine.awaitValue(available);
            defer engine.freeValue(rows);
            if (try length(engine, rows) > 0) {
                const candidate = try engine.checked(c.JS_GetPropertyUint32(engine.context, rows, 0));
                engine.freeValue(model);
                model = candidate;
            }
        }
    }
    try put(engine, data, "model", c.JS_DupValue(engine.context, model));
    const scoped = try get(engine, opts, "scopedModels");
    defer engine.freeValue(scoped);
    try put(engine, data, "scopedModels", if (c.JS_IsUndefined(scoped)) try array(engine) else c.JS_DupValue(engine.context, scoped));
    const chosen = try get(engine, opts, "thinkingLevel");
    defer engine.freeValue(chosen);
    const default_thinking = try invoke(engine, settings, "getDefaultThinkingLevel", &.{});
    defer engine.freeValue(default_thinking);
    const reasoning = if (c.JS_IsObject(model)) try get(engine, model, "reasoning") else c.pi_js_undefined();
    defer engine.freeValue(reasoning);
    try put(engine, data, "thinkingLevel", if (!c.JS_IsObject(model) or c.JS_ToBool(engine.context, reasoning) != 1) try text(engine, "off") else if (c.JS_IsString(chosen)) c.JS_DupValue(engine.context, chosen) else if (c.JS_IsString(default_thinking)) c.JS_DupValue(engine.context, default_thinking) else try text(engine, "medium"));
    const custom = try get(engine, opts, "customTools");
    defer engine.freeValue(custom);
    try put(engine, data, "customTools", if (c.JS_IsArray(custom)) c.JS_DupValue(engine.context, custom) else try array(engine));
    const factory_cwd = if (c.JS_IsString(desired_cwd)) try engine.toString(desired_cwd) else try cwd(engine);
    defer engine.gpa.free(factory_cwd);
    try put(engine, data, "_sdkToolCwd", try text(engine, factory_cwd));
    const image_auto_resize = try invoke(engine, settings, "getImageAutoResize", &.{});
    defer engine.freeValue(image_auto_resize);
    const shell_path_value = try invoke(engine, settings, "getShellPath", &.{});
    defer engine.freeValue(shell_path_value);
    const shell_path = if (c.JS_IsString(shell_path_value)) try engine.toString(shell_path_value) else null;
    defer if (shell_path) |value| engine.gpa.free(value);
    const prefix_value = try invoke(engine, settings, "getShellCommandPrefix", &.{});
    defer engine.freeValue(prefix_value);
    const prefix = if (c.JS_IsString(prefix_value)) try engine.toString(prefix_value) else null;
    defer if (prefix) |value| engine.gpa.free(value);
    try put(engine, data, "_sdkBuiltinDefinitions", try @import("native_sdk_builtin_execution.zig").createDefinitionsWithOptions(engine, factory_cwd, .{ .auto_resize = c.JS_ToBool(engine.context, image_auto_resize) != 0, .shell_path = shell_path, .command_prefix = prefix }));
    const tools = try get(engine, opts, "tools");
    defer engine.freeValue(tools);
    try put(engine, data, "activeTools", if (c.JS_IsArray(tools)) try clone(engine, tools) else try jsonObject(engine, "[\"read\",\"bash\",\"edit\",\"write\"]"));
    const system = try invoke(engine, resources, "getSystemPrompt", &.{});
    defer engine.freeValue(system);
    try put(engine, data, "systemPrompt", if (c.JS_IsString(system)) c.JS_DupValue(engine.context, system) else try text(engine, "You are a helpful coding assistant."));
    const context_value = try invoke(engine, manager, "buildSessionContext", &.{});
    defer engine.freeValue(context_value);
    try put(engine, data, "messages", try get(engine, context_value, "messages"));
    const agent = try object(engine);
    defer engine.freeValue(agent);
    const agent_state = try object(engine);
    defer engine.freeValue(agent_state);
    try put(engine, agent_state, "messages", try get(engine, data, "messages"));
    try put(engine, agent_state, "model", c.JS_DupValue(engine.context, model));
    try put(engine, agent_state, "thinkingLevel", try get(engine, data, "thinkingLevel"));
    try put(engine, agent_state, "tools", try get(engine, data, "customTools"));
    try put(engine, agent, "state", try @import("native_sdk_session_state.zig").view(engine, agent_state));
    try put(engine, data, "agent", c.JS_DupValue(engine.context, agent));
    const session = try new(engine, .agent_session, data);
    defer engine.freeValue(session);
    const session_owner = try state(engine, session);
    try put(engine, data, "_sdkSessionValue", c.JS_DupValue(engine.context, session));
    try put(engine, data, "modelRegistry", try newModelRegistry(engine, runtime));
    try attachSessionModelLease(session_owner);
    errdefer if (session_owner.model_lease_anchor) |anchor| @import("native_sdk_model_bridge.zig").invalidateAnchorRT(engine, engine.runtime, anchor);
    try @import("native_sdk_tool_catalog.zig").initialize(session_owner, opts);
    try @import("native_sdk_tool_catalog.zig").initializeActive(session_owner, opts);
    const result = try object(engine);
    errdefer engine.freeValue(result);
    try put(engine, result, "session", c.JS_DupValue(engine.context, session));
    try put(engine, result, "extensionsResult", try invoke(engine, resources, "getExtensions", &.{}));
    if (!c.JS_IsObject(model)) try put(engine, result, "modelFallbackMessage", try text(engine, "No models available."));
    const existing_messages = try get(engine, data, "messages");
    defer engine.freeValue(existing_messages);
    if (try length(engine, existing_messages) == 0 and c.JS_IsObject(model)) {
        const provider = try get(engine, model, "provider");
        defer engine.freeValue(provider);
        const id = try get(engine, model, "id");
        defer engine.freeValue(id);
        const model_record = try invoke(engine, manager, "appendModelChange", &.{ provider, id });
        engine.freeValue(model_record);
    }
    const thinking = try get(engine, data, "thinkingLevel");
    defer engine.freeValue(thinking);
    const recorded = try invoke(engine, manager, "appendThinkingLevelChange", &.{thinking});
    engine.freeValue(recorded);
    try @import("native_sdk_resource_owners.zig").bindSession(session_owner);
    return result;
}
fn modelDispatch(self: *State, operation: Method, args: []const c.JSValue) !c.JSValue {
    const engine = self.engine;
    const catalog = try get(engine, self.data, "models");
    defer engine.freeValue(catalog);
    if (operation == .registerNativeProvider) return invoke(engine, catalog, "setProvider", args);
    if (operation == .registerProvider) {
        if (args.len != 2 or !c.JS_IsString(args[0]) or !c.JS_IsObject(args[1])) return error.NativeSDKInvalidProviderConfig;
        const provider = try @import("native_sdk_provider_composer.zig").extensionProvider(engine, self.data, args[0], args[1]);
        defer engine.freeValue(provider);
        return invoke(engine, catalog, "setProvider", &.{provider});
    }
    if (operation == .unregisterProvider) return invoke(engine, catalog, "deleteProvider", args);
    const delegate: ?[*:0]const u8 = switch (operation) {
        .getProviders => "getProviders",
        .getModels => "getModels",
        .getAll, .getAllModels => "getAllModels",
        .getModel => "getModel",
        .getModelsOfType => "getModelsOfType",
        .getModelOfType => "getModelOfType",
        .getAllAvailable => "getAllAvailable",
        .getAvailableOfType => "getAvailableOfType",
        .checkAuth => "checkAuth",
        .getAvailable => "getAvailable",
        else => null,
    };
    if (delegate) |name| {
        const result = try invoke(engine, catalog, name, args);
        errdefer engine.freeValue(result);
        if (operation == .getAvailable) {
            const rows = try engine.awaitValue(result);
            defer engine.freeValue(rows);
            try put(engine, self.data, "available", c.JS_DupValue(engine.context, rows));
        }
        return result;
    }
    if (operation == .getAvailableSnapshot) return get(engine, self.data, "available");
    if (operation == .getAuth) {
        if (args.len == 0) return error.NativeSDKMissingArgument;
        const resolved = try @import("native_sdk_models.zig").resolveAuth(engine, self.data, args[0], if (args.len > 1) args[1] else c.pi_js_undefined());
        defer engine.freeValue(resolved);
        return promise(engine, resolved);
    }
    if (operation == .setRuntimeApiKey or operation == .clearRuntimeApiKey or operation == .removeRuntimeApiKey or operation == .hasConfiguredAuth) {
        if (args.len < 1) return error.NativeSDKMissingArgument;
        const keys = try get(engine, self.data, "keys");
        defer engine.freeValue(keys);
        const provider = try engine.toString(args[0]);
        defer engine.gpa.free(provider);
        const key = try engine.gpa.dupeZ(u8, provider);
        defer engine.gpa.free(key);
        if (operation == .hasConfiguredAuth) {
            const pending = try invoke(engine, catalog, "checkAuth", args);
            defer engine.freeValue(pending);
            const value = try engine.awaitValue(pending);
            defer engine.freeValue(value);
            return c.pi_js_bool(engine.context, @intFromBool(c.JS_IsObject(value)));
        }
        try put(engine, keys, key, if (operation == .setRuntimeApiKey and args.len > 1) c.JS_DupValue(engine.context, args[1]) else c.pi_js_undefined());
        return promise(engine, c.pi_js_undefined());
    }
    if (operation == .streamSimple or operation == .completeSimple or operation == .classify or operation == .generateImages) {
        if (args.len < 2) return error.NativeSDKMissingArgument;
        if (operation == .classify or operation == .generateImages) {
            return queueTypedOperation(engine, self.data, args[0], args[1], if (args.len > 2) args[2] else c.pi_js_undefined(), operation == .generateImages);
        }
        const result = try @import("native_sdk_models.zig").request(engine, self.data, args[0], args[1], if (args.len > 2) args[2] else c.pi_js_undefined(), if (operation == .classify) "classify" else if (operation == .generateImages) "generateImages" else "streamSimple");
        if (operation == .streamSimple) return result;
        defer engine.freeValue(result);
        if (operation == .completeSimple) return invoke(engine, result, "result", &.{});
        return promise(engine, result);
    }
    return error.NativeSDKMethodUnavailable;
}
fn openManager(engine: *engine_mod.Engine, args: []const c.JSValue) !c.JSValue {
    return @import("native_sdk_session_files.zig").open(engine, args);
}
fn queueTypedOperation(engine: *engine_mod.Engine, data: c.JSValue, model: c.JSValue, context: c.JSValue, options: c.JSValue, images: bool) !c.JSValue {
    var capabilities: [2]c.JSValue = undefined;
    const result = try engine.checked(c.JS_NewPromiseCapability(engine.context, &capabilities));
    errdefer engine.freeValue(result);
    defer for (capabilities) |callback| engine.freeValue(callback);
    var values = [_]c.JSValue{ data, model, context, options, c.pi_js_bool(engine.context, @intFromBool(images)), capabilities[0], capabilities[1] };
    if (c.JS_EnqueueJob(engine.context, typedOperationJob, values.len, &values) < 0) return error.OutOfMemory;
    return result;
}
fn typedOperationJob(context: ?*c.JSContext, _: c_int, args: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = engine_mod.Engine.fromContext(context.?);
    const value = @import("native_sdk_models.zig").typedOperation(engine, args[0], args[1], args[2], args[3], c.JS_ToBool(context, args[4]) == 1) catch |err| {
        _ = fail(engine, err);
        const reason = c.JS_GetException(context);
        defer engine.freeValue(reason);
        var rejected = [_]c.JSValue{reason};
        return c.JS_Call(context, args[6], c.pi_js_undefined(), 1, &rejected);
    };
    defer engine.freeValue(value);
    var values = [_]c.JSValue{value};
    return c.JS_Call(context, args[5], c.pi_js_undefined(), 1, &values);
}

fn dispatch(self: *State, receiver: c.JSValue, operation: Method, args: []const c.JSValue) !c.JSValue {
    const engine = self.engine;
    const retained_session_method = self.kind == .agent_session and switch (operation) {
        .getAllTools, .getToolDefinition, .getActiveToolNames, .setActiveToolsByName, .setSessionName, .setThinkingLevel, .getAvailableThinkingLevels, .cycleThinkingLevel, .supportsThinking, .setModel => true,
        else => false,
    };
    if (self.disposed and operation != .dispose and !retained_session_method) return error.NativeSDKDisposed;
    const first = if (args.len > 0) args[0] else c.pi_js_undefined();
    const second = if (args.len > 1) args[1] else c.pi_js_undefined();
    if (self.kind == .session_runtime) {
        if (operation == .setRebindSession or operation == .setBeforeSessionInvalidate) {
            try put(engine, self.data, if (operation == .setRebindSession) "rebind" else "invalidate", c.JS_DupValue(engine.context, first));
            return c.pi_js_undefined();
        }
        const previous = try get(engine, self.data, "session");
        defer engine.freeValue(previous);
        if (operation == .dispose) {
            try runtimeHook(self, "invalidate", &.{});
            try retireNativeSessionValue(engine, previous);
            const completed = try invoke(engine, previous, "dispose", &.{});
            engine.freeValue(completed);
            self.disposed = true;
            return promise(engine, c.pi_js_undefined());
        }
        if (operation == .newSession or operation == .switchSession) {
            const old_manager = try get(engine, previous, "sessionManager");
            defer engine.freeValue(old_manager);
            const working = try invoke(engine, old_manager, "getCwd", &.{});
            defer engine.freeValue(working);
            const directory = try invoke(engine, old_manager, "getSessionDir", &.{});
            defer engine.freeValue(directory);
            const persisted = try invoke(engine, old_manager, "isPersisted", &.{});
            defer engine.freeValue(persisted);
            const manager = if (operation == .switchSession) try openManager(engine, &.{first}) else try initManager(engine, &.{ working, directory }, c.JS_ToBool(engine.context, persisted) == 1);
            defer engine.freeValue(manager);
            const options = try object(engine);
            defer engine.freeValue(options);
            try put(engine, options, "cwd", c.JS_DupValue(engine.context, working));
            const services_value = try get(engine, self.data, "services");
            defer engine.freeValue(services_value);
            try put(engine, options, "agentDir", try get(engine, services_value, "agentDir"));
            try put(engine, options, "sessionManager", c.JS_DupValue(engine.context, manager));
            const start = try object(engine);
            defer engine.freeValue(start);
            try put(engine, start, "type", try text(engine, "session_start"));
            try put(engine, start, "reason", try text(engine, if (operation == .newSession) "new" else "resume"));
            try put(engine, options, "sessionStartEvent", c.JS_DupValue(engine.context, start));
            const creator = try get(engine, self.data, "factory");
            defer engine.freeValue(creator);
            const aborted = try invoke(engine, previous, "abort", &.{});
            defer engine.freeValue(aborted);
            const settled_abort = try engine.awaitValue(aborted);
            engine.freeValue(settled_abort);
            try runtimeHook(self, "invalidate", &.{});
            try retireNativeSessionValue(engine, previous);
            const detached = try invoke(engine, previous, "dispose", &.{});
            engine.freeValue(detached);
            var values = [_]c.JSValue{options};
            const pending = try engine.checked(c.JS_Call(engine.context, creator, c.pi_js_undefined(), 1, &values));
            defer engine.freeValue(pending);
            const created = try engine.awaitValue(pending);
            defer engine.freeValue(created);
            const next = try get(engine, created, "session");
            defer engine.freeValue(next);
            if (!c.JS_IsObject(next)) return error.InvalidNativeSDKRuntimeFactory;
            try put(engine, self.data, "session", c.JS_DupValue(engine.context, next));
            try put(engine, self.data, "services", try get(engine, created, "services"));
            try put(engine, self.data, "diagnostics", try get(engine, created, "diagnostics"));
            if (operation == .newSession and c.JS_IsObject(first)) {
                const setup = try get(engine, first, "setup");
                defer engine.freeValue(setup);
                if (c.JS_IsFunction(engine.context, setup)) {
                    var setup_args = [_]c.JSValue{manager};
                    const setup_pending = try engine.checked(c.JS_Call(engine.context, setup, first, 1, &setup_args));
                    defer engine.freeValue(setup_pending);
                    const setup_done = try engine.awaitValue(setup_pending);
                    engine.freeValue(setup_done);
                }
            }
            try runtimeHook(self, "rebind", &.{next});
            const result = try jsonObject(engine, "{\"cancelled\":false}");
            defer engine.freeValue(result);
            return promise(engine, result);
        }
        return error.NativeSDKMethodUnavailable;
    }
    if (self.kind == .agent_session) {
        if (operation == .prompt) return startPrompt(self, receiver, args);
        if (operation == .subscribe) {
            if (!c.JS_IsFunction(engine.context, first)) return error.InvalidNativeSDKListener;
            const listener = c.JS_DupValue(engine.context, first);
            errdefer engine.freeValue(listener);
            try self.listeners.append(engine.gpa, listener);
            var data = [_]c.JSValue{ receiver, first };
            return engine.checked(c.JS_NewCFunctionData2(engine.context, unsubscribeCallback, "unsubscribe", 0, 0, 2, &data));
        }
        if (operation == .dispose) {
            self.disposed = true;
            self.aborted = true;
            try retireSessionModelLease(self);
            for (self.listeners.items) |listener| engine.freeValue(listener);
            self.listeners.clearRetainingCapacity();
            return c.pi_js_undefined();
        }
        if (operation == .abort) {
            self.aborted = true;
            const signal = try get(engine, self.data, "promptSignal");
            defer engine.freeValue(signal);
            if (c.JS_IsObject(signal)) try @import("abort_signal.zig").abort(engine, signal, c.pi_js_undefined());
            if (self.running) {
                return get(engine, self.data, "promptIdle");
            }
            return promise(engine, c.pi_js_undefined());
        }
        if (operation == .bindExtensions) {
            const session = try sessionDataSessionValue(engine, self.data);
            defer engine.freeValue(session);
            try @import("native_sdk_ui_context.zig").bind(engine, session, first);
            const resources = try get(engine, self.data, "resourceLoader");
            defer engine.freeValue(resources);
            return @import("native_sdk_resources.zig").emitAsync(engine, resources, self.data, "session_start", "{\"reason\":\"startup\"}");
        }
        if (operation == .setScopedModels) {
            try put(engine, self.data, "scopedModels", c.JS_DupValue(engine.context, first));
            return c.pi_js_undefined();
        }
        if (operation == .waitForIdle) return if (self.running) get(engine, self.data, "promptIdle") else promise(engine, c.pi_js_undefined());
        if (operation == .getLastAssistantText) return @import("native_sdk_session_state.zig").lastAssistantText(self);
        if (operation == .getActiveToolNames) {
            return @import("native_sdk_tool_catalog.zig").activeNames(self);
        }
        if (operation == .setActiveToolsByName) {
            try @import("native_sdk_tool_catalog.zig").setActive(self, first);
            return c.pi_js_undefined();
        }
        if (operation == .getAllTools) {
            return @import("native_sdk_tool_catalog.zig").sessionRows(self);
        }
        if (operation == .getToolDefinition) return @import("native_sdk_tool_catalog.zig").getDefinition(self, first);
        if (operation == .setSessionName) {
            const manager = try get(engine, self.data, "sessionManager");
            defer engine.freeValue(manager);
            const value = try invoke(engine, manager, "appendSessionInfo", &.{first});
            engine.freeValue(value);
            const notification = try event(self, "session_info_changed");
            defer engine.freeValue(notification);
            try put(engine, notification, "name", try invoke(engine, manager, "getSessionName", &.{}));
            try emit(self, notification);
            const resources = try get(engine, self.data, "resourceLoader");
            defer engine.freeValue(resources);
            const pending = try @import("native_sdk_resources.zig").emitValue(engine, resources, self.data, "session_info_changed", notification);
            engine.freeValue(pending);
            return c.pi_js_undefined();
        }
        if (operation == .setThinkingLevel) {
            try @import("native_sdk_thinking.zig").set(engine, receiver, first, if (args.len > 1) args[1] else c.pi_js_undefined());
            return c.pi_js_undefined();
        }
        if (operation == .getAvailableThinkingLevels or operation == .supportsThinking) {
            const model = try agentField(self, "model");
            defer engine.freeValue(model);
            return if (operation == .getAvailableThinkingLevels) @import("native_sdk_thinking.zig").available(engine, model) else c.pi_js_bool(engine.context, @intFromBool(try @import("native_sdk_thinking.zig").supports(engine, model)));
        }
        if (operation == .cycleThinkingLevel) return @import("native_sdk_thinking.zig").cycle(engine, receiver, first);
        if (operation == .setModel) return @import("native_sdk_model_mutation.zig").set(engine, receiver, first, if (args.len > 1) args[1] else c.pi_js_undefined());
        if (operation == .clearQueue) return c.pi_js_undefined();
        if (operation == .steer or operation == .followUp) return error.NativeSDKQueueWhileRunningRequired;
        if (operation == .newSession) {
            if (self.running) return error.NativeSDKSessionBusy;
            const manager = try get(engine, self.data, "sessionManager");
            defer engine.freeValue(manager);
            const path = try invoke(engine, manager, "newSession", args);
            engine.freeValue(path);
            const empty_messages = try array(engine);
            defer engine.freeValue(empty_messages);
            try setAgentField(self, "messages", empty_messages);
            try retireSessionModelLease(self);
            try attachSessionModelLease(self);
            return promise(engine, c.pi_js_bool(engine.context, 1));
        }
        if (operation == .getSessionStats) {
            const value = try object(engine);
            errdefer engine.freeValue(value);
            try put(engine, value, "sessionId", try getterValue(self, .sessionId));
            try put(engine, value, "sessionFile", try getterValue(self, .sessionFile));
            const messages = try agentField(self, "messages");
            defer engine.freeValue(messages);
            try put(engine, value, "totalMessages", c.JS_NewInt32(engine.context, @intCast(try length(engine, messages))));
            return value;
        }
        return error.NativeSDKMethodUnavailable;
    }
    if (self.kind == .settings_manager) return settingsDispatch(self, operation, args);
    if (self.kind == .model_runtime) {
        if (operation == .getRegisteredProviderConfig) {
            const extensions = try get(engine, self.data, "registeredExtensions");
            defer engine.freeValue(extensions);
            return invoke(engine, extensions, "get", args);
        }
        if (operation == .setRuntimeApiKey or operation == .removeRuntimeApiKey or operation == .clearRuntimeApiKey) {
            if (args.len < 1 or (operation == .setRuntimeApiKey and args.len < 2)) return error.NativeSDKMissingArgument;
            const setting = operation == .setRuntimeApiKey;
            return @import("native_sdk_credential_sync.zig").enqueue(engine, receiver, args[0], if (setting) args[1] else c.pi_js_undefined(), if (args.len > @as(usize, if (setting) 2 else 1)) args[if (setting) 2 else 1] else c.pi_js_undefined(), !setting);
        }
        const auth_query: ?@import("native_sdk_auth_snapshot.zig").Query = switch (operation) {
            .hasConfiguredAuth => .configured,
            .getProviderAuthStatus => .status,
            .getError => .err,
            .isUsingOAuth => .oauth,
            .isUsingSubscription => .subscription,
            .getRegisteredProviderIds => .registered_ids,
            .getRegisteredNativeProvider => .registered_native,
            else => null,
        };
        if (auth_query) |query| return @import("native_sdk_auth_snapshot.zig").query(engine, self.data, query, if (args.len > 0) args[0] else c.pi_js_undefined());
        if (operation == .getProvider) {
            const catalog = try get(engine, self.data, "models");
            defer engine.freeValue(catalog);
            return invoke(engine, catalog, "getProvider", args);
        }
        if (operation == .registerVirtualModel and args.len > 0) return @import("native_sdk_virtual.zig").register(engine, receiver, args[0]);
        if (operation == .unregisterVirtualModel and args.len > 1) return @import("native_sdk_virtual.zig").unregister(engine, receiver, args[0], args[1]);
        if (operation == .resolveModel and args.len > 2) return @import("native_sdk_virtual.zig").resolve(engine, self.data, args[0], args[1], args[2]);
        if (operation == .getPhysicalModel and args.len > 1) return @import("native_sdk_virtual.zig").physical(engine, self.data, args[0], args[1]);
        if (operation == .listCredentials) return @import("native_sdk_models.zig").listCredentials(engine, self.data, if (args.len > 0) args[0] else c.pi_js_undefined());
        if (operation == .refresh) return @import("native_sdk_refresh.zig").start(engine, receiver, if (args.len > 0) args[0] else c.pi_js_undefined());
        if (operation == .cancelDeferred) return @import("native_sdk_chat.zig").cancel(engine, self.data, args);
        if (operation == .streamSimple or operation == .completeSimple or operation == .stream or operation == .complete or operation == .streamDeferred or operation == .fetchDeferred) {
            const output = try @import("native_sdk_chat.zig").streamMode(engine, receiver, self.data, args, if (operation == .stream or operation == .complete) .api else if (operation == .streamDeferred or operation == .fetchDeferred) .deferred else .simple);
            if (operation == .streamSimple or operation == .stream or operation == .streamDeferred) return output;
            defer engine.freeValue(output);
            return invoke(engine, output, "result", &.{});
        }
        if (operation == .getAvailable) return @import("native_sdk_availability.zig").getAvailable(engine, receiver, args);
        if (operation == .registerNativeProvider or operation == .registerProvider or operation == .unregisterProvider) {
            const result = try modelDispatch(self, operation, args);
            errdefer engine.freeValue(result);
            const id = if (operation == .registerNativeProvider) try get(engine, args[0], "id") else c.JS_DupValue(engine.context, args[0]);
            defer engine.freeValue(id);
            try @import("native_sdk_auth_snapshot.zig").registered(engine, self.data, id, if (operation == .registerNativeProvider) args[0] else if (args.len > 1) args[1] else c.pi_js_undefined(), operation == .registerNativeProvider, operation == .unregisterProvider);
            try @import("native_sdk_provider_composer.zig").recompose(engine, self.data, id);
            try @import("native_sdk_auth_snapshot.zig").updateModels(engine, self.data);
            if (operation != .unregisterProvider) {
                const catalog = try get(engine, self.data, "models");
                defer engine.freeValue(catalog);
                const provider = try invoke(engine, catalog, "getProvider", &.{id});
                defer engine.freeValue(provider);
                try @import("native_sdk_auth_snapshot.zig").markProvisional(engine, self.data, id, provider);
            }
            try @import("native_sdk_availability.zig").registrationRefresh(engine, receiver);
            return result;
        }
        return modelDispatch(self, operation, args);
    }
    if (self.kind == .resource_loader) {
        if (operation == .reload) return resourcesReload(self);
        const key: ?[*:0]const u8 = switch (operation) {
            .getExtensions => "extensions",
            .getSkills => "skills",
            .getPrompts => "prompts",
            .getThemes => "themes",
            .getAgentsFiles => "agentsFiles",
            .getSystemPrompt => "systemPrompt",
            .getAppendSystemPrompt => "appendSystemPrompt",
            else => null,
        };
        if (key) |name| return get(engine, self.data, name);
        if (operation == .getSystemPromptSource) return get(engine, self.data, "systemPromptSource");
        if (operation == .getAppendSystemPromptSources) return get(engine, self.data, "appendSystemPromptSources");
        if (operation == .extendResources) return error.NativeSDKResourcePathExtensionsNotYetSupported;
        return error.NativeSDKMethodUnavailable;
    }
    if (self.kind == .session_manager) {
        if (operation == .usesDefaultSessionDir) {
            const working = try get(engine, self.data, "cwd");
            defer engine.freeValue(working);
            const raw = try engine.toString(working);
            defer engine.gpa.free(raw);
            const encoded = try encodeCwd(engine, raw);
            defer engine.gpa.free(encoded);
            const root = try agentDir(engine);
            defer engine.gpa.free(root);
            const path = try std.fs.path.join(engine.gpa, &.{ root, "sessions", encoded });
            defer engine.gpa.free(path);
            const expected = try text(engine, path);
            defer engine.freeValue(expected);
            const actual = try get(engine, self.data, "sessionDir");
            defer engine.freeValue(actual);
            return c.pi_js_bool(engine.context, @intFromBool(c.JS_IsStrictEqual(engine.context, actual, expected)));
        }
        if (operation == .isPersisted) return get(engine, self.data, "persistent");
        if (operation == .getTree) return sessionTree(self);
        if (operation == .getLabel) return labelFor(self, first);
        if (operation == .getSessionName) {
            const rows = try get(engine, self.data, "entries");
            defer engine.freeValue(rows);
            var index = try length(engine, rows);
            while (index > 0) {
                index -= 1;
                const row = try engine.checked(c.JS_GetPropertyUint32(engine.context, rows, index));
                defer engine.freeValue(row);
                const typ = try get(engine, row, "type");
                defer engine.freeValue(typ);
                const value = try engine.toString(typ);
                defer engine.gpa.free(value);
                if (std.mem.eql(u8, value, "session_info")) {
                    const name = try get(engine, row, "name");
                    defer engine.freeValue(name);
                    if (c.JS_IsUndefined(name) or c.JS_IsNull(name)) return c.pi_js_undefined();
                    const trimmed = try invoke(engine, name, "trim", &.{});
                    if (c.JS_ToBool(engine.context, trimmed) == 1) return trimmed;
                    engine.freeValue(trimmed);
                    return c.pi_js_undefined();
                }
            }
            return c.pi_js_undefined();
        }
        const simple: ?[*:0]const u8 = switch (operation) {
            .getCwd => "cwd",
            .getSessionDir => "sessionDir",
            .getSessionFile => "sessionFile",
            .getHeader => "header",
            .getEntries => "entries",
            .getLeafId => "leafId",
            else => null,
        };
        if (simple) |name| {
            const value = try get(engine, self.data, name);
            if (operation != .getEntries) return value;
            defer engine.freeValue(value);
            return invoke(engine, value, "slice", &.{});
        }
        if (operation == .getSessionId) {
            const header = try get(engine, self.data, "header");
            defer engine.freeValue(header);
            return get(engine, header, "id");
        }
        if (operation == .getEntryCount) {
            const index = try get(engine, self.data, "entryIndex");
            defer engine.freeValue(index);
            return get(engine, index, "size");
        }
        if (operation == .getEntry or operation == .getLeafEntry) {
            const id = if (operation == .getEntry) c.JS_DupValue(engine.context, first) else try get(engine, self.data, "leafId");
            defer engine.freeValue(id);
            return findEntry(self, id);
        }
        if (operation == .getBranch) {
            const id = if (c.JS_IsString(first)) c.JS_DupValue(engine.context, first) else try get(engine, self.data, "leafId");
            defer engine.freeValue(id);
            return branchEntries(self, id);
        }
        if (operation == .newSession) {
            const working = try get(engine, self.data, "cwd");
            defer engine.freeValue(working);
            const directory = try get(engine, self.data, "sessionDir");
            defer engine.freeValue(directory);
            const persistent = try get(engine, self.data, "persistent");
            defer engine.freeValue(persistent);
            const created = if (c.JS_ToBool(engine.context, persistent) == 1) try initManager(engine, &.{ working, directory, first }, true) else try initManager(engine, &.{ working, first }, false);
            defer engine.freeValue(created);
            const fresh = try state(engine, created);
            engine.freeValue(self.data);
            self.data = c.JS_DupValue(engine.context, fresh.data);
            self.persisted_count = 0;
            self.session_flushed = false;
            return get(engine, self.data, "sessionFile");
        }
        if (operation == .setSessionFile) {
            const working = try get(engine, self.data, "cwd");
            defer engine.freeValue(working);
            const directory = try get(engine, self.data, "sessionDir");
            defer engine.freeValue(directory);
            const persistent = try get(engine, self.data, "persistent");
            defer engine.freeValue(persistent);
            const replacement = try @import("native_sdk_session_files.zig").openMode(engine, &.{ first, directory, working }, c.JS_ToBool(engine.context, persistent) == 1);
            defer engine.freeValue(replacement);
            const fresh = try state(engine, replacement);
            engine.freeValue(self.data);
            self.data = c.JS_DupValue(engine.context, fresh.data);
            try put(engine, self.data, "sessionDir", c.JS_DupValue(engine.context, directory));
            self.persisted_count = fresh.persisted_count;
            self.session_flushed = fresh.session_flushed;
            return c.pi_js_undefined();
        }
        if (operation == .branch or operation == .resetLeaf) {
            if (operation == .branch) {
                const found = try findEntry(self, first);
                defer engine.freeValue(found);
                if (c.JS_IsUndefined(found)) return missingEntry(self, first);
            }
            try put(engine, self.data, "leafId", if (operation == .branch) c.JS_DupValue(engine.context, first) else c.pi_js_null());
            return c.pi_js_undefined();
        }
        if (operation == .getChildren) {
            const rows = try get(engine, self.data, "entries");
            defer engine.freeValue(rows);
            const output = try array(engine);
            errdefer engine.freeValue(output);
            for (0..try length(engine, rows)) |i| {
                const row = try engine.checked(c.JS_GetPropertyUint32(engine.context, rows, @intCast(i)));
                defer engine.freeValue(row);
                const parent = try get(engine, row, "parentId");
                defer engine.freeValue(parent);
                if (c.JS_IsStrictEqual(engine.context, parent, first)) try append(engine, output, c.JS_DupValue(engine.context, row));
            }
            return output;
        }
        if (operation == .buildSessionContext or operation == .buildSessionProjection or operation == .buildContextEntries) {
            const leaf = try get(engine, self.data, "leafId");
            defer engine.freeValue(leaf);
            const path = try branchEntries(self, leaf);
            defer engine.freeValue(path);
            const projection = @import("native_sdk_session_projection.zig");
            if (operation == .buildContextEntries) return projection.contextEntries(engine, path);
            const result = try projection.project(engine, path);
            if (operation == .buildSessionProjection) return result;
            defer engine.freeValue(result);
            const context = try object(engine);
            errdefer engine.freeValue(context);
            inline for (.{ "messages", "thinkingLevel", "model" }) |field| try put(engine, context, field, try get(engine, result, field));
            return context;
        }
        const kind: ?[]const u8 = switch (operation) {
            .appendMessage => "message",
            .appendCustomEntry => "custom",
            .appendSessionInfo => "session_info",
            .appendModelChange => "model_change",
            .appendThinkingLevelChange => "thinking_level_change",
            .appendLabelChange => "label",
            else => null,
        };
        if (kind) |name| {
            const row = try entry(self, name);
            defer engine.freeValue(row);
            switch (operation) {
                .appendMessage => try put(engine, row, "message", c.JS_DupValue(engine.context, first)),
                .appendCustomEntry => {
                    try put(engine, row, "customType", c.JS_DupValue(engine.context, first));
                    try put(engine, row, "data", c.JS_DupValue(engine.context, second));
                },
                .appendSessionInfo => {
                    const raw = try engine.toString(first);
                    defer engine.gpa.free(raw);
                    var cleaned: std.Io.Writer.Allocating = .init(engine.gpa);
                    defer cleaned.deinit();
                    var newline = false;
                    for (raw) |byte| {
                        if (byte == '\r' or byte == '\n') {
                            if (!newline) try cleaned.writer.writeByte(' ');
                            newline = true;
                        } else {
                            try cleaned.writer.writeByte(byte);
                            newline = false;
                        }
                    }
                    const value = try text(engine, cleaned.written());
                    defer engine.freeValue(value);
                    try put(engine, row, "name", try invoke(engine, value, "trim", &.{}));
                },
                .appendModelChange => {
                    try put(engine, row, "provider", c.JS_DupValue(engine.context, first));
                    try put(engine, row, "modelId", c.JS_DupValue(engine.context, second));
                },
                .appendThinkingLevelChange => try put(engine, row, "thinkingLevel", c.JS_DupValue(engine.context, first)),
                .appendLabelChange => {
                    const found = try findEntry(self, first);
                    defer engine.freeValue(found);
                    if (c.JS_IsUndefined(found)) return missingEntry(self, first);
                    try put(engine, row, "targetId", c.JS_DupValue(engine.context, first));
                    try put(engine, row, "label", c.JS_DupValue(engine.context, second));
                },
                else => unreachable,
            }
            return commitEntry(self, row);
        }
    }
    return error.NativeSDKMethodUnavailable;
}
fn runtimeHook(self: *State, name: [*:0]const u8, args: []const c.JSValue) !void {
    const engine = self.engine;
    const callback = try get(engine, self.data, name);
    defer engine.freeValue(callback);
    if (!c.JS_IsFunction(engine.context, callback)) return;
    const pending = try engine.checked(c.JS_Call(engine.context, callback, c.pi_js_undefined(), @intCast(args.len), @constCast(args.ptr)));
    defer engine.freeValue(pending);
    const settled = try engine.awaitValue(pending);
    engine.freeValue(settled);
}

fn constructor(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, magic: c_int) callconv(.c) c.JSValue {
    const engine = engine_mod.Engine.fromContext(context.?);
    const kind: Kind = @enumFromInt(magic);
    const args = if (argc > 0) argv[0..@intCast(argc)] else &.{};
    return (switch (kind) {
        .session_manager => initManager(engine, args, false),
        .settings_manager => initSettings(engine, args, false),
        .resource_loader => initResources(engine, if (args.len > 0) args[0] else c.pi_js_undefined()),
        .model_runtime => initModelRuntime(engine, if (args.len > 0) args[0] else c.pi_js_undefined()),
        .model_registry => newModelRegistry(engine, if (args.len > 0) args[0] else c.pi_js_undefined()),
        .agent_session, .session_runtime => error.NativeSDKUseSessionFactory,
    }) catch |err| fail(engine, err);
}
fn constructorData(context: ?*c.JSContext, receiver: c.JSValue, argc: c_int, argv: [*c]c.JSValue, magic: c_int, _: [*c]c.JSValue) callconv(.c) c.JSValue {
    return constructor(context, receiver, argc, argv, magic);
}
fn createSession(context: ?*c.JSContext, _: c.JSValue, argc: c_int, args: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = engine_mod.Engine.fromContext(context.?);
    const result = factory(engine, if (argc > 0) args[0] else c.pi_js_undefined()) catch |err| return fail(engine, err);
    defer engine.freeValue(result);
    return promise(engine, result) catch |err| fail(engine, err);
}
fn services(engine: *engine_mod.Engine, options: c.JSValue) !c.JSValue {
    if (!c.JS_IsObject(options)) return error.NativeSDKMissingOptions;
    const work = try get(engine, options, "cwd");
    defer engine.freeValue(work);
    if (!c.JS_IsString(work)) return error.NativeSDKMissingCwd;
    var directory = try get(engine, options, "agentDir");
    defer engine.freeValue(directory);
    if (!c.JS_IsString(directory)) {
        engine.freeValue(directory);
        const path = try agentDir(engine);
        defer engine.gpa.free(path);
        directory = try text(engine, path);
    }
    var runtime = try get(engine, options, "modelRuntime");
    defer engine.freeValue(runtime);
    if (c.JS_IsUndefined(runtime)) {
        engine.freeValue(runtime);
        runtime = try initModelRuntime(engine, c.pi_js_undefined());
    }
    var settings = try get(engine, options, "settingsManager");
    defer engine.freeValue(settings);
    if (c.JS_IsUndefined(settings)) {
        engine.freeValue(settings);
        settings = try initSettings(engine, &.{ work, directory }, engine.native_io != null);
    }
    const supplied = try get(engine, options, "resourceLoaderOptions");
    defer engine.freeValue(supplied);
    const configured = if (c.JS_IsObject(supplied)) c.JS_DupValue(engine.context, supplied) else try object(engine);
    defer engine.freeValue(configured);
    try put(engine, configured, "cwd", c.JS_DupValue(engine.context, work));
    try put(engine, configured, "agentDir", c.JS_DupValue(engine.context, directory));
    const loader = try initResources(engine, configured);
    defer engine.freeValue(loader);
    const loaded = try invoke(engine, loader, "reload", &.{});
    defer engine.freeValue(loaded);
    const done = try engine.awaitValue(loaded);
    engine.freeValue(done);
    const result = try object(engine);
    errdefer engine.freeValue(result);
    try put(engine, result, "cwd", c.JS_DupValue(engine.context, work));
    try put(engine, result, "agentDir", c.JS_DupValue(engine.context, directory));
    try put(engine, result, "modelRuntime", c.JS_DupValue(engine.context, runtime));
    try put(engine, result, "settingsManager", c.JS_DupValue(engine.context, settings));
    try put(engine, result, "resourceLoader", c.JS_DupValue(engine.context, loader));
    try put(engine, result, "diagnostics", try array(engine));
    return result;
}
fn serviceCallback(context: ?*c.JSContext, _: c.JSValue, argc: c_int, args: [*c]c.JSValue, magic: c_int) callconv(.c) c.JSValue {
    const engine = engine_mod.Engine.fromContext(context.?);
    if (argc == 0) return fail(engine, error.NativeSDKMissingOptions);
    const result = (if (magic == 0) services(engine, args[0]) else fromServices(engine, args[0])) catch |err| return fail(engine, err);
    defer engine.freeValue(result);
    return promise(engine, result) catch |err| fail(engine, err);
}
fn fromServices(engine: *engine_mod.Engine, options: c.JSValue) !c.JSValue {
    const group = try get(engine, options, "services");
    defer engine.freeValue(group);
    if (!c.JS_IsObject(group)) return error.NativeSDKMissingServices;
    const merged = try object(engine);
    defer engine.freeValue(merged);
    inline for (.{ "cwd", "agentDir", "modelRuntime", "settingsManager", "resourceLoader" }) |field| try put(engine, merged, field, try get(engine, group, field));
    inline for (.{ "sessionManager", "model", "thinkingLevel", "tools", "excludeTools", "customTools", "sessionStartEvent", "noTools" }) |field| try put(engine, merged, field, try get(engine, options, field));
    return factory(engine, merged);
}
fn createRuntime(context: ?*c.JSContext, _: c.JSValue, argc: c_int, args: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = engine_mod.Engine.fromContext(context.?);
    return runtimeFactory(engine, if (argc > 0) args[0] else c.pi_js_undefined(), if (argc > 1) args[1] else c.pi_js_undefined()) catch |err| fail(engine, err);
}
fn runtimeFactory(engine: *engine_mod.Engine, creator: c.JSValue, options: c.JSValue) !c.JSValue {
    if (!c.JS_IsFunction(engine.context, creator)) return error.InvalidNativeSDKRuntimeFactory;
    var args = [_]c.JSValue{options};
    const pending = try engine.checked(c.JS_Call(engine.context, creator, c.pi_js_undefined(), 1, &args));
    defer engine.freeValue(pending);
    const created = try engine.awaitValue(pending);
    defer engine.freeValue(created);
    const data = try object(engine);
    defer engine.freeValue(data);
    try put(engine, data, "session", try get(engine, created, "session"));
    try put(engine, data, "services", try get(engine, created, "services"));
    try put(engine, data, "diagnostics", try get(engine, created, "diagnostics"));
    try put(engine, data, "factory", c.JS_DupValue(engine.context, creator));
    const result = try new(engine, .session_runtime, data);
    defer engine.freeValue(result);
    return promise(engine, result);
}
fn getAgentDirectory(context: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = engine_mod.Engine.fromContext(context.?);
    const path = agentDir(engine) catch |err| return fail(engine, err);
    defer engine.gpa.free(path);
    return text(engine, path) catch |err| fail(engine, err);
}
fn staticMethod(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, magic: c_int) callconv(.c) c.JSValue {
    const engine = engine_mod.Engine.fromContext(context.?);
    const args = if (argc > 0) argv[0..@intCast(argc)] else &.{};
    const result = (switch (magic) {
        0 => initManager(engine, args, false),
        1 => initManager(engine, args, true),
        2 => openManager(engine, args),
        100 => initSettings(engine, args, false),
        101 => initSettings(engine, args, true),
        102 => initSettingsFromStorage(engine, args),
        300 => initModelRuntime(engine, if (args.len > 0) args[0] else c.pi_js_undefined()),
        else => error.NativeSDKMethodUnavailable,
    }) catch |err| return fail(engine, err);
    if (magic == 300) {
        defer engine.freeValue(result);
        return @import("native_sdk_refresh.zig").created(engine, result, if (args.len > 0) args[0] else c.pi_js_undefined()) catch |err| fail(engine, err);
    }
    return result;
}
pub fn install(engine: *engine_mod.Engine, exports: c.JSValue) !void {
    try @import("native_async_scope.zig").install(engine);
    if (engine.native_sdk_class != 0) return;
    _ = c.JS_NewClassID(engine.runtime, &engine.native_sdk_class);
    const definition: c.JSClassDef = .{ .class_name = "Native coding SDK object", .finalizer = finalizer, .gc_mark = mark, .call = null, .exotic = null };
    if (c.JS_NewClass(engine.runtime, engine.native_sdk_class, &definition) < 0) return error.OutOfMemory;
    try @import("native_sdk_credential_sync.zig").install(engine, exports);
    try @import("native_sdk_session_projection.zig").install(engine, exports);
    try @import("native_sdk_builtin_execution.zig").installFindFactories(engine, exports);
    try put(engine, exports, "VIRTUAL_MODEL_STATE_ENTRY", try text(engine, "pi.virtual-model-state"));
    try put(engine, exports, "createAgentSession", try engine.checked(c.JS_NewCFunction(engine.context, createSession, "createAgentSession", 1)));
    try put(engine, exports, "createAgentSessionServices", try engine.checked(c.pi_js_function_magic(engine.context, serviceCallback, "createAgentSessionServices", 1, 0)));
    try put(engine, exports, "createAgentSessionFromServices", try engine.checked(c.pi_js_function_magic(engine.context, serviceCallback, "createAgentSessionFromServices", 1, 1)));
    try put(engine, exports, "createAgentSessionRuntime", try engine.checked(c.JS_NewCFunction(engine.context, createRuntime, "createAgentSessionRuntime", 2)));
    try put(engine, exports, "getAgentDir", try engine.checked(c.JS_NewCFunction(engine.context, getAgentDirectory, "getAgentDir", 0)));
    inline for (.{ .{ Kind.session_manager, "SessionManager" }, .{ Kind.settings_manager, "SettingsManager" }, .{ Kind.resource_loader, "DefaultResourceLoader" }, .{ Kind.model_runtime, "ModelRuntime" }, .{ Kind.agent_session, "AgentSession" }, .{ Kind.session_runtime, "AgentSessionRuntime" }, .{ Kind.model_registry, "ModelRegistry" } }) |item| {
        const proto = try object(engine);
        defer engine.freeValue(proto);
        if (item[0] == .settings_manager) {
            inline for (.{ Method.applyOverrides, Method.reload, Method.flush, Method.drainErrors }) |operation| {
                const name = @tagName(operation);
                const function = try engine.checked(c.pi_js_function_magic(engine.context, method, name, if (operation == .applyOverrides) 1 else 0, @intFromEnum(operation)));
                if (c.JS_DefinePropertyValueStr(engine.context, proto, name, function, c.JS_PROP_WRITABLE | c.JS_PROP_CONFIGURABLE) < 0) return error.JavaScriptException;
            }
            try @import("native_sdk_settings.zig").install(engine, proto);
        }
        engine.native_sdk_prototypes[@as(usize, @intCast(@intFromEnum(item[0])))] = c.JS_DupValue(engine.context, proto);
        const ctor = try engine.checked(c.JS_NewCFunctionData2(engine.context, constructorData, item[1], 1, @intFromEnum(item[0]), 0, null));
        defer engine.freeValue(ctor);
        _ = c.JS_SetConstructorBit(engine.context, ctor, true);
        if (c.JS_SetConstructor(engine.context, ctor, proto) < 0) return error.JavaScriptException;
        if (item[0] == .session_manager) {
            const operations: []const Method = &.{ .getCwd, .getSessionDir, .usesDefaultSessionDir, .getSessionId, .getSessionName, .getSessionFile, .getHeader, .getEntries, .getEntryCount, .getLeafId, .getLeafEntry, .getEntry, .getChildren, .getBranch, .getLabel, .getTree, .appendMessage, .appendCustomEntry, .appendSessionInfo, .appendModelChange, .appendThinkingLevelChange, .appendLabelChange, .branch, .resetLeaf, .buildSessionContext, .buildContextEntries, .buildSessionProjection, .newSession, .setSessionFile, .isPersisted };
            for (operations) |operation| {
                const name = try engine.gpa.dupeZ(u8, @tagName(operation));
                defer engine.gpa.free(name);
                const arity: c_int = switch (operation) {
                    .appendModelChange, .appendCustomEntry, .appendLabelChange => 2,
                    .getEntry, .getChildren, .getBranch, .getLabel, .appendMessage, .appendSessionInfo, .appendThinkingLevelChange, .branch, .newSession, .setSessionFile => 1,
                    else => 0,
                };
                const function = try engine.checked(c.pi_js_function_magic(engine.context, method, name, arity, @intFromEnum(operation)));
                if (c.JS_DefinePropertyValueStr(engine.context, proto, name, function, c.JS_PROP_WRITABLE | c.JS_PROP_CONFIGURABLE) < 0) return error.JavaScriptException;
            }
            try @import("native_sdk_session_mutations.zig").install(engine, proto);
            try @import("native_sdk_session_branch.zig").install(engine, proto);
        }
        if (item[0] == .model_registry) try @import("native_sdk_model_registry.zig").install(engine, proto);
        if (item[0] == .session_manager) inline for (.{ .{ "inMemory", 0 }, .{ "create", 1 }, .{ "open", 2 } }) |operation| try put(engine, ctor, operation[0], try engine.checked(c.pi_js_function_magic(engine.context, staticMethod, operation[0], 1, operation[1])));
        if (item[0] == .session_manager) try @import("native_sdk_session_discovery.zig").install(engine, ctor);
        if (item[0] == .settings_manager) inline for (.{ .{ "inMemory", 100 }, .{ "create", 101 }, .{ "fromStorage", 102 } }) |operation| try put(engine, ctor, operation[0], try engine.checked(c.pi_js_function_magic(engine.context, staticMethod, operation[0], 1, operation[1])));
        if (item[0] == .model_runtime) try put(engine, ctor, "create", try engine.checked(c.pi_js_function_magic(engine.context, staticMethod, "create", 1, 300)));
        try put(engine, exports, item[1], c.JS_DupValue(engine.context, ctor));
    }
}

test "native SDK SessionManager and SettingsManager own live tree and merged settings" {
    const engine = try engine_mod.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    try @import("native_stream.zig").install(engine);
    const exports = try object(engine);
    defer engine.freeValue(exports);
    try install(engine, exports);
    try engine.registerValueModule("sdk-test", exports);
    const module = try engine.evalModule("import {SessionManager,SettingsManager} from 'sdk-test';const m=SessionManager.inMemory('/sdk');if(!(m instanceof SessionManager)||m.getCwd()!=='/sdk'||m.getSessionFile()!==undefined||m.getLeafId()!==null)throw Error('manager identity');const a=m.appendCustomEntry('a',{value:1});const b=m.appendMessage({role:'user',content:'hello',timestamp:1});m.branch(a);const c=m.appendCustomEntry('c',{});if(m.getEntryCount()!==3||m.getBranch().map(e=>e.id).join()!==[a,c].join()||m.getChildren(a).length!==2)throw Error('tree');const settings=SettingsManager.inMemory({compaction:{enabled:false},retry:{enabled:true,maxRetries:5}});settings.applyOverrides({retry:{baseDelayMs:10}});if(settings.getCompactionSettings().enabled||settings.getRetrySettings().maxRetries!==5||settings.getRetrySettings().baseDelayMs!==10)throw Error('settings');settings.setDefaultThinkingLevel('low');await settings.flush();if(settings.getDefaultThinkingLevel()!=='low'||settings.drainErrors().length)throw Error('settings lifecycle');export const proof=true;", "sdk-tree.mjs");
    defer engine.freeValue(module);
    const settled = try engine.awaitValue(module);
    defer engine.freeValue(settled);
}

test "native SDK factory models and real provider prompt execute independently of outer extension context" {
    const engine = try engine_mod.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    try @import("native_stream.zig").install(engine);
    const exports = try object(engine);
    defer engine.freeValue(exports);
    try install(engine, exports);
    try engine.registerValueModule("sdk-test", exports);
    const module = try engine.evalModule("import {createAgentSession,AgentSession,SessionManager,SettingsManager,DefaultResourceLoader,ModelRuntime} from 'sdk-test';import {createAssistantMessageEventStream} from 'pi-ai';const runtime=await ModelRuntime.create({refreshOnCreate:false});const model={id:'m',provider:'sdk-test',api:'sdk-test',type:'chat',reasoning:false,input:['text'],cost:{input:0,output:0,cacheRead:0,cacheWrite:0},contextWindow:8192,maxTokens:512};runtime.registerNativeProvider({id:'sdk-test',auth:{apiKey:{resolve:async()=>({auth:{apiKey:'fixture-key'},source:'fixture'})}},getModels(){return [model]},getAllModels(){return [model]},streamSimple(model,context){const stream=createAssistantMessageEventStream();const message={role:'assistant',content:[{type:'text',text:'sdk-response'}],api:model.api,provider:model.provider,model:model.id,usage:{input:1,output:2,cacheRead:0,cacheWrite:0,totalTokens:3,cost:{input:0,output:0,cacheRead:0,cacheWrite:0,total:0}},stopReason:'stop',timestamp:2};queueMicrotask(()=>{stream.push({type:'start',partial:message});stream.push({type:'text_delta',contentIndex:0,delta:'sdk-response',partial:message});stream.push({type:'done',reason:'stop',message});stream.end()});return stream}});const loader=new DefaultResourceLoader({systemPromptOverride:()=> 'SDK prompt',skillsOverride:()=>({skills:[],diagnostics:[]})});await loader.reload();const manager=SessionManager.inMemory('/sdk');const {session}=await createAgentSession({model,modelRuntime:runtime,sessionManager:manager,settingsManager:SettingsManager.inMemory(),resourceLoader:loader,tools:[]});if(!(session instanceof AgentSession)||session.sessionId!==manager.getSessionId()||session.systemPrompt!=='SDK prompt')throw Error('factory');const events=[];const off=session.subscribe(e=>events.push(e.type));const work=session.prompt('hello');if(!(work instanceof Promise))throw Error('prompt promise');await work;if(session.messages.length!==3||session.messages[2].content[0].text!=='sdk-response'||!events.includes('message_update')||!events.includes('agent_settled'))throw Error('prompt lifecycle');off();session.dispose();export const proof=true;", "sdk-prompt.mjs");
    defer engine.freeValue(module);
    const settled = try engine.awaitValue(module);
    defer engine.freeValue(settled);
}

test "native SDK lifecycle preserves thrown callbacks and rejects disposed sessions" {
    const engine = try engine_mod.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    try @import("native_stream.zig").install(engine);
    const exports = try object(engine);
    defer engine.freeValue(exports);
    try install(engine, exports);
    try engine.registerValueModule("sdk-life", exports);
    const module = engine.evalModule(
        "import {createAgentSession,createAgentSessionServices,createAgentSessionFromServices,createAgentSessionRuntime,SessionManager,SettingsManager,DefaultResourceLoader,ModelRuntime} from 'sdk-life';" ++
            "const marker={};const loader=new DefaultResourceLoader({skillsOverride(){throw marker}});try{await loader.reload();throw Error('accepted')}catch(e){if(e!==marker)throw e;}" ++
            "const options={cwd:'/sdk',agentDir:'/agent',modelRuntime:await ModelRuntime.create(),settingsManager:SettingsManager.inMemory(),resourceLoaderOptions:{noExtensions:true}};const services=await createAgentSessionServices(options);const factory=async target=>({...await createAgentSessionFromServices({services,sessionManager:target.sessionManager,tools:[]}),services,diagnostics:[]});" ++
            "const owner=await createAgentSessionRuntime(factory,{...options,sessionManager:SessionManager.inMemory('/sdk')});const previous=owner.session;owner.setBeforeSessionInvalidate(()=>{throw marker});try{await owner.newSession();throw Error('accepted')}catch(e){if(e!==marker)throw e;}if(owner.session!==previous)throw Error('replacement before teardown');" ++
            "owner.setBeforeSessionInvalidate(undefined);await owner.newSession();if(owner.session===previous)throw Error('no replacement');let disposed=false;try{await previous.prompt('stale')}catch{disposed=true;}if(!disposed)throw Error('stale session');await owner.dispose();export const proof=true;",
        "sdk-life.mjs",
    ) catch |err| {
        if (engine.last_error) |message| std.debug.print("SDK lifecycle: {s}\n", .{message});
        return err;
    };
    defer engine.freeValue(module);
}

test "native SDK manager settings factories and runtime release every failed host allocation" {
    const Probe = struct {
        fn exercise(gpa: std.mem.Allocator) !void {
            const engine = try engine_mod.Engine.init(gpa, .{});
            defer engine.deinit();
            try @import("native_stream.zig").install(engine);
            const exports = try object(engine);
            defer engine.freeValue(exports);
            try install(engine, exports);
            try engine.registerValueModule("sdk-allocations", exports);
            const module = engine.evalModule(
                "import {SessionManager,SettingsManager,createAgentSession,createAgentSessionRuntime} from 'sdk-allocations';" ++
                    "const manager=SessionManager.inMemory('/sdk');const a=manager.appendCustomEntry('a',{value:1});manager.appendMessage({role:'user',content:'hello'});manager.branch(a);manager.appendLabelChange(a,'label');manager.getTree();const settings=SettingsManager.inMemory({retry:{maxRetries:5}});settings.applyOverrides({retry:{baseDelayMs:10}});" ++
                    "const creator=async target=>({...await createAgentSession({sessionManager:target.sessionManager,settingsManager:settings,tools:[]}),services:{cwd:'/sdk',agentDir:'/agent'},diagnostics:[]});const owner=await createAgentSessionRuntime(creator,{sessionManager:manager});owner.setRebindSession(()=>{});await owner.newSession();await owner.dispose();export const result=true;",
                "sdk-allocations.mjs",
            ) catch |err| {
                const failing: *std.testing.FailingAllocator = @ptrCast(@alignCast(gpa.ptr));
                if (!failing.has_induced_failure) if (engine.last_error) |message| std.debug.print("SDK allocation baseline: {s}\n", .{message});
                return err;
            };
            defer engine.freeValue(module);
            c.JS_RunGC(engine.runtime);
        }
        fn run(gpa: std.mem.Allocator) !void {
            exercise(gpa) catch |err| {
                const failing: *std.testing.FailingAllocator = @ptrCast(@alignCast(gpa.ptr));
                if (failing.has_induced_failure and (err == error.JavaScriptException or err == error.OutOfMemory)) return error.OutOfMemory;
                return err;
            };
        }
    };
    try std.testing.checkAllAllocationFailures(std.testing.allocator, Probe.run, .{});
}

test "native SDK typed queued requests auth transforms and errors release every failed host allocation" {
    const Probe = struct {
        fn exercise(gpa: std.mem.Allocator) !void {
            const engine = try engine_mod.Engine.init(gpa, .{});
            defer engine.deinit();
            try @import("native_stream.zig").install(engine);
            const exports = try object(engine);
            defer engine.freeValue(exports);
            try install(engine, exports);
            try engine.registerValueModule("sdk-model-allocations", exports);
            const module = try engine.evalModule(
                "import {ModelRuntime} from 'sdk-model-allocations';const r=await ModelRuntime.create({modelsPath:null,refreshOnCreate:false});const model={id:'c',provider:'p',api:'custom-classify',type:'classifier',input:['text'],headers:{model:'header'}};" ++
                    "r.registerNativeProvider({id:'p',auth:{apiKey:{async check({credential}){return credential?{type:'api_key'}:undefined},async resolve({credential}){return {auth:{apiKey:credential.key,headers:{auth:'header'}},source:'fixture'}}}},getModels(){return []},getAllModels(){return [model]},async classify(m,ctx,options){if(ctx.fail)throw new RangeError('typed failed');return {api:m.api,provider:m.provider,model:m.id,answers:{},stopReason:'stop',timestamp:1}}});await r.setRuntimeApiKey('p','key');const work=r.classify(model,{state:{},questions:{}},{transformHeaders:async headers=>({...headers,request:'header'})});if(!(work instanceof Promise))throw Error('not queued');const answer=await work;if(answer.stopReason!=='stop')throw Error('request');" ++
                    "const failed=await r.classify(model,{fail:true,state:{},questions:{}});if(failed.errorMessage!=='typed failed')throw Error('error result');const controller=new AbortController;controller.abort('reason');const cancelled=await r.classify(model,{state:{},questions:{}},{signal:controller.signal});if(cancelled.stopReason!=='aborted'||cancelled.errorMessage!=='reason')throw Error('abort result');await r.removeRuntimeApiKey('p');export const proof=true;",
                "sdk-model-allocations.mjs",
            );
            defer engine.freeValue(module);
            c.JS_RunGC(engine.runtime);
        }
        fn run(gpa: std.mem.Allocator) !void {
            exercise(gpa) catch |err| {
                const failing: *std.testing.FailingAllocator = @ptrCast(@alignCast(gpa.ptr));
                if (failing.has_induced_failure and (err == error.JavaScriptException or err == error.OutOfMemory)) return error.OutOfMemory;
                return err;
            };
        }
    };
    try std.testing.checkAllAllocationFailures(std.testing.allocator, Probe.run, .{});
}
