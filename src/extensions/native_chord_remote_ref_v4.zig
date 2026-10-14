//! Actual b45 per-owner remote views over one shared RemoteBinding.
const h = @import("native_chord_host_values.zig");
const Scope = h.Scope;
const js = h.js;
const c = h.c;
const binding_api = @import("native_chord_remote_binding_v4.zig");
const Method = enum(c_int) { contract, address, ended, variant, shape, on_shape, on_status, terminal_error, release, update, end, shape_changed, member };
fn callback(ctx: ?*c.JSContext, receiver: c.JSValue, argc: c_int, argv: [*c]c.JSValue, magic: c_int, captures: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = h.Engine.fromContext(ctx.?);
    return invoke(engine, receiver, if (argc > 0) argv[0..@intCast(argc)] else &.{}, @enumFromInt(magic), captures[0]) catch |err| @import("native_durable.zig").reject(engine, err);
}
fn ended(s: *Scope, receiver: c.JSValue) !bool {
    const status = try s.get(receiver, "status");
    return try s.equal(status, "released") or try s.equal(status, "gone");
}
fn terminalError(s: *Scope, receiver: c.JSValue, bindings: c.JSValue) !c.JSValue {
    return if (try s.equal(try s.get(receiver, "status"), "gone")) s.get(receiver, "error") else h.errorValue(s, bindings, "released", &.{ try s.text("reference "), try s.get(receiver, "address"), try s.text(" released") }, c.pi_js_undefined());
}
fn settleReady(s: *Scope, owned: c.JSValue, value: c.JSValue, rejected: bool) !void {
    const ready = try s.get(owned, "settleReady");
    if (!h.nullish(ready)) try binding_api.settle(s, ready, value, rejected);
    try h.field(s, owned, "settleReady", c.pi_js_undefined());
}
fn invoke(engine: *h.Engine, receiver: c.JSValue, args: []const c.JSValue, method: Method, bindings: c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    const binding = try s.get(receiver, "binding");
    const owned = (try h.actor(&s, receiver, bindings, .RemoteRef)).data;
    switch (method) {
        .contract => return js.get(engine, binding, "contract"),
        .address => return js.get(engine, binding, "key"),
        .shape => return js.get(engine, binding, "shape"),
        .variant => {
            const shape = try s.get(binding, "shape");
            return if (h.nullish(shape)) c.pi_js_undefined() else js.get(engine, shape, "variant");
        },
        .ended => return c.pi_js_bool(engine.context, @intFromBool(try ended(&s, receiver))),
        .terminal_error => return s.result(try terminalError(&s, receiver, bindings)),
        .on_shape => return subscribe(&s, try s.get(receiver, "shapeListeners"), h.arg(args, 0)),
        .on_status => return subscribe(&s, try s.get(owned, "statusListeners"), h.arg(args, 0)),
        .member => return member(&s, receiver, bindings, h.arg(args, 0)),
        .release => {
            if (try ended(&s, receiver)) return c.pi_js_undefined();
            try h.field(&s, receiver, "status", try s.text("released"));
            try statusChanged(&s, receiver, bindings);
            try settleReady(&s, owned, try terminalError(&s, receiver, bindings), true);
            try readables(&s, owned, "stop");
            _ = try h.invoke(&s, binding, "removeView", &.{receiver});
        },
        .update => {
            if (try ended(&s, receiver)) return c.pi_js_undefined();
            const live = try s.equal(try s.get(binding, "status"), "live") and !c.JS_IsUndefined(try s.get(binding, "hold")) and (!try h.flag(&s, receiver, "wantsState") or try h.flag(&s, binding, "hydrated"));
            const next = try s.text(if (live) "live" else "loading");
            if (c.JS_IsStrictEqual(engine.context, next, try s.get(receiver, "status"))) return c.pi_js_undefined();
            try h.field(&s, receiver, "status", next);
            try statusChanged(&s, receiver, bindings);
            if (live) try settleReady(&s, owned, c.pi_js_undefined(), false);
        },
        .end => {
            if (try ended(&s, receiver)) return c.pi_js_undefined();
            const failure = h.arg(args, 0);
            const chord = c.JS_IsInstanceOf(engine.context, failure, try s.get(try s.get(bindings, "errors"), "ChordError"));
            if (chord < 0) return js.capture(engine);
            const released = chord != 0 and try s.equal(try s.get(failure, "code"), "released");
            try h.field(&s, receiver, "status", try s.text(if (released) "released" else "gone"));
            if (!released) try h.field(&s, receiver, "error", failure);
            try statusChanged(&s, receiver, bindings);
            try settleReady(&s, owned, failure, true);
            try readables(&s, owned, "stop");
        },
        .shape_changed => {
            const shape = try s.get(binding, "shape");
            if (c.JS_IsUndefined(shape) or try ended(&s, receiver)) return c.pi_js_undefined();
            const listeners = try h.snapshot(&s, try s.get(receiver, "shapeListeners"));
            for (0..try h.length(&s, listeners)) |index| {
                const result = js.call(engine, try s.at(listeners, index), c.pi_js_undefined(), &.{shape}) catch |err| {
                    if (err != error.JavaScriptException) return err;
                    _ = try h.invoke(&s, try s.get(binding, "host"), "report", &.{engine.captured_exception orelse return err});
                    continue;
                };
                engine.freeValue(result);
            }
        },
    }
    return c.pi_js_undefined();
}
fn asyncCall(engine: *h.Engine, receiver: c.JSValue, bindings: c.JSValue, name: c.JSValue, args: c.JSValue, ctx: c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    if (try ended(&s, receiver)) return js.invoke(engine, try s.keep(try js.global(engine, "Promise")), "reject", &.{try terminalError(&s, receiver, bindings)});
    return js.invoke(engine, try s.get(receiver, "binding"), "call", &.{ name, args, ctx });
}
fn construct(engine: *h.Engine, target: c.JSValue, args: []const c.JSValue, captures: []const c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    const bindings = captures[0];
    const result = try s.keep(try h.allocate(engine, target, bindings, .RemoteRef));
    const owned = (try h.actor(&s, result, bindings, .RemoteRef)).data;
    try h.field(&s, result, "object", c.pi_js_undefined());
    try h.field(&s, result, "binding", h.arg(args, 0));
    try h.field(&s, result, "owner", h.arg(args, 1));
    try h.field(&s, result, "wantsState", h.arg(args, 2));
    try h.field(&s, result, "status", try s.text("loading"));
    try h.field(&s, result, "error", c.pi_js_undefined());
    try h.field(&s, result, "shapeListeners", try h.set(&s));
    inline for (.{ "readables", "callers" }) |field| try h.field(&s, owned, field, try h.map(&s));
    try h.field(&s, owned, "statusListeners", try h.set(&s));
    const ready = try binding_api.deferred(&s);
    try h.field(&s, owned, "settleReady", ready);
    try h.field(&s, result, "ready", try s.get(ready, "promise"));
    const handler = try s.record();
    var values = [_]c.JSValue{bindings};
    try js.define(engine, handler, "get", try engine.checked(c.JS_NewCFunctionData2(engine.context, proxy, "get", 2, 0, 1, &values)));
    const wrapped = try s.keep(try js.builtin(engine, "Proxy", &.{ result, handler }));
    try h.field(&s, result, "proxy", wrapped);
    _ = try h.invoke(&s, try s.get(bindings, "refsByProxy"), "set", &.{ wrapped, result });
    return s.result(result);
}
pub fn install(engine: *h.Engine, bindings: c.JSValue) !void {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    try h.register(&s, bindings, .RemoteRef);
    const prototype = try s.record();
    try js.define(engine, bindings, "RemoteRef", try @import("native_class.zig").constructor(engine, "RemoteRef", 3, prototype, construct, &.{bindings}));
    inline for (.{ .{ "contract", Method.contract, 0, true }, .{ "address", Method.address, 0, true }, .{ "ended", Method.ended, 0, true }, .{ "variant", Method.variant, 0, true }, .{ "shape", Method.shape, 0, true }, .{ "onShape", Method.on_shape, 1, false }, .{ "onStatus", Method.on_status, 1, false }, .{ "terminalError", Method.terminal_error, 0, false }, .{ "release", Method.release, 0, false }, .{ "update", Method.update, 0, false }, .{ "end", Method.end, 1, false }, .{ "shapeChanged", Method.shape_changed, 0, false }, .{ "member", Method.member, 1, false } }) |item| try h.define(&s, prototype, bindings, item[0], callback, @intFromEnum(item[1]), item[2], item[3], false);
    try @import("native_chord_view_readable_v4.zig").install(engine, bindings);
}
fn unsubscribe(ctx: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue, _: c_int, captures: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = h.Engine.fromContext(ctx.?);
    return js.invoke(engine, captures[0], "delete", &.{captures[1]}) catch |err| @import("native_durable.zig").reject(engine, err);
}
fn subscribe(s: *Scope, set: c.JSValue, listener: c.JSValue) !c.JSValue {
    _ = try h.invoke(s, set, "add", &.{listener});
    var captures = [_]c.JSValue{ set, listener };
    return s.engine.checked(c.JS_NewCFunctionData2(s.engine.context, unsubscribe, "", 0, 0, 2, &captures));
}
fn statusChanged(s: *Scope, receiver: c.JSValue, bindings: c.JSValue) !void {
    const data = (try h.actor(s, receiver, bindings, .RemoteRef)).data;
    const listeners = try s.get(data, "statusListeners");
    const status = try s.get(receiver, "status");
    const failure = try s.get(receiver, "error");
    if (!try h.flag(s, listeners, "size")) return;
    var captures = [_]c.JSValue{ try h.snapshot(s, listeners), status, failure, receiver };
    const task = try s.keep(try s.engine.checked(c.JS_NewCFunctionData2(s.engine.context, statusNotification, "", 0, 0, 4, &captures)));
    try @import("native_chord_publish.zig").enqueue(s.engine, bindings, task);
}
fn statusNotification(ctx: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue, _: c_int, captures: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = h.Engine.fromContext(ctx.?);
    engine.native_exception_diagnostics_suppressed += 1;
    defer engine.native_exception_diagnostics_suppressed -= 1;
    return notifyStatus(engine, captures) catch |err| @import("native_durable.zig").reject(engine, err);
}
fn notifyStatus(engine: *h.Engine, captures: [*c]c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    for (0..try h.length(&s, captures[0])) |index| {
        const result = js.call(engine, try s.at(captures[0], index), c.pi_js_undefined(), &.{ captures[1], captures[2] }) catch |err| {
            if (err != error.JavaScriptException) return err;
            _ = try h.invoke(&s, try s.get(try s.get(captures[3], "binding"), "host"), "report", &.{engine.captured_exception orelse return err});
            continue;
        };
        engine.freeValue(result);
    }
    return c.pi_js_undefined();
}

