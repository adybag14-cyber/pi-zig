//! Source Loader and CancellableLoader: ordinary fields, virtual calls and timer-owned callbacks.
const std = @import("std");
const js = @import("native_js_values.zig");
const c = js.c;
const v = @import("native_select_list.zig");
const Method = enum(c_int) { render, start, stop, setMessage, invalidate, setIndicator, restartAnimation, getRenderedIndicator, updateDisplay, signal, aborted, handleInput, dispose };
fn literalElement(engine: *js.Engine, array: c.JSValue, index: u32, value: c.JSValue) !void {
    if (c.JS_DefinePropertyValueUint32(engine.context, array, index, c.JS_DupValue(engine.context, value), c.JS_PROP_C_W_E) < 0) return js.capture(engine);
}
fn spreadArray(engine: *js.Engine, source: c.JSValue, symbol: c.JSValue) !c.JSValue {
    const result = try js.array(engine);
    errdefer engine.freeValue(result);
    var iterator = try js.Iterator.init(engine, source, symbol);
    defer iterator.deinit();
    errdefer iterator.closePreserving();
    var index: u32 = 0;
    while (try iterator.next()) |value| {
        defer engine.freeValue(value);
        try literalElement(engine, result, index, value);
        index += 1;
    }
    return result;
}
fn fail(engine: *js.Engine, err: anyerror) c.JSValue {
    if (err == error.JavaScriptException) return engine.throwCaptured();
    if (err == error.OutOfMemory) return c.JS_ThrowOutOfMemory(engine.context);
    return c.JS_ThrowTypeError(engine.context, "Native Loader: %s", @as([*:0]const u8, @errorName(err)));
}
fn invoke(engine: *js.Engine, object: c.JSValue, name: [*:0]const u8, args: []const c.JSValue) !void {
    const result = try js.invoke(engine, object, name, args);
    engine.freeValue(result);
}
fn primitive(engine: *js.Engine, value: c.JSValue, symbol: c.JSValue) !c.JSValue {
    if (!c.JS_IsObject(value)) return c.JS_DupValue(engine.context, value);
    const exotic = try js.getKey(engine, value, symbol);
    defer engine.freeValue(exotic);
    if (!c.JS_IsUndefined(exotic) and !c.JS_IsNull(exotic)) {
        const hint = try v.text(engine, "default");
        defer engine.freeValue(hint);
        const result = try js.call(engine, exotic, value, &.{hint});
        if (!c.JS_IsObject(result)) return result;
        engine.freeValue(result);
        return js.typeError(engine, "Cannot convert object to primitive value");
    }
    inline for (.{ "valueOf", "toString" }) |name| {
        const function = try js.get(engine, value, name);
        defer engine.freeValue(function);
        if (c.JS_IsFunction(engine.context, function)) {
            const result = try js.call(engine, function, value, &.{});
            if (!c.JS_IsObject(result)) return result;
            engine.freeValue(result);
        }
    }
    return js.typeError(engine, "Cannot convert object to primitive value");
}
fn nextFrame(engine: *js.Engine, object: c.JSValue, symbol: c.JSValue) !void {
    const current = try js.get(engine, object, "currentFrame");
    defer engine.freeValue(current);
    const value = try primitive(engine, current, symbol);
    defer engine.freeValue(value);
    const numerator = if (c.JS_IsString(value)) blk: {
        const one = try v.text(engine, "1");
        defer engine.freeValue(one);
        const joined = try v.concat(engine, &.{ value, one });
        defer engine.freeValue(joined);
        break :blk try v.number(engine, joined);
    } else try v.number(engine, value) + 1;
    const frames = try js.get(engine, object, "frames");
    defer engine.freeValue(frames);
    const denominator = try v.numberField(engine, frames, "length");
    const next = if (!std.math.isFinite(numerator) or std.math.isNan(denominator) or denominator == 0) std.math.nan(f64) else if (std.math.isInf(denominator)) numerator else @rem(numerator, denominator);
    try v.set(engine, object, "currentFrame", v.numeric(engine, next));
    try invoke(engine, object, "updateDisplay", &.{});
}
fn tick(context: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue, _: c_int, data: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = js.Engine.fromContext(context.?);
    nextFrame(engine, data[0], data[1]) catch |err| return fail(engine, err);
    return c.pi_js_undefined();
}
fn superCall(engine: *js.Engine, prototype: c.JSValue, object: c.JSValue, name: [*:0]const u8, args: []const c.JSValue) !c.JSValue {
    const function = try js.get(engine, prototype, name);
    defer engine.freeValue(function);
    return js.call(engine, function, object, args);
}
fn operation(engine: *js.Engine, object: c.JSValue, method: Method, args: []const c.JSValue, data: [*c]c.JSValue) !c.JSValue {
    switch (method) {
        .render => {
            const result = try js.array(engine);
            errdefer engine.freeValue(result);
            const empty = try v.text(engine, "");
            defer engine.freeValue(empty);
            try literalElement(engine, result, 0, empty);
            const lines = try superCall(engine, data[0], object, "render", &.{v.arg(args, 0)});
            defer engine.freeValue(lines);
            var iterator = try js.Iterator.init(engine, lines, data[1]);
            defer iterator.deinit();
            errdefer iterator.closePreserving();
            var index: u32 = 1;
            while (try iterator.next()) |line| {
                defer engine.freeValue(line);
                try literalElement(engine, result, index, line);
                index += 1;
            }
            return result;
        },
        .start => {
            try invoke(engine, object, "updateDisplay", &.{});
            try invoke(engine, object, "restartAnimation", &.{});
        },
        .stop => {
            const token = try js.get(engine, object, "intervalId");
            defer engine.freeValue(token);
            if (v.truthy(engine, token)) {
                const clear = try js.global(engine, "clearInterval");
                defer engine.freeValue(clear);
                const current = try js.get(engine, object, "intervalId");
                defer engine.freeValue(current);
                const ignored = try js.call(engine, clear, c.pi_js_undefined(), &.{current});
                engine.freeValue(ignored);
                try v.set(engine, object, "intervalId", c.pi_js_null());
            }
        },
        .setMessage => {
            try v.set(engine, object, "message", c.JS_DupValue(engine.context, v.arg(args, 0)));
            try invoke(engine, object, "updateDisplay", &.{});
        },
        .invalidate => {
            const ignored = try superCall(engine, data[0], object, "invalidate", &.{});
            engine.freeValue(ignored);
            try invoke(engine, object, "updateDisplay", &.{});
        },
        .setIndicator => {
            const indicator = v.arg(args, 0);
            try v.set(engine, object, "renderIndicatorVerbatim", c.pi_js_bool(engine.context, @intFromBool(!c.JS_IsUndefined(indicator))));
            var source = c.JS_DupValue(engine.context, data[2]);
            defer engine.freeValue(source);
            if (!c.JS_IsNull(indicator) and !c.JS_IsUndefined(indicator)) {
                const candidate = try js.get(engine, indicator, "frames");
                defer engine.freeValue(candidate);
                if (!c.JS_IsUndefined(candidate)) {
                    const current = try js.get(engine, indicator, "frames");
                    engine.freeValue(source);
                    source = current;
                }
            }
            try v.set(engine, object, "frames", try spreadArray(engine, source, data[1]));
            var interval = c.JS_NewInt32(engine.context, 80);
            defer engine.freeValue(interval);
            if (!c.JS_IsNull(indicator) and !c.JS_IsUndefined(indicator)) {
                const first = try js.get(engine, indicator, "intervalMs");
                defer engine.freeValue(first);
                if (v.truthy(engine, first)) {
                    const second = try js.get(engine, indicator, "intervalMs");
                    defer engine.freeValue(second);
                    if (try v.number(engine, second) > 0) {
                        const third = try js.get(engine, indicator, "intervalMs");
                        engine.freeValue(interval);
                        interval = third;
                    }
                }
            }
            try v.set(engine, object, "intervalMs", c.JS_DupValue(engine.context, interval));
            try v.set(engine, object, "currentFrame", c.JS_NewInt32(engine.context, 0));
            try invoke(engine, object, "start", &.{});
        },
        .restartAnimation => {
            try invoke(engine, object, "stop", &.{});
            const frames = try js.get(engine, object, "frames");
            defer engine.freeValue(frames);
            if (try v.numberField(engine, frames, "length") <= 1) return c.pi_js_undefined();
            const set_interval = try js.global(engine, "setInterval");
            defer engine.freeValue(set_interval);
            var captured = [_]c.JSValue{ object, data[4] };
            const callback = try engine.checked(c.JS_NewCFunctionData2(engine.context, tick, "", 0, 0, captured.len, &captured));
            defer engine.freeValue(callback);
            const interval = try js.get(engine, object, "intervalMs");
            defer engine.freeValue(interval);
            try v.set(engine, object, "intervalId", try js.call(engine, set_interval, c.pi_js_undefined(), &.{ callback, interval }));
        },
        .getRenderedIndicator => {
            const frames = try js.get(engine, object, "frames");
            defer engine.freeValue(frames);
            const current = try js.get(engine, object, "currentFrame");
            defer engine.freeValue(current);
            const raw = try js.getKey(engine, frames, current);
            defer engine.freeValue(raw);
            const frame = if (c.JS_IsNull(raw) or c.JS_IsUndefined(raw)) try v.text(engine, "") else c.JS_DupValue(engine.context, raw);
            defer engine.freeValue(frame);
            const verbatim = try js.get(engine, object, "renderIndicatorVerbatim");
            defer engine.freeValue(verbatim);
            if (v.truthy(engine, verbatim)) return c.JS_DupValue(engine.context, frame);
            return js.invoke(engine, object, "spinnerColorFn", &.{frame});
        },
        .updateDisplay => {
            const rendered = try js.invoke(engine, object, "getRenderedIndicator", &.{});
            defer engine.freeValue(rendered);
            const length = try v.numberField(engine, rendered, "length");
            const indicator = if (length > 0) blk: {
                const space = try v.text(engine, " ");
                defer engine.freeValue(space);
                break :blk try v.concat(engine, &.{ rendered, space });
            } else try v.text(engine, "");
            defer engine.freeValue(indicator);
            const set_text = try js.get(engine, object, "setText");
            defer engine.freeValue(set_text);
            const message_color = try js.get(engine, object, "messageColorFn");
            defer engine.freeValue(message_color);
            const message = try js.get(engine, object, "message");
            defer engine.freeValue(message);
            const colored = try js.call(engine, message_color, object, &.{message});
            defer engine.freeValue(colored);
            const text = try v.concat(engine, &.{ indicator, colored });
            defer engine.freeValue(text);
            const set_result = try js.call(engine, set_text, object, &.{text});
            engine.freeValue(set_result);
            const ui = try js.get(engine, object, "ui");
            defer engine.freeValue(ui);
            if (v.truthy(engine, ui)) {
                const current = try js.get(engine, object, "ui");
                defer engine.freeValue(current);
                try invoke(engine, current, "requestRender", &.{});
            }
        },
        .signal, .aborted => {
            const controller = try js.get(engine, object, "abortController");
            defer engine.freeValue(controller);
            const signal = try js.get(engine, controller, "signal");
            if (method == .signal) return signal;
            defer engine.freeValue(signal);
            return js.get(engine, signal, "aborted");
        },
        .handleInput => {
            const kb = try js.call(engine, data[3], c.pi_js_undefined(), &.{});
            defer engine.freeValue(kb);
            const action = try v.text(engine, "tui.select.cancel");
            defer engine.freeValue(action);
            const matches = try js.invoke(engine, kb, "matches", &.{ v.arg(args, 0), action });
            defer engine.freeValue(matches);
            if (v.truthy(engine, matches)) {
                const controller = try js.get(engine, object, "abortController");
                defer engine.freeValue(controller);
                try invoke(engine, controller, "abort", &.{});
                const callback = try js.get(engine, object, "onAbort");
                defer engine.freeValue(callback);
                if (!c.JS_IsNull(callback) and !c.JS_IsUndefined(callback)) {
                    const ignored = try js.call(engine, callback, object, &.{});
                    engine.freeValue(ignored);
                }
            }
        },
        .dispose => try invoke(engine, object, "stop", &.{}),
    }
    return c.pi_js_undefined();
}
fn methodCall(context: ?*c.JSContext, object: c.JSValue, argc: c_int, argv: [*c]c.JSValue, magic: c_int, data: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = js.Engine.fromContext(context.?);
    return operation(engine, object, @enumFromInt(magic), if (argc > 0) argv[0..@intCast(argc)] else &.{}, data) catch |err| fail(engine, err);
}
fn construct(engine: *js.Engine, target: c.JSValue, args: []const c.JSValue, data: []const c.JSValue) !c.JSValue {
    var base_args = [_]c.JSValue{ try v.text(engine, ""), c.JS_NewInt32(engine.context, 1), c.JS_NewInt32(engine.context, 0) };
    defer engine.freeValue(base_args[0]);
    const object = try engine.checked(c.JS_CallConstructor2(engine.context, data[0], target, base_args.len, &base_args));
    errdefer engine.freeValue(object);
    try js.define(engine, object, "frames", try spreadArray(engine, data[1], data[2]));
    try js.define(engine, object, "intervalMs", c.JS_NewInt32(engine.context, 80));
    try js.define(engine, object, "currentFrame", c.JS_NewInt32(engine.context, 0));
    try js.define(engine, object, "intervalId", c.pi_js_null());
    try js.define(engine, object, "ui", c.pi_js_null());
    try js.define(engine, object, "renderIndicatorVerbatim", c.pi_js_bool(engine.context, 0));
    try js.define(engine, object, "spinnerColorFn", c.pi_js_undefined());
    try js.define(engine, object, "messageColorFn", c.pi_js_undefined());
    try js.define(engine, object, "message", try v.text(engine, "Loading..."));
    inline for (.{ .{ "ui", 0 }, .{ "spinnerColorFn", 1 }, .{ "messageColorFn", 2 } }) |field| try v.set(engine, object, field[0], c.JS_DupValue(engine.context, v.arg(args, field[1])));
    const message = v.arg(args, 3);
    try v.set(engine, object, "message", if (c.JS_IsUndefined(message)) try v.text(engine, "Loading...") else c.JS_DupValue(engine.context, message));
    try invoke(engine, object, "setIndicator", &.{v.arg(args, 4)});
    return object;
}
fn constructCancellable(engine: *js.Engine, target: c.JSValue, args: []const c.JSValue, data: []const c.JSValue) !c.JSValue {
    const object = try engine.checked(c.JS_CallConstructor2(engine.context, data[0], target, @intCast(args.len), @constCast(args.ptr)));
    errdefer engine.freeValue(object);
    try js.define(engine, object, "abortController", try js.builtin(engine, "AbortController", &.{}));
    try js.define(engine, object, "onAbort", c.pi_js_undefined());
    return object;
}
pub fn install(engine: *js.Engine, exports: c.JSValue) !void {
    const text = try js.get(engine, exports, "Text");
    defer engine.freeValue(text);
    const text_prototype = try js.get(engine, text, "prototype");
    defer engine.freeValue(text_prototype);
    const symbol = try js.global(engine, "Symbol");
    defer engine.freeValue(symbol);
    const iterator = try js.get(engine, symbol, "iterator");
    defer engine.freeValue(iterator);
    const to_primitive = try js.get(engine, symbol, "toPrimitive");
    defer engine.freeValue(to_primitive);
    const frames = try js.array(engine);
    defer engine.freeValue(frames);
    inline for (.{ "⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏" }, 0..) |frame, index| {
        const value = try v.text(engine, frame);
        defer engine.freeValue(value);
        try literalElement(engine, frames, index, value);
    }
    const keybindings = try js.get(engine, exports, "getKeybindings");
    defer engine.freeValue(keybindings);
    var data = [_]c.JSValue{ text_prototype, iterator, frames, keybindings, to_primitive };
    const prototype = try engine.checked(c.JS_NewObjectProto(engine.context, text_prototype));
    defer engine.freeValue(prototype);
    const cancellable_prototype = try engine.checked(c.JS_NewObjectProto(engine.context, prototype));
    defer engine.freeValue(cancellable_prototype);
    for ([_]c.JSValue{ prototype, cancellable_prototype }) |current| if (c.JS_DefinePropertyValueStr(engine.context, current, "constructor", c.pi_js_undefined(), c.JS_PROP_CONFIGURABLE | c.JS_PROP_WRITABLE) < 0) return js.capture(engine);
    inline for (std.meta.fields(Method)) |field| {
        const method: Method = @enumFromInt(field.value);
        const getter = method == .signal or method == .aborted;
        const name: [:0]const u8 = field.name;
        const function_name: [:0]const u8 = if (getter) "get " ++ field.name else field.name;
        const function = try engine.checked(c.JS_NewCFunctionData2(engine.context, methodCall, function_name.ptr, if (method == .render or method == .setMessage or method == .setIndicator or method == .handleInput) 1 else 0, @intCast(field.value), data.len, &data));
        const target = if (field.value >= @intFromEnum(Method.signal)) cancellable_prototype else prototype;
        if (getter) {
            defer engine.freeValue(function);
            const atom = c.JS_NewAtom(engine.context, name.ptr);
            defer c.JS_FreeAtom(engine.context, atom);
            if (c.JS_DefinePropertyGetSet(engine.context, target, atom, c.JS_DupValue(engine.context, function), c.pi_js_undefined(), c.JS_PROP_CONFIGURABLE) < 0) return js.capture(engine);
        } else if (c.JS_DefinePropertyValueStr(engine.context, target, name.ptr, function, c.JS_PROP_CONFIGURABLE | c.JS_PROP_WRITABLE) < 0) return js.capture(engine);
    }
    const loader = try @import("native_class.zig").constructor(engine, "Loader", 3, prototype, construct, &.{ text, frames, iterator });
    defer engine.freeValue(loader);
    if (c.JS_SetPrototype(engine.context, loader, text) < 0) return js.capture(engine);
    const cancellable = try @import("native_class.zig").constructor(engine, "CancellableLoader", 0, cancellable_prototype, constructCancellable, &.{loader});
    defer engine.freeValue(cancellable);
    if (c.JS_SetPrototype(engine.context, cancellable, loader) < 0) return js.capture(engine);
    try js.define(engine, exports, "Loader", c.JS_DupValue(engine.context, loader));
    try js.define(engine, exports, "CancellableLoader", c.JS_DupValue(engine.context, cancellable));
}
