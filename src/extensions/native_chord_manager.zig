//! Actual Source1692 createHostManager: serialized starts/stops, ready/fatal votes, grace kills and liveness.
const r = @import("native_chord_reload_values.zig");
const h = r.h;
const js = r.js;
const c = r.c;
const Scope = r.Scope;
const Op = enum(c_int) { status, instance, liveness, start, stop, replace, do_start, do_stop, do_replace, exited, ready_executor, ready_timeout, ready_exited, control, grace_executor, grace_timeout, graceful, keep_alive };
fn callback(ctx: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, magic: c_int, captures: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = h.Engine.fromContext(ctx.?);
    const op: Op = @enumFromInt(magic);
    const value = execute(engine, captures[0], if (argc > 0) argv[0..@intCast(argc)] else &.{}, op) catch |err| return if (op == .do_start or op == .do_stop or op == .do_replace) @import("native_durable.zig").rejectedPromise(engine, err) else @import("native_durable.zig").reject(engine, err);
    if (op != .do_start and op != .do_stop and op != .do_replace) return value;
    defer engine.freeValue(value);
    return @import("native_durable.zig").resolvedPromise(engine, value) catch |err| @import("native_durable.zig").rejectedPromise(engine, err);
}
fn function(s: *Scope, state: c.JSValue, op: Op, name: [*:0]const u8, length: c_int) !c.JSValue {
    var captures = [_]c.JSValue{state};
    return s.keep(try s.engine.checked(c.JS_NewCFunctionData2(s.engine.context, callback, name, length, @intFromEnum(op), 1, &captures)));
}
fn emptyReport(s: *Scope) !c.JSValue {
    const value = try s.record();
    inline for (.{ "activeCalls", "viewers", "durableTasks" }) |name| try h.field(s, value, name, c.JS_NewInt32(s.engine.context, 0));
    return value;
}
fn work(s: *Scope, state: c.JSValue, current: c.JSValue) !c.JSValue {
    const value = try s.record();
    try h.field(s, value, "state", state);
    try h.field(s, value, "current", current);
    return value;
}
fn total(s: *Scope, report: c.JSValue) !c.JSValue {
    const first = try s.keep(try s.engine.checked(c.JS_PiBinaryOperator(s.engine.context, 0, try s.get(report, "activeCalls"), try s.get(report, "viewers"))));
    return s.keep(try s.engine.checked(c.JS_PiBinaryOperator(s.engine.context, 0, first, try s.get(report, "durableTasks"))));
}
fn liveness(s: *Scope, state: c.JSValue) !c.JSValue {
    const result = try s.record();
    try h.field(s, result, "booting", try s.get(state, "booting"));
    try js.spreadInto(s.engine, result, try s.get(state, "report"));
    const idle = try s.get(state, "idleSince");
    const elapsed = if (c.JS_IsUndefined(idle)) c.JS_NewInt32(s.engine.context, 0) else try s.keep(try s.engine.checked(c.JS_PiBinaryOperator(s.engine.context, 1, try s.builtin("Date", "now", &.{}), idle)));
    try h.field(s, result, "idleFor", elapsed);
    return result;
}
fn serialized(s: *Scope, state: c.JSValue, op: Op) !c.JSValue {
    const step = try s.get(state, if (op == .start) "doStart" else if (op == .stop) "doStop" else "doReplace");
    const next = try h.invoke(s, try s.get(state, "queue"), "then", &.{ step, step });
    const noop = try s.keep(try s.engine.checked(c.JS_NewCFunctionData2(s.engine.context, r.noop, "", 0, 0, 0, null)));
    try h.field(s, state, "queue", try h.invoke(s, next, "catch", &.{noop}));
    return s.result(next);
}
fn clear(s: *Scope, name: [*:0]const u8, timer: c.JSValue) !void {
    _ = try s.keep(try js.call(s.engine, try s.keep(try js.global(s.engine, name)), c.pi_js_undefined(), &.{timer}));
}
fn settle(s: *Scope, task: c.JSValue, reject: bool, value: c.JSValue) !void {
    try clear(s, "clearTimeout", try s.get(task, "timeout"));
    _ = try s.keep(try js.call(s.engine, try s.get(task, if (reject) "reject" else "resolve"), c.pi_js_undefined(), if (reject) &.{value} else &.{}));
}
fn execute(engine: *h.Engine, state: c.JSValue, args: []const c.JSValue, op: Op) anyerror!c.JSValue {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    if (op == .status or op == .instance) return js.get(engine, state, if (op == .status) "status" else "instance");
    if (op == .liveness) return s.result(try liveness(&s, state));
    if (op == .start or op == .stop or op == .replace) return serialized(&s, state, op);
    if (op == .do_start) return start(&s, state);
    if (op == .do_stop) return stop(&s, state);
    if (op == .do_replace) return h.wait(replaced, engine, state, try s.keep(try js.call(engine, try s.get(state, "doStop"), c.pi_js_undefined(), &.{})), 0);
    const outer = try s.get(state, "state");
    const options = try s.get(outer, "options");
    const bindings = try s.get(outer, "bindings");
    const current = try s.get(state, "current");
    const value = h.arg(args, 0);
    switch (op) {
        .exited => {
            if (c.JS_IsStrictEqual(engine.context, try s.get(outer, "instance"), current)) {
                try h.field(&s, outer, "instance", c.pi_js_undefined());
                try h.field(&s, outer, "status", try s.text("stopped"));
                const timer = try s.get(outer, "timer");
                if (!c.JS_IsUndefined(timer)) try clear(&s, "clearInterval", timer);
            }
            const on_exit = try s.get(options, "onExit");
            if (!h.nullish(on_exit)) _ = try s.keep(try js.call(engine, on_exit, options, &.{value}));
        },
        .ready_executor => {
            try h.field(&s, state, "resolve", value);
            try h.field(&s, state, "reject", h.arg(args, 1));
            const deadline = r.default(&s, try s.get(options, "readyTimeout"), c.JS_NewInt32(engine.context, 30000));
            const timeout = try s.keep(try js.call(engine, try s.keep(try js.global(engine, "setTimeout")), c.pi_js_undefined(), &.{ try function(&s, state, .ready_timeout, "", 0), deadline }));
            try h.field(&s, state, "timeout", timeout);
            _ = try h.invoke(&s, try s.get(current, "exited"), "then", &.{try function(&s, state, .ready_exited, "", 1)});
            _ = try h.invoke(&s, current, "onControl", &.{try function(&s, state, .control, "", 1)});
        },
        .ready_timeout => {
            const failure = try h.errorValue(&s, bindings, "unavailable", &.{try s.text("child not ready in time")}, c.pi_js_undefined());
            _ = try s.keep(try js.call(engine, try s.get(state, "reject"), c.pi_js_undefined(), &.{failure}));
        },
        .ready_exited => {
            const code = r.default(&s, try s.get(value, "code"), try s.get(value, "signal"));
            try settle(&s, state, true, try h.errorValue(&s, bindings, "unavailable", &.{ try s.text("child exited before ready ("), code, try s.text(")") }, c.pi_js_undefined()));
        },
        .control => {
            const tag = try s.get(value, "type");
            if (try s.equal(tag, "ready")) {
                try settle(&s, state, false, c.pi_js_undefined());
            } else if (try s.equal(tag, "fatal")) {
                const detail = try s.record();
                try h.field(&s, detail, "reason", try s.get(value, "reason"));
                try settle(&s, state, true, try h.errorValue(&s, bindings, "unavailable", &.{ try s.text("child failed: "), try s.get(value, "message") }, detail));
            } else if (try s.equal(tag, "status")) {
                const report = try s.record();
                inline for (.{ "activeCalls", "viewers", "durableTasks" }) |name| try h.field(&s, report, name, r.default(&s, try s.get(value, name), c.JS_NewInt32(engine.context, 0)));
                try h.field(&s, outer, "report", report);
                if (try r.greater(&s, try total(&s, report), c.JS_NewInt32(engine.context, 0))) {
                    try h.field(&s, outer, "idleSince", c.pi_js_undefined());
                } else if (h.nullish(try s.get(outer, "idleSince"))) try h.field(&s, outer, "idleSince", try s.builtin("Date", "now", &.{}));
            }
        },
        .grace_executor => {
            try h.field(&s, state, "resolve", value);
            const grace = r.default(&s, try s.get(options, "grace"), c.JS_NewInt32(engine.context, 5000));
            try h.field(&s, state, "graceTimer", try s.keep(try js.call(engine, try s.keep(try js.global(engine, "setTimeout")), c.pi_js_undefined(), &.{ try function(&s, state, .grace_timeout, "", 0), grace })));
        },
        .grace_timeout => return js.call(engine, try s.get(state, "resolve"), c.pi_js_undefined(), &.{c.pi_js_bool(engine.context, 0)}),
        .graceful => return c.pi_js_bool(engine.context, 1),
        .keep_alive => {
            if (try s.equal(try s.get(outer, "status"), "running") and c.JS_ToBool(engine.context, try s.keep(try js.call(engine, try s.get(state, "keepAlive"), c.pi_js_undefined(), &.{try liveness(&s, outer)}))) == 0) _ = try s.keep(try serialized(&s, outer, .stop));
        },
        else => unreachable,
    }
    return c.pi_js_undefined();
}
fn start(s: *Scope, state: c.JSValue) anyerror!c.JSValue {
    const existing = try s.get(state, "instance");
    if (!c.JS_IsUndefined(existing) and try s.equal(try s.get(state, "status"), "running")) return s.result(existing);
    try h.field(s, state, "status", try s.text("starting"));
    try h.field(s, state, "booting", c.pi_js_bool(s.engine.context, 1));
    try h.field(s, state, "report", try emptyReport(s));
    const options = try s.get(state, "options");
    const current = h.invoke(s, try s.get(options, "driver"), "spawn", &.{}) catch |err| {
        const failure = if (err == error.JavaScriptException) try s.keep(c.JS_DupValue(s.engine.context, s.engine.captured_exception.?)) else c.pi_js_undefined();
        try h.field(s, state, "status", try s.text("stopped"));
        try h.field(s, state, "booting", c.pi_js_bool(s.engine.context, 0));
        if (err == error.JavaScriptException) return h.throwValue(s, failure);
        return err;
    };
    try h.field(s, state, "instance", current);
    const task = try work(s, state, current);
    _ = try h.invoke(s, try s.get(current, "exited"), "then", &.{try function(s, task, .exited, "", 1)});
    const pending = try s.keep(try js.builtin(s.engine, "Promise", &.{try function(s, task, .ready_executor, "", 2)}));
    return h.wait(started, s.engine, task, pending, 0);
}
fn started(engine: *h.Engine, task: c.JSValue, value: c.JSValue, rejected: bool, phase: c_int) anyerror!c.JSValue {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    if (phase == 1) {
        if (rejected) return h.throwValue(&s, value);
        return h.throwValue(&s, try s.get(task, "failure"));
    }
    const current = try s.get(task, "current");
    if (rejected) {
        try h.field(&s, task, "failure", value);
        _ = try h.invoke(&s, current, "killTree", &.{});
        return h.wait(started, engine, task, try s.get(current, "exited"), 1);
    }
    const state = try s.get(task, "state");
    try h.field(&s, state, "booting", c.pi_js_bool(engine.context, 0));
    const report = try s.get(state, "report");
    if (c.JS_IsStrictEqual(engine.context, try total(&s, report), c.JS_NewInt32(engine.context, 0)) and h.nullish(try s.get(state, "idleSince"))) try h.field(&s, state, "idleSince", try s.builtin("Date", "now", &.{}));
    try h.field(&s, state, "status", try s.text("running"));
    const options = try s.get(state, "options");
    if (!c.JS_IsUndefined(try s.get(options, "keepAlive"))) {
        try h.field(&s, task, "keepAlive", try s.get(options, "keepAlive"));
        const interval = r.default(&s, try s.get(options, "checkInterval"), c.JS_NewInt32(engine.context, 1000));
        const timer = try s.keep(try js.call(engine, try s.keep(try js.global(engine, "setInterval")), c.pi_js_undefined(), &.{ try function(&s, task, .keep_alive, "", 0), interval }));
        try h.field(&s, state, "timer", timer);
        const unref = try s.get(timer, "unref");
        if (!h.nullish(unref)) _ = try s.keep(try js.call(engine, unref, timer, &.{}));
    }
    return s.result(current);
}
fn stop(s: *Scope, state: c.JSValue) anyerror!c.JSValue {
    const current = try s.get(state, "instance");
    if (c.JS_IsUndefined(current)) {
        try h.field(s, state, "status", try s.text("stopped"));
        try h.field(s, state, "booting", c.pi_js_bool(s.engine.context, 0));
        return c.pi_js_undefined();
    }
    try h.field(s, state, "status", try s.text("stopping"));
    const timer = try s.get(state, "timer");
    if (!c.JS_IsUndefined(timer)) try clear(s, "clearInterval", timer);
    const shutdown = try s.record();
    try h.field(s, shutdown, "type", try s.text("shutdown"));
    _ = try h.invoke(s, current, "send", &.{shutdown});
    const task = try work(s, state, current);
    const waits = try s.list();
    try js.push(s.engine, waits, try h.invoke(s, try s.get(current, "exited"), "then", &.{try function(s, task, .graceful, "", 0)}));
    try js.push(s.engine, waits, try s.keep(try js.builtin(s.engine, "Promise", &.{try function(s, task, .grace_executor, "", 1)})));
    return h.wait(stopped, s.engine, task, try r.promise(s, "race", waits), 0);
}
fn stopped(engine: *h.Engine, task: c.JSValue, value: c.JSValue, rejected: bool, phase: c_int) anyerror!c.JSValue {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    if (rejected) return h.throwValue(&s, value);
    const current = try s.get(task, "current");
    if (phase == 0) {
        try clear(&s, "clearTimeout", try s.get(task, "graceTimer"));
        if (c.JS_ToBool(engine.context, value) == 0) _ = try h.invoke(&s, current, "killTree", &.{});
        return h.wait(stopped, engine, task, try s.get(current, "exited"), 1);
    }
    const state = try s.get(task, "state");
    if (c.JS_IsStrictEqual(engine.context, try s.get(state, "instance"), current)) try h.field(&s, state, "instance", c.pi_js_undefined());
    try h.field(&s, state, "status", try s.text("stopped"));
    return c.pi_js_undefined();
}
fn replaced(engine: *h.Engine, state: c.JSValue, value: c.JSValue, rejected: bool, _: c_int) anyerror!c.JSValue {
    if (rejected) return engine.checked(c.JS_Throw(engine.context, c.JS_DupValue(engine.context, value)));
    return js.invoke(engine, state, "doStart", &.{});
}
pub fn create(engine: *h.Engine, _: c.JSValue, args: []const c.JSValue, captures: []const c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    const state = try s.record();
    try h.field(&s, state, "options", h.arg(args, 0));
    try h.field(&s, state, "bindings", captures[0]);
    try h.field(&s, state, "status", try s.text("stopped"));
    try h.field(&s, state, "instance", c.pi_js_undefined());
    try h.field(&s, state, "queue", try h.invoke(&s, try s.keep(try js.global(engine, "Promise")), "resolve", &.{}));
    try h.field(&s, state, "report", try emptyReport(&s));
    try h.field(&s, state, "booting", c.pi_js_bool(engine.context, 0));
    inline for (.{ "idleSince", "timer" }) |name| try h.field(&s, state, name, c.pi_js_undefined());
    inline for (.{ .{ "doStart", Op.do_start }, .{ "doStop", Op.do_stop }, .{ "doReplace", Op.do_replace } }) |entry| try h.field(&s, state, entry[0], try function(&s, state, entry[1], "", 0));
    const result = try s.record();
    inline for (.{ .{ "status", Op.status }, .{ "instance", Op.instance }, .{ "liveness", Op.liveness } }) |entry| {
        const getter = try function(&s, state, entry[1], entry[0], 0);
        const atom = c.JS_NewAtom(engine.context, entry[0]);
        defer c.JS_FreeAtom(engine.context, atom);
        if (c.JS_DefinePropertyGetSet(engine.context, result, atom, s.result(getter), c.pi_js_undefined(), c.JS_PROP_CONFIGURABLE | c.JS_PROP_ENUMERABLE) < 0) return js.capture(engine);
    }
    inline for (.{ .{ "start", Op.start }, .{ "stop", Op.stop }, .{ "replace", Op.replace } }) |entry| try h.field(&s, result, entry[0], try function(&s, state, entry[1], entry[0], 0));
    return s.result(result);
}
