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
    const namespace = try s.get(modules, "value/convert/from_ref.mjs");
    const frame = try o.frame(&s, c.pi_js_null());
    try s.put(frame, "@this", c.pi_js_undefined());
    try s.put(try s.get(graph, "frames"), "value/convert/from_ref.mjs", frame);
    const bindings = try s.object();
    try s.put(try s.get(graph, "bindings"), "value/convert/from_ref.mjs", bindings);
    const v26833 = try s.own(try ordinary.create(e, "FromRef", 3, body26805, &.{ graph, frame }));
    try o.assign(&s, frame, "binding26804", v26833);
    const v26834 = try o.lookup(&s, frame, "binding26804");
    try s.put(namespace, "FromRef", v26834);
    const v26835 = try o.lookup(&s, frame, "binding26804");
    try s.put(namespace, "FromRef", v26835);
    try s.put(bindings, "FromRef", try s.text("binding26804"));
}
fn body26805(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v26809 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding26806", v26809);
    const v26810 = if (args.len > 1) args[1] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding26807", v26810);
    const v26811 = if (args.len > 2) args[2] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding26808", v26811);
    const v26812 = try o.importValue(&s, graph, "guard/index.mjs", "Guard");
    const v26813 = try s.text("HasPropertyKey");
    const v26814 = try s.own(try js.getKey(e, v26812, v26813));
    const v26815 = try o.lookup(&s, frame, "binding26806");
    const v26816 = try o.lookup(&s, frame, "binding26807");
    const v26817 = try s.text("$ref");
    const v26818 = try s.own(try js.getKey(e, v26816, v26817));
    const v26819 = try s.call(v26814, v26812, &.{ v26815, v26818 });
    const v26821 = conditional26820: {
        if (s.truthy(v26819)) {
            const v26822 = try o.importValue(&s, graph, "value/convert/from_type.mjs", "FromType");
            const v26823 = try o.lookup(&s, frame, "binding26806");
            const v26824 = try o.lookup(&s, frame, "binding26806");
            const v26825 = try o.lookup(&s, frame, "binding26807");
            const v26826 = try s.text("$ref");
            const v26827 = try s.own(try js.getKey(e, v26825, v26826));
            const v26828 = try o.propertyKey(&s, v26827);
            const v26829 = try s.own(try js.getKey(e, v26824, v26828));
            const v26830 = try o.lookup(&s, frame, "binding26808");
            const v26831 = try s.call(v26822, c.pi_js_undefined(), &.{ v26823, v26829, v26830 });
            break :conditional26820 v26831;
        } else {
            const v26832 = try o.lookup(&s, frame, "binding26808");
            break :conditional26820 v26832;
        }
    };
    return c.JS_DupValue(e.context, v26821);
}
