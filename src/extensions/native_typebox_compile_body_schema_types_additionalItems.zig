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
    const namespace = try s.get(modules, "schema/types/additionalItems.mjs");
    const frame = try o.frame(&s, c.pi_js_null());
    try s.put(frame, "@this", c.pi_js_undefined());
    try s.put(try s.get(graph, "frames"), "schema/types/additionalItems.mjs", frame);
    const bindings = try s.object();
    try s.put(try s.get(graph, "bindings"), "schema/types/additionalItems.mjs", bindings);
    const v21063 = try s.own(try ordinary.create(e, "IsAdditionalItems", 1, body21047, &.{ graph, frame }));
    try o.assign(&s, frame, "binding21046", v21063);
    const v21064 = try o.lookup(&s, frame, "binding21046");
    try s.put(namespace, "IsAdditionalItems", v21064);
    const v21065 = try o.lookup(&s, frame, "binding21046");
    try s.put(namespace, "IsAdditionalItems", v21065);
    try s.put(bindings, "IsAdditionalItems", try s.text("binding21046"));
}
fn body21047(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v21049 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding21048", v21049);
    const v21050 = try o.importValue(&s, graph, "guard/index.mjs", "Guard");
    const v21051 = try s.text("HasPropertyKey");
    const v21052 = try s.own(try js.getKey(e, v21050, v21051));
    const v21053 = try o.lookup(&s, frame, "binding21048");
    const v21054 = try s.text("additionalItems");
    const v21055 = try s.call(v21052, v21050, &.{ v21053, v21054 });
    const v21057 = logical21056: {
        if (!s.truthy(v21055)) break :logical21056 v21055;
        const v21058 = try o.importValue(&s, graph, "schema/types/schema.mjs", "IsSchema");
        const v21059 = try o.lookup(&s, frame, "binding21048");
        const v21060 = try s.text("additionalItems");
        const v21061 = try s.own(try js.getKey(e, v21059, v21060));
        const v21062 = try s.call(v21058, c.pi_js_undefined(), &.{v21061});
        break :logical21056 v21062;
    };
    return c.JS_DupValue(e.context, v21057);
}
