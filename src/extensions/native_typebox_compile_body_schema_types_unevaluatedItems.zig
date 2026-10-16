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
    const namespace = try s.get(modules, "schema/types/unevaluatedItems.mjs");
    const frame = try o.frame(&s, c.pi_js_null());
    try s.put(frame, "@this", c.pi_js_undefined());
    try s.put(try s.get(graph, "frames"), "schema/types/unevaluatedItems.mjs", frame);
    const bindings = try s.object();
    try s.put(try s.get(graph, "bindings"), "schema/types/unevaluatedItems.mjs", bindings);
    const v22498 = try s.own(try ordinary.create(e, "IsUnevaluatedItems", 1, body22482, &.{ graph, frame }));
    try o.assign(&s, frame, "binding22481", v22498);
    const v22499 = try o.lookup(&s, frame, "binding22481");
    try s.put(namespace, "IsUnevaluatedItems", v22499);
    const v22500 = try o.lookup(&s, frame, "binding22481");
    try s.put(namespace, "IsUnevaluatedItems", v22500);
    try s.put(bindings, "IsUnevaluatedItems", try s.text("binding22481"));
}
fn body22482(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v22484 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding22483", v22484);
    const v22485 = try o.importValue(&s, graph, "guard/index.mjs", "Guard");
    const v22486 = try s.text("HasPropertyKey");
    const v22487 = try s.own(try js.getKey(e, v22485, v22486));
    const v22488 = try o.lookup(&s, frame, "binding22483");
    const v22489 = try s.text("unevaluatedItems");
    const v22490 = try o.call(&s, @src(), v22487, v22485, &.{ v22488, v22489 });
    const v22492 = logical22491: {
        if (!s.truthy(v22490)) break :logical22491 v22490;
        const v22493 = try o.importValue(&s, graph, "schema/types/schema.mjs", "IsSchema");
        const v22494 = try o.lookup(&s, frame, "binding22483");
        const v22495 = try s.text("unevaluatedItems");
        const v22496 = try s.own(try js.getKey(e, v22494, v22495));
        const v22497 = try o.call(&s, @src(), v22493, c.pi_js_undefined(), &.{v22496});
        break :logical22491 v22497;
    };
    return c.JS_DupValue(e.context, v22492);
}
