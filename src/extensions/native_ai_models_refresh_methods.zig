//! Actual ModelsImpl refresh bodies. The VM owns one outer Promise per async
//! invocation; every Source await resumes that frame without a flow wrapper.
const em = @import("engine.zig");
const js = @import("native_js_values.zig");
const temp = @import("native_sdk_prompt_scope.zig");
const Scope = temp.Scope;
const af = @import("native_async_function.zig");
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
        .runProviderRefreshPhase => .{"hasKnownModelType"},
        .refresh => .{ "ModelsError", "operationSignal", "raceWithAbortSignal" },
        .resolveRefreshCredential => .{"refreshStoredOAuthCredential"},
    };
    inline for (names) |name| {
        const value = try scope.get(imports, name);
        if (!c.JS_IsFunction(engine.context, value)) return error.RequiredActualModelsRefreshImport;
        try scope.put(captured, name, value);
    }
    const Adapter = struct {
        fn call(host: *em.Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
            return publication.publish(host, receiver, args, roots[0]);
        }
        fn body(host: *em.Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue, state: *c.JSValue, completion: af.Completion, input: c.JSValue) !af.Action {
            return switch (kind) {
                .publishProviderModels => unreachable,
                .runProviderRefreshPhase => publication.phaseBody(host, receiver, args, roots, state, completion, input),
                .refresh => refreshBody(host, receiver, args, roots, state, completion, input),
                .resolveRefreshCredential => credentialBody(host, receiver, args, roots, state, completion, input),
            };
        }
    };
    if (kind == .publishProviderModels) return functions.createMethod(engine, @tagName(kind), 4, Adapter.call, &.{captured});
    return af.createResumable(engine, @tagName(kind), switch (kind) {
        .publishProviderModels => unreachable,
        .runProviderRefreshPhase => 6,
        .refresh => 0,
        .resolveRefreshCredential => 3,
    }, Adapter.body, &.{captured});
}
fn arg(args: []const c.JSValue, index: usize) c.JSValue {
    return if (args.len > index) args[index] else c.pi_js_undefined();
}
fn guestReason(engine: *em.Engine, err: anyerror, generation: u64) !c.JSValue {
    if (err != error.JavaScriptException) return err;
    if (engine.nativeAllocationError(err, generation) == error.OutOfMemory) return error.OutOfMemory;
    return c.JS_DupValue(engine.context, engine.captured_exception orelse return error.ActualGuestExceptionRequired);
}
fn credentialBody(engine: *em.Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue, _: *c.JSValue, completion: af.Completion, input: c.JSValue) !af.Action {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    if (completion == .rejected) return publication.thrown(engine, input);
    if (completion == .fulfilled) {
        if (!scope.truthy(input)) return publication.returned(engine, c.pi_js_undefined());
        const credential = try scope.object();
        try scope.put(credential, "type", try scope.text("api_key"));
        try scope.put(credential, "key", try scope.get(try scope.get(input, "auth"), "apiKey"));
        try scope.put(credential, "env", try scope.get(input, "env"));
        return publication.returned(engine, credential);
    }
    const provider = arg(args, 0);
    const stored = arg(args, 1);
    const signal = arg(args, 2);
    const stored_type = if (temp.nullish(stored)) c.pi_js_undefined() else try scope.get(stored, "type");
    if (scope.equal(stored_type, try scope.text("oauth"))) {
        const oauth = try scope.get(try scope.get(provider, "auth"), "oauth");
        if (!scope.truthy(oauth)) return publication.returned(engine, c.pi_js_undefined());
        const now = try scope.invoke(try scope.global("Date"), "now", &.{});
        if (try arithmetic.compare(engine, .less, now, try scope.get(stored, "expires"))) return publication.returned(engine, stored);
        if (scope.truthy(try scope.get(signal, "aborted"))) return publication.returned(engine, c.pi_js_undefined());
        const refresh = try scope.get(roots[0], "refreshStoredOAuthCredential");
        const credentials = try scope.get(receiver, "credentials");
        const id = try scope.get(provider, "id");
        const should_refresh = try scope.own(try functions.createArrow(engine, "", 1, oauthExpired, &.{}));
        // Source returns this expression directly. There is no intervening
        // await, and the started mutation survives cancellation/supersession.
        return publication.returned(engine, try scope.call(refresh, c.pi_js_undefined(), &.{ credentials, id, oauth, should_refresh, signal }));
    }
    const api_key = try scope.get(try scope.get(provider, "auth"), "apiKey");
    if (!scope.truthy(api_key)) return publication.returned(engine, c.pi_js_undefined());
    const credential = if (!temp.nullish(stored) and scope.equal(try scope.get(stored, "type"), try scope.text("api_key"))) stored else c.pi_js_undefined();
    const resolve = try scope.get(api_key, "resolve");
    const options = try scope.object();
    try scope.put(options, "ctx", try scope.get(receiver, "authContext"));
    try scope.put(options, "credential", credential);
    try scope.put(options, "signal", signal);
    return .{ .awaited = c.JS_DupValue(engine.context, try scope.call(resolve, api_key, &.{options})) };
}
fn oauthExpired(engine: *em.Engine, _: c.JSValue, args: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const now = try scope.invoke(try scope.global("Date"), "now", &.{});
    return arithmetic.binary(engine, .greater_equal, now, try scope.get(arg(args, 0), "expires"));
}
fn outcome(scope: *Scope, aborted: c.JSValue, errors: c.JSValue) !c.JSValue {
    const value = try scope.object();
    try scope.put(value, "aborted", aborted);
    try scope.put(value, "errors", errors);
    return value;
}
fn refreshBody(engine: *em.Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue, slot: *c.JSValue, completion: af.Completion, input: c.JSValue) !af.Action {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    if (completion != .start) return finishRefresh(&scope, slot.*, input, completion == .rejected);
    const owner = try publication.initialize(&scope, slot, receiver);
    const supplied = arg(args, 0);
    const options = if (c.JS_IsUndefined(supplied)) try scope.object() else supplied;
    var network = try scope.get(options, "allowNetwork");
    if (temp.nullish(network)) network = c.pi_js_bool(engine.context, 1);
    const caller = try scope.call(try scope.get(roots[0], "operationSignal"), c.pi_js_undefined(), &.{try scope.get(options, "signal")});
    const errors = try scope.own(try js.builtin(engine, "Map", &.{}));
    if (scope.truthy(try scope.get(caller, "aborted"))) return publication.returned(engine, try outcome(&scope, c.pi_js_bool(engine.context, 1), errors));
    var selected = c.pi_js_undefined();
    if (scope.truthy(try scope.get(options, "providers"))) {
        const set = try scope.global("Set");
        var selected_args = [_]c.JSValue{try scope.get(options, "providers")};
        selected = try scope.own(try engine.checked(c.JS_CallConstructor(engine.context, set, selected_args.len, &selected_args)));
    }
    const array = try scope.global("Array");
    const from = try scope.get(array, "from");
    const providers = try scope.call(from, array, &.{try scope.invoke(try scope.get(receiver, "providers"), "values", &.{})});
    const filter = try scope.get(providers, "filter");
    const predicate = try scope.own(try functions.createArrow(engine, "", 1, refreshable, &.{selected}));
    const eligible = try scope.call(filter, providers, &.{predicate});
    const promise = try scope.global("Promise");
    const all = try scope.get(promise, "all");
    const map = try scope.get(eligible, "map");
    const mapper = try scope.own(try af.createResumableArrow(engine, "", 1, providerBody, &.{ receiver, options, network, caller, errors, roots[0] }, receiver));
    const tasks = try scope.call(map, eligible, &.{mapper});
    const refresh = try scope.call(all, promise, &.{tasks});
    try scope.put(owner, "callerSignal", caller);
    try scope.put(owner, "errors", errors);
    // Source try starts after Promise.all/map and all provider setup above.
    const generation = engine.native_allocation_generation;
    const raced = scope.call(try scope.get(roots[0], "raceWithAbortSignal"), c.pi_js_undefined(), &.{ refresh, caller }) catch |err| {
        const reason = try scope.own(try guestReason(engine, err, generation));
        return finishRefresh(&scope, owner, reason, true);
    };
    return .{ .awaited = c.JS_DupValue(engine.context, raced) };
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
fn finishRefresh(scope: *Scope, owner: c.JSValue, value: c.JSValue, rejected: bool) !af.Action {
    const engine = scope.engine;
    if (rejected) try @import("native_async_body.zig").enterRejectedContinuation(engine);
    const caller = try scope.get(owner, "callerSignal");
    if (rejected and !scope.truthy(try scope.get(caller, "aborted"))) return publication.thrown(engine, value);
    const result = try scope.object();
    try scope.put(result, "aborted", try scope.get(caller, "aborted"));
    const map = try scope.global("Map");
    var args = [_]c.JSValue{try scope.get(owner, "errors")};
    try scope.put(result, "errors", try scope.own(try engine.checked(c.JS_CallConstructor(engine.context, map, args.len, &args))));
    return publication.returned(engine, result);
}
fn providerBody(engine: *em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue, slot: *c.JSValue, completion: af.Completion, input: c.JSValue) !af.Action {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    if (completion != .start) return finishProvider(&scope, slot.*, input, completion == .rejected);
    const owner = try publication.initialize(&scope, slot, roots[0]);
    inline for (.{ "options", "allowNetwork", "callerSignal", "errors", "imports" }, 1..) |name, index| try scope.put(owner, name, roots[index]);
    const provider = arg(args, 0);
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
    const operation_body = try scope.own(try af.createResumableArrow(engine, "", 0, operationBody, &.{ roots[0], provider, generation, signal, roots[1], roots[2] }, roots[0]));
    const operation = try scope.call(operation_body, c.pi_js_undefined(), &.{});
    // The Source try/finally excludes IIFE creation and AbortSignal.any setup.
    const native_generation = engine.native_allocation_generation;
    const raced = scope.call(try scope.get(roots[5], "raceWithAbortSignal"), c.pi_js_undefined(), &.{ operation, signal }) catch |err| {
        const reason = try scope.own(try guestReason(engine, err, native_generation));
        return finishProvider(&scope, owner, reason, true);
    };
    return .{ .awaited = c.JS_DupValue(engine.context, raced) };
}
fn finishProvider(scope: *Scope, owner: c.JSValue, value: c.JSValue, rejected: bool) !af.Action {
    const engine = scope.engine;
    if (rejected) {
        try @import("native_async_body.zig").enterRejectedContinuation(engine);
        const generation = engine.native_allocation_generation;
        recordProviderError(scope, owner, value) catch |err| {
            const reason = try scope.own(try guestReason(engine, err, generation));
            try cleanupProvider(scope, owner);
            return publication.thrown(engine, reason);
        };
    }
    try cleanupProvider(scope, owner);
    return publication.returned(engine, c.pi_js_undefined());
}
fn recordProviderError(scope: *Scope, owner: c.JSValue, reason: c.JSValue) !void {
    const engine = scope.engine;
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
fn cleanupProvider(scope: *Scope, owner: c.JSValue) !void {
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
fn operationBody(engine: *em.Engine, _: c.JSValue, _: []const c.JSValue, roots: []const c.JSValue, slot: *c.JSValue, completion: af.Completion, input: c.JSValue) !af.Action {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    if (completion == .start) {
        const owner = try publication.initialize(&scope, slot, roots[0]);
        inline for (.{ "provider", "generation", "signal", "options", "allowNetwork" }, 1..) |name, index| try scope.put(owner, name, roots[index]);
        try scope.put(owner, "storedCredential", c.pi_js_undefined());
        try scope.put(owner, "credentialError", c.pi_js_undefined());
        const native_generation = engine.native_allocation_generation;
        const pending = readOperationCredential(&scope, owner) catch |err| {
            const reason = try scope.own(try guestReason(engine, err, native_generation));
            try scope.put(owner, "credentialError", reason);
            return runCachePhase(&scope, owner);
        };
        return publication.awaitAt(&scope, owner, pending, @intFromEnum(OperationStage.credential));
    }
    const owner = slot.*;
    if (completion == .rejected) try @import("native_async_body.zig").enterRejectedContinuation(engine);
    const stage: OperationStage = @enumFromInt(try publication.stage(&scope, owner));
    if (stage == .credential) {
        try scope.put(owner, if (completion == .rejected) "credentialError" else "storedCredential", input);
        return runCachePhase(&scope, owner);
    }
    if (completion == .rejected) return publication.thrown(engine, input);
    switch (stage) {
        .credential => unreachable,
        .cache => {
            const credential_error = try scope.get(owner, "credentialError");
            if (!c.JS_IsUndefined(credential_error)) return publication.thrown(engine, credential_error);
            if (!scope.truthy(try scope.get(owner, "allowNetwork")) or scope.truthy(try scope.get(try scope.get(owner, "signal"), "aborted"))) return publication.returned(engine, c.pi_js_undefined());
            const receiver = try scope.get(owner, "agent");
            const resolve = try scope.get(receiver, "resolveRefreshCredential");
            const pending = try scope.call(resolve, receiver, &.{ try scope.get(owner, "provider"), try scope.get(owner, "storedCredential"), try scope.get(owner, "signal") });
            return publication.awaitAt(&scope, owner, pending, @intFromEnum(OperationStage.auth));
        },
        .auth => {
            if (!scope.truthy(input)) return publication.returned(engine, c.pi_js_undefined());
            const receiver = try scope.get(owner, "agent");
            const run = try scope.get(receiver, "runProviderRefreshPhase");
            const pending = try scope.call(run, receiver, &.{ try scope.get(owner, "provider"), input, c.pi_js_bool(engine.context, 1), try scope.get(try scope.get(owner, "options"), "force"), try scope.get(owner, "generation"), try scope.get(owner, "signal") });
            return publication.awaitAt(&scope, owner, pending, @intFromEnum(OperationStage.network));
        },
        .network => return publication.returned(engine, c.pi_js_undefined()),
    }
}
fn readOperationCredential(scope: *Scope, owner: c.JSValue) !c.JSValue {
    const receiver = try scope.get(owner, "agent");
    const read = try scope.get(receiver, "readCredential");
    return scope.call(read, receiver, &.{ try scope.get(try scope.get(owner, "provider"), "id"), try scope.get(owner, "signal") });
}
fn runCachePhase(scope: *Scope, owner: c.JSValue) !af.Action {
    const receiver = try scope.get(owner, "agent");
    const run = try scope.get(receiver, "runProviderRefreshPhase");
    const pending = try scope.call(run, receiver, &.{ try scope.get(owner, "provider"), try scope.get(owner, "storedCredential"), c.pi_js_bool(scope.engine.context, 0), c.pi_js_undefined(), try scope.get(owner, "generation"), try scope.get(owner, "signal") });
    return publication.awaitAt(scope, owner, pending, @intFromEnum(OperationStage.cache));
}
