//! Actual OpenAI-completions request parameter body; no fixture or SDK delegate.
const v = @import("native_ai_provider_values.zig");
const Scope = v.Scope;
const c = v.c;
const arithmetic = @import("native_image_arithmetic.zig");
const tools = @import("native_ai_openai_tools.zig");
fn mapped(scope: *Scope, model: c.JSValue, key: c.JSValue) !c.JSValue {
    const map = try scope.get(model, "thinkingLevelMap");
    return if (v.nullish(map)) c.pi_js_undefined() else scope.own(try v.js.getKey(scope.engine, map, key));
}
pub fn cacheRetention(scope: *Scope, options: c.JSValue) !c.JSValue {
    const configured = try v.optional(scope, options, "cacheRetention");
    if (scope.truthy(configured)) return configured;
    const environment = try v.optional(scope, options, "env");
    const env = try scope.own(try @import("native_ai_env_keys.zig").create(scope.engine, .{}));
    const retained = try scope.invoke(env, "getProviderEnvValue", &.{ try scope.text("PI_CACHE_RETENTION"), environment });
    return scope.text(if (try v.eq(scope, retained, "long")) "long" else "short");
}
fn cacheKey(scope: *Scope, key: c.JSValue) !c.JSValue {
    if (c.JS_IsUndefined(key)) return key;
    const chars = try scope.invoke(try scope.global("Array"), "from", &.{key});
    if (try v.length(scope, chars) <= 64) return key;
    return scope.invoke(try scope.invoke(chars, "slice", &.{ c.JS_NewInt32(scope.engine.context, 0), c.JS_NewInt32(scope.engine.context, 64) }), "join", &.{try scope.text("")});
}
fn hasToolHistory(scope: *Scope, messages: c.JSValue) !bool {
    const Adapter = struct {
        fn call(engine: *v.em.Engine, _: c.JSValue, args: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
            var row: Scope = .{ .engine = engine };
            defer row.deinit();
            return c.pi_js_bool(engine.context, @intFromBool(try v.eq(&row, try row.get(if (args.len > 0) args[0] else c.pi_js_undefined(), "type"), "toolCall")));
        }
    };
    const predicate = try scope.own(try @import("native_node_function.zig").create(scope.engine, "", 1, Adapter.call, &.{}));
    var rows = try v.iterator(scope, messages);
    defer rows.deinit();
    errdefer rows.closePreserving();
    while (try rows.next()) |message| {
        defer scope.engine.freeValue(message);
        var row: Scope = .{ .engine = scope.engine };
        defer row.deinit();
        const role = try row.get(message, "role");
        if (try v.eq(&row, role, "toolResult")) return true;
        if (try v.eq(&row, role, "assistant") and row.truthy(try row.invoke(try row.get(message, "content"), "some", &.{predicate}))) return true;
    }
    return false;
}
fn cacheText(scope: *Scope, message: c.JSValue, control: c.JSValue) !bool {
    const content = try scope.get(message, "content");
    if (c.JS_IsString(content)) {
        if (try v.length(scope, content) == 0) return false;
        const part = try scope.object();
        try scope.put(part, "type", try scope.text("text"));
        try scope.put(part, "text", content);
        try scope.put(part, "cache_control", control);
        const parts = try scope.array();
        _ = try scope.invoke(parts, "push", &.{part});
        try scope.set(message, "content", parts);
        return true;
    }
    if (!try v.array(scope, content)) return false;
    var index = try v.length(scope, content);
    while (index > 0) {
        index -= 1;
        const part = try v.at(scope, content, index);
        if (try v.eq(scope, try v.optional(scope, part, "type"), "text")) {
            try scope.set(part, "cache_control", control);
            return true;
        }
    }
    return false;
}
fn applyCache(scope: *Scope, messages: c.JSValue, declarations: c.JSValue, control: c.JSValue) !void {
    var rows = try v.iterator(scope, messages);
    defer rows.deinit();
    errdefer rows.closePreserving();
    while (try rows.next()) |message| {
        defer scope.engine.freeValue(message);
        const role = try scope.get(message, "role");
        if (try v.eq(scope, role, "system") or try v.eq(scope, role, "developer")) {
            _ = try cacheText(scope, message, control);
            break;
        }
    }
    if (scope.truthy(declarations) and try v.length(scope, declarations) > 0) try scope.set(try v.at(scope, declarations, try v.length(scope, declarations) - 1), "cache_control", control);
    var index = try v.length(scope, messages);
    while (index > 0) {
        index -= 1;
        const message = try v.at(scope, messages, index);
        const role = try scope.get(message, "role");
        if ((try v.eq(scope, role, "user") or try v.eq(scope, role, "assistant") or try v.eq(scope, role, "tool")) and try cacheText(scope, message, control)) break;
    }
}
fn chatValues(scope: *Scope, model: c.JSValue, options: c.JSValue, values: c.JSValue, budget: c.JSValue) !c.JSValue {
    const result = try scope.object();
    var rows = try v.iterator(scope, try scope.invoke(try scope.global("Object"), "entries", &.{values}));
    defer rows.deinit();
    errdefer rows.closePreserving();
    while (try rows.next()) |entry| {
        defer scope.engine.freeValue(entry);
        var row: Scope = .{ .engine = scope.engine };
        defer row.deinit();
        const value = try v.at(&row, entry, 1);
        var resolved = value;
        if (c.JS_IsObject(value) and !c.JS_IsFunction(scope.engine.context, value)) {
            const effort = try v.optional(&row, options, "reasoningEffort");
            if (!row.truthy(effort) and row.truthy(try row.get(value, "omitWhenOff"))) continue;
            const variable = try row.get(value, "$var");
            if (try v.eq(&row, variable, "thinking.enabled")) resolved = c.pi_js_bool(scope.engine.context, @intFromBool(row.truthy(effort))) else if (try v.eq(&row, variable, "thinking.budget")) resolved = budget else {
                const configured = try mapped(&row, model, if (row.truthy(effort)) effort else try row.text("off"));
                resolved = if (c.JS_IsUndefined(configured)) effort else if (c.JS_IsString(configured)) configured else c.pi_js_undefined();
            }
        }
        if (!c.JS_IsUndefined(resolved)) try v.js.setKey(scope.engine, result, try v.at(&row, entry, 0), resolved);
    }
    return if (try v.length(scope, try scope.invoke(try scope.global("Object"), "keys", &.{result})) > 0) result else c.pi_js_undefined();
}
fn thinking(scope: *Scope, params: c.JSValue, model: c.JSValue, options: c.JSValue, compat: c.JSValue, simple: c.JSValue) !void {
    const effort = try v.optional(scope, options, "reasoningEffort");
    const enabled = scope.truthy(effort);
    const reasoning = scope.truthy(try scope.get(model, "reasoning"));
    const supported = scope.truthy(try scope.get(compat, "supportsReasoningEffort"));
    const format = try scope.get(compat, "thinkingFormat");
    var field = try scope.get(compat, "thinkingTokenBudgetField");
    if (!scope.truthy(field) and scope.truthy(try scope.get(compat, "supportsThinkingTokenBudget"))) field = try scope.text("thinking_token_budget");
    var budget = c.pi_js_undefined();
    if (enabled and reasoning) {
        var ceiling = try scope.get(params, "max_tokens");
        if (v.nullish(ceiling)) ceiling = try scope.get(params, "max_completion_tokens");
        if (v.nullish(ceiling)) ceiling = try scope.get(model, "maxTokens");
        const desired = try scope.invoke(simple, "thinkingBudgetForLevel", &.{ effort, try v.optional(scope, options, "thinkingBudgets") });
        const clamped = try scope.invoke(simple, "clampThinkingBudgetToAnswerRoom", &.{ desired, ceiling });
        if (try arithmetic.compare(scope.engine, .greater, clamped, c.JS_NewInt32(scope.engine.context, 0))) budget = clamped;
    }
    if (try v.eq(scope, format, "zai") and reasoning) {
        const block = try scope.object();
        try scope.put(block, "type", try scope.text(if (enabled) "enabled" else "disabled"));
        if (enabled) try scope.put(block, "clear_thinking", c.pi_js_bool(scope.engine.context, 0));
        try scope.put(params, "thinking", block);
        if (enabled and supported) {
            const configured = try mapped(scope, model, effort);
            const value = if (c.JS_IsUndefined(configured)) effort else configured;
            if (c.JS_IsString(value)) try scope.put(params, "reasoning_effort", value);
        }
    } else if (try v.eq(scope, format, "qwen") and reasoning) {
        try scope.put(params, "enable_thinking", c.pi_js_bool(scope.engine.context, @intFromBool(enabled)));
        if (enabled and supported) {
            const configured = try mapped(scope, model, effort);
            const value = if (v.nullish(configured)) effort else configured;
            if (c.JS_IsString(value)) try scope.put(params, "reasoning_effort", value);
        }
    } else if (try v.eq(scope, format, "qwen-chat-template") and reasoning) {
        const block = try scope.object();
        try scope.put(block, "enable_thinking", c.pi_js_bool(scope.engine.context, @intFromBool(enabled)));
        try scope.put(block, "preserve_thinking", c.pi_js_bool(scope.engine.context, 1));
        try scope.put(params, "chat_template_kwargs", block);
    } else if ((try v.eq(scope, format, "chat-template") or try v.eq(scope, format, "baseten")) and reasoning) {
        const baseten = try v.eq(scope, format, "baseten");
        const values = try chatValues(scope, model, options, try scope.get(compat, if (baseten) "chatTemplateArgs" else "chatTemplateKwargs"), budget);
        if (scope.truthy(values)) try scope.put(params, if (baseten) "chat_template_args" else "chat_template_kwargs", values);
        if (baseten and supported) {
            const configured = try mapped(scope, model, if (enabled) effort else try scope.text("off"));
            const value = if (c.JS_IsUndefined(configured)) effort else configured;
            if (c.JS_IsString(value)) try scope.put(params, "reasoning_effort", value);
        }
    } else if (try v.eq(scope, format, "deepseek") and reasoning) {
        const off = try mapped(scope, model, try scope.text("off"));
        if (enabled or !c.JS_IsNull(off)) {
            const block = try scope.object();
            try scope.put(block, "type", try scope.text(if (enabled) "enabled" else "disabled"));
            try scope.put(params, "thinking", block);
        }
        if (enabled and supported) {
            const configured = try mapped(scope, model, effort);
            try scope.put(params, "reasoning_effort", if (v.nullish(configured)) effort else configured);
        }
    } else if (try v.eq(scope, format, "openrouter") and reasoning) {
        const off = try mapped(scope, model, try scope.text("off"));
        if (enabled or !c.JS_IsNull(off)) {
            const block = try scope.object();
            const configured = if (enabled) try mapped(scope, model, effort) else off;
            try scope.put(block, "effort", if (v.nullish(configured)) (if (enabled) effort else try scope.text("none")) else configured);
            try scope.put(params, "reasoning", block);
        }
    } else if (try v.eq(scope, format, "ant-ling") and reasoning and enabled) {
        const configured = try mapped(scope, model, effort);
        if (c.JS_IsString(configured)) {
            const block = try scope.object();
            try scope.put(block, "effort", configured);
            try scope.put(params, "reasoning", block);
        }
    } else if (try v.eq(scope, format, "together") and reasoning) {
        const block = try scope.object();
        try scope.put(block, "enabled", c.pi_js_bool(scope.engine.context, @intFromBool(enabled)));
        try scope.put(params, "reasoning", block);
        if (enabled and supported) {
            const configured = try mapped(scope, model, effort);
            try scope.put(params, "reasoning_effort", if (v.nullish(configured)) effort else configured);
        }
    } else if (try v.eq(scope, format, "string-thinking") and reasoning) {
        const configured = try mapped(scope, model, if (enabled) effort else try scope.text("off"));
        if (enabled or !c.JS_IsNull(configured)) try scope.put(params, "thinking", if (v.nullish(configured)) (if (enabled) effort else try scope.text("none")) else configured);
    } else if (reasoning and supported) {
        const configured = try mapped(scope, model, if (enabled) effort else try scope.text("off"));
        if (enabled) try scope.put(params, "reasoning_effort", if (v.nullish(configured)) effort else configured) else if (c.JS_IsString(configured)) try scope.put(params, "reasoning_effort", configured);
    }
    if (scope.truthy(field) and !c.JS_IsUndefined(budget)) {
        const entry = try scope.object();
        try v.js.setKey(scope.engine, entry, field, budget);
        _ = try scope.invoke(try scope.global("Object"), "assign", &.{ params, entry });
    }
}
pub fn build(engine: *v.em.Engine, model: c.JSValue, context: c.JSValue, options: c.JSValue, compat: c.JSValue, retention: c.JSValue, grammar_properties: c.JSValue, simple: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const transcript_tools = try scope.own(try @import("native_ai_provider_transcript.zig").tools(engine, try scope.get(context, "messages"), scope.equal(try scope.get(compat, "supportsMidConvoSystemMessages"), c.pi_js_bool(engine.context, 1)) and scope.equal(try scope.get(compat, "supportsMidConvoToolAdditions"), c.pi_js_bool(engine.context, 1))));
    const messages = try scope.own(try @import("native_ai_openai_messages.zig").convert(engine, model, context, compat, grammar_properties));
    var control = c.pi_js_undefined();
    const long = try v.eq(&scope, retention, "long");
    const none = try v.eq(&scope, retention, "none");
    const supports_long = scope.truthy(try scope.get(compat, "supportsLongCacheRetention"));
    if (try v.eq(&scope, try scope.get(compat, "cacheControlFormat"), "anthropic") and !none) {
        control = try scope.object();
        try scope.put(control, "type", try scope.text("ephemeral"));
        if (long and supports_long) try scope.put(control, "ttl", try scope.text("1h"));
    }
    const params = try scope.object();
    try scope.put(params, "model", try scope.get(model, "id"));
    try scope.put(params, "messages", messages);
    try scope.put(params, "stream", c.pi_js_bool(engine.context, 1));
    const prompt_key = (scope.truthy(try scope.invoke(try scope.get(model, "baseUrl"), "includes", &.{try scope.text("api.openai.com")})) and !none) or (long and supports_long);
    try scope.put(params, "prompt_cache_key", if (prompt_key) try cacheKey(&scope, try v.optional(&scope, options, "sessionId")) else c.pi_js_undefined());
    try scope.put(params, "prompt_cache_retention", if (long and supports_long) try scope.text("24h") else c.pi_js_undefined());
    if (!scope.equal(try scope.get(compat, "supportsUsageInStreaming"), c.pi_js_bool(engine.context, 0))) {
        const streaming = try scope.object();
        try scope.put(streaming, "include_usage", c.pi_js_bool(engine.context, 1));
        try scope.put(params, "stream_options", streaming);
    }
    if (scope.truthy(try scope.get(compat, "supportsStore"))) try scope.put(params, "store", c.pi_js_bool(engine.context, 0));
    if (scope.truthy(try v.optional(&scope, options, "maxTokens"))) try scope.put(params, if (try v.eq(&scope, try scope.get(compat, "maxTokensField"), "max_tokens")) "max_tokens" else "max_completion_tokens", try scope.get(options, "maxTokens"));
    if (!c.JS_IsUndefined(try v.optional(&scope, options, "temperature"))) try scope.put(params, "temperature", try scope.get(options, "temperature"));
    const request_tools = try scope.get(transcript_tools, "requestTools");
    if (try v.length(&scope, request_tools) > 0) {
        try scope.put(params, "tools", try scope.own(try tools.convert(engine, request_tools, compat)));
        if (scope.truthy(try scope.get(compat, "zaiToolStream"))) try scope.put(params, "tool_stream", c.pi_js_bool(engine.context, 1));
    } else if (try hasToolHistory(&scope, try scope.get(context, "messages"))) try scope.put(params, "tools", try scope.array());
    if (scope.truthy(control)) try applyCache(&scope, messages, try scope.get(params, "tools"), control);
    if (scope.truthy(try v.optional(&scope, options, "toolChoice"))) try scope.put(params, "tool_choice", try scope.get(options, "toolChoice"));
    if (!c.JS_IsUndefined(try scope.get(compat, "vllmPriority"))) try scope.put(params, "priority", try scope.get(compat, "vllmPriority"));
    try thinking(&scope, params, model, options, compat, simple);
    const model_compat = try scope.get(model, "compat");
    if (scope.truthy(try v.optional(&scope, model_compat, "openRouterRouting"))) try scope.put(params, "provider", try scope.get(try scope.get(model, "compat"), "openRouterRouting"));
    if (scope.truthy(try v.optional(&scope, model_compat, "vercelGatewayRouting"))) {
        const routing = try scope.get(try scope.get(model, "compat"), "vercelGatewayRouting");
        if (scope.truthy(try scope.get(routing, "only")) or scope.truthy(try scope.get(routing, "order"))) {
            const gateway = try scope.object();
            inline for (.{ "only", "order" }) |key| if (scope.truthy(try scope.get(routing, key))) {
                try scope.put(gateway, key, try scope.get(routing, key));
            };
            const provider_options = try scope.object();
            try scope.put(provider_options, "gateway", gateway);
            try scope.put(params, "providerOptions", provider_options);
        }
    }
    const effort = try v.optional(&scope, options, "reasoningEffort");
    const sampling = try scope.invoke(simple, "resolveSamplingParams", &.{ model, if (v.nullish(effort)) try scope.text("off") else effort, try v.optional(&scope, options, "samplingParams") });
    if (scope.truthy(sampling)) _ = try scope.invoke(try scope.global("Object"), "assign", &.{ params, sampling });
    return c.JS_DupValue(engine.context, params);
}
