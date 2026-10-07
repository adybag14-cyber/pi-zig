//! The public pi-ai in-memory model store. Values are cloned by QuickJS's
//! native graph serializer; no host script performs storage or cloning.
const std = @import("std");
const engine_mod = @import("engine.zig");
const sdk = @import("native_sdk.zig");
const c = engine_mod.c;
const State = struct { engine: *engine_mod.Engine, entries: c.JSValue };
fn finalize(runtime: ?*c.JSRuntime, value: c.JSValue) callconv(.c) void {
    const engine: *engine_mod.Engine = @ptrCast(@alignCast(c.JS_GetRuntimeOpaque(runtime)));
    const self: *State = @ptrCast(@alignCast(c.JS_GetOpaque(value, engine.native_models_store_class) orelse return));
    c.JS_FreeValueRT(runtime, self.entries);
    engine.gpa.destroy(self);
}
fn mark(runtime: ?*c.JSRuntime, value: c.JSValue, marker: ?*const c.JS_MarkFunc) callconv(.c) void {
    const engine: *engine_mod.Engine = @ptrCast(@alignCast(c.JS_GetRuntimeOpaque(runtime)));
    const self: *State = @ptrCast(@alignCast(c.JS_GetOpaque(value, engine.native_models_store_class) orelse return));
    c.JS_MarkValue(runtime, self.entries, marker);
}
pub fn clone(engine: *engine_mod.Engine, value: c.JSValue) !c.JSValue {
    var length: usize = 0;
    const bytes = c.JS_WriteObject(engine.context, &length, value, c.JS_WRITE_OBJ_REFERENCE) orelse {
        _ = engine.checked(c.JS_Throw(engine.context, c.JS_GetException(engine.context))) catch {};
        return error.JavaScriptException;
    };
    defer c.js_free(engine.context, bytes);
    if (length > 16 * 1024 * 1024) return error.NativeModelsStoreLimit;
    return engine.checked(c.JS_ReadObject(engine.context, bytes, length, c.JS_READ_OBJ_REFERENCE));
}
fn rejected(engine: *engine_mod.Engine, failure: c.JSValue) !c.JSValue {
    var caps: [2]c.JSValue = undefined;
    const promise = try engine.checked(c.JS_NewPromiseCapability(engine.context, &caps));
    errdefer engine.freeValue(promise);
    defer for (caps) |value| engine.freeValue(value);
    var args = [_]c.JSValue{failure};
    const result = try engine.checked(c.JS_Call(engine.context, caps[1], c.pi_js_undefined(), 1, &args));
    engine.freeValue(result);
    return promise;
}
fn method(context: ?*c.JSContext, receiver: c.JSValue, argc: c_int, argv: [*c]c.JSValue, operation: c_int) callconv(.c) c.JSValue {
    const engine = engine_mod.Engine.fromContext(context.?);
    const self: *State = @ptrCast(@alignCast(c.JS_GetOpaque2(engine.context, receiver, engine.native_models_store_class) orelse return c.JS_Throw(context, c.JS_GetException(context))));
    return execute(self, operation, if (argc > 0) argv[0..@intCast(argc)] else &.{}) catch |err| {
        _ = sdk.fail(engine, err);
        const failure = c.JS_GetException(context);
        defer engine.freeValue(failure);
        return rejected(engine, failure) catch |failure_error| sdk.fail(engine, failure_error);
    };
}
fn execute(self: *State, operation: c_int, args: []const c.JSValue) !c.JSValue {
    const engine = self.engine;
    const options = if (args.len > @as(usize, if (operation == 1) 2 else 1)) args[if (operation == 1) 2 else 1] else c.pi_js_undefined();
    if (c.JS_IsObject(options)) {
        const signal = try sdk.get(engine, options, "signal");
        defer engine.freeValue(signal);
        if (c.JS_IsObject(signal)) {
            const checked = try sdk.invoke(engine, signal, "throwIfAborted", &.{});
            engine.freeValue(checked);
        }
    }
    const id = if (args.len > 0) args[0] else c.pi_js_undefined();
    if (operation == 0) {
        const stored = try sdk.invoke(engine, self.entries, "get", &.{id});
        defer engine.freeValue(stored);
        const owned = try clone(engine, stored);
        defer engine.freeValue(owned);
        return sdk.promise(engine, owned);
    }
    if (operation == 1) {
        const input = if (args.len > 1) args[1] else c.pi_js_undefined();
        const owned = try clone(engine, input);
        defer engine.freeValue(owned);
        const ignored = try sdk.invoke(engine, self.entries, "set", &.{ id, owned });
        engine.freeValue(ignored);
    } else {
        const ignored = try sdk.invoke(engine, self.entries, "delete", &.{id});
        engine.freeValue(ignored);
    }
    return sdk.promise(engine, c.pi_js_undefined());
}
fn construct(context: ?*c.JSContext, new_target: c.JSValue, _: c_int, _: [*c]c.JSValue, _: c_int) callconv(.c) c.JSValue {
    const engine = engine_mod.Engine.fromContext(context.?);
    return create(engine, new_target) catch |err| sdk.fail(engine, err);
}
fn cloneCallback(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int) callconv(.c) c.JSValue {
    const engine = engine_mod.Engine.fromContext(context.?);
    if (argc < 1) return c.JS_ThrowTypeError(context, "structuredClone requires a value");
    if (argc > 1 and c.JS_IsObject(argv[1])) {
        const transfer = sdk.get(engine, argv[1], "transfer") catch |err| return sdk.fail(engine, err);
        defer engine.freeValue(transfer);
        if (!c.JS_IsUndefined(transfer)) {
            if (!c.JS_IsArray(transfer)) return c.JS_ThrowTypeError(context, "Native structuredClone transfer must be an array");
            const count = sdk.length(engine, transfer) catch |err| return sdk.fail(engine, err);
            if (count != 0) return c.JS_ThrowTypeError(context, "Native structuredClone transferable objects are not implemented");
        }
    }
    return clone(engine, argv[0]) catch |err| sdk.fail(engine, err);
}
fn create(engine: *engine_mod.Engine, new_target: c.JSValue) !c.JSValue {
    const prototype = try sdk.get(engine, new_target, "prototype");
    defer engine.freeValue(prototype);
    const value = try engine.checked(c.JS_NewObjectProtoClass(engine.context, prototype, engine.native_models_store_class));
    errdefer engine.freeValue(value);
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    const map = try sdk.get(engine, global, "Map");
    defer engine.freeValue(map);
    const entries = try engine.checked(c.JS_CallConstructor(engine.context, map, 0, null));
    errdefer engine.freeValue(entries);
    const self = try engine.gpa.create(State);
    self.* = .{ .engine = engine, .entries = entries };
    _ = c.JS_SetOpaque(value, self);
    return value;
}
pub fn install(engine: *engine_mod.Engine, exports: c.JSValue) !void {
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    const existing_clone = try sdk.get(engine, global, "structuredClone");
    defer engine.freeValue(existing_clone);
    if (c.JS_IsUndefined(existing_clone)) try sdk.put(engine, global, "structuredClone", try engine.checked(c.pi_js_function_magic(engine.context, cloneCallback, "structuredClone", 1, 0)));
    if (engine.native_models_store_class == 0) {
        _ = c.JS_NewClassID(engine.runtime, &engine.native_models_store_class);
        var class: c.JSClassDef = std.mem.zeroes(c.JSClassDef);
        class.class_name = "NativeInMemoryModelsStore";
        class.finalizer = finalize;
        class.gc_mark = mark;
        if (c.JS_NewClass(engine.runtime, engine.native_models_store_class, &class) < 0) return error.OutOfMemory;
    }
    const prototype = try sdk.object(engine);
    defer engine.freeValue(prototype);
    inline for (.{ .{ "read", 0 }, .{ "write", 1 }, .{ "delete", 2 } }) |entry| try sdk.put(engine, prototype, entry[0], try engine.checked(c.pi_js_function_magic(engine.context, method, entry[0], 2, entry[1])));
    const constructor = try engine.checked(c.pi_js_function_magic(engine.context, construct, "InMemoryModelsStore", 0, 0));
    defer engine.freeValue(constructor);
    _ = c.JS_SetConstructorBit(engine.context, constructor, true);
    if (c.JS_SetConstructor(engine.context, constructor, prototype) < 0) return error.JavaScriptException;
    try sdk.put(engine, exports, "InMemoryModelsStore", c.JS_DupValue(engine.context, constructor));
}
