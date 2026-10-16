//! Actual latest ModelRuntime.create orchestration. The genuine runtime class,
//! credentials/config/stores/catalog and provider wrappers are required imports.
//! This module does not synthesize builtin providers from plain catalog rows.
const em = @import("engine.zig");
const sdk = @import("native_sdk.zig");
const js = @import("native_js_values.zig");
const temp = @import("native_sdk_prompt_scope.zig");
const Scope = @import("native_models_stream_scope.zig").Scope;
const flow = @import("native_sdk_async_actions.zig");
const c = em.c;
const Stage = enum(c_int) { config, refreshed };
pub const required_functions = .{ "RuntimeCredentials", "DefaultAuthStorage", "ModelConfig", "FileModelsStore", "InMemoryCodingAgentModelsStore", "withPersonalizedCatalog", "personalizeOpenRouterCatalog", "withRemoteCatalog", "join", "dirname", "getAgentDir" };

/// Install only on the actual completed ModelRuntime class. Function/type
/// checks verify wiring prerequisites, not the supplied class's provenance.
pub fn install(engine: *em.Engine, runtime_class: c.JSValue, imports: c.JSValue) !void {
    if (!c.JS_IsConstructor(engine.context, runtime_class)) return error.RequiredActualModelRuntimeConstructor;
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const bindings = try scope.object();
    inline for (required_functions) |name| {
        const value = try scope.get(imports, name);
        if (!c.JS_IsFunction(engine.context, value)) return error.RequiredActualModelRuntimeCreateImport;
        try scope.put(bindings, name, value);
    }
    const catalog = try scope.get(imports, "builtinProviderCatalog");
    inline for (.{ "getBuiltinModelDataGeneratedAt", "builtinProviders" }) |name| if (!c.JS_IsFunction(engine.context, try scope.get(catalog, name))) return error.RequiredActualModelRuntimeBuiltinProviders;
    try scope.put(bindings, "builtinProviderCatalog", catalog);
    try scope.put(bindings, "process", try scope.get(imports, "process"));
    try scope.put(bindings, "ModelRuntime", runtime_class);
    const function = try scope.own(try flow.native.createResumable(engine, "create", 0, createBody, &.{bindings}));
    if (c.JS_DefinePropertyValueStr(engine.context, runtime_class, "create", c.JS_DupValue(engine.context, function), c.JS_PROP_CONFIGURABLE | c.JS_PROP_WRITABLE) < 0) return js.capture(engine);
}
fn imported(scope: *Scope, bindings: c.JSValue, name: [*:0]const u8, args: []const c.JSValue) !c.JSValue {
    return scope.call(try scope.get(bindings, name), c.pi_js_undefined(), args);
}
fn construct(scope: *Scope, bindings: c.JSValue, name: [*:0]const u8, args: []const c.JSValue) !c.JSValue {
    return scope.own(try scope.engine.checked(c.JS_CallConstructor(scope.engine.context, try scope.get(bindings, name), @intCast(args.len), @constCast(args.ptr))));
}
fn createBody(engine: *em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue, state: *c.JSValue, completion: flow.native.Completion, input: c.JSValue) !flow.native.Action {
    var scope: Scope = .{ .engine = engine }; defer scope.deinit();
    if (completion == .rejected and try flow.nativeAllocationReason(engine, state.*, input)) {
        finish(engine, state.*, true, input) catch {};
        return error.OutOfMemory;
    }
    if (completion == .start) {
        const owner = try flow.init(&scope, state);
        start(engine, owner, roots[0], if (args.len > 0) args[0] else c.pi_js_undefined()) catch |err| try fail(engine, owner, err);
    } else continueCreate(engine, state.*, input, completion == .rejected, try flow.body.stage(&scope, state.*)) catch |err| try flow.rejectError(engine, state.*, err);
    return flow.body.action(&scope, state.*);
}
fn start(engine: *em.Engine, owner: c.JSValue, bindings: c.JSValue, supplied: c.JSValue) !void {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    try scope.put(owner, "finallyActive", c.pi_js_bool(engine.context, 0));
    const options = if (c.JS_IsUndefined(supplied)) try scope.object() else supplied;
    try scope.put(owner, "options", options);
    try scope.put(owner, "bindings", bindings);
    var credentials = try scope.get(options, "credentials");
    if (temp.nullish(credentials)) {
        const storage = try scope.get(bindings, "DefaultAuthStorage");
        const create = try scope.get(storage, "create");
        credentials = try scope.call(create, storage, &.{try scope.get(options, "authPath")});
    }
    try scope.put(owner, "credentials", try construct(&scope, bindings, "RuntimeCredentials", &.{credentials}));
    var models_path = try scope.get(options, "modelsPath");
    if (c.JS_IsNull(models_path)) {
        models_path = c.pi_js_undefined();
    } else {
        models_path = try scope.get(options, "modelsPath");
        if (temp.nullish(models_path)) models_path = try imported(&scope, bindings, "join", &.{ try imported(&scope, bindings, "getAgentDir", &.{}), try scope.text("models.json") });
    }
    try scope.put(owner, "modelsPath", models_path);
    const config = try scope.get(bindings, "ModelConfig");
    return flow.wait(continueCreate, engine, owner, try scope.invoke(config, "load", &.{models_path}), @intFromEnum(Stage.config));
}
fn continueCreate(engine: *em.Engine, owner: c.JSValue, value: c.JSValue, rejected: bool, stage: c_int) !void {
    if (rejected) return finish(engine, owner, true, value);
    switch (@as(Stage, @enumFromInt(stage))) {
        .config => afterConfig(engine, owner, value) catch |err| try fail(engine, owner, err),
        .refreshed => {
            const runtime = try sdk.get(engine, owner, "runtime");
            defer engine.freeValue(runtime);
            try finish(engine, owner, false, runtime);
        },
    }
}
fn afterConfig(engine: *em.Engine, owner: c.JSValue, config: c.JSValue) !void {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const bindings = try scope.get(owner, "bindings");
    const options = try scope.get(owner, "options");
    const path = try scope.get(owner, "modelsPath");
    var store = try scope.get(options, "modelsStore");
    if (temp.nullish(store)) {
        if (scope.truthy(path)) {
            var store_path = try scope.get(options, "modelsStorePath");
            if (temp.nullish(store_path)) store_path = try imported(&scope, bindings, "join", &.{ try imported(&scope, bindings, "dirname", &.{path}), try scope.text("models-store.json") });
            store = try construct(&scope, bindings, "FileModelsStore", &.{store_path});
        } else store = try construct(&scope, bindings, "InMemoryCodingAgentModelsStore", &.{});
    }
    const catalog = try scope.get(bindings, "builtinProviderCatalog");
    const generated_at = try scope.invoke(catalog, "getBuiltinModelDataGeneratedAt", &.{});
    const builtins = try scope.invoke(catalog, "builtinProviders", &.{});
    const map = try scope.get(builtins, "map");
    var roots = [_]c.JSValue{ bindings, options, generated_at };
    const wrap = try scope.own(try engine.checked(c.JS_NewCFunctionData2(engine.context, wrapProvider, "", 1, 0, roots.len, &roots)));
    const providers = try scope.call(map, builtins, &.{wrap});
    const offline = try scope.get(try scope.get(try scope.get(bindings, "process"), "env"), "PI_OFFLINE");
    const runtime = try construct(&scope, bindings, "ModelRuntime", &.{ try scope.get(owner, "credentials"), config, path, store, providers, c.pi_js_bool(engine.context, @intFromBool(c.JS_IsUndefined(offline))) });
    try scope.put(owner, "runtime", runtime);
    _ = try scope.invoke(runtime, "configureRadiusProviders", &.{});
    _ = try scope.invoke(runtime, "rebuildProviders", &.{});
    const network_enabled = try scope.get(runtime, "modelNetworkEnabled");
    const refresh_network = if (scope.truthy(network_enabled)) c.pi_js_bool(engine.context, @intFromBool(scope.equal(try scope.get(options, "allowModelNetwork"), c.pi_js_bool(engine.context, 1)))) else network_enabled;
    var controller = c.pi_js_undefined();
    if (scope.truthy(refresh_network) and !c.JS_IsUndefined(try scope.get(options, "modelRefreshTimeoutMs"))) controller = try scope.own(try js.builtin(engine, "AbortController", &.{}));
    var timeout = c.pi_js_undefined();
    if (scope.truthy(controller)) {
        const set_timeout = try scope.global("setTimeout");
        var controller_roots = [_]c.JSValue{controller};
        const abort = try scope.own(try engine.checked(c.JS_NewCFunctionData2(engine.context, abortRefresh, "", 0, 0, controller_roots.len, &controller_roots)));
        timeout = try scope.call(set_timeout, c.pi_js_undefined(), &.{ abort, try scope.get(options, "modelRefreshTimeoutMs") });
    }
    try scope.put(owner, "timeout", timeout);
    var signal: c.JSValue = undefined;
    if (scope.truthy(controller)) {
        if (scope.truthy(try scope.get(options, "signal"))) {
            const abort_signal = try scope.global("AbortSignal");
            const any = try scope.get(abort_signal, "any");
            const signals = try scope.array();
            try scope.index(signals, 0, try scope.get(options, "signal"));
            try scope.index(signals, 1, try scope.get(controller, "signal"));
            signal = try scope.call(any, abort_signal, &.{signals});
        } else signal = try scope.get(controller, "signal");
    } else signal = try scope.get(options, "signal");
    // Source enters try only after signal creation. Earlier failure does not
    // invent a finally/timeout cleanup which Source itself would not execute.
    try scope.put(owner, "finallyActive", c.pi_js_bool(engine.context, 1));
    if (!scope.equal(try scope.get(options, "refreshOnCreate"), c.pi_js_bool(engine.context, 0))) {
        const refresh = try scope.get(runtime, "refresh");
        const configured = try scope.object();
        try scope.put(configured, "allowNetwork", refresh_network);
        try scope.put(configured, "signal", signal);
        return flow.wait(continueCreate, engine, owner, try scope.call(refresh, runtime, &.{configured}), @intFromEnum(Stage.refreshed));
    }
    try finish(engine, owner, false, runtime);
}
fn wrapProvider(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    return wrapped(engine, if (argc > 0) argv[0] else c.pi_js_undefined(), roots[0], roots[1], roots[2]) catch |err| sdk.fail(engine, err);
}
fn wrapped(engine: *em.Engine, provider: c.JSValue, bindings: c.JSValue, options: c.JSValue, generated_at: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    if (scope.equal(try scope.get(provider, "id"), try scope.text("radius"))) return c.JS_DupValue(engine.context, provider);
    if (scope.equal(try scope.get(provider, "id"), try scope.text("openrouter"))) return c.JS_DupValue(engine.context, try imported(&scope, bindings, "withPersonalizedCatalog", &.{ provider, try scope.get(bindings, "personalizeOpenRouterCatalog"), try scope.get(options, "catalogBaseUrl"), generated_at }));
    return c.JS_DupValue(engine.context, try imported(&scope, bindings, "withRemoteCatalog", &.{ provider, try scope.get(options, "catalogBaseUrl"), generated_at }));
}
fn abortRefresh(context: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue, _: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    return js.invoke(engine, roots[0], "abort", &.{}) catch |err| sdk.fail(engine, err);
}
fn finish(engine: *em.Engine, owner: c.JSValue, rejected: bool, value: c.JSValue) !void {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    if (scope.truthy(try scope.get(owner, "finallyActive"))) {
        try scope.put(owner, "finallyActive", c.pi_js_bool(engine.context, 0));
        const timeout = try scope.get(owner, "timeout");
        if (scope.truthy(timeout)) _ = try scope.call(try scope.global("clearTimeout"), c.pi_js_undefined(), &.{timeout});
    }
    try flow.settle(engine, owner, rejected, value);
}
fn fail(engine: *em.Engine, owner: c.JSValue, err: anyerror) !void {
    const native_failure = try flow.nativeFailure(engine, owner, err);
    const reason = flow.reason(engine, err);
    defer engine.freeValue(reason);
    finish(engine, owner, true, reason) catch |failure| try flow.rejectError(engine, owner, failure);
    if (native_failure) return error.OutOfMemory;
}
