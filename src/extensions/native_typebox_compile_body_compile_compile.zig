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
    const namespace = try s.get(modules, "compile/compile.mjs");
    const frame = try o.frame(&s, c.pi_js_null());
    try s.put(frame, "@this", c.pi_js_undefined());
    try s.put(try s.get(graph, "frames"), "compile/compile.mjs", frame);
    const bindings = try s.object();
    try s.put(try s.get(graph, "bindings"), "compile/compile.mjs", bindings);
    const v261 = try s.own(try ordinary.create(e, "Compile", 0, body221, &.{ graph, frame }));
    try o.assign(&s, frame, "binding220", v261);
    const v262 = try o.lookup(&s, frame, "binding220");
    try s.put(namespace, "Compile", v262);
    const v263 = try o.lookup(&s, frame, "binding220");
    try s.put(namespace, "Compile", v263);
    try s.put(bindings, "Compile", try s.text("binding220"));
}
fn body234(e: *Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    _ = roots[0];
    const frame = try o.frame(&s, roots[1]);
    _ = try o.lookup(&s, frame, "@this");
    const v238 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding236", v238);
    const v239 = if (args.len > 1) args[1] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding237", v239);
    const v240 = try s.array();
    const v241 = try o.lookup(&s, frame, "binding236");
    try o.append(&s, v240, v241);
    const v242 = try o.lookup(&s, frame, "binding237");
    try o.append(&s, v240, v242);
    return c.JS_DupValue(e.context, v240);
}
fn body234C(ctx: ?*c.JSContext, receiver: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const e = Engine.fromContext(ctx.?);
    return body234(e, receiver, if (argc > 0) argv[0..@intCast(argc)] else &.{}, roots[0..2]) catch |err| sdk.fail(e, err);
}
fn body245(e: *Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    _ = roots[0];
    const frame = try o.frame(&s, roots[1]);
    _ = try o.lookup(&s, frame, "@this");
    const v248 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding247", v248);
    const v249 = try s.array();
    const v250 = try s.object();
    try o.append(&s, v249, v250);
    const v251 = try o.lookup(&s, frame, "binding247");
    try o.append(&s, v249, v251);
    return c.JS_DupValue(e.context, v249);
}
fn body245C(ctx: ?*c.JSContext, receiver: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const e = Engine.fromContext(ctx.?);
    return body245(e, receiver, if (argc > 0) argv[0..@intCast(argc)] else &.{}, roots[0..2]) catch |err| sdk.fail(e, err);
}
fn body221(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v225 = try o.rest(&s, args, 0);
    try o.assign(&s, frame, "binding222", v225);
    const v228 = try o.importValue(&s, graph, "system/arguments/index.mjs", "Arguments");
    const v229 = try s.text("Match");
    const v230 = try s.own(try js.getKey(e, v228, v229));
    const v231 = try o.lookup(&s, frame, "binding222");
    const v232 = try s.object();
    const v233 = try s.text("2");
    const v243 = try o.arrow(&s, "2", 2, body234C, &.{ graph, frame });
    try o.defineKey(&s, v232, v233, v243);
    const v244 = try s.text("1");
    const v252 = try o.arrow(&s, "1", 1, body245C, &.{ graph, frame });
    try o.defineKey(&s, v232, v244, v252);
    const v253 = try s.call(v230, v228, &.{ v231, v232 });
    var destructure254 = try o.iterator(e, v253);
    defer destructure254.deinit();
    errdefer destructure254.closePreserving();
    const v255 = try s.own(if (destructure254.closed) c.pi_js_undefined() else (try destructure254.next()) orelse c.pi_js_undefined());
    try o.assign(&s, frame, "binding226", v255);
    const v256 = try s.own(if (destructure254.closed) c.pi_js_undefined() else (try destructure254.next()) orelse c.pi_js_undefined());
    try o.assign(&s, frame, "binding227", v256);
    try destructure254.close();
    const v257 = try o.importValue(&s, graph, "compile/validator.mjs", "Validator");
    const v258 = try o.lookup(&s, frame, "binding226");
    const v259 = try o.lookup(&s, frame, "binding227");
    const v260 = try o.construct(&s, v257, &.{ v258, v259 });
    return c.JS_DupValue(e.context, v260);
}
