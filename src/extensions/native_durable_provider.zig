//! Stable provider session identity, including legacy conversation migration.
const std = @import("std");
const engine_mod = @import("engine.zig");
const vm = @import("native_values.zig");
const awaiting = @import("native_durable_await.zig");
const c = engine_mod.c;
const Engine = engine_mod.Engine;
fn put(engine: *Engine, object: c.JSValue, key: [:0]const u8, value: c.JSValue) !void {
    try @import("native_tool_info.zig").putData(engine, object, key, c.JS_DupValue(engine.context, value));
}
fn wait(engine: *Engine, state: c.JSValue, pending: c.JSValue, stage: c_int) !c.JSValue {
    const constructor = try vm.get(engine, state, "promiseConstructor");
    defer engine.freeValue(constructor);
    const resolve = try vm.get(engine, state, "promiseResolve");
    defer engine.freeValue(resolve);
    const then_function = try vm.get(engine, state, "promiseThen");
    defer engine.freeValue(then_function);
    var captured: awaiting.Intrinsics = .{ .constructor = constructor, .resolve = resolve, .then_function = then_function };
    return awaiting.continueWith(advance, engine, &captured, state, pending, stage);
}
pub fn ensure(engine: *Engine, captured: *awaiting.Intrinsics, runtime: c.JSValue, context: c.JSValue, provider_token: c.JSValue) !c.JSValue {
    const state = try vm.object(engine);
    defer engine.freeValue(state);
    inline for (.{ .{ "promiseConstructor", captured.constructor }, .{ "promiseResolve", captured.resolve }, .{ "promiseThen", captured.then_function }, .{ "runtime", runtime }, .{ "context", context }, .{ "providerToken", provider_token } }) |field| try put(engine, state, field[0], field[1]);
    const conversation = try vm.get(engine, runtime, "conversationId");
    defer engine.freeValue(conversation);
    const pending = try vm.invoke(engine, runtime, "snapshot", &.{ provider_token, conversation, context });
    defer engine.freeValue(pending);
    return wait(engine, state, pending, 1);
}
fn advance(engine: *Engine, state: c.JSValue, value: c.JSValue, rejected: bool, stage: c_int) !c.JSValue {
    if (rejected) return engine.checked(c.JS_Throw(engine.context, c.JS_DupValue(engine.context, value)));
    if (stage == 1) {
        if (!c.JS_IsUndefined(value)) return vm.get(engine, value, "sessionId");
        var data = [_]c.JSValue{state};
        const callback = try engine.checked(c.JS_NewCFunctionData2(engine.context, commit, "", 1, 0, data.len, &data));
        defer engine.freeValue(callback);
        const runtime = try vm.get(engine, state, "runtime");
        defer engine.freeValue(runtime);
        const context = try vm.get(engine, state, "context");
        defer engine.freeValue(context);
        const pending = try vm.invoke(engine, runtime, "commit", &.{ callback, context });
        defer engine.freeValue(pending);
        return wait(engine, state, pending, 3);
    }
    if (stage == 2) {
        const id = try vm.get(engine, value, "sessionId");
        defer engine.freeValue(id);
        try put(engine, state, "created", id);
        return c.pi_js_undefined();
    }
    if (stage == 3) {
        const created = try vm.get(engine, state, "created");
        if (!c.JS_IsUndefined(created)) return created;
        engine.freeValue(created);
        const runtime = try vm.get(engine, state, "runtime");
        defer engine.freeValue(runtime);
        const conversation = try vm.get(engine, runtime, "conversationId");
        defer engine.freeValue(conversation);
        const id = try engine.toString(conversation);
        defer engine.gpa.free(id);
        const message = try std.fmt.allocPrint(engine.gpa, "Conversation {s} has no provider session ID", .{id});
        defer engine.gpa.free(message);
        return @import("native_sdk.zig").sourceError(engine, message);
    }
    return error.InvalidProviderContinuation;
}
fn commit(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, data: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = Engine.fromContext(context.?);
    return migrate(engine, data[0], if (argc > 0) argv[0] else c.pi_js_undefined()) catch |err| @import("native_durable.zig").reject(engine, err);
}
fn migrate(engine: *Engine, state: c.JSValue, tx: c.JSValue) !c.JSValue {
    const runtime = try vm.get(engine, state, "runtime");
    defer engine.freeValue(runtime);
    const conversation = try vm.get(engine, runtime, "conversationId");
    defer engine.freeValue(conversation);
    const token = try vm.get(engine, state, "providerToken");
    defer engine.freeValue(token);
    const pending = try vm.invoke(engine, tx, "doc", &.{ token, conversation });
    defer engine.freeValue(pending);
    return wait(engine, state, pending, 2);
}
