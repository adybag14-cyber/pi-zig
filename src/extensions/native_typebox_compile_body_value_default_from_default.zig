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
    const namespace = try s.get(modules, "value/default/from_default.mjs");
    const frame = try o.frame(&s, c.pi_js_null());
    try s.put(frame, "@this", c.pi_js_undefined());
    try s.put(try s.get(graph, "frames"), "value/default/from_default.mjs", frame);
    const bindings = try s.object();
    try s.put(try s.get(graph, "bindings"), "value/default/from_default.mjs", bindings);
    const v29443 = try s.own(try ordinary.create(e, "FromDefault", 2, body29414, &.{ graph, frame }));
    try o.assign(&s, frame, "binding29413", v29443);
    const v29444 = try o.lookup(&s, frame, "binding29413");
    try s.put(namespace, "FromDefault", v29444);
    const v29445 = try o.lookup(&s, frame, "binding29413");
    try s.put(namespace, "FromDefault", v29445);
    try s.put(bindings, "FromDefault", try s.text("binding29413"));
}
fn body29414(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v29417 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding29415", v29417);
    const v29418 = if (args.len > 1) args[1] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding29416", v29418);
    const v29419 = try o.importValue(&s, graph, "guard/index.mjs", "Guard");
    const v29420 = try s.text("IsUndefined");
    const v29421 = try s.own(try js.getKey(e, v29419, v29420));
    const v29422 = try o.lookup(&s, frame, "binding29416");
    const v29423 = try s.call(v29421, v29419, &.{v29422});
    if (s.truthy(o.boolean(&s, !s.truthy(v29423)))) {
        const v29424 = try o.lookup(&s, frame, "binding29416");
        return c.JS_DupValue(e.context, v29424);
    }
    const v29425 = try o.importValue(&s, graph, "guard/index.mjs", "Guard");
    const v29426 = try s.text("IsFunction");
    const v29427 = try s.own(try js.getKey(e, v29425, v29426));
    const v29428 = try o.lookup(&s, frame, "binding29415");
    const v29429 = try s.text("default");
    const v29430 = try s.own(try js.getKey(e, v29428, v29429));
    const v29431 = try s.call(v29427, v29425, &.{v29430});
    const v29433 = conditional29432: {
        if (s.truthy(v29431)) {
            const v29434 = try o.lookup(&s, frame, "binding29415");
            const v29435 = try s.text("default");
            const v29436 = try s.own(try js.getKey(e, v29434, v29435));
            const v29437 = try s.call(v29436, v29434, &.{});
            break :conditional29432 v29437;
        } else {
            const v29438 = try o.importValue(&s, graph, "value/clone/index.mjs", "Clone");
            const v29439 = try o.lookup(&s, frame, "binding29415");
            const v29440 = try s.text("default");
            const v29441 = try s.own(try js.getKey(e, v29439, v29440));
            const v29442 = try s.call(v29438, c.pi_js_undefined(), &.{v29441});
            break :conditional29432 v29442;
        }
    };
    return c.JS_DupValue(e.context, v29433);
}
