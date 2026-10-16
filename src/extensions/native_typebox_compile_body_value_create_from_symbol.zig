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
    const namespace = try s.get(modules, "value/create/from_symbol.mjs");
    const frame = try o.frame(&s, c.pi_js_null());
    try s.put(frame, "@this", c.pi_js_undefined());
    try s.put(try s.get(graph, "frames"), "value/create/from_symbol.mjs", frame);
    const bindings = try s.object();
    try s.put(try s.get(graph, "bindings"), "value/create/from_symbol.mjs", bindings);
    const v28910 = try s.own(try ordinary.create(e, "FromSymbol", 2, body28903, &.{ graph, frame }));
    try o.assign(&s, frame, "binding28902", v28910);
    const v28911 = try o.lookup(&s, frame, "binding28902");
    try s.put(namespace, "FromSymbol", v28911);
    const v28912 = try o.lookup(&s, frame, "binding28902");
    try s.put(namespace, "FromSymbol", v28912);
    try s.put(bindings, "FromSymbol", try s.text("binding28902"));
}
fn body28903(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    _ = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v28906 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding28904", v28906);
    const v28907 = if (args.len > 1) args[1] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding28905", v28907);
    const v28908 = try s.global("Symbol");
    const v28909 = try o.call(&s, @src(), v28908, c.pi_js_undefined(), &.{});
    return c.JS_DupValue(e.context, v28909);
}
