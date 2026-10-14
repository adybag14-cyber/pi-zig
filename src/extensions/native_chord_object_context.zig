//! Actual Chord CtxImpl fields, private expiry and call-owned holds.
const h = @import("native_chord_host_values.zig");
const Scope = h.Scope;
const js = h.js;
const c = h.c;
const Method = enum(c_int) { closed, check, get, child, close };
fn callback(context: ?*c.JSContext, receiver: c.JSValue, argc: c_int, argv: [*c]c.JSValue, operation: c_int, data: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = h.Engine.fromContext(context.?);
    return invoke(engine, receiver, if (argc > 0) argv[0..@intCast(argc)] else &.{}, @enumFromInt(operation), data[0]) catch |err| @import("native_durable.zig").reject(engine, err);
}
fn invoke(engine: *h.Engine, receiver: c.JSValue, args: []const c.JSValue, method: Method, bindings: c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    if (method == .closed) return s.result(try s.get((try h.actor(&s, receiver, bindings, .ObjectCtx)).data, "closed"));
    if (method == .check) {
        if (!c.JS_IsStrictEqual(engine.context, try s.get(receiver, "host"), h.arg(args, 0))) return h.invalid(&s, bindings, "foreign_ctx", &.{try s.text("ctx belongs to another host")});
        const owned = try h.actor(&s, receiver, bindings, .ObjectCtx);
        if (try h.flag(&s, owned.data, "closed")) {
            const options = try s.record();
            try h.field(&s, options, "reason", try s.text("expired"));
            return h.throwValue(&s, try h.errorValue(&s, bindings, "aborted", &.{try s.text("ctx expired: its call already settled")}, options));
        }
        const signal = try s.get(receiver, "signal");
        if (try h.flag(&s, signal, "aborted")) {
            const options = try s.record();
            const reason = try s.get(signal, "reason");
            try h.field(&s, options, "cause", reason);
            const chord = c.JS_IsInstanceOf(engine.context, reason, try s.get(try s.get(bindings, "errors"), "ChordError"));
            if (chord < 0) return js.capture(engine);
            if (chord != 0 and try s.equal(try s.get(reason, "code"), "superseded")) return h.throwValue(&s, try h.errorValue(&s, bindings, "superseded", &.{try s.get(reason, "message")}, options));
            return h.throwValue(&s, try h.errorValue(&s, bindings, "aborted", &.{try s.text("ctx aborted")}, options));
        }
        return c.pi_js_undefined();
    }
    if (method == .get) {
        const host = try s.get(receiver, "host");
        _ = try h.invoke(&s, receiver, "check", &.{host});
        const options = try s.record();
        try h.field(&s, options, "principal", try s.get(receiver, "principal"));
        try js.spreadInto(engine, options, h.arg(args, 2));
        const handle = try h.invoke(&s, host, "acquire", &.{ h.arg(args, 0), h.arg(args, 1), options, try s.text("call") });
        const owned = try h.actor(&s, receiver, bindings, .ObjectCtx);
        _ = try h.invoke(&s, try s.get(owned.data, "refs"), "push", &.{handle});
        return js.get(engine, handle, "proxy");
    }
    if (method == .child) {
        const host = try s.get(receiver, "host");
        const signals = try s.list();
        try js.push(engine, signals, try s.get(receiver, "signal"));
        try js.push(engine, signals, try s.get(try s.get(h.arg(args, 0), "callAbort"), "signal"));
        const fields = try s.record();
        try h.field(&s, fields, "signals", signals);
        try h.field(&s, fields, "rootId", try s.get(receiver, "rootId"));
        try h.field(&s, fields, "codeVersion", try s.get(receiver, "codeVersion"));
        try h.field(&s, fields, "principal", try s.get(host, "principal"));
        return s.result(try h.construct(&s, bindings, "CtxImpl", &.{ host, fields }));
    }
    const owned = try h.actor(&s, receiver, bindings, .ObjectCtx);
    try h.field(&s, owned.data, "closed", c.pi_js_bool(engine.context, 1));
    _ = try s.keep(try js.call(engine, try s.get(owned.data, "release"), receiver, &.{}));
    const holds = try h.invoke(&s, try s.get(owned.data, "refs"), "splice", &.{c.JS_NewInt32(engine.context, 0)});
    const iterator_symbol = try s.keep(try engine.checked(c.JS_GetIteratorSymbol(engine.context)));
    var iterator = try js.Iterator.init(engine, holds, iterator_symbol);
    defer iterator.deinit();
    errdefer iterator.closePreserving();
    while (try iterator.next()) |handle| {
        defer engine.freeValue(handle);
        _ = try h.invoke(&s, handle, "release", &.{});
    }
    return c.pi_js_undefined();
}
fn construct(engine: *h.Engine, target: c.JSValue, args: []const c.JSValue, values: []const c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    const bindings = values[0];
    const result = try s.keep(try h.allocate(engine, target, bindings, .ObjectCtx));
    const owned = try h.actor(&s, result, bindings, .ObjectCtx);
    try h.field(&s, owned.data, "refs", try s.list());
    try h.field(&s, owned.data, "closed", c.pi_js_bool(engine.context, 0));
    try h.field(&s, result, "host", h.arg(args, 0));
    const linked = try @import("native_chord_signal.zig").linked(&s, try s.get(h.arg(args, 1), "signals"));
    try h.field(&s, result, "signal", try s.get(linked, "signal"));
    try h.field(&s, owned.data, "release", try s.get(linked, "release"));
    inline for (.{ "rootId", "codeVersion", "principal" }) |name| try h.field(&s, result, name, try s.get(h.arg(args, 1), name));
    const holder = try s.get(h.arg(args, 1), "holder");
    try h.field(&s, result, "holder", if (h.nullish(holder)) c.pi_js_bool(engine.context, 0) else holder);
    return s.result(result);
}
pub fn install(engine: *h.Engine, bindings: c.JSValue) !void {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    try h.register(&s, bindings, .ObjectCtx);
    const prototype = try s.record();
    const constructor = try @import("native_class.zig").constructor(engine, "CtxImpl", 2, prototype, construct, &.{bindings});
    try js.define(engine, bindings, "CtxImpl", constructor);
    inline for (.{ .{ "closed", Method.closed, 0, true }, .{ "check", Method.check, 1, false }, .{ "get", Method.get, 3, false }, .{ "child", Method.child, 1, false }, .{ "close", Method.close, 0, false } }) |item| try h.define(&s, prototype, bindings, item[0], callback, @intFromEnum(item[1]), item[2], item[3], false);
}
