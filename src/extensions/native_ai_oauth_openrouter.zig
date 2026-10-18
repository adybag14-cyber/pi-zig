//! c268154c auth/oauth/openrouter.ts: genuine login, exchange and zero-Await methods.
//! Browser/manual completion uses the actual shared OAuth callback owner.
const x = @import("native_ai_auth_helper_values.zig");
const c = x.c;
const af = x.af;
const functions = @import("native_node_function.zig");
const callback_server = @import("native_ai_oauth_callback_server.zig");
const authorize_url = "https://openrouter.ai/auth";
const token_url = "https://openrouter.ai/api/v1/auth/keys";
const Stage = enum(i32) { exchange_response, exchange_json, login_pkce, login_callback, login_input, login_exchange };

fn expression(engine: *x.em.Engine, comptime body: anytype, args: anytype) !c.JSValue {
    var scope: x.Scope = .{ .engine = engine };
    var o: x.Ops = .{ .s = &scope };
    return x.owned.finishValue(&scope, @call(.auto, body, .{&o} ++ args));
}
fn statement(engine: *x.em.Engine, comptime body: anytype, args: anytype) !void {
    var scope: x.Scope = .{ .engine = engine };
    var o: x.Ops = .{ .s = &scope };
    return x.owned.finishVoid(&scope, @call(.auto, body, .{&o} ++ args));
}
fn actionExpression(engine: *x.em.Engine, comptime body: anytype, args: anytype) !af.Action {
    var scope: x.Scope = .{ .engine = engine };
    var o: x.Ops = .{ .s = &scope };
    return x.owned.finishAction(&scope, @call(.auto, body, .{&o} ++ args));
}
fn value(o: *x.Ops, comptime body: anytype, args: anytype) !c.JSValue { return o.own(try expression(o.s.engine, body, args)); }
fn truth(o: *x.Ops, comptime body: anytype, args: anytype) !bool { return o.truthy(try value(o, body, args)); }
fn attempt(engine: *x.em.Engine, comptime body: anytype, args: anytype) !af.Action {
    var scope: x.Scope = .{ .engine = engine };
    var o: x.Ops = .{ .s = &scope };
    var completion = x.owned.Completion.initValue(engine, @call(.auto, body, .{&o} ++ args));
    completion.releaseScope(&scope);
    return completion.finishAction();
}
fn discard(engine: *x.em.Engine, input: c.JSValue) !void {
    var completion = x.owned.Completion.initVoid(engine, {});
    completion.release(input);
    return completion.finishVoid();
}
fn duplicate(o: *x.Ops, input: c.JSValue) c.JSValue { return c.JS_DupValue(o.s.engine.context, input); }
fn integer(o: *x.Ops, input: i32) c.JSValue { return c.JS_NewInt32(o.s.engine.context, input); }
fn boolean(o: *x.Ops, input: bool) c.JSValue { return c.pi_js_bool(o.s.engine.context, @intFromBool(input)); }
fn text(o: *x.Ops, input: []const u8) !c.JSValue { return o.text(input); }
fn concat(o: *x.Ops, left: c.JSValue, right: c.JSValue) !c.JSValue { return o.binary(0, left, right); }
fn property(o: *x.Ops, receiver: c.JSValue, name: [*:0]const u8) !c.JSValue { return duplicate(o, try o.get(receiver, name)); }
fn propertyTruthy(o: *x.Ops, receiver: c.JSValue, name: [*:0]const u8) !c.JSValue { return boolean(o, o.truthy(try o.get(receiver, name))); }
fn propertyIsString(o: *x.Ops, receiver: c.JSValue, name: [*:0]const u8) !c.JSValue { return boolean(o, c.JS_IsString(try o.get(receiver, name))); }
fn propertyUndefined(o: *x.Ops, receiver: c.JSValue, name: [*:0]const u8) !c.JSValue { return boolean(o, c.JS_IsUndefined(try o.get(receiver, name))); }
fn equalText(o: *x.Ops, input: c.JSValue, expected: []const u8) !bool { return c.JS_IsStrictEqual(o.s.engine.context, input, try o.text(expected)); }
fn propertyEqualsText(o: *x.Ops, receiver: c.JSValue, name: [*:0]const u8, expected: []const u8) !c.JSValue { return boolean(o, try equalText(o, try o.get(receiver, name), expected)); }
fn stringifyValue(o: *x.Ops, input: c.JSValue) !c.JSValue { return duplicate(o, try o.stringify(input)); }
fn propertyString(o: *x.Ops, receiver: c.JSValue, name: [*:0]const u8) !c.JSValue { return duplicate(o, try o.stringify(try o.get(receiver, name))); }
fn array(o: *x.Ops) !c.JSValue {
    const generation = try o.beforeAllocation();
    return o.allocation(c.JS_NewArray(o.s.engine.context), generation);
}
fn initialize(o: *x.Ops, state: *c.JSValue) !c.JSValue {
    const owner = try o.cell();
    af.replaceState(o.s.engine, state, duplicate(o, owner));
    return owner;
}
fn setStage(o: *x.Ops, owner: c.JSValue, stage: Stage) !void { return o.put(owner, "stage", integer(o, @intFromEnum(stage))); }
fn getStage(o: *x.Ops, owner: c.JSValue) !Stage {
    const raw = try o.get(owner, "stage");
    var n: i32 = 0;
    var boundary: x.guest.Boundary = .{ .engine = o.s.engine };
    try boundary.begin();
    try boundary.finishStatus(c.JS_ToInt32(o.s.engine.context, &n, raw));
    return @enumFromInt(n);
}
fn rejected(engine: *x.em.Engine, input: c.JSValue) !af.Action {
    try @import("native_async_body.zig").enterRejectedContinuation(engine);
    return .{ .thrown = c.JS_DupValue(engine.context, input) };
}
fn declaration(o: *x.Ops, module: c.JSValue, name: [*:0]const u8, length: c_int, body: af.Body) !c.JSValue { return o.own(try af.createResumable(o.s.engine, name, length, body, &.{module})); }
fn newError(o: *x.Ops, comptime message: anytype, args: anytype) !c.JSValue {
    const constructor = try o.global("Error");
    const description = try value(o, message, args);
    return duplicate(o, try x.guest.construct(o.s, constructor, &.{description}));
}
fn raise(o: *x.Ops, reason: c.JSValue) !c.JSValue { return o.s.engine.checked(c.JS_Throw(o.s.engine.context, reason)); }

