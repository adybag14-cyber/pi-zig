//! Owner-local model catalogs. All callbacks and Promise continuations use the
//! directly linked VM; private state consists of GC-visible JavaScript values.
const std = @import("std");
const engine_mod = @import("engine.zig");
const abort_signal = @import("abort_signal.zig");
const c = engine_mod.c;

pub const Method = enum(c_int) { setProvider, deleteProvider, clearProviders, getProviders, getProvider, getModels, getAllModels, getModelsOfType, getModel, getModelOfType, getAvailable, getAllAvailable, getAvailableOfType, checkAuth };
fn get(engine: *engine_mod.Engine, object: c.JSValue, name: [*:0]const u8) !c.JSValue {
    return engine.checked(c.JS_GetPropertyStr(engine.context, object, name));
}
fn put(engine: *engine_mod.Engine, object: c.JSValue, name: [*:0]const u8, value: c.JSValue) !void {
    if (c.JS_DefinePropertyValueStr(engine.context, object, name, value, c.JS_PROP_C_W_E) < 0) return error.JavaScriptException;
}
fn errorProperty(engine: *engine_mod.Engine, target: c.JSValue, name: [*:0]const u8, value: c.JSValue) !void {
    if (c.JS_DefinePropertyValueStr(engine.context, target, name, value, c.JS_PROP_CONFIGURABLE | c.JS_PROP_WRITABLE) < 0) return error.JavaScriptException;
}
fn newObject(engine: *engine_mod.Engine) !c.JSValue {
    return engine.checked(c.JS_NewObjectProto(engine.context, c.pi_js_null()));
}
fn call(engine: *engine_mod.Engine, receiver: c.JSValue, function: c.JSValue, arguments: []const c.JSValue) !c.JSValue {
    return engine.checked(c.JS_Call(engine.context, function, receiver, @intCast(arguments.len), @constCast(arguments.ptr)));
}
fn invoke(engine: *engine_mod.Engine, receiver: c.JSValue, name: [*:0]const u8, arguments: []const c.JSValue) !c.JSValue {
    const function = try get(engine, receiver, name);
    defer engine.freeValue(function);
    return call(engine, receiver, function, arguments);
}
fn cached(engine: *engine_mod.Engine, store: c.JSValue, name: [*:0]const u8, receiver: c.JSValue, arguments: []const c.JSValue) !c.JSValue {
    const cache = try get(engine, store, "cache");
    defer engine.freeValue(cache);
    const function = try get(engine, cache, name);
    defer engine.freeValue(function);
    return call(engine, receiver, function, arguments);
}
fn length(engine: *engine_mod.Engine, array: c.JSValue) !u32 {
    const value = try get(engine, array, "length");
    defer engine.freeValue(value);
    var count: u32 = 0;
    if (c.JS_ToUint32(engine.context, &count, value) < 0) return error.JavaScriptException;
    if (count > 65536) return error.NativeModelCatalogLimit;
    return count;
}
fn append(engine: *engine_mod.Engine, array: c.JSValue, index: u32, value: c.JSValue) !void {
    if (c.JS_SetPropertyUint32(engine.context, array, index, value) < 0) return error.JavaScriptException;
}
fn modelType(engine: *engine_mod.Engine, model: c.JSValue) !c.JSValue {
    const value = try get(engine, model, "type");
    if (!c.JS_IsNull(value) and !c.JS_IsUndefined(value)) return value;
    engine.freeValue(value);
    return engine.checked(c.JS_NewString(engine.context, "chat"));
}
fn same(a: c.JSValue, b: c.JSValue, engine: *engine_mod.Engine) bool {
    return c.JS_IsStrictEqual(engine.context, a, b);
}
fn filterType(engine: *engine_mod.Engine, models: c.JSValue, kind: c.JSValue) !c.JSValue {
    const result = try engine.checked(c.JS_NewArray(engine.context));
    errdefer engine.freeValue(result);
    var output: u32 = 0;
    for (0..try length(engine, models)) |index| {
        const model = try engine.checked(c.JS_GetPropertyUint32(engine.context, models, @intCast(index)));
        defer engine.freeValue(model);
        const actual = try modelType(engine, model);
        defer engine.freeValue(actual);
        if (same(actual, kind, engine)) {
            try append(engine, result, output, c.JS_DupValue(engine.context, model));
            output += 1;
        }
    }
    return result;
}
fn providerModels(engine: *engine_mod.Engine, provider: c.JSValue, all: bool) !c.JSValue {
    const getter = try get(engine, provider, if (all) "getAllModels" else "getModels");
    defer engine.freeValue(getter);
    if (all and (c.JS_IsNull(getter) or c.JS_IsUndefined(getter))) return invoke(engine, provider, "getModels", &.{});
    const models = try call(engine, provider, getter, &.{});
    if (all and (c.JS_IsNull(models) or c.JS_IsUndefined(models))) {
        engine.freeValue(models);
        return invoke(engine, provider, "getModels", &.{});
    }
    return models;
}
fn providerList(engine: *engine_mod.Engine, store: c.JSValue, id: c.JSValue) !c.JSValue {
    const map = try get(engine, store, "map");
    defer engine.freeValue(map);
    const result = try engine.checked(c.JS_NewArray(engine.context));
    errdefer engine.freeValue(result);
    if (!c.JS_IsUndefined(id)) {
        const provider = try cached(engine, store, "map_get", map, &.{id});
        if (!c.JS_IsUndefined(provider)) try append(engine, result, 0, provider) else engine.freeValue(provider);
        return result;
    }
    const iterator = try cached(engine, store, "map_values", map, &.{});
    defer engine.freeValue(iterator);
    var index: u32 = 0;
    while (true) {
        const entry = try cached(engine, store, "iterator_next", iterator, &.{});
        defer engine.freeValue(entry);
        const done = try get(engine, entry, "done");
        defer engine.freeValue(done);
        if (c.JS_ToBool(engine.context, done) == 1) break;
        if (index >= 4096) return error.NativeModelProviderLimit;
        try append(engine, result, index, try get(engine, entry, "value"));
        index += 1;
    }
    return result;
}
fn collect(engine: *engine_mod.Engine, store: c.JSValue, id: c.JSValue, all: bool) !c.JSValue {
    const result = try engine.checked(c.JS_NewArray(engine.context));
    errdefer engine.freeValue(result);
    const map = try get(engine, store, "map");
    defer engine.freeValue(map);
    if (!c.JS_IsUndefined(id)) {
        const provider = try cached(engine, store, "map_get", map, &.{id});
        defer engine.freeValue(provider);
        if (c.JS_IsUndefined(provider)) return result;
        const models = providerModels(engine, provider, all) catch |err| {
            if (err == error.JavaScriptException) return result;
            return err;
        };
        engine.freeValue(result);
        return models;
    }
    const iterator = try cached(engine, store, "map_values", map, &.{});
    defer engine.freeValue(iterator);
    var output: u32 = 0;
    var visited: usize = 0;
    while (true) {
        const entry = try cached(engine, store, "iterator_next", iterator, &.{});
        defer engine.freeValue(entry);
        const done = try get(engine, entry, "done");
        defer engine.freeValue(done);
        if (c.JS_ToBool(engine.context, done) == 1) break;
        if (visited >= 65536) return error.NativeModelProviderLimit;
        visited += 1;
        const provider = try get(engine, entry, "value");
        defer engine.freeValue(provider);
        // Upstream synchronous catalog reads are best effort. A failing live
        // provider must not hide working siblings or change their identity.
        const models = providerModels(engine, provider, all) catch |err| {
            if (err == error.JavaScriptException) continue;
            return err;
        };
        defer engine.freeValue(models);
        for (0..try length(engine, models)) |item| {
            if (output >= 65536) return error.NativeModelCatalogLimit;
            try append(engine, result, output, try engine.checked(c.JS_GetPropertyUint32(engine.context, models, @intCast(item))));
            output += 1;
        }
    }
    return result;
}

