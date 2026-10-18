//! SDK exec-local operations. Guest boundaries use the canonical SDK adapter;
//! private tags born within guest code are DATA, never producer authority.
const v = @import("native_ai_provider_values.zig");
pub const Scope = v.Scope;
pub const c = v.c;
pub const em = v.em;
pub const owned = @import("native_sdk_owned_completion.zig");
pub const af = @import("native_async_function.zig");
pub const guest = @import("native_sdk_guest_operation.zig");
pub const Ops = struct {
    s: *Scope,
    pub fn own(o: *Ops, value: c.JSValue) !c.JSValue { return owned.ownRoot(o.s, value); }
    pub fn get(o: *Ops, target: c.JSValue, name: [*:0]const u8) !c.JSValue { return guest.get(o.s, target, name); }
    pub fn global(o: *Ops, name: [*:0]const u8) !c.JSValue { return guest.global(o.s, name); }
    pub fn call(o: *Ops, function: c.JSValue, receiver: c.JSValue, args: []const c.JSValue) !c.JSValue { return guest.call(o.s, function, receiver, args); }
    pub fn invoke(o: *Ops, receiver: c.JSValue, name: [*:0]const u8, args: []const c.JSValue) !c.JSValue { return guest.invoke(o.s, receiver, name, args); }
    pub fn construct(o: *Ops, constructor: c.JSValue, args: []const c.JSValue) !c.JSValue { return guest.construct(o.s, constructor, args); }
    pub fn beforeAllocation(o: *Ops) !u64 {
        try o.s.engine.checkNativeEntry();
        return o.s.engine.native_allocation_generation;
    }
    /// Only raw non-guest allocation producers use this span. Getter/call/
    /// constructor/coercion spans stay entirely in the guest adapter above.
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
        // checked consumes the raw result on failure before ownRoot sees it.
        return o.own(try engine.checked(value));
    }
    pub fn text(o: *Ops, value: []const u8) !c.JSValue { const generation = try o.beforeAllocation(); return o.allocation(c.JS_NewStringLen(o.s.engine.context, value.ptr, value.len), generation); }
    pub fn object(o: *Ops) !c.JSValue { const generation = try o.beforeAllocation(); return o.allocation(c.JS_NewObject(o.s.engine.context), generation); }
    pub fn cell(o: *Ops) !c.JSValue { const generation = try o.beforeAllocation(); return o.allocation(c.JS_NewObjectProto(o.s.engine.context, c.pi_js_null()), generation); }
    pub fn array(o: *Ops) !c.JSValue { const generation = try o.beforeAllocation(); return o.allocation(c.JS_NewArray(o.s.engine.context), generation); }
    // These are Source literals/private lexical cells: define own C_W_E.
    pub fn put(o: *Ops, target: c.JSValue, name: [*:0]const u8, value: c.JSValue) !void { return guest.put(o.s, target, name, value); }
    pub fn index(o: *Ops, target: c.JSValue, position: u32, value: c.JSValue) !void { return guest.index(o.s, target, position, value); }
    pub fn binary(o: *Ops, operation: c_int, a: c.JSValue, b: c.JSValue) !c.JSValue { return guest.binary(o.s, operation, a, b); }
    pub fn truthy(o: *Ops, value: c.JSValue) bool { return o.s.truthy(value); }
};
pub fn arg(args: []const c.JSValue, index: usize) c.JSValue { return if (index < args.len) args[index] else c.pi_js_undefined(); }
pub fn nullish(value: c.JSValue) bool { return c.JS_IsNull(value) or c.JS_IsUndefined(value); }
pub fn duplicate(engine: *em.Engine, value: anyerror!c.JSValue) anyerror!c.JSValue { return c.JS_DupValue(engine.context, try value); }