// A Source finally keeps the pending completion alive while the cleanup runs.
// Ordinary cleanup failure replaces that completion; a real fatal event wins
// before any retained ordinary value is released.
fn releaseAction(completion: *x.owned.Completion, input: af.Action) void {
    switch (input) { .returned, .thrown => |entry| completion.release(entry), .awaited => unreachable }
}
fn finallyOwned(engine: *x.em.Engine, pending: af.Action, comptime body: anytype, args: anytype) !af.Action {
    var cleanup = x.owned.Completion.initVoid(engine, statement(engine, body, args));
    const completed = cleanup.finishAction() catch |err| {
        var fatal = x.owned.Completion.initAction(engine, @as(anyerror!af.Action, err));
        releaseAction(&fatal, pending);
        return fatal.finishAction();
    };
    return switch (completed) {
        .returned => |ignored| blk: {
            var outcome = x.owned.Completion.initAction(engine, pending);
            outcome.release(ignored);
            break :blk outcome.finishAction();
        },
        .thrown => blk: {
            var outcome = x.owned.Completion.initAction(engine, completed);
            releaseAction(&outcome, pending);
            break :blk outcome.finishAction();
        },
        .awaited => unreachable,
    };
}
fn typedObject(engine: *x.em.Engine, input: c.JSValue) bool {
    return c.JS_IsNull(input) or (c.JS_IsObject(input) and !c.JS_IsFunction(engine.context, input));
}
fn propertyIsObject(o: *x.Ops, receiver: c.JSValue, name: [*:0]const u8) !c.JSValue {
    return boolean(o, typedObject(o.s.engine, try o.get(receiver, name)));
}
fn isArray(o: *x.Ops, input: c.JSValue) !c.JSValue {
    return boolean(o, o.truthy(try o.invoke(try o.global("Array"), "isArray", &.{input})));
}
fn errorIsArray(o: *x.Ops, body: c.JSValue) !c.JSValue {
    const receiver = try o.global("Array");
    const method = try o.get(receiver, "isArray");
    return boolean(o, o.truthy(try o.call(method, receiver, &.{try o.get(body, "error")})));
}
fn nestedErrorMessage(o: *x.Ops, body: c.JSValue) !c.JSValue {
    return duplicate(o, try o.get(try o.get(body, "error"), "message"));
}
fn errorDetail(o: *x.Ops, body: c.JSValue) !c.JSValue {
    inline for (.{ "error_description", "message", "error" }) |name| {
        if (try truth(o, propertyIsString, .{body, @as([*:0]const u8, name)}))
            return expression(o.s.engine, property, .{body, @as([*:0]const u8, name)});
    }
    if (try truth(o, propertyTruthy, .{body, @as([*:0]const u8, "error")}) and
        try truth(o, propertyIsObject, .{body, @as([*:0]const u8, "error")}) and
        !try truth(o, errorIsArray, .{body}))
    {
        const message = try value(o, nestedErrorMessage, .{body});
        if (c.JS_IsString(message)) return duplicate(o, message);
    }
    return c.pi_js_undefined();
}
fn constructValue(o: *x.Ops, name: [*:0]const u8, input: c.JSValue) !c.JSValue {
    return duplicate(o, try x.guest.construct(o.s, try o.global(name), &.{input}));
}
fn constructEmpty(o: *x.Ops, name: [*:0]const u8) !c.JSValue {
    return duplicate(o, try x.guest.construct(o.s, try o.global(name), &.{}));
}
fn trimInput(o: *x.Ops, input: c.JSValue) !c.JSValue { return duplicate(o, try o.invoke(input, "trim", &.{})); }
fn urlSearchParams(o: *x.Ops, input: c.JSValue) !c.JSValue {
    const url = try value(o, constructValue, .{@as([*:0]const u8, "URL"), input});
    return duplicate(o, try o.get(url, "searchParams"));
}
fn parseUrlCode(o: *x.Ops, input: c.JSValue) !c.JSValue {
    const params = try value(o, urlSearchParams, .{input});
    // call_method retires its temporary receiver before the selected callee.
    const method = try o.get(params, "get");
    const code = try o.call(method, params, &.{try o.text("code")});
    return if (x.nullish(code)) c.pi_js_undefined() else duplicate(o, code);
}
fn includesCode(o: *x.Ops, input: c.JSValue) !c.JSValue {
    return boolean(o, o.truthy(try o.invoke(input, "includes", &.{try o.text("code=")})));
}
fn parseQueryCode(o: *x.Ops, input: c.JSValue) !c.JSValue {
    const params = try value(o, constructValue, .{@as([*:0]const u8, "URLSearchParams"), input});
    // call_method retires its temporary receiver before the selected callee.
    const method = try o.get(params, "get");
    const code = try o.call(method, params, &.{try o.text("code")});
    return if (x.nullish(code)) c.pi_js_undefined() else duplicate(o, code);
}
fn parseAuthorizationInput(o: *x.Ops, input: c.JSValue) !c.JSValue {
    const trimmed = try value(o, trimInput, .{input});
    if (!o.truthy(trimmed)) return c.pi_js_undefined();
    const parsed = try attempt(o.s.engine, parseUrlCode, .{trimmed});
    switch (parsed) {
        .returned => |code| return code,
        .thrown => |reason| try discard(o.s.engine, reason),
        .awaited => unreachable,
    }
    if (try truth(o, includesCode, .{trimmed})) return expression(o.s.engine, parseQueryCode, .{trimmed});
    return duplicate(o, trimmed);
}
fn callbackHost(o: *x.Ops, module: c.JSValue) !c.JSValue {
    const result = try o.call(try o.get(module, "getProviderEnvValue"), c.pi_js_undefined(), &.{try o.text("PI_OAUTH_CALLBACK_HOST")});
    return if (o.truthy(result)) duplicate(o, result) else duplicate(o, try o.text("127.0.0.1"));
}
pub fn create(engine: *x.em.Engine) !c.JSValue {
    try engine.checkNativeEntry();
    var frame: x.em.Engine.NativeInvocation = .{};
    engine.enterNativeInvocation(&frame);
    return x.finishInvocation(engine, &frame, expression(engine, createBody, .{}));
}
fn createBody(o: *x.Ops) !c.JSValue {
    const module = try o.cell();
    const pkce = try o.own(try @import("native_ai_oauth_pkce.zig").create(o.s.engine));
    try o.put(module, "generatePKCE", try o.get(pkce, "generatePKCE"));
    try o.put(module, "getProviderEnvValue", try o.own(try @import("native_provider_env.zig").create(o.s.engine)));
    try o.put(module, "exchangeAuthorizationCode", try declaration(o, module, "exchangeAuthorizationCode", 3, exchangeBody));
    const result = try o.object();
    try o.put(result, "name", try o.text("OpenRouter OAuth"));
    try o.put(result, "loginLabel", try o.text("Sign in with OpenRouter"));
    try o.put(result, "login", try declaration(o, module, "loginOpenRouter", 1, loginBody));
    try o.put(result, "refresh", try o.own(try af.create(o.s.engine, "refresh", 2, refreshCall, &.{})));
    try o.put(result, "toAuth", try o.own(try af.create(o.s.engine, "toAuth", 1, toAuthCall, &.{})));
    return duplicate(o, result);
}
fn refreshCall(engine: *x.em.Engine, _: c.JSValue, args: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
    return c.JS_DupValue(engine.context, x.arg(args, 0));
}
fn toAuthCall(engine: *x.em.Engine, _: c.JSValue, args: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
    return expression(engine, toAuth, .{x.arg(args, 0)});
}
fn toAuth(o: *x.Ops, credential: c.JSValue) !c.JSValue {
    const result = try o.object();
    try o.put(result, "apiKey", try o.get(credential, "access"));
    return duplicate(o, result);
}

