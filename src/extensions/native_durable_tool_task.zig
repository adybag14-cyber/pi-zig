//! Built-in ToolTask phase preparation and abort. Every suspended handler owns
//! its state in the VM; execution consumes checked calls after intent commits.
const std = @import("std");
const engine_mod = @import("engine.zig");
const vm = @import("native_values.zig");
const putData = @import("native_tool_info.zig").putData;
const awaiting = @import("native_durable_await.zig");
const settle = @import("native_durable_tool_settle.zig");
const calls = @import("native_durable_tool_call.zig");
const c = engine_mod.c;
const Engine = engine_mod.Engine;
pub const Tokens = struct { assistant: c.JSValue, terminal: settle.Tokens };
const Stage = enum(c_int) { abort_call, recovery_call, recovery_agent, recovery_cleared, normal_call, normal_agent, before_decision, prepared };
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
    fn get(self: *Scope, receiver: c.JSValue, key: [:0]const u8) !c.JSValue {
        return self.own(try vm.get(self.engine, receiver, key));
    }
};
fn put(engine: *Engine, object: c.JSValue, key: [:0]const u8, value: c.JSValue) !void {
    try putData(engine, object, key, c.JS_DupValue(engine.context, value));
}
fn start(engine: *Engine, intrinsics: *awaiting.Intrinsics, tokens: Tokens, task: c.JSValue, runtime: c.JSValue, context: c.JSValue, stage: Stage) !c.JSValue {
    const state = try vm.object(engine);
    defer engine.freeValue(state);
    inline for (.{ .{ "task", task }, .{ "runtime", runtime }, .{ "context", context }, .{ "assistant", tokens.assistant }, .{ "live", tokens.terminal.live }, .{ "nestedCalls", tokens.terminal.nested_calls }, .{ "nestedResults", tokens.terminal.nested_results }, .{ "toolResult", tokens.terminal.tool_result }, .{ "usage", tokens.terminal.usage }, .{ "iteratorSymbol", tokens.terminal.iterator_symbol }, .{ "promiseConstructor", intrinsics.constructor }, .{ "promiseResolve", intrinsics.resolve }, .{ "promiseThen", intrinsics.then_function } }) |field| try put(engine, state, field[0], field[1]);
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    if (stage == .recovery_call) {
        const task_state = try scope.get(task, "state");
        const checkpoint = try scope.get(task_state, "checkpoint");
        try put(engine, state, "arguments", try scope.get(checkpoint, "arguments"));
        try put(engine, state, "replay", try scope.get(checkpoint, "replay"));
    }
    const input = try scope.get(task, "input");
    const pending = try scope.own(try calls.readCall(engine, runtime, input, context, tokens.assistant, intrinsics));
    return awaiting.continueWith(advance, engine, intrinsics, state, pending, @intFromEnum(stage));
}
pub fn abort(engine: *Engine, intrinsics: *awaiting.Intrinsics, tokens: Tokens, task: c.JSValue, runtime: c.JSValue, context: c.JSValue) !c.JSValue {
    return start(engine, intrinsics, tokens, task, runtime, context, .abort_call);
}
pub fn prepareRecovery(engine: *Engine, intrinsics: *awaiting.Intrinsics, tokens: Tokens, task: c.JSValue, runtime: c.JSValue, context: c.JSValue) !c.JSValue {
    return start(engine, intrinsics, tokens, task, runtime, context, .recovery_call);
}
/// Resolves undefined after an early terminal commit, or the checked call/tool/
/// arguments that the driver must record as intent before executing the tool.
pub fn prepareCall(engine: *Engine, intrinsics: *awaiting.Intrinsics, tokens: Tokens, task: c.JSValue, runtime: c.JSValue, context: c.JSValue) !c.JSValue {
    return start(engine, intrinsics, tokens, task, runtime, context, .normal_call);
}
fn advance(engine: *Engine, state: c.JSValue, value: c.JSValue, rejected: bool, raw_stage: c_int) !c.JSValue {
    const stage: Stage = @enumFromInt(raw_stage);
    if (stage == .before_decision) return beforeDecision(engine, state, value, rejected);
    if (rejected) return engine.checked(c.JS_Throw(engine.context, c.JS_DupValue(engine.context, value)));
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    var intrinsics: awaiting.Intrinsics = .{ .constructor = try scope.get(state, "promiseConstructor"), .resolve = try scope.get(state, "promiseResolve"), .then_function = try scope.get(state, "promiseThen") };
    const task = try scope.get(state, "task");
    const runtime = try scope.get(state, "runtime");
    const context = try scope.get(state, "context");
    const input = try scope.get(task, "input");
    if (stage == .recovery_cleared) return vm.get(engine, state, "prepared");
    if (stage == .recovery_call or stage == .normal_call) {
        try put(engine, state, "call", value);
        const pending = try scope.own(try vm.invoke(engine, runtime, "agent", &.{context}));
        return awaiting.continueWith(advance, engine, &intrinsics, state, pending, @intFromEnum(if (stage == .recovery_call) Stage.recovery_agent else Stage.normal_agent));
    }
    const call = if (stage == .abort_call) value else try scope.get(state, "call");
    if (stage == .normal_agent) {
        const name = try scope.get(call, "name");
        const nested = try calls.equalsString(engine, try scope.get(input, "kind"), "nested");
        const tool = try scope.own(try calls.resolveTool(engine, value, nested, name));
        if (c.JS_IsUndefined(tool)) {
            const text = try engine.toString(try scope.get(call, "name"));
            defer engine.gpa.free(text);
            const message = try std.fmt.allocPrint(engine.gpa, "Tool {s} is not available", .{text});
            defer engine.gpa.free(message);
            const message_value = try scope.own(try engine.checked(c.JS_NewStringLen(engine.context, message.ptr, message.len)));
            return earlyResult(engine, state, "tool_unavailable", message_value);
        }
        try put(engine, state, "tool", tool);
        const args = try scope.get(call, "arguments");
        const prepared = try calls.prepare(engine, tool, args, @import("native_durable_errors.zig").errorMessage);
        defer prepared.deinit(engine);
        if (prepared == .failure) return earlyResult(engine, state, "invalid_arguments", prepared.failure);
        const checked = try calls.validate(engine, tool, call, prepared.arguments, @import("native_durable_errors.zig").errorMessage);
        defer checked.deinit(engine);
        if (checked == .failure) return earlyResult(engine, state, "invalid_arguments", checked.failure);
        try put(engine, state, "arguments", checked.arguments);
        const hooks = try scope.get(runtime, "hooks");
        const event = try scope.own(try engine.checked(c.JS_NewString(engine.context, "beforeTool")));
        var captures = [_]c.JSValue{state};
        const callback = try scope.own(try engine.checked(c.JS_NewCFunctionData2(engine.context, beforeHook, "", 1, 0, captures.len, &captures)));
        const pending = try scope.own(try vm.invoke(engine, hooks, "each", &.{ event, callback }));
        return awaiting.continueWith(advance, engine, &intrinsics, state, pending, @intFromEnum(Stage.prepared));
    }
    if (stage == .prepared) {
        const block = try scope.get(state, "block");
        if (!c.JS_IsUndefined(block)) {
            const text = try engine.toString(block);
            defer engine.gpa.free(text);
            const message = try std.fmt.allocPrint(engine.gpa, "Tool call blocked: {s}", .{text});
            defer engine.gpa.free(message);
            const message_value = try scope.own(try engine.checked(c.JS_NewStringLen(engine.context, message.ptr, message.len)));
            return earlyResult(engine, state, "blocked", message_value);
        }
        const tool = try scope.get(state, "tool");
        const args = try scope.get(state, "arguments");
        const checked = try calls.validate(engine, tool, call, args, @import("native_durable_errors.zig").errorMessage);
        defer checked.deinit(engine);
        if (checked == .failure) return earlyResult(engine, state, "invalid_arguments", checked.failure);
        const options = try scope.own(try vm.object(engine));
        try put(engine, options, "omitUndefinedProperties", c.pi_js_bool(engine.context, 1));
        const final = try scope.own(try @import("native_chord_json.zig").copyJson(engine, checked.arguments, options));
        try put(engine, state, "arguments", final);
        return preparedResult(engine, state);
    }
    var code: [:0]const u8 = "interrupted";
    var suffix: []const u8 = " was interrupted and may have partially run";
    const ending: settle.Ending = if (stage == .abort_call) .aborted else .failed;
    if (stage == .abort_call) {
        const reason = try scope.get(task, "abortReason");
        if (!try calls.equalsString(engine, reason, "restart")) {
            code = "aborted";
            suffix = " was aborted";
        } else {
            const task_state = try scope.get(task, "state");
            const checkpoint = try scope.get(task_state, "checkpoint");
            if (try calls.equalsString(engine, try scope.get(checkpoint, "phase"), "execute")) {
                suffix = " was interrupted by a restart and may have partially run";
            } else {
                code = "abandoned";
                suffix = " was not started: its caller ended with a restart";
            }
        }
    } else {
        const name = try scope.get(call, "name");
        const nested = try calls.equalsString(engine, try scope.get(input, "kind"), "nested");
        const tool = try scope.own(try calls.resolveTool(engine, value, nested, name));
        const replay = try scope.get(state, "replay");
        if (try calls.equalsString(engine, replay, "safe") and !c.JS_IsUndefined(tool) and try calls.equalsString(engine, try scope.get(tool, "replay"), "safe")) {
            try put(engine, state, "tool", tool);
            const prepared = try scope.own(try preparedResult(engine, state));
            try put(engine, state, "prepared", prepared);
            const live = try scope.get(state, "live");
            const pending = try scope.own(try @import("native_durable_tool_intent.zig").commit(engine, &intrinsics, live, task, runtime, prepared, context, true));
            return awaiting.continueWith(advance, engine, &intrinsics, state, pending, @intFromEnum(Stage.recovery_cleared));
        }
    }
    const name_value = try scope.get(call, "name");
    const name = try engine.toString(name_value);
    defer engine.gpa.free(name);
    const message_text = try std.fmt.allocPrint(engine.gpa, "Tool {s}{s}", .{ name, suffix });
    defer engine.gpa.free(message_text);
    const message = try scope.own(try engine.checked(c.JS_NewStringLen(engine.context, message_text.ptr, message_text.len)));
    const code_value = try scope.own(try engine.checked(c.JS_NewString(engine.context, code)));
    return settle.run(engine, &intrinsics, .{ .live = try scope.get(state, "live"), .nested_calls = try scope.get(state, "nestedCalls"), .nested_results = try scope.get(state, "nestedResults"), .tool_result = try scope.get(state, "toolResult"), .usage = try scope.get(state, "usage"), .iterator_symbol = try scope.get(state, "iteratorSymbol") }, runtime, input, call, ending, .{ .slot_error = .{ .code = code_value, .message = message } }, context, c.pi_js_undefined(), if (ending == .failed) message else c.pi_js_undefined());
}

