//! Actual c268 auth/oauth/callback-server.ts. QuickJS owns each public
//! AsyncFunction, request Await and invocation. HTTP and page imports are real
//! retained module inputs; this module does not replace them with a worker flow.
const v = @import("native_public_values.zig");
const c = v.c;
const Engine = v.em.Engine;
const Scope = v.Scope;
const af = v.af;
const frames = @import("native_public_lexical_frame.zig");
const cache_key = "\x00ai-oauth-callback-server";
pub const Inputs = struct { http: c.JSValue, page: c.JSValue };

fn expression(engine: *Engine, comptime body: anytype, args: anytype) !c.JSValue {
    var s: Scope = .{ .engine = engine };
    return v.owned.finishValue(&s, @call(.auto, body, .{&s} ++ args));
}
fn statement(engine: *Engine, comptime body: anytype, args: anytype) !void {
    var s: Scope = .{ .engine = engine };
    return v.owned.finishVoid(&s, @call(.auto, body, .{&s} ++ args));
}
fn attempt(engine: *Engine, comptime body: anytype, args: anytype) !af.Action {
    var s: Scope = .{ .engine = engine };
    const result = @call(.auto, body, .{&s} ++ args);
    return v.owned.finishAction(&s, if (result) |result_value| .{ .returned = result_value } else |err| err);
}
fn action(engine: *Engine, comptime body: anytype, args: anytype) !af.Action {
    var s: Scope = .{ .engine = engine };
    return v.owned.finishAction(&s, @call(.auto, body, .{&s} ++ args));
}
fn value(s: *Scope, comptime body: anytype, args: anytype) !c.JSValue {
    return v.own(s, try expression(s.engine, body, args));
}
fn truth(s: *Scope, comptime body: anytype, args: anytype) !bool {
    return v.truthy(s, try expression(s.engine, body, args));
}
fn property(s: *Scope, receiver: c.JSValue, name: [*:0]const u8) !c.JSValue {
    return v.duplicate(s, try v.get(s, receiver, name));
}
fn invoke(s: *Scope, receiver: c.JSValue, name: [*:0]const u8, args: []const c.JSValue) !c.JSValue {
    return v.duplicate(s, try v.call(s, try v.get(s, receiver, name), receiver, args));
}
fn invokeVoid(s: *Scope, receiver: c.JSValue, name: [*:0]const u8, args: []const c.JSValue) !void {
    _ = try v.call(s, try v.get(s, receiver, name), receiver, args);
}
fn fieldTruthy(s: *Scope, receiver: c.JSValue, name: [*:0]const u8) !c.JSValue {
    return v.boolean(s, v.truthy(s, try v.get(s, receiver, name)));
}
fn fieldDefined(s: *Scope, receiver: c.JSValue, name: [*:0]const u8) !c.JSValue {
    return v.boolean(s, !c.JS_IsUndefined(try v.get(s, receiver, name)));
}
fn fixedError(s: *Scope, message: []const u8) !c.JSValue {
    const constructor = try v.global(s, "Error");
    return v.duplicate(s, try v.construct(s, constructor, &.{try v.text(s, message)}));
}
fn errorInstance(s: *Scope, incoming: c.JSValue) !c.JSValue {
    const constructor = try v.global(s, "Error");
    var boundary: v.guest.Boundary = .{ .engine = s.engine }; try boundary.begin();
    const result = c.JS_IsInstanceOf(s.engine.context, incoming, constructor);
    try boundary.finishStatus(result);
    return v.boolean(s, result != 0);
}
fn converted(s: *Scope, incoming: c.JSValue) !c.JSValue {
    return v.duplicate(s, try v.stringify(s, incoming));
}
fn convertedOwned(s: *Scope, incoming: c.JSValue) !c.JSValue {
    return converted(s, try v.own(s, incoming));
}
fn stringCall(s: *Scope, incoming: c.JSValue) !c.JSValue {
    return v.duplicate(s, try v.call(s, try v.global(s, "String"), c.pi_js_undefined(), &.{incoming}));
}
fn constructedStringError(s: *Scope, incoming: c.JSValue) !c.JSValue {
    const constructor = try v.global(s, "Error");
    const message = try value(s, stringCall, .{incoming});
    return v.duplicate(s, try v.construct(s, constructor, &.{message}));
}
fn normalizedError(s: *Scope, incoming: c.JSValue) !c.JSValue {
    if (try truth(s, errorInstance, .{incoming})) return v.duplicate(s, incoming);
    return expression(s.engine, constructedStringError, .{incoming});
}
fn append(s: *Scope, left: c.JSValue, right: c.JSValue) !c.JSValue {
    return v.binary(s, 0, left, right);
}
fn templated(s: *Scope, first: []const u8, input: c.JSValue, last: []const u8) !c.JSValue {
    const prefix = try v.text(s, first);
    const text = try value(s, converted, .{input});
    return v.duplicate(s, try append(s, try append(s, prefix, text), try v.text(s, last)));
}
fn templateError(s: *Scope, provider: c.JSValue, suffix: []const u8) !c.JSValue {
    const constructor = try v.global(s, "Error");
    const message = try value(s, templated, .{@as([]const u8, ""), provider, suffix});
    return v.duplicate(s, try v.construct(s, constructor, &.{message}));
}
fn releaseAction(completion: *v.owned.Completion, pending: af.Action) void {
    switch (pending) { .returned, .awaited, .thrown => |payload| completion.release(payload) }
}
fn finallyOwned(engine: *Engine, pending: af.Action, comptime body: anytype, args: anytype) !af.Action {
    var cleanup = v.owned.Completion.initVoid(engine, statement(engine, body, args));
    const completed = cleanup.finishAction() catch |err| {
        var fatal = v.owned.Completion.initAction(engine, @as(anyerror!af.Action, err));
        releaseAction(&fatal, pending); return fatal.finishAction();
    };
    return switch (completed) {
        .returned => |ignored| blk: {
            var outcome = v.owned.Completion.initAction(engine, pending);
            outcome.release(ignored); break :blk outcome.finishAction();
        },
        .thrown => blk: {
            var outcome = v.owned.Completion.initAction(engine, completed);
            releaseAction(&outcome, pending); break :blk outcome.finishAction();
        },
        .awaited => unreachable,
    };
}
fn sendPageCall(engine: *Engine, _: c.JSValue, args: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
    try statement(engine, sendPageBody, .{v.arg(args, 0), v.arg(args, 1), v.arg(args, 2)});
    return c.pi_js_undefined();
}
fn pageHeaders(s: *Scope) !c.JSValue {
    const headers = try v.object(s);
    try v.put(s, headers, "content-type", try v.text(s, "text/html; charset=utf-8"));
    try v.put(s, headers, "cache-control", try v.text(s, "no-store"));
    return v.duplicate(s, headers);
}
fn writeHead(s: *Scope, response: c.JSValue, status: c.JSValue) !void {
    const method = try v.get(s, response, "writeHead");
    const headers = try value(s, pageHeaders, .{});
    _ = try v.call(s, method, response, &.{status, headers});
}
fn sendPageBody(s: *Scope, response: c.JSValue, status: c.JSValue, html: c.JSValue) !void {
    try statement(s.engine, writeHead, .{response, status});
    try statement(s.engine, invokeVoid, .{response, @as([*:0]const u8, "end"), @as([]const c.JSValue, &.{html})});
}
fn noOp(_: *Engine, _: c.JSValue, _: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
    return c.pi_js_undefined();
}
fn asyncFunction(s: *Scope, name: [*:0]const u8, length: c_int, body: af.Body, roots: []const c.JSValue, comptime close: af.StateClose) !c.JSValue {
    var boundary: v.guest.Boundary = .{ .engine = s.engine }; try boundary.begin();
    return boundary.finishValue(s, af.createResumableWithClose(s.engine, name, length, body, roots, close));
}
fn asyncArrow(s: *Scope, length: c_int, body: af.Body, roots: []const c.JSValue, comptime close: af.StateClose) !c.JSValue {
    var boundary: v.guest.Boundary = .{ .engine = s.engine }; try boundary.begin();
    return boundary.finishValue(s, af.createResumableArrowWithClose(s.engine, "", length, body, roots, c.pi_js_undefined(), close));
}
pub fn create(engine: *Engine) !c.JSValue {
    try engine.checkNativeEntry();
    if (engine.native_module_values.get(cache_key)) |known| return c.JS_DupValue(engine.context, known);
    const http = engine.native_module_values.get("node:http") orelse
        engine.native_module_values.get("http") orelse return error.ActualNodeHttpServerModuleRequired;
    var s: Scope = .{ .engine = engine };
    return v.owned.finishValue(&s, createDefaultBody(&s, http));
}
fn createDefaultBody(s: *Scope, http: c.JSValue) !c.JSValue {
    const page = try v.own(s, try @import("native_ai_oauth_page.zig").create(s.engine));
    return createWithInputs(s.engine, .{ .http = http, .page = page });
}
pub fn createWithInputs(engine: *Engine, inputs: Inputs) !c.JSValue {
    try engine.checkNativeEntry();
    if (engine.native_module_values.get(cache_key)) |known| return c.JS_DupValue(engine.context, known);
    const candidate = try expression(engine, createBody, .{inputs});
    if (engine.native_module_values.get(cache_key)) |known| {
        var completed = v.owned.Completion.initValue(engine, c.JS_DupValue(engine.context, known));
        completed.release(candidate); return completed.finishValue();
    }
    engine.native_module_values.ensureUnusedCapacity(engine.gpa, 1) catch |err| {
        var failed = v.owned.Completion.initValue(engine, @as(anyerror!c.JSValue, err));
        failed.release(candidate); return failed.finishValue();
    };
    engine.native_module_values.putAssumeCapacity(cache_key, candidate);
    return c.JS_DupValue(engine.context, candidate);
}
fn createBody(s: *Scope, inputs: Inputs) !c.JSValue {
    const create_server = try v.get(s, inputs.http, "createServer");
    const error_page = try v.get(s, inputs.page, "oauthErrorHtml");
    const success_page = try v.get(s, inputs.page, "oauthSuccessHtml");
    const send_page = try v.ordinary(s, "sendPage", 3, sendPageCall, &.{});
    const result = try v.object(s);
    try v.put(s, result, "startOAuthCallbackServer", try asyncFunction(s, "startOAuthCallbackServer", 1, startNative,
        &.{create_server, error_page, success_page, send_page}, StartFrame.closeAtAsyncTerminal));
    try v.put(s, result, "waitForCallbackOrManualInput", try asyncFunction(s, "waitForCallbackOrManualInput", 3, waitNative,
        &.{}, WaitFrame.closeAtAsyncTerminal));
    return v.duplicate(s, result);
}
pub fn start(engine: *Engine, options: c.JSValue) !c.JSValue {
    return expression(engine, startEntry, .{options});
}
pub const startOAuthCallbackServer = start;
fn startEntry(s: *Scope, options: c.JSValue) !c.JSValue {
    const module = try v.own(s, try create(s.engine));
    return v.duplicate(s, try v.call(s, try v.get(s, module, "startOAuthCallbackServer"), c.pi_js_undefined(), &.{options}));
}
pub fn waitForCallbackOrManualInput(engine: *Engine, interaction: c.JSValue, callback: c.JSValue, prompt: c.JSValue) !c.JSValue {
    return expression(engine, waitEntry, .{interaction, callback, prompt});
}
fn waitEntry(s: *Scope, interaction: c.JSValue, callback: c.JSValue, prompt: c.JSValue) !c.JSValue {
    const module = try v.own(s, try create(s.engine));
    return v.duplicate(s, try v.call(s, try v.get(s, module, "waitForCallbackOrManualInput"),
        c.pi_js_undefined(), &.{interaction, callback, prompt}));
}



