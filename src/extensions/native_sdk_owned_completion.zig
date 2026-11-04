//! SDK-local completion escrow, not Engine/Scope or global ordinary-error policy.
//! Caller records the REAL outcome BEFORE any native-owned root retirement.
const std = @import("std");
const em = @import("engine.zig");
const p = @import("native_agent_af_values.zig");
const c = em.c;

const Retirement = struct {
    engine: *em.Engine,
    chosen: ?c.JSValue = null,
    // Only actual pending owners may use the native termination reducer.
    // A thrown Action or captured diagnostic remains DATA even when flagged.
    chosen_pending: bool = false,
    // The recorded Source THROW stays authoritative after its owned duplicate
    // retires. This marker owns no value and never creates a pending event.
    discarded_recorded_throw: bool = false,
    fatal: bool = false, // Established generic fatal authority, not a token bit.
    terminal_abort: bool = false, // Actual private history, separate from selected reason class.
    fn isFatal(self: *const Retirement) bool {
        if (self.fatal) return true;
        if (self.chosen_pending) if (self.chosen) |reason| {
            if (c.JS_PiIsExecutionTermination(reason))
                return c.JS_PiNativePendingPriority(c.JS_GetRuntime(self.engine.context), reason) > 0;
        };
        return false;
    }
    fn merge(self: *Retirement, reason: c.JSValue, boundary: ?u64, generic_fatal: bool) ?u64 {
        if (c.JS_PiIsExecutionTermination(reason)) {
            self.terminal_abort = true;
            if (self.engine.native_fatal_invocation != null and !self.engine.nativeTerminationObserved()) {
                // This paired take owns an actual private token. Record its
                // history before any root retires, even behind generic first.
                // The guard makes the actual-only duplicate drain finite.
                _ = c.JS_PiThrowNativePending(self.engine.context, c.JS_DupValue(self.engine.context, reason), generic_fatal);
                self.engine.releaseNativeValue(c.pi_js_undefined());
            }
        }
        var fatal = generic_fatal;
        // Called ONLY for owned ACTUAL pending events, never a diagnostic or
        // PromiseResult. Recognize a private producer born in this exact free.
        if (boundary) |generation| {
            const tagged = c.pi_js_native_allocation_error_generation(reason);
            const distance = tagged -% generation;
            if (tagged != 0 and distance != 0 and distance <= self.engine.native_allocation_generation -% generation) {
                c.JS_SetUncatchableError(self.engine.context, reason);
                fatal = true;
                // Record the actual marked event in the stable invocation
                // before any displaced diagnostic/native finalizer retires.
                _ = self.engine.checked(c.JS_PiThrowNativePending(self.engine.context, c.JS_DupValue(self.engine.context, reason), true)) catch {};
            }
        }
        var replace = self.chosen == null and !self.discarded_recorded_throw;
        if (self.chosen) |previous| {
            replace = if (self.chosen_pending)
                c.JS_PiNativePendingReplaceClassified(c.JS_GetRuntime(self.engine.context),
                    previous, self.fatal, reason, fatal)
            else fatal or (c.JS_PiIsExecutionTermination(reason) and
                c.JS_PiNativePendingPriority(c.JS_GetRuntime(self.engine.context), reason) > 0);
        } else if (self.discarded_recorded_throw) {
            // Ordinary native cleanup cannot replace the recorded Source
            // throw. Genuine actual fatal/private events retain their class.
            replace = fatal or (c.JS_PiIsExecutionTermination(reason) and
                c.JS_PiNativePendingPriority(c.JS_GetRuntime(self.engine.context), reason) > 0);
        }
        if (replace) {
            self.discarded_recorded_throw = false;
            const displaced = self.chosen;
            self.chosen = reason;
            self.chosen_pending = true;
            self.fatal = fatal;
            if (displaced) |old| {
                const generation = self.engine.native_allocation_generation;
                self.engine.freeValue(old);
                return generation;
            }
        } else {
            const generation = self.engine.native_allocation_generation;
            self.engine.freeValue(reason);
            return generation;
        }
        return null;
    }
    fn events(self: *Retirement, boundary: ?u64) void {
        self.eventsMode(boundary, true);
    }
    fn eventsMode(self: *Retirement, boundary: ?u64, poll_requests: bool) void {
        var generation = boundary;
        // Surface Bfb's independently retained first actual invocation event.
        if (!self.isFatal()) {
            if (poll_requests) _ = self.engine.nativeCallbackResult(c.pi_js_undefined())
            else self.engine.releaseNativeValue(c.pi_js_undefined());
        }
        self.terminal_abort = self.terminal_abort or self.engine.nativeTerminationObserved();
        while (c.JS_HasException(self.engine.context) or self.engine.captured_exception != null) {
            if (c.JS_HasException(self.engine.context)) {
                var generic_fatal: bool = false;
                const reason = c.JS_PiGetExceptionWithFatal(self.engine.context, &generic_fatal);
                generation = self.merge(reason, generation, generic_fatal);
            } else {
                const reason = self.engine.captured_exception.?;
                self.engine.captured_exception = null;
                // A diagnostic-only capture may be rejected Promise DATA.
                // Retire it as DATA; only independently retained/pending
                // actual events can promote the completion.
                generation = self.engine.native_allocation_generation;
                self.engine.freeValue(reason);
                if (!self.isFatal()) {
                    if (poll_requests) _ = self.engine.nativeCallbackResult(c.pi_js_undefined())
                    else self.engine.releaseNativeValue(c.pi_js_undefined());
                }
            }
            self.terminal_abort = self.terminal_abort or self.engine.nativeTerminationObserved();
        }
    }
};

