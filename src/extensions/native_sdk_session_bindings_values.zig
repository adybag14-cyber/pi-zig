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
    pub fn raw(self: *Scope, value: c.JSValue, _: u64) anyerror!c.JSValue {
        // A guest operation can create private DATA A successfully and then
        // throw A in this SAME operation. Neither its tag nor a generation
        // interval proves a native failure. C435 observes actual pending/B1;
        // rejected input and diagnostic/history are never fatal evidence.
        if (c.JS_IsException(value) and !c.JS_HasException(self.engine.context)) _ = c.JS_ThrowInternalError(self.engine.context, "Native session binding producer returned exception without pending reason");
        var completion = owned.Completion.initValue(self.engine, value);
        return completion.finishValue();
    }
    pub fn rawAllocation(self: *Scope, value: c.JSValue, generation: u64) anyerror!c.JSValue {
        // Reserved for the listed direct, no-guest VM allocators below and the
        // private null-prototype stage allocation. Never get/call/coercion.
        if (c.JS_HasException(self.engine.context)) {
            const reason = c.JS_GetException(self.engine.context);
            const tag = c.pi_js_native_allocation_error_generation(reason);
            const distance = tag -% generation;
            if (tag != 0 and distance != 0 and distance <= self.engine.native_allocation_generation -% generation) c.JS_SetUncatchableError(self.engine.context, reason);
            _ = c.JS_Throw(self.engine.context, reason);
        }
        return self.raw(value, generation);
    }
    pub fn own(self: *Scope, value: c.JSValue) anyerror!c.JSValue { return owned.ownRoot(self, value); }
    pub fn status(self: *Scope, value: c_int, generation: u64) anyerror!void {
        if (value < 0 and !c.JS_HasException(self.engine.context)) _ = c.JS_ThrowInternalError(self.engine.context, "Native session binding producer failed without pending reason");
        _ = try self.raw(c.pi_js_undefined(), generation);
    }
    fn beginGuest(self: *Scope, invocation: *em.Engine.NativeInvocation) !void {
        try self.engine.checkNativeEntry();
        self.engine.enterNativeInvocation(invocation);
    }
    fn finishGuest(self: *Scope, invocation: *em.Engine.NativeInvocation, value: c.JSValue, root_value: bool) anyerror!c.JSValue {
        // Invocation is caller-local/stable before the VM effect, and remains
        // active through raw-output normalization and ownRoot's failure cleanup.
        const normalized = self.raw(value, 0);
        const rooted: anyerror!c.JSValue = if (normalized) |result| (if (root_value) self.own(result) else result) else |err| err;
        const returned = self.engine.leaveNativeInvocation(invocation, if (rooted) |_| c.pi_js_undefined() else |err| @import("native_sdk.zig").fail(self.engine, err));
        var completion = owned.Completion.initValue(self.engine, returned);
        const completed = try completion.finishValue();
        self.engine.freeValue(completed); // Only the normal undefined exit.
        return rooted;
    }
    fn finishGuestStatus(self: *Scope, invocation: *em.Engine.NativeInvocation, value: c_int) anyerror!void {
        if (value < 0 and !c.JS_HasException(self.engine.context)) _ = c.JS_ThrowInternalError(self.engine.context, "Native session binding producer failed without pending reason");
        _ = try self.finishGuest(invocation, c.pi_js_undefined(), false);
    }
    pub fn get(self: *Scope, target: c.JSValue, name: [*:0]const u8) anyerror!c.JSValue {
        var invocation: em.Engine.NativeInvocation = .{};
        try self.beginGuest(&invocation);
        return self.finishGuest(&invocation, c.JS_GetPropertyStr(self.engine.context, target, name), true);
    }
    pub fn text(self: *Scope, bytes: []const u8) anyerror!c.JSValue {
        try self.engine.checkNativeEntry();
        const generation = self.engine.native_allocation_generation;
        return self.own(try self.rawAllocation(c.JS_NewStringLen(self.engine.context, bytes.ptr, bytes.len), generation));
    }
    pub fn object(self: *Scope) anyerror!c.JSValue {
        try self.engine.checkNativeEntry();
        const generation = self.engine.native_allocation_generation;
        return self.own(try self.rawAllocation(c.JS_NewObject(self.engine.context), generation));
    }
    pub fn call(self: *Scope, function: c.JSValue, receiver: c.JSValue, args: []const c.JSValue) anyerror!c.JSValue {
        var invocation: em.Engine.NativeInvocation = .{};
        try self.beginGuest(&invocation);
        return self.finishGuest(&invocation, c.JS_Call(self.engine.context, function, receiver, @intCast(args.len), @constCast(args.ptr)), true);
    }
    pub fn construct(self: *Scope, function: c.JSValue, args: []const c.JSValue) anyerror!c.JSValue {
        var invocation: em.Engine.NativeInvocation = .{};
        try self.beginGuest(&invocation);
        return self.finishGuest(&invocation, c.JS_CallConstructor(self.engine.context, function, @intCast(args.len), @constCast(args.ptr)), true);
    }
    pub fn invoke(self: *Scope, receiver: c.JSValue, name: [*:0]const u8, args: []const c.JSValue) anyerror!c.JSValue { return self.call(try self.get(receiver, name), receiver, args); }
    pub fn put(self: *Scope, target: c.JSValue, name: [*:0]const u8, value: c.JSValue) anyerror!void {
        try self.define(target, name, value, c.JS_PROP_C_W_E);
    }
    pub fn define(self: *Scope, target: c.JSValue, name: [*:0]const u8, value: c.JSValue, flags: c_int) anyerror!void {
        var invocation: em.Engine.NativeInvocation = .{};
        try self.beginGuest(&invocation);
        try self.finishGuestStatus(&invocation, c.JS_DefinePropertyValueStr(self.engine.context, target, name, c.JS_DupValue(self.engine.context, value), flags));
    }
    pub fn set(self: *Scope, target: c.JSValue, name: [*:0]const u8, value: c.JSValue) anyerror!void {
        var invocation: em.Engine.NativeInvocation = .{};
        try self.beginGuest(&invocation);
        try self.finishGuestStatus(&invocation, c.JS_SetPropertyStr(self.engine.context, target, name, c.JS_DupValue(self.engine.context, value)));
    }
    pub fn concat(self: *Scope, left: c.JSValue, right: c.JSValue) anyerror!c.JSValue {
        var invocation: em.Engine.NativeInvocation = .{};
        try self.beginGuest(&invocation);
        return self.finishGuest(&invocation, c.JS_PiBinaryOperator(self.engine.context, 0, left, right), true);
    }
    pub fn stringify(self: *Scope, value: c.JSValue) anyerror!c.JSValue {
        var invocation: em.Engine.NativeInvocation = .{};
        try self.beginGuest(&invocation);
        return self.finishGuest(&invocation, c.JS_ToString(self.engine.context, value), true);
    }
    pub fn truthy(self: *Scope, value: c.JSValue) bool { return c.JS_ToBool(self.engine.context, value) == 1; }
    pub fn equal(self: *Scope, left: c.JSValue, right: c.JSValue) bool { return c.JS_IsStrictEqual(self.engine.context, left, right); }
};
