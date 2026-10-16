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
    const namespace = try s.get(modules, "schema/types/else.mjs");
    const frame = try o.frame(&s, c.pi_js_null());
    try s.put(frame, "@this", c.pi_js_undefined());
    try s.put(try s.get(graph, "frames"), "schema/types/else.mjs", frame);
    const bindings = try s.object();
    try s.put(try s.get(graph, "bindings"), "schema/types/else.mjs", bindings);
    const v21500 = try s.own(try ordinary.create(e, "IsElse", 1, body21484, &.{ graph, frame }));
    try o.assign(&s, frame, "binding21483", v21500);
    const v21501 = try o.lookup(&s, frame, "binding21483");
    try s.put(namespace, "IsElse", v21501);
    const v21502 = try o.lookup(&s, frame, "binding21483");
    try s.put(namespace, "IsElse", v21502);
    try s.put(bindings, "IsElse", try s.text("binding21483"));
}
fn body21484(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v21486 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding21485", v21486);
    const v21487 = try o.importValue(&s, graph, "guard/index.mjs", "Guard");
    const v21488 = try s.text("HasPropertyKey");
    const v21489 = try s.own(try js.getKey(e, v21487, v21488));
    const v21490 = try o.lookup(&s, frame, "binding21485");
    const v21491 = try s.text("else");
    const v21492 = try s.call(v21489, v21487, &.{ v21490, v21491 });
    const v21494 = logical21493: {
        if (!s.truthy(v21492)) break :logical21493 v21492;
        const v21495 = try o.importValue(&s, graph, "schema/types/schema.mjs", "IsSchema");
        const v21496 = try o.lookup(&s, frame, "binding21485");
        const v21497 = try s.text("else");
        const v21498 = try s.own(try js.getKey(e, v21496, v21497));
        const v21499 = try s.call(v21495, c.pi_js_undefined(), &.{v21498});
        break :logical21493 v21499;
    };
    return c.JS_DupValue(e.context, v21494);
}
