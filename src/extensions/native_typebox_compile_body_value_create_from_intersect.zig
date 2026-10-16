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
    const namespace = try s.get(modules, "value/create/from_intersect.mjs");
    const frame = try o.frame(&s, c.pi_js_null());
    try s.put(frame, "@this", c.pi_js_undefined());
    try s.put(try s.get(graph, "frames"), "value/create/from_intersect.mjs", frame);
    const bindings = try s.object();
    try s.put(try s.get(graph, "bindings"), "value/create/from_intersect.mjs", bindings);
    const v28680 = try s.own(try ordinary.create(e, "FromIntersect", 2, body28660, &.{ graph, frame }));
    try o.assign(&s, frame, "binding28659", v28680);
    const v28681 = try o.lookup(&s, frame, "binding28659");
    try s.put(namespace, "FromIntersect", v28681);
    const v28682 = try o.lookup(&s, frame, "binding28659");
    try s.put(namespace, "FromIntersect", v28682);
    try s.put(bindings, "FromIntersect", try s.text("binding28659"));
}
fn body28660(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v28665 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding28661", v28665);
    const v28666 = if (args.len > 1) args[1] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding28662", v28666);
    const v28669 = try o.importValue(&s, graph, "type/index.mjs", "Instantiate");
    const v28670 = try o.lookup(&s, frame, "binding28661");
    const v28671 = try o.lookup(&s, frame, "binding28662");
    const v28672 = try s.call(v28669, c.pi_js_undefined(), &.{ v28670, v28671 });
    try o.assign(&s, frame, "binding28667", v28672);
    const v28673 = try o.importValue(&s, graph, "type/index.mjs", "Evaluate");
    const v28674 = try o.lookup(&s, frame, "binding28667");
    const v28675 = try s.call(v28673, c.pi_js_undefined(), &.{v28674});
    try o.assign(&s, frame, "binding28668", v28675);
    const v28676 = try o.importValue(&s, graph, "value/create/from_type.mjs", "FromType");
    const v28677 = try o.lookup(&s, frame, "binding28661");
    const v28678 = try o.lookup(&s, frame, "binding28668");
    const v28679 = try s.call(v28676, c.pi_js_undefined(), &.{ v28677, v28678 });
    return c.JS_DupValue(e.context, v28679);
}
