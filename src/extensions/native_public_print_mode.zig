//! Actual c268 single-shot print mode over the retained application owners.
//! QuickJS owns all Await/adoption; closures capture the actual Source bindings.
const v = @import("native_public_values.zig");
const c = v.c;
const Engine = v.em.Engine;
const Scope = v.Scope;
const af = v.af;
const caught = @import("native_agent_af_values.zig").caught;
const enterRejected = @import("native_async_body.zig").enterRejectedContinuation;
const lexical = @import("native_public_lexical_frame.zig");
const guard = @import("native_sdk_output_guard.zig");
const key = "\x00native.public.print-mode";
pub const Inputs = struct { output: guard.Exports, shell: c.JSValue };
const Locals = enum {
    runtime_host, mode, messages, initial_message, initial_images, exit_code,
    session, unsubscribe, unsubscribe_backpressure, disposed, signal_cleanup_handlers,
    dispose_runtime, register_signal_handlers, rebind_session,
    header, message, state, last_message, assistant_message, content, caught_error, cleanup,
    iterator_receiver, iterator_next, iterator_active, phase, pending_value, pending_thrown,
};
const Frame = lexical.Frame(Locals);
const Phase = enum(i32) { before_try, rebind, initial, message, dispose, flush };
const Async = enum { set_rebind, dispose, rebind, fork, navigate, reload, backpressure };
const SimpleAsync = enum { new_session, switch_session };
const Sync = enum { register_signals, signal, signal_exit, signal_cleanup, wait_idle, on_error, event };

