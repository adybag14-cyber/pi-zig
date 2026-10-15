//! Pi 5ab7fe7 federation resolution and SDK 0.129.0 credential exchange/cache.
//! The Pi facade disables SDK default profile discovery. Only the explicit
//! env-derived config below enters this module; no ambient credential fallback.
//! VM callbacks and cached values remain on the owner. HTTP uses the shared
//! owned native worker; a request signal must never cancel a shared exchange.
const std = @import("std");
const builtin = @import("builtin");
const v = @import("native_ai_provider_values.zig");
const Scope = v.Scope;
const c = v.c;
const flow = @import("native_agent_async.zig");
const arithmetic = @import("native_image_arithmetic.zig");
const Stage = enum(c_int) { identity, response, text, raw, read, cancel };
const maximum_response_bytes = 1 << 20;

fn diagnosticUserAgent(scope: *Scope) !c.JSValue {
    const value = try std.fmt.allocPrint(scope.engine.gpa, "pi-zig/Zig-{s} QuickJS-{s} ({s}; {s})", .{ builtin.zig_version_string, std.mem.span(c.JS_GetVersion()), @tagName(builtin.os.tag), @tagName(builtin.cpu.arch) });
    defer scope.engine.gpa.free(value);
    return scope.text(value);
}

fn envValue(scope: *Scope, env: c.JSValue, name: []const u8) !c.JSValue {
    return scope.call(try scope.own(try @import("native_provider_env.zig").create(scope.engine)), c.pi_js_undefined(), &.{ try scope.text(name), env });
}
fn hasAuth(scope: *Scope, key: c.JSValue, headers: c.JSValue) !bool {
    if (scope.truthy(key)) return true;
    if (v.nullish(headers)) return false;
    var rows = try v.iterator(scope, try scope.invoke(try scope.global("Object"), "entries", &.{headers}));
    defer rows.deinit();
    errdefer rows.closePreserving();
    while (try rows.next()) |entry| {
        defer scope.engine.freeValue(entry);
        const name = try scope.invoke(try v.at(scope, entry, 0), "toLowerCase", &.{});
        const value = try v.at(scope, entry, 1);
        if ((try v.eq(scope, name, "authorization") or try v.eq(scope, name, "x-api-key") or try v.eq(scope, name, "cf-aig-authorization")) and !c.JS_IsNull(value) and try v.length(scope, try scope.invoke(value, "trim", &.{})) > 0) return true;
    }
    return false;
}
pub fn resolve(engine: *v.em.Engine, model: c.JSValue, key: c.JSValue, headers: c.JSValue, env: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    if (!try v.eq(&scope, try scope.get(model, "provider"), "anthropic") or try hasAuth(&scope, key, headers)) return c.pi_js_undefined();
    const rule = try envValue(&scope, env, "ANTHROPIC_FEDERATION_RULE_ID");
    const organization = try envValue(&scope, env, "ANTHROPIC_ORGANIZATION_ID");
    const path = try envValue(&scope, env, "ANTHROPIC_IDENTITY_TOKEN_FILE");
    if (!scope.truthy(rule) or !scope.truthy(organization) or !scope.truthy(path)) return c.pi_js_undefined();
    const config = try scope.object();
    try scope.put(config, "organization_id", organization);
    try scope.put(config, "workspace_id", try envValue(&scope, env, "ANTHROPIC_WORKSPACE_ID"));
    const auth = try scope.object();
    try scope.put(auth, "type", try scope.text("oidc_federation"));
    try scope.put(auth, "federation_rule_id", rule);
    try scope.put(auth, "service_account_id", try envValue(&scope, env, "ANTHROPIC_SERVICE_ACCOUNT_ID"));
    const identity = try scope.object();
    try scope.put(identity, "source", try scope.text("file"));
    try scope.put(identity, "path", path);
    try scope.put(auth, "identity_token", identity);
    try scope.put(config, "authentication", auth);
    return c.JS_DupValue(engine.context, config);
}
pub fn createSlot(engine: *v.em.Engine) !c.JSValue {
    return v.js.object(engine);
}
/// One current config+fetch client, matching the module-local upstream slot.
/// Replacing the slot does not affect pending owners retaining the old client.
pub fn client(engine: *v.em.Engine, slot: c.JSValue, model: c.JSValue, config: c.JSValue, fetch: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const key_parts = try scope.array();
    try scope.index(key_parts, 0, try scope.get(model, "baseUrl"));
    try scope.index(key_parts, 1, config);
    const key = try scope.invoke(try scope.global("JSON"), "stringify", &.{key_parts});
    const existing = try scope.get(slot, "client");
    if (!v.nullish(existing) and scope.equal(key, try scope.get(existing, "key")) and scope.equal(fetch, try scope.get(existing, "fetch"))) return c.JS_DupValue(engine.context, existing);
    const result = try scope.object();
    try scope.put(result, "key", key);
    try scope.put(result, "config", config);
    try scope.put(result, "fetch", fetch);
    const configured_base = try scope.get(config, "base_url");
    const base = if (scope.truthy(configured_base)) configured_base else try scope.get(model, "baseUrl");
    // A literal suffix regex is created below rather than interpreting URL path
    // components: SDK strips every trailing slash from the supplied base URL.
    var suffix_args = [_]c.JSValue{ try scope.text("/+$"), try scope.text("") };
    const suffix = try scope.own(try engine.checked(c.JS_CallConstructor(engine.context, engine.intrinsic_regexp_constructor, suffix_args.len, &suffix_args)));
    try scope.put(result, "baseURL", try scope.invoke(base, "replace", &.{ suffix, try scope.text("") }));
    try scope.put(result, "cached", c.pi_js_null());
    try scope.put(result, "pendingRefresh", c.pi_js_null());
    try scope.put(result, "nextForce", c.pi_js_bool(engine.context, 0));
    try scope.put(result, "lastAdvisoryError", c.JS_NewInt32(engine.context, 0));
    try scope.put(slot, "client", result);
    return c.JS_DupValue(engine.context, result);
}
fn seconds(scope: *Scope) !c.JSValue {
    return scope.invoke(try scope.global("Math"), "floor", &.{try scope.own(try arithmetic.binary(scope.engine, .divide, try scope.invoke(try scope.global("Date"), "now", &.{}), c.JS_NewInt32(scope.engine.context, 1000)))});
}
fn resolved(scope: *Scope, value: c.JSValue) !c.JSValue {
    return scope.engine.checked(c.JS_PiPromiseResolve(scope.engine.context, value));
}
pub fn invalidate(engine: *v.em.Engine, state: c.JSValue) !void {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    try scope.put(state, "cached", c.pi_js_null());
    try scope.put(state, "nextForce", c.pi_js_bool(engine.context, 1));
}
/// Returns Promise<string>. Mandatory callers share one provider operation.
/// Invalidation bypasses an older in-flight non-forced provider operation.
pub fn authorize(engine: *v.em.Engine, state: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const force = scope.truthy(try scope.get(state, "nextForce"));
    try scope.put(state, "nextForce", c.pi_js_bool(engine.context, 0));
    const cached = try scope.get(state, "cached");
    if (force or v.nullish(cached)) return refresh(&scope, state, force);
    const token = try scope.get(cached, "token");
    const expires = try scope.get(cached, "expiresAt");
    if (v.nullish(expires)) return resolved(&scope, token);
    const remaining = try scope.own(try arithmetic.binary(engine, .subtract, expires, try seconds(&scope)));
    if (try arithmetic.compare(engine, .greater, remaining, c.JS_NewInt32(engine.context, 120))) return resolved(&scope, token);
    if (try arithmetic.compare(engine, .greater, remaining, c.JS_NewInt32(engine.context, 30))) {
        const pending = try scope.get(state, "pendingRefresh");
        const elapsed = try scope.own(try arithmetic.binary(engine, .subtract, try seconds(&scope), try scope.get(state, "lastAdvisoryError")));
        if (v.nullish(pending) and try arithmetic.compare(engine, .greater_equal, elapsed, c.JS_NewInt32(engine.context, 5))) {
            const refreshed = try scope.own(try refresh(&scope, state, false));
            const observer = try flow.create(engine, state);
            defer engine.freeValue(observer.owner);
            defer engine.freeValue(observer.promise);
            // The catch belongs to a separate child promise, as in Source.
            // Mandatory callers joining pendingRefresh must still see rejection.
            try flow.wait(advisoryObserved, engine, observer.owner, refreshed, 0);
        }
        return resolved(&scope, token);
    }
    return refresh(&scope, state, false);
}
fn advisoryObserved(engine: *v.em.Engine, owner: c.JSValue, _: c.JSValue, rejected: bool, _: c_int) !void {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    if (rejected) try scope.put(try scope.get(owner, "agent"), "lastAdvisoryError", try seconds(&scope));
    return flow.settle(engine, owner, false, c.pi_js_undefined());
}
fn refresh(scope: *Scope, state: c.JSValue, force: bool) !c.JSValue {
    const existing = try scope.get(state, "pendingRefresh");
    if (!force and !v.nullish(existing)) return c.JS_DupValue(scope.engine.context, existing);
    const pending = try flow.create(scope.engine, state);
    defer scope.engine.freeValue(pending.owner);
    errdefer scope.engine.freeValue(pending.promise);
    try scope.put(state, "pendingRefresh", pending.promise);
    start(scope, pending.owner) catch |err| try rejectNative(scope, pending.owner, err);
    return pending.promise;
}
fn workload(scope: *Scope, message: c.JSValue, status: c.JSValue, body: c.JSValue, request_id: c.JSValue) !c.JSValue {
    const reason = try scope.own(try v.js.builtin(scope.engine, "Error", &.{message}));
    // AnthropicError/WorkloadIdentityError inherit Error's default name.
    try scope.put(reason, "statusCode", if (v.nullish(status)) c.pi_js_null() else status);
    try scope.put(reason, "body", if (v.nullish(body)) c.pi_js_null() else body);
    try scope.put(reason, "requestId", if (v.nullish(request_id)) c.pi_js_null() else request_id);
    return reason;
}
fn reject(scope: *Scope, owner: c.JSValue, reason: c.JSValue) !void {
    const state = try scope.get(owner, "agent");
    try scope.put(state, "pendingRefresh", c.pi_js_null());
    return flow.settle(scope.engine, owner, true, reason);
}
fn rejectNative(scope: *Scope, owner: c.JSValue, err: anyerror) !void {
    const reason = try scope.own(flow.reason(scope.engine, err));
    return reject(scope, owner, reason);
}
fn fail(scope: *Scope, owner: c.JSValue, message: c.JSValue) !void {
    return reject(scope, owner, try workload(scope, message, c.pi_js_null(), c.pi_js_null(), c.pi_js_null()));
}
fn secure(scope: *Scope, base: c.JSValue) !bool {
    const parsed = try scope.own(try v.js.builtin(scope.engine, "URL", &.{base}));
    if (try v.eq(scope, try scope.get(parsed, "protocol"), "https:")) return true;
    const host = try scope.invoke(try scope.get(parsed, "hostname"), "toLowerCase", &.{});
    return try v.eq(scope, try scope.get(parsed, "protocol"), "http:") and (try v.eq(scope, host, "localhost") or try v.eq(scope, host, "127.0.0.1") or try v.eq(scope, host, "[::1]"));
}
fn start(scope: *Scope, owner: c.JSValue) !void {
    const state = try scope.get(owner, "agent");
    const config = try scope.get(state, "config");
    const auth = try scope.get(config, "authentication");
    const base = try scope.get(state, "baseURL");
    const url_generation = scope.engine.native_allocation_generation;
    const allowed = secure(scope, base) catch |err| {
        const failure = scope.engine.nativeAllocationError(err, url_generation);
        if (failure != error.JavaScriptException) return failure;
        const reason = try scope.own(flow.reason(scope.engine, failure));
        const message = try scope.concat(try scope.concat(try scope.concat(try scope.text("Invalid token endpoint base URL \""), base), try scope.text("\": ")), try scope.stringify(reason));
        try @import("native_ai_partial_json.zig").discard(scope.engine, failure, url_generation);
        return fail(scope, owner, message);
    };
    if (!allowed) return fail(scope, owner, try scope.concat(try scope.concat(try scope.text("Refusing to send credential over non-https token endpoint \""), base), try scope.text("\"")));
    const identity = try scope.get(auth, "identity_token");
    if (!try v.eq(scope, try v.optional(scope, identity, "source"), "file")) return fail(scope, owner, try scope.text("identity_token.source is not supported by this SDK version (only \"file\")"));
    const path = try scope.get(identity, "path");
    if (!scope.truthy(path)) return fail(scope, owner, try scope.text("identity_token.source \"file\" requires a non-empty path"));
    try scope.put(owner, "identityPath", path);
    const fs = try scope.call(try scope.global("require"), c.pi_js_undefined(), &.{try scope.text("node:fs")});
    return flow.wait(continued, scope.engine, owner, try scope.invoke(try scope.get(fs, "promises"), "readFile", &.{ path, try scope.text("utf-8") }), @intFromEnum(Stage.identity));
}
fn exchange(scope: *Scope, owner: c.JSValue, contents: c.JSValue) !void {
    const state = try scope.get(owner, "agent");
    const config = try scope.get(state, "config");
    const auth = try scope.get(config, "authentication");
    const base = try scope.get(state, "baseURL");
    const path = try scope.get(owner, "identityPath");
    const jwt = try scope.invoke(contents, "trim", &.{});
    if (!scope.truthy(jwt)) return reject(scope, owner, try scope.own(try v.js.builtin(scope.engine, "Error", &.{try scope.concat(try scope.concat(try scope.text("Identity token file at "), path), try scope.text(" is empty"))})));
    const length = try v.length(scope, jwt);
    if (length > 16 * 1024) {
        const message = try std.fmt.allocPrint(scope.engine.gpa, "Identity token is {d} KiB, exceeds the 16 KiB assertion limit", .{(length + 1023) / 1024});
        defer scope.engine.gpa.free(message);
        return fail(scope, owner, try scope.text(message));
    }
    const body = try scope.object();
    try scope.put(body, "grant_type", try scope.text("urn:ietf:params:oauth:grant-type:jwt-bearer"));
    try scope.put(body, "assertion", jwt);
    try scope.put(body, "federation_rule_id", try scope.get(auth, "federation_rule_id"));
    try scope.put(body, "organization_id", try scope.get(config, "organization_id"));
    inline for (.{ "service_account_id", "workspace_id" }, 0..) |name, index| {
        const value = try scope.get(if (index == 0) auth else config, name);
        if (scope.truthy(value)) try scope.put(body, name, value);
    }
    const url = try scope.concat(base, try scope.text("/v1/oauth/token"));
    try scope.put(owner, "url", url);
    const headers = try scope.object();
    try scope.put(headers, "Content-Type", try scope.text("application/json"));
    try scope.put(headers, "anthropic-beta", try scope.text("oauth-2025-04-20,oidc-federation-2026-04-01"));
    // Runtime identity is deliberately native. Keep the raw Source SDK UA in
    // evidence and compare this diagnostic field under its explicit policy.
    const user_agent = try diagnosticUserAgent(scope);
    try scope.put(headers, "User-Agent", user_agent);
    const text = try scope.invoke(try scope.global("JSON"), "stringify", &.{body});
    const fetch = try scope.get(state, "fetch");
    if (!v.nullish(fetch)) {
        const init = try scope.object();
        try scope.put(init, "method", try scope.text("POST"));
        try scope.put(init, "headers", headers);
        try scope.put(init, "body", text);
        const fetch_generation = scope.engine.native_allocation_generation;
        const response = scope.call(fetch, c.pi_js_undefined(), &.{ url, init }) catch |err| {
            const failure = scope.engine.nativeAllocationError(err, fetch_generation);
            if (failure != error.JavaScriptException) return failure;
            const reason = try scope.own(flow.reason(scope.engine, failure));
            const message = try scope.concat(try scope.concat(try scope.text("Failed to reach token endpoint "), url), try scope.concat(try scope.text(": "), try scope.stringify(reason)));
            try @import("native_ai_partial_json.zig").discard(scope.engine, failure, fetch_generation);
            return fail(scope, owner, message);
        };
        return flow.wait(continued, scope.engine, owner, response, @intFromEnum(Stage.response));
    }
    const address = try scope.engine.toString(url);
    defer scope.engine.gpa.free(address);
    const bytes = try scope.engine.toString(text);
    defer scope.engine.gpa.free(bytes);
    const user_agent_bytes = try scope.engine.toString(user_agent);
    defer scope.engine.gpa.free(user_agent_bytes);
    const fields: []const std.http.Header = &.{
        .{ .name = "Content-Type", .value = "application/json" },
        // The SDK leaves Accept to fetch; native raw HTTP reproduces its
        // actual default wire value without changing custom-fetch init.
        .{ .name = "Accept", .value = "*/*" },
        .{ .name = "anthropic-beta", .value = "oauth-2025-04-20,oidc-federation-2026-04-01" },
        .{ .name = "User-Agent", .value = user_agent_bytes },
    };
    // .bytes keeps the SDK's 1 MiB truncation contract in the owner instead of
    // imposing the shared worker's smaller whole-body frame limit.
    const http = try scope.own(try @import("native_ai_http.zig").open(scope.engine, .{ .url = address, .payload = bytes, .headers = fields, .framing = .bytes }, c.pi_js_undefined()));
    try scope.put(owner, "http", http);
    try scope.put(owner, "iterator", try scope.get(http, "events"));
    return flow.wait(continued, scope.engine, owner, try scope.get(http, "ready"), @intFromEnum(Stage.response));
}
fn redact(scope: *Scope, body: c.JSValue) anyerror!c.JSValue {
    if (v.nullish(body)) return body;
    if (c.JS_IsString(body)) {
        const generation = scope.engine.native_allocation_generation;
        const parsed = scope.invoke(try scope.global("JSON"), "parse", &.{body}) catch |err| {
            try @import("native_ai_partial_json.zig").discard(scope.engine, err, generation);
            const length = try v.length(scope, body);
            if (length <= 2000) return body;
            const suffix = try std.fmt.allocPrint(scope.engine.gpa, "... <{d} more chars>", .{length - 2000});
            defer scope.engine.gpa.free(suffix);
            return scope.concat(try scope.invoke(body, "slice", &.{ c.JS_NewInt32(scope.engine.context, 0), c.JS_NewInt32(scope.engine.context, 2000) }), try scope.text(suffix));
        };
        return scope.invoke(try scope.global("JSON"), "stringify", &.{try redact(scope, parsed)});
    }
    if (!c.JS_IsObject(body) or try v.array(scope, body)) return c.pi_js_null();
    const out = try scope.object();
    var rows = try v.iterator(scope, try scope.invoke(try scope.global("Object"), "entries", &.{body}));
    defer rows.deinit();
    errdefer rows.closePreserving();
    while (try rows.next()) |entry| {
        defer scope.engine.freeValue(entry);
        const key = try v.at(scope, entry, 0);
        if (try v.eq(scope, key, "error") or try v.eq(scope, key, "error_description") or try v.eq(scope, key, "error_uri")) try v.js.setKey(scope.engine, out, key, try v.at(scope, entry, 1));
    }
    return out;
}
fn requestId(scope: *Scope, response: c.JSValue) !c.JSValue {
    const headers = try scope.get(response, "headers");
    const getter = try v.optional(scope, headers, "get");
    if (c.JS_IsFunction(scope.engine.context, getter)) return scope.call(getter, headers, &.{try scope.text("Request-Id")});
    const value = try v.optional(scope, headers, "request-id");
    return if (v.nullish(value)) c.pi_js_null() else value;
}
fn parse(scope: *Scope, owner: c.JSValue, text: c.JSValue) !void {
    const response = try scope.get(owner, "response");
    const status = try scope.get(response, "status");
    const id = try requestId(scope, response);
    const redacted = try redact(scope, text);
    const ok = try arithmetic.compare(scope.engine, .greater_equal, status, c.JS_NewInt32(scope.engine.context, 200)) and try arithmetic.compare(scope.engine, .less, status, c.JS_NewInt32(scope.engine.context, 300));
    if (!ok) {
        var message = try scope.concat(try scope.text("Token exchange failed with status "), try scope.stringify(status));
        if (scope.truthy(id)) message = try scope.concat(message, try scope.concat(try scope.concat(try scope.text(" (request-id "), id), try scope.text(")")));
        message = try scope.concat(message, try scope.concat(try scope.text(": "), try scope.stringify(redacted)));
        if (scope.equal(status, c.JS_NewInt32(scope.engine.context, 401))) {
            message = try scope.concat(message, try scope.text(" Ensure your federation rule matches your identity token. "));
            const config = try scope.get(try scope.get(owner, "agent"), "config");
            if (!scope.truthy(try scope.get(config, "workspace_id"))) message = try scope.concat(message, try scope.text("If your federation rule is scoped to multiple workspaces, set the ANTHROPIC_WORKSPACE_ID environment variable, the 'workspace_id' config key, or the `workspaceId` option. "));
            message = try scope.concat(message, try scope.text("View your authentication events in the Workload identity page of Claude Console for more details."));
        }
        return reject(scope, owner, try workload(scope, message, status, redacted, id));
    }
    const generation = scope.engine.native_allocation_generation;
    const data = scope.invoke(try scope.global("JSON"), "parse", &.{text}) catch |err| {
        try @import("native_ai_partial_json.zig").discard(scope.engine, err, generation);
        return reject(scope, owner, try workload(scope, try scope.concat(try scope.concat(try scope.text("Token endpoint returned non-JSON response (status "), try scope.stringify(status)), try scope.text(")")), status, redacted, id));
    };
    const access = try scope.get(data, "access_token");
    if (!scope.truthy(access)) return reject(scope, owner, try workload(scope, try scope.concat(try scope.text("Token endpoint response missing access_token: "), try scope.invoke(try scope.global("JSON"), "stringify", &.{try redact(scope, data)})), status, try redact(scope, data), id));
    const token_type = try scope.get(data, "token_type");
    if (scope.truthy(token_type) and !try v.eq(scope, try scope.invoke(token_type, "toLowerCase", &.{}), "bearer")) return reject(scope, owner, try workload(scope, try scope.concat(try scope.concat(try scope.text("Token endpoint response: unsupported token_type \""), token_type), try scope.text("\" (want Bearer)")), status, try redact(scope, data), id));
    const expires = try scope.call(try scope.global("Number"), c.pi_js_undefined(), &.{try scope.get(data, "expires_in")});
    if (!scope.truthy(try scope.invoke(try scope.global("Number"), "isFinite", &.{expires}))) return reject(scope, owner, try workload(scope, try scope.concat(try scope.text("Token endpoint response missing required fields: "), try scope.invoke(try scope.global("JSON"), "stringify", &.{try redact(scope, data)})), status, try redact(scope, data), id));
    const cached = try scope.object();
    try scope.put(cached, "token", access);
    try scope.put(cached, "expiresAt", try scope.own(try arithmetic.binary(scope.engine, .add, try seconds(scope), expires)));
    const state = try scope.get(owner, "agent");
    try scope.put(state, "cached", cached);
    try scope.put(state, "pendingRefresh", c.pi_js_null());
    return flow.settle(scope.engine, owner, false, access);
}
fn advance(scope: *Scope, owner: c.JSValue, value: c.JSValue, stage: Stage) !void {
    switch (stage) {
        .identity => return exchange(scope, owner, value),
        .response => {
            try scope.put(owner, "response", value);
            const http = try scope.get(owner, "http");
            if (!v.nullish(http)) {
                try scope.put(owner, "chunks", try scope.array());
                try scope.put(owner, "received", c.JS_NewInt32(scope.engine.context, 0));
                return flow.wait(continued, scope.engine, owner, try scope.invoke(try scope.get(owner, "iterator"), "next", &.{}), @intFromEnum(Stage.raw));
            }
            // SDK errors use response.text() without the success-path 1 MiB cap.
            if (!scope.truthy(try scope.get(value, "ok"))) return flow.wait(continued, scope.engine, owner, try scope.invoke(value, "text", &.{}), @intFromEnum(Stage.text));
            const body = try scope.get(value, "body");
            if (!scope.truthy(body)) return parse(scope, owner, try scope.text(""));
            try scope.put(owner, "reader", try scope.invoke(body, "getReader", &.{}));
            try scope.put(owner, "chunks", try scope.array());
            try scope.put(owner, "received", c.JS_NewInt32(scope.engine.context, 0));
            return flow.wait(continued, scope.engine, owner, try scope.invoke(try scope.get(owner, "reader"), "read", &.{}), @intFromEnum(Stage.read));
        },
        .text => return parse(scope, owner, value),
        .cancel => return finishBytes(scope, owner),
        .raw, .read => {
            if (scope.truthy(try scope.get(value, "done"))) return finishBytes(scope, owner);
            var bytes = try scope.get(value, "value");
            if (stage == .raw) {
                if (try v.eq(scope, try scope.get(bytes, "type"), "error_body")) return parse(scope, owner, try scope.get(bytes, "body"));
                bytes = try scope.get(bytes, "data");
            }
            var received: u32 = 0;
            if (c.JS_ToUint32(scope.engine.context, &received, try scope.get(owner, "received")) < 0) return v.js.capture(scope.engine);
            const length = try v.length(scope, bytes);
            if (length > maximum_response_bytes - received) {
                const remaining = maximum_response_bytes - received;
                if (remaining > 0) _ = try scope.invoke(try scope.get(owner, "chunks"), "push", &.{try scope.invoke(bytes, "subarray", &.{ c.JS_NewInt32(scope.engine.context, 0), c.JS_NewUint32(scope.engine.context, remaining) })});
                const reader = try scope.get(owner, if (stage == .raw) "iterator" else "reader");
                return flow.wait(continued, scope.engine, owner, try scope.invoke(reader, if (stage == .raw) "return" else "cancel", &.{}), @intFromEnum(Stage.cancel));
            }
            _ = try scope.invoke(try scope.get(owner, "chunks"), "push", &.{bytes});
            try scope.put(owner, "received", c.JS_NewUint32(scope.engine.context, received + length));
            return flow.wait(continued, scope.engine, owner, if (stage == .raw) try scope.invoke(try scope.get(owner, "iterator"), "next", &.{}) else try scope.invoke(try scope.get(owner, "reader"), "read", &.{}), @intFromEnum(stage));
        },
    }
}
fn finishBytes(scope: *Scope, owner: c.JSValue) !void {
    const chunks = try scope.get(owner, "chunks");
    const count = try v.length(scope, chunks);
    var length: u32 = 0;
    for (0..count) |index| length += try v.length(scope, try v.at(scope, chunks, @intCast(index)));
    const merged = try scope.own(try v.js.builtin(scope.engine, "Uint8Array", &.{c.JS_NewUint32(scope.engine.context, length)}));
    var offset: u32 = 0;
    for (0..count) |index| {
        const chunk = try v.at(scope, chunks, @intCast(index));
        _ = try scope.invoke(merged, "set", &.{ chunk, c.JS_NewUint32(scope.engine.context, offset) });
        offset += try v.length(scope, chunk);
    }
    const decoder = try scope.own(try v.js.builtin(scope.engine, "TextDecoder", &.{try scope.text("utf-8")}));
    return parse(scope, owner, try scope.invoke(decoder, "decode", &.{merged}));
}
fn continued(engine: *v.em.Engine, owner: c.JSValue, value: c.JSValue, rejected: bool, raw: c_int) !void {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const stage: Stage = @enumFromInt(raw);
    if (rejected) {
        if (stage == .identity) return reject(&scope, owner, try scope.own(try v.js.builtin(engine, "Error", &.{try scope.concat(try scope.concat(try scope.text("Failed to read identity token file at "), try scope.get(owner, "identityPath")), try scope.concat(try scope.text(": "), try scope.stringify(value)))})));
        if (stage == .response) return fail(&scope, owner, try scope.concat(try scope.concat(try scope.text("Failed to reach token endpoint "), try scope.get(owner, "url")), try scope.concat(try scope.text(": "), try scope.stringify(value))));
        // SDK swallows errors reading non-2xx text, then formats an empty body.
        if (stage == .text) return parse(&scope, owner, try scope.text(""));
        return reject(&scope, owner, value);
    }
    advance(&scope, owner, value, stage) catch |err| try rejectNative(&scope, owner, err);
}

