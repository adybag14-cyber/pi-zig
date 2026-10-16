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
    const namespace = try s.get(modules, "value/default/from_tuple.mjs");
    const frame = try o.frame(&s, c.pi_js_null());
    try s.put(frame, "@this", c.pi_js_undefined());
    try s.put(try s.get(graph, "frames"), "value/default/from_tuple.mjs", frame);
    const bindings = try s.object();
    try s.put(try s.get(graph, "bindings"), "value/default/from_tuple.mjs", bindings);
    const v29789 = try s.own(try ordinary.create(e, "FromTuple", 3, body29725, &.{ graph, frame }));
    try o.assign(&s, frame, "binding29724", v29789);
    const v29790 = try o.lookup(&s, frame, "binding29724");
    try s.put(namespace, "FromTuple", v29790);
    const v29791 = try o.lookup(&s, frame, "binding29724");
    try s.put(namespace, "FromTuple", v29791);
    try s.put(bindings, "FromTuple", try s.text("binding29724"));
}
fn body29725(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v29731 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding29726", v29731);
    const v29732 = if (args.len > 1) args[1] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding29727", v29732);
    const v29733 = if (args.len > 2) args[2] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding29728", v29733);
    const v29736 = try o.importValue(&s, graph, "guard/index.mjs", "Guard");
    const v29737 = try s.text("IsArray");
    const v29738 = try s.own(try js.getKey(e, v29736, v29737));
    const v29739 = try o.lookup(&s, frame, "binding29728");
    const v29740 = try s.call(v29738, v29736, &.{v29739});
    if (s.truthy(o.boolean(&s, !s.truthy(v29740)))) {
        const v29741 = try o.lookup(&s, frame, "binding29728");
        return c.JS_DupValue(e.context, v29741);
    }
    const v29742 = try s.array();
    const v29743 = try o.lookup(&s, frame, "binding29727");
    const v29744 = try s.text("items");
    const v29745 = try s.own(try js.getKey(e, v29743, v29744));
    try o.append(&s, v29742, v29745);
    const v29746 = try s.global("Math");
    const v29747 = try s.text("max");
    const v29748 = try s.own(try js.getKey(e, v29746, v29747));
    const v29749 = try o.lookup(&s, frame, "binding29727");
    const v29750 = try s.text("items");
    const v29751 = try s.own(try js.getKey(e, v29749, v29750));
    const v29752 = try s.text("length");
    const v29753 = try s.own(try js.getKey(e, v29751, v29752));
    const v29754 = try o.lookup(&s, frame, "binding29728");
    const v29755 = try s.text("length");
    const v29756 = try s.own(try js.getKey(e, v29754, v29755));
    const v29757 = try s.call(v29748, v29746, &.{ v29753, v29756 });
    try o.append(&s, v29742, v29757);
    var destructure29758 = try o.iterator(e, v29742);
    defer destructure29758.deinit();
    errdefer destructure29758.closePreserving();
    const v29759 = try s.own(if (destructure29758.closed) c.pi_js_undefined() else (try destructure29758.next()) orelse c.pi_js_undefined());
    try o.assign(&s, frame, "binding29734", v29759);
    const v29760 = try s.own(if (destructure29758.closed) c.pi_js_undefined() else (try destructure29758.next()) orelse c.pi_js_undefined());
    try o.assign(&s, frame, "binding29735", v29760);
    try destructure29758.close();
    try o.assign(&s, frame, "binding29761", c.JS_NewFloat64(e.context, 0));
    loop29762: while (true) {
        const v29764 = try o.lookup(&s, frame, "binding29761");
        const v29765 = try o.lookup(&s, frame, "binding29735");
        const v29766 = try s.own(try e.checked(c.JS_PiBinaryOperator(e.context, 4, v29764, v29765)));
        if (!s.truthy(v29766)) break :loop29762;
        {
            const v29767 = try o.lookup(&s, frame, "binding29761");
            const v29768 = try o.lookup(&s, frame, "binding29734");
            const v29769 = try s.text("length");
            const v29770 = try s.own(try js.getKey(e, v29768, v29769));
            const v29771 = try s.own(try e.checked(c.JS_PiBinaryOperator(e.context, 4, v29767, v29770)));
            if (s.truthy(v29771)) {
                const v29772 = try o.lookup(&s, frame, "binding29728");
                const v29773 = try o.lookup(&s, frame, "binding29761");
                const v29774 = try o.propertyKey(&s, v29773);
                const v29775 = try o.importValue(&s, graph, "value/default/from_type.mjs", "FromType");
                const v29776 = try o.lookup(&s, frame, "binding29726");
                const v29777 = try o.lookup(&s, frame, "binding29734");
                const v29778 = try o.lookup(&s, frame, "binding29761");
                const v29779 = try o.propertyKey(&s, v29778);
                const v29780 = try s.own(try js.getKey(e, v29777, v29779));
                const v29781 = try o.lookup(&s, frame, "binding29728");
                const v29782 = try o.lookup(&s, frame, "binding29761");
                const v29783 = try o.propertyKey(&s, v29782);
                const v29784 = try s.own(try js.getKey(e, v29781, v29783));
                const v29785 = try s.call(v29775, c.pi_js_undefined(), &.{ v29776, v29780, v29784 });
                try js.setKey(e, v29772, v29774, v29785);
            }
        }
        const v29786 = try o.lookup(&s, frame, "binding29761");
        const v29787 = try s.own(try e.checked(c.JS_PiIncrement(e.context, v29786)));
        try o.assign(&s, frame, "binding29761", v29787);
    }
    const v29788 = try o.lookup(&s, frame, "binding29728");
    return c.JS_DupValue(e.context, v29788);
}
