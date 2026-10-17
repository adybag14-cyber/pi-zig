//! Actual Pi8efd utils/management-http.ts. Management requests only: this is
//! neither model retry nor an SDK/fetch substitute. Every Await uses real AF.
const em = @import("engine.zig");
const p = @import("native_agent_af_values.zig");
const js = @import("native_js_values.zig");
const math = @import("native_image_arithmetic.zig");
const functions = @import("native_node_function.zig");
const Scope = p.Scope;
const c = em.c;
const Stage = enum(i32) { attempt, fetch, cancel };
const Decision = union(enum) { again, action: p.af.Action };
const key = "pi-private:sdk-management-http";

fn argument(args: []const c.JSValue, index: usize) c.JSValue { return if (index < args.len) args[index] else c.pi_js_undefined(); }
fn isUndefined(value: c.JSValue) bool { return c.JS_IsUndefined(value); }
fn nullish(value: c.JSValue) bool { return isUndefined(value) or c.JS_IsNull(value); }
fn binding(s: *Scope, name: [:0]const u8) !c.JSValue {
    const global = try s.own(c.JS_GetGlobalObject(s.engine.context));
    const atom = c.JS_NewAtom(s.engine.context, name.ptr);
    if (atom == c.JS_ATOM_NULL) return js.capture(s.engine);
    defer c.JS_FreeAtom(s.engine.context, atom);
    const generation = s.engine.native_allocation_generation;
    const present = c.JS_HasProperty(s.engine.context, global, atom);
    if (present < 0) return p.guard(s.engine, generation, js.capture(s.engine));
    try s.engine.checkNativeEntry();
    if (present == 0) return s.engine.checked(c.JS_ThrowReferenceError(s.engine.context, "%s is not defined", name.ptr));
    return p.get(s, global, name.ptr);
}
fn compare(s: *Scope, operation: math.Operation, left: c.JSValue, right: c.JSValue) !bool {
    const generation = s.engine.native_allocation_generation;
    return s.truthy(try s.own(try p.guard(s.engine, generation, math.binary(s.engine, operation, left, right))));
}
fn at(s: *Scope, value: c.JSValue, index: u32) !c.JSValue {
    const generation = s.engine.native_allocation_generation;
    return s.own(try p.guard(s.engine, generation, s.engine.checked(c.JS_GetPropertyUint32(s.engine.context, value, index))));
}
fn optional(s: *Scope, value: c.JSValue, name: [*:0]const u8) !c.JSValue { return if (nullish(value)) c.pi_js_undefined() else p.get(s, value, name); }
fn stage(s: *Scope, job: c.JSValue, value: Stage) !void { try s.put(job, "stage", c.JS_NewInt32(s.engine.context, @intFromEnum(value))); }

