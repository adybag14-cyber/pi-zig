//! Source Host remote addressing, longest-prefix routes and authorization fenced around every await.
const h = @import("native_chord_host_values.zig");
const js = h.js;
const c = h.c;
const Scope = h.Scope;
const aw = @import("native_chord_async_work.zig");
pub fn remoteAddress(s: *Scope, at: c.JSValue, token: c.JSValue, input: c.JSValue, principal: c.JSValue) !c.JSValue {
    const canonical = @import("native_chord_canonical.zig");
    const destination = try s.keep(try @import("native_utf16.zig").concat(s.engine, &.{ try s.text("@"), at }));
    const header = try s.keep(try @import("native_utf16.zig").concat(s.engine, &.{ destination, try s.text("\x00"), try s.get(token, "name"), try s.text("\x00") }));
    const identity = try s.keep(try canonical.canonicalJson(s.engine, input));
    const addressed = try s.keep(try @import("native_utf16.zig").concat(s.engine, &.{ header, identity, try s.text("\x00") }));
    const key = if (c.JS_IsUndefined(principal)) try s.text("host") else try s.keep(try canonical.canonicalJson(s.engine, principal));
    return s.keep(try @import("native_utf16.zig").concat(s.engine, &.{ addressed, key }));
}
pub fn childNamed(s: *Scope, host: c.JSValue, name: c.JSValue) !c.JSValue {
    const connections = try h.snapshot(s, try s.get(host, "connections"));
    for (0..try h.length(s, connections)) |index| {
        const connection = try s.at(connections, index);
        if (try h.flag(s, connection, "open") and try s.equal(try s.get(connection, "role"), "downstream") and try s.equal(try s.get(try s.get(connection, "peer"), "kind"), "host") and c.JS_IsStrictEqual(s.engine.context, try s.get(try s.get(connection, "peer"), "name"), name)) return connection;
    }
    return c.pi_js_undefined();
}
pub fn routeFor(s: *Scope, data: c.JSValue, host_name: c.JSValue) !c.JSValue {
    const routes = try s.get(data, "routes");
    var iterator = try js.Iterator.init(s.engine, routes, try h.iteratorSymbol(s));
    defer iterator.deinit();
    errdefer iterator.closePreserving();
    var selected = c.pi_js_undefined();
    while (try iterator.next()) |entry| {
        defer s.engine.freeValue(entry);
        if (c.JS_ToBool(s.engine.context, try h.invoke(s, host_name, "startsWith", &.{try s.at(entry, 0)})) == 0) continue;
        if (!c.JS_IsUndefined(selected)) {
            const longer = try s.keep(try s.engine.checked(c.JS_PiBinaryOperator(s.engine.context, 6, try s.get(try s.at(entry, 0), "length"), try s.get(try s.at(selected, 0), "length"))));
            if (c.JS_ToBool(s.engine.context, longer) == 0) continue;
        }
        selected = try s.keep(c.JS_DupValue(s.engine.context, entry));
    }
    return if (h.nullish(selected)) c.pi_js_undefined() else s.at(selected, 1);
}
pub fn addConnection(s: *Scope, bindings: c.JSValue, host: c.JSValue, link: c.JSValue, config: c.JSValue) !c.JSValue {
    const connection = try h.construct(s, bindings, "Connection", &.{ host, link, config });
    if (try h.flag(s, connection, "open")) _ = try h.invoke(s, try s.get(host, "connections"), "add", &.{connection});
    return connection;
}
fn always(_: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue, _: c_int, _: [*c]c.JSValue) callconv(.c) c.JSValue {
    return c.pi_js_bool(null, 1);
}
fn current(ctx: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue, _: c_int, captures: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = h.Engine.fromContext(ctx.?);
    return js.get(engine, captures[0], "current") catch |err| @import("native_durable.zig").reject(engine, err);
}
fn still(s: *Scope, work: c.JSValue) !bool {
    return c.JS_ToBool(s.engine.context, try s.keep(try js.call(s.engine, try s.get(work, "still"), c.pi_js_undefined(), &.{}))) != 0;
}
fn revoked(s: *Scope, work: c.JSValue) !c.JSValue {
    return h.throwValue(s, try h.errorValue(s, try s.get(work, "bindings"), "gone", &.{try s.text("principal invalidated while resolving")}, c.pi_js_undefined()));
}
fn refused(s: *Scope, work: c.JSValue) !c.JSValue {
    return h.throwValue(s, try h.errorValue(s, try s.get(work, "bindings"), "forbidden", &.{ try s.get(work, "hostName"), try s.text(" refused for this principal") }, c.pi_js_undefined()));
}
fn resolveStep(engine: *h.Engine, work: c.JSValue, value: c.JSValue, rejected: bool, phase: c_int) anyerror!void {
    engine.native_exception_diagnostics_suppressed += 1;
    defer engine.native_exception_diagnostics_suppressed -= 1;
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    if (rejected) return aw.complete(&s, work, value, true);
    if ((phase == 1 or phase == 3) and c.JS_ToBool(engine.context, value) == 0) return aw.complete(&s, work, try h.errorValue(&s, try s.get(work, "bindings"), "forbidden", &.{ try s.get(work, "hostName"), try s.text(" refused for this principal") }, c.pi_js_undefined()), true);
    if (!try still(&s, work)) return aw.complete(&s, work, try h.errorValue(&s, try s.get(work, "bindings"), "gone", &.{try s.text("principal invalidated while resolving")}, c.pi_js_undefined()), true);
    const route = try s.get(work, "route");
    const name = try s.get(work, "hostName");
    if (phase == 1) return aw.wait(resolveStep, &s, work, try h.invoke(&s, route, "resolve", &.{name}), 2);
    if (phase == 2) {
        try h.field(&s, work, "link", value);
        return aw.wait(resolveStep, &s, work, try h.invoke(&s, route, "authorize", &.{ try s.get(work, "principal"), name }), 3);
    }
    if (phase == 4) return aw.complete(&s, work, try s.get(work, "connection"), false);
    const host = try s.get(work, "host");
    const link = try s.get(work, "link");
    const connections = try h.snapshot(&s, try s.get(host, "connections"));
    var connection = c.pi_js_undefined();
    for (0..try h.length(&s, connections)) |index| {
        const candidate = try s.at(connections, index);
        if (c.JS_IsStrictEqual(engine.context, try s.get(candidate, "link"), link)) {
            connection = candidate;
            break;
        }
    }
    if (h.nullish(connection)) {
        const config = try s.record();
        try h.field(&s, config, "role", try s.text("downstream"));
        const principal = try s.keep(try js.call(engine, try s.get(route, "principal"), route, &.{name}));
        try h.field(&s, config, "principal", principal);
        const peer = try s.record();
        try h.field(&s, peer, "kind", try s.text("host"));
        try h.field(&s, peer, "name", name);
        try h.field(&s, config, "peer", peer);
        connection = try addConnection(&s, try s.get(work, "bindings"), host, link, config);
    }
    try h.field(&s, work, "connection", connection);
    return aw.wait(resolveStep, &s, work, try h.invoke(&s, connection, "whenSynced", &.{}), 4);
}
pub fn resolve(engine: *h.Engine, bindings: c.JSValue, host: c.JSValue, route: c.JSValue, name: c.JSValue, principal: c.JSValue, guard: c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    const work = try aw.create(&s);
    inline for (.{ "bindings", "host", "route", "hostName", "principal" }, .{ bindings, host, route, name, principal }) |key, value| try h.field(&s, work, key, value);
    const check = if (c.JS_IsUndefined(guard)) try s.keep(try engine.checked(c.JS_NewCFunctionData2(engine.context, always, "still", 0, 0, 0, null))) else guard;
    try h.field(&s, work, "still", check);
    const generation = engine.native_allocation_generation;
    const authorization = h.invoke(&s, route, "authorize", &.{ principal, name });
    if (authorization) |pending| {
        try aw.wait(resolveStep, &s, work, pending, 1);
    } else |err| try aw.rejectErrorSince(&s, work, err, generation);
    return aw.result(&s, work);
}
fn relayStep(engine: *h.Engine, work: c.JSValue, value: c.JSValue, rejected: bool, _: c_int) anyerror!void {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    if (rejected) return aw.complete(&s, work, value, true);
    const held = try s.get(work, "relay");
    if (try h.flag(&s, held, "current")) _ = try h.invoke(&s, held, "open", &.{value});
    try aw.complete(&s, work, c.pi_js_undefined(), false);
}
pub fn relay(engine: *h.Engine, bindings: c.JSValue, host: c.JSValue, held: c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    const data = (try h.actor(&s, host, bindings, .HostImpl)).data;
    const at = try s.get(try s.get(held, "frame"), "at");
    const frame = try s.get(held, "frame");
    const token = try s.keep(try @import("native_chord_contracts_v4.zig").contractFromDescription(engine, try s.get(try s.get(bindings, "errors"), "ChordError"), try s.get(frame, "token")));
    const placement = try s.get(try s.get(token, "description"), "host");
    if (c.JS_IsUndefined(placement) or !c.JS_IsStrictEqual(engine.context, try s.keep(try @import("native_chord_contracts_v4.zig").resolveHost(engine, try s.get(try s.get(bindings, "errors"), "ChordError"), try s.get(try s.get(frame, "token"), "name"), placement, try s.get(frame, "input"))), at)) return h.invalid(&s, bindings, "placement", &.{ try s.get(try s.get(frame, "token"), "name"), try s.text(" with this input does not live on "), at });
    const route = try routeFor(&s, data, at);
    if (c.JS_IsUndefined(route)) {
        const direct = try childNamed(&s, host, at);
        const failure = try h.errorValue(&s, bindings, if (c.JS_IsUndefined(direct)) "unavailable" else "forbidden", &.{ try s.text(if (c.JS_IsUndefined(direct)) "no route to " else "no route authorizes "), at }, c.pi_js_undefined());
        _ = h.throwValue(&s, failure) catch |err| return @import("native_durable.zig").rejectedPromise(engine, err);
    }
    var captures = [_]c.JSValue{held};
    const guard = try s.keep(try engine.checked(c.JS_NewCFunctionData2(engine.context, current, "", 0, 0, 1, &captures)));
    const pending = try s.keep(try resolve(engine, bindings, host, route, at, try s.get(held, "principal"), guard));
    const work = try aw.create(&s);
    try h.field(&s, work, "relay", held);
    try aw.wait(relayStep, &s, work, pending, 0);
    return aw.result(&s, work);
}
fn bindResult(ctx: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, mode: c_int, captures: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = h.Engine.fromContext(ctx.?);
    engine.native_exception_diagnostics_suppressed += 1;
    defer engine.native_exception_diagnostics_suppressed -= 1;
    return bindValue(engine, captures[0], if (argc > 0) argv[0] else c.pi_js_undefined(), mode) catch |err| @import("native_durable.zig").reject(engine, err);
}
fn bindValue(engine: *h.Engine, handle: c.JSValue, value: c.JSValue, mode: c_int) !c.JSValue {
    if (mode == 0) return c.JS_DupValue(engine.context, handle);
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    if (mode == 2) {
        _ = try h.invoke(&s, handle, "gone", &.{value});
    } else if (!try h.flag(&s, handle, "ended") and c.JS_IsUndefined(try s.get(handle, "hold"))) _ = try h.invoke(&s, value, "hold", &.{ handle, c.pi_js_bool(engine.context, 0) });
    return c.pi_js_undefined();
}
fn bindWhenSynced(s: *Scope, handle: c.JSValue, pending: c.JSValue) !void {
    var captures = [_]c.JSValue{handle};
    const fulfilled = try s.keep(try s.engine.checked(c.JS_NewCFunctionData2(s.engine.context, bindResult, "", 1, 1, 1, &captures)));
    const rejected = try s.keep(try s.engine.checked(c.JS_NewCFunctionData2(s.engine.context, bindResult, "", 1, 2, 1, &captures)));
    _ = try h.invoke(s, pending, "then", &.{ fulfilled, rejected });
}
pub fn acquireRemote(s: *Scope, bindings: c.JSValue, host: c.JSValue, token: c.JSValue, at: c.JSValue, input: c.JSValue, options: c.JSValue, owner: c.JSValue) !c.JSValue {
    const first_principal = if (h.nullish(options)) c.pi_js_undefined() else try s.get(options, "principal");
    const principal = if (c.JS_IsUndefined(first_principal) or c.JS_ToBool(s.engine.context, try h.invoke(s, host, "isSelf", &.{try s.get(options, "principal")})) != 0) c.pi_js_undefined() else try s.get(options, "principal");
    const key = try @import("native_chord_host_placement_v4.zig").remoteKey(s, bindings, host, token, input, if (h.nullish(principal)) try s.get(host, "principal") else principal);
    const map = try s.get(host, "bindings");
    var binding = try h.invoke(s, map, "get", &.{key});
    const fresh = c.JS_IsUndefined(binding) or try h.flag(s, binding, "ended");
    if (c.JS_IsUndefined(binding) or try h.flag(s, binding, "ended")) {
        const fields = try s.record();
        inline for (.{ "key", "contract", "at", "input", "principal" }, .{ key, token, at, input, principal }) |name, value| try h.field(s, fields, name, value);
        binding = try h.construct(s, bindings, "RemoteBinding", &.{ host, fields });
        _ = try h.invoke(s, map, "set", &.{ key, binding });
    }
    const state = if (h.nullish(options)) c.pi_js_undefined() else try s.get(options, "state");
    const ref = try h.construct(s, bindings, "RemoteRef", &.{ binding, owner, c.pi_js_bool(s.engine.context, @intFromBool(!c.JS_IsStrictEqual(s.engine.context, state, c.pi_js_bool(s.engine.context, 0)))) });
    const data = (try h.actor(s, host, bindings, .HostImpl)).data;
    _ = try h.invoke(s, try s.get(data, "lingering"), "delete", &.{key});
    _ = try h.invoke(s, binding, "addView", &.{ref});
    if (fresh) try holdBinding(s, bindings, host, binding, at, principal);
    return ref;
}
fn holdBinding(s: *Scope, bindings: c.JSValue, host: c.JSValue, binding: c.JSValue, at: c.JSValue, principal: c.JSValue) !void {
    const direct = try childNamed(s, host, at);
    if (!c.JS_IsUndefined(try s.get(host, "upstream"))) {
        _ = try h.invoke(s, try s.get(host, "upstream"), "hold", &.{ binding, c.pi_js_bool(s.engine.context, 0) });
    } else if (!c.JS_IsUndefined(direct)) {
        const synchronization = try h.invoke(s, direct, "whenSynced", &.{});
        var captures = [_]c.JSValue{direct};
        const target = try s.keep(try s.engine.checked(c.JS_NewCFunctionData2(s.engine.context, bindResult, "", 0, 0, 1, &captures)));
        try bindWhenSynced(s, binding, try h.invoke(s, synchronization, "then", &.{target}));
    } else {
        const data = (try h.actor(s, host, bindings, .HostImpl)).data;
        const route = try routeFor(s, data, at);
        if (c.JS_IsUndefined(route)) {
            _ = try h.invoke(s, binding, "gone", &.{try h.errorValue(s, bindings, "unavailable", &.{ try s.text("no route to "), at }, c.pi_js_undefined())});
        } else try bindWhenSynced(s, binding, try s.keep(try resolve(s.engine, bindings, host, route, at, if (h.nullish(principal)) try s.get(host, "principal") else principal, c.pi_js_undefined())));
    }
}
