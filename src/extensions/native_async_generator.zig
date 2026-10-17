//! Native bodies on QuickJS's real AsyncGenerator queue, brand and Await path.
//! Review-only C ABI candidate; production integration waits for qualification.
const em = @import("engine.zig");
const c = em.c;
pub const Completion = enum(c_int) {
    start = c.JS_PI_AG_START,
    next = c.JS_PI_AG_NEXT,
    returned = c.JS_PI_AG_RETURN_INPUT,
    thrown = c.JS_PI_AG_THROW_INPUT,
    fulfilled = c.JS_PI_AG_AWAIT_FULFILLED,
    rejected = c.JS_PI_AG_AWAIT_REJECTED,
};
/// Every payload is owned. Await/yield/return are real suspensions; complete
/// means a bare/implicit return or a completion whose expression was awaited
/// explicitly by the native body (e.g. before executing a finally clause).
pub const Action = union(enum) {
    awaited: c.JSValue,
    yielded: c.JSValue,
    returned: c.JSValue,
    complete: c.JSValue,
    thrown: c.JSValue,
};
pub const Resume = *const fn (*em.Engine, c.JSValue, Completion, c.JSValue) anyerror!Action;
pub fn create(engine: *em.Engine, owner: c.JSValue, comptime body: Resume, instance_prototype: c.JSValue) !c.JSValue {
    const Adapter = struct {
        fn call(context: ?*c.JSContext, state: c.JSValue, raw: c_int, input: c.JSValue, action: [*c]c_int) callconv(.c) c.JSValue {
            const host = em.Engine.fromContext(context.?);
            host.checkNativeEntry() catch return host.throwCaptured();
            host.native_exception_diagnostics_suppressed += 1;
            defer host.native_exception_diagnostics_suppressed -= 1;
            var invocation: em.Engine.NativeInvocation = .{};
            host.enterNativeInvocation(&invocation);
            const value = invokeStep(host, state, raw, input, action);
            return host.leaveNativeInvocation(&invocation, value);
        }
        fn invokeStep(host: *em.Engine, state: c.JSValue, raw: c_int, input: c.JSValue, action: [*c]c_int) c.JSValue {
            const step = body(host, state, @enumFromInt(raw), input) catch |err| return @import("native_sdk.zig").fail(host, err);
            return switch (step) {
                .awaited => |value| result(action, c.JS_PI_AG_AWAIT, value),
                .yielded => |value| result(action, c.JS_PI_AG_YIELD, value),
                .returned => |value| result(action, c.JS_PI_AG_RETURN, value),
                .complete => |value| result(action, c.JS_PI_AG_COMPLETE, value),
                .thrown => |value| result(action, c.JS_PI_AG_THROW, value),
            };
        }
        fn result(action: [*c]c_int, kind: c_int, value: c.JSValue) c.JSValue {
            action[0] = kind;
            return value;
        }
    };
    return engine.checked(c.JS_PiNewNativeAsyncGenerator(engine.context, owner, Adapter.call, instance_prototype));
}
pub fn prototype(engine: *em.Engine) !c.JSValue {
    return engine.checked(c.JS_PiGetAsyncGeneratorPrototype(engine.context));
}
pub fn functionPrototype(engine: *em.Engine) !c.JSValue {
    return engine.checked(c.JS_PiGetAsyncGeneratorFunctionPrototype(engine.context));
}
