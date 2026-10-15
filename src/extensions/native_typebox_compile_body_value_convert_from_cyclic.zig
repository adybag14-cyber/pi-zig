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
    const namespace = try s.get(modules, "value/convert/from_cyclic.mjs");
    const frame = try o.frame(&s, c.pi_js_null());
    try s.put(frame, "@this", c.pi_js_undefined());
    try s.put(try s.get(graph, "frames"), "value/convert/from_cyclic.mjs", frame);
    const bindings = try s.object();
    try s.put(try s.get(graph, "bindings"), "value/convert/from_cyclic.mjs", bindings);
    const v26226 = try s.own(try ordinary.create(e, "FromCyclic", 3, body26206, &.{ graph, frame }));
    try o.assign(&s, frame, "binding26205", v26226);
    const v26227 = try o.lookup(&s, frame, "binding26205");
    try s.put(namespace, "FromCyclic", v26227);
    const v26228 = try o.lookup(&s, frame, "binding26205");
    try s.put(namespace, "FromCyclic", v26228);
    try s.put(bindings, "FromCyclic", try s.text("binding26205"));
}
fn body26206(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v26210 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding26207", v26210);
    const v26211 = if (args.len > 1) args[1] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding26208", v26211);
    const v26212 = if (args.len > 2) args[2] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding26209", v26212);
    const v26213 = try o.importValue(&s, graph, "value/convert/from_type.mjs", "FromType");
    const v26214 = try s.object();
    const v26215 = try o.lookup(&s, frame, "binding26207");
    try js.spreadInto(e, v26214, v26215);
    const v26216 = try o.lookup(&s, frame, "binding26208");
    const v26217 = try s.text("$defs");
    const v26218 = try s.own(try js.getKey(e, v26216, v26217));
    try js.spreadInto(e, v26214, v26218);
    const v26219 = try o.importValue(&s, graph, "type/index.mjs", "Ref");
    const v26220 = try o.lookup(&s, frame, "binding26208");
    const v26221 = try s.text("$ref");
    const v26222 = try s.own(try js.getKey(e, v26220, v26221));
    const v26223 = try s.call(v26219, c.pi_js_undefined(), &.{v26222});
    const v26224 = try o.lookup(&s, frame, "binding26209");
    const v26225 = try s.call(v26213, c.pi_js_undefined(), &.{ v26214, v26223, v26224 });
    return c.JS_DupValue(e.context, v26225);
}
