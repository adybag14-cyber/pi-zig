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
    const namespace = try s.get(modules, "schema/types/if.mjs");
    const frame = try o.frame(&s, c.pi_js_null());
    try s.put(frame, "@this", c.pi_js_undefined());
    try s.put(try s.get(graph, "frames"), "schema/types/if.mjs", frame);
    const bindings = try s.object();
    try s.put(try s.get(graph, "bindings"), "schema/types/if.mjs", bindings);
    const v21648 = try s.own(try ordinary.create(e, "IsIf", 1, body21632, &.{ graph, frame }));
    try o.assign(&s, frame, "binding21631", v21648);
    const v21649 = try o.lookup(&s, frame, "binding21631");
    try s.put(namespace, "IsIf", v21649);
    const v21650 = try o.lookup(&s, frame, "binding21631");
    try s.put(namespace, "IsIf", v21650);
    try s.put(bindings, "IsIf", try s.text("binding21631"));
}
fn body21632(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v21634 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding21633", v21634);
    const v21635 = try o.importValue(&s, graph, "guard/index.mjs", "Guard");
    const v21636 = try s.text("HasPropertyKey");
    const v21637 = try s.own(try js.getKey(e, v21635, v21636));
    const v21638 = try o.lookup(&s, frame, "binding21633");
    const v21639 = try s.text("if");
    const v21640 = try s.call(v21637, v21635, &.{ v21638, v21639 });
    const v21642 = logical21641: {
        if (!s.truthy(v21640)) break :logical21641 v21640;
        const v21643 = try o.importValue(&s, graph, "schema/types/schema.mjs", "IsSchema");
        const v21644 = try o.lookup(&s, frame, "binding21633");
        const v21645 = try s.text("if");
        const v21646 = try s.own(try js.getKey(e, v21644, v21645));
        const v21647 = try s.call(v21643, c.pi_js_undefined(), &.{v21646});
        break :logical21641 v21647;
    };
    return c.JS_DupValue(e.context, v21642);
}
