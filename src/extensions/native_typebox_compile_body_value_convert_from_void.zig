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
    const namespace = try s.get(modules, "value/convert/from_void.mjs");
    const frame = try o.frame(&s, c.pi_js_null());
    try s.put(frame, "@this", c.pi_js_undefined());
    try s.put(try s.get(graph, "frames"), "value/convert/from_void.mjs", frame);
    const bindings = try s.object();
    try s.put(try s.get(graph, "bindings"), "value/convert/from_void.mjs", bindings);
    const v27304 = try s.own(try ordinary.create(e, "FromVoid", 3, body27282, &.{ graph, frame }));
    try o.assign(&s, frame, "binding27281", v27304);
    const v27305 = try o.lookup(&s, frame, "binding27281");
    try s.put(namespace, "FromVoid", v27305);
    const v27306 = try o.lookup(&s, frame, "binding27281");
    try s.put(namespace, "FromVoid", v27306);
    try s.put(bindings, "FromVoid", try s.text("binding27281"));
}
fn body27282(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v27287 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding27283", v27287);
    const v27288 = if (args.len > 1) args[1] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding27284", v27288);
    const v27289 = if (args.len > 2) args[2] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding27285", v27289);
    const v27291 = try o.importValue(&s, graph, "value/convert/try/index.mjs", "Try");
    const v27292 = try s.text("TryUndefined");
    const v27293 = try s.own(try js.getKey(e, v27291, v27292));
    const v27294 = try o.lookup(&s, frame, "binding27285");
    const v27295 = try o.call(&s, @src(), v27293, v27291, &.{v27294});
    try o.assign(&s, frame, "binding27290", v27295);
    const v27296 = try o.importValue(&s, graph, "value/convert/try/index.mjs", "Try");
    const v27297 = try s.text("IsOk");
    const v27298 = try s.own(try js.getKey(e, v27296, v27297));
    const v27299 = try o.lookup(&s, frame, "binding27290");
    const v27300 = try o.call(&s, @src(), v27298, v27296, &.{v27299});
    const v27302 = conditional27301: {
        if (s.truthy(v27300)) {
            _ = c.JS_NewFloat64(e.context, 0);
            break :conditional27301 c.pi_js_undefined();
        } else {
            const v27303 = try o.lookup(&s, frame, "binding27285");
            break :conditional27301 v27303;
        }
    };
    return c.JS_DupValue(e.context, v27302);
}
