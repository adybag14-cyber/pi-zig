//! Actual local HostImpl ownership and admission; package activation stays gated.
const h = @import("native_chord_host_values.zig");
const Scope = h.Scope;
const js = h.js;
const c = h.c;
const Method = enum(c_int) { codeVersion, previousCodeVersion, report, install, ready, facetApi, serveInto, startHostObject, currentCodeVersion, hasCodeVersion, retainedCodeVersions, pendingCodeVersion, service, addressOf, acquire, forget, touch, root, joinRoot, endRoot, maybeRetire, registry, buildTables, liveDecls, checkRegistrations, registriesChanged, installTables, bindingIdle, forgetBinding, isSelf, get, hold, close, serve, load, resolve, rootSent, foreignRootEnded, nextCodeVersionId, allowRetire, retire, retireImplementation, disposed, retirable, watchRetirement, announceRetired, reloadEnded, whenReloadEnded, facetRunChanged, peekNextCodeVersion, rememberRemoteModules, accept, connect, route, peerHello, connectionClosed, forgetRemote, relay, reload, onReloadFrame, fail, invalidatePrincipal };
fn callback(context: ?*c.JSContext, receiver: c.JSValue, argc: c_int, argv: [*c]c.JSValue, operation: c_int, data: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = h.Engine.fromContext(context.?);
    const method: Method = @enumFromInt(operation);
    const target = if (method == .serve) data[1] else receiver;
    const result = invoke(engine, target, if (argc > 0) argv[0..@intCast(argc)] else &.{}, method, data[0]) catch |err| {
        return if (method == .get or method == .root or method == .joinRoot or method == .close or method == .load or method == .resolve or method == .relay or method == .invalidatePrincipal) @import("native_durable.zig").rejectedPromise(engine, err) else @import("native_durable.zig").reject(engine, err);
    };
    if (method == .root or method == .resolve) {
        defer engine.freeValue(result);
        return @import("native_durable.zig").resolvedPromise(engine, result) catch |err| @import("native_durable.zig").rejectedPromise(engine, err);
    }
    return result;
}
fn options(s: *Scope, input: c.JSValue) !c.JSValue {
    return if (c.JS_IsUndefined(input)) s.record() else input;
}
fn optional(s: *Scope, input: c.JSValue, name: [*:0]const u8) !c.JSValue {
    return if (h.nullish(input)) c.pi_js_undefined() else s.get(input, name);
}
fn service(s: *Scope, receiver: c.JSValue, type_name: c.JSValue, candidate: bool) !c.JSValue {
    const pending = try s.get(receiver, "pending");
    if (candidate and !h.nullish(pending)) {
        const value = try h.invoke(s, try s.get(pending, "services"), "get", &.{type_name});
        if (!h.nullish(value)) return value;
    }
    return h.invoke(s, receiver, "service", &.{type_name});
}
fn unknown(s: *Scope, bindings: c.JSValue, type_name: c.JSValue, host: c.JSValue) !c.JSValue {
    const detail = try s.record();
    try h.field(s, detail, "reason", try s.text("unknown_type"));
    return h.throwValue(s, try h.errorValue(s, bindings, "unavailable", &.{ type_name, try s.text(" is not served by "), try s.get(host, "name") }, detail));
}
fn reaches(s: *Scope, from: c.JSValue, to: c.JSValue) anyerror!bool {
    const seen = try h.set(s);
    const stack = try s.list();
    try js.push(s.engine, stack, from);
    while (try h.length(s, stack) > 0) {
        const record = try h.invoke(s, stack, "pop", &.{});
        if (c.JS_IsStrictEqual(s.engine.context, record, to)) return true;
        if (c.JS_ToBool(s.engine.context, try h.invoke(s, seen, "has", &.{record})) != 0) continue;
        _ = try h.invoke(s, seen, "add", &.{record});
        const declarations = try h.snapshot(s, try h.invoke(s, record, "allDecls", &.{}));
        const count = try h.length(s, declarations);
        for (0..count) |index| {
            const holds = try h.values(s, try s.get(try s.at(declarations, index), "refs"));
            const size = try h.length(s, holds);
            for (0..size) |position| {
                const target = try s.get(try s.at(holds, position), "object");
                if (!c.JS_IsUndefined(target)) try js.push(s.engine, stack, target);
            }
        }
    }
    return false;
}
fn acquire(s: *Scope, host: c.JSValue, args: []const c.JSValue, bindings: c.JSValue) anyerror!c.JSValue {
    const type_value = h.arg(args, 0);
    const settings = h.arg(args, 2);
    const location = try @import("native_chord_host_placement_v4.zig").elsewhere(s, bindings, host, type_value, h.arg(args, 1));
    if (!c.JS_IsUndefined(location)) return s.result(try @import("native_chord_host_routing.zig").acquireRemote(s, bindings, host, type_value, try s.get(location, "at"), try s.get(location, "input"), settings, h.arg(args, 3)));
    const provider = try service(s, host, try s.get(type_value, "name"), c.JS_ToBool(s.engine.context, h.arg(args, 5)) != 0);
    if (c.JS_IsUndefined(provider)) return unknown(s, bindings, try s.get(type_value, "name"), host);
    _ = try h.invoke(s, try s.get(bindings, "contracts"), "bind", &.{ try s.get(provider, "contract"), try s.get(try s.get(provider, "options"), "accepts"), type_value });
    const raw_principal = try optional(s, settings, "principal");
    const located = try @import("native_chord_host_locate.zig").locate(s, bindings, host, provider, h.arg(args, 1), if (h.nullish(raw_principal)) try s.get(host, "principal") else raw_principal);
    const principal = try s.get(located, "principal");
    const normalized = try s.get(located, "normalized");
    try @import("native_chord_host_placement_v4.zig").checkProvider(s, bindings, host, type_value, provider, normalized);
    const key = try s.get(located, "address");
    const records = try s.get(host, "objects");
    var record = try h.invoke(s, records, "get", &.{key});
    const from = h.arg(args, 4);
    if (!c.JS_IsUndefined(from) and !c.JS_IsUndefined(record) and (c.JS_IsStrictEqual(s.engine.context, record, from) or try reaches(s, record, from))) return h.invalid(s, bindings, "cycle", &.{ try s.get(from, "address"), try s.text(" -> "), key, try s.text(" would create a ref cycle") });
    if (c.JS_IsUndefined(record)) {
        const gating = try s.get(host, "gating");
        if (!h.nullish(gating) and c.JS_ToBool(s.engine.context, try h.invoke(s, gating, "has", &.{try s.get(type_value, "name")})) != 0) {
            const detail = try s.record();
            try h.field(s, detail, "reason", try s.text("gate"));
            return h.throwValue(s, try h.errorValue(s, bindings, "upgrade_conflict", &.{ try s.get(type_value, "name"), try s.text(" is being upgraded; retry") }, detail));
        }
        const owned = try h.actor(s, host, bindings, .HostImpl);
        const dying_map = try s.get(owned.data, "dying");
        const dying = try h.invoke(s, dying_map, "get", &.{key});
        if (!h.nullish(dying) and try s.equal(try s.get(dying, "status"), "disposed")) _ = try h.invoke(s, dying_map, "delete", &.{key});
        const identity = try s.record();
        try h.field(s, identity, "address", key);
        try h.field(s, identity, "typeName", try s.get(type_value, "name"));
        try h.field(s, identity, "input", normalized);
        try h.field(s, identity, "principal", principal);
        try h.field(s, identity, "hostLifetime", c.pi_js_bool(s.engine.context, @intFromBool(try @import("native_chord_service.zig").hostLifetime(s, provider))));
        record = try h.construct(s, bindings, "ObjectImpl", &.{ host, identity });
        _ = try h.invoke(s, records, "set", &.{ key, record });
        const after = if (!h.nullish(dying) and try s.equal(try s.get(dying, "status"), "disposing")) try h.invoke(s, dying, "dispose", &.{c.pi_js_bool(s.engine.context, 0)}) else c.pi_js_undefined();
        _ = try h.invoke(s, record, "start", &.{after});
    }
    const handle = try h.construct(s, bindings, "RefImpl", &.{ record, type_value, h.arg(args, 3) });
    _ = try h.invoke(s, record, "addRef", &.{handle});
    return s.result(handle);
}
fn noop(_: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue, _: c_int, _: [*c]c.JSValue) callconv(.c) c.JSValue {
    return c.pi_js_undefined();
}
fn eagerReady(s: *Scope, input: c.JSValue) !c.JSValue {
    const holds = try h.snapshot(s, input);
    const reader = try s.keep(try s.engine.checked(c.JS_NewCFunctionData2(s.engine.context, holdReady, "", 1, 0, 0, null)));
    const values = try h.invoke(s, holds, "map", &.{reader});
    const promise_type = try s.keep(try js.global(s.engine, "Promise"));
    const all = try h.invoke(s, promise_type, "all", &.{values});
    const nothing = try s.keep(try s.engine.checked(c.JS_NewCFunctionData2(s.engine.context, noop, "", 0, 0, 0, null)));
    const ready = try h.invoke(s, all, "then", &.{nothing});
    _ = try h.invoke(s, ready, "catch", &.{nothing});
    return s.result(ready);
}
fn holdReady(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, _: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = h.Engine.fromContext(context.?);
    return js.get(engine, if (argc > 0) argv[0] else c.pi_js_undefined(), "ready") catch |err| @import("native_durable.zig").reject(engine, err);
}
fn facetServe(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, data: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = h.Engine.fromContext(context.?);
    return serveFacet(engine, if (argc > 0) argv[0..@intCast(argc)] else &.{}, data) catch |err| @import("native_durable.zig").reject(engine, err);
}
fn serveFacet(engine: *h.Engine, args: []const c.JSValue, data: [*c]c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    const provider = try @import("native_chord_service.zig").make(&s, data[3], h.arg(args, 0), h.arg(args, 1), try options(&s, h.arg(args, 2)), try s.get(data[1], "name"));
    _ = try h.invoke(&s, data[0], "serveInto", &.{ try s.get(try s.get(data[0], "current"), "services"), provider });
    _ = try h.invoke(&s, data[2], "push", &.{provider});
    return c.pi_js_undefined();
}
fn facetForward(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, operation: c_int, data: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = h.Engine.fromContext(context.?);
    var args = [_]c.JSValue{ if (argc > 0) argv[0] else c.pi_js_undefined(), if (argc > 1) argv[1] else c.pi_js_undefined() };
    return js.invoke(engine, data[0], if (operation == 0) "root" else "registry", args[0..if (operation == 0) @as(usize, 2) else 1]) catch |err| @import("native_durable.zig").reject(engine, err);
}
fn reportFailure(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, data: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = h.Engine.fromContext(context.?);
    return js.invoke(engine, data[0], "report", &.{if (argc > 0) argv[0] else c.pi_js_undefined()}) catch |err| @import("native_durable.zig").reject(engine, err);
}
fn joinRoot(s: *Scope, host: c.JSValue, args: []const c.JSValue, bindings: c.JSValue) anyerror!c.JSValue {
    const root_id = h.arg(args, 0);
    const epoch_id = h.arg(args, 1);
    const function = h.arg(args, 2);
    const settings = try options(s, h.arg(args, 3));
    const epoch = try h.invoke(s, try s.get(host, "codeVersions"), "get", &.{epoch_id});
    const owned = try h.actor(s, host, bindings, .HostImpl);
    if (c.JS_IsUndefined(epoch)) {
        _ = try h.invoke(s, try s.get(owned.data, "local"), "delete", &.{root_id});
        return h.throwValue(s, try h.errorValue(s, bindings, "superseded", &.{ try s.text("code version "), epoch_id, try s.text(" is not retained by "), try s.get(host, "name") }, c.pi_js_undefined()));
    }
    const from = try s.get(settings, "from");
    if (!c.JS_IsUndefined(from) and c.JS_ToBool(s.engine.context, try h.invoke(s, try s.get(owned.data, "local"), "has", &.{root_id})) == 0) {
        const foreign = try s.get(owned.data, "foreign");
        var links = try h.invoke(s, foreign, "get", &.{root_id});
        if (c.JS_IsUndefined(links)) {
            links = try h.set(s);
            _ = try h.invoke(s, foreign, "set", &.{ root_id, links });
        }
        _ = try h.invoke(s, links, "add", &.{from});
    }
    const roots = try s.get(epoch, "roots");
    const previous = try h.invoke(s, roots, "get", &.{root_id});
    var count: f64 = 0;
    if (!h.nullish(previous) and c.JS_ToFloat64(s.engine.context, &count, previous) < 0) return js.capture(s.engine);
    _ = try h.invoke(s, roots, "set", &.{ root_id, c.JS_NewFloat64(s.engine.context, count + 1) });
    const fields = try s.record();
    const signal = try s.get(settings, "signal");
    const signals = try s.list();
    if (!c.JS_IsUndefined(signal)) try js.push(s.engine, signals, signal);
    try js.push(s.engine, signals, try s.get(try s.get(epoch, "abort"), "signal"));
    try h.field(s, fields, "signals", signals);
    try h.field(s, fields, "rootId", root_id);
    try h.field(s, fields, "codeVersion", try s.get(epoch, "id"));
    const principal = try s.get(settings, "principal");
    try h.field(s, fields, "principal", if (h.nullish(principal)) try s.get(host, "principal") else principal);
    const ctx = try h.construct(s, bindings, "CtxImpl", &.{ host, fields });
    const work = try s.record();
    try h.field(s, work, "bindings", bindings);
    try h.field(s, work, "host", host);
    try h.field(s, work, "ctx", ctx);
    try h.field(s, work, "codeVersion", epoch);
    try h.field(s, work, "rootId", root_id);
    const called = js.call(s.engine, function, c.pi_js_undefined(), &.{ctx}) catch |err| {
        if (err != error.JavaScriptException) return err;
        return finishRoot(s.engine, work, s.engine.captured_exception orelse return err, true, 0);
    };
    defer s.engine.freeValue(called);
    return h.wait(finishRoot, s.engine, work, called, 0);
}
fn finishRoot(engine: *h.Engine, work: c.JSValue, value: c.JSValue, rejected: bool, _: c_int) !c.JSValue {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    _ = try h.invoke(&s, try s.get(work, "ctx"), "close", &.{});
    const roots = try s.get(try s.get(work, "codeVersion"), "roots");
    const root_id = try s.get(work, "rootId");
    const current = try h.invoke(&s, roots, "get", &.{root_id});
    var count: f64 = 1;
    if (!h.nullish(current) and c.JS_ToFloat64(engine.context, &count, current) < 0) return js.capture(engine);
    count -= 1;
    if (count > 0) {
        _ = try h.invoke(&s, roots, "set", &.{ root_id, c.JS_NewFloat64(engine.context, count) });
    } else {
        _ = try h.invoke(&s, roots, "delete", &.{root_id});
        const host = try s.get(work, "host");
        const bindings = (try h.actor(&s, host, try s.get(work, "bindings"), .HostImpl)).bindings;
        const owned = try h.actor(&s, host, bindings, .HostImpl);
        if (c.JS_ToBool(engine.context, try h.invoke(&s, try s.get(owned.data, "foreign"), "has", &.{root_id})) == 0) _ = try h.invoke(&s, host, "endRoot", &.{root_id});
        _ = try h.invoke(&s, host, "maybeRetire", &.{});
        try @import("native_chord_host_versions.zig").changed(&s, bindings, host);
    }
    return if (rejected) engine.checked(c.JS_Throw(engine.context, s.result(value))) else s.result(value);
}
fn liveDecls(s: *Scope, host: c.JSValue, candidates: bool) !c.JSValue {
    const result = try s.list();
    const records = try h.values(s, try s.get(host, "objects"));
    const count = try h.length(s, records);
    for (0..count) |index| {
        const record = try s.at(records, index);
        if (!try s.equal(try s.get(record, "status"), "live") or (!candidates and try h.flag(s, record, "deferredRuntime"))) continue;
        const pair = try s.list();
        try js.push(s.engine, pair, record);
        try js.push(s.engine, pair, try s.get(record, "decls"));
        try js.push(s.engine, result, pair);
    }
    return result;
}
fn excluding(s: *Scope, entries: c.JSValue, record: c.JSValue) !c.JSValue {
    const result = try s.list();
    const count = try h.length(s, entries);
    for (0..count) |index| {
        const entry = try s.at(entries, index);
        if (!c.JS_IsStrictEqual(s.engine.context, try s.at(entry, 0), record)) try js.push(s.engine, result, entry);
    }
    return result;
}
fn invoke(engine: *h.Engine, receiver: c.JSValue, args: []const c.JSValue, method: Method, bindings: c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    if (method == .bindingIdle or method == .forgetBinding) {
        const api = @import("native_chord_host_bindings_v4.zig");
        if (method == .bindingIdle) try api.idle(&s, receiver, bindings, h.arg(args, 0)) else try api.forget(&s, receiver, bindings, h.arg(args, 0));
        return c.pi_js_undefined();
    }
    if (method == .isSelf) {
        const principal = h.arg(args, 0);
        if (c.JS_IsStrictEqual(engine.context, principal, try s.get(receiver, "principal"))) return c.pi_js_bool(engine.context, 1);
        const data = (try h.actor(&s, receiver, bindings, .HostImpl)).data;
        const key = try s.keep(try js.call(engine, try s.get(data, "principalKey"), receiver, &.{principal}));
        return c.pi_js_bool(engine.context, @intFromBool(c.JS_IsStrictEqual(engine.context, key, try s.get(data, "selfKey"))));
    }
    if (method == .invalidatePrincipal) return @import("native_chord_host_invalidate.zig").invalidate(&s, bindings, receiver, h.arg(args, 0));
    if (method == .resolve) return @import("native_chord_host_load.zig").resolve(engine, bindings, receiver, h.arg(args, 0));
    if (method == .retire or method == .retireImplementation or method == .allowRetire or method == .retirable or method == .watchRetirement or method == .announceRetired) {
        const versions = @import("native_chord_host_versions.zig");
        switch (method) {
            .retire => try versions.retire(&s, bindings, receiver),
            .retireImplementation => try versions.retireImplementation(&s, receiver, h.arg(args, 0), h.arg(args, 1)),
            .allowRetire => try versions.allow(&s, bindings, receiver, h.arg(args, 0)),
            .retirable => return c.pi_js_bool(engine.context, @intFromBool(try versions.retirable(&s, bindings, receiver))),
            .watchRetirement => return s.result(try versions.watch(&s, bindings, receiver, h.arg(args, 0))),
            .announceRetired => try versions.announce(&s, receiver, h.arg(args, 0)),
            else => unreachable,
        }
        return c.pi_js_undefined();
    }
    if (method == .retainedCodeVersions) return s.result(try @import("native_chord_host_retained.zig").iterate(&s, receiver));
    if (method == .reloadEnded or method == .whenReloadEnded or method == .facetRunChanged or method == .rememberRemoteModules or method == .reload) {
        const reload_api = @import("native_chord_host_reload.zig");
        switch (method) {
            .reloadEnded => try reload_api.ended(&s, bindings, receiver),
            .whenReloadEnded => return s.result(try reload_api.whenEnded(&s, bindings, receiver)),
            .facetRunChanged => try reload_api.facetRunChanged(&s, bindings, receiver, h.arg(args, 0), h.arg(args, 1)),
            .rememberRemoteModules => try reload_api.remember(&s, receiver, h.arg(args, 0), h.arg(args, 1)),
            .reload => return reload_api.reload(&s, bindings, receiver, h.arg(args, 0), try options(&s, h.arg(args, 1))),
            else => unreachable,
        }
        return c.pi_js_undefined();
    }
    if (method == .accept or method == .connect or method == .route or method == .peerHello or method == .connectionClosed or method == .forgetRemote or method == .onReloadFrame) {
        const connections = @import("native_chord_host_connections.zig");
        switch (method) {
            .accept => try connections.accept(&s, bindings, receiver, h.arg(args, 0), h.arg(args, 1)),
            .connect => try connections.connect(&s, bindings, receiver, h.arg(args, 0), h.arg(args, 1)),
            .route => try connections.route(&s, bindings, receiver, h.arg(args, 0), h.arg(args, 1)),
            .peerHello => try connections.peerHello(&s, bindings, receiver, h.arg(args, 0), h.arg(args, 1), @import("native_chord_cluster_reconcile.zig").reconcile),
            .connectionClosed => try connections.connectionClosed(&s, bindings, receiver, h.arg(args, 0), @import("native_chord_child_reload.zig").parentLost),
            .forgetRemote => try connections.forgetRemote(&s, receiver, h.arg(args, 0)),
            .onReloadFrame => try @import("native_chord_child_reload.zig").handle(&s, bindings, receiver, h.arg(args, 0), h.arg(args, 1)),
            else => unreachable,
        }
        return c.pi_js_undefined();
    }
    if (method == .relay) return @import("native_chord_host_routing.zig").relay(engine, bindings, receiver, h.arg(args, 0));
    if (method == .peekNextCodeVersion) {
        const data = (try h.actor(&s, receiver, bindings, .HostImpl)).data;
        return engine.checked(c.JS_PiBinaryOperator(engine.context, 0, try s.get(data, "codeVersionSeq"), c.JS_NewInt32(engine.context, 1)));
    }
    if (method == .fail) {
        if (h.nullish(try s.get(receiver, "failed"))) try h.field(&s, receiver, "failed", h.arg(args, 0));
        _ = try h.invoke(&s, receiver, "report", &.{h.arg(args, 0)});
        return c.pi_js_undefined();
    }
    if (method == .disposed) {
        const dying = try s.get((try h.actor(&s, receiver, bindings, .HostImpl)).data, "dying");
        const object = h.arg(args, 0);
        const address_value = try s.get(object, "address");
        if (c.JS_IsStrictEqual(engine.context, try h.invoke(&s, dying, "get", &.{address_value}), object)) _ = try h.invoke(&s, dying, "delete", &.{address_value});
        return c.pi_js_undefined();
    }
    if (method == .load) return @import("native_chord_host_load.zig").load(engine, receiver, h.arg(args, 0), try options(&s, h.arg(args, 1)));
    if (method == .nextCodeVersionId) {
        const given = h.arg(args, 0);
        const current = try s.get(try s.get(receiver, "current"), "id");
        var value: f64 = 0;
        var now: f64 = 0;
        if (!c.JS_IsUndefined(given)) {
            if (c.JS_ToFloat64(engine.context, &value, given) < 0 or c.JS_ToFloat64(engine.context, &now, current) < 0) return js.capture(engine);
            if (value <= now) return h.ordinaryError(&s, &.{ try s.text("code version "), given, try s.text(" is not newer than "), current });
        }
        const data = (try h.actor(&s, receiver, bindings, .HostImpl)).data;
        const next = if (!h.nullish(given)) given else next: {
            if (c.JS_ToFloat64(engine.context, &value, try s.get(data, "codeVersionSeq")) < 0) return js.capture(engine);
            break :next c.JS_NewFloat64(engine.context, value + 1);
        };
        try h.field(&s, data, "codeVersionSeq", next);
        return s.result(next);
    }
    if (method == .rootSent) {
        const sent = try s.get((try h.actor(&s, receiver, bindings, .HostImpl)).data, "rootLinks");
        var links = try h.invoke(&s, sent, "get", &.{h.arg(args, 0)});
        if (c.JS_IsUndefined(links)) {
            links = try h.set(&s);
            _ = try h.invoke(&s, sent, "set", &.{ h.arg(args, 0), links });
        }
        _ = try h.invoke(&s, links, "add", &.{h.arg(args, 1)});
        return c.pi_js_undefined();
    }
    if (method == .foreignRootEnded) {
        const foreign = try s.get((try h.actor(&s, receiver, bindings, .HostImpl)).data, "foreign");
        const root_id = h.arg(args, 0);
        const links = try h.invoke(&s, foreign, "get", &.{root_id});
        if (c.JS_IsUndefined(links) or c.JS_ToBool(engine.context, try h.invoke(&s, links, "delete", &.{h.arg(args, 1)})) == 0 or c.JS_ToBool(engine.context, try s.get(links, "size")) != 0) return c.pi_js_undefined();
        const epochs = try h.values(&s, try s.get(receiver, "codeVersions"));
        var running = false;
        for (0..try h.length(&s, epochs)) |index| {
            if (c.JS_ToBool(engine.context, try h.invoke(&s, try s.get(try s.at(epochs, index), "roots"), "has", &.{root_id})) != 0) {
                running = true;
                break;
            }
        }
        _ = try h.invoke(&s, if (running) foreign else receiver, if (running) "delete" else "endRoot", &.{root_id});
        return c.pi_js_undefined();
    }
    if (method == .allowRetire) {
        const data = (try h.actor(&s, receiver, bindings, .HostImpl)).data;
        try h.field(&s, data, "retireAllowed", try h.invoke(&s, try s.keep(try js.global(engine, "Math")), "max", &.{ try s.get(data, "retireAllowed"), h.arg(args, 0) }));
        return js.invoke(engine, receiver, "maybeRetire", &.{});
    }
    if (method == .codeVersion or method == .currentCodeVersion) return js.get(engine, try s.get(receiver, "current"), "id");
    if (method == .previousCodeVersion or method == .pendingCodeVersion) {
        const state = try s.get(receiver, if (method == .previousCodeVersion) "previous" else "pending");
        return if (h.nullish(state)) c.pi_js_undefined() else js.get(engine, state, "id");
    }
    if (method == .report) {
        const owned = try h.actor(&s, receiver, bindings, .HostImpl);
        _ = try s.keep(try js.call(engine, try s.get(owned.data, "onError"), receiver, &.{h.arg(args, 0)}));
        return c.pi_js_undefined();
    }
    if (method == .serve) {
        if (try h.flag(&s, receiver, "reloading")) return h.ordinaryError(&s, &.{try s.text("host.serve during a reload; serve from a facet passed to reload()")});
        const settings = try options(&s, h.arg(args, 2));
        const provider = try @import("native_chord_service.zig").make(&s, bindings, h.arg(args, 0), h.arg(args, 1), settings, try s.text(""));
        _ = try h.invoke(&s, receiver, "serveInto", &.{ try s.get(try s.get(receiver, "current"), "services"), provider });
        if (try s.equal(try s.get(settings, "lifetime"), "host")) _ = try h.invoke(&s, receiver, "startHostObject", &.{try h.invoke(&s, try s.get(try s.get(receiver, "current"), "services"), "get", &.{try s.get(h.arg(args, 0), "name")})});
        return c.pi_js_undefined();
    }
    if (method == .serveInto) {
        const providers = h.arg(args, 0);
        const provider = h.arg(args, 1);
        const name = try s.get(try s.get(provider, "contract"), "name");
        if (c.JS_ToBool(engine.context, try h.invoke(&s, providers, "has", &.{name})) != 0) return h.ordinaryError(&s, &.{ name, try s.text(" is already served") });
        _ = try h.invoke(&s, providers, "set", &.{ name, provider });
        return c.pi_js_undefined();
    }
    if (method == .facetApi) {
        const api = try s.record();
        try h.field(&s, api, "serve", h.arg(args, 0));
        try h.field(&s, api, "name", try s.get(receiver, "name"));
        inline for (.{ "root", "registry" }, 0..) |name, operation| {
            var captures = [_]c.JSValue{receiver};
            try js.define(engine, api, name, try engine.checked(c.JS_NewCFunctionData2(engine.context, facetForward, name, if (operation == 0) 2 else 1, @intCast(operation), 1, &captures)));
        }
        try h.field(&s, api, "signal", h.arg(args, 1));
        return s.result(api);
    }
    if (method == .install) {
        if (try h.flag(&s, receiver, "reloading")) return h.ordinaryError(&s, &.{try s.text("host.install during a reload")});
        const facet = h.arg(args, 0);
        const settings = try options(&s, h.arg(args, 1));
        const facets = try s.get(receiver, "facets");
        if (c.JS_ToBool(engine.context, try h.invoke(&s, facets, "has", &.{try s.get(facet, "name")})) != 0) return h.ordinaryError(&s, &.{ try s.text("facet "), try s.get(facet, "name"), try s.text(" is already installed; use reload()") });
        const added = try s.list();
        const run = try s.keep(try js.builtin(engine, "AbortController", &.{}));
        var captures = [_]c.JSValue{ receiver, facet, added, bindings };
        const serve_function = try s.keep(try engine.checked(c.JS_NewCFunctionData2(engine.context, facetServe, "", 2, 0, 4, &captures)));
        const api = try h.invoke(&s, receiver, "facetApi", &.{ serve_function, try s.get(run, "signal") });
        _ = h.invoke(&s, facet, "setup", &.{api}) catch |err| {
            const failure = if (err == error.JavaScriptException) try s.keep(c.JS_DupValue(engine.context, engine.captured_exception.?)) else c.pi_js_undefined();
            _ = try h.invoke(&s, run, "abort", &.{failure});
            if (err == error.JavaScriptException) return h.throwValue(&s, failure);
            return err;
        };
        _ = try h.invoke(&s, facets, "set", &.{ try s.get(facet, "name"), facet });
        _ = try h.invoke(&s, receiver, "facetRunChanged", &.{ try s.get(facet, "name"), run });
        const holds = try s.list();
        const count = try h.length(&s, added);
        for (0..count) |index| {
            const provider = try s.at(added, index);
            if (try @import("native_chord_service.zig").hostLifetime(&s, provider)) try js.push(engine, holds, try h.invoke(&s, receiver, "startHostObject", &.{provider}));
        }
        if (c.JS_IsStrictEqual(engine.context, try s.get(settings, "awaitHostObjects"), c.pi_js_bool(engine.context, 0))) {
            const promise_type = try s.keep(try js.global(engine, "Promise"));
            return js.invoke(engine, promise_type, "resolve", &.{});
        }
        return eagerReady(&s, holds);
    }
    if (method == .startHostObject) {
        const provider = h.arg(args, 0);
        const input = try s.record();
        const handle = try h.invoke(&s, receiver, "acquire", &.{ try s.get(provider, "contract"), input, c.pi_js_undefined(), try s.text("host") });
        _ = try h.invoke(&s, try s.get(receiver, "hostObjects"), "set", &.{ try s.get(try s.get(provider, "contract"), "name"), handle });
        var captures = [_]c.JSValue{receiver};
        const observer = try s.keep(try engine.checked(c.JS_NewCFunctionData2(engine.context, reportFailure, "", 1, 0, 1, &captures)));
        _ = try h.invoke(&s, try s.get(handle, "ready"), "catch", &.{observer});
        return s.result(handle);
    }
    if (method == .ready) return eagerReady(&s, try h.invoke(&s, try s.get(receiver, "hostObjects"), "values", &.{}));
    if (method == .hasCodeVersion) return js.invoke(engine, try s.get(receiver, "codeVersions"), "has", &.{h.arg(args, 0)});
    if (method == .service) {
        const current = try h.invoke(&s, try s.get(try s.get(receiver, "current"), "services"), "get", &.{h.arg(args, 0)});
        if (!h.nullish(current)) return s.result(current);
        const pending = try s.get(receiver, "pending");
        return if (h.nullish(pending)) c.pi_js_undefined() else js.invoke(engine, try s.get(pending, "services"), "get", &.{h.arg(args, 0)});
    }
    if (method == .addressOf) {
        const type_value = h.arg(args, 0);
        const principal = h.arg(args, 2);
        const location = try @import("native_chord_host_placement_v4.zig").elsewhere(&s, bindings, receiver, type_value, h.arg(args, 1));
        if (!c.JS_IsUndefined(location)) return s.result(try @import("native_chord_host_placement_v4.zig").remoteKey(&s, bindings, receiver, type_value, try s.get(location, "input"), principal));
        const provider = try service(&s, receiver, try s.get(type_value, "name"), c.JS_ToBool(engine.context, h.arg(args, 3)) != 0);
        if (c.JS_IsUndefined(provider)) return unknown(&s, bindings, try s.get(type_value, "name"), receiver);
        return s.result(try s.get(try @import("native_chord_host_locate.zig").locate(&s, bindings, receiver, provider, h.arg(args, 1), principal), "address"));
    }
    if (method == .acquire) return acquire(&s, receiver, args, bindings);
    if (method == .forget) {
        const record = h.arg(args, 0);
        const records = try s.get(receiver, "objects");
        const key = try s.get(record, "address");
        if (c.JS_IsStrictEqual(engine.context, try h.invoke(&s, records, "get", &.{key}), record)) _ = try h.invoke(&s, records, "delete", &.{key});
        if (try s.equal(try s.get(record, "status"), "disposing")) _ = try h.invoke(&s, try s.get((try h.actor(&s, receiver, bindings, .HostImpl)).data, "dying"), "set", &.{ key, record });
        return c.pi_js_undefined();
    }
    if (method == .touch) {
        const owned = try h.actor(&s, receiver, bindings, .HostImpl);
        const touches = try s.get(owned.data, "touches");
        var touched = try h.invoke(&s, touches, "get", &.{h.arg(args, 0)});
        if (c.JS_IsUndefined(touched)) {
            touched = try h.set(&s);
            _ = try h.invoke(&s, touches, "set", &.{ h.arg(args, 0), touched });
        }
        _ = try h.invoke(&s, touched, "add", &.{h.arg(args, 1)});
        return c.pi_js_undefined();
    }
    if (method == .root) {
        const settings = try options(&s, h.arg(args, 1));
        const owned = try h.actor(&s, receiver, bindings, .HostImpl);
        var count: f64 = undefined;
        if (c.JS_ToFloat64(engine.context, &count, try s.get(owned.data, "rootSeq")) < 0) return js.capture(engine);
        const sequence = c.JS_NewFloat64(engine.context, count + 1);
        try h.field(&s, owned.data, "rootSeq", sequence);
        const root_id = try s.keep(try @import("native_utf16.zig").concat(engine, &.{ try s.get(receiver, "name"), try s.text("#"), try s.get(owned.data, "incarnation"), try s.text(":"), sequence }));
        _ = try h.invoke(&s, try s.get(owned.data, "local"), "add", &.{root_id});
        const epoch = try s.get(settings, "codeVersion");
        return js.invoke(engine, receiver, "joinRoot", &.{ root_id, if (h.nullish(epoch)) try s.get(try s.get(receiver, "current"), "id") else epoch, h.arg(args, 0), settings });
    }
    if (method == .joinRoot) return joinRoot(&s, receiver, args, bindings);
    if (method == .endRoot) {
        const owned = try h.actor(&s, receiver, bindings, .HostImpl);
        const root_id = h.arg(args, 0);
        inline for (.{ "local", "foreign" }) |name| _ = try h.invoke(&s, try s.get(owned.data, name), "delete", &.{root_id});
        const touches = try s.get(owned.data, "touches");
        const touched = try h.invoke(&s, touches, "get", &.{root_id});
        if (!h.nullish(touched)) {
            var records = try js.Iterator.init(engine, touched, try h.iteratorSymbol(&s));
            defer records.deinit();
            errdefer records.closePreserving();
            while (try records.next()) |record| {
                defer engine.freeValue(record);
                _ = try h.invoke(&s, record, "rootEnded", &.{root_id});
            }
        }
        _ = try h.invoke(&s, touches, "delete", &.{root_id});
        const root_links = try s.get(owned.data, "rootLinks");
        const links = try h.invoke(&s, root_links, "get", &.{root_id});
        if (!h.nullish(links)) {
            var connections = try js.Iterator.init(engine, links, try h.iteratorSymbol(&s));
            defer connections.deinit();
            errdefer connections.closePreserving();
            while (try connections.next()) |connection| {
                defer engine.freeValue(connection);
                const frame = try s.record();
                try h.field(&s, frame, "t", try s.text("root_end"));
                try h.field(&s, frame, "rootId", root_id);
                _ = try h.invoke(&s, connection, "send", &.{frame});
            }
        }
        _ = try h.invoke(&s, root_links, "delete", &.{root_id});
        return c.pi_js_undefined();
    }
    if (method == .maybeRetire) {
        const previous = try s.get(receiver, "previous");
        if (c.JS_IsUndefined(previous) or c.JS_ToBool(engine.context, try s.get(try s.get(previous, "roots"), "size")) != 0) return c.pi_js_undefined();
        if (!try s.equal(try s.get(receiver, "kind"), "client") and !c.JS_IsUndefined(try s.get(receiver, "upstream"))) {
            var previous_id: f64 = 0;
            var allowed: f64 = 0;
            if (c.JS_ToFloat64(engine.context, &previous_id, try s.get(previous, "id")) < 0 or c.JS_ToFloat64(engine.context, &allowed, try s.get((try h.actor(&s, receiver, bindings, .HostImpl)).data, "retireAllowed")) < 0) return js.capture(engine);
            if (previous_id > allowed) return c.pi_js_undefined();
        }
        return js.invoke(engine, receiver, "retire", &.{});
    }
    if (method == .registry) return @import("native_chord_latest_registry.zig").view(engine, bindings, receiver, h.arg(args, 0));
    if (method == .buildTables) return @import("native_chord_latest_registry.zig").build(engine, bindings, receiver, h.arg(args, 0));
    if (method == .liveDecls) return s.result(try liveDecls(&s, receiver, c.JS_ToBool(engine.context, h.arg(args, 0)) != 0));
    if (method == .checkRegistrations) {
        const record = h.arg(args, 0);
        const declarations = h.arg(args, 1);
        if (c.JS_IsStrictEqual(engine.context, try s.get(try s.get(declarations, "registrations"), "size"), c.JS_NewInt32(engine.context, 0))) return c.pi_js_undefined();
        const entries = try excluding(&s, try liveDecls(&s, receiver, false), record);
        const pair = try s.list();
        try js.push(engine, pair, record);
        try js.push(engine, pair, declarations);
        try js.push(engine, entries, pair);
        _ = try h.invoke(&s, receiver, "buildTables", &.{entries});
        return c.pi_js_undefined();
    }
    if (method == .registriesChanged) {
        const record = h.arg(args, 0);
        const entries = try excluding(&s, try liveDecls(&s, receiver, false), record);
        if (!c.JS_IsUndefined(record)) {
            const pair = try s.list();
            try js.push(engine, pair, record);
            try js.push(engine, pair, try s.get(record, "decls"));
            try js.push(engine, entries, pair);
        }
        const tables = try h.invoke(&s, receiver, "buildTables", &.{entries});
        _ = try h.invoke(&s, receiver, "installTables", &.{ try s.get(receiver, "current"), tables });
        return c.pi_js_undefined();
    }
    if (method == .installTables) {
        try @import("native_chord_latest_registry.zig").installTables(engine, bindings, receiver, h.arg(args, 0), h.arg(args, 1), c.JS_ToBool(engine.context, h.arg(args, 2)) != 0);
        return c.pi_js_undefined();
    }
    if (method == .get) return @import("native_chord_host_get_v4.zig").get(engine, receiver, bindings, h.arg(args, 0), h.arg(args, 1), h.arg(args, 2));
    if (method == .hold) return js.get(engine, try h.invoke(&s, receiver, "acquire", &.{ h.arg(args, 0), h.arg(args, 1), h.arg(args, 2), try s.text("external") }), "proxy");
    if (method == .close) return @import("native_chord_latest_dispose.zig").close(engine, bindings, receiver);
    unreachable;
}
fn defaultReport(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, _: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = h.Engine.fromContext(context.?);
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    const console = s.keep(js.global(engine, "console") catch |err| return @import("native_durable.zig").reject(engine, err)) catch |err| return @import("native_durable.zig").reject(engine, err);
    const prefix = s.text("chord:") catch |err| return @import("native_durable.zig").reject(engine, err);
    return js.invoke(engine, console, "error", &.{ prefix, if (argc > 0) argv[0] else c.pi_js_undefined() }) catch |err| @import("native_durable.zig").reject(engine, err);
}
fn construct(engine: *h.Engine, target: c.JSValue, args: []const c.JSValue, values: []const c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    const bindings = values[0];
    const result = try s.keep(try h.allocate(engine, target, bindings, .HostImpl));
    const owned = try h.actor(&s, result, bindings, .HostImpl);
    inline for (.{ "name", "dev" }) |name| try h.field(&s, result, name, c.pi_js_undefined());
    try h.field(&s, result, "principal", c.pi_js_undefined());
    try h.field(&s, result, "inFactory", c.JS_NewInt32(engine.context, 0));
    try h.field(&s, result, "failed", c.pi_js_undefined());
    inline for (.{ "objects", "codeVersions", "facets", "hostObjects", "bindings" }) |name| try h.field(&s, result, name, try h.map(&s));
    try h.field(&s, result, "kind", c.pi_js_undefined());
    try h.field(&s, result, "connections", try h.set(&s));
    try h.field(&s, result, "upstream", c.pi_js_undefined());
    try h.field(&s, result, "remotes", try h.set(&s));
    inline for (.{ "remoteModules", "remoteRemoved" }) |name| try h.field(&s, result, name, try s.record());
    inline for (.{ "current", "previous", "pending", "gating" }) |name| try h.field(&s, result, name, c.pi_js_undefined());
    try h.field(&s, result, "reloading", c.pi_js_bool(engine.context, 0));
    try @import("native_chord_host_reload.zig").initialize(&s, owned.data);
    inline for (.{ "routes", "foreign", "rootLinks", "dying", "touches", "order", "subscribers", "lingering" }) |name| try h.field(&s, owned.data, name, try h.map(&s));
    try h.field(&s, owned.data, "local", try h.set(&s));
    const random = try h.invoke(&s, try s.keep(try js.global(engine, "Math")), "random", &.{});
    const radix = try h.invoke(&s, random, "toString", &.{c.JS_NewInt32(engine.context, 36)});
    try h.field(&s, owned.data, "incarnation", try h.invoke(&s, radix, "slice", &.{ c.JS_NewInt32(engine.context, 2), c.JS_NewInt32(engine.context, 8) }));
    try h.field(&s, owned.data, "codeVersionSeq", c.JS_NewInt32(engine.context, 1));
    try h.field(&s, owned.data, "rootSeq", c.JS_NewInt32(engine.context, 0));
    try h.field(&s, owned.data, "retireAllowed", c.JS_NewInt32(engine.context, 0));
    var captures = [_]c.JSValue{ bindings, result };
    try js.define(engine, result, "serve", try engine.checked(c.JS_NewCFunctionData2(engine.context, callback, "serve", 2, @intFromEnum(Method.serve), 2, &captures)));
    const settings = h.arg(args, 0);
    const name = try s.get(settings, "name");
    try h.field(&s, result, "name", if (h.nullish(name)) try s.text("host") else name);
    const dev = try s.get(settings, "dev");
    try h.field(&s, result, "dev", if (h.nullish(dev)) c.pi_js_bool(engine.context, 0) else dev);
    const self_atom = try js.atom(engine, try s.text("self"));
    defer c.JS_FreeAtom(engine.context, self_atom);
    const has_self = c.JS_HasProperty(engine.context, settings, self_atom);
    if (has_self < 0) return js.capture(engine);
    if (has_self == 0) {
        const message = try s.text("createHost needs `self`: the principal of the host's own code");
        return h.throwValue(&s, try s.keep(try js.builtin(engine, "TypeError", &.{message})));
    }
    try h.field(&s, result, "principal", try s.get(settings, "self"));
    const principal_key = try s.get(settings, "principalKey");
    try h.field(&s, owned.data, "principalKey", if (h.nullish(principal_key)) try s.get(try s.get(bindings, "schema"), "canonicalJson") else principal_key);
    try h.field(&s, owned.data, "selfKey", try s.keep(try js.call(engine, try s.get(owned.data, "principalKey"), result, &.{try s.get(settings, "self")})));
    const on_error = try s.get(settings, "onError");
    const observer = if (h.nullish(on_error)) try s.keep(try engine.checked(c.JS_NewCFunctionData2(engine.context, defaultReport, "", 1, 0, 0, null))) else on_error;
    try h.field(&s, owned.data, "onError", observer);
    try h.field(&s, owned.data, "loader", try s.get(settings, "loader"));
    const task_deadline = try s.get(settings, "taskStopDeadline");
    try h.field(&s, result, "taskStopDeadline", if (h.nullish(task_deadline)) c.JS_NewInt32(engine.context, 5000) else task_deadline);
    const ready_timeout = try s.get(settings, "readyTimeout");
    try h.field(&s, result, "readyTimeout", if (h.nullish(ready_timeout)) c.JS_NewInt32(engine.context, 60000) else ready_timeout);
    const linger = try s.get(settings, "linger");
    const linger_types = try optional(&s, linger, "types");
    try h.field(&s, owned.data, "lingerTypes", if (h.nullish(linger_types)) try s.record() else linger_types);
    const linger_cap = try optional(&s, try s.get(settings, "linger"), "cap");
    try h.field(&s, owned.data, "lingerCap", if (h.nullish(linger_cap)) c.JS_NewInt32(engine.context, 4) else linger_cap);
    const current = try s.record();
    try h.field(&s, current, "id", try s.get(owned.data, "codeVersionSeq"));
    inline for (.{ "services", "tables", "roots" }) |field_name| try h.field(&s, current, field_name, try h.map(&s));
    try h.field(&s, current, "abort", try s.keep(try js.builtin(engine, "AbortController", &.{})));
    try h.field(&s, result, "current", current);
    _ = try h.invoke(&s, try s.get(result, "codeVersions"), "set", &.{ try s.get(current, "id"), current });
    const kind = try s.get(settings, "kind");
    try h.field(&s, result, "kind", if (h.nullish(kind)) try s.text("host") else kind);
    if (!c.JS_IsUndefined(try s.get(settings, "upstream"))) _ = try h.invoke(&s, result, "connect", &.{ try s.get(try s.get(settings, "upstream"), "link"), try s.get(settings, "upstream") });
    return s.result(result);
}
pub fn install(engine: *h.Engine, bindings: c.JSValue) !void {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    try h.register(&s, bindings, .HostImpl);
    const prototype = try s.record();
    try js.define(engine, bindings, "HostImpl", try @import("native_class.zig").constructor(engine, "HostImpl", 1, prototype, construct, &.{bindings}));
    inline for (.{ .{ Method.retainedCodeVersions, 0, false }, .{ Method.disposed, 1, false }, .{ Method.retirable, 0, false }, .{ Method.watchRetirement, 1, false }, .{ Method.announceRetired, 1, false }, .{ Method.reloadEnded, 0, false }, .{ Method.whenReloadEnded, 0, false }, .{ Method.facetRunChanged, 2, false }, .{ Method.peekNextCodeVersion, 0, false }, .{ Method.rememberRemoteModules, 2, false }, .{ Method.accept, 2, false }, .{ Method.connect, 1, false }, .{ Method.route, 2, false }, .{ Method.peerHello, 2, false }, .{ Method.connectionClosed, 1, false }, .{ Method.forgetRemote, 1, false }, .{ Method.relay, 1, true }, .{ Method.reload, 1, false }, .{ Method.onReloadFrame, 2, false }, .{ Method.fail, 1, false }, .{ Method.invalidatePrincipal, 1, true } }) |entry| try h.define(&s, prototype, bindings, @tagName(entry[0]), callback, @intFromEnum(entry[0]), entry[1], false, entry[2]);
    inline for (.{ .{ "codeVersion", Method.codeVersion, 0, true, false }, .{ "previousCodeVersion", Method.previousCodeVersion, 0, true, false }, .{ "report", Method.report, 1, false, false }, .{ "install", Method.install, 1, false, false }, .{ "ready", Method.ready, 0, false, false }, .{ "facetApi", Method.facetApi, 2, false, false }, .{ "serveInto", Method.serveInto, 2, false, false }, .{ "startHostObject", Method.startHostObject, 1, false, false }, .{ "currentCodeVersion", Method.currentCodeVersion, 0, false, false }, .{ "hasCodeVersion", Method.hasCodeVersion, 1, false, false }, .{ "pendingCodeVersion", Method.pendingCodeVersion, 0, false, false }, .{ "service", Method.service, 1, false, false }, .{ "addressOf", Method.addressOf, 4, false, false }, .{ "acquire", Method.acquire, 5, false, false }, .{ "forget", Method.forget, 1, false, false }, .{ "touch", Method.touch, 2, false, false }, .{ "root", Method.root, 1, false, true }, .{ "joinRoot", Method.joinRoot, 3, false, true }, .{ "endRoot", Method.endRoot, 1, false, false }, .{ "maybeRetire", Method.maybeRetire, 0, false, false }, .{ "registry", Method.registry, 1, false, false }, .{ "buildTables", Method.buildTables, 1, false, false }, .{ "liveDecls", Method.liveDecls, 0, false, false }, .{ "checkRegistrations", Method.checkRegistrations, 2, false, false }, .{ "registriesChanged", Method.registriesChanged, 1, false, false }, .{ "installTables", Method.installTables, 2, false, false }, .{ "bindingIdle", Method.bindingIdle, 1, false, false }, .{ "forgetBinding", Method.forgetBinding, 1, false, false }, .{ "isSelf", Method.isSelf, 1, false, false }, .{ "get", Method.get, 3, false, true }, .{ "hold", Method.hold, 3, false, false }, .{ "close", Method.close, 0, false, true } }) |item| try h.define(&s, prototype, bindings, item[0], callback, @intFromEnum(item[1]), item[2], item[3], item[4]);
    inline for (.{ .{ "load", Method.load, 1, true }, .{ "resolve", Method.resolve, 1, true }, .{ "rootSent", Method.rootSent, 2, false }, .{ "foreignRootEnded", Method.foreignRootEnded, 2, false }, .{ "nextCodeVersionId", Method.nextCodeVersionId, 1, false }, .{ "allowRetire", Method.allowRetire, 1, false }, .{ "retire", Method.retire, 0, false }, .{ "retireImplementation", Method.retireImplementation, 2, false } }) |item| try h.define(&s, prototype, bindings, item[0], callback, @intFromEnum(item[1]), item[2], false, item[3]);
}
