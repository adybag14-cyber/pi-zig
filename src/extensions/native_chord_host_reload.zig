//! Actual Source1692 host reload slots, deferred child hellos, facet signals and cluster dispatch.
const r = @import("native_chord_reload_values.zig");
const h = r.h;
const js = r.js;
const c = r.c;
const Scope = r.Scope;
pub fn initialize(s: *Scope, data: c.JSValue) !void {
    inline for (.{ "deferredHellos", "facetRuns" }) |name| try h.field(s, data, name, try h.map(s));
    try h.field(s, data, "reloadWaiters", try s.list());
    try h.field(s, data, "retirementWatchers", try h.set(s));
    try h.field(s, data, "retireAllowed", c.JS_NewInt32(s.engine.context, 0));
}
pub fn ended(s: *Scope, bindings: c.JSValue, host: c.JSValue) anyerror!void {
    try r.put(s, host, "reloading", c.pi_js_bool(s.engine.context, 0));
    const data = (try h.actor(s, host, bindings, .HostImpl)).data;
    const deferred = try h.snapshot(s, try s.get(data, "deferredHellos"));
    _ = try h.invoke(s, try s.get(data, "deferredHellos"), "clear", &.{});
    for (0..try h.length(s, deferred)) |index| {
        const entry = try s.at(deferred, index);
        const connection = try s.at(entry, 0);
        if (try h.flag(s, connection, "open")) _ = try h.invoke(s, host, "peerHello", &.{ connection, try s.at(entry, 1) });
    }
    const waiters = try h.invoke(s, try s.get(data, "reloadWaiters"), "splice", &.{c.JS_NewInt32(s.engine.context, 0)});
    var iter = try r.iterate(s, waiters);
    defer iter.deinit();
    errdefer iter.closePreserving();
    while (try iter.next()) |resolve| {
        defer s.engine.freeValue(resolve);
        _ = try s.keep(try js.call(s.engine, resolve, c.pi_js_undefined(), &.{}));
    }
    _ = try h.invoke(s, host, "maybeRetire", &.{});
}
fn register(ctx: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, captures: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = h.Engine.fromContext(ctx.?);
    return js.invoke(engine, captures[0], "push", &.{if (argc > 0) argv[0] else c.pi_js_undefined()}) catch |err| @import("native_durable.zig").reject(engine, err);
}
pub fn whenEnded(s: *Scope, bindings: c.JSValue, host: c.JSValue) !c.JSValue {
    if (!try h.flag(s, host, "reloading")) return s.keep(try h.resolved(s.engine, c.pi_js_undefined()));
    const data = (try h.actor(s, host, bindings, .HostImpl)).data;
    var captures = [_]c.JSValue{try s.get(data, "reloadWaiters")};
    const executor = try s.keep(try s.engine.checked(c.JS_NewCFunctionData2(s.engine.context, register, "", 1, 0, 1, &captures)));
    return s.keep(try js.builtin(s.engine, "Promise", &.{executor}));
}
pub fn facetRunChanged(s: *Scope, bindings: c.JSValue, host: c.JSValue, name: c.JSValue, run: c.JSValue) !void {
    const data = (try h.actor(s, host, bindings, .HostImpl)).data;
    const runs = try s.get(data, "facetRuns");
    const replaced = try h.invoke(s, runs, "get", &.{name});
    if (c.JS_IsUndefined(run)) {
        _ = try h.invoke(s, runs, "delete", &.{name});
    } else _ = try h.invoke(s, runs, "set", &.{ name, run });
    if (!c.JS_IsStrictEqual(s.engine.context, replaced, run) and !h.nullish(replaced)) _ = try h.invoke(s, replaced, "abort", &.{try h.errorValue(s, bindings, "gone", &.{ try s.text("facet "), name, try s.text(" was replaced or removed") }, c.pi_js_undefined())});
}
pub fn reload(s: *Scope, bindings: c.JSValue, host: c.JSValue, plugins: c.JSValue, options: c.JSValue) anyerror!c.JSValue {
    if (!try s.equal(try s.get(host, "kind"), "client") and !c.JS_IsUndefined(try s.get(host, "upstream"))) return h.rejected(s.engine, try h.errorValue(s, bindings, "unavailable", &.{try s.text("reloads are coordinated by the server")}, try r.reason(s, "not_coordinator")));
    var children = false;
    const connections = try h.snapshot(s, try s.get(host, "connections"));
    for (0..try h.length(s, connections)) |index| {
        const connection = try s.at(connections, index);
        if (try s.equal(try s.get(connection, "role"), "downstream") and try s.equal(try s.get(try s.get(connection, "peer"), "kind"), "host")) {
            children = true;
            break;
        }
    }
    if (children or !c.JS_IsUndefined(try s.get(options, "remote")) or !c.JS_IsUndefined(try s.get(options, "remoteRemove"))) return @import("native_chord_cluster.zig").run(s.engine, bindings, host, plugins, options);
    return @import("native_chord_reload.zig").run(s.engine, bindings, host, plugins, options);
}
pub fn remember(s: *Scope, host: c.JSValue, remote: c.JSValue, remove: c.JSValue) !void {
    const prefixes = try h.set(s);
    inline for (.{ remote, remove }) |mapping| {
        const keys = try s.keys(if (h.nullish(mapping)) try s.record() else mapping);
        for (0..try h.length(s, keys)) |index| _ = try h.invoke(s, prefixes, "add", &.{try s.at(keys, index)});
    }
    var iter = try r.iterate(s, prefixes);
    defer iter.deinit();
    errdefer iter.closePreserving();
    while (try iter.next()) |prefix| {
        defer s.engine.freeValue(prefix);
        const modules = if (h.nullish(remote)) try s.list() else r.default(s, try s.key(remote, prefix), try s.list());
        const removed = if (h.nullish(remove)) try s.list() else r.default(s, try s.key(remove, prefix), try s.list());
        inline for (.{ "remoteModules", "remoteRemoved" }, .{ modules, removed }, .{ removed, modules }) |name, added, dropped| {
            const target = try s.get(host, name);
            const combined = try r.copySet(s, r.default(s, try s.key(target, prefix), try s.list()));
            var additions = try r.iterate(s, added);
            defer additions.deinit();
            errdefer additions.closePreserving();
            while (try additions.next()) |module| {
                defer s.engine.freeValue(module);
                _ = try h.invoke(s, combined, "add", &.{module});
            }
            const result = try s.list();
            var values = try r.iterate(s, combined);
            defer values.deinit();
            errdefer values.closePreserving();
            while (try values.next()) |module| {
                defer s.engine.freeValue(module);
                if (c.JS_ToBool(s.engine.context, try h.invoke(s, dropped, "includes", &.{module})) == 0) try js.push(s.engine, result, module);
            }
            try js.setKey(s.engine, target, prefix, result);
        }
    }
}
