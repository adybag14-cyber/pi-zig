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
    const namespace = try s.get(modules, "schema/engine/_regexp.mjs");
    const frame = try o.frame(&s, c.pi_js_null());
    try s.put(frame, "@this", c.pi_js_undefined());
    try s.put(try s.get(graph, "frames"), "schema/engine/_regexp.mjs", frame);
    const bindings = try s.object();
    try s.put(try s.get(graph, "bindings"), "schema/engine/_regexp.mjs", bindings);
    const v4792 = try s.own(try ordinary.create(e, "UnicodeRegExp", 1, body4785, &.{ graph, frame }));
    try o.assign(&s, frame, "binding4784", v4792);
    const v4793 = try o.lookup(&s, frame, "binding4784");
    try s.put(namespace, "UnicodeRegExp", v4793);
    const v4794 = try o.lookup(&s, frame, "binding4784");
    try s.put(namespace, "UnicodeRegExp", v4794);
    try s.put(bindings, "UnicodeRegExp", try s.text("binding4784"));
}
fn body4785(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    _ = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v4787 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding4786", v4787);
    const v4788 = try s.global("RegExp");
    const v4789 = try o.lookup(&s, frame, "binding4786");
    const v4790 = try s.text("u");
    const v4791 = try o.construct(&s, v4788, &.{ v4789, v4790 });
    return c.JS_DupValue(e.context, v4791);
}
