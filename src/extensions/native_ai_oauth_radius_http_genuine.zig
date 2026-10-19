//! Exact c268 Radius OAuth HTTP declarations and local Error subclass.
//! Genuine AsyncFunctions own every Source Await; no manual Promise transport.
const x = @import("native_ai_auth_helper_values.zig");
const c = x.c;
const af = x.af;
const p = @import("native_public_values.zig");
const sync = @import("native_sync_arguments.zig");
const functions = @import("native_node_function.zig");
const frames = @import("native_public_lexical_frame.zig");
const error_class = @import("native_node_error_class.zig");
const Discovery = frames.Frame(enum { response, discovery, constructor, prefix, phase });
const ReadError = frames.Frame(enum { text, oauthError, description, data });
const Request = frames.Frame(enum { response, data, caught, phase });
const Phase = enum(i32) { response, json, error_body, error_text };
const Kind = enum { token, device };

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
fn attempt(engine: *x.em.Engine, comptime body: anytype, args: anytype) !af.Action {
    var outcome = x.owned.Completion.initValue(engine, expression(engine, body, args));
    return outcome.finishAction();
}
fn value(o: *x.Ops, comptime body: anytype, args: anytype) !c.JSValue {
    return o.own(try expression(o.s.engine, body, args));
}
fn dup(o: *x.Ops, input: c.JSValue) c.JSValue {
    return c.JS_DupValue(o.s.engine.context, input);
}
fn boolValue(o: *x.Ops, input: bool) c.JSValue {
    return c.pi_js_bool(o.s.engine.context, @intFromBool(input));
}
fn truth(engine: *x.em.Engine, comptime body: anytype, args: anytype) !bool {
    const result = try expression(engine, body, args);
    defer engine.freeValue(result);
    return c.JS_ToBool(engine.context, result) != 0;
}
fn property(o: *x.Ops, target: c.JSValue, name: [*:0]const u8) !c.JSValue {
    return dup(o, try o.get(target, name));
}
fn propertyTruthy(o: *x.Ops, target: c.JSValue, name: [*:0]const u8) !c.JSValue {
    return boolValue(o, o.truthy(try o.get(target, name)));
}
fn propertyString(o: *x.Ops, target: c.JSValue, name: [*:0]const u8) !c.JSValue {
    return boolValue(o, c.JS_IsString(try o.get(target, name)));
}
fn propertyIfString(o: *x.Ops, target: c.JSValue, name: [*:0]const u8) !c.JSValue {
    // The typeof operand is consumed before the conditional's second getter.
    if (!try truth(o.s.engine, propertyString, .{target, name})) return c.pi_js_undefined();
    return dup(o, try o.get(target, name));
}
fn callMethod(o: *x.Ops, receiver: c.JSValue, name: [*:0]const u8) !c.JSValue {
    return dup(o, try o.invoke(receiver, name, &.{}));
}
fn globalValue(o: *x.Ops, name: [*:0]const u8) !c.JSValue {
    return dup(o, try o.global(name));
}
fn construct(o: *x.Ops, constructor: c.JSValue, args: []const c.JSValue) !c.JSValue {
    return dup(o, try x.guest.construct(o.s, constructor, args));
}
fn newError(o: *x.Ops, text: []const u8) !c.JSValue {
    const constructor = try o.global("Error");
    return construct(o, constructor, &.{try o.text(text)});
}
fn part(o: *x.Ops, input: c.JSValue) !c.JSValue {
    // Template substitution performs ToString, never addition's default hint.
    return dup(o, try o.stringify(input));
}
fn append(o: *x.Ops, left: c.JSValue, right: c.JSValue) !c.JSValue {
    return o.binary(0, left, right);
}
fn raise(o: *x.Ops, reason: c.JSValue) !c.JSValue {
    // Actual Source throw, including rethrow and throw-await fulfillment.
    // Ordinary private DATA passes through the real throw operation unchanged.
    return o.s.engine.checked(c.JS_Throw(o.s.engine.context, dup(o, reason)));
}
fn phaseSet(frame: anytype, phase: Phase) !void {
    return frame.take(.phase, c.JS_NewInt32(frame.engine.context, @intFromEnum(phase)));
}
fn phaseGet(o: *x.Ops, frame: anytype) !Phase {
    var raw: c_int = 0;
    var boundary: x.guest.Boundary = .{ .engine = o.s.engine };
    try boundary.begin();
    try boundary.finishStatus(c.JS_ToInt32(o.s.engine.context, &raw, frame.get(.phase)));
    return @enumFromInt(raw);
}
fn initFrame(o: *x.Ops, comptime F: type, state: *c.JSValue) !*F {
    const frame = try F.createAsync(o.s);
    af.replaceState(o.s.engine, state, dup(o, frame.owner));
    return frame;
}
fn entered(engine: *x.em.Engine, completion: af.Completion) !void {
    if (completion == .rejected) try @import("native_async_body.zig").enterRejectedContinuation(engine);
}

