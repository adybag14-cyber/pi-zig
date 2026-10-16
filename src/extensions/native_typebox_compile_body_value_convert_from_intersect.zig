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
    const namespace = try s.get(modules, "value/convert/from_intersect.mjs");
    const frame = try o.frame(&s, c.pi_js_null());
    try s.put(frame, "@this", c.pi_js_undefined());
    try s.put(try s.get(graph, "frames"), "value/convert/from_intersect.mjs", frame);
    const bindings = try s.object();
    try s.put(try s.get(graph, "bindings"), "value/convert/from_intersect.mjs", bindings);
    const v26304 = try s.own(try ordinary.create(e, "FromIntersect", 3, body26281, &.{ graph, frame }));
    try o.assign(&s, frame, "binding26280", v26304);
    const v26305 = try o.lookup(&s, frame, "binding26280");
    try s.put(namespace, "FromIntersect", v26305);
    const v26306 = try o.lookup(&s, frame, "binding26280");
    try s.put(namespace, "FromIntersect", v26306);
    try s.put(bindings, "FromIntersect", try s.text("binding26280"));
}
fn body26281(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v26287 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding26282", v26287);
    const v26288 = if (args.len > 1) args[1] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding26283", v26288);
    const v26289 = if (args.len > 2) args[2] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding26284", v26289);
    const v26292 = try o.importValue(&s, graph, "type/index.mjs", "Instantiate");
    const v26293 = try o.lookup(&s, frame, "binding26282");
    const v26294 = try o.lookup(&s, frame, "binding26283");
    const v26295 = try o.call(&s, @src(), v26292, c.pi_js_undefined(), &.{ v26293, v26294 });
    try o.assign(&s, frame, "binding26290", v26295);
    const v26296 = try o.importValue(&s, graph, "type/index.mjs", "Evaluate");
    const v26297 = try o.lookup(&s, frame, "binding26290");
    const v26298 = try o.call(&s, @src(), v26296, c.pi_js_undefined(), &.{v26297});
    try o.assign(&s, frame, "binding26291", v26298);
    const v26299 = try o.importValue(&s, graph, "value/convert/from_type.mjs", "FromType");
    const v26300 = try o.lookup(&s, frame, "binding26282");
    const v26301 = try o.lookup(&s, frame, "binding26291");
    const v26302 = try o.lookup(&s, frame, "binding26284");
    const v26303 = try o.call(&s, @src(), v26299, c.pi_js_undefined(), &.{ v26300, v26301, v26302 });
    return c.JS_DupValue(e.context, v26303);
}
