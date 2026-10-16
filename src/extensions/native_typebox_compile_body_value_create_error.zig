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
    const namespace = try s.get(modules, "value/create/error.mjs");
    const frame = try o.frame(&s, c.pi_js_null());
    try s.put(frame, "@this", c.pi_js_undefined());
    try s.put(try s.get(graph, "frames"), "value/create/error.mjs", frame);
    const bindings = try s.object();
    try s.put(try s.get(graph, "bindings"), "value/create/error.mjs", bindings);
    const v28400 = try s.global("Error");
    const v28401 = try o.derivedPrototype(&s, v28400);
    const v28410 = try s.own(try class.constructor(e, "CreateError", 2, v28401, constructor28402, &.{ graph, frame, v28400 }));
    try o.setPrototype(&s, v28410, v28400);
    try o.assign(&s, frame, "binding28399", v28410);
    const v28411 = try o.lookup(&s, frame, "binding28399");
    try s.put(namespace, "CreateError", v28411);
    try s.put(bindings, "CreateError", try s.text("binding28399"));
}
fn constructor28402(e: *Engine, target: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    _ = roots[0];
    const frame = try o.frame(&s, roots[1]);
    const v28405 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding28403", v28405);
    const v28406 = if (args.len > 1) args[1] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding28404", v28406);
    const v28407 = try o.lookup(&s, frame, "binding28404");
    const receiver = try o.constructWithTarget(&s, roots[2], target, &.{v28407});
    try s.put(frame, "@this", receiver);
    const v28408 = try s.text("type");
    const v28409 = try o.lookup(&s, frame, "binding28403");
    try js.setKey(e, receiver, v28408, v28409);
    return c.JS_DupValue(e.context, receiver);
}
