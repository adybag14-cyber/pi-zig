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
    const namespace = try s.get(modules, "value/convert/try/try_boolean.mjs");
    const frame = try o.frame(&s, c.pi_js_null());
    try s.put(frame, "@this", c.pi_js_undefined());
    try s.put(try s.get(graph, "frames"), "value/convert/try/try_boolean.mjs", frame);
    const bindings = try s.object();
    try s.put(try s.get(graph, "bindings"), "value/convert/try/try_boolean.mjs", bindings);
    const v27581 = try s.own(try ordinary.create(e, "FromBigInt", 1, body27554, &.{ graph, frame }));
    try o.assign(&s, frame, "binding27550", v27581);
    const v27605 = try s.own(try ordinary.create(e, "FromNumber", 1, body27582, &.{ graph, frame }));
    try o.assign(&s, frame, "binding27551", v27605);
    const v27657 = try s.own(try ordinary.create(e, "FromString", 1, body27606, &.{ graph, frame }));
    try o.assign(&s, frame, "binding27552", v27657);
    const v27721 = try s.own(try ordinary.create(e, "TryBoolean", 1, body27658, &.{ graph, frame }));
    try o.assign(&s, frame, "binding27553", v27721);
    const v27722 = try o.lookup(&s, frame, "binding27553");
    try s.put(namespace, "TryBoolean", v27722);
    const v27723 = try o.lookup(&s, frame, "binding27553");
    try s.put(namespace, "TryBoolean", v27723);
    try s.put(bindings, "TryBoolean", try s.text("binding27553"));
}
fn body27554(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v27556 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding27555", v27556);
    const v27557 = try o.importValue(&s, graph, "guard/index.mjs", "Guard");
    const v27558 = try s.text("IsEqual");
    const v27559 = try s.own(try js.getKey(e, v27557, v27558));
    const v27560 = try o.lookup(&s, frame, "binding27555");
    const v27561 = try s.global("BigInt");
    const v27562 = try s.call(v27561, c.pi_js_undefined(), &.{c.JS_NewFloat64(e.context, 0)});
    const v27563 = try s.call(v27559, v27557, &.{ v27560, v27562 });
    const v27565 = conditional27564: {
        if (s.truthy(v27563)) {
            const v27566 = try o.importValue(&s, graph, "value/convert/try/try_result.mjs", "Ok");
            const v27567 = try s.call(v27566, c.pi_js_undefined(), &.{o.boolean(&s, false)});
            break :conditional27564 v27567;
        } else {
            const v27568 = try o.importValue(&s, graph, "guard/index.mjs", "Guard");
            const v27569 = try s.text("IsEqual");
            const v27570 = try s.own(try js.getKey(e, v27568, v27569));
            const v27571 = try o.lookup(&s, frame, "binding27555");
            const v27572 = try s.global("BigInt");
            const v27573 = try s.call(v27572, c.pi_js_undefined(), &.{c.JS_NewFloat64(e.context, 1)});
            const v27574 = try s.call(v27570, v27568, &.{ v27571, v27573 });
            const v27576 = conditional27575: {
                if (s.truthy(v27574)) {
                    const v27577 = try o.importValue(&s, graph, "value/convert/try/try_result.mjs", "Ok");
                    const v27578 = try s.call(v27577, c.pi_js_undefined(), &.{o.boolean(&s, true)});
                    break :conditional27575 v27578;
                } else {
                    const v27579 = try o.importValue(&s, graph, "value/convert/try/try_result.mjs", "Fail");
                    const v27580 = try s.call(v27579, c.pi_js_undefined(), &.{});
                    break :conditional27575 v27580;
                }
            };
            break :conditional27564 v27576;
        }
    };
    return c.JS_DupValue(e.context, v27565);
}
fn body27582(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v27584 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding27583", v27584);
    const v27585 = try o.importValue(&s, graph, "guard/index.mjs", "Guard");
    const v27586 = try s.text("IsEqual");
    const v27587 = try s.own(try js.getKey(e, v27585, v27586));
    const v27588 = try o.lookup(&s, frame, "binding27583");
    const v27589 = try s.call(v27587, v27585, &.{ v27588, c.JS_NewFloat64(e.context, 0) });
    const v27591 = conditional27590: {
        if (s.truthy(v27589)) {
            const v27592 = try o.importValue(&s, graph, "value/convert/try/try_result.mjs", "Ok");
            const v27593 = try s.call(v27592, c.pi_js_undefined(), &.{o.boolean(&s, false)});
            break :conditional27590 v27593;
        } else {
            const v27594 = try o.importValue(&s, graph, "guard/index.mjs", "Guard");
            const v27595 = try s.text("IsEqual");
            const v27596 = try s.own(try js.getKey(e, v27594, v27595));
            const v27597 = try o.lookup(&s, frame, "binding27583");
            const v27598 = try s.call(v27596, v27594, &.{ v27597, c.JS_NewFloat64(e.context, 1) });
            const v27600 = conditional27599: {
                if (s.truthy(v27598)) {
                    const v27601 = try o.importValue(&s, graph, "value/convert/try/try_result.mjs", "Ok");
                    const v27602 = try s.call(v27601, c.pi_js_undefined(), &.{o.boolean(&s, true)});
                    break :conditional27599 v27602;
                } else {
                    const v27603 = try o.importValue(&s, graph, "value/convert/try/try_result.mjs", "Fail");
                    const v27604 = try s.call(v27603, c.pi_js_undefined(), &.{});
                    break :conditional27599 v27604;
                }
            };
            break :conditional27590 v27600;
        }
    };
    return c.JS_DupValue(e.context, v27591);
}
fn body27606(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v27608 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding27607", v27608);
    const v27609 = try o.importValue(&s, graph, "guard/index.mjs", "Guard");
    const v27610 = try s.text("IsEqual");
    const v27611 = try s.own(try js.getKey(e, v27609, v27610));
    const v27612 = try o.lookup(&s, frame, "binding27607");
    const v27613 = try s.text("toLowerCase");
    const v27614 = try s.own(try js.getKey(e, v27612, v27613));
    const v27615 = try s.call(v27614, v27612, &.{});
    const v27616 = try s.text("false");
    const v27617 = try s.call(v27611, v27609, &.{ v27615, v27616 });
    const v27619 = conditional27618: {
        if (s.truthy(v27617)) {
            const v27620 = try o.importValue(&s, graph, "value/convert/try/try_result.mjs", "Ok");
            const v27621 = try s.call(v27620, c.pi_js_undefined(), &.{o.boolean(&s, false)});
            break :conditional27618 v27621;
        } else {
            const v27622 = try o.importValue(&s, graph, "guard/index.mjs", "Guard");
            const v27623 = try s.text("IsEqual");
            const v27624 = try s.own(try js.getKey(e, v27622, v27623));
            const v27625 = try o.lookup(&s, frame, "binding27607");
            const v27626 = try s.text("toLowerCase");
            const v27627 = try s.own(try js.getKey(e, v27625, v27626));
            const v27628 = try s.call(v27627, v27625, &.{});
            const v27629 = try s.text("true");
            const v27630 = try s.call(v27624, v27622, &.{ v27628, v27629 });
            const v27632 = conditional27631: {
                if (s.truthy(v27630)) {
                    const v27633 = try o.importValue(&s, graph, "value/convert/try/try_result.mjs", "Ok");
                    const v27634 = try s.call(v27633, c.pi_js_undefined(), &.{o.boolean(&s, true)});
                    break :conditional27631 v27634;
                } else {
                    const v27635 = try o.importValue(&s, graph, "guard/index.mjs", "Guard");
                    const v27636 = try s.text("IsEqual");
                    const v27637 = try s.own(try js.getKey(e, v27635, v27636));
                    const v27638 = try o.lookup(&s, frame, "binding27607");
                    const v27639 = try s.text("0");
                    const v27640 = try s.call(v27637, v27635, &.{ v27638, v27639 });
                    const v27642 = conditional27641: {
                        if (s.truthy(v27640)) {
                            const v27643 = try o.importValue(&s, graph, "value/convert/try/try_result.mjs", "Ok");
                            const v27644 = try s.call(v27643, c.pi_js_undefined(), &.{o.boolean(&s, false)});
                            break :conditional27641 v27644;
                        } else {
                            const v27645 = try o.importValue(&s, graph, "guard/index.mjs", "Guard");
                            const v27646 = try s.text("IsEqual");
                            const v27647 = try s.own(try js.getKey(e, v27645, v27646));
                            const v27648 = try o.lookup(&s, frame, "binding27607");
                            const v27649 = try s.text("1");
                            const v27650 = try s.call(v27647, v27645, &.{ v27648, v27649 });
                            const v27652 = conditional27651: {
                                if (s.truthy(v27650)) {
                                    const v27653 = try o.importValue(&s, graph, "value/convert/try/try_result.mjs", "Ok");
                                    const v27654 = try s.call(v27653, c.pi_js_undefined(), &.{o.boolean(&s, true)});
                                    break :conditional27651 v27654;
                                } else {
                                    const v27655 = try o.importValue(&s, graph, "value/convert/try/try_result.mjs", "Fail");
                                    const v27656 = try s.call(v27655, c.pi_js_undefined(), &.{});
                                    break :conditional27651 v27656;
                                }
                            };
                            break :conditional27641 v27652;
                        }
                    };
                    break :conditional27631 v27642;
                }
            };
            break :conditional27618 v27632;
        }
    };
    return c.JS_DupValue(e.context, v27619);
}
fn body27658(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v27660 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding27659", v27660);
    const v27661 = try o.importValue(&s, graph, "guard/index.mjs", "Guard");
    const v27662 = try s.text("IsBigInt");
    const v27663 = try s.own(try js.getKey(e, v27661, v27662));
    const v27664 = try o.lookup(&s, frame, "binding27659");
    const v27665 = try s.call(v27663, v27661, &.{v27664});
    const v27667 = conditional27666: {
        if (s.truthy(v27665)) {
            const v27668 = try o.lookup(&s, frame, "binding27550");
            const v27669 = try o.lookup(&s, frame, "binding27659");
            const v27670 = try s.call(v27668, c.pi_js_undefined(), &.{v27669});
            break :conditional27666 v27670;
        } else {
            const v27671 = try o.importValue(&s, graph, "guard/index.mjs", "Guard");
            const v27672 = try s.text("IsBoolean");
            const v27673 = try s.own(try js.getKey(e, v27671, v27672));
            const v27674 = try o.lookup(&s, frame, "binding27659");
            const v27675 = try s.call(v27673, v27671, &.{v27674});
            const v27677 = conditional27676: {
                if (s.truthy(v27675)) {
                    const v27678 = try o.importValue(&s, graph, "value/convert/try/try_result.mjs", "Ok");
                    const v27679 = try o.lookup(&s, frame, "binding27659");
                    const v27680 = try s.call(v27678, c.pi_js_undefined(), &.{v27679});
                    break :conditional27676 v27680;
                } else {
                    const v27681 = try o.importValue(&s, graph, "guard/index.mjs", "Guard");
                    const v27682 = try s.text("IsNumber");
                    const v27683 = try s.own(try js.getKey(e, v27681, v27682));
                    const v27684 = try o.lookup(&s, frame, "binding27659");
                    const v27685 = try s.call(v27683, v27681, &.{v27684});
                    const v27687 = conditional27686: {
                        if (s.truthy(v27685)) {
                            const v27688 = try o.lookup(&s, frame, "binding27551");
                            const v27689 = try o.lookup(&s, frame, "binding27659");
                            const v27690 = try s.call(v27688, c.pi_js_undefined(), &.{v27689});
                            break :conditional27686 v27690;
                        } else {
                            const v27691 = try o.importValue(&s, graph, "guard/index.mjs", "Guard");
                            const v27692 = try s.text("IsNull");
                            const v27693 = try s.own(try js.getKey(e, v27691, v27692));
                            const v27694 = try o.lookup(&s, frame, "binding27659");
                            const v27695 = try s.call(v27693, v27691, &.{v27694});
                            const v27697 = conditional27696: {
                                if (s.truthy(v27695)) {
                                    const v27698 = try o.importValue(&s, graph, "value/convert/try/try_result.mjs", "Ok");
                                    const v27699 = try s.call(v27698, c.pi_js_undefined(), &.{o.boolean(&s, false)});
                                    break :conditional27696 v27699;
                                } else {
                                    const v27700 = try o.importValue(&s, graph, "guard/index.mjs", "Guard");
                                    const v27701 = try s.text("IsString");
                                    const v27702 = try s.own(try js.getKey(e, v27700, v27701));
                                    const v27703 = try o.lookup(&s, frame, "binding27659");
                                    const v27704 = try s.call(v27702, v27700, &.{v27703});
                                    const v27706 = conditional27705: {
                                        if (s.truthy(v27704)) {
                                            const v27707 = try o.lookup(&s, frame, "binding27552");
                                            const v27708 = try o.lookup(&s, frame, "binding27659");
                                            const v27709 = try s.call(v27707, c.pi_js_undefined(), &.{v27708});
                                            break :conditional27705 v27709;
                                        } else {
                                            const v27710 = try o.importValue(&s, graph, "guard/index.mjs", "Guard");
                                            const v27711 = try s.text("IsUndefined");
                                            const v27712 = try s.own(try js.getKey(e, v27710, v27711));
                                            const v27713 = try o.lookup(&s, frame, "binding27659");
                                            const v27714 = try s.call(v27712, v27710, &.{v27713});
                                            const v27716 = conditional27715: {
                                                if (s.truthy(v27714)) {
                                                    const v27717 = try o.importValue(&s, graph, "value/convert/try/try_result.mjs", "Ok");
                                                    const v27718 = try s.call(v27717, c.pi_js_undefined(), &.{o.boolean(&s, false)});
                                                    break :conditional27715 v27718;
                                                } else {
                                                    const v27719 = try o.importValue(&s, graph, "value/convert/try/try_result.mjs", "Fail");
                                                    const v27720 = try s.call(v27719, c.pi_js_undefined(), &.{});
                                                    break :conditional27715 v27720;
                                                }
                                            };
                                            break :conditional27705 v27716;
                                        }
                                    };
                                    break :conditional27696 v27706;
                                }
                            };
                            break :conditional27686 v27697;
                        }
                    };
                    break :conditional27676 v27687;
                }
            };
            break :conditional27666 v27677;
        }
    };
    return c.JS_DupValue(e.context, v27667);
}
