//! Owner-thread asynchronous provider model refresh. Provider callbacks remain
//! live VM values; publication writes storage before updating provider state.
const std = @import("std");
const sdk = @import("native_sdk.zig");
const engine_mod = @import("engine.zig");
const model_store = @import("native_models_store.zig");
const abort_signal = @import("abort_signal.zig");
const c = engine_mod.c;
const Stage = enum(c_int) { credential, credential_rejected, cache_read, cache_phase, auth, oauth, network_read, network_phase, publication, update, aggregate, rejected, aborted, ignored, race_fulfilled, race_rejected, race_aborted };

pub fn initialize(engine: *engine_mod.Engine, store: c.JSValue, options: c.JSValue) !void {
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    const map = try sdk.get(engine, global, "Map");
    defer engine.freeValue(map);
    inline for (.{ "refreshGenerations", "refreshSignals", "publicationChains" }) |name| try sdk.put(engine, store, name, try engine.checked(c.JS_CallConstructor(engine.context, map, 0, null)));
    const supplied = if (c.JS_IsObject(options)) try sdk.get(engine, options, "modelsStore") else c.pi_js_undefined();
    defer engine.freeValue(supplied);
    if (c.JS_IsObject(supplied)) {
        try sdk.put(engine, store, "modelsStore", c.JS_DupValue(engine.context, supplied));
    } else {
        const temporary = try sdk.object(engine);
        defer engine.freeValue(temporary);
        try model_store.install(engine, temporary);
        const constructor = try sdk.get(engine, temporary, "InMemoryModelsStore");
        defer engine.freeValue(constructor);
        try sdk.put(engine, store, "modelsStore", try engine.checked(c.JS_CallConstructor(engine.context, constructor, 0, null)));
    }
}
fn nativeFunction(engine: *engine_mod.Engine, value: c.JSValue, stage: Stage) !c.JSValue {
    var captured = [_]c.JSValue{value};
    return engine.checked(c.JS_NewCFunctionData2(engine.context, continuation, "nativeModelRefresh", 1, @intFromEnum(stage), 1, &captured));
}
fn adopt(engine: *engine_mod.Engine, value: c.JSValue) !c.JSValue {
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    const promise = try sdk.get(engine, global, "Promise");
    defer engine.freeValue(promise);
    return sdk.invoke(engine, promise, "resolve", &.{value});
}
fn then(engine: *engine_mod.Engine, value: c.JSValue, job: c.JSValue, stage: Stage) !void {
    const pending = try adopt(engine, value);
    defer engine.freeValue(pending);
    const resolved = try nativeFunction(engine, job, stage);
    defer engine.freeValue(resolved);
    const rejected = try nativeFunction(engine, job, if (stage == .credential) .credential_rejected else .rejected);
    defer engine.freeValue(rejected);
    const observed = try sdk.invoke(engine, pending, "then", &.{ resolved, rejected });
    defer engine.freeValue(observed);
    const fallback = try sdk.invoke(engine, observed, "catch", &.{rejected});
    engine.freeValue(fallback);
}
fn capability(engine: *engine_mod.Engine, job: c.JSValue) !c.JSValue {
    var caps: [2]c.JSValue = undefined;
    const result = try engine.checked(c.JS_NewPromiseCapability(engine.context, &caps));
    errdefer engine.freeValue(result);
    defer for (caps) |value| engine.freeValue(value);
    try sdk.put(engine, job, "resolve", c.JS_DupValue(engine.context, caps[0]));
    try sdk.put(engine, job, "reject", c.JS_DupValue(engine.context, caps[1]));
    try sdk.put(engine, job, "closed", c.pi_js_bool(engine.context, 0));
    return result;
}
fn closed(engine: *engine_mod.Engine, job: c.JSValue) !bool {
    const value = try sdk.get(engine, job, "closed");
    defer engine.freeValue(value);
    return c.JS_ToBool(engine.context, value) == 1;
}
fn finish(engine: *engine_mod.Engine, job: c.JSValue, value: c.JSValue, success: bool) !void {
    if (try closed(engine, job)) return;
    try sdk.put(engine, job, "closed", c.pi_js_bool(engine.context, 1));
    const listener = try sdk.get(engine, job, "abortListener");
    defer engine.freeValue(listener);
    if (c.JS_IsFunction(engine.context, listener)) {
        const signal = try sdk.get(engine, job, "signal");
        defer engine.freeValue(signal);
        const event = try sdk.text(engine, "abort");
        defer engine.freeValue(event);
        const ignored = try sdk.invoke(engine, signal, "removeEventListener", &.{ event, listener });
        engine.freeValue(ignored);
        try sdk.put(engine, job, "abortListener", c.pi_js_undefined());
    }
    const provider_owner = try sdk.get(engine, job, "providerOwner");
    defer engine.freeValue(provider_owner);
    if (c.JS_IsObject(provider_owner)) try retireProvider(engine, provider_owner);
    const callback = try sdk.get(engine, job, if (success) "resolve" else "reject");
    defer engine.freeValue(callback);
    var args = [_]c.JSValue{value};
    const result = try engine.checked(c.JS_Call(engine.context, callback, c.pi_js_undefined(), 1, &args));
    engine.freeValue(result);
}
fn operationOptions(engine: *engine_mod.Engine, signal: c.JSValue) !c.JSValue {
    const result = try sdk.object(engine);
    errdefer engine.freeValue(result);
    try sdk.put(engine, result, "signal", c.JS_DupValue(engine.context, signal));
    return result;
}
fn listenStage(engine: *engine_mod.Engine, job: c.JSValue, stage: Stage) !void {
    const signal = try sdk.get(engine, job, "signal");
    defer engine.freeValue(signal);
    const listener = try nativeFunction(engine, job, stage);
    defer engine.freeValue(listener);
    try sdk.put(engine, job, "abortListener", c.JS_DupValue(engine.context, listener));
    const event = try sdk.text(engine, "abort");
    defer engine.freeValue(event);
    const ignored = try sdk.invoke(engine, signal, "addEventListener", &.{ event, listener });
    engine.freeValue(ignored);
}
fn listen(engine: *engine_mod.Engine, job: c.JSValue) !void {
    try listenStage(engine, job, .aborted);
}
pub fn race(engine: *engine_mod.Engine, operation: c.JSValue, signal: c.JSValue, provider_owner: c.JSValue) !c.JSValue {
    const job = try sdk.object(engine);
    defer engine.freeValue(job);
    const result = try capability(engine, job);
    errdefer engine.freeValue(result);
    try sdk.put(engine, job, "signal", c.JS_DupValue(engine.context, signal));
    if (c.JS_IsObject(provider_owner)) try sdk.put(engine, job, "providerOwner", c.JS_DupValue(engine.context, provider_owner));
    const pending = try adopt(engine, operation);
    defer engine.freeValue(pending);
    const fulfilled = try nativeFunction(engine, job, .race_fulfilled);
    defer engine.freeValue(fulfilled);
    const rejected = try nativeFunction(engine, job, .race_rejected);
    defer engine.freeValue(rejected);
    const observed = try sdk.invoke(engine, pending, "then", &.{ fulfilled, rejected });
    defer engine.freeValue(observed);
    const fallback = try sdk.invoke(engine, observed, "catch", &.{rejected});
    engine.freeValue(fallback);
    try listenStage(engine, job, .race_aborted);
    const aborted = try sdk.get(engine, signal, "aborted");
    defer engine.freeValue(aborted);
    if (c.JS_ToBool(engine.context, aborted) == 1) try advance(engine, job, .race_aborted, c.pi_js_undefined());
    return result;
}
fn retireProvider(engine: *engine_mod.Engine, owner: c.JSValue) !void {
    const store = try sdk.get(engine, owner, "store");
    defer engine.freeValue(store);
    const id = try sdk.get(engine, owner, "id");
    defer engine.freeValue(id);
    const own_signal = try sdk.get(engine, owner, "controllerSignal");
    defer engine.freeValue(own_signal);
    const signals = try sdk.get(engine, store, "refreshSignals");
    defer engine.freeValue(signals);
    const current_signal = try sdk.invoke(engine, signals, "get", &.{id});
    defer engine.freeValue(current_signal);
    if (c.JS_IsStrictEqual(engine.context, current_signal, own_signal)) {
        const ignored = try sdk.invoke(engine, signals, "delete", &.{id});
        engine.freeValue(ignored);
    }
}
pub fn supersede(engine: *engine_mod.Engine, store: c.JSValue, id: c.JSValue) !c.JSValue {
    const generations = try sdk.get(engine, store, "refreshGenerations");
    defer engine.freeValue(generations);
    const previous_generation = try sdk.invoke(engine, generations, "get", &.{id});
    defer engine.freeValue(previous_generation);
    var number: f64 = 0;
    if (!c.JS_IsUndefined(previous_generation) and c.JS_ToFloat64(engine.context, &number, previous_generation) < 0) return error.JavaScriptException;
    if (number >= 9007199254740991) return error.NativeSDKRevisionOverflow;
    const next = c.JS_NewFloat64(engine.context, number + 1);
    const set = try sdk.invoke(engine, generations, "set", &.{ id, next });
    engine.freeValue(set);
    const signals = try sdk.get(engine, store, "refreshSignals");
    defer engine.freeValue(signals);
    const previous = try sdk.invoke(engine, signals, "get", &.{id});
    defer engine.freeValue(previous);
    const deleted = try sdk.invoke(engine, signals, "delete", &.{id});
    engine.freeValue(deleted);
    if (c.JS_IsObject(previous)) abort_signal.abort(engine, previous, c.pi_js_undefined()) catch |err| {
        // Native signal delivery prepares its owned listener snapshot before
        // setting aborted. A failed preparation must not invalidate a refresh
        // when the provider replacement itself could not be admitted.
        const aborted = try sdk.get(engine, previous, "aborted");
        defer engine.freeValue(aborted);
        const admitted = try sdk.invoke(engine, generations, "get", &.{id});
        defer engine.freeValue(admitted);
        if (c.JS_ToBool(engine.context, aborted) != 1 and c.JS_IsStrictEqual(engine.context, admitted, next)) {
            const restored = if (c.JS_IsUndefined(previous_generation)) try sdk.invoke(engine, generations, "delete", &.{id}) else try sdk.invoke(engine, generations, "set", &.{ id, previous_generation });
            engine.freeValue(restored);
            const restored_signal = try sdk.invoke(engine, signals, "set", &.{ id, previous });
            engine.freeValue(restored_signal);
        }
        return err;
    };
    return next;
}
fn current(engine: *engine_mod.Engine, job: c.JSValue) !bool {
    const signal = try sdk.get(engine, job, "signal");
    defer engine.freeValue(signal);
    const aborted = try sdk.get(engine, signal, "aborted");
    defer engine.freeValue(aborted);
    if (c.JS_ToBool(engine.context, aborted) == 1) return false;
    const store = try sdk.get(engine, job, "store");
    defer engine.freeValue(store);
    const generations = try sdk.get(engine, store, "refreshGenerations");
    defer engine.freeValue(generations);
    const id = try sdk.get(engine, job, "id");
    defer engine.freeValue(id);
    const latest = try sdk.invoke(engine, generations, "get", &.{id});
    defer engine.freeValue(latest);
    const expected = try sdk.get(engine, job, "generation");
    defer engine.freeValue(expected);
    return c.JS_IsStrictEqual(engine.context, latest, expected);
}
pub fn refresh(engine: *engine_mod.Engine, store: c.JSValue, options: c.JSValue, providers: c.JSValue) !c.JSValue {
    const root = try sdk.object(engine);
    defer engine.freeValue(root);
    const result = try capability(engine, root);
    errdefer engine.freeValue(result);
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    const map = try sdk.get(engine, global, "Map");
    defer engine.freeValue(map);
    const errors = try engine.checked(c.JS_CallConstructor(engine.context, map, 0, null));
    defer engine.freeValue(errors);
    try sdk.put(engine, root, "errors", c.JS_DupValue(engine.context, errors));
    const requested_signal = if (c.JS_IsObject(options)) try sdk.get(engine, options, "signal") else c.pi_js_undefined();
    defer engine.freeValue(requested_signal);
    const signal = if (c.JS_IsObject(requested_signal)) c.JS_DupValue(engine.context, requested_signal) else try abort_signal.create(engine);
    defer engine.freeValue(signal);
    try sdk.put(engine, root, "signal", c.JS_DupValue(engine.context, signal));
    const initially_aborted = try sdk.get(engine, signal, "aborted");
    defer engine.freeValue(initially_aborted);
    // Source returns before reading provider selection or racing Promise.all
    // when the caller has already aborted. The race rejects with the reason;
    // refresh itself reports cancellation in its ordinary aggregate result.
    if (c.JS_ToBool(engine.context, initially_aborted) == 1) {
        try advance(engine, root, .aggregate, c.pi_js_undefined());
        return result;
    }
    try listen(engine, root);
    const pending = try sdk.array(engine);
    defer engine.freeValue(pending);
    const selected = if (c.JS_IsObject(options)) try sdk.get(engine, options, "providers") else c.pi_js_undefined();
    defer engine.freeValue(selected);
    for (0..try sdk.length(engine, providers)) |index| {
        const provider = try engine.checked(c.JS_GetPropertyUint32(engine.context, providers, @intCast(index)));
        defer engine.freeValue(provider);
        const id = try sdk.get(engine, provider, "id");
        defer engine.freeValue(id);
        if (c.JS_IsArray(selected)) {
            const contains = try sdk.invoke(engine, selected, "includes", &.{id});
            defer engine.freeValue(contains);
            if (c.JS_ToBool(engine.context, contains) != 1) continue;
        }
        const callback = try sdk.get(engine, provider, "refreshModels");
        defer engine.freeValue(callback);
        if (!c.JS_IsFunction(engine.context, callback)) continue;
        const job = try sdk.object(engine);
        defer engine.freeValue(job);
        const work = try capability(engine, job);
        defer engine.freeValue(work);
        const generation = try supersede(engine, store, id);
        const own_signal = try abort_signal.create(engine);
        defer engine.freeValue(own_signal);
        const signals = try sdk.get(engine, store, "refreshSignals");
        defer engine.freeValue(signals);
        const set = try sdk.invoke(engine, signals, "set", &.{ id, own_signal });
        engine.freeValue(set);
        const composition = try sdk.array(engine);
        defer engine.freeValue(composition);
        try sdk.append(engine, composition, c.JS_DupValue(engine.context, signal));
        try sdk.append(engine, composition, c.JS_DupValue(engine.context, own_signal));
        const signal_constructor = try sdk.get(engine, global, "AbortSignal");
        defer engine.freeValue(signal_constructor);
        const combined = try sdk.invoke(engine, signal_constructor, "any", &.{composition});
        defer engine.freeValue(combined);
        inline for (.{ .{ "root", root }, .{ "store", store }, .{ "provider", provider }, .{ "id", id }, .{ "signal", combined }, .{ "options", options }, .{ "generation", generation } }) |entry| try sdk.put(engine, job, entry[0], c.JS_DupValue(engine.context, entry[1]));
        try sdk.put(engine, job, "controllerSignal", c.JS_DupValue(engine.context, own_signal));
        try sdk.put(engine, job, "publicationJob", c.pi_js_bool(engine.context, 0));
        const credentials = try sdk.get(engine, store, "credentials");
        defer engine.freeValue(credentials);
        const opts = try operationOptions(engine, combined);
        defer engine.freeValue(opts);
        const read = if (c.JS_IsObject(credentials)) sdk.invoke(engine, credentials, "read", &.{ id, opts }) catch |err| failed: {
            if (err != error.JavaScriptException) return err;
            try rememberCredentialFailure(engine, job, engine.captured_exception.?);
            break :failed c.pi_js_undefined();
        } else c.pi_js_undefined();
        defer engine.freeValue(read);
        try then(engine, read, job, .credential);
        const raced = try race(engine, work, combined, job);
        defer engine.freeValue(raced);
        const ignored = try nativeFunction(engine, job, .ignored);
        defer engine.freeValue(ignored);
        try sdk.append(engine, pending, try sdk.invoke(engine, raced, "catch", &.{ignored}));
    }
    const promise = try sdk.get(engine, global, "Promise");
    defer engine.freeValue(promise);
    const all = try sdk.invoke(engine, promise, "all", &.{pending});
    defer engine.freeValue(all);
    // Source Models.refresh awaits raceWithAbortSignal(Promise.all(...)),
    // including an empty provider set. Preserve that reaction boundary before
    // publishing the aggregate and ModelRuntime's next model snapshot.
    const raced = try race(engine, all, signal, c.pi_js_undefined());
    defer engine.freeValue(raced);
    try then(engine, raced, root, .aggregate);
    return result;
}
fn continuation(context: ?*c.JSContext, _: c.JSValue, argc: c_int, args: [*c]c.JSValue, raw_stage: c_int, captured: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = engine_mod.Engine.fromContext(context.?);
    const job = captured[0];
    advance(engine, job, @enumFromInt(raw_stage), if (argc > 0) args[0] else c.pi_js_undefined()) catch |err| {
        _ = sdk.fail(engine, err);
        const failure = c.JS_GetException(context);
        defer engine.freeValue(failure);
        advance(engine, job, .rejected, failure) catch return c.JS_Throw(context, c.JS_DupValue(context, failure));
    };
    return c.pi_js_undefined();
}
fn advance(engine: *engine_mod.Engine, job: c.JSValue, stage: Stage, value: c.JSValue) !void {
    if (stage == .ignored) return;
    if (try closed(engine, job)) return;
    if (stage == .race_fulfilled or stage == .race_rejected) return finish(engine, job, value, stage == .race_fulfilled);
    if (stage == .race_aborted) {
        const signal = try sdk.get(engine, job, "signal");
        defer engine.freeValue(signal);
        const reason = try sdk.get(engine, signal, "reason");
        defer engine.freeValue(reason);
        return finish(engine, job, reason, false);
    }
    if (stage == .credential_rejected) {
        try rememberCredentialFailure(engine, job, value);
        return advance(engine, job, .credential, c.pi_js_undefined());
    }
    if (stage == .aborted) {
        const root = try sdk.get(engine, job, "root");
        defer engine.freeValue(root);
        const publication_job = try sdk.get(engine, job, "publicationJob");
        defer engine.freeValue(publication_job);
        if (c.JS_ToBool(engine.context, publication_job) == 1) {
            const signal = try sdk.get(engine, job, "signal");
            defer engine.freeValue(signal);
            const reason = try sdk.get(engine, signal, "reason");
            defer engine.freeValue(reason);
            return finish(engine, job, reason, false);
        }
        if (c.JS_IsUndefined(root)) return advance(engine, job, .aggregate, c.pi_js_undefined());
        return finish(engine, job, c.pi_js_undefined(), true);
    }
    if (stage == .aggregate) {
        const result = try sdk.object(engine);
        defer engine.freeValue(result);
        const signal = try sdk.get(engine, job, "signal");
        defer engine.freeValue(signal);
        try sdk.put(engine, result, "aborted", try sdk.get(engine, signal, "aborted"));
        const errors = try sdk.get(engine, job, "errors");
        defer engine.freeValue(errors);
        const global = c.JS_GetGlobalObject(engine.context);
        defer engine.freeValue(global);
        const map = try sdk.get(engine, global, "Map");
        defer engine.freeValue(map);
        var entries = [_]c.JSValue{errors};
        try sdk.put(engine, result, "errors", try engine.checked(c.JS_CallConstructor(engine.context, map, 1, &entries)));
        return finish(engine, job, result, true);
    }
    if (stage == .rejected) {
        const publication_job = try sdk.get(engine, job, "publicationJob");
        defer engine.freeValue(publication_job);
        if (c.JS_ToBool(engine.context, publication_job) == 1) return finish(engine, job, value, false);
        const root = try sdk.get(engine, job, "root");
        defer engine.freeValue(root);
        if (c.JS_IsUndefined(root)) {
            const caller_signal = try sdk.get(engine, job, "signal");
            defer engine.freeValue(caller_signal);
            const caller_aborted = try sdk.get(engine, caller_signal, "aborted");
            defer engine.freeValue(caller_aborted);
            if (c.JS_ToBool(engine.context, caller_aborted) == 1) return advance(engine, job, .aggregate, c.pi_js_undefined());
            return finish(engine, job, value, false);
        }
        const errors = try sdk.get(engine, root, "errors");
        defer engine.freeValue(errors);
        const id = try sdk.get(engine, job, "id");
        defer engine.freeValue(id);
        const signal = try sdk.get(engine, job, "signal");
        defer engine.freeValue(signal);
        const aborted = try sdk.get(engine, signal, "aborted");
        defer engine.freeValue(aborted);
        if (c.JS_ToBool(engine.context, aborted) != 1) {
            const store = try sdk.get(engine, job, "store");
            defer engine.freeValue(store);
            const wrapped = if (c.JS_IsError(value)) c.JS_DupValue(engine.context, value) else wrap: {
                const provider_id = try engine.toString(id);
                defer engine.gpa.free(provider_id);
                const message = try std.fmt.allocPrint(engine.gpa, "Model refresh failed for {s}", .{provider_id});
                defer engine.gpa.free(message);
                break :wrap try @import("native_models.zig").fromCause(engine, store, "model_source", message, value);
            };
            defer engine.freeValue(wrapped);
            const ignored = try sdk.invoke(engine, errors, "set", &.{ id, wrapped });
            engine.freeValue(ignored);
        }
        return finish(engine, job, c.pi_js_undefined(), true);
    }
    const store = try sdk.get(engine, job, "store");
    defer engine.freeValue(store);
    const id = try sdk.get(engine, job, "id");
    defer engine.freeValue(id);
    const signal = try sdk.get(engine, job, "signal");
    defer engine.freeValue(signal);
    const aborted = try sdk.get(engine, signal, "aborted");
    defer engine.freeValue(aborted);
    if (stage == .credential or stage == .auth or stage == .oauth) {
        if (stage == .oauth and !c.JS_IsObject(value)) return finish(engine, job, c.pi_js_undefined(), true);
        const credential = if (stage == .credential or stage == .oauth) c.JS_DupValue(engine.context, value) else resolved: {
            if (!c.JS_IsObject(value)) return finish(engine, job, c.pi_js_undefined(), true);
            const auth = try sdk.get(engine, value, "auth");
            defer engine.freeValue(auth);
            const key = try sdk.get(engine, auth, "apiKey");
            defer engine.freeValue(key);
            const output = try sdk.object(engine);
            errdefer engine.freeValue(output);
            try sdk.put(engine, output, "type", try sdk.text(engine, "api_key"));
            try sdk.put(engine, output, "key", c.JS_DupValue(engine.context, key));
            try sdk.put(engine, output, "env", try sdk.get(engine, value, "env"));
            break :resolved output;
        };
        defer engine.freeValue(credential);
        try sdk.put(engine, job, "credential", c.JS_DupValue(engine.context, credential));
        const backend = try sdk.get(engine, store, "modelsStore");
        defer engine.freeValue(backend);
        const opts = try operationOptions(engine, signal);
        defer engine.freeValue(opts);
        const read = try sdk.invoke(engine, backend, "read", &.{ id, opts });
        defer engine.freeValue(read);
        return then(engine, read, job, if (stage == .credential) .cache_read else .network_read);
    }
    if (stage == .cache_read or stage == .network_read) return phase(engine, job, value, stage == .network_read);
    if (stage == .cache_phase) {
        const credential_error = try sdk.get(engine, job, "credentialError");
        defer engine.freeValue(credential_error);
        if (!c.JS_IsUndefined(credential_error)) return advance(engine, job, .rejected, credential_error);
        const options = try sdk.get(engine, job, "options");
        defer engine.freeValue(options);
        const allow = if (c.JS_IsObject(options)) try sdk.get(engine, options, "allowNetwork") else c.pi_js_undefined();
        defer engine.freeValue(allow);
        if (c.JS_ToBool(engine.context, aborted) == 1 or (!c.JS_IsUndefined(allow) and !c.JS_IsNull(allow) and c.JS_ToBool(engine.context, allow) != 1)) return finish(engine, job, c.pi_js_undefined(), true);
        const provider = try sdk.get(engine, job, "provider");
        defer engine.freeValue(provider);
        const credential = try sdk.get(engine, job, "credential");
        defer engine.freeValue(credential);
        const kind = if (c.JS_IsObject(credential)) try sdk.get(engine, credential, "type") else c.pi_js_undefined();
        defer engine.freeValue(kind);
        const oauth_type = try sdk.text(engine, "oauth");
        defer engine.freeValue(oauth_type);
        if (c.JS_IsStrictEqual(engine.context, kind, oauth_type)) {
            const pending = try @import("native_models_oauth_refresh.zig").resolve(engine, store, provider, credential, signal);
            defer engine.freeValue(pending);
            return then(engine, pending, job, .oauth);
        }
        const auth = try sdk.get(engine, provider, "auth");
        defer engine.freeValue(auth);
        const api = try sdk.get(engine, auth, "apiKey");
        defer engine.freeValue(api);
        if (!c.JS_IsObject(api)) return finish(engine, job, c.pi_js_undefined(), true);
        const context = try sdk.object(engine);
        defer engine.freeValue(context);
        const api_type = try sdk.text(engine, "api_key");
        defer engine.freeValue(api_type);
        try sdk.put(engine, context, "credential", if (c.JS_IsStrictEqual(engine.context, kind, api_type)) c.JS_DupValue(engine.context, credential) else c.pi_js_undefined());
        try sdk.put(engine, context, "ctx", try sdk.get(engine, store, "authContext"));
        try sdk.put(engine, context, "signal", c.JS_DupValue(engine.context, signal));
        const resolved = try sdk.invoke(engine, api, "resolve", &.{context});
        defer engine.freeValue(resolved);
        return then(engine, resolved, job, .auth);
    }
    if (stage == .network_phase) return finish(engine, job, c.pi_js_undefined(), true);
    if (stage == .publication) {
        if (!try current(engine, job)) return finish(engine, job, c.pi_js_bool(engine.context, 0), true);
        const publication_value = try sdk.get(engine, job, "publication");
        defer engine.freeValue(publication_value);
        const persist = try sdk.get(engine, publication_value, "persist");
        defer engine.freeValue(persist);
        const opts = try operationOptions(engine, signal);
        defer engine.freeValue(opts);
        const backend = try sdk.get(engine, store, "modelsStore");
        defer engine.freeValue(backend);
        const mutation = if (c.JS_IsUndefined(persist)) c.pi_js_undefined() else if (c.JS_IsNull(persist)) try sdk.invoke(engine, backend, "delete", &.{ id, opts }) else write: {
            const cloned = try model_store.clone(engine, persist);
            defer engine.freeValue(cloned);
            break :write try sdk.invoke(engine, backend, "write", &.{ id, cloned, opts });
        };
        defer engine.freeValue(mutation);
        return then(engine, mutation, job, .update);
    }
    if (stage == .update) {
        if (!try current(engine, job)) return finish(engine, job, c.pi_js_bool(engine.context, 0), true);
        const publication_value = try sdk.get(engine, job, "publication");
        defer engine.freeValue(publication_value);
        const update = try sdk.get(engine, publication_value, "update");
        defer engine.freeValue(update);
        if (c.JS_IsFunction(engine.context, update)) {
            const ignored = try engine.checked(c.JS_Call(engine.context, update, c.pi_js_undefined(), 0, null));
            engine.freeValue(ignored);
        }
        return finish(engine, job, c.pi_js_bool(engine.context, 1), true);
    }
    return error.NativeModelRefreshStage;
}
fn rememberCredentialFailure(engine: *engine_mod.Engine, job: c.JSValue, failure: c.JSValue) !void {
    const store = try sdk.get(engine, job, "store");
    defer engine.freeValue(store);
    const id = try sdk.get(engine, job, "id");
    defer engine.freeValue(id);
    const provider_id = try engine.toString(id);
    defer engine.gpa.free(provider_id);
    const message = try std.fmt.allocPrint(engine.gpa, "Credential store read failed for {s}", .{provider_id});
    defer engine.gpa.free(message);
    try sdk.put(engine, job, "credentialError", try @import("native_models.zig").fromCause(engine, store, "auth", message, failure));
}
fn phase(engine: *engine_mod.Engine, job: c.JSValue, entry: c.JSValue, network: bool) !void {
    const context = try sdk.object(engine);
    defer engine.freeValue(context);
    try sdk.put(engine, context, "allowNetwork", c.pi_js_bool(engine.context, @intFromBool(network)));
    try sdk.put(engine, context, "signal", try sdk.get(engine, job, "signal"));
    try sdk.put(engine, context, "credential", try sdk.get(engine, job, "credential"));
    const options = try sdk.get(engine, job, "options");
    defer engine.freeValue(options);
    try sdk.put(engine, context, "force", if (network and c.JS_IsObject(options)) try sdk.get(engine, options, "force") else c.pi_js_undefined());
    const stored = try model_store.clone(engine, entry);
    defer engine.freeValue(stored);
    if (c.JS_IsObject(stored)) {
        const rows = try sdk.get(engine, stored, "models");
        defer engine.freeValue(rows);
        const known = try sdk.array(engine);
        defer engine.freeValue(known);
        for (0..try sdk.length(engine, rows)) |index| {
            const row = try engine.checked(c.JS_GetPropertyUint32(engine.context, rows, @intCast(index)));
            defer engine.freeValue(row);
            const type_value = try sdk.get(engine, row, "type");
            defer engine.freeValue(type_value);
            var accepted = c.JS_IsUndefined(type_value);
            inline for (.{ "chat", "image", "classifier" }) |name| {
                const expected = try sdk.text(engine, name);
                defer engine.freeValue(expected);
                accepted = accepted or c.JS_IsStrictEqual(engine.context, type_value, expected);
            }
            if (accepted) try sdk.append(engine, known, c.JS_DupValue(engine.context, row));
        }
        try sdk.put(engine, stored, "models", c.JS_DupValue(engine.context, known));
    }
    try sdk.put(engine, context, "stored", c.JS_DupValue(engine.context, stored));
    var captured = [_]c.JSValue{job};
    try sdk.put(engine, context, "publish", try engine.checked(c.JS_NewCFunctionData2(engine.context, publish, "publish", 1, 0, 1, &captured)));
    const provider = try sdk.get(engine, job, "provider");
    defer engine.freeValue(provider);
    const refreshed = try sdk.invoke(engine, provider, "refreshModels", &.{context});
    defer engine.freeValue(refreshed);
    try then(engine, refreshed, job, if (network) .network_phase else .cache_phase);
}
fn publish(context: ?*c.JSContext, _: c.JSValue, argc: c_int, args: [*c]c.JSValue, _: c_int, captured: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = engine_mod.Engine.fromContext(context.?);
    return publication(engine, captured[0], if (argc > 0) args[0] else c.pi_js_undefined()) catch |err| sdk.fail(engine, err);
}
fn publication(engine: *engine_mod.Engine, owner: c.JSValue, value: c.JSValue) !c.JSValue {
    const job = try sdk.object(engine);
    defer engine.freeValue(job);
    const result = try capability(engine, job);
    errdefer engine.freeValue(result);
    inline for (.{ "store", "id", "signal", "generation" }) |name| try sdk.put(engine, job, name, try sdk.get(engine, owner, name));
    try sdk.put(engine, job, "publicationJob", c.pi_js_bool(engine.context, 1));
    try sdk.put(engine, job, "publication", c.JS_DupValue(engine.context, value));
    const store = try sdk.get(engine, job, "store");
    defer engine.freeValue(store);
    const id = try sdk.get(engine, job, "id");
    defer engine.freeValue(id);
    const chains = try sdk.get(engine, store, "publicationChains");
    defer engine.freeValue(chains);
    const previous = try sdk.invoke(engine, chains, "get", &.{id});
    defer engine.freeValue(previous);
    const ignored = try nativeFunction(engine, job, .ignored);
    defer engine.freeValue(ignored);
    const pending = try adopt(engine, previous);
    defer engine.freeValue(pending);
    const observed = try sdk.invoke(engine, pending, "catch", &.{ignored});
    defer engine.freeValue(observed);
    const tail = try sdk.invoke(engine, result, "catch", &.{ignored});
    defer engine.freeValue(tail);
    const set = try sdk.invoke(engine, chains, "set", &.{ id, tail });
    engine.freeValue(set);
    try then(engine, observed, job, .publication);
    const signal = try sdk.get(engine, job, "signal");
    defer engine.freeValue(signal);
    const raced = try race(engine, result, signal, c.pi_js_undefined());
    engine.freeValue(result);
    return raced;
}

