//! Shared native Node local Scope. Guest-capable operations preserve actual
//! pending/B1 without deriving fatality from a private DATA birth span.
//! Provider Scope, Engine and C/ABI are unchanged.
const v = @import("native_ai_provider_values.zig");
const c = v.c;
const Boundary = @import("native_node_commonjs_owned_boundary.zig").Boundary;
pub const Scope = struct {
    engine: *v.em.Engine,
    values: v.Scope,
    boundary: Boundary,
    pub fn init(engine: *v.em.Engine) Scope { return .{ .engine = engine, .values = .{ .engine = engine }, .boundary = Boundary.begin(engine) }; }
    pub fn pending(self: *Scope) !void { try self.boundary.checkCurrent(); }
    pub fn beforeAllocation(self: *Scope) !u64 { return self.boundary.beforeAllocation(); }
    pub fn own(self: *Scope, value: c.JSValue) !c.JSValue { return self.boundary.own(&self.values, value); }
    /// Raw result with no supplied operation provenance. Do not recover an
    /// earlier generation from the whole Scope or a captured diagnostic.
    pub fn checked(self: *Scope, value: c.JSValue) !c.JSValue {
        self.boundary.checkPendingSince(null) catch |err| { var owned = value; self.boundary.release(&owned); return err; };
        if (c.JS_IsException(value)) return error.MissingActualCJSBootstrapReason;
        return self.own(value);
    }
    /// Only for a non-guest raw producer (e.g. NewString/NewObject). Never use
    /// this tag span around getters, JS calls/constructors or coercion.
    pub fn checkedAllocation(self: *Scope, value: c.JSValue, generation: u64) !c.JSValue {
        self.boundary.checkPendingSince(generation) catch |err| { var owned = value; self.boundary.release(&owned); return err; };
        if (c.JS_IsException(value)) return error.MissingActualCJSBootstrapReason;
        return self.own(value);
    }
    pub fn get(self: *Scope, receiver: c.JSValue, name: [*:0]const u8) !c.JSValue {
        try self.pending(); return self.checked(c.JS_GetPropertyStr(self.engine.context, receiver, name));
    }
    fn atom(self: *Scope, key: c.JSValue) !c.JSAtom {
        try self.pending(); const value = try v.js.atom(self.engine, key);
        self.pending() catch |err| { c.JS_FreeAtom(self.engine.context, value); return err; }; return value;
    }
    pub fn getKey(self: *Scope, receiver: c.JSValue, key: c.JSValue) !c.JSValue {
        const property = try self.atom(key); defer c.JS_FreeAtom(self.engine.context, property);
        try self.pending(); return self.checked(c.JS_GetProperty(self.engine.context, receiver, property));
    }
    pub fn hasKey(self: *Scope, receiver: c.JSValue, key: c.JSValue) !bool {
        const property = try self.atom(key); defer c.JS_FreeAtom(self.engine.context, property);
        try self.pending(); const status = c.JS_HasProperty(self.engine.context, receiver, property); try self.pending();
        if (status < 0) return error.MissingActualNodeHasReason; return status != 0;
    }
    pub fn prototype(self: *Scope, receiver: c.JSValue) !c.JSValue { try self.pending(); return self.checked(c.JS_GetPrototype(self.engine.context, receiver)); }
    /// Descriptor fields are owned only when status>0. Keep them local so their
    /// Source lifetime ends at the caller's original defer, not Scope.finish.
    pub fn descriptor(self: *Scope, receiver: c.JSValue, key: c.JSValue) !?c.JSPropertyDescriptor {
        const property = try self.atom(key); defer c.JS_FreeAtom(self.engine.context, property);
        try self.pending(); var result: c.JSPropertyDescriptor = undefined;
        const status = c.JS_GetOwnProperty(self.engine.context, &result, receiver, property);
        self.pending() catch |err| { if (status > 0) self.releaseDescriptor(&result); return err; };
        if (status < 0) return error.MissingActualNodeDescriptorReason;
        return if (status == 0) null else result;
    }
    pub fn releaseDescriptor(self: *Scope, descriptor_value: *c.JSPropertyDescriptor) void {
        self.boundary.release(&descriptor_value.value); self.boundary.release(&descriptor_value.getter); self.boundary.release(&descriptor_value.setter);
    }
    pub fn hasOwn(self: *Scope, receiver: c.JSValue, key: c.JSValue) !bool {
        var item = try self.descriptor(receiver, key) orelse return false; defer self.releaseDescriptor(&item); return true;
    }
    pub fn text(self: *Scope, bytes: []const u8) !c.JSValue {
        const generation = try self.beforeAllocation(); return self.checkedAllocation(c.JS_NewStringLen(self.engine.context, bytes.ptr, bytes.len), generation);
    }
    pub fn call(self: *Scope, function: c.JSValue, receiver: c.JSValue, args: []const c.JSValue) !c.JSValue {
        try self.pending(); return self.checked(c.JS_Call(self.engine.context, function, receiver, @intCast(args.len), @constCast(args.ptr)));
    }
    pub fn construct(self: *Scope, function: c.JSValue, args: []const c.JSValue) !c.JSValue {
        try self.pending(); return self.checked(c.JS_CallConstructor(self.engine.context, function, @intCast(args.len), @constCast(args.ptr)));
    }
    pub fn object(self: *Scope) !c.JSValue { const generation = try self.beforeAllocation(); return self.checkedAllocation(c.JS_NewObject(self.engine.context), generation); }
    pub fn objectProto(self: *Scope, prototype_value: c.JSValue) !c.JSValue { const generation = try self.beforeAllocation(); return self.checkedAllocation(c.JS_NewObjectProto(self.engine.context, prototype_value), generation); }
    pub fn define(self: *Scope, object_value: c.JSValue, name: [*:0]const u8, value: c.JSValue, flags: c_int) !void {
        try self.pending(); const status = c.JS_DefinePropertyValueStr(self.engine.context, object_value, name, c.JS_DupValue(self.engine.context, value), flags | c.JS_PROP_THROW);
        try self.pending(); if (status < 0) return error.MissingActualNodeDefineReason;
    }
    pub fn put(self: *Scope, receiver: c.JSValue, name: [*:0]const u8, value: c.JSValue) !void {
        try self.pending();
        const status = c.JS_SetPropertyStr(self.engine.context, receiver, name, c.JS_DupValue(self.engine.context, value));
        try self.boundary.checkCurrent();
        if (status < 0) return error.MissingActualCJSBootstrapWriteReason;
    }
    pub fn binary(self: *Scope, operation_id: c_int, left: c.JSValue, right: c.JSValue) !c.JSValue {
        try self.pending(); return self.checked(c.JS_PiBinaryOperator(self.engine.context, operation_id, left, right));
    }
    pub fn toString(self: *Scope, value: c.JSValue) !c.JSValue {
        try self.pending(); return self.checked(c.JS_ToString(self.engine.context, value));
    }
    pub fn truthy(self: *Scope, value: c.JSValue) bool { return c.JS_ToBool(self.engine.context, value) == 1; }
    pub fn equal(self: *Scope, left: c.JSValue, right: c.JSValue) bool { return c.JS_IsStrictEqual(self.engine.context, left, right); }
    pub fn finish(self: *Scope, result: anyerror!c.JSValue) !c.JSValue { return self.boundary.finish(result, &self.values); }
};
