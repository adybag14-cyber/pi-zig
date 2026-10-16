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
    const namespace = try s.get(modules, "value/create/from_ref.mjs");
    const frame = try o.frame(&s, c.pi_js_null());
    try s.put(frame, "@this", c.pi_js_undefined());
    try s.put(try s.get(graph, "frames"), "value/create/from_ref.mjs", frame);
    const bindings = try s.object();
    try s.put(try s.get(graph, "bindings"), "value/create/from_ref.mjs", bindings);
    const v28856 = try s.own(try ordinary.create(e, "FromRef", 2, body28824, &.{ graph, frame }));
    try o.assign(&s, frame, "binding28823", v28856);
    const v28857 = try o.lookup(&s, frame, "binding28823");
    try s.put(namespace, "FromRef", v28857);
    const v28858 = try o.lookup(&s, frame, "binding28823");
    try s.put(namespace, "FromRef", v28858);
    try s.put(bindings, "FromRef", try s.text("binding28823"));
}
fn body28848(e: *Engine, _: c.JSValue, _: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    _ = try o.lookup(&s, frame, "@this");
    const v28850 = try o.importValue(&s, graph, "value/create/error.mjs", "CreateError");
    const v28851 = try o.lookup(&s, frame, "binding28826");
    const v28852 = try s.text("Unable to deref Ref");
    const v28853 = try o.construct(&s, v28850, &.{ v28851, v28852 });
    _ = c.JS_Throw(e.context, c.JS_DupValue(e.context, v28853));
    return js.capture(e);
}
fn body28848C(ctx: ?*c.JSContext, receiver: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const e = Engine.fromContext(ctx.?);
    return body28848(e, receiver, if (argc > 0) argv[0..@intCast(argc)] else &.{}, roots[0..2]) catch |err| sdk.fail(e, err);
}
fn body28824(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v28827 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding28825", v28827);
    const v28828 = if (args.len > 1) args[1] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding28826", v28828);
    const v28829 = try o.importValue(&s, graph, "guard/index.mjs", "Guard");
    const v28830 = try s.text("HasPropertyKey");
    const v28831 = try s.own(try js.getKey(e, v28829, v28830));
    const v28832 = try o.lookup(&s, frame, "binding28825");
    const v28833 = try o.lookup(&s, frame, "binding28826");
    const v28834 = try s.text("$ref");
    const v28835 = try s.own(try js.getKey(e, v28833, v28834));
    const v28836 = try s.call(v28831, v28829, &.{ v28832, v28835 });
    const v28838 = conditional28837: {
        if (s.truthy(v28836)) {
            const v28839 = try o.importValue(&s, graph, "value/create/from_type.mjs", "FromType");
            const v28840 = try o.lookup(&s, frame, "binding28825");
            const v28841 = try o.lookup(&s, frame, "binding28825");
            const v28842 = try o.lookup(&s, frame, "binding28826");
            const v28843 = try s.text("$ref");
            const v28844 = try s.own(try js.getKey(e, v28842, v28843));
            const v28845 = try o.propertyKey(&s, v28844);
            const v28846 = try s.own(try js.getKey(e, v28841, v28845));
            const v28847 = try s.call(v28839, c.pi_js_undefined(), &.{ v28840, v28846 });
            break :conditional28837 v28847;
        } else {
            const v28854 = try o.arrow(&s, "", 0, body28848C, &.{ graph, frame });
            const v28855 = try s.call(v28854, c.pi_js_undefined(), &.{});
            break :conditional28837 v28855;
        }
    };
    return c.JS_DupValue(e.context, v28838);
}