pub fn query(engine: *engine_mod.Engine, store: c.JSValue, method: Method, args: []const c.JSValue) !c.JSValue {
    const first = if (args.len > 0) args[0] else c.pi_js_undefined();
    const second = if (args.len > 1) args[1] else c.pi_js_undefined();
    const third = if (args.len > 2) args[2] else c.pi_js_undefined();
    if (method == .setProvider or method == .deleteProvider or method == .clearProviders or method == .getProvider) {
        const map = try get(engine, store, "map");
        defer engine.freeValue(map);
        if (method == .setProvider) {
            const id = try get(engine, first, "id");
            defer engine.freeValue(id);
            const ignored = try cached(engine, store, "map_set", map, &.{ id, first });
            engine.freeValue(ignored);
            return c.pi_js_undefined();
        }
        const value = try cached(engine, store, switch (method) {
            .deleteProvider => "map_delete",
            .clearProviders => "map_clear",
            else => "map_get",
        }, map, if (method == .clearProviders) &.{} else &.{first});
        if (method == .getProvider) return value;
        engine.freeValue(value);
        return c.pi_js_undefined();
    }
    if (method == .getProviders) return providerList(engine, store, c.pi_js_undefined());
    if (method == .getModels or method == .getAllModels) return collect(engine, store, first, method == .getAllModels);
    if (method == .getModelsOfType) {
        const models = try collect(engine, store, second, true);
        defer engine.freeValue(models);
        return filterType(engine, models, first);
    }
    if (method == .getModel or method == .getModelOfType) {
        const models = if (method == .getModel) try collect(engine, store, first, false) else try query(engine, store, .getModelsOfType, &.{ first, second });
        defer engine.freeValue(models);
        const requested = if (method == .getModel) second else third;
        for (0..try length(engine, models)) |index| {
            const model = try engine.checked(c.JS_GetPropertyUint32(engine.context, models, @intCast(index)));
            const id = get(engine, model, "id") catch |err| {
                engine.freeValue(model);
                return err;
            };
            defer engine.freeValue(id);
            if (same(id, requested, engine)) return model;
            engine.freeValue(model);
        }
        return c.pi_js_undefined();
    }
    return available(engine, store, method, args);
}

fn methodCallback(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, magic: c_int, data: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = engine_mod.Engine.fromContext(context.?);
    return query(engine, data[0], @enumFromInt(magic), if (argc > 0) argv[0..@intCast(argc)] else &.{}) catch |err| {
        if (err == error.JavaScriptException) return engine.throwCaptured();
        if (err == error.OutOfMemory) return c.JS_ThrowOutOfMemory(context);
        return c.JS_ThrowTypeError(context, "Native model catalog: %s", @as([*:0]const u8, @errorName(err)));
    };
}

pub fn create(engine: *engine_mod.Engine, cache: c.JSValue, options: c.JSValue) !c.JSValue {
    const store = try newObject(engine);
    defer engine.freeValue(store);
    try put(engine, store, "cache", c.JS_DupValue(engine.context, cache));
    const map_constructor = try get(engine, cache, "map_constructor");
    defer engine.freeValue(map_constructor);
    try put(engine, store, "map", try engine.checked(c.JS_CallConstructor(engine.context, map_constructor, 0, null)));
    inline for (.{ "credentials", "authContext" }) |name| try put(engine, store, name, if (c.JS_IsUndefined(options) or c.JS_IsNull(options)) c.pi_js_undefined() else try get(engine, options, name));
    const auth_context = try get(engine, store, "authContext");
    defer engine.freeValue(auth_context);
    if (c.JS_IsUndefined(auth_context) or c.JS_IsNull(auth_context)) {
        const defaults = try newObject(engine);
        defer engine.freeValue(defaults);
        try put(engine, defaults, "env", try engine.checked(c.pi_js_function_magic(engine.context, defaultAuthContext, "env", 1, 0)));
        try put(engine, defaults, "fileExists", try engine.checked(c.pi_js_function_magic(engine.context, defaultAuthContext, "fileExists", 1, 1)));
        try put(engine, store, "authContext", c.JS_DupValue(engine.context, defaults));
    }
    const result = try engine.checked(c.JS_NewObject(engine.context));
    errdefer engine.freeValue(result);
    var data = [_]c.JSValue{store};
    inline for (std.meta.fields(Method)) |field| try put(engine, result, field.name, try engine.checked(c.JS_NewCFunctionData2(engine.context, methodCallback, field.name, 0, field.value, data.len, &data)));
    return result;
}
fn createCallback(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, data: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = engine_mod.Engine.fromContext(context.?);
    return create(engine, data[0], if (argc > 0) argv[0] else c.pi_js_undefined()) catch |err| {
        if (err == error.JavaScriptException) return engine.throwCaptured();
        return c.JS_ThrowOutOfMemory(context);
    };
}
fn typeCallback(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, magic: c_int) callconv(.c) c.JSValue {
    const engine = engine_mod.Engine.fromContext(context.?);
    if (argc == 0) return c.JS_ThrowTypeError(context, "Model is required");
    const kind = modelType(engine, argv[0]) catch return engine.throwCaptured();
    if (magic == 0) return kind;
    defer engine.freeValue(kind);
    return c.pi_js_bool(context, @intFromBool(argc > 1 and same(kind, argv[1], engine)));
}

