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
    const namespace = try s.get(modules, "schema/engine/type.mjs");
    const frame = try o.frame(&s, c.pi_js_null());
    try s.put(frame, "@this", c.pi_js_undefined());
    try s.put(try s.get(graph, "frames"), "schema/engine/type.mjs", frame);
    const bindings = try s.object();
    try s.put(try s.get(graph, "bindings"), "schema/engine/type.mjs", bindings);
    const v16787 = try s.own(try ordinary.create(e, "BuildTypeName", 4, body16605, &.{ graph, frame }));
    try o.assign(&s, frame, "binding16598", v16787);
    const v16968 = try s.own(try ordinary.create(e, "CheckTypeName", 5, body16788, &.{ graph, frame }));
    try o.assign(&s, frame, "binding16599", v16968);
    const v16997 = try s.own(try ordinary.create(e, "BuildTypeNames", 4, body16969, &.{ graph, frame }));
    try o.assign(&s, frame, "binding16600", v16997);
    const v17026 = try s.own(try ordinary.create(e, "CheckTypeNames", 5, body16998, &.{ graph, frame }));
    try o.assign(&s, frame, "binding16601", v17026);
    const v17061 = try s.own(try ordinary.create(e, "BuildType", 4, body17027, &.{ graph, frame }));
    try o.assign(&s, frame, "binding16602", v17061);
    const v17098 = try s.own(try ordinary.create(e, "CheckType", 4, body17062, &.{ graph, frame }));
    try o.assign(&s, frame, "binding16603", v17098);
    const v17161 = try s.own(try ordinary.create(e, "ErrorType", 6, body17099, &.{ graph, frame }));
    try o.assign(&s, frame, "binding16604", v17161);
    const v17162 = try o.lookup(&s, frame, "binding16602");
    try s.put(namespace, "BuildType", v17162);
    const v17163 = try o.lookup(&s, frame, "binding16603");
    try s.put(namespace, "CheckType", v17163);
    const v17164 = try o.lookup(&s, frame, "binding16604");
    try s.put(namespace, "ErrorType", v17164);
    const v17165 = try o.lookup(&s, frame, "binding16602");
    try s.put(namespace, "BuildType", v17165);
    const v17166 = try o.lookup(&s, frame, "binding16603");
    try s.put(namespace, "CheckType", v17166);
    const v17167 = try o.lookup(&s, frame, "binding16604");
    try s.put(namespace, "ErrorType", v17167);
    try s.put(bindings, "BuildType", try s.text("binding16602"));
    try s.put(bindings, "CheckType", try s.text("binding16603"));
    try s.put(bindings, "ErrorType", try s.text("binding16604"));
}
fn body16605(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v16610 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding16606", v16610);
    const v16611 = if (args.len > 1) args[1] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding16607", v16611);
    const v16612 = if (args.len > 2) args[2] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding16608", v16612);
    const v16613 = if (args.len > 3) args[3] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding16609", v16613);
    const v16614 = try o.importValue(&s, graph, "guard/index.mjs", "Guard");
    const v16615 = try s.text("IsEqual");
    const v16616 = try s.own(try js.getKey(e, v16614, v16615));
    const v16617 = try o.lookup(&s, frame, "binding16608");
    const v16618 = try s.text("object");
    const v16619 = try s.call(v16616, v16614, &.{ v16617, v16618 });
    const v16621 = conditional16620: {
        if (s.truthy(v16619)) {
            const v16622 = try o.importValue(&s, graph, "guard/index.mjs", "EmitGuard");
            const v16623 = try s.text("IsObjectNotArray");
            const v16624 = try s.own(try js.getKey(e, v16622, v16623));
            const v16625 = try o.lookup(&s, frame, "binding16609");
            const v16626 = try s.call(v16624, v16622, &.{v16625});
            break :conditional16620 v16626;
        } else {
            const v16627 = try o.importValue(&s, graph, "guard/index.mjs", "Guard");
            const v16628 = try s.text("IsEqual");
            const v16629 = try s.own(try js.getKey(e, v16627, v16628));
            const v16630 = try o.lookup(&s, frame, "binding16608");
            const v16631 = try s.text("array");
            const v16632 = try s.call(v16629, v16627, &.{ v16630, v16631 });
            const v16634 = conditional16633: {
                if (s.truthy(v16632)) {
                    const v16635 = try o.importValue(&s, graph, "guard/index.mjs", "EmitGuard");
                    const v16636 = try s.text("IsArray");
                    const v16637 = try s.own(try js.getKey(e, v16635, v16636));
                    const v16638 = try o.lookup(&s, frame, "binding16609");
                    const v16639 = try s.call(v16637, v16635, &.{v16638});
                    break :conditional16633 v16639;
                } else {
                    const v16640 = try o.importValue(&s, graph, "guard/index.mjs", "Guard");
                    const v16641 = try s.text("IsEqual");
                    const v16642 = try s.own(try js.getKey(e, v16640, v16641));
                    const v16643 = try o.lookup(&s, frame, "binding16608");
                    const v16644 = try s.text("boolean");
                    const v16645 = try s.call(v16642, v16640, &.{ v16643, v16644 });
                    const v16647 = conditional16646: {
                        if (s.truthy(v16645)) {
                            const v16648 = try o.importValue(&s, graph, "guard/index.mjs", "EmitGuard");
                            const v16649 = try s.text("IsBoolean");
                            const v16650 = try s.own(try js.getKey(e, v16648, v16649));
                            const v16651 = try o.lookup(&s, frame, "binding16609");
                            const v16652 = try s.call(v16650, v16648, &.{v16651});
                            break :conditional16646 v16652;
                        } else {
                            const v16653 = try o.importValue(&s, graph, "guard/index.mjs", "Guard");
                            const v16654 = try s.text("IsEqual");
                            const v16655 = try s.own(try js.getKey(e, v16653, v16654));
                            const v16656 = try o.lookup(&s, frame, "binding16608");
                            const v16657 = try s.text("integer");
                            const v16658 = try s.call(v16655, v16653, &.{ v16656, v16657 });
                            const v16660 = conditional16659: {
                                if (s.truthy(v16658)) {
                                    const v16661 = try o.importValue(&s, graph, "guard/index.mjs", "EmitGuard");
                                    const v16662 = try s.text("IsInteger");
                                    const v16663 = try s.own(try js.getKey(e, v16661, v16662));
                                    const v16664 = try o.lookup(&s, frame, "binding16609");
                                    const v16665 = try s.call(v16663, v16661, &.{v16664});
                                    break :conditional16659 v16665;
                                } else {
                                    const v16666 = try o.importValue(&s, graph, "guard/index.mjs", "Guard");
                                    const v16667 = try s.text("IsEqual");
                                    const v16668 = try s.own(try js.getKey(e, v16666, v16667));
                                    const v16669 = try o.lookup(&s, frame, "binding16608");
                                    const v16670 = try s.text("number");
                                    const v16671 = try s.call(v16668, v16666, &.{ v16669, v16670 });
                                    const v16673 = conditional16672: {
                                        if (s.truthy(v16671)) {
                                            const v16674 = try o.importValue(&s, graph, "guard/index.mjs", "EmitGuard");
                                            const v16675 = try s.text("IsNumber");
                                            const v16676 = try s.own(try js.getKey(e, v16674, v16675));
                                            const v16677 = try o.lookup(&s, frame, "binding16609");
                                            const v16678 = try s.call(v16676, v16674, &.{v16677});
                                            break :conditional16672 v16678;
                                        } else {
                                            const v16679 = try o.importValue(&s, graph, "guard/index.mjs", "Guard");
                                            const v16680 = try s.text("IsEqual");
                                            const v16681 = try s.own(try js.getKey(e, v16679, v16680));
                                            const v16682 = try o.lookup(&s, frame, "binding16608");
                                            const v16683 = try s.text("null");
                                            const v16684 = try s.call(v16681, v16679, &.{ v16682, v16683 });
                                            const v16686 = conditional16685: {
                                                if (s.truthy(v16684)) {
                                                    const v16687 = try o.importValue(&s, graph, "guard/index.mjs", "EmitGuard");
                                                    const v16688 = try s.text("IsNull");
                                                    const v16689 = try s.own(try js.getKey(e, v16687, v16688));
                                                    const v16690 = try o.lookup(&s, frame, "binding16609");
                                                    const v16691 = try s.call(v16689, v16687, &.{v16690});
                                                    break :conditional16685 v16691;
                                                } else {
                                                    const v16692 = try o.importValue(&s, graph, "guard/index.mjs", "Guard");
                                                    const v16693 = try s.text("IsEqual");
                                                    const v16694 = try s.own(try js.getKey(e, v16692, v16693));
                                                    const v16695 = try o.lookup(&s, frame, "binding16608");
                                                    const v16696 = try s.text("string");
                                                    const v16697 = try s.call(v16694, v16692, &.{ v16695, v16696 });
                                                    const v16699 = conditional16698: {
                                                        if (s.truthy(v16697)) {
                                                            const v16700 = try o.importValue(&s, graph, "guard/index.mjs", "EmitGuard");
                                                            const v16701 = try s.text("IsString");
                                                            const v16702 = try s.own(try js.getKey(e, v16700, v16701));
                                                            const v16703 = try o.lookup(&s, frame, "binding16609");
                                                            const v16704 = try s.call(v16702, v16700, &.{v16703});
                                                            break :conditional16698 v16704;
                                                        } else {
                                                            const v16705 = try o.importValue(&s, graph, "guard/index.mjs", "Guard");
                                                            const v16706 = try s.text("IsEqual");
                                                            const v16707 = try s.own(try js.getKey(e, v16705, v16706));
                                                            const v16708 = try o.lookup(&s, frame, "binding16608");
                                                            const v16709 = try s.text("bigint");
                                                            const v16710 = try s.call(v16707, v16705, &.{ v16708, v16709 });
                                                            const v16712 = conditional16711: {
                                                                if (s.truthy(v16710)) {
                                                                    const v16713 = try o.importValue(&s, graph, "guard/index.mjs", "EmitGuard");
                                                                    const v16714 = try s.text("IsBigInt");
                                                                    const v16715 = try s.own(try js.getKey(e, v16713, v16714));
                                                                    const v16716 = try o.lookup(&s, frame, "binding16609");
                                                                    const v16717 = try s.call(v16715, v16713, &.{v16716});
                                                                    break :conditional16711 v16717;
                                                                } else {
                                                                    const v16718 = try o.importValue(&s, graph, "guard/index.mjs", "Guard");
                                                                    const v16719 = try s.text("IsEqual");
                                                                    const v16720 = try s.own(try js.getKey(e, v16718, v16719));
                                                                    const v16721 = try o.lookup(&s, frame, "binding16608");
                                                                    const v16722 = try s.text("constructor");
                                                                    const v16723 = try s.call(v16720, v16718, &.{ v16721, v16722 });
                                                                    const v16725 = conditional16724: {
                                                                        if (s.truthy(v16723)) {
                                                                            const v16726 = try o.importValue(&s, graph, "guard/index.mjs", "EmitGuard");
                                                                            const v16727 = try s.text("IsConstructor");
                                                                            const v16728 = try s.own(try js.getKey(e, v16726, v16727));
                                                                            const v16729 = try o.lookup(&s, frame, "binding16609");
                                                                            const v16730 = try s.call(v16728, v16726, &.{v16729});
                                                                            break :conditional16724 v16730;
                                                                        } else {
                                                                            const v16731 = try o.importValue(&s, graph, "guard/index.mjs", "Guard");
                                                                            const v16732 = try s.text("IsEqual");
                                                                            const v16733 = try s.own(try js.getKey(e, v16731, v16732));
                                                                            const v16734 = try o.lookup(&s, frame, "binding16608");
                                                                            const v16735 = try s.text("function");
                                                                            const v16736 = try s.call(v16733, v16731, &.{ v16734, v16735 });
                                                                            const v16738 = conditional16737: {
                                                                                if (s.truthy(v16736)) {
                                                                                    const v16739 = try o.importValue(&s, graph, "guard/index.mjs", "EmitGuard");
                                                                                    const v16740 = try s.text("IsFunction");
                                                                                    const v16741 = try s.own(try js.getKey(e, v16739, v16740));
                                                                                    const v16742 = try o.lookup(&s, frame, "binding16609");
                                                                                    const v16743 = try s.call(v16741, v16739, &.{v16742});
                                                                                    break :conditional16737 v16743;
                                                                                } else {
                                                                                    const v16744 = try o.importValue(&s, graph, "guard/index.mjs", "Guard");
                                                                                    const v16745 = try s.text("IsEqual");
                                                                                    const v16746 = try s.own(try js.getKey(e, v16744, v16745));
                                                                                    const v16747 = try o.lookup(&s, frame, "binding16608");
                                                                                    const v16748 = try s.text("symbol");
                                                                                    const v16749 = try s.call(v16746, v16744, &.{ v16747, v16748 });
                                                                                    const v16751 = conditional16750: {
                                                                                        if (s.truthy(v16749)) {
                                                                                            const v16752 = try o.importValue(&s, graph, "guard/index.mjs", "EmitGuard");
                                                                                            const v16753 = try s.text("IsSymbol");
                                                                                            const v16754 = try s.own(try js.getKey(e, v16752, v16753));
                                                                                            const v16755 = try o.lookup(&s, frame, "binding16609");
                                                                                            const v16756 = try s.call(v16754, v16752, &.{v16755});
                                                                                            break :conditional16750 v16756;
                                                                                        } else {
                                                                                            const v16757 = try o.importValue(&s, graph, "guard/index.mjs", "Guard");
                                                                                            const v16758 = try s.text("IsEqual");
                                                                                            const v16759 = try s.own(try js.getKey(e, v16757, v16758));
                                                                                            const v16760 = try o.lookup(&s, frame, "binding16608");
                                                                                            const v16761 = try s.text("undefined");
                                                                                            const v16762 = try s.call(v16759, v16757, &.{ v16760, v16761 });
                                                                                            const v16764 = conditional16763: {
                                                                                                if (s.truthy(v16762)) {
                                                                                                    const v16765 = try o.importValue(&s, graph, "guard/index.mjs", "EmitGuard");
                                                                                                    const v16766 = try s.text("IsUndefined");
                                                                                                    const v16767 = try s.own(try js.getKey(e, v16765, v16766));
                                                                                                    const v16768 = try o.lookup(&s, frame, "binding16609");
                                                                                                    const v16769 = try s.call(v16767, v16765, &.{v16768});
                                                                                                    break :conditional16763 v16769;
                                                                                                } else {
                                                                                                    const v16770 = try o.importValue(&s, graph, "guard/index.mjs", "Guard");
                                                                                                    const v16771 = try s.text("IsEqual");
                                                                                                    const v16772 = try s.own(try js.getKey(e, v16770, v16771));
                                                                                                    const v16773 = try o.lookup(&s, frame, "binding16608");
                                                                                                    const v16774 = try s.text("void");
                                                                                                    const v16775 = try s.call(v16772, v16770, &.{ v16773, v16774 });
                                                                                                    const v16777 = conditional16776: {
                                                                                                        if (s.truthy(v16775)) {
                                                                                                            const v16778 = try o.importValue(&s, graph, "guard/index.mjs", "EmitGuard");
                                                                                                            const v16779 = try s.text("IsUndefined");
                                                                                                            const v16780 = try s.own(try js.getKey(e, v16778, v16779));
                                                                                                            const v16781 = try o.lookup(&s, frame, "binding16609");
                                                                                                            const v16782 = try s.call(v16780, v16778, &.{v16781});
                                                                                                            break :conditional16776 v16782;
                                                                                                        } else {
                                                                                                            const v16783 = try o.importValue(&s, graph, "guard/index.mjs", "EmitGuard");
                                                                                                            const v16784 = try s.text("Constant");
                                                                                                            const v16785 = try s.own(try js.getKey(e, v16783, v16784));
                                                                                                            const v16786 = try s.call(v16785, v16783, &.{o.boolean(&s, true)});
                                                                                                            break :conditional16776 v16786;
                                                                                                        }
                                                                                                    };
                                                                                                    break :conditional16763 v16777;
                                                                                                }
                                                                                            };
                                                                                            break :conditional16750 v16764;
                                                                                        }
                                                                                    };
                                                                                    break :conditional16737 v16751;
                                                                                }
                                                                            };
                                                                            break :conditional16724 v16738;
                                                                        }
                                                                    };
                                                                    break :conditional16711 v16725;
                                                                }
                                                            };
                                                            break :conditional16698 v16712;
                                                        }
                                                    };
                                                    break :conditional16685 v16699;
                                                }
                                            };
                                            break :conditional16672 v16686;
                                        }
                                    };
                                    break :conditional16659 v16673;
                                }
                            };
                            break :conditional16646 v16660;
                        }
                    };
                    break :conditional16633 v16647;
                }
            };
            break :conditional16620 v16634;
        }
    };
    return c.JS_DupValue(e.context, v16621);
}
fn body16788(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v16794 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding16789", v16794);
    const v16795 = if (args.len > 1) args[1] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding16790", v16795);
    const v16796 = if (args.len > 2) args[2] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding16791", v16796);
    const v16797 = if (args.len > 3) args[3] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding16792", v16797);
    const v16798 = if (args.len > 4) args[4] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding16793", v16798);
    const v16799 = try o.importValue(&s, graph, "guard/index.mjs", "Guard");
    const v16800 = try s.text("IsEqual");
    const v16801 = try s.own(try js.getKey(e, v16799, v16800));
    const v16802 = try o.lookup(&s, frame, "binding16791");
    const v16803 = try s.text("object");
    const v16804 = try s.call(v16801, v16799, &.{ v16802, v16803 });
    const v16806 = conditional16805: {
        if (s.truthy(v16804)) {
            const v16807 = try o.importValue(&s, graph, "guard/index.mjs", "Guard");
            const v16808 = try s.text("IsObjectNotArray");
            const v16809 = try s.own(try js.getKey(e, v16807, v16808));
            const v16810 = try o.lookup(&s, frame, "binding16793");
            const v16811 = try s.call(v16809, v16807, &.{v16810});
            break :conditional16805 v16811;
        } else {
            const v16812 = try o.importValue(&s, graph, "guard/index.mjs", "Guard");
            const v16813 = try s.text("IsEqual");
            const v16814 = try s.own(try js.getKey(e, v16812, v16813));
            const v16815 = try o.lookup(&s, frame, "binding16791");
            const v16816 = try s.text("array");
            const v16817 = try s.call(v16814, v16812, &.{ v16815, v16816 });
            const v16819 = conditional16818: {
                if (s.truthy(v16817)) {
                    const v16820 = try o.importValue(&s, graph, "guard/index.mjs", "Guard");
                    const v16821 = try s.text("IsArray");
                    const v16822 = try s.own(try js.getKey(e, v16820, v16821));
                    const v16823 = try o.lookup(&s, frame, "binding16793");
                    const v16824 = try s.call(v16822, v16820, &.{v16823});
                    break :conditional16818 v16824;
                } else {
                    const v16825 = try o.importValue(&s, graph, "guard/index.mjs", "Guard");
                    const v16826 = try s.text("IsEqual");
                    const v16827 = try s.own(try js.getKey(e, v16825, v16826));
                    const v16828 = try o.lookup(&s, frame, "binding16791");
                    const v16829 = try s.text("boolean");
                    const v16830 = try s.call(v16827, v16825, &.{ v16828, v16829 });
                    const v16832 = conditional16831: {
                        if (s.truthy(v16830)) {
                            const v16833 = try o.importValue(&s, graph, "guard/index.mjs", "Guard");
                            const v16834 = try s.text("IsBoolean");
                            const v16835 = try s.own(try js.getKey(e, v16833, v16834));
                            const v16836 = try o.lookup(&s, frame, "binding16793");
                            const v16837 = try s.call(v16835, v16833, &.{v16836});
                            break :conditional16831 v16837;
                        } else {
                            const v16838 = try o.importValue(&s, graph, "guard/index.mjs", "Guard");
                            const v16839 = try s.text("IsEqual");
                            const v16840 = try s.own(try js.getKey(e, v16838, v16839));
                            const v16841 = try o.lookup(&s, frame, "binding16791");
                            const v16842 = try s.text("integer");
                            const v16843 = try s.call(v16840, v16838, &.{ v16841, v16842 });
                            const v16845 = conditional16844: {
                                if (s.truthy(v16843)) {
                                    const v16846 = try o.importValue(&s, graph, "guard/index.mjs", "Guard");
                                    const v16847 = try s.text("IsInteger");
                                    const v16848 = try s.own(try js.getKey(e, v16846, v16847));
                                    const v16849 = try o.lookup(&s, frame, "binding16793");
                                    const v16850 = try s.call(v16848, v16846, &.{v16849});
                                    break :conditional16844 v16850;
                                } else {
                                    const v16851 = try o.importValue(&s, graph, "guard/index.mjs", "Guard");
                                    const v16852 = try s.text("IsEqual");
                                    const v16853 = try s.own(try js.getKey(e, v16851, v16852));
                                    const v16854 = try o.lookup(&s, frame, "binding16791");
                                    const v16855 = try s.text("number");
                                    const v16856 = try s.call(v16853, v16851, &.{ v16854, v16855 });
                                    const v16858 = conditional16857: {
                                        if (s.truthy(v16856)) {
                                            const v16859 = try o.importValue(&s, graph, "guard/index.mjs", "Guard");
                                            const v16860 = try s.text("IsNumber");
                                            const v16861 = try s.own(try js.getKey(e, v16859, v16860));
                                            const v16862 = try o.lookup(&s, frame, "binding16793");
                                            const v16863 = try s.call(v16861, v16859, &.{v16862});
                                            break :conditional16857 v16863;
                                        } else {
                                            const v16864 = try o.importValue(&s, graph, "guard/index.mjs", "Guard");
                                            const v16865 = try s.text("IsEqual");
                                            const v16866 = try s.own(try js.getKey(e, v16864, v16865));
                                            const v16867 = try o.lookup(&s, frame, "binding16791");
                                            const v16868 = try s.text("null");
                                            const v16869 = try s.call(v16866, v16864, &.{ v16867, v16868 });
                                            const v16871 = conditional16870: {
                                                if (s.truthy(v16869)) {
                                                    const v16872 = try o.importValue(&s, graph, "guard/index.mjs", "Guard");
                                                    const v16873 = try s.text("IsNull");
                                                    const v16874 = try s.own(try js.getKey(e, v16872, v16873));
                                                    const v16875 = try o.lookup(&s, frame, "binding16793");
                                                    const v16876 = try s.call(v16874, v16872, &.{v16875});
                                                    break :conditional16870 v16876;
                                                } else {
                                                    const v16877 = try o.importValue(&s, graph, "guard/index.mjs", "Guard");
                                                    const v16878 = try s.text("IsEqual");
                                                    const v16879 = try s.own(try js.getKey(e, v16877, v16878));
                                                    const v16880 = try o.lookup(&s, frame, "binding16791");
                                                    const v16881 = try s.text("string");
                                                    const v16882 = try s.call(v16879, v16877, &.{ v16880, v16881 });
                                                    const v16884 = conditional16883: {
                                                        if (s.truthy(v16882)) {
                                                            const v16885 = try o.importValue(&s, graph, "guard/index.mjs", "Guard");
                                                            const v16886 = try s.text("IsString");
                                                            const v16887 = try s.own(try js.getKey(e, v16885, v16886));
                                                            const v16888 = try o.lookup(&s, frame, "binding16793");
                                                            const v16889 = try s.call(v16887, v16885, &.{v16888});
                                                            break :conditional16883 v16889;
                                                        } else {
                                                            const v16890 = try o.importValue(&s, graph, "guard/index.mjs", "Guard");
                                                            const v16891 = try s.text("IsEqual");
                                                            const v16892 = try s.own(try js.getKey(e, v16890, v16891));
                                                            const v16893 = try o.lookup(&s, frame, "binding16791");
                                                            const v16894 = try s.text("bigint");
                                                            const v16895 = try s.call(v16892, v16890, &.{ v16893, v16894 });
                                                            const v16897 = conditional16896: {
                                                                if (s.truthy(v16895)) {
                                                                    const v16898 = try o.importValue(&s, graph, "guard/index.mjs", "Guard");
                                                                    const v16899 = try s.text("IsBigInt");
                                                                    const v16900 = try s.own(try js.getKey(e, v16898, v16899));
                                                                    const v16901 = try o.lookup(&s, frame, "binding16793");
                                                                    const v16902 = try s.call(v16900, v16898, &.{v16901});
                                                                    break :conditional16896 v16902;
                                                                } else {
                                                                    const v16903 = try o.importValue(&s, graph, "guard/index.mjs", "Guard");
                                                                    const v16904 = try s.text("IsEqual");
                                                                    const v16905 = try s.own(try js.getKey(e, v16903, v16904));
                                                                    const v16906 = try o.lookup(&s, frame, "binding16791");
                                                                    const v16907 = try s.text("constructor");
                                                                    const v16908 = try s.call(v16905, v16903, &.{ v16906, v16907 });
                                                                    const v16910 = conditional16909: {
                                                                        if (s.truthy(v16908)) {
                                                                            const v16911 = try o.importValue(&s, graph, "guard/index.mjs", "Guard");
                                                                            const v16912 = try s.text("IsConstructor");
                                                                            const v16913 = try s.own(try js.getKey(e, v16911, v16912));
                                                                            const v16914 = try o.lookup(&s, frame, "binding16793");
                                                                            const v16915 = try s.call(v16913, v16911, &.{v16914});
                                                                            break :conditional16909 v16915;
                                                                        } else {
                                                                            const v16916 = try o.importValue(&s, graph, "guard/index.mjs", "Guard");
                                                                            const v16917 = try s.text("IsEqual");
                                                                            const v16918 = try s.own(try js.getKey(e, v16916, v16917));
                                                                            const v16919 = try o.lookup(&s, frame, "binding16791");
                                                                            const v16920 = try s.text("function");
                                                                            const v16921 = try s.call(v16918, v16916, &.{ v16919, v16920 });
                                                                            const v16923 = conditional16922: {
                                                                                if (s.truthy(v16921)) {
                                                                                    const v16924 = try o.importValue(&s, graph, "guard/index.mjs", "Guard");
                                                                                    const v16925 = try s.text("IsFunction");
                                                                                    const v16926 = try s.own(try js.getKey(e, v16924, v16925));
                                                                                    const v16927 = try o.lookup(&s, frame, "binding16793");
                                                                                    const v16928 = try s.call(v16926, v16924, &.{v16927});
                                                                                    break :conditional16922 v16928;
                                                                                } else {
                                                                                    const v16929 = try o.importValue(&s, graph, "guard/index.mjs", "Guard");
                                                                                    const v16930 = try s.text("IsEqual");
                                                                                    const v16931 = try s.own(try js.getKey(e, v16929, v16930));
                                                                                    const v16932 = try o.lookup(&s, frame, "binding16791");
                                                                                    const v16933 = try s.text("symbol");
                                                                                    const v16934 = try s.call(v16931, v16929, &.{ v16932, v16933 });
                                                                                    const v16936 = conditional16935: {
                                                                                        if (s.truthy(v16934)) {
                                                                                            const v16937 = try o.importValue(&s, graph, "guard/index.mjs", "Guard");
                                                                                            const v16938 = try s.text("IsSymbol");
                                                                                            const v16939 = try s.own(try js.getKey(e, v16937, v16938));
                                                                                            const v16940 = try o.lookup(&s, frame, "binding16793");
                                                                                            const v16941 = try s.call(v16939, v16937, &.{v16940});
                                                                                            break :conditional16935 v16941;
                                                                                        } else {
                                                                                            const v16942 = try o.importValue(&s, graph, "guard/index.mjs", "Guard");
                                                                                            const v16943 = try s.text("IsEqual");
                                                                                            const v16944 = try s.own(try js.getKey(e, v16942, v16943));
                                                                                            const v16945 = try o.lookup(&s, frame, "binding16791");
                                                                                            const v16946 = try s.text("undefined");
                                                                                            const v16947 = try s.call(v16944, v16942, &.{ v16945, v16946 });
                                                                                            const v16949 = conditional16948: {
                                                                                                if (s.truthy(v16947)) {
                                                                                                    const v16950 = try o.importValue(&s, graph, "guard/index.mjs", "Guard");
                                                                                                    const v16951 = try s.text("IsUndefined");
                                                                                                    const v16952 = try s.own(try js.getKey(e, v16950, v16951));
                                                                                                    const v16953 = try o.lookup(&s, frame, "binding16793");
                                                                                                    const v16954 = try s.call(v16952, v16950, &.{v16953});
                                                                                                    break :conditional16948 v16954;
                                                                                                } else {
                                                                                                    const v16955 = try o.importValue(&s, graph, "guard/index.mjs", "Guard");
                                                                                                    const v16956 = try s.text("IsEqual");
                                                                                                    const v16957 = try s.own(try js.getKey(e, v16955, v16956));
                                                                                                    const v16958 = try o.lookup(&s, frame, "binding16791");
                                                                                                    const v16959 = try s.text("void");
                                                                                                    const v16960 = try s.call(v16957, v16955, &.{ v16958, v16959 });
                                                                                                    const v16962 = conditional16961: {
                                                                                                        if (s.truthy(v16960)) {
                                                                                                            const v16963 = try o.importValue(&s, graph, "guard/index.mjs", "Guard");
                                                                                                            const v16964 = try s.text("IsUndefined");
                                                                                                            const v16965 = try s.own(try js.getKey(e, v16963, v16964));
                                                                                                            const v16966 = try o.lookup(&s, frame, "binding16793");
                                                                                                            const v16967 = try s.call(v16965, v16963, &.{v16966});
                                                                                                            break :conditional16961 v16967;
                                                                                                        } else {
                                                                                                            break :conditional16961 o.boolean(&s, true);
                                                                                                        }
                                                                                                    };
                                                                                                    break :conditional16948 v16962;
                                                                                                }
                                                                                            };
                                                                                            break :conditional16935 v16949;
                                                                                        }
                                                                                    };
                                                                                    break :conditional16922 v16936;
                                                                                }
                                                                            };
                                                                            break :conditional16909 v16923;
                                                                        }
                                                                    };
                                                                    break :conditional16896 v16910;
                                                                }
                                                            };
                                                            break :conditional16883 v16897;
                                                        }
                                                    };
                                                    break :conditional16870 v16884;
                                                }
                                            };
                                            break :conditional16857 v16871;
                                        }
                                    };
                                    break :conditional16844 v16858;
                                }
                            };
                            break :conditional16831 v16845;
                        }
                    };
                    break :conditional16818 v16832;
                }
            };
            break :conditional16805 v16819;
        }
    };
    return c.JS_DupValue(e.context, v16806);
}
fn body16984(e: *Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    _ = roots[0];
    const frame = try o.frame(&s, roots[1]);
    _ = try o.lookup(&s, frame, "@this");
    const v16987 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding16986", v16987);
    const v16988 = try o.lookup(&s, frame, "binding16598");
    const v16989 = try o.lookup(&s, frame, "binding16970");
    const v16990 = try o.lookup(&s, frame, "binding16971");
    const v16991 = try o.lookup(&s, frame, "binding16986");
    const v16992 = try o.lookup(&s, frame, "binding16973");
    const v16993 = try s.call(v16988, c.pi_js_undefined(), &.{ v16989, v16990, v16991, v16992 });
    return c.JS_DupValue(e.context, v16993);
}
fn body16984C(ctx: ?*c.JSContext, receiver: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const e = Engine.fromContext(ctx.?);
    return body16984(e, receiver, if (argc > 0) argv[0..@intCast(argc)] else &.{}, roots[0..2]) catch |err| sdk.fail(e, err);
}
fn body16969(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v16974 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding16970", v16974);
    const v16975 = if (args.len > 1) args[1] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding16971", v16975);
    const v16976 = if (args.len > 2) args[2] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding16972", v16976);
    const v16977 = if (args.len > 3) args[3] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding16973", v16977);
    const v16978 = try o.importValue(&s, graph, "guard/index.mjs", "EmitGuard");
    const v16979 = try s.text("ReduceOr");
    const v16980 = try s.own(try js.getKey(e, v16978, v16979));
    const v16981 = try o.lookup(&s, frame, "binding16972");
    const v16982 = try s.text("map");
    const v16983 = try s.own(try js.getKey(e, v16981, v16982));
    const v16994 = try o.arrow(&s, "", 1, body16984C, &.{ graph, frame });
    const v16995 = try s.call(v16983, v16981, &.{v16994});
    const v16996 = try s.call(v16980, v16978, &.{v16995});
    return c.JS_DupValue(e.context, v16996);
}
fn body17013(e: *Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    _ = roots[0];
    const frame = try o.frame(&s, roots[1]);
    _ = try o.lookup(&s, frame, "@this");
    const v17016 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding17015", v17016);
    const v17017 = try o.lookup(&s, frame, "binding16599");
    const v17018 = try o.lookup(&s, frame, "binding16999");
    const v17019 = try o.lookup(&s, frame, "binding17000");
    const v17020 = try o.lookup(&s, frame, "binding17015");
    const v17021 = try o.lookup(&s, frame, "binding17002");
    const v17022 = try o.lookup(&s, frame, "binding17003");
    const v17023 = try s.call(v17017, c.pi_js_undefined(), &.{ v17018, v17019, v17020, v17021, v17022 });
    return c.JS_DupValue(e.context, v17023);
}
fn body17013C(ctx: ?*c.JSContext, receiver: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const e = Engine.fromContext(ctx.?);
    return body17013(e, receiver, if (argc > 0) argv[0..@intCast(argc)] else &.{}, roots[0..2]) catch |err| sdk.fail(e, err);
}
fn body16998(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v17004 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding16999", v17004);
    const v17005 = if (args.len > 1) args[1] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding17000", v17005);
    const v17006 = if (args.len > 2) args[2] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding17001", v17006);
    const v17007 = if (args.len > 3) args[3] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding17002", v17007);
    const v17008 = if (args.len > 4) args[4] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding17003", v17008);
    const v17009 = try o.importValue(&s, graph, "guard/index.mjs", "Guard");
    const v17010 = try s.text("Some");
    const v17011 = try s.own(try js.getKey(e, v17009, v17010));
    const v17012 = try o.lookup(&s, frame, "binding17001");
    const v17024 = try o.arrow(&s, "", 1, body17013C, &.{ graph, frame });
    const v17025 = try s.call(v17011, v17009, &.{ v17012, v17024 });
    return c.JS_DupValue(e.context, v17025);
}
fn body17027(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v17032 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding17028", v17032);
    const v17033 = if (args.len > 1) args[1] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding17029", v17033);
    const v17034 = if (args.len > 2) args[2] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding17030", v17034);
    const v17035 = if (args.len > 3) args[3] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding17031", v17035);
    const v17036 = try o.importValue(&s, graph, "guard/index.mjs", "Guard");
    const v17037 = try s.text("IsArray");
    const v17038 = try s.own(try js.getKey(e, v17036, v17037));
    const v17039 = try o.lookup(&s, frame, "binding17030");
    const v17040 = try s.text("type");
    const v17041 = try s.own(try js.getKey(e, v17039, v17040));
    const v17042 = try s.call(v17038, v17036, &.{v17041});
    const v17044 = conditional17043: {
        if (s.truthy(v17042)) {
            const v17045 = try o.lookup(&s, frame, "binding16600");
            const v17046 = try o.lookup(&s, frame, "binding17028");
            const v17047 = try o.lookup(&s, frame, "binding17029");
            const v17048 = try o.lookup(&s, frame, "binding17030");
            const v17049 = try s.text("type");
            const v17050 = try s.own(try js.getKey(e, v17048, v17049));
            const v17051 = try o.lookup(&s, frame, "binding17031");
            const v17052 = try s.call(v17045, c.pi_js_undefined(), &.{ v17046, v17047, v17050, v17051 });
            break :conditional17043 v17052;
        } else {
            const v17053 = try o.lookup(&s, frame, "binding16598");
            const v17054 = try o.lookup(&s, frame, "binding17028");
            const v17055 = try o.lookup(&s, frame, "binding17029");
            const v17056 = try o.lookup(&s, frame, "binding17030");
            const v17057 = try s.text("type");
            const v17058 = try s.own(try js.getKey(e, v17056, v17057));
            const v17059 = try o.lookup(&s, frame, "binding17031");
            const v17060 = try s.call(v17053, c.pi_js_undefined(), &.{ v17054, v17055, v17058, v17059 });
            break :conditional17043 v17060;
        }
    };
    return c.JS_DupValue(e.context, v17044);
}
fn body17062(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v17067 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding17063", v17067);
    const v17068 = if (args.len > 1) args[1] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding17064", v17068);
    const v17069 = if (args.len > 2) args[2] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding17065", v17069);
    const v17070 = if (args.len > 3) args[3] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding17066", v17070);
    const v17071 = try o.importValue(&s, graph, "guard/index.mjs", "Guard");
    const v17072 = try s.text("IsArray");
    const v17073 = try s.own(try js.getKey(e, v17071, v17072));
    const v17074 = try o.lookup(&s, frame, "binding17065");
    const v17075 = try s.text("type");
    const v17076 = try s.own(try js.getKey(e, v17074, v17075));
    const v17077 = try s.call(v17073, v17071, &.{v17076});
    const v17079 = conditional17078: {
        if (s.truthy(v17077)) {
            const v17080 = try o.lookup(&s, frame, "binding16601");
            const v17081 = try o.lookup(&s, frame, "binding17063");
            const v17082 = try o.lookup(&s, frame, "binding17064");
            const v17083 = try o.lookup(&s, frame, "binding17065");
            const v17084 = try s.text("type");
            const v17085 = try s.own(try js.getKey(e, v17083, v17084));
            const v17086 = try o.lookup(&s, frame, "binding17065");
            const v17087 = try o.lookup(&s, frame, "binding17066");
            const v17088 = try s.call(v17080, c.pi_js_undefined(), &.{ v17081, v17082, v17085, v17086, v17087 });
            break :conditional17078 v17088;
        } else {
            const v17089 = try o.lookup(&s, frame, "binding16599");
            const v17090 = try o.lookup(&s, frame, "binding17063");
            const v17091 = try o.lookup(&s, frame, "binding17064");
            const v17092 = try o.lookup(&s, frame, "binding17065");
            const v17093 = try s.text("type");
            const v17094 = try s.own(try js.getKey(e, v17092, v17093));
            const v17095 = try o.lookup(&s, frame, "binding17065");
            const v17096 = try o.lookup(&s, frame, "binding17066");
            const v17097 = try s.call(v17089, c.pi_js_undefined(), &.{ v17090, v17091, v17094, v17095, v17096 });
            break :conditional17078 v17097;
        }
    };
    return c.JS_DupValue(e.context, v17079);
}
fn body17099(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v17107 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding17100", v17107);
    const v17108 = if (args.len > 1) args[1] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding17101", v17108);
    const v17109 = if (args.len > 2) args[2] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding17102", v17109);
    const v17110 = if (args.len > 3) args[3] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding17103", v17110);
    const v17111 = if (args.len > 4) args[4] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding17104", v17111);
    const v17112 = if (args.len > 5) args[5] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding17105", v17112);
    const v17114 = try o.importValue(&s, graph, "guard/index.mjs", "Guard");
    const v17115 = try s.text("IsArray");
    const v17116 = try s.own(try js.getKey(e, v17114, v17115));
    const v17117 = try o.lookup(&s, frame, "binding17104");
    const v17118 = try s.text("type");
    const v17119 = try s.own(try js.getKey(e, v17117, v17118));
    const v17120 = try s.call(v17116, v17114, &.{v17119});
    const v17122 = conditional17121: {
        if (s.truthy(v17120)) {
            const v17123 = try o.lookup(&s, frame, "binding16601");
            const v17124 = try o.lookup(&s, frame, "binding17100");
            const v17125 = try o.lookup(&s, frame, "binding17101");
            const v17126 = try o.lookup(&s, frame, "binding17104");
            const v17127 = try s.text("type");
            const v17128 = try s.own(try js.getKey(e, v17126, v17127));
            const v17129 = try o.lookup(&s, frame, "binding17104");
            const v17130 = try o.lookup(&s, frame, "binding17105");
            const v17131 = try s.call(v17123, c.pi_js_undefined(), &.{ v17124, v17125, v17128, v17129, v17130 });
            break :conditional17121 v17131;
        } else {
            const v17132 = try o.lookup(&s, frame, "binding16599");
            const v17133 = try o.lookup(&s, frame, "binding17100");
            const v17134 = try o.lookup(&s, frame, "binding17101");
            const v17135 = try o.lookup(&s, frame, "binding17104");
            const v17136 = try s.text("type");
            const v17137 = try s.own(try js.getKey(e, v17135, v17136));
            const v17138 = try o.lookup(&s, frame, "binding17104");
            const v17139 = try o.lookup(&s, frame, "binding17105");
            const v17140 = try s.call(v17132, c.pi_js_undefined(), &.{ v17133, v17134, v17137, v17138, v17139 });
            break :conditional17121 v17140;
        }
    };
    try o.assign(&s, frame, "binding17113", v17122);
    const v17141 = try o.lookup(&s, frame, "binding17113");
    const v17143 = logical17142: {
        if (s.truthy(v17141)) break :logical17142 v17141;
        const v17144 = try o.lookup(&s, frame, "binding17101");
        const v17145 = try s.text("AddError");
        const v17146 = try s.own(try js.getKey(e, v17144, v17145));
        const v17147 = try s.object();
        const v17148 = try s.text("keyword");
        const v17149 = try s.text("type");
        try o.defineKey(&s, v17147, v17148, v17149);
        const v17150 = try s.text("schemaPath");
        const v17151 = try o.lookup(&s, frame, "binding17102");
        try o.defineKey(&s, v17147, v17150, v17151);
        const v17152 = try s.text("instancePath");
        const v17153 = try o.lookup(&s, frame, "binding17103");
        try o.defineKey(&s, v17147, v17152, v17153);
        const v17154 = try s.text("params");
        const v17155 = try s.object();
        const v17156 = try s.text("type");
        const v17157 = try o.lookup(&s, frame, "binding17104");
        const v17158 = try s.text("type");
        const v17159 = try s.own(try js.getKey(e, v17157, v17158));
        try o.defineKey(&s, v17155, v17156, v17159);
        try o.defineKey(&s, v17147, v17154, v17155);
        const v17160 = try s.call(v17146, v17144, &.{v17147});
        break :logical17142 v17160;
    };
    return c.JS_DupValue(e.context, v17143);
}
