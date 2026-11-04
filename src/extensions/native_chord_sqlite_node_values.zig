//! Operation-local roots and genuine AF boundaries for Chord's Node adapter.
const em = @import("engine.zig");
pub const c = em.c;
const std = @import("std");
/// Private roots. A current VM event is normalized before the host append.
/// Error unwinding owns its first reason across root/finalizer cleanup.
pub const Scope = struct {
    engine: *em.Engine,
    values: std.ArrayList(c.JSValue) = .empty,
    unwind: ?c.JSValue = null,
    unwind_actual_pending: bool = false,
    unwind_generic_fatal: bool = false,
    pub fn captureUnwind(self: *Scope, err: anyerror) void {
        if (self.unwind != null) return;
        _ = self.engine.nativeCallbackResult(c.pi_js_undefined());
        if (err == error.OutOfMemory) _ = self.engine.throwNativeOutOfMemoryFatal();
        if (err != error.JavaScriptException and err != error.OutOfMemory and !c.JS_HasException(self.engine.context)) return;
        self.unwind_actual_pending = c.JS_HasException(self.engine.context);
        self.unwind_generic_fatal = false;
        self.unwind = if (self.unwind_actual_pending)
            c.JS_PiGetExceptionWithFatal(self.engine.context, &self.unwind_generic_fatal)
        else takeCaptured(self.engine);
    }
    pub fn deinit(self: *Scope) void {
        self.engine.native_exception_diagnostics_suppressed += 1;
        defer self.engine.native_exception_diagnostics_suppressed -= 1;
        var cleanup: Cleanup = .{ .engine = self.engine };
        if (self.unwind) |reason| {
            if (self.unwind_actual_pending) cleanup.event(reason, self.unwind_generic_fatal) else cleanup.escaping(reason);
        }
        self.unwind = null;
        self.unwind_actual_pending = false;
        self.unwind_generic_fatal = false;
        cleanup.captureEntry(null);
        for (self.values.items) |value| cleanup.release(value);
        self.values.deinit(self.engine.gpa);
        cleanup.collect();
        cleanup.publish();
    }
    pub fn own(self: *Scope, raw: c.JSValue) !c.JSValue {
        const value = try current(self.engine, raw);
        self.values.append(self.engine.gpa, value) catch |err| {
            if (err == error.OutOfMemory) _ = self.engine.throwNativeOutOfMemoryFatal();
            var cleanup: Cleanup = .{ .engine = self.engine };
            cleanup.captureEntry(null);
            cleanup.release(value);
            cleanup.publish();
            return err;
        };
        return value;
    }

    pub fn get(self: *Scope, object: c.JSValue, name: [*:0]const u8) !c.JSValue { try pending(self.engine); const generation = self.engine.native_allocation_generation; return self.own(try checkedSince(self.engine, c.JS_GetPropertyStr(self.engine.context, object, name), generation)); }
    pub fn global(self: *Scope, name: [*:0]const u8) !c.JSValue { try pending(self.engine); const object = c.JS_GetGlobalObject(self.engine.context); defer self.engine.freeValue(object); return self.get(object, name); }
    pub fn call(self: *Scope, function: c.JSValue, receiver: c.JSValue, args: []const c.JSValue) !c.JSValue { try pending(self.engine); const generation = self.engine.native_allocation_generation; return self.own(try checkedSince(self.engine, c.JS_Call(self.engine.context, function, receiver, @intCast(args.len), @constCast(args.ptr)), generation)); }

    pub fn object(self: *Scope) !c.JSValue { try pending(self.engine); return self.own(try checked(self.engine, c.JS_NewObject(self.engine.context))); }
    pub fn array(self: *Scope) !c.JSValue { try pending(self.engine); return self.own(try checked(self.engine, c.JS_NewArray(self.engine.context))); }
    pub fn text(self: *Scope, value: []const u8) !c.JSValue { try pending(self.engine); return self.own(try checked(self.engine, c.JS_NewStringLen(self.engine.context, value.ptr, value.len))); }
    pub fn put(self: *Scope, object: c.JSValue, name: [*:0]const u8, value: c.JSValue) !void { try pending(self.engine); const generation = self.engine.native_allocation_generation; const result = c.JS_DefinePropertyValueStr(self.engine.context, object, name, c.JS_DupValue(self.engine.context, value), c.JS_PROP_C_W_E); try statusSince(self.engine, result < 0, generation); }
    pub fn set(self: *Scope, object: c.JSValue, name: [*:0]const u8, value: c.JSValue) !void { try pending(self.engine); const generation = self.engine.native_allocation_generation; const result = c.JS_SetPropertyStr(self.engine.context, object, name, c.JS_DupValue(self.engine.context, value)); try statusSince(self.engine, result < 0, generation); }
    pub fn index(self: *Scope, object: c.JSValue, index_value: u32, value: c.JSValue) !void { try pending(self.engine); const generation = self.engine.native_allocation_generation; const result = c.JS_DefinePropertyValueUint32(self.engine.context, object, index_value, c.JS_DupValue(self.engine.context, value), c.JS_PROP_C_W_E); try statusSince(self.engine, result < 0, generation); }

    pub fn concat(self: *Scope, left: c.JSValue, right: c.JSValue) !c.JSValue { try pending(self.engine); const generation = self.engine.native_allocation_generation; return self.own(try checkedSince(self.engine, c.JS_PiBinaryOperator(self.engine.context, 0, left, right), generation)); }
    pub fn stringify(self: *Scope, value: c.JSValue) !c.JSValue { try pending(self.engine); const generation = self.engine.native_allocation_generation; return self.own(try checkedSince(self.engine, c.JS_ToString(self.engine.context, value), generation)); }
    pub fn truthy(self: *Scope, value: c.JSValue) bool { return c.JS_ToBool(self.engine.context, value) == 1; }
    pub fn equal(self: *Scope, left: c.JSValue, right: c.JSValue) bool { return c.JS_IsStrictEqual(self.engine.context, left, right); }
    pub fn positive(self: *Scope, value: c.JSValue) !bool { try pending(self.engine); const generation = self.engine.native_allocation_generation; const result = try self.own(try checkedSince(self.engine, c.JS_PiBinaryOperator(self.engine.context, 6, value, c.JS_NewInt32(self.engine.context, 0)), generation)); return self.truthy(result); }

};
fn takeCaptured(engine: *em.Engine) ?c.JSValue { const previous = engine.captured_exception; engine.captured_exception = null; return previous; }
/// An actual event carries its cached generic policy. Diagnostic DATA never
/// establishes that policy; the private control event uses its live C priority.
const Reason = struct {
    value: c.JSValue,
    generic_fatal: bool = false,
    actual_pending: bool = true,
    fn isFatal(self: Reason, engine: *em.Engine) bool {
        return self.actual_pending and (if (c.JS_PiIsExecutionTermination(self.value))
            c.JS_PiNativePendingPriority(engine.runtime, self.value) > 0 else self.generic_fatal);
    }
};
const Cleanup = struct {
    engine: *em.Engine,
    /// Only one actual root retirement may supply a freshness boundary.
    generation: ?u64 = null,
    selected: ?Reason = null,
    diagnostic: ?c.JSValue = null,
    fn fatal(self: *Cleanup, value: c.JSValue, generic_fatal: bool) bool {
        if (c.JS_PiIsExecutionTermination(value)) return false;
        const tag = c.pi_js_native_allocation_error_generation(value);
        const fresh = if (self.generation) |start| current: {
            const distance = tag -% start;
            break :current tag != 0 and distance != 0 and
                distance <= self.engine.native_allocation_generation -% start;
        } else false;
        // This is a taken ACTUAL event born during one native free. Captured
        // diagnostics and guest-operation spans never reach this classifier.
        if (fresh and c.JS_IsError(value)) c.JS_SetUncatchableError(self.engine.context, value);
        return generic_fatal or fresh;
    }
    fn rememberProducer(self: *Cleanup, reason: Reason) void {
        const invocation = self.engine.native_fatal_invocation orelse return;
        if (invocation.first) |first| {
            if (!c.JS_PiIsExecutionTermination(first) or
                c.JS_PiNativePendingPriority(self.engine.runtime, first) > 0) return;
        }
        // Retain only this ACTUAL producer before any discarded owner retires.
        _ = c.JS_PiThrowNativePending(self.engine.context,
            c.JS_DupValue(self.engine.context, reason.value), reason.generic_fatal);
        _ = self.engine.nativeCallbackResult(c.pi_js_undefined());
        // This duplicate is intentionally retired as DATA, not transferred.
        self.generation = self.engine.native_allocation_generation;
        self.engine.freeValue(c.JS_GetException(self.engine.context));
        self.generation = self.engine.native_allocation_generation;
    }
    fn select(self: *Cleanup, next: Reason) ?c.JSValue {
        if (next.isFatal(self.engine)) self.rememberProducer(next);
        if (self.selected) |prior| {
            const replace = if (prior.actual_pending and next.actual_pending)
                c.JS_PiNativePendingReplaceClassified(self.engine.runtime,
                    prior.value, prior.generic_fatal, next.value, next.generic_fatal)
            else if (!prior.actual_pending) next.isFatal(self.engine)
            else c.JS_PiIsExecutionTermination(prior.value) and
                c.JS_PiNativePendingPriority(self.engine.runtime, prior.value) < 0;
            if (replace) { self.selected = next; return prior.value; }
            return next.value;
        }
        self.selected = next;
        return null;
    }
    fn event(self: *Cleanup, owned: c.JSValue, generic_fatal: bool) void {
        if (self.select(.{ .value = owned, .generic_fatal = generic_fatal })) |old| self.retire(old);
    }
    fn escaping(self: *Cleanup, owned: c.JSValue) void {
        if (self.select(.{ .value = owned, .actual_pending = false })) |old| self.retire(old);
    }
    fn history(self: *Cleanup, owned: c.JSValue) void {
        if (self.diagnostic) |old| { self.diagnostic = owned; self.retire(old); }
        else self.diagnostic = owned;
    }
    fn restorePrior(self: *Cleanup, prior: ?c.JSValue) void {
        if (prior) |old| {
            if (self.diagnostic != null) self.release(old) else self.history(old);
        }
    }
    fn retire(self: *Cleanup, owned: c.JSValue) void {
        self.generation = self.engine.native_allocation_generation;
        self.engine.freeValue(owned);
        self.collect();
        self.generation = self.engine.native_allocation_generation;
    }
    fn collect(self: *Cleanup) void {
        while (true) {
            // Re-surfacing the same independently retained fatal repeatedly
            // would loop. Once selected, that event remains externally owned.
            if (self.selected == null or !self.selected.?.isFatal(self.engine))
                _ = self.engine.nativeCallbackResult(c.pi_js_undefined());
            if (!c.JS_HasException(self.engine.context) and self.engine.captured_exception == null) return;
            var generic_fatal: bool = false;
            const event_value: ?c.JSValue = if (c.JS_HasException(self.engine.context))
                c.JS_PiGetExceptionWithFatal(self.engine.context, &generic_fatal) else null;
            const captured = takeCaptured(self.engine);
            // Take BOTH slots before releasing any displaced native owner.
            const discarded = if (event_value) |value|
                self.select(.{ .value = value, .generic_fatal = self.fatal(value, generic_fatal) }) else null;
            if (captured) |value| self.history(value);
            if (discarded) |old| self.retire(old);
        }
    }
    fn captureEntry(self: *Cleanup, err: ?anyerror) void {
        _ = self.engine.nativeCallbackResult(c.pi_js_undefined());
        if (err) |actual| {
            if (actual == error.OutOfMemory) _ = self.engine.throwNativeOutOfMemoryFatal();
        }
        var generic_fatal: bool = false;
        const event_value: ?c.JSValue = if (c.JS_HasException(self.engine.context))
            c.JS_PiGetExceptionWithFatal(self.engine.context, &generic_fatal) else null;
        const captured = takeCaptured(self.engine);
        if (event_value) |value| self.event(value, generic_fatal);
        if (captured) |value| {
            if (err) |actual| {
                if (actual == error.JavaScriptException and event_value == null and self.selected == null)
                    self.escaping(value)
                else self.history(value);
            } else self.history(value);
        }
        self.collect();
    }
    fn release(self: *Cleanup, owned: c.JSValue) void {
        self.captureEntry(null);
        self.retire(owned);
    }
    fn retireDiagnostics(self: *Cleanup) void {
        if (self.selected != null) {
            while (self.diagnostic) |old| {
                self.diagnostic = null;
                self.retire(old);
            }
        }
    }
    fn publish(self: *Cleanup) void {
        self.retireDiagnostics();
        if (self.selected) |reason| {
            self.selected = null;
            if (reason.actual_pending)
                _ = c.JS_PiThrowNativePending(self.engine.context, reason.value, reason.generic_fatal)
            else
                _ = c.JS_PiThrowExceptionData(self.engine.context, reason.value);
        } else if (self.diagnostic) |history_value| {
            self.diagnostic = null;
            self.engine.captured_exception = history_value;
        }
    }
};
pub fn current(engine: *em.Engine, owned: c.JSValue) !c.JSValue {
    _ = engine.nativeCallbackResult(c.pi_js_undefined());
    if (!c.JS_HasException(engine.context) and !engine.nativeTerminationObserved()) return owned;
    var cleanup: Cleanup = .{ .engine = engine };
    cleanup.captureEntry(null);
    cleanup.release(owned);
    cleanup.publish();
    if (engine.nativeTerminationObserved()) return error.ExecutionTerminated;
    return error.JavaScriptException;
}
/// Existing callers surround getters, calls and coercions with this argument.
/// It is compatibility data, never evidence of a non-guest allocation producer.
pub fn currentSince(engine: *em.Engine, owned: c.JSValue, _: u64) !c.JSValue {
    return current(engine, owned);
}
pub fn pending(engine: *em.Engine) !void {
    try @import("native_pending_owner.zig").checkFatal(engine);
    if (c.JS_HasException(engine.context)) return error.JavaScriptException;
}
pub fn checked(engine: *em.Engine, raw: c.JSValue) !c.JSValue {
    const value = try current(engine, raw);
    if (c.JS_IsException(value)) return error.SqliteCallbackExceptionWithoutCurrentReason;
    return value;
}
pub fn checkedSince(engine: *em.Engine, raw: c.JSValue, _: u64) !c.JSValue {
    return checked(engine, raw);
}
pub fn status(engine: *em.Engine, failed: bool) !void {
    try pending(engine);
    if (failed) return error.SqliteCallbackExceptionWithoutCurrentReason;
}
pub fn statusSince(engine: *em.Engine, failed: bool, _: u64) !void {
    return status(engine, failed);
}
pub const af = @import("native_async_function.zig");
const js = @import("native_js_values.zig");
fn currentError(engine: *em.Engine, err: anyerror) anyerror {
    if (err == error.OutOfMemory) {
        _ = engine.throwNativeOutOfMemoryFatal();
        return err;
    }
    // The real host unwind survives cancellation or later ordinary cleanup.
    if (err == error.ExecutionTerminated) return err;
    _ = engine.nativeCallbackResult(c.pi_js_undefined());
    if (engine.nativeTerminationObserved()) return error.ExecutionTerminated;
    if (c.JS_HasException(engine.context)) return error.JavaScriptException;
    return err;
}
pub fn guard(engine: *em.Engine, _: u64, value: anyerror!c.JSValue) !c.JSValue {
    const owned = value catch |err| return currentError(engine, err);
    return current(engine, owned);
}
pub fn get(s: *Scope, receiver: c.JSValue, key: [*:0]const u8) !c.JSValue { const generation = s.engine.native_allocation_generation; return guard(s.engine, generation, s.get(receiver, key)); }
pub fn call(s: *Scope, function: c.JSValue, receiver: c.JSValue, args: []const c.JSValue) !c.JSValue { const generation = s.engine.native_allocation_generation; return guard(s.engine, generation, s.call(function, receiver, args)); }
pub fn invoke(s: *Scope, receiver: c.JSValue, key: [*:0]const u8, args: []const c.JSValue) !c.JSValue { return call(s, try get(s, receiver, key), receiver, args); }
pub fn global(s: *Scope, key: [*:0]const u8) !c.JSValue { const generation = s.engine.native_allocation_generation; return guard(s.engine, generation, s.global(key)); }
/// Actual GetPrototypeFromConstructor fallback does not consult global Object.
pub fn objectFor(s: *Scope, target: c.JSValue) !c.JSValue {
    const proto = try get(s, target, "prototype");
    return s.own(try checked(s.engine, if (c.JS_IsObject(proto)) c.JS_NewObjectProto(s.engine.context, proto) else c.JS_NewObject(s.engine.context)));
}
pub fn objectPrototype(s: *Scope) !c.JSValue {
    const object = try s.object();
    return s.own(try checked(s.engine, c.JS_GetPrototype(s.engine.context, object)));
}
pub fn construct(s: *Scope, function: c.JSValue, args: []const c.JSValue) !c.JSValue {
    try pending(s.engine);
    const generation = s.engine.native_allocation_generation;
    return s.own(try guard(s.engine, generation, checkedSince(s.engine, c.JS_CallConstructor(s.engine.context, function, @intCast(args.len), @constCast(args.ptr)), generation)));
}
pub fn set(s: *Scope, object: c.JSValue, key: [*:0]const u8, value: c.JSValue) !void {
    const generation = s.engine.native_allocation_generation;
    s.set(object, key, value) catch |err| { _ = try guard(s.engine, generation, @as(anyerror!c.JSValue, err)); };
}
pub fn caught(engine: *em.Engine, err: anyerror) !c.JSValue {
    const actual = currentError(engine, err);
    if (actual == error.OutOfMemory or actual == error.ExecutionTerminated) return actual;
    var cleanup: Cleanup = .{ .engine = engine };
    cleanup.captureEntry(if (actual == error.JavaScriptException) actual else null);
    cleanup.retireDiagnostics();
    if (engine.nativeTerminationObserved()) {
        cleanup.publish();
        return error.ExecutionTerminated;
    }
    if (cleanup.selected) |reason| {
        // Only an ACTUAL slot owner establishes fatal policy. A flagged Error
        // captured as DATA is ordinary. Private-token DATA is forbidden and
        // publish() reports that misuse through the ordinary DATA API policy.
        if ((reason.actual_pending and reason.generic_fatal) or
            c.JS_PiIsExecutionTermination(reason.value))
        {
            cleanup.publish();
            return error.JavaScriptException;
        }
        cleanup.selected = null;
        cleanup.publish();
        return reason.value;
    }
    cleanup.publish();
    return js.typeError(engine, "Unexpected native Chord SQLite failure");
}
pub fn failure(engine: *em.Engine, err: anyerror) !af.Action { return .{ .thrown = try caught(engine, err) }; }
pub fn init(s: *Scope, state: *c.JSValue) !c.JSValue {
    try pending(s.engine);
    const owner = try s.own(try checked(s.engine, c.JS_NewObjectProto(s.engine.context, c.pi_js_null())));
    af.replaceState(s.engine, state, c.JS_DupValue(s.engine.context, owner));
    return owner;
}
pub fn wait(s: *Scope, owner: c.JSValue, function: c.JSValue, receiver: c.JSValue, args: []const c.JSValue, stage: i32) !af.Action {
    try s.put(owner, "stage", c.JS_NewInt32(s.engine.context, stage));
    return .{ .awaited = c.JS_DupValue(s.engine.context, try call(s, function, receiver, args)) };
}
pub fn stage(s: *Scope, owner: c.JSValue) !i32 { var n: i32 = 0; if (c.JS_ToInt32(s.engine.context, &n, try s.get(owner, "stage")) < 0) return js.capture(s.engine); return n; }
pub fn rejected(s: *Scope, _: c.JSValue, _: c.JSValue) !void { try pending(s.engine); }
pub fn at(args: []const c.JSValue, index: usize) c.JSValue { return if (index < args.len) args[index] else c.pi_js_undefined(); }
pub fn nullish(value: c.JSValue) bool { return c.JS_IsNull(value) or c.JS_IsUndefined(value); }
/// Only the new adapter's actual native callback boundary. Never classify DATA
/// or change shared callback policy. Promise reactions may otherwise consume a
/// direct host allocator exception before an outer native AF sees its origin.
pub fn callback(comptime operation: @import("native_node_function.zig").Callback) @import("native_node_function.zig").Callback {
    const Adapter = struct {
        fn call(engine: *em.Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
            var frame = @import("native_pending_owner.zig").Frame.init(engine);
            frame.enter() catch |err| return frame.finishValue(err);
            return frame.finishValue(run(engine, receiver, args, roots));
        }
        fn run(engine: *em.Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
            const prior = takeCaptured(engine);
            const result = operation(engine, receiver, args, roots) catch |err| {
                var cleanup: Cleanup = .{ .engine = engine };
                cleanup.captureEntry(err);
                const current_reason = cleanup.selected != null;
                cleanup.restorePrior(prior);
                cleanup.collect();
                const selected = cleanup.selected != null;
                cleanup.publish();
                if (err == error.OutOfMemory or err == error.ExecutionTerminated) return err;
                if (selected) return error.JavaScriptException;
                if (err == error.JavaScriptException and !current_reason)
                    return error.SqliteCallbackExceptionWithoutCurrentReason;
                return err;
            };
            var cleanup: Cleanup = .{ .engine = engine };
            cleanup.captureEntry(null);
            cleanup.restorePrior(prior);
            cleanup.collect();
            if (cleanup.selected != null) {
                cleanup.release(result);
                cleanup.publish();
                return error.JavaScriptException;
            }
            cleanup.publish();
            return result;
        }
    };
    return Adapter.call;
}
