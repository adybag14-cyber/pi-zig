//! Native cancellation objects. No generated host JavaScript is evaluated.
const std = @import("std");
const engine_mod = @import("engine.zig");
const timers = @import("timers.zig");
const c = engine_mod.c;
const Listener = struct { callback: c.JSValue, once: bool, capture: bool, id: u32, onabort: bool = false };
const State = struct {
    engine: *engine_mod.Engine,
    aborted: bool = false,
    reason: c.JSValue,
    onabort: c.JSValue,
    onabort_id: ?u32 = null,
    listeners: std.ArrayList(Listener) = .empty,
    next_id: u32 = 1,
};
const Controller = struct { engine: *engine_mod.Engine, signal: c.JSValue };
const Method = enum(c_int) { aborted, reason, onabort, set_onabort, add, remove, throwIfAborted };

fn engineForRuntime(runtime: ?*c.JSRuntime) *engine_mod.Engine {
    return @ptrCast(@alignCast(c.JS_GetRuntimeOpaque(runtime)));
}

fn signalFinalizer(runtime: ?*c.JSRuntime, value: c.JSValue) callconv(.c) void {
    const engine = engineForRuntime(runtime);
    const state: *State = @ptrCast(@alignCast(c.JS_GetOpaque(value, engine.abort_signal_class) orelse return));
    for (state.listeners.items) |listener| c.JS_FreeValueRT(runtime, listener.callback);
    state.listeners.deinit(engine.gpa);
    c.JS_FreeValueRT(runtime, state.reason);
    c.JS_FreeValueRT(runtime, state.onabort);
    engine.gpa.destroy(state);
}

fn signalMark(runtime: ?*c.JSRuntime, value: c.JSValue, mark: ?*const c.JS_MarkFunc) callconv(.c) void {
    const engine = engineForRuntime(runtime);
    const state: *State = @ptrCast(@alignCast(c.JS_GetOpaque(value, engine.abort_signal_class) orelse return));
    c.JS_MarkValue(runtime, state.reason, mark);
    c.JS_MarkValue(runtime, state.onabort, mark);
    for (state.listeners.items) |listener| c.JS_MarkValue(runtime, listener.callback, mark);
}

fn controllerFinalizer(runtime: ?*c.JSRuntime, value: c.JSValue) callconv(.c) void {
    const engine = engineForRuntime(runtime);
    const state: *Controller = @ptrCast(@alignCast(c.JS_GetOpaque(value, engine.abort_controller_class) orelse return));
    c.JS_FreeValueRT(runtime, state.signal);
    engine.gpa.destroy(state);
}

fn controllerMark(runtime: ?*c.JSRuntime, value: c.JSValue, mark: ?*const c.JS_MarkFunc) callconv(.c) void {
    const engine = engineForRuntime(runtime);
    const state: *Controller = @ptrCast(@alignCast(c.JS_GetOpaque(value, engine.abort_controller_class) orelse return));
    c.JS_MarkValue(runtime, state.signal, mark);
}

fn stateFor(engine: *engine_mod.Engine, value: c.JSValue) !*State {
    const state: *State = @ptrCast(@alignCast(c.JS_GetOpaque(value, engine.abort_signal_class) orelse return error.IllegalAbortSignalReceiver));
    if (state.engine != engine) return error.IllegalAbortSignalReceiver;
    return state;
}

fn fail(context: ?*c.JSContext, err: anyerror) c.JSValue {
    if (err == error.JavaScriptException) return engine_mod.Engine.fromContext(context.?).throwCaptured();
    if (err == error.OutOfMemory) return c.JS_ThrowOutOfMemory(context);
    return c.JS_ThrowTypeError(context, "Native AbortSignal: %s", @as([*:0]const u8, @errorName(err)));
}

pub fn create(engine: *engine_mod.Engine) !c.JSValue {
    if (engine.abort_signal_class == 0) return error.NativeAbortSignalUnavailable;
    const state = try engine.gpa.create(State);
    errdefer engine.gpa.destroy(state);
    state.* = .{ .engine = engine, .reason = c.pi_js_undefined(), .onabort = c.pi_js_null() };
    const value = try engine.checked(c.JS_NewObjectClass(engine.context, engine.abort_signal_class));
    _ = c.JS_SetOpaque(value, state);
    return value;
}

