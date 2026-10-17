//! Local portable-SQLite operation ownership; no shared Engine/AF policy edits.
const v = @import("native_ai_provider_values.zig");
pub const c = v.c;
pub const Scope = v.Scope;
pub const Engine = v.em.Engine;
pub const body = @import("native_async_body.zig");
pub const af = body.native;
pub const Captures = struct {
    engine: *Engine,
    prior: ?c.JSValue,
    pub fn enter(engine: *Engine) !Captures {
        // An actual VM event outranks an older diagnostic capture. Normalize
        // it before history isolation or any body effect.
        try pending(engine);
        // A preexisting diagnostic capture has no current-producer ownership.
        // Its flag/tag is historical DATA, not permission to skip this body.
        const prior = engine.captured_exception;
        engine.captured_exception = null;
        return .{ .engine = engine, .prior = prior };
    }
    pub fn deinit(self: *Captures) void {
        if (self.engine.captured_exception == null) self.engine.captured_exception = self.prior else if (self.prior) |old| self.engine.freeValue(old);
    }
};
pub fn pending(engine: *Engine) !void {
    if (c.JS_HasException(engine.context)) return v.js.capture(engine);
}
pub fn success(engine: *Engine, owned: c.JSValue) !c.JSValue {
    if (c.JS_HasException(engine.context)) {
        const reason = c.JS_GetException(engine.context);
        engine.freeValue(owned);
        return engine.checked(c.JS_Throw(engine.context, reason));
    }
    return owned;
}
pub fn get(s: *Scope, receiver: c.JSValue, name: [*:0]const u8) !c.JSValue {
    return s.own(try success(s.engine, try v.js.get(s.engine, receiver, name)));
}
pub fn key(s: *Scope, receiver: c.JSValue, name: c.JSValue) !c.JSValue {
    return s.own(try success(s.engine, try v.js.getKey(s.engine, receiver, name)));
}
pub fn call(s: *Scope, function: c.JSValue, receiver: c.JSValue, args: []const c.JSValue) !c.JSValue {
    return s.own(try success(s.engine, try v.js.call(s.engine, function, receiver, args)));
}
pub fn invoke(s: *Scope, receiver: c.JSValue, name: [*:0]const u8, args: []const c.JSValue) !c.JSValue {
    return call(s, try get(s, receiver, name), receiver, args);
}
pub fn put(engine: *Engine, receiver: c.JSValue, name: [*:0]const u8, borrowed: c.JSValue) !void {
    if (c.JS_DefinePropertyValueStr(engine.context, receiver, name, c.JS_DupValue(engine.context, borrowed), c.JS_PROP_C_W_E | c.JS_PROP_THROW) < 0) return v.js.capture(engine);
    try pending(engine);
}
pub fn binary(s: *Scope, op: c_int, left: c.JSValue, right: c.JSValue) !c.JSValue {
    return s.own(try success(s.engine, try s.engine.checked(c.JS_PiBinaryOperator(s.engine.context, op, left, right))));
}
pub fn text(s: *Scope, value: c.JSValue) !c.JSValue {
    return s.own(try success(s.engine, try s.engine.checked(c.JS_ToString(s.engine.context, value))));
}
pub fn errorText(s: *Scope, message: c.JSValue) anyerror {
    const constructor = s.own(success(s.engine, v.js.global(s.engine, "Error") catch |err| return err) catch |err| return err) catch |err| return err;
    var arguments = [_]c.JSValue{message};
    const reason = s.own(success(s.engine, s.engine.checked(c.JS_CallConstructor(s.engine.context, constructor, 1, &arguments)) catch |err| return err) catch |err| return err) catch |err| return err;
    _ = s.engine.checked(c.JS_Throw(s.engine.context, c.JS_DupValue(s.engine.context, reason))) catch |err| return err;
    unreachable;
}
pub fn arg(args: []const c.JSValue, index: usize) c.JSValue {
    return if (index < args.len) args[index] else c.pi_js_undefined();
}
pub fn wait(s: *Scope, job: c.JSValue, next_stage: i32, borrowed: c.JSValue) !af.Action {
    try put(s.engine, job, "stage", c.JS_NewInt32(s.engine.context, next_stage));
    return .{ .awaited = c.JS_DupValue(s.engine.context, borrowed) };
}
pub fn stage(s: *Scope, job: c.JSValue) !i32 {
    var result: i32 = 0;
    if (c.JS_ToInt32(s.engine.context, &result, try get(s, job, "stage")) < 0) return v.js.capture(s.engine);
    return result;
}
pub fn take(engine: *Engine, err: anyerror, generation: u64) !c.JSValue {
    if (err != error.JavaScriptException) return err;
    if (engine.captured_exception == null) try pending(engine);
    const reason = engine.captured_exception orelse return error.MissingCurrentSqliteCapturedReason;
    if (c.JS_IsUncatchableError(reason)) return err;
    try body.rethrowRecognizedAllocation(engine, reason, generation);
    engine.captured_exception = null;
    return reason;
}
pub fn failure(engine: *Engine, err: anyerror, generation: u64) !af.Action {
    return .{ .thrown = try take(engine, err, generation) };
}
