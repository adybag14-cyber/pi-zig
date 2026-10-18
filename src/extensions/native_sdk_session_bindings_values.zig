//! Temporary roots and exact raw producers for the session binding leaf only.
//! Outcome escrow/retirement is the unchanged SDK owned completion contract.
const std = @import("std");
const em = @import("engine.zig");
const owned = @import("native_sdk_owned_completion.zig");
const c = em.c;
pub const Scope = struct {
    engine: *em.Engine,
    inline_values: [32]c.JSValue = undefined,
    inline_count: usize = 0,
    values: std.ArrayList(c.JSValue) = .empty,
    pub fn raw(self: *Scope, value: c.JSValue, generation: u64) anyerror!c.JSValue {
        // Only the ACTUAL pending reason of this producer has event authority.
        // Rejected Await input and captured diagnostic/history remain DATA.
        if (c.JS_HasException(self.engine.context)) {
            const reason = c.JS_GetException(self.engine.context);
            const tag = c.pi_js_native_allocation_error_generation(reason);
            const distance = tag -% generation;
            if (tag != 0 and distance != 0 and distance <= self.engine.native_allocation_generation -% generation) c.JS_SetUncatchableError(self.engine.context, reason);
            _ = c.JS_Throw(self.engine.context, reason);
        } else if (c.JS_IsException(value)) {
            _ = c.JS_ThrowInternalError(self.engine.context, "Native session binding producer returned exception without pending reason");
        }
        var completion = owned.Completion.initValue(self.engine, value);
        return completion.finishValue();
    }
    pub fn own(self: *Scope, value: c.JSValue) anyerror!c.JSValue { return owned.ownRoot(self, value); }
    pub fn status(self: *Scope, value: c_int, generation: u64) anyerror!void {
        if (value < 0 and !c.JS_HasException(self.engine.context)) _ = c.JS_ThrowInternalError(self.engine.context, "Native session binding producer failed without pending reason");
        _ = try self.raw(c.pi_js_undefined(), generation);
    }
    pub fn get(self: *Scope, target: c.JSValue, name: [*:0]const u8) anyerror!c.JSValue {
        const generation = self.engine.native_allocation_generation;
        return self.own(try self.raw(c.JS_GetPropertyStr(self.engine.context, target, name), generation));
    }
    pub fn text(self: *Scope, bytes: []const u8) anyerror!c.JSValue {
        const generation = self.engine.native_allocation_generation;
        return self.own(try self.raw(c.JS_NewStringLen(self.engine.context, bytes.ptr, bytes.len), generation));
    }
    pub fn object(self: *Scope) anyerror!c.JSValue {
        const generation = self.engine.native_allocation_generation;
        return self.own(try self.raw(c.JS_NewObject(self.engine.context), generation));
    }
    pub fn call(self: *Scope, function: c.JSValue, receiver: c.JSValue, args: []const c.JSValue) anyerror!c.JSValue {
        const generation = self.engine.native_allocation_generation;
        return self.own(try self.raw(c.JS_Call(self.engine.context, function, receiver, @intCast(args.len), @constCast(args.ptr)), generation));
    }
    pub fn invoke(self: *Scope, receiver: c.JSValue, name: [*:0]const u8, args: []const c.JSValue) anyerror!c.JSValue { return self.call(try self.get(receiver, name), receiver, args); }
    pub fn put(self: *Scope, target: c.JSValue, name: [*:0]const u8, value: c.JSValue) anyerror!void {
        const generation = self.engine.native_allocation_generation;
        try self.status(c.JS_DefinePropertyValueStr(self.engine.context, target, name, c.JS_DupValue(self.engine.context, value), c.JS_PROP_C_W_E), generation);
    }
    pub fn set(self: *Scope, target: c.JSValue, name: [*:0]const u8, value: c.JSValue) anyerror!void {
        const generation = self.engine.native_allocation_generation;
        try self.status(c.JS_SetPropertyStr(self.engine.context, target, name, c.JS_DupValue(self.engine.context, value)), generation);
    }
    pub fn concat(self: *Scope, left: c.JSValue, right: c.JSValue) anyerror!c.JSValue {
        const generation = self.engine.native_allocation_generation;
        return self.own(try self.raw(c.JS_PiBinaryOperator(self.engine.context, 0, left, right), generation));
    }
    pub fn stringify(self: *Scope, value: c.JSValue) anyerror!c.JSValue {
        const generation = self.engine.native_allocation_generation;
        return self.own(try self.raw(c.JS_ToString(self.engine.context, value), generation));
    }
    pub fn truthy(self: *Scope, value: c.JSValue) bool { return c.JS_ToBool(self.engine.context, value) == 1; }
    pub fn equal(self: *Scope, left: c.JSValue, right: c.JSValue) bool { return c.JS_IsStrictEqual(self.engine.context, left, right); }
};
