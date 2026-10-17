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
    /// Only ACTUAL pending from this exact raw producer may gain private OOM
    /// authority. Diagnostic/captured values and earlier tags remain DATA.
    pub fn raw(self: *Scope, value: c.JSValue, generation: u64) anyerror!c.JSValue {
        if (c.JS_HasException(self.engine.context)) {
            const reason = c.JS_GetException(self.engine.context);
            const tag = c.pi_js_native_allocation_error_generation(reason);
            const distance = tag -% generation;
            if (tag != 0 and distance != 0 and distance <= self.engine.native_allocation_generation -% generation) c.JS_SetUncatchableError(self.engine.context, reason);
            _ = c.JS_Throw(self.engine.context, reason);
        } else if (c.JS_IsException(value)) {
            _ = c.JS_ThrowInternalError(self.engine.context, "Native Chalk producer returned exception without pending reason");
        }
        var completion = owned.Completion.initValue(self.engine, value);
        return completion.finishValue();
    }
    pub fn status(self: *Scope, result: c_int, generation: u64) anyerror!void {
        if (result < 0 and !c.JS_HasException(self.engine.context)) _ = c.JS_ThrowInternalError(self.engine.context, "Native Chalk producer failed without pending reason");
        _ = try self.raw(c.pi_js_undefined(), generation);
    }
    pub fn own(self: *Scope, value: c.JSValue) anyerror!c.JSValue {
        const checked = try self.raw(value, self.engine.native_allocation_generation);
        if (self.inline_count < self.inline_values.len) {
            self.inline_values[self.inline_count] = checked;
            self.inline_count += 1;
        } else self.values.append(self.engine.gpa, checked) catch |err| {
            var completion = owned.Completion.initValue(self.engine, err);
            completion.release(checked);
            return completion.finishValue();
        };
        return checked;
    }
    pub fn get(self: *Scope, object_value: c.JSValue, name: [*:0]const u8) anyerror!c.JSValue {
        const generation = self.engine.native_allocation_generation;
        return self.own(try self.raw(c.JS_GetPropertyStr(self.engine.context, object_value, name), generation));
    }
    pub fn global(self: *Scope, name: [*:0]const u8) anyerror!c.JSValue {
        const generation = self.engine.native_allocation_generation;
        return self.get(try self.own(try self.raw(c.JS_GetGlobalObject(self.engine.context), generation)), name);
    }
    pub fn text(self: *Scope, bytes: []const u8) anyerror!c.JSValue { const generation = self.engine.native_allocation_generation; return self.own(try self.raw(c.JS_NewStringLen(self.engine.context, bytes.ptr, bytes.len), generation)); }
    pub fn object(self: *Scope) anyerror!c.JSValue { const generation = self.engine.native_allocation_generation; return self.own(try self.raw(c.JS_NewObject(self.engine.context), generation)); }
    pub fn array(self: *Scope) anyerror!c.JSValue { const generation = self.engine.native_allocation_generation; return self.own(try self.raw(c.JS_NewArray(self.engine.context), generation)); }
    pub fn call(self: *Scope, function: c.JSValue, receiver: c.JSValue, args: []const c.JSValue) anyerror!c.JSValue {
        const generation = self.engine.native_allocation_generation;
        return self.own(try self.raw(c.JS_Call(self.engine.context, function, receiver, @intCast(args.len), @constCast(args.ptr)), generation));
    }
    pub fn construct(self: *Scope, function: c.JSValue, args: []const c.JSValue) anyerror!c.JSValue {
        const generation = self.engine.native_allocation_generation;
        return self.own(try self.raw(c.JS_CallConstructor(self.engine.context, function, @intCast(args.len), @constCast(args.ptr)), generation));
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
    pub fn index(self: *Scope, target: c.JSValue, position: u32, value: c.JSValue) anyerror!void {
        const generation = self.engine.native_allocation_generation;
        try self.status(c.JS_DefinePropertyValueUint32(self.engine.context, target, position, c.JS_DupValue(self.engine.context, value), c.JS_PROP_C_W_E), generation);
    }
    fn atom(self: *Scope, key: c.JSValue) anyerror!c.JSAtom {
        const generation = self.engine.native_allocation_generation;
        const result = c.JS_ValueToAtom(self.engine.context, key);
        self.status(if (result == c.JS_ATOM_NULL) -1 else 0, generation) catch |err| {
            if (result != c.JS_ATOM_NULL) c.JS_FreeAtom(self.engine.context, result);
            return err;
        };
        return result;
    }
    pub fn getKey(self: *Scope, target: c.JSValue, key: c.JSValue) anyerror!c.JSValue {
        const name = try self.atom(key); defer c.JS_FreeAtom(self.engine.context, name);
        const generation = self.engine.native_allocation_generation;
        return self.own(try self.raw(c.JS_GetProperty(self.engine.context, target, name), generation));
    }
    pub fn setKey(self: *Scope, target: c.JSValue, key: c.JSValue, value: c.JSValue) anyerror!void {
        const name = try self.atom(key); defer c.JS_FreeAtom(self.engine.context, name);
        const generation = self.engine.native_allocation_generation;
        try self.status(c.JS_SetProperty(self.engine.context, target, name, c.JS_DupValue(self.engine.context, value)), generation);
    }
    pub fn hasKey(self: *Scope, target: c.JSValue, key: c.JSValue) anyerror!bool {
        if (!c.JS_IsObject(target)) {
            const generation = self.engine.native_allocation_generation;
            _ = try self.raw(c.JS_ThrowTypeError(self.engine.context, "Right-hand side of 'in' is not an object"), generation);
            unreachable;
        }
        const name = try self.atom(key); defer c.JS_FreeAtom(self.engine.context, name);
        const generation = self.engine.native_allocation_generation;
        const result = c.JS_HasProperty(self.engine.context, target, name);
        try self.status(result, generation);
        return result != 0;
    }
    pub fn binary(self: *Scope, operation: arithmetic.Operation, left: c.JSValue, right: c.JSValue) anyerror!c.JSValue {
        const generation = self.engine.native_allocation_generation;
        return self.own(try self.raw(c.JS_PiBinaryOperator(self.engine.context, @intFromEnum(operation), left, right), generation));
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
