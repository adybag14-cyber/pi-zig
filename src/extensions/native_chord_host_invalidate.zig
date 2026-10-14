//! Actual latest principal invalidation, restamping, propagation and holder-first disposal.
const r = @import("native_chord_reload_values.zig");
const h = r.h;
const js = r.js;
const c = r.c;
const Scope = r.Scope;
fn matches(s: *Scope, pattern: c.JSValue, principal: c.JSValue) anyerror!bool {
    if (c.JS_IsFunction(s.engine.context, pattern)) return c.JS_ToBool(s.engine.context, try s.keep(try js.call(s.engine, pattern, c.pi_js_undefined(), &.{principal}))) != 0;
    if (!c.JS_IsObject(principal) or c.JS_IsFunction(s.engine.context, principal)) return false;
    const entries = try s.entries(pattern);
    for (0..try h.length(s, entries)) |index| {
        const entry = try s.at(entries, index);
        if (!try @import("native_chord_canonical.zig").deepEqual(s.engine, try s.key(principal, try s.at(entry, 0)), try s.at(entry, 1))) return false;
    }
    return true;
}
pub fn invalidate(s: *Scope, bindings: c.JSValue, host: c.JSValue, pattern: c.JSValue) anyerror!c.JSValue {
    const reason = try h.errorValue(s, bindings, "gone", &.{try s.text("principal invalidated")}, c.pi_js_undefined());
    const connections = try h.snapshot(s, try s.get(host, "connections"));
    for (0..try h.length(s, connections)) |index| {
        const connection = try s.at(connections, index);
        if (!try s.equal(try s.get(connection, "role"), "downstream") or !try matches(s, pattern, try s.get(connection, "principal"))) continue;
        const restamp = try s.get(connection, "restamp");
        const principal = if (h.nullish(restamp)) c.pi_js_undefined() else try s.keep(try js.call(s.engine, restamp, connection, &.{try s.get(connection, "principal")}));
        _ = try h.invoke(s, connection, "revoke", &.{principal});
    }
    if (!c.JS_IsFunction(s.engine.context, pattern)) {
        var all = try r.iterate(s, try s.get(host, "connections"));
        defer all.deinit();
        errdefer all.closePreserving();
        while (try all.next()) |connection| {
            defer s.engine.freeValue(connection);
            if (!try s.equal(try s.get(connection, "role"), "downstream") or !try s.equal(try s.get(try s.get(connection, "peer"), "kind"), "host")) continue;
            const frame = try s.record();
            try h.field(s, frame, "t", try s.text("invalidate"));
            try h.field(s, frame, "pattern", pattern);
            _ = try h.invoke(s, connection, "send", &.{frame});
        }
    }
    const objects = try h.values(s, try s.get(host, "objects"));
    const matching = try s.list();
    for (0..try h.length(s, objects)) |index| {
        const object = try s.at(objects, index);
        const principal = try s.get(object, "principal");
        if (c.JS_ToBool(s.engine.context, try h.invoke(s, host, "isSelf", &.{principal})) == 0 and try matches(s, pattern, principal)) try js.push(s.engine, matching, object);
    }
    return @import("native_chord_latest_dispose.zig").holders(s.engine, bindings, host, matching, reason, try s.text("invalidatePrincipal: disposal failed"), false);
}
