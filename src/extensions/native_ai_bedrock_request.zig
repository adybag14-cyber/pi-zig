//! Actual Source5ab ConverseStreamCommand input builder over live JS values.
const v = @import("native_ai_provider_values.zig");
const Scope = v.Scope;
const c = v.c;
const codec = @import("native_ai_bedrock_messages.zig");
pub fn isClaude(scope: *Scope, model: c.JSValue) !bool {
    const id = try scope.invoke(try scope.get(model, "id"), "toLowerCase", &.{});
    const name = try scope.get(model, "name");
    const lower = if (v.nullish(name)) try scope.text("") else try scope.invoke(name, "toLowerCase", &.{});
    return scope.truthy(try scope.invoke(id, "includes", &.{try scope.text("anthropic.claude")})) or scope.truthy(try scope.invoke(id, "includes", &.{try scope.text("anthropic/claude")})) or scope.truthy(try scope.invoke(lower, "includes", &.{try scope.text("anthropic.claude")})) or scope.truthy(try scope.invoke(lower, "includes", &.{try scope.text("anthropic/claude")})) or scope.truthy(try scope.invoke(lower, "includes", &.{try scope.text("claude")}));
}
fn candidates(scope: *Scope, model: c.JSValue) !c.JSValue {
    const result = try scope.array();
    const values = try scope.array();
    _ = try scope.invoke(values, "push", &.{try scope.get(model, "id")});
    const name = try scope.get(model, "name");
    if (scope.truthy(name)) _ = try scope.invoke(values, "push", &.{name});
    var rows = try v.iterator(scope, values);
    defer rows.deinit();
    errdefer rows.closePreserving();
    while (try rows.next()) |value| {
        defer scope.engine.freeValue(value);
        const lower = try scope.invoke(value, "toLowerCase", &.{});
        const regex = try scope.own(try v.js.builtin(scope.engine, "RegExp", &.{ try scope.text("[\\s_.:]+"), try scope.text("g") }));
        _ = try scope.invoke(result, "push", &.{ lower, try scope.invoke(lower, "replace", &.{ regex, try scope.text("-") }) });
    }
    return result;
}
fn contains(scope: *Scope, values: c.JSValue, needle: []const u8) !bool {
    var rows = try v.iterator(scope, values);
    defer rows.deinit();
    errdefer rows.closePreserving();
    while (try rows.next()) |value| {
        defer scope.engine.freeValue(value);
        if (scope.truthy(try scope.invoke(value, "includes", &.{try scope.text(needle)}))) return true;
    }
    return false;
}
pub fn supportsAdaptive(scope: *Scope, model: c.JSValue) !bool {
    const refs = try candidates(scope, model);
    inline for (.{ "opus-4-6", "opus-4-7", "opus-4-8", "opus-5", "sonnet-4-6", "sonnet-5", "haiku-5", "fable-5" }) |needle| if (try contains(scope, refs, needle)) return true;
    return false;
}
fn nativeXhigh(scope: *Scope, model: c.JSValue) !bool {
    const refs = try candidates(scope, model);
    inline for (.{ "opus-4-7", "opus-4-8", "opus-5", "sonnet-5", "haiku-5", "fable-5" }) |needle| if (try contains(scope, refs, needle)) return true;
    return false;
}
fn env(scope: *Scope, name: []const u8, options: c.JSValue) !c.JSValue {
    const provider = try scope.own(try @import("native_ai_env_keys.zig").create(scope.engine, .{}));
    return scope.invoke(provider, "getProviderEnvValue", &.{ try scope.text(name), try v.optional(scope, options, "env") });
}
pub fn configuredRegion(scope: *Scope, options: c.JSValue) !c.JSValue {
    const explicit = try v.optional(scope, options, "region");
    if (scope.truthy(explicit)) return explicit;
    const region = try env(scope, "AWS_REGION", options);
    if (scope.truthy(region)) return region;
    return env(scope, "AWS_DEFAULT_REGION", options);
}
fn govCloud(scope: *Scope, model: c.JSValue, options: c.JSValue) !bool {
    const region = try configuredRegion(scope, options);
    if (scope.truthy(region) and scope.truthy(try scope.invoke(try scope.invoke(region, "toLowerCase", &.{}), "startsWith", &.{try scope.text("us-gov-")}))) return true;
    const id = try scope.invoke(try scope.get(model, "id"), "toLowerCase", &.{});
    return scope.truthy(try scope.invoke(id, "startsWith", &.{try scope.text("us-gov.")})) or scope.truthy(try scope.invoke(id, "startsWith", &.{try scope.text("arn:aws-us-gov:")}));
}
fn cacheSupported(scope: *Scope, model: c.JSValue, options: c.JSValue) !bool {
    const refs = try candidates(scope, model);
    if (!try contains(scope, refs, "claude")) return v.eq(scope, try env(scope, "AWS_BEDROCK_FORCE_CACHE", options), "1");
    inline for (.{ "fable-5", "opus-5", "sonnet-5", "haiku-5", "-4-", "claude-3-7-sonnet", "claude-3-5-haiku" }) |needle| if (try contains(scope, refs, needle)) return true;
    return false;
}
pub fn effort(scope: *Scope, model: c.JSValue, level: c.JSValue) !c.JSValue {
    if (try v.eq(scope, level, "xhigh") and try nativeXhigh(scope, model)) return scope.text("xhigh");
    const map = try scope.get(model, "thinkingLevelMap");
    const mapped = if (scope.truthy(level) and !v.nullish(map)) try scope.own(try v.js.getKey(scope.engine, map, level)) else c.pi_js_undefined();
    if (c.JS_IsString(mapped)) return mapped;
    return scope.text(if (try v.eq(scope, level, "minimal") or try v.eq(scope, level, "low")) "low" else if (try v.eq(scope, level, "medium")) "medium" else "high");
}
fn fields(scope: *Scope, model: c.JSValue, options: c.JSValue) !c.JSValue {
    const level = try v.optional(scope, options, "reasoning");
    if (!scope.truthy(level) or !scope.truthy(try scope.get(model, "reasoning"))) return c.pi_js_undefined();
    const result = try scope.object();
    if (try isClaude(scope, model)) {
        const gov = try govCloud(scope, model, options);
        const adaptive = try supportsAdaptive(scope, model);
        const binding = !gov and try nativeXhigh(scope, model);
        const thinking = try scope.object();
        try scope.put(thinking, "type", try scope.text(if (adaptive) "adaptive" else "enabled"));
        if (!gov) {
            const display = try v.optional(scope, options, "thinkingDisplay");
            try scope.put(thinking, "display", if (v.nullish(display)) try scope.text("summarized") else display);
        }
        if (adaptive) {
            if (binding) {
                const controls = try scope.object();
                try scope.put(controls, "prefix_mismatch_behavior", try scope.text("drop_block"));
                try scope.put(thinking, "block_binding", controls);
                const features = try scope.array();
                _ = try scope.invoke(features, "push", &.{try scope.text("thinking-binding-controls-2026-08-01")});
                try scope.put(result, "anthropic_beta", features);
            }
            const output = try scope.object();
            try scope.put(output, "effort", try effort(scope, model, level));
            try scope.put(result, "output_config", output);
        } else {
            const clamped = if (try v.eq(scope, level, "xhigh") or try v.eq(scope, level, "max")) try scope.text("high") else level;
            const budgets = try v.optional(scope, options, "thinkingBudgets");
            var budget = if (v.nullish(budgets)) c.pi_js_undefined() else try scope.own(try v.js.getKey(scope.engine, budgets, clamped));
            if (v.nullish(budget)) {
                const defaults = try scope.object();
                inline for (.{ .{ "minimal", 1024 }, .{ "low", 2048 }, .{ "medium", 8192 }, .{ "high", 16384 }, .{ "xhigh", 16384 }, .{ "max", 16384 } }) |pair| try scope.put(defaults, pair[0], c.JS_NewInt32(scope.engine.context, pair[1]));
                budget = try scope.own(try v.js.getKey(scope.engine, defaults, level));
            }
            try scope.put(thinking, "budget_tokens", budget);
            const interleaved = try v.optional(scope, options, "interleavedThinking");
            if (v.nullish(interleaved) or scope.truthy(interleaved)) {
                const features = try scope.array();
                _ = try scope.invoke(features, "push", &.{try scope.text("interleaved-thinking-2025-05-14")});
                try scope.put(result, "anthropic_beta", features);
            }
        }
        try scope.put(result, "thinking", thinking);
        return result;
    }
    const refs = try candidates(scope, model);
    if (try contains(scope, refs, "gpt-oss")) {
        const levels = try scope.object();
        inline for (.{ .{ "minimal", "low" }, .{ "low", "low" }, .{ "medium", "medium" }, .{ "high", "high" }, .{ "xhigh", "high" }, .{ "max", "high" } }) |pair| try scope.put(levels, pair[0], try scope.text(pair[1]));
        try scope.put(result, "reasoning_effort", try scope.own(try v.js.getKey(scope.engine, levels, level)));
        return result;
    }
    if (try contains(scope, refs, "gpt-")) {
        const reasoning = try scope.object();
        const map = try scope.get(model, "thinkingLevelMap");
        const mapped = if (v.nullish(map)) c.pi_js_undefined() else try scope.own(try v.js.getKey(scope.engine, map, level));
        const levels = try scope.object();
        inline for (.{ .{ "minimal", "low" }, .{ "low", "low" }, .{ "medium", "medium" }, .{ "high", "high" }, .{ "xhigh", "xhigh" }, .{ "max", "max" } }) |pair| try scope.put(levels, pair[0], try scope.text(pair[1]));
        try scope.put(reasoning, "effort", if (c.JS_IsString(mapped)) mapped else try scope.own(try v.js.getKey(scope.engine, levels, level)));
        try scope.put(result, "reasoning", reasoning);
        return result;
    }
    return c.pi_js_undefined();
}
fn toolConfig(scope: *Scope, tools: c.JSValue, choice: c.JSValue, supported: bool) !c.JSValue {
    if (v.nullish(tools) or try v.length(scope, tools) == 0 or try v.eq(scope, choice, "none")) return c.pi_js_undefined();
    const converted = try scope.array();
    var rows = try v.iterator(scope, tools);
    defer rows.deinit();
    errdefer rows.closePreserving();
    while (try rows.next()) |tool| {
        defer scope.engine.freeValue(tool);
        const config = try scope.get(tool, "constrainedSampling");
        var strict = false;
        if (scope.truthy(config) and try v.eq(scope, try scope.get(config, "type"), "json_schema")) {
            var reason = try scope.text("strict tools are unsupported");
            if (supported) strict = validation: {
                _ = @import("native_ai_constrained_sampling.zig").makeStrict(scope, try scope.get(tool, "parameters"), &reason, null) catch |err| {
                    if (err != error.UnsupportedStrictJsonSchema) return err;
                    if (try v.eq(scope, try scope.get(config, "strict"), "require")) return strictError(scope, tool, reason);
                    break :validation false;
                };
                break :validation true;
            } else if (try v.eq(scope, try scope.get(config, "strict"), "require")) return strictError(scope, tool, reason);
        }
        {
            const definition = try scope.object();
            const spec = try scope.object();
            try scope.put(spec, "name", try scope.get(tool, "name"));
            try scope.put(spec, "description", try scope.get(tool, "description"));
            const schema = try scope.object();
            var reason = c.pi_js_undefined();
            try scope.put(schema, "json", if (strict) try @import("native_ai_constrained_sampling.zig").makeStrict(scope, try scope.get(tool, "parameters"), &reason, null) else try scope.get(tool, "parameters"));
            try scope.put(spec, "inputSchema", schema);
            if (strict) try scope.put(spec, "strict", c.pi_js_bool(scope.engine.context, 1));
            try scope.put(definition, "toolSpec", spec);
            _ = try scope.invoke(converted, "push", &.{definition});
        }
    }
    const result = try scope.object();
    try scope.put(result, "tools", converted);
    var selected = c.pi_js_undefined();
    if (try v.eq(scope, choice, "auto") or try v.eq(scope, choice, "any")) {
        selected = try scope.object();
        try scope.put(selected, if (try v.eq(scope, choice, "auto")) "auto" else "any", try scope.object());
    } else if (scope.truthy(choice) and try v.eq(scope, try scope.get(choice, "type"), "tool")) {
        selected = try scope.object();
        const named = try scope.object();
        try scope.put(named, "name", try scope.get(choice, "name"));
        try scope.put(selected, "tool", named);
    }
    try scope.put(result, "toolChoice", selected);
    return result;
}
fn strictError(scope: *Scope, tool: c.JSValue, reason: c.JSValue) anyerror {
    return v.errorText(scope, try scope.concat(try scope.concat(try scope.concat(try scope.concat(try scope.text("Tool \""), try scope.stringify(try scope.get(tool, "name"))), try scope.text("\" requires JSON-schema constrained sampling, but ")), reason), try scope.text(".")));
}
pub fn build(engine: *v.em.Engine, model: c.JSValue, context: c.JSValue, options: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const retained = try @import("native_ai_provider_request.zig").retention(&scope, options);
    const caching = try cacheSupported(&scope, model, options);
    const claude = try isClaude(&scope, model);
    const result = try scope.object();
    try scope.put(result, "modelId", try scope.get(model, "id"));
    try scope.put(result, "messages", try scope.own(try codec.convert(engine, context, model, retained, caching, claude)));
    const original = try scope.get(context, "messages");
    const first = if (try v.length(&scope, original) > 0) try v.at(&scope, original, 0) else c.pi_js_undefined();
    var system = c.pi_js_undefined();
    if (!c.JS_IsUndefined(first) and try v.eq(&scope, try scope.get(first, "role"), "system")) {
        const prompt = try scope.own(try @import("native_ai_text.zig").system(engine, first, false));
        if (scope.truthy(prompt)) {
            system = try scope.array();
            const block = try scope.object();
            try scope.put(block, "text", try v.sanitize(&scope, prompt));
            _ = try scope.invoke(system, "push", &.{block});
            if (!try v.eq(&scope, retained, "none") and caching) _ = try scope.invoke(system, "push", &.{try codec.cachePoint(&scope, retained)});
        }
    }
    try scope.put(result, "system", system);
    const inference = try scope.object();
    const max = try v.optional(&scope, options, "maxTokens");
    const effective = if (v.nullish(max) and claude) try scope.get(model, "maxTokens") else max;
    if (!c.JS_IsUndefined(effective)) try scope.put(inference, "maxTokens", effective);
    const temperature = try v.optional(&scope, options, "temperature");
    if (!c.JS_IsUndefined(temperature)) try scope.put(inference, "temperature", temperature);
    try scope.put(result, "inferenceConfig", inference);
    const raw_compat = try scope.get(model, "compat");
    const configured_strict = try v.optional(&scope, raw_compat, "supportsStrictMode");
    try scope.put(result, "toolConfig", try toolConfig(&scope, try scope.own(try @import("native_agent_tool_changes.zig").currentTools(engine, original)), try v.optional(&scope, options, "toolChoice"), !v.nullish(configured_strict) and scope.truthy(configured_strict)));
    try scope.put(result, "additionalModelRequestFields", try fields(&scope, model, options));
    const metadata = try v.optional(&scope, options, "requestMetadata");
    if (!c.JS_IsUndefined(metadata)) try scope.put(result, "requestMetadata", metadata);
    return c.JS_DupValue(engine.context, result);
}
