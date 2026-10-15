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
    const namespace = try s.get(modules, "schema/types/not.mjs");
    const frame = try o.frame(&s, c.pi_js_null());
    try s.put(frame, "@this", c.pi_js_undefined());
    try s.put(try s.get(graph, "frames"), "schema/types/not.mjs", frame);
    const bindings = try s.object();
    try s.put(try s.get(graph, "bindings"), "schema/types/not.mjs", bindings);
    const v22020 = try s.own(try ordinary.create(e, "IsNot", 1, body22004, &.{ graph, frame }));
    try o.assign(&s, frame, "binding22003", v22020);
    const v22021 = try o.lookup(&s, frame, "binding22003");
    try s.put(namespace, "IsNot", v22021);
    const v22022 = try o.lookup(&s, frame, "binding22003");
    try s.put(namespace, "IsNot", v22022);
    try s.put(bindings, "IsNot", try s.text("binding22003"));
}
fn body22004(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v22006 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding22005", v22006);
    const v22007 = try o.importValue(&s, graph, "guard/index.mjs", "Guard");
    const v22008 = try s.text("HasPropertyKey");
    const v22009 = try s.own(try js.getKey(e, v22007, v22008));
    const v22010 = try o.lookup(&s, frame, "binding22005");
    const v22011 = try s.text("not");
    const v22012 = try s.call(v22009, v22007, &.{ v22010, v22011 });
    const v22014 = logical22013: {
        if (!s.truthy(v22012)) break :logical22013 v22012;
        const v22015 = try o.importValue(&s, graph, "schema/types/schema.mjs", "IsSchema");
        const v22016 = try o.lookup(&s, frame, "binding22005");
        const v22017 = try s.text("not");
        const v22018 = try s.own(try js.getKey(e, v22016, v22017));
        const v22019 = try s.call(v22015, c.pi_js_undefined(), &.{v22018});
        break :logical22013 v22019;
    };
    return c.JS_DupValue(e.context, v22014);
}
