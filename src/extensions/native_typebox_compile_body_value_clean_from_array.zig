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
    const namespace = try s.get(modules, "value/clean/from_array.mjs");
    const frame = try o.frame(&s, c.pi_js_null());
    try s.put(frame, "@this", c.pi_js_undefined());
    try s.put(try s.get(graph, "frames"), "value/clean/from_array.mjs", frame);
    const bindings = try s.object();
    try s.put(try s.get(graph, "bindings"), "value/clean/from_array.mjs", bindings);
    const v23401 = try s.own(try ordinary.create(e, "FromArray", 3, body23372, &.{ graph, frame }));
    try o.assign(&s, frame, "binding23371", v23401);
    const v23402 = try o.lookup(&s, frame, "binding23371");
    try s.put(namespace, "FromArray", v23402);
    const v23403 = try o.lookup(&s, frame, "binding23371");
    try s.put(namespace, "FromArray", v23403);
    try s.put(bindings, "FromArray", try s.text("binding23371"));
}
fn body23388(e: *Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    _ = try o.lookup(&s, frame, "@this");
    const v23391 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding23390", v23391);
    const v23392 = try o.importValue(&s, graph, "value/clean/from_type.mjs", "FromType");
    const v23393 = try o.lookup(&s, frame, "binding23373");
    const v23394 = try o.lookup(&s, frame, "binding23374");
    const v23395 = try s.text("items");
    const v23396 = try s.own(try js.getKey(e, v23394, v23395));
    const v23397 = try o.lookup(&s, frame, "binding23390");
    const v23398 = try s.call(v23392, c.pi_js_undefined(), &.{ v23393, v23396, v23397 });
    return c.JS_DupValue(e.context, v23398);
}
fn body23388C(ctx: ?*c.JSContext, receiver: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const e = Engine.fromContext(ctx.?);
    return body23388(e, receiver, if (argc > 0) argv[0..@intCast(argc)] else &.{}, roots[0..2]) catch |err| sdk.fail(e, err);
}
fn body23372(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v23376 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding23373", v23376);
    const v23377 = if (args.len > 1) args[1] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding23374", v23377);
    const v23378 = if (args.len > 2) args[2] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding23375", v23378);
    const v23379 = try o.importValue(&s, graph, "guard/index.mjs", "Guard");
    const v23380 = try s.text("IsArray");
    const v23381 = try s.own(try js.getKey(e, v23379, v23380));
    const v23382 = try o.lookup(&s, frame, "binding23375");
    const v23383 = try s.call(v23381, v23379, &.{v23382});
    if (s.truthy(o.boolean(&s, !s.truthy(v23383)))) {
        const v23384 = try o.lookup(&s, frame, "binding23375");
        return c.JS_DupValue(e.context, v23384);
    }
    const v23385 = try o.lookup(&s, frame, "binding23375");
    const v23386 = try s.text("map");
    const v23387 = try s.own(try js.getKey(e, v23385, v23386));
    const v23399 = try o.arrow(&s, "", 1, body23388C, &.{ graph, frame });
    const v23400 = try s.call(v23387, v23385, &.{v23399});
    return c.JS_DupValue(e.context, v23400);
}
