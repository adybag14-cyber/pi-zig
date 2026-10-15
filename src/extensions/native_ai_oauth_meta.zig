//! Meta device authorization and identity-to-Model-API-key exchange.
//! All algorithms and continuations are native Zig; guest values stay on the VM owner.
const v = @import("native_ai_provider_values.zig");
const c = v.c;
const Scope = v.Scope;
const flow = @import("native_agent_async.zig");
const http = @import("native_ai_oauth_http.zig");
const device_flow = @import("native_ai_oauth_device_code.zig");
const helpers = @import("native_ai_auth_helpers.zig");
const functions = @import("native_node_function.zig");
const client_id = "1031625952748946";
const authorize_url = "https://auth.meta.com/oidc/device/authorization/";
const token_url = "https://auth.meta.com/oidc/device/token/";
const mint_url = "https://api.meta.ai/muse-code/key";
const Stage = enum(c_int) { authorized, minted };

pub fn create(engine: *v.em.Engine) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const object = try scope.object();
    try scope.put(object, "name", try scope.text("Meta (Muse subscription)"));
    try scope.put(object, "isSubscription", c.pi_js_bool(engine.context, 1));
    try scope.put(object, "loginLabel", try scope.text("Sign in with Meta"));
    try scope.put(object, "login", try scope.own(try helpers.asyncArrow(engine, "loginMeta", 1, login, &.{})));
    try scope.put(object, "refresh", try scope.own(try functions.createArrow(engine, "refresh", 2, refresh, &.{})));
    try scope.put(object, "toAuth", try scope.own(try helpers.asyncArrow(engine, "toAuth", 1, toAuth, &.{})));
    return c.JS_DupValue(engine.context, object);
}
fn arg(args: []const c.JSValue, i: usize) c.JSValue {
    return if (i < args.len) args[i] else c.pi_js_undefined();
}
fn login(engine: *v.em.Engine, _: c.JSValue, args: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const state = try scope.object();
    try scope.put(state, "interaction", arg(args, 0));
    try scope.put(state, "login", c.pi_js_bool(engine.context, 1));
    const pending = try flow.create(engine, state);
    defer engine.freeValue(pending.owner);
    errdefer engine.freeValue(pending.promise);
    startLogin(&scope, pending.owner) catch |err| try reject(&scope, pending.owner, err);
    return pending.promise;
}
fn refresh(engine: *v.em.Engine, _: c.JSValue, args: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    // This read belongs to the synchronous arrow, before entering async mintApiKey.
    const identity = try scope.get(arg(args, 0), "refresh");
    return mintCredential(engine, identity, arg(args, 1));
}
fn mintCredential(engine: *v.em.Engine, identity: c.JSValue, signal: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const state = try scope.object();
    try scope.put(state, "identity", identity);
    const pending = try flow.create(engine, state);
    defer engine.freeValue(pending.owner);
    errdefer engine.freeValue(pending.promise);
    mint(&scope, pending.owner, signal) catch |err| try flow.rejectError(engine, pending.owner, err);
    return pending.promise;
}
fn toAuth(engine: *v.em.Engine, _: c.JSValue, args: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const pending = try flow.create(engine, c.pi_js_undefined());
    defer engine.freeValue(pending.owner);
    errdefer engine.freeValue(pending.promise);
    authResult(&scope, pending.owner, arg(args, 0)) catch |err| try flow.rejectError(engine, pending.owner, err);
    return pending.promise;
}
fn authResult(scope: *Scope, pending: c.JSValue, credential: c.JSValue) !void {
    const object = try scope.object();
    try scope.put(object, "apiKey", try scope.get(credential, "access"));
    try flow.settle(scope.engine, pending, false, object);
}
fn stateOf(scope: *Scope, pending: c.JSValue) !c.JSValue {
    return scope.get(pending, "agent");
}
fn interactionSignal(scope: *Scope, state: c.JSValue) !c.JSValue {
    return scope.get(try scope.get(state, "interaction"), "signal");
}
fn failText(scope: *Scope, text: c.JSValue) anyerror {
    return v.errorText(scope, text);
}
fn reject(scope: *Scope, pending: c.JSValue, err: anyerror) !void {
    const original = try scope.own(flow.reason(scope.engine, err));
    const state = try stateOf(scope, pending);
    normalizeFailure(scope, pending, state, original) catch |failure| try flow.rejectError(scope.engine, pending, failure);
}
fn normalizeFailure(scope: *Scope, pending: c.JSValue, state: c.JSValue, original: c.JSValue) !void {
    if (scope.truthy(try v.optional(scope, state, "login")) and scope.truthy(try scope.get(try interactionSignal(scope, state), "aborted"))) {
        return flow.settle(scope.engine, pending, true, try scope.own(try v.js.builtin(scope.engine, "Error", &.{try scope.text("Login cancelled")})));
    }
    return flow.settle(scope.engine, pending, true, original);
}
fn requestSignal(scope: *Scope, signal: c.JSValue) !c.JSValue {
    // Preserve callee/getter evaluation before constructing the argument array.
    const constructor = try scope.global("AbortSignal");
    const any = try scope.get(constructor, "any");
    const signals = try scope.array();
    try scope.index(signals, 0, try scope.invoke(try scope.global("AbortSignal"), "timeout", &.{c.JS_NewInt32(scope.engine.context, 30000)}));
    try scope.index(signals, 1, signal);
    return scope.call(any, constructor, &.{signals});
}
fn form(scope: *Scope, entries: c.JSValue) !c.JSValue {
    const params = try scope.own(try v.js.builtin(scope.engine, "URLSearchParams", &.{entries}));
    return scope.invoke(params, "toString", &.{});
}
fn request(scope: *Scope, fetch: c.JSValue, url: []const u8, headers: c.JSValue, body: c.JSValue, signal: c.JSValue) !c.JSValue {
    const init = try scope.object();
    try scope.put(init, "method", try scope.text("POST"));
    try scope.put(init, "headers", headers);
    try scope.put(init, "body", body);
    try scope.put(init, "signal", try requestSignal(scope, signal));
    return scope.own(try http.requestJsonWithFetch(scope.engine, fetch, try scope.text(url), init));
}
fn formHeaders(scope: *Scope) !c.JSValue {
    const headers = try scope.object();
    try scope.put(headers, "Content-Type", try scope.text("application/x-www-form-urlencoded"));
    try scope.put(headers, "Accept", try scope.text("application/json"));
    return headers;
}
fn start(scope: *Scope, pending: c.JSValue) !void {
    const state = try stateOf(scope, pending);
    const signal = try scope.get(state, "signal");
    const fetch = try http.captureFetch(scope);
    const entries = try scope.object();
    try scope.put(entries, "client_id", try scope.text(client_id));
    try flow.wait(advance, scope.engine, pending, try request(scope, fetch, authorize_url, try formHeaders(scope), try form(scope, entries), signal), @intFromEnum(Stage.authorized));
}
fn authorize(engine: *v.em.Engine, signal: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const state = try scope.object();
    try scope.put(state, "signal", signal);
    const pending = try flow.create(engine, state);
    defer engine.freeValue(pending.owner);
    errdefer engine.freeValue(pending.promise);
    start(&scope, pending.owner) catch |err| try flow.rejectError(engine, pending.owner, err);
    return pending.promise;
}
fn startLogin(scope: *Scope, pending: c.JSValue) !void {
    const state = try stateOf(scope, pending);
    const promise = try scope.own(try authorize(scope.engine, try interactionSignal(scope, state)));
    try flow.wait(loginAuthorized, scope.engine, pending, promise, 0);
}
fn detail(scope: *Scope, json: c.JSValue) !c.JSValue {
    inline for (.{ "error_description", "detail", "message", "error" }) |key| {
        const value = try v.optional(scope, json, key);
        if (c.JS_IsString(value)) {
            const trimmed = try scope.invoke(value, "trim", &.{});
            if (scope.truthy(trimmed)) return scope.concat(try scope.text(": "), try scope.invoke(value, "trim", &.{}));
        }
    }
    return scope.text("");
}
fn trustedUrl(scope: *Scope, value: c.JSValue) !c.JSValue {
    if (!c.JS_IsString(value) or !scope.truthy(value)) return c.pi_js_null();
    return trustedUrlInner(scope, value) catch |err| {
        if (err != error.JavaScriptException) return err;
        return c.pi_js_null();
    };
}
fn trustedUrlInner(scope: *Scope, value: c.JSValue) !c.JSValue {
    const url = try scope.own(try v.js.builtin(scope.engine, "URL", &.{value}));
    if (!try v.eq(scope, try scope.get(url, "protocol"), "https:") and !try v.eq(scope, try scope.get(url, "protocol"), "http:")) return c.pi_js_null();
    return scope.get(url, "href");
}
fn positive(scope: *Scope, value: c.JSValue) !c.JSValue {
    if (!c.JS_IsNumber(value)) return c.pi_js_undefined();
    if (!scope.truthy(try scope.invoke(try scope.global("Number"), "isFinite", &.{value}))) return c.pi_js_undefined();
    return if (try scope.positive(value)) value else c.pi_js_undefined();
}
fn authorized(scope: *Scope, pending: c.JSValue, pair: c.JSValue) !void {
    const response = try scope.get(pair, "response");
    const json = try scope.get(pair, "json");
    if (!scope.truthy(try scope.get(response, "ok"))) return failText(scope, try scope.concat(try scope.concat(try scope.text("Meta device authorization failed with status "), try scope.get(response, "status")), try detail(scope, json)));
    const device_code = try v.optional(scope, json, "device_code");
    const user_code = try v.optional(scope, json, "user_code");
    var verification = try trustedUrl(scope, try v.optional(scope, json, "verification_uri_complete"));
    if (v.nullish(verification)) verification = try trustedUrl(scope, try v.optional(scope, json, "verification_uri"));
    if (!c.JS_IsString(device_code) or !scope.truthy(device_code) or !c.JS_IsString(user_code) or !scope.truthy(user_code) or !scope.truthy(verification)) {
        const serialized = try scope.own(try scope.engine.checked(c.JS_JSONStringify(scope.engine.context, json, c.pi_js_undefined(), c.pi_js_undefined())));
        return failText(scope, try scope.concat(try scope.text("Invalid Meta device authorization response: "), serialized));
    }
    const device = try scope.object();
    try scope.put(device, "deviceCode", device_code);
    try scope.put(device, "userCode", user_code);
    try scope.put(device, "verificationUri", verification);
    // Source sanitizes these only after the device-code/user-code/URI validation.
    try scope.put(device, "intervalSeconds", try positive(scope, try v.optional(scope, json, "interval")));
    try scope.put(device, "expiresInSeconds", try positive(scope, try v.optional(scope, json, "expires_in")));
    try flow.settle(scope.engine, pending, false, device);
}
fn loginAuthorized(engine: *v.em.Engine, pending: c.JSValue, value: c.JSValue, rejected: bool, _: c_int) !void {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    if (rejected) {
        const state = try stateOf(&scope, pending);
        normalizeFailure(&scope, pending, state, value) catch |err| try flow.rejectError(engine, pending, err);
        return;
    }
    announceDevice(&scope, pending, value) catch |err| try reject(&scope, pending, err);
}
fn announceDevice(scope: *Scope, pending: c.JSValue, device: c.JSValue) !void {
    const state = try stateOf(scope, pending);
    const interaction = try scope.get(state, "interaction");
    const notifier = try scope.get(interaction, "notify");
    const event = try scope.object();
    try scope.put(event, "type", try scope.text("device_code"));
    try scope.put(event, "userCode", try scope.get(device, "userCode"));
    try scope.put(event, "verificationUri", try scope.get(device, "verificationUri"));
    try scope.put(event, "intervalSeconds", try scope.get(device, "intervalSeconds"));
    try scope.put(event, "expiresInSeconds", try scope.get(device, "expiresInSeconds"));
    _ = try scope.call(notifier, interaction, &.{event});
    const identity = try scope.own(try identityToken(scope.engine, device, try interactionSignal(scope, state)));
    try flow.wait(afterIdentity, scope.engine, pending, identity, 0);
}
fn identityToken(engine: *v.em.Engine, device: c.JSValue, signal: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const state = try scope.object();
    try scope.put(state, "deviceCode", try scope.get(device, "deviceCode"));
    try scope.put(state, "pollSignal", signal);
    const pending = try flow.create(engine, state);
    defer engine.freeValue(pending.owner);
    errdefer engine.freeValue(pending.promise);
    startIdentity(&scope, pending.owner, state, device, signal) catch |err| try flow.rejectError(engine, pending.owner, err);
    return pending.promise;
}
fn startIdentity(scope: *Scope, pending: c.JSValue, state: c.JSValue, device: c.JSValue, signal: c.JSValue) !void {
    const options = try scope.object();
    try scope.put(options, "intervalSeconds", try scope.get(device, "intervalSeconds"));
    try scope.put(options, "expiresInSeconds", try scope.get(device, "expiresInSeconds"));
    try scope.put(options, "waitBeforeFirstPoll", c.pi_js_bool(scope.engine.context, 1));
    try scope.put(options, "signal", signal);
    try scope.put(options, "poll", try scope.own(try functions.createArrow(scope.engine, "poll", 0, pollOnce, &.{state})));
    // The async pollForIdentityToken function returns and adopts this promise.
    try flow.settle(scope.engine, pending, false, try scope.own(try device_flow.poll(scope.engine, options)));
}
fn pollOnce(engine: *v.em.Engine, _: c.JSValue, _: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const pending = try flow.create(engine, roots[0]);
    defer engine.freeValue(pending.owner);
    errdefer engine.freeValue(pending.promise);
    pollRequest(&scope, pending.owner, roots[0]) catch |err| try flow.rejectError(engine, pending.owner, err);
    return pending.promise;
}
fn pollRequest(scope: *Scope, pending: c.JSValue, state: c.JSValue) !void {
    const fetch = try http.captureFetch(scope);
    const entries = try scope.object();
    try scope.put(entries, "grant_type", try scope.text("urn:ietf:params:oauth:grant-type:device_code"));
    try scope.put(entries, "device_code", try scope.get(state, "deviceCode"));
    try scope.put(entries, "client_id", try scope.text(client_id));
    try flow.wait(pollReply, scope.engine, pending, try request(scope, fetch, token_url, try formHeaders(scope), try form(scope, entries), try scope.get(state, "pollSignal")), 0);
}
fn pollReply(engine: *v.em.Engine, pending: c.JSValue, value: c.JSValue, rejected: bool, _: c_int) !void {
    if (rejected) return flow.settle(engine, pending, true, value);
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    polled(&scope, pending, value) catch |err| try flow.rejectError(engine, pending, err);
}
fn polled(scope: *Scope, pending: c.JSValue, pair: c.JSValue) !void {
    const response = try scope.get(pair, "response");
    const json = try scope.get(pair, "json");
    const result = try scope.object();
    if (scope.truthy(try scope.get(response, "ok")) and c.JS_IsString(try v.optional(scope, json, "access_token")) and scope.truthy(try scope.get(json, "access_token"))) {
        try scope.put(result, "status", try scope.text("complete"));
        try scope.put(result, "value", try scope.get(json, "access_token"));
    } else {
        const error_code = try v.optional(scope, json, "error");
        if (try v.eq(scope, error_code, "authorization_pending")) {
            try scope.put(result, "status", try scope.text("pending"));
        } else if (try v.eq(scope, error_code, "slow_down")) {
            try scope.put(result, "status", try scope.text("slow_down"));
            try scope.put(result, "intervalSeconds", try positive(scope, try v.optional(scope, json, "interval")));
        } else {
            try scope.put(result, "status", try scope.text("failed"));
            const message = if (try v.eq(scope, error_code, "access_denied"))
                try scope.text("Meta login was denied.")
            else if (try v.eq(scope, error_code, "expired_token"))
                try scope.text("Meta device authorization expired. Please restart login.")
            else
                try scope.concat(try scope.concat(try scope.text("Meta device token request failed with status "), try scope.get(response, "status")), try detail(scope, json));
            try scope.put(result, "message", message);
        }
    }
    try flow.settle(scope.engine, pending, false, result);
}
fn afterIdentity(engine: *v.em.Engine, pending: c.JSValue, value: c.JSValue, rejected: bool, _: c_int) !void {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    if (rejected) {
        const state = try stateOf(&scope, pending);
        normalizeFailure(&scope, pending, state, value) catch |err| try flow.rejectError(engine, pending, err);
        return;
    }
    enable(&scope, pending, value) catch |err| try reject(&scope, pending, err);
}
fn enable(scope: *Scope, pending: c.JSValue, identity: c.JSValue) !void {
    const state = try stateOf(scope, pending);
    const interaction = try scope.get(state, "interaction");
    const notifier = try scope.get(interaction, "notify");
    const event = try scope.object();
    try scope.put(event, "type", try scope.text("progress"));
    try scope.put(event, "message", try scope.text("Enabling Meta Model API access..."));
    _ = try scope.call(notifier, interaction, &.{event});
    const promise = try scope.own(try mintCredential(scope.engine, identity, try interactionSignal(scope, state)));
    try flow.wait(loginMinted, scope.engine, pending, promise, 0);
}
fn loginMinted(engine: *v.em.Engine, pending: c.JSValue, value: c.JSValue, rejected: bool, _: c_int) !void {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    if (rejected) {
        const state = try stateOf(&scope, pending);
        normalizeFailure(&scope, pending, state, value) catch |err| try flow.rejectError(engine, pending, err);
    } else try flow.settle(engine, pending, false, value);
}
fn mint(scope: *Scope, pending: c.JSValue, signal: c.JSValue) !void {
    const state = try stateOf(scope, pending);
    const fetch = try http.captureFetch(scope);
    const headers = try scope.object();
    try scope.put(headers, "Accept", try scope.text("application/json"));
    try scope.put(headers, "Authorization", try scope.concat(try scope.text("Bearer "), try scope.stringify(try scope.get(state, "identity"))));
    try scope.put(headers, "Content-Type", try scope.text("application/json"));
    try scope.put(headers, "x-api-version", try scope.text("1.0.0"));
    try flow.wait(advance, scope.engine, pending, try request(scope, fetch, mint_url, headers, try scope.text("{}"), signal), @intFromEnum(Stage.minted));
}
fn minted(scope: *Scope, pending: c.JSValue, pair: c.JSValue) !void {
    const response = try scope.get(pair, "response");
    const json = try scope.get(pair, "json");
    const status = try scope.get(response, "status");
    if (scope.equal(status, c.JS_NewInt32(scope.engine.context, 401)) or scope.equal(try scope.get(response, "status"), c.JS_NewInt32(scope.engine.context, 403))) {
        return failText(scope, try scope.concat(try scope.concat(try scope.concat(try scope.text("Meta session expired (status "), try scope.get(response, "status")), try scope.text("). Run `/login meta` to sign in again.")), try detail(scope, json)));
    }
    if (!scope.truthy(try scope.get(response, "ok"))) return failText(scope, try scope.concat(try scope.concat(try scope.text("Meta API key mint failed with status "), try scope.get(response, "status")), try detail(scope, json)));
    const api_key = try v.optional(scope, json, "api_key");
    if (!c.JS_IsString(api_key) or !scope.truthy(api_key)) {
        const action_url = try trustedUrl(scope, try v.optional(scope, json, "action_url"));
        return failText(scope, if (scope.truthy(action_url)) try scope.concat(try scope.text("Meta did not issue an API key. Complete setup at "), action_url) else try scope.text("Meta did not issue an API key."));
    }
    const credential = try scope.object();
    try scope.put(credential, "type", try scope.text("oauth"));
    try scope.put(credential, "refresh", try scope.get(try stateOf(scope, pending), "identity"));
    try scope.put(credential, "access", api_key);
    try scope.put(credential, "expires", try scope.own(try @import("native_image_arithmetic.zig").binary(scope.engine, .add, try scope.invoke(try scope.global("Date"), "now", &.{}), c.JS_NewInt32(scope.engine.context, 86400000))));
    try flow.settle(scope.engine, pending, false, credential);
}
fn advance(engine: *v.em.Engine, pending: c.JSValue, value: c.JSValue, rejected: bool, stage: c_int) !void {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    if (rejected) {
        const state = try stateOf(&scope, pending);
        normalizeFailure(&scope, pending, state, value) catch |err| try flow.rejectError(engine, pending, err);
        return;
    }
    advanceValue(&scope, pending, value, @enumFromInt(stage)) catch |err| try reject(&scope, pending, err);
}
fn advanceValue(scope: *Scope, pending: c.JSValue, value: c.JSValue, stage: Stage) !void {
    switch (stage) {
        .authorized => try authorized(scope, pending, value),
        .minted => try minted(scope, pending, value),
    }
}
