//! Chalk-local raw producer boundary; retirement uses the exact reviewed SDK
//! completion helper. No shared Scope/Engine policy or whole-call tag rescans.
const std = @import("std");
const em = @import("engine.zig");
const owned = @import("native_sdk_owned_completion.zig");
const arithmetic = @import("native_image_arithmetic.zig");
const c = em.c;
pub const Scope = struct {
    engine: *em.Engine,
    inline_values: [32]c.JSValue = undefined,
    inline_count: usize = 0,
    values: std.ArrayList(c.JSValue) = .empty,
    /// Guest operations may successfully create private DATA A and throw A in
    /// the SAME operation. A generation interval never proves that failure.
    pub fn raw(self: *Scope, value: c.JSValue, _: u64) anyerror!c.JSValue {
        if (c.JS_IsException(value) and !c.JS_HasException(self.engine.context)) _ = c.JS_ThrowInternalError(self.engine.context, "Native Chalk producer returned exception without pending reason");
        var completion = owned.Completion.initValue(self.engine, value);
        return completion.finishValue();
    }
    /// Only explicitly listed direct no-guest VM allocations use this path.
    pub fn rawAllocation(self: *Scope, value: c.JSValue, generation: u64) anyerror!c.JSValue {
        if (c.JS_HasException(self.engine.context)) {
            const reason = c.JS_GetException(self.engine.context);
            const tag = c.pi_js_native_allocation_error_generation(reason);
            const distance = tag -% generation;
            if (tag != 0 and distance != 0 and distance <= self.engine.native_allocation_generation -% generation) c.JS_SetUncatchableError(self.engine.context, reason);
            _ = c.JS_Throw(self.engine.context, reason);
        }
        return self.raw(value, generation);
    }
    pub fn status(self: *Scope, result: c_int, generation: u64) anyerror!void {
        if (result < 0 and !c.JS_HasException(self.engine.context)) _ = c.JS_ThrowInternalError(self.engine.context, "Native Chalk producer failed without pending reason");
        _ = try self.raw(c.pi_js_undefined(), generation);
    }
    pub fn own(self: *Scope, value: c.JSValue) anyerror!c.JSValue {
        const checked = try self.raw(value, self.engine.native_allocation_generation);
        return owned.ownRoot(self, checked);
    }
    fn beginGuest(self: *Scope, invocation: *em.Engine.NativeInvocation) !void {
        try self.engine.checkNativeEntry();
        self.engine.enterNativeInvocation(invocation);
    }
    fn finishGuest(self: *Scope, invocation: *em.Engine.NativeInvocation, value: c.JSValue, root_value: bool) anyerror!c.JSValue {
        const normalized = self.raw(value, 0);
        const rooted: anyerror!c.JSValue = if (normalized) |result| (if (root_value) self.own(result) else result) else |err| err;
        return self.finishGuestRooted(invocation, rooted);
    }
    fn finishGuestRooted(self: *Scope, invocation: *em.Engine.NativeInvocation, rooted: anyerror!c.JSValue) anyerror!c.JSValue {
        // Scope owns rooted: consuming leave receives an owned undefined, not
        // that borrowed root. Invocation survives normalization/append cleanup.
        if (rooted) |_| {} else |err| {
            if (err == error.OutOfMemory) _ = self.engine.throwNativeOutOfMemoryFatal();
        }
        const returned = self.engine.leaveNativeInvocation(invocation, c.pi_js_undefined());
        if (c.JS_IsException(returned) or c.JS_HasException(self.engine.context)) {
            var completion = owned.Completion.initValue(self.engine, returned);
            const completed = try completion.finishValue();
            self.engine.freeValue(completed);
        } else self.engine.freeValue(returned);
        // No unconditional post-completion on normal leave: captured ordinary
        // failure DATA belongs to the caller and must not become a new throw.
        return rooted;
    }
    fn finishGuestAtom(self: *Scope, invocation: *em.Engine.NativeInvocation, value: c.JSValue, atom_value: c.JSAtom) anyerror!c.JSValue {
        const normalized = self.raw(value, 0);
        var completion = owned.Completion.initVoid(self.engine, if (normalized) |_| {} else |err| err);
        completion.release(c.pi_js_undefined());
        const generation = self.engine.native_allocation_generation;
        c.JS_FreeAtom(self.engine.context, atom_value);
        _ = self.rawAllocation(c.pi_js_undefined(), generation) catch {};
        const retired = completion.finishVoid();
        return self.finishGuestRooted(invocation, if (retired) |_| normalized else |err| err);
    }
    fn finishGuestStatus(self: *Scope, invocation: *em.Engine.NativeInvocation, value: c_int) anyerror!void {
        if (value < 0 and !c.JS_HasException(self.engine.context)) _ = c.JS_ThrowInternalError(self.engine.context, "Native Chalk producer failed without pending reason");
        _ = try self.finishGuest(invocation, c.pi_js_undefined(), false);
    }
    pub fn get(self: *Scope, object_value: c.JSValue, name: [*:0]const u8) anyerror!c.JSValue {
        var invocation: em.Engine.NativeInvocation = .{};
        try self.beginGuest(&invocation);
        return self.finishGuest(&invocation, c.JS_GetPropertyStr(self.engine.context, object_value, name), true);
    }
    pub fn global(self: *Scope, name: [*:0]const u8) anyerror!c.JSValue {
        const generation = self.engine.native_allocation_generation;
        return self.get(try self.own(try self.rawAllocation(c.JS_GetGlobalObject(self.engine.context), generation)), name);
    }
    pub fn text(self: *Scope, bytes: []const u8) anyerror!c.JSValue { try self.engine.checkNativeEntry(); const generation = self.engine.native_allocation_generation; return self.own(try self.rawAllocation(c.JS_NewStringLen(self.engine.context, bytes.ptr, bytes.len), generation)); }
    pub fn object(self: *Scope) anyerror!c.JSValue { try self.engine.checkNativeEntry(); const generation = self.engine.native_allocation_generation; return self.own(try self.rawAllocation(c.JS_NewObject(self.engine.context), generation)); }
    pub fn array(self: *Scope) anyerror!c.JSValue { try self.engine.checkNativeEntry(); const generation = self.engine.native_allocation_generation; return self.own(try self.rawAllocation(c.JS_NewArray(self.engine.context), generation)); }
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
    pub fn defineGetter(self: *Scope, target: c.JSValue, name: [*:0]const u8, function: c.JSValue, flags: c_int) anyerror!void {
        try self.engine.checkNativeEntry();
        const generation = self.engine.native_allocation_generation;
        const key = c.JS_NewAtom(self.engine.context, name);
        if (key == c.JS_ATOM_NULL and !c.JS_HasException(self.engine.context)) _ = c.JS_ThrowInternalError(self.engine.context, "Native Chalk literal atom allocation failed");
        _ = self.rawAllocation(c.pi_js_undefined(), generation) catch |err| { _ = try self.discardAtom(key, err); unreachable; };
        var invocation: em.Engine.NativeInvocation = .{};
        self.beginGuest(&invocation) catch |err| { _ = try self.discardAtom(key, err); unreachable; };
        const result = c.JS_DefinePropertyGetSet(self.engine.context, target, key, c.JS_DupValue(self.engine.context, function), c.pi_js_undefined(), flags);
        if (result < 0 and !c.JS_HasException(self.engine.context)) _ = c.JS_ThrowInternalError(self.engine.context, "Native Chalk define-getter failed without pending reason");
        _ = try self.finishGuestAtom(&invocation, c.pi_js_undefined(), key);
    }
    pub fn set(self: *Scope, target: c.JSValue, name: [*:0]const u8, value: c.JSValue) anyerror!void {
        var invocation: em.Engine.NativeInvocation = .{};
        try self.beginGuest(&invocation);
        try self.finishGuestStatus(&invocation, c.JS_SetPropertyStr(self.engine.context, target, name, c.JS_DupValue(self.engine.context, value)));
    }
    pub fn index(self: *Scope, target: c.JSValue, position: u32, value: c.JSValue) anyerror!void {
        var invocation: em.Engine.NativeInvocation = .{};
        try self.beginGuest(&invocation);
        try self.finishGuestStatus(&invocation, c.JS_DefinePropertyValueUint32(self.engine.context, target, position, c.JS_DupValue(self.engine.context, value), c.JS_PROP_C_W_E));
    }
    fn atom(self: *Scope, key: c.JSValue) anyerror!c.JSAtom {
        var invocation: em.Engine.NativeInvocation = .{};
        try self.beginGuest(&invocation);
        const result = c.JS_ValueToAtom(self.engine.context, key);
        const checked = self.status(if (result == c.JS_ATOM_NULL) -1 else 0, 0);
        var released = false;
        const normalized: anyerror!c.JSValue = if (checked) |_| c.pi_js_undefined() else |err| failed: {
            released = true;
            break :failed self.discardAtom(result, err);
        };
        const completed = self.finishGuestRooted(&invocation, normalized) catch |err| {
            if (!released) { _ = try self.discardAtom(result, err); unreachable; }
            return err;
        };
        self.engine.freeValue(completed);
        return result;
    }
    fn discardAtom(self: *Scope, atom_value: c.JSAtom, err: anyerror) anyerror!c.JSValue {
        var completion = owned.Completion.initValue(self.engine, err);
        completion.release(c.pi_js_undefined()); // Activate stable first-reason escrow before native resource cleanup.
        if (atom_value != c.JS_ATOM_NULL) {
            const generation = self.engine.native_allocation_generation;
            c.JS_FreeAtom(self.engine.context, atom_value);
            _ = self.rawAllocation(c.pi_js_undefined(), generation) catch {};
        }
        return completion.finishValue();
    }
    pub fn getKey(self: *Scope, target: c.JSValue, key: c.JSValue) anyerror!c.JSValue {
        var invocation: em.Engine.NativeInvocation = .{};
        try self.beginGuest(&invocation);
        // The real VM property operation owns its duplicate key. The caller's
        // borrowed key stays rooted; ToPropertyKey executes inside this frame.
        return self.finishGuest(&invocation, c.JS_GetPropertyValue(self.engine.context, target, c.JS_DupValue(self.engine.context, key)), true);
    }
    pub fn setKey(self: *Scope, target: c.JSValue, key: c.JSValue, value: c.JSValue) anyerror!void {
        var invocation: em.Engine.NativeInvocation = .{};
        try self.beginGuest(&invocation);
        try self.finishGuestStatus(&invocation, c.JS_SetPropertyValue(self.engine.context, target, c.JS_DupValue(self.engine.context, key), c.JS_DupValue(self.engine.context, value), c.JS_PROP_THROW));
    }
    pub fn hasKey(self: *Scope, target: c.JSValue, key: c.JSValue) anyerror!bool {
        if (!c.JS_IsObject(target)) {
            const generation = self.engine.native_allocation_generation;
            _ = try self.raw(c.JS_ThrowTypeError(self.engine.context, "Right-hand side of 'in' is not an object"), generation);
            unreachable;
        }
        const name = try self.atom(key);
        var invocation: em.Engine.NativeInvocation = .{};
        self.beginGuest(&invocation) catch |err| { _ = try self.discardAtom(name, err); unreachable; };
        const result = c.JS_HasProperty(self.engine.context, target, name);
        if (result < 0 and !c.JS_HasException(self.engine.context)) _ = c.JS_ThrowInternalError(self.engine.context, "Native Chalk has-property failed without pending reason");
        const completed = try self.finishGuestAtom(&invocation, c.pi_js_bool(self.engine.context, @intFromBool(result != 0)), name);
        return self.truthy(completed);
    }
    pub fn binary(self: *Scope, operation: arithmetic.Operation, left: c.JSValue, right: c.JSValue) anyerror!c.JSValue {
        var invocation: em.Engine.NativeInvocation = .{};
        try self.beginGuest(&invocation);
        return self.finishGuest(&invocation, c.JS_PiBinaryOperator(self.engine.context, @intFromEnum(operation), left, right), true);
    }
    pub fn stringify(self: *Scope, value: c.JSValue) anyerror!c.JSValue {
        var invocation: em.Engine.NativeInvocation = .{};
        try self.beginGuest(&invocation);
        return self.finishGuest(&invocation, c.JS_ToString(self.engine.context, value), true);
    }
    pub fn toNumeric(self: *Scope, value: c.JSValue) anyerror!c.JSValue {
        var invocation: em.Engine.NativeInvocation = .{};
        try self.beginGuest(&invocation);
        return self.finishGuest(&invocation, c.JS_PiToNumeric(self.engine.context, value), true);
    }
    pub fn compare(self: *Scope, operation: arithmetic.Operation, left: c.JSValue, right: c.JSValue) anyerror!bool { return self.truthy(try self.binary(operation, left, right)); }
    pub fn concat(self: *Scope, left: c.JSValue, right: c.JSValue) anyerror!c.JSValue { return self.binary(.add, left, right); }
    pub fn raise(self: *Scope, reason: c.JSValue) anyerror!noreturn {
        const generation = self.engine.native_allocation_generation;
        _ = try self.raw(c.JS_Throw(self.engine.context, c.JS_DupValue(self.engine.context, reason)), generation);
        unreachable;
    }
    pub fn check(self: *Scope, steps: usize) anyerror!void {
        if (!self.engine.cancelled.load(.acquire) and !(steps % 256 == 0 and blk: { self.engine.interrupts +|= 1; break :blk self.engine.interrupts > self.engine.options.interrupt_budget; })) return;
        const generation = self.engine.native_allocation_generation;
        _ = c.JS_ThrowInternalError(self.engine.context, "interrupted");
        const reason = c.JS_GetException(self.engine.context);
        c.JS_SetUncatchableError(self.engine.context, reason);
        _ = try self.raw(c.JS_Throw(self.engine.context, reason), generation);
        unreachable;
    }
    pub fn truthy(self: *Scope, value: c.JSValue) bool { return c.JS_ToBool(self.engine.context, value) == 1; }
    pub fn equal(self: *Scope, left: c.JSValue, right: c.JSValue) bool { return c.JS_IsStrictEqual(self.engine.context, left, right); }
};
