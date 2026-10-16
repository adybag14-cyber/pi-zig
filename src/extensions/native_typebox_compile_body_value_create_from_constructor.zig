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
    const namespace = try s.get(modules, "value/create/from_constructor.mjs");
    const frame = try o.frame(&s, c.pi_js_null());
    try s.put(frame, "@this", c.pi_js_undefined());
    try s.put(try s.get(graph, "frames"), "value/create/from_constructor.mjs", frame);
    const bindings = try s.object();
    try s.put(try s.get(graph, "bindings"), "value/create/from_constructor.mjs", bindings);
    const v28524 = try s.own(try ordinary.create(e, "FromConstructor", 2, body28503, &.{ graph, frame }));
    try o.assign(&s, frame, "binding28502", v28524);
    const v28525 = try o.lookup(&s, frame, "binding28502");
    try s.put(namespace, "FromConstructor", v28525);
    const v28526 = try o.lookup(&s, frame, "binding28502");
    try s.put(namespace, "FromConstructor", v28526);
    try s.put(bindings, "FromConstructor", try s.text("binding28502"));
}
fn constructor28517(e: *Engine, target: c.JSValue, _: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    _ = roots[0];
    const frame = try o.frame(&s, roots[1]);
    const receiver = try s.own(try class.object(e, target));
    try s.put(frame, "@this", receiver);
    const v28518 = try s.global("Object");
    const v28519 = try s.text("assign");
    const v28520 = try s.own(try js.getKey(e, v28518, v28519));
    const v28521 = try o.lookup(&s, frame, "binding28509");
    const v28522 = try s.call(v28520, v28518, &.{ receiver, v28521 });
    _ = v28522;
    return c.JS_DupValue(e.context, receiver);
}
fn body28503(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v28507 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding28504", v28507);
    const v28508 = if (args.len > 1) args[1] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding28505", v28508);
    const v28510 = try o.importValue(&s, graph, "value/create/from_type.mjs", "FromType");
    const v28511 = try o.lookup(&s, frame, "binding28504");
    const v28512 = try o.lookup(&s, frame, "binding28505");
    const v28513 = try s.text("instanceType");
    const v28514 = try s.own(try js.getKey(e, v28512, v28513));
    const v28515 = try s.call(v28510, c.pi_js_undefined(), &.{ v28511, v28514 });
    try o.assign(&s, frame, "binding28509", v28515);
    const v28516 = try s.object();
    const v28523 = try s.own(try class.constructor(e, "", 0, v28516, constructor28517, &.{ graph, frame, c.pi_js_undefined() }));
    return c.JS_DupValue(e.context, v28523);
}
