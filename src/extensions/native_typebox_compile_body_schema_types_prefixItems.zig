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
    const namespace = try s.get(modules, "schema/types/prefixItems.mjs");
    const frame = try o.frame(&s, c.pi_js_null());
    try s.put(frame, "@this", c.pi_js_undefined());
    try s.put(try s.get(graph, "frames"), "schema/types/prefixItems.mjs", frame);
    const bindings = try s.object();
    try s.put(try s.get(graph, "bindings"), "schema/types/prefixItems.mjs", bindings);
    const v22167 = try s.own(try ordinary.create(e, "IsPrefixItems", 1, body22133, &.{ graph, frame }));
    try o.assign(&s, frame, "binding22132", v22167);
    const v22168 = try o.lookup(&s, frame, "binding22132");
    try s.put(namespace, "IsPrefixItems", v22168);
    const v22169 = try o.lookup(&s, frame, "binding22132");
    try s.put(namespace, "IsPrefixItems", v22169);
    try s.put(bindings, "IsPrefixItems", try s.text("binding22132"));
}
fn body22158(e: *Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    _ = try o.lookup(&s, frame, "@this");
    const v22161 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding22160", v22161);
    const v22162 = try o.importValue(&s, graph, "schema/types/schema.mjs", "IsSchema");
    const v22163 = try o.lookup(&s, frame, "binding22160");
    const v22164 = try o.call(&s, @src(), v22162, c.pi_js_undefined(), &.{v22163});
    return c.JS_DupValue(e.context, v22164);
}
fn body22158C(ctx: ?*c.JSContext, receiver: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const e = Engine.fromContext(ctx.?);
    return body22158(e, receiver, if (argc > 0) argv[0..@intCast(argc)] else &.{}, roots[0..2]) catch |err| sdk.fail(e, err);
}
fn body22133(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v22135 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding22134", v22135);
    const v22136 = try o.importValue(&s, graph, "guard/index.mjs", "Guard");
    const v22137 = try s.text("HasPropertyKey");
    const v22138 = try s.own(try js.getKey(e, v22136, v22137));
    const v22139 = try o.lookup(&s, frame, "binding22134");
    const v22140 = try s.text("prefixItems");
    const v22141 = try o.call(&s, @src(), v22138, v22136, &.{ v22139, v22140 });
    const v22143 = logical22142: {
        if (!s.truthy(v22141)) break :logical22142 v22141;
        const v22144 = try o.importValue(&s, graph, "guard/index.mjs", "Guard");
        const v22145 = try s.text("IsArray");
        const v22146 = try s.own(try js.getKey(e, v22144, v22145));
        const v22147 = try o.lookup(&s, frame, "binding22134");
        const v22148 = try s.text("prefixItems");
        const v22149 = try s.own(try js.getKey(e, v22147, v22148));
        const v22150 = try o.call(&s, @src(), v22146, v22144, &.{v22149});
        break :logical22142 v22150;
    };
    const v22152 = logical22151: {
        if (!s.truthy(v22143)) break :logical22151 v22143;
        const v22153 = try o.lookup(&s, frame, "binding22134");
        const v22154 = try s.text("prefixItems");
        const v22155 = try s.own(try js.getKey(e, v22153, v22154));
        const v22156 = try s.text("every");
        const v22157 = try s.own(try js.getKey(e, v22155, v22156));
        const v22165 = try o.arrow(&s, "", 1, body22158C, &.{ graph, frame });
        const v22166 = try o.call(&s, @src(), v22157, v22155, &.{v22165});
        break :logical22151 v22166;
    };
    return c.JS_DupValue(e.context, v22152);
}
