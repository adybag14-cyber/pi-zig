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
    const namespace = try s.get(modules, "value/shared/union_priority_sort.mjs");
    const frame = try o.frame(&s, c.pi_js_null());
    try s.put(frame, "@this", c.pi_js_undefined());
    try s.put(try s.get(graph, "frames"), "value/shared/union_priority_sort.mjs", frame);
    const bindings = try s.object();
    try s.put(try s.get(graph, "bindings"), "value/shared/union_priority_sort.mjs", bindings);
    const v31722 = try s.own(try ordinary.create(e, "Modifiers", 2, body31693, &.{ graph, frame }));
    try o.assign(&s, frame, "binding31687", v31722);
    const v31749 = try s.own(try ordinary.create(e, "FromProperties", 1, body31723, &.{ graph, frame }));
    try o.assign(&s, frame, "binding31688", v31749);
    const v31758 = try s.own(try ordinary.create(e, "FromPriorityTypes", 1, body31750, &.{ graph, frame }));
    try o.assign(&s, frame, "binding31689", v31758);
    const v31774 = try s.own(try ordinary.create(e, "FromTypes", 1, body31759, &.{ graph, frame }));
    try o.assign(&s, frame, "binding31690", v31774);
    const v31863 = try s.own(try ordinary.create(e, "FromType", 1, body31775, &.{ graph, frame }));
    try o.assign(&s, frame, "binding31691", v31863);
    const v31873 = try s.own(try ordinary.create(e, "UnionPrioritySort", 1, body31864, &.{ graph, frame }));
    try o.assign(&s, frame, "binding31692", v31873);
    const v31874 = try o.lookup(&s, frame, "binding31692");
    try s.put(namespace, "UnionPrioritySort", v31874);
    const v31875 = try o.lookup(&s, frame, "binding31692");
    try s.put(namespace, "UnionPrioritySort", v31875);
    try s.put(bindings, "UnionPrioritySort", try s.text("binding31692"));
}
fn body31693(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v31696 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding31694", v31696);
    const v31697 = if (args.len > 1) args[1] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding31695", v31697);
    const v31698 = try o.importValue(&s, graph, "guard/index.mjs", "default");
    const v31699 = try s.text("Keys");
    const v31700 = try s.own(try js.getKey(e, v31698, v31699));
    const v31701 = try o.lookup(&s, frame, "binding31694");
    const v31702 = try s.call(v31700, v31698, &.{v31701});
    var iterator31703 = try o.iterator(e, v31702);
    defer iterator31703.deinit();
    errdefer iterator31703.closePreserving();
    loop31705: while (try iterator31703.next()) |next31704| {
        defer e.freeValue(next31704);
        const iteration31706 = try o.frame(&s, frame);
        try o.assign(&s, iteration31706, "binding31707", next31704);
        const v31708 = try o.importValue(&s, graph, "guard/index.mjs", "default");
        const v31709 = try s.text("HasPropertyKey");
        const v31710 = try s.own(try js.getKey(e, v31708, v31709));
        const v31711 = try o.lookup(&s, iteration31706, "binding31695");
        const v31712 = try o.lookup(&s, iteration31706, "binding31707");
        const v31713 = try s.call(v31710, v31708, &.{ v31711, v31712 });
        if (s.truthy(v31713)) {
            continue :loop31705;
        }
        const v31714 = try o.lookup(&s, iteration31706, "binding31695");
        const v31715 = try o.lookup(&s, iteration31706, "binding31707");
        const v31716 = try o.propertyKey(&s, v31715);
        const v31717 = try o.lookup(&s, iteration31706, "binding31694");
        const v31718 = try o.lookup(&s, iteration31706, "binding31707");
        const v31719 = try o.propertyKey(&s, v31718);
        const v31720 = try s.own(try js.getKey(e, v31717, v31719));
        try js.setKey(e, v31714, v31716, v31720);
    }
    try iterator31703.close();
    const v31721 = try o.lookup(&s, frame, "binding31695");
    return c.JS_DupValue(e.context, v31721);
}
fn body31723(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v31726 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding31724", v31726);
    const v31728 = try s.object();
    try o.assign(&s, frame, "binding31727", v31728);
    const v31729 = try o.importValue(&s, graph, "guard/index.mjs", "default");
    const v31730 = try s.text("Keys");
    const v31731 = try s.own(try js.getKey(e, v31729, v31730));
    const v31732 = try o.lookup(&s, frame, "binding31724");
    const v31733 = try s.call(v31731, v31729, &.{v31732});
    var iterator31734 = try o.iterator(e, v31733);
    defer iterator31734.deinit();
    errdefer iterator31734.closePreserving();
    while (try iterator31734.next()) |next31735| {
        defer e.freeValue(next31735);
        const iteration31737 = try o.frame(&s, frame);
        try o.assign(&s, iteration31737, "binding31738", next31735);
        const v31739 = try o.lookup(&s, iteration31737, "binding31727");
        const v31740 = try o.lookup(&s, iteration31737, "binding31738");
        const v31741 = try o.propertyKey(&s, v31740);
        const v31742 = try o.lookup(&s, iteration31737, "binding31691");
        const v31743 = try o.lookup(&s, iteration31737, "binding31724");
        const v31744 = try o.lookup(&s, iteration31737, "binding31738");
        const v31745 = try o.propertyKey(&s, v31744);
        const v31746 = try s.own(try js.getKey(e, v31743, v31745));
        const v31747 = try s.call(v31742, c.pi_js_undefined(), &.{v31746});
        try js.setKey(e, v31739, v31741, v31747);
    }
    try iterator31734.close();
    const v31748 = try o.lookup(&s, frame, "binding31727");
    return c.JS_DupValue(e.context, v31748);
}
fn body31750(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v31752 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding31751", v31752);
    const v31753 = try o.lookup(&s, frame, "binding31690");
    const v31754 = try o.importValue(&s, graph, "type/index.mjs", "Priority");
    const v31755 = try o.lookup(&s, frame, "binding31751");
    const v31756 = try s.call(v31754, c.pi_js_undefined(), &.{v31755});
    const v31757 = try s.call(v31753, c.pi_js_undefined(), &.{v31756});
    return c.JS_DupValue(e.context, v31757);
}
fn body31765(e: *Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    _ = roots[0];
    const frame = try o.frame(&s, roots[1]);
    _ = try o.lookup(&s, frame, "@this");
    const v31768 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding31767", v31768);
    const v31769 = try o.lookup(&s, frame, "binding31691");
    const v31770 = try o.lookup(&s, frame, "binding31767");
    const v31771 = try s.call(v31769, c.pi_js_undefined(), &.{v31770});
    return c.JS_DupValue(e.context, v31771);
}
fn body31765C(ctx: ?*c.JSContext, receiver: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const e = Engine.fromContext(ctx.?);
    return body31765(e, receiver, if (argc > 0) argv[0..@intCast(argc)] else &.{}, roots[0..2]) catch |err| sdk.fail(e, err);
}
fn body31759(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v31761 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding31760", v31761);
    const v31762 = try o.lookup(&s, frame, "binding31760");
    const v31763 = try s.text("map");
    const v31764 = try s.own(try js.getKey(e, v31762, v31763));
    const v31772 = try o.arrow(&s, "", 1, body31765C, &.{ graph, frame });
    const v31773 = try s.call(v31764, v31762, &.{v31772});
    return c.JS_DupValue(e.context, v31773);
}
fn body31775(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v31778 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding31776", v31778);
    const v31780 = try o.importValue(&s, graph, "type/index.mjs", "IsArray");
    const v31781 = try o.lookup(&s, frame, "binding31776");
    const v31782 = try s.call(v31780, c.pi_js_undefined(), &.{v31781});
    const v31784 = conditional31783: {
        if (s.truthy(v31782)) {
            const v31785 = try o.importValue(&s, graph, "type/index.mjs", "Array");
            const v31786 = try o.lookup(&s, frame, "binding31691");
            const v31787 = try o.lookup(&s, frame, "binding31776");
            const v31788 = try s.text("items");
            const v31789 = try s.own(try js.getKey(e, v31787, v31788));
            const v31790 = try s.call(v31786, c.pi_js_undefined(), &.{v31789});
            const v31791 = try o.importValue(&s, graph, "type/index.mjs", "ArrayOptions");
            const v31792 = try o.lookup(&s, frame, "binding31776");
            const v31793 = try s.call(v31791, c.pi_js_undefined(), &.{v31792});
            const v31794 = try s.call(v31785, c.pi_js_undefined(), &.{ v31790, v31793 });
            break :conditional31783 v31794;
        } else {
            const v31795 = try o.importValue(&s, graph, "type/index.mjs", "IsIntersect");
            const v31796 = try o.lookup(&s, frame, "binding31776");
            const v31797 = try s.call(v31795, c.pi_js_undefined(), &.{v31796});
            const v31799 = conditional31798: {
                if (s.truthy(v31797)) {
                    const v31800 = try o.importValue(&s, graph, "type/index.mjs", "Intersect");
                    const v31801 = try o.lookup(&s, frame, "binding31690");
                    const v31802 = try o.lookup(&s, frame, "binding31776");
                    const v31803 = try s.text("allOf");
                    const v31804 = try s.own(try js.getKey(e, v31802, v31803));
                    const v31805 = try s.call(v31801, c.pi_js_undefined(), &.{v31804});
                    const v31806 = try s.call(v31800, c.pi_js_undefined(), &.{v31805});
                    break :conditional31798 v31806;
                } else {
                    const v31807 = try o.importValue(&s, graph, "type/index.mjs", "IsUnion");
                    const v31808 = try o.lookup(&s, frame, "binding31776");
                    const v31809 = try s.call(v31807, c.pi_js_undefined(), &.{v31808});
                    const v31811 = conditional31810: {
                        if (s.truthy(v31809)) {
                            const v31812 = try o.importValue(&s, graph, "type/index.mjs", "Union");
                            const v31813 = try o.lookup(&s, frame, "binding31689");
                            const v31814 = try o.lookup(&s, frame, "binding31776");
                            const v31815 = try s.text("anyOf");
                            const v31816 = try s.own(try js.getKey(e, v31814, v31815));
                            const v31817 = try s.call(v31813, c.pi_js_undefined(), &.{v31816});
                            const v31818 = try s.call(v31812, c.pi_js_undefined(), &.{v31817});
                            break :conditional31810 v31818;
                        } else {
                            const v31819 = try o.importValue(&s, graph, "type/index.mjs", "IsObject");
                            const v31820 = try o.lookup(&s, frame, "binding31776");
                            const v31821 = try s.call(v31819, c.pi_js_undefined(), &.{v31820});
                            const v31823 = conditional31822: {
                                if (s.truthy(v31821)) {
                                    const v31824 = try o.importValue(&s, graph, "type/index.mjs", "Object");
                                    const v31825 = try o.lookup(&s, frame, "binding31688");
                                    const v31826 = try o.lookup(&s, frame, "binding31776");
                                    const v31827 = try s.text("properties");
                                    const v31828 = try s.own(try js.getKey(e, v31826, v31827));
                                    const v31829 = try s.call(v31825, c.pi_js_undefined(), &.{v31828});
                                    const v31830 = try s.call(v31824, c.pi_js_undefined(), &.{v31829});
                                    break :conditional31822 v31830;
                                } else {
                                    const v31831 = try o.importValue(&s, graph, "type/index.mjs", "IsRecord");
                                    const v31832 = try o.lookup(&s, frame, "binding31776");
                                    const v31833 = try s.call(v31831, c.pi_js_undefined(), &.{v31832});
                                    const v31835 = conditional31834: {
                                        if (s.truthy(v31833)) {
                                            const v31836 = try o.importValue(&s, graph, "type/index.mjs", "Record");
                                            const v31837 = try o.importValue(&s, graph, "type/index.mjs", "RecordKey");
                                            const v31838 = try o.lookup(&s, frame, "binding31776");
                                            const v31839 = try s.call(v31837, c.pi_js_undefined(), &.{v31838});
                                            const v31840 = try o.lookup(&s, frame, "binding31691");
                                            const v31841 = try o.importValue(&s, graph, "type/index.mjs", "RecordValue");
                                            const v31842 = try o.lookup(&s, frame, "binding31776");
                                            const v31843 = try s.call(v31841, c.pi_js_undefined(), &.{v31842});
                                            const v31844 = try s.call(v31840, c.pi_js_undefined(), &.{v31843});
                                            const v31845 = try s.call(v31836, c.pi_js_undefined(), &.{ v31839, v31844 });
                                            break :conditional31834 v31845;
                                        } else {
                                            const v31846 = try o.importValue(&s, graph, "type/index.mjs", "IsTuple");
                                            const v31847 = try o.lookup(&s, frame, "binding31776");
                                            const v31848 = try s.call(v31846, c.pi_js_undefined(), &.{v31847});
                                            const v31850 = conditional31849: {
                                                if (s.truthy(v31848)) {
                                                    const v31851 = try o.importValue(&s, graph, "type/index.mjs", "Tuple");
                                                    const v31852 = try o.lookup(&s, frame, "binding31690");
                                                    const v31853 = try o.lookup(&s, frame, "binding31776");
                                                    const v31854 = try s.text("items");
                                                    const v31855 = try s.own(try js.getKey(e, v31853, v31854));
                                                    const v31856 = try s.call(v31852, c.pi_js_undefined(), &.{v31855});
                                                    const v31857 = try s.call(v31851, c.pi_js_undefined(), &.{v31856});
                                                    break :conditional31849 v31857;
                                                } else {
                                                    const v31858 = try o.lookup(&s, frame, "binding31776");
                                                    break :conditional31849 v31858;
                                                }
                                            };
                                            break :conditional31834 v31850;
                                        }
                                    };
                                    break :conditional31822 v31835;
                                }
                            };
                            break :conditional31810 v31823;
                        }
                    };
                    break :conditional31798 v31811;
                }
            };
            break :conditional31783 v31799;
        }
    };
    try o.assign(&s, frame, "binding31779", v31784);
    const v31859 = try o.lookup(&s, frame, "binding31687");
    const v31860 = try o.lookup(&s, frame, "binding31776");
    const v31861 = try o.lookup(&s, frame, "binding31779");
    const v31862 = try s.call(v31859, c.pi_js_undefined(), &.{ v31860, v31861 });
    return c.JS_DupValue(e.context, v31862);
}
fn body31864(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    _ = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v31867 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding31865", v31867);
    const v31869 = try o.lookup(&s, frame, "binding31691");
    const v31870 = try o.lookup(&s, frame, "binding31865");
    const v31871 = try s.call(v31869, c.pi_js_undefined(), &.{v31870});
    try o.assign(&s, frame, "binding31868", v31871);
    const v31872 = try o.lookup(&s, frame, "binding31868");
    return c.JS_DupValue(e.context, v31872);
}
