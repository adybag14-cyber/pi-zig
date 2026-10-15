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
    const namespace = try s.get(modules, "schema/types/default.mjs");
    const frame = try o.frame(&s, c.pi_js_null());
    try s.put(frame, "@this", c.pi_js_undefined());
    try s.put(try s.get(graph, "frames"), "schema/types/default.mjs", frame);
    const bindings = try s.object();
    try s.put(try s.get(graph, "bindings"), "schema/types/default.mjs", bindings);
    const v21227 = try s.own(try ordinary.create(e, "IsDefault", 1, body21218, &.{ graph, frame }));
    try o.assign(&s, frame, "binding21217", v21227);
    const v21228 = try o.lookup(&s, frame, "binding21217");
    try s.put(namespace, "IsDefault", v21228);
    const v21229 = try o.lookup(&s, frame, "binding21217");
    try s.put(namespace, "IsDefault", v21229);
    try s.put(bindings, "IsDefault", try s.text("binding21217"));
}
fn body21218(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v21220 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding21219", v21220);
    const v21221 = try o.importValue(&s, graph, "guard/index.mjs", "Guard");
    const v21222 = try s.text("HasPropertyKey");
    const v21223 = try s.own(try js.getKey(e, v21221, v21222));
    const v21224 = try o.lookup(&s, frame, "binding21219");
    const v21225 = try s.text("default");
    const v21226 = try s.call(v21223, v21221, &.{ v21224, v21225 });
    return c.JS_DupValue(e.context, v21226);
}
