//! Local Agent callback completion escrow across temporary root retirement.
//! Shared Scope/Engine policy is unchanged. Action payloads are owned DATA;
//! only an actual pending event or current NativeInvocation producer is fatal.
const em = @import("engine.zig");
const af = @import("native_async_function.zig");
const Scope = @import("native_sdk_prompt_scope.zig").Scope;
const c = em.c;
const Reason = struct { value: c.JSValue, fatal: bool };
const Outcome = union(enum) { action: af.Action, reason: Reason };

fn payload(action: af.Action) c.JSValue {
    return switch (action) { .returned => |v| v, .awaited => |v| v, .thrown => |v| v };
}
fn isFatal(outcome: Outcome) bool { return switch (outcome) { .reason => |r| r.fatal, else => false }; }
fn failed(outcome: Outcome) bool { return switch (outcome) { .reason => true, .action => |a| switch (a) { .thrown => true, else => false } }; }
fn pending(engine: *em.Engine, boundary: u64) ?Reason {
    if (!c.JS_HasException(engine.context)) return null;
    const value = c.JS_GetException(engine.context);
    const tag = c.pi_js_native_allocation_error_generation(value);
    const distance = tag -% boundary;
    const fresh = tag != 0 and distance != 0 and distance <= engine.native_allocation_generation -% boundary;
    if (fresh) c.JS_SetUncatchableError(engine.context, value);
    return .{ .value = value, .fatal = fresh or c.JS_IsUncatchableError(value) };
}
fn checkCurrent(engine: *em.Engine, first: ?Reason) !void {
    // Publish an actual pending fatal before capture/Scope retirement can run
    // another native finalizer. Engine records it in the live invocation; an
    // already older invocation producer still wins. The original stays owned.
    if (first) |reason| if (reason.fatal) {
        _ = c.JS_Throw(engine.context, c.JS_DupValue(engine.context, reason.value));
    };
    return engine.checkNativeEntry();
}
fn failure(engine: *em.Engine, err: anyerror) Outcome {
    const cleanup = pending(engine, engine.native_allocation_generation);
    // The current producer is an earlier event even if its checked() already
    // consumed pending. Own the saved pending value while transporting it.
    checkCurrent(engine, cleanup) catch {
        var outcome: Outcome = .{ .reason = .{ .value = c.JS_DupValue(engine.context, engine.captured_exception.?), .fatal = true } };
        if (cleanup) |reason| release(engine, &outcome, reason.value);
        return outcome;
    };
    if (err == error.OutOfMemory) {
        // Scope.own consumes its input even when GPA append fails. Retiring
        // that value can publish an ordinary event before OOM reaches us.
        // Own that event, but never downgrade the trusted host allocation
        // failure. An already actual fatal (including the current invocation
        // producer) precedes synthesis; captured-only flags are not consulted.
        if (cleanup) |reason| if (reason.fatal) return .{ .reason = reason };
        _ = engine.throwNativeOutOfMemoryFatal();
        var outcome: Outcome = .{ .reason = pending(engine, engine.native_allocation_generation).? };
        if (cleanup) |reason| release(engine, &outcome, reason.value);
        return outcome;
    }
    if (cleanup) |reason| return .{ .reason = reason };
    // A real fatal already entered checkCurrent above. A captured-only slot
    // is otherwise diagnostic DATA; its flags do not prove a current event.
    if (err == error.JavaScriptException) if (engine.captured_exception) |value| return .{ .reason = .{ .value = c.JS_DupValue(engine.context, value), .fatal = false } };
    _ = c.JS_ThrowTypeError(engine.context, "Native Agent async body: %s", @as([*:0]const u8, @errorName(err)));
    return .{ .reason = pending(engine, engine.native_allocation_generation).? };
}
fn merge(outcome: *Outcome, reason: Reason) c.JSValue {
    if (isFatal(outcome.*) or (failed(outcome.*) and !reason.fatal)) return reason.value;
    const displaced = switch (outcome.*) { .action => |a| payload(a), .reason => |r| r.value };
    outcome.* = .{ .reason = reason };
    return displaced;
}
const Retire = struct {
    // One release can displace the prior payload, one saved pending event,
    // and one event from checkNativeEntry's diagnostic retirement. Once that
    // current producer is selected, no further entry capture is performed.
    values: [3]c.JSValue = undefined,
    count: usize = 0,
    fn add(self: *Retire, value: c.JSValue) void { stdAssert(self.count < self.values.len); self.values[self.count] = value; self.count += 1; }
};
fn stdAssert(value: bool) void { @import("std").debug.assert(value); }
fn observe(engine: *em.Engine, outcome: *Outcome, boundary: u64, retired: *Retire) void {
    const first = pending(engine, boundary);
    // A real producer may have used Engine.checked and consumed VM pending.
    // checkNativeEntry consults the active producer frame; captured flags alone
    // are never sufficient. The earlier frame producer precedes `first`.
    if (!isFatal(outcome.*)) {
        checkCurrent(engine, first) catch {
            const current = engine.captured_exception.?;
            retired.add(merge(outcome, .{ .value = c.JS_DupValue(engine.context, current), .fatal = true }));
        };
    }
    if (first) |r| retired.add(merge(outcome, r));
    while (pending(engine, boundary)) |r| retired.add(merge(outcome, r));
}
fn release(engine: *em.Engine, outcome: *Outcome, value: c.JSValue) void {
    var retired: Retire = .{}; retired.add(value);
    while (retired.count != 0) {
        retired.count -= 1;
        const boundary = engine.native_allocation_generation;
        engine.freeValue(retired.values[retired.count]);
        observe(engine, outcome, boundary, &retired);
    }
}
fn drain(engine: *em.Engine, outcome: *Outcome) void {
    var retired: Retire = .{};
    observe(engine, outcome, engine.native_allocation_generation, &retired);
    while (retired.count != 0) { retired.count -= 1; release(engine, outcome, retired.values[retired.count]); }
}
fn retireScope(scope: *Scope, outcome: *Outcome) void {
    switch (outcome.*) {
        .reason => |initial| if (initial.fatal) {
            // Also align a freshly created generic-error/VM fatal before the
            // very first release. An older recorded producer takes priority.
            checkCurrent(scope.engine, initial) catch {
                outcome.* = .{ .reason = .{ .value = c.JS_DupValue(scope.engine.context, scope.engine.captured_exception.?), .fatal = true } };
                release(scope.engine, outcome, initial.value);
            };
        },
        else => {},
    }
    drain(scope.engine, outcome);
    // Preserve Scope's original release order and observe every release.
    for (scope.values.items) |value| release(scope.engine, outcome, value);
    scope.values.deinit(scope.engine.gpa);
    scope.values = .empty;
}
fn transport(engine: *em.Engine, initial: Outcome) anyerror {
    var outcome = initial;
    while (true) {
        const reason = outcome.reason.value;
        const boundary = engine.native_allocation_generation;
        const ignored = engine.checked(c.JS_Throw(engine.context, c.JS_DupValue(engine.context, reason))) catch c.pi_js_undefined();
        engine.freeValue(ignored); // JS_Throw always produces the exception sentinel.
        var retired: Retire = .{}; observe(engine, &outcome, boundary, &retired);
        while (retired.count != 0) { retired.count -= 1; release(engine, &outcome, retired.values[retired.count]); }
        if (engine.captured_exception) |captured| if (c.JS_IsStrictEqual(engine.context, captured, outcome.reason.value)) {
            // The captured slot retains this SAME value, so this duplicate's
            // release cannot run its native finalizer.
            engine.freeValue(outcome.reason.value);
            return error.JavaScriptException;
        };
    }
}
pub fn finishValue(scope: *Scope, result: anyerror!c.JSValue) !c.JSValue {
    var outcome: Outcome = if (result) |value| .{ .action = .{ .returned = value } } else |err| failure(scope.engine, err);
    retireScope(scope, &outcome);
    return switch (outcome) { .action => |a| a.returned, .reason => transport(scope.engine, outcome) };
}
pub fn finishAction(scope: *Scope, result: anyerror!af.Action) !af.Action {
    var outcome: Outcome = if (result) |action| .{ .action = action } else |err| failure(scope.engine, err);
    retireScope(scope, &outcome);
    return switch (outcome) { .action => |a| a, .reason => |r| if (r.fatal) transport(scope.engine, outcome) else .{ .thrown = r.value } };
}
/// Consume an existing completion while running a synchronous cleanup such as
/// IteratorClose for an ordinary Source throw. Ordinary cleanup cannot replace
/// the original throw DATA; actual current/native fatal cleanup still wins.
pub fn finishPreserving(scope: *Scope, original: af.Action, cleanup_result: anyerror!void) !af.Action {
    var outcome: Outcome = .{ .action = original };
    cleanup_result catch |err| {
        const next = failure(scope.engine, err);
        release(scope.engine, &outcome, merge(&outcome, next.reason));
    };
    retireScope(scope, &outcome);
    return switch (outcome) { .action => |a| a, .reason => |r| if (r.fatal) transport(scope.engine, outcome) else .{ .thrown = r.value } };
}
