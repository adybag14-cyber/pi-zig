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
    const namespace = try s.get(modules, "value/create/from_literal.mjs");
    const frame = try o.frame(&s, c.pi_js_null());
    try s.put(frame, "@this", c.pi_js_undefined());
    try s.put(try s.get(graph, "frames"), "value/create/from_literal.mjs", frame);
    const bindings = try s.object();
    try s.put(try s.get(graph, "bindings"), "value/create/from_literal.mjs", bindings);
    const v28692 = try s.own(try ordinary.create(e, "FromLiteral", 2, body28684, &.{ graph, frame }));
    try o.assign(&s, frame, "binding28683", v28692);
    const v28693 = try o.lookup(&s, frame, "binding28683");
    try s.put(namespace, "FromLiteral", v28693);
    const v28694 = try o.lookup(&s, frame, "binding28683");
    try s.put(namespace, "FromLiteral", v28694);
    try s.put(bindings, "FromLiteral", try s.text("binding28683"));
}
fn body28684(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    _ = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v28687 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding28685", v28687);
    const v28688 = if (args.len > 1) args[1] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding28686", v28688);
    const v28689 = try o.lookup(&s, frame, "binding28686");
    const v28690 = try s.text("const");
    const v28691 = try s.own(try js.getKey(e, v28689, v28690));
    return c.JS_DupValue(e.context, v28691);
}
