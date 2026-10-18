//! c268154c auth/oauth/xai.ts: genuine nested async bodies and Source Await.
//! Device authorization, token polling and refresh share the actual postForm body.
const x = @import("native_ai_auth_helper_values.zig");
const c = x.c;
const af = x.af;
const functions = @import("native_node_function.zig");
const client_id = "b1a00492-073a-47ea-816f-4c329264a828";
const request_scope = "openid profile email offline_access grok-cli:access api:access";
const device_url = "https://auth.x.ai/oauth2/device/code";
const token_url = "https://auth.x.ai/oauth2/token";
const Stage = enum(i32) { post_response, post_json };

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
fn text(o: *x.Ops, input: []const u8) !c.JSValue { return duplicate(o, try o.text(input)); }
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
fn finite(o: *x.Ops, input: c.JSValue) !c.JSValue { return boolean(o, o.truthy(try o.invoke(try o.global("Number"), "isFinite", &.{input}))); }
fn finitePositive(o: *x.Ops, input: c.JSValue) !bool {
    return c.JS_IsNumber(input) and try truth(o, finite, .{input}) and o.truthy(try o.binary(6, input, integer(o, 0)));
}
fn invalidField(o: *x.Ops, name: [*:0]const u8) !c.JSValue {
    return duplicate(o, try concat(o, try o.text("Invalid xAI OAuth response field: "), try o.text(@import("std").mem.span(name))));
}
fn requiredString(o: *x.Ops, body: c.JSValue, name: [*:0]const u8) !c.JSValue {
    const field_value = try o.get(body, name);
    if (!c.JS_IsString(field_value) or c.JS_IsStrictEqual(o.s.engine.context, try o.get(field_value, "length"), integer(o, 0)))
        return raise(o, try expression(o.s.engine, newError, .{invalidField, .{name}}));
    return duplicate(o, field_value);
}
fn positiveNumber(o: *x.Ops, body: c.JSValue, name: [*:0]const u8) !c.JSValue {
    const field_value = try o.get(body, name);
    if (!c.JS_IsNumber(field_value) or !try truth(o, finite, .{field_value}) or o.truthy(try o.binary(5, field_value, integer(o, 0))))
        return raise(o, try expression(o.s.engine, newError, .{invalidField, .{name}}));
    return duplicate(o, field_value);
}
fn newUrl(o: *x.Ops, raw: c.JSValue) !c.JSValue { return duplicate(o, try x.guest.construct(o.s, try o.global("URL"), &.{raw})); }
fn untrusted(o: *x.Ops) !c.JSValue { return raise(o, try expression(o.s.engine, newError, .{text, .{@as([]const u8, "Untrusted verification URI in xAI OAuth response")}})); }
fn validateUri(o: *x.Ops, raw: c.JSValue) !c.JSValue {
    // Source catches only URL construction, not the following live protocol/href gets.
    const outcome = try attempt(o.s.engine, newUrl, .{raw});
    const url = switch (outcome) {
        .returned => |result| try o.own(result),
        .thrown => |reason| { try discard(o.s.engine, reason); return untrusted(o); },
        .awaited => unreachable,
    };
    if (!try truth(o, propertyEqualsText, .{url, @as([*:0]const u8, "protocol"), @as([]const u8, "https:")})) return untrusted(o);
    return duplicate(o, try o.get(url, "href"));
}
fn propertyLength(o: *x.Ops, body: c.JSValue, name: [*:0]const u8) !c.JSValue { return duplicate(o, try o.get(try o.get(body, name), "length")); }
fn nonemptyProperty(o: *x.Ops, body: c.JSValue, name: [*:0]const u8) !c.JSValue {
    return duplicate(o, try o.binary(6, try value(o, propertyLength, .{body, name}), integer(o, 0)));
}
fn validateProperty(o: *x.Ops, body: c.JSValue, name: [*:0]const u8) !c.JSValue {
    return duplicate(o, try value(o, validateUri, .{try o.get(body, name)}));
}
fn requiredUri(o: *x.Ops, body: c.JSValue, name: [*:0]const u8) !c.JSValue {
    return duplicate(o, try value(o, validateUri, .{try value(o, requiredString, .{body, name})}));
}
fn parseDeviceCode(o: *x.Ops, body: c.JSValue) !c.JSValue {
    const interval = try o.get(body, "interval");
    const interval_seconds = if (try finitePositive(o, interval)) interval else c.pi_js_undefined();
    const complete = if (try truth(o, propertyIsString, .{body, @as([*:0]const u8, "verification_uri_complete")}) and
        try truth(o, nonemptyProperty, .{body, @as([*:0]const u8, "verification_uri_complete")}))
        try value(o, validateProperty, .{body, @as([*:0]const u8, "verification_uri_complete")}) else c.pi_js_undefined();
    const result = try o.object();
    try o.put(result, "deviceCode", try value(o, requiredString, .{body, @as([*:0]const u8, "device_code")}));
    try o.put(result, "userCode", try value(o, requiredString, .{body, @as([*:0]const u8, "user_code")}));
    try o.put(result, "verificationUri", try value(o, requiredUri, .{body, @as([*:0]const u8, "verification_uri")}));
    try o.put(result, "verificationUriComplete", complete);
    try o.put(result, "intervalSeconds", interval_seconds);
    try o.put(result, "expiresInSeconds", try value(o, positiveNumber, .{body, @as([*:0]const u8, "expires_in")}));
    return duplicate(o, result);
}
fn tokenNow(o: *x.Ops) !c.JSValue { return duplicate(o, try o.invoke(try o.global("Date"), "now", &.{})); }
fn tokenSum(o: *x.Ops, expires: c.JSValue) !c.JSValue {
    const now = try value(o, tokenNow, .{});
    return duplicate(o, try o.binary(0, now, try o.binary(2, expires, integer(o, 1000))));
}
fn tokenExpiry(o: *x.Ops, expires: c.JSValue) !c.JSValue {
    return duplicate(o, try o.binary(1, try value(o, tokenSum, .{expires}), integer(o, 300000)));
}
fn credentials(o: *x.Ops, body: c.JSValue, previous: c.JSValue) !c.JSValue {
    const access = try value(o, requiredString, .{body, @as([*:0]const u8, "access_token")});
    const refresh_token = if (try truth(o, propertyUndefined, .{body, @as([*:0]const u8, "refresh_token")}) and o.truthy(previous))
        try o.own(duplicate(o, previous)) else try value(o, requiredString, .{body, @as([*:0]const u8, "refresh_token")});
    const expires = if (try truth(o, propertyUndefined, .{body, @as([*:0]const u8, "expires_in")})) integer(o, 3600) else
        try value(o, positiveNumber, .{body, @as([*:0]const u8, "expires_in")});
    const result = try o.object();
    try o.put(result, "type", try o.text("oauth"));
    try o.put(result, "access", access);
    try o.put(result, "refresh", refresh_token);
    try o.put(result, "expires", try value(o, tokenExpiry, .{expires}));
    return duplicate(o, result);
}
fn responseField(o: *x.Ops, response: c.JSValue, name: [*:0]const u8) !c.JSValue { return duplicate(o, try o.get(try o.get(response, "body"), name)); }
fn responseFieldIsString(o: *x.Ops, response: c.JSValue, name: [*:0]const u8) !c.JSValue { return boolean(o, c.JS_IsString(try value(o, responseField, .{response, name}))); }
fn responseStringOrUndefined(o: *x.Ops, response: c.JSValue, name: [*:0]const u8) !c.JSValue {
    return if (try truth(o, responseFieldIsString, .{response, name})) expression(o.s.engine, responseField, .{response, name}) else c.pi_js_undefined();
}
fn filterDetails(o: *x.Ops, code: c.JSValue, description: c.JSValue) !c.JSValue {
    const entries = try array(o);
    try x.guest.index(o.s, entries, 0, code);
    try x.guest.index(o.s, entries, 1, description);
    const filter = try o.get(entries, "filter");
    return duplicate(o, try o.call(filter, entries, &.{try o.global("Boolean")}));
}
fn joinDetails(o: *x.Ops, code: c.JSValue, description: c.JSValue) !c.JSValue {
    const filtered = try value(o, filterDetails, .{code, description});
    return duplicate(o, try o.invoke(filtered, "join", &.{try o.text(": ")}));
}
fn failureDescription(o: *x.Ops, action: []const u8, response: c.JSValue, detail: c.JSValue) !c.JSValue {
    var message = try concat(o, try o.text("xAI OAuth "), try o.text(action));
    message = try concat(o, message, try o.text(" failed (HTTP "));
    message = try concat(o, message, try value(o, propertyString, .{response, @as([*:0]const u8, "status")}));
    message = try concat(o, message, try o.text(")"));
    if (o.truthy(detail)) message = try concat(o, message, try concat(o, try o.text(": "), try value(o, stringifyValue, .{detail})));
    return duplicate(o, message);
}
fn requestFailure(o: *x.Ops, action: []const u8, response: c.JSValue) !c.JSValue {
    const code = try value(o, responseStringOrUndefined, .{response, @as([*:0]const u8, "error")});
    const description = try value(o, responseStringOrUndefined, .{response, @as([*:0]const u8, "error_description")});
    const detail = try value(o, joinDetails, .{code, description});
    return expression(o.s.engine, newError, .{failureDescription, .{action, response, detail}});
}
fn failureMessage(o: *x.Ops, response: c.JSValue) !c.JSValue {
    const failure = try value(o, requestFailure, .{@as([]const u8, "device token polling"), response});
    return duplicate(o, try o.get(failure, "message"));
}

