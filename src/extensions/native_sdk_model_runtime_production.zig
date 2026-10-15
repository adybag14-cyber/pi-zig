//! Ordinary latest4954 ModelRuntime. The application supplies actual imported
//! namespaces; this class never seeds builtins, creates SDK.State, blocks the
//! VM on awaitValue, or invents missing collaborator behavior. Static create()
//! is installed separately on this exact constructor by its orchestration owner.
const std = @import("std");
const em = @import("engine.zig");
const sdk = @import("native_sdk.zig");
const js = @import("native_js_values.zig");
const temp = @import("native_sdk_prompt_scope.zig");
const Scope = temp.Scope;
const flow = @import("native_agent_async.zig");
const c = em.c;

pub const source_head = "4954d760504c11df9b2cbdc040346107b6a8153d";
pub const required_functions = .{ "createModels", "ModelsError", "lazyStream", "normalizeContext", "clampThinkingLevel", "assertChatModel", "assertImageModel", "assertClassifierModel", "assertClassifierInputSupported", "imageErrorResult", "classifierErrorResult", "composeModelProvider", "configuredRequestAuthStatus", "resolveCompatibilityRequestConfig", "resolveConfiguredModelHeaders", "validateExtensionProvider", "createVirtualModel", "withVirtualModels", "isVirtualModel", "findLatestResponse", "operationSignal", "raceWithAbortSignal" };
pub const fields = .{ "models", "credentials", "defaultBuiltins", "builtins", "nativeExtensionProviders", "extensionProviders", "virtualModels", "compositionErrors", "modelsPath", "modelNetworkEnabled", "config", "snapshot", "availabilityRefreshSeq", "availabilityErrorSeq", "providerAvailabilitySeq", "availabilityError", "credentialOperations" };
const Method = enum(c_int) { configureRadiusProviders, providerIds, recomposeProvider, composeProvider, rebuildProviders, updateModelSnapshot, runAvailabilityRefresh, queueAvailabilityRefresh, refreshProviderAvailability, getProviders, getProvider, getModels, getModel, getModelsOfType, getModelOfType, getAllModels, getAvailableOfType, getAllAvailable, checkAuth, getAvailable, getAvailableSnapshot, getError, getRegisteredProviderConfig, getRegisteredProviderIds, getRegisteredNativeProvider, getCompatibilityRequestConfig, isUsingOAuth, isUsingSubscription, hasConfiguredAuth, getAuth, enqueueCredentialOperation, synchronizeCredentialState, setRuntimeApiKey, removeRuntimeApiKey, listCredentials, getProviderAuthStatus, prepareRequest, stream, complete, streamSimple, completeSimple, streamDeferred, fetchDeferred, cancelDeferred, generateImages, classify, login, logout, refresh, registerNativeProvider, markProvisionallyConfigured, registerProvider, unregisterProvider, registerVirtualModel, unregisterVirtualModel, resolveModel, getPhysicalModel };
const Stage = enum(c_int) { delegate, auth, prepare_auth, prepare_headers, dispatch_prepared, route_simple, availability_all, availability_provider, availability_return, refresh_config, refresh_models, refresh_available, credential_start, credential_committed, credential_synchronized, synchronize_refreshed, synchronize_available, virtual_routed, pair_auth };

fn asynchronous(method: Method) bool {
    return switch (method) {
        .runAvailabilityRefresh, .refreshProviderAvailability, .checkAuth, .getAvailable, .getAuth, .synchronizeCredentialState, .prepareRequest, .fetchDeferred, .cancelDeferred, .generateImages, .classify, .refresh, .resolveModel => true,
        else => false,
    };
}
fn arity(method: Method) c_int {
    return switch (method) {
        .configureRadiusProviders, .providerIds, .rebuildProviders, .updateModelSnapshot, .getProviders, .getAvailableSnapshot, .getError, .getRegisteredProviderIds, .refresh => 0,
        .runAvailabilityRefresh, .getModelOfType, .enqueueCredentialOperation, .stream, .complete, .streamSimple, .completeSimple, .streamDeferred, .fetchDeferred, .cancelDeferred, .generateImages, .classify, .getAvailableOfType, .markProvisionallyConfigured, .resolveModel => 3,
        .synchronizeCredentialState, .login => 4,
        .refreshProviderAvailability, .getModel, .getModelsOfType, .getAllAvailable, .getAvailable, .checkAuth, .setRuntimeApiKey, .prepareRequest, .registerProvider, .unregisterVirtualModel, .getPhysicalModel => 2,
        else => 1,
    };
}

