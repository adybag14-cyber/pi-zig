//! Native timer callbacks pumped while a promise is awaiting host work.
const std = @import("std");
const engine_mod = @import("engine.zig");
const c = engine_mod.c;
const Timer = struct {
    id: u32,
    deadline_ms: i64,
    handle: c.JSValue,
};
// The handle, rather than the pending queue entry, owns the callback. A fired
// timeout can therefore be refreshed while an unreachable handle and callback
// cycle can still be collected by QuickJS.
const HandleState = struct {
    gpa: std.mem.Allocator,
    id: u32,
    interval_ms: ?i64,
    delay_ms: i64,
    callback: c.JSValue,
    arguments: []c.JSValue,
    async_scope: c.JSValue,
    refed: bool = true,
    cancelled: bool = false,
};

fn handleState(value: c.JSValue) *HandleState {
    return @ptrCast(@alignCast(c.JS_GetOpaque(value, c.JS_GetClassID(value)).?));
}

fn handleFinalizer(runtime: ?*c.JSRuntime, value: c.JSValue) callconv(.c) void {
    const retained = handleState(value);
    c.JS_FreeValueRT(runtime, retained.callback);
    c.JS_FreeValueRT(runtime, retained.async_scope);
    for (retained.arguments) |argument| c.JS_FreeValueRT(runtime, argument);
    retained.gpa.free(retained.arguments);
    retained.gpa.destroy(retained);
}

fn handleMark(runtime: ?*c.JSRuntime, value: c.JSValue, mark: ?*const c.JS_MarkFunc) callconv(.c) void {
    const retained = handleState(value);
    c.JS_MarkValue(runtime, retained.callback, mark);
    c.JS_MarkValue(runtime, retained.async_scope, mark);
    for (retained.arguments) |argument| c.JS_MarkValue(runtime, argument, mark);
}
const Scheduler = struct {
    engine: *engine_mod.Engine,
    io: std.Io,
    next_id: u32 = 1,
    primitive_atom: c.JSAtom = c.JS_ATOM_NULL,
    handle_class: c.JSClassID = 0,
    timers: std.ArrayList(Timer) = .empty,
    fn freeTimer(self: *Scheduler, timer: Timer) void {
        self.engine.freeValue(timer.handle);
    }
};

fn scheduler(engine: *engine_mod.Engine) !*Scheduler {
    return @ptrCast(@alignCast(engine.host_scheduler orelse return error.NativeTimersUnavailable));
}

fn cleanup(engine: *engine_mod.Engine) void {
    const state = scheduler(engine) catch return;
    for (state.timers.items) |timer| state.freeTimer(timer);
    state.timers.deinit(engine.gpa);
    c.JS_FreeAtom(engine.context, state.primitive_atom);
    engine.gpa.destroy(state);
    engine.host_scheduler = null;
    engine.host_pump = null;
    engine.host_scheduler_deinit = null;
}

fn failure(context: ?*c.JSContext, err: anyerror) c.JSValue {
    if (err == error.JavaScriptException) return engine_mod.Engine.fromContext(context.?).throwCaptured();
    if (err == error.OutOfMemory) return c.JS_ThrowOutOfMemory(context);
    return c.JS_ThrowTypeError(context, "Native timer: %s", @as([*:0]const u8, @errorName(err)));
}

fn scheduleCall(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, magic: c_int) callconv(.c) c.JSValue {
    const args: []c.JSValue = if (argc == 0) &.{} else argv[0..@intCast(argc)];
    return schedule(engine_mod.Engine.fromContext(context.?), args, magic == 1) catch |err| failure(context, err);
}

fn schedule(engine: *engine_mod.Engine, args: []c.JSValue, repeat: bool) !c.JSValue {
    const state = try scheduler(engine);
    if (args.len == 0 or !c.JS_IsFunction(engine.context, args[0])) return error.InvalidTimerCallback;
    var raw_delay: f64 = 0;
    if (args.len > 1 and c.JS_ToFloat64(engine.context, &raw_delay, args[1]) < 0) return error.JavaScriptException;
    const delay: i64 = if (!std.math.isFinite(raw_delay) or raw_delay < 1 or raw_delay > std.math.maxInt(i32)) 1 else @intFromFloat(@trunc(raw_delay));
    if (state.timers.items.len >= 4096 or state.next_id == std.math.maxInt(u32)) return error.NativeTimerLimit;
    const handle = try createHandle(engine, state.next_id, delay, repeat, args);
    defer engine.freeValue(handle);
    const timer: Timer = .{
        .id = state.next_id,
        .deadline_ms = std.Io.Clock.awake.now(state.io).toMilliseconds() + delay,
        .handle = c.JS_DupValue(engine.context, handle),
    };
    errdefer engine.freeValue(timer.handle);
    try state.timers.append(engine.gpa, timer);
    state.next_id += 1;
    return c.JS_DupValue(engine.context, handle);
}

fn handleCall(context: ?*c.JSContext, this: c.JSValue, _: c_int, _: [*c]c.JSValue, magic: c_int, data: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = engine_mod.Engine.fromContext(context.?);
    var class_id: u32 = 0;
    if (c.JS_ToUint32(context, &class_id, data[0]) < 0) return engine.throwCaptured();
    const retained: *HandleState = @ptrCast(@alignCast(c.JS_GetOpaque(this, class_id) orelse return c.JS_ThrowTypeError(context, "Illegal timer handle receiver")));
    if (magic == 0) return c.JS_NewInt64(context, retained.id);
    const state = scheduler(engine) catch |err| return failure(context, err);
    if (magic == 3) return c.pi_js_bool(context, @intFromBool(retained.refed));
    if (magic == 1 or magic == 2) {
        retained.refed = magic == 1;
    } else if (magic == 4 or magic == 5) {
        if (magic == 5) retained.cancelled = true;
        for (state.timers.items, 0..) |*timer, index| if (timer.id == retained.id) {
            if (magic == 4) timer.deadline_ms = std.Io.Clock.awake.now(state.io).toMilliseconds() + retained.delay_ms else state.freeTimer(state.timers.orderedRemove(index));
            return c.JS_DupValue(context, this);
        };
        if (magic == 4 and !retained.cancelled) {
            refreshExpired(engine, this) catch |err| return failure(context, err);
        }
    }
    return c.JS_DupValue(context, this);
}