fn defaultReason(engine: *engine_mod.Engine) !c.JSValue {
    const reason = try engine.checked(c.JS_NewError(engine.context));
    errdefer engine.freeValue(reason);
    if (c.JS_DefinePropertyValueStr(engine.context, reason, "name", c.JS_NewString(engine.context, "AbortError"), c.JS_PROP_C_W_E) < 0 or
        c.JS_DefinePropertyValueStr(engine.context, reason, "message", c.JS_NewString(engine.context, "This operation was aborted"), c.JS_PROP_C_W_E) < 0 or
        c.JS_DefinePropertyValueStr(engine.context, reason, "code", c.JS_NewInt32(engine.context, 20), c.JS_PROP_C_W_E) < 0) return error.JavaScriptException;
    return reason;
}

pub fn abort(engine: *engine_mod.Engine, signal: c.JSValue, reason: c.JSValue) !void {
    const state = try stateFor(engine, signal);
    if (state.aborted) return;
    const owned_reason = if (c.JS_IsUndefined(reason)) try defaultReason(engine) else c.JS_DupValue(engine.context, reason);
    var committed = false;
    defer if (!committed) engine.freeValue(owned_reason);
    var snapshot: std.ArrayList(Listener) = .empty;
    defer {
        for (snapshot.items) |listener| engine.freeValue(listener.callback);
        snapshot.deinit(engine.gpa);
    }
    try snapshot.ensureTotalCapacity(engine.gpa, state.listeners.items.len);
    for (state.listeners.items) |listener| snapshot.appendAssumeCapacity(.{ .callback = c.JS_DupValue(engine.context, listener.callback), .once = listener.once, .capture = listener.capture, .id = listener.id, .onabort = listener.onabort });
    const event = try engine.checked(c.JS_NewObject(engine.context));
    defer engine.freeValue(event);
    if (c.JS_DefinePropertyValueStr(engine.context, event, "type", c.JS_NewString(engine.context, "abort"), c.JS_PROP_ENUMERABLE) < 0 or
        c.JS_DefinePropertyValueStr(engine.context, event, "target", c.JS_DupValue(engine.context, signal), c.JS_PROP_ENUMERABLE) < 0 or
        c.JS_DefinePropertyValueStr(engine.context, event, "currentTarget", c.JS_DupValue(engine.context, signal), c.JS_PROP_ENUMERABLE) < 0) return error.JavaScriptException;
    engine.freeValue(state.reason);
    state.reason = owned_reason;
    state.aborted = true;
    committed = true;
    for (snapshot.items) |listener| {
        var live: ?usize = null;
        for (state.listeners.items, 0..) |candidate, index| if (candidate.id == listener.id) {
            live = index;
            break;
        };
        const index = live orelse continue;
        if (listener.once) engine.freeValue(state.listeners.orderedRemove(index).callback);
        const callback = if (listener.onabort) state.onabort else listener.callback;
        const function = if (c.JS_IsFunction(engine.context, callback)) c.JS_DupValue(engine.context, callback) else c.JS_GetPropertyStr(engine.context, callback, "handleEvent");
        if (c.JS_IsException(function)) {
            try reportListenerError(engine);
            continue;
        }
        defer engine.freeValue(function);
        if (!c.JS_IsFunction(engine.context, function)) continue;
        var args = [_]c.JSValue{event};
        const result = c.JS_Call(engine.context, function, if (c.JS_IsFunction(engine.context, callback)) signal else callback, 1, &args);
        if (c.JS_IsException(result)) try reportListenerError(engine) else engine.freeValue(result);
    }
}

fn reportJob(context: ?*c.JSContext, _: c_int, args: [*c]c.JSValue) callconv(.c) c.JSValue {
    return c.JS_Throw(context, c.JS_DupValue(context, args[0]));
}

