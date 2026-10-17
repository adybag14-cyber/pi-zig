//! Prepared native controls. No execution or product parity claimed.
const std = @import("std");
const em = @import("extensions/engine.zig");
const js = @import("extensions/native_js_values.zig");
const node = @import("extensions/native_node_function.zig");
const heap = @import("extensions/native_typebox_continuation.zig");
const c = em.c;

fn legacy(_: *em.Engine, _: c.JSValue, _: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
    return error.LegacyBodyMustNotExecute;
}
fn int(engine: *em.Engine, value: c.JSValue) !i32 {
    var out: i32 = 0;
    if (c.JS_ToInt32(engine.context, &out, value) < 0) return js.capture(engine);
    return out;
}
fn recurse(a: *heap.Activation) !heap.Action {
    const count = try int(a.engine(), a.args[1]);
    if (count == 0) return .{ .returned = c.JS_NewInt32(a.engine().context, 0) };
    a.values[0] = a.args[0];
    a.values[1] = c.JS_NewInt32(a.engine().context, count - 1);
    return .{ .call = .{ .function = a.args[0], .receiver = c.pi_js_undefined(), .args = a.values[0..2], .result = 2, .next = 1 } };
}
fn incrementResult(a: *heap.Activation) !heap.Action {
    return .{ .returned = c.JS_NewInt32(a.engine().context, (try int(a.engine(), a.values[2])) + 1) };
}
const recursion_steps = [_]*const fn (*heap.Activation) anyerror!heap.Action{ recurse, incrementResult };
const recursion_plan: heap.Plan = .{ .source_callback = legacy, .slots = 3, .entry = 0, .steps = &recursion_steps };

