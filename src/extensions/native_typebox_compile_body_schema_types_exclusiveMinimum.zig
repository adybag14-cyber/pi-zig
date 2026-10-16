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
    const namespace = try s.get(modules, "schema/types/exclusiveMinimum.mjs");
    const frame = try o.frame(&s, c.pi_js_null());
    try s.put(frame, "@this", c.pi_js_undefined());
    try s.put(try s.get(graph, "frames"), "schema/types/exclusiveMinimum.mjs", frame);
    const bindings = try s.object();
    try s.put(try s.get(graph, "bindings"), "schema/types/exclusiveMinimum.mjs", bindings);
    const v21584 = try s.own(try ordinary.create(e, "IsExclusiveMinimum", 1, body21557, &.{ graph, frame }));
    try o.assign(&s, frame, "binding21556", v21584);
    const v21585 = try o.lookup(&s, frame, "binding21556");
    try s.put(namespace, "IsExclusiveMinimum", v21585);
    const v21586 = try o.lookup(&s, frame, "binding21556");
    try s.put(namespace, "IsExclusiveMinimum", v21586);
    try s.put(bindings, "IsExclusiveMinimum", try s.text("binding21556"));
}
fn body21557(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v21559 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding21558", v21559);
    const v21560 = try o.importValue(&s, graph, "guard/index.mjs", "Guard");
    const v21561 = try s.text("HasPropertyKey");
    const v21562 = try s.own(try js.getKey(e, v21560, v21561));
    const v21563 = try o.lookup(&s, frame, "binding21558");
    const v21564 = try s.text("exclusiveMinimum");
    const v21565 = try s.call(v21562, v21560, &.{ v21563, v21564 });
    const v21567 = logical21566: {
        if (!s.truthy(v21565)) break :logical21566 v21565;
        const v21568 = try o.importValue(&s, graph, "guard/index.mjs", "Guard");
        const v21569 = try s.text("IsNumber");
        const v21570 = try s.own(try js.getKey(e, v21568, v21569));
        const v21571 = try o.lookup(&s, frame, "binding21558");
        const v21572 = try s.text("exclusiveMinimum");
        const v21573 = try s.own(try js.getKey(e, v21571, v21572));
        const v21574 = try s.call(v21570, v21568, &.{v21573});
        const v21576 = logical21575: {
            if (s.truthy(v21574)) break :logical21575 v21574;
            const v21577 = try o.importValue(&s, graph, "guard/index.mjs", "Guard");
            const v21578 = try s.text("IsBigInt");
            const v21579 = try s.own(try js.getKey(e, v21577, v21578));
            const v21580 = try o.lookup(&s, frame, "binding21558");
            const v21581 = try s.text("exclusiveMinimum");
            const v21582 = try s.own(try js.getKey(e, v21580, v21581));
            const v21583 = try s.call(v21579, v21577, &.{v21582});
            break :logical21575 v21583;
        };
        break :logical21566 v21576;
    };
    return c.JS_DupValue(e.context, v21567);
}
