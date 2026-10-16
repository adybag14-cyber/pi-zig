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
    const namespace = try s.get(modules, "schema/types/required.mjs");
    const frame = try o.frame(&s, c.pi_js_null());
    try s.put(frame, "@this", c.pi_js_undefined());
    try s.put(try s.get(graph, "frames"), "schema/types/required.mjs", frame);
    const bindings = try s.object();
    try s.put(try s.get(graph, "bindings"), "schema/types/required.mjs", bindings);
    const v22363 = try s.own(try ordinary.create(e, "IsRequired", 1, body22327, &.{ graph, frame }));
    try o.assign(&s, frame, "binding22326", v22363);
    const v22364 = try o.lookup(&s, frame, "binding22326");
    try s.put(namespace, "IsRequired", v22364);
    const v22365 = try o.lookup(&s, frame, "binding22326");
    try s.put(namespace, "IsRequired", v22365);
    try s.put(bindings, "IsRequired", try s.text("binding22326"));
}
fn body22352(e: *Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    _ = try o.lookup(&s, frame, "@this");
    const v22355 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding22354", v22355);
    const v22356 = try o.importValue(&s, graph, "guard/index.mjs", "Guard");
    const v22357 = try s.text("IsString");
    const v22358 = try s.own(try js.getKey(e, v22356, v22357));
    const v22359 = try o.lookup(&s, frame, "binding22354");
    const v22360 = try s.call(v22358, v22356, &.{v22359});
    return c.JS_DupValue(e.context, v22360);
}
fn body22352C(ctx: ?*c.JSContext, receiver: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const e = Engine.fromContext(ctx.?);
    return body22352(e, receiver, if (argc > 0) argv[0..@intCast(argc)] else &.{}, roots[0..2]) catch |err| sdk.fail(e, err);
}
fn body22327(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v22329 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding22328", v22329);
    const v22330 = try o.importValue(&s, graph, "guard/index.mjs", "Guard");
    const v22331 = try s.text("HasPropertyKey");
    const v22332 = try s.own(try js.getKey(e, v22330, v22331));
    const v22333 = try o.lookup(&s, frame, "binding22328");
    const v22334 = try s.text("required");
    const v22335 = try s.call(v22332, v22330, &.{ v22333, v22334 });
    const v22337 = logical22336: {
        if (!s.truthy(v22335)) break :logical22336 v22335;
        const v22338 = try o.importValue(&s, graph, "guard/index.mjs", "Guard");
        const v22339 = try s.text("IsArray");
        const v22340 = try s.own(try js.getKey(e, v22338, v22339));
        const v22341 = try o.lookup(&s, frame, "binding22328");
        const v22342 = try s.text("required");
        const v22343 = try s.own(try js.getKey(e, v22341, v22342));
        const v22344 = try s.call(v22340, v22338, &.{v22343});
        break :logical22336 v22344;
    };
    const v22346 = logical22345: {
        if (!s.truthy(v22337)) break :logical22345 v22337;
        const v22347 = try o.lookup(&s, frame, "binding22328");
        const v22348 = try s.text("required");
        const v22349 = try s.own(try js.getKey(e, v22347, v22348));
        const v22350 = try s.text("every");
        const v22351 = try s.own(try js.getKey(e, v22349, v22350));
        const v22361 = try o.arrow(&s, "", 1, body22352C, &.{ graph, frame });
        const v22362 = try s.call(v22351, v22349, &.{v22361});
        break :logical22345 v22362;
    };
    return c.JS_DupValue(e.context, v22346);
}