fn providerIds(scope: *Scope, runtime: c.JSValue) !c.JSValue {
    const list = try scope.array();
    inline for (.{ "builtins", "nativeExtensionProviders" }) |field| {
        const keys = try arrayFrom(scope, try scope.invoke(try scope.get(runtime, field), "keys", &.{}));
        for (0..try sdk.length(scope.engine, keys)) |index| try append(scope, list, try item(scope, keys, index));
    }
    const configured = try arrayFrom(scope, try scope.invoke(try scope.get(runtime, "config"), "getProviderIds", &.{}));
    for (0..try sdk.length(scope.engine, configured)) |index| try append(scope, list, try item(scope, configured, index));
    inline for (.{ "extensionProviders", "virtualModels" }) |field| {
        const keys = try arrayFrom(scope, try scope.invoke(try scope.get(runtime, field), "keys", &.{}));
        for (0..try sdk.length(scope.engine, keys)) |index| try append(scope, list, try item(scope, keys, index));
    }
    return builtin(scope, "Set", &.{list});
}
fn configureRadius(scope: *Scope, runtime: c.JSValue, bindings: c.JSValue) !c.JSValue {
    _ = try scope.invoke(try scope.get(runtime, "builtins"), "clear", &.{});
    const defaults = try arrayFrom(scope, try scope.get(runtime, "defaultBuiltins"));
    for (0..try sdk.length(scope.engine, defaults)) |index| {
        const row = try item(scope, defaults, index);
        try mapSet(scope, runtime, "builtins", try item(scope, row, 0), try item(scope, row, 1));
    }
    const ids = try arrayFrom(scope, try scope.invoke(try scope.get(runtime, "config"), "getProviderIds", &.{}));
    for (0..try sdk.length(scope.engine, ids)) |index| {
        const id = try item(scope, ids, index);
        const config = try scope.invoke(try scope.get(runtime, "config"), "getProvider", &.{id});
        if (temp.nullish(config) or !scope.equal(try scope.get(config, "oauth"), try scope.text("radius")) or !scope.truthy(try scope.get(config, "baseUrl"))) continue;
        const options = try scope.object();
        try scope.put(options, "id", id);
        const name = try scope.get(config, "name");
        try scope.put(options, "name", if (temp.nullish(name)) id else name);
        const regex = try builtin(scope, "RegExp", &.{ try scope.text("/v1/?$"), try scope.text("u") });
        try scope.put(options, "gateway", try scope.invoke(try scope.get(config, "baseUrl"), "replace", &.{ regex, try scope.text("") }));
        try mapSet(scope, runtime, "builtins", id, try scope.invoke(try scope.get(bindings, "builtinProviderCatalog"), "radiusProvider", &.{options}));
    }
    return c.pi_js_undefined();
}
fn compose(scope: *Scope, runtime: c.JSValue, bindings: c.JSValue, id: c.JSValue) !c.JSValue {
    const native = try mapGet(scope, runtime, "nativeExtensionProviders", id);
    const base = if (temp.nullish(native)) try mapGet(scope, runtime, "builtins", id) else native;
    const extension = try mapGet(scope, runtime, "extensionProviders", id);
    if (!scope.truthy(try scope.invoke(try scope.get(runtime, "config"), "getProvider", &.{id})) and !scope.truthy(extension)) {
        try mapDelete(scope, runtime, "compositionErrors", id);
        return base;
    }
    const value = imported(scope, bindings, "composeModelProvider", &.{ id, base, try scope.get(runtime, "config"), extension }) catch |err| {
        if (err != error.JavaScriptException) return err;
        const reason = try scope.own(flow.reason(scope.engine, err));
        try mapSet(scope, runtime, "compositionErrors", id, try errorText(scope, reason));
        return base;
    };
    try mapDelete(scope, runtime, "compositionErrors", id);
    return value;
}
fn recompose(scope: *Scope, runtime: c.JSValue, bindings: c.JSValue, id: c.JSValue) !c.JSValue {
    const provider = try scope.invoke(runtime, "composeProvider", &.{id});
    const entries = try mapGet(scope, runtime, "virtualModels", id);
    const virtual = try scope.array();
    if (!temp.nullish(entries)) {
        const values = try arrayFrom(scope, try scope.invoke(entries, "values", &.{}));
        for (0..try sdk.length(scope.engine, values)) |index| try append(scope, virtual, try scope.get(try item(scope, values, index), "model"));
    }
    const models = try scope.get(runtime, "models");
    if (try sdk.length(scope.engine, virtual) > 0) {
        _ = try scope.invoke(models, "setProvider", &.{try imported(scope, bindings, "withVirtualModels", &.{ id, provider, virtual })});
    } else if (scope.truthy(provider)) {
        _ = try scope.invoke(models, "setProvider", &.{provider});
    } else {
        _ = try scope.invoke(models, "deleteProvider", &.{id});
    }
    return provider;
}
fn filterConfigured(scope: *Scope, all: c.JSValue, configured: c.JSValue) !c.JSValue {
    const output = try scope.array();
    for (0..try sdk.length(scope.engine, all)) |index| {
        const model = try item(scope, all, index);
        if (scope.truthy(try scope.invoke(configured, "has", &.{try scope.get(model, "provider")}))) try append(scope, output, model);
    }
    return output;
}
fn updateSnapshot(scope: *Scope, runtime: c.JSValue) !c.JSValue {
    const all = try arrayFrom(scope, try scope.invoke(try scope.get(runtime, "models"), "getModels", &.{}));
    const snapshot = try objectCopy(scope, try scope.get(runtime, "snapshot"));
    try scope.put(snapshot, "all", all);
    try scope.put(snapshot, "available", try filterConfigured(scope, all, try scope.get(try scope.get(runtime, "snapshot"), "configuredProviders")));
    try scope.set(runtime, "snapshot", snapshot);
    return c.pi_js_undefined();
}
fn getError(scope: *Scope, runtime: c.JSValue) !c.JSValue {
    const list = try scope.array();
    const configured = try scope.invoke(try scope.get(runtime, "config"), "getError", &.{});
    if (scope.truthy(configured)) try append(scope, list, configured);
    const entries = try arrayFrom(scope, try scope.get(runtime, "compositionErrors"));
    for (0..try sdk.length(scope.engine, entries)) |index| {
        const row = try item(scope, entries, index);
        const prefix = try scope.concat(try scope.concat(try scope.text("Provider \""), try item(scope, row, 0)), try scope.text("\": "));
        try append(scope, list, try scope.concat(prefix, try item(scope, row, 1)));
    }
    const availability = try scope.get(runtime, "availabilityError");
    if (scope.truthy(availability)) try append(scope, list, try scope.concat(try scope.text("Availability refresh: "), availability));
    return if (try sdk.length(scope.engine, list) > 0) scope.invoke(list, "join", &.{try scope.text("\n\n")}) else c.pi_js_undefined();
}
fn authStatus(scope: *Scope, runtime: c.JSValue, bindings: c.JSValue, id: c.JSValue) !c.JSValue {
    const output = try scope.object();
    var source: ?[]const u8 = null;
    if (scope.truthy(try scope.invoke(try scope.get(runtime, "credentials"), "hasRuntimeApiKey", &.{id}))) source = "runtime" else if (scope.truthy(try scope.invoke(try scope.get(try scope.get(runtime, "snapshot"), "storedProviders"), "has", &.{id}))) source = "stored";
    if (source) |name| {
        try scope.put(output, "configured", c.pi_js_bool(scope.engine.context, 1));
        try scope.put(output, "source", try scope.text(name));
        return output;
    }
    const configured = try imported(scope, bindings, "configuredRequestAuthStatus", &.{ try scope.invoke(try scope.get(runtime, "config"), "getProvider", &.{id}), try mapGet(scope, runtime, "extensionProviders", id) });
    if (scope.truthy(configured)) return configured;
    const auth = try scope.invoke(try scope.get(try scope.get(runtime, "snapshot"), "auth"), "get", &.{id});
    try scope.put(output, "configured", c.pi_js_bool(scope.engine.context, @intFromBool(scope.truthy(auth))));
    if (scope.truthy(auth)) {
        try scope.put(output, "source", try scope.text("environment"));
        try scope.put(output, "label", try scope.get(auth, "source"));
    }
    return output;
}
fn markConfigured(scope: *Scope, runtime: c.JSValue, args: []const c.JSValue) !c.JSValue {
    const id = arg(args, 0);
    const status = arg(args, 1);
    const old = try scope.get(runtime, "snapshot");
    if (!scope.truthy(try scope.invoke(try scope.get(old, "storedProviders"), "has", &.{id})) and (temp.nullish(status) or !scope.truthy(try scope.get(status, "configured")))) return c.pi_js_undefined();
    const configured = try builtin(scope, "Set", &.{try scope.get(old, "configuredProviders")});
    _ = try scope.invoke(configured, "add", &.{id});
    const auth = try builtin(scope, "Map", &.{try scope.get(old, "auth")});
    if (!scope.truthy(try scope.invoke(auth, "get", &.{id}))) {
        const entry = try scope.object();
        try scope.put(entry, "type", arg(args, 2));
        try scope.put(entry, "source", try scope.text("configured provider"));
        _ = try scope.invoke(auth, "set", &.{ id, entry });
    }
    const snapshot = try objectCopy(scope, try scope.get(runtime, "snapshot"));
    try scope.put(snapshot, "auth", auth);
    try scope.put(snapshot, "configuredProviders", configured);
    try scope.put(snapshot, "available", try filterConfigured(scope, try scope.get(try scope.get(runtime, "snapshot"), "all"), configured));
    try scope.set(runtime, "snapshot", snapshot);
    return c.pi_js_undefined();
}
fn registration(scope: *Scope, runtime: c.JSValue, bindings: c.JSValue, method: Method, args: []const c.JSValue) !c.JSValue {
    var id = arg(args, 0);
    const input = arg(args, 1);
    switch (method) {
        .registerNativeProvider => {
            const provider = arg(args, 0);
            if (!scope.truthy(try scope.invoke(try scope.get(provider, "id"), "trim", &.{}))) return throwValue(scope, try ordinaryError(scope, try scope.text("Provider id must not be empty.")));
            try mapDelete(scope, runtime, "extensionProviders", try scope.get(provider, "id"));
            try mapSet(scope, runtime, "nativeExtensionProviders", try scope.get(provider, "id"), provider);
            _ = try scope.invoke(runtime, "recomposeProvider", &.{try scope.get(provider, "id")});
            _ = try scope.invoke(runtime, "updateModelSnapshot", &.{});
            const target = try scope.get(provider, "id");
            const status = try imported(scope, bindings, "configuredRequestAuthStatus", &.{ try scope.invoke(try scope.get(runtime, "config"), "getProvider", &.{try scope.get(provider, "id")}), c.pi_js_undefined() });
            const oauth = try scope.get(try scope.get(provider, "auth"), "oauth");
            const kind = if (scope.truthy(oauth) and !scope.truthy(try scope.get(try scope.get(provider, "auth"), "apiKey"))) "oauth" else "api_key";
            _ = try scope.invoke(runtime, "markProvisionallyConfigured", &.{ target, status, try scope.text(kind) });
            const options = try scope.object();
            try scope.put(options, "allowNetwork", c.pi_js_bool(scope.engine.context, 0));
            _ = try scope.invoke(runtime, "refresh", &.{options});
            return c.pi_js_undefined();
        },
        .registerProvider => {
            _ = try imported(scope, bindings, "validateExtensionProvider", &.{ id, try mapGet(scope, runtime, "builtins", id), try scope.invoke(try scope.get(runtime, "config"), "getProvider", &.{id}), input });
            try mapDelete(scope, runtime, "nativeExtensionProviders", id);
            const effective = try objectCopy(scope, try mapGet(scope, runtime, "extensionProviders", id));
            const entries = try scope.invoke(try scope.global("Object"), "entries", &.{input});
            for (0..try sdk.length(scope.engine, entries)) |index| {
                const row = try item(scope, entries, index);
                const value = try item(scope, row, 1);
                if (!c.JS_IsUndefined(value)) {
                    const atom = c.JS_ValueToAtom(scope.engine.context, try item(scope, row, 0));
                    defer c.JS_FreeAtom(scope.engine.context, atom);
                    if (c.JS_DefinePropertyValue(scope.engine.context, effective, atom, c.JS_DupValue(scope.engine.context, value), c.JS_PROP_C_W_E) < 0) return js.capture(scope.engine);
                }
            }
            try mapSet(scope, runtime, "extensionProviders", id, effective);
        },
        .unregisterProvider => {
            try mapDelete(scope, runtime, "extensionProviders", id);
            try mapDelete(scope, runtime, "nativeExtensionProviders", id);
        },
        .registerVirtualModel => {
            id = try scope.get(arg(args, 0), "provider");
            const name = try scope.get(arg(args, 0), "id");
            if (!scope.truthy(try scope.invoke(id, "trim", &.{})) or !scope.truthy(try scope.invoke(name, "trim", &.{}))) return throwValue(scope, try ordinaryError(scope, try scope.text("Virtual model provider and id must not be empty.")));
            const existing = try scope.invoke(try scope.get(runtime, "models"), "getModel", &.{ id, name });
            if (scope.truthy(existing) and !scope.truthy(try imported(scope, bindings, "isVirtualModel", &.{existing}))) return throwValue(scope, try ordinaryError(scope, try scope.concat(try message(scope, "Virtual model ", id, "/"), try message(scope, "", name, " conflicts with a physical model."))));
            var entries = try mapGet(scope, runtime, "virtualModels", id);
            if (temp.nullish(entries)) entries = try builtin(scope, "Map", &.{});
            const entry = try scope.object();
            try scope.put(entry, "model", try imported(scope, bindings, "createVirtualModel", &.{arg(args, 0)}));
            try scope.put(entry, "route", try callback(scope, routeDefinition, 0, &.{arg(args, 0)}, 1));
            _ = try scope.invoke(entries, "set", &.{ name, entry });
            try mapSet(scope, runtime, "virtualModels", id, entries);
            const provider = try scope.invoke(runtime, "recomposeProvider", &.{id});
            const old = try scope.get(runtime, "snapshot");
            if (!scope.truthy(provider) and !scope.truthy(try scope.invoke(try scope.get(old, "configuredProviders"), "has", &.{id}))) {
                const auth = try builtin(scope, "Map", &.{try scope.get(old, "auth")});
                const value = try scope.object();
                try scope.put(value, "type", try scope.text("api_key"));
                try scope.put(value, "source", try scope.text("virtual"));
                _ = try scope.invoke(auth, "set", &.{ id, value });
                const configured = try builtin(scope, "Set", &.{try scope.get(try scope.get(runtime, "snapshot"), "configuredProviders")});
                _ = try scope.invoke(configured, "add", &.{id});
                const snapshot = try objectCopy(scope, try scope.get(runtime, "snapshot"));
                try scope.put(snapshot, "auth", auth);
                try scope.put(snapshot, "configuredProviders", configured);
                try scope.set(runtime, "snapshot", snapshot);
            }
        },
        .unregisterVirtualModel => {
            const entries = try mapGet(scope, runtime, "virtualModels", id);
            if (temp.nullish(entries) or !scope.truthy(try scope.invoke(entries, "delete", &.{input}))) return c.pi_js_undefined();
            if (scope.equal(try scope.get(entries, "size"), c.JS_NewInt32(scope.engine.context, 0))) try mapDelete(scope, runtime, "virtualModels", id);
        },
        else => unreachable,
    }
    if (method != .registerVirtualModel) {
        _ = try scope.invoke(runtime, "recomposeProvider", &.{id});
    }
    _ = try scope.invoke(runtime, "updateModelSnapshot", &.{});
    if (method == .registerNativeProvider or method == .registerProvider) {
        const effective = if (method == .registerNativeProvider) c.pi_js_undefined() else try mapGet(scope, runtime, "extensionProviders", id);
        const status = try imported(scope, bindings, "configuredRequestAuthStatus", &.{ try scope.invoke(try scope.get(runtime, "config"), "getProvider", &.{id}), effective });
        const auth = if (method == .registerNativeProvider) try scope.get(arg(args, 0), "auth") else effective;
        const kind = if (scope.truthy(try scope.get(auth, "oauth")) and !scope.truthy(try scope.get(auth, "apiKey"))) "oauth" else "api_key";
        _ = try scope.invoke(runtime, "markProvisionallyConfigured", &.{ id, status, try scope.text(kind) });
    }
    const refresh = try scope.object();
    try scope.put(refresh, "allowNetwork", c.pi_js_bool(scope.engine.context, 0));
    _ = try scope.invoke(runtime, "refresh", &.{refresh});
    return c.pi_js_undefined();
}
fn callback(scope: *Scope, function: c.JSCFunctionData, magic: c_int, roots: []const c.JSValue, length: c_int) !c.JSValue {
    return scope.own(try scope.engine.checked(c.JS_NewCFunctionData2(scope.engine.context, function, "", length, magic, @intCast(roots.len), @constCast(roots.ptr))));
}
fn providerPairCallback(context: ?*c.JSContext, _: c.JSValue, argc: c_int, args: [*c]c.JSValue, _: c_int, _: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const provider = if (argc > 0) args[0] else c.pi_js_undefined();
    const output = pair(&scope, scope.get(provider, "id") catch |err| return sdk.fail(engine, err), provider) catch |err| return sdk.fail(engine, err);
    return c.JS_DupValue(engine.context, output);
}
fn authPairCallback(context: ?*c.JSContext, _: c.JSValue, argc: c_int, args: [*c]c.JSValue, _: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    return authPair(engine, roots[0], roots[1], roots[2], if (argc > 0) args[0] else c.pi_js_undefined()) catch |err| sdk.fail(engine, err);
}
fn authPair(engine: *em.Engine, runtime: c.JSValue, bindings: c.JSValue, input_signal: c.JSValue, provider: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const pending = try flow.create(engine, runtime);
    defer engine.freeValue(pending.owner);
    _ = try scope.own(pending.promise);
    try scope.put(pending.owner, "bindings", bindings);
    authPairStart(&scope, pending.owner, runtime, input_signal, provider) catch |err| {
        try failJob(&scope, pending.owner, try scope.own(flow.reason(engine, err)));
    };
    return c.JS_DupValue(engine.context, pending.promise);
}
fn authPairStart(scope: *Scope, job: c.JSValue, runtime: c.JSValue, input_signal: c.JSValue, provider: c.JSValue) !void {
    try scope.put(job, "providerId", try scope.get(provider, "id"));
    try wait(scope, job, try scope.invoke(try scope.get(runtime, "models"), "checkAuth", &.{ try scope.get(provider, "id"), try signalOptions(scope, input_signal) }), .pair_auth);
}
fn routeDefinition(context: ?*c.JSContext, _: c.JSValue, argc: c_int, args: [*c]c.JSValue, _: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    return js.invoke(engine, roots[0], "route", &.{if (argc > 0) args[0] else c.pi_js_undefined()}) catch |err| sdk.fail(engine, err);
}
fn adopt(scope: *Scope, value: c.JSValue) !c.JSValue {
    const pending = try flow.create(scope.engine, c.pi_js_undefined());
    defer scope.engine.freeValue(pending.owner);
    _ = try scope.own(pending.promise);
    try flow.settle(scope.engine, pending.owner, false, value);
    return pending.promise;
}

