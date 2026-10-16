//! Prepared negative control: the START-path repair does not yet record a
//! module's fatal outcome when its own bytecode body aborts after suspension.
//! This separate gate asserts the required terminal cached/reimport behavior;
//! it is expected to fail until that explicitly known gap is repaired.
const std = @import("std");
const em = @import("extensions/engine.zig");
const af = @import("extensions/native_async_function.zig");
const Scope = @import("extensions/native_models_stream_scope.zig").Scope;
const c = em.c;
fn fatalStart(_: *em.Engine, _: c.JSValue, _: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
    return error.OutOfMemory;
}
test "native TLA resumed fatal KNOWN GAP cached module and reimport must terminate" {
    const engine = try em.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const global = try scope.own(c.JS_GetGlobalObject(engine.context));
    try scope.put(global, "fatalStart", try scope.own(try af.create(engine, "fatalStart", 0, fatalStart, &.{})));
    const source = "await Promise.resolve(); await fatalStart();";
    try engine.registerModule("resumed-fatal", source);
    const module = try engine.eval(source, "resumed-fatal", c.JS_EVAL_TYPE_MODULE | c.JS_EVAL_FLAG_COMPILE_ONLY);
    defer engine.freeValue(module);
    const boundary = engine.native_allocation_generation;
    const first = c.JS_EvalFunction(engine.context, c.JS_DupValue(engine.context, module));
    defer engine.freeValue(first);
    try std.testing.expect(!c.JS_IsException(first));
    try std.testing.expectEqual(c.JS_PROMISE_PENDING, c.JS_PromiseState(engine.context, first));
    try std.testing.expectError(error.JavaScriptException, engine.awaitValue(first));
    const reason = try scope.own(c.JS_DupValue(engine.context, engine.captured_exception.?));
    try std.testing.expect(c.JS_IsUncatchableError(reason));
    try std.testing.expect(c.JS_IsStrictEqual(engine.context, reason, engine.native_allocation_exception.?));
    try std.testing.expect(engine.nativeAllocationError(error.JavaScriptException, boundary) == error.OutOfMemory);
    const retry_boundary = engine.native_allocation_generation;
    const cached = c.JS_EvalFunction(engine.context, c.JS_DupValue(engine.context, module));
    defer engine.freeValue(cached);
    const cached_failed = c.JS_IsException(cached);
    const cached_reason = if (cached_failed) c.JS_GetException(engine.context) else c.pi_js_undefined();
    defer engine.freeValue(cached_reason);
    const importer = try engine.eval("import 'resumed-fatal'; export const unreachable=true;", "resumed-fatal-reimport.mjs", c.JS_EVAL_TYPE_MODULE | c.JS_EVAL_FLAG_COMPILE_ONLY);
    defer engine.freeValue(importer);
    const imported = c.JS_EvalFunction(engine.context, c.JS_DupValue(engine.context, importer));
    defer engine.freeValue(imported);
    const import_failed = c.JS_IsException(imported);
    const imported_reason = if (import_failed) c.JS_GetException(engine.context) else c.pi_js_undefined();
    defer engine.freeValue(imported_reason);
    if (!cached_failed or !import_failed) std.debug.print("KNOWN GAP resumed TLA fatal: cached_exception={} cached_promise_state={d} reimport_exception={} reimport_promise_state={d} jobs_pending={}\n", .{
        cached_failed,
        c.JS_PromiseState(engine.context, cached),
        import_failed,
        c.JS_PromiseState(engine.context, imported),
        c.JS_IsJobPending(engine.runtime),
    });
    // Evaluate both entries before asserting, to expose both pending paths
    // without adding extra ticks or awaiting an already known pending result.
    try std.testing.expect(cached_failed);
    try std.testing.expect(import_failed);
    try std.testing.expect(c.JS_IsStrictEqual(engine.context, reason, cached_reason));
    try std.testing.expect(c.JS_IsStrictEqual(engine.context, reason, imported_reason));
    try std.testing.expect(!c.JS_IsUncatchableError(cached_reason));
    try std.testing.expectEqual(retry_boundary, engine.native_allocation_generation);
    try std.testing.expect(!c.JS_HasException(engine.context));
}