pub fn populateExports(engine: *engine_mod.Engine, exports: c.JSValue) !void {
    if (engine.abort_signal_class == 0) try abort_signal.install(engine);
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    const cache = try newObject(engine);
    defer engine.freeValue(cache);
    const map_constructor = try get(engine, global, "Map");
    defer engine.freeValue(map_constructor);
    try put(engine, cache, "map_constructor", c.JS_DupValue(engine.context, map_constructor));
    const prototype = try get(engine, map_constructor, "prototype");
    defer engine.freeValue(prototype);
    inline for (.{ .{ "get", "map_get" }, .{ "set", "map_set" }, .{ "delete", "map_delete" }, .{ "clear", "map_clear" }, .{ "values", "map_values" } }) |entry| try put(engine, cache, entry[1], try get(engine, prototype, entry[0]));
    const map = try engine.checked(c.JS_CallConstructor(engine.context, map_constructor, 0, null));
    defer engine.freeValue(map);
    const iterator = try invoke(engine, map, "values", &.{});
    defer engine.freeValue(iterator);
    try put(engine, cache, "iterator_next", try get(engine, iterator, "next"));
    const promise = try get(engine, global, "Promise");
    defer engine.freeValue(promise);
    try put(engine, cache, "promise_constructor", c.JS_DupValue(engine.context, promise));
    try put(engine, cache, "promise_all", try get(engine, promise, "all"));
    const promise_prototype = try get(engine, promise, "prototype");
    defer engine.freeValue(promise_prototype);
    try put(engine, cache, "promise_then", try get(engine, promise_prototype, "then"));
    const error_constructor = try get(engine, global, "Error");
    defer engine.freeValue(error_constructor);
    const error_prototype = try get(engine, error_constructor, "prototype");
    defer engine.freeValue(error_prototype);
    const models_error_prototype = try engine.checked(c.JS_NewObjectProto(engine.context, error_prototype));
    defer engine.freeValue(models_error_prototype);
    try put(engine, cache, "models_error_prototype", c.JS_DupValue(engine.context, models_error_prototype));
    var error_data = [_]c.JSValue{models_error_prototype};
    const models_error = try engine.checked(c.JS_NewCFunctionData2(engine.context, errorConstructor, "ModelsError", 3, 0, 1, &error_data));
    defer engine.freeValue(models_error);
    _ = c.JS_SetConstructorBit(engine.context, models_error, true);
    if (c.JS_SetConstructor(engine.context, models_error, models_error_prototype) < 0) return error.JavaScriptException;
    try put(engine, exports, "ModelsError", c.JS_DupValue(engine.context, models_error));
    var data = [_]c.JSValue{cache};
    try put(engine, exports, "createModels", try engine.checked(c.JS_NewCFunctionData2(engine.context, createCallback, "createModels", 1, 0, 1, &data)));
    try put(engine, exports, "getModelType", try engine.checked(c.pi_js_function_magic(engine.context, typeCallback, "getModelType", 1, 0)));
    try put(engine, exports, "isModelType", try engine.checked(c.pi_js_function_magic(engine.context, typeCallback, "isModelType", 2, 1)));
}

