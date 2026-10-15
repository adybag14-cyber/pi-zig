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
    const namespace = try s.get(modules, "schema/types/uniqueItems.mjs");
    const frame = try o.frame(&s, c.pi_js_null());
    try s.put(frame, "@this", c.pi_js_undefined());
    try s.put(try s.get(graph, "frames"), "schema/types/uniqueItems.mjs", frame);
    const bindings = try s.object();
    try s.put(try s.get(graph, "bindings"), "schema/types/uniqueItems.mjs", bindings);
    const v22540 = try s.own(try ordinary.create(e, "IsUniqueItems", 1, body22522, &.{ graph, frame }));
    try o.assign(&s, frame, "binding22521", v22540);
    const v22541 = try o.lookup(&s, frame, "binding22521");
    try s.put(namespace, "IsUniqueItems", v22541);
    const v22542 = try o.lookup(&s, frame, "binding22521");
    try s.put(namespace, "IsUniqueItems", v22542);
    try s.put(bindings, "IsUniqueItems", try s.text("binding22521"));
}
fn body22522(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v22524 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding22523", v22524);
    const v22525 = try o.importValue(&s, graph, "guard/index.mjs", "Guard");
    const v22526 = try s.text("HasPropertyKey");
    const v22527 = try s.own(try js.getKey(e, v22525, v22526));
    const v22528 = try o.lookup(&s, frame, "binding22523");
    const v22529 = try s.text("uniqueItems");
    const v22530 = try s.call(v22527, v22525, &.{ v22528, v22529 });
    const v22532 = logical22531: {
        if (!s.truthy(v22530)) break :logical22531 v22530;
        const v22533 = try o.importValue(&s, graph, "guard/index.mjs", "Guard");
        const v22534 = try s.text("IsBoolean");
        const v22535 = try s.own(try js.getKey(e, v22533, v22534));
        const v22536 = try o.lookup(&s, frame, "binding22523");
        const v22537 = try s.text("uniqueItems");
        const v22538 = try s.own(try js.getKey(e, v22536, v22537));
        const v22539 = try s.call(v22535, v22533, &.{v22538});
        break :logical22531 v22539;
    };
    return c.JS_DupValue(e.context, v22532);
}
