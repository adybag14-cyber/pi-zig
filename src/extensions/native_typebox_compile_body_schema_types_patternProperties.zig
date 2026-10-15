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
    const namespace = try s.get(modules, "schema/types/patternProperties.mjs");
    const frame = try o.frame(&s, c.pi_js_null());
    try s.put(frame, "@this", c.pi_js_undefined());
    try s.put(try s.get(graph, "frames"), "schema/types/patternProperties.mjs", frame);
    const bindings = try s.object();
    try s.put(try s.get(graph, "bindings"), "schema/types/patternProperties.mjs", bindings);
    const v22129 = try s.own(try ordinary.create(e, "IsPatternProperties", 1, body22091, &.{ graph, frame }));
    try o.assign(&s, frame, "binding22090", v22129);
    const v22130 = try o.lookup(&s, frame, "binding22090");
    try s.put(namespace, "IsPatternProperties", v22130);
    const v22131 = try o.lookup(&s, frame, "binding22090");
    try s.put(namespace, "IsPatternProperties", v22131);
    try s.put(bindings, "IsPatternProperties", try s.text("binding22090"));
}
fn body22120(e: *Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    _ = try o.lookup(&s, frame, "@this");
    const v22123 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding22122", v22123);
    const v22124 = try o.importValue(&s, graph, "schema/types/schema.mjs", "IsSchema");
    const v22125 = try o.lookup(&s, frame, "binding22122");
    const v22126 = try s.call(v22124, c.pi_js_undefined(), &.{v22125});
    return c.JS_DupValue(e.context, v22126);
}
fn body22120C(ctx: ?*c.JSContext, receiver: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const e = Engine.fromContext(ctx.?);
    return body22120(e, receiver, if (argc > 0) argv[0..@intCast(argc)] else &.{}, roots[0..2]) catch |err| sdk.fail(e, err);
}
fn body22091(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v22093 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding22092", v22093);
    const v22094 = try o.importValue(&s, graph, "guard/index.mjs", "Guard");
    const v22095 = try s.text("HasPropertyKey");
    const v22096 = try s.own(try js.getKey(e, v22094, v22095));
    const v22097 = try o.lookup(&s, frame, "binding22092");
    const v22098 = try s.text("patternProperties");
    const v22099 = try s.call(v22096, v22094, &.{ v22097, v22098 });
    const v22101 = logical22100: {
        if (!s.truthy(v22099)) break :logical22100 v22099;
        const v22102 = try o.importValue(&s, graph, "guard/index.mjs", "Guard");
        const v22103 = try s.text("IsObject");
        const v22104 = try s.own(try js.getKey(e, v22102, v22103));
        const v22105 = try o.lookup(&s, frame, "binding22092");
        const v22106 = try s.text("patternProperties");
        const v22107 = try s.own(try js.getKey(e, v22105, v22106));
        const v22108 = try s.call(v22104, v22102, &.{v22107});
        break :logical22100 v22108;
    };
    const v22110 = logical22109: {
        if (!s.truthy(v22101)) break :logical22109 v22101;
        const v22111 = try s.global("Object");
        const v22112 = try s.text("values");
        const v22113 = try s.own(try js.getKey(e, v22111, v22112));
        const v22114 = try o.lookup(&s, frame, "binding22092");
        const v22115 = try s.text("patternProperties");
        const v22116 = try s.own(try js.getKey(e, v22114, v22115));
        const v22117 = try s.call(v22113, v22111, &.{v22116});
        const v22118 = try s.text("every");
        const v22119 = try s.own(try js.getKey(e, v22117, v22118));
        const v22127 = try o.arrow(&s, "", 1, body22120C, &.{ graph, frame });
        const v22128 = try s.call(v22119, v22117, &.{v22127});
        break :logical22109 v22128;
    };
    return c.JS_DupValue(e.context, v22110);
}
