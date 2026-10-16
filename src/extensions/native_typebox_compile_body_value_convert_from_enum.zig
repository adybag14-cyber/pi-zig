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
    const namespace = try s.get(modules, "value/convert/from_enum.mjs");
    const frame = try o.frame(&s, c.pi_js_null());
    try s.put(frame, "@this", c.pi_js_undefined());
    try s.put(try s.get(graph, "frames"), "value/convert/from_enum.mjs", frame);
    const bindings = try s.object();
    try s.put(try s.get(graph, "bindings"), "value/convert/from_enum.mjs", bindings);
    const v26244 = try s.own(try ordinary.create(e, "FromEnum", 3, body26230, &.{ graph, frame }));
    try o.assign(&s, frame, "binding26229", v26244);
    const v26245 = try o.lookup(&s, frame, "binding26229");
    try s.put(namespace, "FromEnum", v26245);
    const v26246 = try o.lookup(&s, frame, "binding26229");
    try s.put(namespace, "FromEnum", v26246);
    try s.put(bindings, "FromEnum", try s.text("binding26229"));
}
fn body26230(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v26234 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding26231", v26234);
    const v26235 = if (args.len > 1) args[1] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding26232", v26235);
    const v26236 = if (args.len > 2) args[2] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding26233", v26236);
    const v26237 = try o.importValue(&s, graph, "value/convert/from_type.mjs", "FromType");
    const v26238 = try o.lookup(&s, frame, "binding26231");
    const v26239 = try o.importValue(&s, graph, "type/index.mjs", "Evaluate");
    const v26240 = try o.lookup(&s, frame, "binding26232");
    const v26241 = try s.call(v26239, c.pi_js_undefined(), &.{v26240});
    const v26242 = try o.lookup(&s, frame, "binding26233");
    const v26243 = try s.call(v26237, c.pi_js_undefined(), &.{ v26238, v26241, v26242 });
    return c.JS_DupValue(e.context, v26243);
}
