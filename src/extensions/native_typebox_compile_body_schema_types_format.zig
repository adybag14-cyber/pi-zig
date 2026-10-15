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
    const namespace = try s.get(modules, "schema/types/format.mjs");
    const frame = try o.frame(&s, c.pi_js_null());
    try s.put(frame, "@this", c.pi_js_undefined());
    try s.put(try s.get(graph, "frames"), "schema/types/format.mjs", frame);
    const bindings = try s.object();
    try s.put(try s.get(graph, "bindings"), "schema/types/format.mjs", bindings);
    const v21606 = try s.own(try ordinary.create(e, "IsFormat", 1, body21588, &.{ graph, frame }));
    try o.assign(&s, frame, "binding21587", v21606);
    const v21607 = try o.lookup(&s, frame, "binding21587");
    try s.put(namespace, "IsFormat", v21607);
    const v21608 = try o.lookup(&s, frame, "binding21587");
    try s.put(namespace, "IsFormat", v21608);
    try s.put(bindings, "IsFormat", try s.text("binding21587"));
}
fn body21588(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v21590 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding21589", v21590);
    const v21591 = try o.importValue(&s, graph, "guard/index.mjs", "Guard");
    const v21592 = try s.text("HasPropertyKey");
    const v21593 = try s.own(try js.getKey(e, v21591, v21592));
    const v21594 = try o.lookup(&s, frame, "binding21589");
    const v21595 = try s.text("format");
    const v21596 = try s.call(v21593, v21591, &.{ v21594, v21595 });
    const v21598 = logical21597: {
        if (!s.truthy(v21596)) break :logical21597 v21596;
        const v21599 = try o.importValue(&s, graph, "guard/index.mjs", "Guard");
        const v21600 = try s.text("IsString");
        const v21601 = try s.own(try js.getKey(e, v21599, v21600));
        const v21602 = try o.lookup(&s, frame, "binding21589");
        const v21603 = try s.text("format");
        const v21604 = try s.own(try js.getKey(e, v21602, v21603));
        const v21605 = try s.call(v21601, v21599, &.{v21604});
        break :logical21597 v21605;
    };
    return c.JS_DupValue(e.context, v21598);
}
