//! c268154c auth/oauth/kimi-coding.ts: actual nested async bodies and Source Await.
//! The VM owns each Promise, continuation and return adoption.
const x = @import("native_ai_auth_helper_values.zig");
const c = x.c;
const af = x.af;
const functions = @import("native_node_function.zig");
const client_id = "17e5f671-d194-4dfb-9706-5516cb48c098";
const Stage = enum(i32) { device_response, device_text, device_json, login_device, login_token, poll_response, poll_text, poll_json, refresh_sleep, refresh_response, refresh_json };
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
fn optional(o: *x.Ops, receiver: c.JSValue, name: [*:0]const u8) !c.JSValue { return if (x.nullish(receiver)) c.pi_js_undefined() else o.get(receiver, name); }
fn propertyTruthy(o: *x.Ops, receiver: c.JSValue, name: [*:0]const u8) !c.JSValue { return boolean(o, o.truthy(try o.get(receiver, name))); }
fn equalText(o: *x.Ops, input: c.JSValue, expected: []const u8) !bool { return c.JS_IsStrictEqual(o.s.engine.context, input, try o.text(expected)); }
fn propertyNumberEquals(o: *x.Ops, receiver: c.JSValue, name: [*:0]const u8, expected: i32) !c.JSValue { return boolean(o, c.JS_IsStrictEqual(o.s.engine.context, try o.get(receiver, name), integer(o, expected))); }
fn propertyAtLeast(o: *x.Ops, receiver: c.JSValue, name: [*:0]const u8, expected: i32) !c.JSValue { return duplicate(o, try o.binary(7, try o.get(receiver, name), integer(o, expected))); }
fn array(o: *x.Ops) !c.JSValue {
    const generation = try o.beforeAllocation();
    return o.allocation(c.JS_NewArray(o.s.engine.context), generation);
}
fn index(o: *x.Ops, receiver: c.JSValue, position: u32, input: c.JSValue) !void { return x.guest.index(o.s, receiver, position, input); }
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
fn helper(o: *x.Ops, module: c.JSValue, name: [*:0]const u8, args: []const c.JSValue) !c.JSValue { return o.call(try o.get(module, name), c.pi_js_undefined(), args); }
fn declaration(o: *x.Ops, module: c.JSValue, name: [*:0]const u8, length: c_int, body: af.Body) !c.JSValue { return o.own(try af.createResumable(o.s.engine, name, length, body, &.{module})); }

