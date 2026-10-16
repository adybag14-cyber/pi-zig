//! Actual xAI OAuth public facade; every await resumes on the QuickJS owner.
const h = @import("native_ai_oauth_subscription_values.zig");
const v = h.v;
const Scope = h.Scope;
const c = h.c;
const flow = h.flow;
const protocol = @import("../auth/xai_oauth.zig");
const Stage = enum(c_int) { response, json, device, token, polled };
pub fn create(engine: *v.em.Engine) !c.JSValue {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    const result = try s.object();
    try s.put(result, "name", try s.text("xAI (Grok/X subscription)"));
    try s.put(result, "isSubscription", c.pi_js_bool(engine.context, 1));
    try s.put(result, "loginLabel", try s.text("Sign in with SuperGrok or X Premium"));
    try s.put(result, "login", try s.own(try h.helpers.asyncArrow(engine, "loginXai", 1, login, &.{})));
    try s.put(result, "refresh", try s.own(try h.functions.createArrow(engine, "refresh", 2, refresh, &.{})));
    try s.put(result, "toAuth", try s.own(try h.helpers.asyncArrow(engine, "toAuth", 1, toAuth, &.{})));
    return c.JS_DupValue(engine.context, result);
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
    try s.put(result, "apiKey", try s.get(credential, "access"));
    return result;
}
fn login(engine: *v.em.Engine, _: c.JSValue, args: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    const p = try flow.create(engine, c.pi_js_undefined());
    defer engine.freeValue(p.owner);
    errdefer engine.freeValue(p.promise);
    startLogin(&s, p.owner, h.arg(args, 0)) catch |err| try flow.rejectError(engine, p.owner, err);
    return p.promise;
}
fn startLogin(s: *Scope, owner: c.JSValue, interaction: c.JSValue) !void {
    try s.put(owner, "interaction", interaction);
    try s.put(owner, "mode", try s.text("device"));
    const fields = try s.object();
    try s.put(fields, "client_id", try s.text(protocol.CLIENT_ID));
    try s.put(fields, "scope", try s.text(protocol.SCOPE));
    try s.put(fields, "referrer", try s.text("pi"));
    const signal = try s.get(interaction, "signal");
    try s.put(owner, "signal", signal);
    return post(s, owner, protocol.DEVICE_CODE_URL, fields);
}
fn refresh(engine: *v.em.Engine, _: c.JSValue, args: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    // Source normal arrow evaluates this getter synchronously before async entry.
    const token = try s.get(h.arg(args, 0), "refresh");
    const p = try flow.create(engine, c.pi_js_undefined());
    defer engine.freeValue(p.owner);
    errdefer engine.freeValue(p.promise);
    startRefresh(&s, p.owner, token, h.arg(args, 1)) catch |err| try flow.rejectError(engine, p.owner, err);
    return p.promise;
}
fn startRefresh(s: *Scope, owner: c.JSValue, token: c.JSValue, signal: c.JSValue) !void {
    try s.put(owner, "mode", try s.text("refresh"));
    try s.put(owner, "signal", signal);
    try s.put(owner, "previous", token);
    const fields = try s.object();
    try s.put(fields, "grant_type", try s.text("refresh_token"));
    try s.put(fields, "client_id", try s.text(protocol.CLIENT_ID));
    try s.put(fields, "refresh_token", token);
    return post(s, owner, protocol.TOKEN_URL, fields);
}
fn post(s: *Scope, owner: c.JSValue, url: []const u8, fields: c.JSValue) !void {
    const fetch = try h.http.captureFetch(s);
    const address = try s.text(url);
    const body = try h.form(s, fields, false);
    const init = try h.initForm(s, body, try s.get(owner, "signal"), null, true);
    const returned = s.own(h.http.requestWithFetch(s.engine, fetch, address, init) catch |err| return postError(s, owner, err)) catch |err| return err;
    return wait(s, owner, returned, .response);
}
fn postError(s: *Scope, owner: c.JSValue, err: anyerror) !void {
    if (s.truthy(try s.get(try s.get(owner, "signal"), "aborted"))) {
        const generation = s.engine.native_allocation_generation;
        try @import("native_ai_partial_json.zig").discard(s.engine, err, generation);
        return v.errorText(s, try s.text("Login cancelled"));
    }
    return err;
}
fn wait(s: *Scope, owner: c.JSValue, value: c.JSValue, stage: Stage) !void {
    return flow.wait(continued, s.engine, owner, value, @intFromEnum(stage));
}
fn continued(engine: *v.em.Engine, owner: c.JSValue, value: c.JSValue, rejected: bool, raw: c_int) !void {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    const stage: Stage = @enumFromInt(raw);
    if (rejected) {
        if ((stage == .response or stage == .json) and s.truthy(try s.get(try s.get(owner, "signal"), "aborted"))) return flow.settle(engine, owner, true, try s.own(try v.js.builtin(engine, "Error", &.{try s.text("Login cancelled")})));
        if (stage == .json) {
            const status = try s.stringify(try s.get(try s.get(owner, "response"), "status"));
            const message = try s.concat(try s.concat(try s.text("xAI OAuth returned invalid JSON (HTTP "), status), try s.text(")"));
            return flow.settle(engine, owner, true, try s.own(try v.js.builtin(engine, "Error", &.{message})));
        }
        return flow.settle(engine, owner, true, value);
    }
    advance(&s, owner, value, stage) catch |err| try flow.rejectError(engine, owner, err);
}
fn required(s: *Scope, body: c.JSValue, name: [*:0]const u8) !c.JSValue {
    const value = try s.get(body, name);
    if (!c.JS_IsString(value) or try v.length(s, value) == 0) return v.errorText(s, try s.concat(try s.text("Invalid xAI OAuth response field: "), try s.text(@import("std").mem.span(name))));
    return value;
}
fn positive(s: *Scope, body: c.JSValue, name: [*:0]const u8) !c.JSValue {
    const value = try s.get(body, name);
    if (!try h.positive(s, value)) return v.errorText(s, try s.concat(try s.text("Invalid xAI OAuth response field: "), try s.text(name)));
    return value;
}
fn failure(s: *Scope, owner: c.JSValue, body: c.JSValue, action: []const u8) !c.JSValue {
    const parts = try s.array();
    const error_value = try s.get(body, "error");
    const description = try s.get(body, "error_description");
    if (c.JS_IsString(error_value) and s.truthy(error_value)) _ = try s.invoke(parts, "push", &.{error_value});
    if (c.JS_IsString(description) and s.truthy(description)) _ = try s.invoke(parts, "push", &.{description});
    const detail = try s.invoke(parts, "join", &.{try s.text(": ")});
    var message = try s.concat(try s.concat(try s.text("xAI OAuth "), try s.text(action)), try s.text(" failed (HTTP "));
    message = try s.concat(try s.concat(message, try s.stringify(try s.get(try s.get(owner, "response"), "status"))), try s.text(")"));
    if (s.truthy(detail)) message = try s.concat(try s.concat(message, try s.text(": ")), detail);
    return message;
}
fn credentials(s: *Scope, body: c.JSValue, previous: c.JSValue) !c.JSValue {
    const access = try required(s, body, "access_token");
    const raw_refresh = try s.get(body, "refresh_token");
    const refresh_value = if (c.JS_IsUndefined(raw_refresh) and s.truthy(previous)) previous else try required(s, body, "refresh_token");
    const expiry = if (c.JS_IsUndefined(try s.get(body, "expires_in"))) c.JS_NewInt32(s.engine.context, 3600) else try positive(s, body, "expires_in");
    return h.credential(s, access, refresh_value, try h.binary(s, .subtract, try h.binary(s, .add, try h.now(s), try h.binary(s, .multiply, expiry, c.JS_NewInt32(s.engine.context, 1000))), c.JS_NewInt32(s.engine.context, 300000)));
}
fn advance(s: *Scope, owner: c.JSValue, value: c.JSValue, stage: Stage) !void {
    switch (stage) {
        .response => {
            try s.put(owner, "response", value);
            const generation = s.engine.native_allocation_generation;
            const result = s.invoke(value, "json", &.{}) catch |err| {
                try @import("native_ai_partial_json.zig").discard(s.engine, err, generation);
                if (s.truthy(try s.get(try s.get(owner, "signal"), "aborted"))) return v.errorText(s, try s.text("Login cancelled"));
                return v.errorText(s, try s.concat(try s.concat(try s.text("xAI OAuth returned invalid JSON (HTTP "), try s.stringify(try s.get(value, "status"))), try s.text(")")));
            };
            return wait(s, owner, result, .json);
        },
        .json => {
            const body = if (h.record(s, value) and !try v.array(s, value)) value else try s.object();
            // postForm snapshots both getters after JSON consumption, even on
            // success; subsequent helpers read the ordinary wrapper fields.
            const raw_response = try s.get(owner, "response");
            const response = try s.object();
            try s.put(response, "ok", try s.get(raw_response, "ok"));
            try s.put(response, "status", try s.get(raw_response, "status"));
            try s.put(response, "body", body);
            try s.put(owner, "response", response);
            const mode = try s.get(owner, "mode");
            if (try v.eq(s, mode, "poll")) {
                if (s.truthy(try s.get(response, "ok"))) return flow.settle(s.engine, owner, false, try h.pollResult(s, "complete", "value", try credentials(s, body, c.pi_js_undefined())));
                const err = try s.get(body, "error");
                if (try v.eq(s, err, "authorization_pending")) return flow.settle(s.engine, owner, false, try h.pollResult(s, "pending", null, c.pi_js_undefined()));
                if (try v.eq(s, err, "slow_down")) {
                    const interval = try s.get(body, "interval");
                    return flow.settle(s.engine, owner, false, try h.pollResult(s, "slow_down", "intervalSeconds", if (c.JS_IsNumber(interval)) interval else c.pi_js_undefined()));
                }
                const message = if (try v.eq(s, err, "access_denied") or try v.eq(s, err, "authorization_denied")) try s.text("xAI device authorization was denied") else if (try v.eq(s, err, "expired_token")) try s.text("xAI device code expired") else try failure(s, owner, body, "device token polling");
                return flow.settle(s.engine, owner, false, try h.pollResult(s, "failed", "message", message));
            }
            if (!s.truthy(try s.get(response, "ok"))) return v.errorText(s, try failure(s, owner, body, if (try v.eq(s, mode, "device")) "device authorization" else "token refresh"));
            if (try v.eq(s, mode, "refresh")) return flow.settle(s.engine, owner, false, try credentials(s, body, try s.get(owner, "previous")));
            const interval = try s.get(body, "interval");
            const interval_seconds = if (try h.positive(s, interval)) interval else c.pi_js_undefined();
            const complete = try s.get(body, "verification_uri_complete");
            const complete_uri = if (c.JS_IsString(complete) and try v.length(s, complete) > 0) try h.trusted(s, complete, true, "Untrusted verification URI in xAI OAuth response") else c.pi_js_undefined();
            const device_code = try required(s, body, "device_code");
            const user_code = try required(s, body, "user_code");
            const uri = try h.trusted(s, try required(s, body, "verification_uri"), true, "Untrusted verification URI in xAI OAuth response");
            const expires = try positive(s, body, "expires_in");
            try s.put(owner, "deviceCode", device_code);
            const interaction = try s.get(owner, "interaction");
            const notify = try s.get(interaction, "notify");
            const notification = try s.object();
            try s.put(notification, "type", try s.text("device_code"));
            try s.put(notification, "userCode", user_code);
            try s.put(notification, "verificationUri", if (v.nullish(complete_uri)) uri else complete_uri);
            try s.put(notification, "intervalSeconds", interval_seconds);
            try s.put(notification, "expiresInSeconds", expires);
            _ = try s.call(notify, interaction, &.{notification});
            const options = try s.object();
            try s.put(options, "intervalSeconds", interval_seconds);
            try s.put(options, "expiresInSeconds", expires);
            try s.put(options, "waitBeforeFirstPoll", c.pi_js_bool(s.engine.context, 1));
            const poll_signal = try s.get(interaction, "signal");
            try s.put(owner, "signal", poll_signal);
            try s.put(options, "signal", poll_signal);
            try s.put(options, "poll", try s.own(try h.helpers.asyncArrow(s.engine, "poll", 0, poll, &.{owner})));
            return wait(s, owner, try s.own(try h.device.poll(s.engine, options)), .polled);
        },
        .polled => return flow.settle(s.engine, owner, false, value),
        else => unreachable,
    }
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
    try s.put(owner, "signal", try s.get(parent, "signal"));
    const fields = try s.object();
    try s.put(fields, "grant_type", try s.text("urn:ietf:params:oauth:grant-type:device_code"));
    try s.put(fields, "client_id", try s.text(protocol.CLIENT_ID));
    try s.put(fields, "device_code", try s.get(parent, "deviceCode"));
    return post(s, owner, protocol.TOKEN_URL, fields);
}
