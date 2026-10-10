//! ToolTask's asynchronous terminal transaction. Continuations retain only VM
//! values; no transaction, mutex, or borrowed native stack crosses an await.
const std = @import("std");
const engine_mod = @import("engine.zig");
const vm = @import("native_values.zig");
const putData = @import("native_tool_info.zig").putData;
const awaiting = @import("native_durable_await.zig");
const c = engine_mod.c;
const Engine = engine_mod.Engine;
pub const Tokens = struct { live: c.JSValue, nested_calls: c.JSValue, nested_results: c.JSValue, tool_result: c.JSValue, usage: c.JSValue, iterator_symbol: c.JSValue };
pub const Ending = enum { completed, failed, aborted };
pub const Result = union(enum) { final: c.JSValue, slot_error: struct { code: c.JSValue, message: c.JSValue } };
const Stage = enum(c_int) { index, made_nested, children_aborted, live, usage, parent_index, nested_stored, entry_stored, committed };
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
    fn get(self: *Scope, receiver: c.JSValue, name: [:0]const u8) !c.JSValue {
        return self.own(try vm.get(self.engine, receiver, name));
    }
    fn invoke(self: *Scope, receiver: c.JSValue, name: [:0]const u8, args: []const c.JSValue) !c.JSValue {
        return self.own(try vm.invoke(self.engine, receiver, name, args));
    }
};
fn statePut(engine: *Engine, state: c.JSValue, key: [:0]const u8, value: c.JSValue) !void {
    try putData(engine, state, key, c.JS_DupValue(engine.context, value));
}
fn wait(engine: *Engine, state: c.JSValue, value: c.JSValue, stage: Stage) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    var intrinsics: awaiting.Intrinsics = .{
        .constructor = try scope.get(state, "promiseConstructor"),
        .resolve = try scope.get(state, "promiseResolve"),
        .then_function = try scope.get(state, "promiseThen"),
    };
    return awaiting.continueWith(advance, engine, &intrinsics, state, value, @intFromEnum(stage));
}

pub fn run(engine: *Engine, intrinsics: *awaiting.Intrinsics, tokens: Tokens, runtime: c.JSValue, input: c.JSValue, call: c.JSValue, ending: Ending, result: Result, context: c.JSValue, duration_ms: c.JSValue, failure_message: c.JSValue) !c.JSValue {
    const state = try vm.object(engine);
    defer engine.freeValue(state);
    inline for (.{ .{ "runtime", runtime }, .{ "input", input }, .{ "call", call }, .{ "context", context }, .{ "duration", duration_ms }, .{ "failureMessage", failure_message }, .{ "liveToken", tokens.live }, .{ "nestedCallsToken", tokens.nested_calls }, .{ "nestedResultToken", tokens.nested_results }, .{ "toolResultToken", tokens.tool_result }, .{ "usageToken", tokens.usage }, .{ "promiseConstructor", intrinsics.constructor }, .{ "promiseResolve", intrinsics.resolve }, .{ "promiseThen", intrinsics.then_function } }) |field| try statePut(engine, state, field[0], field[1]);
    switch (result) {
        .final => |value| try statePut(engine, state, "result", value),
        .slot_error => |failure| {
            try statePut(engine, state, "slotErrorCode", failure.code);
            try statePut(engine, state, "slotErrorMessage", failure.message);
        },
    }
    try statePut(engine, state, "iteratorSymbol", tokens.iterator_symbol);
    try putData(engine, state, "ending", try engine.checked(c.JS_NewString(engine.context, @tagName(ending))));
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const snapshot = try scope.invoke(runtime, "ownedTasks", &.{context});
    return wait(engine, state, snapshot, .index);
}