pub fn create(engine: *x.em.Engine) !c.JSValue {
    try engine.checkNativeEntry();
    var frame: x.em.Engine.NativeInvocation = .{};
    engine.enterNativeInvocation(&frame);
    return x.finishInvocation(engine, &frame, expression(engine, createBody, .{}));
}
fn createBody(o: *x.Ops) !c.JSValue {
    const module = try o.cell();
    try o.put(module, "env", try o.own(try @import("native_provider_env.zig").create(o.s.engine)));
    const device = try o.own(try @import("native_ai_oauth_device_code.zig").create(o.s.engine));
    try o.put(module, "pollDevice", try o.get(device, "pollOAuthDeviceCodeFlow"));
    try o.put(module, "sleep", try o.own(try @import("native_ai_sleep.zig").create(o.s.engine)));
    try o.put(module, "readJson", try declaration(o, module, "readJson", 1, readJsonBody));
    try o.put(module, "startDeviceAuthorization", try declaration(o, module, "startDeviceAuthorization", 2, startDeviceBody));
    try o.put(module, "pollForToken", try declaration(o, module, "pollForToken", 3, pollForTokenBody));
    try o.put(module, "refreshToken", try declaration(o, module, "refreshToken", 3, refreshTokenBody));
    const exports = try o.object();
    try o.put(exports, "name", try o.text("Kimi Code (subscription)"));
    try o.put(exports, "isSubscription", boolean(o, true));
    try o.put(exports, "loginLabel", try o.text("Sign in with Kimi Code"));
    try o.put(exports, "login", try declaration(o, module, "loginKimiCoding", 1, loginBody));
    try o.put(exports, "refresh", try o.own(try af.createResumableArrow(o.s.engine, "refresh", 2, refreshBody, &.{module}, c.pi_js_undefined())));
    try o.put(exports, "toAuth", try o.own(try af.create(o.s.engine, "toAuth", 1, toAuthCall, &.{})));
    return duplicate(o, exports);
}
fn toAuthCall(engine: *x.em.Engine, _: c.JSValue, args: []const c.JSValue, _: []const c.JSValue) !c.JSValue { return expression(engine, toAuth, .{x.arg(args, 0)}); }
fn toAuth(o: *x.Ops, input_credential: c.JSValue) !c.JSValue {
    const result = try o.object();
    const headers = try o.object();
    const access = try o.stringify(try o.get(input_credential, "access"));
    try o.put(headers, "Authorization", try concat(o, try o.text("Bearer "), access));
    try o.put(result, "headers", headers);
    return duplicate(o, result);
}
fn getHost(o: *x.Ops, module: c.JSValue) !c.JSValue {
    const env = try o.get(module, "env");
    var override = try o.call(env, c.pi_js_undefined(), &.{try o.text("KIMI_CODE_OAUTH_HOST")});
    if (!o.truthy(override)) override = try o.call(env, c.pi_js_undefined(), &.{try o.text("KIMI_OAUTH_HOST")});
    const host = if (o.truthy(override)) override else try o.text("https://auth.kimi.com");
    const replace = try o.get(host, "replace");
    const regex = try x.guest.construct(o.s, o.s.engine.intrinsic_regexp_constructor, &.{try o.text("/+$"), try o.text("")});
    return duplicate(o, try o.call(replace, host, &.{regex, try o.text("")}));
}
fn requestSignal(o: *x.Ops, signal: c.JSValue) !c.JSValue {
    const abort = try o.global("AbortSignal");
    const any = try o.get(abort, "any");
    const signals = try array(o);
    // Source evaluates a second live AbortSignal lookup for timeout.
    try index(o, signals, 0, try value(o, timeoutSignal, .{}));
    try index(o, signals, 1, signal);
    return duplicate(o, try o.call(any, abort, &.{signals}));
}
fn timeoutSignal(o: *x.Ops) !c.JSValue { return duplicate(o, try o.invoke(try o.global("AbortSignal"), "timeout", &.{integer(o, 30000)})); }
fn formParameters(o: *x.Ops, field_values: c.JSValue) !c.JSValue {
    return duplicate(o, try x.guest.construct(o.s, try o.global("URLSearchParams"), &.{field_values}));
}
fn form(o: *x.Ops, field_values: c.JSValue) !c.JSValue {
    const encoded = try value(o, formParameters, .{field_values});
    return duplicate(o, try o.invoke(encoded, "toString", &.{}));
}
const Request = enum { device, poll, refresh };
fn fields(o: *x.Ops, kind: Request, source: c.JSValue) !c.JSValue {
    const result = try o.object();
    try o.put(result, "client_id", try o.text(client_id));
    switch (kind) {
        .device => {},
        .poll => {
            try o.put(result, "device_code", try o.get(source, "deviceCode"));
            try o.put(result, "grant_type", try o.text("urn:ietf:params:oauth:grant-type:device_code"));
        },
        .refresh => {
            try o.put(result, "grant_type", try o.text("refresh_token"));
            try o.put(result, "refresh_token", source);
        },
    }
    return duplicate(o, result);
}
fn encodedFields(o: *x.Ops, kind: Request, source: c.JSValue) !c.JSValue {
    // The caller argument object retires when formUrlEncode returns, before
    // evaluating the next signal property of the fetch options literal.
    const parameters = try value(o, fields, .{kind, source});
    return duplicate(o, try value(o, form, .{parameters}));
}
fn requestInit(o: *x.Ops, signal: c.JSValue, kind: Request, source: c.JSValue) !c.JSValue {
    const init = try o.object();
    try o.put(init, "method", try o.text("POST"));
    const headers = try o.object();
    try o.put(headers, "Content-Type", try o.text("application/x-www-form-urlencoded"));
    try o.put(headers, "Accept", try o.text("application/json"));
    try o.put(init, "headers", headers);
    try o.put(init, "body", try value(o, encodedFields, .{kind, source}));
    try o.put(init, "signal", try value(o, requestSignal, .{signal}));
    return duplicate(o, init);
}
fn request(o: *x.Ops, host: c.JSValue, signal: c.JSValue, kind: Request, source: c.JSValue) !c.JSValue {
    const fetch = try o.global("fetch");
    const url = try concat(o, try o.stringify(host), try o.text(if (kind == .device) "/api/oauth/device_authorization" else "/api/oauth/token"));
    const init = try value(o, requestInit, .{signal, kind, source});
    return duplicate(o, try o.call(fetch, c.pi_js_undefined(), &.{url, init}));
}
fn invokeJson(o: *x.Ops, response: c.JSValue) !c.JSValue { return duplicate(o, try o.invoke(response, "json", &.{})); }
fn invokeText(o: *x.Ops, response: c.JSValue) !c.JSValue { return duplicate(o, try o.invoke(response, "text", &.{})); }
fn emptyText(engine: *x.em.Engine, _: c.JSValue, _: []const c.JSValue, _: []const c.JSValue) !c.JSValue { return expression(engine, text, .{@as([]const u8, "")}); }
fn responseText(o: *x.Ops, response: c.JSValue) !c.JSValue {
    // The Source's live .catch call is outside any local catch. A synchronous
    // response.text() failure therefore rejects the enclosing async body.
    const promise = try value(o, invokeText, .{response});
    const catcher = try o.get(promise, "catch");
    const callback = try o.own(try functions.createArrow(o.s.engine, "", 0, emptyText, &.{}));
    return duplicate(o, try o.call(catcher, promise, &.{callback}));
}
fn readJsonBody(engine: *x.em.Engine, _: c.JSValue, args: []const c.JSValue, _: []const c.JSValue, _: *c.JSValue, completion: af.Completion, input: c.JSValue) !af.Action {
    if (completion == .rejected) {
        try @import("native_async_body.zig").enterRejectedContinuation(engine);
        return .{ .returned = c.pi_js_null() };
    }
    if (completion == .start) {
        const outcome = try attempt(engine, invokeJson, .{x.arg(args, 0)});
        return switch (outcome) {
            .returned => |result| .{ .awaited = result },
            .thrown => |reason| blk: { try discard(engine, reason); break :blk .{ .returned = c.pi_js_null() }; },
            .awaited => unreachable,
        };
    }
    return .{ .returned = if (c.JS_ToBool(engine.context, input) == 1 and c.JS_IsObject(input) and !c.JS_IsFunction(engine.context, input)) c.JS_DupValue(engine.context, input) else c.pi_js_null() };
}
fn credential(o: *x.Ops, token: c.JSValue) !c.JSValue {
    const result = try o.object();
    try o.put(result, "type", try o.text("oauth"));
    try o.put(result, "access", try o.get(token, "access"));
    try o.put(result, "refresh", try o.get(token, "refresh"));
    try o.put(result, "expires", try o.get(token, "expires"));
    return duplicate(o, result);
}
fn refreshCall(o: *x.Ops, module: c.JSValue, input: c.JSValue, signal: c.JSValue) !c.JSValue {
    const callback = try o.get(module, "refreshToken");
    const host = try value(o, getHost, .{module});
    const token = try o.get(input, "refresh");
    return duplicate(o, try o.call(callback, c.pi_js_undefined(), &.{host, token, signal}));
}
fn refreshBody(engine: *x.em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue, _: *c.JSValue, completion: af.Completion, input: c.JSValue) !af.Action {
    if (completion == .rejected) return rejected(engine, input);
    return if (completion == .start)
        .{ .awaited = try expression(engine, refreshCall, .{roots[0], x.arg(args, 0), x.arg(args, 1)}) }
    else
        .{ .returned = try expression(engine, credential, .{input}) };
}
fn loginBody(engine: *x.em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue, state: *c.JSValue, completion: af.Completion, input: c.JSValue) !af.Action {
    if (completion == .rejected) return rejected(engine, input);
    var scope: x.Scope = .{ .engine = engine };
    var o: x.Ops = .{ .s = &scope };
    return x.owned.finishAction(&scope, loginAdvance(&o, x.arg(args, 0), roots[0], state, completion, input));
}
fn loginAdvance(o: *x.Ops, interaction: c.JSValue, module: c.JSValue, state: *c.JSValue, completion: af.Completion, input: c.JSValue) !af.Action {
    if (completion == .start) {
        const owner = try initialize(o, state);
        try o.put(owner, "host", try value(o, getHost, .{module}));
        try setStage(o, owner, .login_device);
        return .{ .awaited = try expression(o.s.engine, startLogin, .{module, owner, interaction}) };
    }
    if (try getStage(o, state.*) == .login_device) {
        try o.put(state.*, "device", input);
        try statement(o.s.engine, notifyDevice, .{interaction, input});
        try setStage(o, state.*, .login_token);
        return .{ .awaited = try expression(o.s.engine, loginPoll, .{module, state.*, interaction}) };
    }
    try o.put(state.*, "token", input);
    return .{ .returned = try expression(o.s.engine, credential, .{input}) };
}
fn startLogin(o: *x.Ops, module: c.JSValue, owner: c.JSValue, interaction: c.JSValue) !c.JSValue {
    const callback = try o.get(module, "startDeviceAuthorization");
    return duplicate(o, try o.call(callback, c.pi_js_undefined(), &.{try o.get(owner, "host"), try o.get(interaction, "signal")}));
}
fn notifyDevice(o: *x.Ops, interaction: c.JSValue, device: c.JSValue) !void {
    const notify = try o.get(interaction, "notify");
    const message = try o.object();
    try o.put(message, "type", try o.text("device_code"));
    try o.put(message, "userCode", try o.get(device, "userCode"));
    try o.put(message, "verificationUri", try o.get(device, "verificationUriComplete"));
    try o.put(message, "intervalSeconds", try o.get(device, "intervalSeconds"));
    try o.put(message, "expiresInSeconds", try o.get(device, "expiresInSeconds"));
    _ = try o.call(notify, interaction, &.{message});
}
fn loginPoll(o: *x.Ops, module: c.JSValue, owner: c.JSValue, interaction: c.JSValue) !c.JSValue {
    const callback = try o.get(module, "pollForToken");
    return duplicate(o, try o.call(callback, c.pi_js_undefined(), &.{try o.get(owner, "host"), try o.get(owner, "device"), try o.get(interaction, "signal")}));
}

