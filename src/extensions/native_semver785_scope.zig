//! Private owned completion for the SDK's six semver functions.
//! Guest operations retain actual pending classification. Captured diagnostics
//! are DATA, and only one root retirement supplies a local generation span.
const std = @import("std");
const em = @import("engine.zig");
const c = em.c;
const guest = @import("native_sdk_guest_operation.zig");
const Reason = struct {
    value: c.JSValue,
    fatal: bool,
    actual_pending: bool = true,
    fn isFatal(self: Reason, engine: *em.Engine) bool {
        return self.actual_pending and (if (c.JS_PiIsExecutionTermination(self.value))
            c.JS_PiNativePendingPriority(engine.runtime, self.value) > 0 else self.fatal);
    }
    fn uncatchable(self: Reason) bool {
        return self.actual_pending and (self.fatal or c.JS_PiIsExecutionTermination(self.value));
    }
};
fn rememberProducer(engine: *em.Engine, reason: Reason) void {
    if (!reason.actual_pending) return;
    const private = c.JS_PiIsExecutionTermination(reason.value);
    if (private and engine.nativeTerminationObserved()) return;
    if (!private and !reason.isFatal(engine)) return;
    const invocation = engine.native_fatal_invocation orelse return;
    @import("std").debug.assert(invocation.active);
    if (!private) if (invocation.first) |first| {
        if (!c.JS_PiIsExecutionTermination(first) or
            c.JS_PiNativePendingPriority(engine.runtime, first) > 0) return;
    };
    // Retain a proven actual producer before another root can run cleanup.
    // Even a canceled private token records history in every active owner.
    _ = c.JS_PiThrowNativePending(engine.context,
        c.JS_DupValue(engine.context, reason.value), reason.fatal);
    engine.releaseNativeValue(c.pi_js_undefined());
    var duplicate_fatal: bool = false;
    const duplicate = c.JS_PiGetExceptionWithFatal(engine.context, &duplicate_fatal);
    // Retire only the paired duplicate we published. Keep a different
    // normalization winner pending for the caller's existing drain.
    if (duplicate_fatal == reason.fatal and c.JS_IsStrictEqual(engine.context, duplicate, reason.value))
        engine.freeValue(duplicate)
    else
        _ = c.JS_PiThrowNativePending(engine.context, duplicate, duplicate_fatal);
}
const Completion = struct { reason: ?Reason = null };
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
    terminal_abort: bool = false,

    pub fn failed(self: *Scope, err: anyerror) void {
        self.failure = err;
        if (err == error.ExecutionTerminated) self.terminal_abort = true;
        if (err == error.OutOfMemory) _ = self.engine.throwNativeOutOfMemoryFatal();
    }
    fn select(self: *Scope, chosen: *Completion, next: Reason) ?c.JSValue {
        rememberProducer(self.engine, next);
        if (next.actual_pending and c.JS_PiIsExecutionTermination(next.value))
            self.terminal_abort = true;
        const prior = chosen.reason orelse {
            chosen.reason = next;
            return null;
        };
        const replace = if (prior.actual_pending and next.actual_pending)
            c.JS_PiNativePendingReplaceClassified(self.engine.runtime,
                prior.value, prior.fatal, next.value, next.fatal)
        else if (!prior.actual_pending) next.isFatal(self.engine)
        else c.JS_PiIsExecutionTermination(prior.value) and
            c.JS_PiNativePendingPriority(self.engine.runtime, prior.value) < 0;
        if (!replace) return next.value;
        chosen.reason = next;
        return prior.value;
    }
    fn merge(self: *Scope, chosen: *Completion, reason: Reason) void {
        if (self.select(chosen, reason)) |displaced| self.release(chosen, displaced);
    }
    fn take(self: *Scope, chosen: *Completion, release_generation: ?u64) void {
        var generation = release_generation;
        while (c.JS_HasException(self.engine.context)) {
            var fatal: bool = false;
            const value = c.JS_PiGetExceptionWithFatal(self.engine.context, &fatal);
            if (!c.JS_PiIsExecutionTermination(value)) if (generation) |before_release| {
                if (freshAllocation(self.engine, value, before_release)) {
                    fatal = true;
                    c.JS_SetUncatchableError(self.engine.context, value);
                }
            };
            // Classify the actual event before releasing a displaced root.
            self.merge(chosen, .{ .value = value, .fatal = fatal });
            generation = null;
        }
    }
    fn inherit(self: *Scope, chosen: *Completion) void {
        // The stable outer create/callback owner retains an actual event even
        // if checked() already captured it. Do not repeatedly reintroduce an
        // already owned primitive fatal while discarding its duplicate.
        if (chosen.reason == null or !chosen.reason.?.isFatal(self.engine))
            _ = self.engine.nativeCallbackResult(c.pi_js_undefined());
        self.terminal_abort = self.terminal_abort or self.engine.nativeTerminationObserved();
        self.take(chosen, null);
    }
    fn release(self: *Scope, chosen: *Completion, value: c.JSValue) void {
        self.inherit(chosen);
        const generation = self.engine.native_allocation_generation;
        self.engine.freeValue(value);
        self.take(chosen, generation);
        self.inherit(chosen);
    }
    fn retireCaptured(self: *Scope, chosen: *Completion) void {
        while (self.engine.captured_exception) |data| {
            self.engine.captured_exception = null;
            self.release(chosen, data);
        }
    }
    fn publish(self: *Scope, chosen: *Completion) void {
        const reason = chosen.reason orelse return;
        chosen.reason = null;
        if (reason.actual_pending) {
            _ = c.JS_PiThrowNativePending(self.engine.context, reason.value, reason.fatal);
        } else {
            _ = c.JS_PiThrowExceptionData(self.engine.context, reason.value);
        }
    }
    fn capture(self: *Scope, chosen: *Completion) anyerror {
        self.retireCaptured(chosen);
        self.inherit(chosen);
        if (self.terminal_abort) {
            self.publish(chosen);
            return error.ExecutionTerminated;
        }
        const reason = chosen.reason orelse return error.JavaScriptException;
        if (reason.uncatchable()) {
            self.publish(chosen);
            return error.JavaScriptException;
        }
        // The original valid/validRange/satisfies catches consume this ordinary
        // event as DATA. Neither its mutable Error flag nor its tag is authority.
        chosen.reason = null;
        self.engine.captured_exception = reason.value;
        return error.JavaScriptException;
    }
    /// Existing callers include guest-capable operations, so the historical
    /// generation argument is not an allocation producer. Actual slot policy
    /// and the independently retained outer invocation determine completion.
    pub fn complete(self: *Scope, result: c.JSValue, _: u64) !c.JSValue {
        var chosen: Completion = .{};
        self.inherit(&chosen);
        if (chosen.reason == null and c.JS_IsException(result) and !self.terminal_abort) {
            _ = c.JS_ThrowInternalError(self.engine.context, "Native semver operation returned exception without a pending reason");
            self.inherit(&chosen);
        }
        if (chosen.reason != null or self.terminal_abort) {
            self.release(&chosen, result);
            return self.capture(&chosen);
        }
        return result;
    }
    pub fn status(self: *Scope, result: c_int, generation: u64) !void {
        self.terminal_abort = self.terminal_abort or self.engine.nativeTerminationObserved();
        if (result < 0 and !c.JS_HasException(self.engine.context) and !self.terminal_abort)
            _ = c.JS_ThrowInternalError(self.engine.context, "Native semver operation failed without a pending reason");
        _ = try self.complete(c.pi_js_undefined(), generation);
    }
    pub fn retire(self: *Scope, value: c.JSValue) !void {
        var chosen: Completion = .{};
        self.release(&chosen, value);
        if (chosen.reason != null or self.terminal_abort) return self.capture(&chosen);
    }
    pub fn deinit(self: *Scope) void {
        if (self.retired) return;
        self.retired = true;
        var chosen: Completion = .{};
        var saved = self.engine.captured_exception;
        self.engine.captured_exception = null;
        self.inherit(&chosen);
        if (self.failure) |failure| {
            if (failure == error.ExecutionTerminated) self.terminal_abort = true;
            if (failure == error.JavaScriptException and chosen.reason == null) {
                if (saved) |reason| {
                    chosen.reason = .{ .value = reason, .fatal = false, .actual_pending = false };
                    saved = null;
                }
            }
        }
        for (self.values.items) |value| self.release(&chosen, value);
        self.values.deinit(self.engine.gpa);
        self.values = .empty;
        if (chosen.reason != null or self.terminal_abort) {
            if (saved) |data| self.release(&chosen, data);
            self.retireCaptured(&chosen);
            self.inherit(&chosen);
            self.publish(&chosen);
        } else self.engine.captured_exception = saved;
    }
    /// Actual consumers use this after their body locals retire. A private
    /// abort first observed during deinit must still return its host tag even
    /// if cancellation lets a later ordinary cleanup event win selection.
    pub fn finishOutcome(self: *Scope, outcome: anyerror!c.JSValue) !c.JSValue {
        const result = outcome catch |err| {
            self.failed(err);
            self.deinit();
            if (self.terminal_abort) return error.ExecutionTerminated;
            return err;
        };
        self.deinit();
        return self.complete(result, self.engine.native_allocation_generation);
    }
    pub fn finish(self: *Scope, result: c.JSValue) !c.JSValue {
        return self.finishOutcome(result);
    }
    pub fn poll(self: *Scope) !void {
        _ = try self.complete(c.pi_js_undefined(), self.engine.native_allocation_generation);
        self.steps +|= 1;
        if (self.engine.cancelled.load(.acquire) or (self.steps % 256 == 0 and blk: {
            self.engine.interrupts +|= 1;
            break :blk self.engine.interrupts > self.engine.options.interrupt_budget;
        })) {
            _ = c.JS_ThrowInternalError(self.engine.context, "interrupted");
            var generic_fatal: bool = false;
            const reason = c.JS_PiGetExceptionWithFatal(self.engine.context, &generic_fatal);
            // The actual native budget/cancel producer supplies fatal authority,
            // including allocation failure whose reason is primitive null.
            c.JS_SetUncatchableError(self.engine.context, reason);
            _ = try self.complete(c.JS_PiThrowNativePending(self.engine.context, reason, true), self.engine.native_allocation_generation);
            unreachable;
        }
    }
    pub fn own(self: *Scope, value: c.JSValue) !c.JSValue {
        const checked = try self.complete(value, self.engine.native_allocation_generation);
        self.values.append(self.engine.gpa, checked) catch |err| {
            self.failed(err);
            var chosen: Completion = .{};
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
    pub fn raise(self: *Scope, reason: c.JSValue) !noreturn { const generation = self.engine.native_allocation_generation; _ = try self.complete(c.JS_PiThrowExceptionData(self.engine.context, c.JS_DupValue(self.engine.context, reason)), generation); unreachable; }
    pub fn truthy(self: *Scope, value: c.JSValue) bool { return c.JS_ToBool(self.engine.context, value) == 1; }
    pub fn equal(self: *Scope, left: c.JSValue, right: c.JSValue) bool { return c.JS_IsStrictEqual(self.engine.context, left, right); }
};