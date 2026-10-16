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
    const namespace = try s.get(modules, "schema/types/oneOf.mjs");
    const frame = try o.frame(&s, c.pi_js_null());
    try s.put(frame, "@this", c.pi_js_undefined());
    try s.put(try s.get(graph, "frames"), "schema/types/oneOf.mjs", frame);
    const bindings = try s.object();
    try s.put(try s.get(graph, "bindings"), "schema/types/oneOf.mjs", bindings);
    const v22058 = try s.own(try ordinary.create(e, "IsOneOf", 1, body22024, &.{ graph, frame }));
    try o.assign(&s, frame, "binding22023", v22058);
    const v22059 = try o.lookup(&s, frame, "binding22023");
    try s.put(namespace, "IsOneOf", v22059);
    const v22060 = try o.lookup(&s, frame, "binding22023");
    try s.put(namespace, "IsOneOf", v22060);
    try s.put(bindings, "IsOneOf", try s.text("binding22023"));
}
fn body22049(e: *Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    _ = try o.lookup(&s, frame, "@this");
    const v22052 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding22051", v22052);
    const v22053 = try o.importValue(&s, graph, "schema/types/schema.mjs", "IsSchema");
    const v22054 = try o.lookup(&s, frame, "binding22051");
    const v22055 = try s.call(v22053, c.pi_js_undefined(), &.{v22054});
    return c.JS_DupValue(e.context, v22055);
}
fn body22049C(ctx: ?*c.JSContext, receiver: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const e = Engine.fromContext(ctx.?);
    return body22049(e, receiver, if (argc > 0) argv[0..@intCast(argc)] else &.{}, roots[0..2]) catch |err| sdk.fail(e, err);
}
fn body22024(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v22026 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding22025", v22026);
    const v22027 = try o.importValue(&s, graph, "guard/index.mjs", "Guard");
    const v22028 = try s.text("HasPropertyKey");
    const v22029 = try s.own(try js.getKey(e, v22027, v22028));
    const v22030 = try o.lookup(&s, frame, "binding22025");
    const v22031 = try s.text("oneOf");
    const v22032 = try s.call(v22029, v22027, &.{ v22030, v22031 });
    const v22034 = logical22033: {
        if (!s.truthy(v22032)) break :logical22033 v22032;
        const v22035 = try o.importValue(&s, graph, "guard/index.mjs", "Guard");
        const v22036 = try s.text("IsArray");
        const v22037 = try s.own(try js.getKey(e, v22035, v22036));
        const v22038 = try o.lookup(&s, frame, "binding22025");
        const v22039 = try s.text("oneOf");
        const v22040 = try s.own(try js.getKey(e, v22038, v22039));
        const v22041 = try s.call(v22037, v22035, &.{v22040});
        break :logical22033 v22041;
    };
    const v22043 = logical22042: {
        if (!s.truthy(v22034)) break :logical22042 v22034;
        const v22044 = try o.lookup(&s, frame, "binding22025");
        const v22045 = try s.text("oneOf");
        const v22046 = try s.own(try js.getKey(e, v22044, v22045));
        const v22047 = try s.text("every");
        const v22048 = try s.own(try js.getKey(e, v22046, v22047));
        const v22056 = try o.arrow(&s, "", 1, body22049C, &.{ graph, frame });
        const v22057 = try s.call(v22048, v22046, &.{v22056});
        break :logical22042 v22057;
    };
    return c.JS_DupValue(e.context, v22043);
}