fn reportListenerError(engine: *engine_mod.Engine) !void {
    const exception = c.JS_GetException(engine.context);
    if (c.JS_IsUncatchableError(exception)) {
        _ = c.JS_Throw(engine.context, exception);
        return error.JavaScriptException;
    }
    defer engine.freeValue(exception);
    var args = [_]c.JSValue{exception};
    if (c.JS_EnqueueJob(engine.context, reportJob, 1, &args) < 0) return error.JavaScriptException;
}

fn signalCall(context: ?*c.JSContext, this: c.JSValue, argc: c_int, argv: [*c]c.JSValue, magic: c_int) callconv(.c) c.JSValue {
    const args: []c.JSValue = if (argc == 0) &.{} else argv[0..@intCast(argc)];
    return signalMethod(engine_mod.Engine.fromContext(context.?), this, @enumFromInt(magic), args) catch |err| fail(context, err);
}

fn signalMethod(engine: *engine_mod.Engine, this: c.JSValue, method: Method, args: []c.JSValue) !c.JSValue {
    const state = try stateFor(engine, this);
    switch (method) {
        .aborted => return c.pi_js_bool(engine.context, @intFromBool(state.aborted)),
        .reason => return c.JS_DupValue(engine.context, state.reason),
        .onabort => return c.JS_DupValue(engine.context, state.onabort),
        .set_onabort => {
            const value = if (args.len > 0 and c.JS_IsFunction(engine.context, args[0])) args[0] else c.pi_js_null();
            var existing: ?usize = null;
            if (state.onabort_id) |id| for (state.listeners.items, 0..) |listener, index| if (listener.id == id) {
                existing = index;
                break;
            };
            if (c.JS_IsFunction(engine.context, value)) {
                const callback = c.JS_DupValue(engine.context, value);
                if (existing) |index| {
                    engine.freeValue(state.listeners.items[index].callback);
                    state.listeners.items[index].callback = callback;
                } else {
                    errdefer engine.freeValue(callback);
                    if (state.listeners.items.len >= 4096 or state.next_id == std.math.maxInt(u32)) return error.NativeAbortListenerLimit;
                    try state.listeners.append(engine.gpa, .{ .callback = callback, .once = false, .capture = false, .id = state.next_id, .onabort = true });
                    state.onabort_id = state.next_id;
                    state.next_id += 1;
                }
            } else if (existing) |index| {
                engine.freeValue(state.listeners.orderedRemove(index).callback);
                state.onabort_id = null;
            }
            engine.freeValue(state.onabort);
            state.onabort = c.JS_DupValue(engine.context, value);
            return c.pi_js_undefined();
        },
        .throwIfAborted => return if (state.aborted) c.JS_Throw(engine.context, c.JS_DupValue(engine.context, state.reason)) else c.pi_js_undefined(),
        .add, .remove => {
            if (args.len < 2) return error.InvalidAbortListener;
            const kind = try engine.toString(args[0]);
            defer engine.gpa.free(kind);
            if (!std.mem.eql(u8, kind, "abort")) return error.NativeSignalEventUnsupported;
            if (c.JS_IsNull(args[1]) or c.JS_IsUndefined(args[1])) return c.pi_js_undefined();
            if (!c.JS_IsObject(args[1])) return error.InvalidAbortListener;
            var capture = false;
            var once = false;
            if (args.len > 2) {
                if (c.JS_IsBool(args[2])) capture = c.JS_ToBool(engine.context, args[2]) != 0 else if (c.JS_IsObject(args[2])) {
                    const capture_value = try engine.checked(c.JS_GetPropertyStr(engine.context, args[2], "capture"));
                    defer engine.freeValue(capture_value);
                    capture = c.JS_ToBool(engine.context, capture_value) != 0;
                    if (method == .add) {
                        const once_value = try engine.checked(c.JS_GetPropertyStr(engine.context, args[2], "once"));
                        defer engine.freeValue(once_value);
                        once = c.JS_ToBool(engine.context, once_value) != 0;
                    }
                }
            }
            for (state.listeners.items, 0..) |listener, index| if (!listener.onabort and listener.capture == capture and c.JS_IsStrictEqual(engine.context, listener.callback, args[1])) {
                if (method == .remove) engine.freeValue(state.listeners.orderedRemove(index).callback);
                return c.pi_js_undefined();
            };
            if (method == .remove) return c.pi_js_undefined();
            if (state.listeners.items.len >= 4096 or state.next_id == std.math.maxInt(u32)) return error.NativeAbortListenerLimit;
            const callback = c.JS_DupValue(engine.context, args[1]);
            errdefer engine.freeValue(callback);
            try state.listeners.append(engine.gpa, .{ .callback = callback, .once = once, .capture = capture, .id = state.next_id });
            state.next_id += 1;
            return c.pi_js_undefined();
        },
    }
}