/// One actual module instance. The private Set is constructed at module
/// initialization and retained by the genuine AsyncFunction's GC roots.
pub fn create(engine: *em.Engine) !c.JSValue {
    try engine.checkNativeEntry();
    if (engine.native_module_values.get(key)) |cached| return c.JS_DupValue(engine.context, cached);
    var invocation: em.Engine.NativeInvocation = .{};
    engine.enterNativeInvocation(&invocation);
    engine.native_exception_diagnostics_suppressed += 1;
    defer engine.native_exception_diagnostics_suppressed -= 1;
    const result = initialize(engine) catch |err| {
        const failed = @import("native_sdk.zig").fail(engine, err);
        return engine.checked(engine.leaveNativeInvocation(&invocation, failed));
    };
    engine.checkNativeEntry() catch |err| {
        const failed = @import("native_sdk.zig").fail(engine, err);
        engine.freeValue(result);
        return engine.checked(engine.leaveNativeInvocation(&invocation, failed));
    };
    const retained = c.JS_DupValue(engine.context, result);
    engine.native_module_values.put(engine.gpa, key, retained) catch |err| {
        const failed = @import("native_sdk.zig").fail(engine, err);
        engine.freeValue(retained);
        engine.freeValue(result);
        return engine.checked(engine.leaveNativeInvocation(&invocation, failed));
    };
    return engine.checked(engine.leaveNativeInvocation(&invocation, result));
}
fn initialize(engine: *em.Engine) !c.JSValue {
    var s: Scope = .{ .engine = engine }; defer s.deinit();
    const constructor = try binding(&s, "Set");
    const statuses = try s.array();
    inline for (.{ 408, 425, 429, 500, 502, 503, 504 }, 0..) |code, index| try s.index(statuses, index, c.JS_NewInt32(engine.context, code));
    var args = [_]c.JSValue{statuses};
    const generation = engine.native_allocation_generation;
    const retryable = try s.own(try p.guard(engine, generation, engine.checked(c.JS_CallConstructor(engine.context, constructor, args.len, &args))));
    const result = try s.object();
    const function = try s.own(try p.af.createResumable(engine, "fetchWithRetry", 1, run, &.{retryable}));
    try s.put(result, "fetchWithRetry", function);
    return c.JS_DupValue(engine.context, result);
}
fn defaults(s: *Scope, state: *c.JSValue, args: []const c.JSValue) !c.JSValue {
    const job = try p.init(s, state);
    const options = if (isUndefined(argument(args, 2))) try s.object() else argument(args, 2);
    const initial = argument(args, 1);
    try s.put(job, "input", argument(args, 0));
    try s.put(job, "init", initial);
    const first = try p.get(s, options, "maxRetries");
    var maximum = c.JS_NewInt32(s.engine.context, 2);
    if (!isUndefined(first)) {
        const number = try binding(s, "Number");
        const finite = try p.get(s, number, "isFinite");
        const second = try p.get(s, options, "maxRetries");
        if (s.truthy(try p.call(s, finite, number, &.{second}))) {
            const outer_math = try binding(s, "Math");
            const max = try p.get(s, outer_math, "max");
            const inner_math = try binding(s, "Math");
            const floor = try p.get(s, inner_math, "floor");
            const third = try p.get(s, options, "maxRetries");
            maximum = try p.call(s, max, outer_math, &.{ c.JS_NewInt32(s.engine.context, 0), try p.call(s, floor, inner_math, &.{third}) });
        }
    }
    try s.put(job, "maxRetries", maximum);
    const retry = try p.get(s, options, "retryOnStatus");
    try s.put(job, "retryOnStatus", if (nullish(retry)) c.pi_js_bool(s.engine.context, 1) else retry);
    const parent = try optional(s, initial, "signal");
    try s.put(job, "parentSignal", if (nullish(parent)) c.pi_js_undefined() else parent);
    var timeout = c.pi_js_undefined();
    if (!isUndefined(try p.get(s, options, "timeoutMs")) and try compare(s, .greater, try p.get(s, options, "timeoutMs"), c.JS_NewInt32(s.engine.context, 0))) {
        const abort = try binding(s, "AbortSignal");
        const callable = try p.get(s, abort, "timeout");
        timeout = try p.call(s, callable, abort, &.{try p.get(s, options, "timeoutMs")});
    }
    try s.put(job, "timeoutSignal", timeout);
    const attempt_timeout = if (!isUndefined(try p.get(s, options, "attemptTimeoutMs")) and try compare(s, .greater, try p.get(s, options, "attemptTimeoutMs"), c.JS_NewInt32(s.engine.context, 0))) try p.get(s, options, "attemptTimeoutMs") else c.pi_js_undefined();
    try s.put(job, "attemptTimeoutMs", attempt_timeout);
    try s.put(job, "attempt", c.JS_NewInt32(s.engine.context, 0));
    try stage(s, job, .attempt);
    return job;
}
fn filter(engine: *em.Engine, _: c.JSValue, args: []const c.JSValue, _: []const c.JSValue) !c.JSValue { return c.pi_js_bool(engine.context, @intFromBool(!isUndefined(argument(args, 0)))); }
fn signalForAttempt(s: *Scope, job: c.JSValue) !c.JSValue {
    const parent = try s.get(job, "parentSignal");
    const timeout = try s.get(job, "timeoutSignal");
    if (!nullish(parent)) _ = try p.call(s, try p.get(s, parent, "throwIfAborted"), parent, &.{});
    if (!nullish(timeout)) _ = try p.call(s, try p.get(s, timeout, "throwIfAborted"), timeout, &.{});
    var attempt_timeout = c.pi_js_undefined();
    const period = try s.get(job, "attemptTimeoutMs");
    if (s.truthy(period)) {
        const abort = try binding(s, "AbortSignal");
        attempt_timeout = try p.call(s, try p.get(s, abort, "timeout"), abort, &.{period});
    }
    try s.put(job, "attemptTimeoutSignal", attempt_timeout);
    const values = try s.array();
    try s.index(values, 0, parent); try s.index(values, 1, timeout); try s.index(values, 2, attempt_timeout);
    const callable = try p.get(s, values, "filter");
    const predicate = try s.own(try functions.createArrow(s.engine, "", 1, filter, &.{}));
    const signals = try p.call(s, callable, values, &.{predicate});
    try s.put(job, "signals", signals);
    if (try compare(s, .greater, try p.get(s, signals, "length"), c.JS_NewInt32(s.engine.context, 1))) {
        const abort = try binding(s, "AbortSignal");
        const signal = try p.call(s, try p.get(s, abort, "any"), abort, &.{signals});
        try s.put(job, "signal", signal);
        return signal;
    }
    const signal = try at(s, signals, 0);
    try s.put(job, "signal", signal);
    return signal;
}
fn fetchValue(s: *Scope, job: c.JSValue, signal: c.JSValue) !c.JSValue {
    const fetch = try binding(s, "fetch");
    const input = try s.get(job, "input");
    const initial = try s.get(job, "init");
    var init = initial;
    if (s.truthy(signal)) {
        init = try spreadInit(s, initial);
        try s.put(init, "signal", signal);
    }
    return p.call(s, fetch, c.pi_js_undefined(), &.{ input, init });
}
fn captureSince(engine: *em.Engine, generation: u64) anyerror {
    _ = p.guard(engine, generation, js.capture(engine)) catch |err| return err;
    unreachable;
}
fn spreadInit(s: *Scope, initial: c.JSValue) !c.JSValue {
    const result = try s.object();
    if (nullish(initial)) return result;
    var generation = s.engine.native_allocation_generation;
    const boxed = try s.own(try p.guard(s.engine, generation, s.engine.checked(c.JS_ToObject(s.engine.context, initial))));
    var names: [*c]c.JSPropertyEnum = null;
    var count: u32 = 0;
    generation = s.engine.native_allocation_generation;
    if (c.JS_GetOwnPropertyNames(s.engine.context, &names, &count, boxed, c.JS_GPN_STRING_MASK | c.JS_GPN_SYMBOL_MASK) < 0) return captureSince(s.engine, generation);
    defer c.JS_FreePropertyEnum(s.engine.context, names, count);
    try s.engine.checkNativeEntry();
    for (names[0..count]) |entry| {
        var descriptor: c.JSPropertyDescriptor = undefined;
        generation = s.engine.native_allocation_generation;
        const found = c.JS_GetOwnProperty(s.engine.context, &descriptor, boxed, entry.atom);
        if (found < 0) return captureSince(s.engine, generation);
        if (found == 0) { try s.engine.checkNativeEntry(); continue; }
        defer s.engine.freeValue(descriptor.value);
        defer s.engine.freeValue(descriptor.getter);
        defer s.engine.freeValue(descriptor.setter);
        try s.engine.checkNativeEntry();
        if (descriptor.flags & c.JS_PROP_ENUMERABLE == 0) continue;
        generation = s.engine.native_allocation_generation;
        const value = try s.own(try p.guard(s.engine, generation, s.engine.checked(c.JS_GetProperty(s.engine.context, boxed, entry.atom))));
        generation = s.engine.native_allocation_generation;
        if (c.JS_DefinePropertyValue(s.engine.context, result, entry.atom, c.JS_DupValue(s.engine.context, value), c.JS_PROP_C_W_E) < 0) return captureSince(s.engine, generation);
        try s.engine.checkNativeEntry();
    }
    return result;
}
fn advance(s: *Scope, job: c.JSValue) !Decision {
    const previous = try s.get(job, "attempt");
    const generation = s.engine.native_allocation_generation;
    const next = try s.own(try p.guard(s.engine, generation, s.engine.checked(c.JS_PiIncrement(s.engine.context, previous))));
    try s.put(job, "attempt", next);
    inline for (.{ "response", "signal", "signals", "attemptTimeoutSignal" }) |name| try s.put(job, name, c.pi_js_undefined());
    try stage(s, job, .attempt);
    return .again;
}
fn failed(s: *Scope, job: c.JSValue, reason: c.JSValue) !Decision {
    const attempt_signal = try s.get(job, "attemptTimeoutSignal");
    const parent = try s.get(job, "parentSignal");
    const timeout = try s.get(job, "timeoutSignal");
    const timed_out = c.JS_IsStrictEqual(s.engine.context, try optional(s, attempt_signal, "aborted"), c.pi_js_bool(s.engine.context, 1)) and !s.truthy(try optional(s, parent, "aborted")) and !s.truthy(try optional(s, timeout, "aborted"));
    var terminal = s.truthy(try optional(s, parent, "aborted")) or s.truthy(try optional(s, timeout, "aborted"));
    if (!terminal) {
        const error_constructor = try binding(s, "Error");
        const generation = s.engine.native_allocation_generation;
        const instance = c.JS_IsInstanceOf(s.engine.context, reason, error_constructor);
        if (instance < 0) { _ = try p.guard(s.engine, generation, js.capture(s.engine)); unreachable; }
        try s.engine.checkNativeEntry();
        terminal = instance != 0 and s.equal(try p.get(s, reason, "name"), try s.text("AbortError")) and !timed_out and isUndefined(timeout);
    }
    if (!terminal) terminal = try compare(s, .greater_equal, try s.get(job, "attempt"), try s.get(job, "maxRetries"));
    if (terminal) return .{ .action = .{ .thrown = c.JS_DupValue(s.engine.context, reason) } };
    return advance(s, job);
}
fn cancelValue(s: *Scope, response: c.JSValue) !c.JSValue {
    const stream = try p.get(s, response, "body");
    return if (nullish(stream)) c.pi_js_undefined() else p.call(s, try p.get(s, stream, "cancel"), stream, &.{});
}
fn responseValue(s: *Scope, job: c.JSValue, retryable: c.JSValue, response: c.JSValue) !Decision {
    // These Source loop bindings remain traced through the body-cancel Await.
    try s.put(job, "response", response);
    var retry = s.truthy(try s.get(job, "retryOnStatus"));
    if (retry) {
        const has = try p.get(s, retryable, "has");
        retry = s.truthy(try p.call(s, has, retryable, &.{try p.get(s, response, "status")}));
    }
    if (retry) retry = try compare(s, .less, try s.get(job, "attempt"), try s.get(job, "maxRetries"));
    if (!retry) return .{ .action = .{ .returned = c.JS_DupValue(s.engine.context, response) } };
    const cancelled = cancelValue(s, response) catch |err| {
        const ignored = try p.caught(s.engine, err); s.engine.freeValue(ignored);
        return advance(s, job);
    };
    try stage(s, job, .cancel);
    return .{ .action = .{ .awaited = c.JS_DupValue(s.engine.context, cancelled) } };
}
fn received(s: *Scope, job: c.JSValue, retryable: c.JSValue, response: c.JSValue) !Decision {
    return responseValue(s, job, retryable, response) catch |err| {
        const reason = try s.own(try p.caught(s.engine, err));
        return failed(s, job, reason);
    };
}
fn begin(s: *Scope, job: c.JSValue) !Decision {
    const signal = try signalForAttempt(s, job); // Source boundary is OUTSIDE try.
    try stage(s, job, .fetch);
    const value = fetchValue(s, job, signal) catch |err| {
        const reason = try s.own(try p.caught(s.engine, err));
        return failed(s, job, reason);
    };
    return .{ .action = .{ .awaited = c.JS_DupValue(s.engine.context, value) } };
}
fn tick(engine: *em.Engine, steps: *usize) !void {
    steps.* +|= 1;
    if (engine.cancelled.load(.acquire) or (steps.* % 256 == 0 and blk: { engine.interrupts +|= 1; break :blk engine.interrupts > engine.options.interrupt_budget; })) {
        _ = c.JS_ThrowInternalError(engine.context, "interrupted");
        const reason = c.JS_GetException(engine.context); c.JS_SetUncatchableError(engine.context, reason);
        _ = try engine.checked(c.JS_Throw(engine.context, reason)); unreachable;
    }
}
fn run(engine: *em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue, state: *c.JSValue, completion: p.af.Completion, input: c.JSValue) !p.af.Action {
    try engine.checkNativeEntry();
    return execute(engine, args, roots[0], state, completion, input) catch |err| { return p.failure(engine, err); };
}
fn execute(engine: *em.Engine, args: []const c.JSValue, retryable: c.JSValue, state: *c.JSValue, completion: p.af.Completion, input: c.JSValue) !p.af.Action {
    var s: Scope = .{ .engine = engine }; defer s.deinit();
    if (completion == .rejected) try p.body.enterRejectedContinuation(engine);
    const job = if (completion == .start) try defaults(&s, state, args) else state.*;
    if (completion != .start) {
        const previous: Stage = @enumFromInt(try p.stage(&s, job));
        const decision = switch (previous) {
            .fetch => if (completion == .rejected) try failed(&s, job, input) else try received(&s, job, retryable, input),
            .cancel => try advance(&s, job), // Ordinary rejected DATA is discarded.
            .attempt => return error.InvalidManagementHttpContinuation,
        };
        switch (decision) { .action => |action| return action, .again => {} }
    }
    var steps: usize = 0;
    while (true) {
        try tick(engine, &steps);
        var iteration: Scope = .{ .engine = engine }; defer iteration.deinit();
        switch (try begin(&iteration, job)) { .action => |action| return action, .again => {} }
    }
}
