//! Actual Source createEventBus over the qualified native EventEmitter.
const em = @import("engine.zig");
const sdk = @import("native_sdk.zig");
const js = @import("native_js_values.zig");
const Scope = @import("native_models_stream_scope.zig").Scope;
const flow = @import("native_agent_async.zig");
const body = @import("native_async_body.zig");
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
            const handler = try scope.own(try body.native.createResumableArrow(engine, "safeHandler", 1, safeHandler, &.{ first, second }, c.pi_js_undefined()));
            _ = try scope.invoke(roots[0], "on", &.{ first, handler });
            var unsubscribe_roots = [_]c.JSValue{ roots[0], first, handler };
            const unsubscribe = try scope.own(try engine.checked(c.JS_NewCFunctionData2(engine.context, dispatch, "", 0, @intFromEnum(Method.unsubscribe), unsubscribe_roots.len, &unsubscribe_roots)));
            return c.JS_DupValue(engine.context, unsubscribe);
        },
    }
    return c.pi_js_undefined();
}
fn safeHandler(engine: *em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue, state: *c.JSValue, completion: body.native.Completion, input: c.JSValue) !body.native.Action {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const generation = engine.native_allocation_generation;
    if (completion == .start) {
        const job = try body.init(&scope, state);
        try scope.put(job, "generation", try scope.own(try engine.checked(c.JS_NewBigUint64(engine.context, generation))));
        const value = scope.call(roots[1], c.pi_js_undefined(), &.{if (args.len > 0) args[0] else c.pi_js_undefined()}) catch |err| {
            if (engine.nativeAllocationError(err, generation) == error.OutOfMemory) return error.OutOfMemory;
            const reason = try scope.own(flow.reason(engine, err));
            try caught(&scope, roots[0], reason);
            return .{ .returned = c.pi_js_undefined() };
        };
        return .{ .awaited = c.JS_DupValue(engine.context, value) };
    }
    if (completion == .rejected) {
        var boundary: u64 = 0;
        if (c.JS_ToBigUint64(engine.context, &boundary, try scope.get(state.*, "generation")) < 0) return js.capture(engine);
        try body.rethrowRecognizedAllocation(engine, input, boundary);
        try caught(&scope, roots[0], input);
    }
    return .{ .returned = c.pi_js_undefined() };
}
fn caught(scope: *Scope, channel: c.JSValue, reason: c.JSValue) !void {
    const console = try scope.global("console");
    const error_method = try scope.get(console, "error");
    const message = try scope.concat(try scope.concat(try scope.text("Event handler error ("), try scope.stringify(channel)), try scope.text("):"));
    _ = try scope.call(error_method, console, &.{ message, reason });
}
