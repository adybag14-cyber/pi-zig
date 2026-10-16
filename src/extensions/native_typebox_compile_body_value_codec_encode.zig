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
    const namespace = try s.get(modules, "value/codec/encode.mjs");
    const frame = try o.frame(&s, c.pi_js_null());
    try s.put(frame, "@this", c.pi_js_undefined());
    try s.put(try s.get(graph, "frames"), "value/codec/encode.mjs", frame);
    const bindings = try s.object();
    try s.put(try s.get(graph, "bindings"), "value/codec/encode.mjs", bindings);
    const v24268 = try s.own(try ordinary.create(e, "Assert", 3, body24247, &.{ graph, frame }));
    try o.assign(&s, frame, "binding24243", v24268);
    const v24296 = try s.own(try ordinary.create(e, "EncodeUnsafe", 3, body24269, &.{ graph, frame }));
    try o.assign(&s, frame, "binding24244", v24296);
    const v24347 = try s.own(try ordinary.create(e, "Encode", 0, body24297, &.{ graph, frame }));
    try o.assign(&s, frame, "binding24246", v24347);
    const v24348 = try o.lookup(&s, frame, "binding24244");
    try s.put(namespace, "EncodeUnsafe", v24348);
    const v24349 = try o.lookup(&s, frame, "binding24246");
    try s.put(namespace, "Encode", v24349);
    const v24350 = try o.importValue(&s, graph, "value/assert/index.mjs", "AssertError");
    const v24351 = try o.derivedPrototype(&s, v24350);
    const v24360 = try s.own(try class.constructor(e, "EncodeError", 2, v24351, constructor24352, &.{ graph, frame, v24350 }));
    try o.setPrototype(&s, v24360, v24350);
    try o.assign(&s, frame, "binding24242", v24360);
    const v24361 = try o.importValue(&s, graph, "value/pipeline/index.mjs", "Pipeline");
    const v24362 = try s.array();
    const v24374 = try o.arrow(&s, "", 3, body24363C, &.{ graph, frame });
    try o.append(&s, v24362, v24374);
    const v24388 = try o.arrow(&s, "", 3, body24375C, &.{ graph, frame });
    try o.append(&s, v24362, v24388);
    const v24402 = try o.arrow(&s, "", 3, body24389C, &.{ graph, frame });
    try o.append(&s, v24362, v24402);
    const v24416 = try o.arrow(&s, "", 3, body24403C, &.{ graph, frame });
    try o.append(&s, v24362, v24416);
    const v24430 = try o.arrow(&s, "", 3, body24417C, &.{ graph, frame });
    try o.append(&s, v24362, v24430);
    const v24444 = try o.arrow(&s, "", 3, body24431C, &.{ graph, frame });
    try o.append(&s, v24362, v24444);
    const v24445 = try o.call(&s, @src(), v24361, c.pi_js_undefined(), &.{v24362});
    try o.assign(&s, frame, "binding24245", v24445);
    const v24446 = try o.lookup(&s, frame, "binding24244");
    try s.put(namespace, "EncodeUnsafe", v24446);
    const v24447 = try o.lookup(&s, frame, "binding24246");
    try s.put(namespace, "Encode", v24447);
    const v24448 = try o.lookup(&s, frame, "binding24242");
    try s.put(namespace, "EncodeError", v24448);
    try s.put(bindings, "EncodeUnsafe", try s.text("binding24244"));
    try s.put(bindings, "Encode", try s.text("binding24246"));
    try s.put(bindings, "EncodeError", try s.text("binding24242"));
}
fn body24247(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v24251 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding24248", v24251);
    const v24252 = if (args.len > 1) args[1] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding24249", v24252);
    const v24253 = if (args.len > 2) args[2] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding24250", v24253);
    const v24254 = try o.importValue(&s, graph, "value/check/index.mjs", "Check");
    const v24255 = try o.lookup(&s, frame, "binding24248");
    const v24256 = try o.lookup(&s, frame, "binding24249");
    const v24257 = try o.lookup(&s, frame, "binding24250");
    const v24258 = try o.call(&s, @src(), v24254, c.pi_js_undefined(), &.{ v24255, v24256, v24257 });
    if (s.truthy(o.boolean(&s, !s.truthy(v24258)))) {
        const v24259 = try o.lookup(&s, frame, "binding24242");
        const v24260 = try o.lookup(&s, frame, "binding24250");
        const v24261 = try o.importValue(&s, graph, "value/errors/index.mjs", "Errors");
        const v24262 = try o.lookup(&s, frame, "binding24248");
        const v24263 = try o.lookup(&s, frame, "binding24249");
        const v24264 = try o.lookup(&s, frame, "binding24250");
        const v24265 = try o.call(&s, @src(), v24261, c.pi_js_undefined(), &.{ v24262, v24263, v24264 });
        const v24266 = try o.construct(&s, v24259, &.{ v24260, v24265 });
        _ = c.JS_Throw(e.context, c.JS_DupValue(e.context, v24266));
        return js.capture(e);
    }
    const v24267 = try o.lookup(&s, frame, "binding24250");
    return c.JS_DupValue(e.context, v24267);
}
fn body24269(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v24274 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding24270", v24274);
    const v24275 = if (args.len > 1) args[1] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding24271", v24275);
    const v24276 = if (args.len > 2) args[2] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding24272", v24276);
    const v24278 = try o.importValue(&s, graph, "system/index.mjs", "Settings");
    const v24279 = try s.text("Get");
    const v24280 = try s.own(try js.getKey(e, v24278, v24279));
    const v24281 = try o.call(&s, @src(), v24280, v24278, &.{});
    const v24282 = try s.text("unionPrioritySort");
    const v24283 = try s.own(try js.getKey(e, v24281, v24282));
    const v24285 = conditional24284: {
        if (s.truthy(v24283)) {
            const v24286 = try o.importValue(&s, graph, "value/shared/union_priority_sort.mjs", "UnionPrioritySort");
            const v24287 = try o.lookup(&s, frame, "binding24271");
            const v24288 = try o.call(&s, @src(), v24286, c.pi_js_undefined(), &.{v24287});
            break :conditional24284 v24288;
        } else {
            const v24289 = try o.lookup(&s, frame, "binding24271");
            break :conditional24284 v24289;
        }
    };
    try o.assign(&s, frame, "binding24277", v24285);
    const v24290 = try o.importValue(&s, graph, "value/codec/from_type.mjs", "FromType");
    const v24291 = try s.text("Encode");
    const v24292 = try o.lookup(&s, frame, "binding24270");
    const v24293 = try o.lookup(&s, frame, "binding24277");
    const v24294 = try o.lookup(&s, frame, "binding24272");
    const v24295 = try o.call(&s, @src(), v24290, c.pi_js_undefined(), &.{ v24291, v24292, v24293, v24294 });
    return c.JS_DupValue(e.context, v24295);
}
fn body24312(e: *Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    _ = roots[0];
    const frame = try o.frame(&s, roots[1]);
    _ = try o.lookup(&s, frame, "@this");
    const v24317 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding24314", v24317);
    const v24318 = if (args.len > 1) args[1] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding24315", v24318);
    const v24319 = if (args.len > 2) args[2] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding24316", v24319);
    const v24320 = try s.array();
    const v24321 = try o.lookup(&s, frame, "binding24314");
    try o.append(&s, v24320, v24321);
    const v24322 = try o.lookup(&s, frame, "binding24315");
    try o.append(&s, v24320, v24322);
    const v24323 = try o.lookup(&s, frame, "binding24316");
    try o.append(&s, v24320, v24323);
    return c.JS_DupValue(e.context, v24320);
}
fn body24312C(ctx: ?*c.JSContext, receiver: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const e = Engine.fromContext(ctx.?);
    return body24312(e, receiver, if (argc > 0) argv[0..@intCast(argc)] else &.{}, roots[0..2]) catch |err| sdk.fail(e, err);
}
fn body24326(e: *Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    _ = roots[0];
    const frame = try o.frame(&s, roots[1]);
    _ = try o.lookup(&s, frame, "@this");
    const v24330 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding24328", v24330);
    const v24331 = if (args.len > 1) args[1] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding24329", v24331);
    const v24332 = try s.array();
    const v24333 = try s.object();
    try o.append(&s, v24332, v24333);
    const v24334 = try o.lookup(&s, frame, "binding24328");
    try o.append(&s, v24332, v24334);
    const v24335 = try o.lookup(&s, frame, "binding24329");
    try o.append(&s, v24332, v24335);
    return c.JS_DupValue(e.context, v24332);
}
fn body24326C(ctx: ?*c.JSContext, receiver: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const e = Engine.fromContext(ctx.?);
    return body24326(e, receiver, if (argc > 0) argv[0..@intCast(argc)] else &.{}, roots[0..2]) catch |err| sdk.fail(e, err);
}
fn body24297(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v24302 = try o.rest(&s, args, 0);
    try o.assign(&s, frame, "binding24298", v24302);
    const v24306 = try o.importValue(&s, graph, "system/index.mjs", "Arguments");
    const v24307 = try s.text("Match");
    const v24308 = try s.own(try js.getKey(e, v24306, v24307));
    const v24309 = try o.lookup(&s, frame, "binding24298");
    const v24310 = try s.object();
    const v24311 = try s.text("3");
    const v24324 = try o.arrow(&s, "3", 3, body24312C, &.{ graph, frame });
    try o.defineKey(&s, v24310, v24311, v24324);
    const v24325 = try s.text("2");
    const v24336 = try o.arrow(&s, "2", 2, body24326C, &.{ graph, frame });
    try o.defineKey(&s, v24310, v24325, v24336);
    const v24337 = try o.call(&s, @src(), v24308, v24306, &.{ v24309, v24310 });
    var destructure24338 = try o.iterator(e, v24337);
    defer destructure24338.deinit();
    errdefer destructure24338.closePreserving();
    const v24339 = try s.own(if (destructure24338.closed) c.pi_js_undefined() else (try destructure24338.next()) orelse c.pi_js_undefined());
    try o.assign(&s, frame, "binding24303", v24339);
    const v24340 = try s.own(if (destructure24338.closed) c.pi_js_undefined() else (try destructure24338.next()) orelse c.pi_js_undefined());
    try o.assign(&s, frame, "binding24304", v24340);
    const v24341 = try s.own(if (destructure24338.closed) c.pi_js_undefined() else (try destructure24338.next()) orelse c.pi_js_undefined());
    try o.assign(&s, frame, "binding24305", v24341);
    try destructure24338.close();
    const v24342 = try o.lookup(&s, frame, "binding24245");
    const v24343 = try o.lookup(&s, frame, "binding24303");
    const v24344 = try o.lookup(&s, frame, "binding24304");
    const v24345 = try o.lookup(&s, frame, "binding24305");
    const v24346 = try o.call(&s, @src(), v24342, c.pi_js_undefined(), &.{ v24343, v24344, v24345 });
    return c.JS_DupValue(e.context, v24346);
}
fn constructor24352(e: *Engine, target: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    _ = roots[0];
    const frame = try o.frame(&s, roots[1]);
    const v24355 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding24353", v24355);
    const v24356 = if (args.len > 1) args[1] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding24354", v24356);
    const v24357 = try s.text("Encode");
    const v24358 = try o.lookup(&s, frame, "binding24353");
    const v24359 = try o.lookup(&s, frame, "binding24354");
    const receiver = try o.constructWithTarget(&s, roots[2], target, &.{ v24357, v24358, v24359 });
    try s.put(frame, "@this", receiver);
    return c.JS_DupValue(e.context, receiver);
}
fn body24363(e: *Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    _ = try o.lookup(&s, frame, "@this");
    const v24368 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding24365", v24368);
    const v24369 = if (args.len > 1) args[1] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding24366", v24369);
    const v24370 = if (args.len > 2) args[2] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding24367", v24370);
    const v24371 = try o.importValue(&s, graph, "value/clone/index.mjs", "Clone");
    const v24372 = try o.lookup(&s, frame, "binding24367");
    const v24373 = try o.call(&s, @src(), v24371, c.pi_js_undefined(), &.{v24372});
    return c.JS_DupValue(e.context, v24373);
}
fn body24363C(ctx: ?*c.JSContext, receiver: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const e = Engine.fromContext(ctx.?);
    return body24363(e, receiver, if (argc > 0) argv[0..@intCast(argc)] else &.{}, roots[0..2]) catch |err| sdk.fail(e, err);
}
fn body24375(e: *Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    _ = roots[0];
    const frame = try o.frame(&s, roots[1]);
    _ = try o.lookup(&s, frame, "@this");
    const v24380 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding24377", v24380);
    const v24381 = if (args.len > 1) args[1] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding24378", v24381);
    const v24382 = if (args.len > 2) args[2] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding24379", v24382);
    const v24383 = try o.lookup(&s, frame, "binding24244");
    const v24384 = try o.lookup(&s, frame, "binding24377");
    const v24385 = try o.lookup(&s, frame, "binding24378");
    const v24386 = try o.lookup(&s, frame, "binding24379");
    const v24387 = try o.call(&s, @src(), v24383, c.pi_js_undefined(), &.{ v24384, v24385, v24386 });
    return c.JS_DupValue(e.context, v24387);
}
fn body24375C(ctx: ?*c.JSContext, receiver: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const e = Engine.fromContext(ctx.?);
    return body24375(e, receiver, if (argc > 0) argv[0..@intCast(argc)] else &.{}, roots[0..2]) catch |err| sdk.fail(e, err);
}
fn body24389(e: *Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    _ = try o.lookup(&s, frame, "@this");
    const v24394 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding24391", v24394);
    const v24395 = if (args.len > 1) args[1] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding24392", v24395);
    const v24396 = if (args.len > 2) args[2] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding24393", v24396);
    const v24397 = try o.importValue(&s, graph, "value/default/index.mjs", "Default");
    const v24398 = try o.lookup(&s, frame, "binding24391");
    const v24399 = try o.lookup(&s, frame, "binding24392");
    const v24400 = try o.lookup(&s, frame, "binding24393");
    const v24401 = try o.call(&s, @src(), v24397, c.pi_js_undefined(), &.{ v24398, v24399, v24400 });
    return c.JS_DupValue(e.context, v24401);
}
fn body24389C(ctx: ?*c.JSContext, receiver: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const e = Engine.fromContext(ctx.?);
    return body24389(e, receiver, if (argc > 0) argv[0..@intCast(argc)] else &.{}, roots[0..2]) catch |err| sdk.fail(e, err);
}
fn body24403(e: *Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    _ = try o.lookup(&s, frame, "@this");
    const v24408 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding24405", v24408);
    const v24409 = if (args.len > 1) args[1] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding24406", v24409);
    const v24410 = if (args.len > 2) args[2] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding24407", v24410);
    const v24411 = try o.importValue(&s, graph, "value/convert/index.mjs", "Convert");
    const v24412 = try o.lookup(&s, frame, "binding24405");
    const v24413 = try o.lookup(&s, frame, "binding24406");
    const v24414 = try o.lookup(&s, frame, "binding24407");
    const v24415 = try o.call(&s, @src(), v24411, c.pi_js_undefined(), &.{ v24412, v24413, v24414 });
    return c.JS_DupValue(e.context, v24415);
}
fn body24403C(ctx: ?*c.JSContext, receiver: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const e = Engine.fromContext(ctx.?);
    return body24403(e, receiver, if (argc > 0) argv[0..@intCast(argc)] else &.{}, roots[0..2]) catch |err| sdk.fail(e, err);
}
fn body24417(e: *Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    _ = try o.lookup(&s, frame, "@this");
    const v24422 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding24419", v24422);
    const v24423 = if (args.len > 1) args[1] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding24420", v24423);
    const v24424 = if (args.len > 2) args[2] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding24421", v24424);
    const v24425 = try o.importValue(&s, graph, "value/clean/index.mjs", "Clean");
    const v24426 = try o.lookup(&s, frame, "binding24419");
    const v24427 = try o.lookup(&s, frame, "binding24420");
    const v24428 = try o.lookup(&s, frame, "binding24421");
    const v24429 = try o.call(&s, @src(), v24425, c.pi_js_undefined(), &.{ v24426, v24427, v24428 });
    return c.JS_DupValue(e.context, v24429);
}
fn body24417C(ctx: ?*c.JSContext, receiver: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const e = Engine.fromContext(ctx.?);
    return body24417(e, receiver, if (argc > 0) argv[0..@intCast(argc)] else &.{}, roots[0..2]) catch |err| sdk.fail(e, err);
}
fn body24431(e: *Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    _ = roots[0];
    const frame = try o.frame(&s, roots[1]);
    _ = try o.lookup(&s, frame, "@this");
    const v24436 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding24433", v24436);
    const v24437 = if (args.len > 1) args[1] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding24434", v24437);
    const v24438 = if (args.len > 2) args[2] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding24435", v24438);
    const v24439 = try o.lookup(&s, frame, "binding24243");
    const v24440 = try o.lookup(&s, frame, "binding24433");
    const v24441 = try o.lookup(&s, frame, "binding24434");
    const v24442 = try o.lookup(&s, frame, "binding24435");
    const v24443 = try o.call(&s, @src(), v24439, c.pi_js_undefined(), &.{ v24440, v24441, v24442 });
    return c.JS_DupValue(e.context, v24443);
}
fn body24431C(ctx: ?*c.JSContext, receiver: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const e = Engine.fromContext(ctx.?);
    return body24431(e, receiver, if (argc > 0) argv[0..@intCast(argc)] else &.{}, roots[0..2]) catch |err| sdk.fail(e, err);
}
