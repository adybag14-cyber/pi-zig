//! SDK state-machine compatibility surface over the one shared action recorder.
//! No Promise or continuation job is allocated here. The genuine AsyncFunction
//! Body selects its continuation on VM resume and emits exactly one action.
const em = @import("engine.zig");
const Scope = @import("native_models_stream_scope.zig").Scope;
const c = em.c;
pub const body = @import("native_async_body.zig");
pub const native = body.native;
pub const reason = @import("native_agent_async.zig").reason;
pub fn init(scope: *Scope, state: *c.JSValue) !c.JSValue {
    const generation = scope.engine.native_allocation_generation;
    const owner = try body.init(scope, state);
    try scope.put(owner, "nativeSdkAllocationBoundaryLow", c.JS_NewUint32(scope.engine.context, @truncate(generation)));
    try scope.put(owner, "nativeSdkAllocationBoundaryHigh", c.JS_NewUint32(scope.engine.context, @truncate(generation >> 32)));
    return owner;
}
fn boundary(scope: *Scope, owner: c.JSValue) !u64 {
    const low_value = try scope.get(owner, "nativeSdkAllocationBoundaryLow");
    const high_value = try scope.get(owner, "nativeSdkAllocationBoundaryHigh");
    if (!c.JS_IsNumber(low_value) or !c.JS_IsNumber(high_value)) return error.NativeSdkAsyncAllocationBoundaryMissing;
    var low: u32 = 0; var high: u32 = 0;
    if (c.JS_ToUint32(scope.engine.context, &low, low_value) < 0 or c.JS_ToUint32(scope.engine.context, &high, high_value) < 0) return @import("native_js_values.zig").capture(scope.engine);
    return (@as(u64, high) << 32) | low;
}
pub fn nativeAllocationReason(engine: *em.Engine, owner: c.JSValue, value: c.JSValue) !bool {
    const tagged = c.pi_js_native_allocation_error_generation(value);
    if (tagged == 0) return false;
    var scope: Scope = .{ .engine = engine }; defer scope.deinit();
    const generation = try boundary(&scope, owner);
    const distance = tagged -% generation;
    return distance != 0 and distance <= engine.native_allocation_generation -% generation;
}
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
    if (try nativeFailure(engine, owner, err)) return error.OutOfMemory;
    const value = reason(engine, err); defer engine.freeValue(value);
    try settle(engine, owner, true, value);
}
pub fn nativeFailure(engine: *em.Engine, owner: c.JSValue, err: anyerror) !bool {
    if (err == error.OutOfMemory) return true;
    var scope: Scope = .{ .engine = engine }; defer scope.deinit();
    return engine.nativeAllocationError(err, try boundary(&scope, owner)) == error.OutOfMemory;
}
