//! Actual c268154c Anthropic OAuth module, ordinary helpers and genuine AF bodies.
//! Both login paths retain the actual shared import owners and Source Await steps.
//! No production JavaScript is evaluated by this source port.
const x = @import("native_ai_auth_helper_values.zig");
const c = x.c;
const af = x.af;
const functions = @import("native_node_function.zig");
const callback_server = @import("native_ai_oauth_callback_server.zig");
const p = @import("native_public_values.zig");
const h = @import("native_sdk_session_locals.zig");
const frames = @import("native_public_lexical_frame.zig");
const authorize_url = "https://claude.ai/oauth/authorize";
const token_url = "https://platform.claude.com/v1/oauth/token";
const copy_redirect_uri = "https://platform.claude.com/oauth/code/callback";
const scopes = "org:create_api_key user:profile user:inference user:sessions:claude_code user:mcp_servers user:file_upload";
const Stage = enum(i32) {
    post_response, post_text, token_response, login_method,
    browser_pkce, browser_callback, browser_input, browser_exchange,
    copy_pkce, copy_input, copy_exchange,
};
const TokenKind = enum { exchange, refresh };
const ParseFrame = h.Frame(enum { value, url, code, state, params });
const DetailFrame = h.Frame(enum { details, error_with_code });
const BrowserLocal = enum { verifier, challenge, startCallbackServer, callback, redirectUri, authParams, result, code, state, parsed, interactionCapture };
const BrowserFrame = frames.Frame(BrowserLocal);

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

fn property(o: *x.Ops, receiver: c.JSValue, name: [*:0]const u8) !c.JSValue { return duplicate(o, try o.get(receiver, name)); }

// Each substitution completes intrinsic ToString in its own expression scope.
// That scope retires a temporary getter/call result before a later substitution.
fn stringifyValue(o: *x.Ops, input: c.JSValue) !c.JSValue {
    return duplicate(o, try o.stringify(input));
}
fn propertyString(o: *x.Ops, receiver: c.JSValue, name: [*:0]const u8) !c.JSValue {
    return duplicate(o, try o.stringify(try o.get(receiver, name)));
}
fn expressionString(o: *x.Ops, comptime render: anytype, args: anytype) !c.JSValue {
    return duplicate(o, try o.stringify(try value(o, render, args)));
}
fn propertyTruthy(o: *x.Ops, receiver: c.JSValue, name: [*:0]const u8) !c.JSValue { return boolean(o, o.truthy(try o.get(receiver, name))); }
fn propertyIsString(o: *x.Ops, receiver: c.JSValue, name: [*:0]const u8) !c.JSValue { return boolean(o, c.JS_IsString(try o.get(receiver, name))); }
fn propertyUndefined(o: *x.Ops, receiver: c.JSValue, name: [*:0]const u8) !c.JSValue { return boolean(o, c.JS_IsUndefined(try o.get(receiver, name))); }
fn equalText(o: *x.Ops, input: c.JSValue, expected: []const u8) !bool { return c.JS_IsStrictEqual(o.s.engine.context, input, try o.text(expected)); }
fn propertyEqualsText(o: *x.Ops, receiver: c.JSValue, name: [*:0]const u8, expected: []const u8) !c.JSValue { return boolean(o, try equalText(o, try o.get(receiver, name), expected)); }


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

