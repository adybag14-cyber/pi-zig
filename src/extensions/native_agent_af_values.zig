//! Operation-local values/ownership for actual Agent native AF bodies.
const em = @import("engine.zig");
pub const Scope = @import("native_sdk_prompt_scope.zig").Scope;
pub const c = em.c;
pub const body = @import("native_async_body.zig");
pub const af = body.native;
const roots = @import("native_sdk_owned_completion.zig");

/// Must remain at its caller's stable address from begin through finish.
/// Guest spans never classify allocation generations or captured DATA flags.
pub const GuestOperation = struct {
    invocation: em.Engine.NativeInvocation = .{},
    pub fn begin(self: *GuestOperation, engine: *em.Engine) !void {
        engine.enterNativeInvocation(&self.invocation);
        engine.checkNativeEntry() catch |err| {
            _ = self.finish(engine, @as(anyerror!c.JSValue, err)) catch |failure_error| return failure_error;
            unreachable;
        };
    }
    /// result is BORROWED or an error. Only owned undefined enters consuming
    /// leaveNativeInvocation; Scope roots remain owned by their caller.
    pub fn finish(self: *GuestOperation, engine: *em.Engine, result: anyerror!c.JSValue) anyerror!c.JSValue {
        const selected = result catch |err| {
            const failure_error = if (err == error.OutOfMemory) callbackFailure(engine, err) else err;
            _ = try engine.checked(engine.leaveNativeInvocation(&self.invocation, c.pi_js_undefined()));
            return failure_error;
        };
        _ = try engine.checked(engine.leaveNativeInvocation(&self.invocation, c.pi_js_undefined()));
        return selected;
    }
};
/// Compatibility for already-evaluated operations, including borrowed Scope
/// values. Cannot establish a pre-guest boundary. generation is NOT authority.
pub fn guard(engine: *em.Engine, _: u64, result: anyerror!c.JSValue) anyerror!c.JSValue {
    const selected = result catch |err| {
        if (err == error.OutOfMemory) return callbackFailure(engine, err);
        try engine.checkNativeEntry();
        return err;
    };
    try engine.checkNativeEntry();
    return selected;
}
pub fn get(s: *Scope, object: c.JSValue, name: [*:0]const u8) !c.JSValue {
    var operation: GuestOperation = .{}; try operation.begin(s.engine);
    return operation.finish(s.engine, retain(s, c.JS_GetPropertyStr(s.engine.context, object, name)));
}
pub fn getKey(s: *Scope, object: c.JSValue, key: c.JSValue) !c.JSValue {
    var operation: GuestOperation = .{}; try operation.begin(s.engine);
    return operation.finish(s.engine, retainKey(s, object, key));
}
fn retainKey(s: *Scope, object: c.JSValue, key: c.JSValue) !c.JSValue {
    const atom = c.JS_ValueToAtom(s.engine.context, key);
    if (atom == c.JS_ATOM_NULL) return @import("native_js_values.zig").capture(s.engine);
    defer c.JS_FreeAtom(s.engine.context, atom);
    try s.engine.checkNativeEntry();
    return retain(s, c.JS_GetProperty(s.engine.context, object, atom));
}
fn retain(s: *Scope, owned: c.JSValue) !c.JSValue {
    return roots.ownRoot(s, try s.engine.checked(owned));
}
pub fn global(s: *Scope, name: [*:0]const u8) !c.JSValue {
    var operation: GuestOperation = .{}; try operation.begin(s.engine);
    return operation.finish(s.engine, globalValue(s, name));
}
fn globalValue(s: *Scope, name: [*:0]const u8) !c.JSValue {
    const object = try retain(s, c.JS_GetGlobalObject(s.engine.context));
    return retain(s, c.JS_GetPropertyStr(s.engine.context, object, name));
}
pub fn call(s: *Scope, function: c.JSValue, receiver: c.JSValue, args: []const c.JSValue) !c.JSValue {
    var operation: GuestOperation = .{}; try operation.begin(s.engine);
    return operation.finish(s.engine, retain(s, c.JS_Call(s.engine.context, function, receiver, @intCast(args.len), @constCast(args.ptr))));
}
pub fn invoke(s: *Scope, receiver: c.JSValue, name: [*:0]const u8, args: []const c.JSValue) !c.JSValue { return call(s, try get(s, receiver, name), receiver, args); }
pub fn set(s: *Scope, target: c.JSValue, name: [*:0]const u8, value: c.JSValue) !void {
    var operation: GuestOperation = .{}; try operation.begin(s.engine);
    const status = c.JS_SetPropertyStr(s.engine.context, target, name, c.JS_DupValue(s.engine.context, value));
    _ = try operation.finish(s.engine, if (status < 0) @import("native_js_values.zig").capture(s.engine) else c.pi_js_undefined());
}
pub fn construct(s: *Scope, constructor: c.JSValue, args: []const c.JSValue) !c.JSValue {
    var operation: GuestOperation = .{}; try operation.begin(s.engine);
    return operation.finish(s.engine, retain(s, c.JS_CallConstructor(s.engine.context, constructor, @intCast(args.len), @constCast(args.ptr))));
}
pub fn instanceOf(s: *Scope, value: c.JSValue, constructor: c.JSValue) !bool {
    var operation: GuestOperation = .{}; try operation.begin(s.engine);
    const status = c.JS_IsInstanceOf(s.engine.context, value, constructor);
    _ = try operation.finish(s.engine, if (status < 0) @import("native_js_values.zig").capture(s.engine) else c.pi_js_undefined());
    return status != 0;
}
pub fn binary(s: *Scope, opcode: c_int, left: c.JSValue, right: c.JSValue) !c.JSValue {
    var operation: GuestOperation = .{}; try operation.begin(s.engine);
    return operation.finish(s.engine, retain(s, c.JS_PiBinaryOperator(s.engine.context, opcode, left, right)));
}
pub fn positive(s: *Scope, value: c.JSValue) !bool {
    return s.truthy(try binary(s, 6, value, c.JS_NewInt32(s.engine.context, 0)));
}
pub fn init(s: *Scope, slot: *c.JSValue) !c.JSValue {
    const owner = try s.own(try s.engine.checked(c.JS_NewObjectProto(s.engine.context, c.pi_js_null())));
    af.replaceState(s.engine, slot, c.JS_DupValue(s.engine.context, owner));
    return owner;
}
pub fn stage(s: *Scope, owner: c.JSValue) !i32 { var result: i32 = 0; if (c.JS_ToInt32(s.engine.context, &result, try s.get(owner, "stage")) < 0) return @import("native_js_values.zig").capture(s.engine); return result; }
pub fn wait(s: *Scope, owner: c.JSValue, function: c.JSValue, receiver: c.JSValue, args: []const c.JSValue, next: i32) !af.Action {
    try s.put(owner, "stage", c.JS_NewInt32(s.engine.context, next));
    return .{ .awaited = c.JS_DupValue(s.engine.context, try call(s, function, receiver, args)) };
}
pub fn rejected(s: *Scope, _: c.JSValue, _: c.JSValue) !void {
    try body.enterRejectedContinuation(s.engine);
}
pub fn caught(engine: *em.Engine, err: anyerror) !c.JSValue {
    // A trusted typed allocation failure is materialized before ordinary
    // cleanup pending can downgrade it. No diagnostic flags are consulted.
    if (err == error.OutOfMemory) return callbackFailure(engine, err);
    var current = err;
    const actual = engine.nativeCallbackResult(c.pi_js_undefined());
    if (c.JS_IsException(actual) and c.JS_HasException(engine.context)) {
        const reason = c.JS_GetException(engine.context);
        const fatal = c.JS_IsUncatchableError(reason); // ACTUAL pending event.
        _ = engine.checked(c.JS_Throw(engine.context, reason)) catch |capture_error| capture: {
            if (fatal) return capture_error;
            break :capture c.pi_js_undefined();
        };
        current = error.JavaScriptException;
    }
    // Capture/diagnostic retirement can itself publish a genuine producer.
    // Test current provenance again before moving diagnostic-only DATA.
    try engine.checkNativeEntry();
    if (current == error.JavaScriptException) if (engine.captured_exception) |reason| {
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
    _ = engine.throwNativeOutOfMemoryFatal();
    const reason = c.JS_GetException(engine.context);
    c.JS_SetUncatchableError(engine.context, reason);
    _ = engine.checked(c.JS_Throw(engine.context, reason)) catch |failure_error| return failure_error;
    unreachable;
}
