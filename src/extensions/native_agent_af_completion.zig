//! Agent-local owned completion escrow across temporary root retirement.
//! Action payloads and captured diagnostics are DATA. Actual pending events
//! retain their cached class; historical private unwind remains independent.
const em = @import("engine.zig");
const af = @import("native_async_function.zig");
const Scope = @import("native_sdk_prompt_scope.zig").Scope;
const c = em.c;

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
const Outcome = union(enum) { action: af.Action, reason: Reason };
fn payload(action: af.Action) c.JSValue {
    return switch (action) { .returned => |v| v, .awaited => |v| v, .thrown => |v| v };
}
fn pending(engine: *em.Engine, release_generation: ?u64) ?Reason {
    if (!c.JS_HasException(engine.context)) return null;
    var fatal: bool = false;
    const value = c.JS_PiGetExceptionWithFatal(engine.context, &fatal);
    if (!c.JS_PiIsExecutionTermination(value)) if (release_generation) |generation| {
        // This optional provenance belongs to one actual root release only.
        const tag = c.pi_js_native_allocation_error_generation(value);
        const distance = tag -% generation;
        if (tag != 0 and distance != 0 and distance <= engine.native_allocation_generation -% generation) {
            fatal = true;
            c.JS_SetUncatchableError(engine.context, value);
        }
    };
    return .{ .value = value, .fatal = fatal };
}

const Exit = struct {
    engine: *em.Engine,
    invocation: em.Engine.NativeInvocation = .{},
    outcome: ?Outcome = null,
    terminated: bool = false,

    fn enter(self: *Exit) void {
        self.engine.enterNativeInvocation(&self.invocation);
        self.terminated = self.engine.nativeTerminationObserved();
    }
    fn ownsFatal(self: *Exit) bool {
        return if (self.outcome) |outcome| switch (outcome) {
            .reason => |reason| reason.isFatal(self.engine),
            .action => false,
        } else false;
    }
    fn action(self: *Exit, owned: af.Action) void {
        @import("std").debug.assert(self.outcome == null);
        // Source THROW is deliberately ordinary DATA even if its Error object
        // was previously flagged. It still precedes ordinary cleanup.
        self.outcome = switch (owned) {
            .thrown => |value| .{ .reason = .{ .value = value, .fatal = false, .actual_pending = false } },
            else => .{ .action = owned },
        };
    }
    fn select(self: *Exit, next: Reason) ?c.JSValue {
        rememberProducer(self.engine, next);
        if (next.actual_pending and c.JS_PiIsExecutionTermination(next.value))
            self.terminated = true;
        const prior_outcome = self.outcome orelse {
            self.outcome = .{ .reason = next };
            return null;
        };
        switch (prior_outcome) {
            .reason => |prior| {
                const replace = if (prior.actual_pending and next.actual_pending)
                    c.JS_PiNativePendingReplaceClassified(self.engine.runtime,
                        prior.value, prior.fatal, next.value, next.fatal)
                else if (!prior.actual_pending) next.isFatal(self.engine)
                else c.JS_PiIsExecutionTermination(prior.value) and
                    c.JS_PiNativePendingPriority(self.engine.runtime, prior.value) < 0;
                if (!replace) return next.value;
                self.outcome = .{ .reason = next };
                return prior.value;
            },
            .action => |prior| {
                self.outcome = .{ .reason = next };
                return payload(prior);
            },
        }
    }
    fn merge(self: *Exit, next: Reason) void {
        if (self.select(next)) |retired| self.release(retired);
    }
    fn drain(self: *Exit, release_generation: ?u64) void {
        var generation = release_generation;
        while (true) {
            // Repeatedly resurfacing an already owned primitive fatal would
            // recurse forever. A canceled private event has dynamic priority.
            if (!self.ownsFatal()) {
                if (self.invocation.active)
                    _ = self.engine.nativeCallbackResult(c.pi_js_undefined())
                else
                    self.engine.releaseNativeValue(c.pi_js_undefined());
            }
            // Retired collection observes actual events and retained owners;
            // it cannot service a fresh request after this owner has popped.
            self.terminated = self.terminated or self.engine.nativeTerminationObserved();
            const actual = pending(self.engine, generation);
            const captured = self.engine.captured_exception;
            self.engine.captured_exception = null;
            if (actual == null and captured == null) return;
            const displaced = if (actual) |reason| self.select(reason) else null;
            // Snapshot both channels before any destructor. Diagnostic flags
            // and tags never establish actual pending-event ownership.
            if (displaced) |value| self.release(value);
            if (captured) |value| self.release(value);
            generation = null;
        }
    }
    fn release(self: *Exit, owned: c.JSValue) void {
        const generation = self.engine.native_allocation_generation;
        self.engine.freeValue(owned);
        self.drain(generation);
    }
    fn record(self: *Exit, err: anyerror) void {
        if (err == error.ExecutionTerminated) self.terminated = true;
        if (!self.ownsFatal()) _ = self.engine.nativeCallbackResult(c.pi_js_undefined());
        self.terminated = self.terminated or self.engine.nativeTerminationObserved();
        const actual = pending(self.engine, null);
        const captured = self.engine.captured_exception;
        self.engine.captured_exception = null;
        var discard_captured = captured;
        var discard_actual: ?c.JSValue = null;
        var supplied = false;
        if (actual) |reason| {
            discard_actual = self.select(reason);
            supplied = true;
        } else if (err == error.JavaScriptException) {
            if (captured) |reason| {
                discard_captured = self.select(.{ .value = reason, .fatal = false, .actual_pending = false });
                supplied = true;
            }
        }
        // Scope.own can retire its input after a real GPA failure. An ordinary
        // cleanup event must not hide that genuine host allocation producer.
        if (err == error.OutOfMemory and !self.ownsFatal()) {
            _ = self.engine.throwNativeOutOfMemoryFatal();
            if (pending(self.engine, null)) |reason| self.merge(reason);
            supplied = true;
        }
        if (!supplied and !self.terminated and !self.ownsFatal()) {
            _ = c.JS_ThrowTypeError(self.engine.context, "Native Agent async body: %s", @as([*:0]const u8, @errorName(err)));
            if (pending(self.engine, null)) |reason| self.merge(reason);
        }
        if (discard_actual) |value| self.release(value);
        if (discard_captured) |value| self.release(value);
        self.drain(null);
    }
    fn retireScope(self: *Exit, scope: *Scope) void {
        self.drain(null);
        // Preserve the original Scope order and observe each actual release.
        for (scope.values.items) |value| self.release(value);
        scope.values.deinit(self.engine.gpa);
        scope.values = .empty;
        self.drain(null);
    }
    fn retireAbortedAction(self: *Exit) void {
        if (!self.terminated) return;
        if (self.outcome) |outcome| switch (outcome) {
            .action => |owned| {
                self.outcome = null;
                self.release(payload(owned));
            },
            .reason => {},
        };
    }
    fn close(self: *Exit) void {
        self.retireAbortedAction();
        self.drain(null);
        const result = self.engine.leaveNativeInvocation(&self.invocation, c.pi_js_undefined());
        self.terminated = self.terminated or self.invocation.terminated;
        self.engine.freeValue(result); // Immediate undefined/exception only.
        self.drain(null);
        self.retireAbortedAction();
    }
    fn publish(self: *Exit) anyerror {
        const outcome = self.outcome;
        self.outcome = null;
        if (outcome) |owned| switch (owned) {
            .reason => |reason| {
                if (reason.actual_pending) {
                    _ = c.JS_PiThrowNativePending(self.engine.context, reason.value, reason.fatal);
                } else {
                    _ = c.JS_PiThrowExceptionData(self.engine.context, reason.value);
                }
            },
            .action => unreachable,
        };
        return if (self.terminated) error.ExecutionTerminated else error.JavaScriptException;
    }
    fn takeAction(self: *Exit) !af.Action {
        if (self.terminated) return self.publish();
        const outcome = self.outcome orelse return error.JavaScriptException;
        return switch (outcome) {
            .action => |owned| blk: { self.outcome = null; break :blk owned; },
            .reason => |reason| if (reason.uncatchable()) self.publish() else blk: {
                self.outcome = null;
                break :blk .{ .thrown = reason.value };
            },
        };
    }
};

