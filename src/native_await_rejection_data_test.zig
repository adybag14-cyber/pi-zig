//! Prepared real-VM regressions. No expected capture or observed result exists.
//! The flagged escaping-completion test deliberately exposes the separate C3
//! THROW-action frontier; it must not be skipped or reported as already passing.
const std = @import("std");
const em = @import("extensions/engine.zig");
const p = @import("extensions/native_agent_af_values.zig");
const body = @import("extensions/native_async_body.zig");
const af = body.native;
const c = em.c;
comptime { _ = @import("native_async_throw_cleanup_test.zig"); }

fn callOne(engine: *em.Engine, function: c.JSValue, argument: c.JSValue) !c.JSValue {
    var args = [_]c.JSValue{argument};
    return engine.checked(c.JS_Call(engine.context, function, c.pi_js_undefined(), args.len, &args));
}
fn drain(engine: *em.Engine, promise: c.JSValue) !void {
    var turns: usize = 0;
    while (c.JS_PromiseState(engine.context, promise) == c.JS_PROMISE_PENDING and turns < 32) : (turns += 1) {
        var context: ?*c.JSContext = null;
        if (c.JS_ExecutePendingJob(engine.runtime, &context) <= 0) return error.RejectedDataDidNotComplete;
    }
    try std.testing.expect(c.JS_PromiseState(engine.context, promise) != c.JS_PROMISE_PENDING);
}
fn privateReason(engine: *em.Engine) c.JSValue {
    // DATA authority fixture only: exercise the real private tag transport, not
    // a forged property. The allocator-failure test below uses a real failure.
    _ = engine.throwNativeOutOfMemory();
    return c.JS_GetException(engine.context);
}
fn caughtInput(engine: *em.Engine, _: c.JSValue, args: []const c.JSValue, _: []const c.JSValue, _: *c.JSValue, completion: af.Completion, input: c.JSValue) !af.Action {
    if (completion == .start) return .{ .awaited = c.JS_DupValue(engine.context, args[0]) };
    var scope: p.Scope = .{ .engine = engine }; defer scope.deinit();
    if (completion == .rejected) try p.rejected(&scope, c.pi_js_undefined(), input);
    // Models an ordinary Source catch consuming its reason. No flag clearing.
    return .{ .returned = c.JS_DupValue(engine.context, input) };
}
fn escapedInput(engine: *em.Engine, _: c.JSValue, args: []const c.JSValue, _: []const c.JSValue, _: *c.JSValue, completion: af.Completion, input: c.JSValue) !af.Action {
    if (completion == .start) return .{ .awaited = c.JS_DupValue(engine.context, args[0]) };
    try body.enterRejectedContinuation(engine);
    return .{ .thrown = c.JS_DupValue(engine.context, input) };
}

test "native Await DATA old flags private tags and captured history enter catch unchanged" {
    for ([_]bool{ false, true }) |private| {
        const engine = try em.Engine.init(std.testing.allocator, .{}); defer engine.deinit();
        var scope: p.Scope = .{ .engine = engine }; defer scope.deinit();
        const reason = try scope.own(if (private) privateReason(engine) else try engine.checked(c.JS_NewError(engine.context)));
        c.JS_SetUncatchableError(engine.context, reason);
        try std.testing.expect(c.JS_IsUncatchableError(reason));
        if (!private) try std.testing.expectEqual(@as(u64, 0), c.pi_js_native_allocation_error_generation(reason));
        // A retained diagnostic value is not an actual current exception.
        engine.captured_exception = c.JS_DupValue(engine.context, reason);
        const function = try scope.own(try af.createResumable(engine, "catchData", 1, caughtInput, &.{}));
        const rejected = try scope.own(try engine.checked(c.JS_NewSettledPromise(engine.context, true, reason)));
        const pending = try scope.own(try callOne(engine, function, rejected));
        c.JS_RunGC(engine.runtime);
        try drain(engine, pending);
        try std.testing.expectEqual(c.JS_PROMISE_FULFILLED, c.JS_PromiseState(engine.context, pending));
        const result = try scope.own(c.JS_PromiseResult(engine.context, pending));
        try std.testing.expect(c.JS_IsStrictEqual(engine.context, reason, result));
        try std.testing.expect(c.JS_IsUncatchableError(reason));
        try std.testing.expect(!c.JS_HasException(engine.context));
    }
}

