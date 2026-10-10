//! Native generation tool round admission and sequential ownership.
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
fn item(scope: *Scope, array: c.JSValue, index: usize) !c.JSValue {
    return scope.own(try scope.engine.checked(c.JS_GetPropertyUint32(scope.engine.context, array, @intCast(index))));
}
pub fn start(engine: *Engine, intrinsics: *awaiting.Intrinsics, runtime: c.JSValue, context: c.JSValue, request: c.JSValue, message: c.JSValue, calls: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const state = try scope.own(try vm.object(engine));
    inline for (.{ .{ "promiseConstructor", intrinsics.constructor }, .{ "promiseResolve", intrinsics.resolve }, .{ "promiseThen", intrinsics.then_function }, .{ "runtime", runtime }, .{ "context", context }, .{ "request", request }, .{ "message", message }, .{ "calls", calls } }) |field| try put(engine, state, field[0], field[1]);
    const messages = try scope.get(request, "messages");
    if (!c.JS_IsUndefined(messages)) return offeredMessages(engine, state, messages);
    const options = try scope.own(try vm.object(engine));
    try put(engine, options, "at", try scope.get(request, "cutoff"));
    const pending = try scope.invoke(runtime, "context", &.{ try scope.get(runtime, "conversationId"), context, options });
    return wait(engine, state, pending, 1);
}
fn offeredMessages(engine: *Engine, state: c.JSValue, messages: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const tools = try scope.own(try @import("native_durable_prompt.zig").getCurrentTools(engine, messages));
    const offered = try scope.own(try vm.array(engine));
    for (0..try vm.length(engine, tools)) |index| try js.push(engine, offered, try scope.get(try item(&scope, tools, index), "name"));
    try put(engine, state, "offered", offered);
    const pending = try scope.invoke(try scope.get(state, "runtime"), "agent", &.{try scope.get(state, "context")});
    return wait(engine, state, pending, 2);
}
fn roundCommit(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, data: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = Engine.fromContext(context.?);
    return roundDraft(engine, data[0], if (argc > 0) argv[0] else c.pi_js_undefined()) catch |err| @import("native_durable.zig").reject(engine, err);
}
fn roundDraft(engine: *Engine, state: c.JSValue, tx: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    try put(engine, state, "tx", tx);
    const exports = engine.native_module_values.get("@earendil-works/pi-durable") orelse return error.DurableModuleUnavailable;
    const pending = try scope.invoke(tx, "doc", &.{ try scope.get(exports, "LiveDoc"), try scope.get(try scope.get(state, "runtime"), "conversationId") });
    return wait(engine, state, pending, 3);
}
fn advance(engine: *Engine, state: c.JSValue, value: c.JSValue, rejected: bool, stage: c_int) anyerror!c.JSValue {
    if (rejected) return engine.checked(c.JS_Throw(engine.context, c.JS_DupValue(engine.context, value)));
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    if (stage == 1) return offeredMessages(engine, state, try scope.get(value, "messages"));
    if (stage == 2) {
        const runtime = try scope.get(state, "runtime");
        const mode = try scope.get(try scope.get(runtime, "settings"), "toolExecution");
        var sequential = c.JS_IsStrictEqual(engine.context, mode, try scope.text("sequential"));
        const tools = try scope.get(value, "tools");
        const calls = try scope.get(state, "calls");
        const offered = try scope.get(state, "offered");
        if (!sequential) for (0..try vm.length(engine, calls)) |index| {
            const call = try item(&scope, calls, index);
            const name = try scope.get(call, "name");
            if (c.JS_ToBool(engine.context, try scope.invoke(offered, "includes", &.{name})) == 0) continue;
            for (0..try vm.length(engine, tools)) |position| {
                const tool = try item(&scope, tools, position);
                if (c.JS_IsStrictEqual(engine.context, name, try scope.get(tool, "name"))) {
                    sequential = c.JS_IsStrictEqual(engine.context, try scope.get(tool, "executionMode"), try scope.text("sequential"));
                    break;
                }
            }
            if (sequential) break;
        };
        try put(engine, state, "sequential", c.pi_js_bool(engine.context, @intFromBool(sequential)));
        var data = [_]c.JSValue{state};
        const callback = try scope.own(try engine.checked(c.JS_NewCFunctionData2(engine.context, roundCommit, "", 1, 0, data.len, &data)));
        return vm.invoke(engine, runtime, "commit", &.{ callback, try scope.get(state, "context") });
    }
    if (stage == 3) {
        try put(engine, state, "live", value);
        var intrinsics = try captured(&scope, state);
        const pending = try scope.own(try @import("native_durable_generation_task.zig").appendAssistant(engine, &intrinsics, try scope.get(state, "tx"), try scope.get(try scope.get(state, "runtime"), "conversationId"), try scope.get(state, "message")));
        return wait(engine, state, pending, 4);
    }
    if (stage == 4) {
        try put(engine, state, "assistant", try scope.get(value, "id"));
        inline for (.{ "slots", "tools", "pending" }) |key| try @import("native_tool_info.zig").putData(engine, state, key, try vm.array(engine));
        try put(engine, state, "index", c.JS_NewInt32(engine.context, 0));
        return nextCall(engine, state);
    }
    if (stage == 5) {
        const value_slot = try scope.own(try slot(engine, &scope, try scope.get(state, "currentCall")));
        try put(engine, value_slot, "status", try scope.text("done"));
        try put(engine, value_slot, "entry", try scope.get(value, "id"));
        try js.push(engine, try scope.get(state, "slots"), value_slot);
        return nextCall(engine, state);
    }
    if (stage == 6) {
        try js.push(engine, try scope.get(state, "tools"), value);
        const value_slot = try scope.own(try slot(engine, &scope, try scope.get(state, "currentCall")));
        try put(engine, value_slot, "taskId", value);
        try put(engine, value_slot, "status", try scope.text("pending"));
        try js.push(engine, try scope.get(state, "slots"), value_slot);
        return nextCall(engine, state);
    }
    if (stage == 7) {
        try put(engine, state, "live", value);
        const checkpoint = try scope.get(state, "checkpoint");
        const call_id = try item(&scope, try scope.get(checkpoint, "pending"), 0);
        try put(engine, state, "nextCallId", call_id);
        const input = try scope.own(try vm.object(engine));
        try put(engine, input, "kind", try scope.text("model"));
        try put(engine, input, "assistant", try scope.get(checkpoint, "assistant"));
        try put(engine, input, "callId", call_id);
        const ownership = try scope.own(try vm.object(engine));
        try put(engine, ownership, "kind", try scope.text("task"));
        try put(engine, ownership, "taskId", try scope.get(try scope.get(state, "runtime"), "taskId"));
        const options = try scope.own(try vm.object(engine));
        try put(engine, options, "ownership", ownership);
        const exports = engine.native_module_values.get("@earendil-works/pi-durable") orelse return error.DurableModuleUnavailable;
        const pending = try scope.invoke(try scope.get(state, "tx"), "createTask", &.{ try scope.get(exports, "ToolTask"), input, options });
        return wait(engine, state, pending, 8);
    }
    if (stage == 8) {
        const live = try scope.get(state, "live");
        const slots = try scope.get(live, "tools");
        if (!c.JS_IsUndefined(slots) and !c.JS_IsNull(slots)) for (0..try vm.length(engine, slots)) |index| {
            const candidate = try item(&scope, slots, index);
            if (c.JS_IsStrictEqual(engine.context, try scope.get(candidate, "callId"), try scope.get(state, "nextCallId")) and c.JS_IsUndefined(try scope.get(candidate, "taskId"))) {
                try put(engine, candidate, "taskId", value);
                break;
            }
        };
        const old = try scope.get(state, "checkpoint");
        const tools = try scope.invoke(try scope.get(old, "tools"), "slice", &.{});
        try js.push(engine, tools, value);
        const rest = try scope.invoke(try scope.get(old, "pending"), "slice", &.{c.JS_NewInt32(engine.context, 1)});
        const checkpoint = try scope.own(try vm.object(engine));
        try put(engine, checkpoint, "phase", try scope.text("tools"));
        try put(engine, checkpoint, "assistant", try scope.get(old, "assistant"));
        try put(engine, checkpoint, "tools", tools);
        try put(engine, checkpoint, "pending", rest);
        const on = try scope.own(try vm.array(engine));
        try js.push(engine, on, value);
        const next = try vm.object(engine);
        errdefer engine.freeValue(next);
        try put(engine, next, "status", try scope.text("waiting"));
        try put(engine, next, "checkpoint", checkpoint);
        try put(engine, next, "on", on);
        try put(engine, next, "policy", try scope.text("allSettled"));
        return next;
    }
    return error.InvalidGenerationToolRoundContinuation;
}
fn slot(engine: *Engine, scope: *Scope, call: c.JSValue) !c.JSValue {
    const value = try vm.object(engine);
    errdefer engine.freeValue(value);
    try put(engine, value, "callId", try scope.get(call, "id"));
    try put(engine, value, "name", try scope.get(call, "name"));
    return value;
}
fn nextCall(engine: *Engine, state: c.JSValue) anyerror!c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const calls = try scope.get(state, "calls");
    var index: u32 = 0;
    if (c.JS_ToUint32(engine.context, &index, try scope.get(state, "index")) < 0) return js.capture(engine);
    const tools = try scope.get(state, "tools");
    const slots = try scope.get(state, "slots");
    const runtime = try scope.get(state, "runtime");
    const tx = try scope.get(state, "tx");
    while (index < try vm.length(engine, calls)) {
        const call = try item(&scope, calls, index);
        try put(engine, state, "currentCall", call);
        index += 1;
        try put(engine, state, "index", c.JS_NewUint32(engine.context, index));
        const name = try scope.get(call, "name");
        const offered = try scope.invoke(try scope.get(state, "offered"), "includes", &.{name});
        if (c.JS_ToBool(engine.context, offered) == 0) {
            const message = try scope.own(try @import("native_utf16.zig").concat(engine, &.{ try scope.text("Tool "), name, try scope.text(" is not available") }));
            const error_result = try scope.own(try @import("native_durable_tool_result.zig").harnessError(engine, try scope.text("tool_unavailable"), message));
            var intrinsics = try captured(&scope, state);
            const pending = try scope.own(try @import("native_durable_tool_result.zig").append(engine, &intrinsics, tx, try scope.get(runtime, "conversationId"), call, error_result, try scope.invoke(runtime, "now", &.{}), c.pi_js_undefined()));
            return wait(engine, state, pending, 5);
        }
        if (c.JS_ToBool(engine.context, try scope.get(state, "sequential")) != 0 and try vm.length(engine, tools) > 0) {
            try js.push(engine, try scope.get(state, "pending"), try scope.get(call, "id"));
            const pending_slot = try scope.own(try slot(engine, &scope, call));
            try put(engine, pending_slot, "status", try scope.text("pending"));
            try js.push(engine, slots, pending_slot);
            continue;
        }
        const input = try scope.own(try vm.object(engine));
        try put(engine, input, "kind", try scope.text("model"));
        try put(engine, input, "assistant", try scope.get(state, "assistant"));
        try put(engine, input, "callId", try scope.get(call, "id"));
        const ownership = try scope.own(try vm.object(engine));
        try put(engine, ownership, "kind", try scope.text("task"));
        try put(engine, ownership, "taskId", try scope.get(runtime, "taskId"));
        const options = try scope.own(try vm.object(engine));
        try put(engine, options, "ownership", ownership);
        const exports = engine.native_module_values.get("@earendil-works/pi-durable") orelse return error.DurableModuleUnavailable;
        const pending = try scope.invoke(tx, "createTask", &.{ try scope.get(exports, "ToolTask"), input, options });
        return wait(engine, state, pending, 6);
    }
    const live = try scope.get(state, "live");
    const atom = c.JS_NewAtom(engine.context, "generation");
    defer c.JS_FreeAtom(engine.context, atom);
    if (c.JS_DeleteProperty(engine.context, live, atom, c.JS_PROP_THROW) < 0) return js.capture(engine);
    try put(engine, live, "tools", slots);
    const checkpoint = try scope.own(try vm.object(engine));
    try put(engine, checkpoint, "phase", try scope.text("tools"));
    try put(engine, checkpoint, "assistant", try scope.get(state, "assistant"));
    try put(engine, checkpoint, "tools", tools);
    try put(engine, checkpoint, "pending", try scope.get(state, "pending"));
    const next = try vm.object(engine);
    errdefer engine.freeValue(next);
    try put(engine, next, "status", try scope.text("waiting"));
    try put(engine, next, "checkpoint", checkpoint);
    try put(engine, next, "on", tools);
    try put(engine, next, "policy", try scope.text("allSettled"));
    return next;
}
pub fn phase(engine: *Engine, intrinsics: *awaiting.Intrinsics, runtime: c.JSValue, context: c.JSValue, task: c.JSValue, generation_token: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const checkpoint = try scope.get(try scope.get(task, "state"), "checkpoint");
    const pending_calls = try scope.get(checkpoint, "pending");
    if (try vm.length(engine, pending_calls) == 0) return @import("native_durable_generation_finish_tools.zig").run(engine, intrinsics, runtime, context, try scope.get(checkpoint, "assistant"), try scope.get(checkpoint, "tools"), generation_token);
    const state = try scope.own(try vm.object(engine));
    inline for (.{ .{ "promiseConstructor", intrinsics.constructor }, .{ "promiseResolve", intrinsics.resolve }, .{ "promiseThen", intrinsics.then_function }, .{ "runtime", runtime }, .{ "context", context }, .{ "checkpoint", checkpoint } }) |field| try put(engine, state, field[0], field[1]);
    var data = [_]c.JSValue{state};
    const callback = try scope.own(try engine.checked(c.JS_NewCFunctionData2(engine.context, pendingCommit, "", 1, 0, data.len, &data)));
    return vm.invoke(engine, runtime, "commit", &.{ callback, context });
}
fn pendingCommit(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, data: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = Engine.fromContext(context.?);
    return pendingDraft(engine, data[0], if (argc > 0) argv[0] else c.pi_js_undefined()) catch |err| @import("native_durable.zig").reject(engine, err);
}
fn pendingDraft(engine: *Engine, state: c.JSValue, tx: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    try put(engine, state, "tx", tx);
    const exports = engine.native_module_values.get("@earendil-works/pi-durable") orelse return error.DurableModuleUnavailable;
    const pending = try scope.invoke(tx, "doc", &.{ try scope.get(exports, "LiveDoc"), try scope.get(try scope.get(state, "runtime"), "conversationId") });
    return wait(engine, state, pending, 7);
}