const StartFrame = frames.Frame(enum {
    options_parameter, provider_name, signal, resolve_wait, reject_wait, wait_promise,
    claimed, settled, timer, on_abort, finish, server, address, redirect_host,
});
fn bindingTruthy(s: *Scope, binding: c.JSValue) !c.JSValue {
    return v.boolean(s, v.truthy(s, try StartFrame.read(s, binding)));
}
fn bindingProperty(s: *Scope, binding: c.JSValue, name: [*:0]const u8) !c.JSValue {
    return v.duplicate(s, try v.get(s, try StartFrame.read(s, binding), name));
}
fn bindingMethod(s: *Scope, binding: c.JSValue, name: [*:0]const u8, args: []const c.JSValue) !void {
    const receiver = try StartFrame.read(s, binding);
    _ = try v.call(s, try v.get(s, receiver, name), receiver, args);
}
fn bindingCall(s: *Scope, binding: c.JSValue, args: []const c.JSValue) !c.JSValue {
    return v.duplicate(s, try v.call(s, try StartFrame.read(s, binding), c.pi_js_undefined(), args));
}
fn noOpArrow(s: *Scope, name: [*:0]const u8) !c.JSValue {
    return v.duplicate(s, try v.arrow(s, name, 0, noOp, &.{}));
}
fn bindOptions(s: *Scope, frame: *StartFrame, options: c.JSValue) !void {
    const receiver = try v.guest.toObject(s, options);
    try frame.copy(.provider_name, try v.get(s, receiver, "providerName"));
    try frame.copy(.signal, try v.get(s, receiver, "signal"));
}
fn signalAborted(s: *Scope, signal: c.JSValue) !c.JSValue {
    return v.boolean(s, !v.nullish(signal) and v.truthy(s, try v.get(s, signal, "aborted")));
}
fn waitExecutor(engine: *Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    try StartFrame.assign(roots[0], c.JS_DupValue(engine.context, v.arg(args, 0)));
    try StartFrame.assign(roots[1], c.JS_DupValue(engine.context, v.arg(args, 1)));
    return c.pi_js_undefined();
}
fn makeWaitPromise(s: *Scope, frame: *StartFrame) !c.JSValue {
    const constructor = try v.global(s, "Promise");
    const resolve = try frame.capture(s, .resolve_wait, "resolveWait");
    const reject = try frame.capture(s, .reject_wait, "rejectWait");
    const executor = try v.arrow(s, "", 2, waitExecutor, &.{resolve, reject});
    return v.duplicate(s, try v.construct(s, constructor, &.{executor}));
}
fn observeWaitRejection(s: *Scope, frame: *StartFrame) !void {
    const receiver = frame.get(.wait_promise);
    const method = try v.get(s, receiver, "catch");
    const ignore = try v.arrow(s, "", 0, noOp, &.{});
    _ = try v.call(s, method, receiver, &.{ignore});
}
fn fixedErrorRecord(s: *Scope, message: []const u8) !c.JSValue {
    const record = try v.object(s);
    try v.put(s, record, "error", try value(s, fixedError, .{message}));
    return v.duplicate(s, record);
}
fn templateErrorRecord(s: *Scope, provider: c.JSValue, suffix: []const u8) !c.JSValue {
    const record = try v.object(s);
    try v.put(s, record, "error", try value(s, templateError, .{provider, suffix}));
    return v.duplicate(s, record);
}
fn fieldRecord(s: *Scope, name: [*:0]const u8, incoming: c.JSValue) !c.JSValue {
    const record = try v.object(s);
    try v.put(s, record, name, incoming);
    return v.duplicate(s, record);
}
fn finishFixed(s: *Scope, finish: c.JSValue, message: []const u8) !c.JSValue {
    const callback = try StartFrame.read(s, finish);
    const record = try value(s, fixedErrorRecord, .{message});
    return v.duplicate(s, try v.call(s, callback, c.pi_js_undefined(), &.{record}));
}
fn finishField(s: *Scope, finish: c.JSValue, name: [*:0]const u8, incoming: c.JSValue) !c.JSValue {
    const callback = try StartFrame.read(s, finish);
    const record = try value(s, fieldRecord, .{name, incoming});
    return v.duplicate(s, try v.call(s, callback, c.pi_js_undefined(), &.{record}));
}
fn abortCallback(engine: *Engine, _: c.JSValue, _: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    return expression(engine, finishFixed, .{roots[0], @as([]const u8, "Login cancelled")});
}
fn makeAbortCallback(s: *Scope, frame: *StartFrame) !c.JSValue {
    const finish = try frame.capture(s, .finish, "finish");
    return v.duplicate(s, try v.arrow(s, "onAbort", 0, abortCallback, &.{finish}));
}
fn clearTimer(s: *Scope, timer_binding: c.JSValue) !void {
    const clear = try v.global(s, "clearTimeout");
    const timer = try StartFrame.read(s, timer_binding);
    _ = try v.call(s, clear, c.pi_js_undefined(), &.{timer});
}
fn removeAbort(s: *Scope, signal_binding: c.JSValue, abort_binding: c.JSValue) !void {
    const signal = try StartFrame.read(s, signal_binding);
    if (v.nullish(signal)) return;
    const method = try v.get(s, signal, "removeEventListener");
    const event = try v.text(s, "abort");
    const callback = try StartFrame.read(s, abort_binding);
    _ = try v.call(s, method, signal, &.{event, callback});
}
fn hasError(s: *Scope, result: c.JSValue) !c.JSValue {
    if (!c.JS_IsObject(result)) return v.typeError(s, "invalid 'in' operand");
    const name = try v.text(s, "error");
    var boundary: v.guest.Boundary = .{ .engine = s.engine }; try boundary.begin();
    const atom = c.JS_ValueToAtom(s.engine.context, name);
    defer if (atom != c.JS_ATOM_NULL) c.JS_FreeAtom(s.engine.context, atom);
    try boundary.finishStatus(if (atom == c.JS_ATOM_NULL) -1 else 0);
    var property_boundary: v.guest.Boundary = .{ .engine = s.engine }; try property_boundary.begin();
    const found = c.JS_HasProperty(s.engine.context, result, atom);
    try property_boundary.finishStatus(if (found < 0) -1 else 0);
    return v.boolean(s, found != 0);
}
fn settleField(s: *Scope, callback_binding: c.JSValue, result: c.JSValue, field: [*:0]const u8) !void {
    const callback = try StartFrame.read(s, callback_binding);
    const incoming = try value(s, property, .{result, field});
    _ = try v.call(s, callback, c.pi_js_undefined(), &.{incoming});
}
fn finishCallback(engine: *Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    try statement(engine, finishBody, .{v.arg(args, 0), roots});
    return c.pi_js_undefined();
}
fn finishBody(s: *Scope, result: c.JSValue, roots: []const c.JSValue) !void {
    if (try truth(s, bindingTruthy, .{roots[0]})) return;
    try StartFrame.assign(roots[0], c.JS_NewBool(s.engine.context, true));
    if (try truth(s, bindingTruthy, .{roots[1]})) try statement(s.engine, clearTimer, .{roots[1]});
    try statement(s.engine, removeAbort, .{roots[2], roots[3]});
    if (try truth(s, hasError, .{result}))
        try statement(s.engine, settleField, .{roots[4], result, @as([*:0]const u8, "error")})
    else
        try statement(s.engine, settleField, .{roots[5], result, @as([*:0]const u8, "value")});
}
fn makeFinish(s: *Scope, frame: *StartFrame) !c.JSValue {
    const settled = try frame.capture(s, .settled, "settled");
    const timer = try frame.capture(s, .timer, "timer");
    const signal = try frame.capture(s, .signal, "signal");
    const abort = try frame.capture(s, .on_abort, "onAbort");
    const reject = try frame.capture(s, .reject_wait, "rejectWait");
    const resolve = try frame.capture(s, .resolve_wait, "resolveWait");
    return v.duplicate(s, try v.arrow(s, "finish", 1, finishCallback, &.{settled, timer, signal, abort, reject, resolve}));
}
fn serverError(engine: *Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    return expression(engine, finishField, .{roots[0], @as([*:0]const u8, "error"), v.arg(args, 0)});
}
fn listenReady(engine: *Engine, _: c.JSValue, _: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    try statement(engine, listenOff, .{roots[0], roots[1]});
    try statement(engine, resolveListen, .{roots[2]});
    return c.pi_js_undefined();
}
fn listenOff(s: *Scope, server_binding: c.JSValue, reject: c.JSValue) !void {
    const server = try StartFrame.read(s, server_binding);
    const method = try v.get(s, server, "off");
    _ = try v.call(s, method, server, &.{try v.text(s, "error"), reject});
}
fn resolveListen(s: *Scope, resolve: c.JSValue) !void {
    _ = try v.call(s, resolve, c.pi_js_undefined(), &.{});
}
fn listenOnce(s: *Scope, server_binding: c.JSValue, reject: c.JSValue) !void {
    const server = try StartFrame.read(s, server_binding);
    const method = try v.get(s, server, "once");
    _ = try v.call(s, method, server, &.{try v.text(s, "error"), reject});
}
fn listenInvoke(s: *Scope, server_binding: c.JSValue, options_binding: c.JSValue, resolve: c.JSValue, reject: c.JSValue) !void {
    const server = try StartFrame.read(s, server_binding);
    const method = try v.get(s, server, "listen");
    const port = try value(s, bindingProperty, .{options_binding, @as([*:0]const u8, "port")});
    const host = try value(s, bindingProperty, .{options_binding, @as([*:0]const u8, "host")});
    const ready = try v.arrow(s, "", 0, listenReady, &.{server_binding, reject, resolve});
    _ = try v.call(s, method, server, &.{port, host, ready});
}
fn listenExecutor(engine: *Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    try statement(engine, listenOnce, .{roots[0], v.arg(args, 1)});
    try statement(engine, listenInvoke, .{roots[0], roots[1], v.arg(args, 0), v.arg(args, 1)});
    return c.pi_js_undefined();
}
fn listenPromise(s: *Scope, frame: *StartFrame, options: c.JSValue) !c.JSValue {
    const constructor = try v.global(s, "Promise");
    const server = try frame.capture(s, .server, "server");
    const input = try frame.captureImmutableArgument(s, .options_parameter, "options", options);
    const executor = try v.arrow(s, "", 2, listenExecutor, &.{server, input});
    return v.duplicate(s, try v.construct(s, constructor, &.{executor}));
}
fn attachServerError(s: *Scope, frame: *StartFrame) !void {
    const server = frame.get(.server);
    const method = try v.get(s, server, "on");
    const event = try v.text(s, "error");
    const finish = try frame.capture(s, .finish, "finish");
    const callback = try v.arrow(s, "", 1, serverError, &.{finish});
    _ = try v.call(s, method, server, &.{event, callback});
}
fn onceOptions(s: *Scope) !c.JSValue {
    const options = try v.object(s); try v.put(s, options, "once", v.boolean(s, true));
    return v.duplicate(s, options);
}
fn attachAbort(s: *Scope, frame: *StartFrame) !void {
    const signal = frame.get(.signal);
    if (v.nullish(signal)) return;
    const method = try v.get(s, signal, "addEventListener");
    const event = try v.text(s, "abort");
    const options = try value(s, onceOptions, .{});
    _ = try v.call(s, method, signal, &.{event, frame.get(.on_abort), options});
}
fn timeoutBody(s: *Scope, finish_binding: c.JSValue, provider_binding: c.JSValue) !c.JSValue {
    const finish = try StartFrame.read(s, finish_binding);
    const record = try value(s, timeoutRecord, .{provider_binding});
    return v.duplicate(s, try v.call(s, finish, c.pi_js_undefined(), &.{record}));
}
fn timeoutRecord(s: *Scope, provider_binding: c.JSValue) !c.JSValue {
    const result = try v.object(s);
    const constructor = try v.global(s, "Error");
    const message = try value(s, bindingTemplate, .{provider_binding, @as([]const u8, ""), @as([]const u8, " sign-in timed out")});
    try v.put(s, result, "error", try v.construct(s, constructor, &.{message}));
    return v.duplicate(s, result);
}
fn bindingTemplate(s: *Scope, binding: c.JSValue, first: []const u8, last: []const u8) !c.JSValue {
    const prefix = try v.text(s, first);
    const converted_value = try value(s, bindingText, .{binding});
    return v.duplicate(s, try append(s, try append(s, prefix, converted_value), try v.text(s, last)));
}
fn bindingText(s: *Scope, binding: c.JSValue) !c.JSValue {
    return converted(s, try StartFrame.read(s, binding));
}
fn timeoutCallback(engine: *Engine, _: c.JSValue, _: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    return expression(engine, timeoutBody, .{roots[0], roots[1]});
}
fn installTimeout(s: *Scope, frame: *StartFrame, options: c.JSValue) !c.JSValue {
    const callable = try v.global(s, "setTimeout");
    const finish = try frame.capture(s, .finish, "finish");
    const provider = try frame.capture(s, .provider_name, "providerName");
    const callback = try v.arrow(s, "", 0, timeoutCallback, &.{finish, provider});
    const milliseconds = try value(s, property, .{options, @as([*:0]const u8, "timeoutMs")});
    return v.duplicate(s, try v.call(s, callable, c.pi_js_undefined(), &.{callback, milliseconds}));
}
fn redirectHost(s: *Scope, options: c.JSValue) !c.JSValue {
    const host = try v.get(s, options, "redirectHost");
    return v.duplicate(s, if (v.nullish(host)) try v.get(s, options, "host") else host);
}
fn hostIncludesColon(s: *Scope, host: c.JSValue) !c.JSValue {
    const method = try v.get(s, host, "includes");
    const found = try v.call(s, method, host, &.{try v.text(s, ":")});
    return v.boolean(s, v.truthy(s, found));
}
fn uriHostText(s: *Scope, host: c.JSValue) !c.JSValue {
    if (try truth(s, hostIncludesColon, .{host})) return templated(s, "[", host, "]");
    return converted(s, host);
}
fn propertyText(s: *Scope, receiver: c.JSValue, name: [*:0]const u8) !c.JSValue {
    return converted(s, try v.get(s, receiver, name));
}
fn redirectUri(s: *Scope, frame: *StartFrame, options: c.JSValue) !c.JSValue {
    const initial = try v.text(s, "http://");
    const host = try value(s, uriHostText, .{frame.get(.redirect_host)});
    const prefix = try append(s, try append(s, initial, host), try v.text(s, ":"));
    const port = try value(s, propertyText, .{frame.get(.address), @as([*:0]const u8, "port")});
    const with_port = try append(s, prefix, port);
    const path = try value(s, propertyText, .{options, @as([*:0]const u8, "path")});
    return v.duplicate(s, try append(s, with_port, path));
}
fn returnWait(engine: *Engine, _: c.JSValue, _: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    return expression(engine, readBinding, .{roots[0]});
}
fn readBinding(s: *Scope, binding: c.JSValue) !c.JSValue { return v.duplicate(s, try StartFrame.read(s, binding)); }
fn cancelWait(engine: *Engine, _: c.JSValue, _: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    try statement(engine, cancelWaitBody, .{roots});
    return c.pi_js_undefined();
}
fn cancelWaitBody(s: *Scope, roots: []const c.JSValue) !void {
    if (!(try truth(s, bindingTruthy, .{roots[0]}))) {
        _ = try value(s, finishField, .{roots[1], @as([*:0]const u8, "value"), c.pi_js_undefined()});
    }
}
fn closeServer(engine: *Engine, _: c.JSValue, _: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    try statement(engine, closeServerBody, .{roots});
    return c.pi_js_undefined();
}
fn closeServerBody(s: *Scope, roots: []const c.JSValue) !void {
    try statement(s.engine, closeFinish, .{roots[0]});
    try statement(s.engine, bindingMethod, .{roots[1], @as([*:0]const u8, "close"), @as([]const c.JSValue, &.{})});
}
fn closeFinish(s: *Scope, finish: c.JSValue) !void {
    _ = try value(s, finishFixed, .{finish, @as([]const u8, "OAuth callback server closed")});
}
fn startResult(s: *Scope, frame: *StartFrame, options: c.JSValue) !c.JSValue {
    const result = try v.object(s);
    try v.put(s, result, "redirectUri", try value(s, redirectUri, .{frame, options}));
    const promised = try frame.capture(s, .wait_promise, "waitPromise");
    try v.put(s, result, "wait", try v.arrow(s, "wait", 0, returnWait, &.{promised}));
    const claimed = try frame.capture(s, .claimed, "claimed");
    const finish = try frame.capture(s, .finish, "finish");
    try v.put(s, result, "cancel", try v.arrow(s, "cancel", 0, cancelWait, &.{claimed, finish}));
    const server = try frame.capture(s, .server, "server");
    try v.put(s, result, "close", try v.arrow(s, "close", 0, closeServer, &.{finish, server}));
    return v.duplicate(s, result);
}
fn startNative(engine: *Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue, owner: *c.JSValue, completion: af.Completion, input: c.JSValue) !af.Action {
    return action(engine, startAdvance, .{args, roots, owner, completion, input});
}
fn startAdvance(s: *Scope, args: []const c.JSValue, roots: []const c.JSValue, owner: *c.JSValue, completion: af.Completion, input: c.JSValue) !af.Action {
    const options = v.arg(args, 0);
    if (completion == .rejected) {
        try @import("native_async_body.zig").enterRejectedContinuation(s.engine);
        return .{ .thrown = v.duplicate(s, input) };
    }
    if (completion == .start) {
        const frame = try StartFrame.createAsync(s);
        af.replaceState(s.engine, owner, v.duplicate(s, frame.owner));
        try statement(s.engine, bindOptions, .{frame, options});
        if (try truth(s, signalAborted, .{frame.get(.signal)}))
            return .{ .thrown = try expression(s.engine, fixedError, .{@as([]const u8, "Login cancelled")}) };
        try frame.take(.resolve_wait, expression(s.engine, noOpArrow, .{@as([*:0]const u8, "resolveWait")}));
        try frame.take(.reject_wait, expression(s.engine, noOpArrow, .{@as([*:0]const u8, "rejectWait")}));
        try frame.take(.wait_promise, expression(s.engine, makeWaitPromise, .{frame}));
        try statement(s.engine, observeWaitRejection, .{frame});
        try frame.take(.claimed, c.JS_NewBool(s.engine.context, false));
        try frame.take(.settled, c.JS_NewBool(s.engine.context, false));
        try frame.clear(.timer);
        try frame.take(.on_abort, expression(s.engine, makeAbortCallback, .{frame}));
        try frame.take(.finish, expression(s.engine, makeFinish, .{frame}));
        try frame.take(.server, expression(s.engine, makeServer, .{frame, options, roots}));
        return .{ .awaited = try expression(s.engine, listenPromise, .{frame, options}) };
    }
    const frame = StartFrame.from(owner.*);
    try frame.take(.address, expression(s.engine, invoke, .{frame.get(.server), @as([*:0]const u8, "address"), @as([]const c.JSValue, &.{})}));
    if (!v.truthy(s, frame.get(.address)) or c.JS_IsString(frame.get(.address))) {
        try statement(s.engine, invokeVoid, .{frame.get(.server), @as([*:0]const u8, "close"), @as([]const c.JSValue, &.{})});
        return .{ .thrown = try expression(s.engine, fixedError, .{@as([]const u8, "OAuth callback server did not bind to TCP")}) };
    }
    try statement(s.engine, attachServerError, .{frame});
    try statement(s.engine, attachAbort, .{frame});
    if (try truth(s, fieldDefined, .{options, @as([*:0]const u8, "timeoutMs")}))
        try frame.take(.timer, expression(s.engine, installTimeout, .{frame, options}));
    try frame.take(.redirect_host, expression(s.engine, redirectHost, .{options}));
    return .{ .returned = try expression(s.engine, startResult, .{frame, options}) };
}