test "native Await DATA fresh private reason created after actual suspension remains data across wrap" {
    for ([_]u64{ 0, std.math.maxInt(u64) }) |generation| {
        const engine = try em.Engine.init(std.testing.allocator, .{}); defer engine.deinit();
        var scope: p.Scope = .{ .engine = engine }; defer scope.deinit();
        engine.native_allocation_generation = generation;
        var resolving: [2]c.JSValue = undefined;
        const input = try scope.own(try engine.checked(c.JS_NewPromiseCapability(engine.context, &resolving)));
        defer for (resolving) |value| engine.freeValue(value);
        const function = try scope.own(try af.createResumable(engine, "catchFreshData", 1, caughtInput, &.{}));
        const pending = try scope.own(try callOne(engine, function, input));
        try std.testing.expectEqual(c.JS_PROMISE_PENDING, c.JS_PromiseState(engine.context, pending));
        const reason = try scope.own(privateReason(engine));
        const tag = c.pi_js_native_allocation_error_generation(reason);
        try std.testing.expect(tag != 0 and !c.JS_IsUncatchableError(reason));
        _ = try scope.call(resolving[1], c.pi_js_undefined(), &.{reason});
        try drain(engine, pending);
        try std.testing.expectEqual(c.JS_PROMISE_FULFILLED, c.JS_PromiseState(engine.context, pending));
        const actual = try scope.own(c.JS_PromiseResult(engine.context, pending));
        try std.testing.expect(c.JS_IsStrictEqual(engine.context, actual, reason));
        try std.testing.expectEqual(tag, c.pi_js_native_allocation_error_generation(actual));
        try std.testing.expect(!c.JS_IsUncatchableError(actual));
    }
}

test "native Await DATA actual Agent lifecycle executes catch handler and finally for flagged rejection" {
    const engine = try em.Engine.init(std.testing.allocator, .{}); defer engine.deinit();
    try @import("extensions/abort_signal.zig").install(engine);
    var scope: p.Scope = .{ .engine = engine }; defer scope.deinit();
    const global = try scope.own(c.JS_GetGlobalObject(engine.context));
    const reason = try scope.own(privateReason(engine));
    c.JS_SetUncatchableError(engine.context, reason);
    try scope.put(global, "ownedRejectedReason", reason);
    const fixture = try scope.own(try engine.eval(
        \\({agent:{_state:{},handleRunFailure(reason,aborted){if(reason!==ownedRejectedReason||aborted)throw Error('wrong catch');this.caught=reason;this.log.push('catch');},finishRun(){this.log.push('finally');},log:[]},executor(){return Promise.reject(ownedRejectedReason)}})
    , "actual-agent-lifecycle-data.js", c.JS_EVAL_TYPE_GLOBAL));
    const agent = try scope.get(fixture, "agent");
    const function = try scope.own(try @import("extensions/native_agent_lifecycle_async.zig").create(engine));
    const pending = try scope.call(function, agent, &.{try scope.get(fixture, "executor")});
    try drain(engine, pending);
    try std.testing.expectEqual(c.JS_PROMISE_FULFILLED, c.JS_PromiseState(engine.context, pending));
    try std.testing.expect(c.JS_IsStrictEqual(engine.context, reason, try scope.get(agent, "caught")));
    try std.testing.expect(scope.equal(try scope.invoke(try scope.get(agent, "log"), "join", &.{try scope.text(",")}), try scope.text("catch,finally")));
    try std.testing.expect(c.JS_IsUncatchableError(reason));
}

test "native Await DATA actual new throw of the same marked object preserves current event" {
    const engine = try em.Engine.init(std.testing.allocator, .{}); defer engine.deinit();
    const reason = try engine.checked(c.JS_NewError(engine.context)); defer engine.freeValue(reason);
    c.JS_SetUncatchableError(engine.context, reason);
    try body.enterRejectedContinuation(engine); // Same DATA, no pending event.
    _ = c.JS_Throw(engine.context, c.JS_DupValue(engine.context, reason));
    try std.testing.expectError(error.JavaScriptException, body.enterRejectedContinuation(engine));
    try std.testing.expect(c.JS_IsStrictEqual(engine.context, reason, engine.captured_exception.?));
    try std.testing.expectError(error.JavaScriptException, body.failure(engine, error.JavaScriptException));
    try std.testing.expect(c.JS_IsUncatchableError(reason));
}

