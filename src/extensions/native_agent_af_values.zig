//! Operation-local values/ownership for actual Agent native AF bodies.
const em = @import("engine.zig");
pub const Scope = @import("native_sdk_prompt_scope.zig").Scope;
pub const c = em.c;
pub const body = @import("native_async_body.zig");
pub const af = body.native;
fn pendingFirst(engine: *em.Engine, err: anyerror) anyerror {
    if (err == error.JavaScriptException and c.JS_HasException(engine.context)) {
        const reason = c.JS_GetException(engine.context);
        _ = engine.checked(c.JS_Throw(engine.context, reason)) catch |current| return current;
        unreachable;
    }
    return err;
}
pub fn guard(engine: *em.Engine, generation: u64, result: anyerror!c.JSValue) anyerror!c.JSValue {
    return result catch |err| {
        const current = pendingFirst(engine, err);
        if (current == error.JavaScriptException) if (engine.captured_exception) |reason| try body.rethrowRecognizedAllocation(engine, reason, generation);
        return current;
    };
}
pub fn get(s: *Scope, object: c.JSValue, name: [*:0]const u8) !c.JSValue { const generation = s.engine.native_allocation_generation; return guard(s.engine, generation, s.get(object, name)); }
pub fn global(s: *Scope, name: [*:0]const u8) !c.JSValue { const generation = s.engine.native_allocation_generation; return guard(s.engine, generation, s.global(name)); }
pub fn call(s: *Scope, function: c.JSValue, receiver: c.JSValue, args: []const c.JSValue) !c.JSValue { const generation = s.engine.native_allocation_generation; return guard(s.engine, generation, s.call(function, receiver, args)); }
pub fn invoke(s: *Scope, receiver: c.JSValue, name: [*:0]const u8, args: []const c.JSValue) !c.JSValue { return call(s, try get(s, receiver, name), receiver, args); }
pub fn set(s: *Scope, target: c.JSValue, name: [*:0]const u8, value: c.JSValue) !void {
    const generation = s.engine.native_allocation_generation;
    s.set(target, name, value) catch |err| {
        const current = pendingFirst(s.engine, err);
        if (current == error.JavaScriptException) if (s.engine.captured_exception) |reason| try body.rethrowRecognizedAllocation(s.engine, reason, generation);
        return current;
    };
}
pub fn construct(s: *Scope, constructor: c.JSValue, args: []const c.JSValue) !c.JSValue {
    const generation = s.engine.native_allocation_generation;
    return s.own(try guard(s.engine, generation, s.engine.checked(c.JS_CallConstructor(s.engine.context, constructor, @intCast(args.len), @constCast(args.ptr)))));
}
pub fn init(s: *Scope, slot: *c.JSValue) !c.JSValue {
    const owner = try s.own(try s.engine.checked(c.JS_NewObjectProto(s.engine.context, c.pi_js_null())));
    af.replaceState(s.engine, slot, c.JS_DupValue(s.engine.context, owner));
    return owner;
}
pub fn stage(s: *Scope, owner: c.JSValue) !i32 { var result: i32 = 0; if (c.JS_ToInt32(s.engine.context, &result, try s.get(owner, "stage")) < 0) return @import("native_js_values.zig").capture(s.engine); return result; }
pub fn wait(s: *Scope, owner: c.JSValue, function: c.JSValue, receiver: c.JSValue, args: []const c.JSValue, next: i32) !af.Action {
    try s.put(owner, "stage", c.JS_NewInt32(s.engine.context, next));
    const generation = s.engine.native_allocation_generation;
    try s.put(owner, "awaitGeneration", try s.own(try s.engine.checked(c.JS_NewBigUint64(s.engine.context, generation))));
    return .{ .awaited = c.JS_DupValue(s.engine.context, try call(s, function, receiver, args)) };
}
pub fn rejected(s: *Scope, owner: c.JSValue, reason: c.JSValue) !void {
    var generation: u64 = 0;
    if (c.JS_ToBigUint64(s.engine.context, &generation, try s.get(owner, "awaitGeneration")) < 0) return @import("native_js_values.zig").capture(s.engine);
    try body.rethrowRecognizedAllocation(s.engine, reason, generation);
}
pub fn caught(engine: *em.Engine, err: anyerror) !c.JSValue {
    const current = pendingFirst(engine, err);
    if (current == error.OutOfMemory) return current;
    if (current == error.JavaScriptException) if (engine.captured_exception) |reason| {
        if (c.JS_IsUncatchableError(reason)) return current;
        engine.captured_exception = null;
        return reason;
    };
    const action = try body.failure(engine, current);
    return switch (action) { .thrown => |reason| reason, else => error.UnexpectedAgentFailureAction };
}
pub fn failure(engine: *em.Engine, err: anyerror) !af.Action { return .{ .thrown = try caught(engine, err) }; }
pub fn raise(s: *Scope, message: []const u8) !c.JSValue {
    const constructor = try global(s, "Error");
    const reason = try construct(s, constructor, &.{try s.text(message)});
    return s.engine.checked(c.JS_Throw(s.engine.context, c.JS_DupValue(s.engine.context, reason)));
}
/// Ordinary Source callbacks (Promise executor/emitter) must not let the global
/// Promise constructor swallow a direct trusted GPA failure before AF sees it.
pub fn callbackFailure(engine: *em.Engine, err: anyerror) anyerror {
    if (err != error.OutOfMemory) return err;
    _ = engine.throwNativeOutOfMemory();
    const reason = c.JS_GetException(engine.context);
    c.JS_SetUncatchableError(engine.context, reason);
    _ = engine.checked(c.JS_Throw(engine.context, reason)) catch |failure_error| return failure_error;
    unreachable;
}