fn illegalSignal(context: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue) callconv(.c) c.JSValue {
    return c.JS_ThrowTypeError(context, "Illegal AbortSignal constructor");
}

fn controllerConstructor(context: ?*c.JSContext, new_target: c.JSValue, _: c_int, _: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = engine_mod.Engine.fromContext(context.?);
    return constructController(engine, new_target) catch |err| fail(context, err);
}

fn constructController(engine: *engine_mod.Engine, new_target: c.JSValue) !c.JSValue {
    const signal = try create(engine);
    errdefer engine.freeValue(signal);
    const state = try engine.gpa.create(Controller);
    errdefer engine.gpa.destroy(state);
    const prototype = try engine.checked(c.JS_GetPropertyStr(engine.context, new_target, "prototype"));
    defer engine.freeValue(prototype);
    const object = try engine.checked(c.JS_NewObjectProtoClass(engine.context, prototype, engine.abort_controller_class));
    state.* = .{ .engine = engine, .signal = signal };
    _ = c.JS_SetOpaque(object, state);
    return object;
}

fn controllerCall(context: ?*c.JSContext, this: c.JSValue, argc: c_int, argv: [*c]c.JSValue, magic: c_int) callconv(.c) c.JSValue {
    const engine = engine_mod.Engine.fromContext(context.?);
    const state: *Controller = @ptrCast(@alignCast(c.JS_GetOpaque(this, engine.abort_controller_class) orelse return c.JS_ThrowTypeError(context, "Illegal AbortController receiver")));
    if (state.engine != engine) return c.JS_ThrowTypeError(context, "Illegal AbortController receiver");
    if (magic == 0) return c.JS_DupValue(engine.context, state.signal);
    abort(engine, state.signal, if (argc > 0) argv[0] else c.pi_js_undefined()) catch |err| return fail(context, err);
    return c.pi_js_undefined();
}

fn staticAbort(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = engine_mod.Engine.fromContext(context.?);
    const signal = create(engine) catch |err| return fail(context, err);
    abort(engine, signal, if (argc > 0) argv[0] else c.pi_js_undefined()) catch |err| {
        engine.freeValue(signal);
        return fail(context, err);
    };
    return signal;
}

fn timeoutFire(context: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue, _: c_int, data: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = engine_mod.Engine.fromContext(context.?);
    const reason = c.JS_NewError(context);
    if (c.JS_IsException(reason)) return reason;
    defer engine.freeValue(reason);
    if (c.JS_DefinePropertyValueStr(context, reason, "name", c.JS_NewString(context, "TimeoutError"), c.JS_PROP_C_W_E) < 0 or
        c.JS_DefinePropertyValueStr(context, reason, "message", c.JS_NewString(context, "The operation was aborted due to timeout"), c.JS_PROP_C_W_E) < 0 or
        c.JS_DefinePropertyValueStr(context, reason, "code", c.JS_NewInt32(context, 23), c.JS_PROP_C_W_E) < 0) return c.JS_Throw(context, c.JS_GetException(context));
    abort(engine, data[0], reason) catch |err| return fail(context, err);
    return c.pi_js_undefined();
}

fn staticTimeout(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = engine_mod.Engine.fromContext(context.?);
    return timeoutSignal(engine, if (argc > 0) argv[0] else c.pi_js_undefined()) catch |err| fail(context, err);
}

