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
    const namespace = try s.get(modules, "value/convert/try/try_null.mjs");
    const frame = try o.frame(&s, c.pi_js_null());
    try s.put(frame, "@this", c.pi_js_undefined());
    try s.put(try s.get(graph, "frames"), "value/convert/try/try_null.mjs", frame);
    const bindings = try s.object();
    try s.put(try s.get(graph, "bindings"), "value/convert/try/try_null.mjs", bindings);
    const v27745 = try s.own(try ordinary.create(e, "FromBigInt", 1, body27729, &.{ graph, frame }));
    try o.assign(&s, frame, "binding27724", v27745);
    const v27760 = try s.own(try ordinary.create(e, "FromBoolean", 1, body27746, &.{ graph, frame }));
    try o.assign(&s, frame, "binding27725", v27760);
    const v27775 = try s.own(try ordinary.create(e, "FromNumber", 1, body27761, &.{ graph, frame }));
    try o.assign(&s, frame, "binding27726", v27775);
    const v27824 = try s.own(try ordinary.create(e, "FromString", 1, body27776, &.{ graph, frame }));
    try o.assign(&s, frame, "binding27727", v27824);
    const v27888 = try s.own(try ordinary.create(e, "TryNull", 1, body27825, &.{ graph, frame }));
    try o.assign(&s, frame, "binding27728", v27888);
    const v27889 = try o.lookup(&s, frame, "binding27728");
    try s.put(namespace, "TryNull", v27889);
    const v27890 = try o.lookup(&s, frame, "binding27728");
    try s.put(namespace, "TryNull", v27890);
    try s.put(bindings, "TryNull", try s.text("binding27728"));
}
fn body27729(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v27731 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding27730", v27731);
    const v27732 = try o.importValue(&s, graph, "guard/index.mjs", "Guard");
    const v27733 = try s.text("IsEqual");
    const v27734 = try s.own(try js.getKey(e, v27732, v27733));
    const v27735 = try o.lookup(&s, frame, "binding27730");
    const v27736 = try s.global("BigInt");
    const v27737 = try s.call(v27736, c.pi_js_undefined(), &.{c.JS_NewFloat64(e.context, 0)});
    const v27738 = try s.call(v27734, v27732, &.{ v27735, v27737 });
    const v27740 = conditional27739: {
        if (s.truthy(v27738)) {
            const v27741 = try o.importValue(&s, graph, "value/convert/try/try_result.mjs", "Ok");
            const v27742 = try s.call(v27741, c.pi_js_undefined(), &.{c.pi_js_null()});
            break :conditional27739 v27742;
        } else {
            const v27743 = try o.importValue(&s, graph, "value/convert/try/try_result.mjs", "Fail");
            const v27744 = try s.call(v27743, c.pi_js_undefined(), &.{});
            break :conditional27739 v27744;
        }
    };
    return c.JS_DupValue(e.context, v27740);
}
fn body27746(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v27748 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding27747", v27748);
    const v27749 = try o.importValue(&s, graph, "guard/index.mjs", "Guard");
    const v27750 = try s.text("IsEqual");
    const v27751 = try s.own(try js.getKey(e, v27749, v27750));
    const v27752 = try o.lookup(&s, frame, "binding27747");
    const v27753 = try s.call(v27751, v27749, &.{ v27752, o.boolean(&s, false) });
    const v27755 = conditional27754: {
        if (s.truthy(v27753)) {
            const v27756 = try o.importValue(&s, graph, "value/convert/try/try_result.mjs", "Ok");
            const v27757 = try s.call(v27756, c.pi_js_undefined(), &.{c.pi_js_null()});
            break :conditional27754 v27757;
        } else {
            const v27758 = try o.importValue(&s, graph, "value/convert/try/try_result.mjs", "Fail");
            const v27759 = try s.call(v27758, c.pi_js_undefined(), &.{});
            break :conditional27754 v27759;
        }
    };
    return c.JS_DupValue(e.context, v27755);
}
fn body27761(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v27763 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding27762", v27763);
    const v27764 = try o.importValue(&s, graph, "guard/index.mjs", "Guard");
    const v27765 = try s.text("IsEqual");
    const v27766 = try s.own(try js.getKey(e, v27764, v27765));
    const v27767 = try o.lookup(&s, frame, "binding27762");
    const v27768 = try s.call(v27766, v27764, &.{ v27767, c.JS_NewFloat64(e.context, 0) });
    const v27770 = conditional27769: {
        if (s.truthy(v27768)) {
            const v27771 = try o.importValue(&s, graph, "value/convert/try/try_result.mjs", "Ok");
            const v27772 = try s.call(v27771, c.pi_js_undefined(), &.{c.pi_js_null()});
            break :conditional27769 v27772;
        } else {
            const v27773 = try o.importValue(&s, graph, "value/convert/try/try_result.mjs", "Fail");
            const v27774 = try s.call(v27773, c.pi_js_undefined(), &.{});
            break :conditional27769 v27774;
        }
    };
    return c.JS_DupValue(e.context, v27770);
}
fn body27776(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v27780 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding27777", v27780);
    const v27783 = try o.lookup(&s, frame, "binding27777");
    const v27784 = try s.text("toLowerCase");
    const v27785 = try s.own(try js.getKey(e, v27783, v27784));
    const v27786 = try s.call(v27785, v27783, &.{});
    try o.assign(&s, frame, "binding27781", v27786);
    const v27787 = try o.importValue(&s, graph, "guard/index.mjs", "Guard");
    const v27788 = try s.text("IsEqual");
    const v27789 = try s.own(try js.getKey(e, v27787, v27788));
    const v27790 = try o.lookup(&s, frame, "binding27781");
    const v27791 = try s.text("undefined");
    const v27792 = try s.call(v27789, v27787, &.{ v27790, v27791 });
    const v27794 = logical27793: {
        if (s.truthy(v27792)) break :logical27793 v27792;
        const v27795 = try o.importValue(&s, graph, "guard/index.mjs", "Guard");
        const v27796 = try s.text("IsEqual");
        const v27797 = try s.own(try js.getKey(e, v27795, v27796));
        const v27798 = try o.lookup(&s, frame, "binding27781");
        const v27799 = try s.text("null");
        const v27800 = try s.call(v27797, v27795, &.{ v27798, v27799 });
        break :logical27793 v27800;
    };
    const v27802 = logical27801: {
        if (s.truthy(v27794)) break :logical27801 v27794;
        const v27803 = try o.importValue(&s, graph, "guard/index.mjs", "Guard");
        const v27804 = try s.text("IsEqual");
        const v27805 = try s.own(try js.getKey(e, v27803, v27804));
        const v27806 = try o.lookup(&s, frame, "binding27777");
        const v27807 = try s.text("");
        const v27808 = try s.call(v27805, v27803, &.{ v27806, v27807 });
        break :logical27801 v27808;
    };
    const v27810 = logical27809: {
        if (s.truthy(v27802)) break :logical27809 v27802;
        const v27811 = try o.importValue(&s, graph, "guard/index.mjs", "Guard");
        const v27812 = try s.text("IsEqual");
        const v27813 = try s.own(try js.getKey(e, v27811, v27812));
        const v27814 = try o.lookup(&s, frame, "binding27777");
        const v27815 = try s.text("0");
        const v27816 = try s.call(v27813, v27811, &.{ v27814, v27815 });
        break :logical27809 v27816;
    };
    try o.assign(&s, frame, "binding27782", v27810);
    const v27817 = try o.lookup(&s, frame, "binding27782");
    const v27819 = conditional27818: {
        if (s.truthy(v27817)) {
            const v27820 = try o.importValue(&s, graph, "value/convert/try/try_result.mjs", "Ok");
            const v27821 = try s.call(v27820, c.pi_js_undefined(), &.{c.pi_js_null()});
            break :conditional27818 v27821;
        } else {
            const v27822 = try o.importValue(&s, graph, "value/convert/try/try_result.mjs", "Fail");
            const v27823 = try s.call(v27822, c.pi_js_undefined(), &.{});
            break :conditional27818 v27823;
        }
    };
    return c.JS_DupValue(e.context, v27819);
}
fn body27825(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v27827 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding27826", v27827);
    const v27828 = try o.importValue(&s, graph, "guard/index.mjs", "Guard");
    const v27829 = try s.text("IsBigInt");
    const v27830 = try s.own(try js.getKey(e, v27828, v27829));
    const v27831 = try o.lookup(&s, frame, "binding27826");
    const v27832 = try s.call(v27830, v27828, &.{v27831});
    const v27834 = conditional27833: {
        if (s.truthy(v27832)) {
            const v27835 = try o.lookup(&s, frame, "binding27724");
            const v27836 = try o.lookup(&s, frame, "binding27826");
            const v27837 = try s.call(v27835, c.pi_js_undefined(), &.{v27836});
            break :conditional27833 v27837;
        } else {
            const v27838 = try o.importValue(&s, graph, "guard/index.mjs", "Guard");
            const v27839 = try s.text("IsBoolean");
            const v27840 = try s.own(try js.getKey(e, v27838, v27839));
            const v27841 = try o.lookup(&s, frame, "binding27826");
            const v27842 = try s.call(v27840, v27838, &.{v27841});
            const v27844 = conditional27843: {
                if (s.truthy(v27842)) {
                    const v27845 = try o.lookup(&s, frame, "binding27725");
                    const v27846 = try o.lookup(&s, frame, "binding27826");
                    const v27847 = try s.call(v27845, c.pi_js_undefined(), &.{v27846});
                    break :conditional27843 v27847;
                } else {
                    const v27848 = try o.importValue(&s, graph, "guard/index.mjs", "Guard");
                    const v27849 = try s.text("IsNumber");
                    const v27850 = try s.own(try js.getKey(e, v27848, v27849));
                    const v27851 = try o.lookup(&s, frame, "binding27826");
                    const v27852 = try s.call(v27850, v27848, &.{v27851});
                    const v27854 = conditional27853: {
                        if (s.truthy(v27852)) {
                            const v27855 = try o.lookup(&s, frame, "binding27726");
                            const v27856 = try o.lookup(&s, frame, "binding27826");
                            const v27857 = try s.call(v27855, c.pi_js_undefined(), &.{v27856});
                            break :conditional27853 v27857;
                        } else {
                            const v27858 = try o.importValue(&s, graph, "guard/index.mjs", "Guard");
                            const v27859 = try s.text("IsNull");
                            const v27860 = try s.own(try js.getKey(e, v27858, v27859));
                            const v27861 = try o.lookup(&s, frame, "binding27826");
                            const v27862 = try s.call(v27860, v27858, &.{v27861});
                            const v27864 = conditional27863: {
                                if (s.truthy(v27862)) {
                                    const v27865 = try o.importValue(&s, graph, "value/convert/try/try_result.mjs", "Ok");
                                    const v27866 = try s.call(v27865, c.pi_js_undefined(), &.{c.pi_js_null()});
                                    break :conditional27863 v27866;
                                } else {
                                    const v27867 = try o.importValue(&s, graph, "guard/index.mjs", "Guard");
                                    const v27868 = try s.text("IsString");
                                    const v27869 = try s.own(try js.getKey(e, v27867, v27868));
                                    const v27870 = try o.lookup(&s, frame, "binding27826");
                                    const v27871 = try s.call(v27869, v27867, &.{v27870});
                                    const v27873 = conditional27872: {
                                        if (s.truthy(v27871)) {
                                            const v27874 = try o.lookup(&s, frame, "binding27727");
                                            const v27875 = try o.lookup(&s, frame, "binding27826");
                                            const v27876 = try s.call(v27874, c.pi_js_undefined(), &.{v27875});
                                            break :conditional27872 v27876;
                                        } else {
                                            const v27877 = try o.importValue(&s, graph, "guard/index.mjs", "Guard");
                                            const v27878 = try s.text("IsUndefined");
                                            const v27879 = try s.own(try js.getKey(e, v27877, v27878));
                                            const v27880 = try o.lookup(&s, frame, "binding27826");
                                            const v27881 = try s.call(v27879, v27877, &.{v27880});
                                            const v27883 = conditional27882: {
                                                if (s.truthy(v27881)) {
                                                    const v27884 = try o.importValue(&s, graph, "value/convert/try/try_result.mjs", "Ok");
                                                    const v27885 = try s.call(v27884, c.pi_js_undefined(), &.{c.pi_js_null()});
                                                    break :conditional27882 v27885;
                                                } else {
                                                    const v27886 = try o.importValue(&s, graph, "value/convert/try/try_result.mjs", "Fail");
                                                    const v27887 = try s.call(v27886, c.pi_js_undefined(), &.{});
                                                    break :conditional27882 v27887;
                                                }
                                            };
                                            break :conditional27872 v27883;
                                        }
                                    };
                                    break :conditional27863 v27873;
                                }
                            };
                            break :conditional27853 v27864;
                        }
                    };
                    break :conditional27843 v27854;
                }
            };
            break :conditional27833 v27844;
        }
    };
    return c.JS_DupValue(e.context, v27834);
}