fn constructValue(o: *x.Ops, name: [*:0]const u8, input: c.JSValue) !c.JSValue {
    const constructor = try o.global(name);
    return duplicate(o, try x.guest.construct(o.s, constructor, &.{input}));
}
fn trimInput(o: *x.Ops, input: c.JSValue) !c.JSValue {
    return duplicate(o, try o.invoke(input, "trim", &.{}));
}
fn includesText(o: *x.Ops, input: c.JSValue, expected: []const u8) !c.JSValue {
    const method = try o.get(input, "includes");
    return boolean(o, o.truthy(try o.call(method, input, &.{try o.text(expected)})));
}
fn emptyObject(o: *x.Ops) !c.JSValue { return duplicate(o, try o.object()); }
fn inputRecord(o: *x.Ops, input: c.JSValue) !c.JSValue {
    const result = try o.object();
    try o.put(result, "code", input);
    return duplicate(o, result);
}
fn urlParameter(o: *x.Ops, url: c.JSValue, name: []const u8) !c.JSValue {
    const receiver = try o.get(url, "searchParams");
    const method = try o.get(receiver, "get");
    const result = try o.call(method, receiver, &.{try o.text(name)});
    return if (x.nullish(result)) c.pi_js_undefined() else duplicate(o, result);
}
fn parameter(o: *x.Ops, params: c.JSValue, name: []const u8) !c.JSValue {
    const method = try o.get(params, "get");
    const result = try o.call(method, params, &.{try o.text(name)});
    return if (x.nullish(result)) c.pi_js_undefined() else duplicate(o, result);
}
fn parameterRecord(o: *x.Ops, receiver: c.JSValue, comptime url: bool) !c.JSValue {
    const result = try o.object();
    const reader = if (url) urlParameter else parameter;
    try o.put(result, "code", try value(o, reader, .{receiver, @as([]const u8, "code")}));
    try o.put(result, "state", try value(o, reader, .{receiver, @as([]const u8, "state")}));
    return duplicate(o, result);
}
fn parseUrl(o: *x.Ops, frame: *ParseFrame) !c.JSValue {
    try frame.set(.url, expression(o.s.engine, constructValue, .{@as([*:0]const u8, "URL"), frame.get(.value)}));
    return expression(o.s.engine, parameterRecord, .{frame.get(.url), true});
}
fn splitInput(o: *x.Ops, input: c.JSValue) !c.JSValue {
    const method = try o.get(input, "split");
    return duplicate(o, try o.call(method, input, &.{try o.text("#"), integer(o, 2)}));
}
fn normalIteratorCall(o: *x.Ops, receiver: c.JSValue, called: *bool) !c.JSValue {
    const method = try o.get(receiver, "return");
    if (x.nullish(method)) return c.pi_js_undefined();
    called.* = true;
    return duplicate(o, try o.call(method, receiver, &.{}));
}
fn normalIteratorClose(engine: *x.em.Engine, iterator: *p.Iterator) !void {
    if (iterator.closed) return;
    iterator.closed = true;
    const next_method = iterator.next_function;
    iterator.next_function = c.pi_js_undefined();
    var retirement = x.owned.Completion.initVoid(engine, {});
    retirement.release(next_method);
    try retirement.finishVoid();
    var called = false;
    const result = try expression(engine, normalIteratorCall, .{iterator.receiver, &called});
    var scope: x.Scope = .{ .engine = engine };
    const outcome: anyerror!void = if (called and !c.JS_IsObject(result)) p.typeError(&scope, "not an object") else {};
    var completion = x.owned.Completion.initVoid(engine, outcome);
    completion.release(result);
    completion.releaseScope(&scope);
    return completion.finishVoid();
}
fn splitBindings(engine: *x.em.Engine, frame: *ParseFrame, iterator: *p.Iterator) !void {
    try frame.set(.code, (try iterator.next()) orelse c.pi_js_undefined());
    try frame.set(.state, if (iterator.closed) c.pi_js_undefined() else (try iterator.next()) orelse c.pi_js_undefined());
    return normalIteratorClose(engine, iterator);
}
fn bindingRecord(o: *x.Ops, frame: *ParseFrame) !c.JSValue {
    const result = try o.object();
    try o.put(result, "code", frame.get(.code));
    try o.put(result, "state", frame.get(.state));
    return duplicate(o, result);
}
fn parseBody(engine: *x.em.Engine, frame: *ParseFrame, input: c.JSValue) !c.JSValue {
    try frame.set(.value, expression(engine, trimInput, .{input}));
    if (!h.truthy(engine, frame.get(.value))) return expression(engine, emptyObject, .{});
    const tried = try attempt(engine, parseUrl, .{frame});
    switch (tried) {
        .returned => |result| return result,
        .thrown => |reason| try discard(engine, reason),
        .awaited => unreachable,
    }
    if (h.truthy(engine, try expression(engine, includesText, .{frame.get(.value), @as([]const u8, "#")}))) {
        var iterator = try p.Iterator.initOwned(engine, try expression(engine, splitInput, .{frame.get(.value)}));
        try iterator.finish(splitBindings(engine, frame, &iterator));
        return expression(engine, bindingRecord, .{frame});
    }
    if (h.truthy(engine, try expression(engine, includesText, .{frame.get(.value), @as([]const u8, "code=")}))) {
        try frame.set(.params, expression(engine, constructValue, .{@as([*:0]const u8, "URLSearchParams"), frame.get(.value)}));
        return expression(engine, parameterRecord, .{frame.get(.params), false});
    }
    return expression(engine, inputRecord, .{frame.get(.value)});
}
fn parseInputCall(engine: *x.em.Engine, _: c.JSValue, args: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
    var frame = ParseFrame.init(engine);
    return frame.finish(parseBody(engine, &frame, x.arg(args, 0)));
}
fn isErrorInstance(o: *x.Ops, reason: c.JSValue) !c.JSValue {
    const constructor = try o.global("Error");
    var boundary: x.guest.Boundary = .{ .engine = o.s.engine };
    try boundary.begin();
    const result = c.JS_IsInstanceOf(o.s.engine.context, reason, constructor);
    try boundary.finishStatus(if (result < 0) -1 else 0);
    return boolean(o, result != 0);
}
fn initialDetailText(o: *x.Ops, reason: c.JSValue) !c.JSValue {
    const name = try value(o, propertyString, .{reason, @as([*:0]const u8, "name")});
    const first = try o.binary(0, name, try o.text(": "));
    const message = try value(o, propertyString, .{reason, @as([*:0]const u8, "message")});
    return duplicate(o, try o.binary(0, first, message));
}
fn initialDetails(o: *x.Ops, reason: c.JSValue) !c.JSValue {
    const result = try array(o);
    try x.guest.index(o.s, result, 0, try value(o, initialDetailText, .{reason}));
    return duplicate(o, result);
}
fn detailCode(o: *x.Ops, reason: c.JSValue) !c.JSValue {
    const prefix = try o.text("code=");
    const code = try value(o, propertyString, .{reason, @as([*:0]const u8, "code")});
    return duplicate(o, try o.binary(0, prefix, code));
}
fn detailErrno(o: *x.Ops, reason: c.JSValue) !c.JSValue {
    const prefix = try o.text("errno=");
    // Source explicitly calls the live global String before template ToString.
    const number = try value(o, expressionString, .{stringCallProperty, .{reason, @as([*:0]const u8, "errno")}});
    return duplicate(o, try o.binary(0, prefix, number));
}
fn causeDetail(o: *x.Ops, module: c.JSValue, reason: c.JSValue) !c.JSValue {
    const callable = try o.get(module, "formatErrorDetails");
    return duplicate(o, try o.call(callable, c.pi_js_undefined(), &.{try o.get(reason, "cause")}));
}
fn detailCause(o: *x.Ops, module: c.JSValue, reason: c.JSValue) !c.JSValue {
    const prefix = try o.text("cause=");
    const detail = try value(o, expressionString, .{causeDetail, .{module, reason}});
    return duplicate(o, try o.binary(0, prefix, detail));
}
fn detailStack(o: *x.Ops, reason: c.JSValue) !c.JSValue {
    const prefix = try o.text("stack=");
    const stack = try value(o, propertyString, .{reason, @as([*:0]const u8, "stack")});
    return duplicate(o, try o.binary(0, prefix, stack));
}
fn pushDetail(o: *x.Ops, details: c.JSValue, comptime render: anytype, args: anytype) !void {
    const method = try o.get(details, "push");
    const entry = try value(o, render, args);
    _ = try o.call(method, details, &.{entry});
}
fn joinDetails(o: *x.Ops, details: c.JSValue) !c.JSValue {
    const method = try o.get(details, "join");
    return duplicate(o, try o.call(method, details, &.{try o.text("; ")}));
}
fn stringCall(o: *x.Ops, reason: c.JSValue) !c.JSValue {
    const callable = try o.global("String");
    return duplicate(o, try o.call(callable, c.pi_js_undefined(), &.{reason}));
}
fn detailBody(engine: *x.em.Engine, frame: *DetailFrame, module: c.JSValue, reason: c.JSValue) !c.JSValue {
    if (!h.truthy(engine, try expression(engine, isErrorInstance, .{reason}))) return expression(engine, stringCall, .{reason});
    try frame.set(.details, expression(engine, initialDetails, .{reason}));
    try frame.set(.error_with_code, h.duplicate(engine, reason));
    if (h.truthy(engine, try expression(engine, propertyTruthy, .{frame.get(.error_with_code), @as([*:0]const u8, "code")})))
        try statement(engine, pushDetail, .{frame.get(.details), detailCode, .{frame.get(.error_with_code)}});
    if (!h.truthy(engine, try expression(engine, propertyUndefined, .{frame.get(.error_with_code), @as([*:0]const u8, "errno")})))
        try statement(engine, pushDetail, .{frame.get(.details), detailErrno, .{frame.get(.error_with_code)}});
    if (!h.truthy(engine, try expression(engine, propertyUndefined, .{reason, @as([*:0]const u8, "cause")})))
        try statement(engine, pushDetail, .{frame.get(.details), detailCause, .{module, reason}});
    if (h.truthy(engine, try expression(engine, propertyTruthy, .{reason, @as([*:0]const u8, "stack")})))
        try statement(engine, pushDetail, .{frame.get(.details), detailStack, .{reason}});
    return expression(engine, joinDetails, .{frame.get(.details)});
}
fn errorDetailsCall(engine: *x.em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    var frame = DetailFrame.init(engine);
    return frame.finish(detailBody(engine, &frame, roots[0], x.arg(args, 0)));
}

