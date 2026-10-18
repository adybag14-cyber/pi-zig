//! Real shared-runtime composition control; no Source golden or capture.
comptime {
    _ = @import("native_await_rejection_data_test.zig");
    _ = @import("native_receiver_get_test.zig");
}
const std = @import("std");
const em = @import("extensions/engine.zig");
const af = @import("extensions/native_async_function.zig");
const c = em.c;
fn throwData(engine: *em.Engine, _: c.JSValue, _: []const c.JSValue, roots: []const c.JSValue, _: *c.JSValue, completion: af.Completion, _: c.JSValue) !af.Action {
    if (completion != .start) return error.UnexpectedCompositionResume;
    return .{ .thrown = c.JS_DupValue(engine.context, roots[0]) };
}
test "VM AF receiver composition uses real receiver and rejects marked throw DATA" {
    const engine = try em.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    const marker = try engine.checked(c.JS_NewError(engine.context));
    defer engine.freeValue(marker);
    c.JS_SetUncatchableError(engine.context, marker);
    try std.testing.expect(c.JS_IsUncatchableError(marker));
    const function = try af.createResumable(engine, "ordinaryThrowData", 0, throwData, &.{marker});
    defer engine.freeValue(function);
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    if (c.JS_DefinePropertyValueStr(engine.context, global, "ComposedAsync", c.JS_DupValue(engine.context, function), c.JS_PROP_C_W_E) < 0) return error.JavaScriptException;
    const setup = try engine.eval(
        "globalThis.Receiver={};globalThis.Calls=0;globalThis.Base={get action(){if(this!==Receiver)throw Error('receiver lost');Calls++;return ComposedAsync}}",
        "composed-af-receiver-control.js",
        c.JS_EVAL_TYPE_GLOBAL,
    );
    engine.freeValue(setup);
    const base = try engine.checked(c.JS_GetPropertyStr(engine.context, global, "Base"));
    defer engine.freeValue(base);
    const receiver = try engine.checked(c.JS_GetPropertyStr(engine.context, global, "Receiver"));
    defer engine.freeValue(receiver);
    const atom = c.JS_NewAtom(engine.context, "action");
    if (atom == c.JS_ATOM_NULL) return error.OutOfMemory;
    defer c.JS_FreeAtom(engine.context, atom);
    const method = try engine.checked(c.JS_PiGetPropertyReceiver(engine.context, base, atom, receiver));
    defer engine.freeValue(method);
    try std.testing.expect(c.JS_IsStrictEqual(engine.context, function, method));
    const promise = try engine.checked(c.JS_Call(engine.context, method, receiver, 0, null));
    defer engine.freeValue(promise);
    try std.testing.expectEqual(c.JS_PROMISE_REJECTED, c.JS_PromiseState(engine.context, promise));
    const reason = c.JS_PromiseResult(engine.context, promise);
    defer engine.freeValue(reason);
    try std.testing.expect(c.JS_IsStrictEqual(engine.context, marker, reason));
    try std.testing.expect(c.JS_IsUncatchableError(reason));
    try std.testing.expect(!c.JS_HasException(engine.context));
    const calls = try engine.checked(c.JS_GetPropertyStr(engine.context, global, "Calls"));
    defer engine.freeValue(calls);
    var count: i32 = 0;
    if (c.JS_ToInt32(engine.context, &count, calls) < 0) return error.JavaScriptException;
    try std.testing.expectEqual(@as(i32, 1), count);
}