// The actual class definition captures Error as superclass once. Its constructor
// resolves its own current [[Prototype]] before evaluating the super argument.
fn errorDetail(o: *x.Ops, args: []const c.JSValue) !c.JSValue {
    const status = x.arg(args, 0);
    const oauth_error = x.arg(args, 1);
    const description = x.arg(args, 2);
    if (o.truthy(oauth_error)) {
        if (!o.truthy(description)) return dup(o, oauth_error);
        var result = try value(o, part, .{oauth_error});
        result = try append(o, result, try o.text(": "));
        return dup(o, try append(o, result, try value(o, part, .{description})));
    }
    if (o.truthy(description)) return dup(o, description);
    const callable = try o.global("String");
    return dup(o, try o.call(callable, c.pi_js_undefined(), &.{status}));
}
fn prototype(o: *x.Ops, object: c.JSValue) !c.JSValue {
    var boundary: x.guest.Boundary = .{ .engine = o.s.engine };
    try boundary.begin();
    return dup(o, try boundary.finishValue(o.s, c.JS_GetPrototype(o.s.engine.context, object)));
}
fn errorSuper(o: *x.Ops, lexical_class: c.JSValue, new_target: c.JSValue, args: []const c.JSValue, detail: c.JSValue) !c.JSValue {
    const base = try value(o, prototype, .{lexical_class});
    var message = try value(o, part, .{x.arg(args, 3)});
    message = try append(o, message, try o.text(": "));
    message = try append(o, message, try value(o, part, .{detail}));
    var boundary: x.guest.Boundary = .{ .engine = o.s.engine };
    try boundary.begin();
    var super_args = [_]c.JSValue{message};
    const result = try boundary.finishValue(o.s, c.JS_CallConstructor2(o.s.engine.context, base, new_target, 1, &super_args));
    return dup(o, result);
}
fn errorConstructBody(o: *x.Ops, lexical_class: c.JSValue, new_target: c.JSValue, args: []const c.JSValue) !c.JSValue {
    // detail is a Source local. Arguments retain their original actual values.
    const detail = try value(o, errorDetail, .{args});
    const result = try value(o, errorSuper, .{lexical_class, new_target, args, detail});
    // Super's callee and operand stack have retired before field initialization.
    try o.put(result, "status", c.pi_js_undefined());
    try o.put(result, "oauthError", c.pi_js_undefined());
    try x.guest.set(o.s, result, "status", x.arg(args, 0));
    try x.guest.set(o.s, result, "oauthError", x.arg(args, 1));
    return dup(o, result);
}
fn errorConstruct(engine: *x.em.Engine, lexical_class: c.JSValue, new_target: c.JSValue, args: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
    return expression(engine, errorConstructBody, .{lexical_class, new_target, args});
}
fn createErrorClass(o: *x.Ops) !c.JSValue {
    const base = try o.global("Error");
    var constructor_parent = base;
    var base_prototype = base;
    if (c.JS_IsNull(base)) {
        // Actual class heritage null uses a null instance-prototype parent,
        // while the constructor itself inherits intrinsic Function.prototype.
        var boundary: x.guest.Boundary = .{ .engine = o.s.engine };
        try boundary.begin();
        constructor_parent = try boundary.finishValue(o.s, c.JS_GetFunctionProto(o.s.engine.context));
    } else {
        // IsConstructor precedes any observable prototype getter, exactly as
        // QuickJS js_define_class. Keep its actual ordinary TypeError messages.
        if (!c.JS_IsConstructor(o.s.engine.context, base))
            return o.typeError("parent class must be constructor");
        base_prototype = try o.get(base, "prototype");
        if (!c.JS_IsNull(base_prototype) and !c.JS_IsObject(base_prototype))
            return o.typeError("parent prototype must be an object or null");
    }
    const generation = try o.beforeAllocation();
    const proto = try o.allocation(c.JS_NewObjectProto(o.s.engine.context, base_prototype), generation);
    return error_class.create(o.s.engine, "OAuthResponseError", 4, proto, constructor_parent, errorConstruct, &.{});
}

