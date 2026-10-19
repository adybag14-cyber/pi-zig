//! Source c268 Radius browser/device login and exported factory.
//! HTTP declarations are shared lexical functions from the genuine module.
const x = @import("native_ai_auth_helper_values.zig");
const c = x.c;
const af = x.af;
const sync = @import("native_sync_arguments.zig");
const functions = @import("native_node_function.zig");
const frames = @import("native_public_lexical_frame.zig");
const p = @import("native_public_values.zig");
const http = @import("native_ai_oauth_radius_http_genuine.zig");
const redirect_uri = "http://127.0.0.1:1456/oauth/callback";
const Browser = frames.Frame(enum { verifier, challenge, stateValue, authorizeUrl, callback, credential, gatewayCapture, interactionCapture, phase });
const Device = frames.Frame(enum { device, gatewayCapture, interactionCapture });
const Poll = frames.Frame(enum { credentials, errorValue });
const Factory = frames.Frame(enum { gateway });
const Login = frames.Frame(enum { loginMethod, discovery, phase });
const Refresh = frames.Frame(enum { refreshed });
const Phase = enum(i32) { pkce, callback, wait, method, discovery };

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
fn value(o: *x.Ops, comptime body: anytype, args: anytype) !c.JSValue { return o.own(try expression(o.s.engine, body, args)); }
fn dup(o: *x.Ops, incoming: c.JSValue) c.JSValue { return c.JS_DupValue(o.s.engine.context, incoming); }
fn property(o: *x.Ops, target: c.JSValue, name: [*:0]const u8) !c.JSValue { return dup(o, try o.get(target, name)); }
fn callMethod(o: *x.Ops, receiver: c.JSValue, name: [*:0]const u8) !c.JSValue { return dup(o, try o.invoke(receiver, name, &.{})); }
fn directCall(o: *x.Ops, callable: c.JSValue, args: []const c.JSValue) !c.JSValue { return dup(o, try o.call(callable, c.pi_js_undefined(), args)); }
fn construct(o: *x.Ops, constructor: c.JSValue, args: []const c.JSValue) !c.JSValue { return dup(o, try x.guest.construct(o.s, constructor, args)); }
fn newError(o: *x.Ops, message: []const u8) !c.JSValue {
    const constructor = try o.global("Error");
    return construct(o, constructor, &.{try o.text(message)});
}
fn raise(o: *x.Ops, reason: c.JSValue) !c.JSValue {
    // Source explicit throw, including catch rethrow, crosses the actual VM seam.
    return o.s.engine.checked(c.JS_Throw(o.s.engine.context, dup(o, reason)));
}
fn phaseSet(frame: anytype, phase: Phase) !void { return frame.take(.phase, c.JS_NewInt32(frame.engine.context, @intFromEnum(phase))); }
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
fn uuid(o: *x.Ops) !c.JSValue {
    const crypto = try o.global("crypto");
    return dup(o, try o.invoke(crypto, "randomUUID", &.{}));
}
fn authorizationUrl(o: *x.Ops, endpoint: c.JSValue) !c.JSValue {
    const constructor = try o.global("URL");
    return construct(o, constructor, &.{endpoint});
}
fn authorizationParams(o: *x.Ops, frame: *Browser) !c.JSValue {
    const constructor = try o.global("URLSearchParams");
    const fields = try o.object();
    try o.put(fields, "response_type", try o.text("code"));
    try o.put(fields, "client_id", try o.text("pi-gateway"));
    try o.put(fields, "redirect_uri", try o.text(redirect_uri));
    try o.put(fields, "scope", try o.text("gateway offline_access"));
    try o.put(fields, "code_challenge", frame.get(.challenge));
    try o.put(fields, "code_challenge_method", try o.text("S256"));
    try o.put(fields, "handoff", try o.text("url"));
    try o.put(fields, "state", frame.get(.stateValue));
    return construct(o, constructor, &.{fields});
}
fn authorizationSearch(o: *x.Ops, frame: *Browser) !c.JSValue {
    const params = try value(o, authorizationParams, .{frame});
    return dup(o, try o.invoke(params, "toString", &.{}));
}
fn setSearch(o: *x.Ops, frame: *Browser) !void {
    const receiver = frame.get(.authorizeUrl);
    const search = try value(o, authorizationSearch, .{frame});
    try x.guest.set(o.s, receiver, "search", search);
}
fn completeForm(o: *x.Ops, code: c.JSValue, verifier: c.JSValue) !c.JSValue {
    const constructor = try o.global("URLSearchParams");
    const fields = try o.object();
    try o.put(fields, "grant_type", try o.text("authorization_code"));
    try o.put(fields, "client_id", try o.text("pi-gateway"));
    try o.put(fields, "redirect_uri", try o.text(redirect_uri));
    try o.put(fields, "code", code);
    try o.put(fields, "code_verifier", try Browser.read(o.s, verifier));
    return construct(o, constructor, &.{fields});
}
fn complete(o: *x.Ops, args: *sync.Arguments, roots: []const c.JSValue) !c.JSValue {
    // Exact ordinary arrow returning requestOAuthToken's genuine Promise.
    const callable = roots[3];
    const gateway = try Browser.read(o.s, roots[0]);
    const form = try value(o, completeForm, .{args.get(0), roots[1]});
    const interaction = try Browser.read(o.s, roots[2]);
    const signal = try o.get(interaction, "signal");
    return dup(o, try o.call(callable, c.pi_js_undefined(), &.{gateway, form, signal}));
}
fn completeCall(engine: *x.em.Engine, _: c.JSValue, args: *sync.Arguments, roots: []const c.JSValue) !c.JSValue {
    return expression(engine, complete, .{args, roots});
}
fn callbackOptions(o: *x.Ops, frame: *Browser, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    const input = try o.object();
    try o.put(input, "providerName", try o.text("Radius"));
    try o.put(input, "host", try o.text("127.0.0.1"));
    try o.put(input, "port", c.JS_NewInt32(o.s.engine.context, 1456));
    try o.put(input, "path", try o.text("/oauth/callback"));
    try o.put(input, "state", frame.get(.stateValue));
    const gateway = try frame.captureImmutableArgument(o.s, .gatewayCapture, "gateway", x.arg(args, 0));
    const verifier = try frame.capture(o.s, .verifier, "verifier");
    const interaction = try frame.captureImmutableArgument(o.s, .interactionCapture, "interaction", x.arg(args, 2));
    const callback = try o.own(try functions.createArrowWithArguments(o.s.engine, "complete", 1,
        .{ .formal_count = 1, .callback = completeCall }, &.{gateway, verifier, interaction, roots[2]}));
    try o.put(input, "complete", callback);
    try o.put(input, "signal", try o.get(x.arg(args, 2), "signal"));
    return dup(o, input);
}
fn startCallback(o: *x.Ops, frame: *Browser, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    const callable = roots[1];
    const input = try value(o, callbackOptions, .{frame, args, roots});
    return dup(o, try o.call(callable, c.pi_js_undefined(), &.{input}));
}
fn progressInput(o: *x.Ops) !c.JSValue {
    const input = try o.object();
    try o.put(input, "type", try o.text("progress"));
    try o.put(input, "message", try o.text("Listening for OAuth callback on " ++ redirect_uri));
    return dup(o, input);
}
fn progress(o: *x.Ops, interaction: c.JSValue) !void {
    const callable = try o.get(interaction, "notify");
    _ = try o.call(callable, interaction, &.{try value(o, progressInput, .{})});
}
fn authUrlInput(o: *x.Ops, url: c.JSValue) !c.JSValue {
    const input = try o.object();
    try o.put(input, "type", try o.text("auth_url"));
    try o.put(input, "url", try value(o, callMethod, .{url, @as([*:0]const u8, "toString")}));
    try o.put(input, "instructions", try o.text("Continue in your browser."));
    return dup(o, input);
}
fn authUrl(o: *x.Ops, interaction: c.JSValue, url: c.JSValue) !void {
    const callable = try o.get(interaction, "notify");
    _ = try o.call(callable, interaction, &.{try value(o, authUrlInput, .{url})});
}
fn bindPkce(o: *x.Ops, frame: *Browser, input: c.JSValue) !void {
    // Source object destructuring checks coercibility before the first getter.
    const receiver = try x.guest.toObject(o.s, input);
    try frame.take(.verifier, expression(o.s.engine, property, .{receiver, @as([*:0]const u8, "verifier")}));
    try frame.take(.challenge, expression(o.s.engine, property, .{receiver, @as([*:0]const u8, "challenge")}));
}
fn browserFinally(engine: *x.em.Engine, callback: c.JSValue, outcome: af.Action) !af.Action {
    // Ordinary finally failure replaces the Source return/throw. Retiring the
    // displaced completion still preserves any independently produced fatal.
    const closed = attempt(engine, callMethod, .{callback, @as([*:0]const u8, "close")}) catch |err| {
        var fatal = x.owned.Completion.initAction(engine, @as(anyerror!af.Action, err));
        switch (outcome) {
            .returned, .thrown => |incoming| fatal.release(incoming),
            .awaited => unreachable,
        }
        return fatal.finishAction();
    };
    var result = x.owned.Completion.initAction(engine, if (closed == .thrown) closed else outcome);
    if (closed == .thrown) switch (outcome) {
        .returned, .thrown => |incoming| result.release(incoming),
        .awaited => unreachable,
    } else result.release(closed.returned);
    return result.finishAction();
}
fn waitResult(o: *x.Ops, frame: *Browser, input: c.JSValue) !c.JSValue {
    try frame.copy(.credential, input);
    if (!o.truthy(input)) {
        const reason = try value(o, newError, .{@as([]const u8, "OAuth callback did not complete.")});
        _ = try o.s.engine.checked(c.JS_Throw(o.s.engine.context, dup(o, reason)));
        unreachable;
    }
    return dup(o, input);
}
fn browserAdvance(o: *x.Ops, args: []const c.JSValue, roots: []const c.JSValue, state: *c.JSValue, completion: af.Completion, input: c.JSValue) !af.Action {
    if (completion == .start) {
        const frame = try initFrame(o, Browser, state);
        try phaseSet(frame, .pkce);
        return .{ .awaited = try expression(o.s.engine, directCall, .{roots[0], @as([]const c.JSValue, &.{})}) };
    }
    const frame = Browser.from(state.*);
    const phase = try phaseGet(o, frame);
    if (completion == .rejected) {
        if (phase == .wait) return browserFinally(o.s.engine, frame.get(.callback), .{ .thrown = dup(o, input) });
        return .{ .thrown = dup(o, input) };
    }
    switch (phase) {
        .pkce => {
            try statement(o.s.engine, bindPkce, .{frame, input});
            try frame.take(.stateValue, expression(o.s.engine, uuid, .{}));
            try frame.take(.authorizeUrl, expression(o.s.engine, authorizationUrl, .{x.arg(args, 1)}));
            try statement(o.s.engine, setSearch, .{frame});
            try phaseSet(frame, .callback);
            return .{ .awaited = try expression(o.s.engine, startCallback, .{frame, args, roots}) };
        },
        .callback => {
            try frame.copy(.callback, input);
            // These two notifications are outside Source's try/finally.
            try statement(o.s.engine, progress, .{x.arg(args, 2)});
            try statement(o.s.engine, authUrl, .{x.arg(args, 2), frame.get(.authorizeUrl)});
            try phaseSet(frame, .wait);
            const pending = try attempt(o.s.engine, callMethod, .{input, @as([*:0]const u8, "wait")});
            if (pending == .thrown) return browserFinally(o.s.engine, input, pending);
            return .{ .awaited = pending.returned };
        },
        .wait => return browserFinally(o.s.engine, frame.get(.callback), try attempt(o.s.engine, waitResult, .{frame, input})),
        .method, .discovery => unreachable,
    }
}
fn browserBody(engine: *x.em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue, state: *c.JSValue, completion: af.Completion, input: c.JSValue) !af.Action {
    try entered(engine, completion);
    return actionExpression(engine, browserAdvance, .{args, roots, state, completion, input});
}

