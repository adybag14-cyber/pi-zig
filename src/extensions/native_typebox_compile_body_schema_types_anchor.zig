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
    const namespace = try s.get(modules, "schema/types/anchor.mjs");
    const frame = try o.frame(&s, c.pi_js_null());
    try s.put(frame, "@this", c.pi_js_undefined());
    try s.put(try s.get(graph, "frames"), "schema/types/anchor.mjs", frame);
    const bindings = try s.object();
    try s.put(try s.get(graph, "bindings"), "schema/types/anchor.mjs", bindings);
    const v21143 = try s.own(try ordinary.create(e, "IsAnchor", 1, body21125, &.{ graph, frame }));
    try o.assign(&s, frame, "binding21124", v21143);
    const v21144 = try o.lookup(&s, frame, "binding21124");
    try s.put(namespace, "IsAnchor", v21144);
    const v21145 = try o.lookup(&s, frame, "binding21124");
    try s.put(namespace, "IsAnchor", v21145);
    try s.put(bindings, "IsAnchor", try s.text("binding21124"));
}
fn body21125(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v21127 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding21126", v21127);
    const v21128 = try o.importValue(&s, graph, "guard/index.mjs", "Guard");
    const v21129 = try s.text("HasPropertyKey");
    const v21130 = try s.own(try js.getKey(e, v21128, v21129));
    const v21131 = try o.lookup(&s, frame, "binding21126");
    const v21132 = try s.text("$anchor");
    const v21133 = try s.call(v21130, v21128, &.{ v21131, v21132 });
    const v21135 = logical21134: {
        if (!s.truthy(v21133)) break :logical21134 v21133;
        const v21136 = try o.importValue(&s, graph, "guard/index.mjs", "Guard");
        const v21137 = try s.text("IsString");
        const v21138 = try s.own(try js.getKey(e, v21136, v21137));
        const v21139 = try o.lookup(&s, frame, "binding21126");
        const v21140 = try s.text("$anchor");
        const v21141 = try s.own(try js.getKey(e, v21139, v21140));
        const v21142 = try s.call(v21138, v21136, &.{v21141});
        break :logical21134 v21142;
    };
    return c.JS_DupValue(e.context, v21135);
}
