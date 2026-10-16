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
    const namespace = try s.get(modules, "value/default/from_array.mjs");
    const frame = try o.frame(&s, c.pi_js_null());
    try s.put(frame, "@this", c.pi_js_undefined());
    try s.put(try s.get(graph, "frames"), "value/default/from_array.mjs", frame);
    const bindings = try s.object();
    try s.put(try s.get(graph, "bindings"), "value/default/from_array.mjs", bindings);
    const v29386 = try s.own(try ordinary.create(e, "FromArray", 3, body29349, &.{ graph, frame }));
    try o.assign(&s, frame, "binding29348", v29386);
    const v29387 = try o.lookup(&s, frame, "binding29348");
    try s.put(namespace, "FromArray", v29387);
    const v29388 = try o.lookup(&s, frame, "binding29348");
    try s.put(namespace, "FromArray", v29388);
    try s.put(bindings, "FromArray", try s.text("binding29348"));
}
fn body29349(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v29353 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding29350", v29353);
    const v29354 = if (args.len > 1) args[1] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding29351", v29354);
    const v29355 = if (args.len > 2) args[2] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding29352", v29355);
    const v29356 = try o.importValue(&s, graph, "guard/index.mjs", "Guard");
    const v29357 = try s.text("IsArray");
    const v29358 = try s.own(try js.getKey(e, v29356, v29357));
    const v29359 = try o.lookup(&s, frame, "binding29352");
    const v29360 = try s.call(v29358, v29356, &.{v29359});
    if (s.truthy(o.boolean(&s, !s.truthy(v29360)))) {
        const v29361 = try o.lookup(&s, frame, "binding29352");
        return c.JS_DupValue(e.context, v29361);
    }
    try o.assign(&s, frame, "binding29362", c.JS_NewFloat64(e.context, 0));
    loop29363: while (true) {
        const v29365 = try o.lookup(&s, frame, "binding29362");
        const v29366 = try o.lookup(&s, frame, "binding29352");
        const v29367 = try s.text("length");
        const v29368 = try s.own(try js.getKey(e, v29366, v29367));
        const v29369 = try s.own(try e.checked(c.JS_PiBinaryOperator(e.context, 4, v29365, v29368)));
        if (!s.truthy(v29369)) break :loop29363;
        {
            const v29370 = try o.lookup(&s, frame, "binding29352");
            const v29371 = try o.lookup(&s, frame, "binding29362");
            const v29372 = try o.propertyKey(&s, v29371);
            const v29373 = try o.importValue(&s, graph, "value/default/from_type.mjs", "FromType");
            const v29374 = try o.lookup(&s, frame, "binding29350");
            const v29375 = try o.lookup(&s, frame, "binding29351");
            const v29376 = try s.text("items");
            const v29377 = try s.own(try js.getKey(e, v29375, v29376));
            const v29378 = try o.lookup(&s, frame, "binding29352");
            const v29379 = try o.lookup(&s, frame, "binding29362");
            const v29380 = try o.propertyKey(&s, v29379);
            const v29381 = try s.own(try js.getKey(e, v29378, v29380));
            const v29382 = try s.call(v29373, c.pi_js_undefined(), &.{ v29374, v29377, v29381 });
            try js.setKey(e, v29370, v29372, v29382);
        }
        const v29383 = try o.lookup(&s, frame, "binding29362");
        const v29384 = try s.own(try e.checked(c.JS_PiIncrement(e.context, v29383)));
        try o.assign(&s, frame, "binding29362", v29384);
    }
    const v29385 = try o.lookup(&s, frame, "binding29352");
    return c.JS_DupValue(e.context, v29385);
}
