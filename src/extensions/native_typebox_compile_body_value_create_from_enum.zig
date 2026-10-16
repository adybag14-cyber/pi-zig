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
    const namespace = try s.get(modules, "value/create/from_enum.mjs");
    const frame = try o.frame(&s, c.pi_js_null());
    try s.put(frame, "@this", c.pi_js_undefined());
    try s.put(try s.get(graph, "frames"), "value/create/from_enum.mjs", frame);
    const bindings = try s.object();
    try s.put(try s.get(graph, "bindings"), "value/create/from_enum.mjs", bindings);
    const v28600 = try s.own(try ordinary.create(e, "FromEnum", 2, body28589, &.{ graph, frame }));
    try o.assign(&s, frame, "binding28588", v28600);
    const v28601 = try o.lookup(&s, frame, "binding28588");
    try s.put(namespace, "FromEnum", v28601);
    const v28602 = try o.lookup(&s, frame, "binding28588");
    try s.put(namespace, "FromEnum", v28602);
    try s.put(bindings, "FromEnum", try s.text("binding28588"));
}
fn body28589(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v28592 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding28590", v28592);
    const v28593 = if (args.len > 1) args[1] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding28591", v28593);
    const v28594 = try o.importValue(&s, graph, "value/create/from_type.mjs", "FromType");
    const v28595 = try o.lookup(&s, frame, "binding28590");
    const v28596 = try o.importValue(&s, graph, "type/index.mjs", "Evaluate");
    const v28597 = try o.lookup(&s, frame, "binding28591");
    const v28598 = try o.call(&s, @src(), v28596, c.pi_js_undefined(), &.{v28597});
    const v28599 = try o.call(&s, @src(), v28594, c.pi_js_undefined(), &.{ v28595, v28598 });
    return c.JS_DupValue(e.context, v28599);
}
