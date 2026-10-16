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
    const namespace = try s.get(modules, "value/convert/from_null.mjs");
    const frame = try o.frame(&s, c.pi_js_null());
    try s.put(frame, "@this", c.pi_js_undefined());
    try s.put(try s.get(graph, "frames"), "value/convert/from_null.mjs", frame);
    const bindings = try s.object();
    try s.put(try s.get(graph, "bindings"), "value/convert/from_null.mjs", bindings);
    const v26551 = try s.own(try ordinary.create(e, "FromNull", 3, body26526, &.{ graph, frame }));
    try o.assign(&s, frame, "binding26525", v26551);
    const v26552 = try o.lookup(&s, frame, "binding26525");
    try s.put(namespace, "FromNull", v26552);
    const v26553 = try o.lookup(&s, frame, "binding26525");
    try s.put(namespace, "FromNull", v26553);
    try s.put(bindings, "FromNull", try s.text("binding26525"));
}
fn body26526(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v26531 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding26527", v26531);
    const v26532 = if (args.len > 1) args[1] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding26528", v26532);
    const v26533 = if (args.len > 2) args[2] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding26529", v26533);
    const v26535 = try o.importValue(&s, graph, "value/convert/try/index.mjs", "Try");
    const v26536 = try s.text("TryNull");
    const v26537 = try s.own(try js.getKey(e, v26535, v26536));
    const v26538 = try o.lookup(&s, frame, "binding26529");
    const v26539 = try s.call(v26537, v26535, &.{v26538});
    try o.assign(&s, frame, "binding26534", v26539);
    const v26540 = try o.importValue(&s, graph, "value/convert/try/index.mjs", "Try");
    const v26541 = try s.text("IsOk");
    const v26542 = try s.own(try js.getKey(e, v26540, v26541));
    const v26543 = try o.lookup(&s, frame, "binding26534");
    const v26544 = try s.call(v26542, v26540, &.{v26543});
    const v26546 = conditional26545: {
        if (s.truthy(v26544)) {
            const v26547 = try o.lookup(&s, frame, "binding26534");
            const v26548 = try s.text("value");
            const v26549 = try s.own(try js.getKey(e, v26547, v26548));
            break :conditional26545 v26549;
        } else {
            const v26550 = try o.lookup(&s, frame, "binding26529");
            break :conditional26545 v26550;
        }
    };
    return c.JS_DupValue(e.context, v26546);
}
