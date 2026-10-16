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
    const namespace = try s.get(modules, "value/create/from_record.mjs");
    const frame = try o.frame(&s, c.pi_js_null());
    try s.put(frame, "@this", c.pi_js_undefined());
    try s.put(try s.get(graph, "frames"), "value/create/from_record.mjs", frame);
    const bindings = try s.object();
    try s.put(try s.get(graph, "bindings"), "value/create/from_record.mjs", bindings);
    const v28820 = try s.own(try ordinary.create(e, "FromRecord", 2, body28802, &.{ graph, frame }));
    try o.assign(&s, frame, "binding28801", v28820);
    const v28821 = try o.lookup(&s, frame, "binding28801");
    try s.put(namespace, "FromRecord", v28821);
    const v28822 = try o.lookup(&s, frame, "binding28801");
    try s.put(namespace, "FromRecord", v28822);
    try s.put(bindings, "FromRecord", try s.text("binding28801"));
}
fn body28802(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v28805 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding28803", v28805);
    const v28806 = if (args.len > 1) args[1] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding28804", v28806);
    const v28807 = try o.importValue(&s, graph, "schema/types/index.mjs", "IsMinProperties");
    const v28808 = try o.lookup(&s, frame, "binding28804");
    const v28809 = try s.call(v28807, c.pi_js_undefined(), &.{v28808});
    const v28811 = logical28810: {
        if (!s.truthy(v28809)) break :logical28810 v28809;
        const v28812 = try o.importValue(&s, graph, "schema/types/index.mjs", "IsDefault");
        const v28813 = try o.lookup(&s, frame, "binding28804");
        const v28814 = try s.call(v28812, c.pi_js_undefined(), &.{v28813});
        break :logical28810 o.boolean(&s, !s.truthy(v28814));
    };
    if (s.truthy(v28811)) {
        const v28815 = try o.importValue(&s, graph, "value/create/error.mjs", "CreateError");
        const v28816 = try o.lookup(&s, frame, "binding28804");
        const v28817 = try s.text("Record with the minProperties constraint must have a default annotation");
        const v28818 = try o.construct(&s, v28815, &.{ v28816, v28817 });
        _ = c.JS_Throw(e.context, c.JS_DupValue(e.context, v28818));
        return js.capture(e);
    }
    const v28819 = try s.object();
    return c.JS_DupValue(e.context, v28819);
}
