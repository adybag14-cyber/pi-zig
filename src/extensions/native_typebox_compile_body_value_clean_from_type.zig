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
    const namespace = try s.get(modules, "value/clean/from_type.mjs");
    const frame = try o.frame(&s, c.pi_js_null());
    try s.put(frame, "@this", c.pi_js_undefined());
    try s.put(try s.get(graph, "frames"), "value/clean/from_type.mjs", frame);
    const bindings = try s.object();
    try s.put(try s.get(graph, "bindings"), "value/clean/from_type.mjs", bindings);
    const v23919 = try s.own(try ordinary.create(e, "FromType", 3, body23815, &.{ graph, frame }));
    try o.assign(&s, frame, "binding23814", v23919);
    const v23920 = try o.lookup(&s, frame, "binding23814");
    try s.put(namespace, "FromType", v23920);
    const v23921 = try o.lookup(&s, frame, "binding23814");
    try s.put(namespace, "FromType", v23921);
    try s.put(bindings, "FromType", try s.text("binding23814"));
}
fn body23815(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v23819 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding23816", v23819);
    const v23820 = if (args.len > 1) args[1] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding23817", v23820);
    const v23821 = if (args.len > 2) args[2] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding23818", v23821);
    const v23822 = try o.importValue(&s, graph, "type/index.mjs", "*");
    const v23823 = try s.text("IsArray");
    const v23824 = try s.own(try js.getKey(e, v23822, v23823));
    const v23825 = try o.lookup(&s, frame, "binding23817");
    const v23826 = try s.call(v23824, v23822, &.{v23825});
    const v23828 = conditional23827: {
        if (s.truthy(v23826)) {
            const v23829 = try o.importValue(&s, graph, "value/clean/from_array.mjs", "FromArray");
            const v23830 = try o.lookup(&s, frame, "binding23816");
            const v23831 = try o.lookup(&s, frame, "binding23817");
            const v23832 = try o.lookup(&s, frame, "binding23818");
            const v23833 = try s.call(v23829, c.pi_js_undefined(), &.{ v23830, v23831, v23832 });
            break :conditional23827 v23833;
        } else {
            const v23834 = try o.importValue(&s, graph, "type/index.mjs", "*");
            const v23835 = try s.text("IsCyclic");
            const v23836 = try s.own(try js.getKey(e, v23834, v23835));
            const v23837 = try o.lookup(&s, frame, "binding23817");
            const v23838 = try s.call(v23836, v23834, &.{v23837});
            const v23840 = conditional23839: {
                if (s.truthy(v23838)) {
                    const v23841 = try o.importValue(&s, graph, "value/clean/from_cyclic.mjs", "FromCyclic");
                    const v23842 = try o.lookup(&s, frame, "binding23816");
                    const v23843 = try o.lookup(&s, frame, "binding23817");
                    const v23844 = try o.lookup(&s, frame, "binding23818");
                    const v23845 = try s.call(v23841, c.pi_js_undefined(), &.{ v23842, v23843, v23844 });
                    break :conditional23839 v23845;
                } else {
                    const v23846 = try o.importValue(&s, graph, "type/index.mjs", "*");
                    const v23847 = try s.text("IsIntersect");
                    const v23848 = try s.own(try js.getKey(e, v23846, v23847));
                    const v23849 = try o.lookup(&s, frame, "binding23817");
                    const v23850 = try s.call(v23848, v23846, &.{v23849});
                    const v23852 = conditional23851: {
                        if (s.truthy(v23850)) {
                            const v23853 = try o.importValue(&s, graph, "value/clean/from_intersect.mjs", "FromIntersect");
                            const v23854 = try o.lookup(&s, frame, "binding23816");
                            const v23855 = try o.lookup(&s, frame, "binding23817");
                            const v23856 = try o.lookup(&s, frame, "binding23818");
                            const v23857 = try s.call(v23853, c.pi_js_undefined(), &.{ v23854, v23855, v23856 });
                            break :conditional23851 v23857;
                        } else {
                            const v23858 = try o.importValue(&s, graph, "type/index.mjs", "*");
                            const v23859 = try s.text("IsObject");
                            const v23860 = try s.own(try js.getKey(e, v23858, v23859));
                            const v23861 = try o.lookup(&s, frame, "binding23817");
                            const v23862 = try s.call(v23860, v23858, &.{v23861});
                            const v23864 = conditional23863: {
                                if (s.truthy(v23862)) {
                                    const v23865 = try o.importValue(&s, graph, "value/clean/from_object.mjs", "FromObject");
                                    const v23866 = try o.lookup(&s, frame, "binding23816");
                                    const v23867 = try o.lookup(&s, frame, "binding23817");
                                    const v23868 = try o.lookup(&s, frame, "binding23818");
                                    const v23869 = try s.call(v23865, c.pi_js_undefined(), &.{ v23866, v23867, v23868 });
                                    break :conditional23863 v23869;
                                } else {
                                    const v23870 = try o.importValue(&s, graph, "type/index.mjs", "*");
                                    const v23871 = try s.text("IsRecord");
                                    const v23872 = try s.own(try js.getKey(e, v23870, v23871));
                                    const v23873 = try o.lookup(&s, frame, "binding23817");
                                    const v23874 = try s.call(v23872, v23870, &.{v23873});
                                    const v23876 = conditional23875: {
                                        if (s.truthy(v23874)) {
                                            const v23877 = try o.importValue(&s, graph, "value/clean/from_record.mjs", "FromRecord");
                                            const v23878 = try o.lookup(&s, frame, "binding23816");
                                            const v23879 = try o.lookup(&s, frame, "binding23817");
                                            const v23880 = try o.lookup(&s, frame, "binding23818");
                                            const v23881 = try s.call(v23877, c.pi_js_undefined(), &.{ v23878, v23879, v23880 });
                                            break :conditional23875 v23881;
                                        } else {
                                            const v23882 = try o.importValue(&s, graph, "type/index.mjs", "*");
                                            const v23883 = try s.text("IsRef");
                                            const v23884 = try s.own(try js.getKey(e, v23882, v23883));
                                            const v23885 = try o.lookup(&s, frame, "binding23817");
                                            const v23886 = try s.call(v23884, v23882, &.{v23885});
                                            const v23888 = conditional23887: {
                                                if (s.truthy(v23886)) {
                                                    const v23889 = try o.importValue(&s, graph, "value/clean/from_ref.mjs", "FromRef");
                                                    const v23890 = try o.lookup(&s, frame, "binding23816");
                                                    const v23891 = try o.lookup(&s, frame, "binding23817");
                                                    const v23892 = try o.lookup(&s, frame, "binding23818");
                                                    const v23893 = try s.call(v23889, c.pi_js_undefined(), &.{ v23890, v23891, v23892 });
                                                    break :conditional23887 v23893;
                                                } else {
                                                    const v23894 = try o.importValue(&s, graph, "type/index.mjs", "*");
                                                    const v23895 = try s.text("IsTuple");
                                                    const v23896 = try s.own(try js.getKey(e, v23894, v23895));
                                                    const v23897 = try o.lookup(&s, frame, "binding23817");
                                                    const v23898 = try s.call(v23896, v23894, &.{v23897});
                                                    const v23900 = conditional23899: {
                                                        if (s.truthy(v23898)) {
                                                            const v23901 = try o.importValue(&s, graph, "value/clean/from_tuple.mjs", "FromTuple");
                                                            const v23902 = try o.lookup(&s, frame, "binding23816");
                                                            const v23903 = try o.lookup(&s, frame, "binding23817");
                                                            const v23904 = try o.lookup(&s, frame, "binding23818");
                                                            const v23905 = try s.call(v23901, c.pi_js_undefined(), &.{ v23902, v23903, v23904 });
                                                            break :conditional23899 v23905;
                                                        } else {
                                                            const v23906 = try o.importValue(&s, graph, "type/index.mjs", "*");
                                                            const v23907 = try s.text("IsUnion");
                                                            const v23908 = try s.own(try js.getKey(e, v23906, v23907));
                                                            const v23909 = try o.lookup(&s, frame, "binding23817");
                                                            const v23910 = try s.call(v23908, v23906, &.{v23909});
                                                            const v23912 = conditional23911: {
                                                                if (s.truthy(v23910)) {
                                                                    const v23913 = try o.importValue(&s, graph, "value/clean/from_union.mjs", "FromUnion");
                                                                    const v23914 = try o.lookup(&s, frame, "binding23816");
                                                                    const v23915 = try o.lookup(&s, frame, "binding23817");
                                                                    const v23916 = try o.lookup(&s, frame, "binding23818");
                                                                    const v23917 = try s.call(v23913, c.pi_js_undefined(), &.{ v23914, v23915, v23916 });
                                                                    break :conditional23911 v23917;
                                                                } else {
                                                                    const v23918 = try o.lookup(&s, frame, "binding23818");
                                                                    break :conditional23911 v23918;
                                                                }
                                                            };
                                                            break :conditional23899 v23912;
                                                        }
                                                    };
                                                    break :conditional23887 v23900;
                                                }
                                            };
                                            break :conditional23875 v23888;
                                        }
                                    };
                                    break :conditional23863 v23876;
                                }
                            };
                            break :conditional23851 v23864;
                        }
                    };
                    break :conditional23839 v23852;
                }
            };
            break :conditional23827 v23840;
        }
    };
    return c.JS_DupValue(e.context, v23828);
}