fn installFixtureBridge(engine: *v.em.Engine) !void {
    try @import("node_fs.zig").install(engine, std.testing.io);
    try @import("commonjs.zig").install(engine);
    try @import("native_url.zig").install(engine);
    try @import("text_encoding.zig").install(engine);
    try @import("text_decoder.zig").install(engine);
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const slot = try scope.own(try createSlot(engine));
    const exports = try scope.object();
    inline for (.{ "make", "token", "invalidate", "resolve", "pending" }, 0..) |name, index| {
        const Adapter = struct {
            fn call(host: *v.em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
                var local: Scope = .{ .engine = host };
                defer local.deinit();
                const first = if (args.len > 0) args[0] else c.pi_js_undefined();
                switch (index) {
                    0 => {
                        const model = try local.object();
                        try local.put(model, "baseUrl", if (args.len > 2) args[2] else try local.text("http://127.0.0.1:1"));
                        return client(host, roots[0], model, first, if (args.len > 1) args[1] else c.pi_js_undefined());
                    },
                    1 => return authorize(host, first),
                    2 => {
                        try invalidate(host, first);
                        return c.pi_js_undefined();
                    },
                    3 => return resolve(host, first, if (args.len > 1) args[1] else c.pi_js_undefined(), if (args.len > 2) args[2] else c.pi_js_undefined(), if (args.len > 3) args[3] else c.pi_js_undefined()),
                    4 => return c.JS_DupValue(host.context, try local.get(first, "pendingRefresh")),
                    else => unreachable,
                }
            }
        };
        try scope.put(exports, name, try scope.own(try @import("native_node_function.zig").create(engine, name, 1, Adapter.call, &.{slot})));
    }
    try engine.registerValueModule("native:federation-fixture", exports);
}
test "Anthropic federation preserves real file rotation refresh coalescing advisory failure and redacted errors" {
    const engine = try v.em.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    try installFixtureBridge(engine);
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const length = try tmp.dir.realPath(std.testing.io, &buffer);
    const path = try std.fs.path.join(std.testing.allocator, &.{ buffer[0..length], "owned-fake-identity.jwt" });
    defer std.testing.allocator.free(path);
    var source: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer source.deinit();
    try source.writer.writeAll(@embedFile("native_ai_anthropic_federation_fixture.mjs"));
    try source.writer.writeAll("\nimport * as adapter from 'native:federation-fixture'; import fs from 'node:fs'; const path=");
    try std.json.Stringify.value(path, .{}, &source.writer);
    try source.writer.writeAll(
        \\; export const capture = await run(adapter,{path,write:value=>fs.writeFileSync(path,value)});
        \\const byCase = Object.fromEntries(capture.captures.map(row=>[row.case,row]));
        \\if(byCase['coalesced-first'].count!==1 || byCase['fresh-cache'].count!==1)throw Error('refresh did not coalesce/cache');
        \\if(byCase['mandatory-joins-advisory-error'].result.error.message!=='Failed to reach token endpoint http://127.0.0.1:1/v1/oauth/token: Error: owned endpoint offline')throw Error('mandatory caller lost advisory rejection');
        \\if(byCase['force-refresh-rereads-file'].result.token!=='owned-access-rotated')throw Error('rotation');
        \\if(byCase['advisory-backoff'].count!==4)throw Error('advisory backoff');
        \\if(byCase['workspace-change-replaces-cache'].result.error.body!=='{"error":"invalid_grant","error_description":"owned mismatch"}')throw Error('credential redaction');
        \\if(capture.exchanges.some(row=>row.hasSignal))throw Error('shared exchange acquired request signal');
        \\if(JSON.parse(capture.exchanges[0].body).assertion!=='owned.fixture.jwt.first'||JSON.parse(capture.exchanges[2].body).assertion!=='owned.fixture.jwt.rotated')throw Error('file trim/rotation');
    );
    const namespace = try engine.evalModule(source.written(), "owned-anthropic-federation-fixture.mjs");
    defer engine.freeValue(namespace);
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const capture = try scope.get(namespace, "capture");
    const exchange_rows = try scope.get(capture, "exchanges");
    const native_user_agent = try diagnosticUserAgent(&scope);
    for (0..try v.length(&scope, exchange_rows)) |index| {
        const row = try v.at(&scope, exchange_rows, @intCast(index));
        const headers = try scope.get(row, "headers");
        try std.testing.expect(scope.equal(native_user_agent, try scope.get(headers, "User-Agent")));
        try std.testing.expect(try v.eq(&scope, try scope.get(headers, "anthropic-beta"), "oauth-2025-04-20,oidc-federation-2026-04-01"));
    }
}
test "Anthropic federation resolver uses scoped environment without credential fallback behind keys headers or foreign providers" {
    const engine = try v.em.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    try installFixtureBridge(engine);
    const namespace = try engine.evalModule(
        \\import * as adapter from 'native:federation-fixture';
        \\globalThis.process={env:{},versions:{}};
        \\const model={provider:'anthropic'},env={ANTHROPIC_FEDERATION_RULE_ID:'owned-rule',ANTHROPIC_ORGANIZATION_ID:'owned-org',ANTHROPIC_IDENTITY_TOKEN_FILE:'owned-path',ANTHROPIC_WORKSPACE_ID:''};
        \\const config=adapter.resolve(model,undefined,undefined,env);
        \\if(config.organization_id!=='owned-org'||config.authentication.identity_token.path!=='owned-path'||config.workspace_id!==undefined)throw Error('scoped config');
        \\for(const headers of [{Authorization:' Bearer owned '},{'X-API-Key':'owned'},{'CF-AIG-Authorization':' owned '}])if(adapter.resolve(model,undefined,headers,env)!==undefined)throw Error('header precedence');
        \\if(adapter.resolve(model,'owned-key',undefined,env)!==undefined||adapter.resolve({provider:'other'},undefined,undefined,env)!==undefined)throw Error('key/provider precedence');
        \\if(adapter.resolve(model,undefined,undefined,{...env,ANTHROPIC_IDENTITY_TOKEN_FILE:''})!==undefined)throw Error('incomplete federation');
        \\const a=()=>{},b=()=>{};const first=adapter.make(config,a);if(adapter.make(config,a)!==first)throw Error('singleton identity');
        \\if(adapter.make(config,b)===first)throw Error('fetch identity cache key');
        \\const second=adapter.make(config,b);if(adapter.make(config,b,'http://127.0.0.1:2')===second)throw Error('base URL cache key');
    , "owned-federation-env-fixture.mjs");
    defer engine.freeValue(namespace);
}
test "Anthropic federation native owned loopback transport exchanges rotates and keeps workspace in body" {
    const gpa = std.testing.allocator;
    const fixture = @import("../ai/http_fixture.zig");
    const server = try fixture.PlanServer.init(gpa, std.testing.io, &.{
        .{ .path = "/v1/oauth/token", .body = "{\"access_token\":\"owned-native-first\",\"token_type\":\"Bearer\",\"expires_in\":180}", .payload_contains = "owned.jwt.first", .expected_request_headers = &.{.{ .name = "anthropic-beta", .value = "oauth-2025-04-20,oidc-federation-2026-04-01" }} },
        .{ .path = "/v1/oauth/token", .body = "{\"access_token\":\"owned-native-second\",\"expires_in\":180}", .payload_contains = "owned.jwt.second" },
    });
    defer server.deinit();
    const base = try server.url(gpa, "");
    defer gpa.free(base);
    const engine = try v.em.Engine.init(gpa, .{});
    defer engine.deinit();
    try installFixtureBridge(engine);
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const length = try tmp.dir.realPath(std.testing.io, &buffer);
    const path = try std.fs.path.join(gpa, &.{ buffer[0..length], "owned-loopback-identity.jwt" });
    defer gpa.free(path);
    var source: std.Io.Writer.Allocating = .init(gpa);
    defer source.deinit();
    try source.writer.writeAll("import * as adapter from 'native:federation-fixture';import fs from 'node:fs';const path=");
    try std.json.Stringify.value(path, .{}, &source.writer);
    try source.writer.writeAll(";const base=");
    try std.json.Stringify.value(base, .{}, &source.writer);
    try source.writer.writeAll(
        \\;const config={organization_id:'owned-org',workspace_id:'owned-workspace',authentication:{type:'oidc_federation',federation_rule_id:'owned-rule',identity_token:{source:'file',path}}};
        \\fs.writeFileSync(path,'  owned.jwt.first\n');const client=adapter.make(config,undefined,base);
        \\const [a,b]=await Promise.all([adapter.token(client),adapter.token(client)]);if(a!=='owned-native-first'||b!==a)throw Error('native exchange/coalescing');
        \\fs.writeFileSync(path,'owned.jwt.second');adapter.invalidate(client);if(await adapter.token(client)!=='owned-native-second')throw Error('native rotated exchange');
    );
    const namespace = try engine.evalModule(source.written(), "owned-federation-loopback-fixture.mjs");
    defer engine.freeValue(namespace);
    try server.finish();
    try std.testing.expectEqual(@as(usize, 2), server.captured.items.len);
    var captured = try std.json.parseFromSlice(std.json.Value, gpa, server.captured.items[0].payload, .{});
    defer captured.deinit();
    try std.testing.expectEqualStrings("owned-workspace", captured.value.object.get("workspace_id").?.string);
    try std.testing.expectEqualStrings("urn:ietf:params:oauth:grant-type:jwt-bearer", captured.value.object.get("grant_type").?.string);
}
