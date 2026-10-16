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
    const namespace = try s.get(modules, "compile/validator.mjs");
    const frame = try o.frame(&s, c.pi_js_null());
    try s.put(frame, "@this", c.pi_js_undefined());
    try s.put(try s.get(graph, "frames"), "compile/validator.mjs", frame);
    const bindings = try s.object();
    try s.put(try s.get(graph, "bindings"), "compile/validator.mjs", bindings);
    const v265 = try s.object();
    const v287 = try s.own(try class.constructor(e, "Validator", 2, v265, constructor266, &.{ graph, frame, c.pi_js_undefined() }));
    const v294 = try o.arrow(&s, "IsAccelerated", 0, body288C, &.{ graph, frame });
    try o.method(&s, v265, "IsAccelerated", v294);
    const v301 = try o.arrow(&s, "Context", 0, body295C, &.{ graph, frame });
    try o.method(&s, v265, "Context", v301);
    const v308 = try o.arrow(&s, "Type", 0, body302C, &.{ graph, frame });
    try o.method(&s, v265, "Type", v308);
    const v315 = try o.arrow(&s, "Code", 0, body309C, &.{ graph, frame });
    try o.method(&s, v265, "Code", v315);
    const v325 = try o.arrow(&s, "Check", 1, body316C, &.{ graph, frame });
    try o.method(&s, v265, "Check", v325);
    const v359 = try o.arrow(&s, "Parse", 1, body326C, &.{ graph, frame });
    try o.method(&s, v265, "Parse", v359);
    const v382 = try o.arrow(&s, "Errors", 1, body360C, &.{ graph, frame });
    try o.method(&s, v265, "Errors", v382);
    const v395 = try o.arrow(&s, "Clean", 1, body383C, &.{ graph, frame });
    try o.method(&s, v265, "Clean", v395);
    const v408 = try o.arrow(&s, "Convert", 1, body396C, &.{ graph, frame });
    try o.method(&s, v265, "Convert", v408);
    const v418 = try o.arrow(&s, "Create", 0, body409C, &.{ graph, frame });
    try o.method(&s, v265, "Create", v418);
    const v431 = try o.arrow(&s, "Default", 1, body419C, &.{ graph, frame });
    try o.method(&s, v265, "Default", v431);
    const v455 = try o.arrow(&s, "Decode", 1, body432C, &.{ graph, frame });
    try o.method(&s, v265, "Decode", v455);
    const v479 = try o.arrow(&s, "Encode", 1, body456C, &.{ graph, frame });
    try o.method(&s, v265, "Encode", v479);
    try o.assign(&s, frame, "binding264", v287);
    const v480 = try o.lookup(&s, frame, "binding264");
    try s.put(namespace, "Validator", v480);
    try s.put(bindings, "Validator", try s.text("binding264"));
}
fn constructor266(e: *Engine, target: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    const v269 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding267", v269);
    const v270 = if (args.len > 1) args[1] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding268", v270);
    const receiver = try s.own(try class.object(e, target));
    try s.put(frame, "@this", receiver);
    const v271 = try s.text("hasCodec");
    const v272 = try o.importValue(&s, graph, "value/index.mjs", "HasCodec");
    const v273 = try o.lookup(&s, frame, "binding267");
    const v274 = try o.lookup(&s, frame, "binding268");
    const v275 = try s.call(v272, c.pi_js_undefined(), &.{ v273, v274 });
    try js.setKey(e, receiver, v271, v275);
    const v276 = try s.text("buildResult");
    const v277 = try o.importValue(&s, graph, "schema/index.mjs", "Build");
    const v278 = try o.lookup(&s, frame, "binding267");
    const v279 = try o.lookup(&s, frame, "binding268");
    const v280 = try s.call(v277, c.pi_js_undefined(), &.{ v278, v279 });
    try js.setKey(e, receiver, v276, v280);
    const v281 = try s.text("evaluateResult");
    const v282 = try s.text("buildResult");
    const v283 = try s.own(try js.getKey(e, receiver, v282));
    const v284 = try s.text("Evaluate");
    const v285 = try s.own(try js.getKey(e, v283, v284));
    const v286 = try s.call(v285, v283, &.{});
    try js.setKey(e, receiver, v281, v286);
    return c.JS_DupValue(e.context, receiver);
}
fn body288(e: *Engine, receiver: c.JSValue, _: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    _ = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v289 = try s.text("evaluateResult");
    const v290 = try s.own(try js.getKey(e, receiver, v289));
    const v291 = try s.text("IsAccelerated");
    const v292 = try s.own(try js.getKey(e, v290, v291));
    const v293 = try s.call(v292, v290, &.{});
    return c.JS_DupValue(e.context, v293);
}
fn body288C(ctx: ?*c.JSContext, receiver: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const e = Engine.fromContext(ctx.?);
    return body288(e, receiver, if (argc > 0) argv[0..@intCast(argc)] else &.{}, roots[0..2]) catch |err| sdk.fail(e, err);
}
fn body295(e: *Engine, receiver: c.JSValue, _: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    _ = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v296 = try s.text("buildResult");
    const v297 = try s.own(try js.getKey(e, receiver, v296));
    const v298 = try s.text("Context");
    const v299 = try s.own(try js.getKey(e, v297, v298));
    const v300 = try s.call(v299, v297, &.{});
    return c.JS_DupValue(e.context, v300);
}
fn body295C(ctx: ?*c.JSContext, receiver: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const e = Engine.fromContext(ctx.?);
    return body295(e, receiver, if (argc > 0) argv[0..@intCast(argc)] else &.{}, roots[0..2]) catch |err| sdk.fail(e, err);
}
fn body302(e: *Engine, receiver: c.JSValue, _: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    _ = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v303 = try s.text("buildResult");
    const v304 = try s.own(try js.getKey(e, receiver, v303));
    const v305 = try s.text("Schema");
    const v306 = try s.own(try js.getKey(e, v304, v305));
    const v307 = try s.call(v306, v304, &.{});
    return c.JS_DupValue(e.context, v307);
}
fn body302C(ctx: ?*c.JSContext, receiver: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const e = Engine.fromContext(ctx.?);
    return body302(e, receiver, if (argc > 0) argv[0..@intCast(argc)] else &.{}, roots[0..2]) catch |err| sdk.fail(e, err);
}
fn body309(e: *Engine, receiver: c.JSValue, _: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    _ = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v310 = try s.text("evaluateResult");
    const v311 = try s.own(try js.getKey(e, receiver, v310));
    const v312 = try s.text("Code");
    const v313 = try s.own(try js.getKey(e, v311, v312));
    const v314 = try s.call(v313, v311, &.{});
    return c.JS_DupValue(e.context, v314);
}
fn body309C(ctx: ?*c.JSContext, receiver: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const e = Engine.fromContext(ctx.?);
    return body309(e, receiver, if (argc > 0) argv[0..@intCast(argc)] else &.{}, roots[0..2]) catch |err| sdk.fail(e, err);
}
fn body316(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    _ = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v318 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding317", v318);
    const v319 = try s.text("evaluateResult");
    const v320 = try s.own(try js.getKey(e, receiver, v319));
    const v321 = try s.text("Check");
    const v322 = try s.own(try js.getKey(e, v320, v321));
    const v323 = try o.lookup(&s, frame, "binding317");
    const v324 = try s.call(v322, v320, &.{v323});
    return c.JS_DupValue(e.context, v324);
}
fn body316C(ctx: ?*c.JSContext, receiver: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const e = Engine.fromContext(ctx.?);
    return body316(e, receiver, if (argc > 0) argv[0..@intCast(argc)] else &.{}, roots[0..2]) catch |err| sdk.fail(e, err);
}
fn body326(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v329 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding327", v329);
    const v331 = try s.text("Check");
    const v332 = try s.own(try js.getKey(e, receiver, v331));
    const v333 = try o.lookup(&s, frame, "binding327");
    const v334 = try s.call(v332, receiver, &.{v333});
    try o.assign(&s, frame, "binding330", v334);
    const v335 = try o.lookup(&s, frame, "binding330");
    if (s.truthy(v335)) {
        const v336 = try o.lookup(&s, frame, "binding327");
        return c.JS_DupValue(e.context, v336);
    }
    const v337 = try o.importValue(&s, graph, "system/settings/index.mjs", "Settings");
    const v338 = try s.text("Get");
    const v339 = try s.own(try js.getKey(e, v337, v338));
    const v340 = try s.call(v339, v337, &.{});
    const v341 = try s.text("correctiveParse");
    const v342 = try s.own(try js.getKey(e, v340, v341));
    if (s.truthy(v342)) {
        const v343 = try o.importValue(&s, graph, "value/index.mjs", "Parser");
        const v344 = try s.text("Context");
        const v345 = try s.own(try js.getKey(e, receiver, v344));
        const v346 = try s.call(v345, receiver, &.{});
        const v347 = try s.text("Type");
        const v348 = try s.own(try js.getKey(e, receiver, v347));
        const v349 = try s.call(v348, receiver, &.{});
        const v350 = try o.lookup(&s, frame, "binding327");
        const v351 = try s.call(v343, c.pi_js_undefined(), &.{ v346, v349, v350 });
        return c.JS_DupValue(e.context, v351);
    }
    const v352 = try o.importValue(&s, graph, "value/index.mjs", "ParseError");
    const v353 = try o.lookup(&s, frame, "binding327");
    const v354 = try s.text("Errors");
    const v355 = try s.own(try js.getKey(e, receiver, v354));
    const v356 = try o.lookup(&s, frame, "binding327");
    const v357 = try s.call(v355, receiver, &.{v356});
    const v358 = try o.construct(&s, v352, &.{ v353, v357 });
    _ = c.JS_Throw(e.context, c.JS_DupValue(e.context, v358));
    return js.capture(e);
}
fn body326C(ctx: ?*c.JSContext, receiver: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const e = Engine.fromContext(ctx.?);
    return body326(e, receiver, if (argc > 0) argv[0..@intCast(argc)] else &.{}, roots[0..2]) catch |err| sdk.fail(e, err);
}
fn body360(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v362 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding361", v362);
    const v363 = try s.text("IsAccelerated");
    const v364 = try s.own(try js.getKey(e, receiver, v363));
    const v365 = try s.call(v364, receiver, &.{});
    const v367 = logical366: {
        if (!s.truthy(v365)) break :logical366 v365;
        const v368 = try s.text("Check");
        const v369 = try s.own(try js.getKey(e, receiver, v368));
        const v370 = try o.lookup(&s, frame, "binding361");
        const v371 = try s.call(v369, receiver, &.{v370});
        break :logical366 v371;
    };
    if (s.truthy(v367)) {
        const v372 = try s.array();
        return c.JS_DupValue(e.context, v372);
    }
    const v373 = try o.importValue(&s, graph, "value/index.mjs", "Errors");
    const v374 = try s.text("Context");
    const v375 = try s.own(try js.getKey(e, receiver, v374));
    const v376 = try s.call(v375, receiver, &.{});
    const v377 = try s.text("Type");
    const v378 = try s.own(try js.getKey(e, receiver, v377));
    const v379 = try s.call(v378, receiver, &.{});
    const v380 = try o.lookup(&s, frame, "binding361");
    const v381 = try s.call(v373, c.pi_js_undefined(), &.{ v376, v379, v380 });
    return c.JS_DupValue(e.context, v381);
}
fn body360C(ctx: ?*c.JSContext, receiver: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const e = Engine.fromContext(ctx.?);
    return body360(e, receiver, if (argc > 0) argv[0..@intCast(argc)] else &.{}, roots[0..2]) catch |err| sdk.fail(e, err);
}
fn body383(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v385 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding384", v385);
    const v386 = try o.importValue(&s, graph, "value/index.mjs", "Clean");
    const v387 = try s.text("Context");
    const v388 = try s.own(try js.getKey(e, receiver, v387));
    const v389 = try s.call(v388, receiver, &.{});
    const v390 = try s.text("Type");
    const v391 = try s.own(try js.getKey(e, receiver, v390));
    const v392 = try s.call(v391, receiver, &.{});
    const v393 = try o.lookup(&s, frame, "binding384");
    const v394 = try s.call(v386, c.pi_js_undefined(), &.{ v389, v392, v393 });
    return c.JS_DupValue(e.context, v394);
}
fn body383C(ctx: ?*c.JSContext, receiver: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const e = Engine.fromContext(ctx.?);
    return body383(e, receiver, if (argc > 0) argv[0..@intCast(argc)] else &.{}, roots[0..2]) catch |err| sdk.fail(e, err);
}
fn body396(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v398 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding397", v398);
    const v399 = try o.importValue(&s, graph, "value/index.mjs", "Convert");
    const v400 = try s.text("Context");
    const v401 = try s.own(try js.getKey(e, receiver, v400));
    const v402 = try s.call(v401, receiver, &.{});
    const v403 = try s.text("Type");
    const v404 = try s.own(try js.getKey(e, receiver, v403));
    const v405 = try s.call(v404, receiver, &.{});
    const v406 = try o.lookup(&s, frame, "binding397");
    const v407 = try s.call(v399, c.pi_js_undefined(), &.{ v402, v405, v406 });
    return c.JS_DupValue(e.context, v407);
}
fn body396C(ctx: ?*c.JSContext, receiver: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const e = Engine.fromContext(ctx.?);
    return body396(e, receiver, if (argc > 0) argv[0..@intCast(argc)] else &.{}, roots[0..2]) catch |err| sdk.fail(e, err);
}
fn body409(e: *Engine, receiver: c.JSValue, _: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v410 = try o.importValue(&s, graph, "value/index.mjs", "Create");
    const v411 = try s.text("Context");
    const v412 = try s.own(try js.getKey(e, receiver, v411));
    const v413 = try s.call(v412, receiver, &.{});
    const v414 = try s.text("Type");
    const v415 = try s.own(try js.getKey(e, receiver, v414));
    const v416 = try s.call(v415, receiver, &.{});
    const v417 = try s.call(v410, c.pi_js_undefined(), &.{ v413, v416 });
    return c.JS_DupValue(e.context, v417);
}
fn body409C(ctx: ?*c.JSContext, receiver: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const e = Engine.fromContext(ctx.?);
    return body409(e, receiver, if (argc > 0) argv[0..@intCast(argc)] else &.{}, roots[0..2]) catch |err| sdk.fail(e, err);
}
fn body419(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v421 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding420", v421);
    const v422 = try o.importValue(&s, graph, "value/index.mjs", "Default");
    const v423 = try s.text("Context");
    const v424 = try s.own(try js.getKey(e, receiver, v423));
    const v425 = try s.call(v424, receiver, &.{});
    const v426 = try s.text("Type");
    const v427 = try s.own(try js.getKey(e, receiver, v426));
    const v428 = try s.call(v427, receiver, &.{});
    const v429 = try o.lookup(&s, frame, "binding420");
    const v430 = try s.call(v422, c.pi_js_undefined(), &.{ v425, v428, v429 });
    return c.JS_DupValue(e.context, v430);
}
fn body419C(ctx: ?*c.JSContext, receiver: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const e = Engine.fromContext(ctx.?);
    return body419(e, receiver, if (argc > 0) argv[0..@intCast(argc)] else &.{}, roots[0..2]) catch |err| sdk.fail(e, err);
}
fn body432(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v435 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding433", v435);
    const v437 = try s.text("hasCodec");
    const v438 = try s.own(try js.getKey(e, receiver, v437));
    const v440 = conditional439: {
        if (s.truthy(v438)) {
            const v441 = try o.importValue(&s, graph, "value/index.mjs", "Decode");
            const v442 = try s.text("Context");
            const v443 = try s.own(try js.getKey(e, receiver, v442));
            const v444 = try s.call(v443, receiver, &.{});
            const v445 = try s.text("Type");
            const v446 = try s.own(try js.getKey(e, receiver, v445));
            const v447 = try s.call(v446, receiver, &.{});
            const v448 = try o.lookup(&s, frame, "binding433");
            const v449 = try s.call(v441, c.pi_js_undefined(), &.{ v444, v447, v448 });
            break :conditional439 v449;
        } else {
            const v450 = try s.text("Parse");
            const v451 = try s.own(try js.getKey(e, receiver, v450));
            const v452 = try o.lookup(&s, frame, "binding433");
            const v453 = try s.call(v451, receiver, &.{v452});
            break :conditional439 v453;
        }
    };
    try o.assign(&s, frame, "binding436", v440);
    const v454 = try o.lookup(&s, frame, "binding436");
    return c.JS_DupValue(e.context, v454);
}
fn body432C(ctx: ?*c.JSContext, receiver: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const e = Engine.fromContext(ctx.?);
    return body432(e, receiver, if (argc > 0) argv[0..@intCast(argc)] else &.{}, roots[0..2]) catch |err| sdk.fail(e, err);
}
fn body456(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v459 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding457", v459);
    const v461 = try s.text("hasCodec");
    const v462 = try s.own(try js.getKey(e, receiver, v461));
    const v464 = conditional463: {
        if (s.truthy(v462)) {
            const v465 = try o.importValue(&s, graph, "value/index.mjs", "Encode");
            const v466 = try s.text("Context");
            const v467 = try s.own(try js.getKey(e, receiver, v466));
            const v468 = try s.call(v467, receiver, &.{});
            const v469 = try s.text("Type");
            const v470 = try s.own(try js.getKey(e, receiver, v469));
            const v471 = try s.call(v470, receiver, &.{});
            const v472 = try o.lookup(&s, frame, "binding457");
            const v473 = try s.call(v465, c.pi_js_undefined(), &.{ v468, v471, v472 });
            break :conditional463 v473;
        } else {
            const v474 = try s.text("Parse");
            const v475 = try s.own(try js.getKey(e, receiver, v474));
            const v476 = try o.lookup(&s, frame, "binding457");
            const v477 = try s.call(v475, receiver, &.{v476});
            break :conditional463 v477;
        }
    };
    try o.assign(&s, frame, "binding460", v464);
    const v478 = try o.lookup(&s, frame, "binding460");
    return c.JS_DupValue(e.context, v478);
}
fn body456C(ctx: ?*c.JSContext, receiver: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const e = Engine.fromContext(ctx.?);
    return body456(e, receiver, if (argc > 0) argv[0..@intCast(argc)] else &.{}, roots[0..2]) catch |err| sdk.fail(e, err);
}
