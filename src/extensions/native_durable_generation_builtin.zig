//! Genuine built-in pi.generation definition backed by native Zig phases.
const engine_mod = @import("engine.zig");
const vm = @import("native_values.zig");
const task = @import("native_durable_generation_task.zig");
const awaiting = @import("native_durable_await.zig");
const c = engine_mod.c;
const Engine = engine_mod.Engine;
const Handler = enum(c_int) { prepare, request, retry, poll, tools, abort };
pub fn install(engine: *Engine, exports: c.JSValue) !void {
    var captured = try awaiting.Intrinsics.init(engine);
    defer captured.deinit(engine);
    const state = try vm.object(engine);
    defer engine.freeValue(state);
    inline for (.{ .{ "promiseConstructor", captured.constructor }, .{ "promiseResolve", captured.resolve }, .{ "promiseThen", captured.then_function } }) |field| try @import("native_tool_info.zig").putData(engine, state, field[0], c.JS_DupValue(engine.context, field[1]));
    const live = try vm.get(engine, exports, "LiveDoc");
    try @import("native_tool_info.zig").putData(engine, state, "liveToken", live);
    const definition = try vm.object(engine);
    defer engine.freeValue(definition);
    try @import("native_tool_info.zig").putData(engine, definition, "name", try engine.checked(c.JS_NewString(engine.context, "pi.generation")));
    try @import("native_tool_info.zig").putData(engine, definition, "version", c.JS_NewInt32(engine.context, 1));
    try @import("native_tool_info.zig").putData(engine, definition, "initial", try engine.checked(c.JS_NewCFunction(engine.context, initial, "initial", 0)));
    const phases = try vm.object(engine);
    defer engine.freeValue(phases);
    inline for (.{ Handler.prepare, Handler.request, Handler.retry, Handler.poll, Handler.tools }) |handler| {
        var data = [_]c.JSValue{state};
        try @import("native_tool_info.zig").putData(engine, phases, @tagName(handler), try engine.checked(c.JS_NewCFunctionData2(engine.context, dispatch, @tagName(handler), 3, @intFromEnum(handler), data.len, &data)));
    }
    try @import("native_tool_info.zig").putData(engine, definition, "phases", c.JS_DupValue(engine.context, phases));
    var data = [_]c.JSValue{state};
    try @import("native_tool_info.zig").putData(engine, definition, "abort", try engine.checked(c.JS_NewCFunctionData2(engine.context, dispatch, "abort", 3, @intFromEnum(Handler.abort), data.len, &data)));
    const token = try vm.object(engine);
    errdefer engine.freeValue(token);
    try @import("native_tool_info.zig").putData(engine, token, "definition", c.JS_DupValue(engine.context, definition));
    try @import("native_tool_info.zig").putData(engine, state, "generationToken", c.JS_DupValue(engine.context, token));
    try @import("native_tool_info.zig").putData(engine, exports, "GenerationTask", token);
}
fn initial(context: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = Engine.fromContext(context.?);
    const result = vm.object(engine) catch |err| return @import("native_durable.zig").reject(engine, err);
    const phase = engine.checked(c.JS_NewString(engine.context, "prepare")) catch |err| {
        engine.freeValue(result);
        return @import("native_durable.zig").reject(engine, err);
    };
    @import("native_tool_info.zig").putData(engine, result, "phase", phase) catch |err| {
        engine.freeValue(result);
        return @import("native_durable.zig").reject(engine, err);
    };
    @import("native_tool_info.zig").putData(engine, result, "attempt", c.JS_NewInt32(engine.context, 1)) catch |err| {
        engine.freeValue(result);
        return @import("native_durable.zig").reject(engine, err);
    };
    return result;
}
fn dispatch(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, raw: c_int, data: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = Engine.fromContext(context.?);
    return run(engine, data[0], @enumFromInt(raw), argv[0..@intCast(argc)]) catch |err| @import("native_durable.zig").rejectedPromise(engine, err);
}
fn run(engine: *Engine, state: c.JSValue, handler: Handler, args: []const c.JSValue) !c.JSValue {
    const constructor = try vm.get(engine, state, "promiseConstructor");
    defer engine.freeValue(constructor);
    const resolve = try vm.get(engine, state, "promiseResolve");
    defer engine.freeValue(resolve);
    const then_function = try vm.get(engine, state, "promiseThen");
    defer engine.freeValue(then_function);
    const live = try vm.get(engine, state, "liveToken");
    defer engine.freeValue(live);
    var captured: awaiting.Intrinsics = .{ .constructor = constructor, .resolve = resolve, .then_function = then_function };
    const record = if (args.len > 0) args[0] else c.pi_js_undefined();
    const runtime = if (args.len > 1) args[1] else c.pi_js_undefined();
    const context = if (args.len > 2) args[2] else c.pi_js_undefined();
    switch (handler) {
        .prepare => return task.prepare(engine, &captured, runtime, context, live, record),
        .request => return task.requestPhase(engine, &captured, runtime, context, live, record),
        .retry => return task.retry(engine, &captured, runtime, context, live, record),
        .poll => return task.poll(engine, &captured, runtime, context, live, record),
        .tools => {
            const token = try vm.get(engine, state, "generationToken");
            defer engine.freeValue(token);
            return @import("native_durable_generation_tools.zig").phase(engine, &captured, runtime, context, record, token);
        },
        .abort => return @import("native_durable_generation_abort.zig").run(engine, &captured, runtime, context, record),
    }
}
