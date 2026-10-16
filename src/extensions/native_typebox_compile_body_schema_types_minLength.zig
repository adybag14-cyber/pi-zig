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
    const namespace = try s.get(modules, "schema/types/minLength.mjs");
    const frame = try o.frame(&s, c.pi_js_null());
    try s.put(frame, "@this", c.pi_js_undefined());
    try s.put(try s.get(graph, "frames"), "schema/types/minLength.mjs", frame);
    const bindings = try s.object();
    try s.put(try s.get(graph, "bindings"), "schema/types/minLength.mjs", bindings);
    const v21947 = try s.own(try ordinary.create(e, "IsMinLength", 1, body21929, &.{ graph, frame }));
    try o.assign(&s, frame, "binding21928", v21947);
    const v21948 = try o.lookup(&s, frame, "binding21928");
    try s.put(namespace, "IsMinLength", v21948);
    const v21949 = try o.lookup(&s, frame, "binding21928");
    try s.put(namespace, "IsMinLength", v21949);
    try s.put(bindings, "IsMinLength", try s.text("binding21928"));
}
fn body21929(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v21931 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding21930", v21931);
    const v21932 = try o.importValue(&s, graph, "guard/index.mjs", "Guard");
    const v21933 = try s.text("HasPropertyKey");
    const v21934 = try s.own(try js.getKey(e, v21932, v21933));
    const v21935 = try o.lookup(&s, frame, "binding21930");
    const v21936 = try s.text("minLength");
    const v21937 = try o.call(&s, @src(), v21934, v21932, &.{ v21935, v21936 });
    const v21939 = logical21938: {
        if (!s.truthy(v21937)) break :logical21938 v21937;
        const v21940 = try o.importValue(&s, graph, "guard/index.mjs", "Guard");
        const v21941 = try s.text("IsNumber");
        const v21942 = try s.own(try js.getKey(e, v21940, v21941));
        const v21943 = try o.lookup(&s, frame, "binding21930");
        const v21944 = try s.text("minLength");
        const v21945 = try s.own(try js.getKey(e, v21943, v21944));
        const v21946 = try o.call(&s, @src(), v21942, v21940, &.{v21945});
        break :logical21938 v21946;
    };
    return c.JS_DupValue(e.context, v21939);
}