fn timeoutSignal(engine: *engine_mod.Engine, value: c.JSValue) !c.JSValue {
    if (!c.JS_IsNumber(value)) return error.InvalidSignalTimeout;
    var delay: f64 = 0;
    if (c.JS_ToFloat64(engine.context, &delay, value) < 0) return error.JavaScriptException;
    if (!std.math.isFinite(delay) or delay < 0 or delay != @trunc(delay) or delay > std.math.maxInt(u32)) return error.InvalidSignalTimeout;
    const signal = try create(engine);
    errdefer engine.freeValue(signal);
    var data = [_]c.JSValue{signal};
    const callback = try engine.checked(c.JS_NewCFunctionData2(engine.context, timeoutFire, "abort timeout", 0, 0, 1, &data));
    defer engine.freeValue(callback);
    const id = try timers.scheduleOnce(engine, callback, @intFromFloat(delay));
    engine.freeValue(id);
    return signal;
}

fn forwardAbort(context: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue, _: c_int, data: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = engine_mod.Engine.fromContext(context.?);
    const source = stateFor(engine, data[0]) catch |err| return fail(context, err);
    abort(engine, data[1], source.reason) catch |err| return fail(context, err);
    return c.pi_js_undefined();
}

fn staticAny(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = engine_mod.Engine.fromContext(context.?);
    return anySignal(engine, if (argc > 0) argv[0] else c.pi_js_undefined()) catch |err| fail(context, err);
}

fn anySignal(engine: *engine_mod.Engine, values: c.JSValue) !c.JSValue {
    if (!c.JS_IsArray(values)) return error.InvalidSignalList;
    const length = try engine.checked(c.JS_GetPropertyStr(engine.context, values, "length"));
    defer engine.freeValue(length);
    var count: u32 = 0;
    if (c.JS_ToUint32(engine.context, &count, length) < 0) return error.JavaScriptException;
    if (count > 4096) return error.NativeAbortListenerLimit;
    // Validate all sources before adding callbacks to any of them.
    const storage = try engine.gpa.alloc(c.JSValue, count);
    defer engine.gpa.free(storage);
    var initialized: usize = 0;
    defer for (storage[0..initialized]) |source| engine.freeValue(source);
    for (0..count) |index| {
        const source = try engine.checked(c.JS_GetPropertyUint32(engine.context, values, @intCast(index)));
        _ = stateFor(engine, source) catch |err| {
            engine.freeValue(source);
            return err;
        };
        var duplicate = false;
        for (storage[0..initialized]) |previous| if (c.JS_IsStrictEqual(engine.context, source, previous)) {
            duplicate = true;
            break;
        };
        if (duplicate) {
            engine.freeValue(source);
            continue;
        }
        storage[initialized] = source;
        initialized += 1;
    }
    const sources = storage[0..initialized];
    const combined = try create(engine);
    errdefer engine.freeValue(combined);
    for (sources) |source| {
        const state = try stateFor(engine, source);
        if (state.aborted) {
            try abort(engine, combined, state.reason);
            return combined;
        }
    }
    // Reserve all storage before attaching callbacks, so allocator failures do
    // not leave half the source set connected to an unpublished signal.
    for (sources) |source| {
        const state = try stateFor(engine, source);
        if (state.listeners.items.len >= 4096 or state.next_id == std.math.maxInt(u32)) return error.NativeAbortListenerLimit;
        try state.listeners.ensureUnusedCapacity(engine.gpa, 1);
    }
    const callbacks = try engine.gpa.alloc(c.JSValue, sources.len);
    defer engine.gpa.free(callbacks);
    var ready: usize = 0;
    defer for (callbacks[0..ready]) |callback| engine.freeValue(callback);
    for (sources, callbacks) |source, *callback| {
        var data = [_]c.JSValue{ source, combined };
        callback.* = try engine.checked(c.JS_NewCFunctionData2(engine.context, forwardAbort, "combined abort", 1, 0, data.len, &data));
        ready += 1;
    }
    for (sources, callbacks) |source, callback| {
        const state = try stateFor(engine, source);
        state.listeners.appendAssumeCapacity(.{ .callback = c.JS_DupValue(engine.context, callback), .once = true, .capture = false, .id = state.next_id });
        state.next_id += 1;
    }
    return combined;
}

