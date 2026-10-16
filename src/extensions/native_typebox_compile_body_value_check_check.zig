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
    const namespace = try s.get(modules, "value/check/check.mjs");
    const frame = try o.frame(&s, c.pi_js_null());
    try s.put(frame, "@this", c.pi_js_undefined());
    try s.put(try s.get(graph, "frames"), "value/check/check.mjs", frame);
    const bindings = try s.object();
    try s.put(try s.get(graph, "bindings"), "value/check/check.mjs", bindings);
    const v23279 = try s.own(try ordinary.create(e, "Check", 0, body23229, &.{ graph, frame }));
    try o.assign(&s, frame, "binding23228", v23279);
    const v23280 = try o.lookup(&s, frame, "binding23228");
    try s.put(namespace, "Check", v23280);
    const v23281 = try o.lookup(&s, frame, "binding23228");
    try s.put(namespace, "Check", v23281);
    try s.put(bindings, "Check", try s.text("binding23228"));
}
fn body23244(e: *Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    _ = roots[0];
    const frame = try o.frame(&s, roots[1]);
    _ = try o.lookup(&s, frame, "@this");
    const v23249 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding23246", v23249);
    const v23250 = if (args.len > 1) args[1] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding23247", v23250);
    const v23251 = if (args.len > 2) args[2] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding23248", v23251);
    const v23252 = try s.array();
    const v23253 = try o.lookup(&s, frame, "binding23246");
    try o.append(&s, v23252, v23253);
    const v23254 = try o.lookup(&s, frame, "binding23247");
    try o.append(&s, v23252, v23254);
    const v23255 = try o.lookup(&s, frame, "binding23248");
    try o.append(&s, v23252, v23255);
    return c.JS_DupValue(e.context, v23252);
}
fn body23244C(ctx: ?*c.JSContext, receiver: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const e = Engine.fromContext(ctx.?);
    return body23244(e, receiver, if (argc > 0) argv[0..@intCast(argc)] else &.{}, roots[0..2]) catch |err| sdk.fail(e, err);
}
fn body23258(e: *Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    _ = roots[0];
    const frame = try o.frame(&s, roots[1]);
    _ = try o.lookup(&s, frame, "@this");
    const v23262 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding23260", v23262);
    const v23263 = if (args.len > 1) args[1] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding23261", v23263);
    const v23264 = try s.array();
    const v23265 = try s.object();
    try o.append(&s, v23264, v23265);
    const v23266 = try o.lookup(&s, frame, "binding23260");
    try o.append(&s, v23264, v23266);
    const v23267 = try o.lookup(&s, frame, "binding23261");
    try o.append(&s, v23264, v23267);
    return c.JS_DupValue(e.context, v23264);
}
fn body23258C(ctx: ?*c.JSContext, receiver: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const e = Engine.fromContext(ctx.?);
    return body23258(e, receiver, if (argc > 0) argv[0..@intCast(argc)] else &.{}, roots[0..2]) catch |err| sdk.fail(e, err);
}
fn body23229(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v23234 = try o.rest(&s, args, 0);
    try o.assign(&s, frame, "binding23230", v23234);
    const v23238 = try o.importValue(&s, graph, "system/arguments/index.mjs", "Arguments");
    const v23239 = try s.text("Match");
    const v23240 = try s.own(try js.getKey(e, v23238, v23239));
    const v23241 = try o.lookup(&s, frame, "binding23230");
    const v23242 = try s.object();
    const v23243 = try s.text("3");
    const v23256 = try o.arrow(&s, "3", 3, body23244C, &.{ graph, frame });
    try o.defineKey(&s, v23242, v23243, v23256);
    const v23257 = try s.text("2");
    const v23268 = try o.arrow(&s, "2", 2, body23258C, &.{ graph, frame });
    try o.defineKey(&s, v23242, v23257, v23268);
    const v23269 = try o.call(&s, @src(), v23240, v23238, &.{ v23241, v23242 });
    var destructure23270 = try o.iterator(e, v23269);
    defer destructure23270.deinit();
    errdefer destructure23270.closePreserving();
    const v23271 = try s.own(if (destructure23270.closed) c.pi_js_undefined() else (try destructure23270.next()) orelse c.pi_js_undefined());
    try o.assign(&s, frame, "binding23235", v23271);
    const v23272 = try s.own(if (destructure23270.closed) c.pi_js_undefined() else (try destructure23270.next()) orelse c.pi_js_undefined());
    try o.assign(&s, frame, "binding23236", v23272);
    const v23273 = try s.own(if (destructure23270.closed) c.pi_js_undefined() else (try destructure23270.next()) orelse c.pi_js_undefined());
    try o.assign(&s, frame, "binding23237", v23273);
    try destructure23270.close();
    const v23274 = try o.importValue(&s, graph, "schema/index.mjs", "Check");
    const v23275 = try o.lookup(&s, frame, "binding23235");
    const v23276 = try o.lookup(&s, frame, "binding23236");
    const v23277 = try o.lookup(&s, frame, "binding23237");
    const v23278 = try o.call(&s, @src(), v23274, c.pi_js_undefined(), &.{ v23275, v23276, v23277 });
    return c.JS_DupValue(e.context, v23278);
}
