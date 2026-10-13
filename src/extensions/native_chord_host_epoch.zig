//! Actual previous-epoch retirement; detach removed derives, close resources, then release holds.
const h = @import("native_chord_host_values.zig");
const Scope = h.Scope;
const js = h.js;
const c = h.c;
fn report(ctx: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, captures: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = h.Engine.fromContext(ctx.?);
    return js.invoke(engine, captures[0], "report", &.{if (argc > 0) argv[0] else c.pi_js_undefined()}) catch |err| @import("native_durable.zig").reject(engine, err);
}
fn keep(s: *Scope, declarations: c.JSValue, name: [*:0]const u8) !c.JSValue {
    const set = try h.set(s);
    for (0..try h.length(s, declarations)) |index| {
        const values = try h.values(s, try s.get(try s.at(declarations, index), name));
        for (0..try h.length(s, values)) |slot| _ = try h.invoke(s, set, "add", &.{try s.at(values, slot)});
    }
    return set;
}
fn sort(ctx: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, captures: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = h.Engine.fromContext(ctx.?);
    return compare(engine, captures[0], if (argc > 0) argv[0] else c.pi_js_undefined(), if (argc > 1) argv[1] else c.pi_js_undefined()) catch |err| @import("native_durable.zig").reject(engine, err);
}
fn compare(engine: *h.Engine, order: c.JSValue, left: c.JSValue, right: c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    var a: f64 = 0;
    var b: f64 = 0;
    if (c.JS_ToFloat64(engine.context, &a, try h.invoke(&s, order, "indexOf", &.{left})) < 0 or c.JS_ToFloat64(engine.context, &b, try h.invoke(&s, order, "indexOf", &.{right})) < 0) return js.capture(engine);
    return c.JS_NewFloat64(engine.context, b - a);
}
pub fn retireBehavior(engine: *h.Engine, bindings: c.JSValue, host: c.JSValue, record: c.JSValue, epoch: c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    const behaviors = try s.get(record, "behaviors");
    const installed = try h.invoke(&s, behaviors, "get", &.{epoch});
    _ = try h.invoke(&s, behaviors, "delete", &.{epoch});
    if (c.JS_IsUndefined(installed) or c.JS_IsStrictEqual(engine.context, try s.get(installed, "decls"), try s.get(record, "decls"))) return c.pi_js_undefined();
    const declarations = try h.snapshot(&s, try h.invoke(&s, record, "allDecls", &.{}));
    const holds = try keep(&s, declarations, "holds");
    const resources = try keep(&s, declarations, "resources");
    const derives = try keep(&s, declarations, "derives");
    const retired = try s.get(installed, "decls");
    const old_derives = try h.values(&s, try s.get(retired, "derives"));
    for (0..try h.length(&s, old_derives)) |index| {
        const derived = try s.at(old_derives, index);
        if (c.JS_ToBool(engine.context, try h.invoke(&s, derives, "has", &.{derived})) == 0) _ = try h.invoke(&s, derived, "detach", &.{});
    }
    const closing = try s.list();
    const old_resources = try h.values(&s, try s.get(retired, "resources"));
    for (0..try h.length(&s, old_resources)) |index| {
        const resource = try s.at(old_resources, index);
        if (c.JS_ToBool(engine.context, try h.invoke(&s, resources, "has", &.{resource})) == 0) try js.push(engine, closing, resource);
    }
    var captures = [_]c.JSValue{try s.get(record, "openOrder")};
    const comparator = try s.keep(try engine.checked(c.JS_NewCFunctionData2(engine.context, sort, "", 2, 0, 1, &captures)));
    _ = try h.invoke(&s, closing, "sort", &.{comparator});
    const releasing = try s.list();
    const old_holds = try h.values(&s, try s.get(retired, "holds"));
    for (0..try h.length(&s, old_holds)) |index| {
        const hold = try s.at(old_holds, index);
        if (c.JS_ToBool(engine.context, try h.invoke(&s, holds, "has", &.{hold})) == 0) try js.push(engine, releasing, hold);
    }
    _ = try h.invoke(&s, record, "refreshSchemas", &.{});
    const label = try s.keep(try @import("native_utf16.zig").concat(engine, &.{ try s.text("retiring epoch "), epoch, try s.text(" failed") }));
    const pending = try s.keep(@import("native_chord_host_record_lifecycle.zig").cleanup(engine, record, bindings, closing, releasing, label, false) catch |err| if (err == error.JavaScriptException) @import("native_durable.zig").rejectedPromise(engine, err) else return err);
    var reporter_captures = [_]c.JSValue{host};
    const observer = try s.keep(try engine.checked(c.JS_NewCFunctionData2(engine.context, report, "", 1, 0, 1, &reporter_captures)));
    const promise = try s.keep(try h.resolved(engine, pending));
    _ = try h.invoke(&s, promise, "catch", &.{observer});
    return c.pi_js_undefined();
}
pub fn retire(engine: *h.Engine, host: c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    const previous = try s.get(host, "previous");
    if (c.JS_IsUndefined(previous)) return c.pi_js_undefined();
    try js.setKey(engine, host, try s.text("previous"), c.pi_js_undefined());
    const epoch = try s.get(previous, "id");
    _ = try h.invoke(&s, try s.get(host, "epochs"), "delete", &.{epoch});
    const records = try h.values(&s, try s.get(host, "records"));
    for (0..try h.length(&s, records)) |index| _ = try h.invoke(&s, host, "retireBehavior", &.{ try s.at(records, index), epoch });
    const symbol = try h.iteratorSymbol(&s);
    var iterator = try js.Iterator.init(engine, try s.get(host, "connections"), symbol);
    defer iterator.deinit();
    errdefer iterator.closePreserving();
    while (try iterator.next()) |connection| {
        defer engine.freeValue(connection);
        if (!try s.equal(try s.get(connection, "role"), "downstream")) continue;
        const peer = try s.get(connection, "peer");
        if (h.nullish(peer) or !try s.equal(try s.get(peer, "kind"), "host")) continue;
        const frame = try s.record();
        try h.field(&s, frame, "t", try s.text("retire"));
        try h.field(&s, frame, "epoch", epoch);
        _ = try h.invoke(&s, connection, "send", &.{frame});
    }
    _ = try h.invoke(&s, host, "retired", &.{});
    return c.pi_js_undefined();
}
