//! mkdir-local owned completion escrow. Actual pending policy and the stable
//! native invocation survive root retirement; captured diagnostics remain DATA.
const js = @import("native_js_values.zig");
const c = js.c;
const af = @import("native_async_function.zig");
pub const Reason = struct {
    value: c.JSValue,
    fatal: bool,
    actual_pending: bool = true,
    fn isFatal(self: Reason, engine: *js.Engine) bool {
        return self.actual_pending and (if (c.JS_PiIsExecutionTermination(self.value))
            c.JS_PiNativePendingPriority(engine.runtime, self.value) > 0 else self.fatal);
    }
    fn uncatchable(self: Reason) bool {
        return self.actual_pending and (self.fatal or c.JS_PiIsExecutionTermination(self.value));
    }
};
threadlocal var current: ?*Frame = null;
pub fn active(engine: *js.Engine) ?*Frame {
    var frame = current;
    while (frame) |item| : (frame = item.previous) if (item.engine == engine) return item;
    return null;
}
// Existing callers mark guest-capable operations as well as allocations. That
// broad span cannot classify a detached value; actual pending policy does so.
pub fn before(_: *js.Engine) void {}
fn takePending(engine: *js.Engine, release_generation: ?u64) ?Reason {
    if (!c.JS_HasException(engine.context)) return null;
    var fatal: bool = false;
    const value = c.JS_PiGetExceptionWithFatal(engine.context, &fatal);
    if (!c.JS_PiIsExecutionTermination(value)) if (release_generation) |generation| {
        // Only an individual root free supplies this snapshot.
        const tag = c.pi_js_native_allocation_error_generation(value);
        const distance = tag -% generation;
        if (tag != 0 and distance != 0 and distance <= engine.native_allocation_generation -% generation) {
            fatal = true;
            c.JS_SetUncatchableError(engine.context, value);
        }
    };
    return .{ .value = value, .fatal = fatal };
}
fn rememberProducer(engine: *js.Engine, reason: Reason) void {
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
pub const Frame = struct {
    engine: *js.Engine,
    previous: ?*Frame = null,
    chosen: ?Reason = null,
    invocation: js.Engine.NativeInvocation = .{},
    terminated: bool = false,
    pub fn enter(self: *Frame) void {
        self.previous = current;
        current = self; self.engine.native_exception_diagnostics_suppressed += 1;
        self.engine.enterNativeInvocation(&self.invocation);
        self.terminated = self.engine.nativeTerminationObserved();
        // Old history is never classified. An independently retained producer
        // can surface even when a native callback captured it and returned.
        const history = self.engine.captured_exception; self.engine.captured_exception = null;
        self.drain(null);
        if (history) |old| self.release(old);
    }
    pub fn leave(self: *Frame) void {
        if (self.chosen != null or self.invocation.active)
            @panic("mkdir completion escrow was not consumed");
        current = self.previous; self.engine.native_exception_diagnostics_suppressed -= 1;
    }
    fn failure(self: *Frame) anyerror {
        if (self.terminated) return error.ExecutionTerminated;
        if (self.chosen) |reason| return if (reason.actual_pending and c.JS_PiIsExecutionTermination(reason.value))
            error.ExecutionTerminated else error.JavaScriptException;
        return error.JavaScriptException;
    }
    fn select(self: *Frame, next: Reason) ?c.JSValue {
        rememberProducer(self.engine, next);
        self.terminated = self.terminated or self.engine.nativeTerminationObserved();
        // Lifecycle history survives private cancellation and replacement by
        // ordinary cleanup; it never changes that selected reason's policy.
        if (next.actual_pending and c.JS_PiIsExecutionTermination(next.value))
            self.terminated = true;
        if (self.chosen) |prior| {
            const replace = if (prior.actual_pending and next.actual_pending)
                c.JS_PiNativePendingReplaceClassified(self.engine.runtime,
                    prior.value, prior.fatal, next.value, next.fatal)
            else if (!prior.actual_pending) next.isFatal(self.engine)
            else c.JS_PiIsExecutionTermination(prior.value) and
                c.JS_PiNativePendingPriority(self.engine.runtime, prior.value) < 0;
            if (replace) { self.chosen = next; return prior.value; }
            return next.value;
        }
        self.chosen = next; return null;
    }
    fn merge(self: *Frame, next: Reason) void {
        if (self.select(next)) |displaced| {
            const generation = self.engine.native_allocation_generation;
            self.engine.freeValue(displaced); self.drain(generation);
        }
    }
    fn drain(self: *Frame, release_generation: ?u64) void {
        var generation = release_generation;
        while (true) {
            // Once the first fatal is owned, resurfacing the same invocation
            // on each discard would recurse forever for a primitive reason.
            if (self.chosen == null or !self.chosen.?.isFatal(self.engine)) {
                if (self.invocation.active)
                    _ = self.engine.nativeCallbackResult(c.pi_js_undefined())
                else
                    self.engine.releaseNativeValue(c.pi_js_undefined());
            }
            self.terminated = self.terminated or self.engine.nativeTerminationObserved();
            const pending_event = takePending(self.engine, generation);
            const captured = self.engine.captured_exception; self.engine.captured_exception = null;
            if (pending_event == null and captured == null) break;
            const discard_pending = if (pending_event) |reason| self.select(reason) else null;
            // Both channels are snapshotted before a destructor; diagnostic
            // flags/tags cannot establish a current event, even after cleanup.
            if (discard_pending) |old| {
                const next = self.engine.native_allocation_generation;
                self.engine.freeValue(old); self.drain(next);
            }
            if (captured) |old| {
                const next = self.engine.native_allocation_generation;
                self.engine.freeValue(old); self.drain(next);
            }
            generation = null;
        }
    }
    pub fn check(self: *Frame) !void {
        self.drain(null);
        if (self.chosen != null or self.terminated) return self.failure();
    }
    pub fn record(self: *Frame, err: anyerror) void {
        if (self.chosen == null or !self.chosen.?.isFatal(self.engine)) {
            if (self.invocation.active)
                _ = self.engine.nativeCallbackResult(c.pi_js_undefined())
            else
                self.engine.releaseNativeValue(c.pi_js_undefined());
        }
        self.terminated = self.terminated or self.engine.nativeTerminationObserved();
        const pending_event = takePending(self.engine, null);
        const captured = self.engine.captured_exception; self.engine.captured_exception = null;
        var discard_captured = captured;
        var discard_pending: ?c.JSValue = null;
        if (pending_event) |reason| discard_pending = self.select(reason)
        else if (err == error.JavaScriptException) {
            if (captured) |reason| discard_captured =
                self.select(.{ .value = reason, .fatal = false, .actual_pending = false });
        }
        if (err == error.ExecutionTerminated) self.terminated = true;
        if (err == error.OutOfMemory and (self.chosen == null or !self.chosen.?.isFatal(self.engine))) {
            _ = self.engine.throwNativeOutOfMemoryFatal();
            if (takePending(self.engine, null)) |reason| self.merge(reason);
        }
        if (self.chosen == null and !self.terminated) {
            _ = c.JS_ThrowInternalError(self.engine.context, "Native mkdir boundary: %s", @as([*:0]const u8, @errorName(err)));
            if (takePending(self.engine, null)) |reason| self.merge(reason);
        }
        if (discard_pending) |old| self.release(old);
        if (discard_captured) |old| self.release(old);
        self.drain(null);
    }
    pub fn adoptFailureValue(self: *Frame, owned: c.JSValue) void {
        if (c.JS_IsException(owned)) { self.record(error.JavaScriptException); return; }
        self.drain(null);
        if (self.chosen != null or self.terminated) self.release(owned)
        else self.merge(.{ .value = owned, .fatal = false, .actual_pending = false });
        self.drain(null);
    }
    pub fn release(self: *Frame, owned: c.JSValue) void {
        self.drain(null);
        const generation = self.engine.native_allocation_generation;
        self.engine.freeValue(owned); self.drain(generation);
    }
    fn closeInvocation(self: *Frame) void {
        if (!self.invocation.active) return;
        self.drain(null);
        const result = self.engine.leaveNativeInvocation(&self.invocation, c.pi_js_undefined());
        self.terminated = self.terminated or self.invocation.terminated;
        self.engine.freeValue(result); // Only an immediate result/sentinel.
        self.drain(null);
    }
    fn publish(self: *Frame) anyerror {
        const err = self.failure();
        if (self.chosen) |reason| {
            self.chosen = null;
            if (reason.actual_pending) {
                _ = c.JS_PiThrowNativePending(self.engine.context, reason.value, reason.fatal);
            } else {
                _ = c.JS_PiThrowExceptionData(self.engine.context, reason.value);
            }
        }
        return err;
    }
    pub fn finishVoid(self: *Frame) !void {
        self.check() catch {};
        self.closeInvocation();
        if (self.chosen != null or self.terminated) return self.publish();
    }
    pub fn takeOrdinary(self: *Frame) ?c.JSValue {
        self.check() catch {};
        if (self.terminated) return null;
        const reason = self.chosen orelse return null;
        if (reason.uncatchable()) return null;
        self.chosen = null; return reason.value;
    }
    pub fn finishValue(self: *Frame, owned: c.JSValue) !c.JSValue {
        self.check() catch {};
        var released = false;
        if (self.chosen != null or self.terminated) { self.release(owned); released = true; }
        self.closeInvocation();
        if (self.chosen != null or self.terminated) {
            if (!released) self.release(owned);
            return self.publish();
        }
        return owned;
    }
    fn retireAction(self: *Frame, action: af.Action) bool {
        if (self.chosen == null and !self.terminated) return false;
        // Source THROW is DATA: preserve it over ordinary cleanup, while an
        // actual native fatal or private unwind bypasses the source catch.
        switch (action) {
            .thrown => |reason| {
                while (self.chosen) |ordinary| {
                    if (self.terminated or ordinary.uncatchable()) break;
                    self.chosen = null; self.release(ordinary.value);
                }
                if (self.chosen == null and !self.terminated) return false;
                self.release(reason);
            },
            .returned, .awaited => |reason| self.release(reason),
        }
        return true;
    }
    pub fn finishAction(self: *Frame, action: af.Action) !af.Action {
        self.check() catch {};
        const retired = self.retireAction(action);
        self.closeInvocation();
        if (!retired and (self.chosen != null or self.terminated)) _ = self.retireAction(action);
        const selected = self.chosen orelse {
            if (self.terminated) return self.publish();
            return action;
        };
        if (self.terminated) {
            _ = self.publish();
            return error.ExecutionTerminated;
        }
        if (selected.uncatchable()) return self.publish();
        self.chosen = null; return .{ .thrown = selected.value };
    }
};
pub fn pending(engine: *js.Engine) !void { if (active(engine)) |frame| return frame.check(); if (c.JS_HasException(engine.context)) return js.capture(engine); }
pub fn capture(engine: *js.Engine) anyerror { if (active(engine)) |frame| { frame.record(error.JavaScriptException); return frame.failure(); } return js.capture(engine); }
pub fn release(engine: *js.Engine, owned: c.JSValue) void { if (active(engine)) |frame| frame.release(owned) else engine.freeValue(owned); }

/// Native-only contrasting cleanup controls. A real opaque finalizer transfers
/// its owned reason into the VM slot; no fake exception/Engine or JS finalizer.
pub const Testing = if (@import("builtin").is_test) struct {
    pub const PrivateHistoryProbe = struct {
        engine: *js.Engine,
        calls: usize = 0,
        emitted: bool = false,
        canceled: bool = false,
        observed: bool = false,
    };
    const HistoryPayload = struct { probe: *PrivateHistoryProbe, emit_private: bool };
    fn historyFinalized(_: ?*c.JSRuntime, object: c.JSValue) callconv(.c) void {
        const payload: *HistoryPayload = @ptrCast(@alignCast(c.JS_GetOpaque(object, c.JS_GetClassID(object)) orelse return));
        const probe = payload.probe; const emit_private = payload.emit_private;
        const engine = probe.engine; engine.gpa.destroy(payload); probe.calls += 1;
        if (!emit_private) {
            probe.observed = engine.nativeTerminationObserved();
            _ = c.JS_Throw(engine.context, c.pi_js_null());
            return;
        }
        // Produce and cancel a real private event while the earlier generic
        // first reason is detached in the native cleanup owner.
        c.JS_PiRequestExecutionTermination(engine.runtime);
        if (c.JS_PiCheckExecutionTermination(engine.context) >= 0) return;
        var fatal: bool = false;
        const reason = c.JS_PiGetExceptionWithFatal(engine.context, &fatal);
        probe.emitted = c.JS_PiIsExecutionTermination(reason);
        if (!probe.emitted) { _ = c.JS_PiThrowNativePending(engine.context, reason, fatal); return; }
        _ = c.JS_PiThrowNativePending(engine.context, c.JS_DupValue(engine.context, reason), fatal);
        c.JS_PiCancelExecutionTermination(engine.runtime);
        probe.canceled = !c.JS_PiIsExecutionTerminating(engine.runtime);
        // Keep the actual owned token available to the local reducer after
        // cancellation. This is paired native ownership, never diagnostic DATA.
        _ = c.JS_PiThrowNativePending(engine.context, reason, fatal);
    }
    pub fn historyCleanup(probe: *PrivateHistoryProbe, emit_private: bool) !c.JSValue {
        const engine = probe.engine;
        var class: c.JSClassID = 0; _ = c.JS_NewClassID(engine.runtime, &class);
        const definition: c.JSClassDef = .{ .class_name = "Actual private cleanup history witness", .finalizer = historyFinalized };
        if (c.JS_NewClass(engine.runtime, class, &definition) < 0) return error.OutOfMemory;
        const object = try engine.checked(c.JS_NewObjectClass(engine.context, class)); errdefer engine.freeValue(object);
        const payload = try engine.gpa.create(HistoryPayload);
        payload.* = .{ .probe = probe, .emit_private = emit_private };
        _ = c.JS_SetOpaque(object, payload); return object;
    }
    const Payload = struct { engine: *js.Engine, reason: c.JSValue };
    fn finalized(runtime: ?*c.JSRuntime, object: c.JSValue) callconv(.c) void {
        const payload: *Payload = @ptrCast(@alignCast(c.JS_GetOpaque(object, c.JS_GetClassID(object)).?));
        const engine = payload.engine; const reason = payload.reason;
        engine.gpa.destroy(payload);
        _ = runtime; _ = c.JS_Throw(engine.context, reason);
    }
    fn mark(runtime: ?*c.JSRuntime, object: c.JSValue, visit: ?*const c.JS_MarkFunc) callconv(.c) void {
        const payload: *Payload = @ptrCast(@alignCast(c.JS_GetOpaque(object, c.JS_GetClassID(object)).?));
        c.JS_MarkValue(runtime, payload.reason, visit);
    }
    pub fn cleanup(engine: *js.Engine, reason: c.JSValue) !c.JSValue {
        var class: c.JSClassID = 0; _ = c.JS_NewClassID(engine.runtime, &class);
        const definition: c.JSClassDef = .{ .class_name = "Owned mkdir cleanup witness", .finalizer = finalized, .gc_mark = mark };
        if (c.JS_NewClass(engine.runtime, class, &definition) < 0) return error.OutOfMemory;
        const object = try engine.checked(c.JS_NewObjectClass(engine.context, class)); errdefer engine.freeValue(object);
        const payload = try engine.gpa.create(Payload);
        payload.* = .{ .engine = engine, .reason = c.JS_DupValue(engine.context, reason) };
        _ = c.JS_SetOpaque(object, payload); return object;
    }
} else struct {};

test "mkdir owned exit retains first fatal and promotes actual cleanup fatal over ordinary" {
    const std = @import("std");
    const engine = try js.Engine.init(std.testing.allocator, .{}); defer engine.deinit();
    const initial = try engine.checked(c.JS_NewError(engine.context)); defer engine.freeValue(initial);
    const first_cleanup = try engine.checked(c.JS_NewError(engine.context)); defer engine.freeValue(first_cleanup);
    const later_cleanup = try engine.checked(c.JS_NewError(engine.context)); defer engine.freeValue(later_cleanup);
    c.JS_SetUncatchableError(engine.context, first_cleanup); c.JS_SetUncatchableError(engine.context, later_cleanup);
    for ([_]bool{true, false}) |initial_fatal| {
        if (initial_fatal) c.JS_SetUncatchableError(engine.context, initial) else c.JS_ClearUncatchableError(engine.context, initial);
        if (initial_fatal) c.JS_ClearUncatchableError(engine.context, first_cleanup) else c.JS_SetUncatchableError(engine.context, first_cleanup);
        const returned = try Testing.cleanup(engine, first_cleanup);
        const later = try Testing.cleanup(engine, later_cleanup);
        if (initial_fatal) engine.captured_exception = try Testing.cleanup(engine, first_cleanup);
        _ = c.JS_Throw(engine.context, c.JS_DupValue(engine.context, initial));
        var frame: Frame = .{ .engine = engine }; frame.enter(); defer frame.leave();
        try std.testing.expectError(error.JavaScriptException, value(engine, returned));
        release(engine, later);
        try std.testing.expect(!c.JS_HasException(engine.context));
        try std.testing.expect(engine.captured_exception == null);
        try std.testing.expectError(error.JavaScriptException, frame.finishValue(c.pi_js_undefined()));
        const observed = c.JS_GetException(engine.context); defer engine.freeValue(observed);
        try std.testing.expect(c.JS_IsStrictEqual(engine.context, observed, if (initial_fatal) initial else first_cleanup));
    }
}
test "mkdir old flagged captured history is DATA on success" {
    const std = @import("std");
    const engine = try js.Engine.init(std.testing.allocator, .{}); defer engine.deinit();
    const history = try engine.checked(c.JS_NewError(engine.context)); defer engine.freeValue(history);
    c.JS_SetUncatchableError(engine.context, history);
    engine.captured_exception = c.JS_DupValue(engine.context, history);
    var frame: Frame = .{ .engine = engine }; frame.enter(); defer frame.leave();
    const result = try frame.finishValue(c.JS_NewInt32(engine.context, 7)); defer engine.freeValue(result);
    try std.testing.expect(c.JS_IsStrictEqual(engine.context, result, c.JS_NewInt32(engine.context, 7)));
    try std.testing.expect(!c.JS_HasException(engine.context)); try std.testing.expect(engine.captured_exception == null);
}

test "mkdir success-returning native callback keeps its NEW captured fatal before returned cleanup" {
    const std = @import("std");
    const Callback = struct {
        fn run(context: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue, _: c_int, data: [*c]c.JSValue) callconv(.c) c.JSValue {
            const engine = js.Engine.fromContext(context.?);
            var failing = std.testing.FailingAllocator.init(std.testing.allocator, .{ .fail_index = 0 });
            const bytes = failing.allocator().alloc(u8, 1) catch {
                _ = engine.throwNativeOutOfMemory();
                const actual = c.JS_GetException(engine.context);
                c.JS_SetUncatchableError(engine.context, actual);
                _ = engine.checked(c.JS_Throw(engine.context, actual)) catch {};
                return Testing.cleanup(engine, data[0]) catch engine.throwNativeOutOfMemory();
            };
            failing.allocator().free(bytes);
            return c.pi_js_undefined();
        }
    };
    const engine = try js.Engine.init(std.testing.allocator, .{}); defer engine.deinit();
    const ordinary_cleanup = try engine.checked(c.JS_NewError(engine.context)); defer engine.freeValue(ordinary_cleanup);
    const history = try engine.checked(c.JS_NewError(engine.context)); defer engine.freeValue(history);
    c.JS_SetUncatchableError(engine.context, history);
    var data = [_]c.JSValue{ordinary_cleanup};
    const callback = try engine.checked(c.JS_NewCFunctionData2(engine.context, Callback.run, "real allocation capture then success", 0, 0, data.len, &data)); defer engine.freeValue(callback);
    engine.captured_exception = c.JS_DupValue(engine.context, history);
    var frame: Frame = .{ .engine = engine }; frame.enter(); defer frame.leave();
    before(engine);
    const returned = c.JS_Call(engine.context, callback, c.pi_js_undefined(), 0, null);
    try std.testing.expect(!c.JS_IsException(returned));
    try std.testing.expectError(error.JavaScriptException, value(engine, returned));
    try std.testing.expect(!c.JS_HasException(engine.context)); try std.testing.expect(engine.captured_exception == null);
    const generation = engine.native_allocation_generation;
    frame.record(error.OutOfMemory); // propagated host tag after B was escrowed
    try std.testing.expectEqual(generation, engine.native_allocation_generation);
    try std.testing.expectError(error.JavaScriptException, frame.finishValue(c.pi_js_undefined()));
    const observed = c.JS_GetException(engine.context); defer engine.freeValue(observed);
    try std.testing.expect(c.JS_IsStrictEqual(engine.context, observed, engine.native_allocation_exception.?));
    try std.testing.expect(!c.JS_IsStrictEqual(engine.context, observed, history));
    try std.testing.expect(c.JS_IsUncatchableError(observed));
}
pub fn value(engine: *js.Engine, owned: c.JSValue) !c.JSValue {
    if (c.JS_IsException(owned)) return capture(engine);
    pending(engine) catch |err| { release(engine, owned); return err; };
    return owned;
}

test "mkdir primitive fatal capture survives actual invocation pop and later cleanup" {
    const std = @import("std");
    for ([_]bool{ false, true }) |native_fatal| {
        const engine = try js.Engine.init(std.testing.allocator, .{}); defer engine.deinit();
        const later = try engine.checked(c.JS_NewError(engine.context)); defer engine.freeValue(later);
        if (native_fatal) c.JS_SetUncatchableError(engine.context, later);
        const witness = try Testing.cleanup(engine, later);
        var frame: Frame = .{ .engine = engine }; frame.enter(); defer frame.leave();
        if (native_fatal) {
            c.JS_SetMemoryLimit(engine.runtime, 1);
            _ = engine.throwNativeOutOfMemoryFatal();
            c.JS_SetMemoryLimit(engine.runtime, engine.options.memory_limit);
            // The actual invocation, not this diagnostic value, keeps policy.
            _ = engine.checked(c.pi_js_exception()) catch {};
        } else _ = c.JS_Throw(engine.context, c.pi_js_null());
        try std.testing.expectError(error.JavaScriptException, frame.check());
        frame.release(witness);
        try std.testing.expectError(error.JavaScriptException, frame.finishVoid());
        try std.testing.expect(engine.native_fatal_invocation == null);
        var fatal: bool = false;
        const reason = c.JS_PiGetExceptionWithFatal(engine.context, &fatal); defer engine.freeValue(reason);
        try std.testing.expect(c.JS_IsNull(reason));
        try std.testing.expectEqual(native_fatal, fatal);
        try std.testing.expect(!c.JS_IsUncatchableError(reason));
        try std.testing.expect(!c.JS_PiIsPendingUncatchable(engine.context));
        try std.testing.expect(engine.captured_exception == null);
    }
}

test "mkdir canceled private completion yields to a later actual ordinary null" {
    const std = @import("std");
    for ([_]u8{ 0, 1, 2 }) |finish_mode| {
        const engine = try js.Engine.init(std.testing.allocator, .{}); defer engine.deinit();
        var frame: Frame = .{ .engine = engine }; frame.enter(); defer frame.leave();
        c.JS_PiRequestExecutionTermination(engine.runtime);
        try std.testing.expect(c.JS_PiCheckExecutionTermination(engine.context) < 0);
        try std.testing.expectError(error.ExecutionTerminated, frame.check());
        // Cancellation only invalidates an actually pending private event.
        // Re-publish this same detached event without a new request/generation.
        const generation = c.JS_PiExecutionTerminationGeneration(engine.runtime);
        try std.testing.expect(c.JS_PiCheckExecutionTermination(engine.context) < 0);
        try std.testing.expectEqual(generation, c.JS_PiExecutionTerminationGeneration(engine.runtime));
        try std.testing.expect(c.JS_PiIsExecutionTerminating(engine.runtime));
        c.JS_PiCancelExecutionTermination(engine.runtime);
        try std.testing.expect(!c.JS_PiIsExecutionTerminating(engine.runtime));
        _ = c.JS_Throw(engine.context, c.pi_js_null());
        // Ordinary selected cleanup retains generic=false, while the earlier
        // native abort prevents Promise rejection/Action DATA settlement.
        try std.testing.expect(frame.takeOrdinary() == null);
        if (finish_mode == 1)
            try std.testing.expectError(error.ExecutionTerminated, frame.finishAction(.{ .thrown = c.JS_NewInt32(engine.context, 7) }))
        else if (finish_mode == 0)
            try std.testing.expectError(error.ExecutionTerminated, frame.finishVoid())
        else
            try std.testing.expectError(error.ExecutionTerminated, frame.finishValue(c.pi_js_undefined()));
        var fatal: bool = true;
        const reason = c.JS_PiGetExceptionWithFatal(engine.context, &fatal); defer engine.freeValue(reason);
        try std.testing.expect(c.JS_IsNull(reason));
        try std.testing.expect(!fatal);
        try std.testing.expect(!c.JS_PiIsExecutionTerminating(engine.runtime));
        try std.testing.expect(engine.native_fatal_invocation == null);
    }
    // A primitive generic first remains selected, while a later canceled
    // private cleanup must mark every active owner before the next root retires.
    {
        const engine = try js.Engine.init(std.testing.allocator, .{}); defer engine.deinit();
        var probe: Testing.PrivateHistoryProbe = .{ .engine = engine };
        const emitter = try Testing.historyCleanup(&probe, true);
        const observer = try Testing.historyCleanup(&probe, false);
        var outer: js.Engine.NativeInvocation = .{}; engine.enterNativeInvocation(&outer);
        var frame: Frame = .{ .engine = engine }; frame.enter(); defer frame.leave();
        c.JS_SetMemoryLimit(engine.runtime, 1);
        _ = engine.throwNativeOutOfMemoryFatal();
        c.JS_SetMemoryLimit(engine.runtime, engine.options.memory_limit);
        try std.testing.expectError(error.JavaScriptException, frame.check());
        frame.release(emitter); frame.release(observer);
        try std.testing.expectEqual(@as(usize, 2), probe.calls);
        try std.testing.expect(probe.emitted and probe.canceled and probe.observed);
        try std.testing.expectError(error.ExecutionTerminated, frame.finishVoid());
        try std.testing.expect(outer.terminated and engine.nativeTerminationObserved());
        _ = engine.leaveNativeInvocation(&outer, c.pi_js_undefined());
        var fatal: bool = false;
        const reason = c.JS_PiGetExceptionWithFatal(engine.context, &fatal); defer engine.freeValue(reason);
        try std.testing.expect(c.JS_IsNull(reason) and fatal);
        try std.testing.expect(!engine.nativeTerminationObserved());
        try std.testing.expect(engine.native_fatal_invocation == null);
    }
}
