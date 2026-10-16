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
    const namespace = try s.get(modules, "schema/types/then.mjs");
    const frame = try o.frame(&s, c.pi_js_null());
    try s.put(frame, "@this", c.pi_js_undefined());
    try s.put(try s.get(graph, "frames"), "schema/types/then.mjs", frame);
    const bindings = try s.object();
    try s.put(try s.get(graph, "bindings"), "schema/types/then.mjs", bindings);
    const v22429 = try s.own(try ordinary.create(e, "IsThen", 1, body22413, &.{ graph, frame }));
    try o.assign(&s, frame, "binding22412", v22429);
    const v22430 = try o.lookup(&s, frame, "binding22412");
    try s.put(namespace, "IsThen", v22430);
    const v22431 = try o.lookup(&s, frame, "binding22412");
    try s.put(namespace, "IsThen", v22431);
    try s.put(bindings, "IsThen", try s.text("binding22412"));
}
fn body22413(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v22415 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding22414", v22415);
    const v22416 = try o.importValue(&s, graph, "guard/index.mjs", "Guard");
    const v22417 = try s.text("HasPropertyKey");
    const v22418 = try s.own(try js.getKey(e, v22416, v22417));
    const v22419 = try o.lookup(&s, frame, "binding22414");
    const v22420 = try s.text("then");
    const v22421 = try s.call(v22418, v22416, &.{ v22419, v22420 });
    const v22423 = logical22422: {
        if (!s.truthy(v22421)) break :logical22422 v22421;
        const v22424 = try o.importValue(&s, graph, "schema/types/schema.mjs", "IsSchema");
        const v22425 = try o.lookup(&s, frame, "binding22414");
        const v22426 = try s.text("then");
        const v22427 = try s.own(try js.getKey(e, v22425, v22426));
        const v22428 = try s.call(v22424, c.pi_js_undefined(), &.{v22427});
        break :logical22422 v22428;
    };
    return c.JS_DupValue(e.context, v22423);
}