/// A stack-owned host completion. It contains no escaping stack pointer and
/// records no PromiseResult DATA event. Caller MUST finish it exactly once.
/// release()/releaseScope() replace only native deallocation, never Source
/// IteratorClose/catch/finally operations with their own language precedence.
pub const Completion = struct {
    owner: Retirement,
    action: ?p.af.Action = null,
    diagnostic: ?c.JSValue = null,
    pending: ?c.JSValue = null,
    pending_generic_fatal: bool = false,
    invocation: em.Engine.NativeInvocation = .{},
    recorded_throw: bool = false,
    // A cancelled native call can still return this explicit abrupt error
    // after its private pending slot has been cleared by the actual cancel.
    native_aborted: bool = false,
    finished: bool = false,

    pub fn initAction(engine: *em.Engine, result: anyerror!p.af.Action) Completion {
        var selected: ?p.af.Action = null;
        var native_aborted = engine.nativeTerminationObserved();
        if (result) |action| {
            selected = action;
        } else |err| {
            // Surface actual pending/current invocation events independently
            // BEFORE inspecting a failed-operation diagnostic ownership slot.
            _ = engine.nativeCallbackResult(c.pi_js_undefined());
            if (err == error.ExecutionTerminated) {
                native_aborted = true;
            } else if (err == error.JavaScriptException and !c.JS_HasException(engine.context) and engine.captured_exception != null) {
                const reason = engine.captured_exception.?;
                engine.captured_exception = null;
                selected = .{ .thrown = reason }; // Owned DATA; never flag/tag infer.
            } else {
                // Direct trusted GPA and non-JS host failures become actual
                // producer exits before any owned temporary is released.
                _ = @import("native_sdk.zig").fail(engine, err);
            }
        }
        native_aborted = native_aborted or engine.nativeTerminationObserved();
        var self: Completion = .{ .owner = .{ .engine = engine }, .action = selected, .native_aborted = native_aborted };
        if (self.action) |action| switch (action) {
            // Even flagged/private Error payloads are DATA, not pending events.
            .thrown => |reason| { self.owner.chosen = reason; self.action = null; },
            else => {},
        };
        // Detach historical diagnostic DATA before any free. Its own flag has
        // no authority; newly captured cleanup events then have an empty slot.
        self.diagnostic = engine.captured_exception;
        engine.captured_exception = null;
        // Own entry pending without releasing another value in this inactive
        // init record; the first release starts the caller-stable boundary.
        if (c.JS_HasException(engine.context)) self.pending = c.JS_PiGetExceptionWithFatal(engine.context, &self.pending_generic_fatal);
        return self;
    }
    pub fn initValue(engine: *em.Engine, result: anyerror!c.JSValue) Completion {
        const outcome: anyerror!p.af.Action = if (result) |value| .{ .returned = value } else |err| err;
        return initAction(engine, outcome);
    }
    pub fn initVoid(engine: *em.Engine, result: anyerror!void) Completion {
        const outcome: anyerror!p.af.Action = if (result) |_| .{ .returned = c.pi_js_undefined() } else |err| err;
        return initAction(engine, outcome);
    }
    pub fn initRecorded(s: anytype, result: anyerror!void, state: c.JSValue) Completion {
        result catch |err| return initVoid(s.engine, err);
        s.engine.checkNativeEntry() catch |err| return initVoid(s.engine, err);
        const selected = p.body.action(s, state) catch |err| return initVoid(s.engine, err);
        var self = initAction(s.engine, selected);
        self.recorded_throw = selected == .thrown;
        return self;
    }
    fn enter(self: *Completion) void {
        self.native_aborted = self.native_aborted or self.invocation.terminated or self.owner.engine.nativeTerminationObserved();
        if (self.invocation.active) return;
        // init* returns INACTIVE by value. Only this caller-stable address is
        // linked; never copy/move a record after release/finish has started.
        self.owner.engine.enterNativeInvocation(&self.invocation);
        if (self.pending) |first| {
            self.pending = null;
            var later_generic_fatal: bool = false;
            const later: ?c.JSValue = if (c.JS_HasException(self.owner.engine.context))
                c.JS_PiGetExceptionWithFatal(self.owner.engine.context, &later_generic_fatal) else null;
            _ = c.JS_PiThrowNativePending(self.owner.engine.context, first, self.pending_generic_fatal);
            self.pending_generic_fatal = false;
            self.owner.events(null);
            if (later) |reason| { const generation = self.owner.merge(reason, null, later_generic_fatal); self.owner.events(generation); }
        } else self.owner.events(null);
    }
    /// Consumes one actual owned native root in the caller's original order.
    pub fn release(self: *Completion, value: c.JSValue) void {
        std.debug.assert(!self.finished);
        self.enter();
        const generation = self.owner.engine.native_allocation_generation;
        self.owner.engine.freeValue(value);
        self.owner.events(generation);
    }
    /// Consumes actual prompt ArrayList or provider inline32+overflow roots.
    pub fn releaseScope(self: *Completion, scope: anytype) void {
        std.debug.assert(!self.finished);
        self.enter();
        var roots = scope.values;
        scope.values = .empty;
        if (comptime @hasField(@TypeOf(scope.*), "inline_values")) {
            const count = scope.inline_count;
            scope.inline_count = 0;
            for (scope.inline_values[0..count]) |value| self.release(value);
        }
        for (roots.items) |value| self.release(value);
        roots.deinit(scope.engine.gpa);
    }
    pub fn finishAction(self: *Completion) anyerror!p.af.Action {
        return self.finishActionMode(.transfer);
    }
    fn finishActionMode(self: *Completion, comptime mode: enum { transfer, discard_return, discard_recorded }) anyerror!p.af.Action {
        std.debug.assert(!self.finished);
        self.enter();
        if (self.diagnostic) |value| { self.diagnostic = null; self.release(value); }
        if (mode != .transfer) {
            if (mode == .discard_recorded and self.recorded_throw and !self.owner.chosen_pending) if (self.owner.chosen) |reason| {
                self.owner.chosen = null;
                self.owner.discarded_recorded_throw = true;
                self.action = .{ .returned = c.pi_js_undefined() };
                self.release(reason);
            };
            if (self.action) |action| {
                // No returned/awaited root escapes a void completion. Keep
                // the stable owner active while each discarded root retires.
                self.action = .{ .returned = c.pi_js_undefined() };
                switch (action) {
                    .returned => |value| self.release(value),
                    .awaited => |value| if (mode == .discard_recorded) self.release(value) else unreachable,
                    .thrown => unreachable,
                }
            }
        }
        if (self.owner.chosen != null or self.native_aborted or self.owner.terminal_abort or self.invocation.terminated) if (self.action) |action| {
            self.action = null;
            switch (action) { .returned, .awaited, .thrown => |value| self.release(value) }
        };
        // Pop before the selected completion or Await can escape. Keep our
        // chosen first reason owned while the invocation holder retires.
        _ = self.owner.engine.leaveNativeInvocation(&self.invocation, c.pi_js_undefined());
        self.native_aborted = self.native_aborted or self.invocation.terminated or self.owner.engine.nativeTerminationObserved();
        self.owner.eventsMode(null, false);
        self.finished = true;
        if (self.owner.chosen) |reason| {
            const actual_pending = self.owner.chosen_pending;
            self.owner.chosen = null;
            self.owner.chosen_pending = false;
            if (self.native_aborted or self.owner.terminal_abort) {
                // The reason may be later ordinary cleanup or a genuine
                // generic fatal. Keep its actual class while history alone
                // retires the already-aborted native AF/AG activation.
                _ = if (actual_pending)
                    c.JS_PiThrowNativePending(self.owner.engine.context, reason, self.owner.fatal)
                else c.JS_PiThrowExceptionData(self.owner.engine.context, reason);
                return error.ExecutionTerminated;
            }
            if (self.owner.fatal or (actual_pending and c.JS_PiIsExecutionTermination(reason))) {
                const termination = actual_pending and c.JS_PiIsExecutionTermination(reason);
                _ = c.JS_PiThrowNativePending(self.owner.engine.context, reason, self.owner.fatal);
                // The final owner has popped: keep the actual tuple pending,
                // without converting it to captured diagnostic DATA.
                return if (termination) error.ExecutionTerminated else error.JavaScriptException;
            }
            return .{ .thrown = reason };
        }
        if (self.native_aborted or self.owner.terminal_abort) return error.ExecutionTerminated;
        const action = self.action orelse return error.MissingSdkScopeCompletion;
        self.action = null;
        return action;
    }
    pub fn finishValue(self: *Completion) anyerror!c.JSValue {
        return switch (try self.finishAction()) {
            .returned => |value| value,
            .thrown => |reason| self.owner.engine.checked(c.JS_PiThrowExceptionData(self.owner.engine.context, reason)),
            .awaited => unreachable,
        };
    }
    pub fn finishVoid(self: *Completion) anyerror!void {
        switch (try self.finishActionMode(.discard_return)) {
            .returned => {},
            .thrown => |reason| { _ = try self.owner.engine.checked(c.JS_PiThrowExceptionData(self.owner.engine.context, reason)); unreachable; },
            .awaited => unreachable,
        }
    }
    pub fn finishRecorded(self: *Completion) anyerror!void {
        switch (try self.finishActionMode(.discard_recorded)) {
            .returned => {},
            .thrown => |reason| { _ = try self.owner.engine.checked(c.JS_PiThrowExceptionData(self.owner.engine.context, reason)); unreachable; },
            .awaited => unreachable,
        }
    }
};

