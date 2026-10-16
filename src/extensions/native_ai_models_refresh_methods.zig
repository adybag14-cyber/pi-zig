//! Complete original ModelsImpl refresh methods over live ordinary fields.
//! No bound-store facade, synthetic provider, or fabricated empty result.
const em = @import("engine.zig");
const js = @import("native_js_values.zig");
const sdk = @import("native_sdk.zig");
const temp = @import("native_sdk_prompt_scope.zig");
const Scope = temp.Scope;
const flow = @import("native_agent_async.zig");
const functions = @import("native_node_function.zig");
const publication = @import("native_ai_models_refresh_publication.zig");
const arithmetic = @import("native_image_arithmetic.zig");
const c = em.c;
pub const Kind = enum { publishProviderModels, runProviderRefreshPhase, refresh, resolveRefreshCredential };
pub fn create(engine: *em.Engine, comptime kind: Kind, imports: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const captured = try scope.object();
    const names = switch (kind) {
        .publishProviderModels => .{"raceWithAbortSignal"},
        .runProviderRefreshPhase => .{"getModelType"},
        .refresh => .{ "ModelsError", "operationSignal", "raceWithAbortSignal" },
        .resolveRefreshCredential => .{"refreshStoredOAuthCredential"},
    };
    inline for (names) |name| {
        const value = try scope.get(imports, name);
        if (!c.JS_IsFunction(engine.context, value)) return error.RequiredActualModelsRefreshImport;
        try scope.put(captured, name, value);
    }
    if (kind == .runProviderRefreshPhase) try publication.prepareKnownTypes(engine, captured);
    const Adapter = struct {
        fn call(host: *em.Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
            return switch (kind) {
                .publishProviderModels => publication.publish(host, receiver, args, roots[0]),
                .runProviderRefreshPhase => publication.phase(host, receiver, args, roots[0]),
                .refresh => beginRefresh(host, receiver, arg(args, 0), roots[0]),
                .resolveRefreshCredential => beginCredential(host, receiver, args, roots[0]),
            };
        }
    };
    const function = try scope.own(try functions.createMethod(engine, @tagName(kind), switch (kind) {
        .publishProviderModels => 4,
        .runProviderRefreshPhase => 6,
        .refresh => 0,
        .resolveRefreshCredential => 3,
    }, Adapter.call, &.{captured}));
    if (kind != .publishProviderModels) if (c.JS_SetPrototype(engine.context, function, try scope.own(try engine.checked(c.JS_GetAsyncFunctionPrototype(engine.context)))) < 0) return js.capture(engine);
    return c.JS_DupValue(engine.context, function);
}
fn arg(args: []const c.JSValue, index: usize) c.JSValue {
    return if (args.len > index) args[index] else c.pi_js_undefined();
}
fn beginCredential(engine: *em.Engine, receiver: c.JSValue, args: []const c.JSValue, imports: c.JSValue) !c.JSValue {
    const pending = try flow.create(engine, receiver);
    defer engine.freeValue(pending.owner);
    errdefer engine.freeValue(pending.promise);
    credentialBody(engine, pending.owner, receiver, args, imports) catch |err| try flow.rejectError(engine, pending.owner, err);
    return pending.promise;
}
fn credentialBody(engine: *em.Engine, owner: c.JSValue, receiver: c.JSValue, args: []const c.JSValue, imports: c.JSValue) !void {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const provider = arg(args, 0);
    const stored = arg(args, 1);
    const signal = arg(args, 2);
    const stored_type = if (temp.nullish(stored)) c.pi_js_undefined() else try scope.get(stored, "type");
    if (scope.equal(stored_type, try scope.text("oauth"))) {
        const oauth = try scope.get(try scope.get(provider, "auth"), "oauth");
        if (!scope.truthy(oauth)) return flow.settle(engine, owner, false, c.pi_js_undefined());
        const now = try scope.invoke(try scope.global("Date"), "now", &.{});
        if (try arithmetic.compare(engine, .less, now, try scope.get(stored, "expires"))) return flow.settle(engine, owner, false, stored);
        if (scope.truthy(try scope.get(signal, "aborted"))) return flow.settle(engine, owner, false, c.pi_js_undefined());
        const refresh = try scope.get(imports, "refreshStoredOAuthCredential");
        const credentials = try scope.get(receiver, "credentials");
        const id = try scope.get(provider, "id");
        const should_refresh = try scope.own(try functions.createArrow(engine, "", 1, oauthExpired, &.{}));
        // Source returns, rather than awaits, the shared mutation. Its started
        // credential persistence survives cancellation and supersession.
        return flow.settle(engine, owner, false, try scope.call(refresh, c.pi_js_undefined(), &.{ credentials, id, oauth, should_refresh, signal }));
    }
    const api_key = try scope.get(try scope.get(provider, "auth"), "apiKey");
    if (!scope.truthy(api_key)) return flow.settle(engine, owner, false, c.pi_js_undefined());
    const credential = if (!temp.nullish(stored) and scope.equal(try scope.get(stored, "type"), try scope.text("api_key"))) stored else c.pi_js_undefined();
    const resolve = try scope.get(api_key, "resolve");
    const options = try scope.object();
    try scope.put(options, "ctx", try scope.get(receiver, "authContext"));
    try scope.put(options, "credential", credential);
    try scope.put(options, "signal", signal);
    return flow.wait(credentialResolved, engine, owner, try scope.call(resolve, api_key, &.{options}), 0);
}
fn oauthExpired(engine: *em.Engine, _: c.JSValue, args: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const now = try scope.invoke(try scope.global("Date"), "now", &.{});
    return arithmetic.binary(engine, .greater_equal, now, try scope.get(arg(args, 0), "expires"));
}
fn credentialResolved(engine: *em.Engine, owner: c.JSValue, value: c.JSValue, rejected: bool, _: c_int) !void {
    if (rejected) return flow.settle(engine, owner, true, value);
    credentialResult(engine, owner, value) catch |err| try flow.rejectError(engine, owner, err);
}
fn credentialResult(engine: *em.Engine, owner: c.JSValue, value: c.JSValue) !void {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    if (!scope.truthy(value)) return flow.settle(engine, owner, false, c.pi_js_undefined());
    const credential = try scope.object();
    try scope.put(credential, "type", try scope.text("api_key"));
    try scope.put(credential, "key", try scope.get(try scope.get(value, "auth"), "apiKey"));
    try scope.put(credential, "env", try scope.get(value, "env"));
    try flow.settle(engine, owner, false, credential);
}
fn beginRefresh(engine: *em.Engine, receiver: c.JSValue, supplied: c.JSValue, imports: c.JSValue) !c.JSValue {
    const pending = try flow.create(engine, receiver);
    defer engine.freeValue(pending.owner);
    errdefer engine.freeValue(pending.promise);
    startRefresh(engine, pending.owner, receiver, supplied, imports) catch |err| try flow.rejectError(engine, pending.owner, err);
    return pending.promise;
}
fn outcome(scope: *Scope, aborted: c.JSValue, errors: c.JSValue) !c.JSValue {
    const value = try scope.object();
    try scope.put(value, "aborted", aborted);
    try scope.put(value, "errors", errors);
    return value;
}
fn startRefresh(engine: *em.Engine, owner: c.JSValue, receiver: c.JSValue, supplied: c.JSValue, imports: c.JSValue) !void {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    try publication.rememberNativeGeneration(&scope, owner);
    const options = if (c.JS_IsUndefined(supplied)) try scope.object() else supplied;
    var network = try scope.get(options, "allowNetwork");
    if (temp.nullish(network)) network = c.pi_js_bool(engine.context, 1);
    const caller = try scope.call(try scope.get(imports, "operationSignal"), c.pi_js_undefined(), &.{try scope.get(options, "signal")});
    const errors = try scope.own(try js.builtin(engine, "Map", &.{}));
    if (scope.truthy(try scope.get(caller, "aborted"))) return flow.settle(engine, owner, false, try outcome(&scope, c.pi_js_bool(engine.context, 1), errors));
    var selected = c.pi_js_undefined();
    if (scope.truthy(try scope.get(options, "providers"))) {
        const set = try scope.global("Set");
        var args = [_]c.JSValue{try scope.get(options, "providers")};
        selected = try scope.own(try engine.checked(c.JS_CallConstructor(engine.context, set, args.len, &args)));
    }
    const array = try scope.global("Array");
    const from = try scope.get(array, "from");
    const providers = try scope.call(from, array, &.{try scope.invoke(try scope.get(receiver, "providers"), "values", &.{})});
    const filter = try scope.get(providers, "filter");
    const predicate = try scope.own(try functions.createArrow(engine, "", 1, refreshable, &.{selected}));
    const eligible = try scope.call(filter, providers, &.{predicate});
    // Source resolves Promise.all before evaluating refreshable.map(...).
    const promise = try scope.global("Promise");
    const all = try scope.get(promise, "all");
    const map = try scope.get(eligible, "map");
    const mapper = try scope.own(try functions.createArrow(engine, "", 1, providerTask, &.{ receiver, options, network, caller, errors, imports }));
    if (c.JS_SetPrototype(engine.context, mapper, try scope.own(try engine.checked(c.JS_GetAsyncFunctionPrototype(engine.context)))) < 0) return js.capture(engine);
    const tasks = try scope.call(map, eligible, &.{mapper});
    const refresh = try scope.call(all, promise, &.{tasks});
    try scope.put(owner, "callerSignal", caller);
    try scope.put(owner, "errors", errors);
    // Everything above is outside the Source try, including begin/map setup.
    const native_generation = engine.native_allocation_generation;
    const raced = scope.call(try scope.get(imports, "raceWithAbortSignal"), c.pi_js_undefined(), &.{ refresh, caller }) catch |err| {
        if (err != error.JavaScriptException or engine.nativeAllocationError(err, native_generation) == error.OutOfMemory) return err;
        const reason = try scope.own(flow.reason(engine, err));
        return finishRefresh(engine, owner, reason, true);
    };
    return flow.wait(refreshSettled, engine, owner, raced, 0);
}
fn refreshable(engine: *em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const provider = arg(args, 0);
    if (c.JS_IsUndefined(try scope.get(provider, "refreshModels"))) return c.pi_js_bool(engine.context, 0);
    if (!scope.truthy(roots[0])) return c.pi_js_bool(engine.context, 1);
    const has = try scope.get(roots[0], "has");
    return js.call(engine, has, roots[0], &.{try scope.get(provider, "id")});
}
fn refreshSettled(engine: *em.Engine, owner: c.JSValue, value: c.JSValue, rejected: bool, _: c_int) !void {
    finishRefresh(engine, owner, value, rejected) catch |err| try flow.rejectError(engine, owner, err);
}
fn finishRefresh(engine: *em.Engine, owner: c.JSValue, value: c.JSValue, rejected: bool) !void {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    if (rejected and try publication.nativeReason(&scope, owner, value)) return flow.settle(engine, owner, true, value);
    const caller = try scope.get(owner, "callerSignal");
    if (rejected and !scope.truthy(try scope.get(caller, "aborted"))) return flow.settle(engine, owner, true, value);
    const result = try scope.object();
    try scope.put(result, "aborted", try scope.get(caller, "aborted"));
    const map = try scope.global("Map");
    var args = [_]c.JSValue{try scope.get(owner, "errors")};
    try scope.put(result, "errors", try scope.own(try engine.checked(c.JS_CallConstructor(engine.context, map, args.len, &args))));
    try flow.settle(engine, owner, false, result);
}
fn providerTask(engine: *em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    const pending = try flow.create(engine, roots[0]);
    defer engine.freeValue(pending.owner);
    errdefer engine.freeValue(pending.promise);
    startProvider(engine, pending.owner, arg(args, 0), roots) catch |err| try flow.rejectError(engine, pending.owner, err);
    return pending.promise;
}
fn startProvider(engine: *em.Engine, owner: c.JSValue, provider: c.JSValue, roots: []const c.JSValue) !void {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    try publication.rememberNativeGeneration(&scope, owner);
    inline for (.{ "options", "allowNetwork", "callerSignal", "errors", "imports" }, 1..) |name, index| try scope.put(owner, name, roots[index]);
    try scope.put(owner, "provider", provider);
    const begin = try scope.get(roots[0], "beginProviderRefresh");
    const started = try scope.call(begin, roots[0], &.{try scope.get(provider, "id")});
    const generation = try scope.get(started, "generation");
    const controller = try scope.get(started, "controller");
    const abort = try scope.global("AbortSignal");
    const any = try scope.get(abort, "any");
    const signals = try scope.array();
    try scope.index(signals, 0, roots[3]);
    try scope.index(signals, 1, try scope.get(controller, "signal"));
    const signal = try scope.call(any, abort, &.{signals});
    try scope.put(owner, "controller", controller);
    try scope.put(owner, "signal", signal);
    const operation = try scope.own(try beginOperation(engine, roots[0], provider, generation, signal, roots[1], roots[2]));
    // Source finally begins only after operation IIFE creation and any setup.
    const native_generation = engine.native_allocation_generation;
    const raced = scope.call(try scope.get(roots[5], "raceWithAbortSignal"), c.pi_js_undefined(), &.{ operation, signal }) catch |err| {
        if (err != error.JavaScriptException or engine.nativeAllocationError(err, native_generation) == error.OutOfMemory) return err;
        const reason = try scope.own(flow.reason(engine, err));
        return providerRejected(engine, owner, reason);
    };
    return flow.wait(providerSettled, engine, owner, raced, 0);
}
fn providerSettled(engine: *em.Engine, owner: c.JSValue, value: c.JSValue, rejected: bool, _: c_int) !void {
    if (rejected) return providerRejected(engine, owner, value);
    try finishProvider(engine, owner, false, c.pi_js_undefined());
}
fn providerRejected(engine: *em.Engine, owner: c.JSValue, reason: c.JSValue) !void {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    if (try publication.nativeReason(&scope, owner, reason)) return finishProvider(engine, owner, true, reason);
    recordProviderError(engine, owner, reason) catch |err| {
        if (err != error.JavaScriptException) return err;
        const raw = flow.reason(engine, err);
        defer engine.freeValue(raw);
        return finishProvider(engine, owner, true, raw);
    };
    try finishProvider(engine, owner, false, c.pi_js_undefined());
}
fn recordProviderError(engine: *em.Engine, owner: c.JSValue, reason: c.JSValue) !void {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    if (scope.truthy(try scope.get(try scope.get(owner, "signal"), "aborted"))) return;
    const errors = try scope.get(owner, "errors");
    const set = try scope.get(errors, "set");
    const provider = try scope.get(owner, "provider");
    const id = try scope.get(provider, "id");
    const error_class = try scope.global("Error");
    const instance = c.JS_IsInstanceOf(engine.context, reason, error_class);
    if (instance < 0) return js.capture(engine);
    var failure = reason;
    if (instance == 0) {
        const models_error = try scope.get(try scope.get(owner, "imports"), "ModelsError");
        const code = try scope.text("model_source");
        const message = try scope.concat(try scope.text("Model refresh failed for "), try scope.stringify(try scope.get(provider, "id")));
        const options = try scope.object();
        try scope.put(options, "cause", reason);
        var args = [_]c.JSValue{ code, message, options };
        failure = try scope.own(try engine.checked(c.JS_CallConstructor(engine.context, models_error, args.len, &args)));
    }
    _ = try scope.call(set, errors, &.{ id, failure });
}
fn finishProvider(engine: *em.Engine, owner: c.JSValue, rejected: bool, value: c.JSValue) !void {
    cleanupProvider(engine, owner) catch |err| return flow.rejectError(engine, owner, err);
    try flow.settle(engine, owner, rejected, value);
}
fn cleanupProvider(engine: *em.Engine, owner: c.JSValue) !void {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const receiver = try scope.get(owner, "agent");
    const provider = try scope.get(owner, "provider");
    const controllers = try scope.get(receiver, "refreshControllers");
    const get = try scope.get(controllers, "get");
    if (scope.equal(try scope.call(get, controllers, &.{try scope.get(provider, "id")}), try scope.get(owner, "controller"))) {
        const current_controllers = try scope.get(receiver, "refreshControllers");
        const remove = try scope.get(current_controllers, "delete");
        _ = try scope.call(remove, current_controllers, &.{try scope.get(provider, "id")});
    }
}
const OperationStage = enum(c_int) { credential, cache, auth, network };
fn beginOperation(engine: *em.Engine, receiver: c.JSValue, provider: c.JSValue, generation: c.JSValue, signal: c.JSValue, options: c.JSValue, network: c.JSValue) !c.JSValue {
    const pending = try flow.create(engine, receiver);
    defer engine.freeValue(pending.owner);
    errdefer engine.freeValue(pending.promise);
    startOperation(engine, pending.owner, provider, generation, signal, options, network) catch |err| try flow.rejectError(engine, pending.owner, err);
    return pending.promise;
}
fn startOperation(engine: *em.Engine, owner: c.JSValue, provider: c.JSValue, generation: c.JSValue, signal: c.JSValue, options: c.JSValue, network: c.JSValue) !void {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    try publication.rememberNativeGeneration(&scope, owner);
    inline for (.{ .{ "provider", provider }, .{ "generation", generation }, .{ "signal", signal }, .{ "options", options }, .{ "allowNetwork", network } }) |field| try scope.put(owner, field[0], field[1]);
    try scope.put(owner, "storedCredential", c.pi_js_undefined());
    try scope.put(owner, "credentialError", c.pi_js_undefined());
    const native_generation = engine.native_allocation_generation;
    readOperationCredential(engine, owner) catch |err| {
        if (err != error.JavaScriptException or engine.nativeAllocationError(err, native_generation) == error.OutOfMemory) return err;
        const reason = try scope.own(flow.reason(engine, err));
        try scope.put(owner, "credentialError", reason);
        return runCachePhase(engine, owner);
    };
}
fn readOperationCredential(engine: *em.Engine, owner: c.JSValue) !void {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const receiver = try scope.get(owner, "agent");
    const read = try scope.get(receiver, "readCredential");
    const pending = try scope.call(read, receiver, &.{ try scope.get(try scope.get(owner, "provider"), "id"), try scope.get(owner, "signal") });
    return flow.wait(operationSettled, engine, owner, pending, @intFromEnum(OperationStage.credential));
}
fn operationSettled(engine: *em.Engine, owner: c.JSValue, value: c.JSValue, rejected: bool, stage: c_int) !void {
    operationBody(engine, owner, value, rejected, @enumFromInt(stage)) catch |err| try flow.rejectError(engine, owner, err);
}
fn operationBody(engine: *em.Engine, owner: c.JSValue, value: c.JSValue, rejected: bool, stage: OperationStage) !void {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    if (rejected and try publication.nativeReason(&scope, owner, value)) return flow.settle(engine, owner, true, value);
    if (stage == .credential) {
        try scope.put(owner, if (rejected) "credentialError" else "storedCredential", value);
        return runCachePhase(engine, owner);
    }
    if (rejected) return flow.settle(engine, owner, true, value);
    switch (stage) {
        .credential => unreachable,
        .cache => {
            const credential_error = try scope.get(owner, "credentialError");
            if (!c.JS_IsUndefined(credential_error)) return flow.settle(engine, owner, true, credential_error);
            if (!scope.truthy(try scope.get(owner, "allowNetwork")) or scope.truthy(try scope.get(try scope.get(owner, "signal"), "aborted"))) return flow.settle(engine, owner, false, c.pi_js_undefined());
            const receiver = try scope.get(owner, "agent");
            const resolve = try scope.get(receiver, "resolveRefreshCredential");
            const pending = try scope.call(resolve, receiver, &.{ try scope.get(owner, "provider"), try scope.get(owner, "storedCredential"), try scope.get(owner, "signal") });
            return flow.wait(operationSettled, engine, owner, pending, @intFromEnum(OperationStage.auth));
        },
        .auth => {
            if (!scope.truthy(value)) return flow.settle(engine, owner, false, c.pi_js_undefined());
            const receiver = try scope.get(owner, "agent");
            const run = try scope.get(receiver, "runProviderRefreshPhase");
            const pending = try scope.call(run, receiver, &.{ try scope.get(owner, "provider"), value, c.pi_js_bool(engine.context, 1), try scope.get(try scope.get(owner, "options"), "force"), try scope.get(owner, "generation"), try scope.get(owner, "signal") });
            return flow.wait(operationSettled, engine, owner, pending, @intFromEnum(OperationStage.network));
        },
        .network => try flow.settle(engine, owner, false, c.pi_js_undefined()),
    }
}
fn runCachePhase(engine: *em.Engine, owner: c.JSValue) !void {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const receiver = try scope.get(owner, "agent");
    const run = try scope.get(receiver, "runProviderRefreshPhase");
    const pending = try scope.call(run, receiver, &.{ try scope.get(owner, "provider"), try scope.get(owner, "storedCredential"), c.pi_js_bool(engine.context, 0), c.pi_js_undefined(), try scope.get(owner, "generation"), try scope.get(owner, "signal") });
    return flow.wait(operationSettled, engine, owner, pending, @intFromEnum(OperationStage.cache));
}
