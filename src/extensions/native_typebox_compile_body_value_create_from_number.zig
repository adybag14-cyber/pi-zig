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
    const namespace = try s.get(modules, "value/create/from_number.mjs");
    const frame = try o.frame(&s, c.pi_js_null());
    try s.put(frame, "@this", c.pi_js_undefined());
    try s.put(try s.get(graph, "frames"), "value/create/from_number.mjs", frame);
    const bindings = try s.object();
    try s.put(try s.get(graph, "bindings"), "value/create/from_number.mjs", bindings);
    const v28749 = try s.own(try ordinary.create(e, "FromNumber", 2, body28718, &.{ graph, frame }));
    try o.assign(&s, frame, "binding28717", v28749);
    const v28750 = try o.lookup(&s, frame, "binding28717");
    try s.put(namespace, "FromNumber", v28750);
    const v28751 = try o.lookup(&s, frame, "binding28717");
    try s.put(namespace, "FromNumber", v28751);
    try s.put(bindings, "FromNumber", try s.text("binding28717"));
}
fn body28718(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v28721 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding28719", v28721);
    const v28722 = if (args.len > 1) args[1] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding28720", v28722);
    const v28723 = try o.importValue(&s, graph, "schema/types/index.mjs", "IsExclusiveMinimum");
    const v28724 = try o.lookup(&s, frame, "binding28720");
    const v28725 = try s.call(v28723, c.pi_js_undefined(), &.{v28724});
    const v28727 = logical28726: {
        if (!s.truthy(v28725)) break :logical28726 v28725;
        const v28728 = try o.importValue(&s, graph, "guard/index.mjs", "Guard");
        const v28729 = try s.text("IsNumber");
        const v28730 = try s.own(try js.getKey(e, v28728, v28729));
        const v28731 = try o.lookup(&s, frame, "binding28720");
        const v28732 = try s.text("exclusiveMinimum");
        const v28733 = try s.own(try js.getKey(e, v28731, v28732));
        const v28734 = try s.call(v28730, v28728, &.{v28733});
        break :logical28726 v28734;
    };
    const v28736 = conditional28735: {
        if (s.truthy(v28727)) {
            const v28737 = try o.lookup(&s, frame, "binding28720");
            const v28738 = try s.text("exclusiveMinimum");
            const v28739 = try s.own(try js.getKey(e, v28737, v28738));
            const v28740 = try s.own(try e.checked(c.JS_PiBinaryOperator(e.context, 0, v28739, c.JS_NewFloat64(e.context, 1))));
            break :conditional28735 v28740;
        } else {
            const v28741 = try o.importValue(&s, graph, "schema/types/index.mjs", "IsMinimum");
            const v28742 = try o.lookup(&s, frame, "binding28720");
            const v28743 = try s.call(v28741, c.pi_js_undefined(), &.{v28742});
            const v28745 = conditional28744: {
                if (s.truthy(v28743)) {
                    const v28746 = try o.lookup(&s, frame, "binding28720");
                    const v28747 = try s.text("minimum");
                    const v28748 = try s.own(try js.getKey(e, v28746, v28747));
                    break :conditional28744 v28748;
                } else {
                    break :conditional28744 c.JS_NewFloat64(e.context, 0);
                }
            };
            break :conditional28735 v28745;
        }
    };
    return c.JS_DupValue(e.context, v28736);
}
