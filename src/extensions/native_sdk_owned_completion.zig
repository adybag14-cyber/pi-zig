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
    fn merge(self: *Retirement, reason: c.JSValue) void {
        const fatal = c.JS_IsUncatchableError(reason);
        if (self.chosen == null or (!self.fatal and fatal)) {
            const displaced = self.chosen;
            self.chosen = reason;
            self.fatal = fatal;
            if (displaced) |old| self.engine.freeValue(old);
        } else self.engine.freeValue(reason);
    }
    fn events(self: *Retirement) void {
        // Surface Bfb's independently retained first actual invocation event.
        _ = self.engine.nativeCallbackResult(c.pi_js_undefined());
        while (c.JS_HasException(self.engine.context) or self.engine.captured_exception != null) {
            if (c.JS_HasException(self.engine.context)) self.merge(c.JS_GetException(self.engine.context))
            else {
                const reason = self.engine.captured_exception.?;
                self.engine.captured_exception = null;
                self.merge(reason);
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
    recorded_throw: bool = false,
    finished: bool = false,

    pub fn initAction(engine: *em.Engine, result: anyerror!p.af.Action) Completion {
        var selected: ?p.af.Action = null;
        if (result) |action| selected = action else |err| {
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
        self.owner.events();
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
        const selected = p.body.action(s, state) catch |err| return initVoid(s.engine, err);
        var self = initAction(s.engine, selected);
        self.recorded_throw = selected == .thrown;
        return self;
    }
    /// Consumes one actual owned native root in the caller's original order.
    pub fn release(self: *Completion, value: c.JSValue) void {
        std.debug.assert(!self.finished);
        self.owner.engine.freeValue(value);
        self.owner.events();
    }
    /// Consumes actual prompt ArrayList or provider inline32+overflow roots.
    pub fn releaseScope(self: *Completion, scope: anytype) void {
        std.debug.assert(!self.finished);
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
        if (self.diagnostic) |value| { self.diagnostic = null; self.release(value); }
        if (self.owner.chosen != null) if (self.action) |action| {
            self.action = null;
            switch (action) { .returned, .awaited, .thrown => |value| self.release(value) }
        };
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