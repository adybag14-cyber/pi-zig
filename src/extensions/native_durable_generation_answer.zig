//! Native final-answer continuation and inbox boundary handling.
const std = @import("std");
const engine_mod = @import("engine.zig");
const vm = @import("native_values.zig");
const js = @import("native_js_values.zig");
const awaiting = @import("native_durable_await.zig");
const c = engine_mod.c;
const Engine = engine_mod.Engine;
const Scope = struct {
    engine: *Engine,
    values: std.ArrayList(c.JSValue) = .empty,
    fn deinit(self: *Scope) void {
        for (self.values.items) |value| self.engine.freeValue(value);
        self.values.deinit(self.engine.gpa);
    }
    fn own(self: *Scope, value: c.JSValue) !c.JSValue {
        self.values.append(self.engine.gpa, value) catch |err| {
            self.engine.freeValue(value);
            return err;
        };
        return value;
    }
    fn get(self: *Scope, object: c.JSValue, key: [:0]const u8) !c.JSValue {
        return self.own(try vm.get(self.engine, object, key));
    }
    fn invoke(self: *Scope, object: c.JSValue, key: [:0]const u8, args: []const c.JSValue) !c.JSValue {
        return self.own(try vm.invoke(self.engine, object, key, args));
    }
    fn text(self: *Scope, bytes: []const u8) !c.JSValue {
        return self.own(try self.engine.checked(c.JS_NewStringLen(self.engine.context, bytes.ptr, bytes.len)));
    }
};
fn put(engine: *Engine, object: c.JSValue, key: [:0]const u8, value: c.JSValue) !void {
    try @import("native_tool_info.zig").putData(engine, object, key, c.JS_DupValue(engine.context, value));
}
fn captured(scope: *Scope, state: c.JSValue) !awaiting.Intrinsics {
    return .{ .constructor = try scope.get(state, "promiseConstructor"), .resolve = try scope.get(state, "promiseResolve"), .then_function = try scope.get(state, "promiseThen") };
}
fn wait(engine: *Engine, state: c.JSValue, pending: c.JSValue, stage: c_int) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    var intrinsics = try captured(&scope, state);
    return awaiting.continueWith(advance, engine, &intrinsics, state, pending, stage);
}
pub fn run(engine: *Engine, intrinsics: *awaiting.Intrinsics, runtime: c.JSValue, context: c.JSValue, message: c.JSValue, generation_token: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const state = try scope.own(try vm.object(engine));
    inline for (.{ .{ "promiseConstructor", intrinsics.constructor }, .{ "promiseResolve", intrinsics.resolve }, .{ "promiseThen", intrinsics.then_function }, .{ "runtime", runtime }, .{ "context", context }, .{ "message", message }, .{ "generationToken", generation_token } }) |field| try put(engine, state, field[0], field[1]);
    var data = [_]c.JSValue{state};
    const callback = try scope.own(try engine.checked(c.JS_NewCFunctionData2(engine.context, yieldCallback, "", 1, 0, data.len, &data)));
    const pending = try scope.invoke(try scope.get(runtime, "hooks"), "each", &.{ try scope.text("onYield"), callback });
    return wait(engine, state, pending, 1);
}
fn yieldCallback(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, data: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = Engine.fromContext(context.?);
    return yieldHook(engine, data[0], if (argc > 0) argv[0] else c.pi_js_undefined()) catch |err| @import("native_durable.zig").reject(engine, err);
}
fn yieldHook(engine: *Engine, state: c.JSValue, hook: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    if (!c.JS_IsUndefined(try scope.get(state, "continuation"))) return c.pi_js_undefined();
    var args = [_]c.JSValue{ try scope.get(state, "message"), try scope.get(state, "runtime"), try scope.get(state, "context") };
    const pending = try scope.own(try engine.checked(c.JS_Call(engine.context, hook, c.pi_js_undefined(), args.len, &args)));
    return wait(engine, state, pending, 2);
}
fn answerCommit(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, data: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = Engine.fromContext(context.?);
    return answerDraft(engine, data[0], if (argc > 0) argv[0] else c.pi_js_undefined()) catch |err| @import("native_durable.zig").reject(engine, err);
}
fn answerDraft(engine: *Engine, state: c.JSValue, tx: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    try put(engine, state, "tx", tx);
    const runtime = try scope.get(state, "runtime");
    const exports = engine.native_module_values.get("@earendil-works/pi-durable") orelse return error.DurableModuleUnavailable;
    var intrinsics = try captured(&scope, state);
    const pending = try scope.own(try @import("native_durable_inbox.zig").prepare(engine, &intrinsics, tx, try scope.get(runtime, "conversationId"), try scope.get(runtime, "settings"), try scope.get(exports, "InboxDoc")));
    return wait(engine, state, pending, 3);
}
fn advance(engine: *Engine, state: c.JSValue, value: c.JSValue, rejected: bool, stage: c_int) anyerror!c.JSValue {
    if (rejected) return engine.checked(c.JS_Throw(engine.context, c.JS_DupValue(engine.context, value)));
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    if (stage == 2) {
        if (!c.JS_IsUndefined(value) and !c.JS_IsNull(value)) try put(engine, state, "continuation", try scope.get(value, "continue"));
        return c.pi_js_undefined();
    }
    if (stage == 1) {
        var data = [_]c.JSValue{state};
        const callback = try scope.own(try engine.checked(c.JS_NewCFunctionData2(engine.context, answerCommit, "", 1, 0, data.len, &data)));
        return vm.invoke(engine, try scope.get(state, "runtime"), "commit", &.{ callback, try scope.get(state, "context") });
    }
    if (stage == 3) {
        try put(engine, state, "boundary", value);
        const runtime = try scope.get(state, "runtime");
        const exports = engine.native_module_values.get("@earendil-works/pi-durable") orelse return error.DurableModuleUnavailable;
        const pending = try scope.invoke(try scope.get(state, "tx"), "doc", &.{ try scope.get(exports, "LiveDoc"), try scope.get(runtime, "conversationId") });
        return wait(engine, state, pending, 4);
    }
    if (stage == 4) {
        try put(engine, state, "live", value);
        var intrinsics = try captured(&scope, state);
        const pending = try scope.own(try @import("native_durable_generation_task.zig").appendAssistant(engine, &intrinsics, try scope.get(state, "tx"), try scope.get(try scope.get(state, "runtime"), "conversationId"), try scope.get(state, "message")));
        return wait(engine, state, pending, 5);
    }
    if (stage == 5) {
        try put(engine, state, "assistantId", try scope.get(value, "id"));
        const runtime = try scope.get(state, "runtime");
        const exports = engine.native_module_values.get("@earendil-works/pi-durable") orelse return error.DurableModuleUnavailable;
        var intrinsics = try captured(&scope, state);
        const pending = try scope.own(try @import("native_durable_inbox.zig").apply(engine, &intrinsics, try scope.get(state, "tx"), try scope.get(state, "boundary"), true, try scope.invoke(runtime, "now", &.{}), try scope.get(exports, "UserEntry")));
        return wait(engine, state, pending, 6);
    }
    if (stage == 6) {
        try put(engine, state, "users", try scope.get(value, "users"));
        const continuation = try scope.get(state, "continuation");
        if (!c.JS_IsUndefined(continuation) and try vm.length(engine, try scope.get(value, "users")) == 0 and c.JS_ToBool(engine.context, try scope.get(value, "reset")) == 0) return appendContinuation(engine, state, continuation);
        return endAnsweredRun(engine, state);
    }
    if (stage == 7) return createSuccessor(engine, state);
    if (stage == 8) {
        try @import("native_durable_generation_live.zig").handOver(engine, try scope.get(state, "live"), try scope.get(try scope.get(state, "runtime"), "taskId"), value);
        const atom = c.JS_NewAtom(engine.context, "generation");
        defer c.JS_FreeAtom(engine.context, atom);
        if (c.JS_DeleteProperty(engine.context, try scope.get(state, "live"), atom, c.JS_PROP_THROW) < 0) return js.capture(engine);
        return result(engine, state);
    }
    if (stage == 9) return result(engine, state);
    return error.InvalidGenerationAnswerContinuation;
}
fn result(engine: *Engine, state: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const result_value = try scope.own(try vm.object(engine));
    try put(engine, result_value, "entryId", try scope.get(state, "assistantId"));
    const outcome = try scope.own(try vm.object(engine));
    try put(engine, outcome, "status", try scope.text("completed"));
    try put(engine, outcome, "result", result_value);
    const next = try vm.object(engine);
    errdefer engine.freeValue(next);
    try put(engine, next, "status", try scope.text("terminal"));
    try put(engine, next, "outcome", outcome);
    return next;
}
fn appendContinuation(engine: *Engine, state: c.JSValue, continuation: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const runtime = try scope.get(state, "runtime");
    const message = try scope.own(try vm.object(engine));
    try put(engine, message, "role", try scope.text("user"));
    try put(engine, message, "content", continuation);
    try put(engine, message, "timestamp", try scope.invoke(runtime, "now", &.{}));
    const model = try scope.own(try vm.array(engine));
    try js.push(engine, model, message);
    const entry = try scope.own(try vm.object(engine));
    try put(engine, entry, "model", model);
    const exports = engine.native_module_values.get("@earendil-works/pi-durable") orelse return error.DurableModuleUnavailable;
    const pending = try scope.invoke(try scope.get(state, "tx"), "appendEntry", &.{ try scope.get(exports, "UserEntry"), try scope.get(runtime, "conversationId"), entry });
    return wait(engine, state, pending, 7);
}
fn createSuccessor(engine: *Engine, state: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const ownership = try scope.own(try vm.object(engine));
    try put(engine, ownership, "kind", try scope.text("conversation"));
    const options = try scope.own(try vm.object(engine));
    try put(engine, options, "ownership", ownership);
    try put(engine, options, "conversationId", try scope.get(try scope.get(state, "runtime"), "conversationId"));
    const input = try scope.own(try vm.object(engine));
    const token = try scope.get(state, "generationToken");
    if (c.JS_IsUndefined(token)) return error.GenerationTaskUnavailable;
    const pending = try scope.invoke(try scope.get(state, "tx"), "createTask", &.{ token, input, options });
    return wait(engine, state, pending, 8);
}
fn endAnsweredRun(engine: *Engine, state: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const runtime = try scope.get(state, "runtime");
    const settlement = try scope.own(try vm.object(engine));
    try put(engine, settlement, "status", try scope.text("done"));
    try put(engine, settlement, "answer", try scope.get(state, "assistantId"));
    try @import("native_durable_generation_live.zig").endRun(engine, try scope.get(state, "tx"), try scope.get(state, "live"), try scope.get(runtime, "taskId"), settlement);
    const users = try scope.get(state, "users");
    if (try vm.length(engine, users) == 0) return result(engine, state);
    var intrinsics = try captured(&scope, state);
    const pending = try scope.own(try @import("native_durable_generation_live.zig").startRun(engine, &intrinsics, try scope.get(state, "tx"), try scope.get(runtime, "conversationId"), try scope.get(state, "live"), users, try scope.get(state, "generationToken")));
    return wait(engine, state, pending, 9);
}