// postJson's request operands finish before the corresponding guest call.
fn invokeNoArgs(o: *x.Ops, receiver: c.JSValue, name: [*:0]const u8) !c.JSValue {
    return duplicate(o, try o.invoke(receiver, name, &.{}));
}
fn stringCallProperty(o: *x.Ops, receiver: c.JSValue, name: [*:0]const u8) !c.JSValue {
    const callable = try o.global("String");
    return duplicate(o, try o.call(callable, c.pi_js_undefined(), &.{try o.get(receiver, name)}));
}
fn jsonString(o: *x.Ops, body: c.JSValue) !c.JSValue {
    const receiver = try o.global("JSON");
    const method = try o.get(receiver, "stringify");
    return duplicate(o, try o.call(method, receiver, &.{body}));
}
fn abortTimeout(o: *x.Ops) !c.JSValue {
    const receiver = try o.global("AbortSignal");
    const callable = try o.get(receiver, "timeout");
    return duplicate(o, try o.call(callable, receiver, &.{integer(o, 30000)}));
}
fn abortSources(o: *x.Ops, signal: c.JSValue) !c.JSValue {
    const list = try array(o);
    try x.guest.index(o.s, list, 0, signal);
    try x.guest.index(o.s, list, 1, try value(o, abortTimeout, .{}));
    return duplicate(o, list);
}
fn combinedSignal(o: *x.Ops, signal: c.JSValue) !c.JSValue {
    const receiver = try o.global("AbortSignal");
    const callable = try o.get(receiver, "any");
    const sources = try value(o, abortSources, .{signal});
    return duplicate(o, try o.call(callable, receiver, &.{sources}));
}
fn postInit(o: *x.Ops, body: c.JSValue, signal: c.JSValue) !c.JSValue {
    const init = try o.object();
    try o.put(init, "method", try o.text("POST"));
    const headers = try o.object();
    try o.put(headers, "Content-Type", try o.text("application/json"));
    try o.put(headers, "Accept", try o.text("application/json"));
    try o.put(init, "headers", headers);
    try o.put(init, "body", try value(o, jsonString, .{body}));
    try o.put(init, "signal", try value(o, combinedSignal, .{signal}));
    return duplicate(o, init);
}
fn fetchPost(o: *x.Ops, url: c.JSValue, body: c.JSValue, signal: c.JSValue) !c.JSValue {
    const callable = try o.global("fetch");
    const init = try value(o, postInit, .{body, signal});
    return duplicate(o, try o.call(callable, c.pi_js_undefined(), &.{url, init}));
}
fn postErrorText(o: *x.Ops, response: c.JSValue, url: c.JSValue, body: c.JSValue) !c.JSValue {
    const prefix = try o.text("HTTP request failed. status=");
    const status = try value(o, propertyString, .{response, @as([*:0]const u8, "status")});
    const status_text = try o.binary(0, prefix, status);
    const url_prefix = try o.binary(0, status_text, try o.text("; url="));
    const url_text = try value(o, stringifyValue, .{url});
    const url_part = try o.binary(0, url_prefix, url_text);
    const body_prefix = try o.binary(0, url_part, try o.text("; body="));
    const body_text = try value(o, stringifyValue, .{body});
    return duplicate(o, try o.binary(0, body_prefix, body_text));
}
fn postBody(engine: *x.em.Engine, _: c.JSValue, args: []const c.JSValue, _: []const c.JSValue, state: *c.JSValue, completion: af.Completion, input: c.JSValue) !af.Action {
    if (completion == .rejected) try @import("native_async_body.zig").enterRejectedContinuation(engine);
    return actionExpression(engine, postAdvance, .{args, state, completion, input});
}
fn postAdvance(o: *x.Ops, args: []const c.JSValue, state: *c.JSValue, completion: af.Completion, input: c.JSValue) !af.Action {
    if (completion == .start) {
        const owner = try initialize(o, state);
        try o.put(owner, "response", c.pi_js_undefined());
        try o.put(owner, "responseBody", c.pi_js_undefined());
        try setStage(o, owner, .post_response);
        return .{ .awaited = try expression(o.s.engine, fetchPost, .{x.arg(args, 0), x.arg(args, 1), x.arg(args, 2)}) };
    }
    if (completion == .rejected) return .{ .thrown = duplicate(o, input) };
    switch (try getStage(o, state.*)) {
        .post_response => {
            try o.put(state.*, "response", input);
            try setStage(o, state.*, .post_text);
            return .{ .awaited = try expression(o.s.engine, invokeNoArgs, .{input, @as([*:0]const u8, "text")}) };
        },
        .post_text => {
            try o.put(state.*, "responseBody", input);
            const response = try o.get(state.*, "response");
            if (!try truth(o, propertyTruthy, .{response, @as([*:0]const u8, "ok")}))
                return .{ .thrown = try raise(o, try expression(o.s.engine, newError, .{postErrorText, .{response, x.arg(args, 0), input}})) };
            return .{ .returned = duplicate(o, input) };
        },
        else => unreachable,
    }
}
fn requestBody(o: *x.Ops, module: c.JSValue, args: []const c.JSValue, comptime kind: TokenKind) !c.JSValue {
    const body = try o.object();
    try o.put(body, "grant_type", try o.text(if (kind == .exchange) "authorization_code" else "refresh_token"));
    try o.put(body, "client_id", try o.get(module, "CLIENT_ID"));
    if (kind == .exchange) {
        try o.put(body, "code", x.arg(args, 0));
        try o.put(body, "state", x.arg(args, 1));
        try o.put(body, "redirect_uri", x.arg(args, 3));
        try o.put(body, "code_verifier", x.arg(args, 2));
    } else try o.put(body, "refresh_token", x.arg(args, 0));
    return duplicate(o, body);
}
fn tokenRequest(o: *x.Ops, module: c.JSValue, args: []const c.JSValue, comptime kind: TokenKind) !c.JSValue {
    const callable = try o.get(module, "postJson");
    const url = try o.text(token_url);
    const body = try value(o, requestBody, .{module, args, kind});
    return duplicate(o, try o.call(callable, c.pi_js_undefined(), &.{url, body, x.arg(args, if (kind == .exchange) 4 else 1)}));
}
fn formatReason(o: *x.Ops, module: c.JSValue, reason: c.JSValue) !c.JSValue {
    return duplicate(o, try o.call(try o.get(module, "formatErrorDetails"), c.pi_js_undefined(), &.{reason}));
}
fn requestErrorText(o: *x.Ops, module: c.JSValue, reason: c.JSValue, args: []const c.JSValue, comptime kind: TokenKind) !c.JSValue {
    const prefix = try o.text(if (kind == .exchange) "Token exchange request failed. url=" else "Anthropic token refresh request failed. url=");
    const url_part = try o.binary(0, prefix, try o.text(token_url));
    const detail_prefix = if (kind == .exchange) blk: {
        const redirect_prefix = try o.binary(0, url_part, try o.text("; redirect_uri="));
        const redirect = try value(o, stringifyValue, .{x.arg(args, 3)});
        const redirect_part = try o.binary(0, redirect_prefix, redirect);
        break :blk try o.binary(0, redirect_part, try o.text("; response_type=authorization_code; details="));
    } else try o.binary(0, url_part, try o.text("; details="));
    const detail = try value(o, expressionString, .{formatReason, .{module, reason}});
    return duplicate(o, try o.binary(0, detail_prefix, detail));
}
fn jsonErrorText(o: *x.Ops, module: c.JSValue, reason: c.JSValue, body: c.JSValue, comptime kind: TokenKind) !c.JSValue {
    const prefix = try o.text(if (kind == .exchange) "Token exchange returned invalid JSON. url=" else "Anthropic token refresh returned invalid JSON. url=");
    const url_part = try o.binary(0, prefix, try o.text(token_url));
    const body_prefix = try o.binary(0, url_part, try o.text("; body="));
    const body_text = try value(o, stringifyValue, .{body});
    const body_part = try o.binary(0, body_prefix, body_text);
    const detail_prefix = try o.binary(0, body_part, try o.text("; details="));
    const detail = try value(o, expressionString, .{formatReason, .{module, reason}});
    return duplicate(o, try o.binary(0, detail_prefix, detail));
}
fn parseJson(o: *x.Ops, body: c.JSValue) !c.JSValue {
    const receiver = try o.global("JSON");
    const method = try o.get(receiver, "parse");
    return duplicate(o, try o.call(method, receiver, &.{body}));
}
fn now(o: *x.Ops) !c.JSValue {
    const receiver = try o.global("Date");
    const method = try o.get(receiver, "now");
    return duplicate(o, try o.call(method, receiver, &.{}));
}
fn expiryProduct(o: *x.Ops, data: c.JSValue) !c.JSValue {
    return duplicate(o, try o.binary(2, try o.get(data, "expires_in"), integer(o, 1000)));
}
fn expirySum(o: *x.Ops, data: c.JSValue) !c.JSValue {
    const timestamp = try value(o, now, .{});
    const interval = try value(o, expiryProduct, .{data});
    return duplicate(o, try o.binary(0, timestamp, interval));
}
fn expiry(o: *x.Ops, data: c.JSValue) !c.JSValue {
    return duplicate(o, try o.binary(1, try value(o, expirySum, .{data}), integer(o, 300000)));
}
fn tokenCredential(o: *x.Ops, data: c.JSValue) !c.JSValue {
    const result = try o.object();
    try o.put(result, "type", try o.text("oauth"));
    try o.put(result, "refresh", try o.get(data, "refresh_token"));
    try o.put(result, "access", try o.get(data, "access_token"));
    try o.put(result, "expires", try value(o, expiry, .{data}));
    return duplicate(o, result);
}
fn tokenFailure(o: *x.Ops, module: c.JSValue, owner: c.JSValue, args: []const c.JSValue, reason: c.JSValue, comptime kind: TokenKind, comptime json: bool) !af.Action {
    // Source named catch bindings remain live while formatting and constructing.
    try o.put(owner, if (json) "jsonError" else "requestError", reason);
    const wrapped = if (json)
        try expression(o.s.engine, newError, .{jsonErrorText, .{module, reason, try o.get(owner, "responseBody"), kind}})
    else
        try expression(o.s.engine, newError, .{requestErrorText, .{module, reason, args, kind}});
    return .{ .thrown = try raise(o, wrapped) };
}
fn tokenFailureOwned(engine: *x.em.Engine, module: c.JSValue, owner: c.JSValue, args: []const c.JSValue, reason: c.JSValue, comptime kind: TokenKind, comptime json: bool) !af.Action {
    var completion = x.owned.Completion.initAction(engine, actionExpression(engine, tokenFailure, .{module, owner, args, reason, kind, json}));
    completion.release(reason);
    return completion.finishAction();
}
fn tokenAdvance(o: *x.Ops, module: c.JSValue, args: []const c.JSValue, state: *c.JSValue, completion: af.Completion, input: c.JSValue, comptime kind: TokenKind) !af.Action {
    if (completion == .start) {
        const owner = try initialize(o, state);
        inline for (.{ "responseBody", "requestError", "tokenData", "jsonError" }) |name| try o.put(owner, name, c.pi_js_undefined());
        try setStage(o, owner, .token_response);
        const result = try attempt(o.s.engine, tokenRequest, .{module, args, kind});
        return switch (result) {
            .returned => |promise| .{ .awaited = promise },
            .thrown => |reason| tokenFailureOwned(o.s.engine, module, owner, args, reason, kind, false),
            .awaited => unreachable,
        };
    }
    if (completion == .rejected) return tokenFailureOwned(o.s.engine, module, state.*, args, duplicate(o, input), kind, false);
    try o.put(state.*, "responseBody", input);
    const parsed = try attempt(o.s.engine, parseJson, .{input});
    switch (parsed) {
        .thrown => |reason| return tokenFailureOwned(o.s.engine, module, state.*, args, reason, kind, true),
        .returned => |data| {
            var saved = x.owned.Completion.initVoid(o.s.engine, o.put(state.*, "tokenData", data));
            saved.release(data);
            try saved.finishVoid();
        },
        .awaited => unreachable,
    }
    return .{ .returned = try expression(o.s.engine, tokenCredential, .{try o.get(state.*, "tokenData")}) };
}
fn exchangeBody(engine: *x.em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue, state: *c.JSValue, completion: af.Completion, input: c.JSValue) !af.Action {
    if (completion == .rejected) try @import("native_async_body.zig").enterRejectedContinuation(engine);
    return actionExpression(engine, tokenAdvance, .{roots[0], args, state, completion, input, TokenKind.exchange});
}
fn refreshBody(engine: *x.em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue, state: *c.JSValue, completion: af.Completion, input: c.JSValue) !af.Action {
    if (completion == .rejected) try @import("native_async_body.zig").enterRejectedContinuation(engine);
    return actionExpression(engine, tokenAdvance, .{roots[0], args, state, completion, input, TokenKind.refresh});
}