// Availability is completed by native Promise callbacks, never by blocking a
// running JavaScript C frame or moving a JSValue to another thread.
const Stage = enum(c_int) { credential, auth, resolution, aggregate, reject, abort };
fn newPromise(engine: *engine_mod.Engine, job: c.JSValue) !c.JSValue {
    var functions: [2]c.JSValue = undefined;
    const result = try engine.checked(c.JS_NewPromiseCapability(engine.context, &functions));
    errdefer engine.freeValue(result);
    var reject_consumed = false;
    errdefer if (!reject_consumed) engine.freeValue(functions[1]);
    try put(engine, job, "resolve", functions[0]);
    reject_consumed = true;
    try put(engine, job, "reject", functions[1]);
    try put(engine, job, "closed", c.pi_js_bool(engine.context, 0));
    return result;
}
fn continuationFunction(engine: *engine_mod.Engine, job: c.JSValue, stage: Stage) !c.JSValue {
    var data = [_]c.JSValue{job};
    return engine.checked(c.JS_NewCFunctionData2(engine.context, continuation, "modelContinuation", 1, @intFromEnum(stage), 1, &data));
}
fn then(engine: *engine_mod.Engine, job: c.JSValue, value: c.JSValue, stage: Stage) !void {
    try put(engine, job, "pendingStage", c.JS_NewInt32(engine.context, @intFromEnum(stage)));
    var functions: [2]c.JSValue = undefined;
    const adopted = try engine.checked(c.JS_NewPromiseCapability(engine.context, &functions));
    defer engine.freeValue(adopted);
    defer for (functions) |item| engine.freeValue(item);
    const ignored = try call(engine, c.pi_js_undefined(), functions[0], &.{value});
    engine.freeValue(ignored);
    const resolved = try continuationFunction(engine, job, stage);
    defer engine.freeValue(resolved);
    const rejected = try continuationFunction(engine, job, .reject);
    defer engine.freeValue(rejected);
    const store = try get(engine, job, "store");
    defer engine.freeValue(store);
    const chained = try cached(engine, store, "promise_then", adopted, &.{ resolved, rejected });
    engine.freeValue(chained);
}
fn finish(engine: *engine_mod.Engine, job: c.JSValue, result: c.JSValue, success: bool) !void {
    const closed = try get(engine, job, "closed");
    defer engine.freeValue(closed);
    if (c.JS_ToBool(engine.context, closed) == 1) return;
    try put(engine, job, "closed", c.pi_js_bool(engine.context, 1));
    var settled_success = success;
    var settled_result = c.JS_DupValue(engine.context, result);
    defer engine.freeValue(settled_result);
    const signal = try get(engine, job, "signal");
    defer engine.freeValue(signal);
    const listener = try get(engine, job, "listener");
    defer engine.freeValue(listener);
    if (!c.JS_IsUndefined(signal) and !c.JS_IsUndefined(listener)) {
        const event = try engine.checked(c.JS_NewString(engine.context, "abort"));
        defer engine.freeValue(event);
        const removed = invoke(engine, signal, "removeEventListener", &.{ event, listener }) catch failure: {
            // Cleanup can replace a successful result, but must preserve the
            // primary rejection (including the caller's exact abort reason).
            if (success) {
                settled_success = false;
                engine.freeValue(settled_result);
                settled_result = if (engine.captured_exception) |exception| c.JS_DupValue(engine.context, exception) else try engine.checked(c.JS_NewString(engine.context, "Native model cleanup failed"));
            }
            break :failure c.pi_js_undefined();
        };
        engine.freeValue(removed);
    }
    const resolver = try get(engine, job, if (settled_success) "resolve" else "reject");
    defer engine.freeValue(resolver);
    const ignored = try call(engine, c.pi_js_undefined(), resolver, &.{settled_result});
    engine.freeValue(ignored);
}
fn checkAborted(engine: *engine_mod.Engine, job: c.JSValue) !bool {
    const signal = try get(engine, job, "signal");
    defer engine.freeValue(signal);
    if (c.JS_IsUndefined(signal)) return false;
    const aborted = try get(engine, signal, "aborted");
    defer engine.freeValue(aborted);
    if (c.JS_ToBool(engine.context, aborted) != 1) return false;
    const reason = try get(engine, signal, "reason");
    defer engine.freeValue(reason);
    try finish(engine, job, reason, false);
    return true;
}
fn continueJob(engine: *engine_mod.Engine, job: c.JSValue, stage: Stage, value: c.JSValue) !void {
    const closed = try get(engine, job, "closed");
    defer engine.freeValue(closed);
    if (c.JS_ToBool(engine.context, closed) == 1) return;
    const race_abort = try get(engine, job, "raceAbort");
    defer engine.freeValue(race_abort);
    if (c.JS_ToBool(engine.context, race_abort) == 1 and try checkAborted(engine, job)) return;
    if (stage == .reject) {
        const pending = try get(engine, job, "pendingStage");
        defer engine.freeValue(pending);
        var previous: i32 = -1;
        if (!c.JS_IsUndefined(pending) and c.JS_ToInt32(engine.context, &previous, pending) < 0) return error.JavaScriptException;
        if (previous == @intFromEnum(Stage.credential) or previous == @intFromEnum(Stage.auth) or previous == @intFromEnum(Stage.resolution)) {
            const provider_value = try get(engine, job, "provider");
            defer engine.freeValue(provider_value);
            const provider_id = try get(engine, provider_value, "id");
            defer engine.freeValue(provider_id);
            const id = try engine.toString(provider_id);
            defer engine.gpa.free(id);
            const message = if (previous == @intFromEnum(Stage.credential))
                try std.fmt.allocPrint(engine.gpa, "Credential store read failed for {s}", .{id})
            else
                try std.fmt.allocPrint(engine.gpa, "API key auth check failed for provider {s}", .{id});
            defer engine.gpa.free(message);
            const wrapped = try engine.checked(c.JS_NewError(engine.context));
            defer engine.freeValue(wrapped);
            const store = try get(engine, job, "store");
            defer engine.freeValue(store);
            const cache = try get(engine, store, "cache");
            defer engine.freeValue(cache);
            const prototype = try get(engine, cache, "models_error_prototype");
            defer engine.freeValue(prototype);
            if (c.JS_SetPrototype(engine.context, wrapped, prototype) < 0) return error.JavaScriptException;
            try put(engine, wrapped, "name", try engine.checked(c.JS_NewString(engine.context, "ModelsError")));
            const detail_value = if (c.JS_IsError(value)) detail: {
                const error_message = try get(engine, value, "message");
                if (c.JS_ToBool(engine.context, error_message) == 1) break :detail error_message;
                engine.freeValue(error_message);
                break :detail try get(engine, value, "name");
            } else c.JS_DupValue(engine.context, value);
            defer engine.freeValue(detail_value);
            const detail_text = try engine.toString(detail_value);
            defer engine.gpa.free(detail_text);
            const formatted = if (detail_text.len > 0 and std.mem.indexOf(u8, message, detail_text) == null)
                try std.fmt.allocPrint(engine.gpa, "{s}: {s}", .{ message, detail_text })
            else
                try engine.gpa.dupe(u8, message);
            defer engine.gpa.free(formatted);
            try errorProperty(engine, wrapped, "message", try engine.checked(c.JS_NewStringLen(engine.context, formatted.ptr, formatted.len)));
            try put(engine, wrapped, "code", try engine.checked(c.JS_NewString(engine.context, "auth")));
            try errorProperty(engine, wrapped, "cause", c.JS_DupValue(engine.context, value));
            return finish(engine, job, wrapped, false);
        }
        return finish(engine, job, value, false);
    }
    if (stage == .abort) return;
    if (stage == .aggregate) {
        const only_check = try get(engine, job, "onlyCheck");
        defer engine.freeValue(only_check);
        if (c.JS_ToBool(engine.context, only_check) == 1) {
            const result = if (try length(engine, value) > 0) try engine.checked(c.JS_GetPropertyUint32(engine.context, value, 0)) else c.pi_js_undefined();
            defer engine.freeValue(result);
            return finish(engine, job, result, true);
        }
        const result = try engine.checked(c.JS_NewArray(engine.context));
        defer engine.freeValue(result);
        var output: u32 = 0;
        for (0..try length(engine, value)) |index| {
            const models = try engine.checked(c.JS_GetPropertyUint32(engine.context, value, @intCast(index)));
            defer engine.freeValue(models);
            for (0..try length(engine, models)) |model_index| {
                if (output >= 65536) return error.NativeModelCatalogLimit;
                try append(engine, result, output, try engine.checked(c.JS_GetPropertyUint32(engine.context, models, @intCast(model_index))));
                output += 1;
            }
        }
        const kind = try get(engine, job, "type");
        defer engine.freeValue(kind);
        if (!c.JS_IsUndefined(kind)) {
            const filtered = try filterType(engine, result, kind);
            defer engine.freeValue(filtered);
            return finish(engine, job, filtered, true);
        }
        return finish(engine, job, result, true);
    }
    const provider = try get(engine, job, "provider");
    defer engine.freeValue(provider);
    if (stage == .credential) {
        try put(engine, job, "credential", c.JS_DupValue(engine.context, value));
        const auth = try get(engine, provider, "auth");
        defer engine.freeValue(auth);
        const credential_type = if (c.JS_IsNull(value) or c.JS_IsUndefined(value)) c.pi_js_undefined() else try get(engine, value, "type");
        defer engine.freeValue(credential_type);
        const oauth_type = try engine.checked(c.JS_NewString(engine.context, "oauth"));
        defer engine.freeValue(oauth_type);
        if (same(credential_type, oauth_type, engine)) {
            const oauth = try get(engine, auth, "oauth");
            defer engine.freeValue(oauth);
            const check = if (c.JS_ToBool(engine.context, oauth) == 1) try newObject(engine) else c.pi_js_undefined();
            defer engine.freeValue(check);
            if (!c.JS_IsUndefined(check)) {
                try put(engine, check, "type", try engine.checked(c.JS_NewString(engine.context, "oauth")));
                try put(engine, check, "source", try engine.checked(c.JS_NewString(engine.context, "OAuth")));
            }
            return continueJob(engine, job, .auth, check);
        }
        const api_key = try get(engine, auth, "apiKey");
        defer engine.freeValue(api_key);
        if (c.JS_ToBool(engine.context, api_key) == 0) return continueJob(engine, job, .auth, c.pi_js_undefined());
        const options = try newObject(engine);
        defer engine.freeValue(options);
        const store = try get(engine, job, "store");
        defer engine.freeValue(store);
        try put(engine, options, "ctx", try get(engine, store, "authContext"));
        const api_type = try engine.checked(c.JS_NewString(engine.context, "api_key"));
        defer engine.freeValue(api_type);
        try put(engine, options, "credential", if (same(credential_type, api_type, engine)) c.JS_DupValue(engine.context, value) else c.pi_js_undefined());
        try put(engine, options, "signal", try get(engine, job, "signal"));
        const check = try get(engine, api_key, "check");
        defer engine.freeValue(check);
        try put(engine, job, "pendingStage", c.JS_NewInt32(engine.context, @intFromEnum(if (!c.JS_IsUndefined(check)) Stage.auth else Stage.resolution)));
        const pending = if (!c.JS_IsUndefined(check)) try call(engine, api_key, check, &.{options}) else try invoke(engine, api_key, "resolve", &.{options});
        defer engine.freeValue(pending);
        return then(engine, job, pending, if (!c.JS_IsUndefined(check)) .auth else .resolution);
    }
    if (stage == .resolution) {
        const check = if (c.JS_ToBool(engine.context, value) == 1) try newObject(engine) else c.pi_js_undefined();
        defer engine.freeValue(check);
        if (!c.JS_IsUndefined(check)) try put(engine, check, "type", try engine.checked(c.JS_NewString(engine.context, "api_key")));
        return continueJob(engine, job, .auth, check);
    }
    const only_check = try get(engine, job, "onlyCheck");
    defer engine.freeValue(only_check);
    if (c.JS_ToBool(engine.context, only_check) == 1) return finish(engine, job, value, true);
    if (c.JS_IsUndefined(value)) {
        const empty = try engine.checked(c.JS_NewArray(engine.context));
        defer engine.freeValue(empty);
        return finish(engine, job, empty, true);
    }
    const all = try get(engine, job, "all");
    defer engine.freeValue(all);
    const all_types = c.JS_ToBool(engine.context, all) == 1;
    // Credential/auth resolution has completed. Exceptions thrown while
    // obtaining or filtering models retain their original identity.
    try put(engine, job, "pendingStage", c.pi_js_undefined());
    const models = try providerModels(engine, provider, all_types);
    defer engine.freeValue(models);
    const credential = try get(engine, job, "credential");
    defer engine.freeValue(credential);
    const filter = try get(engine, provider, if (all_types) "filterAllModels" else "filterModels");
    defer engine.freeValue(filter);
    if (c.JS_ToBool(engine.context, filter) == 1) {
        const filtered = try call(engine, provider, filter, &.{ models, credential });
        defer engine.freeValue(filtered);
        return finish(engine, job, filtered, true);
    }
    if (!all_types) return finish(engine, job, models, true);
    const chat_filter = try get(engine, provider, "filterModels");
    defer engine.freeValue(chat_filter);
    if (c.JS_ToBool(engine.context, chat_filter) != 1) return finish(engine, job, models, true);
    const chat = try providerModels(engine, provider, false);
    defer engine.freeValue(chat);
    const available_chat = try call(engine, provider, chat_filter, &.{ chat, credential });
    defer engine.freeValue(available_chat);
    const result = try engine.checked(c.JS_NewArray(engine.context));
    defer engine.freeValue(result);
    var output: u32 = 0;
    const chat_type = try engine.checked(c.JS_NewString(engine.context, "chat"));
    defer engine.freeValue(chat_type);
    for (0..try length(engine, models)) |index| {
        const model = try engine.checked(c.JS_GetPropertyUint32(engine.context, models, @intCast(index)));
        defer engine.freeValue(model);
        const kind = try modelType(engine, model);
        defer engine.freeValue(kind);
        var allowed = !same(kind, chat_type, engine);
        if (!allowed) {
            const id = try get(engine, model, "id");
            defer engine.freeValue(id);
            for (0..try length(engine, available_chat)) |chat_index| {
                const candidate = try engine.checked(c.JS_GetPropertyUint32(engine.context, available_chat, @intCast(chat_index)));
                defer engine.freeValue(candidate);
                const candidate_id = try get(engine, candidate, "id");
                defer engine.freeValue(candidate_id);
                if (same(id, candidate_id, engine)) {
                    allowed = true;
                    break;
                }
            }
        }
        if (allowed) {
            try append(engine, result, output, c.JS_DupValue(engine.context, model));
            output += 1;
        }
    }
    return finish(engine, job, result, true);
}
fn continuation(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, magic: c_int, data: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = engine_mod.Engine.fromContext(context.?);
    continueJob(engine, data[0], @enumFromInt(magic), if (argc > 0) argv[0] else c.pi_js_undefined()) catch {
        const exception = if (engine.captured_exception) |value| c.JS_DupValue(context, value) else c.JS_NewString(context, "Native model availability failed");
        defer engine.freeValue(exception);
        continueJob(engine, data[0], .reject, exception) catch {
            finish(engine, data[0], exception, false) catch {};
        };
    };
    return c.pi_js_undefined();
}
fn available(engine: *engine_mod.Engine, store: c.JSValue, method: Method, args: []const c.JSValue) !c.JSValue {
    const typed = method == .getAvailableOfType;
    const id = if (args.len > @as(usize, if (typed) 1 else 0)) args[if (typed) 1 else 0] else c.pi_js_undefined();
    const options = if (args.len > @as(usize, if (typed) 2 else 1)) args[if (typed) 2 else 1] else c.pi_js_undefined();
    const supplied_signal = if (c.JS_IsUndefined(options) or c.JS_IsNull(options)) c.pi_js_undefined() else try get(engine, options, "signal");
    defer engine.freeValue(supplied_signal);
    const signal = if (c.JS_IsUndefined(supplied_signal) or c.JS_IsNull(supplied_signal)) try abort_signal.create(engine) else c.JS_DupValue(engine.context, supplied_signal);
    defer engine.freeValue(signal);
    const aggregate = try newObject(engine);
    defer engine.freeValue(aggregate);
    try put(engine, aggregate, "store", c.JS_DupValue(engine.context, store));
    try put(engine, aggregate, "signal", c.JS_DupValue(engine.context, signal));
    try put(engine, aggregate, "raceAbort", c.pi_js_bool(engine.context, 1));
    try put(engine, aggregate, "onlyCheck", c.pi_js_bool(engine.context, @intFromBool(method == .checkAuth)));
    if (typed) try put(engine, aggregate, "type", c.JS_DupValue(engine.context, args[0]));
    const aggregate_result = try newPromise(engine, aggregate);
    errdefer engine.freeValue(aggregate_result);
    if (try checkAborted(engine, aggregate)) return aggregate_result;
    const providers = try providerList(engine, store, id);
    defer engine.freeValue(providers);
    const pending = try engine.checked(c.JS_NewArray(engine.context));
    defer engine.freeValue(pending);
    for (0..try length(engine, providers)) |index| {
        const provider = try engine.checked(c.JS_GetPropertyUint32(engine.context, providers, @intCast(index)));
        defer engine.freeValue(provider);
        const job = try newObject(engine);
        defer engine.freeValue(job);
        try put(engine, job, "store", c.JS_DupValue(engine.context, store));
        try put(engine, job, "provider", c.JS_DupValue(engine.context, provider));
        try put(engine, job, "signal", c.JS_DupValue(engine.context, signal));
        try put(engine, job, "all", c.pi_js_bool(engine.context, @intFromBool(method != .getAvailable)));
        try put(engine, job, "onlyCheck", c.pi_js_bool(engine.context, @intFromBool(method == .checkAuth)));
        const result = try newPromise(engine, job);
        errdefer engine.freeValue(result);
        start: {
            const credentials = try get(engine, store, "credentials");
            defer engine.freeValue(credentials);
            const provider_id = try get(engine, provider, "id");
            defer engine.freeValue(provider_id);
            const read_options = try newObject(engine);
            defer engine.freeValue(read_options);
            try put(engine, read_options, "signal", c.JS_DupValue(engine.context, signal));
            try put(engine, job, "pendingStage", c.JS_NewInt32(engine.context, @intFromEnum(Stage.credential)));
            const value = if (c.JS_IsUndefined(credentials) or c.JS_IsNull(credentials)) c.pi_js_undefined() else invoke(engine, credentials, "read", &.{ provider_id, read_options }) catch {
                const exception = engine.captured_exception orelse c.pi_js_undefined();
                try continueJob(engine, job, .reject, exception);
                break :start;
            };
            defer engine.freeValue(value);
            try then(engine, job, value, .credential);
        }
        try append(engine, pending, @intCast(index), result);
    }
    const cache = try get(engine, store, "cache");
    defer engine.freeValue(cache);
    const constructor = try get(engine, cache, "promise_constructor");
    defer engine.freeValue(constructor);
    const all = try cached(engine, store, "promise_all", constructor, &.{pending});
    defer engine.freeValue(all);
    try then(engine, aggregate, all, .aggregate);
    const listener = try continuationFunction(engine, aggregate, .abort);
    defer engine.freeValue(listener);
    try put(engine, aggregate, "listener", c.JS_DupValue(engine.context, listener));
    const event = try engine.checked(c.JS_NewString(engine.context, "abort"));
    defer engine.freeValue(event);
    const ignored = try invoke(engine, signal, "addEventListener", &.{ event, listener });
    engine.freeValue(ignored);
    _ = try checkAborted(engine, aggregate);
    return aggregate_result;
}

