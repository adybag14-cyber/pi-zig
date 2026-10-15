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
    const namespace = try s.get(modules, "schema/types/dependentRequired.mjs");
    const frame = try o.frame(&s, c.pi_js_null());
    try s.put(frame, "@this", c.pi_js_undefined());
    try s.put(try s.get(graph, "frames"), "schema/types/dependentRequired.mjs", frame);
    const bindings = try s.object();
    try s.put(try s.get(graph, "bindings"), "schema/types/dependentRequired.mjs", bindings);
    const v21394 = try s.own(try ordinary.create(e, "IsDependentRequired", 1, body21338, &.{ graph, frame }));
    try o.assign(&s, frame, "binding21337", v21394);
    const v21395 = try o.lookup(&s, frame, "binding21337");
    try s.put(namespace, "IsDependentRequired", v21395);
    const v21396 = try o.lookup(&s, frame, "binding21337");
    try s.put(namespace, "IsDependentRequired", v21396);
    try s.put(bindings, "IsDependentRequired", try s.text("binding21337"));
}
fn body21381(e: *Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    _ = try o.lookup(&s, frame, "@this");
    const v21384 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding21383", v21384);
    const v21385 = try o.importValue(&s, graph, "guard/index.mjs", "Guard");
    const v21386 = try s.text("IsString");
    const v21387 = try s.own(try js.getKey(e, v21385, v21386));
    const v21388 = try o.lookup(&s, frame, "binding21383");
    const v21389 = try s.call(v21387, v21385, &.{v21388});
    return c.JS_DupValue(e.context, v21389);
}
fn body21381C(ctx: ?*c.JSContext, receiver: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const e = Engine.fromContext(ctx.?);
    return body21381(e, receiver, if (argc > 0) argv[0..@intCast(argc)] else &.{}, roots[0..2]) catch |err| sdk.fail(e, err);
}
fn body21367(e: *Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    _ = try o.lookup(&s, frame, "@this");
    const v21370 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding21369", v21370);
    const v21371 = try o.importValue(&s, graph, "guard/index.mjs", "Guard");
    const v21372 = try s.text("IsArray");
    const v21373 = try s.own(try js.getKey(e, v21371, v21372));
    const v21374 = try o.lookup(&s, frame, "binding21369");
    const v21375 = try s.call(v21373, v21371, &.{v21374});
    const v21377 = logical21376: {
        if (!s.truthy(v21375)) break :logical21376 v21375;
        const v21378 = try o.lookup(&s, frame, "binding21369");
        const v21379 = try s.text("every");
        const v21380 = try s.own(try js.getKey(e, v21378, v21379));
        const v21390 = try o.arrow(&s, "", 1, body21381C, &.{ graph, frame });
        const v21391 = try s.call(v21380, v21378, &.{v21390});
        break :logical21376 v21391;
    };
    return c.JS_DupValue(e.context, v21377);
}
fn body21367C(ctx: ?*c.JSContext, receiver: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const e = Engine.fromContext(ctx.?);
    return body21367(e, receiver, if (argc > 0) argv[0..@intCast(argc)] else &.{}, roots[0..2]) catch |err| sdk.fail(e, err);
}
fn body21338(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v21340 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding21339", v21340);
    const v21341 = try o.importValue(&s, graph, "guard/index.mjs", "Guard");
    const v21342 = try s.text("HasPropertyKey");
    const v21343 = try s.own(try js.getKey(e, v21341, v21342));
    const v21344 = try o.lookup(&s, frame, "binding21339");
    const v21345 = try s.text("dependentRequired");
    const v21346 = try s.call(v21343, v21341, &.{ v21344, v21345 });
    const v21348 = logical21347: {
        if (!s.truthy(v21346)) break :logical21347 v21346;
        const v21349 = try o.importValue(&s, graph, "guard/index.mjs", "Guard");
        const v21350 = try s.text("IsObject");
        const v21351 = try s.own(try js.getKey(e, v21349, v21350));
        const v21352 = try o.lookup(&s, frame, "binding21339");
        const v21353 = try s.text("dependentRequired");
        const v21354 = try s.own(try js.getKey(e, v21352, v21353));
        const v21355 = try s.call(v21351, v21349, &.{v21354});
        break :logical21347 v21355;
    };
    const v21357 = logical21356: {
        if (!s.truthy(v21348)) break :logical21356 v21348;
        const v21358 = try s.global("Object");
        const v21359 = try s.text("values");
        const v21360 = try s.own(try js.getKey(e, v21358, v21359));
        const v21361 = try o.lookup(&s, frame, "binding21339");
        const v21362 = try s.text("dependentRequired");
        const v21363 = try s.own(try js.getKey(e, v21361, v21362));
        const v21364 = try s.call(v21360, v21358, &.{v21363});
        const v21365 = try s.text("every");
        const v21366 = try s.own(try js.getKey(e, v21364, v21365));
        const v21392 = try o.arrow(&s, "", 1, body21367C, &.{ graph, frame });
        const v21393 = try s.call(v21366, v21364, &.{v21392});
        break :logical21356 v21393;
    };
    return c.JS_DupValue(e.context, v21357);
}
