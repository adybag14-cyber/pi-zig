//! Native createProvider: static/dynamic model catalogs and typed/API dispatch.
const std = @import("std");
const em = @import("engine.zig");
const js = @import("native_js_values.zig");
const vm = @import("native_values.zig");
const Scope = @import("native_models_stream_scope.zig").Scope;
const awaiting = @import("native_durable_await.zig");
const c = em.c;
const Method = enum(c_int) { getModels, getAllModels, refreshModels, stream, streamSimple, fetchDeferred, cancelDeferred, generateImages, classify };
const Stage = enum(c_int) { restored, fetched, published, cancelled };
fn nullish(value: c.JSValue) bool {
    return c.JS_IsUndefined(value) or c.JS_IsNull(value);
}
fn item(scope: *Scope, value: c.JSValue, index: usize) !c.JSValue {
    return scope.own(try scope.engine.checked(c.JS_GetPropertyUint32(scope.engine.context, value, @intCast(index))));
}
fn kind(scope: *Scope, model: c.JSValue) !c.JSValue {
    const value = try scope.get(model, "type");
    return if (nullish(value)) scope.text("chat") else value;
}
fn implementations(scope: *Scope, value: c.JSValue) !c.JSValue {
    const result = try scope.array();
    if (nullish(value)) return result;
    const entries = try scope.invoke(try scope.global("Object"), "values", &.{value});
    var count: u32 = 0;
    for (0..try vm.length(scope.engine, entries)) |i| {
        const entry = try item(scope, entries, i);
        if (!c.JS_IsUndefined(entry)) {
            try scope.index(result, count, entry);
            count += 1;
        }
    }
    return result;
}
fn hasCapability(scope: *Scope, entries: c.JSValue, key: [*:0]const u8) !bool {
    for (0..try vm.length(scope.engine, entries)) |i| if (!c.JS_IsUndefined(try scope.get(try item(scope, entries, i), key))) return true;
    return false;
}
fn methodFunction(scope: *Scope, state: c.JSValue, method: Method) !c.JSValue {
    var data = [_]c.JSValue{state};
    return scope.own(try scope.engine.checked(c.JS_NewCFunctionData2(scope.engine.context, dispatch, @tagName(method), switch (method) {
        .getModels, .getAllModels => 0,
        .refreshModels => 1,
        else => 3,
    }, @intFromEnum(method), data.len, &data)));
}
pub fn install(engine: *em.Engine, exports: c.JSValue, cache: c.JSValue) !void {
    var data = [_]c.JSValue{cache};
    try js.define(engine, exports, "createProvider", try engine.checked(c.JS_NewCFunctionData2(engine.context, construct, "createProvider", 1, 0, data.len, &data)));
}
fn construct(context: ?*c.JSContext, _: c.JSValue, argc: c_int, args: [*c]c.JSValue, _: c_int, data: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    return create(engine, data[0], if (argc > 0) args[0] else c.pi_js_undefined()) catch |err| @import("native_durable.zig").reject(engine, err);
}
fn create(engine: *em.Engine, cache: c.JSValue, input: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const state = try scope.object();
    const store = try scope.object();
    try scope.put(store, "cache", cache);
    try scope.put(state, "store", store);
    try scope.put(state, "input", input);
    try scope.put(state, "baseline", try scope.get(input, "models"));
    try scope.put(state, "dynamic", try scope.array());
    try scope.put(state, "fetch", try scope.get(input, "fetchModels"));
    const api = try scope.get(input, "api");
    const single = scope.truthy(api) and c.JS_IsFunction(engine.context, try scope.get(api, "stream"));
    try scope.put(state, "single", if (single) api else c.pi_js_undefined());
    try scope.put(state, "byApi", if (single or !scope.truthy(api)) c.pi_js_undefined() else api);
    const streams = if (single) list: {
        const result = try scope.array();
        try scope.index(result, 0, api);
        break :list result;
    } else try implementations(&scope, api);
    const images = try scope.get(input, "images");
    const classifiers = try scope.get(input, "classifiers");
    try scope.put(state, "images", images);
    try scope.put(state, "classifiers", classifiers);
    const image_entries = try implementations(&scope, images);
    const classifier_entries = try implementations(&scope, classifiers);
    if (try vm.length(engine, streams) == 0 and try vm.length(engine, image_entries) == 0 and try vm.length(engine, classifier_entries) == 0) {
        const message = try scope.concat(try scope.concat(try scope.text("Provider "), try scope.get(input, "id")), try scope.text(": at least one of \"api\", \"images\", or \"classifiers\" is required."));
        const reason = try scope.own(try engine.checked(c.JS_CallConstructor(engine.context, try scope.global("Error"), 1, @constCast(&[_]c.JSValue{message}))));
        return engine.checked(c.JS_Throw(engine.context, c.JS_DupValue(engine.context, reason)));
    }
    const provider = try scope.object();
    try scope.put(provider, "id", try scope.get(input, "id"));
    const name = try scope.get(input, "name");
    try scope.put(provider, "name", if (nullish(name)) try scope.get(input, "id") else name);
    inline for (.{ "baseUrl", "headers", "auth" }) |key| try scope.put(provider, key, try scope.get(input, key));
    try scope.put(provider, "getModels", try methodFunction(&scope, state, .getModels));
    try scope.put(provider, "getAllModels", try methodFunction(&scope, state, .getAllModels));
    try scope.put(provider, "refreshModels", if (scope.truthy(try scope.get(state, "fetch"))) try methodFunction(&scope, state, .refreshModels) else c.pi_js_undefined());
    inline for (.{ "filterModels", "filterAllModels" }) |key| try scope.put(provider, key, try scope.get(input, key));
    try scope.put(provider, "stream", try methodFunction(&scope, state, .stream));
    try scope.put(provider, "streamSimple", try methodFunction(&scope, state, .streamSimple));
    if (try hasCapability(&scope, streams, "fetchDeferred")) try scope.put(provider, "fetchDeferred", try methodFunction(&scope, state, .fetchDeferred));
    if (try hasCapability(&scope, streams, "cancelDeferred")) try scope.put(provider, "cancelDeferred", try methodFunction(&scope, state, .cancelDeferred));
    if (try vm.length(engine, image_entries) > 0) try scope.put(provider, "generateImages", try methodFunction(&scope, state, .generateImages));
    if (try vm.length(engine, classifier_entries) > 0) try scope.put(provider, "classify", try methodFunction(&scope, state, .classify));
    return c.JS_DupValue(engine.context, provider);
}
fn dispatch(context: ?*c.JSContext, _: c.JSValue, argc: c_int, args: [*c]c.JSValue, raw: c_int, data: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    const method: Method = @enumFromInt(raw);
    return invoke(engine, data[0], method, args[0..@intCast(argc)]) catch |err| switch (method) {
        .getModels, .getAllModels, .stream, .streamSimple, .fetchDeferred => @import("native_durable.zig").reject(engine, err),
        else => @import("native_durable.zig").rejectedPromise(engine, err),
    };
}
fn catalog(scope: *Scope, state: c.JSValue, chat_only: bool) !c.JSValue {
    const baseline = try scope.get(state, "baseline");
    const dynamic = try scope.get(state, "dynamic");
    const result = try scope.array();
    for (0..try vm.length(scope.engine, baseline)) |i| {
        var row: Scope = .{ .engine = scope.engine };
        defer row.deinit();
        try scope.index(result, @intCast(i), try item(&row, baseline, i));
    }
    for (0..try vm.length(scope.engine, dynamic)) |i| {
        var row: Scope = .{ .engine = scope.engine };
        defer row.deinit();
        const model = try item(&row, dynamic, i);
        const model_kind = try kind(&row, model);
        const id = try row.get(model, "id");
        var position: usize = try vm.length(scope.engine, result);
        for (0..position) |j| {
            var entry: Scope = .{ .engine = scope.engine };
            defer entry.deinit();
            const existing = try item(&entry, result, j);
            if (entry.equal(try kind(&entry, existing), model_kind) and entry.equal(try entry.get(existing, "id"), id)) {
                position = j;
                break;
            }
        }
        try scope.index(result, @intCast(position), model);
    }
    if (!chat_only) return result;
    const filtered = try scope.array();
    const chat = try scope.text("chat");
    var count: u32 = 0;
    for (0..try vm.length(scope.engine, result)) |i| {
        var row: Scope = .{ .engine = scope.engine };
        defer row.deinit();
        const model = try item(&row, result, i);
        if (row.equal(try kind(&row, model), chat)) {
            try scope.index(filtered, count, model);
            count += 1;
        }
    }
    return filtered;
}