const PendingCleanup = struct { context: ?*c.JSContext, reason: c.JSValue, calls: usize = 0 };
fn publishCleanupFatal(_: ?*c.JSRuntime, owner: c.JSValue) callconv(.c) void {
    const fixture: *PendingCleanup = @ptrCast(@alignCast(c.JS_GetOpaque(owner, c.JS_GetClassID(owner)).?));
    fixture.calls += 1;
    _ = c.JS_Throw(fixture.context, c.JS_DupValue(fixture.context, fixture.reason));
}
test "native Await DATA pending event remains owned while actual captured diagnostic finalizer publishes fatal" {
    for ([_]bool{ false, true }) |first_fatal| {
        const engine = try em.Engine.init(std.testing.allocator, .{}); defer engine.deinit();
        var scope: p.Scope = .{ .engine = engine }; defer scope.deinit();
        const original = try scope.own(try engine.checked(c.JS_NewError(engine.context)));
        const cleanup = try scope.own(try engine.checked(c.JS_NewError(engine.context)));
        if (first_fatal) c.JS_SetUncatchableError(engine.context, original);
        c.JS_SetUncatchableError(engine.context, cleanup);
        var fixture: PendingCleanup = .{ .context = engine.context, .reason = cleanup };
        var class: c.JSClassID = 0;
        _ = c.JS_NewClassID(engine.runtime, &class);
        const definition: c.JSClassDef = .{ .class_name = "Owned rejected diagnostic cleanup", .finalizer = publishCleanupFatal };
        try std.testing.expect(c.JS_NewClass(engine.runtime, class, &definition) >= 0);
        const diagnostic = try engine.checked(c.JS_NewObjectClass(engine.context, class));
        _ = c.JS_SetOpaque(diagnostic, &fixture);
        // Sole owned diagnostic reference: enterRejectedContinuation's release
        // really invokes its native finalizer rather than leaving a dormant hook.
        engine.captured_exception = diagnostic;
        _ = c.JS_Throw(engine.context, c.JS_DupValue(engine.context, original));
        try std.testing.expectError(error.JavaScriptException, body.enterRejectedContinuation(engine));
        try std.testing.expectEqual(@as(usize, 1), fixture.calls);
        try std.testing.expect(c.JS_IsStrictEqual(engine.context, engine.captured_exception.?, if (first_fatal) original else cleanup));
        try std.testing.expect(c.JS_IsUncatchableError(engine.captured_exception.?));
        try std.testing.expect(!c.JS_HasException(engine.context));
    }
}

test "native Await DATA actual prompt continue abort and wait methods preserve fresh rejection identity" {
    inline for (.{ "prompt", "continue", "abort", "waitForIdle" }) |name| {
        const engine = try em.Engine.init(std.testing.allocator, .{}); defer engine.deinit();
        var scope: p.Scope = .{ .engine = engine }; defer scope.deinit();
        const global = try scope.own(c.JS_GetGlobalObject(engine.context));
        var resolving: [2]c.JSValue = undefined;
        const input = try scope.own(try engine.checked(c.JS_NewPromiseCapability(engine.context, &resolving)));
        defer for (resolving) |value| engine.freeValue(value);
        try scope.put(global, "ownedPendingInput", input);
        const receiver = try scope.own(try engine.eval(
            \\({activeRun:undefined,_state:{messages:[{role:'user'}]},normalizePromptInput(){return[]},runPromptMessages(){return ownedPendingInput},runContinuation(){return ownedPendingInput},isIdle:false,_getIdleWaitPromise(){return ownedPendingInput},abortRetry(){},abortCompaction(){},abortBranchSummary(){},agent:{abort(){}},waitForIdle(){return ownedPendingInput}})
        , "actual-agent-session-rejected-data.js", c.JS_EVAL_TYPE_GLOBAL));
        const function = if (comptime std.mem.eql(u8, name, "prompt"))
            try scope.own(try @import("extensions/native_agent_prompt_async.zig").create(engine, .prompt))
        else if (comptime std.mem.eql(u8, name, "continue"))
            try scope.own(try @import("extensions/native_agent_prompt_async.zig").create(engine, .continue_run))
        else blk: {
            const prototype = try scope.object();
            try @import("extensions/native_sdk_session_control.zig").install(engine, prototype);
            break :blk try scope.get(prototype, name);
        };
        const pending = try scope.call(function, receiver, &.{});
        const reason = try scope.own(privateReason(engine)); // Born after Await.
        _ = try scope.call(resolving[1], c.pi_js_undefined(), &.{reason});
        try drain(engine, pending);
        try std.testing.expectEqual(c.JS_PROMISE_REJECTED, c.JS_PromiseState(engine.context, pending));
        const actual = try scope.own(c.JS_PromiseResult(engine.context, pending));
        try std.testing.expect(c.JS_IsStrictEqual(engine.context, reason, actual));
        try std.testing.expect(!c.JS_IsUncatchableError(actual));
        try std.testing.expect(!c.JS_HasException(engine.context));
    }
}