fn accessor(engine: *engine_mod.Engine, prototype: c.JSValue, name: [:0]const u8, getter: c.JSCFunctionMagic, get_magic: c_int, setter: ?c.JSCFunctionMagic, set_magic: c_int) !void {
    const atom = c.JS_NewAtom(engine.context, name.ptr);
    defer c.JS_FreeAtom(engine.context, atom);
    const read = try engine.checked(c.pi_js_function_magic(engine.context, getter, name.ptr, 0, get_magic));
    defer engine.freeValue(read);
    const write = if (setter) |callback| try engine.checked(c.pi_js_function_magic(engine.context, callback, name.ptr, 1, set_magic)) else c.pi_js_undefined();
    defer engine.freeValue(write);
    if (c.JS_DefinePropertyGetSet(engine.context, prototype, atom, c.JS_DupValue(engine.context, read), c.JS_DupValue(engine.context, write), c.JS_PROP_CONFIGURABLE | c.JS_PROP_ENUMERABLE) < 0) return error.JavaScriptException;
}

pub fn install(engine: *engine_mod.Engine) !void {
    if (engine.abort_signal_class != 0) return error.NativeAbortSignalAlreadyInstalled;
    _ = c.JS_NewClassID(engine.runtime, &engine.abort_signal_class);
    _ = c.JS_NewClassID(engine.runtime, &engine.abort_controller_class);
    const signal_class: c.JSClassDef = .{ .class_name = "AbortSignal", .finalizer = signalFinalizer, .gc_mark = signalMark, .call = null, .exotic = null };
    const controller_class: c.JSClassDef = .{ .class_name = "AbortController", .finalizer = controllerFinalizer, .gc_mark = controllerMark, .call = null, .exotic = null };
    if (c.JS_NewClass(engine.runtime, engine.abort_signal_class, &signal_class) < 0 or c.JS_NewClass(engine.runtime, engine.abort_controller_class, &controller_class) < 0) return error.NativeAbortClassFailed;
    const prototype = try engine.checked(c.JS_NewObject(engine.context));
    defer engine.freeValue(prototype);
    const constructor = try engine.checked(c.JS_NewCFunction2(engine.context, illegalSignal, "AbortSignal", 0, c.JS_CFUNC_constructor, 0));
    defer engine.freeValue(constructor);
    if (c.JS_SetConstructor(engine.context, constructor, prototype) < 0) return error.JavaScriptException;
    c.JS_SetClassProto(engine.context, engine.abort_signal_class, c.JS_DupValue(engine.context, prototype));
    try accessor(engine, prototype, "aborted", signalCall, @intFromEnum(Method.aborted), null, 0);
    try accessor(engine, prototype, "reason", signalCall, @intFromEnum(Method.reason), null, 0);
    try accessor(engine, prototype, "onabort", signalCall, @intFromEnum(Method.onabort), signalCall, @intFromEnum(Method.set_onabort));
    inline for (.{ .{ "addEventListener", Method.add }, .{ "removeEventListener", Method.remove }, .{ "throwIfAborted", Method.throwIfAborted } }) |entry| {
        if (c.JS_DefinePropertyValueStr(engine.context, prototype, entry[0], c.pi_js_function_magic(engine.context, signalCall, entry[0], 2, @intFromEnum(entry[1])), c.JS_PROP_C_W_E) < 0) return error.JavaScriptException;
    }
    if (c.JS_DefinePropertyValueStr(engine.context, constructor, "abort", c.JS_NewCFunction(engine.context, staticAbort, "abort", 0), c.JS_PROP_C_W_E) < 0) return error.JavaScriptException;
    if (c.JS_DefinePropertyValueStr(engine.context, constructor, "timeout", c.JS_NewCFunction(engine.context, staticTimeout, "timeout", 1), c.JS_PROP_C_W_E) < 0) return error.JavaScriptException;
    if (c.JS_DefinePropertyValueStr(engine.context, constructor, "any", c.JS_NewCFunction(engine.context, staticAny, "any", 1), c.JS_PROP_C_W_E) < 0) return error.JavaScriptException;
    const controller_prototype = try engine.checked(c.JS_NewObject(engine.context));
    defer engine.freeValue(controller_prototype);
    const controller_constructor = try engine.checked(c.JS_NewCFunction2(engine.context, controllerConstructor, "AbortController", 0, c.JS_CFUNC_constructor, 0));
    defer engine.freeValue(controller_constructor);
    if (c.JS_SetConstructor(engine.context, controller_constructor, controller_prototype) < 0) return error.JavaScriptException;
    c.JS_SetClassProto(engine.context, engine.abort_controller_class, c.JS_DupValue(engine.context, controller_prototype));
    try accessor(engine, controller_prototype, "signal", controllerCall, 0, null, 0);
    if (c.JS_DefinePropertyValueStr(engine.context, controller_prototype, "abort", c.pi_js_function_magic(engine.context, controllerCall, "abort", 0, 1), c.JS_PROP_C_W_E) < 0) return error.JavaScriptException;
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    if (c.JS_DefinePropertyValueStr(engine.context, global, "AbortSignal", c.JS_DupValue(engine.context, constructor), c.JS_PROP_C_W_E) < 0 or
        c.JS_DefinePropertyValueStr(engine.context, global, "AbortController", c.JS_DupValue(engine.context, controller_constructor), c.JS_PROP_C_W_E) < 0) return error.JavaScriptException;
    engine.abort_signals_ready = true;
}