fn invokePkce(o: *x.Ops, module: c.JSValue) !c.JSValue {
    const callable = try o.get(module, "generatePKCE");
    return duplicate(o, try o.call(callable, c.pi_js_undefined(), &.{}));
}
fn bindPkce(o: *x.Ops, owner: c.JSValue, input: c.JSValue) !void {
    const receiver = try x.guest.toObject(o.s, input);
    try o.put(owner, "verifier", try o.get(receiver, "verifier"));
    try o.put(owner, "challenge", try o.get(receiver, "challenge"));
}
fn authorizationFields(o: *x.Ops, module: c.JSValue, verifier: c.JSValue, challenge: c.JSValue, redirect: c.JSValue) !c.JSValue {
    const fields = try o.object();
    try o.put(fields, "code", try o.text("true"));
    try o.put(fields, "client_id", try o.get(module, "CLIENT_ID"));
    try o.put(fields, "response_type", try o.text("code"));
    try o.put(fields, "redirect_uri", redirect);
    try o.put(fields, "scope", try o.text(scopes));
    try o.put(fields, "code_challenge", challenge);
    try o.put(fields, "code_challenge_method", try o.text("S256"));
    try o.put(fields, "state", verifier);
    return duplicate(o, fields);
}
fn authorizationParams(o: *x.Ops, module: c.JSValue, verifier: c.JSValue, challenge: c.JSValue, redirect: c.JSValue) !c.JSValue {
    const constructor = try o.global("URLSearchParams");
    const fields = try value(o, authorizationFields, .{module, verifier, challenge, redirect});
    return duplicate(o, try x.guest.construct(o.s, constructor, &.{fields}));
}
fn authorizationUrl(o: *x.Ops, params: c.JSValue) !c.JSValue {
    const prefix = try o.binary(0, try o.text(authorize_url), try o.text("?"));
    const encoded = try value(o, expressionString, .{invokeNoArgs, .{params, @as([*:0]const u8, "toString")}});
    return duplicate(o, try o.binary(0, prefix, encoded));
}
fn authorizationNotice(o: *x.Ops, params: c.JSValue, comptime browser: bool) !c.JSValue {
    const event = try o.object();
    try o.put(event, "type", try o.text("auth_url"));
    try o.put(event, "url", try value(o, authorizationUrl, .{params}));
    try o.put(event, "instructions", try o.text(if (browser)
        "Complete login in your browser. If the browser is on another machine, paste the final redirect URL here."
    else "Complete login in your browser, then copy the code Anthropic shows and paste it here."));
    return duplicate(o, event);
}
fn exchangeNotice(o: *x.Ops) !c.JSValue {
    const event = try o.object();
    try o.put(event, "type", try o.text("progress"));
    try o.put(event, "message", try o.text("Exchanging authorization code for tokens..."));
    return duplicate(o, event);
}
fn notify(o: *x.Ops, interaction: c.JSValue, comptime notice: anytype, args: anytype) !void {
    const callable = try o.get(interaction, "notify");
    const event = try value(o, notice, args);
    _ = try o.call(callable, interaction, &.{event});
}
fn manualPrompt(o: *x.Ops, interaction: c.JSValue) !c.JSValue {
    const options = try o.object();
    try o.put(options, "type", try o.text("manual_code"));
    try o.put(options, "message", try o.text("Paste the code Anthropic shows after you sign in:"));
    try o.put(options, "placeholder", try o.text("code#state"));
    try o.put(options, "signal", try o.get(interaction, "signal"));
    return duplicate(o, options);
}
fn promptCopyInput(o: *x.Ops, interaction: c.JSValue) !c.JSValue {
    const method = try o.get(interaction, "prompt");
    const options = try value(o, manualPrompt, .{interaction});
    return duplicate(o, try o.call(method, interaction, &.{options}));
}
fn parseInput(o: *x.Ops, module: c.JSValue, input: c.JSValue) !c.JSValue {
    const callable = try o.get(module, "parseAuthorizationInput");
    return duplicate(o, try o.call(callable, c.pi_js_undefined(), &.{input}));
}
fn parseResultInput(o: *x.Ops, module: c.JSValue, result: c.JSValue) !c.JSValue {
    const callable = try o.get(module, "parseAuthorizationInput");
    return duplicate(o, try o.call(callable, c.pi_js_undefined(), &.{try o.get(result, "input")}));
}
fn stateMismatch(o: *x.Ops, parsed: c.JSValue, verifier: c.JSValue) !c.JSValue {
    if (!try truth(o, propertyTruthy, .{parsed, @as([*:0]const u8, "state")})) return boolean(o, false);
    return boolean(o, !c.JS_IsStrictEqual(o.s.engine.context, try o.get(parsed, "state"), verifier));
}
fn parsedState(o: *x.Ops, parsed: c.JSValue, verifier: c.JSValue) !c.JSValue {
    const state = try o.get(parsed, "state");
    return duplicate(o, if (x.nullish(state)) verifier else state);
}
fn copyExchange(o: *x.Ops, module: c.JSValue, parsed: c.JSValue, verifier: c.JSValue, interaction: c.JSValue) !c.JSValue {
    const callable = try o.get(module, "exchangeAuthorizationCode");
    const code = try o.get(parsed, "code");
    const state = try value(o, parsedState, .{parsed, verifier});
    const redirect = try o.text(copy_redirect_uri);
    return duplicate(o, try o.call(callable, c.pi_js_undefined(), &.{code, state, verifier, redirect, try o.get(interaction, "signal")}));
}
fn copyBody(engine: *x.em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue, state: *c.JSValue, completion: af.Completion, input: c.JSValue) !af.Action {
    if (completion == .rejected) try @import("native_async_body.zig").enterRejectedContinuation(engine);
    return actionExpression(engine, copyAdvance, .{roots[0], x.arg(args, 0), state, completion, input});
}
fn copyAdvance(o: *x.Ops, module: c.JSValue, interaction: c.JSValue, state: *c.JSValue, completion: af.Completion, input: c.JSValue) !af.Action {
    if (completion == .start) {
        const owner = try initialize(o, state);
        inline for (.{ "verifier", "challenge", "authParams", "input", "parsed" }) |name| try o.put(owner, name, c.pi_js_undefined());
        try setStage(o, owner, .copy_pkce);
        return .{ .awaited = try expression(o.s.engine, invokePkce, .{module}) };
    }
    if (completion == .rejected) return .{ .thrown = duplicate(o, input) };
    switch (try getStage(o, state.*)) {
        .copy_pkce => {
            try statement(o.s.engine, bindPkce, .{state.*, input});
            const params = try value(o, authorizationParams, .{module, try o.get(state.*, "verifier"), try o.get(state.*, "challenge"), try o.text(copy_redirect_uri)});
            try o.put(state.*, "authParams", params);
            try statement(o.s.engine, notify, .{interaction, authorizationNotice, .{params, false}});
            try setStage(o, state.*, .copy_input);
            return .{ .awaited = try expression(o.s.engine, promptCopyInput, .{interaction}) };
        },
        .copy_input => {
            try o.put(state.*, "input", input);
            const parsed = try value(o, parseInput, .{module, input});
            try o.put(state.*, "parsed", parsed);
            const verifier = try o.get(state.*, "verifier");
            if (try truth(o, stateMismatch, .{parsed, verifier}))
                return .{ .thrown = try raise(o, try expression(o.s.engine, newError, .{text, .{@as([]const u8, "OAuth state mismatch")}})) };
            if (!try truth(o, propertyTruthy, .{parsed, @as([*:0]const u8, "code")}))
                return .{ .thrown = try raise(o, try expression(o.s.engine, newError, .{text, .{@as([]const u8, "Missing authorization code")}})) };
            try statement(o.s.engine, notify, .{interaction, exchangeNotice, .{}});
            try setStage(o, state.*, .copy_exchange);
            return .{ .awaited = try expression(o.s.engine, copyExchange, .{module, parsed, verifier, interaction}) };
        },
        .copy_exchange => return .{ .returned = duplicate(o, input) },
        else => unreachable,
    }
}

