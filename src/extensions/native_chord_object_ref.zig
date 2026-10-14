//! Actual HandleImpl late-bound proxy, consumer views and per-hold lifetime.
const h = @import("native_chord_host_values.zig");
const Scope = h.Scope;
const js = h.js;
const c = h.c;
const Method = enum(c_int) { variant, shape, onShape, onStatus, release, live, gone, shapeChanged, terminalError, viewOf, currentView, describe, inVariant, member, caller };
fn callback(context: ?*c.JSContext, receiver: c.JSValue, argc: c_int, argv: [*c]c.JSValue, operation: c_int, data: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = h.Engine.fromContext(context.?);
    return invoke(engine, receiver, if (argc > 0) argv[0..@intCast(argc)] else &.{}, @enumFromInt(operation), data[0]) catch |err| @import("native_durable.zig").reject(engine, err);
}
fn variantOf(s: *Scope, view: c.JSValue) !c.JSValue {
    const value = try s.get(view, "variant");
    return if (c.JS_IsString(value)) value else c.pi_js_undefined();
}
fn describe(s: *Scope, receiver: c.JSValue, kind: c.JSValue, name: c.JSValue) !c.JSValue {
    const variants = try s.get(try s.get(try s.get(receiver, "contract"), "description"), "variants");
    if (!c.JS_IsUndefined(kind)) {
        const members = try s.key(variants, kind);
        return if (h.nullish(members)) c.pi_js_undefined() else try s.key(members, name);
    }
    const values = try s.builtin("Object", "values", &.{variants});
    const count = try h.length(s, values);
    for (0..count) |index| {
        const member = try s.key(try s.at(values, index), name);
        if (!c.JS_IsUndefined(member)) return member;
    }
    return c.pi_js_undefined();
}
fn viewOf(s: *Scope, receiver: c.JSValue, installed: c.JSValue, bindings: c.JSValue) !c.JSValue {
    const provider = try s.get(installed, "service");
    const mappings = try s.get(receiver, "bindings");
    var adapter = try h.invoke(s, mappings, "get", &.{provider});
    if (c.JS_ToBool(s.engine.context, try h.invoke(s, mappings, "has", &.{provider})) == 0) {
        adapter = try h.invoke(s, try s.get(bindings, "contracts"), "bind", &.{ try s.get(provider, "contract"), try s.get(try s.get(provider, "options"), "accepts"), try s.get(receiver, "contract") });
        _ = try h.invoke(s, mappings, "set", &.{ provider, adapter });
    }
    const behavior = try s.get(installed, "implementation");
    if (c.JS_IsUndefined(adapter)) return behavior;
    const views = try s.get(receiver, "views");
    var view = try h.invoke(s, views, "get", &.{behavior});
    if (c.JS_IsUndefined(view)) {
        view = try s.keep(try js.call(s.engine, adapter, c.pi_js_undefined(), &.{behavior}));
        _ = try h.invoke(s, views, "set", &.{ behavior, view });
    }
    return view;
}
fn safeView(s: *Scope, receiver: c.JSValue, installed: c.JSValue, bindings: c.JSValue) !c.JSValue {
    return viewOf(s, receiver, installed, bindings) catch |err| {
        if (err != error.JavaScriptException) return err;
        const failure = s.engine.captured_exception orelse return err;
        _ = try h.invoke(s, try s.get(try s.get(receiver, "object"), "host"), "report", &.{failure});
        return c.pi_js_undefined();
    };
}
fn currentView(s: *Scope, receiver: c.JSValue, bindings: c.JSValue) !c.JSValue {
    if (!try s.equal(try s.get(receiver, "status"), "live")) return c.pi_js_undefined();
    const installed = try h.invoke(s, try s.get(receiver, "object"), "currentInstalled", &.{});
    return if (c.JS_IsUndefined(installed)) c.pi_js_undefined() else safeView(s, receiver, installed, bindings);
}
fn unsubscribe(context: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue, _: c_int, data: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = h.Engine.fromContext(context.?);
    return js.invoke(engine, data[0], "delete", &.{data[1]}) catch |err| @import("native_durable.zig").reject(engine, err);
}
fn notification(context: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue, operation: c_int, data: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = h.Engine.fromContext(context.?);
    return notify(engine, data, operation != 0) catch |err| @import("native_durable.zig").reject(engine, err);
}
fn notify(engine: *h.Engine, data: [*c]c.JSValue, shape: bool) !c.JSValue {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    const listeners = data[0];
    const count = try h.length(&s, listeners);
    for (0..count) |index| {
        var args = [_]c.JSValue{ data[1], data[2] };
        const value = js.call(engine, try s.at(listeners, index), c.pi_js_undefined(), args[0..if (shape) @as(usize, 1) else 2]) catch |err| {
            if (err != error.JavaScriptException) return err;
            _ = try h.invoke(&s, data[3], "report", &.{engine.captured_exception orelse return err});
            continue;
        };
        engine.freeValue(value);
    }
    return c.pi_js_undefined();
}
fn statusChanged(s: *Scope, receiver: c.JSValue, bindings: c.JSValue) !void {
    const owned = try h.actor(s, receiver, bindings, .RefImpl);
    const listeners = try s.get(owned.data, "statusListeners");
    if (c.JS_IsStrictEqual(s.engine.context, try s.get(listeners, "size"), c.JS_NewInt32(s.engine.context, 0))) return;
    var captures = [_]c.JSValue{ try h.snapshot(s, listeners), try s.get(receiver, "status"), try s.get(receiver, "error"), try s.get(try s.get(receiver, "object"), "host") };
    const task = try s.keep(try s.engine.checked(c.JS_NewCFunctionData2(s.engine.context, notification, "", 0, 0, 4, &captures)));
    try @import("native_chord_publish.zig").enqueue(s.engine, bindings, task);
}
fn stopReadables(s: *Scope, receiver: c.JSValue) !void {
    const values = try h.values(s, try s.get(receiver, "readables"));
    const count = try h.length(s, values);
    for (0..count) |index| _ = try h.invoke(s, try s.at(values, index), "stop", &.{});
}
fn filterKind(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, _: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = h.Engine.fromContext(context.?);
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    const same = s.equal(if (argc > 0) argv[0] else c.pi_js_undefined(), "variant") catch |err| return @import("native_durable.zig").reject(engine, err);
    return c.pi_js_bool(engine.context, @intFromBool(!same));
}
fn callerCallback(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, no_args: c_int, data: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = h.Engine.fromContext(context.?);
    return call(engine, data[0], data[1], if (no_args == 0 and argc > 0) argv[0] else c.pi_js_undefined(), if (no_args != 0 and argc > 0) argv[0] else if (argc > 1) argv[1] else c.pi_js_undefined(), data[2]) catch |err| @import("native_durable.zig").reject(engine, err);
}
pub fn takesNoArgs(s: *Scope, contract: c.JSValue, name: c.JSValue) !bool {
    const members = try s.builtin("Object", "values", &.{try s.get(try s.get(contract, "description"), "variants")});
    for (0..try h.length(s, members)) |index| {
        const member = try s.key(try s.at(members, index), name);
        if (!h.nullish(member) and try s.equal(try s.get(member, "kind"), "method")) return c.JS_IsUndefined(try s.get(member, "args"));
    }
    return false;
}
fn callRoot(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, data: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = h.Engine.fromContext(context.?);
    return callInRoot(engine, data[0], data[1], data[2], if (argc > 0) argv[0] else c.pi_js_undefined()) catch |err| @import("native_durable.zig").reject(engine, err);
}
fn callInRoot(engine: *h.Engine, handle: c.JSValue, name: c.JSValue, input: c.JSValue, context: c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    return js.invoke(engine, try s.get(handle, "object"), "call", &.{ handle, name, input, context });
}
fn call(engine: *h.Engine, receiver: c.JSValue, name: c.JSValue, input: c.JSValue, context: c.JSValue, bindings: c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    const host = try s.get(try s.get(receiver, "object"), "host");
    var count: f64 = undefined;
    if (c.JS_ToFloat64(engine.context, &count, try s.get(host, "inFactory")) < 0) return js.capture(engine);
    if (count > 0) return h.throwValue(&s, try h.errorValue(&s, bindings, "not_ready", &.{ try s.get(receiver, "address"), try s.text("."), name, try s.text(" called inside a factory") }, c.pi_js_undefined()));
    if (!c.JS_IsUndefined(context)) {
        const constructor = try s.get(bindings, "CtxImpl");
        const instance = c.JS_IsInstanceOf(engine.context, context, constructor);
        if (instance < 0) return js.capture(engine);
        if (instance == 0) {
            const detail = try s.record();
            try h.field(&s, detail, "reason", try s.text("foreign_ctx"));
            const failure = try h.errorValue(&s, bindings, "invalid", &.{try s.text("ctx must come from a Chord host")}, detail);
            const promise = try s.keep(try js.global(engine, "Promise"));
            return js.invoke(engine, promise, "reject", &.{failure});
        }
    }
    if (c.JS_IsUndefined(context) or try h.flag(&s, context, "holder")) {
        if (!c.JS_IsUndefined(context)) {
            _ = h.invoke(&s, context, "check", &.{host}) catch |err| {
                if (err != error.JavaScriptException) return err;
                const promise = try s.keep(try js.global(engine, "Promise"));
                return js.invoke(engine, promise, "reject", &.{engine.captured_exception orelse return err});
            };
        }
        const settings = try s.record();
        try h.field(&s, settings, "signal", if (h.nullish(context)) c.pi_js_undefined() else try s.get(context, "signal"));
        var captures = [_]c.JSValue{ receiver, name, input };
        const function = try s.keep(try engine.checked(c.JS_NewCFunctionData2(engine.context, callRoot, "", 1, 0, 3, &captures)));
        return js.invoke(engine, host, "root", &.{ function, settings });
    }
    return js.invoke(engine, try s.get(receiver, "object"), "call", &.{ receiver, name, input, context });
}
fn invoke(engine: *h.Engine, receiver: c.JSValue, args: []const c.JSValue, method: Method, bindings: c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    if (method == .viewOf) return s.result(try viewOf(&s, receiver, h.arg(args, 0), bindings));
    if (method == .currentView) return s.result(try currentView(&s, receiver, bindings));
    if (method == .describe) return s.result(try describe(&s, receiver, h.arg(args, 0), h.arg(args, 1)));
    if (method == .variant) {
        const view = try currentView(&s, receiver, bindings);
        return if (c.JS_IsUndefined(view)) c.pi_js_undefined() else s.result(try variantOf(&s, view));
    }
    if (method == .shape) {
        const installed = if (try s.equal(try s.get(receiver, "status"), "live")) try h.invoke(&s, try s.get(receiver, "object"), "currentInstalled", &.{}) else c.pi_js_undefined();
        const view = if (c.JS_IsUndefined(installed)) c.pi_js_undefined() else try safeView(&s, receiver, installed, bindings);
        if (c.JS_IsUndefined(installed) or c.JS_IsUndefined(view)) return c.pi_js_undefined();
        const result = try s.record();
        try h.field(&s, result, "variant", try variantOf(&s, view));
        const filter = try s.keep(try engine.checked(c.JS_NewCFunctionData2(engine.context, filterKind, "", 1, 0, 0, null)));
        try h.field(&s, result, "members", try h.invoke(&s, try s.keys(view), "filter", &.{filter}));
        try h.field(&s, result, "contract", try s.get(try s.get(try s.get(installed, "service"), "contract"), "fingerprint"));
        try h.field(&s, result, "codeVersion", try s.get(installed, "codeVersion"));
        return s.result(result);
    }
    if (method == .onShape or method == .onStatus) {
        const set = if (method == .onShape) try s.get(receiver, "shapeListeners") else try s.get((try h.actor(&s, receiver, bindings, .RefImpl)).data, "statusListeners");
        _ = try h.invoke(&s, set, "add", &.{h.arg(args, 0)});
        var captures = [_]c.JSValue{ set, h.arg(args, 0) };
        return engine.checked(c.JS_NewCFunctionData2(engine.context, unsubscribe, "", 0, 0, 2, &captures));
    }
    if (method == .release or method == .gone) {
        if (try s.equal(try s.get(receiver, "status"), "released") or try s.equal(try s.get(receiver, "status"), "gone")) return c.pi_js_undefined();
        try h.field(&s, receiver, "status", try s.text(if (method == .release) "released" else "gone"));
        if (method == .gone) try h.field(&s, receiver, "error", h.arg(args, 0));
        try stopReadables(&s, receiver);
        try statusChanged(&s, receiver, bindings);
        if (method == .release) {
            _ = try h.invoke(&s, try s.get(receiver, "object"), "release", &.{receiver});
        } else {
            const listeners = try h.snapshot(&s, try s.get(receiver, "goneListeners"));
            const count = try h.length(&s, listeners);
            for (0..count) |index| _ = try s.keep(try js.call(engine, try s.at(listeners, index), c.pi_js_undefined(), &.{h.arg(args, 0)}));
        }
        return c.pi_js_undefined();
    }
    if (method == .live) {
        if (!try s.equal(try s.get(receiver, "status"), "loading")) return c.pi_js_undefined();
        try h.field(&s, receiver, "status", try s.text("live"));
        try statusChanged(&s, receiver, bindings);
        _ = try h.invoke(&s, receiver, "shapeChanged", &.{});
        return c.pi_js_undefined();
    }
    if (method == .shapeChanged) {
        const readables = try h.values(&s, try s.get(receiver, "readables"));
        const count = try h.length(&s, readables);
        for (0..count) |index| _ = try h.invoke(&s, try s.at(readables, index), "bind", &.{});
        const shape = try s.get(receiver, "shape");
        if (c.JS_IsUndefined(shape)) return c.pi_js_undefined();
        var captures = [_]c.JSValue{ try h.snapshot(&s, try s.get(receiver, "shapeListeners")), shape, c.pi_js_undefined(), try s.get(try s.get(receiver, "object"), "host") };
        const task = try s.keep(try engine.checked(c.JS_NewCFunctionData2(engine.context, notification, "", 0, 1, 4, &captures)));
        try @import("native_chord_publish.zig").enqueue(engine, bindings, task);
        return c.pi_js_undefined();
    }
    if (method == .terminalError) return if (try s.equal(try s.get(receiver, "status"), "gone")) s.result(try s.get(receiver, "error")) else s.result(try h.errorValue(&s, bindings, "released", &.{ try s.text("reference "), try s.get(receiver, "address"), try s.text(" released") }, c.pi_js_undefined()));
    if (method == .inVariant) {
        if (!try s.equal(try s.get(try s.get(receiver, "contract"), "scope"), "remote")) return c.pi_js_bool(engine.context, 1);
        return c.pi_js_bool(engine.context, @intFromBool(!c.JS_IsUndefined(try describe(&s, receiver, try variantOf(&s, h.arg(args, 0)), h.arg(args, 1)))));
    }
    if (method == .caller) {
        const callers = try s.get(receiver, "callers");
        var function = try h.invoke(&s, callers, "get", &.{h.arg(args, 0)});
        if (c.JS_IsUndefined(function)) {
            var captures = [_]c.JSValue{ receiver, h.arg(args, 0), bindings };
            const no_args = try takesNoArgs(&s, try s.get(receiver, "contract"), h.arg(args, 0));
            function = try s.keep(try engine.checked(c.JS_NewCFunctionData2(engine.context, callerCallback, "caller", 0, @intFromBool(no_args), 3, &captures)));
            _ = try h.invoke(&s, callers, "set", &.{ h.arg(args, 0), function });
        }
        return s.result(function);
    }
    const name = h.arg(args, 0);
    const declared = try describe(&s, receiver, c.pi_js_undefined(), name);
    const view = try currentView(&s, receiver, bindings);
    const value = if (h.nullish(view)) c.pi_js_undefined() else try s.key(view, name);
    const declared_kind = if (h.nullish(declared)) c.pi_js_undefined() else try s.get(declared, "kind");
    if (try s.equal(declared_kind, "method") or (c.JS_IsUndefined(declared) and c.JS_IsFunction(engine.context, value))) return js.invoke(engine, receiver, "caller", &.{name});
    if (try s.equal(declared_kind, "state") or (c.JS_IsUndefined(declared) and (try @import("native_chord_object_schema.zig").source(&s, bindings, value) or try @import("native_chord_object_schema.zig").readable(&s, value)))) {
        const readables = try s.get(receiver, "readables");
        var readable = try h.invoke(&s, readables, "get", &.{name});
        if (c.JS_IsUndefined(readable)) {
            readable = try h.construct(&s, bindings, "MemberReadable", &.{ receiver, name });
            _ = try h.invoke(&s, readables, "set", &.{ name, readable });
        }
        return s.result(readable);
    }
    if (c.JS_IsUndefined(view) or c.JS_ToBool(engine.context, try h.invoke(&s, receiver, "inVariant", &.{ view, name })) == 0) return c.pi_js_undefined();
    const exposed_type = try s.get(bindings, "ExposedImpl");
    const exposed = c.JS_IsInstanceOf(engine.context, value, exposed_type);
    if (exposed < 0) return js.capture(engine);
    return if (exposed != 0) js.get(engine, try s.get(value, "resource"), "value") else s.result(value);
}
fn ready(context: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue, _: c_int, data: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = h.Engine.fromContext(context.?);
    return readyValue(engine, data[0], data[1]) catch |err| @import("native_durable.zig").reject(engine, err);
}
fn readyValue(engine: *h.Engine, receiver: c.JSValue, bindings: c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    if (try s.equal(try s.get(receiver, "status"), "gone")) return h.throwValue(&s, try s.get(receiver, "error"));
    if (try s.equal(try s.get(receiver, "status"), "released")) return h.throwValue(&s, try h.errorValue(&s, bindings, "released", &.{ try s.text("reference "), try s.get(receiver, "address"), try s.text(" released") }, c.pi_js_undefined()));
    return c.pi_js_undefined();
}
fn noop(_: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue, _: c_int, _: [*c]c.JSValue) callconv(.c) c.JSValue {
    return c.pi_js_undefined();
}
fn proxy(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, operation: c_int, data: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = h.Engine.fromContext(context.?);
    return proxyValue(engine, if (argc > 0) argv[0] else c.pi_js_undefined(), if (argc > 1) argv[1] else c.pi_js_undefined(), operation != 0, data[0]) catch |err| @import("native_durable.zig").reject(engine, err);
}
pub fn proxyValue(engine: *h.Engine, target: c.JSValue, property: c.JSValue, has: bool, bindings: c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    const base = try h.invoke(&s, try s.get(bindings, "refBase"), "has", &.{property});
    if (c.JS_ToBool(engine.context, base) != 0) {
        if (has) return c.pi_js_bool(engine.context, 1);
        const reflect = try s.keep(try js.global(engine, "Reflect"));
        const value = try h.invoke(&s, reflect, "get", &.{ target, property, target });
        return if (c.JS_IsFunction(engine.context, value)) js.invoke(engine, value, "bind", &.{target}) else s.result(value);
    }
    if (has) {
        const string = try s.keep(try js.global(engine, "String"));
        const name = try s.keep(try js.call(engine, string, c.pi_js_undefined(), &.{property}));
        const value = try h.invoke(&s, target, "member", &.{name});
        return c.pi_js_bool(engine.context, @intFromBool(!c.JS_IsUndefined(value)));
    }
    if (!c.JS_IsString(property) or try s.equal(property, "then")) return c.pi_js_undefined();
    return js.invoke(engine, target, "member", &.{property});
}
fn construct(engine: *h.Engine, target: c.JSValue, args: []const c.JSValue, values: []const c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    const bindings = values[0];
    const result = try s.keep(try h.allocate(engine, target, bindings, .RefImpl));
    const owned = try h.actor(&s, result, bindings, .RefImpl);
    inline for (.{ "object", "contract", "owner", "address", "proxy", "ready", "status", "error" }) |name| try h.field(&s, result, name, c.pi_js_undefined());
    inline for (.{ "shapeListeners", "goneListeners" }) |name| try h.field(&s, result, name, try h.set(&s));
    try h.field(&s, result, "readables", try h.map(&s));
    inline for (.{ "bindings", "views" }) |name| try h.field(&s, result, name, try s.keep(try js.builtin(engine, "WeakMap", &.{})));
    try h.field(&s, result, "callers", try h.map(&s));
    try h.field(&s, owned.data, "statusListeners", try h.set(&s));
    try h.field(&s, result, "object", h.arg(args, 0));
    try h.field(&s, result, "contract", h.arg(args, 1));
    try h.field(&s, result, "owner", h.arg(args, 2));
    try h.field(&s, result, "address", try s.get(h.arg(args, 0), "address"));
    try h.field(&s, result, "status", try s.text(if (try s.equal(try s.get(h.arg(args, 0), "status"), "live")) "live" else "loading"));
    var captures = [_]c.JSValue{ result, bindings };
    const fulfilled = try s.keep(try engine.checked(c.JS_NewCFunctionData2(engine.context, ready, "", 0, 0, 2, &captures)));
    const pending = try h.invoke(&s, try s.get(h.arg(args, 0), "ready"), "then", &.{fulfilled});
    try h.field(&s, result, "ready", pending);
    const nothing = try s.keep(try engine.checked(c.JS_NewCFunctionData2(engine.context, noop, "noop", 0, 0, 0, null)));
    _ = try h.invoke(&s, pending, "catch", &.{nothing});
    const handler = try s.record();
    inline for (.{ "get", "has" }, 0..) |name, operation| {
        var captured = [_]c.JSValue{bindings};
        try js.define(engine, handler, name, try engine.checked(c.JS_NewCFunctionData2(engine.context, proxy, name, 2, @intCast(operation), 1, &captured)));
    }
    const wrapped = try s.keep(try js.builtin(engine, "Proxy", &.{ result, handler }));
    try h.field(&s, result, "proxy", wrapped);
    _ = try h.invoke(&s, try s.get(bindings, "refsByProxy"), "set", &.{ wrapped, result });
    return s.result(result);
}
pub fn install(engine: *h.Engine, bindings: c.JSValue) !void {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    const base_names = try s.list();
    inline for (.{ "contract", "status", "ready", "variant", "shape", "error", "onShape", "onStatus", "release" }) |name| try js.push(engine, base_names, try s.text(name));
    try h.field(&s, bindings, "refBase", try s.keep(try js.builtin(engine, "Set", &.{base_names})));
    try h.register(&s, bindings, .RefImpl);
    const prototype = try s.record();
    try js.define(engine, bindings, "RefImpl", try @import("native_class.zig").constructor(engine, "RefImpl", 3, prototype, construct, &.{bindings}));
    inline for (.{ .{ "variant", Method.variant, 0, true }, .{ "shape", Method.shape, 0, true }, .{ "onShape", Method.onShape, 1, false }, .{ "onStatus", Method.onStatus, 1, false }, .{ "release", Method.release, 0, false }, .{ "live", Method.live, 0, false }, .{ "gone", Method.gone, 1, false }, .{ "shapeChanged", Method.shapeChanged, 0, false }, .{ "terminalError", Method.terminalError, 0, false }, .{ "viewOf", Method.viewOf, 1, false }, .{ "currentView", Method.currentView, 0, false }, .{ "describe", Method.describe, 2, false }, .{ "inVariant", Method.inVariant, 2, false }, .{ "member", Method.member, 1, false }, .{ "caller", Method.caller, 1, false } }) |item| try h.define(&s, prototype, bindings, item[0], callback, @intFromEnum(item[1]), item[2], item[3], false);
}
