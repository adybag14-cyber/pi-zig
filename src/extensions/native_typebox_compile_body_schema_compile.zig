//! Direct native bodies from pinned typebox@1.3.27. Source-only pending qualification.
const js = @import("native_js_values.zig");
const Scope = @import("native_sdk_prompt_scope.zig").Scope;
const o = @import("native_typebox_compile_ops.zig");
const ordinary = @import("native_node_function.zig");
const class = @import("native_class.zig");
const sdk = @import("native_sdk.zig");
const c = js.c;
const Engine = js.Engine;
pub fn prepare(e: *Engine, graph: c.JSValue) !void {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const modules = try s.get(graph, "modules");
    const namespace = try s.get(modules, "schema/compile.mjs");
    const frame = try o.frame(&s, c.pi_js_null());
    try s.put(frame, "@this", c.pi_js_undefined());
    try s.put(try s.get(graph, "frames"), "schema/compile.mjs", frame);
    const bindings = try s.object();
    try s.put(try s.get(graph, "bindings"), "schema/compile.mjs", bindings);
    const v3642 = try s.own(try ordinary.create(e, "Compile", 0, body3602, &.{ graph, frame }));
    try o.assign(&s, frame, "binding3601", v3642);
    const v3643 = try o.lookup(&s, frame, "binding3601");
    try s.put(namespace, "Compile", v3643);
    const v3644 = try s.object();
    const v3664 = try s.own(try class.constructor(e, "Validator", 2, v3644, constructor3645, &.{ graph, frame, c.pi_js_undefined() }));
    const v3671 = try o.arrow(&s, "IsAccelerated", 0, body3665C, &.{ graph, frame });
    try o.method(&s, v3644, "IsAccelerated", v3671);
    const v3675 = try o.arrow(&s, "Schema", 0, body3672C, &.{ graph, frame });
    try o.method(&s, v3644, "Schema", v3675);
    const v3685 = try o.arrow(&s, "Check", 1, body3676C, &.{ graph, frame });
    try o.method(&s, v3644, "Check", v3685);
    const v3703 = try o.arrow(&s, "Parse", 1, body3686C, &.{ graph, frame });
    try o.method(&s, v3644, "Parse", v3703);
    const v3714 = try o.arrow(&s, "Errors", 1, body3704C, &.{ graph, frame });
    try o.method(&s, v3644, "Errors", v3714);
    try o.assign(&s, frame, "binding3600", v3664);
    const v3715 = try o.lookup(&s, frame, "binding3601");
    try s.put(namespace, "Compile", v3715);
    const v3716 = try o.lookup(&s, frame, "binding3600");
    try s.put(namespace, "Validator", v3716);
    try s.put(bindings, "Compile", try s.text("binding3601"));
    try s.put(bindings, "Validator", try s.text("binding3600"));
}
fn body3615(e: *Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    _ = roots[0];
    const frame = try o.frame(&s, roots[1]);
    _ = try o.lookup(&s, frame, "@this");
    const v3619 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding3617", v3619);
    const v3620 = if (args.len > 1) args[1] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding3618", v3620);
    const v3621 = try s.array();
    const v3622 = try o.lookup(&s, frame, "binding3617");
    try o.append(&s, v3621, v3622);
    const v3623 = try o.lookup(&s, frame, "binding3618");
    try o.append(&s, v3621, v3623);
    return c.JS_DupValue(e.context, v3621);
}
fn body3615C(ctx: ?*c.JSContext, receiver: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const e = Engine.fromContext(ctx.?);
    return body3615(e, receiver, if (argc > 0) argv[0..@intCast(argc)] else &.{}, roots[0..2]) catch |err| sdk.fail(e, err);
}
fn body3626(e: *Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    _ = roots[0];
    const frame = try o.frame(&s, roots[1]);
    _ = try o.lookup(&s, frame, "@this");
    const v3629 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding3628", v3629);
    const v3630 = try s.array();
    const v3631 = try s.object();
    try o.append(&s, v3630, v3631);
    const v3632 = try o.lookup(&s, frame, "binding3628");
    try o.append(&s, v3630, v3632);
    return c.JS_DupValue(e.context, v3630);
}
fn body3626C(ctx: ?*c.JSContext, receiver: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const e = Engine.fromContext(ctx.?);
    return body3626(e, receiver, if (argc > 0) argv[0..@intCast(argc)] else &.{}, roots[0..2]) catch |err| sdk.fail(e, err);
}
fn body3602(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v3606 = try o.rest(&s, args, 0);
    try o.assign(&s, frame, "binding3603", v3606);
    const v3609 = try o.importValue(&s, graph, "system/arguments/index.mjs", "Arguments");
    const v3610 = try s.text("Match");
    const v3611 = try s.own(try js.getKey(e, v3609, v3610));
    const v3612 = try o.lookup(&s, frame, "binding3603");
    const v3613 = try s.object();
    const v3614 = try s.text("2");
    const v3624 = try o.arrow(&s, "2", 2, body3615C, &.{ graph, frame });
    try o.defineKey(&s, v3613, v3614, v3624);
    const v3625 = try s.text("1");
    const v3633 = try o.arrow(&s, "1", 1, body3626C, &.{ graph, frame });
    try o.defineKey(&s, v3613, v3625, v3633);
    const v3634 = try o.call(&s, @src(), v3611, v3609, &.{ v3612, v3613 });
    var destructure3635 = try o.iterator(e, v3634);
    defer destructure3635.deinit();
    errdefer destructure3635.closePreserving();
    const v3636 = try s.own(if (destructure3635.closed) c.pi_js_undefined() else (try destructure3635.next()) orelse c.pi_js_undefined());
    try o.assign(&s, frame, "binding3607", v3636);
    const v3637 = try s.own(if (destructure3635.closed) c.pi_js_undefined() else (try destructure3635.next()) orelse c.pi_js_undefined());
    try o.assign(&s, frame, "binding3608", v3637);
    try destructure3635.close();
    const v3638 = try o.lookup(&s, frame, "binding3600");
    const v3639 = try o.lookup(&s, frame, "binding3607");
    const v3640 = try o.lookup(&s, frame, "binding3608");
    const v3641 = try o.construct(&s, v3638, &.{ v3639, v3640 });
    return c.JS_DupValue(e.context, v3641);
}
fn constructor3645(e: *Engine, target: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    const v3648 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding3646", v3648);
    const v3649 = if (args.len > 1) args[1] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding3647", v3649);
    const receiver = try s.own(try class.object(e, target));
    try s.put(frame, "@this", receiver);
    const v3650 = try s.text("evaluateResult");
    const v3651 = try o.importValue(&s, graph, "schema/build.mjs", "*");
    const v3652 = try s.text("Build");
    const v3653 = try s.own(try js.getKey(e, v3651, v3652));
    const v3654 = try o.lookup(&s, frame, "binding3646");
    const v3655 = try o.lookup(&s, frame, "binding3647");
    const v3656 = try o.call(&s, @src(), v3653, v3651, &.{ v3654, v3655 });
    const v3657 = try s.text("Evaluate");
    const v3658 = try s.own(try js.getKey(e, v3656, v3657));
    const v3659 = try o.call(&s, @src(), v3658, v3656, &.{});
    try js.setKey(e, receiver, v3650, v3659);
    const v3660 = try s.text("context");
    const v3661 = try o.lookup(&s, frame, "binding3646");
    try js.setKey(e, receiver, v3660, v3661);
    const v3662 = try s.text("schema");
    const v3663 = try o.lookup(&s, frame, "binding3647");
    try js.setKey(e, receiver, v3662, v3663);
    return c.JS_DupValue(e.context, receiver);
}
fn body3665(e: *Engine, receiver: c.JSValue, _: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    _ = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v3666 = try s.text("evaluateResult");
    const v3667 = try s.own(try js.getKey(e, receiver, v3666));
    const v3668 = try s.text("IsAccelerated");
    const v3669 = try s.own(try js.getKey(e, v3667, v3668));
    const v3670 = try o.call(&s, @src(), v3669, v3667, &.{});
    return c.JS_DupValue(e.context, v3670);
}
fn body3665C(ctx: ?*c.JSContext, receiver: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const e = Engine.fromContext(ctx.?);
    return body3665(e, receiver, if (argc > 0) argv[0..@intCast(argc)] else &.{}, roots[0..2]) catch |err| sdk.fail(e, err);
}
fn body3672(e: *Engine, receiver: c.JSValue, _: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    _ = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v3673 = try s.text("schema");
    const v3674 = try s.own(try js.getKey(e, receiver, v3673));
    return c.JS_DupValue(e.context, v3674);
}
fn body3672C(ctx: ?*c.JSContext, receiver: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const e = Engine.fromContext(ctx.?);
    return body3672(e, receiver, if (argc > 0) argv[0..@intCast(argc)] else &.{}, roots[0..2]) catch |err| sdk.fail(e, err);
}
fn body3676(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    _ = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v3678 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding3677", v3678);
    const v3679 = try s.text("evaluateResult");
    const v3680 = try s.own(try js.getKey(e, receiver, v3679));
    const v3681 = try s.text("Check");
    const v3682 = try s.own(try js.getKey(e, v3680, v3681));
    const v3683 = try o.lookup(&s, frame, "binding3677");
    const v3684 = try o.call(&s, @src(), v3682, v3680, &.{v3683});
    return c.JS_DupValue(e.context, v3684);
}
fn body3676C(ctx: ?*c.JSContext, receiver: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const e = Engine.fromContext(ctx.?);
    return body3676(e, receiver, if (argc > 0) argv[0..@intCast(argc)] else &.{}, roots[0..2]) catch |err| sdk.fail(e, err);
}
fn body3686(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v3688 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding3687", v3688);
    const v3689 = try s.text("evaluateResult");
    const v3690 = try s.own(try js.getKey(e, receiver, v3689));
    const v3691 = try s.text("Check");
    const v3692 = try s.own(try js.getKey(e, v3690, v3691));
    const v3693 = try o.lookup(&s, frame, "binding3687");
    const v3694 = try o.call(&s, @src(), v3692, v3690, &.{v3693});
    if (s.truthy(v3694)) {
        const v3695 = try o.lookup(&s, frame, "binding3687");
        return c.JS_DupValue(e.context, v3695);
    }
    const v3696 = try o.importValue(&s, graph, "schema/parse.mjs", "ThrowParseError");
    const v3697 = try s.text("context");
    const v3698 = try s.own(try js.getKey(e, receiver, v3697));
    const v3699 = try s.text("schema");
    const v3700 = try s.own(try js.getKey(e, receiver, v3699));
    const v3701 = try o.lookup(&s, frame, "binding3687");
    const v3702 = try o.call(&s, @src(), v3696, c.pi_js_undefined(), &.{ v3698, v3700, v3701 });
    _ = v3702;
    return c.pi_js_undefined();
}
fn body3686C(ctx: ?*c.JSContext, receiver: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const e = Engine.fromContext(ctx.?);
    return body3686(e, receiver, if (argc > 0) argv[0..@intCast(argc)] else &.{}, roots[0..2]) catch |err| sdk.fail(e, err);
}
fn body3704(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v3706 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding3705", v3706);
    const v3707 = try o.importValue(&s, graph, "schema/errors.mjs", "Errors");
    const v3708 = try s.text("context");
    const v3709 = try s.own(try js.getKey(e, receiver, v3708));
    const v3710 = try s.text("schema");
    const v3711 = try s.own(try js.getKey(e, receiver, v3710));
    const v3712 = try o.lookup(&s, frame, "binding3705");
    const v3713 = try o.call(&s, @src(), v3707, c.pi_js_undefined(), &.{ v3709, v3711, v3712 });
    return c.JS_DupValue(e.context, v3713);
}
fn body3704C(ctx: ?*c.JSContext, receiver: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const e = Engine.fromContext(ctx.?);
    return body3704(e, receiver, if (argc > 0) argv[0..@intCast(argc)] else &.{}, roots[0..2]) catch |err| sdk.fail(e, err);
}
