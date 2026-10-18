//! Auth-helper-local operations; raw pending event is held before returned-root
//! retirement. This does not change Engine or global callback policy.
const v = @import("native_ai_provider_values.zig");
pub const Scope = v.Scope;
pub const c = v.c;
pub const em = v.em;
pub const owned = @import("native_sdk_owned_completion.zig");
pub const af = @import("native_async_function.zig");
pub const Ops = struct {
    s: *Scope,
    pub fn own(o: *Ops, value: c.JSValue) !c.JSValue {
        return owned.ownRoot(o.s, value);
    }
    pub fn accept(o: *Ops, value: c.JSValue) !c.JSValue {
        const engine = o.s.engine;
        // Only actual pending/current-invocation producer authority crosses
        // guest operations. A private DATA birth inside one getter/call is
        // still DATA if that same guest operation later throws it ordinarily.
        _ = engine.nativeCallbackResult(c.pi_js_undefined());
        if (c.JS_HasException(engine.context)) {
            var outcome = owned.Completion.initValue(engine, @as(anyerror!c.JSValue, error.JavaScriptException));
            if (!c.JS_IsException(value)) outcome.release(value);
            return o.own(try outcome.finishValue());
        }
        return o.own(try engine.checked(value));
    }
    pub fn failed(o: *Ops) anyerror {
        _ = o.accept(c.pi_js_undefined()) catch |err| return err;
        return error.MissingAuthHelperPendingFailure;
    }
    pub fn get(o: *Ops, target: c.JSValue, name: [*:0]const u8) !c.JSValue {
        try o.s.engine.checkNativeEntry();
        return o.accept(c.JS_GetPropertyStr(o.s.engine.context, target, name));
    }
    pub fn global(o: *Ops, name: [*:0]const u8) !c.JSValue {
        const global_object = try o.own(c.JS_GetGlobalObject(o.s.engine.context)); return o.get(global_object, name);
    }
    pub fn call(o: *Ops, function: c.JSValue, receiver: c.JSValue, args: []const c.JSValue) !c.JSValue {
        try o.s.engine.checkNativeEntry();
        return o.accept(c.JS_Call(o.s.engine.context, function, receiver, @intCast(args.len), @constCast(args.ptr)));
    }
    pub fn invoke(o: *Ops, receiver: c.JSValue, name: [*:0]const u8, args: []const c.JSValue) !c.JSValue { return o.call(try o.get(receiver, name), receiver, args); }
    fn allocation(o: *Ops, value: c.JSValue) !c.JSValue {
        if (c.JS_IsException(value)) { const reason = c.JS_GetException(o.s.engine.context); c.JS_SetUncatchableError(o.s.engine.context, reason); return o.own(try o.s.engine.checked(c.JS_Throw(o.s.engine.context, reason))); }
        return o.own(try o.s.engine.checked(value));
    }
    pub fn text(o: *Ops, value: []const u8) !c.JSValue { try o.s.engine.checkNativeEntry(); return o.allocation(c.JS_NewStringLen(o.s.engine.context, value.ptr, value.len)); }
    pub fn object(o: *Ops) !c.JSValue { try o.s.engine.checkNativeEntry(); return o.allocation(c.JS_NewObject(o.s.engine.context)); }
    pub fn cell(o: *Ops) !c.JSValue { try o.s.engine.checkNativeEntry(); return o.allocation(c.JS_NewObjectProto(o.s.engine.context, c.pi_js_null())); }
    pub fn put(o: *Ops, target: c.JSValue, name: [*:0]const u8, value: c.JSValue) !void {
        try o.s.engine.checkNativeEntry();
        if (c.JS_DefinePropertyValueStr(o.s.engine.context, target, name, c.JS_DupValue(o.s.engine.context, value), c.JS_PROP_C_W_E) < 0) { _ = try o.allocation(c.JS_Throw(o.s.engine.context, c.JS_GetException(o.s.engine.context))); unreachable; }
        try o.s.engine.checkNativeEntry();
    }
    pub fn binary(o: *Ops, operation: c_int, a: c.JSValue, b: c.JSValue) !c.JSValue {
        try o.s.engine.checkNativeEntry();
        return o.accept(c.JS_PiBinaryOperator(o.s.engine.context, operation, a, b));
    }
    pub fn getKey(o: *Ops, receiver: c.JSValue, key: c.JSValue) !c.JSValue {
        try o.s.engine.checkNativeEntry();
        const atom = c.JS_ValueToAtom(o.s.engine.context, key);
        if (atom == c.JS_ATOM_NULL) return o.failed();
        defer c.JS_FreeAtom(o.s.engine.context, atom);
        // Success+pending coercion is normalized before entering the getter.
        try o.s.engine.checkNativeEntry();
        return o.accept(c.JS_GetProperty(o.s.engine.context, receiver, atom));
    }
    pub fn stringify(o: *Ops, value: c.JSValue) !c.JSValue {
        try o.s.engine.checkNativeEntry();
        return o.accept(c.JS_ToString(o.s.engine.context, value));
    }
    pub fn truthy(o: *Ops, value: c.JSValue) bool { return o.s.truthy(value); }
};
pub fn arg(args: []const c.JSValue, index: usize) c.JSValue { return if (index < args.len) args[index] else c.pi_js_undefined(); }
pub fn nullish(value: c.JSValue) bool { return c.JS_IsNull(value) or c.JS_IsUndefined(value); }
pub fn finishInvocation(engine: *em.Engine, invocation: *em.Engine.NativeInvocation, result: anyerror!c.JSValue) !c.JSValue {
    const raw = result catch |err| @import("native_sdk.zig").fail(engine, err);
    return engine.checked(engine.leaveNativeInvocation(invocation, raw));
}
