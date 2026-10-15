//! Actual Anthropic stream facade. Native continuations retain callback/value identity.
//! Direct wire uses native HTTP; supplied SDK clients and fetch remain guest values.
const std = @import("std");
const v = @import("native_ai_provider_values.zig");
const Scope = v.Scope;
const c = v.c;
const flow = @import("native_agent_async.zig");
const request = @import("native_ai_anthropic_request.zig");
const sse = @import("native_ai_anthropic_sse.zig");
const federation = @import("native_ai_anthropic_federation.zig");
const Stage = enum(c_int) { payload, ready, response, read, event, raw, rejected_body };
pub fn create(engine: *v.em.Engine) !c.JSValue {
    try @import("native_stream.zig").install(engine);
    try @import("native_ai_sdk_headers.zig").install(engine);
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const dependencies = try scope.object();
    const thinking = try scope.own(try @import("native_ai_thinking.zig").create(engine));
    const estimate = try scope.own(try @import("native_ai_estimate.zig").create(engine));
    try scope.put(dependencies, "simple", try scope.own(try @import("native_ai_simple_options.zig").create(engine, try scope.get(thinking, "clampThinkingLevel"), try scope.get(estimate, "estimateContextTokens"))));
    try scope.put(dependencies, "json", try scope.own(try @import("native_ai_json_parse.zig").create(engine)));
    try scope.put(dependencies, "errors", try scope.own(try @import("native_ai_anthropic_api_error.zig").create(engine)));
    try scope.put(dependencies, "userAgentOS", try @import("native_ai_user_agent.zig").load(&scope));
    try scope.put(dependencies, "federationSlot", try scope.own(try federation.createSlot(engine)));
    const result = try scope.object();
    inline for (.{ "stream", "streamSimple" }, 0..) |name, index| {
        const Adapter = struct {
            fn call(host: *v.em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
                return stream(host, roots[0], if (args.len > 0) args[0] else c.pi_js_undefined(), if (args.len > 1) args[1] else c.pi_js_undefined(), if (args.len > 2) args[2] else c.pi_js_undefined(), index == 1);
            }
        };
        try scope.put(result, name, try scope.own(try @import("native_node_function.zig").createArrow(engine, name, 3, Adapter.call, &.{dependencies})));
    }
    return c.JS_DupValue(engine.context, result);
}
fn auth(scope: *Scope, model: c.JSValue, options: c.JSValue) !void {
    const key = try v.optional(scope, options, "apiKey");
    if (scope.truthy(key)) return;
    return authKnown(scope, model, key, try v.optional(scope, options, "headers"));
}
fn authKnown(scope: *Scope, model: c.JSValue, key: c.JSValue, headers: c.JSValue) !void {
    if (scope.truthy(key)) return;
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
    const config = try federationConfig(scope, model, options);
    if (c.JS_IsUndefined(config)) try auth(scope, model, options);
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
    try scope.put(owner, "allocationGeneration", try scope.own(try engine.checked(c.JS_NewBigUint64(engine.context, engine.native_allocation_generation))));
    try scope.put(owner, "model", model);
    try scope.put(owner, "context", context);
    try scope.put(owner, "options", effective);
    try scope.put(owner, "compat", compatibility);
    try scope.put(owner, "stream", outer);
    try scope.put(owner, "disabledPreferred", c.pi_js_bool(engine.context, 0));
    try scope.put(owner, "sawStart", c.pi_js_bool(engine.context, 0));
    try scope.put(owner, "sawStop", c.pi_js_bool(engine.context, 0));
    const tools = try scope.own(try @import("native_agent_tool_changes.zig").currentTools(engine, try scope.get(context, "messages")));
    const decoder = try scope.own(try @import("native_ai_anthropic_decode.zig").create(engine, model, outer, try scope.get(dependencies, "json"), false, tools));
    try scope.put(owner, "decoder", decoder);
    setup(&scope, owner) catch |err| try failError(&scope, owner, err);
    return c.JS_DupValue(engine.context, outer);
}
fn hook(scope: *Scope, owner: c.JSValue, name: [*:0]const u8, value: c.JSValue) !c.JSValue {
    const options = try scope.get(owner, "options");
    const callback = try v.optional(scope, options, name);
    return if (v.nullish(callback)) c.pi_js_undefined() else scope.call(callback, options, &.{ value, try scope.get(owner, "model") });
}
fn responseHook(scope: *Scope, owner: c.JSValue, response: c.JSValue) !c.JSValue {
    const options = try scope.get(owner, "options");
    const callback = try v.optional(scope, options, "onResponse");
    if (v.nullish(callback)) return c.pi_js_undefined();
    const metadata = try scope.object();
    try scope.put(metadata, "status", try scope.get(response, "status"));
    const supplied_headers = try scope.get(response, "headers");
    const headers = if (v.nullish(try scope.get(owner, "http"))) supplied_headers else try scope.own(try @import("native_headers.zig").fromRecord(scope.engine, supplied_headers));
    try scope.put(metadata, "headers", try scope.own(try @import("native_ai_headers.zig").toRecord(scope.engine, headers)));
    return scope.call(callback, options, &.{ metadata, try scope.get(owner, "model") });
}
fn wait(scope: *Scope, owner: c.JSValue, value: c.JSValue, stage: Stage) !void {
    return flow.wait(continued, scope.engine, owner, value, @intFromEnum(stage));
}
fn aborted(scope: *Scope, owner: c.JSValue) !bool {
    return scope.truthy(try v.optional(scope, try v.optional(scope, try scope.get(owner, "options"), "signal"), "aborted"));
}
fn setup(scope: *Scope, owner: c.JSValue) !void {
    const options = try scope.get(owner, "options");
    if (!scope.truthy(try scope.get(owner, "configured"))) {
        const model = try scope.get(owner, "model");
        const supplied = try v.optional(scope, options, "client");
        try scope.put(owner, "usesSdkClient", c.pi_js_bool(scope.engine.context, @intFromBool(scope.truthy(supplied))));
        const sdk_client = if (scope.truthy(supplied)) try v.optional(scope, options, "client") else c.pi_js_undefined();
        try scope.put(owner, "sdkClient", sdk_client);
        const key = if (scope.truthy(supplied)) c.pi_js_undefined() else try v.optional(scope, options, "apiKey");
        try scope.put(owner, "apiKey", key);
        const oauth = !scope.truthy(supplied) and !try v.eq(scope, try scope.get(model, "provider"), "github-copilot") and scope.truthy(key) and scope.truthy(try scope.invoke(key, "includes", &.{try scope.text("sk-ant-oat")}));
        try scope.put(owner, "oauth", c.pi_js_bool(scope.engine.context, @intFromBool(oauth)));
        _ = try scope.invoke(try scope.get(owner, "decoder"), "oauthMode", &.{c.pi_js_bool(scope.engine.context, @intFromBool(oauth))});
        if (!scope.truthy(supplied)) {
            const config = try scope.own(try federation.resolve(scope.engine, model, key, try v.optional(scope, options, "headers"), try v.optional(scope, options, "env")));
            if (c.JS_IsUndefined(config)) try authKnown(scope, model, key, try v.optional(scope, options, "headers"));
            const fetch = try v.optional(scope, options, "fetch");
            try scope.put(owner, "fetch", fetch);
            try scope.put(owner, "baseURL", try scope.get(model, "baseUrl"));
            if (!c.JS_IsUndefined(config)) {
                const client = try scope.own(try federation.client(scope.engine, try scope.get(try scope.get(owner, "agent"), "federationSlot"), model, config, fetch));
                try scope.put(owner, "federationClient", client);
            }
            try scope.put(owner, "clientHeaders", try captureClientHeaders(scope, owner));
        }
        const request_options = try scope.object();
        const request_signal = try v.optional(scope, options, "signal");
        if (scope.truthy(request_signal)) try scope.put(request_options, "signal", try v.optional(scope, options, "signal"));
        const timeout = try v.optional(scope, options, "timeoutMs");
        if (!c.JS_IsUndefined(timeout)) try scope.put(request_options, "timeout", try v.optional(scope, options, "timeoutMs"));
        try scope.put(request_options, "maxRetries", c.JS_NewInt32(scope.engine.context, 0));
        try scope.put(owner, "requestOptions", request_options);
        try scope.put(owner, "configured", c.pi_js_bool(scope.engine.context, 1));
    }
    const loop_signal = try v.optional(scope, options, "signal");
    if (!v.nullish(loop_signal)) _ = try scope.invoke(loop_signal, "throwIfAborted", &.{});
    const built = try scope.own(try request.build(scope.engine, try scope.get(owner, "model"), try scope.get(owner, "context"), scope.truthy(try scope.get(owner, "oauth")), options, scope.truthy(try scope.get(owner, "disabledPreferred"))));
    try scope.put(owner, "built", built);
    const payload = try scope.get(built, "params");
    try scope.put(owner, "payload", payload);
    _ = try scope.invoke(try scope.get(owner, "decoder"), "thinkingLevel", &.{try scope.get(built, "providerThinkingLevel")});
    try wait(scope, owner, try hook(scope, owner, "onPayload", payload), .payload);
}
fn federationConfig(scope: *Scope, model: c.JSValue, options: c.JSValue) !c.JSValue {
    return scope.own(try federation.resolve(scope.engine, model, try v.optional(scope, options, "apiKey"), try v.optional(scope, options, "headers"), try v.optional(scope, options, "env")));
}
fn continued(engine: *v.em.Engine, owner: c.JSValue, value: c.JSValue, rejected: bool, raw: c_int) !void {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    if (rejected) {
        if (@as(Stage, @enumFromInt(raw)) == .rejected_body and !try nativeAllocationReason(engine, owner, value)) {
            return rejectedBody(&scope, owner, value) catch |err| failError(&scope, owner, err);
        }
        if (@as(Stage, @enumFromInt(raw)) == .ready) {
            const recovered = fallback(&scope, owner, value) catch |err| return failError(&scope, owner, err);
            if (recovered) return;
        }
        return fail(&scope, owner, value) catch |err| failError(&scope, owner, err);
    }
    advance(&scope, owner, value, @enumFromInt(raw)) catch |err| try failError(&scope, owner, err);
}
fn rejectedBody(scope: *Scope, owner: c.JSValue, failure: c.JSValue) !void {
    const error_value = try @import("native_ai_anthropic_api_error.zig").castToError(scope, failure);
    return failureBody(scope, owner, try scope.get(error_value, "message"));
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
    if (err == error.OutOfMemory or try nativeAllocationReason(scope.engine, owner, reason)) return retireNativeAllocation(scope.engine, owner, reason);
    return fail(scope, owner, reason) catch |secondary| {
        const secondary_reason = flow.reason(scope.engine, secondary);
        defer scope.engine.freeValue(secondary_reason);
        if (secondary == error.OutOfMemory or try nativeAllocationReason(scope.engine, owner, secondary_reason)) return retireNativeAllocation(scope.engine, owner, secondary_reason);
        return secondary;
    };
}
fn nativeAllocationReason(engine: *v.em.Engine, owner: c.JSValue, reason: c.JSValue) !bool {
    const tagged = c.pi_js_native_allocation_error_generation(reason);
    if (tagged == 0) return false;
    const value = try v.js.get(engine, owner, "allocationGeneration");
    defer engine.freeValue(value);
    var generation: u64 = 0;
    if (c.JS_ToBigUint64(engine.context, &generation, value) < 0) return v.js.capture(engine);
    const distance = tagged -% generation;
    return distance != 0 and distance <= engine.native_allocation_generation -% generation;
}
fn retireNativeAllocation(engine: *v.em.Engine, owner: c.JSValue, reason: c.JSValue) !void {
    // No Scope root growth or assistant-event serialization while the host
    // allocator is exhausted. Preserve the actual fresh private native error,
    // including when publication of an ordinary caller error itself ran OOM.
    const wire = try v.js.get(engine, owner, "http");
    defer engine.freeValue(wire);
    if (!v.nullish(wire)) {
        const cancelled = v.js.invoke(engine, wire, "cancel", &.{}) catch null;
        if (cancelled) |value| engine.freeValue(value);
    }
    const stream_value = try v.js.get(engine, owner, "stream");
    defer engine.freeValue(stream_value);
    try @import("native_stream.zig").reject(engine, stream_value, reason);
    try flow.settle(engine, owner, false, c.pi_js_undefined());
}
fn release(scope: *Scope, owner: c.JSValue) !void {
    const reader = try scope.get(owner, "reader");
    try scope.set(owner, "reader", c.pi_js_undefined());
    if (!v.nullish(reader)) _ = try scope.invoke(reader, "releaseLock", &.{});
}
fn fail(scope: *Scope, owner: c.JSValue, reason: c.JSValue) !void {
    if (try nativeAllocationReason(scope.engine, owner, reason)) return retireNativeAllocation(scope.engine, owner, reason);
    release(scope, owner) catch |err| {
        const release_reason = flow.reason(scope.engine, err);
        defer scope.engine.freeValue(release_reason);
        if (err == error.OutOfMemory or try nativeAllocationReason(scope.engine, owner, release_reason)) return retireNativeAllocation(scope.engine, owner, release_reason);
    };
    const wire = try scope.get(owner, "http");
    if (!v.nullish(wire)) _ = try scope.invoke(wire, "cancel", &.{});
    _ = scope.invoke(try scope.get(owner, "decoder"), "fail", &.{ reason, c.pi_js_bool(scope.engine.context, @intFromBool(try aborted(scope, owner))) }) catch |err| {
        const decoder_reason = flow.reason(scope.engine, err);
        defer scope.engine.freeValue(decoder_reason);
        if (err == error.OutOfMemory or try nativeAllocationReason(scope.engine, owner, decoder_reason)) return retireNativeAllocation(scope.engine, owner, decoder_reason);
        try @import("native_stream.zig").reject(scope.engine, try scope.get(owner, "stream"), reason);
        try flow.settle(scope.engine, owner, true, decoder_reason);
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
    const callback = try scope.own(try @import("native_node_function.zig").createArrow(scope.engine, "", 0, Adapter.call, &.{owner}));
    const retry = try scope.own(try @import("native_ai_provider_retry_request.zig").create(scope.engine));
    const options = try scope.get(owner, "options");
    const retry_options = try scope.object();
    inline for (.{ "maxRetries", "maxRetryDelayMs", "signal" }) |key| try scope.put(retry_options, key, try v.optional(scope, options, key));
    return wait(scope, owner, try scope.call(retry, c.pi_js_undefined(), &.{ callback, retry_options }), .ready);
}
fn perform(scope: *Scope, owner: c.JSValue) !c.JSValue {
    if (!scope.truthy(try scope.get(owner, "usesSdkClient"))) try scope.put(owner, "wire", try @import("native_ai_anthropic_wire.zig").prepare(scope, try scope.get(owner, "payload"), try scope.get(try scope.get(owner, "agent"), "errors")));
    const client = try scope.get(owner, "federationClient");
    if (c.JS_IsUndefined(client)) return performAuthorized(scope, owner);
    const pending = try flow.create(scope.engine, owner);
    defer scope.engine.freeValue(pending.owner);
    errdefer scope.engine.freeValue(pending.promise);
    try flow.wait(authorized, scope.engine, pending.owner, try scope.own(try federation.authorize(scope.engine, client)), 0);
    return scope.own(pending.promise);
}
fn authorized(engine: *v.em.Engine, pending: c.JSValue, value: c.JSValue, rejected: bool, stage: c_int) !void {
    if (rejected or stage == 1) return flow.settle(engine, pending, rejected, value);
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const owner = try scope.get(pending, "agent");
    try scope.put(owner, "federationToken", value);
    const response = performAuthorized(&scope, owner) catch |err| {
        try flow.rejectError(engine, pending, err);
        return;
    };
    try flow.wait(authorized, engine, pending, response, 1);
}
fn performAuthorized(scope: *Scope, owner: c.JSValue) !c.JSValue {
    const request_options = try scope.get(owner, "requestOptions");
    if (scope.truthy(try v.optional(scope, try scope.get(request_options, "signal"), "aborted"))) return v.errorText(scope, try scope.text("Request was aborted"));
    const client = try scope.get(owner, "sdkClient");
    if (scope.truthy(try scope.get(owner, "usesSdkClient"))) {
        const created = try scope.invoke(try scope.get(try scope.get(client, "beta"), "messages"), "create", &.{ try scope.get(owner, "payload"), request_options });
        return scope.invoke(created, "asResponse", &.{});
    }
    // Guest-supplied fetch is called with a real native-built request body.
    const fetch = try scope.get(owner, "fetch");
    const base = try scope.get(owner, "baseURL");
    const trimmed = if (scope.truthy(try scope.invoke(base, "endsWith", &.{try scope.text("/")}))) try scope.invoke(base, "slice", &.{ c.JS_NewInt32(scope.engine.context, 0), c.JS_NewInt32(scope.engine.context, -1) }) else base;
    const url = try scope.concat(trimmed, try scope.text("/v1/messages?beta=true"));
    const payload = try scope.get(try scope.get(owner, "wire"), "body");
    const body = try scope.invoke(try scope.global("JSON"), "stringify", &.{payload});
    const headers = try buildHeaders(scope, owner);
    if (!v.nullish(fetch)) {
        const init = try scope.object();
        try scope.put(init, "method", try scope.text("POST"));
        try scope.put(init, "headers", headers);
        try scope.put(init, "body", body);
        try scope.put(init, "signal", try scope.get(request_options, "signal"));
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
    var rows = try v.iterator(scope, try scope.invoke(headers, "entries", &.{}));
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
    const timeout = try scope.get(request_options, "timeout");
    var milliseconds: i64 = 600000;
    if (!c.JS_IsUndefined(timeout) and c.JS_ToInt64(scope.engine.context, &milliseconds, timeout) < 0) return v.js.capture(scope.engine);
    const http = try scope.own(try @import("native_ai_http.zig").open(scope.engine, .{ .url = address, .payload = bytes, .headers = fields.items, .framing = .bytes, .timeout_ms = @intCast(@max(0, milliseconds)) }, try scope.get(request_options, "signal")));
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
        if (!try aborted(scope, owner) and !try v.eq(scope, code, "ProviderRequestTimeout")) {
            const failure = try @import("native_ai_anthropic_api_error.zig").generateValue(scope, errors, c.pi_js_undefined(), value, c.pi_js_undefined(), c.pi_js_undefined());
            return flow.settle(scope.engine, pending, true, failure);
        }
        const constructor = try scope.get(errors, if (try aborted(scope, owner)) "APIUserAbortError" else "APIConnectionTimeoutError");
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
        if (scope.equal(status, c.JS_NewInt32(scope.engine.context, 401))) try invalidateFederation(scope, owner);
        return flow.wait(wireReady, scope.engine, pending, try scope.invoke(try scope.get(owner, "iterator"), "next", &.{}), 1);
    }
    const frame = try scope.get(value, "value");
    const body = if (scope.truthy(try scope.get(value, "done"))) try scope.text("") else try scope.get(frame, "body");
    const failure = try sdkFailure(scope, owner, body);
    return flow.settle(scope.engine, pending, true, failure);
}
fn invalidateFederation(scope: *Scope, owner: c.JSValue) !void {
    const client = try scope.get(owner, "federationClient");
    if (!c.JS_IsUndefined(client)) try federation.invalidate(scope.engine, client);
}
fn captureClientHeaders(scope: *Scope, owner: c.JSValue) !c.JSValue {
    const model = try scope.get(owner, "model");
    const options = try scope.get(owner, "options");
    const oauth = scope.truthy(try scope.get(owner, "oauth"));
    const copilot = try v.eq(scope, try scope.get(model, "provider"), "github-copilot");
    var dynamic = c.pi_js_undefined();
    if (copilot) {
        const transcript = try scope.get(try scope.get(owner, "context"), "messages");
        const helper = @import("native_ai_copilot_headers.zig");
        dynamic = try helper.build(scope, transcript, try helper.hasVision(scope, transcript));
    }
    const retained = try @import("native_ai_provider_request.zig").retention(scope, options);
    const session = if (try v.eq(scope, retained, "none")) c.pi_js_undefined() else try v.optional(scope, options, "sessionId");
    const identity = try scope.object();
    try scope.put(identity, "accept", try scope.text("application/json"));
    try scope.put(identity, "anthropic-dangerous-direct-browser-access", try scope.text("true"));
    if (oauth) {
        try scope.put(identity, "user-agent", try scope.text("claude-cli/2.1.280"));
        try scope.put(identity, "x-app", try scope.text("cli"));
    }
    const affinity = try scope.object();
    if (!oauth and !copilot) {
        const compatibility = try scope.own(try request.compat(scope.engine, model));
        if (scope.truthy(session) and scope.truthy(try scope.get(compatibility, "sendSessionAffinityHeaders"))) try scope.put(affinity, if (try v.eq(scope, try scope.get(compatibility, "sessionAffinityFormat"), "openrouter")) "x-session-id" else "x-session-affinity", session);
    }
    const model_headers = try scope.get(model, "headers");
    const option_headers = try v.optional(scope, options, "headers");
    const user_agent = try scope.object();
    try scope.put(user_agent, "User-Agent", try @import("native_ai_user_agent.zig").runtime(scope));
    const result = try scope.object();
    for ([_]c.JSValue{ user_agent, identity, affinity, model_headers, dynamic, option_headers }) |source| {
        if (scope.truthy(source)) _ = try scope.invoke(try scope.global("Object"), "assign", &.{ result, source });
    }
    return result;
}
fn buildHeaders(scope: *Scope, owner: c.JSValue) !c.JSValue {
    const defaults = try scope.object();
    try scope.put(defaults, "accept", try scope.text("application/json"));
    try scope.put(defaults, "anthropic-version", try scope.text("2023-06-01"));
    try scope.put(defaults, "anthropic-dangerous-direct-browser-access", try scope.text("true"));
    const auth_headers = try scope.object();
    const model = try scope.get(owner, "model");
    const key = try scope.get(owner, "apiKey");
    const oauth = scope.truthy(try scope.get(owner, "oauth"));
    const federated_client = try scope.get(owner, "federationClient");
    if (c.JS_IsUndefined(federated_client) and !v.nullish(key)) try scope.put(auth_headers, if (oauth or try v.eq(scope, try scope.get(model, "provider"), "github-copilot")) "authorization" else "x-api-key", if (oauth or try v.eq(scope, try scope.get(model, "provider"), "github-copilot")) try scope.concat(try scope.text("Bearer "), key) else key);
    const token = try scope.get(owner, "federationToken");
    if (!c.JS_IsUndefined(token)) try scope.put(auth_headers, "authorization", try scope.concat(try scope.text("Bearer "), token));
    const body_headers = try scope.object();
    try scope.put(body_headers, "content-type", try scope.text("application/json"));
    const combined = try @import("native_ai_sdk_headers.zig").build(scope, &.{ defaults, auth_headers, try scope.get(owner, "clientHeaders"), body_headers, try scope.get(try scope.get(owner, "wire"), "headers") });
    const result = try scope.get(combined, "values");
    if (!scope.truthy(try scope.invoke(result, "get", &.{try scope.text("x-api-key")})) and !scope.truthy(try scope.invoke(result, "get", &.{try scope.text("authorization")})) and c.JS_IsUndefined(federated_client)) {
        const nulls = try scope.get(combined, "nulls");
        if (!scope.truthy(try scope.invoke(nulls, "has", &.{try scope.text("x-api-key")})) and !scope.truthy(try scope.invoke(nulls, "has", &.{try scope.text("authorization")}))) return v.errorText(scope, try scope.text("Could not resolve authentication method. Expected one of apiKey, authToken, credentials, config, or profile to be set. Or for one of the \"X-Api-Key\" or \"Authorization\" headers to be explicitly omitted"));
    }
    if (!c.JS_IsUndefined(federated_client)) {
        // SDK credential-chain emits the workspace extra header only for
        // user_oauth. Pi's explicit OIDC federation sends workspace_id in the
        // token exchange, not again on Messages requests.
        const current = try scope.invoke(result, "get", &.{try scope.text("anthropic-beta")});
        const values = if (v.nullish(current)) try scope.array() else try scope.invoke(current, "split", &.{try scope.text(",")});
        const trimmed = try scope.array();
        var features = try v.iterator(scope, values);
        defer features.deinit();
        errdefer features.closePreserving();
        while (try features.next()) |feature| {
            defer scope.engine.freeValue(feature);
            _ = try scope.invoke(trimmed, "push", &.{try scope.invoke(feature, "trim", &.{})});
        }
        if (!scope.truthy(try scope.invoke(trimmed, "includes", &.{try scope.text("oauth-2025-04-20")}))) {
            _ = try scope.invoke(trimmed, "push", &.{try scope.text("oauth-2025-04-20")});
            _ = try scope.invoke(result, "set", &.{ try scope.text("anthropic-beta"), try scope.invoke(trimmed, "join", &.{try scope.text(",")}) });
        }
    }
    return result;
}
fn read(scope: *Scope, owner: c.JSValue) !void {
    if (scope.truthy(try v.optional(scope, try scope.get(owner, "streamSignal"), "aborted"))) return v.errorText(scope, try scope.text("Request was aborted"));
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
            // The default SDK checks fetch Response.ok before exposing its
            // asResponse result. A caller-supplied SDK client's asResponse
            // result is already the public boundary and receives no second
            // SDK status interpretation here.
            if (!scope.truthy(try scope.get(owner, "usesSdkClient")) and v.nullish(try scope.get(owner, "http")) and !scope.truthy(try scope.get(value, "ok"))) {
                const status = try scope.get(value, "status");
                if (scope.equal(status, c.JS_NewInt32(scope.engine.context, 401))) try invalidateFederation(scope, owner);
                const text_method = try scope.get(value, "text");
                if (!v.nullish(text_method)) return wait(scope, owner, try scope.call(text_method, value, &.{}), .rejected_body);
                return read(scope, owner);
            }
            try wait(scope, owner, try responseHook(scope, owner, value), .response);
        },
        .response => {
            _ = try scope.invoke(try scope.get(owner, "decoder"), "start", &.{});
            try scope.put(owner, "streamSignal", try v.optional(scope, try scope.get(owner, "options"), "signal"));
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
    const headers = if (v.nullish(try scope.get(owner, "http"))) header_values else try scope.own(try @import("native_headers.zig").fromRecord(scope.engine, header_values));
    return @import("native_ai_anthropic_api_error.zig").generateValue(scope, try scope.get(try scope.get(owner, "agent"), "errors"), status, body, text, headers);
}
