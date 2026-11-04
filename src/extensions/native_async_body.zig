//! Per-invocation state for genuine resumable native AsyncFunction bodies.
//! These private records describe one VM Await/return/throw; no Promise is made.
const v = @import("native_ai_provider_values.zig");
const c = v.c;
pub const native = @import("native_async_function.zig");
const flow = @import("native_agent_async.zig");
const Kind = enum(i32) { returned, awaited, thrown };
pub fn init(s: anytype, state: *c.JSValue) !c.JSValue {
    // This owner records native lexical locals, never a Source-visible object.
    // Missing locals and assignments must not consult guest Object.prototype.
    const job = try s.own(try s.engine.checked(c.JS_NewObjectProto(s.engine.context, c.pi_js_null())));
    native.replaceState(s.engine, state, c.JS_DupValue(s.engine.context, job));
    return job;
}
fn set(s: anytype, job: c.JSValue, kind: Kind, value: c.JSValue) !void {
    try s.put(job, "nativeAsyncAction", c.JS_NewInt32(s.engine.context, @intFromEnum(kind)));
    try s.put(job, "nativeAsyncValue", value);
}
pub fn wait(s: anytype, job: c.JSValue, value: c.JSValue, next_stage: c_int) !void {
    try s.put(job, "nativeAsyncStage", c.JS_NewInt32(s.engine.context, next_stage));
    try set(s, job, .awaited, value);
}
pub fn resolve(s: anytype, job: c.JSValue, value: c.JSValue) !void {
    try set(s, job, .returned, value);
}
pub fn reject(s: anytype, job: c.JSValue, value: c.JSValue) !void {
    try set(s, job, .thrown, value);
}
pub fn stage(s: anytype, job: c.JSValue) !c_int {
    var result: i32 = 0;
    if (c.JS_ToInt32(s.engine.context, &result, try s.get(job, "nativeAsyncStage")) < 0) return v.js.capture(s.engine);
    return result;
}
pub fn action(s: anytype, job: c.JSValue) !native.Action {
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
    try @import("native_pending_owner.zig").catchFailure(engine, err);
    return .{ .thrown = try flow.reason(engine, err) };
}
/// The stable producer owner supplies actual authority across the operation.
/// A broad host/guest interval cannot classify captured diagnostic DATA.
pub fn failureSince(engine: *v.em.Engine, err: anyerror, _: u64) anyerror!native.Action {
    return failure(engine, err);
}
/// A rejection or captured reason is DATA. Independently owned actual events
/// may still prevent source continuation; no tag/flag on DATA supplies proof.
pub fn rethrowRecognizedAllocation(engine: *v.em.Engine, _: c.JSValue, _: u64) !void {
    try @import("native_pending_owner.zig").checkFatal(engine);
}
/// C3 delivers Await rejection input as borrowed DATA. Actual pending events
/// take precedence; a retained diagnostic/captured value is not a new event.
/// Never inspect, mark or clear flags/private tags on the rejection input.
pub fn enterRejectedContinuation(engine: *v.em.Engine) !void {
    _ = engine.nativeCallbackResult(c.pi_js_undefined());
    if (!c.JS_HasException(engine.context)) return;
    var generic_fatal: bool = false;
    var chosen = c.JS_PiGetExceptionWithFatal(engine.context, &generic_fatal);
    var terminal_abort = c.JS_PiIsExecutionTermination(chosen);
    while (c.JS_HasException(engine.context) or engine.captured_exception != null) {
        if (c.JS_HasException(engine.context)) {
            var next_generic_fatal: bool = false;
            const pending = c.JS_PiGetExceptionWithFatal(engine.context, &next_generic_fatal);
            if (c.JS_PiIsExecutionTermination(pending)) terminal_abort = true;
            if (c.JS_PiNativePendingReplaceClassified(engine.runtime,
                chosen, generic_fatal, pending, next_generic_fatal)) {
                const displaced = chosen;
                chosen = pending;
                generic_fatal = next_generic_fatal;
                engine.freeValue(displaced);
            } else engine.freeValue(pending);
        } else {
            const diagnostic = engine.captured_exception.?;
            engine.captured_exception = null;
            engine.freeValue(diagnostic);
        }
        if (!generic_fatal) _ = engine.nativeCallbackResult(c.pi_js_undefined());
    }
    _ = c.JS_PiThrowNativePending(engine.context, chosen, generic_fatal);
    return if (terminal_abort) error.ExecutionTerminated else error.JavaScriptException;
}