fn advance(engine: *Engine, state: c.JSValue, value: c.JSValue, rejected: bool, raw_stage: c_int) !c.JSValue {
    if (rejected) return c.JS_Throw(engine.context, c.JS_DupValue(engine.context, value));
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const runtime = try scope.get(state, "runtime");
    const context = try scope.get(state, "context");
    switch (@as(Stage, @enumFromInt(raw_stage))) {
        .index => {
            const ids = try scope.own(try vm.array(engine));
            for (0..try vm.length(engine, value)) |index| {
                const record = try scope.own(try engine.checked(c.JS_GetPropertyUint32(engine.context, value, @intCast(index))));
                if (!try @import("native_durable_tool_call.zig").equalsString(engine, try scope.get(record, "kind"), "pi.tool")) continue;
                const input = try scope.get(record, "input");
                if (!try @import("native_durable_tool_call.zig").equalsString(engine, try scope.get(input, "kind"), "nested")) continue;
                _ = try scope.invoke(ids, "push", &.{try scope.get(record, "id")});
            }
            try statePut(engine, state, "nestedIds", ids);
            const label = try scope.own(try engine.checked(c.JS_NewString(engine.context, "pi.tool.madeNestedCalls")));
            const memo = try scope.invoke(runtime, "memo", &.{ label, context });
            return wait(engine, state, memo, .made_nested);
        },
        .made_nested => {
            try statePut(engine, state, "madeNested", c.pi_js_bool(engine.context, @intFromBool(c.JS_IsStrictEqual(engine.context, value, c.pi_js_bool(engine.context, 1)))));
            const object = try scope.own(c.JS_GetGlobalObject(engine.context));
            const ids = try scope.get(state, "nestedIds");
            var captures = [_]c.JSValue{ runtime, context };
            const abort = try scope.own(try engine.checked(c.JS_NewCFunctionData2(engine.context, abortChild, "", 1, 0, captures.len, &captures)));
            const pending = try scope.invoke(ids, "map", &.{abort});
            const promise = try scope.get(object, "Promise");
            const all = try scope.invoke(promise, "all", &.{pending});
            return wait(engine, state, all, .children_aborted);
        },
        .children_aborted => {
            var captures = [_]c.JSValue{state};
            const callback = try scope.own(try engine.checked(c.JS_NewCFunctionData2(engine.context, transaction, "", 1, 0, captures.len, &captures)));
            const committed = try scope.invoke(runtime, "commit", &.{ callback, context });
            return wait(engine, state, committed, .committed);
        },
        .committed => return c.pi_js_undefined(),
        else => return transactionStep(engine, state, value, @enumFromInt(raw_stage)),
    }
}
fn numericOrder(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = Engine.fromContext(context.?);
    var left: f64 = 0;
    var right: f64 = 0;
    if (c.JS_ToFloat64(engine.context, &left, if (argc > 0) argv[0] else c.pi_js_undefined()) < 0 or c.JS_ToFloat64(engine.context, &right, if (argc > 1) argv[1] else c.pi_js_undefined()) < 0) return engine.throwCaptured();
    return c.JS_NewFloat64(engine.context, left - right);
}
fn abortChild(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, data: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = Engine.fromContext(context.?);
    return vm.invoke(engine, data[0], "abortOwned", &.{ if (argc > 0) argv[0] else c.pi_js_undefined(), data[1] }) catch |err| @import("native_durable.zig").reject(engine, err);
}
fn transaction(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, data: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = Engine.fromContext(context.?);
    return startTransaction(engine, data[0], if (argc > 0) argv[0] else c.pi_js_undefined()) catch |err| @import("native_durable.zig").reject(engine, err);
}
fn startTransaction(engine: *Engine, state: c.JSValue, tx: c.JSValue) !c.JSValue {
    try statePut(engine, state, "tx", tx);
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const runtime = try scope.get(state, "runtime");
    const conversation = try scope.get(runtime, "conversationId");
    const token = try scope.get(state, "liveToken");
    const live = try scope.invoke(tx, "doc", &.{ token, conversation });
    return wait(engine, state, live, .live);
}
fn transactionStep(engine: *Engine, state: c.JSValue, value: c.JSValue, stage: Stage) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const runtime = try scope.get(state, "runtime");
    const tx = try scope.get(state, "tx");
    const input = try scope.get(state, "input");
    const call = try scope.get(state, "call");
    var result = try scope.get(state, "result");
    const task_id = try scope.get(runtime, "taskId");
    const conversation_id = try scope.get(runtime, "conversationId");
    const kind = try scope.get(input, "kind");
    const nested = try @import("native_durable_tool_call.zig").equalsString(engine, kind, "nested");
    switch (stage) {
        .live => {
            try statePut(engine, state, "live", value);
            const slot = try scope.own(try @import("native_durable_tool_slots.zig").find(engine, value, task_id));
            try statePut(engine, state, "slot", slot);
            const error_code = try scope.get(state, "slotErrorCode");
            if (!c.JS_IsUndefined(error_code)) {
                const message = try scope.get(state, "slotErrorMessage");
                const symbol = try scope.get(state, "iteratorSymbol");
                result = try scope.own(try resultFromSlot(engine, slot, error_code, message, symbol));
                try statePut(engine, state, "result", result);
            }
            if (nested) {
                const duration = try scope.get(state, "duration");
                const projected = try scope.own(try @import("native_durable_tool_output.zig").nestedResult(engine, task_id, result, duration));
                try statePut(engine, state, "nestedResult", projected);
            } else try buildEntry(engine, state);
            const usage_source = if (nested) try scope.get(state, "nestedResult") else result;
            const usage = try scope.get(usage_source, "usage");
            if (!c.JS_IsUndefined(usage)) {
                try statePut(engine, state, "recordedUsage", usage);
                const token = try scope.get(state, "usageToken");
                const doc = try scope.invoke(tx, "doc", &.{ token, conversation_id });
                return wait(engine, state, doc, .usage);
            }
            return afterUsage(engine, state, nested);
        },
        .usage => {
            const usage = try scope.get(state, "recordedUsage");
            const name = try scope.get(call, "name");
            try recordUsage(engine, value, name, usage);
            return afterUsage(engine, state, nested);
        },
        .parent_index => {
            const indexed = try scope.get(value, "taskId");
            if (!c.JS_IsStrictEqual(engine.context, indexed, task_id)) {
                const id = try scope.get(call, "id");
                const text = try engine.toString(id);
                defer engine.gpa.free(text);
                const message = try std.fmt.allocPrint(engine.gpa, "Nested call {s} is not in its caller's index", .{text});
                defer engine.gpa.free(message);
                return throwError(engine, message);
            }
            const projected = try scope.get(state, "nestedResult");
            try statePut(engine, value, "result", projected);
            return transactionStep(engine, state, value, .nested_stored);
        },
        .nested_stored => {
            const slot = try scope.get(state, "slot");
            if (!c.JS_IsUndefined(slot) and try hasParent(engine, slot)) {
                try @import("native_durable_tool_slots.zig").finish(engine, slot);
                const projected = try scope.get(state, "nestedResult");
                const summary = try scope.own(try buildSummary(engine, projected, result));
                try vm.put(engine, slot, "summary", c.JS_DupValue(engine.context, summary));
            }
            const receipt = try scope.own(try vm.object(engine));
            try putData(engine, receipt, "kind", try engine.checked(c.JS_NewString(engine.context, "nested")));
            return finishOutcome(engine, state, receipt);
        },
        .entry_stored => {
            const entry_id = try scope.get(value, "id");
            const slot = try scope.get(state, "slot");
            if (!c.JS_IsUndefined(slot) and !try hasParent(engine, slot)) {
                try @import("native_durable_tool_slots.zig").finish(engine, slot);
                try vm.put(engine, slot, "entry", c.JS_DupValue(engine.context, entry_id));
            }
            const receipt = try scope.own(try vm.object(engine));
            try putData(engine, receipt, "kind", try engine.checked(c.JS_NewString(engine.context, "model")));
            try statePut(engine, receipt, "entryId", entry_id);
            const control = try scope.get(result, "control");
            const ending = try scope.get(state, "ending");
            if (!c.JS_IsUndefined(control) and try @import("native_durable_tool_call.zig").equalsString(engine, ending, "completed")) {
                const actual_control = try scope.get(result, "control");
                const copied = try scope.own(try strictCopy(engine, actual_control));
                try statePut(engine, receipt, "control", copied);
            }
            return finishOutcome(engine, state, receipt);
        },
        else => unreachable,
    }
}
fn afterUsage(engine: *Engine, state: c.JSValue, nested: bool) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const tx = try scope.get(state, "tx");
    if (nested) {
        const input = try scope.get(state, "input");
        const parent = try scope.get(input, "parent");
        const token = try scope.get(state, "nestedCallsToken");
        const key = try scope.get(input, "key");
        const index = try scope.invoke(tx, "doc", &.{ token, parent, key, c.pi_js_null() });
        return wait(engine, state, index, .parent_index);
    }
    const runtime = try scope.get(state, "runtime");
    const conversation = try scope.get(runtime, "conversationId");
    const token = try scope.get(state, "toolResultToken");
    const data = try scope.get(state, "entryData");
    const entry = try scope.invoke(tx, "appendEntry", &.{ token, conversation, data });
    return wait(engine, state, entry, .entry_stored);
}
fn finishOutcome(engine: *Engine, state: c.JSValue, receipt: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    if (c.JS_IsStrictEqual(engine.context, try scope.get(state, "madeNested"), c.pi_js_bool(engine.context, 1))) {
        const live = try scope.get(state, "live");
        const runtime = try scope.get(state, "runtime");
        const task_id = try scope.get(runtime, "taskId");
        const symbol = try scope.get(state, "iteratorSymbol");
        try @import("native_durable_tool_slots.zig").removeBelow(engine, live, task_id, symbol);
    }
    const result = try vm.object(engine);
    errdefer engine.freeValue(result);
    try putData(engine, result, "status", try engine.checked(c.JS_NewString(engine.context, "terminal")));
    const outcome = try scope.own(try vm.object(engine));
    const ending = try scope.get(state, "ending");
    try statePut(engine, outcome, "status", ending);
    if (try @import("native_durable_tool_call.zig").equalsString(engine, ending, "failed")) {
        const error_value = try scope.own(try vm.object(engine));
        const message = try scope.get(state, "failureMessage");
        try statePut(engine, error_value, "message", message);
        try statePut(engine, outcome, "error", error_value);
    }
    try statePut(engine, outcome, "result", receipt);
    try statePut(engine, result, "outcome", outcome);
    return result;
}
fn hasParent(engine: *Engine, slot: c.JSValue) !bool {
    const atom = c.JS_NewAtom(engine.context, "parentTaskId");
    defer c.JS_FreeAtom(engine.context, atom);
    const result = c.JS_HasProperty(engine.context, slot, atom);
    if (result < 0) {
        _ = try engine.checked(c.JS_Throw(engine.context, c.JS_GetException(engine.context)));
        unreachable;
    }
    return result != 0;
}
fn strictCopy(engine: *Engine, value: c.JSValue) !c.JSValue {
    const options = try vm.object(engine);
    defer engine.freeValue(options);
    try putData(engine, options, "omitUndefinedProperties", c.pi_js_bool(engine.context, 1));
    return @import("native_chord_json.zig").copyJson(engine, value, options);
}
fn throwError(engine: *Engine, message: []const u8) !c.JSValue {
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    const constructor = try vm.get(engine, global, "Error");
    defer engine.freeValue(constructor);
    const text = try engine.checked(c.JS_NewStringLen(engine.context, message.ptr, message.len));
    defer engine.freeValue(text);
    var args = [_]c.JSValue{text};
    const failure = try engine.checked(c.JS_CallConstructor(engine.context, constructor, args.len, &args));
    return engine.checked(c.JS_Throw(engine.context, failure));
}
fn nullish(value: c.JSValue) bool {
    return c.JS_IsUndefined(value) or c.JS_IsNull(value);
}
/// Reconstruct cancellation/recovery results from the durable partial slot.
pub fn resultFromSlot(engine: *Engine, slot: c.JSValue, code: c.JSValue, message: c.JSValue, iterator_symbol: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const raw_diagnostics = if (nullish(slot)) c.pi_js_undefined() else try scope.get(slot, "diagnostics");
    const diagnostics_source = if (nullish(raw_diagnostics)) try scope.own(try vm.array(engine)) else raw_diagnostics;
    const diagnostics = try scope.own(try @import("native_js_values.zig").collect(engine, diagnostics_source, iterator_symbol));
    const raw_bytes = if (nullish(slot)) c.pi_js_undefined() else try scope.get(slot, "droppedBytes");
    const bytes = if (nullish(raw_bytes)) c.JS_NewInt32(engine.context, 0) else raw_bytes;
    var numeric_bytes: f64 = 0;
    if (c.JS_ToFloat64(engine.context, &numeric_bytes, bytes) < 0) {
        _ = try engine.checked(c.JS_Throw(engine.context, c.JS_GetException(engine.context)));
        unreachable;
    }
    if (numeric_bytes > 0) {
        const raw_lines = if (nullish(slot)) c.pi_js_undefined() else try scope.get(slot, "droppedLines");
        const lines = if (nullish(raw_lines)) c.JS_NewInt32(engine.context, 0) else raw_lines;
        const line_text = try engine.toString(lines);
        defer engine.gpa.free(line_text);
        const byte_text = try engine.toString(bytes);
        defer engine.gpa.free(byte_text);
        const text = try std.fmt.allocPrint(engine.gpa, "Output truncated: {s} lines, {s} bytes dropped", .{ line_text, byte_text });
        defer engine.gpa.free(text);
        const truncated = try scope.own(try vm.object(engine));
        try putData(engine, truncated, "severity", try engine.checked(c.JS_NewString(engine.context, "warn")));
        try putData(engine, truncated, "code", try engine.checked(c.JS_NewString(engine.context, "truncated")));
        try putData(engine, truncated, "message", try engine.checked(c.JS_NewStringLen(engine.context, text.ptr, text.len)));
        _ = try scope.invoke(diagnostics, "push", &.{truncated});
    }
    const failure = try scope.own(try vm.object(engine));
    try putData(engine, failure, "severity", try engine.checked(c.JS_NewString(engine.context, "error")));
    try statePut(engine, failure, "code", code);
    try statePut(engine, failure, "message", message);
    _ = try scope.invoke(diagnostics, "push", &.{failure});
    const result = try vm.object(engine);
    errdefer engine.freeValue(result);
    const content = try scope.own(try vm.array(engine));
    const first_output = if (nullish(slot)) c.pi_js_undefined() else try scope.get(slot, "output");
    if (!c.JS_IsUndefined(first_output)) {
        const second_output = try scope.get(slot, "output");
        if (!try @import("native_durable_tool_call.zig").equalsString(engine, second_output, "")) {
            const item = try scope.own(try vm.object(engine));
            try putData(engine, item, "type", try engine.checked(c.JS_NewString(engine.context, "text")));
            try statePut(engine, item, "text", try scope.get(slot, "output"));
            if (c.JS_SetPropertyUint32(engine.context, content, 0, c.JS_DupValue(engine.context, item)) < 0) return error.JavaScriptException;
        }
    }
    try statePut(engine, result, "output", content);
    try putData(engine, result, "isError", c.pi_js_bool(engine.context, 1));
    const details = if (nullish(slot)) c.pi_js_undefined() else try scope.get(slot, "details");
    if (!c.JS_IsUndefined(details)) try statePut(engine, result, "details", try scope.get(slot, "details"));
    try statePut(engine, result, "diagnostics", diagnostics);
    return result;
}
fn buildEntry(engine: *Engine, state: c.JSValue) !void {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const runtime = try scope.get(state, "runtime");
    const timestamp = try scope.invoke(runtime, "now", &.{});
    const result = try scope.get(state, "result");
    const symbol = try scope.get(state, "iteratorSymbol");
    const raw_diagnostics = try scope.get(result, "diagnostics");
    const empty_diagnostics = if (nullish(raw_diagnostics)) try scope.own(try vm.array(engine)) else raw_diagnostics;
    const diagnostics = try scope.own(try @import("native_js_values.zig").collect(engine, empty_diagnostics, symbol));
    const raw_output = try scope.get(result, "output");
    const empty_output = if (nullish(raw_output)) try scope.own(try vm.array(engine)) else raw_output;
    const content = try scope.own(try @import("native_js_values.zig").collect(engine, empty_output, symbol));
    if (try vm.length(engine, diagnostics) != 0) {
        const formatted = try scope.own(try engine.checked(c.JS_NewCFunction(engine.context, formatDiagnostic, "", 1)));
        const lines = try scope.invoke(diagnostics, "map", &.{formatted});
        const separator = try scope.own(try engine.checked(c.JS_NewString(engine.context, "\n")));
        const joined = try scope.invoke(lines, "join", &.{separator});
        const text = try engine.toString(joined);
        defer engine.gpa.free(text);
        const wrapped = try std.fmt.allocPrint(engine.gpa, "<harness>\n{s}\n</harness>", .{text});
        defer engine.gpa.free(wrapped);
        const item = try scope.own(try vm.object(engine));
        try putData(engine, item, "type", try engine.checked(c.JS_NewString(engine.context, "text")));
        try putData(engine, item, "text", try engine.checked(c.JS_NewStringLen(engine.context, wrapped.ptr, wrapped.len)));
        const pushed = try scope.invoke(content, "push", &.{item});
        _ = pushed;
    }
    const call = try scope.get(state, "call");
    const message = try scope.own(try vm.object(engine));
    try putData(engine, message, "role", try engine.checked(c.JS_NewString(engine.context, "toolResult")));
    try statePut(engine, message, "toolCallId", try scope.get(call, "id"));
    try statePut(engine, message, "toolName", try scope.get(call, "name"));
    try statePut(engine, message, "content", content);
    inline for (.{ "details", "usage" }) |name| {
        if (!c.JS_IsUndefined(try scope.get(result, name))) try statePut(engine, message, name, try scope.get(result, name));
    }
    const is_error = try scope.get(result, "isError");
    try statePut(engine, message, "isError", if (nullish(is_error)) c.pi_js_bool(engine.context, 0) else is_error);
    const duration = try scope.get(state, "duration");
    if (!c.JS_IsUndefined(duration)) try statePut(engine, message, "durationMs", duration);
    try statePut(engine, message, "timestamp", timestamp);
    const models = try scope.own(try vm.array(engine));
    if (c.JS_SetPropertyUint32(engine.context, models, 0, c.JS_DupValue(engine.context, message)) < 0) return error.JavaScriptException;
    const metadata = try scope.own(try vm.object(engine));
    try statePut(engine, metadata, "diagnostics", diagnostics);
    const entry = try scope.own(try vm.object(engine));
    try statePut(engine, entry, "model", models);
    try statePut(engine, entry, "data", metadata);
    try statePut(engine, state, "entryData", entry);
}
fn formatDiagnostic(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = Engine.fromContext(context.?);
    return diagnosticText(engine, if (argc > 0) argv[0] else c.pi_js_undefined()) catch |err| @import("native_durable.zig").reject(engine, err);
}
fn diagnosticText(engine: *Engine, diagnostic: c.JSValue) !c.JSValue {
    const severity_value = try vm.get(engine, diagnostic, "severity");
    defer engine.freeValue(severity_value);
    const severity = try engine.toString(severity_value);
    defer engine.gpa.free(severity);
    const message_value = try vm.get(engine, diagnostic, "message");
    defer engine.freeValue(message_value);
    const message = try engine.toString(message_value);
    defer engine.gpa.free(message);
    const text = try std.fmt.allocPrint(engine.gpa, "[{s}] {s}", .{ severity, message });
    defer engine.gpa.free(text);
    return engine.checked(c.JS_NewStringLen(engine.context, text.ptr, text.len));
}
fn recordUsage(engine: *Engine, document: c.JSValue, key: c.JSValue, usage: c.JSValue) !void {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const totals = try scope.get(document, "tools");
    const global = try scope.own(c.JS_GetGlobalObject(engine.context));
    const object = try scope.get(global, "Object");
    const exists = try scope.invoke(object, "hasOwn", &.{ totals, key });
    const previous = if (c.JS_ToBool(engine.context, exists) == 0) c.pi_js_undefined() else try scope.own(try @import("native_js_values.zig").getKey(engine, totals, key));
    if (c.JS_IsUndefined(previous)) {
        const copy = try scope.own(try strictCopy(engine, usage));
        const atom = c.JS_ValueToAtom(engine.context, key);
        defer c.JS_FreeAtom(engine.context, atom);
        if (c.JS_SetProperty(engine.context, totals, atom, c.JS_DupValue(engine.context, copy)) < 0) return error.JavaScriptException;
        return;
    }
    inline for (.{ "input", "output", "cacheRead", "cacheWrite", "totalTokens" }) |name| try addCounter(engine, previous, usage, name, false);
    inline for (.{ "cacheWrite1h", "reasoning" }) |name| {
        if (!c.JS_IsUndefined(try scope.get(usage, name))) try addCounter(engine, previous, usage, name, true);
    }
    const cost = try scope.get(previous, "cost");
    const added_cost = try scope.get(usage, "cost");
    inline for (.{ "input", "output", "cacheRead", "cacheWrite", "total" }) |name| try addCounter(engine, cost, added_cost, name, false);
}
fn addCounter(engine: *Engine, target: c.JSValue, added: c.JSValue, name: [:0]const u8, optional: bool) !void {
    const previous = try vm.get(engine, target, name);
    defer engine.freeValue(previous);
    const next = try vm.get(engine, added, name);
    defer engine.freeValue(next);
    var left: f64 = 0;
    var right: f64 = 0;
    if ((!optional or !nullish(previous)) and c.JS_ToFloat64(engine.context, &left, previous) < 0) {
        _ = try engine.checked(c.JS_Throw(engine.context, c.JS_GetException(engine.context)));
        unreachable;
    }
    if (c.JS_ToFloat64(engine.context, &right, next) < 0) {
        _ = try engine.checked(c.JS_Throw(engine.context, c.JS_GetException(engine.context)));
        unreachable;
    }
    try vm.put(engine, target, name, c.JS_NewFloat64(engine.context, left + right));
}
fn buildSummary(engine: *Engine, nested: c.JSValue, result: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const summary = try vm.object(engine);
    errdefer engine.freeValue(summary);
    const is_error = try scope.get(nested, "isError");
    try statePut(engine, summary, "isError", is_error);
    inline for (.{ "durationMs", "usage" }) |name| {
        if (!c.JS_IsUndefined(try scope.get(nested, name))) try statePut(engine, summary, name, try scope.get(nested, name));
    }
    if (c.JS_ToBool(engine.context, is_error) != 0) {
        const diagnostics = try scope.get(nested, "diagnostics");
        const filter = try scope.own(try engine.checked(c.pi_js_function_magic(engine.context, diagnosticField, "", 1, 0)));
        const errors = try scope.invoke(diagnostics, "filter", &.{filter});
        const has_errors = try vm.length(engine, errors) != 0;
        const source = if (has_errors) errors else source: {
            const output = try scope.get(result, "output");
            break :source if (nullish(output)) try scope.own(try vm.array(engine)) else output;
        };
        const mapper = try scope.own(try engine.checked(c.pi_js_function_magic(engine.context, diagnosticField, "", 1, if (has_errors) 1 else 2)));
        const texts = try scope.invoke(source, if (has_errors) "map" else "flatMap", &.{mapper});
        const separator = try scope.own(try engine.checked(c.JS_NewString(engine.context, "\n")));
        const joined = try scope.invoke(texts, "join", &.{separator});
        const bounded = try scope.invoke(joined, "slice", &.{ c.JS_NewInt32(engine.context, 0), c.JS_NewInt32(engine.context, 500) });
        const text = try engine.toString(bounded);
        defer engine.gpa.free(text);
        if (text.len != 0) try statePut(engine, summary, "error", bounded);
    }
    return summary;
}
fn diagnosticField(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, magic: c_int) callconv(.c) c.JSValue {
    const engine = Engine.fromContext(context.?);
    return diagnosticFieldOwned(engine, if (argc > 0) argv[0] else c.pi_js_undefined(), magic) catch |err| @import("native_durable.zig").reject(engine, err);
}
fn diagnosticFieldOwned(engine: *Engine, item: c.JSValue, mode: c_int) !c.JSValue {
    if (mode == 1) return vm.get(engine, item, "message");
    const kind = try vm.get(engine, item, if (mode == 0) "severity" else "type");
    defer engine.freeValue(kind);
    const matches = try @import("native_durable_tool_call.zig").equalsString(engine, kind, if (mode == 0) "error" else "text");
    if (mode == 0) return c.pi_js_bool(engine.context, @intFromBool(matches));
    const array = try vm.array(engine);
    errdefer engine.freeValue(array);
    if (matches) {
        const text = try vm.get(engine, item, "text");
        if (c.JS_SetPropertyUint32(engine.context, array, 0, text) < 0) return error.JavaScriptException;
    }
    return array;
}
