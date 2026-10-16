//! Intrinsic async continuations used by actual Agent method bodies.
//! Private JS owner graphs are retained directly by VM function data.
const em = @import("engine.zig");
const sdk = @import("native_sdk.zig");
const js = @import("native_js_values.zig");
const c = em.c;

pub const Pending = struct { owner: c.JSValue, promise: c.JSValue };
pub fn create(engine: *em.Engine, agent: c.JSValue) !Pending {
    var functions: [2]c.JSValue = undefined;
    const promise = try engine.checked(c.JS_NewPromiseCapability(engine.context, &functions));
    errdefer engine.freeValue(promise);
    defer for (functions) |function| engine.freeValue(function);
    const owner = try sdk.object(engine);
    errdefer engine.freeValue(owner);
    try sdk.put(engine, owner, "agent", c.JS_DupValue(engine.context, agent));
    try sdk.put(engine, owner, "resolve", c.JS_DupValue(engine.context, functions[0]));
    try sdk.put(engine, owner, "reject", c.JS_DupValue(engine.context, functions[1]));
    return .{ .owner = owner, .promise = promise };
}

pub fn wait(comptime step: *const fn (*em.Engine, c.JSValue, c.JSValue, bool, c_int) anyerror!void, engine: *em.Engine, owner: c.JSValue, value: c.JSValue, stage: c_int) !void {
    const Adapter = struct {
        fn continuation(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, magic: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
            const host = em.Engine.fromContext(context.?);
            host.native_exception_diagnostics_suppressed += 1;
            defer host.native_exception_diagnostics_suppressed -= 1;
            step(host, roots[0], if (argc > 0) argv[0] else c.pi_js_undefined(), @mod(magic, 2) != 0, @divTrunc(magic, 2)) catch |err| {
                rejectError(host, roots[0], err) catch |failure| return sdk.fail(host, failure);
            };
            return c.pi_js_undefined();
        }
    };
    const awaited = try engine.checked(c.JS_PiPromiseResolve(engine.context, value));
    defer engine.freeValue(awaited);
    var roots = [_]c.JSValue{owner};
    const fulfilled = try engine.checked(c.JS_NewCFunctionData2(engine.context, Adapter.continuation, "", 1, stage * 2, roots.len, &roots));
    defer engine.freeValue(fulfilled);
    const rejected = try engine.checked(c.JS_NewCFunctionData2(engine.context, Adapter.continuation, "", 1, stage * 2 + 1, roots.len, &roots));
    defer engine.freeValue(rejected);
    const ignored = try engine.checked(c.JS_PromiseThen(engine.context, awaited, fulfilled, rejected));
    engine.freeValue(ignored);
}

pub fn settle(engine: *em.Engine, owner: c.JSValue, rejected: bool, value: c.JSValue) !void {
    const callback = try sdk.get(engine, owner, if (rejected) "reject" else "resolve");
    defer engine.freeValue(callback);
    const ignored = try js.call(engine, callback, c.pi_js_undefined(), &.{value});
    engine.freeValue(ignored);
}

pub fn rejectError(engine: *em.Engine, owner: c.JSValue, err: anyerror) !void {
    const raw = reason(engine, err);
    defer engine.freeValue(raw);
    @import("std").debug.print("DIAG_FLOW_REJECT err={s} generation={d} raw_tag={d} raw_uncatchable={any} captured_tag={d}\n", .{ @errorName(err), engine.native_allocation_generation, c.pi_js_native_allocation_error_generation(raw), c.JS_IsUncatchableError(raw), if (engine.captured_exception) |value| c.pi_js_native_allocation_error_generation(value) else 0 });
    try settle(engine, owner, true, raw);
}

pub fn reason(engine: *em.Engine, err: anyerror) c.JSValue {
    if (err == error.JavaScriptException and engine.captured_exception != null) return c.JS_DupValue(engine.context, engine.captured_exception.?);
    _ = sdk.fail(engine, err);
    return c.JS_GetException(engine.context);
}
