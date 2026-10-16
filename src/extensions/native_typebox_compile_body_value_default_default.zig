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
    const namespace = try s.get(modules, "value/default/default.mjs");
    const frame = try o.frame(&s, c.pi_js_null());
    try s.put(frame, "@this", c.pi_js_undefined());
    try s.put(try s.get(graph, "frames"), "value/default/default.mjs", frame);
    const bindings = try s.object();
    try s.put(try s.get(graph, "bindings"), "value/default/default.mjs", bindings);
    const v29345 = try s.own(try ordinary.create(e, "Default", 0, body29295, &.{ graph, frame }));
    try o.assign(&s, frame, "binding29294", v29345);
    const v29346 = try o.lookup(&s, frame, "binding29294");
    try s.put(namespace, "Default", v29346);
    const v29347 = try o.lookup(&s, frame, "binding29294");
    try s.put(namespace, "Default", v29347);
    try s.put(bindings, "Default", try s.text("binding29294"));
}
fn body29310(e: *Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    _ = roots[0];
    const frame = try o.frame(&s, roots[1]);
    _ = try o.lookup(&s, frame, "@this");
    const v29315 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding29312", v29315);
    const v29316 = if (args.len > 1) args[1] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding29313", v29316);
    const v29317 = if (args.len > 2) args[2] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding29314", v29317);
    const v29318 = try s.array();
    const v29319 = try o.lookup(&s, frame, "binding29312");
    try o.append(&s, v29318, v29319);
    const v29320 = try o.lookup(&s, frame, "binding29313");
    try o.append(&s, v29318, v29320);
    const v29321 = try o.lookup(&s, frame, "binding29314");
    try o.append(&s, v29318, v29321);
    return c.JS_DupValue(e.context, v29318);
}
fn body29310C(ctx: ?*c.JSContext, receiver: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const e = Engine.fromContext(ctx.?);
    return body29310(e, receiver, if (argc > 0) argv[0..@intCast(argc)] else &.{}, roots[0..2]) catch |err| sdk.fail(e, err);
}
fn body29324(e: *Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    _ = roots[0];
    const frame = try o.frame(&s, roots[1]);
    _ = try o.lookup(&s, frame, "@this");
    const v29328 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding29326", v29328);
    const v29329 = if (args.len > 1) args[1] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding29327", v29329);
    const v29330 = try s.array();
    const v29331 = try s.object();
    try o.append(&s, v29330, v29331);
    const v29332 = try o.lookup(&s, frame, "binding29326");
    try o.append(&s, v29330, v29332);
    const v29333 = try o.lookup(&s, frame, "binding29327");
    try o.append(&s, v29330, v29333);
    return c.JS_DupValue(e.context, v29330);
}
fn body29324C(ctx: ?*c.JSContext, receiver: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const e = Engine.fromContext(ctx.?);
    return body29324(e, receiver, if (argc > 0) argv[0..@intCast(argc)] else &.{}, roots[0..2]) catch |err| sdk.fail(e, err);
}
fn body29295(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v29300 = try o.rest(&s, args, 0);
    try o.assign(&s, frame, "binding29296", v29300);
    const v29304 = try o.importValue(&s, graph, "system/arguments/index.mjs", "Arguments");
    const v29305 = try s.text("Match");
    const v29306 = try s.own(try js.getKey(e, v29304, v29305));
    const v29307 = try o.lookup(&s, frame, "binding29296");
    const v29308 = try s.object();
    const v29309 = try s.text("3");
    const v29322 = try o.arrow(&s, "3", 3, body29310C, &.{ graph, frame });
    try o.defineKey(&s, v29308, v29309, v29322);
    const v29323 = try s.text("2");
    const v29334 = try o.arrow(&s, "2", 2, body29324C, &.{ graph, frame });
    try o.defineKey(&s, v29308, v29323, v29334);
    const v29335 = try s.call(v29306, v29304, &.{ v29307, v29308 });
    var destructure29336 = try o.iterator(e, v29335);
    defer destructure29336.deinit();
    errdefer destructure29336.closePreserving();
    const v29337 = try s.own(if (destructure29336.closed) c.pi_js_undefined() else (try destructure29336.next()) orelse c.pi_js_undefined());
    try o.assign(&s, frame, "binding29301", v29337);
    const v29338 = try s.own(if (destructure29336.closed) c.pi_js_undefined() else (try destructure29336.next()) orelse c.pi_js_undefined());
    try o.assign(&s, frame, "binding29302", v29338);
    const v29339 = try s.own(if (destructure29336.closed) c.pi_js_undefined() else (try destructure29336.next()) orelse c.pi_js_undefined());
    try o.assign(&s, frame, "binding29303", v29339);
    try destructure29336.close();
    const v29340 = try o.importValue(&s, graph, "value/default/from_type.mjs", "FromType");
    const v29341 = try o.lookup(&s, frame, "binding29301");
    const v29342 = try o.lookup(&s, frame, "binding29302");
    const v29343 = try o.lookup(&s, frame, "binding29303");
    const v29344 = try s.call(v29340, c.pi_js_undefined(), &.{ v29341, v29342, v29343 });
    return c.JS_DupValue(e.context, v29344);
}