fn resolvedPromise(engine: *engine_mod.Engine, value: c.JSValue) !c.JSValue {
    var functions: [2]c.JSValue = undefined;
    const result = try engine.checked(c.JS_NewPromiseCapability(engine.context, &functions));
    errdefer engine.freeValue(result);
    defer for (functions) |item| engine.freeValue(item);
    const ignored = try call(engine, c.pi_js_undefined(), functions[0], &.{value});
    engine.freeValue(ignored);
    return result;
}
fn errorConstructor(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, data: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = engine_mod.Engine.fromContext(context.?);
    const result = errorValue(engine, data[0], if (argc > 0) argv[0] else c.pi_js_undefined(), if (argc > 1) argv[1] else c.pi_js_undefined(), if (argc > 2) argv[2] else c.pi_js_undefined()) catch |err| {
        if (err == error.JavaScriptException) return engine.throwCaptured();
        return c.JS_ThrowOutOfMemory(context);
    };
    return result;
}
fn errorValue(engine: *engine_mod.Engine, prototype: c.JSValue, code: c.JSValue, message: c.JSValue, options: c.JSValue) !c.JSValue {
    const result = try engine.checked(c.JS_NewError(engine.context));
    errdefer engine.freeValue(result);
    if (c.JS_SetPrototype(engine.context, result, prototype) < 0) return error.JavaScriptException;
    try put(engine, result, "name", try engine.checked(c.JS_NewString(engine.context, "ModelsError")));
    try put(engine, result, "code", c.JS_DupValue(engine.context, code));
    const formatting_cause = if (c.JS_IsUndefined(options) or c.JS_IsNull(options)) c.pi_js_undefined() else try get(engine, options, "cause");
    defer engine.freeValue(formatting_cause);
    if (!c.JS_IsUndefined(message)) {
        const prefix = try engine.toString(message);
        defer engine.gpa.free(prefix);
        const detail_value = if (c.JS_IsError(formatting_cause)) detail: {
            const error_message = try get(engine, formatting_cause, "message");
            if (c.JS_ToBool(engine.context, error_message) == 1) break :detail error_message;
            engine.freeValue(error_message);
            break :detail try get(engine, formatting_cause, "name");
        } else c.JS_DupValue(engine.context, formatting_cause);
        defer engine.freeValue(detail_value);
        const detail_text = if (c.JS_IsUndefined(formatting_cause) or c.JS_IsNull(formatting_cause)) try engine.gpa.dupe(u8, "") else try engine.toString(detail_value);
        defer engine.gpa.free(detail_text);
        const formatted = if (detail_text.len > 0 and std.mem.indexOf(u8, prefix, detail_text) == null) try std.fmt.allocPrint(engine.gpa, "{s}: {s}", .{ prefix, detail_text }) else try engine.gpa.dupe(u8, prefix);
        defer engine.gpa.free(formatted);
        try errorProperty(engine, result, "message", try engine.checked(c.JS_NewStringLen(engine.context, formatted.ptr, formatted.len)));
    }
    if (!c.JS_IsUndefined(options) and !c.JS_IsNull(options)) {
        const atom = c.JS_NewAtom(engine.context, "cause");
        defer c.JS_FreeAtom(engine.context, atom);
        const present = c.JS_HasProperty(engine.context, options, atom);
        if (present < 0) return error.JavaScriptException;
        if (present == 1) try errorProperty(engine, result, "cause", try get(engine, options, "cause"));
    }
    return result;
}
fn defaultAuthContext(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, magic: c_int) callconv(.c) c.JSValue {
    const engine = engine_mod.Engine.fromContext(context.?);
    return defaultAuthValue(engine, if (argc > 0) argv[0] else c.pi_js_undefined(), magic == 0) catch return engine.throwCaptured();
}
fn defaultAuthValue(engine: *engine_mod.Engine, name: c.JSValue, environment: bool) !c.JSValue {
    if (!environment) {
        const file = engine.native_module_values.get("node:fs");
        if (file) |exports| {
            const value = invoke(engine, exports, "existsSync", &.{name}) catch c.pi_js_bool(engine.context, 0);
            defer engine.freeValue(value);
            return resolvedPromise(engine, value);
        }
        return resolvedPromise(engine, c.pi_js_bool(engine.context, 0));
    }
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    const process = try get(engine, global, "process");
    defer engine.freeValue(process);
    if (c.JS_IsUndefined(process)) return resolvedPromise(engine, c.pi_js_undefined());
    const env = try get(engine, process, "env");
    defer engine.freeValue(env);
    const atom = c.JS_ValueToAtom(engine.context, name);
    if (atom == c.JS_ATOM_NULL) return error.JavaScriptException;
    defer c.JS_FreeAtom(engine.context, atom);
    const value = try engine.checked(c.JS_GetProperty(engine.context, env, atom));
    defer engine.freeValue(value);
    if (!c.JS_IsString(value)) return resolvedPromise(engine, c.pi_js_undefined());
    const trimmed = try invoke(engine, value, "trim", &.{});
    defer engine.freeValue(trimmed);
    const count = try length(engine, trimmed);
    return resolvedPromise(engine, if (count > 0) value else c.pi_js_undefined());
}

