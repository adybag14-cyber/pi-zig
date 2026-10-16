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
    const namespace = try s.get(modules, "value/codec/from_intersect.mjs");
    const frame = try o.frame(&s, c.pi_js_null());
    try s.put(frame, "@this", c.pi_js_undefined());
    try s.put(try s.get(graph, "frames"), "value/codec/from_intersect.mjs", frame);
    const bindings = try s.object();
    try s.put(try s.get(graph, "bindings"), "value/codec/from_intersect.mjs", bindings);
    const v24635 = try s.own(try ordinary.create(e, "MergeInteriors", 1, body24617, &.{ graph, frame }));
    try o.assign(&s, frame, "binding24612", v24635);
    const v24655 = try s.own(try ordinary.create(e, "NonMatchingInterior", 2, body24636, &.{ graph, frame }));
    try o.assign(&s, frame, "binding24613", v24655);
    const v24738 = try s.own(try ordinary.create(e, "Decode", 4, body24656, &.{ graph, frame }));
    try o.assign(&s, frame, "binding24614", v24738);
    const v24819 = try s.own(try ordinary.create(e, "Encode", 4, body24739, &.{ graph, frame }));
    try o.assign(&s, frame, "binding24615", v24819);
    const v24849 = try s.own(try ordinary.create(e, "FromIntersect", 4, body24820, &.{ graph, frame }));
    try o.assign(&s, frame, "binding24616", v24849);
    const v24850 = try o.lookup(&s, frame, "binding24616");
    try s.put(namespace, "FromIntersect", v24850);
    const v24851 = try o.lookup(&s, frame, "binding24616");
    try s.put(namespace, "FromIntersect", v24851);
    try s.put(bindings, "FromIntersect", try s.text("binding24616"));
}
fn body24623(e: *Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    _ = roots[0];
    const frame = try o.frame(&s, roots[1]);
    _ = try o.lookup(&s, frame, "@this");
    const v24627 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding24625", v24627);
    const v24628 = if (args.len > 1) args[1] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding24626", v24628);
    const v24629 = try s.object();
    const v24630 = try o.lookup(&s, frame, "binding24625");
    try js.spreadInto(e, v24629, v24630);
    const v24631 = try o.lookup(&s, frame, "binding24626");
    try js.spreadInto(e, v24629, v24631);
    return c.JS_DupValue(e.context, v24629);
}
fn body24623C(ctx: ?*c.JSContext, receiver: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const e = Engine.fromContext(ctx.?);
    return body24623(e, receiver, if (argc > 0) argv[0..@intCast(argc)] else &.{}, roots[0..2]) catch |err| sdk.fail(e, err);
}
fn body24617(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v24619 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding24618", v24619);
    const v24620 = try o.lookup(&s, frame, "binding24618");
    const v24621 = try s.text("reduce");
    const v24622 = try s.own(try js.getKey(e, v24620, v24621));
    const v24632 = try o.arrow(&s, "", 2, body24623C, &.{ graph, frame });
    const v24633 = try s.object();
    const v24634 = try s.call(v24622, v24620, &.{ v24632, v24633 });
    return c.JS_DupValue(e.context, v24634);
}
fn body24636(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v24639 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding24637", v24639);
    const v24640 = if (args.len > 1) args[1] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding24638", v24640);
    const v24641 = try o.lookup(&s, frame, "binding24638");
    var iterator24642 = try o.iterator(e, v24641);
    defer iterator24642.deinit();
    errdefer iterator24642.closePreserving();
    while (try iterator24642.next()) |next24643| {
        defer e.freeValue(next24643);
        const iteration24645 = try o.frame(&s, frame);
        try o.assign(&s, iteration24645, "binding24646", next24643);
        const v24647 = try o.importValue(&s, graph, "guard/index.mjs", "Guard");
        const v24648 = try s.text("IsDeepEqual");
        const v24649 = try s.own(try js.getKey(e, v24647, v24648));
        const v24650 = try o.lookup(&s, iteration24645, "binding24637");
        const v24651 = try o.lookup(&s, iteration24645, "binding24646");
        const v24652 = try s.call(v24649, v24647, &.{ v24650, v24651 });
        if (s.truthy(o.boolean(&s, !s.truthy(v24652)))) {
            const v24653 = try o.lookup(&s, iteration24645, "binding24646");
            try iterator24642.close();
            return c.JS_DupValue(e.context, v24653);
        }
    }
    try iterator24642.close();
    const v24654 = try o.lookup(&s, frame, "binding24637");
    return c.JS_DupValue(e.context, v24654);
}
fn body24691(e: *Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    _ = try o.lookup(&s, frame, "@this");
    const v24694 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding24693", v24694);
    const v24695 = try o.importValue(&s, graph, "value/codec/from_type.mjs", "FromType");
    const v24696 = try o.lookup(&s, frame, "binding24657");
    const v24697 = try o.lookup(&s, frame, "binding24658");
    const v24698 = try o.lookup(&s, frame, "binding24693");
    const v24699 = try o.importValue(&s, graph, "value/clean/index.mjs", "Clean");
    const v24700 = try o.lookup(&s, frame, "binding24693");
    const v24701 = try o.importValue(&s, graph, "value/clone/index.mjs", "Clone");
    const v24702 = try o.lookup(&s, frame, "binding24660");
    const v24703 = try s.call(v24701, c.pi_js_undefined(), &.{v24702});
    const v24704 = try s.call(v24699, c.pi_js_undefined(), &.{ v24700, v24703 });
    const v24705 = try s.call(v24695, c.pi_js_undefined(), &.{ v24696, v24697, v24698, v24704 });
    return c.JS_DupValue(e.context, v24705);
}
fn body24691C(ctx: ?*c.JSContext, receiver: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const e = Engine.fromContext(ctx.?);
    return body24691(e, receiver, if (argc > 0) argv[0..@intCast(argc)] else &.{}, roots[0..2]) catch |err| sdk.fail(e, err);
}
fn body24711(e: *Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    _ = try o.lookup(&s, frame, "@this");
    const v24714 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding24713", v24714);
    const v24715 = try o.importValue(&s, graph, "guard/index.mjs", "Guard");
    const v24716 = try s.text("IsObject");
    const v24717 = try s.own(try js.getKey(e, v24715, v24716));
    const v24718 = try o.lookup(&s, frame, "binding24713");
    const v24719 = try s.call(v24717, v24715, &.{v24718});
    return c.JS_DupValue(e.context, v24719);
}
fn body24711C(ctx: ?*c.JSContext, receiver: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const e = Engine.fromContext(ctx.?);
    return body24711(e, receiver, if (argc > 0) argv[0..@intCast(argc)] else &.{}, roots[0..2]) catch |err| sdk.fail(e, err);
}
fn body24656(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v24664 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding24657", v24664);
    const v24665 = if (args.len > 1) args[1] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding24658", v24665);
    const v24666 = if (args.len > 2) args[2] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding24659", v24666);
    const v24667 = if (args.len > 3) args[3] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding24660", v24667);
    const v24671 = try o.importValue(&s, graph, "guard/index.mjs", "Guard");
    const v24672 = try s.text("IsEqual");
    const v24673 = try s.own(try js.getKey(e, v24671, v24672));
    const v24674 = try o.lookup(&s, frame, "binding24659");
    const v24675 = try s.text("allOf");
    const v24676 = try s.own(try js.getKey(e, v24674, v24675));
    const v24677 = try s.text("length");
    const v24678 = try s.own(try js.getKey(e, v24676, v24677));
    const v24679 = try s.call(v24673, v24671, &.{ v24678, c.JS_NewFloat64(e.context, 0) });
    if (s.truthy(v24679)) {
        const v24680 = try o.importValue(&s, graph, "value/codec/callback.mjs", "Callback");
        const v24681 = try o.lookup(&s, frame, "binding24657");
        const v24682 = try o.lookup(&s, frame, "binding24658");
        const v24683 = try o.lookup(&s, frame, "binding24659");
        const v24684 = try o.lookup(&s, frame, "binding24660");
        const v24685 = try s.call(v24680, c.pi_js_undefined(), &.{ v24681, v24682, v24683, v24684 });
        return c.JS_DupValue(e.context, v24685);
    }
    const v24686 = try o.lookup(&s, frame, "binding24659");
    const v24687 = try s.text("allOf");
    const v24688 = try s.own(try js.getKey(e, v24686, v24687));
    const v24689 = try s.text("map");
    const v24690 = try s.own(try js.getKey(e, v24688, v24689));
    const v24706 = try o.arrow(&s, "", 1, body24691C, &.{ graph, frame });
    const v24707 = try s.call(v24690, v24688, &.{v24706});
    try o.assign(&s, frame, "binding24668", v24707);
    const v24708 = try o.lookup(&s, frame, "binding24668");
    const v24709 = try s.text("every");
    const v24710 = try s.own(try js.getKey(e, v24708, v24709));
    const v24720 = try o.arrow(&s, "", 1, body24711C, &.{ graph, frame });
    const v24721 = try s.call(v24710, v24708, &.{v24720});
    try o.assign(&s, frame, "binding24669", v24721);
    const v24722 = try o.lookup(&s, frame, "binding24669");
    const v24724 = conditional24723: {
        if (s.truthy(v24722)) {
            const v24725 = try o.lookup(&s, frame, "binding24612");
            const v24726 = try o.lookup(&s, frame, "binding24668");
            const v24727 = try s.call(v24725, c.pi_js_undefined(), &.{v24726});
            break :conditional24723 v24727;
        } else {
            const v24728 = try o.lookup(&s, frame, "binding24613");
            const v24729 = try o.lookup(&s, frame, "binding24660");
            const v24730 = try o.lookup(&s, frame, "binding24668");
            const v24731 = try s.call(v24728, c.pi_js_undefined(), &.{ v24729, v24730 });
            break :conditional24723 v24731;
        }
    };
    try o.assign(&s, frame, "binding24670", v24724);
    const v24732 = try o.importValue(&s, graph, "value/codec/callback.mjs", "Callback");
    const v24733 = try o.lookup(&s, frame, "binding24657");
    const v24734 = try o.lookup(&s, frame, "binding24658");
    const v24735 = try o.lookup(&s, frame, "binding24659");
    const v24736 = try o.lookup(&s, frame, "binding24670");
    const v24737 = try s.call(v24732, c.pi_js_undefined(), &.{ v24733, v24734, v24735, v24736 });
    return c.JS_DupValue(e.context, v24737);
}
fn body24780(e: *Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    _ = try o.lookup(&s, frame, "@this");
    const v24783 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding24782", v24783);
    const v24784 = try o.importValue(&s, graph, "value/codec/from_type.mjs", "FromType");
    const v24785 = try o.lookup(&s, frame, "binding24740");
    const v24786 = try o.lookup(&s, frame, "binding24741");
    const v24787 = try o.lookup(&s, frame, "binding24782");
    const v24788 = try o.importValue(&s, graph, "value/clean/index.mjs", "Clean");
    const v24789 = try o.lookup(&s, frame, "binding24782");
    const v24790 = try o.importValue(&s, graph, "value/clone/index.mjs", "Clone");
    const v24791 = try o.lookup(&s, frame, "binding24751");
    const v24792 = try s.call(v24790, c.pi_js_undefined(), &.{v24791});
    const v24793 = try s.call(v24788, c.pi_js_undefined(), &.{ v24789, v24792 });
    const v24794 = try s.call(v24784, c.pi_js_undefined(), &.{ v24785, v24786, v24787, v24793 });
    return c.JS_DupValue(e.context, v24794);
}
fn body24780C(ctx: ?*c.JSContext, receiver: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const e = Engine.fromContext(ctx.?);
    return body24780(e, receiver, if (argc > 0) argv[0..@intCast(argc)] else &.{}, roots[0..2]) catch |err| sdk.fail(e, err);
}
fn body24800(e: *Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    _ = try o.lookup(&s, frame, "@this");
    const v24803 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding24802", v24803);
    const v24804 = try o.importValue(&s, graph, "guard/index.mjs", "Guard");
    const v24805 = try s.text("IsObject");
    const v24806 = try s.own(try js.getKey(e, v24804, v24805));
    const v24807 = try o.lookup(&s, frame, "binding24802");
    const v24808 = try s.call(v24806, v24804, &.{v24807});
    return c.JS_DupValue(e.context, v24808);
}
fn body24800C(ctx: ?*c.JSContext, receiver: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const e = Engine.fromContext(ctx.?);
    return body24800(e, receiver, if (argc > 0) argv[0..@intCast(argc)] else &.{}, roots[0..2]) catch |err| sdk.fail(e, err);
}
fn body24739(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v24747 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding24740", v24747);
    const v24748 = if (args.len > 1) args[1] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding24741", v24748);
    const v24749 = if (args.len > 2) args[2] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding24742", v24749);
    const v24750 = if (args.len > 3) args[3] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding24743", v24750);
    const v24754 = try o.importValue(&s, graph, "guard/index.mjs", "Guard");
    const v24755 = try s.text("IsEqual");
    const v24756 = try s.own(try js.getKey(e, v24754, v24755));
    const v24757 = try o.lookup(&s, frame, "binding24742");
    const v24758 = try s.text("allOf");
    const v24759 = try s.own(try js.getKey(e, v24757, v24758));
    const v24760 = try s.text("length");
    const v24761 = try s.own(try js.getKey(e, v24759, v24760));
    const v24762 = try s.call(v24756, v24754, &.{ v24761, c.JS_NewFloat64(e.context, 0) });
    if (s.truthy(v24762)) {
        const v24763 = try o.importValue(&s, graph, "value/codec/callback.mjs", "Callback");
        const v24764 = try o.lookup(&s, frame, "binding24740");
        const v24765 = try o.lookup(&s, frame, "binding24741");
        const v24766 = try o.lookup(&s, frame, "binding24742");
        const v24767 = try o.lookup(&s, frame, "binding24743");
        const v24768 = try s.call(v24763, c.pi_js_undefined(), &.{ v24764, v24765, v24766, v24767 });
        return c.JS_DupValue(e.context, v24768);
    }
    const v24769 = try o.importValue(&s, graph, "value/codec/callback.mjs", "Callback");
    const v24770 = try o.lookup(&s, frame, "binding24740");
    const v24771 = try o.lookup(&s, frame, "binding24741");
    const v24772 = try o.lookup(&s, frame, "binding24742");
    const v24773 = try o.lookup(&s, frame, "binding24743");
    const v24774 = try s.call(v24769, c.pi_js_undefined(), &.{ v24770, v24771, v24772, v24773 });
    try o.assign(&s, frame, "binding24751", v24774);
    const v24775 = try o.lookup(&s, frame, "binding24742");
    const v24776 = try s.text("allOf");
    const v24777 = try s.own(try js.getKey(e, v24775, v24776));
    const v24778 = try s.text("map");
    const v24779 = try s.own(try js.getKey(e, v24777, v24778));
    const v24795 = try o.arrow(&s, "", 1, body24780C, &.{ graph, frame });
    const v24796 = try s.call(v24779, v24777, &.{v24795});
    try o.assign(&s, frame, "binding24752", v24796);
    const v24797 = try o.lookup(&s, frame, "binding24752");
    const v24798 = try s.text("every");
    const v24799 = try s.own(try js.getKey(e, v24797, v24798));
    const v24809 = try o.arrow(&s, "", 1, body24800C, &.{ graph, frame });
    const v24810 = try s.call(v24799, v24797, &.{v24809});
    try o.assign(&s, frame, "binding24753", v24810);
    const v24811 = try o.lookup(&s, frame, "binding24753");
    if (s.truthy(v24811)) {
        const v24812 = try o.lookup(&s, frame, "binding24612");
        const v24813 = try o.lookup(&s, frame, "binding24752");
        const v24814 = try s.call(v24812, c.pi_js_undefined(), &.{v24813});
        return c.JS_DupValue(e.context, v24814);
    }
    const v24815 = try o.lookup(&s, frame, "binding24613");
    const v24816 = try o.lookup(&s, frame, "binding24751");
    const v24817 = try o.lookup(&s, frame, "binding24752");
    const v24818 = try s.call(v24815, c.pi_js_undefined(), &.{ v24816, v24817 });
    return c.JS_DupValue(e.context, v24818);
}
fn body24820(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v24825 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding24821", v24825);
    const v24826 = if (args.len > 1) args[1] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding24822", v24826);
    const v24827 = if (args.len > 2) args[2] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding24823", v24827);
    const v24828 = if (args.len > 3) args[3] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding24824", v24828);
    const v24829 = try o.importValue(&s, graph, "guard/index.mjs", "Guard");
    const v24830 = try s.text("IsEqual");
    const v24831 = try s.own(try js.getKey(e, v24829, v24830));
    const v24832 = try o.lookup(&s, frame, "binding24821");
    const v24833 = try s.text("Decode");
    const v24834 = try s.call(v24831, v24829, &.{ v24832, v24833 });
    const v24836 = conditional24835: {
        if (s.truthy(v24834)) {
            const v24837 = try o.lookup(&s, frame, "binding24614");
            const v24838 = try o.lookup(&s, frame, "binding24821");
            const v24839 = try o.lookup(&s, frame, "binding24822");
            const v24840 = try o.lookup(&s, frame, "binding24823");
            const v24841 = try o.lookup(&s, frame, "binding24824");
            const v24842 = try s.call(v24837, c.pi_js_undefined(), &.{ v24838, v24839, v24840, v24841 });
            break :conditional24835 v24842;
        } else {
            const v24843 = try o.lookup(&s, frame, "binding24615");
            const v24844 = try o.lookup(&s, frame, "binding24821");
            const v24845 = try o.lookup(&s, frame, "binding24822");
            const v24846 = try o.lookup(&s, frame, "binding24823");
            const v24847 = try o.lookup(&s, frame, "binding24824");
            const v24848 = try s.call(v24843, c.pi_js_undefined(), &.{ v24844, v24845, v24846, v24847 });
            break :conditional24835 v24848;
        }
    };
    return c.JS_DupValue(e.context, v24836);
}
