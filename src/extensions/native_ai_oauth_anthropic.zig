//! Actual Anthropic OAuthAuth facade. All guest operations remain on the VM owner
//! thread; continuations retain original interactions, signals and responses.

const v = @import("native_ai_provider_values.zig");
const Scope = v.Scope;
const c = v.c;
const flow = @import("native_agent_async.zig");
const functions = @import("native_node_function.zig");
const helpers = @import("native_ai_auth_helpers.zig");
const http = @import("native_ai_oauth_http.zig");
const callback = @import("native_ai_oauth_callback_server.zig");
const protocol = @import("../auth/anthropic_oauth.zig");
const copy_redirect = "https://platform.claude.com/oauth/code/callback";
const Stage = enum(c_int) { select, pkce, preferred, fallback, manual, fetch, text, body };

pub fn argument(args: []const c.JSValue, index: usize) c.JSValue {
    return if (args.len > index) args[index] else c.pi_js_undefined();
}
pub fn callbackHost(scope: *Scope) !c.JSValue {
    const env = try scope.own(try @import("native_provider_env.zig").create(scope.engine));
    const host = try scope.call(env, c.pi_js_undefined(), &.{ try scope.text("PI_OAUTH_CALLBACK_HOST"), c.pi_js_undefined() });
    return if (scope.truthy(host)) host else scope.text("127.0.0.1");
}
pub fn create(engine: *v.em.Engine) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    // Anthropic captures this module constant at module creation; OpenRouter
    // deliberately reads its callback host inside every login instead.
    const host = try callbackHost(&scope);
    const result = try scope.object();
    try scope.put(result, "name", try scope.text("Anthropic (Claude Pro/Max)"));
    try scope.put(result, "isSubscription", c.pi_js_bool(engine.context, 1));
    try scope.put(result, "login", try scope.own(try helpers.asyncArrow(engine, "login", 1, login, &.{host})));
    try scope.put(result, "refresh", try scope.own(try functions.createArrow(engine, "refresh", 2, refresh, &.{})));
    try scope.put(result, "toAuth", try scope.own(try helpers.asyncArrow(engine, "toAuth", 1, toAuth, &.{})));
    return c.JS_DupValue(engine.context, result);
}
pub fn toAuth(engine: *v.em.Engine, _: c.JSValue, args: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const pending = try flow.create(engine, c.pi_js_undefined());
    defer engine.freeValue(pending.owner);
    errdefer engine.freeValue(pending.promise);
    const result = scope.object() catch |err| {
        try flow.rejectError(engine, pending.owner, err);
        return pending.promise;
    };
    const key = scope.get(argument(args, 0), "access") catch |err| {
        try flow.rejectError(engine, pending.owner, err);
        return pending.promise;
    };
    try scope.put(result, "apiKey", key);
    try flow.settle(engine, pending.owner, false, result);
    return pending.promise;
}
fn login(engine: *v.em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const pending = try flow.create(engine, c.pi_js_undefined());
    defer engine.freeValue(pending.owner);
    errdefer engine.freeValue(pending.promise);
    startLogin(&scope, pending.owner, argument(args, 0), roots[0]) catch |err| try flow.rejectError(engine, pending.owner, err);
    return pending.promise;
}
fn startLogin(scope: *Scope, owner: c.JSValue, interaction: c.JSValue, host: c.JSValue) !void {
    try scope.put(owner, "interaction", interaction);
    try scope.put(owner, "host", host);
    try scope.put(owner, "callback", c.pi_js_undefined());
    try scope.put(owner, "refreshing", c.pi_js_bool(scope.engine.context, 0));
    const prompt = try scope.object();
    try scope.put(prompt, "type", try scope.text("select"));
    try scope.put(prompt, "message", try scope.text("Select Anthropic login method:"));
    const options = try scope.array();
    inline for (.{ .{ "browser", "Browser login (default)" }, .{ "copy_code", "Copy code login (headless)" } }, 0..) |pair, index| {
        const item = try scope.object();
        try scope.put(item, "id", try scope.text(pair[0]));
        try scope.put(item, "label", try scope.text(pair[1]));
        try scope.index(options, index, item);
    }
    try scope.put(prompt, "options", options);
    // Member function lookup precedes object argument construction in Source.
    return flow.wait(continued, scope.engine, owner, try scope.invoke(interaction, "prompt", &.{prompt}), @intFromEnum(Stage.select));
}
fn refresh(engine: *v.em.Engine, _: c.JSValue, args: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    // This is a regular arrow, so credential.refresh access throws synchronously.
    const token = try scope.get(argument(args, 0), "refresh");
    const pending = try flow.create(engine, c.pi_js_undefined());
    defer engine.freeValue(pending.owner);
    errdefer engine.freeValue(pending.promise);
    startRefresh(&scope, pending.owner, token, argument(args, 1)) catch |err| try fail(&scope, pending.owner, err, .fetch);
    return pending.promise;
}
fn startRefresh(scope: *Scope, owner: c.JSValue, token: c.JSValue, signal: c.JSValue) !void {
    try scope.put(owner, "refreshing", c.pi_js_bool(scope.engine.context, 1));
    try scope.put(owner, "signal", signal);
    const body = try scope.object();
    try scope.put(body, "grant_type", try scope.text("refresh_token"));
    try scope.put(body, "client_id", try scope.text(protocol.CLIENT_ID));
    try scope.put(body, "refresh_token", token);
    return post(scope, owner, body, signal);
}
fn startCallback(scope: *Scope, owner: c.JSValue, port: i32, stage: Stage) !void {
    const options = try scope.object();
    try scope.put(options, "providerName", try scope.text("Anthropic"));
    try scope.put(options, "host", try scope.get(owner, "host"));
    try scope.put(options, "port", c.JS_NewInt32(scope.engine.context, port));
    try scope.put(options, "path", try scope.text(protocol.CALLBACK_PATH));
    try scope.put(options, "redirectHost", try scope.text("localhost"));
    try scope.put(options, "state", try scope.get(owner, "verifier"));
    const Adapter = struct {
        fn complete(engine: *v.em.Engine, _: c.JSValue, args: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
            const pending = try flow.create(engine, c.pi_js_undefined());
            defer engine.freeValue(pending.owner);
            errdefer engine.freeValue(pending.promise);
            try flow.settle(engine, pending.owner, false, argument(args, 0));
            return pending.promise;
        }
    };
    try scope.put(options, "complete", try scope.own(try helpers.asyncArrow(scope.engine, "complete", 1, Adapter.complete, &.{})));
    try scope.put(options, "signal", try scope.get(try scope.get(owner, "interaction"), "signal"));
    return flow.wait(continued, scope.engine, owner, try scope.own(try callback.start(scope.engine, options)), @intFromEnum(stage));
}
fn authorize(scope: *Scope, owner: c.JSValue) !void {
    const copy = scope.truthy(try scope.get(owner, "copy"));
    const server = try scope.get(owner, "callback");
    const redirect = if (copy) try scope.text(copy_redirect) else if (v.nullish(server)) try scope.text(protocol.REDIRECT_URI) else try scope.get(server, "redirectUri");
    try scope.put(owner, "redirect", redirect);
    const entries = try scope.object();
    try scope.put(entries, "code", try scope.text("true"));
    try scope.put(entries, "client_id", try scope.text(protocol.CLIENT_ID));
    try scope.put(entries, "response_type", try scope.text("code"));
    try scope.put(entries, "redirect_uri", redirect);
    try scope.put(entries, "scope", try scope.text(protocol.SCOPES));
    try scope.put(entries, "code_challenge", try scope.get(owner, "challenge"));
    try scope.put(entries, "code_challenge_method", try scope.text("S256"));
    try scope.put(entries, "state", try scope.get(owner, "verifier"));
    const params = try scope.own(try v.js.builtin(scope.engine, "URLSearchParams", &.{entries}));
    const interaction = try scope.get(owner, "interaction");
    const notify = try scope.get(interaction, "notify");
    const message = try scope.object();
    try scope.put(message, "type", try scope.text("auth_url"));
    try scope.put(message, "url", try scope.concat(try scope.text(protocol.AUTHORIZE_URL ++ "?"), try scope.invoke(params, "toString", &.{})));
    try scope.put(message, "instructions", try scope.text(if (copy) "Complete login in your browser, then copy the code Anthropic shows and paste it here." else "Complete login in your browser. If the browser is on another machine, paste the final redirect URL here."));
    _ = try scope.call(notify, interaction, &.{message});
    const prompt_fn = if (copy) try scope.get(interaction, "prompt") else c.pi_js_undefined();
    const prompt = try scope.object();
    if (copy) try scope.put(prompt, "type", try scope.text("manual_code"));
    try scope.put(prompt, "message", try scope.text(if (copy) "Paste the code Anthropic shows after you sign in:" else "Complete login in your browser, or paste the authorization code / redirect URL here:"));
    try scope.put(prompt, "placeholder", if (copy) try scope.text("code#state") else redirect);
    const returned = if (copy) result: {
        try scope.put(prompt, "signal", try scope.get(interaction, "signal"));
        break :result try scope.call(prompt_fn, interaction, &.{prompt});
    } else try scope.own(try callback.waitForCallbackOrManualInput(scope.engine, interaction, server, prompt));
    return flow.wait(continued, scope.engine, owner, returned, @intFromEnum(Stage.manual));
}
pub fn parseAuthorizationInput(scope: *Scope, input: c.JSValue, with_state: bool) !c.JSValue {
    const value = try scope.invoke(input, "trim", &.{});
    const result = try scope.object();
    if (!scope.truthy(value)) return result;
    const generation = scope.engine.native_allocation_generation;
    const url = v.js.builtin(scope.engine, "URL", &.{value}) catch |err| invalid: {
        try @import("native_ai_partial_json.zig").discard(scope.engine, err, generation);
        break :invalid c.pi_js_undefined();
    };
    if (!c.JS_IsUndefined(url)) {
        const parsed = try scope.own(url);
        const params = try scope.get(parsed, "searchParams");
        try queryInput(scope, result, params, with_state);
        return result;
    }
    if (with_state and scope.truthy(try scope.invoke(value, "includes", &.{try scope.text("#")}))) {
        const parts = try scope.invoke(value, "split", &.{ try scope.text("#"), c.JS_NewInt32(scope.engine.context, 2) });
        try scope.put(result, "code", try v.at(scope, parts, 0));
        try scope.put(result, "state", try v.at(scope, parts, 1));
    } else if (scope.truthy(try scope.invoke(value, "includes", &.{try scope.text("code=")}))) {
        try queryInput(scope, result, try scope.own(try v.js.builtin(scope.engine, "URLSearchParams", &.{value})), with_state);
    } else try scope.put(result, "code", value);
    return result;
}
fn queryInput(scope: *Scope, result: c.JSValue, params: c.JSValue, with_state: bool) !void {
    const code = try scope.invoke(params, "get", &.{try scope.text("code")});
    try scope.put(result, "code", if (v.nullish(code)) c.pi_js_undefined() else code);
    if (with_state) {
        const state = try scope.invoke(params, "get", &.{try scope.text("state")});
        try scope.put(result, "state", if (v.nullish(state)) c.pi_js_undefined() else state);
    }
}
fn exchange(scope: *Scope, owner: c.JSValue, result: c.JSValue) !void {
    var code: c.JSValue = undefined;
    var state = try scope.get(owner, "verifier");
    const copy = scope.truthy(try scope.get(owner, "copy"));
    if (!copy and try v.eq(scope, try scope.get(result, "type"), "callback")) {
        code = try scope.get(result, "value");
    } else {
        const parsed = try parseAuthorizationInput(scope, if (copy) result else try scope.get(result, "input"), true);
        const parsed_state = try v.optional(scope, parsed, "state");
        if (scope.truthy(parsed_state) and !scope.equal(parsed_state, state)) return v.errorText(scope, try scope.text("OAuth state mismatch"));
        code = try v.optional(scope, parsed, "code");
        if (!v.nullish(parsed_state)) state = parsed_state;
    }
    if (!scope.truthy(code)) return v.errorText(scope, try scope.text("Missing authorization code"));
    const interaction = try scope.get(owner, "interaction");
    try notifyProgress(scope, interaction, "Exchanging authorization code for tokens...");
    // The signal getter is evaluated in the caller before entering exchange.
    const signal = try scope.get(interaction, "signal");
    try scope.put(owner, "signal", signal);
    const body = try scope.object();
    try scope.put(body, "grant_type", try scope.text("authorization_code"));
    try scope.put(body, "client_id", try scope.text(protocol.CLIENT_ID));
    try scope.put(body, "code", code);
    try scope.put(body, "state", state);
    try scope.put(body, "redirect_uri", try scope.get(owner, "redirect"));
    try scope.put(body, "code_verifier", try scope.get(owner, "verifier"));
    return post(scope, owner, body, signal);
}
pub fn notifyProgress(scope: *Scope, interaction: c.JSValue, message: []const u8) !void {
    const notify = try scope.get(interaction, "notify");
    const event = try scope.object();
    try scope.put(event, "type", try scope.text("progress"));
    try scope.put(event, "message", try scope.text(message));
    _ = try scope.call(notify, interaction, &.{event});
}
fn post(scope: *Scope, owner: c.JSValue, body: c.JSValue, signal: c.JSValue) !void {
    startPost(scope, owner, body, signal) catch |err| return fail(scope, owner, err, .fetch);
}
fn startPost(scope: *Scope, owner: c.JSValue, body: c.JSValue, signal: c.JSValue) !void {
    const fetch = try http.captureFetch(scope);
    const init = try scope.object();
    try scope.put(init, "method", try scope.text("POST"));
    const headers = try scope.object();
    try scope.put(headers, "Content-Type", try scope.text("application/json"));
    try scope.put(headers, "Accept", try scope.text("application/json"));
    try scope.put(init, "headers", headers);
    try scope.put(init, "body", try scope.invoke(try scope.global("JSON"), "stringify", &.{body}));
    const abort = try scope.global("AbortSignal");
    const any = try scope.get(abort, "any");
    const signals = try scope.array();
    try scope.index(signals, 0, signal);
    try scope.index(signals, 1, try scope.invoke(try scope.global("AbortSignal"), "timeout", &.{c.JS_NewInt32(scope.engine.context, 30000)}));
    try scope.put(init, "signal", try scope.call(any, abort, &.{signals}));
    const returned = try scope.own(try http.requestWithFetch(scope.engine, fetch, try scope.text(protocol.TOKEN_URL), init));
    return flow.wait(continued, scope.engine, owner, returned, @intFromEnum(Stage.fetch));
}
fn close(scope: *Scope, owner: c.JSValue) !void {
    if (scope.truthy(try v.optional(scope, owner, "refreshing"))) return;
    const server = try v.optional(scope, owner, "callback");
    if (!v.nullish(server)) _ = try scope.invoke(server, "close", &.{});
}
fn settle(scope: *Scope, owner: c.JSValue, rejected: bool, value: c.JSValue) !void {
    try close(scope, owner);
    return flow.settle(scope.engine, owner, rejected, value);
}
fn fail(scope: *Scope, owner: c.JSValue, err: anyerror, stage: Stage) !void {
    const reason = try scope.own(flow.reason(scope.engine, err));
    return failure(scope, owner, reason, stage);
}
fn failure(scope: *Scope, owner: c.JSValue, reason: c.JSValue, stage: Stage) !void {
    if (stage == .preferred) return startCallback(scope, owner, 0, .fallback);
    if (stage == .fallback) return authorize(scope, owner);
    if (stage == .fetch or stage == .text) {
        const refreshing = scope.truthy(try scope.get(owner, "refreshing"));
        var text = try scope.text(if (refreshing) "Anthropic token refresh request failed. url=" ++ protocol.TOKEN_URL ++ "; details=" else "Token exchange request failed. url=" ++ protocol.TOKEN_URL ++ "; redirect_uri=");
        if (!refreshing) text = try scope.concat(try scope.concat(text, try scope.get(owner, "redirect")), try scope.text("; response_type=authorization_code; details="));
        const wrapped = try scope.own(try v.js.builtin(scope.engine, "Error", &.{try scope.concat(text, try formatErrorDetails(scope, reason))}));
        return settle(scope, owner, true, wrapped);
    }
    return settle(scope, owner, true, reason);
}
pub fn formatErrorDetails(scope: *Scope, reason: c.JSValue) anyerror!c.JSValue {
    const error_class = try scope.global("Error");
    const instance = c.JS_IsInstanceOf(scope.engine.context, reason, error_class);
    if (instance < 0) return v.js.capture(scope.engine);
    if (instance == 0) return scope.stringify(reason);
    const details = try scope.array();
    const name = try scope.stringify(try scope.get(reason, "name"));
    const message = try scope.stringify(try scope.get(reason, "message"));
    _ = try scope.invoke(details, "push", &.{try scope.concat(try scope.concat(name, try scope.text(": ")), message)});
    if (scope.truthy(try scope.get(reason, "code"))) _ = try scope.invoke(details, "push", &.{try scope.concat(try scope.text("code="), try scope.stringify(try scope.get(reason, "code")))});
    if (!c.JS_IsUndefined(try scope.get(reason, "errno"))) _ = try scope.invoke(details, "push", &.{try scope.concat(try scope.text("errno="), try scope.stringify(try scope.get(reason, "errno")))});
    if (!c.JS_IsUndefined(try scope.get(reason, "cause"))) _ = try scope.invoke(details, "push", &.{try scope.concat(try scope.text("cause="), try formatErrorDetails(scope, try scope.get(reason, "cause")))});
    if (scope.truthy(try scope.get(reason, "stack"))) _ = try scope.invoke(details, "push", &.{try scope.concat(try scope.text("stack="), try scope.stringify(try scope.get(reason, "stack")))});
    return scope.invoke(details, "join", &.{try scope.text("; ")});
}
fn continued(engine: *v.em.Engine, owner: c.JSValue, value: c.JSValue, rejected: bool, raw: c_int) !void {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const stage: Stage = @enumFromInt(raw);
    if (rejected) return failure(&scope, owner, value, stage);
    // The catches on callback startup do not cover the subsequent login body.
    advance(&scope, owner, value, stage) catch |err| try fail(&scope, owner, err, if (stage == .preferred or stage == .fallback) .manual else stage);
}
fn advance(scope: *Scope, owner: c.JSValue, value: c.JSValue, stage: Stage) !void {
    switch (stage) {
        .select => {
            const copy = try v.eq(scope, value, "copy_code");
            if (!copy and !try v.eq(scope, value, "browser")) return v.errorText(scope, try scope.concat(try scope.text("Unknown Anthropic login method: "), try scope.stringify(value)));
            try scope.put(owner, "copy", c.pi_js_bool(scope.engine.context, @intFromBool(copy)));
            return flow.wait(continued, scope.engine, owner, try scope.own(try @import("native_ai_oauth_pkce.zig").generate(scope.engine)), @intFromEnum(Stage.pkce));
        },
        .pkce => {
            try scope.put(owner, "verifier", try scope.get(value, "verifier"));
            try scope.put(owner, "challenge", try scope.get(value, "challenge"));
            if (scope.truthy(try scope.get(owner, "copy"))) return authorize(scope, owner);
            return startCallback(scope, owner, protocol.CALLBACK_PORT, .preferred);
        },
        .preferred, .fallback => {
            try scope.put(owner, "callback", value);
            return authorize(scope, owner);
        },
        .manual => return exchange(scope, owner, value),
        .fetch => {
            try scope.put(owner, "response", value);
            return flow.wait(continued, scope.engine, owner, try scope.invoke(value, "text", &.{}), @intFromEnum(Stage.text));
        },
        .text => {
            const response = try scope.get(owner, "response");
            if (!scope.truthy(try scope.get(response, "ok"))) {
                const status = try scope.stringify(try scope.get(response, "status"));
                return v.errorText(scope, try scope.concat(try scope.concat(try scope.text("HTTP request failed. status="), status), try scope.concat(try scope.text("; url=" ++ protocol.TOKEN_URL ++ "; body="), try scope.stringify(value))));
            }
            return flow.wait(continued, scope.engine, owner, value, @intFromEnum(Stage.body));
        },
        .body => {
            const generation = scope.engine.native_allocation_generation;
            const data = scope.invoke(try scope.global("JSON"), "parse", &.{value}) catch |err| {
                const reason = try scope.own(flow.reason(scope.engine, err));
                try @import("native_ai_partial_json.zig").discard(scope.engine, err, generation);
                const refreshing = scope.truthy(try scope.get(owner, "refreshing"));
                const prefix = if (refreshing) "Anthropic token refresh returned invalid JSON. url=" else "Token exchange returned invalid JSON. url=";
                const text = try scope.concat(try scope.concat(try scope.concat(try scope.text(prefix), try scope.text(protocol.TOKEN_URL ++ "; body=")), try scope.stringify(value)), try scope.concat(try scope.text("; details="), try formatErrorDetails(scope, reason)));
                return settle(scope, owner, true, try scope.own(try v.js.builtin(scope.engine, "Error", &.{text})));
            };
            const credential = try scope.object();
            try scope.put(credential, "type", try scope.text("oauth"));
            try scope.put(credential, "refresh", try scope.get(data, "refresh_token"));
            try scope.put(credential, "access", try scope.get(data, "access_token"));
            const now = try scope.invoke(try scope.global("Date"), "now", &.{});
            const seconds = try scope.get(data, "expires_in");
            const millis = try scope.own(try scope.engine.checked(c.JS_PiBinaryOperator(scope.engine.context, 2, seconds, c.JS_NewInt32(scope.engine.context, 1000))));
            const expiry = try scope.own(try scope.engine.checked(c.JS_PiBinaryOperator(scope.engine.context, 0, now, millis)));
            try scope.put(credential, "expires", try scope.own(try scope.engine.checked(c.JS_PiBinaryOperator(scope.engine.context, 1, expiry, c.JS_NewInt32(scope.engine.context, 300000)))));
            return settle(scope, owner, false, credential);
        },
    }
}
