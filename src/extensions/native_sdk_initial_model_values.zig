//! Resolver-local raw operations. Actual pending producers precede root storage
//! and root retirement; historical diagnostic/Promise payloads are only DATA.
pub const em = @import("engine.zig");
pub const c = em.c;
pub const af = @import("native_async_function.zig");
pub const owned = @import("native_sdk_owned_completion.zig");
pub const Scope = @import("native_models_stream_scope.zig").Scope;
pub const Ops = struct {
    s: *Scope,
    pub fn own(o: *Ops, value: c.JSValue) !c.JSValue { return owned.ownRoot(o.s, value); }
    pub fn accept(o: *Ops, value: c.JSValue, _: u64) !c.JSValue {
        const e = o.s.engine;
        _ = e.nativeCallbackResult(c.pi_js_undefined());
        if (c.JS_HasException(e.context)) {
            // Guest code can create successful fresh private DATA A and throw
            // A inside this SAME operation. Neither an operation generation
            // span nor a captured payload flag proves native failure origin.
            // Independently retained NativeInvocation/current producer events
            // have already been surfaced by nativeCallbackResult above.
            var completion = owned.Completion.initValue(e, @as(anyerror!c.JSValue, error.JavaScriptException));
            if (!c.JS_IsException(value)) completion.release(value);
            return o.own(try completion.finishValue());
        }
        return o.own(try e.checked(value));
    }
    pub fn get(o: *Ops, target: c.JSValue, name: [*:0]const u8) !c.JSValue {
        const e = o.s.engine; try e.checkNativeEntry(); const generation = e.native_allocation_generation;
        return o.accept(c.JS_GetPropertyStr(e.context, target, name), generation);
    }
    pub fn at(o: *Ops, target: c.JSValue, position: u32) !c.JSValue {
        const e = o.s.engine; try e.checkNativeEntry(); const generation = e.native_allocation_generation;
        return o.accept(c.JS_GetPropertyUint32(e.context, target, position), generation);
    }
    pub fn key(o: *Ops, target: c.JSValue, key_value: c.JSValue) !c.JSValue {
        // ToPropertyKey is observable. Use the VM's ordinary computed-property
        // operation rather than converting the key through a native string.
        const e = o.s.engine; try e.checkNativeEntry(); const generation = e.native_allocation_generation;
        const atom = c.JS_ValueToAtom(e.context, key_value);
        if (atom == c.JS_ATOM_NULL) return o.accept(c.JS_Throw(e.context, c.JS_GetException(e.context)), generation);
        defer c.JS_FreeAtom(e.context, atom);
        try e.checkNativeEntry();
        return o.accept(c.JS_GetProperty(e.context, target, atom), generation);
    }
    pub fn global(o: *Ops, name: [*:0]const u8) !c.JSValue {
        const e = o.s.engine; try e.checkNativeEntry(); const generation = e.native_allocation_generation;
        return o.get(try o.accept(c.JS_GetGlobalObject(e.context), generation), name);
    }
    pub fn iteratorSymbol(o: *Ops) !c.JSValue {
        const e = o.s.engine; try e.checkNativeEntry(); const generation = e.native_allocation_generation;
        return o.accept(c.JS_GetIteratorSymbol(e.context), generation);
    }
    pub fn call(o: *Ops, function: c.JSValue, receiver: c.JSValue, args: []const c.JSValue) !c.JSValue {
        const e = o.s.engine; try e.checkNativeEntry(); const generation = e.native_allocation_generation;
        return o.accept(c.JS_Call(e.context, function, receiver, @intCast(args.len), @constCast(args.ptr)), generation);
    }
    pub fn invoke(o: *Ops, receiver: c.JSValue, name: [*:0]const u8, args: []const c.JSValue) !c.JSValue { return o.own(try o.invokeOwned(receiver, name, args)); }
    /// Consumes method-expression temporaries before delivering the owned call
    /// value. The receiver/arguments are borrowed actual Source lexical refs.
    pub fn invokeOwned(o: *Ops, receiver: c.JSValue, name: [*:0]const u8, args: []const c.JSValue) !c.JSValue {
        var s: Scope = .{ .engine = o.s.engine }; var local: Ops = .{ .s = &s };
        return owned.finishValue(&s, invokeBody(&local, receiver, name, args));
    }
    fn invokeBody(o: *Ops, receiver: c.JSValue, name: [*:0]const u8, args: []const c.JSValue) !c.JSValue {
        const value = try o.call(try o.get(receiver, name), receiver, args);
        return c.JS_DupValue(o.s.engine.context, value);
    }
    pub fn allocation(o: *Ops, value: c.JSValue, generation: u64) !c.JSValue {
        if (c.JS_IsException(value) and c.JS_HasException(o.s.engine.context)) {
            const reason = c.JS_GetException(o.s.engine.context);
            c.JS_SetUncatchableError(o.s.engine.context, reason);
            return o.accept(c.JS_Throw(o.s.engine.context, reason), generation);
        }
        return o.accept(value, generation);
    }
    pub fn text(o: *Ops, bytes: []const u8) !c.JSValue {
        const e = o.s.engine; try e.checkNativeEntry(); const generation = e.native_allocation_generation;
        return o.allocation(c.JS_NewStringLen(e.context, bytes.ptr, bytes.len), generation);
    }
    pub fn object(o: *Ops) !c.JSValue {
        const e = o.s.engine; try e.checkNativeEntry(); const generation = e.native_allocation_generation;
        return o.allocation(c.JS_NewObject(e.context), generation);
    }
    pub fn array(o: *Ops) !c.JSValue {
        const e = o.s.engine; try e.checkNativeEntry(); const generation = e.native_allocation_generation;
        return o.allocation(c.JS_NewArray(e.context), generation);
    }
    pub fn put(o: *Ops, target: c.JSValue, name: [*:0]const u8, value: c.JSValue) !void {
        const e = o.s.engine; try e.checkNativeEntry();
        if (c.JS_DefinePropertyValueStr(e.context, target, name, c.JS_DupValue(e.context, value), c.JS_PROP_C_W_E) < 0) {
            // Direct CreateDataProperty on a newly owned native object.
            const reason = c.JS_GetException(e.context); c.JS_SetUncatchableError(e.context, reason);
            _ = try e.checked(c.JS_Throw(e.context, reason)); unreachable;
        }
        try e.checkNativeEntry();
    }
    pub fn index(o: *Ops, target: c.JSValue, position: u32, value: c.JSValue) !void {
        const e = o.s.engine; try e.checkNativeEntry();
        if (c.JS_DefinePropertyValueUint32(e.context, target, position, c.JS_DupValue(e.context, value), c.JS_PROP_C_W_E) < 0) {
            const reason = c.JS_GetException(e.context); c.JS_SetUncatchableError(e.context, reason);
            _ = try e.checked(c.JS_Throw(e.context, reason)); unreachable;
        }
        try e.checkNativeEntry();
    }
    pub fn binary(o: *Ops, operation: c_int, left: c.JSValue, right: c.JSValue) !c.JSValue {
        const e = o.s.engine; try e.checkNativeEntry(); const generation = e.native_allocation_generation;
        return o.accept(c.JS_PiBinaryOperator(e.context, operation, left, right), generation);
    }
    pub fn stringify(o: *Ops, value: c.JSValue) !c.JSValue {
        const e = o.s.engine; try e.checkNativeEntry(); const generation = e.native_allocation_generation;
        return o.accept(c.JS_ToString(e.context, value), generation);
    }
    pub fn truthy(o: *Ops, value: c.JSValue) bool { return c.JS_ToBool(o.s.engine.context, value) == 1; }
    pub fn equal(o: *Ops, a: c.JSValue, b: c.JSValue) bool { return c.JS_IsStrictEqual(o.s.engine.context, a, b); }
    pub fn typeError(o: *Ops, message: [*:0]const u8) anyerror {
        _ = o.s.engine.checked(c.JS_ThrowTypeError(o.s.engine.context, "%s", message)) catch |err| return err;
        unreachable;
    }
};
pub fn nullish(value: c.JSValue) bool { return c.JS_IsNull(value) or c.JS_IsUndefined(value); }