test "native model refresh retained publications aggregate abort matches Source before selection and during work" {
    const engine = try engine_mod.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    try abort_signal.install(engine);
    const exports = try sdk.object(engine);
    defer engine.freeValue(exports);
    try @import("native_models.zig").populateExports(engine, exports);
    try engine.registerValueModule("@earendil-works/pi-ai", exports);
    const Report = struct {
        fn log(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue) callconv(.c) c.JSValue {
            const global = c.JS_GetGlobalObject(context);
            defer c.JS_FreeValue(context, global);
            if (argc > 0 and c.JS_SetPropertyStr(context, global, "abortProof", c.JS_DupValue(context, argv[0])) < 0) return c.JS_Throw(context, c.JS_GetException(context));
            return c.pi_js_undefined();
        }
    };
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    const console = try sdk.object(engine);
    defer engine.freeValue(console);
    try sdk.put(engine, console, "log", try engine.checked(c.JS_NewCFunction(engine.context, Report.log, "log", 1)));
    try sdk.put(engine, global, "console", c.JS_DupValue(engine.context, console));
    const Fixture = struct { schemaVersion: u32, sourceCommit: []const u8, inputSha256: []const u8, input: []const u8 };
    var parsed = try std.json.parseFromSlice(Fixture, std.testing.allocator, @embedFile("fixtures/sdk-model-refresh-abort-6fb2e78.input.json"), .{});
    defer parsed.deinit();
    const module = try engine.evalModule(parsed.value.input, "sdk-model-refresh-abort.mjs");
    defer engine.freeValue(module);
    const proof = try sdk.get(engine, global, "abortProof");
    defer engine.freeValue(proof);
    const actual = try engine.toString(proof);
    defer engine.gpa.free(actual);
    try std.testing.expectEqualStrings(std.mem.trim(u8, @embedFile("fixtures/sdk-model-refresh-abort-6fb2e78.json"), "\r\n"), actual);
}

