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
    const namespace = try s.get(modules, "value/convert/try/try_bigint.mjs");
    const frame = try o.frame(&s, c.pi_js_null());
    try s.put(frame, "@this", c.pi_js_undefined());
    try s.put(try s.get(graph, "frames"), "value/convert/try/try_bigint.mjs", frame);
    const bindings = try s.object();
    try s.put(try s.get(graph, "bindings"), "value/convert/try/try_bigint.mjs", bindings);
    const v27355 = try s.own(try ordinary.create(e, "FromBoolean", 1, body27337, &.{ graph, frame }));
    try o.assign(&s, frame, "binding27328", v27355);
    const v27364 = try s.own(try ordinary.create(e, "IsStringBigIntLike", 1, body27356, &.{ graph, frame }));
    try o.assign(&s, frame, "binding27332", v27364);
    const v27373 = try s.own(try ordinary.create(e, "IsStringDecimalLike", 1, body27365, &.{ graph, frame }));
    try o.assign(&s, frame, "binding27333", v27373);
    const v27382 = try s.own(try ordinary.create(e, "IsStringIntegerLike", 1, body27374, &.{ graph, frame }));
    try o.assign(&s, frame, "binding27334", v27382);
    const v27461 = try s.own(try ordinary.create(e, "FromString", 1, body27383, &.{ graph, frame }));
    try o.assign(&s, frame, "binding27335", v27461);
    const v27535 = try s.own(try ordinary.create(e, "TryBigInt", 1, body27462, &.{ graph, frame }));
    try o.assign(&s, frame, "binding27336", v27535);
    const v27536 = try o.lookup(&s, frame, "binding27336");
    try s.put(namespace, "TryBigInt", v27536);
    const v27537 = try s.text("^-?(0|[1-9]\\d*)n$");
    const v27538 = try s.text("");
    const v27539 = try s.global("RegExp");
    const v27540 = try o.construct(&s, v27539, &.{ v27537, v27538 });
    try o.assign(&s, frame, "binding27329", v27540);
    const v27541 = try s.text("^-?(0|[1-9]\\d*)\\.\\d+$");
    const v27542 = try s.text("");
    const v27543 = try s.global("RegExp");
    const v27544 = try o.construct(&s, v27543, &.{ v27541, v27542 });
    try o.assign(&s, frame, "binding27330", v27544);
    const v27545 = try s.text("^-?(0|[1-9]\\d*)$");
    const v27546 = try s.text("");
    const v27547 = try s.global("RegExp");
    const v27548 = try o.construct(&s, v27547, &.{ v27545, v27546 });
    try o.assign(&s, frame, "binding27331", v27548);
    const v27549 = try o.lookup(&s, frame, "binding27336");
    try s.put(namespace, "TryBigInt", v27549);
    try s.put(bindings, "TryBigInt", try s.text("binding27336"));
}
fn body27337(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v27339 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding27338", v27339);
    const v27340 = try o.importValue(&s, graph, "guard/index.mjs", "Guard");
    const v27341 = try s.text("IsEqual");
    const v27342 = try s.own(try js.getKey(e, v27340, v27341));
    const v27343 = try o.lookup(&s, frame, "binding27338");
    const v27344 = try s.call(v27342, v27340, &.{ v27343, o.boolean(&s, true) });
    const v27346 = conditional27345: {
        if (s.truthy(v27344)) {
            const v27347 = try o.importValue(&s, graph, "value/convert/try/try_result.mjs", "Ok");
            const v27348 = try s.global("BigInt");
            const v27349 = try s.call(v27348, c.pi_js_undefined(), &.{c.JS_NewFloat64(e.context, 1)});
            const v27350 = try s.call(v27347, c.pi_js_undefined(), &.{v27349});
            break :conditional27345 v27350;
        } else {
            const v27351 = try o.importValue(&s, graph, "value/convert/try/try_result.mjs", "Ok");
            const v27352 = try s.global("BigInt");
            const v27353 = try s.call(v27352, c.pi_js_undefined(), &.{c.JS_NewFloat64(e.context, 0)});
            const v27354 = try s.call(v27351, c.pi_js_undefined(), &.{v27353});
            break :conditional27345 v27354;
        }
    };
    return c.JS_DupValue(e.context, v27346);
}
fn body27356(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    _ = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v27358 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding27357", v27358);
    const v27359 = try o.lookup(&s, frame, "binding27329");
    const v27360 = try s.text("test");
    const v27361 = try s.own(try js.getKey(e, v27359, v27360));
    const v27362 = try o.lookup(&s, frame, "binding27357");
    const v27363 = try s.call(v27361, v27359, &.{v27362});
    return c.JS_DupValue(e.context, v27363);
}
fn body27365(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    _ = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v27367 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding27366", v27367);
    const v27368 = try o.lookup(&s, frame, "binding27330");
    const v27369 = try s.text("test");
    const v27370 = try s.own(try js.getKey(e, v27368, v27369));
    const v27371 = try o.lookup(&s, frame, "binding27366");
    const v27372 = try s.call(v27370, v27368, &.{v27371});
    return c.JS_DupValue(e.context, v27372);
}
fn body27374(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    _ = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v27376 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding27375", v27376);
    const v27377 = try o.lookup(&s, frame, "binding27331");
    const v27378 = try s.text("test");
    const v27379 = try s.own(try js.getKey(e, v27377, v27378));
    const v27380 = try o.lookup(&s, frame, "binding27375");
    const v27381 = try s.call(v27379, v27377, &.{v27380});
    return c.JS_DupValue(e.context, v27381);
}
fn body27383(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v27386 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding27384", v27386);
    const v27388 = try o.lookup(&s, frame, "binding27384");
    const v27389 = try s.text("toLowerCase");
    const v27390 = try s.own(try js.getKey(e, v27388, v27389));
    const v27391 = try s.call(v27390, v27388, &.{});
    try o.assign(&s, frame, "binding27387", v27391);
    const v27392 = try o.lookup(&s, frame, "binding27332");
    const v27393 = try o.lookup(&s, frame, "binding27384");
    const v27394 = try s.call(v27392, c.pi_js_undefined(), &.{v27393});
    const v27396 = conditional27395: {
        if (s.truthy(v27394)) {
            const v27397 = try o.importValue(&s, graph, "value/convert/try/try_result.mjs", "Ok");
            const v27398 = try s.global("BigInt");
            const v27399 = try o.lookup(&s, frame, "binding27384");
            const v27400 = try s.text("slice");
            const v27401 = try s.own(try js.getKey(e, v27399, v27400));
            const v27402 = try o.lookup(&s, frame, "binding27384");
            const v27403 = try s.text("length");
            const v27404 = try s.own(try js.getKey(e, v27402, v27403));
            const v27405 = try s.own(try e.checked(c.JS_PiBinaryOperator(e.context, 1, v27404, c.JS_NewFloat64(e.context, 1))));
            const v27406 = try s.call(v27401, v27399, &.{ c.JS_NewFloat64(e.context, 0), v27405 });
            const v27407 = try s.call(v27398, c.pi_js_undefined(), &.{v27406});
            const v27408 = try s.call(v27397, c.pi_js_undefined(), &.{v27407});
            break :conditional27395 v27408;
        } else {
            const v27409 = try o.lookup(&s, frame, "binding27333");
            const v27410 = try o.lookup(&s, frame, "binding27384");
            const v27411 = try s.call(v27409, c.pi_js_undefined(), &.{v27410});
            const v27413 = conditional27412: {
                if (s.truthy(v27411)) {
                    const v27414 = try o.importValue(&s, graph, "value/convert/try/try_result.mjs", "Ok");
                    const v27415 = try s.global("BigInt");
                    const v27416 = try o.lookup(&s, frame, "binding27384");
                    const v27417 = try s.text("split");
                    const v27418 = try s.own(try js.getKey(e, v27416, v27417));
                    const v27419 = try s.text(".");
                    const v27420 = try s.call(v27418, v27416, &.{v27419});
                    const v27421 = try o.propertyKey(&s, c.JS_NewFloat64(e.context, 0));
                    const v27422 = try s.own(try js.getKey(e, v27420, v27421));
                    const v27423 = try s.call(v27415, c.pi_js_undefined(), &.{v27422});
                    const v27424 = try s.call(v27414, c.pi_js_undefined(), &.{v27423});
                    break :conditional27412 v27424;
                } else {
                    const v27425 = try o.lookup(&s, frame, "binding27334");
                    const v27426 = try o.lookup(&s, frame, "binding27384");
                    const v27427 = try s.call(v27425, c.pi_js_undefined(), &.{v27426});
                    const v27429 = conditional27428: {
                        if (s.truthy(v27427)) {
                            const v27430 = try o.importValue(&s, graph, "value/convert/try/try_result.mjs", "Ok");
                            const v27431 = try s.global("BigInt");
                            const v27432 = try o.lookup(&s, frame, "binding27384");
                            const v27433 = try s.call(v27431, c.pi_js_undefined(), &.{v27432});
                            const v27434 = try s.call(v27430, c.pi_js_undefined(), &.{v27433});
                            break :conditional27428 v27434;
                        } else {
                            const v27435 = try o.importValue(&s, graph, "guard/index.mjs", "Guard");
                            const v27436 = try s.text("IsEqual");
                            const v27437 = try s.own(try js.getKey(e, v27435, v27436));
                            const v27438 = try o.lookup(&s, frame, "binding27387");
                            const v27439 = try s.text("false");
                            const v27440 = try s.call(v27437, v27435, &.{ v27438, v27439 });
                            const v27442 = conditional27441: {
                                if (s.truthy(v27440)) {
                                    const v27443 = try o.importValue(&s, graph, "value/convert/try/try_result.mjs", "Ok");
                                    const v27444 = try s.global("BigInt");
                                    const v27445 = try s.call(v27444, c.pi_js_undefined(), &.{c.JS_NewFloat64(e.context, 0)});
                                    const v27446 = try s.call(v27443, c.pi_js_undefined(), &.{v27445});
                                    break :conditional27441 v27446;
                                } else {
                                    const v27447 = try o.importValue(&s, graph, "guard/index.mjs", "Guard");
                                    const v27448 = try s.text("IsEqual");
                                    const v27449 = try s.own(try js.getKey(e, v27447, v27448));
                                    const v27450 = try o.lookup(&s, frame, "binding27387");
                                    const v27451 = try s.text("true");
                                    const v27452 = try s.call(v27449, v27447, &.{ v27450, v27451 });
                                    const v27454 = conditional27453: {
                                        if (s.truthy(v27452)) {
                                            const v27455 = try o.importValue(&s, graph, "value/convert/try/try_result.mjs", "Ok");
                                            const v27456 = try s.global("BigInt");
                                            const v27457 = try s.call(v27456, c.pi_js_undefined(), &.{c.JS_NewFloat64(e.context, 1)});
                                            const v27458 = try s.call(v27455, c.pi_js_undefined(), &.{v27457});
                                            break :conditional27453 v27458;
                                        } else {
                                            const v27459 = try o.importValue(&s, graph, "value/convert/try/try_result.mjs", "Fail");
                                            const v27460 = try s.call(v27459, c.pi_js_undefined(), &.{});
                                            break :conditional27453 v27460;
                                        }
                                    };
                                    break :conditional27441 v27454;
                                }
                            };
                            break :conditional27428 v27442;
                        }
                    };
                    break :conditional27412 v27429;
                }
            };
            break :conditional27395 v27413;
        }
    };
    return c.JS_DupValue(e.context, v27396);
}
fn body27462(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v27464 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding27463", v27464);
    const v27465 = try o.importValue(&s, graph, "guard/index.mjs", "Guard");
    const v27466 = try s.text("IsBigInt");
    const v27467 = try s.own(try js.getKey(e, v27465, v27466));
    const v27468 = try o.lookup(&s, frame, "binding27463");
    const v27469 = try s.call(v27467, v27465, &.{v27468});
    const v27471 = conditional27470: {
        if (s.truthy(v27469)) {
            const v27472 = try o.importValue(&s, graph, "value/convert/try/try_result.mjs", "Ok");
            const v27473 = try o.lookup(&s, frame, "binding27463");
            const v27474 = try s.call(v27472, c.pi_js_undefined(), &.{v27473});
            break :conditional27470 v27474;
        } else {
            const v27475 = try o.importValue(&s, graph, "guard/index.mjs", "Guard");
            const v27476 = try s.text("IsBoolean");
            const v27477 = try s.own(try js.getKey(e, v27475, v27476));
            const v27478 = try o.lookup(&s, frame, "binding27463");
            const v27479 = try s.call(v27477, v27475, &.{v27478});
            const v27481 = conditional27480: {
                if (s.truthy(v27479)) {
                    const v27482 = try o.lookup(&s, frame, "binding27328");
                    const v27483 = try o.lookup(&s, frame, "binding27463");
                    const v27484 = try s.call(v27482, c.pi_js_undefined(), &.{v27483});
                    break :conditional27480 v27484;
                } else {
                    const v27485 = try o.importValue(&s, graph, "guard/index.mjs", "Guard");
                    const v27486 = try s.text("IsNumber");
                    const v27487 = try s.own(try js.getKey(e, v27485, v27486));
                    const v27488 = try o.lookup(&s, frame, "binding27463");
                    const v27489 = try s.call(v27487, v27485, &.{v27488});
                    const v27491 = conditional27490: {
                        if (s.truthy(v27489)) {
                            const v27492 = try o.importValue(&s, graph, "value/convert/try/try_result.mjs", "Ok");
                            const v27493 = try s.global("BigInt");
                            const v27494 = try s.global("Math");
                            const v27495 = try s.text("trunc");
                            const v27496 = try s.own(try js.getKey(e, v27494, v27495));
                            const v27497 = try o.lookup(&s, frame, "binding27463");
                            const v27498 = try s.call(v27496, v27494, &.{v27497});
                            const v27499 = try s.call(v27493, c.pi_js_undefined(), &.{v27498});
                            const v27500 = try s.call(v27492, c.pi_js_undefined(), &.{v27499});
                            break :conditional27490 v27500;
                        } else {
                            const v27501 = try o.importValue(&s, graph, "guard/index.mjs", "Guard");
                            const v27502 = try s.text("IsNull");
                            const v27503 = try s.own(try js.getKey(e, v27501, v27502));
                            const v27504 = try o.lookup(&s, frame, "binding27463");
                            const v27505 = try s.call(v27503, v27501, &.{v27504});
                            const v27507 = conditional27506: {
                                if (s.truthy(v27505)) {
                                    const v27508 = try o.importValue(&s, graph, "value/convert/try/try_result.mjs", "Ok");
                                    const v27509 = try s.global("BigInt");
                                    const v27510 = try s.call(v27509, c.pi_js_undefined(), &.{c.JS_NewFloat64(e.context, 0)});
                                    const v27511 = try s.call(v27508, c.pi_js_undefined(), &.{v27510});
                                    break :conditional27506 v27511;
                                } else {
                                    const v27512 = try o.importValue(&s, graph, "guard/index.mjs", "Guard");
                                    const v27513 = try s.text("IsString");
                                    const v27514 = try s.own(try js.getKey(e, v27512, v27513));
                                    const v27515 = try o.lookup(&s, frame, "binding27463");
                                    const v27516 = try s.call(v27514, v27512, &.{v27515});
                                    const v27518 = conditional27517: {
                                        if (s.truthy(v27516)) {
                                            const v27519 = try o.lookup(&s, frame, "binding27335");
                                            const v27520 = try o.lookup(&s, frame, "binding27463");
                                            const v27521 = try s.call(v27519, c.pi_js_undefined(), &.{v27520});
                                            break :conditional27517 v27521;
                                        } else {
                                            const v27522 = try o.importValue(&s, graph, "guard/index.mjs", "Guard");
                                            const v27523 = try s.text("IsUndefined");
                                            const v27524 = try s.own(try js.getKey(e, v27522, v27523));
                                            const v27525 = try o.lookup(&s, frame, "binding27463");
                                            const v27526 = try s.call(v27524, v27522, &.{v27525});
                                            const v27528 = conditional27527: {
                                                if (s.truthy(v27526)) {
                                                    const v27529 = try o.importValue(&s, graph, "value/convert/try/try_result.mjs", "Ok");
                                                    const v27530 = try s.global("BigInt");
                                                    const v27531 = try s.call(v27530, c.pi_js_undefined(), &.{c.JS_NewFloat64(e.context, 0)});
                                                    const v27532 = try s.call(v27529, c.pi_js_undefined(), &.{v27531});
                                                    break :conditional27527 v27532;
                                                } else {
                                                    const v27533 = try o.importValue(&s, graph, "value/convert/try/try_result.mjs", "Fail");
                                                    const v27534 = try s.call(v27533, c.pi_js_undefined(), &.{});
                                                    break :conditional27527 v27534;
                                                }
                                            };
                                            break :conditional27517 v27528;
                                        }
                                    };
                                    break :conditional27506 v27518;
                                }
                            };
                            break :conditional27490 v27507;
                        }
                    };
                    break :conditional27480 v27491;
                }
            };
            break :conditional27470 v27481;
        }
    };
    return c.JS_DupValue(e.context, v27471);
}