fn begin(scope: *Scope, runtime: c.JSValue, bindings: c.JSValue, method: Method, args: []const c.JSValue) !c.JSValue {
    const pending = try flow.create(scope.engine, runtime);
    defer scope.engine.freeValue(pending.owner);
    _ = try scope.own(pending.promise);
    const job = pending.owner;
    try scope.put(job, "bindings", bindings);
    try scope.put(job, "method", c.JS_NewInt32(scope.engine.context, @intFromEnum(method)));
    const input = try scope.array();
    for (args) |value| try append(scope, input, value);
    try scope.put(job, "args", input);
    start(scope, job, runtime, bindings, method, args) catch |err| {
        try failJob(scope, job, try scope.own(flow.reason(scope.engine, err)));
    };
    return pending.promise;
}
fn wait(scope: *Scope, job: c.JSValue, value: c.JSValue, stage: Stage) !void {
    try flow.wait(continuation, scope.engine, job, value, @intFromEnum(stage));
}
fn finish(scope: *Scope, job: c.JSValue, value: c.JSValue) !void {
    try flow.settle(scope.engine, job, false, value);
}
fn continuation(engine: *em.Engine, job: c.JSValue, value: c.JSValue, rejected: bool, raw: c_int) anyerror!void {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const stage: Stage = @enumFromInt(raw);
    if (rejected) {
        try failJob(&scope, job, value);
        return;
    }
    advance(&scope, job, value, stage) catch |err| {
        try failJob(&scope, job, try scope.own(flow.reason(engine, err)));
    };
}
fn failJob(scope: *Scope, job: c.JSValue, reason: c.JSValue) !void {
    const runtime = try scope.get(job, "agent");
    const bindings = try scope.get(job, "bindings");
    const mode = try scope.get(job, "failureMode");
    if (scope.equal(mode, try scope.text("images")) or scope.equal(mode, try scope.text("classifier"))) {
        const options = try scope.get(job, "options");
        const input = try signal(scope, options);
        const is_aborted = if (temp.nullish(input)) c.pi_js_undefined() else try scope.get(input, "aborted");
        const result = try imported(scope, bindings, if (scope.equal(mode, try scope.text("images"))) "imageErrorResult" else "classifierErrorResult", &.{ try scope.get(job, "model"), reason, is_aborted });
        try finish(scope, job, result);
        return;
    }
    if (scope.equal(mode, try scope.text("synchronize"))) {
        const constructor_value = try scope.get(bindings, "CredentialSynchronizationError");
        const options = try scope.object();
        try scope.put(options, "cause", reason);
        const failure = try scope.own(try scope.engine.checked(c.JS_CallConstructor(scope.engine.context, constructor_value, 4, @constCast((&[_]c.JSValue{ try scope.get(job, "providerId"), try scope.get(job, "operation"), try scope.get(job, "credential"), options }).ptr))));
        try flow.settle(scope.engine, job, true, failure);
        return;
    }
    if (scope.equal(mode, try scope.text("availability")) or scope.equal(mode, try scope.text("providerAvailability"))) {
        const current = scope.equal(try scope.get(job, "errorSeq"), try scope.get(runtime, "availabilityErrorSeq"));
        const provider_current = if (scope.equal(mode, try scope.text("providerAvailability"))) scope.equal(try mapGet(scope, runtime, "providerAvailabilitySeq", try scope.get(job, "providerId")), try scope.get(job, "providerSeq")) else true;
        const effective = if (scope.equal(mode, try scope.text("availability"))) try signal(scope, try scope.get(job, "options")) else try scope.get(job, "signal");
        if (current and provider_current and !try aborted(scope, effective)) try scope.set(runtime, "availabilityError", try errorText(scope, reason));
    }
    if (scope.equal(mode, try scope.text("refreshProvider"))) {
        const options = try scope.get(job, "options");
        if (!try aborted(scope, try signal(scope, options))) {
            const failure = if (c.JS_IsError(reason)) reason else try ordinaryError(scope, try scope.stringify(reason));
            _ = try scope.invoke(try scope.get(job, "errors"), "set", &.{ try scope.get(job, "providerId"), failure });
        }
        try finish(scope, job, c.pi_js_undefined());
        return;
    }
    if (scope.equal(mode, try scope.text("refreshAll"))) {
        try refreshResult(scope, job);
        return;
    }
    try flow.settle(scope.engine, job, true, reason);
}
fn promiseAll(scope: *Scope, values: c.JSValue) !c.JSValue {
    return scope.invoke(try scope.global("Promise"), "all", &.{values});
}
fn signalOptions(scope: *Scope, input: c.JSValue) !c.JSValue {
    const value = try scope.object();
    try scope.put(value, "signal", input);
    return value;
}
fn start(scope: *Scope, job: c.JSValue, runtime: c.JSValue, bindings: c.JSValue, method: Method, args: []const c.JSValue) !void {
    const first = arg(args, 0);
    switch (method) {
        .checkAuth => try finish(scope, job, try scope.invoke(try scope.get(runtime, "models"), "checkAuth", &.{ first, arg(args, 1) })),
        .fetchDeferred => try finish(scope, job, try scope.invoke(try scope.invoke(runtime, "streamDeferred", &.{ first, arg(args, 1), arg(args, 2) }), "result", &.{})),
        .getAuth => {
            const overrides = try optionsDefault(scope, arg(args, 1));
            try scope.put(job, "model", first);
            try scope.put(job, "options", overrides);
            const resolution = try scope.invoke(try scope.get(runtime, "models"), "getAuth", &.{ first, overrides });
            if (c.JS_IsString(first)) try finish(scope, job, resolution) else try wait(scope, job, resolution, .auth);
        },
        .prepareRequest => {
            try scope.put(job, "model", first);
            try scope.put(job, "options", arg(args, 1));
            const provider = try scope.invoke(try scope.get(runtime, "models"), "getProvider", &.{try scope.get(first, "provider")});
            if (!scope.truthy(provider)) {
                _ = try modelsError(scope, bindings, "provider", try message(scope, "Unknown provider: ", try scope.get(first, "provider"), ""));
                return;
            }
            try scope.put(job, "provider", provider);
            const overrides = try scope.object();
            inline for (.{ "apiKey", "env", "signal" }) |name| try scope.put(overrides, name, if (temp.nullish(arg(args, 1))) c.pi_js_undefined() else try scope.get(arg(args, 1), name));
            try wait(scope, job, try scope.invoke(runtime, "getAuth", &.{ first, overrides }), .prepare_auth);
        },
        .getAvailable => {
            const options = arg(args, 1);
            if (scope.truthy(first)) {
                try scope.put(job, "failureMode", try scope.text("availability"));
                try scope.put(job, "errorSeq", try next(scope, runtime, "availabilityErrorSeq"));
                try scope.put(job, "options", options);
                try wait(scope, job, try scope.invoke(try scope.get(runtime, "models"), "getAvailable", &.{ first, options }), .availability_return);
            } else try wait(scope, job, try scope.invoke(runtime, "queueAvailabilityRefresh", &.{try signal(scope, options)}), .availability_return);
            try scope.put(job, "providerQuery", c.pi_js_bool(scope.engine.context, @intFromBool(scope.truthy(first))));
        },
        .runAvailabilityRefresh => {
            try scope.put(job, "seq", first);
            try scope.put(job, "errorSeq", arg(args, 1));
            try scope.put(job, "signal", arg(args, 2));
            const providers = try scope.invoke(try scope.get(runtime, "models"), "getProviders", &.{});
            const values = try scope.array();
            try append(scope, values, try scope.invoke(try scope.get(runtime, "models"), "getAvailable", &.{ c.pi_js_undefined(), try signalOptions(scope, arg(args, 2)) }));
            const mapper = try callback(scope, authPairCallback, 0, &.{ runtime, bindings, arg(args, 2) }, 1);
            if (c.JS_SetPrototype(scope.engine.context, mapper, try scope.own(try scope.engine.checked(c.JS_GetAsyncFunctionPrototype(scope.engine.context)))) < 0) return js.capture(scope.engine);
            const checks = try scope.invoke(providers, "map", &.{mapper});
            try append(scope, values, try promiseAll(scope, checks));
            try append(scope, values, try scope.invoke(try scope.get(runtime, "credentials"), "list", &.{try signalOptions(scope, arg(args, 2))}));
            try wait(scope, job, try promiseAll(scope, values), .availability_all);
        },
        .refreshProviderAvailability => {
            _ = try next(scope, runtime, "availabilityRefreshSeq");
            try scope.put(job, "providerId", first);
            const previous = try mapGet(scope, runtime, "providerAvailabilitySeq", first);
            var number: f64 = 0;
            if (!temp.nullish(previous)) {
                if (c.JS_ToFloat64(scope.engine.context, &number, previous) < 0) return js.capture(scope.engine);
            }
            const seq = c.JS_NewFloat64(scope.engine.context, number + 1);
            try mapSet(scope, runtime, "providerAvailabilitySeq", first, seq);
            try scope.put(job, "providerSeq", seq);
            try scope.put(job, "errorSeq", try next(scope, runtime, "availabilityErrorSeq"));
            try scope.put(job, "failureMode", try scope.text("providerAvailability"));
            try scope.put(job, "signal", arg(args, 1));
            const values = try scope.array();
            try append(scope, values, try scope.invoke(try scope.get(runtime, "models"), "getAvailable", &.{ first, try signalOptions(scope, arg(args, 1)) }));
            try append(scope, values, try scope.invoke(try scope.get(runtime, "models"), "checkAuth", &.{ first, try signalOptions(scope, arg(args, 1)) }));
            try append(scope, values, try scope.invoke(try scope.get(runtime, "credentials"), "read", &.{ first, try signalOptions(scope, arg(args, 1)) }));
            try wait(scope, job, try promiseAll(scope, values), .availability_provider);
        },
        .synchronizeCredentialState => {
            try scope.put(job, "failureMode", try scope.text("synchronize"));
            try scope.put(job, "providerId", first);
            try scope.put(job, "operation", arg(args, 1));
            try scope.put(job, "credential", arg(args, 2));
            try scope.put(job, "signal", arg(args, 3));
            _ = try scope.invoke(arg(args, 3), "throwIfAborted", &.{});
            _ = try scope.invoke(runtime, "recomposeProvider", &.{first});
            const failure = try mapGet(scope, runtime, "compositionErrors", first);
            if (scope.truthy(failure)) {
                _ = try throwValue(scope, try ordinaryError(scope, failure));
                return;
            }
            const options = try scope.object();
            try scope.put(options, "allowNetwork", c.pi_js_bool(scope.engine.context, 0));
            const ids = try scope.array();
            try append(scope, ids, first);
            try scope.put(options, "providers", ids);
            try scope.put(options, "signal", arg(args, 3));
            try wait(scope, job, try scope.invoke(try scope.get(runtime, "models"), "refresh", &.{options}), .synchronize_refreshed);
        },
        .refresh => {
            const options = try optionsDefault(scope, first);
            try scope.put(job, "options", options);
            try wait(scope, job, try scope.invoke(try scope.get(bindings, "ModelConfig"), "load", &.{try scope.get(runtime, "modelsPath")}), .refresh_config);
        },
        .cancelDeferred, .generateImages, .classify => {
            try scope.put(job, "model", first);
            try scope.put(job, "context", arg(args, 1));
            try scope.put(job, "options", arg(args, 2));
            try scope.put(job, "dispatch", try scope.text(if (method == .cancelDeferred) "cancelDeferred" else if (method == .generateImages) "generateImages" else "classify"));
            if (method != .cancelDeferred) try scope.put(job, "failureMode", try scope.text(if (method == .generateImages) "images" else "classifier"));
            _ = try imported(scope, bindings, if (method == .cancelDeferred) "assertChatModel" else if (method == .generateImages) "assertImageModel" else "assertClassifierModel", &.{first});
            if (method == .classify) {
                _ = try imported(scope, bindings, "assertClassifierInputSupported", &.{ first, arg(args, 1) });
            }
            try wait(scope, job, try scope.invoke(runtime, "prepareRequest", &.{ first, arg(args, 2) }), .dispatch_prepared);
        },
        .resolveModel => try routeStart(scope, job, runtime, bindings, args),
        else => return error.InvalidModelRuntimeAsyncMethod,
    }
}
fn advance(scope: *Scope, job: c.JSValue, value: c.JSValue, stage: Stage) !void {
    const runtime = try scope.get(job, "agent");
    const bindings = try scope.get(job, "bindings");
    switch (stage) {
        .delegate => try finish(scope, job, if (scope.truthy(try scope.get(job, "discardResult"))) c.pi_js_undefined() else value),
        .pair_auth => try finish(scope, job, try pair(scope, try scope.get(job, "providerId"), value)),
        .auth => try finish(scope, job, try finishAuth(scope, runtime, bindings, try scope.get(job, "model"), try scope.get(job, "options"), value)),
        .prepare_auth => try prepareAuth(scope, job, runtime, value),
        .prepare_headers => {
            try scope.put(job, "headers", value);
            try prepareResult(scope, job);
        },
        .dispatch_prepared => try dispatchPrepared(scope, job, value),
        .route_simple => try simpleRouted(scope, job, value),
        .availability_all => {
            if (scope.equal(try scope.get(job, "seq"), try scope.get(runtime, "availabilityRefreshSeq"))) {
                const checks = try item(scope, value, 1);
                const configured = try builtin(scope, "Set", &.{});
                for (0..try sdk.length(scope.engine, checks)) |index| {
                    const entry = try item(scope, checks, index);
                    if (!c.JS_IsUndefined(try item(scope, entry, 1))) {
                        _ = try scope.invoke(configured, "add", &.{try item(scope, entry, 0)});
                    }
                }
                const stored = try builtin(scope, "Set", &.{});
                const credentials = try item(scope, value, 2);
                for (0..try sdk.length(scope.engine, credentials)) |index| {
                    _ = try scope.invoke(stored, "add", &.{try scope.get(try item(scope, credentials, index), "providerId")});
                }
                const snapshot = try scope.object();
                try scope.put(snapshot, "all", try arrayFrom(scope, try scope.invoke(try scope.get(runtime, "models"), "getModels", &.{})));
                try scope.put(snapshot, "available", try arrayFrom(scope, try item(scope, value, 0)));
                try scope.put(snapshot, "configuredProviders", configured);
                try scope.put(snapshot, "storedProviders", stored);
                try scope.put(snapshot, "auth", try builtin(scope, "Map", &.{checks}));
                try scope.set(runtime, "snapshot", snapshot);
                if (scope.equal(try scope.get(job, "errorSeq"), try scope.get(runtime, "availabilityErrorSeq"))) try scope.set(runtime, "availabilityError", c.pi_js_undefined());
            }
            try finish(scope, job, c.pi_js_undefined());
        },
        .availability_provider => try providerSnapshot(scope, job, value),
        .availability_return => {
            if (scope.truthy(try scope.get(job, "providerQuery"))) {
                if (scope.equal(try scope.get(job, "errorSeq"), try scope.get(runtime, "availabilityErrorSeq"))) try scope.set(runtime, "availabilityError", c.pi_js_undefined());
                try finish(scope, job, value);
            } else try finish(scope, job, try scope.get(try scope.get(runtime, "snapshot"), "available"));
        },
        .refresh_config => {
            try scope.set(runtime, "config", value);
            _ = try scope.invoke(runtime, "configureRadiusProviders", &.{});
            const options = try scope.get(job, "options");
            const selected = try scope.get(options, "providers");
            if (scope.truthy(selected)) {
                const ids = try arrayFrom(scope, try builtin(scope, "Set", &.{try scope.get(options, "providers")}));
                for (0..try sdk.length(scope.engine, ids)) |index| {
                    _ = try scope.invoke(runtime, "recomposeProvider", &.{try item(scope, ids, index)});
                }
                _ = try scope.invoke(runtime, "updateModelSnapshot", &.{});
            } else {
                _ = try scope.invoke(runtime, "rebuildProviders", &.{});
            }
            const refresh = try objectCopy(scope, options);
            const network = try scope.get(options, "allowNetwork");
            try scope.put(refresh, "allowNetwork", if (temp.nullish(network)) try scope.get(runtime, "modelNetworkEnabled") else network);
            try scope.put(job, "refreshOptions", refresh);
            try wait(scope, job, try scope.invoke(try scope.get(runtime, "models"), "refresh", &.{refresh}), .refresh_models);
        },
        .refresh_models => try refreshModels(scope, job, value),
        .refresh_available => try refreshResult(scope, job),
        .credential_start => {
            _ = try scope.invoke(try scope.get(job, "signal"), "throwIfAborted", &.{});
            _ = try scope.call(try scope.get(job, "markStarted"), c.pi_js_undefined(), &.{});
            try finish(scope, job, try scope.call(try scope.get(job, "task"), c.pi_js_undefined(), &.{}));
        },
        .credential_committed => {
            const credential = if (scope.equal(try scope.get(job, "operation"), try scope.text("login"))) value else c.pi_js_undefined();
            try scope.put(job, "credential", credential);
            try wait(scope, job, try scope.invoke(runtime, "synchronizeCredentialState", &.{ try scope.get(job, "providerId"), try scope.get(job, "operation"), credential, try scope.get(job, "signal") }), .credential_synchronized);
        },
        .credential_synchronized => try finish(scope, job, if (scope.equal(try scope.get(job, "operation"), try scope.text("login"))) try scope.get(job, "credential") else c.pi_js_undefined()),
        .synchronize_refreshed => {
            if (scope.truthy(try scope.get(value, "aborted"))) {
                _ = try scope.invoke(try scope.get(job, "signal"), "throwIfAborted", &.{});
            }
            const failure = try scope.invoke(try scope.get(value, "errors"), "get", &.{try scope.get(job, "providerId")});
            if (scope.truthy(failure)) {
                _ = try throwValue(scope, failure);
                return;
            }
            _ = try scope.invoke(runtime, "updateModelSnapshot", &.{});
            try wait(scope, job, try scope.invoke(runtime, "refreshProviderAvailability", &.{ try scope.get(job, "providerId"), try scope.get(job, "signal") }), .synchronize_available);
        },
        .synchronize_available => try finish(scope, job, c.pi_js_undefined()),
        .virtual_routed => try routeFinish(scope, job, runtime, bindings, value),
    }
}
fn arg(args: []const c.JSValue, index: usize) c.JSValue {
    return if (index < args.len) args[index] else c.pi_js_undefined();
}
fn item(scope: *Scope, value: c.JSValue, index: usize) !c.JSValue {
    return scope.own(try scope.engine.checked(c.JS_GetPropertyUint32(scope.engine.context, value, @intCast(index))));
}
fn objectCopy(scope: *Scope, value: c.JSValue) !c.JSValue {
    return scope.own(try js.spread(scope.engine, value));
}
fn spread(scope: *Scope, target: c.JSValue, value: c.JSValue) !void {
    try js.spreadInto(scope.engine, target, value);
}
fn builtin(scope: *Scope, name: [*:0]const u8, args: []const c.JSValue) !c.JSValue {
    return scope.own(try js.builtin(scope.engine, name, args));
}
fn arrayFrom(scope: *Scope, value: c.JSValue) !c.JSValue {
    return scope.invoke(try scope.global("Array"), "from", &.{value});
}
fn append(scope: *Scope, array: c.JSValue, value: c.JSValue) !void {
    _ = try scope.invoke(array, "push", &.{value});
}
fn pair(scope: *Scope, first: c.JSValue, second: c.JSValue) !c.JSValue {
    const result = try scope.array();
    try append(scope, result, first);
    try append(scope, result, second);
    return result;
}
fn imported(scope: *Scope, bindings: c.JSValue, name: [*:0]const u8, args: []const c.JSValue) !c.JSValue {
    return scope.call(try scope.get(bindings, name), c.pi_js_undefined(), args);
}
fn mapGet(scope: *Scope, runtime: c.JSValue, field: [*:0]const u8, id: c.JSValue) !c.JSValue {
    return scope.invoke(try scope.get(runtime, field), "get", &.{id});
}
fn mapSet(scope: *Scope, runtime: c.JSValue, field: [*:0]const u8, id: c.JSValue, value: c.JSValue) !void {
    _ = try scope.invoke(try scope.get(runtime, field), "set", &.{ id, value });
}
fn mapDelete(scope: *Scope, runtime: c.JSValue, field: [*:0]const u8, id: c.JSValue) !void {
    _ = try scope.invoke(try scope.get(runtime, field), "delete", &.{id});
}
fn next(scope: *Scope, runtime: c.JSValue, field: [*:0]const u8) !c.JSValue {
    var value: f64 = 0;
    if (c.JS_ToFloat64(scope.engine.context, &value, try scope.get(runtime, field)) < 0) return js.capture(scope.engine);
    const result = c.JS_NewFloat64(scope.engine.context, value + 1);
    try scope.set(runtime, field, result);
    return result;
}
fn errorText(scope: *Scope, value: c.JSValue) !c.JSValue {
    return if (c.JS_IsError(value)) scope.get(value, "message") else scope.call(try scope.global("String"), c.pi_js_undefined(), &.{value});
}
fn throwValue(scope: *Scope, value: c.JSValue) !c.JSValue {
    return scope.own(try scope.engine.checked(c.JS_Throw(scope.engine.context, c.JS_DupValue(scope.engine.context, value))));
}
fn ordinaryError(scope: *Scope, text: c.JSValue) !c.JSValue {
    return builtin(scope, "Error", &.{text});
}
fn modelsError(scope: *Scope, bindings: c.JSValue, code: []const u8, text: c.JSValue) !c.JSValue {
    return throwValue(scope, try scope.own(try scope.engine.checked(c.JS_CallConstructor(scope.engine.context, try scope.get(bindings, "ModelsError"), 2, @constCast((&[_]c.JSValue{ try scope.text(code), text }).ptr)))));
}
fn message(scope: *Scope, prefix: []const u8, value: c.JSValue, suffix: []const u8) !c.JSValue {
    return scope.concat(try scope.concat(try scope.text(prefix), value), try scope.text(suffix));
}
fn signal(scope: *Scope, options: c.JSValue) !c.JSValue {
    return if (temp.nullish(options)) c.pi_js_undefined() else scope.get(options, "signal");
}
fn aborted(scope: *Scope, value: c.JSValue) !bool {
    return !temp.nullish(value) and scope.truthy(try scope.get(value, "aborted"));
}
fn optionsDefault(scope: *Scope, value: c.JSValue) !c.JSValue {
    return if (c.JS_IsUndefined(value)) scope.object() else value;
}
fn delete(scope: *Scope, object: c.JSValue, name: [*:0]const u8) !void {
    const atom = c.JS_NewAtom(scope.engine.context, name);
    if (atom == c.JS_ATOM_NULL) return js.capture(scope.engine);
    defer c.JS_FreeAtom(scope.engine.context, atom);
    if (c.JS_DeleteProperty(scope.engine.context, object, atom, 0) < 0) return js.capture(scope.engine);
}

