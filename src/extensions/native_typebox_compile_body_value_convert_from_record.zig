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
    const namespace = try s.get(modules, "value/convert/from_record.mjs");
    const frame = try o.frame(&s, c.pi_js_null());
    try s.put(frame, "@this", c.pi_js_undefined());
    try s.put(try s.get(graph, "frames"), "value/convert/from_record.mjs", frame);
    const bindings = try s.object();
    try s.put(try s.get(graph, "bindings"), "value/convert/from_record.mjs", bindings);
    const v26780 = try s.own(try ordinary.create(e, "FromPatternProperties", 3, body26699, &.{ graph, frame }));
    try o.assign(&s, frame, "binding26697", v26780);
    const v26801 = try s.own(try ordinary.create(e, "FromRecord", 3, body26781, &.{ graph, frame }));
    try o.assign(&s, frame, "binding26698", v26801);
    const v26802 = try o.lookup(&s, frame, "binding26698");
    try s.put(namespace, "FromRecord", v26802);
    const v26803 = try o.lookup(&s, frame, "binding26698");
    try s.put(namespace, "FromRecord", v26803);
    try s.put(bindings, "FromRecord", try s.text("binding26698"));
}
fn body26699(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v26705 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding26700", v26705);
    const v26706 = if (args.len > 1) args[1] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding26701", v26706);
    const v26707 = if (args.len > 2) args[2] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding26702", v26707);
    const v26710 = try o.importValue(&s, graph, "guard/index.mjs", "Guard");
    const v26711 = try s.text("EntriesRegExp");
    const v26712 = try s.own(try js.getKey(e, v26710, v26711));
    const v26713 = try o.lookup(&s, frame, "binding26701");
    const v26714 = try s.text("patternProperties");
    const v26715 = try s.own(try js.getKey(e, v26713, v26714));
    const v26716 = try s.call(v26712, v26710, &.{v26715});
    try o.assign(&s, frame, "binding26708", v26716);
    const v26717 = try o.importValue(&s, graph, "guard/index.mjs", "Guard");
    const v26718 = try s.text("Keys");
    const v26719 = try s.own(try js.getKey(e, v26717, v26718));
    const v26720 = try o.lookup(&s, frame, "binding26702");
    const v26721 = try s.call(v26719, v26717, &.{v26720});
    try o.assign(&s, frame, "binding26709", v26721);
    const v26722 = try o.lookup(&s, frame, "binding26708");
    var iterator26723 = try o.iterator(e, v26722);
    defer iterator26723.deinit();
    errdefer iterator26723.closePreserving();
    while (try iterator26723.next()) |next26724| {
        defer e.freeValue(next26724);
        const iteration26726 = try o.frame(&s, frame);
        var destructure26729 = try o.iterator(e, next26724);
        defer destructure26729.deinit();
        errdefer destructure26729.closePreserving();
        const v26730 = try s.own(if (destructure26729.closed) c.pi_js_undefined() else (try destructure26729.next()) orelse c.pi_js_undefined());
        try o.assign(&s, iteration26726, "binding26727", v26730);
        const v26731 = try s.own(if (destructure26729.closed) c.pi_js_undefined() else (try destructure26729.next()) orelse c.pi_js_undefined());
        try o.assign(&s, iteration26726, "binding26728", v26731);
        try destructure26729.close();
        const v26732 = try o.lookup(&s, iteration26726, "binding26709");
        var iterator26733 = try o.iterator(e, v26732);
        defer iterator26733.deinit();
        errdefer iterator26733.closePreserving();
        while (try iterator26733.next()) |next26734| {
            defer e.freeValue(next26734);
            const iteration26736 = try o.frame(&s, iteration26726);
            try o.assign(&s, iteration26736, "binding26737", next26734);
            const v26738 = try o.lookup(&s, iteration26736, "binding26727");
            const v26739 = try s.text("test");
            const v26740 = try s.own(try js.getKey(e, v26738, v26739));
            const v26741 = try o.lookup(&s, iteration26736, "binding26737");
            const v26742 = try s.call(v26740, v26738, &.{v26741});
            if (s.truthy(v26742)) {
                const v26743 = try o.lookup(&s, iteration26736, "binding26702");
                const v26744 = try o.lookup(&s, iteration26736, "binding26737");
                const v26745 = try o.propertyKey(&s, v26744);
                const v26746 = try o.importValue(&s, graph, "value/convert/from_type.mjs", "FromType");
                const v26747 = try o.lookup(&s, iteration26736, "binding26700");
                const v26748 = try o.lookup(&s, iteration26736, "binding26728");
                const v26749 = try o.lookup(&s, iteration26736, "binding26702");
                const v26750 = try o.lookup(&s, iteration26736, "binding26737");
                const v26751 = try o.propertyKey(&s, v26750);
                const v26752 = try s.own(try js.getKey(e, v26749, v26751));
                const v26753 = try s.call(v26746, c.pi_js_undefined(), &.{ v26747, v26748, v26752 });
                try js.setKey(e, v26743, v26745, v26753);
            }
        }
        try iterator26733.close();
    }
    try iterator26723.close();
    const v26754 = try o.importValue(&s, graph, "guard/index.mjs", "Guard");
    const v26755 = try s.text("HasPropertyKey");
    const v26756 = try s.own(try js.getKey(e, v26754, v26755));
    const v26757 = try o.lookup(&s, frame, "binding26701");
    const v26758 = try s.text("additionalProperties");
    const v26759 = try s.call(v26756, v26754, &.{ v26757, v26758 });
    const v26761 = logical26760: {
        if (!s.truthy(v26759)) break :logical26760 v26759;
        const v26762 = try o.importValue(&s, graph, "guard/index.mjs", "Guard");
        const v26763 = try s.text("IsObject");
        const v26764 = try s.own(try js.getKey(e, v26762, v26763));
        const v26765 = try o.lookup(&s, frame, "binding26701");
        const v26766 = try s.text("additionalProperties");
        const v26767 = try s.own(try js.getKey(e, v26765, v26766));
        const v26768 = try s.call(v26764, v26762, &.{v26767});
        break :logical26760 v26768;
    };
    const v26770 = conditional26769: {
        if (s.truthy(v26761)) {
            const v26771 = try o.importValue(&s, graph, "value/convert/from_additional.mjs", "FromAdditionalProperties");
            const v26772 = try o.lookup(&s, frame, "binding26700");
            const v26773 = try o.lookup(&s, frame, "binding26708");
            const v26774 = try o.lookup(&s, frame, "binding26701");
            const v26775 = try s.text("additionalProperties");
            const v26776 = try s.own(try js.getKey(e, v26774, v26775));
            const v26777 = try o.lookup(&s, frame, "binding26702");
            const v26778 = try s.call(v26771, c.pi_js_undefined(), &.{ v26772, v26773, v26776, v26777 });
            break :conditional26769 v26778;
        } else {
            const v26779 = try o.lookup(&s, frame, "binding26702");
            break :conditional26769 v26779;
        }
    };
    return c.JS_DupValue(e.context, v26770);
}
fn body26781(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v26785 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding26782", v26785);
    const v26786 = if (args.len > 1) args[1] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding26783", v26786);
    const v26787 = if (args.len > 2) args[2] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding26784", v26787);
    const v26788 = try o.importValue(&s, graph, "guard/index.mjs", "Guard");
    const v26789 = try s.text("IsObjectNotArray");
    const v26790 = try s.own(try js.getKey(e, v26788, v26789));
    const v26791 = try o.lookup(&s, frame, "binding26784");
    const v26792 = try s.call(v26790, v26788, &.{v26791});
    const v26794 = conditional26793: {
        if (s.truthy(v26792)) {
            const v26795 = try o.lookup(&s, frame, "binding26697");
            const v26796 = try o.lookup(&s, frame, "binding26782");
            const v26797 = try o.lookup(&s, frame, "binding26783");
            const v26798 = try o.lookup(&s, frame, "binding26784");
            const v26799 = try s.call(v26795, c.pi_js_undefined(), &.{ v26796, v26797, v26798 });
            break :conditional26793 v26799;
        } else {
            const v26800 = try o.lookup(&s, frame, "binding26784");
            break :conditional26793 v26800;
        }
    };
    return c.JS_DupValue(e.context, v26794);
}