fn expression(engine: *Engine, comptime body: anytype, args: anytype) !c.JSValue {
    var s: Scope = .{ .engine = engine };
    return v.owned.finishValue(&s, @call(.auto, body, .{&s} ++ args));
}
fn statement(engine: *Engine, comptime body: anytype, args: anytype) !void {
    var s: Scope = .{ .engine = engine };
    return v.owned.finishVoid(&s, @call(.auto, body, .{&s} ++ args));
}
fn duplicate(engine: *Engine, value: c.JSValue) c.JSValue { return c.JS_DupValue(engine.context, value); }
fn truthy(engine: *Engine, value: c.JSValue) bool { return c.JS_ToBool(engine.context, value) == 1; }
fn field(engine: *Engine, receiver: c.JSValue, name: [*:0]const u8) !c.JSValue {
    return expression(engine, fieldBody, .{ receiver, name });
}
fn fieldBody(s: *Scope, receiver: c.JSValue, name: [*:0]const u8) !c.JSValue {
    const selected = try v.own(s, v.duplicate(s, receiver));
    return v.duplicate(s, try v.get(s, selected, name));
}
fn fieldEqual(engine: *Engine, receiver: c.JSValue, name: [*:0]const u8, value: []const u8) !bool {
    return truthy(engine, try expression(engine, fieldEqualBody, .{ receiver, name, value }));
}
fn fieldEqualBody(s: *Scope, receiver: c.JSValue, name: [*:0]const u8, value: []const u8) !c.JSValue {
    return v.boolean(s, try v.eq(s, try v.get(s, receiver, name), value));
}
fn bindingField(s: *Scope, binding: c.JSValue, name: [*:0]const u8) !c.JSValue {
    return v.duplicate(s, try v.get(s, try Frame.read(s, binding), name));
}
fn bindingEqual(engine: *Engine, binding: c.JSValue, expected: []const u8) !bool {
    return truthy(engine, try expression(engine, bindingEqualBody, .{ binding, expected }));
}
fn bindingEqualBody(s: *Scope, binding: c.JSValue, expected: []const u8) !c.JSValue {
    return v.boolean(s, try v.eq(s, try Frame.read(s, binding), expected));
}
fn bindingTruthy(engine: *Engine, binding: c.JSValue) !bool {
    return truthy(engine, try expression(engine, bindingTruthyBody, .{binding}));
}
fn bindingTruthyBody(s: *Scope, binding: c.JSValue) !c.JSValue { return v.boolean(s, v.truthy(s, try Frame.read(s, binding))); }
fn bindingCall(s: *Scope, binding: c.JSValue, args: []const c.JSValue) !c.JSValue {
    return v.duplicate(s, try v.call(s, try Frame.read(s, binding), c.pi_js_undefined(), args));
}
fn optionalBinding(s: *Scope, binding: c.JSValue) !void {
    const callable = try Frame.read(s, binding);
    if (!v.nullish(callable)) _ = try v.call(s, callable, c.pi_js_undefined(), &.{});
}
fn bindingMethod(s: *Scope, binding: c.JSValue, name: [*:0]const u8, args: []const c.JSValue) !c.JSValue {
    const receiver = try Frame.read(s, binding);
    return v.duplicate(s, try v.invoke(s, receiver, name, args));
}
fn functionCall(s: *Scope, callable: c.JSValue, args: []const c.JSValue) !c.JSValue {
    return v.duplicate(s, try v.call(s, callable, c.pi_js_undefined(), args));
}
fn discardFunction(s: *Scope, callable: c.JSValue, args: []const c.JSValue) !void { _ = try v.call(s, callable, c.pi_js_undefined(), args); }
fn asyncArrow(s: *Scope, comptime kind: Async, name: [*:0]const u8, length: c_int, roots: []const c.JSValue) !c.JSValue {
    const Adapter = struct {
        fn call(engine: *Engine, _: c.JSValue, args: []const c.JSValue, saved: []const c.JSValue, state: *c.JSValue, completion: af.Completion, input: c.JSValue) !af.Action {
            _ = state;
            var scope: Scope = .{ .engine = engine };
            return v.owned.finishAction(&scope, asyncBody(&scope, kind, args, saved, completion, input));
        }
    };
    var boundary: v.guest.Boundary = .{ .engine = s.engine }; try boundary.begin();
    return boundary.finishValue(s, af.createResumableArrow(s.engine, name, length, Adapter.call, roots, c.pi_js_undefined()));
}
fn simpleAsync(s: *Scope, comptime kind: SimpleAsync, name: [*:0]const u8, length: c_int, roots: []const c.JSValue) !c.JSValue {
    const Adapter = struct {
        fn call(engine: *Engine, _: c.JSValue, args: []const c.JSValue, saved: []const c.JSValue) !c.JSValue {
            return expression(engine, simpleAsyncBody, .{ kind, args, saved });
        }
    };
    var boundary: v.guest.Boundary = .{ .engine = s.engine }; try boundary.begin();
    return boundary.finishValue(s, af.createArrow(s.engine, name, length, Adapter.call, roots, c.pi_js_undefined()));
}
fn syncArrow(s: *Scope, comptime kind: Sync, name: [*:0]const u8, length: c_int, roots: []const c.JSValue) !c.JSValue {
    const Adapter = struct {
        fn call(engine: *Engine, _: c.JSValue, args: []const c.JSValue, saved: []const c.JSValue) !c.JSValue {
            return expression(engine, syncBody, .{ kind, args, saved });
        }
    };
    return v.arrow(s, name, length, Adapter.call, roots);
}
fn simpleAsyncBody(s: *Scope, comptime kind: SimpleAsync, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    return bindingMethod(s, roots[0], if (kind == .new_session) "newSession" else "switchSession",
        if (kind == .new_session) &.{v.arg(args, 0)} else &.{ v.arg(args, 0), v.arg(args, 1) });
}
fn asyncBody(s: *Scope, comptime kind: Async, args: []const c.JSValue, roots: []const c.JSValue, completion: af.Completion, input: c.JSValue) !af.Action {
    if (completion == .rejected) {
        try enterRejected(s.engine);
        return .{ .thrown = v.duplicate(s, input) };
    }
    if (completion == .fulfilled) {
        if (kind == .fork or kind == .navigate) {
            const result = try v.object(s);
            try v.put(s, result, "cancelled", try v.get(s, input, "cancelled"));
            return .{ .returned = v.duplicate(s, result) };
        }
        if (kind == .rebind) try rebindSubscriptions(s.engine, roots);
        return .{ .returned = c.pi_js_undefined() };
    }
    const awaited = switch (kind) {
        .set_rebind => try expression(s.engine, bindingCall, .{ roots[0], @as([]const c.JSValue, &.{}) }),
        .dispose => blk: {
            if (try bindingTruthy(s.engine, roots[0])) return .{ .returned = c.pi_js_undefined() };
            try Frame.assign(roots[0], c.JS_NewBool(s.engine.context, true));
            try statement(s.engine, optionalBinding, .{roots[1]});
            try statement(s.engine, optionalBinding, .{roots[2]});
            break :blk try expression(s.engine, bindingMethod, .{ roots[3], @as([*:0]const u8, "dispose"), @as([]const c.JSValue, &.{}) });
        },
        .rebind => blk: {
            try Frame.assign(roots[1], expression(s.engine, bindingField, .{ roots[0], @as([*:0]const u8, "session") }));
            break :blk try expression(s.engine, bindExtensions, .{roots});
        },
        .fork => try expression(s.engine, bindingMethod, .{ roots[0], @as([*:0]const u8, "fork"), @as([]const c.JSValue, &.{ v.arg(args, 0), v.arg(args, 1) }) }),
        .navigate => try expression(s.engine, navigateTree, .{ roots[0], v.arg(args, 0), v.arg(args, 1) }),
        .reload => try expression(s.engine, bindingMethod, .{ roots[0], @as([*:0]const u8, "reload"), @as([]const c.JSValue, &.{}) }),
        .backpressure => try expression(s.engine, functionCall, .{ roots[0], @as([]const c.JSValue, &.{}) }),
    };
    return .{ .awaited = awaited };
}
fn optionalField(s: *Scope, target: c.JSValue, name: [*:0]const u8) !c.JSValue {
    return if (v.nullish(target)) c.pi_js_undefined() else v.get(s, target, name);
}
fn navigateTree(s: *Scope, binding: c.JSValue, target: c.JSValue, options: c.JSValue) !c.JSValue {
    const session = try Frame.read(s, binding);
    const callable = try v.get(s, session, "navigateTree");
    const actual_options = try v.object(s);
    inline for (.{ "summarize", "customInstructions", "replaceInstructions", "label" }) |name|
        try v.put(s, actual_options, name, try optionalField(s, options, name));
    return v.duplicate(s, try v.call(s, callable, session, &.{ target, actual_options }));
}
fn bindExtensions(s: *Scope, roots: []const c.JSValue) !c.JSValue {
    const session = try Frame.read(s, roots[1]);
    const callable = try v.get(s, session, "bindExtensions");
    const options = try v.object(s);
    try v.put(s, options, "mode", try v.text(s, if (try bindingEqual(s.engine, roots[2], "json")) "json" else "print"));
    const actions = try v.object(s);
    try v.put(s, actions, "waitForIdle", try syncArrow(s, .wait_idle, "waitForIdle", 0, &.{roots[1]}));
    try v.put(s, actions, "newSession", try simpleAsync(s, .new_session, "newSession", 1, &.{roots[0]}));
    try v.put(s, actions, "fork", try asyncArrow(s, .fork, "fork", 2, &.{roots[0]}));
    try v.put(s, actions, "navigateTree", try asyncArrow(s, .navigate, "navigateTree", 2, &.{roots[1]}));
    try v.put(s, actions, "switchSession", try simpleAsync(s, .switch_session, "switchSession", 2, &.{roots[0]}));
    try v.put(s, actions, "reload", try asyncArrow(s, .reload, "reload", 0, &.{roots[1]}));
    try v.put(s, options, "commandContextActions", actions);
    try v.put(s, options, "onError", try syncArrow(s, .on_error, "onError", 1, &.{}));
    return v.duplicate(s, try v.call(s, callable, session, &.{options}));
}
fn rebindSubscriptions(engine: *Engine, roots: []const c.JSValue) !void {
    try statement(engine, optionalBinding, .{roots[3]});
    try statement(engine, optionalBinding, .{roots[4]});
    try Frame.assign(roots[3], expression(engine, subscribeEvents, .{roots}));
    try Frame.assign(roots[4], if (try bindingEqual(engine, roots[2], "json"))
        expression(engine, subscribeBackpressure, .{ roots[1], roots[6] })
    else @as(anyerror!c.JSValue, c.pi_js_undefined()));
}
fn subscribeEvents(s: *Scope, roots: []const c.JSValue) !c.JSValue {
    const session = try Frame.read(s, roots[1]);
    const callable = try v.get(s, session, "subscribe");
    const callback = try syncArrow(s, .event, "", 1, &.{ roots[2], roots[5], roots[7] });
    return v.duplicate(s, try v.call(s, callable, session, &.{callback}));
}
fn subscribeBackpressure(s: *Scope, session_binding: c.JSValue, wait: c.JSValue) !c.JSValue {
    const agent = try v.own(s, try expression(s.engine, bindingField, .{ session_binding, @as([*:0]const u8, "agent") }));
    const callable = try v.get(s, agent, "subscribe");
    const callback = try asyncArrow(s, .backpressure, "", 0, &.{wait});
    return v.duplicate(s, try v.call(s, callable, agent, &.{callback}));
}
fn syncBody(s: *Scope, comptime kind: Sync, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    switch (kind) {
        .register_signals => try registerSignals(s.engine, roots),
        .signal => {
            try statement(s.engine, discardFunction, .{ roots[2], @as([]const c.JSValue, &.{}) });
            try statement(s.engine, signalFinally, .{ roots[0], roots[1] });
        },
        .signal_exit => {
            const process = try v.global(s, "process"); const exit_method = try v.get(s, process, "exit");
            _ = try v.call(s, exit_method, process, &.{v.number(s, if (try v.eq(s, roots[0], "SIGHUP")) 129 else 143)});
        },
        .signal_cleanup => {
            const process = try v.global(s, "process"); const off = try v.get(s, process, "off");
            return v.duplicate(s, try v.call(s, off, process, &.{ roots[0], roots[1] }));
        },
        .wait_idle => return bindingMethod(s, roots[0], "waitForIdle", &.{}),
        .on_error => try logExtension(s, v.arg(args, 0)),
        .event => if (try bindingEqual(s.engine, roots[0], "json"))
            try statement(s.engine, writeJson, .{ roots[1], v.arg(args, 0), roots[2] }),
    }
    return c.pi_js_undefined();
}
fn signalFinally(s: *Scope, dispose_binding: c.JSValue, signal: c.JSValue) !void {
    const promise = try v.own(s, try expression(s.engine, bindingCall, .{ dispose_binding, @as([]const c.JSValue, &.{}) }));
    const method = try v.get(s, promise, "finally");
    const callback = try syncArrow(s, .signal_exit, "", 0, &.{signal});
    _ = try v.call(s, method, promise, &.{callback});
}
const SignalFrame = lexical.Frame(enum { signals, signal, handler });
fn registerSignals(engine: *Engine, roots: []const c.JSValue) !void {
    return statement(engine, registerSignalsScoped, .{roots});
}
fn registerSignalsScoped(s: *Scope, roots: []const c.JSValue) !void {
    const f = try SignalFrame.create(s);
    var completion = v.owned.Completion.initVoid(s.engine, registerSignalsBody(f, roots));
    f.close(&completion);
    return completion.finishVoid();
}
fn registerSignalsBody(f: *SignalFrame, roots: []const c.JSValue) !void {
    try f.take(.signals, expression(f.engine, initialSignals, .{}));
    if (!truthy(f.engine, try expression(f.engine, windowsPlatform, .{})))
        try statement(f.engine, pushHangup, .{f.get(.signals)});
    var iterator = try v.Iterator.init(f.engine, f.get(.signals));
    try iterator.finish(registerSignalRows(f, &iterator, roots));
}
fn initialSignals(s: *Scope) !c.JSValue {
    const signals = try v.array(s); try v.index(s, signals, 0, try v.text(s, "SIGTERM"));
    return v.duplicate(s, signals);
}
fn windowsPlatform(s: *Scope) !c.JSValue {
    const platform = try v.own(s, try expression(s.engine, platformValue, .{}));
    return v.boolean(s, try v.eq(s, platform, "win32"));
}
fn platformValue(s: *Scope) !c.JSValue { return v.duplicate(s, try v.get(s, try v.global(s, "process"), "platform")); }
fn pushHangup(s: *Scope, signals: c.JSValue) !void {
    const push = try v.get(s, signals, "push"); _ = try v.call(s, push, signals, &.{try v.text(s, "SIGHUP")});
}
fn registerSignalRows(f: *SignalFrame, iterator: *v.Iterator, roots: []const c.JSValue) !void {
    while (try iterator.next()) |incoming| {
        try f.take(.signal, incoming);
        try f.clear(.handler);
        try f.take(.handler, expression(f.engine, makeSignalHandler, .{ roots[1], f.get(.signal), roots[2] }));
        try statement(f.engine, registerSignal, .{ f.get(.signal), f.get(.handler) });
        try statement(f.engine, registerCleanup, .{ roots[0], f.get(.signal), f.get(.handler) });
    }
}
fn makeSignalHandler(s: *Scope, dispose: c.JSValue, signal: c.JSValue, kill: c.JSValue) !c.JSValue {
    return v.duplicate(s, try syncArrow(s, .signal, "handler", 0, &.{ dispose, signal, kill }));
}
fn registerSignal(s: *Scope, signal: c.JSValue, handler: c.JSValue) !void {
    const process = try v.global(s, "process"); const on = try v.get(s, process, "on");
    _ = try v.call(s, on, process, &.{ signal, handler });
}
fn registerCleanup(s: *Scope, cleanup_binding: c.JSValue, signal: c.JSValue, handler: c.JSValue) !void {
    const handlers = try Frame.read(s, cleanup_binding); const push = try v.get(s, handlers, "push");
    const callback = try syncArrow(s, .signal_cleanup, "", 0, &.{ signal, handler });
    _ = try v.call(s, push, handlers, &.{callback});
}
fn fieldString(s: *Scope, target: c.JSValue, name: [*:0]const u8) !c.JSValue {
    return v.duplicate(s, try v.stringify(s, try v.get(s, target, name)));
}
fn extensionMessage(s: *Scope, error_value: c.JSValue) !c.JSValue {
    const path = try v.own(s, try expression(s.engine, fieldString, .{ error_value, @as([*:0]const u8, "extensionPath") }));
    const prefix = try v.binary(s, 0, try v.text(s, "Extension error ("), path);
    const middle = try v.binary(s, 0, prefix, try v.text(s, "): "));
    const message = try v.own(s, try expression(s.engine, fieldString, .{ error_value, @as([*:0]const u8, "error") }));
    return v.duplicate(s, try v.binary(s, 0, middle, message));
}
fn logExtension(s: *Scope, error_value: c.JSValue) !void {
    const console = try v.global(s, "console"); const log = try v.get(s, console, "error");
    const message = try v.own(s, try expression(s.engine, extensionMessage, .{error_value}));
    _ = try v.call(s, log, console, &.{message});
}
fn serialize(s: *Scope, value: c.JSValue, convert: c.JSValue) !c.JSValue {
    const json = try v.global(s, "JSON"); const stringify = try v.get(s, json, "stringify");
    const event = if (c.JS_IsUndefined(convert)) value else try v.call(s, convert, c.pi_js_undefined(), &.{value});
    return v.duplicate(s, try v.call(s, stringify, json, &.{event}));
}
fn jsonLine(s: *Scope, value: c.JSValue, convert: c.JSValue) !c.JSValue {
    const serialized = try v.own(s, try expression(s.engine, serialize, .{ value, convert }));
    return v.duplicate(s, try v.binary(s, 0, try v.stringify(s, serialized), try v.text(s, "\n")));
}
fn writeJson(s: *Scope, write: c.JSValue, value: c.JSValue, convert: c.JSValue) !void {
    const line = try v.own(s, try expression(s.engine, jsonLine, .{ value, convert }));
    _ = try v.call(s, write, c.pi_js_undefined(), &.{line});
}
fn contentLine(s: *Scope, content: c.JSValue) !c.JSValue {
    const text = try v.own(s, try expression(s.engine, fieldString, .{ content, @as([*:0]const u8, "text") }));
    return v.duplicate(s, try v.binary(s, 0, text, try v.text(s, "\n")));
}
fn writeContent(s: *Scope, write: c.JSValue, content: c.JSValue) !void {
    const line = try v.own(s, try expression(s.engine, contentLine, .{content}));
    _ = try v.call(s, write, c.pi_js_undefined(), &.{line});
}

