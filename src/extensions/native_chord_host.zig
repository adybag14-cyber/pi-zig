//! Actual local HostImpl ownership and admission; package activation stays gated.
const h = @import("native_chord_host_values.zig");
const Scope = h.Scope;
const js = h.js;
const c = h.c;
const Method = enum(c_int) { epoch, previousEpoch, report, install, ready, facetApi, serveInto, startEager, currentEpoch, hasEpoch, retainedEpochs, pendingEpoch, service, addressOf, acquire, forget, touch, root, joinRoot, endRoot, maybeRetire, registry, buildTables, liveDecls, checkRegistrations, registriesChanged, installTables, get, close, serve };
fn callback(context: ?*c.JSContext, receiver: c.JSValue, argc: c_int, argv: [*c]c.JSValue, operation: c_int, data: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = h.Engine.fromContext(context.?);
    const method: Method = @enumFromInt(operation);
    const target = if (method == .serve) data[1] else receiver;
    const result = invoke(engine, target, if (argc > 0) argv[0..@intCast(argc)] else &.{}, method, data[0]) catch |err| {
        return if (method == .root or method == .joinRoot or method == .close) @import("native_durable.zig").rejectedPromise(engine, err) else @import("native_durable.zig").reject(engine, err);
    };
    if (method == .root) {
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
fn makeService(s: *Scope, type_value: c.JSValue, factory: c.JSValue, settings: c.JSValue, facet: c.JSValue) !c.JSValue {
    const result = try s.record();
    try h.field(s, result, "contract", type_value);
    try h.field(s, result, "factory", factory);
    try h.field(s, result, "options", settings);
    try h.field(s, result, "facet", facet);
    const state = try s.get(settings, "state");
    const version = if (h.nullish(state)) c.pi_js_undefined() else try s.get(state, "version");
    try h.field(s, result, "stateVersion", if (h.nullish(version)) c.JS_NewInt32(s.engine.context, 1) else version);
    return result;
}
fn address(s: *Scope, host: c.JSValue, bindings: c.JSValue, provider: c.JSValue, normalized: c.JSValue, principal: c.JSValue) !c.JSValue {
    const owned = try h.actor(s, host, bindings, .HostImpl);
    const key = if (c.JS_IsStrictEqual(s.engine.context, principal, try s.get(host, "principal"))) try s.text("host") else blk: {
        const mapped = try s.keep(try js.call(s.engine, try s.get(owned.data, "principalKey"), host, &.{principal}));
        break :blk try s.keep(try @import("native_utf16.zig").concat(s.engine, &.{ try s.text("p:"), mapped }));
    };
    const contract = try s.get(provider, "contract");
    const identity = try s.keep(try @import("native_chord_identity.zig").canonicalIdentity(s.engine, try s.get(contract, "input"), normalized));
    return s.keep(try @import("native_utf16.zig").concat(s.engine, &.{ try s.get(contract, "name"), try s.text("\x00"), identity, try s.text("\x00"), key }));
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
            const holds = try h.values(s, try s.get(try s.at(declarations, index), "holds"));
            const size = try h.length(s, holds);
            for (0..size) |position| {
                const target = try s.get(try s.at(holds, position), "record");
                if (!c.JS_IsUndefined(target)) try js.push(s.engine, stack, target);
            }
        }
    }
    return false;
}
fn acquire(s: *Scope, host: c.JSValue, args: []const c.JSValue, bindings: c.JSValue) anyerror!c.JSValue {
    const type_value = h.arg(args, 0);
    const settings = h.arg(args, 2);
    const at = try optional(s, settings, "at");
    if (!c.JS_IsUndefined(at) and !c.JS_IsStrictEqual(s.engine.context, at, try s.get(host, "name"))) return error.NativeChordRemoteAcquisitionRequired;
    const provider = try service(s, host, try s.get(type_value, "name"), c.JS_ToBool(s.engine.context, h.arg(args, 5)) != 0);
    if (c.JS_IsUndefined(provider)) return unknown(s, bindings, try s.get(type_value, "name"), host);
    _ = try h.invoke(s, try s.get(bindings, "contracts"), "bind", &.{ try s.get(provider, "contract"), try s.get(try s.get(provider, "options"), "accepts"), type_value });
    const raw_principal = try optional(s, settings, "principal");
    const principal = if (h.nullish(raw_principal)) try s.get(host, "principal") else raw_principal;
    const what = try s.keep(try @import("native_utf16.zig").concat(s.engine, &.{ try s.get(type_value, "name"), try s.text(" input") }));
    const normalized = try s.keep(try @import("native_chord_normalization.zig").normalize(s.engine, try s.get(bindings, "errors"), try s.get(try s.get(provider, "contract"), "input"), h.arg(args, 1), what));
    const key = try address(s, host, bindings, provider, normalized, principal);
    const records = try s.get(host, "records");
    var record = try h.invoke(s, records, "get", &.{key});
    const from = h.arg(args, 4);
    if (!c.JS_IsUndefined(from) and !c.JS_IsUndefined(record) and (c.JS_IsStrictEqual(s.engine.context, record, from) or try reaches(s, record, from))) return h.invalid(s, bindings, "cycle", &.{ try s.get(from, "address"), try s.text(" -> "), key, try s.text(" would create a hold cycle") });
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
        const eager = try s.get(try s.get(provider, "options"), "eager");
        try h.field(s, identity, "eager", c.pi_js_bool(s.engine.context, @intFromBool(!c.JS_IsUndefined(eager) and !c.JS_IsStrictEqual(s.engine.context, eager, c.pi_js_bool(s.engine.context, 0)) and c.JS_IsStrictEqual(s.engine.context, principal, try s.get(host, "principal")))));
        record = try h.construct(s, bindings, "RecordImpl", &.{ host, identity });
        _ = try h.invoke(s, records, "set", &.{ key, record });
        const after = if (!h.nullish(dying) and try s.equal(try s.get(dying, "status"), "disposing")) try h.invoke(s, dying, "dispose", &.{c.pi_js_bool(s.engine.context, 0)}) else c.pi_js_undefined();
        _ = try h.invoke(s, record, "start", &.{after});
    }
    const handle = try h.construct(s, bindings, "HandleImpl", &.{ record, type_value, h.arg(args, 3) });
    _ = try h.invoke(s, record, "addHold", &.{handle});
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
    const provider = try makeService(&s, h.arg(args, 0), h.arg(args, 1), try options(&s, h.arg(args, 2)), try s.get(data[1], "name"));
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
    const epoch = try h.invoke(s, try s.get(host, "epochs"), "get", &.{epoch_id});
    const owned = try h.actor(s, host, bindings, .HostImpl);
    if (c.JS_IsUndefined(epoch)) {
        _ = try h.invoke(s, try s.get(owned.data, "local"), "delete", &.{root_id});
        return h.throwValue(s, try h.errorValue(s, bindings, "superseded", &.{ try s.text("epoch "), epoch_id, try s.text(" is not retained by "), try s.get(host, "name") }, c.pi_js_undefined()));
    }
    if (!c.JS_IsUndefined(try s.get(settings, "from"))) return error.NativeChordForeignRootLinksRequired;
    const roots = try s.get(epoch, "roots");
    const previous = try h.invoke(s, roots, "get", &.{root_id});
    var count: f64 = 0;
    if (!h.nullish(previous) and c.JS_ToFloat64(s.engine.context, &count, previous) < 0) return js.capture(s.engine);
    _ = try h.invoke(s, roots, "set", &.{ root_id, c.JS_NewFloat64(s.engine.context, count + 1) });
    const fields = try s.record();
    const signal = try s.get(settings, "signal");
    try h.field(s, fields, "signal", if (h.nullish(signal)) try s.get(try s.keep(try js.builtin(s.engine, "AbortController", &.{})), "signal") else signal);
    try h.field(s, fields, "rootId", root_id);
    try h.field(s, fields, "epoch", try s.get(epoch, "id"));
    const principal = try s.get(settings, "principal");
    try h.field(s, fields, "principal", if (h.nullish(principal)) try s.get(host, "principal") else principal);
    const ctx = try h.construct(s, bindings, "CtxImpl", &.{ host, fields });
    const work = try s.record();
    try h.field(s, work, "bindings", bindings);
    try h.field(s, work, "host", host);
    try h.field(s, work, "ctx", ctx);
    try h.field(s, work, "epoch", epoch);
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
    const roots = try s.get(try s.get(work, "epoch"), "roots");
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
    }
    return if (rejected) engine.checked(c.JS_Throw(engine.context, s.result(value))) else s.result(value);
}
fn liveDecls(s: *Scope, host: c.JSValue, candidates: bool) !c.JSValue {
    const result = try s.list();
    const records = try h.values(s, try s.get(host, "records"));
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
    if (method == .epoch or method == .currentEpoch) return js.get(engine, try s.get(receiver, "current"), "id");
    if (method == .previousEpoch or method == .pendingEpoch) {
        const state = try s.get(receiver, if (method == .previousEpoch) "previous" else "pending");
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
        const provider = try makeService(&s, h.arg(args, 0), h.arg(args, 1), settings, try s.text(""));
        _ = try h.invoke(&s, receiver, "serveInto", &.{ try s.get(try s.get(receiver, "current"), "services"), provider });
        if (try h.flag(&s, settings, "eager")) _ = try h.invoke(&s, receiver, "startEager", &.{try h.invoke(&s, try s.get(try s.get(receiver, "current"), "services"), "get", &.{try s.get(h.arg(args, 0), "name")})});
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
        return s.result(api);
    }
    if (method == .install) {
        if (try h.flag(&s, receiver, "reloading")) return h.ordinaryError(&s, &.{try s.text("host.install during a reload")});
        const facet = h.arg(args, 0);
        const settings = try options(&s, h.arg(args, 1));
        const facets = try s.get(receiver, "facets");
        if (c.JS_ToBool(engine.context, try h.invoke(&s, facets, "has", &.{try s.get(facet, "name")})) != 0) return h.ordinaryError(&s, &.{ try s.text("facet "), try s.get(facet, "name"), try s.text(" is already installed; use reload()") });
        const added = try s.list();
        var captures = [_]c.JSValue{ receiver, facet, added };
        const serve_function = try s.keep(try engine.checked(c.JS_NewCFunctionData2(engine.context, facetServe, "", 2, 0, 3, &captures)));
        const api = try h.invoke(&s, receiver, "facetApi", &.{serve_function});
        _ = try h.invoke(&s, facet, "setup", &.{api});
        _ = try h.invoke(&s, facets, "set", &.{ try s.get(facet, "name"), facet });
        const holds = try s.list();
        const count = try h.length(&s, added);
        for (0..count) |index| {
            const provider = try s.at(added, index);
            if (try h.flag(&s, try s.get(provider, "options"), "eager")) try js.push(engine, holds, try h.invoke(&s, receiver, "startEager", &.{provider}));
        }
        if (c.JS_IsStrictEqual(engine.context, try s.get(settings, "awaitEager"), c.pi_js_bool(engine.context, 0))) {
            const promise_type = try s.keep(try js.global(engine, "Promise"));
            return js.invoke(engine, promise_type, "resolve", &.{});
        }
        return eagerReady(&s, holds);
    }
    if (method == .startEager) {
        const provider = h.arg(args, 0);
        const eager = try s.get(try s.get(provider, "options"), "eager");
        const input = if (c.JS_IsObject(eager) or c.JS_IsNull(eager)) try s.get(eager, "input") else try s.record();
        const handle = try h.invoke(&s, receiver, "acquire", &.{ try s.get(provider, "contract"), input, c.pi_js_undefined(), try s.text("host") });
        _ = try h.invoke(&s, try s.get(receiver, "eager"), "set", &.{ try s.get(try s.get(provider, "contract"), "name"), handle });
        var captures = [_]c.JSValue{receiver};
        const observer = try s.keep(try engine.checked(c.JS_NewCFunctionData2(engine.context, reportFailure, "", 1, 0, 1, &captures)));
        _ = try h.invoke(&s, try s.get(handle, "ready"), "catch", &.{observer});
        return s.result(handle);
    }
    if (method == .ready) return eagerReady(&s, try h.invoke(&s, try s.get(receiver, "eager"), "values", &.{}));
    if (method == .hasEpoch) return js.invoke(engine, try s.get(receiver, "epochs"), "has", &.{h.arg(args, 0)});
    if (method == .service) {
        const current = try h.invoke(&s, try s.get(try s.get(receiver, "current"), "services"), "get", &.{h.arg(args, 0)});
        if (!h.nullish(current)) return s.result(current);
        const pending = try s.get(receiver, "pending");
        return if (h.nullish(pending)) c.pi_js_undefined() else js.invoke(engine, try s.get(pending, "services"), "get", &.{h.arg(args, 0)});
    }
    if (method == .addressOf) {
        const type_value = h.arg(args, 0);
        const at = h.arg(args, 3);
        const principal = h.arg(args, 2);
        if (!c.JS_IsUndefined(at) and !c.JS_IsStrictEqual(engine.context, at, try s.get(receiver, "name"))) {
            const input = try s.keep(try @import("native_chord_canonical.zig").canonicalJson(engine, h.arg(args, 1)));
            const key = if (c.JS_IsStrictEqual(engine.context, principal, try s.get(receiver, "principal"))) try s.text("host") else try s.keep(try @import("native_chord_canonical.zig").canonicalJson(engine, principal));
            return @import("native_utf16.zig").concat(engine, &.{ try s.text("@"), at, try s.text("\x00"), try s.get(type_value, "name"), try s.text("\x00"), input, try s.text("\x00"), key });
        }
        const provider = try service(&s, receiver, try s.get(type_value, "name"), c.JS_ToBool(engine.context, h.arg(args, 4)) != 0);
        if (c.JS_IsUndefined(provider)) return unknown(&s, bindings, try s.get(type_value, "name"), receiver);
        const what = try s.keep(try @import("native_utf16.zig").concat(engine, &.{ try s.get(type_value, "name"), try s.text(" input") }));
        const normalized = try s.keep(try @import("native_chord_normalization.zig").normalize(engine, try s.get(bindings, "errors"), try s.get(try s.get(provider, "contract"), "input"), h.arg(args, 1), what));
        return s.result(try address(&s, receiver, bindings, provider, normalized, principal));
    }
    if (method == .acquire) return acquire(&s, receiver, args, bindings);
    if (method == .forget) {
        const record = h.arg(args, 0);
        const records = try s.get(receiver, "records");
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
        const epoch = try s.get(settings, "epoch");
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
            const records = try h.snapshot(&s, touched);
            const count = try h.length(&s, records);
            for (0..count) |index| _ = try h.invoke(&s, try s.at(records, index), "rootEnded", &.{root_id});
        }
        _ = try h.invoke(&s, touches, "delete", &.{root_id});
        const root_links = try s.get(owned.data, "rootLinks");
        const links = try h.invoke(&s, root_links, "get", &.{root_id});
        if (!h.nullish(links)) {
            const connections = try h.snapshot(&s, links);
            const frame = try s.record();
            try h.field(&s, frame, "t", try s.text("root_end"));
            try h.field(&s, frame, "rootId", root_id);
            const count = try h.length(&s, connections);
            for (0..count) |index| _ = try h.invoke(&s, try s.at(connections, index), "send", &.{frame});
        }
        _ = try h.invoke(&s, root_links, "delete", &.{root_id});
        return c.pi_js_undefined();
    }
    if (method == .maybeRetire) {
        const previous = try s.get(receiver, "previous");
        if (c.JS_IsUndefined(previous) or c.JS_ToBool(engine.context, try s.get(try s.get(previous, "roots"), "size")) != 0) return c.pi_js_undefined();
        return error.NativeChordEpochRetirementRequired;
    }
    if (method == .registry) return @import("native_chord_host_registry.zig").view(engine, bindings, receiver, h.arg(args, 0));
    if (method == .buildTables) return @import("native_chord_host_registry.zig").build(engine, bindings, receiver, h.arg(args, 0));
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
        try @import("native_chord_host_registry.zig").installTables(engine, bindings, receiver, h.arg(args, 0), h.arg(args, 1), c.JS_ToBool(engine.context, h.arg(args, 2)) != 0);
        return c.pi_js_undefined();
    }
    if (method == .get) return js.get(engine, try h.invoke(&s, receiver, "acquire", &.{ h.arg(args, 0), h.arg(args, 1), h.arg(args, 2), try s.text("external") }), "proxy");
    if (method == .close) return @import("native_chord_host_dispose.zig").close(engine, bindings, receiver);
    return error.NativeChordRetainedEpochIteratorRequired;
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
    try h.field(&s, result, "principal", try s.get(bindings, "hostPrincipal"));
    try h.field(&s, result, "inFactory", c.JS_NewInt32(engine.context, 0));
    try h.field(&s, result, "failed", c.pi_js_undefined());
    inline for (.{ "records", "epochs", "facets", "eager" }) |name| try h.field(&s, result, name, try h.map(&s));
    try h.field(&s, result, "kind", c.pi_js_undefined());
    try h.field(&s, result, "connections", try h.set(&s));
    try h.field(&s, result, "upstream", c.pi_js_undefined());
    try h.field(&s, result, "remotes", try h.set(&s));
    inline for (.{ "remoteModules", "remoteRemoved" }) |name| try h.field(&s, result, name, try s.record());
    inline for (.{ "current", "previous", "pending", "gating" }) |name| try h.field(&s, result, name, c.pi_js_undefined());
    try h.field(&s, result, "reloading", c.pi_js_bool(engine.context, 0));
    try h.field(&s, result, "retired", try s.keep(try engine.checked(c.JS_NewCFunctionData2(engine.context, noop, "retired", 0, 0, 0, null))));
    inline for (.{ "routes", "foreign", "rootLinks", "dying", "touches", "order", "subscribers" }) |name| try h.field(&s, owned.data, name, try h.map(&s));
    try h.field(&s, owned.data, "local", try h.set(&s));
    const random = try h.invoke(&s, try s.keep(try js.global(engine, "Math")), "random", &.{});
    const radix = try h.invoke(&s, random, "toString", &.{c.JS_NewInt32(engine.context, 36)});
    try h.field(&s, owned.data, "incarnation", try h.invoke(&s, radix, "slice", &.{ c.JS_NewInt32(engine.context, 2), c.JS_NewInt32(engine.context, 8) }));
    try h.field(&s, owned.data, "epochSeq", c.JS_NewInt32(engine.context, 1));
    try h.field(&s, owned.data, "rootSeq", c.JS_NewInt32(engine.context, 0));
    try h.field(&s, owned.data, "retireAllowed", c.JS_NewInt32(engine.context, 0));
    var captures = [_]c.JSValue{ bindings, result };
    try js.define(engine, result, "serve", try engine.checked(c.JS_NewCFunctionData2(engine.context, callback, "serve", 2, @intFromEnum(Method.serve), 2, &captures)));
    const settings = h.arg(args, 0);
    const name = try s.get(settings, "name");
    try h.field(&s, result, "name", if (h.nullish(name)) try s.text("host") else name);
    const dev = try s.get(settings, "dev");
    try h.field(&s, result, "dev", if (h.nullish(dev)) c.pi_js_bool(engine.context, 0) else dev);
    const principal_key = try s.get(settings, "principalKey");
    try h.field(&s, owned.data, "principalKey", if (h.nullish(principal_key)) try s.get(try s.get(bindings, "schema"), "canonicalJson") else principal_key);
    const on_error = try s.get(settings, "onError");
    const observer = if (h.nullish(on_error)) try s.keep(try engine.checked(c.JS_NewCFunctionData2(engine.context, defaultReport, "", 1, 0, 0, null))) else on_error;
    try h.field(&s, owned.data, "onError", observer);
    try h.field(&s, owned.data, "loader", try s.get(settings, "loader"));
    const current = try s.record();
    try h.field(&s, current, "id", try s.get(owned.data, "epochSeq"));
    inline for (.{ "services", "tables", "roots" }) |field_name| try h.field(&s, current, field_name, try h.map(&s));
    try h.field(&s, result, "current", current);
    _ = try h.invoke(&s, try s.get(result, "epochs"), "set", &.{ try s.get(current, "id"), current });
    const kind = try s.get(settings, "kind");
    try h.field(&s, result, "kind", if (h.nullish(kind)) try s.text("host") else kind);
    if (!c.JS_IsUndefined(try s.get(settings, "upstream"))) return error.NativeChordConnectionImplementationRequired;
    return s.result(result);
}
fn simpleConstruct(engine: *h.Engine, target: c.JSValue, args: []const c.JSValue, values: []const c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    const result = try s.keep(try @import("native_class.zig").object(engine, target));
    if (c.JS_ToBool(engine.context, values[0]) != 0) {
        try h.field(&s, result, "resource", h.arg(args, 0));
    } else {
        inline for (.{ "cells", "cellSchemas", "holds", "resources", "listeners", "tasks", "derives", "deriveFns", "registrations" }) |name| try h.field(&s, result, name, try h.map(&s));
    }
    return s.result(result);
}
fn install(engine: *h.Engine, bindings: c.JSValue) !void {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    try h.register(&s, bindings, .HostImpl);
    const prototype = try s.record();
    try js.define(engine, bindings, "HostImpl", try @import("native_class.zig").constructor(engine, "HostImpl", 1, prototype, construct, &.{bindings}));
    inline for (.{ .{ "epoch", Method.epoch, 0, true, false }, .{ "previousEpoch", Method.previousEpoch, 0, true, false }, .{ "report", Method.report, 1, false, false }, .{ "install", Method.install, 1, false, false }, .{ "ready", Method.ready, 0, false, false }, .{ "facetApi", Method.facetApi, 1, false, false }, .{ "serveInto", Method.serveInto, 2, false, false }, .{ "startEager", Method.startEager, 1, false, false }, .{ "currentEpoch", Method.currentEpoch, 0, false, false }, .{ "hasEpoch", Method.hasEpoch, 1, false, false }, .{ "pendingEpoch", Method.pendingEpoch, 0, false, false }, .{ "service", Method.service, 1, false, false }, .{ "addressOf", Method.addressOf, 4, false, false }, .{ "acquire", Method.acquire, 5, false, false }, .{ "forget", Method.forget, 1, false, false }, .{ "touch", Method.touch, 2, false, false }, .{ "root", Method.root, 1, false, true }, .{ "joinRoot", Method.joinRoot, 3, false, true }, .{ "endRoot", Method.endRoot, 1, false, false }, .{ "maybeRetire", Method.maybeRetire, 0, false, false }, .{ "registry", Method.registry, 1, false, false }, .{ "buildTables", Method.buildTables, 1, false, false }, .{ "liveDecls", Method.liveDecls, 0, false, false }, .{ "checkRegistrations", Method.checkRegistrations, 2, false, false }, .{ "registriesChanged", Method.registriesChanged, 1, false, false }, .{ "installTables", Method.installTables, 2, false, false }, .{ "get", Method.get, 3, false, false }, .{ "close", Method.close, 0, false, true } }) |item| try h.define(&s, prototype, bindings, item[0], callback, @intFromEnum(item[1]), item[2], item[3], item[4]);
}
fn createHost(engine: *h.Engine, _: c.JSValue, args: []const c.JSValue, values: []const c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    return s.result(try h.construct(&s, values[0], "HostImpl", &.{try options(&s, h.arg(args, 0))}));
}
/// Internal actual Host factory for Source qualification; no module install.
pub const Classes = struct { exports: c.JSValue, bindings: c.JSValue };
pub fn classes(engine: *h.Engine) !Classes {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    try @import("abort_signal.zig").install(engine);
    const bindings = try s.record();
    try h.field(&s, bindings, "classes", try s.record());
    const object = try s.keep(try js.global(engine, "Object"));
    try h.field(&s, bindings, "objectPrototype", try s.get(object, "prototype"));
    const resource_classes = try @import("native_chord_resources.zig").classes(engine);
    _ = try s.keep(resource_classes.exports);
    _ = try s.keep(resource_classes.bindings);
    try h.field(&s, bindings, "errors", resource_classes.exports);
    try h.field(&s, bindings, "resourceBindings", resource_classes.bindings);
    inline for (.{ "ResourceImpl", "ResourceFacade" }) |name| try h.field(&s, bindings, name, try s.get(resource_classes.exports, name));
    const contracts = try s.keep(try @import("native_chord_contracts.zig").exports(engine, try s.get(resource_classes.exports, "ChordError")));
    try h.field(&s, bindings, "contracts", contracts);
    const schema = try s.keep(try @import("native_chord_schema_api.zig").exports(engine));
    try h.field(&s, bindings, "schema", schema);
    const principal = try s.record();
    try h.field(&s, principal, "host", c.pi_js_bool(engine.context, 1));
    _ = try h.invoke(&s, object, "freeze", &.{principal});
    try h.field(&s, bindings, "hostPrincipal", principal);
    try h.field(&s, bindings, "emptyTable", try h.map(&s));
    try h.field(&s, bindings, "holdsByProxy", try s.keep(try js.builtin(engine, "WeakMap", &.{})));
    try @import("native_chord_publish.zig").initialize(engine, bindings);
    try @import("native_chord_cells.zig").install(engine, bindings);
    inline for (.{ "Decls", "ExposedImpl" }, 0..) |name, index| {
        const prototype = try s.record();
        try js.define(engine, bindings, name, try @import("native_class.zig").constructor(engine, name, @intCast(index), prototype, simpleConstruct, &.{c.pi_js_bool(engine.context, @intCast(index))}));
    }
    const declarations = try s.keep(try @import("native_chord_declarations.zig").exports(engine, bindings));
    try h.field(&s, bindings, "declarations", declarations);
    try install(engine, bindings);
    try @import("native_chord_host_context.zig").install(engine, bindings);
    try @import("native_chord_host_self.zig").install(engine, bindings);
    try @import("native_chord_host_record.zig").install(engine, bindings);
    try @import("native_chord_host_readable.zig").install(engine, bindings);
    try @import("native_chord_host_handle.zig").install(engine, bindings);
    const api = try s.record();
    try js.spreadInto(engine, api, contracts);
    inline for (.{ "ChordError", "isChordError", "forbidden", "invalid" }) |name| try h.field(&s, api, name, try s.get(resource_classes.exports, name));
    inline for (.{ "cell", "resource", "listener", "derivation", "defineFacet", "defineRegistry" }) |name| try h.field(&s, api, name, try s.get(declarations, name));
    try h.field(&s, api, "hostPrincipal", principal);
    try js.define(engine, api, "createHost", try @import("native_node_function.zig").create(engine, "createHost", 0, createHost, &.{bindings}));
    try js.define(engine, api, "Type", try @import("typebox.zig").create(engine));
    return .{ .exports = s.result(api), .bindings = s.result(bindings) };
}
pub fn exports(engine: *h.Engine) !c.JSValue {
    const result = try classes(engine);
    engine.freeValue(result.bindings);
    return result.exports;
}
