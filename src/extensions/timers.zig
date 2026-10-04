//! Native timer callbacks pumped while a promise is awaiting host work.
const std = @import("std");
const engine_mod = @import("engine.zig");
const c = engine_mod.c;
const Timer = struct {
    id: u32,
    deadline_ms: i64,
    interval_ms: ?i64,
    delay_ms: i64,
    callback: c.JSValue,
    arguments: []c.JSValue,
    handle: c.JSValue,
};
const Scheduler = struct {
    engine: *engine_mod.Engine,
    io: std.Io,
    next_id: u32 = 1,
    primitive_atom: c.JSAtom = c.JS_ATOM_NULL,
    timers: std.ArrayList(Timer) = .empty,
    fn freeTimer(self: *Scheduler, timer: Timer) void {
        self.engine.freeValue(timer.callback);
        self.engine.freeValue(timer.handle);
        for (timer.arguments) |argument| self.engine.freeValue(argument);
        self.engine.gpa.free(timer.arguments);
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
    const arguments = try engine.gpa.alloc(c.JSValue, if (args.len > 2) args.len - 2 else 0);
    errdefer engine.gpa.free(arguments);
    for (arguments, 0..) |*argument, index| argument.* = c.JS_DupValue(engine.context, args[index + 2]);
    errdefer for (arguments) |argument| engine.freeValue(argument);
    const handle = try createHandle(engine, state.next_id);
    defer engine.freeValue(handle);
    const timer: Timer = .{
        .id = state.next_id,
        .deadline_ms = std.Io.Clock.awake.now(state.io).toMilliseconds() + delay,
        .interval_ms = if (repeat) delay else null,
        .delay_ms = delay,
        .callback = c.JS_DupValue(engine.context, args[0]),
        .arguments = arguments,
        .handle = c.JS_DupValue(engine.context, handle),
    };
    errdefer {
        engine.freeValue(timer.callback);
        engine.freeValue(timer.handle);
    }
    try state.timers.append(engine.gpa, timer);
    state.next_id += 1;
    return c.JS_DupValue(engine.context, handle);
}

fn handleCall(context: ?*c.JSContext, this: c.JSValue, _: c_int, _: [*c]c.JSValue, magic: c_int, data: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = engine_mod.Engine.fromContext(context.?);
    if (!c.JS_IsStrictEqual(context, this, data[1])) return c.JS_ThrowTypeError(context, "Illegal timer handle receiver");
    if (magic == 0) return c.JS_DupValue(context, data[0]);
    const state = scheduler(engine) catch |err| return failure(context, err);
    var id: u32 = 0;
    if (c.JS_ToUint32(context, &id, data[0]) < 0) return engine.throwCaptured();
    if (magic == 3) return c.JS_GetPropertyStr(context, data[2], "refed");
    if (magic == 1 or magic == 2) {
        if (c.JS_SetPropertyStr(context, data[2], "refed", c.pi_js_bool(context, @intFromBool(magic == 1))) < 0) return c.JS_Throw(context, c.JS_GetException(context));
    } else if (magic == 4 or magic == 5) {
        for (state.timers.items, 0..) |*timer, index| if (timer.id == id) {
            if (magic == 4) timer.deadline_ms = std.Io.Clock.awake.now(state.io).toMilliseconds() + timer.delay_ms else state.freeTimer(state.timers.orderedRemove(index));
            return c.JS_DupValue(context, this);
        };
        if (magic == 4) return c.JS_ThrowTypeError(context, "Refreshing an expired native timer is not implemented");
    }
    return c.JS_DupValue(context, this);
}

fn createHandle(engine: *engine_mod.Engine, id: u32) !c.JSValue {
    const state = try scheduler(engine);
    const object = try engine.checked(c.JS_NewObject(engine.context));
    errdefer engine.freeValue(object);
    const flags = try engine.checked(c.JS_NewObjectProto(engine.context, c.pi_js_null()));
    defer engine.freeValue(flags);
    if (c.JS_DefinePropertyValueStr(engine.context, flags, "refed", c.pi_js_bool(engine.context, 1), c.JS_PROP_C_W_E) < 0) return error.JavaScriptException;
    var data = [_]c.JSValue{ c.JS_NewInt64(engine.context, id), object, flags };
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
    if (c.JS_ToUint32(context, &id, argv[0]) < 0) return engine.throwCaptured();
    for (state.timers.items, 0..) |timer, index| if (timer.id == id) {
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
        try recordProperty(engine, record, "listener", c.JS_DupValue(engine.context, listener));
        defer engine.freeValue(listener);
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

fn pump(engine: *engine_mod.Engine) !bool {
    const state = try scheduler(engine);
    if (state.timers.items.len == 0) return false;
    var index: usize = 0;
    for (state.timers.items, 0..) |timer, candidate| if (timer.deadline_ms < state.timers.items[index].deadline_ms) {
        index = candidate;
    };
    const deadline = state.timers.items[index].deadline_ms;
    while (true) {
        if (engine.cancelled.load(.acquire)) return error.JavaScriptInterrupted;
        const now = std.Io.Clock.awake.now(state.io).toMilliseconds();
        if (engine.host_await_deadline_ms) |limit| if (now >= limit) return error.NativeHostPromiseTimeout;
        const remaining = deadline - now;
        if (remaining <= 0) break;
        try state.io.sleep(.fromMilliseconds(@min(remaining, 10)), .awake);
    }
    // Remove before invocation: callbacks can clear or schedule more timers.
    const timer = state.timers.orderedRemove(index);
    defer state.freeTimer(timer);
    if (timer.interval_ms) |interval| {
        const args = try engine.gpa.alloc(c.JSValue, timer.arguments.len);
        for (args, timer.arguments) |*argument, value| argument.* = c.JS_DupValue(engine.context, value);
        const repeated: Timer = .{ .id = timer.id, .deadline_ms = std.Io.Clock.awake.now(state.io).toMilliseconds() + interval, .interval_ms = interval, .delay_ms = timer.delay_ms, .callback = c.JS_DupValue(engine.context, timer.callback), .arguments = args, .handle = c.JS_DupValue(engine.context, timer.handle) };
        errdefer state.freeTimer(repeated);
        try state.timers.append(engine.gpa, repeated);
    }
    const result = try engine.checked(c.JS_Call(engine.context, timer.callback, timer.handle, @intCast(timer.arguments.len), timer.arguments.ptr));
    engine.freeValue(result);
    return true;
}

pub fn install(engine: *engine_mod.Engine, io: std.Io) !void {
    if (engine.host_scheduler != null) return error.NativeTimersAlreadyInstalled;
    const state = try engine.gpa.create(Scheduler);
    errdefer engine.gpa.destroy(state);
    state.* = .{ .engine = engine, .io = io };
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