fn actionExpression(engine: *x.em.Engine, comptime body: anytype, args: anytype) !af.Action {
    var scope: x.Scope = .{ .engine = engine };
    var o: x.Ops = .{ .s = &scope };
    return x.owned.finishAction(&scope, @call(.auto, body, .{&o} ++ args));
}
fn propertyString(o: *x.Ops, receiver: c.JSValue, name: [*:0]const u8) !c.JSValue { return duplicate(o, try o.stringify(try o.get(receiver, name))); }
fn stringifyValue(o: *x.Ops, input: c.JSValue) !c.JSValue { return duplicate(o, try o.stringify(input)); }
fn jsonEncode(o: *x.Ops, input: c.JSValue) !c.JSValue { return duplicate(o, try o.invoke(try o.global("JSON"), "stringify", &.{input})); }
fn jsonTemplate(o: *x.Ops, input: c.JSValue) !c.JSValue { return duplicate(o, try o.stringify(try value(o, jsonEncode, .{input}))); }
fn newError(o: *x.Ops, comptime message: anytype, args: anytype) !c.JSValue {
    const constructor = try o.global("Error");
    const description = try value(o, message, args);
    return duplicate(o, try x.guest.construct(o.s, constructor, &.{description}));
}
fn statusMessage(o: *x.Ops, prefix: []const u8, response: c.JSValue, suffix: c.JSValue) !c.JSValue {
    var message = try concat(o, try o.text(prefix), try value(o, propertyString, .{response, @as([*:0]const u8, "status")}));
    if (o.truthy(suffix)) message = try concat(o, message, try concat(o, try o.text(": "), try value(o, stringifyValue, .{suffix})));
    return duplicate(o, message);
}
fn invalidDeviceMessage(o: *x.Ops, json: c.JSValue) !c.JSValue { return duplicate(o, try concat(o, try o.text("Invalid Kimi Code device authorization response: "), try value(o, jsonTemplate, .{json}))); }
fn missingTokenMessage(o: *x.Ops, json: c.JSValue, operation: c.JSValue) !c.JSValue {
    var message = try concat(o, try o.text("Kimi Code token "), try value(o, stringifyValue, .{operation}));
    message = try concat(o, message, try o.text(" response missing fields: "));
    return duplicate(o, try concat(o, message, try value(o, jsonTemplate, .{json})));
}
fn propertyEqualsText(o: *x.Ops, receiver: c.JSValue, name: [*:0]const u8, expected: []const u8) !c.JSValue { return boolean(o, try equalText(o, try o.get(receiver, name), expected)); }
fn trustedUrl(o: *x.Ops, input: c.JSValue) !c.JSValue {
    if (!c.JS_IsString(input) or !o.truthy(input)) return c.pi_js_null();
    const outcome = try attempt(o.s.engine, trustedUrlTry, .{input});
    return switch (outcome) {
        .returned => |result| result,
        .thrown => |reason| blk: { try discard(o.s.engine, reason); break :blk c.pi_js_null(); },
        .awaited => unreachable,
    };
}
fn newTrustedUrl(o: *x.Ops, input: c.JSValue) !c.JSValue {
    return duplicate(o, try x.guest.construct(o.s, try o.global("URL"), &.{input}));
}
fn trustedUrlTry(o: *x.Ops, input: c.JSValue) !c.JSValue {
    const url = try value(o, newTrustedUrl, .{input});
    if (!try truth(o, propertyEqualsText, .{url, @as([*:0]const u8, "protocol"), @as([]const u8, "https:")}) and
        !try truth(o, propertyEqualsText, .{url, @as([*:0]const u8, "protocol"), @as([]const u8, "http:")})) return c.pi_js_null();
    return duplicate(o, try o.get(url, "href"));
}
fn finite(o: *x.Ops, input: c.JSValue) !c.JSValue { return boolean(o, o.truthy(try o.invoke(try o.global("Number"), "isFinite", &.{input}))); }
fn positive(o: *x.Ops, input: c.JSValue) !bool { return c.JS_IsNumber(input) and o.truthy(try o.binary(6, input, integer(o, 0))); }
fn finitePositive(o: *x.Ops, input: c.JSValue) !bool { return c.JS_IsNumber(input) and try truth(o, finite, .{input}) and try positive(o, input); }
fn parseDevice(o: *x.Ops, owner: c.JSValue, json: c.JSValue) !af.Action {
    const device_code = try optional(o, json, "device_code");
    try o.put(owner, "deviceCode", device_code);
    const user_code = try optional(o, json, "user_code");
    try o.put(owner, "userCode", user_code);
    const verification_uri = try optional(o, json, "verification_uri");
    try o.put(owner, "verificationUri", verification_uri);
    const verification_complete = try optional(o, json, "verification_uri_complete");
    try o.put(owner, "verificationUriComplete", verification_complete);
    if (!c.JS_IsString(device_code) or !c.JS_IsString(user_code) or !c.JS_IsString(verification_uri) or !c.JS_IsString(verification_complete) or
        !try truth(o, trustedUrl, .{verification_complete}) or !try truth(o, trustedUrl, .{verification_uri})) {
        return .{ .thrown = try expression(o.s.engine, newError, .{invalidDeviceMessage, .{json}}) };
    }
    const interval = try optional(o, json, "interval");
    const expires = try optional(o, json, "expires_in");
    const result = try o.object();
    try o.put(result, "deviceCode", device_code);
    try o.put(result, "userCode", user_code);
    try o.put(result, "verificationUri", verification_uri);
    try o.put(result, "verificationUriComplete", verification_complete);
    try o.put(result, "intervalSeconds", if (try finitePositive(o, interval)) interval else integer(o, 5));
    try o.put(result, "expiresInSeconds", if (try finitePositive(o, expires)) expires else integer(o, 900));
    return .{ .returned = duplicate(o, result) };
}
fn startDeviceBody(engine: *x.em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue, state: *c.JSValue, completion: af.Completion, input: c.JSValue) !af.Action {
    if (completion == .rejected) return rejected(engine, input);
    var scope: x.Scope = .{ .engine = engine };
    var o: x.Ops = .{ .s = &scope };
    return x.owned.finishAction(&scope, startDeviceAdvance(&o, args, roots[0], state, completion, input));
}
fn startDeviceAdvance(o: *x.Ops, args: []const c.JSValue, module: c.JSValue, state: *c.JSValue, completion: af.Completion, input: c.JSValue) !af.Action {
    if (completion == .start) {
        const owner = try initialize(o, state);
        try setStage(o, owner, .device_response);
        return .{ .awaited = try expression(o.s.engine, request, .{x.arg(args, 0), x.arg(args, 1), Request.device, c.pi_js_undefined()}) };
    }
    switch (try getStage(o, state.*)) {
        .device_response => {
            try o.put(state.*, "response", input);
            if (!try truth(o, propertyTruthy, .{input, @as([*:0]const u8, "ok")})) {
                try setStage(o, state.*, .device_text);
                return .{ .awaited = try expression(o.s.engine, responseText, .{input}) };
            }
            try setStage(o, state.*, .device_json);
            return .{ .awaited = try expression(o.s.engine, helper, .{module, @as([*:0]const u8, "readJson"), @as([]const c.JSValue, &.{input})}) };
        },
        .device_text => {
            try o.put(state.*, "text", input);
            return .{ .thrown = try expression(o.s.engine, newError, .{statusMessage, .{@as([]const u8, "Kimi Code device authorization failed with status "), try o.get(state.*, "response"), input}}) };
        },
        .device_json => {
            try o.put(state.*, "json", input);
            return actionExpression(o.s.engine, parseDevice, .{state.*, input});
        },
        else => unreachable,
    }
}
fn tokenResponse(o: *x.Ops, json: c.JSValue, operation: c.JSValue) !af.Action {
    const access = try optional(o, json, "access_token");
    const refresh = try optional(o, json, "refresh_token");
    const expires = try optional(o, json, "expires_in");
    if (!c.JS_IsString(access) or !o.truthy(access) or !c.JS_IsString(refresh) or !o.truthy(refresh) or
        !c.JS_IsNumber(expires) or !try truth(o, finite, .{expires}) or o.truthy(try o.binary(5, expires, integer(o, 0)))) {
        return .{ .thrown = try expression(o.s.engine, newError, .{missingTokenMessage, .{json, operation}}) };
    }
    const result = try o.object();
    try o.put(result, "access", access);
    try o.put(result, "refresh", refresh);
    try o.put(result, "expires", try value(o, tokenExpiry, .{expires}));
    return .{ .returned = duplicate(o, result) };
}
fn tokenNow(o: *x.Ops) !c.JSValue { return duplicate(o, try o.invoke(try o.global("Date"), "now", &.{})); }
fn tokenExpiry(o: *x.Ops, expires: c.JSValue) !c.JSValue {
    const now = try value(o, tokenNow, .{});
    return duplicate(o, try o.binary(0, now, try o.binary(2, expires, integer(o, 1000))));
}

