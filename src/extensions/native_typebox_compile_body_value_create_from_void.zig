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
    const namespace = try s.get(modules, "value/create/from_void.mjs");
    const frame = try o.frame(&s, c.pi_js_null());
    try s.put(frame, "@this", c.pi_js_undefined());
    try s.put(try s.get(graph, "frames"), "value/create/from_void.mjs", frame);
    const bindings = try s.object();
    try s.put(try s.get(graph, "bindings"), "value/create/from_void.mjs", bindings);
    const v29291 = try s.own(try ordinary.create(e, "FromVoid", 2, body29286, &.{ graph, frame }));
    try o.assign(&s, frame, "binding29285", v29291);
    const v29292 = try o.lookup(&s, frame, "binding29285");
    try s.put(namespace, "FromVoid", v29292);
    const v29293 = try o.lookup(&s, frame, "binding29285");
    try s.put(namespace, "FromVoid", v29293);
    try s.put(bindings, "FromVoid", try s.text("binding29285"));
}
fn body29286(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    _ = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v29289 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding29287", v29289);
    const v29290 = if (args.len > 1) args[1] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding29288", v29290);
    _ = c.JS_NewFloat64(e.context, 0);
    return c.JS_DupValue(e.context, c.pi_js_undefined());
}
