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
    const namespace = try s.get(modules, "value/codec/has.mjs");
    const frame = try o.frame(&s, c.pi_js_null());
    try s.put(frame, "@this", c.pi_js_undefined());
    try s.put(try s.get(graph, "frames"), "value/codec/has.mjs", frame);
    const bindings = try s.object();
    try s.put(try s.get(graph, "bindings"), "value/codec/has.mjs", bindings);
    const v25676 = try s.own(try ordinary.create(e, "FromArray", 2, body25660, &.{ graph, frame }));
    try o.assign(&s, frame, "binding25649", v25676);
    const v25699 = try s.own(try ordinary.create(e, "FromCyclic", 2, body25677, &.{ graph, frame }));
    try o.assign(&s, frame, "binding25650", v25699);
    const v25725 = try s.own(try ordinary.create(e, "FromIntersect", 2, body25700, &.{ graph, frame }));
    try o.assign(&s, frame, "binding25651", v25725);
    const v25760 = try s.own(try ordinary.create(e, "FromObject", 2, body25726, &.{ graph, frame }));
    try o.assign(&s, frame, "binding25652", v25760);
    const v25777 = try s.own(try ordinary.create(e, "FromRecord", 2, body25761, &.{ graph, frame }));
    try o.assign(&s, frame, "binding25653", v25777);
    const v25821 = try s.own(try ordinary.create(e, "FromRef", 2, body25778, &.{ graph, frame }));
    try o.assign(&s, frame, "binding25654", v25821);
    const v25847 = try s.own(try ordinary.create(e, "FromTuple", 2, body25822, &.{ graph, frame }));
    try o.assign(&s, frame, "binding25655", v25847);
    const v25873 = try s.own(try ordinary.create(e, "FromUnion", 2, body25848, &.{ graph, frame }));
    try o.assign(&s, frame, "binding25656", v25873);
    const v25954 = try s.own(try ordinary.create(e, "FromType", 2, body25874, &.{ graph, frame }));
    try o.assign(&s, frame, "binding25657", v25954);
    const v25999 = try s.own(try ordinary.create(e, "HasCodec", 0, body25955, &.{ graph, frame }));
    try o.assign(&s, frame, "binding25659", v25999);
    const v26000 = try o.lookup(&s, frame, "binding25659");
    try s.put(namespace, "HasCodec", v26000);
    const v26001 = try s.global("Set");
    const v26002 = try o.construct(&s, v26001, &.{});
    try o.assign(&s, frame, "binding25658", v26002);
    const v26003 = try o.lookup(&s, frame, "binding25659");
    try s.put(namespace, "HasCodec", v26003);
    try s.put(bindings, "HasCodec", try s.text("binding25659"));
}
fn body25660(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v25663 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding25661", v25663);
    const v25664 = if (args.len > 1) args[1] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding25662", v25664);
    const v25665 = try o.importValue(&s, graph, "type/index.mjs", "IsCodec");
    const v25666 = try o.lookup(&s, frame, "binding25662");
    const v25667 = try s.call(v25665, c.pi_js_undefined(), &.{v25666});
    const v25669 = logical25668: {
        if (s.truthy(v25667)) break :logical25668 v25667;
        const v25670 = try o.lookup(&s, frame, "binding25657");
        const v25671 = try o.lookup(&s, frame, "binding25661");
        const v25672 = try o.lookup(&s, frame, "binding25662");
        const v25673 = try s.text("items");
        const v25674 = try s.own(try js.getKey(e, v25672, v25673));
        const v25675 = try s.call(v25670, c.pi_js_undefined(), &.{ v25671, v25674 });
        break :logical25668 v25675;
    };
    return c.JS_DupValue(e.context, v25669);
}
fn body25677(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v25680 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding25678", v25680);
    const v25681 = if (args.len > 1) args[1] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding25679", v25681);
    const v25682 = try o.importValue(&s, graph, "type/index.mjs", "IsCodec");
    const v25683 = try o.lookup(&s, frame, "binding25679");
    const v25684 = try s.call(v25682, c.pi_js_undefined(), &.{v25683});
    const v25686 = logical25685: {
        if (s.truthy(v25684)) break :logical25685 v25684;
        const v25687 = try o.lookup(&s, frame, "binding25654");
        const v25688 = try s.object();
        const v25689 = try o.lookup(&s, frame, "binding25678");
        try js.spreadInto(e, v25688, v25689);
        const v25690 = try o.lookup(&s, frame, "binding25679");
        const v25691 = try s.text("$defs");
        const v25692 = try s.own(try js.getKey(e, v25690, v25691));
        try js.spreadInto(e, v25688, v25692);
        const v25693 = try o.importValue(&s, graph, "type/index.mjs", "Ref");
        const v25694 = try o.lookup(&s, frame, "binding25679");
        const v25695 = try s.text("$ref");
        const v25696 = try s.own(try js.getKey(e, v25694, v25695));
        const v25697 = try s.call(v25693, c.pi_js_undefined(), &.{v25696});
        const v25698 = try s.call(v25687, c.pi_js_undefined(), &.{ v25688, v25697 });
        break :logical25685 v25698;
    };
    return c.JS_DupValue(e.context, v25686);
}
fn body25715(e: *Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    _ = roots[0];
    const frame = try o.frame(&s, roots[1]);
    _ = try o.lookup(&s, frame, "@this");
    const v25718 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding25717", v25718);
    const v25719 = try o.lookup(&s, frame, "binding25657");
    const v25720 = try o.lookup(&s, frame, "binding25701");
    const v25721 = try o.lookup(&s, frame, "binding25717");
    const v25722 = try s.call(v25719, c.pi_js_undefined(), &.{ v25720, v25721 });
    return c.JS_DupValue(e.context, v25722);
}
fn body25715C(ctx: ?*c.JSContext, receiver: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const e = Engine.fromContext(ctx.?);
    return body25715(e, receiver, if (argc > 0) argv[0..@intCast(argc)] else &.{}, roots[0..2]) catch |err| sdk.fail(e, err);
}
fn body25700(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v25703 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding25701", v25703);
    const v25704 = if (args.len > 1) args[1] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding25702", v25704);
    const v25705 = try o.importValue(&s, graph, "type/index.mjs", "IsCodec");
    const v25706 = try o.lookup(&s, frame, "binding25702");
    const v25707 = try s.call(v25705, c.pi_js_undefined(), &.{v25706});
    const v25709 = logical25708: {
        if (s.truthy(v25707)) break :logical25708 v25707;
        const v25710 = try o.lookup(&s, frame, "binding25702");
        const v25711 = try s.text("allOf");
        const v25712 = try s.own(try js.getKey(e, v25710, v25711));
        const v25713 = try s.text("some");
        const v25714 = try s.own(try js.getKey(e, v25712, v25713));
        const v25723 = try o.arrow(&s, "", 1, body25715C, &.{ graph, frame });
        const v25724 = try s.call(v25714, v25712, &.{v25723});
        break :logical25708 v25724;
    };
    return c.JS_DupValue(e.context, v25709);
}
fn body25745(e: *Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    _ = roots[0];
    const frame = try o.frame(&s, roots[1]);
    _ = try o.lookup(&s, frame, "@this");
    const v25748 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding25747", v25748);
    const v25749 = try o.lookup(&s, frame, "binding25657");
    const v25750 = try o.lookup(&s, frame, "binding25727");
    const v25751 = try o.lookup(&s, frame, "binding25728");
    const v25752 = try s.text("properties");
    const v25753 = try s.own(try js.getKey(e, v25751, v25752));
    const v25754 = try o.lookup(&s, frame, "binding25747");
    const v25755 = try o.propertyKey(&s, v25754);
    const v25756 = try s.own(try js.getKey(e, v25753, v25755));
    const v25757 = try s.call(v25749, c.pi_js_undefined(), &.{ v25750, v25756 });
    return c.JS_DupValue(e.context, v25757);
}
fn body25745C(ctx: ?*c.JSContext, receiver: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const e = Engine.fromContext(ctx.?);
    return body25745(e, receiver, if (argc > 0) argv[0..@intCast(argc)] else &.{}, roots[0..2]) catch |err| sdk.fail(e, err);
}
fn body25726(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v25729 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding25727", v25729);
    const v25730 = if (args.len > 1) args[1] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding25728", v25730);
    const v25731 = try o.importValue(&s, graph, "type/index.mjs", "IsCodec");
    const v25732 = try o.lookup(&s, frame, "binding25728");
    const v25733 = try s.call(v25731, c.pi_js_undefined(), &.{v25732});
    const v25735 = logical25734: {
        if (s.truthy(v25733)) break :logical25734 v25733;
        const v25736 = try o.importValue(&s, graph, "guard/index.mjs", "Guard");
        const v25737 = try s.text("Keys");
        const v25738 = try s.own(try js.getKey(e, v25736, v25737));
        const v25739 = try o.lookup(&s, frame, "binding25728");
        const v25740 = try s.text("properties");
        const v25741 = try s.own(try js.getKey(e, v25739, v25740));
        const v25742 = try s.call(v25738, v25736, &.{v25741});
        const v25743 = try s.text("some");
        const v25744 = try s.own(try js.getKey(e, v25742, v25743));
        const v25758 = try o.arrow(&s, "", 1, body25745C, &.{ graph, frame });
        const v25759 = try s.call(v25744, v25742, &.{v25758});
        break :logical25734 v25759;
    };
    return c.JS_DupValue(e.context, v25735);
}
fn body25761(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v25764 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding25762", v25764);
    const v25765 = if (args.len > 1) args[1] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding25763", v25765);
    const v25766 = try o.importValue(&s, graph, "type/index.mjs", "IsCodec");
    const v25767 = try o.lookup(&s, frame, "binding25763");
    const v25768 = try s.call(v25766, c.pi_js_undefined(), &.{v25767});
    const v25770 = logical25769: {
        if (s.truthy(v25768)) break :logical25769 v25768;
        const v25771 = try o.lookup(&s, frame, "binding25657");
        const v25772 = try o.lookup(&s, frame, "binding25762");
        const v25773 = try o.importValue(&s, graph, "type/index.mjs", "RecordValue");
        const v25774 = try o.lookup(&s, frame, "binding25763");
        const v25775 = try s.call(v25773, c.pi_js_undefined(), &.{v25774});
        const v25776 = try s.call(v25771, c.pi_js_undefined(), &.{ v25772, v25775 });
        break :logical25769 v25776;
    };
    return c.JS_DupValue(e.context, v25770);
}
fn body25778(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v25781 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding25779", v25781);
    const v25782 = if (args.len > 1) args[1] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding25780", v25782);
    const v25783 = try o.lookup(&s, frame, "binding25658");
    const v25784 = try s.text("has");
    const v25785 = try s.own(try js.getKey(e, v25783, v25784));
    const v25786 = try o.lookup(&s, frame, "binding25780");
    const v25787 = try s.text("$ref");
    const v25788 = try s.own(try js.getKey(e, v25786, v25787));
    const v25789 = try s.call(v25785, v25783, &.{v25788});
    if (s.truthy(v25789)) {
        return c.JS_DupValue(e.context, o.boolean(&s, false));
    }
    const v25790 = try o.lookup(&s, frame, "binding25658");
    const v25791 = try s.text("add");
    const v25792 = try s.own(try js.getKey(e, v25790, v25791));
    const v25793 = try o.lookup(&s, frame, "binding25780");
    const v25794 = try s.text("$ref");
    const v25795 = try s.own(try js.getKey(e, v25793, v25794));
    const v25796 = try s.call(v25792, v25790, &.{v25795});
    _ = v25796;
    const v25797 = try o.importValue(&s, graph, "type/index.mjs", "IsCodec");
    const v25798 = try o.lookup(&s, frame, "binding25780");
    const v25799 = try s.call(v25797, c.pi_js_undefined(), &.{v25798});
    const v25801 = logical25800: {
        if (s.truthy(v25799)) break :logical25800 v25799;
        const v25802 = try o.importValue(&s, graph, "guard/index.mjs", "Guard");
        const v25803 = try s.text("HasPropertyKey");
        const v25804 = try s.own(try js.getKey(e, v25802, v25803));
        const v25805 = try o.lookup(&s, frame, "binding25779");
        const v25806 = try o.lookup(&s, frame, "binding25780");
        const v25807 = try s.text("$ref");
        const v25808 = try s.own(try js.getKey(e, v25806, v25807));
        const v25809 = try s.call(v25804, v25802, &.{ v25805, v25808 });
        const v25811 = logical25810: {
            if (!s.truthy(v25809)) break :logical25810 v25809;
            const v25812 = try o.lookup(&s, frame, "binding25657");
            const v25813 = try o.lookup(&s, frame, "binding25779");
            const v25814 = try o.lookup(&s, frame, "binding25779");
            const v25815 = try o.lookup(&s, frame, "binding25780");
            const v25816 = try s.text("$ref");
            const v25817 = try s.own(try js.getKey(e, v25815, v25816));
            const v25818 = try o.propertyKey(&s, v25817);
            const v25819 = try s.own(try js.getKey(e, v25814, v25818));
            const v25820 = try s.call(v25812, c.pi_js_undefined(), &.{ v25813, v25819 });
            break :logical25810 v25820;
        };
        break :logical25800 v25811;
    };
    return c.JS_DupValue(e.context, v25801);
}
fn body25837(e: *Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    _ = roots[0];
    const frame = try o.frame(&s, roots[1]);
    _ = try o.lookup(&s, frame, "@this");
    const v25840 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding25839", v25840);
    const v25841 = try o.lookup(&s, frame, "binding25657");
    const v25842 = try o.lookup(&s, frame, "binding25823");
    const v25843 = try o.lookup(&s, frame, "binding25839");
    const v25844 = try s.call(v25841, c.pi_js_undefined(), &.{ v25842, v25843 });
    return c.JS_DupValue(e.context, v25844);
}
fn body25837C(ctx: ?*c.JSContext, receiver: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const e = Engine.fromContext(ctx.?);
    return body25837(e, receiver, if (argc > 0) argv[0..@intCast(argc)] else &.{}, roots[0..2]) catch |err| sdk.fail(e, err);
}
fn body25822(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v25825 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding25823", v25825);
    const v25826 = if (args.len > 1) args[1] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding25824", v25826);
    const v25827 = try o.importValue(&s, graph, "type/index.mjs", "IsCodec");
    const v25828 = try o.lookup(&s, frame, "binding25824");
    const v25829 = try s.call(v25827, c.pi_js_undefined(), &.{v25828});
    const v25831 = logical25830: {
        if (s.truthy(v25829)) break :logical25830 v25829;
        const v25832 = try o.lookup(&s, frame, "binding25824");
        const v25833 = try s.text("items");
        const v25834 = try s.own(try js.getKey(e, v25832, v25833));
        const v25835 = try s.text("some");
        const v25836 = try s.own(try js.getKey(e, v25834, v25835));
        const v25845 = try o.arrow(&s, "", 1, body25837C, &.{ graph, frame });
        const v25846 = try s.call(v25836, v25834, &.{v25845});
        break :logical25830 v25846;
    };
    return c.JS_DupValue(e.context, v25831);
}
fn body25863(e: *Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    _ = roots[0];
    const frame = try o.frame(&s, roots[1]);
    _ = try o.lookup(&s, frame, "@this");
    const v25866 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding25865", v25866);
    const v25867 = try o.lookup(&s, frame, "binding25657");
    const v25868 = try o.lookup(&s, frame, "binding25849");
    const v25869 = try o.lookup(&s, frame, "binding25865");
    const v25870 = try s.call(v25867, c.pi_js_undefined(), &.{ v25868, v25869 });
    return c.JS_DupValue(e.context, v25870);
}
fn body25863C(ctx: ?*c.JSContext, receiver: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const e = Engine.fromContext(ctx.?);
    return body25863(e, receiver, if (argc > 0) argv[0..@intCast(argc)] else &.{}, roots[0..2]) catch |err| sdk.fail(e, err);
}
fn body25848(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v25851 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding25849", v25851);
    const v25852 = if (args.len > 1) args[1] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding25850", v25852);
    const v25853 = try o.importValue(&s, graph, "type/index.mjs", "IsCodec");
    const v25854 = try o.lookup(&s, frame, "binding25850");
    const v25855 = try s.call(v25853, c.pi_js_undefined(), &.{v25854});
    const v25857 = logical25856: {
        if (s.truthy(v25855)) break :logical25856 v25855;
        const v25858 = try o.lookup(&s, frame, "binding25850");
        const v25859 = try s.text("anyOf");
        const v25860 = try s.own(try js.getKey(e, v25858, v25859));
        const v25861 = try s.text("some");
        const v25862 = try s.own(try js.getKey(e, v25860, v25861));
        const v25871 = try o.arrow(&s, "", 1, body25863C, &.{ graph, frame });
        const v25872 = try s.call(v25862, v25860, &.{v25871});
        break :logical25856 v25872;
    };
    return c.JS_DupValue(e.context, v25857);
}
fn body25874(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v25877 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding25875", v25877);
    const v25878 = if (args.len > 1) args[1] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding25876", v25878);
    const v25879 = try o.importValue(&s, graph, "type/index.mjs", "IsArray");
    const v25880 = try o.lookup(&s, frame, "binding25876");
    const v25881 = try s.call(v25879, c.pi_js_undefined(), &.{v25880});
    const v25883 = conditional25882: {
        if (s.truthy(v25881)) {
            const v25884 = try o.lookup(&s, frame, "binding25649");
            const v25885 = try o.lookup(&s, frame, "binding25875");
            const v25886 = try o.lookup(&s, frame, "binding25876");
            const v25887 = try s.call(v25884, c.pi_js_undefined(), &.{ v25885, v25886 });
            break :conditional25882 v25887;
        } else {
            const v25888 = try o.importValue(&s, graph, "type/index.mjs", "IsCyclic");
            const v25889 = try o.lookup(&s, frame, "binding25876");
            const v25890 = try s.call(v25888, c.pi_js_undefined(), &.{v25889});
            const v25892 = conditional25891: {
                if (s.truthy(v25890)) {
                    const v25893 = try o.lookup(&s, frame, "binding25650");
                    const v25894 = try o.lookup(&s, frame, "binding25875");
                    const v25895 = try o.lookup(&s, frame, "binding25876");
                    const v25896 = try s.call(v25893, c.pi_js_undefined(), &.{ v25894, v25895 });
                    break :conditional25891 v25896;
                } else {
                    const v25897 = try o.importValue(&s, graph, "type/index.mjs", "IsIntersect");
                    const v25898 = try o.lookup(&s, frame, "binding25876");
                    const v25899 = try s.call(v25897, c.pi_js_undefined(), &.{v25898});
                    const v25901 = conditional25900: {
                        if (s.truthy(v25899)) {
                            const v25902 = try o.lookup(&s, frame, "binding25651");
                            const v25903 = try o.lookup(&s, frame, "binding25875");
                            const v25904 = try o.lookup(&s, frame, "binding25876");
                            const v25905 = try s.call(v25902, c.pi_js_undefined(), &.{ v25903, v25904 });
                            break :conditional25900 v25905;
                        } else {
                            const v25906 = try o.importValue(&s, graph, "type/index.mjs", "IsObject");
                            const v25907 = try o.lookup(&s, frame, "binding25876");
                            const v25908 = try s.call(v25906, c.pi_js_undefined(), &.{v25907});
                            const v25910 = conditional25909: {
                                if (s.truthy(v25908)) {
                                    const v25911 = try o.lookup(&s, frame, "binding25652");
                                    const v25912 = try o.lookup(&s, frame, "binding25875");
                                    const v25913 = try o.lookup(&s, frame, "binding25876");
                                    const v25914 = try s.call(v25911, c.pi_js_undefined(), &.{ v25912, v25913 });
                                    break :conditional25909 v25914;
                                } else {
                                    const v25915 = try o.importValue(&s, graph, "type/index.mjs", "IsRecord");
                                    const v25916 = try o.lookup(&s, frame, "binding25876");
                                    const v25917 = try s.call(v25915, c.pi_js_undefined(), &.{v25916});
                                    const v25919 = conditional25918: {
                                        if (s.truthy(v25917)) {
                                            const v25920 = try o.lookup(&s, frame, "binding25653");
                                            const v25921 = try o.lookup(&s, frame, "binding25875");
                                            const v25922 = try o.lookup(&s, frame, "binding25876");
                                            const v25923 = try s.call(v25920, c.pi_js_undefined(), &.{ v25921, v25922 });
                                            break :conditional25918 v25923;
                                        } else {
                                            const v25924 = try o.importValue(&s, graph, "type/index.mjs", "IsRef");
                                            const v25925 = try o.lookup(&s, frame, "binding25876");
                                            const v25926 = try s.call(v25924, c.pi_js_undefined(), &.{v25925});
                                            const v25928 = conditional25927: {
                                                if (s.truthy(v25926)) {
                                                    const v25929 = try o.lookup(&s, frame, "binding25654");
                                                    const v25930 = try o.lookup(&s, frame, "binding25875");
                                                    const v25931 = try o.lookup(&s, frame, "binding25876");
                                                    const v25932 = try s.call(v25929, c.pi_js_undefined(), &.{ v25930, v25931 });
                                                    break :conditional25927 v25932;
                                                } else {
                                                    const v25933 = try o.importValue(&s, graph, "type/index.mjs", "IsTuple");
                                                    const v25934 = try o.lookup(&s, frame, "binding25876");
                                                    const v25935 = try s.call(v25933, c.pi_js_undefined(), &.{v25934});
                                                    const v25937 = conditional25936: {
                                                        if (s.truthy(v25935)) {
                                                            const v25938 = try o.lookup(&s, frame, "binding25655");
                                                            const v25939 = try o.lookup(&s, frame, "binding25875");
                                                            const v25940 = try o.lookup(&s, frame, "binding25876");
                                                            const v25941 = try s.call(v25938, c.pi_js_undefined(), &.{ v25939, v25940 });
                                                            break :conditional25936 v25941;
                                                        } else {
                                                            const v25942 = try o.importValue(&s, graph, "type/index.mjs", "IsUnion");
                                                            const v25943 = try o.lookup(&s, frame, "binding25876");
                                                            const v25944 = try s.call(v25942, c.pi_js_undefined(), &.{v25943});
                                                            const v25946 = conditional25945: {
                                                                if (s.truthy(v25944)) {
                                                                    const v25947 = try o.lookup(&s, frame, "binding25656");
                                                                    const v25948 = try o.lookup(&s, frame, "binding25875");
                                                                    const v25949 = try o.lookup(&s, frame, "binding25876");
                                                                    const v25950 = try s.call(v25947, c.pi_js_undefined(), &.{ v25948, v25949 });
                                                                    break :conditional25945 v25950;
                                                                } else {
                                                                    const v25951 = try o.importValue(&s, graph, "type/index.mjs", "IsCodec");
                                                                    const v25952 = try o.lookup(&s, frame, "binding25876");
                                                                    const v25953 = try s.call(v25951, c.pi_js_undefined(), &.{v25952});
                                                                    break :conditional25945 v25953;
                                                                }
                                                            };
                                                            break :conditional25936 v25946;
                                                        }
                                                    };
                                                    break :conditional25927 v25937;
                                                }
                                            };
                                            break :conditional25918 v25928;
                                        }
                                    };
                                    break :conditional25909 v25919;
                                }
                            };
                            break :conditional25900 v25910;
                        }
                    };
                    break :conditional25891 v25901;
                }
            };
            break :conditional25882 v25892;
        }
    };
    return c.JS_DupValue(e.context, v25883);
}
fn body25968(e: *Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    _ = roots[0];
    const frame = try o.frame(&s, roots[1]);
    _ = try o.lookup(&s, frame, "@this");
    const v25972 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding25970", v25972);
    const v25973 = if (args.len > 1) args[1] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding25971", v25973);
    const v25974 = try s.array();
    const v25975 = try o.lookup(&s, frame, "binding25970");
    try o.append(&s, v25974, v25975);
    const v25976 = try o.lookup(&s, frame, "binding25971");
    try o.append(&s, v25974, v25976);
    return c.JS_DupValue(e.context, v25974);
}
fn body25968C(ctx: ?*c.JSContext, receiver: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const e = Engine.fromContext(ctx.?);
    return body25968(e, receiver, if (argc > 0) argv[0..@intCast(argc)] else &.{}, roots[0..2]) catch |err| sdk.fail(e, err);
}
fn body25979(e: *Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    _ = roots[0];
    const frame = try o.frame(&s, roots[1]);
    _ = try o.lookup(&s, frame, "@this");
    const v25982 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding25981", v25982);
    const v25983 = try s.array();
    const v25984 = try s.object();
    try o.append(&s, v25983, v25984);
    const v25985 = try o.lookup(&s, frame, "binding25981");
    try o.append(&s, v25983, v25985);
    return c.JS_DupValue(e.context, v25983);
}
fn body25979C(ctx: ?*c.JSContext, receiver: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const e = Engine.fromContext(ctx.?);
    return body25979(e, receiver, if (argc > 0) argv[0..@intCast(argc)] else &.{}, roots[0..2]) catch |err| sdk.fail(e, err);
}
fn body25955(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v25959 = try o.rest(&s, args, 0);
    try o.assign(&s, frame, "binding25956", v25959);
    const v25962 = try o.importValue(&s, graph, "system/arguments/index.mjs", "Arguments");
    const v25963 = try s.text("Match");
    const v25964 = try s.own(try js.getKey(e, v25962, v25963));
    const v25965 = try o.lookup(&s, frame, "binding25956");
    const v25966 = try s.object();
    const v25967 = try s.text("2");
    const v25977 = try o.arrow(&s, "2", 2, body25968C, &.{ graph, frame });
    try o.defineKey(&s, v25966, v25967, v25977);
    const v25978 = try s.text("1");
    const v25986 = try o.arrow(&s, "1", 1, body25979C, &.{ graph, frame });
    try o.defineKey(&s, v25966, v25978, v25986);
    const v25987 = try s.call(v25964, v25962, &.{ v25965, v25966 });
    var destructure25988 = try o.iterator(e, v25987);
    defer destructure25988.deinit();
    errdefer destructure25988.closePreserving();
    const v25989 = try s.own(if (destructure25988.closed) c.pi_js_undefined() else (try destructure25988.next()) orelse c.pi_js_undefined());
    try o.assign(&s, frame, "binding25960", v25989);
    const v25990 = try s.own(if (destructure25988.closed) c.pi_js_undefined() else (try destructure25988.next()) orelse c.pi_js_undefined());
    try o.assign(&s, frame, "binding25961", v25990);
    try destructure25988.close();
    const v25991 = try o.lookup(&s, frame, "binding25658");
    const v25992 = try s.text("clear");
    const v25993 = try s.own(try js.getKey(e, v25991, v25992));
    const v25994 = try s.call(v25993, v25991, &.{});
    _ = v25994;
    const v25995 = try o.lookup(&s, frame, "binding25657");
    const v25996 = try o.lookup(&s, frame, "binding25960");
    const v25997 = try o.lookup(&s, frame, "binding25961");
    const v25998 = try s.call(v25995, c.pi_js_undefined(), &.{ v25996, v25997 });
    return c.JS_DupValue(e.context, v25998);
}
