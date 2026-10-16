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
    const namespace = try s.get(modules, "schema/types/const.mjs");
    const frame = try o.frame(&s, c.pi_js_null());
    try s.put(frame, "@this", c.pi_js_undefined());
    try s.put(try s.get(graph, "frames"), "schema/types/const.mjs", frame);
    const bindings = try s.object();
    try s.put(try s.get(graph, "bindings"), "schema/types/const.mjs", bindings);
    const v21194 = try s.own(try ordinary.create(e, "IsConst", 1, body21185, &.{ graph, frame }));
    try o.assign(&s, frame, "binding21184", v21194);
    const v21195 = try o.lookup(&s, frame, "binding21184");
    try s.put(namespace, "IsConst", v21195);
    const v21196 = try o.lookup(&s, frame, "binding21184");
    try s.put(namespace, "IsConst", v21196);
    try s.put(bindings, "IsConst", try s.text("binding21184"));
}
fn body21185(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v21187 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding21186", v21187);
    const v21188 = try o.importValue(&s, graph, "guard/index.mjs", "Guard");
    const v21189 = try s.text("HasPropertyKey");
    const v21190 = try s.own(try js.getKey(e, v21188, v21189));
    const v21191 = try o.lookup(&s, frame, "binding21186");
    const v21192 = try s.text("const");
    const v21193 = try s.call(v21190, v21188, &.{ v21191, v21192 });
    return c.JS_DupValue(e.context, v21193);
}
