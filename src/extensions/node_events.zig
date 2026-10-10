//! Native Node24 EventEmitter dependency, ordinary fields, async subscriptions
//! and private owner scopes. Host code stays Zig with direct QuickJS C calls.
const std = @import("std");
const js = @import("native_js_values.zig");
const c = js.c;
const v = @import("native_select_list.zig");
const async_scope = @import("native_async_scope.zig");
const Method = enum(c_int) { init, setMaxListeners, getMaxListeners, emit, addListener, prependListener, once, prependOnceListener, removeListener, removeAllListeners, listeners, rawListeners, listenerCount, eventNames, defaultGet, defaultSet, onceWrapper, captureGet, captureSet, staticListeners, staticCount, staticGetMax, staticSetMax };
const Constructor = struct { engine: *js.Engine, state: c.JSValue };
fn fail(engine: *js.Engine, err: anyerror) c.JSValue {
    if (err == error.JavaScriptException) return engine.throwCaptured();
    if (err == error.OutOfMemory) return c.JS_ThrowOutOfMemory(engine.context);
    return c.JS_ThrowTypeError(engine.context, "Native EventEmitter: %s", @as([*:0]const u8, @errorName(err)));
}
fn emptyEvents(engine: *js.Engine) !c.JSValue {
    return engine.checked(c.JS_NewObjectProto(engine.context, c.pi_js_null()));
}
fn equalText(engine: *js.Engine, value: c.JSValue, text: []const u8) !bool {
    const expected = try v.text(engine, text);
    defer engine.freeValue(expected);
    return c.JS_IsStrictEqual(engine.context, value, expected);
}
fn fieldTruthy(engine: *js.Engine, object: c.JSValue, name: [*:0]const u8) !bool {
    const value = try js.get(engine, object, name);
    defer engine.freeValue(value);
    return v.truthy(engine, value);
}
fn invokeVoid(engine: *js.Engine, object: c.JSValue, name: [*:0]const u8, args: []const c.JSValue) !void {
    const value = try js.invoke(engine, object, name, args);
    engine.freeValue(value);
}
fn putAt(engine: *js.Engine, array: c.JSValue, index: u32, value: c.JSValue) !void {
    if (c.JS_DefinePropertyValueUint32(engine.context, array, index, c.JS_DupValue(engine.context, value), c.JS_PROP_C_W_E) < 0) return js.capture(engine);
}
pub fn description(engine: *js.Engine, value: c.JSValue) ![]u8 {
    if (c.JS_IsUndefined(value)) return engine.gpa.dupe(u8, "undefined");
    if (c.JS_IsNull(value)) return engine.gpa.dupe(u8, "null");
    if (c.JS_IsString(value)) {
        const text = try engine.toString(value);
        defer engine.gpa.free(text);
        return std.fmt.allocPrint(engine.gpa, "type string ('{s}')", .{text});
    }
    if (c.JS_IsNumber(value)) {
        const text = try engine.toString(value);
        defer engine.gpa.free(text);
        return std.fmt.allocPrint(engine.gpa, "type number ({s})", .{text});
    }
    if (c.JS_IsBool(value)) return std.fmt.allocPrint(engine.gpa, "type boolean ({s})", .{if (v.truthy(engine, value)) "true" else "false"});
    if (c.JS_IsFunction(engine.context, value)) {
        const name_value = try js.get(engine, value, "name");
        defer engine.freeValue(name_value);
        const name = try engine.toString(name_value);
        defer engine.gpa.free(name);
        return std.fmt.allocPrint(engine.gpa, "function {s}", .{name});
    }
    if (c.JS_IsArray(value)) return engine.gpa.dupe(u8, "an instance of Array");
    return engine.gpa.dupe(u8, "an instance of Object");
}
fn validateBoolean(engine: *js.Engine, value: c.JSValue, name: []const u8) !void {
    if (c.JS_IsBool(value)) return;
    const received = try description(engine, value);
    defer engine.gpa.free(received);
    const message = try std.fmt.allocPrint(engine.gpa, "The \"{s}\" property must be of type boolean. Received {s}", .{ name, received });
    defer engine.gpa.free(message);
    return codedError(engine, "TypeError", "ERR_INVALID_ARG_TYPE", message);
}
fn invalidTarget(engine: *js.Engine, value: c.JSValue, name: []const u8) anyerror {
    const received = try description(engine, value);
    defer engine.gpa.free(received);
    const message = try std.fmt.allocPrint(engine.gpa, "The \"{s}\" argument must be an instance of EventEmitter or EventTarget. Received {s}", .{ name, received });
    defer engine.gpa.free(message);
    return codedError(engine, "TypeError", "ERR_INVALID_ARG_TYPE", message);
}
pub fn codedError(engine: *js.Engine, kind: [*:0]const u8, code: []const u8, message: []const u8) anyerror {
    const text = try v.text(engine, message);
    defer engine.freeValue(text);
    const error_value = try js.builtin(engine, kind, &.{text});
    var transferred = false;
    errdefer if (!transferred) engine.freeValue(error_value);
    try js.define(engine, error_value, "code", try v.text(engine, code));
    transferred = true;
    _ = engine.checked(c.JS_Throw(engine.context, error_value)) catch |err| return err;
    unreachable;
}
fn validateListener(engine: *js.Engine, value: c.JSValue) !void {
    if (c.JS_IsFunction(engine.context, value)) return;
    const received = try description(engine, value);
    defer engine.gpa.free(received);
    const message = try std.fmt.allocPrint(engine.gpa, "The \"listener\" argument must be of type function. Received {s}", .{received});
    defer engine.gpa.free(message);
    return codedError(engine, "TypeError", "ERR_INVALID_ARG_TYPE", message);
}
fn validateMax(engine: *js.Engine, value: c.JSValue, name: []const u8) !void {
    if (!c.JS_IsNumber(value)) {
        const received = try description(engine, value);
        defer engine.gpa.free(received);
        const message = try std.fmt.allocPrint(engine.gpa, "The \"{s}\" argument must be of type number. Received {s}", .{ name, received });
        defer engine.gpa.free(message);
        return codedError(engine, "TypeError", "ERR_INVALID_ARG_TYPE", message);
    }
    const number = try v.number(engine, value);
    if (number < 0 or std.math.isNan(number)) {
        const received = try engine.toString(value);
        defer engine.gpa.free(received);
        const message = try std.fmt.allocPrint(engine.gpa, "The value of \"{s}\" is out of range. It must be >= 0. Received {s}", .{ name, received });
        defer engine.gpa.free(message);
        return codedError(engine, "RangeError", "ERR_OUT_OF_RANGE", message);
    }
}
fn copyListeners(engine: *js.Engine, list: c.JSValue, unwrap: bool) !c.JSValue {
    const result = try js.array(engine);
    errdefer engine.freeValue(result);
    const single = c.JS_IsFunction(engine.context, list);
    const count: u32 = if (single) 1 else @intFromFloat(try v.numberField(engine, list, "length"));
    if (count > 65536) return error.NativeEventListenerLimit;
    for (0..count) |index| {
        const value = if (single) c.JS_DupValue(engine.context, list) else try engine.checked(c.JS_GetPropertyUint32(engine.context, list, @intCast(index)));
        defer engine.freeValue(value);
        if (unwrap) {
            const original = try js.get(engine, value, "listener");
            defer engine.freeValue(original);
            try putAt(engine, result, @intCast(index), if (v.truthy(engine, original)) original else value);
        } else try putAt(engine, result, @intCast(index), value);
    }
    return result;
}
fn applyListener(engine: *js.Engine, function: c.JSValue, receiver: c.JSValue, args: []const c.JSValue) !c.JSValue {
    const apply = try js.get(engine, function, "apply");
    defer engine.freeValue(apply);
    const array = try js.array(engine);
    defer engine.freeValue(array);
    for (args, 0..) |value, index| try putAt(engine, array, @intCast(index), value);
    return js.call(engine, apply, function, &.{ receiver, array });
}
fn maxListeners(engine: *js.Engine, object: c.JSValue, state: c.JSValue) !c.JSValue {
    const value = try js.get(engine, object, "_maxListeners");
    if (!c.JS_IsUndefined(value)) {
        engine.freeValue(value);
        return js.get(engine, object, "_maxListeners");
    }
    engine.freeValue(value);
    const constructor = try js.get(engine, state, "constructor");
    defer engine.freeValue(constructor);
    return js.get(engine, constructor, "defaultMaxListeners");
}
fn add(engine: *js.Engine, object: c.JSValue, type_value: c.JSValue, listener: c.JSValue, prepend: bool, state: c.JSValue) !c.JSValue {
    try validateListener(engine, listener);
    var events = try js.get(engine, object, "_events");
    defer engine.freeValue(events);
    var existing = c.pi_js_undefined();
    defer engine.freeValue(existing);
    if (c.JS_IsUndefined(events)) {
        engine.freeValue(events);
        events = try emptyEvents(engine);
        try v.set(engine, object, "_events", c.JS_DupValue(engine.context, events));
        try v.set(engine, object, "_eventsCount", c.JS_NewInt32(engine.context, 0));
    } else {
        const new_listener = try js.get(engine, events, "newListener");
        defer engine.freeValue(new_listener);
        if (!c.JS_IsUndefined(new_listener)) {
            const original = try js.get(engine, listener, "listener");
            defer engine.freeValue(original);
            const name = try v.text(engine, "newListener");
            defer engine.freeValue(name);
            try invokeVoid(engine, object, "emit", &.{ name, type_value, if (c.JS_IsNull(original) or c.JS_IsUndefined(original)) listener else original });
            const current = try js.get(engine, object, "_events");
            engine.freeValue(events);
            events = current;
        }
        existing = try js.getKey(engine, events, type_value);
    }
    if (c.JS_IsUndefined(existing)) {
        try js.setKey(engine, events, type_value, listener);
        try v.set(engine, object, "_eventsCount", v.numeric(engine, try v.numberField(engine, object, "_eventsCount") + 1));
    } else {
        if (c.JS_IsFunction(engine.context, existing)) {
            const array = try js.array(engine);
            errdefer engine.freeValue(array);
            try putAt(engine, array, 0, if (prepend) listener else existing);
            try putAt(engine, array, 1, if (prepend) existing else listener);
            try js.setKey(engine, events, type_value, array);
            engine.freeValue(existing);
            existing = array;
        } else try invokeVoid(engine, existing, if (prepend) "unshift" else "push", &.{listener});
        const maximum = try maxListeners(engine, object, state);
        defer engine.freeValue(maximum);
        if (try v.number(engine, maximum) > 0 and try v.numberField(engine, existing, "length") > try v.number(engine, maximum) and !try fieldTruthy(engine, existing, "warned")) {
            try v.set(engine, existing, "warned", c.pi_js_bool(engine.context, 1));
            const count = try v.numberField(engine, existing, "length");
            const string = try js.global(engine, "String");
            defer engine.freeValue(string);
            const type_string = try js.call(engine, string, c.pi_js_undefined(), &.{type_value});
            defer engine.freeValue(type_string);
            const type_text = try engine.toString(type_string);
            defer engine.gpa.free(type_text);
            const inspected = try @import("node_event_inspect.zig").inspect(engine, object, -1);
            defer engine.gpa.free(inspected);
            const max_text = try engine.toString(maximum);
            defer engine.gpa.free(max_text);
            const message = try std.fmt.allocPrint(engine.gpa, "Possible EventEmitter memory leak detected. {d} {s} listeners added to {s}. MaxListeners is {s}. Use emitter.setMaxListeners() to increase limit", .{ @as(u32, @intFromFloat(count)), type_text, inspected, max_text });
            defer engine.gpa.free(message);
            const text = try v.text(engine, message);
            defer engine.freeValue(text);
            const warning = try js.builtin(engine, "Error", &.{text});
            defer engine.freeValue(warning);
            try js.define(engine, warning, "name", try v.text(engine, "MaxListenersExceededWarning"));
            try js.define(engine, warning, "emitter", c.JS_DupValue(engine.context, object));
            try js.define(engine, warning, "type", c.JS_DupValue(engine.context, type_value));
            try js.define(engine, warning, "count", v.numeric(engine, count));
            const process = try js.global(engine, "process");
            defer engine.freeValue(process);
            try invokeVoid(engine, process, "emitWarning", &.{warning});
        }
    }
    return c.JS_DupValue(engine.context, object);
}
fn once(engine: *js.Engine, object: c.JSValue, type_value: c.JSValue, listener: c.JSValue, prepend: bool, state: c.JSValue) !c.JSValue {
    try validateListener(engine, listener);
    const holder = try js.object(engine);
    defer engine.freeValue(holder);
    try js.define(engine, holder, "fired", c.pi_js_bool(engine.context, 0));
    try js.define(engine, holder, "wrapFn", c.pi_js_undefined());
    try js.define(engine, holder, "target", c.JS_DupValue(engine.context, object));
    try js.define(engine, holder, "type", c.JS_DupValue(engine.context, type_value));
    try js.define(engine, holder, "listener", c.JS_DupValue(engine.context, listener));
    const wrapper = try @import("native_node_function.zig").create(engine, "onceWrapper", 0, ordinaryOnceWrapper, &.{ state, holder });
    defer engine.freeValue(wrapper);
    const bind = try js.get(engine, state, "functionBind");
    defer engine.freeValue(bind);
    const wrapped = try js.call(engine, bind, wrapper, &.{holder});
    defer engine.freeValue(wrapped);
    try js.define(engine, wrapped, "listener", c.JS_DupValue(engine.context, listener));
    try v.set(engine, holder, "wrapFn", c.JS_DupValue(engine.context, wrapped));
    try invokeVoid(engine, object, if (prepend) "prependListener" else "on", &.{ type_value, wrapped });
    return c.JS_DupValue(engine.context, object);
}
fn ordinaryOnceWrapper(engine: *js.Engine, receiver: c.JSValue, args: []const c.JSValue, values: []const c.JSValue) anyerror!c.JSValue {
    return operation(engine, receiver, .onceWrapper, args, values[0], values[1]);
}
fn deleteKey(engine: *js.Engine, object: c.JSValue, key: c.JSValue) !void {
    const atom = try js.atom(engine, key);
    defer c.JS_FreeAtom(engine.context, atom);
    if (c.JS_DeleteProperty(engine.context, object, atom, c.JS_PROP_THROW) < 0) return js.capture(engine);
}
fn remove(engine: *js.Engine, object: c.JSValue, type_value: c.JSValue, listener: c.JSValue, state: c.JSValue) !c.JSValue {
    try validateListener(engine, listener);
    const events = try js.get(engine, object, "_events");
    defer engine.freeValue(events);
    if (c.JS_IsUndefined(events)) return c.JS_DupValue(engine.context, object);
    const list = try js.getKey(engine, events, type_value);
    defer engine.freeValue(list);
    if (c.JS_IsUndefined(list)) return c.JS_DupValue(engine.context, object);
    var matches = c.JS_IsStrictEqual(engine.context, list, listener);
    if (!matches) {
        const original = try js.get(engine, list, "listener");
        defer engine.freeValue(original);
        matches = c.JS_IsStrictEqual(engine.context, original, listener);
    }
    if (matches) {
        try v.set(engine, object, "_eventsCount", v.numeric(engine, try v.numberField(engine, object, "_eventsCount") - 1));
        const shape = try js.get(engine, state, "shapeSymbol");
        defer engine.freeValue(shape);
        const value = try js.getKey(engine, object, shape);
        defer engine.freeValue(value);
        if (v.truthy(engine, value)) try js.setKey(engine, events, type_value, c.pi_js_undefined()) else if (try v.numberField(engine, object, "_eventsCount") == 0) try v.set(engine, object, "_events", try emptyEvents(engine)) else try deleteKey(engine, events, type_value);
        const removing = try js.get(engine, events, "removeListener");
        defer engine.freeValue(removing);
        if (!c.JS_IsUndefined(removing)) {
            const name = try v.text(engine, "removeListener");
            defer engine.freeValue(name);
            const original = try js.get(engine, list, "listener");
            defer engine.freeValue(original);
            try invokeVoid(engine, object, "emit", &.{ name, type_value, if (v.truthy(engine, original)) original else listener });
        }
    } else if (!c.JS_IsFunction(engine.context, list)) {
        var index = try v.numberField(engine, list, "length") - 1;
        var position: f64 = -1;
        while (index >= 0) : (index -= 1) {
            const value = try js.getKey(engine, list, v.numeric(engine, index));
            defer engine.freeValue(value);
            if (c.JS_IsStrictEqual(engine.context, value, listener)) {
                position = index;
                break;
            }
            const unwrapped = try js.get(engine, value, "listener");
            defer engine.freeValue(unwrapped);
            if (c.JS_IsStrictEqual(engine.context, unwrapped, listener)) {
                position = index;
                break;
            }
        }
        if (position < 0) return c.JS_DupValue(engine.context, object);
        if (position == 0) try invokeVoid(engine, list, "shift", &.{}) else {
            const length = try v.numberField(engine, list, "length");
            var at = position;
            while (at < length - 1) : (at += 1) {
                const value = try js.getKey(engine, list, v.numeric(engine, at + 1));
                defer engine.freeValue(value);
                try js.setKey(engine, list, v.numeric(engine, at), value);
            }
            try v.set(engine, list, "length", v.numeric(engine, length - 1));
        }
        if (try v.numberField(engine, list, "length") == 1) {
            const value = try js.getKey(engine, list, c.JS_NewInt32(engine.context, 0));
            defer engine.freeValue(value);
            try js.setKey(engine, events, type_value, value);
        }
        const removing = try js.get(engine, events, "removeListener");
        defer engine.freeValue(removing);
        if (!c.JS_IsUndefined(removing)) {
            const name = try v.text(engine, "removeListener");
            defer engine.freeValue(name);
            try invokeVoid(engine, object, "emit", &.{ name, type_value, listener });
        }
    }
    return c.JS_DupValue(engine.context, object);
}
fn dispatchRejection(engine: *js.Engine, entry: c.JSValue, state: c.JSValue) !void {
    const object = try js.get(engine, entry, "object");
    defer engine.freeValue(object);
    const reason = try js.get(engine, entry, "reason");
    defer engine.freeValue(reason);
    const rejection_symbol = try js.get(engine, state, "rejectionSymbol");
    defer engine.freeValue(rejection_symbol);
    const handler = try js.getKey(engine, object, rejection_symbol);
    defer engine.freeValue(handler);
    if (c.JS_IsFunction(engine.context, handler)) {
        const actual = try js.getKey(engine, object, rejection_symbol);
        defer engine.freeValue(actual);
        const type_value = try js.get(engine, entry, "type");
        defer engine.freeValue(type_value);
        const arguments = try js.get(engine, entry, "args");
        defer engine.freeValue(arguments);
        var values: std.ArrayList(c.JSValue) = .empty;
        defer values.deinit(engine.gpa);
        try values.appendSlice(engine.gpa, &.{ reason, type_value });
        const count: usize = @intFromFloat(try v.numberField(engine, arguments, "length"));
        if (count > 65536) return error.NativeEventListenerLimit;
        defer for (values.items[2..]) |value| engine.freeValue(value);
        for (0..count) |index| {
            const value = try engine.checked(c.JS_GetPropertyUint32(engine.context, arguments, @intCast(index)));
            errdefer engine.freeValue(value);
            try values.append(engine.gpa, value);
        }
        const result = try js.call(engine, actual, object, values.items);
        engine.freeValue(result);
    } else {
        const capture_symbol = try js.get(engine, state, "captureSymbol");
        defer engine.freeValue(capture_symbol);
        const previous = try js.getKey(engine, object, capture_symbol);
        defer engine.freeValue(previous);
        try js.setKey(engine, object, capture_symbol, c.pi_js_bool(engine.context, 0));
        const name = try v.text(engine, "error");
        defer engine.freeValue(name);
        invokeVoid(engine, object, "emit", &.{ name, reason }) catch |err| {
            const original = engine.captured_exception;
            engine.captured_exception = null;
            js.setKey(engine, object, capture_symbol, previous) catch |restore_err| {
                if (original) |value| engine.freeValue(value);
                return restore_err;
            };
            engine.captured_exception = original;
            return err;
        };
        try js.setKey(engine, object, capture_symbol, previous);
    }
}
fn scheduleDrain(engine: *js.Engine, state: c.JSValue) !void {
    const generation = v.numeric(engine, try v.numberField(engine, state, "tickGeneration") + 1);
    try v.set(engine, state, "tickGeneration", generation);
    var data = [_]c.JSValue{ state, generation };
    if (c.JS_EnqueueJob(engine.context, rejectionDrainJob, 2, &data) < 0) return js.capture(engine);
    try v.set(engine, state, "rejectionScheduled", c.pi_js_bool(engine.context, 1));
}
fn drainRejections(engine: *js.Engine, state: c.JSValue, host_boundary: bool) !c.JSValue {
    // Node's rejection handler runs in nextTick after the current microtask
    // checkpoint. One drain per module avoids competing drains that would
    // perpetually see each other as pending work. Each entry retains its own
    // private owner scope; batching never replaces that scope with the first.
    if (!try fieldTruthy(engine, state, "rejectionScheduled")) return c.pi_js_undefined();
    if (!host_boundary and c.JS_IsJobPending(engine.runtime)) {
        const generation = try js.get(engine, state, "tickGeneration");
        defer engine.freeValue(generation);
        var data = [_]c.JSValue{ state, generation };
        if (c.JS_EnqueueJob(engine.context, rejectionDrainJob, 2, &data) < 0) return js.capture(engine);
        return c.pi_js_undefined();
    }
    const queue = try js.get(engine, state, "rejections");
    defer engine.freeValue(queue);
    var index: u32 = 0;
    errdefer {
        v.set(engine, state, "rejectionScheduled", c.pi_js_bool(engine.context, 0)) catch {};
        v.set(engine, queue, "length", c.JS_NewInt32(engine.context, 0)) catch {};
    }
    while (@as(f64, @floatFromInt(index)) < try v.numberField(engine, queue, "length")) : (index += 1) {
        if (index >= engine.options.job_budget) return error.JavaScriptJobLimit;
        if (engine.cancelled.load(.acquire)) return error.JavaScriptInterrupted;
        const entry = try engine.checked(c.JS_GetPropertyUint32(engine.context, queue, index));
        defer engine.freeValue(entry);
        const scope = try js.get(engine, entry, "scope");
        defer engine.freeValue(scope);
        var guard = async_scope.enter(engine, scope);
        defer guard.restore();
        const callback = try js.get(engine, entry, "callback");
        defer engine.freeValue(callback);
        if (c.JS_IsUndefined(callback)) try dispatchRejection(engine, entry, state) else {
            const arguments = try js.get(engine, entry, "args");
            defer engine.freeValue(arguments);
            var values: std.ArrayList(c.JSValue) = .empty;
            defer {
                for (values.items) |value| engine.freeValue(value);
                values.deinit(engine.gpa);
            }
            const count: u32 = @intFromFloat(try v.numberField(engine, arguments, "length"));
            if (count > 65536) return error.NativeEventListenerLimit;
            for (0..count) |at| {
                const value = try engine.checked(c.JS_GetPropertyUint32(engine.context, arguments, @intCast(at)));
                errdefer engine.freeValue(value);
                try values.append(engine.gpa, value);
            }
            const result = try js.call(engine, callback, c.pi_js_undefined(), values.items);
            engine.freeValue(result);
        }
    }
    try v.set(engine, queue, "length", c.JS_NewInt32(engine.context, 0));
    try v.set(engine, state, "rejectionScheduled", c.pi_js_bool(engine.context, 0));
    return c.pi_js_undefined();
}
fn rejectionDrainJob(context: ?*c.JSContext, _: c_int, args: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = js.Engine.fromContext(context.?);
    const generation = js.get(engine, args[0], "tickGeneration") catch |err| return fail(engine, err);
    defer engine.freeValue(generation);
    // A host boundary may have drained this job's queue already. A new queue
    // owns a later generation; stale jobs must not become competing drains.
    if (!c.JS_IsStrictEqual(context, generation, args[1])) return c.pi_js_undefined();
    return drainRejections(engine, args[0], false) catch |err| fail(engine, err);
}
fn rejectionCallback(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, data: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = js.Engine.fromContext(context.?);
    return enqueueRejection(engine, data, if (argc > 0) argv[0] else c.pi_js_undefined()) catch |err| fail(engine, err);
}
fn enqueueRejection(engine: *js.Engine, data: [*c]c.JSValue, reason: c.JSValue) !c.JSValue {
    const state = data[0];
    const process = try js.global(engine, "process");
    defer engine.freeValue(process);
    if (!c.JS_IsUndefined(process)) {
        var function_data = [_]c.JSValue{state};
        const callback = try engine.checked(c.JS_NewCFunctionData2(engine.context, dispatchRejectionCall, "emitUnhandledRejectionOrErr", 4, 0, 1, &function_data));
        defer engine.freeValue(callback);
        const result = try js.invoke(engine, process, "nextTick", &.{ callback, data[1], reason, data[2], data[3] });
        engine.freeValue(result);
        return c.pi_js_undefined();
    }
    const queue = try js.get(engine, state, "rejections");
    defer engine.freeValue(queue);
    const entry = try js.object(engine);
    defer engine.freeValue(entry);
    try js.define(engine, entry, "object", c.JS_DupValue(engine.context, data[1]));
    try js.define(engine, entry, "type", c.JS_DupValue(engine.context, data[2]));
    try js.define(engine, entry, "args", c.JS_DupValue(engine.context, data[3]));
    try js.define(engine, entry, "reason", c.JS_DupValue(engine.context, reason));
    try js.define(engine, entry, "scope", async_scope.capture(engine));
    const length: u32 = @intFromFloat(try v.numberField(engine, queue, "length"));
    if (length >= 65536) return error.NativeEventListenerLimit;
    try putAt(engine, queue, length, entry);
    if (!try fieldTruthy(engine, state, "rejectionScheduled")) {
        try scheduleDrain(engine, state);
    }
    return c.pi_js_undefined();
}
fn dispatchRejectionCall(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, data: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = js.Engine.fromContext(context.?);
    return dispatchRejectionArguments(engine, data[0], if (argc > 0) argv[0..@intCast(argc)] else &.{}) catch |err| fail(engine, err);
}
fn dispatchRejectionArguments(engine: *js.Engine, state: c.JSValue, args: []const c.JSValue) !c.JSValue {
    const entry = try js.object(engine);
    defer engine.freeValue(entry);
    inline for (.{ "object", "reason", "type", "args" }, 0..) |name, index| try js.define(engine, entry, name, c.JS_DupValue(engine.context, v.arg(args, index)));
    try dispatchRejection(engine, entry, state);
    return c.pi_js_undefined();
}
fn tickCall(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, data: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = js.Engine.fromContext(context.?);
    return enqueueTick(engine, data[0], data[1], if (argc > 0) argv[0..@intCast(argc)] else &.{}) catch |err| fail(engine, err);
}
fn ordinaryTick(engine: *js.Engine, _: c.JSValue, args: []const c.JSValue, values: []const c.JSValue) anyerror!c.JSValue {
    return enqueueTick(engine, values[0], values[1], args);
}
fn enqueueTick(engine: *js.Engine, state: c.JSValue, process: c.JSValue, args: []const c.JSValue) !c.JSValue {
    const callback = v.arg(args, 0);
    if (!c.JS_IsFunction(engine.context, callback)) {
        const received = try description(engine, callback);
        defer engine.gpa.free(received);
        const message = try std.fmt.allocPrint(engine.gpa, "The \"callback\" argument must be of type function. Received {s}", .{received});
        defer engine.gpa.free(message);
        return codedError(engine, "TypeError", "ERR_INVALID_ARG_TYPE", message);
    }
    if (try fieldTruthy(engine, process, "_exiting")) return c.pi_js_undefined();
    const queue = try js.get(engine, state, "rejections");
    defer engine.freeValue(queue);
    const entry = try js.object(engine);
    defer engine.freeValue(entry);
    try js.define(engine, entry, "callback", c.JS_DupValue(engine.context, callback));
    try js.define(engine, entry, "scope", async_scope.capture(engine));
    const arguments = try js.array(engine);
    defer engine.freeValue(arguments);
    if (args.len > 1) for (args[1..], 0..) |value, index| try putAt(engine, arguments, @intCast(index), value);
    try js.define(engine, entry, "args", c.JS_DupValue(engine.context, arguments));
    const length: u32 = @intFromFloat(try v.numberField(engine, queue, "length"));
    if (length >= 65536) return error.NativeEventListenerLimit;
    try putAt(engine, queue, length, entry);
    if (!try fieldTruthy(engine, state, "rejectionScheduled")) {
        try scheduleDrain(engine, state);
    }
    return c.pi_js_undefined();
}
pub fn nextTickFunction(engine: *js.Engine, process: c.JSValue) !c.JSValue {
    try install(engine);
    const exports = engine.native_module_values.get("node:events") orelse return error.NativeEventEmitterMissing;
    const constructor = try js.get(engine, exports, "EventEmitter");
    defer engine.freeValue(constructor);
    const owner: *Constructor = @ptrCast(@alignCast(c.JS_GetOpaque(constructor, c.JS_GetClassID(constructor)) orelse return error.NativeEventEmitterMissing));
    return @import("native_node_function.zig").create(engine, "nextTick", 1, ordinaryTick, &.{ owner.state, process });
}
pub fn drainHostTicks(engine: *js.Engine) !void {
    const exports = engine.native_module_values.get("node:events") orelse return;
    const constructor = try js.get(engine, exports, "EventEmitter");
    defer engine.freeValue(constructor);
    const owner: *Constructor = @ptrCast(@alignCast(c.JS_GetOpaque(constructor, c.JS_GetClassID(constructor)) orelse return error.NativeEventEmitterMissing));
    const result = try drainRejections(engine, owner.state, true);
    engine.freeValue(result);
}
fn captureThen(engine: *js.Engine, object: c.JSValue, promise: c.JSValue, args: []const c.JSValue, state: c.JSValue) !void {
    const then = try js.get(engine, promise, "then");
    defer engine.freeValue(then);
    if (!c.JS_IsFunction(engine.context, then)) return;
    const arguments = try js.array(engine);
    defer engine.freeValue(arguments);
    if (args.len > 1) for (args[1..], 0..) |value, index| try putAt(engine, arguments, @intCast(index), value);
    var data = [_]c.JSValue{ state, object, v.arg(args, 0), arguments };
    const callback = try engine.checked(c.JS_NewCFunctionData2(engine.context, rejectionCallback, "", 1, 0, data.len, &data));
    defer engine.freeValue(callback);
    const result = try js.invoke(engine, then, "call", &.{ promise, c.pi_js_undefined(), callback });
    engine.freeValue(result);
}
fn addCatch(engine: *js.Engine, object: c.JSValue, promise: c.JSValue, args: []const c.JSValue, state: c.JSValue) !void {
    const capture_symbol = try js.get(engine, state, "captureSymbol");
    defer engine.freeValue(capture_symbol);
    const capture = try js.getKey(engine, object, capture_symbol);
    defer engine.freeValue(capture);
    if (!v.truthy(engine, capture)) return;
    captureThen(engine, object, promise, args, state) catch |err| {
        if (err != error.JavaScriptException) return err;
        const reason = engine.captured_exception orelse return err;
        engine.captured_exception = null;
        defer engine.freeValue(reason);
        const name = try v.text(engine, "error");
        defer engine.freeValue(name);
        try invokeVoid(engine, object, "emit", &.{ name, reason });
    };
}
fn emit(engine: *js.Engine, object: c.JSValue, args: []const c.JSValue, state: c.JSValue) !c.JSValue {
    const type_value = v.arg(args, 0);
    var do_error = try equalText(engine, type_value, "error");
    const events = try js.get(engine, object, "_events");
    defer engine.freeValue(events);
    if (!c.JS_IsUndefined(events)) {
        if (do_error) {
            const monitor = try js.get(engine, state, "errorMonitor");
            defer engine.freeValue(monitor);
            const handler = try js.getKey(engine, events, monitor);
            defer engine.freeValue(handler);
            if (!c.JS_IsUndefined(handler)) {
                var values: std.ArrayList(c.JSValue) = .empty;
                defer values.deinit(engine.gpa);
                try values.append(engine.gpa, monitor);
                if (args.len > 1) try values.appendSlice(engine.gpa, args[1..]);
                try invokeVoid(engine, object, "emit", values.items);
            }
            const error_handler = try js.get(engine, events, "error");
            defer engine.freeValue(error_handler);
            do_error = c.JS_IsUndefined(error_handler);
        }
    } else if (!do_error) return c.pi_js_bool(engine.context, 0);
    if (do_error) {
        const reason = v.arg(args, 1);
        const error_constructor = try js.get(engine, state, "Error");
        defer engine.freeValue(error_constructor);
        const is_error = c.JS_IsInstanceOf(engine.context, reason, error_constructor);
        if (is_error < 0) return js.capture(engine);
        if (is_error != 0) {
            _ = try engine.checked(c.JS_Throw(engine.context, c.JS_DupValue(engine.context, reason)));
            unreachable;
        }
        const text = @import("node_event_inspect.zig").inspect(engine, reason, 2) catch |err| blk: {
            if (err != error.JavaScriptException) return err;
            if (engine.captured_exception) |value| engine.freeValue(value);
            engine.captured_exception = null;
            break :blk try engine.toString(reason);
        };
        defer engine.gpa.free(text);
        const message = try std.fmt.allocPrint(engine.gpa, "Unhandled error. ({s})", .{text});
        defer engine.gpa.free(message);
        const string = try v.text(engine, message);
        defer engine.freeValue(string);
        const error_value = try js.builtin(engine, "Error", &.{string});
        var transferred = false;
        errdefer if (!transferred) engine.freeValue(error_value);
        try js.define(engine, error_value, "code", try v.text(engine, "ERR_UNHANDLED_ERROR"));
        try js.define(engine, error_value, "context", c.JS_DupValue(engine.context, reason));
        transferred = true;
        _ = try engine.checked(c.JS_Throw(engine.context, error_value));
        unreachable;
    }
    const handler = try js.getKey(engine, events, type_value);
    defer engine.freeValue(handler);
    if (c.JS_IsUndefined(handler)) return c.pi_js_bool(engine.context, 0);
    const listeners = if (c.JS_IsFunction(engine.context, handler)) c.JS_DupValue(engine.context, handler) else try copyListeners(engine, handler, false);
    defer engine.freeValue(listeners);
    const count: u32 = if (c.JS_IsFunction(engine.context, listeners)) 1 else @intFromFloat(try v.numberField(engine, listeners, "length"));
    for (0..count) |index| {
        const function = if (c.JS_IsFunction(engine.context, listeners)) c.JS_DupValue(engine.context, listeners) else try engine.checked(c.JS_GetPropertyUint32(engine.context, listeners, @intCast(index)));
        defer engine.freeValue(function);
        const result = try applyListener(engine, function, object, if (args.len > 1) args[1..] else &.{});
        defer engine.freeValue(result);
        if (!c.JS_IsNull(result) and !c.JS_IsUndefined(result)) {
            try addCatch(engine, object, result, args, state);
        }
    }
    return c.pi_js_bool(engine.context, 1);
}
fn listenerCount(engine: *js.Engine, object: c.JSValue, args: []const c.JSValue) !c.JSValue {
    const events = try js.get(engine, object, "_events");
    defer engine.freeValue(events);
    if (c.JS_IsUndefined(events)) return c.JS_NewInt32(engine.context, 0);
    const list = try js.getKey(engine, events, v.arg(args, 0));
    defer engine.freeValue(list);
    if (c.JS_IsUndefined(list)) return c.JS_NewInt32(engine.context, 0);
    const wanted = v.arg(args, 1);
    const filtered = !c.JS_IsNull(wanted) and !c.JS_IsUndefined(wanted);
    if (c.JS_IsFunction(engine.context, list)) {
        if (!filtered) return c.JS_NewInt32(engine.context, 1);
        if (c.JS_IsStrictEqual(engine.context, list, wanted)) return c.JS_NewInt32(engine.context, 1);
        const original = try js.get(engine, list, "listener");
        defer engine.freeValue(original);
        return c.JS_NewInt32(engine.context, @intFromBool(c.JS_IsStrictEqual(engine.context, original, wanted)));
    }
    if (!filtered) return js.get(engine, list, "length");
    const count = try v.numberField(engine, list, "length");
    var index: f64 = 0;
    var matching: f64 = 0;
    while (index < count) : (index += 1) {
        const item = try js.getKey(engine, list, v.numeric(engine, index));
        defer engine.freeValue(item);
        if (c.JS_IsStrictEqual(engine.context, item, wanted)) {
            matching += 1;
            continue;
        }
        const original = try js.get(engine, item, "listener");
        defer engine.freeValue(original);
        if (c.JS_IsStrictEqual(engine.context, original, wanted)) matching += 1;
    }
    return v.numeric(engine, matching);
}
fn resetShape(engine: *js.Engine, object: c.JSValue, state: c.JSValue) !void {
    const symbol = try js.get(engine, state, "shapeSymbol");
    defer engine.freeValue(symbol);
    try js.setKey(engine, object, symbol, c.pi_js_bool(engine.context, 0));
}
fn removeAll(engine: *js.Engine, object: c.JSValue, args: []const c.JSValue, state: c.JSValue) !c.JSValue {
    const events = try js.get(engine, object, "_events");
    defer engine.freeValue(events);
    if (c.JS_IsUndefined(events)) return c.JS_DupValue(engine.context, object);
    const removed = try js.get(engine, events, "removeListener");
    defer engine.freeValue(removed);
    if (c.JS_IsUndefined(removed)) {
        if (args.len == 0) {
            try v.set(engine, object, "_events", try emptyEvents(engine));
            try v.set(engine, object, "_eventsCount", c.JS_NewInt32(engine.context, 0));
        } else {
            const item = try js.getKey(engine, events, args[0]);
            defer engine.freeValue(item);
            if (!c.JS_IsUndefined(item)) {
                const count = try v.numberField(engine, object, "_eventsCount") - 1;
                try v.set(engine, object, "_eventsCount", v.numeric(engine, count));
                if (count == 0) try v.set(engine, object, "_events", try emptyEvents(engine)) else try deleteKey(engine, events, args[0]);
            }
        }
        try resetShape(engine, object, state);
        return c.JS_DupValue(engine.context, object);
    }
    if (args.len == 0) {
        const reflect = try js.global(engine, "Reflect");
        defer engine.freeValue(reflect);
        const keys = try js.invoke(engine, reflect, "ownKeys", &.{events});
        defer engine.freeValue(keys);
        const length = try v.numberField(engine, keys, "length");
        var index: f64 = 0;
        while (index < length) : (index += 1) {
            const key = try js.getKey(engine, keys, v.numeric(engine, index));
            defer engine.freeValue(key);
            if (!try equalText(engine, key, "removeListener")) try invokeVoid(engine, object, "removeAllListeners", &.{key});
        }
        const name = try v.text(engine, "removeListener");
        defer engine.freeValue(name);
        try invokeVoid(engine, object, "removeAllListeners", &.{name});
        try v.set(engine, object, "_events", try emptyEvents(engine));
        try v.set(engine, object, "_eventsCount", c.JS_NewInt32(engine.context, 0));
        try resetShape(engine, object, state);
        return c.JS_DupValue(engine.context, object);
    }
    const list = try js.getKey(engine, events, args[0]);
    defer engine.freeValue(list);
    if (c.JS_IsFunction(engine.context, list)) try invokeVoid(engine, object, "removeListener", &.{ args[0], list }) else if (!c.JS_IsUndefined(list)) {
        var index = try v.numberField(engine, list, "length") - 1;
        while (index >= 0) : (index -= 1) {
            const listener = try js.getKey(engine, list, v.numeric(engine, index));
            defer engine.freeValue(listener);
            try invokeVoid(engine, object, "removeListener", &.{ args[0], listener });
        }
    }
    return c.JS_DupValue(engine.context, object);
}
fn initialize(engine: *js.Engine, object: c.JSValue, options: c.JSValue, state: c.JSValue) !void {
    if (c.JS_IsUndefined(object)) {
        _ = try engine.checked(c.JS_ThrowTypeError(engine.context, "Cannot read properties of undefined (reading '_events')"));
        unreachable;
    }
    const current = try js.get(engine, object, "_events");
    defer engine.freeValue(current);
    var fresh = c.JS_IsUndefined(current);
    if (!fresh) {
        const second = try js.get(engine, object, "_events");
        defer engine.freeValue(second);
        const prototype = try engine.checked(c.JS_GetPrototype(engine.context, object));
        defer engine.freeValue(prototype);
        const inherited = try js.get(engine, prototype, "_events");
        defer engine.freeValue(inherited);
        fresh = c.JS_IsStrictEqual(engine.context, second, inherited);
    }
    const shape = try js.get(engine, state, "shapeSymbol");
    defer engine.freeValue(shape);
    if (fresh) {
        try v.set(engine, object, "_events", try emptyEvents(engine));
        try v.set(engine, object, "_eventsCount", c.JS_NewInt32(engine.context, 0));
    }
    try js.setKey(engine, object, shape, c.pi_js_bool(engine.context, @intFromBool(!fresh)));
    const maximum = try js.get(engine, object, "_maxListeners");
    defer engine.freeValue(maximum);
    if (!v.truthy(engine, maximum)) try v.set(engine, object, "_maxListeners", c.pi_js_undefined());
    const capture_symbol = try js.get(engine, state, "captureSymbol");
    defer engine.freeValue(capture_symbol);
    var capture = c.pi_js_undefined();
    defer engine.freeValue(capture);
    if (!c.JS_IsNull(options) and !c.JS_IsUndefined(options)) capture = try js.get(engine, options, "captureRejections");
    if (v.truthy(engine, capture)) {
        const validate = try js.get(engine, options, "captureRejections");
        defer engine.freeValue(validate);
        try validateBoolean(engine, validate, "options.captureRejections");
        const value = try js.get(engine, options, "captureRejections");
        defer engine.freeValue(value);
        try js.setKey(engine, object, capture_symbol, c.pi_js_bool(engine.context, @intFromBool(v.truthy(engine, value))));
    } else {
        const prototype = try js.get(engine, state, "prototype");
        defer engine.freeValue(prototype);
        const value = try js.getKey(engine, prototype, capture_symbol);
        defer engine.freeValue(value);
        try js.setKey(engine, object, capture_symbol, value);
    }
}
fn operation(engine: *js.Engine, object: c.JSValue, method: Method, args: []const c.JSValue, state: c.JSValue, holder: c.JSValue) !c.JSValue {
    switch (method) {
        .captureGet, .captureSet => {
            const prototype = try js.get(engine, state, "prototype");
            defer engine.freeValue(prototype);
            const key = try js.get(engine, state, "captureSymbol");
            defer engine.freeValue(key);
            if (method == .captureGet) return js.getKey(engine, prototype, key);
            try validateBoolean(engine, v.arg(args, 0), "EventEmitter.captureRejections");
            try js.setKey(engine, prototype, key, v.arg(args, 0));
            return c.pi_js_undefined();
        },
        .staticListeners, .staticCount => {
            const target = v.arg(args, 0);
            const name = if (method == .staticListeners) "listeners" else "listenerCount";
            if (c.JS_IsNull(target) or c.JS_IsUndefined(target)) {
                _ = try engine.checked(c.JS_ThrowTypeError(engine.context, "Cannot read properties of %s (reading '%s')", @as([*:0]const u8, if (c.JS_IsNull(target)) "null" else "undefined"), @as([*:0]const u8, name)));
                unreachable;
            }
            const function = try js.get(engine, target, name);
            defer engine.freeValue(function);
            if (c.JS_IsFunction(engine.context, function)) return js.invoke(engine, target, name, &.{v.arg(args, 1)});
            return invalidTarget(engine, target, "emitter");
        },
        .staticGetMax => {
            const target = v.arg(args, 0);
            if (!c.JS_IsNull(target) and !c.JS_IsUndefined(target)) {
                const function = try js.get(engine, target, "getMaxListeners");
                defer engine.freeValue(function);
                if (c.JS_IsFunction(engine.context, function)) return maxListeners(engine, target, state);
                const key = try js.get(engine, state, "targetMaxSymbol");
                defer engine.freeValue(key);
                const maximum = try js.getKey(engine, target, key);
                defer engine.freeValue(maximum);
                if (c.JS_IsNumber(maximum)) return js.getKey(engine, target, key);
            }
            return invalidTarget(engine, target, "emitter");
        },
        .staticSetMax => {
            const maximum = if (c.JS_IsUndefined(v.arg(args, 0))) try js.get(engine, state, "defaultMaxListeners") else c.JS_DupValue(engine.context, args[0]);
            defer engine.freeValue(maximum);
            try validateMax(engine, maximum, "setMaxListeners");
            if (args.len <= 1) {
                try v.set(engine, state, "defaultMaxListeners", c.JS_DupValue(engine.context, maximum));
            } else for (args[1..]) |target| {
                const function = try js.get(engine, target, "setMaxListeners");
                defer engine.freeValue(function);
                if (!c.JS_IsFunction(engine.context, function)) return invalidTarget(engine, target, "eventTargets");
                try invokeVoid(engine, target, "setMaxListeners", &.{maximum});
            }
            return c.pi_js_undefined();
        },
        .init => {
            try initialize(engine, object, v.arg(args, 0), state);
            return c.pi_js_undefined();
        },
        .setMaxListeners => {
            try validateMax(engine, v.arg(args, 0), "setMaxListeners");
            try v.set(engine, object, "_maxListeners", c.JS_DupValue(engine.context, v.arg(args, 0)));
            return c.JS_DupValue(engine.context, object);
        },
        .getMaxListeners => return maxListeners(engine, object, state),
        .emit => return emit(engine, object, args, state),
        .addListener, .prependListener => return add(engine, object, v.arg(args, 0), v.arg(args, 1), method == .prependListener, state),
        .once, .prependOnceListener => return once(engine, object, v.arg(args, 0), v.arg(args, 1), method == .prependOnceListener, state),
        .removeListener => return remove(engine, object, v.arg(args, 0), v.arg(args, 1), state),
        .removeAllListeners => return removeAll(engine, object, args, state),
        .listeners, .rawListeners => {
            const events = try js.get(engine, object, "_events");
            defer engine.freeValue(events);
            if (c.JS_IsUndefined(events)) return js.array(engine);
            const list = try js.getKey(engine, events, v.arg(args, 0));
            defer engine.freeValue(list);
            if (c.JS_IsUndefined(list)) return js.array(engine);
            return copyListeners(engine, list, method == .listeners);
        },
        .listenerCount => return listenerCount(engine, object, args),
        .eventNames => {
            if (!(try v.numberField(engine, object, "_eventsCount") > 0)) return js.array(engine);
            const events = try js.get(engine, object, "_events");
            defer engine.freeValue(events);
            const reflect = try js.global(engine, "Reflect");
            defer engine.freeValue(reflect);
            return js.invoke(engine, reflect, "ownKeys", &.{events});
        },
        .defaultGet => return js.get(engine, state, "defaultMaxListeners"),
        .defaultSet => {
            try validateMax(engine, v.arg(args, 0), "defaultMaxListeners");
            try v.set(engine, state, "defaultMaxListeners", c.JS_DupValue(engine.context, v.arg(args, 0)));
            return c.pi_js_undefined();
        },
        .onceWrapper => {
            if (try fieldTruthy(engine, holder, "fired")) return c.pi_js_undefined();
            const target = try js.get(engine, holder, "target");
            defer engine.freeValue(target);
            const type_value = try js.get(engine, holder, "type");
            defer engine.freeValue(type_value);
            const wrapped = try js.get(engine, holder, "wrapFn");
            defer engine.freeValue(wrapped);
            try invokeVoid(engine, target, "removeListener", &.{ type_value, wrapped });
            try v.set(engine, holder, "fired", c.pi_js_bool(engine.context, 1));
            const listener = try js.get(engine, holder, "listener");
            defer engine.freeValue(listener);
            return if (args.len == 0) js.invoke(engine, listener, "call", &.{target}) else applyListener(engine, listener, target, args);
        },
    }
}
fn methodCall(context: ?*c.JSContext, object: c.JSValue, argc: c_int, argv: [*c]c.JSValue, magic: c_int, data: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = js.Engine.fromContext(context.?);
    return operation(engine, object, @enumFromInt(magic), if (argc > 0) argv[0..@intCast(argc)] else &.{}, data[0], data[1]) catch |err| fail(engine, err);
}
fn makeFunction(engine: *js.Engine, name: [*:0]const u8, length: c_int, method: Method, state: c.JSValue) !c.JSValue {
    if (method != .captureGet and method != .captureSet) {
        return @import("native_node_function.zig").create(engine, name, length, ordinaryCall, &.{ state, c.JS_NewInt32(engine.context, @intFromEnum(method)) });
    }
    var data = [_]c.JSValue{ state, c.pi_js_undefined() };
    return engine.checked(c.JS_NewCFunctionData2(engine.context, methodCall, name, length, @intFromEnum(method), data.len, &data));
}
fn ordinaryCall(engine: *js.Engine, receiver: c.JSValue, args: []const c.JSValue, values: []const c.JSValue) anyerror!c.JSValue {
    return operation(engine, receiver, @enumFromInt(@as(c_int, @intFromFloat(try v.number(engine, values[1])))), args, values[0], c.pi_js_undefined());
}
fn constructorFinalizer(runtime: ?*c.JSRuntime, value: c.JSValue) callconv(.c) void {
    const state: *Constructor = @ptrCast(@alignCast(c.JS_GetOpaque(value, c.JS_GetClassID(value)) orelse return));
    c.JS_FreeValueRT(runtime, state.state);
    state.engine.gpa.destroy(state);
}
fn constructorMark(runtime: ?*c.JSRuntime, value: c.JSValue, mark: ?*const c.JS_MarkFunc) callconv(.c) void {
    const state: *Constructor = @ptrCast(@alignCast(c.JS_GetOpaque(value, c.JS_GetClassID(value)) orelse return));
    c.JS_MarkValue(runtime, state.state, mark);
}
fn constructorCall(context: ?*c.JSContext, function: c.JSValue, target: c.JSValue, argc: c_int, argv: [*c]c.JSValue, flags: c_int) callconv(.c) c.JSValue {
    const engine = js.Engine.fromContext(context.?);
    return construct(engine, function, target, if (argc > 0) argv[0..@intCast(argc)] else &.{}, flags & c.JS_CALL_FLAG_CONSTRUCTOR != 0) catch |err| fail(engine, err);
}
fn construct(engine: *js.Engine, function: c.JSValue, target: c.JSValue, args: []const c.JSValue, is_constructor: bool) !c.JSValue {
    const object = if (is_constructor) try @import("native_class.zig").object(engine, target) else c.JS_DupValue(engine.context, target);
    defer if (!is_constructor) engine.freeValue(object);
    errdefer if (is_constructor) engine.freeValue(object);
    const init = try js.get(engine, function, "init");
    defer engine.freeValue(init);
    const result = try js.invoke(engine, init, "call", &.{ object, v.arg(args, 0) });
    engine.freeValue(result);
    return if (is_constructor) object else c.pi_js_undefined();
}
pub fn install(engine: *js.Engine) !void {
    if (engine.native_module_names.contains("node:events")) return;
    const state = try js.object(engine);
    defer engine.freeValue(state);
    const function_proto = try engine.checked(c.JS_GetFunctionProto(engine.context));
    defer engine.freeValue(function_proto);
    try js.define(engine, state, "functionBind", try js.get(engine, function_proto, "bind"));
    try js.define(engine, state, "defaultMaxListeners", c.JS_NewInt32(engine.context, 10));
    try js.define(engine, state, "rejections", try js.array(engine));
    try js.define(engine, state, "rejectionScheduled", c.pi_js_bool(engine.context, 0));
    try js.define(engine, state, "tickGeneration", c.JS_NewInt32(engine.context, 0));
    const symbol = try js.global(engine, "Symbol");
    defer engine.freeValue(symbol);
    inline for (.{ .{ "shapeSymbol", "shapeMode" }, .{ "captureSymbol", "kCapture" }, .{ "errorMonitor", "events.errorMonitor" }, .{ "targetMaxSymbol", "events.maxEventTargetListeners" }, .{ "targetWarnedSymbol", "events.maxEventTargetListenersWarned" }, .{ "resistSymbol", "kResistStopPropagation" } }) |entry| {
        const name = try v.text(engine, entry[1]);
        defer engine.freeValue(name);
        try js.define(engine, state, entry[0], try js.call(engine, symbol, c.pi_js_undefined(), &.{name}));
    }
    const rejection_name = try v.text(engine, "nodejs.rejection");
    defer engine.freeValue(rejection_name);
    try js.define(engine, state, "rejectionSymbol", try js.invoke(engine, symbol, "for", &.{rejection_name}));
    try js.define(engine, state, "Error", try js.global(engine, "Error"));
    const prototype = try js.object(engine);
    defer engine.freeValue(prototype);
    if (c.JS_DefinePropertyValueStr(engine.context, prototype, "constructor", c.pi_js_undefined(), c.JS_PROP_CONFIGURABLE | c.JS_PROP_WRITABLE) < 0) return js.capture(engine);
    try js.define(engine, prototype, "_events", c.pi_js_undefined());
    try js.define(engine, prototype, "_eventsCount", c.JS_NewInt32(engine.context, 0));
    try js.define(engine, prototype, "_maxListeners", c.pi_js_undefined());
    try js.define(engine, state, "prototype", c.JS_DupValue(engine.context, prototype));
    const capture_symbol = try js.get(engine, state, "captureSymbol");
    defer engine.freeValue(capture_symbol);
    const capture_atom = try js.atom(engine, capture_symbol);
    defer c.JS_FreeAtom(engine.context, capture_atom);
    if (c.JS_DefinePropertyValue(engine.context, prototype, capture_atom, c.pi_js_bool(engine.context, 0), c.JS_PROP_WRITABLE) < 0) return js.capture(engine);
    inline for (.{ .{ "setMaxListeners", Method.setMaxListeners, 1 }, .{ "getMaxListeners", Method.getMaxListeners, 0 }, .{ "emit", Method.emit, 1 }, .{ "addListener", Method.addListener, 2 }, .{ "on", Method.addListener, 2 }, .{ "prependListener", Method.prependListener, 2 }, .{ "once", Method.once, 2 }, .{ "prependOnceListener", Method.prependOnceListener, 2 }, .{ "removeListener", Method.removeListener, 2 }, .{ "off", Method.removeListener, 2 }, .{ "removeAllListeners", Method.removeAllListeners, 1 }, .{ "listeners", Method.listeners, 1 }, .{ "rawListeners", Method.rawListeners, 1 }, .{ "listenerCount", Method.listenerCount, 2 }, .{ "eventNames", Method.eventNames, 0 } }) |entry| {
        if (comptime std.mem.eql(u8, entry[0], "on") or std.mem.eql(u8, entry[0], "off")) {
            try js.define(engine, prototype, entry[0], try js.get(engine, prototype, if (comptime std.mem.eql(u8, entry[0], "on")) "addListener" else "removeListener"));
        } else try js.define(engine, prototype, entry[0], try makeFunction(engine, entry[0], entry[2], entry[1], state));
    }
    var class: c.JSClassID = 0;
    _ = c.JS_NewClassID(engine.runtime, &class);
    const definition: c.JSClassDef = .{ .class_name = "EventEmitter", .call = constructorCall, .finalizer = constructorFinalizer, .gc_mark = constructorMark };
    if (c.JS_NewClass(engine.runtime, class, &definition) < 0) return error.OutOfMemory;
    const function = try js.global(engine, "Function");
    defer engine.freeValue(function);
    const function_prototype = try js.get(engine, function, "prototype");
    defer engine.freeValue(function_prototype);
    const constructor = try engine.checked(c.JS_NewObjectProtoClass(engine.context, function_prototype, class));
    defer engine.freeValue(constructor);
    const owned = try engine.gpa.create(Constructor);
    owned.* = .{ .engine = engine, .state = c.JS_DupValue(engine.context, state) };
    _ = c.JS_SetOpaque(constructor, owned);
    _ = c.JS_SetConstructorBit(engine.context, constructor, true);
    if (c.JS_DefinePropertyValueStr(engine.context, constructor, "length", c.JS_NewInt32(engine.context, 1), c.JS_PROP_CONFIGURABLE) < 0) return js.capture(engine);
    if (c.JS_DefinePropertyValueStr(engine.context, constructor, "name", try v.text(engine, "EventEmitter"), c.JS_PROP_CONFIGURABLE) < 0) return js.capture(engine);
    if (c.JS_DefinePropertyValueStr(engine.context, constructor, "prototype", c.JS_DupValue(engine.context, prototype), c.JS_PROP_WRITABLE) < 0) return js.capture(engine);
    if (c.JS_DefinePropertyValueStr(engine.context, prototype, "constructor", c.JS_DupValue(engine.context, constructor), c.JS_PROP_CONFIGURABLE | c.JS_PROP_WRITABLE) < 0) return js.capture(engine);
    try js.define(engine, state, "constructor", c.JS_DupValue(engine.context, constructor));
    try js.define(engine, constructor, "addAbortListener", try @import("node_events_async.zig").addAbortFunction(engine, state));
    try js.define(engine, constructor, "once", try @import("node_events_async.zig").onceFunction(engine, state));
    try js.define(engine, constructor, "on", try @import("node_events_on.zig").onFunction(engine, state));
    inline for (.{ .{ "getEventListeners", Method.staticListeners, 2 }, .{ "getMaxListeners", Method.staticGetMax, 1 }, .{ "listenerCount", Method.staticCount, 2 } }) |entry| try js.define(engine, constructor, entry[0], try makeFunction(engine, entry[0], entry[2], entry[1], state));
    try js.define(engine, constructor, "EventEmitter", c.JS_DupValue(engine.context, constructor));
    try js.define(engine, constructor, "usingDomains", c.pi_js_bool(engine.context, 0));
    try js.define(engine, constructor, "captureRejectionSymbol", try js.get(engine, state, "rejectionSymbol"));
    const capture_get = try makeFunction(engine, "get", 0, .captureGet, state);
    defer engine.freeValue(capture_get);
    const capture_set = try makeFunction(engine, "set", 1, .captureSet, state);
    defer engine.freeValue(capture_set);
    const capture_name = c.JS_NewAtom(engine.context, "captureRejections");
    defer c.JS_FreeAtom(engine.context, capture_name);
    if (c.JS_DefinePropertyGetSet(engine.context, constructor, capture_name, c.JS_DupValue(engine.context, capture_get), c.JS_DupValue(engine.context, capture_set), c.JS_PROP_ENUMERABLE) < 0) return js.capture(engine);
    const resource_constructor = try @import("node_events_resource.zig").install(engine, constructor, prototype);
    defer engine.freeValue(resource_constructor);
    try js.define(engine, constructor, "errorMonitor", try js.get(engine, state, "errorMonitor"));
    const get = try makeFunction(engine, "get", 0, .defaultGet, state);
    defer engine.freeValue(get);
    const set = try makeFunction(engine, "set", 1, .defaultSet, state);
    defer engine.freeValue(set);
    const atom = c.JS_NewAtom(engine.context, "defaultMaxListeners");
    defer c.JS_FreeAtom(engine.context, atom);
    if (c.JS_DefinePropertyGetSet(engine.context, constructor, atom, c.JS_DupValue(engine.context, get), c.JS_DupValue(engine.context, set), c.JS_PROP_ENUMERABLE) < 0) return js.capture(engine);
    inline for (.{ .{ "kMaxEventTargetListeners", "targetMaxSymbol" }, .{ "kMaxEventTargetListenersWarned", "targetWarnedSymbol" } }) |entry| if (c.JS_DefinePropertyValueStr(engine.context, constructor, entry[0], try js.get(engine, state, entry[1]), 0) < 0) return js.capture(engine);
    try js.define(engine, constructor, "setMaxListeners", try makeFunction(engine, "", 0, .staticSetMax, state));
    try js.define(engine, constructor, "init", try makeFunction(engine, "", 1, .init, state));
    const exports = try js.object(engine);
    defer engine.freeValue(exports);
    try js.define(engine, exports, "default", c.JS_DupValue(engine.context, constructor));
    try js.define(engine, exports, "EventEmitter", c.JS_DupValue(engine.context, constructor));
    try js.define(engine, exports, "EventEmitterAsyncResource", c.JS_DupValue(engine.context, resource_constructor));
    try js.define(engine, exports, "errorMonitor", try js.get(engine, state, "errorMonitor"));
    inline for (.{ "addAbortListener", "once", "on", "getEventListeners", "getMaxListeners", "listenerCount", "captureRejectionSymbol", "setMaxListeners", "captureRejections", "defaultMaxListeners", "init", "usingDomains" }) |name| try js.define(engine, exports, name, try js.get(engine, constructor, name));
    try engine.registerValueModule("node:events", exports);
    try engine.registerValueModule("events", exports);
}