fn refreshExpired(engine: *engine_mod.Engine, handle: c.JSValue) !void {
    const state = try scheduler(engine);
    const retained = handleState(handle);
    if (state.timers.items.len >= 4096 or state.next_id == std.math.maxInt(u32)) return error.NativeTimerLimit;
    const timer: Timer = .{
        .id = state.next_id,
        .deadline_ms = std.Io.Clock.awake.now(state.io).toMilliseconds() + retained.delay_ms,
        .handle = c.JS_DupValue(engine.context, handle),
    };
    errdefer state.freeTimer(timer);
    try state.timers.append(engine.gpa, timer);
    // Publish the new primitive ID only after queue allocation succeeds.
    retained.id = state.next_id;
    state.next_id += 1;
}

fn createHandle(engine: *engine_mod.Engine, id: u32, delay: i64, repeat: bool, args: []c.JSValue) !c.JSValue {
    const state = try scheduler(engine);
    const retained = try engine.gpa.create(HandleState);
    const arguments = engine.gpa.alloc(c.JSValue, if (args.len > 2) args.len - 2 else 0) catch |err| {
        engine.gpa.destroy(retained);
        return err;
    };
    for (arguments, 0..) |*argument, index| argument.* = c.JS_DupValue(engine.context, args[index + 2]);
    retained.* = .{ .gpa = engine.gpa, .id = id, .delay_ms = delay, .interval_ms = if (repeat) delay else null, .callback = c.JS_DupValue(engine.context, args[0]), .arguments = arguments, .async_scope = @import("native_async_scope.zig").capture(engine) };
    const object = engine.checked(c.JS_NewObjectClass(engine.context, state.handle_class)) catch |err| {
        engine.freeValue(retained.callback);
        engine.freeValue(retained.async_scope);
        for (arguments) |argument| engine.freeValue(argument);
        engine.gpa.free(arguments);
        engine.gpa.destroy(retained);
        return err;
    };
    _ = c.JS_SetOpaque(object, retained);
    errdefer engine.freeValue(object);
    // Method closures carry only the immutable native brand, never their own
    // handle. Capturing object here creates seven handle/method self-cycles,
    // delaying release of callback state until runtime cycle collection after
    // scheduler/context teardown. Brand the supplied receiver instead, as Node
    // does, so an unreachable timer releases its native ownership immediately.
    var data = [_]c.JSValue{c.JS_NewInt64(engine.context, state.handle_class)};
    defer engine.freeValue(data[0]);
    inline for (.{ .{ "valueOf", 0 }, .{ "ref", 1 }, .{ "unref", 2 }, .{ "hasRef", 3 }, .{ "refresh", 4 }, .{ "close", 5 } }) |entry| {
        const function = try engine.checked(c.JS_NewCFunctionData2(engine.context, handleCall, entry[0], 0, entry[1], data.len, &data));
        if (c.JS_DefinePropertyValueStr(engine.context, object, entry[0], function, c.JS_PROP_C_W_E) < 0) return error.JavaScriptException;
    }
    const primitive = try engine.checked(c.JS_NewCFunctionData2(engine.context, handleCall, "timer id", 1, 0, data.len, &data));
    if (c.JS_DefinePropertyValue(engine.context, object, state.primitive_atom, primitive, c.JS_PROP_C_W_E) < 0) return error.JavaScriptException;
    return object;
}

pub fn scheduleOnce(engine: *engine_mod.Engine, callback: c.JSValue, delay_ms: u32) !c.JSValue {
    var args = [_]c.JSValue{ callback, c.JS_NewInt64(engine.context, delay_ms) };
    defer engine.freeValue(args[1]);
    return schedule(engine, &args, false);
}

fn clearCall(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = engine_mod.Engine.fromContext(context.?);
    const state = scheduler(engine) catch |err| return failure(context, err);
    if (argc == 0) return c.pi_js_undefined();
    var id: u32 = 0;
    if (c.JS_GetOpaque(argv[0], state.handle_class)) |pointer| {
        const retained: *HandleState = @ptrCast(@alignCast(pointer));
        id = retained.id;
        retained.cancelled = true;
    } else if (c.JS_IsNumber(argv[0])) {
        var number: f64 = 0;
        if (c.JS_ToFloat64(context, &number, argv[0]) < 0) return engine.throwCaptured();
        if (!std.math.isFinite(number) or number < 1 or number > std.math.maxInt(u32) or number != @trunc(number)) return c.pi_js_undefined();
        id = @intFromFloat(number);
    } else if (c.JS_IsString(argv[0])) {
        var length: usize = 0;
        const encoded = c.JS_ToCStringLen(context, &length, argv[0]) orelse return engine.throwCaptured();
        defer c.JS_FreeCString(context, encoded);
        const text = encoded[0..length];
        // Node looks up the exact decimal ID string, without numeric coercion.
        // Leading zeros, whitespace, signs and fractional spellings do not
        // identify the same timer, and oversized numbers must not wrap around.
        if (text.len == 0 or text[0] == '0') return c.pi_js_undefined();
        for (text) |byte| if (byte < '0' or byte > '9') return c.pi_js_undefined();
        id = std.fmt.parseInt(u32, text, 10) catch return c.pi_js_undefined();
    } else {
        // Symbols, BigInts and arbitrary objects are harmless no-ops; in
        // particular, never invoke their user-controlled coercion methods.
        return c.pi_js_undefined();
    }
    for (state.timers.items, 0..) |timer, index| if (timer.id == id) {
        handleState(timer.handle).cancelled = true;
        state.freeTimer(state.timers.orderedRemove(index));
        break;
    };
    return c.pi_js_undefined();
}

fn microtaskJob(context: ?*c.JSContext, _: c_int, argv: [*c]c.JSValue) callconv(.c) c.JSValue {
    return c.JS_Call(context, argv[0], c.pi_js_undefined(), 0, null);
}

