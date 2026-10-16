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
    const namespace = try s.get(modules, "value/clean/from_ref.mjs");
    const frame = try o.frame(&s, c.pi_js_null());
    try s.put(frame, "@this", c.pi_js_undefined());
    try s.put(try s.get(graph, "frames"), "value/clean/from_ref.mjs", frame);
    const bindings = try s.object();
    try s.put(try s.get(graph, "bindings"), "value/clean/from_ref.mjs", bindings);
    const v23740 = try s.own(try ordinary.create(e, "FromRef", 3, body23712, &.{ graph, frame }));
    try o.assign(&s, frame, "binding23711", v23740);
    const v23741 = try o.lookup(&s, frame, "binding23711");
    try s.put(namespace, "FromRef", v23741);
    const v23742 = try o.lookup(&s, frame, "binding23711");
    try s.put(namespace, "FromRef", v23742);
    try s.put(bindings, "FromRef", try s.text("binding23711"));
}
fn body23712(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v23716 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding23713", v23716);
    const v23717 = if (args.len > 1) args[1] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding23714", v23717);
    const v23718 = if (args.len > 2) args[2] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding23715", v23718);
    const v23719 = try o.importValue(&s, graph, "guard/index.mjs", "Guard");
    const v23720 = try s.text("HasPropertyKey");
    const v23721 = try s.own(try js.getKey(e, v23719, v23720));
    const v23722 = try o.lookup(&s, frame, "binding23713");
    const v23723 = try o.lookup(&s, frame, "binding23714");
    const v23724 = try s.text("$ref");
    const v23725 = try s.own(try js.getKey(e, v23723, v23724));
    const v23726 = try o.call(&s, @src(), v23721, v23719, &.{ v23722, v23725 });
    const v23728 = conditional23727: {
        if (s.truthy(v23726)) {
            const v23729 = try o.importValue(&s, graph, "value/clean/from_type.mjs", "FromType");
            const v23730 = try o.lookup(&s, frame, "binding23713");
            const v23731 = try o.lookup(&s, frame, "binding23713");
            const v23732 = try o.lookup(&s, frame, "binding23714");
            const v23733 = try s.text("$ref");
            const v23734 = try s.own(try js.getKey(e, v23732, v23733));
            const v23735 = try o.propertyKey(&s, v23734);
            const v23736 = try s.own(try js.getKey(e, v23731, v23735));
            const v23737 = try o.lookup(&s, frame, "binding23715");
            const v23738 = try o.call(&s, @src(), v23729, c.pi_js_undefined(), &.{ v23730, v23736, v23737 });
            break :conditional23727 v23738;
        } else {
            const v23739 = try o.lookup(&s, frame, "binding23715");
            break :conditional23727 v23739;
        }
    };
    return c.JS_DupValue(e.context, v23728);
}