/// Adapt declarative/snapshot lists to the same typed Provider catalog contract.
/// Native Provider objects bypass this adapter and retain their exact identity.
pub fn snapshotProvider(engine: *engine_mod.Engine, name: c.JSValue, config: c.JSValue, configured: bool, normalize: bool) !c.JSValue {
    const provider = try newObject(engine);
    errdefer engine.freeValue(provider);
    try put(engine, provider, "id", c.JS_DupValue(engine.context, name));
    var data = [_]c.JSValue{ config, name, c.pi_js_bool(engine.context, @intFromBool(configured)), c.pi_js_bool(engine.context, @intFromBool(normalize)) };
    try put(engine, provider, "getModels", try engine.checked(c.JS_NewCFunctionData2(engine.context, snapshotCallback, "getModels", 0, 0, data.len, &data)));
    try put(engine, provider, "getAllModels", try engine.checked(c.JS_NewCFunctionData2(engine.context, snapshotCallback, "getAllModels", 0, 1, data.len, &data)));
    const auth = try newObject(engine);
    defer engine.freeValue(auth);
    const api_key = try newObject(engine);
    defer engine.freeValue(api_key);
    try put(engine, api_key, "check", try engine.checked(c.JS_NewCFunctionData2(engine.context, snapshotCallback, "check", 1, 2, data.len, &data)));
    try put(engine, auth, "apiKey", c.JS_DupValue(engine.context, api_key));
    try put(engine, provider, "auth", c.JS_DupValue(engine.context, auth));
    return provider;
}
fn snapshotCallback(context: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue, magic: c_int, data: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = engine_mod.Engine.fromContext(context.?);
    return snapshotValue(engine, magic, data) catch |err| {
        if (err == error.JavaScriptException) return engine.throwCaptured();
        return c.JS_ThrowOutOfMemory(context);
    };
}
fn snapshotValue(engine: *engine_mod.Engine, magic: c_int, data: [*c]c.JSValue) !c.JSValue {
    if (magic == 2) {
        var configured = c.JS_ToBool(engine.context, data[2]) == 1;
        if (!configured and c.JS_ToBool(engine.context, data[3]) == 1) {
            const key = try get(engine, data[0], "apiKey");
            defer engine.freeValue(key);
            if (c.JS_IsString(key)) {
                const text = try engine.toString(key);
                defer engine.gpa.free(text);
                // Literal extension-owned keys can be checked locally. Host
                // credential/command resolution remains authoritative in its
                // configured snapshot; do not equate a placeholder with auth.
                configured = text.len > 0 and text[0] != '$' and text[0] != '!';
            }
        }
        if (!configured) return c.pi_js_undefined();
        const check = try newObject(engine);
        errdefer engine.freeValue(check);
        try put(engine, check, "type", try engine.checked(c.JS_NewString(engine.context, "api_key")));
        return check;
    }
    const preferred = try get(engine, data[0], if (magic == 1) "getAllModels" else "getModels");
    defer engine.freeValue(preferred);
    const fallback = if (magic == 1 and c.JS_IsUndefined(preferred)) try get(engine, data[0], "getModels") else c.pi_js_undefined();
    defer engine.freeValue(fallback);
    const models = if (c.JS_IsFunction(engine.context, preferred)) try call(engine, data[0], preferred, &.{}) else if (c.JS_IsFunction(engine.context, fallback)) try call(engine, data[0], fallback, &.{}) else try get(engine, data[0], "models");
    defer engine.freeValue(models);
    if (c.JS_IsUndefined(models)) return engine.checked(c.JS_NewArray(engine.context));
    const projected = if (c.JS_ToBool(engine.context, data[3]) == 1) try normalizeModels(engine, data[1], data[0], models) else c.JS_DupValue(engine.context, models);
    defer engine.freeValue(projected);
    if (magic == 1) return c.JS_DupValue(engine.context, projected);
    const kind = try engine.checked(c.JS_NewString(engine.context, "chat"));
    defer engine.freeValue(kind);
    return filterType(engine, projected, kind);
}
fn normalizeModels(engine: *engine_mod.Engine, name: c.JSValue, config: c.JSValue, models: c.JSValue) !c.JSValue {
    const result = try engine.checked(c.JS_NewArray(engine.context));
    errdefer engine.freeValue(result);
    for (0..try length(engine, models)) |index| {
        const source = try engine.checked(c.JS_GetPropertyUint32(engine.context, models, @intCast(index)));
        defer engine.freeValue(source);
        const model = try engine.checked(c.JS_NewObject(engine.context));
        defer engine.freeValue(model);
        var names: [*c]c.JSPropertyEnum = null;
        var count: u32 = 0;
        if (c.JS_GetOwnPropertyNames(engine.context, &names, &count, source, c.JS_GPN_STRING_MASK | c.JS_GPN_ENUM_ONLY) < 0) return error.JavaScriptException;
        defer c.JS_FreePropertyEnum(engine.context, names, count);
        for (names[0..count]) |property_name| {
            const value = try engine.checked(c.JS_GetProperty(engine.context, source, property_name.atom));
            if (c.JS_DefinePropertyValue(engine.context, model, property_name.atom, value, c.JS_PROP_C_W_E) < 0) return error.JavaScriptException;
        }
        try put(engine, model, "provider", c.JS_DupValue(engine.context, name));
        inline for (.{ "api", "baseUrl" }) |field| {
            const existing = try get(engine, model, field);
            defer engine.freeValue(existing);
            if (c.JS_IsUndefined(existing)) {
                const inherited = try get(engine, config, field);
                if (c.JS_IsUndefined(inherited)) engine.freeValue(inherited) else try put(engine, model, field, inherited);
            }
        }
        try append(engine, result, @intCast(index), c.JS_DupValue(engine.context, model));
    }
    return result;
}

