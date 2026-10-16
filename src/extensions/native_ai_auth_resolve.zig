//! Actual auth/resolve.ts, Source4954. Captures canonical imports once; all
//! stores, providers, credentials, context values and errors remain VM values.
const std = @import("std");
const v = @import("native_ai_provider_values.zig");
const Scope = v.Scope;
const c = v.c;
const functions = @import("native_node_function.zig");
const flow = @import("native_agent_async.zig");
const arithmetic = @import("native_image_arithmetic.zig");
const cache_key = "\x00actual-auth-resolve-namespace";
const Stage = enum(c_int) { read, read_helper, api, refreshed, derived, modified, refresh_callback, overlay_env };
fn arg(args: []const c.JSValue, i: usize) c.JSValue {
    return if (i < args.len) args[i] else c.pi_js_undefined();
}
fn imported(s: *Scope, imports: c.JSValue, name: [*:0]const u8, args: []const c.JSValue) !c.JSValue {
    return s.call(try s.get(imports, name), c.pi_js_undefined(), args);
}
fn wait(s: *Scope, job: c.JSValue, value: c.JSValue, stage: Stage) !void {
    try flow.wait(continued, s.engine, job, value, @intFromEnum(stage));
}
fn resolve(s: *Scope, job: c.JSValue, value: c.JSValue) !void {
    try flow.settle(s.engine, job, false, value);
}
fn reject(s: *Scope, job: c.JSValue, value: c.JSValue) !void {
    try flow.settle(s.engine, job, true, value);
}
fn arrow(s: *Scope, callback: functions.Callback, arity: c_int, roots: []const c.JSValue, is_async: bool) !c.JSValue {
    const out = try s.own(try functions.createArrow(s.engine, "", arity, callback, roots));
    if (is_async) {
        const prototype = try s.own(try s.engine.checked(c.JS_GetAsyncFunctionPrototype(s.engine.context)));
        if (c.JS_SetPrototype(s.engine.context, out, prototype) < 0) return v.js.capture(s.engine);
    }
    return out;
}
fn errorValue(s: *Scope, job: c.JSValue, code: []const u8, prefix: []const u8, cause: ?c.JSValue) !c.JSValue {
    const message = try s.concat(try s.text(prefix), try s.stringify(try s.get(job, "id")));
    const options = if (cause) |raw| blk: {
        const out = try s.object();
        try s.put(out, "cause", raw);
        break :blk out;
    } else c.pi_js_undefined();
    const constructor = try s.get(try s.get(job, "imports"), "ModelsError");
    var args = [_]c.JSValue{ try s.text(code), message, options };
    return s.own(try s.engine.checked(c.JS_CallConstructor(s.engine.context, constructor, args.len, &args)));
}
fn failWrapped(s: *Scope, job: c.JSValue, code: []const u8, prefix: []const u8, cause: c.JSValue) !void {
    try reject(s, job, try errorValue(s, job, code, prefix, cause));
}
/// The public ModelsError export is the exact supplied canonical constructor.
/// operationSignal/raceWithAbortSignal come from ONE shared actual abort module.
pub fn create(engine: *v.em.Engine, imports: c.JSValue) !c.JSValue {
    if (engine.native_module_values.get(cache_key)) |cached| return c.JS_DupValue(engine.context, cached);
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    const captured = try s.object();
    inline for (.{ "ModelsError", "operationSignal", "raceWithAbortSignal" }) |name| {
        const binding = try s.get(imports, name);
        if (!c.JS_IsFunction(engine.context, binding)) return error.RequiredActualAuthResolveDependency;
        if (comptime std.mem.eql(u8, name, "ModelsError")) if (!c.JS_IsConstructor(engine.context, binding)) return error.RequiredCanonicalModelsError;
        try s.put(captured, name, binding);
    }
    const exports = try s.object();
    try s.put(exports, "resolveProviderAuth", try s.own(try functions.create(engine, "resolveProviderAuth", 4, resolveProviderAuth, &.{captured})));
    const refresh = try s.own(try functions.createMethod(engine, "refreshStoredOAuthCredential", 5, refreshStoredOAuthCredential, &.{captured}));
    const prototype = try s.own(try engine.checked(c.JS_GetAsyncFunctionPrototype(engine.context)));
    if (c.JS_SetPrototype(engine.context, refresh, prototype) < 0) return v.js.capture(engine);
    try s.put(exports, "refreshStoredOAuthCredential", refresh);
    try s.put(exports, "ModelsError", try s.get(captured, "ModelsError"));
    const retained = c.JS_DupValue(engine.context, exports);
    engine.native_module_values.put(engine.gpa, cache_key, retained) catch |err| {
        engine.freeValue(retained);
        return err;
    };
    return c.JS_DupValue(engine.context, exports);
}
fn resolveProviderAuth(engine: *v.em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    const imports = roots[0];
    const signal = try imported(&s, imports, "operationSignal", &.{try v.optional(&s, arg(args, 3), "signal")});
    // The lexical race callee is evaluated before starting the inner async body.
    const race = try s.get(imports, "raceWithAbortSignal");
    const pending = try flow.create(engine, c.pi_js_undefined());
    defer engine.freeValue(pending.owner);
    defer engine.freeValue(pending.promise);
    const job = pending.owner;
    try s.put(job, "imports", imports);
    try s.put(job, "signal", signal);
    inline for (.{ "provider", "credentials", "authContext", "overrides" }, 0..) |name, index| try s.put(job, name, arg(args, index));
    beginResolve(&s, job) catch |err| try flow.rejectError(engine, job, err);
    return c.JS_DupValue(engine.context, try s.call(race, c.pi_js_undefined(), &.{ pending.promise, signal }));
}
fn overlayEnv(engine: *v.em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    const pending = try flow.create(engine, c.pi_js_undefined());
    defer engine.freeValue(pending.owner);
    errdefer engine.freeValue(pending.promise);
    overlayEnvBody(&s, pending.owner, arg(args, 0), roots) catch |err| try flow.rejectError(engine, pending.owner, err);
    return pending.promise;
}
fn overlayEnvBody(s: *Scope, job: c.JSValue, name: c.JSValue, roots: []const c.JSValue) !void {
    const local = try s.own(try v.js.getKey(s.engine, roots[1], name));
    if (s.truthy(local)) return resolve(s, job, local);
    try wait(s, job, try s.invoke(roots[0], "env", &.{name}), .overlay_env);
}
fn overlayFile(engine: *v.em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    return c.JS_DupValue(engine.context, try s.invoke(roots[0], "fileExists", &.{arg(args, 0)}));
}
fn overlay(s: *Scope, base: c.JSValue, env: c.JSValue) !c.JSValue {
    const out = try s.object();
    try s.put(out, "env", try arrow(s, overlayEnv, 1, &.{ base, env }, true));
    try s.put(out, "fileExists", try arrow(s, overlayFile, 1, &.{base}, false));
    return out;
}
fn beginResolve(s: *Scope, job: c.JSValue) !void {
    const signal = try s.get(job, "signal");
    _ = try s.invoke(signal, "throwIfAborted", &.{});
    const overrides = try s.get(job, "overrides");
    const base = try s.get(job, "authContext");
    const context = if (s.truthy(try v.optional(s, overrides, "env"))) try overlay(s, base, try s.get(overrides, "env")) else base;
    try s.put(job, "requestAuthContext", context);
    const provider = try s.get(job, "provider");
    if (!c.JS_IsUndefined(try v.optional(s, overrides, "apiKey")) and s.truthy(try s.get(try s.get(provider, "auth"), "apiKey"))) {
        const api = try s.get(try s.get(provider, "auth"), "apiKey");
        const id = try s.get(provider, "id");
        const credential = try s.object();
        try s.put(credential, "type", try s.text("api_key"));
        try s.put(credential, "key", try s.get(overrides, "apiKey"));
        try s.put(credential, "env", try s.get(overrides, "env"));
        try s.put(job, "id", id);
        return apiResolve(s, job, api, credential);
    }
    const store = try s.get(job, "credentials");
    const id = try s.get(provider, "id");
    try s.put(job, "id", id);
    // readCredential is an async helper that is itself awaited by the caller.
    // Keep both Promise boundaries; collapsing them changes reaction ordering.
    const pending = try flow.create(s.engine, c.pi_js_undefined());
    defer s.engine.freeValue(pending.owner);
    defer s.engine.freeValue(pending.promise);
    try s.put(pending.owner, "imports", try s.get(job, "imports"));
    try s.put(pending.owner, "id", id);
    const generation = s.engine.native_allocation_generation;
    readStart(s, pending.owner, store, id, signal) catch |err| {
        if (s.engine.nativeAllocationError(err, generation) != null) return err;
        try failWrapped(s, pending.owner, "auth", "Credential store read failed for ", try s.own(flow.reason(s.engine, err)));
    };
    try wait(s, job, pending.promise, .read);
}
fn readStart(s: *Scope, job: c.JSValue, store: c.JSValue, id: c.JSValue, signal: c.JSValue) !void {
    const read = try s.get(store, "read");
    const options = try s.object();
    try s.put(options, "signal", signal);
    try wait(s, job, try s.call(read, store, &.{ id, options }), .read_helper);
}
fn afterRead(s: *Scope, job: c.JSValue, stored: c.JSValue) !void {
    const provider = try s.get(job, "provider");
    const overrides = try s.get(job, "overrides");
    if (s.truthy(stored)) {
        if (try v.eq(s, try s.get(stored, "type"), "oauth") and s.truthy(try s.get(try s.get(provider, "auth"), "oauth"))) {
            const store = try s.get(job, "credentials");
            const id = try s.get(provider, "id");
            const oauth = try s.get(try s.get(provider, "auth"), "oauth");
            const signal = try s.get(job, "signal");
            const minimum = try v.optional(s, overrides, "minOAuthValidityMs");
            return resolve(s, job, try s.own(try storedOAuth(s, try s.get(job, "imports"), store, id, oauth, stored, signal, minimum)));
        }
        if (try v.eq(s, try s.get(stored, "type"), "api_key") and s.truthy(try s.get(try s.get(provider, "auth"), "apiKey"))) {
            const credential = if (s.truthy(try v.optional(s, overrides, "env"))) blk: {
                const out = try v.spread(s, stored);
                const env = try v.spread(s, try s.get(stored, "env"));
                try v.js.spreadInto(s.engine, env, try s.get(overrides, "env"));
                try s.put(out, "env", env);
                break :blk out;
            } else stored;
            const api = try s.get(try s.get(provider, "auth"), "apiKey");
            try s.put(job, "id", try s.get(provider, "id"));
            return apiResolve(s, job, api, credential);
        }
        return resolve(s, job, c.pi_js_undefined());
    }
    if (s.truthy(try s.get(try s.get(provider, "auth"), "apiKey"))) {
        const api = try s.get(try s.get(provider, "auth"), "apiKey");
        try s.put(job, "id", try s.get(provider, "id"));
        return apiResolve(s, job, api, c.pi_js_undefined());
    }
    try resolve(s, job, c.pi_js_undefined());
}
fn apiResolve(s: *Scope, job: c.JSValue, api: c.JSValue, credential: c.JSValue) !void {
    const pending = try flow.create(s.engine, c.pi_js_undefined());
    defer s.engine.freeValue(pending.owner);
    defer s.engine.freeValue(pending.promise);
    inline for (.{ "imports", "id", "requestAuthContext", "signal" }) |name| try s.put(pending.owner, name, try s.get(job, name));
    const generation = s.engine.native_allocation_generation;
    apiStart(s, pending.owner, api, credential) catch |err| {
        if (s.engine.nativeAllocationError(err, generation) != null) return err;
        try failWrapped(s, pending.owner, "auth", "API key auth failed for provider ", try s.own(flow.reason(s.engine, err)));
    };
    try resolve(s, job, pending.promise);
}
fn storedOAuth(s: *Scope, imports: c.JSValue, store: c.JSValue, id: c.JSValue, oauth: c.JSValue, stored: c.JSValue, signal: c.JSValue, minimum: c.JSValue) !c.JSValue {
    const pending = try flow.create(s.engine, c.pi_js_undefined());
    defer s.engine.freeValue(pending.owner);
    errdefer s.engine.freeValue(pending.promise);
    const job = pending.owner;
    try s.put(job, "imports", imports);
    try s.put(job, "id", id);
    try s.put(job, "oauth", oauth);
    try s.put(job, "minimumRequested", minimum);
    storedOAuthStart(s, job, store, stored, signal, minimum) catch |err| try flow.rejectError(s.engine, job, err);
    return pending.promise;
}
fn storedOAuthStart(s: *Scope, job: c.JSValue, store: c.JSValue, stored: c.JSValue, signal: c.JSValue, minimum: c.JSValue) !void {
    const floor = try s.invoke(try s.global("Math"), "max", &.{ c.JS_NewInt32(s.engine.context, 300000), if (v.nullish(minimum)) c.JS_NewInt32(s.engine.context, 0) else minimum });
    try s.put(job, "minimum", floor);
    if (try expiresSoon(s, job, stored)) {
        const pending = try s.own(try beginRefresh(s.engine, try s.get(job, "imports"), &.{ store, try s.get(job, "id"), try s.get(job, "oauth"), try arrow(s, expiresPredicate, 1, &.{job}, false), signal }));
        return wait(s, job, pending, .refreshed);
    }
    try derive(s, job, stored);
}
fn apiStart(s: *Scope, job: c.JSValue, api: c.JSValue, credential: c.JSValue) !void {
    const callback = try s.get(api, "resolve");
    const options = try s.object();
    try s.put(options, "ctx", try s.get(job, "requestAuthContext"));
    try s.put(options, "credential", credential);
    try s.put(options, "signal", try s.get(job, "signal"));
    try wait(s, job, try s.call(callback, api, &.{options}), .api);
}
fn expiresSoon(s: *Scope, job: c.JSValue, credential: c.JSValue) !bool {
    const now = try s.invoke(try s.global("Date"), "now", &.{});
    const sum = try s.own(try arithmetic.binary(s.engine, .add, now, try s.get(job, "minimum")));
    return arithmetic.compare(s.engine, .greater_equal, sum, try s.get(credential, "expires"));
}
fn expiresPredicate(engine: *v.em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    return c.pi_js_bool(engine.context, @intFromBool(try expiresSoon(&s, roots[0], arg(args, 0))));
}
fn derive(s: *Scope, job: c.JSValue, credential: c.JSValue) !void {
    const generation = s.engine.native_allocation_generation;
    deriveStart(s, job, credential) catch |err| {
        if (s.engine.nativeAllocationError(err, generation) != null) return err;
        try failWrapped(s, job, "oauth", "OAuth auth derivation failed for ", try s.own(flow.reason(s.engine, err)));
    };
}
fn deriveStart(s: *Scope, job: c.JSValue, credential: c.JSValue) !void {
    // The enclosing result literal is allocated before awaiting its auth value.
    try s.put(job, "result", try s.object());
    try wait(s, job, try s.invoke(try s.get(job, "oauth"), "toAuth", &.{credential}), .derived);
}
fn refreshStoredOAuthCredential(engine: *v.em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    return beginRefresh(engine, roots[0], args);
}
pub fn beginRefresh(engine: *v.em.Engine, imports: c.JSValue, args: []const c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    const pending = try flow.create(engine, c.pi_js_undefined());
    defer engine.freeValue(pending.owner);
    errdefer engine.freeValue(pending.promise);
    try s.put(pending.owner, "imports", imports);
    inline for (.{ "credentials", "id", "oauth", "needsRefresh", "signal" }, 0..) |name, i| try s.put(pending.owner, name, arg(args, i));
    refreshStart(&s, pending.owner) catch |err| try flow.rejectError(engine, pending.owner, err);
    return pending.promise;
}
fn cancelLock(engine: *v.em.Engine, _: c.JSValue, _: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    const job = roots[0];
    const lock = try s.get(job, "lockWait");
    const abort = try s.get(lock, "abort");
    return c.JS_DupValue(engine.context, try s.call(abort, lock, &.{try s.get(try s.get(job, "signal"), "reason")}));
}
fn cleanup(s: *Scope, job: c.JSValue) !void {
    _ = try s.invoke(try s.get(job, "signal"), "removeEventListener", &.{ try s.text("abort"), try s.get(job, "cancelLockWait") });
}
fn refreshStart(s: *Scope, job: c.JSValue) !void {
    const lock = try s.own(try v.js.builtin(s.engine, "AbortController", &.{}));
    try s.put(job, "lockWait", lock);
    const cancel = try arrow(s, cancelLock, 0, &.{job}, false);
    try s.put(job, "cancelLockWait", cancel);
    const signal = try s.get(job, "signal");
    const once = try s.object();
    try s.put(once, "once", c.pi_js_bool(s.engine.context, 1));
    _ = try s.invoke(signal, "addEventListener", &.{ try s.text("abort"), cancel, once });
    if (s.truthy(try s.get(signal, "aborted"))) _ = try s.call(cancel, c.pi_js_undefined(), &.{});
    const generation = s.engine.native_allocation_generation;
    modifyStart(s, job) catch |err| {
        if (s.engine.nativeAllocationError(err, generation) != null) {
            try cleanup(s, job);
            return err;
        }
        try finishModify(s, job, try s.own(flow.reason(s.engine, err)), true);
    };
}
fn modifyStart(s: *Scope, job: c.JSValue) !void {
    const store = try s.get(job, "credentials");
    const method = try s.get(store, "modify");
    const id = try s.get(job, "id");
    const callback = try arrow(s, refreshMutation, 1, &.{job}, true);
    const options = try s.object();
    try s.put(options, "signal", try s.get(try s.get(job, "lockWait"), "signal"));
    try wait(s, job, try s.call(method, store, &.{ id, callback, options }), .modified);
}
fn refreshMutation(engine: *v.em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    const pending = try flow.create(engine, c.pi_js_undefined());
    defer engine.freeValue(pending.owner);
    errdefer engine.freeValue(pending.promise);
    const parent = roots[0];
    try s.put(pending.owner, "parent", parent);
    try s.put(pending.owner, "imports", try s.get(parent, "imports"));
    try s.put(pending.owner, "id", try s.get(parent, "id"));
    refreshMutationBody(&s, pending.owner, arg(args, 0)) catch |err| try flow.rejectError(engine, pending.owner, err);
    return pending.promise;
}
fn refreshMutationBody(s: *Scope, job: c.JSValue, current: c.JSValue) !void {
    const parent = try s.get(job, "parent");
    try cleanup(s, parent);
    _ = try s.invoke(try s.get(parent, "signal"), "throwIfAborted", &.{});
    if (!try v.eq(s, try v.optional(s, current, "type"), "oauth")) return resolve(s, job, c.pi_js_undefined());
    if (!s.truthy(try s.call(try s.get(parent, "needsRefresh"), c.pi_js_undefined(), &.{current}))) return resolve(s, job, c.pi_js_undefined());
    const generation = s.engine.native_allocation_generation;
    refreshCall(s, job, parent, current) catch |err| {
        if (s.engine.nativeAllocationError(err, generation) != null) return err;
        try failWrapped(s, job, "oauth", "OAuth refresh failed for ", try s.own(flow.reason(s.engine, err)));
    };
}
fn refreshCall(s: *Scope, job: c.JSValue, parent: c.JSValue, current: c.JSValue) !void {
    const oauth = try s.get(parent, "oauth");
    const method = try s.get(oauth, "refresh");
    const timeout = try s.invoke(try s.global("AbortSignal"), "timeout", &.{c.JS_NewInt32(s.engine.context, 15000)});
    try wait(s, job, try s.call(method, oauth, &.{ current, timeout }), .refresh_callback);
}
fn modifyFailure(s: *Scope, job: c.JSValue, raw: c.JSValue) !c.JSValue {
    const constructor = try s.get(try s.get(job, "imports"), "ModelsError");
    const instance = c.JS_IsInstanceOf(s.engine.context, raw, constructor);
    if (instance < 0) return v.js.capture(s.engine);
    if (instance != 0) return raw;
    _ = try s.invoke(try s.get(job, "signal"), "throwIfAborted", &.{});
    return errorValue(s, job, "auth", "Credential store modify failed for ", raw);
}
fn finishModify(s: *Scope, job: c.JSValue, value: c.JSValue, failed: bool) !void {
    var failure = value;
    if (failed) failure = modifyFailure(s, job, value) catch |err| try s.own(flow.reason(s.engine, err));
    // Source finally executes even when instanceof/throwIfAborted/wrapping fail.
    try cleanup(s, job);
    if (failed) return reject(s, job, failure);
    try resolve(s, job, if (try v.eq(s, try v.optional(s, value, "type"), "oauth")) value else c.pi_js_undefined());
}
fn continued(engine: *v.em.Engine, job: c.JSValue, value: c.JSValue, failed: bool, raw_stage: c_int) !void {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    const stage: Stage = @enumFromInt(raw_stage);
    if (stage == .modified) return finishModify(&s, job, value, failed);
    if (failed) return switch (stage) {
        .read_helper => failWrapped(&s, job, "auth", "Credential store read failed for ", value),
        .api => failWrapped(&s, job, "auth", "API key auth failed for provider ", value),
        .derived => failWrapped(&s, job, "oauth", "OAuth auth derivation failed for ", value),
        .refresh_callback => failWrapped(&s, job, "oauth", "OAuth refresh failed for ", value),
        else => reject(&s, job, value),
    };
    switch (stage) {
        .read => try afterRead(&s, job, value),
        .read_helper, .api, .refresh_callback, .overlay_env => try resolve(&s, job, value),
        .refreshed => {
            if (!s.truthy(value)) return resolve(&s, job, c.pi_js_undefined());
            if (!c.JS_IsUndefined(try s.get(job, "minimumRequested")) and try expiresSoon(&s, job, value)) return reject(&s, job, try errorValue(&s, job, "oauth", "OAuth refresh returned a token that expires too soon for ", null));
            try derive(&s, job, value);
        },
        .derived => {
            const result = try s.get(job, "result");
            try s.put(result, "auth", value);
            try s.put(result, "source", try s.text("OAuth"));
            try resolve(&s, job, result);
        },
        .modified => unreachable,
    }
}
