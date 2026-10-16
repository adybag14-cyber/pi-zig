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
    const namespace = try s.get(modules, "value/create/from_default.mjs");
    const frame = try o.frame(&s, c.pi_js_null());
    try s.put(frame, "@this", c.pi_js_undefined());
    try s.put(try s.get(graph, "frames"), "value/create/from_default.mjs", frame);
    const bindings = try s.object();
    try s.put(try s.get(graph, "bindings"), "value/create/from_default.mjs", bindings);
    const v28585 = try s.own(try ordinary.create(e, "FromDefault", 2, body28549, &.{ graph, frame }));
    try o.assign(&s, frame, "binding28548", v28585);
    const v28586 = try o.lookup(&s, frame, "binding28548");
    try s.put(namespace, "FromDefault", v28586);
    const v28587 = try o.lookup(&s, frame, "binding28548");
    try s.put(namespace, "FromDefault", v28587);
    try s.put(bindings, "FromDefault", try s.text("binding28548"));
}
fn body28549(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v28552 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding28550", v28552);
    const v28553 = if (args.len > 1) args[1] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding28551", v28553);
    const v28554 = try o.importValue(&s, graph, "guard/index.mjs", "Guard");
    const v28555 = try s.text("IsFunction");
    const v28556 = try s.own(try js.getKey(e, v28554, v28555));
    const v28557 = try o.lookup(&s, frame, "binding28551");
    const v28558 = try s.text("default");
    const v28559 = try s.own(try js.getKey(e, v28557, v28558));
    const v28560 = try s.call(v28556, v28554, &.{v28559});
    const v28562 = conditional28561: {
        if (s.truthy(v28560)) {
            const v28563 = try o.lookup(&s, frame, "binding28551");
            const v28564 = try s.text("default");
            const v28565 = try s.own(try js.getKey(e, v28563, v28564));
            const v28566 = try o.lookup(&s, frame, "binding28551");
            const v28567 = try s.call(v28565, v28563, &.{v28566});
            break :conditional28561 v28567;
        } else {
            const v28568 = try o.importValue(&s, graph, "guard/index.mjs", "Guard");
            const v28569 = try s.text("IsObject");
            const v28570 = try s.own(try js.getKey(e, v28568, v28569));
            const v28571 = try o.lookup(&s, frame, "binding28551");
            const v28572 = try s.text("default");
            const v28573 = try s.own(try js.getKey(e, v28571, v28572));
            const v28574 = try s.call(v28570, v28568, &.{v28573});
            const v28576 = conditional28575: {
                if (s.truthy(v28574)) {
                    const v28577 = try o.importValue(&s, graph, "value/clone/index.mjs", "Clone");
                    const v28578 = try o.lookup(&s, frame, "binding28551");
                    const v28579 = try s.text("default");
                    const v28580 = try s.own(try js.getKey(e, v28578, v28579));
                    const v28581 = try s.call(v28577, c.pi_js_undefined(), &.{v28580});
                    break :conditional28575 v28581;
                } else {
                    const v28582 = try o.lookup(&s, frame, "binding28551");
                    const v28583 = try s.text("default");
                    const v28584 = try s.own(try js.getKey(e, v28582, v28583));
                    break :conditional28575 v28584;
                }
            };
            break :conditional28561 v28576;
        }
    };
    return c.JS_DupValue(e.context, v28562);
}
