//! Bound model-facing text while retaining every non-text item and its identity.
const std = @import("std");
const engine_mod = @import("engine.zig");
const vm = @import("native_values.zig");
const js = @import("native_js_values.zig");
const calls = @import("native_durable_tool_call.zig");
const window = @import("native_durable_output_limits.zig");
const c = engine_mod.c;
const Engine = engine_mod.Engine;
pub const Bounded = struct {
    content: c.JSValue,
    dropped_bytes: usize,
    dropped_lines: u64,
    pub fn deinit(self: *Bounded, engine: *Engine) void {
        engine.freeValue(self.content);
    }
};
pub fn content(engine: *Engine, supplied: c.JSValue, limits: window.Limits, iterator_symbol: c.JSValue) !Bounded {
    const predicate = try engine.checked(c.pi_js_function_magic(engine.context, textField, "", 1, 0));
    defer engine.freeValue(predicate);
    const texts = try vm.invoke(engine, supplied, "filter", &.{predicate});
    defer engine.freeValue(texts);
    const mapper = try engine.checked(c.pi_js_function_magic(engine.context, textField, "", 1, 1));
    defer engine.freeValue(mapper);
    const values = try vm.invoke(engine, texts, "map", &.{mapper});
    defer engine.freeValue(values);
    const separator = try engine.checked(c.JS_NewString(engine.context, ""));
    defer engine.freeValue(separator);
    const joined = try vm.invoke(engine, values, "join", &.{separator});
    defer engine.freeValue(joined);
    const text = try engine.toString(joined);
    defer engine.gpa.free(text);
    // Source's TextEncoder replaces lone UTF-16 surrogates before slicing.
    // With no truncation, return the original items and their original strings.
    try std.unicode.wtf8ToUtf8Lossy(text, text);
    const bounded = try window.boundOutput(engine.gpa, text, limits);
    defer engine.gpa.free(bounded.text);
    if (bounded.droppedBytes == 0) return .{ .content = c.JS_DupValue(engine.context, supplied), .dropped_bytes = 0, .dropped_lines = 0 };
    const keep = if (limits.retain == .head) try engine.checked(c.JS_GetPropertyUint32(engine.context, texts, 0)) else try vm.invoke(engine, texts, "at", &.{c.JS_NewInt32(engine.context, -1)});
    defer engine.freeValue(keep);
    const result = try vm.array(engine);
    errdefer engine.freeValue(result);
    var iterator = try js.Iterator.init(engine, supplied, iterator_symbol);
    defer iterator.deinit();
    errdefer iterator.closePreserving();
    while (try iterator.next()) |item| {
        defer engine.freeValue(item);
        const kind = try vm.get(engine, item, "type");
        defer engine.freeValue(kind);
        if (!try calls.equalsString(engine, kind, "text")) {
            try js.push(engine, result, item);
        } else if (c.JS_IsStrictEqual(engine.context, item, keep)) {
            const replacement = try js.spread(engine, item);
            defer engine.freeValue(replacement);
            try @import("native_tool_info.zig").putData(engine, replacement, "text", try engine.checked(c.JS_NewStringLen(engine.context, bounded.text.ptr, bounded.text.len)));
            try js.push(engine, result, replacement);
        }
    }
    return .{ .content = result, .dropped_bytes = bounded.droppedBytes, .dropped_lines = bounded.droppedLines };
}
fn textField(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, mode: c_int) callconv(.c) c.JSValue {
    const engine = Engine.fromContext(context.?);
    const item = if (argc > 0) argv[0] else c.pi_js_undefined();
    if (mode == 1) return vm.get(engine, item, "text") catch |err| @import("native_durable.zig").reject(engine, err);
    const kind = vm.get(engine, item, "type") catch |err| return @import("native_durable.zig").reject(engine, err);
    defer engine.freeValue(kind);
    const matches = calls.equalsString(engine, kind, "text") catch |err| return @import("native_durable.zig").reject(engine, err);
    return c.pi_js_bool(engine.context, @intFromBool(matches));
}