fn pollForTokenBody(engine: *x.em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue, _: *c.JSValue, completion: af.Completion, _: c.JSValue) !af.Action {
    if (completion != .start) unreachable;
    return .{ .returned = try expression(engine, pollForToken, .{roots[0], args}) };
}
fn pollForToken(o: *x.Ops, module: c.JSValue, args: []const c.JSValue) !c.JSValue {
    const callback = try o.get(module, "pollDevice");
    const options = try o.object();
    try o.put(options, "intervalSeconds", try o.get(x.arg(args, 1), "intervalSeconds"));
    try o.put(options, "expiresInSeconds", try o.get(x.arg(args, 1), "expiresInSeconds"));
    try o.put(options, "waitBeforeFirstPoll", boolean(o, true));
    try o.put(options, "signal", x.arg(args, 2));
    try o.put(options, "poll", try o.own(try af.createResumableArrow(o.s.engine, "poll", 0, pollBody, &.{module, x.arg(args, 0), x.arg(args, 1), x.arg(args, 2)}, c.pi_js_undefined())));
    return duplicate(o, try o.call(callback, c.pi_js_undefined(), &.{options}));
}
fn pollBody(engine: *x.em.Engine, _: c.JSValue, _: []const c.JSValue, roots: []const c.JSValue, state: *c.JSValue, completion: af.Completion, input: c.JSValue) !af.Action {
    if (completion == .rejected) return rejected(engine, input);
    var scope: x.Scope = .{ .engine = engine };
    var o: x.Ops = .{ .s = &scope };
    return x.owned.finishAction(&scope, pollAdvance(&o, roots, state, completion, input));
}
fn pollAdvance(o: *x.Ops, roots: []const c.JSValue, state: *c.JSValue, completion: af.Completion, input: c.JSValue) !af.Action {
    if (completion == .start) {
        const owner = try initialize(o, state);
        try setStage(o, owner, .poll_response);
        return .{ .awaited = try expression(o.s.engine, request, .{roots[1], roots[3], Request.poll, roots[2]}) };
    }
    switch (try getStage(o, state.*)) {
        .poll_response => {
            try o.put(state.*, "response", input);
            if (try truth(o, propertyAtLeast, .{input, @as([*:0]const u8, "status"), @as(i32, 500)})) {
                try setStage(o, state.*, .poll_text);
                return .{ .awaited = try expression(o.s.engine, responseText, .{input}) };
            }
            try setStage(o, state.*, .poll_json);
            return .{ .awaited = try expression(o.s.engine, helper, .{roots[0], @as([*:0]const u8, "readJson"), @as([]const c.JSValue, &.{input})}) };
        },
        .poll_text => {
            try o.put(state.*, "text", input);
            return .{ .returned = try expression(o.s.engine, pollTextResult, .{try o.get(state.*, "response"), input}) };
        },
        .poll_json => {
            try o.put(state.*, "json", input);
            return pollJson(o, state.*, input);
        },
        else => unreachable,
    }
}
fn resultStatus(o: *x.Ops, status: []const u8) !c.JSValue {
    const result = try o.object();
    try o.put(result, "status", try o.text(status));
    return result;
}
fn pollTextResult(o: *x.Ops, response: c.JSValue, suffix: c.JSValue) !c.JSValue {
    const result = try resultStatus(o, "failed");
    try o.put(result, "message", try value(o, statusMessage, .{@as([]const u8, "Kimi Code device token request failed with status "), response, suffix}));
    return duplicate(o, result);
}
fn accessIsString(o: *x.Ops, json: c.JSValue) !c.JSValue { return boolean(o, c.JS_IsString(try optional(o, json, "access_token"))); }
fn completeToken(o: *x.Ops, json: c.JSValue) !af.Action {
    const result = try resultStatus(o, "complete");
    const token = try actionExpression(o.s.engine, tokenResponse, .{json, try o.text("poll")});
    switch (token) {
        .returned => |input| {
            try o.put(result, "value", try o.own(input));
            return .{ .returned = duplicate(o, result) };
        },
        .thrown => return token,
        .awaited => unreachable,
    }
}
fn instanceOfError(o: *x.Ops, input: c.JSValue) !c.JSValue {
    const constructor = try o.global("Error");
    var boundary: x.guest.Boundary = .{ .engine = o.s.engine };
    try boundary.begin();
    const result = c.JS_IsInstanceOf(o.s.engine.context, input, constructor);
    try boundary.finishStatus(result);
    return boolean(o, result != 0);
}
fn stringCall(o: *x.Ops, input: c.JSValue) !c.JSValue { return duplicate(o, try o.call(try o.global("String"), c.pi_js_undefined(), &.{input})); }
fn pollCaught(o: *x.Ops, reason: c.JSValue) !c.JSValue {
    const result = try resultStatus(o, "failed");
    try o.put(result, "message", if (try truth(o, instanceOfError, .{reason})) try o.get(reason, "message") else try value(o, stringCall, .{reason}));
    return duplicate(o, result);
}
fn errorDescription(o: *x.Ops, json: c.JSValue) !c.JSValue {
    if (!c.JS_IsString(try optional(o, json, "error_description"))) return o.text("");
    return duplicate(o, try concat(o, try o.text(": "), try value(o, propertyString, .{json, @as([*:0]const u8, "error_description")})));
}
fn failedMessage(o: *x.Ops, message: []const u8) !c.JSValue {
    const result = try resultStatus(o, "failed");
    try o.put(result, "message", try o.text(message));
    return duplicate(o, result);
}
fn fallbackPoll(o: *x.Ops, response: c.JSValue, problem: c.JSValue, description: c.JSValue) !c.JSValue {
    const result = try resultStatus(o, "failed");
    var message = try concat(o, try o.text("Kimi Code device token request failed (status "), try value(o, propertyString, .{response, @as([*:0]const u8, "status")}));
    message = try concat(o, message, try o.text(")"));
    if (c.JS_IsString(problem)) message = try concat(o, message, try concat(o, try concat(o, try o.text(": "), problem), description));
    try o.put(result, "message", message);
    return duplicate(o, result);
}
fn pollJson(o: *x.Ops, owner: c.JSValue, json: c.JSValue) !af.Action {
    const response = try o.get(owner, "response");
    if (try truth(o, propertyTruthy, .{response, @as([*:0]const u8, "ok")}) and try truth(o, accessIsString, .{json})) {
        const outcome = try actionExpression(o.s.engine, completeToken, .{json});
        return switch (outcome) {
            .returned => outcome,
            .thrown => |reason| blk: {
                const held = try o.own(reason);
                try o.put(owner, "caughtError", held);
                break :blk .{ .returned = try expression(o.s.engine, pollCaught, .{held}) };
            },
            .awaited => unreachable,
        };
    }
    const problem = try optional(o, json, "error");
    try o.put(owner, "error", problem);
    const description = try value(o, errorDescription, .{json});
    try o.put(owner, "description", description);
    if (try equalText(o, problem, "authorization_pending")) return .{ .returned = duplicate(o, try resultStatus(o, "pending")) };
    if (try equalText(o, problem, "slow_down")) {
        const interval = try optional(o, json, "interval");
        try o.put(owner, "interval", interval);
        const result = try resultStatus(o, "slow_down");
        try o.put(result, "intervalSeconds", if (try positive(o, interval)) interval else c.pi_js_undefined());
        return .{ .returned = duplicate(o, result) };
    }
    if (try equalText(o, problem, "expired_token")) return .{ .returned = try expression(o.s.engine, failedMessage, .{@as([]const u8, "Kimi Code device authorization expired. Please restart login.")}) };
    if (try equalText(o, problem, "access_denied")) return .{ .returned = try expression(o.s.engine, failedMessage, .{@as([]const u8, "Kimi Code login was denied.")}) };
    return .{ .returned = try expression(o.s.engine, fallbackPoll, .{response, problem, description}) };
}

