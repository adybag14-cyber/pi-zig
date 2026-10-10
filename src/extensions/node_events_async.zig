//! Native async Node event subscriptions. Callback closures own genuine JS
//! values and promise capabilities; public receiver methods remain observable.
const std = @import("std");
const js = @import("native_js_values.zig");
const c = js.c;
const v = @import("native_select_list.zig");
const events = @import("node_events.zig");
const Method = enum(c_int) { once, resolve, reject, abort, addAbort, disposeAbort };
fn fail(engine: *js.Engine, err: anyerror) c.JSValue {
    if (err == error.JavaScriptException) return engine.throwCaptured();
    if (err == error.OutOfMemory) return c.JS_ThrowOutOfMemory(engine.context);
    return c.JS_ThrowTypeError(engine.context, "Native async events: %s", @as([*:0]const u8, @errorName(err)));
}
fn invalid(engine: *js.Engine, value: c.JSValue, name: []const u8, expected: []const u8, property: bool) anyerror {
    const received = try events.description(engine, value);
    defer engine.gpa.free(received);
    const message = try std.fmt.allocPrint(engine.gpa, "The \"{s}\" {s} must be {s}. Received {s}", .{ name, if (property) "property" else "argument", expected, received });
    defer engine.gpa.free(message);
    return events.codedError(engine, "TypeError", "ERR_INVALID_ARG_TYPE", message);
}
fn checkedGet(engine: *js.Engine, object: c.JSValue, name: [*:0]const u8) !c.JSValue {
    if (c.JS_IsNull(object) or c.JS_IsUndefined(object)) {
        _ = try engine.checked(c.JS_ThrowTypeError(engine.context, "Cannot read properties of %s (reading '%s')", @as([*:0]const u8, if (c.JS_IsNull(object)) "null" else "undefined"), name));
        unreachable;
    }
    return js.get(engine, object, name);
}
pub fn addListener(engine: *js.Engine, emitter: c.JSValue, name: c.JSValue, listener: c.JSValue, once: bool, resist: c.JSValue) !void {
    const on = try checkedGet(engine, emitter, "on");
    defer engine.freeValue(on);
    if (c.JS_IsFunction(engine.context, on)) {
        const result = try js.invoke(engine, emitter, if (once) "once" else "on", &.{ name, listener });
        engine.freeValue(result);
    } else {
        const add = try js.get(engine, emitter, "addEventListener");
        defer engine.freeValue(add);
        if (!c.JS_IsFunction(engine.context, add)) return invalid(engine, emitter, "emitter", "an instance of EventEmitter", false);
        const flags = try engine.checked(c.JS_NewObjectProto(engine.context, c.pi_js_null()));
        defer engine.freeValue(flags);
        try js.define(engine, flags, "once", c.pi_js_bool(engine.context, @intFromBool(once)));
        if (!c.JS_IsUndefined(resist)) try js.setKey(engine, flags, resist, c.pi_js_bool(engine.context, 1));
        const result = try js.invoke(engine, emitter, "addEventListener", &.{ name, listener, flags });
        engine.freeValue(result);
    }
}
pub fn removeListener(engine: *js.Engine, emitter: c.JSValue, name: c.JSValue, listener: c.JSValue) !void {
    const remove = try checkedGet(engine, emitter, "removeListener");
    defer engine.freeValue(remove);
    if (c.JS_IsFunction(engine.context, remove)) {
        const result = try js.invoke(engine, emitter, "removeListener", &.{ name, listener });
        engine.freeValue(result);
    } else {
        const remove_event = try js.get(engine, emitter, "removeEventListener");
        defer engine.freeValue(remove_event);
        if (!c.JS_IsFunction(engine.context, remove_event)) return invalid(engine, emitter, "emitter", "an instance of EventEmitter", false);
        const result = try js.invoke(engine, emitter, "removeEventListener", &.{ name, listener, c.pi_js_undefined() });
        engine.freeValue(result);
    }
}
pub fn validateSignal(engine: *js.Engine, signal: c.JSValue, name: []const u8) !void {
    if (c.JS_IsUndefined(signal)) return;
    const aborted = try v.text(engine, "aborted");
    defer engine.freeValue(aborted);
    if (c.JS_IsNull(signal) or !c.JS_IsObject(signal) or c.JS_IsFunction(engine.context, signal) or !try js.hasKey(engine, signal, aborted)) return invalid(engine, signal, name, "an instance of AbortSignal", std.mem.indexOfScalar(u8, name, '.') != null);
}
pub fn abortError(engine: *js.Engine, signal: c.JSValue) !c.JSValue {
    const message = try v.text(engine, "The operation was aborted");
    defer engine.freeValue(message);
    const value = try js.builtin(engine, "Error", &.{message});
    errdefer engine.freeValue(value);
    try js.define(engine, value, "name", try v.text(engine, "AbortError"));
    try js.define(engine, value, "code", try v.text(engine, "ABORT_ERR"));
    const reason = if (!c.JS_IsNull(signal) and !c.JS_IsUndefined(signal)) try js.get(engine, signal, "reason") else c.pi_js_undefined();
    if (c.JS_DefinePropertyValueStr(engine.context, value, "cause", reason, c.JS_PROP_CONFIGURABLE | c.JS_PROP_WRITABLE) < 0) return js.capture(engine);
    return value;
}
fn function(engine: *js.Engine, holder: c.JSValue, method: Method, name: [*:0]const u8, length: c_int) !c.JSValue {
    if (method == .abort) return @import("native_node_function.zig").create(engine, name, length, ordinaryAbortListener, &.{holder});
    var data = [_]c.JSValue{holder};
    return engine.checked(c.JS_NewCFunctionData2(engine.context, call, name, length, @intFromEnum(method), 1, &data));
}
fn ordinaryAbortListener(engine: *js.Engine, _: c.JSValue, args: []const c.JSValue, values: []const c.JSValue) anyerror!c.JSValue {
    return callback(engine, values[0], .abort, args);
}
fn call(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, magic: c_int, data: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = js.Engine.fromContext(context.?);
    const args: []const c.JSValue = if (argc > 0) argv[0..@intCast(argc)] else &.{};
    const method: Method = @enumFromInt(magic);
    if (method == .once) return createOnce(engine, args, data[0]) catch |err| fail(engine, err);
    if (method == .addAbort) return addAbort(engine, args, data[0]) catch |err| fail(engine, err);
    if (method == .disposeAbort) return disposeAbort(engine, data[0]) catch |err| fail(engine, err);
    return callback(engine, data[0], @enumFromInt(magic), args) catch |err| fail(engine, err);
}
fn callback(engine: *js.Engine, holder: c.JSValue, method: Method, args: []const c.JSValue) !c.JSValue {
    const emitter = try js.get(engine, holder, "emitter");
    defer engine.freeValue(emitter);
    const name = try js.get(engine, holder, "name");
    defer engine.freeValue(name);
    const signal = try js.get(engine, holder, "signal");
    defer engine.freeValue(signal);
    const resolve_listener = try js.get(engine, holder, "resolver");
    defer engine.freeValue(resolve_listener);
    const error_listener = try js.get(engine, holder, "errorListener");
    defer engine.freeValue(error_listener);
    const error_name = try v.text(engine, "error");
    defer engine.freeValue(error_name);
    if (method == .resolve) {
        const remove = try js.get(engine, emitter, "removeListener");
        defer engine.freeValue(remove);
        if (c.JS_IsFunction(engine.context, remove)) {
            const result = try js.invoke(engine, emitter, "removeListener", &.{ error_name, error_listener });
            engine.freeValue(result);
        }
    } else if (method == .reject) {
        const result = try js.invoke(engine, emitter, "removeListener", &.{ name, resolve_listener });
        engine.freeValue(result);
    } else {
        try removeListener(engine, emitter, name, resolve_listener);
        try removeListener(engine, emitter, error_name, error_listener);
    }
    if (method != .abort and !c.JS_IsNull(signal) and !c.JS_IsUndefined(signal)) {
        const abort_name = try v.text(engine, "abort");
        defer engine.freeValue(abort_name);
        const listener = try js.get(engine, holder, "abortListener");
        defer engine.freeValue(listener);
        try removeListener(engine, signal, abort_name, listener);
    }
    const settle = try js.get(engine, holder, if (method == .resolve) "resolve" else "reject");
    defer engine.freeValue(settle);
    const value = if (method == .resolve) blk: {
        const array = try js.array(engine);
        errdefer engine.freeValue(array);
        for (args, 0..) |item, index| if (c.JS_DefinePropertyValueUint32(engine.context, array, @intCast(index), c.JS_DupValue(engine.context, item), c.JS_PROP_C_W_E) < 0) return js.capture(engine);
        break :blk array;
    } else if (method == .abort) try abortError(engine, signal) else c.JS_DupValue(engine.context, v.arg(args, 0));
    defer engine.freeValue(value);
    const result = try js.call(engine, settle, c.pi_js_undefined(), &.{value});
    engine.freeValue(result);
    return c.pi_js_undefined();
}
fn setupOnce(engine: *js.Engine, holder: c.JSValue, args: []const c.JSValue) !void {
    const emitter = v.arg(args, 0);
    const name = v.arg(args, 1);
    const options = v.arg(args, 2);
    if (!c.JS_IsUndefined(options) and (c.JS_IsNull(options) or !c.JS_IsObject(options) or c.JS_IsArray(options) or c.JS_IsFunction(engine.context, options))) return invalid(engine, options, "options", "of type object", false);
    const signal = if (c.JS_IsUndefined(options)) c.pi_js_undefined() else try js.get(engine, options, "signal");
    defer engine.freeValue(signal);
    try validateSignal(engine, signal, "options.signal");
    if (!c.JS_IsNull(signal) and !c.JS_IsUndefined(signal)) {
        const aborted = try js.get(engine, signal, "aborted");
        defer engine.freeValue(aborted);
        if (v.truthy(engine, aborted)) {
            _ = try engine.checked(c.JS_Throw(engine.context, try abortError(engine, signal)));
            unreachable;
        }
    }
    try js.define(engine, holder, "emitter", c.JS_DupValue(engine.context, emitter));
    try js.define(engine, holder, "name", c.JS_DupValue(engine.context, name));
    try js.define(engine, holder, "signal", c.JS_DupValue(engine.context, signal));
    const resolver = try function(engine, holder, .resolve, "resolver", 0);
    defer engine.freeValue(resolver);
    const error_listener = try function(engine, holder, .reject, "errorListener", 1);
    defer engine.freeValue(error_listener);
    const abort_listener = try function(engine, holder, .abort, "abortListener", 0);
    defer engine.freeValue(abort_listener);
    try js.define(engine, holder, "resolver", c.JS_DupValue(engine.context, resolver));
    try js.define(engine, holder, "errorListener", c.JS_DupValue(engine.context, error_listener));
    try js.define(engine, holder, "abortListener", c.JS_DupValue(engine.context, abort_listener));
    const resist = try js.get(engine, holder, "resist");
    defer engine.freeValue(resist);
    try addListener(engine, emitter, name, resolver, true, resist);
    const error_name = try v.text(engine, "error");
    defer engine.freeValue(error_name);
    if (!c.JS_IsStrictEqual(engine.context, name, error_name)) {
        const once = try js.get(engine, emitter, "once");
        defer engine.freeValue(once);
        if (c.JS_IsFunction(engine.context, once)) {
            const result = try js.invoke(engine, emitter, "once", &.{ error_name, error_listener });
            engine.freeValue(result);
        }
    }
    if (!c.JS_IsNull(signal) and !c.JS_IsUndefined(signal)) {
        const abort_name = try v.text(engine, "abort");
        defer engine.freeValue(abort_name);
        try addListener(engine, signal, abort_name, abort_listener, true, resist);
    }
}
fn createOnce(engine: *js.Engine, args: []const c.JSValue, state: c.JSValue) !c.JSValue {
    var outer_caps: [2]c.JSValue = undefined;
    const outer = try engine.checked(c.JS_NewPromiseCapability(engine.context, &outer_caps));
    errdefer engine.freeValue(outer);
    defer for (outer_caps) |value| engine.freeValue(value);
    var inner_caps: [2]c.JSValue = undefined;
    const inner = try engine.checked(c.JS_NewPromiseCapability(engine.context, &inner_caps));
    defer engine.freeValue(inner);
    defer for (inner_caps) |value| engine.freeValue(value);
    const holder = try js.object(engine);
    defer engine.freeValue(holder);
    try js.define(engine, holder, "resist", try js.get(engine, state, "resistSymbol"));
    try js.define(engine, holder, "resolve", c.JS_DupValue(engine.context, inner_caps[0]));
    try js.define(engine, holder, "reject", c.JS_DupValue(engine.context, inner_caps[1]));
    setupOnce(engine, holder, args) catch |err| {
        if (err != error.JavaScriptException) return err;
        const exception = engine.captured_exception orelse return err;
        engine.captured_exception = null;
        defer engine.freeValue(exception);
        const result = try js.call(engine, outer_caps[1], c.pi_js_undefined(), &.{exception});
        engine.freeValue(result);
        return outer;
    };
    const result = try js.call(engine, outer_caps[0], c.pi_js_undefined(), &.{inner});
    engine.freeValue(result);
    return outer;
}
pub fn onceFunction(engine: *js.Engine, state: c.JSValue) !c.JSValue {
    const callback_value = try function(engine, state, .once, "once", 2);
    errdefer engine.freeValue(callback_value);
    const intrinsic = try engine.checked(c.JS_GetAsyncFunctionPrototype(engine.context));
    defer engine.freeValue(intrinsic);
    if (c.JS_SetPrototype(engine.context, callback_value, intrinsic) < 0) return js.capture(engine);
    return callback_value;
}
fn abortMicrotask(context: ?*c.JSContext, _: c_int, args: [*c]c.JSValue) callconv(.c) c.JSValue {
    return c.JS_Call(context, args[0], c.pi_js_undefined(), 0, null);
}
fn addAbort(engine: *js.Engine, args: []const c.JSValue, state: c.JSValue) !c.JSValue {
    const signal = v.arg(args, 0);
    const listener = v.arg(args, 1);
    if (c.JS_IsUndefined(signal)) return invalid(engine, signal, "signal", "an instance of AbortSignal", false);
    try validateSignal(engine, signal, "signal");
    if (!c.JS_IsFunction(engine.context, listener)) return invalid(engine, listener, "listener", "of type function", false);
    const aborted = try js.get(engine, signal, "aborted");
    defer engine.freeValue(aborted);
    const inactive = v.truthy(engine, aborted);
    if (inactive) {
        var values = [_]c.JSValue{listener};
        if (c.JS_EnqueueJob(engine.context, abortMicrotask, 1, &values) < 0) return js.capture(engine);
    } else {
        const event = try v.text(engine, "abort");
        defer engine.freeValue(event);
        const flags = try engine.checked(c.JS_NewObjectProto(engine.context, c.pi_js_null()));
        defer engine.freeValue(flags);
        try js.define(engine, flags, "once", c.pi_js_bool(engine.context, 1));
        const resist = try js.get(engine, state, "resistSymbol");
        defer engine.freeValue(resist);
        try js.setKey(engine, flags, resist, c.pi_js_bool(engine.context, 1));
        const result = try js.invoke(engine, signal, "addEventListener", &.{ event, listener, flags });
        engine.freeValue(result);
    }
    const holder = try js.object(engine);
    defer engine.freeValue(holder);
    try js.define(engine, holder, "active", c.pi_js_bool(engine.context, @intFromBool(!inactive)));
    try js.define(engine, holder, "signal", c.JS_DupValue(engine.context, signal));
    try js.define(engine, holder, "listener", c.JS_DupValue(engine.context, listener));
    const disposable = try engine.checked(c.JS_NewObjectProto(engine.context, c.pi_js_null()));
    errdefer engine.freeValue(disposable);
    const symbol = try js.global(engine, "Symbol");
    defer engine.freeValue(symbol);
    const dispose = try js.get(engine, symbol, "dispose");
    defer engine.freeValue(dispose);
    const callback_value = try function(engine, holder, .disposeAbort, "[Symbol.dispose]", 0);
    defer engine.freeValue(callback_value);
    try js.setKey(engine, disposable, dispose, callback_value);
    return disposable;
}
fn disposeAbort(engine: *js.Engine, holder: c.JSValue) !c.JSValue {
    const active = try js.get(engine, holder, "active");
    defer engine.freeValue(active);
    if (!v.truthy(engine, active)) return c.pi_js_undefined();
    const signal = try js.get(engine, holder, "signal");
    defer engine.freeValue(signal);
    const listener = try js.get(engine, holder, "listener");
    defer engine.freeValue(listener);
    const event = try v.text(engine, "abort");
    defer engine.freeValue(event);
    const result = try js.invoke(engine, signal, "removeEventListener", &.{ event, listener });
    engine.freeValue(result);
    return c.pi_js_undefined();
}
pub fn addAbortFunction(engine: *js.Engine, state: c.JSValue) !c.JSValue {
    return @import("native_node_function.zig").create(engine, "addAbortListener", 2, ordinaryAbort, &.{state});
}
fn ordinaryAbort(engine: *js.Engine, _: c.JSValue, args: []const c.JSValue, values: []const c.JSValue) anyerror!c.JSValue {
    return addAbort(engine, args, values[0]);
}
