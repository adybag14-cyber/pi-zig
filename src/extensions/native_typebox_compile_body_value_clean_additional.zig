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
    const namespace = try s.get(modules, "value/clean/additional.mjs");
    const frame = try o.frame(&s, c.pi_js_null());
    try s.put(frame, "@this", c.pi_js_undefined());
    try s.put(try s.get(graph, "frames"), "value/clean/additional.mjs", frame);
    const bindings = try s.object();
    try s.put(try s.get(graph, "bindings"), "value/clean/additional.mjs", bindings);
    const v23300 = try s.own(try ordinary.create(e, "GetAdditionalProperties", 1, body23283, &.{ graph, frame }));
    try o.assign(&s, frame, "binding23282", v23300);
    const v23301 = try o.lookup(&s, frame, "binding23282");
    try s.put(namespace, "GetAdditionalProperties", v23301);
    const v23302 = try o.lookup(&s, frame, "binding23282");
    try s.put(namespace, "GetAdditionalProperties", v23302);
    try s.put(bindings, "GetAdditionalProperties", try s.text("binding23282"));
}
fn body23283(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v23286 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding23284", v23286);
    const v23288 = try o.importValue(&s, graph, "guard/index.mjs", "Guard");
    const v23289 = try s.text("HasPropertyKey");
    const v23290 = try s.own(try js.getKey(e, v23288, v23289));
    const v23291 = try o.lookup(&s, frame, "binding23284");
    const v23292 = try s.text("additionalProperties");
    const v23293 = try s.call(v23290, v23288, &.{ v23291, v23292 });
    const v23295 = conditional23294: {
        if (s.truthy(v23293)) {
            const v23296 = try o.lookup(&s, frame, "binding23284");
            const v23297 = try s.text("additionalProperties");
            const v23298 = try s.own(try js.getKey(e, v23296, v23297));
            break :conditional23294 v23298;
        } else {
            break :conditional23294 c.pi_js_undefined();
        }
    };
    try o.assign(&s, frame, "binding23287", v23295);
    const v23299 = try o.lookup(&s, frame, "binding23287");
    return c.JS_DupValue(e.context, v23299);
}