const Listener = struct {
    const options = 0; const send_page = 1; const error_page = 2; const claimed = 3;
    const settled = 4; const provider = 5; const finish = 6; const success_page = 7;
};
const Request = struct {
    const request = 0; const options = 1; const send_page = 2; const response = 3;
    const error_page = 4; const claimed = 5; const settled = 6; const provider = 7;
    const finish = 8; const success_page = 9;
};
const RequestFrame = frames.Frame(enum { url, error_value, description, code, value, caught_error, failure });
fn makeServer(s: *Scope, frame: *StartFrame, options: c.JSValue, imports: []const c.JSValue) !c.JSValue {
    // Imported createServer is selected before creating its actual listener.
    const create_server = try v.own(s, v.duplicate(s, imports[0]));
    const input = try frame.captureImmutableArgument(s, .options_parameter, "options", options);
    const claimed = try frame.capture(s, .claimed, "claimed");
    const settled = try frame.capture(s, .settled, "settled");
    const provider = try frame.capture(s, .provider_name, "providerName");
    const finish = try frame.capture(s, .finish, "finish");
    const listener = try v.arrow(s, "", 2, requestListener,
        &.{input, imports[3], imports[1], claimed, settled, provider, finish, imports[2]});
    return v.duplicate(s, try v.call(s, create_server, c.pi_js_undefined(), &.{listener}));
}
fn requestListener(engine: *Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    try statement(engine, invokeRequest, .{args, roots});
    return c.pi_js_undefined();
}
fn invokeRequest(s: *Scope, args: []const c.JSValue, roots: []const c.JSValue) !void {
    const body = try asyncArrow(s, 0, requestNative,
        &.{v.arg(args, 0), roots[Listener.options], roots[Listener.send_page], v.arg(args, 1),
            roots[Listener.error_page], roots[Listener.claimed], roots[Listener.settled],
            roots[Listener.provider], roots[Listener.finish], roots[Listener.success_page]},
        RequestFrame.closeAtAsyncTerminal);
    _ = try v.call(s, body, c.pi_js_undefined(), &.{});
}
fn requestUrlArgument(s: *Scope, request: c.JSValue) !c.JSValue {
    const url = try v.get(s, request, "url");
    return v.duplicate(s, if (v.nullish(url)) try v.text(s, "/") else url);
}
fn newRequestUrl(s: *Scope, request: c.JSValue) !c.JSValue {
    const constructor = try v.global(s, "URL");
    const url = try value(s, requestUrlArgument, .{request});
    const base = try v.text(s, "http://localhost");
    return v.duplicate(s, try v.construct(s, constructor, &.{url, base}));
}
fn requestGet(s: *Scope, request: c.JSValue) !c.JSValue {
    return v.boolean(s, try v.eq(s, try v.get(s, request, "method"), "GET"));
}
fn requestPath(s: *Scope, frame: *RequestFrame, options_binding: c.JSValue) !c.JSValue {
    const path = try value(s, property, .{frame.get(.url), @as([*:0]const u8, "pathname")});
    const expected = try value(s, bindingProperty, .{options_binding, @as([*:0]const u8, "path")});
    return v.boolean(s, v.equal(s, path, expected));
}
fn optionsStateDefined(s: *Scope, options_binding: c.JSValue) !c.JSValue {
    return v.boolean(s, !c.JS_IsUndefined(try value(s, bindingProperty, .{options_binding, @as([*:0]const u8, "state")})));
}
fn searchParameter(s: *Scope, url: c.JSValue, name: []const u8) !c.JSValue {
    const parameters = try v.get(s, url, "searchParams");
    const method = try v.get(s, parameters, "get");
    return v.duplicate(s, try v.call(s, method, parameters, &.{try v.text(s, name)}));
}
fn stateMatches(s: *Scope, frame: *RequestFrame, options_binding: c.JSValue) !c.JSValue {
    const actual = try value(s, searchParameter, .{frame.get(.url), @as([]const u8, "state")});
    const expected = try value(s, bindingProperty, .{options_binding, @as([*:0]const u8, "state")});
    return v.boolean(s, v.equal(s, actual, expected));
}
fn fixedPageHtml(s: *Scope, page: c.JSValue, message: []const u8) !c.JSValue {
    const callable = try v.own(s, v.duplicate(s, page));
    return v.duplicate(s, try v.call(s, callable, c.pi_js_undefined(), &.{try v.text(s, message)}));
}
fn sendFixedPage(s: *Scope, roots: []const c.JSValue, status: i32, message: []const u8) !void {
    const send_page = try v.own(s, v.duplicate(s, roots[Request.send_page]));
    const response = try v.own(s, v.duplicate(s, roots[Request.response]));
    const html = try value(s, fixedPageHtml, .{roots[Request.error_page], message});
    _ = try v.call(s, send_page, c.pi_js_undefined(), &.{response, c.JS_NewInt32(s.engine.context, status), html});
}
fn descriptionValue(s: *Scope, frame: *RequestFrame) !c.JSValue {
    const description = try value(s, searchParameter, .{frame.get(.url), @as([]const u8, "error_description")});
    return v.duplicate(s, if (v.nullish(description)) frame.get(.error_value) else description);
}
fn failedPageHtml(s: *Scope, roots: []const c.JSValue, description: c.JSValue) !c.JSValue {
    const callable = try v.own(s, v.duplicate(s, roots[Request.error_page]));
    const message = try value(s, bindingTemplate, .{roots[Request.provider], @as([]const u8, ""), @as([]const u8, " authorization failed.")});
    return v.duplicate(s, try v.call(s, callable, c.pi_js_undefined(), &.{message, description}));
}
fn sendFailedPage(s: *Scope, roots: []const c.JSValue, description: c.JSValue) !void {
    const send_page = try v.own(s, v.duplicate(s, roots[Request.send_page]));
    const response = try v.own(s, v.duplicate(s, roots[Request.response]));
    const html = try value(s, failedPageHtml, .{roots, description});
    _ = try v.call(s, send_page, c.pi_js_undefined(), &.{response, c.JS_NewInt32(s.engine.context, 400), html});
}
fn authorizationMessage(s: *Scope, provider_binding: c.JSValue, description: c.JSValue) !c.JSValue {
    const initial = try v.text(s, "");
    const provider = try value(s, bindingText, .{provider_binding});
    const prefix = try append(s, try append(s, initial, provider), try v.text(s, " authorization failed: "));
    const detail = try value(s, converted, .{description});
    return v.duplicate(s, try append(s, prefix, detail));
}
fn authorizationError(s: *Scope, provider_binding: c.JSValue, description: c.JSValue) !c.JSValue {
    const constructor = try v.global(s, "Error");
    const message = try value(s, authorizationMessage, .{provider_binding, description});
    return v.duplicate(s, try v.construct(s, constructor, &.{message}));
}
fn authorizationErrorRecord(s: *Scope, provider_binding: c.JSValue, description: c.JSValue) !c.JSValue {
    const record = try v.object(s);
    try v.put(s, record, "error", try value(s, authorizationError, .{provider_binding, description}));
    return v.duplicate(s, record);
}
fn finishAuthorizationError(s: *Scope, roots: []const c.JSValue, description: c.JSValue) !void {
    const finish = try StartFrame.read(s, roots[Request.finish]);
    const record = try value(s, authorizationErrorRecord, .{roots[Request.provider], description});
    _ = try v.call(s, finish, c.pi_js_undefined(), &.{record});
}
fn completeRequest(s: *Scope, options_binding: c.JSValue, code: c.JSValue) !c.JSValue {
    const options = try StartFrame.read(s, options_binding);
    const method = try v.get(s, options, "complete");
    return v.duplicate(s, try v.call(s, method, options, &.{code}));
}
fn successHtml(s: *Scope, roots: []const c.JSValue) !c.JSValue {
    const callable = try v.own(s, v.duplicate(s, roots[Request.success_page]));
    const message = try value(s, bindingTemplate, .{roots[Request.provider],
        @as([]const u8, "Signed in to "), @as([]const u8, ". You may now close this page.")});
    return v.duplicate(s, try v.call(s, callable, c.pi_js_undefined(), &.{message}));
}
fn sendSuccess(s: *Scope, roots: []const c.JSValue) !void {
    const send_page = try v.own(s, v.duplicate(s, roots[Request.send_page]));
    const response = try v.own(s, v.duplicate(s, roots[Request.response]));
    const html = try value(s, successHtml, .{roots});
    _ = try v.call(s, send_page, c.pi_js_undefined(), &.{response, c.JS_NewInt32(s.engine.context, 200), html});
}
fn finishRequestValue(s: *Scope, roots: []const c.JSValue, incoming: c.JSValue) !void {
    _ = try value(s, finishField, .{roots[Request.finish], @as([*:0]const u8, "value"), incoming});
}
fn catchHtml(s: *Scope, roots: []const c.JSValue, failure: c.JSValue) !c.JSValue {
    const callable = try v.own(s, v.duplicate(s, roots[Request.error_page]));
    const message = try value(s, bindingTemplate, .{roots[Request.provider], @as([]const u8, ""), @as([]const u8, " sign-in failed.")});
    const detail = try value(s, property, .{failure, @as([*:0]const u8, "message")});
    return v.duplicate(s, try v.call(s, callable, c.pi_js_undefined(), &.{message, detail}));
}
fn sendCatch(s: *Scope, roots: []const c.JSValue, failure: c.JSValue) !void {
    const send_page = try v.own(s, v.duplicate(s, roots[Request.send_page]));
    const response = try v.own(s, v.duplicate(s, roots[Request.response]));
    const html = try value(s, catchHtml, .{roots, failure});
    _ = try v.call(s, send_page, c.pi_js_undefined(), &.{response, c.JS_NewInt32(s.engine.context, 502), html});
}
fn finishRequestFailure(s: *Scope, roots: []const c.JSValue, failure: c.JSValue) !void {
    _ = try value(s, finishField, .{roots[Request.finish], @as([*:0]const u8, "error"), failure});
}
fn requestTry(s: *Scope, frame: *RequestFrame, roots: []const c.JSValue, completion: af.Completion, input: c.JSValue) !af.Action {
    if (completion == .start)
        return .{ .awaited = try expression(s.engine, completeRequest, .{roots[Request.options], frame.get(.code)}) };
    if (completion == .rejected) {
        try @import("native_async_body.zig").enterRejectedContinuation(s.engine);
        return .{ .thrown = v.duplicate(s, input) };
    }
    try frame.copy(.value, input);
    try statement(s.engine, sendSuccess, .{roots});
    try statement(s.engine, finishRequestValue, .{roots, frame.get(.value)});
    return .{ .returned = c.pi_js_undefined() };
}
fn requestCatch(s: *Scope, frame: *RequestFrame, roots: []const c.JSValue) !af.Action {
    try frame.take(.failure, expression(s.engine, normalizedError, .{frame.get(.caught_error)}));
    try statement(s.engine, sendCatch, .{roots, frame.get(.failure)});
    try statement(s.engine, finishRequestFailure, .{roots, frame.get(.failure)});
    return .{ .returned = c.pi_js_undefined() };
}
fn requestNative(engine: *Engine, _: c.JSValue, _: []const c.JSValue, roots: []const c.JSValue, owner: *c.JSValue, completion: af.Completion, input: c.JSValue) !af.Action {
    return action(engine, requestAdvance, .{roots, owner, completion, input});
}
fn requestAdvance(s: *Scope, roots: []const c.JSValue, owner: *c.JSValue, completion: af.Completion, input: c.JSValue) !af.Action {
    const frame = if (completion == .start) blk: {
        const made = try RequestFrame.createAsync(s);
        af.replaceState(s.engine, owner, v.duplicate(s, made.owner));
        try made.take(.url, expression(s.engine, newRequestUrl, .{roots[Request.request]}));
        if (!(try truth(s, requestGet, .{roots[Request.request]})) or
            !(try truth(s, requestPath, .{made, roots[Request.options]}))) {
            try statement(s.engine, sendFixedPage, .{roots, @as(i32, 404), @as([]const u8, "Callback route not found.")});
            return .{ .returned = c.pi_js_undefined() };
        }
        if ((try truth(s, optionsStateDefined, .{roots[Request.options]})) and
            !(try truth(s, stateMatches, .{made, roots[Request.options]}))) {
            try statement(s.engine, sendFixedPage, .{roots, @as(i32, 400), @as([]const u8, "State mismatch.")});
            return .{ .returned = c.pi_js_undefined() };
        }
        if ((try truth(s, bindingTruthy, .{roots[Request.claimed]})) or
            (try truth(s, bindingTruthy, .{roots[Request.settled]}))) {
            try statement(s.engine, sendFixedPage, .{roots, @as(i32, 409), @as([]const u8, "This sign-in has already been handled.")});
            return .{ .returned = c.pi_js_undefined() };
        }
        try made.take(.error_value, expression(s.engine, searchParameter, .{made.get(.url), @as([]const u8, "error")}));
        if (v.truthy(s, made.get(.error_value))) {
            try made.take(.description, expression(s.engine, descriptionValue, .{made}));
            try statement(s.engine, sendFailedPage, .{roots, made.get(.description)});
            try statement(s.engine, finishAuthorizationError, .{roots, made.get(.description)});
            return .{ .returned = c.pi_js_undefined() };
        }
        try made.take(.code, expression(s.engine, searchParameter, .{made.get(.url), @as([]const u8, "code")}));
        if (!v.truthy(s, made.get(.code))) {
            try statement(s.engine, sendFixedPage, .{roots, @as(i32, 400), @as([]const u8, "Missing authorization code.")});
            return .{ .returned = c.pi_js_undefined() };
        }
        try StartFrame.assign(roots[Request.claimed], c.JS_NewBool(s.engine.context, true));
        // Only the complete/send/finish sequence belongs to this Source try.
        break :blk made;
    } else RequestFrame.from(owner.*);
    const completed = try action(s.engine, requestTry, .{frame, roots, completion, input});
    return switch (completed) {
        .awaited, .returned => completed,
        .thrown => |reason| blk: {
            try frame.take(.caught_error, reason);
            break :blk requestCatch(s, frame, roots);
        },
    };
}