fn abortCall(engine: *x.em.Engine, _: c.JSValue, _: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    return expression(engine, abortFromSignal, .{roots[0], roots[1]});
}
fn abortFromSignal(o: *x.Ops, controller: c.JSValue, signal: c.JSValue) !c.JSValue {
    const method = try o.get(controller, "abort");
    return duplicate(o, try o.call(method, controller, &.{try o.get(signal, "reason")}));
}
fn timeoutCall(engine: *x.em.Engine, _: c.JSValue, _: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    return expression(engine, abortFromTimeout, .{roots[0]});
}
fn abortFromTimeout(o: *x.Ops, controller: c.JSValue) !c.JSValue {
    const method = try o.get(controller, "abort");
    const reason = try value(o, newError, .{text, .{@as([]const u8, "OpenRouter OAuth token exchange timed out")}});
    return duplicate(o, try o.call(method, controller, &.{reason}));
}
fn addAbortListener(o: *x.Ops, signal: c.JSValue, on_abort: c.JSValue) !void {
    const method = try o.get(signal, "addEventListener");
    const event = try o.text("abort");
    const options = try o.object();
    try o.put(options, "once", boolean(o, true));
    _ = try o.call(method, signal, &.{event, on_abort, options});
}
fn setExchangeTimeout(o: *x.Ops, controller: c.JSValue) !c.JSValue {
    const method = try o.global("setTimeout");
    const callback = try o.own(try functions.createArrow(o.s.engine, "", 0, timeoutCall, &.{controller}));
    return duplicate(o, try o.call(method, c.pi_js_undefined(), &.{callback, integer(o, 30000)}));
}
fn clearExchangeTimeout(o: *x.Ops, timeout: c.JSValue) !void {
    _ = try o.call(try o.global("clearTimeout"), c.pi_js_undefined(), &.{timeout});
}
fn removeAbortListener(o: *x.Ops, signal: c.JSValue, on_abort: c.JSValue) !void {
    _ = try o.invoke(signal, "removeEventListener", &.{try o.text("abort"), on_abort});
}
fn exchangeCleanup(o: *x.Ops, owner: c.JSValue, signal: c.JSValue) !void {
    try statement(o.s.engine, clearExchangeTimeout, .{try o.get(owner, "timeout")});
    try statement(o.s.engine, removeAbortListener, .{signal, try o.get(owner, "onAbort")});
}
fn keyPayload(o: *x.Ops, code: c.JSValue, verifier: c.JSValue) !c.JSValue {
    const payload = try o.object();
    try o.put(payload, "code", code);
    try o.put(payload, "code_verifier", verifier);
    try o.put(payload, "code_challenge_method", try o.text("S256"));
    return duplicate(o, payload);
}
fn encodePayload(o: *x.Ops, code: c.JSValue, verifier: c.JSValue) !c.JSValue {
    const receiver = try o.global("JSON");
    const method = try o.get(receiver, "stringify");
    const payload = try value(o, keyPayload, .{code, verifier});
    return duplicate(o, try o.call(method, receiver, &.{payload}));
}
fn requestInit(o: *x.Ops, code: c.JSValue, verifier: c.JSValue, controller: c.JSValue) !c.JSValue {
    const init = try o.object();
    try o.put(init, "method", try o.text("POST"));
    const headers = try o.object();
    try o.put(headers, "accept", try o.text("application/json"));
    try o.put(headers, "content-type", try o.text("application/json"));
    try o.put(init, "headers", headers);
    try o.put(init, "body", try value(o, encodePayload, .{code, verifier}));
    try o.put(init, "signal", try o.get(controller, "signal"));
    return duplicate(o, init);
}
fn fetchKey(o: *x.Ops, code: c.JSValue, verifier: c.JSValue, controller: c.JSValue) !c.JSValue {
    const fetch = try o.global("fetch");
    const url = try o.text(token_url);
    const init = try value(o, requestInit, .{code, verifier, controller});
    return duplicate(o, try o.call(fetch, c.pi_js_undefined(), &.{url, init}));
}
fn invokeJson(o: *x.Ops, response: c.JSValue) !c.JSValue {
    return duplicate(o, try o.invoke(response, "json", &.{}));
}
fn recordParsed(o: *x.Ops, owner: c.JSValue, parsed: c.JSValue) !c.JSValue {
    // Unlike postForm in xAI, Source preserves the already-created empty body
    // when the parsed value is not a non-array object.
    try o.put(owner, "parsed", parsed);
    if (o.truthy(parsed) and typedObject(o.s.engine, parsed) and !try truth(o, isArray, .{parsed}))
        try o.put(owner, "body", parsed);
    return c.pi_js_undefined();
}
fn controllerAborted(o: *x.Ops, controller: c.JSValue) !c.JSValue {
    return boolean(o, o.truthy(try o.get(try o.get(controller, "signal"), "aborted")));
}
fn exchangeCatch(o: *x.Ops, owner: c.JSValue, signal: c.JSValue, reason: c.JSValue) !af.Action {
    // The named catch binding remains a local through finally and return.
    try o.put(owner, "error", reason);
    if (try truth(o, propertyTruthy, .{signal, @as([*:0]const u8, "aborted")}))
        return .{ .thrown = try expression(o.s.engine, newError, .{text, .{@as([]const u8, "Login cancelled")}}) };
    if (try truth(o, controllerAborted, .{try o.get(owner, "controller")}))
        return .{ .thrown = try expression(o.s.engine, newError, .{text, .{@as([]const u8, "OpenRouter OAuth token exchange timed out")}}) };
    return .{ .thrown = duplicate(o, reason) };
}
fn exchangeCaught(engine: *x.em.Engine, owner: c.JSValue, signal: c.JSValue, reason: c.JSValue) !af.Action {
    var result = x.owned.Completion.initAction(engine, actionExpression(engine, exchangeCatch, .{owner, signal, reason}));
    result.release(reason);
    return result.finishAction();
}
fn jsonCatch(o: *x.Ops, response: c.JSValue) !c.JSValue {
    if (try truth(o, propertyTruthy, .{response, @as([*:0]const u8, "ok")}))
        return raise(o, try expression(o.s.engine, newError, .{text, .{@as([]const u8, "OpenRouter OAuth returned invalid JSON")}}));
    return c.pi_js_undefined();
}
fn invalidKey(o: *x.Ops, body: c.JSValue) !c.JSValue {
    return boolean(o, c.JS_IsStrictEqual(o.s.engine.context, try o.get(try o.get(body, "key"), "length"), integer(o, 0)));
}
fn keyFailureMessage(o: *x.Ops, response: c.JSValue, detail: c.JSValue) !c.JSValue {
    var result = try concat(o, try o.text("OpenRouter OAuth key exchange failed (HTTP "), try value(o, propertyString, .{response, @as([*:0]const u8, "status")}));
    result = try concat(o, result, try o.text(")"));
    const suffix = if (o.truthy(detail)) try concat(o, try o.text(": "), try value(o, stringifyValue, .{detail})) else try o.text("");
    return duplicate(o, try concat(o, result, suffix));
}
fn tokenResult(o: *x.Ops, owner: c.JSValue) !c.JSValue {
    const response = try o.get(owner, "response");
    const body = try o.get(owner, "body");
    if (!try truth(o, propertyTruthy, .{response, @as([*:0]const u8, "ok")})) {
        const detail = try value(o, errorDetail, .{body});
        try o.put(owner, "detail", detail);
        return raise(o, try expression(o.s.engine, newError, .{keyFailureMessage, .{response, detail}}));
    }
    if (!try truth(o, propertyIsString, .{body, @as([*:0]const u8, "key")}) or try truth(o, invalidKey, .{body}))
        return raise(o, try expression(o.s.engine, newError, .{text, .{@as([]const u8, "OpenRouter OAuth response carries no \"key\"")}}));
    const result = try o.object();
    try o.put(result, "type", try o.text("oauth"));
    try o.put(result, "access", try o.get(body, "key"));
    try o.put(result, "refresh", try o.text(""));
    try o.put(result, "expires", try o.get(try o.global("Number"), "MAX_SAFE_INTEGER"));
    return duplicate(o, result);
}
fn finishExchange(engine: *x.em.Engine, owner: c.JSValue, signal: c.JSValue, pending: af.Action) !af.Action {
    const outcome = try finallyOwned(engine, pending, exchangeCleanup, .{owner, signal});
    return switch (outcome) {
        .thrown => outcome,
        .returned => |ignored| blk: {
            try discard(engine, ignored);
            break :blk .{ .returned = try expression(engine, tokenResult, .{owner}) };
        },
        .awaited => unreachable,
    };
}
fn exchangeFailure(engine: *x.em.Engine, owner: c.JSValue, signal: c.JSValue, reason: c.JSValue) !af.Action {
    return finishExchange(engine, owner, signal, try exchangeCaught(engine, owner, signal, reason));
}
fn jsonFailure(engine: *x.em.Engine, owner: c.JSValue, signal: c.JSValue, reason: c.JSValue) !af.Action {
    // No Source binding exists in this inner catch.
    try discard(engine, reason);
    const result = try attempt(engine, jsonCatchFromOwner, .{owner});
    return switch (result) {
        .returned => finishExchange(engine, owner, signal, result),
        .thrown => |failure| exchangeFailure(engine, owner, signal, failure),
        .awaited => unreachable,
    };
}
fn jsonCatchFromOwner(o: *x.Ops, owner: c.JSValue) !c.JSValue {
    return expression(o.s.engine, jsonCatch, .{try o.get(owner, "response")});
}
fn exchangeBody(engine: *x.em.Engine, _: c.JSValue, args: []const c.JSValue, _: []const c.JSValue, state: *c.JSValue, completion: af.Completion, input: c.JSValue) !af.Action {
    if (completion == .rejected) try @import("native_async_body.zig").enterRejectedContinuation(engine);
    return actionExpression(engine, exchangeAdvance, .{args, state, completion, input});
}
fn exchangeAdvance(o: *x.Ops, args: []const c.JSValue, state: *c.JSValue, completion: af.Completion, input: c.JSValue) !af.Action {
    const signal = x.arg(args, 2);
    if (completion == .start) {
        const owner = try initialize(o, state);
        inline for (.{ "controller", "onAbort", "timeout", "response", "body", "parsed", "error", "detail" }) |name|
            try o.put(owner, name, c.pi_js_undefined());
        if (try truth(o, propertyTruthy, .{signal, @as([*:0]const u8, "aborted")}))
            return .{ .thrown = try expression(o.s.engine, newError, .{text, .{@as([]const u8, "Login cancelled")}}) };
        const controller = try value(o, constructEmpty, .{@as([*:0]const u8, "AbortController")});
        try o.put(owner, "controller", controller);
        const on_abort = try o.own(try functions.createArrow(o.s.engine, "onAbort", 0, abortCall, &.{controller, signal}));
        try o.put(owner, "onAbort", on_abort);
        try statement(o.s.engine, addAbortListener, .{signal, on_abort});
        try o.put(owner, "timeout", try value(o, setExchangeTimeout, .{controller}));
        try o.put(owner, "body", try o.object());
        try setStage(o, owner, .exchange_response);
        // The Source try region starts at fetch, after listener/timer setup.
        const response = try attempt(o.s.engine, fetchKey, .{x.arg(args, 0), x.arg(args, 1), controller});
        return switch (response) {
            .returned => |promise| .{ .awaited = promise },
            .thrown => |reason| exchangeFailure(o.s.engine, owner, signal, reason),
            .awaited => unreachable,
        };
    }
    switch (try getStage(o, state.*)) {
        .exchange_response => {
            if (completion == .rejected) return exchangeFailure(o.s.engine, state.*, signal, duplicate(o, input));
            try o.put(state.*, "response", input);
            try setStage(o, state.*, .exchange_json);
            const parsed = try attempt(o.s.engine, invokeJson, .{input});
            return switch (parsed) {
                .returned => |promise| .{ .awaited = promise },
                .thrown => |reason| jsonFailure(o.s.engine, state.*, signal, reason),
                .awaited => unreachable,
            };
        },
        .exchange_json => {
            if (completion == .rejected) return jsonFailure(o.s.engine, state.*, signal, duplicate(o, input));
            const parsed = try attempt(o.s.engine, recordParsed, .{state.*, input});
            return switch (parsed) {
                .returned => finishExchange(o.s.engine, state.*, signal, parsed),
                .thrown => |reason| jsonFailure(o.s.engine, state.*, signal, reason),
                .awaited => unreachable,
            };
        },
        else => unreachable,
    }
}

