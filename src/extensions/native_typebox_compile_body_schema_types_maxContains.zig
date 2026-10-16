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
    const namespace = try s.get(modules, "schema/types/maxContains.mjs");
    const frame = try o.frame(&s, c.pi_js_null());
    try s.put(frame, "@this", c.pi_js_undefined());
    try s.put(try s.get(graph, "frames"), "schema/types/maxContains.mjs", frame);
    const bindings = try s.object();
    try s.put(try s.get(graph, "bindings"), "schema/types/maxContains.mjs", bindings);
    const v21753 = try s.own(try ordinary.create(e, "IsMaxContains", 1, body21735, &.{ graph, frame }));
    try o.assign(&s, frame, "binding21734", v21753);
    const v21754 = try o.lookup(&s, frame, "binding21734");
    try s.put(namespace, "IsMaxContains", v21754);
    const v21755 = try o.lookup(&s, frame, "binding21734");
    try s.put(namespace, "IsMaxContains", v21755);
    try s.put(bindings, "IsMaxContains", try s.text("binding21734"));
}
fn body21735(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v21737 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding21736", v21737);
    const v21738 = try o.importValue(&s, graph, "guard/index.mjs", "Guard");
    const v21739 = try s.text("HasPropertyKey");
    const v21740 = try s.own(try js.getKey(e, v21738, v21739));
    const v21741 = try o.lookup(&s, frame, "binding21736");
    const v21742 = try s.text("maxContains");
    const v21743 = try s.call(v21740, v21738, &.{ v21741, v21742 });
    const v21745 = logical21744: {
        if (!s.truthy(v21743)) break :logical21744 v21743;
        const v21746 = try o.importValue(&s, graph, "guard/index.mjs", "Guard");
        const v21747 = try s.text("IsNumber");
        const v21748 = try s.own(try js.getKey(e, v21746, v21747));
        const v21749 = try o.lookup(&s, frame, "binding21736");
        const v21750 = try s.text("maxContains");
        const v21751 = try s.own(try js.getKey(e, v21749, v21750));
        const v21752 = try s.call(v21748, v21746, &.{v21751});
        break :logical21744 v21752;
    };
    return c.JS_DupValue(e.context, v21745);
}