test "native AbortController signals retain reasons listeners and native brands" {
    const engine = try engine_mod.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    try install(engine);
    const value = try engine.evalModule(
        "const controller=new AbortController(),signal=controller.signal;if(!(controller instanceof AbortController)||!(signal instanceof AbortSignal)||signal!==controller.signal||signal.aborted||signal.reason!==undefined)throw Error('brands');const original={reason:'owned'}, calls=[];function second(){calls.push('removed')};function first(event){if(this!==signal||event.type!=='abort'||event.target!==signal||event.currentTarget!==signal)throw Error('event');calls.push('first');signal.removeEventListener('abort',second)};signal.addEventListener('abort',first,{once:true});signal.addEventListener('abort',first);signal.addEventListener('abort',second);const object={handleEvent(event){if(this!==object||event.target!==signal)throw Error('object receiver');calls.push('object')}};signal.addEventListener('abort',object);signal.onabort=()=>calls.push('onabort');controller.abort(original);controller.abort('ignored');if(!signal.aborted||signal.reason!==original||calls.join(',')!=='first,object,onabort')throw Error('delivery');let caught=false;try{signal.throwIfAborted()}catch(error){if(error!==original)throw Error('reason replaced');caught=true}if(!caught)throw Error('missing throw');const late=()=>{throw Error('late listener')};signal.addEventListener('abort',late);if(AbortSignal.abort().reason.name!=='AbortError'||AbortSignal.abort().reason.code!==20)throw Error('default reason');let branded=false;try{AbortSignal.prototype.throwIfAborted.call({})}catch(error){branded=error instanceof TypeError}if(!branded)throw Error('illegal receiver');let illegal=false;try{new AbortSignal()}catch(error){illegal=error instanceof TypeError}if(!illegal)throw Error('illegal constructor');",
        "native-abort-signal.mjs",
    );
    defer engine.freeValue(value);
}

test "native signal garbage collection marks listener cycles and releases host allocations" {
    const engine = try engine_mod.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    try install(engine);
    const value = try engine.evalModule("for(let i=0;i<50;i++){const controller=new AbortController();const signal=controller.signal;signal.addEventListener('abort',()=>signal.reason);signal.onabort=()=>controller.signal;}", "native-abort-gc.mjs");
    defer engine.freeValue(value);
    c.JS_RunGC(engine.runtime);
}

test "native onabort assignment retains event position and removal ignores once getters" {
    const engine = try engine_mod.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    try install(engine);
    const value = try engine.evalModule("const controller=new AbortController(),s=controller.signal,calls=[];s.onabort=()=>calls.push('old');const cb=()=>calls.push('listener');s.addEventListener('abort',cb);s.onabort=()=>calls.push('updated');s.removeEventListener('abort',()=>{}, {get capture(){return false},get once(){throw Error('once getter read')}});controller.abort();if(calls.join(',')!=='updated,listener')throw Error('onabort position');const second=new AbortController();second.signal.onabort=cb;second.signal.onabort=null;second.abort();if(calls.length!==2)throw Error('onabort clear');", "native-onabort-order.mjs");
    defer engine.freeValue(value);
}