test "native Models typed catalogs preserve identity order availability filtering auth causes and cancellation" {
    const engine = try engine_mod.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    try @import("abort_signal.zig").install(engine);
    const exports = try newObject(engine);
    defer engine.freeValue(exports);
    try populateExports(engine, exports);
    try engine.registerValueModule("native-models-test", exports);
    const module = try engine.evalModule(
        \\import {createModels,getModelType,isModelType,ModelsError} from 'native-models-test';
        \\const assert=(value,label)=>{if(!value)throw Error(label)};const cause=new Error('ctor-detail'),wrapped=new ModelsError('auth','ctor-prefix',{cause});assert(wrapped instanceof Error&&wrapped instanceof ModelsError&&wrapped.cause===cause&&wrapped.message==='ctor-prefix: ctor-detail','error constructor');assert(!Object.keys(wrapped).includes('message')&&!Object.keys(wrapped).includes('cause'),'error descriptors');
        \\const chat={id:'same',provider:'a'},image={type:'image',id:'same',provider:'a'},classifier={type:'classifier',id:'same',provider:'a'},extra={id:'extra',provider:'a'};
        \\const chats=[chat,extra],all=[chat,image,classifier,extra];let checks=0;
        \\const apiKey={async check(input){assert(this===apiKey,'auth receiver');assert(input.credential.key==='key-a','credential');assert(input.signal instanceof AbortSignal,'operation signal');checks++;return {type:'api_key'}}};
        \\const a={id:'a',auth:{apiKey},getModels(){assert(this===a,'models receiver');return chats},getAllModels(){return all},filterModels(models){assert(this===a,'filter receiver');return models.filter(m=>m.id!=='same')}};
        \\const m=createModels({credentials:{async read(id){return {type:'api_key',key:'key-'+id}}}});m.setProvider(a);
        \\assert(m.getModels('a')===chats,'single array identity');assert(m.getAllModels('a')===all,'all array identity');assert(m.getModels().length===2,'chat only');assert(m.getAllModels().length===4,'all types');
        \\assert(m.getModel('a','same')===chat&&m.getModelOfType('image','a','same')===image,'qualified identity');assert(m.getModelsOfType('classifier')[0]===classifier,'classifier');assert(getModelType(chat)==='chat'&&isModelType(image,'image'),'type guards');
        \\const available=await m.getAllAvailable();assert(available.length===3&&available[0]===image&&available[1]===classifier&&available[2]===extra,'chat filter keeps nonchat');assert((await m.getAvailable()).length===1,'available chat');assert((await m.getAvailableOfType('image'))[0]===image,'typed available');
        \\a.filterAllModels=function(models){return models.filter(model=>model.type==='classifier')};assert((await m.getAllAvailable())[0]===classifier,'all filter override');
        \\const original={original:true};m.setProvider({id:'bad',auth:{apiKey:{check(){throw original}}},getModels(){throw original}});assert(m.getModels().length===2,'best effort provider');try{await m.getAllAvailable('bad');throw Error('missing rejection')}catch(error){assert(error.cause===original&&error.code==='auth'&&error instanceof ModelsError,'auth cause')}
        \\m.setProvider({id:'bad',auth:{apiKey:{async check(){return undefined}}},getModels(){return []}});assert(m.getProviders()[0]===a&&m.getProviders()[1].id==='bad','replacement order');assert(m.deleteProvider('bad')===undefined,'delete void');
        \\let release;const blocked=createModels({credentials:{read(){return new Promise(resolve=>release=resolve)}}});blocked.setProvider(a);const controller=new AbortController,reason={cancel:'original'};const pending=blocked.getAllAvailable(undefined,{signal:controller.signal});controller.abort(reason);try{await pending;throw Error('not cancelled')}catch(error){assert(error===reason,'abort identity')};const before=checks;release({type:'api_key',key:'key-a'});await Promise.resolve();await Promise.resolve();assert(checks===before+1,'abandoned operation remains observed');
        \\m.clearProviders();assert(m.getAllModels().length===0,'clear');let added=false;m.setProvider({id:'first',getModels(){if(!added){added=true;m.setProvider({id:'late',getModels(){return [{id:'late',provider:'late'}]}})}return [{id:'first',provider:'first'}]}});assert(m.getModels().map(model=>model.id).join(',')==='first,late','live iteration');export const result='native-models-ok';
    , "native-models-contract.mjs");
    defer engine.freeValue(module);
    const result = try get(engine, module, "result");
    defer engine.freeValue(result);
    const text = try engine.toString(result);
    defer engine.gpa.free(text);
    try std.testing.expectEqualStrings("native-models-ok", text);
    c.JS_RunGC(engine.runtime);
}

