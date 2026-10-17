//! Genuine native-VM host-boundary controls; inert producer patch prerequisite.
//! Direct error.OutOfMemory injections qualify transport/ownership, not actual
//! allocator-stage coverage. No original expected data is manufactured here.
const std = @import("std");
const em = @import("extensions/engine.zig");
const c = em.c;
const gen = @import("extensions/native_async_generator.zig");
const fatal = @import("extensions/native_promise_executor_fatal.zig");
const Scope = @import("extensions/native_models_stream_scope.zig").Scope;
var first: ?c.JSValue = null;
var awaited: bool = false;
fn failingBody(engine: *em.Engine, _: c.JSValue, completion: gen.Completion, _: c.JSValue) !gen.Action {
    if (completion == .start and awaited) return .{ .awaited = try engine.checked(c.JS_NewSettledPromise(engine.context, false, c.pi_js_undefined())) };
    const err = fatal.failureSince(engine, error.OutOfMemory, engine.native_allocation_generation);
    first = engine.captured_exception; return err;
}
fn next(s: *Scope, iterator: c.JSValue, value: ?c.JSValue) !c.JSValue {
    const function = try s.get(iterator, "next");
    if (value) |input| { var args = [_]c.JSValue{input}; return s.engine.checked(c.JS_Call(s.engine.context, function, iterator, 1, &args)); }
    return s.engine.checked(c.JS_Call(s.engine.context, function, iterator, 0, null));
}
test "native generator producer direct first next escapes actual pending fatal identity" {
    const engine = try em.Engine.init(std.testing.allocator, .{}); defer engine.deinit();
    var s: Scope = .{ .engine = engine }; defer s.deinit(); first = null; awaited = false;
    const owner = try s.object(); const iterator = try s.own(try gen.create(engine, owner, failingBody, c.pi_js_undefined()));
    try std.testing.expectError(error.JavaScriptException, next(&s, iterator, null));
    const reason = engine.captured_exception orelse return error.MissingNativeGeneratorFatal;
    try std.testing.expect(first != null and c.JS_IsStrictEqual(engine.context, reason, first.?));
    try std.testing.expect(c.JS_IsUncatchableError(reason));
    try std.testing.expect(!c.JS_HasException(engine.context));
}
fn dataBody(engine: *em.Engine, owner: c.JSValue, _: gen.Completion, _: c.JSValue) !gen.Action { return .{ .thrown = c.JS_DupValue(engine.context, owner) }; }
test "native generator producer marked rejected DATA without pending remains ordinary data" {
    const engine = try em.Engine.init(std.testing.allocator, .{}); defer engine.deinit();
    var s: Scope = .{ .engine = engine }; defer s.deinit();
    const marked = try s.own(try engine.checked(c.JS_NewError(engine.context))); c.JS_SetUncatchableError(engine.context, marked);
    const iterator = try s.own(try gen.create(engine, marked, dataBody, c.pi_js_undefined()));
    const promise = try s.own(try next(&s, iterator, null));
    try std.testing.expectEqual(c.JS_PROMISE_REJECTED, c.JS_PromiseState(engine.context, promise));
    const reason = try s.own(c.JS_PromiseResult(engine.context, promise));
    try std.testing.expect(c.JS_IsStrictEqual(engine.context, reason, marked));
    try std.testing.expect(c.JS_IsUncatchableError(reason));
    try std.testing.expect(!c.JS_HasException(engine.context));
}
var cleanup_context: ?*c.JSContext = null;
var ordinary_cleanup: c.JSValue = undefined;
var owner_freed: usize = 0;
var request_freed: usize = 0;
fn ownerFinalizer(_: ?*c.JSRuntime, _: c.JSValue) callconv(.c) void {
    owner_freed += 1; _ = c.JS_Throw(cleanup_context, c.JS_DupValue(cleanup_context, ordinary_cleanup));
}
fn requestFinalizer(_: ?*c.JSRuntime, _: c.JSValue) callconv(.c) void {
    request_freed += 1; const engine = em.Engine.fromContext(cleanup_context.?);
    _ = fatal.failureSince(engine, error.OutOfMemory, engine.native_allocation_generation);
    _ = engine.throwCaptured();
}
test "native generator producer Await job escapes first fatal through owner and queued request cleanup" {
    const engine = try em.Engine.init(std.testing.allocator, .{}); defer engine.deinit();
    var s: Scope = .{ .engine = engine }; defer s.deinit();
    first = null; awaited = true; cleanup_context = engine.context; owner_freed = 0; request_freed = 0;
    ordinary_cleanup = try s.own(try engine.checked(c.JS_NewError(engine.context)));
    var owner_class: c.JSClassID = 0; _ = c.JS_NewClassID(engine.runtime, &owner_class);
    var request_class: c.JSClassID = 0; _ = c.JS_NewClassID(engine.runtime, &request_class);
    const owner_def: c.JSClassDef = .{ .class_name = "Native generator owner cleanup control", .finalizer = ownerFinalizer };
    const request_def: c.JSClassDef = .{ .class_name = "Native generator request cleanup control", .finalizer = requestFinalizer };
    try std.testing.expectEqual(@as(c_int, 0), c.JS_NewClass(engine.runtime, owner_class, &owner_def));
    try std.testing.expectEqual(@as(c_int, 0), c.JS_NewClass(engine.runtime, request_class, &request_def));
    const owner = try engine.checked(c.JS_NewObjectClass(engine.context, owner_class));
    const iterator = gen.create(engine, owner, failingBody, c.pi_js_undefined()) catch |err| { engine.freeValue(owner); return err; }; engine.freeValue(owner);
    _ = try s.own(iterator);
    const first_promise = try s.own(try next(&s, iterator, null));
    const token = try engine.checked(c.JS_NewObjectClass(engine.context, request_class));
    const queued = next(&s, iterator, token) catch |err| { engine.freeValue(token); return err; }; engine.freeValue(token);
    const queued_promise = try s.own(queued);
    var job_context: ?*c.JSContext = null; var failed = false;
    for (0..16) |_| {
        const result = c.JS_ExecutePendingJob(engine.runtime, &job_context);
        if (result < 0) { failed = true; break; }
        if (result == 0) break;
    }
    try std.testing.expect(failed and c.JS_HasException(engine.context));
    const actual = c.JS_GetException(engine.context); defer engine.freeValue(actual);
    try std.testing.expect(first != null and c.JS_IsStrictEqual(engine.context, actual, first.?));
    try std.testing.expect(c.JS_IsUncatchableError(actual));
    try std.testing.expectEqual(@as(usize, 1), owner_freed); try std.testing.expectEqual(@as(usize, 1), request_freed);
    // Host-abort teardown releases native queued storage without an ordinary
    // resolver call. Already-published JS promises do not receive settlements.
    try std.testing.expectEqual(c.JS_PROMISE_PENDING, c.JS_PromiseState(engine.context, first_promise));
    try std.testing.expectEqual(c.JS_PROMISE_PENDING, c.JS_PromiseState(engine.context, queued_promise));
}
