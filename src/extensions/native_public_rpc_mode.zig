//! Actual c268 headless RPC mode, composed from genuine application owners.
//! Command, UI, input and shutdown closures share the Source lexical bindings.
const h = @import("native_public_rpc_state.zig");
const v = h.v;
const c = h.c;
const Engine = h.Engine;
const Scope = h.Scope;
const af = h.af;
const Frame = h.Frame;
const guard = @import("native_sdk_output_guard.zig");
const ui = @import("native_public_rpc_ui.zig");
const commands = @import("native_public_rpc_commands.zig");
const key = "\x00native.public.rpc-mode";
pub const Inputs = struct { output: guard.Exports, shell: c.JSValue, theme: c.JSValue };
// Actual retained imports: takeover, write, wait, flush, kill, event, serialize,
// attach, UUID, original Theme.
const Import = enum(usize) { takeover, write, wait, flush, kill, event, serialize, attach, uuid, theme };
fn imported(roots: []const c.JSValue, comptime name: Import) c.JSValue { return roots[@intFromEnum(name)]; }
const Async = enum { set_rebind, rebind, fork, navigate, reload, backpressure, check_shutdown };
const Simple = enum { new_session, switch_session };
const Sync = enum { output, success, failure, shutdown_request, extension_error, event, wait_idle, on_end, on_line, signal, signal_cleanup };

