//! Actual Google SDK-facing parameters and their REST wire conversion.
const v = @import("native_ai_provider_values.zig");
const Scope = v.Scope;
const c = v.c;
pub fn usesLevel(scope: *Scope, model: c.JSValue) !bool {
    const id = try scope.invoke(try scope.get(model, "id"), "toLowerCase", &.{});
    const regex = try scope.own(try v.js.builtin(scope.engine, "RegExp", &.{try scope.text("gemini-3(?:\\.\\d+)?-(?:pro|flash)|gemini-(?:[4-9]|[1-9]\\d)|gemma-?4")}));
    return scope.truthy(try scope.invoke(regex, "test", &.{id})) or try v.eq(scope, id, "gemini-flash-latest") or try v.eq(scope, id, "gemini-flash-lite-latest");
}
fn level(scope: *Scope, model: c.JSValue, input: c.JSValue) !c.JSValue {
    const map = try scope.get(model, "thinkingLevelMap");
    const mapped = if (v.nullish(map)) c.pi_js_undefined() else try scope.own(try v.js.getKey(scope.engine, map, input));
    const resolved = if (c.JS_IsString(mapped)) try scope.invoke(mapped, "toLowerCase", &.{}) else input;
    inline for (.{ "minimal", "low", "medium", "high" }) |name| if (try v.eq(scope, resolved, name)) return scope.invoke(resolved, "toUpperCase", &.{});
    var message = try scope.concat(try scope.text("Unsupported Google thinking level mapping for "), try scope.stringify(try scope.get(model, "provider")));
    message = try scope.concat(try scope.concat(message, try scope.text("/")), try scope.stringify(try scope.get(model, "id")));
    message = try scope.concat(try scope.concat(message, try scope.text(": ")), try scope.stringify(input));
    return v.errorText(scope, try scope.concat(try scope.concat(message, try scope.text(" -> ")), try scope.stringify(mapped)));
}
pub fn simple(scope: *Scope, dependencies: c.JSValue, model: c.JSValue, context: c.JSValue, input: c.JSValue, vertex: bool) !c.JSValue {
    const base = try scope.invoke(try scope.get(dependencies, "simple"), "buildBaseOptions", &.{ model, context, input, try v.optional(scope, input, "apiKey") });
    const result = try v.spread(scope, base);
    try scope.put(result, "toolChoice", try v.optional(scope, input, "toolChoice"));
    const thinking = try scope.object();
    const reasoning = try v.optional(scope, input, "reasoning");
    const clamped = if (scope.truthy(reasoning)) try scope.invoke(try scope.get(dependencies, "thinking"), "clampThinkingLevel", &.{ model, reasoning }) else try scope.text("off");
    const enabled = !try v.eq(scope, clamped, "off");
    try scope.put(thinking, "enabled", c.pi_js_bool(scope.engine.context, @intFromBool(enabled)));
    if (enabled) {
        const resolved = try level(scope, model, clamped);
        if (try usesLevel(scope, model)) try scope.put(thinking, "level", resolved) else {
            const key = try scope.invoke(resolved, "toLowerCase", &.{});
            const budgets = try v.optional(scope, input, "thinkingBudgets");
            const override = if (v.nullish(budgets)) c.pi_js_undefined() else try scope.own(try v.js.getKey(scope.engine, budgets, key));
            var budget: i32 = -1;
            if (c.JS_IsUndefined(override)) {
                const id = try scope.get(model, "id");
                const pro = scope.truthy(try scope.invoke(id, "includes", &.{try scope.text("2.5-pro")}));
                const flash = scope.truthy(try scope.invoke(id, "includes", &.{try scope.text("2.5-flash")}));
                const lite = !vertex and scope.truthy(try scope.invoke(id, "includes", &.{try scope.text("2.5-flash-lite")}));
                if (pro or flash) budget = if (try v.eq(scope, key, "minimal")) (if (lite) 512 else 128) else if (try v.eq(scope, key, "low")) 2048 else if (try v.eq(scope, key, "medium")) 8192 else if (pro) 32768 else 24576;
            }
            try scope.put(thinking, "budgetTokens", if (!c.JS_IsUndefined(override)) override else c.JS_NewInt32(scope.engine.context, budget));
        }
    }
    try scope.put(result, "thinking", thinking);
    return result;
}
pub fn build(engine: *v.em.Engine, dependencies: c.JSValue, model: c.JSValue, context: c.JSValue, options: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const result = try scope.object();
    try scope.put(result, "model", try scope.get(model, "id"));
    try scope.put(result, "contents", try scope.own(try @import("native_ai_google_messages.zig").convert(engine, model, context)));
    const config = try scope.object();
    inline for (.{ .{ "temperature", "temperature" }, .{ "maxTokens", "maxOutputTokens" } }) |pair| {
        const value = try v.optional(&scope, options, pair[0]);
        if (!c.JS_IsUndefined(value)) try scope.put(config, pair[1], value);
    }
    const messages = try scope.get(context, "messages");
    if (try v.length(&scope, messages) > 0) {
        const first = try v.at(&scope, messages, 0);
        if (try v.eq(&scope, try scope.get(first, "role"), "system")) {
            const prompt = try scope.invoke(try scope.get(dependencies, "text"), "getSystemMessageText", &.{first});
            if (scope.truthy(prompt)) try scope.put(config, "systemInstruction", try v.sanitize(&scope, prompt));
        }
    }
    const tools = try scope.own(try @import("native_agent_tool_changes.zig").currentTools(engine, messages));
    if (try v.length(&scope, tools) > 0) {
        const strict = (try @import("native_ai_google_messages.zig").family(&scope, model)).strict;
        const compat = try scope.object();
        try scope.put(compat, "supportsStrictMode", c.pi_js_bool(engine.context, @intFromBool(strict)));
        const converted = try scope.own(try @import("native_ai_openai_tools.zig").convert(engine, tools, compat));
        const declarations = try scope.array();
        var has_strict = false;
        var rows = try v.iterator(&scope, converted);
        defer rows.deinit();
        errdefer rows.closePreserving();
        while (try rows.next()) |tool| {
            defer engine.freeValue(tool);
            var row: Scope = .{ .engine = engine };
            defer row.deinit();
            const body = try row.get(tool, "function");
            const declaration = try row.object();
            inline for (.{ "name", "description" }) |key| try row.put(declaration, key, try row.get(body, key));
            try row.put(declaration, "parametersJsonSchema", try row.get(body, "parameters"));
            if (row.equal(try row.get(body, "strict"), c.pi_js_bool(engine.context, 1))) has_strict = true;
            _ = try row.invoke(declarations, "push", &.{declaration});
        }
        const group = try scope.object();
        try scope.put(group, "functionDeclarations", declarations);
        const groups = try scope.array();
        _ = try scope.invoke(groups, "push", &.{group});
        try scope.put(config, "tools", groups);
        const choice = try v.optional(&scope, options, "toolChoice");
        const mode: ?[]const u8 = if (try v.eq(&scope, choice, "none")) "NONE" else if (try v.eq(&scope, choice, "any")) "ANY" else if (has_strict) "VALIDATED" else if (scope.truthy(choice)) "AUTO" else null;
        if (mode) |value| {
            const function = try scope.object();
            try scope.put(function, "mode", try scope.text(value));
            const tool_config = try scope.object();
            try scope.put(tool_config, "functionCallingConfig", function);
            try scope.put(config, "toolConfig", tool_config);
        }
    }
    const thinking = try v.optional(&scope, options, "thinking");
    if (scope.truthy(try scope.get(model, "reasoning")) and !v.nullish(thinking)) {
        const settings = try scope.object();
        if (scope.truthy(try scope.get(thinking, "enabled"))) {
            try scope.put(settings, "includeThoughts", c.pi_js_bool(engine.context, 1));
            const value = try scope.get(thinking, "level");
            const budget = try scope.get(thinking, "budgetTokens");
            if (!c.JS_IsUndefined(value)) try scope.put(settings, "thinkingLevel", value) else if (!c.JS_IsUndefined(budget)) try scope.put(settings, "thinkingBudget", budget);
        } else {
            const fallback = if (try usesLevel(&scope, model)) try scope.invoke(try scope.get(dependencies, "thinking"), "clampThinkingLevel", &.{ model, try scope.text("off") }) else try scope.text("off");
            if (try v.eq(&scope, fallback, "off")) try scope.put(settings, "thinkingBudget", c.JS_NewInt32(engine.context, 0)) else try scope.put(settings, "thinkingLevel", try level(&scope, model, fallback));
        }
        try scope.put(config, "thinkingConfig", settings);
    }
    const signal = try v.optional(&scope, options, "signal");
    if (scope.truthy(signal)) {
        if (scope.truthy(try scope.get(signal, "aborted"))) return v.errorText(&scope, try scope.text("Request aborted"));
        try scope.put(config, "abortSignal", signal);
    }
    try scope.put(result, "config", config);
    return c.JS_DupValue(engine.context, result);
}
pub fn wire(scope: *Scope, params: c.JSValue) !c.JSValue {
    const result = try scope.object();
    try scope.put(result, "contents", try scope.get(params, "contents"));
    const config = try scope.get(params, "config");
    const generation = try v.spread(scope, config);
    inline for (.{ "abortSignal", "tools", "toolConfig", "systemInstruction" }) |key| try v.remove(scope, generation, key);
    if (try v.length(scope, try scope.invoke(try scope.global("Object"), "keys", &.{generation})) > 0) try scope.put(result, "generationConfig", generation);
    inline for (.{ "tools", "toolConfig" }) |key| {
        const value = try v.optional(scope, config, key);
        if (!c.JS_IsUndefined(value)) try scope.put(result, key, value);
    }
    const instruction = try v.optional(scope, config, "systemInstruction");
    if (c.JS_IsString(instruction)) {
        const system = try scope.object();
        const parts = try scope.array();
        const part = try scope.object();
        try scope.put(part, "text", instruction);
        _ = try scope.invoke(parts, "push", &.{part});
        try scope.put(system, "parts", parts);
        try scope.put(system, "role", try scope.text("user"));
        try scope.put(result, "systemInstruction", system);
    } else if (!c.JS_IsUndefined(instruction)) try scope.put(result, "systemInstruction", instruction);
    return result;
}
