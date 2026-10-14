//! Actual latest reconcileChild: wait for local reload to end, announce retirement, vote and retry changed versions.
const r = @import("native_chord_reload_values.zig");
const v = @import("native_chord_cluster_values.zig");
const h = r.h;
const c = r.c;
const Scope = r.Scope;
pub fn reconcile(engine: *h.Engine, bindings: c.JSValue, host: c.JSValue, connection: c.JSValue) anyerror!c.JSValue {
    const pending = begin(engine, bindings, host, connection) catch |err| return @import("native_durable.zig").rejectedPromise(engine, err);
    defer engine.freeValue(pending);
    return @import("native_durable.zig").resolvedPromise(engine, pending);
}
fn begin(engine: *h.Engine, bindings: c.JSValue, host: c.JSValue, connection: c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    const work = try s.record();
    inline for (.{ "bindings", "host", "connection" }, .{ bindings, host, connection }) |name, value| try h.field(&s, work, name, value);
    return step(engine, work, c.pi_js_undefined(), false, 0);
}
fn step(engine: *h.Engine, work: c.JSValue, value: c.JSValue, rejected: bool, phase: c_int) anyerror!c.JSValue {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    if (rejected) return h.throwValue(&s, value);
    const host = try s.get(work, "host");
    const connection = try s.get(work, "connection");
    if (phase == 1) {
        const id = try s.get(work, "id");
        if (!c.JS_IsStrictEqual(engine.context, try s.get(try s.get(host, "current"), "id"), try s.get(work, "codeVersion"))) {
            try v.send(&s, connection, try v.frame(&s, "abort", id));
        } else {
            try v.send(&s, connection, try v.frame(&s, "commit", id));
            try r.put(&s, connection, "peerCodeVersion", try s.get(work, "codeVersion"));
        }
    }
    if (!try h.flag(&s, connection, "open")) return c.pi_js_undefined();
    if (try h.flag(&s, host, "reloading")) return h.wait(step, engine, work, try h.invoke(&s, host, "whenReloadEnded", &.{}), 0);
    const version = try s.get(try s.get(host, "current"), "id");
    if (c.JS_IsStrictEqual(engine.context, try s.get(connection, "peerCodeVersion"), version)) {
        _ = try h.invoke(&s, connection, "markSynced", &.{version});
        _ = try h.invoke(&s, host, "announceRetired", &.{connection});
        return c.pi_js_undefined();
    }
    _ = try h.invoke(&s, host, "announceRetired", &.{connection});
    const id = try v.nextId(&s, try s.get(work, "bindings"));
    try h.field(&s, work, "id", id);
    try h.field(&s, work, "codeVersion", version);
    const vote = try v.awaitVote(&s, try s.get(work, "bindings"), connection, id, c.JS_NewInt32(engine.context, 30000));
    const message = try v.frame(&s, "prepare", id);
    try h.field(&s, message, "codeVersion", version);
    try h.field(&s, message, "plugins", try v.modulesFor(&s, try s.get(host, "remoteModules"), try s.get(connection, "name")));
    const options = try s.record();
    try h.field(&s, options, "remove", try v.modulesFor(&s, try s.get(host, "remoteRemoved"), try s.get(connection, "name")));
    try h.field(&s, message, "options", options);
    try v.send(&s, connection, message);
    return h.wait(step, engine, work, vote, 1);
}
