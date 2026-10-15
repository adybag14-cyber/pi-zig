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
    const namespace = try s.get(modules, "schema/types/minProperties.mjs");
    const frame = try o.frame(&s, c.pi_js_null());
    try s.put(frame, "@this", c.pi_js_undefined());
    try s.put(try s.get(graph, "frames"), "schema/types/minProperties.mjs", frame);
    const bindings = try s.object();
    try s.put(try s.get(graph, "bindings"), "schema/types/minProperties.mjs", bindings);
    const v21969 = try s.own(try ordinary.create(e, "IsMinProperties", 1, body21951, &.{ graph, frame }));
    try o.assign(&s, frame, "binding21950", v21969);
    const v21970 = try o.lookup(&s, frame, "binding21950");
    try s.put(namespace, "IsMinProperties", v21970);
    const v21971 = try o.lookup(&s, frame, "binding21950");
    try s.put(namespace, "IsMinProperties", v21971);
    try s.put(bindings, "IsMinProperties", try s.text("binding21950"));
}
fn body21951(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v21953 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding21952", v21953);
    const v21954 = try o.importValue(&s, graph, "guard/index.mjs", "Guard");
    const v21955 = try s.text("HasPropertyKey");
    const v21956 = try s.own(try js.getKey(e, v21954, v21955));
    const v21957 = try o.lookup(&s, frame, "binding21952");
    const v21958 = try s.text("minProperties");
    const v21959 = try s.call(v21956, v21954, &.{ v21957, v21958 });
    const v21961 = logical21960: {
        if (!s.truthy(v21959)) break :logical21960 v21959;
        const v21962 = try o.importValue(&s, graph, "guard/index.mjs", "Guard");
        const v21963 = try s.text("IsNumber");
        const v21964 = try s.own(try js.getKey(e, v21962, v21963));
        const v21965 = try o.lookup(&s, frame, "binding21952");
        const v21966 = try s.text("minProperties");
        const v21967 = try s.own(try js.getKey(e, v21965, v21966));
        const v21968 = try s.call(v21964, v21962, &.{v21967});
        break :logical21960 v21968;
    };
    return c.JS_DupValue(e.context, v21961);
}