test "native model refresh retained publications signals store roots and GC release failed host allocations" {
    const Probe = struct {
        fn report(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue) callconv(.c) c.JSValue {
            const global = c.JS_GetGlobalObject(context);
            defer c.JS_FreeValue(context, global);
            if (argc > 0 and c.JS_SetPropertyStr(context, global, "refreshProof", c.JS_DupValue(context, argv[0])) < 0) return c.JS_Throw(context, c.JS_GetException(context));
            return c.pi_js_undefined();
        }
        fn exercise(gpa: std.mem.Allocator) !void {
            const engine = try engine_mod.Engine.init(gpa, .{});
            defer engine.deinit();
            try abort_signal.install(engine);
            const exports = try sdk.object(engine);
            defer engine.freeValue(exports);
            try @import("native_models.zig").populateExports(engine, exports);
            try engine.registerValueModule("@earendil-works/pi-ai", exports);
            const global = c.JS_GetGlobalObject(engine.context);
            defer engine.freeValue(global);
            const console = try sdk.object(engine);
            defer engine.freeValue(console);
            try sdk.put(engine, console, "log", try engine.checked(c.JS_NewCFunction(engine.context, report, "log", 1)));
            try sdk.put(engine, global, "console", c.JS_DupValue(engine.context, console));
            const Fixture = struct { schemaVersion: u32, sourceCommit: []const u8, inputSha256: []const u8, input: []const u8 };
            var parsed = try std.json.parseFromSlice(Fixture, gpa, @embedFile("fixtures/sdk-model-refresh-races-7fb59f9.input.json"), .{});
            defer parsed.deinit();
            const evaluated = try engine.evalModule(parsed.value.input, "refresh-allocation-probe.mjs");
            defer engine.freeValue(evaluated);
            const settled = try engine.awaitValue(evaluated);
            defer engine.freeValue(settled);
            const proof = try sdk.get(engine, global, "refreshProof");
            defer engine.freeValue(proof);
            const actual = try engine.toString(proof);
            defer gpa.free(actual);
            try std.testing.expectEqualStrings(std.mem.trim(u8, @embedFile("fixtures/sdk-model-refresh-races-7fb59f9.json"), "\r\n"), actual);
            c.JS_RunGC(engine.runtime);
        }
        fn run(gpa: std.mem.Allocator) !void {
            exercise(gpa) catch |err| {
                const failing: *std.testing.FailingAllocator = @ptrCast(@alignCast(gpa.ptr));
                if (failing.has_induced_failure and (err == error.JavaScriptException or err == error.OutOfMemory)) return error.OutOfMemory;
                std.debug.print("Refresh allocation probe: {s}; induced={any}; index={d}\n", .{ @errorName(err), failing.has_induced_failure, failing.alloc_index });
                if (failing.has_induced_failure) {
                    const trace = failing.getStackTrace();
                    std.debug.dumpStackTrace(&trace);
                }
                return err;
            };
            const failing: *std.testing.FailingAllocator = @ptrCast(@alignCast(gpa.ptr));
            if (failing.has_induced_failure) return error.OutOfMemory;
        }
    };
    try std.testing.checkAllAllocationFailures(std.testing.allocator, Probe.run, .{});
}