fn readables(s: *Scope, data: c.JSValue, method: [*:0]const u8) !void {
    const values = try h.invoke(s, try s.get(data, "readables"), "values", &.{});
    var iterator = try js.Iterator.init(s.engine, values, try h.iteratorSymbol(s));
    defer iterator.deinit();
    errdefer iterator.closePreserving();
    while (try iterator.next()) |readable| {
        defer s.engine.freeValue(readable);
        _ = try h.invoke(s, readable, method, &.{});
    }
}

fn selectDescription(ctx: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, magic: c_int, captures: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = h.Engine.fromContext(ctx.?);
    const value = if (argc > 0) argv[0] else c.pi_js_undefined();
    if (magic == 1) return c.pi_js_bool(engine.context, @intFromBool(!c.JS_IsUndefined(value)));
    return js.getKey(engine, value, captures[0]) catch |err| @import("native_durable.zig").reject(engine, err);
}
fn member(s: *Scope, receiver: c.JSValue, bindings: c.JSValue, name: c.JSValue) !c.JSValue {
    const variants = try s.builtin("Object", "values", &.{try s.get(try s.get(try s.get(receiver, "contract"), "description"), "variants")});
    var captures = [_]c.JSValue{name};
    const selector = try s.keep(try s.engine.checked(c.JS_NewCFunctionData2(s.engine.context, selectDescription, "", 1, 0, 1, &captures)));
    const described = try h.invoke(s, variants, "map", &.{selector});
    const present = try s.keep(try s.engine.checked(c.JS_NewCFunctionData2(s.engine.context, selectDescription, "", 1, 1, 0, null)));
    const description = try h.invoke(s, described, "find", &.{present});
    const kind = if (h.nullish(description)) c.pi_js_undefined() else try s.get(description, "kind");
    if (try s.equal(kind, "method")) {
        const data = (try h.actor(s, receiver, bindings, .RemoteRef)).data;
        const callers = try s.get(data, "callers");
        var function = try h.invoke(s, callers, "get", &.{name});
        if (c.JS_IsUndefined(function)) {
            var caller_captures = [_]c.JSValue{ receiver, bindings, name };
            const no_args = try @import("native_chord_object_ref.zig").takesNoArgs(s, try s.get(receiver, "contract"), name);
            function = try s.keep(try s.engine.checked(c.JS_NewCFunctionData2(s.engine.context, caller, "caller", 0, @intFromBool(no_args), 3, &caller_captures)));
            _ = try h.invoke(s, callers, "set", &.{ name, function });
        }
        return s.result(function);
    }
    if (try s.equal(if (h.nullish(description)) c.pi_js_undefined() else try s.get(description, "kind"), "state")) {
        const data = (try h.actor(s, receiver, bindings, .RemoteRef)).data;
        const values = try s.get(data, "readables");
        var value = try h.invoke(s, values, "get", &.{name});
        if (c.JS_IsUndefined(value)) {
            value = try h.construct(s, bindings, "ViewReadable", &.{ receiver, name });
            _ = try h.invoke(s, values, "set", &.{ name, value });
        }
        return s.result(value);
    }
    return c.pi_js_undefined();
}
fn caller(ctx: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, no_args: c_int, captures: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = h.Engine.fromContext(ctx.?);
    engine.native_exception_diagnostics_suppressed += 1;
    defer engine.native_exception_diagnostics_suppressed -= 1;
    return call(engine, captures[0], captures[1], captures[2], if (no_args == 0 and argc > 0) argv[0] else c.pi_js_undefined(), if (no_args != 0 and argc > 0) argv[0] else if (argc > 1) argv[1] else c.pi_js_undefined()) catch |err| @import("native_durable.zig").reject(engine, err);
}
fn inRoot(ctx: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, captures: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = h.Engine.fromContext(ctx.?);
    return asyncCall(engine, captures[0], captures[1], captures[2], captures[3], if (argc > 0) argv[0] else c.pi_js_undefined()) catch |err| @import("native_durable.zig").rejectedPromise(engine, err);
}
fn call(engine: *h.Engine, receiver: c.JSValue, bindings: c.JSValue, name: c.JSValue, args: c.JSValue, ctx: c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    const host = try s.get(try s.get(receiver, "binding"), "host");
    var depth: f64 = 0;
    if (c.JS_ToFloat64(engine.context, &depth, try s.get(host, "inFactory")) < 0) return js.capture(engine);
    if (depth > 0) return h.throwValue(&s, try h.errorValue(&s, bindings, "not_ready", &.{ try s.get(receiver, "address"), try s.text("."), name, try s.text(" called inside a factory") }, c.pi_js_undefined()));
    const native_ctx = c.JS_IsInstanceOf(engine.context, ctx, try s.get(bindings, "CtxImpl"));
    if (native_ctx < 0) return js.capture(engine);
    if (native_ctx != 0) {
        _ = h.invoke(&s, ctx, "check", &.{try s.get(ctx, "host")}) catch |err| return @import("native_durable.zig").rejectedPromise(engine, err);
    }
    if (c.JS_IsUndefined(ctx) or (native_ctx != 0 and try h.flag(&s, ctx, "holder"))) {
        const options = try s.record();
        try h.field(&s, options, "signal", if (h.nullish(ctx)) c.pi_js_undefined() else try s.get(ctx, "signal"));
        var captures = [_]c.JSValue{ receiver, bindings, name, args };
        const function = try s.keep(try engine.checked(c.JS_NewCFunctionData2(engine.context, inRoot, "", 1, 0, 4, &captures)));
        return js.invoke(engine, host, "root", &.{ function, options });
    }
    return asyncCall(engine, receiver, bindings, name, args, ctx);
}

fn proxy(ctx: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, captures: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = h.Engine.fromContext(ctx.?);
    return @import("native_chord_object_ref.zig").proxyValue(engine, if (argc > 0) argv[0] else c.pi_js_undefined(), if (argc > 1) argv[1] else c.pi_js_undefined(), false, captures[0]) catch |err| @import("native_durable.zig").reject(engine, err);
}
