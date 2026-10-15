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
    const namespace = try s.get(modules, "value/create/from_never.mjs");
    const frame = try o.frame(&s, c.pi_js_null());
    try s.put(frame, "@this", c.pi_js_undefined());
    try s.put(try s.get(graph, "frames"), "value/create/from_never.mjs", frame);
    const bindings = try s.object();
    try s.put(try s.get(graph, "bindings"), "value/create/from_never.mjs", bindings);
    const v28705 = try s.own(try ordinary.create(e, "FromNever", 2, body28696, &.{ graph, frame }));
    try o.assign(&s, frame, "binding28695", v28705);
    const v28706 = try o.lookup(&s, frame, "binding28695");
    try s.put(namespace, "FromNever", v28706);
    const v28707 = try o.lookup(&s, frame, "binding28695");
    try s.put(namespace, "FromNever", v28707);
    try s.put(bindings, "FromNever", try s.text("binding28695"));
}
fn body28696(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v28699 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding28697", v28699);
    const v28700 = if (args.len > 1) args[1] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding28698", v28700);
    const v28701 = try o.importValue(&s, graph, "value/create/error.mjs", "CreateError");
    const v28702 = try o.lookup(&s, frame, "binding28698");
    const v28703 = try s.text("Cannot create TNever types");
    const v28704 = try o.construct(&s, v28701, &.{ v28702, v28703 });
    _ = c.JS_Throw(e.context, c.JS_DupValue(e.context, v28704));
    return js.capture(e);
}
