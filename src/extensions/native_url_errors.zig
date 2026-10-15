//! Node24 URL coercion and errors. Parse errors from the native binding are
//! ordinary TypeErrors; missing-argument and href-setter errors are NodeErrors.
const em = @import("engine.zig");
const js = @import("native_js_values.zig");
const c = em.c;
const Scope = @import("native_models_stream_scope.zig").Scope;
fn typeError(engine: *em.Engine, message: [*:0]const u8) !c.JSValue {
    _ = c.JS_ThrowTypeError(engine.context, "%s", message);
    const value = c.JS_GetException(engine.context);
    if (!c.JS_IsError(value)) return engine.checked(c.JS_Throw(engine.context, value));
    return value;
}
fn throwValue(engine: *em.Engine, value: c.JSValue) anyerror {
    _ = engine.checked(c.JS_Throw(engine.context, c.JS_DupValue(engine.context, value))) catch |err| return err;
    unreachable;
}
fn coercionError(engine: *em.Engine, message: [*:0]const u8) anyerror {
    const value = typeError(engine, message) catch |err| return err;
    defer engine.freeValue(value);
    return throwValue(engine, value);
}
/// Template interpolation applies ToPrimitive with the string hint. Keeping
/// the primitive as a VM value retains lone surrogates in error.input/base.
pub fn string(engine: *em.Engine, value: c.JSValue) !c.JSValue {
    if (!c.JS_IsObject(value)) {
        if (c.JS_IsSymbol(value)) return coercionError(engine, "Cannot convert a Symbol value to a string");
        return engine.checked(c.JS_ToString(engine.context, value));
    }
    const symbol = try engine.checked(c.JS_GetToPrimitiveSymbol(engine.context));
    defer engine.freeValue(symbol);
    const atom = c.JS_ValueToAtom(engine.context, symbol);
    if (atom == c.JS_ATOM_NULL) return js.capture(engine);
    defer c.JS_FreeAtom(engine.context, atom);
    const method = try engine.checked(c.JS_GetProperty(engine.context, value, atom));
    defer engine.freeValue(method);
    if (!c.JS_IsUndefined(method) and !c.JS_IsNull(method)) {
        // Calling a non-callable method is still a conversion TypeError; any
        // user exception thrown by an actual method is retained without inspection.
        const hint = try engine.checked(c.JS_NewString(engine.context, "string"));
        defer engine.freeValue(hint);
        const result = try js.call(engine, method, value, &.{hint});
        defer engine.freeValue(result);
        if (c.JS_IsObject(result)) return coercionError(engine, "Cannot convert object to primitive value");
        return string(engine, result);
    }
    inline for (.{ "toString", "valueOf" }) |key| {
        const ordinary = try js.get(engine, value, key);
        defer engine.freeValue(ordinary);
        if (c.JS_IsFunction(engine.context, ordinary)) {
            const result = try js.call(engine, ordinary, value, &.{});
            defer engine.freeValue(result);
            if (!c.JS_IsObject(result)) return string(engine, result);
        }
    }
    return coercionError(engine, "Cannot convert object to primitive value");
}
fn nodeToString(context: ?*c.JSContext, receiver: c.JSValue, _: c_int, _: [*c]c.JSValue, _: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    engine.native_exception_diagnostics_suppressed += 1;
    defer engine.native_exception_diagnostics_suppressed -= 1;
    return nodeString(engine, receiver, roots[0]) catch |err| @import("native_sdk.zig").fail(engine, err);
}
fn nodeString(engine: *em.Engine, receiver: c.JSValue, code: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const name = try scope.own(try string(engine, try scope.get(receiver, "name")));
    const prefix = try scope.concat(try scope.concat(name, try scope.text(" [")), code);
    const message = try scope.own(try string(engine, try scope.get(receiver, "message")));
    return c.JS_DupValue(engine.context, try scope.concat(try scope.concat(prefix, try scope.text("]: ")), message));
}
fn constructorGetter(context: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue, _: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    return c.JS_DupValue(context, roots[0]);
}
/// The two private NodeError prototypes are rooted by the URL constructor,
/// setters and static methods. Errors of the same family share their prototype.
pub fn families(engine: *em.Engine) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const sample = try scope.own(try typeError(engine, ""));
    const base = try scope.own(try engine.checked(c.JS_GetPrototype(engine.context, sample)));
    const constructor = try scope.get(base, "constructor");
    const output = try scope.object();
    inline for (.{ .{ "missing", "ERR_MISSING_ARGS" }, .{ "setter", "ERR_INVALID_URL" } }) |row| {
        const prototype = try scope.own(try engine.checked(c.JS_NewObjectProto(engine.context, base)));
        var code_roots = [_]c.JSValue{try scope.text(row[1])};
        const method = try scope.own(try engine.checked(c.JS_NewCFunctionData2(engine.context, nodeToString, "toString", 0, 0, 1, &code_roots)));
        if (c.JS_DefinePropertyValueStr(engine.context, prototype, "toString", c.JS_DupValue(engine.context, method), c.JS_PROP_WRITABLE | c.JS_PROP_CONFIGURABLE) < 0) return js.capture(engine);
        var getter_roots = [_]c.JSValue{constructor};
        const getter = try scope.own(try engine.checked(c.JS_NewCFunctionData2(engine.context, constructorGetter, "get constructor", 0, 0, 1, &getter_roots)));
        const atom = c.JS_NewAtom(engine.context, "constructor");
        if (atom == c.JS_ATOM_NULL) return js.capture(engine);
        defer c.JS_FreeAtom(engine.context, atom);
        if (c.JS_DefinePropertyGetSet(engine.context, prototype, atom, c.JS_DupValue(engine.context, getter), c.pi_js_undefined(), c.JS_PROP_CONFIGURABLE) < 0) return js.capture(engine);
        try scope.put(output, row[0], prototype);
    }
    return c.JS_DupValue(engine.context, output);
}
fn define(engine: *em.Engine, error_value: c.JSValue, key: [*:0]const u8, value: c.JSValue, enumerable: bool) !void {
    if (c.JS_DefinePropertyValueStr(engine.context, error_value, key, c.JS_DupValue(engine.context, value), c.JS_PROP_CONFIGURABLE | c.JS_PROP_WRITABLE | (if (enumerable) @as(c_int, c.JS_PROP_ENUMERABLE) else 0)) < 0) return js.capture(engine);
}
fn nodeError(engine: *em.Engine, family: c.JSValue, key: [*:0]const u8, code: []const u8, message: []const u8, input: ?c.JSValue) anyerror {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const value = scope.own(typeError(engine, "") catch |err| return err) catch |err| return err;
    // super() has no own message; the NodeError field initializer defines code
    // before getMessage defines input and finally the non-enumerable message.
    const atom = c.JS_NewAtom(engine.context, "message");
    if (atom == c.JS_ATOM_NULL) return js.capture(engine);
    defer c.JS_FreeAtom(engine.context, atom);
    if (c.JS_DeleteProperty(engine.context, value, atom, c.JS_PROP_THROW) < 0) return js.capture(engine);
    const prototype = scope.get(family, key) catch |err| return err;
    if (c.JS_SetPrototype(engine.context, value, prototype) < 0) return js.capture(engine);
    define(engine, value, "code", scope.text(code) catch |err| return err, true) catch |err| return err;
    if (input) |text| define(engine, value, "input", text, true) catch |err| return err;
    define(engine, value, "message", scope.text(message) catch |err| return err, false) catch |err| return err;
    return throwValue(engine, value);
}
pub fn missing(engine: *em.Engine, family: c.JSValue) anyerror {
    return nodeError(engine, family, "missing", "ERR_MISSING_ARGS", "The \"url\" argument must be specified", null);
}
pub fn setter(engine: *em.Engine, family: c.JSValue, input: c.JSValue) anyerror {
    return nodeError(engine, family, "setter", "ERR_INVALID_URL", "Invalid URL", input);
}
pub fn invalid(engine: *em.Engine, input: c.JSValue, base: c.JSValue) anyerror {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const value = scope.own(typeError(engine, "Invalid URL") catch |err| return err) catch |err| return err;
    define(engine, value, "code", scope.text("ERR_INVALID_URL") catch |err| return err, true) catch |err| return err;
    define(engine, value, "input", input, true) catch |err| return err;
    if (!c.JS_IsUndefined(base)) define(engine, value, "base", base, true) catch |err| return err;
    return throwValue(engine, value);
}
