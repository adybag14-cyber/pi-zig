//! Prepared genuine host-entry controls; not selected by build.zig or executed.
//! They create actual pending Error events, not fabricated captured slots.
const std = @import("std");
const em = @import("extensions/engine.zig");
const c = em.c;
const js = @import("extensions/native_js_values.zig");
const tty = @import("extensions/native_node_tty.zig");
const colors = @import("extensions/native_node_tty_colors.zig");
const h = @import("extensions/native_node_tty_values.zig");
fn reason(engine: *em.Engine) !c.JSValue {
    const setup = try engine.evalModule("globalThis.ttyDiagnosticCalls=0;globalThis.ttyReason=new Error('actual pending reason');ttyReason.toString=function(){ttyDiagnosticCalls++;return 'observed diagnostics'};export const proof=true;", "tty-factory-boundary-setup.mjs");
    engine.freeValue(setup);
    return js.global(engine, "ttyReason");
}
fn check(engine: *em.Engine, actual: c.JSValue, previous: usize) !void {
    try std.testing.expectEqual(previous, engine.native_exception_diagnostics_suppressed);
    const captured = engine.captured_exception orelse return error.MissingActualPendingReason;
    try std.testing.expect(c.JS_IsStrictEqual(engine.context, captured, actual));
    engine.captured_exception = null;
    engine.freeValue(captured);
    try std.testing.expect(!c.JS_HasException(engine.context));
    const calls = try js.global(engine, "ttyDiagnosticCalls"); defer engine.freeValue(calls);
    try std.testing.expect(c.JS_IsStrictEqual(engine.context, calls, c.JS_NewInt32(engine.context, 0)));
}
test "TTY four direct factories preserve actual pending Error identity without diagnostics" {
    const engine = try em.Engine.init(std.testing.allocator, .{}); defer engine.deinit();
    const actual = try reason(engine); defer engine.freeValue(actual);
    const previous = engine.native_exception_diagnostics_suppressed;
    const unused = c.pi_js_undefined();
    _ = c.JS_Throw(engine.context, c.JS_DupValue(engine.context, actual));
    try std.testing.expectError(error.JavaScriptException, colors.capturePrimordials(engine));
    try check(engine, actual, previous);
    _ = c.JS_Throw(engine.context, c.JS_DupValue(engine.context, actual));
    try std.testing.expectError(error.JavaScriptException, colors.createValidator(engine, unused, unused, unused));
    try check(engine, actual, previous);
    // These values must never be inspected: the actual preexisting event wins.
    const color_inputs: colors.Inputs = .{ .require = unused, .validate_integer = unused, .string_split = unused, .string_lower = unused, .regexp_exec = unused, .regexp_constructor = unused, .has_own = unused };
    _ = c.JS_Throw(engine.context, c.JS_DupValue(engine.context, actual));
    try std.testing.expectError(error.JavaScriptException, colors.create(engine, color_inputs));
    try check(engine, actual, previous);
    const tty_inputs: tty.Inputs = .{ .net = unused, .tty_constructor = unused, .is_tty = unused, .invalid_fd = unused, .tty_init_failed = unused, .errno_exception = unused, .require = unused, .number_is_integer = unused, .colors = .{ .get_color_depth = unused, .has_colors = unused } };
    _ = c.JS_Throw(engine.context, c.JS_DupValue(engine.context, actual));
    try std.testing.expectError(error.JavaScriptException, tty.create(engine, tty_inputs));
    try check(engine, actual, previous);
}
test "TTY bootstrap getter-thrown Error keeps identity and restores suppression nesting" {
    const engine = try em.Engine.init(std.testing.allocator, .{}); defer engine.deinit();
    const actual = try reason(engine); defer engine.freeValue(actual);
    const setup = try engine.evalModule("Object.defineProperty(globalThis,'String',{configurable:true,get(){throw ttyReason}});export const proof=true;", "tty-bootstrap-getter-boundary.mjs");
    engine.freeValue(setup);
    // Baseline zero is essential: outer suppression must not mask a missing
    // guard in the direct factory under test.
    try std.testing.expectEqual(@as(usize, 0), engine.native_exception_diagnostics_suppressed);
    try std.testing.expectError(error.JavaScriptException, colors.capturePrimordials(engine));
    try check(engine, actual, 0);
    engine.native_exception_diagnostics_suppressed += 1;
    defer engine.native_exception_diagnostics_suppressed -= 1;
    const previous = engine.native_exception_diagnostics_suppressed;
    try std.testing.expectError(error.JavaScriptException, colors.capturePrimordials(engine));
    try check(engine, actual, previous);
}
// Test-only native callback. The owner sets it for one serial coercion, clears
// it with defer, and never publishes its address into a production namespace.
var coercion_allocator: ?*std.testing.FailingAllocator = null;
fn pendingNumber(context: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    const actual = js.global(engine, "ttyReason") catch return c.JS_ThrowTypeError(context, "control setup failed");
    _ = c.JS_Throw(context, actual);
    const failing = coercion_allocator.?;
    // Exactly the next host allocation fails; VM values use their linked C
    // allocator. Scope's first overflow append would be that allocation.
    failing.fail_index = failing.alloc_index;
    return c.JS_NewInt32(context, 4);
}
test "TTY arithmetic pending event wins before a causally failing overflow-root allocation" {
    var failing = std.testing.FailingAllocator.init(std.testing.allocator, .{});
    const engine = try em.Engine.init(failing.allocator(), .{}); defer engine.deinit();
    const actual = try reason(engine); defer engine.freeValue(actual);
    const object = try engine.checked(c.JS_NewObject(engine.context)); defer engine.freeValue(object);
    const native = try engine.checked(c.JS_NewCFunction(engine.context, pendingNumber, "actualPendingCoercion", 0));
    if (c.JS_DefinePropertyValueStr(engine.context, object, "valueOf", native, c.JS_PROP_C_W_E) < 0) return js.capture(engine);
    var s: h.Scope = .{ .engine = engine }; defer s.deinit();
    for (0..32) |_| _ = try s.own(c.JS_NewInt32(engine.context, 0));
    coercion_allocator = &failing;
    defer coercion_allocator = null;
    engine.native_exception_diagnostics_suppressed += 1;
    defer engine.native_exception_diagnostics_suppressed -= 1;
    const previous = engine.native_exception_diagnostics_suppressed;
    try std.testing.expectError(error.JavaScriptException, h.binary(&s, .power, c.JS_NewInt32(engine.context, 2), object));
    // A root-first implementation attempts/fails allocation and returns OOM.
    // Correct event-first handling never reaches that allocation at all.
    try std.testing.expect(!failing.has_induced_failure);
    failing.fail_index = std.math.maxInt(usize);
    try check(engine, actual, previous);
}
