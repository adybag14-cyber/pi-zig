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
    const namespace = try s.get(modules, "schema/types/dependentSchemas.mjs");
    const frame = try o.frame(&s, c.pi_js_null());
    try s.put(frame, "@this", c.pi_js_undefined());
    try s.put(try s.get(graph, "frames"), "schema/types/dependentSchemas.mjs", frame);
    const bindings = try s.object();
    try s.put(try s.get(graph, "bindings"), "schema/types/dependentSchemas.mjs", bindings);
    const v21436 = try s.own(try ordinary.create(e, "IsDependentSchemas", 1, body21398, &.{ graph, frame }));
    try o.assign(&s, frame, "binding21397", v21436);
    const v21437 = try o.lookup(&s, frame, "binding21397");
    try s.put(namespace, "IsDependentSchemas", v21437);
    const v21438 = try o.lookup(&s, frame, "binding21397");
    try s.put(namespace, "IsDependentSchemas", v21438);
    try s.put(bindings, "IsDependentSchemas", try s.text("binding21397"));
}
fn body21427(e: *Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    _ = try o.lookup(&s, frame, "@this");
    const v21430 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding21429", v21430);
    const v21431 = try o.importValue(&s, graph, "schema/types/schema.mjs", "IsSchema");
    const v21432 = try o.lookup(&s, frame, "binding21429");
    const v21433 = try o.call(&s, @src(), v21431, c.pi_js_undefined(), &.{v21432});
    return c.JS_DupValue(e.context, v21433);
}
fn body21427C(ctx: ?*c.JSContext, receiver: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const e = Engine.fromContext(ctx.?);
    return body21427(e, receiver, if (argc > 0) argv[0..@intCast(argc)] else &.{}, roots[0..2]) catch |err| sdk.fail(e, err);
}
fn body21398(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v21400 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding21399", v21400);
    const v21401 = try o.importValue(&s, graph, "guard/index.mjs", "Guard");
    const v21402 = try s.text("HasPropertyKey");
    const v21403 = try s.own(try js.getKey(e, v21401, v21402));
    const v21404 = try o.lookup(&s, frame, "binding21399");
    const v21405 = try s.text("dependentSchemas");
    const v21406 = try o.call(&s, @src(), v21403, v21401, &.{ v21404, v21405 });
    const v21408 = logical21407: {
        if (!s.truthy(v21406)) break :logical21407 v21406;
        const v21409 = try o.importValue(&s, graph, "guard/index.mjs", "Guard");
        const v21410 = try s.text("IsObject");
        const v21411 = try s.own(try js.getKey(e, v21409, v21410));
        const v21412 = try o.lookup(&s, frame, "binding21399");
        const v21413 = try s.text("dependentSchemas");
        const v21414 = try s.own(try js.getKey(e, v21412, v21413));
        const v21415 = try o.call(&s, @src(), v21411, v21409, &.{v21414});
        break :logical21407 v21415;
    };
    const v21417 = logical21416: {
        if (!s.truthy(v21408)) break :logical21416 v21408;
        const v21418 = try s.global("Object");
        const v21419 = try s.text("values");
        const v21420 = try s.own(try js.getKey(e, v21418, v21419));
        const v21421 = try o.lookup(&s, frame, "binding21399");
        const v21422 = try s.text("dependentSchemas");
        const v21423 = try s.own(try js.getKey(e, v21421, v21422));
        const v21424 = try o.call(&s, @src(), v21420, v21418, &.{v21423});
        const v21425 = try s.text("every");
        const v21426 = try s.own(try js.getKey(e, v21424, v21425));
        const v21434 = try o.arrow(&s, "", 1, body21427C, &.{ graph, frame });
        const v21435 = try o.call(&s, @src(), v21426, v21424, &.{v21434});
        break :logical21416 v21435;
    };
    return c.JS_DupValue(e.context, v21417);
}