pub fn create(engine: *Engine, inputs: Inputs) !c.JSValue {
    try engine.checkNativeEntry();
    if (engine.native_module_values.get(key)) |cached| return h.duplicate(engine, cached);
    const candidate = try h.expression(engine, createBody, .{inputs});
    if (engine.native_module_values.get(key)) |cached| {
        var completion = v.owned.Completion.initValue(engine, h.duplicate(engine, cached));
        completion.release(candidate); return completion.finishValue();
    }
    engine.native_module_values.ensureUnusedCapacity(engine.gpa, 1) catch |err| {
        var completion = v.owned.Completion.initVoid(engine, err); completion.release(candidate);
        try completion.finishVoid(); unreachable;
    };
    const result = h.duplicate(engine, candidate);
    engine.native_module_values.putAssumeCapacity(key, candidate);
    return result;
}
fn createBody(s: *Scope, inputs: Inputs) !c.JSValue {
    const json = try v.own(s, try @import("native_public_json_event.zig").create(s.engine));
    const lines = try v.own(s, try @import("native_public_rpc_jsonl.zig").create(s.engine));
    const uuid = try v.own(s, try @import("native_node_crypto_uuid_binding.zig").create(s.engine));
    const roots = [_]c.JSValue{
        inputs.output.take_over_stdout, inputs.output.write_raw_stdout, inputs.output.wait_for_raw_stdout_backpressure,
        inputs.output.flush_raw_stdout, try v.get(s, inputs.shell, "killTrackedDetachedChildren"),
        try v.get(s, json, "toJsonEvent"), try v.get(s, lines, "serializeJsonLine"), try v.get(s, lines, "attachJsonlLineReader"), uuid, inputs.theme,
    };
    const result = try v.object(s);
    var boundary: v.guest.Boundary = .{ .engine = s.engine }; try boundary.begin();
    const run = try boundary.finishValue(s, af.createResumable(s.engine, "runRpcMode", 1, main, &roots));
    try v.put(s, result, "runRpcMode", run);
    return v.duplicate(s, result);
}
fn syncArrow(s: *Scope, comptime kind: Sync, name: [*:0]const u8, length: c_int, roots: []const c.JSValue) !c.JSValue {
    const Adapter = struct {
        fn call(engine: *Engine, receiver: c.JSValue, args: []const c.JSValue, captured: []const c.JSValue) !c.JSValue {
            return h.expression(engine, syncBody, .{ kind, receiver, args, captured });
        }
    };
    return v.arrow(s, name, length, Adapter.call, roots);
}
fn asyncArrow(s: *Scope, comptime kind: Async, name: [*:0]const u8, length: c_int, roots: []const c.JSValue) !c.JSValue {
    const Adapter = struct {
        fn call(engine: *Engine, _: c.JSValue, args: []const c.JSValue, captured: []const c.JSValue, _: *c.JSValue, completion: af.Completion, input: c.JSValue) !af.Action {
            var scope: Scope = .{ .engine = engine };
            return v.owned.finishAction(&scope, asyncBody(&scope, kind, args, captured, completion, input));
        }
    };
    return h.asyncArrow(s, name, length, Adapter.call, roots);
}
fn simpleAsync(s: *Scope, comptime kind: Simple, name: [*:0]const u8, length: c_int, roots: []const c.JSValue) !c.JSValue {
    const Adapter = struct {
        fn call(engine: *Engine, _: c.JSValue, args: []const c.JSValue, captured: []const c.JSValue) !c.JSValue {
            return h.expression(engine, h.bindingMethod, .{ captured[0], @as([*:0]const u8, if (kind == .new_session) "newSession" else "switchSession"),
                @as([]const c.JSValue, if (kind == .new_session) &.{v.arg(args, 0)} else &.{ v.arg(args, 0), v.arg(args, 1) }) });
        }
    };
    return h.simpleAsync(s, name, length, Adapter.call, roots);
}
fn main(engine: *Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue, state: *c.JSValue, completion: af.Completion, input: c.JSValue) !af.Action {
    var s: Scope = .{ .engine = engine };
    const outcome = v.owned.finishAction(&s, mainAdvance(&s, args, roots, state, completion, input));
    if (outcome) |action| { if (action == .awaited) return action; } else |_| {}
    var selected = v.owned.Completion.initAction(engine, outcome);
    if (!c.JS_IsUndefined(state.*)) Frame.from(state.*).close(&selected);
    return selected.finishAction();
}
fn mainAdvance(s: *Scope, args: []const c.JSValue, roots: []const c.JSValue, state: *c.JSValue, completion: af.Completion, input: c.JSValue) !af.Action {
    if (completion == .rejected) { try h.enterRejected(s.engine); return .{ .thrown = v.duplicate(s, input) }; }
    if (completion == .start) {
        const f = try Frame.create(s); af.replaceState(s.engine, state, v.duplicate(s, f.owner));
        try f.copy(.runtime_host, v.arg(args, 0));
        // Function declarations exist before the first executable statement.
        try h.statement(s.engine, hoisted, .{ f, roots });
        try h.statement(s.engine, h.discardFunction, .{ imported(roots, .takeover), @as([]const c.JSValue, &.{}) });
        try f.take(.session, h.fieldOwned(s.engine, f.get(.runtime_host), "session"));
        try f.clear(.unsubscribe); try f.clear(.unsubscribe_backpressure);
        try h.statement(s.engine, initializeCallbacks, .{ f, roots });
        try f.take(.pending_requests, h.expression(s.engine, newMap, .{}));
        try f.take(.shutdown_requested, v.boolean(s, false)); try f.take(.shutting_down, v.boolean(s, false));
        try f.take(.signal_cleanup_handlers, h.expression(s.engine, h.emptyArray, .{}));
        try h.statement(s.engine, initializeMode, .{ f, roots });
        return .{ .awaited = try h.expression(s.engine, h.functionCall, .{ f.get(.rebind_session), @as([]const c.JSValue, &.{}) }) };
    }
    const f = Frame.from(state.*);
    try h.statement(s.engine, h.discardFunction, .{ f.get(.register_signals), @as([]const c.JSValue, &.{}) });
    try h.statement(s.engine, initializeInput, .{ f, roots });
    return .{ .returned = try h.expression(s.engine, pendingForever, .{}) };
}
fn hoisted(s: *Scope, f: *Frame, roots: []const c.JSValue) !void {
    try f.take(.create_dialog, v.duplicate(s, try ui.dialogFunction(s,
        try f.capture(s, .pending_requests, "pendingExtensionRequests"), try f.capture(s, .output, "output"), imported(roots, .uuid))));
    const shutdown_roots = [_]c.JSValue{
        try f.capture(s, .shutting_down, "shuttingDown"), try f.capture(s, .signal_cleanup_handlers, "signalCleanupHandlers"),
        try f.capture(s, .unsubscribe, "unsubscribe"), try f.capture(s, .unsubscribe_backpressure, "unsubscribeBackpressure"),
        try f.capture(s, .runtime_host, "runtimeHost"), try f.capture(s, .detach_input, "detachInput"), imported(roots, .flush),
    };
    var boundary: v.guest.Boundary = .{ .engine = s.engine }; try boundary.begin();
    try f.take(.shutdown, v.duplicate(s, try boundary.finishValue(s, af.createResumable(s.engine, "shutdown", 0, shutdown, &shutdown_roots))));
    const check_roots = [_]c.JSValue{ try f.capture(s, .shutdown_requested, "shutdownRequested"), try f.capture(s, .shutdown, "shutdown") };
    var check_boundary: v.guest.Boundary = .{ .engine = s.engine }; try check_boundary.begin();
    const Checker = struct {
        fn call(engine: *Engine, _: c.JSValue, args: []const c.JSValue, captured: []const c.JSValue, _: *c.JSValue, completion: af.Completion, input: c.JSValue) !af.Action {
            var local: Scope = .{ .engine = engine };
            return v.owned.finishAction(&local, asyncBody(&local, .check_shutdown, args, captured, completion, input));
        }
    };
    try f.take(.check_shutdown, v.duplicate(s, try check_boundary.finishValue(s, af.createResumable(s.engine, "checkShutdownRequested", 0, Checker.call,
        &check_roots))));
}
fn initializeCallbacks(s: *Scope, f: *Frame, roots: []const c.JSValue) !void {
    try f.take(.output, v.duplicate(s, try syncArrow(s, .output, "output", 1, &.{ imported(roots, .write), imported(roots, .serialize) })));
    try f.take(.success, v.duplicate(s, try syncArrow(s, .success, "success", 3, &.{})));
    try f.take(.failure, v.duplicate(s, try syncArrow(s, .failure, "error", 3, &.{})));
}
fn newMap(s: *Scope) !c.JSValue { return v.duplicate(s, try v.construct(s, try v.global(s, "Map"), &.{})); }
fn initializeMode(s: *Scope, f: *Frame, roots: []const c.JSValue) !void {
    try f.take(.create_ui, v.duplicate(s, try ui.contextFunction(s, &.{
        try f.capture(s, .create_dialog, "createDialogPromise"), try f.capture(s, .output, "output"),
        try f.capture(s, .pending_requests, "pendingExtensionRequests"), imported(roots, .uuid), imported(roots, .theme),
    })));
    try h.statement(s.engine, setRebind, .{f});
    try f.take(.rebind_session, v.duplicate(s, try asyncArrow(s, .rebind, "rebindSession", 0, &.{
        try f.capture(s, .runtime_host, "runtimeHost"), try f.capture(s, .session, "session"), try f.capture(s, .create_ui, "createExtensionUIContext"),
        try f.capture(s, .unsubscribe, "unsubscribe"), try f.capture(s, .unsubscribe_backpressure, "unsubscribeBackpressure"),
        try f.capture(s, .output, "output"), try f.capture(s, .shutdown_requested, "shutdownRequested"),
        try f.capture(s, .check_shutdown, "checkShutdownRequested"), imported(roots, .wait), imported(roots, .event),
    })));
    try f.take(.register_signals, v.duplicate(s, try v.arrow(s, "registerSignalHandlers", 0, registerSignals, &.{
        try f.capture(s, .signal_cleanup_handlers, "signalCleanupHandlers"), imported(roots, .kill), try f.capture(s, .shutdown, "shutdown"),
    })));
}
fn setRebind(s: *Scope, f: *Frame) !void {
    const host = try v.own(s, v.duplicate(s, f.get(.runtime_host))); const method = try v.get(s, host, "setRebindSession");
    const callback = try asyncArrow(s, .set_rebind, "", 0, &.{try f.capture(s, .rebind_session, "rebindSession")});
    _ = try v.call(s, method, host, &.{callback});
}
fn asyncBody(s: *Scope, comptime kind: Async, args: []const c.JSValue, roots: []const c.JSValue, completion: af.Completion, input: c.JSValue) !af.Action {
    if (completion == .rejected) { try h.enterRejected(s.engine); return .{ .thrown = v.duplicate(s, input) }; }
    if (completion == .fulfilled) {
        if (kind == .fork or kind == .navigate) {
            const result = try v.object(s); try v.put(s, result, "cancelled", try h.fieldValue(s, input, "cancelled"));
            return .{ .returned = v.duplicate(s, result) };
        }
        if (kind == .rebind) try rebindSubscriptions(s.engine, roots);
        return .{ .returned = c.pi_js_undefined() };
    }
    const result = switch (kind) {
        .set_rebind => try h.expression(s.engine, h.bindingCall, .{ roots[0], @as([]const c.JSValue, &.{}) }),
        .rebind => blk: {
            try Frame.assign(roots[1], h.expression(s.engine, h.bindingField, .{ roots[0], @as([*:0]const u8, "session") }));
            break :blk try h.expression(s.engine, bindExtensions, .{roots});
        },
        .fork => try h.expression(s.engine, h.bindingMethod, .{ roots[0], @as([*:0]const u8, "fork"), @as([]const c.JSValue, &.{ v.arg(args, 0), v.arg(args, 1) }) }),
        .navigate => try h.expression(s.engine, navigate, .{ roots[0], v.arg(args, 0), v.arg(args, 1) }),
        .reload => try h.expression(s.engine, h.bindingMethod, .{ roots[0], @as([*:0]const u8, "reload"), @as([]const c.JSValue, &.{}) }),
        .backpressure => try h.expression(s.engine, h.functionCall, .{ roots[0], @as([]const c.JSValue, &.{}) }),
        .check_shutdown => blk: {
            if (!try h.bindingTruthy(s.engine, roots[0])) return .{ .returned = c.pi_js_undefined() };
            break :blk try h.expression(s.engine, h.bindingCall, .{ roots[1], @as([]const c.JSValue, &.{}) });
        },
    };
    return .{ .awaited = result };
}
fn navigate(s: *Scope, session_cell: c.JSValue, target: c.JSValue, options: c.JSValue) !c.JSValue {
    const session = try Frame.read(s, session_cell); const method = try v.get(s, session, "navigateTree"); const actual = try v.object(s);
    inline for (.{ "summarize", "customInstructions", "replaceInstructions", "label" }) |name|
        try v.put(s, actual, name, try h.optionalField(s, options, name));
    return v.duplicate(s, try v.call(s, method, session, &.{ target, actual }));
}
fn bindExtensions(s: *Scope, roots: []const c.JSValue) !c.JSValue {
    const session = try Frame.read(s, roots[1]); const method = try v.get(s, session, "bindExtensions"); const options = try v.object(s);
    try v.put(s, options, "uiContext", try v.own(s, try h.expression(s.engine, h.bindingCall, .{ roots[2], @as([]const c.JSValue, &.{}) })));
    try v.put(s, options, "mode", try v.text(s, "rpc"));
    const actions = try v.object(s);
    try v.put(s, actions, "waitForIdle", try syncArrow(s, .wait_idle, "waitForIdle", 0, &.{roots[1]}));
    try v.put(s, actions, "newSession", try simpleAsync(s, .new_session, "newSession", 1, &.{roots[0]}));
    try v.put(s, actions, "fork", try asyncArrow(s, .fork, "fork", 2, &.{roots[0]}));
    try v.put(s, actions, "navigateTree", try asyncArrow(s, .navigate, "navigateTree", 2, &.{roots[1]}));
    try v.put(s, actions, "switchSession", try simpleAsync(s, .switch_session, "switchSession", 2, &.{roots[0]}));
    try v.put(s, actions, "reload", try asyncArrow(s, .reload, "reload", 0, &.{roots[1]}));
    try v.put(s, options, "commandContextActions", actions);
    try v.put(s, options, "shutdownHandler", try syncArrow(s, .shutdown_request, "shutdownHandler", 0, &.{roots[6]}));
    try v.put(s, options, "onError", try syncArrow(s, .extension_error, "onError", 1, &.{roots[5]}));
    return v.duplicate(s, try v.call(s, method, session, &.{options}));
}
fn rebindSubscriptions(engine: *Engine, roots: []const c.JSValue) !void {
    try h.statement(engine, h.optionalBinding, .{roots[3]}); try h.statement(engine, h.optionalBinding, .{roots[4]});
    try Frame.assign(roots[3], h.expression(engine, subscribeEvents, .{roots}));
    try Frame.assign(roots[4], h.expression(engine, subscribeBackpressure, .{ roots[1], roots[8] }));
}
fn subscribeEvents(s: *Scope, roots: []const c.JSValue) !c.JSValue {
    const session = try Frame.read(s, roots[1]); const method = try v.get(s, session, "subscribe");
    const callback = try syncArrow(s, .event, "", 1, &.{ roots[5], roots[7], roots[9] });
    return v.duplicate(s, try v.call(s, method, session, &.{callback}));
}
fn subscribeBackpressure(s: *Scope, session_cell: c.JSValue, wait: c.JSValue) !c.JSValue {
    const agent = try v.own(s, try h.expression(s.engine, h.bindingField, .{ session_cell, @as([*:0]const u8, "agent") }));
    const method = try v.get(s, agent, "subscribe"); const callback = try asyncArrow(s, .backpressure, "", 0, &.{wait});
    return v.duplicate(s, try v.call(s, method, agent, &.{callback}));
}
fn syncBody(s: *Scope, comptime kind: Sync, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    switch (kind) {
        .output => {
            const encoded = try v.own(s, try h.expression(s.engine, h.functionCall, .{ roots[1], @as([]const c.JSValue, &.{v.arg(args, 0)}) }));
            _ = try v.call(s, roots[0], c.pi_js_undefined(), &.{encoded});
        },
        .success, .failure => {
            const result = try v.object(s); try v.put(s, result, "id", v.arg(args, 0)); try v.put(s, result, "type", try v.text(s, "response"));
            try v.put(s, result, "command", v.arg(args, 1)); try v.put(s, result, "success", v.boolean(s, kind == .success));
            if (kind == .failure) try v.put(s, result, "error", v.arg(args, 2))
            else if (!c.JS_IsUndefined(v.arg(args, 2))) try v.put(s, result, "data", v.arg(args, 2));
            return v.duplicate(s, result);
        },
        .shutdown_request => try Frame.assign(roots[0], v.boolean(s, true)),
        .extension_error => {
            const output = try Frame.read(s, roots[0]); const result = try v.object(s); try v.put(s, result, "type", try v.text(s, "extension_error"));
            inline for (.{ "extensionPath", "event", "error" }) |name| try v.put(s, result, name, try h.fieldValue(s, v.arg(args, 0), name));
            _ = try v.call(s, output, c.pi_js_undefined(), &.{result});
        },
        .event => {
            try h.statement(s.engine, outputEvent, .{ roots[0], roots[2], v.arg(args, 0) });
            if (try h.fieldEqual(s.engine, v.arg(args, 0), "type", "agent_settled"))
                try h.statement(s.engine, h.discardBinding, .{ roots[1], @as([]const c.JSValue, &.{}) });
        },
        .wait_idle => return h.bindingMethod(s, roots[0], "waitForIdle", &.{}),
        .on_end => try h.statement(s.engine, h.discardBinding, .{ roots[0], @as([]const c.JSValue, &.{}) }),
        .on_line => try h.statement(s.engine, h.discardBinding, .{ roots[0], @as([]const c.JSValue, &.{v.arg(args, 0)}) }),
        .signal => {
            try h.statement(s.engine, h.discardFunction, .{ roots[1], @as([]const c.JSValue, &.{}) });
            try h.statement(s.engine, shutdownSignal, .{ roots[2], roots[0] });
        },
        .signal_cleanup => {
            const process = try v.global(s, "process"); const method = try v.get(s, process, "off");
            return v.duplicate(s, try v.call(s, method, process, &.{ roots[0], roots[1] }));
        },
    }
    return c.pi_js_undefined();
}
fn outputEvent(s: *Scope, output_cell: c.JSValue, project: c.JSValue, event: c.JSValue) !void {
    const output = try Frame.read(s, output_cell);
    const data = try v.own(s, try h.expression(s.engine, h.functionCall, .{ project, @as([]const c.JSValue, &.{event}) }));
    _ = try v.call(s, output, c.pi_js_undefined(), &.{data});
}
const Signal = h.lexical.Frame(enum { signals, signal, handler });
fn registerSignals(engine: *Engine, _: c.JSValue, _: []const c.JSValue, roots: []const c.JSValue) !c.JSValue { return h.expression(engine, signalsScoped, .{roots}); }
fn signalsScoped(s: *Scope, roots: []const c.JSValue) !c.JSValue {
    const f = try Signal.create(s);
    var completion = v.owned.Completion.initVoid(s.engine, signalsBody(f, roots)); f.close(&completion); try completion.finishVoid();
    return c.pi_js_undefined();
}
fn signalsBody(f: *Signal, roots: []const c.JSValue) !void {
    try f.take(.signals, h.expression(f.engine, signalArray, .{}));
    if (!h.truthy(f.engine, try h.expression(f.engine, isWindows, .{}))) try h.statement(f.engine, appendHangup, .{f.get(.signals)});
    var iterator = try v.Iterator.init(f.engine, f.get(.signals));
    try iterator.finish(signalRows(f, &iterator, roots));
}
fn signalArray(s: *Scope) !c.JSValue { const result = try v.array(s); try v.index(s, result, 0, try v.text(s, "SIGTERM")); return v.duplicate(s, result); }
fn processPlatform(s: *Scope) !c.JSValue { return v.duplicate(s, try v.get(s, try v.global(s, "process"), "platform")); }
fn isWindows(s: *Scope) !c.JSValue { return v.boolean(s, try v.eq(s, try v.own(s, try h.expression(s.engine, processPlatform, .{})), "win32")); }
fn appendHangup(s: *Scope, signals: c.JSValue) !void { const method = try v.get(s, signals, "push"); _ = try v.call(s, method, signals, &.{try v.text(s, "SIGHUP")}); }
fn signalRows(f: *Signal, iterator: *v.Iterator, roots: []const c.JSValue) !void {
    while (try iterator.next()) |incoming| {
        try f.take(.signal, incoming); try f.clear(.handler);
        try f.take(.handler, h.expression(f.engine, signalHandler, .{ f.get(.signal), roots[1], roots[2] }));
        try h.statement(f.engine, registerSignal, .{ f.get(.signal), f.get(.handler) });
        try h.statement(f.engine, signalCleanup, .{ roots[0], f.get(.signal), f.get(.handler) });
    }
}
fn signalHandler(s: *Scope, signal: c.JSValue, kill: c.JSValue, shutdown_cell: c.JSValue) !c.JSValue {
    return v.duplicate(s, try syncArrow(s, .signal, "handler", 0, &.{ signal, kill, shutdown_cell }));
}
fn registerSignal(s: *Scope, signal: c.JSValue, handler: c.JSValue) !void {
    const process = try v.global(s, "process"); const method = try v.get(s, process, "on"); _ = try v.call(s, method, process, &.{ signal, handler });
}
fn signalCleanup(s: *Scope, cleanup_cell: c.JSValue, signal: c.JSValue, handler: c.JSValue) !void {
    const list = try Frame.read(s, cleanup_cell); const push = try v.get(s, list, "push");
    const callback = try syncArrow(s, .signal_cleanup, "", 0, &.{ signal, handler });
    _ = try v.call(s, push, list, &.{callback});
}
fn shutdownSignal(s: *Scope, cell: c.JSValue, signal: c.JSValue) !void {
    const callable = try Frame.read(s, cell); const code = v.number(s, if (try v.eq(s, signal, "SIGHUP")) 129 else 143);
    _ = try v.call(s, callable, c.pi_js_undefined(), &.{ code, signal });
}
const Shutdown = h.lexical.Frame(enum { exit_code, signal, cleanup, phase });
fn shutdown(engine: *Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue, state: *c.JSValue, completion: af.Completion, input: c.JSValue) !af.Action {
    var s: Scope = .{ .engine = engine };
    const outcome = v.owned.finishAction(&s, shutdownAdvance(&s, args, roots, state, completion, input));
    if (outcome) |action| { if (action == .awaited) return action; } else |_| {}
    var selected = v.owned.Completion.initAction(engine, outcome);
    if (!c.JS_IsUndefined(state.*)) Shutdown.from(state.*).close(&selected);
    return selected.finishAction();
}
fn shutdownAdvance(s: *Scope, args: []const c.JSValue, roots: []const c.JSValue, state: *c.JSValue, completion: af.Completion, input: c.JSValue) !af.Action {
    if (completion == .rejected) { try h.enterRejected(s.engine); return .{ .thrown = v.duplicate(s, input) }; }
    if (completion == .start) {
        const f = try Shutdown.create(s); af.replaceState(s.engine, state, v.duplicate(s, f.owner));
        try f.copy(.exit_code, if (c.JS_IsUndefined(v.arg(args, 0))) v.number(s, 0) else v.arg(args, 0)); try f.copy(.signal, v.arg(args, 1));
        if (try h.bindingTruthy(s.engine, roots[0])) try h.statement(s.engine, processExit, .{f.get(.exit_code)});
        try Frame.assign(roots[0], v.boolean(s, true));
        const handlers = try h.expression(s.engine, bindingValue, .{roots[1]});
        var iterator = try v.Iterator.initOwned(s.engine, handlers);
        try iterator.finish(shutdownRows(f, &iterator));
        try h.statement(s.engine, h.optionalBinding, .{roots[2]}); try h.statement(s.engine, h.optionalBinding, .{roots[3]});
        try f.take(.phase, v.number(s, 0));
        return .{ .awaited = try h.expression(s.engine, h.bindingMethod, .{ roots[4], @as([*:0]const u8, "dispose"), @as([]const c.JSValue, &.{}) }) };
    }
    const f = Shutdown.from(state.*);
    if (c.JS_IsStrictEqual(s.engine.context, f.get(.phase), v.number(s, 0))) {
        try h.statement(s.engine, h.discardBinding, .{ roots[5], @as([]const c.JSValue, &.{}) });
        try h.statement(s.engine, pauseInput, .{});
        if (!try v.eq(s, f.get(.signal), "SIGTERM")) {
            try f.take(.phase, v.number(s, 1));
            return .{ .awaited = try h.expression(s.engine, h.functionCall, .{ roots[6], @as([]const c.JSValue, &.{}) }) };
        }
    }
    try h.statement(s.engine, processExit, .{f.get(.exit_code)});
    return .{ .returned = c.pi_js_undefined() };
}
fn bindingValue(s: *Scope, cell: c.JSValue) !c.JSValue { return v.duplicate(s, try Frame.read(s, cell)); }
fn shutdownRows(f: *Shutdown, iterator: *v.Iterator) !void {
    while (try iterator.next()) |incoming| { try f.take(.cleanup, incoming); try h.statement(f.engine, h.discardFunction, .{ f.get(.cleanup), @as([]const c.JSValue, &.{}) }); }
}
fn processExit(s: *Scope, code: c.JSValue) !void { const process = try v.global(s, "process"); const method = try v.get(s, process, "exit"); _ = try v.call(s, method, process, &.{code}); }
fn processInput(s: *Scope) !c.JSValue { return v.duplicate(s, try v.get(s, try v.global(s, "process"), "stdin")); }
fn pauseInput(s: *Scope) !void {
    const input = try v.own(s, try h.expression(s.engine, processInput, .{})); const method = try v.get(s, input, "pause");
    _ = try v.call(s, method, input, &.{});
}

