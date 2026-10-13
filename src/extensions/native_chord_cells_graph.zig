//! Actual transitive dependency walk and Source-sequence candidate recomputation.
const h = @import("native_chord_host_values.zig");
const Scope = h.Scope;
const js = h.js;
const c = h.c;
const Walker = struct {
    scope: *Scope,
    pending: c.JSValue,
    steps: usize = 0,
    fn visit(self: *Walker, source: c.JSValue) anyerror!void {
        const s = self.scope;
        self.steps +|= 1;
        if (s.engine.cancelled.load(.acquire) or (self.steps % 256 == 0 and blk: {
            s.engine.interrupts +|= 1;
            break :blk s.engine.interrupts > s.engine.options.interrupt_budget;
        })) _ = try s.engine.checked(c.JS_ThrowInternalError(s.engine.context, "interrupted"));
        const symbol = try h.iteratorSymbol(s);
        var iterator = try js.Iterator.init(s.engine, try s.get(source, "dependents"), symbol);
        defer iterator.deinit();
        errdefer iterator.closePreserving();
        while (try iterator.next()) |derived| {
            defer s.engine.freeValue(derived);
            if (c.JS_ToBool(s.engine.context, try h.invoke(s, self.pending, "has", &.{derived})) != 0) continue;
            _ = try h.invoke(s, self.pending, "add", &.{derived});
            try self.visit(derived);
        }
    }
};
fn order(ctx: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, _: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = h.Engine.fromContext(ctx.?);
    return compare(engine, if (argc > 0) argv[0..@intCast(argc)] else &.{}) catch |err| @import("native_durable.zig").reject(engine, err);
}
fn compare(engine: *h.Engine, args: []const c.JSValue) !c.JSValue {
    const left = try js.get(engine, h.arg(args, 0), "seq");
    defer engine.freeValue(left);
    const right = try js.get(engine, h.arg(args, 1), "seq");
    defer engine.freeValue(right);
    var a: f64 = 0;
    var b: f64 = 0;
    if (c.JS_ToFloat64(engine.context, &a, left) < 0 or c.JS_ToFloat64(engine.context, &b, right) < 0) return js.capture(engine);
    return c.JS_NewFloat64(engine.context, a - b);
}
fn read(ctx: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, captures: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = h.Engine.fromContext(ctx.?);
    return selected(engine, captures[0], if (argc > 0) argv[0] else c.pi_js_undefined()) catch |err| @import("native_durable.zig").reject(engine, err);
}
fn selected(engine: *h.Engine, values: c.JSValue, source: c.JSValue) !c.JSValue {
    const present = try js.invoke(engine, values, "has", &.{source});
    defer engine.freeValue(present);
    return if (c.JS_ToBool(engine.context, present) != 0) js.invoke(engine, values, "get", &.{source}) else js.get(engine, source, "value");
}
pub fn compute(s: *Scope, changed: c.JSValue, value: c.JSValue, validate: bool) !c.JSValue {
    const pending = try h.set(s);
    var walker: Walker = .{ .scope = s, .pending = pending };
    try walker.visit(changed);
    const values = try h.map(s);
    _ = try h.invoke(s, values, "set", &.{ changed, value });
    const result = try h.map(s);
    const ordered = try h.snapshot(s, pending);
    const comparator = try s.keep(try s.engine.checked(c.JS_NewCFunctionData2(s.engine.context, order, "", 2, 0, 0, null)));
    _ = try h.invoke(s, ordered, "sort", &.{comparator});
    var captures = [_]c.JSValue{values};
    const reader = try s.keep(try s.engine.checked(c.JS_NewCFunctionData2(s.engine.context, read, "", 1, 0, 1, &captures)));
    for (0..try h.length(s, ordered)) |index| {
        const derived = try s.at(ordered, index);
        const next = try h.invoke(s, derived, "compute", &.{reader});
        if (validate) _ = try h.invoke(s, derived, "validate", &.{next});
        _ = try h.invoke(s, values, "set", &.{ derived, next });
        _ = try h.invoke(s, result, "set", &.{ derived, next });
    }
    return result;
}
pub fn install(s: *Scope, candidates: c.JSValue) !void {
    const symbol = try h.iteratorSymbol(s);
    var iterator = try js.Iterator.init(s.engine, candidates, symbol);
    defer iterator.deinit();
    errdefer iterator.closePreserving();
    while (try iterator.next()) |entry| {
        defer s.engine.freeValue(entry);
        _ = try h.invoke(s, try s.at(entry, 0), "install", &.{try s.at(entry, 1)});
    }
}
