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
    const namespace = try s.get(modules, "schema/types/anyOf.mjs");
    const frame = try o.frame(&s, c.pi_js_null());
    try s.put(frame, "@this", c.pi_js_undefined());
    try s.put(try s.get(graph, "frames"), "schema/types/anyOf.mjs", frame);
    const bindings = try s.object();
    try s.put(try s.get(graph, "bindings"), "schema/types/anyOf.mjs", bindings);
    const v21181 = try s.own(try ordinary.create(e, "IsAnyOf", 1, body21147, &.{ graph, frame }));
    try o.assign(&s, frame, "binding21146", v21181);
    const v21182 = try o.lookup(&s, frame, "binding21146");
    try s.put(namespace, "IsAnyOf", v21182);
    const v21183 = try o.lookup(&s, frame, "binding21146");
    try s.put(namespace, "IsAnyOf", v21183);
    try s.put(bindings, "IsAnyOf", try s.text("binding21146"));
}
fn body21172(e: *Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    _ = try o.lookup(&s, frame, "@this");
    const v21175 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding21174", v21175);
    const v21176 = try o.importValue(&s, graph, "schema/types/schema.mjs", "IsSchema");
    const v21177 = try o.lookup(&s, frame, "binding21174");
    const v21178 = try o.call(&s, @src(), v21176, c.pi_js_undefined(), &.{v21177});
    return c.JS_DupValue(e.context, v21178);
}
fn body21172C(ctx: ?*c.JSContext, receiver: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const e = Engine.fromContext(ctx.?);
    return body21172(e, receiver, if (argc > 0) argv[0..@intCast(argc)] else &.{}, roots[0..2]) catch |err| sdk.fail(e, err);
}
fn body21147(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v21149 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding21148", v21149);
    const v21150 = try o.importValue(&s, graph, "guard/index.mjs", "Guard");
    const v21151 = try s.text("HasPropertyKey");
    const v21152 = try s.own(try js.getKey(e, v21150, v21151));
    const v21153 = try o.lookup(&s, frame, "binding21148");
    const v21154 = try s.text("anyOf");
    const v21155 = try o.call(&s, @src(), v21152, v21150, &.{ v21153, v21154 });
    const v21157 = logical21156: {
        if (!s.truthy(v21155)) break :logical21156 v21155;
        const v21158 = try o.importValue(&s, graph, "guard/index.mjs", "Guard");
        const v21159 = try s.text("IsArray");
        const v21160 = try s.own(try js.getKey(e, v21158, v21159));
        const v21161 = try o.lookup(&s, frame, "binding21148");
        const v21162 = try s.text("anyOf");
        const v21163 = try s.own(try js.getKey(e, v21161, v21162));
        const v21164 = try o.call(&s, @src(), v21160, v21158, &.{v21163});
        break :logical21156 v21164;
    };
    const v21166 = logical21165: {
        if (!s.truthy(v21157)) break :logical21165 v21157;
        const v21167 = try o.lookup(&s, frame, "binding21148");
        const v21168 = try s.text("anyOf");
        const v21169 = try s.own(try js.getKey(e, v21167, v21168));
        const v21170 = try s.text("every");
        const v21171 = try s.own(try js.getKey(e, v21169, v21170));
        const v21179 = try o.arrow(&s, "", 1, body21172C, &.{ graph, frame });
        const v21180 = try o.call(&s, @src(), v21171, v21169, &.{v21179});
        break :logical21165 v21180;
    };
    return c.JS_DupValue(e.context, v21166);
}
