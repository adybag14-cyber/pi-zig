//! Translate committed view operations into assistant and tool progress events.
const engine_mod = @import("engine.zig");
const vm = @import("native_values.zig");
const js = @import("native_js_values.zig");
const Scope = @import("native_durable_view_mount.zig").Scope;
const c = engine_mod.c;
const Engine = engine_mod.Engine;
fn put(engine: *Engine, object: c.JSValue, key: [:0]const u8, value: c.JSValue) !void {
    try @import("native_tool_info.zig").putData(engine, object, key, c.JS_DupValue(engine.context, value));
}
fn same(engine: *Engine, left: c.JSValue, right: c.JSValue) bool {
    return c.JS_IsStrictEqual(engine.context, left, right);
}
fn is(scope: *Scope, value: c.JSValue, bytes: []const u8) !bool {
    return same(scope.engine, value, try scope.text(bytes));
}
fn startsWith(scope: *Scope, path: c.JSValue, prefix: c.JSValue) !bool {
    const length = try vm.length(scope.engine, prefix);
    if (length > try vm.length(scope.engine, path)) return false;
    for (0..length) |index| if (!same(scope.engine, try scope.item(path, index), try scope.item(prefix, index))) return false;
    return true;
}
fn event(scope: *Scope, kind: []const u8) !c.JSValue {
    const result = try scope.own(try vm.object(scope.engine));
    try put(scope.engine, result, "type", try scope.text(kind));
    return result;
}
fn wholeMessage(scope: *Scope, message: c.JSValue) !c.JSValue {
    const result = try event(scope, "message");
    try put(scope.engine, result, "message", message);
    return scope.array(&.{result});
}
pub fn messageChanges(engine: *Engine, operations: c.JSValue, message: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const result = try scope.array(&.{});
    const whole = try scope.own(try js.builtin(engine, "Set", &.{}));
    const prefix = try scope.array(&.{ try scope.text("docs"), try scope.text("pi.live"), try scope.text("generation"), try scope.text("message") });
    for (0..try vm.length(engine, operations)) |index| {
        const op = try scope.item(operations, index);
        const path = try scope.item(op, 1);
        if (!try startsWith(&scope, path, prefix)) {
            if (try startsWith(&scope, prefix, path)) return c.JS_DupValue(engine.context, try wholeMessage(&scope, message));
            continue;
        }
        const rest = try scope.invoke(path, "slice", &.{c.JS_NewInt32(engine.context, 4)});
        const first = try scope.item(rest, 0);
        if (try is(&scope, first, "usage")) continue;
        if (!try is(&scope, first, "content")) return c.JS_DupValue(engine.context, try wholeMessage(&scope, message));
        const kind = try scope.item(op, 0);
        const length = try vm.length(engine, rest);
        if (length == 1) {
            if (!try is(&scope, kind, "p") or !same(engine, try scope.item(op, 3), c.JS_NewInt32(engine.context, 0))) return c.JS_DupValue(engine.context, try wholeMessage(&scope, message));
            const blocks = try scope.item(op, 4);
            var start: f64 = 0;
            if (c.JS_ToFloat64(engine.context, &start, try scope.item(op, 2)) < 0) return js.capture(engine);
            for (0..try vm.length(engine, blocks)) |offset| {
                const block = try scope.item(blocks, offset);
                const block_kind = try scope.get(block, "type");
                const next = try event(&scope, if (try is(&scope, block_kind, "text")) "text_start" else if (try is(&scope, block_kind, "thinking")) "thinking_start" else "toolcall_start");
                try put(engine, next, "contentIndex", c.JS_NewFloat64(engine.context, start + @as(f64, @floatFromInt(offset))));
                try put(engine, next, "block", block);
                try js.push(engine, result, next);
            }
            continue;
        }
        const content_index = try scope.item(rest, 1);
        if (c.JS_ToBool(engine.context, try scope.invoke(whole, "has", &.{content_index})) != 0) continue;
        const field = try scope.item(rest, 2);
        const append = try is(&scope, kind, "a");
        const text = length == 3 and (try is(&scope, field, "text") or try is(&scope, field, "thinking"));
        const arguments = try is(&scope, field, "arguments");
        const next = try event(&scope, if (append and text) (if (try is(&scope, field, "text")) "text_delta" else "thinking_delta") else if (append and arguments) "toolcall_delta" else "block");
        try put(engine, next, "contentIndex", content_index);
        if (append and (text or arguments)) {
            try put(engine, next, "delta", try scope.item(op, 2));
            if (arguments) try put(engine, next, "path", try scope.invoke(rest, "slice", &.{c.JS_NewInt32(engine.context, 3)}));
        } else {
            _ = try scope.invoke(whole, "add", &.{content_index});
            try put(engine, next, "block", try scope.own(try js.getKey(engine, try scope.get(message, "content"), content_index)));
        }
        try js.push(engine, result, next);
    }
    return c.JS_DupValue(engine.context, result);
}
pub fn callOf(engine: *Engine, slot: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const result = try vm.object(engine);
    errdefer engine.freeValue(result);
    try put(engine, result, "toolCallId", try scope.get(slot, "callId"));
    try put(engine, result, "toolName", try scope.get(slot, "name"));
    const task = try scope.get(slot, "taskId");
    if (!c.JS_IsUndefined(task)) try put(engine, result, "taskId", task);
    const key = try scope.text("parentCallId");
    const atom = c.JS_ValueToAtom(engine.context, key);
    defer c.JS_FreeAtom(engine.context, atom);
    const has = c.JS_HasProperty(engine.context, slot, atom);
    if (has < 0) return js.capture(engine);
    if (has != 0) {
        try put(engine, result, "parentToolCallId", try scope.get(slot, "parentCallId"));
        try put(engine, result, "parentTaskId", try scope.get(slot, "parentTaskId"));
    }
    return result;
}
pub fn toolUpdate(engine: *Engine, operations: c.JSValue, at: c.JSValue, slot: c.JSValue, previous: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const prefix = try scope.array(&.{ try scope.text("docs"), try scope.text("pi.live") });
    const path = try scope.invoke(prefix, "concat", &.{at});
    try js.push(engine, path, try scope.text("output"));
    var trim: f64 = 0;
    var append = try scope.text("");
    var set = false;
    for (0..try vm.length(engine, operations)) |index| {
        const op = try scope.item(operations, index);
        if (!try startsWith(&scope, try scope.item(op, 1), path)) continue;
        const kind = try scope.item(op, 0);
        if (try is(&scope, kind, "t")) {
            var amount: f64 = 0;
            if (c.JS_ToFloat64(engine.context, &amount, try scope.item(op, 2)) < 0) return js.capture(engine);
            trim += amount;
        } else if (try is(&scope, kind, "a")) {
            append = try scope.invoke(append, "concat", &.{try scope.item(op, 2)});
        } else set = true;
    }
    const result = try scope.own(try vm.object(engine));
    const current_output = try scope.get(slot, "output");
    const prior_output = try scope.get(previous, "output");
    const has_append = try vm.length(engine, append) > 0;
    if (set or (!same(engine, current_output, prior_output) and trim == 0 and !has_append)) {
        const output = try scope.own(try vm.object(engine));
        try put(engine, output, "set", if (c.JS_IsNull(current_output) or c.JS_IsUndefined(current_output)) try scope.text("") else current_output);
        try put(engine, result, "output", output);
    } else if (trim > 0 or has_append) {
        const output = try scope.own(try vm.object(engine));
        if (trim > 0) try put(engine, output, "trimStart", c.JS_NewFloat64(engine.context, trim));
        if (has_append) try put(engine, output, "append", append);
        try put(engine, result, "output", output);
    }
    inline for (.{ "details", "diagnostics" }) |key| {
        const current = try scope.get(slot, key);
        if (!same(engine, current, try scope.get(previous, key))) try put(engine, result, key, if (c.JS_IsNull(current) or c.JS_IsUndefined(current)) (if (comptime @import("std").mem.eql(u8, key, "details")) c.pi_js_null() else try scope.array(&.{})) else current);
    }
    const keys = try scope.invoke(try scope.own(try js.global(engine, "Object")), "keys", &.{result});
    return if (try vm.length(engine, keys) == 0) c.pi_js_undefined() else c.JS_DupValue(engine.context, result);
}
