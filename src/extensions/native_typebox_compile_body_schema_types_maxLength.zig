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
    const namespace = try s.get(modules, "schema/types/maxLength.mjs");
    const frame = try o.frame(&s, c.pi_js_null());
    try s.put(frame, "@this", c.pi_js_undefined());
    try s.put(try s.get(graph, "frames"), "schema/types/maxLength.mjs", frame);
    const bindings = try s.object();
    try s.put(try s.get(graph, "bindings"), "schema/types/maxLength.mjs", bindings);
    const v21828 = try s.own(try ordinary.create(e, "IsMaxLength", 1, body21810, &.{ graph, frame }));
    try o.assign(&s, frame, "binding21809", v21828);
    const v21829 = try o.lookup(&s, frame, "binding21809");
    try s.put(namespace, "IsMaxLength", v21829);
    const v21830 = try o.lookup(&s, frame, "binding21809");
    try s.put(namespace, "IsMaxLength", v21830);
    try s.put(bindings, "IsMaxLength", try s.text("binding21809"));
}
fn body21810(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v21812 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding21811", v21812);
    const v21813 = try o.importValue(&s, graph, "guard/index.mjs", "Guard");
    const v21814 = try s.text("HasPropertyKey");
    const v21815 = try s.own(try js.getKey(e, v21813, v21814));
    const v21816 = try o.lookup(&s, frame, "binding21811");
    const v21817 = try s.text("maxLength");
    const v21818 = try s.call(v21815, v21813, &.{ v21816, v21817 });
    const v21820 = logical21819: {
        if (!s.truthy(v21818)) break :logical21819 v21818;
        const v21821 = try o.importValue(&s, graph, "guard/index.mjs", "Guard");
        const v21822 = try s.text("IsNumber");
        const v21823 = try s.own(try js.getKey(e, v21821, v21822));
        const v21824 = try o.lookup(&s, frame, "binding21811");
        const v21825 = try s.text("maxLength");
        const v21826 = try s.own(try js.getKey(e, v21824, v21825));
        const v21827 = try s.call(v21823, v21821, &.{v21826});
        break :logical21819 v21827;
    };
    return c.JS_DupValue(e.context, v21820);
}
