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
    const namespace = try s.get(modules, "value/create/from_template_literal.mjs");
    const frame = try o.frame(&s, c.pi_js_null());
    try s.put(frame, "@this", c.pi_js_undefined());
    try s.put(try s.get(graph, "frames"), "value/create/from_template_literal.mjs", frame);
    const bindings = try s.object();
    try s.put(try s.get(graph, "bindings"), "value/create/from_template_literal.mjs", bindings);
    const v28937 = try s.own(try ordinary.create(e, "FromTemplateLiteral", 2, body28914, &.{ graph, frame }));
    try o.assign(&s, frame, "binding28913", v28937);
    const v28938 = try o.lookup(&s, frame, "binding28913");
    try s.put(namespace, "FromTemplateLiteral", v28938);
    const v28939 = try o.lookup(&s, frame, "binding28913");
    try s.put(namespace, "FromTemplateLiteral", v28939);
    try s.put(bindings, "FromTemplateLiteral", try s.text("binding28913"));
}
fn body28914(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v28918 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding28915", v28918);
    const v28919 = if (args.len > 1) args[1] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding28916", v28919);
    const v28921 = try o.importValue(&s, graph, "type/engine/template_literal/index.mjs", "TemplateLiteralDecode");
    const v28922 = try o.lookup(&s, frame, "binding28916");
    const v28923 = try s.text("pattern");
    const v28924 = try s.own(try js.getKey(e, v28922, v28923));
    const v28925 = try s.call(v28921, c.pi_js_undefined(), &.{v28924});
    try o.assign(&s, frame, "binding28920", v28925);
    const v28926 = try o.importValue(&s, graph, "type/index.mjs", "IsString");
    const v28927 = try o.lookup(&s, frame, "binding28920");
    const v28928 = try s.call(v28926, c.pi_js_undefined(), &.{v28927});
    if (s.truthy(v28928)) {
        const v28929 = try o.importValue(&s, graph, "value/create/error.mjs", "CreateError");
        const v28930 = try o.lookup(&s, frame, "binding28916");
        const v28931 = try s.text("Unable to create TemplateLiteral due to infinite type expansion");
        const v28932 = try o.construct(&s, v28929, &.{ v28930, v28931 });
        _ = c.JS_Throw(e.context, c.JS_DupValue(e.context, v28932));
        return js.capture(e);
    }
    const v28933 = try o.importValue(&s, graph, "value/create/from_type.mjs", "FromType");
    const v28934 = try o.lookup(&s, frame, "binding28915");
    const v28935 = try o.lookup(&s, frame, "binding28920");
    const v28936 = try s.call(v28933, c.pi_js_undefined(), &.{ v28934, v28935 });
    return c.JS_DupValue(e.context, v28936);
}
