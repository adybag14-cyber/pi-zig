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
    const namespace = try s.get(modules, "value/create/from_boolean.mjs");
    const frame = try o.frame(&s, c.pi_js_null());
    try s.put(frame, "@this", c.pi_js_undefined());
    try s.put(try s.get(graph, "frames"), "value/create/from_boolean.mjs", frame);
    const bindings = try s.object();
    try s.put(try s.get(graph, "bindings"), "value/create/from_boolean.mjs", bindings);
    const v28499 = try s.own(try ordinary.create(e, "FromBoolean", 2, body28494, &.{ graph, frame }));
    try o.assign(&s, frame, "binding28493", v28499);
    const v28500 = try o.lookup(&s, frame, "binding28493");
    try s.put(namespace, "FromBoolean", v28500);
    const v28501 = try o.lookup(&s, frame, "binding28493");
    try s.put(namespace, "FromBoolean", v28501);
    try s.put(bindings, "FromBoolean", try s.text("binding28493"));
}
fn body28494(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    _ = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v28497 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding28495", v28497);
    const v28498 = if (args.len > 1) args[1] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding28496", v28498);
    return c.JS_DupValue(e.context, o.boolean(&s, false));
}
