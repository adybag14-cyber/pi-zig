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
    const namespace = try s.get(modules, "schema/types/properties.mjs");
    const frame = try o.frame(&s, c.pi_js_null());
    try s.put(frame, "@this", c.pi_js_undefined());
    try s.put(try s.get(graph, "frames"), "schema/types/properties.mjs", frame);
    const bindings = try s.object();
    try s.put(try s.get(graph, "bindings"), "schema/types/properties.mjs", bindings);
    const v22209 = try s.own(try ordinary.create(e, "IsProperties", 1, body22171, &.{ graph, frame }));
    try o.assign(&s, frame, "binding22170", v22209);
    const v22210 = try o.lookup(&s, frame, "binding22170");
    try s.put(namespace, "IsProperties", v22210);
    const v22211 = try o.lookup(&s, frame, "binding22170");
    try s.put(namespace, "IsProperties", v22211);
    try s.put(bindings, "IsProperties", try s.text("binding22170"));
}
fn body22200(e: *Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    _ = try o.lookup(&s, frame, "@this");
    const v22203 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding22202", v22203);
    const v22204 = try o.importValue(&s, graph, "schema/types/schema.mjs", "IsSchema");
    const v22205 = try o.lookup(&s, frame, "binding22202");
    const v22206 = try s.call(v22204, c.pi_js_undefined(), &.{v22205});
    return c.JS_DupValue(e.context, v22206);
}
fn body22200C(ctx: ?*c.JSContext, receiver: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const e = Engine.fromContext(ctx.?);
    return body22200(e, receiver, if (argc > 0) argv[0..@intCast(argc)] else &.{}, roots[0..2]) catch |err| sdk.fail(e, err);
}
fn body22171(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v22173 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding22172", v22173);
    const v22174 = try o.importValue(&s, graph, "guard/index.mjs", "Guard");
    const v22175 = try s.text("HasPropertyKey");
    const v22176 = try s.own(try js.getKey(e, v22174, v22175));
    const v22177 = try o.lookup(&s, frame, "binding22172");
    const v22178 = try s.text("properties");
    const v22179 = try s.call(v22176, v22174, &.{ v22177, v22178 });
    const v22181 = logical22180: {
        if (!s.truthy(v22179)) break :logical22180 v22179;
        const v22182 = try o.importValue(&s, graph, "guard/index.mjs", "Guard");
        const v22183 = try s.text("IsObject");
        const v22184 = try s.own(try js.getKey(e, v22182, v22183));
        const v22185 = try o.lookup(&s, frame, "binding22172");
        const v22186 = try s.text("properties");
        const v22187 = try s.own(try js.getKey(e, v22185, v22186));
        const v22188 = try s.call(v22184, v22182, &.{v22187});
        break :logical22180 v22188;
    };
    const v22190 = logical22189: {
        if (!s.truthy(v22181)) break :logical22189 v22181;
        const v22191 = try s.global("Object");
        const v22192 = try s.text("values");
        const v22193 = try s.own(try js.getKey(e, v22191, v22192));
        const v22194 = try o.lookup(&s, frame, "binding22172");
        const v22195 = try s.text("properties");
        const v22196 = try s.own(try js.getKey(e, v22194, v22195));
        const v22197 = try s.call(v22193, v22191, &.{v22196});
        const v22198 = try s.text("every");
        const v22199 = try s.own(try js.getKey(e, v22197, v22198));
        const v22207 = try o.arrow(&s, "", 1, body22200C, &.{ graph, frame });
        const v22208 = try s.call(v22199, v22197, &.{v22207});
        break :logical22189 v22208;
    };
    return c.JS_DupValue(e.context, v22190);
}
