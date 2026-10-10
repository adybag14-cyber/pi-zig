//! Native generation task phase continuations. Public token waits for all phases.
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
fn createState(engine: *Engine, intrinsics: *awaiting.Intrinsics, runtime: c.JSValue, context: c.JSValue, live_token: c.JSValue, task: c.JSValue) !c.JSValue {
    const state = try vm.object(engine);
    errdefer engine.freeValue(state);
    inline for (.{ .{ "promiseConstructor", intrinsics.constructor }, .{ "promiseResolve", intrinsics.resolve }, .{ "promiseThen", intrinsics.then_function }, .{ "runtime", runtime }, .{ "context", context }, .{ "liveToken", live_token }, .{ "task", task } }) |field| try put(engine, state, field[0], field[1]);
    return state;
}
fn wait(engine: *Engine, state: c.JSValue, pending: c.JSValue, stage: c_int) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    var intrinsics = try captured(&scope, state);
    return awaiting.continueWith(advance, engine, &intrinsics, state, pending, stage);
}
pub fn retry(engine: *Engine, intrinsics: *awaiting.Intrinsics, runtime: c.JSValue, context: c.JSValue, live_token: c.JSValue, task: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const state = try scope.own(try createState(engine, intrinsics, runtime, context, live_token, task));
    const checkpoint = try scope.get(try scope.get(task, "state"), "checkpoint");
    try put(engine, state, "checkpoint", checkpoint);
    const pending = try scope.invoke(runtime, "sleep", &.{ try scope.get(checkpoint, "until"), context });
    return wait(engine, state, pending, 1);
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
    return wait(engine, state, pending, 2);
}
fn advance(engine: *Engine, state: c.JSValue, value: c.JSValue, rejected: bool, stage: c_int) anyerror!c.JSValue {
    if (stage == 7) return afterEnvironment(engine, state, value, rejected);
    if (rejected) return engine.checked(c.JS_Throw(engine.context, c.JS_DupValue(engine.context, value)));
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    if (stage == 1) {
        var data = [_]c.JSValue{state};
        const callback = try scope.own(try engine.checked(c.JS_NewCFunctionData2(engine.context, retryCommit, "", 1, 0, data.len, &data)));
        return vm.invoke(engine, try scope.get(state, "runtime"), "commit", &.{ callback, try scope.get(state, "context") });
    }
    if (stage == 2) {
        const checkpoint = try scope.get(state, "checkpoint");
        var attempt: f64 = 0;
        if (c.JS_ToFloat64(engine.context, &attempt, try scope.get(checkpoint, "attempt")) < 0) return js.capture(engine);
        attempt += 1;
        const generation = try scope.own(try vm.object(engine));
        try put(engine, generation, "attempt", c.JS_NewFloat64(engine.context, attempt));
        try put(engine, value, "generation", generation);
        const next_checkpoint = try scope.own(try vm.object(engine));
        try put(engine, next_checkpoint, "phase", try scope.text("prepare"));
        try put(engine, next_checkpoint, "attempt", c.JS_NewFloat64(engine.context, attempt));
        const compacted = try scope.get(checkpoint, "compacted");
        if (!c.JS_IsUndefined(compacted)) try put(engine, next_checkpoint, "compacted", compacted);
        const next = try vm.object(engine);
        errdefer engine.freeValue(next);
        try put(engine, next, "status", try scope.text("running"));
        try put(engine, next, "checkpoint", next_checkpoint);
        return next;
    }
    if (stage == 3) {
        const runtime = try scope.get(state, "runtime");
        const reason = try scope.get(state, "failureReason");
        const settlement = try scope.own(try vm.object(engine));
        try put(engine, settlement, "status", try scope.text("unanswered"));
        try put(engine, settlement, "reason", reason);
        const model_error = try scope.text("model_error");
        if (c.JS_IsStrictEqual(engine.context, reason, model_error)) try put(engine, settlement, "detail", try scope.get(state, "failureMessage"));
        try @import("native_durable_generation_live.zig").endRun(engine, try scope.get(state, "tx"), value, try scope.get(runtime, "taskId"), settlement);
        const detail = try scope.own(try vm.object(engine));
        try put(engine, detail, "reason", reason);
        const failure = try scope.own(try vm.object(engine));
        try put(engine, failure, "message", try scope.get(state, "failureMessage"));
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
    if (stage == 4) {
        const request = try scope.get(state, "request");
        const generation = try scope.own(try vm.object(engine));
        try put(engine, generation, "attempt", try scope.get(request, "attempt"));
        const polling = try scope.own(try vm.object(engine));
        try put(engine, polling, "pollAt", try scope.get(state, "pollAt"));
        try put(engine, generation, "deferred", polling);
        try put(engine, value, "generation", generation);
        const checkpoint = try scope.own(try vm.object(engine));
        try put(engine, checkpoint, "phase", try scope.text("poll"));
        try put(engine, checkpoint, "attempt", try scope.get(request, "attempt"));
        const compacted = try scope.get(request, "compacted");
        if (!c.JS_IsUndefined(compacted)) try put(engine, checkpoint, "compacted", compacted);
        inline for (.{ "model", "cutoff" }) |key| try put(engine, checkpoint, key, try scope.get(request, key));
        try put(engine, checkpoint, "handle", try scope.get(state, "handle"));
        try put(engine, checkpoint, "pollAt", try scope.get(state, "pollAt"));
        const next = try vm.object(engine);
        errdefer engine.freeValue(next);
        try put(engine, next, "status", try scope.text("running"));
        try put(engine, next, "checkpoint", checkpoint);
        return next;
    }
    if (stage == 5) {
        const runtime = try scope.get(state, "runtime");
        const ref = try scope.get(value, "model");
        var intrinsics = try captured(&scope, state);
        if (c.JS_IsUndefined(ref)) return failNoModel(engine, &intrinsics, runtime, try scope.get(state, "context"), try scope.get(state, "liveToken"), ref);
        const model = try scope.invoke(try scope.get(runtime, "models"), "getModel", &.{ try scope.get(ref, "provider"), try scope.get(ref, "modelId") });
        if (c.JS_IsUndefined(model)) return failNoModel(engine, &intrinsics, runtime, try scope.get(state, "context"), try scope.get(state, "liveToken"), ref);
        try put(engine, state, "agent", value);
        try put(engine, state, "model", model);
        try put(engine, state, "modelRef", ref);
        const checkpoint = try scope.get(try scope.get(try scope.get(state, "task"), "state"), "checkpoint");
        try put(engine, state, "checkpoint", checkpoint);
        if (!c.JS_IsUndefined(try scope.get(checkpoint, "compacted")) and !c.JS_IsUndefined(try scope.get(checkpoint, "overflow"))) {
            const ids = try scope.own(try vm.array(engine));
            try js.push(engine, ids, try scope.get(checkpoint, "compacted"));
            const pending = try scope.invoke(runtime, "outcomes", &.{ ids, try scope.get(state, "context") });
            return wait(engine, state, pending, 14);
        }
        const pending = try scope.invoke(runtime, "context", &.{ try scope.get(runtime, "conversationId"), try scope.get(state, "context") });
        return wait(engine, state, pending, 6);
    }
    if (stage == 6) {
        try put(engine, state, "view", value);
        const shown = try scope.own(try @import("native_durable_prompt.zig").replaySections(engine, try scope.get(value, "messages")));
        try put(engine, state, "shown", shown);
        const runtime = try scope.get(state, "runtime");
        const pending = scope.invoke(runtime, "env", &.{try scope.get(state, "context")}) catch |err| {
            if (err != error.JavaScriptException) return err;
            return afterEnvironment(engine, state, engine.captured_exception orelse return err, true);
        };
        return wait(engine, state, pending, 7);
    }
    if (stage == 8) {
        const runtime = try scope.get(state, "runtime");
        const agent = try scope.get(state, "agent");
        const view = try scope.get(state, "view");
        const entries = try scope.own(try @import("native_durable_prompt.zig").planSystemEntries(engine, view, value, try scope.get(agent, "tools"), try scope.invoke(runtime, "now", &.{})));
        try put(engine, state, "entries", entries);
        const checkpoint = try scope.get(state, "checkpoint");
        var threshold: ?Threshold = null;
        if (c.JS_IsUndefined(try scope.get(checkpoint, "compacted"))) {
            var window: f64 = 0;
            if (c.JS_ToFloat64(engine.context, &window, try scope.get(try scope.get(state, "model"), "contextWindow")) < 0) return js.capture(engine);
            threshold = try thresholdCompaction(engine, view, entries, window, try scope.get(try scope.get(runtime, "settings"), "compaction"));
        }
        if (threshold) |selected| try put(engine, state, "threshold", try scope.text(@tagName(selected)));
        var data = [_]c.JSValue{state};
        const callback = try scope.own(try engine.checked(c.JS_NewCFunctionData2(engine.context, prepareCommit, "", 1, 0, data.len, &data)));
        return vm.invoke(engine, runtime, "commit", &.{ callback, try scope.get(state, "context") });
    }
    if (stage == 9) {
        const items = try scope.get(value, "items");
        const first = try scope.own(try engine.checked(c.JS_GetPropertyUint32(engine.context, items, 0)));
        if (!c.JS_IsUndefined(first)) try put(engine, state, "cutoff", try scope.get(first, "id"));
        try put(engine, state, "entryIndex", c.JS_NewInt32(engine.context, 0));
        return appendPreparedEntry(engine, state);
    }
    if (stage == 10) {
        try put(engine, state, "cutoff", try scope.get(value, "id"));
        return appendPreparedEntry(engine, state);
    }
    if (stage == 11) {
        const checkpoint = try scope.own(try vm.object(engine));
        try put(engine, checkpoint, "phase", try scope.text("prepare"));
        try put(engine, checkpoint, "attempt", try scope.get(try scope.get(state, "checkpoint"), "attempt"));
        try put(engine, checkpoint, "compacted", value);
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
    if (stage == 12) {
        if (!c.JS_IsUndefined(try scope.get(value, "compactions"))) return preparedCheckpoint(engine, state);
        const runtime = try scope.get(state, "runtime");
        const input = try scope.own(try vm.object(engine));
        try put(engine, input, "reason", try scope.text("threshold"));
        const exports = engine.native_module_values.get("@earendil-works/pi-durable") orelse return error.DurableModuleUnavailable;
        var intrinsics = try captured(&scope, state);
        const pending = try scope.own(try @import("native_durable_compaction_task.zig").createCompaction(engine, &intrinsics, try scope.get(state, "tx"), try scope.get(runtime, "conversationId"), input, c.pi_js_undefined(), try scope.get(exports, "CompactionTask"), try scope.get(state, "liveToken")));
        return wait(engine, state, pending, 13);
    }
    if (stage == 13) return preparedCheckpoint(engine, state);
    if (stage == 14) {
        const outcome = try scope.own(try engine.checked(c.JS_GetPropertyUint32(engine.context, value, 0)));
        var succeeded = false;
        if (!c.JS_IsUndefined(outcome)) {
            const status = try scope.get(outcome, "status");
            const completed = try scope.text("completed");
            if (c.JS_IsStrictEqual(engine.context, status, completed)) succeeded = !c.JS_IsUndefined(try scope.get(try scope.get(outcome, "result"), "entryId"));
        }
        if (!succeeded) {
            try put(engine, state, "failureMessage", try scope.get(try scope.get(state, "checkpoint"), "overflow"));
            try put(engine, state, "failureReason", try scope.text("model_error"));
            return fail(engine, state);
        }
        const runtime = try scope.get(state, "runtime");
        const pending = try scope.invoke(runtime, "context", &.{ try scope.get(runtime, "conversationId"), try scope.get(state, "context") });
        return wait(engine, state, pending, 6);
    }
    if (stage == 15) {
        try put(engine, state, "live", value);
        const generation = try scope.get(value, "generation");
        if (!c.JS_IsUndefined(generation) and !c.JS_IsNull(generation)) {
            const partial = try scope.get(generation, "message");
            if (!c.JS_IsUndefined(partial)) {
                const options = try scope.own(try vm.object(engine));
                const copied = try scope.own(try @import("native_chord_json.zig").copyJson(engine, partial, options));
                try put(engine, copied, "stopReason", try scope.text("aborted"));
                var intrinsics = try captured(&scope, state);
                const pending = try scope.own(try appendAssistant(engine, &intrinsics, try scope.get(state, "tx"), try scope.get(try scope.get(state, "runtime"), "conversationId"), copied));
                return wait(engine, state, pending, 16);
            }
        }
        return requestStarted(engine, state, value);
    }
    if (stage == 17) {
        const runtime = try scope.get(state, "runtime");
        const checkpoint = try scope.get(state, "checkpoint");
        const ref = try scope.get(checkpoint, "model");
        var intrinsics = try captured(&scope, state);
        const model = try scope.invoke(try scope.get(runtime, "models"), "getModel", &.{ try scope.get(ref, "provider"), try scope.get(ref, "modelId") });
        if (c.JS_IsUndefined(model)) return failNoModel(engine, &intrinsics, runtime, try scope.get(state, "context"), try scope.get(state, "liveToken"), ref);
        try put(engine, state, "model", model);
        const options = try scope.own(try vm.object(engine));
        try put(engine, options, "at", try scope.get(checkpoint, "cutoff"));
        const pending = try scope.invoke(runtime, "context", &.{ try scope.get(runtime, "conversationId"), try scope.get(state, "context"), options });
        return wait(engine, state, pending, 18);
    }
    if (stage == 16) return requestStarted(engine, state, try scope.get(state, "live"));
    if (stage == 30) {
        const model = try scope.own(try vm.array(engine));
        try js.push(engine, model, try scope.get(state, "message"));
        const entry = try scope.own(try vm.object(engine));
        try put(engine, entry, "model", model);
        const exports = engine.native_module_values.get("@earendil-works/pi-durable") orelse return error.DurableModuleUnavailable;
        return vm.invoke(engine, try scope.get(state, "tx"), "appendEntry", &.{ try scope.get(exports, "AssistantEntry"), try scope.get(state, "conversation"), entry });
    }
    if (stage == 18) {
        try put(engine, state, "view", value);
        try put(engine, state, "messages", try scope.get(value, "messages"));
        const runtime = try scope.get(state, "runtime");
        var data = [_]c.JSValue{state};
        const callback = try scope.own(try engine.checked(c.JS_NewCFunctionData2(engine.context, beforeRequestCallback, "", 1, 0, data.len, &data)));
        const pending = try scope.invoke(try scope.get(runtime, "hooks"), "each", &.{ try scope.text("beforeRequest"), callback });
        return wait(engine, state, pending, 20);
    }
    if (stage == 19) {
        if (!c.JS_IsUndefined(value)) try put(engine, state, "messages", try scope.get(value, "messages"));
        return c.pi_js_undefined();
    }
    if (stage == 20) {
        var intrinsics = try captured(&scope, state);
        const exports = engine.native_module_values.get("@earendil-works/pi-durable") orelse return error.DurableModuleUnavailable;
        const pending = try scope.own(try @import("native_durable_provider.zig").ensure(engine, &intrinsics, try scope.get(state, "runtime"), try scope.get(state, "context"), try scope.get(exports, "ProviderDoc")));
        return wait(engine, state, pending, 21);
    }
    if (stage == 21) {
        const runtime = try scope.get(state, "runtime");
        const checkpoint = try scope.get(state, "checkpoint");
        const options = try scope.own(try js.spread(engine, try scope.get(checkpoint, "streamOptions")));
        try put(engine, options, "signal", try scope.get(runtime, "signal"));
        try put(engine, options, "sessionId", value);
        const thinking = try scope.get(checkpoint, "thinkingLevel");
        const off = try scope.text("off");
        if (!c.JS_IsStrictEqual(engine.context, thinking, off)) try put(engine, options, "reasoning", thinking);
        var intrinsics = try captured(&scope, state);
        const pending = try scope.own(try @import("native_durable_generation_stream.zig").run(engine, &intrinsics, runtime, try scope.get(state, "model"), try scope.get(state, "messages"), options, try scope.get(checkpoint, "attempt"), try scope.get(state, "context"), try scope.get(state, "liveToken")));
        return wait(engine, state, pending, 22);
    }
    if (stage == 22) {
        const checkpoint = try scope.get(state, "checkpoint");
        const request_value = try scope.own(try vm.object(engine));
        inline for (.{ "attempt", "compacted", "model", "cutoff" }) |key| try put(engine, request_value, key, try scope.get(checkpoint, key));
        try put(engine, request_value, "messages", try scope.get(try scope.get(state, "view"), "messages"));
        var intrinsics = try captured(&scope, state);
        return classify(engine, &intrinsics, try scope.get(state, "runtime"), try scope.get(state, "context"), try scope.get(state, "liveToken"), request_value, value);
    }
    if (stage == 23) {
        const message = try scope.get(state, "message");
        const reason = try scope.get(message, "stopReason");
        inline for (.{ "stop", "length", "toolUse" }) |tag| {
            const text = try scope.text(tag);
            if (c.JS_IsStrictEqual(engine.context, reason, text)) {
                if (comptime std.mem.eql(u8, tag, "toolUse")) {
                    const content = try scope.get(message, "content");
                    for (0..try vm.length(engine, content)) |index| {
                        const block = try scope.own(try engine.checked(c.JS_GetPropertyUint32(engine.context, content, @intCast(index))));
                        const kind = try scope.get(block, "type");
                        const tool_call = try scope.text("toolCall");
                        if (c.JS_IsStrictEqual(engine.context, kind, tool_call)) {
                            const calls = try scope.own(try vm.array(engine));
                            for (0..try vm.length(engine, content)) |position| {
                                const candidate = try scope.own(try engine.checked(c.JS_GetPropertyUint32(engine.context, content, @intCast(position))));
                                if (c.JS_IsStrictEqual(engine.context, try scope.get(candidate, "type"), tool_call)) try js.push(engine, calls, candidate);
                            }
                            var intrinsics = try captured(&scope, state);
                            return @import("native_durable_generation_tools.zig").start(engine, &intrinsics, try scope.get(state, "runtime"), try scope.get(state, "context"), try scope.get(state, "request"), message, calls);
                        }
                    }
                }
                const exports = engine.native_module_values.get("@earendil-works/pi-durable") orelse return error.DurableModuleUnavailable;
                var intrinsics = try captured(&scope, state);
                return @import("native_durable_generation_answer.zig").run(engine, &intrinsics, try scope.get(state, "runtime"), try scope.get(state, "context"), message, try scope.get(exports, "GenerationTask"));
            }
        }
        return classifyError(engine, state);
    }
    if (stage == 24) {
        try put(engine, state, "live", value);
        var intrinsics = try captured(&scope, state);
        const pending = try scope.own(try appendAssistant(engine, &intrinsics, try scope.get(state, "tx"), try scope.get(try scope.get(state, "runtime"), "conversationId"), try scope.get(state, "message")));
        return wait(engine, state, pending, 25);
    }
    if (stage == 25) return classifiedErrorOutcome(engine, state);
    if (stage == 26) {
        const runtime = try scope.get(state, "runtime");
        const policy = try scope.get(try scope.get(runtime, "settings"), "compaction");
        var keep: f64 = 0;
        if (c.JS_ToFloat64(engine.context, &keep, try scope.get(policy, "keepRecentTokens")) < 0) return js.capture(engine);
        if (try @import("native_durable_compaction_text.zig").selectCut(engine, value, keep) == null) return classifyError(engine, state);
        try put(engine, state, "overflowCompaction", c.pi_js_bool(engine.context, 1));
        var data = [_]c.JSValue{state};
        const callback = try scope.own(try engine.checked(c.JS_NewCFunctionData2(engine.context, errorCommit, "", 1, 0, data.len, &data)));
        return vm.invoke(engine, runtime, "commit", &.{ callback, try scope.get(state, "context") });
    }
    if (stage == 27) {
        const request_value = try scope.get(state, "request");
        const checkpoint = try scope.own(try vm.object(engine));
        try put(engine, checkpoint, "phase", try scope.text("prepare"));
        try put(engine, checkpoint, "attempt", try scope.get(request_value, "attempt"));
        try put(engine, checkpoint, "compacted", value);
        const error_message = try scope.get(try scope.get(state, "message"), "errorMessage");
        try put(engine, checkpoint, "overflow", if (c.JS_IsUndefined(error_message) or c.JS_IsNull(error_message)) try scope.text("Context overflow") else error_message);
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
    if (stage == 28) {
        const runtime = try scope.get(state, "runtime");
        const options = try scope.own(try vm.object(engine));
        try put(engine, options, "signal", try scope.get(runtime, "signal"));
        const pending = try scope.invoke(try scope.get(runtime, "models"), "fetchDeferred", &.{ try scope.get(state, "model"), try scope.get(try scope.get(state, "checkpoint"), "handle"), options });
        return wait(engine, state, pending, 29);
    }
    if (stage == 29) {
        const checkpoint = try scope.get(state, "checkpoint");
        const request_value = try scope.own(try vm.object(engine));
        inline for (.{ "attempt", "compacted", "model", "cutoff", "pollAt" }) |key| try put(engine, request_value, key, try scope.get(checkpoint, key));
        var intrinsics = try captured(&scope, state);
        return classify(engine, &intrinsics, try scope.get(state, "runtime"), try scope.get(state, "context"), try scope.get(state, "liveToken"), request_value, value);
    }
    return error.InvalidGenerationContinuation;
}
pub fn failNoModel(engine: *Engine, intrinsics: *awaiting.Intrinsics, runtime: c.JSValue, context: c.JSValue, live_token: c.JSValue, ref: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const state = try scope.own(try createState(engine, intrinsics, runtime, context, live_token, c.pi_js_undefined()));
    const message = if (c.JS_IsUndefined(ref)) try scope.text("No model is configured") else try scope.own(try @import("native_utf16.zig").concat(engine, &.{ try scope.text("Model "), try scope.get(ref, "provider"), try scope.text("/"), try scope.get(ref, "modelId"), try scope.text(" is not available") }));
    try put(engine, state, "failureMessage", message);
    try put(engine, state, "failureReason", try scope.text("no_model"));
    return fail(engine, state);
}
fn fail(engine: *Engine, state: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    var data = [_]c.JSValue{state};
    const callback = try scope.own(try engine.checked(c.JS_NewCFunctionData2(engine.context, failCommit, "", 1, 0, data.len, &data)));
    return vm.invoke(engine, try scope.get(state, "runtime"), "commit", &.{ callback, try scope.get(state, "context") });
}
fn failCommit(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, data: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = Engine.fromContext(context.?);
    return failDraft(engine, data[0], if (argc > 0) argv[0] else c.pi_js_undefined()) catch |err| @import("native_durable.zig").reject(engine, err);
}
fn failDraft(engine: *Engine, state: c.JSValue, tx: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    try put(engine, state, "tx", tx);
    const runtime = try scope.get(state, "runtime");
    const pending = try scope.invoke(tx, "doc", &.{ try scope.get(state, "liveToken"), try scope.get(runtime, "conversationId") });
    return wait(engine, state, pending, 3);
}
pub fn deferred(engine: *Engine, intrinsics: *awaiting.Intrinsics, runtime: c.JSValue, context: c.JSValue, live_token: c.JSValue, request: c.JSValue, message: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const state = try scope.own(try createState(engine, intrinsics, runtime, context, live_token, c.pi_js_undefined()));
    try put(engine, state, "request", request);
    try put(engine, state, "handle", try scope.get(message, "deferred"));
    const signal = try scope.get(runtime, "signal");
    _ = try scope.invoke(signal, "throwIfAborted", &.{});
    const handle = try scope.get(state, "handle");
    const delay = try scope.get(handle, "pollAfterMs");
    var delay_number: f64 = 5000;
    if (!c.JS_IsUndefined(delay) and !c.JS_IsNull(delay) and c.JS_ToFloat64(engine.context, &delay_number, delay) < 0) return js.capture(engine);
    var now: f64 = 0;
    if (c.JS_ToFloat64(engine.context, &now, try scope.invoke(runtime, "now", &.{})) < 0) return js.capture(engine);
    const previous = try scope.get(request, "pollAt");
    var previous_number: f64 = -std.math.inf(f64);
    if (!c.JS_IsUndefined(previous)) {
        if (c.JS_ToFloat64(engine.context, &previous_number, previous) < 0) return js.capture(engine);
        previous_number += 1;
    }
    const math = try scope.own(try js.global(engine, "Math"));
    const at = try scope.invoke(math, "max", &.{ c.JS_NewFloat64(engine.context, now + delay_number), c.JS_NewFloat64(engine.context, previous_number) });
    try put(engine, state, "pollAt", at);
    var data = [_]c.JSValue{state};
    const callback = try scope.own(try engine.checked(c.JS_NewCFunctionData2(engine.context, deferredCommit, "", 1, 0, data.len, &data)));
    return vm.invoke(engine, runtime, "commit", &.{ callback, context });
}
fn deferredCommit(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, data: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = Engine.fromContext(context.?);
    return deferredDraft(engine, data[0], if (argc > 0) argv[0] else c.pi_js_undefined()) catch |err| @import("native_durable.zig").reject(engine, err);
}
fn deferredDraft(engine: *Engine, state: c.JSValue, tx: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const runtime = try scope.get(state, "runtime");
    const pending = try scope.invoke(tx, "doc", &.{ try scope.get(state, "liveToken"), try scope.get(runtime, "conversationId") });
    return wait(engine, state, pending, 4);
}
pub fn prepare(engine: *Engine, intrinsics: *awaiting.Intrinsics, runtime: c.JSValue, context: c.JSValue, live_token: c.JSValue, task: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const state = try scope.own(try createState(engine, intrinsics, runtime, context, live_token, task));
    const pending = try scope.invoke(runtime, "agent", &.{context});
    return wait(engine, state, pending, 5);
}
fn reportCallback(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, data: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = Engine.fromContext(context.?);
    return vm.invoke(engine, data[0], "report", &.{if (argc > 0) argv[0] else c.pi_js_undefined()}) catch |err| @import("native_durable.zig").reject(engine, err);
}
fn afterEnvironment(engine: *Engine, state: c.JSValue, value: c.JSValue, rejected: bool) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const runtime = try scope.get(state, "runtime");
    const context = try scope.get(state, "context");
    if (rejected) {
        const signal = try scope.get(context, "abortSignal");
        if (!c.JS_IsUndefined(signal) and !c.JS_IsNull(signal) and c.JS_ToBool(engine.context, try scope.get(signal, "aborted")) != 0) return engine.checked(c.JS_Throw(engine.context, c.JS_DupValue(engine.context, value)));
        _ = try scope.invoke(runtime, "report", &.{value});
    }
    const input = try scope.own(try vm.object(engine));
    try put(engine, input, "conversationId", try scope.get(runtime, "conversationId"));
    const agent = try scope.get(state, "agent");
    try put(engine, input, "agent", agent);
    try put(engine, input, "env", if (rejected) c.pi_js_undefined() else value);
    const shown = try scope.get(state, "shown");
    const object = try scope.own(try js.global(engine, "Object"));
    try put(engine, input, "shown", try scope.invoke(object, "fromEntries", &.{shown}));
    try put(engine, input, "read", runtime);
    var data = [_]c.JSValue{runtime};
    const report = try scope.own(try engine.checked(c.JS_NewCFunctionData2(engine.context, reportCallback, "", 1, 0, data.len, &data)));
    var intrinsics = try captured(&scope, state);
    const pending = try scope.own(try @import("native_durable_prompt.zig").renderSections(engine, &intrinsics, try scope.get(agent, "sections"), input, shown, report, context));
    return wait(engine, state, pending, 8);
}
pub const Threshold = enum { blocking, background };
pub fn thresholdCompaction(engine: *Engine, view: c.JSValue, planned: c.JSValue, context_window: f64, policy: c.JSValue) !?Threshold {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    if (c.JS_ToBool(engine.context, try scope.get(policy, "enabled")) == 0 or context_window <= 0) return null;
    const extra = try scope.own(try vm.array(engine));
    for (0..try vm.length(engine, planned)) |index| {
        const entry = try scope.own(try engine.checked(c.JS_GetPropertyUint32(engine.context, planned, @intCast(index))));
        const model = try scope.get(entry, "model");
        if (c.JS_IsUndefined(model) or c.JS_IsNull(model)) continue;
        for (0..try vm.length(engine, model)) |position| {
            const message = try scope.own(try engine.checked(c.JS_GetPropertyUint32(engine.context, model, @intCast(position))));
            try js.push(engine, extra, message);
        }
    }
    const tokens = try @import("native_durable_compaction_text.zig").estimateContext(engine, view, extra);
    var reserve: f64 = 0;
    var background: f64 = 0;
    var keep: f64 = 0;
    if (c.JS_ToFloat64(engine.context, &reserve, try scope.get(policy, "reserveTokens")) < 0 or c.JS_ToFloat64(engine.context, &background, try scope.get(policy, "backgroundTokens")) < 0 or c.JS_ToFloat64(engine.context, &keep, try scope.get(policy, "keepRecentTokens")) < 0) return js.capture(engine);
    const over: ?Threshold = if (tokens > context_window - reserve) .blocking else if (background > 0 and tokens > context_window - reserve - background) .background else null;
    if (over == null or try @import("native_durable_compaction_text.zig").selectCut(engine, view, keep) == null) return null;
    return over;
}
fn prepareCommit(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, data: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = Engine.fromContext(context.?);
    return prepareDraft(engine, data[0], if (argc > 0) argv[0] else c.pi_js_undefined()) catch |err| @import("native_durable.zig").reject(engine, err);
}
fn prepareDraft(engine: *Engine, state: c.JSValue, tx: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    try put(engine, state, "tx", tx);
    const threshold = try scope.get(state, "threshold");
    const blocking = try scope.text("blocking");
    if (c.JS_IsStrictEqual(engine.context, threshold, blocking)) {
        const runtime = try scope.get(state, "runtime");
        const input = try scope.own(try vm.object(engine));
        try put(engine, input, "reason", try scope.text("threshold"));
        const exports = engine.native_module_values.get("@earendil-works/pi-durable") orelse return error.DurableModuleUnavailable;
        var intrinsics = try captured(&scope, state);
        const pending = try scope.own(try @import("native_durable_compaction_task.zig").createCompaction(engine, &intrinsics, tx, try scope.get(runtime, "conversationId"), input, try scope.get(runtime, "taskId"), try scope.get(exports, "CompactionTask"), try scope.get(state, "liveToken")));
        return wait(engine, state, pending, 11);
    }
    const query = try scope.own(try vm.object(engine));
    try put(engine, query, "conversationId", try scope.get(try scope.get(state, "runtime"), "conversationId"));
    const pending = try scope.invoke(tx, "scanEntries", &.{ query, c.JS_NewInt32(engine.context, 1) });
    return wait(engine, state, pending, 9);
}
fn appendPreparedEntry(engine: *Engine, state: c.JSValue) anyerror!c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const entries = try scope.get(state, "entries");
    var index: u32 = 0;
    if (c.JS_ToUint32(engine.context, &index, try scope.get(state, "entryIndex")) < 0) return js.capture(engine);
    if (index < try vm.length(engine, entries)) {
        try put(engine, state, "entryIndex", c.JS_NewUint32(engine.context, index + 1));
        const entry = try scope.own(try engine.checked(c.JS_GetPropertyUint32(engine.context, entries, index)));
        const exports = engine.native_module_values.get("@earendil-works/pi-durable") orelse return error.DurableModuleUnavailable;
        const pending = try scope.invoke(try scope.get(state, "tx"), "appendEntry", &.{ try scope.get(exports, "SystemEntry"), try scope.get(try scope.get(state, "runtime"), "conversationId"), entry });
        return wait(engine, state, pending, 10);
    }
    return preparedCheckpoint(engine, state);
}
fn preparedCheckpoint(engine: *Engine, state: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const runtime = try scope.get(state, "runtime");
    const cutoff = try scope.get(state, "cutoff");
    if (c.JS_IsUndefined(cutoff)) {
        const id = try engine.toString(try scope.get(runtime, "conversationId"));
        defer engine.gpa.free(id);
        const message = try std.fmt.allocPrint(engine.gpa, "Conversation {s} has no entries to send", .{id});
        defer engine.gpa.free(message);
        return @import("native_sdk.zig").sourceError(engine, message);
    }
    const threshold = try scope.get(state, "threshold");
    if (!c.JS_IsUndefined(threshold) and c.JS_IsUndefined(try scope.get(state, "backgroundChecked"))) {
        try put(engine, state, "backgroundChecked", c.pi_js_bool(engine.context, 1));
        const pending = try scope.invoke(try scope.get(state, "tx"), "doc", &.{ try scope.get(state, "liveToken"), try scope.get(runtime, "conversationId") });
        return wait(engine, state, pending, 12);
    }
    const old = try scope.get(state, "checkpoint");
    const request = try scope.own(try vm.object(engine));
    try put(engine, request, "phase", try scope.text("request"));
    try put(engine, request, "attempt", try scope.get(old, "attempt"));
    const compacted = try scope.get(old, "compacted");
    if (!c.JS_IsUndefined(compacted)) try put(engine, request, "compacted", compacted);
    try put(engine, request, "model", try scope.get(state, "modelRef"));
    try put(engine, request, "thinkingLevel", try scope.get(try scope.get(state, "agent"), "thinkingLevel"));
    try put(engine, request, "streamOptions", try scope.get(try scope.get(runtime, "settings"), "stream"));
    try put(engine, request, "cutoff", cutoff);
    const next = try vm.object(engine);
    errdefer engine.freeValue(next);
    try put(engine, next, "status", try scope.text("running"));
    try put(engine, next, "checkpoint", request);
    return next;
}
pub fn requestPhase(engine: *Engine, intrinsics: *awaiting.Intrinsics, runtime: c.JSValue, context: c.JSValue, live_token: c.JSValue, task: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const state = try scope.own(try createState(engine, intrinsics, runtime, context, live_token, task));
    try put(engine, state, "checkpoint", try scope.get(try scope.get(task, "state"), "checkpoint"));
    var data = [_]c.JSValue{state};
    const callback = try scope.own(try engine.checked(c.JS_NewCFunctionData2(engine.context, requestCommit, "", 1, 0, data.len, &data)));
    const pending = try scope.invoke(runtime, "commit", &.{ callback, context });
    return wait(engine, state, pending, 17);
}
fn requestCommit(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, data: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = Engine.fromContext(context.?);
    return requestDraft(engine, data[0], if (argc > 0) argv[0] else c.pi_js_undefined()) catch |err| @import("native_durable.zig").reject(engine, err);
}
fn requestDraft(engine: *Engine, state: c.JSValue, tx: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    try put(engine, state, "tx", tx);
    const runtime = try scope.get(state, "runtime");
    const pending = try scope.invoke(tx, "doc", &.{ try scope.get(state, "liveToken"), try scope.get(runtime, "conversationId") });
    return wait(engine, state, pending, 15);
}
fn requestStarted(engine: *Engine, state: c.JSValue, live: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const generation = try scope.own(try vm.object(engine));
    try put(engine, generation, "attempt", try scope.get(try scope.get(state, "checkpoint"), "attempt"));
    try put(engine, live, "generation", generation);
    return c.pi_js_undefined();
}
pub fn appendAssistant(engine: *Engine, intrinsics: *awaiting.Intrinsics, tx: c.JSValue, conversation: c.JSValue, message: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const state = try scope.own(try createState(engine, intrinsics, c.pi_js_undefined(), c.pi_js_undefined(), c.pi_js_undefined(), c.pi_js_undefined()));
    inline for (.{ .{ "tx", tx }, .{ "conversation", conversation }, .{ "message", message } }) |field| try put(engine, state, field[0], field[1]);
    const key = try scope.own(try @import("native_utf16.zig").concat(engine, &.{ try scope.get(message, "provider"), try scope.text("/"), try scope.get(message, "model") }));
    const exports = engine.native_module_values.get("@earendil-works/pi-durable") orelse return error.DurableModuleUnavailable;
    const pending = try scope.own(try @import("native_durable_usage.zig").record(engine, intrinsics, tx, conversation, "models", key, try scope.get(message, "usage"), try scope.get(exports, "UsageDoc")));
    return wait(engine, state, pending, 30);
}
fn beforeRequestCallback(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, data: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = Engine.fromContext(context.?);
    return beforeRequestHook(engine, data[0], if (argc > 0) argv[0] else c.pi_js_undefined()) catch |err| @import("native_durable.zig").reject(engine, err);
}
fn beforeRequestHook(engine: *Engine, state: c.JSValue, hook: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const input = try scope.own(try vm.object(engine));
    try put(engine, input, "messages", try scope.get(state, "messages"));
    var args = [_]c.JSValue{ input, try scope.get(state, "runtime"), try scope.get(state, "context") };
    const pending = try scope.own(try engine.checked(c.JS_Call(engine.context, hook, c.pi_js_undefined(), args.len, &args)));
    return wait(engine, state, pending, 19);
}
pub fn classify(engine: *Engine, intrinsics: *awaiting.Intrinsics, runtime: c.JSValue, context: c.JSValue, live_token: c.JSValue, request_value: c.JSValue, message: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    _ = try scope.invoke(try scope.get(runtime, "signal"), "throwIfAborted", &.{});
    const reason = try scope.get(message, "stopReason");
    const deferred_reason = try scope.text("deferred");
    if (c.JS_IsStrictEqual(engine.context, reason, deferred_reason) and !c.JS_IsUndefined(try scope.get(message, "deferred"))) return deferred(engine, intrinsics, runtime, context, live_token, request_value, message);
    const state = try scope.own(try createState(engine, intrinsics, runtime, context, live_token, c.pi_js_undefined()));
    try put(engine, state, "request", request_value);
    try put(engine, state, "message", message);
    var data = [_]c.JSValue{state};
    const callback = try scope.own(try engine.checked(c.JS_NewCFunctionData2(engine.context, afterResponseCallback, "", 1, 0, data.len, &data)));
    const pending = try scope.invoke(try scope.get(runtime, "hooks"), "each", &.{ try scope.text("afterResponse"), callback });
    return wait(engine, state, pending, 23);
}
fn afterResponseCallback(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, data: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = Engine.fromContext(context.?);
    return afterResponseHook(engine, data[0], if (argc > 0) argv[0] else c.pi_js_undefined()) catch |err| @import("native_durable.zig").reject(engine, err);
}
fn afterResponseHook(engine: *Engine, state: c.JSValue, hook: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    var args = [_]c.JSValue{ try scope.get(state, "message"), try scope.get(state, "runtime"), try scope.get(state, "context") };
    return engine.checked(c.JS_Call(engine.context, hook, c.pi_js_undefined(), args.len, &args));
}
fn classifyError(engine: *Engine, state: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const runtime = try scope.get(state, "runtime");
    const message = try scope.get(state, "message");
    const request_value = try scope.get(state, "request");
    const settings = try scope.get(runtime, "settings");
    const overflow = try @import("native_durable_generation_overflow.zig").errorOverflow(engine, message);
    try put(engine, state, "overflow", c.pi_js_bool(engine.context, @intFromBool(overflow)));
    if (overflow and c.JS_IsUndefined(try scope.get(request_value, "compacted")) and c.JS_ToBool(engine.context, try scope.get(try scope.get(settings, "compaction"), "enabled")) != 0 and c.JS_IsUndefined(try scope.get(state, "overflowChecked"))) {
        try put(engine, state, "overflowChecked", c.pi_js_bool(engine.context, 1));
        const options = try scope.own(try vm.object(engine));
        try put(engine, options, "at", try scope.get(request_value, "cutoff"));
        const pending = try scope.invoke(runtime, "context", &.{ try scope.get(runtime, "conversationId"), try scope.get(state, "context"), options });
        return wait(engine, state, pending, 26);
    }
    const policy = try scope.get(settings, "retry");
    var attempt: f64 = 0;
    var max_retries: f64 = 0;
    if (c.JS_ToFloat64(engine.context, &attempt, try scope.get(request_value, "attempt")) < 0 or c.JS_ToFloat64(engine.context, &max_retries, try scope.get(policy, "maxRetries")) < 0) return js.capture(engine);
    const should_retry = !overflow and try @import("native_durable_retry.zig").retryable(engine, message) and c.JS_ToBool(engine.context, try scope.get(policy, "enabled")) != 0 and attempt <= max_retries;
    try put(engine, state, "retry", c.pi_js_bool(engine.context, @intFromBool(should_retry)));
    var until: f64 = 0;
    if (should_retry) {
        var now: f64 = 0;
        var delay: f64 = 0;
        if (c.JS_ToFloat64(engine.context, &now, try scope.invoke(runtime, "now", &.{})) < 0 or c.JS_ToFloat64(engine.context, &delay, try scope.own(try @import("native_durable_retry.zig").delay(engine, policy, try scope.get(request_value, "attempt")))) < 0) return js.capture(engine);
        until = now + delay;
    }
    try put(engine, state, "until", c.JS_NewFloat64(engine.context, until));
    var data = [_]c.JSValue{state};
    const callback = try scope.own(try engine.checked(c.JS_NewCFunctionData2(engine.context, errorCommit, "", 1, 0, data.len, &data)));
    return vm.invoke(engine, runtime, "commit", &.{ callback, try scope.get(state, "context") });
}
fn errorCommit(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, data: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = Engine.fromContext(context.?);
    return errorDraft(engine, data[0], if (argc > 0) argv[0] else c.pi_js_undefined()) catch |err| @import("native_durable.zig").reject(engine, err);
}
fn errorDraft(engine: *Engine, state: c.JSValue, tx: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    try put(engine, state, "tx", tx);
    const runtime = try scope.get(state, "runtime");
    const pending = try scope.invoke(tx, "doc", &.{ try scope.get(state, "liveToken"), try scope.get(runtime, "conversationId") });
    return wait(engine, state, pending, 24);
}
fn classifiedErrorOutcome(engine: *Engine, state: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const runtime = try scope.get(state, "runtime");
    const live = try scope.get(state, "live");
    const message = try scope.get(state, "message");
    const request_value = try scope.get(state, "request");
    const error_message = try scope.get(message, "errorMessage");
    if (c.JS_ToBool(engine.context, try scope.get(state, "overflowCompaction")) != 0) {
        const key = c.JS_NewAtom(engine.context, "generation");
        defer c.JS_FreeAtom(engine.context, key);
        if (c.JS_DeleteProperty(engine.context, live, key, c.JS_PROP_THROW) < 0) return js.capture(engine);
        const input = try scope.own(try vm.object(engine));
        try put(engine, input, "reason", try scope.text("overflow"));
        const exports = engine.native_module_values.get("@earendil-works/pi-durable") orelse return error.DurableModuleUnavailable;
        var intrinsics = try captured(&scope, state);
        const pending = try scope.own(try @import("native_durable_compaction_task.zig").createCompaction(engine, &intrinsics, try scope.get(state, "tx"), try scope.get(runtime, "conversationId"), input, try scope.get(runtime, "taskId"), try scope.get(exports, "CompactionTask"), try scope.get(state, "liveToken")));
        return wait(engine, state, pending, 27);
    }
    if (c.JS_ToBool(engine.context, try scope.get(state, "retry")) != 0) {
        const generation = try scope.own(try vm.object(engine));
        try put(engine, generation, "attempt", try scope.get(request_value, "attempt"));
        const retry_info = try scope.own(try vm.object(engine));
        try put(engine, retry_info, "at", try scope.get(state, "until"));
        try put(engine, retry_info, "error", if (c.JS_IsUndefined(error_message) or c.JS_IsNull(error_message)) try scope.text("") else error_message);
        try put(engine, generation, "retry", retry_info);
        try put(engine, live, "generation", generation);
        const checkpoint = try scope.own(try vm.object(engine));
        try put(engine, checkpoint, "phase", try scope.text("retry"));
        try put(engine, checkpoint, "attempt", try scope.get(request_value, "attempt"));
        const compacted = try scope.get(request_value, "compacted");
        if (!c.JS_IsUndefined(compacted)) try put(engine, checkpoint, "compacted", compacted);
        try put(engine, checkpoint, "until", try scope.get(state, "until"));
        const next = try vm.object(engine);
        errdefer engine.freeValue(next);
        try put(engine, next, "status", try scope.text("running"));
        try put(engine, next, "checkpoint", checkpoint);
        return next;
    }
    const text = if (c.JS_IsUndefined(error_message) or c.JS_IsNull(error_message)) try scope.own(try @import("native_utf16.zig").concat(engine, &.{ try scope.text("Model response ended with stop reason "), try scope.get(message, "stopReason") })) else error_message;
    const settlement = try scope.own(try vm.object(engine));
    try put(engine, settlement, "status", try scope.text("unanswered"));
    try put(engine, settlement, "reason", try scope.text("model_error"));
    try put(engine, settlement, "detail", text);
    try @import("native_durable_generation_live.zig").endRun(engine, try scope.get(state, "tx"), live, try scope.get(runtime, "taskId"), settlement);
    const detail = try scope.own(try vm.object(engine));
    try put(engine, detail, "reason", try scope.text("model_error"));
    const failure = try scope.own(try vm.object(engine));
    try put(engine, failure, "message", text);
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
pub fn poll(engine: *Engine, intrinsics: *awaiting.Intrinsics, runtime: c.JSValue, context: c.JSValue, live_token: c.JSValue, task: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const state = try scope.own(try createState(engine, intrinsics, runtime, context, live_token, task));
    const checkpoint = try scope.get(try scope.get(task, "state"), "checkpoint");
    try put(engine, state, "checkpoint", checkpoint);
    const ref = try scope.get(checkpoint, "model");
    const model = try scope.invoke(try scope.get(runtime, "models"), "getModel", &.{ try scope.get(ref, "provider"), try scope.get(ref, "modelId") });
    if (c.JS_IsUndefined(model)) return failNoModel(engine, intrinsics, runtime, context, live_token, ref);
    try put(engine, state, "model", model);
    const pending = try scope.invoke(runtime, "sleep", &.{ try scope.get(checkpoint, "pollAt"), context });
    return wait(engine, state, pending, 28);
}
