//! Actual single-source attachment cursor validation, disposal and isolation.
const r = @import("native_chord_replicated_values.zig");
const h = r.h;
const js = r.js;
const c = r.c;
const Scope = r.Scope;
const Method = enum(c_int) { value, subscribe, activate, dispose };
const Op = enum(c_int) { receive, report };
fn callback(ctx: ?*c.JSContext, receiver: c.JSValue, argc: c_int, argv: [*c]c.JSValue, magic: c_int, captures: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = h.Engine.fromContext(ctx.?);
    return invoke(engine, receiver, captures[0], if (argc > 0) argv[0] else c.pi_js_undefined(), @enumFromInt(magic)) catch |err| @import("native_durable.zig").reject(engine, err);
}
fn observer(ctx: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, magic: c_int, captures: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = h.Engine.fromContext(ctx.?);
    return observed(engine, captures[0], captures[1], if (argc > 0) argv[0] else c.pi_js_undefined(), @enumFromInt(magic)) catch |err| @import("native_durable.zig").reject(engine, err);
}
fn function(s: *Scope, state: c.JSValue, bindings: c.JSValue, op: Op) !c.JSValue {
    var captures = [_]c.JSValue{ state, bindings };
    return s.keep(try s.engine.checked(c.JS_NewCFunctionData2(s.engine.context, observer, "", 1, @intFromEnum(op), 2, &captures)));
}
fn assertCursor(s: *Scope, cursor: c.JSValue, kind: []const u8) !void {
    if (c.JS_ToBool(s.engine.context, try s.builtin("Number", "isSafeInteger", &.{cursor})) == 0) _ = try h.typeError(s, &.{ try s.text("Replicated state source "), try s.text(kind), try s.text(" cursor must be a safe integer") });
}
fn aggregate(s: *Scope, a: c.JSValue, b: c.JSValue, message: []const u8) !c.JSValue {
    const values = try s.list();
    try js.push(s.engine, values, a);
    try js.push(s.engine, values, b);
    return s.keep(try js.builtin(s.engine, "AggregateError", &.{ values, try s.text(message) }));
}
fn fail(s: *Scope, state: c.JSValue, owned: c.JSValue, reason: c.JSValue) !void {
    if (try h.flag(s, owned, "disposed")) return;
    try h.field(s, owned, "disposed", c.pi_js_bool(s.engine.context, 1));
    const generation = s.engine.native_allocation_generation;
    _ = h.invoke(s, try s.get(owned, "attachment"), "dispose", &.{}) catch |err| {
        const mapped = s.engine.nativeAllocationError(err, generation);
        if (mapped != error.JavaScriptException) return mapped;
        const combined = try aggregate(s, reason, s.engine.captured_exception orelse return err, "Replicated state source contract failed");
        try r.report(s, state, try s.get(owned, "reportError"), combined);
        return;
    };
    try r.report(s, state, try s.get(owned, "reportError"), reason);
}
fn receive(s: *Scope, owned: c.JSValue, frame: c.JSValue) !void {
    try assertCursor(s, try s.get(frame, "cursor"), "frame");
    const expected = try r.binary(s, 0, try s.get(owned, "cursor"), c.JS_NewInt32(s.engine.context, 1));
    if (!c.JS_IsStrictEqual(s.engine.context, try s.get(frame, "cursor"), expected)) _ = try h.throwValue(s, try s.keep(try js.builtin(s.engine, "Error", &.{try s.keep(try @import("native_utf16.zig").concat(s.engine, &.{ try s.text("Replicated state source cursor has a gap: expected "), expected, try s.text(", received "), try s.get(frame, "cursor") }))})));
    try h.field(s, owned, "cursor", try s.get(frame, "cursor"));
    _ = try h.invoke(s, try s.get(owned, "publisher"), "publish", &.{ try s.get(frame, "value"), try s.get(frame, "context") });
}
fn observed(engine: *h.Engine, state: c.JSValue, bindings: c.JSValue, value: c.JSValue, op: Op) !c.JSValue {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    const owned = try r.own(&s, state, bindings, .ReplicatedAttached);
    if (op == .report) {
        try r.report(&s, state, try s.get(owned, "reportError"), value);
        return c.pi_js_undefined();
    }
    if (try h.flag(&s, owned, "disposed")) return c.pi_js_undefined();
    const generation = engine.native_allocation_generation;
    receive(&s, owned, value) catch |err| {
        const mapped = engine.nativeAllocationError(err, generation);
        if (mapped != error.JavaScriptException) return mapped;
        try fail(&s, state, owned, try r.toError(&s, engine.captured_exception orelse return err));
    };
    return c.pi_js_undefined();
}
fn invoke(engine: *h.Engine, state: c.JSValue, bindings: c.JSValue, arg: c.JSValue, method: Method) !c.JSValue {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    const owned = try r.own(&s, state, bindings, .ReplicatedAttached);
    switch (method) {
        .value => return js.get(engine, try s.get(owned, "publisher"), "value"),
        .subscribe => return js.invoke(engine, try s.get(owned, "publisher"), "subscribe", &.{arg}),
        .activate => _ = try h.invoke(&s, try s.get(owned, "attachment"), "activate", &.{try function(&s, state, bindings, .receive)}),
        .dispose => {
            if (try h.flag(&s, owned, "disposed")) return c.pi_js_undefined();
            try h.field(&s, owned, "disposed", c.pi_js_bool(engine.context, 1));
            _ = try h.invoke(&s, try s.get(owned, "attachment"), "dispose", &.{});
        },
    }
    return c.pi_js_undefined();
}
fn construct(engine: *h.Engine, target: c.JSValue, args: []const c.JSValue, captures: []const c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    const state = try s.keep(try h.allocate(engine, target, captures[0], .ReplicatedAttached));
    const owned = try r.own(&s, state, captures[0], .ReplicatedAttached);
    const attachment = h.arg(args, 0);
    const snapshot = try s.get(attachment, "snapshot");
    try assertCursor(&s, try s.get(snapshot, "cursor"), "snapshot");
    try h.field(&s, owned, "attachment", attachment);
    try h.field(&s, owned, "cursor", try s.get(snapshot, "cursor"));
    const report_error = try s.get(h.arg(args, 1), "onError");
    try h.field(&s, owned, "reportError", if (h.nullish(report_error)) try @import("native_chord_replicated_publisher.zig").reporter(&s) else report_error);
    try h.field(&s, owned, "publisher", try h.construct(&s, captures[0], "ReplicatedStatePublisher", &.{ try s.get(snapshot, "value"), try function(&s, state, captures[0], .report) }));
    try h.field(&s, owned, "disposed", c.pi_js_bool(engine.context, 0));
    return s.result(state);
}
pub fn attach(engine: *h.Engine, bindings: c.JSValue, source: c.JSValue, options: c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    const attachment = try h.invoke(&s, source, "attach", &.{});
    const generation = engine.native_allocation_generation;
    return attachAndActivate(&s, bindings, attachment, if (c.JS_IsUndefined(options)) try s.record() else options) catch |err| {
        const mapped = engine.nativeAllocationError(err, generation);
        if (mapped != error.JavaScriptException) return mapped;
        const original = try s.keep(c.JS_DupValue(engine.context, engine.captured_exception orelse return err));
        const cleanup_generation = engine.native_allocation_generation;
        _ = h.invoke(&s, attachment, "dispose", &.{}) catch |cleanup_error| {
            const cleanup_mapped = engine.nativeAllocationError(cleanup_error, cleanup_generation);
            if (cleanup_mapped != error.JavaScriptException) return cleanup_mapped;
            return h.throwValue(&s, try aggregate(&s, original, engine.captured_exception orelse return cleanup_error, "Failed to attach replicated state source"));
        };
        return h.throwValue(&s, original);
    };
}
fn attachAndActivate(s: *Scope, bindings: c.JSValue, attachment: c.JSValue, options: c.JSValue) !c.JSValue {
    const state = try h.construct(s, bindings, "AttachedReplicatedStateImpl", &.{ attachment, options });
    _ = try h.invoke(s, state, "activate", &.{});
    return s.result(state);
}
pub fn install(engine: *h.Engine, bindings: c.JSValue) !void {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    try h.register(&s, bindings, .ReplicatedAttached);
    const prototype = try s.record();
    try js.define(engine, bindings, "AttachedReplicatedStateImpl", try @import("native_class.zig").constructor(engine, "AttachedReplicatedStateImpl", 2, prototype, construct, &.{bindings}));
    inline for (.{ .{ "value", Method.value, 0, true }, .{ "subscribe", Method.subscribe, 1, false }, .{ "activate", Method.activate, 0, false }, .{ "dispose", Method.dispose, 0, false } }) |item| try h.define(&s, prototype, bindings, item[0], callback, @intFromEnum(item[1]), item[2], item[3], false);
}
