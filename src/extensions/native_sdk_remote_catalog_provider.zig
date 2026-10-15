//! Actual coding-agent remote-catalog-provider.ts wrappers. Real management HTTP,
//! type helpers and runtime user-agent bindings are mandatory borrowed imports.
//! Providers and context callbacks remain genuine guest values and live calls.
const v = @import("native_ai_provider_values.zig");
const Scope = v.Scope;
const c = v.c;
const functions = @import("native_node_function.zig");
const flow = @import("native_agent_async.zig");
const arithmetic = @import("native_image_arithmetic.zig");
const async_functions = @import("native_ai_auth_helpers.zig");
pub const refresh_interval_ms = 4 * 60 * 60 * 1000;
pub const Dependencies = struct {
    get_model_type: c.JSValue,
    is_model_type: c.JSValue,
    fetch_with_retry: c.JSValue,
    get_pi_user_agent: c.JSValue,
    version: c.JSValue,
};
const Op = enum { remote_get, remote_all, personal_get, personal_all, entry, chat, provider, map_provider, update };
const Stage = enum(c_int) { restored, response, read_catalog, personalized, published, failed_published, finished };
fn arg(args: []const c.JSValue, index: usize) c.JSValue {
    return if (index < args.len) args[index] else c.pi_js_undefined();
}
fn arrow(scope: *Scope, name: [*:0]const u8, length: c_int, comptime operation: Op, roots: []const c.JSValue) !c.JSValue {
    const Adapter = struct {
        fn call(engine: *v.em.Engine, _: c.JSValue, args: []const c.JSValue, values: []const c.JSValue) !c.JSValue {
            return invoke(engine, operation, args, values);
        }
    };
    return scope.own(try functions.createArrow(scope.engine, name, length, Adapter.call, roots));
}
pub fn create(engine: *v.em.Engine, dependencies: Dependencies) !c.JSValue {
    if (!c.JS_IsFunction(engine.context, dependencies.get_model_type) or !c.JS_IsFunction(engine.context, dependencies.is_model_type) or !c.JS_IsFunction(engine.context, dependencies.fetch_with_retry) or !c.JS_IsFunction(engine.context, dependencies.get_pi_user_agent) or !c.JS_IsString(dependencies.version)) return error.ActualRemoteCatalogDependenciesRequired;
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const owner = try scope.object();
    inline for (.{ "getModelType", "isModelType", "fetchWithRetry", "getPiUserAgent", "VERSION" }, .{ dependencies.get_model_type, dependencies.is_model_type, dependencies.fetch_with_retry, dependencies.get_pi_user_agent, dependencies.version }) |name, value| try scope.put(owner, name, value);
    const types = try scope.array();
    inline for (.{ "chat", "image", "classifier" }, 0..) |name, index| try scope.index(types, index, try scope.text(name));
    try scope.put(owner, "types", types);
    try scope.put(owner, "supported", try scope.own(try functions.create(engine, "isSupportedModelType", 1, supported, &.{owner})));
    const result = try scope.object();
    try scope.put(result, "REMOTE_CATALOG_REFRESH_INTERVAL_MS", c.JS_NewInt32(engine.context, refresh_interval_ms));
    try scope.put(result, "REMOTE_CATALOG_MODEL_TYPES", types);
    try scope.put(result, "withRemoteCatalog", try scope.own(try functions.create(engine, "withRemoteCatalog", 1, remoteFactory, &.{owner})));
    try scope.put(result, "withPersonalizedCatalog", try scope.own(try functions.create(engine, "withPersonalizedCatalog", 2, personalFactory, &.{owner})));
    return c.JS_DupValue(engine.context, result);
}
fn remoteFactory(engine: *v.em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    return wrap(engine, roots[0], args, false);
}
fn personalFactory(engine: *v.em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    return wrap(engine, roots[0], args, true);
}
fn wrap(engine: *v.em.Engine, imports: c.JSValue, args: []const c.JSValue, personal: bool) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const owner = try scope.object();
    try scope.put(owner, "imports", imports);
    try scope.put(owner, "provider", arg(args, 0));
    const base = arg(args, if (personal) 2 else 1);
    try scope.put(owner, "base", if (c.JS_IsUndefined(base)) try scope.text("https://pi.dev") else base);
    try scope.put(owner, "generated", arg(args, if (personal) 3 else 2));
    try scope.put(owner, "personalize", if (personal) arg(args, 1) else c.pi_js_undefined());
    try scope.put(owner, "personal", c.pi_js_bool(engine.context, @intFromBool(personal)));
    try scope.put(owner, "models", try scope.array());
    const result = try v.spread(&scope, arg(args, 0));
    try scope.put(result, "getModels", if (personal) try arrow(&scope, "getModels", 0, .personal_get, &.{owner}) else try arrow(&scope, "getModels", 0, .remote_get, &.{owner}));
    try scope.put(result, "getAllModels", if (personal) try arrow(&scope, "getAllModels", 0, .personal_all, &.{owner}) else try arrow(&scope, "getAllModels", 0, .remote_all, &.{owner}));
    try scope.put(result, "refreshModels", try scope.own(try async_functions.asyncArrow(engine, "refreshModels", 1, refresh, &.{owner})));
    return c.JS_DupValue(engine.context, result);
}
fn builtin(scope: *Scope, owner: c.JSValue) !c.JSValue {
    const provider = try scope.get(owner, "provider");
    const all = try scope.get(provider, "getAllModels");
    const value = if (v.nullish(all)) c.pi_js_undefined() else try scope.call(all, provider, &.{});
    return if (v.nullish(value)) scope.invoke(provider, "getModels", &.{}) else value;
}
fn personalAll(scope: *Scope, owner: c.JSValue) !c.JSValue {
    const models = try scope.get(owner, "models");
    return if (try arithmetic.compare(scope.engine, .greater, try scope.get(models, "length"), c.JS_NewInt32(scope.engine.context, 0))) models else builtin(scope, owner);
}
fn filter(scope: *Scope, receiver: c.JSValue, comptime operation: Op, roots: []const c.JSValue) !c.JSValue {
    const method = try scope.get(receiver, "filter");
    const predicate = try arrow(scope, "", 1, operation, roots);
    return scope.call(method, receiver, &.{predicate});
}
fn appendIterable(scope: *Scope, array: c.JSValue, value: c.JSValue, index: *u32) !void {
    var iterator = try v.iterator(scope, value);
    defer iterator.deinit();
    errdefer iterator.closePreserving();
    while (try iterator.next()) |item| {
        defer scope.engine.freeValue(item);
        try scope.index(array, index.*, item);
        index.* += 1;
    }
}
fn merge(scope: *Scope, imports: c.JSValue, baseline: c.JSValue, dynamic: c.JSValue) !c.JSValue {
    const engine = scope.engine;
    const map = try scope.own(try v.js.builtin(engine, "Map", &.{}));
    const input = try scope.array();
    var index: u32 = 0;
    try appendIterable(scope, input, baseline, &index);
    try appendIterable(scope, input, dynamic, &index);
    var iterator = try v.iterator(scope, input);
    defer iterator.deinit();
    errdefer iterator.closePreserving();
    while (try iterator.next()) |model| {
        defer engine.freeValue(model);
        // Member callee lookup precedes the key's user-observable conversions.
        const setter = try scope.get(map, "set");
        const model_type = try scope.call(try scope.get(imports, "getModelType"), c.pi_js_undefined(), &.{model});
        var key = try scope.concat(try scope.stringify(model_type), try scope.text("\x00"));
        key = try scope.concat(key, try scope.stringify(try scope.get(model, "id")));
        _ = try scope.call(setter, map, &.{ key, model });
    }
    const values = try scope.invoke(map, "values", &.{});
    const result = try scope.array();
    index = 0;
    try appendIterable(scope, result, values, &index);
    return result;
}
fn supported(engine: *v.em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const model = arg(args, 0);
    if (c.JS_IsUndefined(try scope.get(model, "type"))) return c.pi_js_bool(engine.context, 1);
    if (!c.JS_IsString(try scope.get(model, "type"))) return c.pi_js_bool(engine.context, 0);
    const types = try scope.get(roots[0], "types");
    const includes = try scope.get(types, "includes");
    return c.JS_DupValue(engine.context, try scope.call(includes, types, &.{try scope.get(model, "type")}));
}
fn invoke(engine: *v.em.Engine, operation: Op, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const owner = if (roots.len > 0) roots[0] else c.pi_js_undefined();
    const model = arg(args, 0);
    return switch (operation) {
        .remote_get => blk: {
            const baseline = try scope.invoke(try scope.get(owner, "provider"), "getModels", &.{});
            const dynamic = try filter(&scope, try scope.get(owner, "models"), .chat, &.{try scope.get(owner, "imports")});
            break :blk c.JS_DupValue(engine.context, try merge(&scope, try scope.get(owner, "imports"), baseline, dynamic));
        },
        .remote_all => c.JS_DupValue(engine.context, try merge(&scope, try scope.get(owner, "imports"), try builtin(&scope, owner), try scope.get(owner, "models"))),
        .personal_all => c.JS_DupValue(engine.context, try personalAll(&scope, owner)),
        .personal_get => c.JS_DupValue(engine.context, try filter(&scope, try personalAll(&scope, owner), .chat, &.{try scope.get(owner, "imports")})),
        .entry => c.pi_js_bool(engine.context, @intFromBool(c.JS_IsObject(model) and !c.JS_IsFunction(engine.context, model) and try v.js.hasKey(engine, model, try scope.text("id")))),
        .chat => c.JS_DupValue(engine.context, try scope.call(try scope.get(owner, "isModelType"), c.pi_js_undefined(), &.{ model, try scope.text("chat") })),
        .provider => c.pi_js_bool(engine.context, @intFromBool(scope.equal(try scope.get(model, "provider"), try scope.get(try scope.get(owner, "provider"), "id")))),
        .map_provider => blk: {
            const result = try v.spread(&scope, model);
            try scope.put(result, "provider", owner);
            break :blk c.JS_DupValue(engine.context, result);
        },
        .update => blk: {
            try scope.put(owner, "models", roots[1]);
            break :blk c.pi_js_undefined();
        },
    };
}
fn isNewer(scope: *Scope, last: c.JSValue, generated: c.JSValue) !bool {
    return c.JS_IsUndefined(generated) or (!c.JS_IsUndefined(last) and try arithmetic.compare(scope.engine, .greater, last, generated));
}
fn remoteModels(scope: *Scope, entry: c.JSValue, generated: c.JSValue) !c.JSValue {
    if (scope.truthy(entry) and try isNewer(scope, try scope.get(entry, "lastModified"), generated)) return scope.get(entry, "models");
    return scope.array();
}
fn parseCatalog(scope: *Scope, imports: c.JSValue, provider_id: c.JSValue, value: c.JSValue) !c.JSValue {
    var entries = c.pi_js_undefined();
    if (try v.array(scope, value)) {
        entries = value;
    } else if (c.JS_IsObject(value) and !c.JS_IsFunction(scope.engine.context, value) and try v.js.hasKey(scope.engine, value, try scope.text("models")) and try v.array(scope, try scope.get(value, "models"))) {
        entries = try scope.get(value, "models");
    } else if (c.JS_IsObject(value) and !c.JS_IsFunction(scope.engine.context, value)) {
        entries = try scope.invoke(try scope.global("Object"), "values", &.{value});
    }
    if (!scope.truthy(entries)) return catalogError(scope, provider_id, null);
    const valid = try filter(scope, entries, .entry, &.{});
    const supported_filter = try scope.get(valid, "filter");
    const supported_entries = try scope.call(supported_filter, valid, &.{try scope.get(imports, "supported")});
    const mapper = try scope.get(supported_entries, "map");
    return scope.call(mapper, supported_entries, &.{try arrow(scope, "", 1, .map_provider, &.{provider_id})});
}
fn catalogError(scope: *Scope, provider_id: c.JSValue, status: ?c.JSValue) anyerror {
    const constructor = scope.global("Error") catch |err| return err;
    var message = scope.concat(scope.text(if (status == null) "Invalid model catalog for provider \"" else "Model catalog request failed for ") catch |err| return err, scope.stringify(provider_id) catch |err| return err) catch |err| return err;
    message = if (status) |value| scope.concat(scope.concat(message, scope.text(": ") catch |err| return err) catch |err| return err, scope.stringify(value) catch |err| return err) catch |err| return err else scope.concat(message, scope.text("\"") catch |err| return err) catch |err| return err;
    var args = [_]c.JSValue{message};
    const reason = scope.own(scope.engine.checked(c.JS_CallConstructor(scope.engine.context, constructor, 1, &args)) catch |err| return err) catch |err| return err;
    _ = scope.engine.checked(c.JS_Throw(scope.engine.context, c.JS_DupValue(scope.engine.context, reason))) catch |err| return err;
    unreachable;
}
fn failedRequest(scope: *Scope, wrapper: c.JSValue, response: c.JSValue) anyerror {
    const constructor = scope.global("Error") catch |err| return err;
    const provider = scope.get(wrapper, "provider") catch |err| return err;
    const id = scope.get(provider, "id") catch |err| return err;
    var message = scope.concat(scope.text("Model catalog request failed for ") catch |err| return err, scope.stringify(id) catch |err| return err) catch |err| return err;
    message = scope.concat(message, scope.text(": ") catch |err| return err) catch |err| return err;
    message = scope.concat(message, scope.stringify(scope.get(response, "status") catch |err| return err) catch |err| return err) catch |err| return err;
    var args = [_]c.JSValue{message};
    const reason = scope.own(scope.engine.checked(c.JS_CallConstructor(scope.engine.context, constructor, 1, &args)) catch |err| return err) catch |err| return err;
    _ = scope.engine.checked(c.JS_Throw(scope.engine.context, c.JS_DupValue(scope.engine.context, reason))) catch |err| return err;
    unreachable;
}
fn request(scope: *Scope, imports: c.JSValue, provider_id: c.JSValue, base: c.JSValue, signal: c.JSValue, validator: c.JSValue) !c.JSValue {
    const constructor = try scope.global("URL");
    const encoded = try scope.call(try scope.global("encodeURIComponent"), c.pi_js_undefined(), &.{provider_id});
    const path = try scope.concat(try scope.text("/api/models/providers/"), try scope.stringify(encoded));
    var url_args = [_]c.JSValue{ path, base };
    const url = try scope.own(try scope.engine.checked(c.JS_CallConstructor(scope.engine.context, constructor, 2, &url_args)));
    const params = try scope.get(url, "searchParams");
    const set = try scope.get(params, "set");
    const joined = try scope.invoke(try scope.get(imports, "types"), "join", &.{try scope.text(",")});
    _ = try scope.call(set, params, &.{ try scope.text("types"), joined });
    const fetch = try scope.get(imports, "fetchWithRetry");
    const headers = try scope.object();
    try scope.put(headers, "accept", try scope.text("application/json"));
    try scope.put(headers, "User-Agent", try scope.call(try scope.get(imports, "getPiUserAgent"), c.pi_js_undefined(), &.{try scope.get(imports, "VERSION")}));
    if (scope.truthy(validator)) try scope.put(headers, "if-none-match", validator);
    const init = try scope.object();
    try scope.put(init, "headers", headers);
    try scope.put(init, "signal", signal);
    const options = try scope.object();
    try scope.put(options, "attemptTimeoutMs", c.JS_NewInt32(scope.engine.context, 4000));
    return scope.call(fetch, c.pi_js_undefined(), &.{ url, init, options });
}
fn publish(scope: *Scope, job: c.JSValue, persist: ?c.JSValue, update: ?c.JSValue, stage: Stage) !void {
    const context = try scope.get(job, "context");
    const method = try scope.get(context, "publish");
    return publishCaptured(scope, job, context, method, persist, update, stage);
}
fn publishCaptured(scope: *Scope, job: c.JSValue, context: c.JSValue, method: c.JSValue, persist: ?c.JSValue, update: ?c.JSValue, stage: Stage) !void {
    const record = try scope.object();
    if (persist) |entry| try scope.put(record, "persist", entry);
    if (update) |models| try scope.put(record, "update", try arrow(scope, "update", 0, .update, &.{ try scope.get(job, "wrapper"), models }));
    return flow.wait(advance, scope.engine, job, try scope.call(method, context, &.{record}), @intFromEnum(stage));
}
fn refresh(engine: *v.em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const pending = try flow.create(engine, c.pi_js_undefined());
    defer engine.freeValue(pending.owner);
    errdefer engine.freeValue(pending.promise);
    try scope.put(pending.owner, "wrapper", roots[0]);
    try scope.put(pending.owner, "context", arg(args, 0));
    start(&scope, pending.owner) catch |err| try flow.rejectError(engine, pending.owner, err);
    return pending.promise;
}
fn start(scope: *Scope, job: c.JSValue) !void {
    const wrapper = try scope.get(job, "wrapper");
    const context = try scope.get(job, "context");
    const stored = try scope.get(context, "stored");
    // Personal refresh does not snapshot stored; its only stored read is here.
    const personal = scope.truthy(try scope.get(wrapper, "personal"));
    if (!personal) try scope.put(job, "stored", stored);
    const models = if (personal) blk: {
        const supplied = try v.optional(scope, stored, "models");
        break :blk if (v.nullish(supplied)) try scope.array() else supplied;
    } else try remoteModels(scope, stored, try scope.get(wrapper, "generated"));
    const restored = try filter(scope, models, .provider, &.{wrapper});
    return publish(scope, job, null, restored, .restored);
}
fn abort(scope: *Scope, context: c.JSValue) !bool {
    return scope.truthy(try scope.get(try scope.get(context, "signal"), "aborted"));
}
fn settleDone(scope: *Scope, job: c.JSValue) !void {
    return flow.settle(scope.engine, job, false, c.pi_js_undefined());
}
fn advance(engine: *v.em.Engine, job: c.JSValue, value: c.JSValue, rejected: bool, raw: c_int) !void {
    if (rejected) return flow.settle(engine, job, true, value);
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    continueRefresh(&scope, job, value, @enumFromInt(raw)) catch |err| try flow.rejectError(engine, job, err);
}
fn persistBase(scope: *Scope, stored: c.JSValue) !c.JSValue {
    if (!v.nullish(stored)) return v.spread(scope, stored);
    const result = try scope.object();
    try scope.put(result, "models", try scope.array());
    return result;
}
fn continueRefresh(scope: *Scope, job: c.JSValue, value: c.JSValue, stage: Stage) !void {
    const engine = scope.engine;
    const wrapper = try scope.get(job, "wrapper");
    const imports = try scope.get(wrapper, "imports");
    const context = try scope.get(job, "context");
    const personal = scope.truthy(try scope.get(wrapper, "personal"));
    switch (stage) {
        .restored => {
            if (!scope.truthy(value) or !scope.truthy(try scope.get(context, "allowNetwork")) or try abort(scope, context)) return settleDone(scope, job);
            const stored = if (personal) c.pi_js_undefined() else try scope.get(job, "stored");
            if (!personal and !scope.truthy(try scope.get(context, "force")) and !c.JS_IsUndefined(try v.optional(scope, stored, "checkedAt")) and !c.JS_IsUndefined(try scope.get(stored, "lastModified"))) {
                const now = try scope.invoke(try scope.global("Date"), "now", &.{});
                const delta = try scope.own(try arithmetic.binary(engine, .subtract, now, try scope.get(stored, "checkedAt")));
                if (try arithmetic.compare(engine, .less, delta, c.JS_NewInt32(engine.context, refresh_interval_ms))) return settleDone(scope, job);
            }
            const validator = if (!personal and scope.truthy(stored) and try arithmetic.compare(engine, .greater, try scope.get(try scope.get(stored, "models"), "length"), c.JS_NewInt32(engine.context, 0))) try scope.get(stored, "etag") else c.pi_js_undefined();
            const provider_id = try scope.get(try scope.get(wrapper, "provider"), "id");
            const result = try request(scope, imports, provider_id, try scope.get(wrapper, "base"), try scope.get(context, "signal"), validator);
            return flow.wait(advance, engine, job, result, @intFromEnum(Stage.response));
        },
        .response => {
            if (try abort(scope, context)) return settleDone(scope, job);
            try scope.put(job, "response", value);
            if (personal) {
                if (!scope.equal(try scope.get(value, "status"), c.JS_NewInt32(engine.context, 404)) and !scope.equal(try scope.get(value, "status"), c.JS_NewInt32(engine.context, 501))) {
                    if (!scope.truthy(try scope.get(value, "ok"))) return failedRequest(scope, wrapper, value);
                    return beginRead(scope, job, wrapper, value);
                }
                return personalize(scope, job, try scope.array());
            }
            const checked = try scope.invoke(try scope.global("Date"), "now", &.{});
            try scope.put(job, "checked", checked);
            const stored = try scope.get(job, "stored");
            if (scope.equal(try scope.get(value, "status"), c.JS_NewInt32(engine.context, 304)) and scope.truthy(stored)) {
                const publisher = try scope.get(context, "publish");
                const persist = try v.spread(scope, stored);
                try scope.put(persist, "checkedAt", checked);
                return publishCaptured(scope, job, context, publisher, persist, null, .finished);
            }
            if (scope.equal(try scope.get(value, "status"), c.JS_NewInt32(engine.context, 404)) or scope.equal(try scope.get(value, "status"), c.JS_NewInt32(engine.context, 501))) {
                const publisher = try scope.get(context, "publish");
                const persist = try persistBase(scope, stored);
                try scope.put(persist, "checkedAt", checked);
                try scope.put(persist, "lastModified", c.JS_NewInt32(engine.context, 0));
                try scope.put(persist, "etag", c.pi_js_undefined());
                return publishCaptured(scope, job, context, publisher, persist, null, .finished);
            }
            if (!scope.truthy(try scope.get(value, "ok"))) {
                const publisher = try scope.get(context, "publish");
                const persist = try persistBase(scope, stored);
                try scope.put(persist, "checkedAt", checked);
                return publishCaptured(scope, job, context, publisher, persist, null, .failed_published);
            }
            return beginRead(scope, job, wrapper, value);
        },
        .read_catalog => {
            if (personal) {
                const remote = if (try isNewer(scope, try scope.get(value, "lastModified"), try scope.get(wrapper, "generated"))) try scope.get(value, "models") else try scope.array();
                return personalize(scope, job, remote);
            }
            if (try abort(scope, context)) return settleDone(scope, job);
            const entry = try v.spread(scope, value);
            try scope.put(entry, "checkedAt", try scope.get(job, "checked"));
            const models = try remoteModels(scope, entry, try scope.get(wrapper, "generated"));
            return publish(scope, job, entry, models, .published);
        },
        .personalized => {
            if (try abort(scope, context)) return settleDone(scope, job);
            // Callee lookup happens before the checkedAt Date.now getter/call.
            const publisher = try scope.get(context, "publish");
            const persist = try scope.object();
            try scope.put(persist, "models", value);
            try scope.put(persist, "checkedAt", try scope.invoke(try scope.global("Date"), "now", &.{}));
            const record = try scope.object();
            try scope.put(record, "persist", persist);
            try scope.put(record, "update", try arrow(scope, "update", 0, .update, &.{ wrapper, value }));
            return flow.wait(advance, engine, job, try scope.call(publisher, context, &.{record}), @intFromEnum(Stage.published));
        },
        .failed_published => return failedRequest(scope, wrapper, try scope.get(job, "response")),
        .published, .finished => return settleDone(scope, job),
    }
}
fn personalize(scope: *Scope, job: c.JSValue, remote: c.JSValue) !void {
    const wrapper = try scope.get(job, "wrapper");
    const callback = try scope.get(wrapper, "personalize");
    const merged = try merge(scope, try scope.get(wrapper, "imports"), try builtin(scope, wrapper), remote);
    return flow.wait(advance, scope.engine, job, try scope.call(callback, c.pi_js_undefined(), &.{ merged, try scope.get(job, "context") }), @intFromEnum(Stage.personalized));
}
fn beginRead(scope: *Scope, job: c.JSValue, wrapper: c.JSValue, response: c.JSValue) !void {
    const pending = try flow.create(scope.engine, c.pi_js_undefined());
    defer scope.engine.freeValue(pending.owner);
    defer scope.engine.freeValue(pending.promise);
    try scope.put(pending.owner, "imports", try scope.get(wrapper, "imports"));
    try scope.put(pending.owner, "providerId", try scope.get(try scope.get(wrapper, "provider"), "id"));
    try scope.put(pending.owner, "response", response);
    readStart(scope, pending.owner, response) catch |err| try flow.rejectError(scope.engine, pending.owner, err);
    return flow.wait(advance, scope.engine, job, pending.promise, @intFromEnum(Stage.read_catalog));
}
fn readStart(scope: *Scope, owner: c.JSValue, response: c.JSValue) !void {
    const date = try scope.global("Date");
    const parse = try scope.get(date, "parse");
    const modified = try scope.invoke(try scope.get(response, "headers"), "get", &.{try scope.text("last-modified")});
    try scope.put(owner, "lastModified", try scope.call(parse, date, &.{if (v.nullish(modified)) try scope.text("") else modified}));
    const json = try scope.invoke(response, "json", &.{});
    return flow.wait(readReady, scope.engine, owner, json, 0);
}
fn readReady(engine: *v.em.Engine, owner: c.JSValue, value: c.JSValue, rejected: bool, _: c_int) !void {
    if (rejected) return flow.settle(engine, owner, true, value);
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    finishRead(&scope, owner, value) catch |err| try flow.rejectError(engine, owner, err);
}
fn finishRead(scope: *Scope, owner: c.JSValue, value: c.JSValue) !void {
    const result = try scope.object();
    try scope.put(result, "models", try parseCatalog(scope, try scope.get(owner, "imports"), try scope.get(owner, "providerId"), value));
    const last = try scope.get(owner, "lastModified");
    const invalid = try scope.invoke(try scope.global("Number"), "isNaN", &.{last});
    try scope.put(result, "lastModified", if (scope.truthy(invalid)) c.JS_NewInt32(scope.engine.context, 0) else last);
    const etag = try scope.invoke(try scope.get(try scope.get(owner, "response"), "headers"), "get", &.{try scope.text("etag")});
    try scope.put(result, "etag", if (v.nullish(etag)) c.pi_js_undefined() else etag);
    return flow.settle(scope.engine, owner, false, result);
}
