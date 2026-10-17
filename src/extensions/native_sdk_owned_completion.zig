//! SDK-local completion escrow, not Engine/Scope or global ordinary-error policy.
//! Caller records the REAL outcome BEFORE any native-owned root retirement.
const std = @import("std");
const em = @import("engine.zig");
const p = @import("native_agent_af_values.zig");
const c = em.c;

const Retirement = struct {
    engine: *em.Engine,
    chosen: ?c.JSValue = null,
    fatal: bool = false,
    fn merge(self: *Retirement, reason: c.JSValue, boundary: ?u64) ?u64 {
        // Called ONLY for owned ACTUAL pending events, never a diagnostic or
        // PromiseResult. Recognize a private producer born in this exact free.
        if (boundary) |generation| {
            const tagged = c.pi_js_native_allocation_error_generation(reason);
            const distance = tagged -% generation;
            if (tagged != 0 and distance != 0 and distance <= self.engine.native_allocation_generation -% generation) {
                c.JS_SetUncatchableError(self.engine.context, reason);
                // Record the actual marked event in the stable invocation
                // before any displaced diagnostic/native finalizer retires.
                _ = self.engine.checked(c.JS_Throw(self.engine.context, c.JS_DupValue(self.engine.context, reason))) catch {};
            }
        }
        const fatal = c.JS_IsUncatchableError(reason);
        if (self.chosen == null or (!self.fatal and fatal)) {
            const displaced = self.chosen;
            self.chosen = reason;
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
        var generation = boundary;
        // Surface Bfb's independently retained first actual invocation event.
        _ = self.engine.nativeCallbackResult(c.pi_js_undefined());
        while (c.JS_HasException(self.engine.context) or self.engine.captured_exception != null) {
            if (c.JS_HasException(self.engine.context)) generation = self.merge(c.JS_GetException(self.engine.context), generation)
            else {
                const reason = self.engine.captured_exception.?;
                self.engine.captured_exception = null;
                // A diagnostic-only capture may be rejected Promise DATA.
                // Retire it as DATA; only independently retained/pending
                // actual events can promote the completion.
                generation = self.engine.native_allocation_generation;
                self.engine.freeValue(reason);
                if (!self.fatal) _ = self.engine.nativeCallbackResult(c.pi_js_undefined());
            }
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
    invocation: em.Engine.NativeInvocation = .{},
    recorded_throw: bool = false,
    finished: bool = false,

    pub fn initAction(engine: *em.Engine, result: anyerror!p.af.Action) Completion {
        var selected: ?p.af.Action = null;
        if (result) |action| {
            selected = action;
        } else |err| {
            // Surface actual pending/current invocation events independently
            // BEFORE inspecting a failed-operation diagnostic ownership slot.
            _ = engine.nativeCallbackResult(c.pi_js_undefined());
            if (err == error.JavaScriptException and !c.JS_HasException(engine.context) and engine.captured_exception != null) {
                const reason = engine.captured_exception.?;
                engine.captured_exception = null;
                selected = .{ .thrown = reason }; // Owned DATA; never flag/tag infer.
            } else {
                // Direct trusted GPA and non-JS host failures become actual
                // producer exits before any owned temporary is released.
                _ = @import("native_sdk.zig").fail(engine, err);
            }
        }
        var self: Completion = .{ .owner = .{ .engine = engine }, .action = selected };
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
        if (c.JS_HasException(engine.context)) self.pending = c.JS_GetException(engine.context);
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
        if (self.invocation.active) return;
        // init* returns INACTIVE by value. Only this caller-stable address is
        // linked; never copy/move a record after release/finish has started.
        self.owner.engine.enterNativeInvocation(&self.invocation);
        if (self.pending) |first| {
            self.pending = null;
            const later: ?c.JSValue = if (c.JS_HasException(self.owner.engine.context)) c.JS_GetException(self.owner.engine.context) else null;
            _ = c.JS_Throw(self.owner.engine.context, first); // Empty slot.
            self.owner.events(null);
            if (later) |reason| { const generation = self.owner.merge(reason, null); self.owner.events(generation); }
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
        std.debug.assert(!self.finished);
        self.enter();
        if (self.diagnostic) |value| { self.diagnostic = null; self.release(value); }
        if (self.owner.chosen != null) if (self.action) |action| {
            self.action = null;
            switch (action) { .returned, .awaited, .thrown => |value| self.release(value) }
        };
        // Pop before the selected completion or Await can escape. Keep our
        // chosen first reason owned while the invocation holder retires.
        _ = self.owner.engine.leaveNativeInvocation(&self.invocation, c.pi_js_undefined());
        self.owner.events(null);
        self.finished = true;
        if (self.owner.chosen) |reason| {
            self.owner.chosen = null;
            if (self.owner.fatal) {
                _ = try self.owner.engine.checked(c.JS_Throw(self.owner.engine.context, reason));
                unreachable;
            }
            return .{ .thrown = reason };
        }
        const action = self.action orelse return error.MissingSdkScopeCompletion;
        self.action = null;
        return action;
    }
    pub fn finishValue(self: *Completion) anyerror!c.JSValue {
        return switch (try self.finishAction()) {
            .returned => |value| value,
            .thrown => |reason| self.owner.engine.checked(c.JS_Throw(self.owner.engine.context, reason)),
            .awaited => unreachable,
        };
    }
    pub fn finishVoid(self: *Completion) anyerror!void {
        switch (try self.finishAction()) {
            .returned => |value| self.owner.engine.freeValue(value),
            .thrown => |reason| { _ = try self.owner.engine.checked(c.JS_Throw(self.owner.engine.context, reason)); unreachable; },
            .awaited => unreachable,
        }
    }
    pub fn finishRecorded(self: *Completion) anyerror!void {
        switch (try self.finishAction()) {
            .thrown => |reason| {
                if (self.recorded_throw) self.owner.engine.freeValue(reason)
                else { _ = try self.owner.engine.checked(c.JS_Throw(self.owner.engine.context, reason)); unreachable; }
            },
            .returned, .awaited => |value| self.owner.engine.freeValue(value),
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