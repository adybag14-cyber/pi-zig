//! Mistral Conversations payload, ID collision handling and wire remapping.
const v = @import("native_ai_provider_values.zig");
const Scope = v.Scope;
const c = v.c;
fn uint(scope: *Scope, value: c.JSValue) !u32 {
    var result: u32 = 0;
    if (c.JS_ToUint32(scope.engine.context, &result, value) < 0) return v.js.capture(scope.engine);
    return result;
}
pub fn derive(scope: *Scope, id: c.JSValue, attempt: u32) !c.JSValue {
    const regex = try scope.own(try v.js.builtin(scope.engine, "RegExp", &.{ try scope.text("[^a-zA-Z0-9]"), try scope.text("g") }));
    const normalized = try scope.invoke(id, "replace", &.{ regex, try scope.text("") });
    if (attempt == 0 and try v.length(scope, normalized) == 9) return normalized;
    const base = if (scope.truthy(normalized)) normalized else id;
    const seed = if (attempt == 0) base else try scope.concat(try scope.concat(base, try scope.text(":")), try scope.stringify(c.JS_NewUint32(scope.engine.context, attempt)));
    var h1: u32 = 0xdeadbeef;
    var h2: u32 = 0x41c6ce57;
    var index: u32 = 0;
    while (index < try v.length(scope, seed)) : (index += 1) {
        const ch = try uint(scope, try scope.invoke(seed, "charCodeAt", &.{c.JS_NewUint32(scope.engine.context, index)}));
        h1 = (h1 ^ ch) *% 2654435761;
        h2 = (h2 ^ ch) *% 1597334677;
    }
    h1 = ((h1 ^ (h1 >> 16)) *% 2246822507) ^ ((h2 ^ (h2 >> 13)) *% 3266489909);
    h2 = ((h2 ^ (h2 >> 16)) *% 2246822507) ^ ((h1 ^ (h1 >> 13)) *% 3266489909);
    const hash = try scope.concat(try scope.invoke(c.JS_NewUint32(scope.engine.context, h2), "toString", &.{c.JS_NewInt32(scope.engine.context, 36)}), try scope.invoke(c.JS_NewUint32(scope.engine.context, h1), "toString", &.{c.JS_NewInt32(scope.engine.context, 36)}));
    return scope.invoke(hash, "slice", &.{ c.JS_NewInt32(scope.engine.context, 0), c.JS_NewInt32(scope.engine.context, 9) });
}
fn normalize(engine: *v.em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const id = if (args.len > 0) args[0] else c.pi_js_undefined();
    const mapped = try scope.invoke(roots[0], "get", &.{id});
    if (scope.truthy(mapped)) return c.JS_DupValue(engine.context, mapped);
    var attempt: u32 = 0;
    while (true) : (attempt += 1) {
        const candidate = try derive(&scope, id, attempt);
        const owner = try scope.invoke(roots[1], "get", &.{candidate});
        if (!scope.truthy(owner) or scope.equal(owner, id)) {
            _ = try scope.invoke(roots[0], "set", &.{ id, candidate });
            _ = try scope.invoke(roots[1], "set", &.{ candidate, id });
            return c.JS_DupValue(engine.context, candidate);
        }
    }
}
pub fn simple(scope: *Scope, dependencies: c.JSValue, model: c.JSValue, context: c.JSValue, input: c.JSValue) !c.JSValue {
    const base = try scope.invoke(try scope.get(dependencies, "simple"), "buildBaseOptions", &.{ model, context, input, try v.optional(scope, input, "apiKey") });
    const result = try v.spread(scope, base);
    try scope.put(result, "toolChoice", try v.optional(scope, input, "toolChoice"));
    const raw = try v.optional(scope, input, "reasoning");
    const clamped = if (scope.truthy(raw)) try scope.invoke(try scope.get(dependencies, "thinking"), "clampThinkingLevel", &.{ model, raw }) else c.pi_js_undefined();
    const reasoning = if (try v.eq(scope, clamped, "off")) c.pi_js_undefined() else clamped;
    const map = if (scope.truthy(try scope.get(model, "reasoning"))) try scope.get(model, "thinkingLevelMap") else c.pi_js_undefined();
    var effort = c.pi_js_undefined();
    if (scope.truthy(map)) {
        effort = try scope.own(try v.js.getKey(scope.engine, map, if (scope.truthy(reasoning)) reasoning else try scope.text("off")));
        if (v.nullish(effort)) effort = if (scope.truthy(reasoning)) try scope.text("high") else c.pi_js_undefined();
    }
    try scope.put(result, "promptMode", if (scope.truthy(try scope.get(model, "reasoning")) and !scope.truthy(map) and scope.truthy(reasoning)) try scope.text("reasoning") else c.pi_js_undefined());
    try scope.put(result, "reasoningEffort", effort);
    return result;
}
fn text(scope: *Scope, value: c.JSValue) !c.JSValue {
    const result = try scope.object();
    try scope.put(result, "type", try scope.text("text"));
    try scope.put(result, "text", value);
    return result;
}
fn image(scope: *Scope, block: c.JSValue) !c.JSValue {
    const result = try scope.object();
    try scope.put(result, "type", try scope.text("image_url"));
    const url = try scope.concat(try scope.concat(try scope.text("data:"), try scope.stringify(try scope.get(block, "mimeType"))), try scope.text(";base64,"));
    try scope.put(result, "imageUrl", try scope.concat(url, try scope.stringify(try scope.get(block, "data"))));
    return result;
}
pub fn cache(scope: *Scope, options: c.JSValue) !bool {
    return !try v.eq(scope, try v.optional(scope, options, "cacheRetention"), "none") and scope.truthy(try v.optional(scope, options, "sessionId"));
}
pub fn build(engine: *v.em.Engine, dependencies: c.JSValue, model: c.JSValue, context: c.JSValue, options: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const id_map = try scope.own(try v.js.builtin(engine, "Map", &.{}));
    const reverse = try scope.own(try v.js.builtin(engine, "Map", &.{}));
    const normalizer = try scope.own(try @import("native_node_function.zig").create(engine, "", 1, normalize, &.{ id_map, reverse }));
    const transformed = try scope.own(try @import("native_ai_transform_messages.zig").transform(engine, try scope.get(context, "messages"), model, normalizer));
    const result = try scope.object();
    try scope.put(result, "model", try scope.get(model, "id"));
    try scope.put(result, "stream", c.pi_js_bool(engine.context, 1));
    const messages = try scope.array();
    try scope.put(result, "messages", messages);
    const supports_images = scope.truthy(try scope.invoke(try scope.get(model, "input"), "includes", &.{try scope.text("image")}));
    var rows = try v.iterator(&scope, transformed);
    defer rows.deinit();
    errdefer rows.closePreserving();
    var message_index: usize = 0;
    while (try rows.next()) |message| : (message_index += 1) {
        defer engine.freeValue(message);
        var row: Scope = .{ .engine = engine };
        defer row.deinit();
        const role = try row.get(message, "role");
        const content = try row.get(message, "content");
        const outgoing = try row.object();
        if (try v.eq(&row, role, "system")) {
            const value = try row.invoke(try row.get(dependencies, "text"), if (message_index == 0) "getSystemMessageText" else "renderSystemMessageUpdate", &.{message});
            if (try v.length(&row, value) == 0) continue;
            try row.put(outgoing, "role", try row.text("system"));
            try row.put(outgoing, "content", try v.sanitize(&row, value));
        } else if (try v.eq(&row, role, "user")) {
            try row.put(outgoing, "role", role);
            if (c.JS_IsString(content)) try row.put(outgoing, "content", try v.sanitize(&row, content)) else {
                const parts = try row.array();
                var blocks = try v.iterator(&row, content);
                defer blocks.deinit();
                errdefer blocks.closePreserving();
                var had_images = false;
                while (try blocks.next()) |block| {
                    defer engine.freeValue(block);
                    if (try v.eq(&row, try row.get(block, "type"), "text")) _ = try row.invoke(parts, "push", &.{try text(&row, try v.sanitize(&row, try row.get(block, "text")))}) else {
                        had_images = true;
                        if (supports_images) _ = try row.invoke(parts, "push", &.{try image(&row, block)});
                    }
                }
                if (try v.length(&row, parts) > 0) try row.put(outgoing, "content", parts) else if (had_images and !supports_images) try row.put(outgoing, "content", try row.text("(image omitted: model does not support images)")) else continue;
            }
        } else if (try v.eq(&row, role, "assistant")) {
            const parts = try row.array();
            const calls = try row.array();
            var blocks = try v.iterator(&row, content);
            defer blocks.deinit();
            errdefer blocks.closePreserving();
            while (try blocks.next()) |block| {
                defer engine.freeValue(block);
                var item: Scope = .{ .engine = engine };
                defer item.deinit();
                const kind = try item.get(block, "type");
                if (try v.eq(&item, kind, "text") or try v.eq(&item, kind, "thinking")) {
                    const thinking = try v.eq(&item, kind, "thinking");
                    const value = try item.get(block, if (thinking) "thinking" else "text");
                    if (try v.length(&item, try item.invoke(value, "trim", &.{})) == 0) continue;
                    const part = if (!thinking) try text(&item, try v.sanitize(&item, value)) else blk: {
                        const chunk = try item.object();
                        try item.put(chunk, "type", try item.text("thinking"));
                        const texts = try item.array();
                        _ = try item.invoke(texts, "push", &.{try text(&item, try v.sanitize(&item, value))});
                        try item.put(chunk, "thinking", texts);
                        break :blk chunk;
                    };
                    _ = try item.invoke(parts, "push", &.{part});
                } else {
                    const call = try item.object();
                    try item.put(call, "id", try item.get(block, "id"));
                    try item.put(call, "type", try item.text("function"));
                    const function = try item.object();
                    try item.put(function, "name", try item.get(block, "name"));
                    const args = try item.get(block, "arguments");
                    try item.put(function, "arguments", try item.invoke(try item.global("JSON"), "stringify", &.{if (item.truthy(args)) args else try item.object()}));
                    try item.put(call, "function", function);
                    try item.put(call, "index", c.JS_NewInt32(engine.context, 0));
                    _ = try item.invoke(calls, "push", &.{call});
                }
            }
            if (try v.length(&row, parts) == 0 and try v.length(&row, calls) == 0) continue;
            try row.put(outgoing, "role", role);
            try row.put(outgoing, "prefix", c.pi_js_bool(engine.context, 0));
            if (try v.length(&row, parts) > 0) try row.put(outgoing, "content", parts);
            if (try v.length(&row, calls) > 0) try row.put(outgoing, "toolCalls", calls);
        } else {
            const texts = try row.array();
            const images = try row.array();
            var blocks = try v.iterator(&row, content);
            defer blocks.deinit();
            errdefer blocks.closePreserving();
            var has_images = false;
            while (try blocks.next()) |block| {
                defer engine.freeValue(block);
                if (try v.eq(&row, try row.get(block, "type"), "text")) _ = try row.invoke(texts, "push", &.{try v.sanitize(&row, try row.get(block, "text"))}) else if (try v.eq(&row, try row.get(block, "type"), "image")) {
                    has_images = true;
                    if (supports_images) _ = try row.invoke(images, "push", &.{try image(&row, block)});
                }
            }
            const joined = try row.invoke(try row.invoke(texts, "join", &.{try row.text("\n")}), "trim", &.{});
            const prefix = if (row.truthy(try row.get(message, "isError"))) "[tool error] " else "";
            var value = try row.concat(try row.text(prefix), if (try v.length(&row, joined) > 0) joined else try row.text(if (has_images) (if (supports_images) "(see attached image)" else "(image omitted: model does not support images)") else "(no tool output)"));
            if (try v.length(&row, joined) > 0 and has_images and !supports_images) value = try row.concat(value, try row.text("\n[tool image omitted: model does not support images]"));
            const parts = try row.array();
            _ = try row.invoke(parts, "push", &.{try text(&row, value)});
            try row.put(outgoing, "content", try row.invoke(parts, "concat", &.{images}));
            try row.put(outgoing, "role", try row.text("tool"));
            try row.put(outgoing, "toolCallId", try row.get(message, "toolCallId"));
            try row.put(outgoing, "name", try row.get(message, "toolName"));
        }
        _ = try row.invoke(messages, "push", &.{outgoing});
    }
    const tools = try scope.own(try @import("native_agent_tool_changes.zig").currentTools(engine, try scope.get(context, "messages")));
    if (try v.length(&scope, tools) > 0) try scope.put(result, "tools", try scope.own(try @import("native_ai_openai_tools.zig").convert(engine, tools, try scope.object())));
    inline for (.{ "temperature", "maxTokens", "promptMode", "reasoningEffort" }) |key| {
        const value = try v.optional(&scope, options, key);
        if (!c.JS_IsUndefined(value)) try scope.put(result, key, value);
    }
    const choice = try v.optional(&scope, options, "toolChoice");
    if (scope.truthy(choice)) {
        if (c.JS_IsString(choice)) try scope.put(result, "toolChoice", choice) else {
            const selected = try scope.object();
            try scope.put(selected, "type", try scope.text("function"));
            const function = try scope.object();
            try scope.put(function, "name", try scope.get(try scope.get(choice, "function"), "name"));
            try scope.put(selected, "function", function);
            try scope.put(result, "toolChoice", selected);
        }
    }
    if (try cache(&scope, options)) try scope.put(result, "promptCacheKey", try scope.get(options, "sessionId"));
    return c.JS_DupValue(engine.context, result);
}
fn remap(scope: *Scope, destination: c.JSValue, source: [*:0]const u8, target: [*:0]const u8) !void {
    if (!try v.js.hasKey(scope.engine, destination, try scope.text(@import("std").mem.span(source)))) return;
    try scope.put(destination, target, try scope.get(destination, source));
    try v.remove(scope, destination, source);
}
fn record(scope: *Scope, value: c.JSValue) !bool {
    return c.JS_IsObject(value) and !c.JS_IsFunction(scope.engine.context, value) and !try v.array(scope, value);
}
pub fn wire(scope: *Scope, payload: c.JSValue) !c.JSValue {
    const result = try v.spread(scope, payload);
    inline for (.{ .{ "topP", "top_p" }, .{ "maxTokens", "max_tokens" }, .{ "randomSeed", "random_seed" }, .{ "responseFormat", "response_format" }, .{ "toolChoice", "tool_choice" }, .{ "presencePenalty", "presence_penalty" }, .{ "frequencyPenalty", "frequency_penalty" }, .{ "parallelToolCalls", "parallel_tool_calls" }, .{ "reasoningEffort", "reasoning_effort" }, .{ "promptMode", "prompt_mode" }, .{ "promptCacheKey", "prompt_cache_key" }, .{ "safePrompt", "safe_prompt" } }) |pair| try remap(scope, result, pair[0], pair[1]);
    const messages = try scope.array();
    var rows = try v.iterator(scope, try scope.get(payload, "messages"));
    defer rows.deinit();
    errdefer rows.closePreserving();
    while (try rows.next()) |message| {
        defer scope.engine.freeValue(message);
        var row: Scope = .{ .engine = scope.engine };
        defer row.deinit();
        const output = try v.spread(&row, message);
        try remap(&row, output, "toolCalls", "tool_calls");
        try remap(&row, output, "toolCallId", "tool_call_id");
        const content = try row.get(message, "content");
        if (try v.array(&row, content)) {
            const parts = try row.array();
            var blocks = try v.iterator(&row, content);
            defer blocks.deinit();
            errdefer blocks.closePreserving();
            while (try blocks.next()) |block| {
                defer scope.engine.freeValue(block);
                const part = try v.spread(&row, block);
                inline for (.{ .{ "imageUrl", "image_url" }, .{ "documentUrl", "document_url" }, .{ "documentName", "document_name" }, .{ "fileId", "file_id" }, .{ "referenceIds", "reference_ids" }, .{ "inputAudio", "input_audio" } }) |pair| try remap(&row, part, pair[0], pair[1]);
                _ = try row.invoke(parts, "push", &.{part});
            }
            try row.put(output, "content", parts);
        }
        _ = try row.invoke(messages, "push", &.{output});
    }
    try scope.put(result, "messages", messages);
    const format = try scope.get(result, "response_format");
    if (try record(scope, format)) {
        const copy = try v.spread(scope, format);
        try remap(scope, copy, "jsonSchema", "json_schema");
        const schema = try scope.get(copy, "json_schema");
        if (try record(scope, schema)) {
            const child = try v.spread(scope, schema);
            try remap(scope, child, "schemaDefinition", "schema");
            try scope.put(copy, "json_schema", child);
        }
        try scope.put(result, "response_format", copy);
    }
    return result;
}
