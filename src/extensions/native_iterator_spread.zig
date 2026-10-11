//! Array spread uses the VM's immutable well-known iterator identity. It must
//! not consult the mutable global Symbol or observable Array.prototype.push.
const em = @import("engine.zig");
const c = em.c;

// Supplied by the separately frozen QuickJS intrinsic 6c84e40c. Keeping this
// declaration local allows this source draft to preserve its existing vendor
// tree until that prerequisite is composed and qualified.
extern "c" fn JS_GetIteratorSymbol(context: ?*c.JSContext) c.JSValue;

fn property(engine: *em.Engine, object: c.JSValue, name: [*:0]const u8) !c.JSValue {
    return engine.checked(c.JS_GetPropertyStr(engine.context, object, name));
}
fn typeError(engine: *em.Engine, message: [*:0]const u8) anyerror {
    _ = c.JS_ThrowTypeError(engine.context, "%s", message);
    return @import("native_js_values.zig").capture(engine);
}
pub fn snapshot(engine: *em.Engine, iterable: c.JSValue) !c.JSValue {
    const symbol = try engine.checked(JS_GetIteratorSymbol(engine.context));
    defer engine.freeValue(symbol);
    const atom = c.JS_ValueToAtom(engine.context, symbol);
    if (atom == c.JS_ATOM_NULL) return @import("native_js_values.zig").capture(engine);
    defer c.JS_FreeAtom(engine.context, atom);
    const method = try engine.checked(c.JS_GetProperty(engine.context, iterable, atom));
    defer engine.freeValue(method);
    const iterator = try engine.checked(c.JS_Call(engine.context, method, iterable, 0, null));
    defer engine.freeValue(iterator);
    if (!c.JS_IsObject(iterator)) return typeError(engine, "iterator must return an object");
    const next = try property(engine, iterator, "next");
    defer engine.freeValue(next);
    const result = try engine.checked(c.JS_NewArray(engine.context));
    errdefer engine.freeValue(result);
    var index: u32 = 0;
    while (true) {
        const step = try engine.checked(c.JS_Call(engine.context, next, iterator, 0, null));
        defer engine.freeValue(step);
        if (!c.JS_IsObject(step)) return typeError(engine, "iterator result must be an object");
        const done = try property(engine, step, "done");
        defer engine.freeValue(done);
        if (c.JS_ToBool(engine.context, done) == 1) return result;
        const value = try property(engine, step, "value");
        if (c.JS_DefinePropertyValueUint32(engine.context, result, index, value, c.JS_PROP_C_W_E) < 0)
            return @import("native_js_values.zig").capture(engine);
        if (index == @import("std").math.maxInt(u32)) return error.NativeIteratorArrayTooLarge;
        index += 1;
    }
}

/// The caller resolves the callee before evaluating the spread argument.
pub fn call(engine: *em.Engine, receiver: c.JSValue, function: c.JSValue, iterable: c.JSValue) !c.JSValue {
    const expanded = try snapshot(engine, iterable);
    defer engine.freeValue(expanded);
    var count: u32 = 0;
    const length = try property(engine, expanded, "length");
    defer engine.freeValue(length);
    if (c.JS_ToUint32(engine.context, &count, length) < 0) return @import("native_js_values.zig").capture(engine);
    const arguments = try engine.gpa.alloc(c.JSValue, count);
    defer engine.gpa.free(arguments);
    var initialized: usize = 0;
    defer for (arguments[0..initialized]) |argument| engine.freeValue(argument);
    for (arguments, 0..) |*argument, index| {
        argument.* = try engine.checked(c.JS_GetPropertyUint32(engine.context, expanded, @intCast(index)));
        initialized += 1;
    }
    return engine.checked(c.JS_Call(engine.context, function, receiver, @intCast(count), arguments.ptr));
}
