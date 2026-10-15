//! Actual classifier JSON POST: shared owned HTTP, per-attempt signals and the
//! original native retryProviderRequest. No worker fork and no JS host runtime.
const std = @import("std");
const v = @import("native_ai_provider_values.zig");
const Scope = v.Scope;
const c = v.c;
const flow = @import("native_agent_async.zig");
const Stage = enum(c_int) { payload, retried, observed, fetched, head, body, collected, json, text, errorText };
pub const Config = struct { require_key: bool = true, observe: bool = true, headers_once: bool = false, prepared_headers: ?c.JSValue = null, sdk_defaults: ?c.JSValue = null, api_key: ?c.JSValue = null, fetch: ?c.JSValue = null, url_factory: ?c.JSValue = null, sdk_errors: bool = false, default_retries: u32 = 2 };
pub fn create(engine: *v.em.Engine) !c.JSValue {
    const retry = try @import("native_ai_provider_retry_request.zig").create(engine);
    defer engine.freeValue(retry);
    const Adapter = struct {
        fn call(host: *v.em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
            var values = [_]c.JSValue{c.pi_js_undefined()} ** 6;
            for (args[0..@min(args.len, values.len)], 0..) |value, i| values[i] = value;
            return post(host, roots[0], &values, .{});
        }
    };
    const function = try @import("native_node_function.zig").createArrow(engine, "postClassifierRequest", 6, Adapter.call, &.{retry});
    errdefer engine.freeValue(function);
    const prototype = try engine.checked(c.JS_GetAsyncFunctionPrototype(engine.context));
    defer engine.freeValue(prototype);
    if (c.JS_SetPrototype(engine.context, function, prototype) < 0) return v.js.capture(engine);
    return function;
}
pub fn post(engine: *v.em.Engine, retry: c.JSValue, args: []const c.JSValue, config: Config) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const pending = try flow.create(engine, retry);
    defer engine.freeValue(pending.owner);
    errdefer engine.freeValue(pending.promise);
    const owner = pending.owner;
    try @import("native_ai_classifier_values.zig").generation(&scope, owner);
    inline for (.{ "label", "url", "model", "payload", "options", "noRetryStatuses" }, 0..) |key, i| try scope.put(owner, key, args[i]);
    try scope.put(owner, "observe", c.pi_js_bool(engine.context, @intFromBool(config.observe)));
    try scope.put(owner, "headersOnce", c.pi_js_bool(engine.context, @intFromBool(config.headers_once)));
    try scope.put(owner, "preparedHeaders", c.pi_js_bool(engine.context, @intFromBool(config.prepared_headers != null)));
    if (config.prepared_headers) |headers_value| try scope.put(owner, "headers", headers_value);
    try scope.put(owner, "preparedSdkHeaders", c.pi_js_bool(engine.context, @intFromBool(config.sdk_defaults != null)));
    if (config.sdk_defaults) |defaults| try scope.put(owner, "sdkDefaults", defaults);
    if (config.api_key) |key| try scope.put(owner, "apiKey", key);
    try scope.put(owner, "preparedFetch", c.pi_js_bool(engine.context, @intFromBool(config.fetch != null)));
    if (config.fetch) |fetch| try scope.put(owner, "fetch", fetch);
    try scope.put(owner, "urlFactory", config.url_factory orelse c.pi_js_undefined());
    try scope.put(owner, "sdk", c.pi_js_bool(engine.context, @intFromBool(config.sdk_errors)));
    try scope.put(owner, "defaultRetries", c.JS_NewUint32(engine.context, config.default_retries));
    setup(&scope, owner, config) catch |err| try rejectError(&scope, owner, err);
    return pending.promise;
}
fn rejectError(scope: *Scope, owner: c.JSValue, err: anyerror) !void {
    const reason = flow.reason(scope.engine, err);
    defer scope.engine.freeValue(reason);
    if (scope.engine.captured_exception) |captured| {
        scope.engine.captured_exception = null;
        scope.engine.freeValue(captured);
    }
    try flow.settle(scope.engine, owner, true, reason);
}
fn setup(scope: *Scope, owner: c.JSValue, config: Config) !void {
    const options = try scope.get(owner, "options");
    if (config.require_key) {
        if (!scope.truthy(try v.optional(scope, options, "apiKey"))) return v.errorText(scope, try scope.concat(try scope.text("No API key for provider: "), try scope.stringify(try scope.get(try scope.get(owner, "model"), "provider"))));
        try scope.put(owner, "apiKey", try scope.get(options, "apiKey"));
    }
    const callback = if (config.observe) try v.optional(scope, options, "onPayload") else c.pi_js_undefined();
    if (!config.observe) return startRetry(scope, owner, c.pi_js_undefined());
    const value = if (v.nullish(callback)) c.pi_js_undefined() else try scope.call(callback, options, &.{ try scope.get(owner, "payload"), try scope.get(owner, "model") });
    try flow.wait(continued, scope.engine, owner, value, @intFromEnum(Stage.payload));
}
fn hook(scope: *Scope, owner: c.JSValue, response: c.JSValue) !c.JSValue {
    if (!scope.truthy(try scope.get(owner, "observe"))) return c.pi_js_undefined();
    const options = try scope.get(owner, "options");
    const callback = try v.optional(scope, options, "onResponse");
    if (v.nullish(callback)) return c.pi_js_undefined();
    const metadata = try scope.object();
    try scope.put(metadata, "status", try scope.get(response, "status"));
    const headers = try scope.object();
    var iterator = try v.iterator(scope, try scope.invoke(try scope.get(response, "headers"), "entries", &.{}));
    defer iterator.deinit();
    errdefer iterator.closePreserving();
    while (try iterator.next()) |entry| {
        defer scope.engine.freeValue(entry);
        var row: Scope = .{ .engine = scope.engine };
        defer row.deinit();
        try v.js.setKey(scope.engine, headers, try v.at(&row, entry, 0), try v.at(&row, entry, 1));
    }
    try scope.put(metadata, "headers", headers);
    return scope.call(callback, options, &.{ metadata, try scope.get(owner, "model") });
}
pub fn headers(scope: *Scope, sources: []const c.JSValue) !c.JSValue {
    const result = try @import("native_ai_openai_headers.zig").providerRecord(scope, sources);
    return if (c.JS_IsUndefined(result)) scope.object() else result;
}
fn buildHeaders(scope: *Scope, owner: c.JSValue, optional_key: bool) !c.JSValue {
    const options = try scope.get(owner, "options");
    const defaults = try scope.object();
    if (!optional_key) try scope.put(defaults, "authorization", try scope.concat(try scope.text("Bearer "), try scope.stringify(try scope.get(owner, "apiKey"))));
    try scope.put(defaults, "content-type", try scope.text("application/json"));
    if (optional_key and scope.truthy(try v.optional(scope, options, "apiKey"))) try scope.put(defaults, "authorization", try scope.concat(try scope.text("Bearer "), try scope.stringify(try scope.get(options, "apiKey"))));
    return headers(scope, &.{ defaults, try scope.get(try scope.get(owner, "model"), "headers"), try v.optional(scope, options, "headers") });
}
fn continued(engine: *v.em.Engine, owner: c.JSValue, value: c.JSValue, rejected: bool, raw: c_int) !void {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    if (rejected) return flow.settle(engine, owner, true, value);
    switch (@as(Stage, @enumFromInt(raw))) {
        .payload => startRetry(&scope, owner, value) catch |err| try rejectError(&scope, owner, err),
        .retried => {
            try scope.put(owner, "result", value);
            if (!scope.truthy(try scope.get(owner, "observe"))) return flow.settle(engine, owner, false, try scope.get(value, "json"));
            observe(&scope, owner, value) catch |err| try rejectError(&scope, owner, err);
        },
        .observed => try flow.settle(engine, owner, false, try scope.get(try scope.get(owner, "result"), "json")),
        else => unreachable,
    }
}
fn observe(scope: *Scope, owner: c.JSValue, value: c.JSValue) !void {
    try flow.wait(continued, scope.engine, owner, try hook(scope, owner, try scope.get(value, "response")), @intFromEnum(Stage.observed));
}
fn startRetry(scope: *Scope, owner: c.JSValue, transformed: c.JSValue) !void {
    if (!c.JS_IsUndefined(transformed)) try scope.put(owner, "payload", transformed);
    const source_options = try scope.get(owner, "options");
    if (!scope.truthy(try scope.get(owner, "preparedFetch"))) try scope.put(owner, "fetch", try v.optional(scope, source_options, "fetch"));
    if (scope.truthy(try scope.get(owner, "sdk"))) {
        const signal = try v.optional(scope, source_options, "signal");
        try scope.put(owner, "sdkSignal", if (scope.truthy(signal)) try scope.get(source_options, "signal") else c.pi_js_undefined());
        const timeout = try v.optional(scope, source_options, "timeoutMs");
        try scope.put(owner, "sdkTimeout", if (c.JS_IsUndefined(timeout)) timeout else try scope.get(source_options, "timeoutMs"));
    }
    if (scope.truthy(try scope.get(owner, "headersOnce")) and !scope.truthy(try scope.get(owner, "preparedHeaders"))) try scope.put(owner, "headers", try buildHeaders(scope, owner, true));
    const Adapter = struct {
        fn call(host: *v.em.Engine, _: c.JSValue, _: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
            var row: Scope = .{ .engine = host };
            defer row.deinit();
            const pending = try flow.create(host, roots[0]);
            defer host.freeValue(pending.owner);
            errdefer host.freeValue(pending.promise);
            try row.put(pending.owner, "http", c.pi_js_undefined());
            attempt(&row, pending.owner) catch |err| try rejectAttemptError(&row, pending.owner, err);
            return pending.promise;
        }
    };
    const callback = try scope.own(try @import("native_node_function.zig").createArrow(scope.engine, "", 0, Adapter.call, &.{owner}));
    const options = try scope.get(owner, "options");
    const retry_options = try scope.object();
    const retries = try v.optional(scope, options, "maxRetries");
    try scope.put(retry_options, "maxRetries", if (v.nullish(retries)) try scope.get(owner, "defaultRetries") else retries);
    try scope.put(retry_options, "maxRetryDelayMs", try v.optional(scope, options, "maxRetryDelayMs"));
    try scope.put(retry_options, "signal", try v.optional(scope, options, "signal"));
    try scope.put(retry_options, "noRetryStatuses", try scope.get(owner, "noRetryStatuses"));
    try flow.wait(continued, scope.engine, owner, try scope.call(try scope.get(owner, "agent"), c.pi_js_undefined(), &.{ callback, retry_options }), @intFromEnum(Stage.retried));
}
fn attempt(scope: *Scope, pending: c.JSValue) !void {
    const owner = try scope.get(pending, "agent");
    const options = try scope.get(owner, "options");
    const sdk = scope.truthy(try scope.get(owner, "sdk"));
    const timeout = if (sdk) try scope.get(owner, "sdkTimeout") else try v.optional(scope, options, "timeoutMs");
    const url_factory = try scope.get(owner, "urlFactory");
    const request_url = if (v.nullish(url_factory)) try scope.get(owner, "url") else try scope.call(url_factory, c.pi_js_undefined(), &.{});
    var encoded_payload = c.pi_js_undefined();
    var sdk_headers = c.pi_js_undefined();
    if (sdk) {
        if (!c.JS_IsUndefined(timeout)) {
            if (!c.JS_IsNumber(timeout) or !scope.truthy(try scope.invoke(try scope.global("Number"), "isInteger", &.{timeout}))) return v.errorText(scope, try scope.text("timeout must be an integer"));
            if (try @import("native_image_arithmetic.zig").compare(scope.engine, .less, timeout, c.JS_NewInt32(scope.engine.context, 0))) return v.errorText(scope, try scope.text("timeout must be a positive integer"));
        }
        encoded_payload = try scope.invoke(try scope.global("JSON"), "stringify", &.{try scope.get(owner, "payload")});
        if (scope.truthy(try scope.get(owner, "preparedSdkHeaders"))) sdk_headers = try @import("native_ai_openai_headers.zig").buildPrepared(scope, try scope.get(owner, "sdkDefaults"), try scope.get(owner, "apiKey"), timeout);
    }
    const timeout_signal = if (!sdk and !c.JS_IsUndefined(timeout)) try scope.invoke(try scope.global("AbortSignal"), "timeout", &.{timeout}) else c.pi_js_undefined();
    try scope.put(pending, "timeoutSignal", timeout_signal);
    const caller_signal = if (sdk) try scope.get(owner, "sdkSignal") else try v.optional(scope, options, "signal");
    var signal = if (v.nullish(caller_signal)) timeout_signal else caller_signal;
    if (sdk) {
        if (scope.truthy(try v.optional(scope, caller_signal, "aborted"))) return rejectAttempt(scope, pending, try @import("native_ai_openai_api_error.zig").connection(scope, .aborted, c.pi_js_undefined()));
        const controller = try scope.own(try v.js.builtin(scope.engine, "AbortController", &.{}));
        try scope.put(pending, "controller", controller);
        signal = try scope.get(controller, "signal");
        const Abort = struct {
            fn call(host: *v.em.Engine, _: c.JSValue, _: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
                return v.js.invoke(host, roots[0], "abort", &.{});
            }
        };
        const abort_callback = try scope.own(try @import("native_node_function.zig").createArrow(scope.engine, "", 0, Abort.call, &.{controller}));
        if (scope.truthy(caller_signal)) {
            const once = try scope.object();
            try scope.put(once, "once", c.pi_js_bool(scope.engine.context, 1));
            _ = try scope.invoke(caller_signal, "addEventListener", &.{ try scope.text("abort"), abort_callback, once });
        }
        try scope.put(pending, "sdkTimer", try scope.call(try scope.global("setTimeout"), c.pi_js_undefined(), &.{ abort_callback, if (c.JS_IsUndefined(timeout)) c.JS_NewInt32(scope.engine.context, 600000) else timeout }));
    } else if (scope.truthy(caller_signal) and scope.truthy(timeout_signal)) {
        const signals = try scope.array();
        try scope.index(signals, 0, caller_signal);
        try scope.index(signals, 1, timeout_signal);
        signal = try scope.invoke(try scope.global("AbortSignal"), "any", &.{signals});
    }
    try scope.put(pending, "signal", signal);
    const fields = if (!c.JS_IsUndefined(sdk_headers)) sdk_headers else if (scope.truthy(try scope.get(owner, "headersOnce")) or scope.truthy(try scope.get(owner, "preparedHeaders"))) try scope.get(owner, "headers") else try buildHeaders(scope, owner, false);
    const payload = if (sdk) encoded_payload else try scope.invoke(try scope.global("JSON"), "stringify", &.{try scope.get(owner, "payload")});
    const fetch = try scope.get(owner, "fetch");
    if (!v.nullish(fetch)) {
        const init = try scope.object();
        try scope.put(init, "method", try scope.text("POST"));
        try scope.put(init, "headers", fields);
        try scope.put(init, "body", payload);
        try scope.put(init, "signal", signal);
        const fetched = scope.call(fetch, c.pi_js_undefined(), &.{ request_url, init }) catch |err| {
            if (err == error.OutOfMemory) return rejectAttemptError(scope, pending, err);
            const reason = flow.reason(scope.engine, err);
            defer scope.engine.freeValue(reason);
            if (scope.engine.captured_exception) |captured| {
                scope.engine.captured_exception = null;
                scope.engine.freeValue(captured);
            }
            return attemptContinued(scope.engine, pending, reason, true, @intFromEnum(Stage.fetched));
        };
        return flow.wait(attemptContinued, scope.engine, pending, fetched, @intFromEnum(Stage.fetched));
    }
    var headers_list: std.ArrayList(std.http.Header) = .empty;
    defer {
        for (headers_list.items) |field| {
            scope.engine.gpa.free(field.name);
            scope.engine.gpa.free(field.value);
        }
        headers_list.deinit(scope.engine.gpa);
    }
    const entries = if (scope.truthy(try scope.get(owner, "preparedHeaders")) or scope.truthy(try scope.get(owner, "preparedSdkHeaders"))) try scope.invoke(fields, "entries", &.{}) else try scope.invoke(try scope.global("Object"), "entries", &.{fields});
    var iterator = try v.iterator(scope, entries);
    defer iterator.deinit();
    errdefer iterator.closePreserving();
    while (try iterator.next()) |entry| {
        defer scope.engine.freeValue(entry);
        var row: Scope = .{ .engine = scope.engine };
        defer row.deinit();
        const name = try scope.engine.toString(try v.at(&row, entry, 0));
        errdefer scope.engine.gpa.free(name);
        const value = try scope.engine.toString(try v.at(&row, entry, 1));
        errdefer scope.engine.gpa.free(value);
        try headers_list.append(scope.engine.gpa, .{ .name = name, .value = value });
    }
    const url = try scope.engine.toString(request_url);
    defer scope.engine.gpa.free(url);
    const body = try scope.engine.toString(payload);
    defer scope.engine.gpa.free(body);
    const http = try scope.own(try @import("native_ai_http.zig").openWithOptions(scope.engine, .{ .url = url, .payload = body, .headers = headers_list.items, .framing = if (sdk) .bytes else .body, .stream_error_bytes = sdk }, signal, .{ .raw_header_pairs = true }));
    try scope.put(pending, "http", http);
    try flow.wait(attemptContinued, scope.engine, pending, try scope.get(http, "ready"), @intFromEnum(Stage.head));
}
fn rejectAttemptError(scope: *Scope, pending: c.JSValue, err: anyerror) !void {
    const reason = flow.reason(scope.engine, err);
    defer scope.engine.freeValue(reason);
    if (scope.engine.captured_exception) |captured| {
        scope.engine.captured_exception = null;
        scope.engine.freeValue(captured);
    }
    try rejectAttempt(scope, pending, reason);
}
fn rejectAttempt(scope: *Scope, pending: c.JSValue, reason: c.JSValue) !void {
    const http = try scope.get(pending, "http");
    if (!v.nullish(http)) _ = try scope.invoke(http, "cancel", &.{});
    const owner = try scope.get(pending, "agent");
    const options = try scope.get(owner, "options");
    if (scope.truthy(try scope.get(owner, "sdk"))) return flow.settle(scope.engine, pending, true, reason);
    const timed_out = scope.truthy(try v.optional(scope, try scope.get(pending, "timeoutSignal"), "aborted"));
    const aborted = scope.truthy(try v.optional(scope, try v.optional(scope, options, "signal"), "aborted"));
    if (timed_out and !aborted) {
        const text = try scope.concat(try scope.concat(try scope.text("Request timed out after "), try scope.stringify(try scope.get(options, "timeoutMs"))), try scope.text("ms"));
        const timeout = try scope.own(try v.js.builtin(scope.engine, "Error", &.{text}));
        try scope.set(timeout, "name", try scope.text("TimeoutError"));
        try scope.set(timeout, "status", c.pi_js_undefined());
        try scope.set(timeout, "headers", c.pi_js_undefined());
        try scope.set(timeout, "body", try scope.text(""));
        return flow.settle(scope.engine, pending, true, timeout);
    }
    try flow.settle(scope.engine, pending, true, reason);
}
fn httpError(scope: *Scope, pending: c.JSValue, response: c.JSValue, body: c.JSValue) !void {
    const owner = try scope.get(pending, "agent");
    if (scope.truthy(try scope.get(owner, "sdk"))) return rejectAttempt(scope, pending, try @import("native_ai_openai_api_error.zig").response(scope, try scope.get(response, "status"), body, try scope.get(response, "headers")));
    const text = try scope.concat(try scope.concat(try scope.stringify(try scope.get(owner, "label")), try scope.text(" returned ")), try scope.stringify(try scope.get(response, "status")));
    const failure = try scope.own(try v.js.builtin(scope.engine, "Error", &.{text}));
    try scope.set(failure, "status", try scope.get(response, "status"));
    try scope.set(failure, "headers", try scope.get(response, "headers"));
    try scope.set(failure, "body", body);
    try rejectAttempt(scope, pending, failure);
}
fn complete(scope: *Scope, pending: c.JSValue, json: c.JSValue) !void {
    const result = try scope.object();
    try scope.put(result, "response", try scope.get(pending, "response"));
    try scope.put(result, "json", json);
    try flow.settle(scope.engine, pending, false, result);
}
fn attemptContinued(engine: *v.em.Engine, pending: c.JSValue, value: c.JSValue, rejected: bool, raw: c_int) !void {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const request_owner = try scope.get(pending, "agent");
    const is_sdk = scope.truthy(try scope.get(request_owner, "sdk"));
    const phase: Stage = @enumFromInt(raw);
    if (is_sdk and (phase == .head or phase == .fetched)) {
        const timer = try scope.get(pending, "sdkTimer");
        if (!c.JS_IsUndefined(timer)) {
            try scope.put(pending, "sdkTimer", c.pi_js_undefined());
            _ = try scope.call(try scope.global("clearTimeout"), c.pi_js_undefined(), &.{timer});
        }
    }
    if (rejected) {
        if (try @import("native_ai_classifier_values.zig").ownedAllocation(&scope, request_owner, value)) return flow.settle(engine, pending, true, value);
        const owner = try scope.get(pending, "agent");
        const sdk = scope.truthy(try scope.get(owner, "sdk"));
        const stage: Stage = @enumFromInt(raw);
        const native = !v.nullish(try scope.get(pending, "http"));
        var reason = value;
        if (native and (stage == .head or stage == .body or stage == .collected) and !try v.eq(&scope, try v.optional(&scope, value, "code"), "NativeBodyLimit")) {
            if (try v.eq(&scope, try v.optional(&scope, value, "code"), "OutOfMemory")) return rejectAttemptError(&scope, pending, error.OutOfMemory);
            const signal = try scope.get(pending, "signal");
            reason = if (scope.truthy(try v.optional(&scope, signal, "aborted"))) try scope.get(signal, "reason") else try scope.own(try v.js.builtin(engine, "TypeError", &.{try scope.text(if (stage == .head) "fetch failed" else "terminated")}));
        }
        if (sdk and (stage == .head or stage == .fetched)) {
            const aborted = scope.truthy(try v.optional(&scope, try v.optional(&scope, try scope.get(owner, "options"), "signal"), "aborted"));
            const timed_out = scope.truthy(try v.optional(&scope, try scope.get(pending, "signal"), "aborted")) or try v.eq(&scope, try v.optional(&scope, reason, "name"), "AbortError") or try v.eq(&scope, try v.optional(&scope, value, "code"), "ProviderRequestTimeout");
            reason = try @import("native_ai_openai_api_error.zig").connection(&scope, if (aborted) .aborted else if (timed_out) .timeout else .failed, reason);
        }
        if (sdk and (stage == .errorText or ((stage == .body or stage == .collected) and !scope.truthy(try scope.get(try scope.get(pending, "response"), "ok"))))) {
            const instance = c.JS_IsInstanceOf(engine.context, reason, try scope.global("Error"));
            if (instance < 0) return v.js.capture(engine);
            return httpError(&scope, pending, try scope.get(pending, "response"), if (instance == 1) try scope.get(reason, "message") else try scope.call(try scope.global("String"), c.pi_js_undefined(), &.{reason}));
        }
        return rejectAttempt(&scope, pending, reason);
    }
    attemptAdvance(&scope, pending, value, @enumFromInt(raw)) catch |err| try rejectAttemptError(&scope, pending, err);
}
fn attemptAdvance(scope: *Scope, pending: c.JSValue, value: c.JSValue, stage: Stage) !void {
    switch (stage) {
        .fetched => {
            try scope.put(pending, "response", value);
            const ok = scope.truthy(try scope.get(value, "ok"));
            if (!ok) return flow.wait(attemptContinued, scope.engine, pending, try scope.invoke(value, "text", &.{}), @intFromEnum(Stage.errorText));
            if (scope.truthy(try scope.get(try scope.get(pending, "agent"), "sdk"))) {
                if (scope.equal(try scope.get(value, "status"), c.JS_NewInt32(scope.engine.context, 204))) return complete(scope, pending, c.pi_js_null());
                const headers_value = try scope.get(value, "headers");
                const is_json = try jsonMediaType(scope, headers_value);
                if (is_json and try v.eq(scope, try scope.invoke(headers_value, "get", &.{try scope.text("content-length")}), "0")) return complete(scope, pending, c.pi_js_undefined());
                return flow.wait(attemptContinued, scope.engine, pending, try scope.invoke(value, if (is_json) "json" else "text", &.{}), @intFromEnum(if (is_json) Stage.json else Stage.text));
            }
            try flow.wait(attemptContinued, scope.engine, pending, try scope.invoke(value, "json", &.{}), @intFromEnum(Stage.json));
        },
        .head => {
            const response = try scope.object();
            const status = try scope.get(value, "status");
            var code: i32 = 0;
            if (c.JS_ToInt32(scope.engine.context, &code, status) < 0) return v.js.capture(scope.engine);
            try scope.put(response, "status", status);
            try scope.put(response, "ok", c.pi_js_bool(scope.engine.context, @intFromBool(code >= 200 and code < 300)));
            try scope.put(response, "headers", try scope.own(try @import("native_headers.zig").fromRecord(scope.engine, try scope.get(value, "rawHeaders"))));
            try scope.put(pending, "response", response);
            const http = try scope.get(pending, "http");
            if (scope.truthy(try scope.get(try scope.get(pending, "agent"), "sdk"))) {
                const collected = try scope.own(try @import("native_body_collect.zig").collect(scope.engine, try scope.get(http, "events"), .{ .mode = .text, .input = .byte_events, .signal = try scope.get(pending, "signal"), .cancel = try scope.get(http, "cancel") }));
                return flow.wait(attemptContinued, scope.engine, pending, collected, @intFromEnum(Stage.collected));
            }
            try flow.wait(attemptContinued, scope.engine, pending, try scope.invoke(try scope.get(http, "events"), "next", &.{}), @intFromEnum(Stage.body));
        },
        .body, .collected => {
            const response = try scope.get(pending, "response");
            var body = if (stage == .collected) value else if (scope.truthy(try scope.get(value, "done"))) try scope.text("") else try scope.get(try scope.get(value, "value"), "body");
            if (scope.truthy(try scope.invoke(body, "startsWith", &.{try scope.text("\u{feff}")}))) body = try scope.invoke(body, "slice", &.{c.JS_NewInt32(scope.engine.context, 1)});
            if (!scope.truthy(try scope.get(response, "ok"))) return httpError(scope, pending, response, body);
            if (scope.truthy(try scope.get(try scope.get(pending, "agent"), "sdk"))) {
                if (scope.equal(try scope.get(response, "status"), c.JS_NewInt32(scope.engine.context, 204))) return complete(scope, pending, c.pi_js_null());
                const headers_value = try scope.get(response, "headers");
                if (!try jsonMediaType(scope, headers_value)) return complete(scope, pending, body);
                if (try v.eq(scope, try scope.invoke(headers_value, "get", &.{try scope.text("content-length")}), "0")) return complete(scope, pending, c.pi_js_undefined());
            }
            var diagnostics = @import("native_ai_json_scope.zig").Guard.enter(scope.engine);
            defer diagnostics.deinit();
            try complete(scope, pending, try scope.invoke(try scope.global("JSON"), "parse", &.{body}));
        },
        .json, .text => try complete(scope, pending, value),
        .errorText => try httpError(scope, pending, try scope.get(pending, "response"), value),
        else => unreachable,
    }
}
fn jsonMediaType(scope: *Scope, headers_value: c.JSValue) !bool {
    const content_type = try scope.invoke(headers_value, "get", &.{try scope.text("content-type")});
    if (v.nullish(content_type)) return false;
    const media_type = try scope.invoke(try v.at(scope, try scope.invoke(content_type, "split", &.{try scope.text(";")}), 0), "trim", &.{});
    return scope.truthy(try scope.invoke(media_type, "includes", &.{try scope.text("application/json")})) or scope.truthy(try scope.invoke(media_type, "endsWith", &.{try scope.text("+json")}));
}
