//! Radius OAuth factory with guest-visible values retained across native awaits.
const v = @import("native_ai_provider_values.zig");
const Scope = v.Scope;
const c = v.c;
const flow = @import("native_agent_async.zig");
const functions = @import("native_node_function.zig");
const helpers = @import("native_ai_auth_helpers.zig");
const http = @import("native_ai_oauth_http.zig");
const device = @import("native_ai_oauth_device_code.zig");
const callback = @import("native_ai_oauth_callback_server.zig");
const common = @import("native_ai_oauth_codex.zig");
const protocol = @import("../auth/radius_oauth.zig");
const Stage = enum(c_int) { method, discovery, discovery_json, discovery_text, pkce, listener, browser, token, token_json, error_text, device, device_json, poll };

pub fn create(engine: *v.em.Engine, options: c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    return createWithConstructor(engine, options, try errorConstructor(&s));
}
/// Module-local Error subclass identity belongs to the exported factory, so all
/// OAuth objects created from one module share the same captured constructor.
pub fn factory(engine: *v.em.Engine) !c.JSValue {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    const Adapter = struct {
        fn call(host: *v.em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
            return createWithConstructor(host, common.arg(args, 0), roots[0]);
        }
    };
    return functions.create(engine, "createRadiusOAuth", 1, Adapter.call, &.{try errorConstructor(&s)});
}
fn createWithConstructor(engine: *v.em.Engine, options: c.JSValue, constructor: c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    const raw = try common.property(&s, options, "gateway");
    const scheme = try literalRegex(&s, "^https?://", "iu");
    const with_scheme = if (s.truthy(try s.invoke(scheme, "test", &.{raw}))) raw else try s.concat(try s.text("https://"), try s.stringify(raw));
    const trailing = try literalRegex(&s, "/+$", "u");
    const normalized = try s.invoke(with_scheme, "replace", &.{ trailing, try s.text("") });
    const state = try s.object();
    try s.put(state, "options", options);
    try s.put(state, "gateway", normalized);
    try s.put(state, "errorConstructor", constructor);
    const result = try s.object();
    try s.put(result, "name", try s.get(options, "name"));
    try s.put(result, "login", try s.own(try helpers.asyncArrow(engine, "login", 1, login, &.{state})));
    try s.put(result, "refresh", try s.own(try helpers.asyncArrow(engine, "refresh", 2, refresh, &.{state})));
    try s.put(result, "toAuth", try s.own(try helpers.asyncArrow(engine, "toAuth", 1, common.toAuth, &.{})));
    return c.JS_DupValue(engine.context, result);
}
fn literalRegex(s: *Scope, pattern: []const u8, flags: []const u8) !c.JSValue {
    var args = [_]c.JSValue{ try s.text(pattern), try s.text(flags) };
    return s.own(try s.engine.checked(c.JS_CallConstructor(s.engine.context, s.engine.intrinsic_regexp_constructor, args.len, &args)));
}
fn login(engine: *v.em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    const pending = try flow.create(engine, roots[0]);
    defer engine.freeValue(pending.owner);
    errdefer engine.freeValue(pending.promise);
    startLogin(&s, pending.owner, common.arg(args, 0)) catch |err| try flow.rejectError(engine, pending.owner, err);
    return pending.promise;
}
fn startLogin(s: *Scope, owner: c.JSValue, interaction: c.JSValue) !void {
    try s.put(owner, "interaction", interaction);
    const prompt_function = try s.get(interaction, "prompt");
    const prompt = try s.object();
    try s.put(prompt, "type", try s.text("select"));
    try s.put(prompt, "message", try s.concat(try s.concat(try s.text("Sign in to "), try s.stringify(try optionName(s, owner))), try s.text(":")));
    const choices = try s.array();
    inline for (.{ .{ "browser", "Sign in with browser (recommended)" }, .{ "device-code", "Sign in with device code (when signing in from another device)" } }, 0..) |choice, index| {
        const item = try s.object();
        try s.put(item, "id", try s.text(choice[0]));
        try s.put(item, "label", try s.text(choice[1]));
        try s.index(choices, index, item);
    }
    try s.put(prompt, "options", choices);
    return flow.wait(continued, s.engine, owner, try s.call(prompt_function, interaction, &.{prompt}), @intFromEnum(Stage.method));
}
fn optionName(s: *Scope, owner: c.JSValue) !c.JSValue {
    return s.get(try s.get(try s.get(owner, "agent"), "options"), "name");
}
fn gateway(s: *Scope, owner: c.JSValue) !c.JSValue {
    return s.get(try s.get(owner, "agent"), "gateway");
}
fn refresh(engine: *v.em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    const pending = try flow.create(engine, roots[0]);
    defer engine.freeValue(pending.owner);
    errdefer engine.freeValue(pending.promise);
    startRefresh(&s, pending.owner, common.arg(args, 0), common.arg(args, 1)) catch |err| try flow.rejectError(engine, pending.owner, err);
    return pending.promise;
}
fn startRefresh(s: *Scope, owner: c.JSValue, credential: c.JSValue, signal: c.JSValue) !void {
    const constructor = try s.global("URLSearchParams");
    const body = try common.formWithConstructor(s, constructor, &.{ .{ "grant_type", try s.text("refresh_token") }, .{ "client_id", try s.text(protocol.CLIENT_ID) }, .{ "refresh_token", try common.property(s, credential, "refresh") } });
    try s.put(owner, "signal", signal);
    return tokenRequest(s, owner, body);
}
fn request(s: *Scope, owner: c.JSValue, path: []const u8, body: c.JSValue, stage: Stage) !void {
    const generation = s.engine.native_allocation_generation;
    requestBody(s, owner, path, body, stage) catch |err| {
        if (s.engine.nativeAllocationError(err, generation) == error.OutOfMemory) return flow.rejectError(s.engine, owner, err);
        const reason = try s.own(flow.reason(s.engine, err));
        return continued(s.engine, owner, reason, true, @intFromEnum(stage));
    };
}
fn requestBody(s: *Scope, owner: c.JSValue, path: []const u8, body: c.JSValue, stage: Stage) !void {
    // Source evaluates fetch and URL before the init object and its signal.
    const fetch = try http.captureFetch(s);
    const url = try s.own(try v.js.builtin(s.engine, "URL", &.{ try s.text(path), try gateway(s, owner) }));
    const init = try s.object();
    if (!c.JS_IsUndefined(body)) try s.put(init, "method", try s.text("POST"));
    const headers = try s.object();
    try s.put(headers, "accept", try s.text("application/json"));
    if (!c.JS_IsUndefined(body)) try s.put(headers, "content-type", try s.text("application/x-www-form-urlencoded"));
    try s.put(init, "headers", headers);
    if (!c.JS_IsUndefined(body)) try s.put(init, "body", body);
    try s.put(init, "signal", try s.get(owner, "signal"));
    return flow.wait(continued, s.engine, owner, try s.own(try http.requestWithFetch(s.engine, fetch, url, init)), @intFromEnum(stage));
}
fn tokenRequest(s: *Scope, owner: c.JSValue, body: c.JSValue) !void {
    return request(s, owner, "/v1/oauth/token", body, .token);
}
fn close(s: *Scope, owner: c.JSValue) !void {
    const server = try s.get(owner, "callback");
    if (!v.nullish(server)) _ = try s.invoke(server, "close", &.{});
}
fn finish(s: *Scope, owner: c.JSValue, rejected: bool, value: c.JSValue) !void {
    close(s, owner) catch |err| return flow.rejectError(s.engine, owner, err);
    return flow.settle(s.engine, owner, rejected, value);
}
fn continued(engine: *v.em.Engine, owner: c.JSValue, value: c.JSValue, rejected: bool, raw: c_int) anyerror!void {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    const stage: Stage = @enumFromInt(raw);
    if (rejected) {
        if (stage == .error_text) return errorResponse(&s, owner, try s.text(""));
        if ((stage == .token or stage == .device) and s.truthy(try s.get(try s.get(owner, "signal"), "aborted"))) return finish(&s, owner, true, try s.own(try v.js.builtin(engine, "Error", &.{try s.text("Login cancelled")})));
        return finish(&s, owner, true, value);
    }
    advance(&s, owner, value, stage) catch |err| return finish(&s, owner, true, try s.own(flow.reason(engine, err)));
}
fn advance(s: *Scope, owner: c.JSValue, value: c.JSValue, stage: Stage) !void {
    switch (stage) {
        .method => {
            if (try v.eq(s, value, "device-code")) {
                try s.put(owner, "signal", try s.get(try s.get(owner, "interaction"), "signal"));
                const body = try common.form(s, &.{ .{ "client_id", try s.text(protocol.CLIENT_ID) }, .{ "scope", try s.text(protocol.SCOPE) } });
                return request(s, owner, "/v1/oauth/device", body, .device);
            }
            if (try v.eq(s, value, "browser")) {
                try s.put(owner, "signal", try s.get(try s.get(owner, "interaction"), "signal"));
                return request(s, owner, "/v1/oauth", c.pi_js_undefined(), .discovery);
            }
            const message = try s.concat(try s.concat(try s.concat(try s.text("Unknown "), try s.stringify(try optionName(s, owner))), try s.text(" sign-in method: ")), try s.stringify(value));
            return common.failure(s, owner, message);
        },
        .discovery => {
            try s.put(owner, "response", value);
            const ok = s.truthy(try s.get(value, "ok"));
            return flow.wait(continued, s.engine, owner, try s.invoke(value, if (ok) "json" else "text", &.{}), @intFromEnum(if (ok) Stage.discovery_json else Stage.discovery_text));
        },
        .discovery_text => {
            var message = try s.concat(try s.text("Could not load Radius OAuth config from "), try gateway(s, owner));
            message = try s.concat(message, try s.text(": "));
            message = try s.concat(message, try s.stringify(try s.get(try s.get(owner, "response"), "status")));
            return common.failure(s, owner, try s.concat(try s.concat(message, try s.text(" ")), value));
        },
        .discovery_json => {
            const endpoint = try common.property(s, value, "authorizationEndpoint");
            if (!c.JS_IsString(endpoint)) return common.failure(s, owner, try s.concat(try s.text("Invalid Radius OAuth config from "), try gateway(s, owner)));
            try s.put(owner, "endpoint", try s.get(value, "authorizationEndpoint"));
            return flow.wait(continued, s.engine, owner, try s.own(try @import("native_ai_oauth_pkce.zig").generate(s.engine)), @intFromEnum(Stage.pkce));
        },
        .pkce => return browserStart(s, owner, value),
        .listener => {
            try s.put(owner, "callback", value);
            const interaction = try s.get(owner, "interaction");
            const progress_notify = try s.get(interaction, "notify");
            const progress = try s.object();
            try s.put(progress, "type", try s.text("progress"));
            try s.put(progress, "message", try s.text("Listening for OAuth callback on " ++ protocol.REDIRECT_URI));
            _ = try s.call(progress_notify, interaction, &.{progress});
            const auth_notify = try s.get(interaction, "notify");
            const auth = try s.object();
            try s.put(auth, "type", try s.text("auth_url"));
            try s.put(auth, "url", try s.invoke(try s.get(owner, "url"), "toString", &.{}));
            try s.put(auth, "instructions", try s.text("Continue in your browser."));
            _ = try s.call(auth_notify, interaction, &.{auth});
            return flow.wait(continued, s.engine, owner, try s.invoke(value, "wait", &.{}), @intFromEnum(Stage.browser));
        },
        .browser => {
            if (!s.truthy(value)) return finish(s, owner, true, try s.own(try v.js.builtin(s.engine, "Error", &.{try s.text("OAuth callback did not complete.")})));
            return finish(s, owner, false, value);
        },
        .token, .device => {
            try s.put(owner, "response", value);
            const ok = s.truthy(try s.get(value, "ok"));
            if (!ok) try s.put(owner, "errorMessage", try s.text(if (stage == .token) "Radius OAuth token request failed" else "Radius OAuth device authorization failed"));
            return flow.wait(continued, s.engine, owner, try s.invoke(value, if (ok) "json" else "text", &.{}), @intFromEnum(if (!ok) Stage.error_text else if (stage == .token) Stage.token_json else Stage.device_json));
        },
        .token_json => {
            const credential = try s.object();
            try s.put(credential, "type", try s.text("oauth"));
            try s.put(credential, "access", try common.property(s, value, "access_token"));
            try s.put(credential, "refresh", try s.get(value, "refresh_token"));
            const now = try s.invoke(try s.global("Date"), "now", &.{});
            try s.put(credential, "expires", try common.binary(s, .subtract, try common.binary(s, .add, now, try common.binary(s, .multiply, try s.get(value, "expires_in"), c.JS_NewInt32(s.engine.context, 1000))), c.JS_NewInt32(s.engine.context, 60_000)));
            try s.put(credential, "scope", try s.get(value, "scope"));
            return finish(s, owner, false, credential);
        },
        .error_text => return errorResponse(s, owner, value),
        .device_json => return deviceReady(s, owner, value),
        .poll => return finish(s, owner, false, value),
    }
}
fn errorResponse(s: *Scope, owner: c.JSValue, text: c.JSValue) !void {
    var oauth_error = c.pi_js_undefined();
    var description = c.pi_js_undefined();
    if (s.truthy(text)) {
        const generation = s.engine.native_allocation_generation;
        const parsed = readErrorDetail(s, text) catch |err| blk: {
            try @import("native_ai_partial_json.zig").discard(s.engine, err, generation);
            description = text;
            break :blk null;
        };
        if (parsed) |fields| {
            oauth_error = fields[0];
            description = fields[1];
        }
    }
    const status = try s.get(try s.get(owner, "response"), "status");
    const constructor = try s.get(try s.get(owner, "agent"), "errorConstructor");
    const err = try s.own(try s.engine.checked(c.JS_CallConstructor(s.engine.context, constructor, 4, @constCast(&[_]c.JSValue{ status, oauth_error, description, try s.get(owner, "errorMessage") }))));
    // Private brand preserves Source instanceof OAuthResponseError without trusting
    // a user supplied status/oauthError-shaped rejection.
    try s.put(owner, "oauthFailure", err);
    return finish(s, owner, true, err);
}
fn readErrorDetail(s: *Scope, text: c.JSValue) !?[2]c.JSValue {
    const parsed = try s.invoke(try s.global("JSON"), "parse", &.{text});
    const err = try s.get(parsed, "error");
    const desc = try s.get(parsed, "error_description");
    return .{ if (c.JS_IsString(err)) err else c.pi_js_undefined(), if (c.JS_IsString(desc)) desc else c.pi_js_undefined() };
}
fn errorConstructor(s: *Scope) !c.JSValue {
    const base = try s.global("Error");
    const prototype = try s.own(try s.engine.checked(c.JS_NewObjectProto(s.engine.context, try s.get(base, "prototype"))));
    const Adapter = struct {
        fn construct(engine: *v.em.Engine, target: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
            var local: Scope = .{ .engine = engine };
            defer local.deinit();
            const status = common.arg(args, 0);
            const oauth_error = common.arg(args, 1);
            const description = common.arg(args, 2);
            const detail = if (local.truthy(oauth_error)) if (local.truthy(description)) try local.concat(try local.concat(try local.stringify(oauth_error), try local.text(": ")), try local.stringify(description)) else oauth_error else if (local.truthy(description)) description else try local.call(try local.global("String"), c.pi_js_undefined(), &.{status});
            const message = try local.concat(try local.concat(try local.stringify(common.arg(args, 3)), try local.text(": ")), try local.stringify(detail));
            const result = try local.own(try engine.checked(c.JS_CallConstructor(engine.context, roots[0], 1, @constCast(&[_]c.JSValue{message}))));
            if (c.JS_SetPrototype(engine.context, result, try local.get(target, "prototype")) < 0) return v.js.capture(engine);
            try local.put(result, "status", status);
            try local.put(result, "oauthError", oauth_error);
            return c.JS_DupValue(engine.context, result);
        }
    };
    const constructor = try s.own(try @import("native_class.zig").constructor(s.engine, "OAuthResponseError", 4, prototype, Adapter.construct, &.{base}));
    if (c.JS_SetPrototype(s.engine.context, constructor, base) < 0) return v.js.capture(s.engine);
    return constructor;
}
fn pollFailure(s: *Scope, owner: c.JSValue, err: c.JSValue, oauth_error: c.JSValue) !void {
    const result = try s.object();
    if (try v.eq(s, oauth_error, "authorization_pending")) try s.put(result, "status", try s.text("pending")) else if (try v.eq(s, oauth_error, "slow_down")) try s.put(result, "status", try s.text("slow_down")) else if (try v.eq(s, oauth_error, "expired_token") or try v.eq(s, oauth_error, "access_denied")) {
        try s.put(result, "status", try s.text("failed"));
        try s.put(result, "message", try s.text(if (try v.eq(s, oauth_error, "expired_token")) "Device authorization expired." else "Device authorization was denied."));
    } else return flow.settle(s.engine, owner, true, err);
    return flow.settle(s.engine, owner, false, result);
}
fn deviceReady(s: *Scope, owner: c.JSValue, data: c.JSValue) !void {
    if (!s.truthy(try common.property(s, data, "device_code")) or !s.truthy(try s.get(data, "user_code")) or !s.truthy(try s.get(data, "verification_uri")) or !s.truthy(try s.get(data, "expires_in"))) return common.failure(s, owner, try s.text("Radius OAuth device authorization response is missing required fields"));
    const info = try s.object();
    inline for (.{ "device_code", "user_code", "verification_uri", "expires_in", "interval" }) |key| try s.put(info, key, try s.get(data, key));
    try s.put(owner, "device", info);
    const interaction = try s.get(owner, "interaction");
    const notify = try s.get(interaction, "notify");
    const notification = try s.object();
    try s.put(notification, "type", try s.text("device_code"));
    try s.put(notification, "userCode", try s.get(info, "user_code"));
    try s.put(notification, "verificationUri", try s.get(info, "verification_uri"));
    try s.put(notification, "intervalSeconds", try s.get(info, "interval"));
    try s.put(notification, "expiresInSeconds", try s.get(info, "expires_in"));
    _ = try s.call(notify, interaction, &.{notification});
    const options = try s.object();
    try s.put(options, "intervalSeconds", try s.get(info, "interval"));
    try s.put(options, "expiresInSeconds", try s.get(info, "expires_in"));
    try s.put(options, "signal", try s.get(try s.get(owner, "interaction"), "signal"));
    const Adapter = struct {
        fn call(engine: *v.em.Engine, _: c.JSValue, _: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
            var local: Scope = .{ .engine = engine };
            defer local.deinit();
            const pending = try flow.create(engine, try local.get(roots[0], "agent"));
            defer engine.freeValue(pending.owner);
            errdefer engine.freeValue(pending.promise);
            const token = try flow.create(engine, try local.get(roots[0], "agent"));
            defer engine.freeValue(token.owner);
            defer engine.freeValue(token.promise);
            try local.put(pending.owner, "tokenOwner", token.owner);
            try local.put(token.owner, "signal", try local.get(try local.get(roots[0], "interaction"), "signal"));
            const body = try common.form(&local, &.{ .{ "grant_type", try local.text(protocol.DEVICE_GRANT) }, .{ "client_id", try local.text(protocol.CLIENT_ID) }, .{ "device_code", try local.get(try local.get(roots[0], "device"), "device_code") } });
            tokenRequest(&local, token.owner, body) catch |err| try flow.rejectError(engine, token.owner, err);
            try flow.wait(pollReady, engine, pending.owner, token.promise, 0);
            return pending.promise;
        }
    };
    try s.put(options, "poll", try s.own(try helpers.asyncArrow(s.engine, "poll", 0, Adapter.call, &.{owner})));
    return flow.wait(continued, s.engine, owner, try s.own(try device.poll(s.engine, options)), @intFromEnum(Stage.poll));
}
fn pollReady(engine: *v.em.Engine, owner: c.JSValue, value: c.JSValue, rejected: bool, _: c_int) !void {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    if (rejected) {
        const token = try s.get(owner, "tokenOwner");
        if (s.equal(value, try s.get(token, "oauthFailure"))) return pollFailure(&s, owner, value, try s.get(value, "oauthError"));
        return flow.settle(engine, owner, true, value);
    }
    const result = try s.object();
    try s.put(result, "status", try s.text("complete"));
    try s.put(result, "value", value);
    return flow.settle(engine, owner, false, result);
}
fn browserStart(s: *Scope, owner: c.JSValue, pair: c.JSValue) !void {
    try s.put(owner, "verifier", try s.get(pair, "verifier"));
    const state = try s.invoke(try s.global("crypto"), "randomUUID", &.{});
    const url = try s.own(try v.js.builtin(s.engine, "URL", &.{try s.get(owner, "endpoint")}));
    const params = try common.form(s, &.{ .{ "response_type", try s.text("code") }, .{ "client_id", try s.text(protocol.CLIENT_ID) }, .{ "redirect_uri", try s.text(protocol.REDIRECT_URI) }, .{ "scope", try s.text(protocol.SCOPE) }, .{ "code_challenge", try s.get(pair, "challenge") }, .{ "code_challenge_method", try s.text("S256") }, .{ "handoff", try s.text("url") }, .{ "state", state } });
    try s.set(url, "search", try s.invoke(params, "toString", &.{}));
    try s.put(owner, "url", url);
    const options = try s.object();
    try s.put(options, "providerName", try s.text("Radius"));
    try s.put(options, "host", try s.text(protocol.CALLBACK_HOST));
    try s.put(options, "port", c.JS_NewInt32(s.engine.context, protocol.CALLBACK_PORT));
    try s.put(options, "path", try s.text(protocol.CALLBACK_PATH));
    try s.put(options, "state", state);
    const Adapter = struct {
        fn call(engine: *v.em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
            var local: Scope = .{ .engine = engine };
            defer local.deinit();
            const pending = try flow.create(engine, try local.get(roots[0], "agent"));
            defer engine.freeValue(pending.owner);
            errdefer engine.freeValue(pending.promise);
            const body = try common.form(&local, &.{ .{ "grant_type", try local.text("authorization_code") }, .{ "client_id", try local.text(protocol.CLIENT_ID) }, .{ "redirect_uri", try local.text(protocol.REDIRECT_URI) }, .{ "code", common.arg(args, 0) }, .{ "code_verifier", try local.get(roots[0], "verifier") } });
            try local.put(pending.owner, "signal", try local.get(try local.get(roots[0], "interaction"), "signal"));
            tokenRequest(&local, pending.owner, body) catch |err| try flow.rejectError(engine, pending.owner, err);
            return pending.promise;
        }
    };
    try s.put(options, "complete", try s.own(try functions.createArrow(s.engine, "complete", 1, Adapter.call, &.{owner})));
    try s.put(options, "signal", try s.get(try s.get(owner, "interaction"), "signal"));
    return flow.wait(continued, s.engine, owner, try s.own(try callback.start(s.engine, options)), @intFromEnum(Stage.listener));
}
