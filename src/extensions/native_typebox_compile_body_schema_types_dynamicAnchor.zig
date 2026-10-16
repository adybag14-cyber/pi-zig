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
    const namespace = try s.get(modules, "schema/types/dynamicAnchor.mjs");
    const frame = try o.frame(&s, c.pi_js_null());
    try s.put(frame, "@this", c.pi_js_undefined());
    try s.put(try s.get(graph, "frames"), "schema/types/dynamicAnchor.mjs", frame);
    const bindings = try s.object();
    try s.put(try s.get(graph, "bindings"), "schema/types/dynamicAnchor.mjs", bindings);
    const v21458 = try s.own(try ordinary.create(e, "IsDynamicAnchor", 1, body21440, &.{ graph, frame }));
    try o.assign(&s, frame, "binding21439", v21458);
    const v21459 = try o.lookup(&s, frame, "binding21439");
    try s.put(namespace, "IsDynamicAnchor", v21459);
    const v21460 = try o.lookup(&s, frame, "binding21439");
    try s.put(namespace, "IsDynamicAnchor", v21460);
    try s.put(bindings, "IsDynamicAnchor", try s.text("binding21439"));
}
fn body21440(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v21442 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding21441", v21442);
    const v21443 = try o.importValue(&s, graph, "guard/index.mjs", "Guard");
    const v21444 = try s.text("HasPropertyKey");
    const v21445 = try s.own(try js.getKey(e, v21443, v21444));
    const v21446 = try o.lookup(&s, frame, "binding21441");
    const v21447 = try s.text("$dynamicAnchor");
    const v21448 = try o.call(&s, @src(), v21445, v21443, &.{ v21446, v21447 });
    const v21450 = logical21449: {
        if (!s.truthy(v21448)) break :logical21449 v21448;
        const v21451 = try o.importValue(&s, graph, "guard/index.mjs", "Guard");
        const v21452 = try s.text("IsString");
        const v21453 = try s.own(try js.getKey(e, v21451, v21452));
        const v21454 = try o.lookup(&s, frame, "binding21441");
        const v21455 = try s.text("$dynamicAnchor");
        const v21456 = try s.own(try js.getKey(e, v21454, v21455));
        const v21457 = try o.call(&s, @src(), v21453, v21451, &.{v21456});
        break :logical21449 v21457;
    };
    return c.JS_DupValue(e.context, v21450);
}