fn queueMicrotask(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue) callconv(.c) c.JSValue {
    if (argc == 0 or !c.JS_IsFunction(context, argv[0])) return c.JS_ThrowTypeError(context, "queueMicrotask requires a function");
    var args = [_]c.JSValue{argv[0]};
    if (c.JS_EnqueueJob(context, microtaskJob, 1, &args) < 0) return c.JS_Throw(context, c.JS_GetException(context));
    return c.pi_js_undefined();
}

fn promiseCallback(context: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue, magic: c_int, data: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = engine_mod.Engine.fromContext(context.?);
    const record = data[0];
    const signal = c.JS_GetPropertyStr(context, record, "signal");
    if (c.JS_IsException(signal)) return signal;
    defer engine.freeValue(signal);
    if (magic == 1) {
        const handle = c.JS_GetPropertyStr(context, record, "handle");
        if (c.JS_IsException(handle)) return handle;
        defer engine.freeValue(handle);
        var args = [_]c.JSValue{handle};
        const cleared = clearCall(context, c.pi_js_undefined(), 1, &args);
        if (c.JS_IsException(cleared)) return cleared;
        engine.freeValue(cleared);
    } else if (!c.JS_IsUndefined(signal)) {
        const listener = c.JS_GetPropertyStr(context, record, "listener");
        if (c.JS_IsException(listener)) return listener;
        defer engine.freeValue(listener);
        const remove = c.JS_GetPropertyStr(context, signal, "removeEventListener");
        if (c.JS_IsException(remove)) return remove;
        defer engine.freeValue(remove);
        var args = [_]c.JSValue{ c.JS_NewString(context, "abort"), listener };
        defer engine.freeValue(args[0]);
        const removed = c.JS_Call(context, remove, signal, args.len, &args);
        if (c.JS_IsException(removed)) return removed;
        engine.freeValue(removed);
    }
    const settle = c.JS_GetPropertyStr(context, record, if (magic == 1) "reject" else "resolve");
    if (c.JS_IsException(settle)) return settle;
    defer engine.freeValue(settle);
    const value = if (magic == 1) abortedPromiseError(engine, signal) catch |err| return failure(context, err) else c.JS_GetPropertyStr(context, record, "value");
    if (c.JS_IsException(value)) return value;
    defer engine.freeValue(value);
    var args = [_]c.JSValue{value};
    return c.JS_Call(context, settle, c.pi_js_undefined(), 1, &args);
}

fn abortedPromiseError(engine: *engine_mod.Engine, signal: c.JSValue) !c.JSValue {
    const error_value = try engine.checked(c.JS_NewError(engine.context));
    errdefer engine.freeValue(error_value);
    const reason = try engine.checked(c.JS_GetPropertyStr(engine.context, signal, "reason"));
    if (c.JS_DefinePropertyValueStr(engine.context, error_value, "cause", reason, c.JS_PROP_C_W_E) < 0 or
        c.JS_DefinePropertyValueStr(engine.context, error_value, "name", c.JS_NewString(engine.context, "AbortError"), c.JS_PROP_C_W_E) < 0 or
        c.JS_DefinePropertyValueStr(engine.context, error_value, "code", c.JS_NewString(engine.context, "ABORT_ERR"), c.JS_PROP_C_W_E) < 0) return error.JavaScriptException;
    return error_value;
}

fn promiseTimeout(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue) callconv(.c) c.JSValue {
    const args: []c.JSValue = if (argc == 0) &.{} else argv[0..@intCast(argc)];
    return schedulePromise(engine_mod.Engine.fromContext(context.?), args) catch |err| failure(context, err);
}

fn recordProperty(engine: *engine_mod.Engine, record: c.JSValue, key: [*:0]const u8, value: c.JSValue) !void {
    if (c.JS_DefinePropertyValueStr(engine.context, record, key, value, c.JS_PROP_C_W_E) < 0) return error.JavaScriptException;
}

fn schedulePromise(engine: *engine_mod.Engine, args: []c.JSValue) !c.JSValue {
    var capabilities: [2]c.JSValue = undefined;
    const promise = try engine.checked(c.JS_NewPromiseCapability(engine.context, &capabilities));
    errdefer engine.freeValue(promise);
    defer engine.freeValue(capabilities[0]);
    defer engine.freeValue(capabilities[1]);
    if (args.len > 0 and !c.JS_IsUndefined(args[0]) and !c.JS_IsNumber(args[0])) {
        // Unlike callback timers, timers/promises requires a primitive number.
        // Its validation failure rejects the returned promise before options
        // getters are consulted; it must not throw or coerce the delay object.
        _ = c.JS_ThrowTypeError(engine.context, "The \"delay\" argument must be of type number");
        const reason = c.JS_GetException(engine.context);
        defer engine.freeValue(reason);
        try recordProperty(engine, reason, "code", try engine.checked(c.JS_NewString(engine.context, "ERR_INVALID_ARG_TYPE")));
        var rejected_args = [_]c.JSValue{reason};
        const rejected = try engine.checked(c.JS_Call(engine.context, capabilities[1], c.pi_js_undefined(), 1, &rejected_args));
        engine.freeValue(rejected);
        return promise;
    }
    const signal = if (args.len > 2 and c.JS_IsObject(args[2])) try engine.checked(c.JS_GetPropertyStr(engine.context, args[2], "signal")) else c.pi_js_undefined();
    defer engine.freeValue(signal);
    if (!c.JS_IsUndefined(signal) and (engine.abort_signal_class == 0 or c.JS_GetOpaque(signal, engine.abort_signal_class) == null)) return error.InvalidPromiseTimerSignal;
    const record = try engine.checked(c.JS_NewObjectProto(engine.context, c.pi_js_null()));
    defer engine.freeValue(record);
    try recordProperty(engine, record, "resolve", c.JS_DupValue(engine.context, capabilities[0]));
    try recordProperty(engine, record, "reject", c.JS_DupValue(engine.context, capabilities[1]));
    try recordProperty(engine, record, "signal", c.JS_DupValue(engine.context, signal));
    try recordProperty(engine, record, "value", if (args.len > 1) c.JS_DupValue(engine.context, args[1]) else c.pi_js_undefined());
    var data = [_]c.JSValue{record};
    const callback = try engine.checked(c.JS_NewCFunctionData2(engine.context, promiseCallback, "promise timer", 0, 0, 1, &data));
    defer engine.freeValue(callback);
    if (!c.JS_IsUndefined(signal)) {
        const aborted = try engine.checked(c.JS_GetPropertyStr(engine.context, signal, "aborted"));
        defer engine.freeValue(aborted);
        if (c.JS_ToBool(engine.context, aborted) != 0) {
            const reason = try abortedPromiseError(engine, signal);
            defer engine.freeValue(reason);
            var arguments = [_]c.JSValue{reason};
            const result = try engine.checked(c.JS_Call(engine.context, capabilities[1], c.pi_js_undefined(), 1, &arguments));
            engine.freeValue(result);
            return promise;
        }
    }
    var timer_args = [_]c.JSValue{ callback, if (args.len > 0) args[0] else c.pi_js_undefined() };
    const handle = try schedule(engine, &timer_args, false);
    defer engine.freeValue(handle);
    // The new ID is known independently of JS coercion; remove the timer on
    // any later setup failure, even when the context holds a pending exception.
    const timer_id = (try scheduler(engine)).next_id - 1;
    errdefer {
        const state = scheduler(engine) catch unreachable;
        for (state.timers.items, 0..) |timer, index| if (timer.id == timer_id) {
            state.freeTimer(state.timers.orderedRemove(index));
            break;
        };
    }
    try recordProperty(engine, record, "handle", c.JS_DupValue(engine.context, handle));
    if (!c.JS_IsUndefined(signal)) {
        const listener = try engine.checked(c.JS_NewCFunctionData2(engine.context, promiseCallback, "abort promise timer", 1, 1, 1, &data));
        defer engine.freeValue(listener);
        try recordProperty(engine, record, "listener", c.JS_DupValue(engine.context, listener));
        const add = try engine.checked(c.JS_GetPropertyStr(engine.context, signal, "addEventListener"));
        defer engine.freeValue(add);
        const options = try engine.checked(c.JS_NewObject(engine.context));
        defer engine.freeValue(options);
        try recordProperty(engine, options, "once", c.pi_js_bool(engine.context, 1));
        var arguments = [_]c.JSValue{ c.JS_NewString(engine.context, "abort"), listener, options };
        defer engine.freeValue(arguments[0]);
        const result = try engine.checked(c.JS_Call(engine.context, add, signal, arguments.len, &arguments));
        engine.freeValue(result);
    }
    return promise;
}