fn callbackCompleteBody(engine: *x.em.Engine, _: c.JSValue, args: []const c.JSValue, _: []const c.JSValue, _: *c.JSValue, completion: af.Completion, _: c.JSValue) !af.Action {
    if (completion != .start) unreachable;
    return .{ .returned = c.JS_DupValue(engine.context, x.arg(args, 0)) };
}
fn callbackOptions(o: *x.Ops, module: c.JSValue, interaction: c.JSValue, verifier: c.JSValue, port: c.JSValue) !c.JSValue {
    const options = try o.object();
    try o.put(options, "providerName", try o.text("Anthropic"));
    try o.put(options, "host", try o.get(module, "CALLBACK_HOST"));
    try o.put(options, "port", port);
    try o.put(options, "path", try o.text("/callback"));
    try o.put(options, "redirectHost", try o.text("localhost"));
    try o.put(options, "state", verifier);
    try o.put(options, "complete", try o.own(try af.createResumableArrow(o.s.engine, "complete", 1, callbackCompleteBody, &.{}, c.pi_js_undefined())));
    try o.put(options, "signal", try o.get(interaction, "signal"));
    return duplicate(o, options);
}
fn startCallback(o: *x.Ops, module: c.JSValue, interaction: c.JSValue, verifier: c.JSValue, port: c.JSValue) !c.JSValue {
    const callable = try o.get(module, "startOAuthCallbackServer");
    const options = try value(o, callbackOptions, .{module, interaction, verifier, port});
    return duplicate(o, try o.call(callable, c.pi_js_undefined(), &.{options}));
}
fn browserRead(o: *x.Ops, owner: c.JSValue, comptime name: BrowserLocal) !c.JSValue {
    return o.own(c.JS_DupValue(o.s.engine.context, BrowserFrame.from(owner).get(name)));
}
fn startCallbackCall(engine: *x.em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    return expression(engine, startCapturedCallback, .{roots[0], roots[1], roots[2], x.arg(args, 0)});
}
fn startCapturedCallback(o: *x.Ops, module: c.JSValue, interaction_cell: c.JSValue, verifier_cell: c.JSValue, port: c.JSValue) !c.JSValue {
    const interaction = try BrowserFrame.read(o.s, interaction_cell);
    const verifier = try BrowserFrame.read(o.s, verifier_cell);
    return startCallback(o, module, interaction, verifier, port);
}
fn callPreferredPort(o: *x.Ops, start: c.JSValue) !c.JSValue {
    return duplicate(o, try o.call(start, c.pi_js_undefined(), &.{integer(o, 53692)}));
}
fn retryPortCall(engine: *x.em.Engine, _: c.JSValue, _: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    return expression(engine, callCapturedFreePort, .{roots[0]});
}
fn callCapturedFreePort(o: *x.Ops, binding: c.JSValue) !c.JSValue {
    const start = try BrowserFrame.read(o.s, binding);
    return duplicate(o, try o.call(start, c.pi_js_undefined(), &.{integer(o, 0)}));
}
fn undefinedCall(_: *x.em.Engine, _: c.JSValue, _: []const c.JSValue, _: []const c.JSValue) !c.JSValue { return c.pi_js_undefined(); }
fn firstCallbackCatch(o: *x.Ops, owner: c.JSValue) !c.JSValue {
    const promise = try value(o, callPreferredPort, .{BrowserFrame.from(owner).get(.startCallbackServer)});
    const method = try o.get(promise, "catch");
    const binding = try BrowserFrame.from(owner).capture(o.s, .startCallbackServer, "startCallbackServer");
    const fallback = try o.own(try functions.createArrow(o.s.engine, "", 0, retryPortCall, &.{binding}));
    return duplicate(o, try o.call(method, promise, &.{fallback}));
}
fn callbackWithFallback(o: *x.Ops, owner: c.JSValue) !c.JSValue {
    const promise = try value(o, firstCallbackCatch, .{owner});
    const method = try o.get(promise, "catch");
    const fallback = try o.own(try functions.createArrow(o.s.engine, "", 0, undefinedCall, &.{}));
    return duplicate(o, try o.call(method, promise, &.{fallback}));
}
fn callbackRedirect(o: *x.Ops, module: c.JSValue, callback: c.JSValue) !c.JSValue {
    const selected = if (x.nullish(callback)) c.pi_js_undefined() else try o.get(callback, "redirectUri");
    return duplicate(o, if (x.nullish(selected)) try o.get(module, "REDIRECT_URI") else selected);
}
fn browserPrompt(o: *x.Ops, redirect: c.JSValue) !c.JSValue {
    const prompt = try o.object();
    try o.put(prompt, "message", try o.text("Complete login in your browser, or paste the authorization code / redirect URL here:"));
    try o.put(prompt, "placeholder", redirect);
    return duplicate(o, prompt);
}
fn waitForInput(o: *x.Ops, module: c.JSValue, interaction: c.JSValue, callback: c.JSValue, redirect: c.JSValue) !c.JSValue {
    const callable = try o.get(module, "waitForCallbackOrManualInput");
    const prompt = try value(o, browserPrompt, .{redirect});
    return duplicate(o, try o.call(callable, c.pi_js_undefined(), &.{interaction, callback, prompt}));
}
fn closeCallback(o: *x.Ops, callback: c.JSValue) !void {
    if (!x.nullish(callback)) _ = try o.invoke(callback, "close", &.{});
}
fn browserExchange(o: *x.Ops, module: c.JSValue, owner: c.JSValue, interaction: c.JSValue) !c.JSValue {
    const callable = try o.get(module, "exchangeAuthorizationCode");
    const code = try browserRead(o, owner, .code);
    const state = try browserRead(o, owner, .state);
    const verifier = try browserRead(o, owner, .verifier);
    const redirect = try browserRead(o, owner, .redirectUri);
    return duplicate(o, try o.call(callable, c.pi_js_undefined(), &.{code, state, verifier, redirect, try o.get(interaction, "signal")}));
}
fn browserTry(o: *x.Ops, module: c.JSValue, interaction: c.JSValue, owner: c.JSValue, stage: Stage, completion: af.Completion, input: c.JSValue) !af.Action {
    if (completion == .rejected) return .{ .thrown = duplicate(o, input) };
    const frame = BrowserFrame.from(owner);
    switch (stage) {
        .browser_callback => {
            const params = try value(o, authorizationParams, .{module, try browserRead(o, owner, .verifier), try browserRead(o, owner, .challenge), try browserRead(o, owner, .redirectUri)});
            try frame.copy(.authParams, params);
            try statement(o.s.engine, notify, .{interaction, authorizationNotice, .{params, true}});
            try setStage(o, owner, .browser_input);
            return .{ .awaited = try expression(o.s.engine, waitForInput, .{module, interaction, try browserRead(o, owner, .callback), try browserRead(o, owner, .redirectUri)}) };
        },
        .browser_input => {
            try frame.copy(.result, input);
            const verifier = try browserRead(o, owner, .verifier);
            try frame.copy(.code, c.pi_js_undefined());
            try frame.copy(.state, verifier);
            if (try truth(o, propertyEqualsText, .{input, @as([*:0]const u8, "type"), @as([]const u8, "callback")})) {
                try frame.copy(.code, try o.get(input, "value"));
            } else {
                const parsed = try value(o, parseResultInput, .{module, input});
                try frame.copy(.parsed, parsed);
                if (try truth(o, stateMismatch, .{parsed, verifier}))
                    return .{ .thrown = try raise(o, try expression(o.s.engine, newError, .{text, .{@as([]const u8, "OAuth state mismatch")}})) };
                try frame.copy(.code, try o.get(parsed, "code"));
                try frame.copy(.state, try value(o, parsedState, .{parsed, verifier}));
            }
            if (!o.truthy(frame.get(.code)))
                return .{ .thrown = try raise(o, try expression(o.s.engine, newError, .{text, .{@as([]const u8, "Missing authorization code")}})) };
            try statement(o.s.engine, notify, .{interaction, exchangeNotice, .{}});
            try setStage(o, owner, .browser_exchange);
            return .{ .awaited = try expression(o.s.engine, browserExchange, .{module, owner, interaction}) };
        },
        .browser_exchange => return .{ .returned = duplicate(o, input) },
        else => unreachable,
    }
}
fn browserBody(engine: *x.em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue, state: *c.JSValue, completion: af.Completion, input: c.JSValue) !af.Action {
    if (completion == .rejected) try @import("native_async_body.zig").enterRejectedContinuation(engine);
    return actionExpression(engine, browserAdvance, .{roots[0], x.arg(args, 0), state, completion, input});
}
fn browserBindPkce(o: *x.Ops, owner: c.JSValue, input: c.JSValue) !void {
    const receiver = try x.guest.toObject(o.s, input);
    const frame = BrowserFrame.from(owner);
    try frame.copy(.verifier, try o.get(receiver, "verifier"));
    try frame.copy(.challenge, try o.get(receiver, "challenge"));
}
fn browserAdvance(o: *x.Ops, module: c.JSValue, interaction: c.JSValue, state: *c.JSValue, completion: af.Completion, input: c.JSValue) !af.Action {
    if (completion == .start) {
        const frame = try BrowserFrame.createAsync(o.s);
        af.replaceState(o.s.engine, state, duplicate(o, frame.owner));
        try setStage(o, frame.owner, .browser_pkce);
        return .{ .awaited = try expression(o.s.engine, invokePkce, .{module}) };
    }
    const frame = BrowserFrame.from(state.*);
    const stage = try getStage(o, state.*);
    if (stage == .browser_pkce) {
        if (completion == .rejected) return .{ .thrown = duplicate(o, input) };
        try statement(o.s.engine, browserBindPkce, .{state.*, input});
        const interaction_cell = try frame.captureImmutableArgument(o.s, .interactionCapture, "interaction", interaction);
        const verifier_cell = try frame.capture(o.s, .verifier, "verifier");
        const start = try o.own(try functions.createArrow(o.s.engine, "startCallbackServer", 1, startCallbackCall, &.{module, interaction_cell, verifier_cell}));
        try frame.copy(.startCallbackServer, start);
        try setStage(o, state.*, .browser_callback);
        return .{ .awaited = try expression(o.s.engine, callbackWithFallback, .{state.*}) };
    }
    if (stage == .browser_callback) {
        if (completion == .rejected) return .{ .thrown = duplicate(o, input) };
        try frame.copy(.callback, input);
        try frame.copy(.redirectUri, try value(o, callbackRedirect, .{module, input}));
        // The Source try starts after the optional redirect getter completes.
    }
    const outcome = try actionExpression(o.s.engine, browserTry, .{module, interaction, state.*, stage, completion, input});
    return switch (outcome) {
        .awaited => outcome,
        .returned, .thrown => finallyOwned(o.s.engine, outcome, closeCallback, .{try browserRead(o, state.*, .callback)}),
    };
}
fn loginOptions(o: *x.Ops) !c.JSValue {
    const options = try o.object();
    try o.put(options, "type", try o.text("select"));
    try o.put(options, "message", try o.text("Select Anthropic login method:"));
    const entries = try array(o);
    const browser = try o.object();
    try o.put(browser, "id", try o.text("browser"));
    try o.put(browser, "label", try o.text("Browser login (default)"));
    try x.guest.index(o.s, entries, 0, browser);
    const copy = try o.object();
    try o.put(copy, "id", try o.text("copy_code"));
    try o.put(copy, "label", try o.text("Copy code login (headless)"));
    try x.guest.index(o.s, entries, 1, copy);
    try o.put(options, "options", entries);
    return duplicate(o, options);
}
fn promptMethod(o: *x.Ops, interaction: c.JSValue) !c.JSValue {
    const callable = try o.get(interaction, "prompt");
    const options = try value(o, loginOptions, .{});
    return duplicate(o, try o.call(callable, interaction, &.{options}));
}
fn invokeLogin(o: *x.Ops, module: c.JSValue, interaction: c.JSValue, comptime copy: bool) !c.JSValue {
    const callable = try o.get(module, if (copy) "loginAnthropicCopyCode" else "loginAnthropic");
    return duplicate(o, try o.call(callable, c.pi_js_undefined(), &.{interaction}));
}
fn unknownMethod(o: *x.Ops, method: c.JSValue) !c.JSValue {
    const prefix = try o.text("Unknown Anthropic login method: ");
    const description = try value(o, stringifyValue, .{method});
    return duplicate(o, try o.binary(0, prefix, description));
}
fn loginBody(engine: *x.em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue, state: *c.JSValue, completion: af.Completion, input: c.JSValue) !af.Action {
    if (completion == .rejected) try @import("native_async_body.zig").enterRejectedContinuation(engine);
    return actionExpression(engine, loginAdvance, .{roots[0], x.arg(args, 0), state, completion, input});
}
fn loginAdvance(o: *x.Ops, module: c.JSValue, interaction: c.JSValue, state: *c.JSValue, completion: af.Completion, input: c.JSValue) !af.Action {
    if (completion == .start) {
        const owner = try initialize(o, state);
        try o.put(owner, "method", c.pi_js_undefined());
        try setStage(o, owner, .login_method);
        return .{ .awaited = try expression(o.s.engine, promptMethod, .{interaction}) };
    }
    if (completion == .rejected) return .{ .thrown = duplicate(o, input) };
    try o.put(state.*, "method", input);
    if (try equalText(o, input, "copy_code")) return .{ .returned = try expression(o.s.engine, invokeLogin, .{module, interaction, true}) };
    if (!try equalText(o, input, "browser")) return .{ .thrown = try raise(o, try expression(o.s.engine, newError, .{unknownMethod, .{input}})) };
    return .{ .returned = try expression(o.s.engine, invokeLogin, .{module, interaction, false}) };
}

