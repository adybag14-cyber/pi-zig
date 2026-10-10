//! Program-facing executeTool: track admission, await the owned task, then read
//! its task-family result. The returned copy belongs to the calling tool.
const std = @import("std");
const engine_mod = @import("engine.zig");
const vm = @import("native_values.zig");
const js = @import("native_js_values.zig");
const awaiting = @import("native_durable_await.zig");
const c = engine_mod.c;
const Engine = engine_mod.Engine;
const Stage = enum(c_int) { admitted, settled, stored };
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
    fn get(self: *Scope, value: c.JSValue, key: [:0]const u8) !c.JSValue {
        return self.own(try vm.get(self.engine, value, key));
    }
    fn invoke(self: *Scope, value: c.JSValue, key: [:0]const u8, args: []const c.JSValue) !c.JSValue {
        return self.own(try vm.invoke(self.engine, value, key, args));
    }
};
fn put(engine: *Engine, state: c.JSValue, key: [:0]const u8, value: c.JSValue) !void {
    try @import("native_tool_info.zig").putData(engine, state, key, c.JS_DupValue(engine.context, value));
}
fn intrinsics(scope: *Scope, attempt: c.JSValue) !awaiting.Intrinsics {
    return .{ .constructor = try scope.get(attempt, "promiseConstructor"), .resolve = try scope.get(attempt, "promiseResolve"), .then_function = try scope.get(attempt, "promiseThen") };
}
fn wait(engine: *Engine, state: c.JSValue, value: c.JSValue, stage: Stage) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const attempt = try scope.get(state, "attempt");
    var captured = try intrinsics(&scope, attempt);
    return awaiting.continueWith(advance, engine, &captured, state, value, @intFromEnum(stage));
}
pub fn function(engine: *Engine, attempt: c.JSValue) !c.JSValue {
    var captures = [_]c.JSValue{attempt};
    return engine.checked(c.JS_NewCFunctionData2(engine.context, dispatch, "executeTool", 3, 0, captures.len, &captures));
}
fn dispatch(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, data: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = Engine.fromContext(context.?);
    return execute(engine, data[0], argv[0..@intCast(argc)]) catch |err| @import("native_durable.zig").rejectedPromise(engine, err);
}
fn execute(engine: *Engine, attempt: c.JSValue, args: []const c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const call = try scope.get(attempt, "call");
    if (c.JS_ToBool(engine.context, try scope.get(attempt, "ended")) != 0) {
        const id = try engine.toString(try scope.get(call, "id"));
        defer engine.gpa.free(id);
        const message = try std.fmt.allocPrint(engine.gpa, "Tool call {s} has settled", .{id});
        defer engine.gpa.free(message);
        return @import("native_sdk.zig").sourceError(engine, message);
    }
    const options = if (args.len > 3 and !c.JS_IsUndefined(args[3])) args[3] else try scope.own(try vm.object(engine));
    const raw_key = try scope.get(options, "key");
    const key = if (c.JS_IsUndefined(raw_key) or c.JS_IsNull(raw_key)) key: {
        const previous = try scope.get(attempt, "sequence");
        var number: f64 = 0;
        if (c.JS_ToFloat64(engine.context, &number, previous) < 0) return js.capture(engine);
        const next = c.JS_NewFloat64(engine.context, number + 1);
        try put(engine, attempt, "sequence", next);
        const string = try scope.own(try js.global(engine, "String"));
        break :key try scope.own(try js.call(engine, string, c.pi_js_undefined(), &.{next}));
    } else raw_key;
    if (!c.JS_IsUndefined(try scope.get(options, "key"))) try @import("native_durable_tool_call.zig").checkKey(engine, try scope.get(options, "key"));
    const name = if (args.len > 0) args[0] else c.pi_js_undefined();
    const arguments = if (args.len > 1) args[1] else c.pi_js_undefined();
    const context = if (args.len > 2) args[2] else c.pi_js_undefined();
    const runtime = try scope.get(attempt, "runtime");
    var captured = try intrinsics(&scope, attempt);
    const parent_id = try scope.get(call, "id");
    const progress = try scope.get(options, "progress");
    const resumes = c.JS_ToBool(engine.context, try scope.get(attempt, "resumes")) != 0;
    const state = try scope.own(try vm.object(engine));
    try put(engine, state, "attempt", attempt);
    try put(engine, state, "name", name);
    try put(engine, state, "context", context);
    try put(engine, state, "arguments", arguments);
    try put(engine, state, "key", key);
    try put(engine, state, "parentCallId", parent_id);
    try put(engine, state, "progress", progress);
    try put(engine, state, "abandonOnRestart", c.pi_js_bool(engine.context, @intFromBool(!resumes)));
    var memo = try scope.get(attempt, "madeNestedMemo");
    if (c.JS_IsUndefined(memo)) {
        const label = try scope.own(try engine.checked(c.JS_NewString(engine.context, "pi.tool.madeNestedCalls")));
        const pending = try scope.invoke(runtime, "memo", &.{ label, c.pi_js_bool(engine.context, 1), context });
        memo = try scope.own(try awaiting.continueWith(memoSettled, engine, &captured, attempt, pending, 0));
        try put(engine, attempt, "madeNestedMemo", memo);
    }
    const admission = try scope.own(try awaiting.continueWith(admitAfterMemo, engine, &captured, state, memo, 0));
    const admissions = try scope.get(attempt, "admissions");
    // Track admission before the memo or nested-call commit can finish, so
    // cleanup observes every call started by this attempt.
    _ = try scope.invoke(admissions, "push", &.{admission});
    return wait(engine, state, admission, .admitted);
}
fn memoSettled(engine: *Engine, attempt: c.JSValue, value: c.JSValue, rejected: bool, _: c_int) !c.JSValue {
    if (rejected) {
        try put(engine, attempt, "madeNestedMemo", c.pi_js_undefined());
        return c.JS_Throw(engine.context, c.JS_DupValue(engine.context, value));
    }
    return c.JS_DupValue(engine.context, value);
}
fn admitAfterMemo(engine: *Engine, state: c.JSValue, value: c.JSValue, rejected: bool, _: c_int) !c.JSValue {
    if (rejected) return c.JS_Throw(engine.context, c.JS_DupValue(engine.context, value));
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const attempt = try scope.get(state, "attempt");
    var captured = try intrinsics(&scope, attempt);
    const tokens: @import("native_durable_nested_call.zig").Tokens = .{ .task = try scope.get(attempt, "toolTaskToken"), .index = try scope.get(attempt, "nestedCallsToken"), .live = try scope.get(attempt, "liveToken") };
    return @import("native_durable_nested_call.zig").admit(engine, &captured, tokens, try scope.get(attempt, "runtime"), try scope.get(state, "parentCallId"), try scope.get(state, "name"), try scope.get(state, "arguments"), try scope.get(state, "key"), try scope.get(state, "progress"), c.JS_ToBool(engine.context, try scope.get(state, "abandonOnRestart")) != 0, try scope.get(state, "context"));
}
fn advance(engine: *Engine, state: c.JSValue, value: c.JSValue, rejected: bool, raw_stage: c_int) !c.JSValue {
    if (rejected) return c.JS_Throw(engine.context, c.JS_DupValue(engine.context, value));
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const attempt = try scope.get(state, "attempt");
    const runtime = try scope.get(attempt, "runtime");
    const context = try scope.get(state, "context");
    switch (@as(Stage, @enumFromInt(raw_stage))) {
        .admitted => {
            try put(engine, state, "id", value);
            const pending = try scope.invoke(runtime, "waitForTask", &.{ value, context });
            return wait(engine, state, pending, .settled);
        },
        .settled => {
            try put(engine, state, "settled", value);
            const key = try scope.get(state, "key");
            const token = try scope.get(attempt, "nestedCallsToken");
            const owner_id = try scope.get(runtime, "taskId");
            const pending = try scope.invoke(runtime, "snapshot", &.{ token, owner_id, key, context });
            return wait(engine, state, pending, .stored);
        },
        .stored => {
            const stored = if (c.JS_IsUndefined(value) or c.JS_IsNull(value)) c.pi_js_undefined() else try scope.get(value, "result");
            if (!c.JS_IsUndefined(stored)) return @import("native_chord_json.zig").copyJson(engine, stored, c.pi_js_undefined());
            const settled = try scope.get(state, "settled");
            const task_state = try scope.get(settled, "state");
            const outcome = try scope.get(task_state, "outcome");
            return fallback(engine, try scope.get(state, "id"), try scope.get(state, "name"), outcome);
        },
    }
}
fn fallback(engine: *Engine, id: c.JSValue, name: c.JSValue, outcome: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const status = try scope.get(outcome, "status");
    const faulted = try @import("native_durable_tool_call.zig").equalsString(engine, status, "faulted");
    const orphaned = if (faulted) false else try @import("native_durable_tool_call.zig").equalsString(engine, try scope.get(outcome, "status"), "orphaned");
    const name_text = try engine.toString(name);
    defer engine.gpa.free(name_text);
    const message = if (faulted or orphaned) message: {
        const reason = if (faulted) reason: {
            const error_value = try scope.get(outcome, "error");
            break :reason try scope.get(error_value, "message");
        } else try scope.get(outcome, "reason");
        const reason_text = try engine.toString(reason);
        defer engine.gpa.free(reason_text);
        break :message try std.fmt.allocPrint(engine.gpa, "Tool {s}{s}{s}", .{ name_text, if (faulted) " failed: " else " could not resume: ", reason_text });
    } else try std.fmt.allocPrint(engine.gpa, "Tool {s} ended without a result", .{name_text});
    defer engine.gpa.free(message);
    const diagnostic = try scope.own(try vm.object(engine));
    try @import("native_tool_info.zig").putData(engine, diagnostic, "severity", try engine.checked(c.JS_NewString(engine.context, "error")));
    try put(engine, diagnostic, "code", try scope.get(outcome, "status"));
    try @import("native_tool_info.zig").putData(engine, diagnostic, "message", try engine.checked(c.JS_NewStringLen(engine.context, message.ptr, message.len)));
    const diagnostics = try scope.own(try vm.array(engine));
    try js.push(engine, diagnostics, diagnostic);
    const result = try vm.object(engine);
    errdefer engine.freeValue(result);
    try put(engine, result, "taskId", id);
    try put(engine, result, "isError", c.pi_js_bool(engine.context, 1));
    try put(engine, result, "diagnostics", diagnostics);
    return result;
}