pub fn nextDeadline(engine: *engine_mod.Engine) !?i64 {
    const state = try scheduler(engine);
    if (state.timers.items.len == 0) return null;
    var deadline = state.timers.items[0].deadline_ms;
    for (state.timers.items) |timer| deadline = @min(deadline, timer.deadline_ms);
    return deadline;
}

/// Execute one due callback without waiting for a future deadline. All timer
/// and JavaScript ownership remains on the calling engine owner thread.
pub fn pumpReady(engine: *engine_mod.Engine) !bool {
    const state = try scheduler(engine);
    if (state.timers.items.len == 0) return false;
    var index: usize = 0;
    for (state.timers.items, 0..) |timer, candidate| if (timer.deadline_ms < state.timers.items[index].deadline_ms) {
        index = candidate;
    };
    if (state.timers.items[index].deadline_ms > std.Io.Clock.awake.now(state.io).toMilliseconds()) return false;
    return fire(state, index);
}

fn pump(engine: *engine_mod.Engine) !bool {
    const state = try scheduler(engine);
    if (state.timers.items.len == 0) return false;
    var index: usize = 0;
    for (state.timers.items, 0..) |timer, candidate| if (timer.deadline_ms < state.timers.items[index].deadline_ms) {
        index = candidate;
    };
    const deadline = state.timers.items[index].deadline_ms;
    while (true) {
        // Abort listeners run on this owner thread and may clear or schedule
        // timers. Yield after any dispatched control so awaitValue drains jobs
        // and the next pump selects a fresh queue entry and deadline.
        if (try engine.pumpControls()) return true;
        if (engine.cancelled.load(.acquire)) return error.JavaScriptInterrupted;
        const now = std.Io.Clock.awake.now(state.io).toMilliseconds();
        if (engine.host_await_deadline_ms) |limit| if (now >= limit) return error.NativeHostPromiseTimeout;
        const remaining = deadline - now;
        if (remaining <= 0) break;
        try state.io.sleep(.fromMilliseconds(@min(remaining, 10)), .awake);
    }
    return fire(state, index);
}

fn fire(state: *Scheduler, index: usize) !bool {
    const engine = state.engine;
    // Remove before invocation: callbacks can clear or schedule more timers.
    const timer = state.timers.orderedRemove(index);
    defer state.freeTimer(timer);
    const retained = handleState(timer.handle);
    const scope = @import("native_async_scope.zig").enter(engine, retained.async_scope);
    defer scope.restore();
    // Retired scopes still run ordinary JS bookkeeping. Their native action,
    // context and UI capabilities reject instead of borrowing another ticket.
    if (retained.interval_ms) |interval| {
        const repeated: Timer = .{ .id = timer.id, .deadline_ms = std.Io.Clock.awake.now(state.io).toMilliseconds() + interval, .handle = c.JS_DupValue(engine.context, timer.handle) };
        errdefer state.freeTimer(repeated);
        try state.timers.append(engine.gpa, repeated);
    }
    const result = try engine.checked(c.JS_Call(engine.context, retained.callback, timer.handle, @intCast(retained.arguments.len), retained.arguments.ptr));
    engine.freeValue(result);
    return true;
}

