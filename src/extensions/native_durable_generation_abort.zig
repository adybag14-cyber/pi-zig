//! Native generation abort cleanup for committed partials and unstarted calls.
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
pub fn run(engine: *Engine, intrinsics: *awaiting.Intrinsics, runtime: c.JSValue, context: c.JSValue, task: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const state = try scope.own(try vm.object(engine));
    inline for (.{ .{ "promiseConstructor", intrinsics.constructor }, .{ "promiseResolve", intrinsics.resolve }, .{ "promiseThen", intrinsics.then_function }, .{ "runtime", runtime }, .{ "context", context }, .{ "task", task } }) |field| try put(engine, state, field[0], field[1]);
    const checkpoint = try scope.get(try scope.get(task, "state"), "checkpoint");
    try put(engine, state, "checkpoint", checkpoint);
    const phase = try scope.get(checkpoint, "phase");
    const polling = try scope.text("poll");
    if (c.JS_IsStrictEqual(engine.context, phase, polling)) {
        const ref = try scope.get(checkpoint, "model");
        const model = try scope.invoke(try scope.get(runtime, "models"), "getModel", &.{ try scope.get(ref, "provider"), try scope.get(ref, "modelId") });
        if (!c.JS_IsUndefined(model)) {
            const options = try scope.own(try vm.object(engine));
            try put(engine, options, "signal", try scope.get(runtime, "signal"));
            const pending = scope.invoke(try scope.get(runtime, "models"), "cancelDeferred", &.{ model, try scope.get(checkpoint, "handle"), options }) catch |err| {
                if (err != error.JavaScriptException) return err;
                return canceled(engine, state, engine.captured_exception orelse return err, true);
            };
            return wait(engine, state, pending, 1);
        }
    }
    return readUnstarted(engine, state);
}
fn canceled(engine: *Engine, state: c.JSValue, value: c.JSValue, rejected: bool) anyerror!c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    if (rejected) _ = try scope.invoke(try scope.get(state, "runtime"), "report", &.{value});
    return readUnstarted(engine, state);
}
fn readUnstarted(engine: *Engine, state: c.JSValue) anyerror!c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const checkpoint = try scope.get(state, "checkpoint");
    const tools = try scope.text("tools");
    if (c.JS_IsStrictEqual(engine.context, try scope.get(checkpoint, "phase"), tools)) {
        const exports = engine.native_module_values.get("@earendil-works/pi-durable") orelse return error.DurableModuleUnavailable;
        const pending = try scope.invoke(try scope.get(state, "runtime"), "entry", &.{ try scope.get(exports, "AssistantEntry"), try scope.get(checkpoint, "assistant"), try scope.get(state, "context") });
        return wait(engine, state, pending, 2);
    }
    try @import("native_tool_info.zig").putData(engine, state, "unstarted", try vm.array(engine));
    return commitAbort(engine, state);
}
fn commitAbort(engine: *Engine, state: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    var data = [_]c.JSValue{state};
    const callback = try scope.own(try engine.checked(c.JS_NewCFunctionData2(engine.context, abortCommit, "", 1, 0, data.len, &data)));
    return vm.invoke(engine, try scope.get(state, "runtime"), "commit", &.{ callback, try scope.get(state, "context") });
}
fn abortCommit(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, data: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = Engine.fromContext(context.?);
    return abortDraft(engine, data[0], if (argc > 0) argv[0] else c.pi_js_undefined()) catch |err| @import("native_durable.zig").reject(engine, err);
}
fn abortDraft(engine: *Engine, state: c.JSValue, tx: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    try put(engine, state, "tx", tx);
    const exports = engine.native_module_values.get("@earendil-works/pi-durable") orelse return error.DurableModuleUnavailable;
    const pending = try scope.invoke(tx, "doc", &.{ try scope.get(exports, "LiveDoc"), try scope.get(try scope.get(state, "runtime"), "conversationId") });
    return wait(engine, state, pending, 3);
}
fn advance(engine: *Engine, state: c.JSValue, value: c.JSValue, rejected: bool, stage: c_int) anyerror!c.JSValue {
    if (stage == 1) return canceled(engine, state, value, rejected);
    if (rejected) return engine.checked(c.JS_Throw(engine.context, c.JS_DupValue(engine.context, value)));
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    if (stage == 2) {
        const unstarted = try scope.own(try vm.array(engine));
        var message = c.pi_js_undefined();
        if (!c.JS_IsUndefined(value) and !c.JS_IsNull(value)) {
            const model = try scope.get(value, "model");
            if (!c.JS_IsUndefined(model) and !c.JS_IsNull(model)) message = try scope.own(try engine.checked(c.JS_GetPropertyUint32(engine.context, model, 0)));
        }
        if (!c.JS_IsUndefined(message) and c.JS_IsStrictEqual(engine.context, try scope.get(message, "role"), try scope.text("assistant"))) {
            const content = try scope.get(message, "content");
            const pending = try scope.get(try scope.get(state, "checkpoint"), "pending");
            for (0..try vm.length(engine, pending)) |index| {
                const id = try scope.own(try engine.checked(c.JS_GetPropertyUint32(engine.context, pending, @intCast(index))));
                for (0..try vm.length(engine, content)) |position| {
                    const call = try scope.own(try engine.checked(c.JS_GetPropertyUint32(engine.context, content, @intCast(position))));
                    if (c.JS_IsStrictEqual(engine.context, try scope.get(call, "type"), try scope.text("toolCall")) and c.JS_IsStrictEqual(engine.context, try scope.get(call, "id"), id)) {
                        try js.push(engine, unstarted, call);
                        break;
                    }
                }
            }
        }
        try put(engine, state, "unstarted", unstarted);
        return commitAbort(engine, state);
    }
    if (stage == 3) {
        try put(engine, state, "live", value);
        const generation = try scope.get(value, "generation");
        if (!c.JS_IsUndefined(generation) and !c.JS_IsNull(generation)) {
            const partial = try scope.get(generation, "message");
            if (!c.JS_IsUndefined(partial)) {
                const options = try scope.own(try vm.object(engine));
                const message = try scope.own(try @import("native_chord_json.zig").copyJson(engine, partial, options));
                try put(engine, message, "stopReason", try scope.text("aborted"));
                var intrinsics = try captured(&scope, state);
                const pending = try scope.own(try @import("native_durable_generation_task.zig").appendAssistant(engine, &intrinsics, try scope.get(state, "tx"), try scope.get(try scope.get(state, "runtime"), "conversationId"), message));
                return wait(engine, state, pending, 4);
            }
        }
        return beginUnstarted(engine, state);
    }
    if (stage == 4) return beginUnstarted(engine, state);
    if (stage == 5) return appendUnstarted(engine, state);
    return error.InvalidGenerationAbortContinuation;
}
fn beginUnstarted(engine: *Engine, state: c.JSValue) !c.JSValue {
    try put(engine, state, "index", c.JS_NewInt32(engine.context, 0));
    return appendUnstarted(engine, state);
}
fn appendUnstarted(engine: *Engine, state: c.JSValue) anyerror!c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const calls = try scope.get(state, "unstarted");
    var index: u32 = 0;
    if (c.JS_ToUint32(engine.context, &index, try scope.get(state, "index")) < 0) return js.capture(engine);
    const runtime = try scope.get(state, "runtime");
    if (index < try vm.length(engine, calls)) {
        try put(engine, state, "index", c.JS_NewUint32(engine.context, index + 1));
        const call = try scope.own(try engine.checked(c.JS_GetPropertyUint32(engine.context, calls, index)));
        const message = try scope.own(try @import("native_utf16.zig").concat(engine, &.{ try scope.text("Tool "), try scope.get(call, "name"), try scope.text(" was aborted") }));
        const result = try scope.own(try @import("native_durable_tool_result.zig").harnessError(engine, try scope.text("aborted"), message));
        var intrinsics = try captured(&scope, state);
        const pending = try scope.own(try @import("native_durable_tool_result.zig").append(engine, &intrinsics, try scope.get(state, "tx"), try scope.get(runtime, "conversationId"), call, result, try scope.invoke(runtime, "now", &.{}), c.pi_js_undefined()));
        return wait(engine, state, pending, 5);
    }
    const settlement = try scope.own(try vm.object(engine));
    try put(engine, settlement, "status", try scope.text("unanswered"));
    try put(engine, settlement, "reason", try scope.text("aborted"));
    try @import("native_durable_generation_live.zig").endRun(engine, try scope.get(state, "tx"), try scope.get(state, "live"), try scope.get(runtime, "taskId"), settlement);
    const outcome = try scope.own(try vm.object(engine));
    try put(engine, outcome, "status", try scope.text("aborted"));
    const next = try vm.object(engine);
    errdefer engine.freeValue(next);
    try put(engine, next, "status", try scope.text("terminal"));
    try put(engine, next, "outcome", outcome);
    return next;
}
