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
    const namespace = try s.get(modules, "system/unreachable/unreachable.mjs");
    const frame = try o.frame(&s, c.pi_js_null());
    try s.put(frame, "@this", c.pi_js_undefined());
    try s.put(try s.get(graph, "frames"), "system/unreachable/unreachable.mjs", frame);
    const bindings = try s.object();
    try s.put(try s.get(graph, "bindings"), "system/unreachable/unreachable.mjs", bindings);
    const v22915 = try s.own(try ordinary.create(e, "Unreachable", 0, body22911, &.{ graph, frame }));
    try o.assign(&s, frame, "binding22910", v22915);
    const v22916 = try o.lookup(&s, frame, "binding22910");
    try s.put(namespace, "Unreachable", v22916);
    const v22917 = try o.lookup(&s, frame, "binding22910");
    try s.put(namespace, "Unreachable", v22917);
    try s.put(bindings, "Unreachable", try s.text("binding22910"));
}
fn body22911(e: *Engine, receiver: c.JSValue, _: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    _ = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v22912 = try s.global("Error");
    const v22913 = try s.text("Unreachable");
    const v22914 = try o.construct(&s, v22912, &.{v22913});
    _ = c.JS_Throw(e.context, c.JS_DupValue(e.context, v22914));
    return js.capture(e);
}
