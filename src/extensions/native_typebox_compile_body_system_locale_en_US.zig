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
    const namespace = try s.get(modules, "system/locale/en_US.mjs");
    const frame = try o.frame(&s, c.pi_js_null());
    try s.put(frame, "@this", c.pi_js_undefined());
    try s.put(try s.get(graph, "frames"), "system/locale/en_US.mjs", frame);
    const bindings = try s.object();
    try s.put(try s.get(graph, "bindings"), "system/locale/en_US.mjs", bindings);
    const v22907 = try s.own(try ordinary.create(e, "en_US", 1, body22568, &.{ graph, frame }));
    try o.assign(&s, frame, "binding22567", v22907);
    const v22908 = try o.lookup(&s, frame, "binding22567");
    try s.put(namespace, "en_US", v22908);
    const v22909 = try o.lookup(&s, frame, "binding22567");
    try s.put(namespace, "en_US", v22909);
    try s.put(bindings, "en_US", try s.text("binding22567"));
}
fn body22568(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    _ = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v22570 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding22569", v22570);
    const v22571 = try o.lookup(&s, frame, "binding22569");
    const v22572 = try s.text("keyword");
    const v22573 = try s.own(try js.getKey(e, v22571, v22572));
    var entered22575 = false;
    switch_block22574: {
        const v22576 = try s.text("additionalProperties");
        if (entered22575 or s.equal(v22573, v22576)) {
            entered22575 = true;
            const v22577 = try s.text("must not have additional properties");
            return c.JS_DupValue(e.context, v22577);
        }
        const v22578 = try s.text("anyOf");
        if (entered22575 or s.equal(v22573, v22578)) {
            entered22575 = true;
            const v22579 = try s.text("must match a schema in anyOf");
            return c.JS_DupValue(e.context, v22579);
        }
        const v22580 = try s.text("boolean");
        if (entered22575 or s.equal(v22573, v22580)) {
            entered22575 = true;
            const v22581 = try s.text("schema is false");
            return c.JS_DupValue(e.context, v22581);
        }
        const v22582 = try s.text("const");
        if (entered22575 or s.equal(v22573, v22582)) {
            entered22575 = true;
            const v22583 = try s.text("must be equal to constant");
            return c.JS_DupValue(e.context, v22583);
        }
        const v22584 = try s.text("contains");
        if (entered22575 or s.equal(v22573, v22584)) {
            entered22575 = true;
            const v22585 = try s.text("must contain at least 1 valid item");
            return c.JS_DupValue(e.context, v22585);
        }
        const v22586 = try s.text("dependencies");
        if (entered22575 or s.equal(v22573, v22586)) {
            entered22575 = true;
            const v22587 = try s.text("must have properties ");
            const v22588 = try o.lookup(&s, frame, "binding22569");
            const v22589 = try s.text("params");
            const v22590 = try s.own(try js.getKey(e, v22588, v22589));
            const v22591 = try s.text("dependencies");
            const v22592 = try s.own(try js.getKey(e, v22590, v22591));
            const v22593 = try s.text("join");
            const v22594 = try s.own(try js.getKey(e, v22592, v22593));
            const v22595 = try s.text(", ");
            const v22596 = try s.call(v22594, v22592, &.{v22595});
            const v22597 = try s.stringify(v22596);
            const v22598 = try s.concat(v22587, v22597);
            const v22599 = try s.text(" when property ");
            const v22600 = try s.concat(v22598, v22599);
            const v22601 = try o.lookup(&s, frame, "binding22569");
            const v22602 = try s.text("params");
            const v22603 = try s.own(try js.getKey(e, v22601, v22602));
            const v22604 = try s.text("property");
            const v22605 = try s.own(try js.getKey(e, v22603, v22604));
            const v22606 = try s.stringify(v22605);
            const v22607 = try s.concat(v22600, v22606);
            const v22608 = try s.text(" is present");
            const v22609 = try s.concat(v22607, v22608);
            return c.JS_DupValue(e.context, v22609);
        }
        const v22610 = try s.text("dependentRequired");
        if (entered22575 or s.equal(v22573, v22610)) {
            entered22575 = true;
            const v22611 = try s.text("must have properties ");
            const v22612 = try o.lookup(&s, frame, "binding22569");
            const v22613 = try s.text("params");
            const v22614 = try s.own(try js.getKey(e, v22612, v22613));
            const v22615 = try s.text("dependencies");
            const v22616 = try s.own(try js.getKey(e, v22614, v22615));
            const v22617 = try s.text("join");
            const v22618 = try s.own(try js.getKey(e, v22616, v22617));
            const v22619 = try s.text(", ");
            const v22620 = try s.call(v22618, v22616, &.{v22619});
            const v22621 = try s.stringify(v22620);
            const v22622 = try s.concat(v22611, v22621);
            const v22623 = try s.text(" when property ");
            const v22624 = try s.concat(v22622, v22623);
            const v22625 = try o.lookup(&s, frame, "binding22569");
            const v22626 = try s.text("params");
            const v22627 = try s.own(try js.getKey(e, v22625, v22626));
            const v22628 = try s.text("property");
            const v22629 = try s.own(try js.getKey(e, v22627, v22628));
            const v22630 = try s.stringify(v22629);
            const v22631 = try s.concat(v22624, v22630);
            const v22632 = try s.text(" is present");
            const v22633 = try s.concat(v22631, v22632);
            return c.JS_DupValue(e.context, v22633);
        }
        const v22634 = try s.text("enum");
        if (entered22575 or s.equal(v22573, v22634)) {
            entered22575 = true;
            const v22635 = try s.text("must be equal to one of the allowed values");
            return c.JS_DupValue(e.context, v22635);
        }
        const v22636 = try s.text("exclusiveMaximum");
        if (entered22575 or s.equal(v22573, v22636)) {
            entered22575 = true;
            const v22637 = try s.text("must be ");
            const v22638 = try o.lookup(&s, frame, "binding22569");
            const v22639 = try s.text("params");
            const v22640 = try s.own(try js.getKey(e, v22638, v22639));
            const v22641 = try s.text("comparison");
            const v22642 = try s.own(try js.getKey(e, v22640, v22641));
            const v22643 = try s.stringify(v22642);
            const v22644 = try s.concat(v22637, v22643);
            const v22645 = try s.text(" ");
            const v22646 = try s.concat(v22644, v22645);
            const v22647 = try o.lookup(&s, frame, "binding22569");
            const v22648 = try s.text("params");
            const v22649 = try s.own(try js.getKey(e, v22647, v22648));
            const v22650 = try s.text("limit");
            const v22651 = try s.own(try js.getKey(e, v22649, v22650));
            const v22652 = try s.stringify(v22651);
            const v22653 = try s.concat(v22646, v22652);
            const v22654 = try s.text("");
            const v22655 = try s.concat(v22653, v22654);
            return c.JS_DupValue(e.context, v22655);
        }
        const v22656 = try s.text("exclusiveMinimum");
        if (entered22575 or s.equal(v22573, v22656)) {
            entered22575 = true;
            const v22657 = try s.text("must be ");
            const v22658 = try o.lookup(&s, frame, "binding22569");
            const v22659 = try s.text("params");
            const v22660 = try s.own(try js.getKey(e, v22658, v22659));
            const v22661 = try s.text("comparison");
            const v22662 = try s.own(try js.getKey(e, v22660, v22661));
            const v22663 = try s.stringify(v22662);
            const v22664 = try s.concat(v22657, v22663);
            const v22665 = try s.text(" ");
            const v22666 = try s.concat(v22664, v22665);
            const v22667 = try o.lookup(&s, frame, "binding22569");
            const v22668 = try s.text("params");
            const v22669 = try s.own(try js.getKey(e, v22667, v22668));
            const v22670 = try s.text("limit");
            const v22671 = try s.own(try js.getKey(e, v22669, v22670));
            const v22672 = try s.stringify(v22671);
            const v22673 = try s.concat(v22666, v22672);
            const v22674 = try s.text("");
            const v22675 = try s.concat(v22673, v22674);
            return c.JS_DupValue(e.context, v22675);
        }
        const v22676 = try s.text("format");
        if (entered22575 or s.equal(v22573, v22676)) {
            entered22575 = true;
            const v22677 = try s.text("must match format \"");
            const v22678 = try o.lookup(&s, frame, "binding22569");
            const v22679 = try s.text("params");
            const v22680 = try s.own(try js.getKey(e, v22678, v22679));
            const v22681 = try s.text("format");
            const v22682 = try s.own(try js.getKey(e, v22680, v22681));
            const v22683 = try s.stringify(v22682);
            const v22684 = try s.concat(v22677, v22683);
            const v22685 = try s.text("\"");
            const v22686 = try s.concat(v22684, v22685);
            return c.JS_DupValue(e.context, v22686);
        }
        const v22687 = try s.text("if");
        if (entered22575 or s.equal(v22573, v22687)) {
            entered22575 = true;
            const v22688 = try s.text("must match \"");
            const v22689 = try o.lookup(&s, frame, "binding22569");
            const v22690 = try s.text("params");
            const v22691 = try s.own(try js.getKey(e, v22689, v22690));
            const v22692 = try s.text("failingKeyword");
            const v22693 = try s.own(try js.getKey(e, v22691, v22692));
            const v22694 = try s.stringify(v22693);
            const v22695 = try s.concat(v22688, v22694);
            const v22696 = try s.text("\" schema");
            const v22697 = try s.concat(v22695, v22696);
            return c.JS_DupValue(e.context, v22697);
        }
        const v22698 = try s.text("maxItems");
        if (entered22575 or s.equal(v22573, v22698)) {
            entered22575 = true;
            const v22699 = try s.text("must not have more than ");
            const v22700 = try o.lookup(&s, frame, "binding22569");
            const v22701 = try s.text("params");
            const v22702 = try s.own(try js.getKey(e, v22700, v22701));
            const v22703 = try s.text("limit");
            const v22704 = try s.own(try js.getKey(e, v22702, v22703));
            const v22705 = try s.stringify(v22704);
            const v22706 = try s.concat(v22699, v22705);
            const v22707 = try s.text(" items");
            const v22708 = try s.concat(v22706, v22707);
            return c.JS_DupValue(e.context, v22708);
        }
        const v22709 = try s.text("maxLength");
        if (entered22575 or s.equal(v22573, v22709)) {
            entered22575 = true;
            const v22710 = try s.text("must not have more than ");
            const v22711 = try o.lookup(&s, frame, "binding22569");
            const v22712 = try s.text("params");
            const v22713 = try s.own(try js.getKey(e, v22711, v22712));
            const v22714 = try s.text("limit");
            const v22715 = try s.own(try js.getKey(e, v22713, v22714));
            const v22716 = try s.stringify(v22715);
            const v22717 = try s.concat(v22710, v22716);
            const v22718 = try s.text(" characters");
            const v22719 = try s.concat(v22717, v22718);
            return c.JS_DupValue(e.context, v22719);
        }
        const v22720 = try s.text("maxProperties");
        if (entered22575 or s.equal(v22573, v22720)) {
            entered22575 = true;
            const v22721 = try s.text("must not have more than ");
            const v22722 = try o.lookup(&s, frame, "binding22569");
            const v22723 = try s.text("params");
            const v22724 = try s.own(try js.getKey(e, v22722, v22723));
            const v22725 = try s.text("limit");
            const v22726 = try s.own(try js.getKey(e, v22724, v22725));
            const v22727 = try s.stringify(v22726);
            const v22728 = try s.concat(v22721, v22727);
            const v22729 = try s.text(" properties");
            const v22730 = try s.concat(v22728, v22729);
            return c.JS_DupValue(e.context, v22730);
        }
        const v22731 = try s.text("maximum");
        if (entered22575 or s.equal(v22573, v22731)) {
            entered22575 = true;
            const v22732 = try s.text("must be ");
            const v22733 = try o.lookup(&s, frame, "binding22569");
            const v22734 = try s.text("params");
            const v22735 = try s.own(try js.getKey(e, v22733, v22734));
            const v22736 = try s.text("comparison");
            const v22737 = try s.own(try js.getKey(e, v22735, v22736));
            const v22738 = try s.stringify(v22737);
            const v22739 = try s.concat(v22732, v22738);
            const v22740 = try s.text(" ");
            const v22741 = try s.concat(v22739, v22740);
            const v22742 = try o.lookup(&s, frame, "binding22569");
            const v22743 = try s.text("params");
            const v22744 = try s.own(try js.getKey(e, v22742, v22743));
            const v22745 = try s.text("limit");
            const v22746 = try s.own(try js.getKey(e, v22744, v22745));
            const v22747 = try s.stringify(v22746);
            const v22748 = try s.concat(v22741, v22747);
            const v22749 = try s.text("");
            const v22750 = try s.concat(v22748, v22749);
            return c.JS_DupValue(e.context, v22750);
        }
        const v22751 = try s.text("minItems");
        if (entered22575 or s.equal(v22573, v22751)) {
            entered22575 = true;
            const v22752 = try s.text("must not have fewer than ");
            const v22753 = try o.lookup(&s, frame, "binding22569");
            const v22754 = try s.text("params");
            const v22755 = try s.own(try js.getKey(e, v22753, v22754));
            const v22756 = try s.text("limit");
            const v22757 = try s.own(try js.getKey(e, v22755, v22756));
            const v22758 = try s.stringify(v22757);
            const v22759 = try s.concat(v22752, v22758);
            const v22760 = try s.text(" items");
            const v22761 = try s.concat(v22759, v22760);
            return c.JS_DupValue(e.context, v22761);
        }
        const v22762 = try s.text("minLength");
        if (entered22575 or s.equal(v22573, v22762)) {
            entered22575 = true;
            const v22763 = try s.text("must not have fewer than ");
            const v22764 = try o.lookup(&s, frame, "binding22569");
            const v22765 = try s.text("params");
            const v22766 = try s.own(try js.getKey(e, v22764, v22765));
            const v22767 = try s.text("limit");
            const v22768 = try s.own(try js.getKey(e, v22766, v22767));
            const v22769 = try s.stringify(v22768);
            const v22770 = try s.concat(v22763, v22769);
            const v22771 = try s.text(" characters");
            const v22772 = try s.concat(v22770, v22771);
            return c.JS_DupValue(e.context, v22772);
        }
        const v22773 = try s.text("minProperties");
        if (entered22575 or s.equal(v22573, v22773)) {
            entered22575 = true;
            const v22774 = try s.text("must not have fewer than ");
            const v22775 = try o.lookup(&s, frame, "binding22569");
            const v22776 = try s.text("params");
            const v22777 = try s.own(try js.getKey(e, v22775, v22776));
            const v22778 = try s.text("limit");
            const v22779 = try s.own(try js.getKey(e, v22777, v22778));
            const v22780 = try s.stringify(v22779);
            const v22781 = try s.concat(v22774, v22780);
            const v22782 = try s.text(" properties");
            const v22783 = try s.concat(v22781, v22782);
            return c.JS_DupValue(e.context, v22783);
        }
        const v22784 = try s.text("minimum");
        if (entered22575 or s.equal(v22573, v22784)) {
            entered22575 = true;
            const v22785 = try s.text("must be ");
            const v22786 = try o.lookup(&s, frame, "binding22569");
            const v22787 = try s.text("params");
            const v22788 = try s.own(try js.getKey(e, v22786, v22787));
            const v22789 = try s.text("comparison");
            const v22790 = try s.own(try js.getKey(e, v22788, v22789));
            const v22791 = try s.stringify(v22790);
            const v22792 = try s.concat(v22785, v22791);
            const v22793 = try s.text(" ");
            const v22794 = try s.concat(v22792, v22793);
            const v22795 = try o.lookup(&s, frame, "binding22569");
            const v22796 = try s.text("params");
            const v22797 = try s.own(try js.getKey(e, v22795, v22796));
            const v22798 = try s.text("limit");
            const v22799 = try s.own(try js.getKey(e, v22797, v22798));
            const v22800 = try s.stringify(v22799);
            const v22801 = try s.concat(v22794, v22800);
            const v22802 = try s.text("");
            const v22803 = try s.concat(v22801, v22802);
            return c.JS_DupValue(e.context, v22803);
        }
        const v22804 = try s.text("multipleOf");
        if (entered22575 or s.equal(v22573, v22804)) {
            entered22575 = true;
            const v22805 = try s.text("must be multiple of ");
            const v22806 = try o.lookup(&s, frame, "binding22569");
            const v22807 = try s.text("params");
            const v22808 = try s.own(try js.getKey(e, v22806, v22807));
            const v22809 = try s.text("multipleOf");
            const v22810 = try s.own(try js.getKey(e, v22808, v22809));
            const v22811 = try s.stringify(v22810);
            const v22812 = try s.concat(v22805, v22811);
            const v22813 = try s.text("");
            const v22814 = try s.concat(v22812, v22813);
            return c.JS_DupValue(e.context, v22814);
        }
        const v22815 = try s.text("not");
        if (entered22575 or s.equal(v22573, v22815)) {
            entered22575 = true;
            const v22816 = try s.text("must not be valid");
            return c.JS_DupValue(e.context, v22816);
        }
        const v22817 = try s.text("oneOf");
        if (entered22575 or s.equal(v22573, v22817)) {
            entered22575 = true;
            const v22818 = try s.text("must match exactly one schema in oneOf");
            return c.JS_DupValue(e.context, v22818);
        }
        const v22819 = try s.text("pattern");
        if (entered22575 or s.equal(v22573, v22819)) {
            entered22575 = true;
            const v22820 = try s.text("must match pattern \"");
            const v22821 = try o.lookup(&s, frame, "binding22569");
            const v22822 = try s.text("params");
            const v22823 = try s.own(try js.getKey(e, v22821, v22822));
            const v22824 = try s.text("pattern");
            const v22825 = try s.own(try js.getKey(e, v22823, v22824));
            const v22826 = try s.stringify(v22825);
            const v22827 = try s.concat(v22820, v22826);
            const v22828 = try s.text("\"");
            const v22829 = try s.concat(v22827, v22828);
            return c.JS_DupValue(e.context, v22829);
        }
        const v22830 = try s.text("propertyNames");
        if (entered22575 or s.equal(v22573, v22830)) {
            entered22575 = true;
            const v22831 = try s.text("property names ");
            const v22832 = try o.lookup(&s, frame, "binding22569");
            const v22833 = try s.text("params");
            const v22834 = try s.own(try js.getKey(e, v22832, v22833));
            const v22835 = try s.text("propertyNames");
            const v22836 = try s.own(try js.getKey(e, v22834, v22835));
            const v22837 = try s.text("join");
            const v22838 = try s.own(try js.getKey(e, v22836, v22837));
            const v22839 = try s.text(", ");
            const v22840 = try s.call(v22838, v22836, &.{v22839});
            const v22841 = try s.stringify(v22840);
            const v22842 = try s.concat(v22831, v22841);
            const v22843 = try s.text(" are invalid");
            const v22844 = try s.concat(v22842, v22843);
            return c.JS_DupValue(e.context, v22844);
        }
        const v22845 = try s.text("required");
        if (entered22575 or s.equal(v22573, v22845)) {
            entered22575 = true;
            const v22846 = try s.text("must have required properties ");
            const v22847 = try o.lookup(&s, frame, "binding22569");
            const v22848 = try s.text("params");
            const v22849 = try s.own(try js.getKey(e, v22847, v22848));
            const v22850 = try s.text("requiredProperties");
            const v22851 = try s.own(try js.getKey(e, v22849, v22850));
            const v22852 = try s.text("join");
            const v22853 = try s.own(try js.getKey(e, v22851, v22852));
            const v22854 = try s.text(", ");
            const v22855 = try s.call(v22853, v22851, &.{v22854});
            const v22856 = try s.stringify(v22855);
            const v22857 = try s.concat(v22846, v22856);
            const v22858 = try s.text("");
            const v22859 = try s.concat(v22857, v22858);
            return c.JS_DupValue(e.context, v22859);
        }
        const v22860 = try s.text("type");
        if (entered22575 or s.equal(v22573, v22860)) {
            entered22575 = true;
            const v22861 = try o.lookup(&s, frame, "binding22569");
            const v22862 = try s.text("params");
            const v22863 = try s.own(try js.getKey(e, v22861, v22862));
            const v22864 = try s.text("type");
            const v22865 = try s.own(try js.getKey(e, v22863, v22864));
            const v22866 = try o.typeOf(&s, v22865);
            const v22867 = try s.text("string");
            const v22869 = conditional22868: {
                if (s.truthy(o.boolean(&s, s.equal(v22866, v22867)))) {
                    const v22870 = try s.text("must be ");
                    const v22871 = try o.lookup(&s, frame, "binding22569");
                    const v22872 = try s.text("params");
                    const v22873 = try s.own(try js.getKey(e, v22871, v22872));
                    const v22874 = try s.text("type");
                    const v22875 = try s.own(try js.getKey(e, v22873, v22874));
                    const v22876 = try s.stringify(v22875);
                    const v22877 = try s.concat(v22870, v22876);
                    const v22878 = try s.text("");
                    const v22879 = try s.concat(v22877, v22878);
                    break :conditional22868 v22879;
                } else {
                    const v22880 = try s.text("must be either ");
                    const v22881 = try o.lookup(&s, frame, "binding22569");
                    const v22882 = try s.text("params");
                    const v22883 = try s.own(try js.getKey(e, v22881, v22882));
                    const v22884 = try s.text("type");
                    const v22885 = try s.own(try js.getKey(e, v22883, v22884));
                    const v22886 = try s.text("join");
                    const v22887 = try s.own(try js.getKey(e, v22885, v22886));
                    const v22888 = try s.text(" or ");
                    const v22889 = try s.call(v22887, v22885, &.{v22888});
                    const v22890 = try s.stringify(v22889);
                    const v22891 = try s.concat(v22880, v22890);
                    const v22892 = try s.text("");
                    const v22893 = try s.concat(v22891, v22892);
                    break :conditional22868 v22893;
                }
            };
            return c.JS_DupValue(e.context, v22869);
        }
        const v22894 = try s.text("unevaluatedItems");
        if (entered22575 or s.equal(v22573, v22894)) {
            entered22575 = true;
            const v22895 = try s.text("must not have unevaluated items");
            return c.JS_DupValue(e.context, v22895);
        }
        const v22896 = try s.text("unevaluatedProperties");
        if (entered22575 or s.equal(v22573, v22896)) {
            entered22575 = true;
            const v22897 = try s.text("must not have unevaluated properties");
            return c.JS_DupValue(e.context, v22897);
        }
        const v22898 = try s.text("uniqueItems");
        if (entered22575 or s.equal(v22573, v22898)) {
            entered22575 = true;
            const v22899 = try s.text("must not have duplicate items");
            return c.JS_DupValue(e.context, v22899);
        }
        const v22900 = try s.text("~refine");
        if (entered22575 or s.equal(v22573, v22900)) {
            entered22575 = true;
            const v22901 = try o.lookup(&s, frame, "binding22569");
            const v22902 = try s.text("params");
            const v22903 = try s.own(try js.getKey(e, v22901, v22902));
            const v22904 = try s.text("message");
            const v22905 = try s.own(try js.getKey(e, v22903, v22904));
            return c.JS_DupValue(e.context, v22905);
        }
        if (!entered22575) {
            const v22906 = try s.text("an unknown validation error occurred");
            return c.JS_DupValue(e.context, v22906);
        }
        break :switch_block22574;
    }
    return c.pi_js_undefined();
}
