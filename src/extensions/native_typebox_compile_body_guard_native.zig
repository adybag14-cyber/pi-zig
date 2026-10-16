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
    const namespace = try s.get(modules, "guard/native.mjs");
    const frame = try o.frame(&s, c.pi_js_null());
    try s.put(frame, "@this", c.pi_js_undefined());
    try s.put(try s.get(graph, "frames"), "guard/native.mjs", frame);
    const bindings = try s.object();
    try s.put(try s.get(graph, "bindings"), "guard/native.mjs", bindings);
    const v2619 = try s.own(try ordinary.create(e, "IsF32", 1, body2599, &.{ graph, frame }));
    try o.assign(&s, frame, "binding2589", v2619);
    const v2628 = try s.own(try ordinary.create(e, "IsF64", 1, body2620, &.{ graph, frame }));
    try o.assign(&s, frame, "binding2590", v2628);
    const v2651 = try s.own(try ordinary.create(e, "IsU8", 1, body2629, &.{ graph, frame }));
    try o.assign(&s, frame, "binding2591", v2651);
    const v2674 = try s.own(try ordinary.create(e, "IsU16", 1, body2652, &.{ graph, frame }));
    try o.assign(&s, frame, "binding2592", v2674);
    const v2697 = try s.own(try ordinary.create(e, "IsU32", 1, body2675, &.{ graph, frame }));
    try o.assign(&s, frame, "binding2593", v2697);
    const v2713 = try s.own(try ordinary.create(e, "IsU64", 1, body2698, &.{ graph, frame }));
    try o.assign(&s, frame, "binding2594", v2713);
    const v2737 = try s.own(try ordinary.create(e, "IsI8", 1, body2714, &.{ graph, frame }));
    try o.assign(&s, frame, "binding2595", v2737);
    const v2761 = try s.own(try ordinary.create(e, "IsI16", 1, body2738, &.{ graph, frame }));
    try o.assign(&s, frame, "binding2596", v2761);
    const v2785 = try s.own(try ordinary.create(e, "IsI32", 1, body2762, &.{ graph, frame }));
    try o.assign(&s, frame, "binding2597", v2785);
    const v2814 = try s.own(try ordinary.create(e, "IsI64", 1, body2786, &.{ graph, frame }));
    try o.assign(&s, frame, "binding2598", v2814);
    const v2815 = try o.lookup(&s, frame, "binding2589");
    try s.put(namespace, "IsF32", v2815);
    const v2816 = try o.lookup(&s, frame, "binding2590");
    try s.put(namespace, "IsF64", v2816);
    const v2817 = try o.lookup(&s, frame, "binding2591");
    try s.put(namespace, "IsU8", v2817);
    const v2818 = try o.lookup(&s, frame, "binding2592");
    try s.put(namespace, "IsU16", v2818);
    const v2819 = try o.lookup(&s, frame, "binding2593");
    try s.put(namespace, "IsU32", v2819);
    const v2820 = try o.lookup(&s, frame, "binding2594");
    try s.put(namespace, "IsU64", v2820);
    const v2821 = try o.lookup(&s, frame, "binding2595");
    try s.put(namespace, "IsI8", v2821);
    const v2822 = try o.lookup(&s, frame, "binding2596");
    try s.put(namespace, "IsI16", v2822);
    const v2823 = try o.lookup(&s, frame, "binding2597");
    try s.put(namespace, "IsI32", v2823);
    const v2824 = try o.lookup(&s, frame, "binding2598");
    try s.put(namespace, "IsI64", v2824);
    const v2825 = try o.lookup(&s, frame, "binding2589");
    try s.put(namespace, "IsF32", v2825);
    const v2826 = try o.lookup(&s, frame, "binding2590");
    try s.put(namespace, "IsF64", v2826);
    const v2827 = try o.lookup(&s, frame, "binding2591");
    try s.put(namespace, "IsU8", v2827);
    const v2828 = try o.lookup(&s, frame, "binding2592");
    try s.put(namespace, "IsU16", v2828);
    const v2829 = try o.lookup(&s, frame, "binding2593");
    try s.put(namespace, "IsU32", v2829);
    const v2830 = try o.lookup(&s, frame, "binding2594");
    try s.put(namespace, "IsU64", v2830);
    const v2831 = try o.lookup(&s, frame, "binding2595");
    try s.put(namespace, "IsI8", v2831);
    const v2832 = try o.lookup(&s, frame, "binding2596");
    try s.put(namespace, "IsI16", v2832);
    const v2833 = try o.lookup(&s, frame, "binding2597");
    try s.put(namespace, "IsI32", v2833);
    const v2834 = try o.lookup(&s, frame, "binding2598");
    try s.put(namespace, "IsI64", v2834);
    try s.put(bindings, "IsF32", try s.text("binding2589"));
    try s.put(bindings, "IsF64", try s.text("binding2590"));
    try s.put(bindings, "IsU8", try s.text("binding2591"));
    try s.put(bindings, "IsU16", try s.text("binding2592"));
    try s.put(bindings, "IsU32", try s.text("binding2593"));
    try s.put(bindings, "IsU64", try s.text("binding2594"));
    try s.put(bindings, "IsI8", try s.text("binding2595"));
    try s.put(bindings, "IsI16", try s.text("binding2596"));
    try s.put(bindings, "IsI32", try s.text("binding2597"));
    try s.put(bindings, "IsI64", try s.text("binding2598"));
}
fn body2599(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v2601 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding2600", v2601);
    const v2602 = try o.importValue(&s, graph, "guard/guard.mjs", "*");
    const v2603 = try s.text("IsNumber");
    const v2604 = try s.own(try js.getKey(e, v2602, v2603));
    const v2605 = try o.lookup(&s, frame, "binding2600");
    const v2606 = try s.call(v2604, v2602, &.{v2605});
    const v2608 = logical2607: {
        if (!s.truthy(v2606)) break :logical2607 v2606;
        const v2609 = try o.importValue(&s, graph, "guard/guard.mjs", "*");
        const v2610 = try s.text("IsEqual");
        const v2611 = try s.own(try js.getKey(e, v2609, v2610));
        const v2612 = try o.lookup(&s, frame, "binding2600");
        const v2613 = try s.global("Math");
        const v2614 = try s.text("fround");
        const v2615 = try s.own(try js.getKey(e, v2613, v2614));
        const v2616 = try o.lookup(&s, frame, "binding2600");
        const v2617 = try s.call(v2615, v2613, &.{v2616});
        const v2618 = try s.call(v2611, v2609, &.{ v2612, v2617 });
        break :logical2607 v2618;
    };
    return c.JS_DupValue(e.context, v2608);
}
fn body2620(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v2622 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding2621", v2622);
    const v2623 = try o.importValue(&s, graph, "guard/guard.mjs", "*");
    const v2624 = try s.text("IsNumber");
    const v2625 = try s.own(try js.getKey(e, v2623, v2624));
    const v2626 = try o.lookup(&s, frame, "binding2621");
    const v2627 = try s.call(v2625, v2623, &.{v2626});
    return c.JS_DupValue(e.context, v2627);
}
fn body2629(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v2631 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding2630", v2631);
    const v2632 = try o.importValue(&s, graph, "guard/guard.mjs", "*");
    const v2633 = try s.text("IsInteger");
    const v2634 = try s.own(try js.getKey(e, v2632, v2633));
    const v2635 = try o.lookup(&s, frame, "binding2630");
    const v2636 = try s.call(v2634, v2632, &.{v2635});
    const v2638 = logical2637: {
        if (!s.truthy(v2636)) break :logical2637 v2636;
        const v2639 = try o.importValue(&s, graph, "guard/guard.mjs", "*");
        const v2640 = try s.text("IsGreaterEqualThan");
        const v2641 = try s.own(try js.getKey(e, v2639, v2640));
        const v2642 = try o.lookup(&s, frame, "binding2630");
        const v2643 = try s.call(v2641, v2639, &.{ v2642, c.JS_NewFloat64(e.context, 0) });
        break :logical2637 v2643;
    };
    const v2645 = logical2644: {
        if (!s.truthy(v2638)) break :logical2644 v2638;
        const v2646 = try o.importValue(&s, graph, "guard/guard.mjs", "*");
        const v2647 = try s.text("IsLessEqualThan");
        const v2648 = try s.own(try js.getKey(e, v2646, v2647));
        const v2649 = try o.lookup(&s, frame, "binding2630");
        const v2650 = try s.call(v2648, v2646, &.{ v2649, c.JS_NewFloat64(e.context, 255) });
        break :logical2644 v2650;
    };
    return c.JS_DupValue(e.context, v2645);
}
fn body2652(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v2654 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding2653", v2654);
    const v2655 = try o.importValue(&s, graph, "guard/guard.mjs", "*");
    const v2656 = try s.text("IsInteger");
    const v2657 = try s.own(try js.getKey(e, v2655, v2656));
    const v2658 = try o.lookup(&s, frame, "binding2653");
    const v2659 = try s.call(v2657, v2655, &.{v2658});
    const v2661 = logical2660: {
        if (!s.truthy(v2659)) break :logical2660 v2659;
        const v2662 = try o.importValue(&s, graph, "guard/guard.mjs", "*");
        const v2663 = try s.text("IsGreaterEqualThan");
        const v2664 = try s.own(try js.getKey(e, v2662, v2663));
        const v2665 = try o.lookup(&s, frame, "binding2653");
        const v2666 = try s.call(v2664, v2662, &.{ v2665, c.JS_NewFloat64(e.context, 0) });
        break :logical2660 v2666;
    };
    const v2668 = logical2667: {
        if (!s.truthy(v2661)) break :logical2667 v2661;
        const v2669 = try o.importValue(&s, graph, "guard/guard.mjs", "*");
        const v2670 = try s.text("IsLessEqualThan");
        const v2671 = try s.own(try js.getKey(e, v2669, v2670));
        const v2672 = try o.lookup(&s, frame, "binding2653");
        const v2673 = try s.call(v2671, v2669, &.{ v2672, c.JS_NewFloat64(e.context, 65535) });
        break :logical2667 v2673;
    };
    return c.JS_DupValue(e.context, v2668);
}
fn body2675(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v2677 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding2676", v2677);
    const v2678 = try o.importValue(&s, graph, "guard/guard.mjs", "*");
    const v2679 = try s.text("IsInteger");
    const v2680 = try s.own(try js.getKey(e, v2678, v2679));
    const v2681 = try o.lookup(&s, frame, "binding2676");
    const v2682 = try s.call(v2680, v2678, &.{v2681});
    const v2684 = logical2683: {
        if (!s.truthy(v2682)) break :logical2683 v2682;
        const v2685 = try o.importValue(&s, graph, "guard/guard.mjs", "*");
        const v2686 = try s.text("IsGreaterEqualThan");
        const v2687 = try s.own(try js.getKey(e, v2685, v2686));
        const v2688 = try o.lookup(&s, frame, "binding2676");
        const v2689 = try s.call(v2687, v2685, &.{ v2688, c.JS_NewFloat64(e.context, 0) });
        break :logical2683 v2689;
    };
    const v2691 = logical2690: {
        if (!s.truthy(v2684)) break :logical2690 v2684;
        const v2692 = try o.importValue(&s, graph, "guard/guard.mjs", "*");
        const v2693 = try s.text("IsLessEqualThan");
        const v2694 = try s.own(try js.getKey(e, v2692, v2693));
        const v2695 = try o.lookup(&s, frame, "binding2676");
        const v2696 = try s.call(v2694, v2692, &.{ v2695, c.JS_NewFloat64(e.context, 4294967295) });
        break :logical2690 v2696;
    };
    return c.JS_DupValue(e.context, v2691);
}
fn body2698(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v2700 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding2699", v2700);
    const v2701 = try o.importValue(&s, graph, "guard/guard.mjs", "*");
    const v2702 = try s.text("IsInteger");
    const v2703 = try s.own(try js.getKey(e, v2701, v2702));
    const v2704 = try o.lookup(&s, frame, "binding2699");
    const v2705 = try s.call(v2703, v2701, &.{v2704});
    const v2707 = logical2706: {
        if (!s.truthy(v2705)) break :logical2706 v2705;
        const v2708 = try o.importValue(&s, graph, "guard/guard.mjs", "*");
        const v2709 = try s.text("IsGreaterEqualThan");
        const v2710 = try s.own(try js.getKey(e, v2708, v2709));
        const v2711 = try o.lookup(&s, frame, "binding2699");
        const v2712 = try s.call(v2710, v2708, &.{ v2711, c.JS_NewFloat64(e.context, 0) });
        break :logical2706 v2712;
    };
    return c.JS_DupValue(e.context, v2707);
}
fn body2714(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v2716 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding2715", v2716);
    const v2717 = try o.importValue(&s, graph, "guard/guard.mjs", "*");
    const v2718 = try s.text("IsInteger");
    const v2719 = try s.own(try js.getKey(e, v2717, v2718));
    const v2720 = try o.lookup(&s, frame, "binding2715");
    const v2721 = try s.call(v2719, v2717, &.{v2720});
    const v2723 = logical2722: {
        if (!s.truthy(v2721)) break :logical2722 v2721;
        const v2724 = try o.importValue(&s, graph, "guard/guard.mjs", "*");
        const v2725 = try s.text("IsGreaterEqualThan");
        const v2726 = try s.own(try js.getKey(e, v2724, v2725));
        const v2727 = try o.lookup(&s, frame, "binding2715");
        const v2728 = try o.negate(&s, c.JS_NewFloat64(e.context, 128));
        const v2729 = try s.call(v2726, v2724, &.{ v2727, v2728 });
        break :logical2722 v2729;
    };
    const v2731 = logical2730: {
        if (!s.truthy(v2723)) break :logical2730 v2723;
        const v2732 = try o.importValue(&s, graph, "guard/guard.mjs", "*");
        const v2733 = try s.text("IsLessEqualThan");
        const v2734 = try s.own(try js.getKey(e, v2732, v2733));
        const v2735 = try o.lookup(&s, frame, "binding2715");
        const v2736 = try s.call(v2734, v2732, &.{ v2735, c.JS_NewFloat64(e.context, 127) });
        break :logical2730 v2736;
    };
    return c.JS_DupValue(e.context, v2731);
}
fn body2738(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v2740 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding2739", v2740);
    const v2741 = try o.importValue(&s, graph, "guard/guard.mjs", "*");
    const v2742 = try s.text("IsInteger");
    const v2743 = try s.own(try js.getKey(e, v2741, v2742));
    const v2744 = try o.lookup(&s, frame, "binding2739");
    const v2745 = try s.call(v2743, v2741, &.{v2744});
    const v2747 = logical2746: {
        if (!s.truthy(v2745)) break :logical2746 v2745;
        const v2748 = try o.importValue(&s, graph, "guard/guard.mjs", "*");
        const v2749 = try s.text("IsGreaterEqualThan");
        const v2750 = try s.own(try js.getKey(e, v2748, v2749));
        const v2751 = try o.lookup(&s, frame, "binding2739");
        const v2752 = try o.negate(&s, c.JS_NewFloat64(e.context, 32768));
        const v2753 = try s.call(v2750, v2748, &.{ v2751, v2752 });
        break :logical2746 v2753;
    };
    const v2755 = logical2754: {
        if (!s.truthy(v2747)) break :logical2754 v2747;
        const v2756 = try o.importValue(&s, graph, "guard/guard.mjs", "*");
        const v2757 = try s.text("IsLessEqualThan");
        const v2758 = try s.own(try js.getKey(e, v2756, v2757));
        const v2759 = try o.lookup(&s, frame, "binding2739");
        const v2760 = try s.call(v2758, v2756, &.{ v2759, c.JS_NewFloat64(e.context, 32767) });
        break :logical2754 v2760;
    };
    return c.JS_DupValue(e.context, v2755);
}
fn body2762(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v2764 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding2763", v2764);
    const v2765 = try o.importValue(&s, graph, "guard/guard.mjs", "*");
    const v2766 = try s.text("IsInteger");
    const v2767 = try s.own(try js.getKey(e, v2765, v2766));
    const v2768 = try o.lookup(&s, frame, "binding2763");
    const v2769 = try s.call(v2767, v2765, &.{v2768});
    const v2771 = logical2770: {
        if (!s.truthy(v2769)) break :logical2770 v2769;
        const v2772 = try o.importValue(&s, graph, "guard/guard.mjs", "*");
        const v2773 = try s.text("IsGreaterEqualThan");
        const v2774 = try s.own(try js.getKey(e, v2772, v2773));
        const v2775 = try o.lookup(&s, frame, "binding2763");
        const v2776 = try o.negate(&s, c.JS_NewFloat64(e.context, 2147483648));
        const v2777 = try s.call(v2774, v2772, &.{ v2775, v2776 });
        break :logical2770 v2777;
    };
    const v2779 = logical2778: {
        if (!s.truthy(v2771)) break :logical2778 v2771;
        const v2780 = try o.importValue(&s, graph, "guard/guard.mjs", "*");
        const v2781 = try s.text("IsLessEqualThan");
        const v2782 = try s.own(try js.getKey(e, v2780, v2781));
        const v2783 = try o.lookup(&s, frame, "binding2763");
        const v2784 = try s.call(v2782, v2780, &.{ v2783, c.JS_NewFloat64(e.context, 2147483647) });
        break :logical2778 v2784;
    };
    return c.JS_DupValue(e.context, v2779);
}
fn body2786(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v2788 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding2787", v2788);
    const v2789 = try o.importValue(&s, graph, "guard/guard.mjs", "*");
    const v2790 = try s.text("IsBigInt");
    const v2791 = try s.own(try js.getKey(e, v2789, v2790));
    const v2792 = try o.lookup(&s, frame, "binding2787");
    const v2793 = try s.call(v2791, v2789, &.{v2792});
    const v2795 = logical2794: {
        if (!s.truthy(v2793)) break :logical2794 v2793;
        const v2796 = try o.importValue(&s, graph, "guard/guard.mjs", "*");
        const v2797 = try s.text("IsGreaterEqualThan");
        const v2798 = try s.own(try js.getKey(e, v2796, v2797));
        const v2799 = try o.lookup(&s, frame, "binding2787");
        const v2800 = try s.global("BigInt");
        const v2801 = try s.text("-9223372036854775808");
        const v2802 = try s.call(v2800, c.pi_js_undefined(), &.{v2801});
        const v2803 = try s.call(v2798, v2796, &.{ v2799, v2802 });
        break :logical2794 v2803;
    };
    const v2805 = logical2804: {
        if (!s.truthy(v2795)) break :logical2804 v2795;
        const v2806 = try o.importValue(&s, graph, "guard/guard.mjs", "*");
        const v2807 = try s.text("IsLessEqualThan");
        const v2808 = try s.own(try js.getKey(e, v2806, v2807));
        const v2809 = try o.lookup(&s, frame, "binding2787");
        const v2810 = try s.global("BigInt");
        const v2811 = try s.text("9223372036854775807");
        const v2812 = try s.call(v2810, c.pi_js_undefined(), &.{v2811});
        const v2813 = try s.call(v2808, v2806, &.{ v2809, v2812 });
        break :logical2804 v2813;
    };
    return c.JS_DupValue(e.context, v2805);
}