fn rest(scope: *Scope, source: c.JSValue, excluded: []const [:0]const u8) !c.JSValue {
    const output = try scope.object();
    if (temp.nullish(source)) return output;
    const boxed = try scope.own(try scope.engine.checked(c.JS_ToObject(scope.engine.context, source)));
    var names: [*c]c.JSPropertyEnum = null;
    var count: u32 = 0;
    if (c.JS_GetOwnPropertyNames(scope.engine.context, &names, &count, boxed, c.JS_GPN_STRING_MASK | c.JS_GPN_SYMBOL_MASK) < 0) return js.capture(scope.engine);
    defer c.JS_FreePropertyEnum(scope.engine.context, names, count);
    for (names[0..count]) |entry| {
        var skip = false;
        for (excluded) |name| {
            const atom = c.JS_NewAtom(scope.engine.context, name.ptr);
            if (atom == c.JS_ATOM_NULL) return js.capture(scope.engine);
            defer c.JS_FreeAtom(scope.engine.context, atom);
            skip = skip or entry.atom == atom;
        }
        if (skip) continue;
        var descriptor: c.JSPropertyDescriptor = undefined;
        const present = c.JS_GetOwnProperty(scope.engine.context, &descriptor, boxed, entry.atom);
        if (present < 0) return js.capture(scope.engine);
        if (present == 0) continue;
        defer scope.engine.freeValue(descriptor.value);
        defer scope.engine.freeValue(descriptor.getter);
        defer scope.engine.freeValue(descriptor.setter);
        if (descriptor.flags & c.JS_PROP_ENUMERABLE == 0) continue;
        const value = try scope.engine.checked(c.JS_GetProperty(scope.engine.context, boxed, entry.atom));
        if (c.JS_DefinePropertyValue(scope.engine.context, output, entry.atom, value, c.JS_PROP_C_W_E) < 0) return js.capture(scope.engine);
    }
    return output;
}
fn mergeHeaders(scope: *Scope, base: c.JSValue, override: c.JSValue) !c.JSValue {
    if (!scope.truthy(base) and !scope.truthy(override)) return c.pi_js_undefined();
    const merged = try objectCopy(scope, base);
    const entries = try scope.invoke(try scope.global("Object"), "entries", &.{if (temp.nullish(override)) try scope.object() else override});
    for (0..try sdk.length(scope.engine, entries)) |index| {
        const row = try item(scope, entries, index);
        const name = try item(scope, row, 0);
        const lower = try scope.invoke(name, "toLowerCase", &.{});
        const keys = try scope.invoke(try scope.global("Object"), "keys", &.{merged});
        for (0..try sdk.length(scope.engine, keys)) |old_index| {
            const old = try item(scope, keys, old_index);
            if (scope.equal(try scope.invoke(old, "toLowerCase", &.{}), lower)) {
                const atom = c.JS_ValueToAtom(scope.engine.context, old);
                if (atom == c.JS_ATOM_NULL) return js.capture(scope.engine);
                defer c.JS_FreeAtom(scope.engine.context, atom);
                if (c.JS_DeleteProperty(scope.engine.context, merged, atom, 0) < 0) return js.capture(scope.engine);
            }
        }
        const atom = c.JS_ValueToAtom(scope.engine.context, name);
        if (atom == c.JS_ATOM_NULL) return js.capture(scope.engine);
        defer c.JS_FreeAtom(scope.engine.context, atom);
        if (c.JS_DefinePropertyValue(scope.engine.context, merged, atom, c.JS_DupValue(scope.engine.context, try item(scope, row, 1)), c.JS_PROP_C_W_E) < 0) return js.capture(scope.engine);
    }
    return merged;
}
fn finishAuth(scope: *Scope, runtime: c.JSValue, bindings: c.JSValue, model: c.JSValue, overrides: c.JSValue, resolution: c.JSValue) !c.JSValue {
    if (!scope.truthy(resolution)) return c.pi_js_undefined();
    const env = try objectCopy(scope, try scope.get(resolution, "env"));
    try spread(scope, env, try scope.get(overrides, "env"));
    const headers = try imported(scope, bindings, "resolveConfiguredModelHeaders", &.{ model, try scope.invoke(try scope.get(runtime, "config"), "getProvider", &.{try scope.get(model, "provider")}), try mapGet(scope, runtime, "extensionProviders", try scope.get(model, "provider")), env });
    const output = try objectCopy(scope, resolution);
    const auth = try objectCopy(scope, try scope.get(resolution, "auth"));
    try scope.put(auth, "headers", try mergeHeaders(scope, try scope.get(try scope.get(resolution, "auth"), "headers"), headers));
    try scope.put(output, "auth", auth);
    return output;
}
fn prepareAuth(scope: *Scope, job: c.JSValue, _: c.JSValue, resolution: c.JSValue) !void {
    const model = try scope.get(job, "model");
    const bindings = try scope.get(job, "bindings");
    if (!scope.truthy(resolution)) {
        _ = try modelsError(scope, bindings, "auth", try message(scope, "Provider is not configured: ", try scope.get(model, "provider"), ""));
        return;
    }
    try scope.put(job, "resolution", resolution);
    const options = try scope.get(job, "options");
    const source = if (temp.nullish(options)) try scope.object() else options;
    const transform = try scope.get(source, "transformHeaders");
    const raw = try rest(scope, source, &.{"transformHeaders"});
    try scope.put(job, "providerOptions", raw);
    const headers = try mergeHeaders(scope, try scope.get(try scope.get(resolution, "auth"), "headers"), try scope.get(raw, "headers"));
    try scope.put(job, "headers", headers);
    if (scope.truthy(transform)) try wait(scope, job, try scope.call(transform, c.pi_js_undefined(), &.{if (temp.nullish(headers)) try scope.object() else headers}), .prepare_headers) else try prepareResult(scope, job);
}
fn prepareResult(scope: *Scope, job: c.JSValue) !void {
    const resolution = try scope.get(job, "resolution");
    const raw = try scope.get(job, "providerOptions");
    const auth = try scope.get(resolution, "auth");
    const initial = try scope.get(job, "model");
    const auth_env = try scope.get(resolution, "env");
    const raw_env = try scope.get(raw, "env");
    var env = c.pi_js_undefined();
    if (scope.truthy(auth_env) or scope.truthy(raw_env)) {
        env = try objectCopy(scope, auth_env);
        try spread(scope, env, raw_env);
    }
    var model = initial;
    if (scope.truthy(try scope.get(auth, "baseUrl"))) {
        model = try objectCopy(scope, initial);
        try scope.put(model, "baseUrl", try scope.get(auth, "baseUrl"));
    }
    const options = try objectCopy(scope, raw);
    const key = try scope.get(raw, "apiKey");
    try scope.put(options, "apiKey", if (temp.nullish(key)) try scope.get(auth, "apiKey") else key);
    try scope.put(options, "headers", try scope.get(job, "headers"));
    try scope.put(options, "env", env);
    const result = try scope.object();
    try scope.put(result, "provider", try scope.get(job, "provider"));
    try scope.put(result, "model", model);
    try scope.put(result, "options", options);
    try finish(scope, job, result);
}
fn providerSnapshot(scope: *Scope, job: c.JSValue, value: c.JSValue) !void {
    const runtime = try scope.get(job, "agent");
    const id = try scope.get(job, "providerId");
    _ = try scope.invoke(try scope.get(job, "signal"), "throwIfAborted", &.{});
    if (!scope.equal(try mapGet(scope, runtime, "providerAvailabilitySeq", id), try scope.get(job, "providerSeq"))) {
        try finish(scope, job, c.pi_js_undefined());
        return;
    }
    const old = try scope.get(runtime, "snapshot");
    const configured = try builtin(scope, "Set", &.{try scope.get(old, "configuredProviders")});
    const stored = try builtin(scope, "Set", &.{try scope.get(old, "storedProviders")});
    const auths = try builtin(scope, "Map", &.{try scope.get(old, "auth")});
    const auth = try item(scope, value, 1);
    _ = try scope.invoke(configured, if (scope.truthy(auth)) "add" else "delete", &.{id});
    if (scope.truthy(auth)) {
        _ = try scope.invoke(auths, "set", &.{ id, auth });
    } else {
        _ = try scope.invoke(auths, "delete", &.{id});
    }
    _ = try scope.invoke(stored, if (scope.truthy(try item(scope, value, 2))) "add" else "delete", &.{id});
    const all_models = try arrayFrom(scope, try scope.invoke(try scope.get(runtime, "models"), "getModels", &.{}));
    const available = try scope.array();
    const previous = try scope.get(try scope.get(runtime, "snapshot"), "available");
    for (0..try sdk.length(scope.engine, previous)) |index| {
        const model = try item(scope, previous, index);
        if (!scope.equal(try scope.get(model, "provider"), id)) try append(scope, available, model);
    }
    const next_models = try arrayFrom(scope, try item(scope, value, 0));
    for (0..try sdk.length(scope.engine, next_models)) |index| try append(scope, available, try item(scope, next_models, index));
    const by_id = try builtin(scope, "Map", &.{});
    for (0..try sdk.length(scope.engine, available)) |index| {
        const model = try item(scope, available, index);
        _ = try scope.invoke(by_id, "set", &.{ try modelKey(scope, model), model });
    }
    const ordered = try scope.array();
    for (0..try sdk.length(scope.engine, all_models)) |index| {
        const model = try item(scope, all_models, index);
        const offered = try scope.invoke(by_id, "get", &.{try modelKey(scope, model)});
        if (!temp.nullish(offered)) try append(scope, ordered, offered);
    }
    const snapshot = try scope.object();
    try scope.put(snapshot, "all", all_models);
    try scope.put(snapshot, "available", ordered);
    try scope.put(snapshot, "configuredProviders", configured);
    try scope.put(snapshot, "storedProviders", stored);
    try scope.put(snapshot, "auth", auths);
    try scope.set(runtime, "snapshot", snapshot);
    if (scope.equal(try scope.get(job, "errorSeq"), try scope.get(runtime, "availabilityErrorSeq"))) try scope.set(runtime, "availabilityError", c.pi_js_undefined());
    try finish(scope, job, c.pi_js_undefined());
}
fn modelKey(scope: *Scope, model: c.JSValue) !c.JSValue {
    return scope.concat(try scope.concat(try scope.get(model, "provider"), try scope.text("\x00")), try scope.get(model, "id"));
}
fn queueAvailability(scope: *Scope, runtime: c.JSValue, bindings: c.JSValue, input: c.JSValue) !c.JSValue {
    const seq = try next(scope, runtime, "availabilityRefreshSeq");
    const rows = try arrayFrom(scope, try scope.get(runtime, "providerAvailabilitySeq"));
    for (0..try sdk.length(scope.engine, rows)) |index| {
        const row = try item(scope, rows, index);
        var number: f64 = 0;
        if (c.JS_ToFloat64(scope.engine.context, &number, try item(scope, row, 1)) < 0) return js.capture(scope.engine);
        try mapSet(scope, runtime, "providerAvailabilitySeq", try item(scope, row, 0), c.JS_NewFloat64(scope.engine.context, number + 1));
    }
    const error_seq = try next(scope, runtime, "availabilityErrorSeq");
    const effective = try imported(scope, bindings, "operationSignal", &.{input});
    const pending = try scope.invoke(runtime, "runAvailabilityRefresh", &.{ seq, error_seq, effective });
    const failure = try callback(scope, availabilityFailed, 0, &.{ runtime, error_seq, effective }, 1);
    return scope.invoke(pending, "catch", &.{failure});
}
fn availabilityFailed(context: ?*c.JSContext, _: c.JSValue, argc: c_int, args: [*c]c.JSValue, _: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const value = if (argc > 0) args[0] else c.pi_js_undefined();
    return blk: {
        if (scope.equal(roots[1], scope.get(roots[0], "availabilityErrorSeq") catch |err| return sdk.fail(engine, err)) and !(aborted(&scope, roots[2]) catch |err| return sdk.fail(engine, err))) scope.set(roots[0], "availabilityError", errorText(&scope, value) catch |err| return sdk.fail(engine, err)) catch |err| return sdk.fail(engine, err);
        break :blk c.JS_Throw(engine.context, c.JS_DupValue(engine.context, value));
    };
}
fn refreshModels(scope: *Scope, job: c.JSValue, value: c.JSValue) !void {
    const runtime = try scope.get(job, "agent");
    const options = try scope.get(job, "options");
    var result = value;
    if (temp.nullish(result)) {
        result = try scope.object();
        const abort_signal = try signal(scope, try scope.get(job, "refreshOptions"));
        const flag = if (temp.nullish(abort_signal)) c.pi_js_undefined() else try scope.get(abort_signal, "aborted");
        try scope.put(result, "aborted", if (temp.nullish(flag)) c.pi_js_bool(scope.engine.context, 0) else flag);
        try scope.put(result, "errors", try builtin(scope, "Map", &.{}));
    }
    try scope.put(job, "refreshResult", result);
    const errors = try builtin(scope, "Map", &.{try scope.get(result, "errors")});
    try scope.put(job, "errors", errors);
    _ = try scope.invoke(runtime, "updateModelSnapshot", &.{});
    if (scope.truthy(try scope.get(options, "providers"))) {
        const ids = try arrayFrom(scope, try builtin(scope, "Set", &.{try scope.get(options, "providers")}));
        const pending = try scope.array();
        for (0..try sdk.length(scope.engine, ids)) |index| {
            const id = try item(scope, ids, index);
            const task = try flow.create(scope.engine, runtime);
            defer scope.engine.freeValue(task.owner);
            _ = try scope.own(task.promise);
            try scope.put(task.owner, "bindings", try scope.get(job, "bindings"));
            try scope.put(task.owner, "failureMode", try scope.text("refreshProvider"));
            try scope.put(task.owner, "errors", errors);
            try scope.put(task.owner, "providerId", id);
            try scope.put(task.owner, "options", options);
            const effective = imported(scope, try scope.get(job, "bindings"), "operationSignal", &.{try signal(scope, options)}) catch |err| {
                try failJob(scope, task.owner, try scope.own(flow.reason(scope.engine, err)));
                try append(scope, pending, task.promise);
                continue;
            };
            const refresh = scope.invoke(runtime, "refreshProviderAvailability", &.{ id, effective }) catch |err| {
                try failJob(scope, task.owner, try scope.own(flow.reason(scope.engine, err)));
                try append(scope, pending, task.promise);
                continue;
            };
            try wait(scope, task.owner, refresh, .delegate);
            try append(scope, pending, task.promise);
        }
        try wait(scope, job, try promiseAll(scope, pending), .refresh_available);
    } else {
        try scope.put(job, "failureMode", try scope.text("refreshAll"));
        const pending = scope.invoke(runtime, "queueAvailabilityRefresh", &.{try signal(scope, options)}) catch {
            try refreshResult(scope, job);
            return;
        };
        try wait(scope, job, pending, .refresh_available);
    }
}
fn refreshResult(scope: *Scope, job: c.JSValue) !void {
    const output = try scope.object();
    const result = try scope.get(job, "refreshResult");
    const selected = try scope.get(result, "aborted");
    const options = try scope.get(job, "options");
    var flag = selected;
    if (!scope.truthy(selected)) {
        const selected_signal = try signal(scope, options);
        const value = if (temp.nullish(selected_signal)) c.pi_js_undefined() else try scope.get(selected_signal, "aborted");
        flag = if (temp.nullish(value)) c.pi_js_bool(scope.engine.context, 0) else value;
    }
    try scope.put(output, "aborted", flag);
    try scope.put(output, "errors", try scope.get(job, "errors"));
    try finish(scope, job, output);
}

