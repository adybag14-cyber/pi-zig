//! SDK exec-local operations; raw pending event is held before returned-root
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
        if (o.s.inline_count < o.s.inline_values.len) { o.s.inline_values[o.s.inline_count] = value; o.s.inline_count += 1; return value; }
        o.s.values.append(o.s.engine.gpa, value) catch |err| {
            var outcome = owned.Completion.initValue(o.s.engine, @as(anyerror!c.JSValue, err)); outcome.release(value); return outcome.finishValue();
        };
        return value;
    }
    pub fn accept(o: *Ops, value: c.JSValue, generation: u64) !c.JSValue {
        const engine = o.s.engine;
        if (c.JS_HasException(engine.context)) {
            // This is an ACTUAL pending producer event. No Promise input or
            // historical diagnostic slot is used as classification authority.
            const reason = c.JS_GetException(engine.context);
            const tag = c.pi_js_native_allocation_error_generation(reason); const distance = tag -% generation;
            if (tag != 0 and distance != 0 and distance <= engine.native_allocation_generation -% generation) c.JS_SetUncatchableError(engine.context, reason);
            _ = c.JS_Throw(engine.context, reason);
            var outcome = owned.Completion.initValue(engine, @as(anyerror!c.JSValue, error.JavaScriptException));
            if (!c.JS_IsException(value)) outcome.release(value);
            return o.own(try outcome.finishValue());
        }
        return o.own(try engine.checked(value));
    }
    pub fn get(o: *Ops, target: c.JSValue, name: [*:0]const u8) !c.JSValue {
        try o.s.engine.checkNativeEntry(); const generation = o.s.engine.native_allocation_generation;
        return o.accept(c.JS_GetPropertyStr(o.s.engine.context, target, name), generation);
    }
    pub fn global(o: *Ops, name: [*:0]const u8) !c.JSValue {
        const global_object = try o.own(c.JS_GetGlobalObject(o.s.engine.context)); return o.get(global_object, name);
    }
    pub fn call(o: *Ops, function: c.JSValue, receiver: c.JSValue, args: []const c.JSValue) !c.JSValue {
        try o.s.engine.checkNativeEntry(); const generation = o.s.engine.native_allocation_generation;
        return o.accept(c.JS_Call(o.s.engine.context, function, receiver, @intCast(args.len), @constCast(args.ptr)), generation);
    }
    pub fn invoke(o: *Ops, receiver: c.JSValue, name: [*:0]const u8, args: []const c.JSValue) !c.JSValue { return o.call(try o.get(receiver, name), receiver, args); }
    pub fn construct(o: *Ops, constructor: c.JSValue, args: []const c.JSValue) !c.JSValue {
        try o.s.engine.checkNativeEntry(); const generation = o.s.engine.native_allocation_generation;
        return o.accept(c.JS_CallConstructor(o.s.engine.context, constructor, @intCast(args.len), @constCast(args.ptr)), generation);
    }
    fn allocation(o: *Ops, value: c.JSValue) !c.JSValue {
        if (c.JS_IsException(value)) { const reason = c.JS_GetException(o.s.engine.context); c.JS_SetUncatchableError(o.s.engine.context, reason); return o.own(try o.s.engine.checked(c.JS_Throw(o.s.engine.context, reason))); }
        return o.own(try o.s.engine.checked(value));
    }
    pub fn text(o: *Ops, value: []const u8) !c.JSValue { try o.s.engine.checkNativeEntry(); return o.allocation(c.JS_NewStringLen(o.s.engine.context, value.ptr, value.len)); }
    pub fn object(o: *Ops) !c.JSValue { try o.s.engine.checkNativeEntry(); return o.allocation(c.JS_NewObject(o.s.engine.context)); }
    pub fn cell(o: *Ops) !c.JSValue { try o.s.engine.checkNativeEntry(); return o.allocation(c.JS_NewObjectProto(o.s.engine.context, c.pi_js_null())); }
    pub fn array(o: *Ops) !c.JSValue { try o.s.engine.checkNativeEntry(); return o.allocation(c.JS_NewArray(o.s.engine.context)); }
    pub fn put(o: *Ops, target: c.JSValue, name: [*:0]const u8, value: c.JSValue) !void {
        try o.s.engine.checkNativeEntry();
        if (c.JS_DefinePropertyValueStr(o.s.engine.context, target, name, c.JS_DupValue(o.s.engine.context, value), c.JS_PROP_C_W_E) < 0) { _ = try o.allocation(c.JS_Throw(o.s.engine.context, c.JS_GetException(o.s.engine.context))); unreachable; }
        try o.s.engine.checkNativeEntry();
    }
    pub fn index(o: *Ops, target: c.JSValue, position: u32, value: c.JSValue) !void {
        try o.s.engine.checkNativeEntry();
        if (c.JS_DefinePropertyValueUint32(o.s.engine.context, target, position, c.JS_DupValue(o.s.engine.context, value), c.JS_PROP_C_W_E) < 0) { _ = try o.allocation(c.JS_Throw(o.s.engine.context, c.JS_GetException(o.s.engine.context))); unreachable; }
        try o.s.engine.checkNativeEntry();
    }
    pub fn binary(o: *Ops, operation: c_int, a: c.JSValue, b: c.JSValue) !c.JSValue {
        try o.s.engine.checkNativeEntry(); const generation = o.s.engine.native_allocation_generation;
        return o.accept(c.JS_PiBinaryOperator(o.s.engine.context, operation, a, b), generation);
    }
    pub fn truthy(o: *Ops, value: c.JSValue) bool { return o.s.truthy(value); }
};
pub fn arg(args: []const c.JSValue, index: usize) c.JSValue { return if (index < args.len) args[index] else c.pi_js_undefined(); }
pub fn nullish(value: c.JSValue) bool { return c.JS_IsNull(value) or c.JS_IsUndefined(value); }
pub fn duplicate(engine: *em.Engine, value: anyerror!c.JSValue) anyerror!c.JSValue { return c.JS_DupValue(engine.context, try value); }
