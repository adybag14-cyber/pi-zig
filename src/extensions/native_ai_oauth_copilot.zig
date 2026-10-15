//! GitHub Copilot's actual public device/token/catalog/policy OAuth bodies.
//! All rich values and observable coercions remain in the owner QuickJS realm.
const h = @import("native_ai_oauth_subscription_values.zig");
const v = h.v;
const Scope = h.Scope;
const c = h.c;
const flow = h.flow;
const protocol = @import("../auth/github_copilot_oauth.zig");
const arithmetic = @import("native_image_arithmetic.zig");
const Stage = enum(c_int) { prompt, response, json, text, polled, cancel, sleep };
pub fn create(engine: *v.em.Engine) !c.JSValue {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    const catalog = try s.own(try @import("native_ai_catalog_values.zig").providerChatCatalog(engine, try s.text("github-copilot")));
    return createWithCatalog(engine, catalog);
}
/// Central assembly supplies its one actual provider catalog object. It remains
/// live and borrowed here, and is marked through the facade's callback roots.
pub fn createWithCatalog(engine: *v.em.Engine, catalog: c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    const result = try s.object();
    const lexical = try s.object();
    try s.put(lexical, "catalog", catalog);
    try s.put(result, "name", try s.text("GitHub Copilot"));
    try s.put(result, "isSubscription", c.pi_js_bool(engine.context, 1));
    try s.put(result, "login", try s.own(try h.helpers.asyncArrow(engine, "loginGitHubCopilot", 1, login, &.{lexical})));
    try s.put(result, "refresh", try s.own(try h.functions.createArrow(engine, "refresh", 2, refresh, &.{lexical})));
    try s.put(result, "toAuth", try s.own(try h.helpers.asyncArrow(engine, "toAuth", 1, toAuth, &.{})));
    return c.JS_DupValue(engine.context, result);
}
fn normalize(s: *Scope, input: c.JSValue) !c.JSValue {
    const trimmed = try s.invoke(input, "trim", &.{});
    if (!s.truthy(trimmed)) return c.pi_js_null();
    const generation = s.engine.native_allocation_generation;
    const value = normalizeInner(s, trimmed) catch |err| {
        try @import("native_ai_partial_json.zig").discard(s.engine, err, generation);
        return c.pi_js_null();
    };
    return value;
}
fn normalizeInner(s: *Scope, trimmed: c.JSValue) !c.JSValue {
    const raw = if (s.truthy(try s.invoke(trimmed, "includes", &.{try s.text("://")}))) trimmed else try s.concat(try s.text("https://"), trimmed);
    return s.get(try s.own(try v.js.builtin(s.engine, "URL", &.{raw})), "hostname");
}
fn enterprise(s: *Scope, credential: c.JSValue) !c.JSValue {
    const value = try s.get(credential, "enterpriseUrl");
    if (!c.JS_IsString(value) or !s.truthy(value)) return c.pi_js_undefined();
    const domain = try normalize(s, value);
    return if (v.nullish(domain)) c.pi_js_undefined() else domain;
}
fn baseUrl(s: *Scope, token: c.JSValue, domain: c.JSValue) !c.JSValue {
    if (s.truthy(token)) {
        const regex = try s.own(try v.js.builtin(s.engine, "RegExp", &.{try s.text("proxy-ep=([^;]+)")}));
        const match = try s.invoke(token, "match", &.{regex});
        if (s.truthy(match)) {
            const host = try v.at(s, match, 1);
            const prefix = try s.own(try v.js.builtin(s.engine, "RegExp", &.{try s.text("^proxy\\.")}));
            return s.concat(try s.text("https://"), try s.invoke(host, "replace", &.{ prefix, try s.text("api.") }));
        }
    }
    if (s.truthy(domain)) return s.concat(try s.text("https://copilot-api."), try s.stringify(domain));
    return s.text("https://api.individual.githubcopilot.com");
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
    const token = try s.get(credential, "access");
    const domain = try enterprise(s, credential);
    try s.put(result, "baseUrl", try baseUrl(s, token, domain));
    return result;
}
fn login(engine: *v.em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    const p = try flow.create(engine, roots[0]);
    defer engine.freeValue(p.owner);
    errdefer engine.freeValue(p.promise);
    startLogin(&s, p.owner, h.arg(args, 0)) catch |err| try flow.rejectError(engine, p.owner, err);
    return p.promise;
}
fn startLogin(s: *Scope, owner: c.JSValue, interaction: c.JSValue) !void {
    try s.put(owner, "interaction", interaction);
    try s.put(owner, "login", c.pi_js_bool(s.engine.context, 1));
    const method = try s.get(interaction, "prompt");
    const input = try s.object();
    try s.put(input, "type", try s.text("text"));
    try s.put(input, "message", try s.text("GitHub Enterprise URL/domain (blank for github.com)"));
    try s.put(input, "placeholder", try s.text("company.ghe.com"));
    return wait(s, owner, try s.call(method, interaction, &.{input}), .prompt);
}
fn refresh(engine: *v.em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    const credential = h.arg(args, 0);
    const token = try s.get(credential, "refresh");
    const domain = try enterprise(&s, credential);
    const p = try flow.create(engine, roots[0]);
    defer engine.freeValue(p.owner);
    errdefer engine.freeValue(p.promise);
    startRefresh(&s, p.owner, token, domain, h.arg(args, 1)) catch |err| try flow.rejectError(engine, p.owner, err);
    return p.promise;
}
fn startRefresh(s: *Scope, owner: c.JSValue, token: c.JSValue, domain: c.JSValue, signal: c.JSValue) !void {
    try s.put(owner, "login", c.pi_js_bool(s.engine.context, 0));
    try s.put(owner, "domain", domain);
    try s.put(owner, "signal", signal);
    try s.put(owner, "refresh", token);
    return tokenRequest(s, owner);
}
fn url(s: *Scope, domain: c.JSValue, prefix: []const u8, path: []const u8) !c.JSValue {
    return s.concat(try s.concat(try s.text(prefix), try s.stringify(if (s.truthy(domain)) domain else try s.text("github.com"))), try s.text(path));
}
fn headers(s: *Scope, auth: ?c.JSValue, device_headers: bool) !c.JSValue {
    const result = try s.object();
    try s.put(result, "Accept", try s.text("application/json"));
    if (auth) |token| try s.put(result, "Authorization", try s.concat(try s.text("Bearer "), try s.stringify(token)));
    if (device_headers) try s.put(result, "Content-Type", try s.text("application/x-www-form-urlencoded"));
    try s.put(result, "User-Agent", try s.text(protocol.USER_AGENT));
    if (!device_headers) {
        try s.put(result, "Editor-Version", try s.text(protocol.EDITOR_VERSION));
        try s.put(result, "Editor-Plugin-Version", try s.text(protocol.EDITOR_PLUGIN_VERSION));
        try s.put(result, "Copilot-Integration-Id", try s.text(protocol.INTEGRATION_ID));
    }
    return result;
}
fn deviceRequest(s: *Scope, owner: c.JSValue, polling: bool) !void {
    try s.put(owner, "mode", try s.text(if (polling) "poll" else "device"));
    const fetch = try h.http.captureFetch(s);
    const address = try url(s, try s.get(owner, "domain"), "https://", if (polling) "/login/oauth/access_token" else "/login/device/code");
    const init = try s.object();
    try s.put(init, "method", try s.text("POST"));
    try s.put(init, "headers", try headers(s, null, true));
    const fields = try s.object();
    try s.put(fields, "client_id", try s.text(protocol.CLIENT_ID));
    if (polling) {
        try s.put(fields, "device_code", try s.get(try s.get(owner, "device"), "device_code"));
        try s.put(fields, "grant_type", try s.text("urn:ietf:params:oauth:grant-type:device_code"));
    } else try s.put(fields, "scope", try s.text("read:user"));
    try s.put(init, "body", try h.form(s, fields, false));
    try s.put(init, "signal", try s.get(owner, "signal"));
    return fetchDirect(s, owner, fetch, address, init);
}
fn tokenRequest(s: *Scope, owner: c.JSValue) !void {
    try s.put(owner, "mode", try s.text("token"));
    const fetch = try h.http.captureFetch(s);
    const address = try url(s, try s.get(owner, "domain"), "https://api.", "/copilot_internal/v2/token");
    const init = try s.object();
    try s.put(init, "headers", try headers(s, try s.get(owner, "refresh"), false));
    try s.put(init, "signal", try s.get(owner, "signal"));
    return fetchDirect(s, owner, fetch, address, init);
}
fn fetchDirect(s: *Scope, owner: c.JSValue, fetch: c.JSValue, address: c.JSValue, init: c.JSValue) !void {
    try s.put(owner, "rate", c.pi_js_bool(s.engine.context, 0));
    return wait(s, owner, try s.own(try h.http.requestWithFetch(s.engine, fetch, address, init)), .response);
}
fn modelsRequest(s: *Scope, owner: c.JSValue) !void {
    try s.put(owner, "mode", try s.text("models"));
    const credential = try s.get(owner, "credential");
    const token = try s.get(credential, "access");
    const base = try baseUrl(s, token, try s.get(owner, "domain"));
    try s.put(owner, "base", base);
    const init = try s.object();
    const fields = try headers(s, token, false);
    try s.put(fields, "X-GitHub-Api-Version", try s.text(protocol.COPILOT_API_VERSION));
    try s.put(init, "headers", fields);
    return rateStart(s, owner, try s.concat(base, try s.text("/models")), init, if (s.truthy(try s.get(owner, "login"))) 2 else 0);
}
fn rateStart(s: *Scope, owner: c.JSValue, address: c.JSValue, init: c.JSValue, maximum: i32) !void {
    try s.put(owner, "rate", c.pi_js_bool(s.engine.context, 1));
    try s.put(owner, "url", address);
    try s.put(owner, "init", init);
    try s.put(owner, "retry", c.JS_NewInt32(s.engine.context, 0));
    try s.put(owner, "maximum", c.JS_NewInt32(s.engine.context, maximum));
    const signal = try s.get(owner, "signal");
    var request_signal = signal;
    var deadline = c.pi_js_undefined();
    if (maximum > 0) {
        const abort = try s.global("AbortSignal");
        const budget = try s.invoke(abort, "timeout", &.{c.JS_NewInt32(s.engine.context, 5000)});
        const signals = try s.array();
        try s.index(signals, 0, signal);
        try s.index(signals, 1, budget);
        request_signal = try s.invoke(abort, "any", &.{signals});
        deadline = try h.binary(s, .add, try h.now(s), c.JS_NewInt32(s.engine.context, 5000));
    }
    try s.put(owner, "requestSignal", request_signal);
    try s.put(owner, "deadline", deadline);
    return rateAttempt(s, owner);
}
fn rateAttempt(s: *Scope, owner: c.JSValue) !void {
    const fetch = try h.http.captureFetch(s);
    const address = try s.get(owner, "url");
    const init = try v.spread(s, try s.get(owner, "init"));
    const abort = try s.global("AbortSignal");
    const signals = try s.array();
    try s.index(signals, 0, try s.get(owner, "requestSignal"));
    try s.index(signals, 1, try s.invoke(abort, "timeout", &.{c.JS_NewInt32(s.engine.context, 5000)}));
    try s.put(init, "signal", try s.invoke(abort, "any", &.{signals}));
    const generation = s.engine.native_allocation_generation;
    const returned = h.http.requestWithFetch(s.engine, fetch, address, init) catch |err| {
        if (try v.eq(s, try s.get(owner, "mode"), "policy") and !s.truthy(try s.get(try s.get(owner, "signal"), "aborted"))) {
            try @import("native_ai_partial_json.zig").discard(s.engine, err, generation);
            return nextPolicy(s, owner, false);
        }
        return err;
    };
    return wait(s, owner, try s.own(returned), .response);
}
fn wait(s: *Scope, owner: c.JSValue, value: c.JSValue, stage: Stage) !void {
    return flow.wait(continued, s.engine, owner, value, @intFromEnum(stage));
}
fn continued(engine: *v.em.Engine, owner: c.JSValue, value: c.JSValue, rejected: bool, raw: c_int) !void {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    const stage: Stage = @enumFromInt(raw);
    if (rejected) {
        if ((stage == .response or stage == .cancel or stage == .sleep) and try v.eq(&s, try s.get(owner, "mode"), "policy") and !s.truthy(try s.get(try s.get(owner, "signal"), "aborted"))) {
            nextPolicy(&s, owner, false) catch |err| try flow.rejectError(engine, owner, err);
            return;
        }
        return flow.settle(engine, owner, true, value);
    }
    advance(&s, owner, value, stage) catch |err| {
        if (try v.eq(&s, try s.get(owner, "mode"), "policy") and !s.truthy(try s.get(try s.get(owner, "signal"), "aborted"))) {
            const generation = engine.native_allocation_generation;
            try @import("native_ai_partial_json.zig").discard(engine, err, generation);
            return finalCredential(&s, owner);
        }
        try flow.rejectError(engine, owner, err);
    };
}
fn responseReady(s: *Scope, owner: c.JSValue, response: c.JSValue) !void {
    try s.put(owner, "response", response);
    if (s.truthy(try s.get(owner, "rate")) and s.equal(try s.get(response, "status"), c.JS_NewInt32(s.engine.context, 429)) and !s.equal(try s.get(owner, "retry"), try s.get(owner, "maximum"))) {
        const after = try s.invoke(try s.get(response, "headers"), "get", &.{try s.text("retry-after")});
        var delay = try h.binary(s, .multiply, c.JS_NewInt32(s.engine.context, 500), try h.binary(s, .power, c.JS_NewInt32(s.engine.context, 2), try s.get(owner, "retry")));
        if (s.truthy(after)) {
            const seconds = try s.invoke(try s.global("Number"), "parseFloat", &.{after});
            delay = if (s.truthy(try s.invoke(try s.global("Number"), "isNaN", &.{seconds}))) try h.binary(s, .subtract, try s.invoke(try s.global("Date"), "parse", &.{after}), try h.now(s)) else try h.binary(s, .multiply, seconds, c.JS_NewInt32(s.engine.context, 1000));
            if (!s.truthy(try s.invoke(try s.global("Number"), "isFinite", &.{delay}))) return consume(s, owner, response);
        }
        delay = try s.invoke(try s.global("Math"), "max", &.{ c.JS_NewInt32(s.engine.context, 0), delay });
        const deadline = try s.get(owner, "deadline");
        if (!c.JS_IsUndefined(deadline) and try arithmetic.compare(s.engine, .greater_equal, delay, try h.binary(s, .subtract, deadline, try h.now(s)))) return consume(s, owner, response);
        try s.put(owner, "delay", delay);
        const body = try s.get(response, "body");
        return wait(s, owner, if (v.nullish(body)) c.pi_js_undefined() else try s.invoke(body, "cancel", &.{}), .cancel);
    }
    return consume(s, owner, response);
}
fn consume(s: *Scope, owner: c.JSValue, response: c.JSValue) !void {
    if (try v.eq(s, try s.get(owner, "mode"), "policy")) {
        if (s.equal(try s.get(response, "status"), c.JS_NewInt32(s.engine.context, 429))) return wait(s, owner, try s.invoke(response, "text", &.{}), .text);
        return nextPolicy(s, owner, s.truthy(try s.get(response, "ok")));
    }
    if (!s.truthy(try s.get(response, "ok"))) return wait(s, owner, try s.invoke(response, "text", &.{}), .text);
    return wait(s, owner, try s.invoke(response, "json", &.{}), .json);
}
fn advance(s: *Scope, owner: c.JSValue, value: c.JSValue, stage: Stage) !void {
    switch (stage) {
        .prompt => {
            const interaction = try s.get(owner, "interaction");
            if (s.truthy(try s.get(try s.get(interaction, "signal"), "aborted"))) return v.errorText(s, try s.text("Login cancelled"));
            const trimmed = try s.invoke(value, "trim", &.{});
            const domain = try normalize(s, value);
            if (s.truthy(trimmed) and !s.truthy(domain)) return v.errorText(s, try s.text("Invalid GitHub Enterprise URL/domain"));
            try s.put(owner, "domain", if (v.nullish(domain)) c.pi_js_undefined() else domain);
            try s.put(owner, "signal", try s.get(interaction, "signal"));
            return deviceRequest(s, owner, false);
        },
        .response => return responseReady(s, owner, value),
        .cancel => return wait(s, owner, try s.own(try h.sleep(s.engine, try s.get(owner, "delay"), try s.get(owner, "requestSignal"))), .sleep),
        .sleep => {
            try s.put(owner, "retry", try h.binary(s, .add, try s.get(owner, "retry"), c.JS_NewInt32(s.engine.context, 1)));
            return rateAttempt(s, owner);
        },
        .text => {
            const response = try s.get(owner, "response");
            var message = try s.concat(try s.concat(try s.stringify(try s.get(response, "status")), try s.text(" ")), try s.stringify(try s.get(response, "statusText")));
            message = try s.concat(try s.concat(message, try s.text(": ")), try s.stringify(value));
            return v.errorText(s, message);
        },
        .polled => {
            try s.put(owner, "refresh", value);
            try s.put(owner, "signal", try s.get(try s.get(owner, "interaction"), "signal"));
            return tokenRequest(s, owner);
        },
        .json => return afterJson(s, owner, value),
    }
}
fn afterJson(s: *Scope, owner: c.JSValue, raw: c.JSValue) !void {
    const mode = try s.get(owner, "mode");
    if (try v.eq(s, mode, "device")) {
        if (!h.record(s, raw)) return v.errorText(s, try s.text("Invalid device code response"));
        const code = try s.get(raw, "device_code");
        const user = try s.get(raw, "user_code");
        const verification = try s.get(raw, "verification_uri");
        const interval = try s.get(raw, "interval");
        const expires = try s.get(raw, "expires_in");
        if (!c.JS_IsString(code) or !c.JS_IsString(user) or !c.JS_IsString(verification) or (!c.JS_IsUndefined(interval) and !c.JS_IsNumber(interval)) or !c.JS_IsNumber(expires)) return v.errorText(s, try s.text("Invalid device code response fields"));
        const uri = try h.trusted(s, verification, false, "Untrusted verification_uri in device code response");
        const device = try s.object();
        try s.put(device, "device_code", code);
        try s.put(device, "user_code", user);
        try s.put(device, "verification_uri", uri);
        try s.put(device, "interval", interval);
        try s.put(device, "expires_in", expires);
        try s.put(owner, "device", device);
        const interaction = try s.get(owner, "interaction");
        const notify = try s.get(interaction, "notify");
        const notification = try s.object();
        try s.put(notification, "type", try s.text("device_code"));
        try s.put(notification, "userCode", user);
        try s.put(notification, "verificationUri", uri);
        try s.put(notification, "intervalSeconds", interval);
        try s.put(notification, "expiresInSeconds", expires);
        _ = try s.call(notify, interaction, &.{notification});
        try s.put(owner, "signal", try s.get(interaction, "signal"));
        const options = try s.object();
        try s.put(options, "intervalSeconds", interval);
        try s.put(options, "expiresInSeconds", expires);
        try s.put(options, "waitBeforeFirstPoll", c.pi_js_bool(s.engine.context, 1));
        try s.put(options, "signal", try s.get(owner, "signal"));
        try s.put(options, "poll", try s.own(try h.helpers.asyncArrow(s.engine, "poll", 0, poll, &.{owner})));
        return wait(s, owner, try s.own(try h.device.poll(s.engine, options)), .polled);
    }
    if (try v.eq(s, mode, "poll")) {
        if (h.record(s, raw) and c.JS_IsString(try s.get(raw, "access_token"))) return flow.settle(s.engine, owner, false, try h.pollResult(s, "complete", "value", try s.get(raw, "access_token")));
        if (h.record(s, raw) and c.JS_IsString(try s.get(raw, "error"))) {
            const err = try s.get(raw, "error");
            const description = try s.get(raw, "error_description");
            const interval = try s.get(raw, "interval");
            if (try v.eq(s, err, "authorization_pending")) return flow.settle(s.engine, owner, false, try h.pollResult(s, "pending", null, c.pi_js_undefined()));
            if (try v.eq(s, err, "slow_down")) return flow.settle(s.engine, owner, false, try h.pollResult(s, "slow_down", "intervalSeconds", if (c.JS_IsNumber(interval)) interval else c.pi_js_undefined()));
            var message = try s.concat(try s.text("Device flow failed: "), try s.stringify(err));
            if (s.truthy(description)) message = try s.concat(try s.concat(message, try s.text(": ")), try s.stringify(description));
            return flow.settle(s.engine, owner, false, try h.pollResult(s, "failed", "message", message));
        }
        return flow.settle(s.engine, owner, false, try h.pollResult(s, "failed", "message", try s.text("Invalid device token response")));
    }
    if (try v.eq(s, mode, "token")) {
        if (!h.record(s, raw)) return v.errorText(s, try s.text("Invalid Copilot token response"));
        const token = try s.get(raw, "token");
        const expires = try s.get(raw, "expires_at");
        if (!c.JS_IsString(token) or !c.JS_IsNumber(expires)) return v.errorText(s, try s.text("Invalid Copilot token response fields"));
        const credential = try s.object();
        try s.put(credential, "type", try s.text("oauth"));
        try s.put(credential, "refresh", try s.get(owner, "refresh"));
        try s.put(credential, "access", token);
        try s.put(credential, "expires", try h.binary(s, .subtract, try h.binary(s, .multiply, expires, c.JS_NewInt32(s.engine.context, 1000)), c.JS_NewInt32(s.engine.context, 300000)));
        try s.put(credential, "enterpriseUrl", try s.get(owner, "domain"));
        try s.put(owner, "credential", credential);
        if (s.truthy(try s.get(owner, "login"))) try s.put(owner, "signal", try s.get(try s.get(owner, "interaction"), "signal"));
        return modelsRequest(s, owner);
    }
    return afterModels(s, owner, raw);
}
fn asRecord(s: *Scope, value: c.JSValue) c.JSValue {
    return if (h.record(s, value)) value else c.pi_js_undefined();
}
fn accountRow(engine: *v.em.Engine, _: c.JSValue, args: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    const result = try s.array();
    const item = asRecord(&s, h.arg(args, 0));
    const id = try v.optional(&s, item, "id");
    if (c.JS_IsUndefined(item) or !c.JS_IsString(id)) return c.JS_DupValue(engine.context, result);
    const capabilities = asRecord(&s, try s.get(item, "capabilities"));
    const supports = asRecord(&s, try v.optional(&s, capabilities, "supports"));
    if (s.equal(try v.optional(&s, supports, "tool_calls"), c.pi_js_bool(engine.context, 0))) return c.JS_DupValue(engine.context, result);
    const row = try s.object();
    try s.put(row, "id", id);
    try s.put(row, "pickerEnabled", c.pi_js_bool(engine.context, @intFromBool(s.equal(try s.get(item, "model_picker_enabled"), c.pi_js_bool(engine.context, 1)))));
    try s.put(row, "policyState", try v.optional(&s, asRecord(&s, try s.get(item, "policy")), "state"));
    try s.index(result, 0, row);
    return c.JS_DupValue(engine.context, result);
}
fn idRow(engine: *v.em.Engine, _: c.JSValue, args: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
    return v.js.get(engine, h.arg(args, 0), "id");
}
fn pickerRow(engine: *v.em.Engine, _: c.JSValue, args: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    const item = h.arg(args, 0);
    return c.pi_js_bool(engine.context, @intFromBool(s.truthy(try s.get(item, "pickerEnabled")) and !try v.eq(&s, try s.get(item, "policyState"), "disabled")));
}
fn enabledRow(engine: *v.em.Engine, _: c.JSValue, args: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    return c.pi_js_bool(engine.context, @intFromBool(try v.eq(&s, try s.get(h.arg(args, 0), "policyState"), "enabled")));
}
fn policyRow(engine: *v.em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    const item = h.arg(args, 0);
    return c.pi_js_bool(engine.context, @intFromBool(try v.eq(&s, try s.get(item, "policyState"), "unconfigured") and s.truthy(try s.invoke(try s.global("Object"), "hasOwn", &.{ roots[0], try s.get(item, "id") })) and (s.truthy(try s.get(item, "pickerEnabled")) or s.truthy(roots[1]))));
}
fn afterModels(s: *Scope, owner: c.JSValue, raw: c.JSValue) !void {
    const data = try v.optional(s, asRecord(s, raw), "data");
    if (!try v.array(s, data)) return v.errorText(s, try s.text("Invalid Copilot models response"));
    const accounts = try s.invoke(data, "flatMap", &.{try s.own(try h.functions.createArrow(s.engine, "", 1, accountRow, &.{}))});
    const picker_rows = try s.invoke(accounts, "filter", &.{try s.own(try h.functions.createArrow(s.engine, "", 1, pickerRow, &.{}))});
    const picker = try s.invoke(picker_rows, "map", &.{try s.own(try h.functions.createArrow(s.engine, "", 1, idRow, &.{}))});
    const fallback = try v.eq(s, try s.get(owner, "base"), "https://api.individual.githubcopilot.com") and try v.length(s, picker) == 0;
    const available = if (fallback) try s.invoke(try s.invoke(accounts, "filter", &.{try s.own(try h.functions.createArrow(s.engine, "", 1, enabledRow, &.{}))}), "map", &.{try s.own(try h.functions.createArrow(s.engine, "", 1, idRow, &.{}))}) else picker;
    const catalog = try s.get(try s.get(owner, "agent"), "catalog");
    const policy_rows = try s.invoke(accounts, "filter", &.{try s.own(try h.functions.createArrow(s.engine, "", 1, policyRow, &.{ catalog, c.pi_js_bool(s.engine.context, @intFromBool(fallback)) }))});
    const policies = try s.invoke(policy_rows, "map", &.{try s.own(try h.functions.createArrow(s.engine, "", 1, idRow, &.{}))});
    try s.put(owner, "available", available);
    try s.put(owner, "policies", policies);
    try s.put(owner, "enabled", try s.array());
    try s.put(owner, "policyIndex", c.JS_NewInt32(s.engine.context, 0));
    if (!s.truthy(try s.get(owner, "login")) or try v.length(s, policies) == 0) return finalCredential(s, owner);
    const interaction = try s.get(owner, "interaction");
    const notify = try s.get(interaction, "notify");
    const notification = try s.object();
    try s.put(notification, "type", try s.text("progress"));
    try s.put(notification, "message", try s.text("Enabling models..."));
    _ = try s.call(notify, interaction, &.{notification});
    try s.put(owner, "signal", try s.get(interaction, "signal"));
    return policyRequest(s, owner);
}
fn policyRequest(s: *Scope, owner: c.JSValue) !void {
    try s.put(owner, "mode", try s.text("policy"));
    const token = try s.get(try s.get(owner, "credential"), "access");
    const base = try baseUrl(s, token, try s.get(owner, "domain"));
    const model = try s.own(try v.js.getKey(s.engine, try s.get(owner, "policies"), try s.get(owner, "policyIndex")));
    try s.put(owner, "policyModel", model);
    const address = try s.concat(try s.concat(try s.concat(base, try s.text("/models/")), try s.stringify(model)), try s.text("/policy"));
    const init = try s.object();
    try s.put(init, "method", try s.text("POST"));
    const fields = try s.object();
    try s.put(fields, "Content-Type", try s.text("application/json"));
    try s.put(fields, "Authorization", try s.concat(try s.text("Bearer "), try s.stringify(token)));
    try s.put(fields, "User-Agent", try s.text(protocol.USER_AGENT));
    try s.put(fields, "Editor-Version", try s.text(protocol.EDITOR_VERSION));
    try s.put(fields, "Editor-Plugin-Version", try s.text(protocol.EDITOR_PLUGIN_VERSION));
    try s.put(fields, "Copilot-Integration-Id", try s.text(protocol.INTEGRATION_ID));
    try s.put(fields, "openai-intent", try s.text("chat-policy"));
    try s.put(fields, "x-interaction-type", try s.text("chat-policy"));
    try s.put(init, "headers", fields);
    const state = try s.object();
    try s.put(state, "state", try s.text("enabled"));
    try s.put(init, "body", try h.json(s, state));
    return rateStart(s, owner, address, init, 2);
}
fn nextPolicy(s: *Scope, owner: c.JSValue, enabled: bool) !void {
    if (enabled) _ = try s.invoke(try s.get(owner, "enabled"), "push", &.{try s.get(owner, "policyModel")});
    const index = try h.binary(s, .add, try s.get(owner, "policyIndex"), c.JS_NewInt32(s.engine.context, 1));
    try s.put(owner, "policyIndex", index);
    if (try arithmetic.compare(s.engine, .less, index, try s.get(try s.get(owner, "policies"), "length"))) return policyRequest(s, owner);
    return finalCredential(s, owner);
}
fn finalCredential(s: *Scope, owner: c.JSValue) !void {
    const result = try v.spread(s, try s.get(owner, "credential"));
    var available = try s.get(owner, "available");
    if (s.truthy(try s.get(owner, "login"))) {
        const combined = try s.array();
        inline for (.{ "available", "enabled" }) |key| {
            var iterator = try v.iterator(s, try s.get(owner, key));
            defer iterator.deinit();
            errdefer iterator.closePreserving();
            while (try iterator.next()) |value| {
                defer s.engine.freeValue(value);
                _ = try s.invoke(combined, "push", &.{value});
            }
        }
        const set = try s.own(try v.js.builtin(s.engine, "Set", &.{combined}));
        available = try s.array();
        var iterator = try v.iterator(s, set);
        defer iterator.deinit();
        errdefer iterator.closePreserving();
        while (try iterator.next()) |value| {
            defer s.engine.freeValue(value);
            _ = try s.invoke(available, "push", &.{value});
        }
    }
    try s.put(result, "availableModelIds", available);
    return flow.settle(s.engine, owner, false, result);
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
    try s.put(owner, "domain", try s.get(parent, "domain"));
    try s.put(owner, "device", try s.get(parent, "device"));
    try s.put(owner, "signal", try s.get(parent, "signal"));
    return deviceRequest(s, owner, true);
}
