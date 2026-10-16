//! Native createProvider: static/dynamic model catalogs and typed/API dispatch.
const std = @import("std");
const em = @import("engine.zig");
const js = @import("native_js_values.zig");
const vm = @import("native_values.zig");
const Scope = @import("native_models_stream_scope.zig").Scope;
const async_functions = @import("native_async_function.zig");
const functions = @import("native_node_function.zig");
const c = em.c;
const Method = enum(c_int) { getModels, getAllModels, refreshModels, stream, streamSimple, fetchDeferred, cancelDeferred, generateImages, classify };
const Stage = enum(c_int) { restored, fetched, published, cancelled };
fn nullish(value: c.JSValue) bool {
    return c.JS_IsUndefined(value) or c.JS_IsNull(value);
}
fn item(scope: *Scope, value: c.JSValue, index: usize) !c.JSValue {
    return scope.own(try scope.engine.checked(c.JS_GetPropertyUint32(scope.engine.context, value, @intCast(index))));
}
fn operations(scope: *Scope, state: c.JSValue) !c.JSValue {
    return scope.get(try scope.get(try scope.get(state, "store"), "cache"), "model_operations");
}
fn implementations(scope: *Scope, value: c.JSValue) !c.JSValue {
    const entries = try scope.invoke(try scope.global("Object"), "values", &.{if (nullish(value)) try scope.object() else value});
    const Filter = struct {
        fn call(engine: *em.Engine, _: c.JSValue, args: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
            return c.JS_NewBool(engine.context, args.len > 0 and !c.JS_IsUndefined(args[0]));
        }
    };
    return scope.invoke(entries, "filter", &.{try scope.own(try functions.createArrow(scope.engine, "", 1, Filter.call, &.{}))});
}
fn hasCapability(scope: *Scope, entries: c.JSValue, key: [*:0]const u8) !bool {
    const Predicate = struct {
        fn call(engine: *em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
            const value = try js.getKey(engine, if (args.len > 0) args[0] else c.pi_js_undefined(), roots[0]);
            defer engine.freeValue(value);
            return c.JS_NewBool(engine.context, !c.JS_IsUndefined(value));
        }
    };
    const predicate = try scope.own(try functions.createArrow(scope.engine, "", 1, Predicate.call, &.{try scope.text(std.mem.span(key))}));
    return scope.truthy(try scope.invoke(entries, "some", &.{predicate}));
}
fn methodFunction(scope: *Scope, state: c.JSValue, method: Method) !c.JSValue {
    const name: [*:0]const u8 = switch (method) {
        .getAllModels => "currentModels",
        .fetchDeferred, .cancelDeferred, .generateImages, .classify => "",
        else => @tagName(method),
    };
    const arity: c_int = switch (method) {
        .getModels, .getAllModels => 0,
        .refreshModels => 1,
        else => 3,
    };
    const roots: []const c.JSValue = &.{ state, c.JS_NewInt32(scope.engine.context, @intFromEnum(method)) };
    if (method == .refreshModels or method == .cancelDeferred) return scope.own(try async_functions.createResumableArrow(scope.engine, name, arity, asyncBody, roots, c.pi_js_undefined()));
    if (method == .generateImages or method == .classify) return scope.own(try async_functions.createArrow(scope.engine, name, arity, methodCall, roots, c.pi_js_undefined()));
    return scope.own(try functions.createArrow(scope.engine, name, arity, methodCall, roots));
}
fn methodCall(engine: *em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    var raw: i32 = 0;
    if (c.JS_ToInt32(engine.context, &raw, roots[1]) < 0) return js.capture(engine);
    const method: Method = @enumFromInt(raw);
    return invoke(engine, roots[0], method, args);
}
fn asyncBody(engine: *em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue, slot: *c.JSValue, completion: async_functions.Completion, input: c.JSValue) !async_functions.Action {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    if (completion == .start) {
        const job = try scope.object();
        try scope.put(job, "state", roots[0]);
        var raw: i32 = 0;
        if (c.JS_ToInt32(engine.context, &raw, roots[1]) < 0) return js.capture(engine);
        const method: Method = @enumFromInt(raw);
        try scope.put(job, "context", if (args.len > (if (method == .refreshModels) @as(usize, 0) else 1)) args[if (method == .refreshModels) 0 else 1] else c.pi_js_undefined());
        async_functions.replaceState(engine, slot, c.JS_DupValue(engine.context, job));
        if (method == .refreshModels) return refresh(&scope, job, true);
        const model = if (args.len > 0) args[0] else c.pi_js_undefined();
        const entry = try implementation(&scope, roots[0], method, model);
        if (!scope.truthy(entry) or !scope.truthy(try scope.get(entry, "cancelDeferred"))) return .{ .thrown = c.JS_DupValue(engine.context, try missing(&scope, roots[0], method, model)) };
        const pending = try scope.invoke(entry, "cancelDeferred", &.{ model, try scope.get(job, "context"), if (args.len > 2) args[2] else c.pi_js_undefined() });
        return wait(&scope, job, pending, .cancelled);
    }
    if (completion == .rejected) return .{ .thrown = c.JS_DupValue(engine.context, input) };
    var raw: i32 = 0;
    if (c.JS_ToInt32(engine.context, &raw, try scope.get(slot.*, "stage")) < 0) return js.capture(engine);
    return advance(engine, slot.*, input, @enumFromInt(raw));
}
pub fn install(engine: *em.Engine, exports: c.JSValue, cache: c.JSValue) !void {
    const Factory = struct {
        fn call(host: *em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
            return create(host, roots[0], if (args.len > 0) args[0] else c.pi_js_undefined());
        }
    };
    try js.define(engine, exports, "createProvider", try functions.create(engine, "createProvider", 1, Factory.call, &.{cache}));
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
    try scope.put(state, "hasKnownModelType", try scope.get(cache, "has_known_model_type"));
    // Preserve Source's repeated input.api reads, including short circuiting.
    const first_api = try scope.get(input, "api");
    const single = if (scope.truthy(first_api) and c.JS_IsFunction(engine.context, try scope.get(try scope.get(input, "api"), "stream"))) try scope.get(input, "api") else c.pi_js_undefined();
    const by_api = if (scope.truthy(single) or !scope.truthy(try scope.get(input, "api"))) c.pi_js_undefined() else try scope.get(input, "api");
    try scope.put(state, "single", single);
    try scope.put(state, "byApi", by_api);
    const images = try scope.get(input, "images");
    const classifiers = try scope.get(input, "classifiers");
    try scope.put(state, "images", images);
    try scope.put(state, "classifiers", classifiers);
    const streams = if (scope.truthy(single)) list: {
        const result = try scope.array();
        try scope.index(result, 0, single);
        break :list result;
    } else try implementations(&scope, by_api);
    const image_entries = try implementations(&scope, images);
    const classifier_entries = try implementations(&scope, classifiers);
    if (try vm.length(engine, streams) == 0 and try vm.length(engine, image_entries) == 0 and try vm.length(engine, classifier_entries) == 0) {
        const error_constructor = try scope.global("Error");
        const id = try scope.own(try engine.checked(c.JS_ToString(engine.context, try scope.get(input, "id"))));
        const message = try scope.concat(try scope.concat(try scope.text("Provider "), id), try scope.text(": at least one of \"api\", \"images\", or \"classifiers\" is required."));
        const reason = try scope.own(try engine.checked(c.JS_CallConstructor(engine.context, error_constructor, 1, @constCast(&[_]c.JSValue{message}))));
        return engine.checked(c.JS_Throw(engine.context, c.JS_DupValue(engine.context, reason)));
    }
    try scope.put(state, "baseline", try scope.get(input, "models"));
    try scope.put(state, "dynamic", try scope.array());
    try scope.put(state, "fetch", try scope.get(input, "fetchModels"));
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
    if (scope.truthy(images) and try vm.length(engine, image_entries) > 0) try scope.put(provider, "generateImages", try methodFunction(&scope, state, .generateImages));
    if (scope.truthy(classifiers) and try vm.length(engine, classifier_entries) > 0) try scope.put(provider, "classify", try methodFunction(&scope, state, .classify));
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
    const lexical = try operations(scope, state);
    const get_model_type = try scope.get(lexical, "getModelType");
    const baseline = try scope.get(state, "baseline");
    const dynamic = try scope.get(state, "dynamic");
    const result = try scope.own(try js.collect(scope.engine, baseline, try scope.own(try scope.engine.checked(c.JS_GetIteratorSymbol(scope.engine.context)))));
    var iterator = try @import("native_ai_provider_values.zig").iterator(scope, dynamic);
    defer iterator.deinit();
    errdefer iterator.closePreserving();
    while (try iterator.next()) |owned_model| {
        defer scope.engine.freeValue(owned_model);
        var row: Scope = .{ .engine = scope.engine };
        defer row.deinit();
        const Match = struct {
            fn call(engine: *em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
                var inner: Scope = .{ .engine = engine };
                defer inner.deinit();
                const entry = if (args.len > 0) args[0] else c.pi_js_undefined();
                return c.JS_NewBool(engine.context, inner.equal(try inner.call(roots[1], c.pi_js_undefined(), &.{entry}), try inner.call(roots[1], c.pi_js_undefined(), &.{roots[0]})) and inner.equal(try inner.get(entry, "id"), try inner.get(roots[0], "id")));
            }
        };
        const position_value = try row.invoke(result, "findIndex", &.{try row.own(try functions.createArrow(scope.engine, "", 1, Match.call, &.{ owned_model, get_model_type }))});
        if (row.truthy(try row.own(try scope.engine.checked(c.JS_PiBinaryOperator(scope.engine.context, 7, position_value, c.JS_NewInt32(scope.engine.context, 0)))))) {
            // Assignment follows ordinary Set semantics, including patched setters.
            try js.setKey(scope.engine, result, position_value, owned_model);
        } else {
            _ = try row.invoke(result, "push", &.{owned_model});
        }
    }
    if (!chat_only) return result;
    const Chat = struct {
        fn call(engine: *em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
            var row: Scope = .{ .engine = engine };
            defer row.deinit();
            return c.JS_DupValue(engine.context, try row.call(roots[0], c.pi_js_undefined(), &.{ if (args.len > 0) args[0] else c.pi_js_undefined(), try row.text("chat") }));
        }
    };
    return scope.invoke(result, "filter", &.{try scope.own(try functions.createArrow(scope.engine, "", 1, Chat.call, &.{try scope.get(lexical, "isModelType")}))});
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
    const prefix = try scope.concat(try scope.text("Provider "), try scope.stringify(try scope.get(input, "id")));
    const middle = try scope.text(switch (method) {
        .generateImages => " has no image generation implementation for \"",
        .classify => " has no classifier implementation for \"",
        .fetchDeferred => " does not support deferred responses for \"",
        .cancelDeferred => " cannot cancel deferred responses for \"",
        else => " has no API implementation for \"",
    });
    const message = try scope.concat(try scope.concat(try scope.concat(prefix, middle), try scope.stringify(try scope.get(model, "api"))), try scope.text("\""));
    const constructor = try scope.get(try scope.get(try scope.get(state, "store"), "cache"), "models_error_constructor");
    var args = [_]c.JSValue{ try scope.text(if (method == .stream or method == .streamSimple) "stream" else "provider"), message };
    return scope.own(try scope.engine.checked(c.JS_CallConstructor(scope.engine.context, constructor, args.len, &args)));
}
fn invoke(engine: *em.Engine, state: c.JSValue, method: Method, args: []const c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    if (method == .getModels or method == .getAllModels) return c.JS_DupValue(engine.context, try catalog(&scope, state, method == .getModels));
    const job = try scope.object();
    try scope.put(job, "state", state);
    try scope.put(job, "store", try scope.get(state, "store"));
    if (method == .refreshModels or method == .cancelDeferred) return error.ResumableProviderBodyRequired;
    const model = if (args.len > 0) args[0] else c.pi_js_undefined();
    try scope.put(job, "model", model);
    try scope.put(job, "context", if (args.len > 1) args[1] else c.pi_js_undefined());
    try scope.put(job, "options", if (args.len > 2) args[2] else c.pi_js_undefined());
    try scope.put(job, "method", c.JS_NewInt32(engine.context, @intFromEnum(method)));
    const entry = if (method == .fetchDeferred) c.pi_js_undefined() else try implementation(&scope, state, method, model);
    if (method == .fetchDeferred or ((method == .stream or method == .streamSimple) and !scope.truthy(entry))) {
        const Setup = struct {
            fn call(host: *em.Engine, _: c.JSValue, _: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
                return setupCall(host, roots[0]);
            }
        };
        const setup = try scope.own(try async_functions.createArrow(engine, "", 0, Setup.call, &.{job}, c.pi_js_undefined()));
        return @import("native_ai_lazy_api.zig").lazyStream(engine, model, setup);
    }
    if (!scope.truthy(entry) or (method == .cancelDeferred and !scope.truthy(try scope.get(entry, "cancelDeferred")))) {
        const reason = try missing(&scope, state, method, model);
        if (method == .generateImages or method == .classify) {
            const lexical = try operations(&scope, state);
            const result = try scope.call(try scope.get(lexical, if (method == .generateImages) "imageErrorResult" else "classifierErrorResult"), c.pi_js_undefined(), &.{ model, reason });
            return c.JS_DupValue(engine.context, result);
        }
        return engine.checked(c.JS_Throw(engine.context, c.JS_DupValue(engine.context, reason)));
    }
    const pending = try scope.invoke(entry, @tagName(method), &.{ model, try scope.get(job, "context"), try scope.get(job, "options") });
    return c.JS_DupValue(engine.context, pending);
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
    const entry = if (method == .stream or method == .streamSimple) c.pi_js_undefined() else try implementation(&scope, state, method, model);
    if (!scope.truthy(entry) or (method == .fetchDeferred and !scope.truthy(try scope.get(entry, "fetchDeferred")))) return engine.checked(c.JS_Throw(engine.context, c.JS_DupValue(engine.context, try missing(&scope, state, method, model))));
    return c.JS_DupValue(engine.context, try scope.invoke(entry, @tagName(method), &.{ model, try scope.get(job, "context"), try scope.get(job, "options") }));
}
fn wait(scope: *Scope, job: c.JSValue, value: c.JSValue, stage: Stage) !async_functions.Action {
    try scope.put(job, "stage", c.JS_NewInt32(scope.engine.context, @intFromEnum(stage)));
    return .{ .awaited = c.JS_DupValue(scope.engine.context, value) };
}
fn update(context: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue, _: c_int, data: [*c]c.JSValue) callconv(.c) c.JSValue {
    if (c.JS_DefinePropertyValueStr(context, data[0], "dynamic", c.JS_DupValue(context, data[1]), c.JS_PROP_C_W_E) < 0) return c.JS_Throw(context, c.JS_GetException(context));
    return c.pi_js_undefined();
}
fn publication(scope: *Scope, job: c.JSValue, models: c.JSValue, persist: bool) !c.JSValue {
    const result = try scope.object();
    const state = try scope.get(job, "state");
    if (persist) {
        const record = try scope.object();
        try scope.put(record, "models", models);
        try scope.put(record, "checkedAt", try scope.invoke(try scope.global("Date"), "now", &.{}));
        try scope.put(result, "persist", record);
    }
    const Update = struct {
        fn call(engine: *em.Engine, _: c.JSValue, _: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
            try js.define(engine, roots[0], "dynamic", c.JS_DupValue(engine.context, roots[1]));
            return c.pi_js_undefined();
        }
    };
    try scope.put(result, "update", try scope.own(try functions.createArrow(scope.engine, "update", 0, Update.call, &.{ state, models })));
    return result;
}
fn refresh(scope: *Scope, job: c.JSValue, restore: bool) !async_functions.Action {
    const context = try scope.get(job, "context");
    const state = try scope.get(job, "state");
    if (restore and scope.truthy(try scope.get(context, "stored"))) {
        const values = try scope.get(try scope.get(context, "stored"), "models");
        const Filter = struct {
            fn call(engine: *em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
                var row: Scope = .{ .engine = engine };
                defer row.deinit();
                return c.JS_NewBool(engine.context, row.equal(try row.get(if (args.len > 0) args[0] else c.pi_js_undefined(), "provider"), try row.get(roots[0], "id")));
            }
        };
        const Identity = struct {
            fn call(engine: *em.Engine, _: c.JSValue, args: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
                return if (args.len > 0) c.JS_DupValue(engine.context, args[0]) else c.pi_js_undefined();
            }
        };
        const selected = try scope.invoke(values, "filter", &.{try scope.own(try functions.createArrow(scope.engine, "", 1, Filter.call, &.{try scope.get(state, "input")}))});
        const restored = try scope.invoke(selected, "map", &.{try scope.own(try functions.createArrow(scope.engine, "", 1, Identity.call, &.{}))});
        const pending = try scope.invoke(context, "publish", &.{try publication(scope, job, restored, false)});
        return wait(scope, job, pending, .restored);
    }
    if (!scope.truthy(try scope.get(context, "allowNetwork")) or scope.truthy(try scope.get(try scope.get(context, "signal"), "aborted"))) return .{ .returned = c.pi_js_undefined() };
    return wait(scope, job, try scope.call(try scope.get(state, "fetch"), c.pi_js_undefined(), &.{context}), .fetched);
}
fn advance(engine: *em.Engine, job: c.JSValue, value: c.JSValue, stage: Stage) anyerror!async_functions.Action {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    switch (stage) {
        .cancelled, .published => return .{ .returned = c.pi_js_undefined() },
        .restored => {
            if (!scope.truthy(value)) return .{ .returned = c.pi_js_undefined() };
            return refresh(&scope, job, false);
        },
        .fetched => {
            const context = try scope.get(job, "context");
            if (scope.truthy(try scope.get(try scope.get(context, "signal"), "aborted"))) return .{ .returned = c.pi_js_undefined() };
            const state = try scope.get(job, "state");
            const models = try scope.invoke(value, "filter", &.{try scope.get(state, "hasKnownModelType")});
            return wait(&scope, job, try scope.invoke(context, "publish", &.{try publication(&scope, job, models, true)}), .published);
        },
    }
}
