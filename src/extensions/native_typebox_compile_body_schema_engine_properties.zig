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
    const namespace = try s.get(modules, "schema/engine/properties.mjs");
    const frame = try o.frame(&s, c.pi_js_null());
    try s.put(frame, "@this", c.pi_js_undefined());
    try s.put(try s.get(graph, "frames"), "schema/engine/properties.mjs", frame);
    const bindings = try s.object();
    try s.put(try s.get(graph, "bindings"), "schema/engine/properties.mjs", bindings);
    const v12816 = try s.own(try ordinary.create(e, "BuildProperties", 4, body12681, &.{ graph, frame }));
    try o.assign(&s, frame, "binding12678", v12816);
    const v12902 = try s.own(try ordinary.create(e, "CheckProperties", 4, body12817, &.{ graph, frame }));
    try o.assign(&s, frame, "binding12679", v12902);
    const v13025 = try s.own(try ordinary.create(e, "ErrorProperties", 6, body12903, &.{ graph, frame }));
    try o.assign(&s, frame, "binding12680", v13025);
    const v13026 = try o.lookup(&s, frame, "binding12678");
    try s.put(namespace, "BuildProperties", v13026);
    const v13027 = try o.lookup(&s, frame, "binding12679");
    try s.put(namespace, "CheckProperties", v13027);
    const v13028 = try o.lookup(&s, frame, "binding12680");
    try s.put(namespace, "ErrorProperties", v13028);
    const v13029 = try o.lookup(&s, frame, "binding12678");
    try s.put(namespace, "BuildProperties", v13029);
    const v13030 = try o.lookup(&s, frame, "binding12679");
    try s.put(namespace, "CheckProperties", v13030);
    const v13031 = try o.lookup(&s, frame, "binding12680");
    try s.put(namespace, "ErrorProperties", v13031);
    try s.put(bindings, "BuildProperties", try s.text("binding12678"));
    try s.put(bindings, "CheckProperties", try s.text("binding12679"));
    try s.put(bindings, "ErrorProperties", try s.text("binding12680"));
}
fn body12714(e: *Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    _ = try o.lookup(&s, frame, "@this");
    const v12723 = if (args.len > 0) args[0] else c.pi_js_undefined();
    var destructure12724 = try o.iterator(e, v12723);
    defer destructure12724.deinit();
    errdefer destructure12724.closePreserving();
    const v12725 = try s.own(if (destructure12724.closed) c.pi_js_undefined() else (try destructure12724.next()) orelse c.pi_js_undefined());
    try o.assign(&s, frame, "binding12716", v12725);
    const v12726 = try s.own(if (destructure12724.closed) c.pi_js_undefined() else (try destructure12724.next()) orelse c.pi_js_undefined());
    try o.assign(&s, frame, "binding12717", v12726);
    try destructure12724.close();
    const v12732 = try o.importValue(&s, graph, "guard/index.mjs", "EmitGuard");
    const v12733 = try s.text("Not");
    const v12734 = try s.own(try js.getKey(e, v12732, v12733));
    const v12735 = try o.importValue(&s, graph, "guard/index.mjs", "EmitGuard");
    const v12736 = try s.text("HasPropertyKey");
    const v12737 = try s.own(try js.getKey(e, v12735, v12736));
    const v12738 = try o.lookup(&s, frame, "binding12685");
    const v12739 = try o.importValue(&s, graph, "guard/index.mjs", "EmitGuard");
    const v12740 = try s.text("Constant");
    const v12741 = try s.own(try js.getKey(e, v12739, v12740));
    const v12742 = try o.lookup(&s, frame, "binding12716");
    const v12743 = try s.call(v12741, v12739, &.{v12742});
    const v12744 = try s.call(v12737, v12735, &.{ v12738, v12743 });
    const v12745 = try s.call(v12734, v12732, &.{v12744});
    try o.assign(&s, frame, "binding12727", v12745);
    const v12746 = try o.importValue(&s, graph, "schema/engine/schema.mjs", "BuildSchemaPushStack");
    const v12747 = try o.lookup(&s, frame, "binding12682");
    const v12748 = try o.lookup(&s, frame, "binding12683");
    const v12749 = try o.lookup(&s, frame, "binding12717");
    const v12750 = try o.importValue(&s, graph, "guard/index.mjs", "EmitGuard");
    const v12751 = try s.text("Member");
    const v12752 = try s.own(try js.getKey(e, v12750, v12751));
    const v12753 = try o.lookup(&s, frame, "binding12685");
    const v12754 = try o.lookup(&s, frame, "binding12716");
    const v12755 = try s.call(v12752, v12750, &.{ v12753, v12754 });
    const v12756 = try s.call(v12746, c.pi_js_undefined(), &.{ v12747, v12748, v12749, v12755 });
    try o.assign(&s, frame, "binding12728", v12756);
    const v12757 = try o.lookup(&s, frame, "binding12683");
    const v12758 = try s.text("AddKey");
    const v12759 = try s.own(try js.getKey(e, v12757, v12758));
    const v12760 = try o.importValue(&s, graph, "guard/index.mjs", "EmitGuard");
    const v12761 = try s.text("Constant");
    const v12762 = try s.own(try js.getKey(e, v12760, v12761));
    const v12763 = try o.lookup(&s, frame, "binding12716");
    const v12764 = try s.call(v12762, v12760, &.{v12763});
    const v12765 = try s.call(v12759, v12757, &.{v12764});
    try o.assign(&s, frame, "binding12729", v12765);
    const v12766 = try o.lookup(&s, frame, "binding12683");
    const v12767 = try s.text("UseUnevaluated");
    const v12768 = try s.own(try js.getKey(e, v12766, v12767));
    const v12769 = try s.call(v12768, v12766, &.{});
    const v12771 = conditional12770: {
        if (s.truthy(v12769)) {
            const v12772 = try o.importValue(&s, graph, "guard/index.mjs", "EmitGuard");
            const v12773 = try s.text("And");
            const v12774 = try s.own(try js.getKey(e, v12772, v12773));
            const v12775 = try o.lookup(&s, frame, "binding12728");
            const v12776 = try o.lookup(&s, frame, "binding12729");
            const v12777 = try s.call(v12774, v12772, &.{ v12775, v12776 });
            break :conditional12770 v12777;
        } else {
            const v12778 = try o.lookup(&s, frame, "binding12728");
            break :conditional12770 v12778;
        }
    };
    try o.assign(&s, frame, "binding12730", v12771);
    const v12779 = try o.lookup(&s, frame, "binding12692");
    const v12780 = try s.text("includes");
    const v12781 = try s.own(try js.getKey(e, v12779, v12780));
    const v12782 = try o.lookup(&s, frame, "binding12716");
    const v12783 = try s.call(v12781, v12779, &.{v12782});
    const v12785 = conditional12784: {
        if (s.truthy(v12783)) {
            const v12786 = try o.lookup(&s, frame, "binding12730");
            break :conditional12784 v12786;
        } else {
            const v12787 = try o.importValue(&s, graph, "guard/index.mjs", "EmitGuard");
            const v12788 = try s.text("Or");
            const v12789 = try s.own(try js.getKey(e, v12787, v12788));
            const v12790 = try o.lookup(&s, frame, "binding12727");
            const v12791 = try o.lookup(&s, frame, "binding12730");
            const v12792 = try s.call(v12789, v12787, &.{ v12790, v12791 });
            break :conditional12784 v12792;
        }
    };
    try o.assign(&s, frame, "binding12731", v12785);
    const v12793 = try o.importValue(&s, graph, "schema/engine/_exact_optional.mjs", "IsExactOptional");
    const v12794 = try o.lookup(&s, frame, "binding12692");
    const v12795 = try o.lookup(&s, frame, "binding12716");
    const v12796 = try s.call(v12793, c.pi_js_undefined(), &.{ v12794, v12795 });
    const v12798 = conditional12797: {
        if (s.truthy(v12796)) {
            const v12799 = try o.lookup(&s, frame, "binding12731");
            break :conditional12797 v12799;
        } else {
            const v12800 = try o.importValue(&s, graph, "guard/index.mjs", "EmitGuard");
            const v12801 = try s.text("Or");
            const v12802 = try s.own(try js.getKey(e, v12800, v12801));
            const v12803 = try o.importValue(&s, graph, "schema/engine/_exact_optional.mjs", "InexactOptionalBuild");
            const v12804 = try o.lookup(&s, frame, "binding12685");
            const v12805 = try o.lookup(&s, frame, "binding12716");
            const v12806 = try s.call(v12803, c.pi_js_undefined(), &.{ v12804, v12805 });
            const v12807 = try o.lookup(&s, frame, "binding12731");
            const v12808 = try s.call(v12802, v12800, &.{ v12806, v12807 });
            break :conditional12797 v12808;
        }
    };
    return c.JS_DupValue(e.context, v12798);
}
fn body12714C(ctx: ?*c.JSContext, receiver: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const e = Engine.fromContext(ctx.?);
    return body12714(e, receiver, if (argc > 0) argv[0..@intCast(argc)] else &.{}, roots[0..2]) catch |err| sdk.fail(e, err);
}
fn body12681(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v12688 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding12682", v12688);
    const v12689 = if (args.len > 1) args[1] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding12683", v12689);
    const v12690 = if (args.len > 2) args[2] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding12684", v12690);
    const v12691 = if (args.len > 3) args[3] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding12685", v12691);
    const v12694 = try o.importValue(&s, graph, "schema/types/index.mjs", "*");
    const v12695 = try s.text("IsRequired");
    const v12696 = try s.own(try js.getKey(e, v12694, v12695));
    const v12697 = try o.lookup(&s, frame, "binding12684");
    const v12698 = try s.call(v12696, v12694, &.{v12697});
    const v12700 = conditional12699: {
        if (s.truthy(v12698)) {
            const v12701 = try o.lookup(&s, frame, "binding12684");
            const v12702 = try s.text("required");
            const v12703 = try s.own(try js.getKey(e, v12701, v12702));
            break :conditional12699 v12703;
        } else {
            const v12704 = try s.array();
            break :conditional12699 v12704;
        }
    };
    try o.assign(&s, frame, "binding12692", v12700);
    const v12705 = try o.importValue(&s, graph, "guard/index.mjs", "Guard");
    const v12706 = try s.text("Entries");
    const v12707 = try s.own(try js.getKey(e, v12705, v12706));
    const v12708 = try o.lookup(&s, frame, "binding12684");
    const v12709 = try s.text("properties");
    const v12710 = try s.own(try js.getKey(e, v12708, v12709));
    const v12711 = try s.call(v12707, v12705, &.{v12710});
    const v12712 = try s.text("map");
    const v12713 = try s.own(try js.getKey(e, v12711, v12712));
    const v12809 = try o.arrow(&s, "", 1, body12714C, &.{ graph, frame });
    const v12810 = try s.call(v12713, v12711, &.{v12809});
    try o.assign(&s, frame, "binding12693", v12810);
    const v12811 = try o.importValue(&s, graph, "guard/index.mjs", "EmitGuard");
    const v12812 = try s.text("ReduceAnd");
    const v12813 = try s.own(try js.getKey(e, v12811, v12812));
    const v12814 = try o.lookup(&s, frame, "binding12693");
    const v12815 = try s.call(v12813, v12811, &.{v12814});
    return c.JS_DupValue(e.context, v12815);
}
fn body12851(e: *Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    _ = try o.lookup(&s, frame, "@this");
    const v12856 = if (args.len > 0) args[0] else c.pi_js_undefined();
    var destructure12857 = try o.iterator(e, v12856);
    defer destructure12857.deinit();
    errdefer destructure12857.closePreserving();
    const v12858 = try s.own(if (destructure12857.closed) c.pi_js_undefined() else (try destructure12857.next()) orelse c.pi_js_undefined());
    try o.assign(&s, frame, "binding12853", v12858);
    const v12859 = try s.own(if (destructure12857.closed) c.pi_js_undefined() else (try destructure12857.next()) orelse c.pi_js_undefined());
    try o.assign(&s, frame, "binding12854", v12859);
    try destructure12857.close();
    const v12861 = try o.importValue(&s, graph, "guard/index.mjs", "Guard");
    const v12862 = try s.text("HasPropertyKey");
    const v12863 = try s.own(try js.getKey(e, v12861, v12862));
    const v12864 = try o.lookup(&s, frame, "binding12821");
    const v12865 = try o.lookup(&s, frame, "binding12853");
    const v12866 = try s.call(v12863, v12861, &.{ v12864, v12865 });
    const v12868 = logical12867: {
        if (s.truthy(o.boolean(&s, !s.truthy(v12866)))) break :logical12867 o.boolean(&s, !s.truthy(v12866));
        const v12869 = try o.importValue(&s, graph, "schema/engine/schema.mjs", "CheckSchemaPushStack");
        const v12870 = try o.lookup(&s, frame, "binding12818");
        const v12871 = try o.lookup(&s, frame, "binding12819");
        const v12872 = try o.lookup(&s, frame, "binding12854");
        const v12873 = try o.lookup(&s, frame, "binding12821");
        const v12874 = try o.lookup(&s, frame, "binding12853");
        const v12875 = try o.propertyKey(&s, v12874);
        const v12876 = try s.own(try js.getKey(e, v12873, v12875));
        const v12877 = try s.call(v12869, c.pi_js_undefined(), &.{ v12870, v12871, v12872, v12876 });
        const v12879 = logical12878: {
            if (!s.truthy(v12877)) break :logical12878 v12877;
            const v12880 = try o.lookup(&s, frame, "binding12819");
            const v12881 = try s.text("AddKey");
            const v12882 = try s.own(try js.getKey(e, v12880, v12881));
            const v12883 = try o.lookup(&s, frame, "binding12853");
            const v12884 = try s.call(v12882, v12880, &.{v12883});
            break :logical12878 v12884;
        };
        break :logical12867 v12879;
    };
    try o.assign(&s, frame, "binding12860", v12868);
    const v12885 = try o.importValue(&s, graph, "schema/engine/_exact_optional.mjs", "IsExactOptional");
    const v12886 = try o.lookup(&s, frame, "binding12828");
    const v12887 = try o.lookup(&s, frame, "binding12853");
    const v12888 = try s.call(v12885, c.pi_js_undefined(), &.{ v12886, v12887 });
    const v12890 = conditional12889: {
        if (s.truthy(v12888)) {
            const v12891 = try o.lookup(&s, frame, "binding12860");
            break :conditional12889 v12891;
        } else {
            const v12892 = try o.importValue(&s, graph, "schema/engine/_exact_optional.mjs", "InexactOptionalCheck");
            const v12893 = try o.lookup(&s, frame, "binding12821");
            const v12894 = try o.lookup(&s, frame, "binding12853");
            const v12895 = try s.call(v12892, c.pi_js_undefined(), &.{ v12893, v12894 });
            const v12897 = logical12896: {
                if (s.truthy(v12895)) break :logical12896 v12895;
                const v12898 = try o.lookup(&s, frame, "binding12860");
                break :logical12896 v12898;
            };
            break :conditional12889 v12897;
        }
    };
    return c.JS_DupValue(e.context, v12890);
}
fn body12851C(ctx: ?*c.JSContext, receiver: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const e = Engine.fromContext(ctx.?);
    return body12851(e, receiver, if (argc > 0) argv[0..@intCast(argc)] else &.{}, roots[0..2]) catch |err| sdk.fail(e, err);
}
fn body12817(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v12824 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding12818", v12824);
    const v12825 = if (args.len > 1) args[1] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding12819", v12825);
    const v12826 = if (args.len > 2) args[2] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding12820", v12826);
    const v12827 = if (args.len > 3) args[3] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding12821", v12827);
    const v12830 = try o.importValue(&s, graph, "schema/types/index.mjs", "*");
    const v12831 = try s.text("IsRequired");
    const v12832 = try s.own(try js.getKey(e, v12830, v12831));
    const v12833 = try o.lookup(&s, frame, "binding12820");
    const v12834 = try s.call(v12832, v12830, &.{v12833});
    const v12836 = conditional12835: {
        if (s.truthy(v12834)) {
            const v12837 = try o.lookup(&s, frame, "binding12820");
            const v12838 = try s.text("required");
            const v12839 = try s.own(try js.getKey(e, v12837, v12838));
            break :conditional12835 v12839;
        } else {
            const v12840 = try s.array();
            break :conditional12835 v12840;
        }
    };
    try o.assign(&s, frame, "binding12828", v12836);
    const v12841 = try o.importValue(&s, graph, "guard/index.mjs", "Guard");
    const v12842 = try s.text("Every");
    const v12843 = try s.own(try js.getKey(e, v12841, v12842));
    const v12844 = try o.importValue(&s, graph, "guard/index.mjs", "Guard");
    const v12845 = try s.text("Entries");
    const v12846 = try s.own(try js.getKey(e, v12844, v12845));
    const v12847 = try o.lookup(&s, frame, "binding12820");
    const v12848 = try s.text("properties");
    const v12849 = try s.own(try js.getKey(e, v12847, v12848));
    const v12850 = try s.call(v12846, v12844, &.{v12849});
    const v12899 = try o.arrow(&s, "", 1, body12851C, &.{ graph, frame });
    const v12900 = try s.call(v12843, v12841, &.{ v12850, c.JS_NewFloat64(e.context, 0), v12899 });
    try o.assign(&s, frame, "binding12829", v12900);
    const v12901 = try o.lookup(&s, frame, "binding12829");
    return c.JS_DupValue(e.context, v12901);
}
fn body12977(e: *Engine, _: c.JSValue, _: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    _ = try o.lookup(&s, frame, "@this");
    const v12979 = try o.importValue(&s, graph, "guard/index.mjs", "Guard");
    const v12980 = try s.text("HasPropertyKey");
    const v12981 = try s.own(try js.getKey(e, v12979, v12980));
    const v12982 = try o.lookup(&s, frame, "binding12909");
    const v12983 = try o.lookup(&s, frame, "binding12943");
    const v12984 = try s.call(v12981, v12979, &.{ v12982, v12983 });
    const v12986 = logical12985: {
        if (s.truthy(o.boolean(&s, !s.truthy(v12984)))) break :logical12985 o.boolean(&s, !s.truthy(v12984));
        const v12987 = try o.importValue(&s, graph, "schema/engine/schema.mjs", "ErrorSchemaPushStack");
        const v12988 = try o.lookup(&s, frame, "binding12904");
        const v12989 = try o.lookup(&s, frame, "binding12905");
        const v12990 = try o.lookup(&s, frame, "binding12952");
        const v12991 = try o.lookup(&s, frame, "binding12953");
        const v12992 = try o.lookup(&s, frame, "binding12944");
        const v12993 = try o.lookup(&s, frame, "binding12909");
        const v12994 = try o.lookup(&s, frame, "binding12943");
        const v12995 = try o.propertyKey(&s, v12994);
        const v12996 = try s.own(try js.getKey(e, v12993, v12995));
        const v12997 = try s.call(v12987, c.pi_js_undefined(), &.{ v12988, v12989, v12990, v12991, v12992, v12996 });
        const v12999 = logical12998: {
            if (!s.truthy(v12997)) break :logical12998 v12997;
            const v13000 = try o.lookup(&s, frame, "binding12905");
            const v13001 = try s.text("AddKey");
            const v13002 = try s.own(try js.getKey(e, v13000, v13001));
            const v13003 = try o.lookup(&s, frame, "binding12943");
            const v13004 = try s.call(v13002, v13000, &.{v13003});
            break :logical12998 v13004;
        };
        break :logical12985 v12999;
    };
    return c.JS_DupValue(e.context, v12986);
}
fn body12977C(ctx: ?*c.JSContext, receiver: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const e = Engine.fromContext(ctx.?);
    return body12977(e, receiver, if (argc > 0) argv[0..@intCast(argc)] else &.{}, roots[0..2]) catch |err| sdk.fail(e, err);
}
fn body12941(e: *Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    _ = try o.lookup(&s, frame, "@this");
    const v12948 = if (args.len > 0) args[0] else c.pi_js_undefined();
    var destructure12949 = try o.iterator(e, v12948);
    defer destructure12949.deinit();
    errdefer destructure12949.closePreserving();
    const v12950 = try s.own(if (destructure12949.closed) c.pi_js_undefined() else (try destructure12949.next()) orelse c.pi_js_undefined());
    try o.assign(&s, frame, "binding12943", v12950);
    const v12951 = try s.own(if (destructure12949.closed) c.pi_js_undefined() else (try destructure12949.next()) orelse c.pi_js_undefined());
    try o.assign(&s, frame, "binding12944", v12951);
    try destructure12949.close();
    const v12955 = try s.text("");
    const v12956 = try o.lookup(&s, frame, "binding12906");
    const v12957 = try s.stringify(v12956);
    const v12958 = try s.concat(v12955, v12957);
    const v12959 = try s.text("/properties/");
    const v12960 = try s.concat(v12958, v12959);
    const v12961 = try o.lookup(&s, frame, "binding12943");
    const v12962 = try s.stringify(v12961);
    const v12963 = try s.concat(v12960, v12962);
    const v12964 = try s.text("");
    const v12965 = try s.concat(v12963, v12964);
    try o.assign(&s, frame, "binding12952", v12965);
    const v12966 = try s.text("");
    const v12967 = try o.lookup(&s, frame, "binding12907");
    const v12968 = try s.stringify(v12967);
    const v12969 = try s.concat(v12966, v12968);
    const v12970 = try s.text("/");
    const v12971 = try s.concat(v12969, v12970);
    const v12972 = try o.lookup(&s, frame, "binding12943");
    const v12973 = try s.stringify(v12972);
    const v12974 = try s.concat(v12971, v12973);
    const v12975 = try s.text("");
    const v12976 = try s.concat(v12974, v12975);
    try o.assign(&s, frame, "binding12953", v12976);
    const v13005 = try o.arrow(&s, "isProperty", 0, body12977C, &.{ graph, frame });
    try o.assign(&s, frame, "binding12954", v13005);
    const v13006 = try o.importValue(&s, graph, "schema/engine/_exact_optional.mjs", "IsExactOptional");
    const v13007 = try o.lookup(&s, frame, "binding12918");
    const v13008 = try o.lookup(&s, frame, "binding12943");
    const v13009 = try s.call(v13006, c.pi_js_undefined(), &.{ v13007, v13008 });
    const v13011 = conditional13010: {
        if (s.truthy(v13009)) {
            const v13012 = try o.lookup(&s, frame, "binding12954");
            const v13013 = try s.call(v13012, c.pi_js_undefined(), &.{});
            break :conditional13010 v13013;
        } else {
            const v13014 = try o.importValue(&s, graph, "schema/engine/_exact_optional.mjs", "InexactOptionalCheck");
            const v13015 = try o.lookup(&s, frame, "binding12909");
            const v13016 = try o.lookup(&s, frame, "binding12943");
            const v13017 = try s.call(v13014, c.pi_js_undefined(), &.{ v13015, v13016 });
            const v13019 = logical13018: {
                if (s.truthy(v13017)) break :logical13018 v13017;
                const v13020 = try o.lookup(&s, frame, "binding12954");
                const v13021 = try s.call(v13020, c.pi_js_undefined(), &.{});
                break :logical13018 v13021;
            };
            break :conditional13010 v13019;
        }
    };
    return c.JS_DupValue(e.context, v13011);
}
fn body12941C(ctx: ?*c.JSContext, receiver: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const e = Engine.fromContext(ctx.?);
    return body12941(e, receiver, if (argc > 0) argv[0..@intCast(argc)] else &.{}, roots[0..2]) catch |err| sdk.fail(e, err);
}
fn body12903(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v12912 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding12904", v12912);
    const v12913 = if (args.len > 1) args[1] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding12905", v12913);
    const v12914 = if (args.len > 2) args[2] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding12906", v12914);
    const v12915 = if (args.len > 3) args[3] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding12907", v12915);
    const v12916 = if (args.len > 4) args[4] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding12908", v12916);
    const v12917 = if (args.len > 5) args[5] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding12909", v12917);
    const v12920 = try o.importValue(&s, graph, "schema/types/index.mjs", "*");
    const v12921 = try s.text("IsRequired");
    const v12922 = try s.own(try js.getKey(e, v12920, v12921));
    const v12923 = try o.lookup(&s, frame, "binding12908");
    const v12924 = try s.call(v12922, v12920, &.{v12923});
    const v12926 = conditional12925: {
        if (s.truthy(v12924)) {
            const v12927 = try o.lookup(&s, frame, "binding12908");
            const v12928 = try s.text("required");
            const v12929 = try s.own(try js.getKey(e, v12927, v12928));
            break :conditional12925 v12929;
        } else {
            const v12930 = try s.array();
            break :conditional12925 v12930;
        }
    };
    try o.assign(&s, frame, "binding12918", v12926);
    const v12931 = try o.importValue(&s, graph, "guard/index.mjs", "Guard");
    const v12932 = try s.text("EveryAll");
    const v12933 = try s.own(try js.getKey(e, v12931, v12932));
    const v12934 = try o.importValue(&s, graph, "guard/index.mjs", "Guard");
    const v12935 = try s.text("Entries");
    const v12936 = try s.own(try js.getKey(e, v12934, v12935));
    const v12937 = try o.lookup(&s, frame, "binding12908");
    const v12938 = try s.text("properties");
    const v12939 = try s.own(try js.getKey(e, v12937, v12938));
    const v12940 = try s.call(v12936, v12934, &.{v12939});
    const v13022 = try o.arrow(&s, "", 1, body12941C, &.{ graph, frame });
    const v13023 = try s.call(v12933, v12931, &.{ v12940, c.JS_NewFloat64(e.context, 0), v13022 });
    try o.assign(&s, frame, "binding12919", v13023);
    const v13024 = try o.lookup(&s, frame, "binding12919");
    return c.JS_DupValue(e.context, v13024);
}