test "native model refresh retained publications replacement OOM preserves old generation and provider" {
    var failing = std.testing.FailingAllocator.init(std.testing.allocator, .{});
    const engine = try engine_mod.Engine.init(failing.allocator(), .{});
    defer engine.deinit();
    try abort_signal.install(engine);
    const exports = try sdk.object(engine);
    defer engine.freeValue(exports);
    try @import("native_models.zig").populateExports(engine, exports);
    try engine.registerValueModule("refresh-admission", exports);
    const module = try engine.evalModule(
        \\import {createModels} from 'refresh-admission';let release,enter,updated=0;const entered=new Promise(resolve=>enter=resolve);export const models=createModels();export const old={id:'p',getModels:()=>[],async refreshModels(ctx){enter();await new Promise(resolve=>release=resolve);await ctx.publish({update(){updated++}})}};models.setProvider(old);export const work=models.refresh({allowNetwork:false});await entered;export function replace(){models.setProvider({id:'p',getModels:()=>[]})}export function resume(){release()}export function count(){return updated}
    , "refresh-admission.mjs");
    defer engine.freeValue(module);
    const old = try sdk.get(engine, module, "old");
    defer engine.freeValue(old);
    const models_value = try sdk.get(engine, module, "models");
    defer engine.freeValue(models_value);
    failing.fail_index = failing.alloc_index;
    const rejected = sdk.invoke(engine, module, "replace", &.{});
    if (rejected) |value| {
        engine.freeValue(value);
        return error.ExpectedReplacementAllocationFailure;
    } else |err| try std.testing.expect(err == error.JavaScriptException or err == error.OutOfMemory);
    try std.testing.expect(failing.has_induced_failure);
    failing.fail_index = std.math.maxInt(usize);
    engine.beginInvocation();
    const id = try sdk.text(engine, "p");
    defer engine.freeValue(id);
    const admitted = try sdk.invoke(engine, models_value, "getProvider", &.{id});
    defer engine.freeValue(admitted);
    try std.testing.expect(c.JS_IsStrictEqual(engine.context, admitted, old));
    const resumed = try sdk.invoke(engine, module, "resume", &.{});
    engine.freeValue(resumed);
    const work = try sdk.get(engine, module, "work");
    defer engine.freeValue(work);
    const settled = try engine.awaitValue(work);
    defer engine.freeValue(settled);
    const errors = try sdk.get(engine, settled, "errors");
    defer engine.freeValue(errors);
    const size = try sdk.get(engine, errors, "size");
    defer engine.freeValue(size);
    var count: i32 = 0;
    if (c.JS_ToInt32(engine.context, &count, size) < 0) return error.JavaScriptException;
    try std.testing.expectEqual(@as(i32, 0), count);
    const updates = try sdk.invoke(engine, module, "count", &.{});
    defer engine.freeValue(updates);
    if (c.JS_ToInt32(engine.context, &count, updates) < 0) return error.JavaScriptException;
    try std.testing.expectEqual(@as(i32, 1), count);
    c.JS_RunGC(engine.runtime);
}