fn newUrl(o: *x.Ops, path: []const u8, gateway: c.JSValue) !c.JSValue {
    const constructor = try o.global("URL");
    return construct(o, constructor, &.{try o.text(path), gateway});
}
fn propertyPart(o: *x.Ops, receiver: c.JSValue, name: [*:0]const u8) !c.JSValue {
    const incoming = try o.get(receiver, name);
    return dup(o, try o.stringify(incoming));
}
fn discoveryInit(o: *x.Ops, signal: c.JSValue) !c.JSValue {
    const init = try o.object();
    const headers = try o.object();
    try o.put(headers, "accept", try o.text("application/json"));
    try o.put(init, "headers", headers);
    try o.put(init, "signal", signal);
    return dup(o, init);
}
fn discoveryFetch(o: *x.Ops, gateway: c.JSValue, signal: c.JSValue) !c.JSValue {
    const fetch = try o.global("fetch");
    const url = try value(o, newUrl, .{@as([]const u8, "/v1/oauth"), gateway});
    const init = try value(o, discoveryInit, .{signal});
    return dup(o, try o.call(fetch, c.pi_js_undefined(), &.{url, init}));
}

fn discoveryPrefix(o: *x.Ops, gateway: c.JSValue, response: c.JSValue) !c.JSValue {
    var prefix = try o.text("Could not load Radius OAuth config from ");
    prefix = try append(o, prefix, try value(o, part, .{gateway}));
    prefix = try append(o, prefix, try o.text(": "));
    prefix = try append(o, prefix, try value(o, propertyPart, .{response, @as([*:0]const u8, "status")}));
    return dup(o, try append(o, prefix, try o.text(" ")));
}
fn discoveryError(o: *x.Ops, frame: *Discovery, input: c.JSValue) !c.JSValue {
    // Resume Source's operand stack, then clear its suspended copies. Both
    // operands retire with this new-expression before its explicit throw.
    const constructor = try o.own(dup(o, frame.get(.constructor)));
    try frame.clear(.constructor);
    const prefix = try o.own(dup(o, frame.get(.prefix)));
    try frame.clear(.prefix);
    const message = try append(o, prefix, try value(o, part, .{input}));
    return construct(o, constructor, &.{message});
}

