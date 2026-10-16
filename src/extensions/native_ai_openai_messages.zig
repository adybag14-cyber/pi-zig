//! Actual OpenAI-completions transcript-to-request message conversion.
const v = @import("native_ai_provider_values.zig");
const Scope = v.Scope;
const c = v.c;
const tools = @import("native_ai_openai_tools.zig");
const Kind = enum { text, thinking, tool, image, nonempty_text, nonempty_thinking, user_nonempty, user_part, text_part, text_value, thinking_value, sanitized_thinking, normalize_id, signed, legacy, defined, valid_detail, tool_call };
fn function(scope: *Scope, comptime kind: Kind, roots: []const c.JSValue) !c.JSValue {
    const Adapter = struct {
        fn call(engine: *v.em.Engine, _: c.JSValue, args: []const c.JSValue, data: []const c.JSValue) !c.JSValue {
            var row: Scope = .{ .engine = engine };
            defer row.deinit();
            return callback(&row, kind, if (args.len > 0) args[0] else c.pi_js_undefined(), data);
        }
    };
    return scope.own(try @import("native_node_function.zig").createArrow(scope.engine, "", 1, Adapter.call, roots));
}
fn predicate(scope: *Scope, result: bool) c.JSValue {
    return c.pi_js_bool(scope.engine.context, @intFromBool(result));
}
fn callback(scope: *Scope, kind: Kind, value: c.JSValue, roots: []const c.JSValue) !c.JSValue {
    const engine = scope.engine;
    switch (kind) {
        .text, .thinking, .tool, .image => return predicate(scope, try v.eq(scope, try scope.get(value, "type"), if (kind == .text) "text" else if (kind == .thinking) "thinking" else if (kind == .tool) "toolCall" else "image")),
        .nonempty_text, .nonempty_thinking => return predicate(scope, try v.length(scope, try scope.invoke(try scope.get(value, if (kind == .nonempty_text) "text" else "thinking"), "trim", &.{})) > 0),
        .user_nonempty => return predicate(scope, !try v.eq(scope, try scope.get(value, "type"), "text") or try v.length(scope, try scope.get(value, "text")) > 0),
        .user_part => return c.JS_DupValue(engine.context, if (try v.eq(scope, try scope.get(value, "type"), "text")) try textPart(scope, try v.sanitize(scope, try scope.get(value, "text"))) else try imagePart(scope, value)),
        .text_part => return c.JS_DupValue(engine.context, try textPart(scope, try v.sanitize(scope, try scope.get(value, "text")))),
        .text_value => return v.js.get(engine, value, "text"),
        .thinking_value => return v.js.get(engine, value, "thinking"),
        .sanitized_thinking => return c.JS_DupValue(engine.context, try v.sanitize(scope, try scope.get(value, "thinking"))),
        .normalize_id => return normalizeId(scope, value, roots[0]),
        .signed => return parseDetails(scope, try scope.get(value, "thinkingSignature"), false),
        .legacy => return parseDetails(scope, try scope.get(value, "thoughtSignature"), true),
        .defined => return predicate(scope, !c.JS_IsUndefined(value)),
        .valid_detail => return predicate(scope, try @import("native_ai_openai_decode.zig").validDetail(scope, value)),
        .tool_call => {
            const custom = if (v.nullish(roots[0])) c.pi_js_undefined() else try scope.invoke(roots[0], "get", &.{try scope.get(value, "name")});
            const result = try scope.object();
            try scope.put(result, "id", try scope.get(value, "id"));
            const body = try scope.object();
            if (!c.JS_IsUndefined(custom)) {
                try scope.put(result, "type", try scope.text("custom"));
                try scope.put(body, "name", try scope.get(value, "name"));
                const input = try scope.own(try v.js.getKey(engine, try scope.get(value, "arguments"), custom));
                if (!c.JS_IsString(input)) return v.errorText(scope, try scope.concat(try scope.concat(try scope.concat(try scope.text("Grammar tool call \""), try scope.stringify(try scope.get(value, "name"))), try scope.text("\" requires argument \"")), try scope.concat(try scope.stringify(custom), try scope.text("\" to be a string."))));
                try scope.put(body, "input", try v.sanitize(scope, input));
                try scope.put(result, "custom", body);
            } else {
                try scope.put(result, "type", try scope.text("function"));
                try scope.put(body, "name", try scope.get(value, "name"));
                try scope.put(body, "arguments", try scope.invoke(try scope.global("JSON"), "stringify", &.{try scope.get(value, "arguments")}));
                try scope.put(result, "function", body);
            }
            return c.JS_DupValue(engine.context, result);
        },
    }
}
fn textPart(scope: *Scope, text: c.JSValue) !c.JSValue {
    const result = try scope.object();
    try scope.put(result, "type", try scope.text("text"));
    try scope.put(result, "text", text);
    return result;
}
fn imagePart(scope: *Scope, image: c.JSValue) !c.JSValue {
    const result = try scope.object();
    try scope.put(result, "type", try scope.text("image_url"));
    const url = try scope.object();
    var text = try scope.concat(try scope.text("data:"), try scope.stringify(try scope.get(image, "mimeType")));
    text = try scope.concat(text, try scope.text(";base64,"));
    try scope.put(url, "url", try scope.concat(text, try scope.stringify(try scope.get(image, "data"))));
    try scope.put(result, "image_url", url);
    return result;
}
fn parseDetails(scope: *Scope, signature: c.JSValue, legacy: bool) !c.JSValue {
    if (!scope.truthy(signature)) return c.pi_js_undefined();
    const generation = scope.engine.native_allocation_generation;
    return detailBody(scope, signature, legacy) catch |err| {
        try @import("native_ai_partial_json.zig").discard(scope.engine, err, generation);
        return c.pi_js_undefined();
    };
}
fn detailBody(scope: *Scope, signature: c.JSValue, legacy: bool) !c.JSValue {
    const parsed = try scope.invoke(try scope.global("JSON"), "parse", &.{signature});
    if (legacy) {
        if (try @import("native_ai_openai_decode.zig").validDetail(scope, parsed) and try v.eq(scope, try scope.get(parsed, "type"), "reasoning.encrypted") and c.JS_IsString(try scope.get(parsed, "id")) and try v.length(scope, try scope.get(parsed, "id")) > 0 and try v.length(scope, try scope.get(parsed, "data")) > 0) return c.JS_DupValue(scope.engine.context, parsed);
    } else if (try v.array(scope, parsed) and try v.length(scope, parsed) > 0 and scope.truthy(try scope.invoke(parsed, "every", &.{try function(scope, .valid_detail, &.{})}))) return c.JS_DupValue(scope.engine.context, parsed);
    return c.pi_js_undefined();
}
fn toU32(scope: *Scope, value: c.JSValue) !u32 {
    var result: u32 = 0;
    if (c.JS_ToUint32(scope.engine.context, &result, value) < 0) return v.js.capture(scope.engine);
    return result;
}
fn imul(scope: *Scope, left: u32, right: u32) !c.JSValue {
    return scope.invoke(try scope.global("Math"), "imul", &.{ c.JS_NewUint32(scope.engine.context, left), c.JS_NewUint32(scope.engine.context, right) });
}
fn hash(scope: *Scope, text: c.JSValue) !c.JSValue {
    var h1 = c.JS_NewUint32(scope.engine.context, 0xdeadbeef);
    var h2 = c.JS_NewUint32(scope.engine.context, 0x41c6ce57);
    var index: u32 = 0;
    while (index < try v.length(scope, text)) : (index += 1) {
        const ch = try scope.invoke(text, "charCodeAt", &.{c.JS_NewUint32(scope.engine.context, index)});
        h1 = try imul(scope, try toU32(scope, h1) ^ try toU32(scope, ch), 2654435761);
        h2 = try imul(scope, try toU32(scope, h2) ^ try toU32(scope, ch), 1597334677);
    }
    const first = try imul(scope, try toU32(scope, h1) ^ (try toU32(scope, h1) >> 16), 2246822507);
    const second = try imul(scope, try toU32(scope, h2) ^ (try toU32(scope, h2) >> 13), 3266489909);
    h1 = c.JS_NewUint32(scope.engine.context, try toU32(scope, first) ^ try toU32(scope, second));
    const third = try imul(scope, try toU32(scope, h2) ^ (try toU32(scope, h2) >> 16), 2246822507);
    const fourth = try imul(scope, try toU32(scope, h1) ^ (try toU32(scope, h1) >> 13), 3266489909);
    h2 = c.JS_NewUint32(scope.engine.context, try toU32(scope, third) ^ try toU32(scope, fourth));
    return scope.concat(try scope.invoke(h2, "toString", &.{c.JS_NewInt32(scope.engine.context, 36)}), try scope.invoke(h1, "toString", &.{c.JS_NewInt32(scope.engine.context, 36)}));
}
fn normalizeId(scope: *Scope, id: c.JSValue, model: c.JSValue) !c.JSValue {
    if (scope.truthy(try scope.invoke(id, "includes", &.{try scope.text("|")}))) {
        const separator = try scope.invoke(id, "indexOf", &.{try scope.text("|")});
        const regex = try scope.own(try v.js.builtin(scope.engine, "RegExp", &.{ try scope.text("[^a-zA-Z0-9_-]"), try scope.text("g") }));
        const call_id = try scope.invoke(try scope.invoke(id, "slice", &.{ c.JS_NewInt32(scope.engine.context, 0), separator }), "replace", &.{ regex, try scope.text("_") });
        const next = try scope.own(try @import("native_image_arithmetic.zig").binary(scope.engine, .add, separator, c.JS_NewInt32(scope.engine.context, 1)));
        const item_id = try scope.invoke(try scope.invoke(id, "slice", &.{next}), "replace", &.{ regex, try scope.text("_") });
        const combined = if (try v.length(scope, item_id) > 0) try scope.concat(try scope.concat(call_id, try scope.text("_")), item_id) else call_id;
        if (try v.length(scope, combined) <= 40) return c.JS_DupValue(scope.engine.context, combined);
        const hashed = try scope.invoke(try hash(scope, id), "slice", &.{ c.JS_NewInt32(scope.engine.context, 0), c.JS_NewInt32(scope.engine.context, 8) });
        const room = try scope.own(try @import("native_image_arithmetic.zig").binary(scope.engine, .subtract, c.JS_NewInt32(scope.engine.context, 39), try scope.get(hashed, "length")));
        const prefix = try scope.invoke(call_id, "slice", &.{ c.JS_NewInt32(scope.engine.context, 0), try scope.invoke(try scope.global("Math"), "max", &.{ c.JS_NewInt32(scope.engine.context, 1), room }) });
        return c.JS_DupValue(scope.engine.context, try scope.concat(try scope.concat(prefix, try scope.text("_")), hashed));
    }
    if (try v.eq(scope, try scope.get(model, "provider"), "openai") and try v.length(scope, id) > 40) return v.js.invoke(scope.engine, id, "slice", &.{ c.JS_NewInt32(scope.engine.context, 0), c.JS_NewInt32(scope.engine.context, 40) });
    return c.JS_DupValue(scope.engine.context, id);
}
fn assistant(scope: *Scope, message: c.JSValue, model: c.JSValue, compat: c.JSValue, grammar_properties: c.JSValue) !c.JSValue {
    const result = try scope.object();
    try scope.put(result, "role", try scope.text("assistant"));
    try scope.put(result, "content", if (scope.truthy(try scope.get(compat, "requiresAssistantAfterToolResult"))) try scope.text("") else c.pi_js_null());
    const content = try scope.get(message, "content");
    const text_blocks = try scope.invoke(content, "filter", &.{try function(scope, .text, &.{})});
    const nonempty_text = try scope.invoke(text_blocks, "filter", &.{try function(scope, .nonempty_text, &.{})});
    const text_parts = try scope.invoke(nonempty_text, "map", &.{try function(scope, .text_part, &.{})});
    const text = try scope.invoke(try scope.invoke(text_parts, "map", &.{try function(scope, .text_value, &.{})}), "join", &.{try scope.text("")});
    const thinking = try scope.invoke(content, "filter", &.{try function(scope, .thinking, &.{})});
    const calls = try scope.invoke(content, "filter", &.{try function(scope, .tool, &.{})});
    const signed = try scope.invoke(try scope.invoke(thinking, "map", &.{try function(scope, .signed, &.{})}), "find", &.{try function(scope, .defined, &.{})});
    const legacy = try scope.invoke(try scope.invoke(calls, "map", &.{try function(scope, .legacy, &.{})}), "filter", &.{try function(scope, .defined, &.{})});
    const details = if (!v.nullish(signed)) signed else if (try v.length(scope, legacy) > 0) legacy else c.pi_js_undefined();
    const nonempty = try scope.invoke(thinking, "filter", &.{try function(scope, .nonempty_thinking, &.{})});
    if (try v.length(scope, nonempty) > 0) {
        if (scope.truthy(try scope.get(compat, "requiresThinkingAsText"))) {
            const thought = try scope.invoke(try scope.invoke(nonempty, "map", &.{try function(scope, .sanitized_thinking, &.{})}), "join", &.{try scope.text("\n\n")});
            const combined = try scope.own(try @import("native_sdk_transcript_replay.zig").arraySpread(scope.engine, text_parts, try textPart(scope, thought)));
            try scope.put(result, "content", combined);
        } else {
            if (try v.length(scope, text) > 0) try scope.put(result, "content", text);
            if (!scope.truthy(details)) {
                var signature = try scope.get(try v.at(scope, nonempty, 0), "thinkingSignature");
                if (try v.eq(scope, try scope.get(model, "provider"), "opencode-go") and try v.eq(scope, signature, "reasoning")) signature = try scope.text("reasoning_content");
                if (scope.truthy(signature) and (try v.eq(scope, signature, "reasoning") or try v.eq(scope, signature, "reasoning_content") or try v.eq(scope, signature, "reasoning_text"))) {
                    const joined = try scope.invoke(try scope.invoke(nonempty, "map", &.{try function(scope, .thinking_value, &.{})}), "join", &.{try scope.text("\n")});
                    try v.js.setKey(scope.engine, result, signature, joined);
                }
            }
        }
    } else if (try v.length(scope, text) > 0) try scope.put(result, "content", text);
    if (try v.length(scope, calls) > 0) try scope.put(result, "tool_calls", try scope.invoke(calls, "map", &.{try function(scope, .tool_call, &.{grammar_properties})}));
    if (scope.truthy(details)) try scope.put(result, "reasoning_details", details);
    if (scope.truthy(try scope.get(compat, "requiresReasoningContentOnAssistantMessages")) and scope.truthy(try scope.get(model, "reasoning")) and c.JS_IsUndefined(try scope.get(result, "reasoning_content"))) try scope.put(result, "reasoning_content", try scope.text(""));
    const final_content = try scope.get(result, "content");
    const has_content = !v.nullish(final_content) and try v.length(scope, final_content) > 0;
    return if (!has_content and !scope.truthy(try scope.get(result, "tool_calls"))) c.pi_js_undefined() else result;
}
fn bridge(scope: *Scope) !c.JSValue {
    const result = try scope.object();
    try scope.put(result, "role", try scope.text("assistant"));
    try scope.put(result, "content", try scope.text("I have processed the tool results."));
    return result;
}
pub fn convert(engine: *v.em.Engine, model: c.JSValue, context: c.JSValue, compat: c.JSValue, grammar_properties: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const normalized = try scope.own(try @import("native_ai_provider_transcript.zig").resolve(engine, context, scope.truthy(try scope.get(compat, "supportsMidConvoSystemMessages"))));
    const result = try scope.array();
    const messages = try scope.own(try @import("native_ai_transform_messages.zig").transform(engine, try scope.get(normalized, "messages"), model, try function(&scope, .normalize_id, &.{model})));
    const transcript_tools = try scope.own(try @import("native_ai_provider_transcript.zig").tools(engine, try scope.get(normalized, "messages"), scope.equal(try scope.get(compat, "supportsMidConvoSystemMessages"), c.pi_js_bool(engine.context, 1)) and scope.equal(try scope.get(compat, "supportsMidConvoToolAdditions"), c.pi_js_bool(engine.context, 1))));
    const instruction: []const u8 = if (scope.truthy(try scope.get(model, "reasoning")) and scope.truthy(try scope.get(compat, "supportsDeveloperRole"))) "developer" else "system";
    var last_role = c.pi_js_null();
    var index: u32 = 0;
    while (index < try v.length(&scope, messages)) : (index += 1) {
        var row: Scope = .{ .engine = engine };
        defer row.deinit();
        const message = try v.at(&row, messages, index);
        const role = try row.get(message, "role");
        if (row.truthy(try row.get(compat, "requiresAssistantAfterToolResult")) and try v.eq(&row, last_role, "toolResult") and try v.eq(&row, role, "user")) _ = try row.invoke(result, "push", &.{try bridge(&row)});
        if (try v.eq(&row, role, "system")) {
            const additions = if (index > 0 and row.truthy(try row.get(transcript_tools, "anchorsAdditions"))) try row.get(message, "toolsAdded") else c.pi_js_undefined();
            if (!v.nullish(additions) and try v.length(&row, additions) > 0) {
                const tool_message = try row.object();
                try row.put(tool_message, "role", try row.text("system"));
                try row.put(tool_message, "tools", try row.own(try tools.convert(engine, additions, compat)));
                _ = try row.invoke(result, "push", &.{tool_message});
            }
            const text = try row.own(try @import("native_ai_text.zig").system(engine, message, index != 0));
            if (try v.length(&row, text) > 0) {
                const part = try row.object();
                try row.put(part, "role", try row.text(instruction));
                try row.put(part, "content", try v.sanitize(&row, text));
                _ = try row.invoke(result, "push", &.{part});
            }
        } else if (try v.eq(&row, role, "user")) {
            const content = try row.get(message, "content");
            var converted = c.pi_js_undefined();
            if (c.JS_IsString(content)) converted = try v.sanitize(&row, content) else {
                converted = try row.invoke(try row.invoke(content, "filter", &.{try function(&row, .user_nonempty, &.{})}), "map", &.{try function(&row, .user_part, &.{})});
                if (try v.length(&row, converted) == 0) continue;
            }
            const part = try row.object();
            try row.put(part, "role", try row.text("user"));
            try row.put(part, "content", converted);
            _ = try row.invoke(result, "push", &.{part});
        } else if (try v.eq(&row, role, "assistant")) {
            const converted = try assistant(&row, message, model, compat, grammar_properties);
            if (c.JS_IsUndefined(converted)) continue;
            _ = try row.invoke(result, "push", &.{converted});
        } else if (try v.eq(&row, role, "toolResult")) {
            const images = try row.array();
            var next = index;
            while (next < try v.length(&row, messages)) : (next += 1) {
                var tool_row: Scope = .{ .engine = engine };
                defer tool_row.deinit();
                const tool_message = try v.at(&tool_row, messages, next);
                if (!try v.eq(&tool_row, try tool_row.get(tool_message, "role"), "toolResult")) break;
                const content = try tool_row.get(tool_message, "content");
                const text = try tool_row.invoke(try tool_row.invoke(try tool_row.invoke(content, "filter", &.{try function(&tool_row, .text, &.{})}), "map", &.{try function(&tool_row, .text_value, &.{})}), "join", &.{try tool_row.text("\n")});
                const has_images = tool_row.truthy(try tool_row.invoke(content, "some", &.{try function(&tool_row, .image, &.{})}));
                const has_text = try @import("native_image_arithmetic.zig").compare(engine, .greater, try tool_row.get(try tool_row.invoke(text, "trim", &.{}), "length"), c.JS_NewInt32(engine.context, 0));
                const part = try tool_row.object();
                try tool_row.put(part, "role", try tool_row.text("tool"));
                try tool_row.put(part, "content", try v.sanitize(&tool_row, if (has_text) text else try tool_row.text(if (has_images) "(see attached image)" else "(no tool output)")));
                try tool_row.put(part, "tool_call_id", try tool_row.get(tool_message, "toolCallId"));
                if (tool_row.truthy(try tool_row.get(compat, "requiresToolResultName")) and tool_row.truthy(try tool_row.get(tool_message, "toolName"))) try tool_row.put(part, "name", try tool_row.get(tool_message, "toolName"));
                _ = try tool_row.invoke(result, "push", &.{part});
                if (has_images and tool_row.truthy(try tool_row.invoke(try tool_row.get(model, "input"), "includes", &.{try tool_row.text("image")}))) {
                    var rows = try v.iterator(&tool_row, content);
                    defer rows.deinit();
                    errdefer rows.closePreserving();
                    while (try rows.next()) |block| {
                        defer engine.freeValue(block);
                        if (try v.eq(&tool_row, try tool_row.get(block, "type"), "image")) _ = try tool_row.invoke(images, "push", &.{try imagePart(&tool_row, block)});
                    }
                }
            }
            index = next - 1;
            if (try v.length(&row, images) > 0) {
                if (row.truthy(try row.get(compat, "requiresAssistantAfterToolResult"))) _ = try row.invoke(result, "push", &.{try bridge(&row)});
                const part = try row.object();
                try row.put(part, "role", try row.text("user"));
                try row.put(part, "content", try row.own(try @import("native_sdk_transcript_replay.zig").arraySpread(engine, images, try textPart(&row, try row.text("Attached image(s) from tool result:")))));
                _ = try row.invoke(result, "push", &.{part});
                last_role = try scope.text("user");
            } else last_role = try scope.text("toolResult");
            continue;
        }
        last_role = try scope.own(c.JS_DupValue(engine.context, try row.get(message, "role")));
    }
    return c.JS_DupValue(engine.context, result);
}
