//! Native timer callbacks pumped while a promise is awaiting host work.
const std = @import("std");
const engine_mod = @import("engine.zig");
const c = engine_mod.c;
const Timer = struct {
    id: u32,
    deadline_ms: i64,
    interval_ms: ?i64,
    callback: c.JSValue,
    arguments: []c.JSValue,
};
const Scheduler = struct {
    engine: *engine_mod.Engine,
    io: std.Io,
    next_id: u32 = 1,
    timers: std.ArrayList(Timer) = .empty,
    fn freeTimer(self: *Scheduler, timer: Timer) void {
        self.engine.freeValue(timer.callback);
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
    for (arguments, 0..) |*argument, index| argument.* = c.JS_DupValue(engine.context, args[index + 2]);
    const timer: Timer = .{
        .id = state.next_id,
        .deadline_ms = std.Io.Clock.awake.now(state.io).toMilliseconds() + delay,
        .interval_ms = if (repeat) delay else null,
        .callback = c.JS_DupValue(engine.context, args[0]),
        .arguments = arguments,
    };
    errdefer state.freeTimer(timer);
    try state.timers.append(engine.gpa, timer);
    state.next_id += 1;
    return c.JS_NewInt64(engine.context, timer.id);
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
        const repeated: Timer = .{ .id = timer.id, .deadline_ms = std.Io.Clock.awake.now(state.io).toMilliseconds() + interval, .interval_ms = interval, .callback = c.JS_DupValue(engine.context, timer.callback), .arguments = args };
        errdefer state.freeTimer(repeated);
        try state.timers.append(engine.gpa, repeated);
    }
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    const result = try engine.checked(c.JS_Call(engine.context, timer.callback, global, @intCast(timer.arguments.len), timer.arguments.ptr));
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
