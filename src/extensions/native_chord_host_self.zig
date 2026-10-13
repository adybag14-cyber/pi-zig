//! Actual factory SelfImpl declaration ownership, dependencies and exposure.
const h = @import("native_chord_host_values.zig");
const Scope = h.Scope;
const js = h.js;
const c = h.c;
const Method = enum(c_int) { run, state, get, resources, listen, tasks, derive, expose, register };
fn callback(context: ?*c.JSContext, receiver: c.JSValue, argc: c_int, argv: [*c]c.JSValue, operation: c_int, data: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = h.Engine.fromContext(context.?);
    return invoke(engine, receiver, if (argc > 0) argv[0..@intCast(argc)] else &.{}, @enumFromInt(operation), data[0]) catch |err| @import("native_durable.zig").reject(engine, err);
}
fn entries(s: *Scope, input: c.JSValue, kind: []const u8) !c.JSValue {
    if (!c.JS_IsObject(input) or c.JS_IsFunction(s.engine.context, input)) return h.typeError(s, &.{ try s.text(kind), try s.text(" takes an object of named declarations") });
    return s.entries(input);
}
fn checkEntry(s: *Scope, bindings: c.JSValue, record: c.JSValue, map: c.JSValue, kind: []const u8, name: c.JSValue, declaration: c.JSValue, descriptor: ?[]const u8) !void {
    if (c.JS_ToBool(s.engine.context, try h.invoke(s, map, "has", &.{name})) != 0) {
        _ = try h.invalid(s, bindings, "duplicate", &.{ try s.get(record, "typeName"), try s.text(": duplicate "), try s.text(kind), try s.text(" name "), name });
    }
    if (descriptor) |expected| {
        const declarations = try s.get(bindings, "declarations");
        const tag = try h.invoke(s, declarations, "declKind", &.{declaration});
        if (!try s.equal(tag, expected)) _ = try h.typeError(s, &.{ try s.text(kind), try s.text("."), name, try s.text(" must be declared with "), try s.text(expected), try s.text("()") });
    }
}
fn dependency(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, data: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = h.Engine.fromContext(context.?);
    return resolveDependency(engine, if (argc > 0) argv[0] else c.pi_js_undefined(), data[0], data[1]) catch |err| @import("native_durable.zig").reject(engine, err);
}
fn resolveDependency(engine: *h.Engine, value: c.JSValue, bindings: c.JSValue, name: c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    if (c.JS_IsObject(value) and !c.JS_IsFunction(engine.context, value)) {
        const hold = try h.invoke(&s, try s.get(bindings, "holdsByProxy"), "get", &.{value});
        if (!h.nullish(hold)) return s.result(hold);
    }
    const resource = try s.keep(try @import("native_chord_resources.zig").resourceOf(engine, value, try s.get(bindings, "resourceBindings")));
    if (c.JS_IsUndefined(resource)) return h.typeError(&s, &.{ try s.text("resource "), name, try s.text(": deps must be handles or resources of this record") });
    return s.result(resource);
}
fn sameDependencies(s: *Scope, left: c.JSValue, right: c.JSValue) !bool {
    const count = try h.length(s, left);
    if (count != try h.length(s, right)) return false;
    for (0..count) |index| {
        const key = c.JS_NewUint32(s.engine.context, @intCast(index));
        if (!try js.hasKey(s.engine, left, key)) continue;
        if (!c.JS_IsStrictEqual(s.engine.context, try s.at(left, index), try s.at(right, index))) return false;
    }
    return true;
}
fn resources(s: *Scope, receiver: c.JSValue, input: c.JSValue, bindings: c.JSValue) anyerror!c.JSValue {
    const owned = try h.actor(s, receiver, bindings, .SelfImpl);
    const record = try s.get(owned.data, "record");
    const decls = try s.get(owned.data, "decls");
    const declared = try s.get(decls, "resources");
    const previous = try s.get(owned.data, "previous");
    const result = try s.record();
    const list = try entries(s, input, "resources");
    const count = try h.length(s, list);
    for (0..count) |index| {
        const entry = try s.at(list, index);
        const name = try s.at(entry, 0);
        const declaration = try s.at(entry, 1);
        try checkEntry(s, bindings, record, declared, "resources", name, declaration, "resource");
        const spec = try s.get(declaration, "spec");
        const raw_deps = try s.get(spec, "deps");
        const deps_source = if (h.nullish(raw_deps)) try s.list() else raw_deps;
        var captures = [_]c.JSValue{ bindings, name };
        const resolver = try s.keep(try s.engine.checked(c.JS_NewCFunctionData2(s.engine.context, dependency, "", 1, 0, 2, &captures)));
        const deps = try h.invoke(s, deps_source, "map", &.{resolver});
        const existing = if (h.nullish(previous)) c.pi_js_undefined() else try h.invoke(s, try s.get(previous, "resources"), "get", &.{name});
        const exclusive = c.JS_IsStrictEqual(s.engine.context, try s.get(spec, "exclusive"), c.pi_js_bool(s.engine.context, 1));
        const kept = !c.JS_IsUndefined(existing) and c.JS_IsStrictEqual(s.engine.context, try s.get(try s.get(existing, "spec"), "rev"), try s.get(spec, "rev")) and (c.JS_ToBool(s.engine.context, try s.get(existing, "exclusive")) != 0) == exclusive and try sameDependencies(s, try s.get(existing, "deps"), deps);
        const resource = if (kept) existing else try h.construct(s, bindings, "ResourceImpl", &.{ name, spec, deps });
        if (!kept) _ = try h.invoke(s, try s.get(try s.get(owned.data, "created"), "resources"), "push", &.{resource});
        _ = try h.invoke(s, declared, "set", &.{ name, resource });
        const facade = try h.construct(s, bindings, "ResourceFacade", &.{ resource, try s.get(record, "host") });
        try js.setKey(s.engine, result, name, facade);
    }
    return s.result(result);
}
fn invoke(engine: *h.Engine, receiver: c.JSValue, args: []const c.JSValue, method: Method, bindings: c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    const owned = try h.actor(&s, receiver, bindings, .SelfImpl);
    const record = try s.get(owned.data, "record");
    const decls = try s.get(owned.data, "decls");
    if (method == .resources) return resources(&s, receiver, h.arg(args, 0), bindings);
    if (method == .state or method == .derive) {
        const is_state = method == .state;
        const map = try s.get(decls, if (is_state) "cells" else "derives");
        const previous = try s.get(owned.data, "previous");
        const result = try s.record();
        const list = try entries(&s, h.arg(args, 0), if (is_state) "state" else "derive");
        for (0..try h.length(&s, list)) |index| {
            const entry = try s.at(list, index);
            const name = try s.at(entry, 0);
            const declaration = try s.at(entry, 1);
            try checkEntry(&s, bindings, record, map, if (is_state) "state" else "derive", name, declaration, if (is_state) "cell" else "derivation");
            const existing = if (h.nullish(previous)) c.pi_js_undefined() else try h.invoke(&s, try s.get(previous, if (is_state) "cells" else "derives"), "get", &.{name});
            const options = try s.record();
            const host = try s.get(record, "host");
            try h.field(&s, options, "dev", try s.get(host, "dev"));
            var captures = [_]c.JSValue{host};
            try h.field(&s, options, "report", try s.keep(try engine.checked(c.JS_NewCFunctionData2(engine.context, report, "report", 1, 0, 1, &captures))));
            var value = existing;
            if (is_state) {
                if (c.JS_IsUndefined(value)) value = try h.construct(&s, bindings, "Cell", &.{ name, try s.get(declaration, "schema"), try s.get(declaration, "initial"), try s.get(record, "guard"), options });
                _ = try h.invoke(&s, try s.get(decls, "cellSchemas"), "set", &.{ name, try s.get(declaration, "schema") });
            } else {
                const sources = try s.get(declaration, "sources");
                if (c.JS_IsUndefined(existing) or !try sameDependencies(&s, try s.get(existing, "sources"), sources)) {
                    value = try h.construct(&s, bindings, "Derived", &.{ name, sources, try s.get(declaration, "fn"), options });
                    _ = try h.invoke(&s, try s.get(try s.get(owned.data, "created"), "derives"), "push", &.{value});
                }
                _ = try h.invoke(&s, try s.get(decls, "deriveFns"), "set", &.{ name, try s.get(declaration, "fn") });
            }
            _ = try h.invoke(&s, map, "set", &.{ name, value });
            try js.setKey(engine, result, name, value);
        }
        return s.result(result);
    }
    if (method == .run) {
        const result = try s.record();
        try h.field(&s, result, "behavior", h.arg(args, 0));
        try h.field(&s, result, "decls", decls);
        try h.field(&s, result, "created", try s.get(owned.data, "created"));
        return s.result(result);
    }
    if (method == .get) {
        const host = try s.get(record, "host");
        const type_value = h.arg(args, 0);
        const options = h.arg(args, 2);
        const principal = if (h.nullish(options)) c.pi_js_undefined() else try s.get(options, "principal");
        const at = if (h.nullish(options)) c.pi_js_undefined() else try s.get(options, "at");
        const candidate = !c.JS_IsUndefined(try s.get(owned.data, "previous"));
        const address = try h.invoke(&s, host, "addressOf", &.{ type_value, h.arg(args, 1), if (h.nullish(principal)) try s.get(host, "principal") else principal, at, c.pi_js_bool(engine.context, @intFromBool(candidate)) });
        const holds = try s.get(decls, "holds");
        const declared = try h.invoke(&s, holds, "get", &.{address});
        if (!c.JS_IsUndefined(declared)) {
            if (!c.JS_IsStrictEqual(engine.context, try s.get(try s.get(declared, "contract"), "fingerprint"), try s.get(type_value, "fingerprint"))) return h.invalid(&s, bindings, "duplicate", &.{ try s.get(record, "typeName"), try s.text(": "), try s.get(type_value, "name"), try s.text(" held twice with different contracts") });
            return js.get(engine, declared, "proxy");
        }
        const previous = try s.get(owned.data, "previous");
        const existing = if (h.nullish(previous)) c.pi_js_undefined() else try h.invoke(&s, try s.get(previous, "holds"), "get", &.{address});
        if (!c.JS_IsUndefined(existing) and c.JS_IsStrictEqual(engine.context, try s.get(try s.get(existing, "contract"), "fingerprint"), try s.get(type_value, "fingerprint")) and !try s.equal(try s.get(existing, "status"), "gone") and !try s.equal(try s.get(existing, "status"), "released")) {
            _ = try h.invoke(&s, holds, "set", &.{ address, existing });
            return js.get(engine, existing, "proxy");
        }
        const handle = try h.invoke(&s, host, "acquire", &.{ type_value, h.arg(args, 1), options, try s.text("record"), record, c.pi_js_bool(engine.context, @intFromBool(candidate)) });
        _ = try h.invoke(&s, holds, "set", &.{ address, handle });
        _ = try h.invoke(&s, try s.get(try s.get(owned.data, "created"), "holds"), "push", &.{handle});
        return js.get(engine, handle, "proxy");
    }
    if (method == .expose) {
        const resolved = try s.keep(try @import("native_chord_resources.zig").resourceOf(engine, h.arg(args, 0), try s.get(bindings, "resourceBindings")));
        const resources_values = try h.values(&s, try s.get(decls, "resources"));
        if (c.JS_IsUndefined(resolved) or c.JS_ToBool(engine.context, try h.invoke(&s, resources_values, "includes", &.{resolved})) == 0) return h.typeError(&s, &.{try s.text("expose takes a resource declared by this record")});
        return s.result(try h.construct(&s, bindings, "ExposedImpl", &.{resolved}));
    }
    if (method == .register) {
        if (!try h.flag(&s, record, "eager")) return h.invalid(&s, bindings, "not_eager", &.{ try s.get(record, "typeName"), try s.text(": only eager records may register") });
        const registry = h.arg(args, 0);
        const values = try s.entries(h.arg(args, 1));
        const prefixed = try s.record();
        const count = try h.length(&s, values);
        for (0..count) |index| {
            const entry = try s.at(values, index);
            const id = try s.keep(try @import("native_utf16.zig").concat(engine, &.{ try s.get(registry, "name"), try s.text("\x00"), try s.at(entry, 0) }));
            try js.setKey(engine, prefixed, id, try s.at(entry, 1));
        }
        const declarations = try entries(&s, prefixed, "register");
        const registrations = try s.get(decls, "registrations");
        const size = try h.length(&s, declarations);
        for (0..size) |index| {
            const entry = try s.at(declarations, index);
            const id = try s.at(entry, 0);
            const value = try s.at(entry, 1);
            try checkEntry(&s, bindings, record, registrations, "register", id, value, null);
            const name_length = try s.get(try s.get(registry, "name"), "length");
            var start: f64 = undefined;
            if (c.JS_ToFloat64(engine.context, &start, name_length) < 0) return js.capture(engine);
            const registration = try s.record();
            try h.field(&s, registration, "registry", registry);
            try h.field(&s, registration, "key", try h.invoke(&s, id, "slice", &.{c.JS_NewFloat64(engine.context, start + 1)}));
            try h.field(&s, registration, "value", value);
            _ = try h.invoke(&s, registrations, "set", &.{ id, registration });
        }
        return c.pi_js_undefined();
    }
    const name: []const u8 = if (method == .listen) "listen" else "tasks";
    const field_name: [*:0]const u8 = if (method == .listen) "listeners" else "tasks";
    const map = try s.get(decls, field_name);
    const values = try entries(&s, h.arg(args, 0), name);
    const count = try h.length(&s, values);
    for (0..count) |index| {
        const entry = try s.at(values, index);
        const key = try s.at(entry, 0);
        const value = try s.at(entry, 1);
        try checkEntry(&s, bindings, record, map, name, key, value, if (method == .listen) "listener" else null);
        if (method == .tasks and !c.JS_IsFunction(engine.context, value)) return h.typeError(&s, &.{ try s.text("tasks."), key, try s.text(" must be a function") });
        _ = try h.invoke(&s, map, "set", &.{ key, value });
    }
    return c.pi_js_undefined();
}
fn construct(engine: *h.Engine, target: c.JSValue, args: []const c.JSValue, values: []const c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    const result = try s.keep(try h.allocate(engine, target, values[0], .SelfImpl));
    const owned = try h.actor(&s, result, values[0], .SelfImpl);
    try h.field(&s, owned.data, "record", h.arg(args, 0));
    try h.field(&s, owned.data, "previous", h.arg(args, 1));
    try h.field(&s, owned.data, "decls", try h.construct(&s, values[0], "Decls", &.{}));
    const created = try s.record();
    inline for (.{ "holds", "resources", "derives" }) |name| try h.field(&s, created, name, try s.list());
    try h.field(&s, owned.data, "created", created);
    return s.result(result);
}
pub fn install(engine: *h.Engine, bindings: c.JSValue) !void {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    try h.register(&s, bindings, .SelfImpl);
    const prototype = try s.record();
    try js.define(engine, bindings, "SelfImpl", try @import("native_class.zig").constructor(engine, "SelfImpl", 2, prototype, construct, &.{bindings}));
    inline for (.{ .{ "run", Method.run, 1 }, .{ "state", Method.state, 1 }, .{ "get", Method.get, 3 }, .{ "resources", Method.resources, 1 }, .{ "listen", Method.listen, 1 }, .{ "tasks", Method.tasks, 1 }, .{ "derive", Method.derive, 1 }, .{ "expose", Method.expose, 1 }, .{ "register", Method.register, 2 } }) |item| try h.define(&s, prototype, bindings, item[0], callback, @intFromEnum(item[1]), item[2], false, false);
}
fn report(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, data: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = h.Engine.fromContext(context.?);
    return js.invoke(engine, data[0], "report", &.{if (argc > 0) argv[0] else c.pi_js_undefined()}) catch |err| @import("native_durable.zig").reject(engine, err);
}
