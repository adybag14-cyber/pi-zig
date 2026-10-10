//! Native generation completion of a terminal tool round.
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
fn equals(scope: *Scope, value: c.JSValue, text: []const u8) !bool {
    return c.JS_IsStrictEqual(scope.engine.context, value, try scope.text(text));
}
pub fn run(engine: *Engine, intrinsics: *awaiting.Intrinsics, runtime: c.JSValue, context: c.JSValue, assistant: c.JSValue, tools: c.JSValue, generation_token: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const state = try scope.own(try vm.object(engine));
    inline for (.{ .{ "promiseConstructor", intrinsics.constructor }, .{ "promiseResolve", intrinsics.resolve }, .{ "promiseThen", intrinsics.then_function }, .{ "runtime", runtime }, .{ "context", context }, .{ "assistant", assistant }, .{ "tools", tools }, .{ "generationToken", generation_token } }) |field| try put(engine, state, field[0], field[1]);
    const pending = try scope.invoke(runtime, "outcomes", &.{ tools, context });
    return wait(engine, state, pending, 1);
}
fn afterToolsCallback(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, data: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = Engine.fromContext(context.?);
    return afterToolsHook(engine, data[0], if (argc > 0) argv[0] else c.pi_js_undefined()) catch |err| @import("native_durable.zig").reject(engine, err);
}
fn afterToolsHook(engine: *Engine, state: c.JSValue, hook: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    var args = [_]c.JSValue{ try scope.get(state, "assistant"), try scope.get(state, "results"), try scope.get(state, "runtime"), try scope.get(state, "context") };
    return engine.checked(c.JS_Call(engine.context, hook, c.pi_js_undefined(), args.len, &args));
}
fn finishCommit(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, data: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = Engine.fromContext(context.?);
    return finishDraft(engine, data[0], if (argc > 0) argv[0] else c.pi_js_undefined()) catch |err| @import("native_durable.zig").reject(engine, err);
}
fn finishDraft(engine: *Engine, state: c.JSValue, tx: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    try put(engine, state, "tx", tx);
    const runtime = try scope.get(state, "runtime");
    const exports = engine.native_module_values.get("@earendil-works/pi-durable") orelse return error.DurableModuleUnavailable;
    var intrinsics = try captured(&scope, state);
    const pending = try scope.own(try @import("native_durable_inbox.zig").prepare(engine, &intrinsics, tx, try scope.get(runtime, "conversationId"), try scope.get(runtime, "settings"), try scope.get(exports, "InboxDoc")));
    return wait(engine, state, pending, 4);
}
fn advance(engine: *Engine, state: c.JSValue, value: c.JSValue, rejected: bool, stage: c_int) anyerror!c.JSValue {
    if (rejected) return engine.checked(c.JS_Throw(engine.context, c.JS_DupValue(engine.context, value)));
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    if (stage == 1) {
        const constructor = try scope.own(try js.global(engine, "Map"));
        const controls = try scope.own(try engine.checked(c.JS_CallConstructor(engine.context, constructor, 0, null)));
        const tools = try scope.get(state, "tools");
        for (0..try vm.length(engine, tools)) |index| {
            const outcome = try item(&scope, value, index);
            var control = c.pi_js_undefined();
            if (try equals(&scope, try scope.get(outcome, "status"), "completed")) {
                const result = try scope.get(outcome, "result");
                if (!try equals(&scope, try scope.get(result, "kind"), "nested")) control = try scope.get(result, "control");
            }
            _ = try scope.invoke(controls, "set", &.{ try item(&scope, tools, index), control });
        }
        try put(engine, state, "controls", controls);
        const runtime = try scope.get(state, "runtime");
        const exports = engine.native_module_values.get("@earendil-works/pi-durable") orelse return error.DurableModuleUnavailable;
        const pending = try scope.invoke(runtime, "snapshot", &.{ try scope.get(exports, "LiveDoc"), try scope.get(runtime, "conversationId"), try scope.get(state, "context") });
        return wait(engine, state, pending, 2);
    }
    if (stage == 2) {
        const slots = if (c.JS_IsUndefined(value) or c.JS_IsNull(value)) try scope.own(try vm.array(engine)) else try scope.get(value, "tools");
        const selected = if (c.JS_IsUndefined(slots) or c.JS_IsNull(slots)) try scope.own(try vm.array(engine)) else slots;
        try put(engine, state, "slots", selected);
        const results = try scope.own(try vm.array(engine));
        for (0..try vm.length(engine, selected)) |index| {
            const entry = try scope.get(try item(&scope, selected, index), "entry");
            if (!c.JS_IsUndefined(entry)) try js.push(engine, results, entry);
        }
        try put(engine, state, "results", results);
        const runtime = try scope.get(state, "runtime");
        var data = [_]c.JSValue{state};
        const callback = try scope.own(try engine.checked(c.JS_NewCFunctionData2(engine.context, afterToolsCallback, "", 1, 0, data.len, &data)));
        const pending = try scope.invoke(try scope.get(runtime, "hooks"), "each", &.{ try scope.text("afterTools"), callback });
        return wait(engine, state, pending, 3);
    }
    if (stage == 3) return decideControls(engine, state);
    if (stage == 4) {
        try put(engine, state, "boundary", value);
        return afterBoundary(engine, state);
    }
    if (stage == 5) {
        try addTools(engine, state, value);
        return readLive(engine, state);
    }
    if (stage == 6) {
        try put(engine, state, "live", value);
        const runtime = try scope.get(state, "runtime");
        try put(engine, state, "now", try scope.invoke(runtime, "now", &.{}));
        return decideBoundary(engine, state);
    }
    if (stage == 7) {
        try put(engine, try scope.get(state, "boundary"), "head", try scope.get(value, "id"));
        return applyBoundary(engine, state);
    }
    if (stage == 8) {
        const runtime = try scope.get(state, "runtime");
        const live = try scope.get(state, "live");
        const users = try scope.get(value, "users");
        const final = c.JS_ToBool(engine.context, try scope.get(state, "terminate")) != 0 or !c.JS_IsUndefined(try scope.get(state, "handoff"));
        const reset = c.JS_ToBool(engine.context, try scope.get(value, "reset")) != 0;
        if (final or reset) {
            const settlement = try scope.own(try vm.object(engine));
            try put(engine, settlement, "status", try scope.text(if (final) "done" else "unanswered"));
            if (final) try put(engine, settlement, "answer", try scope.get(state, "assistant")) else try put(engine, settlement, "reason", try scope.text("reset"));
            try @import("native_durable_generation_live.zig").endRun(engine, try scope.get(state, "tx"), live, try scope.get(runtime, "taskId"), settlement);
            if (try vm.length(engine, users) == 0) return completed(engine, state);
            var intrinsics = try captured(&scope, state);
            const pending = try scope.own(try @import("native_durable_generation_live.zig").startRun(engine, &intrinsics, try scope.get(state, "tx"), try scope.get(runtime, "conversationId"), live, users, try scope.get(state, "generationToken")));
            return wait(engine, state, pending, 10);
        }
        try delete(engine, live, "tools");
        try delete(engine, live, "nestedTools");
        const active_run = try scope.get(live, "run");
        if (!c.JS_IsUndefined(active_run) and !c.JS_IsNull(active_run) and c.JS_IsStrictEqual(engine.context, try scope.get(active_run, "taskId"), try scope.get(runtime, "taskId"))) {
            const inputs = try scope.get(active_run, "inputs");
            for (0..try vm.length(engine, users)) |index| try js.push(engine, inputs, try item(&scope, users, index));
        }
        return createSuccessor(engine, state);
    }
    if (stage == 9) {
        try @import("native_durable_generation_live.zig").handOver(engine, try scope.get(state, "live"), try scope.get(try scope.get(state, "runtime"), "taskId"), value);
        return completed(engine, state);
    }
    if (stage == 10) return completed(engine, state);
    return error.InvalidGenerationFinishToolsContinuation;
}
fn decideControls(engine: *Engine, state: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const slots = try scope.get(state, "slots");
    const controls = try scope.get(state, "controls");
    var terminate = try vm.length(engine, slots) > 0;
    for (0..try vm.length(engine, slots)) |index| {
        const id = try scope.get(try item(&scope, slots, index), "taskId");
        if (c.JS_IsUndefined(id)) {
            terminate = false;
            break;
        }
        const control = try scope.invoke(controls, "get", &.{id});
        if (c.JS_IsUndefined(control) or c.JS_IsNull(control) or !c.JS_IsStrictEqual(engine.context, try scope.get(control, "terminate"), c.pi_js_bool(engine.context, 1))) {
            terminate = false;
            break;
        }
    }
    const array = try scope.own(try js.global(engine, "Array"));
    const values = try scope.invoke(array, "from", &.{try scope.invoke(controls, "values", &.{})});
    const added = try scope.own(try vm.array(engine));
    var handoff = c.pi_js_undefined();
    for (0..try vm.length(engine, values)) |index| {
        const control = try item(&scope, values, index);
        if (c.JS_IsUndefined(control) or c.JS_IsNull(control)) continue;
        const tools = try scope.get(control, "addTools");
        if (!c.JS_IsUndefined(tools) and !c.JS_IsNull(tools)) for (0..try vm.length(engine, tools)) |position| try js.push(engine, added, try item(&scope, tools, position));
        const next = try scope.get(control, "handoff");
        if (!c.JS_IsUndefined(next)) handoff = next;
    }
    try put(engine, state, "terminate", c.pi_js_bool(engine.context, @intFromBool(terminate)));
    try put(engine, state, "handoff", handoff);
    try put(engine, state, "added", added);
    var data = [_]c.JSValue{state};
    const callback = try scope.own(try engine.checked(c.JS_NewCFunctionData2(engine.context, finishCommit, "", 1, 0, data.len, &data)));
    return vm.invoke(engine, try scope.get(state, "runtime"), "commit", &.{ callback, try scope.get(state, "context") });
}
fn afterBoundary(engine: *Engine, state: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const exports = engine.native_module_values.get("@earendil-works/pi-durable") orelse return error.DurableModuleUnavailable;
    const runtime = try scope.get(state, "runtime");
    const added = try scope.get(state, "added");
    if (try vm.length(engine, added) > 0) {
        const pending = try scope.invoke(try scope.get(state, "tx"), "doc", &.{ try scope.get(exports, "AgentDoc"), try scope.get(runtime, "conversationId") });
        return wait(engine, state, pending, 5);
    }
    return readLive(engine, state);
}
fn readLive(engine: *Engine, state: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const exports = engine.native_module_values.get("@earendil-works/pi-durable") orelse return error.DurableModuleUnavailable;
    const pending = try scope.invoke(try scope.get(state, "tx"), "doc", &.{ try scope.get(exports, "LiveDoc"), try scope.get(try scope.get(state, "runtime"), "conversationId") });
    return wait(engine, state, pending, 6);
}
fn addTools(engine: *Engine, state: c.JSValue, agent: c.JSValue) !void {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const added = try scope.get(state, "added");
    inline for (.{ "tools", "modelTools" }) |key| {
        const filter = try scope.get(agent, key);
        if (!c.JS_IsUndefined(filter)) {
            if (c.JS_IsArray(filter)) {
                for (0..try vm.length(engine, added)) |index| {
                    const name = try item(&scope, added, index);
                    if (c.JS_ToBool(engine.context, try scope.invoke(filter, "includes", &.{name})) == 0) try js.push(engine, filter, name);
                }
            } else {
                const removed = try scope.get(filter, "remove");
                const retained = try scope.own(try vm.array(engine));
                var changed = false;
                for (0..try vm.length(engine, removed)) |index| {
                    const name = try item(&scope, removed, index);
                    if (c.JS_ToBool(engine.context, try scope.invoke(added, "includes", &.{name})) != 0) {
                        changed = true;
                    } else try js.push(engine, retained, name);
                }
                if (changed) {
                    const replacement = try scope.own(try vm.object(engine));
                    try put(engine, replacement, "remove", retained);
                    try put(engine, agent, key, replacement);
                }
            }
        }
    }
}
fn decideBoundary(engine: *Engine, state: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const handoff = try scope.get(state, "handoff");
    if (!c.JS_IsUndefined(handoff)) {
        const message = try scope.own(try vm.object(engine));
        try put(engine, message, "role", try scope.text("user"));
        try put(engine, message, "content", handoff);
        try put(engine, message, "timestamp", try scope.get(state, "now"));
        const model = try scope.own(try vm.array(engine));
        try js.push(engine, model, message);
        const entry = try scope.own(try vm.object(engine));
        try put(engine, entry, "head", try scope.text("self"));
        try put(engine, entry, "model", model);
        const exports = engine.native_module_values.get("@earendil-works/pi-durable") orelse return error.DurableModuleUnavailable;
        const pending = try scope.invoke(try scope.get(state, "tx"), "appendEntry", &.{ try scope.get(exports, "ResetEntry"), try scope.get(try scope.get(state, "runtime"), "conversationId"), entry });
        return wait(engine, state, pending, 7);
    }
    return applyBoundary(engine, state);
}
fn applyBoundary(engine: *Engine, state: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const final = c.JS_ToBool(engine.context, try scope.get(state, "terminate")) != 0 or !c.JS_IsUndefined(try scope.get(state, "handoff"));
    const exports = engine.native_module_values.get("@earendil-works/pi-durable") orelse return error.DurableModuleUnavailable;
    var intrinsics = try captured(&scope, state);
    const pending = try scope.own(try @import("native_durable_inbox.zig").apply(engine, &intrinsics, try scope.get(state, "tx"), try scope.get(state, "boundary"), final, try scope.get(state, "now"), try scope.get(exports, "UserEntry")));
    return wait(engine, state, pending, 8);
}
fn delete(engine: *Engine, object: c.JSValue, key: [:0]const u8) !void {
    const atom = c.JS_NewAtom(engine.context, key);
    defer c.JS_FreeAtom(engine.context, atom);
    if (c.JS_DeleteProperty(engine.context, object, atom, c.JS_PROP_THROW) < 0) return js.capture(engine);
}
fn completed(engine: *Engine, state: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const result = try scope.own(try vm.object(engine));
    try put(engine, result, "entryId", try scope.get(state, "assistant"));
    const outcome = try scope.own(try vm.object(engine));
    try put(engine, outcome, "status", try scope.text("completed"));
    try put(engine, outcome, "result", result);
    const next = try vm.object(engine);
    errdefer engine.freeValue(next);
    try put(engine, next, "status", try scope.text("terminal"));
    try put(engine, next, "outcome", outcome);
    return next;
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
    return wait(engine, state, pending, 9);
}
