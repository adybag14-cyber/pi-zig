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
    const namespace = try s.get(modules, "value/default/from_type.mjs");
    const frame = try o.frame(&s, c.pi_js_null());
    try s.put(frame, "@this", c.pi_js_undefined());
    try s.put(try s.get(graph, "frames"), "value/default/from_type.mjs", frame);
    const bindings = try s.object();
    try s.put(try s.get(graph, "bindings"), "value/default/from_type.mjs", bindings);
    const v29909 = try s.own(try ordinary.create(e, "FromType", 3, body29793, &.{ graph, frame }));
    try o.assign(&s, frame, "binding29792", v29909);
    const v29910 = try o.lookup(&s, frame, "binding29792");
    try s.put(namespace, "FromType", v29910);
    const v29911 = try o.lookup(&s, frame, "binding29792");
    try s.put(namespace, "FromType", v29911);
    try s.put(bindings, "FromType", try s.text("binding29792"));
}
fn body29793(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v29798 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding29794", v29798);
    const v29799 = if (args.len > 1) args[1] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding29795", v29799);
    const v29800 = if (args.len > 2) args[2] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding29796", v29800);
    const v29802 = try o.importValue(&s, graph, "schema/index.mjs", "IsDefault");
    const v29803 = try o.lookup(&s, frame, "binding29795");
    const v29804 = try s.call(v29802, c.pi_js_undefined(), &.{v29803});
    const v29806 = conditional29805: {
        if (s.truthy(v29804)) {
            const v29807 = try o.importValue(&s, graph, "value/default/from_default.mjs", "FromDefault");
            const v29808 = try o.lookup(&s, frame, "binding29795");
            const v29809 = try o.lookup(&s, frame, "binding29796");
            const v29810 = try s.call(v29807, c.pi_js_undefined(), &.{ v29808, v29809 });
            break :conditional29805 v29810;
        } else {
            const v29811 = try o.lookup(&s, frame, "binding29796");
            break :conditional29805 v29811;
        }
    };
    try o.assign(&s, frame, "binding29801", v29806);
    const v29812 = try o.importValue(&s, graph, "type/index.mjs", "*");
    const v29813 = try s.text("IsArray");
    const v29814 = try s.own(try js.getKey(e, v29812, v29813));
    const v29815 = try o.lookup(&s, frame, "binding29795");
    const v29816 = try s.call(v29814, v29812, &.{v29815});
    const v29818 = conditional29817: {
        if (s.truthy(v29816)) {
            const v29819 = try o.importValue(&s, graph, "value/default/from_array.mjs", "FromArray");
            const v29820 = try o.lookup(&s, frame, "binding29794");
            const v29821 = try o.lookup(&s, frame, "binding29795");
            const v29822 = try o.lookup(&s, frame, "binding29801");
            const v29823 = try s.call(v29819, c.pi_js_undefined(), &.{ v29820, v29821, v29822 });
            break :conditional29817 v29823;
        } else {
            const v29824 = try o.importValue(&s, graph, "type/index.mjs", "*");
            const v29825 = try s.text("IsCyclic");
            const v29826 = try s.own(try js.getKey(e, v29824, v29825));
            const v29827 = try o.lookup(&s, frame, "binding29795");
            const v29828 = try s.call(v29826, v29824, &.{v29827});
            const v29830 = conditional29829: {
                if (s.truthy(v29828)) {
                    const v29831 = try o.importValue(&s, graph, "value/default/from_cyclic.mjs", "FromCyclic");
                    const v29832 = try o.lookup(&s, frame, "binding29794");
                    const v29833 = try o.lookup(&s, frame, "binding29795");
                    const v29834 = try o.lookup(&s, frame, "binding29801");
                    const v29835 = try s.call(v29831, c.pi_js_undefined(), &.{ v29832, v29833, v29834 });
                    break :conditional29829 v29835;
                } else {
                    const v29836 = try o.importValue(&s, graph, "type/index.mjs", "*");
                    const v29837 = try s.text("IsIntersect");
                    const v29838 = try s.own(try js.getKey(e, v29836, v29837));
                    const v29839 = try o.lookup(&s, frame, "binding29795");
                    const v29840 = try s.call(v29838, v29836, &.{v29839});
                    const v29842 = conditional29841: {
                        if (s.truthy(v29840)) {
                            const v29843 = try o.importValue(&s, graph, "value/default/from_intersect.mjs", "FromIntersect");
                            const v29844 = try o.lookup(&s, frame, "binding29794");
                            const v29845 = try o.lookup(&s, frame, "binding29795");
                            const v29846 = try o.lookup(&s, frame, "binding29801");
                            const v29847 = try s.call(v29843, c.pi_js_undefined(), &.{ v29844, v29845, v29846 });
                            break :conditional29841 v29847;
                        } else {
                            const v29848 = try o.importValue(&s, graph, "type/index.mjs", "*");
                            const v29849 = try s.text("IsObject");
                            const v29850 = try s.own(try js.getKey(e, v29848, v29849));
                            const v29851 = try o.lookup(&s, frame, "binding29795");
                            const v29852 = try s.call(v29850, v29848, &.{v29851});
                            const v29854 = conditional29853: {
                                if (s.truthy(v29852)) {
                                    const v29855 = try o.importValue(&s, graph, "value/default/from_object.mjs", "FromObject");
                                    const v29856 = try o.lookup(&s, frame, "binding29794");
                                    const v29857 = try o.lookup(&s, frame, "binding29795");
                                    const v29858 = try o.lookup(&s, frame, "binding29801");
                                    const v29859 = try s.call(v29855, c.pi_js_undefined(), &.{ v29856, v29857, v29858 });
                                    break :conditional29853 v29859;
                                } else {
                                    const v29860 = try o.importValue(&s, graph, "type/index.mjs", "*");
                                    const v29861 = try s.text("IsRecord");
                                    const v29862 = try s.own(try js.getKey(e, v29860, v29861));
                                    const v29863 = try o.lookup(&s, frame, "binding29795");
                                    const v29864 = try s.call(v29862, v29860, &.{v29863});
                                    const v29866 = conditional29865: {
                                        if (s.truthy(v29864)) {
                                            const v29867 = try o.importValue(&s, graph, "value/default/from_record.mjs", "FromRecord");
                                            const v29868 = try o.lookup(&s, frame, "binding29794");
                                            const v29869 = try o.lookup(&s, frame, "binding29795");
                                            const v29870 = try o.lookup(&s, frame, "binding29801");
                                            const v29871 = try s.call(v29867, c.pi_js_undefined(), &.{ v29868, v29869, v29870 });
                                            break :conditional29865 v29871;
                                        } else {
                                            const v29872 = try o.importValue(&s, graph, "type/index.mjs", "*");
                                            const v29873 = try s.text("IsRef");
                                            const v29874 = try s.own(try js.getKey(e, v29872, v29873));
                                            const v29875 = try o.lookup(&s, frame, "binding29795");
                                            const v29876 = try s.call(v29874, v29872, &.{v29875});
                                            const v29878 = conditional29877: {
                                                if (s.truthy(v29876)) {
                                                    const v29879 = try o.importValue(&s, graph, "value/default/from_ref.mjs", "FromRef");
                                                    const v29880 = try o.lookup(&s, frame, "binding29794");
                                                    const v29881 = try o.lookup(&s, frame, "binding29795");
                                                    const v29882 = try o.lookup(&s, frame, "binding29801");
                                                    const v29883 = try s.call(v29879, c.pi_js_undefined(), &.{ v29880, v29881, v29882 });
                                                    break :conditional29877 v29883;
                                                } else {
                                                    const v29884 = try o.importValue(&s, graph, "type/index.mjs", "*");
                                                    const v29885 = try s.text("IsTuple");
                                                    const v29886 = try s.own(try js.getKey(e, v29884, v29885));
                                                    const v29887 = try o.lookup(&s, frame, "binding29795");
                                                    const v29888 = try s.call(v29886, v29884, &.{v29887});
                                                    const v29890 = conditional29889: {
                                                        if (s.truthy(v29888)) {
                                                            const v29891 = try o.importValue(&s, graph, "value/default/from_tuple.mjs", "FromTuple");
                                                            const v29892 = try o.lookup(&s, frame, "binding29794");
                                                            const v29893 = try o.lookup(&s, frame, "binding29795");
                                                            const v29894 = try o.lookup(&s, frame, "binding29801");
                                                            const v29895 = try s.call(v29891, c.pi_js_undefined(), &.{ v29892, v29893, v29894 });
                                                            break :conditional29889 v29895;
                                                        } else {
                                                            const v29896 = try o.importValue(&s, graph, "type/index.mjs", "*");
                                                            const v29897 = try s.text("IsUnion");
                                                            const v29898 = try s.own(try js.getKey(e, v29896, v29897));
                                                            const v29899 = try o.lookup(&s, frame, "binding29795");
                                                            const v29900 = try s.call(v29898, v29896, &.{v29899});
                                                            const v29902 = conditional29901: {
                                                                if (s.truthy(v29900)) {
                                                                    const v29903 = try o.importValue(&s, graph, "value/default/from_union.mjs", "FromUnion");
                                                                    const v29904 = try o.lookup(&s, frame, "binding29794");
                                                                    const v29905 = try o.lookup(&s, frame, "binding29795");
                                                                    const v29906 = try o.lookup(&s, frame, "binding29801");
                                                                    const v29907 = try s.call(v29903, c.pi_js_undefined(), &.{ v29904, v29905, v29906 });
                                                                    break :conditional29901 v29907;
                                                                } else {
                                                                    const v29908 = try o.lookup(&s, frame, "binding29801");
                                                                    break :conditional29901 v29908;
                                                                }
                                                            };
                                                            break :conditional29889 v29902;
                                                        }
                                                    };
                                                    break :conditional29877 v29890;
                                                }
                                            };
                                            break :conditional29865 v29878;
                                        }
                                    };
                                    break :conditional29853 v29866;
                                }
                            };
                            break :conditional29841 v29854;
                        }
                    };
                    break :conditional29829 v29842;
                }
            };
            break :conditional29817 v29830;
        }
    };
    return c.JS_DupValue(e.context, v29818);
}