pub fn install(engine: *engine_mod.Engine, io: std.Io) !void {
    if (engine.host_scheduler != null) return error.NativeTimersAlreadyInstalled;
    const state = try engine.gpa.create(Scheduler);
    errdefer engine.gpa.destroy(state);
    state.* = .{ .engine = engine, .io = io };
    _ = c.JS_NewClassID(engine.runtime, &state.handle_class);
    const handle_class: c.JSClassDef = .{ .class_name = "Timeout", .finalizer = handleFinalizer, .gc_mark = handleMark, .call = null, .exotic = null };
    if (c.JS_NewClass(engine.runtime, state.handle_class, &handle_class) < 0) return error.OutOfMemory;
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    const symbols = try engine.checked(c.JS_GetPropertyStr(engine.context, global, "Symbol"));
    defer engine.freeValue(symbols);
    const primitive = try engine.checked(c.JS_GetPropertyStr(engine.context, symbols, "toPrimitive"));
    defer engine.freeValue(primitive);
    state.primitive_atom = c.JS_ValueToAtom(engine.context, primitive);
    if (state.primitive_atom == c.JS_ATOM_NULL) return error.OutOfMemory;
    errdefer c.JS_FreeAtom(engine.context, state.primitive_atom);
    inline for (.{ .{ "setTimeout", 0 }, .{ "setInterval", 1 } }) |entry| {
        const value = try engine.checked(c.pi_js_function_magic(engine.context, scheduleCall, entry[0], 2, entry[1]));
        if (c.JS_DefinePropertyValueStr(engine.context, global, entry[0], value, c.JS_PROP_C_W_E) < 0) return error.JavaScriptException;
    }
    inline for (.{ "clearTimeout", "clearInterval" }) |name| {
        const value = try engine.checked(c.JS_NewCFunction(engine.context, clearCall, name, 1));
        if (c.JS_DefinePropertyValueStr(engine.context, global, name, value, c.JS_PROP_C_W_E) < 0) return error.JavaScriptException;
    }
    const microtask = try engine.checked(c.JS_NewCFunction(engine.context, queueMicrotask, "queueMicrotask", 1));
    if (c.JS_DefinePropertyValueStr(engine.context, global, "queueMicrotask", microtask, c.JS_PROP_C_W_E) < 0) return error.JavaScriptException;
    const module = try engine.checked(c.JS_NewObject(engine.context));
    defer engine.freeValue(module);
    inline for (.{ "setTimeout", "setInterval", "clearTimeout", "clearInterval" }) |name| {
        const value = try engine.checked(c.JS_GetPropertyStr(engine.context, global, name));
        if (c.JS_DefinePropertyValueStr(engine.context, module, name, value, c.JS_PROP_C_W_E) < 0) return error.JavaScriptException;
    }
    try engine.registerDefaultModule("node:timers", module);
    try engine.registerDefaultModule("timers", module);
    const promise_module = try engine.checked(c.JS_NewObject(engine.context));
    defer engine.freeValue(promise_module);
    if (c.JS_DefinePropertyValueStr(engine.context, promise_module, "setTimeout", c.JS_NewCFunction(engine.context, promiseTimeout, "setTimeout", 2), c.JS_PROP_C_W_E) < 0) return error.JavaScriptException;
    try engine.registerDefaultModule("node:timers/promises", promise_module);
    try engine.registerDefaultModule("timers/promises", promise_module);
    engine.host_scheduler = state;
    if (engine.native_io == null) engine.native_io = io;
    engine.host_pump = pump;
    engine.host_scheduler_deinit = cleanup;
}

test "native timers resolve real promises preserve arguments and retire cleared intervals" {
    const engine = try engine_mod.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    try install(engine, std.testing.io);
    const value = try engine.evalModule("const calls=[];const removed=setTimeout(()=>calls.push('wrong'),1);clearTimeout(removed);const first=await new Promise(resolve=>setTimeout((a,b)=>resolve(a+':'+b),2,'a','b'));let ticks=0;await new Promise(resolve=>{const id=setInterval(()=>{if(++ticks===2){clearInterval(id);resolve()}},1)});export const result=first+':'+ticks+':'+calls.length;", "native-timer-promises.mjs");
    defer engine.freeValue(value);
    const result = try engine.checked(c.JS_GetPropertyStr(engine.context, value, "result"));
    defer engine.freeValue(result);
    const text = try engine.toString(result);
    defer engine.gpa.free(text);
    try std.testing.expectEqualStrings("a:b:2:0", text);
    try std.testing.expectEqual(@as(usize, 0), (try scheduler(engine)).timers.items.len);
}

test "native timer callbacks retain original thrown values" {
    const engine = try engine_mod.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    try install(engine, std.testing.io);
    try std.testing.expectError(error.JavaScriptException, engine.evalModule("setTimeout(()=>{throw new Error('owned timer error')},1);await new Promise(()=>{});", "native-timer-error.mjs"));
    try std.testing.expect(std.mem.indexOf(u8, engine.last_error.?, "owned timer error") != null);
}

test "native host promise deadlines bound a timer that never completes its await" {
    const engine = try engine_mod.Engine.init(std.testing.allocator, .{ .host_await_timeout_ms = 5 });
    defer engine.deinit();
    try install(engine, std.testing.io);
    try std.testing.expectError(error.NativeHostPromiseTimeout, engine.evalModule("await new Promise(resolve=>setTimeout(resolve,1000));", "native-timer-deadline.mjs"));
}

test "pending timer timeout callback cycles survive repeated explicit GC and engine teardown" {
    for (0..96) |iteration| {
        const engine = try engine_mod.Engine.init(std.testing.allocator, .{ .host_await_timeout_ms = 5 });
        defer engine.deinit();
        try install(engine, std.testing.io);
        try std.testing.expectError(error.NativeHostPromiseTimeout, engine.evalModule("await new Promise(resolve=>setTimeout(resolve,1000));", "pending-timer-gc.mjs"));
        // Exercise collection with a queued native root, then with only the
        // timer/method/promise cycles left after scheduler ownership releases.
        c.JS_RunGC(engine.runtime);
        cleanup(engine);
        c.JS_RunGC(engine.runtime);
        const allocation_churn = try engine.eval("Array.from({length:128},(_,i)=>({i,payload:new Uint8Array((i%7)+1)}))", "pending-timer-churn.js", c.JS_EVAL_TYPE_GLOBAL);
        engine.freeValue(allocation_churn);
        c.JS_RunGC(engine.runtime);
        if (iteration % 8 == 0) c.JS_RunGC(engine.runtime);
    }
}

