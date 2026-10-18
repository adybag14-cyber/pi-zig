//! Auth-helper operations use actual guest-operation boundaries. Allocation
//! provenance is considered only across direct native allocations.
const v = @import("native_ai_provider_values.zig");
pub const Scope = v.Scope;
pub const c = v.c;
pub const em = v.em;
pub const owned = @import("native_sdk_owned_completion.zig");
pub const guest = @import("native_sdk_guest_operation.zig");
pub const af = @import("native_async_function.zig");
pub const Ops = struct {
    s: *Scope,
    pub fn own(o: *Ops, value: c.JSValue) !c.JSValue {
        return owned.ownRoot(o.s, value);
    }
    pub fn accept(o: *Ops, value: c.JSValue) !c.JSValue {
        const engine = o.s.engine;
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
        return guest.get(o.s, target, name);
    }
    pub fn global(o: *Ops, name: [*:0]const u8) !c.JSValue {
        return guest.global(o.s, name);
    }
    pub fn call(o: *Ops, function: c.JSValue, receiver: c.JSValue, args: []const c.JSValue) !c.JSValue {
        return guest.call(o.s, function, receiver, args);
    }
    pub fn invoke(o: *Ops, receiver: c.JSValue, name: [*:0]const u8, args: []const c.JSValue) !c.JSValue {
        return guest.invoke(o.s, receiver, name, args);
    }
    pub fn beforeAllocation(o: *Ops) !u64 {
        try o.s.engine.checkNativeEntry();
        return o.s.engine.native_allocation_generation;
    }
    pub fn allocation(o: *Ops, value: c.JSValue, generation: u64) !c.JSValue {
        const engine = o.s.engine;
        _ = engine.nativeCallbackResult(c.pi_js_undefined());
        if (c.JS_HasException(engine.context)) {
            const reason = c.JS_GetException(engine.context);
            const tag = c.pi_js_native_allocation_error_generation(reason);
            const distance = tag -% generation;
            if (tag != 0 and distance != 0 and distance <= engine.native_allocation_generation -% generation)
                c.JS_SetUncatchableError(engine.context, reason);
            _ = c.JS_Throw(engine.context, reason);
        }
        return o.accept(value);
    }
    pub fn text(o: *Ops, value: []const u8) !c.JSValue {
        const generation = try o.beforeAllocation();
        return o.allocation(c.JS_NewStringLen(o.s.engine.context, value.ptr, value.len), generation);
    }
    pub fn object(o: *Ops) !c.JSValue {
        const generation = try o.beforeAllocation();
        return o.allocation(c.JS_NewObject(o.s.engine.context), generation);
    }
    pub fn cell(o: *Ops) !c.JSValue {
        const generation = try o.beforeAllocation();
        return o.allocation(c.JS_NewObjectProto(o.s.engine.context, c.pi_js_null()), generation);
    }
    pub fn put(o: *Ops, target: c.JSValue, name: [*:0]const u8, value: c.JSValue) !void {
        return guest.put(o.s, target, name, value);
    }
    pub fn binary(o: *Ops, operation: c_int, a: c.JSValue, b: c.JSValue) !c.JSValue {
        return guest.binary(o.s, operation, a, b);
    }
    pub fn getKey(o: *Ops, receiver: c.JSValue, key: c.JSValue) !c.JSValue {
        var boundary: guest.Boundary = .{ .engine = o.s.engine };
        try boundary.begin();
        const atom = c.JS_ValueToAtom(o.s.engine.context, key);
        defer if (atom != c.JS_ATOM_NULL) c.JS_FreeAtom(o.s.engine.context, atom);
        try boundary.finishStatus(if (atom == c.JS_ATOM_NULL) -1 else 0);
        return guest.getAtom(o.s, receiver, atom);
    }
    pub fn stringify(o: *Ops, value: c.JSValue) !c.JSValue {
        return guest.stringify(o.s, value);
    }
    pub fn truthy(o: *Ops, value: c.JSValue) bool { return o.s.truthy(value); }
};
pub fn arg(args: []const c.JSValue, index: usize) c.JSValue { return if (index < args.len) args[index] else c.pi_js_undefined(); }
pub fn nullish(value: c.JSValue) bool { return c.JS_IsNull(value) or c.JS_IsUndefined(value); }
pub fn finishInvocation(engine: *em.Engine, invocation: *em.Engine.NativeInvocation, result: anyerror!c.JSValue) !c.JSValue {
    const raw = result catch |err| @import("native_sdk.zig").fail(engine, err);
    return engine.checked(engine.leaveNativeInvocation(invocation, raw));
}
