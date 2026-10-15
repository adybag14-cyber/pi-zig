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
    const namespace = try s.get(modules, "schema/types/contains.mjs");
    const frame = try o.frame(&s, c.pi_js_null());
    try s.put(frame, "@this", c.pi_js_undefined());
    try s.put(try s.get(graph, "frames"), "schema/types/contains.mjs", frame);
    const bindings = try s.object();
    try s.put(try s.get(graph, "bindings"), "schema/types/contains.mjs", bindings);
    const v21214 = try s.own(try ordinary.create(e, "IsContains", 1, body21198, &.{ graph, frame }));
    try o.assign(&s, frame, "binding21197", v21214);
    const v21215 = try o.lookup(&s, frame, "binding21197");
    try s.put(namespace, "IsContains", v21215);
    const v21216 = try o.lookup(&s, frame, "binding21197");
    try s.put(namespace, "IsContains", v21216);
    try s.put(bindings, "IsContains", try s.text("binding21197"));
}
fn body21198(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v21200 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding21199", v21200);
    const v21201 = try o.importValue(&s, graph, "guard/index.mjs", "Guard");
    const v21202 = try s.text("HasPropertyKey");
    const v21203 = try s.own(try js.getKey(e, v21201, v21202));
    const v21204 = try o.lookup(&s, frame, "binding21199");
    const v21205 = try s.text("contains");
    const v21206 = try s.call(v21203, v21201, &.{ v21204, v21205 });
    const v21208 = logical21207: {
        if (!s.truthy(v21206)) break :logical21207 v21206;
        const v21209 = try o.importValue(&s, graph, "schema/types/schema.mjs", "IsSchema");
        const v21210 = try o.lookup(&s, frame, "binding21199");
        const v21211 = try s.text("contains");
        const v21212 = try s.own(try js.getKey(e, v21210, v21211));
        const v21213 = try s.call(v21209, c.pi_js_undefined(), &.{v21212});
        break :logical21207 v21213;
    };
    return c.JS_DupValue(e.context, v21208);
}
