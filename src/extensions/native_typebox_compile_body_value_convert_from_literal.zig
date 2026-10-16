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
    const namespace = try s.get(modules, "value/convert/from_literal.mjs");
    const frame = try o.frame(&s, c.pi_js_null());
    try s.put(frame, "@this", c.pi_js_undefined());
    try s.put(try s.get(graph, "frames"), "value/convert/from_literal.mjs", frame);
    const bindings = try s.object();
    try s.put(try s.get(graph, "bindings"), "value/convert/from_literal.mjs", bindings);
    const v26349 = try s.own(try ordinary.create(e, "FromLiteralBigInt", 3, body26312, &.{ graph, frame }));
    try o.assign(&s, frame, "binding26307", v26349);
    const v26387 = try s.own(try ordinary.create(e, "FromLiteralBoolean", 3, body26350, &.{ graph, frame }));
    try o.assign(&s, frame, "binding26308", v26387);
    const v26425 = try s.own(try ordinary.create(e, "FromLiteralNumber", 3, body26388, &.{ graph, frame }));
    try o.assign(&s, frame, "binding26309", v26425);
    const v26463 = try s.own(try ordinary.create(e, "FromLiteralString", 3, body26426, &.{ graph, frame }));
    try o.assign(&s, frame, "binding26310", v26463);
    const v26522 = try s.own(try ordinary.create(e, "FromLiteral", 3, body26464, &.{ graph, frame }));
    try o.assign(&s, frame, "binding26311", v26522);
    const v26523 = try o.lookup(&s, frame, "binding26311");
    try s.put(namespace, "FromLiteral", v26523);
    const v26524 = try o.lookup(&s, frame, "binding26311");
    try s.put(namespace, "FromLiteral", v26524);
    try s.put(bindings, "FromLiteral", try s.text("binding26311"));
}
fn body26312(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v26317 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding26313", v26317);
    const v26318 = if (args.len > 1) args[1] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding26314", v26318);
    const v26319 = if (args.len > 2) args[2] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding26315", v26319);
    const v26321 = try o.importValue(&s, graph, "value/convert/try/index.mjs", "Try");
    const v26322 = try s.text("TryBigInt");
    const v26323 = try s.own(try js.getKey(e, v26321, v26322));
    const v26324 = try o.lookup(&s, frame, "binding26315");
    const v26325 = try s.call(v26323, v26321, &.{v26324});
    try o.assign(&s, frame, "binding26320", v26325);
    const v26326 = try o.importValue(&s, graph, "value/convert/try/index.mjs", "Try");
    const v26327 = try s.text("IsOk");
    const v26328 = try s.own(try js.getKey(e, v26326, v26327));
    const v26329 = try o.lookup(&s, frame, "binding26320");
    const v26330 = try s.call(v26328, v26326, &.{v26329});
    const v26332 = logical26331: {
        if (!s.truthy(v26330)) break :logical26331 v26330;
        const v26333 = try o.importValue(&s, graph, "guard/index.mjs", "Guard");
        const v26334 = try s.text("IsEqual");
        const v26335 = try s.own(try js.getKey(e, v26333, v26334));
        const v26336 = try o.lookup(&s, frame, "binding26314");
        const v26337 = try s.text("const");
        const v26338 = try s.own(try js.getKey(e, v26336, v26337));
        const v26339 = try o.lookup(&s, frame, "binding26320");
        const v26340 = try s.text("value");
        const v26341 = try s.own(try js.getKey(e, v26339, v26340));
        const v26342 = try s.call(v26335, v26333, &.{ v26338, v26341 });
        break :logical26331 v26342;
    };
    const v26344 = conditional26343: {
        if (s.truthy(v26332)) {
            const v26345 = try o.lookup(&s, frame, "binding26320");
            const v26346 = try s.text("value");
            const v26347 = try s.own(try js.getKey(e, v26345, v26346));
            break :conditional26343 v26347;
        } else {
            const v26348 = try o.lookup(&s, frame, "binding26315");
            break :conditional26343 v26348;
        }
    };
    return c.JS_DupValue(e.context, v26344);
}
fn body26350(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v26355 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding26351", v26355);
    const v26356 = if (args.len > 1) args[1] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding26352", v26356);
    const v26357 = if (args.len > 2) args[2] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding26353", v26357);
    const v26359 = try o.importValue(&s, graph, "value/convert/try/index.mjs", "Try");
    const v26360 = try s.text("TryBoolean");
    const v26361 = try s.own(try js.getKey(e, v26359, v26360));
    const v26362 = try o.lookup(&s, frame, "binding26353");
    const v26363 = try s.call(v26361, v26359, &.{v26362});
    try o.assign(&s, frame, "binding26358", v26363);
    const v26364 = try o.importValue(&s, graph, "value/convert/try/index.mjs", "Try");
    const v26365 = try s.text("IsOk");
    const v26366 = try s.own(try js.getKey(e, v26364, v26365));
    const v26367 = try o.lookup(&s, frame, "binding26358");
    const v26368 = try s.call(v26366, v26364, &.{v26367});
    const v26370 = logical26369: {
        if (!s.truthy(v26368)) break :logical26369 v26368;
        const v26371 = try o.importValue(&s, graph, "guard/index.mjs", "Guard");
        const v26372 = try s.text("IsEqual");
        const v26373 = try s.own(try js.getKey(e, v26371, v26372));
        const v26374 = try o.lookup(&s, frame, "binding26352");
        const v26375 = try s.text("const");
        const v26376 = try s.own(try js.getKey(e, v26374, v26375));
        const v26377 = try o.lookup(&s, frame, "binding26358");
        const v26378 = try s.text("value");
        const v26379 = try s.own(try js.getKey(e, v26377, v26378));
        const v26380 = try s.call(v26373, v26371, &.{ v26376, v26379 });
        break :logical26369 v26380;
    };
    const v26382 = conditional26381: {
        if (s.truthy(v26370)) {
            const v26383 = try o.lookup(&s, frame, "binding26358");
            const v26384 = try s.text("value");
            const v26385 = try s.own(try js.getKey(e, v26383, v26384));
            break :conditional26381 v26385;
        } else {
            const v26386 = try o.lookup(&s, frame, "binding26353");
            break :conditional26381 v26386;
        }
    };
    return c.JS_DupValue(e.context, v26382);
}
fn body26388(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v26393 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding26389", v26393);
    const v26394 = if (args.len > 1) args[1] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding26390", v26394);
    const v26395 = if (args.len > 2) args[2] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding26391", v26395);
    const v26397 = try o.importValue(&s, graph, "value/convert/try/index.mjs", "Try");
    const v26398 = try s.text("TryNumber");
    const v26399 = try s.own(try js.getKey(e, v26397, v26398));
    const v26400 = try o.lookup(&s, frame, "binding26391");
    const v26401 = try s.call(v26399, v26397, &.{v26400});
    try o.assign(&s, frame, "binding26396", v26401);
    const v26402 = try o.importValue(&s, graph, "value/convert/try/index.mjs", "Try");
    const v26403 = try s.text("IsOk");
    const v26404 = try s.own(try js.getKey(e, v26402, v26403));
    const v26405 = try o.lookup(&s, frame, "binding26396");
    const v26406 = try s.call(v26404, v26402, &.{v26405});
    const v26408 = logical26407: {
        if (!s.truthy(v26406)) break :logical26407 v26406;
        const v26409 = try o.importValue(&s, graph, "guard/index.mjs", "Guard");
        const v26410 = try s.text("IsEqual");
        const v26411 = try s.own(try js.getKey(e, v26409, v26410));
        const v26412 = try o.lookup(&s, frame, "binding26390");
        const v26413 = try s.text("const");
        const v26414 = try s.own(try js.getKey(e, v26412, v26413));
        const v26415 = try o.lookup(&s, frame, "binding26396");
        const v26416 = try s.text("value");
        const v26417 = try s.own(try js.getKey(e, v26415, v26416));
        const v26418 = try s.call(v26411, v26409, &.{ v26414, v26417 });
        break :logical26407 v26418;
    };
    const v26420 = conditional26419: {
        if (s.truthy(v26408)) {
            const v26421 = try o.lookup(&s, frame, "binding26396");
            const v26422 = try s.text("value");
            const v26423 = try s.own(try js.getKey(e, v26421, v26422));
            break :conditional26419 v26423;
        } else {
            const v26424 = try o.lookup(&s, frame, "binding26391");
            break :conditional26419 v26424;
        }
    };
    return c.JS_DupValue(e.context, v26420);
}
fn body26426(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v26431 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding26427", v26431);
    const v26432 = if (args.len > 1) args[1] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding26428", v26432);
    const v26433 = if (args.len > 2) args[2] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding26429", v26433);
    const v26435 = try o.importValue(&s, graph, "value/convert/try/index.mjs", "Try");
    const v26436 = try s.text("TryString");
    const v26437 = try s.own(try js.getKey(e, v26435, v26436));
    const v26438 = try o.lookup(&s, frame, "binding26429");
    const v26439 = try s.call(v26437, v26435, &.{v26438});
    try o.assign(&s, frame, "binding26434", v26439);
    const v26440 = try o.importValue(&s, graph, "value/convert/try/index.mjs", "Try");
    const v26441 = try s.text("IsOk");
    const v26442 = try s.own(try js.getKey(e, v26440, v26441));
    const v26443 = try o.lookup(&s, frame, "binding26434");
    const v26444 = try s.call(v26442, v26440, &.{v26443});
    const v26446 = logical26445: {
        if (!s.truthy(v26444)) break :logical26445 v26444;
        const v26447 = try o.importValue(&s, graph, "guard/index.mjs", "Guard");
        const v26448 = try s.text("IsEqual");
        const v26449 = try s.own(try js.getKey(e, v26447, v26448));
        const v26450 = try o.lookup(&s, frame, "binding26428");
        const v26451 = try s.text("const");
        const v26452 = try s.own(try js.getKey(e, v26450, v26451));
        const v26453 = try o.lookup(&s, frame, "binding26434");
        const v26454 = try s.text("value");
        const v26455 = try s.own(try js.getKey(e, v26453, v26454));
        const v26456 = try s.call(v26449, v26447, &.{ v26452, v26455 });
        break :logical26445 v26456;
    };
    const v26458 = conditional26457: {
        if (s.truthy(v26446)) {
            const v26459 = try o.lookup(&s, frame, "binding26434");
            const v26460 = try s.text("value");
            const v26461 = try s.own(try js.getKey(e, v26459, v26460));
            break :conditional26457 v26461;
        } else {
            const v26462 = try o.lookup(&s, frame, "binding26429");
            break :conditional26457 v26462;
        }
    };
    return c.JS_DupValue(e.context, v26458);
}
fn body26464(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v26468 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding26465", v26468);
    const v26469 = if (args.len > 1) args[1] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding26466", v26469);
    const v26470 = if (args.len > 2) args[2] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding26467", v26470);
    const v26471 = try o.importValue(&s, graph, "guard/index.mjs", "Guard");
    const v26472 = try s.text("IsEqual");
    const v26473 = try s.own(try js.getKey(e, v26471, v26472));
    const v26474 = try o.lookup(&s, frame, "binding26466");
    const v26475 = try s.text("const");
    const v26476 = try s.own(try js.getKey(e, v26474, v26475));
    const v26477 = try o.lookup(&s, frame, "binding26467");
    const v26478 = try s.call(v26473, v26471, &.{ v26476, v26477 });
    if (s.truthy(v26478)) {
        const v26479 = try o.lookup(&s, frame, "binding26467");
        return c.JS_DupValue(e.context, v26479);
    }
    const v26480 = try o.importValue(&s, graph, "type/index.mjs", "IsLiteralBigInt");
    const v26481 = try o.lookup(&s, frame, "binding26466");
    const v26482 = try s.call(v26480, c.pi_js_undefined(), &.{v26481});
    const v26484 = conditional26483: {
        if (s.truthy(v26482)) {
            const v26485 = try o.lookup(&s, frame, "binding26307");
            const v26486 = try o.lookup(&s, frame, "binding26465");
            const v26487 = try o.lookup(&s, frame, "binding26466");
            const v26488 = try o.lookup(&s, frame, "binding26467");
            const v26489 = try s.call(v26485, c.pi_js_undefined(), &.{ v26486, v26487, v26488 });
            break :conditional26483 v26489;
        } else {
            const v26490 = try o.importValue(&s, graph, "type/index.mjs", "IsLiteralBoolean");
            const v26491 = try o.lookup(&s, frame, "binding26466");
            const v26492 = try s.call(v26490, c.pi_js_undefined(), &.{v26491});
            const v26494 = conditional26493: {
                if (s.truthy(v26492)) {
                    const v26495 = try o.lookup(&s, frame, "binding26308");
                    const v26496 = try o.lookup(&s, frame, "binding26465");
                    const v26497 = try o.lookup(&s, frame, "binding26466");
                    const v26498 = try o.lookup(&s, frame, "binding26467");
                    const v26499 = try s.call(v26495, c.pi_js_undefined(), &.{ v26496, v26497, v26498 });
                    break :conditional26493 v26499;
                } else {
                    const v26500 = try o.importValue(&s, graph, "type/index.mjs", "IsLiteralNumber");
                    const v26501 = try o.lookup(&s, frame, "binding26466");
                    const v26502 = try s.call(v26500, c.pi_js_undefined(), &.{v26501});
                    const v26504 = conditional26503: {
                        if (s.truthy(v26502)) {
                            const v26505 = try o.lookup(&s, frame, "binding26309");
                            const v26506 = try o.lookup(&s, frame, "binding26465");
                            const v26507 = try o.lookup(&s, frame, "binding26466");
                            const v26508 = try o.lookup(&s, frame, "binding26467");
                            const v26509 = try s.call(v26505, c.pi_js_undefined(), &.{ v26506, v26507, v26508 });
                            break :conditional26503 v26509;
                        } else {
                            const v26510 = try o.importValue(&s, graph, "type/index.mjs", "IsLiteralString");
                            const v26511 = try o.lookup(&s, frame, "binding26466");
                            const v26512 = try s.call(v26510, c.pi_js_undefined(), &.{v26511});
                            const v26514 = conditional26513: {
                                if (s.truthy(v26512)) {
                                    const v26515 = try o.lookup(&s, frame, "binding26310");
                                    const v26516 = try o.lookup(&s, frame, "binding26465");
                                    const v26517 = try o.lookup(&s, frame, "binding26466");
                                    const v26518 = try o.lookup(&s, frame, "binding26467");
                                    const v26519 = try s.call(v26515, c.pi_js_undefined(), &.{ v26516, v26517, v26518 });
                                    break :conditional26513 v26519;
                                } else {
                                    const v26520 = try o.importValue(&s, graph, "system/unreachable/index.mjs", "Unreachable");
                                    const v26521 = try s.call(v26520, c.pi_js_undefined(), &.{});
                                    break :conditional26513 v26521;
                                }
                            };
                            break :conditional26503 v26514;
                        }
                    };
                    break :conditional26493 v26504;
                }
            };
            break :conditional26483 v26494;
        }
    };
    return c.JS_DupValue(e.context, v26484);
}
