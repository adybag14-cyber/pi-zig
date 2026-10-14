//! Actual b45 activation transaction: open, hydrate, initialize, publish, unwind.
const h = @import("native_chord_host_values.zig");
const js = h.js;
const c = h.c;
const Scope = h.Scope;
const aw = @import("native_chord_async_work.zig");
const object = @import("native_chord_object.zig");
fn noop(_: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue) callconv(.c) c.JSValue {
    return c.pi_js_undefined();
}
fn resultCallback(ctx: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, magic: c_int, data: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = h.Engine.fromContext(ctx.?);
    return object.startedResult(engine, data[0], if (argc > 0) argv[0] else c.pi_js_undefined(), magic != 0, 0) catch |err| @import("native_durable.zig").reject(engine, err);
}
pub fn start(engine: *h.Engine, record: c.JSValue, bindings: c.JSValue, after: c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    const work = try aw.create(&s);
    try h.field(&s, work, "object", record);
    try h.field(&s, work, "bindings", bindings);
    const ignored = try s.keep(try engine.checked(c.JS_NewCFunction(engine.context, noop, "noop", 0)));
    // Source awaits after?.catch(noop), then uses public .then for start's observers.
    if (h.nullish(after)) {
        try aw.wait(advance, &s, work, c.pi_js_undefined(), 0);
    } else {
        const awaited = h.invoke(&s, after, "catch", &.{ignored});
        if (awaited) |pending| {
            try aw.wait(advance, &s, work, pending, 0);
        } else |err| try aw.rejectError(&s, work, err);
    }
    var captures = [_]c.JSValue{work};
    const fulfilled = try s.keep(try engine.checked(c.JS_NewCFunctionData2(engine.context, resultCallback, "", 0, 0, 1, &captures)));
    const rejected = try s.keep(try engine.checked(c.JS_NewCFunctionData2(engine.context, resultCallback, "", 1, 1, 1, &captures)));
    const ready = try h.invoke(&s, try s.get(work, "promise"), "then", &.{ fulfilled, rejected });
    try h.field(&s, record, "ready", ready);
    _ = try h.invoke(&s, ready, "catch", &.{ignored});
    return c.pi_js_undefined();
}
fn abandoned(s: *Scope, record: c.JSValue, bindings: c.JSValue) !c.JSValue {
    return h.errorValue(s, bindings, "aborted", &.{ try s.get(record, "address"), try s.text(" abandoned") }, c.pi_js_undefined());
}
fn advance(engine: *h.Engine, work: c.JSValue, value: c.JSValue, rejected: bool, stage: c_int) anyerror!void {
    step(engine, work, value, rejected, stage) catch |err| {
        if (err != error.JavaScriptException) return err;
        var s: Scope = .{ .engine = engine };
        defer s.deinit();
        if (stage >= 1 and stage <= 3) {
            fail(&s, work, engine.captured_exception orelse return err) catch |cleanup_error| {
                // The original finally executes even when rollback itself fails.
                const replacement = if (cleanup_error == error.JavaScriptException) engine.captured_exception else null;
                try dropPending(&s, try s.get(work, "object"), try s.get(work, "run"));
                if (replacement) |reason| try aw.complete(&s, work, reason, true) else return cleanup_error;
            };
        } else if (stage >= 4) {
            const reason = engine.captured_exception orelse return err;
            try dropPending(&s, try s.get(work, "object"), try s.get(work, "run"));
            try aw.complete(&s, work, reason, true);
        } else return err;
    };
}
fn dropPending(s: *Scope, record: c.JSValue, run: c.JSValue) !void {
    _ = try h.invoke(s, try s.get(record, "pending"), "delete", &.{try s.get(run, "decls")});
}
fn step(engine: *h.Engine, work: c.JSValue, value: c.JSValue, rejected: bool, stage: c_int) anyerror!void {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    const record = try s.get(work, "object");
    const bindings = try s.get(work, "bindings");
    const host = try s.get(record, "host");
    if (stage == 5) {
        try dropPending(&s, record, try s.get(work, "run"));
        try aw.complete(&s, work, if (rejected) value else try s.get(work, "failure"), true);
        return;
    }
    if (stage == 4) {
        if (rejected) {
            try dropPending(&s, record, try s.get(work, "run"));
            try aw.complete(&s, work, value, true);
            return;
        }
        const cleanup = try h.invoke(&s, record, "unwind", &.{try s.get(work, "run")});
        var captures = [_]c.JSValue{host};
        const observer = try s.keep(try engine.checked(c.JS_NewCFunctionData2(engine.context, reportCleanup, "", 1, 0, 1, &captures)));
        try aw.wait(advance, &s, work, try h.invoke(&s, cleanup, "catch", &.{observer}), 5);
        return;
    }
    if (stage == 0) {
        if (rejected) {
            try aw.complete(&s, work, value, true);
            return;
        }
        const signal = try s.get(try s.get(record, "activationAbort"), "signal");
        if (try h.flag(&s, signal, "aborted")) {
            try aw.complete(&s, work, try abandoned(&s, record, bindings), true);
            return;
        }
        const service = try h.invoke(&s, host, "service", &.{try s.get(record, "typeName")});
        if (c.JS_IsUndefined(service)) {
            const options = try s.record();
            try h.field(&s, options, "reason", try s.text("unknown_type"));
            try aw.complete(&s, work, try h.errorValue(&s, bindings, "unavailable", &.{ try s.get(record, "typeName"), try s.text(" is not served") }, options), true);
            return;
        }
        try h.field(&s, record, "service", service);
        const run = try h.invoke(&s, record, "run", &.{ service, c.pi_js_undefined() });
        try h.field(&s, work, "run", run);
        try open(&s, work, record, run, signal);
        return;
    }
    if (rejected) {
        try fail(&s, work, value);
        return;
    }
    const run = try s.get(work, "run");
    const signal = try s.get(try s.get(record, "activationAbort"), "signal");
    if (try h.flag(&s, signal, "aborted")) {
        try fail(&s, work, try abandoned(&s, record, bindings));
        return;
    }
    if (stage == 1) {
        try aw.wait(advance, &s, work, try h.invoke(&s, record, "waitHydrated", &.{run}), 2);
        return;
    }
    if (stage == 2) {
        try aw.wait(advance, &s, work, try h.invoke(&s, record, "initCells", &.{ run, signal }), 3);
        return;
    }
    try object.finalize(&s, record, bindings, run);
    try dropPending(&s, record, run);
    try aw.complete(&s, work, c.pi_js_undefined(), false);
}
fn reportCleanup(ctx: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, data: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = h.Engine.fromContext(ctx.?);
    return js.invoke(engine, data[0], "report", &.{if (argc > 0) argv[0] else c.pi_js_undefined()}) catch |err| @import("native_durable.zig").reject(engine, err);
}
fn open(s: *Scope, work: c.JSValue, record: c.JSValue, run: c.JSValue, signal: c.JSValue) !void {
    openWithinTry(s, work, record, run, signal) catch |err| {
        if (err != error.JavaScriptException) return err;
        try fail(s, work, s.engine.captured_exception orelse return err);
    };
}
fn openWithinTry(s: *Scope, work: c.JSValue, record: c.JSValue, run: c.JSValue, signal: c.JSValue) !void {
    const created = try s.get(run, "created");
    const opening = try h.invoke(s, record, "open", &.{ try s.get(created, "resources"), try s.get(created, "refs"), signal });
    try aw.wait(advance, s, work, opening, 1);
}
fn fail(s: *Scope, work: c.JSValue, failure: c.JSValue) !void {
    const record = try s.get(work, "object");
    const bindings = try s.get(work, "bindings");
    try h.field(s, work, "failure", failure);
    _ = try h.invoke(s, try s.get(record, "callAbort"), "abort", &.{failure});
    _ = try h.invoke(s, record, "stopListeners", &.{});
    _ = try h.invoke(s, record, "stopTasks", &.{});
    const registered = try object.nonempty(s, try s.get(try s.get(record, "decls"), "registrations")) and !try h.flag(s, record, "deferredRuntime");
    _ = try h.invoke(s, try s.get(record, "implementations"), "clear", &.{});
    try h.field(s, record, "decls", try h.construct(s, bindings, "Decls", &.{}));
    if (registered) _ = try h.invoke(s, try s.get(record, "host"), "registriesChanged", &.{});
    const data = try object.state(s, record, bindings);
    const jobs = try h.snapshot(s, try s.get(data, "invocations"));
    const stopped = try h.snapshot(s, try s.get(data, "stopped"));
    const all = try h.invoke(s, jobs, "concat", &.{stopped});
    try aw.wait(advance, s, work, try s.builtin("Promise", "allSettled", &.{all}), 4);
}
