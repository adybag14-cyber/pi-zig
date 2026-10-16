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
    const namespace = try s.get(modules, "schema/types/maximum.mjs");
    const frame = try o.frame(&s, c.pi_js_null());
    try s.put(frame, "@this", c.pi_js_undefined());
    try s.put(try s.get(graph, "frames"), "schema/types/maximum.mjs", frame);
    const bindings = try s.object();
    try s.put(try s.get(graph, "bindings"), "schema/types/maximum.mjs", bindings);
    const v21784 = try s.own(try ordinary.create(e, "IsMaximum", 1, body21757, &.{ graph, frame }));
    try o.assign(&s, frame, "binding21756", v21784);
    const v21785 = try o.lookup(&s, frame, "binding21756");
    try s.put(namespace, "IsMaximum", v21785);
    const v21786 = try o.lookup(&s, frame, "binding21756");
    try s.put(namespace, "IsMaximum", v21786);
    try s.put(bindings, "IsMaximum", try s.text("binding21756"));
}
fn body21757(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v21759 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding21758", v21759);
    const v21760 = try o.importValue(&s, graph, "guard/index.mjs", "Guard");
    const v21761 = try s.text("HasPropertyKey");
    const v21762 = try s.own(try js.getKey(e, v21760, v21761));
    const v21763 = try o.lookup(&s, frame, "binding21758");
    const v21764 = try s.text("maximum");
    const v21765 = try s.call(v21762, v21760, &.{ v21763, v21764 });
    const v21767 = logical21766: {
        if (!s.truthy(v21765)) break :logical21766 v21765;
        const v21768 = try o.importValue(&s, graph, "guard/index.mjs", "Guard");
        const v21769 = try s.text("IsNumber");
        const v21770 = try s.own(try js.getKey(e, v21768, v21769));
        const v21771 = try o.lookup(&s, frame, "binding21758");
        const v21772 = try s.text("maximum");
        const v21773 = try s.own(try js.getKey(e, v21771, v21772));
        const v21774 = try s.call(v21770, v21768, &.{v21773});
        const v21776 = logical21775: {
            if (s.truthy(v21774)) break :logical21775 v21774;
            const v21777 = try o.importValue(&s, graph, "guard/index.mjs", "Guard");
            const v21778 = try s.text("IsBigInt");
            const v21779 = try s.own(try js.getKey(e, v21777, v21778));
            const v21780 = try o.lookup(&s, frame, "binding21758");
            const v21781 = try s.text("maximum");
            const v21782 = try s.own(try js.getKey(e, v21780, v21781));
            const v21783 = try s.call(v21779, v21777, &.{v21782});
            break :logical21775 v21783;
        };
        break :logical21766 v21776;
    };
    return c.JS_DupValue(e.context, v21767);
}