fn allocateOnResume(engine: *em.Engine, _: c.JSValue, _: []const c.JSValue, _: []const c.JSValue, _: *c.JSValue, completion: af.Completion, _: c.JSValue) !af.Action {
    if (completion == .start) return .{ .awaited = c.pi_js_undefined() };
    const bytes = try engine.gpa.alloc(u8, 1);
    defer engine.gpa.free(bytes);
    return .{ .returned = c.pi_js_undefined() };
}
test "native Await DATA genuine resumed allocator failure remains a host fatal event" {
    var failing = std.testing.FailingAllocator.init(std.testing.allocator, .{});
    const engine = try em.Engine.init(failing.allocator(), .{}); defer engine.deinit();
    const function = try af.createResumable(engine, "allocateOnResume", 0, allocateOnResume, &.{}); defer engine.freeValue(function);
    const pending = try engine.checked(c.JS_Call(engine.context, function, c.pi_js_undefined(), 0, null)); defer engine.freeValue(pending);
    failing.fail_index = failing.alloc_index;
    var context: ?*c.JSContext = null;
    const status = c.JS_ExecutePendingJob(engine.runtime, &context);
    failing.fail_index = std.math.maxInt(usize);
    try std.testing.expect(failing.has_induced_failure and status < 0);
    const reason = c.JS_GetException(context orelse engine.context); defer engine.freeValue(reason);
    try std.testing.expect(c.JS_IsUncatchableError(reason));
    try std.testing.expect(c.pi_js_native_allocation_error_generation(reason) != 0);
    try std.testing.expectEqual(c.JS_PROMISE_PENDING, c.JS_PromiseState(engine.context, pending));
}

test "native Await DATA genuine cancellation before resumed job remains host fatal" {
    const engine = try em.Engine.init(std.testing.allocator, .{}); defer engine.deinit();
    const function = try af.createResumable(engine, "cancelBeforeResume", 0, allocateOnResume, &.{}); defer engine.freeValue(function);
    const pending = try engine.checked(c.JS_Call(engine.context, function, c.pi_js_undefined(), 0, null)); defer engine.freeValue(pending);
    engine.cancelled.store(true, .release);
    var context: ?*c.JSContext = null;
    const status = c.JS_ExecutePendingJob(engine.runtime, &context);
    engine.cancelled.store(false, .release);
    try std.testing.expect(status < 0);
    const reason = c.JS_GetException(context orelse engine.context); defer engine.freeValue(reason);
    try std.testing.expect(c.JS_IsUncatchableError(reason));
    try std.testing.expectEqual(c.JS_PROMISE_PENDING, c.JS_PromiseState(engine.context, pending));
}

test "native Await DATA escaping flagged completion must reject raw reason without new host event" {
    // Normative regression: current C3 incorrectly treats JS_PI_AF_THROW's
    // value bit as an actual pending fatal. This source test remains a known
    // negative until the separately reviewed primitive distinction is fixed.
    const engine = try em.Engine.init(std.testing.allocator, .{}); defer engine.deinit();
    var scope: p.Scope = .{ .engine = engine }; defer scope.deinit();
    const reason = try scope.own(try engine.checked(c.JS_NewError(engine.context)));
    c.JS_SetUncatchableError(engine.context, reason);
    const input = try scope.own(try engine.checked(c.JS_NewSettledPromise(engine.context, true, reason)));
    const function = try scope.own(try af.createResumable(engine, "escapeFlaggedData", 1, escapedInput, &.{}));
    const pending = try scope.own(try callOne(engine, function, input));
    try drain(engine, pending);
    try std.testing.expectEqual(c.JS_PROMISE_REJECTED, c.JS_PromiseState(engine.context, pending));
    const actual = try scope.own(c.JS_PromiseResult(engine.context, pending));
    try std.testing.expect(c.JS_IsStrictEqual(engine.context, reason, actual));
    try std.testing.expect(c.JS_IsUncatchableError(reason));
    try std.testing.expect(!c.JS_HasException(engine.context));
}
