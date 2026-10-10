//! Source TypeBox error classes implemented through native C constructors.
const engine_mod = @import("engine.zig");
const vm = @import("native_values.zig");
const c = engine_mod.c;
const Engine = engine_mod.Engine;
pub fn literalConstructor(engine: *Engine) !c.JSValue {
    if (engine.native_typebox_literal_error) |constructor| return c.JS_DupValue(engine.context, constructor);
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    const base = try vm.get(engine, global, "Error");
    defer engine.freeValue(base);
    const base_prototype = try vm.get(engine, base, "prototype");
    defer engine.freeValue(base_prototype);
    var stack_getter: ?c.JSValue = null;
    defer if (stack_getter) |getter| engine.freeValue(getter);
    const stack_atom = c.JS_NewAtom(engine.context, "stack");
    defer c.JS_FreeAtom(engine.context, stack_atom);
    var descriptor: c.JSPropertyDescriptor = undefined;
    const found = c.JS_GetOwnProperty(engine.context, &descriptor, base_prototype, stack_atom);
    if (found < 0) return error.JavaScriptException;
    if (found != 0) {
        defer engine.freeValue(descriptor.value);
        defer engine.freeValue(descriptor.getter);
        defer engine.freeValue(descriptor.setter);
        if (c.JS_IsFunction(engine.context, descriptor.getter)) stack_getter = c.JS_DupValue(engine.context, descriptor.getter);
    }
    const prototype = try engine.checked(c.JS_NewObjectProto(engine.context, base_prototype));
    defer engine.freeValue(prototype);
    const constructor = try engine.checked(c.JS_NewCFunction2(engine.context, constructLiteralError, "InvalidLiteralValue", 1, c.JS_CFUNC_constructor_or_func, 0));
    errdefer engine.freeValue(constructor);
    if (c.JS_SetPrototype(engine.context, constructor, base) < 0) return error.JavaScriptException;
    if (c.JS_SetConstructor(engine.context, constructor, prototype) < 0) return error.JavaScriptException;
    if (c.JS_DefinePropertyValueStr(engine.context, constructor, "prototype", c.JS_DupValue(engine.context, prototype), 0) < 0) return error.JavaScriptException;
    engine.native_typebox_literal_error = c.JS_DupValue(engine.context, constructor);
    engine.native_typebox_literal_base = c.JS_DupValue(engine.context, base);
    engine.native_typebox_literal_stack = if (stack_getter) |getter| c.JS_DupValue(engine.context, getter) else null;
    return constructor;
}
fn constructLiteralError(context: ?*c.JSContext, target: c.JSValue, argc: c_int, argv: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = Engine.fromContext(context.?);
    if (c.JS_IsUndefined(target)) return c.JS_ThrowTypeError(context, "Class constructor InvalidLiteralValue cannot be invoked without 'new'");
    return constructOwned(engine, target, if (argc > 0) argv[0] else c.pi_js_undefined()) catch |err| {
        if (err == error.OutOfMemory) return c.JS_ThrowOutOfMemory(context);
        return engine.throwCaptured();
    };
}
fn constructOwned(engine: *Engine, target: c.JSValue, value: c.JSValue) !c.JSValue {
    const base = try engine.checked(c.JS_GetPrototype(engine.context, engine.native_typebox_literal_error.?));
    defer engine.freeValue(base);
    const message = try engine.checked(c.JS_NewString(engine.context, "Invalid Literal value"));
    defer engine.freeValue(message);
    var args = [_]c.JSValue{message};
    const result = try engine.checked(c.JS_CallConstructor2(engine.context, base, target, 1, &args));
    errdefer engine.freeValue(result);
    if (engine.native_typebox_literal_stack != null and engine.native_typebox_literal_base != null and c.JS_IsStrictEqual(engine.context, base, engine.native_typebox_literal_base.?)) {
        const stack = try engine.checked(c.JS_Call(engine.context, engine.native_typebox_literal_stack.?, result, 0, null));
        defer engine.freeValue(stack);
        const message_atom = c.JS_NewAtom(engine.context, "message");
        defer c.JS_FreeAtom(engine.context, message_atom);
        if (c.JS_DeleteProperty(engine.context, result, message_atom, c.JS_PROP_THROW) < 0) return error.JavaScriptException;
        if (c.JS_DefinePropertyValueStr(engine.context, result, "stack", c.JS_DupValue(engine.context, stack), c.JS_PROP_CONFIGURABLE | c.JS_PROP_WRITABLE) < 0) return error.JavaScriptException;
        if (c.JS_DefinePropertyValueStr(engine.context, result, "message", c.JS_DupValue(engine.context, message), c.JS_PROP_CONFIGURABLE | c.JS_PROP_WRITABLE) < 0) return error.JavaScriptException;
    }
    const cause = try vm.object(engine);
    defer engine.freeValue(cause);
    try vm.put(engine, cause, "value", c.JS_DupValue(engine.context, value));
    if (c.JS_DefinePropertyValueStr(engine.context, result, "cause", c.JS_DupValue(engine.context, cause), 0) < 0) return error.JavaScriptException;
    return result;
}
pub fn invalidLiteral(engine: *Engine, value: c.JSValue) !c.JSValue {
    const constructor = try literalConstructor(engine);
    defer engine.freeValue(constructor);
    var args = [_]c.JSValue{value};
    const failure = try engine.checked(c.JS_CallConstructor(engine.context, constructor, 1, &args));
    return engine.checked(c.JS_Throw(engine.context, failure));
}
