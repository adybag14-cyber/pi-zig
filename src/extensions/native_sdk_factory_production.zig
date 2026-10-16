//! Actual sdk.ts and agent-session-services.ts orchestration over captured,
//! genuine imported bindings. This module never constructs SDK.Kind.agent_session.
//! Production composition supplies the real AI, loader, model/auth and lifecycle
//! classes; dependency validation alone is not a qualification claim.
const em = @import("engine.zig");
const sdk = @import("native_sdk.zig");
const js = @import("native_js_values.zig");
const temp = @import("native_sdk_prompt_scope.zig");
const Scope = temp.Scope;
const body = @import("native_async_body.zig");
const af = body.native;
const c = em.c;
const Operation = enum(c_int) { createAgentSession, createAgentSessionServices, createAgentSessionFromServices, createAgentSessionRuntime };
const Stage = enum(c_int) { runtime, reload, initial_model, services_runtime, services_reload, services_refresh, lifecycle };
const ActionKind = enum(c_int) { returned, awaited };
fn put(engine: *em.Engine, target: c.JSValue, name: [*:0]const u8, borrowed: c.JSValue) !void {
    if (c.JS_DefinePropertyValueStr(engine.context, target, name, c.JS_DupValue(engine.context, borrowed), c.JS_PROP_C_W_E) < 0) return js.capture(engine);
}
fn wait(engine: *em.Engine, owner: c.JSValue, value: c.JSValue, stage: Stage) !void {
    try put(engine, owner, "factoryStage", c.JS_NewInt32(engine.context, @intFromEnum(stage)));
    try put(engine, owner, "factoryValue", value);
    try put(engine, owner, "factoryAction", c.JS_NewInt32(engine.context, @intFromEnum(ActionKind.awaited)));
}
fn resolve(engine: *em.Engine, owner: c.JSValue, value: c.JSValue) !void {
    try put(engine, owner, "factoryValue", value);
    try put(engine, owner, "factoryAction", c.JS_NewInt32(engine.context, @intFromEnum(ActionKind.returned)));
}
fn trustedBoundary(engine: *em.Engine, err: anyerror, generation: u64) !void {
    if (err == error.OutOfMemory) return err;
    if (err == error.JavaScriptException) if (engine.captured_exception) |reason| {
        if (c.JS_IsUncatchableError(reason)) return err;
        try body.rethrowRecognizedAllocation(engine, reason, generation);
    };
}
fn currentFailure(engine: *em.Engine, err: anyerror, generation: u64) anyerror {
    if (err == error.JavaScriptException) if (engine.captured_exception) |reason| {
        if (c.JS_IsUncatchableError(reason)) return err;
        body.rethrowRecognizedAllocation(engine, reason, generation) catch |fatal| return fatal;
    };
    if (err == error.JavaScriptException and c.JS_HasException(engine.context)) {
        const reason = c.JS_GetException(engine.context);
        _ = engine.checked(c.JS_Throw(engine.context, reason)) catch |current| return current;
        unreachable;
    }
    return err;
}
fn takeReason(engine: *em.Engine, err: anyerror, generation: u64) !c.JSValue {
    const current = currentFailure(engine, err, generation);
    try trustedBoundary(engine, current, generation);
    if (current != error.JavaScriptException) return current;
    const reason = engine.captured_exception orelse return error.MissingFactoryCapturedReason;
    engine.captured_exception = null;
    return reason;
}

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
        try put(scope.engine, bindings, name, value);
    }
    if (!c.JS_IsConstructor(engine.context, ordinary)) return error.RequiredOrdinaryAgentSessionConstructor;
    try put(scope.engine, bindings, "AgentSession", ordinary);
    try put(scope.engine, bindings, "process", try scope.get(imports, "process"));
    try put(scope.engine, bindings, "DEFAULT_THINKING_LEVEL", try scope.get(imports, "DEFAULT_THINKING_LEVEL"));
    try put(scope.engine, bindings, "DEFAULT_TOOL_NAMES", try scope.get(imports, "DEFAULT_TOOL_NAMES"));
    // Source SDK module preserves agent-core's pre-0.81 low-level fallback by
    // setting its actual shared default to the actual compat dispatch once.
    _ = try imported(&scope, bindings, "setDefaultStreamFn", &.{try scope.get(bindings, "streamSimple")});
    const result = try scope.object();
    inline for (@typeInfo(Operation).@"enum".fields) |field| {
        const function = try scope.own(try af.createResumable(engine, field.name, if (field.value == @intFromEnum(Operation.createAgentSession)) 0 else if (field.value == @intFromEnum(Operation.createAgentSessionRuntime)) 2 else 1, factoryBody, &.{bindings, c.JS_NewInt32(engine.context, field.value)}));
        try put(scope.engine, result, field.name, function);
        // Source's services module captures the original SDK function binding.
        if (comptime field.value == @intFromEnum(Operation.createAgentSession)) try put(scope.engine, bindings, "createAgentSession", function);
    }
    try put(scope.engine, result, "AgentSession", ordinary);
    return c.JS_DupValue(engine.context, result);
}
fn factoryBody(engine: *em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue, state: *c.JSValue, completion: af.Completion, input: c.JSValue) !af.Action {
    const generation = engine.native_allocation_generation;
    return factoryInner(engine, args, roots, state, completion, input) catch |err| {
        const current = currentFailure(engine, err, generation);
        try trustedBoundary(engine, current, generation);
        if (current == error.JavaScriptException) {
            const reason = engine.captured_exception orelse return error.MissingFactoryCapturedReason;
            engine.captured_exception = null;
            return .{ .thrown = reason };
        }
        return body.failureSince(engine, current, generation);
    };
}
fn factoryInner(engine: *em.Engine, args: []const c.JSValue, roots: []const c.JSValue, state: *c.JSValue, completion: af.Completion, input: c.JSValue) !af.Action {
    var scope: Scope = .{ .engine = engine }; defer scope.deinit();
    if (completion == .start) {
        const owner = try scope.own(try engine.checked(c.JS_NewObjectProto(engine.context, c.JS_NULL)));
        af.replaceState(engine, state, c.JS_DupValue(engine.context, owner));
        try put(engine, owner, "generation", try scope.own(try engine.checked(c.JS_NewBigUint64(engine.context, engine.native_allocation_generation))));
        var raw: i32 = 0;
        if (c.JS_ToInt32(engine.context, &raw, roots[1]) < 0) return js.capture(engine);
        try start(engine, owner, roots[0], @enumFromInt(raw), if (args.len > 0) args[0] else c.pi_js_undefined(), if (args.len > 1) args[1] else c.pi_js_undefined());
    } else {
        const owner = state.*;
        // The primitive owns input during this call; release the old Await
        // expression before resuming Source lexical work.
        try put(engine, owner, "factoryValue", c.pi_js_undefined());
        if (completion == .rejected) {
            if (c.JS_IsUncatchableError(input)) {
                _ = try engine.checked(c.JS_Throw(engine.context, c.JS_DupValue(engine.context, input)));
                unreachable;
            }
            var boundary: u64 = 0;
            if (c.JS_ToBigUint64(engine.context, &boundary, try scope.get(owner, "generation")) < 0) return js.capture(engine);
            try body.rethrowRecognizedAllocation(engine, input, boundary);
            return .{ .thrown = c.JS_DupValue(engine.context, input) };
        }
        var raw: i32 = 0;
        if (c.JS_ToInt32(engine.context, &raw, try scope.get(owner, "factoryStage")) < 0) return js.capture(engine);
        try resumeBody(engine, owner, input, @enumFromInt(raw));
    }
    var raw: i32 = 0;
    if (c.JS_ToInt32(engine.context, &raw, try scope.get(state.*, "factoryAction")) < 0) return js.capture(engine);
    const value = c.JS_DupValue(engine.context, try scope.get(state.*, "factoryValue"));
    return switch (@as(ActionKind, @enumFromInt(raw))) { .returned => .{ .returned = value }, .awaited => .{ .awaited = value } };
}
fn imported(scope: *Scope, bindings: c.JSValue, name: [*:0]const u8, args: []const c.JSValue) !c.JSValue {
    return scope.call(try scope.get(bindings, name), c.pi_js_undefined(), args);
}
fn construct(scope: *Scope, bindings: c.JSValue, name: [*:0]const u8, args: []const c.JSValue) !c.JSValue {
    return scope.own(try scope.engine.checked(c.JS_CallConstructor(scope.engine.context, try scope.get(bindings, name), @intCast(args.len), @constCast(args.ptr))));
}
fn start(engine: *em.Engine, owner: c.JSValue, bindings: c.JSValue, operation: Operation, first: c.JSValue, second: c.JSValue) !void {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    try put(scope.engine, owner, "bindings", bindings);
    switch (operation) {
        .createAgentSession => {
            const options = if (c.JS_IsUndefined(first)) try scope.object() else first;
            try put(scope.engine, owner, "options", options);
            try startSession(engine, owner);
        },
        .createAgentSessionServices => {
            try put(scope.engine, owner, "options", first);
            try startServices(engine, owner);
        },
        .createAgentSessionFromServices => {
            const inner_function = try scope.get(bindings, "createAgentSession");
            const options = try scope.object();
            // Source evaluates options.services independently for each field.
            inline for (.{ "cwd", "agentDir", "modelRuntime", "settingsManager", "resourceLoader" }) |name| try put(scope.engine, options, name, try scope.get(try scope.get(first, "services"), name));
            inline for (.{ "sessionManager", "model", "thinkingLevel", "scopedModels", "tools", "excludeTools", "noTools", "customTools", "sessionStartEvent" }) |name| try put(scope.engine, options, name, try scope.get(first, name));
            // Source returns the inner async call from a separate async body.
            // Keep both promises and the adoption job, including synchronous
            // options-getter rejection of this outer call before the inner call.
            const inner = try scope.call(inner_function, c.pi_js_undefined(), &.{options});
            return resolve(engine, owner, inner);
        },
        .createAgentSessionRuntime => {
            const assert_cwd = try scope.get(bindings, "assertSessionCwdExists");
            _ = try scope.call(assert_cwd, c.pi_js_undefined(), &.{ try scope.get(second, "sessionManager"), try scope.get(second, "cwd") });
            try put(scope.engine, owner, "createRuntime", first);
            return wait(engine, owner, try scope.call(first, c.pi_js_undefined(), &.{second}), .lifecycle);
        },
    }
}
fn resumeBody(engine: *em.Engine, owner: c.JSValue, value: c.JSValue, stage: Stage) !void {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    switch (stage) {
        .runtime => {
            try put(scope.engine, owner, "modelRuntime", value);
            try sessionServices(engine, owner);
        },
        .reload => {
            _ = try imported(&scope, try scope.get(owner, "bindings"), "time", &.{try scope.text("resourceLoader.reload")});
            try restoreSession(engine, owner);
        },
        .initial_model => {
            const bindings = try scope.get(owner, "bindings");
            const model = try scope.get(value, "model");
            try put(scope.engine, owner, "model", model);
            if (!scope.truthy(model)) {
                try put(scope.engine, owner, "modelFallbackMessage", try imported(&scope, bindings, "formatNoModelsAvailableMessage", &.{}));
            } else if (scope.truthy(try scope.get(owner, "modelFallbackMessage"))) {
                const suffix = try scope.concat(try scope.concat(try scope.concat(try scope.text(". Using "), try scope.stringify(try scope.get(model, "provider"))), try scope.text("/")), try scope.stringify(try scope.get(model, "id")));
                try put(scope.engine, owner, "modelFallbackMessage", try scope.concat(try scope.get(owner, "modelFallbackMessage"), suffix));
            }
            try finishSession(engine, owner);
        },
        .services_runtime => {
            try put(scope.engine, owner, "modelRuntime", value);
            try servicesLoader(engine, owner);
        },
        .services_reload => try registerPendingProviders(engine, owner),
        .services_refresh => try finishServices(engine, owner),
        .lifecycle => {
            const constructor = try scope.get(try scope.get(owner, "bindings"), "AgentSessionRuntime");
            const arguments = [_]c.JSValue{ try scope.get(value, "session"), try scope.get(value, "services"), try scope.get(owner, "createRuntime"), try scope.get(value, "diagnostics"), try scope.get(value, "modelFallbackMessage") };
            const target = try scope.own(try engine.checked(c.JS_CallConstructor(engine.context, constructor, arguments.len, @constCast(&arguments))));
            try resolve(engine, owner, target);
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
    try put(scope.engine, owner, "cwd", try imported(&scope, bindings, "resolvePath", &.{work}));
    const directory = if (scope.truthy(try scope.get(options, "agentDir"))) try imported(&scope, bindings, "resolvePath", &.{try scope.get(options, "agentDir")}) else try imported(&scope, bindings, "getAgentDir", &.{});
    try put(scope.engine, owner, "agentDir", directory);
    try put(scope.engine, owner, "resourceLoader", try scope.get(options, "resourceLoader"));
    const auth_path = if (scope.truthy(try scope.get(options, "agentDir"))) try imported(&scope, bindings, "join", &.{ directory, try scope.text("auth.json") }) else c.pi_js_undefined();
    const models_path = if (scope.truthy(try scope.get(options, "agentDir"))) try imported(&scope, bindings, "join", &.{ directory, try scope.text("models.json") }) else c.pi_js_undefined();
    const runtime = try scope.get(options, "modelRuntime");
    if (temp.nullish(runtime)) {
        const constructor = try scope.get(bindings, "ModelRuntime");
        const create_method = try scope.get(constructor, "create");
        const configured = try scope.object();
        try put(scope.engine, configured, "authPath", auth_path);
        try put(scope.engine, configured, "modelsPath", models_path);
        return wait(engine, owner, try scope.call(create_method, constructor, &.{configured}), .runtime);
    }
    try put(scope.engine, owner, "modelRuntime", runtime);
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
    try put(scope.engine, owner, "settingsManager", settings);
    var manager = try scope.get(options, "sessionManager");
    if (temp.nullish(manager)) {
        // Preserve lookup of SessionManager.create before evaluating its arguments.
        const ctor = try scope.get(bindings, "SessionManager");
        const create_method = try scope.get(ctor, "create");
        manager = try scope.call(create_method, ctor, &.{ cwd, try imported(&scope, bindings, "getDefaultSessionDir", &.{ cwd, directory }) });
    }
    try put(scope.engine, owner, "sessionManager", manager);
    if (!scope.truthy(try scope.get(owner, "resourceLoader"))) {
        const configured = try scope.object();
        try put(scope.engine, configured, "cwd", cwd);
        try put(scope.engine, configured, "agentDir", directory);
        try put(scope.engine, configured, "settingsManager", settings);
        const loader = try construct(&scope, bindings, "DefaultResourceLoader", &.{configured});
        try put(scope.engine, owner, "resourceLoader", loader);
        return wait(engine, owner, try scope.invoke(loader, "reload", &.{}), .reload);
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
    try put(scope.engine, owner, "existingSession", existing);
    const has_existing = try scope.positive(try scope.get(try scope.get(existing, "messages"), "length"));
    try put(scope.engine, owner, "hasExistingSession", c.pi_js_bool(engine.context, @intFromBool(has_existing)));
    const branch = try scope.invoke(manager, "getBranch", &.{});
    const some = try scope.get(branch, "some");
    const predicate = try scope.own(try engine.checked(c.JS_NewCFunction(engine.context, isThinkingEntry, "", 1)));
    try put(scope.engine, owner, "hasThinkingEntry", try scope.call(some, branch, &.{predicate}));
    var model = try scope.get(options, "model");
    try put(scope.engine, owner, "modelFallbackMessage", c.pi_js_undefined());
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
            try put(scope.engine, owner, "modelFallbackMessage", message);
        }
    }
    try put(scope.engine, owner, "model", model);
    if (!scope.truthy(model)) {
        const find = try scope.get(bindings, "findInitialModel");
        const configured = try scope.object();
        try put(scope.engine, configured, "scopedModels", try scope.array());
        try put(scope.engine, configured, "isContinuing", c.pi_js_bool(engine.context, @intFromBool(has_existing)));
        inline for (.{ .{ "defaultProvider", "getDefaultProvider" }, .{ "defaultModelId", "getDefaultModel" }, .{ "defaultThinkingLevel", "getDefaultThinkingLevel" }, .{ "modelThinkingLevels", "getAllModelThinkingLevels" } }) |pair| try put(scope.engine, configured, pair[0], try scope.invoke(settings, pair[1], &.{}));
        try put(scope.engine, configured, "modelRuntime", runtime);
        return wait(engine, owner, try scope.call(find, c.pi_js_undefined(), &.{configured}), .initial_model);
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
    try put(scope.engine, agent_box, "initialized", c.pi_js_bool(engine.context, 0));
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
    try put(scope.engine, state, "systemPrompt", try scope.text(""));
    try put(scope.engine, state, "model", model);
    try put(scope.engine, state, "thinkingLevel", thinking);
    try put(scope.engine, state, "tools", try scope.array());
    try put(scope.engine, state, "messages", try scope.get(try scope.get(owner, "existingSession"), "messages"));
    try put(scope.engine, agent_config, "initialState", state);
    try put(scope.engine, agent_config, "convertToLlm", converter);
    inline for (.{ .{ "streamFn", "streamFn" }, .{ "onPayload", "onPayload" }, .{ "onResponse", "onResponse" }, .{ "onProviderStreamEvent", "onProviderStreamEvent" } }) |pair| try put(scope.engine, agent_config, pair[0], try scope.get(callbacks, pair[1]));
    try put(scope.engine, agent_config, "sessionId", try scope.invoke(manager, "getSessionId", &.{}));
    try put(scope.engine, agent_config, "transformContext", try scope.get(callbacks, "transformContext"));
    inline for (.{ .{ "steeringMode", "getSteeringMode" }, .{ "followUpMode", "getFollowUpMode" }, .{ "transport", "getTransport" }, .{ "thinkingBudgets", "getThinkingBudgets" } }) |pair| try put(scope.engine, agent_config, pair[0], try scope.invoke(settings, pair[1], &.{}));
    try put(scope.engine, agent_config, "maxRetryDelayMs", try scope.get(try scope.invoke(settings, "getProviderRetrySettings", &.{}), "maxRetryDelayMs"));
    const agent = try construct(&scope, bindings, "Agent", &.{agent_config});
    try put(scope.engine, agent_box, "binding", agent);
    try put(scope.engine, agent_box, "initialized", c.pi_js_bool(engine.context, 1));
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
    try put(scope.engine, config, "agent", agent);
    try put(scope.engine, config, "sessionManager", manager);
    try put(scope.engine, config, "settingsManager", settings);
    try put(scope.engine, config, "cwd", try scope.get(owner, "cwd"));
    try put(scope.engine, config, "scopedModels", try scope.get(options, "scopedModels"));
    try put(scope.engine, config, "resourceLoader", try scope.get(owner, "resourceLoader"));
    try put(scope.engine, config, "customTools", try scope.get(options, "customTools"));
    try put(scope.engine, config, "modelRuntime", runtime);
    try put(scope.engine, config, "cacheWarmer", warmer);
    try put(scope.engine, config, "initialActiveToolNames", active);
    const uses_defaults = (c.JS_IsUndefined(try scope.get(options, "tools")) or !c.JS_IsUndefined(modifiers)) and !scope.truthy(try scope.get(options, "noTools"));
    try put(scope.engine, config, "usesDefaultTools", c.pi_js_bool(engine.context, @intFromBool(uses_defaults)));
    try put(scope.engine, config, "defaultToolModifiers", modifiers);
    try put(scope.engine, config, "allowedToolNames", allowed);
    try put(scope.engine, config, "excludedToolNames", excluded);
    try put(scope.engine, config, "extensionRunnerRef", runner_ref);
    try put(scope.engine, config, "sessionStartEvent", try scope.get(options, "sessionStartEvent"));
    const session = try construct(&scope, bindings, "AgentSession", &.{config});
    const extensions = try scope.invoke(try scope.get(owner, "resourceLoader"), "getExtensions", &.{});
    const result = try scope.object();
    try put(scope.engine, result, "session", session);
    try put(scope.engine, result, "extensionsResult", extensions);
    try put(scope.engine, result, "modelFallbackMessage", try scope.get(owner, "modelFallbackMessage"));
    try resolve(engine, owner, result);
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
    try put(scope.engine, owner, "cwd", try imported(&scope, bindings, "resolvePath", &.{try scope.get(options, "cwd")}));
    const directory = if (scope.truthy(try scope.get(options, "agentDir"))) try imported(&scope, bindings, "resolvePath", &.{try scope.get(options, "agentDir")}) else try imported(&scope, bindings, "getAgentDir", &.{});
    try put(scope.engine, owner, "agentDir", directory);
    const runtime = try scope.get(options, "modelRuntime");
    if (temp.nullish(runtime)) {
        const ctor = try scope.get(bindings, "ModelRuntime");
        const create_method = try scope.get(ctor, "create");
        const configured = try scope.object();
        try put(scope.engine, configured, "authPath", try imported(&scope, bindings, "join", &.{ directory, try scope.text("auth.json") }));
        try put(scope.engine, configured, "modelsPath", try imported(&scope, bindings, "join", &.{ directory, try scope.text("models.json") }));
        try put(scope.engine, configured, "signal", try scope.get(options, "modelRuntimeSignal"));
        return wait(engine, owner, try scope.call(create_method, ctor, &.{configured}), .services_runtime);
    }
    try put(scope.engine, owner, "modelRuntime", runtime);
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
    try put(scope.engine, owner, "settingsManager", settings);
    var supplied = try scope.get(options, "resourceLoaderOptions");
    if (temp.nullish(supplied)) supplied = try scope.object();
    const configured = try scope.own(try js.spread(engine, supplied));
    try put(scope.engine, configured, "cwd", cwd);
    try put(scope.engine, configured, "agentDir", directory);
    try put(scope.engine, configured, "settingsManager", settings);
    const loader = try construct(&scope, bindings, "DefaultResourceLoader", &.{configured});
    try put(scope.engine, owner, "resourceLoader", loader);
    const reload = try scope.get(loader, "reload");
    return wait(engine, owner, try scope.call(reload, loader, &.{try scope.get(options, "resourceLoaderReloadOptions")}), .services_reload);
}
fn registerPendingProviders(engine: *em.Engine, owner: c.JSValue) !void {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const diagnostics = try scope.array();
    try put(scope.engine, owner, "diagnostics", diagnostics);
    const extensions = try scope.invoke(try scope.get(owner, "resourceLoader"), "getExtensions", &.{});
    try put(scope.engine, owner, "extensionsResult", extensions);
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
            const generation = engine.native_allocation_generation;
            const ignored = js.invoke(engine, runtime, pair[1], if (kind == 0) &.{ first, config } else &.{first}) catch |err| {
                const reason = try frame.own(try takeReason(engine, err, generation));
                const error_ctor = try frame.global("Error");
                const instance = c.JS_IsInstanceOf(engine.context, reason, error_ctor);
                if (instance < 0) return js.capture(engine);
                const message = if (instance == 1) try frame.get(reason, "message") else try frame.call(try frame.global("String"), c.pi_js_undefined(), &.{reason});
                const push = try frame.get(diagnostics, "push");
                const diagnostic = try frame.object();
                try put(frame.engine, diagnostic, "type", try frame.text("error"));
                const text = try frame.concat(try frame.concat(try frame.concat(try frame.text("Extension \""), try frame.stringify(path)), try frame.text("\" error: ")), try frame.stringify(message));
                try put(frame.engine, diagnostic, "message", text);
                _ = try frame.call(push, diagnostics, &.{diagnostic});
                continue;
            };
            engine.freeValue(ignored);
        }
        try scope.set(try scope.get(extensions, "runtime"), pair[0], try scope.array());
    }
    const refresh = try scope.get(runtime, "refresh");
    const configured = try scope.object();
    try put(scope.engine, configured, "allowNetwork", c.pi_js_bool(engine.context, 0));
    return wait(engine, owner, try scope.call(refresh, runtime, &.{configured}), .services_refresh);
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
    inline for (.{ "cwd", "agentDir", "modelRuntime", "settingsManager", "resourceLoader", "diagnostics" }) |name| try put(scope.engine, result, name, try scope.get(owner, name));
    try resolve(engine, owner, result);
}
