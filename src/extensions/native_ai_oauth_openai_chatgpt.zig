//! Actual ae7 ChatGPT dynamic-client OAuth body, evaluated through native Zig/C.
//! Credentials and interactions remain live VM values; no callback JSON bridge.
const std = @import("std");
const v = @import("native_ai_provider_values.zig");
const Scope = v.Scope;
const c = v.c;
const flow = @import("native_agent_async.zig");
const helpers = @import("native_ai_auth_helpers.zig");
const http = @import("native_ai_oauth_http.zig");
const callback = @import("native_ai_oauth_chatgpt_callback.zig");
const pkce = @import("../auth/pkce.zig");
const arithmetic = @import("native_image_arithmetic.zig");
const resource = "https://api.openai.com/v1";
const direct_scope = "chatgpt.tokens.use.direct";
const Stage = enum(c_int) { pkce_ready, callback_ready, raced, fetched, error_text, json };
pub const TestOptions = struct { token_origin: ?[]const u8 = null, callback_port: u16 = 0 };
pub fn create(engine: *v.em.Engine) !c.JSValue {
    return createInternal(engine, null);
}
pub fn createForTest(engine: *v.em.Engine, options: TestOptions) !c.JSValue {
    if (!@import("builtin").is_test) return error.TestOnlyOAuthConfiguration;
    return createInternal(engine, options);
}
fn createInternal(engine: *v.em.Engine, options: ?TestOptions) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const config = try scope.object();
    try scope.put(config, "port", c.JS_NewInt32(engine.context, if (options) |test_options| test_options.callback_port else 1455));
    const token_url = if (options) |test_options| if (test_options.token_origin) |origin| try scope.concat(try scope.text(origin), try scope.text("/api/accounts/oauth/token")) else try scope.text("https://auth.openai.com/api/accounts/oauth/token") else try scope.text("https://auth.openai.com/api/accounts/oauth/token");
    try scope.put(config, "tokenUrl", token_url);
    // The callback host is a module-load setting in Source; the redirect stays fixed.
    const process = try scope.global("process");
    const env = try v.optional(&scope, process, "env");
    const host = try v.optional(&scope, env, "PI_OAUTH_CALLBACK_HOST");
    try scope.put(config, "host", if (scope.truthy(host)) host else try scope.text("127.0.0.1"));
    const object = try scope.object();
    try scope.put(object, "name", try scope.text("OpenAI (ChatGPT subscription)"));
    try scope.put(object, "isSubscription", c.pi_js_bool(engine.context, 1));
    try scope.put(object, "loginLabel", try scope.text("Sign in with ChatGPT"));
    try scope.put(object, "login", try scope.own(try helpers.asyncArrow(engine, "loginOpenAIChatGPT", 2, login, &.{config})));
    try scope.put(object, "refresh", try scope.own(try helpers.asyncArrow(engine, "refreshAccessToken", 2, refresh, &.{config})));
    try scope.put(object, "toAuth", try scope.own(try helpers.asyncArrow(engine, "toAuth", 1, toAuth, &.{})));
    return c.JS_DupValue(engine.context, object);
}
fn arg(args: []const c.JSValue, index: usize) c.JSValue {
    return if (index < args.len) args[index] else c.pi_js_undefined();
}
fn fail(scope: *Scope, message: []const u8) anyerror {
    return v.errorText(scope, scope.text(message) catch |err| return err);
}
fn credentialField(scope: *Scope, credential_value: c.JSValue, field: [*:0]const u8) !c.JSValue {
    if (v.nullish(credential_value)) {
        const message = try std.fmt.allocPrint(scope.engine.gpa, "Cannot read properties of {s} (reading '{s}')", .{ if (c.JS_IsNull(credential_value)) "null" else "undefined", field });
        defer scope.engine.gpa.free(message);
        const reason = try scope.own(try v.js.builtin(scope.engine, "TypeError", &.{try scope.text(message)}));
        _ = scope.engine.checked(c.JS_Throw(scope.engine.context, c.JS_DupValue(scope.engine.context, reason))) catch |err| return err;
        unreachable;
    }
    return scope.get(credential_value, field);
}
fn rejected(engine: *v.em.Engine, pending: flow.Pending, err: anyerror) !c.JSValue {
    defer engine.freeValue(pending.owner);
    errdefer engine.freeValue(pending.promise);
    try flow.rejectError(engine, pending.owner, err);
    return pending.promise;
}
fn toAuth(engine: *v.em.Engine, _: c.JSValue, args: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
    const pending = try flow.create(engine, c.pi_js_undefined());
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const value = credentialField(&scope, arg(args, 0), "access") catch |err| return rejected(engine, pending, err);
    const output = scope.object() catch |err| return rejected(engine, pending, err);
    scope.put(output, "apiKey", value) catch |err| return rejected(engine, pending, err);
    defer engine.freeValue(pending.owner);
    errdefer engine.freeValue(pending.promise);
    try flow.settle(engine, pending.owner, false, output);
    return pending.promise;
}
fn refresh(engine: *v.em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    const pending = try flow.create(engine, c.pi_js_undefined());
    initializeRefresh(engine, pending.owner, args, roots[0]) catch |err| return rejected(engine, pending, err);
    engine.freeValue(pending.owner);
    return pending.promise;
}
fn initializeRefresh(engine: *v.em.Engine, owner: c.JSValue, args: []const c.JSValue, config: c.JSValue) !void {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const credential = arg(args, 0);
    const client_id = try credentialField(&scope, credential, "clientId");
    if (!try nonempty(&scope, client_id)) return fail(&scope, "Stored OpenAI OAuth credential does not contain an issued client ID; reconnect ChatGPT");
    try scope.put(owner, "clientId", client_id);
    try scope.put(owner, "config", config);
    try scope.put(owner, "login", c.pi_js_bool(engine.context, 0));
    const params_constructor = try scope.global("URLSearchParams");
    const fields = try scope.object();
    try scope.put(fields, "grant_type", try scope.text("refresh_token"));
    try scope.put(fields, "client_id", client_id);
    try scope.put(fields, "refresh_token", try scope.get(credential, "refresh"));
    try scope.put(fields, "resource", try scope.text(resource));
    const body = try scope.own(try engine.checked(c.JS_CallConstructor(engine.context, params_constructor, 1, @constCast(&[_]c.JSValue{fields}))));
    try request(&scope, owner, body, arg(args, 1));
}
fn nonempty(scope: *Scope, value: c.JSValue) !bool {
    return c.JS_IsString(value) and scope.truthy(try scope.get(try scope.invoke(value, "trim", &.{}), "length"));
}
fn construct(scope: *Scope, name: [*:0]const u8, args: []const c.JSValue) !c.JSValue {
    return scope.own(try scope.engine.checked(c.JS_CallConstructor(scope.engine.context, try scope.global(name), @intCast(args.len), @constCast(args.ptr))));
}
fn request(scope: *Scope, owner: c.JSValue, body: c.JSValue, signal: c.JSValue) !void {
    const fetch = try http.captureFetch(scope);
    const init = try scope.object();
    try scope.put(init, "method", try scope.text("POST"));
    const headers = try scope.object();
    try scope.put(headers, "accept", try scope.text("application/json"));
    try scope.put(headers, "content-type", try scope.text("application/x-www-form-urlencoded"));
    try scope.put(init, "headers", headers);
    try scope.put(init, "body", body);
    try scope.put(init, "signal", signal);
    const pending = try scope.own(try http.requestWithFetch(scope.engine, fetch, try scope.get(try scope.get(owner, "config"), "tokenUrl"), init));
    try flow.wait(continued, scope.engine, owner, pending, @intFromEnum(Stage.fetched));
}
fn login(engine: *v.em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    const pending = try flow.create(engine, c.pi_js_undefined());
    initializeLogin(engine, pending.owner, args, roots[0]) catch |err| return rejected(engine, pending, err);
    engine.freeValue(pending.owner);
    return pending.promise;
}
fn validUuid(value: []const u8) bool {
    if (value.len != 36) return false;
    for (value, 0..) |byte, index| {
        if (index == 8 or index == 13 or index == 18 or index == 23) {
            if (byte != '-') return false;
        } else if (!std.ascii.isHex(byte)) return false;
    }
    return true;
}
fn randomValue(engine: *v.em.Engine) ![]u8 {
    var bytes: [32]u8 = undefined;
    try (engine.native_io orelse return error.NativeHttpIoRequired).randomSecure(&bytes);
    return pkce.base64UrlNoPadAlloc(engine.gpa, &bytes);
}
fn initializeLogin(engine: *v.em.Engine, owner: c.JSValue, args: []const c.JSValue, config: c.JSValue) !void {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const options = arg(args, 1);
    const getter = try v.optional(&scope, options, "getDeviceId");
    const device_id = if (v.nullish(getter)) c.pi_js_undefined() else try scope.call(getter, options, &.{});
    if (!scope.truthy(device_id)) return fail(&scope, "Sign in with ChatGPT requires a device ID (UUID) for this installation");
    const device_text = try engine.toString(device_id);
    defer engine.gpa.free(device_text);
    if (!validUuid(device_text)) return fail(&scope, "Sign in with ChatGPT requires a device ID (UUID) for this installation");
    try scope.put(owner, "hostId", try scope.concat(try scope.text("urn:uuid:"), try scope.invoke(device_id, "toLowerCase", &.{})));
    try scope.put(owner, "interaction", arg(args, 0));
    try scope.put(owner, "options", options);
    try scope.put(owner, "config", config);
    try scope.put(owner, "login", c.pi_js_bool(engine.context, 1));
    var pair = try pkce.generate(engine.gpa, engine.native_io orelse return error.NativeHttpIoRequired);
    defer pair.deinit(engine.gpa);
    try scope.put(owner, "verifier", try scope.text(pair.verifier));
    try scope.put(owner, "challenge", try scope.text(pair.challenge));
    // generatePKCE is awaited in Source, even though its entropy work is synchronous.
    try flow.wait(continued, engine, owner, c.pi_js_undefined(), @intFromEnum(Stage.pkce_ready));
}
fn afterPkce(scope: *Scope, owner: c.JSValue) !void {
    const engine = scope.engine;
    const state = try randomValue(engine);
    defer engine.gpa.free(state);
    const nonce = try randomValue(engine);
    defer engine.gpa.free(nonce);
    try scope.put(owner, "state", try scope.text(state));
    const config = try scope.get(owner, "config");
    const host = try engine.toString(try scope.get(config, "host"));
    defer engine.gpa.free(host);
    var port: u32 = 0;
    if (c.JS_ToUint32(engine.context, &port, try scope.get(config, "port")) < 0) return v.js.capture(engine);
    const server = callback.open(engine, state, host, @intCast(port)) catch |err| {
        if (err == error.AddressInUse) return fail(scope, "Port 1455 is in use, probably by an unfinished login in another pi session or by the Codex CLI. Cancel that login and try again.");
        return err;
    };
    _ = try scope.own(server);
    try scope.put(owner, "callback", server);
    try scope.put(owner, "nonce", try scope.text(nonce));
    try flow.wait(continued, engine, owner, c.pi_js_undefined(), @intFromEnum(Stage.callback_ready));
}
fn afterCallback(scope: *Scope, owner: c.JSValue) !void {
    const engine = scope.engine;
    const server = try scope.get(owner, "callback");
    const options = try scope.get(owner, "options");
    const authorization_url = try construct(scope, "URL", &.{try scope.text("https://auth.openai.com/api/accounts/authorize")});
    const params_constructor = try scope.global("URLSearchParams");
    const fields = try scope.object();
    try scope.put(fields, "client_id", try scope.text("dynamic_agent_client"));
    const agent_name = try v.optional(scope, options, "agentName");
    try scope.put(fields, "agent_name_hint", if (v.nullish(agent_name)) try scope.text("Pi") else agent_name);
    try scope.put(fields, "ext_agent_host_id", try scope.get(owner, "hostId"));
    try scope.put(fields, "response_type", try scope.text("code"));
    try scope.put(fields, "redirect_uri", try scope.text(callback.redirect_uri));
    try scope.put(fields, "resource", try scope.text(resource));
    try scope.put(fields, "scope", try scope.text("openid profile email offline_access resource.invoke chatgpt.tokens.use.direct"));
    try scope.put(fields, "state", try scope.get(owner, "state"));
    try scope.put(fields, "code_challenge", try scope.get(owner, "challenge"));
    try scope.put(fields, "code_challenge_method", try scope.text("S256"));
    try scope.put(fields, "nonce", try scope.get(owner, "nonce"));
    const search = try scope.own(try engine.checked(c.JS_CallConstructor(engine.context, params_constructor, 1, @constCast(&[_]c.JSValue{fields}))));
    try scope.set(authorization_url, "search", try scope.invoke(search, "toString", &.{}));
    const interaction = try scope.get(owner, "interaction");
    const notify = try scope.get(interaction, "notify");
    const notice = try scope.object();
    try scope.put(notice, "type", try scope.text("auth_url"));
    try scope.put(notice, "url", try scope.invoke(authorization_url, "toString", &.{}));
    try scope.put(notice, "instructions", try scope.text("Complete sign-in in your browser. If the callback does not complete, paste the final redirect URL here."));
    _ = try scope.call(notify, interaction, &.{notice});
    const manual_abort = try construct(scope, "AbortController", &.{});
    try scope.put(owner, "manualAbort", manual_abort);
    const prompt_function = try scope.get(interaction, "prompt");
    const prompt = try scope.object();
    try scope.put(prompt, "type", try scope.text("manual_code"));
    try scope.put(prompt, "message", try scope.text("Complete login in your browser, or paste the final redirect URL here:"));
    try scope.put(prompt, "placeholder", try scope.text(callback.redirect_uri));
    const signals = try scope.array();
    try scope.index(signals, 0, try scope.get(manual_abort, "signal"));
    try scope.index(signals, 1, try scope.get(interaction, "signal"));
    try scope.put(prompt, "signal", try scope.invoke(try scope.global("AbortSignal"), "any", &.{signals}));
    const answer = try scope.call(prompt_function, interaction, &.{prompt});
    const parse_answer = try scope.own(try @import("native_node_function.zig").createArrow(engine, "", 1, parseManual, &.{owner}));
    const manual_code = try scope.invoke(answer, "then", &.{parse_answer});
    const racers = try scope.array();
    try scope.index(racers, 0, try scope.get(server, "result"));
    try scope.index(racers, 1, manual_code);
    try scope.put(owner, "inTry", c.pi_js_bool(engine.context, 1));
    try flow.wait(continued, engine, owner, try scope.invoke(try scope.global("Promise"), "race", &.{racers}), @intFromEnum(Stage.raced));
}
fn parseManual(engine: *v.em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    return c.JS_DupValue(engine.context, try manualResult(&scope, arg(args, 0), try scope.get(roots[0], "state")));
}
fn manualResult(scope: *Scope, input: c.JSValue, state: c.JSValue) !c.JSValue {
    const url = construct(scope, "URL", &.{try scope.invoke(input, "trim", &.{})}) catch {
        return fail(scope, "Paste the full callback URL from the browser");
    };
    const expected = try construct(scope, "URL", &.{try scope.text(callback.redirect_uri)});
    if (!scope.equal(try scope.get(url, "origin"), try scope.get(expected, "origin")) or !scope.equal(try scope.get(url, "pathname"), try scope.get(expected, "pathname"))) return fail(scope, "The pasted callback URL must start with http://127.0.0.1:1455/auth/callback");
    const params_value = try scope.get(url, "searchParams");
    const oauth_error = try scope.invoke(params_value, "get", &.{try scope.text("error")});
    if (scope.truthy(oauth_error)) return v.errorText(scope, try scope.concat(try scope.text("ChatGPT authorization failed: "), oauth_error));
    const code = try scope.invoke(params_value, "get", &.{try scope.text("code")});
    if (!scope.truthy(code)) return fail(scope, "Missing authorization code");
    const actual_state = try scope.invoke(params_value, "get", &.{try scope.text("state")});
    if (!scope.truthy(actual_state)) return fail(scope, "Missing OAuth state");
    if (!scope.equal(actual_state, state)) return fail(scope, "OAuth state mismatch");
    const client_id = try scope.invoke(params_value, "get", &.{try scope.text("client_id")});
    const trimmed_id = if (v.nullish(client_id)) c.pi_js_undefined() else try scope.invoke(client_id, "trim", &.{});
    if (!scope.truthy(trimmed_id)) return fail(scope, "OpenAI OAuth registration callback did not contain an issued client ID");
    const result = try scope.object();
    try scope.put(result, "code", code);
    try scope.put(result, "clientId", trimmed_id);
    return result;
}
fn cleanup(scope: *Scope, owner: c.JSValue) !void {
    const controller = try scope.get(owner, "manualAbort");
    if (!v.nullish(controller)) _ = try scope.invoke(controller, "abort", &.{});
    const server = try scope.get(owner, "callback");
    if (!v.nullish(server)) {
        _ = try scope.invoke(server, "close", &.{});
        try scope.put(owner, "callback", c.pi_js_undefined());
    }
}
fn finishFailure(scope: *Scope, owner: c.JSValue, reason: c.JSValue) !void {
    var final_reason = reason;
    if (scope.truthy(try scope.get(owner, "login"))) {
        if (scope.truthy(try scope.get(owner, "inTry"))) {
            const interaction = try scope.get(owner, "interaction");
            if (scope.truthy(try scope.get(try scope.get(interaction, "signal"), "aborted"))) final_reason = try scope.own(try v.js.builtin(scope.engine, "Error", &.{try scope.text("Login cancelled")}));
        }
        try cleanup(scope, owner);
    }
    try flow.settle(scope.engine, owner, true, final_reason);
}
fn continued(engine: *v.em.Engine, owner: c.JSValue, value: c.JSValue, failed: bool, stage_raw: c_int) !void {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const stage: Stage = @enumFromInt(stage_raw);
    if (failed) return finishFailure(&scope, owner, value);
    advance(&scope, owner, value, stage) catch |err| {
        const reason = try scope.own(flow.reason(engine, err));
        try finishFailure(&scope, owner, reason);
    };
}
fn emptyText(engine: *v.em.Engine, _: c.JSValue, _: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
    return @import("native_sdk.zig").text(engine, "");
}
fn advance(scope: *Scope, owner: c.JSValue, value: c.JSValue, stage: Stage) !void {
    const engine = scope.engine;
    switch (stage) {
        .pkce_ready => try afterPkce(scope, owner),
        .callback_ready => try afterCallback(scope, owner),
        .raced => {
            const interaction = try scope.get(owner, "interaction");
            const progress = try scope.object();
            try scope.put(progress, "type", try scope.text("progress"));
            try scope.put(progress, "message", try scope.text("Exchanging authorization code for tokens..."));
            _ = try scope.invoke(interaction, "notify", &.{progress});
            const params_constructor = try scope.global("URLSearchParams");
            const fields = try scope.object();
            try scope.put(fields, "grant_type", try scope.text("authorization_code"));
            const client_id = try scope.get(value, "clientId");
            try scope.put(owner, "clientId", client_id);
            try scope.put(fields, "client_id", client_id);
            try scope.put(fields, "code", try scope.get(value, "code"));
            try scope.put(fields, "code_verifier", try scope.get(owner, "verifier"));
            try scope.put(fields, "redirect_uri", try scope.text(callback.redirect_uri));
            try scope.put(fields, "resource", try scope.text(resource));
            const body = try scope.own(try engine.checked(c.JS_CallConstructor(engine.context, params_constructor, 1, @constCast(&[_]c.JSValue{fields}))));
            try request(scope, owner, body, try scope.get(interaction, "signal"));
        },
        .fetched => {
            try scope.put(owner, "response", value);
            if (!scope.truthy(try scope.get(value, "ok"))) {
                const text = try scope.invoke(value, "text", &.{});
                const ignore_error = try scope.own(try @import("native_node_function.zig").createArrow(engine, "", 0, emptyText, &.{}));
                const caught = try scope.invoke(text, "catch", &.{ignore_error});
                try flow.wait(continued, engine, owner, caught, @intFromEnum(Stage.error_text));
            } else try flow.wait(continued, engine, owner, try scope.invoke(value, "json", &.{}), @intFromEnum(Stage.json));
        },
        .error_text => {
            const response = try scope.get(owner, "response");
            var message = try scope.concat(try scope.text("OpenAI OAuth token request failed ("), try scope.get(response, "status"));
            message = try scope.concat(message, try scope.text("): "));
            message = try scope.concat(message, if (scope.truthy(value)) value else try scope.get(response, "statusText"));
            return v.errorText(scope, message);
        },
        .json => {
            if (!c.JS_IsObject(value) or c.JS_IsNull(value) or try v.array(scope, value) or c.JS_IsFunction(engine.context, value)) return fail(scope, "OpenAI OAuth token response must be an object");
            if (scope.truthy(try scope.get(owner, "login"))) {
                if (!c.JS_IsString(try scope.get(value, "id_token")) or !scope.truthy(try scope.get(try scope.invoke(try scope.get(value, "id_token"), "trim", &.{}), "length"))) return fail(scope, "OpenAI OAuth token response did not contain an ID token");
            }
            const output = try credential(scope, value, try scope.get(owner, "clientId"));
            if (scope.truthy(try scope.get(owner, "login"))) try cleanup(scope, owner);
            try flow.settle(engine, owner, false, output);
        },
    }
}
fn requireString(scope: *Scope, token: c.JSValue, field: [*:0]const u8) !c.JSValue {
    const value = try scope.get(token, field);
    if (!try nonempty(scope, value)) return v.errorText(scope, try scope.concat(try scope.text("OpenAI OAuth token response has invalid "), try scope.text(std.mem.span(field))));
    return value;
}
fn credential(scope: *Scope, token: c.JSValue, client_id: c.JSValue) !c.JSValue {
    const engine = scope.engine;
    const access = try requireString(scope, token, "access_token");
    const refresh_token = try requireString(scope, token, "refresh_token");
    const scope_string = try requireString(scope, token, "scope");
    const expires_type = try scope.get(token, "expires_in");
    if (!c.JS_IsNumber(expires_type)) return fail(scope, "OpenAI OAuth token response has invalid expires_in");
    const number = try scope.global("Number");
    const finite = try scope.get(number, "isFinite");
    if (!scope.truthy(try scope.call(finite, number, &.{try scope.get(token, "expires_in")})) or try arithmetic.compare(engine, .less_equal, try scope.get(token, "expires_in"), c.JS_NewInt32(engine.context, 0))) return fail(scope, "OpenAI OAuth token response has invalid expires_in");
    const regex = try scope.own(try v.js.builtin(engine, "RegExp", &.{try scope.text("\\s+")}));
    const split = try scope.invoke(try scope.invoke(scope_string, "trim", &.{}), "split", &.{regex});
    const scopes = try scope.invoke(split, "filter", &.{try scope.global("Boolean")});
    if (!scope.truthy(try scope.invoke(scopes, "includes", &.{try scope.text(direct_scope)}))) return fail(scope, "OpenAI OAuth grant did not include chatgpt.tokens.use.direct");
    const output = try scope.object();
    try scope.put(output, "type", try scope.text("oauth"));
    try scope.put(output, "access", access);
    try scope.put(output, "refresh", refresh_token);
    const now = try scope.invoke(try scope.global("Date"), "now", &.{});
    const seconds = try scope.get(token, "expires_in");
    const duration = try scope.own(try arithmetic.binary(engine, .multiply, seconds, c.JS_NewInt32(engine.context, 1000)));
    const deadline = try scope.own(try arithmetic.binary(engine, .add, now, duration));
    try scope.put(output, "expires", try scope.own(try arithmetic.binary(engine, .subtract, deadline, c.JS_NewInt32(engine.context, 180000))));
    try scope.put(output, "clientId", client_id);
    try scope.put(output, "scopes", scopes);
    return output;
}
