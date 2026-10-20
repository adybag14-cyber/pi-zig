//! Zig calls into the actual native Node fatal/CHECK platform owner.
//! These calls terminate the native process. They do not mark a guest value
//! uncatchable or dispatch any process event.
const em = @import("engine.zig");
const c = em.c;
pub const Diagnostics = extern struct {
    report: ?*const fn (?*anyopaque, ?*c.JSContext, [*:0]const u8,
        [*:0]const u8, [*:0]const u8) callconv(.c) void = null,
    report_opaque: ?*anyopaque = null,
};
pub const AssertionInfo = extern struct {
    file_line: ?[*:0]const u8,
    message: [*:0]const u8,
    function: ?[*:0]const u8,
};
extern fn pi_node_heap_out_of_memory(?*c.JSContext, ?*const Diagnostics) void;
extern fn pi_node_maybe_check_failure(?*c.JSContext, ?*const Diagnostics) void;
extern fn pi_node_default_fatal_error(?*c.JSContext, ?[*:0]const u8,
    [*:0]const u8, ?*const Diagnostics) void;
extern fn pi_node_assert_failure(?*c.JSContext, *const AssertionInfo) void;
extern fn pi_node_corrupted_async_stack(?*c.JSContext, f64, f64, c_int) void;

/// The caller proves a new actual failed intrinsic allocation. This is the
/// selected original native heap OOM handler, before operand rollback.
pub fn heapOutOfMemory(engine: *em.Engine, diagnostics: ?*const Diagnostics) noreturn {
    pi_node_heap_out_of_memory(engine.context, diagnostics);
    unreachable;
}
pub fn maybeCheck(engine: *em.Engine, diagnostics: ?*const Diagnostics) noreturn {
    pi_node_maybe_check_failure(engine.context, diagnostics);
    unreachable;
}
pub fn fatal(engine: ?*em.Engine, location: ?[*:0]const u8,
    message: [*:0]const u8, diagnostics: ?*const Diagnostics) noreturn
{
    pi_node_default_fatal_error(if (engine) |owner| owner.context else null,
        location, message, diagnostics);
    unreachable;
}
pub fn assertion(engine: ?*em.Engine, info: AssertionInfo) noreturn {
    pi_node_assert_failure(if (engine) |owner| owner.context else null, &info);
    unreachable;
}
pub fn corruptedAsyncStack(engine: *em.Engine, actual: f64,
    expected: f64, abort_on_uncaught: bool) noreturn
{
    pi_node_corrupted_async_stack(engine.context, actual, expected,
        @intFromBool(abort_on_uncaught));
    unreachable;
}
