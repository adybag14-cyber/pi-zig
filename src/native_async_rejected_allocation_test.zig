const std = @import("std");
const v = @import("extensions/native_ai_provider_values.zig");
const body = @import("extensions/native_async_body.zig");
const native = body.native;
const c = v.c;
fn allocationReason(engine: *v.em.Engine) c.JSValue {
    _ = engine.throwNativeOutOfMemory();
    return c.JS_GetException(engine.context);
}
fn awaitRejected(engine: *v.em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue, _: *c.JSValue, completion: native.Completion, input: c.JSValue) !native.Action {
    if (completion == .start) return .{ .awaited = c.JS_DupValue(engine.context, args[0]) };
    var generation: u64 = 0;
    if (c.JS_ToBigUint64(engine.context, &generation, roots[0]) < 0) return v.js.capture(engine);
    if (completion == .rejected) {
        body.rethrowRecognizedAllocation(engine, input, generation) catch |err| return body.failure(engine, err);
        return .{ .thrown = c.JS_DupValue(engine.context, input) };
    }
    return .{ .returned = c.JS_DupValue(engine.context, input) };
}
fn rejectedInput(engine: *v.em.Engine, reason: c.JSValue, generation: u64) !c.JSValue {
    const marker = try engine.checked(c.JS_NewBigUint64(engine.context, generation));
    defer engine.freeValue(marker);
    const function = try native.createResumable(engine, "rejectedAllocationBoundary", 1, awaitRejected, &.{marker});
    defer engine.freeValue(function);
    const input = try engine.checked(c.JS_NewSettledPromise(engine.context, true, reason));
    defer engine.freeValue(input);
    var args = [_]c.JSValue{input};
    return engine.checked(c.JS_Call(engine.context, function, c.pi_js_undefined(), args.len, &args));
}
test "native async rejected allocation fresh private reason retains exact identity and uncatchable failure" {
    const engine = try v.em.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    const generation = engine.native_allocation_generation;
    const reason = allocationReason(engine);
    defer engine.freeValue(reason);
    defer c.JS_ClearUncatchableError(engine.context, reason);
    try std.testing.expect(!c.JS_IsUncatchableError(reason));
    try std.testing.expectError(error.JavaScriptException, body.rethrowRecognizedAllocation(engine, reason, generation));
    try std.testing.expect(c.JS_IsUncatchableError(reason));
    try std.testing.expect(c.JS_IsStrictEqual(engine.context, reason, engine.captured_exception.?));
    try std.testing.expectError(error.JavaScriptException, body.failure(engine, error.JavaScriptException));
    try std.testing.expect(c.JS_IsStrictEqual(engine.context, reason, engine.captured_exception.?));
}
test "native async rejected allocation historical private tag remains ordinary guest rejection" {
    const engine = try v.em.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    const reason = allocationReason(engine);
    defer engine.freeValue(reason);
    const generation = engine.native_allocation_generation;
    const pending = try rejectedInput(engine, reason, generation);
    defer engine.freeValue(pending);
    _ = try engine.runReadyJobs(16);
    try std.testing.expect(!c.JS_IsUncatchableError(reason));
    try std.testing.expectEqual(c.JS_PROMISE_REJECTED, c.JS_PromiseState(engine.context, pending));
    const rejected = c.JS_PromiseResult(engine.context, pending);
    defer engine.freeValue(rejected);
    try std.testing.expect(c.JS_IsStrictEqual(engine.context, rejected, reason));
    try std.testing.expect(!c.JS_HasException(engine.context));
}
test "native async rejected allocation user lookalike properties never become private host authority" {
    const engine = try v.em.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    var scope: v.Scope = .{ .engine = engine };
    defer scope.deinit();
    const reason = try scope.own(try v.js.builtin(engine, "Error", &.{try scope.text("out of memory")}));
    try scope.set(reason, "name", try scope.text("InternalError"));
    try scope.put(reason, "native_allocation_generation", c.JS_NewInt32(engine.context, 1));
    try scope.put(reason, "status", c.JS_NewInt32(engine.context, 503));
    const generation = engine.native_allocation_generation;
    const unrelated = allocationReason(engine);
    defer engine.freeValue(unrelated);
    try std.testing.expectEqual(@as(u64, 0), c.pi_js_native_allocation_error_generation(reason));
    const pending = try scope.own(try rejectedInput(engine, reason, generation));
    _ = try engine.runReadyJobs(16);
    try std.testing.expect(!c.JS_IsUncatchableError(reason));
    try std.testing.expectEqual(c.JS_PROMISE_REJECTED, c.JS_PromiseState(engine.context, pending));
    const rejected = try scope.own(c.JS_PromiseResult(engine.context, pending));
    try std.testing.expect(c.JS_IsStrictEqual(engine.context, rejected, reason));
    try std.testing.expect(!c.JS_HasException(engine.context));
}
test "native async rejected allocation unsigned wrap accepts both fresh reasons and excludes older tag" {
    const engine = try v.em.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    engine.native_allocation_generation = std.math.maxInt(u64) - 3;
    const historical = allocationReason(engine);
    defer engine.freeValue(historical);
    const boundary_marker = allocationReason(engine);
    defer engine.freeValue(boundary_marker);
    const generation = engine.native_allocation_generation;
    const before_wrap = allocationReason(engine);
    defer engine.freeValue(before_wrap);
    defer c.JS_ClearUncatchableError(engine.context, before_wrap);
    const after_wrap = allocationReason(engine);
    defer engine.freeValue(after_wrap);
    defer c.JS_ClearUncatchableError(engine.context, after_wrap);
    try std.testing.expectEqual(@as(u64, 1), engine.native_allocation_generation);
    try body.rethrowRecognizedAllocation(engine, historical, generation);
    try std.testing.expect(!c.JS_IsUncatchableError(historical));
    for ([_]c.JSValue{ before_wrap, after_wrap }) |reason| {
        try std.testing.expectError(error.JavaScriptException, body.rethrowRecognizedAllocation(engine, reason, generation));
        try std.testing.expect(c.JS_IsUncatchableError(reason));
        try std.testing.expect(c.JS_IsStrictEqual(engine.context, reason, engine.captured_exception.?));
    }
}
test "native async rejected allocation recognized resumed reason escapes real primitive job with original identity" {
    const engine = try v.em.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    const generation = engine.native_allocation_generation;
    const reason = allocationReason(engine);
    defer engine.freeValue(reason);
    defer c.JS_ClearUncatchableError(engine.context, reason);
    const pending = try rejectedInput(engine, reason, generation);
    defer engine.freeValue(pending);
    try std.testing.expectEqual(c.JS_PROMISE_PENDING, c.JS_PromiseState(engine.context, pending));
    var context: ?*c.JSContext = null;
    try std.testing.expect(c.JS_ExecutePendingJob(engine.runtime, &context) < 0);
    const escaped = c.JS_GetException(context orelse engine.context);
    defer engine.freeValue(escaped);
    try std.testing.expect(c.JS_IsUncatchableError(escaped));
    try std.testing.expect(c.JS_IsStrictEqual(engine.context, escaped, reason));
    try std.testing.expect(c.JS_IsStrictEqual(engine.context, escaped, engine.captured_exception.?));
    try std.testing.expectEqual(c.JS_PROMISE_PENDING, c.JS_PromiseState(engine.context, pending));
    c.JS_RunGC(engine.runtime);
}
