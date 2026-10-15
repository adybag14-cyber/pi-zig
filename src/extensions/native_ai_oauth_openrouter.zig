//! Actual OpenRouter OAuth PKCE facade. Exchange completes before callback HTML,
//! permanent issued keys and caller credential identity retain Source behavior.
const v = @import("native_ai_provider_values.zig");
const Scope = v.Scope;
const c = v.c;
const flow = @import("native_agent_async.zig");
const functions = @import("native_node_function.zig");
const helpers = @import("native_ai_auth_helpers.zig");
const http = @import("native_ai_oauth_http.zig");
const callback = @import("native_ai_oauth_callback_server.zig");
const common = @import("native_ai_oauth_anthropic.zig");
const Stage = enum(c_int) { pkce, callback, manual, exchange, fetch, json };
const token_url = "https://openrouter.ai/api/v1/auth/keys";

pub fn create(engine: *v.em.Engine) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const result = try scope.object();
    try scope.put(result, "name", try scope.text("OpenRouter OAuth"));
    try scope.put(result, "loginLabel", try scope.text("Sign in with OpenRouter"));
    try scope.put(result, "login", try scope.own(try helpers.asyncArrow(engine, "loginOpenRouter", 1, login, &.{})));
    try scope.put(result, "refresh", try scope.own(try helpers.asyncArrow(engine, "refresh", 2, refresh, &.{})));
    try scope.put(result, "toAuth", try scope.own(try helpers.asyncArrow(engine, "toAuth", 1, common.toAuth, &.{})));
    return c.JS_DupValue(engine.context, result);
}
fn refresh(engine: *v.em.Engine, _: c.JSValue, args: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
    const pending = try flow.create(engine, c.pi_js_undefined());
    defer engine.freeValue(pending.owner);
    errdefer engine.freeValue(pending.promise);
    try flow.settle(engine, pending.owner, false, common.argument(args, 0));
    return pending.promise;
}
fn login(engine: *v.em.Engine, _: c.JSValue, args: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const pending = try flow.create(engine, c.pi_js_undefined());
    defer engine.freeValue(pending.owner);
    errdefer engine.freeValue(pending.promise);
    try scope.put(pending.owner, "interaction", common.argument(args, 0));
    try scope.put(pending.owner, "callback", c.pi_js_undefined());
    const generated = @import("native_ai_oauth_pkce.zig").generate(engine) catch |err| {
        try flow.rejectError(engine, pending.owner, err);
        return pending.promise;
    };
    try flow.wait(continued, engine, pending.owner, try scope.own(generated), @intFromEnum(Stage.pkce));
    return pending.promise;
}
fn startCallback(scope: *Scope, owner: c.JSValue, pair: c.JSValue) !void {
    // Destructuring order remains verifier followed by challenge.
    const verifier = try scope.get(pair, "verifier");
    try scope.put(owner, "verifier", verifier);
    try scope.put(owner, "challenge", try scope.get(pair, "challenge"));
    const options = try scope.object();
    try scope.put(options, "providerName", try scope.text("OpenRouter"));
    try scope.put(options, "host", try common.callbackHost(scope));
    try scope.put(options, "port", c.JS_NewInt32(scope.engine.context, 0));
    try scope.put(options, "path", try scope.concat(try scope.text("/oauth/callback/"), try scope.invoke(try scope.global("crypto"), "randomUUID", &.{})));
    const Adapter = struct {
        fn complete(engine: *v.em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
            var local: Scope = .{ .engine = engine };
            defer local.deinit();
            const signal = try local.get(roots[1], "signal");
            return exchangeAuthorizationCode(engine, common.argument(args, 0), roots[0], signal);
        }
    };
    const interaction = try scope.get(owner, "interaction");
    try scope.put(options, "complete", try scope.own(try functions.createArrow(scope.engine, "complete", 1, Adapter.complete, &.{ verifier, interaction })));
    try scope.put(options, "signal", try scope.get(interaction, "signal"));
    try scope.put(options, "timeoutMs", c.JS_NewInt32(scope.engine.context, 300000));
    return flow.wait(continued, scope.engine, owner, try scope.own(try callback.start(scope.engine, options)), @intFromEnum(Stage.callback));
}
fn authorize(scope: *Scope, owner: c.JSValue, server: c.JSValue) !void {
    try scope.put(owner, "callback", server);
    const url = try scope.own(try v.js.builtin(scope.engine, "URL", &.{try scope.text("https://openrouter.ai/auth")}));
    const entries = try scope.object();
    try scope.put(entries, "callback_url", try scope.get(server, "redirectUri"));
    try scope.put(entries, "code_challenge", try scope.get(owner, "challenge"));
    try scope.put(entries, "code_challenge_method", try scope.text("S256"));
    const params = try scope.own(try v.js.builtin(scope.engine, "URLSearchParams", &.{entries}));
    try scope.set(url, "search", try scope.invoke(params, "toString", &.{}));
    const interaction = try scope.get(owner, "interaction");
    const progress_notify = try scope.get(interaction, "notify");
    const progress = try scope.object();
    try scope.put(progress, "type", try scope.text("progress"));
    try scope.put(progress, "message", try scope.concat(try scope.text("Listening for OpenRouter OAuth callback on "), try scope.stringify(try scope.get(server, "redirectUri"))));
    _ = try scope.call(progress_notify, interaction, &.{progress});
    const notify = try scope.get(interaction, "notify");
    const message = try scope.object();
    try scope.put(message, "type", try scope.text("auth_url"));
    try scope.put(message, "url", try scope.invoke(url, "toString", &.{}));
    try scope.put(message, "instructions", try scope.text("Complete sign-in in your browser. If the browser is on another machine, paste the final redirect URL here."));
    _ = try scope.call(notify, interaction, &.{message});
    const prompt = try scope.object();
    try scope.put(prompt, "message", try scope.text("Complete sign-in in your browser, or paste the authorization code / redirect URL here:"));
    try scope.put(prompt, "placeholder", try scope.get(server, "redirectUri"));
    return flow.wait(continued, scope.engine, owner, try scope.own(try callback.waitForCallbackOrManualInput(scope.engine, interaction, server, prompt)), @intFromEnum(Stage.manual));
}
fn close(scope: *Scope, owner: c.JSValue) !void {
    const server = try v.optional(scope, owner, "callback");
    if (!v.nullish(server)) _ = try scope.invoke(server, "close", &.{});
}
fn settle(scope: *Scope, owner: c.JSValue, rejected: bool, value: c.JSValue) !void {
    try close(scope, owner);
    return flow.settle(scope.engine, owner, rejected, value);
}
fn continued(engine: *v.em.Engine, owner: c.JSValue, value: c.JSValue, rejected: bool, raw: c_int) !void {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    if (rejected) return settle(&scope, owner, true, value);
    advance(&scope, owner, value, @enumFromInt(raw)) catch |err| {
        const reason = try scope.own(flow.reason(engine, err));
        return settle(&scope, owner, true, reason);
    };
}
fn advance(scope: *Scope, owner: c.JSValue, value: c.JSValue, stage: Stage) !void {
    switch (stage) {
        .pkce => return startCallback(scope, owner, value),
        .callback => return authorize(scope, owner, value),
        .manual => {
            if (try v.eq(scope, try scope.get(value, "type"), "callback")) return settle(scope, owner, false, try scope.get(value, "value"));
            const parsed = try common.parseAuthorizationInput(scope, try scope.get(value, "input"), false);
            const code = try v.optional(scope, parsed, "code");
            if (!scope.truthy(code)) return v.errorText(scope, try scope.text("Missing authorization code"));
            const interaction = try scope.get(owner, "interaction");
            try common.notifyProgress(scope, interaction, "Exchanging authorization code for an API key...");
            return flow.wait(continued, scope.engine, owner, try scope.own(try exchangeAuthorizationCode(scope.engine, code, try scope.get(owner, "verifier"), try scope.get(interaction, "signal"))), @intFromEnum(Stage.exchange));
        },
        .exchange => return settle(scope, owner, false, value),
        else => unreachable,
    }
}
fn exchangeAuthorizationCode(engine: *v.em.Engine, code: c.JSValue, verifier: c.JSValue, signal: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const pending = try flow.create(engine, c.pi_js_undefined());
    defer engine.freeValue(pending.owner);
    errdefer engine.freeValue(pending.promise);
    try scope.put(pending.owner, "signal", signal);
    try scope.put(pending.owner, "inRequest", c.pi_js_bool(engine.context, 0));
    startExchange(&scope, pending.owner, code, verifier, signal) catch |err| {
        const reason = try scope.own(flow.reason(engine, err));
        try exchangeFailure(&scope, pending.owner, reason);
    };
    return pending.promise;
}
fn startExchange(scope: *Scope, owner: c.JSValue, code: c.JSValue, verifier: c.JSValue, signal: c.JSValue) !void {
    if (scope.truthy(try scope.get(signal, "aborted"))) return v.errorText(scope, try scope.text("Login cancelled"));
    const controller = try scope.own(try v.js.builtin(scope.engine, "AbortController", &.{}));
    try scope.put(owner, "controller", controller);
    const Abort = struct {
        fn run(engine: *v.em.Engine, _: c.JSValue, _: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
            var local: Scope = .{ .engine = engine };
            defer local.deinit();
            return c.JS_DupValue(engine.context, try local.invoke(roots[0], "abort", &.{try local.get(roots[1], "reason")}));
        }
    };
    const on_abort = try scope.own(try functions.createArrow(scope.engine, "onAbort", 0, Abort.run, &.{ controller, signal }));
    try scope.put(owner, "onAbort", on_abort);
    const listener_options = try scope.object();
    try scope.put(listener_options, "once", c.pi_js_bool(scope.engine.context, 1));
    _ = try scope.invoke(signal, "addEventListener", &.{ try scope.text("abort"), on_abort, listener_options });
    const timeout_fn = try scope.global("setTimeout");
    const Timer = struct {
        fn run(engine: *v.em.Engine, _: c.JSValue, _: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
            var local: Scope = .{ .engine = engine };
            defer local.deinit();
            const abort = try local.get(roots[0], "abort");
            const error_value = try local.own(try v.js.builtin(engine, "Error", &.{try local.text("OpenRouter OAuth token exchange timed out")}));
            return c.JS_DupValue(engine.context, try local.call(abort, roots[0], &.{error_value}));
        }
    };
    const timer = try scope.call(timeout_fn, c.pi_js_undefined(), &.{ try scope.own(try functions.createArrow(scope.engine, "", 0, Timer.run, &.{controller})), c.JS_NewInt32(scope.engine.context, 30000) });
    try scope.put(owner, "timer", timer);
    try scope.put(owner, "body", try scope.object());
    try scope.put(owner, "inRequest", c.pi_js_bool(scope.engine.context, 1));
    const fetch = try http.captureFetch(scope);
    const init = try scope.object();
    try scope.put(init, "method", try scope.text("POST"));
    const headers = try scope.object();
    try scope.put(headers, "accept", try scope.text("application/json"));
    try scope.put(headers, "content-type", try scope.text("application/json"));
    try scope.put(init, "headers", headers);
    const payload = try scope.object();
    try scope.put(payload, "code", code);
    try scope.put(payload, "code_verifier", verifier);
    try scope.put(payload, "code_challenge_method", try scope.text("S256"));
    try scope.put(init, "body", try scope.invoke(try scope.global("JSON"), "stringify", &.{payload}));
    try scope.put(init, "signal", try scope.get(controller, "signal"));
    return flow.wait(exchangeReady, scope.engine, owner, try scope.own(try http.requestWithFetch(scope.engine, fetch, try scope.text(token_url), init)), @intFromEnum(Stage.fetch));
}
fn cleanup(scope: *Scope, owner: c.JSValue) !void {
    // Mark the finally region before calling guest hooks so a throwing cleanup
    // is propagated once instead of re-entering the exchange catch/finally.
    try scope.put(owner, "inRequest", c.pi_js_bool(scope.engine.context, 0));
    _ = try scope.call(try scope.global("clearTimeout"), c.pi_js_undefined(), &.{try scope.get(owner, "timer")});
    _ = try scope.invoke(try scope.get(owner, "signal"), "removeEventListener", &.{ try scope.text("abort"), try scope.get(owner, "onAbort") });
}
fn exchangeFailure(scope: *Scope, owner: c.JSValue, reason: c.JSValue) !void {
    if (!scope.truthy(try scope.get(owner, "inRequest"))) return flow.settle(scope.engine, owner, true, reason);
    const signal = try scope.get(owner, "signal");
    var failure = reason;
    if (scope.truthy(try scope.get(signal, "aborted"))) {
        failure = try scope.own(try v.js.builtin(scope.engine, "Error", &.{try scope.text("Login cancelled")}));
    } else if (scope.truthy(try scope.get(try scope.get(try scope.get(owner, "controller"), "signal"), "aborted"))) {
        failure = try scope.own(try v.js.builtin(scope.engine, "Error", &.{try scope.text("OpenRouter OAuth token exchange timed out")}));
    }
    try cleanup(scope, owner);
    return flow.settle(scope.engine, owner, true, failure);
}
fn exchangeReady(engine: *v.em.Engine, owner: c.JSValue, value: c.JSValue, rejected: bool, raw: c_int) !void {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const stage: Stage = @enumFromInt(raw);
    exchangeAdvance(&scope, owner, value, rejected, stage) catch |err| {
        const reason = try scope.own(flow.reason(engine, err));
        return exchangeFailure(&scope, owner, reason);
    };
}
fn exchangeAdvance(scope: *Scope, owner: c.JSValue, value: c.JSValue, rejected: bool, stage: Stage) !void {
    if (stage == .fetch) {
        if (rejected) return exchangeFailure(scope, owner, value);
        try scope.put(owner, "response", value);
        const generation = scope.engine.native_allocation_generation;
        const parsed = scope.invoke(value, "json", &.{}) catch |err| {
            const reason = try scope.own(flow.reason(scope.engine, err));
            try @import("native_ai_partial_json.zig").discard(scope.engine, err, generation);
            return jsonFailure(scope, owner, reason);
        };
        return flow.wait(exchangeReady, scope.engine, owner, parsed, @intFromEnum(Stage.json));
    }
    if (rejected) return jsonFailure(scope, owner, value);
    const generation = scope.engine.native_allocation_generation;
    parseBody(scope, owner, value) catch |err| {
        const reason = try scope.own(flow.reason(scope.engine, err));
        try @import("native_ai_partial_json.zig").discard(scope.engine, err, generation);
        return jsonFailure(scope, owner, reason);
    };
    return finishExchange(scope, owner);
}
fn parseBody(scope: *Scope, owner: c.JSValue, value: c.JSValue) !void {
    // typeof a function is not "object" even though QuickJS stores functions as
    // objects internally.
    if (scope.truthy(value) and c.JS_IsObject(value) and !c.JS_IsFunction(scope.engine.context, value) and !try v.array(scope, value)) try scope.put(owner, "body", value);
}
fn jsonFailure(scope: *Scope, owner: c.JSValue, reason: c.JSValue) !void {
    _ = reason;
    if (scope.truthy(try scope.get(try scope.get(owner, "response"), "ok"))) {
        return exchangeFailure(scope, owner, try scope.own(try v.js.builtin(scope.engine, "Error", &.{try scope.text("OpenRouter OAuth returned invalid JSON")})));
    }
    return finishExchange(scope, owner);
}
fn finishExchange(scope: *Scope, owner: c.JSValue) !void {
    try cleanup(scope, owner);
    const response = try scope.get(owner, "response");
    const body = try scope.get(owner, "body");
    if (!scope.truthy(try scope.get(response, "ok"))) {
        const detail = try errorDetail(scope, body);
        var message = try scope.concat(try scope.concat(try scope.text("OpenRouter OAuth key exchange failed (HTTP "), try scope.stringify(try scope.get(response, "status"))), try scope.text(")"));
        if (scope.truthy(detail)) message = try scope.concat(message, try scope.concat(try scope.text(": "), try scope.stringify(detail)));
        return flow.settle(scope.engine, owner, true, try scope.own(try v.js.builtin(scope.engine, "Error", &.{message})));
    }
    const key_type = try scope.get(body, "key");
    if (!c.JS_IsString(key_type) or try v.length(scope, try scope.get(body, "key")) == 0) return flow.settle(scope.engine, owner, true, try scope.own(try v.js.builtin(scope.engine, "Error", &.{try scope.text("OpenRouter OAuth response carries no \"key\"")})));
    const credential = try scope.object();
    try scope.put(credential, "type", try scope.text("oauth"));
    try scope.put(credential, "access", try scope.get(body, "key"));
    try scope.put(credential, "refresh", try scope.text(""));
    try scope.put(credential, "expires", try scope.get(try scope.global("Number"), "MAX_SAFE_INTEGER"));
    return flow.settle(scope.engine, owner, false, credential);
}
fn errorDetail(scope: *Scope, body: c.JSValue) !c.JSValue {
    inline for (.{ "error_description", "message", "error" }) |key| {
        if (c.JS_IsString(try scope.get(body, key))) return scope.get(body, key);
    }
    if (scope.truthy(try scope.get(body, "error")) and c.JS_IsObject(try scope.get(body, "error")) and !c.JS_IsFunction(scope.engine.context, try scope.get(body, "error")) and !try v.array(scope, try scope.get(body, "error"))) {
        const message = try scope.get(try scope.get(body, "error"), "message");
        if (c.JS_IsString(message)) return message;
    }
    return c.pi_js_undefined();
}
