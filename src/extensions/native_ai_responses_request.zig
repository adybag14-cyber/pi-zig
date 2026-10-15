//! Native JSValue Responses requests, replay and tools for Source 5ab7fe74.
const v = @import("native_ai_provider_values.zig");
const Scope = v.Scope;
const c = v.c;
const tool_mod = @import("native_ai_openai_tools.zig");
pub const Mode = enum { standard, azure, codex };
fn push(scope: *Scope, list: c.JSValue, item: c.JSValue) !void {
    _ = try scope.invoke(list, "push", &.{item});
}
fn json(scope: *Scope, value: c.JSValue) !c.JSValue {
    return scope.invoke(try scope.global("JSON"), "stringify", &.{value});
}
fn regex(scope: *Scope, pattern: []const u8, flags: []const u8) !c.JSValue {
    return scope.own(try v.js.builtin(scope.engine, "RegExp", &.{ try scope.text(pattern), try scope.text(flags) }));
}
fn toU32(scope: *Scope, value: c.JSValue) !u32 {
    var n: u32 = 0;
    if (c.JS_ToUint32(scope.engine.context, &n, value) < 0) return v.js.capture(scope.engine);
    return n;
}
fn imul(scope: *Scope, a: u32, b: u32) !u32 {
    return toU32(scope, try scope.invoke(try scope.global("Math"), "imul", &.{ c.JS_NewUint32(scope.engine.context, a), c.JS_NewUint32(scope.engine.context, b) }));
}
pub fn hash(scope: *Scope, value: c.JSValue) !c.JSValue {
    var a: u32 = 0xdeadbeef;
    var b: u32 = 0x41c6ce57;
    var i: u32 = 0;
    while (i < try v.length(scope, value)) : (i += 1) {
        const ch = try toU32(scope, try scope.invoke(value, "charCodeAt", &.{c.JS_NewUint32(scope.engine.context, i)}));
        a = try imul(scope, a ^ ch, 2654435761);
        b = try imul(scope, b ^ ch, 1597334677);
    }
    a = try imul(scope, a ^ (a >> 16), 2246822507) ^ try imul(scope, b ^ (b >> 13), 3266489909);
    b = try imul(scope, b ^ (b >> 16), 2246822507) ^ try imul(scope, a ^ (a >> 13), 3266489909);
    return scope.concat(try scope.invoke(c.JS_NewUint32(scope.engine.context, b), "toString", &.{c.JS_NewInt32(scope.engine.context, 36)}), try scope.invoke(c.JS_NewUint32(scope.engine.context, a), "toString", &.{c.JS_NewInt32(scope.engine.context, 36)}));
}
fn idPart(scope: *Scope, value: c.JSValue) !c.JSValue {
    const safe = try scope.invoke(value, "replace", &.{ try regex(scope, "[^a-zA-Z0-9_-]", "g"), try scope.text("_") });
    return scope.invoke(try scope.invoke(safe, "slice", &.{ c.JS_NewInt32(scope.engine.context, 0), c.JS_NewInt32(scope.engine.context, 64) }), "replace", &.{ try regex(scope, "_+$", ""), try scope.text("") });
}
fn normalize(scope: *Scope, id: c.JSValue, model: c.JSValue, source: c.JSValue) !c.JSValue {
    const provider = try scope.get(model, "provider");
    if (!(try v.eq(scope, provider, "openai") or try v.eq(scope, provider, "openai-codex") or try v.eq(scope, provider, "opencode") or (try v.eq(scope, provider, "azure") and try v.eq(scope, try scope.get(model, "api"), "azure-openai-responses"))) or !scope.truthy(try scope.invoke(id, "includes", &.{try scope.text("|")}))) return idPart(scope, id);
    const parts = try scope.invoke(id, "split", &.{try scope.text("|")});
    const call = try idPart(scope, try v.at(scope, parts, 0));
    const foreign = !scope.equal(try scope.get(source, "provider"), provider) or !scope.equal(try scope.get(source, "api"), try scope.get(model, "api"));
    var item = if (foreign) try scope.concat(try scope.text("fc_"), try hash(scope, try v.at(scope, parts, 1))) else try idPart(scope, try v.at(scope, parts, 1));
    if (!scope.truthy(try scope.invoke(item, "startsWith", &.{try scope.text("fc_")}))) item = try idPart(scope, try scope.concat(try scope.text("fc_"), item));
    return scope.concat(try scope.concat(call, try scope.text("|")), item);
}
pub fn compat(engine: *v.em.Engine, model: c.JSValue, mode: Mode) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const result = try scope.object();
    const input = try scope.get(model, "compat");
    inline for (.{ "supportsDeveloperRole", "supportsMidConvoSystemMessages", "supportsLongCacheRetention", "supportsStrictMode", "supportsOpenAIGrammarTools", "supportsAdditionalTools", "supportsToolSearch", "supportsExplicitPromptCacheMode", "supportsMaxOutputTokens", "supportsMidConvoEffort" }) |key| {
        const value = try v.optional(&scope, input, key);
        const default = @import("std").mem.eql(u8, key, "supportsDeveloperRole") or @import("std").mem.eql(u8, key, "supportsLongCacheRetention") or @import("std").mem.eql(u8, key, "supportsMaxOutputTokens") or (mode != .standard and @import("std").mem.eql(u8, key, "supportsStrictMode"));
        try scope.put(result, key, if (v.nullish(value)) c.pi_js_bool(engine.context, @intFromBool(default)) else value);
    }
    const affinity = try v.optional(&scope, input, "sessionAffinityFormat");
    const base = try scope.get(model, "baseUrl");
    const openrouter = try v.eq(&scope, try scope.get(model, "provider"), "openrouter") or (!v.nullish(base) and scope.truthy(try scope.invoke(base, "includes", &.{try scope.text("openrouter.ai")})));
    try scope.put(result, "sessionAffinityFormat", if (v.nullish(affinity)) try scope.text(if (openrouter) "openrouter" else "openai") else affinity);
    return c.JS_DupValue(engine.context, result);
}
pub fn chatGPT(scope: *Scope, model: c.JSValue, options: c.JSValue) !bool {
    const key = try v.optional(scope, options, "apiKey");
    return try v.eq(scope, try scope.get(model, "provider"), "openai") and try v.eq(scope, try scope.get(model, "baseUrl"), "https://api.openai.com/v1") and !c.JS_IsUndefined(key) and !scope.truthy(try scope.invoke(key, "startsWith", &.{try scope.text("sk-")}));
}
fn mapped(scope: *Scope, model: c.JSValue, effort: c.JSValue) !c.JSValue {
    const map = try scope.get(model, "thinkingLevelMap");
    const value = if (v.nullish(map)) c.pi_js_undefined() else try scope.own(try v.js.getKey(scope.engine, map, effort));
    return if (v.nullish(value)) effort else value;
}
pub fn configurationEffort(scope: *Scope, model: c.JSValue, options: c.JSValue, config: c.JSValue, mode: Mode) !c.JSValue {
    const effort = try v.optional(scope, options, "reasoningEffort");
    if (mode != .standard or !scope.truthy(try scope.get(config, "supportsMidConvoEffort")) or !scope.truthy(effort) or try chatGPT(scope, model, options)) return c.pi_js_undefined();
    return mapped(scope, model, effort);
}
fn configuration(scope: *Scope, list: c.JSValue, effort: c.JSValue) !void {
    const item = try scope.object();
    const reasoning = try scope.object();
    try scope.put(item, "type", try scope.text("configuration_update"));
    try scope.put(reasoning, "effort", effort);
    try scope.put(item, "reasoning", reasoning);
    try push(scope, list, item);
}
pub fn convertTools(scope: *Scope, tools: c.JSValue, config: c.JSValue, mode: Mode, deferred: bool) !c.JSValue {
    const converted = try scope.own(try tool_mod.convert(scope.engine, tools, config));
    const result = try scope.array();
    var rows = try v.iterator(scope, converted);
    defer rows.deinit();
    errdefer rows.closePreserving();
    while (try rows.next()) |tool| {
        defer scope.engine.freeValue(tool);
        var row: Scope = .{ .engine = scope.engine };
        defer row.deinit();
        const custom = try v.eq(&row, try row.get(tool, "type"), "custom");
        const body = try row.object();
        try row.put(body, "type", try row.text(if (custom) "custom" else "function"));
        try v.js.spreadInto(row.engine, body, try row.get(tool, if (custom) "custom" else "function"));
        if (custom) {
            const format = try row.object();
            const raw = try row.get(try row.get(body, "format"), "grammar");
            try row.put(format, "type", try row.text("grammar"));
            try row.put(format, "syntax", try row.get(raw, "syntax"));
            try row.put(format, "definition", try row.get(raw, "definition"));
            try row.put(body, "format", format);
        } else if (mode == .codex and row.equal(try row.get(body, "strict"), c.pi_js_bool(scope.engine.context, 0))) try row.put(body, "strict", c.pi_js_null());
        if (deferred) try row.put(body, "defer_loading", c.pi_js_bool(scope.engine.context, 1));
        try push(&row, result, body);
    }
    return result;
}
fn textPart(scope: *Scope, value: c.JSValue) !c.JSValue {
    const item = try scope.object();
    try scope.put(item, "type", try scope.text("input_text"));
    try scope.put(item, "text", try v.sanitize(scope, value));
    return item;
}
fn imagePart(scope: *Scope, value: c.JSValue) !c.JSValue {
    const item = try scope.object();
    try scope.put(item, "type", try scope.text("input_image"));
    try scope.put(item, "detail", try scope.text("auto"));
    try scope.put(item, "image_url", try scope.concat(try scope.concat(try scope.concat(try scope.text("data:"), try scope.stringify(try scope.get(value, "mimeType"))), try scope.text(";base64,")), try scope.stringify(try scope.get(value, "data"))));
    return item;
}
fn toolOutput(scope: *Scope, model: c.JSValue, content: c.JSValue) !c.JSValue {
    const texts = try scope.array();
    const images = try scope.array();
    var rows = try v.iterator(scope, content);
    defer rows.deinit();
    errdefer rows.closePreserving();
    while (try rows.next()) |block| {
        defer scope.engine.freeValue(block);
        if (try v.eq(scope, try scope.get(block, "type"), "text")) try push(scope, texts, try scope.get(block, "text")) else if (try v.eq(scope, try scope.get(block, "type"), "image")) try push(scope, images, block);
    }
    const text = try scope.invoke(texts, "join", &.{try scope.text("\n")});
    const has_images = try v.length(scope, images) > 0;
    if (!has_images or !scope.truthy(try scope.invoke(try scope.get(model, "input"), "includes", &.{try scope.text("image")}))) return v.sanitize(scope, if (scope.truthy(text)) text else try scope.text(if (has_images) "(see attached image)" else "(no tool output)"));
    const output = try scope.array();
    if (scope.truthy(text)) try push(scope, output, try textPart(scope, text));
    var pics = try v.iterator(scope, images);
    defer pics.deinit();
    errdefer pics.closePreserving();
    while (try pics.next()) |image| {
        defer scope.engine.freeValue(image);
        try push(scope, output, try imagePart(scope, image));
    }
    return output;
}
fn signature(scope: *Scope, value: c.JSValue) !c.JSValue {
    if (!scope.truthy(value)) return c.pi_js_undefined();
    if (scope.truthy(try scope.invoke(value, "startsWith", &.{try scope.text("{")}))) {
        const generation = scope.engine.native_allocation_generation;
        const parsed = scope.invoke(try scope.global("JSON"), "parse", &.{value}) catch |err| {
            try @import("native_ai_partial_json.zig").discard(scope.engine, err, generation);
            const legacy = try scope.object();
            try scope.put(legacy, "id", value);
            return legacy;
        };
        if (scope.equal(try scope.get(parsed, "v"), c.JS_NewInt32(scope.engine.context, 1)) and c.JS_IsString(try scope.get(parsed, "id"))) {
            const result = try scope.object();
            try scope.put(result, "id", try scope.get(parsed, "id"));
            const phase = try scope.get(parsed, "phase");
            if (try v.eq(scope, phase, "commentary") or try v.eq(scope, phase, "final_answer")) try scope.put(result, "phase", phase);
            return result;
        }
    }
    const result = try scope.object();
    try scope.put(result, "id", value);
    return result;
}
fn assistant(scope: *Scope, model: c.JSValue, message: c.JSValue, grammar: c.JSValue, msg_index: u32) !c.JSValue {
    const result = try scope.array();
    const same_api = scope.equal(try scope.get(message, "provider"), try scope.get(model, "provider")) and scope.equal(try scope.get(message, "api"), try scope.get(model, "api"));
    const same_model = same_api and scope.equal(try scope.get(message, "model"), try scope.get(model, "id"));
    var text_index: u32 = 0;
    var blocks = try v.iterator(scope, try scope.get(message, "content"));
    defer blocks.deinit();
    errdefer blocks.closePreserving();
    while (try blocks.next()) |block| {
        defer scope.engine.freeValue(block);
        var row: Scope = .{ .engine = scope.engine };
        defer row.deinit();
        const typ = try row.get(block, "type");
        if (try v.eq(&row, typ, "thinking")) {
            const signed = try row.get(block, "thinkingSignature");
            if (row.truthy(signed)) try push(&row, result, try row.invoke(try row.global("JSON"), "parse", &.{signed}));
        } else if (try v.eq(&row, typ, "text")) {
            const signed = try signature(&row, try row.get(block, "textSignature"));
            var id = try v.optional(&row, signed, "id");
            if (!row.truthy(id)) {
                const raw = if (text_index == 0) try @import("std").fmt.allocPrint(row.engine.gpa, "msg_pi_{d}", .{msg_index}) else try @import("std").fmt.allocPrint(row.engine.gpa, "msg_pi_{d}_{d}", .{ msg_index, text_index });
                defer row.engine.gpa.free(raw);
                id = try row.text(raw);
            } else if (try v.length(&row, id) > 64) id = try row.concat(try row.text("msg_"), try hash(&row, id));
            text_index += 1;
            const item = try row.object();
            try row.put(item, "type", try row.text("message"));
            try row.put(item, "role", try row.text("assistant"));
            try row.put(item, "status", try row.text("completed"));
            try row.put(item, "id", id);
            try row.put(item, "phase", try v.optional(&row, signed, "phase"));
            const part = try row.object();
            try row.put(part, "type", try row.text("output_text"));
            try row.put(part, "text", try v.sanitize(&row, try row.get(block, "text")));
            try row.put(part, "annotations", try row.array());
            const content = try row.array();
            try push(&row, content, part);
            try row.put(item, "content", content);
            try push(&row, result, item);
        } else if (try v.eq(&row, typ, "toolCall")) {
            const ids = try row.invoke(try row.get(block, "id"), "split", &.{try row.text("|")});
            const property = try row.invoke(grammar, "get", &.{try row.get(block, "name")});
            const custom = !c.JS_IsUndefined(property);
            var id = try v.at(&row, ids, 1);
            if ((same_api and !same_model) or v.nullish(id) or !row.truthy(try row.invoke(id, "startsWith", &.{try row.text(if (custom) "ctc_" else "fc_")}))) id = c.pi_js_undefined();
            const item = try row.object();
            try row.put(item, "type", try row.text(if (custom) "custom_tool_call" else "function_call"));
            try row.put(item, "id", id);
            try row.put(item, "call_id", try v.at(&row, ids, 0));
            try row.put(item, "name", try row.get(block, "name"));
            if (custom) {
                const input = try row.own(try v.js.getKey(row.engine, try row.get(block, "arguments"), property));
                if (!c.JS_IsString(input)) return v.errorText(&row, try row.concat(try row.concat(try row.concat(try row.text("Grammar tool call \""), try row.stringify(try row.get(block, "name"))), try row.text("\" requires argument \"")), try row.concat(try row.stringify(property), try row.text("\" to be a string."))));
                try row.put(item, "input", try v.sanitize(&row, input));
            } else try row.put(item, "arguments", try json(&row, try row.get(block, "arguments")));
            const namespace = try row.get(block, "namespace");
            if (same_model and !c.JS_IsUndefined(namespace)) try row.put(item, "namespace", namespace);
            try push(&row, result, item);
        }
    }
    return result;
}
pub fn messages(scope: *Scope, model: c.JSValue, context: c.JSValue, config: c.JSValue, grammar: c.JSValue, effort: c.JSValue, mode: Mode) !c.JSValue {
    const Adapter = struct {
        fn call(host: *v.em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
            var row: Scope = .{ .engine = host };
            defer row.deinit();
            return c.JS_DupValue(host.context, try normalize(&row, if (args.len > 0) args[0] else c.pi_js_undefined(), roots[0], if (args.len > 2) args[2] else c.pi_js_undefined()));
        }
    };
    const original = try scope.get(context, "messages");
    const transformed = try scope.own(try @import("native_ai_transform_messages.zig").transform(scope.engine, original, model, try scope.own(try @import("native_node_function.zig").create(scope.engine, "", 3, Adapter.call, &.{model}))));
    const tool_state = try scope.own(try @import("native_ai_provider_transcript.zig").tools(scope.engine, original, scope.truthy(try scope.get(config, "supportsAdditionalTools")) or scope.truthy(try scope.get(config, "supportsToolSearch"))));
    const result = try scope.array();
    const role = if (scope.truthy(try scope.get(model, "reasoning")) and scope.truthy(try scope.get(config, "supportsDeveloperRole"))) "developer" else "system";
    var source_index: u32 = 0;
    var msg_index: u32 = 0;
    var rows = try v.iterator(scope, transformed);
    defer rows.deinit();
    errdefer rows.closePreserving();
    while (try rows.next()) |message| {
        defer scope.engine.freeValue(message);
        var row: Scope = .{ .engine = scope.engine };
        defer row.deinit();
        const kind = try row.get(message, "role");
        const leading = source_index == 0 and try v.eq(&row, kind, "system");
        source_index += 1;
        if (try v.eq(&row, kind, "system")) {
            const added = if (!leading and row.truthy(try row.get(tool_state, "anchorsAdditions"))) try row.get(message, "toolsAdded") else c.pi_js_undefined();
            if (!v.nullish(added) and try v.length(&row, added) > 0) {
                if (row.truthy(try row.get(config, "supportsAdditionalTools"))) {
                    const item = try row.object();
                    try row.put(item, "type", try row.text("additional_tools"));
                    try row.put(item, "role", try row.text("developer"));
                    try row.put(item, "tools", try convertTools(&row, added, config, mode, false));
                    try push(&row, result, item);
                } else if (row.truthy(try row.get(config, "supportsToolSearch"))) {
                    const names = try row.array();
                    var additions = try v.iterator(&row, added);
                    defer additions.deinit();
                    errdefer additions.closePreserving();
                    while (try additions.next()) |tool| {
                        defer row.engine.freeValue(tool);
                        try push(&row, names, try row.get(tool, "name"));
                    }
                    const seed = try @import("std").fmt.allocPrint(row.engine.gpa, "system:{d}:", .{msg_index});
                    defer row.engine.gpa.free(seed);
                    const id = try row.concat(try row.text("pi_tool_load_"), try hash(&row, try row.concat(try row.text(seed), try row.invoke(names, "join", &.{try row.text(",")}))));
                    const call = try row.object();
                    try row.put(call, "type", try row.text("tool_search_call"));
                    try row.put(call, "call_id", id);
                    inline for (.{ "execution", "status" }, .{ "client", "completed" }) |key, value| try row.put(call, key, try row.text(value));
                    const args = try row.object();
                    try row.put(args, "query", try row.invoke(names, "join", &.{try row.text(" ")}));
                    try row.put(args, "limit", try row.get(names, "length"));
                    try row.put(call, "arguments", args);
                    try push(&row, result, call);
                    const output = try row.object();
                    try row.put(output, "type", try row.text("tool_search_output"));
                    try row.put(output, "call_id", id);
                    inline for (.{ "execution", "status" }, .{ "client", "completed" }) |key, value| try row.put(output, key, try row.text(value));
                    try row.put(output, "tools", try convertTools(&row, added, config, mode, true));
                    try push(&row, result, output);
                }
            }
            if (!leading or mode != .codex) {
                const content = try row.own(try @import("native_ai_text.zig").system(row.engine, message, !leading));
                if (try v.length(&row, content) > 0) {
                    const item = try row.object();
                    try row.put(item, "role", try row.text(role));
                    try row.put(item, "content", try v.sanitize(&row, content));
                    try push(&row, result, item);
                }
            }
        } else if (try v.eq(&row, kind, "user")) {
            const raw = try row.get(message, "content");
            const parts = try row.array();
            if (c.JS_IsString(raw)) try push(&row, parts, try textPart(&row, raw)) else {
                var blocks = try v.iterator(&row, raw);
                defer blocks.deinit();
                errdefer blocks.closePreserving();
                while (try blocks.next()) |block| {
                    defer row.engine.freeValue(block);
                    try push(&row, parts, if (try v.eq(&row, try row.get(block, "type"), "text")) try textPart(&row, try row.get(block, "text")) else try imagePart(&row, block));
                }
            }
            if (try v.length(&row, parts) == 0) continue;
            const item = try row.object();
            try row.put(item, "role", try row.text("user"));
            try row.put(item, "content", parts);
            try push(&row, result, item);
        } else if (try v.eq(&row, kind, "assistant")) {
            const output = try assistant(&row, model, message, grammar, msg_index);
            if (try v.length(&row, output) == 0) continue;
            const historical_effort = try row.get(message, "providerThinkingLevel");
            if (!c.JS_IsUndefined(effort) and !c.JS_IsUndefined(historical_effort) and row.equal(try row.get(message, "provider"), try row.get(model, "provider")) and row.equal(try row.get(message, "api"), try row.get(model, "api")) and row.equal(try row.get(message, "model"), try row.get(model, "id"))) try configuration(&row, result, historical_effort);
            var blocks = try v.iterator(&row, output);
            defer blocks.deinit();
            errdefer blocks.closePreserving();
            while (try blocks.next()) |block| {
                defer row.engine.freeValue(block);
                try push(&row, result, block);
            }
        } else if (try v.eq(&row, kind, "toolResult")) {
            const item = try row.object();
            const custom = row.truthy(try row.invoke(grammar, "has", &.{try row.get(message, "toolName")}));
            try row.put(item, "type", try row.text(if (custom) "custom_tool_call_output" else "function_call_output"));
            try row.put(item, "call_id", try v.at(&row, try row.invoke(try row.get(message, "toolCallId"), "split", &.{try row.text("|")}), 0));
            try row.put(item, "output", try toolOutput(&row, model, try row.get(message, "content")));
            try push(&row, result, item);
        }
        if (!leading) msg_index += 1;
    }
    if (!c.JS_IsUndefined(effort)) try configuration(scope, result, effort);
    return result;
}
pub fn build(engine: *v.em.Engine, model: c.JSValue, context: c.JSValue, options: c.JSValue, config: c.JSValue, retention: c.JSValue, grammar: c.JSValue, effort: c.JSValue, simple: c.JSValue, mode: Mode) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const params = try scope.object();
    try scope.put(params, "model", try scope.get(model, "id"));
    try scope.put(params, "input", try messages(&scope, model, context, config, grammar, effort, mode));
    try scope.put(params, "stream", c.pi_js_bool(engine.context, 1));
    const session = try v.optional(&scope, options, "sessionId");
    try scope.put(params, "prompt_cache_key", if (mode != .azure and try v.eq(&scope, retention, "none")) c.pi_js_undefined() else try cacheKey(&scope, session));
    if (mode == .standard) {
        try scope.put(params, "prompt_cache_retention", c.pi_js_undefined());
        try scope.put(params, "prompt_cache_options", c.pi_js_undefined());
    }
    const omit = mode == .standard and try chatGPT(&scope, model, options);
    if (mode == .standard and !omit) {
        const explicit = scope.truthy(try scope.get(config, "supportsExplicitPromptCacheMode"));
        const long = try v.eq(&scope, retention, "long") and scope.truthy(try scope.get(config, "supportsLongCacheRetention"));
        if (long and !explicit) try scope.put(params, "prompt_cache_retention", try scope.text("24h"));
        if (explicit and (long or try v.eq(&scope, retention, "none"))) {
            const cache = try scope.object();
            if (try v.eq(&scope, retention, "none")) try scope.put(cache, "mode", try scope.text("explicit")) else try scope.put(cache, "ttl", try scope.text("30m"));
            try scope.put(params, "prompt_cache_options", cache);
        }
    }
    try scope.put(params, "store", c.pi_js_bool(engine.context, 0));
    const max = try v.optional(&scope, options, "maxTokens");
    if (mode != .codex and !omit and scope.truthy(max) and (mode == .azure or scope.truthy(try scope.get(config, "supportsMaxOutputTokens")))) try scope.put(params, "max_output_tokens", try scope.invoke(try scope.global("Math"), "max", &.{ max, c.JS_NewInt32(engine.context, 16) }));
    const temperature = try v.optional(&scope, options, "temperature");
    if (!omit and !c.JS_IsUndefined(temperature)) try scope.put(params, "temperature", temperature);
    const tier = try v.optional(&scope, options, "serviceTier");
    if (mode != .azure and !c.JS_IsUndefined(tier)) try scope.put(params, "service_tier", tier);
    const transcript = try scope.own(try @import("native_ai_provider_transcript.zig").tools(engine, try scope.get(context, "messages"), scope.truthy(try scope.get(config, "supportsAdditionalTools")) or scope.truthy(try scope.get(config, "supportsToolSearch"))));
    const declarations = try scope.get(transcript, "requestTools");
    if (try v.length(&scope, declarations) > 0) try scope.put(params, "tools", try convertTools(&scope, declarations, config, mode, false));
    const choice = try v.optional(&scope, options, "toolChoice");
    if (!c.JS_IsUndefined(choice) or mode == .codex) try scope.put(params, "tool_choice", if (v.nullish(choice) and mode == .codex) try scope.text("auto") else choice);
    const requested = try v.optional(&scope, options, "reasoningEffort");
    const summary = try v.optional(&scope, options, "reasoningSummary");
    const reasoning_effort = if (!v.nullish(requested)) requested else if (scope.truthy(summary)) try scope.text("medium") else c.pi_js_undefined();
    const map = try scope.get(model, "thinkingLevelMap");
    const off = try v.optional(&scope, map, "off");
    if (mode == .codex) {
        try scope.put(params, "parallel_tool_calls", c.pi_js_bool(engine.context, 1));
        const verbosity = try v.optional(&scope, options, "textVerbosity");
        const text = try scope.object();
        try scope.put(text, "verbosity", if (scope.truthy(verbosity)) verbosity else try scope.text("low"));
        try scope.put(params, "text", text);
        const include = try scope.array();
        try push(&scope, include, try scope.text("reasoning.encrypted_content"));
        try scope.put(params, "include", include);
        const first = try v.at(&scope, try scope.get(context, "messages"), 0);
        var instructions = try scope.text("");
        if (scope.truthy(first) and try v.eq(&scope, try scope.get(first, "role"), "system")) instructions = try scope.own(try @import("native_ai_text.zig").system(engine, first, false));
        try scope.put(params, "instructions", if (scope.truthy(instructions)) instructions else try scope.text("You are a helpful assistant."));
        if (!c.JS_IsUndefined(requested)) {
            const level = if (try v.eq(&scope, requested, "none")) (if (c.JS_IsUndefined(off)) try scope.text("none") else off) else try mapped(&scope, model, requested);
            if (!c.JS_IsNull(level)) {
                const reasoning = try scope.object();
                try scope.put(reasoning, "effort", level);
                try scope.put(reasoning, "summary", if (v.nullish(summary)) try scope.text("auto") else summary);
                try scope.put(params, "reasoning", reasoning);
            }
        } else if (scope.truthy(try scope.get(model, "reasoning")) and !c.JS_IsNull(off)) {
            const reasoning = try scope.object();
            try scope.put(reasoning, "effort", if (v.nullish(off)) try scope.text("none") else off);
            try scope.put(params, "reasoning", reasoning);
        }
    } else if (scope.truthy(try scope.get(model, "reasoning"))) {
        if (scope.truthy(reasoning_effort)) {
            const reasoning = try scope.object();
            try scope.put(reasoning, "effort", if (!c.JS_IsUndefined(effort)) try scope.text("medium") else if (scope.truthy(requested)) try mapped(&scope, model, requested) else reasoning_effort);
            try scope.put(reasoning, "summary", if (scope.truthy(summary)) summary else try scope.text("auto"));
            try scope.put(params, "reasoning", reasoning);
            const include = try scope.array();
            try push(&scope, include, try scope.text("reasoning.encrypted_content"));
            try scope.put(params, "include", include);
        } else if ((mode == .azure or !try v.eq(&scope, try scope.get(model, "provider"), "github-copilot")) and !c.JS_IsNull(off)) {
            const reasoning = try scope.object();
            try scope.put(reasoning, "effort", if (v.nullish(off)) try scope.text("none") else off);
            try scope.put(params, "reasoning", reasoning);
        }
        if (mode == .standard and try v.eq(&scope, try scope.get(model, "provider"), "xai")) {
            const include = try scope.array();
            try push(&scope, include, try scope.text("reasoning.encrypted_content"));
            try scope.put(params, "include", include);
        }
    }
    if (mode != .codex) {
        const sampling = try scope.invoke(simple, "resolveSamplingParams", &.{ model, if (v.nullish(reasoning_effort)) try scope.text("off") else reasoning_effort, try v.optional(&scope, options, "samplingParams") });
        if (scope.truthy(sampling)) try v.js.spreadInto(engine, params, sampling);
    }
    // Standard/Azure construction preserves insertion positions when sampling
    // overwrites an existing field; a sampling-only field stays at the end.
    if (mode != .codex) return c.JS_DupValue(engine.context, params);
    // Codex has a separate literal layout and does not use sampling overlays.
    const ordered = try scope.object();
    if (mode == .codex) {
        inline for (.{ "model", "store", "stream", "instructions", "input", "text", "include", "prompt_cache_key", "tool_choice", "parallel_tool_calls", "temperature", "service_tier", "tools", "reasoning" }) |key| if (try v.js.hasKey(engine, params, try scope.text(key))) try scope.put(ordered, key, try scope.get(params, key));
    }
    var keys = try v.iterator(&scope, try scope.invoke(try scope.global("Object"), "keys", &.{params}));
    defer keys.deinit();
    errdefer keys.closePreserving();
    while (try keys.next()) |key| {
        defer engine.freeValue(key);
        if (!try v.js.hasKey(engine, ordered, key)) try v.js.setKey(engine, ordered, key, try scope.own(try v.js.getKey(engine, params, key)));
    }
    return c.JS_DupValue(engine.context, ordered);
}
pub fn cacheKey(scope: *Scope, key: c.JSValue) !c.JSValue {
    if (c.JS_IsUndefined(key)) return key;
    const chars = try scope.invoke(try scope.global("Array"), "from", &.{key});
    if (try v.length(scope, chars) <= 64) return key;
    return scope.invoke(try scope.invoke(chars, "slice", &.{ c.JS_NewInt32(scope.engine.context, 0), c.JS_NewInt32(scope.engine.context, 64) }), "join", &.{try scope.text("")});
}
