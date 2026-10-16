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
    const namespace = try s.get(modules, "schema/engine/oneOf.mjs");
    const frame = try o.frame(&s, c.pi_js_null());
    try s.put(frame, "@this", c.pi_js_undefined());
    try s.put(try s.get(graph, "frames"), "schema/engine/oneOf.mjs", frame);
    const bindings = try s.object();
    try s.put(try s.get(graph, "bindings"), "schema/engine/oneOf.mjs", bindings);
    const v11656 = try s.own(try ordinary.create(e, "BuildOneOfStandard", 4, body11625, &.{ graph, frame }));
    try o.assign(&s, frame, "binding11620", v11656);
    const v11724 = try s.own(try ordinary.create(e, "BuildOneOfFast", 4, body11657, &.{ graph, frame }));
    try o.assign(&s, frame, "binding11621", v11724);
    const v11752 = try s.own(try ordinary.create(e, "BuildOneOf", 4, body11725, &.{ graph, frame }));
    try o.assign(&s, frame, "binding11622", v11752);
    const v11808 = try s.own(try ordinary.create(e, "CheckOneOf", 4, body11753, &.{ graph, frame }));
    try o.assign(&s, frame, "binding11623", v11808);
    const v11962 = try s.own(try ordinary.create(e, "ErrorOneOf", 6, body11809, &.{ graph, frame }));
    try o.assign(&s, frame, "binding11624", v11962);
    const v11963 = try o.lookup(&s, frame, "binding11622");
    try s.put(namespace, "BuildOneOf", v11963);
    const v11964 = try o.lookup(&s, frame, "binding11623");
    try s.put(namespace, "CheckOneOf", v11964);
    const v11965 = try o.lookup(&s, frame, "binding11624");
    try s.put(namespace, "ErrorOneOf", v11965);
    const v11966 = try o.lookup(&s, frame, "binding11622");
    try s.put(namespace, "BuildOneOf", v11966);
    const v11967 = try o.lookup(&s, frame, "binding11623");
    try s.put(namespace, "CheckOneOf", v11967);
    const v11968 = try o.lookup(&s, frame, "binding11624");
    try s.put(namespace, "ErrorOneOf", v11968);
    try s.put(bindings, "BuildOneOf", try s.text("binding11622"));
    try s.put(bindings, "CheckOneOf", try s.text("binding11623"));
    try s.put(bindings, "ErrorOneOf", try s.text("binding11624"));
}
fn body11625(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v11630 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding11626", v11630);
    const v11631 = if (args.len > 1) args[1] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding11627", v11631);
    const v11632 = if (args.len > 2) args[2] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding11628", v11632);
    const v11633 = if (args.len > 3) args[3] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding11629", v11633);
    const v11634 = try o.importValue(&s, graph, "schema/engine/_reducer.mjs", "Reducer");
    const v11635 = try o.lookup(&s, frame, "binding11626");
    const v11636 = try o.lookup(&s, frame, "binding11627");
    const v11637 = try o.lookup(&s, frame, "binding11628");
    const v11638 = try s.text("oneOf");
    const v11639 = try s.own(try js.getKey(e, v11637, v11638));
    const v11640 = try o.lookup(&s, frame, "binding11629");
    const v11641 = try o.importValue(&s, graph, "guard/index.mjs", "EmitGuard");
    const v11642 = try s.text("IsEqual");
    const v11643 = try s.own(try js.getKey(e, v11641, v11642));
    const v11644 = try o.importValue(&s, graph, "guard/index.mjs", "EmitGuard");
    const v11645 = try s.text("Member");
    const v11646 = try s.own(try js.getKey(e, v11644, v11645));
    const v11647 = try s.text("results");
    const v11648 = try s.text("length");
    const v11649 = try s.call(v11646, v11644, &.{ v11647, v11648 });
    const v11650 = try o.importValue(&s, graph, "guard/index.mjs", "EmitGuard");
    const v11651 = try s.text("Constant");
    const v11652 = try s.own(try js.getKey(e, v11650, v11651));
    const v11653 = try s.call(v11652, v11650, &.{c.JS_NewFloat64(e.context, 1)});
    const v11654 = try s.call(v11643, v11641, &.{ v11649, v11653 });
    const v11655 = try s.call(v11634, c.pi_js_undefined(), &.{ v11635, v11636, v11639, v11640, v11654 });
    return c.JS_DupValue(e.context, v11655);
}
fn body11685(e: *Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    _ = try o.lookup(&s, frame, "@this");
    const v11688 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding11687", v11688);
    const v11689 = try o.importValue(&s, graph, "schema/engine/schema.mjs", "BuildSchema");
    const v11690 = try o.lookup(&s, frame, "binding11658");
    const v11691 = try o.lookup(&s, frame, "binding11659");
    const v11692 = try o.lookup(&s, frame, "binding11687");
    const v11693 = try o.lookup(&s, frame, "binding11661");
    const v11694 = try s.call(v11689, c.pi_js_undefined(), &.{ v11690, v11691, v11692, v11693 });
    return c.JS_DupValue(e.context, v11694);
}
fn body11685C(ctx: ?*c.JSContext, receiver: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const e = Engine.fromContext(ctx.?);
    return body11685(e, receiver, if (argc > 0) argv[0..@intCast(argc)] else &.{}, roots[0..2]) catch |err| sdk.fail(e, err);
}
fn body11657(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v11665 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding11658", v11665);
    const v11666 = if (args.len > 1) args[1] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding11659", v11666);
    const v11667 = if (args.len > 2) args[2] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding11660", v11667);
    const v11668 = if (args.len > 3) args[3] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding11661", v11668);
    const v11672 = try s.array();
    const v11673 = try o.importValue(&s, graph, "schema/engine/_unique.mjs", "Unique");
    const v11674 = try s.call(v11673, c.pi_js_undefined(), &.{});
    try o.append(&s, v11672, v11674);
    var destructure11675 = try o.iterator(e, v11672);
    defer destructure11675.deinit();
    errdefer destructure11675.closePreserving();
    const v11676 = try s.own(if (destructure11675.closed) c.pi_js_undefined() else (try destructure11675.next()) orelse c.pi_js_undefined());
    try o.assign(&s, frame, "binding11669", v11676);
    try destructure11675.close();
    const v11677 = try o.importValue(&s, graph, "guard/index.mjs", "EmitGuard");
    const v11678 = try s.text("ArrayLiteral");
    const v11679 = try s.own(try js.getKey(e, v11677, v11678));
    const v11680 = try o.lookup(&s, frame, "binding11660");
    const v11681 = try s.text("oneOf");
    const v11682 = try s.own(try js.getKey(e, v11680, v11681));
    const v11683 = try s.text("map");
    const v11684 = try s.own(try js.getKey(e, v11682, v11683));
    const v11695 = try o.arrow(&s, "", 1, body11685C, &.{ graph, frame });
    const v11696 = try s.call(v11684, v11682, &.{v11695});
    const v11697 = try s.call(v11679, v11677, &.{v11696});
    try o.assign(&s, frame, "binding11670", v11697);
    const v11698 = try o.importValue(&s, graph, "guard/index.mjs", "EmitGuard");
    const v11699 = try s.text("Counted");
    const v11700 = try s.own(try js.getKey(e, v11698, v11699));
    const v11701 = try o.lookup(&s, frame, "binding11670");
    const v11702 = try s.array();
    const v11703 = try o.lookup(&s, frame, "binding11669");
    try o.append(&s, v11702, v11703);
    const v11704 = try s.text("_");
    try o.append(&s, v11702, v11704);
    const v11705 = try o.importValue(&s, graph, "guard/index.mjs", "EmitGuard");
    const v11706 = try s.text("IsEqual");
    const v11707 = try s.own(try js.getKey(e, v11705, v11706));
    const v11708 = try o.lookup(&s, frame, "binding11669");
    const v11709 = try o.importValue(&s, graph, "guard/index.mjs", "EmitGuard");
    const v11710 = try s.text("Constant");
    const v11711 = try s.own(try js.getKey(e, v11709, v11710));
    const v11712 = try s.call(v11711, v11709, &.{o.boolean(&s, true)});
    const v11713 = try s.call(v11707, v11705, &.{ v11708, v11712 });
    const v11714 = try s.call(v11700, v11698, &.{ v11701, v11702, v11713 });
    try o.assign(&s, frame, "binding11671", v11714);
    const v11715 = try o.importValue(&s, graph, "guard/index.mjs", "EmitGuard");
    const v11716 = try s.text("IsEqual");
    const v11717 = try s.own(try js.getKey(e, v11715, v11716));
    const v11718 = try o.lookup(&s, frame, "binding11671");
    const v11719 = try o.importValue(&s, graph, "guard/index.mjs", "EmitGuard");
    const v11720 = try s.text("Constant");
    const v11721 = try s.own(try js.getKey(e, v11719, v11720));
    const v11722 = try s.call(v11721, v11719, &.{c.JS_NewFloat64(e.context, 1)});
    const v11723 = try s.call(v11717, v11715, &.{ v11718, v11722 });
    return c.JS_DupValue(e.context, v11723);
}
fn body11725(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    _ = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v11730 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding11726", v11730);
    const v11731 = if (args.len > 1) args[1] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding11727", v11731);
    const v11732 = if (args.len > 2) args[2] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding11728", v11732);
    const v11733 = if (args.len > 3) args[3] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding11729", v11733);
    const v11734 = try o.lookup(&s, frame, "binding11727");
    const v11735 = try s.text("UseUnevaluated");
    const v11736 = try s.own(try js.getKey(e, v11734, v11735));
    const v11737 = try s.call(v11736, v11734, &.{});
    const v11739 = conditional11738: {
        if (s.truthy(v11737)) {
            const v11740 = try o.lookup(&s, frame, "binding11620");
            const v11741 = try o.lookup(&s, frame, "binding11726");
            const v11742 = try o.lookup(&s, frame, "binding11727");
            const v11743 = try o.lookup(&s, frame, "binding11728");
            const v11744 = try o.lookup(&s, frame, "binding11729");
            const v11745 = try s.call(v11740, c.pi_js_undefined(), &.{ v11741, v11742, v11743, v11744 });
            break :conditional11738 v11745;
        } else {
            const v11746 = try o.lookup(&s, frame, "binding11621");
            const v11747 = try o.lookup(&s, frame, "binding11726");
            const v11748 = try o.lookup(&s, frame, "binding11727");
            const v11749 = try o.lookup(&s, frame, "binding11728");
            const v11750 = try o.lookup(&s, frame, "binding11729");
            const v11751 = try s.call(v11746, c.pi_js_undefined(), &.{ v11747, v11748, v11749, v11750 });
            break :conditional11738 v11751;
        }
    };
    return c.JS_DupValue(e.context, v11739);
}
fn body11769(e: *Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    _ = try o.lookup(&s, frame, "@this");
    const v11774 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding11771", v11774);
    const v11775 = if (args.len > 1) args[1] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding11772", v11775);
    const v11777 = try o.importValue(&s, graph, "schema/engine/_context.mjs", "CheckContext");
    const v11778 = try o.construct(&s, v11777, &.{});
    try o.assign(&s, frame, "binding11776", v11778);
    const v11779 = try o.importValue(&s, graph, "schema/engine/schema.mjs", "CheckSchema");
    const v11780 = try o.lookup(&s, frame, "binding11754");
    const v11781 = try o.lookup(&s, frame, "binding11776");
    const v11782 = try o.lookup(&s, frame, "binding11772");
    const v11783 = try o.lookup(&s, frame, "binding11757");
    const v11784 = try s.call(v11779, c.pi_js_undefined(), &.{ v11780, v11781, v11782, v11783 });
    const v11786 = conditional11785: {
        if (s.truthy(v11784)) {
            const v11787 = try s.array();
            const v11788 = try o.lookup(&s, frame, "binding11771");
            try o.spreadArray(&s, v11787, v11788);
            const v11789 = try o.lookup(&s, frame, "binding11776");
            try o.append(&s, v11787, v11789);
            break :conditional11785 v11787;
        } else {
            const v11790 = try o.lookup(&s, frame, "binding11771");
            break :conditional11785 v11790;
        }
    };
    return c.JS_DupValue(e.context, v11786);
}
fn body11769C(ctx: ?*c.JSContext, receiver: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const e = Engine.fromContext(ctx.?);
    return body11769(e, receiver, if (argc > 0) argv[0..@intCast(argc)] else &.{}, roots[0..2]) catch |err| sdk.fail(e, err);
}
fn body11753(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v11759 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding11754", v11759);
    const v11760 = if (args.len > 1) args[1] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding11755", v11760);
    const v11761 = if (args.len > 2) args[2] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding11756", v11761);
    const v11762 = if (args.len > 3) args[3] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding11757", v11762);
    const v11764 = try o.lookup(&s, frame, "binding11756");
    const v11765 = try s.text("oneOf");
    const v11766 = try s.own(try js.getKey(e, v11764, v11765));
    const v11767 = try s.text("reduce");
    const v11768 = try s.own(try js.getKey(e, v11766, v11767));
    const v11791 = try o.arrow(&s, "", 2, body11769C, &.{ graph, frame });
    const v11792 = try s.array();
    const v11793 = try s.call(v11768, v11766, &.{ v11791, v11792 });
    try o.assign(&s, frame, "binding11763", v11793);
    const v11794 = try o.importValue(&s, graph, "guard/index.mjs", "Guard");
    const v11795 = try s.text("IsEqual");
    const v11796 = try s.own(try js.getKey(e, v11794, v11795));
    const v11797 = try o.lookup(&s, frame, "binding11763");
    const v11798 = try s.text("length");
    const v11799 = try s.own(try js.getKey(e, v11797, v11798));
    const v11800 = try s.call(v11796, v11794, &.{ v11799, c.JS_NewFloat64(e.context, 1) });
    const v11802 = logical11801: {
        if (!s.truthy(v11800)) break :logical11801 v11800;
        const v11803 = try o.lookup(&s, frame, "binding11755");
        const v11804 = try s.text("Merge");
        const v11805 = try s.own(try js.getKey(e, v11803, v11804));
        const v11806 = try o.lookup(&s, frame, "binding11763");
        const v11807 = try s.call(v11805, v11803, &.{v11806});
        break :logical11801 v11807;
    };
    return c.JS_DupValue(e.context, v11802);
}
fn body11837(e: *Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    _ = try o.lookup(&s, frame, "@this");
    const v11845 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding11839", v11845);
    const v11846 = if (args.len > 1) args[1] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding11840", v11846);
    const v11847 = if (args.len > 2) args[2] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding11841", v11847);
    const v11851 = try o.importValue(&s, graph, "schema/engine/_context.mjs", "ErrorContext");
    const v11852 = try o.construct(&s, v11851, &.{});
    try o.assign(&s, frame, "binding11848", v11852);
    const v11853 = try s.text("");
    const v11854 = try o.lookup(&s, frame, "binding11812");
    const v11855 = try s.stringify(v11854);
    const v11856 = try s.concat(v11853, v11855);
    const v11857 = try s.text("/oneOf/");
    const v11858 = try s.concat(v11856, v11857);
    const v11859 = try o.lookup(&s, frame, "binding11841");
    const v11860 = try s.stringify(v11859);
    const v11861 = try s.concat(v11858, v11860);
    const v11862 = try s.text("");
    const v11863 = try s.concat(v11861, v11862);
    try o.assign(&s, frame, "binding11849", v11863);
    const v11864 = try o.importValue(&s, graph, "schema/engine/schema.mjs", "ErrorSchema");
    const v11865 = try o.lookup(&s, frame, "binding11810");
    const v11866 = try o.lookup(&s, frame, "binding11848");
    const v11867 = try o.lookup(&s, frame, "binding11849");
    const v11868 = try o.lookup(&s, frame, "binding11813");
    const v11869 = try o.lookup(&s, frame, "binding11840");
    const v11870 = try o.lookup(&s, frame, "binding11815");
    const v11871 = try s.call(v11864, c.pi_js_undefined(), &.{ v11865, v11866, v11867, v11868, v11869, v11870 });
    try o.assign(&s, frame, "binding11850", v11871);
    const v11872 = try o.lookup(&s, frame, "binding11850");
    if (s.truthy(v11872)) {
        const v11873 = try o.lookup(&s, frame, "binding11827");
        const v11874 = try s.text("push");
        const v11875 = try s.own(try js.getKey(e, v11873, v11874));
        const v11876 = try o.lookup(&s, frame, "binding11841");
        const v11877 = try s.call(v11875, v11873, &.{v11876});
        _ = v11877;
    }
    const v11878 = try o.lookup(&s, frame, "binding11850");
    if (s.truthy(o.boolean(&s, !s.truthy(v11878)))) {
        const v11879 = try o.lookup(&s, frame, "binding11826");
        const v11880 = try s.text("push");
        const v11881 = try s.own(try js.getKey(e, v11879, v11880));
        const v11882 = try o.lookup(&s, frame, "binding11848");
        const v11883 = try s.call(v11881, v11879, &.{v11882});
        _ = v11883;
    }
    const v11884 = try o.lookup(&s, frame, "binding11850");
    const v11886 = conditional11885: {
        if (s.truthy(v11884)) {
            const v11887 = try s.array();
            const v11888 = try o.lookup(&s, frame, "binding11839");
            try o.spreadArray(&s, v11887, v11888);
            const v11889 = try o.lookup(&s, frame, "binding11848");
            try o.append(&s, v11887, v11889);
            break :conditional11885 v11887;
        } else {
            const v11890 = try o.lookup(&s, frame, "binding11839");
            break :conditional11885 v11890;
        }
    };
    return c.JS_DupValue(e.context, v11886);
}
fn body11837C(ctx: ?*c.JSContext, receiver: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const e = Engine.fromContext(ctx.?);
    return body11837(e, receiver, if (argc > 0) argv[0..@intCast(argc)] else &.{}, roots[0..2]) catch |err| sdk.fail(e, err);
}
fn body11931(e: *Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    _ = roots[0];
    const frame = try o.frame(&s, roots[1]);
    _ = try o.lookup(&s, frame, "@this");
    const v11934 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding11933", v11934);
    const v11935 = try o.lookup(&s, frame, "binding11811");
    const v11936 = try s.text("AddError");
    const v11937 = try s.own(try js.getKey(e, v11935, v11936));
    const v11938 = try o.lookup(&s, frame, "binding11933");
    const v11939 = try s.call(v11937, v11935, &.{v11938});
    return c.JS_DupValue(e.context, v11939);
}
fn body11931C(ctx: ?*c.JSContext, receiver: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const e = Engine.fromContext(ctx.?);
    return body11931(e, receiver, if (argc > 0) argv[0..@intCast(argc)] else &.{}, roots[0..2]) catch |err| sdk.fail(e, err);
}
fn body11921(e: *Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    _ = try o.lookup(&s, frame, "@this");
    const v11924 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding11923", v11924);
    const v11925 = try o.lookup(&s, frame, "binding11923");
    const v11926 = try s.text("GetErrors");
    const v11927 = try s.own(try js.getKey(e, v11925, v11926));
    const v11928 = try s.call(v11927, v11925, &.{});
    const v11929 = try s.text("forEach");
    const v11930 = try s.own(try js.getKey(e, v11928, v11929));
    const v11940 = try o.arrow(&s, "", 1, body11931C, &.{ graph, frame });
    const v11941 = try s.call(v11930, v11928, &.{v11940});
    return c.JS_DupValue(e.context, v11941);
}
fn body11921C(ctx: ?*c.JSContext, receiver: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const e = Engine.fromContext(ctx.?);
    return body11921(e, receiver, if (argc > 0) argv[0..@intCast(argc)] else &.{}, roots[0..2]) catch |err| sdk.fail(e, err);
}
fn body11809(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v11820 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding11810", v11820);
    const v11821 = if (args.len > 1) args[1] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding11811", v11821);
    const v11822 = if (args.len > 2) args[2] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding11812", v11822);
    const v11823 = if (args.len > 3) args[3] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding11813", v11823);
    const v11824 = if (args.len > 4) args[4] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding11814", v11824);
    const v11825 = if (args.len > 5) args[5] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding11815", v11825);
    const v11830 = try s.array();
    try o.assign(&s, frame, "binding11826", v11830);
    const v11831 = try s.array();
    try o.assign(&s, frame, "binding11827", v11831);
    const v11832 = try o.lookup(&s, frame, "binding11814");
    const v11833 = try s.text("oneOf");
    const v11834 = try s.own(try js.getKey(e, v11832, v11833));
    const v11835 = try s.text("reduce");
    const v11836 = try s.own(try js.getKey(e, v11834, v11835));
    const v11891 = try o.arrow(&s, "", 3, body11837C, &.{ graph, frame });
    const v11892 = try s.array();
    const v11893 = try s.call(v11836, v11834, &.{ v11891, v11892 });
    try o.assign(&s, frame, "binding11828", v11893);
    const v11894 = try o.importValue(&s, graph, "guard/index.mjs", "Guard");
    const v11895 = try s.text("IsEqual");
    const v11896 = try s.own(try js.getKey(e, v11894, v11895));
    const v11897 = try o.lookup(&s, frame, "binding11828");
    const v11898 = try s.text("length");
    const v11899 = try s.own(try js.getKey(e, v11897, v11898));
    const v11900 = try s.call(v11896, v11894, &.{ v11899, c.JS_NewFloat64(e.context, 1) });
    const v11902 = logical11901: {
        if (!s.truthy(v11900)) break :logical11901 v11900;
        const v11903 = try o.lookup(&s, frame, "binding11811");
        const v11904 = try s.text("Merge");
        const v11905 = try s.own(try js.getKey(e, v11903, v11904));
        const v11906 = try o.lookup(&s, frame, "binding11828");
        const v11907 = try s.call(v11905, v11903, &.{v11906});
        break :logical11901 v11907;
    };
    try o.assign(&s, frame, "binding11829", v11902);
    const v11908 = try o.lookup(&s, frame, "binding11829");
    const v11910 = logical11909: {
        if (!s.truthy(o.boolean(&s, !s.truthy(v11908)))) break :logical11909 o.boolean(&s, !s.truthy(v11908));
        const v11911 = try o.importValue(&s, graph, "guard/index.mjs", "Guard");
        const v11912 = try s.text("IsEqual");
        const v11913 = try s.own(try js.getKey(e, v11911, v11912));
        const v11914 = try o.lookup(&s, frame, "binding11827");
        const v11915 = try s.text("length");
        const v11916 = try s.own(try js.getKey(e, v11914, v11915));
        const v11917 = try s.call(v11913, v11911, &.{ v11916, c.JS_NewFloat64(e.context, 0) });
        break :logical11909 v11917;
    };
    if (s.truthy(v11910)) {
        const v11918 = try o.lookup(&s, frame, "binding11826");
        const v11919 = try s.text("forEach");
        const v11920 = try s.own(try js.getKey(e, v11918, v11919));
        const v11942 = try o.arrow(&s, "", 1, body11921C, &.{ graph, frame });
        const v11943 = try s.call(v11920, v11918, &.{v11942});
        _ = v11943;
    }
    const v11944 = try o.lookup(&s, frame, "binding11829");
    const v11946 = logical11945: {
        if (s.truthy(v11944)) break :logical11945 v11944;
        const v11947 = try o.lookup(&s, frame, "binding11811");
        const v11948 = try s.text("AddError");
        const v11949 = try s.own(try js.getKey(e, v11947, v11948));
        const v11950 = try s.object();
        const v11951 = try s.text("keyword");
        const v11952 = try s.text("oneOf");
        try o.defineKey(&s, v11950, v11951, v11952);
        const v11953 = try s.text("schemaPath");
        const v11954 = try o.lookup(&s, frame, "binding11812");
        try o.defineKey(&s, v11950, v11953, v11954);
        const v11955 = try s.text("instancePath");
        const v11956 = try o.lookup(&s, frame, "binding11813");
        try o.defineKey(&s, v11950, v11955, v11956);
        const v11957 = try s.text("params");
        const v11958 = try s.object();
        const v11959 = try s.text("passingSchemas");
        const v11960 = try o.lookup(&s, frame, "binding11827");
        try o.defineKey(&s, v11958, v11959, v11960);
        try o.defineKey(&s, v11950, v11957, v11958);
        const v11961 = try s.call(v11949, v11947, &.{v11950});
        break :logical11945 v11961;
    };
    return c.JS_DupValue(e.context, v11946);
}
