//! Source Connection closed callback. All iterations keep their Source live/snapshot distinction.
const h = @import("native_chord_host_values.zig");
const js = h.js;
const c = h.c;
pub const DropServed = *const fn (*h.Scope, c.JSValue, c.JSValue, c.JSValue, bool) anyerror!void;
fn each(s: *h.Scope, iterable: c.JSValue, method: [*:0]const u8, value: c.JSValue) !void {
    var iterator = try js.Iterator.init(s.engine, iterable, try h.iteratorSymbol(s));
    defer iterator.deinit();
    errdefer iterator.closePreserving();
    while (try iterator.next()) |entry| {
        defer s.engine.freeValue(entry);
        _ = try h.invoke(s, entry, method, &.{value});
    }
}
pub fn closed(s: *h.Scope, bindings: c.JSValue, receiver: c.JSValue, data: c.JSValue, reason: c.JSValue, dropServed: DropServed) anyerror!void {
    const pinger = try s.get(data, "pinger");
    if (!c.JS_IsUndefined(pinger)) _ = try s.keep(try js.call(s.engine, try s.keep(try js.global(s.engine, "clearInterval")), c.pi_js_undefined(), &.{pinger}));
    const name = try s.get(receiver, "name");
    const failure = try h.errorValue(s, bindings, "unavailable", &.{ try s.text("link to "), if (h.nullish(name)) try s.text("peer") else name, try s.text(" closed: "), reason }, c.pi_js_undefined());
    const served = try h.snapshot(s, try h.invoke(s, try s.get(receiver, "served"), "keys", &.{}));
    for (0..try h.length(s, served)) |index| try dropServed(s, bindings, receiver, try s.at(served, index), true);
    try each(s, try h.invoke(s, try s.get(receiver, "incoming"), "values", &.{}), "abort", failure);
    _ = try h.invoke(s, try s.get(receiver, "incoming"), "clear", &.{});
    try each(s, try h.invoke(s, try s.get(receiver, "calls"), "values", &.{}), "reject", failure);
    _ = try h.invoke(s, try s.get(receiver, "calls"), "clear", &.{});
    _ = try h.invoke(s, try s.get(receiver, "subs"), "clear", &.{});
    try each(s, try h.invoke(s, try s.get(receiver, "votes"), "values", &.{}), "reject", failure);
    _ = try h.invoke(s, try s.get(receiver, "votes"), "clear", &.{});
    try each(s, try s.get(data, "syncWaiters"), "reject", failure);
    _ = try h.invoke(s, try s.get(data, "syncWaiters"), "clear", &.{});
    const relayed = try h.values(s, try s.get(receiver, "relayedHolds"));
    for (0..try h.length(s, relayed)) |index| {
        const options = try s.record();
        try h.field(s, options, "releaseDown", c.pi_js_bool(s.engine.context, 0));
        try h.field(s, options, "notify", c.pi_js_bool(s.engine.context, 1));
        _ = try h.invoke(s, try s.at(relayed, index), "close", &.{ failure, options });
    }
    inline for (.{ "relayedHolds", "relayedCalls", "relayedSubs" }) |key| _ = try h.invoke(s, try s.get(receiver, key), "clear", &.{});
    const remotes = try h.invoke(s, try s.get(receiver, "remotes"), "values", &.{});
    var iterator = try js.Iterator.init(s.engine, remotes, try h.iteratorSymbol(s));
    defer iterator.deinit();
    errdefer iterator.closePreserving();
    while (try iterator.next()) |handle| {
        defer s.engine.freeValue(handle);
        if (try s.equal(try s.get(receiver, "role"), "upstream")) _ = try h.invoke(s, handle, "detached", &.{}) else _ = try h.invoke(s, handle, "gone", &.{failure});
    }
    _ = try h.invoke(s, try s.get(receiver, "remotes"), "clear", &.{});
    _ = try h.invoke(s, try s.get(receiver, "host"), "connectionClosed", &.{receiver});
}
