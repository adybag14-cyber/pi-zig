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
    const namespace = try s.get(modules, "value/default/from_intersect.mjs");
    const frame = try o.frame(&s, c.pi_js_null());
    try s.put(frame, "@this", c.pi_js_undefined());
    try s.put(try s.get(graph, "frames"), "value/default/from_intersect.mjs", frame);
    const bindings = try s.object();
    try s.put(try s.get(graph, "bindings"), "value/default/from_intersect.mjs", bindings);
    const v29470 = try s.own(try ordinary.create(e, "FromIntersect", 3, body29447, &.{ graph, frame }));
    try o.assign(&s, frame, "binding29446", v29470);
    const v29471 = try o.lookup(&s, frame, "binding29446");
    try s.put(namespace, "FromIntersect", v29471);
    const v29472 = try o.lookup(&s, frame, "binding29446");
    try s.put(namespace, "FromIntersect", v29472);
    try s.put(bindings, "FromIntersect", try s.text("binding29446"));
}
fn body29447(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v29453 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding29448", v29453);
    const v29454 = if (args.len > 1) args[1] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding29449", v29454);
    const v29455 = if (args.len > 2) args[2] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding29450", v29455);
    const v29458 = try o.importValue(&s, graph, "type/index.mjs", "Instantiate");
    const v29459 = try o.lookup(&s, frame, "binding29448");
    const v29460 = try o.lookup(&s, frame, "binding29449");
    const v29461 = try s.call(v29458, c.pi_js_undefined(), &.{ v29459, v29460 });
    try o.assign(&s, frame, "binding29456", v29461);
    const v29462 = try o.importValue(&s, graph, "type/index.mjs", "Evaluate");
    const v29463 = try o.lookup(&s, frame, "binding29456");
    const v29464 = try s.call(v29462, c.pi_js_undefined(), &.{v29463});
    try o.assign(&s, frame, "binding29457", v29464);
    const v29465 = try o.importValue(&s, graph, "value/default/from_type.mjs", "FromType");
    const v29466 = try o.lookup(&s, frame, "binding29448");
    const v29467 = try o.lookup(&s, frame, "binding29457");
    const v29468 = try o.lookup(&s, frame, "binding29450");
    const v29469 = try s.call(v29465, c.pi_js_undefined(), &.{ v29466, v29467, v29468 });
    return c.JS_DupValue(e.context, v29469);
}