fn stream(scope: *Scope, runtime: c.JSValue, bindings: c.JSValue, method: Method, args: []const c.JSValue) !c.JSValue {
    const data = try scope.object();
    try scope.put(data, "agent", runtime);
    try scope.put(data, "bindings", bindings);
    try scope.put(data, "model", arg(args, 0));
    try scope.put(data, "originalContext", arg(args, 1));
    try scope.put(data, "options", arg(args, 2));
    const transcript = if (method == .streamDeferred) arg(args, 1) else try imported(scope, bindings, "normalizeContext", &.{arg(args, 1)});
    try scope.put(data, "context", transcript);
    try scope.put(data, "dispatch", try scope.text(if (method == .stream) "stream" else if (method == .streamSimple) "streamSimple" else "fetchDeferred"));
    const virtual = method == .streamSimple and scope.truthy(try imported(scope, bindings, "isVirtualModel", &.{arg(args, 0)}));
    try scope.put(data, "virtual", c.pi_js_bool(scope.engine.context, @intFromBool(virtual)));
    const setup = try callback(scope, lazySetup, 0, &.{data}, 0);
    if (c.JS_SetPrototype(scope.engine.context, setup, try scope.own(try scope.engine.checked(c.JS_GetAsyncFunctionPrototype(scope.engine.context)))) < 0) return js.capture(scope.engine);
    return imported(scope, bindings, "lazyStream", &.{ arg(args, 0), setup });
}
fn lazySetup(context: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue, _: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    return lazyBegin(engine, roots[0]) catch |err| sdk.fail(engine, err);
}
fn lazyBegin(engine: *em.Engine, data: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const runtime = try scope.get(data, "agent");
    const bindings = try scope.get(data, "bindings");
    const pending = try flow.create(engine, runtime);
    defer engine.freeValue(pending.owner);
    _ = try scope.own(pending.promise);
    try spread(&scope, pending.owner, data);
    lazyStart(&scope, pending.owner, runtime, bindings) catch |err| {
        try failJob(&scope, pending.owner, try scope.own(flow.reason(engine, err)));
    };
    return c.JS_DupValue(engine.context, pending.promise);
}
fn lazyStart(scope: *Scope, job: c.JSValue, runtime: c.JSValue, bindings: c.JSValue) !void {
    const model = try scope.get(job, "model");
    const options = try scope.get(job, "options");
    if (scope.truthy(try scope.get(job, "virtual"))) {
        const route = try scope.object();
        try scope.put(route, "reason", try scope.text("direct"));
        const reasoning = if (temp.nullish(options)) c.pi_js_undefined() else try scope.get(options, "reasoning");
        try scope.put(route, "thinkingLevel", if (temp.nullish(reasoning)) try scope.text("off") else reasoning);
        try scope.put(route, "signal", try signal(scope, options));
        try wait(scope, job, try scope.invoke(runtime, "resolveModel", &.{ model, try scope.get(try scope.get(job, "context"), "messages"), route }), .route_simple);
        return;
    }
    _ = try imported(scope, bindings, "assertChatModel", &.{model});
    try wait(scope, job, try scope.invoke(runtime, "prepareRequest", &.{ model, options }), .dispatch_prepared);
}
fn dispatchPrepared(scope: *Scope, job: c.JSValue, prepared: c.JSValue) !void {
    const provider = try scope.get(prepared, "provider");
    const method = try scope.get(job, "dispatch");
    const name = try scope.engine.toString(method);
    defer scope.engine.gpa.free(name);
    const zname = try scope.engine.gpa.dupeZ(u8, name);
    defer scope.engine.gpa.free(zname);
    const supports = try scope.get(provider, zname);
    var suffix: ?[]const u8 = null;
    if (std.mem.eql(u8, name, "fetchDeferred") or std.mem.eql(u8, name, "cancelDeferred")) suffix = " does not support deferred responses" else if (std.mem.eql(u8, name, "generateImages")) suffix = " does not support image generation" else if (std.mem.eql(u8, name, "classify")) suffix = " does not support classification";
    if (suffix) |text| if (!scope.truthy(supports)) {
        _ = try modelsError(scope, try scope.get(job, "bindings"), "provider", try message(scope, "Provider ", try scope.get(try scope.get(job, "model"), "provider"), text));
        return;
    };
    const implementation = if (suffix != null) try scope.get(try scope.get(prepared, "provider"), zname) else supports;
    const value = try scope.call(implementation, provider, &.{ try scope.get(prepared, "model"), try scope.get(job, "context"), try scope.get(prepared, "options") });
    if (std.mem.eql(u8, name, "cancelDeferred")) try scope.put(job, "discardResult", c.pi_js_bool(scope.engine.context, 1));
    try wait(scope, job, value, .delegate);
}
fn simpleRouted(scope: *Scope, job: c.JSValue, route: c.JSValue) !void {
    const options = try scope.get(job, "options");
    const model = try scope.get(route, "model");
    const limit = try scope.get(model, "maxTokens");
    const first = if (temp.nullish(options)) c.pi_js_undefined() else try scope.get(options, "maxTokens");
    const max_tokens = if (scope.truthy(first) and try scope.positive(limit)) try scope.invoke(try scope.global("Math"), "min", &.{ try scope.get(options, "maxTokens"), limit }) else if (temp.nullish(options)) c.pi_js_undefined() else try scope.get(options, "maxTokens");
    const level = try scope.get(route, "thinkingLevel");
    const reasoning = if (scope.equal(level, try scope.text("off"))) c.pi_js_undefined() else level;
    const input = if (temp.nullish(options)) try scope.object() else options;
    const key = try scope.get(input, "apiKey");
    const headers = try scope.get(input, "headers");
    const env = try scope.get(input, "env");
    const output = try rest(scope, input, &.{ "apiKey", "headers", "env" });
    if (scope.equal(try scope.get(model, "provider"), try scope.get(try scope.get(job, "model"), "provider"))) {
        try scope.put(output, "apiKey", key);
        try scope.put(output, "headers", headers);
        try scope.put(output, "env", env);
    }
    try scope.put(output, "maxTokens", max_tokens);
    try scope.put(output, "reasoning", reasoning);
    try finish(scope, job, try scope.invoke(try scope.get(job, "agent"), "streamSimple", &.{ try scope.get(route, "model"), try scope.get(job, "originalContext"), output }));
}
fn credentialOperation(scope: *Scope, runtime: c.JSValue, bindings: c.JSValue, method: Method, args: []const c.JSValue) !c.JSValue {
    const options = if (method == .login) arg(args, 3) else try optionsDefault(scope, arg(args, if (method == .setRuntimeApiKey) 2 else 1));
    const effective = try imported(scope, bindings, "operationSignal", &.{if (method == .login) try scope.get(arg(args, 2), "signal") else try scope.get(options, "signal")});
    const data = try scope.object();
    try scope.put(data, "agent", runtime);
    try scope.put(data, "bindings", bindings);
    try scope.put(data, "providerId", arg(args, 0));
    try scope.put(data, "operation", try scope.text(@tagName(method)));
    try scope.put(data, "signal", effective);
    try scope.put(data, "options", options);
    try scope.put(data, "type", arg(args, 1));
    try scope.put(data, "interaction", arg(args, 2));
    try scope.put(data, "apiKey", arg(args, 1));
    const task = try callback(scope, credentialTask, 0, &.{data}, 0);
    if (c.JS_SetPrototype(scope.engine.context, task, try scope.own(try scope.engine.checked(c.JS_GetAsyncFunctionPrototype(scope.engine.context)))) < 0) return js.capture(scope.engine);
    return scope.invoke(runtime, "enqueueCredentialOperation", &.{ arg(args, 0), effective, task });
}
fn credentialTask(context: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue, _: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    return credentialBegin(engine, roots[0]) catch |err| sdk.fail(engine, err);
}
fn credentialBegin(engine: *em.Engine, data: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const runtime = try scope.get(data, "agent");
    const pending = try flow.create(engine, runtime);
    defer engine.freeValue(pending.owner);
    _ = try scope.own(pending.promise);
    try spread(&scope, pending.owner, data);
    credentialStart(&scope, pending.owner, runtime) catch |err| {
        try failJob(&scope, pending.owner, try scope.own(flow.reason(engine, err)));
    };
    return c.JS_DupValue(engine.context, pending.promise);
}
fn credentialStart(scope: *Scope, job: c.JSValue, runtime: c.JSValue) !void {
    const id = try scope.get(job, "providerId");
    const operation = try scope.get(job, "operation");
    const selected = try scope.get(job, "signal");
    if (scope.equal(operation, try scope.text("login"))) {
        const interaction = try objectCopy(scope, try scope.get(job, "interaction"));
        try scope.put(interaction, "signal", selected);
        try wait(scope, job, try scope.invoke(try scope.get(runtime, "models"), "login", &.{ id, try scope.get(job, "type"), interaction, try scope.get(job, "options") }), .credential_committed);
        return;
    }
    if (scope.equal(operation, try scope.text("logout"))) {
        try wait(scope, job, try scope.invoke(try scope.get(runtime, "models"), "logout", &.{ id, try signalOptions(scope, selected) }), .credential_committed);
        return;
    }
    const credentials = try scope.get(runtime, "credentials");
    var credential = c.pi_js_undefined();
    if (scope.equal(operation, try scope.text("setRuntimeApiKey"))) {
        _ = try scope.invoke(credentials, "setRuntimeApiKey", &.{ id, try scope.get(job, "apiKey") });
        credential = try scope.object();
        try scope.put(credential, "type", try scope.text("api_key"));
        try scope.put(credential, "key", try scope.get(job, "apiKey"));
    } else {
        _ = try scope.invoke(credentials, "removeRuntimeApiKey", &.{id});
    }
    try scope.put(job, "credential", credential);
    try wait(scope, job, try scope.invoke(runtime, "synchronizeCredentialState", &.{ id, operation, credential, selected }), .credential_synchronized);
}
fn noop(_: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue, _: c_int, _: [*c]c.JSValue) callconv(.c) c.JSValue {
    return c.pi_js_undefined();
}
fn enqueue(scope: *Scope, runtime: c.JSValue, bindings: c.JSValue, args: []const c.JSValue) !c.JSValue {
    const id = arg(args, 0);
    const input_signal = arg(args, 1);
    const previous = try mapGet(scope, runtime, "credentialOperations", id);
    const predecessor = if (temp.nullish(previous)) try scope.own(try scope.engine.checked(c.JS_PiPromiseResolve(scope.engine.context, c.pi_js_undefined()))) else previous;
    var started_functions: [2]c.JSValue = undefined;
    const started = try scope.own(try scope.engine.checked(c.JS_NewPromiseCapability(scope.engine.context, &started_functions)));
    defer for (started_functions) |value| scope.engine.freeValue(value);
    const pending = try flow.create(scope.engine, runtime);
    defer scope.engine.freeValue(pending.owner);
    _ = try scope.own(pending.promise);
    try scope.put(pending.owner, "bindings", bindings);
    try scope.put(pending.owner, "signal", input_signal);
    try scope.put(pending.owner, "task", arg(args, 2));
    try scope.put(pending.owner, "markStarted", started_functions[0]);
    const ignore = try callback(scope, noop, 0, &.{}, 0);
    const ready = scope.invoke(predecessor, "catch", &.{ignore}) catch |err| {
        try failJob(scope, pending.owner, try scope.own(flow.reason(scope.engine, err)));
        return enqueueTail(scope, runtime, bindings, id, input_signal, started, pending.promise, ignore);
    };
    try wait(scope, pending.owner, ready, .credential_start);
    return enqueueTail(scope, runtime, bindings, id, input_signal, started, pending.promise, ignore);
}
fn enqueueTail(scope: *Scope, runtime: c.JSValue, bindings: c.JSValue, id: c.JSValue, input_signal: c.JSValue, started: c.JSValue, operation: c.JSValue, ignore: c.JSValue) !c.JSValue {
    const tail = try scope.invoke(operation, "catch", &.{ignore});
    try mapSet(scope, runtime, "credentialOperations", id, tail);
    const cleanup = try callback(scope, credentialCleanup, 0, &.{ runtime, id, tail }, 0);
    _ = try scope.invoke(tail, "then", &.{cleanup});
    const racing = try imported(scope, bindings, "raceWithAbortSignal", &.{ started, input_signal });
    return scope.invoke(racing, "then", &.{try callback(scope, returnCaptured, 0, &.{operation}, 0)});
}
fn returnCaptured(context: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue, _: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    return c.JS_DupValue(context, roots[0]);
}
fn credentialCleanup(context: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue, _: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const current = mapGet(&scope, roots[0], "credentialOperations", roots[1]) catch |err| return sdk.fail(engine, err);
    if (scope.equal(current, roots[2])) mapDelete(&scope, roots[0], "credentialOperations", roots[1]) catch |err| return sdk.fail(engine, err);
    return c.pi_js_undefined();
}
fn routeStart(scope: *Scope, job: c.JSValue, runtime: c.JSValue, bindings: c.JSValue, args: []const c.JSValue) !void {
    const model = arg(args, 0);
    const messages = arg(args, 1);
    const options = arg(args, 2);
    try scope.put(job, "model", model);
    const name = try scope.concat(try message(scope, "Virtual model ", try scope.get(model, "provider"), "/"), try scope.get(model, "id"));
    try scope.put(job, "routeName", name);
    const provider = try mapGet(scope, runtime, "virtualModels", try scope.get(model, "provider"));
    const virtual = if (temp.nullish(provider)) c.pi_js_undefined() else try scope.invoke(provider, "get", &.{try scope.get(model, "id")});
    if (!scope.truthy(virtual)) {
        _ = try throwValue(scope, try ordinaryError(scope, try scope.concat(name, try scope.text(" is not registered."))));
        return;
    }
    const failed = try scope.get(options, "failed");
    const request = try rest(scope, options, &.{"failed"});
    const latest = try imported(scope, bindings, "findLatestResponse", &.{messages});
    const previous = if (scope.truthy(latest)) try scope.invoke(runtime, "getPhysicalModel", &.{ try scope.get(latest, "provider"), try scope.get(latest, "model") }) else latest;
    const failed_model = if (scope.truthy(failed)) try scope.invoke(runtime, "getPhysicalModel", &.{ try scope.get(failed, "provider"), try scope.get(failed, "model") }) else failed;
    try scope.put(request, "model", model);
    var previous_row = previous;
    if (scope.truthy(previous)) {
        previous_row = try scope.object();
        try scope.put(previous_row, "model", previous);
        try scope.put(previous_row, "thinkingLevel", if (temp.nullish(latest)) c.pi_js_undefined() else try scope.get(latest, "thinkingLevel"));
    }
    try scope.put(request, "previous", previous_row);
    var failed_row = failed_model;
    if (scope.truthy(failed_model) and scope.truthy(failed)) {
        failed_row = try scope.object();
        try scope.put(failed_row, "model", failed_model);
        try scope.put(failed_row, "thinkingLevel", try scope.get(failed, "thinkingLevel"));
        try scope.put(failed_row, "message", failed);
    }
    try scope.put(request, "failed", failed_row);
    try scope.put(request, "messages", messages);
    try wait(scope, job, try scope.invoke(virtual, "route", &.{request}), .virtual_routed);
}
fn routeFinish(scope: *Scope, job: c.JSValue, runtime: c.JSValue, bindings: c.JSValue, route: c.JSValue) !void {
    const model = try scope.get(route, "model");
    const target = try scope.invoke(runtime, "getPhysicalModel", &.{ try scope.get(model, "provider"), try scope.get(model, "id") });
    const routed = try scope.concat(try scope.concat(try scope.concat(try scope.get(job, "routeName"), try scope.text(" routed to ")), try scope.get(try scope.get(route, "model"), "provider")), try message(scope, "/", try scope.get(try scope.get(route, "model"), "id"), ""));
    if (!scope.truthy(target)) {
        _ = try throwValue(scope, try ordinaryError(scope, try scope.concat(routed, try scope.text(", which is not a physical model."))));
        return;
    }
    if (!scope.truthy(try scope.invoke(runtime, "hasConfiguredAuth", &.{try scope.get(target, "provider")}))) {
        _ = try throwValue(scope, try ordinaryError(scope, try scope.concat(routed, try scope.text(", which has no credentials."))));
        return;
    }
    const result = try scope.object();
    try scope.put(result, "model", target);
    try scope.put(result, "thinkingLevel", try imported(scope, bindings, "clampThinkingLevel", &.{ target, try scope.get(route, "thinkingLevel") }));
    try scope.put(result, "state", try scope.get(route, "state"));
    try finish(scope, job, result);
}