pub fn finishValue(scope: *Scope, result: anyerror!c.JSValue) !c.JSValue {
    var exit: Exit = .{ .engine = scope.engine };
    exit.enter();
    if (result) |value| exit.action(.{ .returned = value }) else |err| exit.record(err);
    exit.retireScope(scope);
    exit.close();
    if (exit.terminated) return exit.publish();
    const outcome = exit.outcome orelse return error.JavaScriptException;
    return switch (outcome) {
        .action => |owned| blk: { exit.outcome = null; break :blk owned.returned; },
        .reason => exit.publish(),
    };
}
pub fn finishAction(scope: *Scope, result: anyerror!af.Action) !af.Action {
    var exit: Exit = .{ .engine = scope.engine };
    exit.enter();
    if (result) |owned| exit.action(owned) else |err| exit.record(err);
    exit.retireScope(scope);
    exit.close();
    return exit.takeAction();
}
/// Ordinary Source throw data precedes ordinary IteratorClose cleanup. A real
/// fatal event or historical native unwind still escapes through the AF owner.
pub fn finishPreserving(scope: *Scope, original: af.Action, cleanup_result: anyerror!void) !af.Action {
    var exit: Exit = .{ .engine = scope.engine };
    exit.enter();
    exit.action(original);
    cleanup_result catch |err| exit.record(err);
    exit.retireScope(scope);
    exit.close();
    return exit.takeAction();
}
