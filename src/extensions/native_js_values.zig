//! Owner-thread JS value operations for native component algorithms.
const engine_mod = @import("engine.zig");
pub const c = engine_mod.c;
pub const Engine = engine_mod.Engine;
pub fn object(engine: *Engine) !c.JSValue {
    return engine.checked(c.JS_NewObject(engine.context));
}
pub fn array(engine: *Engine) !c.JSValue {
    return engine.checked(c.JS_NewArray(engine.context));
}
pub fn get(engine: *Engine, receiver: c.JSValue, name: [*:0]const u8) !c.JSValue {
    return engine.checked(c.JS_GetPropertyStr(engine.context, receiver, name));
}
pub fn define(engine: *Engine, receiver: c.JSValue, name: [*:0]const u8, value: c.JSValue) !void {
    if (c.JS_DefinePropertyValueStr(engine.context, receiver, name, value, c.JS_PROP_C_W_E) < 0) return capture(engine);
}
pub fn call(engine: *Engine, function: c.JSValue, receiver: c.JSValue, arguments: []const c.JSValue) !c.JSValue {
    return engine.checked(c.JS_Call(engine.context, function, receiver, @intCast(arguments.len), @constCast(arguments.ptr)));
}
pub fn invoke(engine: *Engine, receiver: c.JSValue, name: [*:0]const u8, arguments: []const c.JSValue) !c.JSValue {
    const function = try get(engine, receiver, name);
    defer engine.freeValue(function);
    return call(engine, function, receiver, arguments);
}
pub fn global(engine: *Engine, name: [*:0]const u8) !c.JSValue {
    const root = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(root);
    return get(engine, root, name);
}
pub fn builtin(engine: *Engine, name: [*:0]const u8, arguments: []const c.JSValue) !c.JSValue {
    const constructor = try global(engine, name);
    defer engine.freeValue(constructor);
    return engine.checked(c.JS_CallConstructor(engine.context, constructor, @intCast(arguments.len), @constCast(arguments.ptr)));
}
pub fn objectMethod(engine: *Engine, name: [*:0]const u8, value: c.JSValue) !c.JSValue {
    const constructor = try global(engine, "Object");
    defer engine.freeValue(constructor);
    return invoke(engine, constructor, name, &.{value});
}
pub fn push(engine: *Engine, target: c.JSValue, value: c.JSValue) !void {
    const ignored = try invoke(engine, target, "push", &.{value});
    engine.freeValue(ignored);
}
pub fn atom(engine: *Engine, key: c.JSValue) !c.JSAtom {
    const result = c.JS_ValueToAtom(engine.context, key);
    if (result == c.JS_ATOM_NULL) return capture(engine);
    return result;
}
pub fn getKey(engine: *Engine, receiver: c.JSValue, key: c.JSValue) !c.JSValue {
    const name = try atom(engine, key);
    defer c.JS_FreeAtom(engine.context, name);
    return engine.checked(c.JS_GetProperty(engine.context, receiver, name));
}
pub fn setKey(engine: *Engine, receiver: c.JSValue, key: c.JSValue, value: c.JSValue) !void {
    const name = try atom(engine, key);
    defer c.JS_FreeAtom(engine.context, name);
    if (c.JS_SetProperty(engine.context, receiver, name, c.JS_DupValue(engine.context, value)) < 0) return capture(engine);
}
pub fn hasKey(engine: *Engine, receiver: c.JSValue, key: c.JSValue) !bool {
    if (!c.JS_IsObject(receiver)) return typeError(engine, "Right-hand side of 'in' is not an object");
    const name = try atom(engine, key);
    defer c.JS_FreeAtom(engine.context, name);
    const result = c.JS_HasProperty(engine.context, receiver, name);
    if (result < 0) return capture(engine);
    return result != 0;
}
pub fn capture(engine: *Engine) anyerror {
    _ = engine.checked(c.JS_Throw(engine.context, c.JS_GetException(engine.context))) catch |err| return err;
    unreachable;
}
pub fn typeError(engine: *Engine, message: [*:0]const u8) anyerror {
    _ = engine.checked(c.JS_ThrowTypeError(engine.context, "%s", message)) catch |err| return err;
    unreachable;
}
pub fn spread(engine: *Engine, source: c.JSValue) !c.JSValue {
    const result = try object(engine);
    errdefer engine.freeValue(result);
    try spreadInto(engine, result, source);
    return result;
}
pub fn spreadInto(engine: *Engine, target: c.JSValue, source: c.JSValue) !void {
    if (c.JS_IsNull(source) or c.JS_IsUndefined(source)) return;
    const boxed = try engine.checked(c.JS_ToObject(engine.context, source));
    defer engine.freeValue(boxed);
    var names: [*c]c.JSPropertyEnum = null;
    var count: u32 = 0;
    if (c.JS_GetOwnPropertyNames(engine.context, &names, &count, boxed, c.JS_GPN_STRING_MASK | c.JS_GPN_SYMBOL_MASK) < 0) return capture(engine);
    defer c.JS_FreePropertyEnum(engine.context, names, count);
    for (names[0..count]) |entry| {
        var descriptor: c.JSPropertyDescriptor = undefined;
        const present = c.JS_GetOwnProperty(engine.context, &descriptor, boxed, entry.atom);
        if (present < 0) return capture(engine);
        if (present == 0) continue;
        defer engine.freeValue(descriptor.value);
        defer engine.freeValue(descriptor.getter);
        defer engine.freeValue(descriptor.setter);
        if (descriptor.flags & c.JS_PROP_ENUMERABLE == 0) continue;
        const value = try engine.checked(c.JS_GetProperty(engine.context, boxed, entry.atom));
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
        const method = try getKey(engine, iterable, symbol);
        defer engine.freeValue(method);
        const value = try call(engine, method, iterable, &.{});
        errdefer engine.freeValue(value);
        if (!c.JS_IsObject(value)) return typeError(engine, "Iterator is not an object");
        return .{ .engine = engine, .iterator = value, .next_function = try get(engine, value, "next") };
    }
    pub fn deinit(self: *Iterator) void {
        self.engine.freeValue(self.next_function);
        self.engine.freeValue(self.iterator);
    }
    pub fn next(self: *Iterator) !?c.JSValue {
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
        defer self.engine.freeValue(step);
        if (!c.JS_IsObject(step)) return typeError(self.engine, "Iterator result is not an object");
        const done = try get(self.engine, step, "done");
        defer self.engine.freeValue(done);
        if (c.JS_ToBool(self.engine.context, done) != 0) {
            self.closed = true;
            return null;
        }
        return try get(self.engine, step, "value");
    }
    pub fn close(self: *Iterator) !void {
        if (self.closed) return;
        self.closed = true;
        const method = try get(self.engine, self.iterator, "return");
        defer self.engine.freeValue(method);
        if (c.JS_IsNull(method) or c.JS_IsUndefined(method)) return;
        const result = try call(self.engine, method, self.iterator, &.{});
        defer self.engine.freeValue(result);
        if (!c.JS_IsObject(result)) return typeError(self.engine, "Iterator return result is not an object");
    }
    pub fn closePreserving(self: *Iterator) void {
        const original = if (self.engine.captured_exception) |value| c.JS_DupValue(self.engine.context, value) else null;
        defer if (original) |value| self.engine.freeValue(value);
        self.close() catch {};
        if (self.engine.captured_exception) |value| self.engine.freeValue(value);
        self.engine.captured_exception = if (original) |value| c.JS_DupValue(self.engine.context, value) else null;
    }
};
pub fn collect(engine: *Engine, iterable: c.JSValue, symbol: c.JSValue) !c.JSValue {
    const result = try array(engine);
    errdefer engine.freeValue(result);
    var iterator = try Iterator.init(engine, iterable, symbol);
    defer iterator.deinit();
    errdefer iterator.closePreserving();
    while (try iterator.next()) |item| {
        defer engine.freeValue(item);
        try push(engine, result, item);
    }
    return result;
}
pub fn pair(engine: *Engine, iterable: c.JSValue, symbol: c.JSValue) ![2]c.JSValue {
    var iterator = try Iterator.init(engine, iterable, symbol);
    defer iterator.deinit();
    errdefer iterator.closePreserving();
    const first = (try iterator.next()) orelse c.pi_js_undefined();
    errdefer engine.freeValue(first);
    const second = if (iterator.closed) c.pi_js_undefined() else (try iterator.next()) orelse c.pi_js_undefined();
    errdefer engine.freeValue(second);
    try iterator.close();
    return .{ first, second };
}