/// Actual utils/abort.ts helpers. The assembler passes these exports explicitly
/// into ModelRuntime imports; constructor() never supplies a fallback namespace.
pub fn abortHelpers(engine: *em.Engine) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const result = try scope.object();
    try scope.put(result, "operationSignal", try scope.own(try @import("native_node_function.zig").create(engine, "operationSignal", 1, abortFunction, &.{c.JS_NewInt32(engine.context, 0)})));
    try scope.put(result, "raceWithAbortSignal", try scope.own(try @import("native_node_function.zig").create(engine, "raceWithAbortSignal", 2, abortFunction, &.{c.JS_NewInt32(engine.context, 1)})));
    return c.JS_DupValue(engine.context, result);
}
fn abortFunction(engine: *em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    var magic: i32 = 0;
    if (c.JS_ToInt32(engine.context, &magic, roots[0]) < 0) return js.capture(engine);
    const result = if (magic == 0) operationSignal(&scope, arg(args, 0)) else raceAbort(&scope, arg(args, 0), arg(args, 1));
    return c.JS_DupValue(engine.context, try result);
}
fn operationSignal(scope: *Scope, value: c.JSValue) !c.JSValue {
    return if (!temp.nullish(value)) value else scope.get(try builtin(scope, "AbortController", &.{}), "signal");
}
fn abortReason(scope: *Scope, input: c.JSValue) !c.JSValue {
    const reason = try scope.get(input, "reason");
    if (!c.JS_IsUndefined(reason)) return reason;
    const failure = try ordinaryError(scope, try scope.text("The operation was aborted"));
    try scope.set(failure, "name", try scope.text("AbortError"));
    return failure;
}
fn raceAbort(scope: *Scope, operation: c.JSValue, input: c.JSValue) !c.JSValue {
    if (!scope.truthy(input)) return operation;
    if (try aborted(scope, input)) {
        _ = try scope.invoke(operation, "catch", &.{try callback(scope, noop, 0, &.{}, 0)});
        return scope.invoke(try scope.global("Promise"), "reject", &.{try abortReason(scope, input)});
    }
    const pending = try flow.create(scope.engine, operation);
    defer scope.engine.freeValue(pending.owner);
    _ = try scope.own(pending.promise);
    const job = pending.owner;
    try scope.put(job, "signal", input);
    try scope.put(job, "settled", c.pi_js_bool(scope.engine.context, 0));
    const on_abort = try callback(scope, abortContinuation, 2, &.{job}, 0);
    try scope.put(job, "onAbort", on_abort);
    raceStart(scope, job, operation, input, on_abort) catch |err| {
        try flow.settle(scope.engine, job, true, try scope.own(flow.reason(scope.engine, err)));
    };
    return pending.promise;
}
fn raceStart(scope: *Scope, job: c.JSValue, operation: c.JSValue, input: c.JSValue, on_abort: c.JSValue) !void {
    const options = try scope.object();
    try scope.put(options, "once", c.pi_js_bool(scope.engine.context, 1));
    _ = try scope.invoke(input, "addEventListener", &.{ try scope.text("abort"), on_abort, options });
    _ = try scope.invoke(operation, "then", &.{ try callback(scope, abortContinuation, 0, &.{job}, 1), try callback(scope, abortContinuation, 1, &.{job}, 1) });
    if (try aborted(scope, input)) {
        _ = try scope.call(on_abort, c.pi_js_undefined(), &.{});
    }
}
fn abortContinuation(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, magic: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    abortComplete(&scope, roots[0], if (argc > 0) argv[0] else c.pi_js_undefined(), magic) catch |err| return sdk.fail(engine, err);
    return c.pi_js_undefined();
}
fn abortComplete(scope: *Scope, job: c.JSValue, value: c.JSValue, magic: c_int) !void {
    if (scope.truthy(try scope.get(job, "settled"))) return;
    try scope.set(job, "settled", c.pi_js_bool(scope.engine.context, 1));
    const input = try scope.get(job, "signal");
    _ = try scope.invoke(input, "removeEventListener", &.{ try scope.text("abort"), try scope.get(job, "onAbort") });
    try flow.settle(scope.engine, job, magic != 0, if (magic == 2) try abortReason(scope, input) else value);
}