fn implementation(scope: *Scope, state: c.JSValue, method: Method, model: c.JSValue) !c.JSValue {
    if (method == .generateImages or method == .classify) {
        const map = try scope.get(state, if (method == .generateImages) "images" else "classifiers");
        return if (nullish(map)) c.pi_js_undefined() else scope.own(try js.getKey(scope.engine, map, try scope.get(model, "api")));
    }
    const single = try scope.get(state, "single");
    if (!c.JS_IsUndefined(single)) return single;
    const map = try scope.get(state, "byApi");
    return if (nullish(map)) c.pi_js_undefined() else scope.own(try js.getKey(scope.engine, map, try scope.get(model, "api")));
}
fn missing(scope: *Scope, state: c.JSValue, method: Method, model: c.JSValue) !c.JSValue {
    const input = try scope.get(state, "input");
    const prefix = try scope.concat(try scope.text("Provider "), try scope.get(input, "id"));
    const middle = try scope.text(switch (method) {
        .generateImages => " has no image generation implementation for \"",
        .classify => " has no classifier implementation for \"",
        .fetchDeferred => " does not support deferred responses for \"",
        .cancelDeferred => " cannot cancel deferred responses for \"",
        else => " has no API implementation for \"",
    });
    const message = try scope.concat(try scope.concat(try scope.concat(prefix, middle), try scope.get(model, "api")), try scope.text("\""));
    const text = try scope.engine.toString(message);
    defer scope.engine.gpa.free(text);
    return scope.own(try @import("native_models.zig").fromCause(scope.engine, try scope.get(state, "store"), if (method == .stream or method == .streamSimple) "stream" else "provider", text, c.pi_js_undefined()));
}
fn invoke(engine: *em.Engine, state: c.JSValue, method: Method, args: []const c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    if (method == .getModels or method == .getAllModels) return c.JS_DupValue(engine.context, try catalog(&scope, state, method == .getModels));
    const job = try scope.object();
    try scope.put(job, "state", state);
    try scope.put(job, "store", try scope.get(state, "store"));
    if (method == .refreshModels) {
        try scope.put(job, "context", if (args.len > 0) args[0] else c.pi_js_undefined());
        return c.JS_DupValue(engine.context, try refresh(&scope, job, true));
    }
    const model = if (args.len > 0) args[0] else c.pi_js_undefined();
    try scope.put(job, "model", model);
    try scope.put(job, "context", if (args.len > 1) args[1] else c.pi_js_undefined());
    try scope.put(job, "options", if (args.len > 2) args[2] else c.pi_js_undefined());
    try scope.put(job, "method", c.JS_NewInt32(engine.context, @intFromEnum(method)));
    const entry = try implementation(&scope, state, method, model);
    if (method == .fetchDeferred or ((method == .stream or method == .streamSimple) and !scope.truthy(entry))) {
        var data = [_]c.JSValue{job};
        const setup = try scope.own(try engine.checked(c.JS_NewCFunctionData2(engine.context, deferredSetup, "", 0, 0, data.len, &data)));
        return @import("native_models_streaming.zig").fromSetup(engine, try scope.get(state, "store"), model, setup);
    }
    if (!scope.truthy(entry) or (method == .cancelDeferred and !scope.truthy(try scope.get(entry, "cancelDeferred")))) {
        const reason = try missing(&scope, state, method, model);
        if (method == .generateImages or method == .classify) {
            try scope.put(job, "images", c.pi_js_bool(engine.context, @intFromBool(method == .generateImages)));
            const result = try scope.own(try @import("native_models_typed.zig").errorResult(&scope, job, reason));
            return @import("native_durable.zig").resolvedPromise(engine, result);
        }
        return engine.checked(c.JS_Throw(engine.context, c.JS_DupValue(engine.context, reason)));
    }
    const pending = try scope.invoke(entry, @tagName(method), &.{ model, try scope.get(job, "context"), try scope.get(job, "options") });
    if (method == .cancelDeferred) return c.JS_DupValue(engine.context, try wait(&scope, job, pending, .cancelled));
    return if (method == .generateImages or method == .classify) @import("native_durable.zig").resolvedPromise(engine, pending) else c.JS_DupValue(engine.context, pending);
}
fn deferredSetup(context: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue, _: c_int, data: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    return setupCall(engine, data[0]) catch |err| @import("native_durable.zig").reject(engine, err);
}
fn setupCall(engine: *em.Engine, job: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const state = try scope.get(job, "state");
    var raw: i32 = 0;
    if (c.JS_ToInt32(engine.context, &raw, try scope.get(job, "method")) < 0) return js.capture(engine);
    const method: Method = @enumFromInt(raw);
    const model = try scope.get(job, "model");
    const entry = try implementation(&scope, state, method, model);
    if (!scope.truthy(entry) or (method == .fetchDeferred and !scope.truthy(try scope.get(entry, "fetchDeferred")))) return engine.checked(c.JS_Throw(engine.context, c.JS_DupValue(engine.context, try missing(&scope, state, method, model))));
    return c.JS_DupValue(engine.context, try scope.invoke(entry, @tagName(method), &.{ model, try scope.get(job, "context"), try scope.get(job, "options") }));
}
fn wait(scope: *Scope, job: c.JSValue, value: c.JSValue, stage: Stage) !c.JSValue {
    const cache = try scope.get(try scope.get(job, "store"), "cache");
    var captured: awaiting.Intrinsics = .{ .constructor = try scope.get(cache, "promise_constructor"), .resolve = try scope.get(cache, "promise_resolve"), .then_function = try scope.get(cache, "promise_then") };
    return scope.own(try awaiting.continueWith(advance, scope.engine, &captured, job, value, @intFromEnum(stage)));
}
fn update(context: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue, _: c_int, data: [*c]c.JSValue) callconv(.c) c.JSValue {
    if (c.JS_DefinePropertyValueStr(context, data[0], "dynamic", c.JS_DupValue(context, data[1]), c.JS_PROP_C_W_E) < 0) return c.JS_Throw(context, c.JS_GetException(context));
    return c.pi_js_undefined();
}
fn publication(scope: *Scope, job: c.JSValue, models: c.JSValue, persist: bool) !c.JSValue {
    const result = try scope.object();
    const state = try scope.get(job, "state");
    var data = [_]c.JSValue{ state, models };
    if (persist) {
        const record = try scope.object();
        try scope.put(record, "models", models);
        try scope.put(record, "checkedAt", try scope.invoke(try scope.global("Date"), "now", &.{}));
        try scope.put(result, "persist", record);
    }
    try scope.put(result, "update", try scope.own(try scope.engine.checked(c.JS_NewCFunctionData2(scope.engine.context, update, "update", 0, 0, data.len, &data))));
    return result;
}
fn refresh(scope: *Scope, job: c.JSValue, restore: bool) !c.JSValue {
    const context = try scope.get(job, "context");
    const state = try scope.get(job, "state");
    const stored = try scope.get(context, "stored");
    if (restore and scope.truthy(stored)) {
        const values = try scope.get(stored, "models");
        const restored = try scope.array();
        const id = try scope.get(try scope.get(state, "input"), "id");
        var count: u32 = 0;
        for (0..try vm.length(scope.engine, values)) |i| {
            const model = try item(scope, values, i);
            if (scope.equal(try scope.get(model, "provider"), id)) {
                try scope.index(restored, count, model);
                count += 1;
            }
        }
        const pending = try scope.invoke(context, "publish", &.{try publication(scope, job, restored, false)});
        return wait(scope, job, pending, .restored);
    }
    const signal = try scope.get(context, "signal");
    if (!scope.truthy(try scope.get(context, "allowNetwork")) or scope.truthy(try scope.get(signal, "aborted"))) return scope.own(try @import("native_durable.zig").resolvedPromise(scope.engine, c.pi_js_undefined()));
    return wait(scope, job, try scope.call(try scope.get(state, "fetch"), c.pi_js_undefined(), &.{context}), .fetched);
}
fn advance(engine: *em.Engine, job: c.JSValue, value: c.JSValue, rejected: bool, raw: c_int) anyerror!c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    if (rejected) return engine.checked(c.JS_Throw(engine.context, c.JS_DupValue(engine.context, value)));
    const stage: Stage = @enumFromInt(raw);
    switch (stage) {
        .cancelled, .published => return c.pi_js_undefined(),
        .restored => {
            if (!scope.truthy(value)) return c.pi_js_undefined();
            return c.JS_DupValue(engine.context, try refresh(&scope, job, false));
        },
        .fetched => {
            const context = try scope.get(job, "context");
            if (scope.truthy(try scope.get(try scope.get(context, "signal"), "aborted"))) return c.pi_js_undefined();
            const models = try scope.array();
            var count: u32 = 0;
            for (0..try vm.length(engine, value)) |i| {
                const model = try item(&scope, value, i);
                const model_kind = try kind(&scope, model);
                if (scope.equal(model_kind, try scope.text("chat")) or scope.equal(model_kind, try scope.text("image")) or scope.equal(model_kind, try scope.text("classifier"))) {
                    try scope.index(models, count, model);
                    count += 1;
                }
            }
            return c.JS_DupValue(engine.context, try wait(&scope, job, try scope.invoke(context, "publish", &.{try publication(&scope, job, models, true)}), .published));
        },
    }
}
