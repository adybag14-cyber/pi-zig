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
    const namespace = try s.get(modules, "schema/resolve/resolve.mjs");
    const frame = try o.frame(&s, c.pi_js_null());
    try s.put(frame, "@this", c.pi_js_undefined());
    try s.put(try s.get(graph, "frames"), "schema/resolve/resolve.mjs", frame);
    const bindings = try s.object();
    try s.put(try s.get(graph, "bindings"), "schema/resolve/resolve.mjs", bindings);
    const v19687 = try s.own(try ordinary.create(e, "FindDynamicAnchor", 2, body19634, &.{ graph, frame }));
    try o.assign(&s, frame, "binding19608", v19687);
    const v19782 = try s.own(try ordinary.create(e, "FindBase", 3, body19688, &.{ graph, frame }));
    try o.assign(&s, frame, "binding19609", v19782);
    const v19835 = try s.own(try ordinary.create(e, "MatchId", 3, body19783, &.{ graph, frame }));
    try o.assign(&s, frame, "binding19610", v19835);
    const v19881 = try s.own(try ordinary.create(e, "MatchAnchor", 3, body19836, &.{ graph, frame }));
    try o.assign(&s, frame, "binding19611", v19881);
    const v19930 = try s.own(try ordinary.create(e, "MatchDynamicAnchor", 3, body19882, &.{ graph, frame }));
    try o.assign(&s, frame, "binding19612", v19930);
    const v19975 = try s.own(try ordinary.create(e, "MatchHash", 2, body19931, &.{ graph, frame }));
    try o.assign(&s, frame, "binding19613", v19975);
    const v20038 = try s.own(try ordinary.create(e, "Match", 3, body19976, &.{ graph, frame }));
    try o.assign(&s, frame, "binding19614", v20038);
    const v20073 = try s.own(try ordinary.create(e, "FromArray", 3, body20039, &.{ graph, frame }));
    try o.assign(&s, frame, "binding19615", v20073);
    const v20091 = try s.own(try ordinary.create(e, "SkipProperty", 1, body20074, &.{ graph, frame }));
    try o.assign(&s, frame, "binding19616", v20091);
    const v20137 = try s.own(try ordinary.create(e, "FromObject", 3, body20092, &.{ graph, frame }));
    try o.assign(&s, frame, "binding19617", v20137);
    const v20207 = try s.own(try ordinary.create(e, "FromValue", 3, body20138, &.{ graph, frame }));
    try o.assign(&s, frame, "binding19618", v20207);
    const v20226 = try s.own(try ordinary.create(e, "Base", 3, body20208, &.{ graph, frame }));
    try o.assign(&s, frame, "binding19619", v20226);
    const v20259 = try s.own(try ordinary.create(e, "Resource", 4, body20227, &.{ graph, frame }));
    try o.assign(&s, frame, "binding19620", v20259);
    const v20272 = try s.own(try ordinary.create(e, "CanonicalHref", 1, body20260, &.{ graph, frame }));
    try o.assign(&s, frame, "binding19621", v20272);
    const v20290 = try s.own(try ordinary.create(e, "RefContext", 2, body20273, &.{ graph, frame }));
    try o.assign(&s, frame, "binding19622", v20290);
    const v20303 = try s.own(try ordinary.create(e, "RefLocal", 3, body20291, &.{ graph, frame }));
    try o.assign(&s, frame, "binding19623", v20303);
    const v20380 = try s.own(try ordinary.create(e, "RefRemote", 3, body20304, &.{ graph, frame }));
    try o.assign(&s, frame, "binding19624", v20380);
    const v20432 = try s.own(try ordinary.create(e, "LegacyRetrievedResource", 5, body20381, &.{ graph, frame }));
    try o.assign(&s, frame, "binding19625", v20432);
    const v20458 = try s.own(try ordinary.create(e, "RemoteRetrievedResource", 3, body20433, &.{ graph, frame }));
    try o.assign(&s, frame, "binding19626", v20458);
    const v20501 = try s.own(try ordinary.create(e, "FindRetrievedResource", 5, body20459, &.{ graph, frame }));
    try o.assign(&s, frame, "binding19627", v20501);
    const v20541 = try s.own(try ordinary.create(e, "FindResolvedResource", 6, body20502, &.{ graph, frame }));
    try o.assign(&s, frame, "binding19628", v20541);
    const v20608 = try s.own(try ordinary.create(e, "Ref", 4, body20542, &.{ graph, frame }));
    try o.assign(&s, frame, "binding19629", v20608);
    const v20766 = try s.own(try ordinary.create(e, "DynamicRef", 6, body20609, &.{ graph, frame }));
    try o.assign(&s, frame, "binding19630", v20766);
    const v20890 = try s.own(try ordinary.create(e, "ResolveRef", 2, body20767, &.{ graph, frame }));
    try o.assign(&s, frame, "binding19631", v20890);
    const v20927 = try s.own(try ordinary.create(e, "ResolveRecursiveRef", 2, body20891, &.{ graph, frame }));
    try o.assign(&s, frame, "binding19632", v20927);
    const v20951 = try s.own(try ordinary.create(e, "ResolveDynamicRef", 2, body20928, &.{ graph, frame }));
    try o.assign(&s, frame, "binding19633", v20951);
    const v20952 = try o.lookup(&s, frame, "binding19607");
    try s.put(namespace, "DefaultBase", v20952);
    const v20953 = try o.lookup(&s, frame, "binding19619");
    try s.put(namespace, "Base", v20953);
    const v20954 = try o.lookup(&s, frame, "binding19620");
    try s.put(namespace, "Resource", v20954);
    const v20955 = try o.lookup(&s, frame, "binding19629");
    try s.put(namespace, "Ref", v20955);
    const v20956 = try o.lookup(&s, frame, "binding19630");
    try s.put(namespace, "DynamicRef", v20956);
    const v20957 = try o.lookup(&s, frame, "binding19631");
    try s.put(namespace, "ResolveRef", v20957);
    const v20958 = try o.lookup(&s, frame, "binding19632");
    try s.put(namespace, "ResolveRecursiveRef", v20958);
    const v20959 = try o.lookup(&s, frame, "binding19633");
    try s.put(namespace, "ResolveDynamicRef", v20959);
    const v20960 = try s.text("https://json-schema.org");
    try o.assign(&s, frame, "binding19607", v20960);
    const v20961 = try o.lookup(&s, frame, "binding19607");
    try s.put(namespace, "DefaultBase", v20961);
    const v20962 = try o.lookup(&s, frame, "binding19619");
    try s.put(namespace, "Base", v20962);
    const v20963 = try o.lookup(&s, frame, "binding19620");
    try s.put(namespace, "Resource", v20963);
    const v20964 = try o.lookup(&s, frame, "binding19629");
    try s.put(namespace, "Ref", v20964);
    const v20965 = try o.lookup(&s, frame, "binding19630");
    try s.put(namespace, "DynamicRef", v20965);
    const v20966 = try o.lookup(&s, frame, "binding19631");
    try s.put(namespace, "ResolveRef", v20966);
    const v20967 = try o.lookup(&s, frame, "binding19632");
    try s.put(namespace, "ResolveRecursiveRef", v20967);
    const v20968 = try o.lookup(&s, frame, "binding19633");
    try s.put(namespace, "ResolveDynamicRef", v20968);
    try s.put(bindings, "DefaultBase", try s.text("binding19607"));
    try s.put(bindings, "Base", try s.text("binding19619"));
    try s.put(bindings, "Resource", try s.text("binding19620"));
    try s.put(bindings, "Ref", try s.text("binding19629"));
    try s.put(bindings, "DynamicRef", try s.text("binding19630"));
    try s.put(bindings, "ResolveRef", try s.text("binding19631"));
    try s.put(bindings, "ResolveRecursiveRef", try s.text("binding19632"));
    try s.put(bindings, "ResolveDynamicRef", try s.text("binding19633"));
}
fn body19634(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v19637 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding19635", v19637);
    const v19638 = if (args.len > 1) args[1] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding19636", v19638);
    const v19639 = try o.importValue(&s, graph, "guard/index.mjs", "Guard");
    const v19640 = try s.text("IsObject");
    const v19641 = try s.own(try js.getKey(e, v19639, v19640));
    const v19642 = try o.lookup(&s, frame, "binding19635");
    const v19643 = try s.call(v19641, v19639, &.{v19642});
    const v19645 = logical19644: {
        if (!s.truthy(v19643)) break :logical19644 v19643;
        const v19646 = try o.importValue(&s, graph, "schema/types/index.mjs", "*");
        const v19647 = try s.text("IsDynamicAnchor");
        const v19648 = try s.own(try js.getKey(e, v19646, v19647));
        const v19649 = try o.lookup(&s, frame, "binding19635");
        const v19650 = try s.call(v19648, v19646, &.{v19649});
        break :logical19644 v19650;
    };
    const v19652 = logical19651: {
        if (!s.truthy(v19645)) break :logical19651 v19645;
        const v19653 = try o.importValue(&s, graph, "guard/index.mjs", "Guard");
        const v19654 = try s.text("IsEqual");
        const v19655 = try s.own(try js.getKey(e, v19653, v19654));
        const v19656 = try o.lookup(&s, frame, "binding19635");
        const v19657 = try s.text("$dynamicAnchor");
        const v19658 = try s.own(try js.getKey(e, v19656, v19657));
        const v19659 = try o.lookup(&s, frame, "binding19636");
        const v19660 = try s.call(v19655, v19653, &.{ v19658, v19659 });
        break :logical19651 v19660;
    };
    if (s.truthy(v19652)) {
        const v19661 = try o.lookup(&s, frame, "binding19635");
        return c.JS_DupValue(e.context, v19661);
    }
    const v19662 = try o.importValue(&s, graph, "guard/index.mjs", "Guard");
    const v19663 = try s.text("IsObject");
    const v19664 = try s.own(try js.getKey(e, v19662, v19663));
    const v19665 = try o.lookup(&s, frame, "binding19635");
    const v19666 = try s.call(v19664, v19662, &.{v19665});
    if (s.truthy(v19666)) {
        const v19667 = try o.importValue(&s, graph, "guard/index.mjs", "Guard");
        const v19668 = try s.text("Keys");
        const v19669 = try s.own(try js.getKey(e, v19667, v19668));
        const v19670 = try o.lookup(&s, frame, "binding19635");
        const v19671 = try s.call(v19669, v19667, &.{v19670});
        var iterator19672 = try o.iterator(e, v19671);
        defer iterator19672.deinit();
        errdefer iterator19672.closePreserving();
        while (try iterator19672.next()) |next19673| {
            defer e.freeValue(next19673);
            const iteration19675 = try o.frame(&s, frame);
            try o.assign(&s, iteration19675, "binding19676", next19673);
            const v19678 = try o.lookup(&s, iteration19675, "binding19608");
            const v19679 = try o.lookup(&s, iteration19675, "binding19635");
            const v19680 = try o.lookup(&s, iteration19675, "binding19676");
            const v19681 = try o.propertyKey(&s, v19680);
            const v19682 = try s.own(try js.getKey(e, v19679, v19681));
            const v19683 = try o.lookup(&s, iteration19675, "binding19636");
            const v19684 = try s.call(v19678, c.pi_js_undefined(), &.{ v19682, v19683 });
            try o.assign(&s, iteration19675, "binding19677", v19684);
            const v19685 = try o.lookup(&s, iteration19675, "binding19677");
            if (s.truthy(v19685)) {
                const v19686 = try o.lookup(&s, iteration19675, "binding19677");
                try iterator19672.close();
                return c.JS_DupValue(e.context, v19686);
            }
        }
        try iterator19672.close();
    }
    return c.JS_DupValue(e.context, c.pi_js_undefined());
}
fn body19688(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v19693 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding19689", v19693);
    const v19694 = if (args.len > 1) args[1] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding19690", v19694);
    const v19695 = if (args.len > 2) args[2] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding19691", v19695);
    const v19697 = try o.importValue(&s, graph, "guard/index.mjs", "Guard");
    const v19698 = try s.text("IsEqual");
    const v19699 = try s.own(try js.getKey(e, v19697, v19698));
    const v19700 = try o.lookup(&s, frame, "binding19689");
    const v19701 = try o.lookup(&s, frame, "binding19691");
    const v19702 = try s.call(v19699, v19697, &.{ v19700, v19701 });
    if (s.truthy(v19702)) {
        const v19703 = try o.lookup(&s, frame, "binding19690");
        const v19704 = try s.text("href");
        const v19705 = try s.own(try js.getKey(e, v19703, v19704));
        return c.JS_DupValue(e.context, v19705);
    }
    const v19706 = try o.importValue(&s, graph, "schema/types/index.mjs", "*");
    const v19707 = try s.text("IsSchemaObject");
    const v19708 = try s.own(try js.getKey(e, v19706, v19707));
    const v19709 = try o.lookup(&s, frame, "binding19689");
    const v19710 = try s.call(v19708, v19706, &.{v19709});
    const v19712 = logical19711: {
        if (!s.truthy(v19710)) break :logical19711 v19710;
        const v19713 = try o.importValue(&s, graph, "schema/types/index.mjs", "*");
        const v19714 = try s.text("IsId");
        const v19715 = try s.own(try js.getKey(e, v19713, v19714));
        const v19716 = try o.lookup(&s, frame, "binding19689");
        const v19717 = try s.call(v19715, v19713, &.{v19716});
        break :logical19711 v19717;
    };
    const v19719 = conditional19718: {
        if (s.truthy(v19712)) {
            const v19720 = try s.global("URL");
            const v19721 = try o.lookup(&s, frame, "binding19689");
            const v19722 = try s.text("$id");
            const v19723 = try s.own(try js.getKey(e, v19721, v19722));
            const v19724 = try o.lookup(&s, frame, "binding19690");
            const v19725 = try s.text("href");
            const v19726 = try s.own(try js.getKey(e, v19724, v19725));
            const v19727 = try o.construct(&s, v19720, &.{ v19723, v19726 });
            break :conditional19718 v19727;
        } else {
            const v19728 = try o.lookup(&s, frame, "binding19690");
            break :conditional19718 v19728;
        }
    };
    try o.assign(&s, frame, "binding19696", v19719);
    const v19729 = try o.importValue(&s, graph, "guard/index.mjs", "Guard");
    const v19730 = try s.text("IsArray");
    const v19731 = try s.own(try js.getKey(e, v19729, v19730));
    const v19732 = try o.lookup(&s, frame, "binding19689");
    const v19733 = try s.call(v19731, v19729, &.{v19732});
    if (s.truthy(v19733)) {
        const v19734 = try o.lookup(&s, frame, "binding19689");
        var iterator19735 = try o.iterator(e, v19734);
        defer iterator19735.deinit();
        errdefer iterator19735.closePreserving();
        while (try iterator19735.next()) |next19736| {
            defer e.freeValue(next19736);
            const iteration19738 = try o.frame(&s, frame);
            try o.assign(&s, iteration19738, "binding19739", next19736);
            const v19741 = try o.lookup(&s, iteration19738, "binding19609");
            const v19742 = try o.lookup(&s, iteration19738, "binding19739");
            const v19743 = try o.lookup(&s, iteration19738, "binding19696");
            const v19744 = try o.lookup(&s, iteration19738, "binding19691");
            const v19745 = try s.call(v19741, c.pi_js_undefined(), &.{ v19742, v19743, v19744 });
            try o.assign(&s, iteration19738, "binding19740", v19745);
            const v19746 = try o.importValue(&s, graph, "guard/index.mjs", "Guard");
            const v19747 = try s.text("IsUndefined");
            const v19748 = try s.own(try js.getKey(e, v19746, v19747));
            const v19749 = try o.lookup(&s, iteration19738, "binding19740");
            const v19750 = try s.call(v19748, v19746, &.{v19749});
            if (s.truthy(o.boolean(&s, !s.truthy(v19750)))) {
                const v19751 = try o.lookup(&s, iteration19738, "binding19740");
                try iterator19735.close();
                return c.JS_DupValue(e.context, v19751);
            }
        }
        try iterator19735.close();
    } else {
        const v19752 = try o.importValue(&s, graph, "guard/index.mjs", "Guard");
        const v19753 = try s.text("IsObject");
        const v19754 = try s.own(try js.getKey(e, v19752, v19753));
        const v19755 = try o.lookup(&s, frame, "binding19689");
        const v19756 = try s.call(v19754, v19752, &.{v19755});
        if (s.truthy(v19756)) {
            const v19757 = try o.importValue(&s, graph, "guard/index.mjs", "Guard");
            const v19758 = try s.text("Keys");
            const v19759 = try s.own(try js.getKey(e, v19757, v19758));
            const v19760 = try o.lookup(&s, frame, "binding19689");
            const v19761 = try s.call(v19759, v19757, &.{v19760});
            var iterator19762 = try o.iterator(e, v19761);
            defer iterator19762.deinit();
            errdefer iterator19762.closePreserving();
            while (try iterator19762.next()) |next19763| {
                defer e.freeValue(next19763);
                const iteration19765 = try o.frame(&s, frame);
                try o.assign(&s, iteration19765, "binding19766", next19763);
                const v19768 = try o.lookup(&s, iteration19765, "binding19609");
                const v19769 = try o.lookup(&s, iteration19765, "binding19689");
                const v19770 = try o.lookup(&s, iteration19765, "binding19766");
                const v19771 = try o.propertyKey(&s, v19770);
                const v19772 = try s.own(try js.getKey(e, v19769, v19771));
                const v19773 = try o.lookup(&s, iteration19765, "binding19696");
                const v19774 = try o.lookup(&s, iteration19765, "binding19691");
                const v19775 = try s.call(v19768, c.pi_js_undefined(), &.{ v19772, v19773, v19774 });
                try o.assign(&s, iteration19765, "binding19767", v19775);
                const v19776 = try o.importValue(&s, graph, "guard/index.mjs", "Guard");
                const v19777 = try s.text("IsUndefined");
                const v19778 = try s.own(try js.getKey(e, v19776, v19777));
                const v19779 = try o.lookup(&s, iteration19765, "binding19767");
                const v19780 = try s.call(v19778, v19776, &.{v19779});
                if (s.truthy(o.boolean(&s, !s.truthy(v19780)))) {
                    const v19781 = try o.lookup(&s, iteration19765, "binding19767");
                    try iterator19762.close();
                    return c.JS_DupValue(e.context, v19781);
                }
            }
            try iterator19762.close();
        }
    }
    return c.JS_DupValue(e.context, c.pi_js_undefined());
}
fn body19783(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v19788 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding19784", v19788);
    const v19789 = if (args.len > 1) args[1] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding19785", v19789);
    const v19790 = if (args.len > 2) args[2] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding19786", v19790);
    const v19792 = try o.importValue(&s, graph, "guard/index.mjs", "Guard");
    const v19793 = try s.text("IsEqual");
    const v19794 = try s.own(try js.getKey(e, v19792, v19793));
    const v19795 = try o.lookup(&s, frame, "binding19784");
    const v19796 = try s.text("$id");
    const v19797 = try s.own(try js.getKey(e, v19795, v19796));
    const v19798 = try o.lookup(&s, frame, "binding19786");
    const v19799 = try s.text("hash");
    const v19800 = try s.own(try js.getKey(e, v19798, v19799));
    const v19801 = try s.call(v19794, v19792, &.{ v19797, v19800 });
    if (s.truthy(v19801)) {
        const v19802 = try o.lookup(&s, frame, "binding19784");
        return c.JS_DupValue(e.context, v19802);
    }
    const v19803 = try s.global("URL");
    const v19804 = try o.lookup(&s, frame, "binding19786");
    const v19805 = try s.text("href");
    const v19806 = try s.own(try js.getKey(e, v19804, v19805));
    const v19807 = try o.lookup(&s, frame, "binding19785");
    const v19808 = try s.text("href");
    const v19809 = try s.own(try js.getKey(e, v19807, v19808));
    const v19810 = try o.construct(&s, v19803, &.{ v19806, v19809 });
    try o.assign(&s, frame, "binding19791", v19810);
    const v19811 = try o.importValue(&s, graph, "guard/index.mjs", "Guard");
    const v19812 = try s.text("IsEqual");
    const v19813 = try s.own(try js.getKey(e, v19811, v19812));
    const v19814 = try o.lookup(&s, frame, "binding19785");
    const v19815 = try s.text("pathname");
    const v19816 = try s.own(try js.getKey(e, v19814, v19815));
    const v19817 = try o.lookup(&s, frame, "binding19791");
    const v19818 = try s.text("pathname");
    const v19819 = try s.own(try js.getKey(e, v19817, v19818));
    const v19820 = try s.call(v19813, v19811, &.{ v19816, v19819 });
    if (s.truthy(v19820)) {
        const v19821 = try o.lookup(&s, frame, "binding19786");
        const v19822 = try s.text("hash");
        const v19823 = try s.own(try js.getKey(e, v19821, v19822));
        const v19824 = try s.text("startsWith");
        const v19825 = try s.own(try js.getKey(e, v19823, v19824));
        const v19826 = try s.text("#");
        const v19827 = try s.call(v19825, v19823, &.{v19826});
        const v19829 = conditional19828: {
            if (s.truthy(v19827)) {
                const v19830 = try o.lookup(&s, frame, "binding19613");
                const v19831 = try o.lookup(&s, frame, "binding19784");
                const v19832 = try o.lookup(&s, frame, "binding19786");
                const v19833 = try s.call(v19830, c.pi_js_undefined(), &.{ v19831, v19832 });
                break :conditional19828 v19833;
            } else {
                const v19834 = try o.lookup(&s, frame, "binding19784");
                break :conditional19828 v19834;
            }
        };
        return c.JS_DupValue(e.context, v19829);
    }
    return c.JS_DupValue(e.context, c.pi_js_undefined());
}
fn body19836(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v19842 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding19837", v19842);
    const v19843 = if (args.len > 1) args[1] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding19838", v19843);
    const v19844 = if (args.len > 2) args[2] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding19839", v19844);
    const v19847 = try s.global("URL");
    const v19848 = try s.text("#");
    const v19849 = try o.lookup(&s, frame, "binding19837");
    const v19850 = try s.text("$anchor");
    const v19851 = try s.own(try js.getKey(e, v19849, v19850));
    const v19852 = try s.stringify(v19851);
    const v19853 = try s.concat(v19848, v19852);
    const v19854 = try s.text("");
    const v19855 = try s.concat(v19853, v19854);
    const v19856 = try o.lookup(&s, frame, "binding19838");
    const v19857 = try s.text("href");
    const v19858 = try s.own(try js.getKey(e, v19856, v19857));
    const v19859 = try o.construct(&s, v19847, &.{ v19855, v19858 });
    try o.assign(&s, frame, "binding19845", v19859);
    const v19860 = try s.global("URL");
    const v19861 = try o.lookup(&s, frame, "binding19839");
    const v19862 = try s.text("href");
    const v19863 = try s.own(try js.getKey(e, v19861, v19862));
    const v19864 = try o.lookup(&s, frame, "binding19838");
    const v19865 = try s.text("href");
    const v19866 = try s.own(try js.getKey(e, v19864, v19865));
    const v19867 = try o.construct(&s, v19860, &.{ v19863, v19866 });
    try o.assign(&s, frame, "binding19846", v19867);
    const v19868 = try o.importValue(&s, graph, "guard/index.mjs", "Guard");
    const v19869 = try s.text("IsEqual");
    const v19870 = try s.own(try js.getKey(e, v19868, v19869));
    const v19871 = try o.lookup(&s, frame, "binding19845");
    const v19872 = try s.text("href");
    const v19873 = try s.own(try js.getKey(e, v19871, v19872));
    const v19874 = try o.lookup(&s, frame, "binding19846");
    const v19875 = try s.text("href");
    const v19876 = try s.own(try js.getKey(e, v19874, v19875));
    const v19877 = try s.call(v19870, v19868, &.{ v19873, v19876 });
    const v19879 = conditional19878: {
        if (s.truthy(v19877)) {
            const v19880 = try o.lookup(&s, frame, "binding19837");
            break :conditional19878 v19880;
        } else {
            break :conditional19878 c.pi_js_undefined();
        }
    };
    return c.JS_DupValue(e.context, v19879);
}
fn body19882(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v19889 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding19883", v19889);
    const v19890 = if (args.len > 1) args[1] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding19884", v19890);
    const v19891 = if (args.len > 2) args[2] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding19885", v19891);
    const v19895 = try s.global("URL");
    const v19896 = try s.text("#");
    const v19897 = try o.lookup(&s, frame, "binding19883");
    const v19898 = try s.text("$dynamicAnchor");
    const v19899 = try s.own(try js.getKey(e, v19897, v19898));
    const v19900 = try s.stringify(v19899);
    const v19901 = try s.concat(v19896, v19900);
    const v19902 = try s.text("");
    const v19903 = try s.concat(v19901, v19902);
    const v19904 = try o.lookup(&s, frame, "binding19884");
    const v19905 = try s.text("href");
    const v19906 = try s.own(try js.getKey(e, v19904, v19905));
    const v19907 = try o.construct(&s, v19895, &.{ v19903, v19906 });
    try o.assign(&s, frame, "binding19892", v19907);
    const v19908 = try s.global("URL");
    const v19909 = try o.lookup(&s, frame, "binding19885");
    const v19910 = try s.text("href");
    const v19911 = try s.own(try js.getKey(e, v19909, v19910));
    const v19912 = try o.lookup(&s, frame, "binding19884");
    const v19913 = try s.text("href");
    const v19914 = try s.own(try js.getKey(e, v19912, v19913));
    const v19915 = try o.construct(&s, v19908, &.{ v19911, v19914 });
    try o.assign(&s, frame, "binding19893", v19915);
    const v19916 = try o.importValue(&s, graph, "guard/index.mjs", "Guard");
    const v19917 = try s.text("IsEqual");
    const v19918 = try s.own(try js.getKey(e, v19916, v19917));
    const v19919 = try o.lookup(&s, frame, "binding19892");
    const v19920 = try s.text("href");
    const v19921 = try s.own(try js.getKey(e, v19919, v19920));
    const v19922 = try o.lookup(&s, frame, "binding19893");
    const v19923 = try s.text("href");
    const v19924 = try s.own(try js.getKey(e, v19922, v19923));
    const v19925 = try s.call(v19918, v19916, &.{ v19921, v19924 });
    try o.assign(&s, frame, "binding19894", v19925);
    const v19926 = try o.lookup(&s, frame, "binding19894");
    const v19928 = conditional19927: {
        if (s.truthy(v19926)) {
            const v19929 = try o.lookup(&s, frame, "binding19883");
            break :conditional19927 v19929;
        } else {
            break :conditional19927 c.pi_js_undefined();
        }
    };
    return c.JS_DupValue(e.context, v19928);
}
fn body19931(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v19936 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding19932", v19936);
    const v19937 = if (args.len > 1) args[1] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding19933", v19937);
    const v19940 = try o.lookup(&s, frame, "binding19933");
    const v19941 = try s.text("href");
    const v19942 = try s.own(try js.getKey(e, v19940, v19941));
    const v19943 = try s.text("endsWith");
    const v19944 = try s.own(try js.getKey(e, v19942, v19943));
    const v19945 = try s.text("#");
    const v19946 = try s.call(v19944, v19942, &.{v19945});
    if (s.truthy(v19946)) {
        const v19947 = try o.lookup(&s, frame, "binding19932");
        return c.JS_DupValue(e.context, v19947);
    }
    const v19948 = try o.lookup(&s, frame, "binding19933");
    const v19949 = try s.text("hash");
    const v19950 = try s.own(try js.getKey(e, v19948, v19949));
    const v19951 = try s.text("startsWith");
    const v19952 = try s.own(try js.getKey(e, v19950, v19951));
    const v19953 = try s.text("#");
    const v19954 = try s.call(v19952, v19950, &.{v19953});
    if (s.truthy(o.boolean(&s, !s.truthy(v19954)))) {
        return c.JS_DupValue(e.context, c.pi_js_undefined());
    }
    const v19955 = try s.global("decodeURIComponent");
    const v19956 = try o.lookup(&s, frame, "binding19933");
    const v19957 = try s.text("hash");
    const v19958 = try s.own(try js.getKey(e, v19956, v19957));
    const v19959 = try s.text("slice");
    const v19960 = try s.own(try js.getKey(e, v19958, v19959));
    const v19961 = try s.call(v19960, v19958, &.{c.JS_NewFloat64(e.context, 1)});
    const v19962 = try s.call(v19955, c.pi_js_undefined(), &.{v19961});
    try o.assign(&s, frame, "binding19938", v19962);
    const v19963 = try o.lookup(&s, frame, "binding19938");
    const v19964 = try s.text("startsWith");
    const v19965 = try s.own(try js.getKey(e, v19963, v19964));
    const v19966 = try s.text("/");
    const v19967 = try s.call(v19965, v19963, &.{v19966});
    if (s.truthy(o.boolean(&s, !s.truthy(v19967)))) {
        return c.JS_DupValue(e.context, c.pi_js_undefined());
    }
    const v19968 = try o.importValue(&s, graph, "schema/pointer/index.mjs", "Pointer");
    const v19969 = try s.text("Get");
    const v19970 = try s.own(try js.getKey(e, v19968, v19969));
    const v19971 = try o.lookup(&s, frame, "binding19932");
    const v19972 = try o.lookup(&s, frame, "binding19938");
    const v19973 = try s.call(v19970, v19968, &.{ v19971, v19972 });
    try o.assign(&s, frame, "binding19939", v19973);
    const v19974 = try o.lookup(&s, frame, "binding19939");
    return c.JS_DupValue(e.context, v19974);
}
fn body19976(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v19980 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding19977", v19980);
    const v19981 = if (args.len > 1) args[1] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding19978", v19981);
    const v19982 = if (args.len > 2) args[2] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding19979", v19982);
    const v19983 = try o.importValue(&s, graph, "schema/types/index.mjs", "*");
    const v19984 = try s.text("IsId");
    const v19985 = try s.own(try js.getKey(e, v19983, v19984));
    const v19986 = try o.lookup(&s, frame, "binding19977");
    const v19987 = try s.call(v19985, v19983, &.{v19986});
    if (s.truthy(v19987)) {
        const v19989 = try o.lookup(&s, frame, "binding19610");
        const v19990 = try o.lookup(&s, frame, "binding19977");
        const v19991 = try o.lookup(&s, frame, "binding19978");
        const v19992 = try o.lookup(&s, frame, "binding19979");
        const v19993 = try s.call(v19989, c.pi_js_undefined(), &.{ v19990, v19991, v19992 });
        try o.assign(&s, frame, "binding19988", v19993);
        const v19994 = try o.importValue(&s, graph, "guard/index.mjs", "Guard");
        const v19995 = try s.text("IsUndefined");
        const v19996 = try s.own(try js.getKey(e, v19994, v19995));
        const v19997 = try o.lookup(&s, frame, "binding19988");
        const v19998 = try s.call(v19996, v19994, &.{v19997});
        if (s.truthy(o.boolean(&s, !s.truthy(v19998)))) {
            const v19999 = try o.lookup(&s, frame, "binding19988");
            return c.JS_DupValue(e.context, v19999);
        }
    }
    const v20000 = try o.importValue(&s, graph, "schema/types/index.mjs", "*");
    const v20001 = try s.text("IsAnchor");
    const v20002 = try s.own(try js.getKey(e, v20000, v20001));
    const v20003 = try o.lookup(&s, frame, "binding19977");
    const v20004 = try s.call(v20002, v20000, &.{v20003});
    if (s.truthy(v20004)) {
        const v20006 = try o.lookup(&s, frame, "binding19611");
        const v20007 = try o.lookup(&s, frame, "binding19977");
        const v20008 = try o.lookup(&s, frame, "binding19978");
        const v20009 = try o.lookup(&s, frame, "binding19979");
        const v20010 = try s.call(v20006, c.pi_js_undefined(), &.{ v20007, v20008, v20009 });
        try o.assign(&s, frame, "binding20005", v20010);
        const v20011 = try o.importValue(&s, graph, "guard/index.mjs", "Guard");
        const v20012 = try s.text("IsUndefined");
        const v20013 = try s.own(try js.getKey(e, v20011, v20012));
        const v20014 = try o.lookup(&s, frame, "binding20005");
        const v20015 = try s.call(v20013, v20011, &.{v20014});
        if (s.truthy(o.boolean(&s, !s.truthy(v20015)))) {
            const v20016 = try o.lookup(&s, frame, "binding20005");
            return c.JS_DupValue(e.context, v20016);
        }
    }
    const v20017 = try o.importValue(&s, graph, "schema/types/index.mjs", "*");
    const v20018 = try s.text("IsDynamicAnchor");
    const v20019 = try s.own(try js.getKey(e, v20017, v20018));
    const v20020 = try o.lookup(&s, frame, "binding19977");
    const v20021 = try s.call(v20019, v20017, &.{v20020});
    if (s.truthy(v20021)) {
        const v20023 = try o.lookup(&s, frame, "binding19612");
        const v20024 = try o.lookup(&s, frame, "binding19977");
        const v20025 = try o.lookup(&s, frame, "binding19978");
        const v20026 = try o.lookup(&s, frame, "binding19979");
        const v20027 = try s.call(v20023, c.pi_js_undefined(), &.{ v20024, v20025, v20026 });
        try o.assign(&s, frame, "binding20022", v20027);
        const v20028 = try o.importValue(&s, graph, "guard/index.mjs", "Guard");
        const v20029 = try s.text("IsUndefined");
        const v20030 = try s.own(try js.getKey(e, v20028, v20029));
        const v20031 = try o.lookup(&s, frame, "binding20022");
        const v20032 = try s.call(v20030, v20028, &.{v20031});
        if (s.truthy(o.boolean(&s, !s.truthy(v20032)))) {
            const v20033 = try o.lookup(&s, frame, "binding20022");
            return c.JS_DupValue(e.context, v20033);
        }
    }
    const v20034 = try o.lookup(&s, frame, "binding19613");
    const v20035 = try o.lookup(&s, frame, "binding19977");
    const v20036 = try o.lookup(&s, frame, "binding19979");
    const v20037 = try s.call(v20034, c.pi_js_undefined(), &.{ v20035, v20036 });
    return c.JS_DupValue(e.context, v20037);
}
fn body20049(e: *Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    _ = try o.lookup(&s, frame, "@this");
    const v20054 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding20051", v20054);
    const v20055 = if (args.len > 1) args[1] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding20052", v20055);
    const v20057 = try o.lookup(&s, frame, "binding19618");
    const v20058 = try o.lookup(&s, frame, "binding20052");
    const v20059 = try o.lookup(&s, frame, "binding20041");
    const v20060 = try o.lookup(&s, frame, "binding20042");
    const v20061 = try s.call(v20057, c.pi_js_undefined(), &.{ v20058, v20059, v20060 });
    try o.assign(&s, frame, "binding20056", v20061);
    const v20062 = try o.importValue(&s, graph, "guard/index.mjs", "Guard");
    const v20063 = try s.text("IsUndefined");
    const v20064 = try s.own(try js.getKey(e, v20062, v20063));
    const v20065 = try o.lookup(&s, frame, "binding20056");
    const v20066 = try s.call(v20064, v20062, &.{v20065});
    const v20068 = conditional20067: {
        if (s.truthy(o.boolean(&s, !s.truthy(v20066)))) {
            const v20069 = try o.lookup(&s, frame, "binding20056");
            break :conditional20067 v20069;
        } else {
            const v20070 = try o.lookup(&s, frame, "binding20051");
            break :conditional20067 v20070;
        }
    };
    return c.JS_DupValue(e.context, v20068);
}
fn body20049C(ctx: ?*c.JSContext, receiver: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const e = Engine.fromContext(ctx.?);
    return body20049(e, receiver, if (argc > 0) argv[0..@intCast(argc)] else &.{}, roots[0..2]) catch |err| sdk.fail(e, err);
}
fn body20039(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v20043 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding20040", v20043);
    const v20044 = if (args.len > 1) args[1] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding20041", v20044);
    const v20045 = if (args.len > 2) args[2] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding20042", v20045);
    const v20046 = try o.lookup(&s, frame, "binding20040");
    const v20047 = try s.text("reduce");
    const v20048 = try s.own(try js.getKey(e, v20046, v20047));
    const v20071 = try o.arrow(&s, "", 2, body20049C, &.{ graph, frame });
    const v20072 = try s.call(v20048, v20046, &.{ v20071, c.pi_js_undefined() });
    return c.JS_DupValue(e.context, v20072);
}
fn body20074(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v20076 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding20075", v20076);
    const v20077 = try o.importValue(&s, graph, "guard/index.mjs", "Guard");
    const v20078 = try s.text("IsEqual");
    const v20079 = try s.own(try js.getKey(e, v20077, v20078));
    const v20080 = try o.lookup(&s, frame, "binding20075");
    const v20081 = try s.text("const");
    const v20082 = try s.call(v20079, v20077, &.{ v20080, v20081 });
    const v20084 = logical20083: {
        if (s.truthy(v20082)) break :logical20083 v20082;
        const v20085 = try o.importValue(&s, graph, "guard/index.mjs", "Guard");
        const v20086 = try s.text("IsEqual");
        const v20087 = try s.own(try js.getKey(e, v20085, v20086));
        const v20088 = try o.lookup(&s, frame, "binding20075");
        const v20089 = try s.text("enum");
        const v20090 = try s.call(v20087, v20085, &.{ v20088, v20089 });
        break :logical20083 v20090;
    };
    return c.JS_DupValue(e.context, v20084);
}
fn body20106(e: *Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    _ = try o.lookup(&s, frame, "@this");
    const v20111 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding20108", v20111);
    const v20112 = if (args.len > 1) args[1] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding20109", v20112);
    const v20114 = try o.lookup(&s, frame, "binding19616");
    const v20115 = try o.lookup(&s, frame, "binding20109");
    const v20116 = try s.call(v20114, c.pi_js_undefined(), &.{v20115});
    if (s.truthy(v20116)) {
        const v20117 = try o.lookup(&s, frame, "binding20108");
        return c.JS_DupValue(e.context, v20117);
    }
    const v20118 = try o.lookup(&s, frame, "binding19618");
    const v20119 = try o.lookup(&s, frame, "binding20093");
    const v20120 = try o.lookup(&s, frame, "binding20109");
    const v20121 = try o.propertyKey(&s, v20120);
    const v20122 = try s.own(try js.getKey(e, v20119, v20121));
    const v20123 = try o.lookup(&s, frame, "binding20094");
    const v20124 = try o.lookup(&s, frame, "binding20095");
    const v20125 = try s.call(v20118, c.pi_js_undefined(), &.{ v20122, v20123, v20124 });
    try o.assign(&s, frame, "binding20113", v20125);
    const v20126 = try o.importValue(&s, graph, "guard/index.mjs", "Guard");
    const v20127 = try s.text("IsUndefined");
    const v20128 = try s.own(try js.getKey(e, v20126, v20127));
    const v20129 = try o.lookup(&s, frame, "binding20113");
    const v20130 = try s.call(v20128, v20126, &.{v20129});
    const v20132 = conditional20131: {
        if (s.truthy(o.boolean(&s, !s.truthy(v20130)))) {
            const v20133 = try o.lookup(&s, frame, "binding20113");
            break :conditional20131 v20133;
        } else {
            const v20134 = try o.lookup(&s, frame, "binding20108");
            break :conditional20131 v20134;
        }
    };
    return c.JS_DupValue(e.context, v20132);
}
fn body20106C(ctx: ?*c.JSContext, receiver: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const e = Engine.fromContext(ctx.?);
    return body20106(e, receiver, if (argc > 0) argv[0..@intCast(argc)] else &.{}, roots[0..2]) catch |err| sdk.fail(e, err);
}
fn body20092(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v20096 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding20093", v20096);
    const v20097 = if (args.len > 1) args[1] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding20094", v20097);
    const v20098 = if (args.len > 2) args[2] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding20095", v20098);
    const v20099 = try o.importValue(&s, graph, "guard/index.mjs", "Guard");
    const v20100 = try s.text("Keys");
    const v20101 = try s.own(try js.getKey(e, v20099, v20100));
    const v20102 = try o.lookup(&s, frame, "binding20093");
    const v20103 = try s.call(v20101, v20099, &.{v20102});
    const v20104 = try s.text("reduce");
    const v20105 = try s.own(try js.getKey(e, v20103, v20104));
    const v20135 = try o.arrow(&s, "", 2, body20106C, &.{ graph, frame });
    const v20136 = try s.call(v20105, v20103, &.{ v20135, c.pi_js_undefined() });
    return c.JS_DupValue(e.context, v20136);
}
fn body20138(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v20143 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding20139", v20143);
    const v20144 = if (args.len > 1) args[1] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding20140", v20144);
    const v20145 = if (args.len > 2) args[2] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding20141", v20145);
    const v20147 = try o.importValue(&s, graph, "schema/types/index.mjs", "*");
    const v20148 = try s.text("IsSchemaObject");
    const v20149 = try s.own(try js.getKey(e, v20147, v20148));
    const v20150 = try o.lookup(&s, frame, "binding20139");
    const v20151 = try s.call(v20149, v20147, &.{v20150});
    const v20153 = logical20152: {
        if (!s.truthy(v20151)) break :logical20152 v20151;
        const v20154 = try o.importValue(&s, graph, "schema/types/index.mjs", "*");
        const v20155 = try s.text("IsId");
        const v20156 = try s.own(try js.getKey(e, v20154, v20155));
        const v20157 = try o.lookup(&s, frame, "binding20139");
        const v20158 = try s.call(v20156, v20154, &.{v20157});
        break :logical20152 v20158;
    };
    const v20160 = conditional20159: {
        if (s.truthy(v20153)) {
            const v20161 = try s.global("URL");
            const v20162 = try o.lookup(&s, frame, "binding20139");
            const v20163 = try s.text("$id");
            const v20164 = try s.own(try js.getKey(e, v20162, v20163));
            const v20165 = try o.lookup(&s, frame, "binding20140");
            const v20166 = try s.text("href");
            const v20167 = try s.own(try js.getKey(e, v20165, v20166));
            const v20168 = try o.construct(&s, v20161, &.{ v20164, v20167 });
            break :conditional20159 v20168;
        } else {
            const v20169 = try o.lookup(&s, frame, "binding20140");
            break :conditional20159 v20169;
        }
    };
    try o.assign(&s, frame, "binding20146", v20160);
    const v20170 = try o.importValue(&s, graph, "schema/types/index.mjs", "*");
    const v20171 = try s.text("IsSchemaObject");
    const v20172 = try s.own(try js.getKey(e, v20170, v20171));
    const v20173 = try o.lookup(&s, frame, "binding20139");
    const v20174 = try s.call(v20172, v20170, &.{v20173});
    if (s.truthy(v20174)) {
        const v20176 = try o.lookup(&s, frame, "binding19614");
        const v20177 = try o.lookup(&s, frame, "binding20139");
        const v20178 = try o.lookup(&s, frame, "binding20146");
        const v20179 = try o.lookup(&s, frame, "binding20141");
        const v20180 = try s.call(v20176, c.pi_js_undefined(), &.{ v20177, v20178, v20179 });
        try o.assign(&s, frame, "binding20175", v20180);
        const v20181 = try o.importValue(&s, graph, "guard/index.mjs", "Guard");
        const v20182 = try s.text("IsUndefined");
        const v20183 = try s.own(try js.getKey(e, v20181, v20182));
        const v20184 = try o.lookup(&s, frame, "binding20175");
        const v20185 = try s.call(v20183, v20181, &.{v20184});
        if (s.truthy(o.boolean(&s, !s.truthy(v20185)))) {
            const v20186 = try o.lookup(&s, frame, "binding20175");
            return c.JS_DupValue(e.context, v20186);
        }
    }
    const v20187 = try o.importValue(&s, graph, "guard/index.mjs", "Guard");
    const v20188 = try s.text("IsArray");
    const v20189 = try s.own(try js.getKey(e, v20187, v20188));
    const v20190 = try o.lookup(&s, frame, "binding20139");
    const v20191 = try s.call(v20189, v20187, &.{v20190});
    if (s.truthy(v20191)) {
        const v20192 = try o.lookup(&s, frame, "binding19615");
        const v20193 = try o.lookup(&s, frame, "binding20139");
        const v20194 = try o.lookup(&s, frame, "binding20146");
        const v20195 = try o.lookup(&s, frame, "binding20141");
        const v20196 = try s.call(v20192, c.pi_js_undefined(), &.{ v20193, v20194, v20195 });
        return c.JS_DupValue(e.context, v20196);
    }
    const v20197 = try o.importValue(&s, graph, "guard/index.mjs", "Guard");
    const v20198 = try s.text("IsObject");
    const v20199 = try s.own(try js.getKey(e, v20197, v20198));
    const v20200 = try o.lookup(&s, frame, "binding20139");
    const v20201 = try s.call(v20199, v20197, &.{v20200});
    if (s.truthy(v20201)) {
        const v20202 = try o.lookup(&s, frame, "binding19617");
        const v20203 = try o.lookup(&s, frame, "binding20139");
        const v20204 = try o.lookup(&s, frame, "binding20146");
        const v20205 = try o.lookup(&s, frame, "binding20141");
        const v20206 = try s.call(v20202, c.pi_js_undefined(), &.{ v20203, v20204, v20205 });
        return c.JS_DupValue(e.context, v20206);
    }
    return c.JS_DupValue(e.context, c.pi_js_undefined());
}
fn body20208(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    _ = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v20212 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding20209", v20212);
    const v20213 = if (args.len > 1) args[1] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding20210", v20213);
    const v20214 = if (args.len > 2) args[2] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding20211", v20214);
    const v20215 = try o.lookup(&s, frame, "binding19609");
    const v20216 = try o.lookup(&s, frame, "binding20209");
    const v20217 = try s.global("URL");
    const v20218 = try o.lookup(&s, frame, "binding20210");
    const v20220 = logical20219: {
        if (s.truthy(v20218)) break :logical20219 v20218;
        const v20221 = try s.text(".");
        break :logical20219 v20221;
    };
    const v20222 = try o.lookup(&s, frame, "binding19607");
    const v20223 = try o.construct(&s, v20217, &.{ v20220, v20222 });
    const v20224 = try o.lookup(&s, frame, "binding20211");
    const v20225 = try s.call(v20215, c.pi_js_undefined(), &.{ v20216, v20223, v20224 });
    return c.JS_DupValue(e.context, v20225);
}
fn body20227(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v20233 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding20228", v20233);
    const v20234 = if (args.len > 1) args[1] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding20229", v20234);
    const v20235 = if (args.len > 2) args[2] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding20230", v20235);
    const v20236 = if (args.len > 3) args[3] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding20231", v20236);
    const v20238 = try o.lookup(&s, frame, "binding19629");
    const v20239 = try o.lookup(&s, frame, "binding20228");
    const v20240 = try o.lookup(&s, frame, "binding20229");
    const v20241 = try o.lookup(&s, frame, "binding20230");
    const v20242 = try o.lookup(&s, frame, "binding20231");
    const v20243 = try s.call(v20238, c.pi_js_undefined(), &.{ v20239, v20240, v20241, v20242, o.boolean(&s, false) });
    try o.assign(&s, frame, "binding20237", v20243);
    const v20244 = try o.importValue(&s, graph, "schema/types/index.mjs", "*");
    const v20245 = try s.text("IsSchemaObject");
    const v20246 = try s.own(try js.getKey(e, v20244, v20245));
    const v20247 = try o.lookup(&s, frame, "binding20237");
    const v20248 = try s.call(v20246, v20244, &.{v20247});
    const v20250 = logical20249: {
        if (!s.truthy(v20248)) break :logical20249 v20248;
        const v20251 = try o.importValue(&s, graph, "schema/types/index.mjs", "*");
        const v20252 = try s.text("IsId");
        const v20253 = try s.own(try js.getKey(e, v20251, v20252));
        const v20254 = try o.lookup(&s, frame, "binding20237");
        const v20255 = try s.call(v20253, v20251, &.{v20254});
        break :logical20249 v20255;
    };
    const v20257 = conditional20256: {
        if (s.truthy(v20250)) {
            const v20258 = try o.lookup(&s, frame, "binding20237");
            break :conditional20256 v20258;
        } else {
            break :conditional20256 c.pi_js_undefined();
        }
    };
    return c.JS_DupValue(e.context, v20257);
}
fn body20260(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    _ = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v20262 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding20261", v20262);
    const v20263 = try o.lookup(&s, frame, "binding20261");
    const v20264 = try s.text("href");
    const v20265 = try s.own(try js.getKey(e, v20263, v20264));
    const v20266 = try s.text("split");
    const v20267 = try s.own(try js.getKey(e, v20265, v20266));
    const v20268 = try s.text("#");
    const v20269 = try s.call(v20267, v20265, &.{v20268});
    const v20270 = try o.propertyKey(&s, c.JS_NewFloat64(e.context, 0));
    const v20271 = try s.own(try js.getKey(e, v20269, v20270));
    return c.JS_DupValue(e.context, v20271);
}
fn body20273(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v20276 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding20274", v20276);
    const v20277 = if (args.len > 1) args[1] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding20275", v20277);
    const v20278 = try o.importValue(&s, graph, "guard/index.mjs", "Guard");
    const v20279 = try s.text("HasPropertyKey");
    const v20280 = try s.own(try js.getKey(e, v20278, v20279));
    const v20281 = try o.lookup(&s, frame, "binding20274");
    const v20282 = try o.lookup(&s, frame, "binding20275");
    const v20283 = try s.call(v20280, v20278, &.{ v20281, v20282 });
    const v20285 = conditional20284: {
        if (s.truthy(v20283)) {
            const v20286 = try o.lookup(&s, frame, "binding20274");
            const v20287 = try o.lookup(&s, frame, "binding20275");
            const v20288 = try o.propertyKey(&s, v20287);
            const v20289 = try s.own(try js.getKey(e, v20286, v20288));
            break :conditional20284 v20289;
        } else {
            break :conditional20284 c.pi_js_undefined();
        }
    };
    return c.JS_DupValue(e.context, v20285);
}
fn body20291(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    _ = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v20295 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding20292", v20295);
    const v20296 = if (args.len > 1) args[1] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding20293", v20296);
    const v20297 = if (args.len > 2) args[2] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding20294", v20297);
    const v20298 = try o.lookup(&s, frame, "binding19618");
    const v20299 = try o.lookup(&s, frame, "binding20292");
    const v20300 = try o.lookup(&s, frame, "binding20293");
    const v20301 = try o.lookup(&s, frame, "binding20294");
    const v20302 = try s.call(v20298, c.pi_js_undefined(), &.{ v20299, v20300, v20301 });
    return c.JS_DupValue(e.context, v20302);
}
fn body20304(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v20312 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding20305", v20312);
    const v20313 = if (args.len > 1) args[1] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding20306", v20313);
    const v20314 = if (args.len > 2) args[2] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding20307", v20314);
    const v20319 = try o.lookup(&s, frame, "binding19621");
    const v20320 = try o.lookup(&s, frame, "binding20307");
    const v20321 = try s.call(v20319, c.pi_js_undefined(), &.{v20320});
    try o.assign(&s, frame, "binding20315", v20321);
    const v20322 = try o.importValue(&s, graph, "guard/index.mjs", "Guard");
    const v20323 = try s.text("IsEqual");
    const v20324 = try s.own(try js.getKey(e, v20322, v20323));
    const v20325 = try o.lookup(&s, frame, "binding20315");
    const v20326 = try o.lookup(&s, frame, "binding19621");
    const v20327 = try o.lookup(&s, frame, "binding20306");
    const v20328 = try s.call(v20326, c.pi_js_undefined(), &.{v20327});
    const v20329 = try s.call(v20324, v20322, &.{ v20325, v20328 });
    if (s.truthy(v20329)) {
        return c.JS_DupValue(e.context, c.pi_js_undefined());
    }
    const v20330 = try o.importValue(&s, graph, "guard/index.mjs", "Guard");
    const v20331 = try s.text("HasPropertyKey");
    const v20332 = try s.own(try js.getKey(e, v20330, v20331));
    const v20333 = try o.lookup(&s, frame, "binding20305");
    const v20334 = try o.lookup(&s, frame, "binding20315");
    const v20335 = try s.call(v20332, v20330, &.{ v20333, v20334 });
    if (s.truthy(o.boolean(&s, !s.truthy(v20335)))) {
        return c.JS_DupValue(e.context, c.pi_js_undefined());
    }
    const v20336 = try o.lookup(&s, frame, "binding20305");
    const v20337 = try o.lookup(&s, frame, "binding20315");
    const v20338 = try o.propertyKey(&s, v20337);
    const v20339 = try s.own(try js.getKey(e, v20336, v20338));
    try o.assign(&s, frame, "binding20316", v20339);
    const v20340 = try o.importValue(&s, graph, "schema/types/index.mjs", "*");
    const v20341 = try s.text("IsSchemaObject");
    const v20342 = try s.own(try js.getKey(e, v20340, v20341));
    const v20343 = try o.lookup(&s, frame, "binding20316");
    const v20344 = try s.call(v20342, v20340, &.{v20343});
    const v20346 = logical20345: {
        if (!s.truthy(v20344)) break :logical20345 v20344;
        const v20347 = try o.importValue(&s, graph, "schema/types/index.mjs", "*");
        const v20348 = try s.text("IsId");
        const v20349 = try s.own(try js.getKey(e, v20347, v20348));
        const v20350 = try o.lookup(&s, frame, "binding20316");
        const v20351 = try s.call(v20349, v20347, &.{v20350});
        break :logical20345 v20351;
    };
    const v20353 = conditional20352: {
        if (s.truthy(v20346)) {
            const v20354 = try s.global("URL");
            const v20355 = try o.lookup(&s, frame, "binding20316");
            const v20356 = try s.text("$id");
            const v20357 = try s.own(try js.getKey(e, v20355, v20356));
            const v20358 = try o.lookup(&s, frame, "binding20315");
            const v20359 = try o.construct(&s, v20354, &.{ v20357, v20358 });
            break :conditional20352 v20359;
        } else {
            const v20360 = try s.global("URL");
            const v20361 = try o.lookup(&s, frame, "binding20315");
            const v20362 = try o.construct(&s, v20360, &.{v20361});
            break :conditional20352 v20362;
        }
    };
    try o.assign(&s, frame, "binding20317", v20353);
    const v20363 = try o.importValue(&s, graph, "guard/index.mjs", "Guard");
    const v20364 = try s.text("IsEqual");
    const v20365 = try s.own(try js.getKey(e, v20363, v20364));
    const v20366 = try o.lookup(&s, frame, "binding20307");
    const v20367 = try s.text("hash");
    const v20368 = try s.own(try js.getKey(e, v20366, v20367));
    const v20369 = try s.text("");
    const v20370 = try s.call(v20365, v20363, &.{ v20368, v20369 });
    const v20372 = conditional20371: {
        if (s.truthy(v20370)) {
            const v20373 = try o.lookup(&s, frame, "binding20316");
            break :conditional20371 v20373;
        } else {
            const v20374 = try o.lookup(&s, frame, "binding19618");
            const v20375 = try o.lookup(&s, frame, "binding20316");
            const v20376 = try o.lookup(&s, frame, "binding20317");
            const v20377 = try o.lookup(&s, frame, "binding20307");
            const v20378 = try s.call(v20374, c.pi_js_undefined(), &.{ v20375, v20376, v20377 });
            break :conditional20371 v20378;
        }
    };
    try o.assign(&s, frame, "binding20318", v20372);
    const v20379 = try o.lookup(&s, frame, "binding20318");
    return c.JS_DupValue(e.context, v20379);
}
fn body20381(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v20388 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding20382", v20388);
    const v20389 = if (args.len > 1) args[1] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding20383", v20389);
    const v20390 = if (args.len > 2) args[2] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding20384", v20390);
    const v20391 = if (args.len > 3) args[3] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding20385", v20391);
    const v20392 = if (args.len > 4) args[4] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding20386", v20392);
    const v20394 = try o.lookup(&s, frame, "binding20385");
    const v20395 = try s.text("$ref");
    const v20396 = try s.own(try js.getKey(e, v20394, v20395));
    const v20397 = try s.text("startsWith");
    const v20398 = try s.own(try js.getKey(e, v20396, v20397));
    const v20399 = try s.text("#");
    const v20400 = try s.call(v20398, v20396, &.{v20399});
    if (s.truthy(o.boolean(&s, !s.truthy(v20400)))) {
        return c.JS_DupValue(e.context, c.pi_js_undefined());
    }
    const v20401 = try o.importValue(&s, graph, "guard/index.mjs", "Guard");
    const v20402 = try s.text("HasPropertyKey");
    const v20403 = try s.own(try js.getKey(e, v20401, v20402));
    const v20404 = try o.lookup(&s, frame, "binding20382");
    const v20405 = try s.text("$schema");
    const v20406 = try s.call(v20403, v20401, &.{ v20404, v20405 });
    if (s.truthy(v20406)) {
        return c.JS_DupValue(e.context, c.pi_js_undefined());
    }
    const v20407 = try o.lookup(&s, frame, "binding19619");
    const v20408 = try o.lookup(&s, frame, "binding20383");
    const v20409 = try o.lookup(&s, frame, "binding20384");
    const v20410 = try o.lookup(&s, frame, "binding20386");
    const v20411 = try s.call(v20407, c.pi_js_undefined(), &.{ v20408, v20409, v20410 });
    try o.assign(&s, frame, "binding20393", v20411);
    const v20412 = try o.importValue(&s, graph, "guard/index.mjs", "Guard");
    const v20413 = try s.text("IsUndefined");
    const v20414 = try s.own(try js.getKey(e, v20412, v20413));
    const v20415 = try o.lookup(&s, frame, "binding20393");
    const v20416 = try s.call(v20414, v20412, &.{v20415});
    const v20418 = logical20417: {
        if (s.truthy(v20416)) break :logical20417 v20416;
        const v20419 = try o.importValue(&s, graph, "guard/index.mjs", "Guard");
        const v20420 = try s.text("IsEqual");
        const v20421 = try s.own(try js.getKey(e, v20419, v20420));
        const v20422 = try o.lookup(&s, frame, "binding20393");
        const v20423 = try o.lookup(&s, frame, "binding20384");
        const v20424 = try s.call(v20421, v20419, &.{ v20422, v20423 });
        break :logical20417 v20424;
    };
    if (s.truthy(v20418)) {
        return c.JS_DupValue(e.context, c.pi_js_undefined());
    }
    const v20425 = try s.object();
    const v20426 = try s.text("target");
    const v20427 = try o.lookup(&s, frame, "binding20386");
    try o.defineKey(&s, v20425, v20426, v20427);
    const v20428 = try s.text("base");
    const v20429 = try o.lookup(&s, frame, "binding20393");
    try o.defineKey(&s, v20425, v20428, v20429);
    const v20430 = try s.text("root");
    const v20431 = try o.lookup(&s, frame, "binding20383");
    try o.defineKey(&s, v20425, v20430, v20431);
    return c.JS_DupValue(e.context, v20425);
}
fn body20433(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v20438 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding20434", v20438);
    const v20439 = if (args.len > 1) args[1] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding20435", v20439);
    const v20440 = if (args.len > 2) args[2] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding20436", v20440);
    const v20442 = try o.lookup(&s, frame, "binding20434");
    const v20443 = try o.lookup(&s, frame, "binding20435");
    const v20444 = try o.propertyKey(&s, v20443);
    const v20445 = try s.own(try js.getKey(e, v20442, v20444));
    try o.assign(&s, frame, "binding20441", v20445);
    const v20446 = try o.importValue(&s, graph, "schema/types/index.mjs", "*");
    const v20447 = try s.text("IsSchemaObject");
    const v20448 = try s.own(try js.getKey(e, v20446, v20447));
    const v20449 = try o.lookup(&s, frame, "binding20441");
    const v20450 = try s.call(v20448, v20446, &.{v20449});
    if (s.truthy(o.boolean(&s, !s.truthy(v20450)))) {
        return c.JS_DupValue(e.context, c.pi_js_undefined());
    }
    const v20451 = try s.object();
    const v20452 = try s.text("target");
    const v20453 = try o.lookup(&s, frame, "binding20436");
    try o.defineKey(&s, v20451, v20452, v20453);
    const v20454 = try s.text("base");
    const v20455 = try o.lookup(&s, frame, "binding20435");
    try o.defineKey(&s, v20451, v20454, v20455);
    const v20456 = try s.text("root");
    const v20457 = try o.lookup(&s, frame, "binding20441");
    try o.defineKey(&s, v20451, v20456, v20457);
    return c.JS_DupValue(e.context, v20451);
}
fn body20459(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v20466 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding20460", v20466);
    const v20467 = if (args.len > 1) args[1] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding20461", v20467);
    const v20468 = if (args.len > 2) args[2] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding20462", v20468);
    const v20469 = if (args.len > 3) args[3] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding20463", v20469);
    const v20470 = if (args.len > 4) args[4] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding20464", v20470);
    const v20472 = try o.lookup(&s, frame, "binding20464");
    const v20474 = conditional20473: {
        if (s.truthy(v20472)) {
            const v20475 = try o.lookup(&s, frame, "binding19626");
            const v20476 = try o.lookup(&s, frame, "binding20460");
            const v20477 = try s.text("context");
            const v20478 = try s.own(try js.getKey(e, v20476, v20477));
            const v20479 = try o.lookup(&s, frame, "binding20463");
            const v20480 = try o.lookup(&s, frame, "binding20462");
            const v20481 = try s.call(v20475, c.pi_js_undefined(), &.{ v20478, v20479, v20480 });
            break :conditional20473 v20481;
        } else {
            break :conditional20473 c.pi_js_undefined();
        }
    };
    try o.assign(&s, frame, "binding20471", v20474);
    const v20482 = try o.importValue(&s, graph, "guard/index.mjs", "Guard");
    const v20483 = try s.text("IsUndefined");
    const v20484 = try s.own(try js.getKey(e, v20482, v20483));
    const v20485 = try o.lookup(&s, frame, "binding20471");
    const v20486 = try s.call(v20484, v20482, &.{v20485});
    if (s.truthy(o.boolean(&s, !s.truthy(v20486)))) {
        const v20487 = try o.lookup(&s, frame, "binding20471");
        return c.JS_DupValue(e.context, v20487);
    }
    const v20488 = try o.lookup(&s, frame, "binding19625");
    const v20489 = try o.lookup(&s, frame, "binding20460");
    const v20490 = try s.text("root");
    const v20491 = try s.own(try js.getKey(e, v20489, v20490));
    const v20492 = try o.lookup(&s, frame, "binding20460");
    const v20493 = try s.text("lexicalSchema");
    const v20494 = try s.own(try js.getKey(e, v20492, v20493));
    const v20495 = try o.lookup(&s, frame, "binding20460");
    const v20496 = try s.text("referenceBase");
    const v20497 = try s.own(try js.getKey(e, v20495, v20496));
    const v20498 = try o.lookup(&s, frame, "binding20461");
    const v20499 = try o.lookup(&s, frame, "binding20462");
    const v20500 = try s.call(v20488, c.pi_js_undefined(), &.{ v20491, v20494, v20497, v20498, v20499 });
    return c.JS_DupValue(e.context, v20500);
}
fn body20502(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v20510 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding20503", v20510);
    const v20511 = if (args.len > 1) args[1] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding20504", v20511);
    const v20512 = if (args.len > 2) args[2] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding20505", v20512);
    const v20513 = if (args.len > 3) args[3] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding20506", v20513);
    const v20514 = if (args.len > 4) args[4] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding20507", v20514);
    const v20515 = if (args.len > 5) args[5] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding20508", v20515);
    const v20517 = try o.importValue(&s, graph, "schema/types/index.mjs", "*");
    const v20518 = try s.text("IsId");
    const v20519 = try s.own(try js.getKey(e, v20517, v20518));
    const v20520 = try o.lookup(&s, frame, "binding20507");
    const v20521 = try s.call(v20519, v20517, &.{v20520});
    if (s.truthy(v20521)) {
        return c.JS_DupValue(e.context, c.pi_js_undefined());
    }
    const v20522 = try o.lookup(&s, frame, "binding19620");
    const v20523 = try o.lookup(&s, frame, "binding20503");
    const v20524 = try o.lookup(&s, frame, "binding20504");
    const v20525 = try o.lookup(&s, frame, "binding20505");
    const v20526 = try o.lookup(&s, frame, "binding20506");
    const v20527 = try s.call(v20522, c.pi_js_undefined(), &.{ v20523, v20524, v20525, v20526 });
    try o.assign(&s, frame, "binding20516", v20527);
    const v20528 = try o.lookup(&s, frame, "binding20516");
    const v20530 = logical20529: {
        if (s.truthy(o.boolean(&s, !s.truthy(v20528)))) break :logical20529 o.boolean(&s, !s.truthy(v20528));
        const v20531 = try o.lookup(&s, frame, "binding20508");
        const v20532 = try s.text("includes");
        const v20533 = try s.own(try js.getKey(e, v20531, v20532));
        const v20534 = try o.lookup(&s, frame, "binding20516");
        const v20535 = try s.call(v20533, v20531, &.{v20534});
        break :logical20529 v20535;
    };
    if (s.truthy(v20530)) {
        return c.JS_DupValue(e.context, c.pi_js_undefined());
    }
    const v20536 = try s.object();
    const v20537 = try s.text("target");
    const v20538 = try o.lookup(&s, frame, "binding20507");
    try o.defineKey(&s, v20536, v20537, v20538);
    const v20539 = try s.text("resource");
    const v20540 = try o.lookup(&s, frame, "binding20516");
    try o.defineKey(&s, v20536, v20539, v20540);
    return c.JS_DupValue(e.context, v20536);
}
fn body20542(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v20551 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding20543", v20551);
    const v20552 = if (args.len > 1) args[1] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding20544", v20552);
    const v20553 = if (args.len > 2) args[2] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding20545", v20553);
    const v20554 = if (args.len > 3) args[3] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding20546", v20554);
    const v20555 = if (args.len > 4) args[4] else c.pi_js_undefined();
    const v20556 = default_value: {
        if (!c.JS_IsUndefined(v20555)) break :default_value v20555;
        break :default_value o.boolean(&s, true);
    };
    try o.assign(&s, frame, "binding20547", v20556);
    const v20560 = try s.global("URL");
    const v20561 = try o.lookup(&s, frame, "binding20545");
    const v20563 = logical20562: {
        if (s.truthy(v20561)) break :logical20562 v20561;
        const v20564 = try s.text(".");
        break :logical20562 v20564;
    };
    const v20565 = try o.lookup(&s, frame, "binding19607");
    const v20566 = try o.construct(&s, v20560, &.{ v20563, v20565 });
    try o.assign(&s, frame, "binding20557", v20566);
    const v20567 = try o.lookup(&s, frame, "binding20547");
    const v20569 = logical20568: {
        if (!s.truthy(v20567)) break :logical20568 v20567;
        const v20570 = try o.importValue(&s, graph, "schema/types/index.mjs", "*");
        const v20571 = try s.text("IsId");
        const v20572 = try s.own(try js.getKey(e, v20570, v20571));
        const v20573 = try o.lookup(&s, frame, "binding20544");
        const v20574 = try s.call(v20572, v20570, &.{v20573});
        break :logical20568 v20574;
    };
    const v20576 = conditional20575: {
        if (s.truthy(v20569)) {
            const v20577 = try s.global("URL");
            const v20578 = try o.lookup(&s, frame, "binding20544");
            const v20579 = try s.text("$id");
            const v20580 = try s.own(try js.getKey(e, v20578, v20579));
            const v20581 = try o.lookup(&s, frame, "binding20557");
            const v20582 = try o.construct(&s, v20577, &.{ v20580, v20581 });
            break :conditional20575 v20582;
        } else {
            const v20583 = try o.lookup(&s, frame, "binding20557");
            break :conditional20575 v20583;
        }
    };
    try o.assign(&s, frame, "binding20558", v20576);
    const v20584 = try s.global("URL");
    const v20585 = try o.lookup(&s, frame, "binding20546");
    const v20586 = try o.lookup(&s, frame, "binding20558");
    const v20587 = try s.text("href");
    const v20588 = try s.own(try js.getKey(e, v20586, v20587));
    const v20589 = try o.construct(&s, v20584, &.{ v20585, v20588 });
    try o.assign(&s, frame, "binding20559", v20589);
    const v20590 = try o.lookup(&s, frame, "binding19622");
    const v20591 = try o.lookup(&s, frame, "binding20543");
    const v20592 = try o.lookup(&s, frame, "binding20546");
    const v20593 = try s.call(v20590, c.pi_js_undefined(), &.{ v20591, v20592 });
    const v20595 = logical20594: {
        if (!c.JS_IsNull(v20593) and !c.JS_IsUndefined(v20593)) break :logical20594 v20593;
        const v20596 = try o.lookup(&s, frame, "binding19623");
        const v20597 = try o.lookup(&s, frame, "binding20544");
        const v20598 = try o.lookup(&s, frame, "binding20558");
        const v20599 = try o.lookup(&s, frame, "binding20559");
        const v20600 = try s.call(v20596, c.pi_js_undefined(), &.{ v20597, v20598, v20599 });
        break :logical20594 v20600;
    };
    const v20602 = logical20601: {
        if (!c.JS_IsNull(v20595) and !c.JS_IsUndefined(v20595)) break :logical20601 v20595;
        const v20603 = try o.lookup(&s, frame, "binding19624");
        const v20604 = try o.lookup(&s, frame, "binding20543");
        const v20605 = try o.lookup(&s, frame, "binding20558");
        const v20606 = try o.lookup(&s, frame, "binding20559");
        const v20607 = try s.call(v20603, c.pi_js_undefined(), &.{ v20604, v20605, v20606 });
        break :logical20601 v20607;
    };
    return c.JS_DupValue(e.context, v20602);
}
fn body20695(e: *Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    _ = try o.lookup(&s, frame, "@this");
    const v20698 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding20697", v20698);
    const v20699 = try o.importValue(&s, graph, "guard/index.mjs", "Guard");
    const v20700 = try s.text("IsEqual");
    const v20701 = try s.own(try js.getKey(e, v20699, v20700));
    const v20702 = try o.lookup(&s, frame, "binding20697");
    const v20703 = try s.text("$dynamicAnchor");
    const v20704 = try s.own(try js.getKey(e, v20702, v20703));
    const v20705 = try o.lookup(&s, frame, "binding20684");
    const v20706 = try s.call(v20701, v20699, &.{ v20704, v20705 });
    return c.JS_DupValue(e.context, v20706);
}
fn body20695C(ctx: ?*c.JSContext, receiver: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const e = Engine.fromContext(ctx.?);
    return body20695(e, receiver, if (argc > 0) argv[0..@intCast(argc)] else &.{}, roots[0..2]) catch |err| sdk.fail(e, err);
}
fn body20746(e: *Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    _ = try o.lookup(&s, frame, "@this");
    const v20749 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding20748", v20749);
    const v20750 = try o.importValue(&s, graph, "guard/index.mjs", "Guard");
    const v20751 = try s.text("IsEqual");
    const v20752 = try s.own(try js.getKey(e, v20750, v20751));
    const v20753 = try o.lookup(&s, frame, "binding20748");
    const v20754 = try s.text("$dynamicAnchor");
    const v20755 = try s.own(try js.getKey(e, v20753, v20754));
    const v20756 = try o.lookup(&s, frame, "binding20629");
    const v20757 = try s.text("$dynamicAnchor");
    const v20758 = try s.own(try js.getKey(e, v20756, v20757));
    const v20759 = try s.call(v20752, v20750, &.{ v20755, v20758 });
    return c.JS_DupValue(e.context, v20759);
}
fn body20746C(ctx: ?*c.JSContext, receiver: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const e = Engine.fromContext(ctx.?);
    return body20746(e, receiver, if (argc > 0) argv[0..@intCast(argc)] else &.{}, roots[0..2]) catch |err| sdk.fail(e, err);
}
fn body20609(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v20621 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding20610", v20621);
    const v20622 = if (args.len > 1) args[1] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding20611", v20622);
    const v20623 = if (args.len > 2) args[2] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding20612", v20623);
    const v20624 = if (args.len > 3) args[3] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding20613", v20624);
    const v20625 = if (args.len > 4) args[4] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding20614", v20625);
    const v20626 = if (args.len > 5) args[5] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding20615", v20626);
    const v20632 = try s.global("URL");
    const v20633 = try o.lookup(&s, frame, "binding20612");
    const v20635 = logical20634: {
        if (s.truthy(v20633)) break :logical20634 v20633;
        const v20636 = try s.text(".");
        break :logical20634 v20636;
    };
    const v20637 = try o.lookup(&s, frame, "binding19607");
    const v20638 = try o.construct(&s, v20632, &.{ v20635, v20637 });
    try o.assign(&s, frame, "binding20627", v20638);
    const v20639 = try o.lookup(&s, frame, "binding20614");
    const v20640 = try s.text("$dynamicRef");
    const v20641 = try s.own(try js.getKey(e, v20639, v20640));
    const v20642 = try s.text("startsWith");
    const v20643 = try s.own(try js.getKey(e, v20641, v20642));
    const v20644 = try s.text("#");
    const v20645 = try s.call(v20643, v20641, &.{v20644});
    const v20647 = conditional20646: {
        if (s.truthy(v20645)) {
            const v20648 = try o.lookup(&s, frame, "binding20613");
            break :conditional20646 v20648;
        } else {
            const v20649 = try o.lookup(&s, frame, "binding20611");
            break :conditional20646 v20649;
        }
    };
    try o.assign(&s, frame, "binding20628", v20647);
    const v20650 = try o.lookup(&s, frame, "binding19629");
    const v20651 = try o.lookup(&s, frame, "binding20610");
    const v20652 = try o.lookup(&s, frame, "binding20628");
    const v20653 = try o.lookup(&s, frame, "binding20612");
    const v20654 = try o.lookup(&s, frame, "binding20614");
    const v20655 = try s.text("$dynamicRef");
    const v20656 = try s.own(try js.getKey(e, v20654, v20655));
    const v20657 = try s.call(v20650, c.pi_js_undefined(), &.{ v20651, v20652, v20653, v20656, o.boolean(&s, false) });
    try o.assign(&s, frame, "binding20629", v20657);
    const v20658 = try o.importValue(&s, graph, "guard/index.mjs", "Guard");
    const v20659 = try s.text("IsUndefined");
    const v20660 = try s.own(try js.getKey(e, v20658, v20659));
    const v20661 = try o.lookup(&s, frame, "binding20629");
    const v20662 = try s.call(v20660, v20658, &.{v20661});
    if (s.truthy(v20662)) {
        const v20664 = try s.global("URL");
        const v20665 = try o.lookup(&s, frame, "binding20614");
        const v20666 = try s.text("$dynamicRef");
        const v20667 = try s.own(try js.getKey(e, v20665, v20666));
        const v20668 = try o.lookup(&s, frame, "binding20627");
        const v20669 = try o.construct(&s, v20664, &.{ v20667, v20668 });
        const v20670 = try s.text("hash");
        const v20671 = try s.own(try js.getKey(e, v20669, v20670));
        try o.assign(&s, frame, "binding20663", v20671);
        const v20672 = try o.lookup(&s, frame, "binding20663");
        const v20673 = try s.text("startsWith");
        const v20674 = try s.own(try js.getKey(e, v20672, v20673));
        const v20675 = try s.text("#/");
        const v20676 = try s.call(v20674, v20672, &.{v20675});
        const v20678 = logical20677: {
            if (!s.truthy(o.boolean(&s, !s.truthy(v20676)))) break :logical20677 o.boolean(&s, !s.truthy(v20676));
            const v20679 = try o.lookup(&s, frame, "binding20663");
            const v20680 = try s.text("startsWith");
            const v20681 = try s.own(try js.getKey(e, v20679, v20680));
            const v20682 = try s.text("#");
            const v20683 = try s.call(v20681, v20679, &.{v20682});
            break :logical20677 v20683;
        };
        if (s.truthy(v20678)) {
            const v20686 = try s.global("decodeURIComponent");
            const v20687 = try o.lookup(&s, frame, "binding20663");
            const v20688 = try s.text("slice");
            const v20689 = try s.own(try js.getKey(e, v20687, v20688));
            const v20690 = try s.call(v20689, v20687, &.{c.JS_NewFloat64(e.context, 1)});
            const v20691 = try s.call(v20686, c.pi_js_undefined(), &.{v20690});
            try o.assign(&s, frame, "binding20684", v20691);
            const v20692 = try o.lookup(&s, frame, "binding20615");
            const v20693 = try s.text("find");
            const v20694 = try s.own(try js.getKey(e, v20692, v20693));
            const v20707 = try o.arrow(&s, "", 1, body20695C, &.{ graph, frame });
            const v20708 = try s.call(v20694, v20692, &.{v20707});
            const v20710 = logical20709: {
                if (!c.JS_IsNull(v20708) and !c.JS_IsUndefined(v20708)) break :logical20709 v20708;
                const v20711 = try o.lookup(&s, frame, "binding19608");
                const v20712 = try o.lookup(&s, frame, "binding20611");
                const v20713 = try o.lookup(&s, frame, "binding20684");
                const v20714 = try s.call(v20711, c.pi_js_undefined(), &.{ v20712, v20713 });
                break :logical20709 v20714;
            };
            try o.assign(&s, frame, "binding20685", v20710);
            const v20715 = try o.lookup(&s, frame, "binding20685");
            return c.JS_DupValue(e.context, v20715);
        }
        return c.JS_DupValue(e.context, c.pi_js_undefined());
    }
    const v20716 = try o.importValue(&s, graph, "schema/types/index.mjs", "*");
    const v20717 = try s.text("IsSchemaObject");
    const v20718 = try s.own(try js.getKey(e, v20716, v20717));
    const v20719 = try o.lookup(&s, frame, "binding20629");
    const v20720 = try s.call(v20718, v20716, &.{v20719});
    const v20722 = logical20721: {
        if (s.truthy(o.boolean(&s, !s.truthy(v20720)))) break :logical20721 o.boolean(&s, !s.truthy(v20720));
        const v20723 = try o.importValue(&s, graph, "schema/types/index.mjs", "*");
        const v20724 = try s.text("IsDynamicAnchor");
        const v20725 = try s.own(try js.getKey(e, v20723, v20724));
        const v20726 = try o.lookup(&s, frame, "binding20629");
        const v20727 = try s.call(v20725, v20723, &.{v20726});
        break :logical20721 o.boolean(&s, !s.truthy(v20727));
    };
    if (s.truthy(v20722)) {
        const v20728 = try o.lookup(&s, frame, "binding20629");
        return c.JS_DupValue(e.context, v20728);
    }
    const v20729 = try s.global("URL");
    const v20730 = try o.lookup(&s, frame, "binding20614");
    const v20731 = try s.text("$dynamicRef");
    const v20732 = try s.own(try js.getKey(e, v20730, v20731));
    const v20733 = try o.lookup(&s, frame, "binding20627");
    const v20734 = try o.construct(&s, v20729, &.{ v20732, v20733 });
    const v20735 = try s.text("hash");
    const v20736 = try s.own(try js.getKey(e, v20734, v20735));
    try o.assign(&s, frame, "binding20630", v20736);
    const v20737 = try o.lookup(&s, frame, "binding20630");
    const v20738 = try s.text("startsWith");
    const v20739 = try s.own(try js.getKey(e, v20737, v20738));
    const v20740 = try s.text("#/");
    const v20741 = try s.call(v20739, v20737, &.{v20740});
    if (s.truthy(v20741)) {
        const v20742 = try o.lookup(&s, frame, "binding20629");
        return c.JS_DupValue(e.context, v20742);
    }
    const v20743 = try o.lookup(&s, frame, "binding20615");
    const v20744 = try s.text("find");
    const v20745 = try s.own(try js.getKey(e, v20743, v20744));
    const v20760 = try o.arrow(&s, "", 1, body20746C, &.{ graph, frame });
    const v20761 = try s.call(v20745, v20743, &.{v20760});
    try o.assign(&s, frame, "binding20631", v20761);
    const v20762 = try o.lookup(&s, frame, "binding20631");
    const v20764 = logical20763: {
        if (!c.JS_IsNull(v20762) and !c.JS_IsUndefined(v20762)) break :logical20763 v20762;
        const v20765 = try o.lookup(&s, frame, "binding20629");
        break :logical20763 v20765;
    };
    return c.JS_DupValue(e.context, v20764);
}
fn body20767(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v20777 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding20768", v20777);
    const v20778 = if (args.len > 1) args[1] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding20769", v20778);
    const v20786 = try o.lookup(&s, frame, "binding20768");
    const v20787 = try s.text("inRetrievedFrame");
    const v20788 = try s.own(try js.getKey(e, v20786, v20787));
    const v20790 = conditional20789: {
        if (s.truthy(v20788)) {
            const v20791 = try o.lookup(&s, frame, "binding20768");
            const v20792 = try s.text("lexicalSchema");
            const v20793 = try s.own(try js.getKey(e, v20791, v20792));
            break :conditional20789 v20793;
        } else {
            const v20794 = try o.lookup(&s, frame, "binding20768");
            const v20795 = try s.text("root");
            const v20796 = try s.own(try js.getKey(e, v20794, v20795));
            break :conditional20789 v20796;
        }
    };
    try o.assign(&s, frame, "binding20779", v20790);
    const v20797 = try o.lookup(&s, frame, "binding20769");
    const v20798 = try s.text("$ref");
    const v20799 = try s.own(try js.getKey(e, v20797, v20798));
    const v20800 = try s.text("startsWith");
    const v20801 = try s.own(try js.getKey(e, v20799, v20800));
    const v20802 = try s.text("#");
    const v20803 = try s.call(v20801, v20799, &.{v20802});
    const v20805 = conditional20804: {
        if (s.truthy(v20803)) {
            const v20806 = try o.lookup(&s, frame, "binding20768");
            const v20807 = try s.text("lexicalSchema");
            const v20808 = try s.own(try js.getKey(e, v20806, v20807));
            break :conditional20804 v20808;
        } else {
            const v20809 = try o.lookup(&s, frame, "binding20779");
            break :conditional20804 v20809;
        }
    };
    try o.assign(&s, frame, "binding20780", v20805);
    const v20810 = try o.lookup(&s, frame, "binding19629");
    const v20811 = try o.lookup(&s, frame, "binding20768");
    const v20812 = try s.text("context");
    const v20813 = try s.own(try js.getKey(e, v20811, v20812));
    const v20814 = try o.lookup(&s, frame, "binding20780");
    const v20815 = try o.lookup(&s, frame, "binding20768");
    const v20816 = try s.text("referenceBase");
    const v20817 = try s.own(try js.getKey(e, v20815, v20816));
    const v20818 = try o.lookup(&s, frame, "binding20769");
    const v20819 = try s.text("$ref");
    const v20820 = try s.own(try js.getKey(e, v20818, v20819));
    const v20821 = try s.call(v20810, c.pi_js_undefined(), &.{ v20813, v20814, v20817, v20820, o.boolean(&s, false) });
    try o.assign(&s, frame, "binding20781", v20821);
    const v20822 = try o.lookup(&s, frame, "binding20781");
    const v20824 = logical20823: {
        if (s.truthy(o.boolean(&s, !s.truthy(v20822)))) break :logical20823 o.boolean(&s, !s.truthy(v20822));
        const v20825 = try o.importValue(&s, graph, "schema/types/index.mjs", "*");
        const v20826 = try s.text("IsSchemaObject");
        const v20827 = try s.own(try js.getKey(e, v20825, v20826));
        const v20828 = try o.lookup(&s, frame, "binding20781");
        const v20829 = try s.call(v20827, v20825, &.{v20828});
        break :logical20823 o.boolean(&s, !s.truthy(v20829));
    };
    if (s.truthy(v20824)) {
        const v20830 = try s.object();
        const v20831 = try s.text("schema");
        const v20832 = try o.lookup(&s, frame, "binding20781");
        try o.defineKey(&s, v20830, v20831, v20832);
        return c.JS_DupValue(e.context, v20830);
    }
    const v20833 = try s.global("URL");
    const v20834 = try o.lookup(&s, frame, "binding20769");
    const v20835 = try s.text("$ref");
    const v20836 = try s.own(try js.getKey(e, v20834, v20835));
    const v20837 = try o.lookup(&s, frame, "binding20768");
    const v20838 = try s.text("referenceBase");
    const v20839 = try s.own(try js.getKey(e, v20837, v20838));
    const v20840 = try o.construct(&s, v20833, &.{ v20836, v20839 });
    const v20841 = try s.text("href");
    const v20842 = try s.own(try js.getKey(e, v20840, v20841));
    const v20843 = try s.text("split");
    const v20844 = try s.own(try js.getKey(e, v20842, v20843));
    const v20845 = try s.text("#");
    const v20846 = try s.call(v20844, v20842, &.{v20845});
    const v20847 = try o.propertyKey(&s, c.JS_NewFloat64(e.context, 0));
    const v20848 = try s.own(try js.getKey(e, v20846, v20847));
    try o.assign(&s, frame, "binding20782", v20848);
    const v20849 = try o.importValue(&s, graph, "guard/index.mjs", "Guard");
    const v20850 = try s.text("IsEqual");
    const v20851 = try s.own(try js.getKey(e, v20849, v20850));
    const v20852 = try o.lookup(&s, frame, "binding20782");
    const v20853 = try o.lookup(&s, frame, "binding20768");
    const v20854 = try s.text("resourceBase");
    const v20855 = try s.own(try js.getKey(e, v20853, v20854));
    const v20856 = try s.call(v20851, v20849, &.{ v20852, v20855 });
    try o.assign(&s, frame, "binding20783", o.boolean(&s, !s.truthy(v20856)));
    const v20857 = try o.lookup(&s, frame, "binding19627");
    const v20858 = try o.lookup(&s, frame, "binding20768");
    const v20859 = try o.lookup(&s, frame, "binding20769");
    const v20860 = try o.lookup(&s, frame, "binding20781");
    const v20861 = try o.lookup(&s, frame, "binding20782");
    const v20862 = try o.lookup(&s, frame, "binding20783");
    const v20863 = try s.call(v20857, c.pi_js_undefined(), &.{ v20858, v20859, v20860, v20861, v20862 });
    try o.assign(&s, frame, "binding20784", v20863);
    const v20864 = try o.lookup(&s, frame, "binding20783");
    const v20866 = conditional20865: {
        if (s.truthy(v20864)) {
            const v20867 = try o.lookup(&s, frame, "binding19628");
            const v20868 = try o.lookup(&s, frame, "binding20768");
            const v20869 = try s.text("context");
            const v20870 = try s.own(try js.getKey(e, v20868, v20869));
            const v20871 = try o.lookup(&s, frame, "binding20768");
            const v20872 = try s.text("root");
            const v20873 = try s.own(try js.getKey(e, v20871, v20872));
            const v20874 = try o.lookup(&s, frame, "binding20768");
            const v20875 = try s.text("referenceBase");
            const v20876 = try s.own(try js.getKey(e, v20874, v20875));
            const v20877 = try o.lookup(&s, frame, "binding20782");
            const v20878 = try o.lookup(&s, frame, "binding20781");
            const v20879 = try o.lookup(&s, frame, "binding20768");
            const v20880 = try s.text("ids");
            const v20881 = try s.own(try js.getKey(e, v20879, v20880));
            const v20882 = try s.call(v20867, c.pi_js_undefined(), &.{ v20870, v20873, v20876, v20877, v20878, v20881 });
            break :conditional20865 v20882;
        } else {
            break :conditional20865 c.pi_js_undefined();
        }
    };
    try o.assign(&s, frame, "binding20785", v20866);
    const v20883 = try s.object();
    const v20884 = try s.text("schema");
    const v20885 = try o.lookup(&s, frame, "binding20781");
    try o.defineKey(&s, v20883, v20884, v20885);
    const v20886 = try s.text("retrievedResource");
    const v20887 = try o.lookup(&s, frame, "binding20784");
    try o.defineKey(&s, v20883, v20886, v20887);
    const v20888 = try s.text("resolvedResource");
    const v20889 = try o.lookup(&s, frame, "binding20785");
    try o.defineKey(&s, v20883, v20888, v20889);
    return c.JS_DupValue(e.context, v20883);
}
fn body20891(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v20895 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding20892", v20895);
    const v20896 = if (args.len > 1) args[1] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding20893", v20896);
    const v20898 = try o.importValue(&s, graph, "schema/types/index.mjs", "*");
    const v20899 = try s.text("IsRecursiveAnchorTrue");
    const v20900 = try s.own(try js.getKey(e, v20898, v20899));
    const v20901 = try o.lookup(&s, frame, "binding20892");
    const v20902 = try s.text("lexicalSchema");
    const v20903 = try s.own(try js.getKey(e, v20901, v20902));
    const v20904 = try s.call(v20900, v20898, &.{v20903});
    const v20906 = conditional20905: {
        if (s.truthy(v20904)) {
            const v20907 = try o.lookup(&s, frame, "binding20892");
            const v20908 = try s.text("recursiveAnchors");
            const v20909 = try s.own(try js.getKey(e, v20907, v20908));
            const v20910 = try o.propertyKey(&s, c.JS_NewFloat64(e.context, 0));
            const v20911 = try s.own(try js.getKey(e, v20909, v20910));
            break :conditional20905 v20911;
        } else {
            const v20912 = try o.lookup(&s, frame, "binding20892");
            const v20913 = try s.text("lexicalSchema");
            const v20914 = try s.own(try js.getKey(e, v20912, v20913));
            break :conditional20905 v20914;
        }
    };
    try o.assign(&s, frame, "binding20897", v20906);
    const v20915 = try o.lookup(&s, frame, "binding19629");
    const v20916 = try o.lookup(&s, frame, "binding20892");
    const v20917 = try s.text("context");
    const v20918 = try s.own(try js.getKey(e, v20916, v20917));
    const v20919 = try o.lookup(&s, frame, "binding20897");
    const v20920 = try o.lookup(&s, frame, "binding20892");
    const v20921 = try s.text("lexicalBase");
    const v20922 = try s.own(try js.getKey(e, v20920, v20921));
    const v20923 = try o.lookup(&s, frame, "binding20893");
    const v20924 = try s.text("$recursiveRef");
    const v20925 = try s.own(try js.getKey(e, v20923, v20924));
    const v20926 = try s.call(v20915, c.pi_js_undefined(), &.{ v20918, v20919, v20922, v20925, o.boolean(&s, false) });
    return c.JS_DupValue(e.context, v20926);
}
fn body20928(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    _ = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v20931 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding20929", v20931);
    const v20932 = if (args.len > 1) args[1] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding20930", v20932);
    const v20933 = try o.lookup(&s, frame, "binding19630");
    const v20934 = try o.lookup(&s, frame, "binding20929");
    const v20935 = try s.text("context");
    const v20936 = try s.own(try js.getKey(e, v20934, v20935));
    const v20937 = try o.lookup(&s, frame, "binding20929");
    const v20938 = try s.text("root");
    const v20939 = try s.own(try js.getKey(e, v20937, v20938));
    const v20940 = try o.lookup(&s, frame, "binding20929");
    const v20941 = try s.text("lexicalBase");
    const v20942 = try s.own(try js.getKey(e, v20940, v20941));
    const v20943 = try o.lookup(&s, frame, "binding20929");
    const v20944 = try s.text("lexicalSchema");
    const v20945 = try s.own(try js.getKey(e, v20943, v20944));
    const v20946 = try o.lookup(&s, frame, "binding20930");
    const v20947 = try o.lookup(&s, frame, "binding20929");
    const v20948 = try s.text("dynamicAnchors");
    const v20949 = try s.own(try js.getKey(e, v20947, v20948));
    const v20950 = try s.call(v20933, c.pi_js_undefined(), &.{ v20936, v20939, v20942, v20945, v20946, v20949 });
    return c.JS_DupValue(e.context, v20950);
}
