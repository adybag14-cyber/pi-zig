//! Adaptive, serialized progress writes with terminal-flush waiter transfer.
const engine_mod = @import("engine.zig");
const vm = @import("native_values.zig");
const js = @import("native_js_values.zig");
const awaiting = @import("native_durable_await.zig");
const c = engine_mod.c;
const Engine = engine_mod.Engine;
const Action = enum(c_int) { mark, markAndWait, stop, timer, written, failed, finished, stopped };
fn put(engine: *Engine, state: c.JSValue, name: [:0]const u8, value: c.JSValue) !void {
    try @import("native_tool_info.zig").putData(engine, state, name, c.JS_DupValue(engine.context, value));
}
fn callback(engine: *Engine, state: c.JSValue, action: Action) !c.JSValue {
    var data = [_]c.JSValue{state};
    return engine.checked(c.JS_NewCFunctionData2(engine.context, dispatch, "", if (action == .written or action == .failed) 1 else 0, @intFromEnum(action), data.len, &data));
}
pub fn create(engine: *Engine, intrinsics: *awaiting.Intrinsics, write: c.JSValue, on_error: c.JSValue, minimum_interval: c.JSValue) !c.JSValue {
    const state = try vm.object(engine);
    errdefer engine.freeValue(state);
    inline for (.{ .{ "write", write }, .{ "onError", on_error }, .{ "minimumInterval", minimum_interval }, .{ "promiseConstructor", intrinsics.constructor }, .{ "promiseResolve", intrinsics.resolve }, .{ "promiseThen", intrinsics.then_function } }) |field| try put(engine, state, field[0], field[1]);
    try @import("native_tool_info.zig").putData(engine, state, "waiters", try vm.array(engine));
    try put(engine, state, "nextAt", c.JS_NewInt32(engine.context, 0));
    inline for (.{ Action.mark, Action.markAndWait, Action.stop }) |action| try @import("native_tool_info.zig").putData(engine, state, @tagName(action), try callback(engine, state, action));
    return state;
}
fn dispatch(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, raw_action: c_int, data: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = Engine.fromContext(context.?);
    const action: Action = @enumFromInt(raw_action);
    return act(engine, data[0], action, if (argc > 0) argv[0] else c.pi_js_undefined()) catch |err| if (action == .stop) @import("native_durable.zig").rejectedPromise(engine, err) else @import("native_durable.zig").reject(engine, err);
}
fn truth(engine: *Engine, state: c.JSValue, name: [:0]const u8) !bool {
    const value = try vm.get(engine, state, name);
    defer engine.freeValue(value);
    return c.JS_ToBool(engine.context, value) != 0;
}
fn fieldNumber(engine: *Engine, state: c.JSValue, name: [:0]const u8) !f64 {
    const value = try vm.get(engine, state, name);
    defer engine.freeValue(value);
    var number: f64 = 0;
    if (c.JS_ToFloat64(engine.context, &number, value) < 0) return js.capture(engine);
    return number;
}
fn now(engine: *Engine) !f64 {
    const date = try js.global(engine, "Date");
    defer engine.freeValue(date);
    const value = try vm.invoke(engine, date, "now", &.{});
    defer engine.freeValue(value);
    var number: f64 = 0;
    if (c.JS_ToFloat64(engine.context, &number, value) < 0) return js.capture(engine);
    return number;
}
fn act(engine: *Engine, state: c.JSValue, action: Action, value: c.JSValue) !c.JSValue {
    switch (action) {
        .mark => {
            try put(engine, state, "dirty", c.pi_js_bool(engine.context, 1));
            try schedule(engine, state);
            return c.pi_js_undefined();
        },
        .markAndWait => {
            const promise = try js.global(engine, "Promise");
            defer engine.freeValue(promise);
            const waiter = try vm.invoke(engine, promise, "withResolvers", &.{});
            defer engine.freeValue(waiter);
            const waiters = try vm.get(engine, state, "waiters");
            defer engine.freeValue(waiters);
            try js.push(engine, waiters, waiter);
            const result = try vm.get(engine, waiter, "promise");
            errdefer engine.freeValue(result);
            _ = try act(engine, state, .mark, c.pi_js_undefined());
            return result;
        },
        .stop => {
            try put(engine, state, "stopped", c.pi_js_bool(engine.context, 1));
            const timer = try vm.get(engine, state, "timer");
            defer engine.freeValue(timer);
            const clear = try js.global(engine, "clearTimeout");
            defer engine.freeValue(clear);
            const ignored = try js.call(engine, clear, c.pi_js_undefined(), &.{timer});
            engine.freeValue(ignored);
            try put(engine, state, "timer", c.pi_js_undefined());
            const pending = try vm.get(engine, state, "inFlight");
            defer engine.freeValue(pending);
            const constructor = try vm.get(engine, state, "promiseConstructor");
            defer engine.freeValue(constructor);
            const resolve = try vm.get(engine, state, "promiseResolve");
            defer engine.freeValue(resolve);
            const then_function = try vm.get(engine, state, "promiseThen");
            defer engine.freeValue(then_function);
            var intrinsics: awaiting.Intrinsics = .{ .constructor = constructor, .resolve = resolve, .then_function = then_function };
            const stopped = try callback(engine, state, .stopped);
            defer engine.freeValue(stopped);
            return intrinsics.chain(engine, pending, stopped, c.pi_js_undefined());
        },
        .stopped => {
            const waiters = try vm.get(engine, state, "waiters");
            defer engine.freeValue(waiters);
            return vm.invoke(engine, waiters, "splice", &.{c.JS_NewInt32(engine.context, 0)});
        },
        .timer => {
            try put(engine, state, "timer", c.pi_js_undefined());
            try flush(engine, state);
            return c.pi_js_undefined();
        },
        .written, .failed => {
            const owner = try vm.get(engine, state, "owner");
            defer engine.freeValue(owner);
            const minimum = try fieldNumber(engine, owner, "minimumInterval");
            var delay = minimum;
            if (action == .written) {
                var bytes: f64 = 0;
                if (c.JS_ToFloat64(engine.context, &bytes, value) < 0) return js.capture(engine);
                delay = @max(minimum, bytes * 1000 / (100 * 1024));
            }
            try put(engine, owner, "nextAt", c.JS_NewFloat64(engine.context, (try fieldNumber(engine, state, "started")) + delay));
            const waiters = try vm.get(engine, state, "waiters");
            defer engine.freeValue(waiters);
            const iterator_symbol = try symbolIterator(engine);
            defer engine.freeValue(iterator_symbol);
            var iterator = try js.Iterator.init(engine, waiters, iterator_symbol);
            defer iterator.deinit();
            errdefer iterator.closePreserving();
            while (try iterator.next()) |waiter| {
                defer engine.freeValue(waiter);
                const ignored = try vm.invoke(engine, waiter, if (action == .written) "resolve" else "reject", if (action == .written) &.{} else &.{value});
                engine.freeValue(ignored);
            }
            if (action == .failed) {
                const on_error = try vm.get(engine, owner, "onError");
                defer engine.freeValue(on_error);
                const ignored = try js.call(engine, on_error, owner, &.{value});
                engine.freeValue(ignored);
            }
            return c.pi_js_undefined();
        },
        .finished => {
            try put(engine, state, "inFlight", c.pi_js_undefined());
            if (try truth(engine, state, "dirty")) try schedule(engine, state);
            return c.pi_js_undefined();
        },
    }
}
fn symbolIterator(engine: *Engine) !c.JSValue {
    const symbol = try js.global(engine, "Symbol");
    defer engine.freeValue(symbol);
    return vm.get(engine, symbol, "iterator");
}
fn schedule(engine: *Engine, state: c.JSValue) !void {
    if (try truth(engine, state, "stopped")) return;
    const timer = try vm.get(engine, state, "timer");
    defer engine.freeValue(timer);
    if (!c.JS_IsUndefined(timer)) return;
    const pending = try vm.get(engine, state, "inFlight");
    defer engine.freeValue(pending);
    if (!c.JS_IsUndefined(pending)) return;
    const wait = (try fieldNumber(engine, state, "nextAt")) - (try now(engine));
    if (wait <= 0) return flush(engine, state);
    const timeout = try js.global(engine, "setTimeout");
    defer engine.freeValue(timeout);
    const function = try callback(engine, state, .timer);
    defer engine.freeValue(function);
    const handle = try js.call(engine, timeout, c.pi_js_undefined(), &.{ function, c.JS_NewFloat64(engine.context, wait) });
    defer engine.freeValue(handle);
    try put(engine, state, "timer", handle);
}
fn flush(engine: *Engine, state: c.JSValue) !void {
    if (try truth(engine, state, "stopped") or !try truth(engine, state, "dirty")) return;
    try put(engine, state, "dirty", c.pi_js_bool(engine.context, 0));
    const waiters = try vm.get(engine, state, "waiters");
    defer engine.freeValue(waiters);
    const batch = try vm.invoke(engine, waiters, "splice", &.{c.JS_NewInt32(engine.context, 0)});
    defer engine.freeValue(batch);
    // The write callback can reenter mark(). Each write must retain its own
    // waiter batch and timestamp, including when the next write starts first.
    const frame = try vm.object(engine);
    defer engine.freeValue(frame);
    try put(engine, frame, "owner", state);
    try put(engine, frame, "waiters", batch);
    try put(engine, frame, "started", c.JS_NewFloat64(engine.context, try now(engine)));
    const write = try vm.get(engine, state, "write");
    defer engine.freeValue(write);
    const pending = try js.call(engine, write, state, &.{});
    defer engine.freeValue(pending);
    const fulfilled = try callback(engine, frame, .written);
    defer engine.freeValue(fulfilled);
    const rejected = try callback(engine, frame, .failed);
    defer engine.freeValue(rejected);
    const observed = try vm.invoke(engine, pending, "then", &.{ fulfilled, rejected });
    defer engine.freeValue(observed);
    const finished = try callback(engine, state, .finished);
    defer engine.freeValue(finished);
    const in_flight = try vm.invoke(engine, observed, "finally", &.{finished});
    defer engine.freeValue(in_flight);
    try put(engine, state, "inFlight", in_flight);
}
