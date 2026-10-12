//! One native durable CodeMode invocation. Retained JS cells own every async
//! continuation; guest execution uses the actual controlled native sandbox.
const std = @import("std");
const em = @import("engine.zig");
const js = @import("native_js_values.zig");
const vm = @import("native_values.zig");
const Scope = @import("native_sdk_prompt_scope.zig").Scope;
const awaiter = @import("native_durable_await.zig");
const journal = @import("native_durable_codemode_journal.zig");
const mapping = @import("native_durable_codemode_outcome.zig");
const c = em.c;
const Stage = enum(c_int) { initialized, fingerprint, result, formatted, completed, batch, tool, global, decided, earlier_snapshot, earlier_task, closed, model_waiter, model_ready };
const Event = enum(c_int) { started, call, idle, abort };
fn number(engine: *em.Engine, value: c.JSValue) !f64 {
    var result: f64 = 0;
    if (c.JS_ToFloat64(engine.context, &result, value) < 0) return js.capture(engine);
    return result;
}
fn n(scope: *Scope, state: c.JSValue, key: [*:0]const u8) !f64 {
    return number(scope.engine, try scope.get(state, key));
}
fn flag(scope: *Scope, state: c.JSValue, key: [*:0]const u8) !bool {
    return scope.truthy(try scope.get(state, key));
}
fn setFlag(scope: *Scope, state: c.JSValue, key: [*:0]const u8, value: bool) !void {
    try scope.put(state, key, c.pi_js_bool(scope.engine.context, @intFromBool(value)));
}
fn setNumber(scope: *Scope, state: c.JSValue, key: [*:0]const u8, value: f64) !void {
    try scope.put(state, key, c.JS_NewFloat64(scope.engine.context, value));
}
fn item(scope: *Scope, array: c.JSValue, index: usize) !c.JSValue {
    return scope.own(try scope.engine.checked(c.JS_GetPropertyUint32(scope.engine.context, array, @intCast(index))));
}
fn append(scope: *Scope, array: c.JSValue, value: c.JSValue) !void {
    _ = try scope.invoke(array, "push", &.{value});
}
fn is(scope: *Scope, value: c.JSValue, text: []const u8) !bool {
    return scope.equal(value, try scope.text(text));
}
fn intrinsics(scope: *Scope, state: c.JSValue) !awaiter.Intrinsics {
    const docs = try scope.get(state, "documents");
    return .{ .constructor = try scope.get(docs, "promiseConstructor"), .resolve = try scope.get(docs, "promiseResolve"), .then_function = try scope.get(docs, "promiseThen") };
}
fn wait(scope: *Scope, state: c.JSValue, promise: c.JSValue, stage: Stage) !c.JSValue {
    var captured = try intrinsics(scope, state);
    return scope.own(try awaiter.continueWith(advance, scope.engine, &captured, state, promise, @intFromEnum(stage)));
}
fn stopped(scope: *Scope, state: c.JSValue) !bool {
    if (!c.JS_IsUndefined(try scope.get(state, "ended")) or !c.JS_IsUndefined(try scope.get(state, "failure"))) return true;
    const run = try scope.get(state, "run");
    return !c.JS_IsUndefined(run) and try flag(scope, run, "finished");
}
fn abort(scope: *Scope, state: c.JSValue, reason: c.JSValue) !void {
    _ = try scope.invoke(try scope.get(state, "controller"), "abort", &.{reason});
}
fn cleanup(scope: *Scope, state: c.JSValue) !void {
    const signal = try scope.get(try scope.get(state, "context"), "abortSignal");
    const handler = try scope.get(state, "abortHandler");
    if (!c.JS_IsUndefined(signal) and !c.JS_IsUndefined(handler)) {
        _ = try scope.invoke(signal, "removeEventListener", &.{ try scope.text("abort"), handler });
        try scope.put(state, "abortHandler", c.pi_js_undefined());
    }
}
fn errorMessage(scope: *Scope, reason: c.JSValue) !c.JSValue {
    if (c.JS_IsObject(reason)) {
        const message = try scope.get(reason, "message");
        if (c.JS_IsString(message)) return message;
    }
    return scope.stringify(reason);
}
fn concat(scope: *Scope, values: []const c.JSValue) !c.JSValue {
    var result = try scope.text("");
    for (values) |value| result = try scope.concat(result, value);
    return result;
}
fn describe(scope: *Scope, call: c.JSValue) !c.JSValue {
    const encoded = try scope.invoke(try scope.global("JSON"), "stringify", &.{try scope.get(call, "args")});
    return concat(scope, &.{ try scope.text(if (try is(scope, try scope.get(call, "target"), "tool")) "tools." else ""), try scope.get(call, "name"), try scope.text("("), if (c.JS_IsUndefined(encoded)) try scope.text("") else encoded, try scope.text(")") });
}
fn changed(scope: *Scope, call: c.JSValue, suffix: c.JSValue) !c.JSValue {
    return concat(scope, &.{ try scope.text("call "), try scope.stringify(try scope.get(call, "id")), try scope.text(" is "), try describe(scope, call), suffix });
}
fn failure(scope: *Scope, state: c.JSValue, reason: c.JSValue) !void {
    if (!c.JS_IsUndefined(try scope.get(state, "failure"))) return;
    try scope.put(state, "failure", reason);
    try abort(scope, state, reason);
}
fn errorResult(scope: *Scope, message: c.JSValue) !c.JSValue {
    const result = try scope.object();
    const output = try scope.array();
    const text = try scope.object();
    try scope.put(text, "type", try scope.text("text"));
    try scope.put(text, "text", message);
    try append(scope, output, text);
    try scope.put(result, "output", output);
    try setFlag(scope, result, "isError", true);
    return result;
}
fn decided(scope: *Scope, state: c.JSValue, message: c.JSValue) !void {
    if (try stopped(scope, state)) return;
    const result = try errorResult(scope, message);
    try scope.put(state, "ended", result);
    const stored = try scope.own(try js.spread(scope.engine, result));
    try scope.put(stored, "details", try details(scope, state));
    const pending = try scope.own(try journal.decide(scope.engine, try scope.get(state, "documents"), try scope.get(state, "api"), try scope.get(state, "context"), stored));
    _ = try wait(scope, state, pending, .decided);
}
fn diverge(scope: *Scope, state: c.JSValue, message: c.JSValue) !void {
    try decided(scope, state, try scope.concat(try scope.text("The script took a different path when resumed after a restart: "), message));
}
fn callback(scope: *Scope, state: c.JSValue, kind: Event) !c.JSValue {
    var captures = [_]c.JSValue{state};
    return scope.own(try scope.engine.checked(c.JS_NewCFunctionData2(scope.engine.context, event, "", 2, @intFromEnum(kind), captures.len, &captures)));
}
/// The caller supplies Source-shaped start data and the actual sandbox. Public
/// tool declaration/discovery construction is a separate boundary.
pub fn execute(engine: *em.Engine, docs: c.JSValue, api: c.JSValue, context: c.JSValue, sandbox: c.JSValue, code: c.JSValue, draft: c.JSValue, globals: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const state = try scope.object();
    inline for (.{ .{ "documents", docs }, .{ "api", api }, .{ "context", context }, .{ "sandbox", sandbox }, .{ "code", code }, .{ "globals", globals } }) |field| try scope.put(state, field[0], field[1]);
    const controller = try scope.own(try js.builtin(engine, "AbortController", &.{}));
    try scope.put(state, "controller", controller);
    inline for (.{ "held", "waiting", "queue", "releaseCalls", "modelWaiters" }) |key| try scope.put(state, key, try scope.array());
    inline for (.{ "acks", "ready", "replayIndex", "rows" }) |key| try scope.put(state, key, try scope.own(try js.builtin(engine, "Map", &.{})));
    inline for (.{ "journalLength", "nextReplayed", "issued", "durableIssued", "releaseIndex", "modelCalls", "generatedImages" }) |key| try setNumber(&scope, state, key, 0);
    const pending = try scope.own(try journal.initialize(engine, docs, api, context, draft));
    return c.JS_DupValue(engine.context, try wait(&scope, state, pending, .initialized));
}
fn event(context: ?*c.JSContext, _: c.JSValue, argc: c_int, args: [*c]c.JSValue, raw: c_int, captures: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    handle(&scope, captures[0], @enumFromInt(raw), args[0..@intCast(argc)]) catch |err| {
        const reason = if (err == error.JavaScriptException and engine.captured_exception != null) c.JS_DupValue(engine.context, engine.captured_exception.?) else js.builtin(engine, "Error", &.{scope.text(@errorName(err)) catch return c.pi_js_undefined()}) catch return c.pi_js_undefined();
        defer engine.freeValue(reason);
        failure(&scope, captures[0], reason) catch {};
    };
    return c.pi_js_undefined();
}
fn handle(scope: *Scope, state: c.JSValue, kind: Event, args: []const c.JSValue) !void {
    if (kind == .abort) {
        try abort(scope, state, try scope.get(try scope.get(try scope.get(state, "context"), "abortSignal"), "reason"));
        const resolve = try scope.get(state, "closedResolve");
        if (!c.JS_IsUndefined(resolve)) _ = try scope.call(resolve, c.pi_js_undefined(), &.{});
        return;
    }
    if (try stopped(scope, state)) return;
    switch (kind) {
        .started => {
            const recorded = try scope.get(try scope.get(state, "start"), "fingerprint");
            if (!c.JS_IsUndefined(recorded)) {
                if (!scope.equal(recorded, args[0])) {
                    try decided(scope, state, try scope.concat(try scope.concat(try scope.concat(try scope.text("The script cannot resume: the sandbox changed since it started ("), recorded), try scope.text(" -> ")), try scope.concat(args[0], try scope.text(")."))));
                    return;
                }
                try openGate(scope, state);
            } else {
                const pending = try scope.own(try journal.fingerprint(scope.engine, try scope.get(state, "documents"), try scope.get(state, "api"), try scope.get(state, "context"), args[0]));
                _ = try wait(scope, state, pending, .fingerprint);
            }
        },
        .call => {
            var call = args[0];
            if (try is(scope, try scope.get(call, "target"), "global")) {
                const name = try scope.get(call, "name");
                if (try is(scope, name, "models.classify") or try is(scope, name, "models.generateImages")) {
                    const mapped = try scope.object();
                    const given = try scope.get(call, "args");
                    const list = if (c.JS_IsArray(given)) given else try scope.array();
                    const model = try item(scope, list, 0);
                    const context = try item(scope, list, 1);
                    const parameters = try scope.object();
                    try scope.put(mapped, "id", try scope.get(call, "id"));
                    try scope.put(mapped, "target", try scope.text("tool"));
                    try scope.put(mapped, "name", try scope.concat(try scope.text("pi.codemode."), name));
                    try scope.put(parameters, "model", if (c.JS_IsUndefined(model) or c.JS_IsNull(model)) c.pi_js_null() else model);
                    try scope.put(parameters, "context", if (c.JS_IsUndefined(context) or c.JS_IsNull(context)) c.pi_js_null() else context);
                    try scope.put(mapped, "args", parameters);
                    call = mapped;
                }
            }
            const id = try scope.get(call, "id");
            if (try is(scope, try scope.get(call, "target"), "tool")) {
                const rows = try scope.get(state, "rows");
                if (!scope.truthy(try scope.invoke(rows, "has", &.{id}))) {
                    const row = try scope.object();
                    try scope.put(row, "id", id);
                    const name = try scope.get(call, "name");
                    try scope.put(row, "name", if (scope.truthy(try scope.invoke(name, "startsWith", &.{try scope.text("pi.codemode.")}))) try scope.invoke(name, "slice", &.{c.JS_NewInt32(scope.engine.context, "pi.codemode.".len)}) else name);
                    const given = try scope.get(call, "args");
                    const encoded = if (c.JS_IsUndefined(given)) try scope.text("") else try scope.invoke(try scope.global("JSON"), "stringify", &.{given});
                    try scope.put(row, "args", try cut(scope, encoded, 200));
                    try scope.put(row, "status", try scope.text("running"));
                    _ = try scope.invoke(rows, "set", &.{ id, row });
                }
            }
            try setNumber(scope, state, "issued", @max(try n(scope, state, "issued"), try number(scope.engine, id)));
            if (try flag(scope, state, "replaying")) {
                const index = try scope.invoke(try scope.get(state, "replayIndex"), "get", &.{id});
                if (!c.JS_IsUndefined(index)) {
                    const entry = try item(scope, try scope.get(state, "replayed"), @intFromFloat(try number(scope.engine, index)));
                    const global = try scope.get(entry, "global");
                    if (!c.JS_IsUndefined(global)) {
                        if (!try is(scope, try scope.get(call, "target"), "global") or !scope.equal(try scope.get(call, "name"), try scope.get(global, "name")) or !try sameJson(scope, try scope.get(call, "args"), try scope.get(global, "args"))) {
                            try diverge(scope, state, try changed(scope, call, try scope.concat(try scope.text(", but was a call to "), try scope.get(global, "name"))));
                            return;
                        }
                        _ = try scope.invoke(try scope.get(state, "ready"), "set", &.{ id, try scope.get(global, "outcome") });
                        try deliverReplayed(scope, state);
                    } else if (!try is(scope, try scope.get(call, "target"), "tool")) {
                        try diverge(scope, state, try changed(scope, call, try scope.text(", but was a tool call")));
                    } else {
                        try scope.put(call, "replay", c.pi_js_bool(scope.engine.context, 1));
                        if (try flag(scope, state, "gate")) try launch(scope, state, call) else try append(scope, try scope.get(state, "held"), call);
                    }
                    return;
                }
            }
            try append(scope, try scope.get(state, if (try flag(scope, state, "released")) "waiting" else "held"), call);
            try launchCovered(scope, state);
        },
        .idle => {
            const seq: usize = @intFromFloat(try number(scope.engine, args[0]));
            const issued = try number(scope.engine, args[1]);
            const replayed = try scope.get(state, "replayed");
            const length = try vm.length(scope.engine, replayed);
            if (try flag(scope, state, "rerun") and seq <= length) {
                const recorded = if (seq == 0) try scope.get(state, "firstIssued") else try scope.get(try item(scope, replayed, seq - 1), "issuedAfter");
                if (!c.JS_IsUndefined(recorded) and try number(scope.engine, recorded) != issued) {
                    const message = if (seq == 0) try concat(scope, &.{ try scope.text("its first run made "), try scope.stringify(args[1]), try scope.text(" calls, where it had made "), try scope.stringify(recorded) }) else try concat(scope, &.{ try scope.text("after result "), try scope.stringify(args[0]), try scope.text(" it had made "), try scope.stringify(args[1]), try scope.text(" calls, where it had made "), try scope.stringify(recorded) });
                    try diverge(scope, state, message);
                    return;
                }
            }
            _ = try scope.invoke(try scope.get(state, "acks"), "set", &.{ args[0], args[1] });
            if (!try flag(scope, state, "replaying")) {
                if (seq == 0 and try flag(scope, state, "rerun")) try release(scope, state);
                if (@as(f64, @floatFromInt(seq)) == try n(scope, state, "journalLength")) try pump(scope, state);
            } else if (@as(f64, @floatFromInt(seq)) == try n(scope, state, "nextReplayed")) {
                if (seq < length) {
                    if (try n(scope, try item(scope, replayed, seq), "id") > issued) try diverge(scope, state, try concat(scope, &.{ try scope.text("it waits without making call "), try scope.stringify(try scope.get(try item(scope, replayed, seq), "id")), try scope.text(", which it made before") }));
                } else {
                    try setFlag(scope, state, "replaying", false);
                    try pump(scope, state);
                    try release(scope, state);
                }
            }
        },
        .abort => unreachable,
    }
}
fn openGate(scope: *Scope, state: c.JSValue) !void {
    try setFlag(scope, state, "gate", true);
    const held = try scope.get(state, "held");
    const keep = try scope.array();
    for (0..try vm.length(scope.engine, held)) |index| {
        const call = try item(scope, held, index);
        if (try flag(scope, call, "replay")) try launch(scope, state, call) else try append(scope, keep, call);
    }
    try scope.put(state, "held", keep);
    if (try flag(scope, state, "replaying")) try deliverReplayed(scope, state) else if (!try flag(scope, state, "rerun")) try release(scope, state);
}
fn deliverReplayed(scope: *Scope, state: c.JSValue) !void {
    if (!try flag(scope, state, "gate") or c.JS_IsUndefined(try scope.get(state, "run"))) return;
    const entries = try scope.get(state, "replayed");
    const ready = try scope.get(state, "ready");
    var next: usize = @intFromFloat(try n(scope, state, "nextReplayed"));
    while (next < try vm.length(scope.engine, entries) and !try stopped(scope, state)) {
        const entry = try item(scope, entries, next);
        const id = try scope.get(entry, "id");
        const outcome = try scope.invoke(ready, "get", &.{id});
        if (try number(scope.engine, id) > try n(scope, state, "issued") or c.JS_IsUndefined(outcome)) return;
        _ = try scope.invoke(ready, "delete", &.{id});
        next += 1;
        try setNumber(scope, state, "nextReplayed", @floatFromInt(next));
        _ = try scope.invoke(try scope.get(state, "run"), "deliver", &.{ c.JS_NewFloat64(scope.engine.context, @floatFromInt(next)), try scope.get(entry, "at"), id, outcome });
    }
}
fn release(scope: *Scope, state: c.JSValue) !void {
    if (!try flag(scope, state, "gate") or try flag(scope, state, "released") or try flag(scope, state, "releasing") or try stopped(scope, state)) return;
    try setFlag(scope, state, "releasing", true);
    try scope.put(state, "releaseCalls", try scope.invoke(try scope.get(state, "held"), "splice", &.{c.JS_NewInt32(scope.engine.context, 0)}));
    try setNumber(scope, state, "releaseIndex", 0);
    try checkEarlier(scope, state);
}
fn checkEarlier(scope: *Scope, state: c.JSValue) !void {
    const calls = try scope.get(state, "releaseCalls");
    const index: usize = @intFromFloat(try n(scope, state, "releaseIndex"));
    if (try stopped(scope, state)) return;
    if (try flag(scope, state, "rerun") and index < try vm.length(scope.engine, calls)) {
        const call = try item(scope, calls, index);
        const key = try scope.concat(try scope.text("c"), try scope.stringify(try scope.get(call, "id")));
        const exports = scope.engine.native_module_values.get("@earendil-works/pi-durable") orelse return error.DurableModuleMissing;
        const api = try scope.get(state, "api");
        const pending = try scope.invoke(api, "snapshot", &.{ try scope.get(exports, "NestedCallDoc"), try scope.get(api, "taskId"), key, try scope.get(state, "context") });
        _ = try wait(scope, state, pending, .earlier_snapshot);
        return;
    }
    const waiting = try scope.get(state, "waiting");
    for (0..try vm.length(scope.engine, calls)) |i| try append(scope, waiting, try item(scope, calls, i));
    const held = try scope.invoke(try scope.get(state, "held"), "splice", &.{c.JS_NewInt32(scope.engine.context, 0)});
    for (0..try vm.length(scope.engine, held)) |i| try append(scope, waiting, try item(scope, held, i));
    try setFlag(scope, state, "released", true);
    try setFlag(scope, state, "releasing", false);
    try launchCovered(scope, state);
}
fn launchCovered(scope: *Scope, state: c.JSValue) !void {
    if (!try flag(scope, state, "released") or try stopped(scope, state)) return;
    const waiting = try scope.get(state, "waiting");
    const pending = try scope.array();
    const covered = try scope.array();
    for (0..try vm.length(scope.engine, waiting)) |i| {
        const call = try item(scope, waiting, i);
        try append(scope, if (try n(scope, call, "id") <= try n(scope, state, "durableIssued")) covered else pending, call);
    }
    try scope.put(state, "waiting", pending);
    for (0..try vm.length(scope.engine, covered)) |i| try launch(scope, state, try item(scope, covered, i));
}
fn launch(scope: *Scope, state: c.JSValue, call: c.JSValue) !void {
    if (try stopped(scope, state)) return;
    const operation = try scope.object();
    try scope.put(operation, "parent", state);
    try scope.put(operation, "call", call);
    try scope.put(operation, "documents", try scope.get(state, "documents"));
    const args = try scope.get(call, "args");
    const api = try scope.get(state, "api");
    const context = try scope.get(state, "context");
    if (try is(scope, try scope.get(call, "target"), "tool")) {
        if (scope.truthy(try scope.invoke(try scope.get(call, "name"), "startsWith", &.{try scope.text("pi.codemode.")}))) {
            try setFlag(scope, operation, "modelSlot", true);
            if (try n(scope, state, "modelCalls") >= 4) {
                var functions: [2]c.JSValue = undefined;
                const promise = try scope.own(try scope.engine.checked(c.JS_NewPromiseCapability(scope.engine.context, &functions)));
                defer scope.engine.freeValue(functions[0]);
                defer scope.engine.freeValue(functions[1]);
                try append(scope, try scope.get(state, "modelWaiters"), functions[0]);
                _ = try wait(scope, operation, promise, .model_waiter);
            } else {
                try setNumber(scope, state, "modelCalls", try n(scope, state, "modelCalls") + 1);
                _ = try wait(scope, operation, c.pi_js_undefined(), .model_ready);
            }
            return;
        }
        const options = try scope.object();
        try scope.put(options, "key", try scope.concat(try scope.text("c"), try scope.stringify(try scope.get(call, "id"))));
        _ = try wait(scope, operation, try scope.invoke(api, "executeTool", &.{ try scope.get(call, "name"), if (c.JS_IsUndefined(args) or c.JS_IsNull(args)) try scope.object() else args, context, options }), .tool);
    } else {
        if (try @import("native_durable_codemode_catalog.zig").isCatalog(scope.engine, try scope.get(call, "name"))) {
            const pending = @import("native_durable_codemode_catalog.zig").invoke(scope.engine, try scope.get(state, "documents"), try scope.get(api, "models"), context, call) catch |err| {
                if (err != error.JavaScriptException or scope.engine.captured_exception == null) return err;
                const signal = try scope.get(context, "abortSignal");
                if (!c.JS_IsUndefined(signal) and try flag(scope, signal, "aborted")) {
                    try failure(scope, state, scope.engine.captured_exception.?);
                    return;
                }
                const outcome = try scope.object();
                try setFlag(scope, outcome, "ok", false);
                try scope.put(outcome, "message", try errorMessage(scope, scope.engine.captured_exception.?));
                try finished(scope, operation, outcome);
                return;
            };
            _ = try wait(scope, operation, try scope.own(pending), .global);
            return;
        }
        if (try @import("native_durable_codemode_discovery.zig").isDiscovery(scope.engine, try scope.get(call, "name"))) {
            const value = @import("native_durable_codemode_discovery.zig").invoke(scope.engine, try scope.get(state, "start"), call) catch |err| {
                if (err != error.JavaScriptException or scope.engine.captured_exception == null) return err;
                const outcome = try scope.object();
                try setFlag(scope, outcome, "ok", false);
                try scope.put(outcome, "message", try errorMessage(scope, scope.engine.captured_exception.?));
                try finished(scope, operation, outcome);
                return;
            };
            _ = try wait(scope, operation, try scope.own(value), .global);
            return;
        }
        const globals = try scope.get(state, "globals");
        for (0..try vm.length(scope.engine, globals)) |i| {
            const global = try item(scope, globals, i);
            if (scope.equal(try scope.get(global, "name"), try scope.get(call, "name"))) {
                const pending = scope.invoke(global, "execute", &.{ args, api, context }) catch |err| {
                    if (err != error.JavaScriptException or scope.engine.captured_exception == null) return err;
                    const signal = try scope.get(context, "abortSignal");
                    if (!c.JS_IsUndefined(signal) and try flag(scope, signal, "aborted")) {
                        try failure(scope, state, scope.engine.captured_exception.?);
                        return;
                    }
                    const outcome = try scope.object();
                    try setFlag(scope, outcome, "ok", false);
                    try scope.put(outcome, "message", try errorMessage(scope, scope.engine.captured_exception.?));
                    try finished(scope, operation, outcome);
                    return;
                };
                _ = try wait(scope, operation, pending, .global);
                return;
            }
        }
        const outcome = try scope.object();
        try setFlag(scope, outcome, "ok", false);
        try scope.put(outcome, "message", try scope.concat(try scope.text("Unknown global "), try scope.get(call, "name")));
        try finished(scope, operation, outcome);
    }
}
fn releaseModelSlot(scope: *Scope, operation: c.JSValue) !void {
    if (!try flag(scope, operation, "modelSlot")) return;
    try setFlag(scope, operation, "modelSlot", false);
    const state = try scope.get(operation, "parent");
    try setNumber(scope, state, "modelCalls", try n(scope, state, "modelCalls") - 1);
    const waiter = try scope.invoke(try scope.get(state, "modelWaiters"), "shift", &.{});
    if (!c.JS_IsUndefined(waiter)) _ = try scope.call(waiter, c.pi_js_undefined(), &.{});
}
fn finished(scope: *Scope, operation: c.JSValue, outcome: c.JSValue) !void {
    const state = try scope.get(operation, "parent");
    const call = try scope.get(operation, "call");
    if (try flag(scope, call, "replay")) {
        _ = try scope.invoke(try scope.get(state, "ready"), "set", &.{ try scope.get(call, "id"), outcome });
        try deliverReplayed(scope, state);
        return;
    }
    const entry = try scope.object();
    try scope.put(entry, "id", try scope.get(call, "id"));
    try scope.put(entry, "at", try scope.invoke(try scope.global("Date"), "now", &.{}));
    try scope.put(entry, "outcome", outcome);
    if (try is(scope, try scope.get(call, "target"), "global")) {
        const global = try scope.object();
        try scope.put(global, "name", try scope.get(call, "name"));
        const args = try scope.get(call, "args");
        if (!c.JS_IsUndefined(args)) try scope.put(global, "args", args);
        try scope.put(global, "outcome", outcome);
        try scope.put(entry, "global", global);
    }
    try append(scope, try scope.get(state, "queue"), entry);
    try pump(scope, state);
}
fn pump(scope: *Scope, state: c.JSValue) !void {
    if (try flag(scope, state, "committing") or try stopped(scope, state)) return;
    const queue = try scope.get(state, "queue");
    const acks = try scope.get(state, "acks");
    if (try vm.length(scope.engine, queue) == 0 and try n(scope, acks, "size") == 0) return;
    try setFlag(scope, state, "committing", true);
    const batch = try scope.object();
    try scope.put(batch, "entries", try scope.invoke(queue, "splice", &.{c.JS_NewInt32(scope.engine.context, 0)}));
    const symbol = try scope.get(try scope.global("Symbol"), "iterator");
    try scope.put(batch, "acks", try scope.own(try js.collect(scope.engine, acks, symbol)));
    _ = try scope.invoke(acks, "clear", &.{});
    try scope.put(state, "batch", batch);
    const pending = try scope.own(try journal.batch(scope.engine, try scope.get(state, "documents"), try scope.get(state, "api"), try scope.get(state, "context"), batch));
    _ = try wait(scope, state, pending, .batch);
}
fn sameJson(scope: *Scope, left: c.JSValue, right: c.JSValue) anyerror!bool {
    if (scope.equal(left, right)) return true;
    if (!c.JS_IsObject(left) or !c.JS_IsObject(right) or c.JS_IsNull(left) or c.JS_IsNull(right)) return false;
    const array = c.JS_IsArray(left);
    if (array != c.JS_IsArray(right)) return false;
    if (array) {
        const count = try vm.length(scope.engine, left);
        if (count != try vm.length(scope.engine, right)) return false;
        for (0..count) |i| if (!try sameJson(scope, try item(scope, left, i), try item(scope, right, i))) return false;
    } else {
        const object = try scope.global("Object");
        const keys = try scope.invoke(object, "keys", &.{left});
        if (try vm.length(scope.engine, keys) != try vm.length(scope.engine, try scope.invoke(object, "keys", &.{right}))) return false;
        for (0..try vm.length(scope.engine, keys)) |i| {
            const key = try item(scope, keys, i);
            if (!scope.truthy(try scope.invoke(object, "hasOwn", &.{ right, key }))) return false;
            const atom = c.JS_ValueToAtom(scope.engine.context, key);
            if (atom == c.JS_ATOM_NULL) return js.capture(scope.engine);
            defer c.JS_FreeAtom(scope.engine.context, atom);
            if (!try sameJson(scope, try scope.own(try scope.engine.checked(c.JS_GetProperty(scope.engine.context, left, atom))), try scope.own(try scope.engine.checked(c.JS_GetProperty(scope.engine.context, right, atom))))) return false;
        }
    }
    return true;
}
fn cut(scope: *Scope, value: c.JSValue, limit: i32) !c.JSValue {
    if (try n(scope, value, "length") <= @as(f64, @floatFromInt(limit))) return value;
    return scope.concat(try scope.invoke(value, "slice", &.{ c.JS_NewInt32(scope.engine.context, 0), c.JS_NewInt32(scope.engine.context, limit - 3) }), try scope.text("..."));
}
fn details(scope: *Scope, state: c.JSValue) !c.JSValue {
    const values = try scope.invoke(try scope.get(state, "rows"), "values", &.{});
    const rows = try scope.own(try js.collect(scope.engine, values, try scope.get(try scope.global("Symbol"), "iterator")));
    const copied = try scope.array();
    for (0..try vm.length(scope.engine, rows)) |i| {
        const row = try scope.own(try js.spread(scope.engine, try item(scope, rows, i)));
        if (try is(scope, try scope.get(row, "status"), "running")) try scope.put(row, "status", try scope.text("cancelled"));
        try append(scope, copied, row);
    }
    const result = try scope.object();
    try scope.put(result, "calls", copied);
    return result;
}
fn advance(engine: *em.Engine, state: c.JSValue, value: c.JSValue, rejected: bool, raw: c_int) anyerror!c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const stage: Stage = @enumFromInt(raw);
    if (rejected) {
        if (stage == .tool) try releaseModelSlot(&scope, state);
        const parent = if (stage == .tool or stage == .global) try scope.get(state, "parent") else state;
        if (stage == .global) {
            const signal = try scope.get(try scope.get(parent, "context"), "abortSignal");
            if (c.JS_IsUndefined(signal) or !try flag(&scope, signal, "aborted")) {
                const outcome = try scope.object();
                try setFlag(&scope, outcome, "ok", false);
                try scope.put(outcome, "message", try errorMessage(&scope, value));
                try finished(&scope, state, outcome);
                return c.pi_js_undefined();
            }
        }
        if (stage == .tool) {
            const signal = try scope.get(try scope.get(parent, "context"), "abortSignal");
            if (!try stopped(&scope, parent) and (c.JS_IsUndefined(signal) or !try flag(&scope, signal, "aborted"))) {
                try diverge(&scope, parent, try changed(&scope, try scope.get(state, "call"), try scope.concat(try scope.text(": "), try errorMessage(&scope, value))));
                return c.pi_js_undefined();
            }
        }
        if (stage == .initialized or stage == .result or stage == .formatted or stage == .completed or stage == .closed) {
            try cleanup(&scope, state);
            return engine.checked(c.JS_Throw(engine.context, c.JS_DupValue(engine.context, value)));
        }
        try failure(&scope, parent, value);
        return c.pi_js_undefined();
    }
    switch (stage) {
        .model_waiter => {
            const parent = try scope.get(state, "parent");
            try setNumber(&scope, parent, "modelCalls", try n(&scope, parent, "modelCalls") + 1);
            _ = try wait(&scope, state, c.pi_js_undefined(), .model_ready);
        },
        .model_ready => {
            const parent = try scope.get(state, "parent");
            if (try stopped(&scope, parent)) {
                try releaseModelSlot(&scope, state);
                return c.pi_js_undefined();
            }
            const call = try scope.get(state, "call");
            const options = try scope.object();
            try scope.put(options, "key", try scope.concat(try scope.text("c"), try scope.stringify(try scope.get(call, "id"))));
            const pending = scope.invoke(try scope.get(parent, "api"), "executeTool", &.{ try scope.get(call, "name"), try scope.get(call, "args"), try scope.get(parent, "context"), options }) catch |err| {
                try releaseModelSlot(&scope, state);
                return err;
            };
            _ = try wait(&scope, state, pending, .tool);
        },
        .initialized => {
            const done = try scope.get(value, "done");
            if (!c.JS_IsUndefined(done)) return c.JS_DupValue(engine.context, done);
            inline for (.{ "start", "firstIssued", "rerun" }) |key| try scope.put(state, key, try scope.get(value, key));
            const entries = try scope.get(value, "journal");
            try scope.put(state, "replayed", entries);
            const length = try vm.length(engine, entries);
            try setNumber(&scope, state, "journalLength", @floatFromInt(length));
            try setFlag(&scope, state, "replaying", length > 0);
            var durable: f64 = 0;
            const first = try scope.get(value, "firstIssued");
            if (!c.JS_IsUndefined(first)) durable = try number(engine, first);
            for (0..length) |i| {
                const entry = try item(&scope, entries, i);
                _ = try scope.invoke(try scope.get(state, "replayIndex"), "set", &.{ try scope.get(entry, "id"), c.JS_NewFloat64(engine.context, @floatFromInt(i)) });
                const issued = try scope.get(entry, "issuedAfter");
                if (!c.JS_IsUndefined(issued)) durable = @max(durable, try number(engine, issued));
            }
            try setNumber(&scope, state, "durableIssued", durable);
            const start = try scope.get(state, "start");
            const version = try scope.get(start, "version");
            if (try number(engine, version) != 2) {
                const result = try errorResult(&scope, try scope.concat(try scope.concat(try scope.text("The script cannot resume: it started under code mode version "), try scope.stringify(version)), try scope.text(", this is 2.")));
                try scope.put(result, "details", try details(&scope, state));
                return journal.decide(engine, try scope.get(state, "documents"), try scope.get(state, "api"), try scope.get(state, "context"), result);
            }
            const options = try scope.object();
            inline for (.{ "startedAt", "seed", "globals", "store" }) |key| try scope.put(options, key, try scope.get(start, key));
            const declared = try scope.get(start, "tools");
            const visible = try scope.array();
            for (0..try vm.length(engine, declared)) |i| {
                const tool = try item(&scope, declared, i);
                if (!try flag(&scope, tool, "hidden")) try append(&scope, visible, tool);
            }
            try scope.put(options, "tools", visible);
            try scope.put(options, "signal", try scope.get(try scope.get(state, "controller"), "signal"));
            const deadline = try scope.get(start, "deadline");
            if (!c.JS_IsUndefined(deadline)) {
                const remaining = try number(engine, deadline) - try number(engine, try scope.invoke(try scope.global("Date"), "now", &.{}));
                if (remaining <= 0) {
                    const result = try errorResult(&scope, try scope.text("Script timed out: its deadline passed while it was interrupted."));
                    try scope.put(result, "details", try details(&scope, state));
                    return journal.decide(engine, try scope.get(state, "documents"), try scope.get(state, "api"), try scope.get(state, "context"), result);
                }
                try setNumber(&scope, options, "timeoutMs", remaining);
            }
            const signal = try scope.get(try scope.get(state, "context"), "abortSignal");
            if (!c.JS_IsUndefined(signal)) {
                const handler = try callback(&scope, state, .abort);
                try scope.put(state, "abortHandler", handler);
                const once = try scope.object();
                try setFlag(&scope, once, "once", true);
                _ = try scope.invoke(signal, "addEventListener", &.{ try scope.text("abort"), handler, once });
                if (try flag(&scope, signal, "aborted")) try abort(&scope, state, try scope.get(signal, "reason"));
            }
            inline for (.{ .{ "onStarted", Event.started }, .{ "onCall", Event.call }, .{ "onIdle", Event.idle } }) |entry| try scope.put(options, entry[0], try callback(&scope, state, entry[1]));
            const run = try scope.invoke(try scope.get(state, "sandbox"), "start", &.{ try scope.get(state, "code"), options });
            try scope.put(state, "run", run);
            return c.JS_DupValue(engine.context, try wait(&scope, state, try scope.get(run, "result"), .result));
        },
        .fingerprint => try openGate(&scope, state),
        .tool, .global => {
            const parent = try scope.get(state, "parent");
            const call = try scope.get(state, "call");
            var outcome: c.JSValue = undefined;
            if (stage == .tool) {
                try releaseModelSlot(&scope, state);
                if (try is(&scope, try scope.get(call, "name"), "pi.codemode.models.generateImages")) {
                    const structured = try scope.get(value, "structuredOutput");
                    if (c.JS_IsObject(structured) and !c.JS_IsNull(structured)) {
                        const output = try scope.get(structured, "output");
                        if (c.JS_IsArray(output)) for (0..try vm.length(engine, output)) |i| {
                            const block = try item(&scope, output, i);
                            if (c.JS_IsObject(block) and !c.JS_IsNull(block) and try is(&scope, try scope.get(block, "type"), "image")) try setNumber(&scope, parent, "generatedImages", try n(&scope, parent, "generatedImages") + 1);
                        };
                    }
                }
                var structured = false;
                const tools = try scope.get(try scope.get(parent, "start"), "tools");
                for (0..try vm.length(engine, tools)) |i| {
                    const tool = try item(&scope, tools, i);
                    if (scope.equal(try scope.get(tool, "name"), try scope.get(call, "name"))) {
                        structured = try flag(&scope, tool, "structured");
                        break;
                    }
                }
                outcome = try scope.own(try mapping.fromNested(engine, try scope.get(call, "name"), structured, value));
                const row = try scope.invoke(try scope.get(parent, "rows"), "get", &.{try scope.get(call, "id")});
                if (!c.JS_IsUndefined(row)) {
                    const failed = try flag(&scope, value, "isError");
                    try scope.put(row, "status", try scope.text(if (failed) "error" else "ok"));
                    const duration = try scope.get(value, "durationMs");
                    if (!c.JS_IsUndefined(duration)) try scope.put(row, "durationMs", duration);
                    const errors = try scope.array();
                    const diagnostics = try scope.get(value, "diagnostics");
                    for (0..try vm.length(engine, diagnostics)) |i| {
                        const diagnostic = try item(&scope, diagnostics, i);
                        if (try is(&scope, try scope.get(diagnostic, "severity"), "error")) try append(&scope, errors, try scope.get(diagnostic, "message"));
                    }
                    const message = if (!try flag(&scope, outcome, "ok")) try scope.get(outcome, "message") else try scope.invoke(errors, "join", &.{try scope.text("\n")});
                    if (failed and scope.truthy(message)) try scope.put(row, "error", try cut(&scope, message, 500));
                }
            } else {
                outcome = try scope.object();
                try setFlag(&scope, outcome, "ok", true);
                try scope.put(outcome, "value", value);
            }
            try finished(&scope, state, outcome);
        },
        .batch => {
            const batch = try scope.get(state, "batch");
            const acks = try scope.get(batch, "acks");
            for (0..try vm.length(engine, acks)) |i| try setNumber(&scope, state, "durableIssued", @max(try n(&scope, state, "durableIssued"), try number(engine, try item(&scope, try item(&scope, acks, i), 1))));
            const entries = try scope.get(batch, "entries");
            for (0..try vm.length(engine, entries)) |i| {
                const entry = try item(&scope, entries, i);
                const seq = try n(&scope, state, "journalLength") + 1;
                try setNumber(&scope, state, "journalLength", seq);
                if (!try flag(&scope, try scope.get(state, "run"), "finished")) _ = try scope.invoke(try scope.get(state, "run"), "deliver", &.{ c.JS_NewFloat64(engine.context, seq), try scope.get(entry, "at"), try scope.get(entry, "id"), try scope.get(entry, "outcome") });
            }
            try launchCovered(&scope, state);
            try setFlag(&scope, state, "committing", false);
            try pump(&scope, state);
        },
        .decided => try abort(&scope, state, try scope.text("CodeMode invocation decided")),
        .earlier_snapshot => {
            if (!c.JS_IsUndefined(value)) {
                const task = try scope.get(value, "taskId");
                if (!c.JS_IsUndefined(task)) {
                    _ = try wait(&scope, state, try scope.invoke(try scope.get(state, "api"), "getTask", &.{ task, try scope.get(state, "context") }), .earlier_task);
                    return c.pi_js_undefined();
                }
            }
            try setNumber(&scope, state, "releaseIndex", try n(&scope, state, "releaseIndex") + 1);
            try checkEarlier(&scope, state);
        },
        .earlier_task => {
            if (!c.JS_IsUndefined(value)) {
                const input = try scope.get(value, "input");
                if (!c.JS_IsUndefined(input) and try is(&scope, try scope.get(input, "kind"), "nested")) {
                    const made = try scope.get(input, "call");
                    const call = try item(&scope, try scope.get(state, "releaseCalls"), @intFromFloat(try n(&scope, state, "releaseIndex")));
                    const args = try scope.get(call, "args");
                    if (!try is(&scope, try scope.get(call, "target"), "tool") or !scope.equal(try scope.get(made, "name"), try scope.get(call, "name")) or !try sameJson(&scope, try scope.get(made, "arguments"), if (c.JS_IsUndefined(args) or c.JS_IsNull(args)) try scope.object() else args)) {
                        const before = try concat(&scope, &.{ try scope.text(", but was tools."), try scope.get(made, "name"), try scope.text("("), try scope.invoke(try scope.global("JSON"), "stringify", &.{try scope.get(made, "arguments")}), try scope.text(")") });
                        try diverge(&scope, state, try changed(&scope, call, before));
                        return c.pi_js_undefined();
                    }
                }
            }
            try setNumber(&scope, state, "releaseIndex", try n(&scope, state, "releaseIndex") + 1);
            try checkEarlier(&scope, state);
        },
        .result => {
            const reason = try scope.get(state, "failure");
            if (!c.JS_IsUndefined(reason)) {
                try cleanup(&scope, state);
                return engine.checked(c.JS_Throw(engine.context, c.JS_DupValue(engine.context, reason)));
            }
            const ended = try scope.get(state, "ended");
            if (!c.JS_IsUndefined(ended)) {
                try cleanup(&scope, state);
                return c.JS_DupValue(engine.context, ended);
            }
            const signal = try scope.get(try scope.get(state, "context"), "abortSignal");
            if (!c.JS_IsUndefined(signal)) _ = try scope.invoke(signal, "throwIfAborted", &.{});
            if (!try flag(&scope, value, "ok") and try is(&scope, try scope.get(try scope.get(value, "error"), "kind"), "aborted") and !try flag(&scope, try scope.get(try scope.get(state, "controller"), "signal"), "aborted")) {
                if (!c.JS_IsUndefined(signal) and !try flag(&scope, signal, "aborted")) {
                    var functions: [2]c.JSValue = undefined;
                    const pending = try scope.own(try engine.checked(c.JS_NewPromiseCapability(engine.context, &functions)));
                    defer engine.freeValue(functions[0]);
                    defer engine.freeValue(functions[1]);
                    try scope.put(state, "closedResolve", functions[0]);
                    return c.JS_DupValue(engine.context, try wait(&scope, state, pending, .closed));
                }
                return advance(engine, state, c.pi_js_undefined(), false, @intFromEnum(Stage.closed));
            }
            const during = try scope.get(value, "during");
            const replayed = try scope.get(state, "replayed");
            if (try flag(&scope, state, "rerun") and !c.JS_IsUndefined(during)) {
                const seq: usize = @intFromFloat(try n(&scope, during, "seq"));
                const length = try vm.length(engine, replayed);
                if (seq <= length) {
                    var continued = if (seq == 0) length > 0 or !c.JS_IsUndefined(try scope.get(state, "firstIssued")) else !c.JS_IsUndefined(try scope.get(try item(&scope, replayed, seq - 1), "issuedAfter"));
                    for (seq..length) |i| {
                        if (try n(&scope, try item(&scope, replayed, i), "id") > try n(&scope, during, "issued")) continued = true;
                    }
                    if (continued) {
                        const message = try scope.concat(try scope.concat(try scope.text("The script took a different path when resumed after a restart: it ended after result "), try scope.stringify(try scope.get(during, "seq"))), try scope.text(", where it went on before."));
                        const result = try errorResult(&scope, message);
                        try scope.put(result, "details", try details(&scope, state));
                        return c.JS_DupValue(engine.context, try wait(&scope, state, try scope.own(try journal.decide(engine, try scope.get(state, "documents"), try scope.get(state, "api"), try scope.get(state, "context"), result)), .completed));
                    }
                }
            }
            try scope.put(state, "result", value);
            const options = try scope.object();
            try scope.put(options, "generatedImages", try scope.get(state, "generatedImages"));
            try setNumber(&scope, options, "wallMs", try number(engine, try scope.invoke(try scope.global("Date"), "now", &.{})) - try n(&scope, try scope.get(state, "start"), "startedAt"));
            try scope.put(options, "maxOutputTokens", try scope.get(try scope.get(state, "start"), "maxOutputTokens"));
            try scope.put(options, "calls", try scope.get(try details(&scope, state), "calls"));
            const limits = try scope.object();
            try setNumber(&scope, limits, "maxBytes", 4 * 1024 * 1024);
            try setNumber(&scope, limits, "maxLines", 100000);
            try scope.put(options, "limits", limits);
            try scope.put(options, "write", try scope.own(try @import("native_durable_codemode_files.zig").writer(engine, try scope.get(state, "documents"), try scope.get(state, "api"), try scope.get(state, "context"))));
            return c.JS_DupValue(engine.context, try wait(&scope, state, try scope.own(try @import("native_durable_codemode_output.zig").format(engine, value, options)), .formatted));
        },
        .formatted => {
            const result = try scope.get(state, "result");
            const tool = try scope.object();
            try scope.put(tool, "output", try scope.get(value, "content"));
            try setFlag(&scope, tool, "isError", !try flag(&scope, result, "ok"));
            const call_details = try details(&scope, state);
            const full_path = try scope.get(value, "fullOutputPath");
            if (!c.JS_IsUndefined(full_path)) try scope.put(call_details, "fullOutputPath", full_path);
            try scope.put(tool, "details", call_details);
            const payload = try scope.object();
            try scope.put(payload, "result", tool);
            if (try flag(&scope, result, "ok")) try scope.put(payload, "writes", try scope.get(result, "storeWrites"));
            return c.JS_DupValue(engine.context, try wait(&scope, state, try scope.own(try journal.complete(engine, try scope.get(state, "documents"), try scope.get(state, "api"), try scope.get(state, "context"), payload)), .completed));
        },
        .completed => {
            try cleanup(&scope, state);
            return c.JS_DupValue(engine.context, value);
        },
        .closed => {
            try cleanup(&scope, state);
            const signal = try scope.get(try scope.get(state, "context"), "abortSignal");
            if (!c.JS_IsUndefined(signal)) _ = try scope.invoke(signal, "throwIfAborted", &.{});
            const reason = try scope.own(try js.builtin(engine, "Error", &.{try scope.text("The code mode sandbox was closed while the script ran")}));
            return engine.checked(c.JS_Throw(engine.context, c.JS_DupValue(engine.context, reason)));
        },
    }
    return c.pi_js_undefined();
}
