//! Actual b45 local-provider state units and live per-member feeds.
const h = @import("native_chord_host_values.zig");
const js = h.js;
const c = h.c;
const Scope = h.Scope;
const flow = @import("native_chord_connection_flow_v4.zig");
const Op = enum(c_int) { unit, send_unit, receive, resend, member, missing, name };
fn callback(ctx: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, magic: c_int, captures: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = h.Engine.fromContext(ctx.?);
    return invoke(engine, captures[0], if (argc > 0) argv[0] else c.pi_js_undefined(), @enumFromInt(magic)) catch |err| @import("native_durable.zig").reject(engine, err);
}
fn function(s: *Scope, work: c.JSValue, op: Op) !c.JSValue {
    var captures = [_]c.JSValue{work};
    return s.keep(try s.engine.checked(c.JS_NewCFunctionData2(s.engine.context, callback, "", 1, @intFromEnum(op), 1, &captures)));
}
pub fn workFor(s: *Scope, bindings: c.JSValue, connection: c.JSValue, served: c.JSValue) !c.JSValue {
    const work = try s.record();
    inline for (.{ "bindings", "connection", "served" }, .{ bindings, connection, served }) |name, value| try h.field(s, work, name, value);
    return work;
}
pub fn shapeListener(s: *Scope, bindings: c.JSValue, connection: c.JSValue, served: c.JSValue) !c.JSValue {
    return function(s, try workFor(s, bindings, connection, served), .unit);
}
fn stopFeeds(s: *Scope, served: c.JSValue) !void {
    const feeds = try s.get(served, "feeds");
    var iterator = try js.Iterator.init(s.engine, try h.invoke(s, feeds, "values", &.{}), try h.iteratorSymbol(s));
    defer iterator.deinit();
    errdefer iterator.closePreserving();
    while (try iterator.next()) |feed| {
        defer s.engine.freeValue(feed);
        _ = try h.invoke(s, feed, "unsubscribe", &.{});
    }
    _ = try h.invoke(s, feeds, "clear", &.{});
}
pub fn wantState(s: *Scope, bindings: c.JSValue, connection: c.JSValue, hold: c.JSValue, wanted: bool) !void {
    const served = try h.invoke(s, try s.get(connection, "served"), "get", &.{hold});
    if (c.JS_IsUndefined(served)) return;
    if (try s.equal(try s.get(served, "kind"), "relay")) {
        _ = try h.invoke(s, try s.get(served, "relay"), "wantState", &.{c.pi_js_bool(s.engine.context, @intFromBool(wanted))});
        return;
    }
    if (c.JS_IsStrictEqual(s.engine.context, try s.get(served, "wantsState"), c.pi_js_bool(s.engine.context, @intFromBool(wanted)))) return;
    try h.field(s, served, "wantsState", c.pi_js_bool(s.engine.context, @intFromBool(wanted)));
    if (wanted) {
        try unit(s, bindings, connection, served);
        return;
    }
    try stopFeeds(s, served);
    try flow.dropHoldState(s, (try h.actor(s, connection, bindings, .Connection)).data, hold);
}
pub fn resync(s: *Scope, bindings: c.JSValue, connection: c.JSValue, hold: c.JSValue, member: c.JSValue) !void {
    const served = try h.invoke(s, try s.get(connection, "served"), "get", &.{hold});
    if (c.JS_IsUndefined(served)) return;
    if (try s.equal(try s.get(served, "kind"), "relay")) {
        _ = try h.invoke(s, try s.get(served, "relay"), "resync", &.{member});
        return;
    }
    if (c.JS_ToBool(s.engine.context, try h.invoke(s, try s.get(served, "feeds"), "has", &.{member})) == 0) return;
    const work = try workFor(s, bindings, connection, served);
    try h.field(s, work, "name", member);
    try flow.resetLater(s, bindings, connection, hold, member, try function(s, work, .resend));
}
pub fn dropServed(s: *Scope, bindings: c.JSValue, connection: c.JSValue, id: c.JSValue, release: bool) !void {
    const map = try s.get(connection, "served");
    const served = try h.invoke(s, map, "get", &.{id});
    if (c.JS_IsUndefined(served)) return;
    _ = try h.invoke(s, map, "delete", &.{id});
    if (try s.equal(try s.get(served, "kind"), "relay")) {
        const options = try s.record();
        try h.field(s, options, "releaseDown", c.pi_js_bool(s.engine.context, @intFromBool(release)));
        try h.field(s, options, "notify", c.pi_js_bool(s.engine.context, 0));
        _ = try h.invoke(s, try s.get(served, "relay"), "close", &.{ try h.errorValue(s, bindings, "released", &.{try s.text("relayed hold released")}, c.pi_js_undefined()), options });
        return;
    }
    try stopFeeds(s, served);
    try flow.dropHoldState(s, (try h.actor(s, connection, bindings, .Connection)).data, id);
    if (release) _ = try h.invoke(s, try s.get(served, "ref"), "release", &.{});
}
fn noop(_: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue) callconv(.c) c.JSValue {
    return c.pi_js_undefined();
}
fn invoke(engine: *h.Engine, work: c.JSValue, arg: c.JSValue, op: Op) !c.JSValue {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    if (op == .name) return js.get(engine, arg, "m");
    const connection = try s.get(work, "connection");
    const bindings = try s.get(work, "bindings");
    const served = try s.get(work, "served");
    switch (op) {
        .unit => try unit(&s, bindings, connection, served),
        .send_unit => try sendUnit(&s, bindings, connection, served),
        .resend => try resend(&s, bindings, connection, served, try s.get(work, "name")),
        .member => {
            const description = try h.invoke(&s, try s.get(served, "ref"), "describe", &.{ try s.get(try s.get(work, "shape"), "variant"), arg });
            return c.pi_js_bool(engine.context, @intFromBool(!h.nullish(description) and try s.equal(try s.get(description, "kind"), "state")));
        },
        .missing => return c.pi_js_bool(engine.context, @intFromBool(c.JS_ToBool(engine.context, try h.invoke(&s, try s.get(served, "feeds"), "has", &.{arg})) == 0)),
        .receive => {
            const feed = try s.get(work, "feed");
            if (c.JS_IsUndefined(try s.get(work, "first"))) {
                try h.field(&s, work, "first", arg);
            } else if (!c.JS_IsUndefined(try s.get(feed, "buffer"))) {
                _ = try h.invoke(&s, try s.get(feed, "buffer"), "push", &.{arg});
            } else try feedEvent(&s, bindings, connection, served, try s.get(work, "name"), feed, arg);
        },
        .name => unreachable,
    }
    return c.pi_js_undefined();
}
fn members(s: *Scope, work: c.JSValue, shape: c.JSValue) !c.JSValue {
    try h.field(s, work, "shape", shape);
    return h.invoke(s, try s.get(shape, "members"), "filter", &.{try function(s, work, .member)});
}
pub fn unit(s: *Scope, bindings: c.JSValue, connection: c.JSValue, served: c.JSValue) !void {
    const id = try s.get(served, "id");
    if (!c.JS_IsStrictEqual(s.engine.context, try h.invoke(s, try s.get(connection, "served"), "get", &.{id}), served)) return;
    const shape = try s.get(try s.get(served, "ref"), "shape");
    if (c.JS_IsUndefined(shape)) return;
    const work = try workFor(s, bindings, connection, served);
    const wanted = try s.keep(try js.builtin(s.engine, "Set", &.{if (try h.flag(s, served, "wantsState")) try members(s, work, shape) else try s.list()}));
    const feeds = try s.get(served, "feeds");
    var iterator = try js.Iterator.init(s.engine, feeds, try h.iteratorSymbol(s));
    defer iterator.deinit();
    errdefer iterator.closePreserving();
    while (try iterator.next()) |pair| {
        defer s.engine.freeValue(pair);
        const name = try s.at(pair, 0);
        if (c.JS_ToBool(s.engine.context, try h.invoke(s, wanted, "has", &.{name})) != 0) continue;
        _ = try h.invoke(s, try s.at(pair, 1), "unsubscribe", &.{});
        _ = try h.invoke(s, feeds, "delete", &.{name});
        const data = (try h.actor(s, connection, bindings, .Connection)).data;
        try flow.dropState(s, data, id, name);
    }
    const urgent = c.JS_IsStrictEqual(s.engine.context, try s.get(feeds, "size"), c.JS_NewInt32(s.engine.context, 0)) and !(try h.flag(s, served, "again") and !try h.flag(s, served, "unitSent"));
    if (urgent) try sendUnit(s, bindings, connection, served) else try flow.queueUnit(s, bindings, connection, id, try function(s, work, .send_unit));
}
pub fn sendUnit(s: *Scope, bindings: c.JSValue, connection: c.JSValue, served: c.JSValue) !void {
    const id = try s.get(served, "id");
    const data = (try h.actor(s, connection, bindings, .Connection)).data;
    _ = try h.invoke(s, try s.get(data, "pending"), "delete", &.{try flow.unitKey(s, id)});
    if (!c.JS_IsStrictEqual(s.engine.context, try h.invoke(s, try s.get(connection, "served"), "get", &.{id}), served)) return;
    const shape = try s.get(try s.get(served, "ref"), "shape");
    if (c.JS_IsUndefined(shape)) return;
    try h.field(s, served, "unitSent", c.pi_js_bool(s.engine.context, 1));
    const work = try workFor(s, bindings, connection, served);
    const state_members = if (try h.flag(s, served, "wantsState")) try members(s, work, shape) else try s.list();
    const listed = try h.invoke(s, state_members, "filter", &.{try function(s, work, .missing)});
    const snaps = try s.list();
    const attached = try s.list();
    var iterator = try js.Iterator.init(s.engine, listed, try h.iteratorSymbol(s));
    defer iterator.deinit();
    errdefer iterator.closePreserving();
    while (try iterator.next()) |name| {
        defer s.engine.freeValue(name);
        const attachment = try attach(s, bindings, connection, served, name, "snap");
        if (c.JS_IsUndefined(attachment)) continue;
        _ = try h.invoke(s, snaps, "push", &.{try s.get(attachment, "frame")});
        const pair = try s.list();
        try js.push(s.engine, pair, name);
        try js.push(s.engine, pair, try s.get(attachment, "feed"));
        _ = try h.invoke(s, attached, "push", &.{pair});
    }
    const frame = try s.record();
    try h.field(s, frame, "t", try s.text("shape"));
    try h.field(s, frame, "id", id);
    if (!c.JS_IsUndefined(try s.get(shape, "variant"))) try h.field(s, frame, "variant", try s.get(shape, "variant"));
    inline for (.{ "members", "contract" }) |field| try h.field(s, frame, field, try s.get(shape, field));
    try h.field(s, frame, "state", try h.invoke(s, snaps, "map", &.{try function(s, work, .name)}));
    _ = try h.invoke(s, connection, "send", &.{frame});
    for (0..try h.length(s, snaps)) |index| _ = try h.invoke(s, connection, "send", &.{try s.at(snaps, index)});
    for (0..try h.length(s, attached)) |index| {
        const pair = try s.at(attached, index);
        try replay(s, bindings, connection, served, try s.at(pair, 0), try s.at(pair, 1));
    }
}
fn snapshot(s: *Scope, bindings: c.JSValue, served: c.JSValue, name: c.JSValue, as: []const u8, value: c.JSValue) !c.JSValue {
    const frame = try s.record();
    try h.field(s, frame, "t", try s.text("state"));
    try h.field(s, frame, "hold", try s.get(served, "id"));
    try h.field(s, frame, "m", name);
    const generation = s.engine.native_allocation_generation;
    @import("native_chord_connection_v2_provider.zig").validateSnapshot(s, bindings, try s.get(served, "ref"), name, value) catch |err| {
        const mapped = s.engine.nativeAllocationError(err, generation);
        if (mapped != error.JavaScriptException) return mapped;
        const failure = s.engine.captured_exception orelse return err;
        try h.field(s, frame, "as", try s.text("error"));
        try h.field(s, frame, "error", try h.invoke(s, try s.get(bindings, "Wire"), "toWireError", &.{failure}));
        return frame;
    };
    try h.field(s, frame, "as", try s.text(as));
    if (!c.JS_IsUndefined(value)) try h.field(s, frame, "value", value);
    return frame;
}
fn attach(s: *Scope, bindings: c.JSValue, connection: c.JSValue, served: c.JSValue, name: c.JSValue, as: []const u8) !c.JSValue {
    const readable = try h.invoke(s, try s.get(served, "ref"), "member", &.{name});
    if (c.JS_IsUndefined(readable) or !c.JS_IsFunction(s.engine.context, try s.get(readable, "events"))) return c.pi_js_undefined();
    const feed = try s.record();
    try h.field(s, feed, "unsubscribe", try s.keep(try s.engine.checked(c.JS_NewCFunction(s.engine.context, noop, "", 0))));
    try h.field(s, feed, "encoder", try h.invoke(s, try s.get(bindings, "DeltaCodec"), "encoder", &.{}));
    try h.field(s, feed, "buffer", try s.list());
    const work = try workFor(s, bindings, connection, served);
    try h.field(s, work, "feed", feed);
    try h.field(s, work, "name", name);
    try h.field(s, work, "first", c.pi_js_undefined());
    try h.field(s, feed, "unsubscribe", try h.invoke(s, readable, "events", &.{try function(s, work, .receive)}));
    _ = try h.invoke(s, try s.get(served, "feeds"), "set", &.{ name, feed });
    const first = try s.get(work, "first");
    const attachment = try s.record();
    try h.field(s, attachment, "frame", try snapshot(s, bindings, served, name, as, if (h.nullish(first)) c.pi_js_undefined() else try s.get(first, "value")));
    try h.field(s, attachment, "feed", feed);
    return attachment;
}
fn replay(s: *Scope, bindings: c.JSValue, connection: c.JSValue, served: c.JSValue, name: c.JSValue, feed: c.JSValue) !void {
    const given = try s.get(feed, "buffer");
    const buffered = if (h.nullish(given)) try s.list() else given;
    try h.field(s, feed, "buffer", c.pi_js_undefined());
    var iterator = try js.Iterator.init(s.engine, buffered, try h.iteratorSymbol(s));
    defer iterator.deinit();
    errdefer iterator.closePreserving();
    while (try iterator.next()) |event| {
        defer s.engine.freeValue(event);
        try feedEvent(s, bindings, connection, served, name, feed, event);
    }
}
fn feedEvent(s: *Scope, bindings: c.JSValue, connection: c.JSValue, served: c.JSValue, name: c.JSValue, feed: c.JSValue, event: c.JSValue) !void {
    if (!c.JS_IsStrictEqual(s.engine.context, try h.invoke(s, try s.get(served, "feeds"), "get", &.{name}), feed)) return;
    const work = try workFor(s, bindings, connection, served);
    try h.field(s, work, "name", name);
    const overflow = try s.record();
    try h.field(s, overflow, "resend", try function(s, work, .resend));
    if (try s.equal(try s.get(event, "type"), "ops")) {
        const frame = try s.record();
        try h.field(s, frame, "t", try s.text("state"));
        try h.field(s, frame, "hold", try s.get(served, "id"));
        try h.field(s, frame, "m", name);
        try h.field(s, frame, "as", try s.text("ops"));
        try h.field(s, frame, "ops", try h.invoke(s, try s.get(feed, "encoder"), "encode", &.{try s.get(event, "ops")}));
        _ = try h.invoke(s, connection, "sendState", &.{ frame, overflow });
    } else {
        try h.field(s, feed, "encoder", try h.invoke(s, try s.get(bindings, "DeltaCodec"), "encoder", &.{}));
        _ = try h.invoke(s, connection, "sendState", &.{ try snapshot(s, bindings, served, name, "reset", try s.get(event, "value")), overflow });
    }
}
fn resend(s: *Scope, bindings: c.JSValue, connection: c.JSValue, served: c.JSValue, name: c.JSValue) !void {
    const feeds = try s.get(served, "feeds");
    const feed = try h.invoke(s, feeds, "get", &.{name});
    if (c.JS_IsUndefined(feed) or !c.JS_IsStrictEqual(s.engine.context, try h.invoke(s, try s.get(connection, "served"), "get", &.{try s.get(served, "id")}), served)) return;
    _ = try h.invoke(s, feed, "unsubscribe", &.{});
    _ = try h.invoke(s, feeds, "delete", &.{name});
    const attachment = try attach(s, bindings, connection, served, name, "reset");
    if (c.JS_IsUndefined(attachment)) return;
    _ = try h.invoke(s, connection, "send", &.{try s.get(attachment, "frame")});
    try replay(s, bindings, connection, served, name, try s.get(attachment, "feed"));
}
