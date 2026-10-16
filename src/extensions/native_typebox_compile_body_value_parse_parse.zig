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
    const namespace = try s.get(modules, "value/parse/parse.mjs");
    const frame = try o.frame(&s, c.pi_js_null());
    try s.put(frame, "@this", c.pi_js_undefined());
    try s.put(try s.get(graph, "frames"), "value/parse/parse.mjs", frame);
    const bindings = try s.object();
    try s.put(try s.get(graph, "bindings"), "value/parse/parse.mjs", bindings);
    const v30337 = try s.own(try ordinary.create(e, "Assert", 3, body30316, &.{ graph, frame }));
    try o.assign(&s, frame, "binding30313", v30337);
    const v30411 = try s.own(try ordinary.create(e, "Parse", 0, body30338, &.{ graph, frame }));
    try o.assign(&s, frame, "binding30315", v30411);
    const v30412 = try o.lookup(&s, frame, "binding30314");
    try s.put(namespace, "Parser", v30412);
    const v30413 = try o.lookup(&s, frame, "binding30315");
    try s.put(namespace, "Parse", v30413);
    const v30414 = try o.importValue(&s, graph, "value/assert/index.mjs", "AssertError");
    const v30415 = try o.derivedPrototype(&s, v30414);
    const v30424 = try s.own(try class.constructor(e, "ParseError", 2, v30415, constructor30416, &.{ graph, frame, v30414 }));
    try o.setPrototype(&s, v30424, v30414);
    try o.assign(&s, frame, "binding30312", v30424);
    const v30425 = try o.importValue(&s, graph, "value/pipeline/index.mjs", "Pipeline");
    const v30426 = try s.array();
    const v30438 = try o.arrow(&s, "", 3, body30427C, &.{ graph, frame });
    try o.append(&s, v30426, v30438);
    const v30452 = try o.arrow(&s, "", 3, body30439C, &.{ graph, frame });
    try o.append(&s, v30426, v30452);
    const v30466 = try o.arrow(&s, "", 3, body30453C, &.{ graph, frame });
    try o.append(&s, v30426, v30466);
    const v30480 = try o.arrow(&s, "", 3, body30467C, &.{ graph, frame });
    try o.append(&s, v30426, v30480);
    const v30494 = try o.arrow(&s, "", 3, body30481C, &.{ graph, frame });
    try o.append(&s, v30426, v30494);
    const v30495 = try s.call(v30425, c.pi_js_undefined(), &.{v30426});
    try o.assign(&s, frame, "binding30314", v30495);
    const v30496 = try o.lookup(&s, frame, "binding30314");
    try s.put(namespace, "Parser", v30496);
    const v30497 = try o.lookup(&s, frame, "binding30315");
    try s.put(namespace, "Parse", v30497);
    const v30498 = try o.lookup(&s, frame, "binding30312");
    try s.put(namespace, "ParseError", v30498);
    try s.put(bindings, "Parser", try s.text("binding30314"));
    try s.put(bindings, "Parse", try s.text("binding30315"));
    try s.put(bindings, "ParseError", try s.text("binding30312"));
}
fn body30316(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v30320 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding30317", v30320);
    const v30321 = if (args.len > 1) args[1] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding30318", v30321);
    const v30322 = if (args.len > 2) args[2] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding30319", v30322);
    const v30323 = try o.importValue(&s, graph, "value/check/index.mjs", "Check");
    const v30324 = try o.lookup(&s, frame, "binding30317");
    const v30325 = try o.lookup(&s, frame, "binding30318");
    const v30326 = try o.lookup(&s, frame, "binding30319");
    const v30327 = try s.call(v30323, c.pi_js_undefined(), &.{ v30324, v30325, v30326 });
    if (s.truthy(o.boolean(&s, !s.truthy(v30327)))) {
        const v30328 = try o.lookup(&s, frame, "binding30312");
        const v30329 = try o.lookup(&s, frame, "binding30319");
        const v30330 = try o.importValue(&s, graph, "value/errors/index.mjs", "Errors");
        const v30331 = try o.lookup(&s, frame, "binding30317");
        const v30332 = try o.lookup(&s, frame, "binding30318");
        const v30333 = try o.lookup(&s, frame, "binding30319");
        const v30334 = try s.call(v30330, c.pi_js_undefined(), &.{ v30331, v30332, v30333 });
        const v30335 = try o.construct(&s, v30328, &.{ v30329, v30334 });
        _ = c.JS_Throw(e.context, c.JS_DupValue(e.context, v30335));
        return js.capture(e);
    }
    const v30336 = try o.lookup(&s, frame, "binding30319");
    return c.JS_DupValue(e.context, v30336);
}
fn body30355(e: *Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    _ = roots[0];
    const frame = try o.frame(&s, roots[1]);
    _ = try o.lookup(&s, frame, "@this");
    const v30360 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding30357", v30360);
    const v30361 = if (args.len > 1) args[1] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding30358", v30361);
    const v30362 = if (args.len > 2) args[2] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding30359", v30362);
    const v30363 = try s.array();
    const v30364 = try o.lookup(&s, frame, "binding30357");
    try o.append(&s, v30363, v30364);
    const v30365 = try o.lookup(&s, frame, "binding30358");
    try o.append(&s, v30363, v30365);
    const v30366 = try o.lookup(&s, frame, "binding30359");
    try o.append(&s, v30363, v30366);
    return c.JS_DupValue(e.context, v30363);
}
fn body30355C(ctx: ?*c.JSContext, receiver: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const e = Engine.fromContext(ctx.?);
    return body30355(e, receiver, if (argc > 0) argv[0..@intCast(argc)] else &.{}, roots[0..2]) catch |err| sdk.fail(e, err);
}
fn body30369(e: *Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    _ = roots[0];
    const frame = try o.frame(&s, roots[1]);
    _ = try o.lookup(&s, frame, "@this");
    const v30373 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding30371", v30373);
    const v30374 = if (args.len > 1) args[1] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding30372", v30374);
    const v30375 = try s.array();
    const v30376 = try s.object();
    try o.append(&s, v30375, v30376);
    const v30377 = try o.lookup(&s, frame, "binding30371");
    try o.append(&s, v30375, v30377);
    const v30378 = try o.lookup(&s, frame, "binding30372");
    try o.append(&s, v30375, v30378);
    return c.JS_DupValue(e.context, v30375);
}
fn body30369C(ctx: ?*c.JSContext, receiver: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const e = Engine.fromContext(ctx.?);
    return body30369(e, receiver, if (argc > 0) argv[0..@intCast(argc)] else &.{}, roots[0..2]) catch |err| sdk.fail(e, err);
}
fn body30338(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v30344 = try o.rest(&s, args, 0);
    try o.assign(&s, frame, "binding30339", v30344);
    const v30349 = try o.importValue(&s, graph, "system/arguments/index.mjs", "Arguments");
    const v30350 = try s.text("Match");
    const v30351 = try s.own(try js.getKey(e, v30349, v30350));
    const v30352 = try o.lookup(&s, frame, "binding30339");
    const v30353 = try s.object();
    const v30354 = try s.text("3");
    const v30367 = try o.arrow(&s, "3", 3, body30355C, &.{ graph, frame });
    try o.defineKey(&s, v30353, v30354, v30367);
    const v30368 = try s.text("2");
    const v30379 = try o.arrow(&s, "2", 2, body30369C, &.{ graph, frame });
    try o.defineKey(&s, v30353, v30368, v30379);
    const v30380 = try s.call(v30351, v30349, &.{ v30352, v30353 });
    var destructure30381 = try o.iterator(e, v30380);
    defer destructure30381.deinit();
    errdefer destructure30381.closePreserving();
    const v30382 = try s.own(if (destructure30381.closed) c.pi_js_undefined() else (try destructure30381.next()) orelse c.pi_js_undefined());
    try o.assign(&s, frame, "binding30345", v30382);
    const v30383 = try s.own(if (destructure30381.closed) c.pi_js_undefined() else (try destructure30381.next()) orelse c.pi_js_undefined());
    try o.assign(&s, frame, "binding30346", v30383);
    const v30384 = try s.own(if (destructure30381.closed) c.pi_js_undefined() else (try destructure30381.next()) orelse c.pi_js_undefined());
    try o.assign(&s, frame, "binding30347", v30384);
    try destructure30381.close();
    const v30385 = try o.importValue(&s, graph, "value/check/index.mjs", "Check");
    const v30386 = try o.lookup(&s, frame, "binding30345");
    const v30387 = try o.lookup(&s, frame, "binding30346");
    const v30388 = try o.lookup(&s, frame, "binding30347");
    const v30389 = try s.call(v30385, c.pi_js_undefined(), &.{ v30386, v30387, v30388 });
    try o.assign(&s, frame, "binding30348", v30389);
    const v30390 = try o.lookup(&s, frame, "binding30348");
    if (s.truthy(v30390)) {
        const v30391 = try o.lookup(&s, frame, "binding30347");
        return c.JS_DupValue(e.context, v30391);
    }
    const v30392 = try o.importValue(&s, graph, "system/system.mjs", "Settings");
    const v30393 = try s.text("Get");
    const v30394 = try s.own(try js.getKey(e, v30392, v30393));
    const v30395 = try s.call(v30394, v30392, &.{});
    const v30396 = try s.text("correctiveParse");
    const v30397 = try s.own(try js.getKey(e, v30395, v30396));
    if (s.truthy(v30397)) {
        const v30398 = try o.lookup(&s, frame, "binding30314");
        const v30399 = try o.lookup(&s, frame, "binding30345");
        const v30400 = try o.lookup(&s, frame, "binding30346");
        const v30401 = try o.lookup(&s, frame, "binding30347");
        const v30402 = try s.call(v30398, c.pi_js_undefined(), &.{ v30399, v30400, v30401 });
        return c.JS_DupValue(e.context, v30402);
    }
    const v30403 = try o.lookup(&s, frame, "binding30312");
    const v30404 = try o.lookup(&s, frame, "binding30347");
    const v30405 = try o.importValue(&s, graph, "value/errors/index.mjs", "Errors");
    const v30406 = try o.lookup(&s, frame, "binding30345");
    const v30407 = try o.lookup(&s, frame, "binding30346");
    const v30408 = try o.lookup(&s, frame, "binding30347");
    const v30409 = try s.call(v30405, c.pi_js_undefined(), &.{ v30406, v30407, v30408 });
    const v30410 = try o.construct(&s, v30403, &.{ v30404, v30409 });
    _ = c.JS_Throw(e.context, c.JS_DupValue(e.context, v30410));
    return js.capture(e);
}
fn constructor30416(e: *Engine, target: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    _ = roots[0];
    const frame = try o.frame(&s, roots[1]);
    const v30419 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding30417", v30419);
    const v30420 = if (args.len > 1) args[1] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding30418", v30420);
    const v30421 = try s.text("Parse");
    const v30422 = try o.lookup(&s, frame, "binding30417");
    const v30423 = try o.lookup(&s, frame, "binding30418");
    const receiver = try o.constructWithTarget(&s, roots[2], target, &.{ v30421, v30422, v30423 });
    try s.put(frame, "@this", receiver);
    return c.JS_DupValue(e.context, receiver);
}
fn body30427(e: *Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    _ = try o.lookup(&s, frame, "@this");
    const v30432 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding30429", v30432);
    const v30433 = if (args.len > 1) args[1] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding30430", v30433);
    const v30434 = if (args.len > 2) args[2] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding30431", v30434);
    const v30435 = try o.importValue(&s, graph, "value/clone/index.mjs", "Clone");
    const v30436 = try o.lookup(&s, frame, "binding30431");
    const v30437 = try s.call(v30435, c.pi_js_undefined(), &.{v30436});
    return c.JS_DupValue(e.context, v30437);
}
fn body30427C(ctx: ?*c.JSContext, receiver: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const e = Engine.fromContext(ctx.?);
    return body30427(e, receiver, if (argc > 0) argv[0..@intCast(argc)] else &.{}, roots[0..2]) catch |err| sdk.fail(e, err);
}
fn body30439(e: *Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    _ = try o.lookup(&s, frame, "@this");
    const v30444 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding30441", v30444);
    const v30445 = if (args.len > 1) args[1] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding30442", v30445);
    const v30446 = if (args.len > 2) args[2] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding30443", v30446);
    const v30447 = try o.importValue(&s, graph, "value/default/index.mjs", "Default");
    const v30448 = try o.lookup(&s, frame, "binding30441");
    const v30449 = try o.lookup(&s, frame, "binding30442");
    const v30450 = try o.lookup(&s, frame, "binding30443");
    const v30451 = try s.call(v30447, c.pi_js_undefined(), &.{ v30448, v30449, v30450 });
    return c.JS_DupValue(e.context, v30451);
}
fn body30439C(ctx: ?*c.JSContext, receiver: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const e = Engine.fromContext(ctx.?);
    return body30439(e, receiver, if (argc > 0) argv[0..@intCast(argc)] else &.{}, roots[0..2]) catch |err| sdk.fail(e, err);
}
fn body30453(e: *Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    _ = try o.lookup(&s, frame, "@this");
    const v30458 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding30455", v30458);
    const v30459 = if (args.len > 1) args[1] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding30456", v30459);
    const v30460 = if (args.len > 2) args[2] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding30457", v30460);
    const v30461 = try o.importValue(&s, graph, "value/convert/index.mjs", "Convert");
    const v30462 = try o.lookup(&s, frame, "binding30455");
    const v30463 = try o.lookup(&s, frame, "binding30456");
    const v30464 = try o.lookup(&s, frame, "binding30457");
    const v30465 = try s.call(v30461, c.pi_js_undefined(), &.{ v30462, v30463, v30464 });
    return c.JS_DupValue(e.context, v30465);
}
fn body30453C(ctx: ?*c.JSContext, receiver: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const e = Engine.fromContext(ctx.?);
    return body30453(e, receiver, if (argc > 0) argv[0..@intCast(argc)] else &.{}, roots[0..2]) catch |err| sdk.fail(e, err);
}
fn body30467(e: *Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    _ = try o.lookup(&s, frame, "@this");
    const v30472 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding30469", v30472);
    const v30473 = if (args.len > 1) args[1] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding30470", v30473);
    const v30474 = if (args.len > 2) args[2] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding30471", v30474);
    const v30475 = try o.importValue(&s, graph, "value/clean/index.mjs", "Clean");
    const v30476 = try o.lookup(&s, frame, "binding30469");
    const v30477 = try o.lookup(&s, frame, "binding30470");
    const v30478 = try o.lookup(&s, frame, "binding30471");
    const v30479 = try s.call(v30475, c.pi_js_undefined(), &.{ v30476, v30477, v30478 });
    return c.JS_DupValue(e.context, v30479);
}
fn body30467C(ctx: ?*c.JSContext, receiver: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const e = Engine.fromContext(ctx.?);
    return body30467(e, receiver, if (argc > 0) argv[0..@intCast(argc)] else &.{}, roots[0..2]) catch |err| sdk.fail(e, err);
}
fn body30481(e: *Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    _ = roots[0];
    const frame = try o.frame(&s, roots[1]);
    _ = try o.lookup(&s, frame, "@this");
    const v30486 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding30483", v30486);
    const v30487 = if (args.len > 1) args[1] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding30484", v30487);
    const v30488 = if (args.len > 2) args[2] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding30485", v30488);
    const v30489 = try o.lookup(&s, frame, "binding30313");
    const v30490 = try o.lookup(&s, frame, "binding30483");
    const v30491 = try o.lookup(&s, frame, "binding30484");
    const v30492 = try o.lookup(&s, frame, "binding30485");
    const v30493 = try s.call(v30489, c.pi_js_undefined(), &.{ v30490, v30491, v30492 });
    return c.JS_DupValue(e.context, v30493);
}
fn body30481C(ctx: ?*c.JSContext, receiver: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const e = Engine.fromContext(ctx.?);
    return body30481(e, receiver, if (argc > 0) argv[0..@intCast(argc)] else &.{}, roots[0..2]) catch |err| sdk.fail(e, err);
}