test "native timed signals settle a real listener promise with timeout reasons" {
    const engine = try engine_mod.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    try install(engine);
    try timers.install(engine, std.testing.io);
    const value = try engine.evalModule("const signal=AbortSignal.timeout(2);if(!(signal instanceof AbortSignal)||signal.aborted)throw Error('timed brand');await new Promise(resolve=>signal.addEventListener('abort',resolve,{once:true}));if(!signal.aborted||signal.reason.name!=='TimeoutError'||signal.reason.code!==23)throw Error('timed reason');", "native-timeout-signal.mjs");
    defer engine.freeValue(value);
}

test "native abort listener errors are reported after other listeners and abort returns" {
    const engine = try engine_mod.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    try install(engine);
    try std.testing.expectError(error.JavaScriptException, engine.evalModule("globalThis.order=[];const controller=new AbortController();controller.signal.addEventListener('abort',()=>{order.push('throw');throw Error('reported listener')});controller.signal.addEventListener('abort',()=>order.push('after'));controller.abort();order.push('returned');", "native-abort-report.mjs"));
    try std.testing.expect(std.mem.indexOf(u8, engine.last_error.?, "reported listener") != null);
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    const order = try engine.checked(c.JS_GetPropertyStr(engine.context, global, "order"));
    defer engine.freeValue(order);
    const encoded = try engine.stringify(order);
    defer engine.gpa.free(encoded);
    try std.testing.expectEqualStrings("[\"throw\",\"after\",\"returned\"]", encoded);
}

test "native signal composition retains the first reason and validates all sources" {
    const engine = try engine_mod.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    try install(engine);
    const value = try engine.evalModule("const a=new AbortController(),b=new AbortController(),combined=AbortSignal.any([a.signal,b.signal]);const reason={winner:1};let count=0;combined.addEventListener('abort',()=>count++);b.abort(reason);a.abort('later');if(!combined.aborted||combined.reason!==reason||count!==1)throw Error('composition');const immediate=AbortSignal.any([AbortSignal.abort(reason),a.signal]);if(immediate.reason!==reason)throw Error('first pre-aborted');if(AbortSignal.any([]).aborted)throw Error('empty set');let invalid=false;try{AbortSignal.any([a.signal,{}])}catch(error){invalid=error instanceof TypeError}if(!invalid)throw Error('source validation');", "native-signal-any.mjs");
    defer engine.freeValue(value);
}

test "native composed signals deduplicate repeated source objects" {
    const engine = try engine_mod.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    try install(engine);
    const value = try engine.evalModule("const controller=new AbortController();const combined=AbortSignal.any(new Array(100).fill(controller.signal));let calls=0;combined.addEventListener('abort',()=>calls++);controller.abort('one');if(calls!==1||combined.reason!=='one')throw Error('duplicate sources');", "native-signal-duplicates.mjs");
    defer engine.freeValue(value);
}

fn allocationListener(context: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue) callconv(.c) c.JSValue {
    _ = context;
    return c.pi_js_undefined();
}

fn signalAllocationProbe(gpa: std.mem.Allocator) !void {
    const engine = try engine_mod.Engine.init(gpa, .{});
    defer engine.deinit();
    try install(engine);
    const signal = try create(engine);
    defer engine.freeValue(signal);
    const state = try stateFor(engine, signal);
    const callback = try engine.checked(c.JS_NewCFunction(engine.context, allocationListener, "allocation listener", 1));
    var transferred = false;
    defer if (!transferred) engine.freeValue(callback);
    try state.listeners.append(gpa, .{ .callback = callback, .once = true, .capture = false, .id = 1 });
    transferred = true;
    try abort(engine, signal, c.pi_js_undefined());
    try std.testing.expect(state.aborted and state.listeners.items.len == 0);
}

test "native abort ownership releases every allocator failure without losing listener values" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, signalAllocationProbe, .{});
}
