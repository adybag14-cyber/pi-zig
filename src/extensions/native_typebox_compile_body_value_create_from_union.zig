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
    const namespace = try s.get(modules, "value/create/from_union.mjs");
    const frame = try o.frame(&s, c.pi_js_null());
    try s.put(frame, "@this", c.pi_js_undefined());
    try s.put(try s.get(graph, "frames"), "value/create/from_union.mjs", frame);
    const bindings = try s.object();
    try s.put(try s.get(graph, "bindings"), "value/create/from_union.mjs", bindings);
    const v29282 = try s.own(try ordinary.create(e, "FromUnion", 2, body29257, &.{ graph, frame }));
    try o.assign(&s, frame, "binding29256", v29282);
    const v29283 = try o.lookup(&s, frame, "binding29256");
    try s.put(namespace, "FromUnion", v29283);
    const v29284 = try o.lookup(&s, frame, "binding29256");
    try s.put(namespace, "FromUnion", v29284);
    try s.put(bindings, "FromUnion", try s.text("binding29256"));
}
fn body29257(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v29260 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding29258", v29260);
    const v29261 = if (args.len > 1) args[1] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding29259", v29261);
    const v29262 = try o.importValue(&s, graph, "guard/index.mjs", "Guard");
    const v29263 = try s.text("IsEqual");
    const v29264 = try s.own(try js.getKey(e, v29262, v29263));
    const v29265 = try o.lookup(&s, frame, "binding29259");
    const v29266 = try s.text("anyOf");
    const v29267 = try s.own(try js.getKey(e, v29265, v29266));
    const v29268 = try s.text("length");
    const v29269 = try s.own(try js.getKey(e, v29267, v29268));
    const v29270 = try s.call(v29264, v29262, &.{ v29269, c.JS_NewFloat64(e.context, 0) });
    if (s.truthy(v29270)) {
        const v29271 = try s.global("Error");
        const v29272 = try s.text("Unable to create Union with no variants");
        const v29273 = try s.call(v29271, c.pi_js_undefined(), &.{v29272});
        _ = c.JS_Throw(e.context, c.JS_DupValue(e.context, v29273));
        return js.capture(e);
    }
    const v29274 = try o.importValue(&s, graph, "value/create/from_type.mjs", "FromType");
    const v29275 = try o.lookup(&s, frame, "binding29258");
    const v29276 = try o.lookup(&s, frame, "binding29259");
    const v29277 = try s.text("anyOf");
    const v29278 = try s.own(try js.getKey(e, v29276, v29277));
    const v29279 = try o.propertyKey(&s, c.JS_NewFloat64(e.context, 0));
    const v29280 = try s.own(try js.getKey(e, v29278, v29279));
    const v29281 = try s.call(v29274, c.pi_js_undefined(), &.{ v29275, v29280 });
    return c.JS_DupValue(e.context, v29281);
}
