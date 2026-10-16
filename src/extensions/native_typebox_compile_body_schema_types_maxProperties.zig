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
    const namespace = try s.get(modules, "schema/types/maxProperties.mjs");
    const frame = try o.frame(&s, c.pi_js_null());
    try s.put(frame, "@this", c.pi_js_undefined());
    try s.put(try s.get(graph, "frames"), "schema/types/maxProperties.mjs", frame);
    const bindings = try s.object();
    try s.put(try s.get(graph, "bindings"), "schema/types/maxProperties.mjs", bindings);
    const v21850 = try s.own(try ordinary.create(e, "IsMaxProperties", 1, body21832, &.{ graph, frame }));
    try o.assign(&s, frame, "binding21831", v21850);
    const v21851 = try o.lookup(&s, frame, "binding21831");
    try s.put(namespace, "IsMaxProperties", v21851);
    const v21852 = try o.lookup(&s, frame, "binding21831");
    try s.put(namespace, "IsMaxProperties", v21852);
    try s.put(bindings, "IsMaxProperties", try s.text("binding21831"));
}
fn body21832(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v21834 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding21833", v21834);
    const v21835 = try o.importValue(&s, graph, "guard/index.mjs", "Guard");
    const v21836 = try s.text("HasPropertyKey");
    const v21837 = try s.own(try js.getKey(e, v21835, v21836));
    const v21838 = try o.lookup(&s, frame, "binding21833");
    const v21839 = try s.text("maxProperties");
    const v21840 = try o.call(&s, @src(), v21837, v21835, &.{ v21838, v21839 });
    const v21842 = logical21841: {
        if (!s.truthy(v21840)) break :logical21841 v21840;
        const v21843 = try o.importValue(&s, graph, "guard/index.mjs", "Guard");
        const v21844 = try s.text("IsNumber");
        const v21845 = try s.own(try js.getKey(e, v21843, v21844));
        const v21846 = try o.lookup(&s, frame, "binding21833");
        const v21847 = try s.text("maxProperties");
        const v21848 = try s.own(try js.getKey(e, v21846, v21847));
        const v21849 = try o.call(&s, @src(), v21845, v21843, &.{v21848});
        break :logical21841 v21849;
    };
    return c.JS_DupValue(e.context, v21842);
}