pub fn create(engine: *x.em.Engine) !c.JSValue {
    try engine.checkNativeEntry();
    var frame: x.em.Engine.NativeInvocation = .{};
    engine.enterNativeInvocation(&frame);
    return x.finishInvocation(engine, &frame, expression(engine, createBody, .{}));
}
fn createBody(o: *x.Ops) !c.JSValue {
    const module = try o.cell();
    const device = try o.own(try @import("native_ai_oauth_device_code.zig").create(o.s.engine));
    try o.put(module, "pollDevice", try o.get(device, "pollOAuthDeviceCodeFlow"));
    try o.put(module, "postForm", try declaration(o, module, "postForm", 3, postFormBody));
    try o.put(module, "requestDeviceCode", try declaration(o, module, "requestDeviceCode", 1, requestDeviceBody));
    try o.put(module, "pollForTokens", try declaration(o, module, "pollForTokens", 2, pollForTokensBody));
    try o.put(module, "refreshXaiToken", try declaration(o, module, "refreshXaiToken", 2, refreshTokenBody));
    const exports = try o.object();
    try o.put(exports, "name", try o.text("xAI (Grok/X subscription)"));
    try o.put(exports, "isSubscription", boolean(o, true));
    try o.put(exports, "loginLabel", try o.text("Sign in with SuperGrok or X Premium"));
    try o.put(exports, "login", try declaration(o, module, "loginXai", 1, loginBody));
    try o.put(exports, "refresh", try o.own(try functions.createArrow(o.s.engine, "refresh", 2, refreshCall, &.{module})));
    try o.put(exports, "toAuth", try o.own(try af.create(o.s.engine, "toAuth", 1, toAuthCall, &.{})));
    return duplicate(o, exports);
}
fn toAuthCall(engine: *x.em.Engine, _: c.JSValue, args: []const c.JSValue, _: []const c.JSValue) !c.JSValue { return expression(engine, toAuth, .{x.arg(args, 0)}); }
fn toAuth(o: *x.Ops, input_credential: c.JSValue) !c.JSValue {
    const result = try o.object();
    try o.put(result, "apiKey", try o.get(input_credential, "access"));
    return duplicate(o, result);
}
fn refreshCall(engine: *x.em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    return expression(engine, refresh, .{roots[0], x.arg(args, 0), x.arg(args, 1)});
}
fn refresh(o: *x.Ops, module: c.JSValue, input_credential: c.JSValue, signal: c.JSValue) !c.JSValue {
    const callback = try o.get(module, "refreshXaiToken");
    return duplicate(o, try o.call(callback, c.pi_js_undefined(), &.{try o.get(input_credential, "refresh"), signal}));
}
fn formParameters(o: *x.Ops, field_values: c.JSValue) !c.JSValue {
    return duplicate(o, try x.guest.construct(o.s, try o.global("URLSearchParams"), &.{field_values}));
}
fn formInit(o: *x.Ops, field_values: c.JSValue, signal: c.JSValue) !c.JSValue {
    const init = try o.object();
    try o.put(init, "method", try o.text("POST"));
    const headers = try o.object();
    try o.put(headers, "Accept", try o.text("application/json"));
    try o.put(headers, "Content-Type", try o.text("application/x-www-form-urlencoded"));
    try o.put(init, "headers", headers);
    // The URLSearchParams constructor retires before the following signal field.
    try o.put(init, "body", try value(o, formParameters, .{field_values}));
    try o.put(init, "signal", signal);
    return duplicate(o, init);
}
fn fetchForm(o: *x.Ops, url: c.JSValue, field_values: c.JSValue, signal: c.JSValue) !c.JSValue {
    const fetch = try o.global("fetch");
    // Complete the init argument before entering fetch: only its own property
    // roots keep headers/body alive when the guest deletes those properties.
    const init = try value(o, formInit, .{field_values, signal});
    return duplicate(o, try o.call(fetch, c.pi_js_undefined(), &.{url, init}));
}
fn invokeJson(o: *x.Ops, response: c.JSValue) !c.JSValue { return duplicate(o, try o.invoke(response, "json", &.{})); }
fn isArray(o: *x.Ops, input: c.JSValue) !c.JSValue { return boolean(o, o.truthy(try o.invoke(try o.global("Array"), "isArray", &.{input}))); }
fn normalizeJson(o: *x.Ops, parsed: c.JSValue) !c.JSValue {
    return if (o.truthy(parsed) and c.JS_IsObject(parsed) and !c.JS_IsFunction(o.s.engine.context, parsed) and !try truth(o, isArray, .{parsed}))
        duplicate(o, parsed) else duplicate(o, try o.object());
}
fn invalidJsonMessage(o: *x.Ops, response: c.JSValue) !c.JSValue {
    const prefix = try concat(o, try o.text("xAI OAuth returned invalid JSON (HTTP "), try value(o, propertyString, .{response, @as([*:0]const u8, "status")}));
    return duplicate(o, try concat(o, prefix, try o.text(")")));
}
fn fetchCaught(o: *x.Ops, owner: c.JSValue, signal: c.JSValue, reason: c.JSValue) !af.Action {
    // Source's catch binding remains a local until this invocation exits.
    try o.put(owner, "error", reason);
    if (try truth(o, propertyTruthy, .{signal, @as([*:0]const u8, "aborted")}))
        return .{ .thrown = try expression(o.s.engine, newError, .{text, .{@as([]const u8, "Login cancelled")}}) };
    return .{ .thrown = duplicate(o, reason) };
}
fn fetchFailure(engine: *x.em.Engine, owner: c.JSValue, signal: c.JSValue, reason: c.JSValue) !af.Action {
    var completion = x.owned.Completion.initAction(engine, actionExpression(engine, fetchCaught, .{owner, signal, reason}));
    completion.release(reason);
    return completion.finishAction();
}
fn jsonCaught(o: *x.Ops, response: c.JSValue, signal: c.JSValue) !af.Action {
    if (try truth(o, propertyTruthy, .{signal, @as([*:0]const u8, "aborted")}))
        return .{ .thrown = try expression(o.s.engine, newError, .{text, .{@as([]const u8, "Login cancelled")}}) };
    return .{ .thrown = try expression(o.s.engine, newError, .{invalidJsonMessage, .{response}}) };
}
fn jsonFailure(engine: *x.em.Engine, response: c.JSValue, signal: c.JSValue, reason: c.JSValue) !af.Action {
    // Empty catch drops its ordinary reason before its first signal getter.
    try discard(engine, reason);
    return actionExpression(engine, jsonCaught, .{response, signal});
}
fn httpResponse(o: *x.Ops, response: c.JSValue, body: c.JSValue) !c.JSValue {
    const result = try o.object();
    try o.put(result, "ok", try o.get(response, "ok"));
    try o.put(result, "status", try o.get(response, "status"));
    try o.put(result, "body", body);
    return duplicate(o, result);
}
fn postFormBody(engine: *x.em.Engine, _: c.JSValue, args: []const c.JSValue, _: []const c.JSValue, state: *c.JSValue, completion: af.Completion, input: c.JSValue) !af.Action {
    if (completion == .rejected) try @import("native_async_body.zig").enterRejectedContinuation(engine);
    return actionExpression(engine, postFormAdvance, .{args, state, completion, input});
}
fn postFormAdvance(o: *x.Ops, args: []const c.JSValue, state: *c.JSValue, completion: af.Completion, input: c.JSValue) !af.Action {
    const signal = x.arg(args, 2);
    if (completion == .start) {
        const owner = try initialize(o, state);
        try setStage(o, owner, .post_response);
        // BCDF local declaration/retirement order, including the catch binding.
        inline for (.{ "response", "error", "body", "parsed" }) |name| try o.put(owner, name, c.pi_js_undefined());
        const result = try attempt(o.s.engine, fetchForm, .{x.arg(args, 0), x.arg(args, 1), signal});
        return switch (result) {
            .returned => |promise| .{ .awaited = promise },
            .thrown => |reason| try fetchFailure(o.s.engine, owner, signal, reason),
            .awaited => unreachable,
        };
    }
    switch (try getStage(o, state.*)) {
        .post_response => {
            if (completion == .rejected) return fetchFailure(o.s.engine, state.*, signal, duplicate(o, input));
            try o.put(state.*, "response", input);
            try setStage(o, state.*, .post_json);
            const result = try attempt(o.s.engine, invokeJson, .{input});
            return switch (result) {
                .returned => |promise| .{ .awaited = promise },
                .thrown => |reason| try jsonFailure(o.s.engine, input, signal, reason),
                .awaited => unreachable,
            };
        },
        .post_json => {
            const response = try o.get(state.*, "response");
            if (completion == .rejected) return jsonFailure(o.s.engine, response, signal, duplicate(o, input));
            try o.put(state.*, "parsed", input);
            const result = try attempt(o.s.engine, normalizeJson, .{input});
            switch (result) {
                .returned => |body| try o.put(state.*, "body", try o.own(body)),
                .thrown => |reason| return jsonFailure(o.s.engine, response, signal, reason),
                .awaited => unreachable,
            }
            // The final ok/status getters are outside both Source catch blocks.
            return .{ .returned = try expression(o.s.engine, httpResponse, .{response, try o.get(state.*, "body")}) };
        },
    }
}
const Request = enum { device, poll, refresh };
fn requestFields(o: *x.Ops, kind: Request, source: c.JSValue) !c.JSValue {
    const result = try o.object();
    switch (kind) {
        .device => {
            try o.put(result, "client_id", try o.text(client_id));
            try o.put(result, "scope", try o.text(request_scope));
            try o.put(result, "referrer", try o.text("pi"));
        },
        .poll => {
            try o.put(result, "grant_type", try o.text("urn:ietf:params:oauth:grant-type:device_code"));
            try o.put(result, "client_id", try o.text(client_id));
            try o.put(result, "device_code", try o.get(source, "deviceCode"));
        },
        .refresh => {
            try o.put(result, "grant_type", try o.text("refresh_token"));
            try o.put(result, "client_id", try o.text(client_id));
            try o.put(result, "refresh_token", source);
        },
    }
    return duplicate(o, result);
}
fn post(o: *x.Ops, module: c.JSValue, kind: Request, source: c.JSValue, signal: c.JSValue) !c.JSValue {
    const callback = try o.get(module, "postForm");
    const url = try o.text(if (kind == .device) device_url else token_url);
    const field_values = try value(o, requestFields, .{kind, source});
    return duplicate(o, try o.call(callback, c.pi_js_undefined(), &.{url, field_values, signal}));
}
fn parseResponse(o: *x.Ops, response: c.JSValue) !c.JSValue {
    return duplicate(o, try value(o, parseDeviceCode, .{try o.get(response, "body")}));
}
fn responseCredentials(o: *x.Ops, response: c.JSValue, previous: c.JSValue) !c.JSValue {
    return duplicate(o, try value(o, credentials, .{try o.get(response, "body"), previous}));
}
fn requestDeviceBody(engine: *x.em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue, state: *c.JSValue, completion: af.Completion, input: c.JSValue) !af.Action {
    if (completion == .rejected) return rejected(engine, input);
    return actionExpression(engine, requestDeviceAdvance, .{roots[0], x.arg(args, 0), state, completion, input});
}
fn requestDeviceAdvance(o: *x.Ops, module: c.JSValue, signal: c.JSValue, state: *c.JSValue, completion: af.Completion, input: c.JSValue) !af.Action {
    if (completion == .start) {
        _ = try initialize(o, state);
        return .{ .awaited = try expression(o.s.engine, post, .{module, Request.device, c.pi_js_undefined(), signal}) };
    }
    try o.put(state.*, "response", input);
    if (!try truth(o, propertyTruthy, .{input, @as([*:0]const u8, "ok")}))
        return .{ .thrown = try expression(o.s.engine, requestFailure, .{@as([]const u8, "device authorization"), input}) };
    return .{ .returned = try expression(o.s.engine, parseResponse, .{input}) };
}
fn refreshTokenBody(engine: *x.em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue, state: *c.JSValue, completion: af.Completion, input: c.JSValue) !af.Action {
    if (completion == .rejected) return rejected(engine, input);
    return actionExpression(engine, refreshTokenAdvance, .{roots[0], args, state, completion, input});
}
fn refreshTokenAdvance(o: *x.Ops, module: c.JSValue, args: []const c.JSValue, state: *c.JSValue, completion: af.Completion, input: c.JSValue) !af.Action {
    if (completion == .start) {
        _ = try initialize(o, state);
        return .{ .awaited = try expression(o.s.engine, post, .{module, Request.refresh, x.arg(args, 0), x.arg(args, 1)}) };
    }
    try o.put(state.*, "response", input);
    if (!try truth(o, propertyTruthy, .{input, @as([*:0]const u8, "ok")}))
        return .{ .thrown = try expression(o.s.engine, requestFailure, .{@as([]const u8, "token refresh"), input}) };
    return .{ .returned = try expression(o.s.engine, responseCredentials, .{input, x.arg(args, 0)}) };
}

