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
    const namespace = try s.get(modules, "value/clean/from_cyclic.mjs");
    const frame = try o.frame(&s, c.pi_js_null());
    try s.put(frame, "@this", c.pi_js_undefined());
    try s.put(try s.get(graph, "frames"), "value/clean/from_cyclic.mjs", frame);
    const bindings = try s.object();
    try s.put(try s.get(graph, "bindings"), "value/clean/from_cyclic.mjs", bindings);
    const v23425 = try s.own(try ordinary.create(e, "FromCyclic", 3, body23405, &.{ graph, frame }));
    try o.assign(&s, frame, "binding23404", v23425);
    const v23426 = try o.lookup(&s, frame, "binding23404");
    try s.put(namespace, "FromCyclic", v23426);
    const v23427 = try o.lookup(&s, frame, "binding23404");
    try s.put(namespace, "FromCyclic", v23427);
    try s.put(bindings, "FromCyclic", try s.text("binding23404"));
}
fn body23405(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v23409 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding23406", v23409);
    const v23410 = if (args.len > 1) args[1] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding23407", v23410);
    const v23411 = if (args.len > 2) args[2] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding23408", v23411);
    const v23412 = try o.importValue(&s, graph, "value/clean/from_type.mjs", "FromType");
    const v23413 = try s.object();
    const v23414 = try o.lookup(&s, frame, "binding23406");
    try js.spreadInto(e, v23413, v23414);
    const v23415 = try o.lookup(&s, frame, "binding23407");
    const v23416 = try s.text("$defs");
    const v23417 = try s.own(try js.getKey(e, v23415, v23416));
    try js.spreadInto(e, v23413, v23417);
    const v23418 = try o.importValue(&s, graph, "type/index.mjs", "Ref");
    const v23419 = try o.lookup(&s, frame, "binding23407");
    const v23420 = try s.text("$ref");
    const v23421 = try s.own(try js.getKey(e, v23419, v23420));
    const v23422 = try s.call(v23418, c.pi_js_undefined(), &.{v23421});
    const v23423 = try o.lookup(&s, frame, "binding23408");
    const v23424 = try s.call(v23412, c.pi_js_undefined(), &.{ v23413, v23422, v23423 });
    return c.JS_DupValue(e.context, v23424);
}
