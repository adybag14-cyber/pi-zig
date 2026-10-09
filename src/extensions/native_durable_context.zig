//! Native Chord Context derivation; parent and keyed values are owner VM roots.
const engine_mod = @import("engine.zig");
const sdk = @import("native_sdk.zig");
const durable = @import("native_durable.zig");
const Engine = engine_mod.Engine;
const c = engine_mod.c;
pub fn withoutAbortSignal(engine: *Engine, parent: c.JSValue) !c.JSValue {
    const label = try sdk.text(engine, "chord.abortSignal");
    defer engine.freeValue(label);
    return derive(engine, parent, c.pi_js_undefined(), c.pi_js_undefined(), c.pi_js_undefined(), label);
}
pub fn withAbortSignal(engine: *Engine, signal: c.JSValue, parent: c.JSValue) anyerror!c.JSValue {
    return exportedOwned(engine, &.{ signal, parent }, 2);
}
fn derive(engine: *Engine, parent: c.JSValue, key: c.JSValue, value: c.JSValue, signal: c.JSValue, name: c.JSValue) !c.JSValue {
    const object = try sdk.object(engine);
    errdefer engine.freeValue(object);
    var data = [_]c.JSValue{ parent, key, value, name };
    inline for (.{ "value", "toString" }, 0..) |method_name, operation| {
        const callback = try engine.checked(c.JS_NewCFunctionData(engine.context, contextMethod, 1, @intCast(operation), data.len, &data));
        if (c.JS_DefinePropertyValueStr(engine.context, object, method_name, callback, 0) < 0) return error.JavaScriptException;
    }
    if (c.JS_DefinePropertyValueStr(engine.context, object, "abortSignal", c.JS_DupValue(engine.context, signal), 0) < 0) return error.JavaScriptException;
    return object;
}
fn contextMethod(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, operation: c_int, data: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = Engine.fromContext(context.?);
    return contextMethodOwned(engine, if (argc > 0) argv[0] else c.pi_js_undefined(), operation, data) catch |err| durable.reject(engine, err);
}
fn contextMethodOwned(engine: *Engine, key: c.JSValue, operation: c_int, data: [*c]c.JSValue) !c.JSValue {
    if (operation == 0) {
        if (!c.JS_IsUndefined(data[1])) {
            const requested = try sdk.get(engine, key, "token");
            defer engine.freeValue(requested);
            const stored = try sdk.get(engine, data[1], "token");
            defer engine.freeValue(stored);
            if (c.JS_IsStrictEqual(engine.context, requested, stored)) return c.JS_DupValue(engine.context, data[2]);
        }
        if (c.JS_IsUndefined(data[0])) return c.pi_js_undefined();
        return sdk.invoke(engine, data[0], "value", &.{key});
    }
    if (c.JS_IsUndefined(data[0])) return c.JS_DupValue(engine.context, data[3]);
    const parent = try engine.toString(data[0]);
    defer engine.gpa.free(parent);
    const name = if (!c.JS_IsUndefined(data[1])) blk: {
        const token = try sdk.get(engine, data[1], "token");
        defer engine.freeValue(token);
        const description = try sdk.get(engine, token, "description");
        defer engine.freeValue(description);
        break :blk if (c.JS_IsUndefined(description)) try engine.gpa.dupe(u8, "anonymous") else try engine.toString(description);
    } else try engine.toString(data[3]);
    defer engine.gpa.free(name);
    const text = try @import("std").fmt.allocPrint(engine.gpa, "{s}.WithValue({s})", .{ parent, name });
    defer engine.gpa.free(text);
    return sdk.text(engine, text);
}
pub fn install(engine: *Engine) !void {
    if (!engine.abort_signals_ready) try @import("abort_signal.zig").install(engine);
    const exports = try sdk.object(engine);
    defer engine.freeValue(exports);
    inline for (.{ "BACKGROUND_CONTEXT", "TODO_CONTEXT" }) |name| {
        const label = try sdk.text(engine, if (@import("std").mem.eql(u8, name, "BACKGROUND_CONTEXT")) "[Context BACKGROUND_CONTEXT]" else "[Context TODO_CONTEXT]");
        defer engine.freeValue(label);
        try sdk.put(engine, exports, name, try derive(engine, c.pi_js_undefined(), c.pi_js_undefined(), c.pi_js_undefined(), c.pi_js_undefined(), label));
    }
    inline for (.{ "createContextKey", "withContextValue", "withAbortSignal", "withoutAbortSignal", "withCancel", "awaitWithContext" }, 0..) |name, operation| try sdk.put(engine, exports, name, try engine.checked(c.pi_js_function_magic(engine.context, exported, name, 3, @intCast(operation))));
    try engine.registerValueModule("@earendil-works/chord/context", exports);
    const root = try sdk.object(engine);
    defer engine.freeValue(root);
    try @import("native_sdk_models.zig").copy(engine, root, exports);
    try @import("native_chord_json.zig").install(engine, root);
    if (!engine.native_module_names.contains("@earendil-works/chord")) try engine.registerValueModule("@earendil-works/chord", root);
}
fn argument(args: []const c.JSValue, index: usize) c.JSValue {
    return if (index < args.len) args[index] else c.pi_js_undefined();
}
fn exported(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, operation: c_int) callconv(.c) c.JSValue {
    const engine = Engine.fromContext(context.?);
    return exportedOwned(engine, argv[0..@intCast(argc)], operation) catch |err| durable.reject(engine, err);
}
fn exportedOwned(engine: *Engine, args: []const c.JSValue, operation: c_int) !c.JSValue {
    if (operation == 5) return awaitWithContext(engine, argument(args, 0), argument(args, 1));
    if (operation == 4) {
        const global = c.JS_GetGlobalObject(engine.context);
        defer engine.freeValue(global);
        const constructor = try sdk.get(engine, global, "AbortController");
        defer engine.freeValue(constructor);
        const controller = try engine.checked(c.JS_CallConstructor(engine.context, constructor, 0, null));
        defer engine.freeValue(controller);
        const signal = try sdk.get(engine, controller, "signal");
        defer engine.freeValue(signal);
        const result = try sdk.object(engine);
        errdefer engine.freeValue(result);
        try sdk.put(engine, result, "context", try withAbortSignal(engine, signal, argument(args, 0)));
        var data = [_]c.JSValue{controller};
        try sdk.put(engine, result, "cancel", try engine.checked(c.JS_NewCFunctionData(engine.context, cancel, 1, 0, 1, &data)));
        return result;
    }
    if (operation == 3) return withoutAbortSignal(engine, argument(args, 0));
    if (operation == 0) {
        const global = c.JS_GetGlobalObject(engine.context);
        defer engine.freeValue(global);
        const symbol = try sdk.get(engine, global, "Symbol");
        defer engine.freeValue(symbol);
        var description = [_]c.JSValue{argument(args, 0)};
        const value = try engine.checked(c.JS_Call(engine.context, symbol, c.pi_js_undefined(), 1, &description));
        const key = try sdk.object(engine);
        errdefer engine.freeValue(key);
        try sdk.put(engine, key, "token", value);
        const object = try sdk.get(engine, global, "Object");
        defer engine.freeValue(object);
        const frozen = try sdk.invoke(engine, object, "freeze", &.{key});
        engine.freeValue(frozen);
        return key;
    }
    const parent = argument(args, if (operation == 1) 2 else 1);
    const inherited = try sdk.get(engine, parent, "abortSignal");
    defer engine.freeValue(inherited);
    const label = try sdk.text(engine, "chord.abortSignal");
    defer engine.freeValue(label);
    if (operation == 1) return derive(engine, parent, argument(args, 0), argument(args, 1), inherited, label);
    var signal = c.JS_DupValue(engine.context, argument(args, 0));
    defer engine.freeValue(signal);
    if (!c.JS_IsUndefined(inherited)) {
        const global = c.JS_GetGlobalObject(engine.context);
        defer engine.freeValue(global);
        const constructor = try sdk.get(engine, global, "AbortSignal");
        defer engine.freeValue(constructor);
        const signals = try sdk.array(engine);
        defer engine.freeValue(signals);
        try sdk.append(engine, signals, c.JS_DupValue(engine.context, inherited));
        try sdk.append(engine, signals, c.JS_DupValue(engine.context, signal));
        const combined = try sdk.invoke(engine, constructor, "any", &.{signals});
        engine.freeValue(signal);
        signal = combined;
    }
    return derive(engine, parent, c.pi_js_undefined(), c.pi_js_undefined(), signal, label);
}
fn cancel(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, data: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = Engine.fromContext(context.?);
    return sdk.invoke(engine, data[0], "abort", argv[0..@intCast(argc)]) catch |err| durable.reject(engine, err);
}
pub fn abortError(engine: *Engine, signal: c.JSValue) !c.JSValue {
    const reason = try sdk.get(engine, signal, "reason");
    var released = false;
    errdefer if (!released) engine.freeValue(reason);
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    const constructor = try sdk.get(engine, global, "Error");
    defer engine.freeValue(constructor);
    const instance = c.JS_IsInstanceOf(engine.context, reason, constructor);
    if (instance < 0) return error.JavaScriptException;
    if (instance > 0) return reason;
    engine.freeValue(reason);
    released = true;
    return @import("dom_exception.zig").create(engine, "The operation was aborted", "AbortError");
}
pub fn awaitWithContext(engine: *Engine, promise: c.JSValue, context: c.JSValue) !c.JSValue {
    const signal = try sdk.get(engine, context, "abortSignal");
    defer engine.freeValue(signal);
    if (c.JS_IsUndefined(signal)) return c.JS_DupValue(engine.context, promise);
    var functions: [2]c.JSValue = undefined;
    const waiter = try engine.checked(c.JS_NewPromiseCapability(engine.context, &functions));
    errdefer engine.freeValue(waiter);
    defer for (functions) |function| engine.freeValue(function);
    const aborted = try sdk.get(engine, signal, "aborted");
    defer engine.freeValue(aborted);
    if (c.JS_ToBool(engine.context, aborted) > 0) {
        const failure = try abortError(engine, signal);
        defer engine.freeValue(failure);
        var values = [_]c.JSValue{failure};
        const result = try engine.checked(c.JS_Call(engine.context, functions[1], c.pi_js_undefined(), 1, &values));
        engine.freeValue(result);
        return waiter;
    }
    var abort_data = [_]c.JSValue{ signal, functions[0], functions[1] };
    const on_abort = try engine.checked(c.JS_NewCFunctionData(engine.context, waitSettled, 1, 2, 3, &abort_data));
    defer engine.freeValue(on_abort);
    const abort = try sdk.text(engine, "abort");
    defer engine.freeValue(abort);
    const options = try sdk.object(engine);
    defer engine.freeValue(options);
    try sdk.put(engine, options, "once", c.pi_js_bool(engine.context, 1));
    const installed = try sdk.invoke(engine, signal, "addEventListener", &.{ abort, on_abort, options });
    engine.freeValue(installed);
    errdefer {
        if (sdk.invoke(engine, signal, "removeEventListener", &.{ abort, on_abort })) |result| engine.freeValue(result) else |_| {}
    }
    var data = [_]c.JSValue{ signal, functions[0], functions[1], on_abort };
    const fulfilled = try engine.checked(c.JS_NewCFunctionData(engine.context, waitSettled, 1, 0, 4, &data));
    defer engine.freeValue(fulfilled);
    const rejected = try engine.checked(c.JS_NewCFunctionData(engine.context, waitSettled, 1, 1, 4, &data));
    defer engine.freeValue(rejected);
    const result = try sdk.invoke(engine, promise, "then", &.{ fulfilled, rejected });
    engine.freeValue(result);
    return waiter;
}
fn waitSettled(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, operation: c_int, data: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = Engine.fromContext(context.?);
    return waitSettledOwned(engine, if (argc > 0) argv[0] else c.pi_js_undefined(), operation, data) catch |err| durable.reject(engine, err);
}
fn waitSettledOwned(engine: *Engine, value: c.JSValue, operation: c_int, data: [*c]c.JSValue) !c.JSValue {
    if (operation != 2) {
        const abort = try sdk.text(engine, "abort");
        defer engine.freeValue(abort);
        const result = try sdk.invoke(engine, data[0], "removeEventListener", &.{ abort, data[3] });
        engine.freeValue(result);
    }
    const settled_value = if (operation == 2) try abortError(engine, data[0]) else c.JS_DupValue(engine.context, value);
    defer engine.freeValue(settled_value);
    var args = [_]c.JSValue{settled_value};
    return engine.checked(c.JS_Call(engine.context, data[if (operation == 0) @as(usize, 1) else 2], c.pi_js_undefined(), 1, &args));
}
