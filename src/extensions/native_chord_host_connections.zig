//! Source Host accept/connect, connection ownership and peer fencing. Reload hooks have no default handler.
const h = @import("native_chord_host_values.zig");
const js = h.js;
const c = h.c;
const Scope = h.Scope;
const routing = @import("native_chord_host_routing.zig");
pub const ParentLost = *const fn (*Scope, c.JSValue, c.JSValue, c.JSValue) anyerror!void;
pub const ReconcileChild = *const fn (*h.Engine, c.JSValue, c.JSValue, c.JSValue) anyerror!c.JSValue;
pub fn accept(s: *Scope, bindings: c.JSValue, host: c.JSValue, link: c.JSValue, options: c.JSValue) !void {
    const configured = try s.get(options, "kind");
    const kind = if (h.nullish(configured)) try s.text("client") else configured;
    const is_host = try s.equal(kind, "host");
    if (is_host and c.JS_IsUndefined(try s.get(options, "name"))) {
        _ = try h.typeError(s, &.{try s.text("accepting a host link needs its name")});
    }
    const config = try s.record();
    try js.spreadInto(s.engine, config, options);
    try h.field(s, config, "role", try s.text("downstream"));
    try h.field(s, config, "principal", try s.get(options, "principal"));
    const peer = try s.record();
    try h.field(s, peer, "kind", kind);
    try h.field(s, peer, "name", if (is_host) try s.get(options, "name") else c.pi_js_undefined());
    try h.field(s, config, "peer", peer);
    _ = try routing.addConnection(s, bindings, host, link, config);
}
pub fn connect(s: *Scope, bindings: c.JSValue, host: c.JSValue, link: c.JSValue, options_value: c.JSValue) !void {
    const previous = try s.get(host, "upstream");
    if (!h.nullish(previous) and try h.flag(s, previous, "open")) _ = try h.invoke(s, try s.get(try s.get(host, "upstream"), "link"), "close", &.{try s.text("replaced")});
    const config = try s.record();
    const options = if (c.JS_IsUndefined(options_value)) try s.record() else options_value;
    try js.spreadInto(s.engine, config, options);
    try h.field(s, config, "role", try s.text("upstream"));
    try h.field(s, config, "principal", c.pi_js_undefined());
    const peer = try s.record();
    try h.field(s, peer, "kind", try s.text("host"));
    try h.field(s, peer, "name", c.pi_js_undefined());
    try h.field(s, config, "peer", peer);
    const connection = try routing.addConnection(s, bindings, host, link, config);
    try js.setKey(s.engine, host, try s.text("upstream"), connection);
    var iterator = try js.Iterator.init(s.engine, try s.get(host, "remotes"), try h.iteratorSymbol(s));
    defer iterator.deinit();
    errdefer iterator.closePreserving();
    while (try iterator.next()) |handle| {
        defer s.engine.freeValue(handle);
        if (c.JS_IsUndefined(try s.get(handle, "binding"))) _ = try h.invoke(s, connection, "hold", &.{handle});
    }
}
pub fn connectionClosed(s: *Scope, bindings: c.JSValue, host: c.JSValue, connection: c.JSValue, parent_lost: ParentLost) anyerror!void {
    const data = (try h.actor(s, host, bindings, .HostImpl)).data;
    _ = try h.invoke(s, try s.get(host, "connections"), "delete", &.{connection});
    _ = try h.invoke(s, try s.get(data, "deferredHellos"), "delete", &.{connection});
    const foreign = try h.snapshot(s, try s.get(data, "foreign"));
    for (0..try h.length(s, foreign)) |index| {
        const pair = try s.at(foreign, index);
        const values = try js.pair(s.engine, pair, try h.iteratorSymbol(s));
        defer for (values) |value| s.engine.freeValue(value);
        if (c.JS_ToBool(s.engine.context, try h.invoke(s, values[1], "has", &.{connection})) != 0) _ = try h.invoke(s, host, "foreignRootEnded", &.{ values[0], connection });
    }
    const root_links = try h.invoke(s, try s.get(data, "rootLinks"), "values", &.{});
    var iterator = try js.Iterator.init(s.engine, root_links, try h.iteratorSymbol(s));
    defer iterator.deinit();
    errdefer iterator.closePreserving();
    while (try iterator.next()) |links| {
        defer s.engine.freeValue(links);
        _ = try h.invoke(s, links, "delete", &.{connection});
    }
    if (c.JS_IsStrictEqual(s.engine.context, try s.get(host, "upstream"), connection)) {
        try js.setKey(s.engine, host, try s.text("upstream"), c.pi_js_undefined());
        try parent_lost(s, bindings, host, data);
    }
}
pub fn forgetRemote(s: *Scope, host: c.JSValue, handle: c.JSValue) !void {
    _ = try h.invoke(s, try s.get(host, "remotes"), "delete", &.{handle});
}
pub fn route(s: *Scope, bindings: c.JSValue, host: c.JSValue, prefix: c.JSValue, value: c.JSValue) !void {
    const data = (try h.actor(s, host, bindings, .HostImpl)).data;
    _ = try h.invoke(s, try s.get(data, "routes"), "set", &.{ prefix, value });
}
fn rejected(ctx: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, captures: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = h.Engine.fromContext(ctx.?);
    return reconcileFailed(engine, captures[0], captures[1], if (argc > 0) argv[0] else c.pi_js_undefined()) catch |err| @import("native_durable.zig").reject(engine, err);
}
fn reconcileFailed(engine: *h.Engine, host: c.JSValue, connection: c.JSValue, error_value: c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    _ = try h.invoke(&s, host, "report", &.{error_value});
    _ = try h.invoke(&s, try s.get(connection, "link"), "close", &.{try s.text("reconciliation failed")});
    return c.pi_js_undefined();
}
pub fn peerHello(s: *Scope, bindings: c.JSValue, host: c.JSValue, connection: c.JSValue, epoch: c.JSValue, reconcile: ReconcileChild) anyerror!void {
    const ahead = try s.keep(try s.engine.checked(c.JS_PiBinaryOperator(s.engine.context, 6, epoch, try s.get(try s.get(host, "current"), "id"))));
    if (c.JS_ToBool(s.engine.context, ahead) != 0) {
        const failure = try h.errorValue(s, bindings, "invalid", &.{ try s.get(connection, "name"), try s.text(" runs code version "), epoch, try s.text(", ahead of "), try s.get(try s.get(host, "current"), "id") }, c.pi_js_undefined());
        _ = try h.invoke(s, host, "report", &.{failure});
        _ = try h.invoke(s, try s.get(connection, "link"), "close", &.{try s.text("code version ahead of parent")});
        return;
    }
    if (try h.flag(s, host, "reloading")) {
        try js.setKey(s.engine, connection, try s.text("peerCodeVersion"), epoch);
        const behind = try s.keep(try s.engine.checked(c.JS_PiBinaryOperator(s.engine.context, 4, epoch, try s.get(try s.get(host, "current"), "id"))));
        if (c.JS_ToBool(s.engine.context, behind) != 0) _ = try h.invoke(s, try s.get(connection, "fencedCodeVersions"), "add", &.{epoch});
        const data = (try h.actor(s, host, bindings, .HostImpl)).data;
        _ = try h.invoke(s, try s.get(data, "deferredHellos"), "set", &.{ connection, epoch });
        return;
    }
    if (c.JS_IsStrictEqual(s.engine.context, epoch, try s.get(try s.get(host, "current"), "id"))) {
        _ = try h.invoke(s, connection, "markSynced", &.{epoch});
        _ = try h.invoke(s, host, "announceRetired", &.{connection});
        return;
    }
    try js.setKey(s.engine, connection, try s.text("peerCodeVersion"), epoch);
    _ = try h.invoke(s, try s.get(connection, "fencedCodeVersions"), "add", &.{epoch});
    const pending = try s.keep(try reconcile(s.engine, bindings, host, connection));
    var captures = [_]c.JSValue{ host, connection };
    const failed = try s.keep(try s.engine.checked(c.JS_NewCFunctionData2(s.engine.context, rejected, "", 1, 0, 2, &captures)));
    _ = try h.invoke(s, pending, "catch", &.{failed});
}