fn invalidDiscovery(o: *x.Ops, gateway: c.JSValue) !c.JSValue {
    const constructor = try o.global("Error");
    const message = try append(o, try o.text("Invalid Radius OAuth config from "), try value(o, part, .{gateway}));
    return construct(o, constructor, &.{message});
}
fn discoveryResult(o: *x.Ops, discovery: c.JSValue) !c.JSValue {
    const result = try o.object();
    try o.put(result, "authorizationEndpoint", try o.get(discovery, "authorizationEndpoint"));
    return dup(o, result);
}
fn discoveryAdvance(o: *x.Ops, args: []const c.JSValue, state: *c.JSValue, completion: af.Completion, input: c.JSValue) !af.Action {
    if (completion == .start) {
        const frame = try initFrame(o, Discovery, state);
        try phaseSet(frame, .response);
        return .{ .awaited = try expression(o.s.engine, discoveryFetch, .{x.arg(args, 0), x.arg(args, 1)}) };
    }
    const frame = Discovery.from(state.*);
    if (completion == .rejected) {
        // A rejected text Await abandons its suspended new-expression operands.
        // Forwarding this rejection does not introduce a Source throw operation.
        _ = try o.own(dup(o, input));
        try frame.clear(.constructor);
        try frame.clear(.prefix);
        return .{ .thrown = dup(o, input) };
    }
    switch (try phaseGet(o, frame)) {
        .response => {
            try frame.copy(.response, input);
            if (!try truth(o.s.engine, propertyTruthy, .{input, @as([*:0]const u8, "ok")})) {
                // new Error and the entire prefix stay on Source's operand stack
                // through response.text's genuine Await.
                try frame.take(.constructor, expression(o.s.engine, globalValue, .{@as([*:0]const u8, "Error")}));
                try frame.take(.prefix, expression(o.s.engine, discoveryPrefix, .{x.arg(args, 0), input}));
                try phaseSet(frame, .error_text);
                return .{ .awaited = try expression(o.s.engine, callMethod, .{input, @as([*:0]const u8, "text")}) };
            }
            try phaseSet(frame, .json);
            return .{ .awaited = try expression(o.s.engine, callMethod, .{input, @as([*:0]const u8, "json")}) };
        },
        .error_text => return .{ .thrown = try expression(o.s.engine, raise, .{try value(o, discoveryError, .{frame, input})}) },
        .json => {
            try frame.copy(.discovery, input);
            if (!try truth(o.s.engine, propertyString, .{input, @as([*:0]const u8, "authorizationEndpoint")}))
                return .{ .thrown = try expression(o.s.engine, raise, .{try value(o, invalidDiscovery, .{x.arg(args, 0)})}) };
            return .{ .returned = try expression(o.s.engine, discoveryResult, .{input}) };
        },
        .error_body => unreachable,
    }
}
fn discoveryBody(engine: *x.em.Engine, _: c.JSValue, args: []const c.JSValue, _: []const c.JSValue, state: *c.JSValue, completion: af.Completion, input: c.JSValue) !af.Action {
    try entered(engine, completion);
    return actionExpression(engine, discoveryAdvance, .{args, state, completion, input});
}
fn emptyCatch(engine: *x.em.Engine, _: c.JSValue, _: *sync.Arguments, _: []const c.JSValue) !c.JSValue {
    return expression(engine, emptyString, .{});
}
fn emptyString(o: *x.Ops) !c.JSValue { return dup(o, try o.text("")); }
fn errorText(o: *x.Ops, response: c.JSValue) !c.JSValue {
    const pending = try value(o, callMethod, .{response, @as([*:0]const u8, "text")});
    const callable = try o.get(pending, "catch");
    const recover = try o.own(try functions.createArrowWithArguments(o.s.engine, "", 0,
        .{ .formal_count = 0, .callback = emptyCatch }, &.{}));
    return dup(o, try o.call(callable, pending, &.{recover}));
}
fn jsonParse(o: *x.Ops, text: c.JSValue) !c.JSValue {
    const receiver = try o.global("JSON");
    return dup(o, try o.invoke(receiver, "parse", &.{text}));
}
fn readErrorData(o: *x.Ops, frame: *ReadError) !c.JSValue {
    try frame.take(.data, expression(o.s.engine, jsonParse, .{frame.get(.text)}));
    try frame.take(.oauthError, expression(o.s.engine, propertyIfString, .{frame.get(.data), @as([*:0]const u8, "error")}));
    try frame.take(.description, expression(o.s.engine, propertyIfString, .{frame.get(.data), @as([*:0]const u8, "error_description")}));
    return c.pi_js_undefined();
}
fn createResponseError(o: *x.Ops, response: c.JSValue, message: c.JSValue, constructor: c.JSValue, frame: *ReadError) !c.JSValue {
    const status = try o.get(response, "status");
    return construct(o, constructor, &.{status, frame.get(.oauthError), frame.get(.description), message});
}
fn readErrorAdvance(o: *x.Ops, args: []const c.JSValue, roots: []const c.JSValue, state: *c.JSValue, completion: af.Completion, input: c.JSValue) !af.Action {
    if (completion == .start) {
        _ = try initFrame(o, ReadError, state);
        return .{ .awaited = try expression(o.s.engine, errorText, .{x.arg(args, 0)}) };
    }
    if (completion == .rejected) return .{ .thrown = dup(o, input) };
    const frame = ReadError.from(state.*);
    try frame.copy(.text, input);
    try frame.take(.oauthError, c.pi_js_undefined());
    try frame.take(.description, c.pi_js_undefined());
    if (o.truthy(input)) {
        const outcome = try attempt(o.s.engine, readErrorData, .{frame});
        switch (outcome) {
            .returned => |result| _ = try o.own(result),
            .thrown => |reason| {
                // Catch without binding consumes its actual ordinary reason.
                // An independently produced fatal always leaves attempt().
                var release = x.owned.Completion.initVoid(o.s.engine, {});
                release.release(reason);
                try release.finishVoid();
                try frame.copy(.description, frame.get(.text));
            },
            .awaited => unreachable,
        }
    }
    return .{ .returned = try expression(o.s.engine, createResponseError, .{x.arg(args, 0), x.arg(args, 1), roots[0], frame}) };
}
fn readErrorBody(engine: *x.em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue, state: *c.JSValue, completion: af.Completion, input: c.JSValue) !af.Action {
    try entered(engine, completion);
    return actionExpression(engine, readErrorAdvance, .{args, roots, state, completion, input});
}