fn deviceRequest(o: *x.Ops, callable: c.JSValue, gateway: c.JSValue, interaction: c.JSValue) !c.JSValue {
    return dup(o, try o.call(callable, c.pi_js_undefined(), &.{gateway, try o.get(interaction, "signal")}));
}
fn deviceNoticeInput(o: *x.Ops, device: c.JSValue) !c.JSValue {
    const input = try o.object();
    try o.put(input, "type", try o.text("device_code"));
    try o.put(input, "userCode", try value(o, property, .{device, @as([*:0]const u8, "user_code")}));
    try o.put(input, "verificationUri", try value(o, property, .{device, @as([*:0]const u8, "verification_uri")}));
    try o.put(input, "intervalSeconds", try value(o, property, .{device, @as([*:0]const u8, "interval")}));
    try o.put(input, "expiresInSeconds", try value(o, property, .{device, @as([*:0]const u8, "expires_in")}));
    return dup(o, input);
}
fn deviceNotice(o: *x.Ops, interaction: c.JSValue, device: c.JSValue) !void {
    const callable = try o.get(interaction, "notify");
    _ = try o.call(callable, interaction, &.{try value(o, deviceNoticeInput, .{device})});
}
fn pollForm(o: *x.Ops, device_binding: c.JSValue) !c.JSValue {
    const constructor = try o.global("URLSearchParams");
    const input = try o.object();
    try o.put(input, "grant_type", try o.text("urn:ietf:params:oauth:grant-type:device_code"));
    try o.put(input, "client_id", try o.text("pi-gateway"));
    try o.put(input, "device_code", try o.get(try Device.read(o.s, device_binding), "device_code"));
    return construct(o, constructor, &.{input});
}
fn pollRequest(o: *x.Ops, roots: []const c.JSValue) !c.JSValue {
    const callable = roots[3];
    const gateway = try Device.read(o.s, roots[0]);
    const body = try value(o, pollForm, .{roots[1]});
    const signal = try o.get(try Device.read(o.s, roots[2]), "signal");
    return dup(o, try o.call(callable, c.pi_js_undefined(), &.{gateway, body, signal}));
}
fn pollComplete(o: *x.Ops, credentials: c.JSValue) !c.JSValue {
    const result = try o.object();
    try o.put(result, "status", try o.text("complete"));
    try o.put(result, "value", credentials);
    return dup(o, result);
}
fn isResponseError(engine: *x.em.Engine, input: c.JSValue, constructor: c.JSValue) !bool {
    var boundary: x.guest.Boundary = .{ .engine = engine };
    try boundary.begin();
    const result = c.JS_IsInstanceOf(engine.context, input, constructor);
    try boundary.finishStatus(result);
    return result == 1;
}
fn pollStatus(o: *x.Ops, reason: c.JSValue) !c.JSValue {
    const status = try o.get(reason, "oauthError");
    inline for (.{
        .{ "authorization_pending", "pending", "" },
        .{ "slow_down", "slow_down", "" },
        .{ "expired_token", "failed", "Device authorization expired." },
        .{ "access_denied", "failed", "Device authorization was denied." },
    }) |entry| {
        if (c.JS_IsStrictEqual(o.s.engine.context, status, try o.text(entry[0]))) {
            const result = try o.object();
            try o.put(result, "status", try o.text(entry[1]));
            if (comptime entry[2].len != 0) try o.put(result, "message", try o.text(entry[2]));
            return dup(o, result);
        }
    }
    // An internal sentinel for switch default, never a Source result.
    return c.pi_js_undefined();
}
fn pollCatch(o: *x.Ops, frame: *Poll, reason: c.JSValue, constructor: c.JSValue) !af.Action {
    try frame.copy(.errorValue, reason);
    if (!try isResponseError(o.s.engine, reason, constructor)) return .{ .thrown = try expression(o.s.engine, raise, .{reason}) };
    const result = try value(o, pollStatus, .{reason});
    if (c.JS_IsUndefined(result)) return .{ .thrown = try expression(o.s.engine, raise, .{reason}) };
    return .{ .returned = dup(o, result) };
}
fn pollAdvance(o: *x.Ops, roots: []const c.JSValue, state: *c.JSValue, completion: af.Completion, input: c.JSValue) !af.Action {
    if (completion == .start) {
        const frame = try initFrame(o, Poll, state);
        const outcome = try attempt(o.s.engine, pollRequest, .{roots});
        if (outcome == .returned) return .{ .awaited = outcome.returned };
        _ = try o.own(outcome.thrown);
        return pollCatch(o, frame, outcome.thrown, roots[4]);
    }
    const frame = Poll.from(state.*);
    if (completion == .rejected) return pollCatch(o, frame, input, roots[4]);
    try frame.copy(.credentials, input);
    return .{ .returned = try expression(o.s.engine, pollComplete, .{input}) };
}
fn pollBody(engine: *x.em.Engine, _: c.JSValue, _: []const c.JSValue, roots: []const c.JSValue, state: *c.JSValue, completion: af.Completion, input: c.JSValue) !af.Action {
    try entered(engine, completion);
    return actionExpression(engine, pollAdvance, .{roots, state, completion, input});
}
fn pollingOptions(o: *x.Ops, frame: *Device, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    const options = try o.object();
    try o.put(options, "intervalSeconds", try value(o, property, .{frame.get(.device), @as([*:0]const u8, "interval")}));
    try o.put(options, "expiresInSeconds", try value(o, property, .{frame.get(.device), @as([*:0]const u8, "expires_in")}));
    try o.put(options, "signal", try value(o, property, .{x.arg(args, 1), @as([*:0]const u8, "signal")}));
    const gateway = try frame.captureImmutableArgument(o.s, .gatewayCapture, "gateway", x.arg(args, 0));
    const device = try frame.capture(o.s, .device, "device");
    const interaction = try frame.captureImmutableArgument(o.s, .interactionCapture, "interaction", x.arg(args, 1));
    const poll = try o.own(try af.createResumableArrowWithClose(o.s.engine, "poll", 0, pollBody,
        &.{gateway, device, interaction, roots[2], roots[3]}, c.pi_js_undefined(), Poll.closeAtAsyncTerminal));
    try o.put(options, "poll", poll);
    return dup(o, options);
}
fn startPolling(o: *x.Ops, frame: *Device, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    const callable = roots[1];
    const options = try value(o, pollingOptions, .{frame, args, roots});
    return dup(o, try o.call(callable, c.pi_js_undefined(), &.{options}));
}
fn deviceAdvance(o: *x.Ops, args: []const c.JSValue, roots: []const c.JSValue, state: *c.JSValue, completion: af.Completion, input: c.JSValue) !af.Action {
    if (completion == .start) {
        _ = try initFrame(o, Device, state);
        return .{ .awaited = try expression(o.s.engine, deviceRequest, .{roots[0], x.arg(args, 0), x.arg(args, 1)}) };
    }
    if (completion == .rejected) return .{ .thrown = dup(o, input) };
    const frame = Device.from(state.*);
    try frame.copy(.device, input);
    try statement(o.s.engine, deviceNotice, .{x.arg(args, 1), input});
    // Source returns the polling Promise; it does not await it here.
    return .{ .returned = try expression(o.s.engine, startPolling, .{frame, args, roots}) };
}
fn deviceBody(engine: *x.em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue, state: *c.JSValue, completion: af.Completion, input: c.JSValue) !af.Action {
    try entered(engine, completion);
    return actionExpression(engine, deviceAdvance, .{args, roots, state, completion, input});
}


