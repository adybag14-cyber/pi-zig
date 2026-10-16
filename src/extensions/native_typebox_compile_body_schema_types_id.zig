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
    const namespace = try s.get(modules, "schema/types/id.mjs");
    const frame = try o.frame(&s, c.pi_js_null());
    try s.put(frame, "@this", c.pi_js_undefined());
    try s.put(try s.get(graph, "frames"), "schema/types/id.mjs", frame);
    const bindings = try s.object();
    try s.put(try s.get(graph, "bindings"), "schema/types/id.mjs", bindings);
    const v21628 = try s.own(try ordinary.create(e, "IsId", 1, body21610, &.{ graph, frame }));
    try o.assign(&s, frame, "binding21609", v21628);
    const v21629 = try o.lookup(&s, frame, "binding21609");
    try s.put(namespace, "IsId", v21629);
    const v21630 = try o.lookup(&s, frame, "binding21609");
    try s.put(namespace, "IsId", v21630);
    try s.put(bindings, "IsId", try s.text("binding21609"));
}
fn body21610(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v21612 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding21611", v21612);
    const v21613 = try o.importValue(&s, graph, "guard/index.mjs", "Guard");
    const v21614 = try s.text("HasPropertyKey");
    const v21615 = try s.own(try js.getKey(e, v21613, v21614));
    const v21616 = try o.lookup(&s, frame, "binding21611");
    const v21617 = try s.text("$id");
    const v21618 = try s.call(v21615, v21613, &.{ v21616, v21617 });
    const v21620 = logical21619: {
        if (!s.truthy(v21618)) break :logical21619 v21618;
        const v21621 = try o.importValue(&s, graph, "guard/index.mjs", "Guard");
        const v21622 = try s.text("IsString");
        const v21623 = try s.own(try js.getKey(e, v21621, v21622));
        const v21624 = try o.lookup(&s, frame, "binding21611");
        const v21625 = try s.text("$id");
        const v21626 = try s.own(try js.getKey(e, v21624, v21625));
        const v21627 = try s.call(v21623, v21621, &.{v21626});
        break :logical21619 v21627;
    };
    return c.JS_DupValue(e.context, v21620);
}
