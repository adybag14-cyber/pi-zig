//! Source1692 named factory declarations; per-cell migrations, adopted resources and fresh positional derivations/tasks.
const r = @import("native_chord_reload_values.zig");
const h = r.h;
const js = r.js;
const c = r.c;
const Scope = r.Scope;
const Method = enum(c_int) { run, state, get, resource, on, task, derive, expose, register };
fn callback(ctx: ?*c.JSContext, receiver: c.JSValue, argc: c_int, argv: [*c]c.JSValue, operation: c_int, captures: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = h.Engine.fromContext(ctx.?);
    return invoke(engine, captures[0], receiver, if (argc > 0) argv[0..@intCast(argc)] else &.{}, @enumFromInt(operation)) catch |err| @import("native_durable.zig").reject(engine, err);
}
fn unique(s: *Scope, bindings: c.JSValue, object: c.JSValue, map: c.JSValue, kind: []const u8, name: c.JSValue) !void {
    if (!c.JS_IsString(name) or try s.equal(name, "")) _ = try h.typeError(s, &.{ try s.text(kind), try s.text(" needs a name") });
    if (try r.has(s, map, name)) _ = try h.invalid(s, bindings, "duplicate", &.{ try s.get(object, "typeName"), try s.text(": duplicate "), try s.text(kind), try s.text(" name "), name });
}
fn sourceOptions(s: *Scope, host: c.JSValue) !c.JSValue {
    const options = try s.record();
    try h.field(s, options, "dev", try s.get(host, "dev"));
    try h.field(s, options, "report", try r.reportFunction(s, host));
    return options;
}
fn position(s: *Scope, map: c.JSValue) !c.JSValue {
    return r.concat(s, &.{ try s.text("#"), try s.get(map, "size") });
}
fn dependency(ctx: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, captures: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = h.Engine.fromContext(ctx.?);
    return resolveDependency(engine, captures[0], captures[1], if (argc > 0) argv[0] else c.pi_js_undefined()) catch |err| @import("native_durable.zig").reject(engine, err);
}
fn resolveDependency(engine: *h.Engine, bindings: c.JSValue, name: c.JSValue, value: c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    if (c.JS_IsObject(value) and !c.JS_IsFunction(engine.context, value)) {
        const ref = try h.invoke(&s, try s.get(bindings, "refsByProxy"), "get", &.{value});
        if (!h.nullish(ref)) return s.result(ref);
    }
    const resource = try s.keep(try @import("native_chord_latest_resources.zig").resourceOf(engine, value, try s.get(bindings, "resourceBindings")));
    if (c.JS_IsUndefined(resource)) return h.typeError(&s, &.{ try s.text("resource "), name, try s.text(": deps must be references or resources of this object") });
    return s.result(resource);
}
fn sameDependencies(s: *Scope, a: c.JSValue, b: c.JSValue) !bool {
    const count = try h.length(s, a);
    if (count != try h.length(s, b)) return false;
    for (0..count) |index| {
        if (!try js.hasKey(s.engine, a, c.JS_NewUint32(s.engine.context, @intCast(index)))) continue;
        if (!c.JS_IsStrictEqual(s.engine.context, try s.at(a, index), try s.at(b, index))) return false;
    }
    return true;
}
fn invoke(engine: *h.Engine, bindings: c.JSValue, receiver: c.JSValue, args: []const c.JSValue, method: Method) anyerror!c.JSValue {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    const data = (try h.actor(&s, receiver, bindings, .ObjectSelf)).data;
    const object = try s.get(data, "object");
    const decls = try s.get(data, "decls");
    const previous = try s.get(data, "previous");
    const created = try s.get(data, "created");
    if (method == .run) {
        const run = try s.record();
        try h.field(&s, run, "implementation", h.arg(args, 0));
        try h.field(&s, run, "decls", decls);
        try h.field(&s, run, "created", created);
        return s.result(run);
    }
    if (method == .state) {
        const name = h.arg(args, 0);
        const cells = try s.get(decls, "cells");
        try unique(&s, bindings, object, cells, "state", name);
        const options = if (c.JS_IsUndefined(h.arg(args, 3))) try s.record() else h.arg(args, 3);
        const version = r.default(&s, try s.get(options, "version"), c.JS_NewInt32(engine.context, 1));
        if (c.JS_ToBool(engine.context, try s.builtin("Number", "isInteger", &.{version})) == 0 or try r.greater(&s, c.JS_NewInt32(engine.context, 1), version)) return h.typeError(&s, &.{ try s.text("state "), name, try s.text(": version must be a positive integer") });
        const host = try s.get(object, "host");
        const initial = h.arg(args, 2);
        const init = if (c.JS_IsObject(initial) and !c.JS_IsFunction(engine.context, initial) and c.JS_IsFunction(engine.context, try s.get(initial, "init"))) try s.get(initial, "init") else c.pi_js_undefined();
        const existing = if (h.nullish(previous)) c.pi_js_undefined() else try h.invoke(&s, try s.get(previous, "cells"), "get", &.{name});
        var cell = existing;
        if (c.JS_IsUndefined(cell)) {
            const boxed = if (c.JS_IsUndefined(init)) try s.record() else c.pi_js_undefined();
            if (c.JS_IsUndefined(init)) try h.field(&s, boxed, "value", initial);
            cell = try h.construct(&s, bindings, "Cell", &.{ name, h.arg(args, 1), boxed, try s.get(object, "guard"), try sourceOptions(&s, host) });
            if (!c.JS_IsUndefined(init)) {
                const declaration = try s.list();
                try js.push(engine, declaration, cell);
                try js.push(engine, declaration, init);
                try js.push(engine, try s.get(created, "inits"), declaration);
            }
        }
        _ = try h.invoke(&s, cells, "set", &.{ name, cell });
        _ = try h.invoke(&s, try s.get(decls, "cellSchemas"), "set", &.{ name, h.arg(args, 1) });
        _ = try h.invoke(&s, try s.get(decls, "cellVersions"), "set", &.{ name, version });
        const migrate = try s.get(options, "migrate");
        if (!c.JS_IsUndefined(migrate)) _ = try h.invoke(&s, try s.get(decls, "cellMigrations"), "set", &.{ name, try s.get(options, "migrate") });
        return s.result(cell);
    }
    if (method == .get) return get(&s, bindings, object, previous, decls, created, args);
    if (method == .resource) {
        const name = h.arg(args, 0);
        const declaration = h.arg(args, 1);
        const declared = try s.get(decls, "resources");
        try unique(&s, bindings, object, declared, "resource", name);
        if (c.JS_ToBool(engine.context, try s.builtin("Number", "isInteger", &.{try s.get(declaration, "version")})) == 0) return h.typeError(&s, &.{ try s.text("resource "), name, try s.text(": version must be an integer") });
        var captures = [_]c.JSValue{ bindings, name };
        const resolver = try s.keep(try engine.checked(c.JS_NewCFunctionData2(engine.context, dependency, "", 1, 0, 2, &captures)));
        const deps = try h.invoke(&s, r.default(&s, try s.get(declaration, "deps"), try s.list()), "map", &.{resolver});
        const existing = if (h.nullish(previous)) c.pi_js_undefined() else try h.invoke(&s, try s.get(previous, "resources"), "get", &.{name});
        const exclusive = c.JS_IsStrictEqual(engine.context, try s.get(declaration, "exclusive"), c.pi_js_bool(engine.context, 1));
        const kept = !c.JS_IsUndefined(existing) and c.JS_IsStrictEqual(engine.context, try s.get(try s.get(existing, "spec"), "version"), try s.get(declaration, "version")) and (c.JS_ToBool(engine.context, try s.get(existing, "exclusive")) != 0) == exclusive and try sameDependencies(&s, try s.get(existing, "deps"), deps);
        const resource = if (kept) existing else try h.construct(&s, bindings, "ResourceImpl", &.{ name, declaration, deps });
        if (kept) {
            _ = try h.invoke(&s, try s.get(decls, "adopted"), "set", &.{ existing, declaration });
        } else try js.push(engine, try s.get(created, "resources"), resource);
        _ = try h.invoke(&s, declared, "set", &.{ name, resource });
        return s.result(try h.construct(&s, bindings, "ResourceFacade", &.{ resource, try s.get(object, "host") }));
    }
    if (method == .on) {
        const name = h.arg(args, 0);
        const listeners = try s.get(decls, "listeners");
        try unique(&s, bindings, object, listeners, "listener", name);
        const select = if (args.len == 3) c.pi_js_undefined() else h.arg(args, 2);
        const handler = if (args.len == 3) h.arg(args, 2) else h.arg(args, 3);
        if (!c.JS_IsFunction(engine.context, handler)) return h.typeError(&s, &.{ try s.text("listener "), name, try s.text(": the handler must be a function") });
        if (!c.JS_IsUndefined(select) and !c.JS_IsFunction(engine.context, select)) return h.typeError(&s, &.{ try s.text("listener "), name, try s.text(": select must be a function") });
        const listener = try s.record();
        try h.field(&s, listener, "source", h.arg(args, 1));
        try h.field(&s, listener, "select", select);
        try h.field(&s, listener, "fn", handler);
        _ = try h.invoke(&s, listeners, "set", &.{ name, listener });
        return c.pi_js_undefined();
    }
    if (method == .task) {
        if (!c.JS_IsFunction(engine.context, h.arg(args, 0))) return h.typeError(&s, &.{try s.text("a task must be a function")});
        const tasks = try s.get(decls, "tasks");
        _ = try h.invoke(&s, tasks, "set", &.{ try position(&s, tasks), h.arg(args, 0) });
        return c.pi_js_undefined();
    }
    if (method == .derive) {
        if (!c.JS_IsFunction(engine.context, h.arg(args, 1))) return h.typeError(&s, &.{try s.text("a derivation needs a function")});
        const host = try s.get(object, "host");
        const derives = try s.get(decls, "derives");
        const key = try position(&s, derives);
        const derived = try h.construct(&s, bindings, "Derived", &.{ key, h.arg(args, 0), h.arg(args, 1), try sourceOptions(&s, host) });
        try js.push(engine, try s.get(created, "derives"), derived);
        _ = try h.invoke(&s, derives, "set", &.{ key, derived });
        return s.result(derived);
    }
    if (method == .expose) {
        const resource = try s.keep(try @import("native_chord_latest_resources.zig").resourceOf(engine, h.arg(args, 0), try s.get(bindings, "resourceBindings")));
        const resources = try h.values(&s, try s.get(decls, "resources"));
        if (c.JS_IsUndefined(resource) or c.JS_ToBool(engine.context, try h.invoke(&s, resources, "includes", &.{resource})) == 0) return h.typeError(&s, &.{try s.text("expose takes a resource declared by this object")});
        return s.result(try h.construct(&s, bindings, "ExposedImpl", &.{resource}));
    }
    if (!try h.flag(&s, object, "hostLifetime")) return h.invalid(&s, bindings, "not_host_lifetime", &.{ try s.get(object, "typeName"), try s.text(": only objects of lifetime \"host\" may register") });
    const registry = h.arg(args, 0);
    const entries = try s.entries(h.arg(args, 1));
    for (0..try h.length(&s, entries)) |index| {
        const entry = try s.at(entries, index);
        const key = try s.at(entry, 0);
        const id = try r.concat(&s, &.{ try s.get(registry, "name"), try s.text("\x00"), key });
        const registrations = try s.get(decls, "registrations");
        try unique(&s, bindings, object, registrations, "register", id);
        const registration = try s.record();
        try h.field(&s, registration, "registry", registry);
        try h.field(&s, registration, "key", key);
        try h.field(&s, registration, "value", try s.at(entry, 1));
        _ = try h.invoke(&s, registrations, "set", &.{ id, registration });
    }
    return c.pi_js_undefined();
}
fn get(s: *Scope, bindings: c.JSValue, object: c.JSValue, previous: c.JSValue, decls: c.JSValue, created: c.JSValue, args: []const c.JSValue) !c.JSValue {
    const host = try s.get(object, "host");
    const token = h.arg(args, 0);
    const options = h.arg(args, 2);
    const principal = try r.optional(s, options, "principal");
    const candidate = !c.JS_IsUndefined(previous);
    const address = try h.invoke(s, host, "addressOf", &.{ token, h.arg(args, 1), r.default(s, principal, try s.get(host, "principal")), c.pi_js_bool(s.engine.context, @intFromBool(candidate)) });
    const refs = try s.get(decls, "refs");
    const declared = try h.invoke(s, refs, "get", &.{address});
    if (!c.JS_IsUndefined(declared)) {
        if (!c.JS_IsStrictEqual(s.engine.context, try s.get(try s.get(declared, "contract"), "fingerprint"), try s.get(token, "fingerprint"))) return h.invalid(s, bindings, "duplicate", &.{ try s.get(object, "typeName"), try s.text(": "), try s.get(token, "name"), try s.text(" held twice with different contracts") });
        return js.get(s.engine, declared, "proxy");
    }
    const existing = if (h.nullish(previous)) c.pi_js_undefined() else try h.invoke(s, try s.get(previous, "refs"), "get", &.{address});
    if (!c.JS_IsUndefined(existing) and c.JS_IsStrictEqual(s.engine.context, try s.get(try s.get(existing, "contract"), "fingerprint"), try s.get(token, "fingerprint")) and !try s.equal(try s.get(existing, "status"), "gone") and !try s.equal(try s.get(existing, "status"), "released")) {
        _ = try h.invoke(s, refs, "set", &.{ address, existing });
        return js.get(s.engine, existing, "proxy");
    }
    const ref = try h.invoke(s, host, "acquire", &.{ token, h.arg(args, 1), options, try s.text("object"), object, c.pi_js_bool(s.engine.context, @intFromBool(candidate)) });
    _ = try h.invoke(s, refs, "set", &.{ address, ref });
    try js.push(s.engine, try s.get(created, "refs"), ref);
    return js.get(s.engine, ref, "proxy");
}
fn construct(engine: *h.Engine, target: c.JSValue, args: []const c.JSValue, captures: []const c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    const result = try s.keep(try h.allocate(engine, target, captures[0], .ObjectSelf));
    const data = (try h.actor(&s, result, captures[0], .ObjectSelf)).data;
    try h.field(&s, data, "object", h.arg(args, 0));
    try h.field(&s, data, "previous", h.arg(args, 1));
    try h.field(&s, data, "decls", try h.construct(&s, captures[0], "Decls", &.{}));
    const created = try s.record();
    inline for (.{ "refs", "resources", "derives", "inits" }) |name| try h.field(&s, created, name, try s.list());
    try h.field(&s, data, "created", created);
    return s.result(result);
}
pub fn install(engine: *h.Engine, bindings: c.JSValue) !void {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    try h.register(&s, bindings, .ObjectSelf);
    const prototype = try s.record();
    try js.define(engine, bindings, "SelfImpl", try @import("native_class.zig").constructor(engine, "SelfImpl", 2, prototype, construct, &.{bindings}));
    inline for (.{ .{ Method.run, 1 }, .{ Method.state, 3 }, .{ Method.get, 3 }, .{ Method.resource, 2 }, .{ Method.on, 2 }, .{ Method.task, 1 }, .{ Method.derive, 2 }, .{ Method.expose, 1 }, .{ Method.register, 2 } }) |entry| try h.define(&s, prototype, bindings, @tagName(entry[0]), callback, @intFromEnum(entry[0]), entry[1], false, false);
}