pub fn finishAction(scope: anytype, result: anyerror!p.af.Action) anyerror!p.af.Action {
    var completion = Completion.initAction(scope.engine, result);
    completion.releaseScope(scope);
    return completion.finishAction();
}
pub fn finishValue(scope: anytype, result: anyerror!c.JSValue) anyerror!c.JSValue {
    var completion = Completion.initValue(scope.engine, result);
    completion.releaseScope(scope);
    return completion.finishValue();
}
pub fn finishVoid(scope: anytype, result: anyerror!void) anyerror!void {
    var completion = Completion.initVoid(scope.engine, result);
    completion.releaseScope(scope);
    return completion.finishVoid();
}
pub fn finishRecorded(scope: anytype, result: anyerror!void, state: c.JSValue) anyerror!void {
    var completion = Completion.initRecorded(scope, result, state);
    completion.releaseScope(scope);
    return completion.finishRecorded();
}

/// Consume a checked, owned ordinary JS value into SDK temporary storage.
/// Caller normalizes its actual get/call/allocation result BEFORE this method;
/// JS_EXCEPTION without a pending event is a native callback-contract failure,
/// not a stored value. No flag/tag on `value` or diagnostic DATA is inspected.
/// Both prompt ArrayList and provider inline32+overflow storage are supported.
pub fn ownRoot(scope: anytype, value: c.JSValue) anyerror!c.JSValue {
    const engine = scope.engine;
    engine.native_exception_diagnostics_suppressed += 1;
    defer engine.native_exception_diagnostics_suppressed -= 1;
    // Surface actual pending/Bfb events WITHOUT first capturing/freeing an old
    // diagnostic. initValue snapshots both slots before the incoming root can
    // retire. With no event this leaves captured-only history entirely DATA.
    _ = engine.nativeCallbackResult(c.pi_js_undefined());
    if (engine.nativeTerminationObserved()) return rejectRoot(scope, value, error.ExecutionTerminated);
    if (c.JS_HasException(engine.context)) return rejectRoot(scope, value, error.JavaScriptException);
    std.debug.assert(!c.JS_IsException(value));
    if (comptime @hasField(@TypeOf(scope.*), "inline_values")) {
        if (scope.inline_count < scope.inline_values.len) {
            scope.inline_values[scope.inline_count] = value;
            scope.inline_count += 1;
            return value;
        }
    }
    scope.values.append(engine.gpa, value) catch |err| {
        // This typed allocator failure is the actual producer. Publish/own it
        // before freeing a sole carrier, even with an old flagged/private DATA
        // reason in captured_exception. The existing completion core delegates
        // typed OOM directly to throwNativeOutOfMemoryFatal, not throwCaptured.
        return rejectRoot(scope, value, err);
    };
    return value;
}
fn rejectRoot(scope: anytype, value: c.JSValue, err: anyerror) anyerror!c.JSValue {
    var completion = Completion.initValue(scope.engine, err);
    completion.release(value);
    return completion.finishValue();
}