pub fn validateInputs(engine: *em.Engine, imports: c.JSValue) !void {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    if (!c.JS_IsObject(imports)) return error.RequiredActualModelRuntimeImports;
    inline for (required_functions) |name| if (!c.JS_IsFunction(engine.context, try scope.get(imports, name))) return error.RequiredActualModelRuntimeBinding;
    if (!c.JS_IsFunction(engine.context, try scope.get(try scope.get(imports, "ModelConfig"), "load"))) return error.RequiredActualModelConfigLoad;
    if (!c.JS_IsFunction(engine.context, try scope.get(try scope.get(imports, "builtinProviderCatalog"), "radiusProvider"))) return error.RequiredActualRadiusProvider;
}
/// Captures genuine module imports once. No default catalog or fallback service.
pub fn exports(engine: *em.Engine, imports: c.JSValue) !c.JSValue {
    try validateInputs(engine, imports);
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const bindings = try scope.object();
    inline for (required_functions) |name| try scope.put(bindings, name, try scope.get(imports, name));
    inline for (.{ "ModelConfig", "builtinProviderCatalog" }) |name| try scope.put(bindings, name, try scope.get(imports, name));
    const failure = try credentialErrorConstructor(&scope);
    try scope.put(bindings, "CredentialSynchronizationError", failure);
    const prototype = try scope.object();
    const ctor = try scope.own(try @import("native_class.zig").constructor(engine, "ModelRuntime", 6, prototype, construct, &.{bindings}));
    inline for (@typeInfo(Method).@"enum".fields) |field| {
        const method: Method = @enumFromInt(field.value);
        const function = try scope.own(try engine.checked(c.JS_NewCFunctionData2(engine.context, dispatch, field.name, arity(method), field.value, 1, @constCast((&[_]c.JSValue{bindings}).ptr))));
        if (asynchronous(method)) if (c.JS_SetPrototype(engine.context, function, try scope.own(try engine.checked(c.JS_GetAsyncFunctionPrototype(engine.context)))) < 0) return js.capture(engine);
        if (c.JS_DefinePropertyValueStr(engine.context, prototype, field.name, c.JS_DupValue(engine.context, function), c.JS_PROP_CONFIGURABLE | c.JS_PROP_WRITABLE) < 0) return js.capture(engine);
    }
    const result = try scope.object();
    try scope.put(result, "ModelRuntime", ctor);
    try scope.put(result, "CredentialSynchronizationError", failure);
    return c.JS_DupValue(engine.context, result);
}
pub fn constructor(engine: *em.Engine, imports: c.JSValue) !c.JSValue {
    const namespace = try exports(engine, imports);
    defer engine.freeValue(namespace);
    return sdk.get(engine, namespace, "ModelRuntime");
}
fn credentialErrorConstructor(scope: *Scope) !c.JSValue {
    const parent = try scope.global("Error");
    const prototype = try scope.own(try scope.engine.checked(c.JS_NewObjectProto(scope.engine.context, try scope.get(parent, "prototype"))));
    const result = try scope.own(try @import("native_class.zig").constructor(scope.engine, "CredentialSynchronizationError", 4, prototype, constructError, &.{parent}));
    if (c.JS_SetPrototype(scope.engine.context, result, parent) < 0) return js.capture(scope.engine);
    return result;
}
fn constructError(engine: *em.Engine, target: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const text = try scope.concat(try scope.concat(try scope.concat(try scope.text("Credential "), arg(args, 1)), try scope.text(" committed for ")), try message(&scope, "", arg(args, 0), ", but local synchronization failed"));
    const value = try scope.own(try engine.checked(c.JS_CallConstructor2(engine.context, roots[0], target, 2, @constCast((&[_]c.JSValue{ text, arg(args, 3) }).ptr))));
    try scope.set(value, "name", try scope.text("CredentialSynchronizationError"));
    inline for (.{ "providerId", "operation", "credential" }, 0..) |field, index| try scope.set(value, field, arg(args, index));
    return c.JS_DupValue(engine.context, value);
}
fn construct(engine: *em.Engine, target: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const value = try scope.own(try @import("native_class.zig").object(engine, target));
    inline for (fields) |field| {
        const initial = if (comptime std.mem.eql(u8, field, "builtins") or std.mem.eql(u8, field, "nativeExtensionProviders") or std.mem.eql(u8, field, "extensionProviders") or std.mem.eql(u8, field, "virtualModels") or std.mem.eql(u8, field, "compositionErrors") or std.mem.eql(u8, field, "providerAvailabilitySeq") or std.mem.eql(u8, field, "credentialOperations")) try builtin(&scope, "Map", &.{}) else if (comptime std.mem.eql(u8, field, "availabilityRefreshSeq") or std.mem.eql(u8, field, "availabilityErrorSeq")) c.JS_NewInt32(engine.context, 0) else if (comptime std.mem.eql(u8, field, "snapshot")) try emptySnapshot(&scope) else c.pi_js_undefined();
        try scope.put(value, field, initial);
    }
    try scope.set(value, "credentials", arg(args, 0));
    try scope.set(value, "config", arg(args, 1));
    try scope.set(value, "modelsPath", arg(args, 2));
    try scope.set(value, "modelNetworkEnabled", arg(args, 5));
    const providers = arg(args, 4);
    const rows = try scope.invoke(providers, "map", &.{try callback(&scope, providerPairCallback, 0, &.{}, 1)});
    const defaults = try builtin(&scope, "Map", &.{rows});
    try scope.set(value, "defaultBuiltins", defaults);
    const entries = try arrayFrom(&scope, defaults);
    for (0..try sdk.length(engine, entries)) |index| {
        const entry = try item(&scope, entries, index);
        try mapSet(&scope, value, "builtins", try item(&scope, entry, 0), try item(&scope, entry, 1));
    }
    const options = try scope.object();
    try scope.put(options, "credentials", arg(args, 0));
    try scope.put(options, "modelsStore", arg(args, 3));
    try scope.set(value, "models", try imported(&scope, roots[0], "createModels", &.{options}));
    _ = try scope.invoke(value, "rebuildProviders", &.{});
    return c.JS_DupValue(engine.context, value);
}
fn emptySnapshot(scope: *Scope) !c.JSValue {
    const snapshot = try scope.object();
    try scope.put(snapshot, "all", try scope.array());
    try scope.put(snapshot, "available", try scope.array());
    inline for (.{ "configuredProviders", "storedProviders" }) |field| try scope.put(snapshot, field, try builtin(scope, "Set", &.{}));
    try scope.put(snapshot, "auth", try builtin(scope, "Map", &.{}));
    return snapshot;
}
fn dispatch(context: ?*c.JSContext, this: c.JSValue, argc: c_int, argv: [*c]c.JSValue, magic: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    engine.native_exception_diagnostics_suppressed += 1;
    defer engine.native_exception_diagnostics_suppressed -= 1;
    const args: []const c.JSValue = if (argc > 0) argv[0..@intCast(argc)] else &.{};
    return invoke(engine, this, roots[0], @enumFromInt(magic), args) catch |err| sdk.fail(engine, err);
}
fn invoke(engine: *em.Engine, runtime: c.JSValue, bindings: c.JSValue, method: Method, args: []const c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const id = arg(args, 0);
    const result: c.JSValue = switch (method) {
        .getProviders => try scope.invoke(try scope.get(runtime, "models"), "getProviders", &.{}),
        .getProvider, .getModels, .getAllModels => try scope.invoke(try scope.get(runtime, "models"), @tagName(method), &.{id}),
        .getModel, .getModelsOfType, .getAllAvailable => try scope.invoke(try scope.get(runtime, "models"), @tagName(method), &.{ id, arg(args, 1) }),
        .getModelOfType, .getAvailableOfType => try scope.invoke(try scope.get(runtime, "models"), @tagName(method), &.{ id, arg(args, 1), arg(args, 2) }),
        .getAvailableSnapshot => try scope.get(try scope.get(runtime, "snapshot"), "available"),
        .getRegisteredProviderConfig => try mapGet(&scope, runtime, "extensionProviders", id),
        .getRegisteredNativeProvider => try mapGet(&scope, runtime, "nativeExtensionProviders", id),
        .listCredentials => try scope.invoke(try scope.get(runtime, "credentials"), "list", &.{id}),
        .getPhysicalModel => blk: {
            const model = try scope.invoke(try scope.get(runtime, "models"), "getModel", &.{ id, arg(args, 1) });
            break :blk if (scope.truthy(model) and !scope.truthy(try imported(&scope, bindings, "isVirtualModel", &.{model}))) model else c.pi_js_undefined();
        },
        .hasConfiguredAuth => try scope.invoke(try scope.get(try scope.get(runtime, "snapshot"), "configuredProviders"), "has", &.{id}),
        .isUsingOAuth => blk: {
            const auth = try scope.invoke(try scope.get(try scope.get(runtime, "snapshot"), "auth"), "get", &.{id});
            break :blk c.pi_js_bool(engine.context, @intFromBool(!temp.nullish(auth) and scope.equal(try scope.get(auth, "type"), try scope.text("oauth"))));
        },
        .isUsingSubscription => blk: {
            const oauth = try scope.invoke(runtime, "isUsingOAuth", &.{id});
            const provider = if (scope.truthy(oauth)) try scope.invoke(try scope.get(runtime, "models"), "getProvider", &.{id}) else c.pi_js_undefined();
            const auth = if (!temp.nullish(provider)) try scope.get(provider, "auth") else c.pi_js_undefined();
            const selected = if (!temp.nullish(provider)) try scope.get(auth, "oauth") else c.pi_js_undefined();
            break :blk c.pi_js_bool(engine.context, @intFromBool(scope.truthy(oauth) and !temp.nullish(selected) and scope.equal(try scope.get(selected, "isSubscription"), c.pi_js_bool(engine.context, 1))));
        },
        .providerIds => try providerIds(&scope, runtime),
        .configureRadiusProviders => try configureRadius(&scope, runtime, bindings),
        .composeProvider => try compose(&scope, runtime, bindings, id),
        .recomposeProvider => try recompose(&scope, runtime, bindings, id),
        .rebuildProviders => blk: {
            _ = try scope.invoke(try scope.get(runtime, "models"), "clearProviders", &.{});
            _ = try scope.invoke(try scope.get(runtime, "compositionErrors"), "clear", &.{});
            const ids = try arrayFrom(&scope, try scope.invoke(runtime, "providerIds", &.{}));
            for (0..try sdk.length(engine, ids)) |index| {
                _ = try scope.invoke(runtime, "recomposeProvider", &.{try item(&scope, ids, index)});
            }
            _ = try scope.invoke(runtime, "updateModelSnapshot", &.{});
            break :blk c.pi_js_undefined();
        },
        .updateModelSnapshot => try updateSnapshot(&scope, runtime),
        .getError => try getError(&scope, runtime),
        .getRegisteredProviderIds => blk: {
            const array = try scope.array();
            inline for (.{ "extensionProviders", "nativeExtensionProviders" }) |field| {
                const keys = try arrayFrom(&scope, try scope.invoke(try scope.get(runtime, field), "keys", &.{}));
                for (0..try sdk.length(engine, keys)) |index| try append(&scope, array, try item(&scope, keys, index));
            }
            break :blk try arrayFrom(&scope, try builtin(&scope, "Set", &.{array}));
        },
        .getCompatibilityRequestConfig => try imported(&scope, bindings, "resolveCompatibilityRequestConfig", &.{ id, try scope.invoke(try scope.get(runtime, "config"), "getProvider", &.{try scope.get(id, "provider")}), try mapGet(&scope, runtime, "extensionProviders", try scope.get(id, "provider")) }),
        .getProviderAuthStatus => try authStatus(&scope, runtime, bindings, id),
        .markProvisionallyConfigured => try markConfigured(&scope, runtime, args),
        .registerNativeProvider, .registerProvider, .unregisterProvider, .registerVirtualModel, .unregisterVirtualModel => try registration(&scope, runtime, bindings, method, args),
        .complete, .completeSimple => blk: {
            const event_stream = try scope.invoke(runtime, if (method == .complete) "stream" else "streamSimple", &.{ id, arg(args, 1), arg(args, 2) });
            const value = try scope.invoke(event_stream, "result", &.{});
            break :blk value;
        },
        .stream, .streamSimple, .streamDeferred => try stream(&scope, runtime, bindings, method, args),
        .login, .logout, .setRuntimeApiKey, .removeRuntimeApiKey => try credentialOperation(&scope, runtime, bindings, method, args),
        .enqueueCredentialOperation => try enqueue(&scope, runtime, bindings, args),
        .queueAvailabilityRefresh => try queueAvailability(&scope, runtime, bindings, id),
        else => try begin(&scope, runtime, bindings, method, args),
    };
    return c.JS_DupValue(engine.context, result);
}
