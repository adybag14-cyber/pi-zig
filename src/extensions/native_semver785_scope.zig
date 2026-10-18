//! Private current-event ownership for the SDK's six semver functions.
//! Guest-capable calls use the canonical operation boundary; the local
//! generation check is restricted to direct allocations and native retirement.
const std = @import("std");
const em = @import("engine.zig");
const c = em.c;
const guest = @import("native_sdk_guest_operation.zig");
const Completion = struct { reason: ?c.JSValue = null, fatal: bool = false };
pub fn freshAllocation(engine: *em.Engine, reason: c.JSValue, generation: u64) bool {
    const tag = c.pi_js_native_allocation_error_generation(reason);
    const distance = tag -% generation;
    return tag != 0 and distance != 0 and distance <= engine.native_allocation_generation -% generation;
}
pub const Scope = struct {
    engine: *em.Engine,
    values: std.ArrayList(c.JSValue) = .empty,
    failure: ?anyerror = null,
    steps: usize = 0,
    retired: bool = false,

    pub fn failed(self: *Scope, err: anyerror) void {
        self.failure = err;
        if (err == error.OutOfMemory) _ = self.engine.throwNativeOutOfMemoryFatal();
    }
    fn release(self: *Scope, chosen: *Completion, value: c.JSValue) void {
        const generation = self.engine.native_allocation_generation;
        self.engine.freeValue(value);
        self.take(chosen, generation);
    }
    fn publishFatal(self: *Scope, chosen: *Completion) void {
        // Publish BEFORE any displaced ordinary reason can finalize. Holding
        // the chosen reference prevents the shared normalizer from retiring
        // this event; it can only restore an already-earlier invocation fatal.
        _ = c.JS_Throw(self.engine.context, c.JS_DupValue(self.engine.context, chosen.reason.?));
        _ = self.engine.nativeCallbackResult(c.pi_js_undefined());
        const first = c.JS_GetException(self.engine.context);
        const displaced = chosen.reason.?;
        chosen.* = .{ .reason = first, .fatal = true };
        self.release(chosen, displaced);
    }
    fn merge(self: *Scope, chosen: *Completion, reason: c.JSValue) void {
        const fatal = c.JS_IsUncatchableError(reason);
        if (chosen.reason == null) {
            chosen.* = .{ .reason = reason, .fatal = fatal };
            if (fatal) self.publishFatal(chosen);
        } else if (!chosen.fatal and fatal) {
            const old = chosen.reason.?;
            chosen.* = .{ .reason = reason, .fatal = true };
            self.publishFatal(chosen);
            self.release(chosen, old);
        } else self.release(chosen, reason);
    }
    fn take(self: *Scope, chosen: *Completion, generation: u64) void {
        while (c.JS_HasException(self.engine.context)) {
            const reason = c.JS_GetException(self.engine.context);
            // Only an actual pending event, born after this producer/release,
            // has private allocation authority. Captured DATA is never tested.
            if (freshAllocation(self.engine, reason, generation)) c.JS_SetUncatchableError(self.engine.context, reason);
            self.merge(chosen, reason);
        }
    }
    fn inherit(self: *Scope, chosen: *Completion) void {
        // The pending slot is empty here. A retained invocation fatal can be
        // imported without freeing a sole-owned result or unrelated reason.
        _ = self.engine.nativeCallbackResult(c.pi_js_undefined());
        self.take(chosen, self.engine.native_allocation_generation);
    }
    fn retireCaptured(self: *Scope, chosen: *Completion) void {
        while (self.engine.captured_exception) |data| {
            self.engine.captured_exception = null;
            self.release(chosen, data);
        }
    }
    fn capture(self: *Scope, chosen: *Completion) anyerror {
        self.retireCaptured(chosen);
        self.inherit(chosen);
        self.engine.captured_exception = chosen.reason.?;
        chosen.reason = null;
        return error.JavaScriptException;
    }
    /// Consumes raw result before ANY shared checked()/result cleanup. Caller
    /// must snapshot generation before the raw operation (including its args).
    pub fn complete(self: *Scope, result: c.JSValue, generation: u64) !c.JSValue {
        var chosen: Completion = .{};
        self.take(&chosen, generation);
        self.inherit(&chosen);
        if (chosen.reason == null and c.JS_IsException(result)) {
            _ = c.JS_ThrowInternalError(self.engine.context, "Native semver operation returned exception without a pending reason");
            self.take(&chosen, generation);
        }
        if (chosen.reason != null) {
            self.release(&chosen, result);
            return self.capture(&chosen);
        }
        return result;
    }
    pub fn status(self: *Scope, result: c_int, generation: u64) !void {
        if (result < 0 and !c.JS_HasException(self.engine.context)) _ = c.JS_ThrowInternalError(self.engine.context, "Native semver operation failed without a pending reason");
        _ = try self.complete(c.pi_js_undefined(), generation);
    }
    pub fn retire(self: *Scope, value: c.JSValue) !void {
        var chosen: Completion = .{};
        self.release(&chosen, value);
        self.inherit(&chosen);
        if (chosen.reason != null) return self.capture(&chosen);
    }
    pub fn deinit(self: *Scope) void {
        if (self.retired) return;
        self.retired = true;
        var chosen: Completion = .{};
        var saved = self.engine.captured_exception;
        self.engine.captured_exception = null;
        if (self.failure) |failure| if (failure == error.JavaScriptException) if (saved) |reason| {
            chosen = .{ .reason = reason, .fatal = c.JS_IsUncatchableError(reason) };
            saved = null;
        };
        self.take(&chosen, self.engine.native_allocation_generation);
        self.inherit(&chosen);
        for (self.values.items) |value| self.release(&chosen, value);
        self.values.deinit(self.engine.gpa);
        if (chosen.reason != null) {
            if (saved) |data| self.release(&chosen, data);
            self.retireCaptured(&chosen);
            self.inherit(&chosen);
            _ = c.JS_Throw(self.engine.context, chosen.reason.?);
        } else self.engine.captured_exception = saved;
    }
    pub fn finish(self: *Scope, result: c.JSValue) !c.JSValue {
        self.deinit();
        // Every inner producer/release has already been qualified. An older
        // tag born in this callback is DATA for a later ordinary event.
        return self.complete(result, self.engine.native_allocation_generation);
    }
    pub fn poll(self: *Scope) !void {
        _ = try self.complete(c.pi_js_undefined(), self.engine.native_allocation_generation);
        self.steps +|= 1;
        if (self.engine.cancelled.load(.acquire) or (self.steps % 256 == 0 and blk: {
            self.engine.interrupts +|= 1;
            break :blk self.engine.interrupts > self.engine.options.interrupt_budget;
        })) {
            const generation = self.engine.native_allocation_generation;
            _ = c.JS_ThrowInternalError(self.engine.context, "interrupted");
            const reason = c.JS_GetException(self.engine.context);
            c.JS_SetUncatchableError(self.engine.context, reason);
            _ = try self.complete(c.JS_Throw(self.engine.context, reason), generation);
            unreachable;
        }
    }
    pub fn own(self: *Scope, value: c.JSValue) !c.JSValue {
        const checked = try self.complete(value, self.engine.native_allocation_generation);
        self.values.append(self.engine.gpa, checked) catch |err| {
            self.failed(err);
            var chosen: Completion = .{};
            self.take(&chosen, self.engine.native_allocation_generation);
            self.inherit(&chosen);
            self.release(&chosen, checked);
            _ = self.capture(&chosen);
            return err;
        };
        return checked;
    }
    pub fn get(self: *Scope, object_value: c.JSValue, name: [*:0]const u8) !c.JSValue { try self.poll(); return guest.get(self, object_value, name); }
    pub fn global(self: *Scope, name: [*:0]const u8) !c.JSValue { const generation = self.engine.native_allocation_generation; const root = try self.own(try self.complete(c.JS_GetGlobalObject(self.engine.context), generation)); return self.get(root, name); }
    pub fn text(self: *Scope, bytes: []const u8) !c.JSValue { try self.poll(); const generation = self.engine.native_allocation_generation; return self.own(try self.complete(c.JS_NewStringLen(self.engine.context, bytes.ptr, bytes.len), generation)); }
    pub fn object(self: *Scope) !c.JSValue { try self.poll(); const generation = self.engine.native_allocation_generation; return self.own(try self.complete(c.JS_NewObject(self.engine.context), generation)); }
    pub fn plain(self: *Scope) !c.JSValue { try self.poll(); const generation = self.engine.native_allocation_generation; return self.own(try self.complete(c.JS_NewObjectProto(self.engine.context, c.pi_js_null()), generation)); }
    pub fn array(self: *Scope) !c.JSValue { try self.poll(); const generation = self.engine.native_allocation_generation; return self.own(try self.complete(c.JS_NewArray(self.engine.context), generation)); }
    pub fn call(self: *Scope, function: c.JSValue, receiver: c.JSValue, args: []const c.JSValue) !c.JSValue { try self.poll(); return guest.call(self, function, receiver, args); }
    pub fn construct(self: *Scope, function: c.JSValue, args: []const c.JSValue) !c.JSValue { try self.poll(); return guest.construct(self, function, args); }
    pub fn builtin(self: *Scope, name: [*:0]const u8, args: []const c.JSValue) !c.JSValue { return self.construct(try self.global(name), args); }
    pub fn invoke(self: *Scope, receiver: c.JSValue, name: [*:0]const u8, args: []const c.JSValue) !c.JSValue { return self.call(try self.get(receiver, name), receiver, args); }
    pub fn snapshot(self: *Scope, iterable: c.JSValue) !c.JSValue {
        try self.poll();
        const generation = self.engine.native_allocation_generation;
        const symbol = try self.own(try self.complete(c.JS_GetIteratorSymbol(self.engine.context), generation));
        const atom_generation = self.engine.native_allocation_generation;
        const atom = c.JS_ValueToAtom(self.engine.context, symbol);
        if (atom == c.JS_ATOM_NULL) { try self.status(-1, atom_generation); unreachable; }
        defer c.JS_FreeAtom(self.engine.context, atom);
        const method = try guest.getAtom(self, iterable, atom);
        const iterator = try self.call(method, iterable, &.{});
        if (!c.JS_IsObject(iterator)) return self.iteratorTypeError("iterator must return an object");
        const next = try self.get(iterator, "next");
        const result = try self.array();
        var position: u32 = 0;
        while (true) {
            const step = try self.call(next, iterator, &.{});
            if (!c.JS_IsObject(step)) return self.iteratorTypeError("iterator result must be an object");
            if (self.truthy(try self.get(step, "done"))) return result;
            try self.index(result, position, try self.get(step, "value"));
            if (position == std.math.maxInt(u32)) return error.NativeIteratorArrayTooLarge;
            position += 1;
        }
    }
    fn iteratorTypeError(self: *Scope, message: [*:0]const u8) !noreturn {
        const generation = self.engine.native_allocation_generation;
        _ = try self.complete(c.JS_ThrowTypeError(self.engine.context, "%s", message), generation);
        unreachable;
    }
    pub fn put(self: *Scope, target: c.JSValue, name: [*:0]const u8, value: c.JSValue) !void { try self.poll(); return guest.put(self, target, name, value); }
    pub fn index(self: *Scope, target: c.JSValue, position: u32, value: c.JSValue) !void { try self.poll(); return guest.index(self, target, position, value); }
    pub fn at(self: *Scope, value: c.JSValue, position: u32) !c.JSValue { try self.poll(); return guest.at(self, value, position); }
    pub fn number(self: *Scope, value: c.JSValue) !c.JSValue { try self.poll(); var boundary: guest.Boundary = .{ .engine = self.engine }; try boundary.begin(); return boundary.finishValue(self, c.JS_ToNumber(self.engine.context, value)); }
    pub fn length(self: *Scope, value: c.JSValue) !u32 { const size = try self.get(value, "length"); var result: u32 = 0; var boundary: guest.Boundary = .{ .engine = self.engine }; try boundary.begin(); try boundary.finishStatus(c.JS_ToUint32(self.engine.context, &result, size)); return result; }
    pub fn binary(self: *Scope, operation: @import("native_image_arithmetic.zig").Operation, left: c.JSValue, right: c.JSValue) !c.JSValue { try self.poll(); return guest.binary(self, @intFromEnum(operation), left, right); }
    pub fn compare(self: *Scope, operation: @import("native_image_arithmetic.zig").Operation, left: c.JSValue, right: c.JSValue) !bool { return self.truthy(try self.binary(operation, left, right)); }
    pub fn concat(self: *Scope, left: c.JSValue, right: c.JSValue) !c.JSValue { return self.binary(.add, left, right); }
    pub fn stringify(self: *Scope, value: c.JSValue) !c.JSValue { try self.poll(); return guest.stringify(self, value); }
    pub fn raise(self: *Scope, reason: c.JSValue) !noreturn { const generation = self.engine.native_allocation_generation; _ = try self.complete(c.JS_Throw(self.engine.context, c.JS_DupValue(self.engine.context, reason)), generation); unreachable; }
    pub fn truthy(self: *Scope, value: c.JSValue) bool { return c.JS_ToBool(self.engine.context, value) == 1; }
    pub fn equal(self: *Scope, left: c.JSValue, right: c.JSValue) bool { return c.JS_IsStrictEqual(self.engine.context, left, right); }
};