fn deviceBodyForm(o: *x.Ops) !c.JSValue {
    const constructor = try o.global("URLSearchParams");
    const fields = try o.object();
    try o.put(fields, "client_id", try o.text("pi-gateway"));
    try o.put(fields, "scope", try o.text("gateway offline_access"));
    return construct(o, constructor, &.{fields});
}
fn requestInit(o: *x.Ops, comptime kind: Kind, args: []const c.JSValue) !c.JSValue {
    const init = try o.object();
    try o.put(init, "method", try o.text("POST"));
    const headers = try o.object();
    try o.put(headers, "accept", try o.text("application/json"));
    try o.put(headers, "content-type", try o.text("application/x-www-form-urlencoded"));
    try o.put(init, "headers", headers);
    const body = if (kind == .token) x.arg(args, 1) else try value(o, deviceBodyForm, .{});
    try o.put(init, "body", body);
    try o.put(init, "signal", x.arg(args, if (kind == .token) 2 else 1));
    return dup(o, init);
}
fn requestFetch(o: *x.Ops, comptime kind: Kind, args: []const c.JSValue) !c.JSValue {
    const fetch = try o.global("fetch");
    const url = try value(o, newUrl, .{
        @as([]const u8, if (kind == .token) "/v1/oauth/token" else "/v1/oauth/device"), x.arg(args, 0),
    });
    const init = try value(o, requestInit, .{kind, args});
    return dup(o, try o.call(fetch, c.pi_js_undefined(), &.{url, init}));
}

fn caughtFetch(o: *x.Ops, frame: *Request, signal: c.JSValue, reason: c.JSValue) !af.Action {
    try frame.copy(.caught, reason);
    if (try truth(o.s.engine, propertyTruthy, .{signal, @as([*:0]const u8, "aborted")}))
        return .{ .thrown = try expression(o.s.engine, raise, .{try value(o, newError, .{@as([]const u8, "Login cancelled")})}) };
    return .{ .thrown = try expression(o.s.engine, raise, .{frame.get(.caught)}) };
}

fn callReadError(o: *x.Ops, callable: c.JSValue, response: c.JSValue, comptime kind: Kind) !c.JSValue {
    const message = try o.text(if (kind == .token) "Radius OAuth token request failed" else "Radius OAuth device authorization failed");
    return dup(o, try o.call(callable, c.pi_js_undefined(), &.{response, message}));
}
fn dateNow(o: *x.Ops) !c.JSValue {
    const date = try o.global("Date");
    return dup(o, try o.invoke(date, "now", &.{}));
}
fn milliseconds(o: *x.Ops, data: c.JSValue) !c.JSValue {
    return dup(o, try o.binary(2, try o.get(data, "expires_in"), c.JS_NewInt32(o.s.engine.context, 1000)));
}
fn expirySum(o: *x.Ops, data: c.JSValue) !c.JSValue {
    const now = try value(o, dateNow, .{});
    const duration = try value(o, milliseconds, .{data});
    return dup(o, try o.binary(0, now, duration));
}
fn expiry(o: *x.Ops, data: c.JSValue) !c.JSValue {
    // Addition consumes the arbitrary Date.now operand before subtraction.
    const sum = try value(o, expirySum, .{data});
    return dup(o, try o.binary(1, sum, c.JS_NewInt32(o.s.engine.context, 60_000)));
}

