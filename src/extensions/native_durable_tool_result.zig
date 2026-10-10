//! Shared native tool-result entry writer for generation and abort paths.
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
pub fn harnessError(engine: *Engine, code: c.JSValue, message: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const diagnostic = try scope.own(try vm.object(engine));
    try put(engine, diagnostic, "severity", try scope.text("error"));
    try put(engine, diagnostic, "code", code);
    try put(engine, diagnostic, "message", message);
    const diagnostics = try scope.own(try vm.array(engine));
    try js.push(engine, diagnostics, diagnostic);
    const result = try vm.object(engine);
    errdefer engine.freeValue(result);
    try @import("native_tool_info.zig").putData(engine,result,"output",try vm.array(engine));
    try put(engine, result, "isError", c.pi_js_bool(engine.context, 1));
    try put(engine, result, "diagnostics", diagnostics);
    return result;
}
pub fn append(engine: *Engine, captured: *awaiting.Intrinsics, tx: c.JSValue, conversation: c.JSValue, call: c.JSValue, result: c.JSValue, timestamp: c.JSValue, duration: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const symbol_object = try scope.own(try js.global(engine, "Symbol"));
    const symbol = try scope.get(symbol_object, "iterator");
    const raw_diagnostics = try scope.get(result, "diagnostics");
    const raw_output = try scope.get(result, "output");
    const empty = try scope.own(try vm.array(engine));
    const diagnostics = try scope.own(try js.collect(engine, if (c.JS_IsUndefined(raw_diagnostics) or c.JS_IsNull(raw_diagnostics)) empty else raw_diagnostics, symbol));
    const content = try scope.own(try js.collect(engine, if (c.JS_IsUndefined(raw_output) or c.JS_IsNull(raw_output)) empty else raw_output, symbol));
    if (try vm.length(engine, diagnostics) > 0) {
        const lines = try scope.own(try vm.array(engine));
        for (0..try vm.length(engine, diagnostics)) |index| {
            const item = try scope.own(try engine.checked(c.JS_GetPropertyUint32(engine.context, diagnostics, @intCast(index))));
            const line = try scope.own(try @import("native_utf16.zig").concat(engine, &.{ try scope.text("["), try scope.get(item, "severity"), try scope.text("] "), try scope.get(item, "message") }));
            try js.push(engine, lines, line);
        }
        const joined = try scope.invoke(lines, "join", &.{try scope.text("\n")});
        const text = try scope.own(try @import("native_utf16.zig").concat(engine, &.{ try scope.text("<harness>\n"), joined, try scope.text("\n</harness>") }));
        const item = try scope.own(try vm.object(engine));
        try put(engine, item, "type", try scope.text("text"));
        try put(engine, item, "text", text);
        try js.push(engine, content, item);
    }
    const message = try scope.own(try vm.object(engine));
    try put(engine, message, "role", try scope.text("toolResult"));
    try put(engine, message, "toolCallId", try scope.get(call, "id"));
    try put(engine, message, "toolName", try scope.get(call, "name"));
    try put(engine, message, "content", content);
    inline for (.{ "details", "usage" }) |key| {
        const value = try scope.get(result, key);
        if (!c.JS_IsUndefined(value)) try put(engine, message, key, value);
    }
    const is_error = try scope.get(result, "isError");
    try put(engine, message, "isError", if (c.JS_IsUndefined(is_error) or c.JS_IsNull(is_error)) c.pi_js_bool(engine.context, 0) else is_error);
    if (!c.JS_IsUndefined(duration)) try put(engine, message, "durationMs", duration);
    try put(engine, message, "timestamp", timestamp);
    const model = try scope.own(try vm.array(engine));
    try js.push(engine, model, message);
    const data = try scope.own(try vm.object(engine));
    try put(engine, data, "diagnostics", diagnostics);
    const entry = try scope.own(try vm.object(engine));
    try put(engine, entry, "model", model);
    try put(engine, entry, "data", data);
    const exports = engine.native_module_values.get("@earendil-works/pi-durable") orelse return error.DurableModuleUnavailable;
    const usage = try scope.get(result, "usage");
    if (c.JS_IsUndefined(usage)) return vm.invoke(engine, tx, "appendEntry", &.{ try scope.get(exports, "ToolResultEntry"), conversation, entry });
    const state = try scope.own(try vm.object(engine));
    inline for (.{ .{ "tx", tx }, .{ "conversation", conversation }, .{ "entry", entry }, .{ "token", try scope.get(exports, "ToolResultEntry") } }) |field| try put(engine, state, field[0], field[1]);
    const pending = try scope.own(try @import("native_durable_usage.zig").record(engine, captured, tx, conversation, "tools", try scope.get(call, "name"), usage, try scope.get(exports, "UsageDoc")));
    return awaiting.continueWith(usageReady, engine, captured, state, pending, 0);
}
fn usageReady(engine: *Engine, state: c.JSValue, value: c.JSValue, rejected: bool, _: c_int) !c.JSValue {
    if (rejected) return engine.checked(c.JS_Throw(engine.context, c.JS_DupValue(engine.context, value)));
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    return vm.invoke(engine, try scope.get(state, "tx"), "appendEntry", &.{ try scope.get(state, "token"), try scope.get(state, "conversation"), try scope.get(state, "entry") });
}
