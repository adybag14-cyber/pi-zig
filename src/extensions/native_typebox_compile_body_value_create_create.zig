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
    const namespace = try s.get(modules, "value/create/create.mjs");
    const frame = try o.frame(&s, c.pi_js_null());
    try s.put(frame, "@this", c.pi_js_undefined());
    try s.put(try s.get(graph, "frames"), "value/create/create.mjs", frame);
    const bindings = try s.object();
    try s.put(try s.get(graph, "bindings"), "value/create/create.mjs", bindings);
    const v28396 = try s.own(try ordinary.create(e, "Create", 0, body28356, &.{ graph, frame }));
    try o.assign(&s, frame, "binding28355", v28396);
    const v28397 = try o.lookup(&s, frame, "binding28355");
    try s.put(namespace, "Create", v28397);
    const v28398 = try o.lookup(&s, frame, "binding28355");
    try s.put(namespace, "Create", v28398);
    try s.put(bindings, "Create", try s.text("binding28355"));
}
fn body28369(e: *Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    _ = roots[0];
    const frame = try o.frame(&s, roots[1]);
    _ = try o.lookup(&s, frame, "@this");
    const v28373 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding28371", v28373);
    const v28374 = if (args.len > 1) args[1] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding28372", v28374);
    const v28375 = try s.array();
    const v28376 = try o.lookup(&s, frame, "binding28371");
    try o.append(&s, v28375, v28376);
    const v28377 = try o.lookup(&s, frame, "binding28372");
    try o.append(&s, v28375, v28377);
    return c.JS_DupValue(e.context, v28375);
}
fn body28369C(ctx: ?*c.JSContext, receiver: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const e = Engine.fromContext(ctx.?);
    return body28369(e, receiver, if (argc > 0) argv[0..@intCast(argc)] else &.{}, roots[0..2]) catch |err| sdk.fail(e, err);
}
fn body28380(e: *Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    _ = roots[0];
    const frame = try o.frame(&s, roots[1]);
    _ = try o.lookup(&s, frame, "@this");
    const v28383 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding28382", v28383);
    const v28384 = try s.array();
    const v28385 = try s.object();
    try o.append(&s, v28384, v28385);
    const v28386 = try o.lookup(&s, frame, "binding28382");
    try o.append(&s, v28384, v28386);
    return c.JS_DupValue(e.context, v28384);
}
fn body28380C(ctx: ?*c.JSContext, receiver: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const e = Engine.fromContext(ctx.?);
    return body28380(e, receiver, if (argc > 0) argv[0..@intCast(argc)] else &.{}, roots[0..2]) catch |err| sdk.fail(e, err);
}
fn body28356(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v28360 = try o.rest(&s, args, 0);
    try o.assign(&s, frame, "binding28357", v28360);
    const v28363 = try o.importValue(&s, graph, "system/arguments/index.mjs", "Arguments");
    const v28364 = try s.text("Match");
    const v28365 = try s.own(try js.getKey(e, v28363, v28364));
    const v28366 = try o.lookup(&s, frame, "binding28357");
    const v28367 = try s.object();
    const v28368 = try s.text("2");
    const v28378 = try o.arrow(&s, "2", 2, body28369C, &.{ graph, frame });
    try o.defineKey(&s, v28367, v28368, v28378);
    const v28379 = try s.text("1");
    const v28387 = try o.arrow(&s, "1", 1, body28380C, &.{ graph, frame });
    try o.defineKey(&s, v28367, v28379, v28387);
    const v28388 = try s.call(v28365, v28363, &.{ v28366, v28367 });
    var destructure28389 = try o.iterator(e, v28388);
    defer destructure28389.deinit();
    errdefer destructure28389.closePreserving();
    const v28390 = try s.own(if (destructure28389.closed) c.pi_js_undefined() else (try destructure28389.next()) orelse c.pi_js_undefined());
    try o.assign(&s, frame, "binding28361", v28390);
    const v28391 = try s.own(if (destructure28389.closed) c.pi_js_undefined() else (try destructure28389.next()) orelse c.pi_js_undefined());
    try o.assign(&s, frame, "binding28362", v28391);
    try destructure28389.close();
    const v28392 = try o.importValue(&s, graph, "value/create/from_type.mjs", "FromType");
    const v28393 = try o.lookup(&s, frame, "binding28361");
    const v28394 = try o.lookup(&s, frame, "binding28362");
    const v28395 = try s.call(v28392, c.pi_js_undefined(), &.{ v28393, v28394 });
    return c.JS_DupValue(e.context, v28395);
}
