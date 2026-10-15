//! Actual native Responses stream APIs over owned HTTP/SSE transport.
//! Private binding until genuine full wire/request/event/callback qualification.
const std = @import("std");
const v = @import("native_ai_provider_values.zig");
const Scope = v.Scope;
const c = v.c;
const flow = @import("native_agent_async.zig");
const http = @import("native_ai_http.zig");
const request = @import("native_ai_responses_request.zig");
const Stage = enum(c_int) { payload, ready, response, next, chunk, retried };
fn getMode(scope: *Scope, dependencies: c.JSValue) !request.Mode {
    const value = try scope.get(dependencies, "mode");
    return if (try v.eq(scope, value, "azure")) .azure else if (try v.eq(scope, value, "codex")) .codex else .standard;
}
pub fn create(engine: *v.em.Engine) !c.JSValue {
    return createMode(engine, .standard);
}
pub fn createMode(engine: *v.em.Engine, mode: request.Mode) !c.JSValue {
    try @import("native_stream.zig").install(engine);
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const dependencies = try scope.own(try @import("native_ai_openai_dependencies.zig").create(engine));
    try scope.put(dependencies, "userAgentOS", try userAgentOS(&scope));
    try scope.put(dependencies, "mode", try scope.text(@tagName(mode)));
    const result = try scope.object();
    inline for (.{ "stream", "streamSimple" }, 0..) |name, index| {
        const Adapter = struct {
            fn call(host: *v.em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
                var values = [_]c.JSValue{c.pi_js_undefined()} ** 3;
                for (args[0..@min(args.len, values.len)], 0..) |value, i| values[i] = value;
                return stream(host, roots[0], &values, index == 1);
            }
        };
        try scope.put(result, name, try scope.own(try @import("native_node_function.zig").create(engine, name, 3, Adapter.call, &.{dependencies})));
    }
    return c.JS_DupValue(engine.context, result);
}
fn userAgentOS(scope: *Scope) !c.JSValue {
    const process = try scope.global("process");
    const versions = try v.optional(scope, process, "versions");
    if (c.JS_IsUndefined(process) or !(scope.truthy(try v.optional(scope, versions, "node")) or scope.truthy(try v.optional(scope, versions, "bun")))) return c.pi_js_null();
    const loader = try scope.get(process, "getBuiltinModule");
    if (v.nullish(loader)) return c.pi_js_null();
    const os = try scope.call(loader, process, &.{try scope.text("node:os")});
    return if (v.nullish(os)) c.pi_js_null() else os;
}
fn userAgent(scope: *Scope, dependencies: c.JSValue) !c.JSValue {
    const os = try scope.get(dependencies, "userAgentOS");
    if (!scope.truthy(os)) return scope.text("pi (browser)");
    var result = try scope.concat(try scope.text("pi ("), try scope.stringify(try scope.invoke(os, "platform", &.{})));
    result = try scope.concat(try scope.concat(result, try scope.text(" ")), try scope.stringify(try scope.invoke(os, "release", &.{})));
    result = try scope.concat(try scope.concat(result, try scope.text("; ")), try scope.stringify(try scope.invoke(os, "arch", &.{})));
    return scope.concat(result, try scope.text(")"));
}
fn hasHeader(scope: *Scope, headers: c.JSValue, expected: []const u8) !bool {
    if (!scope.truthy(headers)) return false;
    var rows = try v.iterator(scope, try scope.invoke(try scope.global("Object"), "entries", &.{headers}));
    defer rows.deinit();
    errdefer rows.closePreserving();
    while (try rows.next()) |entry| {
        defer scope.engine.freeValue(entry);
        var row: Scope = .{ .engine = scope.engine };
        defer row.deinit();
        const key = try v.at(&row, entry, 0);
        const value = try v.at(&row, entry, 1);
        if (try v.eq(&row, try row.invoke(key, "toLowerCase", &.{}), expected) and !c.JS_IsNull(value) and try v.length(&row, try row.invoke(value, "trim", &.{})) > 0) return true;
    }
    return false;
}
fn apiKey(scope: *Scope, model: c.JSValue, options: c.JSValue, mode: request.Mode) !c.JSValue {
    const key = try v.optional(scope, options, "apiKey");
    if (scope.truthy(key)) return key;
    const headers = try v.optional(scope, options, "headers");
    if (mode == .standard and (try hasHeader(scope, headers, "authorization") or try hasHeader(scope, headers, "cf-aig-authorization"))) return scope.text("unused");
    return v.errorText(scope, try scope.concat(try scope.text("No API key for provider: "), try scope.stringify(try scope.get(model, "provider"))));
}
fn stream(engine: *v.em.Engine, dependencies: c.JSValue, args: []const c.JSValue, simple: bool) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    var options = args[2];
    if (simple) {
        _ = try apiKey(&scope, args[0], options, try getMode(&scope, dependencies));
        options = try @import("native_ai_openai_dependencies.zig").options(&scope, dependencies, args[0], args[1], options);
    }
    const module = engine.native_module_values.get("@earendil-works/pi-ai") orelse return error.NativeOpenAIStreamMissing;
    const constructor = try scope.get(module, "AssistantMessageEventStream");
    const outer = try scope.own(try engine.checked(c.JS_CallConstructor(engine.context, constructor, 0, null)));
    const compat = try scope.own(try request.compat(engine, args[0], try getMode(&scope, dependencies)));
    const context = try scope.own(try @import("native_ai_provider_transcript.zig").resolve(engine, args[1], scope.truthy(try scope.get(compat, "supportsMidConvoSystemMessages"))));
    const pending = try flow.create(engine, dependencies);
    defer engine.freeValue(pending.owner);
    defer engine.freeValue(pending.promise);
    const owner = pending.owner;
    try scope.put(owner, "model", args[0]);
    try scope.put(owner, "context", context);
    try scope.put(owner, "options", options);
    try scope.put(owner, "compat", compat);
    try scope.put(owner, "stream", outer);
    try scope.put(owner, "http", c.pi_js_undefined());
    try scope.put(owner, "seenDone", c.pi_js_bool(engine.context, 0));
    try scope.put(owner, "attempt", c.JS_NewInt32(engine.context, 0));
    const declared = try scope.own(try @import("native_ai_provider_transcript.zig").declared(engine, try scope.get(context, "messages")));
    const properties = try scope.own(try @import("native_ai_openai_tools.zig").grammarProperties(engine, declared, scope.truthy(try scope.get(compat, "supportsOpenAIGrammarTools"))));
    const effort = try request.configurationEffort(&scope, args[0], options, compat, try getMode(&scope, dependencies));
    try scope.put(owner, "effort", effort);
    const decoder = try scope.own(try @import("native_ai_responses_decode.zig").create(engine, args[0], outer, try scope.get(dependencies, "json"), properties, options, effort, try getMode(&scope, dependencies) == .codex));
    try scope.put(owner, "decoder", decoder);
    setup(&scope, owner, properties) catch |err| try failError(&scope, owner, err);
    return c.JS_DupValue(engine.context, outer);
}
fn setup(scope: *Scope, owner: c.JSValue, properties: c.JSValue) !void {
    const options = try scope.get(owner, "options");
    const mode = try getMode(scope, try scope.get(owner, "agent"));
    try scope.put(owner, "apiKey", try apiKey(scope, try scope.get(owner, "model"), options, mode));
    const retention = if (mode == .codex) (if (try v.eq(scope, try v.optional(scope, options, "cacheRetention"), "none")) try scope.text("none") else try scope.text("short")) else try @import("native_ai_openai_request.zig").cacheRetention(scope, options);
    try scope.put(owner, "retention", retention);
    const params = try scope.own(try request.build(scope.engine, try scope.get(owner, "model"), try scope.get(owner, "context"), options, try scope.get(owner, "compat"), retention, properties, try scope.get(owner, "effort"), try scope.get(try scope.get(owner, "agent"), "simple"), try getMode(scope, try scope.get(owner, "agent"))));
    if (mode == .azure) {
        const config = try @import("native_ai_responses_azure.zig").resolve(scope, try scope.get(owner, "agent"), try scope.get(owner, "model"), options);
        try scope.put(owner, "azure", config);
        try scope.put(params, "model", try scope.get(config, "deployment"));
    }
    if (mode == .codex) try scope.put(owner, "accountId", try accountId(scope, try scope.get(owner, "apiKey")));
    try scope.put(owner, "payload", params);
    try wait(scope, owner, try hook(scope, owner, "onPayload", params), .payload);
}
fn hook(scope: *Scope, owner: c.JSValue, key: [*:0]const u8, value: c.JSValue) !c.JSValue {
    const options = try scope.get(owner, "options");
    const callback = try v.optional(scope, options, key);
    return if (v.nullish(callback)) c.pi_js_undefined() else scope.call(callback, options, &.{ value, try scope.get(owner, "model") });
}
fn wait(scope: *Scope, owner: c.JSValue, value: c.JSValue, stage: Stage) !void {
    try flow.wait(continued, scope.engine, owner, value, @intFromEnum(stage));
}
fn continued(engine: *v.em.Engine, owner: c.JSValue, value: c.JSValue, rejected: bool, raw: c_int) !void {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    if (rejected) {
        const stage: Stage = @enumFromInt(raw);
        if (stage == .ready) {
            // The SDK wraps request-establishment failures; Codex's direct
            // fetch path and every entered response reader retain raw errors.
            const mode = try getMode(&scope, try scope.get(owner, "agent"));
            retryOrFail(&scope, owner, if (mode == .codex) value else try transportError(&scope, owner, value)) catch |err| try failError(&scope, owner, err);
        } else fail(&scope, owner, value) catch |err| try flow.rejectError(engine, owner, err);
        return;
    }
    advance(&scope, owner, value, @enumFromInt(raw)) catch |err| try failError(&scope, owner, err);
}
fn aborted(scope: *Scope, owner: c.JSValue) !bool {
    return scope.truthy(try v.optional(scope, try v.optional(scope, try scope.get(owner, "options"), "signal"), "aborted"));
}
fn failError(scope: *Scope, owner: c.JSValue, err: anyerror) !void {
    const reason = flow.reason(scope.engine, err);
    defer scope.engine.freeValue(reason);
    if (scope.engine.captured_exception) |captured| {
        scope.engine.captured_exception = null;
        scope.engine.freeValue(captured);
    }
    return fail(scope, owner, reason);
}
fn fail(scope: *Scope, owner: c.JSValue, reason: c.JSValue) !void {
    const transport = try scope.get(owner, "http");
    if (!v.nullish(transport)) _ = try scope.invoke(transport, "cancel", &.{});
    _ = scope.invoke(try scope.get(owner, "decoder"), "fail", &.{ reason, c.pi_js_bool(scope.engine.context, @intFromBool(try aborted(scope, owner))) }) catch |err| {
        try @import("native_stream.zig").reject(scope.engine, try scope.get(owner, "stream"), reason);
        try flow.rejectError(scope.engine, owner, err);
        return;
    };
    try flow.settle(scope.engine, owner, false, c.pi_js_undefined());
}
fn mergeHeaders(scope: *Scope, target: c.JSValue, source: c.JSValue) !void {
    if (v.nullish(source)) return;
    var rows = try v.iterator(scope, try scope.invoke(try scope.global("Object"), "entries", &.{source}));
    defer rows.deinit();
    errdefer rows.closePreserving();
    while (try rows.next()) |entry| {
        defer scope.engine.freeValue(entry);
        const name = try scope.invoke(try v.at(scope, entry, 0), "toLowerCase", &.{});
        try v.js.setKey(scope.engine, target, name, try v.at(scope, entry, 1));
    }
}
fn buildHeaders(scope: *Scope, owner: c.JSValue) !c.JSValue {
    const mode = try getMode(scope, try scope.get(owner, "agent"));
    const result = try scope.object();
    try scope.put(result, "accept", try scope.text(if (mode == .codex) "text/event-stream" else "application/json"));
    try scope.put(result, "content-type", try scope.text("application/json"));
    try scope.put(result, if (mode == .azure) "api-key" else "authorization", if (mode == .azure) try scope.get(owner, "apiKey") else try scope.concat(try scope.text("Bearer "), try scope.stringify(try scope.get(owner, "apiKey"))));
    const defaults = try scope.object();
    try scope.put(defaults, "User-Agent", try userAgent(scope, try scope.get(owner, "agent")));
    if (mode == .codex) try scope.put(defaults, "originator", try scope.text("pi"));
    const model = try scope.get(owner, "model");
    try v.js.spreadInto(scope.engine, defaults, try scope.get(model, "headers"));
    if (try v.eq(scope, try scope.get(model, "provider"), "github-copilot")) {
        const messages = try scope.get(try scope.get(owner, "context"), "messages");
        const count = try v.length(scope, messages);
        const last = if (count > 0) try v.at(scope, messages, count - 1) else c.pi_js_undefined();
        try scope.put(defaults, "X-Initiator", try scope.text(if (scope.truthy(last) and !try v.eq(scope, try scope.get(last, "role"), "user")) "agent" else "user"));
        try scope.put(defaults, "Openai-Intent", try scope.text("conversation-edits"));
        var rows = try v.iterator(scope, messages);
        defer rows.deinit();
        errdefer rows.closePreserving();
        while (try rows.next()) |message| {
            defer scope.engine.freeValue(message);
            const role = try scope.get(message, "role");
            const content = try scope.get(message, "content");
            if (!(try v.eq(scope, role, "user") or try v.eq(scope, role, "toolResult")) or !try v.array(scope, content)) continue;
            var blocks = try v.iterator(scope, content);
            defer blocks.deinit();
            errdefer blocks.closePreserving();
            var found = false;
            while (try blocks.next()) |block| {
                defer scope.engine.freeValue(block);
                if (try v.eq(scope, try scope.get(block, "type"), "image")) {
                    found = true;
                    break;
                }
            }
            if (found) {
                try scope.put(defaults, "Copilot-Vision-Request", try scope.text("true"));
                break;
            }
        }
    }
    const options = try scope.get(owner, "options");
    const session = if (try v.eq(scope, try scope.get(owner, "retention"), "none")) c.pi_js_undefined() else try v.optional(scope, options, "sessionId");
    const compat = try scope.get(owner, "compat");
    if (mode == .standard and scope.truthy(session)) {
        if (try v.eq(scope, try scope.get(compat, "sessionAffinityFormat"), "openrouter")) try scope.put(defaults, "x-session-id", session) else {
            if (try v.eq(scope, try scope.get(compat, "sessionAffinityFormat"), "openai")) try scope.put(defaults, "session_id", session);
            try scope.put(defaults, "x-client-request-id", session);
        }
    }
    try v.js.spreadInto(scope.engine, defaults, try v.optional(scope, options, "headers"));
    try mergeHeaders(scope, result, defaults);
    if (mode == .codex) {
        // Codex reapplies identity headers after nullable caller overrides.
        try scope.put(result, "authorization", try scope.concat(try scope.text("Bearer "), try scope.get(owner, "apiKey")));
        try scope.put(result, "chatgpt-account-id", try scope.get(owner, "accountId"));
        try scope.put(result, "openai-beta", try scope.text("responses=experimental"));
        try scope.put(result, "accept", try scope.text("text/event-stream"));
        try scope.put(result, "content-type", try scope.text("application/json"));
        if (scope.truthy(session)) {
            const clamped = try request.cacheKey(scope, session);
            try scope.put(result, "session-id", clamped);
            try scope.put(result, "x-client-request-id", clamped);
        }
    }
    return result;
}
fn accountId(scope: *Scope, token: c.JSValue) !c.JSValue {
    const generation = scope.engine.native_allocation_generation;
    return accountIdBody(scope, token) catch |err| {
        try @import("native_ai_partial_json.zig").discard(scope.engine, err, generation);
        return v.errorText(scope, try scope.text("Failed to extract accountId from token"));
    };
}
fn accountIdBody(scope: *Scope, token: c.JSValue) !c.JSValue {
    const parts = try scope.invoke(token, "split", &.{try scope.text(".")});
    if (try v.length(scope, parts) != 3) return error.InvalidCodexToken;
    const decoded = try scope.call(try scope.global("atob"), c.pi_js_undefined(), &.{try v.at(scope, parts, 1)});
    const payload = try scope.invoke(try scope.global("JSON"), "parse", &.{decoded});
    const id = try v.optional(scope, try v.optional(scope, payload, "https://api.openai.com/auth"), "chatgpt_account_id");
    if (!scope.truthy(id)) return error.InvalidCodexToken;
    return id;
}
fn open(scope: *Scope, owner: c.JSValue) !void {
    const engine = scope.engine;
    const options = try scope.get(owner, "options");
    const mode = try getMode(scope, try scope.get(owner, "agent"));
    const header_object = try buildHeaders(scope, owner);
    if (mode == .codex) try scope.put(header_object, "content-encoding", try scope.text("zstd"));
    var fields: std.ArrayList(std.http.Header) = .empty;
    defer {
        for (fields.items) |field| {
            engine.gpa.free(field.name);
            engine.gpa.free(field.value);
        }
        fields.deinit(engine.gpa);
    }
    var rows = try v.iterator(scope, try scope.invoke(try scope.global("Object"), "entries", &.{header_object}));
    defer rows.deinit();
    errdefer rows.closePreserving();
    while (try rows.next()) |entry| {
        defer engine.freeValue(entry);
        const value = try v.at(scope, entry, 1);
        if (v.nullish(value)) continue;
        const name = try engine.toString(try v.at(scope, entry, 0));
        errdefer engine.gpa.free(name);
        const text = try engine.toString(value);
        errdefer engine.gpa.free(text);
        try fields.append(engine.gpa, .{ .name = name, .value = text });
    }
    var base = try scope.get(try scope.get(owner, "model"), "baseUrl");
    if (mode == .codex and (!scope.truthy(base) or try v.length(scope, try scope.invoke(base, "trim", &.{})) == 0)) base = try scope.text("https://chatgpt.com/backend-api");
    const trimmed = if (scope.truthy(try scope.invoke(base, "endsWith", &.{try scope.text("/")}))) try scope.invoke(base, "slice", &.{ c.JS_NewInt32(engine.context, 0), c.JS_NewInt32(engine.context, -1) }) else base;
    const url_value = if (mode == .azure) try @import("native_ai_responses_azure.zig").endpoint(scope, try scope.get(owner, "azure")) else if (mode == .codex and scope.truthy(try scope.invoke(trimmed, "endsWith", &.{try scope.text("/codex/responses")}))) trimmed else try scope.concat(trimmed, try scope.text(if (mode == .codex and !scope.truthy(try scope.invoke(trimmed, "endsWith", &.{try scope.text("/codex")}))) "/codex/responses" else "/responses"));
    const url = try engine.toString(url_value);
    defer engine.gpa.free(url);
    const payload = try engine.toString(try scope.invoke(try scope.global("JSON"), "stringify", &.{try scope.get(owner, "payload")}));
    defer engine.gpa.free(payload);
    const compressed = if (mode == .codex) try @import("../ai/openai_responses.zig").encodeZstdRequestBody(engine.gpa, payload) else null;
    defer if (compressed) |bytes| engine.gpa.free(bytes);
    const body_bytes = compressed orelse payload;
    const timeout = try v.optional(scope, options, "timeoutMs");
    var milliseconds: i64 = 600000;
    if (!c.JS_IsUndefined(timeout) and c.JS_ToInt64(engine.context, &milliseconds, timeout) < 0) return v.js.capture(engine);
    const fetch = try v.optional(scope, options, "fetch");
    var transport: c.JSValue = undefined;
    if (!v.nullish(fetch)) {
        const init = try scope.object();
        try scope.put(init, "method", try scope.text("POST"));
        try scope.put(init, "headers", header_object);
        const body = if (compressed) |bytes| encoded: {
            const buffer = try scope.own(try engine.checked(c.JS_NewArrayBufferCopy(engine.context, bytes.ptr, bytes.len)));
            var args = [_]c.JSValue{buffer};
            break :encoded try scope.own(try engine.checked(c.JS_NewTypedArray(engine.context, args.len, &args, c.JS_TYPED_ARRAY_UINT8)));
        } else try scope.text(payload);
        try scope.put(init, "body", body);
        try scope.put(init, "signal", try v.optional(scope, options, "signal"));
        transport = try scope.own(try @import("native_ai_responses_fetch.zig").open(engine, fetch, url_value, init));
    } else transport = try scope.own(try http.open(engine, .{ .url = url, .payload = body_bytes, .headers = fields.items, .timeout_ms = @intCast(@max(0, milliseconds)) }, try v.optional(scope, options, "signal")));
    try scope.put(owner, "http", transport);
    try scope.put(owner, "iterator", try scope.get(transport, "events"));
    try wait(scope, owner, try scope.get(transport, "ready"), .ready);
}
fn next(scope: *Scope, owner: c.JSValue) !void {
    try wait(scope, owner, try scope.invoke(try scope.get(owner, "iterator"), "next", &.{}), .next);
}
fn advance(scope: *Scope, owner: c.JSValue, value: c.JSValue, stage: Stage) !void {
    switch (stage) {
        .payload => {
            if (!c.JS_IsUndefined(value)) try scope.put(owner, "payload", value);
            try open(scope, owner);
        },
        .ready => {
            try scope.put(owner, "response", value);
            const status = try scope.get(value, "status");
            const arithmetic = @import("native_image_arithmetic.zig");
            if (try arithmetic.compare(scope.engine, .less, status, c.JS_NewInt32(scope.engine.context, 200)) or try arithmetic.compare(scope.engine, .greater_equal, status, c.JS_NewInt32(scope.engine.context, 300))) {
                try scope.put(owner, "httpError", c.pi_js_bool(scope.engine.context, 1));
                return next(scope, owner);
            }
            try scope.put(owner, "httpError", c.pi_js_bool(scope.engine.context, 0));
            const observed = try scope.object();
            try scope.put(observed, "status", status);
            try scope.put(observed, "headers", try scope.get(value, "headers"));
            try wait(scope, owner, try hook(scope, owner, "onResponse", observed), .response);
        },
        .response => {
            _ = try scope.invoke(try scope.get(owner, "decoder"), "start", &.{});
            try next(scope, owner);
        },
        .next => {
            if (scope.truthy(try scope.get(value, "done"))) {
                _ = try scope.invoke(try scope.get(owner, "decoder"), "finish", &.{c.pi_js_bool(scope.engine.context, @intFromBool(try aborted(scope, owner)))});
                return flow.settle(scope.engine, owner, false, c.pi_js_undefined());
            }
            const frame = try scope.get(value, "value");
            if (try v.eq(scope, try scope.get(frame, "type"), "error_body")) {
                const reason = try sdkError(scope, try scope.get(try scope.get(owner, "response"), "status"), try scope.get(frame, "body"));
                try scope.put(reason, "headers", try scope.get(try scope.get(owner, "response"), "headers"));
                return retryOrFail(scope, owner, reason);
            }
            if (scope.truthy(try scope.get(owner, "seenDone"))) return next(scope, owner);
            const data = try scope.get(frame, "data");
            if (scope.truthy(try scope.invoke(data, "startsWith", &.{try scope.text("[DONE]")}))) {
                try scope.put(owner, "seenDone", c.pi_js_bool(scope.engine.context, 1));
                return next(scope, owner);
            }
            const decoded = try decodeJSON(scope, data);
            try scope.put(owner, "chunk", decoded);
            try wait(scope, owner, try hook(scope, owner, "onProviderStreamEvent", decoded), .chunk);
        },
        .chunk => {
            var event = try scope.get(owner, "chunk");
            if (try getMode(scope, try scope.get(owner, "agent")) == .codex) event = try mapCodex(scope, owner, event);
            _ = try scope.invoke(try scope.get(owner, "decoder"), "push", &.{event});
            if (scope.truthy(try scope.get(owner, "codexTerminal"))) {
                _ = try scope.invoke(try scope.get(owner, "http"), "cancel", &.{});
                _ = try scope.invoke(try scope.get(owner, "decoder"), "finish", &.{c.pi_js_bool(scope.engine.context, @intFromBool(try aborted(scope, owner)))});
                return flow.settle(scope.engine, owner, false, c.pi_js_undefined());
            }
            try next(scope, owner);
        },
        .retried => try open(scope, owner),
    }
}
fn mapCodex(scope: *Scope, owner: c.JSValue, event: c.JSValue) !c.JSValue {
    const typ = try scope.get(event, "type");
    if (try v.eq(scope, typ, "error")) {
        const nested = try scope.get(event, "error");
        var code = try scope.get(event, "code");
        if (!c.JS_IsString(code)) code = try v.optional(scope, nested, "code");
        var message = try scope.get(event, "message");
        if (!c.JS_IsString(message)) message = try v.optional(scope, nested, "message");
        const fallback = if (scope.truthy(message)) message else if (scope.truthy(code)) code else try scope.invoke(try scope.global("JSON"), "stringify", &.{event});
        return v.errorText(scope, try scope.concat(try scope.text("Codex error: "), fallback));
    }
    if (try v.eq(scope, typ, "response.failed")) {
        const message = try v.optional(scope, try v.optional(scope, try v.optional(scope, event, "response"), "error"), "message");
        return v.errorText(scope, if (scope.truthy(message)) message else try scope.text("Codex response failed"));
    }
    if (try v.eq(scope, typ, "response.done") or try v.eq(scope, typ, "response.completed") or try v.eq(scope, typ, "response.incomplete")) {
        try scope.put(owner, "codexTerminal", c.pi_js_bool(scope.engine.context, 1));
        const response = try scope.get(event, "response");
        const end_turn = try v.optional(scope, response, "end_turn");
        if (c.JS_IsBool(end_turn)) try scope.put(try scope.get(try scope.get(owner, "decoder"), "output"), "endTurn", end_turn);
        const mapped = try v.spread(scope, event);
        try scope.put(mapped, "type", try scope.text("response.completed"));
        if (scope.truthy(response)) {
            const normalized = try v.spread(scope, response);
            const status = try scope.get(response, "status");
            var valid = false;
            inline for (.{ "completed", "incomplete", "failed", "cancelled", "queued", "in_progress" }) |s| {
                if (try v.eq(scope, status, s)) valid = true;
            }
            try scope.put(normalized, "status", if (valid) status else c.pi_js_undefined());
            try scope.put(mapped, "response", normalized);
        }
        return mapped;
    }
    return event;
}
fn decodeJSON(scope: *Scope, text: c.JSValue) !c.JSValue {
    var diagnostics = @import("native_ai_json_scope.zig").Guard.enter(scope.engine);
    defer diagnostics.deinit();
    return scope.invoke(try scope.global("JSON"), "parse", &.{text});
}
fn sdkError(scope: *Scope, status: c.JSValue, body: c.JSValue) !c.JSValue {
    const generation = scope.engine.native_allocation_generation;
    const parsed = scope.invoke(try scope.global("JSON"), "parse", &.{body}) catch |err| {
        try @import("native_ai_partial_json.zig").discard(scope.engine, err, generation);
        return sdkErrorValue(scope, status, c.pi_js_undefined(), body);
    };
    return sdkErrorValue(scope, status, try v.optional(scope, parsed, "error"), body);
}
fn sdkErrorValue(scope: *Scope, status: c.JSValue, error_body: c.JSValue, fallback: c.JSValue) !c.JSValue {
    var message = try v.optional(scope, error_body, "message");
    if (scope.truthy(message)) {
        if (!c.JS_IsString(message)) message = try scope.invoke(try scope.global("JSON"), "stringify", &.{message});
    } else if (scope.truthy(error_body)) message = try scope.invoke(try scope.global("JSON"), "stringify", &.{error_body}) else message = fallback;
    const has_status = scope.truthy(status);
    if (has_status and scope.truthy(message)) message = try scope.concat(try scope.concat(try scope.stringify(status), try scope.text(" ")), try scope.stringify(message)) else if (has_status) message = try scope.concat(try scope.stringify(status), try scope.text(" status code (no body)")) else if (!scope.truthy(message)) message = try scope.text("(no status code or body)");
    const result = try scope.own(try v.js.builtin(scope.engine, "Error", &.{message}));
    try scope.put(result, "status", status);
    try scope.put(result, "headers", c.pi_js_undefined());
    try scope.put(result, "error", error_body);
    return result;
}
fn abortError(scope: *Scope) !c.JSValue {
    const result = try scope.own(try v.js.builtin(scope.engine, "Error", &.{try scope.text("Request aborted")}));
    try scope.put(result, "name", try scope.text("AbortError"));
    return result;
}
fn transportError(scope: *Scope, owner: c.JSValue, value: c.JSValue) !c.JSValue {
    if (try aborted(scope, owner)) return abortError(scope);
    const code = try v.optional(scope, value, "code");
    const result = try scope.own(try v.js.builtin(scope.engine, "Error", &.{try scope.text(if (try v.eq(scope, code, "ProviderRequestTimeout")) "Request timed out." else "Connection error.")}));
    try scope.put(result, "status", c.pi_js_undefined());
    try scope.put(result, "headers", c.pi_js_undefined());
    try scope.put(result, "cause", value);
    return result;
}
fn binary(scope: *Scope, operation: @import("native_image_arithmetic.zig").Operation, left: c.JSValue, right: c.JSValue) !c.JSValue {
    return scope.own(try @import("native_image_arithmetic.zig").binary(scope.engine, operation, left, right));
}
fn retryOrFail(scope: *Scope, owner: c.JSValue, reason: c.JSValue) !void {
    if (try aborted(scope, owner)) return fail(scope, owner, try abortError(scope));
    const options = try scope.get(owner, "options");
    const raw_max = try v.optional(scope, options, "maxRetries");
    const maximum = if (v.nullish(raw_max)) c.JS_NewInt32(scope.engine.context, 0) else raw_max;
    const attempt = try scope.get(owner, "attempt");
    const arithmetic = @import("native_image_arithmetic.zig");
    if (try arithmetic.compare(scope.engine, .greater_equal, attempt, maximum)) return fail(scope, owner, reason);
    const headers_value = try scope.get(reason, "headers");
    const hint = try v.optional(scope, headers_value, "x-should-retry");
    const status = try scope.get(reason, "status");
    const retryable = if (try v.eq(scope, hint, "true")) true else if (try v.eq(scope, hint, "false")) false else c.JS_IsUndefined(status) or scope.equal(status, c.JS_NewInt32(scope.engine.context, 408)) or scope.equal(status, c.JS_NewInt32(scope.engine.context, 409)) or scope.equal(status, c.JS_NewInt32(scope.engine.context, 429)) or (c.JS_IsNumber(status) and try arithmetic.compare(scope.engine, .greater_equal, status, c.JS_NewInt32(scope.engine.context, 500)));
    if (!retryable) return fail(scope, owner, reason);
    try scope.put(owner, "attempt", try binary(scope, .add, attempt, c.JS_NewInt32(scope.engine.context, 1)));
    var delay = c.pi_js_undefined();
    const number = try scope.global("Number");
    const after_ms = try v.optional(scope, headers_value, "retry-after-ms");
    if (scope.truthy(after_ms)) {
        const parsed = try scope.invoke(number, "parseFloat", &.{after_ms});
        if (scope.truthy(try scope.invoke(number, "isFinite", &.{parsed}))) delay = parsed;
    }
    if (c.JS_IsUndefined(delay)) {
        const after = try v.optional(scope, headers_value, "retry-after");
        if (scope.truthy(after)) {
            const seconds = try scope.invoke(number, "parseFloat", &.{after});
            const parsed = if (scope.truthy(try scope.invoke(number, "isNaN", &.{seconds}))) try binary(scope, .subtract, try scope.invoke(try scope.global("Date"), "parse", &.{after}), try scope.invoke(try scope.global("Date"), "now", &.{})) else try binary(scope, .multiply, seconds, c.JS_NewInt32(scope.engine.context, 1000));
            if (scope.truthy(try scope.invoke(number, "isFinite", &.{parsed}))) delay = parsed;
        }
    }
    if (!c.JS_IsUndefined(delay)) {
        const configured = try v.optional(scope, options, "maxRetryDelayMs");
        const cap = if (v.nullish(configured)) c.JS_NewInt32(scope.engine.context, 60000) else configured;
        if (try arithmetic.compare(scope.engine, .greater, cap, c.JS_NewInt32(scope.engine.context, 0)) and try arithmetic.compare(scope.engine, .greater, delay, cap)) {
            const seconds = try scope.invoke(try scope.global("Math"), "ceil", &.{try binary(scope, .divide, delay, c.JS_NewInt32(scope.engine.context, 1000))});
            const limit = try scope.invoke(try scope.global("Math"), "ceil", &.{try binary(scope, .divide, cap, c.JS_NewInt32(scope.engine.context, 1000))});
            var message = try scope.concat(try scope.concat(try scope.text("Server requested "), try scope.stringify(seconds)), try scope.text("s retry delay (max: "));
            message = try scope.concat(try scope.concat(message, try scope.stringify(limit)), try scope.text("s). "));
            return v.errorText(scope, try scope.concat(message, try scope.stringify(try scope.get(reason, "message"))));
        }
    } else {
        const exponential = try binary(scope, .multiply, try scope.invoke(try scope.global("Math"), "min", &.{ try binary(scope, .multiply, c.JS_NewFloat64(scope.engine.context, 0.5), try binary(scope, .power, c.JS_NewInt32(scope.engine.context, 2), attempt)), c.JS_NewInt32(scope.engine.context, 8) }), c.JS_NewInt32(scope.engine.context, 1000));
        delay = try binary(scope, .multiply, exponential, try binary(scope, .subtract, c.JS_NewInt32(scope.engine.context, 1), try binary(scope, .multiply, try scope.invoke(try scope.global("Math"), "random", &.{}), c.JS_NewFloat64(scope.engine.context, 0.25))));
    }
    try wait(scope, owner, try sleep(scope, delay, try v.optional(scope, options, "signal")), .retried);
}
fn sleep(scope: *Scope, delay: c.JSValue, signal: c.JSValue) !c.JSValue {
    const engine = scope.engine;
    const pending = try flow.create(engine, signal);
    defer engine.freeValue(pending.owner);
    errdefer engine.freeValue(pending.promise);
    if (scope.truthy(try v.optional(scope, signal, "aborted"))) {
        try flow.settle(engine, pending.owner, true, try abortError(scope));
        return pending.promise;
    }
    const Adapter = struct {
        fn timer(host: *v.em.Engine, _: c.JSValue, _: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
            var row: Scope = .{ .engine = host };
            defer row.deinit();
            const signal_value = try row.get(roots[0], "agent");
            if (!v.nullish(signal_value)) _ = try row.invoke(signal_value, "removeEventListener", &.{ try row.text("abort"), try row.get(roots[0], "onAbort") });
            try flow.settle(host, roots[0], false, c.pi_js_undefined());
            return c.pi_js_undefined();
        }
        fn abort(host: *v.em.Engine, _: c.JSValue, _: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
            var row: Scope = .{ .engine = host };
            defer row.deinit();
            _ = try row.call(try row.global("clearTimeout"), c.pi_js_undefined(), &.{try row.get(roots[0], "timeout")});
            try flow.settle(host, roots[0], true, try abortError(&row));
            return c.pi_js_undefined();
        }
    };
    const on_abort = try scope.own(try @import("native_node_function.zig").create(engine, "onAbort", 0, Adapter.abort, &.{pending.owner}));
    try scope.put(pending.owner, "onAbort", on_abort);
    const timer = try scope.own(try @import("native_node_function.zig").create(engine, "", 0, Adapter.timer, &.{pending.owner}));
    const timeout = try scope.call(try scope.global("setTimeout"), c.pi_js_undefined(), &.{ timer, try scope.invoke(try scope.global("Math"), "max", &.{ c.JS_NewInt32(engine.context, 0), delay }) });
    try scope.put(pending.owner, "timeout", timeout);
    if (!v.nullish(signal)) {
        const once = try scope.object();
        try scope.put(once, "once", c.pi_js_bool(engine.context, 1));
        _ = try scope.invoke(signal, "addEventListener", &.{ try scope.text("abort"), on_abort, once });
    }
    return pending.promise;
}
