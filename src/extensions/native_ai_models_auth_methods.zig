//! Actual Source4954 ModelsImpl auth methods. Ordinary dynamic receivers and
//! captured real module imports; no private model state or Error family.
const std = @import("std");
const v = @import("native_ai_provider_values.zig");
const Scope = v.Scope;
const c = v.c;
const functions = @import("native_node_function.zig");
const flow = @import("native_agent_async.zig");
const body = @import("native_async_body.zig");
const native = body.native;
pub const Kind = enum { readCredential, checkProviderAuth, checkAuth, getAuthenticatedProviders, getAvailable, getAvailableOfType, getAllAvailable, getAuth, login, logout, applyAuth };
const Stage = enum(c_int) { read, checked, fallback, check_read, authenticated_read, authenticated_check, authenticated_all, available, available_type, auth, apply, transformed, login, login_barrier, login_mutation, logout };

fn arg(args: []const c.JSValue, index: usize) c.JSValue {
    return if (index < args.len) args[index] else c.pi_js_undefined();
}
fn imported(s: *Scope, imports: c.JSValue, name: [*:0]const u8, args: []const c.JSValue) !c.JSValue {
    return s.call(try s.get(imports, name), c.pi_js_undefined(), args);
}
fn ownArg(s: *Scope, job: c.JSValue, name: [*:0]const u8, value: c.JSValue) !void {
    try s.put(job, name, value);
}
fn operationSignal(s: *Scope, imports: c.JSValue, options: c.JSValue) !c.JSValue {
    return imported(s, imports, "operationSignal", &.{try v.optional(s, options, "signal")});
}
fn signalOptions(s: *Scope, signal: c.JSValue) !c.JSValue {
    const out = try s.object();
    try s.put(out, "signal", signal);
    return out;
}
fn awaitValue(s: *Scope, job: c.JSValue, value: c.JSValue, stage: Stage) !void {
    try body.wait(s, job, value, @intFromEnum(stage));
}
fn resolve(s: *Scope, job: c.JSValue, value: c.JSValue) !void {
    try body.resolve(s, job, value);
}
fn reject(s: *Scope, job: c.JSValue, value: c.JSValue) !void {
    try body.reject(s, job, value);
}
fn arrow(s: *Scope, callback: functions.Callback, arity: c_int, roots: []const c.JSValue, is_async: bool) !c.JSValue {
    return s.own(if (is_async)
        try native.createArrow(s.engine, "", arity, callback, roots, c.pi_js_undefined())
    else
        try functions.createArrow(s.engine, "", arity, callback, roots));
}
pub fn length(comptime kind: Kind) c_int {
    return switch (kind) {
        .readCredential, .checkAuth, .getAvailable, .getAllAvailable, .getAuth, .logout, .applyAuth => 2,
        .checkProviderAuth, .getAvailableOfType => 3,
        .getAuthenticatedProviders => 2,
        .login => 4,
    };
}
pub fn asynchronous(comptime kind: Kind) bool {
    return kind != .checkAuth and kind != .getAvailable and kind != .getAllAvailable;
}
/// Imports must be the canonical module's actual bindings. Assembly captures
/// them once, including the SAME public ModelsError constructor.
pub fn create(engine: *v.em.Engine, comptime kind: Kind, imports: c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    const captured = try s.object();
    inline for (.{ "ModelsError", "operationSignal", "raceWithAbortSignal", "resolveProviderAuth", "isModelType" }) |name| {
        const value = try s.get(imports, name);
        if (!c.JS_IsFunction(engine.context, value)) return error.RequiredActualModelsAuthDependency;
        if (comptime std.mem.eql(u8, name, "ModelsError")) if (!c.JS_IsConstructor(engine.context, value)) return error.RequiredCanonicalModelsError;
        try s.put(captured, name, value);
    }
    const Adapter = struct {
        fn call(host: *v.em.Engine, self: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
            return dispatch(host, kind, roots[0], self, args);
        }
        fn advanceBody(host: *v.em.Engine, self: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue, state: *c.JSValue, completion: native.Completion, input: c.JSValue) !native.Action {
            return runBody(host, kind, roots[0], self, args, c.pi_js_undefined(), state, completion, input);
        }
    };
    const out = try s.own(if (asynchronous(kind))
        try native.createResumable(engine, @tagName(kind), length(kind), Adapter.advanceBody, &.{captured})
    else
        try functions.createMethod(engine, @tagName(kind), length(kind), Adapter.call, &.{captured}));
    return c.JS_DupValue(engine.context, out);
}
pub fn dispatch(engine: *v.em.Engine, kind: Kind, imports: c.JSValue, self: c.JSValue, args: []const c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    // Source regular public methods evaluate operationSignal before entering
    // their async IIFE. A throwing options.signal getter throws synchronously.
    const signal = try operationSignal(&s, imports, arg(args, 1));
    const Iife = struct {
        fn advanceBody(host: *v.em.Engine, _: c.JSValue, _: []const c.JSValue, roots: []const c.JSValue, state: *c.JSValue, completion: native.Completion, input: c.JSValue) !native.Action {
            var raw: i32 = 0;
            if (c.JS_ToInt32(host.context, &raw, roots[3]) < 0) return v.js.capture(host);
            return runBody(host, @enumFromInt(raw), roots[0], roots[1], roots[4..], roots[2], state, completion, input);
        }
    };
    const inner = try s.own(try native.createResumableArrow(engine, "", 0, Iife.advanceBody, &.{ imports, self, signal, c.JS_NewInt32(engine.context, @intFromEnum(kind)), arg(args, 0), arg(args, 1), arg(args, 2), arg(args, 3) }, c.pi_js_undefined()));
    const promise = try s.call(inner, c.pi_js_undefined(), &.{});
    return c.JS_DupValue(engine.context, try imported(&s, imports, "raceWithAbortSignal", &.{ promise, signal }));
}
fn runBody(engine: *v.em.Engine, kind: Kind, imports: c.JSValue, self: c.JSValue, args: []const c.JSValue, signal: c.JSValue, state: *c.JSValue, completion: native.Completion, input: c.JSValue) !native.Action {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    if (completion == .start) {
        const job = try body.init(&s, state);
        try ownArg(&s, job, "imports", imports);
        try ownArg(&s, job, "self", self);
        try ownArg(&s, job, "signal", signal);
        try s.put(job, "kind", c.JS_NewInt32(engine.context, @intFromEnum(kind)));
        inline for (.{ "a", "b", "d", "e" }, 0..) |name, index| try ownArg(&s, job, name, arg(args, index));
        start(&s, job, kind) catch |err| return body.failure(engine, err);
    } else continued(engine, state.*, input, completion == .rejected, try body.stage(&s, state.*)) catch |err| return body.failure(engine, err);
    return body.action(&s, state.*);
}
fn modelsError(s: *Scope, job: c.JSValue, code: []const u8, prefix: []const u8, id: c.JSValue, cause: ?c.JSValue) !c.JSValue {
    const message = try s.concat(try s.text(prefix), try s.stringify(id));
    const options = if (cause) |raw| blk: {
        const out = try s.object();
        try s.put(out, "cause", raw);
        break :blk out;
    } else c.pi_js_undefined();
    const ctor = try s.get(try s.get(job, "imports"), "ModelsError");
    var args = [_]c.JSValue{ try s.text(code), message, options };
    return s.own(try s.engine.checked(c.JS_CallConstructor(s.engine.context, ctor, 3, &args)));
}
fn failWrapped(s: *Scope, job: c.JSValue, prefix: []const u8, id: c.JSValue, cause: c.JSValue) !void {
    try reject(s, job, try modelsError(s, job, "auth", prefix, id, cause));
}
fn readStart(s: *Scope, job: c.JSValue) !void {
    const self = try s.get(job, "self");
    const id = try s.get(job, "a");
    const store = try s.get(self, "credentials");
    const method = try s.get(store, "read");
    const pending = try s.call(method, store, &.{ id, try signalOptions(s, try s.get(job, "b")) });
    try awaitValue(s, job, pending, .read);
}
fn start(s: *Scope, job: c.JSValue, kind: Kind) !void {
    const self = try s.get(job, "self");
    const imports = try s.get(job, "imports");
    const a = try s.get(job, "a");
    const b = try s.get(job, "b");
    switch (kind) {
        .readCredential => {
            const generation = s.engine.native_allocation_generation;
            readStart(s, job) catch |err| {
                if (s.engine.nativeAllocationError(err, generation) == error.OutOfMemory) return error.OutOfMemory;
                const raw = try s.own(flow.reason(s.engine, err));
                try failWrapped(s, job, "Credential store read failed for ", a, raw);
            };
        },
        .checkProviderAuth => {
            const signal = try s.get(job, "d");
            if (try v.eq(s, try v.optional(s, b, "type"), "oauth")) {
                const oauth = try s.get(try s.get(a, "auth"), "oauth");
                if (!s.truthy(oauth)) return resolve(s, job, c.pi_js_undefined());
                const out = try s.object();
                try s.put(out, "source", try s.text("OAuth"));
                try s.put(out, "type", try s.text("oauth"));
                return resolve(s, job, out);
            }
            const api = try s.get(try s.get(a, "auth"), "apiKey");
            if (!s.truthy(api)) return resolve(s, job, c.pi_js_undefined());
            try s.put(job, "api", api);
            if (s.truthy(try s.get(api, "check"))) {
                const generation = s.engine.native_allocation_generation;
                checkStart(s, job, a, b, signal) catch |err| {
                    if (s.engine.nativeAllocationError(err, generation) == error.OutOfMemory) return error.OutOfMemory;
                    const raw = try s.own(flow.reason(s.engine, err));
                    try failWrapped(s, job, "API key auth check failed for provider ", try s.get(a, "id"), raw);
                };
            } else {
                // This lexical resolver performs its OWN second credential read.
                try awaitValue(s, job, try imported(s, imports, "resolveProviderAuth", &.{ a, try s.get(self, "credentials"), try s.get(self, "authContext"), try signalOptions(s, signal) }), .fallback);
            }
        },
        .checkAuth => {
            const signal = try s.get(job, "signal");
            _ = try s.invoke(signal, "throwIfAborted", &.{});
            const provider = try s.invoke(try s.get(self, "providers"), "get", &.{a});
            if (!s.truthy(provider)) return resolve(s, job, c.pi_js_undefined());
            try s.put(job, "provider", provider);
            // Callee lookup occurs before the await argument, as in Source.
            try s.put(job, "check", try s.get(self, "checkProviderAuth"));
            try awaitValue(s, job, try s.invoke(self, "readCredential", &.{ a, signal }), .check_read);
        },
        .getAuthenticatedProviders => {
            _ = try s.invoke(b, "throwIfAborted", &.{});
            const providers = if (s.truthy(a)) blk: {
                const out = try s.array();
                const provider = try s.invoke(try s.get(self, "providers"), "get", &.{a});
                try s.index(out, 0, provider);
                break :blk try s.invoke(out, "filter", &.{try arrow(s, defined, 1, &.{}, false)});
            } else try s.invoke(self, "getProviders", &.{});
            const promise = try s.global("Promise");
            const all = try s.get(promise, "all");
            const mapped = try s.invoke(providers, "map", &.{try s.own(try native.createResumableArrow(s.engine, "", 1, authenticated, &.{job}, c.pi_js_undefined()))});
            try awaitValue(s, job, try s.call(all, promise, &.{mapped}), .authenticated_all);
        },
        .getAvailable, .getAllAvailable => {
            try awaitValue(s, job, try s.invoke(self, "getAuthenticatedProviders", &.{ a, try s.get(job, "signal") }), .available);
        },
        .getAvailableOfType => try awaitValue(s, job, try s.invoke(self, "getAllAvailable", &.{ b, try s.get(job, "d") }), .available_type),
        .getAuth => {
            const signal = try operationSignal(s, imports, b);
            const id = if (c.JS_IsString(a)) a else try s.get(a, "provider");
            const provider = try s.invoke(try s.get(self, "providers"), "get", &.{id});
            if (!s.truthy(provider)) return resolve(s, job, c.pi_js_undefined());
            // Imported resolver callee and receiver field getters precede spread.
            const resolver = try s.get(imports, "resolveProviderAuth");
            const credentials = try s.get(self, "credentials");
            const context = try s.get(self, "authContext");
            const options = try v.spread(s, b);
            try s.put(options, "signal", signal);
            try awaitValue(s, job, try s.call(resolver, c.pi_js_undefined(), &.{ provider, credentials, context, options }), .auth);
        },
        .applyAuth => {
            _ = try s.invoke(self, "requireProvider", &.{a});
            const method = try s.get(self, "getAuth");
            const options = try s.object();
            inline for (.{ "apiKey", "env", "signal" }) |name| try s.put(options, name, try v.optional(s, b, name));
            try awaitValue(s, job, try s.call(method, self, &.{ a, options }), .apply);
        },
        .login => {
            const interaction = try s.get(job, "d");
            const signal = try imported(s, imports, "operationSignal", &.{try s.get(interaction, "signal")});
            try s.put(job, "signal", signal);
            _ = try s.invoke(signal, "throwIfAborted", &.{});
            const provider = try s.invoke(try s.get(self, "providers"), "get", &.{a});
            if (!s.truthy(provider)) return reject(s, job, try modelsError(s, job, "provider", "Unknown provider: ", a, null));
            const method = try s.get(try s.get(provider, "auth"), if (try v.eq(s, b, "oauth")) "oauth" else "apiKey");
            if (!s.truthy(try v.optional(s, method, "login"))) {
                const message = try s.concat(try s.concat(try s.concat(try s.stringify(try s.get(provider, "name")), try s.text(" does not support ")), try s.stringify(b)), try s.text(" login"));
                return reject(s, job, try modelsError(s, job, "auth", "", message, null));
            }
            const login = try s.get(method, "login");
            const next = try v.spread(s, interaction);
            try s.put(next, "signal", signal);
            const operation = try s.call(login, method, &.{ next, try s.get(job, "e") });
            try awaitValue(s, job, try imported(s, imports, "raceWithAbortSignal", &.{ operation, signal }), .login);
        },
        .logout => {
            const signal = try operationSignal(s, imports, b);
            try s.put(job, "signal", signal);
            _ = try s.invoke(signal, "throwIfAborted", &.{});
            const generation = s.engine.native_allocation_generation;
            logoutStart(s, job, a, signal) catch |err| {
                if (s.engine.nativeAllocationError(err, generation) == error.OutOfMemory) return error.OutOfMemory;
                const raw = try s.own(flow.reason(s.engine, err));
                try mutationFailure(s, job, raw, "Credential store delete failed for ");
            };
        },
    }
}
fn checkStart(s: *Scope, job: c.JSValue, provider: c.JSValue, credential: c.JSValue, signal: c.JSValue) !void {
    const api = try s.get(job, "api");
    const callback = try s.get(api, "check");
    const options = try s.object();
    try s.put(options, "ctx", try s.get(try s.get(job, "self"), "authContext"));
    try s.put(options, "credential", if (try v.eq(s, try v.optional(s, credential, "type"), "api_key")) credential else c.pi_js_undefined());
    try s.put(options, "signal", signal);
    _ = provider;
    try awaitValue(s, job, try s.call(callback, api, &.{options}), .checked);
}
fn logoutStart(s: *Scope, job: c.JSValue, id: c.JSValue, signal: c.JSValue) !void {
    const store = try s.get(try s.get(job, "self"), "credentials");
    const method = try s.get(store, "delete");
    try awaitValue(s, job, try s.call(method, store, &.{ id, try signalOptions(s, signal) }), .logout);
}
fn defined(engine: *v.em.Engine, _: c.JSValue, args: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
    return c.pi_js_bool(engine.context, @intFromBool(!c.JS_IsUndefined(arg(args, 0))));
}
fn authenticated(engine: *v.em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue, state: *c.JSValue, completion: native.Completion, input: c.JSValue) !native.Action {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    if (completion == .start) {
        const job = try body.init(&s, state);
        try s.put(job, "parent", roots[0]);
        try s.put(job, "provider", arg(args, 0));
        authenticatedStart(&s, job) catch |err| return body.failure(engine, err);
    } else continued(engine, state.*, input, completion == .rejected, try body.stage(&s, state.*)) catch |err| return body.failure(engine, err);
    return body.action(&s, state.*);
}
fn authenticatedStart(s: *Scope, job: c.JSValue) !void {
    const parent = try s.get(job, "parent");
    const self = try s.get(parent, "self");
    const method = try s.get(self, "readCredential");
    const provider = try s.get(job, "provider");
    try awaitValue(s, job, try s.call(method, self, &.{ try s.get(provider, "id"), try s.get(parent, "b") }), .authenticated_read);
}
fn hasAuth(engine: *v.em.Engine, _: c.JSValue, args: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    return c.pi_js_bool(engine.context, @intFromBool(!c.JS_IsUndefined(try s.get(arg(args, 0), "auth"))));
}
fn typeFilter(engine: *v.em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    return c.JS_DupValue(engine.context, try imported(&s, roots[0], "isModelType", &.{ arg(args, 0), roots[1] }));
}
fn allFilter(engine: *v.em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    const model = arg(args, 0);
    if (!s.truthy(try imported(&s, roots[0], "isModelType", &.{ model, try s.text("chat") }))) return c.pi_js_bool(engine.context, 1);
    return c.JS_DupValue(engine.context, try s.invoke(roots[1], "has", &.{try s.get(model, "id")}));
}
fn modelId(engine: *v.em.Engine, _: c.JSValue, args: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
    return v.js.get(engine, arg(args, 0), "id");
}
fn availableMap(engine: *v.em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    const entry = arg(args, 0);
    const provider = try s.get(entry, "provider");
    const credential = try s.get(entry, "credential");
    const job = roots[0];
    var raw_kind: i32 = 0;
    if (c.JS_ToInt32(engine.context, &raw_kind, try s.get(job, "kind")) < 0) return v.js.capture(engine);
    const kind: Kind = @enumFromInt(raw_kind);
    if (kind == .getAvailable) {
        const models = try s.invoke(provider, "getModels", &.{});
        const filter = try s.get(provider, "filterModels");
        const value = if (v.nullish(filter)) c.pi_js_undefined() else try s.call(filter, provider, &.{ models, credential });
        return c.JS_DupValue(engine.context, if (v.nullish(value)) models else value);
    }
    const all = try s.get(provider, "getAllModels");
    const from_all = if (v.nullish(all)) c.pi_js_undefined() else try s.call(all, provider, &.{});
    const models = if (v.nullish(from_all)) try s.invoke(provider, "getModels", &.{}) else from_all;
    if (s.truthy(try s.get(provider, "filterAllModels"))) return c.JS_DupValue(engine.context, try s.invoke(provider, "filterAllModels", &.{ models, credential }));
    if (!s.truthy(try s.get(provider, "filterModels"))) return c.JS_DupValue(engine.context, models);
    const filter = try s.get(provider, "filterModels");
    const chat = try s.invoke(provider, "getModels", &.{});
    const ids = try s.invoke(try s.call(filter, provider, &.{ chat, credential }), "map", &.{try arrow(&s, modelId, 1, &.{}, false)});
    const set = try s.own(try v.js.builtin(engine, "Set", &.{ids}));
    return c.JS_DupValue(engine.context, try s.invoke(models, "filter", &.{try arrow(&s, allFilter, 1, &.{ try s.get(job, "imports"), set }, false)}));
}
fn mergeHeaders(s: *Scope, base: c.JSValue, override: c.JSValue) !c.JSValue {
    if (!s.truthy(base) and !s.truthy(override)) return c.pi_js_undefined();
    const merged = try v.spread(s, base);
    const entries = try s.invoke(try s.global("Object"), "entries", &.{if (v.nullish(override)) try s.object() else override});
    var iterator = try v.iterator(s, entries);
    defer iterator.deinit();
    errdefer iterator.closePreserving();
    while (try iterator.next()) |entry_raw| {
        const entry = try s.own(entry_raw);
        const name = try v.at(s, entry, 0);
        const value = try v.at(s, entry, 1);
        const lower = try s.invoke(name, "toLowerCase", &.{});
        var names = try v.iterator(s, try s.invoke(try s.global("Object"), "keys", &.{merged}));
        defer names.deinit();
        errdefer names.closePreserving();
        while (try names.next()) |raw_name| {
            const existing = try s.own(raw_name);
            if (s.equal(try s.invoke(existing, "toLowerCase", &.{}), lower)) {
                const atom = try v.js.atom(s.engine, existing);
                defer c.JS_FreeAtom(s.engine.context, atom);
                if (c.JS_DeleteProperty(s.engine.context, merged, atom, c.JS_PROP_THROW) < 0) return v.js.capture(s.engine);
            }
        }
        try v.js.setKey(s.engine, merged, name, value);
    }
    return merged;
}
fn finishApply(s: *Scope, job: c.JSValue, headers: c.JSValue) !void {
    const resolution = try s.get(job, "resolution");
    const options = try s.get(job, "b");
    const auth = try s.get(job, "auth");
    const model = try s.get(job, "a");
    const env = if (s.truthy(try s.get(resolution, "env")) or s.truthy(try v.optional(s, options, "env"))) blk: {
        const out = try v.spread(s, try s.get(resolution, "env"));
        try v.js.spreadInto(s.engine, out, try v.optional(s, options, "env"));
        break :blk out;
    } else c.pi_js_undefined();
    const request_model = if (s.truthy(try s.get(auth, "baseUrl"))) blk: {
        const out = try v.spread(s, model);
        try s.put(out, "baseUrl", try s.get(auth, "baseUrl"));
        break :blk out;
    } else model;
    // Destructuring performs the excluded getter before copying enumerable rest.
    const source = if (v.nullish(options)) try s.object() else options;
    _ = try s.get(source, "transformHeaders");
    const provider_options = try objectRest(s, source, "transformHeaders");
    const request_options = try v.spread(s, provider_options);
    try s.put(request_options, "apiKey", try s.get(job, "apiKey"));
    try s.put(request_options, "headers", headers);
    try s.put(request_options, "env", env);
    const result = try s.object();
    try s.put(result, "requestModel", request_model);
    try s.put(result, "requestOptions", request_options);
    try resolve(s, job, result);
}
fn objectRest(s: *Scope, source: c.JSValue, excluded: [*:0]const u8) !c.JSValue {
    const out = try s.object();
    const boxed = try s.own(try s.engine.checked(c.JS_ToObject(s.engine.context, source)));
    const excluded_atom = c.JS_NewAtom(s.engine.context, excluded);
    if (excluded_atom == c.JS_ATOM_NULL) return v.js.capture(s.engine);
    defer c.JS_FreeAtom(s.engine.context, excluded_atom);
    var names: [*c]c.JSPropertyEnum = null;
    var count: u32 = 0;
    if (c.JS_GetOwnPropertyNames(s.engine.context, &names, &count, boxed, c.JS_GPN_STRING_MASK | c.JS_GPN_SYMBOL_MASK) < 0) return v.js.capture(s.engine);
    defer c.JS_FreePropertyEnum(s.engine.context, names, count);
    for (names[0..count]) |entry| {
        if (entry.atom == excluded_atom) continue;
        var descriptor: c.JSPropertyDescriptor = undefined;
        const present = c.JS_GetOwnProperty(s.engine.context, &descriptor, boxed, entry.atom);
        if (present < 0) return v.js.capture(s.engine);
        if (present == 0) continue;
        defer s.engine.freeValue(descriptor.value);
        defer s.engine.freeValue(descriptor.getter);
        defer s.engine.freeValue(descriptor.setter);
        if (descriptor.flags & c.JS_PROP_ENUMERABLE == 0) continue;
        const value = try s.engine.checked(c.JS_GetProperty(s.engine.context, boxed, entry.atom));
        if (c.JS_DefinePropertyValue(s.engine.context, out, entry.atom, value, c.JS_PROP_C_W_E) < 0) return v.js.capture(s.engine);
    }
    return out;
}
fn continued(engine: *v.em.Engine, job: c.JSValue, value: c.JSValue, failed: bool, raw_stage: c_int) !void {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    const stage: Stage = @enumFromInt(raw_stage);
    if (failed) {
        if (stage == .read) return failWrapped(&s, job, "Credential store read failed for ", try s.get(job, "a"), value);
        if (stage == .checked) return failWrapped(&s, job, "API key auth check failed for provider ", try s.get(try s.get(job, "a"), "id"), value);
        if (stage == .logout or stage == .login_barrier or stage == .login_mutation) return mutationFailure(&s, job, value, if (stage == .logout) "Credential store delete failed for " else "Credential store modify failed for ");
        return reject(&s, job, value);
    }
    switch (stage) {
        .read, .checked => try resolve(&s, job, value),
        .fallback => {
            if (!s.truthy(value)) return resolve(&s, job, c.pi_js_undefined());
            const out = try s.object();
            try s.put(out, "source", try s.get(value, "source"));
            try s.put(out, "type", try s.text("api_key"));
            try resolve(&s, job, out);
        },
        .check_read => {
            const self = try s.get(job, "self");
            const result = try s.call(try s.get(job, "check"), self, &.{ try s.get(job, "provider"), value, try s.get(job, "signal") });
            try resolve(&s, job, result);
        },
        .authenticated_read => {
            try s.put(job, "credential", value);
            const parent = try s.get(job, "parent");
            const self = try s.get(parent, "self");
            const out = try s.object();
            try s.put(out, "provider", try s.get(job, "provider"));
            try s.put(out, "credential", value);
            try s.put(job, "entry", out);
            try awaitValue(&s, job, try s.invoke(self, "checkProviderAuth", &.{ try s.get(job, "provider"), value, try s.get(parent, "b") }), .authenticated_check);
        },
        .authenticated_check => {
            const out = try s.get(job, "entry");
            try s.put(out, "auth", value);
            try resolve(&s, job, out);
        },
        .authenticated_all => try resolve(&s, job, try s.invoke(value, "filter", &.{try arrow(&s, hasAuth, 1, &.{}, false)})),
        .available => try resolve(&s, job, try s.invoke(value, "flatMap", &.{try arrow(&s, availableMap, 1, &.{job}, false)})),
        .available_type => try resolve(&s, job, try s.invoke(value, "filter", &.{try arrow(&s, typeFilter, 1, &.{ try s.get(job, "imports"), try s.get(job, "a") }, false)})),
        .auth => {
            const input = try s.get(job, "a");
            if (!s.truthy(value) or c.JS_IsString(input) or !s.truthy(try s.get(input, "headers"))) return resolve(&s, job, value);
            const out = try v.spread(&s, value);
            const auth = try v.spread(&s, try s.get(value, "auth"));
            try s.put(auth, "headers", try mergeHeaders(&s, try s.get(try s.get(value, "auth"), "headers"), try s.get(input, "headers")));
            try s.put(out, "auth", auth);
            try resolve(&s, job, out);
        },
        .apply => {
            if (!s.truthy(value)) return reject(&s, job, try modelsError(&s, job, "auth", "Provider is not configured: ", try s.get(try s.get(job, "a"), "provider"), null));
            try s.put(job, "resolution", value);
            const auth = try s.get(value, "auth");
            try s.put(job, "auth", auth);
            const options = try s.get(job, "b");
            const key = try v.optional(&s, options, "apiKey");
            try s.put(job, "apiKey", if (v.nullish(key)) try s.get(auth, "apiKey") else key);
            const headers = try mergeHeaders(&s, try s.get(auth, "headers"), try v.optional(&s, options, "headers"));
            if (s.truthy(try v.optional(&s, options, "transformHeaders"))) try awaitValue(&s, job, try s.invoke(options, "transformHeaders", &.{if (v.nullish(headers)) try s.object() else headers}), .transformed) else try finishApply(&s, job, headers);
        },
        .transformed => try finishApply(&s, job, value),
        .login => try loginMutation(&s, job, value),
        .login_barrier => try awaitValue(&s, job, try s.get(job, "mutation"), .login_mutation),
        .login_mutation => try resolve(&s, job, try s.get(job, "credential")),
        .logout => try resolve(&s, job, c.pi_js_undefined()),
    }
}
fn noop(_: *v.em.Engine, _: c.JSValue, _: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
    return c.pi_js_undefined();
}
fn startedExecutor(engine: *v.em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    try s.put(roots[0], "markMutationStarted", arg(args, 0));
    return c.pi_js_undefined();
}
fn mutationCallback(engine: *v.em.Engine, _: c.JSValue, _: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    const job = roots[0];
    try s.set(job, "mutationStarted", c.pi_js_bool(engine.context, 1));
    const callback = try s.get(job, "markMutationStarted");
    if (!v.nullish(callback)) _ = try s.call(callback, c.pi_js_undefined(), &.{});
    return c.JS_DupValue(engine.context, try s.get(job, "credential"));
}
fn onAbort(engine: *v.em.Engine, _: c.JSValue, _: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    const job = roots[0];
    if (!s.truthy(try s.get(job, "mutationStarted"))) _ = try s.call(try s.get(job, "barrierReject"), c.pi_js_undefined(), &.{try s.get(try s.get(job, "signal"), "reason")});
    return c.pi_js_undefined();
}
fn barrierDone(engine: *v.em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    const job = roots[0];
    _ = try s.invoke(try s.get(job, "signal"), "removeEventListener", &.{ try s.text("abort"), try s.get(job, "onAbort") });
    _ = try s.call(try s.get(job, if (s.truthy(roots[1])) "barrierReject" else "barrierResolve"), c.pi_js_undefined(), if (s.truthy(roots[1])) &.{arg(args, 0)} else &.{});
    return c.pi_js_undefined();
}
fn barrierExecutor(engine: *v.em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    const job = roots[0];
    const signal = try s.get(job, "signal");
    try s.put(job, "barrierResolve", arg(args, 0));
    try s.put(job, "barrierReject", arg(args, 1));
    const abort = try arrow(&s, onAbort, 0, &.{job}, false);
    try s.put(job, "onAbort", abort);
    const once = try s.object();
    try s.put(once, "once", c.pi_js_bool(engine.context, 1));
    _ = try s.invoke(signal, "addEventListener", &.{ try s.text("abort"), abort, once });
    const values = try s.array();
    try s.index(values, 0, try s.get(job, "started"));
    try s.index(values, 1, try s.get(job, "mutation"));
    const race = try s.invoke(try s.global("Promise"), "race", &.{values});
    _ = try s.invoke(race, "then", &.{ try arrow(&s, barrierDone, 0, &.{ job, c.pi_js_bool(engine.context, 0) }, false), try arrow(&s, barrierDone, 1, &.{ job, c.pi_js_bool(engine.context, 1) }, false) });
    if (s.truthy(try s.get(signal, "aborted"))) _ = try s.call(abort, c.pi_js_undefined(), &.{});
    return c.pi_js_undefined();
}
fn loginMutation(s: *Scope, job: c.JSValue, credential: c.JSValue) !void {
    try s.put(job, "credential", credential);
    try s.put(job, "mutationStarted", c.pi_js_bool(s.engine.context, 0));
    const started = try s.own(try v.js.builtin(s.engine, "Promise", &.{try arrow(s, startedExecutor, 1, &.{job}, false)}));
    try s.put(job, "started", started);
    const store = try s.get(try s.get(job, "self"), "credentials");
    const modify = try s.get(store, "modify");
    const mutation = try s.call(modify, store, &.{ try s.get(job, "a"), try arrow(s, mutationCallback, 0, &.{job}, true), try signalOptions(s, try s.get(job, "signal")) });
    try s.put(job, "mutation", mutation);
    _ = try s.invoke(mutation, "catch", &.{try arrow(s, noop, 0, &.{}, false)});
    const generation = s.engine.native_allocation_generation;
    const barrier = s.own(v.js.builtin(s.engine, "Promise", &.{try arrow(s, barrierExecutor, 2, &.{job}, false)}) catch |err| {
        if (s.engine.nativeAllocationError(err, generation) == error.OutOfMemory) return error.OutOfMemory;
        return mutationFailure(s, job, try s.own(flow.reason(s.engine, err)), "Credential store modify failed for ");
    }) catch |err| return err;
    try awaitValue(s, job, barrier, .login_barrier);
}
fn mutationFailure(s: *Scope, job: c.JSValue, cause: c.JSValue, prefix: []const u8) !void {
    _ = try s.invoke(try s.get(job, "signal"), "throwIfAborted", &.{});
    try failWrapped(s, job, prefix, try s.get(job, "a"), cause);
}
