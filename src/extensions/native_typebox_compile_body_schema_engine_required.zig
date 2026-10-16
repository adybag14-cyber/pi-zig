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
    const namespace = try s.get(modules, "schema/engine/required.mjs");
    const frame = try o.frame(&s, c.pi_js_null());
    try s.put(frame, "@this", c.pi_js_undefined());
    try s.put(try s.get(graph, "frames"), "schema/engine/required.mjs", frame);
    const bindings = try s.object();
    try s.put(try s.get(graph, "bindings"), "schema/engine/required.mjs", bindings);
    const v13627 = try s.own(try ordinary.create(e, "BuildRequired", 4, body13593, &.{ graph, frame }));
    try o.assign(&s, frame, "binding13590", v13627);
    const v13655 = try s.own(try ordinary.create(e, "CheckRequired", 4, body13628, &.{ graph, frame }));
    try o.assign(&s, frame, "binding13591", v13655);
    const v13719 = try s.own(try ordinary.create(e, "ErrorRequired", 6, body13656, &.{ graph, frame }));
    try o.assign(&s, frame, "binding13592", v13719);
    const v13720 = try o.lookup(&s, frame, "binding13590");
    try s.put(namespace, "BuildRequired", v13720);
    const v13721 = try o.lookup(&s, frame, "binding13591");
    try s.put(namespace, "CheckRequired", v13721);
    const v13722 = try o.lookup(&s, frame, "binding13592");
    try s.put(namespace, "ErrorRequired", v13722);
    const v13723 = try o.lookup(&s, frame, "binding13590");
    try s.put(namespace, "BuildRequired", v13723);
    const v13724 = try o.lookup(&s, frame, "binding13591");
    try s.put(namespace, "CheckRequired", v13724);
    const v13725 = try o.lookup(&s, frame, "binding13592");
    try s.put(namespace, "ErrorRequired", v13725);
    try s.put(bindings, "BuildRequired", try s.text("binding13590"));
    try s.put(bindings, "CheckRequired", try s.text("binding13591"));
    try s.put(bindings, "ErrorRequired", try s.text("binding13592"));
}
fn body13610(e: *Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    _ = try o.lookup(&s, frame, "@this");
    const v13613 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding13612", v13613);
    const v13614 = try o.importValue(&s, graph, "guard/index.mjs", "EmitGuard");
    const v13615 = try s.text("HasPropertyKey");
    const v13616 = try s.own(try js.getKey(e, v13614, v13615));
    const v13617 = try o.lookup(&s, frame, "binding13597");
    const v13618 = try o.importValue(&s, graph, "guard/index.mjs", "EmitGuard");
    const v13619 = try s.text("Constant");
    const v13620 = try s.own(try js.getKey(e, v13618, v13619));
    const v13621 = try o.lookup(&s, frame, "binding13612");
    const v13622 = try s.call(v13620, v13618, &.{v13621});
    const v13623 = try s.call(v13616, v13614, &.{ v13617, v13622 });
    return c.JS_DupValue(e.context, v13623);
}
fn body13610C(ctx: ?*c.JSContext, receiver: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const e = Engine.fromContext(ctx.?);
    return body13610(e, receiver, if (argc > 0) argv[0..@intCast(argc)] else &.{}, roots[0..2]) catch |err| sdk.fail(e, err);
}
fn body13593(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v13598 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding13594", v13598);
    const v13599 = if (args.len > 1) args[1] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding13595", v13599);
    const v13600 = if (args.len > 2) args[2] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding13596", v13600);
    const v13601 = if (args.len > 3) args[3] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding13597", v13601);
    const v13602 = try o.importValue(&s, graph, "guard/index.mjs", "EmitGuard");
    const v13603 = try s.text("ReduceAnd");
    const v13604 = try s.own(try js.getKey(e, v13602, v13603));
    const v13605 = try o.lookup(&s, frame, "binding13596");
    const v13606 = try s.text("required");
    const v13607 = try s.own(try js.getKey(e, v13605, v13606));
    const v13608 = try s.text("map");
    const v13609 = try s.own(try js.getKey(e, v13607, v13608));
    const v13624 = try o.arrow(&s, "", 1, body13610C, &.{ graph, frame });
    const v13625 = try s.call(v13609, v13607, &.{v13624});
    const v13626 = try s.call(v13604, v13602, &.{v13625});
    return c.JS_DupValue(e.context, v13626);
}
fn body13643(e: *Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    _ = try o.lookup(&s, frame, "@this");
    const v13646 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding13645", v13646);
    const v13647 = try o.importValue(&s, graph, "guard/index.mjs", "Guard");
    const v13648 = try s.text("HasPropertyKey");
    const v13649 = try s.own(try js.getKey(e, v13647, v13648));
    const v13650 = try o.lookup(&s, frame, "binding13632");
    const v13651 = try o.lookup(&s, frame, "binding13645");
    const v13652 = try s.call(v13649, v13647, &.{ v13650, v13651 });
    return c.JS_DupValue(e.context, v13652);
}
fn body13643C(ctx: ?*c.JSContext, receiver: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const e = Engine.fromContext(ctx.?);
    return body13643(e, receiver, if (argc > 0) argv[0..@intCast(argc)] else &.{}, roots[0..2]) catch |err| sdk.fail(e, err);
}
fn body13628(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v13633 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding13629", v13633);
    const v13634 = if (args.len > 1) args[1] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding13630", v13634);
    const v13635 = if (args.len > 2) args[2] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding13631", v13635);
    const v13636 = if (args.len > 3) args[3] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding13632", v13636);
    const v13637 = try o.importValue(&s, graph, "guard/index.mjs", "Guard");
    const v13638 = try s.text("Every");
    const v13639 = try s.own(try js.getKey(e, v13637, v13638));
    const v13640 = try o.lookup(&s, frame, "binding13631");
    const v13641 = try s.text("required");
    const v13642 = try s.own(try js.getKey(e, v13640, v13641));
    const v13653 = try o.arrow(&s, "", 1, body13643C, &.{ graph, frame });
    const v13654 = try s.call(v13639, v13637, &.{ v13642, c.JS_NewFloat64(e.context, 0), v13653 });
    return c.JS_DupValue(e.context, v13654);
}
fn body13680(e: *Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    _ = try o.lookup(&s, frame, "@this");
    const v13684 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding13682", v13684);
    const v13686 = try o.importValue(&s, graph, "guard/index.mjs", "Guard");
    const v13687 = try s.text("HasPropertyKey");
    const v13688 = try s.own(try js.getKey(e, v13686, v13687));
    const v13689 = try o.lookup(&s, frame, "binding13662");
    const v13690 = try o.lookup(&s, frame, "binding13682");
    const v13691 = try s.call(v13688, v13686, &.{ v13689, v13690 });
    try o.assign(&s, frame, "binding13685", v13691);
    const v13692 = try o.lookup(&s, frame, "binding13685");
    if (s.truthy(o.boolean(&s, !s.truthy(v13692)))) {
        const v13693 = try o.lookup(&s, frame, "binding13671");
        const v13694 = try s.text("push");
        const v13695 = try s.own(try js.getKey(e, v13693, v13694));
        const v13696 = try o.lookup(&s, frame, "binding13682");
        const v13697 = try s.call(v13695, v13693, &.{v13696});
        _ = v13697;
    }
    const v13698 = try o.lookup(&s, frame, "binding13685");
    return c.JS_DupValue(e.context, v13698);
}
fn body13680C(ctx: ?*c.JSContext, receiver: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const e = Engine.fromContext(ctx.?);
    return body13680(e, receiver, if (argc > 0) argv[0..@intCast(argc)] else &.{}, roots[0..2]) catch |err| sdk.fail(e, err);
}
fn body13656(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v13665 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding13657", v13665);
    const v13666 = if (args.len > 1) args[1] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding13658", v13666);
    const v13667 = if (args.len > 2) args[2] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding13659", v13667);
    const v13668 = if (args.len > 3) args[3] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding13660", v13668);
    const v13669 = if (args.len > 4) args[4] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding13661", v13669);
    const v13670 = if (args.len > 5) args[5] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding13662", v13670);
    const v13673 = try s.array();
    try o.assign(&s, frame, "binding13671", v13673);
    const v13674 = try o.importValue(&s, graph, "guard/index.mjs", "Guard");
    const v13675 = try s.text("EveryAll");
    const v13676 = try s.own(try js.getKey(e, v13674, v13675));
    const v13677 = try o.lookup(&s, frame, "binding13661");
    const v13678 = try s.text("required");
    const v13679 = try s.own(try js.getKey(e, v13677, v13678));
    const v13699 = try o.arrow(&s, "", 1, body13680C, &.{ graph, frame });
    const v13700 = try s.call(v13676, v13674, &.{ v13679, c.JS_NewFloat64(e.context, 0), v13699 });
    try o.assign(&s, frame, "binding13672", v13700);
    const v13701 = try o.lookup(&s, frame, "binding13672");
    const v13703 = logical13702: {
        if (s.truthy(v13701)) break :logical13702 v13701;
        const v13704 = try o.lookup(&s, frame, "binding13658");
        const v13705 = try s.text("AddError");
        const v13706 = try s.own(try js.getKey(e, v13704, v13705));
        const v13707 = try s.object();
        const v13708 = try s.text("keyword");
        const v13709 = try s.text("required");
        try o.defineKey(&s, v13707, v13708, v13709);
        const v13710 = try s.text("schemaPath");
        const v13711 = try o.lookup(&s, frame, "binding13659");
        try o.defineKey(&s, v13707, v13710, v13711);
        const v13712 = try s.text("instancePath");
        const v13713 = try o.lookup(&s, frame, "binding13660");
        try o.defineKey(&s, v13707, v13712, v13713);
        const v13714 = try s.text("params");
        const v13715 = try s.object();
        const v13716 = try s.text("requiredProperties");
        const v13717 = try o.lookup(&s, frame, "binding13671");
        try o.defineKey(&s, v13715, v13716, v13717);
        try o.defineKey(&s, v13707, v13714, v13715);
        const v13718 = try s.call(v13706, v13704, &.{v13707});
        break :logical13702 v13718;
    };
    return c.JS_DupValue(e.context, v13703);
}
