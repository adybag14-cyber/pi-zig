//! Actual Kimi Code subscription OAuth with native retry/poll continuations.
const h = @import("native_ai_oauth_subscription_values.zig");
const v = h.v;
const Scope = h.Scope;
const c = h.c;
const flow = h.flow;
const protocol = @import("../auth/kimi_coding_oauth.zig");
const arithmetic = @import("native_image_arithmetic.zig");
const Stage = enum(c_int) { response, json, text, sleep, polled };
pub fn create(engine: *v.em.Engine) !c.JSValue {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    const result = try s.object();
    const env = try s.own(try @import("native_provider_env.zig").create(engine));
    try s.put(result, "name", try s.text("Kimi Code (subscription)"));
    try s.put(result, "isSubscription", c.pi_js_bool(engine.context, 1));
    try s.put(result, "loginLabel", try s.text("Sign in with Kimi Code"));
    try s.put(result, "login", try s.own(try h.helpers.asyncArrow(engine, "loginKimiCoding", 1, login, &.{env})));
    try s.put(result, "refresh", try s.own(try h.helpers.asyncArrow(engine, "refresh", 2, refresh, &.{env})));
    try s.put(result, "toAuth", try s.own(try h.helpers.asyncArrow(engine, "toAuth", 1, toAuth, &.{})));
    return c.JS_DupValue(engine.context, result);
}
fn host(s: *Scope, env: c.JSValue) !c.JSValue {
    var override = try s.call(env, c.pi_js_undefined(), &.{try s.text("KIMI_CODE_OAUTH_HOST")});
    if (!s.truthy(override)) override = try s.call(env, c.pi_js_undefined(), &.{try s.text("KIMI_OAUTH_HOST")});
    const value = if (s.truthy(override)) override else try s.text("https://auth.kimi.com");
    const regex = try s.own(try v.js.builtin(s.engine, "RegExp", &.{ try s.text("/+$"), try s.text("") }));
    return s.invoke(value, "replace", &.{ regex, try s.text("") });
}
fn toAuth(engine: *v.em.Engine, _: c.JSValue, args: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    const p = try flow.create(engine, c.pi_js_undefined());
    defer engine.freeValue(p.owner);
    errdefer engine.freeValue(p.promise);
    const result = toAuthBody(&s, h.arg(args, 0)) catch |err| {
        try flow.rejectError(engine, p.owner, err);
        return p.promise;
    };
    try flow.settle(engine, p.owner, false, result);
    return p.promise;
}
fn toAuthBody(s: *Scope, credential: c.JSValue) !c.JSValue {
    const result = try s.object();
    const headers = try s.object();
    try s.put(headers, "Authorization", try s.concat(try s.text("Bearer "), try s.stringify(try s.get(credential, "access"))));
    try s.put(result, "headers", headers);
    return result;
}
fn login(engine: *v.em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    const p = try flow.create(engine, c.pi_js_undefined());
    defer engine.freeValue(p.owner);
    errdefer engine.freeValue(p.promise);
    try s.put(p.owner, "env", roots[0]);
    startLogin(&s, p.owner, h.arg(args, 0)) catch |err| try flow.rejectError(engine, p.owner, err);
    return p.promise;
}
fn startLogin(s: *Scope, owner: c.JSValue, interaction: c.JSValue) !void {
    try s.put(owner, "host", try host(s, try s.get(owner, "env")));
    try s.put(owner, "interaction", interaction);
    try s.put(owner, "mode", try s.text("device"));
    try s.put(owner, "signal", try s.get(interaction, "signal"));
    const fields = try s.object();
    try s.put(fields, "client_id", try s.text(protocol.CLIENT_ID));
    return post(s, owner, "/api/oauth/device_authorization", fields);
}
fn refresh(engine: *v.em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    const p = try flow.create(engine, c.pi_js_undefined());
    defer engine.freeValue(p.owner);
    errdefer engine.freeValue(p.promise);
    try s.put(p.owner, "env", roots[0]);
    startRefresh(&s, p.owner, h.arg(args, 0), h.arg(args, 1)) catch |err| try flow.rejectError(engine, p.owner, err);
    return p.promise;
}
fn startRefresh(s: *Scope, owner: c.JSValue, credential: c.JSValue, signal: c.JSValue) !void {
    try s.put(owner, "host", try host(s, try s.get(owner, "env")));
    try s.put(owner, "refresh", try s.get(credential, "refresh"));
    try s.put(owner, "signal", signal);
    try s.put(owner, "mode", try s.text("refresh"));
    try s.put(owner, "attempt", c.JS_NewInt32(s.engine.context, 0));
    try s.put(owner, "lastError", c.pi_js_undefined());
    return refreshAttempt(s, owner);
}
fn refreshAttempt(s: *Scope, owner: c.JSValue) !void {
    if (s.truthy(try s.get(try s.get(owner, "signal"), "aborted"))) return v.errorText(s, try s.text("Kimi Code token refresh aborted"));
    const fields = try s.object();
    try s.put(fields, "client_id", try s.text(protocol.CLIENT_ID));
    try s.put(fields, "grant_type", try s.text("refresh_token"));
    try s.put(fields, "refresh_token", try s.get(owner, "refresh"));
    return post(s, owner, "/api/oauth/token", fields);
}
fn post(s: *Scope, owner: c.JSValue, path: []const u8, fields: c.JSValue) !void {
    const fetch = try h.http.captureFetch(s);
    const url = try s.concat(try s.get(owner, "host"), try s.text(path));
    const body = try h.form(s, fields, true);
    const init = try h.initForm(s, body, try s.get(owner, "signal"), 30000, false);
    const result = s.own(h.http.requestWithFetch(s.engine, fetch, url, init) catch |err| {
        if (try v.eq(s, try s.get(owner, "mode"), "refresh")) {
            const reason = try s.own(flow.reason(s.engine, err));
            return retry(s, owner, reason);
        }
        return err;
    }) catch |err| return err;
    return wait(s, owner, result, .response);
}
fn retry(s: *Scope, owner: c.JSValue, reason: c.JSValue) !void {
    // Native Error conversion matches the Source catch before next iteration.
    const error_constructor = try s.global("Error");
    const instance = c.JS_IsInstanceOf(s.engine.context, reason, error_constructor);
    if (instance < 0) return v.js.capture(s.engine);
    const error_value = if (instance != 0) reason else try s.own(try v.js.builtin(s.engine, "Error", &.{try s.stringify(reason)}));
    try s.put(owner, "lastError", error_value);
    const attempt = try s.get(owner, "attempt");
    if (try arithmetic.compare(s.engine, .greater_equal, attempt, c.JS_NewInt32(s.engine.context, 3))) return flow.settle(s.engine, owner, true, error_value);
    try s.put(owner, "attempt", try h.binary(s, .add, attempt, c.JS_NewInt32(s.engine.context, 1)));
    const delay = try h.binary(s, .multiply, c.JS_NewInt32(s.engine.context, 1000), try h.binary(s, .power, c.JS_NewInt32(s.engine.context, 2), attempt));
    return wait(s, owner, try s.own(try h.sleep(s.engine, delay, try s.get(owner, "signal"))), .sleep);
}
fn wait(s: *Scope, owner: c.JSValue, value: c.JSValue, stage: Stage) !void {
    return flow.wait(continued, s.engine, owner, value, @intFromEnum(stage));
}
fn continued(engine: *v.em.Engine, owner: c.JSValue, value: c.JSValue, rejected: bool, raw: c_int) !void {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    const stage: Stage = @enumFromInt(raw);
    if (rejected) {
        if (stage == .response and try v.eq(&s, try s.get(owner, "mode"), "refresh")) {
            retry(&s, owner, value) catch |err| try flow.rejectError(engine, owner, err);
            return;
        }
        if (stage == .json) {
            afterJson(&s, owner, c.pi_js_null()) catch |err| try flow.rejectError(engine, owner, err);
            return;
        }
        if (stage == .text) {
            afterText(&s, owner, try s.text("")) catch |err| try flow.rejectError(engine, owner, err);
            return;
        }
        return flow.settle(engine, owner, true, value);
    }
    advance(&s, owner, value, stage) catch |err| try flow.rejectError(engine, owner, err);
}
fn advance(s: *Scope, owner: c.JSValue, value: c.JSValue, stage: Stage) !void {
    switch (stage) {
        .response => {
            try s.put(owner, "response", value);
            const mode = try s.get(owner, "mode");
            if ((try v.eq(s, mode, "device") and !s.truthy(try s.get(value, "ok"))) or (try v.eq(s, mode, "poll") and try arithmetic.compare(s.engine, .greater_equal, try s.get(value, "status"), c.JS_NewInt32(s.engine.context, 500)))) return wait(s, owner, try s.invoke(value, "text", &.{}), .text);
            const generation = s.engine.native_allocation_generation;
            const parsed = s.invoke(value, "json", &.{}) catch |err| {
                try @import("native_ai_partial_json.zig").discard(s.engine, err, generation);
                return afterJson(s, owner, c.pi_js_null());
            };
            return wait(s, owner, parsed, .json);
        },
        .json => return afterJson(s, owner, value),
        .text => return afterText(s, owner, value),
        .sleep => return refreshAttempt(s, owner),
        .polled => return flow.settle(s.engine, owner, false, value),
    }
}
fn statusMessage(s: *Scope, owner: c.JSValue, prefix: []const u8) !c.JSValue {
    return s.concat(try s.text(prefix), try s.stringify(try s.get(try s.get(owner, "response"), "status")));
}
fn afterText(s: *Scope, owner: c.JSValue, text: c.JSValue) !void {
    const polling = try v.eq(s, try s.get(owner, "mode"), "poll");
    var message = try statusMessage(s, owner, if (polling) "Kimi Code device token request failed with status " else "Kimi Code device authorization failed with status ");
    if (s.truthy(text)) message = try s.concat(try s.concat(message, try s.text(": ")), text);
    if (polling) return flow.settle(s.engine, owner, false, try h.pollResult(s, "failed", "message", message));
    return v.errorText(s, message);
}
fn token(s: *Scope, body: c.JSValue, operation: []const u8) !c.JSValue {
    const access = try v.optional(s, body, "access_token");
    const refresh_value = try v.optional(s, body, "refresh_token");
    const expires = try v.optional(s, body, "expires_in");
    if (!c.JS_IsString(access) or !s.truthy(access) or !c.JS_IsString(refresh_value) or !s.truthy(refresh_value) or !try h.positive(s, expires)) return v.errorText(s, try s.concat(try s.concat(try s.concat(try s.text("Kimi Code token "), try s.text(operation)), try s.text(" response missing fields: ")), try h.json(s, body)));
    return h.credential(s, access, refresh_value, try h.binary(s, .add, try h.now(s), try h.binary(s, .multiply, expires, c.JS_NewInt32(s.engine.context, 1000))));
}
fn validUri(s: *Scope, value: c.JSValue) !bool {
    if (!c.JS_IsString(value) or !s.truthy(value)) return false;
    const generation = s.engine.native_allocation_generation;
    _ = h.trusted(s, value, false, "Invalid Kimi URL") catch |err| {
        try @import("native_ai_partial_json.zig").discard(s.engine, err, generation);
        return false;
    };
    return true;
}
fn afterJson(s: *Scope, owner: c.JSValue, raw: c.JSValue) !void {
    const body = if (h.record(s, raw)) raw else c.pi_js_null();
    const response = try s.get(owner, "response");
    const mode = try s.get(owner, "mode");
    if (try v.eq(s, mode, "device")) {
        const device_code = try v.optional(s, body, "device_code");
        const user_code = try v.optional(s, body, "user_code");
        const uri = try v.optional(s, body, "verification_uri");
        const complete = try v.optional(s, body, "verification_uri_complete");
        if (!c.JS_IsString(device_code) or !c.JS_IsString(user_code) or !c.JS_IsString(uri) or !c.JS_IsString(complete) or !try validUri(s, complete) or !try validUri(s, uri)) return v.errorText(s, try s.concat(try s.text("Invalid Kimi Code device authorization response: "), try h.json(s, body)));
        const interval = try v.optional(s, body, "interval");
        const expires = try v.optional(s, body, "expires_in");
        const interval_seconds = if (try h.positive(s, interval)) interval else c.JS_NewInt32(s.engine.context, 5);
        const expires_seconds = if (try h.positive(s, expires)) expires else c.JS_NewInt32(s.engine.context, 900);
        try s.put(owner, "deviceCode", device_code);
        const interaction = try s.get(owner, "interaction");
        const notify = try s.get(interaction, "notify");
        const notification = try s.object();
        try s.put(notification, "type", try s.text("device_code"));
        try s.put(notification, "userCode", user_code);
        try s.put(notification, "verificationUri", complete);
        try s.put(notification, "intervalSeconds", interval_seconds);
        try s.put(notification, "expiresInSeconds", expires_seconds);
        _ = try s.call(notify, interaction, &.{notification});
        const options = try s.object();
        try s.put(options, "intervalSeconds", interval_seconds);
        try s.put(options, "expiresInSeconds", expires_seconds);
        try s.put(options, "waitBeforeFirstPoll", c.pi_js_bool(s.engine.context, 1));
        const poll_signal = try s.get(interaction, "signal");
        try s.put(owner, "signal", poll_signal);
        try s.put(options, "signal", poll_signal);
        try s.put(options, "poll", try s.own(try h.helpers.asyncArrow(s.engine, "poll", 0, poll, &.{owner})));
        return wait(s, owner, try s.own(try h.device.poll(s.engine, options)), .polled);
    }
    if (try v.eq(s, mode, "poll")) {
        if (s.truthy(try s.get(response, "ok")) and c.JS_IsString(try v.optional(s, body, "access_token"))) {
            const generation = s.engine.native_allocation_generation;
            const result = token(s, body, "poll") catch |err| {
                const reason = try s.own(flow.reason(s.engine, err));
                _ = generation;
                return flow.settle(s.engine, owner, false, try h.pollResult(s, "failed", "message", try h.errorMessage(s, reason)));
            };
            return flow.settle(s.engine, owner, false, try h.pollResult(s, "complete", "value", result));
        }
        const err = try v.optional(s, body, "error");
        if (try v.eq(s, err, "authorization_pending")) return flow.settle(s.engine, owner, false, try h.pollResult(s, "pending", null, c.pi_js_undefined()));
        if (try v.eq(s, err, "slow_down")) {
            const interval = try v.optional(s, body, "interval");
            return flow.settle(s.engine, owner, false, try h.pollResult(s, "slow_down", "intervalSeconds", if (c.JS_IsNumber(interval) and try arithmetic.compare(s.engine, .greater, interval, c.JS_NewInt32(s.engine.context, 0))) interval else c.pi_js_undefined()));
        }
        var message = if (try v.eq(s, err, "expired_token")) try s.text("Kimi Code device authorization expired. Please restart login.") else if (try v.eq(s, err, "access_denied")) try s.text("Kimi Code login was denied.") else try s.concat(try statusMessage(s, owner, "Kimi Code device token request failed (status "), try s.text(")"));
        if (!try v.eq(s, err, "expired_token") and !try v.eq(s, err, "access_denied") and c.JS_IsString(err)) {
            message = try s.concat(try s.concat(message, try s.text(": ")), err);
            const description = try v.optional(s, body, "error_description");
            if (c.JS_IsString(description)) message = try s.concat(try s.concat(message, try s.text(": ")), description);
        }
        return flow.settle(s.engine, owner, false, try h.pollResult(s, "failed", "message", message));
    }
    if (s.truthy(try s.get(response, "ok"))) return flow.settle(s.engine, owner, false, try token(s, body, "refresh"));
    const status = try s.get(response, "status");
    if (s.equal(status, c.JS_NewInt32(s.engine.context, 401)) or s.equal(status, c.JS_NewInt32(s.engine.context, 403)) or try v.eq(s, try v.optional(s, body, "error"), "invalid_grant")) {
        var message = try s.concat(try statusMessage(s, owner, "Kimi Code token refresh unauthorized (status "), try s.text(")"));
        const description = try v.optional(s, body, "error_description");
        if (c.JS_IsString(description)) message = try s.concat(try s.concat(message, try s.text(": ")), description);
        return v.errorText(s, message);
    }
    if ((s.equal(status, c.JS_NewInt32(s.engine.context, 429)) or try arithmetic.compare(s.engine, .greater_equal, status, c.JS_NewInt32(s.engine.context, 500))) and try arithmetic.compare(s.engine, .less, try s.get(owner, "attempt"), c.JS_NewInt32(s.engine.context, 3))) return retry(s, owner, try s.own(try v.js.builtin(s.engine, "Error", &.{try statusMessage(s, owner, "Kimi Code token refresh failed with status ")})));
    const text = try h.json(s, body);
    var message = try statusMessage(s, owner, "Kimi Code token refresh failed with status ");
    if (s.truthy(text)) message = try s.concat(try s.concat(message, try s.text(": ")), text);
    return v.errorText(s, message);
}
fn poll(engine: *v.em.Engine, _: c.JSValue, _: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    const p = try flow.create(engine, roots[0]);
    defer engine.freeValue(p.owner);
    errdefer engine.freeValue(p.promise);
    startPoll(&s, p.owner, roots[0]) catch |err| try flow.rejectError(engine, p.owner, err);
    return p.promise;
}
fn startPoll(s: *Scope, owner: c.JSValue, parent: c.JSValue) !void {
    try s.put(owner, "mode", try s.text("poll"));
    try s.put(owner, "host", try s.get(parent, "host"));
    try s.put(owner, "signal", try s.get(parent, "signal"));
    const fields = try s.object();
    try s.put(fields, "client_id", try s.text(protocol.CLIENT_ID));
    try s.put(fields, "device_code", try s.get(parent, "deviceCode"));
    try s.put(fields, "grant_type", try s.text("urn:ietf:params:oauth:grant-type:device_code"));
    return post(s, owner, "/api/oauth/token", fields);
}
