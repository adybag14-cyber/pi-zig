//! Native compaction response classification and transcript serialization.
const std = @import("std");
const engine_mod = @import("engine.zig");
const vm = @import("native_values.zig");
const js = @import("native_js_values.zig");
const utf16 = @import("native_utf16.zig");
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
fn equals(engine: *Engine, value: c.JSValue, text: [:0]const u8) !bool {
    const expected = try engine.checked(c.JS_NewString(engine.context, text));
    defer engine.freeValue(expected);
    return c.JS_IsStrictEqual(engine.context, value, expected);
}
fn selectedText(scope: *Scope, content: c.JSValue, kind: [:0]const u8, field: [:0]const u8, separator: []const u8) !c.JSValue {
    const values = try scope.own(try vm.array(scope.engine));
    for (0..try vm.length(scope.engine, content)) |index| {
        const item = try scope.own(try scope.engine.checked(c.JS_GetPropertyUint32(scope.engine.context, content, @intCast(index))));
        if (try equals(scope.engine, try scope.get(item, "type"), kind)) {
            const value = try scope.get(item, field);
            if (!c.JS_IsUndefined(value)) try js.push(scope.engine, values, value);
        }
    }
    return scope.invoke(values, "join", &.{try scope.text(separator)});
}
fn hasCall(scope: *Scope, content: c.JSValue) !bool {
    for (0..try vm.length(scope.engine, content)) |index| {
        const item = try scope.own(try scope.engine.checked(c.JS_GetPropertyUint32(scope.engine.context, content, @intCast(index))));
        if (try equals(scope.engine, try scope.get(item, "type"), "toolCall")) return true;
    }
    return false;
}
pub fn summaryText(engine: *Engine, message: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    if (!try equals(engine, try scope.get(message, "stopReason"), "stop")) return c.pi_js_undefined();
    const content = try scope.get(message, "content");
    if (try hasCall(&scope, content)) return c.pi_js_undefined();
    const text = try selectedText(&scope, content, "text", "text", "\n");
    const trimmed = try scope.invoke(text, "trim", &.{});
    const empty = try scope.text("");
    return if (c.JS_IsStrictEqual(engine.context, trimmed, empty)) c.pi_js_undefined() else c.JS_DupValue(engine.context, trimmed);
}
pub fn summaryFailure(engine: *Engine, message: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const reason = try scope.get(message, "stopReason");
    if (try equals(engine, reason, "error") or try equals(engine, reason, "aborted")) {
        const error_message = try scope.get(message, "errorMessage");
        return utf16.concat(engine, &.{ try scope.text("Summarization failed: "), if (c.JS_IsUndefined(error_message) or c.JS_IsNull(error_message)) reason else error_message });
    }
    const text: []const u8 = if (try equals(engine, reason, "length")) "Summarization hit the token limit; the summary is incomplete" else if (try hasCall(&scope, try scope.get(message, "content"))) "Summarization attempted to call a tool" else "Summarization produced no text";
    return engine.checked(c.JS_NewStringLen(engine.context, text.ptr, text.len));
}
fn contentText(scope: *Scope, content: c.JSValue) !c.JSValue {
    return if (c.JS_IsString(content)) c.JS_DupValue(scope.engine.context, content) else c.JS_DupValue(scope.engine.context, try selectedText(scope, content, "text", "text", "\n"));
}
fn appendLabeled(scope: *Scope, parts: c.JSValue, label: []const u8, text: c.JSValue) !void {
    const length = try scope.get(text, "length");
    var count: i64 = 0;
    if (c.JS_ToInt64(scope.engine.context, &count, length) < 0) return js.capture(scope.engine);
    if (count == 0) return;
    const part = try scope.own(try utf16.concat(scope.engine, &.{ try scope.text(label), text }));
    try js.push(scope.engine, parts, part);
}
pub fn serializeConversation(engine: *Engine, messages: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const parts = try scope.own(try vm.array(engine));
    for (0..try vm.length(engine, messages)) |index| {
        const message = try scope.own(try engine.checked(c.JS_GetPropertyUint32(engine.context, messages, @intCast(index))));
        const role = try scope.get(message, "role");
        const content = try scope.get(message, "content");
        if (try equals(engine, role, "user")) {
            try appendLabeled(&scope, parts, "[User]: ", try scope.own(try contentText(&scope, content)));
        } else if (try equals(engine, role, "assistant")) {
            try appendLabeled(&scope, parts, "[Assistant thinking]: ", try selectedText(&scope, content, "thinking", "thinking", "\n"));
            try appendLabeled(&scope, parts, "[Assistant]: ", try selectedText(&scope, content, "text", "text", "\n"));
            const calls = try scope.own(try vm.array(engine));
            for (0..try vm.length(engine, content)) |position| {
                const block = try scope.own(try engine.checked(c.JS_GetPropertyUint32(engine.context, content, @intCast(position))));
                if (!try equals(engine, try scope.get(block, "type"), "toolCall")) continue;
                const object = try scope.own(try js.global(engine, "Object"));
                const entries = try scope.invoke(object, "entries", &.{try scope.get(block, "arguments")});
                const arguments = try scope.own(try vm.array(engine));
                const json_object = try scope.own(try js.global(engine, "JSON"));
                for (0..try vm.length(engine, entries)) |argument| {
                    const pair = try scope.own(try engine.checked(c.JS_GetPropertyUint32(engine.context, entries, @intCast(argument))));
                    const key = try scope.own(try engine.checked(c.JS_GetPropertyUint32(engine.context, pair, 0)));
                    const value = try scope.own(try engine.checked(c.JS_GetPropertyUint32(engine.context, pair, 1)));
                    const serialized = try scope.invoke(json_object, "stringify", &.{value});
                    const argument_text = try scope.own(try utf16.concat(engine, &.{ key, try scope.text("="), serialized }));
                    try js.push(engine, arguments, argument_text);
                }
                const joined = try scope.invoke(arguments, "join", &.{try scope.text(", ")});
                const call = try scope.own(try utf16.concat(engine, &.{ try scope.get(block, "name"), try scope.text("("), joined, try scope.text(")") }));
                try js.push(engine, calls, call);
            }
            try appendLabeled(&scope, parts, "[Assistant tool calls]: ", try scope.invoke(calls, "join", &.{try scope.text("; ")}));
        } else if (try equals(engine, role, "toolResult")) {
            var text = try scope.own(try contentText(&scope, content));
            const units = try utf16.unitsAlloc(engine, text);
            defer engine.gpa.free(units);
            if (units.len > 2000) {
                const prefix = try scope.own(try utf16.string(engine, units[0..2000]));
                const suffix = try std.fmt.allocPrint(engine.gpa, "\n\n[... {d} more characters truncated]", .{units.len - 2000});
                defer engine.gpa.free(suffix);
                text = try scope.own(try utf16.concat(engine, &.{ prefix, try scope.text(suffix) }));
            }
            try appendLabeled(&scope, parts, "[Tool result]: ", text);
        }
    }
    return c.JS_DupValue(engine.context, try scope.invoke(parts, "join", &.{try scope.text("\n\n")}));
}
pub fn summaryPrompt(engine: *Engine, messages: c.JSValue, instructions: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const transcript = try scope.own(try serializeConversation(engine, messages));
    const focus = if (c.JS_IsUndefined(instructions)) try scope.text("") else try scope.own(try utf16.concat(engine, &.{ try scope.text("\n\nAdditional focus: "), instructions }));
    return utf16.concat(engine, &.{ try scope.text("<conversation>\n"), transcript, try scope.text("\n</conversation>\n\n"), try scope.text(@embedFile("compaction_summary_prompt.txt")), focus });
}
fn numeric(scope: *Scope, value: c.JSValue) !f64 {
    var result: f64 = 0;
    if (c.JS_ToFloat64(scope.engine.context, &result, value) < 0) return js.capture(scope.engine);
    return result;
}
fn stringLength(scope: *Scope, value: c.JSValue) !f64 {
    return numeric(scope, try scope.get(value, "length"));
}
fn stringify(scope: *Scope, value: c.JSValue) !c.JSValue {
    const object = try scope.own(try js.global(scope.engine, "JSON"));
    const result = scope.invoke(object, "stringify", &.{value}) catch |err| {
        if (err != error.JavaScriptException) return err;
        return scope.text("[unserializable]");
    };
    return if (c.JS_IsUndefined(result)) scope.text("undefined") else result;
}
fn contentChars(scope: *Scope, content: c.JSValue) !f64 {
    if (c.JS_IsString(content)) return stringLength(scope, content);
    var chars: f64 = 0;
    for (0..try vm.length(scope.engine, content)) |index| {
        const block = try scope.own(try scope.engine.checked(c.JS_GetPropertyUint32(scope.engine.context, content, @intCast(index))));
        chars += if (try equals(scope.engine, try scope.get(block, "type"), "text")) try stringLength(scope, try scope.get(block, "text")) else 4800;
    }
    return chars;
}
pub fn estimateMessageTokens(engine: *Engine, message: c.JSValue) !f64 {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const role = try scope.get(message, "role");
    const content = try scope.get(message, "content");
    if (try equals(engine, role, "user") or try equals(engine, role, "toolResult")) return @ceil((try contentChars(&scope, content)) / 3.5);
    if (try equals(engine, role, "system")) {
        var chars = try contentChars(&scope, content);
        var result = @ceil(chars / 3.5);
        inline for (.{ "toolsAdded", "toolsRemoved" }) |key| {
            const tools = try scope.get(message, key);
            if (!c.JS_IsUndefined(tools) and !c.JS_IsNull(tools) and try vm.length(engine, tools) != 0) {
                chars = try stringLength(&scope, try stringify(&scope, tools));
                result += @ceil(chars / 3.5);
            }
        }
        return result;
    }
    var chars: f64 = 0;
    for (0..try vm.length(engine, content)) |index| {
        const block = try scope.own(try engine.checked(c.JS_GetPropertyUint32(engine.context, content, @intCast(index))));
        const kind = try scope.get(block, "type");
        if (try equals(engine, kind, "text")) chars += try stringLength(&scope, try scope.get(block, "text")) else if (try equals(engine, kind, "thinking")) chars += try stringLength(&scope, try scope.get(block, "thinking")) else {
            chars += try stringLength(&scope, try scope.get(block, "name"));
            chars += try stringLength(&scope, try stringify(&scope, try scope.get(block, "arguments")));
        }
    }
    return @ceil(chars / 3.5);
}
pub fn calculateContextTokens(engine: *Engine, usage: c.JSValue) !f64 {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const total = try scope.get(usage, "totalTokens");
    if (c.JS_ToBool(engine.context, total) != 0) return numeric(&scope, total);
    var result: f64 = 0;
    inline for (.{ "input", "output", "cacheRead", "cacheWrite" }) |key| result += try numeric(&scope, try scope.get(usage, key));
    return result;
}
fn arrayItem(scope: *Scope, array: c.JSValue, index: usize) !c.JSValue {
    return scope.own(try scope.engine.checked(c.JS_GetPropertyUint32(scope.engine.context, array, @intCast(index))));
}
fn isCandidate(scope: *Scope, contributions: c.JSValue, index: usize) !bool {
    const current = try arrayItem(scope, contributions, index);
    const first = try arrayItem(scope, current, 0);
    if (c.JS_IsUndefined(first)) return false;
    const role = try scope.get(first, "role");
    if (try equals(scope.engine, role, "assistant")) return true;
    if (!try equals(scope.engine, role, "user")) return false;
    const calls = try scope.own(try vm.array(scope.engine));
    var before = index;
    outer: while (before > 0) {
        before -= 1;
        const contribution = try arrayItem(scope, contributions, before);
        var position = try vm.length(scope.engine, contribution);
        while (position > 0) {
            position -= 1;
            const message = try arrayItem(scope, contribution, position);
            if (!try equals(scope.engine, try scope.get(message, "role"), "assistant")) continue;
            const content = try scope.get(message, "content");
            for (0..try vm.length(scope.engine, content)) |block_index| {
                const block = try arrayItem(scope, content, block_index);
                if (try equals(scope.engine, try scope.get(block, "type"), "toolCall")) try js.push(scope.engine, calls, try scope.get(block, "id"));
            }
            break :outer;
        }
    }
    if (try vm.length(scope.engine, calls) == 0) return true;
    for (index..try vm.length(scope.engine, contributions)) |after| {
        const contribution = try arrayItem(scope, contributions, after);
        for (0..try vm.length(scope.engine, contribution)) |position| {
            const message = try arrayItem(scope, contribution, position);
            const next_role = try scope.get(message, "role");
            if (try equals(scope.engine, next_role, "assistant") and (after > index or position > 0)) return true;
            if (try equals(scope.engine, next_role, "toolResult")) {
                const found = try scope.invoke(calls, "includes", &.{try scope.get(message, "toolCallId")});
                if (c.JS_ToBool(scope.engine.context, found) != 0) return false;
            }
        }
    }
    return true;
}
pub fn selectCut(engine: *Engine, view: c.JSValue, keep_recent_tokens: f64) !?usize {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const contributions = try scope.get(view, "contributions");
    const start: usize = if (c.JS_IsUndefined(try scope.get(view, "head"))) 0 else 1;
    const length = try vm.length(engine, contributions);
    var candidates: std.ArrayList(usize) = .empty;
    defer candidates.deinit(engine.gpa);
    if (start >= length) return null;
    for (start..length) |index| if (try isCandidate(&scope, contributions, index)) {
        try candidates.append(engine.gpa, index);
    };
    var kept: f64 = 0;
    var cut: ?usize = null;
    var index = length;
    while (index > start) {
        index -= 1;
        const contribution = try arrayItem(&scope, contributions, index);
        for (0..try vm.length(engine, contribution)) |position| kept += try estimateMessageTokens(engine, try arrayItem(&scope, contribution, position));
        if (kept < keep_recent_tokens) continue;
        for (candidates.items) |candidate| if (candidate >= index) {
            cut = candidate;
            break;
        };
        if (cut == null and candidates.items.len != 0) cut = candidates.items[candidates.items.len - 1];
        break;
    }
    const selected = cut orelse return null;
    for (start..selected) |before| if (try vm.length(engine, try arrayItem(&scope, contributions, before)) > 0) return selected;
    return null;
}
pub fn estimateContext(engine: *Engine, view: c.JSValue, extra: c.JSValue) !f64 {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const entries = try scope.get(view, "entries");
    const contributions = try scope.get(view, "contributions");
    const messages = try scope.get(view, "messages");
    const head = try scope.get(view, "head");
    const after = if (c.JS_IsUndefined(head) or c.JS_IsNull(head)) -std.math.inf(f64) else try numeric(&scope, try scope.get(head, "id"));
    var measured = c.pi_js_undefined();
    var cursor = try vm.length(engine, entries);
    while (cursor > 0 and c.JS_IsUndefined(measured)) {
        cursor -= 1;
        const entry = try arrayItem(&scope, entries, cursor);
        if (try numeric(&scope, try scope.get(entry, "id")) <= after) continue;
        const contribution = try arrayItem(&scope, contributions, cursor);
        var position = try vm.length(engine, contribution);
        while (position > 0) {
            position -= 1;
            const message = try arrayItem(&scope, contribution, position);
            if (try equals(engine, try scope.get(message, "role"), "assistant") and try calculateContextTokens(engine, try scope.get(message, "usage")) > 0) {
                measured = message;
                break;
            }
        }
    }
    var from: usize = 0;
    var tokens: f64 = 0;
    if (!c.JS_IsUndefined(measured)) {
        tokens = try calculateContextTokens(engine, try scope.get(measured, "usage"));
        const position = try scope.invoke(messages, "lastIndexOf", &.{measured});
        const start = try numeric(&scope, position);
        from = @intFromFloat(start + 1);
    }
    for (from..try vm.length(engine, messages)) |index| tokens += try estimateMessageTokens(engine, try arrayItem(&scope, messages, index));
    for (0..try vm.length(engine, extra)) |index| tokens += try estimateMessageTokens(engine, try arrayItem(&scope, extra, index));
    return tokens;
}
pub fn summarizedMessages(engine: *Engine, view: c.JSValue, cut: usize) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const contributions = try scope.get(view, "contributions");
    const prefix = try scope.invoke(contributions, "slice", &.{ c.JS_NewInt32(engine.context, 0), c.JS_NewFloat64(engine.context, @floatFromInt(cut)) });
    const messages = try scope.invoke(prefix, "flat", &.{});
    const ordered = try vm.array(engine);
    errdefer engine.freeValue(ordered);
    const length = try vm.length(engine, messages);
    for (0..length) |index| {
        const message = try arrayItem(&scope, messages, index);
        const role = try scope.get(message, "role");
        if (try equals(engine, role, "toolResult")) continue;
        try js.push(engine, ordered, message);
        if (!try equals(engine, role, "assistant")) continue;
        const content = try scope.get(message, "content");
        for (0..try vm.length(engine, content)) |position| {
            const call = try arrayItem(&scope, content, position);
            if (!try equals(engine, try scope.get(call, "type"), "toolCall")) continue;
            const id = try scope.get(call, "id");
            var found = c.pi_js_undefined();
            for (index + 1..length) |after| {
                const candidate = try arrayItem(&scope, messages, after);
                const next_role = try scope.get(candidate, "role");
                if (try equals(engine, next_role, "assistant")) break;
                if (try equals(engine, next_role, "toolResult") and c.JS_IsStrictEqual(engine.context, try scope.get(candidate, "toolCallId"), id)) {
                    found = candidate;
                    break;
                }
            }
            if (c.JS_IsUndefined(found)) {
                found = try scope.own(try vm.object(engine));
                const missing_content = try scope.own(try vm.array(engine));
                const block = try scope.own(try vm.object(engine));
                try @import("native_tool_info.zig").putData(engine, block, "type", c.JS_DupValue(engine.context, try scope.text("text")));
                try @import("native_tool_info.zig").putData(engine, block, "text", c.JS_DupValue(engine.context, try scope.text("Tool result unavailable: history ends before this call completed.")));
                try js.push(engine, missing_content, block);
                inline for (.{ .{ "role", try scope.text("toolResult") }, .{ "toolCallId", id }, .{ "toolName", try scope.get(call, "name") }, .{ "content", missing_content }, .{ "isError", c.pi_js_bool(engine.context, 1) }, .{ "timestamp", try scope.get(message, "timestamp") } }) |field| try @import("native_tool_info.zig").putData(engine, found, field[0], c.JS_DupValue(engine.context, field[1]));
                const details = try scope.own(try vm.object(engine));
                try @import("native_tool_info.zig").putData(engine, details, "reason", c.JS_DupValue(engine.context, try scope.text("missing_result")));
                try @import("native_tool_info.zig").putData(engine, found, "details", c.JS_DupValue(engine.context, details));
            }
            try js.push(engine, ordered, found);
        }
    }
    return ordered;
}
