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
    const namespace = try s.get(modules, "value/create/from_cyclic.mjs");
    const frame = try o.frame(&s, c.pi_js_null());
    try s.put(frame, "@this", c.pi_js_undefined());
    try s.put(try s.get(graph, "frames"), "value/create/from_cyclic.mjs", frame);
    const bindings = try s.object();
    try s.put(try s.get(graph, "bindings"), "value/create/from_cyclic.mjs", bindings);
    const v28545 = try s.own(try ordinary.create(e, "FromCyclic", 2, body28528, &.{ graph, frame }));
    try o.assign(&s, frame, "binding28527", v28545);
    const v28546 = try o.lookup(&s, frame, "binding28527");
    try s.put(namespace, "FromCyclic", v28546);
    const v28547 = try o.lookup(&s, frame, "binding28527");
    try s.put(namespace, "FromCyclic", v28547);
    try s.put(bindings, "FromCyclic", try s.text("binding28527"));
}
fn body28528(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v28531 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding28529", v28531);
    const v28532 = if (args.len > 1) args[1] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding28530", v28532);
    const v28533 = try o.importValue(&s, graph, "value/create/from_type.mjs", "FromType");
    const v28534 = try s.object();
    const v28535 = try o.lookup(&s, frame, "binding28529");
    try js.spreadInto(e, v28534, v28535);
    const v28536 = try o.lookup(&s, frame, "binding28530");
    const v28537 = try s.text("$defs");
    const v28538 = try s.own(try js.getKey(e, v28536, v28537));
    try js.spreadInto(e, v28534, v28538);
    const v28539 = try o.importValue(&s, graph, "type/index.mjs", "Ref");
    const v28540 = try o.lookup(&s, frame, "binding28530");
    const v28541 = try s.text("$ref");
    const v28542 = try s.own(try js.getKey(e, v28540, v28541));
    const v28543 = try s.call(v28539, c.pi_js_undefined(), &.{v28542});
    const v28544 = try s.call(v28533, c.pi_js_undefined(), &.{ v28534, v28543 });
    return c.JS_DupValue(e.context, v28544);
}
