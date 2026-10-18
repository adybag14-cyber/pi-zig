//! c268154c auth/oauth/meta.ts: actual nested async bodies and Source Await.
//! Identity-token polling and API-key minting retain their distinct lifecycles.
const x = @import("native_ai_auth_helper_values.zig");
const c = x.c;
const af = x.af;
const functions = @import("native_node_function.zig");
const p = @import("native_public_values.zig");
const client_id = "1031625952748946";
const Stage = enum(i32) { device_response, device_json, poll_response, poll_json, mint_response, mint_json, login_device, login_identity, login_minted };
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

fn invokeJson(o: *x.Ops, response: c.JSValue) !c.JSValue { return duplicate(o, try o.invoke(response, "json", &.{})); }

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

fn tokenNow(o: *x.Ops) !c.JSValue { return duplicate(o, try o.invoke(try o.global("Date"), "now", &.{})); }

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

fn accessIsString(o: *x.Ops, json: c.JSValue) !c.JSValue { return boolean(o, c.JS_IsString(try optional(o, json, "access_token"))); }

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
    try o.put(module, "readJson", try declaration(o, module, "readJson", 1, readJsonBody));
    try o.put(module, "startDeviceAuthorization", try declaration(o, module, "startDeviceAuthorization", 1, startDeviceBody));
    try o.put(module, "pollForIdentityToken", try declaration(o, module, "pollForIdentityToken", 2, pollForIdentityBody));
    try o.put(module, "mintApiKey", try declaration(o, module, "mintApiKey", 2, mintBody));
    const exports = try o.object();
    try o.put(exports, "name", try o.text("Meta (Muse subscription)"));
    try o.put(exports, "isSubscription", boolean(o, true));
    try o.put(exports, "loginLabel", try o.text("Sign in with Meta"));
    try o.put(exports, "login", try declaration(o, module, "loginMeta", 1, loginBody));
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
    const callback = try o.get(module, "mintApiKey");
    return duplicate(o, try o.call(callback, c.pi_js_undefined(), &.{try o.get(input_credential, "refresh"), signal}));
}
const Request = enum { device, poll, mint };
fn formParameters(o: *x.Ops, kind: Request, source: c.JSValue) !c.JSValue {
    const constructor = try o.global("URLSearchParams");
    const fields = try o.object();
    if (kind == .poll) {
        try o.put(fields, "grant_type", try o.text("urn:ietf:params:oauth:grant-type:device_code"));
        try o.put(fields, "device_code", try o.get(source, "deviceCode"));
    }
    try o.put(fields, "client_id", try o.text(client_id));
    return duplicate(o, try x.guest.construct(o.s, constructor, &.{fields}));
}
fn encodedFields(o: *x.Ops, kind: Request, source: c.JSValue) !c.JSValue {
    // The constructor and its argument literal retire before the live method get.
    const parameters = try value(o, formParameters, .{kind, source});
    return duplicate(o, try o.invoke(parameters, "toString", &.{}));
}
fn bearer(o: *x.Ops, identity: c.JSValue) !c.JSValue {
    return duplicate(o, try concat(o, try o.text("Bearer "), try value(o, stringifyValue, .{identity})));
}
fn requestInit(o: *x.Ops, signal: c.JSValue, kind: Request, source: c.JSValue) !c.JSValue {
    const options = try o.object();
    try o.put(options, "method", try o.text("POST"));
    const headers = try o.object();
    if (kind == .mint) {
        try o.put(headers, "Accept", try o.text("application/json"));
        try o.put(headers, "Authorization", try value(o, bearer, .{source}));
        try o.put(headers, "Content-Type", try o.text("application/json"));
        try o.put(headers, "x-api-version", try o.text("1.0.0"));
    } else {
        try o.put(headers, "Content-Type", try o.text("application/x-www-form-urlencoded"));
        try o.put(headers, "Accept", try o.text("application/json"));
    }
    try o.put(options, "headers", headers);
    try o.put(options, "body", if (kind == .mint) try o.text("{}") else try value(o, encodedFields, .{kind, source}));
    try o.put(options, "signal", try value(o, requestSignal, .{signal}));
    return duplicate(o, options);
}
fn request(o: *x.Ops, signal: c.JSValue, kind: Request, source: c.JSValue) !c.JSValue {
    const fetch = try o.global("fetch");
    const address: []const u8 = switch (kind) {
        .device => "https://auth.meta.com/oidc/device/authorization/",
        .poll => "https://auth.meta.com/oidc/device/token/",
        .mint => "https://api.meta.ai/muse-code/key",
    };
    const url = try o.text(address);
    const options = try value(o, requestInit, .{signal, kind, source});
    return duplicate(o, try o.call(fetch, c.pi_js_undefined(), &.{url, options}));
}
fn trustedProperty(o: *x.Ops, json: c.JSValue, name: [*:0]const u8) !c.JSValue {
    const input = try optional(o, json, name);
    return trustedUrl(o, input);
}
fn positiveNumber(o: *x.Ops, input: c.JSValue) !c.JSValue {
    return if (try finitePositive(o, input)) duplicate(o, input) else c.pi_js_undefined();
}
fn positiveProperty(o: *x.Ops, json: c.JSValue, name: [*:0]const u8) !c.JSValue {
    const input = try optional(o, json, name);
    return positiveNumber(o, input);
}
fn detailKeys(o: *x.Ops) !c.JSValue {
    const result = try array(o);
    inline for (.{ "error_description", "detail", "message", "error" }, 0..) |name, position| {
        try index(o, result, position, try o.text(name));
    }
    return duplicate(o, result);
}
fn detailValue(o: *x.Ops, json: c.JSValue, key: c.JSValue) !c.JSValue {
    return if (x.nullish(json)) c.pi_js_undefined() else duplicate(o, try o.getKey(json, key));
}
fn trim(o: *x.Ops, input: c.JSValue) !c.JSValue { return duplicate(o, try o.invoke(input, "trim", &.{})); }
fn trimmedTemplate(o: *x.Ops, input: c.JSValue) !c.JSValue {
    return duplicate(o, try o.stringify(try value(o, trim, .{input})));
}
fn detailText(o: *x.Ops, input: c.JSValue) !c.JSValue {
    return duplicate(o, try concat(o, try o.text(": "), try value(o, trimmedTemplate, .{input})));
}
fn replaceLocal(engine: *x.em.Engine, slot: *c.JSValue, incoming: c.JSValue) !void {
    const previous = slot.*;
    slot.* = incoming;
    var completion = x.owned.Completion.initVoid(engine, {});
    completion.release(previous);
    return completion.finishVoid();
}
const DetailLocals = struct { key: c.JSValue, value: c.JSValue };
fn normalIteratorCall(o: *x.Ops, receiver: c.JSValue, called: *bool) !c.JSValue {
    const method = try o.get(receiver, "return");
    if (x.nullish(method)) return c.pi_js_undefined();
    called.* = true;
    return duplicate(o, try o.call(method, receiver, &.{}));
}
fn normalIteratorClose(engine: *x.em.Engine, iterator: *p.Iterator) !void {
    if (iterator.closed) return;
    iterator.closed = true;
    // OP_iterator_close drops the cached next method before reading return.
    const next_method = iterator.next_function;
    iterator.next_function = c.pi_js_undefined();
    var retirement = x.owned.Completion.initVoid(engine, {});
    retirement.release(next_method);
    try retirement.finishVoid();
    var called = false;
    const result = try expression(engine, normalIteratorCall, .{iterator.receiver, &called});
    // JS_CallFree retires the method before validating the returned value.
    var scope: x.Scope = .{ .engine = engine };
    const outcome: anyerror!void = if (called and !c.JS_IsObject(result)) p.typeError(&scope, "not an object") else {};
    var completion = x.owned.Completion.initVoid(engine, outcome);
    completion.release(result);
    completion.releaseScope(&scope);
    return completion.finishVoid();
}
fn detailRows(engine: *x.em.Engine, json: c.JSValue, iterator: *p.Iterator, locals: *DetailLocals, output: *c.JSValue, found: *bool) !void {
    while (try iterator.next()) |incoming| {
        // The next/done/value operations precede replacement of the old head.
        try replaceLocal(engine, &locals.key, incoming);
        // Source enters the body scope only after assigning the iteration head.
        try replaceLocal(engine, &locals.value, c.pi_js_undefined());
        try replaceLocal(engine, &locals.value, try expression(engine, detailValue, .{json, locals.key}));
        if (c.JS_IsString(locals.value)) {
            const nonempty = try expression(engine, trim, .{locals.value});
            const truthy = c.JS_ToBool(engine.context, nonempty) == 1;
            try discard(engine, nonempty);
            if (truthy) {
                output.* = try expression(engine, detailText, .{locals.value});
                found.* = true;
                try normalIteratorClose(engine, iterator);
                return;
            }
        }
    }
}
fn errorDetail(o: *x.Ops, json: c.JSValue) !c.JSValue {
    var iterator = try p.Iterator.initOwned(o.s.engine, try expression(o.s.engine, detailKeys, .{}));
    var locals: DetailLocals = .{ .key = c.pi_js_undefined(), .value = c.pi_js_undefined() };
    var output = c.pi_js_undefined();
    var found = false;
    const closed = iterator.finish(detailRows(o.s.engine, json, &iterator, &locals, &output, &found));
    const selected: anyerror!c.JSValue = if (closed) |_| (if (found) output else expression(o.s.engine, text, .{@as([]const u8, "")})) else |err| err;
    var completion = x.owned.Completion.initValue(o.s.engine, selected);
    if (closed) |_| {} else |_| completion.release(output);
    // The linked VM keeps uncaptured loop slots until function exit.
    completion.release(locals.key);
    completion.release(locals.value);
    return completion.finishValue();
}
fn statusMessage(o: *x.Ops, prefix: []const u8, response: c.JSValue, json: c.JSValue) !c.JSValue {
    var message = try concat(o, try o.text(prefix), try value(o, propertyString, .{response, @as([*:0]const u8, "status")}));
    message = try concat(o, message, try value(o, errorDetail, .{json}));
    return duplicate(o, message);
}
fn invalidDeviceMessage(o: *x.Ops, json: c.JSValue) !c.JSValue {
    return duplicate(o, try concat(o, try o.text("Invalid Meta device authorization response: "), try value(o, jsonTemplate, .{json})));
}
fn expiredSessionMessage(o: *x.Ops, response: c.JSValue, json: c.JSValue) !c.JSValue {
    var message = try concat(o, try o.text("Meta session expired (status "), try value(o, propertyString, .{response, @as([*:0]const u8, "status")}));
    message = try concat(o, message, try o.text("). Run \x60/login meta\x60 to sign in again."));
    return duplicate(o, try concat(o, message, try value(o, errorDetail, .{json})));
}
fn missingKeyMessage(o: *x.Ops, action_url: c.JSValue) !c.JSValue {
    const suffix = if (o.truthy(action_url)) try concat(o, try o.text(" Complete setup at "), try value(o, stringifyValue, .{action_url})) else try o.text("");
    return duplicate(o, try concat(o, try o.text("Meta did not issue an API key."), suffix));
}

