//! Actual Source5ab Anthropic Messages request builder, with native effort updates.
const v = @import("native_ai_provider_values.zig");
const Scope = v.Scope;
const c = v.c;
const messages = @import("native_ai_anthropic_messages.zig");
pub fn compat(engine: *v.em.Engine, model: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const configured = try scope.get(model, "compat");
    const router = try v.eq(&scope, try scope.get(model, "provider"), "openrouter") or scope.truthy(try scope.invoke(try scope.get(model, "baseUrl"), "includes", &.{try scope.text("openrouter.ai")}));
    const result = try scope.object();
    inline for (.{ .{ "supportsEagerToolInputStreaming", true }, .{ "supportsLongCacheRetention", true }, .{ "sendSessionAffinityHeaders", router }, .{ "supportsCacheControlOnTools", true }, .{ "supportsTemperature", true }, .{ "allowEmptySignature", false }, .{ "supportsStrictTools", false }, .{ "supportsMidConvoSystemMessages", false }, .{ "supportsMidConvoToolChanges", false } }) |entry| {
        const value = try v.optional(&scope, configured, entry[0]);
        try scope.put(result, entry[0], if (v.nullish(value)) c.pi_js_bool(engine.context, @intFromBool(entry[1])) else value);
    }
    const format = try v.optional(&scope, configured, "sessionAffinityFormat");
    try scope.put(result, "sessionAffinityFormat", if (v.nullish(format) and router) try scope.text("openrouter") else format);
    return c.JS_DupValue(engine.context, result);
}
fn beta(scope: *Scope, model: c.JSValue, options: c.JSValue, oauth: bool, native_tools: bool, current_tools: c.JSValue, compatibility: c.JSValue) !c.JSValue {
    var configured = c.pi_js_undefined();
    for ([_]c.JSValue{ try scope.get(model, "headers"), try v.optional(scope, options, "headers") }) |headers| {
        const entries = try scope.invoke(try scope.global("Object"), "entries", &.{if (v.nullish(headers)) try scope.object() else headers});
        var rows = try v.iterator(scope, entries);
        defer rows.deinit();
        errdefer rows.closePreserving();
        while (try rows.next()) |entry| {
            defer scope.engine.freeValue(entry);
            if (try v.eq(scope, try scope.invoke(try v.at(scope, entry, 0), "toLowerCase", &.{}), "anthropic-beta")) configured = try v.at(scope, entry, 1);
        }
    }
    const result = try scope.array();
    if (c.JS_IsNull(configured)) return result;
    if (!c.JS_IsUndefined(configured)) {
        const seen = try scope.own(try v.js.builtin(scope.engine, "Set", &.{}));
        var rows = try v.iterator(scope, try scope.invoke(configured, "split", &.{try scope.text(",")}));
        defer rows.deinit();
        errdefer rows.closePreserving();
        while (try rows.next()) |entry| {
            defer scope.engine.freeValue(entry);
            const value = try scope.invoke(entry, "trim", &.{});
            if (try v.length(scope, value) > 0 and !scope.truthy(try scope.invoke(seen, "has", &.{value}))) {
                _ = try scope.invoke(seen, "add", &.{value});
                _ = try scope.invoke(result, "push", &.{value});
            }
        }
        return result;
    }
    if (oauth) _ = try scope.invoke(result, "push", &.{ try scope.text("claude-code-20250219"), try scope.text("oauth-2025-04-20") });
    if (try v.length(scope, current_tools) > 0 and !scope.truthy(try scope.get(compatibility, "supportsEagerToolInputStreaming"))) _ = try scope.invoke(result, "push", &.{try scope.text("fine-grained-tool-streaming-2025-05-14")});
    const raw_compat = try scope.get(model, "compat");
    const enabled = try v.optional(scope, options, "thinkingEnabled");
    const interleaved = try v.optional(scope, options, "interleavedThinking");
    if (scope.truthy(try scope.get(model, "reasoning")) and scope.equal(enabled, c.pi_js_bool(scope.engine.context, 1)) and (v.nullish(interleaved) or scope.truthy(interleaved)) and !scope.equal(try v.optional(scope, raw_compat, "forceAdaptiveThinking"), c.pi_js_bool(scope.engine.context, 1))) _ = try scope.invoke(result, "push", &.{try scope.text("interleaved-thinking-2025-05-14")});
    const fallbacks = try v.optional(scope, raw_compat, "allowedFallbackModels");
    if (!v.nullish(fallbacks) and try v.length(scope, fallbacks) > 0) _ = try scope.invoke(result, "push", &.{try scope.text("server-side-fallback-2026-07-01")});
    if (scope.equal(try v.optional(scope, raw_compat, "supportsMidConvoEffort"), c.pi_js_bool(scope.engine.context, 1))) _ = try scope.invoke(result, "push", &.{ try scope.text("mid-conversation-output-config-2026-07-01"), try scope.text("thinking-binding-controls-2026-08-01") });
    if (native_tools) _ = try scope.invoke(result, "push", &.{try scope.text("inline-tools-2026-09-15")});
    return result;
}
pub fn build(engine: *v.em.Engine, model: c.JSValue, context: c.JSValue, oauth: bool, options: c.JSValue, disable_preferred: bool) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const compatibility = try scope.own(try compat(engine, model));
    const original = try scope.get(context, "messages");
    var initial = c.pi_js_undefined();
    if (try v.length(&scope, original) > 0) {
        const first = try v.at(&scope, original, 0);
        if (try v.eq(&scope, try scope.get(first, "role"), "system")) initial = first;
    }
    const initial_text = if (c.JS_IsUndefined(initial)) try scope.text("") else try scope.own(try @import("native_ai_text.zig").system(engine, initial, false));
    const transformed = try scope.own(try @import("native_ai_transform_messages.zig").transform(engine, original, model, try scope.own(try @import("native_ai_provider_request.zig").normalizeId(engine))));
    const conversation = if (c.JS_IsUndefined(initial)) transformed else try scope.invoke(transformed, "slice", &.{c.JS_NewInt32(engine.context, 1)});
    var initial_tools = try v.optional(&scope, initial, "toolsAdded");
    if (v.nullish(initial_tools)) initial_tools = try scope.array();
    const native_tools = scope.truthy(try scope.get(compatibility, "supportsMidConvoSystemMessages")) and scope.truthy(try scope.get(compatibility, "supportsMidConvoToolChanges")) and try v.length(&scope, initial_tools) > 0;
    const enabled = try v.optional(&scope, options, "thinkingEnabled");
    const off_entry = try v.optional(&scope, try scope.get(model, "thinkingLevelMap"), "off");
    const disabled = scope.truthy(try scope.get(model, "reasoning")) and scope.equal(enabled, c.pi_js_bool(engine.context, 0)) and !c.JS_IsNull(off_entry);
    const raw_compat = try scope.get(model, "compat");
    const managed = scope.equal(try v.optional(&scope, raw_compat, "supportsMidConvoEffort"), c.pi_js_bool(engine.context, 1)) and !disabled;
    const retained = try @import("native_ai_provider_request.zig").retention(&scope, options);
    var cache = c.pi_js_undefined();
    if (!try v.eq(&scope, retained, "none")) {
        cache = try scope.object();
        try scope.put(cache, "type", try scope.text("ephemeral"));
        if (try v.eq(&scope, retained, "long") and scope.truthy(try scope.get(compatibility, "supportsLongCacheRetention"))) try scope.put(cache, "ttl", try scope.text("1h"));
    }
    const tool_cache = if (scope.truthy(try scope.get(compatibility, "supportsCacheControlOnTools"))) cache else c.pi_js_undefined();
    const converter = try scope.own(try @import("native_ai_anthropic_tools.zig").converter(engine, oauth, compatibility, c.pi_js_undefined(), disable_preferred));
    const converted = try scope.own(try messages.convert(engine, conversation, oauth, cache, scope.truthy(try scope.get(compatibility, "allowEmptySignature")), if (managed) try scope.get(model, "provider") else c.pi_js_undefined(), if (native_tools) converter else c.pi_js_undefined()));
    const active = try v.optional(&scope, options, "effort");
    const effort = if (v.nullish(active)) try scope.text("high") else active;
    const params = try scope.object();
    try scope.put(params, "model", try scope.get(model, "id"));
    try scope.put(params, "messages", if (managed) try messages.insertEffort(&scope, converted, effort) else try scope.get(converted, "messages"));
    const max_tokens = try v.optional(&scope, options, "maxTokens");
    try scope.put(params, "max_tokens", if (v.nullish(max_tokens)) try scope.get(model, "maxTokens") else max_tokens);
    try scope.put(params, "stream", c.pi_js_bool(engine.context, 1));
    const current_tools = try scope.own(try @import("native_agent_tool_changes.zig").currentTools(engine, original));
    const features = try beta(&scope, model, options, oauth, native_tools, current_tools, compatibility);
    if (try v.length(&scope, features) > 0) try scope.put(params, "betas", features);
    const system = try scope.array();
    if (oauth) {
        const identity = try messages.text(&scope, try scope.text("You are Claude Code, Anthropic's official CLI for Claude."));
        if (!c.JS_IsUndefined(cache)) try scope.put(identity, "cache_control", cache);
        _ = try scope.invoke(system, "push", &.{identity});
    }
    if (scope.truthy(initial_text)) {
        const block = try messages.text(&scope, initial_text);
        if (!c.JS_IsUndefined(cache)) try scope.put(block, "cache_control", cache);
        _ = try scope.invoke(system, "push", &.{block});
    }
    if (try v.length(&scope, system) > 0) try scope.put(params, "system", system);
    const temperature = try v.optional(&scope, options, "temperature");
    if (!c.JS_IsUndefined(temperature) and !scope.truthy(enabled) and !scope.equal(try v.optional(&scope, raw_compat, "supportsMidConvoEffort"), c.pi_js_bool(engine.context, 1)) and scope.truthy(try scope.get(compatibility, "supportsTemperature"))) try scope.put(params, "temperature", temperature);
    const request_tools = if (native_tools) initial_tools else current_tools;
    const tools_converter = try scope.own(try @import("native_ai_anthropic_tools.zig").converter(engine, oauth, compatibility, tool_cache, disable_preferred));
    const tools = try scope.call(tools_converter, c.pi_js_undefined(), &.{request_tools});
    if (native_tools) _ = try scope.invoke(tools, "push", &.{try @import("native_ai_anthropic_tools.zig").placeholder(&scope)});
    if (try v.length(&scope, tools) > 0) try scope.put(params, "tools", tools);
    const thinking = try scope.object();
    if (disabled) {
        try scope.put(thinking, "type", try scope.text("disabled"));
        try scope.put(params, "thinking", thinking);
    } else if (managed or (scope.truthy(try scope.get(model, "reasoning")) and scope.truthy(enabled))) {
        const adaptive = managed or scope.equal(try v.optional(&scope, raw_compat, "forceAdaptiveThinking"), c.pi_js_bool(engine.context, 1));
        try scope.put(thinking, "type", try scope.text(if (adaptive) "adaptive" else "enabled"));
        const display = try v.optional(&scope, options, "thinkingDisplay");
        try scope.put(thinking, "display", if (v.nullish(display)) try scope.text("summarized") else display);
        if (managed) {
            const binding = try scope.object();
            try scope.put(binding, "prefix_mismatch_behavior", try scope.text("drop_block"));
            try scope.put(thinking, "block_binding", binding);
        } else if (!adaptive) {
            const budget = try v.optional(&scope, options, "thinkingBudgetTokens");
            try scope.put(thinking, "budget_tokens", if (scope.truthy(budget)) budget else c.JS_NewInt32(engine.context, 1024));
        }
        try scope.put(params, "thinking", thinking);
        if (managed or (adaptive and scope.truthy(active))) {
            const config = try scope.object();
            try scope.put(config, "effort", if (managed) try scope.text("high") else active);
            try scope.put(params, "output_config", config);
        }
    }
    const user_id = try v.optional(&scope, try v.optional(&scope, options, "metadata"), "user_id");
    if (c.JS_IsString(user_id)) {
        const metadata = try scope.object();
        try scope.put(metadata, "user_id", user_id);
        try scope.put(params, "metadata", metadata);
    }
    const choice = try v.optional(&scope, options, "toolChoice");
    if (scope.truthy(choice)) {
        const value = if (c.JS_IsString(choice)) try scope.object() else choice;
        if (c.JS_IsString(choice)) try scope.put(value, "type", choice);
        try scope.put(params, "tool_choice", value);
    }
    const fallback_models = try v.optional(&scope, raw_compat, "allowedFallbackModels");
    if (!v.nullish(fallback_models) and try v.length(&scope, fallback_models) > 0) {
        const fallbacks = try scope.array();
        var rows = try v.iterator(&scope, fallback_models);
        defer rows.deinit();
        errdefer rows.closePreserving();
        while (try rows.next()) |entry| {
            defer engine.freeValue(entry);
            const result = try scope.object();
            try scope.put(result, "model", try scope.get(entry, "model"));
            _ = try scope.invoke(fallbacks, "push", &.{result});
        }
        try scope.put(params, "fallbacks", fallbacks);
    }
    const result = try scope.object();
    try scope.put(result, "params", params);
    try scope.put(result, "hasPreferredStrictTools", try @import("native_ai_anthropic_tools.zig").hasPreferred(&scope, request_tools, tools));
    try scope.put(result, "providerThinkingLevel", if (managed) effort else c.pi_js_undefined());
    return c.JS_DupValue(engine.context, result);
}
