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
    const namespace = try s.get(modules, "schema/types/allOf.mjs");
    const frame = try o.frame(&s, c.pi_js_null());
    try s.put(frame, "@this", c.pi_js_undefined());
    try s.put(try s.get(graph, "frames"), "schema/types/allOf.mjs", frame);
    const bindings = try s.object();
    try s.put(try s.get(graph, "bindings"), "schema/types/allOf.mjs", bindings);
    const v21121 = try s.own(try ordinary.create(e, "IsAllOf", 1, body21087, &.{ graph, frame }));
    try o.assign(&s, frame, "binding21086", v21121);
    const v21122 = try o.lookup(&s, frame, "binding21086");
    try s.put(namespace, "IsAllOf", v21122);
    const v21123 = try o.lookup(&s, frame, "binding21086");
    try s.put(namespace, "IsAllOf", v21123);
    try s.put(bindings, "IsAllOf", try s.text("binding21086"));
}
fn body21112(e: *Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    _ = try o.lookup(&s, frame, "@this");
    const v21115 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding21114", v21115);
    const v21116 = try o.importValue(&s, graph, "schema/types/schema.mjs", "IsSchema");
    const v21117 = try o.lookup(&s, frame, "binding21114");
    const v21118 = try s.call(v21116, c.pi_js_undefined(), &.{v21117});
    return c.JS_DupValue(e.context, v21118);
}
fn body21112C(ctx: ?*c.JSContext, receiver: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const e = Engine.fromContext(ctx.?);
    return body21112(e, receiver, if (argc > 0) argv[0..@intCast(argc)] else &.{}, roots[0..2]) catch |err| sdk.fail(e, err);
}
fn body21087(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v21089 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding21088", v21089);
    const v21090 = try o.importValue(&s, graph, "guard/index.mjs", "Guard");
    const v21091 = try s.text("HasPropertyKey");
    const v21092 = try s.own(try js.getKey(e, v21090, v21091));
    const v21093 = try o.lookup(&s, frame, "binding21088");
    const v21094 = try s.text("allOf");
    const v21095 = try s.call(v21092, v21090, &.{ v21093, v21094 });
    const v21097 = logical21096: {
        if (!s.truthy(v21095)) break :logical21096 v21095;
        const v21098 = try o.importValue(&s, graph, "guard/index.mjs", "Guard");
        const v21099 = try s.text("IsArray");
        const v21100 = try s.own(try js.getKey(e, v21098, v21099));
        const v21101 = try o.lookup(&s, frame, "binding21088");
        const v21102 = try s.text("allOf");
        const v21103 = try s.own(try js.getKey(e, v21101, v21102));
        const v21104 = try s.call(v21100, v21098, &.{v21103});
        break :logical21096 v21104;
    };
    const v21106 = logical21105: {
        if (!s.truthy(v21097)) break :logical21105 v21097;
        const v21107 = try o.lookup(&s, frame, "binding21088");
        const v21108 = try s.text("allOf");
        const v21109 = try s.own(try js.getKey(e, v21107, v21108));
        const v21110 = try s.text("every");
        const v21111 = try s.own(try js.getKey(e, v21109, v21110));
        const v21119 = try o.arrow(&s, "", 1, body21112C, &.{ graph, frame });
        const v21120 = try s.call(v21111, v21109, &.{v21119});
        break :logical21105 v21120;
    };
    return c.JS_DupValue(e.context, v21106);
}
