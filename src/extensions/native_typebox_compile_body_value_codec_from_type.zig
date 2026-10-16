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
    const namespace = try s.get(modules, "value/codec/from_type.mjs");
    const frame = try o.frame(&s, c.pi_js_null());
    try s.put(frame, "@this", c.pi_js_undefined());
    try s.put(try s.get(graph, "frames"), "value/codec/from_type.mjs", frame);
    const bindings = try s.object();
    try s.put(try s.get(graph, "bindings"), "value/codec/from_type.mjs", bindings);
    const v25532 = try s.own(try ordinary.create(e, "FromType", 4, body25413, &.{ graph, frame }));
    try o.assign(&s, frame, "binding25412", v25532);
    const v25533 = try o.lookup(&s, frame, "binding25412");
    try s.put(namespace, "FromType", v25533);
    const v25534 = try o.lookup(&s, frame, "binding25412");
    try s.put(namespace, "FromType", v25534);
    try s.put(bindings, "FromType", try s.text("binding25412"));
}
fn body25413(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v25418 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding25414", v25418);
    const v25419 = if (args.len > 1) args[1] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding25415", v25419);
    const v25420 = if (args.len > 2) args[2] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding25416", v25420);
    const v25421 = if (args.len > 3) args[3] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding25417", v25421);
    const v25422 = try o.importValue(&s, graph, "type/index.mjs", "*");
    const v25423 = try s.text("IsArray");
    const v25424 = try s.own(try js.getKey(e, v25422, v25423));
    const v25425 = try o.lookup(&s, frame, "binding25416");
    const v25426 = try s.call(v25424, v25422, &.{v25425});
    const v25428 = conditional25427: {
        if (s.truthy(v25426)) {
            const v25429 = try o.importValue(&s, graph, "value/codec/from_array.mjs", "FromArray");
            const v25430 = try o.lookup(&s, frame, "binding25414");
            const v25431 = try o.lookup(&s, frame, "binding25415");
            const v25432 = try o.lookup(&s, frame, "binding25416");
            const v25433 = try o.lookup(&s, frame, "binding25417");
            const v25434 = try s.call(v25429, c.pi_js_undefined(), &.{ v25430, v25431, v25432, v25433 });
            break :conditional25427 v25434;
        } else {
            const v25435 = try o.importValue(&s, graph, "type/index.mjs", "*");
            const v25436 = try s.text("IsCyclic");
            const v25437 = try s.own(try js.getKey(e, v25435, v25436));
            const v25438 = try o.lookup(&s, frame, "binding25416");
            const v25439 = try s.call(v25437, v25435, &.{v25438});
            const v25441 = conditional25440: {
                if (s.truthy(v25439)) {
                    const v25442 = try o.importValue(&s, graph, "value/codec/from_cyclic.mjs", "FromCyclic");
                    const v25443 = try o.lookup(&s, frame, "binding25414");
                    const v25444 = try o.lookup(&s, frame, "binding25415");
                    const v25445 = try o.lookup(&s, frame, "binding25416");
                    const v25446 = try o.lookup(&s, frame, "binding25417");
                    const v25447 = try s.call(v25442, c.pi_js_undefined(), &.{ v25443, v25444, v25445, v25446 });
                    break :conditional25440 v25447;
                } else {
                    const v25448 = try o.importValue(&s, graph, "type/index.mjs", "*");
                    const v25449 = try s.text("IsIntersect");
                    const v25450 = try s.own(try js.getKey(e, v25448, v25449));
                    const v25451 = try o.lookup(&s, frame, "binding25416");
                    const v25452 = try s.call(v25450, v25448, &.{v25451});
                    const v25454 = conditional25453: {
                        if (s.truthy(v25452)) {
                            const v25455 = try o.importValue(&s, graph, "value/codec/from_intersect.mjs", "FromIntersect");
                            const v25456 = try o.lookup(&s, frame, "binding25414");
                            const v25457 = try o.lookup(&s, frame, "binding25415");
                            const v25458 = try o.lookup(&s, frame, "binding25416");
                            const v25459 = try o.lookup(&s, frame, "binding25417");
                            const v25460 = try s.call(v25455, c.pi_js_undefined(), &.{ v25456, v25457, v25458, v25459 });
                            break :conditional25453 v25460;
                        } else {
                            const v25461 = try o.importValue(&s, graph, "type/index.mjs", "*");
                            const v25462 = try s.text("IsObject");
                            const v25463 = try s.own(try js.getKey(e, v25461, v25462));
                            const v25464 = try o.lookup(&s, frame, "binding25416");
                            const v25465 = try s.call(v25463, v25461, &.{v25464});
                            const v25467 = conditional25466: {
                                if (s.truthy(v25465)) {
                                    const v25468 = try o.importValue(&s, graph, "value/codec/from_object.mjs", "FromObject");
                                    const v25469 = try o.lookup(&s, frame, "binding25414");
                                    const v25470 = try o.lookup(&s, frame, "binding25415");
                                    const v25471 = try o.lookup(&s, frame, "binding25416");
                                    const v25472 = try o.lookup(&s, frame, "binding25417");
                                    const v25473 = try s.call(v25468, c.pi_js_undefined(), &.{ v25469, v25470, v25471, v25472 });
                                    break :conditional25466 v25473;
                                } else {
                                    const v25474 = try o.importValue(&s, graph, "type/index.mjs", "*");
                                    const v25475 = try s.text("IsRecord");
                                    const v25476 = try s.own(try js.getKey(e, v25474, v25475));
                                    const v25477 = try o.lookup(&s, frame, "binding25416");
                                    const v25478 = try s.call(v25476, v25474, &.{v25477});
                                    const v25480 = conditional25479: {
                                        if (s.truthy(v25478)) {
                                            const v25481 = try o.importValue(&s, graph, "value/codec/from_record.mjs", "FromRecord");
                                            const v25482 = try o.lookup(&s, frame, "binding25414");
                                            const v25483 = try o.lookup(&s, frame, "binding25415");
                                            const v25484 = try o.lookup(&s, frame, "binding25416");
                                            const v25485 = try o.lookup(&s, frame, "binding25417");
                                            const v25486 = try s.call(v25481, c.pi_js_undefined(), &.{ v25482, v25483, v25484, v25485 });
                                            break :conditional25479 v25486;
                                        } else {
                                            const v25487 = try o.importValue(&s, graph, "type/index.mjs", "*");
                                            const v25488 = try s.text("IsRef");
                                            const v25489 = try s.own(try js.getKey(e, v25487, v25488));
                                            const v25490 = try o.lookup(&s, frame, "binding25416");
                                            const v25491 = try s.call(v25489, v25487, &.{v25490});
                                            const v25493 = conditional25492: {
                                                if (s.truthy(v25491)) {
                                                    const v25494 = try o.importValue(&s, graph, "value/codec/from_ref.mjs", "FromRef");
                                                    const v25495 = try o.lookup(&s, frame, "binding25414");
                                                    const v25496 = try o.lookup(&s, frame, "binding25415");
                                                    const v25497 = try o.lookup(&s, frame, "binding25416");
                                                    const v25498 = try o.lookup(&s, frame, "binding25417");
                                                    const v25499 = try s.call(v25494, c.pi_js_undefined(), &.{ v25495, v25496, v25497, v25498 });
                                                    break :conditional25492 v25499;
                                                } else {
                                                    const v25500 = try o.importValue(&s, graph, "type/index.mjs", "*");
                                                    const v25501 = try s.text("IsTuple");
                                                    const v25502 = try s.own(try js.getKey(e, v25500, v25501));
                                                    const v25503 = try o.lookup(&s, frame, "binding25416");
                                                    const v25504 = try s.call(v25502, v25500, &.{v25503});
                                                    const v25506 = conditional25505: {
                                                        if (s.truthy(v25504)) {
                                                            const v25507 = try o.importValue(&s, graph, "value/codec/from_tuple.mjs", "FromTuple");
                                                            const v25508 = try o.lookup(&s, frame, "binding25414");
                                                            const v25509 = try o.lookup(&s, frame, "binding25415");
                                                            const v25510 = try o.lookup(&s, frame, "binding25416");
                                                            const v25511 = try o.lookup(&s, frame, "binding25417");
                                                            const v25512 = try s.call(v25507, c.pi_js_undefined(), &.{ v25508, v25509, v25510, v25511 });
                                                            break :conditional25505 v25512;
                                                        } else {
                                                            const v25513 = try o.importValue(&s, graph, "type/index.mjs", "*");
                                                            const v25514 = try s.text("IsUnion");
                                                            const v25515 = try s.own(try js.getKey(e, v25513, v25514));
                                                            const v25516 = try o.lookup(&s, frame, "binding25416");
                                                            const v25517 = try s.call(v25515, v25513, &.{v25516});
                                                            const v25519 = conditional25518: {
                                                                if (s.truthy(v25517)) {
                                                                    const v25520 = try o.importValue(&s, graph, "value/codec/from_union.mjs", "FromUnion");
                                                                    const v25521 = try o.lookup(&s, frame, "binding25414");
                                                                    const v25522 = try o.lookup(&s, frame, "binding25415");
                                                                    const v25523 = try o.lookup(&s, frame, "binding25416");
                                                                    const v25524 = try o.lookup(&s, frame, "binding25417");
                                                                    const v25525 = try s.call(v25520, c.pi_js_undefined(), &.{ v25521, v25522, v25523, v25524 });
                                                                    break :conditional25518 v25525;
                                                                } else {
                                                                    const v25526 = try o.importValue(&s, graph, "value/codec/callback.mjs", "Callback");
                                                                    const v25527 = try o.lookup(&s, frame, "binding25414");
                                                                    const v25528 = try o.lookup(&s, frame, "binding25415");
                                                                    const v25529 = try o.lookup(&s, frame, "binding25416");
                                                                    const v25530 = try o.lookup(&s, frame, "binding25417");
                                                                    const v25531 = try s.call(v25526, c.pi_js_undefined(), &.{ v25527, v25528, v25529, v25530 });
                                                                    break :conditional25518 v25531;
                                                                }
                                                            };
                                                            break :conditional25505 v25519;
                                                        }
                                                    };
                                                    break :conditional25492 v25506;
                                                }
                                            };
                                            break :conditional25479 v25493;
                                        }
                                    };
                                    break :conditional25466 v25480;
                                }
                            };
                            break :conditional25453 v25467;
                        }
                    };
                    break :conditional25440 v25454;
                }
            };
            break :conditional25427 v25441;
        }
    };
    return c.JS_DupValue(e.context, v25428);
}
