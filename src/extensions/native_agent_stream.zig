//! Original EventStream-returning AgentLoop wrappers over the real native loop.
const em = @import("engine.zig");
const sdk = @import("native_sdk.zig");
const js = @import("native_js_values.zig");
const temp = @import("native_sdk_prompt_scope.zig");
const Scope = temp.Scope;
const returned = @import("native_async_return.zig");
const af_values = @import("native_agent_af_values.zig");
const c = em.c;

pub fn function(engine: *em.Engine, continuing: bool) !c.JSValue {
    const result = try engine.checked(c.JS_NewCFunction2(engine.context, if (continuing) continueCall else startCall, if (continuing) "agentLoopContinue" else "agentLoop", if (continuing) 4 else 5, c.JS_CFUNC_constructor_or_func, 0));
    errdefer engine.freeValue(result);
    const prototype = try sdk.object(engine);
    defer engine.freeValue(prototype);
    if (c.JS_DefinePropertyValueStr(engine.context, result, "prototype", c.JS_DupValue(engine.context, prototype), c.JS_PROP_WRITABLE) < 0) return js.capture(engine);
    if (c.JS_DefinePropertyValueStr(engine.context, prototype, "constructor", c.JS_DupValue(engine.context, result), c.JS_PROP_WRITABLE | c.JS_PROP_CONFIGURABLE) < 0) return js.capture(engine);
    return result;
}
fn startCall(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    return callValue(engine, argc, argv, false) catch |err| sdk.fail(engine, err);
}
fn continueCall(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    return callValue(engine, argc, argv, true) catch |err| sdk.fail(engine, err);
}
fn callValue(engine: *em.Engine, argc: c_int, argv: [*c]c.JSValue, continuing: bool) !c.JSValue {
    var args = [_]c.JSValue{c.pi_js_undefined()} ** 5;
    for (0..@min(args.len, @as(usize, @intCast(argc)))) |index| args[index] = argv[index];
    return if (continuing) run(engine, c.pi_js_undefined(), args[0], args[1], args[2], args[3], true) else run(engine, args[0], args[1], args[2], args[3], args[4], false);
}

pub fn run(engine: *em.Engine, prompts: c.JSValue, context: c.JSValue, config: c.JSValue, signal: c.JSValue, stream_function: c.JSValue, continuing: bool) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    if (continuing) {
        if (scope.equal(try scope.get(try scope.get(context, "messages"), "length"), c.JS_NewInt32(engine.context, 0))) _ = try @import("native_agent_methods.zig").raise(&scope, "Cannot continue: no messages in context");
        const messages = try scope.get(context, "messages");
        const length = try scope.get(try scope.get(context, "messages"), "length");
        const index = try scope.own(try engine.checked(c.JS_PiBinaryOperator(engine.context, 1, length, c.JS_NewInt32(engine.context, 1))));
        const last = try scope.own(try js.getKey(engine, messages, index));
        if (scope.equal(try scope.get(last, "role"), try scope.text("assistant"))) _ = try @import("native_agent_methods.zig").raise(&scope, "Cannot continue from message role: assistant");
    }
    const stream = try createStream(&scope);
    var roots = [_]c.JSValue{stream};
    const emit = try scope.own(try createEmitter(engine, stream));
    const pending = try scope.own(try @import("native_agent_loop.zig").run(engine, prompts, context, config, emit, signal, stream_function, continuing));
    const then = try scope.get(pending, "then");
    const fulfilled = try scope.own(try engine.checked(c.JS_NewCFunctionData2(engine.context, finishCall, "", 1, 0, roots.len, &roots)));
    _ = try scope.call(then, pending, &.{fulfilled});
    return c.JS_DupValue(engine.context, stream);
}
fn createStream(scope: *Scope) !c.JSValue {
    const engine = scope.engine;
    try @import("native_stream.zig").install(engine);
    const namespace = engine.native_module_values.get("@earendil-works/pi-ai") orelse return error.NativePiAiModuleUnavailable;
    const constructor = try scope.get(namespace, "EventStream");
    const complete = try scope.own(try engine.checked(c.JS_NewCFunction(engine.context, completeCall, "", 1)));
    const extract = try scope.own(try engine.checked(c.JS_NewCFunction(engine.context, extractCall, "", 1)));
    var args = [_]c.JSValue{ complete, extract };
    return scope.own(try engine.checked(c.JS_CallConstructor(engine.context, constructor, args.len, &args)));
}
fn completeCall(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    return completeValue(engine, if (argc > 0) argv[0] else c.pi_js_undefined(), false) catch |err| sdk.fail(engine, err);
}
fn extractCall(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    return completeValue(engine, if (argc > 0) argv[0] else c.pi_js_undefined(), true) catch |err| sdk.fail(engine, err);
}
fn completeValue(engine: *em.Engine, event: c.JSValue, extracting: bool) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const complete = scope.equal(try scope.get(event, "type"), try scope.text("agent_end"));
    if (!extracting) return c.pi_js_bool(engine.context, @intFromBool(complete));
    return if (complete) sdk.get(engine, event, "messages") else sdk.array(engine);
}
pub fn createEmitter(engine: *em.Engine, stream: c.JSValue) !c.JSValue {
    return returned.createArrow(engine, "", 1, emitEvent, &.{stream}, c.pi_js_undefined());
}
fn emitEvent(engine: *em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    return @import("native_agent_af_completion.zig").finishValue(&scope, pushEvent(&scope, args, roots[0]));
}
fn pushEvent(scope: *Scope, args: []const c.JSValue, stream: c.JSValue) !c.JSValue {
    _ = try af_values.invoke(scope, stream, "push", &.{if (args.len > 0) args[0] else c.pi_js_undefined()});
    // The Source async emitter does not await or return stream.push's value.
    return c.pi_js_undefined();
}
fn finishCall(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    const ignored = js.invoke(engine, roots[0], "end", &.{if (argc > 0) argv[0] else c.pi_js_undefined()}) catch |err| return sdk.fail(engine, err);
    engine.freeValue(ignored);
    return c.pi_js_undefined();
}
