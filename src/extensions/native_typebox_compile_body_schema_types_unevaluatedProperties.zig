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
    const namespace = try s.get(modules, "schema/types/unevaluatedProperties.mjs");
    const frame = try o.frame(&s, c.pi_js_null());
    try s.put(frame, "@this", c.pi_js_undefined());
    try s.put(try s.get(graph, "frames"), "schema/types/unevaluatedProperties.mjs", frame);
    const bindings = try s.object();
    try s.put(try s.get(graph, "bindings"), "schema/types/unevaluatedProperties.mjs", bindings);
    const v22518 = try s.own(try ordinary.create(e, "IsUnevaluatedProperties", 1, body22502, &.{ graph, frame }));
    try o.assign(&s, frame, "binding22501", v22518);
    const v22519 = try o.lookup(&s, frame, "binding22501");
    try s.put(namespace, "IsUnevaluatedProperties", v22519);
    const v22520 = try o.lookup(&s, frame, "binding22501");
    try s.put(namespace, "IsUnevaluatedProperties", v22520);
    try s.put(bindings, "IsUnevaluatedProperties", try s.text("binding22501"));
}
fn body22502(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v22504 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding22503", v22504);
    const v22505 = try o.importValue(&s, graph, "guard/index.mjs", "Guard");
    const v22506 = try s.text("HasPropertyKey");
    const v22507 = try s.own(try js.getKey(e, v22505, v22506));
    const v22508 = try o.lookup(&s, frame, "binding22503");
    const v22509 = try s.text("unevaluatedProperties");
    const v22510 = try o.call(&s, @src(), v22507, v22505, &.{ v22508, v22509 });
    const v22512 = logical22511: {
        if (!s.truthy(v22510)) break :logical22511 v22510;
        const v22513 = try o.importValue(&s, graph, "schema/types/schema.mjs", "IsSchema");
        const v22514 = try o.lookup(&s, frame, "binding22503");
        const v22515 = try s.text("unevaluatedProperties");
        const v22516 = try s.own(try js.getKey(e, v22514, v22515));
        const v22517 = try o.call(&s, @src(), v22513, c.pi_js_undefined(), &.{v22516});
        break :logical22511 v22517;
    };
    return c.JS_DupValue(e.context, v22512);
}
