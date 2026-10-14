//! Actual stable late-bound Handle state member readable and publication rebinds.
const h = @import("native_chord_host_values.zig");
const Scope = h.Scope;
const js = h.js;
const c = h.c;
const cells = @import("native_chord_cells_v4.zig");
const aw = @import("native_chord_async_work.zig");
const Method = enum(c_int) { value, hydration, subscribe, events, bind, stop };
fn callback(context: ?*c.JSContext, receiver: c.JSValue, argc: c_int, argv: [*c]c.JSValue, operation: c_int, data: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = h.Engine.fromContext(context.?);
    return invoke(engine, receiver, if (argc > 0) argv[0..@intCast(argc)] else &.{}, @enumFromInt(operation), data[0]) catch |err| @import("native_durable.zig").reject(engine, err);
}
fn host(s: *Scope, data: c.JSValue) !c.JSValue {
    return s.get(try s.get(try s.get(data, "handle"), "object"), "host");
}
fn safe(s: *Scope, data: c.JSValue, listener: c.JSValue, value: c.JSValue) !void {
    const result = js.call(s.engine, listener, c.pi_js_undefined(), &.{value}) catch |err| {
        if (err != error.JavaScriptException) return err;
        _ = try h.invoke(s, try host(s, data), "report", &.{s.engine.captured_exception orelse return err});
        return;
    };
    s.engine.freeValue(result);
}
fn current(s: *Scope, data: c.JSValue, bindings: c.JSValue) !c.JSValue {
    const handle = try s.get(data, "handle");
    const name = try s.get(data, "name");
    const view = try h.invoke(s, handle, "currentView", &.{});
    if (c.JS_IsUndefined(view) or c.JS_ToBool(s.engine.context, try h.invoke(s, handle, "inVariant", &.{ view, name })) == 0) return c.pi_js_undefined();
    const value = try s.key(view, name);
    return if (try @import("native_chord_object_schema.zig").source(s, bindings, value) or try @import("native_chord_object_schema.zig").readable(s, value)) value else c.pi_js_undefined();
}
fn unlisten(context: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue, _: c_int, data: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = h.Engine.fromContext(context.?);
    return remove(engine, data) catch |err| @import("native_durable.zig").reject(engine, err);
}
fn remove(engine: *h.Engine, data: [*c]c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    if (c.JS_ToBool(engine.context, data[4]) != 0) {
        const owned = (try h.actor(&s, data[0], data[1], .MemberReadable)).data;
        _ = try h.invoke(&s, try s.get(owned, "unseen"), "delete", &.{data[3]});
    }
    _ = try h.invoke(&s, data[2], "delete", &.{data[3]});
    _ = try h.invoke(&s, data[0], "bind", &.{});
    return c.pi_js_undefined();
}
fn upstream(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, data: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = h.Engine.fromContext(context.?);
    return receive(engine, data[0], data[1], data[2], if (argc > 0) argv[0] else c.pi_js_undefined()) catch |err| @import("native_durable.zig").reject(engine, err);
}
fn receive(engine: *h.Engine, receiver: c.JSValue, bindings: c.JSValue, first: c.JSValue, event: c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    const data = (try h.actor(&s, receiver, bindings, .MemberReadable)).data;
    const is_first = try h.flag(&s, first, "value");
    try h.field(&s, first, "value", c.pi_js_bool(engine.context, 0));
    const value = try s.get(event, "value");
    const seen = try s.get(data, "seen");
    if (is_first and !try @import("native_chord_object.zig").nonempty(&s, try s.get(data, "unseen")) and !c.JS_IsUndefined(seen) and c.JS_IsStrictEqual(engine.context, value, try s.get(seen, "value"))) return c.pi_js_undefined();
    const box = try s.record();
    try h.field(&s, box, "value", value);
    try h.field(&s, data, "seen", box);
    const translated = if (!is_first) event else blk: {
        const reset = try s.record();
        try h.field(&s, reset, "type", try s.text("reset"));
        try h.field(&s, reset, "value", value);
        break :blk reset;
    };
    const unseen = try s.keep(try js.builtin(engine, "Set", &.{try s.get(data, "unseen")}));
    _ = try h.invoke(&s, try s.get(data, "unseen"), "clear", &.{});
    var captures = [_]c.JSValue{ receiver, bindings, try h.snapshot(&s, try s.get(data, "events")), try h.snapshot(&s, try s.get(data, "values")), translated, value, unseen };
    const task = try s.keep(try engine.checked(c.JS_NewCFunctionData2(engine.context, publish, "", 0, 0, 7, &captures)));
    try @import("native_chord_publish.zig").enqueue(engine, bindings, task);
    return c.pi_js_undefined();
}
fn publish(context: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue, _: c_int, data: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = h.Engine.fromContext(context.?);
    return published(engine, data) catch |err| @import("native_durable.zig").reject(engine, err);
}
fn published(engine: *h.Engine, captures: [*c]c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    const data = (try h.actor(&s, captures[0], captures[1], .MemberReadable)).data;
    inline for (.{ "events", "values" }, 0..) |name, index| {
        const set = try s.get(data, name);
        const listeners = captures[index + 2];
        for (0..try h.length(&s, listeners)) |slot| {
            const listener = try s.at(listeners, slot);
            if (c.JS_ToBool(engine.context, try h.invoke(&s, set, "has", &.{listener})) != 0) {
                const delivered = if (index == 0 and c.JS_ToBool(engine.context, try h.invoke(&s, captures[6], "has", &.{listener})) != 0) blk: {
                    const event = try s.record();
                    try h.field(&s, event, "type", try s.text("snap"));
                    try h.field(&s, event, "value", captures[5]);
                    break :blk event;
                } else captures[index + 4];
                try safe(&s, data, listener, delivered);
            }
        }
    }
    return c.pi_js_undefined();
}
fn notReady(s: *Scope, data: c.JSValue, bindings: c.JSValue) !c.JSValue {
    const label = try s.keep(try @import("native_utf16.zig").concat(s.engine, &.{ try s.get(try s.get(data, "handle"), "address"), try s.text("."), try s.get(data, "name") }));
    return h.throwValue(s, try h.invoke(s, bindings, "notReady", &.{label}));
}
fn readable(s: *Scope, data: c.JSValue, bindings: c.JSValue) !c.JSValue {
    const source = try current(s, data, bindings);
    if (c.JS_IsUndefined(source)) return source;
    const hydration = try cells.hydrationOf(s, bindings, source);
    if (!h.nullish(hydration) and c.JS_IsStrictEqual(s.engine.context, try s.get(hydration, "hydrated"), c.pi_js_bool(s.engine.context, 0))) return c.pi_js_undefined();
    return source;
}
fn hydrationStage(engine: *h.Engine, work: c.JSValue, value: c.JSValue, rejected: bool, stage: c_int) anyerror!void {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    if (rejected or stage == 1) {
        try aw.complete(&s, work, if (rejected) value else c.pi_js_undefined(), rejected);
        return;
    }
    const bindings = try s.get(work, "bindings");
    const data = (try h.actor(&s, try s.get(work, "readable"), bindings, .MemberReadable)).data;
    const hydration = try cells.hydrationOf(&s, bindings, try current(&s, data, bindings));
    const pending = if (h.nullish(hydration)) c.pi_js_undefined() else try h.invoke(&s, hydration, "whenHydrated", &.{});
    try aw.wait(hydrationStage, &s, work, pending, 1);
}
fn waitHydrated(ctx: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue, _: c_int, captures: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = h.Engine.fromContext(ctx.?);
    return hydrationWait(engine, captures[0], captures[1]) catch |err| @import("native_durable.zig").rejectedPromise(engine, err);
}
fn hydrationWait(engine: *h.Engine, receiver: c.JSValue, bindings: c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    const work = try aw.create(&s);
    try h.field(&s, work, "readable", receiver);
    try h.field(&s, work, "bindings", bindings);
    const data = (try h.actor(&s, receiver, bindings, .MemberReadable)).data;
    try aw.wait(hydrationStage, &s, work, try s.get(try s.get(data, "handle"), "ready"), 0);
    return aw.result(&s, work);
}
fn invoke(engine: *h.Engine, receiver: c.JSValue, args: []const c.JSValue, method: Method, bindings: c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    const data = (try h.actor(&s, receiver, bindings, .MemberReadable)).data;
    const ref = try s.get(data, "handle");
    if (method == .value) {
        const status = try s.get(ref, "status");
        if (try s.equal(status, "released") or try s.equal(status, "gone")) return h.throwValue(&s, try h.invoke(&s, ref, "terminalError", &.{}));
        if (!try s.equal(status, "live")) return notReady(&s, data, bindings);
        const view = try h.invoke(&s, ref, "currentView", &.{});
        if (c.JS_IsUndefined(view)) return notReady(&s, data, bindings);
        const source = try current(&s, data, bindings);
        if (c.JS_IsUndefined(source)) {
            const variant = try s.get(view, "variant");
            return h.throwValue(&s, try h.errorValue(&s, bindings, "not_in_variant", &.{ try s.get(ref, "address"), try s.text(": "), try s.get(data, "name"), try s.text(" is not a state member of variant "), if (c.JS_IsString(variant)) variant else try s.text("(local)") }, c.pi_js_undefined()));
        }
        return js.get(engine, source, "value");
    }
    if (method == .hydration) {
        if (try s.equal(try s.get(ref, "status"), "live")) return s.result(try cells.hydrationOf(&s, bindings, try current(&s, data, bindings)));
        const hydration = try s.record();
        try h.field(&s, hydration, "hydrated", c.pi_js_bool(engine.context, 0));
        var captures = [_]c.JSValue{ receiver, bindings };
        const wait = try s.keep(try engine.checked(c.JS_NewCFunctionData2(engine.context, waitHydrated, "", 0, 0, 2, &captures)));
        const async_prototype = try s.keep(try engine.checked(c.JS_GetAsyncFunctionPrototype(engine.context)));
        if (c.JS_SetPrototype(engine.context, wait, async_prototype) < 0) return js.capture(engine);
        try h.field(&s, hydration, "whenHydrated", wait);
        return s.result(hydration);
    }
    if (method == .subscribe or method == .events) {
        const set = try s.get(data, if (method == .events) "events" else "values");
        _ = try h.invoke(&s, set, "add", &.{h.arg(args, 0)});
        const source = try readable(&s, data, bindings);
        if (!c.JS_IsUndefined(source)) {
            const value = try s.get(source, "value");
            const box = try s.record();
            try h.field(&s, box, "value", value);
            try h.field(&s, data, "seen", box);
            const announced = if (method == .subscribe) try s.get(source, "value") else blk: {
                const event = try s.record();
                try h.field(&s, event, "type", try s.text("snap"));
                try h.field(&s, event, "value", value);
                break :blk event;
            };
            try safe(&s, data, h.arg(args, 0), announced);
        } else if (method == .events) _ = try h.invoke(&s, try s.get(data, "unseen"), "add", &.{h.arg(args, 0)});
        _ = try h.invoke(&s, receiver, "bind", &.{});
        var captures = [_]c.JSValue{ receiver, bindings, set, h.arg(args, 0), c.pi_js_bool(engine.context, @intFromBool(method == .events)) };
        return engine.checked(c.JS_NewCFunctionData2(engine.context, unlisten, "", 0, 0, 5, &captures));
    }
    if (method == .stop) {
        _ = try h.invoke(&s, try s.get(data, "values"), "clear", &.{});
        _ = try h.invoke(&s, try s.get(data, "events"), "clear", &.{});
        _ = try h.invoke(&s, try s.get(data, "unseen"), "clear", &.{});
    }
    const listened = try @import("native_chord_object.zig").nonempty(&s, try s.get(data, "values")) or try @import("native_chord_object.zig").nonempty(&s, try s.get(data, "events"));
    const source = if (listened) try current(&s, data, bindings) else c.pi_js_undefined();
    if (c.JS_IsStrictEqual(engine.context, source, try s.get(data, "source"))) return c.pi_js_undefined();
    const previous = try s.get(data, "upstream");
    if (!c.JS_IsUndefined(previous)) _ = try s.keep(try js.call(engine, previous, c.pi_js_undefined(), &.{}));
    try h.field(&s, data, "upstream", c.pi_js_undefined());
    try h.field(&s, data, "source", source);
    if (c.JS_IsUndefined(source)) return c.pi_js_undefined();
    const first = try s.record();
    try h.field(&s, first, "value", c.pi_js_bool(engine.context, 1));
    var captures = [_]c.JSValue{ receiver, bindings, first };
    const listener = try s.keep(try engine.checked(c.JS_NewCFunctionData2(engine.context, upstream, "", 1, 0, 3, &captures)));
    try h.field(&s, data, "upstream", try h.invoke(&s, source, "events", &.{listener}));
    return c.pi_js_undefined();
}
fn construct(engine: *h.Engine, target: c.JSValue, args: []const c.JSValue, values: []const c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    const result = try s.keep(try h.allocate(engine, target, values[0], .MemberReadable));
    const data = (try h.actor(&s, result, values[0], .MemberReadable)).data;
    try h.field(&s, data, "handle", h.arg(args, 0));
    try h.field(&s, data, "name", h.arg(args, 1));
    inline for (.{ "values", "events", "unseen" }) |name| try h.field(&s, data, name, try h.set(&s));
    inline for (.{ "source", "upstream", "seen" }) |name| try h.field(&s, data, name, c.pi_js_undefined());
    return s.result(result);
}
pub fn install(engine: *h.Engine, bindings: c.JSValue) !void {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    try h.register(&s, bindings, .MemberReadable);
    const prototype = try s.record();
    try js.define(engine, bindings, "MemberReadable", try @import("native_class.zig").constructor(engine, "MemberReadable", 2, prototype, construct, &.{bindings}));
    inline for (.{ .{ "value", Method.value, 0, true }, .{ "subscribe", Method.subscribe, 1, false }, .{ "events", Method.events, 1, false }, .{ "bind", Method.bind, 0, false }, .{ "stop", Method.stop, 0, false } }) |item| try h.define(&s, prototype, bindings, item[0], callback, @intFromEnum(item[1]), item[2], item[3], false);
    const atom = try js.atom(engine, try s.get(bindings, "HYDRATION"));
    defer c.JS_FreeAtom(engine.context, atom);
    var captures = [_]c.JSValue{bindings};
    const getter = try engine.checked(c.JS_NewCFunctionData2(engine.context, callback, "get [chord.hydration]", 0, @intFromEnum(Method.hydration), 1, &captures));
    if (c.JS_DefinePropertyGetSet(engine.context, prototype, atom, getter, c.pi_js_undefined(), c.JS_PROP_CONFIGURABLE) < 0) return js.capture(engine);
}
