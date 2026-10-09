//! Publish a running tool's retained output, details and added diagnostics.
const std = @import("std");
const engine_mod = @import("engine.zig");
const vm = @import("native_values.zig");
const js = @import("native_js_values.zig");
const awaiting = @import("native_durable_await.zig");
const c = engine_mod.c;
const Engine = engine_mod.Engine;
const Stage = enum(c_int) { live, committed };
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
fn number(engine: *Engine, value: c.JSValue) !f64 {
    var result: f64 = 0;
    if (c.JS_ToFloat64(engine.context, &result, value) < 0) return js.capture(engine);
    return result;
}
fn bytes(engine: *Engine, value: c.JSValue) !usize {
    const text = try engine.toString(value);
    defer engine.gpa.free(text);
    return text.len;
}
fn wait(engine: *Engine, state: c.JSValue, value: c.JSValue, stage: Stage) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const owner = try scope.get(state, "owner");
    var intrinsics: awaiting.Intrinsics = .{ .constructor = try scope.get(owner, "promiseConstructor"), .resolve = try scope.get(owner, "promiseResolve"), .then_function = try scope.get(owner, "promiseThen") };
    return awaiting.continueWith(advance, engine, &intrinsics, state, value, @intFromEnum(stage));
}
pub fn create(engine: *Engine, intrinsics: *awaiting.Intrinsics, runtime: c.JSValue, reported: c.JSValue, enabled: bool, context: c.JSValue, live_token: c.JSValue, iterator_symbol: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const state = try scope.own(try vm.object(engine));
    inline for (.{ .{ "runtime", runtime }, .{ "reported", reported }, .{ "context", context }, .{ "liveToken", live_token }, .{ "iterator", iterator_symbol }, .{ "promiseConstructor", intrinsics.constructor }, .{ "promiseResolve", intrinsics.resolve }, .{ "promiseThen", intrinsics.then_function } }) |field| try put(engine, state, field[0], field[1]);
    try put(engine, state, "enabled", c.pi_js_bool(engine.context, @intFromBool(enabled)));
    try @import("native_tool_info.zig").putData(engine, state, "writtenText", try engine.checked(c.JS_NewString(engine.context, "")));
    try put(engine, state, "writtenDiagnostics", c.JS_NewInt32(engine.context, 0));
    var captures = [_]c.JSValue{state};
    const write_function = try scope.own(try engine.checked(c.JS_NewCFunctionData2(engine.context, writeCallback, "", 0, 0, captures.len, &captures)));
    const on_error = try scope.own(try engine.checked(c.JS_NewCFunctionData2(engine.context, errorCallback, "", 1, 0, captures.len, &captures)));
    const settings = try scope.get(runtime, "settings");
    const progress = try scope.get(settings, "progress");
    const interval = try scope.get(progress, "outputIntervalMs");
    return @import("native_durable_progress.zig").create(engine, intrinsics, write_function, on_error, interval);
}
fn writeCallback(context: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue, _: c_int, data: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = Engine.fromContext(context.?);
    return write(engine, data[0]) catch |err| @import("native_durable.zig").rejectedPromise(engine, err);
}
fn errorCallback(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, data: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = Engine.fromContext(context.?);
    return report(engine, data[0], if (argc > 0) argv[0] else c.pi_js_undefined()) catch |err| @import("native_durable.zig").reject(engine, err);
}
fn report(engine: *Engine, state: c.JSValue, failure: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const runtime = try scope.get(state, "runtime");
    const signal = try scope.get(runtime, "signal");
    if (c.JS_ToBool(engine.context, try scope.get(signal, "aborted")) == 0) _ = try scope.invoke(runtime, "report", &.{failure});
    return c.pi_js_undefined();
}
fn write(engine: *Engine, owner: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    if (c.JS_ToBool(engine.context, try scope.get(owner, "enabled")) == 0) return @import("native_sdk.zig").promise(engine, c.JS_NewInt32(engine.context, 0));
    const state = try scope.own(try vm.object(engine));
    try put(engine, state, "owner", owner);
    const reported = try scope.get(owner, "reported");
    const buffer = try scope.get(reported, "output");
    const snapshot = try scope.invoke(buffer, "snapshot", &.{});
    try put(engine, state, "snapshot", snapshot);
    const text = try scope.get(snapshot, "text");
    const details = try scope.get(reported, "details");
    const diagnostics = try scope.get(reported, "diagnostics");
    const count = try scope.get(diagnostics, "length");
    inline for (.{ .{ "text", text }, .{ "details", details }, .{ "count", count } }) |field| try put(engine, state, field[0], field[1]);
    const written_count = try scope.get(owner, "writtenDiagnostics");
    const added = try scope.invoke(diagnostics, "slice", &.{ written_count, count });
    try put(engine, state, "added", added);
    const details_changed = !c.JS_IsStrictEqual(engine.context, details, try scope.get(owner, "writtenDetails"));
    try put(engine, state, "detailsChanged", c.pi_js_bool(engine.context, @intFromBool(details_changed)));
    const previous = try scope.get(owner, "writtenText");
    var written_bytes: usize = 0;
    if (!c.JS_IsStrictEqual(engine.context, text, previous)) {
        const starts = try scope.invoke(text, "startsWith", &.{previous});
        const shared = if (c.JS_ToBool(engine.context, starts) != 0) @as(usize, @intFromFloat(try number(engine, try scope.get(previous, "length")))) else shared: {
            const lhs = try @import("native_utf16.zig").unitsAlloc(engine, previous);
            defer engine.gpa.free(lhs);
            const rhs = try @import("native_utf16.zig").unitsAlloc(engine, text);
            defer engine.gpa.free(rhs);
            break :shared @import("native_durable_overlap.zig").overlap(lhs, rhs, 65_536, 64, 8);
        };
        const appended = try scope.invoke(text, "slice", &.{c.JS_NewFloat64(engine.context, @floatFromInt(shared))});
        written_bytes += try bytes(engine, appended);
    }
    const json = try scope.own(try js.global(engine, "JSON"));
    if (details_changed) {
        const serialized = try scope.invoke(json, "stringify", &.{if (c.JS_IsUndefined(details) or c.JS_IsNull(details)) c.pi_js_null() else details});
        written_bytes += try bytes(engine, serialized);
    }
    if (try vm.length(engine, added) > 0) {
        const serialized = try scope.invoke(json, "stringify", &.{added});
        written_bytes += try bytes(engine, serialized);
    }
    try put(engine, state, "bytes", c.JS_NewFloat64(engine.context, @floatFromInt(written_bytes)));
    var captures = [_]c.JSValue{state};
    const transaction = try scope.own(try engine.checked(c.JS_NewCFunctionData2(engine.context, transactionCallback, "", 1, 0, captures.len, &captures)));
    const runtime = try scope.get(owner, "runtime");
    const context = try scope.get(owner, "context");
    const pending = try scope.invoke(runtime, "commit", &.{ transaction, context });
    return wait(engine, state, pending, .committed);
}
fn transactionCallback(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, data: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = Engine.fromContext(context.?);
    return startTransaction(engine, data[0], if (argc > 0) argv[0] else c.pi_js_undefined()) catch |err| @import("native_durable.zig").rejectedPromise(engine, err);
}
fn startTransaction(engine: *Engine, state: c.JSValue, tx: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const owner = try scope.get(state, "owner");
    const runtime = try scope.get(owner, "runtime");
    const token = try scope.get(owner, "liveToken");
    const conversation = try scope.get(runtime, "conversationId");
    const pending = try scope.invoke(tx, "doc", &.{ token, conversation });
    return wait(engine, state, pending, .live);
}
fn advance(engine: *Engine, state: c.JSValue, value: c.JSValue, rejected: bool, raw_stage: c_int) !c.JSValue {
    if (rejected) return engine.checked(c.JS_Throw(engine.context, c.JS_DupValue(engine.context, value)));
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const owner = try scope.get(state, "owner");
    if (@as(Stage, @enumFromInt(raw_stage)) == .committed) {
        try put(engine, owner, "writtenText", try scope.get(state, "text"));
        try put(engine, owner, "writtenDetails", try scope.get(state, "details"));
        try put(engine, owner, "writtenDiagnostics", try scope.get(state, "count"));
        return vm.get(engine, state, "bytes");
    }
    const runtime = try scope.get(owner, "runtime");
    const task_id = try scope.get(runtime, "taskId");
    const slot = try scope.own(try @import("native_durable_tool_slots.zig").find(engine, value, task_id));
    if (c.JS_IsUndefined(slot)) return c.pi_js_undefined();
    const snapshot = try scope.get(state, "snapshot");
    const text = try scope.get(snapshot, "text");
    const previous = try scope.get(slot, "output");
    const empty = try scope.own(try engine.checked(c.JS_NewString(engine.context, "")));
    if (!c.JS_IsStrictEqual(engine.context, if (c.JS_IsUndefined(previous) or c.JS_IsNull(previous)) empty else previous, text)) try vm.put(engine, slot, "output", c.JS_DupValue(engine.context, text));
    inline for (.{ "droppedBytes", "droppedLines" }) |key| {
        const amount = try scope.get(snapshot, key);
        if (try number(engine, amount) > 0) try vm.put(engine, slot, key, try vm.get(engine, snapshot, key));
    }
    const details = try scope.get(state, "details");
    if (c.JS_ToBool(engine.context, try scope.get(state, "detailsChanged")) != 0 and !c.JS_IsUndefined(details)) {
        const key = try scope.own(try engine.checked(c.JS_NewString(engine.context, "details")));
        try @import("native_durable_tool_json.zig").assign(engine, slot, key, details, try scope.get(owner, "iterator"));
    }
    const added = try scope.get(state, "added");
    if (try vm.length(engine, added) > 0) {
        const old = try scope.get(slot, "diagnostics");
        if (c.JS_IsUndefined(old)) try vm.put(engine, slot, "diagnostics", try vm.array(engine));
        const symbol = try scope.get(owner, "iterator");
        var iterator = try js.Iterator.init(engine, added, symbol);
        defer iterator.deinit();
        errdefer iterator.closePreserving();
        while (try iterator.next()) |diagnostic| {
            defer engine.freeValue(diagnostic);
            const target = try scope.get(slot, "diagnostics");
            _ = try scope.invoke(target, "push", &.{diagnostic});
        }
    }
    return c.pi_js_undefined();
}
