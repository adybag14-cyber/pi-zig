//! Internal builtin owner local Scope, extracted verbatim from reviewed6be.
//! The shared provider Scope/Engine are unchanged; completion uses the SAME
//! CJS-local current/B1/DATA Boundary. This avoids importing public createRequire.
const v = @import("native_ai_provider_values.zig");
const c = v.c;
const Boundary = @import("native_node_commonjs_owned_boundary.zig").Boundary;
pub const Scope = struct {
    engine: *v.em.Engine,
    values: v.Scope,
    boundary: Boundary,
    pub fn init(engine: *v.em.Engine) Scope { return .{ .engine = engine, .values = .{ .engine = engine }, .boundary = Boundary.begin(engine) }; }
    pub fn pending(self: *Scope) !void {
        try self.boundary.checkCurrent();
    }
    pub fn own(self: *Scope, value: c.JSValue) !c.JSValue {
        if (c.JS_HasException(self.engine.context)) return self.boundary.rejectOwned(value);
        return self.boundary.own(&self.values, value);
    }
    pub fn checked(self: *Scope, value: c.JSValue) !c.JSValue {
        if (c.JS_HasException(self.engine.context)) return self.boundary.rejectOwned(value);
        if (c.JS_IsException(value)) return error.MissingActualCJSBootstrapReason;
        return self.own(try self.engine.checked(value));
    }
    pub fn get(self: *Scope, object: c.JSValue, name: [*:0]const u8) !c.JSValue { try self.pending(); return self.checked(c.JS_GetPropertyStr(self.engine.context, object, name)); }
    pub fn text(self: *Scope, bytes: []const u8) !c.JSValue { try self.pending(); return self.checked(c.JS_NewStringLen(self.engine.context, bytes.ptr, bytes.len)); }
    pub fn call(self: *Scope, function: c.JSValue, receiver: c.JSValue, args: []const c.JSValue) !c.JSValue { try self.pending(); return self.checked(c.JS_Call(self.engine.context, function, receiver, @intCast(args.len), @constCast(args.ptr))); }
    pub fn construct(self: *Scope, function: c.JSValue, args: []const c.JSValue) !c.JSValue { try self.pending(); return self.checked(c.JS_CallConstructor(self.engine.context, function, @intCast(args.len), @constCast(args.ptr))); }
    pub fn put(self: *Scope, object: c.JSValue, name: [*:0]const u8, value: c.JSValue) !void {
        try self.pending();
        const status = c.JS_SetPropertyStr(self.engine.context, object, name, c.JS_DupValue(self.engine.context, value));
        if (c.JS_HasException(self.engine.context)) return self.boundary.rejectOwned(c.pi_js_undefined());
        if (status < 0) return error.MissingActualCJSBootstrapWriteReason;
    }
    pub fn truthy(self: *Scope, value: c.JSValue) bool { return c.JS_ToBool(self.engine.context, value) == 1; }
    pub fn finish(self: *Scope, result: anyerror!c.JSValue) !c.JSValue { return self.boundary.finish(result, &self.values); }
};
