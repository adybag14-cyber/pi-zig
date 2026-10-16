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
    const namespace = try s.get(modules, "schema/types/dynamicRef.mjs");
    const frame = try o.frame(&s, c.pi_js_null());
    try s.put(frame, "@this", c.pi_js_undefined());
    try s.put(try s.get(graph, "frames"), "schema/types/dynamicRef.mjs", frame);
    const bindings = try s.object();
    try s.put(try s.get(graph, "bindings"), "schema/types/dynamicRef.mjs", bindings);
    const v21480 = try s.own(try ordinary.create(e, "IsDynamicRef", 1, body21462, &.{ graph, frame }));
    try o.assign(&s, frame, "binding21461", v21480);
    const v21481 = try o.lookup(&s, frame, "binding21461");
    try s.put(namespace, "IsDynamicRef", v21481);
    const v21482 = try o.lookup(&s, frame, "binding21461");
    try s.put(namespace, "IsDynamicRef", v21482);
    try s.put(bindings, "IsDynamicRef", try s.text("binding21461"));
}
fn body21462(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v21464 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding21463", v21464);
    const v21465 = try o.importValue(&s, graph, "guard/index.mjs", "Guard");
    const v21466 = try s.text("HasPropertyKey");
    const v21467 = try s.own(try js.getKey(e, v21465, v21466));
    const v21468 = try o.lookup(&s, frame, "binding21463");
    const v21469 = try s.text("$dynamicRef");
    const v21470 = try s.call(v21467, v21465, &.{ v21468, v21469 });
    const v21472 = logical21471: {
        if (!s.truthy(v21470)) break :logical21471 v21470;
        const v21473 = try o.importValue(&s, graph, "guard/index.mjs", "Guard");
        const v21474 = try s.text("IsString");
        const v21475 = try s.own(try js.getKey(e, v21473, v21474));
        const v21476 = try o.lookup(&s, frame, "binding21463");
        const v21477 = try s.text("$dynamicRef");
        const v21478 = try s.own(try js.getKey(e, v21476, v21477));
        const v21479 = try s.call(v21475, v21473, &.{v21478});
        break :logical21471 v21479;
    };
    return c.JS_DupValue(e.context, v21472);
}
