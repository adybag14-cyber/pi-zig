//! Actual Source/Fanout classes and the module-shared publication graph.
const h = @import("native_chord_host_values.zig");
pub const Scope = h.Scope;
pub const js = h.js;
pub const c = h.c;
const Method = enum(c_int) { subscribe, events, validate, own_schemas, fanout_subscribe, fanout_events, fanout_emit, is_source, not_ready };
fn callback(ctx: ?*c.JSContext, receiver: c.JSValue, argc: c_int, argv: [*c]c.JSValue, magic: c_int, captures: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = h.Engine.fromContext(ctx.?);
    return invoke(engine, receiver, if (argc > 0) argv[0..@intCast(argc)] else &.{}, @enumFromInt(magic), captures[0]) catch |err| @import("native_durable.zig").reject(engine, err);
}
pub fn isSource(s: *Scope, bindings: c.JSValue, value: c.JSValue) !bool {
    const result = c.JS_IsInstanceOf(s.engine.context, value, try s.get(bindings, "Source"));
    if (result < 0) return js.capture(s.engine);
    return result != 0;
}
pub fn sourceOptions(s: *Scope, receiver: c.JSValue) !c.JSValue {
    return s.get(receiver, "options");
}
pub fn report(s: *Scope, receiver: c.JSValue, failure: c.JSValue) !void {
    _ = try h.invoke(s, try sourceOptions(s, receiver), "report", &.{failure});
}
fn safe(s: *Scope, fanout: c.JSValue, data: c.JSValue, listener: c.JSValue, value: c.JSValue) !void {
    const result = js.call(s.engine, listener, c.pi_js_undefined(), &.{value}) catch |err| {
        if (err != error.JavaScriptException) return err;
        const original = try s.keep(c.JS_DupValue(s.engine.context, s.engine.captured_exception orelse return err));
        _ = try s.keep(try js.call(s.engine, try s.get(data, "report"), fanout, &.{original}));
        return;
    };
    s.engine.freeValue(result);
}
fn unsubscribe(ctx: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue, _: c_int, captures: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = h.Engine.fromContext(ctx.?);
    return js.invoke(engine, captures[0], "delete", &.{captures[1]}) catch |err| @import("native_durable.zig").reject(engine, err);
}
fn deliver(ctx: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue, _: c_int, captures: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = h.Engine.fromContext(ctx.?);
    return delivery(engine, captures) catch |err| @import("native_durable.zig").reject(engine, err);
}
fn delivery(engine: *h.Engine, captures: [*c]c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    const fanout = captures[0];
    const data = (try h.actor(&s, fanout, captures[1], .Fanout)).data;
    inline for (.{ "events", "values" }, 0..) |name, index| {
        const current = try s.get(data, name);
        const selected = captures[index + 2];
        for (0..try h.length(&s, selected)) |slot| {
            const listener = try s.at(selected, slot);
            if (c.JS_ToBool(engine.context, try h.invoke(&s, current, "has", &.{listener})) == 0) continue;
            const value = if (index == 0) captures[4] else try s.get(captures[4], "value");
            try safe(&s, fanout, data, listener, value);
        }
    }
    return c.pi_js_undefined();
}
fn validateList(s: *Scope, bindings: c.JSValue, receiver: c.JSValue, schemas: c.JSValue, value: c.JSValue) !void {
    const symbol = try h.iteratorSymbol(s);
    var iterator = try js.Iterator.init(s.engine, schemas, symbol);
    defer iterator.deinit();
    errdefer iterator.closePreserving();
    while (try iterator.next()) |schema| {
        defer s.engine.freeValue(schema);
        const what = try s.keep(try @import("native_utf16.zig").concat(s.engine, &.{ try s.text("state "), try s.get(receiver, "key") }));
        try @import("native_chord_host_record_schema.zig").assertValid(s, bindings, "state", what, schema, value);
    }
}
fn invoke(engine: *h.Engine, receiver: c.JSValue, args: []const c.JSValue, method: Method, bindings: c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    if (method == .is_source) return c.pi_js_bool(engine.context, @intFromBool(try isSource(&s, bindings, h.arg(args, 0))));
    if (method == .not_ready) return s.result(try h.errorValue(&s, bindings, "not_ready", &.{ h.arg(args, 0), try s.text(" is not ready") }, c.pi_js_undefined()));
    if (method == .own_schemas) return js.array(engine);
    if (method == .subscribe or method == .events) return js.invoke(engine, try s.get(receiver, "fanout"), if (method == .subscribe) "subscribe" else "events", &.{ h.arg(args, 0), try s.get(receiver, "value") });
    if (method == .validate) {
        if (!try h.flag(&s, try s.get(receiver, "options"), "dev")) return c.pi_js_undefined();
        try validateList(&s, bindings, receiver, try h.invoke(&s, receiver, "ownSchemas", &.{}), h.arg(args, 0));
        try validateList(&s, bindings, receiver, try s.get(receiver, "schemas"), h.arg(args, 0));
        return c.pi_js_undefined();
    }
    const data = (try h.actor(&s, receiver, bindings, .Fanout)).data;
    if (method == .fanout_subscribe or method == .fanout_events) {
        const set = try s.get(data, if (method == .fanout_subscribe) "values" else "events");
        _ = try h.invoke(&s, set, "add", &.{h.arg(args, 0)});
        const announced = if (method == .fanout_subscribe) h.arg(args, 1) else blk: {
            const event = try s.record();
            try h.field(&s, event, "type", try s.text("snap"));
            try h.field(&s, event, "value", h.arg(args, 1));
            break :blk event;
        };
        try safe(&s, receiver, data, h.arg(args, 0), announced);
        var captures = [_]c.JSValue{ set, h.arg(args, 0) };
        return engine.checked(c.JS_NewCFunctionData2(engine.context, unsubscribe, "", 0, 0, 2, &captures));
    }
    const events = try h.snapshot(&s, try s.get(data, "events"));
    const values = try h.snapshot(&s, try s.get(data, "values"));
    var captures = [_]c.JSValue{ receiver, bindings, events, values, h.arg(args, 0) };
    const task = try s.keep(try engine.checked(c.JS_NewCFunctionData2(engine.context, deliver, "", 0, 0, 5, &captures)));
    try @import("native_chord_publish.zig").enqueue(engine, bindings, task);
    return c.pi_js_undefined();
}
pub fn initialize(s: *Scope, bindings: c.JSValue, receiver: c.JSValue, key: c.JSValue, options: c.JSValue) !void {
    const sequence = try s.get(bindings, "sourceSequence");
    var count: f64 = 0;
    if (c.JS_ToFloat64(s.engine.context, &count, sequence) < 0) return js.capture(s.engine);
    count += 1;
    try h.field(s, bindings, "sourceSequence", c.JS_NewFloat64(s.engine.context, count));
    try h.field(s, receiver, "key", key);
    try h.field(s, receiver, "seq", c.JS_NewFloat64(s.engine.context, count));
    try h.field(s, receiver, "dependents", try h.set(s));
    try h.field(s, receiver, "schemas", try s.list());
    try h.field(s, receiver, "options", options);
    try h.field(s, receiver, "fanout", try h.construct(s, bindings, "Fanout", &.{try s.get(options, "report")}));
}
fn constructSource(engine: *h.Engine, target: c.JSValue, args: []const c.JSValue, captures: []const c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    const result = try s.keep(try h.allocate(engine, target, captures[0], .Source));
    try initialize(&s, captures[0], result, h.arg(args, 0), h.arg(args, 1));
    return s.result(result);
}
fn constructFanout(engine: *h.Engine, target: c.JSValue, args: []const c.JSValue, captures: []const c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    const result = try s.keep(try h.allocate(engine, target, captures[0], .Fanout));
    const data = (try h.actor(&s, result, captures[0], .Fanout)).data;
    try h.field(&s, data, "values", try h.set(&s));
    try h.field(&s, data, "events", try h.set(&s));
    try h.field(&s, data, "report", h.arg(args, 0));
    return s.result(result);
}
pub fn install(engine: *h.Engine, bindings: c.JSValue) !void {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    try h.register(&s, bindings, .Source);
    try h.register(&s, bindings, .Fanout);
    try h.field(&s, bindings, "sourceSequence", c.JS_NewInt32(engine.context, 0));
    const source_prototype = try s.record();
    try js.define(engine, bindings, "Source", try @import("native_class.zig").constructor(engine, "Source", 2, source_prototype, constructSource, &.{bindings}));
    const fanout_prototype = try s.record();
    try js.define(engine, bindings, "Fanout", try @import("native_class.zig").constructor(engine, "Fanout", 1, fanout_prototype, constructFanout, &.{bindings}));
    inline for (.{ .{ "subscribe", Method.subscribe, 1 }, .{ "events", Method.events, 1 }, .{ "validate", Method.validate, 1 }, .{ "ownSchemas", Method.own_schemas, 0 } }) |item| try h.define(&s, source_prototype, bindings, item[0], callback, @intFromEnum(item[1]), item[2], false, false);
    inline for (.{ .{ "subscribe", Method.fanout_subscribe, 2 }, .{ "events", Method.fanout_events, 2 }, .{ "emit", Method.fanout_emit, 1 } }) |item| try h.define(&s, fanout_prototype, bindings, item[0], callback, @intFromEnum(item[1]), item[2], false, false);
    try @import("native_chord_cells_cell.zig").install(engine, bindings);
    try @import("native_chord_cells_derived.zig").install(engine, bindings);
    inline for (.{ .{ "isSource", Method.is_source }, .{ "notReady", Method.not_ready } }) |item| {
        var captures = [_]c.JSValue{bindings};
        try js.define(engine, bindings, item[0], try engine.checked(c.JS_NewCFunctionData2(engine.context, callback, item[0], 1, @intFromEnum(item[1]), 1, &captures)));
    }
}
