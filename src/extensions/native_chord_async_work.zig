//! Intrinsic async-method capability and stage ownership for the actual v4 graph.
//! A stage schedules its next await and returns void, avoiding public .then
//! assimilation of a nested native await promise. Guest-returned values still
//! resolve through the actual intrinsic resolving function.
const h = @import("native_chord_host_values.zig");
const js = h.js;
const c = h.c;
pub const Scope = h.Scope;
pub const Next = *const fn (*h.Engine, c.JSValue, c.JSValue, bool, c_int) anyerror!void;
pub fn create(s: *Scope) !c.JSValue {
    const work = try s.record();
    var functions: [2]c.JSValue = undefined;
    const promise = try s.engine.checked(c.JS_NewPromiseCapability(s.engine.context, &functions));
    defer s.engine.freeValue(promise);
    defer for (functions) |function| s.engine.freeValue(function);
    try h.field(s, work, "promise", promise);
    try h.field(s, work, "resolve", functions[0]);
    try h.field(s, work, "reject", functions[1]);
    return work;
}
pub fn result(s: *Scope, work: c.JSValue) !c.JSValue {
    return s.result(try s.get(work, "promise"));
}
pub fn complete(s: *Scope, work: c.JSValue, value: c.JSValue, rejected: bool) !void {
    _ = try s.keep(try js.call(s.engine, try s.get(work, if (rejected) "reject" else "resolve"), c.pi_js_undefined(), &.{value}));
}
pub fn rejectError(s: *Scope, work: c.JSValue, err: anyerror) !void {
    _ = @import("native_durable.zig").reject(s.engine, err);
    const reason = try s.keep(c.JS_GetException(s.engine.context));
    try complete(s, work, reason, true);
}
pub fn rejectErrorSince(s: *Scope, work: c.JSValue, err: anyerror, generation: u64) !void {
    const mapped = s.engine.nativeAllocationError(err, generation);
    if (mapped == error.OutOfMemory) return mapped;
    try rejectError(s, work, err);
}
pub fn wait(comptime next: Next, s: *Scope, work: c.JSValue, awaited: c.JSValue, stage: c_int) !void {
    const Adapter = struct {
        fn continueStage(engine: *h.Engine, owned: c.JSValue, value: c.JSValue, rejected: bool, phase: c_int) anyerror!c.JSValue {
            const generation = engine.native_allocation_generation;
            next(engine, owned, value, rejected, phase) catch |err| {
                // Preserve the existing narrow fresh-native-failure escape in
                // h.wait; ordinary and stale guest values reject this method.
                if (engine.nativeAllocationError(err, generation) == error.OutOfMemory) return err;
                var scope: Scope = .{ .engine = engine };
                defer scope.deinit();
                try rejectError(&scope, owned, err);
            };
            return c.pi_js_undefined();
        }
    };
    const continuation = try h.wait(Adapter.continueStage, s.engine, work, awaited, stage);
    s.engine.freeValue(continuation);
}
