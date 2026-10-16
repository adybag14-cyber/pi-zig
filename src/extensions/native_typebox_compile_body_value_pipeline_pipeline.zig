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
    const namespace = try s.get(modules, "value/pipeline/pipeline.mjs");
    const frame = try o.frame(&s, c.pi_js_null());
    try s.put(frame, "@this", c.pi_js_undefined());
    try s.put(try s.get(graph, "frames"), "value/pipeline/pipeline.mjs", frame);
    const bindings = try s.object();
    try s.put(try s.get(graph, "bindings"), "value/pipeline/pipeline.mjs", bindings);
    const v30567 = try s.own(try ordinary.create(e, "Pipeline", 1, body30500, &.{ graph, frame }));
    try o.assign(&s, frame, "binding30499", v30567);
    const v30568 = try o.lookup(&s, frame, "binding30499");
    try s.put(namespace, "Pipeline", v30568);
    const v30569 = try o.lookup(&s, frame, "binding30499");
    try s.put(namespace, "Pipeline", v30569);
    try s.put(bindings, "Pipeline", try s.text("binding30499"));
}
fn body30519(e: *Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    _ = roots[0];
    const frame = try o.frame(&s, roots[1]);
    _ = try o.lookup(&s, frame, "@this");
    const v30524 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding30521", v30524);
    const v30525 = if (args.len > 1) args[1] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding30522", v30525);
    const v30526 = if (args.len > 2) args[2] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding30523", v30526);
    const v30527 = try s.array();
    const v30528 = try o.lookup(&s, frame, "binding30521");
    try o.append(&s, v30527, v30528);
    const v30529 = try o.lookup(&s, frame, "binding30522");
    try o.append(&s, v30527, v30529);
    const v30530 = try o.lookup(&s, frame, "binding30523");
    try o.append(&s, v30527, v30530);
    return c.JS_DupValue(e.context, v30527);
}
fn body30519C(ctx: ?*c.JSContext, receiver: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const e = Engine.fromContext(ctx.?);
    return body30519(e, receiver, if (argc > 0) argv[0..@intCast(argc)] else &.{}, roots[0..2]) catch |err| sdk.fail(e, err);
}
fn body30533(e: *Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    _ = roots[0];
    const frame = try o.frame(&s, roots[1]);
    _ = try o.lookup(&s, frame, "@this");
    const v30537 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding30535", v30537);
    const v30538 = if (args.len > 1) args[1] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding30536", v30538);
    const v30539 = try s.array();
    const v30540 = try s.object();
    try o.append(&s, v30539, v30540);
    const v30541 = try o.lookup(&s, frame, "binding30535");
    try o.append(&s, v30539, v30541);
    const v30542 = try o.lookup(&s, frame, "binding30536");
    try o.append(&s, v30539, v30542);
    return c.JS_DupValue(e.context, v30539);
}
fn body30533C(ctx: ?*c.JSContext, receiver: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const e = Engine.fromContext(ctx.?);
    return body30533(e, receiver, if (argc > 0) argv[0..@intCast(argc)] else &.{}, roots[0..2]) catch |err| sdk.fail(e, err);
}
fn body30552(e: *Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    _ = roots[0];
    const frame = try o.frame(&s, roots[1]);
    _ = try o.lookup(&s, frame, "@this");
    const v30556 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding30554", v30556);
    const v30557 = if (args.len > 1) args[1] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding30555", v30557);
    const v30558 = try o.lookup(&s, frame, "binding30555");
    const v30559 = try o.lookup(&s, frame, "binding30510");
    const v30560 = try o.lookup(&s, frame, "binding30511");
    const v30561 = try o.lookup(&s, frame, "binding30554");
    const v30562 = try s.call(v30558, c.pi_js_undefined(), &.{ v30559, v30560, v30561 });
    return c.JS_DupValue(e.context, v30562);
}
fn body30552C(ctx: ?*c.JSContext, receiver: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const e = Engine.fromContext(ctx.?);
    return body30552(e, receiver, if (argc > 0) argv[0..@intCast(argc)] else &.{}, roots[0..2]) catch |err| sdk.fail(e, err);
}
fn body30503(e: *Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    _ = try o.lookup(&s, frame, "@this");
    const v30509 = try o.rest(&s, args, 0);
    try o.assign(&s, frame, "binding30505", v30509);
    const v30513 = try o.importValue(&s, graph, "system/arguments/index.mjs", "Arguments");
    const v30514 = try s.text("Match");
    const v30515 = try s.own(try js.getKey(e, v30513, v30514));
    const v30516 = try o.lookup(&s, frame, "binding30505");
    const v30517 = try s.object();
    const v30518 = try s.text("3");
    const v30531 = try o.arrow(&s, "3", 3, body30519C, &.{ graph, frame });
    try o.defineKey(&s, v30517, v30518, v30531);
    const v30532 = try s.text("2");
    const v30543 = try o.arrow(&s, "2", 2, body30533C, &.{ graph, frame });
    try o.defineKey(&s, v30517, v30532, v30543);
    const v30544 = try s.call(v30515, v30513, &.{ v30516, v30517 });
    var destructure30545 = try o.iterator(e, v30544);
    defer destructure30545.deinit();
    errdefer destructure30545.closePreserving();
    const v30546 = try s.own(if (destructure30545.closed) c.pi_js_undefined() else (try destructure30545.next()) orelse c.pi_js_undefined());
    try o.assign(&s, frame, "binding30510", v30546);
    const v30547 = try s.own(if (destructure30545.closed) c.pi_js_undefined() else (try destructure30545.next()) orelse c.pi_js_undefined());
    try o.assign(&s, frame, "binding30511", v30547);
    const v30548 = try s.own(if (destructure30545.closed) c.pi_js_undefined() else (try destructure30545.next()) orelse c.pi_js_undefined());
    try o.assign(&s, frame, "binding30512", v30548);
    try destructure30545.close();
    const v30549 = try o.lookup(&s, frame, "binding30501");
    const v30550 = try s.text("reduce");
    const v30551 = try s.own(try js.getKey(e, v30549, v30550));
    const v30563 = try o.arrow(&s, "", 2, body30552C, &.{ graph, frame });
    const v30564 = try o.lookup(&s, frame, "binding30512");
    const v30565 = try s.call(v30551, v30549, &.{ v30563, v30564 });
    return c.JS_DupValue(e.context, v30565);
}
fn body30503C(ctx: ?*c.JSContext, receiver: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const e = Engine.fromContext(ctx.?);
    return body30503(e, receiver, if (argc > 0) argv[0..@intCast(argc)] else &.{}, roots[0..2]) catch |err| sdk.fail(e, err);
}
fn body30500(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v30502 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding30501", v30502);
    const v30566 = try o.arrow(&s, "", 0, body30503C, &.{ graph, frame });
    return c.JS_DupValue(e.context, v30566);
}
