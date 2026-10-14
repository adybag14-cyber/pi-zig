//! Actual b45 dependency opens plus bounded collective reference readiness.
const h = @import("native_chord_host_values.zig");
const js = h.js;
const c = h.c;
const Scope = h.Scope;
const aw = @import("native_chord_async_work.zig");
const Op = enum(c_int) { resource, dependency, ready, loading, address, waiting, rejected };
fn callback(ctx: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, magic: c_int, captures: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = h.Engine.fromContext(ctx.?);
    return invoke(engine, captures[0], if (argc > 0) argv[0] else c.pi_js_undefined(), @enumFromInt(magic)) catch |err| @import("native_durable.zig").reject(engine, err);
}
fn function(s: *Scope, work: c.JSValue, op: Op) !c.JSValue {
    var captures = [_]c.JSValue{work};
    return s.keep(try s.engine.checked(c.JS_NewCFunctionData2(s.engine.context, callback, "", 1, @intFromEnum(op), 1, &captures)));
}
fn append(s: *Scope, array: c.JSValue, iterable: c.JSValue) !void {
    var iterator = try js.Iterator.init(s.engine, iterable, try h.iteratorSymbol(s));
    defer iterator.deinit();
    errdefer iterator.closePreserving();
    while (try iterator.next()) |value| {
        defer s.engine.freeValue(value);
        try js.push(s.engine, array, value);
    }
}
fn invoke(engine: *h.Engine, work: c.JSValue, value: c.JSValue, op: Op) !c.JSValue {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    switch (op) {
        .resource => return openOne(engine, work, value),
        .dependency => {
            const instance = c.JS_IsInstanceOf(engine.context, value, try s.get(try s.get(work, "bindings"), "ResourceImpl"));
            if (instance < 0) return js.capture(engine);
            if (instance == 0) return js.get(engine, value, "ready");
            if (c.JS_ToBool(engine.context, try h.invoke(&s, try s.get(work, "resources"), "includes", &.{value})) != 0) return openOne(engine, work, value);
            return c.pi_js_undefined();
        },
        .ready => return js.get(engine, value, "ready"),
        .loading => return c.pi_js_bool(engine.context, @intFromBool(try s.equal(try s.get(value, "status"), "loading"))),
        .address => return js.get(engine, value, "address"),
        .waiting => return js.invoke(engine, try h.invoke(&s, try s.get(work, "refs"), "filter", &.{try function(&s, work, .loading)}), "map", &.{try function(&s, work, .address)}),
        .rejected => return c.pi_js_bool(engine.context, @intFromBool(try s.equal(try s.get(value, "status"), "rejected"))),
    }
}
fn openOne(engine: *h.Engine, parent: c.JSValue, resource: c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    const opening = try s.get(parent, "opening");
    const existing = try h.invoke(&s, opening, "get", &.{resource});
    if (!c.JS_IsUndefined(existing)) return s.result(existing);
    const work = try aw.create(&s);
    inline for (.{ "object", "bindings", "resources", "signal", "opening" }) |name| try h.field(&s, work, name, try s.get(parent, name));
    try h.field(&s, work, "resource", resource);
    // An async IIFE starts its synchronous portion immediately, before map.set.
    startResource(&s, work) catch |err| try aw.rejectError(&s, work, err);
    const pending = try s.get(work, "promise");
    _ = try h.invoke(&s, opening, "set", &.{ resource, pending });
    return s.result(pending);
}
fn startResource(s: *Scope, work: c.JSValue) !void {
    const promise = try s.keep(try js.global(s.engine, "Promise"));
    const all = try s.get(promise, "all");
    const deps = try h.invoke(s, try s.get(try s.get(work, "resource"), "deps"), "map", &.{try function(s, work, .dependency)});
    try aw.wait(resourceStage, s, work, try s.keep(try js.call(s.engine, all, promise, &.{deps})), 0);
}
fn resourceStage(engine: *h.Engine, work: c.JSValue, value: c.JSValue, rejected: bool, stage: c_int) anyerror!void {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    if (rejected or stage == 1) {
        try aw.complete(&s, work, if (rejected) value else c.pi_js_undefined(), rejected);
        return;
    }
    const pending = try h.invoke(&s, try s.get(work, "resource"), "open", &.{ try s.get(work, "signal"), try s.get(try s.get(work, "object"), "openOrder") });
    try aw.wait(resourceStage, &s, work, pending, 1);
}
fn settled(engine: *h.Engine, work: c.JSValue, value: c.JSValue, rejected: bool, _: c_int) anyerror!void {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    if (rejected) {
        try aw.complete(&s, work, value, true);
        return;
    }
    const failure = try h.invoke(&s, value, "find", &.{try function(&s, work, .rejected)});
    try aw.complete(&s, work, if (c.JS_IsUndefined(failure)) c.pi_js_undefined() else try s.get(failure, "reason"), !c.JS_IsUndefined(failure));
}
pub fn open(engine: *h.Engine, record: c.JSValue, bindings: c.JSValue, resources: c.JSValue, refs: c.JSValue, signal: c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    const work = try aw.create(&s);
    inline for (.{ "object", "bindings", "resources", "refs", "signal" }, .{ record, bindings, resources, refs, signal }) |name, value| try h.field(&s, work, name, value);
    try h.field(&s, work, "opening", try h.map(&s));
    const promise = try s.keep(try js.global(engine, "Promise"));
    const all = try s.get(promise, "all");
    const readies = try h.invoke(&s, refs, "map", &.{try function(&s, work, .ready)});
    const ready = try h.invoke(&s, record, "withinReadyTimeout", &.{ try s.keep(try js.call(engine, all, promise, &.{readies})), try function(&s, work, .waiting) });
    const all_settled = try s.get(promise, "allSettled");
    const pending = try s.list();
    try append(&s, pending, try h.invoke(&s, resources, "map", &.{try function(&s, work, .resource)}));
    try js.push(engine, pending, ready);
    try aw.wait(settled, &s, work, try s.keep(try js.call(engine, all_settled, promise, &.{pending})), 0);
    return aw.result(&s, work);
}
