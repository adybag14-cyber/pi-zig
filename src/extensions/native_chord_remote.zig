//! Actual remote hold lifecycle, late-bound member callers and reconnect state.
const h = @import("native_chord_host_values.zig");
const Scope = h.Scope;
const js = h.js;
const c = h.c;
const Method = enum(c_int) { kind, on_shape, on_status, release, bound, shaped, gone, detached, member };
fn callback(ctx: ?*c.JSContext, receiver: c.JSValue, argc: c_int, argv: [*c]c.JSValue, magic: c_int, captures: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = h.Engine.fromContext(ctx.?);
    engine.native_exception_diagnostics_suppressed += 1;
    defer engine.native_exception_diagnostics_suppressed -= 1;
    return invoke(engine, receiver, if (argc > 0) argv[0..@intCast(argc)] else &.{}, @enumFromInt(magic), captures[0]) catch |err| @import("native_durable.zig").reject(engine, err);
}
fn noop(_: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue, _: c_int, _: [*c]c.JSValue) callconv(.c) c.JSValue {
    return c.pi_js_undefined();
}
fn promise(s: *Scope) !c.JSValue {
    var capability: [2]c.JSValue = undefined;
    const value = try s.engine.checked(c.JS_NewPromiseCapability(s.engine.context, &capability));
    var value_transferred = false;
    var resolve_transferred = false;
    var reject_transferred = false;
    defer if (!value_transferred) s.engine.freeValue(value);
    defer if (!resolve_transferred) s.engine.freeValue(capability[0]);
    defer if (!reject_transferred) s.engine.freeValue(capability[1]);
    value_transferred = true;
    _ = try s.keep(value);
    resolve_transferred = true;
    _ = try s.keep(capability[0]);
    reject_transferred = true;
    _ = try s.keep(capability[1]);
    const result = try s.record();
    try h.field(s, result, "promise", value);
    try h.field(s, result, "resolve", capability[0]);
    try h.field(s, result, "reject", capability[1]);
    const ignored = try s.keep(try s.engine.checked(c.JS_NewCFunctionData2(s.engine.context, noop, "noop", 0, 0, 0, null)));
    _ = try h.invoke(s, value, "catch", &.{ignored});
    return result;
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
    const data = (try h.actor(s, receiver, bindings, .RemoteHandle)).data;
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
            _ = try h.invoke(&s, try s.get(captures[3], "host"), "report", &.{engine.captured_exception orelse return err});
            continue;
        };
        engine.freeValue(result);
    }
    return c.pi_js_undefined();
}
fn terminal(s: *Scope, receiver: c.JSValue) !bool {
    const status = try s.get(receiver, "status");
    return try s.equal(status, "released") or try s.equal(status, "gone");
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
fn settle(s: *Scope, data: c.JSValue, method: [*:0]const u8, value: c.JSValue) !void {
    const ready = try s.get(data, "settleReady");
    if (!h.nullish(ready)) _ = try h.invoke(s, ready, method, &.{value});
}
fn invoke(engine: *h.Engine, receiver: c.JSValue, args: []const c.JSValue, method: Method, bindings: c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    if (method == .kind) {
        const shape = try s.get(receiver, "shape");
        return if (h.nullish(shape)) c.pi_js_undefined() else js.get(engine, shape, "kind");
    }
    if (method == .on_shape) return subscribe(&s, try s.get(receiver, "shapeListeners"), h.arg(args, 0));
    if (method == .bound) {
        const binding = try s.record();
        try h.field(&s, binding, "channel", h.arg(args, 0));
        try h.field(&s, binding, "id", h.arg(args, 1));
        try js.setKey(engine, receiver, try s.text("binding"), binding);
        return c.pi_js_undefined();
    }
    if (method == .on_status) return subscribe(&s, try s.get((try h.actor(&s, receiver, bindings, .RemoteHandle)).data, "statusListeners"), h.arg(args, 0));
    if (method == .member) return member(&s, receiver, bindings, h.arg(args, 0));
    if (try terminal(&s, receiver)) return c.pi_js_undefined();
    if (method == .release) {
        try js.setKey(engine, receiver, try s.text("status"), try s.text("released"));
        try statusChanged(&s, receiver, bindings);
        const data = (try h.actor(&s, receiver, bindings, .RemoteHandle)).data;
        const failure = try h.errorValue(&s, bindings, "released", &.{ try s.text("handle "), try s.get(receiver, "address"), try s.text(" released") }, c.pi_js_undefined());
        try settle(&s, data, "reject", failure);
        _ = try h.invoke(&s, try s.get(data, "live"), "reject", &.{failure});
        try readables(&s, data, "stop");
        const binding = try s.get(receiver, "binding");
        if (!c.JS_IsUndefined(binding)) _ = try h.invoke(&s, try s.get(binding, "channel"), "release", &.{try s.get(binding, "id")});
        try js.setKey(engine, receiver, try s.text("binding"), c.pi_js_undefined());
        _ = try h.invoke(&s, try s.get(receiver, "host"), "forgetRemote", &.{receiver});
    } else if (method == .shaped) {
        try js.setKey(engine, receiver, try s.text("shape"), h.arg(args, 0));
        const loading = try s.equal(try s.get(receiver, "status"), "loading");
        try js.setKey(engine, receiver, try s.text("status"), try s.text("live"));
        const data = (try h.actor(&s, receiver, bindings, .RemoteHandle)).data;
        if (loading) {
            try statusChanged(&s, receiver, bindings);
            try settle(&s, data, "resolve", c.pi_js_undefined());
            try h.field(&s, data, "settleReady", c.pi_js_undefined());
            _ = try h.invoke(&s, try s.get(data, "live"), "resolve", &.{});
        }
        try readables(&s, data, "bind");
        const listeners = try h.snapshot(&s, try s.get(receiver, "shapeListeners"));
        for (0..try h.length(&s, listeners)) |index| {
            const result = js.call(engine, try s.at(listeners, index), c.pi_js_undefined(), &.{h.arg(args, 0)}) catch |err| {
                if (err != error.JavaScriptException) return err;
                _ = try h.invoke(&s, try s.get(receiver, "host"), "report", &.{engine.captured_exception orelse return err});
                continue;
            };
            engine.freeValue(result);
        }
    } else if (method == .gone) {
        try js.setKey(engine, receiver, try s.text("status"), try s.text("gone"));
        try js.setKey(engine, receiver, try s.text("error"), h.arg(args, 0));
        try statusChanged(&s, receiver, bindings);
        try js.setKey(engine, receiver, try s.text("binding"), c.pi_js_undefined());
        const data = (try h.actor(&s, receiver, bindings, .RemoteHandle)).data;
        try settle(&s, data, "reject", h.arg(args, 0));
        _ = try h.invoke(&s, try s.get(data, "live"), "reject", &.{h.arg(args, 0)});
        try readables(&s, data, "stop");
        _ = try h.invoke(&s, try s.get(receiver, "host"), "forgetRemote", &.{receiver});
    } else {
        try js.setKey(engine, receiver, try s.text("binding"), c.pi_js_undefined());
        const data = (try h.actor(&s, receiver, bindings, .RemoteHandle)).data;
        try readables(&s, data, "detach");
        if (try s.equal(try s.get(receiver, "status"), "live")) {
            try js.setKey(engine, receiver, try s.text("status"), try s.text("loading"));
            try h.field(&s, data, "live", try promise(&s));
            try statusChanged(&s, receiver, bindings);
        }
    }
    return c.pi_js_undefined();
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
        const data = (try h.actor(s, receiver, bindings, .RemoteHandle)).data;
        const callers = try s.get(data, "callers");
        var function = try h.invoke(s, callers, "get", &.{name});
        if (c.JS_IsUndefined(function)) {
            var caller_captures = [_]c.JSValue{ receiver, bindings, name };
            function = try s.keep(try s.engine.checked(c.JS_NewCFunctionData2(s.engine.context, caller, "caller", 2, 0, 3, &caller_captures)));
            _ = try h.invoke(s, callers, "set", &.{ name, function });
        }
        return s.result(function);
    }
    if (try s.equal(if (h.nullish(description)) c.pi_js_undefined() else try s.get(description, "kind"), "state")) {
        const data = (try h.actor(s, receiver, bindings, .RemoteHandle)).data;
        const values = try s.get(data, "readables");
        var value = try h.invoke(s, values, "get", &.{name});
        if (c.JS_IsUndefined(value)) {
            value = try h.construct(s, bindings, "RemoteReadable", &.{ receiver, name });
            _ = try h.invoke(s, values, "set", &.{ name, value });
        }
        return s.result(value);
    }
    return c.pi_js_undefined();
}
fn caller(ctx: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, captures: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = h.Engine.fromContext(ctx.?);
    engine.native_exception_diagnostics_suppressed += 1;
    defer engine.native_exception_diagnostics_suppressed -= 1;
    return call(engine, captures[0], captures[1], captures[2], if (argc > 0) argv[0] else c.pi_js_undefined(), if (argc > 1) argv[1] else c.pi_js_undefined()) catch |err| @import("native_durable.zig").reject(engine, err);
}
fn inRoot(ctx: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, captures: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = h.Engine.fromContext(ctx.?);
    return asyncCall(engine, captures[0], captures[1], captures[2], captures[3], if (argc > 0) argv[0] else c.pi_js_undefined()) catch |err| @import("native_durable.zig").rejectedPromise(engine, err);
}
fn call(engine: *h.Engine, receiver: c.JSValue, bindings: c.JSValue, name: c.JSValue, args: c.JSValue, ctx: c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    const host = try s.get(receiver, "host");
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
fn asyncCall(engine: *h.Engine, receiver: c.JSValue, bindings: c.JSValue, name: c.JSValue, args: c.JSValue, ctx: c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    const work = try s.record();
    try h.field(&s, work, "handle", receiver);
    try h.field(&s, work, "bindings", bindings);
    try h.field(&s, work, "name", name);
    try h.field(&s, work, "args", args);
    try h.field(&s, work, "ctx", ctx);
    const returned = callLoop(engine, work, c.pi_js_undefined(), false, 0) catch |err| return @import("native_durable.zig").rejectedPromise(engine, err);
    defer engine.freeValue(returned);
    return @import("native_durable.zig").resolvedPromise(engine, returned);
}
fn callDescription(s: *Scope, receiver: c.JSValue, kind: c.JSValue, name: c.JSValue) !c.JSValue {
    const variants = try s.get(try s.get(try s.get(receiver, "contract"), "description"), "variants");
    const variant = try s.key(variants, kind);
    return if (h.nullish(variant)) c.pi_js_undefined() else try s.key(variant, name);
}
fn callLoop(engine: *h.Engine, work: c.JSValue, value: c.JSValue, rejected: bool, stage: c_int) anyerror!c.JSValue {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    if (rejected) return h.throwValue(&s, value);
    const receiver = try s.get(work, "handle");
    const bindings = try s.get(work, "bindings");
    const data = (try h.actor(&s, receiver, bindings, .RemoteHandle)).data;
    const name = try s.get(work, "name");
    const ctx = try s.get(work, "ctx");
    var steps: usize = 0;
    var resumed = stage == 1;
    while (true) {
        steps +|= 1;
        if (engine.cancelled.load(.acquire) or (steps % 256 == 0 and blk: {
            engine.interrupts +|= 1;
            break :blk engine.interrupts > engine.options.interrupt_budget;
        })) _ = try engine.checked(c.JS_ThrowInternalError(engine.context, "interrupted"));
        if (!resumed) {
            if (try terminal(&s, receiver)) return h.throwValue(&s, if (try s.equal(try s.get(receiver, "status"), "gone")) try s.get(receiver, "error") else try h.errorValue(&s, bindings, "released", &.{ try s.text("handle "), try s.get(receiver, "address"), try s.text(" released") }, c.pi_js_undefined()));
            if (try s.equal(try s.get(receiver, "status"), "loading")) return h.wait(callLoop, engine, work, try s.keep(try @import("native_chord_host_record_call.zig").raceSignal(engine, bindings, try s.get(try s.get(data, "live"), "promise"), try s.get(ctx, "signal"))), 1);
        }
        resumed = false;
        const binding = try s.get(receiver, "binding");
        if (c.JS_IsUndefined(binding)) continue;
        const shape = try s.get(receiver, "shape");
        const kind = if (h.nullish(shape)) c.pi_js_undefined() else try s.get(shape, "kind");
        const valid = !c.JS_IsUndefined(kind) and valid: {
            const description = try callDescription(&s, receiver, kind, name);
            break :valid !h.nullish(description) and try s.equal(try s.get(description, "kind"), "method");
        };
        if (!valid) return h.throwValue(&s, try h.errorValue(&s, bindings, "not_in_variant", &.{ try s.get(receiver, "address"), try s.text(": "), name, try s.text(" is not a method of variant "), kind }, c.pi_js_undefined()));
        const description = try callDescription(&s, receiver, kind, name);
        const sent = if (!h.nullish(description) and try s.equal(try s.get(description, "kind"), "method")) try @import("native_chord_host_record_schema.zig").clean(&s, try s.get(description, "args"), try s.get(work, "args")) else try s.get(work, "args");
        const root = try s.record();
        try h.field(&s, root, "rootId", try s.get(ctx, "rootId"));
        try h.field(&s, root, "epoch", try s.get(ctx, "epoch"));
        return js.invoke(engine, try s.get(binding, "channel"), "call", &.{ try s.get(binding, "id"), name, sent, root, try s.get(ctx, "signal") });
    }
}
fn proxy(ctx: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, captures: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = h.Engine.fromContext(ctx.?);
    return @import("native_chord_host_handle.zig").proxyValue(engine, if (argc > 0) argv[0] else c.pi_js_undefined(), if (argc > 1) argv[1] else c.pi_js_undefined(), false, captures[0]) catch |err| @import("native_durable.zig").reject(engine, err);
}
fn construct(engine: *h.Engine, target: c.JSValue, args: []const c.JSValue, captures: []const c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    const bindings = captures[0];
    const result = try s.keep(try h.allocate(engine, target, bindings, .RemoteHandle));
    const data = (try h.actor(&s, result, bindings, .RemoteHandle)).data;
    inline for (.{ "record", "host", "contract", "at", "input", "principal", "owner", "address", "proxy", "ready", "status", "error", "shape", "binding" }) |name| try h.field(&s, result, name, c.pi_js_undefined());
    try h.field(&s, result, "status", try s.text("loading"));
    try h.field(&s, result, "shapeListeners", try h.set(&s));
    inline for (.{ "readables", "callers" }) |name| try h.field(&s, data, name, try h.map(&s));
    try h.field(&s, data, "statusListeners", try h.set(&s));
    try h.field(&s, result, "host", h.arg(args, 0));
    inline for (.{ "contract", "at", "input", "principal", "owner", "address" }) |name| try h.field(&s, result, name, try s.get(h.arg(args, 1), name));
    const ready = try promise(&s);
    try h.field(&s, data, "settleReady", ready);
    try h.field(&s, result, "ready", try s.get(ready, "promise"));
    try h.field(&s, data, "live", try promise(&s));
    const handler = try s.record();
    var values = [_]c.JSValue{bindings};
    try js.define(engine, handler, "get", try engine.checked(c.JS_NewCFunctionData2(engine.context, proxy, "get", 2, 0, 1, &values)));
    const wrapped = try s.keep(try js.builtin(engine, "Proxy", &.{ result, handler }));
    try h.field(&s, result, "proxy", wrapped);
    _ = try h.invoke(&s, try s.get(bindings, "holdsByProxy"), "set", &.{ wrapped, result });
    return s.result(result);
}
pub fn install(engine: *h.Engine, bindings: c.JSValue) !void {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    try h.register(&s, bindings, .RemoteHandle);
    const prototype = try s.record();
    try js.define(engine, bindings, "RemoteHandle", try @import("native_class.zig").constructor(engine, "RemoteHandle", 2, prototype, construct, &.{bindings}));
    inline for (.{ .{ "kind", Method.kind, 0, true }, .{ "onShape", Method.on_shape, 1, false }, .{ "onStatus", Method.on_status, 1, false }, .{ "release", Method.release, 0, false }, .{ "bound", Method.bound, 2, false }, .{ "shaped", Method.shaped, 1, false }, .{ "gone", Method.gone, 1, false }, .{ "detached", Method.detached, 0, false }, .{ "member", Method.member, 1, false } }) |entry| try h.define(&s, prototype, bindings, entry[0], callback, @intFromEnum(entry[1]), entry[2], entry[3], false);
    try @import("native_chord_remote_readable.zig").install(engine, bindings);
}
