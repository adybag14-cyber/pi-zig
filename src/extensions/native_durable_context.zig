//! Native Chord2 Context values preserve live prototype lookup and private identity.
const engine_mod = @import("engine.zig");
const sdk = @import("native_sdk.zig");
const objects = @import("native_chord_context_objects.zig");
const durable = @import("native_durable.zig");
const Engine = engine_mod.Engine;
const c = engine_mod.c;
pub fn withoutAbortSignal(engine: *Engine, parent: c.JSValue) !c.JSValue {
    const exports = engine.native_module_values.get("@earendil-works/chord/context") orelse return error.NativeChordContextUnavailable;
    return sdk.invoke(engine, exports, "withoutAbortSignal", &.{parent});
}
pub fn withAbortSignal(engine: *Engine, signal: c.JSValue, parent: c.JSValue) anyerror!c.JSValue {
    const exports = engine.native_module_values.get("@earendil-works/chord/context") orelse return error.NativeChordContextUnavailable;
    return sdk.invoke(engine, exports, "withAbortSignal", &.{ signal, parent });
}
fn createKey(engine: *Engine, description: c.JSValue) !c.JSValue {
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    const symbol = try sdk.get(engine, global, "Symbol");
    defer engine.freeValue(symbol);
    var args = [_]c.JSValue{description};
    const token = try engine.checked(c.JS_Call(engine.context, symbol, c.pi_js_undefined(), 1, &args));
    defer engine.freeValue(token);
    const key = try sdk.object(engine);
    errdefer engine.freeValue(key);
    try sdk.put(engine, key, "token", c.JS_DupValue(engine.context, token));
    const object = try sdk.get(engine, global, "Object");
    defer engine.freeValue(object);
    const frozen = try sdk.invoke(engine, object, "freeze", &.{key});
    engine.freeValue(frozen);
    return key;
}
pub fn install(engine: *Engine) !void {
    return installWithRoot(engine, true);
}
/// The private complete package bootstrap installs its real root factory after
/// creating this exact shared context, without first registering a partial root.
pub fn installContextOnly(engine: *Engine) !void {
    return installWithRoot(engine, false);
}
fn installWithRoot(engine: *Engine, compatibility_root: bool) !void {
    if (engine.native_module_names.contains("@earendil-works/chord/context")) return;
    if (!engine.abort_signals_ready) try @import("abort_signal.zig").install(engine);
    const exports = try sdk.object(engine);
    defer engine.freeValue(exports);
    const description = try sdk.text(engine, "chord.abortSignal");
    defer engine.freeValue(description);
    const abort_key = try createKey(engine, description);
    defer engine.freeValue(abort_key);
    const bindings = try objects.bindings(engine, abort_key);
    defer engine.freeValue(bindings);
    inline for (.{ "BACKGROUND_CONTEXT", "TODO_CONTEXT" }) |name| {
        const label = try sdk.text(engine, if (@import("std").mem.eql(u8, name, "BACKGROUND_CONTEXT")) "[Context BACKGROUND_CONTEXT]" else "[Context TODO_CONTEXT]");
        defer engine.freeValue(label);
        try sdk.put(engine, exports, name, try objects.create(engine, bindings, "EmptyContext", &.{label}));
    }
    inline for (.{ "createContextKey", "withContextValue", "withAbortSignal", "withoutAbortSignal", "withCancel", "awaitWithContext" }, 0..) |name, operation| {
        const length: c_int = switch (operation) {
            0, 3, 4 => 1,
            1 => 3,
            else => 2,
        };
        try sdk.put(engine, exports, name, try @import("native_node_function.zig").create(engine, name, length, exported, &.{ bindings, c.JS_NewInt32(engine.context, @intCast(operation)) }));
    }
    try engine.registerValueModule("@earendil-works/chord/context", exports);
    if (!compatibility_root) return;
    const root = try sdk.object(engine);
    defer engine.freeValue(root);
    try @import("native_sdk_models.zig").copy(engine, root, exports);
    try @import("native_chord_json.zig").install(engine, root);
    if (!engine.native_module_names.contains("@earendil-works/chord")) try engine.registerValueModule("@earendil-works/chord", root);
}
fn argument(args: []const c.JSValue, index: usize) c.JSValue {
    return if (index < args.len) args[index] else c.pi_js_undefined();
}
fn exported(engine: *Engine, _: c.JSValue, args: []const c.JSValue, data: []const c.JSValue) !c.JSValue {
    var operation: i32 = undefined;
    if (c.JS_ToInt32(engine.context, &operation, data[1]) < 0) return error.JavaScriptException;
    return exportedOwned(engine, args, operation, data[0]);
}
fn exportedOwned(engine: *Engine, args: []const c.JSValue, operation: c_int, bindings: c.JSValue) anyerror!c.JSValue {
    if (operation == 5) return awaitWithContext(engine, argument(args, 0), argument(args, 1));
    if (operation == 0) return createKey(engine, argument(args, 0));
    const abort_key = try sdk.get(engine, bindings, "abortKey");
    defer engine.freeValue(abort_key);
    if (operation == 1) return objects.create(engine, bindings, "ContextValue", &.{ argument(args, 2), argument(args, 0), argument(args, 1) });
    if (operation == 3) return objects.create(engine, bindings, "ContextValue", &.{ argument(args, 0), abort_key, c.pi_js_undefined() });
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
        try sdk.put(engine, result, "context", try addSignal(engine, bindings, abort_key, signal, argument(args, 0)));
        var data = [_]c.JSValue{controller};
        try sdk.put(engine, result, "cancel", try engine.checked(c.JS_NewCFunctionData2(engine.context, cancel, "cancel", 1, 0, 1, &data)));
        return result;
    }
    return addSignal(engine, bindings, abort_key, argument(args, 0), argument(args, 1));
}
fn addSignal(engine: *Engine, bindings: c.JSValue, abort_key: c.JSValue, signal: c.JSValue, parent: c.JSValue) !c.JSValue {
    const inherited = try sdk.get(engine, parent, "abortSignal");
    defer engine.freeValue(inherited);
    var combined = c.JS_DupValue(engine.context, signal);
    defer engine.freeValue(combined);
    if (!c.JS_IsUndefined(inherited)) {
        const global = c.JS_GetGlobalObject(engine.context);
        defer engine.freeValue(global);
        const constructor = try sdk.get(engine, global, "AbortSignal");
        defer engine.freeValue(constructor);
        const signals = try sdk.array(engine);
        defer engine.freeValue(signals);
        try sdk.append(engine, signals, c.JS_DupValue(engine.context, inherited));
        try sdk.append(engine, signals, c.JS_DupValue(engine.context, signal));
        const value = try sdk.invoke(engine, constructor, "any", &.{signals});
        engine.freeValue(combined);
        combined = value;
    }
    return objects.create(engine, bindings, "ContextValue", &.{ parent, abort_key, combined });
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
    const aborted = try sdk.get(engine, signal, "aborted");
    defer engine.freeValue(aborted);
    var functions: [2]c.JSValue = undefined;
    const waiter = try engine.checked(c.JS_NewPromiseCapability(engine.context, &functions));
    errdefer engine.freeValue(waiter);
    defer for (functions) |function| engine.freeValue(function);
    if (c.JS_ToBool(engine.context, aborted) > 0) {
        const failure = try abortError(engine, signal);
        defer engine.freeValue(failure);
        var values = [_]c.JSValue{failure};
        const result = try engine.checked(c.JS_Call(engine.context, functions[1], c.pi_js_undefined(), 1, &values));
        engine.freeValue(result);
        return waiter;
    }
    // Listener installation and then access run inside Source's Promise
    // executor. Their raw errors reject this waiter, rather than throwing from
    // awaitWithContext or issuing an extra observable removeEventListener call.
    attachWaiter(engine, promise, signal, functions) catch |err| {
        _ = durable.reject(engine, err);
        const failure = c.JS_GetException(engine.context);
        defer engine.freeValue(failure);
        var args = [_]c.JSValue{failure};
        const ignored = try engine.checked(c.JS_Call(engine.context, functions[1], c.pi_js_undefined(), 1, &args));
        engine.freeValue(ignored);
    };
    return waiter;
}
fn attachWaiter(engine: *Engine, promise: c.JSValue, signal: c.JSValue, functions: [2]c.JSValue) !void {
    var abort_data = [_]c.JSValue{ signal, functions[0], functions[1] };
    const on_abort = try engine.checked(c.JS_NewCFunctionData2(engine.context, waitSettled, "onAbort", 0, 2, 3, &abort_data));
    defer engine.freeValue(on_abort);
    const abort = try sdk.text(engine, "abort");
    defer engine.freeValue(abort);
    const options = try sdk.object(engine);
    defer engine.freeValue(options);
    try sdk.put(engine, options, "once", c.pi_js_bool(engine.context, 1));
    const installed = try sdk.invoke(engine, signal, "addEventListener", &.{ abort, on_abort, options });
    engine.freeValue(installed);
    var data = [_]c.JSValue{ signal, functions[0], functions[1], on_abort };
    const fulfilled = try engine.checked(c.JS_NewCFunctionData(engine.context, waitSettled, 1, 0, 4, &data));
    defer engine.freeValue(fulfilled);
    const rejected = try engine.checked(c.JS_NewCFunctionData(engine.context, waitSettled, 1, 1, 4, &data));
    defer engine.freeValue(rejected);
    const result = try sdk.invoke(engine, promise, "then", &.{ fulfilled, rejected });
    engine.freeValue(result);
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