test "TypeBox heap continuation real VM dispatch retires private recursion frames" {
    const engine = try em.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    const function = try node.createPlanned(engine, "recursive", 2, legacy, &.{}, false, &recursion_plan);
    defer engine.freeValue(function);
    const returned = try js.call(engine, function, c.pi_js_undefined(), &.{ function, c.JS_NewInt32(engine.context, 1500) });
    defer engine.freeValue(returned);
    try std.testing.expectEqual(@as(i32, 1500), try int(engine, returned));
    try std.testing.expectEqual(@as(usize, 0), engine.native_exception_diagnostics_suppressed);
}
fn returnRoot(a: *heap.Activation) !heap.Action { return .{ .returned = a.roots[0] }; }
const root_steps = [_]*const fn (*heap.Activation) anyerror!heap.Action{returnRoot};
const root_plan: heap.Plan = .{ .source_callback = legacy, .slots = 0, .entry = 0, .steps = &root_steps };
test "TypeBox heap continuation registry distinguishes closures sharing callback and descriptor" {
    const engine = try em.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    const first = try node.createPlanned(engine, "same", 0, legacy, &.{c.JS_NewInt32(engine.context, 41)}, false, &root_plan);
    defer engine.freeValue(first);
    const second = try node.createPlanned(engine, "same", 0, legacy, &.{c.JS_NewInt32(engine.context, 42)}, false, &root_plan);
    defer engine.freeValue(second);
    const a = try js.call(engine, first, c.pi_js_undefined(), &.{});
    defer engine.freeValue(a);
    const b = try js.call(engine, second, c.pi_js_undefined(), &.{});
    defer engine.freeValue(b);
    try std.testing.expectEqual(@as(i32, 41), try int(engine, a));
    try std.testing.expectEqual(@as(i32, 42), try int(engine, b));
}
test "TypeBox heap continuation finalizer removes weak registration before address reuse" {
    const engine = try em.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    for (0..64) |index| {
        const function = try node.createPlanned(engine, "reuse", 0, legacy, &.{c.JS_NewInt32(engine.context, @intCast(index))}, false, &root_plan);
        const returned = try js.call(engine, function, c.pi_js_undefined(), &.{});
        try std.testing.expectEqual(@as(i32, @intCast(index)), try int(engine, returned));
        engine.freeValue(returned);
        engine.freeValue(function);
    }
}
fn returnReceiver(a: *heap.Activation) !heap.Action { return .{ .returned = a.receiver }; }
const receiver_steps = [_]*const fn (*heap.Activation) anyerror!heap.Action{returnReceiver};
const receiver_plan: heap.Plan = .{ .source_callback = legacy, .slots = 0, .entry = 0, .steps = &receiver_steps };
fn returnLexical(a: *heap.Activation) !heap.Action {
    if (!c.JS_IsUndefined(a.receiver)) return error.ArrowReceiverMustBeUndefined;
    return .{ .returned = a.roots[1] };
}
const lexical_steps = [_]*const fn (*heap.Activation) anyerror!heap.Action{returnLexical};
const lexical_plan: heap.Plan = .{ .source_callback = legacy, .slots = 0, .entry = 0, .steps = &lexical_steps };
test "TypeBox heap continuation ordinary and arrow receivers retain their distinct rules" {
    const engine = try em.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    const target = try js.object(engine);
    defer engine.freeValue(target);
    const lexical = try js.object(engine);
    defer engine.freeValue(lexical);
    const ordinary = try node.createPlanned(engine, "ordinary", 0, legacy, &.{}, false, &receiver_plan);
    defer engine.freeValue(ordinary);
    const arrow = try node.createPlanned(engine, "arrow", 0, legacy, &.{ c.pi_js_undefined(), lexical }, true, &lexical_plan);
    defer engine.freeValue(arrow);
    const a = try js.call(engine, ordinary, target, &.{});
    defer engine.freeValue(a);
    const b = try js.call(engine, arrow, target, &.{});
    defer engine.freeValue(b);
    try std.testing.expect(c.JS_IsStrictEqual(engine.context, a, target));
    try std.testing.expect(c.JS_IsStrictEqual(engine.context, b, lexical));
    try std.testing.expect(!c.JS_IsConstructor(engine.context, arrow));
}
test "TypeBox heap continuation constructor preserves actual receiver prototype rules" {
    const engine = try em.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    const constructor = try node.createPlanned(engine, "Constructed", 0, legacy, &.{}, false, &receiver_plan);
    defer engine.freeValue(constructor);
    const returned = try engine.checked(c.JS_CallConstructor(engine.context, constructor, 0, null));
    defer engine.freeValue(returned);
    const prototype = try engine.checked(c.JS_GetPrototype(engine.context, returned));
    defer engine.freeValue(prototype);
    const expected = try js.get(engine, constructor, "prototype");
    defer engine.freeValue(expected);
    try std.testing.expect(c.JS_IsObject(returned));
    try std.testing.expect(c.JS_IsStrictEqual(engine.context, prototype, expected));
}
fn sum(a: *heap.Activation) !heap.Action {
    return .{ .returned = c.JS_NewInt32(a.engine().context, (try int(a.engine(), a.args[0])) + (try int(a.engine(), a.args[1]))) };
}
const sum_steps = [_]*const fn (*heap.Activation) anyerror!heap.Action{sum};
const sum_plan: heap.Plan = .{ .source_callback = legacy, .slots = 0, .entry = 0, .steps = &sum_steps };
fn leaf(a: *heap.Activation) !heap.Action { return .{ .returned = c.JS_NewInt32(a.engine().context, 17) }; }
const leaf_steps = [_]*const fn (*heap.Activation) anyerror!heap.Action{leaf};
const leaf_plan: heap.Plan = .{ .source_callback = legacy, .slots = 0, .entry = 0, .steps = &leaf_steps };
fn reduce(a: *heap.Activation) !heap.Action {
    a.values[0] = a.args[2];
    a.values[1] = c.JS_NewInt32(a.engine().context, 0);
    return .{ .call = .{ .function = a.args[0], .receiver = a.args[1], .args = a.values[0..2], .result = 2, .next = 1 } };
}
fn afterReduce(a: *heap.Activation) !heap.Action {
    return .{ .call = .{ .function = a.args[3], .receiver = c.pi_js_undefined(), .args = a.values[0..0], .result = 3, .next = 2 } };
}
fn afterLeaf(a: *heap.Activation) !heap.Action {
    return .{ .returned = c.JS_NewInt32(a.engine().context, (try int(a.engine(), a.values[2])) + (try int(a.engine(), a.values[3]))) };
}
const reduce_steps = [_]*const fn (*heap.Activation) anyerror!heap.Action{ reduce, afterReduce, afterLeaf };
const reduce_plan: heap.Plan = .{ .source_callback = legacy, .slots = 4, .entry = 0, .steps = &reduce_steps };
test "TypeBox heap continuation actual Array reduce reentry restores outer scheduler" {
    const engine = try em.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    const array = try engine.eval("[1,2,3]", "heap-reduce-control.js", c.JS_EVAL_TYPE_GLOBAL);
    defer engine.freeValue(array);
    const reducer = try js.get(engine, array, "reduce");
    defer engine.freeValue(reducer);
    const callback = try node.createPlanned(engine, "sum", 2, legacy, &.{}, true, &sum_plan);
    defer engine.freeValue(callback);
    const final = try node.createPlanned(engine, "leaf", 0, legacy, &.{}, false, &leaf_plan);
    defer engine.freeValue(final);
    const root = try node.createPlanned(engine, "reduce-root", 4, legacy, &.{}, false, &reduce_plan);
    defer engine.freeValue(root);
    const returned = try js.call(engine, root, c.pi_js_undefined(), &.{ reducer, array, callback, final });
    defer engine.freeValue(returned);
    try std.testing.expectEqual(@as(i32, 23), try int(engine, returned));
    try std.testing.expectEqual(@as(usize, 0), engine.native_exception_diagnostics_suppressed);
}
fn enterFinally(_: *heap.Activation) !heap.Action { return .{ .enter_finally = .{ .handler = 2, .next = 1 } }; }
fn ordinaryThrow(a: *heap.Activation) !heap.Action { return .{ .thrown = a.args[0] }; }
fn overrideFinally(a: *heap.Activation) !heap.Action { return .{ .returned = a.args[1] }; }
fn freshOom(_: *heap.Activation) !heap.Action { return error.OutOfMemory; }
const ordinary_steps = [_]*const fn (*heap.Activation) anyerror!heap.Action{ enterFinally, ordinaryThrow, overrideFinally };
const ordinary_plan: heap.Plan = .{ .source_callback = legacy, .slots = 0, .entry = 0, .steps = &ordinary_steps };
const fatal_steps = [_]*const fn (*heap.Activation) anyerror!heap.Action{ enterFinally, freshOom, overrideFinally };
const fatal_plan: heap.Plan = .{ .source_callback = legacy, .slots = 0, .entry = 0, .steps = &fatal_steps };
test "TypeBox heap continuation ordinary finally overrides throw and retains captured identity" {
    const engine = try em.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    const reason = try js.object(engine);
    defer engine.freeValue(reason);
    const override = try js.object(engine);
    defer engine.freeValue(override);
    const function = try node.createPlanned(engine, "ordinary-finally", 2, legacy, &.{}, false, &ordinary_plan);
    defer engine.freeValue(function);
    const returned = try js.call(engine, function, c.pi_js_undefined(), &.{ reason, override });
    defer engine.freeValue(returned);
    try std.testing.expect(c.JS_IsStrictEqual(engine.context, returned, override));
    try std.testing.expect(c.JS_IsStrictEqual(engine.context, engine.captured_exception.?, reason));
}
test "TypeBox heap continuation trusted fatal skips guest finally without replacing reason" {
    const engine = try em.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    const function = try node.createPlanned(engine, "fatal-finally", 2, legacy, &.{}, false, &fatal_plan);
    defer engine.freeValue(function);
    const historical = try js.object(engine);
    defer engine.freeValue(historical);
    try std.testing.expectError(error.JavaScriptException, engine.checked(c.JS_Throw(engine.context, c.JS_DupValue(engine.context, historical))));
    const before = engine.native_allocation_generation;
    const returned = c.JS_Call(engine.context, function, c.pi_js_undefined(), 2, @constCast(&[_]c.JSValue{ c.pi_js_null(), c.JS_NewInt32(engine.context, 99) }));
    try std.testing.expect(c.JS_IsException(returned));
    const reason = c.JS_GetException(engine.context);
    defer engine.freeValue(reason);
    try std.testing.expect(c.JS_IsUncatchableError(reason));
    try std.testing.expectEqual(before + 1, engine.native_allocation_generation);
    try std.testing.expectEqual(engine.native_allocation_generation, c.pi_js_native_allocation_error_generation(reason));
    try std.testing.expect(c.JS_IsStrictEqual(engine.context, reason, engine.native_allocation_exception.?));
    try std.testing.expectEqual(@as(usize, 0), engine.native_exception_diagnostics_suppressed);
}
fn cleanupFatal(runtime: ?*c.JSRuntime, _: c.JSValue) callconv(.c) void {
    const engine: *em.Engine = @ptrCast(@alignCast(c.JS_GetRuntimeOpaque(runtime).?));
    _ = engine.throwNativeOutOfMemory();
    const reason = c.JS_GetException(engine.context);
    c.JS_SetUncatchableError(engine.context, reason);
    _ = c.JS_Throw(engine.context, reason);
}
fn cleanupSentinel(engine: *em.Engine) !c.JSValue {
    var class: c.JSClassID = 0;
    _ = c.JS_NewClassID(engine.runtime, &class);
    const definition: c.JSClassDef = .{ .class_name = "Heap cleanup sentinel", .finalizer = cleanupFatal };
    if (c.JS_NewClass(engine.runtime, class, &definition) < 0) return error.OutOfMemory;
    return engine.checked(c.JS_NewObjectClass(engine.context, @intCast(class)));
}
fn makeCleanupSentinel(a: *heap.Activation) !void {
    _ = try a.scope.own(try cleanupSentinel(a.engine()));
}
fn normalWithCleanup(a: *heap.Activation) !heap.Action {
    try makeCleanupSentinel(a);
    return .{ .returned = c.JS_NewInt32(a.engine().context, 7) };
}
fn fatalWithCleanup(a: *heap.Activation) !heap.Action {
    try makeCleanupSentinel(a);
    return error.OutOfMemory;
}
fn normalWithTwoCleanups(a: *heap.Activation) !heap.Action {
    try makeCleanupSentinel(a);
    try makeCleanupSentinel(a);
    return .{ .returned = c.JS_NewInt32(a.engine().context, 7) };
}
const cleanup_steps = [_]*const fn (*heap.Activation) anyerror!heap.Action{normalWithCleanup};
const cleanup_plan: heap.Plan = .{ .source_callback = legacy, .slots = 0, .entry = 0, .steps = &cleanup_steps };
const fatal_cleanup_steps = [_]*const fn (*heap.Activation) anyerror!heap.Action{fatalWithCleanup};
const fatal_cleanup_plan: heap.Plan = .{ .source_callback = legacy, .slots = 0, .entry = 0, .steps = &fatal_cleanup_steps };
const two_cleanup_steps = [_]*const fn (*heap.Activation) anyerror!heap.Action{normalWithTwoCleanups};
const two_cleanup_plan: heap.Plan = .{ .source_callback = legacy, .slots = 0, .entry = 0, .steps = &two_cleanup_steps };
test "TypeBox heap continuation teardown fatal cannot escape as a successful result" {
    const engine = try em.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    const function = try node.createPlanned(engine, "cleanup-fatal", 0, legacy, &.{}, false, &cleanup_plan);
    defer engine.freeValue(function);
    const returned = c.JS_Call(engine.context, function, c.pi_js_undefined(), 0, null);
    try std.testing.expect(c.JS_IsException(returned));
    const reason = c.JS_GetException(engine.context);
    defer engine.freeValue(reason);
    try std.testing.expect(c.JS_IsUncatchableError(reason));
    try std.testing.expect(c.pi_js_native_allocation_error_generation(reason) != 0);
}
test "TypeBox heap continuation first trusted fatal survives a later teardown fatal" {
    const engine = try em.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    const function = try node.createPlanned(engine, "two-fatals", 0, legacy, &.{}, false, &fatal_cleanup_plan);
    defer engine.freeValue(function);
    const before = engine.native_allocation_generation;
    const returned = c.JS_Call(engine.context, function, c.pi_js_undefined(), 0, null);
    try std.testing.expect(c.JS_IsException(returned));
    const reason = c.JS_GetException(engine.context);
    defer engine.freeValue(reason);
    try std.testing.expect(c.JS_IsUncatchableError(reason));
    try std.testing.expectEqual(before + 1, c.pi_js_native_allocation_error_generation(reason));
    try std.testing.expectEqual(before + 2, engine.native_allocation_generation);
}
test "TypeBox heap continuation first fatal survives cleanup of the old captured slot" {
    const engine = try em.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    const function = try node.createPlanned(engine, "captured-slot-fatal", 2, legacy, &.{}, false, &fatal_plan);
    defer engine.freeValue(function);
    try std.testing.expect(engine.captured_exception == null);
    engine.captured_exception = try cleanupSentinel(engine);
    const before = engine.native_allocation_generation;
    const arguments = [_]c.JSValue{ c.pi_js_null(), c.JS_NewInt32(engine.context, 99) };
    const returned = c.JS_Call(engine.context, function, c.pi_js_undefined(), 2, @constCast(&arguments));
    try std.testing.expect(c.JS_IsException(returned));
    const reason = c.JS_GetException(engine.context);
    defer engine.freeValue(reason);
    try std.testing.expect(c.JS_IsUncatchableError(reason));
    try std.testing.expectEqual(before + 1, c.pi_js_native_allocation_error_generation(reason));
    try std.testing.expectEqual(before + 2, engine.native_allocation_generation);
    try std.testing.expect(c.JS_IsStrictEqual(engine.context, reason, engine.captured_exception.?));
}
test "TypeBox heap continuation observes first fatal between distinct root releases" {
    const engine = try em.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    const function = try node.createPlanned(engine, "two-cleanups", 0, legacy, &.{}, false, &two_cleanup_plan);
    defer engine.freeValue(function);
    const before = engine.native_allocation_generation;
    const returned = c.JS_Call(engine.context, function, c.pi_js_undefined(), 0, null);
    try std.testing.expect(c.JS_IsException(returned));
    const reason = c.JS_GetException(engine.context);
    defer engine.freeValue(reason);
    try std.testing.expect(c.JS_IsUncatchableError(reason));
    try std.testing.expectEqual(before + 1, c.pi_js_native_allocation_error_generation(reason));
    try std.testing.expectEqual(before + 2, engine.native_allocation_generation);
}
fn fillParent(a: *heap.Activation) !heap.Action {
    while (a.scope.inline_count < a.scope.inline_values.len) _ = try a.scope.own(c.pi_js_undefined());
    return .{ .call = .{ .function = a.args[0], .receiver = c.pi_js_undefined(), .args = a.values[0..0], .result = 0, .next = 1 } };
}
fn returnChild(a: *heap.Activation) !heap.Action { return .{ .returned = a.values[0] }; }
fn failParentOwn(a: *heap.Activation) !heap.Action {
    const object = try a.scope.object();
    const failing: *std.testing.FailingAllocator = @ptrCast(@alignCast(a.engine().gpa.ptr));
    failing.fail_index = failing.alloc_index;
    return .{ .returned = object };
}
const parent_own_steps = [_]*const fn (*heap.Activation) anyerror!heap.Action{ fillParent, returnChild };
const parent_own_plan: heap.Plan = .{ .source_callback = legacy, .slots = 1, .entry = 0, .steps = &parent_own_steps };
const fail_own_steps = [_]*const fn (*heap.Activation) anyerror!heap.Action{failParentOwn};
const fail_own_plan: heap.Plan = .{ .source_callback = legacy, .slots = 0, .entry = 0, .steps = &fail_own_steps };
test "TypeBox heap continuation moved child result is consumed once when parent own fails" {
    var failing = std.testing.FailingAllocator.init(std.testing.allocator, .{});
    const engine = try em.Engine.init(failing.allocator(), .{});
    defer engine.deinit();
    const child = try node.createPlanned(engine, "owned-child", 0, legacy, &.{}, false, &fail_own_plan);
    defer engine.freeValue(child);
    const parent = try node.createPlanned(engine, "full-parent", 1, legacy, &.{}, false, &parent_own_plan);
    defer engine.freeValue(parent);
    const arguments = [_]c.JSValue{child};
    const returned = c.JS_Call(engine.context, parent, c.pi_js_undefined(), 1, @constCast(&arguments));
    failing.fail_index = std.math.maxInt(usize);
    try std.testing.expect(failing.has_induced_failure);
    try std.testing.expect(c.JS_IsException(returned));
    const reason = c.JS_GetException(engine.context);
    defer engine.freeValue(reason);
    try std.testing.expect(c.JS_IsUncatchableError(reason));
    try std.testing.expectEqual(@as(usize, 0), engine.native_exception_diagnostics_suppressed);
}
test "TypeBox heap continuation historical allocation reason remains ordinary for finally" {
    const engine = try em.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    _ = engine.throwNativeOutOfMemory();
    const historical = c.JS_GetException(engine.context);
    defer engine.freeValue(historical);
    const function = try node.createPlanned(engine, "historical-finally", 2, legacy, &.{}, false, &ordinary_plan);
    defer engine.freeValue(function);
    const returned = try js.call(engine, function, c.pi_js_undefined(), &.{ historical, c.JS_NewInt32(engine.context, 99) });
    defer engine.freeValue(returned);
    try std.testing.expectEqual(@as(i32, 99), try int(engine, returned));
}
test "TypeBox heap continuation real VM cancellation is retained as a VM failure" {
    const engine = try em.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    const function = try node.createPlanned(engine, "cancel-recursion", 2, legacy, &.{}, false, &recursion_plan);
    defer engine.freeValue(function);
    engine.cancel();
    const arguments = [_]c.JSValue{ function, c.JS_NewInt32(engine.context, 100000) };
    const returned = c.JS_Call(engine.context, function, c.pi_js_undefined(), 2, @constCast(&arguments));
    try std.testing.expect(c.JS_IsException(returned));
    const reason = c.JS_GetException(engine.context);
    defer engine.freeValue(reason);
    try std.testing.expect(c.JS_IsUncatchableError(reason));
    const message = try js.get(engine, reason, "message");
    defer engine.freeValue(message);
    const text = c.JS_ToCString(engine.context, message) orelse return error.MissingInterruptMessage;
    defer c.JS_FreeCString(engine.context, text);
    try std.testing.expect(std.mem.indexOf(u8, std.mem.span(text), "interrupted") != null);
    try std.testing.expectEqual(@as(usize, 0), engine.native_exception_diagnostics_suppressed);
}
