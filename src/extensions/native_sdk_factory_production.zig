//! Actual sdk.ts and agent-session-services.ts orchestration over captured,
//! genuine imported bindings. This module never constructs SDK.Kind.agent_session.
//! Production composition supplies the real AI, loader, model/auth and lifecycle
//! classes; dependency validation alone is not a qualification claim.
const em = @import("engine.zig");
const sdk = @import("native_sdk.zig");
const js = @import("native_js_values.zig");
const temp = @import("native_sdk_prompt_scope.zig");
const Scope = temp.Scope;
const flow = @import("native_agent_async.zig");
const c = em.c;
const Operation = enum(c_int) { createAgentSession, createAgentSessionServices, createAgentSessionFromServices, createAgentSessionRuntime };
const Stage = enum(c_int) { runtime, reload, initial_model, services_runtime, services_reload, services_refresh, lifecycle };

/// Import bindings captured once, just as Source module imports are captured.
/// AgentSession is deliberately absent: compose() creates it through the actual
/// ordinary production constructor, and create() takes that exact identity.
pub const required_functions = .{ "resolvePath", "getAgentDir", "join", "getDefaultSessionDir", "findInitialModel", "getBranchSelection", "clampThinkingLevel", "formatNoModelsAvailableMessage", "getToolListError", "isToolModifier", "applyToolModifiers", "createToolNameMatcher", "time", "Agent", "SettingsManager", "SessionManager", "ModelRuntime", "DefaultResourceLoader", "AgentSessionRuntime", "assertSessionCwdExists", "setDefaultStreamFn", "streamSimple" };

pub fn compose(engine: *em.Engine, inputs: @import("native_sdk_session_production.zig").Inputs, imports: c.JSValue) !c.JSValue {
    const ordinary = try @import("native_sdk_session_production.zig").constructor(engine, inputs);
    defer engine.freeValue(ordinary);
    return create(engine, imports, ordinary);
}

