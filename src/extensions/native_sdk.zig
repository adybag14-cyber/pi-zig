//! Programmatic coding-agent SDK objects, implemented through the C ABI.
const std = @import("std");
const engine_mod = @import("engine.zig");
const c = engine_mod.c;
const Kind = enum(c_int) { session_manager, settings_manager, resource_loader, model_runtime, agent_session, session_runtime };
const State = struct {
    engine: *engine_mod.Engine,
    kind: Kind,
    data: c.JSValue,
    listeners: std.ArrayList(c.JSValue) = .empty,
    disposed: bool = false,
    running: bool = false,
    aborted: bool = false,
    next_entry: u64 = 1,
    persisted_count: u32 = 0,
};
const Method = enum(c_int) {
    getCwd,
    getSessionDir,
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
    setSessionName,
    setThinkingLevel,
    setModel,
    getSessionStats,
    clearQueue,
    steer,
    followUp,
};
const Getter = enum(c_int) { sessionId, sessionFile, sessionManager, settingsManager, modelRuntime, resourceLoader, model, thinkingLevel, messages, agent, systemPrompt, isStreaming, sessionName, session, services, cwd, diagnostics };

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
fn state(engine: *engine_mod.Engine, value: c.JSValue) !*State {
    return @ptrCast(@alignCast(c.JS_GetOpaque2(engine.context, value, engine.native_sdk_class) orelse return error.InvalidNativeSDKReceiver));
}
fn finalizer(runtime: ?*c.JSRuntime, value: c.JSValue) callconv(.c) void {
    const engine: *engine_mod.Engine = @ptrCast(@alignCast(c.JS_GetRuntimeOpaque(runtime)));
    const self: *State = @ptrCast(@alignCast(c.JS_GetOpaque(value, engine.native_sdk_class) orelse return));
    c.JS_FreeValueRT(runtime, self.data);
    for (self.listeners.items) |listener| c.JS_FreeValueRT(runtime, listener);
    self.listeners.deinit(engine.gpa);
    engine.gpa.destroy(self);
}
fn mark(runtime: ?*c.JSRuntime, value: c.JSValue, marker: ?*const c.JS_MarkFunc) callconv(.c) void {
    const engine: *engine_mod.Engine = @ptrCast(@alignCast(c.JS_GetRuntimeOpaque(runtime)));
    const self: *State = @ptrCast(@alignCast(c.JS_GetOpaque(value, engine.native_sdk_class) orelse return));
    c.JS_MarkValue(runtime, self.data, marker);
    for (self.listeners.items) |listener| c.JS_MarkValue(runtime, listener, marker);
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
    const methods: []const Method = switch (kind) {
        .session_manager => &.{ .getCwd, .getSessionDir, .getSessionId, .getSessionName, .getSessionFile, .getHeader, .getEntries, .getEntryCount, .getLeafId, .getLeafEntry, .getEntry, .getChildren, .getBranch, .getLabel, .getTree, .appendMessage, .appendCustomEntry, .appendSessionInfo, .appendModelChange, .appendThinkingLevelChange, .appendLabelChange, .branch, .resetLeaf, .buildSessionContext, .newSession, .setSessionFile, .isPersisted },
        .settings_manager => &.{ .getGlobalSettings, .getProjectSettings, .applyOverrides, .reload, .flush, .drainErrors, .getDefaultProvider, .getDefaultModel, .getDefaultThinkingLevel, .setDefaultThinkingLevel, .getCompactionSettings, .getRetrySettings, .getDefaultTools, .getTransport },
        .resource_loader => &.{ .reload, .getExtensions, .getSkills, .getPrompts, .getThemes, .getAgentsFiles, .getSystemPrompt, .getAppendSystemPrompt, .getSystemPromptSource, .getAppendSystemPromptSources, .extendResources },
        .model_runtime => &.{ .registerProvider, .registerNativeProvider, .unregisterProvider, .getProviders, .getModels, .getAll, .getAvailable, .getModel, .getModelsOfType, .getModelOfType, .getAllModels, .getAllAvailable, .getAvailableOfType, .checkAuth, .getAuth, .getAvailableSnapshot, .setRuntimeApiKey, .removeRuntimeApiKey, .hasConfiguredAuth, .clearRuntimeApiKey, .refresh, .streamSimple, .completeSimple, .classify, .generateImages },
        .agent_session => &.{ .subscribe, .unsubscribe, .dispose, .prompt, .abort, .bindExtensions, .getActiveToolNames, .setActiveToolsByName, .getAllTools, .setSessionName, .setThinkingLevel, .setModel, .getSessionStats, .clearQueue, .steer, .followUp, .newSession },
        .session_runtime => &.{ .newSession, .switchSession, .dispose, .setRebindSession, .setBeforeSessionInvalidate },
    };
    for (methods) |operation| {
        const name = try engine.gpa.dupeZ(u8, @tagName(operation));
        defer engine.gpa.free(name);
        try put(engine, value, name, try engine.checked(c.pi_js_function_magic(engine.context, method, name, 1, @intFromEnum(operation))));
    }
    if (kind == .agent_session or kind == .session_runtime) inline for (std.meta.fields(Getter)) |field| {
        const atom = c.JS_NewAtom(engine.context, field.name);
        defer c.JS_FreeAtom(engine.context, atom);
        const read = try engine.checked(c.pi_js_function_magic(engine.context, getter, field.name, 0, @intCast(field.value)));
        if (c.JS_DefinePropertyGetSet(engine.context, value, atom, read, c.pi_js_undefined(), c.JS_PROP_CONFIGURABLE | c.JS_PROP_ENUMERABLE) < 0) return error.JavaScriptException;
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
fn emit(self: *State, notification: c.JSValue) !void {
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
    var task = [_]c.JSValue{ receiver, args[0], if (args.len > 1) args[1] else c.pi_js_undefined(), functions[0], functions[1] };
    if (c.JS_EnqueueJob(engine.context, promptJob, task.len, &task) < 0) return error.OutOfMemory;
    self.running = true;
    self.aborted = false;
    return result;
}
fn runPrompt(self: *State, prompt_text: c.JSValue, _: c.JSValue) !void {
    const engine = self.engine;
    if (self.disposed) return error.NativeSDKDisposed;
    const model = try get(engine, self.data, "model");
    defer engine.freeValue(model);
    if (!c.JS_IsObject(model)) return error.NativeSDKNoModelSelected;
    const runtime = try get(engine, self.data, "modelRuntime");
    defer engine.freeValue(runtime);
    const manager = try get(engine, self.data, "sessionManager");
    defer engine.freeValue(manager);
    const messages = try get(engine, self.data, "messages");
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
        try put(engine, sections, "custom", try get(engine, self.data, "systemPrompt"));
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
        try put(engine, ctx, "tools", try get(engine, self.data, "customTools"));
        const options = try object(engine);
        defer engine.freeValue(options);
        try put(engine, options, "reasoning", try get(engine, self.data, "thinkingLevel"));
        const streamed = try invoke(engine, runtime, "streamSimple", &.{ model, ctx, options });
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
        const definitions = try get(engine, self.data, "customTools");
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
                const pending = try invoke(engine, tool, "execute", &.{ id, arguments, c.pi_js_undefined(), c.pi_js_undefined(), context_value });
                defer engine.freeValue(pending);
                const result = try engine.awaitValue(pending);
                defer engine.freeValue(result);
                const message = try object(engine);
                defer engine.freeValue(message);
                try put(engine, message, "role", try text(engine, "toolResult"));
                try put(engine, message, "toolCallId", c.JS_DupValue(engine.context, id));
                try put(engine, message, "toolName", c.JS_DupValue(engine.context, name));
                try put(engine, message, "content", try get(engine, result, "content"));
                try put(engine, message, "isError", c.pi_js_bool(engine.context, 0));
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
    try emit(self, settled);
}
fn emitMessage(self: *State, kind: []const u8, message: c.JSValue) !void {
    const value = try event(self, kind);
    defer self.engine.freeValue(value);
    try put(self.engine, value, "message", c.JS_DupValue(self.engine.context, message));
    try emit(self, value);
}
fn cwd(engine: *engine_mod.Engine) ![]u8 {
    if (engine.native_io) |io| {
        var buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
        const directory = try std.Io.Dir.cwd().openDir(io, ".", .{});
        defer directory.close(io);
        const count = try directory.realPath(io, &buffer);
        return engine.gpa.dupe(u8, buffer[0..count]);
    }
    return engine.gpa.dupe(u8, ".");
}
fn agentDir(engine: *engine_mod.Engine) ![]u8 {
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    const process = try get(engine, global, "process");
    defer engine.freeValue(process);
    if (c.JS_IsObject(process)) {
        const env = try get(engine, process, "env");
        defer engine.freeValue(env);
        if (c.JS_IsObject(env)) {
            const configured = try get(engine, env, "PI_AGENT_DIR");
            defer engine.freeValue(configured);
            if (c.JS_IsString(configured)) return engine.toString(configured);
            const home = try get(engine, env, "HOME");
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
fn identifier(engine: *engine_mod.Engine, prefix: []const u8) !c.JSValue {
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
fn initManager(engine: *engine_mod.Engine, args: []const c.JSValue, persistent: bool) !c.JSValue {
    const data = try object(engine);
    defer engine.freeValue(data);
    const current = if (args.len > 0 and c.JS_IsString(args[0])) try engine.toString(args[0]) else try cwd(engine);
    defer engine.gpa.free(current);
    try put(engine, data, "cwd", try text(engine, current));
    const directory = if (!persistent) try engine.gpa.dupe(u8, "") else if (args.len > 1 and c.JS_IsString(args[1])) try engine.toString(args[1]) else blk: {
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
    if (args.len > options_index and c.JS_IsObject(args[options_index])) {
        const chosen = try get(engine, args[options_index], "id");
        defer engine.freeValue(chosen);
        if (!c.JS_IsUndefined(chosen)) {
            if (!c.JS_IsString(chosen)) return error.InvalidSessionId;
            const raw = try engine.toString(chosen);
            defer engine.gpa.free(raw);
            if (raw.len == 0 or !std.ascii.isAlphanumeric(raw[0]) or !std.ascii.isAlphanumeric(raw[raw.len - 1])) return error.InvalidSessionId;
            for (raw) |byte| if (!std.ascii.isAlphanumeric(byte) and byte != '.' and byte != '_' and byte != '-') return error.InvalidSessionId;
            try put(engine, header, "id", c.JS_DupValue(engine.context, chosen));
        }
    }
    try put(engine, header, "timestamp", try timestamp(engine));
    try put(engine, header, "cwd", try text(engine, current));
    try put(engine, data, "header", c.JS_DupValue(engine.context, header));
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
    return new(engine, .session_manager, data);
}
fn encodeCwd(engine: *engine_mod.Engine, input: []const u8) ![]u8 {
    const start: usize = if (input.len > 0 and (input[0] == '/' or input[0] == '\\')) 1 else 0;
    const result = try std.fmt.allocPrint(engine.gpa, "--{s}--", .{input[start..]});
    for (result) |*byte| if (byte.* == '/' or byte.* == '\\' or byte.* == ':') {
        byte.* = '-';
    };
    return result;
}
fn entry(self: *State, kind: []const u8) !c.JSValue {
    const engine = self.engine;
    const result = try object(engine);
    errdefer engine.freeValue(result);
    try put(engine, result, "type", try text(engine, kind));
    try put(engine, result, "id", try identifier(engine, "entry"));
    try put(engine, result, "timestamp", try timestamp(engine));
    try put(engine, result, "parentId", try get(engine, self.data, "leafId"));
    return result;
}
fn commitEntry(self: *State, value: c.JSValue) !c.JSValue {
    const engine = self.engine;
    const entries = try get(engine, self.data, "entries");
    defer engine.freeValue(entries);
    const id = try get(engine, value, "id");
    errdefer engine.freeValue(id);
    try append(engine, entries, c.JS_DupValue(engine.context, value));
    try put(engine, self.data, "leafId", c.JS_DupValue(engine.context, id));
    try persist(self);
    return id;
}
fn persist(self: *State) !void {
    const engine = self.engine;
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
    if (!has_assistant) return;
    var output: std.Io.Writer.Allocating = .init(engine.gpa);
    defer output.deinit();
    const header = try get(engine, self.data, "header");
    defer engine.freeValue(header);
    if (self.persisted_count == 0) {
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
    if (self.persisted_count == 0) {
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
}
fn findEntry(self: *State, id: c.JSValue) !c.JSValue {
    const engine = self.engine;
    const names = try engine.toString(id);
    defer engine.gpa.free(names);
    const entries = try get(engine, self.data, "entries");
    defer engine.freeValue(entries);
    for (0..try length(engine, entries)) |i| {
        const row = try engine.checked(c.JS_GetPropertyUint32(engine.context, entries, @intCast(i)));
        defer engine.freeValue(row);
        const candidate = try get(engine, row, "id");
        defer engine.freeValue(candidate);
        const value = try engine.toString(candidate);
        defer engine.gpa.free(value);
        if (std.mem.eql(u8, names, value)) return c.JS_DupValue(engine.context, row);
    }
    return c.pi_js_undefined();
}
fn branchEntries(self: *State, from: c.JSValue) !c.JSValue {
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
    const rows = try get(engine, self.data, "entries");
    defer engine.freeValue(rows);
    var result = c.pi_js_undefined();
    errdefer engine.freeValue(result);
    for (0..try length(engine, rows)) |i| {
        const row = try engine.checked(c.JS_GetPropertyUint32(engine.context, rows, @intCast(i)));
        defer engine.freeValue(row);
        const typ = try get(engine, row, "type");
        defer engine.freeValue(typ);
        const name = try engine.toString(typ);
        defer engine.gpa.free(name);
        if (!std.mem.eql(u8, name, "label")) continue;
        const target = try get(engine, row, "targetId");
        defer engine.freeValue(target);
        if (!c.JS_IsStrictEqual(engine.context, target, id)) continue;
        engine.freeValue(result);
        result = try get(engine, row, "label");
        if (c.JS_IsNull(result)) {
            engine.freeValue(result);
            result = c.pi_js_undefined();
        }
    }
    return result;
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
        try put(engine, node, "entry", try clone(engine, row));
        try put(engine, node, "children", try array(engine));
        const id = try get(engine, row, "id");
        defer engine.freeValue(id);
        const label = try labelFor(self, id);
        defer engine.freeValue(label);
        if (!c.JS_IsUndefined(label)) try put(engine, node, "label", c.JS_DupValue(engine.context, label));
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
        var attached = false;
        if (c.JS_IsString(parent)) for (0..try length(engine, nodes)) |j| {
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
    return roots;
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
    var project = try object(engine);
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
        const loaded_global = try loadJsonFile(engine, global_path);
        engine.freeValue(global);
        global = loaded_global;
        const loaded_project = try loadJsonFile(engine, project_path);
        engine.freeValue(project);
        project = loaded_project;
        try put(engine, data, "settingsPath", try text(engine, global_path));
        try put(engine, data, "projectPath", try text(engine, project_path));
    } else if (args.len > 0 and c.JS_IsObject(args[0])) {
        const loaded_global = try clone(engine, args[0]);
        engine.freeValue(global);
        global = loaded_global;
    }
    try put(engine, data, "global", c.JS_DupValue(engine.context, global));
    try put(engine, data, "project", c.JS_DupValue(engine.context, project));
    try put(engine, data, "settings", try merge(engine, global, project));
    try put(engine, data, "errors", try array(engine));
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
        const base = try text(engine, "You are a helpful coding assistant.");
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
    const first = if (args.len > 0) args[0] else c.pi_js_undefined();
    if (operation == .getGlobalSettings or operation == .getProjectSettings) {
        const value = try get(engine, self.data, if (operation == .getGlobalSettings) "global" else "project");
        defer engine.freeValue(value);
        return clone(engine, value);
    }
    if (operation == .applyOverrides) {
        const old = try get(engine, self.data, "settings");
        defer engine.freeValue(old);
        try put(engine, self.data, "settings", try merge(engine, old, first));
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
        try put(engine, self.data, "settings", try merge(engine, global, project));
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
    try put(engine, agent_state, "tools", try get(engine, data, "customTools"));
    try put(engine, agent, "state", c.JS_DupValue(engine.context, agent_state));
    try put(engine, data, "agent", c.JS_DupValue(engine.context, agent));
    const session = try new(engine, .agent_session, data);
    defer engine.freeValue(session);
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
    return result;
}
fn modelDispatch(self: *State, operation: Method, args: []const c.JSValue) !c.JSValue {
    const engine = self.engine;
    const catalog = try get(engine, self.data, "models");
    defer engine.freeValue(catalog);
    if (operation == .registerNativeProvider) return invoke(engine, catalog, "setProvider", args);
    if (operation == .registerProvider) {
        if (args.len != 2 or !c.JS_IsString(args[0]) or !c.JS_IsObject(args[1])) return error.NativeSDKInvalidProviderConfig;
        const provider = try object(engine);
        defer engine.freeValue(provider);
        try put(engine, provider, "id", c.JS_DupValue(engine.context, args[0]));
        const models = try get(engine, args[1], "models");
        defer engine.freeValue(models);
        if (!c.JS_IsArray(models)) return error.NativeSDKInvalidProviderConfig;
        var data = [_]c.JSValue{ models, args[0] };
        const model_getter = try engine.checked(c.JS_NewCFunctionData2(engine.context, providerModels, "getModels", 0, 0, 2, &data));
        defer engine.freeValue(model_getter);
        try put(engine, provider, "getModels", c.JS_DupValue(engine.context, model_getter));
        try put(engine, provider, "getAllModels", c.JS_DupValue(engine.context, model_getter));
        const streamer = try get(engine, args[1], "streamSimple");
        defer engine.freeValue(streamer);
        if (c.JS_IsFunction(engine.context, streamer)) try put(engine, provider, "streamSimple", c.JS_DupValue(engine.context, streamer));
        const authentication = try get(engine, args[1], "auth");
        defer engine.freeValue(authentication);
        try put(engine, provider, "auth", if (c.JS_IsObject(authentication)) c.JS_DupValue(engine.context, authentication) else try object(engine));
        try @import("native_sdk_operations.zig").install(engine, provider);
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
    if (operation == .refresh) {
        const value = try object(engine);
        defer engine.freeValue(value);
        try put(engine, value, "errors", try array(engine));
        return promise(engine, value);
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
    if (args.len == 0 or !c.JS_IsString(args[0])) return error.NativeSDKMissingArgument;
    const path = try engine.toString(args[0]);
    defer engine.gpa.free(path);
    const raw = try std.Io.Dir.cwd().readFileAlloc(engine.native_io orelse return error.NativeSDKRequiresIO, path, engine.gpa, .limited(16 * 1024 * 1024));
    defer engine.gpa.free(raw);
    var lines = std.mem.splitScalar(u8, raw, '\n');
    const header = try jsonObject(engine, lines.next() orelse return error.InvalidSessionFile);
    defer engine.freeValue(header);
    const header_cwd = try get(engine, header, "cwd");
    defer engine.freeValue(header_cwd);
    const session_dir = try text(engine, std.fs.path.dirname(path) orelse ".");
    defer engine.freeValue(session_dir);
    const manager = try initManager(engine, &.{ header_cwd, session_dir }, false);
    errdefer engine.freeValue(manager);
    const target = try state(engine, manager);
    try put(engine, target.data, "header", c.JS_DupValue(engine.context, header));
    try put(engine, target.data, "sessionFile", c.JS_DupValue(engine.context, args[0]));
    try put(engine, target.data, "sessionDir", c.JS_DupValue(engine.context, session_dir));
    try put(engine, target.data, "persistent", c.pi_js_bool(engine.context, 1));
    const entries = try get(engine, target.data, "entries");
    defer engine.freeValue(entries);
    while (lines.next()) |line| {
        if (std.mem.trim(u8, line, " \r\t").len == 0) continue;
        const row = try jsonObject(engine, line);
        defer engine.freeValue(row);
        try append(engine, entries, c.JS_DupValue(engine.context, row));
        try put(engine, target.data, "leafId", try get(engine, row, "id"));
    }
    target.persisted_count = try length(engine, entries);
    return manager;
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
    if (self.disposed and operation != .dispose) return error.NativeSDKDisposed;
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
            for (self.listeners.items) |listener| engine.freeValue(listener);
            self.listeners.clearRetainingCapacity();
            return c.pi_js_undefined();
        }
        if (operation == .abort) {
            self.aborted = true;
            return promise(engine, c.pi_js_undefined());
        }
        if (operation == .bindExtensions) return promise(engine, c.pi_js_undefined());
        if (operation == .getActiveToolNames) {
            const value = try get(engine, self.data, "activeTools");
            defer engine.freeValue(value);
            return clone(engine, value);
        }
        if (operation == .setActiveToolsByName) {
            try put(engine, self.data, "activeTools", try clone(engine, first));
            return c.pi_js_undefined();
        }
        if (operation == .getAllTools) {
            const value = try get(engine, self.data, "customTools");
            defer engine.freeValue(value);
            return c.JS_DupValue(engine.context, value);
        }
        if (operation == .setSessionName) {
            const manager = try get(engine, self.data, "sessionManager");
            defer engine.freeValue(manager);
            const value = try invoke(engine, manager, "appendSessionInfo", &.{first});
            engine.freeValue(value);
            return c.pi_js_undefined();
        }
        if (operation == .setThinkingLevel) {
            try put(engine, self.data, "thinkingLevel", c.JS_DupValue(engine.context, first));
            const manager = try get(engine, self.data, "sessionManager");
            defer engine.freeValue(manager);
            const value = try invoke(engine, manager, "appendThinkingLevelChange", &.{first});
            engine.freeValue(value);
            return c.pi_js_undefined();
        }
        if (operation == .setModel) {
            if (args.len < 2) return error.NativeSDKMissingArgument;
            const runtime = try get(engine, self.data, "modelRuntime");
            defer engine.freeValue(runtime);
            const model = try invoke(engine, runtime, "getModel", args);
            defer engine.freeValue(model);
            if (!c.JS_IsObject(model)) return error.NativeSDKModelUnavailable;
            try put(engine, self.data, "model", c.JS_DupValue(engine.context, model));
            const manager = try get(engine, self.data, "sessionManager");
            defer engine.freeValue(manager);
            const recorded = try invoke(engine, manager, "appendModelChange", args);
            engine.freeValue(recorded);
            return promise(engine, c.pi_js_undefined());
        }
        if (operation == .clearQueue) return c.pi_js_undefined();
        if (operation == .steer or operation == .followUp) return error.NativeSDKQueueWhileRunningRequired;
        if (operation == .newSession) {
            if (self.running) return error.NativeSDKSessionBusy;
            const manager = try get(engine, self.data, "sessionManager");
            defer engine.freeValue(manager);
            const path = try invoke(engine, manager, "newSession", args);
            engine.freeValue(path);
            try put(engine, self.data, "messages", try array(engine));
            return promise(engine, c.pi_js_bool(engine.context, 1));
        }
        if (operation == .getSessionStats) {
            const value = try object(engine);
            errdefer engine.freeValue(value);
            try put(engine, value, "sessionId", try getterValue(self, .sessionId));
            try put(engine, value, "sessionFile", try getterValue(self, .sessionFile));
            const messages = try get(engine, self.data, "messages");
            defer engine.freeValue(messages);
            try put(engine, value, "totalMessages", c.JS_NewInt32(engine.context, @intCast(try length(engine, messages))));
            return value;
        }
        return error.NativeSDKMethodUnavailable;
    }
    if (self.kind == .settings_manager) return settingsDispatch(self, operation, args);
    if (self.kind == .model_runtime) return modelDispatch(self, operation, args);
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
        if (operation == .getSystemPromptSource) return c.pi_js_undefined();
        if (operation == .getAppendSystemPromptSources) return array(engine);
        if (operation == .extendResources) return error.NativeSDKResourcePathExtensionsNotYetSupported;
        return error.NativeSDKMethodUnavailable;
    }
    if (self.kind == .session_manager) {
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
                if (std.mem.eql(u8, value, "session_info")) return get(engine, row, "name");
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
            defer engine.freeValue(value);
            return clone(engine, value);
        }
        if (operation == .getSessionId) {
            const header = try get(engine, self.data, "header");
            defer engine.freeValue(header);
            return get(engine, header, "id");
        }
        if (operation == .getEntryCount) {
            const rows = try get(engine, self.data, "entries");
            defer engine.freeValue(rows);
            return c.JS_NewInt32(engine.context, @intCast(try length(engine, rows)));
        }
        if (operation == .getEntry or operation == .getLeafEntry) {
            const id = if (operation == .getEntry) c.JS_DupValue(engine.context, first) else try get(engine, self.data, "leafId");
            defer engine.freeValue(id);
            const value = try findEntry(self, id);
            defer engine.freeValue(value);
            return clone(engine, value);
        }
        if (operation == .getBranch) {
            const id = if (c.JS_IsString(first)) c.JS_DupValue(engine.context, first) else try get(engine, self.data, "leafId");
            defer engine.freeValue(id);
            const value = try branchEntries(self, id);
            defer engine.freeValue(value);
            return clone(engine, value);
        }
        if (operation == .newSession) {
            const working = try get(engine, self.data, "cwd");
            defer engine.freeValue(working);
            const directory = try get(engine, self.data, "sessionDir");
            defer engine.freeValue(directory);
            const persistent = try get(engine, self.data, "persistent");
            defer engine.freeValue(persistent);
            const created = try initManager(engine, &.{ working, directory }, c.JS_ToBool(engine.context, persistent) == 1);
            defer engine.freeValue(created);
            const fresh = try state(engine, created);
            engine.freeValue(self.data);
            self.data = c.JS_DupValue(engine.context, fresh.data);
            self.persisted_count = 0;
            return get(engine, self.data, "sessionFile");
        }
        if (operation == .setSessionFile) {
            const replacement = try openManager(engine, &.{first});
            defer engine.freeValue(replacement);
            const fresh = try state(engine, replacement);
            engine.freeValue(self.data);
            self.data = c.JS_DupValue(engine.context, fresh.data);
            self.persisted_count = fresh.persisted_count;
            return c.pi_js_undefined();
        }
        if (operation == .branch or operation == .resetLeaf) {
            if (operation == .branch) {
                const found = try findEntry(self, first);
                defer engine.freeValue(found);
                if (c.JS_IsUndefined(found)) return error.InvalidSessionEntry;
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
                if (c.JS_IsStrictEqual(engine.context, parent, first)) try append(engine, output, try clone(engine, row));
            }
            return output;
        }
        if (operation == .buildSessionContext) {
            const result = try object(engine);
            errdefer engine.freeValue(result);
            const id = try get(engine, self.data, "leafId");
            defer engine.freeValue(id);
            const path = try branchEntries(self, id);
            defer engine.freeValue(path);
            const messages = try array(engine);
            defer engine.freeValue(messages);
            var thinking: c.JSValue = try text(engine, "off");
            defer engine.freeValue(thinking);
            var model = c.pi_js_null();
            defer engine.freeValue(model);
            for (0..try length(engine, path)) |i| {
                const row = try engine.checked(c.JS_GetPropertyUint32(engine.context, path, @intCast(i)));
                defer engine.freeValue(row);
                const typ = try get(engine, row, "type");
                defer engine.freeValue(typ);
                const name = try engine.toString(typ);
                defer engine.gpa.free(name);
                if (std.mem.eql(u8, name, "message")) {
                    try append(engine, messages, try get(engine, row, "message"));
                } else if (std.mem.eql(u8, name, "thinking_level_change")) {
                    engine.freeValue(thinking);
                    thinking = try get(engine, row, "thinkingLevel");
                } else if (std.mem.eql(u8, name, "model_change")) {
                    engine.freeValue(model);
                    model = try object(engine);
                    try put(engine, model, "provider", try get(engine, row, "provider"));
                    try put(engine, model, "modelId", try get(engine, row, "modelId"));
                }
            }
            try put(engine, result, "messages", c.JS_DupValue(engine.context, messages));
            try put(engine, result, "thinkingLevel", c.JS_DupValue(engine.context, thinking));
            try put(engine, result, "model", c.JS_DupValue(engine.context, model));
            return result;
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
                .appendMessage => try put(engine, row, "message", try clone(engine, first)),
                .appendCustomEntry => {
                    try put(engine, row, "customType", c.JS_DupValue(engine.context, first));
                    if (args.len > 1) try put(engine, row, "data", try clone(engine, second));
                },
                .appendSessionInfo => try put(engine, row, "name", c.JS_DupValue(engine.context, first)),
                .appendModelChange => {
                    try put(engine, row, "provider", c.JS_DupValue(engine.context, first));
                    try put(engine, row, "modelId", c.JS_DupValue(engine.context, second));
                },
                .appendThinkingLevelChange => try put(engine, row, "thinkingLevel", c.JS_DupValue(engine.context, first)),
                .appendLabelChange => {
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
        300 => initModelRuntime(engine, if (args.len > 0) args[0] else c.pi_js_undefined()),
        else => error.NativeSDKMethodUnavailable,
    }) catch |err| return fail(engine, err);
    if (magic == 300) {
        defer engine.freeValue(result);
        return promise(engine, result) catch |err| fail(engine, err);
    }
    return result;
}
pub fn install(engine: *engine_mod.Engine, exports: c.JSValue) !void {
    if (engine.native_sdk_class != 0) return;
    _ = c.JS_NewClassID(engine.runtime, &engine.native_sdk_class);
    const definition: c.JSClassDef = .{ .class_name = "Native coding SDK object", .finalizer = finalizer, .gc_mark = mark, .call = null, .exotic = null };
    if (c.JS_NewClass(engine.runtime, engine.native_sdk_class, &definition) < 0) return error.OutOfMemory;
    try put(engine, exports, "createAgentSession", try engine.checked(c.JS_NewCFunction(engine.context, createSession, "createAgentSession", 1)));
    try put(engine, exports, "createAgentSessionServices", try engine.checked(c.pi_js_function_magic(engine.context, serviceCallback, "createAgentSessionServices", 1, 0)));
    try put(engine, exports, "createAgentSessionFromServices", try engine.checked(c.pi_js_function_magic(engine.context, serviceCallback, "createAgentSessionFromServices", 1, 1)));
    try put(engine, exports, "createAgentSessionRuntime", try engine.checked(c.JS_NewCFunction(engine.context, createRuntime, "createAgentSessionRuntime", 2)));
    try put(engine, exports, "getAgentDir", try engine.checked(c.JS_NewCFunction(engine.context, getAgentDirectory, "getAgentDir", 0)));
    inline for (.{ .{ Kind.session_manager, "SessionManager" }, .{ Kind.settings_manager, "SettingsManager" }, .{ Kind.resource_loader, "DefaultResourceLoader" }, .{ Kind.model_runtime, "ModelRuntime" }, .{ Kind.agent_session, "AgentSession" }, .{ Kind.session_runtime, "AgentSessionRuntime" } }) |item| {
        const proto = try object(engine);
        defer engine.freeValue(proto);
        engine.native_sdk_prototypes[@as(usize, @intCast(@intFromEnum(item[0])))] = c.JS_DupValue(engine.context, proto);
        const ctor = try engine.checked(c.JS_NewCFunctionData2(engine.context, constructorData, item[1], 1, @intFromEnum(item[0]), 0, null));
        defer engine.freeValue(ctor);
        _ = c.JS_SetConstructorBit(engine.context, ctor, true);
        if (c.JS_SetConstructor(engine.context, ctor, proto) < 0) return error.JavaScriptException;
        if (item[0] == .session_manager) inline for (.{ .{ "inMemory", 0 }, .{ "create", 1 }, .{ "open", 2 } }) |operation| try put(engine, ctor, operation[0], try engine.checked(c.pi_js_function_magic(engine.context, staticMethod, operation[0], 1, operation[1])));
        if (item[0] == .settings_manager) inline for (.{ .{ "inMemory", 100 }, .{ "create", 101 } }) |operation| try put(engine, ctor, operation[0], try engine.checked(c.pi_js_function_magic(engine.context, staticMethod, operation[0], 1, operation[1])));
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
