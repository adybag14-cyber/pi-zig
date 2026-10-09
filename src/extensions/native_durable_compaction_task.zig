//! Native compaction task continuations. The public token is installed only
//! once every real phase is wired; helper tests do not substitute a stub token.
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
fn put(engine: *Engine, object: c.JSValue, name: [:0]const u8, value: c.JSValue) !void {
    try @import("native_tool_info.zig").putData(engine, object, name, c.JS_DupValue(engine.context, value));
}
fn captured(scope: *Scope, state: c.JSValue) !awaiting.Intrinsics {
    return .{ .constructor = try scope.get(state, "promiseConstructor"), .resolve = try scope.get(state, "promiseResolve"), .then_function = try scope.get(state, "promiseThen") };
}
fn createState(engine: *Engine, intrinsics: *awaiting.Intrinsics, runtime: c.JSValue, context: c.JSValue, live_token: c.JSValue) !c.JSValue {
    const state = try vm.object(engine);
    errdefer engine.freeValue(state);
    inline for (.{ .{ "promiseConstructor", intrinsics.constructor }, .{ "promiseResolve", intrinsics.resolve }, .{ "promiseThen", intrinsics.then_function }, .{ "runtime", runtime }, .{ "context", context }, .{ "liveToken", live_token } }) |field| try put(engine, state, field[0], field[1]);
    return state;
}
fn wait(engine: *Engine, state: c.JSValue, pending: c.JSValue, stage: c_int) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    var intrinsics = try captured(&scope, state);
    return awaiting.continueWith(advance, engine, &intrinsics, state, pending, stage);
}
pub fn terminal(engine: *Engine, intrinsics: *awaiting.Intrinsics, runtime: c.JSValue, context: c.JSValue, live_token: c.JSValue, outcome: c.JSValue) !c.JSValue {
    const state = try createState(engine, intrinsics, runtime, context, live_token);
    defer engine.freeValue(state);
    try put(engine, state, "outcome", outcome);
    var data = [_]c.JSValue{state};
    const callback = try engine.checked(c.JS_NewCFunctionData2(engine.context, commitTerminal, "", 1, 0, data.len, &data));
    defer engine.freeValue(callback);
    return vm.invoke(engine, runtime, "commit", &.{ callback, context });
}
fn commitTerminal(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, data: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = Engine.fromContext(context.?);
    return terminalDraft(engine, data[0], if (argc > 0) argv[0] else c.pi_js_undefined()) catch |err| @import("native_durable.zig").reject(engine, err);
}
fn terminalDraft(engine: *Engine, state: c.JSValue, tx: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const runtime = try scope.get(state, "runtime");
    const id = try scope.get(runtime, "conversationId");
    const pending = try scope.invoke(tx, "doc", &.{ try scope.get(state, "liveToken"), id });
    return wait(engine, state, pending, 1);
}
fn advance(engine: *Engine, state: c.JSValue, value: c.JSValue, rejected: bool, stage: c_int) !c.JSValue {
    if (rejected) return engine.checked(c.JS_Throw(engine.context, c.JS_DupValue(engine.context, value)));
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    if (stage == 1) {
        const runtime = try scope.get(state, "runtime");
        try @import("native_durable_compaction_status.zig").remove(engine, value, try scope.get(runtime, "taskId"));
        const next = try vm.object(engine);
        errdefer engine.freeValue(next);
        try put(engine, next, "status", try scope.text("terminal"));
        try put(engine, next, "outcome", try scope.get(state, "outcome"));
        return next;
    }
    if (stage == 2) {
        const runtime = try scope.get(state, "runtime");
        var data = [_]c.JSValue{state};
        const callback = try scope.own(try engine.checked(c.JS_NewCFunctionData2(engine.context, retryCommit, "", 1, 0, data.len, &data)));
        return vm.invoke(engine, runtime, "commit", &.{ callback, try scope.get(state, "context") });
    }
    if (stage == 3) {
        const runtime = try scope.get(state, "runtime");
        const checkpoint = try scope.get(state, "checkpoint");
        var attempt: f64 = 0;
        if (c.JS_ToFloat64(engine.context, &attempt, try scope.get(checkpoint, "attempt")) < 0) return js.capture(engine);
        attempt += 1;
        const status = try scope.own(try @import("native_durable_compaction_status.zig").find(engine, value, try scope.get(runtime, "taskId")));
        if (!c.JS_IsUndefined(status)) {
            try put(engine, status, "attempt", c.JS_NewFloat64(engine.context, attempt));
            try delete(engine, status, "retry");
        }
        const request = try scope.own(try js.spread(engine, checkpoint));
        try delete(engine, request, "phase");
        try delete(engine, request, "until");
        const next_checkpoint = try scope.own(try vm.object(engine));
        try put(engine, next_checkpoint, "phase", try scope.text("summarize"));
        try js.spreadInto(engine, next_checkpoint, request);
        try put(engine, next_checkpoint, "attempt", c.JS_NewFloat64(engine.context, attempt));
        const next = try vm.object(engine);
        errdefer engine.freeValue(next);
        try put(engine, next, "status", try scope.text("running"));
        try put(engine, next, "checkpoint", next_checkpoint);
        return next;
    }
    if (stage == 4) {
        const runtime = try scope.get(state, "runtime");
        const ref = try scope.get(value, "model");
        if (c.JS_IsUndefined(ref)) return failNoModel(engine, state, ref);
        const models = try scope.get(runtime, "models");
        const model = try scope.invoke(models, "getModel", &.{ try scope.get(ref, "provider"), try scope.get(ref, "modelId") });
        if (c.JS_IsUndefined(model)) return failNoModel(engine, state, ref);
        try put(engine, state, "agent", value);
        try put(engine, state, "model", model);
        try put(engine, state, "modelRef", ref);
        const pending = try scope.invoke(runtime, "context", &.{ try scope.get(runtime, "conversationId"), try scope.get(state, "context") });
        return wait(engine, state, pending, 5);
    }
    if (stage == 5) {
        const runtime = try scope.get(state, "runtime");
        const settings = try scope.get(runtime, "settings");
        const policy = try scope.get(settings, "compaction");
        var keep: f64 = 0;
        if (c.JS_ToFloat64(engine.context, &keep, try scope.get(policy, "keepRecentTokens")) < 0) return js.capture(engine);
        const cut = try @import("native_durable_compaction_text.zig").selectCut(engine, value, keep);
        if (cut == null) {
            const outcome = try scope.own(try vm.object(engine));
            try put(engine, outcome, "status", try scope.text("completed"));
            try @import("native_tool_info.zig").putData(engine, outcome, "result", try vm.object(engine));
            var intrinsics = try captured(&scope, state);
            return terminal(engine, &intrinsics, runtime, try scope.get(state, "context"), try scope.get(state, "liveToken"), outcome);
        }
        try put(engine, state, "view", value);
        try put(engine, state, "cut", c.JS_NewFloat64(engine.context, @floatFromInt(cut.?)));
        return beforeCompact(engine, state, value, cut.?);
    }
    if (stage == 7) {
        try put(engine, state, "decision", value);
        return c.pi_js_undefined();
    }
    if (stage == 6) {
        const decision = try scope.get(state, "decision");
        if (!c.JS_IsUndefined(decision)) {
            const atom = c.JS_NewAtom(engine.context, "decline");
            defer c.JS_FreeAtom(engine.context, atom);
            const declined = c.JS_HasProperty(engine.context, decision, atom);
            if (declined < 0) return js.capture(engine);
            if (declined != 0) {
                const outcome = try scope.own(try vm.object(engine));
                try put(engine, outcome, "status", try scope.text("completed"));
                try @import("native_tool_info.zig").putData(engine, outcome, "result", try vm.object(engine));
                var intrinsics = try captured(&scope, state);
                return terminal(engine, &intrinsics, try scope.get(state, "runtime"), try scope.get(state, "context"), try scope.get(state, "liveToken"), outcome);
            }
            try put(engine, state, "summary", try scope.get(decision, "summary"));
            return place(engine, state);
        }
        return pinRequest(engine, state);
    }
    if (stage == 8) return placeDraftReady(engine, state, value);
    if (stage == 9) {
        const result = try scope.own(try vm.object(engine));
        try put(engine, result, "entryId", try scope.get(value, "id"));
        return completed(engine, &scope, result);
    }
    if (stage == 10) {
        const result = try scope.own(try vm.object(engine));
        try put(engine, result, "submissionId", value);
        return completed(engine, &scope, result);
    }
    if (stage == 11) {
        try put(engine, state, "view", value);
        return prepareSummaryRequest(engine, state, value);
    }
    if (stage == 12) {
        try put(engine, state, "providerSessionId", value);
        return callSummaryModel(engine, state);
    }
    if (stage == 13) {
        try put(engine, state, "message", value);
        return classifySummary(engine, state, value);
    }
    if (stage == 14) {
        const tx = try scope.get(state, "tx");
        const runtime = try scope.get(state, "runtime");
        const pending = try scope.invoke(tx, "doc", &.{ try scope.get(state, "liveToken"), try scope.get(runtime, "conversationId") });
        return wait(engine, state, pending, 15);
    }
    if (stage == 15) return finishSummary(engine, state, value);
    return error.InvalidCompactionContinuation;
}
pub fn retry(engine: *Engine, intrinsics: *awaiting.Intrinsics, runtime: c.JSValue, context: c.JSValue, live_token: c.JSValue, checkpoint: c.JSValue) !c.JSValue {
    const state = try createState(engine, intrinsics, runtime, context, live_token);
    defer engine.freeValue(state);
    try put(engine, state, "checkpoint", checkpoint);
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const pending = try scope.invoke(runtime, "sleep", &.{ try scope.get(checkpoint, "until"), context });
    return wait(engine, state, pending, 2);
}
fn retryCommit(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, data: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = Engine.fromContext(context.?);
    return retryDraft(engine, data[0], if (argc > 0) argv[0] else c.pi_js_undefined()) catch |err| @import("native_durable.zig").reject(engine, err);
}
fn retryDraft(engine: *Engine, state: c.JSValue, tx: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const runtime = try scope.get(state, "runtime");
    const pending = try scope.invoke(tx, "doc", &.{ try scope.get(state, "liveToken"), try scope.get(runtime, "conversationId") });
    return wait(engine, state, pending, 3);
}
fn delete(engine: *Engine, object: c.JSValue, key: [:0]const u8) !void {
    const atom = c.JS_NewAtom(engine.context, key);
    defer c.JS_FreeAtom(engine.context, atom);
    if (c.JS_DeleteProperty(engine.context, object, atom, c.JS_PROP_THROW) < 0) return js.capture(engine);
}
pub fn select(engine: *Engine, intrinsics: *awaiting.Intrinsics, runtime: c.JSValue, context: c.JSValue, live_token: c.JSValue, task: c.JSValue) !c.JSValue {
    const state = try createState(engine, intrinsics, runtime, context, live_token);
    defer engine.freeValue(state);
    try put(engine, state, "task", task);
    const pending = try vm.invoke(engine, runtime, "agent", &.{context});
    defer engine.freeValue(pending);
    return wait(engine, state, pending, 4);
}
fn failNoModel(engine: *Engine, state: c.JSValue, ref: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const message = if (c.JS_IsUndefined(ref)) try scope.text("No model is configured") else try scope.own(try @import("native_utf16.zig").concat(engine, &.{ try scope.text("Model "), try scope.get(ref, "provider"), try scope.text("/"), try scope.get(ref, "modelId"), try scope.text(" is not available") }));
    const detail = try scope.own(try vm.object(engine));
    try put(engine, detail, "reason", try scope.text("no_model"));
    const failure = try scope.own(try vm.object(engine));
    try put(engine, failure, "message", message);
    try put(engine, failure, "detail", detail);
    const outcome = try scope.own(try vm.object(engine));
    try put(engine, outcome, "status", try scope.text("failed"));
    try put(engine, outcome, "error", failure);
    var intrinsics = try captured(&scope, state);
    return terminal(engine, &intrinsics, try scope.get(state, "runtime"), try scope.get(state, "context"), try scope.get(state, "liveToken"), outcome);
}
fn beforeCompact(engine: *Engine, state: c.JSValue, view: c.JSValue, cut: usize) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const runtime = try scope.get(state, "runtime");
    const task = try scope.get(state, "task");
    const input = try scope.get(task, "input");
    const compaction = try scope.own(try vm.object(engine));
    try put(engine, compaction, "reason", try scope.get(input, "reason"));
    const entries = try scope.get(view, "entries");
    const kept = try scope.own(try engine.checked(c.JS_GetPropertyUint32(engine.context, entries, @intCast(cut))));
    const first = try scope.get(kept, "id");
    try put(engine, state, "firstKept", first);
    try put(engine, compaction, "entries", try scope.invoke(entries, "slice", &.{ c.JS_NewInt32(engine.context, 0), c.JS_NewFloat64(engine.context, @floatFromInt(cut)) }));
    try @import("native_tool_info.zig").putData(engine, compaction, "messages", try @import("native_durable_compaction_text.zig").summarizedMessages(engine, view, cut));
    try put(engine, compaction, "firstKept", first);
    const instructions = try scope.get(input, "instructions");
    if (!c.JS_IsUndefined(instructions)) try put(engine, compaction, "instructions", instructions);
    try put(engine, state, "compaction", compaction);
    var data = [_]c.JSValue{state};
    const callback = try scope.own(try engine.checked(c.JS_NewCFunctionData2(engine.context, hookCallback, "", 1, 0, data.len, &data)));
    const hooks = try scope.get(runtime, "hooks");
    const pending = try scope.invoke(hooks, "each", &.{ try scope.text("beforeCompact"), callback });
    return wait(engine, state, pending, 6);
}
fn hookCallback(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, data: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = Engine.fromContext(context.?);
    return callHook(engine, data[0], if (argc > 0) argv[0] else c.pi_js_undefined()) catch |err| @import("native_durable.zig").reject(engine, err);
}
fn callHook(engine: *Engine, state: c.JSValue, hook: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    if (!c.JS_IsUndefined(try scope.get(state, "decision"))) return c.pi_js_undefined();
    var args = [_]c.JSValue{ try scope.get(state, "compaction"), try scope.get(state, "runtime"), try scope.get(state, "context") };
    const pending = try scope.own(try engine.checked(c.JS_Call(engine.context, hook, c.pi_js_undefined(), args.len, &args)));
    return wait(engine, state, pending, 7);
}
fn pinRequest(engine: *Engine, state: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const runtime = try scope.get(state, "runtime");
    const settings = try scope.get(runtime, "settings");
    const policy = try scope.get(settings, "compaction");
    const model = try scope.get(state, "model");
    const agent = try scope.get(state, "agent");
    var reserve: f64 = 0;
    var model_max: f64 = 0;
    if (c.JS_ToFloat64(engine.context, &reserve, try scope.get(policy, "reserveTokens")) < 0 or c.JS_ToFloat64(engine.context, &model_max, try scope.get(model, "maxTokens")) < 0) return js.capture(engine);
    const math = try scope.own(try js.global(engine, "Math"));
    const floored = try scope.invoke(math, "floor", &.{c.JS_NewFloat64(engine.context, 0.8 * reserve)});
    const max_tokens = try scope.invoke(math, "min", &.{ floored, c.JS_NewFloat64(engine.context, if (model_max > 0) model_max else std.math.inf(f64)) });
    const checkpoint = try scope.own(try vm.object(engine));
    try put(engine, checkpoint, "phase", try scope.text("summarize"));
    try put(engine, checkpoint, "attempt", c.JS_NewInt32(engine.context, 1));
    try put(engine, checkpoint, "model", try scope.get(state, "modelRef"));
    try put(engine, checkpoint, "thinkingLevel", try scope.get(agent, "thinkingLevel"));
    try put(engine, checkpoint, "streamOptions", try scope.get(settings, "stream"));
    try put(engine, checkpoint, "maxTokens", max_tokens);
    const first = try scope.get(state, "firstKept");
    var tail = first;
    var tail_number: f64 = 0;
    if (c.JS_ToFloat64(engine.context, &tail_number, tail) < 0) return js.capture(engine);
    const entries = try scope.get(try scope.get(state, "view"), "entries");
    for (0..try vm.length(engine, entries)) |index| {
        const entry = try scope.own(try engine.checked(c.JS_GetPropertyUint32(engine.context, entries, @intCast(index))));
        const id = try scope.get(entry, "id");
        var number: f64 = 0;
        if (c.JS_ToFloat64(engine.context, &number, id) < 0) return js.capture(engine);
        if (number > tail_number) {
            tail = id;
            tail_number = number;
        }
    }
    try put(engine, checkpoint, "tail", tail);
    try put(engine, checkpoint, "firstKept", first);
    const next = try scope.own(try vm.object(engine));
    try put(engine, next, "status", try scope.text("running"));
    try put(engine, next, "checkpoint", checkpoint);
    var data = [_]c.JSValue{next};
    const callback = try scope.own(try engine.checked(c.JS_NewCFunctionData2(engine.context, returnState, "", 0, 0, data.len, &data)));
    return vm.invoke(engine, runtime, "commit", &.{ callback, try scope.get(state, "context") });
}
fn returnState(context: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue, _: c_int, data: [*c]c.JSValue) callconv(.c) c.JSValue {
    return c.JS_DupValue(context, data[0]);
}
fn completed(engine: *Engine, scope: *Scope, result: c.JSValue) !c.JSValue {
    const outcome = try scope.own(try vm.object(engine));
    try put(engine, outcome, "status", try scope.text("completed"));
    try put(engine, outcome, "result", result);
    const next = try vm.object(engine);
    errdefer engine.freeValue(next);
    try put(engine, next, "status", try scope.text("terminal"));
    try put(engine, next, "outcome", outcome);
    return next;
}
fn place(engine: *Engine, state: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    var data = [_]c.JSValue{state};
    const callback = try scope.own(try engine.checked(c.JS_NewCFunctionData2(engine.context, placeCommit, "", 2, 0, data.len, &data)));
    return vm.invoke(engine, try scope.get(state, "runtime"), "commit", &.{ callback, try scope.get(state, "context") });
}
fn placeCommit(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, data: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = Engine.fromContext(context.?);
    return placeDraft(engine, data[0], if (argc > 0) argv[0] else c.pi_js_undefined(), if (argc > 1) argv[1] else c.pi_js_undefined()) catch |err| @import("native_durable.zig").reject(engine, err);
}
fn placeDraft(engine: *Engine, state: c.JSValue, tx: c.JSValue, current: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    try put(engine, state, "tx", tx);
    try put(engine, state, "current", current);
    const runtime = try scope.get(state, "runtime");
    const pending = try scope.invoke(tx, "doc", &.{ try scope.get(state, "liveToken"), try scope.get(runtime, "conversationId") });
    return wait(engine, state, pending, 8);
}
fn placeDraftReady(engine: *Engine, state: c.JSValue, live: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const runtime = try scope.get(state, "runtime");
    const current = try scope.get(state, "current");
    const tx = try scope.get(state, "tx");
    try @import("native_durable_compaction_status.zig").remove(engine, live, try scope.get(runtime, "taskId"));
    const text = try scope.own(try @import("native_utf16.zig").concat(engine, &.{ try scope.text("The conversation history before this point was compacted into the following summary:\n\n<summary>\n"), try scope.get(state, "summary"), try scope.text("\n</summary>") }));
    const model = try scope.own(try vm.array(engine));
    const message = try scope.own(try vm.object(engine));
    try put(engine, message, "role", try scope.text("user"));
    const content = try scope.own(try vm.array(engine));
    const block = try scope.own(try vm.object(engine));
    try put(engine, block, "type", try scope.text("text"));
    try put(engine, block, "text", text);
    try js.push(engine, content, block);
    try put(engine, message, "content", content);
    try put(engine, message, "timestamp", try scope.invoke(runtime, "now", &.{}));
    try js.push(engine, model, message);
    const entry = try scope.own(try vm.object(engine));
    try put(engine, entry, "kind", try scope.text("pi.compaction"));
    try put(engine, entry, "head", try scope.get(state, "firstKept"));
    try put(engine, entry, "model", model);
    const details = try scope.own(try vm.object(engine));
    try put(engine, details, "reason", try scope.get(try scope.get(current, "input"), "reason"));
    try put(engine, entry, "data", details);
    if (c.JS_IsUndefined(try scope.get(current, "owner"))) {
        const draft = try scope.own(try vm.object(engine));
        try put(engine, draft, "type", try scope.text("write"));
        const task_text = try engine.toString(try scope.get(runtime, "taskId"));
        defer engine.gpa.free(task_text);
        const request = try std.fmt.allocPrint(engine.gpa, "compaction:{s}", .{task_text});
        defer engine.gpa.free(request);
        try put(engine, draft, "requestId", try scope.text(request));
        try put(engine, draft, "entry", entry);
        const exports = engine.native_module_values.get("@earendil-works/pi-durable") orelse return error.DurableModuleUnavailable;
        var captured_intrinsics = try captured(&scope, state);
        const pending = try scope.own(try @import("native_durable_submissions.zig").admit(engine, &captured_intrinsics, .{ .live = try scope.get(exports, "LiveDoc"), .inbox = try scope.get(exports, "InboxDoc"), .user = try scope.get(exports, "UserEntry"), .generation = try scope.get(exports, "GenerationTask") }, tx, try scope.get(runtime, "conversationId"), draft, try scope.invoke(runtime, "now", &.{}), try scope.get(runtime, "settings")));
        return wait(engine, state, pending, 10);
    }
    const pending = try scope.invoke(tx, "appendEntry", &.{ try scope.get(runtime, "conversationId"), entry });
    return wait(engine, state, pending, 9);
}
pub fn summarize(engine: *Engine, captured_intrinsics: *awaiting.Intrinsics, runtime: c.JSValue, context: c.JSValue, live_token: c.JSValue, task: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const state = try scope.own(try createState(engine, captured_intrinsics, runtime, context, live_token));
    try put(engine, state, "task", task);
    const checkpoint = try scope.get(try scope.get(task, "state"), "checkpoint");
    const request = try scope.own(try js.spread(engine, checkpoint));
    try delete(engine, request, "phase");
    try put(engine, state, "request", request);
    const ref = try scope.get(request, "model");
    const model = try scope.invoke(try scope.get(runtime, "models"), "getModel", &.{ try scope.get(ref, "provider"), try scope.get(ref, "modelId") });
    if (c.JS_IsUndefined(model)) return failNoModel(engine, state, ref);
    try put(engine, state, "model", model);
    const options = try scope.own(try vm.object(engine));
    try put(engine, options, "at", try scope.get(request, "tail"));
    const pending = try scope.invoke(runtime, "context", &.{ try scope.get(runtime, "conversationId"), context, options });
    return wait(engine, state, pending, 11);
}
fn prepareSummaryRequest(engine: *Engine, state: c.JSValue, view: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const runtime = try scope.get(state, "runtime");
    const request = try scope.get(state, "request");
    const entries = try scope.get(view, "entries");
    const first = try scope.get(request, "firstKept");
    var cut: i64 = -1;
    for (0..try vm.length(engine, entries)) |index| {
        const entry = try scope.own(try engine.checked(c.JS_GetPropertyUint32(engine.context, entries, @intCast(index))));
        if (c.JS_IsStrictEqual(engine.context, try scope.get(entry, "id"), first)) {
            cut = @intCast(index);
            break;
        }
    }
    const length = try vm.length(engine, entries);
    const selected = if (cut < 0) length - @min(length, 1) else @as(usize, @intCast(cut));
    const messages = try scope.own(try @import("native_durable_compaction_text.zig").summarizedMessages(engine, view, selected));
    const now = try scope.invoke(runtime, "now", &.{});
    const context_messages = try scope.own(try vm.array(engine));
    const system = try scope.own(try vm.object(engine));
    try put(engine, system, "role", try scope.text("system"));
    try put(engine, system, "content", try scope.text(@embedFile("compaction_system_prompt.txt")));
    try put(engine, system, "timestamp", now);
    try js.push(engine, context_messages, system);
    const user = try scope.own(try vm.object(engine));
    try put(engine, user, "role", try scope.text("user"));
    const content = try scope.own(try vm.array(engine));
    const block = try scope.own(try vm.object(engine));
    try put(engine, block, "type", try scope.text("text"));
    const instructions = try scope.get(try scope.get(try scope.get(state, "task"), "input"), "instructions");
    try @import("native_tool_info.zig").putData(engine, block, "text", try @import("native_durable_compaction_text.zig").summaryPrompt(engine, messages, instructions));
    try js.push(engine, content, block);
    try put(engine, user, "content", content);
    try put(engine, user, "timestamp", now);
    try js.push(engine, context_messages, user);
    try put(engine, state, "summaryMessages", context_messages);
    try put(engine, state, "firstKept", first);
    const exports = engine.native_module_values.get("@earendil-works/pi-durable") orelse return error.DurableModuleUnavailable;
    var captured_intrinsics = try captured(&scope, state);
    const pending = try scope.own(try @import("native_durable_provider.zig").ensure(engine, &captured_intrinsics, runtime, try scope.get(state, "context"), try scope.get(exports, "ProviderDoc")));
    return wait(engine, state, pending, 12);
}
fn callSummaryModel(engine: *Engine, state: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const runtime = try scope.get(state, "runtime");
    const request = try scope.get(state, "request");
    const options = try scope.own(try js.spread(engine, try scope.get(request, "streamOptions")));
    try delete(engine, options, "deferred");
    try put(engine, options, "cacheRetention", try scope.text("none"));
    try put(engine, options, "maxTokens", try scope.get(request, "maxTokens"));
    try put(engine, options, "signal", try scope.get(runtime, "signal"));
    try put(engine, options, "sessionId", try scope.get(state, "providerSessionId"));
    const thinking = try scope.get(request, "thinkingLevel");
    if (!try @import("native_durable_tool_call.zig").equalsString(engine, thinking, "off")) try put(engine, options, "reasoning", thinking);
    const model_context = try scope.own(try vm.object(engine));
    try put(engine, model_context, "messages", try scope.get(state, "summaryMessages"));
    const pending = try scope.invoke(try scope.get(runtime, "models"), "completeSimple", &.{ try scope.get(state, "model"), model_context, options });
    return wait(engine, state, pending, 13);
}
fn classifySummary(engine: *Engine, state: c.JSValue, message: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const runtime = try scope.get(state, "runtime");
    _ = try scope.invoke(try scope.get(runtime, "signal"), "throwIfAborted", &.{});
    const summary = try scope.own(try @import("native_durable_compaction_text.zig").summaryText(engine, message));
    try put(engine, state, "summary", summary);
    const policy = try scope.get(try scope.get(runtime, "settings"), "retry");
    const request = try scope.get(state, "request");
    var attempt: f64 = 0;
    var maximum: f64 = 0;
    if (c.JS_ToFloat64(engine.context, &attempt, try scope.get(request, "attempt")) < 0 or c.JS_ToFloat64(engine.context, &maximum, try scope.get(policy, "maxRetries")) < 0) return js.capture(engine);
    const retry_value = try @import("native_durable_retry.zig").retryable(engine, message) and c.JS_ToBool(engine.context, try scope.get(policy, "enabled")) != 0 and attempt <= maximum;
    try put(engine, state, "retry", c.pi_js_bool(engine.context, @intFromBool(retry_value)));
    var until: f64 = 0;
    if (retry_value) {
        const now = try scope.invoke(runtime, "now", &.{});
        const delay = try scope.own(try @import("native_durable_retry.zig").delay(engine, policy, try scope.get(request, "attempt")));
        var current: f64 = 0;
        var pause: f64 = 0;
        if (c.JS_ToFloat64(engine.context, &current, now) < 0 or c.JS_ToFloat64(engine.context, &pause, delay) < 0) return js.capture(engine);
        until = current + pause;
    }
    try put(engine, state, "until", c.JS_NewFloat64(engine.context, until));
    var data = [_]c.JSValue{state};
    const callback = try scope.own(try engine.checked(c.JS_NewCFunctionData2(engine.context, summaryCommit, "", 2, 0, data.len, &data)));
    return vm.invoke(engine, runtime, "commit", &.{ callback, try scope.get(state, "context") });
}
fn summaryCommit(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, data: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = Engine.fromContext(context.?);
    return summaryDraft(engine, data[0], if (argc > 0) argv[0] else c.pi_js_undefined(), if (argc > 1) argv[1] else c.pi_js_undefined()) catch |err| @import("native_durable.zig").reject(engine, err);
}
fn summaryDraft(engine: *Engine, state: c.JSValue, tx: c.JSValue, current: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    try put(engine, state, "tx", tx);
    try put(engine, state, "current", current);
    const runtime = try scope.get(state, "runtime");
    const message = try scope.get(state, "message");
    const key = try scope.own(try @import("native_utf16.zig").concat(engine, &.{ try scope.get(message, "provider"), try scope.text("/"), try scope.get(message, "model") }));
    const exports = engine.native_module_values.get("@earendil-works/pi-durable") orelse return error.DurableModuleUnavailable;
    var captured_intrinsics = try captured(&scope, state);
    const pending = try scope.own(try @import("native_durable_usage.zig").record(engine, &captured_intrinsics, tx, try scope.get(runtime, "conversationId"), "models", key, try scope.get(message, "usage"), try scope.get(exports, "UsageDoc")));
    return wait(engine, state, pending, 14);
}
fn finishSummary(engine: *Engine, state: c.JSValue, live: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const runtime = try scope.get(state, "runtime");
    const task_id = try scope.get(runtime, "taskId");
    if (!c.JS_IsUndefined(try scope.get(state, "summary"))) return placeDraftReady(engine, state, live);
    if (c.JS_ToBool(engine.context, try scope.get(state, "retry")) != 0) {
        const status = try scope.own(try @import("native_durable_compaction_status.zig").find(engine, live, task_id));
        if (!c.JS_IsUndefined(status)) {
            const retry_value = try scope.own(try vm.object(engine));
            try put(engine, retry_value, "at", try scope.get(state, "until"));
            const message = try scope.get(state, "message");
            const error_message = try scope.get(message, "errorMessage");
            try put(engine, retry_value, "error", if (c.JS_IsUndefined(error_message) or c.JS_IsNull(error_message)) try scope.text("") else error_message);
            try put(engine, status, "retry", retry_value);
        }
        const checkpoint = try scope.own(try vm.object(engine));
        try put(engine, checkpoint, "phase", try scope.text("retry"));
        try js.spreadInto(engine, checkpoint, try scope.get(state, "request"));
        try put(engine, checkpoint, "until", try scope.get(state, "until"));
        const next = try vm.object(engine);
        errdefer engine.freeValue(next);
        try put(engine, next, "status", try scope.text("running"));
        try put(engine, next, "checkpoint", checkpoint);
        return next;
    }
    try @import("native_durable_compaction_status.zig").remove(engine, live, task_id);
    const detail = try scope.own(try vm.object(engine));
    try put(engine, detail, "reason", try scope.text("model_error"));
    const failure = try scope.own(try vm.object(engine));
    try @import("native_tool_info.zig").putData(engine, failure, "message", try @import("native_durable_compaction_text.zig").summaryFailure(engine, try scope.get(state, "message")));
    try put(engine, failure, "detail", detail);
    const outcome = try scope.own(try vm.object(engine));
    try put(engine, outcome, "status", try scope.text("failed"));
    try put(engine, outcome, "error", failure);
    const next = try vm.object(engine);
    errdefer engine.freeValue(next);
    try put(engine, next, "status", try scope.text("terminal"));
    try put(engine, next, "outcome", outcome);
    return next;
}