fn invokePkce(o: *x.Ops, module: c.JSValue) !c.JSValue {
    return duplicate(o, try o.call(try o.get(module, "generatePKCE"), c.pi_js_undefined(), &.{}));
}
fn randomUuid(o: *x.Ops) !c.JSValue { return duplicate(o, try o.invoke(try o.global("crypto"), "randomUUID", &.{})); }
fn callbackPath(o: *x.Ops) !c.JSValue {
    const id = try value(o, randomUuid, .{});
    return duplicate(o, try concat(o, try o.text("/oauth/callback/"), try value(o, stringifyValue, .{id})));
}
fn completeCall(engine: *x.em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    return expression(engine, completeCode, .{roots[0], x.arg(args, 0), roots[1], roots[2]});
}
fn completeCode(o: *x.Ops, module: c.JSValue, code: c.JSValue, verifier: c.JSValue, interaction: c.JSValue) !c.JSValue {
    const callable = try o.get(module, "exchangeAuthorizationCode");
    return duplicate(o, try o.call(callable, c.pi_js_undefined(), &.{code, verifier, try o.get(interaction, "signal")}));
}
fn callbackOptions(o: *x.Ops, module: c.JSValue, interaction: c.JSValue, verifier: c.JSValue) !c.JSValue {
    const options = try o.object();
    try o.put(options, "providerName", try o.text("OpenRouter"));
    try o.put(options, "host", try value(o, callbackHost, .{module}));
    try o.put(options, "port", integer(o, 0));
    try o.put(options, "path", try value(o, callbackPath, .{}));
    const complete = try o.own(try functions.createArrow(o.s.engine, "complete", 1, completeCall, &.{module, verifier, interaction}));
    try o.put(options, "complete", complete);
    try o.put(options, "signal", try o.get(interaction, "signal"));
    try o.put(options, "timeoutMs", integer(o, 300000));
    return duplicate(o, options);
}
fn startCallback(o: *x.Ops, module: c.JSValue, interaction: c.JSValue, verifier: c.JSValue) !c.JSValue {
    const options = try value(o, callbackOptions, .{module, interaction, verifier});
    return callback_server.start(o.s.engine, options);
}
fn authorizationFields(o: *x.Ops, callback: c.JSValue, challenge: c.JSValue) !c.JSValue {
    const fields = try o.object();
    try o.put(fields, "callback_url", try o.get(callback, "redirectUri"));
    try o.put(fields, "code_challenge", challenge);
    try o.put(fields, "code_challenge_method", try o.text("S256"));
    return duplicate(o, fields);
}
fn authorizationParams(o: *x.Ops, callback: c.JSValue, challenge: c.JSValue) !c.JSValue {
    const constructor = try o.global("URLSearchParams");
    const fields = try value(o, authorizationFields, .{callback, challenge});
    return duplicate(o, try x.guest.construct(o.s, constructor, &.{fields}));
}
fn authorizationSearch(o: *x.Ops, callback: c.JSValue, challenge: c.JSValue) !c.JSValue {
    const params = try value(o, authorizationParams, .{callback, challenge});
    return duplicate(o, try o.invoke(params, "toString", &.{}));
}
fn setAuthorizationSearch(o: *x.Ops, url: c.JSValue, callback: c.JSValue, challenge: c.JSValue) !void {
    try x.guest.set(o.s, url, "search", try value(o, authorizationSearch, .{callback, challenge}));
}
fn listeningMessage(o: *x.Ops, callback: c.JSValue) !c.JSValue {
    return duplicate(o, try concat(o, try o.text("Listening for OpenRouter OAuth callback on "), try value(o, propertyString, .{callback, @as([*:0]const u8, "redirectUri")})));
}
fn listeningNotice(o: *x.Ops, callback: c.JSValue) !c.JSValue {
    const event = try o.object();
    try o.put(event, "type", try o.text("progress"));
    try o.put(event, "message", try value(o, listeningMessage, .{callback}));
    return duplicate(o, event);
}
fn authorizationUrl(o: *x.Ops, url: c.JSValue) !c.JSValue { return duplicate(o, try o.invoke(url, "toString", &.{})); }
fn authorizationNotice(o: *x.Ops, url: c.JSValue) !c.JSValue {
    const event = try o.object();
    try o.put(event, "type", try o.text("auth_url"));
    try o.put(event, "url", try value(o, authorizationUrl, .{url}));
    try o.put(event, "instructions", try o.text("Complete sign-in in your browser. If the browser is on another machine, paste the final redirect URL here."));
    return duplicate(o, event);
}
fn exchangeNotice(o: *x.Ops) !c.JSValue {
    const event = try o.object();
    try o.put(event, "type", try o.text("progress"));
    try o.put(event, "message", try o.text("Exchanging authorization code for an API key..."));
    return duplicate(o, event);
}
fn notify(o: *x.Ops, interaction: c.JSValue, comptime notice: anytype, args: anytype) !void {
    const callable = try o.get(interaction, "notify");
    const event = try value(o, notice, args);
    _ = try o.call(callable, interaction, &.{event});
}
fn manualPrompt(o: *x.Ops, callback: c.JSValue) !c.JSValue {
    const prompt = try o.object();
    try o.put(prompt, "message", try o.text("Complete sign-in in your browser, or paste the authorization code / redirect URL here:"));
    try o.put(prompt, "placeholder", try o.get(callback, "redirectUri"));
    return duplicate(o, prompt);
}
fn waitForInput(o: *x.Ops, interaction: c.JSValue, callback: c.JSValue) !c.JSValue {
    const prompt = try value(o, manualPrompt, .{callback});
    return callback_server.waitForCallbackOrManualInput(o.s.engine, interaction, callback, prompt);
}
fn closeCallback(o: *x.Ops, callback: c.JSValue) !void {
    _ = try o.invoke(callback, "close", &.{});
}
fn parseResultInput(o: *x.Ops, result: c.JSValue) !c.JSValue {
    return expression(o.s.engine, parseAuthorizationInput, .{try o.get(result, "input")});
}
fn loginTry(o: *x.Ops, module: c.JSValue, interaction: c.JSValue, owner: c.JSValue, stage: Stage, completion: af.Completion, input: c.JSValue) !af.Action {
    if (completion == .rejected) return .{ .thrown = duplicate(o, input) };
    const callback = try o.get(owner, "callback");
    switch (stage) {
        .login_callback => {
            const url = try value(o, constructValue, .{@as([*:0]const u8, "URL"), try o.text(authorize_url)});
            try o.put(owner, "authorizeUrl", url);
            try statement(o.s.engine, setAuthorizationSearch, .{url, callback, try o.get(owner, "challenge")});
            try statement(o.s.engine, notify, .{interaction, listeningNotice, .{callback}});
            try statement(o.s.engine, notify, .{interaction, authorizationNotice, .{url}});
            try setStage(o, owner, .login_input);
            return .{ .awaited = try expression(o.s.engine, waitForInput, .{interaction, callback}) };
        },
        .login_input => {
            try o.put(owner, "result", input);
            if (try truth(o, propertyEqualsText, .{input, @as([*:0]const u8, "type"), @as([]const u8, "callback")}))
                return .{ .returned = try expression(o.s.engine, property, .{input, @as([*:0]const u8, "value")}) };
            const code = try value(o, parseResultInput, .{input});
            try o.put(owner, "code", code);
            if (!o.truthy(code))
                return .{ .thrown = try expression(o.s.engine, newError, .{text, .{@as([]const u8, "Missing authorization code")}}) };
            try statement(o.s.engine, notify, .{interaction, exchangeNotice, .{}});
            try setStage(o, owner, .login_exchange);
            return .{ .awaited = try expression(o.s.engine, completeCode, .{module, code, try o.get(owner, "verifier"), interaction}) };
        },
        .login_exchange => return .{ .returned = duplicate(o, input) },
        else => unreachable,
    }
}
fn loginBody(engine: *x.em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue, state: *c.JSValue, completion: af.Completion, input: c.JSValue) !af.Action {
    if (completion == .rejected) try @import("native_async_body.zig").enterRejectedContinuation(engine);
    return actionExpression(engine, loginAdvance, .{roots[0], x.arg(args, 0), state, completion, input});
}
fn bindPkce(o: *x.Ops, owner: c.JSValue, input: c.JSValue) !void {
    // A Source object BindingPattern boxes a primitive once for both reads.
    const receiver = try x.guest.toObject(o.s, input);
    try o.put(owner, "verifier", try o.get(receiver, "verifier"));
    try o.put(owner, "challenge", try o.get(receiver, "challenge"));
}
fn loginAdvance(o: *x.Ops, module: c.JSValue, interaction: c.JSValue, state: *c.JSValue, completion: af.Completion, input: c.JSValue) !af.Action {
    if (completion == .start) {
        const owner = try initialize(o, state);
        inline for (.{ "verifier", "challenge", "callback", "authorizeUrl", "result", "code" }) |name|
            try o.put(owner, name, c.pi_js_undefined());
        try setStage(o, owner, .login_pkce);
        return .{ .awaited = try expression(o.s.engine, invokePkce, .{module}) };
    }
    const stage = try getStage(o, state.*);
    if (stage == .login_pkce) {
        if (completion == .rejected) return .{ .thrown = duplicate(o, input) };
        try statement(o.s.engine, bindPkce, .{state.*, input});
        try setStage(o, state.*, .login_callback);
        return .{ .awaited = try expression(o.s.engine, startCallback, .{module, interaction, try o.get(state.*, "verifier")}) };
    }
    if (stage == .login_callback) {
        // The Source try/finally begins only after the start-server Await.
        if (completion == .rejected) return .{ .thrown = duplicate(o, input) };
        try o.put(state.*, "callback", input);
    }
    const outcome = try actionExpression(o.s.engine, loginTry, .{module, interaction, state.*, stage, completion, input});
    return switch (outcome) {
        .awaited => outcome,
        .returned, .thrown => finallyOwned(o.s.engine, outcome, closeCallback, .{try o.get(state.*, "callback")}),
    };
}