const WaitFrame = frames.Frame(enum { callback_parameter, manual_abort, manual_error, manual, value, input, stage });
fn waitNative(engine: *Engine, _: c.JSValue, args: []const c.JSValue, _: []const c.JSValue, owner: *c.JSValue, completion: af.Completion, input: c.JSValue) !af.Action {
    return action(engine, waitAdvance, .{args, owner, completion, input});
}
fn emptyAbort(s: *Scope) !c.JSValue {
    return v.duplicate(s, try v.construct(s, try v.global(s, "AbortController"), &.{}));
}
fn manualPromptObject(s: *Scope, frame: *WaitFrame, prompt: c.JSValue) !c.JSValue {
    const result = try v.object(s);
    try v.put(s, result, "type", try v.text(s, "manual_code"));
    var operations: @import("native_sdk_catalog_values.zig").Ops = .{ .s = s };
    try @import("native_sdk_catalog_copy.zig").into(&operations, result, prompt);
    try v.put(s, result, "signal", try v.get(s, frame.get(.manual_abort), "signal"));
    return v.duplicate(s, result);
}
fn manualPrompt(s: *Scope, frame: *WaitFrame, interaction: c.JSValue, prompt: c.JSValue) !c.JSValue {
    const method = try v.get(s, interaction, "prompt");
    const options = try value(s, manualPromptObject, .{frame, prompt});
    return v.duplicate(s, try v.call(s, method, interaction, &.{options}));
}
fn cancelCallback(s: *Scope, binding: c.JSValue) !void {
    const callback = try WaitFrame.read(s, binding);
    if (!v.nullish(callback)) _ = try v.call(s, try v.get(s, callback, "cancel"), callback, &.{});
}
fn manualThen(engine: *Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    try statement(engine, cancelCallback, .{roots[0]});
    return c.JS_DupValue(engine.context, v.arg(args, 0));
}
fn manualCatch(engine: *Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    try WaitFrame.assign(roots[0], expression(engine, normalizedError, .{v.arg(args, 0)}));
    try statement(engine, cancelCallback, .{roots[1]});
    return c.pi_js_undefined();
}
fn thenManual(s: *Scope, frame: *WaitFrame, callback: c.JSValue, incoming: c.JSValue) !c.JSValue {
    const receiver = try v.own(s, incoming);
    const method = try v.get(s, receiver, "then");
    const binding = try frame.captureImmutableArgument(s, .callback_parameter, "callback", callback);
    const next = try v.arrow(s, "", 1, manualThen, &.{binding});
    return v.duplicate(s, try v.call(s, method, receiver, &.{next}));
}
fn catchManual(s: *Scope, frame: *WaitFrame, callback: c.JSValue, incoming: c.JSValue) !c.JSValue {
    const receiver = try v.own(s, incoming);
    const method = try v.get(s, receiver, "catch");
    const error_binding = try frame.capture(s, .manual_error, "manualError");
    const callback_binding = try frame.captureImmutableArgument(s, .callback_parameter, "callback", callback);
    const next = try v.arrow(s, "", 1, manualCatch, &.{error_binding, callback_binding});
    return v.duplicate(s, try v.call(s, method, receiver, &.{next}));
}
fn manualChain(engine: *Engine, frame: *WaitFrame, interaction: c.JSValue, callback: c.JSValue, prompt: c.JSValue) !c.JSValue {
    const promised = try expression(engine, manualPrompt, .{frame, interaction, prompt});
    const continued = try expression(engine, thenManual, .{frame, callback, promised});
    return expression(engine, catchManual, .{frame, callback, continued});
}
fn callbackWait(s: *Scope, callback: c.JSValue) !c.JSValue {
    if (v.nullish(callback)) return c.pi_js_undefined();
    return invoke(s, callback, "wait", &.{});
}
fn manualFinally(s: *Scope, frame: *WaitFrame) !void {
    try invokeVoid(s, frame.get(.manual_abort), "abort", &.{});
}
fn callbackResult(s: *Scope, result: c.JSValue) !c.JSValue {
    const record = try v.object(s);
    try v.put(s, record, "type", try v.text(s, "callback"));
    try v.put(s, record, "value", result);
    return v.duplicate(s, record);
}
fn manualResult(s: *Scope, result: c.JSValue) !c.JSValue {
    const record = try v.object(s);
    try v.put(s, record, "type", try v.text(s, "manual"));
    try v.put(s, record, "input", if (v.nullish(result)) try v.text(s, "") else result);
    return v.duplicate(s, record);
}
fn waitTry(s: *Scope, frame: *WaitFrame, callback: c.JSValue, completion: af.Completion, input: c.JSValue) !af.Action {
    if (completion == .start) return .{ .awaited = try expression(s.engine, callbackWait, .{callback}) };
    if (completion == .rejected) {
        try @import("native_async_body.zig").enterRejectedContinuation(s.engine);
        return .{ .thrown = v.duplicate(s, input) };
    }
    if (v.equal(s, frame.get(.stage), c.JS_NewInt32(s.engine.context, 1))) {
        try frame.copy(.value, input);
        if (v.truthy(s, frame.get(.manual_error))) return .{ .thrown = v.duplicate(s, frame.get(.manual_error)) };
        if (!c.JS_IsUndefined(frame.get(.value))) return .{ .returned = try expression(s.engine, callbackResult, .{frame.get(.value)}) };
        try frame.take(.stage, c.JS_NewInt32(s.engine.context, 2));
        return .{ .awaited = v.duplicate(s, frame.get(.manual)) };
    }
    try frame.copy(.input, input);
    if (v.truthy(s, frame.get(.manual_error))) return .{ .thrown = v.duplicate(s, frame.get(.manual_error)) };
    return .{ .returned = try expression(s.engine, manualResult, .{frame.get(.input)}) };
}
fn waitAdvance(s: *Scope, args: []const c.JSValue, owner: *c.JSValue, completion: af.Completion, input: c.JSValue) !af.Action {
    const frame = if (completion == .start) blk: {
        const made = try WaitFrame.createAsync(s);
        af.replaceState(s.engine, owner, v.duplicate(s, made.owner));
        try made.take(.manual_abort, expression(s.engine, emptyAbort, .{}));
        try made.clear(.manual_error);
        // Source's try begins only after the complete prompt/then/catch chain.
        try made.take(.manual, manualChain(s.engine, made, v.arg(args, 0), v.arg(args, 1), v.arg(args, 2)));
        try made.take(.stage, c.JS_NewInt32(s.engine.context, 1));
        break :blk made;
    } else WaitFrame.from(owner.*);
    const result = try action(s.engine, waitTry, .{frame, v.arg(args, 1), completion, input});
    if (result == .awaited) return result;
    return finallyOwned(s.engine, result, manualFinally, .{frame});
}