fn initializeInput(s: *Scope, f: *Frame, roots: []const c.JSValue) !void {
    try f.take(.handle_command, v.duplicate(s, try commands.create(s, &.{
        try f.capture(s, .session, "session"), try f.capture(s, .runtime_host, "runtimeHost"), try f.capture(s, .rebind_session, "rebindSession"),
        try f.capture(s, .success, "success"), try f.capture(s, .failure, "error"), try f.capture(s, .output, "output"),
    })));
    try f.take(.detach_input, v.duplicate(s, try v.arrow(s, "detachInput", 0, h.emptyCallback, &.{})));
    try f.take(.handle_input, v.duplicate(s, try h.asyncArrow(s, "handleInputLine", 1, handleInput, &.{
        try f.capture(s, .output, "output"), try f.capture(s, .failure, "error"), imported(roots, .wait),
        try f.capture(s, .pending_requests, "pendingExtensionRequests"), try f.capture(s, .handle_command, "handleCommand"),
        try f.capture(s, .check_shutdown, "checkShutdownRequested"),
    })));
    try f.take(.on_input_end, v.duplicate(s, try syncArrow(s, .on_end, "onInputEnd", 0, &.{try f.capture(s, .shutdown, "shutdown")})));
    try h.statement(s.engine, registerEnd, .{f.get(.on_input_end)});
    try f.take(.detach_input, attachInput(s.engine, f, imported(roots, .attach)));
}
fn registerEnd(s: *Scope, callback: c.JSValue) !void {
    const input = try v.own(s, try h.expression(s.engine, processInput, .{}));
    const method = try v.get(s, input, "on"); _ = try v.call(s, method, input, &.{ try v.text(s, "end"), callback });
}
const Attachment = h.lexical.Frame(enum { detach_jsonl });
fn attachInput(engine: *Engine, main_frame: *Frame, attach: c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine };
    const f = Attachment.create(&s) catch |err| return v.owned.finishValue(&s, err);
    const keeper = h.duplicate(engine, f.owner);
    var selected = v.owned.Completion.initValue(engine, attachBody(f, main_frame, attach));
    selected.releaseScope(&s); f.close(&selected); selected.release(keeper); return selected.finishValue();
}
fn attachBody(f: *Attachment, main_frame: *Frame, attach: c.JSValue) !c.JSValue {
    try f.take(.detach_jsonl, h.expression(f.engine, attachLines, .{ main_frame, attach }));
    return h.expression(f.engine, makeDetach, .{ f, main_frame });
}
fn attachLines(s: *Scope, f: *Frame, attach: c.JSValue) !c.JSValue {
    const input = try v.own(s, try h.expression(s.engine, processInput, .{}));
    const callback = try syncArrow(s, .on_line, "", 1, &.{try f.capture(s, .handle_input, "handleInputLine")});
    return v.duplicate(s, try v.call(s, attach, c.pi_js_undefined(), &.{ input, callback }));
}
fn makeDetach(s: *Scope, f: *Attachment, main_frame: *Frame) !c.JSValue {
    return v.duplicate(s, try v.arrow(s, "", 0, detach, &.{ try f.capture(s, .detach_jsonl, "detachJsonl"), try main_frame.capture(s, .on_input_end, "onInputEnd") }));
}
fn detach(engine: *Engine, _: c.JSValue, _: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    try h.statement(engine, detachLines, .{roots[0]}); try h.statement(engine, detachEnd, .{roots[1]}); return c.pi_js_undefined();
}
fn detachLines(s: *Scope, cell: c.JSValue) !void { _ = try v.call(s, try Attachment.read(s, cell), c.pi_js_undefined(), &.{}); }
fn detachEnd(s: *Scope, cell: c.JSValue) !void {
    const input = try v.own(s, try h.expression(s.engine, processInput, .{})); const method = try v.get(s, input, "off"); const name = try v.text(s, "end");
    _ = try v.call(s, method, input, &.{ name, try Frame.read(s, cell) });
}
fn pendingForever(s: *Scope) !c.JSValue {
    const constructor = try v.global(s, "Promise"); const executor = try v.arrow(s, "", 0, h.emptyCallback, &.{});
    return v.duplicate(s, try v.construct(s, constructor, &.{executor}));
}
const InputFrame = h.lexical.Frame(enum { line, parsed, parse_error, response, pending, command, command_response, command_error, phase });
const InputPhase = enum(i32) { parse_wait, command, output_wait, shutdown_wait, error_wait };
fn inputPhase(f: *InputFrame) InputPhase { var tag: i32 = 0; _ = c.JS_ToInt32(f.engine.context, &tag, f.get(.phase)); return @enumFromInt(tag); }
fn setInputPhase(f: *InputFrame, phase: InputPhase) !void { try f.take(.phase, c.JS_NewInt32(f.engine.context, @intFromEnum(phase))); }
fn attempt(engine: *Engine, comptime body: anytype, args: anytype) !af.Action {
    var s: Scope = .{ .engine = engine };
    var completion = v.owned.Completion.initValue(engine, @call(.auto, body, .{&s} ++ args));
    completion.releaseScope(&s); return completion.finishAction();
}
fn handleInput(engine: *Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue, state: *c.JSValue, completion: af.Completion, input: c.JSValue) !af.Action {
    var s: Scope = .{ .engine = engine };
    const outcome = v.owned.finishAction(&s, inputAdvance(&s, args, roots, state, completion, input));
    if (outcome) |action| { if (action == .awaited) return action; } else |_| {}
    var selected = v.owned.Completion.initAction(engine, outcome);
    if (!c.JS_IsUndefined(state.*)) InputFrame.from(state.*).close(&selected);
    return selected.finishAction();
}
fn inputAdvance(s: *Scope, args: []const c.JSValue, roots: []const c.JSValue, state: *c.JSValue, completion: af.Completion, input: c.JSValue) !af.Action {
    if (completion == .rejected) try h.enterRejected(s.engine);
    if (completion == .start) {
        const f = try InputFrame.create(s); af.replaceState(s.engine, state, v.duplicate(s, f.owner));
        try f.copy(.line, v.arg(args, 0)); try f.clear(.parsed);
        switch (try attempt(s.engine, parseLine, .{f.get(.line)})) {
            .returned => |value| try f.take(.parsed, value),
            .thrown => |reason| {
                try f.take(.parse_error, reason);
                try h.statement(s.engine, outputParseFailure, .{ f, roots });
                try setInputPhase(f, .parse_wait);
                return .{ .awaited = try h.expression(s.engine, h.functionCall, .{ roots[2], @as([]const c.JSValue, &.{}) }) };
            },
            .awaited => unreachable,
        }
        if (h.truthy(s.engine, try h.expression(s.engine, isUiResponse, .{f.get(.parsed)}))) {
            try f.copy(.response, f.get(.parsed));
            try f.take(.pending, h.expression(s.engine, getUiPending, .{ f, roots[3] }));
            if (h.truthy(s.engine, f.get(.pending))) {
                try h.statement(s.engine, deleteUiPending, .{ f, roots[3] });
                try h.statement(s.engine, resolveUiPending, .{f});
            }
            return .{ .returned = c.pi_js_undefined() };
        }
        try f.copy(.command, f.get(.parsed)); try setInputPhase(f, .command);
        return commandStep(f, roots, .start, c.pi_js_undefined());
    }
    const f = InputFrame.from(state.*);
    if (inputPhase(f) == .parse_wait or inputPhase(f) == .error_wait) return if (completion == .rejected)
        .{ .thrown = v.duplicate(s, input) } else .{ .returned = c.pi_js_undefined() };
    return commandStep(f, roots, completion, input);
}
fn parseLine(s: *Scope, line: c.JSValue) !c.JSValue {
    const json = try v.global(s, "JSON"); const method = try v.get(s, json, "parse");
    return v.duplicate(s, try v.call(s, method, json, &.{line}));
}
fn isUiResponse(s: *Scope, parsed: c.JSValue) !c.JSValue {
    if (!c.JS_IsObject(parsed) or c.JS_IsFunction(s.engine.context, parsed)) return v.boolean(s, false);
    if (!try h.has(s, parsed, "type")) return v.boolean(s, false);
    return v.boolean(s, try v.eq(s, try h.fieldValue(s, parsed, "type"), "extension_ui_response"));
}
fn getUiPending(s: *Scope, f: *InputFrame, pending_cell: c.JSValue) !c.JSValue {
    const pending = try Frame.read(s, pending_cell); const method = try v.get(s, pending, "get");
    return v.duplicate(s, try v.call(s, method, pending, &.{try h.fieldValue(s, f.get(.response), "id")}));
}
fn deleteUiPending(s: *Scope, f: *InputFrame, pending_cell: c.JSValue) !void {
    const pending = try Frame.read(s, pending_cell); const method = try v.get(s, pending, "delete");
    _ = try v.call(s, method, pending, &.{try h.fieldValue(s, f.get(.response), "id")});
}
fn resolveUiPending(s: *Scope, f: *InputFrame) !void { _ = try v.invoke(s, f.get(.pending), "resolve", &.{f.get(.response)}); }
fn parseMessage(s: *Scope, reason: c.JSValue) !c.JSValue {
    const raw = try v.own(s, try h.expression(s.engine, h.caughtMessage, .{reason}));
    return v.duplicate(s, try v.stringify(s, raw));
}
fn parseDescription(s: *Scope, reason: c.JSValue) !c.JSValue {
    const text = try v.own(s, try h.expression(s.engine, parseMessage, .{reason}));
    return v.duplicate(s, try v.binary(s, 0, try v.text(s, "Failed to parse command: "), text));
}
fn parseFailure(s: *Scope, f: *InputFrame, roots: []const c.JSValue) !c.JSValue {
    const failure = try Frame.read(s, roots[1]); const name = try v.text(s, "parse");
    const message = try v.own(s, try h.expression(s.engine, parseDescription, .{f.get(.parse_error)}));
    return v.duplicate(s, try v.call(s, failure, c.pi_js_undefined(), &.{ c.pi_js_undefined(), name, message }));
}
fn outputParseFailure(s: *Scope, f: *InputFrame, roots: []const c.JSValue) !void {
    const output = try Frame.read(s, roots[0]); const response = try v.own(s, try h.expression(s.engine, parseFailure, .{ f, roots }));
    _ = try v.call(s, output, c.pi_js_undefined(), &.{response});
}
fn commandStep(f: *InputFrame, roots: []const c.JSValue, completion: af.Completion, input: c.JSValue) !af.Action {
    var s: Scope = .{ .engine = f.engine };
    const outcome = if (completion == .rejected) af.Action{ .thrown = h.duplicate(f.engine, input) }
        else try v.owned.finishAction(&s, commandAdvance(f, roots, completion, input));
    return switch (outcome) {
        .returned, .awaited => outcome,
        .thrown => |reason| blk: {
            try f.take(.command_error, reason);
            try h.statement(f.engine, outputCommandFailure, .{ f, roots });
            try setInputPhase(f, .error_wait);
            break :blk .{ .awaited = try h.expression(f.engine, h.functionCall, .{ roots[2], @as([]const c.JSValue, &.{}) }) };
        },
    };
}
fn commandAdvance(f: *InputFrame, roots: []const c.JSValue, completion: af.Completion, input: c.JSValue) !af.Action {
    if (completion == .start) return .{ .awaited = try h.expression(f.engine, h.bindingCall, .{ roots[4], @as([]const c.JSValue, &.{f.get(.command)}) }) };
    switch (inputPhase(f)) {
        .command => {
            try f.copy(.command_response, input);
            if (h.truthy(f.engine, f.get(.command_response))) {
                try h.statement(f.engine, h.discardBinding, .{ roots[0], @as([]const c.JSValue, &.{f.get(.command_response)}) });
                try setInputPhase(f, .output_wait);
                return .{ .awaited = try h.expression(f.engine, h.functionCall, .{ roots[2], @as([]const c.JSValue, &.{}) }) };
            }
        },
        .output_wait => {},
        .shutdown_wait => return .{ .returned = c.pi_js_undefined() },
        else => unreachable,
    }
    try setInputPhase(f, .shutdown_wait);
    return .{ .awaited = try h.expression(f.engine, h.bindingCall, .{ roots[5], @as([]const c.JSValue, &.{}) }) };
}
fn commandFailure(s: *Scope, f: *InputFrame, roots: []const c.JSValue) !c.JSValue {
    const failure = try Frame.read(s, roots[1]); const id = try h.fieldValue(s, f.get(.command), "id");
    const command = try h.fieldValue(s, f.get(.command), "type");
    const message = try v.own(s, try h.expression(s.engine, h.caughtMessage, .{f.get(.command_error)}));
    return v.duplicate(s, try v.call(s, failure, c.pi_js_undefined(), &.{ id, command, message }));
}
fn outputCommandFailure(s: *Scope, f: *InputFrame, roots: []const c.JSValue) !void {
    const output = try Frame.read(s, roots[0]); const response = try v.own(s, try h.expression(s.engine, commandFailure, .{ f, roots }));
    _ = try v.call(s, output, c.pi_js_undefined(), &.{response});
}
