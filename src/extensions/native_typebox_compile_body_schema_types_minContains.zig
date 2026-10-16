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
    const namespace = try s.get(modules, "schema/types/minContains.mjs");
    const frame = try o.frame(&s, c.pi_js_null());
    try s.put(frame, "@this", c.pi_js_undefined());
    try s.put(try s.get(graph, "frames"), "schema/types/minContains.mjs", frame);
    const bindings = try s.object();
    try s.put(try s.get(graph, "bindings"), "schema/types/minContains.mjs", bindings);
    const v21872 = try s.own(try ordinary.create(e, "IsMinContains", 1, body21854, &.{ graph, frame }));
    try o.assign(&s, frame, "binding21853", v21872);
    const v21873 = try o.lookup(&s, frame, "binding21853");
    try s.put(namespace, "IsMinContains", v21873);
    const v21874 = try o.lookup(&s, frame, "binding21853");
    try s.put(namespace, "IsMinContains", v21874);
    try s.put(bindings, "IsMinContains", try s.text("binding21853"));
}
fn body21854(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v21856 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding21855", v21856);
    const v21857 = try o.importValue(&s, graph, "guard/index.mjs", "Guard");
    const v21858 = try s.text("HasPropertyKey");
    const v21859 = try s.own(try js.getKey(e, v21857, v21858));
    const v21860 = try o.lookup(&s, frame, "binding21855");
    const v21861 = try s.text("minContains");
    const v21862 = try s.call(v21859, v21857, &.{ v21860, v21861 });
    const v21864 = logical21863: {
        if (!s.truthy(v21862)) break :logical21863 v21862;
        const v21865 = try o.importValue(&s, graph, "guard/index.mjs", "Guard");
        const v21866 = try s.text("IsNumber");
        const v21867 = try s.own(try js.getKey(e, v21865, v21866));
        const v21868 = try o.lookup(&s, frame, "binding21855");
        const v21869 = try s.text("minContains");
        const v21870 = try s.own(try js.getKey(e, v21868, v21869));
        const v21871 = try s.call(v21867, v21865, &.{v21870});
        break :logical21863 v21871;
    };
    return c.JS_DupValue(e.context, v21864);
}