const module_cache_key = "pi-native:oauth-anthropic-genuine";
fn decodeCall(engine: *x.em.Engine, _: c.JSValue, args: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
    return expression(engine, decodeBody, .{x.arg(args, 0)});
}
fn decodeBody(o: *x.Ops, input: c.JSValue) !c.JSValue {
    return duplicate(o, try o.call(try o.global("atob"), c.pi_js_undefined(), &.{input}));
}
fn clientId(o: *x.Ops, module: c.JSValue) !c.JSValue {
    const decode = try o.get(module, "decode");
    return duplicate(o, try o.call(decode, c.pi_js_undefined(), &.{try o.text("OWQxYzI1MGEtZTYxYi00NGQ5LTg4ZWQtNTk0NGQxOTYyZjVl")}));
}
fn callbackHost(o: *x.Ops, module: c.JSValue) !c.JSValue {
    const callable = try o.get(module, "getProviderEnvValue");
    const value_result = try o.call(callable, c.pi_js_undefined(), &.{try o.text("PI_OAUTH_CALLBACK_HOST")});
    return duplicate(o, if (o.truthy(value_result)) value_result else try o.text("127.0.0.1"));
}
fn refreshCall(engine: *x.em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    return expression(engine, refreshCredential, .{roots[0], x.arg(args, 0), x.arg(args, 1)});
}
fn refreshCredential(o: *x.Ops, module: c.JSValue, credential: c.JSValue, signal: c.JSValue) !c.JSValue {
    const callable = try o.get(module, "refreshAnthropicToken");
    return duplicate(o, try o.call(callable, c.pi_js_undefined(), &.{try o.get(credential, "refresh"), signal}));
}
fn toAuthCall(engine: *x.em.Engine, _: c.JSValue, args: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
    return expression(engine, toAuth, .{x.arg(args, 0)});
}
fn toAuth(o: *x.Ops, credential: c.JSValue) !c.JSValue {
    const result = try o.object();
    try o.put(result, "apiKey", try o.get(credential, "access"));
    return duplicate(o, result);
}
fn moduleRedirectUri(o: *x.Ops) !c.JSValue {
    const prefix = try o.text("http://localhost:");
    const port = try value(o, stringifyValue, .{integer(o, 53692)});
    const host = try o.binary(0, prefix, port);
    return duplicate(o, try o.binary(0, host, try o.text("/callback")));
}
const ModuleImports = struct {
    start_callback: c.JSValue,
    wait_for_input: c.JSValue,
    generate_pkce: c.JSValue,
    provider_env: c.JSValue,
};
fn createModuleBody(o: *x.Ops) !c.JSValue {
    const callback = try o.own(try callback_server.create(o.s.engine));
    const start_callback = try o.get(callback, "startOAuthCallbackServer");
    const wait_for_input = try o.get(callback, "waitForCallbackOrManualInput");
    const pkce = try o.own(try @import("native_ai_oauth_pkce.zig").create(o.s.engine));
    const generate_pkce = try o.get(pkce, "generatePKCE");
    const provider_env = try o.own(try @import("native_provider_env.zig").create(o.s.engine));
    return createModuleFromImports(o, .{
        .start_callback = start_callback,
        .wait_for_input = wait_for_input,
        .generate_pkce = generate_pkce,
        .provider_env = provider_env,
    });
}
fn createModuleFromImports(o: *x.Ops, imports: ModuleImports) !c.JSValue {
    const module = try o.cell();
    try o.put(module, "startOAuthCallbackServer", imports.start_callback);
    try o.put(module, "waitForCallbackOrManualInput", imports.wait_for_input);
    try o.put(module, "generatePKCE", imports.generate_pkce);
    try o.put(module, "getProviderEnvValue", imports.provider_env);
    try o.put(module, "decode", try o.own(try functions.createArrow(o.s.engine, "decode", 1, decodeCall, &.{})));
    try o.put(module, "CLIENT_ID", try value(o, clientId, .{module}));
    try o.put(module, "CALLBACK_HOST", try value(o, callbackHost, .{module}));
    try o.put(module, "REDIRECT_URI", try value(o, moduleRedirectUri, .{}));
    try o.put(module, "parseAuthorizationInput", try o.own(try functions.create(o.s.engine, "parseAuthorizationInput", 1, parseInputCall, &.{})));
    try o.put(module, "formatErrorDetails", try o.own(try functions.create(o.s.engine, "formatErrorDetails", 1, errorDetailsCall, &.{module})));
    try o.put(module, "postJson", try declaration(o, module, "postJson", 3, postBody));
    try o.put(module, "exchangeAuthorizationCode", try declaration(o, module, "exchangeAuthorizationCode", 5, exchangeBody));
    try o.put(module, "loginAnthropic", try o.own(try af.createResumableWithClose(o.s.engine, "loginAnthropic", 1, browserBody, &.{module}, BrowserFrame.closeAtAsyncTerminal)));
    try o.put(module, "loginAnthropicCopyCode", try declaration(o, module, "loginAnthropicCopyCode", 1, copyBody));
    try o.put(module, "refreshAnthropicToken", try declaration(o, module, "refreshAnthropicToken", 2, refreshBody));
    const result = try o.object();
    try o.put(result, "name", try o.text("Anthropic (Claude Pro/Max)"));
    try o.put(result, "isSubscription", boolean(o, true));
    try o.put(result, "login", try declaration(o, module, "login", 1, loginBody));
    try o.put(result, "refresh", try o.own(try functions.createArrow(o.s.engine, "refresh", 2, refreshCall, &.{module})));
    try o.put(result, "toAuth", try o.own(try af.create(o.s.engine, "toAuth", 1, toAuthCall, &.{})));
    try o.put(module, "anthropicOAuth", result);
    return duplicate(o, module);
}
fn moduleValue(engine: *x.em.Engine) !c.JSValue {
    try engine.checkNativeEntry();
    if (engine.native_module_values.get(module_cache_key)) |cached| return c.JS_DupValue(engine.context, cached);
    const candidate = try expression(engine, createModuleBody, .{});
    if (engine.native_module_values.get(module_cache_key)) |cached| {
        var selected = x.owned.Completion.initValue(engine, c.JS_DupValue(engine.context, cached));
        selected.release(candidate);
        return selected.finishValue();
    }
    engine.native_module_values.ensureUnusedCapacity(engine.gpa, 1) catch |err| {
        var failed = x.owned.Completion.initValue(engine, @as(anyerror!c.JSValue, err));
        failed.release(candidate);
        return failed.finishValue();
    };
    engine.native_module_values.putAssumeCapacity(module_cache_key, candidate);
    return c.JS_DupValue(engine.context, candidate);
}
fn providerValue(o: *x.Ops) !c.JSValue {
    const module = try o.own(try moduleValue(o.s.engine));
    return duplicate(o, try o.get(module, "anthropicOAuth"));
}
pub fn create(engine: *x.em.Engine) !c.JSValue {
    try engine.checkNativeEntry();
    var invocation: x.em.Engine.NativeInvocation = .{};
    engine.enterNativeInvocation(&invocation);
    return x.finishInvocation(engine, &invocation, expression(engine, providerValue, .{}));
}
/// Test projection of actual private functions from the same completed module.
/// No production import or callback/HTTP owner is replaced by this projection.
pub fn createTestInternals(engine: *x.em.Engine) !c.JSValue {
    if (!@import("builtin").is_test) @compileError("Anthropic private projection is only available to native controls");
    try engine.checkNativeEntry();
    var invocation: x.em.Engine.NativeInvocation = .{};
    engine.enterNativeInvocation(&invocation);
    return x.finishInvocation(engine, &invocation, expression(engine, privateValues, .{}));
}
fn privateValues(o: *x.Ops) !c.JSValue {
    const module = try o.own(try moduleValue(o.s.engine));
    return projectPrivateValues(o, module);
}
fn projectPrivateValues(o: *x.Ops, module: c.JSValue) !c.JSValue {
    const result = try o.object();
    inline for (.{ "parseAuthorizationInput", "formatErrorDetails", "postJson", "exchangeAuthorizationCode", "loginAnthropic", "loginAnthropicCopyCode", "refreshAnthropicToken", "anthropicOAuth" }) |name|
        try o.put(result, name, try o.get(module, name));
    return duplicate(o, result);
}

/// Controlled lexical imports for genuine Source/native body comparisons only.
/// This does not publish or change the cached production provider or its owners.
pub fn createTestWithImports(engine: *x.em.Engine, imports: c.JSValue) !c.JSValue {
    if (!@import("builtin").is_test) @compileError("Controlled Anthropic imports are only available to native controls");
    try engine.checkNativeEntry();
    var invocation: x.em.Engine.NativeInvocation = .{};
    engine.enterNativeInvocation(&invocation);
    return x.finishInvocation(engine, &invocation, expression(engine, testImportsBody, .{imports}));
}
fn testImportsBody(o: *x.Ops, imports: c.JSValue) !c.JSValue {
    const module = try o.own(try createModuleFromImports(o, .{
        .start_callback = try o.get(imports, "startOAuthCallbackServer"),
        .wait_for_input = try o.get(imports, "waitForCallbackOrManualInput"),
        .generate_pkce = try o.get(imports, "generatePKCE"),
        .provider_env = try o.get(imports, "getProviderEnvValue"),
    }));
    return projectPrivateValues(o, module);
}