fn preparedResult(engine: *Engine, state: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const result = try vm.object(engine);
    errdefer engine.freeValue(result);
    inline for (.{ "call", "tool", "arguments" }) |name| try put(engine, result, name, try scope.get(state, name));
    return result;
}

fn beforeHook(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, data: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = Engine.fromContext(context.?);
    return invokeBefore(engine, data[0], if (argc > 0) argv[0] else c.pi_js_undefined()) catch |err| @import("native_durable.zig").rejectedPromise(engine, err);
}
fn invokeBefore(engine: *Engine, state: c.JSValue, hook: c.JSValue) !c.JSValue {
    return invokeBeforeOwned(engine, state, hook) catch |err| {
        if (err != error.JavaScriptException) return err;
        const failure = engine.captured_exception orelse return err;
        const handled = try beforeDecision(engine, state, failure, true);
        defer engine.freeValue(handled);
        return @import("native_sdk.zig").promise(engine, handled);
    };
}
fn invokeBeforeOwned(engine: *Engine, state: c.JSValue, hook: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const block = try scope.get(state, "block");
    if (!c.JS_IsUndefined(block)) return @import("native_sdk.zig").promise(engine, c.pi_js_undefined());
    var intrinsics: awaiting.Intrinsics = .{ .constructor = try scope.get(state, "promiseConstructor"), .resolve = try scope.get(state, "promiseResolve"), .then_function = try scope.get(state, "promiseThen") };
    const call = try scope.get(state, "call");
    const projected = try scope.own(try @import("native_js_values.zig").spread(engine, call));
    try put(engine, projected, "arguments", try scope.get(state, "arguments"));
    var args = [_]c.JSValue{ projected, try scope.get(state, "runtime"), try scope.get(state, "context") };
    const pending = try scope.own(try engine.checked(c.JS_Call(engine.context, hook, c.pi_js_undefined(), args.len, &args)));
    return awaiting.continueWith(advance, engine, &intrinsics, state, pending, @intFromEnum(Stage.before_decision));
}
fn beforeDecision(engine: *Engine, state: c.JSValue, decision: c.JSValue, rejected: bool) !c.JSValue {
    return beforeDecisionOwned(engine, state, decision, rejected) catch |err| {
        if (rejected or err != error.JavaScriptException) return err;
        return beforeDecisionOwned(engine, state, engine.captured_exception orelse return err, true);
    };
}
fn beforeDecisionOwned(engine: *Engine, state: c.JSValue, decision: c.JSValue, rejected: bool) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    if (rejected) {
        const original = try scope.own(c.JS_DupValue(engine.context, decision));
        const runtime = try scope.get(state, "runtime");
        const signal = try scope.get(runtime, "signal");
        if (c.JS_ToBool(engine.context, try scope.get(signal, "aborted")) != 0) return engine.checked(c.JS_Throw(engine.context, c.JS_DupValue(engine.context, original)));
        const message = try scope.own(try @import("native_durable_errors.zig").errorMessage(engine, original));
        try put(engine, state, "block", message);
        return c.pi_js_undefined();
    }
    if (c.JS_IsUndefined(decision) or c.JS_IsNull(decision)) return c.pi_js_undefined();
    const block = try scope.get(decision, "block");
    if (!c.JS_IsUndefined(block)) {
        try put(engine, state, "block", try scope.get(decision, "block"));
    } else if (!c.JS_IsUndefined(try scope.get(decision, "arguments"))) {
        try put(engine, state, "arguments", try scope.get(decision, "arguments"));
    }
    return c.pi_js_undefined();
}
fn earlyResult(engine: *Engine, state: c.JSValue, code: [:0]const u8, message: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const result = try scope.own(try vm.object(engine));
    try @import("native_tool_info.zig").putData(engine, result, "output", try vm.array(engine));
    try put(engine, result, "isError", c.pi_js_bool(engine.context, 1));
    const diagnostic = try scope.own(try vm.object(engine));
    try @import("native_tool_info.zig").putData(engine, diagnostic, "severity", try engine.checked(c.JS_NewString(engine.context, "error")));
    try @import("native_tool_info.zig").putData(engine, diagnostic, "code", try engine.checked(c.JS_NewString(engine.context, code)));
    try put(engine, diagnostic, "message", message);
    const diagnostics = try scope.own(try vm.array(engine));
    if (c.JS_SetPropertyUint32(engine.context, diagnostics, 0, c.JS_DupValue(engine.context, diagnostic)) < 0) return error.JavaScriptException;
    try put(engine, result, "diagnostics", diagnostics);
    var intrinsics: awaiting.Intrinsics = .{ .constructor = try scope.get(state, "promiseConstructor"), .resolve = try scope.get(state, "promiseResolve"), .then_function = try scope.get(state, "promiseThen") };
    const task = try scope.get(state, "task");
    return settle.run(engine, &intrinsics, .{ .live = try scope.get(state, "live"), .nested_calls = try scope.get(state, "nestedCalls"), .nested_results = try scope.get(state, "nestedResults"), .tool_result = try scope.get(state, "toolResult"), .usage = try scope.get(state, "usage"), .iterator_symbol = try scope.get(state, "iteratorSymbol") }, try scope.get(state, "runtime"), try scope.get(task, "input"), try scope.get(state, "call"), .completed, .{ .final = result }, try scope.get(state, "context"), c.pi_js_undefined(), c.pi_js_undefined());
}
