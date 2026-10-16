//! Per-invocation state for genuine resumable native AsyncFunction bodies.
//! These private records describe one VM Await/return/throw; no Promise is made.
const v = @import("native_ai_provider_values.zig");
const c = v.c;
const Scope = v.Scope;
pub const native = @import("native_async_function.zig");
const flow = @import("native_agent_async.zig");
const Kind = enum(i32) { returned, awaited, thrown };
pub fn init(s: *Scope, state: *c.JSValue) !c.JSValue {
    const job = try s.object();
    native.replaceState(s.engine, state, c.JS_DupValue(s.engine.context, job));
    return job;
}
fn set(s: *Scope, job: c.JSValue, kind: Kind, value: c.JSValue) !void {
    try s.put(job, "nativeAsyncAction", c.JS_NewInt32(s.engine.context, @intFromEnum(kind)));
    try s.put(job, "nativeAsyncValue", value);
}
pub fn wait(s: *Scope, job: c.JSValue, value: c.JSValue, stage: c_int) !void {
    try s.put(job, "nativeAsyncStage", c.JS_NewInt32(s.engine.context, stage));
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
pub fn failure(engine: *v.em.Engine, err: anyerror) native.Action {
    return .{ .thrown = flow.reason(engine, err) };
}
