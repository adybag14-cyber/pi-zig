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
    const namespace = try s.get(modules, "schema/types/recursiveRef.mjs");
    const frame = try o.frame(&s, c.pi_js_null());
    try s.put(frame, "@this", c.pi_js_undefined());
    try s.put(try s.get(graph, "frames"), "schema/types/recursiveRef.mjs", frame);
    const bindings = try s.object();
    try s.put(try s.get(graph, "bindings"), "schema/types/recursiveRef.mjs", bindings);
    const v22301 = try s.own(try ordinary.create(e, "IsRecursiveRef", 1, body22283, &.{ graph, frame }));
    try o.assign(&s, frame, "binding22282", v22301);
    const v22302 = try o.lookup(&s, frame, "binding22282");
    try s.put(namespace, "IsRecursiveRef", v22302);
    const v22303 = try o.lookup(&s, frame, "binding22282");
    try s.put(namespace, "IsRecursiveRef", v22303);
    try s.put(bindings, "IsRecursiveRef", try s.text("binding22282"));
}
fn body22283(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v22285 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding22284", v22285);
    const v22286 = try o.importValue(&s, graph, "guard/index.mjs", "Guard");
    const v22287 = try s.text("HasPropertyKey");
    const v22288 = try s.own(try js.getKey(e, v22286, v22287));
    const v22289 = try o.lookup(&s, frame, "binding22284");
    const v22290 = try s.text("$recursiveRef");
    const v22291 = try s.call(v22288, v22286, &.{ v22289, v22290 });
    const v22293 = logical22292: {
        if (!s.truthy(v22291)) break :logical22292 v22291;
        const v22294 = try o.importValue(&s, graph, "guard/index.mjs", "Guard");
        const v22295 = try s.text("IsString");
        const v22296 = try s.own(try js.getKey(e, v22294, v22295));
        const v22297 = try o.lookup(&s, frame, "binding22284");
        const v22298 = try s.text("$recursiveRef");
        const v22299 = try s.own(try js.getKey(e, v22297, v22298));
        const v22300 = try s.call(v22296, v22294, &.{v22299});
        break :logical22292 v22300;
    };
    return c.JS_DupValue(e.context, v22293);
}
