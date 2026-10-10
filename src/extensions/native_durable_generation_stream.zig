//! Native async stream driving and trailing partial publication for generation.
const std = @import("std");
const engine_mod = @import("engine.zig");
const vm = @import("native_values.zig");
const js = @import("native_js_values.zig");
const awaiting = @import("native_durable_await.zig");
const c = engine_mod.c;
const Engine = engine_mod.Engine;
const Scope = struct {
    engine: *Engine,
    values: std.ArrayList(c.JSValue) = .empty,
    fn deinit(self: *Scope) void {
        for (self.values.items) |value| self.engine.freeValue(value);
        self.values.deinit(self.engine.gpa);
    }
    fn own(self: *Scope, value: c.JSValue) !c.JSValue {
        self.values.append(self.engine.gpa, value) catch |err| {
            self.engine.freeValue(value);
            return err;
        };
        return value;
    }
    fn get(self: *Scope, object: c.JSValue, key: [:0]const u8) !c.JSValue {
        return self.own(try vm.get(self.engine, object, key));
    }
    fn invoke(self: *Scope, object: c.JSValue, key: [:0]const u8, args: []const c.JSValue) !c.JSValue {
        return self.own(try vm.invoke(self.engine, object, key, args));
    }
    fn call(self: *Scope, function: c.JSValue, receiver: c.JSValue) !c.JSValue {
        return self.own(try js.call(self.engine, function, receiver, &.{}));
    }
};
fn put(engine: *Engine, object: c.JSValue, key: [:0]const u8, value: c.JSValue) !void {
    try @import("native_tool_info.zig").putData(engine, object, key, c.JS_DupValue(engine.context, value));
}
fn wait(engine: *Engine, state: c.JSValue, pending: c.JSValue, stage: c_int) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    var captured: awaiting.Intrinsics = .{ .constructor = try scope.get(state, "promiseConstructor"), .resolve = try scope.get(state, "promiseResolve"), .then_function = try scope.get(state, "promiseThen") };
    return awaiting.continueWith(advance, engine, &captured, state, pending, stage);
}
pub fn run(engine: *Engine, captured: *awaiting.Intrinsics, runtime: c.JSValue, model: c.JSValue, messages: c.JSValue, options: c.JSValue, attempt: c.JSValue, context: c.JSValue, live_token: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const state = try scope.own(try vm.object(engine));
    inline for (.{ .{ "promiseConstructor", captured.constructor }, .{ "promiseResolve", captured.resolve }, .{ "promiseThen", captured.then_function }, .{ "runtime", runtime }, .{ "context", context }, .{ "attempt", attempt }, .{ "liveToken", live_token } }) |field| try put(engine, state, field[0], field[1]);
    return begin(engine, state, model, messages, options) catch |err| {
        if (err != error.JavaScriptException) return err;
        return finish(engine, state, engine.captured_exception orelse return err, true);
    };
}
fn begin(engine: *Engine, state: c.JSValue, model: c.JSValue, messages: c.JSValue, options: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const runtime = try scope.get(state, "runtime");
    const models = try scope.get(runtime, "models");
    const model_context = try scope.own(try vm.object(engine));
    const copied = try scope.own(try js.collect(engine, messages, try iteratorSymbol(&scope, "iterator")));
    try put(engine, model_context, "messages", copied);
    const events = try scope.invoke(models, "streamSimple", &.{ model, model_context, options });
    try put(engine, state, "events", events);
    var method = try scope.own(try js.getKey(engine, events, try iteratorSymbol(&scope, "asyncIterator")));
    const synchronous = c.JS_IsUndefined(method) or c.JS_IsNull(method);
    if (synchronous) method = try scope.own(try js.getKey(engine, events, try iteratorSymbol(&scope, "iterator")));
    const iterator = try scope.own(try js.call(engine, method, events, &.{}));
    if (!c.JS_IsObject(iterator)) return js.typeError(engine, "Iterator is not an object");
    try put(engine, state, "iterator", iterator);
    try put(engine, state, "next", try scope.get(iterator, "next"));
    try put(engine, state, "synchronous", c.pi_js_bool(engine.context, @intFromBool(synchronous)));
    return next(engine, state);
}
fn iteratorSymbol(scope: *Scope, key: [:0]const u8) !c.JSValue {
    const symbol = try scope.own(try js.global(scope.engine, "Symbol"));
    return scope.get(symbol, key);
}
fn next(engine: *Engine, state: c.JSValue) anyerror!c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const pending = scope.call(try scope.get(state, "next"), try scope.get(state, "iterator")) catch |err| {
        if (err != error.JavaScriptException) return err;
        return finish(engine, state, engine.captured_exception orelse return err, true);
    };
    if (try truth(&scope, state, "synchronous")) return step(engine, state, pending);
    return wait(engine, state, pending, 1);
}
fn advance(engine: *Engine, state: c.JSValue, value: c.JSValue, rejected: bool, stage: c_int) anyerror!c.JSValue {
    return advanceCore(engine, state, value, rejected, stage) catch |err| {
        if (err != error.JavaScriptException or stage == 3 or stage == 5 or stage == 8) return err;
        return finish(engine, state, engine.captured_exception orelse return err, true);
    };
}
fn advanceCore(engine: *Engine, state: c.JSValue, value: c.JSValue, rejected: bool, stage: c_int) anyerror!c.JSValue {
    if (stage == 7) {
        var scope: Scope = .{ .engine = engine };
        defer scope.deinit();
        return finish(engine, state, try scope.get(state, "bodyError"), true);
    }
    if (stage == 3) {
        var scope: Scope = .{ .engine = engine };
        defer scope.deinit();
        if (rejected) {
            const runtime = try scope.get(state, "runtime");
            if (!try truth(&scope, try scope.get(runtime, "signal"), "aborted")) _ = try scope.invoke(runtime, "report", &.{value});
        }
        return c.pi_js_undefined();
    }
    if (stage == 8) {
        var scope: Scope = .{ .engine = engine };
        defer scope.deinit();
        try put(engine, state, "inFlight", c.pi_js_undefined());
        if (!c.JS_IsUndefined(try scope.get(state, "pending")) and !try truth(&scope, state, "stopped")) try schedule(engine, state);
        if (rejected) return engine.checked(c.JS_Throw(engine.context, c.JS_DupValue(engine.context, value)));
        return c.pi_js_undefined();
    }
    if (rejected and (stage == 1 or stage == 2 or stage == 6)) return finish(engine, state, value, true);
    if (rejected) return engine.checked(c.JS_Throw(engine.context, c.JS_DupValue(engine.context, value)));
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    if (stage == 1) return step(engine, state, value);
    if (stage == 6) return if (try truth(&scope, state, "iterationDone")) terminalResult(engine, state) else eventBody(engine, state, value);
    if (stage == 2) return finish(engine, state, value, false);
    if (stage == 5) {
        const failed = try scope.get(state, "finalRejected");
        const result = try scope.get(state, "finalValue");
        if (c.JS_ToBool(engine.context, failed) != 0) return engine.checked(c.JS_Throw(engine.context, c.JS_DupValue(engine.context, result)));
        return c.JS_DupValue(engine.context, result);
    }
    if (stage == 4) {
        var generation = try scope.get(value, "generation");
        if (c.JS_IsUndefined(generation) or c.JS_IsNull(generation)) {
            generation = try scope.own(try vm.object(engine));
            try put(engine, generation, "attempt", try scope.get(state, "attempt"));
            try put(engine, value, "generation", generation);
        }
        const key = try scope.own(try engine.checked(c.JS_NewString(engine.context, "message")));
        const symbol = try iteratorSymbol(&scope, "iterator");
        try @import("native_durable_tool_json.zig").assign(engine, generation, key, try scope.get(state, "partialCopy"), symbol);
        return c.pi_js_undefined();
    }
    return error.InvalidGenerationStreamContinuation;
}
fn terminalResult(engine: *Engine, state: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    return wait(engine, state, try scope.invoke(try scope.get(state, "events"), "result", &.{}), 2);
}
fn step(engine: *Engine, state: c.JSValue, value: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    if (!c.JS_IsObject(value)) return js.typeError(engine, "Iterator result is not an object");
    const done = try scope.get(value, "done");
    if (try truth(&scope, state, "synchronous")) {
        const item = try scope.get(value, "value");
        try put(engine, state, "iterationDone", done);
        return wait(engine, state, item, 6);
    }
    if (c.JS_ToBool(engine.context, done) != 0) return terminalResult(engine, state);
    return eventBody(engine, state, try scope.get(value, "value"));
}
fn eventBody(engine: *Engine, state: c.JSValue, event: c.JSValue) anyerror!c.JSValue {
    processEvent(engine, state, event) catch |err| {
        if (err != error.JavaScriptException) return err;
        const original = engine.captured_exception orelse return err;
        return closeAfterBodyError(engine, state, original);
    };
    return next(engine, state);
}
fn processEvent(engine: *Engine, state: c.JSValue, event: c.JSValue) !void {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const kind = try scope.get(event, "type");
    const done = try scope.own(try engine.checked(c.JS_NewString(engine.context, "done")));
    const failed = try scope.own(try engine.checked(c.JS_NewString(engine.context, "error")));
    if (c.JS_IsStrictEqual(engine.context, kind, done) or c.JS_IsStrictEqual(engine.context, kind, failed)) return;
    const partial = try scope.get(event, "partial");
    if (try vm.length(engine, try scope.get(partial, "content")) == 0) return;
    try put(engine, state, "pending", partial);
    try schedule(engine, state);
}
fn closeAfterBodyError(engine: *Engine, state: c.JSValue, original: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    try put(engine, state, "bodyError", original);
    const iterator = try scope.get(state, "iterator");
    const method = scope.get(iterator, "return") catch |err| {
        if (err != error.JavaScriptException) return err;
        return finish(engine, state, try scope.get(state, "bodyError"), true);
    };
    if (c.JS_IsUndefined(method) or c.JS_IsNull(method)) return finish(engine, state, try scope.get(state, "bodyError"), true);
    const pending = scope.call(method, iterator) catch |err| {
        if (err != error.JavaScriptException) return err;
        return finish(engine, state, try scope.get(state, "bodyError"), true);
    };
    return wait(engine, state, pending, 7);
}
fn truth(scope: *Scope, state: c.JSValue, key: [:0]const u8) !bool {
    return c.JS_ToBool(scope.engine.context, try scope.get(state, key)) != 0;
}
fn schedule(engine: *Engine, state: c.JSValue) !void {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    if (try truth(&scope, state, "stopped") or !c.JS_IsUndefined(try scope.get(state, "timer")) or !c.JS_IsUndefined(try scope.get(state, "inFlight"))) return;
    const runtime = try scope.get(state, "runtime");
    const interval = try scope.get(try scope.get(try scope.get(runtime, "settings"), "progress"), "partialIntervalMs");
    var data = [_]c.JSValue{state};
    const callback = try scope.own(try engine.checked(c.JS_NewCFunctionData2(engine.context, flushCallback, "", 0, 0, data.len, &data)));
    const timer = try scope.own(try js.global(engine, "setTimeout"));
    var args = [_]c.JSValue{ callback, interval };
    const id = try scope.own(try engine.checked(c.JS_Call(engine.context, timer, c.pi_js_undefined(), args.len, &args)));
    try put(engine, state, "timer", id);
}
fn flushCallback(context: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue, _: c_int, data: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = Engine.fromContext(context.?);
    flush(engine, data[0]) catch |err| return @import("native_durable.zig").reject(engine, err);
    return c.pi_js_undefined();
}
fn flush(engine: *Engine, state: c.JSValue) !void {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    try put(engine, state, "timer", c.pi_js_undefined());
    const pending = try scope.get(state, "pending");
    try put(engine, state, "pending", c.pi_js_undefined());
    if (c.JS_IsUndefined(pending) or try truth(&scope, state, "stopped")) return;
    const commit = try scope.own(writePartial(engine, state, pending) catch |err| failure: {
        if (err != error.JavaScriptException) return err;
        break :failure try engine.checked(@import("native_durable.zig").rejectedPromise(engine, err));
    });
    const observed = try scope.own(try wait(engine, state, commit, 3));
    const finished = try scope.own(try wait(engine, state, observed, 8));
    try put(engine, state, "inFlight", finished);
}
fn writePartial(engine: *Engine, state: c.JSValue, pending: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const options = try scope.own(try vm.object(engine));
    try put(engine, options, "omitUndefinedProperties", c.pi_js_bool(engine.context, 1));
    try @import("native_tool_info.zig").putData(engine, state, "partialCopy", try @import("native_chord_json.zig").copyJson(engine, pending, options));
    var data = [_]c.JSValue{state};
    const callback = try scope.own(try engine.checked(c.JS_NewCFunctionData2(engine.context, partialCommit, "", 1, 0, data.len, &data)));
    return vm.invoke(engine, try scope.get(state, "runtime"), "commit", &.{ callback, try scope.get(state, "context") });
}
fn partialCommit(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, data: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = Engine.fromContext(context.?);
    return partialDraft(engine, data[0], if (argc > 0) argv[0] else c.pi_js_undefined()) catch |err| @import("native_durable.zig").reject(engine, err);
}
fn partialDraft(engine: *Engine, state: c.JSValue, tx: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const runtime = try scope.get(state, "runtime");
    const pending = try scope.invoke(tx, "doc", &.{ try scope.get(state, "liveToken"), try scope.get(runtime, "conversationId") });
    return wait(engine, state, pending, 4);
}
fn finish(engine: *Engine, state: c.JSValue, value: c.JSValue, rejected: bool) anyerror!c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    try put(engine, state, "stopped", c.pi_js_bool(engine.context, 1));
    try put(engine, state, "finalValue", value);
    try put(engine, state, "finalRejected", c.pi_js_bool(engine.context, @intFromBool(rejected)));
    const timer = try scope.get(state, "timer");
    const clear = try scope.own(try js.global(engine, "clearTimeout"));
    var args = [_]c.JSValue{timer};
    _ = try scope.own(try engine.checked(c.JS_Call(engine.context, clear, c.pi_js_undefined(), 1, &args)));
    try put(engine, state, "timer", c.pi_js_undefined());
    return wait(engine, state, try scope.get(state, "inFlight"), 5);
}
