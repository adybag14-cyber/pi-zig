//! Owner-thread JS value operations for native component algorithms.
const engine_mod = @import("engine.zig");
pub const c = engine_mod.c;
pub const Engine = engine_mod.Engine;
pub fn object(engine: *Engine) !c.JSValue {
        var frame = @import("native_pending_owner.zig").Frame.init(engine);
        frame.enter() catch |err| return frame.finishValue(err);
        return frame.finishValue(objectPendingBody(engine));
    }
    fn objectPendingBody(engine: *Engine) !c.JSValue {
    return engine.checked(c.JS_NewObject(engine.context));
}
pub fn array(engine: *Engine) !c.JSValue {
        var frame = @import("native_pending_owner.zig").Frame.init(engine);
        frame.enter() catch |err| return frame.finishValue(err);
        return frame.finishValue(arrayPendingBody(engine));
    }
    fn arrayPendingBody(engine: *Engine) !c.JSValue {
    return engine.checked(c.JS_NewArray(engine.context));
}
pub fn get(engine: *Engine, receiver: c.JSValue, name: [*:0]const u8) !c.JSValue {
        var frame = @import("native_pending_owner.zig").Frame.init(engine);
        frame.enter() catch |err| return frame.finishValue(err);
        return frame.finishValue(getPendingBody(engine, receiver, name));
    }
    fn getPendingBody(engine: *Engine, receiver: c.JSValue, name: [*:0]const u8) !c.JSValue {
    return engine.checked(native_guest_0: { try engine.checkNativeEntry(); break :native_guest_0 c.JS_GetPropertyStr(engine.context, receiver, name); });
}
pub fn define(engine: *Engine, receiver: c.JSValue, name: [*:0]const u8, value: c.JSValue) !void {
        var frame = @import("native_pending_owner.zig").Frame.init(engine);
        frame.enter() catch |err| { engine.releaseNativeValue(value); return frame.finishVoid(err); };
        return frame.finishVoid(definePendingBody(engine, receiver, name, value));
    }
    fn definePendingBody(engine: *Engine, receiver: c.JSValue, name: [*:0]const u8, value: c.JSValue) !void {
    if (c.JS_DefinePropertyValueStr(engine.context, receiver, name, value, c.JS_PROP_C_W_E) < 0) return capture(engine);
}
pub fn call(engine: *Engine, function: c.JSValue, receiver: c.JSValue, arguments: []const c.JSValue) !c.JSValue {
        var frame = @import("native_pending_owner.zig").Frame.init(engine);
        frame.enter() catch |err| return frame.finishValue(err);
        return frame.finishValue(callPendingBody(engine, function, receiver, arguments));
    }
    fn callPendingBody(engine: *Engine, function: c.JSValue, receiver: c.JSValue, arguments: []const c.JSValue) !c.JSValue {
    return engine.checked(native_guest_0: { try engine.checkNativeEntry(); break :native_guest_0 c.JS_Call(engine.context, function, receiver, @intCast(arguments.len), @constCast(arguments.ptr)); });
}
pub fn invoke(engine: *Engine, receiver: c.JSValue, name: [*:0]const u8, arguments: []const c.JSValue) !c.JSValue {
        var frame = @import("native_pending_owner.zig").Frame.init(engine);
        frame.enter() catch |err| return frame.finishValue(err);
        return frame.finishValue(invokePendingBody(engine, receiver, name, arguments));
    }
    fn invokePendingBody(engine: *Engine, receiver: c.JSValue, name: [*:0]const u8, arguments: []const c.JSValue) !c.JSValue {
    const function = try get(engine, receiver, name);
    defer engine.releaseNativeValue(function);
    return call(engine, function, receiver, arguments);
}
pub fn global(engine: *Engine, name: [*:0]const u8) !c.JSValue {
        var frame = @import("native_pending_owner.zig").Frame.init(engine);
        frame.enter() catch |err| return frame.finishValue(err);
        return frame.finishValue(globalPendingBody(engine, name));
    }
    fn globalPendingBody(engine: *Engine, name: [*:0]const u8) !c.JSValue {
    const root = c.JS_GetGlobalObject(engine.context);
    defer engine.releaseNativeValue(root);
    return get(engine, root, name);
}
pub fn builtin(engine: *Engine, name: [*:0]const u8, arguments: []const c.JSValue) !c.JSValue {
        var frame = @import("native_pending_owner.zig").Frame.init(engine);
        frame.enter() catch |err| return frame.finishValue(err);
        return frame.finishValue(builtinPendingBody(engine, name, arguments));
    }
    fn builtinPendingBody(engine: *Engine, name: [*:0]const u8, arguments: []const c.JSValue) !c.JSValue {
    const constructor = try global(engine, name);
    defer engine.releaseNativeValue(constructor);
    return engine.checked(native_guest_0: { try engine.checkNativeEntry(); break :native_guest_0 c.JS_CallConstructor(engine.context, constructor, @intCast(arguments.len), @constCast(arguments.ptr)); });
}
pub fn objectMethod(engine: *Engine, name: [*:0]const u8, value: c.JSValue) !c.JSValue {
        var frame = @import("native_pending_owner.zig").Frame.init(engine);
        frame.enter() catch |err| return frame.finishValue(err);
        return frame.finishValue(objectMethodPendingBody(engine, name, value));
    }
    fn objectMethodPendingBody(engine: *Engine, name: [*:0]const u8, value: c.JSValue) !c.JSValue {
    const constructor = try global(engine, "Object");
    defer engine.releaseNativeValue(constructor);
    return invoke(engine, constructor, name, &.{value});
}
pub fn push(engine: *Engine, target: c.JSValue, value: c.JSValue) !void {
        var frame = @import("native_pending_owner.zig").Frame.init(engine);
        frame.enter() catch |err| return frame.finishVoid(err);
        return frame.finishVoid(pushPendingBody(engine, target, value));
    }
    fn pushPendingBody(engine: *Engine, target: c.JSValue, value: c.JSValue) !void {
    const ignored = try invoke(engine, target, "push", &.{value});
    engine.releaseNativeValue(ignored);
}
pub fn atom(engine: *Engine, key: c.JSValue) !c.JSAtom {
        var frame = @import("native_pending_owner.zig").Frame.init(engine);
        frame.enter() catch |err| { frame.finishVoid(err) catch |failure| return failure; unreachable; };
        const value = atomPendingBody(engine, key) catch |err| { frame.finishVoid(err) catch |failure| return failure; unreachable; };
        frame.finishVoid({}) catch |err| { c.JS_FreeAtom(engine.context, value); return err; };
        return value;
    }
    fn atomPendingBody(engine: *Engine, key: c.JSValue) !c.JSAtom {
    const result = native_guest_0: { try engine.checkNativeEntry(); break :native_guest_0 c.JS_ValueToAtom(engine.context, key); };
    if (result == c.JS_ATOM_NULL) return capture(engine);
    return result;
}
pub fn getKey(engine: *Engine, receiver: c.JSValue, key: c.JSValue) !c.JSValue {
        var frame = @import("native_pending_owner.zig").Frame.init(engine);
        frame.enter() catch |err| return frame.finishValue(err);
        return frame.finishValue(getKeyPendingBody(engine, receiver, key));
    }
    fn getKeyPendingBody(engine: *Engine, receiver: c.JSValue, key: c.JSValue) !c.JSValue {
    const name = try atom(engine, key);
    defer c.JS_FreeAtom(engine.context, name);
    return engine.checked(native_guest_0: { try engine.checkNativeEntry(); break :native_guest_0 c.JS_GetProperty(engine.context, receiver, name); });
}
pub fn setKey(engine: *Engine, receiver: c.JSValue, key: c.JSValue, value: c.JSValue) !void {
        var frame = @import("native_pending_owner.zig").Frame.init(engine);
        frame.enter() catch |err| return frame.finishVoid(err);
        return frame.finishVoid(setKeyPendingBody(engine, receiver, key, value));
    }
    fn setKeyPendingBody(engine: *Engine, receiver: c.JSValue, key: c.JSValue, value: c.JSValue) !void {
    const name = try atom(engine, key);
    defer c.JS_FreeAtom(engine.context, name);
    if (c.JS_SetProperty(engine.context, receiver, name, c.JS_DupValue(engine.context, value)) < 0) return capture(engine);
}
pub fn hasKey(engine: *Engine, receiver: c.JSValue, key: c.JSValue) !bool {
        var frame = @import("native_pending_owner.zig").Frame.init(engine);
        frame.enter() catch |err| return frame.finishBool(err);
        return frame.finishBool(hasKeyPendingBody(engine, receiver, key));
    }
    fn hasKeyPendingBody(engine: *Engine, receiver: c.JSValue, key: c.JSValue) !bool {
    if (!c.JS_IsObject(receiver)) return typeError(engine, "Right-hand side of 'in' is not an object");
    const name = try atom(engine, key);
    defer c.JS_FreeAtom(engine.context, name);
    const result = native_guest_0: { try engine.checkNativeEntry(); break :native_guest_0 c.JS_HasProperty(engine.context, receiver, name); };
    if (result < 0) return capture(engine);
    return result != 0;
}
pub fn capture(engine: *Engine) anyerror {
    var frame = @import("native_pending_owner.zig").Frame.init(engine);
    frame.enter() catch {};
    const failure = capturePendingBody(engine);
    frame.finishVoid(failure) catch |err| return err;
    unreachable;
}
fn capturePendingBody(engine: *Engine) anyerror {
    _ = engine.checked(c.pi_js_exception()) catch |err| return err;
    unreachable;
}
pub fn typeError(engine: *Engine, message: [*:0]const u8) anyerror {
    var frame = @import("native_pending_owner.zig").Frame.init(engine);
    frame.enter() catch |err| { frame.finishVoid(err) catch |failure| return failure; unreachable; };
    const failure = typeErrorPendingBody(engine, message);
    frame.finishVoid(failure) catch |err| return err;
    unreachable;
}
fn typeErrorPendingBody(engine: *Engine, message: [*:0]const u8) anyerror {
    _ = engine.checked(c.JS_ThrowTypeError(engine.context, "%s", message)) catch |err| return err;
    unreachable;
}
pub fn spread(engine: *Engine, source: c.JSValue) !c.JSValue {
        var frame = @import("native_pending_owner.zig").Frame.init(engine);
        frame.enter() catch |err| return frame.finishValue(err);
        return frame.finishValue(spreadPendingBody(engine, source));
    }
    fn spreadPendingBody(engine: *Engine, source: c.JSValue) !c.JSValue {
    const result = try object(engine);
    errdefer engine.releaseNativeValue(result);
    try spreadInto(engine, result, source);
    return result;
}
pub fn spreadInto(engine: *Engine, target: c.JSValue, source: c.JSValue) !void {
        var frame = @import("native_pending_owner.zig").Frame.init(engine);
        frame.enter() catch |err| return frame.finishVoid(err);
        return frame.finishVoid(spreadIntoPendingBody(engine, target, source));
    }
    fn spreadIntoPendingBody(engine: *Engine, target: c.JSValue, source: c.JSValue) !void {
    if (c.JS_IsNull(source) or c.JS_IsUndefined(source)) return;
    const boxed = try engine.checked(native_guest_3: { try engine.checkNativeEntry(); break :native_guest_3 c.JS_ToObject(engine.context, source); });
    defer engine.releaseNativeValue(boxed);
    var names: [*c]c.JSPropertyEnum = null;
    var count: u32 = 0;
    if (native_guest_2: { try engine.checkNativeEntry(); break :native_guest_2 c.JS_GetOwnPropertyNames(engine.context, &names, &count, boxed, c.JS_GPN_STRING_MASK | c.JS_GPN_SYMBOL_MASK); } < 0) return capture(engine);
    defer c.JS_FreePropertyEnum(engine.context, names, count);
    for (names[0..count]) |entry| {
        try engine.checkNativeEntry();
        var descriptor: c.JSPropertyDescriptor = undefined;
        const present = native_guest_1: { try engine.checkNativeEntry(); break :native_guest_1 c.JS_GetOwnProperty(engine.context, &descriptor, boxed, entry.atom); };
        if (present < 0) return capture(engine);
        if (present == 0) continue;
        defer engine.releaseNativeValue(descriptor.value);
        defer engine.releaseNativeValue(descriptor.getter);
        defer engine.releaseNativeValue(descriptor.setter);
        if (descriptor.flags & c.JS_PROP_ENUMERABLE == 0) continue;
        const value = try engine.checked(native_guest_0: { try engine.checkNativeEntry(); break :native_guest_0 c.JS_GetProperty(engine.context, boxed, entry.atom); });
        if (c.JS_DefinePropertyValue(engine.context, target, entry.atom, value, c.JS_PROP_C_W_E) < 0) return capture(engine);
    }
}
pub const Iterator = struct {
    engine: *Engine,
    iterator: c.JSValue,
    next_function: c.JSValue,
    closed: bool = false,
    native_steps: usize = 0,
    pub fn init(engine: *Engine, iterable: c.JSValue, symbol: c.JSValue) !Iterator {
        var frame = @import("native_pending_owner.zig").Frame.init(engine);
        frame.enter() catch |err| { frame.finishVoid(err) catch |failure| return failure; unreachable; };
        var value = initPendingBody(engine, iterable, symbol) catch |err| { frame.finishVoid(err) catch |failure| return failure; unreachable; };
        const pending = engine.nativeCallbackResult(c.pi_js_undefined());
        if (frame.terminated() or c.JS_IsException(pending)) {
            value.deinit();
            frame.finishVoid(if (frame.terminated()) error.ExecutionTerminated else error.JavaScriptException) catch |err| return err;
            unreachable;
        }
        // No guest operation or fresh-request poll occurs between this
        // aggregate ownership check and the final native-owner pop.
        try frame.finishVoid({});
        return value;
    }
    fn initPendingBody(engine: *Engine, iterable: c.JSValue, symbol: c.JSValue) !Iterator {
        const method = try getKey(engine, iterable, symbol);
        defer engine.releaseNativeValue(method);
        const value = try call(engine, method, iterable, &.{});
        errdefer engine.releaseNativeValue(value);
        if (!c.JS_IsObject(value)) return typeError(engine, "Iterator is not an object");
        return .{ .engine = engine, .iterator = value, .next_function = try get(engine, value, "next") };
    }
    pub fn deinit(self: *Iterator) void {
        self.engine.releaseNativeValue(self.next_function);
        self.engine.releaseNativeValue(self.iterator);
    }
    pub fn next(self: *Iterator) !?c.JSValue {
        var frame = @import("native_pending_owner.zig").Frame.init(self.engine);
        frame.enter() catch |err| { frame.finishVoid(err) catch |failure| return failure; unreachable; };
        const value = nextPendingBody(self) catch |err| { frame.finishVoid(err) catch |failure| return failure; unreachable; };
        if (value) |owned| return try frame.finishValue(owned);
        try frame.finishVoid({});
        return null;
    }
    fn nextPendingBody(self: *Iterator) !?c.JSValue {
        // Built-in JS iterators can run entirely in C. Keep the engine's
        // cancellation and resource budget effective inside native algorithms.
        self.native_steps +|= 1;
        if (self.engine.cancelled.load(.acquire) or (self.native_steps % 256 == 0 and blk: {
            self.engine.interrupts +|= 1;
            break :blk self.engine.interrupts > self.engine.options.interrupt_budget;
        })) {
            _ = try self.engine.checked(c.JS_ThrowInternalError(self.engine.context, "interrupted"));
            unreachable;
        }
        errdefer self.closed = true;
        const step = try call(self.engine, self.next_function, self.iterator, &.{});
        defer self.engine.releaseNativeValue(step);
        if (!c.JS_IsObject(step)) return typeError(self.engine, "Iterator result is not an object");
        const done = try get(self.engine, step, "done");
        defer self.engine.releaseNativeValue(done);
        if (c.JS_ToBool(self.engine.context, done) != 0) {
            self.closed = true;
            return null;
        }
        return try get(self.engine, step, "value");
    }
    pub fn close(self: *Iterator) !void {
        var frame = @import("native_pending_owner.zig").Frame.init(self.engine);
        frame.enter() catch |err| return frame.finishVoid(err);
        return frame.finishVoid(closePendingBody(self));
    }
    fn closePendingBody(self: *Iterator) !void {
        if (self.closed) return;
        self.closed = true;
        const method = try get(self.engine, self.iterator, "return");
        defer self.engine.releaseNativeValue(method);
        if (c.JS_IsNull(method) or c.JS_IsUndefined(method)) return;
        const result = try call(self.engine, method, self.iterator, &.{});
        defer self.engine.releaseNativeValue(result);
        if (!c.JS_IsObject(result)) return typeError(self.engine, "Iterator return result is not an object");
    }
    pub fn closePreserving(self: *Iterator) void {
        var frame = @import("native_pending_owner.zig").Frame.init(self.engine);
        // IteratorClose is required for an existing ordinary throw. Establish
        // the stable owner without rejecting that actual ordinary completion.
        self.engine.enterNativeInvocation(&frame.invocation);
        frame.finishVoid(self.closePreservingPendingBody()) catch {};
    }
    fn closePreservingPendingBody(self: *Iterator) !void {
        try self.captureCloseOrdinary();
        const original = if (self.engine.captured_exception) |value| c.JS_DupValue(self.engine.context, value) else null;
        defer if (original) |value| self.engine.releaseNativeValue(value);
        self.close() catch |err| try @import("native_pending_owner.zig").catchFailure(self.engine, err);
        while (true) {
            // An ordinary close failure, including a late method-root cleanup
            // event, cannot replace the original Source throw completion.
            try self.captureCloseOrdinary();
            const displaced = self.engine.captured_exception;
            self.engine.captured_exception = if (original) |value| c.JS_DupValue(self.engine.context, value) else null;
            if (displaced) |value| self.engine.releaseNativeValue(value);
            try @import("native_pending_owner.zig").checkFatal(self.engine);
            if (!c.JS_HasException(self.engine.context)) break;
        }
    }
    fn captureCloseOrdinary(self: *Iterator) !void {
        try @import("native_pending_owner.zig").checkFatal(self.engine);
        if (c.JS_HasException(self.engine.context)) {
            // checkNativeEntry suppresses diagnostic guest work and captures
            // only this actual ordinary tuple while our owner remains live.
            self.engine.checkNativeEntry() catch |err| {
                if (err != error.JavaScriptException) return err;
            };
            try @import("native_pending_owner.zig").checkFatal(self.engine);
        }
    }
};
pub fn collect(engine: *Engine, iterable: c.JSValue, symbol: c.JSValue) !c.JSValue {
        var frame = @import("native_pending_owner.zig").Frame.init(engine);
        frame.enter() catch |err| return frame.finishValue(err);
        return frame.finishValue(collectPendingBody(engine, iterable, symbol));
    }
    fn collectPendingBody(engine: *Engine, iterable: c.JSValue, symbol: c.JSValue) !c.JSValue {
    const result = try array(engine);
    errdefer engine.releaseNativeValue(result);
    var iterator = try Iterator.init(engine, iterable, symbol);
    defer iterator.deinit();
    errdefer iterator.closePreserving();
    while (try iterator.next()) |item| {
        defer engine.releaseNativeValue(item);
        try push(engine, result, item);
    }
    return result;
}
pub fn pair(engine: *Engine, iterable: c.JSValue, symbol: c.JSValue) ![2]c.JSValue {
        var frame = @import("native_pending_owner.zig").Frame.init(engine);
        frame.enter() catch |err| { frame.finishVoid(err) catch |failure| return failure; unreachable; };
        const value = pairPendingBody(engine, iterable, symbol) catch |err| { frame.finishVoid(err) catch |failure| return failure; unreachable; };
        const pending = engine.nativeCallbackResult(c.pi_js_undefined());
        if (frame.terminated() or c.JS_IsException(pending)) {
            for (value) |root| engine.releaseNativeValue(root);
            frame.finishVoid(if (frame.terminated()) error.ExecutionTerminated else error.JavaScriptException) catch |err| return err;
            unreachable;
        }
        // No guest operation or fresh-request poll occurs between this
        // aggregate ownership check and the final native-owner pop.
        try frame.finishVoid({});
        return value;
    }
    fn pairPendingBody(engine: *Engine, iterable: c.JSValue, symbol: c.JSValue) ![2]c.JSValue {
    var iterator = try Iterator.init(engine, iterable, symbol);
    defer iterator.deinit();
    errdefer iterator.closePreserving();
    const first = (try iterator.next()) orelse c.pi_js_undefined();
    errdefer engine.releaseNativeValue(first);
    const second = if (iterator.closed) c.pi_js_undefined() else (try iterator.next()) orelse c.pi_js_undefined();
    errdefer engine.releaseNativeValue(second);
    try iterator.close();
    return .{ first, second };
}
