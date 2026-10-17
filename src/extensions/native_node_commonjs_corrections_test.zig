//! Prepared, uncompiled controls for the CommonJS-local interruption boundary.
//! These do not claim a composed Node namespace or whole-loop mutation gate.
const std = @import("std");
const v = @import("native_ai_provider_values.zig");
const c = v.c;
const interrupt = @import("native_node_commonjs_interrupt.zig");
const functions = @import("native_node_module_callable.zig");
fn cancelBoundary(engine: *v.em.Engine, _: c.JSValue, _: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
    const previous = engine.cancelled.load(.acquire);
    engine.cancelled.store(true, .release);
    defer engine.cancelled.store(previous, .release);
    var steps: usize = 0;
    try interrupt.step(engine, &steps);
    return c.pi_js_undefined();
}
fn budgetBoundary(engine: *v.em.Engine, _: c.JSValue, _: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
    const previous = engine.interrupts;
    engine.interrupts = engine.options.interrupt_budget;
    defer engine.interrupts = previous;
    var steps: usize = 255;
    try interrupt.step(engine, &steps);
    return c.pi_js_undefined();
}
fn uncaughtBoundary(callback: functions.Callback) !void {
    const engine = try v.em.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    const generation = engine.native_allocation_generation;
    const global = try engine.checked(c.JS_GetGlobalObject(engine.context));
    defer engine.freeValue(global);
    const function = try functions.create(engine, "ownedLoopBoundary", 0, false, callback, &.{});
    if (c.JS_DefinePropertyValueStr(engine.context, global, "ownedLoopBoundary", function, c.JS_PROP_C_W_E) < 0) return v.js.capture(engine);
    const source = "globalThis.ownedCaught=0;try{ownedLoopBoundary()}catch(e){ownedCaught++}globalThis.ownedAfter=true";
    const result = c.JS_Eval(engine.context, source.ptr, source.len, "owned-commonjs-interruption.js", c.JS_EVAL_TYPE_GLOBAL);
    defer engine.freeValue(result); // Includes an unexpected successful result.
    try std.testing.expect(c.JS_IsException(result));
    try std.testing.expect(c.JS_HasException(engine.context));
    const reason = c.JS_GetException(engine.context);
    defer engine.freeValue(reason);
    try std.testing.expect(c.JS_IsUncatchableError(reason));
    const caught = try engine.checked(c.JS_GetPropertyStr(engine.context, global, "ownedCaught"));
    defer engine.freeValue(caught);
    try std.testing.expect(c.JS_IsStrictEqual(engine.context, caught, c.JS_NewInt32(engine.context, 0)));
    const after = try engine.checked(c.JS_GetPropertyStr(engine.context, global, "ownedAfter"));
    defer engine.freeValue(after);
    try std.testing.expect(c.JS_IsUndefined(after));
    try std.testing.expectEqual(generation, engine.native_allocation_generation);
    c.JS_ClearUncatchableError(engine.context, reason); // Host has handled it.
    const reused = try engine.eval("1+1", "owned-commonjs-after-interruption.js", c.JS_EVAL_TYPE_GLOBAL);
    defer engine.freeValue(reused);
    try std.testing.expect(c.JS_IsStrictEqual(engine.context, reused, c.JS_NewInt32(engine.context, 2)));
}
test "CommonJS local cancellation escapes a genuine ordinary VM callable and guest catch" {
    try uncaughtBoundary(cancelBoundary);
}
test "CommonJS local native loop budget escapes without relying on the VM poll counter" {
    try uncaughtBoundary(budgetBoundary);
}
test "CommonJS local step ignores historical captured flags until a fresh cancellation" {
    const engine = try v.em.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    const historical = try engine.checked(c.JS_NewError(engine.context));
    defer engine.freeValue(historical);
    c.JS_SetUncatchableError(engine.context, historical);
    engine.captured_exception = c.JS_DupValue(engine.context, historical);
    const generation = engine.native_allocation_generation;
    var steps: usize = 0;
    try interrupt.step(engine, &steps);
    try std.testing.expectEqual(@as(usize, 1), steps);
    try std.testing.expect(!c.JS_HasException(engine.context));
    try std.testing.expect(c.JS_IsStrictEqual(engine.context, engine.captured_exception.?, historical));
    engine.cancelled.store(true, .release);
    defer engine.cancelled.store(false, .release);
    try std.testing.expectError(error.JavaScriptException, interrupt.step(engine, &steps));
    engine.cancelled.store(false, .release);
    const fresh = engine.captured_exception.?;
    try std.testing.expect(!c.JS_IsStrictEqual(engine.context, fresh, historical));
    try std.testing.expect(c.JS_IsUncatchableError(fresh));
    try std.testing.expectEqual(generation, engine.native_allocation_generation);
    c.JS_ClearUncatchableError(engine.context, fresh);
    c.JS_ClearUncatchableError(engine.context, historical);
}
fn preservesPending(fatal: bool) !void {
    const engine = try v.em.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    const old = try engine.checked(c.JS_NewError(engine.context));
    defer engine.freeValue(old);
    engine.captured_exception = c.JS_DupValue(engine.context, old);
    const current = try engine.checked(c.JS_NewError(engine.context));
    defer engine.freeValue(current);
    if (fatal) c.JS_SetUncatchableError(engine.context, current);
    _ = c.JS_Throw(engine.context, c.JS_DupValue(engine.context, current));
    engine.cancelled.store(true, .release);
    defer engine.cancelled.store(false, .release);
    const generation = engine.native_allocation_generation;
    var steps: usize = 0;
    try std.testing.expectError(error.JavaScriptException, interrupt.step(engine, &steps));
    try std.testing.expectEqual(@as(usize, 0), steps);
    try std.testing.expect(!c.JS_HasException(engine.context));
    try std.testing.expect(c.JS_IsStrictEqual(engine.context, engine.captured_exception.?, current));
    try std.testing.expectEqual(fatal, c.JS_IsUncatchableError(current));
    try std.testing.expectEqual(generation, engine.native_allocation_generation);
    if (fatal) c.JS_ClearUncatchableError(engine.context, current);
}
test "CommonJS local step captures an actual pending fatal before creating an interruption" {
    try preservesPending(true);
}
test "CommonJS local step preserves an actual ordinary pending reason without retagging" {
    try preservesPending(false);
}
