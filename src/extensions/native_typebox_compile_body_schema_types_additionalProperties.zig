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
    const namespace = try s.get(modules, "schema/types/additionalProperties.mjs");
    const frame = try o.frame(&s, c.pi_js_null());
    try s.put(frame, "@this", c.pi_js_undefined());
    try s.put(try s.get(graph, "frames"), "schema/types/additionalProperties.mjs", frame);
    const bindings = try s.object();
    try s.put(try s.get(graph, "bindings"), "schema/types/additionalProperties.mjs", bindings);
    const v21083 = try s.own(try ordinary.create(e, "IsAdditionalProperties", 1, body21067, &.{ graph, frame }));
    try o.assign(&s, frame, "binding21066", v21083);
    const v21084 = try o.lookup(&s, frame, "binding21066");
    try s.put(namespace, "IsAdditionalProperties", v21084);
    const v21085 = try o.lookup(&s, frame, "binding21066");
    try s.put(namespace, "IsAdditionalProperties", v21085);
    try s.put(bindings, "IsAdditionalProperties", try s.text("binding21066"));
}
fn body21067(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v21069 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding21068", v21069);
    const v21070 = try o.importValue(&s, graph, "guard/index.mjs", "Guard");
    const v21071 = try s.text("HasPropertyKey");
    const v21072 = try s.own(try js.getKey(e, v21070, v21071));
    const v21073 = try o.lookup(&s, frame, "binding21068");
    const v21074 = try s.text("additionalProperties");
    const v21075 = try o.call(&s, @src(), v21072, v21070, &.{ v21073, v21074 });
    const v21077 = logical21076: {
        if (!s.truthy(v21075)) break :logical21076 v21075;
        const v21078 = try o.importValue(&s, graph, "schema/types/schema.mjs", "IsSchema");
        const v21079 = try o.lookup(&s, frame, "binding21068");
        const v21080 = try s.text("additionalProperties");
        const v21081 = try s.own(try js.getKey(e, v21079, v21080));
        const v21082 = try o.call(&s, @src(), v21078, c.pi_js_undefined(), &.{v21081});
        break :logical21076 v21082;
    };
    return c.JS_DupValue(e.context, v21077);
}
