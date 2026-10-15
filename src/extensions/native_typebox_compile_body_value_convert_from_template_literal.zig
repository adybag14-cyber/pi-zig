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
    const namespace = try s.get(modules, "value/convert/from_template_literal.mjs");
    const frame = try o.frame(&s, c.pi_js_null());
    try s.put(frame, "@this", c.pi_js_undefined());
    try s.put(try s.get(graph, "frames"), "value/convert/from_template_literal.mjs", frame);
    const bindings = try s.object();
    try s.put(try s.get(graph, "bindings"), "value/convert/from_template_literal.mjs", bindings);
    const v26880 = try s.own(try ordinary.create(e, "FromTemplateLiteral", 3, body26866, &.{ graph, frame }));
    try o.assign(&s, frame, "binding26865", v26880);
    const v26881 = try o.lookup(&s, frame, "binding26865");
    try s.put(namespace, "FromTemplateLiteral", v26881);
    const v26882 = try o.lookup(&s, frame, "binding26865");
    try s.put(namespace, "FromTemplateLiteral", v26882);
    try s.put(bindings, "FromTemplateLiteral", try s.text("binding26865"));
}
fn body26866(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v26870 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding26867", v26870);
    const v26871 = if (args.len > 1) args[1] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding26868", v26871);
    const v26872 = if (args.len > 2) args[2] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding26869", v26872);
    const v26873 = try o.importValue(&s, graph, "value/convert/from_type.mjs", "FromType");
    const v26874 = try o.lookup(&s, frame, "binding26867");
    const v26875 = try o.importValue(&s, graph, "type/index.mjs", "Evaluate");
    const v26876 = try o.lookup(&s, frame, "binding26868");
    const v26877 = try s.call(v26875, c.pi_js_undefined(), &.{v26876});
    const v26878 = try o.lookup(&s, frame, "binding26869");
    const v26879 = try s.call(v26873, c.pi_js_undefined(), &.{ v26874, v26877, v26878 });
    return c.JS_DupValue(e.context, v26879);
}
