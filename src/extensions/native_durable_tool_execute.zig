//! One native ToolTask execution attempt, from environment construction through
//! terminal settlement. All continuations own VM values, not native stack data.
const std = @import("std");
const engine_mod = @import("engine.zig");
const vm = @import("native_values.zig");
const js = @import("native_js_values.zig");
const awaiting = @import("native_durable_await.zig");
const output = @import("native_durable_tool_output.zig");
const terminal = @import("native_durable_tool_settle.zig");
const window = @import("native_durable_output_limits.zig");
const c = engine_mod.c;
const Engine = engine_mod.Engine;
pub const Tokens = struct { tool_task: c.JSValue, terminal: terminal.Tokens, sanitize_pattern: c.JSValue };
const Stage = enum(c_int) { environment, executed, admissions, stopped, projected, settled, aborted_stopped };
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
fn intrinsics(scope: *Scope, state: c.JSValue) !awaiting.Intrinsics {
    return .{ .constructor = try scope.get(state, "promiseConstructor"), .resolve = try scope.get(state, "promiseResolve"), .then_function = try scope.get(state, "promiseThen") };
}
fn wait(engine: *Engine, state: c.JSValue, value: c.JSValue, stage: Stage) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    var captured = try intrinsics(&scope, state);
    return awaiting.continueWith(advance, engine, &captured, state, value, @intFromEnum(stage));
}
pub fn run(engine: *Engine, captured: *awaiting.Intrinsics, cache: *output.Cache, tokens: Tokens, limits: window.Limits, runtime: c.JSValue, input: c.JSValue, call: c.JSValue, tool: c.JSValue, arguments: c.JSValue, context: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const state = try scope.own(try vm.object(engine));
    inline for (.{ .{ "runtime", runtime }, .{ "input", input }, .{ "call", call }, .{ "tool", tool }, .{ "arguments", arguments }, .{ "context", context }, .{ "toolTaskToken", tokens.tool_task }, .{ "liveToken", tokens.terminal.live }, .{ "nestedCallsToken", tokens.terminal.nested_calls }, .{ "nestedResultToken", tokens.terminal.nested_results }, .{ "toolResultToken", tokens.terminal.tool_result }, .{ "usageToken", tokens.terminal.usage }, .{ "iterator", tokens.terminal.iterator_symbol }, .{ "weak", cache.weak }, .{ "promiseConstructor", captured.constructor }, .{ "promiseResolve", captured.resolve }, .{ "promiseThen", captured.then_function } }) |field| try put(engine, state, field[0], field[1]);
    try put(engine, state, "maxBytes", c.JS_NewFloat64(engine.context, limits.maxBytes));
    try put(engine, state, "maxLines", c.JS_NewFloat64(engine.context, limits.maxLines));
    try put(engine, state, "tail", c.pi_js_bool(engine.context, @intFromBool(limits.retain == .tail)));
    try put(engine, state, "head", c.pi_js_bool(engine.context, @intFromBool(limits.retain == .head)));
    const reported = try scope.own(try vm.object(engine));
    try @import("native_tool_info.zig").putData(engine, reported, "output", try @import("native_durable_output_buffer.zig").create(engine, limits, tokens.sanitize_pattern));
    try @import("native_tool_info.zig").putData(engine, reported, "diagnostics", try vm.array(engine));
    try put(engine, state, "reported", reported);
    const streams = try @import("native_durable_tool_call.zig").equalsString(engine, try scope.get(input, "kind"), "model") or !c.JS_IsStrictEqual(engine.context, try scope.get(input, "progress"), c.pi_js_bool(engine.context, 0));
    const progress = try scope.own(try @import("native_durable_tool_progress.zig").create(engine, captured, runtime, reported, streams, context, tokens.terminal.live, tokens.terminal.iterator_symbol));
    try put(engine, state, "progress", progress);
    try @import("native_tool_info.zig").putData(engine, state, "admissions", try vm.array(engine));
    try put(engine, state, "resumes", c.pi_js_bool(engine.context, @intFromBool(try @import("native_durable_tool_call.zig").equalsString(engine, try scope.get(tool, "replay"), "safe"))));
    try put(engine, state, "sequence", c.JS_NewInt32(engine.context, 0));
    try put(engine, state, "ending", c.JS_NewInt32(engine.context, 0));
    const commit = try scope.own(try @import("native_durable_tool_transactions.zig").commitFunction(engine, state));
    const create_task = try scope.own(try @import("native_durable_tool_transactions.zig").createTaskFunction(engine, state));
    const execute_tool = try scope.own(try @import("native_durable_tool_nested.zig").function(engine, state));
    const api = try scope.own(try @import("native_durable_tool_api.zig").create(engine, state, limits, .{ .commit = commit, .create_task = create_task, .execute_tool = execute_tool }));
    try put(engine, state, "api", api);
    const pending = vm.invoke(engine, runtime, "env", &.{context}) catch |err| return failure(engine, state, err);
    defer engine.freeValue(pending);
    return wait(engine, state, pending, .environment);
}
fn performanceNow(scope: *Scope) !c.JSValue {
    const performance = try scope.own(try js.global(scope.engine, "performance"));
    return scope.invoke(performance, "now", &.{});
}
fn duration(engine: *Engine, state: c.JSValue) !void {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const now = try performanceNow(&scope);
    const started = try scope.get(state, "startedAt");
    var left: f64 = 0;
    var right: f64 = 0;
    if (c.JS_ToFloat64(engine.context, &left, now) < 0 or c.JS_ToFloat64(engine.context, &right, started) < 0) return js.capture(engine);
    const math = try scope.own(try js.global(engine, "Math"));
    const rounded = try scope.invoke(math, "round", &.{c.JS_NewFloat64(engine.context, left - right)});
    try put(engine, state, "duration", rounded);
}
fn advance(engine: *Engine, state: c.JSValue, value: c.JSValue, rejected: bool, raw_stage: c_int) !c.JSValue {
    const stage: Stage = @enumFromInt(raw_stage);
    if (stage == .executed) try duration(engine, state);
    if (rejected) {
        if (stage == .environment or stage == .executed) return failedValue(engine, state, value);
        if (stage == .projected or stage == .settled) {
            try settleWaiters(engine, state, false, value);
        }
        return engine.checked(c.JS_Throw(engine.context, c.JS_DupValue(engine.context, value)));
    }
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const runtime = try scope.get(state, "runtime");
    const context = try scope.get(state, "context");
    switch (stage) {
        .environment => {
            const started = try performanceNow(&scope);
            try put(engine, state, "startedAt", started);
            const api = try scope.get(state, "api");
            const projected = try scope.own(try js.spread(engine, api));
            try put(engine, projected, "env", value);
            const tool = try scope.get(state, "tool");
            const args = try scope.get(state, "arguments");
            const pending = vm.invoke(engine, tool, "execute", &.{ args, projected, context }) catch |err| {
                try duration(engine, state);
                return failure(engine, state, err);
            };
            defer engine.freeValue(pending);
            return wait(engine, state, pending, .executed);
        },
        .executed => {
            try put(engine, state, "result", value);
            return endAttempt(engine, state);
        },
        .admissions => {
            const reported = try scope.get(state, "reported");
            const buffer = try scope.get(reported, "output");
            _ = try scope.invoke(buffer, "end", &.{});
            const progress = try scope.get(state, "progress");
            const pending = try scope.invoke(progress, "stop", &.{});
            return wait(engine, state, pending, .stopped);
        },
        .stopped => {
            try put(engine, state, "pendingWaiters", value);
            const reported = try scope.get(state, "reported");
            const buffer = try scope.get(reported, "output");
            const snapshot = try scope.invoke(buffer, "snapshot", &.{});
            var captured = try intrinsics(&scope, state);
            var cache: output.Cache = .{ .engine = engine, .weak = try scope.get(state, "weak"), .iterator_symbol = try scope.get(state, "iterator") };
            const limits: window.Limits = .{ .maxBytes = try numeric(engine, try scope.get(state, "maxBytes")), .maxLines = try numeric(engine, try scope.get(state, "maxLines")), .retain = if (c.JS_ToBool(engine.context, try scope.get(state, "head")) != 0) .head else if (c.JS_ToBool(engine.context, try scope.get(state, "tail")) != 0) .tail else .other };
            const pending = @import("native_durable_tool_final.zig").run(engine, &captured, &cache, runtime, try scope.get(state, "input"), try scope.get(state, "call"), try scope.get(state, "tool"), try scope.get(state, "result"), .{ .snapshot = snapshot, .details = try scope.get(reported, "details"), .diagnostics = try scope.get(reported, "diagnostics"), .limits = limits }, context) catch |err| return finalFailure(engine, state, err);
            defer engine.freeValue(pending);
            return wait(engine, state, pending, .projected);
        },
        .projected => {
            var captured = try intrinsics(&scope, state);
            const ending = try scope.get(state, "ending");
            const is_failed = try numeric(engine, ending) != 0;
            const tokens: terminal.Tokens = .{ .live = try scope.get(state, "liveToken"), .nested_calls = try scope.get(state, "nestedCallsToken"), .nested_results = try scope.get(state, "nestedResultToken"), .tool_result = try scope.get(state, "toolResultToken"), .usage = try scope.get(state, "usageToken"), .iterator_symbol = try scope.get(state, "iterator") };
            const pending = terminal.run(engine, &captured, tokens, runtime, try scope.get(state, "input"), try scope.get(state, "call"), if (is_failed) .failed else .completed, .{ .final = value }, context, try scope.get(state, "duration"), try scope.get(state, "failureMessage")) catch |err| return finalFailure(engine, state, err);
            defer engine.freeValue(pending);
            return wait(engine, state, pending, .settled);
        },
        .settled => {
            try settleWaiters(engine, state, true, c.pi_js_undefined());
            return c.pi_js_undefined();
        },
        .aborted_stopped => {
            try put(engine, state, "pendingWaiters", value);
            const failure_value = try scope.get(state, "abortFailure");
            try settleWaiters(engine, state, false, failure_value);
            return engine.checked(c.JS_Throw(engine.context, c.JS_DupValue(engine.context, failure_value)));
        },
    }
}
fn numeric(engine: *Engine, value: c.JSValue) !f64 {
    var number: f64 = 0;
    if (c.JS_ToFloat64(engine.context, &number, value) < 0) return js.capture(engine);
    return number;
}
fn failure(engine: *Engine, state: c.JSValue, err: anyerror) !c.JSValue {
    if (err != error.JavaScriptException) return err;
    return failedValue(engine, state, engine.captured_exception orelse return err);
}
fn failedValue(engine: *Engine, state: c.JSValue, value: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const original = try scope.own(c.JS_DupValue(engine.context, value));
    const runtime = try scope.get(state, "runtime");
    const signal = try scope.get(runtime, "signal");
    if (c.JS_ToBool(engine.context, try scope.get(signal, "aborted")) != 0) {
        try put(engine, state, "ended", c.pi_js_bool(engine.context, 1));
        try put(engine, state, "abortFailure", original);
        const progress = try scope.get(state, "progress");
        const pending = try scope.invoke(progress, "stop", &.{});
        return wait(engine, state, pending, .aborted_stopped);
    }
    const result = try scope.own(try vm.object(engine));
    try put(engine, result, "isError", c.pi_js_bool(engine.context, 1));
    const diagnostic = try scope.own(try vm.object(engine));
    try @import("native_tool_info.zig").putData(engine, diagnostic, "severity", try engine.checked(c.JS_NewString(engine.context, "error")));
    try @import("native_tool_info.zig").putData(engine, diagnostic, "code", try engine.checked(c.JS_NewString(engine.context, "tool_error")));
    const message = try scope.own(try @import("native_durable_errors.zig").errorMessage(engine, original));
    try put(engine, diagnostic, "message", message);
    const diagnostics = try scope.own(try vm.array(engine));
    try js.push(engine, diagnostics, diagnostic);
    try put(engine, result, "diagnostics", diagnostics);
    try put(engine, state, "result", result);
    try put(engine, state, "ending", c.JS_NewInt32(engine.context, 1));
    const call = try scope.get(state, "call");
    const name = try engine.toString(try scope.get(call, "name"));
    defer engine.gpa.free(name);
    const text = try std.fmt.allocPrint(engine.gpa, "Tool {s} threw", .{name});
    defer engine.gpa.free(text);
    try @import("native_tool_info.zig").putData(engine, state, "failureMessage", try engine.checked(c.JS_NewStringLen(engine.context, text.ptr, text.len)));
    return endAttempt(engine, state);
}
fn endAttempt(engine: *Engine, state: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    try put(engine, state, "ended", c.pi_js_bool(engine.context, 1));
    const admissions = try scope.get(state, "admissions");
    const promise = try scope.own(try js.global(engine, "Promise"));
    const pending = try scope.invoke(promise, "allSettled", &.{admissions});
    return wait(engine, state, pending, .admissions);
}
fn finalFailure(engine: *Engine, state: c.JSValue, err: anyerror) !c.JSValue {
    if (err == error.JavaScriptException) {
        const original = engine.captured_exception orelse return err;
        const retained = c.JS_DupValue(engine.context, original);
        defer engine.freeValue(retained);
        try settleWaiters(engine, state, false, retained);
        return engine.checked(c.JS_Throw(engine.context, c.JS_DupValue(engine.context, retained)));
    }
    return err;
}
fn settleWaiters(engine: *Engine, state: c.JSValue, success: bool, value: c.JSValue) !void {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const pending = try scope.get(state, "pendingWaiters");
    if (c.JS_IsUndefined(pending)) return;
    const symbol = try scope.get(state, "iterator");
    var iterator = try js.Iterator.init(engine, pending, symbol);
    defer iterator.deinit();
    errdefer iterator.closePreserving();
    while (try iterator.next()) |waiter| {
        defer engine.freeValue(waiter);
        _ = try scope.invoke(waiter, if (success) "resolve" else "reject", if (success) &.{} else &.{value});
    }
}
