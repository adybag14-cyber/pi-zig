//! Actual Node24 makeSafe(Promise) and SafePromisePrototypeFinally flow in native Zig/C.
//! Protected constructor/prototype state remains private and is never a public Promise replacement.
const js = @import("native_js_values.zig");
const Scope = @import("native_sdk_prompt_scope.zig").Scope;
const c = js.c;
fn copyMissing(scope: *Scope, source: c.JSValue, destination: c.JSValue) !void {
    const engine = scope.engine;
    var names: [*c]c.JSPropertyEnum = null;
    var count: u32 = 0;
    if (c.JS_GetOwnPropertyNames(engine.context, &names, &count, source, c.JS_GPN_STRING_MASK | c.JS_GPN_SYMBOL_MASK) < 0) return js.capture(engine);
    defer c.JS_FreePropertyEnum(engine.context, names, count);
    for (names[0..count]) |entry| {
        const existing = c.JS_GetOwnProperty(engine.context, null, destination, entry.atom);
        if (existing < 0) return js.capture(engine);
        if (existing != 0) continue;
        var descriptor: c.JSPropertyDescriptor = undefined;
        const present = c.JS_GetOwnProperty(engine.context, &descriptor, source, entry.atom);
        if (present < 0) return js.capture(engine);
        if (present == 0) continue;
        defer engine.freeValue(descriptor.value);
        defer engine.freeValue(descriptor.getter);
        defer engine.freeValue(descriptor.setter);
        const status = if (descriptor.flags & c.JS_PROP_GETSET != 0)
            c.JS_DefinePropertyGetSet(engine.context, destination, entry.atom, c.JS_DupValue(engine.context, descriptor.getter), c.JS_DupValue(engine.context, descriptor.setter), descriptor.flags & (c.JS_PROP_CONFIGURABLE | c.JS_PROP_ENUMERABLE))
        else
            c.JS_DefinePropertyValue(engine.context, destination, entry.atom, c.JS_DupValue(engine.context, descriptor.value), descriptor.flags & c.JS_PROP_C_W_E);
        if (status < 0) return js.capture(engine);
    }
}
fn construct(engine: *js.Engine, target: c.JSValue, args: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
    const executor = if (args.len == 0) c.pi_js_undefined() else args[0];
    if (!c.JS_IsFunction(engine.context, executor)) return js.typeError(engine, "Promise executor is not callable");
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    var functions: [2]c.JSValue = undefined;
    const created = try engine.checked(c.JS_NewPromiseCapability(engine.context, &functions));
    defer for (functions) |function| engine.freeValue(function);
    const result = try scope.own(created);
    if (c.JS_SetPrototype(engine.context, result, try scope.get(target, "prototype")) < 0) return js.capture(engine);
    const returned = c.JS_Call(engine.context, executor, c.pi_js_undefined(), functions.len, &functions);
    if (c.JS_IsException(returned)) {
        const reason = c.JS_GetException(engine.context);
        defer engine.freeValue(reason);
        var reject_args = [_]c.JSValue{reason};
        const ignored = try engine.checked(c.JS_Call(engine.context, functions[1], c.pi_js_undefined(), reject_args.len, &reject_args));
        engine.freeValue(ignored);
    } else engine.freeValue(returned);
    return c.JS_DupValue(engine.context, result);
}
pub fn create(engine: *js.Engine) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const holder = try scope.object();
    const original = try scope.global("Promise");
    const original_prototype = try scope.get(original, "prototype");
    try scope.put(holder, "original", original);
    try scope.put(holder, "then", try scope.get(original_prototype, "then"));
    try scope.put(holder, "finally", try scope.get(original_prototype, "finally"));
    const prototype = try scope.object();
    const safe = try scope.own(try @import("native_class.zig").constructor(engine, "SafePromise", 0, prototype, construct, &.{}));
    if (c.JS_SetPrototype(engine.context, safe, original) < 0) return js.capture(engine);
    try copyMissing(&scope, original_prototype, prototype);
    try copyMissing(&scope, original, safe);
    if (c.JS_SetPrototype(engine.context, prototype, c.pi_js_null()) < 0) return js.capture(engine);
    if (c.JS_FreezeObject(engine.context, prototype) < 0 or c.JS_FreezeObject(engine.context, safe) < 0) return js.capture(engine);
    try scope.put(holder, "safe", safe);
    return c.JS_DupValue(engine.context, holder);
}
fn innerExecutor(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, data: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = js.Engine.fromContext(context.?);
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const function = scope.get(data[0], "then") catch |err| return @import("native_durable.zig").reject(engine, err);
    return c.JS_Call(context, function, data[1], argc, argv);
}
fn outer(engine: *js.Engine, holder: c.JSValue, pending: c.JSValue, cleanup: c.JSValue, args: []const c.JSValue) !void {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    var captures = [_]c.JSValue{ holder, pending };
    const executor = try scope.own(try engine.checked(c.JS_NewCFunctionData2(engine.context, innerExecutor, "", 2, 0, captures.len, &captures)));
    var constructor_args = [_]c.JSValue{executor};
    const protected = try scope.own(try engine.checked(c.JS_CallConstructor(engine.context, try scope.get(holder, "safe"), constructor_args.len, &constructor_args)));
    const final = try scope.call(try scope.get(holder, "finally"), protected, &.{cleanup});
    _ = try scope.call(try scope.get(holder, "then"), final, args);
}
fn outerExecutor(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, data: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = js.Engine.fromContext(context.?);
    outer(engine, data[0], data[1], data[2], if (argc > 0) argv[0..@intCast(argc)] else &.{}) catch |err| return @import("native_durable.zig").reject(engine, err);
    return c.pi_js_undefined();
}
pub fn finallyValue(scope: *Scope, holder: c.JSValue, pending: c.JSValue, cleanup: c.JSValue) !c.JSValue {
    var captures = [_]c.JSValue{ holder, pending, cleanup };
    const executor = try scope.own(try scope.engine.checked(c.JS_NewCFunctionData2(scope.engine.context, outerExecutor, "", 2, 0, captures.len, &captures)));
    var args = [_]c.JSValue{executor};
    return scope.own(try scope.engine.checked(c.JS_CallConstructor(scope.engine.context, try scope.get(holder, "original"), args.len, &args)));
}
