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
    const namespace = try s.get(modules, "value/create/from_undefined.mjs");
    const frame = try o.frame(&s, c.pi_js_null());
    try s.put(frame, "@this", c.pi_js_undefined());
    try s.put(try s.get(graph, "frames"), "value/create/from_undefined.mjs", frame);
    const bindings = try s.object();
    try s.put(try s.get(graph, "bindings"), "value/create/from_undefined.mjs", bindings);
    const v29253 = try s.own(try ordinary.create(e, "FromUndefined", 2, body29248, &.{ graph, frame }));
    try o.assign(&s, frame, "binding29247", v29253);
    const v29254 = try o.lookup(&s, frame, "binding29247");
    try s.put(namespace, "FromUndefined", v29254);
    const v29255 = try o.lookup(&s, frame, "binding29247");
    try s.put(namespace, "FromUndefined", v29255);
    try s.put(bindings, "FromUndefined", try s.text("binding29247"));
}
fn body29248(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    _ = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v29251 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding29249", v29251);
    const v29252 = if (args.len > 1) args[1] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding29250", v29252);
    return c.JS_DupValue(e.context, c.pi_js_undefined());
}
