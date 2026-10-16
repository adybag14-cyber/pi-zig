//! Per-invocation state for genuine resumable native AsyncFunction bodies.
//! These private records describe one VM Await/return/throw; no Promise is made.
const v = @import("native_ai_provider_values.zig");
const c = v.c;
const Scope = v.Scope;
pub const native = @import("native_async_function.zig");
const flow = @import("native_agent_async.zig");
const Kind = enum(i32) { returned, awaited, thrown };
pub fn init(s: *Scope, state: *c.JSValue) !c.JSValue {
    // This owner records native lexical locals, never a Source-visible object.
    // Missing locals and assignments must not consult guest Object.prototype.
    const job = try s.own(try s.engine.checked(c.JS_NewObjectProto(s.engine.context, c.pi_js_null())));
    native.replaceState(s.engine, state, c.JS_DupValue(s.engine.context, job));
    return job;
}
fn set(s: *Scope, job: c.JSValue, kind: Kind, value: c.JSValue) !void {
    try s.put(job, "nativeAsyncAction", c.JS_NewInt32(s.engine.context, @intFromEnum(kind)));
    try s.put(job, "nativeAsyncValue", value);
}
pub fn wait(s: *Scope, job: c.JSValue, value: c.JSValue, next_stage: c_int) !void {
    try s.put(job, "nativeAsyncStage", c.JS_NewInt32(s.engine.context, next_stage));
    try set(s, job, .awaited, value);
}
pub fn resolve(s: *Scope, job: c.JSValue, value: c.JSValue) !void {
    try set(s, job, .returned, value);
}
pub fn reject(s: *Scope, job: c.JSValue, value: c.JSValue) !void {
    try set(s, job, .thrown, value);
}
pub fn stage(s: *Scope, job: c.JSValue) !c_int {
    var result: i32 = 0;
    if (c.JS_ToInt32(s.engine.context, &result, try s.get(job, "nativeAsyncStage")) < 0) return v.js.capture(s.engine);
    return result;
}
pub fn action(s: *Scope, job: c.JSValue) !native.Action {
    var kind: i32 = 0;
    if (c.JS_ToInt32(s.engine.context, &kind, try s.get(job, "nativeAsyncAction")) < 0) return v.js.capture(s.engine);
    const value = c.JS_DupValue(s.engine.context, try s.get(job, "nativeAsyncValue"));
    return switch (@as(Kind, @enumFromInt(kind))) {
        .returned => .{ .returned = value },
        .awaited => .{ .awaited = value },
        .thrown => .{ .thrown = value },
    };
}
pub fn failure(engine: *v.em.Engine, err: anyerror) anyerror!native.Action {
    // Only a trusted classified host failure enters the primitive's scoped
    // uncatchable path. Guest names/messages and old native tags are irrelevant.
    if (err == error.OutOfMemory) return err;
    if (err == error.JavaScriptException) if (engine.captured_exception) |reason| {
        if (c.JS_IsUncatchableError(reason)) return error.JavaScriptException;
    };
    return .{ .thrown = flow.reason(engine, err) };
}
/// The caller snapshots generation before the fallible host/guest boundary.
/// Engine classification excludes historical tags and guest lookalikes.
pub fn failureSince(engine: *v.em.Engine, err: anyerror, generation: u64) anyerror!native.Action {
    return failure(engine, engine.nativeAllocationError(err, generation));
}

/// A rejected value is trusted only when its private allocation tag was born
/// inside the caller's explicit host boundary. Preserve Engine's unsigned wrap
/// rule and rethrow that exact value; never allocate a replacement error.
/// Historical or guest lookalike reasons return normally to Source's catch.
pub fn rethrowRecognizedAllocation(engine: *v.em.Engine, reason: c.JSValue, boundary_generation: u64) !void {
    const tagged = c.pi_js_native_allocation_error_generation(reason);
    const distance = tagged -% boundary_generation;
    if (tagged == 0 or distance == 0 or distance > engine.native_allocation_generation -% boundary_generation) return;
    c.JS_SetUncatchableError(engine.context, reason);
    engine.native_exception_diagnostics_suppressed += 1;
    defer engine.native_exception_diagnostics_suppressed -= 1;
    _ = try engine.checked(c.JS_Throw(engine.context, c.JS_DupValue(engine.context, reason)));
    unreachable;
}