fn optionsNameString(o: *x.Ops, binding: c.JSValue) !c.JSValue {
    const options = try sync.read(o.s, binding);
    return dup(o, try o.stringify(try o.get(options, "name")));
}
fn stringValue(o: *x.Ops, input: c.JSValue) !c.JSValue {
    return dup(o, try o.stringify(input));
}
fn promptMessage(o: *x.Ops, options: c.JSValue) !c.JSValue {
    const prefix = try o.text("Sign in to ");
    const name = try value(o, optionsNameString, .{options});
    const prompt_prefix = try o.binary(0, prefix, name);
    return dup(o, try o.binary(0, prompt_prefix, try o.text(":")));
}
fn promptOptions(o: *x.Ops, options: c.JSValue) !c.JSValue {
    const input = try o.object();
    try o.put(input, "type", try o.text("select"));
    try o.put(input, "message", try value(o, promptMessage, .{options}));
    const choices = try p.array(o.s);
    inline for (.{
        .{ "browser", "Sign in with browser (recommended)" },
        .{ "device-code", "Sign in with device code (when signing in from another device)" },
    }, 0..) |choice, index| {
        const item = try o.object();
        try o.put(item, "id", try o.text(choice[0]));
        try o.put(item, "label", try o.text(choice[1]));
        try p.index(o.s, choices, index, item);
    }
    try o.put(input, "options", choices);
    return dup(o, input);
}
fn promptLogin(o: *x.Ops, interaction: c.JSValue, options: c.JSValue) !c.JSValue {
    const callable = try o.get(interaction, "prompt");
    const input = try value(o, promptOptions, .{options});
    return dup(o, try o.call(callable, interaction, &.{input}));
}
fn loginDevice(o: *x.Ops, interaction: c.JSValue, roots: []const c.JSValue) !c.JSValue {
    const gateway = try Factory.read(o.s, roots[1]);
    return dup(o, try o.call(roots[3], c.pi_js_undefined(), &.{gateway, interaction}));
}
fn loginDiscovery(o: *x.Ops, interaction: c.JSValue, roots: []const c.JSValue) !c.JSValue {
    const gateway = try Factory.read(o.s, roots[1]);
    return dup(o, try o.call(roots[4], c.pi_js_undefined(), &.{gateway, try o.get(interaction, "signal")}));
}
fn loginBrowser(o: *x.Ops, interaction: c.JSValue, discovery: c.JSValue, roots: []const c.JSValue) !c.JSValue {
    const gateway = try Factory.read(o.s, roots[1]);
    const endpoint = try o.get(discovery, "authorizationEndpoint");
    return dup(o, try o.call(roots[2], c.pi_js_undefined(), &.{gateway, endpoint, interaction}));
}
fn unknownMessage(o: *x.Ops, options: c.JSValue, method: c.JSValue) !c.JSValue {
    const prefix = try o.text("Unknown ");
    const name = try value(o, optionsNameString, .{options});
    const named = try o.binary(0, prefix, name);
    const message = try o.binary(0, named, try o.text(" sign-in method: "));
    return dup(o, try o.binary(0, message, try value(o, stringValue, .{method})));
}
fn unknownError(o: *x.Ops, options: c.JSValue, method: c.JSValue) !c.JSValue {
    const constructor = try o.global("Error");
    return construct(o, constructor, &.{try value(o, unknownMessage, .{options, method})});
}
fn loginAdvance(o: *x.Ops, args: []const c.JSValue, roots: []const c.JSValue, state: *c.JSValue, completion: af.Completion, input: c.JSValue) !af.Action {
    const interaction = x.arg(args, 0);
    if (completion == .start) {
        const frame = try initFrame(o, Login, state);
        try phaseSet(frame, .method);
        return .{ .awaited = try expression(o.s.engine, promptLogin, .{interaction, roots[0]}) };
    }
    if (completion == .rejected) return .{ .thrown = dup(o, input) };
    const frame = Login.from(state.*);
    switch (try phaseGet(o, frame)) {
        .method => {
            try frame.copy(.loginMethod, input);
            if (c.JS_IsStrictEqual(o.s.engine.context, input, try o.text("device-code")))
                return .{ .returned = try expression(o.s.engine, loginDevice, .{interaction, roots}) };
            if (c.JS_IsStrictEqual(o.s.engine.context, input, try o.text("browser"))) {
                try phaseSet(frame, .discovery);
                return .{ .awaited = try expression(o.s.engine, loginDiscovery, .{interaction, roots}) };
            }
            const reason = try value(o, unknownError, .{roots[0], input});
            return .{ .thrown = try expression(o.s.engine, raise, .{reason}) };
        },
        .discovery => {
            try frame.copy(.discovery, input);
            return .{ .returned = try expression(o.s.engine, loginBrowser, .{interaction, input, roots}) };
        },
        .pkce, .callback, .wait => unreachable,
    }
}
fn loginBody(engine: *x.em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue, state: *c.JSValue, completion: af.Completion, input: c.JSValue) !af.Action {
    try entered(engine, completion);
    return actionExpression(engine, loginAdvance, .{args, roots, state, completion, input});
}
fn refreshForm(o: *x.Ops, credential: c.JSValue) !c.JSValue {
    const constructor = try o.global("URLSearchParams");
    const fields = try o.object();
    try o.put(fields, "grant_type", try o.text("refresh_token"));
    try o.put(fields, "client_id", try o.text("pi-gateway"));
    try o.put(fields, "refresh_token", try o.get(credential, "refresh"));
    return construct(o, constructor, &.{fields});
}
fn refreshRequest(o: *x.Ops, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    const callable = roots[1];
    const gateway = try Factory.read(o.s, roots[0]);
    const body = try value(o, refreshForm, .{x.arg(args, 0)});
    return dup(o, try o.call(callable, c.pi_js_undefined(), &.{gateway, body, x.arg(args, 1)}));
}
fn refreshAdvance(o: *x.Ops, args: []const c.JSValue, roots: []const c.JSValue, state: *c.JSValue, completion: af.Completion, input: c.JSValue) !af.Action {
    if (completion == .start) {
        _ = try initFrame(o, Refresh, state);
        return .{ .awaited = try expression(o.s.engine, refreshRequest, .{args, roots}) };
    }
    if (completion == .rejected) return .{ .thrown = dup(o, input) };
    const frame = Refresh.from(state.*);
    try frame.copy(.refreshed, input);
    return .{ .returned = dup(o, frame.get(.refreshed)) };
}
fn refreshBody(engine: *x.em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue, state: *c.JSValue, completion: af.Completion, input: c.JSValue) !af.Action {
    try entered(engine, completion);
    return actionExpression(engine, refreshAdvance, .{args, roots, state, completion, input});
}
fn toAuthValue(o: *x.Ops, credential: c.JSValue) !c.JSValue {
    const result = try o.object();
    try o.put(result, "apiKey", try o.get(credential, "access"));
    return dup(o, result);
}
fn toAuthCall(engine: *x.em.Engine, _: c.JSValue, args: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
    // Source is an AsyncFunction with no Await; QuickJS owns Promise creation.
    return expression(engine, toAuthValue, .{x.arg(args, 0)});
}
fn normalizeGateway(o: *x.Ops, options: c.JSValue, callable: c.JSValue) !c.JSValue {
    return dup(o, try o.call(callable, c.pi_js_undefined(), &.{try o.get(options, "gateway")}));
}
fn factoryObject(o: *x.Ops, args: *sync.Arguments, frame: *Factory, roots: []const c.JSValue) !c.JSValue {
    const result = try o.object();
    try o.put(result, "name", try value(o, property, .{args.get(0), @as([*:0]const u8, "name")}));
    const options = try args.capture(o.s, 0);
    const gateway = try frame.capture(o.s, .gateway, "gateway");
    const login = try o.own(try af.createResumableWithClose(o.s.engine, "login", 1, loginBody,
        &.{options, gateway, roots[1], roots[2], roots[3]}, Login.closeAtAsyncTerminal));
    try o.put(result, "login", login);
    const refresh = try o.own(try af.createResumableWithClose(o.s.engine, "refresh", 2, refreshBody,
        &.{gateway, roots[4]}, Refresh.closeAtAsyncTerminal));
    try o.put(result, "refresh", refresh);
    try o.put(result, "toAuth", try o.own(try af.create(o.s.engine, "toAuth", 1, toAuthCall, &.{})));
    return dup(o, result);
}
fn factoryBody(o: *x.Ops, args: *sync.Arguments, roots: []const c.JSValue) !c.JSValue {
    const frame = try args.createFrame(o.s, Factory);
    try frame.take(.gateway, expression(o.s.engine, normalizeGateway, .{args.get(0), roots[0]}));
    return expression(o.s.engine, factoryObject, .{args, frame, roots});
}
fn factoryCall(engine: *x.em.Engine, _: c.JSValue, args: *sync.Arguments, roots: []const c.JSValue) !c.JSValue {
    return expression(engine, factoryBody, .{args, roots});
}
const ModuleImports = struct {
    normalize_gateway: c.JSValue,
    start_callback: c.JSValue,
    poll_device: c.JSValue,
    generate_pkce: c.JSValue,
};
const module_cache_key = "pi-native:radius-oauth-genuine";
fn createModuleFromImports(o: *x.Ops, imports: ModuleImports) !c.JSValue {
    const lexical_http = try o.own(try http.create(o.s.engine));
    const token = try o.get(lexical_http, "requestOAuthToken");
    const device_request = try o.get(lexical_http, "requestDeviceAuthorization");
    const error_class = try o.get(lexical_http, "OAuthResponseError");
    const discovery = try o.get(lexical_http, "loadRadiusOAuthDiscovery");
    const browser = try o.own(try af.createResumableWithClose(o.s.engine, "loginWithBrowser", 3,
        browserBody, &.{imports.generate_pkce, imports.start_callback, token}, Browser.closeAtAsyncTerminal));
    const device = try o.own(try af.createResumableWithClose(o.s.engine, "loginWithDeviceCode", 2,
        deviceBody, &.{device_request, imports.poll_device, token, error_class}, Device.closeAtAsyncTerminal));
    const factory_value = try o.own(try functions.createWithArguments(o.s.engine, "createRadiusOAuth", 1,
        .{ .formal_count = 1, .callback = factoryCall, .hooks = sync.frameHooks(Factory) },
        &.{imports.normalize_gateway, browser, device, discovery, token}));
    const result = try o.cell();
    inline for (.{"OAuthResponseError", "readOAuthResponseError", "loadRadiusOAuthDiscovery", "requestOAuthToken", "requestDeviceAuthorization"}) |name|
        try o.put(result, name, try o.get(lexical_http, name));
    try o.put(result, "loginWithBrowser", browser);
    try o.put(result, "loginWithDeviceCode", device);
    try o.put(result, "createRadiusOAuth", factory_value);
    return dup(o, result);
}
fn createModuleBody(o: *x.Ops) !c.JSValue {
    const config = try o.own(try @import("native_ai_radius_config.zig").create(o.s.engine));
    const normalize = try o.get(config, "normalizeRadiusGatewayUrl");
    const callback = try o.own(try @import("native_ai_oauth_callback_server.zig").create(o.s.engine));
    const start = try o.get(callback, "startOAuthCallbackServer");
    const device = try o.own(try @import("native_ai_oauth_device_code.zig").create(o.s.engine));
    const poll = try o.get(device, "pollOAuthDeviceCodeFlow");
    const pkce = try o.own(try @import("native_ai_oauth_pkce.zig").create(o.s.engine));
    return createModuleFromImports(o, .{
        .normalize_gateway = normalize,
        .start_callback = start,
        .poll_device = poll,
        .generate_pkce = try o.get(pkce, "generatePKCE"),
    });
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
fn factoryValue(o: *x.Ops) !c.JSValue {
    const module = try o.own(try moduleValue(o.s.engine));
    return dup(o, try o.get(module, "createRadiusOAuth"));
}
pub fn factory(engine: *x.em.Engine) !c.JSValue {
    try engine.checkNativeEntry();
    var invocation: x.em.Engine.NativeInvocation = .{};
    engine.enterNativeInvocation(&invocation);
    return x.finishInvocation(engine, &invocation, expression(engine, factoryValue, .{}));
}
fn createValue(o: *x.Ops, options: c.JSValue) !c.JSValue {
    const callable = try value(o, factoryValue, .{});
    return dup(o, try o.call(callable, c.pi_js_undefined(), &.{options}));
}
pub fn create(engine: *x.em.Engine, options: c.JSValue) !c.JSValue {
    try engine.checkNativeEntry();
    var invocation: x.em.Engine.NativeInvocation = .{};
    engine.enterNativeInvocation(&invocation);
    return x.finishInvocation(engine, &invocation, expression(engine, createValue, .{options}));
}
fn testModule(o: *x.Ops, imports: c.JSValue) !c.JSValue {
    return createModuleFromImports(o, .{
        .normalize_gateway = try o.get(imports, "normalizeRadiusGatewayUrl"),
        .start_callback = try o.get(imports, "startOAuthCallbackServer"),
        .poll_device = try o.get(imports, "pollOAuthDeviceCodeFlow"),
        .generate_pkce = try o.get(imports, "generatePKCE"),
    });
}
/// Controlled imports select the actual same declaration bodies. They never
/// publish into the production module cache or replace a production I/O owner.
pub fn createTestWithImports(engine: *x.em.Engine, imports: c.JSValue) !c.JSValue {
    if (!@import("builtin").is_test) @compileError("Controlled Radius OAuth imports are only for native controls");
    try engine.checkNativeEntry();
    var invocation: x.em.Engine.NativeInvocation = .{};
    engine.enterNativeInvocation(&invocation);
    return x.finishInvocation(engine, &invocation, expression(engine, testModule, .{imports}));
}