fn emptyArray(s: *Scope) !c.JSValue { return v.duplicate(s, try v.array(s)); }
fn destructureOptions(s: *Scope, f: *Frame, options: c.JSValue) !void {
    const boxed = try v.guest.toObject(s, options);
    try f.copy(.mode, try v.get(s, boxed, "mode"));
    const messages = try v.get(s, boxed, "messages");
    try f.copy(.messages, if (c.JS_IsUndefined(messages)) try v.array(s) else messages);
    try f.copy(.initial_message, try v.get(s, boxed, "initialMessage"));
    try f.copy(.initial_images, try v.get(s, boxed, "initialImages"));
}
fn makeDispose(s: *Scope, f: *Frame) !c.JSValue {
    return v.duplicate(s, try asyncArrow(s, .dispose, "disposeRuntime", 0, &.{
        try f.capture(s, .disposed, "disposed"), try f.capture(s, .unsubscribe, "unsubscribe"),
        try f.capture(s, .unsubscribe_backpressure, "unsubscribeBackpressure"), try f.capture(s, .runtime_host, "runtimeHost"),
    }));
}
fn makeRegister(s: *Scope, f: *Frame, kill: c.JSValue) !c.JSValue {
    return v.duplicate(s, try syncArrow(s, .register_signals, "registerSignalHandlers", 0, &.{
        try f.capture(s, .signal_cleanup_handlers, "signalCleanupHandlers"), try f.capture(s, .dispose_runtime, "disposeRuntime"), kill,
    }));
}
fn setRebind(s: *Scope, f: *Frame) !void {
    const runtime = try v.own(s, duplicate(s.engine, f.get(.runtime_host)));
    const method = try v.get(s, runtime, "setRebindSession");
    // The lexical const is still uninitialized while this live method runs.
    const callback = try asyncArrow(s, .set_rebind, "", 0, &.{try f.capture(s, .rebind_session, "rebindSession")});
    _ = try v.call(s, method, runtime, &.{callback});
}
fn makeRebind(s: *Scope, f: *Frame, imports: []const c.JSValue) !c.JSValue {
    return v.duplicate(s, try asyncArrow(s, .rebind, "rebindSession", 0, &.{
        try f.capture(s, .runtime_host, "runtimeHost"), try f.capture(s, .session, "session"), try f.capture(s, .mode, "mode"),
        try f.capture(s, .unsubscribe, "unsubscribe"), try f.capture(s, .unsubscribe_backpressure, "unsubscribeBackpressure"),
        imports[0], imports[1], imports[4],
    }));
}
fn initialize(f: *Frame, args: []const c.JSValue, imports: []const c.JSValue) !void {
    try f.copy(.runtime_host, v.arg(args, 0));
    try statement(f.engine, destructureOptions, .{ f, v.arg(args, 1) });
    try f.take(.exit_code, c.JS_NewInt32(f.engine.context, 0));
    try f.take(.session, field(f.engine, f.get(.runtime_host), "session"));
    try f.clear(.unsubscribe); try f.clear(.unsubscribe_backpressure);
    try f.take(.disposed, c.JS_NewBool(f.engine.context, false));
    try f.take(.signal_cleanup_handlers, expression(f.engine, emptyArray, .{}));
    try f.take(.dispose_runtime, expression(f.engine, makeDispose, .{f}));
    try f.take(.register_signal_handlers, expression(f.engine, makeRegister, .{ f, imports[3] }));
    try statement(f.engine, discardFunction, .{ f.get(.register_signal_handlers), @as([]const c.JSValue, &.{}) });
    try statement(f.engine, setRebind, .{f});
    try f.take(.rebind_session, expression(f.engine, makeRebind, .{ f, imports }));
}
fn stage(f: *Frame) Phase {
    var raw: i32 = 0; _ = c.JS_ToInt32(f.engine.context, &raw, f.get(.phase));
    return @enumFromInt(raw);
}
fn setStage(f: *Frame, next: Phase) !void { return f.take(.phase, c.JS_NewInt32(f.engine.context, @intFromEnum(next))); }
fn mainBody(engine: *Engine, _: c.JSValue, args: []const c.JSValue, imports: []const c.JSValue, state: *c.JSValue, completion: af.Completion, input: c.JSValue) !af.Action {
    var s: Scope = .{ .engine = engine };
    const outcome = v.owned.finishAction(&s, advance(&s, args, imports, state, completion, input));
    if (outcome) |action| {
        if (action == .awaited) return action;
    } else |_| {}
    var selected = v.owned.Completion.initAction(engine, outcome);
    if (!c.JS_IsUndefined(state.*)) Frame.from(state.*).close(&selected);
    return selected.finishAction();
}
fn advance(s: *Scope, args: []const c.JSValue, imports: []const c.JSValue, state: *c.JSValue, completion: af.Completion, input: c.JSValue) !af.Action {
    if (completion == .rejected) try enterRejected(s.engine);
    if (completion == .start) {
        const f = try Frame.create(s);
        af.replaceState(s.engine, state, duplicate(s.engine, f.owner));
        try initialize(f, args, imports);
        // Source's try starts only after signal registration and rebind setup.
        try setStage(f, .rebind);
        const result = startBody(f, imports) catch |err| return bodyFailure(f, imports, err);
        return finishBodyAction(f, imports, result);
    }
    const f = Frame.from(state.*);
    switch (stage(f)) {
        .dispose => {
            if (completion == .rejected) return .{ .thrown = duplicate(f.engine, input) };
            try setStage(f, .flush);
            return .{ .awaited = try expression(f.engine, functionCall, .{ imports[2], @as([]const c.JSValue, &.{}) }) };
        },
        .flush => {
            if (completion == .rejected) return .{ .thrown = duplicate(f.engine, input) };
            return if (truthy(f.engine, f.get(.pending_thrown))) .{ .thrown = duplicate(f.engine, f.get(.pending_value)) }
                else .{ .returned = duplicate(f.engine, f.get(.pending_value)) };
        },
        .rebind, .initial, .message => {
            if (completion == .rejected) return bodyData(f, imports, duplicate(f.engine, input));
            const result = resumeBody(f, imports) catch |err| return bodyFailure(f, imports, err);
            return finishBodyAction(f, imports, result);
        },
        .before_try => return error.PrintModeInvalidStage,
    }
}
fn finishBodyAction(f: *Frame, imports: []const c.JSValue, result: af.Action) !af.Action {
    return switch (result) {
        .awaited => result,
        .returned => beginFinally(f, imports, result),
        .thrown => |reason| bodyData(f, imports, reason),
    };
}
fn sessionManager(s: *Scope, f: *Frame) !c.JSValue {
    const session = try v.own(s, duplicate(s.engine, f.get(.session)));
    return v.duplicate(s, try v.get(s, session, "sessionManager"));
}
fn sessionHeader(s: *Scope, f: *Frame) !c.JSValue {
    const manager = try v.own(s, try expression(s.engine, sessionManager, .{f}));
    return v.duplicate(s, try v.invoke(s, manager, "getHeader", &.{}));
}
fn modeIs(f: *Frame, expected: []const u8) !bool {
    var s: Scope = .{ .engine = f.engine };
    return v.eq(&s, f.get(.mode), expected);
}
fn startBody(f: *Frame, imports: []const c.JSValue) !af.Action {
    if (try modeIs(f, "json")) {
        try f.take(.header, expression(f.engine, sessionHeader, .{f}));
        if (truthy(f.engine, f.get(.header)))
            try statement(f.engine, writeJson, .{ imports[0], f.get(.header), c.pi_js_undefined() });
    }
    return .{ .awaited = try expression(f.engine, functionCall, .{ f.get(.rebind_session), @as([]const c.JSValue, &.{}) }) };
}
fn promptInitial(s: *Scope, f: *Frame) !c.JSValue {
    const session = try v.own(s, duplicate(s.engine, f.get(.session)));
    const prompt = try v.get(s, session, "prompt");
    const options = try v.object(s); try v.put(s, options, "images", f.get(.initial_images));
    return v.duplicate(s, try v.call(s, prompt, session, &.{ f.get(.initial_message), options }));
}
fn promptMessage(s: *Scope, f: *Frame) !c.JSValue {
    const session = try v.own(s, duplicate(s.engine, f.get(.session)));
    return v.duplicate(s, try v.invoke(s, session, "prompt", &.{f.get(.message)}));
}
fn initMessageIterator(s: *Scope, f: *Frame) !void {
    const iterator = try v.Iterator.init(s.engine, f.get(.messages));
    var completion = v.owned.Completion.initVoid(s.engine, attachMessageIterator(f, iterator));
    completion.release(iterator.receiver); completion.release(iterator.next_function);
    return completion.finishVoid();
}
fn attachMessageIterator(f: *Frame, iterator: v.Iterator) !void {
    try f.copy(.iterator_receiver, iterator.receiver); try f.copy(.iterator_next, iterator.next_function);
    try f.take(.iterator_active, c.JS_NewBool(f.engine.context, true));
}
fn resumeBody(f: *Frame, imports: []const c.JSValue) !af.Action {
    const current = stage(f);
    if (current == .rebind and truthy(f.engine, f.get(.initial_message))) {
        try setStage(f, .initial);
        return .{ .awaited = try expression(f.engine, promptInitial, .{f}) };
    }
    if (current == .rebind or current == .initial) try statement(f.engine, initMessageIterator, .{f});
    var iterator: v.Iterator = .{ .engine = f.engine, .receiver = f.get(.iterator_receiver), .next_function = f.get(.iterator_next) };
    const incoming = iterator.next() catch |err| {
        // IteratorStep failure is already abrupt, so no IteratorClose is added.
        f.values[@intFromEnum(Locals.iterator_active)] = c.JS_NewBool(f.engine.context, false);
        return err;
    };
    if (incoming) |message| {
        try f.take(.message, message);
        try setStage(f, .message);
        return .{ .awaited = try expression(f.engine, promptMessage, .{f}) };
    }
    try retireIterator(f);
    if (try modeIs(f, "text")) try printText(f, imports[0]);
    return .{ .returned = duplicate(f.engine, f.get(.exit_code)) };
}
fn retireIterator(f: *Frame) !void {
    var completion = v.owned.Completion.initVoid(f.engine, {});
    f.retire(.iterator_receiver, &completion); f.retire(.iterator_next, &completion);
    f.values[@intFromEnum(Locals.iterator_active)] = c.JS_NewBool(f.engine.context, false);
    return completion.finishVoid();
}
fn closeBody(s: *Scope, receiver: c.JSValue, original: c.JSValue) !af.Action {
    _ = try v.own(s, original);
    closeCall(s, receiver) catch |err| { _ = try v.own(s, try caught(s.engine, err)); };
    return .{ .thrown = v.duplicate(s, original) };
}
fn closeCall(s: *Scope, receiver: c.JSValue) !void {
    const method = try v.get(s, receiver, "return");
    if (!v.nullish(method)) _ = try v.call(s, method, receiver, &.{});
    // IteratorClose with an original Throw ignores a normal result's type.
}
fn closeBodyIterator(f: *Frame, reason: c.JSValue) !af.Action {
    var s: Scope = .{ .engine = f.engine };
    const result: anyerror!af.Action = if (truthy(f.engine, f.get(.iterator_active)))
        closeBody(&s, f.get(.iterator_receiver), reason)
    else .{ .thrown = reason };
    var completion = v.owned.Completion.initAction(f.engine, result);
    completion.releaseScope(&s);
    f.retire(.iterator_receiver, &completion); f.retire(.iterator_next, &completion);
    f.values[@intFromEnum(Locals.iterator_active)] = c.JS_NewBool(f.engine.context, false);
    return completion.finishAction();
}
fn bodyFailure(f: *Frame, imports: []const c.JSValue, err: anyerror) !af.Action {
    return bodyData(f, imports, try caught(f.engine, err));
}
fn bodyData(f: *Frame, imports: []const c.JSValue, original: c.JSValue) !af.Action {
    const chosen = try closeBodyIterator(f, original);
    const reason = switch (chosen) { .thrown => |value| value, else => unreachable };
    try f.take(.caught_error, reason);
    statement(f.engine, logCaught, .{f.get(.caught_error)}) catch |err|
        return beginFinally(f, imports, .{ .thrown = try caught(f.engine, err) });
    return beginFinally(f, imports, .{ .returned = c.JS_NewInt32(f.engine.context, 1) });
}
fn instanceError(s: *Scope, reason: c.JSValue) !c.JSValue {
    const constructor = try v.global(s, "Error");
    var boundary: v.guest.Boundary = .{ .engine = s.engine }; try boundary.begin();
    const result = c.JS_IsInstanceOf(s.engine.context, reason, constructor);
    try boundary.finishStatus(if (result < 0) -1 else 0);
    return v.boolean(s, result != 0);
}
fn caughtMessage(s: *Scope, reason: c.JSValue) !c.JSValue {
    if (truthy(s.engine, try expression(s.engine, instanceError, .{reason}))) return v.duplicate(s, try v.get(s, reason, "message"));
    const string = try v.global(s, "String");
    return v.duplicate(s, try v.call(s, string, c.pi_js_undefined(), &.{reason}));
}
fn logCaught(s: *Scope, reason: c.JSValue) !void {
    const console = try v.global(s, "console"); const log = try v.get(s, console, "error");
    const message = try v.own(s, try expression(s.engine, caughtMessage, .{reason}));
    _ = try v.call(s, log, console, &.{message});
}
fn beginFinally(f: *Frame, imports: []const c.JSValue, pending: af.Action) !af.Action {
    switch (pending) {
        .returned => |value| {
            try f.take(.pending_value, value);
            try f.take(.pending_thrown, c.JS_NewBool(f.engine.context, false));
        },
        .thrown => |value| {
            try f.take(.pending_value, value);
            try f.take(.pending_thrown, c.JS_NewBool(f.engine.context, true));
        },
        .awaited => unreachable,
    }
    var iterator = try v.Iterator.init(f.engine, f.get(.signal_cleanup_handlers));
    try iterator.finish(cleanupRows(f, &iterator));
    try setStage(f, .dispose);
    _ = imports;
    return .{ .awaited = try expression(f.engine, functionCall, .{ f.get(.dispose_runtime), @as([]const c.JSValue, &.{}) }) };
}
fn cleanupRows(f: *Frame, iterator: *v.Iterator) !void {
    while (try iterator.next()) |incoming| {
        try f.take(.cleanup, incoming);
        try statement(f.engine, discardFunction, .{ f.get(.cleanup), @as([]const c.JSValue, &.{}) });
    }
}
fn sessionState(s: *Scope, f: *Frame) !c.JSValue {
    const session = try v.own(s, duplicate(s.engine, f.get(.session)));
    return v.duplicate(s, try v.get(s, session, "state"));
}
fn messageLength(s: *Scope, state: c.JSValue) !c.JSValue {
    const messages = try v.get(s, state, "messages");
    return v.duplicate(s, try v.get(s, messages, "length"));
}
fn messagePosition(s: *Scope, state: c.JSValue) !c.JSValue {
    const length = try v.own(s, try expression(s.engine, messageLength, .{state}));
    return v.duplicate(s, try v.binary(s, 1, length, v.number(s, 1)));
}
fn lastMessage(s: *Scope, state: c.JSValue) !c.JSValue {
    const messages = try v.get(s, state, "messages");
    const index = try v.own(s, try expression(s.engine, messagePosition, .{state}));
    return v.duplicate(s, try v.key(s, messages, index));
}
fn assistantRole(s: *Scope, value: c.JSValue) !c.JSValue {
    return v.boolean(s, if (v.nullish(value)) false else try v.eq(s, try v.get(s, value, "role"), "assistant"));
}
fn printText(f: *Frame, write: c.JSValue) !void {
    try f.take(.state, expression(f.engine, sessionState, .{f}));
    try f.take(.last_message, expression(f.engine, lastMessage, .{f.get(.state)}));
    if (!truthy(f.engine, try expression(f.engine, assistantRole, .{f.get(.last_message)}))) return;
    try f.copy(.assistant_message, f.get(.last_message));
    const assistant = f.get(.assistant_message);
    if (try fieldEqual(f.engine, assistant, "stopReason", "error") or try fieldEqual(f.engine, assistant, "stopReason", "aborted")) {
        try statement(f.engine, logAssistantError, .{assistant});
        try f.take(.exit_code, c.JS_NewInt32(f.engine.context, 1));
    } else {
        const contents = try field(f.engine, assistant, "content");
        var iterator = try v.Iterator.initOwned(f.engine, contents);
        try iterator.finish(contentRows(f, &iterator, write));
        if (try fieldEqual(f.engine, assistant, "stopReason", "length")) {
            try statement(f.engine, logLiteral, .{@as([]const u8, "Response was truncated: the model reached its output token limit.")});
            try f.take(.exit_code, c.JS_NewInt32(f.engine.context, 1));
        }
    }
}
fn contentRows(f: *Frame, iterator: *v.Iterator, write: c.JSValue) !void {
    while (try iterator.next()) |incoming| {
        try f.take(.content, incoming);
        if (try fieldEqual(f.engine, f.get(.content), "type", "text"))
            try statement(f.engine, writeContent, .{ write, f.get(.content) });
    }
}
fn assistantErrorMessage(s: *Scope, assistant: c.JSValue) !c.JSValue {
    const message = try v.get(s, assistant, "errorMessage");
    if (v.truthy(s, message)) return v.duplicate(s, message);
    const stop = try v.own(s, try expression(s.engine, fieldString, .{ assistant, @as([*:0]const u8, "stopReason") }));
    return v.duplicate(s, try v.binary(s, 0, try v.text(s, "Request "), stop));
}
fn logAssistantError(s: *Scope, assistant: c.JSValue) !void {
    const console = try v.global(s, "console"); const log = try v.get(s, console, "error");
    const message = try v.own(s, try expression(s.engine, assistantErrorMessage, .{assistant}));
    _ = try v.call(s, log, console, &.{message});
}
fn logLiteral(s: *Scope, message: []const u8) !void {
    const console = try v.global(s, "console"); const log = try v.get(s, console, "error");
    _ = try v.call(s, log, console, &.{try v.text(s, message)});
}
pub fn create(engine: *Engine, inputs: Inputs) !c.JSValue {
    try engine.checkNativeEntry();
    if (engine.native_module_values.get(key)) |cached| return duplicate(engine, cached);
    const candidate = try expression(engine, createBody, .{inputs});
    if (engine.native_module_values.get(key)) |cached| {
        var completion = v.owned.Completion.initValue(engine, duplicate(engine, cached));
        completion.release(candidate); return completion.finishValue();
    }
    engine.native_module_values.ensureUnusedCapacity(engine.gpa, 1) catch |err| {
        var completion = v.owned.Completion.initVoid(engine, err);
        completion.release(candidate); try completion.finishVoid(); unreachable;
    };
    const result = duplicate(engine, candidate);
    engine.native_module_values.putAssumeCapacity(key, candidate);
    return result;
}
fn createBody(s: *Scope, inputs: Inputs) !c.JSValue {
    const json = try v.own(s, try @import("native_public_json_event.zig").create(s.engine));
    const imports = [_]c.JSValue{
        inputs.output.write_raw_stdout, inputs.output.wait_for_raw_stdout_backpressure, inputs.output.flush_raw_stdout,
        try v.get(s, inputs.shell, "killTrackedDetachedChildren"), try v.get(s, json, "toJsonEvent"),
    };
    const exports = try v.object(s);
    var boundary: v.guest.Boundary = .{ .engine = s.engine }; try boundary.begin();
    const run = try boundary.finishValue(s, af.createResumable(s.engine, "runPrintMode", 2, mainBody, &imports));
    try v.put(s, exports, "runPrintMode", run);
    return v.duplicate(s, exports);
}