test "timed-out scheduler releases native callback ownership before cycle GC" {
    var counting = std.testing.FailingAllocator.init(std.testing.allocator, .{});
    const engine = try engine_mod.Engine.init(counting.allocator(), .{ .host_await_timeout_ms = 5 });
    defer engine.deinit();
    try install(engine, std.testing.io);
    const installed_bytes = counting.allocated_bytes - counting.freed_bytes;
    try std.testing.expectError(error.NativeHostPromiseTimeout, engine.evalModule("await new Promise(resolve=>setTimeout(resolve,1000));", "timeout-native-owner.mjs"));
    cleanup(engine);
    // No JavaScript reference retains this handle: the timeout call's result
    // was discarded. Host callback state must be gone before any cycle GC or
    // context teardown tries to free method-function captured values.
    try std.testing.expectEqual(installed_bytes - @sizeOf(Scheduler), counting.allocated_bytes - counting.freed_bytes);
    c.JS_RunGC(engine.runtime);
}

test "native timer methods brand their receiver without retaining a different handle" {
    const engine = try engine_mod.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    try install(engine, std.testing.io);
    const module = try engine.evalModule("const a=setTimeout(()=>{},1000),b=setTimeout(()=>{},1000);const ref=a.ref;if(ref.call(b)!==b||a.hasRef.call(b)!==true)throw Error('genuine receiver');let caught=false;try{ref.call({})}catch(error){caught=error instanceof TypeError}if(!caught)throw Error('unbranded receiver');clearTimeout(a);clearTimeout(b);", "timer-method-receiver.mjs");
    defer engine.freeValue(module);
}

test "native microtasks drain in order before a settled callback is published" {
    const engine = try engine_mod.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    try install(engine, std.testing.io);
    const value = try engine.evalModule("export const order=[];queueMicrotask(()=>{order.push('first');queueMicrotask(()=>order.push('third'))});queueMicrotask(()=>order.push('second'));", "native-microtasks.mjs");
    defer engine.freeValue(value);
    const result = try engine.checked(c.JS_GetPropertyStr(engine.context, value, "order"));
    defer engine.freeValue(result);
    const encoded = try engine.stringify(result);
    defer engine.gpa.free(encoded);
    try std.testing.expectEqualStrings("[\"first\",\"second\",\"third\"]", encoded);
}

fn allocationCallback(_: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue) callconv(.c) c.JSValue {
    return c.pi_js_undefined();
}

fn timerAllocationProbe(gpa: std.mem.Allocator) !void {
    const engine = try engine_mod.Engine.init(gpa, .{});
    defer engine.deinit();
    try install(engine, std.testing.io);
    const callback = try engine.checked(c.JS_NewCFunction(engine.context, allocationCallback, "owned timer", 0));
    defer engine.freeValue(callback);
    var args = [_]c.JSValue{ callback, c.JS_NewInt32(engine.context, 1), c.JS_NewString(engine.context, "retained argument") };
    defer engine.freeValue(args[1]);
    defer engine.freeValue(args[2]);
    const id = try schedule(engine, &args, true);
    defer engine.freeValue(id);
    try std.testing.expect(try pump(engine));
}

test "native timer scheduling and interval ownership release every failed allocation" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, timerAllocationProbe, .{});
}

test "native timer handles support Node lifecycle methods identity and module aliases" {
    const engine = try engine_mod.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    try install(engine, std.testing.io);
    const value = try engine.evalModule("import {setTimeout as imported} from 'node:timers';import timers from 'timers';if(imported!==setTimeout||timers.setTimeout!==setTimeout)throw Error('module identity');let calls=0;const removed=setTimeout(()=>calls++,2);if(typeof removed!=='object'||!removed.hasRef()||removed.unref()!==removed||removed.hasRef()||removed.ref()!==removed||!removed.hasRef()||removed.refresh()!==removed||!Number.isInteger(+removed)||String(removed)!==String(+removed))throw Error('timer handle');if(removed.close()!==removed)throw Error('close identity');await new Promise(resolve=>{const handle=setTimeout(function(){if(this!==handle)throw Error('callback receiver');resolve()},2);clearTimeout(+removed)});if(calls!==0)throw Error('closed timer');", "native-timer-handles.mjs");
    defer engine.freeValue(value);
}

test "native promise timer module resolves values and cancellation preserves causes" {
    const engine = try engine_mod.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    try @import("abort_signal.zig").install(engine);
    try install(engine, std.testing.io);
    const value = try engine.evalModule("import {setTimeout as delay} from 'node:timers/promises';const token={value:1};if(await delay(2,token)!==token)throw Error('promise value');const pre=new AbortController();const reason={cancel:1};pre.abort(reason);try{await delay(2,'bad',{signal:pre.signal});throw Error('preabort resolved')}catch(error){if(error.name!=='AbortError'||error.code!=='ABORT_ERR'||error.cause!==reason)throw error}const live=new AbortController();const promise=delay(100,'bad',{signal:live.signal});setTimeout(()=>live.abort(reason),2);try{await promise;throw Error('live abort resolved')}catch(error){if(error.cause!==reason)throw error}", "native-promise-timers.mjs");
    defer engine.freeValue(value);
    try std.testing.expectEqual(@as(usize, 0), (try scheduler(engine)).timers.items.len);
}

test "failed promise timer setup does not retain an unpublished scheduled callback" {
    const engine = try engine_mod.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    try @import("abort_signal.zig").install(engine);
    try install(engine, std.testing.io);
    const value = try engine.evalModule("import {setTimeout as delay} from 'node:timers/promises';const controller=new AbortController();const original=Error('setup failure');controller.signal.addEventListener=()=>{throw original};let caught=false;try{await delay(100,'bad',{signal:controller.signal})}catch(error){if(error!==original)throw Error('exception replaced');caught=true}if(!caught)throw Error('setup did not fail');", "native-promise-timer-setup.mjs");
    defer engine.freeValue(value);
    try std.testing.expectEqual(@as(usize, 0), (try scheduler(engine)).timers.items.len);
}

