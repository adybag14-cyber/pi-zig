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
    const namespace = try s.get(modules, "value/clean/from_tuple.mjs");
    const frame = try o.frame(&s, c.pi_js_null());
    try s.put(frame, "@this", c.pi_js_undefined());
    try s.put(try s.get(graph, "frames"), "value/clean/from_tuple.mjs", frame);
    const bindings = try s.object();
    try s.put(try s.get(graph, "bindings"), "value/clean/from_tuple.mjs", bindings);
    const v23811 = try s.own(try ordinary.create(e, "FromTuple", 3, body23744, &.{ graph, frame }));
    try o.assign(&s, frame, "binding23743", v23811);
    const v23812 = try o.lookup(&s, frame, "binding23743");
    try s.put(namespace, "FromTuple", v23812);
    const v23813 = try o.lookup(&s, frame, "binding23743");
    try s.put(namespace, "FromTuple", v23813);
    try s.put(bindings, "FromTuple", try s.text("binding23743"));
}
fn body23744(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v23749 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding23745", v23749);
    const v23750 = if (args.len > 1) args[1] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding23746", v23750);
    const v23751 = if (args.len > 2) args[2] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding23747", v23751);
    const v23753 = try o.importValue(&s, graph, "guard/index.mjs", "Guard");
    const v23754 = try s.text("IsArray");
    const v23755 = try s.own(try js.getKey(e, v23753, v23754));
    const v23756 = try o.lookup(&s, frame, "binding23747");
    const v23757 = try s.call(v23755, v23753, &.{v23756});
    if (s.truthy(o.boolean(&s, !s.truthy(v23757)))) {
        const v23758 = try o.lookup(&s, frame, "binding23747");
        return c.JS_DupValue(e.context, v23758);
    }
    const v23759 = try s.global("Math");
    const v23760 = try s.text("min");
    const v23761 = try s.own(try js.getKey(e, v23759, v23760));
    const v23762 = try o.lookup(&s, frame, "binding23747");
    const v23763 = try s.text("length");
    const v23764 = try s.own(try js.getKey(e, v23762, v23763));
    const v23765 = try o.lookup(&s, frame, "binding23746");
    const v23766 = try s.text("items");
    const v23767 = try s.own(try js.getKey(e, v23765, v23766));
    const v23768 = try s.text("length");
    const v23769 = try s.own(try js.getKey(e, v23767, v23768));
    const v23770 = try s.call(v23761, v23759, &.{ v23764, v23769 });
    try o.assign(&s, frame, "binding23752", v23770);
    try o.assign(&s, frame, "binding23771", c.JS_NewFloat64(e.context, 0));
    loop23772: while (true) {
        const v23774 = try o.lookup(&s, frame, "binding23771");
        const v23775 = try o.lookup(&s, frame, "binding23752");
        const v23776 = try s.own(try e.checked(c.JS_PiBinaryOperator(e.context, 4, v23774, v23775)));
        if (!s.truthy(v23776)) break :loop23772;
        {
            const v23777 = try o.lookup(&s, frame, "binding23747");
            const v23778 = try o.lookup(&s, frame, "binding23771");
            const v23779 = try o.propertyKey(&s, v23778);
            const v23780 = try o.importValue(&s, graph, "value/clean/from_type.mjs", "FromType");
            const v23781 = try o.lookup(&s, frame, "binding23745");
            const v23782 = try o.lookup(&s, frame, "binding23746");
            const v23783 = try s.text("items");
            const v23784 = try s.own(try js.getKey(e, v23782, v23783));
            const v23785 = try o.lookup(&s, frame, "binding23771");
            const v23786 = try o.propertyKey(&s, v23785);
            const v23787 = try s.own(try js.getKey(e, v23784, v23786));
            const v23788 = try o.lookup(&s, frame, "binding23747");
            const v23789 = try o.lookup(&s, frame, "binding23771");
            const v23790 = try o.propertyKey(&s, v23789);
            const v23791 = try s.own(try js.getKey(e, v23788, v23790));
            const v23792 = try s.call(v23780, c.pi_js_undefined(), &.{ v23781, v23787, v23791 });
            try js.setKey(e, v23777, v23779, v23792);
        }
        const v23793 = try o.lookup(&s, frame, "binding23771");
        const v23794 = try s.own(try e.checked(c.JS_PiIncrement(e.context, v23793)));
        try o.assign(&s, frame, "binding23771", v23794);
    }
    const v23795 = try o.importValue(&s, graph, "guard/index.mjs", "Guard");
    const v23796 = try s.text("IsGreaterThan");
    const v23797 = try s.own(try js.getKey(e, v23795, v23796));
    const v23798 = try o.lookup(&s, frame, "binding23747");
    const v23799 = try s.text("length");
    const v23800 = try s.own(try js.getKey(e, v23798, v23799));
    const v23801 = try o.lookup(&s, frame, "binding23752");
    const v23802 = try s.call(v23797, v23795, &.{ v23800, v23801 });
    const v23804 = conditional23803: {
        if (s.truthy(v23802)) {
            const v23805 = try o.lookup(&s, frame, "binding23747");
            const v23806 = try s.text("slice");
            const v23807 = try s.own(try js.getKey(e, v23805, v23806));
            const v23808 = try o.lookup(&s, frame, "binding23752");
            const v23809 = try s.call(v23807, v23805, &.{ c.JS_NewFloat64(e.context, 0), v23808 });
            break :conditional23803 v23809;
        } else {
            const v23810 = try o.lookup(&s, frame, "binding23747");
            break :conditional23803 v23810;
        }
    };
    return c.JS_DupValue(e.context, v23804);
}
