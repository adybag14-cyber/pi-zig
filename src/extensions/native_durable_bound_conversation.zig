//! Harness-created invocation handles are plain closures over private owners.
//! Public id edits and borrowed receivers never select a different capability.
const engine_mod = @import("engine.zig");
const durable = @import("native_durable.zig");
const sdk = @import("native_sdk.zig");
const tasks = @import("native_durable_tasks.zig");
const contexts = @import("native_durable_context.zig");
const Engine = engine_mod.Engine;
const c = engine_mod.c;
pub fn acquire(engine: *Engine, runtime: c.JSValue, session: c.JSValue, options: c.JSValue, id: c.JSValue, signal: c.JSValue, context: c.JSValue) !c.JSValue {
    var captures = [_]c.JSValue{ runtime, session, options, id, signal, context };
    const read = try engine.checked(c.JS_NewCFunctionData(engine.context, readQueued, 0, 0, captures.len, &captures));
    defer engine.freeValue(read);
    const pending = try durable.enqueue(engine, session, read);
    defer engine.freeValue(pending);
    const adopt = try engine.checked(c.JS_NewCFunctionData(engine.context, acquired, 1, 0, 5, &captures));
    defer engine.freeValue(adopt);
    return sdk.invoke(engine, pending, "then", &.{adopt});
}
fn readQueued(context: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue, _: c_int, data: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = Engine.fromContext(context.?);
    const manager = tasks.getManager(engine, data[1]) catch |err| return durable.reject(engine, err);
    const id = durable.number(engine, data[3]) catch |err| return durable.reject(engine, err);
    return manager.abort_controls.admitConversationAccepted(manager, id, data[5]) catch |err| durable.reject(engine, err);
}
fn acquired(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, data: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = Engine.fromContext(context.?);
    if (argc == 0 or c.JS_ToBool(context, argv[0]) == 0) return c.pi_js_undefined();
    return handle(engine, data) catch |err| durable.reject(engine, err);
}
fn handle(engine: *Engine, data: [*c]c.JSValue) !c.JSValue {
    const value = try sdk.object(engine);
    errdefer engine.freeValue(value);
    try sdk.put(engine, value, "id", c.JS_DupValue(engine.context, data[3]));
    inline for (.{ "submit", "abort", "waitForIdle" }, 0..) |name, operation| {
        const arity: c_int = if (operation == 2) 1 else 2;
        const function = try engine.checked(c.JS_NewCFunctionData2(engine.context, handleMethod, if (operation == 2) "" else name, arity, @intCast(operation), 5, data));
        try sdk.put(engine, value, name, function);
    }
    return value;
}
fn handleMethod(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, operation: c_int, data: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = Engine.fromContext(context.?);
    return handleMethodOwned(engine, argv[0..@intCast(argc)], operation, data) catch |err| durable.rejectedPromise(engine, err);
}
fn argument(args: []const c.JSValue, index: usize) c.JSValue {
    return if (args.len > index) args[index] else c.pi_js_undefined();
}
fn handleMethodOwned(engine: *Engine, args: []const c.JSValue, operation: c_int, data: [*c]c.JSValue) !c.JSValue {
    try tasks.checkInvocation(engine, data[0]);
    const bound = try contexts.withAbortSignal(engine, data[4], argument(args, if (operation == 0) 1 else 0));
    defer engine.freeValue(bound);
    const manager = try tasks.getManager(engine, data[1]);
    if (operation == 2) return tasks.wait(manager, null, try durable.number(engine, data[3]), bound);
    if (operation == 1) {
        const options = argument(args, 1);
        const background = if (c.JS_IsUndefined(options)) c.pi_js_undefined() else try sdk.get(engine, options, "background");
        defer engine.freeValue(background);
        return @import("native_durable_abort_control.zig").abortConversation(manager, try durable.number(engine, data[3]), c.JS_IsBool(background) and c.JS_ToBool(engine.context, background) != 0, bound);
    }
    const pending = try @import("native_durable_submission_handle.zig").submit(engine, data[1], data[2], data[3], argument(args, 0), bound);
    defer engine.freeValue(pending);
    var captures = [_]c.JSValue{ data[0], data[4] };
    const adopt = try engine.checked(c.JS_NewCFunctionData(engine.context, receiptAdopted, 1, 0, captures.len, &captures));
    defer engine.freeValue(adopt);
    return sdk.invoke(engine, pending, "then", &.{adopt});
}
fn receiptAdopted(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, data: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = Engine.fromContext(context.?);
    return receipt(engine, if (argc > 0) argv[0] else c.pi_js_undefined(), data) catch |err| durable.reject(engine, err);
}
fn receipt(engine: *Engine, original: c.JSValue, data: [*c]c.JSValue) !c.JSValue {
    const result = try sdk.object(engine);
    errdefer engine.freeValue(result);
    try sdk.put(engine, result, "id", try sdk.get(engine, original, "id"));
    var captures = [_]c.JSValue{ data[0], data[1], original };
    inline for (.{ "status", "wait", "abort" }, 0..) |name, operation| try sdk.put(engine, result, name, try engine.checked(c.JS_NewCFunctionData(engine.context, receiptMethod, 1, @intCast(operation), captures.len, &captures)));
    return result;
}
fn receiptMethod(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, operation: c_int, data: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = Engine.fromContext(context.?);
    return receiptMethodOwned(engine, if (argc > 0) argv[0] else c.pi_js_undefined(), operation, data) catch |err| durable.rejectedPromise(engine, err);
}
fn receiptMethodOwned(engine: *Engine, context: c.JSValue, operation: c_int, data: [*c]c.JSValue) !c.JSValue {
    try tasks.checkInvocation(engine, data[0]);
    const bound = try contexts.withAbortSignal(engine, data[1], context);
    defer engine.freeValue(bound);
    const name: [:0]const u8 = switch (operation) {
        0 => "status",
        1 => "wait",
        else => "abort",
    };
    return sdk.invoke(engine, data[2], name, &.{bound});
}