const expired_refresh_scenario =
    \\const sleep=ms=>new Promise(resolve=>setTimeout(resolve,ms));
    \\const token={owned:true};let ticks=0;let finish;
    \\const handle=setTimeout(function(a,b){if(this!==handle||a!==token||b!=='argument')throw Error('retained callback');ticks++;if(ticks===2){if(this.refresh()!==this||this.refresh()!==this)throw Error('self refresh identity')}else finish()},2,token,'argument');
    \\const firstId=+handle;await new Promise(resolve=>finish=resolve);
    \\if(handle.unref()!==handle||handle.hasRef()||handle.refresh()!==handle||handle.hasRef()||+handle===firstId)throw Error('expired refresh lifecycle');
    \\// A referenced guard also lets Node run the unreferenced refreshed handle.
    \\const guard=setTimeout(()=>{throw Error('refresh did not fire')},500);
    \\await new Promise(resolve=>finish=resolve);clearTimeout(guard);
    \\if(ticks!==3||handle.ref()!==handle||!handle.hasRef())throw Error('duplicate refresh');
    \\let clearedTicks=0;const cleared=setTimeout(()=>clearedTicks++,1);await sleep(5);clearTimeout(cleared);cleared.refresh();
    \\let closedTicks=0;const closed=setTimeout(()=>closedTicks++,1);await sleep(5);if(closed.close()!==closed||closed.refresh()!==closed)throw Error('close identity');
    \\let numericTicks=0;const numeric=setTimeout(()=>numericTicks++,1);const oldId=+numeric;await sleep(5);clearTimeout(oldId);numeric.refresh();const freshId=+numeric;if(freshId===oldId)throw Error('primitive id not renewed');clearTimeout(oldId);
    \\await sleep(5);if(clearedTicks!==1||closedTicks!==1||numericTicks!==2)throw Error('expired cancellation');
    \\let activeTicks=0;const active=setTimeout(()=>activeTicks++,1);const activeId=+active;if(active.refresh()!==active||+active!==activeId)throw Error('active refresh identity');clearTimeout(activeId);active.refresh();await sleep(5);if(activeTicks!==0)throw Error('cleared active revived');
    \\const branded=setTimeout(()=>{throw Error('branded handle was not cleared')},1);branded[Symbol.toPrimitive]=()=>{throw Error('clear coerced branded handle')};clearTimeout(branded);branded.refresh();await sleep(5);
    \\export const result='refresh:'+ticks+':'+clearedTicks+':'+closedTicks+':'+numericTicks+':'+activeTicks;
;

test "expired native timers refresh with retained arguments receiver and Node cancellation semantics" {
    const engine = try engine_mod.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    try install(engine, std.testing.io);
    const value = try engine.evalModule(expired_refresh_scenario, "native-expired-timer-refresh.mjs");
    defer engine.freeValue(value);
    const result = try engine.checked(c.JS_GetPropertyStr(engine.context, value, "result"));
    defer engine.freeValue(result);
    const text = try engine.toString(result);
    defer engine.gpa.free(text);
    try std.testing.expectEqualStrings("refresh:3:1:1:2:0", text);
    try std.testing.expectEqual(@as(usize, 0), (try scheduler(engine)).timers.items.len);
}

fn expiredRefreshAllocationProbe(gpa: std.mem.Allocator) !void {
    const engine = try engine_mod.Engine.init(gpa, .{});
    defer engine.deinit();
    try install(engine, std.testing.io);
    const callback = try engine.checked(c.JS_NewCFunction(engine.context, allocationCallback, "refresh allocation", 0));
    defer engine.freeValue(callback);
    const handle = try scheduleOnce(engine, callback, 1);
    defer engine.freeValue(handle);
    try std.testing.expect(try pump(engine));
    const state = try scheduler(engine);
    // Fill the retained queue capacity so refreshing must grow its allocation.
    while (state.timers.items.len < state.timers.capacity) {
        const pending = try scheduleOnce(engine, callback, 100);
        engine.freeValue(pending);
    }
    const previous_id = handleState(handle).id;
    const previous_count = state.timers.items.len;
    refreshExpired(engine, handle) catch |err| {
        try std.testing.expectEqual(previous_id, handleState(handle).id);
        try std.testing.expectEqual(previous_count, state.timers.items.len);
        return err;
    };
    try std.testing.expect(handleState(handle).id != previous_id);
    try std.testing.expectEqual(previous_count + 1, state.timers.items.len);
}

test "expired native timer refresh publishes no queue entry or id on allocation failure" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, expiredRefreshAllocationProbe, .{});
}

test "expired native timer refresh limit failures preserve the handle and can be retried" {
    const engine = try engine_mod.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    try install(engine, std.testing.io);
    const callback = try engine.checked(c.JS_NewCFunction(engine.context, allocationCallback, "refresh limit", 0));
    defer engine.freeValue(callback);
    const handle = try scheduleOnce(engine, callback, 1);
    defer engine.freeValue(handle);
    try std.testing.expect(try pump(engine));
    const state = try scheduler(engine);
    const previous_id = handleState(handle).id;
    const next_id = state.next_id;
    state.next_id = std.math.maxInt(u32);
    try std.testing.expectError(error.NativeTimerLimit, refreshExpired(engine, handle));
    try std.testing.expectEqual(previous_id, handleState(handle).id);
    try std.testing.expectEqual(@as(usize, 0), state.timers.items.len);
    state.next_id = next_id;
    try refreshExpired(engine, handle);
    try std.testing.expectEqual(next_id, handleState(handle).id);
    try std.testing.expect(try pump(engine));
    try std.testing.expectEqual(@as(usize, 0), state.timers.items.len);
}

test "expired native timer callback argument and handle cycles are garbage collected" {
    var allocations = std.testing.FailingAllocator.init(std.testing.allocator, .{});
    const engine = try engine_mod.Engine.init(allocations.allocator(), .{});
    defer engine.deinit();
    try install(engine, std.testing.io);
    const callback = try engine.checked(c.JS_NewCFunction(engine.context, allocationCallback, "cycle callback", 0));
    defer engine.freeValue(callback);
    const argument = try engine.checked(c.JS_NewObject(engine.context));
    var args = [_]c.JSValue{ callback, c.JS_NewInt32(engine.context, 1), argument };
    const handle = try schedule(engine, &args, false);
    if (c.JS_DefinePropertyValueStr(engine.context, argument, "handle", c.JS_DupValue(engine.context, handle), c.JS_PROP_C_W_E) < 0) return error.JavaScriptException;
    engine.freeValue(argument);
    try std.testing.expect(try pump(engine));
    c.JS_RunGC(engine.runtime);
    const before = allocations.freed_bytes;
    engine.freeValue(handle);
    c.JS_RunGC(engine.runtime);
    try std.testing.expectEqual(@sizeOf(HandleState) + @sizeOf(c.JSValue), allocations.freed_bytes - before);
    try std.testing.expectEqual(@as(usize, 0), (try scheduler(engine)).timers.items.len);
}

