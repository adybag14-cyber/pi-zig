//! Direct native bodies from pinned typebox@1.3.27. Source-only pending qualification.
const js = @import("native_js_values.zig");
const Scope = @import("native_sdk_prompt_scope.zig").Scope;
const o = @import("native_typebox_compile_ops.zig");
const ordinary = @import("native_legacy_function.zig");
const class = @import("native_class.zig");
const sdk = @import("native_sdk.zig");
const c = js.c;
const Engine = js.Engine;
pub fn prepare(e: *Engine, graph: c.JSValue) !void {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const modules = try s.get(graph, "modules");
    const namespace = try s.get(modules, "schema/check.mjs");
    const frame = try o.frame(&s, c.pi_js_null());
    try s.put(frame, "@this", c.pi_js_undefined());
    try s.put(try s.get(graph, "frames"), "schema/check.mjs", frame);
    const bindings = try s.object();
    try s.put(try s.get(graph, "bindings"), "schema/check.mjs", bindings);
    const v3597 = try s.own(try ordinary.create(e, "Check", 0, body3530, &.{ graph, frame }));
    try o.assign(&s, frame, "binding3529", v3597);
    const v3598 = try o.lookup(&s, frame, "binding3529");
    try s.put(namespace, "Check", v3598);
    const v3599 = try o.lookup(&s, frame, "binding3529");
    try s.put(namespace, "Check", v3599);
    try s.put(bindings, "Check", try s.text("binding3529"));
}
fn body3549(e: *Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    _ = roots[0];
    const frame = try o.frame(&s, roots[1]);
    _ = try o.lookup(&s, frame, "@this");
    const v3554 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding3551", v3554);
    const v3555 = if (args.len > 1) args[1] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding3552", v3555);
    const v3556 = if (args.len > 2) args[2] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding3553", v3556);
    const v3557 = try s.array();
    const v3558 = try o.lookup(&s, frame, "binding3551");
    try o.append(&s, v3557, v3558);
    const v3559 = try o.lookup(&s, frame, "binding3552");
    try o.append(&s, v3557, v3559);
    const v3560 = try o.lookup(&s, frame, "binding3553");
    try o.append(&s, v3557, v3560);
    return c.JS_DupValue(e.context, v3557);
}
fn body3549C(ctx: ?*c.JSContext, receiver: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const e = Engine.fromContext(ctx.?);
    return body3549(e, receiver, if (argc > 0) argv[0..@intCast(argc)] else &.{}, roots[0..2]) catch |err| sdk.fail(e, err);
}
fn body3563(e: *Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    _ = roots[0];
    const frame = try o.frame(&s, roots[1]);
    _ = try o.lookup(&s, frame, "@this");
    const v3567 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding3565", v3567);
    const v3568 = if (args.len > 1) args[1] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding3566", v3568);
    const v3569 = try s.array();
    const v3570 = try s.object();
    try o.append(&s, v3569, v3570);
    const v3571 = try o.lookup(&s, frame, "binding3565");
    try o.append(&s, v3569, v3571);
    const v3572 = try o.lookup(&s, frame, "binding3566");
    try o.append(&s, v3569, v3572);
    return c.JS_DupValue(e.context, v3569);
}
fn body3563C(ctx: ?*c.JSContext, receiver: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const e = Engine.fromContext(ctx.?);
    return body3563(e, receiver, if (argc > 0) argv[0..@intCast(argc)] else &.{}, roots[0..2]) catch |err| sdk.fail(e, err);
}
fn body3530(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v3537 = try o.rest(&s, args, 0);
    try o.assign(&s, frame, "binding3531", v3537);
    const v3543 = try o.importValue(&s, graph, "system/arguments/index.mjs", "Arguments");
    const v3544 = try s.text("Match");
    const v3545 = try s.own(try js.getKey(e, v3543, v3544));
    const v3546 = try o.lookup(&s, frame, "binding3531");
    const v3547 = try s.object();
    const v3548 = try s.text("3");
    const v3561 = try o.arrow(&s, "3", 3, body3549C, &.{ graph, frame });
    try o.defineKey(&s, v3547, v3548, v3561);
    const v3562 = try s.text("2");
    const v3573 = try o.arrow(&s, "2", 2, body3563C, &.{ graph, frame });
    try o.defineKey(&s, v3547, v3562, v3573);
    const v3574 = try s.call(v3545, v3543, &.{ v3546, v3547 });
    var destructure3575 = try o.iterator(e, v3574);
    defer destructure3575.deinit();
    errdefer destructure3575.closePreserving();
    const v3576 = try s.own(if (destructure3575.closed) c.pi_js_undefined() else (try destructure3575.next()) orelse c.pi_js_undefined());
    try o.assign(&s, frame, "binding3538", v3576);
    const v3577 = try s.own(if (destructure3575.closed) c.pi_js_undefined() else (try destructure3575.next()) orelse c.pi_js_undefined());
    try o.assign(&s, frame, "binding3539", v3577);
    const v3578 = try s.own(if (destructure3575.closed) c.pi_js_undefined() else (try destructure3575.next()) orelse c.pi_js_undefined());
    try o.assign(&s, frame, "binding3540", v3578);
    try destructure3575.close();
    const v3579 = try o.importValue(&s, graph, "schema/engine/index.mjs", "*");
    const v3580 = try s.text("Stack");
    const v3581 = try s.own(try js.getKey(e, v3579, v3580));
    const v3582 = try o.lookup(&s, frame, "binding3538");
    const v3583 = try o.lookup(&s, frame, "binding3539");
    const v3584 = try o.construct(&s, v3581, &.{ v3582, v3583 });
    try o.assign(&s, frame, "binding3541", v3584);
    const v3585 = try o.importValue(&s, graph, "schema/engine/index.mjs", "*");
    const v3586 = try s.text("CheckContext");
    const v3587 = try s.own(try js.getKey(e, v3585, v3586));
    const v3588 = try o.construct(&s, v3587, &.{});
    try o.assign(&s, frame, "binding3542", v3588);
    const v3589 = try o.importValue(&s, graph, "schema/engine/index.mjs", "*");
    const v3590 = try s.text("CheckSchema");
    const v3591 = try s.own(try js.getKey(e, v3589, v3590));
    const v3592 = try o.lookup(&s, frame, "binding3541");
    const v3593 = try o.lookup(&s, frame, "binding3542");
    const v3594 = try o.lookup(&s, frame, "binding3539");
    const v3595 = try o.lookup(&s, frame, "binding3540");
    const v3596 = try s.call(v3591, v3589, &.{ v3592, v3593, v3594, v3595 });
    return c.JS_DupValue(e.context, v3596);
}
