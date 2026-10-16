//! Actual Source createEventBus over the qualified native EventEmitter.
const em = @import("engine.zig");
const sdk = @import("native_sdk.zig");
const js = @import("native_js_values.zig");
const Scope = @import("native_sdk_prompt_scope.zig").Scope;
const flow = @import("native_agent_async.zig");
const c = em.c;
const Method = enum(c_int) { emit, on, clear, unsubscribe };
pub fn create(engine: *em.Engine) !c.JSValue {
    if (!engine.native_module_values.contains("node:events")) try @import("node_events.zig").install(engine);
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const constructor = try scope.get(engine.native_module_values.get("node:events").?, "EventEmitter");
    const emitter = try scope.own(try engine.checked(c.JS_CallConstructor(engine.context, constructor, 0, null)));
    const result = try scope.object();
    inline for (.{ Method.emit, .on, .clear }) |kind| {
        var roots = [_]c.JSValue{emitter};
        const function = try scope.own(try engine.checked(c.JS_NewCFunctionData2(engine.context, dispatch, @tagName(kind), if (kind == .clear) 0 else 2, @intFromEnum(kind), roots.len, &roots)));
        try scope.put(result, @tagName(kind), function);
    }
    return c.JS_DupValue(engine.context, result);
}
fn dispatch(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, magic: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    return method(engine, @enumFromInt(magic), roots, if (argc > 0) argv[0..@intCast(argc)] else &.{}) catch |err| sdk.fail(engine, err);
}
fn method(engine: *em.Engine, kind: Method, roots: [*c]c.JSValue, args: []const c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const first = if (args.len > 0) args[0] else c.pi_js_undefined();
    const second = if (args.len > 1) args[1] else c.pi_js_undefined();
    switch (kind) {
        .emit => _ = try scope.invoke(roots[0], "emit", &.{ first, second }),
        .clear => _ = try scope.invoke(roots[0], "removeAllListeners", &.{}),
        .unsubscribe => return c.JS_DupValue(engine.context, try scope.invoke(roots[0], "off", &.{ roots[1], roots[2] })),
        .on => {
            var handler_roots = [_]c.JSValue{ first, second };
            const handler = try scope.own(try engine.checked(c.JS_NewCFunctionData2(engine.context, safeHandler, "safeHandler", 1, 0, handler_roots.len, &handler_roots)));
            const async_parent = try scope.own(try engine.checked(c.JS_GetAsyncFunctionPrototype(engine.context)));
            if (c.JS_SetPrototype(engine.context, handler, async_parent) < 0) return js.capture(engine);
            _ = try scope.invoke(roots[0], "on", &.{ first, handler });
            var unsubscribe_roots = [_]c.JSValue{ roots[0], first, handler };
            const unsubscribe = try scope.own(try engine.checked(c.JS_NewCFunctionData2(engine.context, dispatch, "", 0, @intFromEnum(Method.unsubscribe), unsubscribe_roots.len, &unsubscribe_roots)));
            return c.JS_DupValue(engine.context, unsubscribe);
        },
    }
    return c.pi_js_undefined();
}
fn safeHandler(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    engine.native_exception_diagnostics_suppressed += 1;
    defer engine.native_exception_diagnostics_suppressed -= 1;
    return start(engine, roots[0], roots[1], if (argc > 0) argv[0] else c.pi_js_undefined()) catch |err| sdk.fail(engine, err);
}
fn start(engine: *em.Engine, channel: c.JSValue, handler: c.JSValue, data: c.JSValue) !c.JSValue {
    const pending = try flow.create(engine, handler);
    defer engine.freeValue(pending.owner);
    errdefer engine.freeValue(pending.promise);
    initialize(engine, pending.owner, channel, data) catch |err| {
        const reason = flow.reason(engine, err);
        defer engine.freeValue(reason);
        caught(engine, pending.owner, reason) catch |failure| try flow.rejectError(engine, pending.owner, failure);
    };
    return pending.promise;
}
fn initialize(engine: *em.Engine, owner: c.JSValue, channel: c.JSValue, data: c.JSValue) !void {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    try scope.put(owner, "channel", channel);
    const handler = try scope.get(owner, "agent");
    try flow.wait(done, engine, owner, try scope.call(handler, c.pi_js_undefined(), &.{data}), 0);
}
fn done(engine: *em.Engine, owner: c.JSValue, value: c.JSValue, rejected: bool, _: c_int) !void {
    if (rejected) return caught(engine, owner, value);
    try flow.settle(engine, owner, false, c.pi_js_undefined());
}
fn caught(engine: *em.Engine, owner: c.JSValue, reason: c.JSValue) !void {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const console = try scope.global("console");
    const error_method = try scope.get(console, "error");
    const message = try scope.concat(try scope.concat(try scope.text("Event handler error ("), try scope.stringify(try scope.get(owner, "channel"))), try scope.text("):"));
    _ = try scope.call(error_method, console, &.{ message, reason });
    try flow.settle(engine, owner, false, c.pi_js_undefined());
}