const timer_input_validation_scenario =
    \\import {setTimeout as delay} from 'node:timers/promises';
    \\let coerced=0;const trap={valueOf(){coerced++;throw Error('delay coercion')},[Symbol.toPrimitive](){coerced++;throw Error('primitive coercion')}};
    \\const invalid=[null,true,'1',Symbol('delay'),1n,new Number(1),trap];let rejected=0;
    \\for(const value of invalid){let promise;try{promise=delay(value,'bad')}catch(error){throw Error('validation threw synchronously')}if(!(promise instanceof Promise))throw Error('missing promise');try{await promise;throw Error('invalid delay resolved')}catch(error){if(!(error instanceof TypeError)||error.code!=='ERR_INVALID_ARG_TYPE')throw error;rejected++}}
    \\let touched=0;try{await delay('1',null,{get signal(){touched++;throw Error('signal accessed before delay validation')}})}catch(error){if(error.code!=='ERR_INVALID_ARG_TYPE')throw error}if(touched||coerced)throw Error('validation invoked user code');
    \\for(const value of [undefined,1,NaN,Infinity,-1,0,.25])if(await delay(value,'ok')!=='ok')throw Error('primitive numeric delay');if(await delay()!==undefined)throw Error('default delay');
    \\// Ordinary callback timers intentionally keep their numeric coercion.
    \\let callbackCoercions=0;await new Promise(resolve=>setTimeout(resolve,{valueOf(){callbackCoercions++;return 1}}));if(callbackCoercions!==1)throw Error('callback coercion changed');
    \\const noops=[id=>undefined,id=>null,id=>true,id=>Symbol('timer'),id=>BigInt(id),id=>trap,id=>new Number(id),id=>[id],id=>id+4294967296,id=>-id,id=>id+.25,id=>NaN,id=>Infinity,id=>'0'+id,id=>' '+id,id=>id+' ',id=>'+'+id,id=>id+'.0',id=>id+'e0',id=>'0x'+id.toString(16),id=>'',id=>String(id)+'\0'];let fired=0;
    \\for(const input of noops){let calls=0;const handle=setTimeout(()=>calls++,1);if(clearTimeout(input(+handle))!==undefined)throw Error('clear return value');await delay(4);if(calls!==1)throw Error('noncanonical timer cancelled');fired+=calls;clearTimeout(handle)}
    \\for(const canonical of [id=>id,id=>String(id)]){let calls=0;const handle=setTimeout(()=>calls++,1);clearInterval(canonical(+handle));handle.refresh();await delay(4);if(calls!==0)throw Error('canonical clear failed')}
    \\if(coerced!==0)throw Error('clearTimeout coerced object');export const result='inputs:'+rejected+':'+fired+':'+coerced+':'+touched;
;

test "native timer inputs preserve Node no-coercion cancellation and promise number validation" {
    const engine = try engine_mod.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    try install(engine, std.testing.io);
    const value = try engine.evalModule(timer_input_validation_scenario, "native-timer-input-validation.mjs");
    defer engine.freeValue(value);
    const result = try engine.checked(c.JS_GetPropertyStr(engine.context, value, "result"));
    defer engine.freeValue(result);
    const encoded = try engine.toString(result);
    defer engine.gpa.free(encoded);
    try std.testing.expectEqualStrings("inputs:7:22:0:0", encoded);
    try std.testing.expectEqual(@as(usize, 0), (try scheduler(engine)).timers.items.len);
}

fn rejectedDelayAllocationProbe(gpa: std.mem.Allocator) !void {
    const engine = try engine_mod.Engine.init(gpa, .{});
    defer engine.deinit();
    try install(engine, std.testing.io);
    const invalid_delay = try engine.checked(c.JS_NewString(engine.context, "invalid delay"));
    defer engine.freeValue(invalid_delay);
    var args = [_]c.JSValue{invalid_delay};
    const promise = try schedulePromise(engine, &args);
    defer engine.freeValue(promise);
    try std.testing.expectEqual(c.JS_PROMISE_REJECTED, c.JS_PromiseState(engine.context, promise));
    try std.testing.expectEqual(@as(usize, 0), (try scheduler(engine)).timers.items.len);
}

test "native promise delay rejection releases every failed native allocation" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, rejectedDelayAllocationProbe, .{});
}

fn clearWaitingTimerControl(engine: *engine_mod.Engine) !bool {
    const state = try scheduler(engine);
    var args = [_]c.JSValue{state.timers.items[0].handle};
    const result = try engine.checked(clearCall(engine.context, c.pi_js_undefined(), 1, &args));
    engine.freeValue(result);
    engine.host_control_pump = null;
    return true;
}

fn failingWaitingTimerControl(_: *engine_mod.Engine) !bool {
    return error.TimerControlProbeFailure;
}

test "native timer waits dispatch owner controls and reselect after queue mutation" {
    const engine = try engine_mod.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    try install(engine, std.testing.io);
    const callback = try engine.checked(c.JS_NewCFunction(engine.context, allocationCallback, "control wait", 0));
    defer engine.freeValue(callback);
    const handle = try scheduleOnce(engine, callback, 1000);
    defer engine.freeValue(handle);
    engine.host_control_pump = failingWaitingTimerControl;
    try std.testing.expectError(error.TimerControlProbeFailure, pump(engine));
    try std.testing.expectEqual(@as(usize, 1), (try scheduler(engine)).timers.items.len);
    engine.host_control_pump = clearWaitingTimerControl;
    try std.testing.expect(try pump(engine));
    try std.testing.expectEqual(@as(usize, 0), (try scheduler(engine)).timers.items.len);
    try std.testing.expect(!try pump(engine));
}
