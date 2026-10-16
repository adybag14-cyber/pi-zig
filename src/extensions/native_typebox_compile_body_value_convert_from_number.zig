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
    const namespace = try s.get(modules, "value/convert/from_number.mjs");
    const frame = try o.frame(&s, c.pi_js_null());
    try s.put(frame, "@this", c.pi_js_undefined());
    try s.put(try s.get(graph, "frames"), "value/convert/from_number.mjs", frame);
    const bindings = try s.object();
    try s.put(try s.get(graph, "bindings"), "value/convert/from_number.mjs", bindings);
    const v26580 = try s.own(try ordinary.create(e, "FromNumber", 3, body26555, &.{ graph, frame }));
    try o.assign(&s, frame, "binding26554", v26580);
    const v26581 = try o.lookup(&s, frame, "binding26554");
    try s.put(namespace, "FromNumber", v26581);
    const v26582 = try o.lookup(&s, frame, "binding26554");
    try s.put(namespace, "FromNumber", v26582);
    try s.put(bindings, "FromNumber", try s.text("binding26554"));
}
fn body26555(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v26560 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding26556", v26560);
    const v26561 = if (args.len > 1) args[1] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding26557", v26561);
    const v26562 = if (args.len > 2) args[2] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding26558", v26562);
    const v26564 = try o.importValue(&s, graph, "value/convert/try/index.mjs", "Try");
    const v26565 = try s.text("TryNumber");
    const v26566 = try s.own(try js.getKey(e, v26564, v26565));
    const v26567 = try o.lookup(&s, frame, "binding26558");
    const v26568 = try s.call(v26566, v26564, &.{v26567});
    try o.assign(&s, frame, "binding26563", v26568);
    const v26569 = try o.importValue(&s, graph, "value/convert/try/index.mjs", "Try");
    const v26570 = try s.text("IsOk");
    const v26571 = try s.own(try js.getKey(e, v26569, v26570));
    const v26572 = try o.lookup(&s, frame, "binding26563");
    const v26573 = try s.call(v26571, v26569, &.{v26572});
    const v26575 = conditional26574: {
        if (s.truthy(v26573)) {
            const v26576 = try o.lookup(&s, frame, "binding26563");
            const v26577 = try s.text("value");
            const v26578 = try s.own(try js.getKey(e, v26576, v26577));
            break :conditional26574 v26578;
        } else {
            const v26579 = try o.lookup(&s, frame, "binding26558");
            break :conditional26574 v26579;
        }
    };
    return c.JS_DupValue(e.context, v26575);
}
