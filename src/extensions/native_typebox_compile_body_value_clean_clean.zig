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
    const namespace = try s.get(modules, "value/clean/clean.mjs");
    const frame = try o.frame(&s, c.pi_js_null());
    try s.put(frame, "@this", c.pi_js_undefined());
    try s.put(try s.get(graph, "frames"), "value/clean/clean.mjs", frame);
    const bindings = try s.object();
    try s.put(try s.get(graph, "bindings"), "value/clean/clean.mjs", bindings);
    const v23368 = try s.own(try ordinary.create(e, "Clean", 0, body23304, &.{ graph, frame }));
    try o.assign(&s, frame, "binding23303", v23368);
    const v23369 = try o.lookup(&s, frame, "binding23303");
    try s.put(namespace, "Clean", v23369);
    const v23370 = try o.lookup(&s, frame, "binding23303");
    try s.put(namespace, "Clean", v23370);
    try s.put(bindings, "Clean", try s.text("binding23303"));
}
fn body23321(e: *Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    _ = roots[0];
    const frame = try o.frame(&s, roots[1]);
    _ = try o.lookup(&s, frame, "@this");
    const v23326 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding23323", v23326);
    const v23327 = if (args.len > 1) args[1] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding23324", v23327);
    const v23328 = if (args.len > 2) args[2] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding23325", v23328);
    const v23329 = try s.array();
    const v23330 = try o.lookup(&s, frame, "binding23323");
    try o.append(&s, v23329, v23330);
    const v23331 = try o.lookup(&s, frame, "binding23324");
    try o.append(&s, v23329, v23331);
    const v23332 = try o.lookup(&s, frame, "binding23325");
    try o.append(&s, v23329, v23332);
    return c.JS_DupValue(e.context, v23329);
}
fn body23321C(ctx: ?*c.JSContext, receiver: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const e = Engine.fromContext(ctx.?);
    return body23321(e, receiver, if (argc > 0) argv[0..@intCast(argc)] else &.{}, roots[0..2]) catch |err| sdk.fail(e, err);
}
fn body23335(e: *Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    _ = roots[0];
    const frame = try o.frame(&s, roots[1]);
    _ = try o.lookup(&s, frame, "@this");
    const v23339 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding23337", v23339);
    const v23340 = if (args.len > 1) args[1] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding23338", v23340);
    const v23341 = try s.array();
    const v23342 = try s.object();
    try o.append(&s, v23341, v23342);
    const v23343 = try o.lookup(&s, frame, "binding23337");
    try o.append(&s, v23341, v23343);
    const v23344 = try o.lookup(&s, frame, "binding23338");
    try o.append(&s, v23341, v23344);
    return c.JS_DupValue(e.context, v23341);
}
fn body23335C(ctx: ?*c.JSContext, receiver: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const e = Engine.fromContext(ctx.?);
    return body23335(e, receiver, if (argc > 0) argv[0..@intCast(argc)] else &.{}, roots[0..2]) catch |err| sdk.fail(e, err);
}
fn body23304(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v23310 = try o.rest(&s, args, 0);
    try o.assign(&s, frame, "binding23305", v23310);
    const v23315 = try o.importValue(&s, graph, "system/index.mjs", "Arguments");
    const v23316 = try s.text("Match");
    const v23317 = try s.own(try js.getKey(e, v23315, v23316));
    const v23318 = try o.lookup(&s, frame, "binding23305");
    const v23319 = try s.object();
    const v23320 = try s.text("3");
    const v23333 = try o.arrow(&s, "3", 3, body23321C, &.{ graph, frame });
    try o.defineKey(&s, v23319, v23320, v23333);
    const v23334 = try s.text("2");
    const v23345 = try o.arrow(&s, "2", 2, body23335C, &.{ graph, frame });
    try o.defineKey(&s, v23319, v23334, v23345);
    const v23346 = try s.call(v23317, v23315, &.{ v23318, v23319 });
    var destructure23347 = try o.iterator(e, v23346);
    defer destructure23347.deinit();
    errdefer destructure23347.closePreserving();
    const v23348 = try s.own(if (destructure23347.closed) c.pi_js_undefined() else (try destructure23347.next()) orelse c.pi_js_undefined());
    try o.assign(&s, frame, "binding23311", v23348);
    const v23349 = try s.own(if (destructure23347.closed) c.pi_js_undefined() else (try destructure23347.next()) orelse c.pi_js_undefined());
    try o.assign(&s, frame, "binding23312", v23349);
    const v23350 = try s.own(if (destructure23347.closed) c.pi_js_undefined() else (try destructure23347.next()) orelse c.pi_js_undefined());
    try o.assign(&s, frame, "binding23313", v23350);
    try destructure23347.close();
    const v23351 = try o.importValue(&s, graph, "system/index.mjs", "Settings");
    const v23352 = try s.text("Get");
    const v23353 = try s.own(try js.getKey(e, v23351, v23352));
    const v23354 = try s.call(v23353, v23351, &.{});
    const v23355 = try s.text("unionPrioritySort");
    const v23356 = try s.own(try js.getKey(e, v23354, v23355));
    const v23358 = conditional23357: {
        if (s.truthy(v23356)) {
            const v23359 = try o.importValue(&s, graph, "value/shared/union_priority_sort.mjs", "UnionPrioritySort");
            const v23360 = try o.lookup(&s, frame, "binding23312");
            const v23361 = try s.call(v23359, c.pi_js_undefined(), &.{v23360});
            break :conditional23357 v23361;
        } else {
            const v23362 = try o.lookup(&s, frame, "binding23312");
            break :conditional23357 v23362;
        }
    };
    try o.assign(&s, frame, "binding23314", v23358);
    const v23363 = try o.importValue(&s, graph, "value/clean/from_type.mjs", "FromType");
    const v23364 = try o.lookup(&s, frame, "binding23311");
    const v23365 = try o.lookup(&s, frame, "binding23314");
    const v23366 = try o.lookup(&s, frame, "binding23313");
    const v23367 = try s.call(v23363, c.pi_js_undefined(), &.{ v23364, v23365, v23366 });
    return c.JS_DupValue(e.context, v23367);
}
