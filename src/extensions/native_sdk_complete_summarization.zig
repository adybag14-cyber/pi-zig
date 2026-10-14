//! Original completeSummarization with module-bound native AI dependencies.
//! The private assembly supplies the real shared uuidv7 and completeSimple
//! functions. This does not install a default provider or a successful fallback.
const em = @import("engine.zig");
const sdk = @import("native_sdk.zig");
const js = @import("native_js_values.zig");
const Scope = @import("native_sdk_prompt_scope.zig").Scope;
const flow = @import("native_agent_async.zig");
const c = em.c;

pub fn create(engine: *em.Engine, uuid: c.JSValue, complete_simple: c.JSValue, retry_assistant: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    var roots = [_]c.JSValue{ uuid, complete_simple, retry_assistant };
    const function = try scope.own(try engine.checked(c.JS_NewCFunctionData2(engine.context, dispatch, "completeSummarization", 6, 0, roots.len, &roots)));
    try asyncPrototype(&scope, function);
    return c.JS_DupValue(engine.context, function);
}
fn asyncPrototype(scope: *Scope, function: c.JSValue) !void {
    const prototype = try scope.own(try scope.engine.checked(c.JS_GetAsyncFunctionPrototype(scope.engine.context)));
    if (c.JS_SetPrototype(scope.engine.context, function, prototype) < 0) return js.capture(scope.engine);
}
fn dispatch(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    engine.native_exception_diagnostics_suppressed += 1;
    defer engine.native_exception_diagnostics_suppressed -= 1;
    var args = [_]c.JSValue{c.pi_js_undefined()} ** 6;
    if (argc > 0) for (argv[0..@min(args.len, @as(usize, @intCast(argc)))], 0..) |value, index| {
        args[index] = value;
    };
    return complete(engine, &args, roots[0..3]) catch |err| sdk.fail(engine, err);
}
fn complete(engine: *em.Engine, args: []const c.JSValue, dependencies: []const c.JSValue) !c.JSValue {
    const pending = try flow.create(engine, c.pi_js_undefined());
    defer engine.freeValue(pending.owner);
    errdefer engine.freeValue(pending.promise);
    start(engine, pending.owner, args, dependencies) catch |err| try flow.rejectError(engine, pending.owner, err);
    return pending.promise;
}
fn start(engine: *em.Engine, owner: c.JSValue, args: []const c.JSValue, dependencies: []const c.JSValue) !void {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const options = try scope.own(try js.spread(engine, args[2]));
    try scope.put(options, "cacheRetention", try scope.text("none"));
    const session_id = try scope.get(args[2], "sessionId");
    try scope.put(options, "sessionId", if (c.JS_IsNull(session_id) or c.JS_IsUndefined(session_id)) try scope.call(dependencies[0], c.pi_js_undefined(), &.{}) else session_id);
    inline for (.{ "model", "context", "options", "streamFn", "completeSimple" }, .{ args[0], args[1], options, args[3], dependencies[1] }) |name, value| try scope.put(owner, name, value);
    var roots = [_]c.JSValue{owner};
    const produce_function = try scope.own(try engine.checked(c.JS_NewCFunctionData2(engine.context, producer, "produce", 0, 0, roots.len, &roots)));
    try asyncPrototype(&scope, produce_function);
    const result = try scope.call(dependencies[2], c.pi_js_undefined(), &.{ produce_function, args[4], try scope.get(options, "signal"), args[5] });
    // Async return adoption invokes the intrinsic resolving function. Awaiting
    // this promise instead would incorrectly ignore a replaced public then.
    try flow.settle(engine, owner, false, result);
}
fn producer(context: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue, _: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    engine.native_exception_diagnostics_suppressed += 1;
    defer engine.native_exception_diagnostics_suppressed -= 1;
    return produce(engine, roots[0]) catch |err| sdk.fail(engine, err);
}
fn produce(engine: *em.Engine, request: c.JSValue) !c.JSValue {
    const pending = try flow.create(engine, request);
    defer engine.freeValue(pending.owner);
    errdefer engine.freeValue(pending.promise);
    produceStart(engine, pending.owner, request) catch |err| try flow.rejectError(engine, pending.owner, err);
    return pending.promise;
}
fn produceStart(engine: *em.Engine, owner: c.JSValue, request: c.JSValue) !void {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const stream = try scope.get(request, "streamFn");
    const function = if (scope.truthy(stream)) stream else try scope.get(request, "completeSimple");
    const result = try scope.call(function, c.pi_js_undefined(), &.{ try scope.get(request, "model"), try scope.get(request, "context"), try scope.get(request, "options") });
    if (scope.truthy(stream)) return flow.wait(streamReady, engine, owner, result, 0);
    return flow.settle(engine, owner, false, result);
}
fn streamReady(engine: *em.Engine, owner: c.JSValue, stream: c.JSValue, failed: bool, _: c_int) !void {
    if (failed) return flow.settle(engine, owner, true, stream);
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    // .result is read after awaiting the actual stream, preserving its receiver.
    return flow.settle(engine, owner, false, try scope.invoke(stream, "result", &.{}));
}
