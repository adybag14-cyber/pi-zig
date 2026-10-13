//! Actual staged listeners, buffered publication and abort-owned record tasks.
const std = @import("std");
const h = @import("native_chord_host_values.zig");
const r = @import("native_chord_host_record.zig");
const Scope = h.Scope;
const js = h.js;
const c = h.c;
fn noop(_: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue, _: c_int, _: [*c]c.JSValue) callconv(.c) c.JSValue {
    return c.pi_js_undefined();
}
fn origin(s: *Scope, bindings: c.JSValue, declaration: c.JSValue) !c.JSValue {
    const value = try s.get(declaration, "source");
    const resource = try s.keep(try @import("native_chord_resources.zig").resourceOf(s.engine, value, try s.get(bindings, "resourceBindings")));
    return if (c.JS_IsUndefined(resource)) value else resource;
}
fn sameSelect(s: *Scope, left: c.JSValue, right: c.JSValue) !bool {
    if (c.JS_IsStrictEqual(s.engine.context, left, right)) return true;
    if (c.JS_IsUndefined(left) or c.JS_IsUndefined(right)) return false;
    const string = try s.keep(try js.global(s.engine, "String"));
    const a = try s.keep(try js.call(s.engine, string, c.pi_js_undefined(), &.{left}));
    const b = try s.keep(try js.call(s.engine, string, c.pi_js_undefined(), &.{right}));
    return c.JS_IsStrictEqual(s.engine.context, a, b);
}
fn listenSource(s: *Scope, bindings: c.JSValue, key: c.JSValue, declaration: c.JSValue) !c.JSValue {
    const value = try s.get(declaration, "source");
    const resource = try s.keep(try @import("native_chord_resources.zig").resourceOf(s.engine, value, try s.get(bindings, "resourceBindings")));
    const resolved = if (c.JS_IsUndefined(resource)) value else try s.get(resource, "value");
    const select = try s.get(declaration, "select");
    const source = if (c.JS_IsUndefined(select)) resolved else try s.keep(try js.call(s.engine, select, declaration, &.{resolved}));
    if (h.nullish(source) or !c.JS_IsFunction(s.engine.context, try s.get(source, "subscribe"))) return h.invalid(s, bindings, "behavior", &.{ try s.text("listener "), key, try s.text(": source has no subscribe()") });
    return source;
}
fn stage(s: *Scope, record: c.JSValue, bindings: c.JSValue, declarations: c.JSValue) anyerror!c.JSValue {
    const work = try r.workFor(s, record, bindings);
    const fresh = try h.map(s);
    const kept = try h.set(s);
    try h.field(s, work, "fresh", fresh);
    try h.field(s, work, "kept", kept);
    prepare(s, work, declarations) catch |err| {
        const entries = try h.values(s, fresh);
        for (0..try h.length(s, entries)) |index| {
            const entry = try s.at(entries, index);
            _ = try s.keep(try js.call(s.engine, try s.get(entry, "unsubscribe"), entry, &.{}));
        }
        return err;
    };
    const result = try s.record();
    inline for (.{ "activate", "discard" }, 0..) |name, operation| {
        var captures = [_]c.JSValue{work};
        try js.define(s.engine, result, name, try s.engine.checked(c.JS_NewCFunctionData2(s.engine.context, staged, name, 0, @intCast(operation), 1, &captures)));
    }
    return s.result(result);
}
fn prepare(s: *Scope, work: c.JSValue, declarations: c.JSValue) anyerror!void {
    const record = try s.get(work, "record");
    const bindings = try s.get(work, "bindings");
    const subscriptions = try s.get(try r.state(s, record, bindings), "subscriptions");
    const entries = try h.entries(s, try s.get(declarations, "listeners"));
    for (0..try h.length(s, entries)) |index| {
        const pair = try s.at(entries, index);
        const key = try s.at(pair, 0);
        const declaration = try s.at(pair, 1);
        const owned_origin = try origin(s, bindings, declaration);
        const select = try s.get(declaration, "select");
        const previous = try h.invoke(s, subscriptions, "get", &.{key});
        if (!c.JS_IsUndefined(previous) and c.JS_IsStrictEqual(s.engine.context, owned_origin, try s.get(previous, "origin")) and try sameSelect(s, select, try s.get(previous, "select"))) {
            _ = try h.invoke(s, try s.get(work, "kept"), "add", &.{key});
            continue;
        }
        const source = try listenSource(s, bindings, key, declaration);
        const entry = try s.record();
        try h.field(s, entry, "origin", owned_origin);
        try h.field(s, entry, "select", select);
        try h.field(s, entry, "unsubscribe", try s.keep(try s.engine.checked(c.JS_NewCFunctionData2(s.engine.context, noop, "noop", 0, 0, 0, null))));
        try h.field(s, entry, "buffer", try s.list());
        _ = try h.invoke(s, try s.get(work, "fresh"), "set", &.{ key, entry });
        var captures = [_]c.JSValue{ record, bindings, key, entry };
        const listener = try s.keep(try s.engine.checked(c.JS_NewCFunctionData2(s.engine.context, listenEvent, "", 1, 0, 4, &captures)));
        const unsubscribe = try h.invoke(s, source, "subscribe", &.{listener});
        try h.field(s, entry, "unsubscribe", unsubscribe);
    }
}
fn listenEvent(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, data: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = h.Engine.fromContext(context.?);
    onEvent(engine, data[0], data[1], data[2], data[3], if (argc > 0) argv[0] else c.pi_js_undefined()) catch |err| return @import("native_durable.zig").reject(engine, err);
    return c.pi_js_undefined();
}
fn onEvent(engine: *h.Engine, record: c.JSValue, bindings: c.JSValue, key: c.JSValue, entry: c.JSValue, event: c.JSValue) !void {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    const buffer = try s.get(entry, "buffer");
    if (!c.JS_IsUndefined(buffer)) {
        try js.push(engine, buffer, event);
        return;
    }
    try deliver(engine, record, bindings, key, event);
}
fn staged(context: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue, operation: c_int, data: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = h.Engine.fromContext(context.?);
    return stagedValue(engine, data[0], operation == 0) catch |err| @import("native_durable.zig").reject(engine, err);
}
fn stagedValue(engine: *h.Engine, work: c.JSValue, activate: bool) anyerror!c.JSValue {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    const record = try s.get(work, "record");
    const bindings = try s.get(work, "bindings");
    const subscriptions = try s.get(try r.state(&s, record, bindings), "subscriptions");
    const fresh = try h.entries(&s, try s.get(work, "fresh"));
    if (!activate) {
        for (0..try h.length(&s, fresh)) |index| {
            const entry = try s.at(try s.at(fresh, index), 1);
            _ = try s.keep(try js.call(engine, try s.get(entry, "unsubscribe"), entry, &.{}));
        }
        return c.pi_js_undefined();
    }
    const existing = try h.entries(&s, subscriptions);
    for (0..try h.length(&s, existing)) |index| {
        const pair = try s.at(existing, index);
        const key = try s.at(pair, 0);
        const entry = try s.at(pair, 1);
        if (c.JS_ToBool(engine.context, try h.invoke(&s, try s.get(work, "kept"), "has", &.{key})) != 0) continue;
        _ = try s.keep(try js.call(engine, try s.get(entry, "unsubscribe"), entry, &.{}));
        _ = try h.invoke(&s, subscriptions, "delete", &.{key});
    }
    for (0..try h.length(&s, fresh)) |index| {
        const pair = try s.at(fresh, index);
        const key = try s.at(pair, 0);
        const entry = try s.at(pair, 1);
        _ = try h.invoke(&s, subscriptions, "set", &.{ key, entry });
        const buffer = try s.get(entry, "buffer");
        try h.field(&s, entry, "buffer", c.pi_js_undefined());
        if (!c.JS_IsUndefined(buffer)) for (0..try h.length(&s, buffer)) |slot| try deliver(engine, record, bindings, key, try s.at(buffer, slot));
    }
    return c.pi_js_undefined();
}
pub fn deliver(engine: *h.Engine, record: c.JSValue, bindings: c.JSValue, key: c.JSValue, event: c.JSValue) !void {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    var captures = [_]c.JSValue{ record, bindings, key, event };
    const task = try s.keep(try engine.checked(c.JS_NewCFunctionData2(engine.context, delivery, "", 0, 0, 4, &captures)));
    try @import("native_chord_publish.zig").enqueue(engine, bindings, task);
}
fn delivery(context: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue, _: c_int, data: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = h.Engine.fromContext(context.?);
    return delivered(engine, data) catch |err| @import("native_durable.zig").reject(engine, err);
}
fn delivered(engine: *h.Engine, data: [*c]c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    const record = data[0];
    const gate = try s.get(record, "gate");
    if (!c.JS_IsUndefined(gate)) {
        const item = try s.record();
        try h.field(&s, item, "key", data[2]);
        try h.field(&s, item, "event", data[3]);
        try js.push(engine, try s.get(gate, "queue"), item);
        return c.pi_js_undefined();
    }
    const declaration = try h.invoke(&s, try s.get(try s.get(record, "decls"), "listeners"), "get", &.{data[2]});
    const status = try s.get(record, "status");
    if (c.JS_IsUndefined(declaration) or (!try s.equal(status, "live") and !try s.equal(status, "activating"))) return c.pi_js_undefined();
    var captures = [_]c.JSValue{ record, data[1], declaration, data[3] };
    const function = try s.keep(try engine.checked(c.JS_NewCFunctionData2(engine.context, listenerRoot, "", 1, 0, 4, &captures)));
    const invocation = try h.invoke(&s, try s.get(record, "host"), "root", &.{function});
    try r.background(&s, record, invocation);
    return c.pi_js_undefined();
}
fn listenerRoot(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, data: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = h.Engine.fromContext(context.?);
    return listenerRun(engine, data, if (argc > 0) argv[0] else c.pi_js_undefined()) catch |err| @import("native_durable.zig").reject(engine, err);
}
fn listenerRun(engine: *h.Engine, data: [*c]c.JSValue, ctx: c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    _ = try h.invoke(&s, data[0], "lease", &.{ctx});
    const child = try h.invoke(&s, ctx, "child", &.{data[0]});
    const work = try r.workFor(&s, data[0], data[1]);
    try h.field(&s, work, "child", child);
    const returned = js.call(engine, try s.get(data[2], "fn"), data[2], &.{ data[3], child }) catch |err| {
        if (err != error.JavaScriptException) return err;
        const failure = engine.captured_exception orelse return err;
        const rejected = try s.keep(try h.rejected(engine, failure));
        const closed = try s.keep(try h.wait(listenerDone, engine, work, rejected, 0));
        return @import("native_chord_host_record_call.zig").track(engine, data[0], data[1], closed);
    };
    const result = try s.keep(returned);
    const closed = try s.keep(try h.wait(listenerDone, engine, work, result, 0));
    return @import("native_chord_host_record_call.zig").track(engine, data[0], data[1], closed);
}
fn listenerDone(engine: *h.Engine, work: c.JSValue, value: c.JSValue, rejected: bool, _: c_int) !c.JSValue {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    _ = try h.invoke(&s, try s.get(work, "child"), "close", &.{});
    return if (rejected) h.throwValue(&s, value) else s.result(value);
}
fn startTask(s: *Scope, record: c.JSValue, bindings: c.JSValue, key: c.JSValue, epoch: c.JSValue) !void {
    const function = try h.invoke(s, try s.get(try s.get(record, "decls"), "tasks"), "get", &.{key});
    if (c.JS_IsUndefined(function)) return;
    const controller = try s.keep(try js.builtin(s.engine, "AbortController", &.{}));
    const signals = try s.list();
    try js.push(s.engine, signals, try s.get(controller, "signal"));
    try js.push(s.engine, signals, try s.get(try s.get(record, "callAbort"), "signal"));
    const fields = try s.record();
    try h.field(s, fields, "signal", try h.invoke(s, try s.keep(try js.global(s.engine, "AbortSignal")), "any", &.{signals}));
    const root = try s.keep(try @import("native_utf16.zig").concat(s.engine, &.{ try s.text("task:"), try s.get(record, "address"), try s.text(":"), key }));
    try h.field(s, fields, "rootId", root);
    try h.field(s, fields, "epoch", epoch);
    try h.field(s, fields, "principal", try s.get(try s.get(record, "host"), "principal"));
    try h.field(s, fields, "holder", c.pi_js_bool(s.engine.context, 1));
    const ctx = try h.construct(s, bindings, "CtxImpl", &.{ try s.get(record, "host"), fields });
    const work = try r.workFor(s, record, bindings);
    try h.field(s, work, "key", key);
    try h.field(s, work, "controller", controller);
    try h.field(s, work, "ctx", ctx);
    const returned = js.call(s.engine, function, c.pi_js_undefined(), &.{ctx}) catch |err| {
        if (err != error.JavaScriptException) return err;
        const failure = try s.keep(try h.rejected(s.engine, s.engine.captured_exception orelse return err));
        return taskStore(s, record, bindings, key, controller, try s.keep(try h.wait(taskDone, s.engine, work, failure, 0)));
    };
    const result = try s.keep(returned);
    try taskStore(s, record, bindings, key, controller, try s.keep(try h.wait(taskDone, s.engine, work, result, 0)));
}
fn taskStore(s: *Scope, record: c.JSValue, bindings: c.JSValue, key: c.JSValue, controller: c.JSValue, done: c.JSValue) !void {
    const entry = try s.record();
    try h.field(s, entry, "controller", controller);
    try h.field(s, entry, "done", done);
    _ = try h.invoke(s, try s.get(try r.state(s, record, bindings), "tasks"), "set", &.{ key, entry });
}
fn taskDone(engine: *h.Engine, work: c.JSValue, value: c.JSValue, rejected: bool, _: c_int) !c.JSValue {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    const record = try s.get(work, "record");
    const bindings = try s.get(work, "bindings");
    const ctx = try s.get(work, "ctx");
    if (rejected and !try h.flag(&s, try s.get(ctx, "signal"), "aborted")) _ = try h.invoke(&s, try s.get(record, "host"), "report", &.{value});
    _ = try h.invoke(&s, ctx, "close", &.{});
    const tasks = try s.get(try r.state(&s, record, bindings), "tasks");
    const key = try s.get(work, "key");
    const current = try h.invoke(&s, tasks, "get", &.{key});
    if (!c.JS_IsUndefined(current) and c.JS_IsStrictEqual(engine.context, try s.get(current, "controller"), try s.get(work, "controller"))) _ = try h.invoke(&s, tasks, "delete", &.{key});
    return c.pi_js_undefined();
}
pub fn invoke(engine: *h.Engine, record: c.JSValue, bindings: c.JSValue, operation: []const u8, args: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    const state = try r.state(&s, record, bindings);
    if (std.mem.eql(u8, operation, "stageListeners")) return stage(&s, record, bindings, h.arg(args, 0));
    if (std.mem.eql(u8, operation, "startRuntime")) {
        const staged_value = try h.invoke(&s, record, "stageListeners", &.{try s.get(record, "decls")});
        _ = try h.invoke(&s, staged_value, "activate", &.{});
        _ = try h.invoke(&s, record, "startTasks", &.{});
        return c.pi_js_undefined();
    }
    if (std.mem.eql(u8, operation, "startTasks")) {
        const keys = try h.snapshot(&s, try h.invoke(&s, try s.get(try s.get(record, "decls"), "tasks"), "keys", &.{}));
        for (0..try h.length(&s, keys)) |index| try startTask(&s, record, bindings, try s.at(keys, index), try h.invoke(&s, try s.get(record, "host"), "currentEpoch", &.{}));
        return c.pi_js_undefined();
    }
    if (std.mem.eql(u8, operation, "startTask")) {
        try startTask(&s, record, bindings, h.arg(args, 0), h.arg(args, 1));
        return c.pi_js_undefined();
    }
    if (std.mem.eql(u8, operation, "stopListeners")) {
        const subscriptions = try s.get(state, "subscriptions");
        const values = try h.values(&s, subscriptions);
        for (0..try h.length(&s, values)) |index| {
            const entry = try s.at(values, index);
            _ = try s.keep(try js.call(engine, try s.get(entry, "unsubscribe"), entry, &.{}));
        }
        _ = try h.invoke(&s, subscriptions, "clear", &.{});
        return c.pi_js_undefined();
    }
    if (std.mem.eql(u8, operation, "stopTasks")) {
        const tasks = try s.get(state, "tasks");
        const values = try h.values(&s, tasks);
        for (0..try h.length(&s, values)) |index| {
            const entry = try s.at(values, index);
            _ = try h.invoke(&s, try s.get(entry, "controller"), "abort", &.{try h.errorValue(&s, bindings, "aborted", &.{try s.text("task stopped")}, c.pi_js_undefined())});
            try js.push(engine, try s.get(state, "stopped"), try s.get(entry, "done"));
        }
        _ = try h.invoke(&s, tasks, "clear", &.{});
        return c.pi_js_undefined();
    }
    const gate = try s.get(record, "gate");
    try h.field(&s, record, "gate", c.pi_js_undefined());
    if (!c.JS_IsUndefined(gate)) {
        const queue = try s.get(gate, "queue");
        for (0..try h.length(&s, queue)) |index| {
            const item = try s.at(queue, index);
            try deliver(engine, record, bindings, try s.get(item, "key"), try s.get(item, "event"));
        }
    }
    return c.pi_js_undefined();
}
