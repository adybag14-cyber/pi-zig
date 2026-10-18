//! Actual coding-agent remote-catalog-provider.ts wrappers. Real management HTTP,
//! type helpers and runtime user-agent bindings are mandatory borrowed imports.
//! Providers and context callbacks remain genuine guest values and live calls.
const v = @import("native_ai_provider_values.zig");
const x = @import("native_sdk_catalog_values.zig");
const Scope = x.Ops;
const copy = @import("native_sdk_catalog_copy.zig");
const af = x.af;
const c = v.c;
const functions = @import("native_node_function.zig");
const arithmetic = @import("native_image_arithmetic.zig");
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
    return scope.own(try functions.createArrow(scope.s.engine, name, length, Adapter.call, roots));
}
pub fn create(engine: *v.em.Engine, dependencies: Dependencies) !c.JSValue {
    engine.native_exception_diagnostics_suppressed += 1; defer engine.native_exception_diagnostics_suppressed -= 1;
    try engine.checkNativeEntry();
    var invocation: v.em.Engine.NativeInvocation = .{}; engine.enterNativeInvocation(&invocation);
    var storage: x.Scope = .{ .engine = engine }; var scope: Scope = .{ .s = &storage };
    const result = x.owned.finishValue(&storage, createBody(&scope, dependencies)) catch |err| @import("native_sdk.zig").fail(engine, err);
    return engine.checked(engine.leaveNativeInvocation(&invocation, result));
}
fn createBody(scope: *Scope, dependencies: Dependencies) !c.JSValue {
    const engine = scope.s.engine;
    if (!c.JS_IsFunction(engine.context, dependencies.get_model_type) or !c.JS_IsFunction(engine.context, dependencies.is_model_type) or !c.JS_IsFunction(engine.context, dependencies.fetch_with_retry) or !c.JS_IsFunction(engine.context, dependencies.get_pi_user_agent) or !c.JS_IsString(dependencies.version)) return error.ActualRemoteCatalogDependenciesRequired;
    const owner = try scope.object();
    inline for (.{ "getModelType", "isModelType", "fetchWithRetry", "getPiUserAgent", "VERSION" }, .{ dependencies.get_model_type, dependencies.is_model_type, dependencies.fetch_with_retry, dependencies.get_pi_user_agent, dependencies.version }) |name, value| try scope.put(owner, name, value);
    const types = try scope.array();
    inline for (.{ "chat", "image", "classifier" }, 0..) |name, index| try scope.index(types, index, try scope.text(name));
    try scope.put(owner, "types", types);
    try scope.put(owner, "readCatalog", try scope.own(try af.createResumable(engine, "readCatalog", 2, readCatalog, &.{owner})));
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
    var storage: x.Scope = .{ .engine = engine }; var scope: Scope = .{ .s = &storage };
    return x.owned.finishValue(&storage, wrapBody(&scope, imports, args, personal));
}
fn wrapBody(scope: *Scope, imports: c.JSValue, args: []const c.JSValue, personal: bool) !c.JSValue {
    const engine = scope.s.engine;
    const owner = try scope.object();
    try scope.put(owner, "imports", imports);
    try scope.put(owner, "provider", arg(args, 0));
    const base = arg(args, if (personal) 2 else 1);
    try scope.put(owner, "base", if (c.JS_IsUndefined(base)) try scope.text("https://pi.dev") else base);
    try scope.put(owner, "generated", arg(args, if (personal) 3 else 2));
    try scope.put(owner, "personalize", if (personal) arg(args, 1) else c.pi_js_undefined());
    try scope.put(owner, "personal", c.pi_js_bool(engine.context, @intFromBool(personal)));
    try scope.put(owner, "models", try scope.array());
    const result = try copy.object(scope, arg(args, 0));
    try scope.put(result, "getModels", if (personal) try arrow(scope, "getModels", 0, .personal_get, &.{owner}) else try arrow(scope, "getModels", 0, .remote_get, &.{owner}));
    try scope.put(result, "getAllModels", if (personal) try arrow(scope, "getAllModels", 0, .personal_all, &.{owner}) else try arrow(scope, "getAllModels", 0, .remote_all, &.{owner}));
    try scope.put(result, "refreshModels", try scope.own(try af.createResumableArrow(engine, "refreshModels", 1, refresh, &.{owner}, c.pi_js_undefined())));
    return c.JS_DupValue(engine.context, result);
}
fn builtin(scope: *Scope, owner: c.JSValue) !c.JSValue {
    const provider = try scope.get(owner, "provider");
    const all = try scope.get(provider, "getAllModels");
    const value = if (x.nullish(all)) c.pi_js_undefined() else try scope.call(all, provider, &.{});
    return if (x.nullish(value)) scope.invoke(provider, "getModels", &.{}) else value;
}
fn personalAll(scope: *Scope, owner: c.JSValue) !c.JSValue {
    const models = try scope.get(owner, "models");
    return if (try scope.compare(.greater, try scope.get(models, "length"), c.JS_NewInt32(scope.s.engine.context, 0))) scope.get(owner, "models") else builtin(scope, owner);
}
fn filter(scope: *Scope, receiver: c.JSValue, comptime operation: Op, roots: []const c.JSValue) !c.JSValue {
    const method = try scope.get(receiver, "filter");
    const predicate = try arrow(scope, "", 1, operation, roots);
    return scope.call(method, receiver, &.{predicate});
}
const Iterator = struct { iterator: c.JSValue, next: c.JSValue };
fn iterator(scope: *Scope, value: c.JSValue) !Iterator {
    const engine = scope.s.engine;
    var storage: x.Scope = .{ .engine = engine }; var local: Scope = .{ .s = &storage };
    var next_value = c.pi_js_undefined();
    const selected = x.owned.finishValue(&storage, iteratorBody(&local, value, &next_value));
    const iter = selected catch |err| {
        var failed = x.owned.Completion.initVoid(engine, err); failed.release(next_value); try failed.finishVoid(); unreachable;
    };
    const held = scope.own(iter) catch |err| {
        var failed = x.owned.Completion.initVoid(engine, err); failed.release(next_value); try failed.finishVoid(); unreachable;
    };
    return .{ .iterator = held, .next = try scope.own(next_value) };
}
fn iteratorBody(scope: *Scope, value: c.JSValue, next_value: *c.JSValue) !c.JSValue {
    const symbol = try scope.iteratorSymbol();
    const result = try scope.call(try scope.key(value, symbol), value, &.{});
    if (!c.JS_IsObject(result)) return scope.typeError("Iterator is not an object");
    next_value.* = c.JS_DupValue(scope.s.engine.context, try scope.get(result, "next"));
    return c.JS_DupValue(scope.s.engine.context, result);
}
fn nextOwned(engine: *v.em.Engine, iter: Iterator, is_done: *bool) !c.JSValue {
    var storage: x.Scope = .{ .engine = engine }; var scope: Scope = .{ .s = &storage };
    return x.owned.finishValue(&storage, nextBody(&scope, iter, is_done));
}
fn nextBody(scope: *Scope, iter: Iterator, is_done: *bool) !c.JSValue {
    const step = try scope.call(iter.next, iter.iterator, &.{});
    if (!c.JS_IsObject(step)) return scope.typeError("Iterator result is not an object");
    if (scope.truthy(try scope.get(step, "done"))) { is_done.* = true; return c.pi_js_undefined(); }
    is_done.* = false;
    return c.JS_DupValue(scope.s.engine.context, try scope.get(step, "value"));
}
fn appendIterable(scope: *Scope, array: c.JSValue, value: c.JSValue, index: *u32) !void {
    var storage: x.Scope = .{ .engine = scope.s.engine }; var local: Scope = .{ .s = &storage };
    return x.owned.finishVoid(&storage, appendBody(&local, array, value, index));
}
fn appendBody(scope: *Scope, array: c.JSValue, value: c.JSValue, index: *u32) !void {
    const iter = try iterator(scope, value);
    while (true) {
        var exhausted = false;
        const item = try nextOwned(scope.s.engine, iter, &exhausted);
        if (exhausted) return;
        var completion = x.owned.Completion.initVoid(scope.s.engine, scope.index(array, index.*, item));
        completion.release(item);
        try completion.finishVoid();
        index.* += 1;
    }
}
fn merge(scope: *Scope, imports: c.JSValue, baseline: c.JSValue, dynamic: c.JSValue) !c.JSValue {
    var storage: x.Scope = .{ .engine = scope.s.engine }; var local: Scope = .{ .s = &storage };
    return scope.own(try x.owned.finishValue(&storage, mergeBody(&local, imports, baseline, dynamic)));
}
fn mergeBody(scope: *Scope, imports: c.JSValue, baseline: c.JSValue, dynamic: c.JSValue) !c.JSValue {
    const map = try scope.construct(try scope.global("Map"), &.{});
    try mergeInput(scope, imports, map, baseline, dynamic);
    const values = try scope.own(try scope.invokeOwned(map, "values", &.{}));
    const result = try scope.array(); var index: u32 = 0;
    try appendIterable(scope, result, values, &index);
    return c.JS_DupValue(scope.s.engine.context, result);
}
fn mergeInput(scope: *Scope, imports: c.JSValue, map: c.JSValue, baseline: c.JSValue, dynamic: c.JSValue) !void {
    var storage: x.Scope = .{ .engine = scope.s.engine }; var local: Scope = .{ .s = &storage };
    return x.owned.finishVoid(&storage, mergeInputBody(&local, imports, map, baseline, dynamic));
}
fn mergedInputOwned(scope: *Scope, baseline: c.JSValue, dynamic: c.JSValue) !c.JSValue {
    var storage: x.Scope = .{ .engine = scope.s.engine }; var local: Scope = .{ .s = &storage };
    return x.owned.finishValue(&storage, mergedInputBody(&local, baseline, dynamic));
}
fn mergedInputBody(scope: *Scope, baseline: c.JSValue, dynamic: c.JSValue) !c.JSValue {
    const input = try scope.array(); var index: u32 = 0;
    try appendIterable(scope, input, baseline, &index); try appendIterable(scope, input, dynamic, &index);
    return c.JS_DupValue(scope.s.engine.context, input);
}
fn mergedIterator(scope: *Scope, baseline: c.JSValue, dynamic: c.JSValue) !Iterator {
    const input = try mergedInputOwned(scope, baseline, dynamic);
    const outcome = iterator(scope, input);
    var completion = x.owned.Completion.initVoid(scope.s.engine, if (outcome) |_| {} else |err| err);
    completion.release(input); try completion.finishVoid();
    return outcome;
}
fn mergeInputBody(scope: *Scope, imports: c.JSValue, map: c.JSValue, baseline: c.JSValue, dynamic: c.JSValue) !void {
    const iter = try mergedIterator(scope, baseline, dynamic);
    while (true) {
        var exhausted = false;
        const model = try nextOwned(scope.s.engine, iter, &exhausted);
        if (exhausted) return;
        var completion = x.owned.Completion.initVoid(scope.s.engine, mergeEntry(scope, imports, map, model));
        completion.release(model);
        const action = try completion.finishAction();
        switch (action) {
            .returned => {},
            .thrown => |reason| {
                var closed = x.owned.Completion.initVoid(scope.s.engine, closeIterator(scope, iter.iterator));
                const close_action = closed.finishAction() catch |err| {
                    var fatal = x.owned.Completion.initVoid(scope.s.engine, err); fatal.release(reason); return fatal.finishVoid();
                };
                var original = x.owned.Completion.initAction(scope.s.engine, .{ .thrown = reason });
                switch (close_action) { .returned, .thrown => |value| original.release(value), .awaited => unreachable }
                return original.finishVoid();
            },
            .awaited => unreachable,
        }
    }
}
fn mergeEntry(scope: *Scope, imports: c.JSValue, map: c.JSValue, model: c.JSValue) !void {
    var storage: x.Scope = .{ .engine = scope.s.engine }; var local: Scope = .{ .s = &storage };
    return x.owned.finishVoid(&storage, mergeEntryBody(&local, imports, map, model));
}
fn mergeEntryBody(scope: *Scope, imports: c.JSValue, map: c.JSValue, model: c.JSValue) !void {
    const setter = try scope.get(map, "set");
    const model_type = try scope.call(try scope.get(imports, "getModelType"), c.pi_js_undefined(), &.{model});
    var key = try scope.concat(try scope.stringify(model_type), try scope.text("\x00"));
    key = try scope.concat(key, try scope.stringify(try scope.get(model, "id")));
    _ = try scope.call(setter, map, &.{key, model});
}
fn closeIterator(scope: *Scope, iter: c.JSValue) !void {
    const close = try scope.get(iter, "return");
    if (x.nullish(close)) return;
    const result = try scope.call(close, iter, &.{});
    if (!c.JS_IsObject(result)) return scope.typeError("Iterator return is not an object");
}
fn supported(engine: *v.em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    var storage: x.Scope = .{ .engine = engine }; var scope: Scope = .{ .s = &storage };
    return x.owned.finishValue(&storage, supportedBody(&scope, args, roots));
}
fn supportedBody(scope: *Scope, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    const engine = scope.s.engine;
    const model = arg(args, 0);
    if (try scope.fieldTest(model, "type", .undefined_value)) return c.pi_js_bool(engine.context, 1);
    if (!try scope.fieldTest(model, "type", .string_value)) return c.pi_js_bool(engine.context, 0);
    const types = try scope.get(roots[0], "types");
    const includes = try scope.get(types, "includes");
    return c.JS_DupValue(engine.context, try scope.call(includes, types, &.{try scope.get(model, "type")}));
}
fn invoke(engine: *v.em.Engine, operation: Op, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    var storage: x.Scope = .{ .engine = engine }; var scope: Scope = .{ .s = &storage };
    return x.owned.finishValue(&storage, invokeBody(&scope, operation, args, roots));
}
fn invokeBody(scope: *Scope, operation: Op, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    const engine = scope.s.engine;
    const owner = if (roots.len > 0) roots[0] else c.pi_js_undefined();
    const model = arg(args, 0);
    return switch (operation) {
        .remote_get => blk: {
            const baseline = try scope.invoke(try scope.get(owner, "provider"), "getModels", &.{});
            const dynamic = try filter(scope, try scope.get(owner, "models"), .chat, &.{try scope.get(owner, "imports")});
            break :blk c.JS_DupValue(engine.context, try merge(scope, try scope.get(owner, "imports"), baseline, dynamic));
        },
        .remote_all => c.JS_DupValue(engine.context, try merge(scope, try scope.get(owner, "imports"), try builtin(scope, owner), try scope.get(owner, "models"))),
        .personal_all => c.JS_DupValue(engine.context, try personalAll(scope, owner)),
        .personal_get => c.JS_DupValue(engine.context, try filter(scope, try personalAll(scope, owner), .chat, &.{try scope.get(owner, "imports")})),
        .entry => c.pi_js_bool(engine.context, @intFromBool(c.JS_IsObject(model) and !c.JS_IsFunction(engine.context, model) and try scope.has(model, "id"))),
        .chat => c.JS_DupValue(engine.context, try scope.call(try scope.get(owner, "isModelType"), c.pi_js_undefined(), &.{ model, try scope.text("chat") })),
        .provider => c.pi_js_bool(engine.context, @intFromBool(scope.equal(try scope.get(model, "provider"), try scope.get(try scope.get(owner, "provider"), "id")))),
        .map_provider => blk: {
            const result = try copy.object(scope, model);
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
    return c.JS_IsUndefined(generated) or (!c.JS_IsUndefined(last) and try scope.compare(.greater, last, generated));
}
fn remoteModels(scope: *Scope, entry: c.JSValue, generated: c.JSValue) !c.JSValue {
    if (scope.truthy(entry) and try isNewer(scope, try scope.get(entry, "lastModified"), generated)) return scope.get(entry, "models");
    return scope.array();
}
fn parseCatalog(scope: *Scope, imports: c.JSValue, provider_id: c.JSValue, value: c.JSValue) !c.JSValue {
    var storage: x.Scope = .{ .engine = scope.s.engine }; var local: Scope = .{ .s = &storage };
    return scope.own(try x.owned.finishValue(&storage, parseCatalogBody(&local, imports, provider_id, value)));
}
fn parseCatalogBody(scope: *Scope, imports: c.JSValue, provider_id: c.JSValue, value: c.JSValue) !c.JSValue {
    var entries = c.pi_js_undefined();
    if (try scope.isArray(value)) {
        entries = value;
    } else if (c.JS_IsObject(value) and !c.JS_IsFunction(scope.s.engine.context, value) and try scope.has(value, "models") and try modelsIsArray(scope, value)) {
        entries = try scope.get(value, "models");
    } else if (c.JS_IsObject(value) and !c.JS_IsFunction(scope.s.engine.context, value)) {
        entries = try scope.invoke(try scope.global("Object"), "values", &.{value});
    }
    if (!scope.truthy(entries)) return catalogError(scope, provider_id, null);
    const valid = try filter(scope, entries, .entry, &.{});
    const supported_filter = try scope.get(valid, "filter");
    const supported_entries = try scope.call(supported_filter, valid, &.{try scope.get(imports, "supported")});
    const mapper = try scope.get(supported_entries, "map");
    return c.JS_DupValue(scope.s.engine.context, try scope.call(mapper, supported_entries, &.{try arrow(scope, "", 1, .map_provider, &.{provider_id})}));
}
fn modelsIsArray(scope: *Scope, value: c.JSValue) !bool {
    var storage: x.Scope = .{ .engine = scope.s.engine }; var local: Scope = .{ .s = &storage };
    return scope.truthy(try x.owned.finishValue(&storage, modelsIsArrayBody(&local, value)));
}
fn modelsIsArrayBody(scope: *Scope, value: c.JSValue) !c.JSValue {
    // Array.isArray's receiver and callee precede the user-observable models getter.
    const array = try scope.global("Array");
    const method = try scope.get(array, "isArray");
    return c.pi_js_bool(scope.s.engine.context, @intFromBool(scope.truthy(try scope.call(method, array, &.{try scope.get(value, "models")}))));
}
fn throwData(scope: *Scope, reason: c.JSValue) anyerror {
    const engine = scope.s.engine;
    engine.checkNativeEntry() catch |err| return err;
    var completion = x.owned.Completion.initAction(engine, .{ .thrown = c.JS_DupValue(engine.context, reason) });
    const selected = completion.finishAction() catch |err| return err;
    switch (selected) {
        .thrown => |owned_reason| { engine.captured_exception = owned_reason; return error.JavaScriptException; },
        else => unreachable,
    }
}
fn catalogError(scope: *Scope, provider_id: c.JSValue, status: ?c.JSValue) anyerror {
    const constructor = scope.global("Error") catch |err| return err;
    var message = scope.concat(scope.text(if (status == null) "Invalid model catalog for provider \"" else "Model catalog request failed for ") catch |err| return err, scope.stringify(provider_id) catch |err| return err) catch |err| return err;
    message = if (status) |value| scope.concat(scope.concat(message, scope.text(": ") catch |err| return err) catch |err| return err, scope.stringify(value) catch |err| return err) catch |err| return err else scope.concat(message, scope.text("\"") catch |err| return err) catch |err| return err;
    const args = [_]c.JSValue{message};
    const reason = scope.construct(constructor, &args) catch |err| return err;
    return throwData(scope, reason);
}
fn failedRequest(scope: *Scope, wrapper: c.JSValue, response: c.JSValue) anyerror {
    const constructor = scope.global("Error") catch |err| return err;
    const provider = scope.get(wrapper, "provider") catch |err| return err;
    const id = scope.get(provider, "id") catch |err| return err;
    var message = scope.concat(scope.text("Model catalog request failed for ") catch |err| return err, scope.stringify(id) catch |err| return err) catch |err| return err;
    message = scope.concat(message, scope.text(": ") catch |err| return err) catch |err| return err;
    message = scope.concat(message, scope.stringify(scope.get(response, "status") catch |err| return err) catch |err| return err) catch |err| return err;
    const args = [_]c.JSValue{message};
    const reason = scope.construct(constructor, &args) catch |err| return err;
    return throwData(scope, reason);
}
fn request(scope: *Scope, imports: c.JSValue, provider_id: c.JSValue, base: c.JSValue, signal: c.JSValue, validator: c.JSValue) !c.JSValue {
    var storage: x.Scope = .{ .engine = scope.s.engine }; var local: Scope = .{ .s = &storage };
    return scope.own(try x.owned.finishValue(&storage, requestBody(&local, imports, provider_id, base, signal, validator)));
}
fn requestUrl(scope: *Scope, provider_id: c.JSValue, base: c.JSValue) !c.JSValue {
    var storage: x.Scope = .{ .engine = scope.s.engine }; var local: Scope = .{ .s = &storage };
    return scope.own(try x.owned.finishValue(&storage, requestUrlBody(&local, provider_id, base)));
}
fn requestUrlBody(scope: *Scope, provider_id: c.JSValue, base: c.JSValue) !c.JSValue {
    const constructor = try scope.global("URL");
    const encoded = try scope.call(try scope.global("encodeURIComponent"), c.pi_js_undefined(), &.{provider_id});
    const path = try scope.concat(try scope.text("/api/models/providers/"), try scope.stringify(encoded));
    return c.JS_DupValue(scope.s.engine.context, try scope.construct(constructor, &.{path, base}));
}
fn requestQuery(scope: *Scope, imports: c.JSValue, url: c.JSValue) !void {
    var storage: x.Scope = .{ .engine = scope.s.engine }; var local: Scope = .{ .s = &storage };
    return x.owned.finishVoid(&storage, requestQueryBody(&local, imports, url));
}
fn requestQueryBody(scope: *Scope, imports: c.JSValue, url: c.JSValue) !void {
    const params = try scope.get(url, "searchParams");
    const setter = try scope.get(params, "set");
    const joined = try scope.invoke(try scope.get(imports, "types"), "join", &.{try scope.text(",")});
    _ = try scope.call(setter, params, &.{ try scope.text("types"), joined });
}
fn requestBody(scope: *Scope, imports: c.JSValue, provider_id: c.JSValue, base: c.JSValue, signal: c.JSValue, validator: c.JSValue) !c.JSValue {
    const url = try requestUrl(scope, provider_id, base);
    try requestQuery(scope, imports, url);
    const fetch = try scope.get(imports, "fetchWithRetry");
    const headers = try scope.object();
    try scope.put(headers, "accept", try scope.text("application/json"));
    try scope.put(headers, "User-Agent", try scope.call(try scope.get(imports, "getPiUserAgent"), c.pi_js_undefined(), &.{try scope.get(imports, "VERSION")}));
    if (scope.truthy(validator)) try scope.put(headers, "if-none-match", validator);
    const init = try scope.object();
    try scope.put(init, "headers", headers);
    try scope.put(init, "signal", signal);
    const options = try scope.object();
    try scope.put(options, "attemptTimeoutMs", c.JS_NewInt32(scope.s.engine.context, 4000));
    return c.JS_DupValue(scope.s.engine.context, try scope.call(fetch, c.pi_js_undefined(), &.{ url, init, options }));
}
fn done() af.Action { return .{ .returned = c.pi_js_undefined() }; }
fn wait(scope: *Scope, job: c.JSValue, stage: Stage, value: c.JSValue) !af.Action {
    try scope.put(job, "stage", c.JS_NewInt32(scope.s.engine.context, @intFromEnum(stage)));
    return .{ .awaited = c.JS_DupValue(scope.s.engine.context, value) };
}
fn publish(scope: *Scope, job: c.JSValue, persist: ?c.JSValue, update: ?c.JSValue, stage: Stage) !af.Action {
    const context = try scope.get(job, "context");
    const method = try scope.get(context, "publish");
    return publishCaptured(scope, job, context, method, persist, update, stage);
}
fn publishCaptured(scope: *Scope, job: c.JSValue, context: c.JSValue, method: c.JSValue, persist: ?c.JSValue, update: ?c.JSValue, stage: Stage) !af.Action {
    const record = try scope.object();
    if (persist) |entry| try scope.put(record, "persist", entry);
    if (update) |models| try scope.put(record, "update", try arrow(scope, "update", 0, .update, &.{ try scope.get(job, "wrapper"), models }));
    return wait(scope, job, stage, try scope.call(method, context, &.{record}));
}
fn refresh(engine: *v.em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue, state: *c.JSValue, completion: af.Completion, value: c.JSValue) !af.Action {
    var storage: x.Scope = .{ .engine = engine }; var scope: Scope = .{ .s = &storage };
    return x.owned.finishAction(&storage, refreshBody(&scope, args, roots, state, completion, value));
}
fn refreshBody(scope: *Scope, args: []const c.JSValue, roots: []const c.JSValue, state: *c.JSValue, completion: af.Completion, value: c.JSValue) !af.Action {
    const engine = scope.s.engine;
    if (completion == .rejected) {
        try @import("native_async_body.zig").enterRejectedContinuation(engine);
        return .{ .thrown = c.JS_DupValue(engine.context, value) };
    }
    if (completion == .start) {
        const job = try scope.cell(); af.replaceState(engine, state, c.JS_DupValue(engine.context, job)); try engine.checkNativeEntry();
        try scope.put(job, "wrapper", roots[0]); try scope.put(job, "context", arg(args, 0));
        return start(scope, job);
    }
    var stage: i32 = 0;
    if (c.JS_ToInt32(engine.context, &stage, try scope.get(state.*, "stage")) < 0) return @import("native_js_values.zig").capture(engine);
    return continueRefresh(scope, state.*, value, @enumFromInt(stage));
}
fn start(scope: *Scope, job: c.JSValue) !af.Action {
    const wrapper = try scope.get(job, "wrapper");
    const context = try scope.get(job, "context");
    const stored = try scope.get(context, "stored");
    const personal = scope.truthy(try scope.get(wrapper, "personal"));
    if (!personal) try scope.put(job, "stored", stored);
    const models = if (personal) blk: {
        const supplied = try scope.optional(stored, "models");
        break :blk if (x.nullish(supplied)) try scope.array() else supplied;
    } else try remoteModels(scope, stored, try scope.get(wrapper, "generated"));
    const restored = try filter(scope, models, .provider, &.{wrapper});
    return publish(scope, job, null, restored, .restored);
}
fn abort(scope: *Scope, context: c.JSValue) !bool {
    var storage: x.Scope = .{ .engine = scope.s.engine }; var local: Scope = .{ .s = &storage };
    return scope.truthy(try x.owned.finishValue(&storage, abortBody(&local, context)));
}
fn abortBody(scope: *Scope, context: c.JSValue) !c.JSValue {
    return c.pi_js_bool(scope.s.engine.context, @intFromBool(scope.truthy(try scope.get(try scope.get(context, "signal"), "aborted"))));
}
fn freshEnough(scope: *Scope, context: c.JSValue, stored: c.JSValue) !bool {
    var storage: x.Scope = .{ .engine = scope.s.engine }; var local: Scope = .{ .s = &storage };
    return scope.truthy(try x.owned.finishValue(&storage, freshnessBody(&local, context, stored)));
}
fn freshnessBody(scope: *Scope, context: c.JSValue, stored: c.JSValue) !c.JSValue {
    const engine = scope.s.engine;
    if (try scope.fieldTest(context, "force", .truthy_value)) return c.pi_js_bool(engine.context, 0);
    if (x.nullish(stored) or try scope.fieldTest(stored, "checkedAt", .undefined_value) or try scope.fieldTest(stored, "lastModified", .undefined_value)) return c.pi_js_bool(engine.context, 0);
    const now = try scope.own(try scope.globalInvokeOwned("Date", "now", &.{}));
    const delta = try scope.binary(@intFromEnum(arithmetic.Operation.subtract), now, try scope.get(stored, "checkedAt"));
    return c.pi_js_bool(engine.context, @intFromBool(try scope.compare(.less, delta, c.JS_NewInt32(engine.context, refresh_interval_ms))));
}
fn hasStoredModels(scope: *Scope, stored: c.JSValue) !bool {
    var storage: x.Scope = .{ .engine = scope.s.engine }; var local: Scope = .{ .s = &storage };
    return scope.truthy(try x.owned.finishValue(&storage, hasStoredModelsBody(&local, stored)));
}
fn hasStoredModelsBody(scope: *Scope, stored: c.JSValue) !c.JSValue {
    return c.pi_js_bool(scope.s.engine.context, @intFromBool(try scope.compare(.greater, try scope.get(try scope.get(stored, "models"), "length"), c.JS_NewInt32(scope.s.engine.context, 0))));
}
fn persistBase(scope: *Scope, stored: c.JSValue) !c.JSValue {
    if (!x.nullish(stored)) return copy.object(scope, stored);
    const result = try scope.object();
    try scope.put(result, "models", try scope.array());
    return result;
}
fn continueRefresh(scope: *Scope, job: c.JSValue, value: c.JSValue, stage: Stage) !af.Action {
    const engine = scope.s.engine;
    const wrapper = try scope.get(job, "wrapper");
    const imports = try scope.get(wrapper, "imports");
    const context = try scope.get(job, "context");
    const personal = scope.truthy(try scope.get(wrapper, "personal"));
    switch (stage) {
        .restored => {
            if (!scope.truthy(value) or !try scope.fieldTest(context, "allowNetwork", .truthy_value) or try abort(scope, context)) return done();
            const stored = if (personal) c.pi_js_undefined() else try scope.get(job, "stored");
            if (!personal and try freshEnough(scope, context, stored)) return done();
            const validator = if (!personal and scope.truthy(stored) and try hasStoredModels(scope, stored)) try scope.get(stored, "etag") else c.pi_js_undefined();
            const provider_id = try scope.get(try scope.get(wrapper, "provider"), "id");
            const result = try request(scope, imports, provider_id, try scope.get(wrapper, "base"), try scope.get(context, "signal"), validator);
            return wait(scope, job, .response, result);
        },
        .response => {
            if (try abort(scope, context)) return done();
            try scope.put(job, "response", value);
            if (personal) {
                if (!scope.equal(try scope.get(value, "status"), c.JS_NewInt32(engine.context, 404)) and !scope.equal(try scope.get(value, "status"), c.JS_NewInt32(engine.context, 501))) {
                    if (!try scope.fieldTest(value, "ok", .truthy_value)) return failedRequest(scope, wrapper, value);
                    return beginRead(scope, job, wrapper, value);
                }
                return personalize(scope, job, try scope.array());
            }
            const checked = try scope.own(try scope.globalInvokeOwned("Date", "now", &.{}));
            try scope.put(job, "checked", checked);
            const stored = try scope.get(job, "stored");
            if (scope.equal(try scope.get(value, "status"), c.JS_NewInt32(engine.context, 304)) and scope.truthy(stored)) {
                const publisher = try scope.get(context, "publish");
                const persist = try copy.object(scope, stored);
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
            if (!try scope.fieldTest(value, "ok", .truthy_value)) {
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
            if (try abort(scope, context)) return done();
            const entry = try copy.object(scope, value);
            try scope.put(entry, "checkedAt", try scope.get(job, "checked"));
            const models = try remoteModels(scope, entry, try scope.get(wrapper, "generated"));
            return publish(scope, job, entry, models, .published);
        },
        .personalized => {
            if (try abort(scope, context)) return done();
            // Callee lookup happens before the checkedAt Date.now getter/call.
            const publisher = try scope.get(context, "publish");
            const persist = try scope.object();
            try scope.put(persist, "models", value);
            try scope.put(persist, "checkedAt", try scope.own(try scope.globalInvokeOwned("Date", "now", &.{})));
            const record = try scope.object();
            try scope.put(record, "persist", persist);
            try scope.put(record, "update", try arrow(scope, "update", 0, .update, &.{ wrapper, value }));
            return wait(scope, job, .published, try scope.call(publisher, context, &.{record}));
        },
        .failed_published => return failedRequest(scope, wrapper, try scope.get(job, "response")),
        .published, .finished => return done(),
    }
}
fn personalize(scope: *Scope, job: c.JSValue, remote: c.JSValue) !af.Action {
    const wrapper = try scope.get(job, "wrapper");
    const callback = try scope.get(wrapper, "personalize");
    const merged = try merge(scope, try scope.get(wrapper, "imports"), try builtin(scope, wrapper), remote);
    return wait(scope, job, .personalized, try scope.call(callback, c.pi_js_undefined(), &.{ merged, try scope.get(job, "context") }));
}
fn beginRead(scope: *Scope, job: c.JSValue, wrapper: c.JSValue, response: c.JSValue) !af.Action {
    const imports = try scope.get(wrapper, "imports");
    const function = try scope.get(imports, "readCatalog");
    const provider_id = try scope.get(try scope.get(wrapper, "provider"), "id");
    return wait(scope, job, .read_catalog, try scope.call(function, c.pi_js_undefined(), &.{provider_id, response}));
}
fn readCatalog(engine: *v.em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue, state: *c.JSValue, completion: af.Completion, value: c.JSValue) !af.Action {
    var storage: x.Scope = .{ .engine = engine }; var scope: Scope = .{ .s = &storage };
    return x.owned.finishAction(&storage, readBody(&scope, args, roots, state, completion, value));
}
fn readBody(scope: *Scope, args: []const c.JSValue, roots: []const c.JSValue, state: *c.JSValue, completion: af.Completion, value: c.JSValue) !af.Action {
    const engine = scope.s.engine;
    if (completion == .rejected) {
        try @import("native_async_body.zig").enterRejectedContinuation(engine);
        return .{ .thrown = c.JS_DupValue(engine.context, value) };
    }
    if (completion == .start) {
        const job = try scope.cell(); af.replaceState(engine, state, c.JS_DupValue(engine.context, job)); try engine.checkNativeEntry();
        try scope.put(job, "providerId", arg(args, 0)); try scope.put(job, "response", arg(args, 1));
        const last = try readModified(scope, arg(args, 1));
        try scope.put(job, "lastModified", last);
        // Source creates the return object before evaluating its awaited models property.
        try scope.put(job, "result", try scope.object());
        const json = try scope.own(try scope.invokeOwned(arg(args, 1), "json", &.{}));
        return .{ .awaited = c.JS_DupValue(engine.context, json) };
    }
    const result = try scope.get(state.*, "result");
    try scope.put(result, "models", try parseCatalog(scope, roots[0], try scope.get(state.*, "providerId"), value));
    const last = try scope.get(state.*, "lastModified");
    try scope.put(result, "lastModified", if (try invalidDate(scope, last)) c.JS_NewInt32(engine.context, 0) else last);
    const etag = try readHeader(scope, try scope.get(state.*, "response"), "etag");
    try scope.put(result, "etag", if (x.nullish(etag)) c.pi_js_undefined() else etag);
    return .{ .returned = c.JS_DupValue(engine.context, result) };
}

fn readModified(scope: *Scope, response: c.JSValue) !c.JSValue {
    var storage: x.Scope = .{ .engine = scope.s.engine }; var local: Scope = .{ .s = &storage };
    return scope.own(try x.owned.finishValue(&storage, readModifiedBody(&local, response)));
}
fn readModifiedBody(scope: *Scope, response: c.JSValue) !c.JSValue {
    const date = try scope.global("Date");
    const parse = try scope.get(date, "parse");
    const modified = try readHeader(scope, response, "last-modified");
    return c.JS_DupValue(scope.s.engine.context, try scope.call(parse, date, &.{if (x.nullish(modified)) try scope.text("") else modified}));
}
fn readHeader(scope: *Scope, response: c.JSValue, name: []const u8) !c.JSValue {
    var storage: x.Scope = .{ .engine = scope.s.engine }; var local: Scope = .{ .s = &storage };
    return scope.own(try x.owned.finishValue(&storage, readHeaderBody(&local, response, name)));
}
fn readHeaderBody(scope: *Scope, response: c.JSValue, name: []const u8) !c.JSValue {
    return c.JS_DupValue(scope.s.engine.context, try scope.invoke(try scope.get(response, "headers"), "get", &.{try scope.text(name)}));
}
fn invalidDate(scope: *Scope, last: c.JSValue) !bool {
    var storage: x.Scope = .{ .engine = scope.s.engine }; var local: Scope = .{ .s = &storage };
    return scope.truthy(try x.owned.finishValue(&storage, invalidDateBody(&local, last)));
}
fn invalidDateBody(scope: *Scope, last: c.JSValue) !c.JSValue {
    return c.pi_js_bool(scope.s.engine.context, @intFromBool(scope.truthy(try scope.invoke(try scope.global("Number"), "isNaN", &.{last}))));
}
