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
    const namespace = try s.get(modules, "value/clone/clone.mjs");
    const frame = try o.frame(&s, c.pi_js_null());
    try s.put(frame, "@this", c.pi_js_undefined());
    try s.put(try s.get(graph, "frames"), "value/clone/clone.mjs", frame);
    const bindings = try s.object();
    try s.put(try s.get(graph, "bindings"), "value/clone/clone.mjs", bindings);
    const v23963 = try s.own(try ordinary.create(e, "Clone", 1, body23957, &.{ graph, frame }));
    try o.assign(&s, frame, "binding23956", v23963);
    const v23964 = try o.lookup(&s, frame, "binding23956");
    try s.put(namespace, "Clone", v23964);
    const v23965 = try o.lookup(&s, frame, "binding23956");
    try s.put(namespace, "Clone", v23965);
    try s.put(bindings, "Clone", try s.text("binding23956"));
}
fn body23957(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v23959 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding23958", v23959);
    const v23960 = try o.importValue(&s, graph, "system/memory/clone.mjs", "Clone");
    const v23961 = try o.lookup(&s, frame, "binding23958");
    const v23962 = try o.call(&s, @src(), v23960, c.pi_js_undefined(), &.{v23961});
    return c.JS_DupValue(e.context, v23962);
}