/// Test projection of the actual private Source bodies. The production provider
/// still obtains exchangeAuthorizationCode from its own retained module owner.
pub fn createTestInternals(engine: *x.em.Engine) !c.JSValue {
    if (!@import("builtin").is_test) @compileError("OpenRouter private projection is only available to native controls");
    try engine.checkNativeEntry();
    var frame: x.em.Engine.NativeInvocation = .{};
    engine.enterNativeInvocation(&frame);
    return x.finishInvocation(engine, &frame, expression(engine, testInternals, .{}));
}
fn testInternals(o: *x.Ops) !c.JSValue {
    const result = try o.object();
    try o.put(result, "exchangeAuthorizationCode", try o.own(try af.createResumable(o.s.engine, "exchangeAuthorizationCode", 3, exchangeBody, &.{})));
    try o.put(result, "parseAuthorizationInput", try o.own(try functions.create(o.s.engine, "parseAuthorizationInput", 1, parseInputCall, &.{})));
    try o.put(result, "errorDetail", try o.own(try functions.create(o.s.engine, "errorDetail", 1, errorDetailCall, &.{})));
    try o.put(result, "refresh", try o.own(try af.create(o.s.engine, "refresh", 2, refreshCall, &.{})));
    try o.put(result, "toAuth", try o.own(try af.create(o.s.engine, "toAuth", 1, toAuthCall, &.{})));
    return duplicate(o, result);
}
fn parseInputCall(engine: *x.em.Engine, _: c.JSValue, args: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
    return expression(engine, parseAuthorizationInput, .{x.arg(args, 0)});
}
fn errorDetailCall(engine: *x.em.Engine, _: c.JSValue, args: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
    return expression(engine, errorDetail, .{x.arg(args, 0)});
}
