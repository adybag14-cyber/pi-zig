//! Actual Pi8efd utils/management-http.ts. Management requests only: this is
//! neither model retry nor an SDK/fetch substitute. Every Await uses real AF.
const em = @import("engine.zig");
const p = @import("native_agent_af_values.zig");
const js = @import("native_js_values.zig");
const math = @import("native_image_arithmetic.zig");
const functions = @import("native_node_function.zig");
const owned = @import("native_sdk_owned_completion.zig");
const guest = @import("native_sdk_guest_operation.zig");
const Scope = p.Scope;
const c = em.c;
const Stage = enum(i32) { attempt, fetch, cancel };
const Decision = union(enum) { again, action: p.af.Action };
const key = "pi-private:sdk-management-http";

fn put(s: *Scope, target: c.JSValue, name: [*:0]const u8, value: c.JSValue) !void {
    return guest.put(s, target, name, value);
}
fn argument(args: []const c.JSValue, index: usize) c.JSValue { return if (index < args.len) args[index] else c.pi_js_undefined(); }
fn isUndefined(value: c.JSValue) bool { return c.JS_IsUndefined(value); }
fn nullish(value: c.JSValue) bool { return isUndefined(value) or c.JS_IsNull(value); }
fn binding(s: *Scope, name: [:0]const u8) !c.JSValue {
    const global = try s.own(c.JS_GetGlobalObject(s.engine.context));
    const atom = c.JS_NewAtom(s.engine.context, name.ptr);
    if (atom == c.JS_ATOM_NULL) return js.capture(s.engine);
    defer c.JS_FreeAtom(s.engine.context, atom);
    var boundary: guest.Boundary = .{ .engine = s.engine }; try boundary.begin();
    const present = c.JS_HasProperty(s.engine.context, global, atom);
    try boundary.finishStatus(present);
    if (present == 0) return s.engine.checked(c.JS_ThrowReferenceError(s.engine.context, "%s is not defined", name.ptr));
    return p.get(s, global, name.ptr);
}
fn compare(s: *Scope, operation: math.Operation, left: c.JSValue, right: c.JSValue) !bool {
    return s.truthy(try guest.binary(s, @intFromEnum(operation), left, right));
}
fn at(s: *Scope, value: c.JSValue, index: u32) !c.JSValue {
    return guest.at(s, value, index);
}
fn optional(s: *Scope, value: c.JSValue, name: [*:0]const u8) !c.JSValue { return if (nullish(value)) c.pi_js_undefined() else p.get(s, value, name); }
fn stage(s: *Scope, job: c.JSValue, value: Stage) !void { try put(s, job, "stage", c.JS_NewInt32(s.engine.context, @intFromEnum(value))); }

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
        const failure_value = @import("native_sdk.zig").fail(engine, err);
        return engine.checked(engine.leaveNativeInvocation(&invocation, failure_value));
    };
    engine.checkNativeEntry() catch |err| {
        const failure_value = @import("native_sdk.zig").fail(engine, err);
        engine.freeValue(result);
        return engine.checked(engine.leaveNativeInvocation(&invocation, failure_value));
    };
    const retained = c.JS_DupValue(engine.context, result);
    engine.native_module_values.put(engine.gpa, key, retained) catch |err| {
        const failure_value = @import("native_sdk.zig").fail(engine, err);
        engine.freeValue(retained);
        engine.freeValue(result);
        return engine.checked(engine.leaveNativeInvocation(&invocation, failure_value));
    };
    return engine.checked(engine.leaveNativeInvocation(&invocation, result));
}
fn initialize(engine: *em.Engine) !c.JSValue {
    var s: Scope = .{ .engine = engine };
    return owned.finishValue(&s, initializeBody(&s));
}
fn initializeBody(s: *Scope) !c.JSValue {
    const engine = s.engine;
    const constructor = try binding(s, "Set");
    const statuses = try s.array();
    inline for (.{ 408, 425, 429, 500, 502, 503, 504 }, 0..) |code, index| try s.index(statuses, index, c.JS_NewInt32(engine.context, code));
    const retryable = try guest.construct(s, constructor, &.{statuses});
    const result = try s.object();
    const function = try s.own(try p.af.createResumable(engine, "fetchWithRetry", 1, run, &.{retryable}));
    try put(s, result, "fetchWithRetry", function);
    return c.JS_DupValue(engine.context, result);
}
// Source condition/call temporaries are retired at their expression boundary,
// before a later live getter can observe GC/native-holder lifetime.
fn definedBody(s: *Scope, object: c.JSValue, name: [*:0]const u8) !c.JSValue {
    return c.pi_js_bool(s.engine.context, @intFromBool(!isUndefined(try p.get(s, object, name))));
}
fn defined(engine: *em.Engine, object: c.JSValue, name: [*:0]const u8) !bool {
    var s: Scope = .{ .engine = engine };
    const result = try owned.finishValue(&s, definedBody(&s, object, name));
    defer engine.freeValue(result);
    return c.JS_ToBool(engine.context, result) == 1;
}
fn finiteBody(s: *Scope, options: c.JSValue) !c.JSValue {
    const number = try binding(s, "Number");
    const callable = try p.get(s, number, "isFinite");
    const value = try p.call(s, callable, number, &.{try p.get(s, options, "maxRetries")});
    return c.pi_js_bool(s.engine.context, @intFromBool(s.truthy(value)));
}
fn finite(engine: *em.Engine, options: c.JSValue) !bool {
    var s: Scope = .{ .engine = engine };
    const result = try owned.finishValue(&s, finiteBody(&s, options));
    defer engine.freeValue(result);
    return c.JS_ToBool(engine.context, result) == 1;
}
fn floorBody(s: *Scope, options: c.JSValue) !c.JSValue {
    const math_object = try binding(s, "Math");
    const callable = try p.get(s, math_object, "floor");
    return c.JS_DupValue(s.engine.context, try p.call(s, callable, math_object, &.{try p.get(s, options, "maxRetries")}));
}
fn floorValue(engine: *em.Engine, options: c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine };
    return owned.finishValue(&s, floorBody(&s, options));
}
fn maximumBody(s: *Scope, options: c.JSValue) !c.JSValue {
    const math_object = try binding(s, "Math");
    const callable = try p.get(s, math_object, "max");
    const floored = try s.own(try floorValue(s.engine, options));
    return c.JS_DupValue(s.engine.context, try p.call(s, callable, math_object, &.{c.JS_NewInt32(s.engine.context, 0), floored}));
}
fn maximumRetries(engine: *em.Engine, options: c.JSValue) !c.JSValue {
    if (!try defined(engine, options, "maxRetries") or !try finite(engine, options)) return c.JS_NewInt32(engine.context, 2);
    var s: Scope = .{ .engine = engine };
    return owned.finishValue(&s, maximumBody(&s, options));
}
fn positiveBody(s: *Scope, options: c.JSValue, name: [*:0]const u8) !c.JSValue {
    return c.pi_js_bool(s.engine.context, @intFromBool(try compare(s, .greater, try p.get(s, options, name), c.JS_NewInt32(s.engine.context, 0))));
}
fn positiveOption(engine: *em.Engine, options: c.JSValue, name: [*:0]const u8) !bool {
    if (!try defined(engine, options, name)) return false;
    var s: Scope = .{ .engine = engine };
    const result = try owned.finishValue(&s, positiveBody(&s, options, name));
    defer engine.freeValue(result);
    return c.JS_ToBool(engine.context, result) == 1;
}
fn timeoutBody(s: *Scope, options: c.JSValue) !c.JSValue {
    const abort = try binding(s, "AbortSignal");
    const callable = try p.get(s, abort, "timeout");
    return c.JS_DupValue(s.engine.context, try p.call(s, callable, abort, &.{try p.get(s, options, "timeoutMs")}));
}
fn timeoutValue(engine: *em.Engine, options: c.JSValue) !c.JSValue {
    if (!try positiveOption(engine, options, "timeoutMs")) return c.pi_js_undefined();
    var s: Scope = .{ .engine = engine };
    return owned.finishValue(&s, timeoutBody(&s, options));
}
fn defaults(s: *Scope, state: *c.JSValue, args: []const c.JSValue) !c.JSValue {
    const job = try p.init(s, state);
    const options = if (isUndefined(argument(args, 2))) try s.object() else argument(args, 2);
    const initial = argument(args, 1);
    try put(s, job, "input", argument(args, 0));
    try put(s, job, "init", initial);
    try put(s, job, "options", options);
    const maximum = try s.own(try maximumRetries(s.engine, options));
    try put(s, job, "maxRetries", maximum);
    const retry = try p.get(s, options, "retryOnStatus");
    try put(s, job, "retryOnStatus", if (nullish(retry)) c.pi_js_bool(s.engine.context, 1) else retry);
    const parent = try optional(s, initial, "signal");
    try put(s, job, "parentSignal", if (nullish(parent)) c.pi_js_undefined() else parent);
    const timeout = try s.own(try timeoutValue(s.engine, options));
    try put(s, job, "timeoutSignal", timeout);
    const attempt_timeout = if (try positiveOption(s.engine, options, "attemptTimeoutMs")) try p.get(s, options, "attemptTimeoutMs") else c.pi_js_undefined();
    try put(s, job, "attemptTimeoutMs", attempt_timeout);
    try put(s, job, "attempt", c.JS_NewInt32(s.engine.context, 0));
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
    try put(s, job, "attemptTimeoutSignal", attempt_timeout);
    const values = try s.array();
    try s.index(values, 0, parent); try s.index(values, 1, timeout); try s.index(values, 2, attempt_timeout);
    const callable = try p.get(s, values, "filter");
    const predicate = try s.own(try functions.createArrow(s.engine, "", 1, filter, &.{}));
    const signals = try p.call(s, callable, values, &.{predicate});
    try put(s, job, "signals", signals);
    if (try compare(s, .greater, try p.get(s, signals, "length"), c.JS_NewInt32(s.engine.context, 1))) {
        const abort = try binding(s, "AbortSignal");
        const signal = try p.call(s, try p.get(s, abort, "any"), abort, &.{signals});
        try put(s, job, "signal", signal);
        return signal;
    }
    const signal = try at(s, signals, 0);
    try put(s, job, "signal", signal);
    return signal;
}
fn fetchValue(s: *Scope, job: c.JSValue, signal: c.JSValue) !c.JSValue {
    const fetch = try binding(s, "fetch");
    const input = try s.get(job, "input");
    const initial = try s.get(job, "init");
    var init = initial;
    if (s.truthy(signal)) {
        init = try spreadInit(s, initial);
        try put(s, init, "signal", signal);
    }
    return p.call(s, fetch, c.pi_js_undefined(), &.{ input, init });
}
fn copyDescriptorBody(s: *Scope, result: c.JSValue, boxed: c.JSValue, atom: c.JSAtom, descriptor: *const c.JSPropertyDescriptor) !void {
    try s.engine.checkNativeEntry();
    if (descriptor.flags & c.JS_PROP_ENUMERABLE == 0) return;
    const value = try guest.getAtom(s, boxed, atom);
    var boundary: guest.Boundary = .{ .engine = s.engine }; try boundary.begin();
    return boundary.finishStatus(c.JS_DefinePropertyValue(s.engine.context, result, atom, c.JS_DupValue(s.engine.context, value), c.JS_PROP_C_W_E));
}
fn copyDescriptor(s: *Scope, result: c.JSValue, boxed: c.JSValue, atom: c.JSAtom) !void {
    var descriptor: c.JSPropertyDescriptor = undefined;
    var boundary: guest.Boundary = .{ .engine = s.engine }; try boundary.begin();
    const found = c.JS_GetOwnProperty(s.engine.context, &descriptor, boxed, atom);
    const inspected = boundary.finishStatus(found);
    if (found <= 0) return inspected;
    // Capture the actual Get/copy outcome BEFORE descriptor field releases.
    // Neither caught DATA nor a new ordinary finalizer overwrites Source A.
    const outcome: anyerror!void = if (inspected) |_| copyDescriptorBody(s, result, boxed, atom, &descriptor) else |err| err;
    var completion = owned.Completion.initVoid(s.engine, outcome);
    // Preserve the previous three defers' actual LIFO native release order.
    completion.release(descriptor.setter);
    completion.release(descriptor.getter);
    completion.release(descriptor.value);
    return completion.finishVoid();
}
fn spreadInit(s: *Scope, initial: c.JSValue) !c.JSValue {
    const result = try s.object();
    if (nullish(initial)) return result;
    const boxed = try guest.toObject(s, initial);
    var names: [*c]c.JSPropertyEnum = null;
    var count: u32 = 0;
    var boundary: guest.Boundary = .{ .engine = s.engine }; try boundary.begin();
    const status = c.JS_GetOwnPropertyNames(s.engine.context, &names, &count, boxed, c.JS_GPN_STRING_MASK | c.JS_GPN_SYMBOL_MASK);
    const inspected = boundary.finishStatus(status);
    if (status < 0) { try inspected; unreachable; }
    defer c.JS_FreePropertyEnum(s.engine.context, names, count);
    try inspected;
    for (names[0..count]) |entry| {
        try copyDescriptor(s, result, boxed, entry.atom);
    }
    return result;
}
fn advance(s: *Scope, job: c.JSValue) !Decision {
    const previous = try s.get(job, "attempt");
    const next = try guest.increment(s, previous);
    try put(s, job, "attempt", next);
    inline for (.{ "response", "signal", "signals", "attemptTimeoutSignal" }) |name| try put(s, job, name, c.pi_js_undefined());
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
        var boundary: guest.Boundary = .{ .engine = s.engine }; try boundary.begin();
        const instance = c.JS_IsInstanceOf(s.engine.context, reason, error_constructor);
        try boundary.finishStatus(instance);
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
    try put(s, job, "response", response);
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
fn iterate(engine: *em.Engine, job: c.JSValue) anyerror!Decision {
    var s: Scope = .{ .engine = engine };
    const decision = begin(&s, job) catch |err| return .{ .action = try owned.finishAction(&s, err) };
    if (decision == .action) return .{ .action = try owned.finishAction(&s, decision.action) };
    const completion = try owned.finishAction(&s, .{ .returned = c.pi_js_undefined() });
    return switch (completion) {
        .returned => |value| blk: { engine.freeValue(value); break :blk .again; },
        else => .{ .action = completion },
    };
}
fn execute(engine: *em.Engine, args: []const c.JSValue, retryable: c.JSValue, state: *c.JSValue, completion: p.af.Completion, input: c.JSValue) anyerror!p.af.Action {
    var s: Scope = .{ .engine = engine };
    return owned.finishAction(&s, executeBody(&s, args, retryable, state, completion, input));
}
fn executeBody(s: *Scope, args: []const c.JSValue, retryable: c.JSValue, state: *c.JSValue, completion: p.af.Completion, input: c.JSValue) anyerror!p.af.Action {
    const engine = s.engine;
    if (completion == .rejected) try p.body.enterRejectedContinuation(engine);
    const job = if (completion == .start) try defaults(s, state, args) else state.*;
    if (completion != .start) {
        const previous: Stage = @enumFromInt(try p.stage(s, job));
        const decision = switch (previous) {
            .fetch => if (completion == .rejected) try failed(s, job, input) else try received(s, job, retryable, input),
            .cancel => try advance(s, job), // Ordinary rejected DATA is discarded.
            .attempt => return error.InvalidManagementHttpContinuation,
        };
        switch (decision) { .action => |action| return action, .again => {} }
    }
    var steps: usize = 0;
    while (true) {
        try tick(engine, &steps);
        switch (try iterate(engine, job)) { .action => |action| return action, .again => {} }
    }
}

test "SDK management HTTP consuming state replacement preserves first event before next field" {
    const std = @import("std");
    const Token = struct {
        const Emission = struct { engine: *em.Engine, reason: c.JSValue, calls: usize = 0 };
        fn finalize(_: ?*c.JSRuntime, value: c.JSValue) callconv(.c) void {
            const emission: *Emission = @ptrCast(@alignCast(c.JS_GetOpaque(value, c.JS_GetClassID(value)).?));
            emission.calls += 1;
            _ = c.JS_Throw(emission.engine.context, c.JS_DupValue(emission.engine.context, emission.reason));
        }
        fn create(emission: *Emission) !c.JSValue {
            var class: c.JSClassID = 0; _ = c.JS_NewClassID(emission.engine.runtime, &class);
            const definition: c.JSClassDef = .{ .class_name = "Actual management state retirement", .finalizer = finalize };
            if (c.JS_NewClass(emission.engine.runtime, class, &definition) < 0) return error.OutOfMemory;
            const result = try emission.engine.checked(c.JS_NewObjectClass(emission.engine.context, class));
            _ = c.JS_SetOpaque(result, emission);
            return result;
        }
    };
    const engine = try em.Engine.init(std.testing.allocator, .{}); defer engine.deinit();
    var outer: Scope = .{ .engine = engine }; defer outer.deinit();
    const first = try outer.own(try engine.checked(c.JS_NewError(engine.context)));
    const second = try outer.own(try engine.checked(c.JS_NewError(engine.context)));
    var response: Token.Emission = .{ .engine = engine, .reason = first };
    var signal: Token.Emission = .{ .engine = engine, .reason = second };
    var scope: Scope = .{ .engine = engine };
    const job = try scope.object();
    try scope.put(job, "attempt", c.JS_NewInt32(engine.context, 0));
    if (c.JS_DefinePropertyValueStr(engine.context, job, "response", try Token.create(&response), c.JS_PROP_C_W_E) < 0) return js.capture(engine);
    if (c.JS_DefinePropertyValueStr(engine.context, job, "signal", try Token.create(&signal), c.JS_PROP_C_W_E) < 0) return js.capture(engine);
    const outcome = advance(&scope, job);
    if (outcome) |_| return error.RequiredFirstConsumingEvent else |err| {
        try std.testing.expect(err == error.JavaScriptException);
        try std.testing.expectEqual(@as(usize, 1), response.calls);
        try std.testing.expectEqual(@as(usize, 0), signal.calls); // No next define.
        const action = try owned.finishAction(&scope, err);
        try std.testing.expect(action == .thrown);
        defer engine.freeValue(action.thrown);
        try std.testing.expect(c.JS_IsStrictEqual(engine.context, first, action.thrown));
        try std.testing.expectEqual(@as(usize, 1), signal.calls);
        try std.testing.expect(!c.JS_HasException(engine.context));
    }
}
