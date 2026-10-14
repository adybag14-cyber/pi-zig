//! Actual ChildReloads.handle/run lifetime, with operation registration before the first await.
const r = @import("native_chord_reload_values.zig");
const h = r.h;
const js = r.js;
const c = r.c;
const Scope = r.Scope;
const lifetime = @import("native_chord_child_reload_lifetime.zig");
fn vote(s: *Scope, bindings: c.JSValue, connection: c.JSValue, frame: c.JSValue, value: c.JSValue, failure: bool) !void {
    const message = try s.record();
    try h.field(s, message, "t", try s.text("vote"));
    try h.field(s, message, "reload", try s.get(frame, "reload"));
    try h.field(s, message, if (failure) "error" else "report", if (failure) try h.invoke(s, try s.get(bindings, "Wire"), "toWireError", &.{value}) else value);
    _ = try h.invoke(s, connection, "send", &.{message});
}
pub fn handle(s: *Scope, bindings: c.JSValue, host: c.JSValue, connection: c.JSValue, frame: c.JSValue) anyerror!void {
    const data = (try h.actor(s, host, bindings, .HostImpl)).data;
    if (try s.equal(try s.get(frame, "t"), "prepare")) {
        if (!c.JS_IsUndefined(try s.get(data, "childOperation"))) {
            const failure = try h.errorValue(s, bindings, "unavailable", &.{try s.text("a reload is already running")}, try r.reason(s, "reload_running"));
            try vote(s, bindings, connection, frame, failure, true);
            return;
        }
        const operation = try s.record();
        try h.field(s, operation, "id", try s.get(frame, "reload"));
        try h.field(s, operation, "reload", c.pi_js_undefined());
        try h.field(s, operation, "state", try s.text("loading"));
        try h.field(s, operation, "cancelled", c.pi_js_bool(s.engine.context, 0));
        try h.field(s, data, "childOperation", operation);
        const work = try s.record();
        inline for (.{ "bindings", "host", "data", "operation", "connection", "frame" }, .{ bindings, host, data, operation, connection, frame }) |name, value| try h.field(s, work, name, value);
        const pending = try s.keep(try run(s.engine, work));
        _ = try r.reportPending(s, host, pending);
        return;
    }
    const operation = try s.get(data, "childOperation");
    if (c.JS_IsUndefined(operation) or !c.JS_IsStrictEqual(s.engine.context, try s.get(operation, "id"), try s.get(frame, "reload"))) return;
    if (try s.equal(try s.get(frame, "t"), "abort")) {
        try lifetime.cancel(s, host, data, operation);
        return;
    }
    if (!try s.equal(try s.get(operation, "state"), "prepared")) return;
    try h.field(s, data, "childOperation", c.pi_js_undefined());
    const reload = try s.get(operation, "reload");
    if (!h.nullish(reload)) {
        _ = h.invoke(s, reload, "commit", &.{}) catch |err| {
            const original = if (err == error.JavaScriptException) try s.keep(c.JS_DupValue(s.engine.context, s.engine.captured_exception.?)) else c.pi_js_undefined();
            try lifetime.endReload(s, host);
            if (err == error.JavaScriptException) _ = try h.throwValue(s, original);
            return err;
        };
    }
    try lifetime.endReload(s, host);
}
fn run(engine: *h.Engine, work: c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    const frame = try s.get(work, "frame");
    const pending = try s.keep(try @import("native_chord_reload.zig").begin(engine, try s.get(work, "bindings"), try s.get(work, "host"), try s.get(frame, "plugins"), try s.get(frame, "options"), try s.get(frame, "codeVersion")));
    return h.wait(step, engine, work, pending, 0);
}
fn runFailure(s: *Scope, work: c.JSValue, value: c.JSValue) anyerror!c.JSValue {
    try h.field(s, work, "failure", value);
    const reload = try s.get(try s.get(work, "operation"), "reload");
    if (!c.JS_IsUndefined(reload)) {
        const pending = try r.reportPending(s, try s.get(work, "host"), try h.invoke(s, reload, "rollback", &.{}));
        return h.wait(step, s.engine, work, pending, 2);
    }
    return finish(s, work, false);
}
fn finish(s: *Scope, work: c.JSValue, end: bool) anyerror!c.JSValue {
    if (end) try lifetime.endReload(s, try s.get(work, "host"));
    const operation = try s.get(work, "operation");
    const data = try s.get(work, "data");
    if (c.JS_IsStrictEqual(s.engine.context, try s.get(data, "childOperation"), operation)) try h.field(s, data, "childOperation", c.pi_js_undefined());
    if (!try h.flag(s, operation, "cancelled")) try vote(s, try s.get(work, "bindings"), try s.get(work, "connection"), try s.get(work, "frame"), try s.get(work, "failure"), true);
    return c.pi_js_undefined();
}
fn step(engine: *h.Engine, work: c.JSValue, value: c.JSValue, rejected: bool, phase: c_int) anyerror!c.JSValue {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    if (phase == 2) {
        if (rejected) return h.throwValue(&s, value);
        return finish(&s, work, true);
    }
    if (rejected) return runFailure(&s, work, value);
    return advance(&s, work, value, phase) catch |err| {
        if (err != error.JavaScriptException) return err;
        return runFailure(&s, work, try s.keep(c.JS_DupValue(engine.context, engine.captured_exception.?)));
    };
}
fn advance(s: *Scope, work: c.JSValue, value: c.JSValue, phase: c_int) anyerror!c.JSValue {
    const operation = try s.get(work, "operation");
    if (phase == 0) try r.put(s, operation, "reload", value);
    if (try h.flag(s, operation, "cancelled")) return h.throwValue(s, try h.errorValue(s, try s.get(work, "bindings"), "aborted", &.{try s.text("reload aborted by the server")}, try r.reason(s, "aborted")));
    if (phase == 0) {
        try r.put(s, operation, "state", try s.text("preparing"));
        return h.wait(step, s.engine, work, try h.invoke(s, try s.get(operation, "reload"), "prepare", &.{}), 1);
    }
    try r.put(s, operation, "state", try s.text("prepared"));
    try vote(s, try s.get(work, "bindings"), try s.get(work, "connection"), try s.get(work, "frame"), try h.invoke(s, try s.get(operation, "reload"), "summary", &.{}), false);
    return c.pi_js_undefined();
}
pub const parentLost = lifetime.parentLost;