fn startDeviceBody(engine: *x.em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue, state: *c.JSValue, completion: af.Completion, input: c.JSValue) !af.Action {
    if (completion == .rejected) return rejected(engine, input);
    return actionExpression(engine, startDeviceAdvance, .{x.arg(args, 0), roots[0], state, completion, input});
}
fn startDeviceAdvance(o: *x.Ops, signal: c.JSValue, module: c.JSValue, state: *c.JSValue, completion: af.Completion, input: c.JSValue) !af.Action {
    if (completion == .start) {
        const owner = try initialize(o, state);
        try setStage(o, owner, .device_response);
        return .{ .awaited = try expression(o.s.engine, request, .{signal, Request.device, c.pi_js_undefined()}) };
    }
    if (try getStage(o, state.*) == .device_response) {
        try o.put(state.*, "response", input);
        try setStage(o, state.*, .device_json);
        return .{ .awaited = try expression(o.s.engine, helper, .{module, @as([*:0]const u8, "readJson"), @as([]const c.JSValue, &.{input})}) };
    }
    try o.put(state.*, "json", input);
    const response = try o.get(state.*, "response");
    if (!try truth(o, propertyTruthy, .{response, @as([*:0]const u8, "ok")})) {
        return .{ .thrown = try expression(o.s.engine, newError, .{statusMessage, .{@as([]const u8, "Meta device authorization failed with status "), response, input}}) };
    }
    return actionExpression(o.s.engine, parseDevice, .{state.*, input});
}
fn parseDevice(o: *x.Ops, owner: c.JSValue, json: c.JSValue) !af.Action {
    const device_code = try optional(o, json, "device_code");
    try o.put(owner, "deviceCode", device_code);
    const user_code = try optional(o, json, "user_code");
    try o.put(owner, "userCode", user_code);
    var verification_uri = try value(o, trustedProperty, .{json, @as([*:0]const u8, "verification_uri_complete")});
    if (x.nullish(verification_uri)) verification_uri = try value(o, trustedProperty, .{json, @as([*:0]const u8, "verification_uri")});
    try o.put(owner, "verificationUri", verification_uri);
    if (!c.JS_IsString(device_code) or !o.truthy(device_code) or !c.JS_IsString(user_code) or !o.truthy(user_code) or !o.truthy(verification_uri)) {
        return .{ .thrown = try expression(o.s.engine, newError, .{invalidDeviceMessage, .{json}}) };
    }
    const result = try o.object();
    try o.put(result, "deviceCode", device_code);
    try o.put(result, "userCode", user_code);
    try o.put(result, "verificationUri", verification_uri);
    try o.put(result, "intervalSeconds", try value(o, positiveProperty, .{json, @as([*:0]const u8, "interval")}));
    try o.put(result, "expiresInSeconds", try value(o, positiveProperty, .{json, @as([*:0]const u8, "expires_in")}));
    return .{ .returned = duplicate(o, result) };
}
fn pollForIdentityBody(engine: *x.em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue, _: *c.JSValue, completion: af.Completion, _: c.JSValue) !af.Action {
    if (completion != .start) unreachable;
    return .{ .returned = try expression(engine, pollForIdentity, .{roots[0], x.arg(args, 0), x.arg(args, 1)}) };
}
fn pollForIdentity(o: *x.Ops, module: c.JSValue, device: c.JSValue, signal: c.JSValue) !c.JSValue {
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
        try setStage(o, owner, .poll_response);
        return .{ .awaited = try expression(o.s.engine, request, .{roots[2], Request.poll, roots[1]}) };
    }
    if (try getStage(o, state.*) == .poll_response) {
        try o.put(state.*, "response", input);
        try setStage(o, state.*, .poll_json);
        return .{ .awaited = try expression(o.s.engine, helper, .{roots[0], @as([*:0]const u8, "readJson"), @as([]const c.JSValue, &.{input})}) };
    }
    try o.put(state.*, "json", input);
    return .{ .returned = try expression(o.s.engine, pollDecision, .{try o.get(state.*, "response"), input}) };
}
fn failureKind(o: *x.Ops, json: c.JSValue) !c.JSValue {
    const problem = try optional(o, json, "error");
    const selected: i32 = if (try equalText(o, problem, "authorization_pending")) 1 else
        if (try equalText(o, problem, "slow_down")) 2 else
        if (try equalText(o, problem, "access_denied")) 3 else
        if (try equalText(o, problem, "expired_token")) 4 else 0;
    return integer(o, selected);
}
fn failureIndex(o: *x.Ops, json: c.JSValue) !i32 {
    const selected = try value(o, failureKind, .{json});
    var result: i32 = 0;
    var boundary: x.guest.Boundary = .{ .engine = o.s.engine };
    try boundary.begin();
    try boundary.finishStatus(c.JS_ToInt32(o.s.engine.context, &result, selected));
    return result;
}
fn pollDecision(o: *x.Ops, response: c.JSValue, json: c.JSValue) !c.JSValue {
    if (try truth(o, propertyTruthy, .{response, @as([*:0]const u8, "ok")}) and
        try truth(o, accessIsString, .{json}) and try truth(o, propertyTruthy, .{json, @as([*:0]const u8, "access_token")})) {
        const result = try resultStatus(o, "complete");
        try o.put(result, "value", try o.get(json, "access_token"));
        return duplicate(o, result);
    }
    // The switch discriminant is popped before the selected branch executes.
    switch (try failureIndex(o, json)) {
        1 => return duplicate(o, try resultStatus(o, "pending")),
        2 => {
            const result = try resultStatus(o, "slow_down");
            try o.put(result, "intervalSeconds", try value(o, positiveProperty, .{json, @as([*:0]const u8, "interval")}));
            return duplicate(o, result);
        },
        3 => return failedMessage(o, "Meta login was denied."),
        4 => return failedMessage(o, "Meta device authorization expired. Please restart login."),
        else => {
            const result = try resultStatus(o, "failed");
            try o.put(result, "message", try value(o, statusMessage, .{@as([]const u8, "Meta device token request failed with status "), response, json}));
            return duplicate(o, result);
        },
    }
}
fn mintBody(engine: *x.em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue, state: *c.JSValue, completion: af.Completion, input: c.JSValue) !af.Action {
    if (completion == .rejected) return rejected(engine, input);
    return actionExpression(engine, mintAdvance, .{args, roots[0], state, completion, input});
}
fn mintAdvance(o: *x.Ops, args: []const c.JSValue, module: c.JSValue, state: *c.JSValue, completion: af.Completion, input: c.JSValue) !af.Action {
    if (completion == .start) {
        const owner = try initialize(o, state);
        try setStage(o, owner, .mint_response);
        return .{ .awaited = try expression(o.s.engine, request, .{x.arg(args, 1), Request.mint, x.arg(args, 0)}) };
    }
    if (try getStage(o, state.*) == .mint_response) {
        try o.put(state.*, "response", input);
        try setStage(o, state.*, .mint_json);
        return .{ .awaited = try expression(o.s.engine, helper, .{module, @as([*:0]const u8, "readJson"), @as([]const c.JSValue, &.{input})}) };
    }
    try o.put(state.*, "json", input);
    return actionExpression(o.s.engine, mintDecision, .{x.arg(args, 0), state.*, input});
}
fn mintExpiry(o: *x.Ops) !c.JSValue {
    const now = try value(o, tokenNow, .{});
    return duplicate(o, try o.binary(0, now, integer(o, 86400000)));
}
fn mintDecision(o: *x.Ops, identity: c.JSValue, owner: c.JSValue, json: c.JSValue) !af.Action {
    const response = try o.get(owner, "response");
    if (try truth(o, propertyNumberEquals, .{response, @as([*:0]const u8, "status"), @as(i32, 401)}) or
        try truth(o, propertyNumberEquals, .{response, @as([*:0]const u8, "status"), @as(i32, 403)})) {
        return .{ .thrown = try expression(o.s.engine, newError, .{expiredSessionMessage, .{response, json}}) };
    }
    if (!try truth(o, propertyTruthy, .{response, @as([*:0]const u8, "ok")})) {
        return .{ .thrown = try expression(o.s.engine, newError, .{statusMessage, .{@as([]const u8, "Meta API key mint failed with status "), response, json}}) };
    }
    const api_key = try optional(o, json, "api_key");
    try o.put(owner, "apiKey", api_key);
    if (!c.JS_IsString(api_key) or !o.truthy(api_key)) {
        const action_url = try value(o, trustedProperty, .{json, @as([*:0]const u8, "action_url")});
        try o.put(owner, "actionUrl", action_url);
        return .{ .thrown = try expression(o.s.engine, newError, .{missingKeyMessage, .{action_url}}) };
    }
    const result = try o.object();
    try o.put(result, "type", try o.text("oauth"));
    try o.put(result, "refresh", identity);
    try o.put(result, "access", api_key);
    try o.put(result, "expires", try value(o, mintExpiry, .{}));
    return .{ .returned = duplicate(o, result) };
}
fn startLogin(o: *x.Ops, module: c.JSValue, interaction: c.JSValue) !c.JSValue {
    const callback = try o.get(module, "startDeviceAuthorization");
    return duplicate(o, try o.call(callback, c.pi_js_undefined(), &.{try o.get(interaction, "signal")}));
}
fn notifyDevice(o: *x.Ops, interaction: c.JSValue, device: c.JSValue) !void {
    const notify = try o.get(interaction, "notify");
    const message = try o.object();
    try o.put(message, "type", try o.text("device_code"));
    try o.put(message, "userCode", try o.get(device, "userCode"));
    try o.put(message, "verificationUri", try o.get(device, "verificationUri"));
    try o.put(message, "intervalSeconds", try o.get(device, "intervalSeconds"));
    try o.put(message, "expiresInSeconds", try o.get(device, "expiresInSeconds"));
    _ = try o.call(notify, interaction, &.{message});
}
fn loginPoll(o: *x.Ops, module: c.JSValue, owner: c.JSValue, interaction: c.JSValue) !c.JSValue {
    const callback = try o.get(module, "pollForIdentityToken");
    return duplicate(o, try o.call(callback, c.pi_js_undefined(), &.{try o.get(owner, "device"), try o.get(interaction, "signal")}));
}
fn notifyProgress(o: *x.Ops, interaction: c.JSValue) !void {
    const notify = try o.get(interaction, "notify");
    const message = try o.object();
    try o.put(message, "type", try o.text("progress"));
    try o.put(message, "message", try o.text("Enabling Meta Model API access..."));
    _ = try o.call(notify, interaction, &.{message});
}
fn loginMint(o: *x.Ops, module: c.JSValue, owner: c.JSValue, interaction: c.JSValue) !c.JSValue {
    const callback = try o.get(module, "mintApiKey");
    return duplicate(o, try o.call(callback, c.pi_js_undefined(), &.{try o.get(owner, "identityToken"), try o.get(interaction, "signal")}));
}
fn signalAborted(o: *x.Ops, interaction: c.JSValue) !c.JSValue {
    const signal = try o.get(interaction, "signal");
    return boolean(o, o.truthy(try o.get(signal, "aborted")));
}
fn loginCaught(o: *x.Ops, interaction: c.JSValue, owner: c.JSValue, reason: c.JSValue) !af.Action {
    try o.put(owner, "caughtError", reason);
    if (try truth(o, signalAborted, .{interaction})) {
        return .{ .thrown = try expression(o.s.engine, newError, .{text, .{@as([]const u8, "Login cancelled")}}) };
    }
    return .{ .thrown = duplicate(o, reason) };
}
fn loginBody(engine: *x.em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue, state: *c.JSValue, completion: af.Completion, input: c.JSValue) !af.Action {
    if (completion == .rejected) try @import("native_async_body.zig").enterRejectedContinuation(engine);
    const outcome = if (completion == .rejected) af.Action{ .thrown = c.JS_DupValue(engine.context, input) } else
        try actionExpression(engine, loginAdvance, .{x.arg(args, 0), roots[0], state, completion, input});
    return switch (outcome) {
        .returned, .awaited => outcome,
        .thrown => |reason| blk: {
            var caught = x.owned.Completion.initAction(engine, actionExpression(engine, loginCaught, .{x.arg(args, 0), state.*, reason}));
            caught.release(reason);
            break :blk try caught.finishAction();
        },
    };
}
fn loginAdvance(o: *x.Ops, interaction: c.JSValue, module: c.JSValue, state: *c.JSValue, completion: af.Completion, input: c.JSValue) !af.Action {
    if (completion == .start) {
        const owner = try initialize(o, state);
        try setStage(o, owner, .login_device);
        return .{ .awaited = try expression(o.s.engine, startLogin, .{module, interaction}) };
    }
    switch (try getStage(o, state.*)) {
        .login_device => {
            try o.put(state.*, "device", input);
            try statement(o.s.engine, notifyDevice, .{interaction, input});
            try setStage(o, state.*, .login_identity);
            return .{ .awaited = try expression(o.s.engine, loginPoll, .{module, state.*, interaction}) };
        },
        .login_identity => {
            try o.put(state.*, "identityToken", input);
            try statement(o.s.engine, notifyProgress, .{interaction});
            try setStage(o, state.*, .login_minted);
            return .{ .awaited = try expression(o.s.engine, loginMint, .{module, state.*, interaction}) };
        },
        .login_minted => return .{ .returned = duplicate(o, input) },
        else => unreachable,
    }
}
