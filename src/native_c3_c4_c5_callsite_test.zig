//! Combined real VM controls. Importing these retains their original assertions.
//! Metadata and execution require separate Root grants; no result is assumed.
comptime {
    _ = @import("native_module_graph_tla_query_test.zig");
    _ = @import("native_async_iterator_api_test.zig");
    _ = @import("native_callsite_visibility_test.zig");
    _ = @import("native_module_link_transaction_test.zig");
}

const std = @import("std");
const em = @import("extensions/engine.zig");
const js = @import("extensions/native_js_values.zig");
const c = em.c;

fn capture(context: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue) callconv(.c) c.JSValue {
    return c.JS_CaptureCurrentStackFrames(context, 32, c.pi_js_undefined(), null, 0, 0, c.JS_ERROR_STACK_SKIP_FIRST);
}

test "VM query link iterator CallSite composition preserves real declaration and evaluation boundaries" {
    const engine = try em.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    const error_owner = try @import("extensions/native_error_stack.zig").install(engine);
    defer engine.freeValue(error_owner);
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    const probe = try engine.checked(c.JS_NewCFunction(engine.context, capture, "captureComposed", 0));
    try js.define(engine, global, "captureComposed", probe);
    const module = try engine.eval(
        "globalThis.composedBody=(globalThis.composedBody||0)+1;export async function* values(){yield 23}export function frames(){return captureComposed()}",
        "C:/composition/actual-module.mjs",
        c.JS_EVAL_TYPE_MODULE | c.JS_EVAL_FLAG_COMPILE_ONLY,
    );
    defer engine.freeValue(module);
    var has_tla: c_int = 99;
    try std.testing.expectEqual(@as(c_int, 0), c.JS_PiModuleGraphHasTLA(engine.context, module, &has_tla));
    try std.testing.expectEqual(@as(c_int, 0), has_tla);
    {
        // This caller attests the genuine capture-only owner above, balanced
        // suppression, Engine's trusted interrupt and no graph/context reentry.
        engine.native_exception_diagnostics_suppressed += 1;
        defer engine.native_exception_diagnostics_suppressed -= 1;
        try std.testing.expectEqual(@as(c_int, 0), c.JS_PiLinkModuleGraph(engine.context, module));
    }
    try std.testing.expect(!c.JS_HasException(engine.context));
    const before = try js.get(engine, global, "composedBody");
    defer engine.freeValue(before);
    try std.testing.expect(c.JS_IsUndefined(before));
    try std.testing.expect(!c.JS_IsJobPending(engine.runtime));
    has_tla = 99;
    try std.testing.expectEqual(@as(c_int, 0), c.JS_PiModuleGraphHasTLA(engine.context, module, &has_tla));
    try std.testing.expectEqual(@as(c_int, 0), has_tla);

    const evaluated = try engine.checked(c.JS_EvalFunction(engine.context, c.JS_DupValue(engine.context, module)));
    defer engine.freeValue(evaluated);
    const settled = try engine.awaitValue(evaluated);
    defer engine.freeValue(settled);
    const body_count = try js.get(engine, global, "composedBody");
    defer engine.freeValue(body_count);
    try std.testing.expect(c.JS_IsStrictEqual(engine.context, body_count, c.JS_NewInt32(engine.context, 1)));
    const namespace = try engine.checked(c.JS_GetModuleNamespace(engine.context, c.pi_js_module(module)));
    defer engine.freeValue(namespace);
    const values = try js.get(engine, namespace, "values");
    defer engine.freeValue(values);
    const generator = try js.call(engine, values, c.pi_js_undefined(), &.{});
    defer engine.freeValue(generator);
    const iterator = try @import("extensions/native_async_iterator_api.zig").acquire(engine, generator);
    defer engine.freeValue(iterator);
    try std.testing.expect(c.JS_IsStrictEqual(engine.context, generator, iterator));
    const pending = try js.invoke(engine, iterator, "next", &.{});
    defer engine.freeValue(pending);
    const step = try engine.awaitValue(pending);
    defer engine.freeValue(step);
    const value = try js.get(engine, step, "value");
    defer engine.freeValue(value);
    try std.testing.expect(c.JS_IsStrictEqual(engine.context, value, c.JS_NewInt32(engine.context, 23)));
    const frames_function = try js.get(engine, namespace, "frames");
    defer engine.freeValue(frames_function);
    const frames = try js.call(engine, frames_function, namespace, &.{});
    defer engine.freeValue(frames);
    const frame = try engine.checked(c.JS_GetPropertyUint32(engine.context, frames, 0));
    defer engine.freeValue(frame);
    const function = try js.invoke(engine, frame, "getFunction", &.{});
    defer engine.freeValue(function);
    const receiver = try js.invoke(engine, frame, "getThis", &.{});
    defer engine.freeValue(receiver);
    try std.testing.expect(c.JS_IsUndefined(function) and c.JS_IsUndefined(receiver));
    try std.testing.expectEqual(@as(usize, 0), engine.native_exception_diagnostics_suppressed);
}
