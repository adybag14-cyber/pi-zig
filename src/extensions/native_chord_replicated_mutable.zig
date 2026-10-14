//! Actual authoritative replicated state over the genuine overlay Tracker.
const r = @import("native_chord_replicated_values.zig");
const h = r.h;
const js = r.js;
const c = r.c;
const Scope = r.Scope;
const Method = enum(c_int) { value, change, replace, subscribe };
fn callback(ctx: ?*c.JSContext, receiver: c.JSValue, argc: c_int, argv: [*c]c.JSValue, magic: c_int, captures: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = h.Engine.fromContext(ctx.?);
    return invoke(engine, receiver, captures[0], if (argc > 0) argv[0..@intCast(argc)] else &.{}, @enumFromInt(magic)) catch |err| @import("native_durable.zig").reject(engine, err);
}
fn noop(_: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue) callconv(.c) c.JSValue {
    return c.pi_js_undefined();
}
fn runChange(s: *Scope, change: c.JSValue, mutate: c.JSValue) !c.JSValue {
    const outcome = try s.keep(try js.call(s.engine, mutate, c.pi_js_undefined(), &.{try s.get(change, "state")}));
    if (try r.promiseLike(s, outcome)) {
        const promise = try s.builtin("Promise", "resolve", &.{outcome});
        const ignored = try s.keep(try s.engine.checked(c.JS_NewCFunction(s.engine.context, noop, "", 0)));
        _ = try h.invoke(s, promise, "catch", &.{ignored});
        return h.typeError(s, &.{try s.text("Replicated state change callbacks must be synchronous")});
    }
    return h.invoke(s, change, "prepare", &.{});
}
fn prepare(s: *Scope, tracker: c.JSValue, mutate: c.JSValue) !c.JSValue {
    const change = try h.invoke(s, tracker, "beginChange", &.{});
    return runChange(s, change, mutate) catch |err| {
        // Source aborts before rethrow; an abort failure itself takes precedence.
        _ = try h.invoke(s, change, "abort", &.{});
        return err;
    };
}
fn invoke(engine: *h.Engine, state: c.JSValue, bindings: c.JSValue, args: []const c.JSValue, method: Method) !c.JSValue {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    const owned = try r.own(&s, state, bindings, .ReplicatedMutable);
    const tracker = try s.get(owned, "tracker");
    if (method == .value) return js.get(engine, tracker, "value");
    if (method == .subscribe) return js.invoke(engine, try s.get(owned, "publisher"), "subscribe", &.{h.arg(args, 0)});
    if (try h.flag(&s, owned, "changing")) return h.runtimeError(&s, if (method == .change) "Replicated state cannot be changed reentrantly from a change callback" else "Replicated state cannot be replaced from a change callback");
    const prepared = if (method == .change) value: {
        try h.field(&s, owned, "changing", c.pi_js_bool(engine.context, 1));
        const result = prepare(&s, tracker, h.arg(args, 1)) catch |err| {
            try h.field(&s, owned, "changing", c.pi_js_bool(engine.context, 0));
            return err;
        };
        try h.field(&s, owned, "changing", c.pi_js_bool(engine.context, 0));
        break :value result;
    } else try h.invoke(&s, tracker, "prepareReplace", &.{h.arg(args, 1)});
    _ = try h.invoke(&s, tracker, "adopt", &.{prepared});
    if (c.JS_ToBool(engine.context, try r.binary(&s, 6, try s.get(try s.get(prepared, "ops"), "length"), c.JS_NewInt32(engine.context, 0))) != 0) _ = try h.invoke(&s, try s.get(owned, "publisher"), "publish", &.{ try s.get(prepared, "value"), h.arg(args, 0) });
    return c.pi_js_undefined();
}
fn construct(engine: *h.Engine, target: c.JSValue, args: []const c.JSValue, captures: []const c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    const state = try s.keep(try h.allocate(engine, target, captures[0], .ReplicatedMutable));
    const owned = try r.own(&s, state, captures[0], .ReplicatedMutable);
    const tracker = try s.keep(try @import("native_chord_delta_tracker.zig").track(engine, h.arg(args, 0)));
    try h.field(&s, owned, "tracker", tracker);
    try h.field(&s, owned, "publisher", try h.construct(&s, captures[0], "ReplicatedStatePublisher", &.{try s.get(tracker, "value")}));
    try h.field(&s, owned, "changing", c.pi_js_bool(engine.context, 0));
    return s.result(state);
}
pub fn install(engine: *h.Engine, bindings: c.JSValue) !void {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    try h.register(&s, bindings, .ReplicatedMutable);
    const prototype = try s.record();
    try js.define(engine, bindings, "MutableReplicatedStateImpl", try @import("native_class.zig").constructor(engine, "MutableReplicatedStateImpl", 1, prototype, construct, &.{bindings}));
    inline for (.{ .{ "value", Method.value, 0, true }, .{ "change", Method.change, 2, false }, .{ "replace", Method.replace, 2, false }, .{ "subscribe", Method.subscribe, 1, false } }) |item| try h.define(&s, prototype, bindings, item[0], callback, @intFromEnum(item[1]), item[2], item[3], false);
}
