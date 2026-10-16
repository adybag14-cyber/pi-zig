//! SDK state-machine compatibility surface over the one shared action recorder.
//! No Promise or continuation job is allocated here. The genuine AsyncFunction
//! Body selects its continuation on VM resume and emits exactly one action.
const em = @import("engine.zig");
const Scope = @import("native_models_stream_scope.zig").Scope;
const c = em.c;
pub const body = @import("native_async_body.zig");
pub const native = body.native;
pub const reason = @import("native_agent_async.zig").reason;
pub fn wait(comptime _: *const fn (*em.Engine, c.JSValue, c.JSValue, bool, c_int) anyerror!void, engine: *em.Engine, owner: c.JSValue, value: c.JSValue, stage: c_int) !void {
    var scope: Scope = .{ .engine = engine }; defer scope.deinit();
    try body.wait(&scope, owner, value, stage);
}
pub fn settle(engine: *em.Engine, owner: c.JSValue, rejected: bool, value: c.JSValue) !void {
    var scope: Scope = .{ .engine = engine }; defer scope.deinit();
    if (rejected) try body.reject(&scope, owner, value) else try body.resolve(&scope, owner, value);
}
pub fn rejectError(engine: *em.Engine, owner: c.JSValue, err: anyerror) !void {
    // Trusted allocator failure must reach the primitive's scoped uncatchable
    // host-OOM path, rather than becoming an ordinary recorded guest throw.
    if (err == error.OutOfMemory) return err;
    if (err == error.JavaScriptException) if (engine.captured_exception) |captured| {
        if (c.pi_js_native_allocation_error_generation(captured) != 0) return error.OutOfMemory;
    };
    const value = reason(engine, err); defer engine.freeValue(value);
    try settle(engine, owner, true, value);
}