/// No fallback classes or models are supplied here. The application's module
/// assembler owns the provenance of imports and the shared ordinary constructor.
pub fn create(engine: *em.Engine, imports: c.JSValue, ordinary: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const bindings = try scope.object();
    inline for (required_functions) |name| {
        const value = try scope.get(imports, name);
        if (!c.JS_IsFunction(engine.context, value)) return error.RequiredActualSdkFactoryBinding;
        try scope.put(bindings, name, value);
    }
    if (!c.JS_IsConstructor(engine.context, ordinary)) return error.RequiredOrdinaryAgentSessionConstructor;
    try scope.put(bindings, "AgentSession", ordinary);
    try scope.put(bindings, "process", try scope.get(imports, "process"));
    try scope.put(bindings, "DEFAULT_THINKING_LEVEL", try scope.get(imports, "DEFAULT_THINKING_LEVEL"));
    try scope.put(bindings, "DEFAULT_TOOL_NAMES", try scope.get(imports, "DEFAULT_TOOL_NAMES"));
    // Source SDK module preserves agent-core's pre-0.81 low-level fallback by
    // setting its actual shared default to the actual compat dispatch once.
    _ = try imported(&scope, bindings, "setDefaultStreamFn", &.{try scope.get(bindings, "streamSimple")});
    const result = try scope.object();
    inline for (@typeInfo(Operation).@"enum".fields) |field| {
        var roots = [_]c.JSValue{bindings};
        const function = try scope.own(try engine.checked(c.JS_NewCFunctionData2(engine.context, dispatch, field.name, if (field.value == @intFromEnum(Operation.createAgentSession)) 0 else if (field.value == @intFromEnum(Operation.createAgentSessionRuntime)) 2 else 1, field.value, roots.len, &roots)));
        if (c.JS_SetPrototype(engine.context, function, try scope.own(try engine.checked(c.JS_GetAsyncFunctionPrototype(engine.context)))) < 0) return js.capture(engine);
        try scope.put(result, field.name, function);
    }
    try scope.put(result, "AgentSession", ordinary);
    return c.JS_DupValue(engine.context, result);
}
fn dispatch(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, magic: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    engine.native_exception_diagnostics_suppressed += 1;
    defer engine.native_exception_diagnostics_suppressed -= 1;
    return begin(engine, roots[0], @enumFromInt(magic), if (argc > 0) argv[0] else c.pi_js_undefined(), if (argc > 1) argv[1] else c.pi_js_undefined()) catch |err| sdk.fail(engine, err);
}
fn imported(scope: *Scope, bindings: c.JSValue, name: [*:0]const u8, args: []const c.JSValue) !c.JSValue {
    return scope.call(try scope.get(bindings, name), c.pi_js_undefined(), args);
}
fn construct(scope: *Scope, bindings: c.JSValue, name: [*:0]const u8, args: []const c.JSValue) !c.JSValue {
    return scope.own(try scope.engine.checked(c.JS_CallConstructor(scope.engine.context, try scope.get(bindings, name), @intCast(args.len), @constCast(args.ptr))));
}
fn begin(engine: *em.Engine, bindings: c.JSValue, operation: Operation, first: c.JSValue, second: c.JSValue) !c.JSValue {
    const pending = try flow.create(engine, c.pi_js_undefined());
    defer engine.freeValue(pending.owner);
    errdefer engine.freeValue(pending.promise);
    start(engine, pending.owner, bindings, operation, first, second) catch |err| try flow.rejectError(engine, pending.owner, err);
    return pending.promise;
}
fn start(engine: *em.Engine, owner: c.JSValue, bindings: c.JSValue, operation: Operation, first: c.JSValue, second: c.JSValue) !void {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    try scope.put(owner, "bindings", bindings);
    switch (operation) {
        .createAgentSession => {
            const options = if (c.JS_IsUndefined(first)) try scope.object() else first;
            try scope.put(owner, "options", options);
            try startSession(engine, owner);
        },
        .createAgentSessionServices => {
            try scope.put(owner, "options", first);
            try startServices(engine, owner);
        },
        .createAgentSessionFromServices => {
            const options = try scope.object();
            // Source evaluates options.services independently for each field.
            inline for (.{ "cwd", "agentDir", "modelRuntime", "settingsManager", "resourceLoader" }) |name| try scope.put(options, name, try scope.get(try scope.get(first, "services"), name));
            inline for (.{ "sessionManager", "model", "thinkingLevel", "scopedModels", "tools", "excludeTools", "noTools", "customTools", "sessionStartEvent" }) |name| try scope.put(options, name, try scope.get(first, name));
            // Source returns the inner async call from a separate async body.
            // Keep both promises and the adoption job, including synchronous
            // options-getter rejection of this outer call before the inner call.
            const inner = try scope.own(try begin(engine, bindings, .createAgentSession, options, c.pi_js_undefined()));
            return flow.settle(engine, owner, false, inner);
        },
        .createAgentSessionRuntime => {
            _ = try imported(&scope, bindings, "assertSessionCwdExists", &.{ try scope.get(second, "sessionManager"), try scope.get(second, "cwd") });
            try scope.put(owner, "createRuntime", first);
            return flow.wait(continueFactory, engine, owner, try scope.call(first, c.pi_js_undefined(), &.{second}), @intFromEnum(Stage.lifecycle));
        },
    }
}
fn continueFactory(engine: *em.Engine, owner: c.JSValue, value: c.JSValue, rejected: bool, stage: c_int) !void {
    if (rejected) return flow.settle(engine, owner, true, value);
    resumeBody(engine, owner, value, @enumFromInt(stage)) catch |err| try flow.rejectError(engine, owner, err);
}
fn resumeBody(engine: *em.Engine, owner: c.JSValue, value: c.JSValue, stage: Stage) !void {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    switch (stage) {
        .runtime => {
            try scope.put(owner, "modelRuntime", value);
            try sessionServices(engine, owner);
        },
        .reload => {
            _ = try imported(&scope, try scope.get(owner, "bindings"), "time", &.{try scope.text("resourceLoader.reload")});
            try restoreSession(engine, owner);
        },
        .initial_model => {
            const bindings = try scope.get(owner, "bindings");
            const model = try scope.get(value, "model");
            try scope.put(owner, "model", model);
            if (!scope.truthy(model)) {
                try scope.put(owner, "modelFallbackMessage", try imported(&scope, bindings, "formatNoModelsAvailableMessage", &.{}));
            } else if (scope.truthy(try scope.get(owner, "modelFallbackMessage"))) {
                const suffix = try scope.concat(try scope.concat(try scope.concat(try scope.text(". Using "), try scope.stringify(try scope.get(model, "provider"))), try scope.text("/")), try scope.stringify(try scope.get(model, "id")));
                try scope.put(owner, "modelFallbackMessage", try scope.concat(try scope.get(owner, "modelFallbackMessage"), suffix));
            }
            try finishSession(engine, owner);
        },
        .services_runtime => {
            try scope.put(owner, "modelRuntime", value);
            try servicesLoader(engine, owner);
        },
        .services_reload => try registerPendingProviders(engine, owner),
        .services_refresh => try finishServices(engine, owner),
        .lifecycle => {
            const target = try construct(&scope, try scope.get(owner, "bindings"), "AgentSessionRuntime", &.{ try scope.get(value, "session"), try scope.get(value, "services"), try scope.get(owner, "createRuntime"), try scope.get(value, "diagnostics"), try scope.get(value, "modelFallbackMessage") });
            try flow.settle(engine, owner, false, target);
        },
    }
}
fn startSession(engine: *em.Engine, owner: c.JSValue) !void {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const bindings = try scope.get(owner, "bindings");
    const options = try scope.get(owner, "options");
    var work = try scope.get(options, "cwd");
    if (temp.nullish(work)) {
        const manager = try scope.get(options, "sessionManager");
        work = if (temp.nullish(manager)) c.pi_js_undefined() else try scope.invoke(manager, "getCwd", &.{});
        if (temp.nullish(work)) work = try scope.invoke(try scope.get(bindings, "process"), "cwd", &.{});
    }
    try scope.put(owner, "cwd", try imported(&scope, bindings, "resolvePath", &.{work}));
    const directory = if (scope.truthy(try scope.get(options, "agentDir"))) try imported(&scope, bindings, "resolvePath", &.{try scope.get(options, "agentDir")}) else try imported(&scope, bindings, "getAgentDir", &.{});
    try scope.put(owner, "agentDir", directory);
    try scope.put(owner, "resourceLoader", try scope.get(options, "resourceLoader"));
    const auth_path = if (scope.truthy(try scope.get(options, "agentDir"))) try imported(&scope, bindings, "join", &.{ directory, try scope.text("auth.json") }) else c.pi_js_undefined();
    const models_path = if (scope.truthy(try scope.get(options, "agentDir"))) try imported(&scope, bindings, "join", &.{ directory, try scope.text("models.json") }) else c.pi_js_undefined();
    const runtime = try scope.get(options, "modelRuntime");
    if (temp.nullish(runtime)) {
        const constructor = try scope.get(bindings, "ModelRuntime");
        const create_method = try scope.get(constructor, "create");
        const configured = try scope.object();
        try scope.put(configured, "authPath", auth_path);
        try scope.put(configured, "modelsPath", models_path);
        return flow.wait(continueFactory, engine, owner, try scope.call(create_method, constructor, &.{configured}), @intFromEnum(Stage.runtime));
    }
    try scope.put(owner, "modelRuntime", runtime);
    try sessionServices(engine, owner);
}
fn sessionServices(engine: *em.Engine, owner: c.JSValue) !void {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const bindings = try scope.get(owner, "bindings");
    const options = try scope.get(owner, "options");
    const cwd = try scope.get(owner, "cwd");
    const directory = try scope.get(owner, "agentDir");
    var settings = try scope.get(options, "settingsManager");
    if (temp.nullish(settings)) settings = try scope.invoke(try scope.get(bindings, "SettingsManager"), "create", &.{ cwd, directory });
    try scope.put(owner, "settingsManager", settings);
    var manager = try scope.get(options, "sessionManager");
    if (temp.nullish(manager)) {
        // Preserve lookup of SessionManager.create before evaluating its arguments.
        const ctor = try scope.get(bindings, "SessionManager");
        const create_method = try scope.get(ctor, "create");
        manager = try scope.call(create_method, ctor, &.{ cwd, try imported(&scope, bindings, "getDefaultSessionDir", &.{ cwd, directory }) });
    }
    try scope.put(owner, "sessionManager", manager);
    if (!scope.truthy(try scope.get(owner, "resourceLoader"))) {
        const configured = try scope.object();
        try scope.put(configured, "cwd", cwd);
        try scope.put(configured, "agentDir", directory);
        try scope.put(configured, "settingsManager", settings);
        const loader = try construct(&scope, bindings, "DefaultResourceLoader", &.{configured});
        try scope.put(owner, "resourceLoader", loader);
        return flow.wait(continueFactory, engine, owner, try scope.invoke(loader, "reload", &.{}), @intFromEnum(Stage.reload));
    }
    try restoreSession(engine, owner);
}
fn restoreSession(engine: *em.Engine, owner: c.JSValue) !void {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const bindings = try scope.get(owner, "bindings");
    const options = try scope.get(owner, "options");
    const manager = try scope.get(owner, "sessionManager");
    const runtime = try scope.get(owner, "modelRuntime");
    const settings = try scope.get(owner, "settingsManager");
    const existing = try scope.invoke(manager, "buildSessionContext", &.{});
    try scope.put(owner, "existingSession", existing);
    const has_existing = try scope.positive(try scope.get(try scope.get(existing, "messages"), "length"));
    try scope.put(owner, "hasExistingSession", c.pi_js_bool(engine.context, @intFromBool(has_existing)));
    const branch = try scope.invoke(manager, "getBranch", &.{});
    const some = try scope.get(branch, "some");
    const predicate = try scope.own(try engine.checked(c.JS_NewCFunction(engine.context, isThinkingEntry, "", 1)));
    try scope.put(owner, "hasThinkingEntry", try scope.call(some, branch, &.{predicate}));
    var model = try scope.get(options, "model");
    try scope.put(owner, "modelFallbackMessage", c.pi_js_undefined());
    const select = try scope.get(bindings, "getBranchSelection");
    const current_branch = try scope.invoke(manager, "getBranch", &.{});
    var roots = [_]c.JSValue{runtime};
    const lookup = try scope.own(try engine.checked(c.JS_NewCFunctionData2(engine.context, lookupModel, "", 2, 0, roots.len, &roots)));
    const selection = try scope.call(select, c.pi_js_undefined(), &.{ current_branch, lookup });
    if (!scope.truthy(model) and has_existing and scope.truthy(selection)) {
        const restored = try scope.invoke(runtime, "getModel", &.{ try scope.get(selection, "provider"), try scope.get(selection, "modelId") });
        if (scope.truthy(restored)) {
            const check = try scope.get(runtime, "hasConfiguredAuth");
            if (scope.truthy(try scope.call(check, runtime, &.{try scope.get(restored, "provider")}))) model = restored;
        }
        if (!scope.truthy(model)) {
            const message = try scope.concat(try scope.concat(try scope.concat(try scope.text("Could not restore model "), try scope.stringify(try scope.get(selection, "provider"))), try scope.text("/")), try scope.stringify(try scope.get(selection, "modelId")));
            try scope.put(owner, "modelFallbackMessage", message);
        }
    }
    try scope.put(owner, "model", model);
    if (!scope.truthy(model)) {
        const find = try scope.get(bindings, "findInitialModel");
        const configured = try scope.object();
        try scope.put(configured, "scopedModels", try scope.array());
        try scope.put(configured, "isContinuing", c.pi_js_bool(engine.context, @intFromBool(has_existing)));
        inline for (.{ .{ "defaultProvider", "getDefaultProvider" }, .{ "defaultModelId", "getDefaultModel" }, .{ "defaultThinkingLevel", "getDefaultThinkingLevel" }, .{ "modelThinkingLevels", "getAllModelThinkingLevels" } }) |pair| try scope.put(configured, pair[0], try scope.invoke(settings, pair[1], &.{}));
        try scope.put(configured, "modelRuntime", runtime);
        return flow.wait(continueFactory, engine, owner, try scope.call(find, c.pi_js_undefined(), &.{configured}), @intFromEnum(Stage.initial_model));
    }
    try finishSession(engine, owner);
}
fn isThinkingEntry(context: ?*c.JSContext, _: c.JSValue, argc: c_int, args: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const entry_type = scope.get(if (argc > 0) args[0] else c.pi_js_undefined(), "type") catch |err| return sdk.fail(engine, err);
    const expected = scope.text("thinking_level_change") catch |err| return sdk.fail(engine, err);
    return c.pi_js_bool(context, @intFromBool(scope.equal(entry_type, expected)));
}
fn lookupModel(context: ?*c.JSContext, _: c.JSValue, argc: c_int, args: [*c]c.JSValue, _: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    return js.invoke(engine, roots[0], "getModel", &.{ if (argc > 0) args[0] else c.pi_js_undefined(), if (argc > 1) args[1] else c.pi_js_undefined() }) catch |err| sdk.fail(engine, err);
}
fn defaultThinking(scope: *Scope, bindings: c.JSValue, settings: c.JSValue) !c.JSValue {
    const chosen = try scope.invoke(settings, "getDefaultThinkingLevel", &.{});
    return if (temp.nullish(chosen)) scope.get(bindings, "DEFAULT_THINKING_LEVEL") else chosen;
}
fn finishSession(engine: *em.Engine, owner: c.JSValue) !void {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const bindings = try scope.get(owner, "bindings");
    const options = try scope.get(owner, "options");
    const settings = try scope.get(owner, "settingsManager");
    const manager = try scope.get(owner, "sessionManager");
    const runtime = try scope.get(owner, "modelRuntime");
    const model = try scope.get(owner, "model");
    const has_existing = scope.truthy(try scope.get(owner, "hasExistingSession"));
    const has_thinking = scope.truthy(try scope.get(owner, "hasThinkingEntry"));
    var thinking = try scope.get(options, "thinkingLevel");
    if (c.JS_IsUndefined(thinking) and has_existing) thinking = if (has_thinking) try scope.get(try scope.get(owner, "existingSession"), "thinkingLevel") else try defaultThinking(&scope, bindings, settings);
    if (c.JS_IsUndefined(thinking) and scope.truthy(model)) {
        const get_level = try scope.get(settings, "getModelThinkingLevel");
        const per_model = try scope.call(get_level, settings, &.{ try scope.get(model, "provider"), try scope.get(model, "id") });
        if (scope.truthy(per_model)) thinking = per_model;
    }
    if (c.JS_IsUndefined(thinking)) thinking = try defaultThinking(&scope, bindings, settings);
    thinking = if (!scope.truthy(model)) try scope.text("off") else try imported(&scope, bindings, "clampThinkingLevel", &.{ model, thinking });
    const tool_error = if (scope.truthy(try scope.get(options, "tools"))) try imported(&scope, bindings, "getToolListError", &.{try scope.get(options, "tools")}) else c.pi_js_undefined();
    if (scope.truthy(tool_error)) {
        const ctor = try scope.global("Error");
        var args = [_]c.JSValue{try scope.concat(try scope.text("Invalid tools option: "), tool_error)};
        _ = try engine.checked(c.JS_Throw(engine.context, try engine.checked(c.JS_CallConstructor(engine.context, ctor, args.len, &args))));
        unreachable;
    }
    var defaults = if (scope.truthy(try scope.get(options, "noTools"))) try scope.array() else try scope.invoke(settings, "getDefaultTools", &.{});
    if (temp.nullish(defaults)) defaults = try scope.get(bindings, "DEFAULT_TOOL_NAMES");
    const some_tools = try scope.get(options, "tools");
    const modifiers = if (!temp.nullish(some_tools) and scope.truthy(try scope.invoke(some_tools, "some", &.{try scope.get(bindings, "isToolModifier")}))) try scope.get(options, "tools") else c.pi_js_undefined();
    const selected = if (scope.truthy(modifiers)) try imported(&scope, bindings, "applyToolModifiers", &.{ defaults, modifiers }) else try scope.get(options, "tools");
    const all = try scope.text("all");
    var allowed: c.JSValue = undefined;
    if (scope.truthy(modifiers)) {
        allowed = if (scope.equal(try scope.get(options, "noTools"), all)) selected else c.pi_js_undefined();
    } else {
        allowed = try scope.get(options, "tools");
        if (temp.nullish(allowed)) allowed = if (scope.equal(try scope.get(options, "noTools"), all)) try scope.array() else c.pi_js_undefined();
    }
    const excluded = try scope.get(options, "excludeTools");
    const matcher = if (scope.truthy(excluded)) try imported(&scope, bindings, "createToolNameMatcher", &.{excluded}) else c.pi_js_undefined();
    const initial = if (temp.nullish(selected)) defaults else selected;
    const filter = try scope.get(initial, "filter");
    var captures = [_]c.JSValue{matcher};
    const predicate = try scope.own(try engine.checked(c.JS_NewCFunctionData2(engine.context, activeTool, "", 1, 0, captures.len, &captures)));
    const active = try scope.call(filter, initial, &.{predicate});
    const converter = try scope.own(try @import("native_sdk_block_images.zig").create(engine, settings));
    const runner_ref = try scope.object();
    const agent_box = try scope.object();
    try scope.put(agent_box, "initialized", c.pi_js_bool(engine.context, 0));
    var agent_roots = [_]c.JSValue{agent_box};
    const agent_getter = try scope.own(try engine.checked(c.JS_NewCFunctionData2(engine.context, readAgentBinding, "get value", 0, 0, agent_roots.len, &agent_roots)));
    const agent_atom = c.JS_NewAtom(engine.context, "value");
    defer c.JS_FreeAtom(engine.context, agent_atom);
    if (c.JS_DefinePropertyGetSet(engine.context, agent_box, agent_atom, c.JS_DupValue(engine.context, agent_getter), c.pi_js_undefined(), c.JS_PROP_CONFIGURABLE) < 0) return js.capture(engine);
    // The source lexical warmer binding is assigned after callback creation.
    // The first set is only used for the two callbacks passed into CacheWarmer;
    // the second set captures the constructed warmer for Agent.streamFn.
    const early = try scope.own(try @import("native_sdk_factory_provider_callbacks.zig").create(engine, settings, runtime, manager, runner_ref, agent_box, c.pi_js_undefined()));
    const warmer_bindings = try scope.own(try @import("native_cache_warmer.zig").createBindings(engine));
    var warmer_args = [_]c.JSValue{ runtime, manager, try scope.get(early, "getCacheMode"), try scope.get(early, "decideCacheWarming") };
    const warmer = try scope.own(try engine.checked(c.JS_CallConstructor(engine.context, try scope.get(warmer_bindings, "CacheWarmer"), warmer_args.len, &warmer_args)));
    const callbacks = try scope.own(try @import("native_sdk_factory_provider_callbacks.zig").create(engine, settings, runtime, manager, runner_ref, agent_box, warmer));
    const agent_config = try scope.object();
    const state = try scope.object();
    try scope.put(state, "systemPrompt", try scope.text(""));
    try scope.put(state, "model", model);
    try scope.put(state, "thinkingLevel", thinking);
    try scope.put(state, "tools", try scope.array());
    try scope.put(state, "messages", try scope.get(try scope.get(owner, "existingSession"), "messages"));
    try scope.put(agent_config, "initialState", state);
    try scope.put(agent_config, "convertToLlm", converter);
    inline for (.{ .{ "streamFn", "streamFn" }, .{ "onPayload", "onPayload" }, .{ "onResponse", "onResponse" }, .{ "onProviderStreamEvent", "onProviderStreamEvent" } }) |pair| try scope.put(agent_config, pair[0], try scope.get(callbacks, pair[1]));
    try scope.put(agent_config, "sessionId", try scope.invoke(manager, "getSessionId", &.{}));
    try scope.put(agent_config, "transformContext", try scope.get(callbacks, "transformContext"));
    inline for (.{ .{ "steeringMode", "getSteeringMode" }, .{ "followUpMode", "getFollowUpMode" }, .{ "transport", "getTransport" }, .{ "thinkingBudgets", "getThinkingBudgets" } }) |pair| try scope.put(agent_config, pair[0], try scope.invoke(settings, pair[1], &.{}));
    try scope.put(agent_config, "maxRetryDelayMs", try scope.get(try scope.invoke(settings, "getProviderRetrySettings", &.{}), "maxRetryDelayMs"));
    const agent = try construct(&scope, bindings, "Agent", &.{agent_config});
    try scope.put(agent_box, "binding", agent);
    try scope.put(agent_box, "initialized", c.pi_js_bool(engine.context, 1));
    if (has_existing) {
        if (!has_thinking) _ = try scope.invoke(manager, "appendThinkingLevelChange", &.{thinking});
    } else {
        if (scope.truthy(model)) {
            const append = try scope.get(manager, "appendModelChange");
            _ = try scope.call(append, manager, &.{ try scope.get(model, "provider"), try scope.get(model, "id") });
        }
        _ = try scope.invoke(manager, "appendThinkingLevelChange", &.{thinking});
    }
    const config = try scope.object();
    try scope.put(config, "agent", agent);
    try scope.put(config, "sessionManager", manager);
    try scope.put(config, "settingsManager", settings);
    try scope.put(config, "cwd", try scope.get(owner, "cwd"));
    try scope.put(config, "scopedModels", try scope.get(options, "scopedModels"));
    try scope.put(config, "resourceLoader", try scope.get(owner, "resourceLoader"));
    try scope.put(config, "customTools", try scope.get(options, "customTools"));
    try scope.put(config, "modelRuntime", runtime);
    try scope.put(config, "cacheWarmer", warmer);
    try scope.put(config, "initialActiveToolNames", active);
    const uses_defaults = (c.JS_IsUndefined(try scope.get(options, "tools")) or !c.JS_IsUndefined(modifiers)) and !scope.truthy(try scope.get(options, "noTools"));
    try scope.put(config, "usesDefaultTools", c.pi_js_bool(engine.context, @intFromBool(uses_defaults)));
    try scope.put(config, "defaultToolModifiers", modifiers);
    try scope.put(config, "allowedToolNames", allowed);
    try scope.put(config, "excludedToolNames", excluded);
    try scope.put(config, "extensionRunnerRef", runner_ref);
    try scope.put(config, "sessionStartEvent", try scope.get(options, "sessionStartEvent"));
    const session = try construct(&scope, bindings, "AgentSession", &.{config});
    const extensions = try scope.invoke(try scope.get(owner, "resourceLoader"), "getExtensions", &.{});
    const result = try scope.object();
    try scope.put(result, "session", session);
    try scope.put(result, "extensionsResult", extensions);
    try scope.put(result, "modelFallbackMessage", try scope.get(owner, "modelFallbackMessage"));
    try flow.settle(engine, owner, false, result);
}
fn readAgentBinding(context: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue, _: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    return agentBinding(engine, roots[0]) catch |err| sdk.fail(engine, err);
}
fn agentBinding(engine: *em.Engine, box: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    if (!scope.truthy(try scope.get(box, "initialized"))) {
        const ctor = try scope.global("ReferenceError");
        var args = [_]c.JSValue{try scope.text("Cannot access 'agent' before initialization")};
        _ = try engine.checked(c.JS_Throw(engine.context, try engine.checked(c.JS_CallConstructor(engine.context, ctor, args.len, &args))));
        unreachable;
    }
    return js.get(engine, box, "binding");
}
fn activeTool(context: ?*c.JSContext, _: c.JSValue, argc: c_int, args: [*c]c.JSValue, _: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    if (temp.nullish(roots[0])) return c.pi_js_bool(context, 1);
    const result = js.call(engine, roots[0], c.pi_js_undefined(), &.{if (argc > 0) args[0] else c.pi_js_undefined()}) catch |err| return sdk.fail(engine, err);
    defer engine.freeValue(result);
    return c.pi_js_bool(context, @intFromBool(c.JS_ToBool(context, result) != 1));
}
fn startServices(engine: *em.Engine, owner: c.JSValue) !void {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const bindings = try scope.get(owner, "bindings");
    const options = try scope.get(owner, "options");
    try scope.put(owner, "cwd", try imported(&scope, bindings, "resolvePath", &.{try scope.get(options, "cwd")}));
    const directory = if (scope.truthy(try scope.get(options, "agentDir"))) try imported(&scope, bindings, "resolvePath", &.{try scope.get(options, "agentDir")}) else try imported(&scope, bindings, "getAgentDir", &.{});
    try scope.put(owner, "agentDir", directory);
    const runtime = try scope.get(options, "modelRuntime");
    if (temp.nullish(runtime)) {
        const ctor = try scope.get(bindings, "ModelRuntime");
        const create_method = try scope.get(ctor, "create");
        const configured = try scope.object();
        try scope.put(configured, "authPath", try imported(&scope, bindings, "join", &.{ directory, try scope.text("auth.json") }));
        try scope.put(configured, "modelsPath", try imported(&scope, bindings, "join", &.{ directory, try scope.text("models.json") }));
        try scope.put(configured, "signal", try scope.get(options, "modelRuntimeSignal"));
        return flow.wait(continueFactory, engine, owner, try scope.call(create_method, ctor, &.{configured}), @intFromEnum(Stage.services_runtime));
    }
    try scope.put(owner, "modelRuntime", runtime);
    try servicesLoader(engine, owner);
}
fn servicesLoader(engine: *em.Engine, owner: c.JSValue) !void {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const bindings = try scope.get(owner, "bindings");
    const options = try scope.get(owner, "options");
    const cwd = try scope.get(owner, "cwd");
    const directory = try scope.get(owner, "agentDir");
    var settings = try scope.get(options, "settingsManager");
    if (temp.nullish(settings)) settings = try scope.invoke(try scope.get(bindings, "SettingsManager"), "create", &.{ cwd, directory });
    try scope.put(owner, "settingsManager", settings);
    var supplied = try scope.get(options, "resourceLoaderOptions");
    if (temp.nullish(supplied)) supplied = try scope.object();
    const configured = try scope.own(try js.spread(engine, supplied));
    try scope.put(configured, "cwd", cwd);
    try scope.put(configured, "agentDir", directory);
    try scope.put(configured, "settingsManager", settings);
    const loader = try construct(&scope, bindings, "DefaultResourceLoader", &.{configured});
    try scope.put(owner, "resourceLoader", loader);
    const reload = try scope.get(loader, "reload");
    return flow.wait(continueFactory, engine, owner, try scope.call(reload, loader, &.{try scope.get(options, "resourceLoaderReloadOptions")}), @intFromEnum(Stage.services_reload));
}
fn registerPendingProviders(engine: *em.Engine, owner: c.JSValue) !void {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const diagnostics = try scope.array();
    try scope.put(owner, "diagnostics", diagnostics);
    const extensions = try scope.invoke(try scope.get(owner, "resourceLoader"), "getExtensions", &.{});
    try scope.put(owner, "extensionsResult", extensions);
    const runtime = try scope.get(owner, "modelRuntime");
    inline for (.{ .{ "pendingProviderRegistrations", "registerProvider" }, .{ "pendingNativeProviderRegistrations", "registerNativeProvider" }, .{ "pendingVirtualModelRegistrations", "registerVirtualModel" } }, 0..) |pair, kind| {
        const pending = try scope.get(try scope.get(extensions, "runtime"), pair[0]);
        var iterator = try js.Iterator.init(engine, pending, try scope.own(try engine.checked(c.JS_GetIteratorSymbol(engine.context))));
        defer iterator.deinit();
        errdefer iterator.closePreserving();
        while (try iterator.next()) |row| {
            defer engine.freeValue(row);
            var frame: Scope = .{ .engine = engine };
            defer frame.deinit();
            // The destructuring is outside the catch in Source.
            const first = try frame.get(row, if (kind == 0) "name" else if (kind == 1) "provider" else "definition");
            const config = if (kind == 0) try frame.get(row, "config") else c.pi_js_undefined();
            const path = try frame.get(row, "extensionPath");
            const ignored = js.invoke(engine, runtime, pair[1], if (kind == 0) &.{ first, config } else &.{first}) catch |err| {
                const reason = try frame.own(flow.reason(engine, err));
                const error_ctor = try frame.global("Error");
                const instance = c.JS_IsInstanceOf(engine.context, reason, error_ctor);
                if (instance < 0) return js.capture(engine);
                const message = if (instance == 1) try frame.get(reason, "message") else try frame.call(try frame.global("String"), c.pi_js_undefined(), &.{reason});
                const push = try frame.get(diagnostics, "push");
                const diagnostic = try frame.object();
                try frame.put(diagnostic, "type", try frame.text("error"));
                const text = try frame.concat(try frame.concat(try frame.concat(try frame.text("Extension \""), try frame.stringify(path)), try frame.text("\" error: ")), try frame.stringify(message));
                try frame.put(diagnostic, "message", text);
                _ = try frame.call(push, diagnostics, &.{diagnostic});
                continue;
            };
            engine.freeValue(ignored);
        }
        try scope.set(try scope.get(extensions, "runtime"), pair[0], try scope.array());
    }
    const refresh = try scope.get(runtime, "refresh");
    const configured = try scope.object();
    try scope.put(configured, "allowNetwork", c.pi_js_bool(engine.context, 0));
    return flow.wait(continueFactory, engine, owner, try scope.call(refresh, runtime, &.{configured}), @intFromEnum(Stage.services_refresh));
}
fn finishServices(engine: *em.Engine, owner: c.JSValue) !void {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const diagnostics = try scope.get(owner, "diagnostics");
    const options = try scope.get(owner, "options");
    const push = try scope.get(diagnostics, "push");
    const flags = try scope.own(try @import("native_sdk_factory_flags.zig").apply(engine, try scope.get(owner, "resourceLoader"), try scope.get(options, "extensionFlagValues")));
    const arguments = try scope.own(try @import("native_sdk_transcript_replay.zig").arraySpread(engine, flags, null));
    const length = try sdk.length(engine, arguments);
    var values: @import("std").ArrayList(c.JSValue) = .empty;
    defer values.deinit(engine.gpa);
    try values.ensureTotalCapacity(engine.gpa, length);
    for (0..length) |index| values.appendAssumeCapacity(try scope.own(try engine.checked(c.JS_GetPropertyUint32(engine.context, arguments, @intCast(index)))));
    _ = try scope.call(push, diagnostics, values.items);
    const result = try scope.object();
    inline for (.{ "cwd", "agentDir", "modelRuntime", "settingsManager", "resourceLoader", "diagnostics" }) |name| try scope.put(result, name, try scope.get(owner, name));
    try flow.settle(engine, owner, false, result);
}
