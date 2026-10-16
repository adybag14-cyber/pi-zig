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
    const namespace = try s.get(modules, "schema/types/enum.mjs");
    const frame = try o.frame(&s, c.pi_js_null());
    try s.put(frame, "@this", c.pi_js_undefined());
    try s.put(try s.get(graph, "frames"), "schema/types/enum.mjs", frame);
    const bindings = try s.object();
    try s.put(try s.get(graph, "bindings"), "schema/types/enum.mjs", bindings);
    const v21522 = try s.own(try ordinary.create(e, "IsEnum", 1, body21504, &.{ graph, frame }));
    try o.assign(&s, frame, "binding21503", v21522);
    const v21523 = try o.lookup(&s, frame, "binding21503");
    try s.put(namespace, "IsEnum", v21523);
    const v21524 = try o.lookup(&s, frame, "binding21503");
    try s.put(namespace, "IsEnum", v21524);
    try s.put(bindings, "IsEnum", try s.text("binding21503"));
}
fn body21504(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v21506 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding21505", v21506);
    const v21507 = try o.importValue(&s, graph, "guard/index.mjs", "Guard");
    const v21508 = try s.text("HasPropertyKey");
    const v21509 = try s.own(try js.getKey(e, v21507, v21508));
    const v21510 = try o.lookup(&s, frame, "binding21505");
    const v21511 = try s.text("enum");
    const v21512 = try s.call(v21509, v21507, &.{ v21510, v21511 });
    const v21514 = logical21513: {
        if (!s.truthy(v21512)) break :logical21513 v21512;
        const v21515 = try o.importValue(&s, graph, "guard/index.mjs", "Guard");
        const v21516 = try s.text("IsArray");
        const v21517 = try s.own(try js.getKey(e, v21515, v21516));
        const v21518 = try o.lookup(&s, frame, "binding21505");
        const v21519 = try s.text("enum");
        const v21520 = try s.own(try js.getKey(e, v21518, v21519));
        const v21521 = try s.call(v21517, v21515, &.{v21520});
        break :logical21513 v21521;
    };
    return c.JS_DupValue(e.context, v21514);
}
