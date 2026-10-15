//! OpenAI Codex public OAuth bodies over directly retained QuickJS values.
const std = @import("std");
const v = @import("native_ai_provider_values.zig");
const Scope = v.Scope;
const c = v.c;
const flow = @import("native_agent_async.zig");
const functions = @import("native_node_function.zig");
const helpers = @import("native_ai_auth_helpers.zig");
const http = @import("native_ai_oauth_http.zig");
const device = @import("native_ai_oauth_device_code.zig");
const callback = @import("native_ai_oauth_callback_server.zig");
const protocol = @import("../auth/openai_codex_oauth.zig");
const arithmetic = @import("native_image_arithmetic.zig");
const Stage = enum(c_int) { method, pkce, listener, manual, token, token_json, token_text, device, device_json, device_text, poll, poll_json, poll_text, device_code };

pub fn create(engine: *v.em.Engine) !c.JSValue {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    const result = try s.object();
    try s.put(result, "name", try s.text("OpenAI (ChatGPT Plus/Pro)"));
    try s.put(result, "isSubscription", c.pi_js_bool(engine.context, 1));
    try s.put(result, "login", try s.own(try helpers.asyncArrow(engine, "login", 2, login, &.{})));
    // Source refresh is a regular arrow: its credential getter throws synchronously.
    try s.put(result, "refresh", try s.own(try functions.createArrow(engine, "refresh", 2, refresh, &.{})));
    try s.put(result, "toAuth", try s.own(try helpers.asyncArrow(engine, "toAuth", 1, toAuth, &.{})));
    return c.JS_DupValue(engine.context, result);
}
pub fn arg(args: []const c.JSValue, index: usize) c.JSValue {
    return if (index < args.len) args[index] else c.pi_js_undefined();
}
pub fn binary(s: *Scope, op: arithmetic.Operation, left: c.JSValue, right: c.JSValue) !c.JSValue {
    return s.own(try arithmetic.binary(s.engine, op, left, right));
}
pub fn jsonString(s: *Scope, value: c.JSValue) !c.JSValue {
    return s.invoke(try s.global("JSON"), "stringify", &.{value});
}
pub fn property(s: *Scope, value: c.JSValue, key: [*:0]const u8) !c.JSValue {
    if (v.nullish(value)) {
        _ = c.JS_ThrowTypeError(s.engine.context, "Cannot read properties of %s (reading '%s')", @as([*:0]const u8, if (c.JS_IsNull(value)) "null" else "undefined"), key);
        return v.js.capture(s.engine);
    }
    return s.get(value, key);
}
pub fn form(s: *Scope, fields: []const struct { []const u8, c.JSValue }) !c.JSValue {
    return formWithConstructor(s, try s.global("URLSearchParams"), fields);
}
pub fn formWithConstructor(s: *Scope, constructor: c.JSValue, fields: []const struct { []const u8, c.JSValue }) !c.JSValue {
    const object = try s.object();
    for (fields) |field| {
        const key = try s.text(field[0]);
        try v.js.setKey(s.engine, object, key, field[1]);
    }
    return s.own(try s.engine.checked(c.JS_CallConstructor(s.engine.context, constructor, 1, @constCast(&[_]c.JSValue{object}))));
}
pub fn failure(s: *Scope, owner: c.JSValue, message: c.JSValue) !void {
    return flow.settle(s.engine, owner, true, try s.own(try v.js.builtin(s.engine, "Error", &.{message})));
}
pub fn toAuth(engine: *v.em.Engine, _: c.JSValue, args: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    const pending = try flow.create(engine, c.pi_js_undefined());
    defer engine.freeValue(pending.owner);
    errdefer engine.freeValue(pending.promise);
    authResult(&s, pending.owner, arg(args, 0)) catch |err| try flow.rejectError(engine, pending.owner, err);
    return pending.promise;
}
fn authResult(s: *Scope, owner: c.JSValue, credential: c.JSValue) !void {
    const result = try s.object();
    try s.put(result, "apiKey", try property(s, credential, "access"));
    return flow.settle(s.engine, owner, false, result);
}
fn login(engine: *v.em.Engine, _: c.JSValue, args: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    const pending = try flow.create(engine, c.pi_js_undefined());
    defer engine.freeValue(pending.owner);
    errdefer engine.freeValue(pending.promise);
    startLogin(&s, pending.owner, arg(args, 0), arg(args, 1)) catch |err| try flow.rejectError(engine, pending.owner, err);
    return pending.promise;
}
fn startLogin(s: *Scope, owner: c.JSValue, interaction: c.JSValue, options: c.JSValue) !void {
    try s.put(owner, "interaction", interaction);
    try s.put(owner, "options", options);
    const prompt_function = try s.get(interaction, "prompt");
    const prompt = try s.object();
    try s.put(prompt, "type", try s.text("select"));
    try s.put(prompt, "message", try s.text("Select OpenAI Codex login method:"));
    const choices = try s.array();
    inline for (.{ .{ "browser", "Browser login (default)" }, .{ "device_code", "Device code login (headless)" } }, 0..) |choice, index| {
        const item = try s.object();
        try s.put(item, "id", try s.text(choice[0]));
        try s.put(item, "label", try s.text(choice[1]));
        try s.index(choices, index, item);
    }
    try s.put(prompt, "options", choices);
    return flow.wait(continued, s.engine, owner, try s.call(prompt_function, interaction, &.{prompt}), @intFromEnum(Stage.method));
}
fn refresh(engine: *v.em.Engine, _: c.JSValue, args: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    const refresh_token = try property(&s, arg(args, 0), "refresh");
    const pending = try flow.create(engine, c.pi_js_undefined());
    defer engine.freeValue(pending.owner);
    errdefer engine.freeValue(pending.promise);
    startRefresh(&s, pending.owner, refresh_token, arg(args, 1)) catch |err| try flow.rejectError(engine, pending.owner, err);
    return pending.promise;
}
fn startRefresh(s: *Scope, owner: c.JSValue, refresh_token: c.JSValue, signal: c.JSValue) !void {
    try s.put(owner, "signal", signal);
    try s.put(owner, "operation", try s.text("refresh"));
    const fetch = try http.captureFetch(s);
    const init = try tokenInit(s, signal);
    try s.put(init, "body", try form(s, &.{ .{ "grant_type", try s.text("refresh_token") }, .{ "refresh_token", refresh_token }, .{ "client_id", try s.text(protocol.CLIENT_ID) } }));
    return flow.wait(continued, s.engine, owner, try s.own(try http.requestWithFetch(s.engine, fetch, try s.text(protocol.TOKEN_URL), init)), @intFromEnum(Stage.token));
}
fn tokenInit(s: *Scope, signal: c.JSValue) !c.JSValue {
    const init = try s.object();
    try s.put(init, "method", try s.text("POST"));
    const headers = try s.object();
    try s.put(headers, "Content-Type", try s.text("application/x-www-form-urlencoded"));
    try s.put(init, "headers", headers);
    try s.put(init, "signal", signal);
    return init;
}
fn exchange(s: *Scope, owner: c.JSValue, code: c.JSValue, verifier: c.JSValue, redirect: []const u8) !void {
    try s.put(owner, "operation", try s.text("exchange"));
    const fetch = try http.captureFetch(s);
    const init = try tokenInit(s, try s.get(owner, "signal"));
    try s.put(init, "body", try form(s, &.{ .{ "grant_type", try s.text("authorization_code") }, .{ "client_id", try s.text(protocol.CLIENT_ID) }, .{ "code", code }, .{ "code_verifier", verifier }, .{ "redirect_uri", try s.text(redirect) } }));
    return flow.wait(continued, s.engine, owner, try s.own(try http.requestWithFetch(s.engine, fetch, try s.text(protocol.TOKEN_URL), init)), @intFromEnum(Stage.token));
}
fn requestDevice(s: *Scope, owner: c.JSValue, poll: bool) !void {
    const fetch = try http.captureFetch(s);
    const init = try s.object();
    try s.put(init, "method", try s.text("POST"));
    const headers = try s.object();
    try s.put(headers, "Content-Type", try s.text("application/json"));
    try s.put(init, "headers", headers);
    const body = try s.object();
    if (poll) {
        const info = try s.get(owner, "device");
        try s.put(body, "device_auth_id", try s.get(info, "device_auth_id"));
        try s.put(body, "user_code", try s.get(info, "user_code"));
    } else try s.put(body, "client_id", try s.text(protocol.CLIENT_ID));
    try s.put(init, "body", try jsonString(s, body));
    try s.put(init, "signal", try s.get(owner, "signal"));
    return flow.wait(continued, s.engine, owner, try s.own(try http.requestWithFetch(s.engine, fetch, try s.text(if (poll) protocol.DEVICE_TOKEN_URL else protocol.DEVICE_USER_CODE_URL), init)), @intFromEnum(if (poll) Stage.poll else Stage.device));
}
fn closeCallback(s: *Scope, owner: c.JSValue) !void {
    const server = try s.get(owner, "callback");
    if (!v.nullish(server)) _ = try s.invoke(server, "close", &.{});
}
fn finish(s: *Scope, owner: c.JSValue, rejected: bool, value: c.JSValue) !void {
    closeCallback(s, owner) catch |err| return flow.rejectError(s.engine, owner, err);
    return flow.settle(s.engine, owner, rejected, value);
}
fn continued(engine: *v.em.Engine, owner: c.JSValue, value: c.JSValue, rejected: bool, raw: c_int) !void {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    const stage: Stage = @enumFromInt(raw);
    if (rejected) {
        if (stage == .listener) return browserPrompt(&s, owner, c.pi_js_undefined());
        if (stage == .token_text or stage == .device_text or stage == .poll_text) return advance(&s, owner, try s.text(""), stage);
        if (stage == .token and try v.eq(&s, try s.get(owner, "operation"), "refresh")) {
            const branded = c.JS_IsInstanceOf(engine.context, value, try s.global("Error"));
            if (branded < 0) return flow.rejectError(engine, owner, v.js.capture(engine));
            const message = if (branded != 0) try s.get(value, "message") else try s.stringify(value);
            return finish(&s, owner, true, try s.own(try v.js.builtin(engine, "Error", &.{try s.concat(try s.text("OpenAI Codex token refresh error: "), message)})));
        }
        if ((stage == .token or stage == .device or stage == .poll) and s.truthy(try v.optional(&s, try s.get(owner, "signal"), "aborted"))) return finish(&s, owner, true, try s.own(try v.js.builtin(engine, "Error", &.{try s.text("Login cancelled")})));
        return finish(&s, owner, true, value);
    }
    advance(&s, owner, value, stage) catch |err| {
        const reason = try s.own(flow.reason(engine, err));
        return finish(&s, owner, true, reason);
    };
}
fn advance(s: *Scope, owner: c.JSValue, value: c.JSValue, stage: Stage) !void {
    switch (stage) {
        .method => {
            if (try v.eq(s, value, "device_code")) {
                try s.put(owner, "signal", try s.get(try s.get(owner, "interaction"), "signal"));
                return requestDevice(s, owner, false);
            }
            if (!try v.eq(s, value, "browser")) return failure(s, owner, try s.concat(try s.text("Unknown OpenAI Codex login method: "), try s.stringify(value)));
            try s.put(owner, "agentName", try v.optional(s, try s.get(owner, "options"), "agentName"));
            return flow.wait(continued, s.engine, owner, try s.own(try @import("native_ai_oauth_pkce.zig").generate(s.engine)), @intFromEnum(Stage.pkce));
        },
        .pkce => return startBrowser(s, owner, value),
        .listener => return browserPrompt(s, owner, value),
        .manual => {
            var code: c.JSValue = undefined;
            if (try v.eq(s, try s.get(value, "type"), "callback")) code = try s.get(value, "value") else {
                const input = try s.get(value, "input");
                const parsed = try parseInput(s, input);
                const state = try s.get(parsed, "state");
                if (s.truthy(state) and !s.equal(state, try s.get(owner, "state"))) return finish(s, owner, true, try s.own(try v.js.builtin(s.engine, "Error", &.{try s.text("State mismatch")})));
                code = try s.get(parsed, "code");
            }
            if (!s.truthy(code)) return finish(s, owner, true, try s.own(try v.js.builtin(s.engine, "Error", &.{try s.text("Missing authorization code")})));
            try s.put(owner, "signal", try s.get(try s.get(owner, "interaction"), "signal"));
            return exchange(s, owner, code, try s.get(owner, "verifier"), protocol.REDIRECT_URI);
        },
        .token => {
            try s.put(owner, "response", value);
            const ok = s.truthy(try s.get(value, "ok"));
            return flow.wait(continued, s.engine, owner, try s.invoke(value, if (ok) "json" else "text", &.{}), @intFromEnum(if (ok) Stage.token_json else Stage.token_text));
        },
        .token_text => {
            const response = try s.get(owner, "response");
            var message = try s.concat(try s.text("OpenAI Codex token "), try s.get(owner, "operation"));
            message = try s.concat(message, try s.text(" failed ("));
            message = try s.concat(message, try s.stringify(try s.get(response, "status")));
            message = try s.concat(message, try s.text("): "));
            message = try s.concat(message, if (s.truthy(value)) value else try s.get(response, "statusText"));
            return finish(s, owner, true, try s.own(try v.js.builtin(s.engine, "Error", &.{message})));
        },
        .token_json => return credentials(s, owner, value),
        .device => {
            try s.put(owner, "response", value);
            const ok = s.truthy(try s.get(value, "ok"));
            if (!ok and s.equal(try s.get(value, "status"), c.JS_NewInt32(s.engine.context, 404))) return failure(s, owner, try s.text("OpenAI Codex device code login is not enabled for this server. Use browser login or verify the server URL."));
            return flow.wait(continued, s.engine, owner, try s.invoke(value, if (ok) "json" else "text", &.{}), @intFromEnum(if (ok) Stage.device_json else Stage.device_text));
        },
        .device_text => return statusFailure(s, owner, "OpenAI Codex device code request failed with status ", value, false),
        .device_json => return deviceReady(s, owner, value),
        .poll => {
            try s.put(owner, "response", value);
            if (s.truthy(try s.get(value, "ok"))) return flow.wait(continued, s.engine, owner, try s.invoke(value, "json", &.{}), @intFromEnum(Stage.poll_json));
            const status = try s.get(value, "status");
            if (s.equal(status, c.JS_NewInt32(s.engine.context, 403)) or s.equal(status, c.JS_NewInt32(s.engine.context, 404))) return pollResult(s, owner, "pending", c.pi_js_undefined());
            return flow.wait(continued, s.engine, owner, try s.invoke(value, "text", &.{}), @intFromEnum(Stage.poll_text));
        },
        .poll_json => {
            if (!s.truthy(try v.optional(s, value, "authorization_code")) or !s.truthy(try s.get(value, "code_verifier"))) return pollResult(s, owner, "failed", try s.concat(try s.text("Invalid OpenAI Codex device auth token response: "), try jsonString(s, value)));
            const result = try s.object();
            try s.put(result, "authorizationCode", try s.get(value, "authorization_code"));
            try s.put(result, "codeVerifier", try s.get(value, "code_verifier"));
            return pollResult(s, owner, "complete", result);
        },
        .poll_text => {
            const generation = s.engine.native_allocation_generation;
            const parsed = s.invoke(try s.global("JSON"), "parse", &.{value}) catch |err| blk: {
                try @import("native_ai_partial_json.zig").discard(s.engine, err, generation);
                break :blk c.pi_js_null();
            };
            const err = try v.optional(s, parsed, "error");
            const code = if (c.JS_IsObject(err) or c.JS_IsNull(err)) try v.optional(s, err, "code") else err;
            if (try v.eq(s, code, "deviceauth_authorization_pending")) return pollResult(s, owner, "pending", c.pi_js_undefined());
            if (try v.eq(s, code, "slow_down")) return pollResult(s, owner, "slow_down", c.pi_js_undefined());
            return statusFailure(s, owner, "OpenAI Codex device auth failed with status ", value, true);
        },
        .device_code => {
            try s.put(owner, "signal", try s.get(try s.get(owner, "interaction"), "signal"));
            return exchange(s, owner, try s.get(value, "authorizationCode"), try s.get(value, "codeVerifier"), protocol.DEVICE_REDIRECT_URI);
        },
    }
}
fn statusFailure(s: *Scope, owner: c.JSValue, prefix: []const u8, body: c.JSValue, polling: bool) !void {
    var message = try s.concat(try s.text(prefix), try s.stringify(try s.get(try s.get(owner, "response"), "status")));
    if (s.truthy(body)) message = try s.concat(try s.concat(message, try s.text(": ")), body);
    return if (polling) pollResult(s, owner, "failed", message) else failure(s, owner, message);
}
fn pollResult(s: *Scope, owner: c.JSValue, status: []const u8, value: c.JSValue) !void {
    const result = try s.object();
    try s.put(result, "status", try s.text(status));
    if (std.mem.eql(u8, status, "complete")) try s.put(result, "value", value);
    if (std.mem.eql(u8, status, "failed")) try s.put(result, "message", value);
    return flow.settle(s.engine, owner, false, result);
}
fn deviceReady(s: *Scope, owner: c.JSValue, value: c.JSValue) !void {
    const raw_interval = try v.optional(s, value, "interval");
    const interval = if (c.JS_IsString(raw_interval)) try s.call(try s.global("Number"), c.pi_js_undefined(), &.{try s.invoke(try s.get(value, "interval"), "trim", &.{})}) else try v.optional(s, value, "interval");
    if (!s.truthy(try v.optional(s, value, "device_auth_id")) or !s.truthy(try s.get(value, "user_code")) or !c.JS_IsNumber(interval) or !s.truthy(try s.invoke(try s.global("Number"), "isFinite", &.{interval})) or try arithmetic.compare(s.engine, .less, interval, c.JS_NewInt32(s.engine.context, 0))) return failure(s, owner, try s.concat(try s.text("Invalid OpenAI Codex device code response: "), try jsonString(s, value)));
    const info = try s.object();
    try s.put(info, "device_auth_id", try s.get(value, "device_auth_id"));
    try s.put(info, "user_code", try s.get(value, "user_code"));
    try s.put(owner, "device", info);
    const interaction = try s.get(owner, "interaction");
    const notify = try s.get(interaction, "notify");
    const notification = try s.object();
    try s.put(notification, "type", try s.text("device_code"));
    try s.put(notification, "userCode", try s.get(info, "user_code"));
    try s.put(notification, "verificationUri", try s.text(protocol.DEVICE_VERIFICATION_URI));
    try s.put(notification, "intervalSeconds", interval);
    try s.put(notification, "expiresInSeconds", c.JS_NewInt32(s.engine.context, 900));
    _ = try s.call(notify, interaction, &.{notification});
    try s.put(owner, "signal", try s.get(interaction, "signal"));
    const options = try s.object();
    try s.put(options, "intervalSeconds", interval);
    try s.put(options, "expiresInSeconds", c.JS_NewInt32(s.engine.context, 900));
    try s.put(options, "signal", try s.get(owner, "signal"));
    const Adapter = struct {
        fn call(engine: *v.em.Engine, _: c.JSValue, _: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
            var local: Scope = .{ .engine = engine };
            defer local.deinit();
            const pending = try flow.create(engine, c.pi_js_undefined());
            defer engine.freeValue(pending.owner);
            errdefer engine.freeValue(pending.promise);
            try local.put(pending.owner, "device", try local.get(roots[0], "device"));
            try local.put(pending.owner, "signal", try local.get(roots[0], "signal"));
            requestDevice(&local, pending.owner, true) catch |err| try flow.rejectError(engine, pending.owner, err);
            return pending.promise;
        }
    };
    try s.put(options, "poll", try s.own(try helpers.asyncArrow(s.engine, "poll", 0, Adapter.call, &.{owner})));
    return flow.wait(continued, s.engine, owner, try s.own(try device.poll(s.engine, options)), @intFromEnum(Stage.device_code));
}
fn credentials(s: *Scope, owner: c.JSValue, json: c.JSValue) !void {
    if (!s.truthy(try v.optional(s, json, "access_token")) or !s.truthy(try s.get(json, "refresh_token")) or !c.JS_IsNumber(try s.get(json, "expires_in"))) {
        const prefix = try s.concat(try s.concat(try s.text("OpenAI Codex token "), try s.get(owner, "operation")), try s.text(" response missing fields: "));
        return finish(s, owner, true, try s.own(try v.js.builtin(s.engine, "Error", &.{try s.concat(prefix, try jsonString(s, json))})));
    }
    const token = try s.object();
    try s.put(token, "access", try s.get(json, "access_token"));
    try s.put(token, "refresh", try s.get(json, "refresh_token"));
    const date = try s.invoke(try s.global("Date"), "now", &.{});
    try s.put(token, "expires", try binary(s, .add, date, try binary(s, .multiply, try s.get(json, "expires_in"), c.JS_NewInt32(s.engine.context, 1000))));
    const account_id = try accountId(s, try s.get(token, "access"));
    if (v.nullish(account_id)) return finish(s, owner, true, try s.own(try v.js.builtin(s.engine, "Error", &.{try s.text("Failed to extract accountId from token")})));
    const credential = try s.object();
    try s.put(credential, "type", try s.text("oauth"));
    inline for (.{ "access", "refresh", "expires" }) |key| try s.put(credential, key, try s.get(token, key));
    try s.put(credential, "accountId", account_id);
    return finish(s, owner, false, credential);
}
fn accountId(s: *Scope, token: c.JSValue) !c.JSValue {
    const generation = s.engine.native_allocation_generation;
    return decodeAccount(s, token) catch |err| {
        try @import("native_ai_partial_json.zig").discard(s.engine, err, generation);
        return c.pi_js_null();
    };
}
fn decodeAccount(s: *Scope, token: c.JSValue) !c.JSValue {
    const parts = try s.invoke(token, "split", &.{try s.text(".")});
    if (try v.length(s, parts) != 3) return c.pi_js_null();
    const payload = try s.call(try s.global("atob"), c.pi_js_undefined(), &.{try v.at(s, parts, 1)});
    const decoded = try s.invoke(try s.global("JSON"), "parse", &.{payload});
    const auth = try v.optional(s, decoded, protocol.JWT_CLAIM_PATH);
    const id = try v.optional(s, auth, "chatgpt_account_id");
    return if (c.JS_IsString(id) and try v.length(s, id) > 0) id else c.pi_js_null();
}
fn startBrowser(s: *Scope, owner: c.JSValue, pair: c.JSValue) !void {
    try s.put(owner, "verifier", try s.get(pair, "verifier"));
    const state_bytes = try @import("../auth/pkce.zig").generateHexState(s.engine.gpa, s.engine.native_io orelse return error.NativeOAuthIoRequired);
    defer s.engine.gpa.free(state_bytes);
    const state = try s.text(state_bytes);
    try s.put(owner, "state", state);
    const agent_name = try s.get(owner, "agentName");
    const url = try s.own(try v.js.builtin(s.engine, "URL", &.{try s.text(protocol.AUTHORIZE_URL)}));
    const params = try s.get(url, "searchParams");
    const fields = .{ .{ "response_type", "code" }, .{ "client_id", protocol.CLIENT_ID }, .{ "redirect_uri", protocol.REDIRECT_URI }, .{ "scope", protocol.SCOPE } };
    inline for (fields) |field| _ = try s.invoke(params, "set", &.{ try s.text(field[0]), try s.text(field[1]) });
    _ = try s.invoke(params, "set", &.{ try s.text("code_challenge"), try s.get(pair, "challenge") });
    _ = try s.invoke(params, "set", &.{ try s.text("code_challenge_method"), try s.text("S256") });
    _ = try s.invoke(params, "set", &.{ try s.text("state"), state });
    _ = try s.invoke(params, "set", &.{ try s.text("id_token_add_organizations"), try s.text("true") });
    _ = try s.invoke(params, "set", &.{ try s.text("codex_cli_simplified_flow"), try s.text("true") });
    _ = try s.invoke(params, "set", &.{ try s.text("originator"), if (c.JS_IsUndefined(agent_name)) try s.text("pi") else agent_name });
    try s.put(owner, "url", try s.invoke(url, "toString", &.{}));
    const options = try s.object();
    try s.put(options, "providerName", try s.text("OpenAI"));
    const process = try s.global("process");
    const env = try v.optional(s, process, "env");
    const host = try v.optional(s, env, "PI_OAUTH_CALLBACK_HOST");
    try s.put(options, "host", if (s.truthy(host)) host else try s.text("127.0.0.1"));
    try s.put(options, "port", c.JS_NewInt32(s.engine.context, 1455));
    try s.put(options, "path", try s.text(protocol.CALLBACK_PATH));
    try s.put(options, "state", state);
    const Adapter = struct {
        fn call(engine: *v.em.Engine, _: c.JSValue, args: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
            const pending = try flow.create(engine, c.pi_js_undefined());
            defer engine.freeValue(pending.owner);
            errdefer engine.freeValue(pending.promise);
            try flow.settle(engine, pending.owner, false, arg(args, 0));
            return pending.promise;
        }
    };
    try s.put(options, "complete", try s.own(try helpers.asyncArrow(s.engine, "complete", 1, Adapter.call, &.{})));
    const signal = try s.get(try s.get(owner, "interaction"), "signal");
    try s.put(owner, "signal", signal);
    try s.put(options, "signal", signal);
    return flow.wait(continued, s.engine, owner, try s.own(try callback.start(s.engine, options)), @intFromEnum(Stage.listener));
}
fn browserPrompt(s: *Scope, owner: c.JSValue, server: c.JSValue) !void {
    try s.put(owner, "callback", server);
    const interaction = try s.get(owner, "interaction");
    const notify = try s.get(interaction, "notify");
    const notification = try s.object();
    try s.put(notification, "type", try s.text("auth_url"));
    try s.put(notification, "url", try s.get(owner, "url"));
    try s.put(notification, "instructions", try s.text("A browser window should open. Complete login to finish."));
    _ = try s.call(notify, interaction, &.{notification});
    const prompt = try s.object();
    try s.put(prompt, "message", try s.text("Complete login in your browser, or paste the authorization code / redirect URL here:"));
    try s.put(prompt, "placeholder", try s.text(protocol.REDIRECT_URI));
    return flow.wait(continued, s.engine, owner, try s.own(try callback.waitForCallbackOrManualInput(s.engine, try s.get(owner, "interaction"), server, prompt)), @intFromEnum(Stage.manual));
}
fn parseInput(s: *Scope, input: c.JSValue) !c.JSValue {
    const value = try s.invoke(input, "trim", &.{});
    const result = try s.object();
    if (!s.truthy(value)) return result;
    const generation = s.engine.native_allocation_generation;
    const raw_url = v.js.builtin(s.engine, "URL", &.{value}) catch |err| blk: {
        try @import("native_ai_partial_json.zig").discard(s.engine, err, generation);
        break :blk c.pi_js_undefined();
    };
    const url = try s.own(raw_url);
    var params: c.JSValue = undefined;
    if (!v.nullish(url)) params = try s.get(url, "searchParams") else {
        if (s.truthy(try s.invoke(value, "includes", &.{try s.text("#")}))) {
            const split = try s.invoke(value, "split", &.{ try s.text("#"), c.JS_NewInt32(s.engine.context, 2) });
            try s.put(result, "code", try v.at(s, split, 0));
            try s.put(result, "state", try v.at(s, split, 1));
            return result;
        }
        if (!s.truthy(try s.invoke(value, "includes", &.{try s.text("code=")}))) {
            try s.put(result, "code", value);
            return result;
        }
        params = try s.own(try v.js.builtin(s.engine, "URLSearchParams", &.{value}));
    }
    inline for (.{ "code", "state" }) |key| {
        const found = try s.invoke(params, "get", &.{try s.text(key)});
        try s.put(result, key, if (v.nullish(found)) c.pi_js_undefined() else found);
    }
    return result;
}
