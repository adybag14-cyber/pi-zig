//! Direct native bodies from pinned typebox@1.3.27. Source-only pending qualification.
const js = @import("native_js_values.zig");
const Scope = @import("native_sdk_prompt_scope.zig").Scope;
const o = @import("native_typebox_compile_ops.zig");
const ordinary = @import("native_legacy_function.zig");
const class = @import("native_class.zig");
const sdk = @import("native_sdk.zig");
const c = js.c;
const Engine = js.Engine;
pub fn prepare(e: *Engine, graph: c.JSValue) !void {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const modules = try s.get(graph, "modules");
    const namespace = try s.get(modules, "value/default/from_cyclic.mjs");
    const frame = try o.frame(&s, c.pi_js_null());
    try s.put(frame, "@this", c.pi_js_undefined());
    try s.put(try s.get(graph, "frames"), "value/default/from_cyclic.mjs", frame);
    const bindings = try s.object();
    try s.put(try s.get(graph, "bindings"), "value/default/from_cyclic.mjs", bindings);
    const v29410 = try s.own(try ordinary.create(e, "FromCyclic", 3, body29390, &.{ graph, frame }));
    try o.assign(&s, frame, "binding29389", v29410);
    const v29411 = try o.lookup(&s, frame, "binding29389");
    try s.put(namespace, "FromCyclic", v29411);
    const v29412 = try o.lookup(&s, frame, "binding29389");
    try s.put(namespace, "FromCyclic", v29412);
    try s.put(bindings, "FromCyclic", try s.text("binding29389"));
}
fn body29390(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v29394 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding29391", v29394);
    const v29395 = if (args.len > 1) args[1] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding29392", v29395);
    const v29396 = if (args.len > 2) args[2] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding29393", v29396);
    const v29397 = try o.importValue(&s, graph, "value/default/from_type.mjs", "FromType");
    const v29398 = try s.object();
    const v29399 = try o.lookup(&s, frame, "binding29391");
    try js.spreadInto(e, v29398, v29399);
    const v29400 = try o.lookup(&s, frame, "binding29392");
    const v29401 = try s.text("$defs");
    const v29402 = try s.own(try js.getKey(e, v29400, v29401));
    try js.spreadInto(e, v29398, v29402);
    const v29403 = try o.importValue(&s, graph, "type/index.mjs", "Ref");
    const v29404 = try o.lookup(&s, frame, "binding29392");
    const v29405 = try s.text("$ref");
    const v29406 = try s.own(try js.getKey(e, v29404, v29405));
    const v29407 = try s.call(v29403, c.pi_js_undefined(), &.{v29406});
    const v29408 = try o.lookup(&s, frame, "binding29393");
    const v29409 = try s.call(v29397, c.pi_js_undefined(), &.{ v29398, v29407, v29408 });
    return c.JS_DupValue(e.context, v29409);
}