fn tokenResult(o: *x.Ops, data: c.JSValue) !c.JSValue {
    const result = try o.object();
    try o.put(result, "type", try o.text("oauth"));
    try o.put(result, "access", try value(o, property, .{data, @as([*:0]const u8, "access_token")}));
    try o.put(result, "refresh", try value(o, property, .{data, @as([*:0]const u8, "refresh_token")}));
    try o.put(result, "expires", try value(o, expiry, .{data}));
    try o.put(result, "scope", try value(o, property, .{data, @as([*:0]const u8, "scope")}));
    return dup(o, result);
}
fn deviceValid(engine: *x.em.Engine, data: c.JSValue) !bool {
    inline for (.{ "device_code", "user_code", "verification_uri", "expires_in" }) |name|
        if (!try truth(engine, propertyTruthy, .{data, @as([*:0]const u8, name)})) return false;
    return true;
}
fn deviceResult(o: *x.Ops, data: c.JSValue) !c.JSValue {
    const result = try o.object();
    inline for (.{ "device_code", "user_code", "verification_uri", "expires_in", "interval" }) |name|
        try o.put(result, name, try value(o, property, .{data, @as([*:0]const u8, name)}));
    return dup(o, result);
}
fn requestAdvance(o: *x.Ops, comptime kind: Kind, args: []const c.JSValue, roots: []const c.JSValue, state: *c.JSValue, completion: af.Completion, input: c.JSValue) !af.Action {
    const signal = x.arg(args, if (kind == .token) 2 else 1);
    if (completion == .start) {
        const frame = try initFrame(o, Request, state);
        // Source let response is initialized before entry into the try.
        try frame.take(.response, c.pi_js_undefined());
        try phaseSet(frame, .response);
        const request = try attempt(o.s.engine, requestFetch, .{kind, args});
        switch (request) {
            .returned => |pending| return .{ .awaited = pending },
            .thrown => |reason| {
                _ = try o.own(reason);
                return caughtFetch(o, frame, signal, reason);
            },
            .awaited => unreachable,
        }
    }
    const frame = Request.from(state.*);
    const phase = try phaseGet(o, frame);
    if (completion == .rejected) {
        if (phase == .response) return caughtFetch(o, frame, signal, input);
        return .{ .thrown = dup(o, input) };
    }
    switch (phase) {
        .response => {
            // Assignment publishes before it retires the previous Source local.
            try frame.copy(.response, input);
            if (!try truth(o.s.engine, propertyTruthy, .{input, @as([*:0]const u8, "ok")})) {
                try phaseSet(frame, .error_body);
                return .{ .awaited = try expression(o.s.engine, callReadError, .{roots[0], input, kind}) };
            }
            try phaseSet(frame, .json);
            return .{ .awaited = try expression(o.s.engine, callMethod, .{input, @as([*:0]const u8, "json")}) };
        },
        // This is Source "throw await": the resolved Error object is DATA until
        // the explicit throw completion, without name/brand/provenance checks.
        .error_body => return .{ .thrown = try expression(o.s.engine, raise, .{input}) },
        .json => {
            try frame.copy(.data, input);
            if (kind == .token) return .{ .returned = try expression(o.s.engine, tokenResult, .{input}) };
            if (!try deviceValid(o.s.engine, input))
                return .{ .thrown = try expression(o.s.engine, raise, .{try value(o, newError, .{@as([]const u8, "Radius OAuth device authorization response is missing required fields")})}) };
            return .{ .returned = try expression(o.s.engine, deviceResult, .{input}) };
        },
        .error_text => unreachable,
    }
}
fn RequestBody(comptime kind: Kind) type {
    return struct {
        fn call(engine: *x.em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue, state: *c.JSValue, completion: af.Completion, input: c.JSValue) !af.Action {
            try entered(engine, completion);
            return actionExpression(engine, requestAdvance, .{kind, args, roots, state, completion, input});
        }
    };
}
fn createBody(o: *x.Ops) !c.JSValue {
    const constructor = try value(o, createErrorClass, .{});
    const read_error = try o.own(try af.createResumableWithClose(o.s.engine, "readOAuthResponseError", 2,
        readErrorBody, &.{constructor}, ReadError.closeAtAsyncTerminal));
    const discovery = try o.own(try af.createResumableWithClose(o.s.engine, "loadRadiusOAuthDiscovery", 2,
        discoveryBody, &.{}, Discovery.closeAtAsyncTerminal));
    const token = try o.own(try af.createResumableWithClose(o.s.engine, "requestOAuthToken", 3,
        RequestBody(.token).call, &.{read_error}, Request.closeAtAsyncTerminal));
    const device = try o.own(try af.createResumableWithClose(o.s.engine, "requestDeviceAuthorization", 2,
        RequestBody(.device).call, &.{read_error}, Request.closeAtAsyncTerminal));
    const result = try o.object();
    try o.put(result, "OAuthResponseError", constructor);
    try o.put(result, "readOAuthResponseError", read_error);
    try o.put(result, "loadRadiusOAuthDiscovery", discovery);
    try o.put(result, "requestOAuthToken", token);
    try o.put(result, "requestDeviceAuthorization", device);
    return dup(o, result);
}
/// Internal lexical module, consumed by the Radius OAuth factory. This object
/// does not add exports to the Source namespace.
pub fn create(engine: *x.em.Engine) !c.JSValue {
    try engine.checkNativeEntry();
    var invocation: x.em.Engine.NativeInvocation = .{};
    engine.enterNativeInvocation(&invocation);
    return x.finishInvocation(engine, &invocation, expression(engine, createBody, .{}));
}
