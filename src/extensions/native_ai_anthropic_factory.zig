//! Actual Anthropic stream facade. Native continuations retain callback/value identity.
//! Direct wire uses native HTTP; supplied SDK clients and fetch remain guest values.
const std = @import("std");
const v = @import("native_ai_provider_values.zig");
const Scope = v.Scope;
const c = v.c;
const flow = @import("native_agent_async.zig");
const request = @import("native_ai_anthropic_request.zig");
const sse = @import("native_ai_anthropic_sse.zig");
const Stage = enum(c_int) { payload, ready, response, read, event, raw, rejected_body };
pub fn create(engine: *v.em.Engine) !c.JSValue {
    try @import("native_stream.zig").install(engine);
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const dependencies = try scope.object();
    const thinking = try scope.own(try @import("native_ai_thinking.zig").create(engine));
    const estimate = try scope.own(try @import("native_ai_estimate.zig").create(engine));
    try scope.put(dependencies, "simple", try scope.own(try @import("native_ai_simple_options.zig").create(engine, try scope.get(thinking, "clampThinkingLevel"), try scope.get(estimate, "estimateContextTokens"))));
    try scope.put(dependencies, "json", try scope.own(try @import("native_ai_json_parse.zig").create(engine)));
    try scope.put(dependencies, "errors", try scope.own(try @import("native_ai_anthropic_api_error.zig").create(engine)));
    const result = try scope.object();
    inline for (.{ "stream", "streamSimple" }, 0..) |name, index| {
        const Adapter = struct {
            fn call(host: *v.em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
                return stream(host, roots[0], if (args.len > 0) args[0] else c.pi_js_undefined(), if (args.len > 1) args[1] else c.pi_js_undefined(), if (args.len > 2) args[2] else c.pi_js_undefined(), index == 1);
            }
        };
        try scope.put(result, name, try scope.own(try @import("native_node_function.zig").create(engine, name, 3, Adapter.call, &.{dependencies})));
    }
    return c.JS_DupValue(engine.context, result);
}
fn auth(scope: *Scope, model: c.JSValue, options: c.JSValue) !void {
    if (scope.truthy(try v.optional(scope, options, "apiKey"))) return;
    const headers = try v.optional(scope, options, "headers");
    if (scope.truthy(headers)) {
        var rows = try v.iterator(scope, try scope.invoke(try scope.global("Object"), "entries", &.{headers}));
        defer rows.deinit();
        errdefer rows.closePreserving();
        while (try rows.next()) |entry| {
            defer scope.engine.freeValue(entry);
            const name = try scope.invoke(try v.at(scope, entry, 0), "toLowerCase", &.{});
            const value = try v.at(scope, entry, 1);
            if ((try v.eq(scope, name, "authorization") or try v.eq(scope, name, "x-api-key") or try v.eq(scope, name, "cf-aig-authorization")) and !c.JS_IsNull(value) and try v.length(scope, try scope.invoke(value, "trim", &.{})) > 0) return;
        }
    }
    return v.errorText(scope, try scope.concat(try scope.text("No API key for provider: "), try scope.stringify(try scope.get(model, "provider"))));
}
fn simple(scope: *Scope, dependencies: c.JSValue, model: c.JSValue, context: c.JSValue, options: c.JSValue) !c.JSValue {
    try auth(scope, model, options);
    const helpers = try scope.get(dependencies, "simple");
    const base = try scope.invoke(helpers, "buildBaseOptions", &.{ model, context, options, try v.optional(scope, options, "apiKey") });
    const result = try v.spread(scope, base);
    try scope.put(result, "toolChoice", try v.optional(scope, options, "toolChoice"));
    const level = try v.optional(scope, options, "reasoning");
    try scope.put(result, "thinkingEnabled", c.pi_js_bool(scope.engine.context, @intFromBool(scope.truthy(level))));
    if (!scope.truthy(level)) return result;
    if (scope.equal(try v.optional(scope, try scope.get(model, "compat"), "forceAdaptiveThinking"), c.pi_js_bool(scope.engine.context, 1))) {
        const mapped = try v.optional(scope, model, "thinkingLevelMap");
        const value = if (v.nullish(mapped)) c.pi_js_undefined() else try scope.own(try v.js.getKey(scope.engine, mapped, level));
        try scope.put(result, "effort", if (c.JS_IsString(value)) value else if (try v.eq(scope, level, "minimal") or try v.eq(scope, level, "low")) try scope.text("low") else if (try v.eq(scope, level, "medium")) try scope.text("medium") else try scope.text("high"));
    } else {
        const adjusted = try scope.invoke(helpers, "adjustMaxTokensForThinking", &.{ try scope.get(base, "maxTokens"), try scope.get(model, "maxTokens"), level, try v.optional(scope, options, "thinkingBudgets") });
        const max = try scope.invoke(helpers, "clampMaxTokensToContext", &.{ model, context, try scope.get(adjusted, "maxTokens") });
        try scope.put(result, "maxTokens", max);
        const remaining = try scope.own(try @import("native_image_arithmetic.zig").binary(scope.engine, .subtract, max, c.JS_NewInt32(scope.engine.context, 1024)));
        const room = try scope.invoke(try scope.global("Math"), "max", &.{ c.JS_NewInt32(scope.engine.context, 0), remaining });
        try scope.put(result, "thinkingBudgetTokens", try scope.invoke(try scope.global("Math"), "min", &.{ try scope.get(adjusted, "thinkingBudget"), room }));
    }
    return result;
}
fn stream(engine: *v.em.Engine, dependencies: c.JSValue, model: c.JSValue, input_context: c.JSValue, options: c.JSValue, is_simple: bool) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const effective = if (is_simple) try simple(&scope, dependencies, model, input_context, options) else options;
    const compatibility = try scope.own(try request.compat(engine, model));
    const context = try scope.own(try @import("native_ai_provider_transcript.zig").resolve(engine, input_context, scope.truthy(try scope.get(compatibility, "supportsMidConvoSystemMessages"))));
    const module = engine.native_module_values.get("@earendil-works/pi-ai") orelse return error.NativeAnthropicStreamMissing;
    const constructor = try scope.get(module, "AssistantMessageEventStream");
    const outer = try scope.own(try engine.checked(c.JS_CallConstructor(engine.context, constructor, 0, null)));
    const pending = try flow.create(engine, dependencies);
    defer engine.freeValue(pending.owner);
    defer engine.freeValue(pending.promise);
    const owner = pending.owner;
    try scope.put(owner, "model", model);
    try scope.put(owner, "context", context);
    try scope.put(owner, "options", effective);
    try scope.put(owner, "compat", compatibility);
    try scope.put(owner, "stream", outer);
    try scope.put(owner, "disabledPreferred", c.pi_js_bool(engine.context, 0));
    try scope.put(owner, "sawStart", c.pi_js_bool(engine.context, 0));
    try scope.put(owner, "sawStop", c.pi_js_bool(engine.context, 0));
    const key = try v.optional(&scope, effective, "apiKey");
    const client = try v.optional(&scope, effective, "client");
    const oauth = !scope.truthy(client) and scope.truthy(key) and scope.truthy(try scope.invoke(key, "includes", &.{try scope.text("sk-ant-oat")}));
    try scope.put(owner, "oauth", c.pi_js_bool(engine.context, @intFromBool(oauth)));
    const tools = try scope.own(try @import("native_agent_tool_changes.zig").currentTools(engine, try scope.get(context, "messages")));
    const decoder = try scope.own(try @import("native_ai_anthropic_decode.zig").create(engine, model, outer, try scope.get(dependencies, "json"), oauth, tools));
    try scope.put(owner, "decoder", decoder);
    setup(&scope, owner) catch |err| try failError(&scope, owner, err);
    return c.JS_DupValue(engine.context, outer);
}
fn hook(scope: *Scope, owner: c.JSValue, name: [*:0]const u8, value: c.JSValue) !c.JSValue {
    const options = try scope.get(owner, "options");
    const callback = try v.optional(scope, options, name);
    return if (v.nullish(callback)) c.pi_js_undefined() else scope.call(callback, options, &.{ value, try scope.get(owner, "model") });
}
fn wait(scope: *Scope, owner: c.JSValue, value: c.JSValue, stage: Stage) !void {
    return flow.wait(continued, scope.engine, owner, value, @intFromEnum(stage));
}
fn aborted(scope: *Scope, owner: c.JSValue) !bool {
    return scope.truthy(try v.optional(scope, try v.optional(scope, try scope.get(owner, "options"), "signal"), "aborted"));
}
fn setup(scope: *Scope, owner: c.JSValue) !void {
    const options = try scope.get(owner, "options");
    if (!scope.truthy(try v.optional(scope, options, "client"))) try auth(scope, try scope.get(owner, "model"), options);
    const built = try scope.own(try request.build(scope.engine, try scope.get(owner, "model"), try scope.get(owner, "context"), scope.truthy(try scope.get(owner, "oauth")), options, scope.truthy(try scope.get(owner, "disabledPreferred"))));
    try scope.put(owner, "built", built);
    const payload = try scope.get(built, "params");
    try scope.put(owner, "payload", payload);
    _ = try scope.invoke(try scope.get(owner, "decoder"), "thinkingLevel", &.{try scope.get(built, "providerThinkingLevel")});
    try wait(scope, owner, try hook(scope, owner, "onPayload", payload), .payload);
}
fn continued(engine: *v.em.Engine, owner: c.JSValue, value: c.JSValue, rejected: bool, raw: c_int) !void {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    if (rejected) {
        if (@as(Stage, @enumFromInt(raw)) == .ready and try fallback(&scope, owner, value)) return;
        return fail(&scope, owner, value);
    }
    advance(&scope, owner, value, @enumFromInt(raw)) catch |err| try failError(&scope, owner, err);
}
fn fallback(scope: *Scope, owner: c.JSValue, failure: c.JSValue) !bool {
    const api_error = try scope.get(try scope.get(try scope.get(owner, "agent"), "errors"), "APIError");
    const branded = c.JS_IsInstanceOf(scope.engine.context, failure, api_error);
    if (branded < 0) return v.js.capture(scope.engine);
    if (branded != 1) return false;
    if (try aborted(scope, owner) or scope.truthy(try scope.get(owner, "disabledPreferred")) or !scope.truthy(try scope.get(try scope.get(owner, "built"), "hasPreferredStrictTools")) or !scope.equal(try v.optional(scope, failure, "status"), c.JS_NewInt32(scope.engine.context, 400)) or !try v.eq(scope, try v.optional(scope, failure, "type"), "invalid_request_error")) return false;
    const message = try scope.get(failure, "message");
    inline for (.{ "The compiled grammar is too large", "Too many strict tools (", "Schemas contains too many parameters with union types (" }) |prefix| {
        if (scope.truthy(try scope.invoke(message, "includes", &.{try scope.text(prefix)}))) {
            try scope.put(owner, "disabledPreferred", c.pi_js_bool(scope.engine.context, 1));
            _ = try scope.invoke(try scope.get(owner, "decoder"), "strictFallback", &.{failure});
            try setup(scope, owner);
            return true;
        }
    }
    return false;
}
fn failError(scope: *Scope, owner: c.JSValue, err: anyerror) !void {
    const reason = flow.reason(scope.engine, err);
    defer scope.engine.freeValue(reason);
    return fail(scope, owner, reason);
}
fn release(scope: *Scope, owner: c.JSValue) !void {
    const reader = try scope.get(owner, "reader");
    if (!v.nullish(reader)) _ = try scope.invoke(reader, "releaseLock", &.{});
    try scope.set(owner, "reader", c.pi_js_undefined());
}
fn fail(scope: *Scope, owner: c.JSValue, reason: c.JSValue) !void {
    release(scope, owner) catch {};
    const wire = try scope.get(owner, "http");
    if (!v.nullish(wire)) _ = try scope.invoke(wire, "cancel", &.{});
    _ = scope.invoke(try scope.get(owner, "decoder"), "fail", &.{ reason, c.pi_js_bool(scope.engine.context, @intFromBool(try aborted(scope, owner))) }) catch |err| {
        try @import("native_stream.zig").reject(scope.engine, try scope.get(owner, "stream"), reason);
        try flow.rejectError(scope.engine, owner, err);
        return;
    };
    try flow.settle(scope.engine, owner, false, c.pi_js_undefined());
}
fn open(scope: *Scope, owner: c.JSValue) !void {
    const Adapter = struct {
        fn call(host: *v.em.Engine, _: c.JSValue, _: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
            var row: Scope = .{ .engine = host };
            defer row.deinit();
            return c.JS_DupValue(host.context, try perform(&row, roots[0]));
        }
    };
    const callback = try scope.own(try @import("native_node_function.zig").create(scope.engine, "", 0, Adapter.call, &.{owner}));
    const retry = try scope.own(try @import("native_ai_provider_retry_request.zig").create(scope.engine));
    const options = try scope.get(owner, "options");
    const retry_options = try scope.object();
    inline for (.{ "maxRetries", "maxRetryDelayMs", "signal" }) |key| try scope.put(retry_options, key, try v.optional(scope, options, key));
    return wait(scope, owner, try scope.call(retry, c.pi_js_undefined(), &.{ callback, retry_options }), .ready);
}
fn perform(scope: *Scope, owner: c.JSValue) !c.JSValue {
    if (try aborted(scope, owner)) return v.errorText(scope, try scope.text("Request was aborted"));
    const options = try scope.get(owner, "options");
    const client = try v.optional(scope, options, "client");
    if (scope.truthy(client)) {
        const sdk_options = try scope.object();
        const signal = try v.optional(scope, options, "signal");
        if (scope.truthy(signal)) try scope.put(sdk_options, "signal", signal);
        const timeout = try v.optional(scope, options, "timeoutMs");
        if (!c.JS_IsUndefined(timeout)) try scope.put(sdk_options, "timeout", timeout);
        try scope.put(sdk_options, "maxRetries", c.JS_NewInt32(scope.engine.context, 0));
        const created = try scope.invoke(try scope.get(try scope.get(client, "beta"), "messages"), "create", &.{ try scope.get(owner, "payload"), sdk_options });
        return scope.invoke(created, "asResponse", &.{});
    }
    // Guest-supplied fetch is called with a real native-built request body.
    const fetch = try v.optional(scope, options, "fetch");
    const model = try scope.get(owner, "model");
    const base = try scope.get(model, "baseUrl");
    const trimmed = if (scope.truthy(try scope.invoke(base, "endsWith", &.{try scope.text("/")}))) try scope.invoke(base, "slice", &.{ c.JS_NewInt32(scope.engine.context, 0), c.JS_NewInt32(scope.engine.context, -1) }) else base;
    const url = try scope.concat(trimmed, try scope.text("/v1/messages"));
    const payload = try v.spread(scope, try scope.get(owner, "payload"));
    try v.remove(scope, payload, "betas");
    const body = try scope.invoke(try scope.global("JSON"), "stringify", &.{payload});
    const headers = try buildHeaders(scope, owner);
    if (!v.nullish(fetch)) {
        const init = try scope.object();
        try scope.put(init, "method", try scope.text("POST"));
        try scope.put(init, "headers", headers);
        try scope.put(init, "body", body);
        try scope.put(init, "signal", try v.optional(scope, options, "signal"));
        return scope.call(fetch, c.pi_js_undefined(), &.{ url, init });
    }
    const address = try scope.engine.toString(url);
    defer scope.engine.gpa.free(address);
    const bytes = try scope.engine.toString(body);
    defer scope.engine.gpa.free(bytes);
    var fields: std.ArrayList(std.http.Header) = .empty;
    defer {
        for (fields.items) |field| {
            scope.engine.gpa.free(field.name);
            scope.engine.gpa.free(field.value);
        }
        fields.deinit(scope.engine.gpa);
    }
    var rows = try v.iterator(scope, try scope.invoke(try scope.global("Object"), "entries", &.{headers}));
    defer rows.deinit();
    errdefer rows.closePreserving();
    while (try rows.next()) |entry| {
        defer scope.engine.freeValue(entry);
        const value = try v.at(scope, entry, 1);
        if (v.nullish(value)) continue;
        const name = try scope.engine.toString(try v.at(scope, entry, 0));
        errdefer scope.engine.gpa.free(name);
        const value_bytes = try scope.engine.toString(value);
        errdefer scope.engine.gpa.free(value_bytes);
        try fields.append(scope.engine.gpa, .{ .name = name, .value = value_bytes });
    }
    const timeout = try v.optional(scope, options, "timeoutMs");
    var milliseconds: i64 = 600000;
    if (!c.JS_IsUndefined(timeout) and c.JS_ToInt64(scope.engine.context, &milliseconds, timeout) < 0) return v.js.capture(scope.engine);
    const http = try scope.own(try @import("native_ai_http.zig").open(scope.engine, .{ .url = address, .payload = bytes, .headers = fields.items, .framing = .bytes, .timeout_ms = @intCast(@max(0, milliseconds)) }, try v.optional(scope, options, "signal")));
    try scope.put(owner, "http", http);
    try scope.put(owner, "iterator", try scope.get(http, "events"));
    const pending = try flow.create(scope.engine, owner);
    defer scope.engine.freeValue(pending.owner);
    errdefer scope.engine.freeValue(pending.promise);
    try flow.wait(wireReady, scope.engine, pending.owner, try scope.get(http, "ready"), 0);
    return scope.own(pending.promise);
}
fn wireReady(engine: *v.em.Engine, pending: c.JSValue, value: c.JSValue, rejected: bool, stage: c_int) !void {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const owner = try scope.get(pending, "agent");
    wireAdvance(&scope, pending, owner, value, rejected, stage) catch |err| try flow.rejectError(engine, pending, err);
}
fn wireAdvance(scope: *Scope, pending: c.JSValue, owner: c.JSValue, value: c.JSValue, rejected: bool, stage: c_int) !void {
    if (rejected) {
        const errors = try scope.get(try scope.get(owner, "agent"), "errors");
        const code = try v.optional(scope, value, "code");
        const constructor = try scope.get(errors, if (try aborted(scope, owner)) "APIUserAbortError" else if (try v.eq(scope, code, "ProviderRequestTimeout")) "APIConnectionTimeoutError" else "APIConnectionError");
        const options = try scope.object();
        try scope.put(options, "cause", value);
        var args = [_]c.JSValue{options};
        const failure = try scope.own(try scope.engine.checked(c.JS_CallConstructor(scope.engine.context, constructor, 1, &args)));
        return flow.settle(scope.engine, pending, true, failure);
    }
    if (stage == 0) {
        const status = try scope.get(value, "status");
        if (try @import("native_image_arithmetic.zig").compare(scope.engine, .greater_equal, status, c.JS_NewInt32(scope.engine.context, 200)) and try @import("native_image_arithmetic.zig").compare(scope.engine, .less, status, c.JS_NewInt32(scope.engine.context, 300))) return flow.settle(scope.engine, pending, false, value);
        try scope.put(owner, "response", value);
        return flow.wait(wireReady, scope.engine, pending, try scope.invoke(try scope.get(owner, "iterator"), "next", &.{}), 1);
    }
    const frame = try scope.get(value, "value");
    const body = if (scope.truthy(try scope.get(value, "done"))) try scope.text("") else try scope.get(frame, "body");
    const failure = try sdkFailure(scope, owner, body);
    return flow.settle(scope.engine, pending, true, failure);
}
fn merge(scope: *Scope, target: c.JSValue, source: c.JSValue) !void {
    if (v.nullish(source)) return;
    var rows = try v.iterator(scope, try scope.invoke(try scope.global("Object"), "entries", &.{source}));
    defer rows.deinit();
    errdefer rows.closePreserving();
    while (try rows.next()) |entry| {
        defer scope.engine.freeValue(entry);
        try v.js.setKey(scope.engine, target, try scope.invoke(try v.at(scope, entry, 0), "toLowerCase", &.{}), try v.at(scope, entry, 1));
    }
}
fn buildHeaders(scope: *Scope, owner: c.JSValue) !c.JSValue {
    const headers = try scope.object();
    try scope.put(headers, "content-type", try scope.text("application/json"));
    try scope.put(headers, "accept", try scope.text("application/json"));
    try scope.put(headers, "anthropic-version", try scope.text("2023-06-01"));
    try scope.put(headers, "anthropic-dangerous-direct-browser-access", try scope.text("true"));
    const model = try scope.get(owner, "model");
    const options = try scope.get(owner, "options");
    const key = try v.optional(scope, options, "apiKey");
    const oauth = scope.truthy(try scope.get(owner, "oauth"));
    if (scope.truthy(key)) try scope.put(headers, if (oauth or try v.eq(scope, try scope.get(model, "provider"), "github-copilot")) "authorization" else "x-api-key", if (oauth or try v.eq(scope, try scope.get(model, "provider"), "github-copilot")) try scope.concat(try scope.text("Bearer "), key) else key);
    if (oauth) {
        try scope.put(headers, "user-agent", try scope.text("claude-cli/2.1.280"));
        try scope.put(headers, "x-app", try scope.text("cli"));
    } else {
        try scope.put(headers, "user-agent", try scope.text(@import("../ai/pi_user_agent.zig").value));
        const session = try v.optional(scope, options, "sessionId");
        if (scope.truthy(session) and !try v.eq(scope, try @import("native_ai_provider_request.zig").retention(scope, options), "none") and scope.truthy(try scope.get(try scope.get(owner, "compat"), "sendSessionAffinityHeaders"))) try scope.put(headers, if (try v.eq(scope, try scope.get(try scope.get(owner, "compat"), "sessionAffinityFormat"), "openrouter")) "x-session-id" else "x-session-affinity", session);
    }
    const betas = try scope.get(try scope.get(owner, "payload"), "betas");
    if (!v.nullish(betas) and try v.length(scope, betas) > 0) try scope.put(headers, "anthropic-beta", try scope.invoke(betas, "join", &.{try scope.text(",")}));
    try merge(scope, headers, try scope.get(model, "headers"));
    try merge(scope, headers, try v.optional(scope, options, "headers"));
    return headers;
}
fn read(scope: *Scope, owner: c.JSValue) !void {
    if (try aborted(scope, owner)) return v.errorText(scope, try scope.text("Request was aborted"));
    const reader = try scope.get(owner, "reader");
    if (!v.nullish(reader)) return wait(scope, owner, try scope.invoke(reader, "read", &.{}), .read);
    return wait(scope, owner, try scope.invoke(try scope.get(owner, "iterator"), "next", &.{}), .raw);
}
fn queued(scope: *Scope, owner: c.JSValue) !void {
    const queue = try scope.get(owner, "events");
    while (try v.length(scope, queue) > 0) {
        const frame = try scope.invoke(queue, "shift", &.{});
        const decoded = try sse.decode(scope, frame, try scope.get(try scope.get(owner, "agent"), "json"));
        if (c.JS_IsUndefined(decoded)) continue;
        const type_value = try scope.get(decoded, "type");
        if (try v.eq(scope, type_value, "message_start")) try scope.put(owner, "sawStart", c.pi_js_bool(scope.engine.context, 1));
        if (try v.eq(scope, type_value, "message_stop")) try scope.put(owner, "sawStop", c.pi_js_bool(scope.engine.context, 1));
        try scope.put(owner, "event", decoded);
        return wait(scope, owner, try hook(scope, owner, "onProviderStreamEvent", decoded), .event);
    }
    if (scope.truthy(try scope.get(owner, "eof"))) {
        try release(scope, owner);
        if (scope.truthy(try scope.get(owner, "sawStart")) and !scope.truthy(try scope.get(owner, "sawStop"))) return v.errorText(scope, try scope.text("Anthropic stream ended before message_stop"));
        _ = try scope.invoke(try scope.get(owner, "decoder"), "finish", &.{c.pi_js_bool(scope.engine.context, @intFromBool(try aborted(scope, owner)))});
        return flow.settle(scope.engine, owner, false, c.pi_js_undefined());
    }
    return read(scope, owner);
}
fn advance(scope: *Scope, owner: c.JSValue, value: c.JSValue, stage: Stage) !void {
    switch (stage) {
        .payload => {
            if (!c.JS_IsUndefined(value)) {
                const replaced = try v.spread(scope, value);
                try scope.put(replaced, "stream", c.pi_js_bool(scope.engine.context, 1));
                try scope.put(owner, "payload", replaced);
            }
            try open(scope, owner);
        },
        .ready => {
            try scope.put(owner, "response", value);
            const status = try scope.get(value, "status");
            if (try @import("native_image_arithmetic.zig").compare(scope.engine, .greater_equal, status, c.JS_NewInt32(scope.engine.context, 400))) {
                const text_method = try scope.get(value, "text");
                if (!v.nullish(text_method)) return wait(scope, owner, try scope.call(text_method, value, &.{}), .rejected_body);
                return read(scope, owner);
            }
            const metadata = try scope.object();
            try scope.put(metadata, "status", status);
            const headers = try scope.get(value, "headers");
            const entries = try v.optional(scope, headers, "entries");
            try scope.put(metadata, "headers", if (c.JS_IsFunction(scope.engine.context, entries)) try scope.invoke(try scope.global("Object"), "fromEntries", &.{try scope.call(entries, headers, &.{})}) else headers);
            try wait(scope, owner, try hook(scope, owner, "onResponse", metadata), .response);
        },
        .response => {
            _ = try scope.invoke(try scope.get(owner, "decoder"), "start", &.{});
            try scope.put(owner, "events", try scope.array());
            try scope.put(owner, "sse", try sse.create(scope));
            try scope.put(owner, "textDecoder", try scope.own(try v.js.builtin(scope.engine, "TextDecoder", &.{})));
            const http = try scope.get(owner, "http");
            if (v.nullish(http)) {
                const body = try scope.get(try scope.get(owner, "response"), "body");
                if (!scope.truthy(body)) return v.errorText(scope, try scope.text("Attempted to iterate over an Anthropic response with no body"));
                try scope.put(owner, "reader", try scope.invoke(body, "getReader", &.{}));
            }
            try read(scope, owner);
        },
        .read => {
            const eof = scope.truthy(try scope.get(value, "done"));
            const decoder = try scope.get(owner, "textDecoder");
            const config = try scope.object();
            try scope.put(config, "stream", c.pi_js_bool(scope.engine.context, 1));
            const text = if (eof) try scope.invoke(decoder, "decode", &.{}) else try scope.invoke(decoder, "decode", &.{ try scope.get(value, "value"), config });
            try scope.put(owner, "events", try sse.feed(scope, try scope.get(owner, "sse"), text, eof));
            try scope.put(owner, "eof", c.pi_js_bool(scope.engine.context, @intFromBool(eof)));
            try queued(scope, owner);
        },
        .event => {
            _ = try scope.invoke(try scope.get(owner, "decoder"), "event", &.{try scope.get(owner, "event")});
            try queued(scope, owner);
        },
        .raw => {
            const eof = scope.truthy(try scope.get(value, "done"));
            if (!eof) {
                const frame = try scope.get(value, "value");
                const error_body = try v.eq(scope, try scope.get(frame, "type"), "error_body");
                if (error_body) return failureBody(scope, owner, try scope.get(frame, "body"));
                const config = try scope.object();
                try scope.put(config, "stream", c.pi_js_bool(scope.engine.context, 1));
                const text = try scope.invoke(try scope.get(owner, "textDecoder"), "decode", &.{ try scope.get(frame, "data"), config });
                try scope.put(owner, "events", try sse.feed(scope, try scope.get(owner, "sse"), text, false));
            } else {
                const text = try scope.invoke(try scope.get(owner, "textDecoder"), "decode", &.{});
                try scope.put(owner, "events", try sse.feed(scope, try scope.get(owner, "sse"), text, true));
            }
            try scope.put(owner, "eof", c.pi_js_bool(scope.engine.context, @intFromBool(eof)));
            try queued(scope, owner);
        },
        .rejected_body => try failureBody(scope, owner, value),
    }
}
fn failureBody(scope: *Scope, owner: c.JSValue, text: c.JSValue) !void {
    const reason = try sdkFailure(scope, owner, text);
    if (!try fallback(scope, owner, reason)) try fail(scope, owner, reason);
}
fn sdkFailure(scope: *Scope, owner: c.JSValue, text: c.JSValue) !c.JSValue {
    const generation = scope.engine.native_allocation_generation;
    const body = scope.invoke(try scope.global("JSON"), "parse", &.{text}) catch |err| missing: {
        try @import("native_ai_partial_json.zig").discard(scope.engine, err, generation);
        break :missing c.pi_js_undefined();
    };
    const status = try scope.get(try scope.get(owner, "response"), "status");
    const header_values = try scope.get(try scope.get(owner, "response"), "headers");
    const headers = try scope.own(try v.js.builtin(scope.engine, "Headers", &.{header_values}));
    return @import("native_ai_anthropic_api_error.zig").generateValue(scope, try scope.get(try scope.get(owner, "agent"), "errors"), status, body, text, headers);
}
