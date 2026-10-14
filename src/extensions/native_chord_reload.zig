//! Actual Source Reload class and serialized begin/run/end entry points. Private installation only.
const r = @import("native_chord_reload_values.zig");
const h = r.h;
const js = r.js;
const c = r.c;
const Scope = r.Scope;
const Method = enum(c_int) { prepare, summary, waitForRetirement, load, withDeadline, checkProviders, prepareAll, prepareObject, checkRefs, entries, gate, migrate, rollback, commit, install };
fn asyncMethod(method: Method) bool {
    return switch (method) {
        .prepare, .waitForRetirement, .withDeadline, .prepareAll, .prepareObject, .gate, .rollback => true,
        else => false,
    };
}
fn callback(ctx: ?*c.JSContext, receiver: c.JSValue, argc: c_int, argv: [*c]c.JSValue, operation: c_int, captures: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = h.Engine.fromContext(ctx.?);
    const method: Method = @enumFromInt(operation);
    const returned = invoke(engine, captures[0], receiver, if (argc > 0) argv[0..@intCast(argc)] else &.{}, method) catch |err| return if (asyncMethod(method)) @import("native_durable.zig").rejectedPromise(engine, err) else @import("native_durable.zig").reject(engine, err);
    if (!asyncMethod(method)) return returned;
    defer engine.freeValue(returned);
    return @import("native_durable.zig").resolvedPromise(engine, returned) catch |err| @import("native_durable.zig").rejectedPromise(engine, err);
}
fn invoke(engine: *h.Engine, bindings: c.JSValue, receiver: c.JSValue, args: []const c.JSValue, method: Method) anyerror!c.JSValue {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    switch (method) {
        .prepare => return @import("native_chord_reload_prepare.zig").prepare(&s, bindings, receiver),
        .summary => return s.result(try @import("native_chord_reload_table.zig").summary(&s, receiver)),
        .waitForRetirement => return s.result(try @import("native_chord_reload_retirement.zig").wait(&s, bindings, receiver)),
        .load => try @import("native_chord_reload_table.zig").load(&s, bindings, receiver),
        .withDeadline => return @import("native_chord_reload_timing.zig").deadline(&s, bindings, receiver, h.arg(args, 0), h.arg(args, 1)),
        .checkProviders => try @import("native_chord_reload_candidate.zig").checkProviders(&s, bindings, receiver),
        .prepareAll => return @import("native_chord_reload_prepare.zig").prepareAll(&s, bindings, receiver),
        .prepareObject => {
            const pending = try @import("native_chord_reload_record.zig").prepare(&s, bindings, receiver, h.arg(args, 0));
            return h.wait(discard, engine, c.pi_js_undefined(), pending, 0);
        },
        .checkRefs => try @import("native_chord_reload_candidate.zig").checkRefs(&s, bindings, receiver),
        .entries => return s.result(try @import("native_chord_reload_table.zig").entries(&s, receiver)),
        .gate => return @import("native_chord_reload_prepare.zig").gate(&s, bindings, receiver),
        .migrate => try @import("native_chord_reload_candidate.zig").migrate(&s, bindings, h.arg(args, 0)),
        .rollback => return @import("native_chord_reload_rollback.zig").rollback(&s, bindings, receiver),
        .commit, .install => {
            const starts = try s.get((try h.actor(&s, receiver, bindings, .Reload)).data, "starts");
            if (method == .commit) return @import("native_chord_reload_commit.zig").commit(&s, bindings, receiver, starts, h.arg(args, 0));
            try @import("native_chord_reload_install.zig").install(&s, bindings, receiver, starts, h.arg(args, 0), h.arg(args, 1));
        },
    }
    return c.pi_js_undefined();
}
fn discard(engine: *h.Engine, _: c.JSValue, value: c.JSValue, rejected: bool, _: c_int) anyerror!c.JSValue {
    if (rejected) return engine.checked(c.JS_Throw(engine.context, c.JS_DupValue(engine.context, value)));
    return c.pi_js_undefined();
}
fn construct(engine: *h.Engine, target: c.JSValue, args: []const c.JSValue, captures: []const c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    const bindings = captures[0];
    const result = try s.keep(try h.allocate(engine, target, bindings, .Reload));
    inline for (.{ "host", "facets", "options", "codeVersion" }, 0..) |name, index| try h.field(&s, result, name, h.arg(args, index));
    inline for (.{ "candidates", "services", "tables", "deferred", "facetRuns" }) |name| try h.field(&s, result, name, try h.map(&s));
    inline for (.{ "changed", "removed" }) |name| try h.field(&s, result, name, try h.set(&s));
    inline for (.{ "closed", "gated" }) |name| try h.field(&s, result, name, try s.list());
    try h.field(&s, result, "abort", try s.keep(try js.builtin(engine, "AbortController", &.{})));
    try h.field(&s, result, "rolledBack", c.pi_js_bool(engine.context, 0));
    try h.field(&s, (try h.actor(&s, result, bindings, .Reload)).data, "starts", try s.list());
    return s.result(result);
}
pub fn install(engine: *h.Engine, bindings: c.JSValue) !void {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    try h.field(&s, bindings, "reloadSeq", c.JS_NewInt32(engine.context, 0));
    try h.register(&s, bindings, .Reload);
    const prototype = try s.record();
    try js.define(engine, bindings, "Reload", try @import("native_class.zig").constructor(engine, "Reload", 4, prototype, construct, &.{bindings}));
    inline for (.{ .{ Method.prepare, 0 }, .{ Method.summary, 0 }, .{ Method.waitForRetirement, 0 }, .{ Method.load, 0 }, .{ Method.withDeadline, 2 }, .{ Method.checkProviders, 0 }, .{ Method.prepareAll, 0 }, .{ Method.prepareObject, 1 }, .{ Method.checkRefs, 0 }, .{ Method.entries, 0 }, .{ Method.gate, 0 }, .{ Method.migrate, 1 }, .{ Method.rollback, 0 }, .{ Method.commit, 1 }, .{ Method.install, 2 } }) |entry| try h.define(&s, prototype, bindings, @tagName(entry[0]), callback, @intFromEnum(entry[0]), entry[1], false, asyncMethod(entry[0]));
}
pub fn begin(engine: *h.Engine, bindings: c.JSValue, host: c.JSValue, plugins: c.JSValue, options: c.JSValue, epoch: c.JSValue) anyerror!c.JSValue {
    const pending = beginInner(engine, bindings, host, plugins, options, epoch) catch |err| return @import("native_durable.zig").rejectedPromise(engine, err);
    defer engine.freeValue(pending);
    return @import("native_durable.zig").resolvedPromise(engine, pending);
}
fn beginInner(engine: *h.Engine, bindings: c.JSValue, host: c.JSValue, plugins: c.JSValue, options: c.JSValue, epoch: c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    if (try h.flag(&s, host, "reloading")) return h.throwValue(&s, try h.errorValue(&s, bindings, "unavailable", &.{try s.text("a reload is already running")}, try r.reason(&s, "reload_running")));
    try r.put(&s, host, "reloading", c.pi_js_bool(engine.context, 1));
    const work = try s.record();
    inline for (.{ "bindings", "host", "options", "codeVersion" }, .{ bindings, host, options, epoch }) |name, value| try h.field(&s, work, name, value);
    const pending = h.invoke(&s, host, "resolve", &.{plugins}) catch |err| {
        if (err != error.JavaScriptException) return err;
        const failure = try s.keep(c.JS_DupValue(engine.context, engine.captured_exception.?));
        return beginStep(engine, work, failure, true, 0);
    };
    return h.wait(beginStep, engine, work, pending, 0);
}
fn beginStep(engine: *h.Engine, work: c.JSValue, facets: c.JSValue, rejected: bool, _: c_int) anyerror!c.JSValue {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    const bindings = try s.get(work, "bindings");
    const host = try s.get(work, "host");
    if (!rejected) {
        const result = h.construct(&s, bindings, "Reload", &.{ host, facets, try s.get(work, "options"), try s.get(work, "codeVersion") }) catch |err| {
            _ = try h.invoke(&s, host, "reloadEnded", &.{});
            if (err != error.JavaScriptException) return err;
            return h.throwValue(&s, try r.reloadError(&s, bindings, try s.keep(c.JS_DupValue(engine.context, engine.captured_exception.?))));
        };
        return s.result(result);
    }
    _ = try h.invoke(&s, host, "reloadEnded", &.{});
    return h.throwValue(&s, try r.reloadError(&s, bindings, facets));
}
pub fn run(engine: *h.Engine, bindings: c.JSValue, host: c.JSValue, plugins: c.JSValue, options: c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    const work = try s.record();
    try h.field(&s, work, "host", host);
    const pending = try s.keep(try begin(engine, bindings, host, plugins, options, c.pi_js_undefined()));
    return h.wait(runStep, engine, work, pending, 0);
}
fn runStep(engine: *h.Engine, work: c.JSValue, value: c.JSValue, rejected: bool, phase: c_int) anyerror!c.JSValue {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    if (phase == 0) {
        if (rejected) return h.throwValue(&s, value);
        try h.field(&s, work, "reload", value);
        const pending = h.invoke(&s, value, "prepare", &.{}) catch |err| {
            const original = if (err == error.JavaScriptException) try s.keep(c.JS_DupValue(engine.context, engine.captured_exception.?)) else c.pi_js_undefined();
            try r.endReload(&s, try s.get(work, "host"));
            if (err == error.JavaScriptException) return h.throwValue(&s, original);
            return err;
        };
        return h.wait(runStep, engine, work, pending, 1);
    }
    if (rejected) {
        try r.endReload(&s, try s.get(work, "host"));
        return h.throwValue(&s, value);
    }
    const result = h.invoke(&s, try s.get(work, "reload"), "commit", &.{}) catch |err| {
        const original = if (err == error.JavaScriptException) try s.keep(c.JS_DupValue(engine.context, engine.captured_exception.?)) else c.pi_js_undefined();
        try r.endReload(&s, try s.get(work, "host"));
        if (err == error.JavaScriptException) return h.throwValue(&s, original);
        return err;
    };
    try r.endReload(&s, try s.get(work, "host"));
    return s.result(result);
}
