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
    const namespace = try s.get(modules, "schema/types/minItems.mjs");
    const frame = try o.frame(&s, c.pi_js_null());
    try s.put(frame, "@this", c.pi_js_undefined());
    try s.put(try s.get(graph, "frames"), "schema/types/minItems.mjs", frame);
    const bindings = try s.object();
    try s.put(try s.get(graph, "bindings"), "schema/types/minItems.mjs", bindings);
    const v21925 = try s.own(try ordinary.create(e, "IsMinItems", 1, body21907, &.{ graph, frame }));
    try o.assign(&s, frame, "binding21906", v21925);
    const v21926 = try o.lookup(&s, frame, "binding21906");
    try s.put(namespace, "IsMinItems", v21926);
    const v21927 = try o.lookup(&s, frame, "binding21906");
    try s.put(namespace, "IsMinItems", v21927);
    try s.put(bindings, "IsMinItems", try s.text("binding21906"));
}
fn body21907(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v21909 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding21908", v21909);
    const v21910 = try o.importValue(&s, graph, "guard/index.mjs", "Guard");
    const v21911 = try s.text("HasPropertyKey");
    const v21912 = try s.own(try js.getKey(e, v21910, v21911));
    const v21913 = try o.lookup(&s, frame, "binding21908");
    const v21914 = try s.text("minItems");
    const v21915 = try s.call(v21912, v21910, &.{ v21913, v21914 });
    const v21917 = logical21916: {
        if (!s.truthy(v21915)) break :logical21916 v21915;
        const v21918 = try o.importValue(&s, graph, "guard/index.mjs", "Guard");
        const v21919 = try s.text("IsNumber");
        const v21920 = try s.own(try js.getKey(e, v21918, v21919));
        const v21921 = try o.lookup(&s, frame, "binding21908");
        const v21922 = try s.text("minItems");
        const v21923 = try s.own(try js.getKey(e, v21921, v21922));
        const v21924 = try s.call(v21920, v21918, &.{v21923});
        break :logical21916 v21924;
    };
    return c.JS_DupValue(e.context, v21917);
}