fn refreshTokenBody(engine: *x.em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue, state: *c.JSValue, completion: af.Completion, input: c.JSValue) !af.Action {
    var again = false;
    var outcome = try actionExpression(engine, refreshEnter, .{roots[0], args, state, completion, input, &again});
    while (again) {
        switch (outcome) {
            .returned => |unused| try discard(engine, unused),
            .thrown, .awaited => unreachable,
        }
        // The preceding Source stage's temporary roots are already retired.
        // enter_scope on a true for condition now retires the previous body.
        again = false;
        outcome = try actionExpression(engine, refreshNext, .{roots[0], args, state.*, &again});
    }
    return outcome;
}
fn refreshEnter(o: *x.Ops, module: c.JSValue, args: []const c.JSValue, state: *c.JSValue, completion: af.Completion, input: c.JSValue, again: *bool) !af.Action {
    if (completion == .start) {
        const owner = try initialize(o, state);
        try o.put(owner, "attempt", integer(o, -1));
        try o.put(owner, "lastError", c.pi_js_undefined());
        // Uncaptured Source declarations are ordered independently of stages.
        try o.put(owner, "response", c.pi_js_undefined());
        try o.put(owner, "json", c.pi_js_undefined());
        try o.put(owner, "text", c.pi_js_undefined());
        try o.put(owner, "fetchError", c.pi_js_undefined());
        again.* = true;
        return .{ .returned = c.pi_js_undefined() };
    }
    const stage = try getStage(o, state.*);
    if (completion == .rejected) {
        if (stage != .refresh_response) return rejected(o.s.engine, input);
        try @import("native_async_body.zig").enterRejectedContinuation(o.s.engine);
        try statement(o.s.engine, recordFetchFailure, .{state.*, input});
        again.* = true;
        return .{ .returned = c.pi_js_undefined() };
    }
    switch (stage) {
        .refresh_sleep => return refreshSend(o, args, state.*, again),
        .refresh_response => {
            try o.put(state.*, "response", input);
            try setStage(o, state.*, .refresh_json);
            return .{ .awaited = try expression(o.s.engine, helper, .{module, @as([*:0]const u8, "readJson"), @as([]const c.JSValue, &.{input})}) };
        },
        .refresh_json => {
            try o.put(state.*, "json", input);
            return refreshDecision(o, state.*, input, again);
        },
        else => unreachable,
    }
}
fn attemptIndex(o: *x.Ops, owner: c.JSValue) !i32 {
    const input = try o.get(owner, "attempt");
    var result: i32 = 0;
    var boundary: x.guest.Boundary = .{ .engine = o.s.engine };
    try boundary.begin();
    try boundary.finishStatus(c.JS_ToInt32(o.s.engine.context, &result, input));
    return result;
}
fn refreshNext(o: *x.Ops, module: c.JSValue, args: []const c.JSValue, owner: c.JSValue, again: *bool) !af.Action {
    const number = try attemptIndex(o, owner) + 1;
    try o.put(owner, "attempt", integer(o, number));
    if (number > 3) {
        const last = try o.get(owner, "lastError");
        return .{ .thrown = if (!x.nullish(last)) duplicate(o, last) else try expression(o.s.engine, newError, .{text, .{@as([]const u8, "Kimi Code token refresh failed")}}) };
    }
    // Linked BCDF OP_enter_scope initializes the body declarations in reverse.
    // The uncaptured catch error is a different lexical scope and survives
    // subsequent successful requests until the next catch enters or exit.
    try o.put(owner, "text", c.pi_js_undefined());
    try o.put(owner, "json", c.pi_js_undefined());
    try o.put(owner, "response", c.pi_js_undefined());
    if (number > 0) {
        const milliseconds: i32 = switch (number) { 1 => 1000, 2 => 2000, 3 => 4000, else => unreachable };
        try setStage(o, owner, .refresh_sleep);
        return .{ .awaited = try expression(o.s.engine, helper, .{module, @as([*:0]const u8, "sleep"), @as([]const c.JSValue, &.{integer(o, milliseconds), x.arg(args, 2)})}) };
    }
    return refreshSend(o, args, owner, again);
}
fn normalizeFetchFailure(o: *x.Ops, reason: c.JSValue) !c.JSValue {
    if (try truth(o, instanceOfError, .{reason})) return duplicate(o, reason);
    // Source evaluates Error before the independent live String call.
    return newError(o, stringCall, .{reason});
}
fn recordFetchFailure(o: *x.Ops, owner: c.JSValue, reason: c.JSValue) !void {
    try o.put(owner, "fetchError", reason);
    try o.put(owner, "lastError", try value(o, normalizeFetchFailure, .{reason}));
}
fn refreshSend(o: *x.Ops, args: []const c.JSValue, owner: c.JSValue, again: *bool) !af.Action {
    if (try truth(o, propertyTruthy, .{x.arg(args, 2), @as([*:0]const u8, "aborted")})) {
        return .{ .thrown = try expression(o.s.engine, newError, .{text, .{@as([]const u8, "Kimi Code token refresh aborted")}}) };
    }
    try setStage(o, owner, .refresh_response);
    const outcome = try attempt(o.s.engine, request, .{x.arg(args, 0), x.arg(args, 2), Request.refresh, x.arg(args, 1)});
    return switch (outcome) {
        .returned => |response| .{ .awaited = response },
        .thrown => |reason| blk: {
            var caught = x.owned.Completion.initVoid(o.s.engine, statement(o.s.engine, recordFetchFailure, .{owner, reason}));
            caught.release(reason);
            try caught.finishVoid();
            again.* = true;
            break :blk .{ .returned = c.pi_js_undefined() };
        },
        .awaited => unreachable,
    };
}
fn invalidGrant(o: *x.Ops, json: c.JSValue) !c.JSValue { return boolean(o, try equalText(o, try optional(o, json, "error"), "invalid_grant")); }
fn retryable(o: *x.Ops, response: c.JSValue) !c.JSValue {
    return boolean(o, try truth(o, propertyNumberEquals, .{response, @as([*:0]const u8, "status"), @as(i32, 429)}) or
        try truth(o, propertyAtLeast, .{response, @as([*:0]const u8, "status"), @as(i32, 500)}));
}
fn unauthorizedMessage(o: *x.Ops, response: c.JSValue, description: c.JSValue) !c.JSValue {
    var message = try concat(o, try o.text("Kimi Code token refresh unauthorized (status "), try value(o, propertyString, .{response, @as([*:0]const u8, "status")}));
    message = try concat(o, message, try o.text(")"));
    return duplicate(o, try concat(o, message, description));
}
fn refreshDecision(o: *x.Ops, owner: c.JSValue, json: c.JSValue, again: *bool) !af.Action {
    const response = try o.get(owner, "response");
    if (try truth(o, propertyTruthy, .{response, @as([*:0]const u8, "ok")})) {
        return actionExpression(o.s.engine, tokenResponse, .{json, try o.text("refresh")});
    }
    if (try truth(o, propertyNumberEquals, .{response, @as([*:0]const u8, "status"), @as(i32, 401)}) or
        try truth(o, propertyNumberEquals, .{response, @as([*:0]const u8, "status"), @as(i32, 403)}) or
        try truth(o, invalidGrant, .{json})) {
        const description = try value(o, errorDescription, .{json});
        try o.put(owner, "unauthorizedDescription", description);
        return .{ .thrown = try expression(o.s.engine, newError, .{unauthorizedMessage, .{response, description}}) };
    }
    if (try truth(o, retryable, .{response}) and try attemptIndex(o, owner) < 3) {
        try o.put(owner, "lastError", try value(o, newError, .{statusMessage, .{@as([]const u8, "Kimi Code token refresh failed with status "), response, c.pi_js_undefined()}}));
        again.* = true;
        return .{ .returned = c.pi_js_undefined() };
    }
    const encoded = try value(o, jsonEncode, .{json});
    try o.put(owner, "text", encoded);
    return .{ .thrown = try expression(o.s.engine, newError, .{statusMessage, .{@as([]const u8, "Kimi Code token refresh failed with status "), response, encoded}}) };
}
