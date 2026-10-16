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
    const namespace = try s.get(modules, "value/errors/errors.mjs");
    const frame = try o.frame(&s, c.pi_js_null());
    try s.put(frame, "@this", c.pi_js_undefined());
    try s.put(try s.get(graph, "frames"), "value/errors/errors.mjs", frame);
    const bindings = try s.object();
    try s.put(try s.get(graph, "bindings"), "value/errors/errors.mjs", bindings);
    const v30297 = try s.own(try ordinary.create(e, "Errors", 0, body30239, &.{ graph, frame }));
    try o.assign(&s, frame, "binding30238", v30297);
    const v30298 = try o.lookup(&s, frame, "binding30238");
    try s.put(namespace, "Errors", v30298);
    const v30299 = try o.lookup(&s, frame, "binding30238");
    try s.put(namespace, "Errors", v30299);
    try s.put(bindings, "Errors", try s.text("binding30238"));
}
fn body30258(e: *Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    _ = roots[0];
    const frame = try o.frame(&s, roots[1]);
    _ = try o.lookup(&s, frame, "@this");
    const v30263 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding30260", v30263);
    const v30264 = if (args.len > 1) args[1] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding30261", v30264);
    const v30265 = if (args.len > 2) args[2] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding30262", v30265);
    const v30266 = try s.array();
    const v30267 = try o.lookup(&s, frame, "binding30260");
    try o.append(&s, v30266, v30267);
    const v30268 = try o.lookup(&s, frame, "binding30261");
    try o.append(&s, v30266, v30268);
    const v30269 = try o.lookup(&s, frame, "binding30262");
    try o.append(&s, v30266, v30269);
    return c.JS_DupValue(e.context, v30266);
}
fn body30258C(ctx: ?*c.JSContext, receiver: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const e = Engine.fromContext(ctx.?);
    return body30258(e, receiver, if (argc > 0) argv[0..@intCast(argc)] else &.{}, roots[0..2]) catch |err| sdk.fail(e, err);
}
fn body30272(e: *Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    _ = roots[0];
    const frame = try o.frame(&s, roots[1]);
    _ = try o.lookup(&s, frame, "@this");
    const v30276 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding30274", v30276);
    const v30277 = if (args.len > 1) args[1] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding30275", v30277);
    const v30278 = try s.array();
    const v30279 = try s.object();
    try o.append(&s, v30278, v30279);
    const v30280 = try o.lookup(&s, frame, "binding30274");
    try o.append(&s, v30278, v30280);
    const v30281 = try o.lookup(&s, frame, "binding30275");
    try o.append(&s, v30278, v30281);
    return c.JS_DupValue(e.context, v30278);
}
fn body30272C(ctx: ?*c.JSContext, receiver: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const e = Engine.fromContext(ctx.?);
    return body30272(e, receiver, if (argc > 0) argv[0..@intCast(argc)] else &.{}, roots[0..2]) catch |err| sdk.fail(e, err);
}
fn body30239(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v30246 = try o.rest(&s, args, 0);
    try o.assign(&s, frame, "binding30240", v30246);
    const v30252 = try o.importValue(&s, graph, "system/arguments/index.mjs", "Arguments");
    const v30253 = try s.text("Match");
    const v30254 = try s.own(try js.getKey(e, v30252, v30253));
    const v30255 = try o.lookup(&s, frame, "binding30240");
    const v30256 = try s.object();
    const v30257 = try s.text("3");
    const v30270 = try o.arrow(&s, "3", 3, body30258C, &.{ graph, frame });
    try o.defineKey(&s, v30256, v30257, v30270);
    const v30271 = try s.text("2");
    const v30282 = try o.arrow(&s, "2", 2, body30272C, &.{ graph, frame });
    try o.defineKey(&s, v30256, v30271, v30282);
    const v30283 = try s.call(v30254, v30252, &.{ v30255, v30256 });
    var destructure30284 = try o.iterator(e, v30283);
    defer destructure30284.deinit();
    errdefer destructure30284.closePreserving();
    const v30285 = try s.own(if (destructure30284.closed) c.pi_js_undefined() else (try destructure30284.next()) orelse c.pi_js_undefined());
    try o.assign(&s, frame, "binding30247", v30285);
    const v30286 = try s.own(if (destructure30284.closed) c.pi_js_undefined() else (try destructure30284.next()) orelse c.pi_js_undefined());
    try o.assign(&s, frame, "binding30248", v30286);
    const v30287 = try s.own(if (destructure30284.closed) c.pi_js_undefined() else (try destructure30284.next()) orelse c.pi_js_undefined());
    try o.assign(&s, frame, "binding30249", v30287);
    try destructure30284.close();
    const v30288 = try o.importValue(&s, graph, "schema/index.mjs", "Errors");
    const v30289 = try o.lookup(&s, frame, "binding30247");
    const v30290 = try o.lookup(&s, frame, "binding30248");
    const v30291 = try o.lookup(&s, frame, "binding30249");
    const v30292 = try s.call(v30288, c.pi_js_undefined(), &.{ v30289, v30290, v30291 });
    var destructure30293 = try o.iterator(e, v30292);
    defer destructure30293.deinit();
    errdefer destructure30293.closePreserving();
    const v30294 = try s.own(if (destructure30293.closed) c.pi_js_undefined() else (try destructure30293.next()) orelse c.pi_js_undefined());
    try o.assign(&s, frame, "binding30250", v30294);
    const v30295 = try s.own(if (destructure30293.closed) c.pi_js_undefined() else (try destructure30293.next()) orelse c.pi_js_undefined());
    try o.assign(&s, frame, "binding30251", v30295);
    try destructure30293.close();
    const v30296 = try o.lookup(&s, frame, "binding30251");
    return c.JS_DupValue(e.context, v30296);
}
