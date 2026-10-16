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
    const namespace = try s.get(modules, "schema/types/maxItems.mjs");
    const frame = try o.frame(&s, c.pi_js_null());
    try s.put(frame, "@this", c.pi_js_undefined());
    try s.put(try s.get(graph, "frames"), "schema/types/maxItems.mjs", frame);
    const bindings = try s.object();
    try s.put(try s.get(graph, "bindings"), "schema/types/maxItems.mjs", bindings);
    const v21806 = try s.own(try ordinary.create(e, "IsMaxItems", 1, body21788, &.{ graph, frame }));
    try o.assign(&s, frame, "binding21787", v21806);
    const v21807 = try o.lookup(&s, frame, "binding21787");
    try s.put(namespace, "IsMaxItems", v21807);
    const v21808 = try o.lookup(&s, frame, "binding21787");
    try s.put(namespace, "IsMaxItems", v21808);
    try s.put(bindings, "IsMaxItems", try s.text("binding21787"));
}
fn body21788(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v21790 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding21789", v21790);
    const v21791 = try o.importValue(&s, graph, "guard/index.mjs", "Guard");
    const v21792 = try s.text("HasPropertyKey");
    const v21793 = try s.own(try js.getKey(e, v21791, v21792));
    const v21794 = try o.lookup(&s, frame, "binding21789");
    const v21795 = try s.text("maxItems");
    const v21796 = try s.call(v21793, v21791, &.{ v21794, v21795 });
    const v21798 = logical21797: {
        if (!s.truthy(v21796)) break :logical21797 v21796;
        const v21799 = try o.importValue(&s, graph, "guard/index.mjs", "Guard");
        const v21800 = try s.text("IsNumber");
        const v21801 = try s.own(try js.getKey(e, v21799, v21800));
        const v21802 = try o.lookup(&s, frame, "binding21789");
        const v21803 = try s.text("maxItems");
        const v21804 = try s.own(try js.getKey(e, v21802, v21803));
        const v21805 = try s.call(v21801, v21799, &.{v21804});
        break :logical21797 v21805;
    };
    return c.JS_DupValue(e.context, v21798);
}
