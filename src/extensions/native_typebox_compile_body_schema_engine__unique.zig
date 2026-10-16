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
    const namespace = try s.get(modules, "schema/engine/_unique.mjs");
    const frame = try o.frame(&s, c.pi_js_null());
    try s.put(frame, "@this", c.pi_js_undefined());
    try s.put(try s.get(graph, "frames"), "schema/engine/_unique.mjs", frame);
    const bindings = try s.object();
    try s.put(try s.get(graph, "bindings"), "schema/engine/_unique.mjs", bindings);
    const v5851 = try s.own(try ordinary.create(e, "Unique", 0, body5843, &.{ graph, frame }));
    try o.assign(&s, frame, "binding5842", v5851);
    const v5852 = try o.lookup(&s, frame, "binding5842");
    try s.put(namespace, "Unique", v5852);
    try o.assign(&s, frame, "binding5841", c.JS_NewFloat64(e.context, 0));
    const v5853 = try o.lookup(&s, frame, "binding5842");
    try s.put(namespace, "Unique", v5853);
    try s.put(bindings, "Unique", try s.text("binding5842"));
}
fn body5843(e: *Engine, receiver: c.JSValue, _: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    _ = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v5844 = try s.text("var_");
    const v5845 = try o.lookup(&s, frame, "binding5841");
    const v5846 = try s.own(try e.checked(c.JS_PiIncrement(e.context, v5845)));
    try o.assign(&s, frame, "binding5841", v5846);
    const v5847 = try s.stringify(v5845);
    const v5848 = try s.concat(v5844, v5847);
    const v5849 = try s.text("");
    const v5850 = try s.concat(v5848, v5849);
    return c.JS_DupValue(e.context, v5850);
}