test "native Models installation catalog async queries and signal ownership release every failed host allocation" {
    const Probe = struct {
        fn exercise(gpa: std.mem.Allocator) !void {
            const engine = try engine_mod.Engine.init(gpa, .{});
            defer engine.deinit();
            const exports = try newObject(engine);
            defer engine.freeValue(exports);
            try populateExports(engine, exports);
            try engine.registerValueModule("native-allocation-models", exports);
            const module = try engine.evalModule("import {createModels} from 'native-allocation-models';const m=createModels();m.setProvider({id:'p',auth:{apiKey:{async check(){return {type:'api_key'}}}},getModels(){return [{id:'m',provider:'p'}]},getAllModels(){return [{id:'m',provider:'p'},{id:'image',provider:'p',type:'image'}]}});export const result=await m.getAvailableOfType('image');if(result.length!==1)throw Error('allocation query');", "native-model-allocations.mjs");
            defer engine.freeValue(module);
            c.JS_RunGC(engine.runtime);
        }
        fn run(gpa: std.mem.Allocator) !void {
            exercise(gpa) catch |err| {
                const failing: *std.testing.FailingAllocator = @ptrCast(@alignCast(gpa.ptr));
                if (failing.has_induced_failure and (err == error.JavaScriptException or err == error.OutOfMemory)) return error.OutOfMemory;
                return err;
            };
        }
    };
    try std.testing.checkAllAllocationFailures(std.testing.allocator, Probe.run, .{});
}