fn resultStatus(o: *x.Ops, status: []const u8) !c.JSValue {
    const result = try o.object();
    try o.put(result, "status", try o.text(status));
    return result;
}
fn failedMessage(o: *x.Ops, message: []const u8) !c.JSValue {
    const result = try resultStatus(o, "failed");
    try o.put(result, "message", try o.text(message));
    return duplicate(o, result);
}
fn pollForTokensBody(engine: *x.em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue, _: *c.JSValue, completion: af.Completion, _: c.JSValue) !af.Action {
    if (completion != .start) unreachable;
    // Genuine zero-Await async return adopts the poller's intrinsic Promise.
    return .{ .returned = try expression(engine, pollForTokens, .{roots[0], x.arg(args, 0), x.arg(args, 1)}) };
}
fn pollForTokens(o: *x.Ops, module: c.JSValue, device: c.JSValue, signal: c.JSValue) !c.JSValue {
    const callback = try o.get(module, "pollDevice");
    const options = try o.object();
    try o.put(options, "intervalSeconds", try o.get(device, "intervalSeconds"));
    try o.put(options, "expiresInSeconds", try o.get(device, "expiresInSeconds"));
    try o.put(options, "waitBeforeFirstPoll", boolean(o, true));
    try o.put(options, "signal", signal);
    try o.put(options, "poll", try o.own(try af.createResumableArrow(o.s.engine, "poll", 0, pollBody, &.{module, device, signal}, c.pi_js_undefined())));
    return duplicate(o, try o.call(callback, c.pi_js_undefined(), &.{options}));
}
fn pollBody(engine: *x.em.Engine, _: c.JSValue, _: []const c.JSValue, roots: []const c.JSValue, state: *c.JSValue, completion: af.Completion, input: c.JSValue) !af.Action {
    if (completion == .rejected) return rejected(engine, input);
    return actionExpression(engine, pollAdvance, .{roots, state, completion, input});
}
fn pollAdvance(o: *x.Ops, roots: []const c.JSValue, state: *c.JSValue, completion: af.Completion, input: c.JSValue) !af.Action {
    if (completion == .start) {
        const owner = try initialize(o, state);
        inline for (.{ "response", "error", "interval" }) |name| try o.put(owner, name, c.pi_js_undefined());
        return .{ .awaited = try expression(o.s.engine, post, .{roots[0], Request.poll, roots[1], roots[2]}) };
    }
    try o.put(state.*, "response", input);
    return .{ .returned = try expression(o.s.engine, pollResponse, .{state.*, input}) };
}
fn pollResponse(o: *x.Ops, owner: c.JSValue, response: c.JSValue) !c.JSValue {
    if (try truth(o, propertyTruthy, .{response, @as([*:0]const u8, "ok")})) {
        const result = try resultStatus(o, "complete");
        try o.put(result, "value", try value(o, responseCredentials, .{response, c.pi_js_undefined()}));
        return duplicate(o, result);
    }
    const code = try value(o, responseField, .{response, @as([*:0]const u8, "error")});
    try o.put(owner, "error", code);
    if (try equalText(o, code, "authorization_pending")) return duplicate(o, try resultStatus(o, "pending"));
    if (try equalText(o, code, "slow_down")) {
        const interval = try value(o, responseField, .{response, @as([*:0]const u8, "interval")});
        try o.put(owner, "interval", interval);
        const result = try resultStatus(o, "slow_down");
        try o.put(result, "intervalSeconds", if (c.JS_IsNumber(interval)) interval else c.pi_js_undefined());
        return duplicate(o, result);
    }
    if (try equalText(o, code, "access_denied") or try equalText(o, code, "authorization_denied"))
        return failedMessage(o, "xAI device authorization was denied");
    if (try equalText(o, code, "expired_token")) return failedMessage(o, "xAI device code expired");
    const result = try resultStatus(o, "failed");
    try o.put(result, "message", try value(o, failureMessage, .{response}));
    return duplicate(o, result);
}
fn startLogin(o: *x.Ops, module: c.JSValue, interaction: c.JSValue) !c.JSValue {
    const callback = try o.get(module, "requestDeviceCode");
    return duplicate(o, try o.call(callback, c.pi_js_undefined(), &.{try o.get(interaction, "signal")}));
}
fn notifyDevice(o: *x.Ops, interaction: c.JSValue, device: c.JSValue) !void {
    const notify = try o.get(interaction, "notify");
    const message = try o.object();
    try o.put(message, "type", try o.text("device_code"));
    try o.put(message, "userCode", try o.get(device, "userCode"));
    const complete = try o.get(device, "verificationUriComplete");
    try o.put(message, "verificationUri", if (x.nullish(complete)) try o.get(device, "verificationUri") else complete);
    try o.put(message, "intervalSeconds", try o.get(device, "intervalSeconds"));
    try o.put(message, "expiresInSeconds", try o.get(device, "expiresInSeconds"));
    _ = try o.call(notify, interaction, &.{message});
}
fn loginPoll(o: *x.Ops, module: c.JSValue, device: c.JSValue, interaction: c.JSValue) !c.JSValue {
    const callback = try o.get(module, "pollForTokens");
    return duplicate(o, try o.call(callback, c.pi_js_undefined(), &.{device, try o.get(interaction, "signal")}));
}
fn loginBody(engine: *x.em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue, state: *c.JSValue, completion: af.Completion, input: c.JSValue) !af.Action {
    if (completion == .rejected) return rejected(engine, input);
    return actionExpression(engine, loginAdvance, .{roots[0], x.arg(args, 0), state, completion, input});
}
fn loginAdvance(o: *x.Ops, module: c.JSValue, interaction: c.JSValue, state: *c.JSValue, completion: af.Completion, input: c.JSValue) !af.Action {
    if (completion == .start) {
        _ = try initialize(o, state);
        return .{ .awaited = try expression(o.s.engine, startLogin, .{module, interaction}) };
    }
    try o.put(state.*, "device", input);
    try statement(o.s.engine, notifyDevice, .{interaction, input});
    // Source returns pollForTokens directly after its one request-device Await.
    return .{ .returned = try expression(o.s.engine, loginPoll, .{module, input, interaction}) };
}
