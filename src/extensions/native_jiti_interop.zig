//! Actual jiti2.7.0 utils.ts interopDefault, require.ts JSON rule, and the
//! jiti.import default return expression. No namespace/factory is fabricated.
//! Derived from jiti2.7.0, Copyright Pooya Parsa, MIT; see the retained authority LICENSE.
const v = @import("native_ai_provider_values.zig");
const c = v.c;
const Scope = v.Scope;
const body = @import("native_async_body.zig");
fn put(engine: *v.em.Engine, target: c.JSValue, name: [*:0]const u8, value: c.JSValue) !void { try v.js.define(engine, target, name, c.JS_DupValue(engine.context, value)); }
fn arg(args: []const c.JSValue, index: usize) c.JSValue { return if (index < args.len) args[index] else c.pi_js_undefined(); }
fn instance(s: *Scope, value: c.JSValue, constructor: c.JSValue) !bool {
    const result = c.JS_IsInstanceOf(s.engine.context, value, constructor);
    if (result < 0) return v.js.capture(s.engine);
    return result != 0;
}
/// Owned Source result; ctx.opts.interopDefault is a live read on each call.
pub fn jitiInteropDefault(engine: *v.em.Engine, context: c.JSValue, value: c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine }; defer s.deinit();
    if (!s.truthy(try s.get(try s.get(context, "opts"), "interopDefault"))) return c.JS_DupValue(engine.context, value);
    return interopDefault(engine, value);
}
pub fn interopDefault(engine: *v.em.Engine, value: c.JSValue) !c.JSValue {
    if (c.JS_IsNull(value) or !c.JS_IsObject(value)) return c.JS_DupValue(engine.context, value);
    var s: Scope = .{ .engine = engine }; defer s.deinit();
    const def = try s.get(value, "default");
    const nil = v.nullish(def);
    // typeof null is object. This matters: Source attempts null[prop] when a
    // null-default ordinary module is queried for a missing property.
    const def_object_or_function = c.JS_IsObject(def) or c.JS_IsNull(def);
    if (nil and try instance(&s, value, try s.global("Promise"))) return c.JS_DupValue(engine.context, value);
    const needs_apply = c.JS_IsFunction(engine.context, def) and !c.JS_IsFunction(engine.context, value);
    const fallback = def_object_or_function and !try instance(&s, def, try s.global("Promise"));
    const cache = try s.own(try v.js.builtin(engine, "Map", &.{}));
    const owner = try s.own(try engine.checked(c.JS_NewObjectProto(engine.context, c.JS_NULL)));
    try put(engine, owner, "mod", value);
    try put(engine, owner, "def", def);
    try put(engine, owner, "defIsNil", c.pi_js_bool(engine.context, @intFromBool(nil)));
    try put(engine, owner, "fallback", c.pi_js_bool(engine.context, @intFromBool(fallback)));
    try put(engine, owner, "cache", cache);
    const proxy_constructor = try s.global("Proxy");
    const handler = try s.object();
    try put(engine, handler, "get", try s.own(try trap(engine, "get", 2, 0, owner)));
    const apply = if (needs_apply) try s.own(try trap(engine, "", 3, 1, def)) else c.pi_js_undefined();
    try put(engine, handler, "apply", apply);
    const arguments = [_]c.JSValue{ value, handler };
    // Source uses Proxy(mod), even if mod is not callable and def is. An apply
    // trap does not make a noncallable target callable; retain that behavior.
    return engine.checked(c.JS_CallConstructor(engine.context, proxy_constructor, arguments.len, @constCast(&arguments)));
}
/// Native ordinary callback exit: return this error after restoring the owned
/// reason to the VM. The primitive/VM owns it; no captured catch slot remains.
pub fn callbackFailure(engine: *v.em.Engine, err: anyerror, generation: u64) anyerror {
    if (err == error.OutOfMemory) {
        _ = engine.throwNativeOutOfMemory();
        const reason = c.JS_GetException(engine.context);
        c.JS_SetUncatchableError(engine.context, reason);
        _ = c.JS_Throw(engine.context, reason);
        return error.JavaScriptException;
    }
    if (err != error.JavaScriptException) return err;
    const reason = engine.captured_exception orelse return err;
    if (!c.JS_IsUncatchableError(reason)) body.rethrowRecognizedAllocation(engine, reason, generation) catch |fatal| {
        if (fatal != error.JavaScriptException) return fatal;
    };
    const owned = engine.captured_exception orelse return err;
    engine.captured_exception = null;
    _ = c.JS_Throw(engine.context, owned);
    return error.JavaScriptException;
}
fn trap(engine: *v.em.Engine, name: [*:0]const u8, length: c_int, kind: c_int, root: c.JSValue) !c.JSValue {
    // VM-owned function-data roots are traced/charged/freed by the existing C
    // runtime. No untraced native record or context-pinned interop owner exists.
    var roots = [_]c.JSValue{root};
    return engine.checked(c.JS_NewCFunctionData2(engine.context, dispatch, name, length, kind, roots.len, &roots));
}
fn dispatch(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, kind: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = v.em.Engine.fromContext(context.?);
    engine.native_exception_diagnostics_suppressed += 1;
    defer engine.native_exception_diagnostics_suppressed -= 1;
    const args: []const c.JSValue = if (argc > 0) argv[0..@intCast(argc)] else &.{};
    const generation = engine.native_allocation_generation;
    const result = if (kind == 0) getValue(engine, arg(args, 0), arg(args, 1), roots[0]) else applyValue(engine, arg(args, 1), arg(args, 2), roots[0]);
    return result catch |err| {
        const current = callbackFailure(engine, err, generation);
        if (current == error.JavaScriptException) return engine.throwCaptured();
        return c.JS_ThrowTypeError(engine.context, "Native jiti interop trap: %s", @as([*:0]const u8, @errorName(current)));
    };
}
fn getValue(engine: *v.em.Engine, target: c.JSValue, prop: c.JSValue, owner: c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine }; defer s.deinit();
    const cache = try s.get(owner, "cache");
    if (s.truthy(try s.invoke(cache, "has", &.{prop}))) return c.JS_DupValue(engine.context, try s.invoke(cache, "get", &.{prop}));
    const mod = try s.get(owner, "mod");
    const def = try s.get(owner, "def");
    var value = c.pi_js_undefined();
    if (s.equal(prop, try s.text("__esModule"))) {
        value = c.pi_js_bool(engine.context, 1);
    } else if (s.equal(prop, try s.text("default"))) {
        if (s.truthy(try s.get(owner, "defIsNil"))) {
            value = mod;
        } else {
            const nested = try s.get(def, "default");
            if (c.JS_IsFunction(engine.context, nested) and s.truthy(try s.get(mod, "__esModule"))) value = try s.get(def, "default") else value = def;
        }
    } else if (try v.js.hasKey(engine, target, prop)) {
        value = try s.own(try v.js.getKey(engine, target, prop));
    } else if (s.truthy(try s.get(owner, "fallback"))) {
        value = try s.own(try v.js.getKey(engine, def, prop));
        if (c.JS_IsFunction(engine.context, value)) value = try s.invoke(value, "bind", &.{def});
    }
    _ = try s.invoke(cache, "set", &.{ prop, value });
    return c.JS_DupValue(engine.context, value);
}
fn applyValue(engine: *v.em.Engine, receiver: c.JSValue, arguments: c.JSValue, def: c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine }; defer s.deinit();
    return c.JS_DupValue(engine.context, try s.invoke(try s.global("Reflect"), "apply", &.{ def, receiver, arguments }));
}
/// Owned original JSON export, with the Source permanent nonenumerable self
/// default only when no own/inherited default exists. Truthy primitives throw
/// at the actual `in` operation, matching Source rather than being boxed.
pub fn jsonSelfDefault(engine: *v.em.Engine, value: c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine }; defer s.deinit();
    if (s.truthy(value) and !try v.js.hasKey(engine, value, try s.text("default"))) {
        const object = try s.global("Object");
        const define = try s.get(object, "defineProperty");
        const descriptor = try s.object();
        try put(engine, descriptor, "value", value);
        try put(engine, descriptor, "enumerable", c.pi_js_bool(engine.context, 0));
        _ = try s.call(define, object, &.{ value, try s.text("default"), descriptor });
    }
    return c.JS_DupValue(engine.context, value);
}
/// The synchronous expression after jiti.import's one genuine Await. Caller
/// owns its AsyncFunction/awaited operation; this helper creates no Promise.
pub fn importDefault(engine: *v.em.Engine, module: c.JSValue, options: c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine }; defer s.deinit();
    if (v.nullish(options) or !s.truthy(try s.get(options, "default"))) return c.JS_DupValue(engine.context, module);
    const def = if (v.nullish(module)) c.pi_js_undefined() else try s.get(module, "default");
    return c.JS_DupValue(engine.context, if (v.nullish(def)) module else def);
}
