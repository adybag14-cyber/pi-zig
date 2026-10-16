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
    const namespace = try s.get(modules, "schema/types/exclusiveMaximum.mjs");
    const frame = try o.frame(&s, c.pi_js_null());
    try s.put(frame, "@this", c.pi_js_undefined());
    try s.put(try s.get(graph, "frames"), "schema/types/exclusiveMaximum.mjs", frame);
    const bindings = try s.object();
    try s.put(try s.get(graph, "bindings"), "schema/types/exclusiveMaximum.mjs", bindings);
    const v21553 = try s.own(try ordinary.create(e, "IsExclusiveMaximum", 1, body21526, &.{ graph, frame }));
    try o.assign(&s, frame, "binding21525", v21553);
    const v21554 = try o.lookup(&s, frame, "binding21525");
    try s.put(namespace, "IsExclusiveMaximum", v21554);
    const v21555 = try o.lookup(&s, frame, "binding21525");
    try s.put(namespace, "IsExclusiveMaximum", v21555);
    try s.put(bindings, "IsExclusiveMaximum", try s.text("binding21525"));
}
fn body21526(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v21528 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding21527", v21528);
    const v21529 = try o.importValue(&s, graph, "guard/index.mjs", "Guard");
    const v21530 = try s.text("HasPropertyKey");
    const v21531 = try s.own(try js.getKey(e, v21529, v21530));
    const v21532 = try o.lookup(&s, frame, "binding21527");
    const v21533 = try s.text("exclusiveMaximum");
    const v21534 = try o.call(&s, @src(), v21531, v21529, &.{ v21532, v21533 });
    const v21536 = logical21535: {
        if (!s.truthy(v21534)) break :logical21535 v21534;
        const v21537 = try o.importValue(&s, graph, "guard/index.mjs", "Guard");
        const v21538 = try s.text("IsNumber");
        const v21539 = try s.own(try js.getKey(e, v21537, v21538));
        const v21540 = try o.lookup(&s, frame, "binding21527");
        const v21541 = try s.text("exclusiveMaximum");
        const v21542 = try s.own(try js.getKey(e, v21540, v21541));
        const v21543 = try o.call(&s, @src(), v21539, v21537, &.{v21542});
        const v21545 = logical21544: {
            if (s.truthy(v21543)) break :logical21544 v21543;
            const v21546 = try o.importValue(&s, graph, "guard/index.mjs", "Guard");
            const v21547 = try s.text("IsBigInt");
            const v21548 = try s.own(try js.getKey(e, v21546, v21547));
            const v21549 = try o.lookup(&s, frame, "binding21527");
            const v21550 = try s.text("exclusiveMaximum");
            const v21551 = try s.own(try js.getKey(e, v21549, v21550));
            const v21552 = try o.call(&s, @src(), v21548, v21546, &.{v21551});
            break :logical21544 v21552;
        };
        break :logical21535 v21545;
    };
    return c.JS_DupValue(e.context, v21536);
}
