//! Running tool output keeps original UTF-16 chunks until byte slicing is needed.
//! Native TextDecoder supplies streaming bytes; all buffer algorithms are Zig.
const std = @import("std");
const engine_mod = @import("engine.zig");
const vm = @import("native_values.zig");
const js = @import("native_js_values.zig");
const window = @import("native_durable_output_limits.zig");
const c = engine_mod.c;
const Engine = engine_mod.Engine;
const Action = enum(c_int) { push, end, snapshot, chunkText };
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
    fn get(self: *Scope, value: c.JSValue, name: [:0]const u8) !c.JSValue {
        return self.own(try vm.get(self.engine, value, name));
    }
    fn invoke(self: *Scope, value: c.JSValue, name: [:0]const u8, args: []const c.JSValue) !c.JSValue {
        return self.own(try vm.invoke(self.engine, value, name, args));
    }
};
fn put(engine: *Engine, state: c.JSValue, key: [:0]const u8, value: c.JSValue) !void {
    try @import("native_tool_info.zig").putData(engine, state, key, c.JS_DupValue(engine.context, value));
}
fn numeric(engine: *Engine, state: c.JSValue, key: [:0]const u8) !f64 {
    const value = try vm.get(engine, state, key);
    defer engine.freeValue(value);
    var result: f64 = 0;
    if (c.JS_ToFloat64(engine.context, &result, value) < 0) return js.capture(engine);
    return result;
}
fn flag(engine: *Engine, state: c.JSValue, key: [:0]const u8) !bool {
    const value = try vm.get(engine, state, key);
    defer engine.freeValue(value);
    return c.JS_ToBool(engine.context, value) != 0;
}
fn setNumber(engine: *Engine, state: c.JSValue, key: [:0]const u8, value: f64) !void {
    try put(engine, state, key, c.JS_NewFloat64(engine.context, value));
}
pub fn create(engine: *Engine, limits: window.Limits, sanitize_pattern: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const state = try vm.object(engine);
    errdefer engine.freeValue(state);
    try setNumber(engine, state, "maxBytes", limits.maxBytes);
    try setNumber(engine, state, "maxLines", limits.maxLines);
    try put(engine, state, "tail", c.pi_js_bool(engine.context, @intFromBool(limits.retain == .tail)));
    try put(engine, state, "head", c.pi_js_bool(engine.context, @intFromBool(limits.retain == .head)));
    try @import("native_tool_info.zig").putData(engine, state, "chunks", try vm.array(engine));
    inline for (.{ "storedBytes", "storedNewlines", "totalBytes", "totalNewlines" }) |key| try setNumber(engine, state, key, 0);
    try put(engine, state, "endsWithNewline", c.pi_js_bool(engine.context, 1));
    try put(engine, state, "pattern", sanitize_pattern);
    const options = try scope.own(try vm.object(engine));
    try put(engine, options, "ignoreBOM", c.pi_js_bool(engine.context, 1));
    const constructor = try scope.own(try js.global(engine, "TextDecoder"));
    const encoding = try scope.own(try engine.checked(c.JS_NewString(engine.context, "utf-8")));
    var args = [_]c.JSValue{ encoding, options };
    try @import("native_tool_info.zig").putData(engine, state, "decoder", try engine.checked(c.JS_CallConstructor(engine.context, constructor, args.len, &args)));
    inline for (.{ Action.push, Action.end, Action.snapshot }) |action| {
        var captures = [_]c.JSValue{state};
        try @import("native_tool_info.zig").putData(engine, state, @tagName(action), try engine.checked(c.JS_NewCFunctionData2(engine.context, dispatch, "", if (action == .push) 2 else 0, @intFromEnum(action), captures.len, &captures)));
    }
    return state;
}
fn dispatch(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, raw_action: c_int, data: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = Engine.fromContext(context.?);
    return act(engine, data[0], @enumFromInt(raw_action), argv[0..@intCast(argc)]) catch |err| @import("native_durable.zig").reject(engine, err);
}
fn act(engine: *Engine, state: c.JSValue, action: Action, args: []const c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    if (action == .snapshot) return snapshot(engine, state);
    if (action == .chunkText) return vm.get(engine, if (args.len > 0) args[0] else c.pi_js_undefined(), "text");
    const decoder = try scope.get(state, "decoder");
    if (action == .end) {
        const text = try scope.invoke(decoder, "decode", &.{});
        _ = try accept(engine, state, text);
        return c.pi_js_undefined();
    }
    const chunk = if (args.len > 0) args[0] else c.pi_js_undefined();
    const skipped = if (args.len > 1) args[1] else c.pi_js_undefined();
    const is_string = c.JS_IsString(chunk);
    const empty = try scope.own(try engine.checked(c.JS_NewString(engine.context, "")));
    const pending = if (is_string or !c.JS_IsUndefined(skipped)) try scope.invoke(decoder, "decode", &.{}) else empty;
    var text = if (is_string) chunk else text: {
        const options = try scope.own(try vm.object(engine));
        try put(engine, options, "stream", c.pi_js_bool(engine.context, 1));
        break :text try scope.invoke(decoder, "decode", &.{ chunk, options });
    };
    const pending_empty = c.JS_IsStrictEqual(engine.context, pending, empty);
    const text_empty = c.JS_IsStrictEqual(engine.context, text, empty);
    const first = !try flag(engine, state, "started") and pending_empty and c.JS_IsUndefined(skipped);
    if (!pending_empty or !text_empty or !c.JS_IsUndefined(skipped)) try put(engine, state, "started", c.pi_js_bool(engine.context, 1));
    if (first and !is_string) {
        const bom = try scope.own(try engine.checked(c.JS_NewString(engine.context, "\xef\xbb\xbf")));
        const starts = try scope.invoke(text, "startsWith", &.{bom});
        if (c.JS_ToBool(engine.context, starts) != 0) text = try scope.invoke(text, "slice", &.{c.JS_NewInt32(engine.context, 1)});
    }
    if (c.JS_IsUndefined(skipped)) {
        const joined = try scope.own(try @import("native_utf16.zig").concat(engine, &.{ pending, text }));
        return c.pi_js_bool(engine.context, @intFromBool(try accept(engine, state, joined)));
    }
    if (!try flag(engine, state, "tail")) return @import("native_sdk.zig").sourceError(engine, "Skipped output requires tail retention");
    _ = try accept(engine, state, pending);
    const bytes = try scope.get(skipped, "bytes");
    if (!c.JS_IsStrictEqual(engine.context, bytes, c.JS_NewInt32(engine.context, 0))) {
        try setNumber(engine, state, "totalBytes", (try numeric(engine, state, "totalBytes")) + (try numeric(engine, skipped, "bytes")));
        try setNumber(engine, state, "totalNewlines", (try numeric(engine, state, "totalNewlines")) + (try numeric(engine, skipped, "newlines")));
        try put(engine, state, "endsWithNewline", try scope.get(skipped, "endsWithNewline"));
        try @import("native_tool_info.zig").putData(engine, state, "chunks", try vm.array(engine));
        try setNumber(engine, state, "storedBytes", 0);
        try setNumber(engine, state, "storedNewlines", 0);
    }
    _ = try accept(engine, state, text);
    return c.pi_js_bool(engine.context, 1);
}
fn accept(engine: *Engine, state: c.JSValue, text: c.JSValue) !bool {
    const bytes = try engine.toString(text);
    defer engine.gpa.free(bytes);
    if (bytes.len == 0) return false;
    const newlines = std.mem.count(u8, bytes, "\n");
    try setNumber(engine, state, "totalBytes", (try numeric(engine, state, "totalBytes")) + @as(f64, @floatFromInt(bytes.len)));
    try setNumber(engine, state, "totalNewlines", (try numeric(engine, state, "totalNewlines")) + @as(f64, @floatFromInt(newlines)));
    const newline = try engine.checked(c.JS_NewString(engine.context, "\n"));
    defer engine.freeValue(newline);
    const ends = try vm.invoke(engine, text, "endsWith", &.{newline});
    defer engine.freeValue(ends);
    try put(engine, state, "endsWithNewline", ends);
    if (try flag(engine, state, "full")) return true;
    const chunk = try vm.object(engine);
    defer engine.freeValue(chunk);
    try put(engine, chunk, "text", text);
    try setNumber(engine, chunk, "bytes", @floatFromInt(bytes.len));
    try setNumber(engine, chunk, "newlines", @floatFromInt(newlines));
    const chunks = try vm.get(engine, state, "chunks");
    defer engine.freeValue(chunks);
    try js.push(engine, chunks, chunk);
    try setNumber(engine, state, "storedBytes", (try numeric(engine, state, "storedBytes")) + @as(f64, @floatFromInt(bytes.len)));
    try setNumber(engine, state, "storedNewlines", (try numeric(engine, state, "storedNewlines")) + @as(f64, @floatFromInt(newlines)));
    const max_bytes = try numeric(engine, state, "maxBytes");
    const max_lines = try numeric(engine, state, "maxLines");
    if (try flag(engine, state, "head")) {
        try put(engine, state, "full", c.pi_js_bool(engine.context, @intFromBool((try numeric(engine, state, "storedBytes")) > max_bytes or (try numeric(engine, state, "storedNewlines")) >= max_lines)));
        return true;
    }
    while (try vm.length(engine, chunks) > 1) {
        const first = try engine.checked(c.JS_GetPropertyUint32(engine.context, chunks, 0));
        defer engine.freeValue(first);
        const bytes_after = (try numeric(engine, state, "storedBytes")) - (try numeric(engine, first, "bytes"));
        const lines_after = (try numeric(engine, state, "storedNewlines")) - (try numeric(engine, first, "newlines"));
        if (bytes_after <= max_bytes + 1 and lines_after <= max_lines + 1) break;
        const removed = try vm.invoke(engine, chunks, "shift", &.{});
        engine.freeValue(removed);
        try setNumber(engine, state, "storedBytes", bytes_after);
        try setNumber(engine, state, "storedNewlines", lines_after);
    }
    return true;
}
fn snapshot(engine: *Engine, state: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const chunks = try scope.get(state, "chunks");
    const length = try vm.length(engine, chunks);
    const stored = if (length == 1) stored: {
        const first = try scope.own(try engine.checked(c.JS_GetPropertyUint32(engine.context, chunks, 0)));
        break :stored try scope.get(first, "text");
    } else stored: {
        var captures = [_]c.JSValue{state};
        const mapper = try scope.own(try engine.checked(c.JS_NewCFunctionData2(engine.context, dispatch, "", 1, @intFromEnum(Action.chunkText), captures.len, &captures)));
        const texts = try scope.invoke(chunks, "map", &.{mapper});
        const empty = try scope.own(try engine.checked(c.JS_NewString(engine.context, "")));
        break :stored try scope.invoke(texts, "join", &.{empty});
    };
    const encoded = try engine.toString(stored);
    defer engine.gpa.free(encoded);
    try std.unicode.wtf8ToUtf8Lossy(encoded, encoded);
    const tail = try flag(engine, state, "tail");
    const limits: window.Limits = .{ .maxBytes = try numeric(engine, state, "maxBytes"), .maxLines = try numeric(engine, state, "maxLines"), .retain = if (try flag(engine, state, "head")) .head else if (tail) .tail else .other };
    const kept = try window.boundOutput(engine.gpa, encoded, limits);
    defer engine.gpa.free(kept.text);
    const kept_value = if (kept.droppedBytes == 0) stored else try scope.own(try engine.checked(c.JS_NewStringLen(engine.context, kept.text.ptr, kept.text.len)));
    const stored_lines = (try numeric(engine, state, "storedNewlines")) + @as(f64, @floatFromInt(@as(usize, @intFromBool(encoded.len != 0 and encoded[encoded.len - 1] != '\n'))));
    if (tail or length > 1) {
        const start = if (tail) window.tailMargin(encoded, limits) else 0;
        const text = if (start == 0) stored else try scope.own(try engine.checked(c.JS_NewStringLen(engine.context, encoded[start..].ptr, encoded.len - start)));
        const bytes = if (tail) @as(f64, @floatFromInt(encoded.len - start)) else try numeric(engine, state, "storedBytes");
        const next_chunks = try scope.own(try vm.array(engine));
        const empty = try scope.own(try engine.checked(c.JS_NewString(engine.context, "")));
        var newlines: usize = 0;
        if (!c.JS_IsStrictEqual(engine.context, text, empty)) {
            const raw = try engine.toString(text);
            defer engine.gpa.free(raw);
            newlines = std.mem.count(u8, raw, "\n");
            const chunk = try scope.own(try vm.object(engine));
            try put(engine, chunk, "text", text);
            try setNumber(engine, chunk, "bytes", bytes);
            try setNumber(engine, chunk, "newlines", @floatFromInt(newlines));
            try js.push(engine, next_chunks, chunk);
        }
        try put(engine, state, "chunks", next_chunks);
        try setNumber(engine, state, "storedBytes", bytes);
        try setNumber(engine, state, "storedNewlines", @floatFromInt(newlines));
    }
    const pattern = try scope.get(state, "pattern");
    const empty = try scope.own(try engine.checked(c.JS_NewString(engine.context, "")));
    const sanitized = try scope.invoke(kept_value, "replace", &.{ pattern, empty });
    const result = try vm.object(engine);
    errdefer engine.freeValue(result);
    try put(engine, result, "text", sanitized);
    try setNumber(engine, result, "droppedBytes", (try numeric(engine, state, "totalBytes")) - @as(f64, @floatFromInt(kept.bytes)));
    const total_lines = (try numeric(engine, state, "totalNewlines")) + @as(f64, @floatFromInt(@as(usize, @intFromBool(!try flag(engine, state, "endsWithNewline")))));
    try setNumber(engine, result, "droppedLines", total_lines - (stored_lines - @as(f64, @floatFromInt(kept.droppedLines))));
    return result;
}
