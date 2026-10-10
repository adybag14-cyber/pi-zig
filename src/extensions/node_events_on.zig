//! Node24 events.on: genuine intrinsic async iterator, owned callback queues,
//! observable emitter operations and watermark backpressure.
const std = @import("std");
const js = @import("native_js_values.zig");
const c = js.c;
const v = @import("native_select_list.zig");
const events = @import("node_events.zig");
const subscriptions = @import("node_events_async.zig");
const Method = enum(c_int) { on, next, return_, throw_, self, event, error_, close, abort, size, low, high, paused };
fn fail(engine: *js.Engine, err: anyerror) c.JSValue {
    if (err == error.JavaScriptException) return engine.throwCaptured();
    if (err == error.OutOfMemory) return c.JS_ThrowOutOfMemory(engine.context);
    return c.JS_ThrowTypeError(engine.context, "Native events iterator: %s", @as([*:0]const u8, @errorName(err)));
}
fn function(engine: *js.Engine, holder: c.JSValue, method: Method, name: [*:0]const u8, length: c_int) !c.JSValue {
    if (method == .event or method == .error_ or method == .close or method == .abort) return @import("native_node_function.zig").create(engine, name, length, ordinaryCallback, &.{ holder, c.JS_NewInt32(engine.context, @intFromEnum(method)) });
    var data = [_]c.JSValue{holder};
    return engine.checked(c.JS_NewCFunctionData2(engine.context, call, name, length, @intFromEnum(method), 1, &data));
}
fn ordinaryCallback(engine: *js.Engine, receiver: c.JSValue, args: []const c.JSValue, values: []const c.JSValue) anyerror!c.JSValue {
    return run(engine, receiver, values[0], @enumFromInt(@as(c_int, @intFromFloat(try v.number(engine, values[1])))), args);
}
fn call(context: ?*c.JSContext, receiver: c.JSValue, argc: c_int, argv: [*c]c.JSValue, magic: c_int, data: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = js.Engine.fromContext(context.?);
    return run(engine, receiver, data[0], @enumFromInt(magic), if (argc > 0) argv[0..@intCast(argc)] else &.{}) catch |err| fail(engine, err);
}
fn invalid(engine: *js.Engine, value: c.JSValue, name: []const u8, expected: []const u8, property: bool) anyerror {
    const received = try events.description(engine, value);
    defer engine.gpa.free(received);
    const message = try std.fmt.allocPrint(engine.gpa, "The \"{s}\" {s} must be {s}. Received {s}", .{ name, if (property) "property" else "argument", expected, received });
    defer engine.gpa.free(message);
    return events.codedError(engine, "TypeError", "ERR_INVALID_ARG_TYPE", message);
}
fn integer(engine: *js.Engine, value: c.JSValue, name: []const u8) !void {
    if (!c.JS_IsNumber(value)) return invalid(engine, value, name, "of type number", true);
    const number = try v.number(engine, value);
    const whole = std.math.isFinite(number) and @trunc(number) == number;
    if (!whole or number < 1 or number > 9007199254740991) {
        const received = try engine.toString(value);
        defer engine.gpa.free(received);
        const message = try std.fmt.allocPrint(engine.gpa, "The value of \"{s}\" is out of range. It must be {s}. Received {s}", .{ name, if (!whole) "an integer" else ">= 1 && <= 9007199254740991", received });
        defer engine.gpa.free(message);
        return events.codedError(engine, "RangeError", "ERR_OUT_OF_RANGE", message);
    }
}
fn nullish(value: c.JSValue) bool {
    return c.JS_IsNull(value) or c.JS_IsUndefined(value);
}
fn watermark(engine: *js.Engine, options: c.JSValue, name: [*:0]const u8, legacy: [*:0]const u8, fallback: f64) !c.JSValue {
    var value = if (c.JS_IsUndefined(options)) c.pi_js_undefined() else try js.get(engine, options, name);
    if (nullish(value)) {
        engine.freeValue(value);
        value = if (c.JS_IsUndefined(options)) c.pi_js_undefined() else try js.get(engine, options, legacy);
    }
    if (nullish(value)) {
        engine.freeValue(value);
        value = v.numeric(engine, fallback);
    }
    errdefer engine.freeValue(value);
    const qualified = try std.fmt.allocPrint(engine.gpa, "options.{s}", .{name});
    defer engine.gpa.free(qualified);
    try integer(engine, value, qualified);
    return value;
}
fn push(engine: *js.Engine, array: c.JSValue, item: c.JSValue) !void {
    const length = try v.numberField(engine, array, "length");
    if (length >= 65536) return error.NativeEventQueueLimit;
    if (c.JS_DefinePropertyValueUint32(engine.context, array, @intFromFloat(length), c.JS_DupValue(engine.context, item), c.JS_PROP_C_W_E) < 0) return js.capture(engine);
}
fn shift(engine: *js.Engine, queue: c.JSValue) !c.JSValue {
    // Internal queues use intrinsic operations; guest prototype overrides do
    // not replace Node's internal FixedQueue behavior.
    const length: u32 = @intFromFloat(try v.numberField(engine, queue, "length"));
    if (length == 0) return c.pi_js_undefined();
    const first = try engine.checked(c.JS_GetPropertyUint32(engine.context, queue, 0));
    errdefer engine.freeValue(first);
    for (1..length) |index| {
        const value = try engine.checked(c.JS_GetPropertyUint32(engine.context, queue, @intCast(index)));
        if (c.JS_DefinePropertyValueUint32(engine.context, queue, @intCast(index - 1), value, c.JS_PROP_C_W_E) < 0) return js.capture(engine);
    }
    const atom = c.JS_NewAtomUInt32(engine.context, length - 1);
    defer c.JS_FreeAtom(engine.context, atom);
    if (c.JS_DeleteProperty(engine.context, queue, atom, c.JS_PROP_THROW) < 0) return js.capture(engine);
    try v.set(engine, queue, "length", c.JS_NewUint32(engine.context, length - 1));
    return first;
}
fn result(engine: *js.Engine, value: c.JSValue, done: bool) !c.JSValue {
    const object = try js.object(engine);
    errdefer engine.freeValue(object);
    try js.define(engine, object, "value", c.JS_DupValue(engine.context, value));
    try js.define(engine, object, "done", c.pi_js_bool(engine.context, @intFromBool(done)));
    return object;
}
fn settled(engine: *js.Engine, value: c.JSValue, rejected: bool) !c.JSValue {
    var capabilities: [2]c.JSValue = undefined;
    const promise = try engine.checked(c.JS_NewPromiseCapability(engine.context, &capabilities));
    errdefer engine.freeValue(promise);
    defer for (capabilities) |capability| engine.freeValue(capability);
    const returned = try js.call(engine, capabilities[@intFromBool(rejected)], c.pi_js_undefined(), &.{value});
    engine.freeValue(returned);
    return promise;
}
fn settleWaiter(engine: *js.Engine, waiter: c.JSValue, value: c.JSValue, rejected: bool) !void {
    const capability = try js.get(engine, waiter, if (rejected) "reject" else "resolve");
    defer engine.freeValue(capability);
    const returned = try js.call(engine, capability, c.pi_js_undefined(), &.{value});
    engine.freeValue(returned);
}
fn listen(engine: *js.Engine, holder: c.JSValue, emitter: c.JSValue, name: c.JSValue, callback: c.JSValue) !void {
    try subscriptions.addListener(engine, emitter, name, callback, false, c.pi_js_undefined());
    const listeners = try js.get(engine, holder, "listeners");
    defer engine.freeValue(listeners);
    const entry = try js.array(engine);
    defer engine.freeValue(entry);
    try push(engine, entry, emitter);
    try push(engine, entry, name);
    try push(engine, entry, callback);
    try push(engine, listeners, entry);
}
fn close(engine: *js.Engine, holder: c.JSValue) !c.JSValue {
    const disposable = try js.get(engine, holder, "abortDisposable");
    defer engine.freeValue(disposable);
    if (!nullish(disposable)) {
        const symbol = try js.global(engine, "Symbol");
        defer engine.freeValue(symbol);
        const key = try js.get(engine, symbol, "dispose");
        defer engine.freeValue(key);
        const dispose = try js.getKey(engine, disposable, key);
        defer engine.freeValue(dispose);
        const returned = try js.call(engine, dispose, disposable, &.{});
        engine.freeValue(returned);
    }
    const listeners = try js.get(engine, holder, "listeners");
    defer engine.freeValue(listeners);
    while (try v.numberField(engine, listeners, "length") > 0) {
        const length: u32 = @intFromFloat(try v.numberField(engine, listeners, "length"));
        const entry = try engine.checked(c.JS_GetPropertyUint32(engine.context, listeners, length - 1));
        defer engine.freeValue(entry);
        // Remove before invoking the receiver, matching pop/reentrant cleanup.
        try v.set(engine, listeners, "length", c.JS_NewUint32(engine.context, length - 1));
        const emitter = try engine.checked(c.JS_GetPropertyUint32(engine.context, entry, 0));
        defer engine.freeValue(emitter);
        const name = try engine.checked(c.JS_GetPropertyUint32(engine.context, entry, 1));
        defer engine.freeValue(name);
        const callback = try engine.checked(c.JS_GetPropertyUint32(engine.context, entry, 2));
        defer engine.freeValue(callback);
        try subscriptions.removeListener(engine, emitter, name, callback);
    }
    try v.set(engine, holder, "finished", c.pi_js_bool(engine.context, 1));
    const done = try result(engine, c.pi_js_undefined(), true);
    defer engine.freeValue(done);
    const waiting = try js.get(engine, holder, "waiting");
    defer engine.freeValue(waiting);
    while (try v.numberField(engine, waiting, "length") > 0) {
        const waiter = try shift(engine, waiting);
        defer engine.freeValue(waiter);
        try settleWaiter(engine, waiter, done, false);
    }
    return settled(engine, done, false);
}
fn errorHandler(engine: *js.Engine, holder: c.JSValue, reason: c.JSValue) !c.JSValue {
    const waiting = try js.get(engine, holder, "waiting");
    defer engine.freeValue(waiting);
    if (try v.numberField(engine, waiting, "length") == 0) {
        try v.set(engine, holder, "error", c.JS_DupValue(engine.context, reason));
    } else {
        const waiter = try shift(engine, waiting);
        defer engine.freeValue(waiter);
        try settleWaiter(engine, waiter, reason, true);
    }
    const done = try close(engine, holder);
    engine.freeValue(done);
    return c.pi_js_undefined();
}
fn run(engine: *js.Engine, receiver: c.JSValue, holder: c.JSValue, method: Method, args: []const c.JSValue) !c.JSValue {
    if (method == .on) return create(engine, holder, args);
    if (method == .self) return c.JS_DupValue(engine.context, receiver);
    if (method == .size or method == .low or method == .high or method == .paused) return js.get(engine, holder, switch (method) {
        .size => "size",
        .low => "low",
        .high => "high",
        .paused => "paused",
        else => unreachable,
    });
    if (method == .return_ or method == .close) return close(engine, holder);
    if (method == .throw_) {
        const reason = v.arg(args, 0);
        const error_constructor = try js.global(engine, "Error");
        defer engine.freeValue(error_constructor);
        const is_error = c.JS_IsInstanceOf(engine.context, reason, error_constructor);
        if (is_error < 0) return js.capture(engine);
        if (is_error == 0) return invalid(engine, reason, "EventEmitter.AsyncIterator", "an instance of Error", true);
        return errorHandler(engine, holder, reason);
    }
    if (method == .error_) return errorHandler(engine, holder, v.arg(args, 0));
    if (method == .abort) {
        const signal = try js.get(engine, holder, "signal");
        defer engine.freeValue(signal);
        const reason = try subscriptions.abortError(engine, signal);
        defer engine.freeValue(reason);
        return errorHandler(engine, holder, reason);
    }
    const waiting = try js.get(engine, holder, "waiting");
    defer engine.freeValue(waiting);
    const queue = try js.get(engine, holder, "queue");
    defer engine.freeValue(queue);
    const emitter = try js.get(engine, holder, "emitter");
    defer engine.freeValue(emitter);
    if (method == .event) {
        const value = try js.array(engine);
        defer engine.freeValue(value);
        for (args) |item| try push(engine, value, item);
        if (try v.numberField(engine, waiting, "length") == 0) {
            const size = try v.numberField(engine, holder, "size") + 1;
            try v.set(engine, holder, "size", v.numeric(engine, size));
            const paused = try js.get(engine, holder, "paused");
            defer engine.freeValue(paused);
            if (!v.truthy(engine, paused) and size > try v.numberField(engine, holder, "high")) {
                try v.set(engine, holder, "paused", c.pi_js_bool(engine.context, 1));
                const returned = try js.invoke(engine, emitter, "pause", &.{});
                engine.freeValue(returned);
            }
            try push(engine, queue, value);
        } else {
            const waiter = try shift(engine, waiting);
            defer engine.freeValue(waiter);
            const item = try result(engine, value, false);
            defer engine.freeValue(item);
            try settleWaiter(engine, waiter, item, false);
        }
        return c.pi_js_undefined();
    }
    const size = try v.numberField(engine, holder, "size");
    if (size > 0) {
        const value = try shift(engine, queue);
        defer engine.freeValue(value);
        try v.set(engine, holder, "size", v.numeric(engine, size - 1));
        const paused = try js.get(engine, holder, "paused");
        defer engine.freeValue(paused);
        if (v.truthy(engine, paused) and size - 1 < try v.numberField(engine, holder, "low")) {
            const returned = try js.invoke(engine, emitter, "resume", &.{});
            engine.freeValue(returned);
            try v.set(engine, holder, "paused", c.pi_js_bool(engine.context, 0));
        }
        const item = try result(engine, value, false);
        defer engine.freeValue(item);
        return settled(engine, item, false);
    }
    const reason = try js.get(engine, holder, "error");
    defer engine.freeValue(reason);
    if (v.truthy(engine, reason)) {
        const promise = try settled(engine, reason, true);
        errdefer engine.freeValue(promise);
        try v.set(engine, holder, "error", c.pi_js_null());
        return promise;
    }
    const finished = try js.get(engine, holder, "finished");
    defer engine.freeValue(finished);
    if (v.truthy(engine, finished)) return close(engine, holder);
    var capabilities: [2]c.JSValue = undefined;
    const promise = try engine.checked(c.JS_NewPromiseCapability(engine.context, &capabilities));
    errdefer engine.freeValue(promise);
    defer for (capabilities) |capability| engine.freeValue(capability);
    const waiter = try js.object(engine);
    defer engine.freeValue(waiter);
    try js.define(engine, waiter, "resolve", c.JS_DupValue(engine.context, capabilities[0]));
    try js.define(engine, waiter, "reject", c.JS_DupValue(engine.context, capabilities[1]));
    try push(engine, waiting, waiter);
    return promise;
}
fn create(engine: *js.Engine, state: c.JSValue, args: []const c.JSValue) !c.JSValue {
    const emitter = v.arg(args, 0);
    const event = v.arg(args, 1);
    const options = v.arg(args, 2);
    if (!c.JS_IsUndefined(options) and (c.JS_IsNull(options) or !c.JS_IsObject(options) or c.JS_IsArray(options) or c.JS_IsFunction(engine.context, options))) return invalid(engine, options, "options", "of type object", false);
    const signal = if (c.JS_IsUndefined(options)) c.pi_js_undefined() else try js.get(engine, options, "signal");
    defer engine.freeValue(signal);
    try subscriptions.validateSignal(engine, signal, "options.signal");
    if (!nullish(signal)) {
        const aborted = try js.get(engine, signal, "aborted");
        defer engine.freeValue(aborted);
        if (v.truthy(engine, aborted)) {
            _ = try engine.checked(c.JS_Throw(engine.context, try subscriptions.abortError(engine, signal)));
            unreachable;
        }
    }
    const high = try watermark(engine, options, "highWaterMark", "highWatermark", 9007199254740991);
    defer engine.freeValue(high);
    const low = try watermark(engine, options, "lowWaterMark", "lowWatermark", 1);
    defer engine.freeValue(low);
    const holder = try js.object(engine);
    defer engine.freeValue(holder);
    try js.define(engine, holder, "emitter", c.JS_DupValue(engine.context, emitter));
    try js.define(engine, holder, "signal", c.JS_DupValue(engine.context, signal));
    try js.define(engine, holder, "high", c.JS_DupValue(engine.context, high));
    try js.define(engine, holder, "low", c.JS_DupValue(engine.context, low));
    try js.define(engine, holder, "size", c.JS_NewInt32(engine.context, 0));
    try js.define(engine, holder, "paused", c.pi_js_bool(engine.context, 0));
    try js.define(engine, holder, "finished", c.pi_js_bool(engine.context, 0));
    try js.define(engine, holder, "error", c.pi_js_null());
    inline for (.{ "queue", "waiting", "listeners" }) |name| try js.define(engine, holder, name, try js.array(engine));
    const intrinsic = try engine.checked(c.JS_GetAsyncIteratorPrototype(engine.context));
    defer engine.freeValue(intrinsic);
    const iterator = try engine.checked(c.JS_NewObjectProto(engine.context, intrinsic));
    errdefer engine.freeValue(iterator);
    inline for (.{ .{ "next", Method.next, 0 }, .{ "return", Method.return_, 0 }, .{ "throw", Method.throw_, 1 } }) |entry| try js.define(engine, iterator, entry[0], try function(engine, holder, entry[1], entry[0], entry[2]));
    const symbol = try js.global(engine, "Symbol");
    defer engine.freeValue(symbol);
    const async_key = try js.get(engine, symbol, "asyncIterator");
    defer engine.freeValue(async_key);
    const self = try function(engine, holder, .self, "[Symbol.asyncIterator]", 0);
    defer engine.freeValue(self);
    try js.setKey(engine, iterator, async_key, self);
    const watermarks = try js.object(engine);
    defer engine.freeValue(watermarks);
    inline for (.{ .{ "size", Method.size }, .{ "low", Method.low }, .{ "high", Method.high }, .{ "isPaused", Method.paused } }) |entry| {
        const getter = try function(engine, holder, entry[1], "get " ++ entry[0], 0);
        const atom = c.JS_NewAtom(engine.context, entry[0]);
        defer c.JS_FreeAtom(engine.context, atom);
        if (c.JS_DefinePropertyGetSet(engine.context, watermarks, atom, getter, c.pi_js_undefined(), c.JS_PROP_C_W_E) < 0) return js.capture(engine);
    }
    const watermark_text = try v.text(engine, "nodejs.watermarkData");
    defer engine.freeValue(watermark_text);
    const watermark_key = try js.invoke(engine, symbol, "for", &.{watermark_text});
    defer engine.freeValue(watermark_key);
    try js.setKey(engine, iterator, watermark_key, watermarks);
    const event_callback = try function(engine, holder, .event, "", 0);
    defer engine.freeValue(event_callback);
    try listen(engine, holder, emitter, event, event_callback);
    const error_name = try v.text(engine, "error");
    defer engine.freeValue(error_name);
    if (!c.JS_IsStrictEqual(engine.context, event, error_name)) {
        const on = try js.get(engine, emitter, "on");
        defer engine.freeValue(on);
        if (c.JS_IsFunction(engine.context, on)) {
            const error_callback = try function(engine, holder, .error_, "errorHandler", 1);
            defer engine.freeValue(error_callback);
            try listen(engine, holder, emitter, error_name, error_callback);
        }
    }
    const close_events = if (c.JS_IsUndefined(options)) c.pi_js_undefined() else try js.get(engine, options, "close");
    defer engine.freeValue(close_events);
    if (!nullish(close_events)) {
        const length = try js.get(engine, close_events, "length");
        defer engine.freeValue(length);
        if (v.truthy(engine, length)) {
            var index: u32 = 0;
            while (true) : (index += 1) {
                const dynamic_length = try v.numberField(engine, close_events, "length");
                if (@as(f64, @floatFromInt(index)) >= dynamic_length) break;
                if (index >= 65536) return error.NativeEventListenerLimit;
                const name = try engine.checked(c.JS_GetPropertyUint32(engine.context, close_events, index));
                defer engine.freeValue(name);
                const close_callback = try function(engine, holder, .close, "closeHandler", 0);
                defer engine.freeValue(close_callback);
                try listen(engine, holder, emitter, name, close_callback);
            }
        }
    }
    if (v.truthy(engine, signal)) {
        const callback = try function(engine, holder, .abort, "abortListener", 0);
        defer engine.freeValue(callback);
        const add_abort = try subscriptions.addAbortFunction(engine, state);
        defer engine.freeValue(add_abort);
        try js.define(engine, holder, "abortDisposable", try js.call(engine, add_abort, c.pi_js_undefined(), &.{ signal, callback }));
    }
    return iterator;
}
pub fn onFunction(engine: *js.Engine, state: c.JSValue) !c.JSValue {
    return @import("native_node_function.zig").create(engine, "on", 2, ordinaryOn, &.{state});
}
fn ordinaryOn(engine: *js.Engine, _: c.JSValue, args: []const c.JSValue, values: []const c.JSValue) anyerror!c.JSValue {
    return create(engine, values[0], args);
}
