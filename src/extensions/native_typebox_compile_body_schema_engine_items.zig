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
    const namespace = try s.get(modules, "schema/engine/items.mjs");
    const frame = try o.frame(&s, c.pi_js_null());
    try s.put(frame, "@this", c.pi_js_undefined());
    try s.put(try s.get(graph, "frames"), "schema/engine/items.mjs", frame);
    const bindings = try s.object();
    try s.put(try s.get(graph, "bindings"), "schema/engine/items.mjs", bindings);
    const v9594 = try s.own(try ordinary.create(e, "BuildItemsSizedStandard", 4, body9511, &.{ graph, frame }));
    try o.assign(&s, frame, "binding9498", v9594);
    const v9662 = try s.own(try ordinary.create(e, "BuildItemsSizedFast", 4, body9595, &.{ graph, frame }));
    try o.assign(&s, frame, "binding9499", v9662);
    const v9690 = try s.own(try ordinary.create(e, "BuildItemsSized", 4, body9663, &.{ graph, frame }));
    try o.assign(&s, frame, "binding9500", v9690);
    const v9740 = try s.own(try ordinary.create(e, "CheckItemsSized", 4, body9691, &.{ graph, frame }));
    try o.assign(&s, frame, "binding9501", v9740);
    const v9822 = try s.own(try ordinary.create(e, "ErrorItemsSized", 6, body9741, &.{ graph, frame }));
    try o.assign(&s, frame, "binding9502", v9822);
    const v9882 = try s.own(try ordinary.create(e, "BuildItemsUnsizedStandard", 4, body9823, &.{ graph, frame }));
    try o.assign(&s, frame, "binding9503", v9882);
    const v9930 = try s.own(try ordinary.create(e, "BuildItemsUnsizedFast", 4, body9883, &.{ graph, frame }));
    try o.assign(&s, frame, "binding9504", v9930);
    const v9958 = try s.own(try ordinary.create(e, "BuildItemsUnsized", 4, body9931, &.{ graph, frame }));
    try o.assign(&s, frame, "binding9505", v9958);
    const v10010 = try s.own(try ordinary.create(e, "CheckItemsUnsized", 4, body9959, &.{ graph, frame }));
    try o.assign(&s, frame, "binding9506", v10010);
    const v10089 = try s.own(try ordinary.create(e, "ErrorItemsUnsized", 6, body10011, &.{ graph, frame }));
    try o.assign(&s, frame, "binding9507", v10089);
    const v10118 = try s.own(try ordinary.create(e, "BuildItems", 4, body10090, &.{ graph, frame }));
    try o.assign(&s, frame, "binding9508", v10118);
    const v10147 = try s.own(try ordinary.create(e, "CheckItems", 4, body10119, &.{ graph, frame }));
    try o.assign(&s, frame, "binding9509", v10147);
    const v10184 = try s.own(try ordinary.create(e, "ErrorItems", 6, body10148, &.{ graph, frame }));
    try o.assign(&s, frame, "binding9510", v10184);
    const v10185 = try o.lookup(&s, frame, "binding9508");
    try s.put(namespace, "BuildItems", v10185);
    const v10186 = try o.lookup(&s, frame, "binding9509");
    try s.put(namespace, "CheckItems", v10186);
    const v10187 = try o.lookup(&s, frame, "binding9510");
    try s.put(namespace, "ErrorItems", v10187);
    const v10188 = try o.lookup(&s, frame, "binding9508");
    try s.put(namespace, "BuildItems", v10188);
    const v10189 = try o.lookup(&s, frame, "binding9509");
    try s.put(namespace, "CheckItems", v10189);
    const v10190 = try o.lookup(&s, frame, "binding9510");
    try s.put(namespace, "ErrorItems", v10190);
    try s.put(bindings, "BuildItems", try s.text("binding9508"));
    try s.put(bindings, "CheckItems", try s.text("binding9509"));
    try s.put(bindings, "ErrorItems", try s.text("binding9510"));
}
fn body9528(e: *Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    _ = try o.lookup(&s, frame, "@this");
    const v9535 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding9530", v9535);
    const v9536 = if (args.len > 1) args[1] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding9531", v9536);
    const v9540 = try o.importValue(&s, graph, "guard/index.mjs", "EmitGuard");
    const v9541 = try s.text("IsLessEqualThan");
    const v9542 = try s.own(try js.getKey(e, v9540, v9541));
    const v9543 = try o.importValue(&s, graph, "guard/index.mjs", "EmitGuard");
    const v9544 = try s.text("Member");
    const v9545 = try s.own(try js.getKey(e, v9543, v9544));
    const v9546 = try o.lookup(&s, frame, "binding9515");
    const v9547 = try s.text("length");
    const v9548 = try s.call(v9545, v9543, &.{ v9546, v9547 });
    const v9549 = try o.importValue(&s, graph, "guard/index.mjs", "EmitGuard");
    const v9550 = try s.text("Constant");
    const v9551 = try s.own(try js.getKey(e, v9549, v9550));
    const v9552 = try o.lookup(&s, frame, "binding9531");
    const v9553 = try s.call(v9551, v9549, &.{v9552});
    const v9554 = try s.call(v9542, v9540, &.{ v9548, v9553 });
    try o.assign(&s, frame, "binding9537", v9554);
    const v9555 = try o.importValue(&s, graph, "schema/engine/schema.mjs", "BuildSchemaPushStack");
    const v9556 = try o.lookup(&s, frame, "binding9512");
    const v9557 = try o.lookup(&s, frame, "binding9513");
    const v9558 = try o.lookup(&s, frame, "binding9530");
    const v9559 = try s.text("");
    const v9560 = try o.lookup(&s, frame, "binding9515");
    const v9561 = try s.stringify(v9560);
    const v9562 = try s.concat(v9559, v9561);
    const v9563 = try s.text("[");
    const v9564 = try s.concat(v9562, v9563);
    const v9565 = try o.lookup(&s, frame, "binding9531");
    const v9566 = try s.stringify(v9565);
    const v9567 = try s.concat(v9564, v9566);
    const v9568 = try s.text("]");
    const v9569 = try s.concat(v9567, v9568);
    const v9570 = try s.call(v9555, c.pi_js_undefined(), &.{ v9556, v9557, v9558, v9569 });
    try o.assign(&s, frame, "binding9538", v9570);
    const v9571 = try o.lookup(&s, frame, "binding9513");
    const v9572 = try s.text("AddIndex");
    const v9573 = try s.own(try js.getKey(e, v9571, v9572));
    const v9574 = try o.importValue(&s, graph, "guard/index.mjs", "EmitGuard");
    const v9575 = try s.text("Constant");
    const v9576 = try s.own(try js.getKey(e, v9574, v9575));
    const v9577 = try o.lookup(&s, frame, "binding9531");
    const v9578 = try s.call(v9576, v9574, &.{v9577});
    const v9579 = try s.call(v9573, v9571, &.{v9578});
    try o.assign(&s, frame, "binding9539", v9579);
    const v9580 = try o.importValue(&s, graph, "guard/index.mjs", "EmitGuard");
    const v9581 = try s.text("Or");
    const v9582 = try s.own(try js.getKey(e, v9580, v9581));
    const v9583 = try o.lookup(&s, frame, "binding9537");
    const v9584 = try o.importValue(&s, graph, "guard/index.mjs", "EmitGuard");
    const v9585 = try s.text("And");
    const v9586 = try s.own(try js.getKey(e, v9584, v9585));
    const v9587 = try o.lookup(&s, frame, "binding9538");
    const v9588 = try o.lookup(&s, frame, "binding9539");
    const v9589 = try s.call(v9586, v9584, &.{ v9587, v9588 });
    const v9590 = try s.call(v9582, v9580, &.{ v9583, v9589 });
    return c.JS_DupValue(e.context, v9590);
}
fn body9528C(ctx: ?*c.JSContext, receiver: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const e = Engine.fromContext(ctx.?);
    return body9528(e, receiver, if (argc > 0) argv[0..@intCast(argc)] else &.{}, roots[0..2]) catch |err| sdk.fail(e, err);
}
fn body9511(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v9516 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding9512", v9516);
    const v9517 = if (args.len > 1) args[1] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding9513", v9517);
    const v9518 = if (args.len > 2) args[2] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding9514", v9518);
    const v9519 = if (args.len > 3) args[3] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding9515", v9519);
    const v9520 = try o.importValue(&s, graph, "guard/index.mjs", "EmitGuard");
    const v9521 = try s.text("ReduceAnd");
    const v9522 = try s.own(try js.getKey(e, v9520, v9521));
    const v9523 = try o.lookup(&s, frame, "binding9514");
    const v9524 = try s.text("items");
    const v9525 = try s.own(try js.getKey(e, v9523, v9524));
    const v9526 = try s.text("map");
    const v9527 = try s.own(try js.getKey(e, v9525, v9526));
    const v9591 = try o.arrow(&s, "", 2, body9528C, &.{ graph, frame });
    const v9592 = try s.call(v9527, v9525, &.{v9591});
    const v9593 = try s.call(v9522, v9520, &.{v9592});
    return c.JS_DupValue(e.context, v9593);
}
fn body9612(e: *Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    _ = try o.lookup(&s, frame, "@this");
    const v9618 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding9614", v9618);
    const v9619 = if (args.len > 1) args[1] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding9615", v9619);
    const v9622 = try o.importValue(&s, graph, "guard/index.mjs", "EmitGuard");
    const v9623 = try s.text("IsLessEqualThan");
    const v9624 = try s.own(try js.getKey(e, v9622, v9623));
    const v9625 = try o.importValue(&s, graph, "guard/index.mjs", "EmitGuard");
    const v9626 = try s.text("Member");
    const v9627 = try s.own(try js.getKey(e, v9625, v9626));
    const v9628 = try o.lookup(&s, frame, "binding9599");
    const v9629 = try s.text("length");
    const v9630 = try s.call(v9627, v9625, &.{ v9628, v9629 });
    const v9631 = try o.importValue(&s, graph, "guard/index.mjs", "EmitGuard");
    const v9632 = try s.text("Constant");
    const v9633 = try s.own(try js.getKey(e, v9631, v9632));
    const v9634 = try o.lookup(&s, frame, "binding9615");
    const v9635 = try s.call(v9633, v9631, &.{v9634});
    const v9636 = try s.call(v9624, v9622, &.{ v9630, v9635 });
    try o.assign(&s, frame, "binding9620", v9636);
    const v9637 = try o.importValue(&s, graph, "schema/engine/schema.mjs", "BuildSchemaPushStack");
    const v9638 = try o.lookup(&s, frame, "binding9596");
    const v9639 = try o.lookup(&s, frame, "binding9597");
    const v9640 = try o.lookup(&s, frame, "binding9614");
    const v9641 = try s.text("");
    const v9642 = try o.lookup(&s, frame, "binding9599");
    const v9643 = try s.stringify(v9642);
    const v9644 = try s.concat(v9641, v9643);
    const v9645 = try s.text("[");
    const v9646 = try s.concat(v9644, v9645);
    const v9647 = try o.lookup(&s, frame, "binding9615");
    const v9648 = try s.stringify(v9647);
    const v9649 = try s.concat(v9646, v9648);
    const v9650 = try s.text("]");
    const v9651 = try s.concat(v9649, v9650);
    const v9652 = try s.call(v9637, c.pi_js_undefined(), &.{ v9638, v9639, v9640, v9651 });
    try o.assign(&s, frame, "binding9621", v9652);
    const v9653 = try o.importValue(&s, graph, "guard/index.mjs", "EmitGuard");
    const v9654 = try s.text("Or");
    const v9655 = try s.own(try js.getKey(e, v9653, v9654));
    const v9656 = try o.lookup(&s, frame, "binding9620");
    const v9657 = try o.lookup(&s, frame, "binding9621");
    const v9658 = try s.call(v9655, v9653, &.{ v9656, v9657 });
    return c.JS_DupValue(e.context, v9658);
}
fn body9612C(ctx: ?*c.JSContext, receiver: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const e = Engine.fromContext(ctx.?);
    return body9612(e, receiver, if (argc > 0) argv[0..@intCast(argc)] else &.{}, roots[0..2]) catch |err| sdk.fail(e, err);
}
fn body9595(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v9600 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding9596", v9600);
    const v9601 = if (args.len > 1) args[1] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding9597", v9601);
    const v9602 = if (args.len > 2) args[2] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding9598", v9602);
    const v9603 = if (args.len > 3) args[3] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding9599", v9603);
    const v9604 = try o.importValue(&s, graph, "guard/index.mjs", "EmitGuard");
    const v9605 = try s.text("ReduceAnd");
    const v9606 = try s.own(try js.getKey(e, v9604, v9605));
    const v9607 = try o.lookup(&s, frame, "binding9598");
    const v9608 = try s.text("items");
    const v9609 = try s.own(try js.getKey(e, v9607, v9608));
    const v9610 = try s.text("map");
    const v9611 = try s.own(try js.getKey(e, v9609, v9610));
    const v9659 = try o.arrow(&s, "", 2, body9612C, &.{ graph, frame });
    const v9660 = try s.call(v9611, v9609, &.{v9659});
    const v9661 = try s.call(v9606, v9604, &.{v9660});
    return c.JS_DupValue(e.context, v9661);
}
fn body9663(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    _ = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v9668 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding9664", v9668);
    const v9669 = if (args.len > 1) args[1] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding9665", v9669);
    const v9670 = if (args.len > 2) args[2] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding9666", v9670);
    const v9671 = if (args.len > 3) args[3] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding9667", v9671);
    const v9672 = try o.lookup(&s, frame, "binding9665");
    const v9673 = try s.text("UseUnevaluated");
    const v9674 = try s.own(try js.getKey(e, v9672, v9673));
    const v9675 = try s.call(v9674, v9672, &.{});
    const v9677 = conditional9676: {
        if (s.truthy(v9675)) {
            const v9678 = try o.lookup(&s, frame, "binding9498");
            const v9679 = try o.lookup(&s, frame, "binding9664");
            const v9680 = try o.lookup(&s, frame, "binding9665");
            const v9681 = try o.lookup(&s, frame, "binding9666");
            const v9682 = try o.lookup(&s, frame, "binding9667");
            const v9683 = try s.call(v9678, c.pi_js_undefined(), &.{ v9679, v9680, v9681, v9682 });
            break :conditional9676 v9683;
        } else {
            const v9684 = try o.lookup(&s, frame, "binding9499");
            const v9685 = try o.lookup(&s, frame, "binding9664");
            const v9686 = try o.lookup(&s, frame, "binding9665");
            const v9687 = try o.lookup(&s, frame, "binding9666");
            const v9688 = try o.lookup(&s, frame, "binding9667");
            const v9689 = try s.call(v9684, c.pi_js_undefined(), &.{ v9685, v9686, v9687, v9688 });
            break :conditional9676 v9689;
        }
    };
    return c.JS_DupValue(e.context, v9677);
}
fn body9706(e: *Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    _ = try o.lookup(&s, frame, "@this");
    const v9710 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding9708", v9710);
    const v9711 = if (args.len > 1) args[1] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding9709", v9711);
    const v9712 = try o.importValue(&s, graph, "guard/index.mjs", "Guard");
    const v9713 = try s.text("IsLessEqualThan");
    const v9714 = try s.own(try js.getKey(e, v9712, v9713));
    const v9715 = try o.lookup(&s, frame, "binding9695");
    const v9716 = try s.text("length");
    const v9717 = try s.own(try js.getKey(e, v9715, v9716));
    const v9718 = try o.lookup(&s, frame, "binding9709");
    const v9719 = try s.call(v9714, v9712, &.{ v9717, v9718 });
    const v9721 = logical9720: {
        if (s.truthy(v9719)) break :logical9720 v9719;
        const v9722 = try o.importValue(&s, graph, "schema/engine/schema.mjs", "CheckSchemaPushStack");
        const v9723 = try o.lookup(&s, frame, "binding9692");
        const v9724 = try o.lookup(&s, frame, "binding9693");
        const v9725 = try o.lookup(&s, frame, "binding9708");
        const v9726 = try o.lookup(&s, frame, "binding9695");
        const v9727 = try o.lookup(&s, frame, "binding9709");
        const v9728 = try o.propertyKey(&s, v9727);
        const v9729 = try s.own(try js.getKey(e, v9726, v9728));
        const v9730 = try s.call(v9722, c.pi_js_undefined(), &.{ v9723, v9724, v9725, v9729 });
        const v9732 = logical9731: {
            if (!s.truthy(v9730)) break :logical9731 v9730;
            const v9733 = try o.lookup(&s, frame, "binding9693");
            const v9734 = try s.text("AddIndex");
            const v9735 = try s.own(try js.getKey(e, v9733, v9734));
            const v9736 = try o.lookup(&s, frame, "binding9709");
            const v9737 = try s.call(v9735, v9733, &.{v9736});
            break :logical9731 v9737;
        };
        break :logical9720 v9732;
    };
    return c.JS_DupValue(e.context, v9721);
}
fn body9706C(ctx: ?*c.JSContext, receiver: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const e = Engine.fromContext(ctx.?);
    return body9706(e, receiver, if (argc > 0) argv[0..@intCast(argc)] else &.{}, roots[0..2]) catch |err| sdk.fail(e, err);
}
fn body9691(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v9696 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding9692", v9696);
    const v9697 = if (args.len > 1) args[1] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding9693", v9697);
    const v9698 = if (args.len > 2) args[2] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding9694", v9698);
    const v9699 = if (args.len > 3) args[3] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding9695", v9699);
    const v9700 = try o.importValue(&s, graph, "guard/index.mjs", "Guard");
    const v9701 = try s.text("Every");
    const v9702 = try s.own(try js.getKey(e, v9700, v9701));
    const v9703 = try o.lookup(&s, frame, "binding9694");
    const v9704 = try s.text("items");
    const v9705 = try s.own(try js.getKey(e, v9703, v9704));
    const v9738 = try o.arrow(&s, "", 2, body9706C, &.{ graph, frame });
    const v9739 = try s.call(v9702, v9700, &.{ v9705, c.JS_NewFloat64(e.context, 0), v9738 });
    return c.JS_DupValue(e.context, v9739);
}
fn body9760(e: *Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    _ = try o.lookup(&s, frame, "@this");
    const v9766 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding9762", v9766);
    const v9767 = if (args.len > 1) args[1] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding9763", v9767);
    const v9770 = try s.text("");
    const v9771 = try o.lookup(&s, frame, "binding9744");
    const v9772 = try s.stringify(v9771);
    const v9773 = try s.concat(v9770, v9772);
    const v9774 = try s.text("/items/");
    const v9775 = try s.concat(v9773, v9774);
    const v9776 = try o.lookup(&s, frame, "binding9763");
    const v9777 = try s.stringify(v9776);
    const v9778 = try s.concat(v9775, v9777);
    const v9779 = try s.text("");
    const v9780 = try s.concat(v9778, v9779);
    try o.assign(&s, frame, "binding9768", v9780);
    const v9781 = try s.text("");
    const v9782 = try o.lookup(&s, frame, "binding9745");
    const v9783 = try s.stringify(v9782);
    const v9784 = try s.concat(v9781, v9783);
    const v9785 = try s.text("/");
    const v9786 = try s.concat(v9784, v9785);
    const v9787 = try o.lookup(&s, frame, "binding9763");
    const v9788 = try s.stringify(v9787);
    const v9789 = try s.concat(v9786, v9788);
    const v9790 = try s.text("");
    const v9791 = try s.concat(v9789, v9790);
    try o.assign(&s, frame, "binding9769", v9791);
    const v9792 = try o.importValue(&s, graph, "guard/index.mjs", "Guard");
    const v9793 = try s.text("IsLessEqualThan");
    const v9794 = try s.own(try js.getKey(e, v9792, v9793));
    const v9795 = try o.lookup(&s, frame, "binding9747");
    const v9796 = try s.text("length");
    const v9797 = try s.own(try js.getKey(e, v9795, v9796));
    const v9798 = try o.lookup(&s, frame, "binding9763");
    const v9799 = try s.call(v9794, v9792, &.{ v9797, v9798 });
    const v9801 = logical9800: {
        if (s.truthy(v9799)) break :logical9800 v9799;
        const v9802 = try o.importValue(&s, graph, "schema/engine/schema.mjs", "ErrorSchemaPushStack");
        const v9803 = try o.lookup(&s, frame, "binding9742");
        const v9804 = try o.lookup(&s, frame, "binding9743");
        const v9805 = try o.lookup(&s, frame, "binding9768");
        const v9806 = try o.lookup(&s, frame, "binding9769");
        const v9807 = try o.lookup(&s, frame, "binding9762");
        const v9808 = try o.lookup(&s, frame, "binding9747");
        const v9809 = try o.lookup(&s, frame, "binding9763");
        const v9810 = try o.propertyKey(&s, v9809);
        const v9811 = try s.own(try js.getKey(e, v9808, v9810));
        const v9812 = try s.call(v9802, c.pi_js_undefined(), &.{ v9803, v9804, v9805, v9806, v9807, v9811 });
        const v9814 = logical9813: {
            if (!s.truthy(v9812)) break :logical9813 v9812;
            const v9815 = try o.lookup(&s, frame, "binding9743");
            const v9816 = try s.text("AddIndex");
            const v9817 = try s.own(try js.getKey(e, v9815, v9816));
            const v9818 = try o.lookup(&s, frame, "binding9763");
            const v9819 = try s.call(v9817, v9815, &.{v9818});
            break :logical9813 v9819;
        };
        break :logical9800 v9814;
    };
    return c.JS_DupValue(e.context, v9801);
}
fn body9760C(ctx: ?*c.JSContext, receiver: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const e = Engine.fromContext(ctx.?);
    return body9760(e, receiver, if (argc > 0) argv[0..@intCast(argc)] else &.{}, roots[0..2]) catch |err| sdk.fail(e, err);
}
fn body9741(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v9748 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding9742", v9748);
    const v9749 = if (args.len > 1) args[1] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding9743", v9749);
    const v9750 = if (args.len > 2) args[2] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding9744", v9750);
    const v9751 = if (args.len > 3) args[3] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding9745", v9751);
    const v9752 = if (args.len > 4) args[4] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding9746", v9752);
    const v9753 = if (args.len > 5) args[5] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding9747", v9753);
    const v9754 = try o.importValue(&s, graph, "guard/index.mjs", "Guard");
    const v9755 = try s.text("EveryAll");
    const v9756 = try s.own(try js.getKey(e, v9754, v9755));
    const v9757 = try o.lookup(&s, frame, "binding9746");
    const v9758 = try s.text("items");
    const v9759 = try s.own(try js.getKey(e, v9757, v9758));
    const v9820 = try o.arrow(&s, "", 2, body9760C, &.{ graph, frame });
    const v9821 = try s.call(v9756, v9754, &.{ v9759, c.JS_NewFloat64(e.context, 0), v9820 });
    return c.JS_DupValue(e.context, v9821);
}
fn body9823(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v9831 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding9824", v9831);
    const v9832 = if (args.len > 1) args[1] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding9825", v9832);
    const v9833 = if (args.len > 2) args[2] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding9826", v9833);
    const v9834 = if (args.len > 3) args[3] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding9827", v9834);
    const v9838 = try o.importValue(&s, graph, "schema/types/index.mjs", "*");
    const v9839 = try s.text("IsPrefixItems");
    const v9840 = try s.own(try js.getKey(e, v9838, v9839));
    const v9841 = try o.lookup(&s, frame, "binding9826");
    const v9842 = try s.call(v9840, v9838, &.{v9841});
    const v9844 = conditional9843: {
        if (s.truthy(v9842)) {
            const v9845 = try o.lookup(&s, frame, "binding9826");
            const v9846 = try s.text("prefixItems");
            const v9847 = try s.own(try js.getKey(e, v9845, v9846));
            const v9848 = try s.text("length");
            const v9849 = try s.own(try js.getKey(e, v9847, v9848));
            break :conditional9843 v9849;
        } else {
            break :conditional9843 c.JS_NewFloat64(e.context, 0);
        }
    };
    try o.assign(&s, frame, "binding9835", v9844);
    const v9850 = try o.importValue(&s, graph, "schema/engine/schema.mjs", "BuildSchemaPushStack");
    const v9851 = try o.lookup(&s, frame, "binding9824");
    const v9852 = try o.lookup(&s, frame, "binding9825");
    const v9853 = try o.lookup(&s, frame, "binding9826");
    const v9854 = try s.text("items");
    const v9855 = try s.own(try js.getKey(e, v9853, v9854));
    const v9856 = try s.text("element");
    const v9857 = try s.call(v9850, c.pi_js_undefined(), &.{ v9851, v9852, v9855, v9856 });
    try o.assign(&s, frame, "binding9836", v9857);
    const v9858 = try o.lookup(&s, frame, "binding9825");
    const v9859 = try s.text("AddIndex");
    const v9860 = try s.own(try js.getKey(e, v9858, v9859));
    const v9861 = try s.text("index");
    const v9862 = try s.call(v9860, v9858, &.{v9861});
    try o.assign(&s, frame, "binding9837", v9862);
    const v9863 = try o.importValue(&s, graph, "guard/index.mjs", "EmitGuard");
    const v9864 = try s.text("Every");
    const v9865 = try s.own(try js.getKey(e, v9863, v9864));
    const v9866 = try o.lookup(&s, frame, "binding9827");
    const v9867 = try o.importValue(&s, graph, "guard/index.mjs", "EmitGuard");
    const v9868 = try s.text("Constant");
    const v9869 = try s.own(try js.getKey(e, v9867, v9868));
    const v9870 = try o.lookup(&s, frame, "binding9835");
    const v9871 = try s.call(v9869, v9867, &.{v9870});
    const v9872 = try s.array();
    const v9873 = try s.text("element");
    try o.append(&s, v9872, v9873);
    const v9874 = try s.text("index");
    try o.append(&s, v9872, v9874);
    const v9875 = try o.importValue(&s, graph, "guard/index.mjs", "EmitGuard");
    const v9876 = try s.text("And");
    const v9877 = try s.own(try js.getKey(e, v9875, v9876));
    const v9878 = try o.lookup(&s, frame, "binding9836");
    const v9879 = try o.lookup(&s, frame, "binding9837");
    const v9880 = try s.call(v9877, v9875, &.{ v9878, v9879 });
    const v9881 = try s.call(v9865, v9863, &.{ v9866, v9871, v9872, v9880 });
    return c.JS_DupValue(e.context, v9881);
}
fn body9883(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v9890 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding9884", v9890);
    const v9891 = if (args.len > 1) args[1] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding9885", v9891);
    const v9892 = if (args.len > 2) args[2] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding9886", v9892);
    const v9893 = if (args.len > 3) args[3] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding9887", v9893);
    const v9896 = try o.importValue(&s, graph, "schema/types/index.mjs", "*");
    const v9897 = try s.text("IsPrefixItems");
    const v9898 = try s.own(try js.getKey(e, v9896, v9897));
    const v9899 = try o.lookup(&s, frame, "binding9886");
    const v9900 = try s.call(v9898, v9896, &.{v9899});
    const v9902 = conditional9901: {
        if (s.truthy(v9900)) {
            const v9903 = try o.lookup(&s, frame, "binding9886");
            const v9904 = try s.text("prefixItems");
            const v9905 = try s.own(try js.getKey(e, v9903, v9904));
            const v9906 = try s.text("length");
            const v9907 = try s.own(try js.getKey(e, v9905, v9906));
            break :conditional9901 v9907;
        } else {
            break :conditional9901 c.JS_NewFloat64(e.context, 0);
        }
    };
    try o.assign(&s, frame, "binding9894", v9902);
    const v9908 = try o.importValue(&s, graph, "schema/engine/schema.mjs", "BuildSchemaPushStack");
    const v9909 = try o.lookup(&s, frame, "binding9884");
    const v9910 = try o.lookup(&s, frame, "binding9885");
    const v9911 = try o.lookup(&s, frame, "binding9886");
    const v9912 = try s.text("items");
    const v9913 = try s.own(try js.getKey(e, v9911, v9912));
    const v9914 = try s.text("element");
    const v9915 = try s.call(v9908, c.pi_js_undefined(), &.{ v9909, v9910, v9913, v9914 });
    try o.assign(&s, frame, "binding9895", v9915);
    const v9916 = try o.importValue(&s, graph, "guard/index.mjs", "EmitGuard");
    const v9917 = try s.text("Every");
    const v9918 = try s.own(try js.getKey(e, v9916, v9917));
    const v9919 = try o.lookup(&s, frame, "binding9887");
    const v9920 = try o.importValue(&s, graph, "guard/index.mjs", "EmitGuard");
    const v9921 = try s.text("Constant");
    const v9922 = try s.own(try js.getKey(e, v9920, v9921));
    const v9923 = try o.lookup(&s, frame, "binding9894");
    const v9924 = try s.call(v9922, v9920, &.{v9923});
    const v9925 = try s.array();
    const v9926 = try s.text("element");
    try o.append(&s, v9925, v9926);
    const v9927 = try s.text("index");
    try o.append(&s, v9925, v9927);
    const v9928 = try o.lookup(&s, frame, "binding9895");
    const v9929 = try s.call(v9918, v9916, &.{ v9919, v9924, v9925, v9928 });
    return c.JS_DupValue(e.context, v9929);
}
fn body9931(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    _ = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v9936 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding9932", v9936);
    const v9937 = if (args.len > 1) args[1] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding9933", v9937);
    const v9938 = if (args.len > 2) args[2] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding9934", v9938);
    const v9939 = if (args.len > 3) args[3] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding9935", v9939);
    const v9940 = try o.lookup(&s, frame, "binding9933");
    const v9941 = try s.text("UseUnevaluated");
    const v9942 = try s.own(try js.getKey(e, v9940, v9941));
    const v9943 = try s.call(v9942, v9940, &.{});
    const v9945 = conditional9944: {
        if (s.truthy(v9943)) {
            const v9946 = try o.lookup(&s, frame, "binding9503");
            const v9947 = try o.lookup(&s, frame, "binding9932");
            const v9948 = try o.lookup(&s, frame, "binding9933");
            const v9949 = try o.lookup(&s, frame, "binding9934");
            const v9950 = try o.lookup(&s, frame, "binding9935");
            const v9951 = try s.call(v9946, c.pi_js_undefined(), &.{ v9947, v9948, v9949, v9950 });
            break :conditional9944 v9951;
        } else {
            const v9952 = try o.lookup(&s, frame, "binding9504");
            const v9953 = try o.lookup(&s, frame, "binding9932");
            const v9954 = try o.lookup(&s, frame, "binding9933");
            const v9955 = try o.lookup(&s, frame, "binding9934");
            const v9956 = try o.lookup(&s, frame, "binding9935");
            const v9957 = try s.call(v9952, c.pi_js_undefined(), &.{ v9953, v9954, v9955, v9956 });
            break :conditional9944 v9957;
        }
    };
    return c.JS_DupValue(e.context, v9945);
}
fn body9987(e: *Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    _ = try o.lookup(&s, frame, "@this");
    const v9991 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding9989", v9991);
    const v9992 = if (args.len > 1) args[1] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding9990", v9992);
    const v9993 = try o.importValue(&s, graph, "schema/engine/schema.mjs", "CheckSchemaPushStack");
    const v9994 = try o.lookup(&s, frame, "binding9960");
    const v9995 = try o.lookup(&s, frame, "binding9961");
    const v9996 = try o.lookup(&s, frame, "binding9962");
    const v9997 = try s.text("items");
    const v9998 = try s.own(try js.getKey(e, v9996, v9997));
    const v9999 = try o.lookup(&s, frame, "binding9989");
    const v10000 = try s.call(v9993, c.pi_js_undefined(), &.{ v9994, v9995, v9998, v9999 });
    const v10002 = logical10001: {
        if (!s.truthy(v10000)) break :logical10001 v10000;
        const v10003 = try o.lookup(&s, frame, "binding9961");
        const v10004 = try s.text("AddIndex");
        const v10005 = try s.own(try js.getKey(e, v10003, v10004));
        const v10006 = try o.lookup(&s, frame, "binding9990");
        const v10007 = try s.call(v10005, v10003, &.{v10006});
        break :logical10001 v10007;
    };
    return c.JS_DupValue(e.context, v10002);
}
fn body9987C(ctx: ?*c.JSContext, receiver: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const e = Engine.fromContext(ctx.?);
    return body9987(e, receiver, if (argc > 0) argv[0..@intCast(argc)] else &.{}, roots[0..2]) catch |err| sdk.fail(e, err);
}
fn body9959(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v9965 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding9960", v9965);
    const v9966 = if (args.len > 1) args[1] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding9961", v9966);
    const v9967 = if (args.len > 2) args[2] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding9962", v9967);
    const v9968 = if (args.len > 3) args[3] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding9963", v9968);
    const v9970 = try o.importValue(&s, graph, "schema/types/index.mjs", "*");
    const v9971 = try s.text("IsPrefixItems");
    const v9972 = try s.own(try js.getKey(e, v9970, v9971));
    const v9973 = try o.lookup(&s, frame, "binding9962");
    const v9974 = try s.call(v9972, v9970, &.{v9973});
    const v9976 = conditional9975: {
        if (s.truthy(v9974)) {
            const v9977 = try o.lookup(&s, frame, "binding9962");
            const v9978 = try s.text("prefixItems");
            const v9979 = try s.own(try js.getKey(e, v9977, v9978));
            const v9980 = try s.text("length");
            const v9981 = try s.own(try js.getKey(e, v9979, v9980));
            break :conditional9975 v9981;
        } else {
            break :conditional9975 c.JS_NewFloat64(e.context, 0);
        }
    };
    try o.assign(&s, frame, "binding9969", v9976);
    const v9982 = try o.importValue(&s, graph, "guard/index.mjs", "Guard");
    const v9983 = try s.text("Every");
    const v9984 = try s.own(try js.getKey(e, v9982, v9983));
    const v9985 = try o.lookup(&s, frame, "binding9963");
    const v9986 = try o.lookup(&s, frame, "binding9969");
    const v10008 = try o.arrow(&s, "", 2, body9987C, &.{ graph, frame });
    const v10009 = try s.call(v9984, v9982, &.{ v9985, v9986, v10008 });
    return c.JS_DupValue(e.context, v10009);
}
fn body10043(e: *Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    _ = try o.lookup(&s, frame, "@this");
    const v10049 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding10045", v10049);
    const v10050 = if (args.len > 1) args[1] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding10046", v10050);
    const v10053 = try s.text("");
    const v10054 = try o.lookup(&s, frame, "binding10014");
    const v10055 = try s.stringify(v10054);
    const v10056 = try s.concat(v10053, v10055);
    const v10057 = try s.text("/items");
    const v10058 = try s.concat(v10056, v10057);
    try o.assign(&s, frame, "binding10051", v10058);
    const v10059 = try s.text("");
    const v10060 = try o.lookup(&s, frame, "binding10015");
    const v10061 = try s.stringify(v10060);
    const v10062 = try s.concat(v10059, v10061);
    const v10063 = try s.text("/");
    const v10064 = try s.concat(v10062, v10063);
    const v10065 = try o.lookup(&s, frame, "binding10046");
    const v10066 = try s.stringify(v10065);
    const v10067 = try s.concat(v10064, v10066);
    const v10068 = try s.text("");
    const v10069 = try s.concat(v10067, v10068);
    try o.assign(&s, frame, "binding10052", v10069);
    const v10070 = try o.importValue(&s, graph, "schema/engine/schema.mjs", "ErrorSchemaPushStack");
    const v10071 = try o.lookup(&s, frame, "binding10012");
    const v10072 = try o.lookup(&s, frame, "binding10013");
    const v10073 = try o.lookup(&s, frame, "binding10051");
    const v10074 = try o.lookup(&s, frame, "binding10052");
    const v10075 = try o.lookup(&s, frame, "binding10016");
    const v10076 = try s.text("items");
    const v10077 = try s.own(try js.getKey(e, v10075, v10076));
    const v10078 = try o.lookup(&s, frame, "binding10045");
    const v10079 = try s.call(v10070, c.pi_js_undefined(), &.{ v10071, v10072, v10073, v10074, v10077, v10078 });
    const v10081 = logical10080: {
        if (!s.truthy(v10079)) break :logical10080 v10079;
        const v10082 = try o.lookup(&s, frame, "binding10013");
        const v10083 = try s.text("AddIndex");
        const v10084 = try s.own(try js.getKey(e, v10082, v10083));
        const v10085 = try o.lookup(&s, frame, "binding10046");
        const v10086 = try s.call(v10084, v10082, &.{v10085});
        break :logical10080 v10086;
    };
    return c.JS_DupValue(e.context, v10081);
}
fn body10043C(ctx: ?*c.JSContext, receiver: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const e = Engine.fromContext(ctx.?);
    return body10043(e, receiver, if (argc > 0) argv[0..@intCast(argc)] else &.{}, roots[0..2]) catch |err| sdk.fail(e, err);
}
fn body10011(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v10019 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding10012", v10019);
    const v10020 = if (args.len > 1) args[1] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding10013", v10020);
    const v10021 = if (args.len > 2) args[2] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding10014", v10021);
    const v10022 = if (args.len > 3) args[3] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding10015", v10022);
    const v10023 = if (args.len > 4) args[4] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding10016", v10023);
    const v10024 = if (args.len > 5) args[5] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding10017", v10024);
    const v10026 = try o.importValue(&s, graph, "schema/types/index.mjs", "*");
    const v10027 = try s.text("IsPrefixItems");
    const v10028 = try s.own(try js.getKey(e, v10026, v10027));
    const v10029 = try o.lookup(&s, frame, "binding10016");
    const v10030 = try s.call(v10028, v10026, &.{v10029});
    const v10032 = conditional10031: {
        if (s.truthy(v10030)) {
            const v10033 = try o.lookup(&s, frame, "binding10016");
            const v10034 = try s.text("prefixItems");
            const v10035 = try s.own(try js.getKey(e, v10033, v10034));
            const v10036 = try s.text("length");
            const v10037 = try s.own(try js.getKey(e, v10035, v10036));
            break :conditional10031 v10037;
        } else {
            break :conditional10031 c.JS_NewFloat64(e.context, 0);
        }
    };
    try o.assign(&s, frame, "binding10025", v10032);
    const v10038 = try o.importValue(&s, graph, "guard/index.mjs", "Guard");
    const v10039 = try s.text("EveryAll");
    const v10040 = try s.own(try js.getKey(e, v10038, v10039));
    const v10041 = try o.lookup(&s, frame, "binding10017");
    const v10042 = try o.lookup(&s, frame, "binding10025");
    const v10087 = try o.arrow(&s, "", 2, body10043C, &.{ graph, frame });
    const v10088 = try s.call(v10040, v10038, &.{ v10041, v10042, v10087 });
    return c.JS_DupValue(e.context, v10088);
}
fn body10090(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v10095 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding10091", v10095);
    const v10096 = if (args.len > 1) args[1] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding10092", v10096);
    const v10097 = if (args.len > 2) args[2] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding10093", v10097);
    const v10098 = if (args.len > 3) args[3] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding10094", v10098);
    const v10099 = try o.importValue(&s, graph, "schema/types/index.mjs", "*");
    const v10100 = try s.text("IsItemsSized");
    const v10101 = try s.own(try js.getKey(e, v10099, v10100));
    const v10102 = try o.lookup(&s, frame, "binding10093");
    const v10103 = try s.call(v10101, v10099, &.{v10102});
    const v10105 = conditional10104: {
        if (s.truthy(v10103)) {
            const v10106 = try o.lookup(&s, frame, "binding9500");
            const v10107 = try o.lookup(&s, frame, "binding10091");
            const v10108 = try o.lookup(&s, frame, "binding10092");
            const v10109 = try o.lookup(&s, frame, "binding10093");
            const v10110 = try o.lookup(&s, frame, "binding10094");
            const v10111 = try s.call(v10106, c.pi_js_undefined(), &.{ v10107, v10108, v10109, v10110 });
            break :conditional10104 v10111;
        } else {
            const v10112 = try o.lookup(&s, frame, "binding9505");
            const v10113 = try o.lookup(&s, frame, "binding10091");
            const v10114 = try o.lookup(&s, frame, "binding10092");
            const v10115 = try o.lookup(&s, frame, "binding10093");
            const v10116 = try o.lookup(&s, frame, "binding10094");
            const v10117 = try s.call(v10112, c.pi_js_undefined(), &.{ v10113, v10114, v10115, v10116 });
            break :conditional10104 v10117;
        }
    };
    return c.JS_DupValue(e.context, v10105);
}
fn body10119(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v10124 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding10120", v10124);
    const v10125 = if (args.len > 1) args[1] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding10121", v10125);
    const v10126 = if (args.len > 2) args[2] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding10122", v10126);
    const v10127 = if (args.len > 3) args[3] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding10123", v10127);
    const v10128 = try o.importValue(&s, graph, "schema/types/index.mjs", "*");
    const v10129 = try s.text("IsItemsSized");
    const v10130 = try s.own(try js.getKey(e, v10128, v10129));
    const v10131 = try o.lookup(&s, frame, "binding10122");
    const v10132 = try s.call(v10130, v10128, &.{v10131});
    const v10134 = conditional10133: {
        if (s.truthy(v10132)) {
            const v10135 = try o.lookup(&s, frame, "binding9501");
            const v10136 = try o.lookup(&s, frame, "binding10120");
            const v10137 = try o.lookup(&s, frame, "binding10121");
            const v10138 = try o.lookup(&s, frame, "binding10122");
            const v10139 = try o.lookup(&s, frame, "binding10123");
            const v10140 = try s.call(v10135, c.pi_js_undefined(), &.{ v10136, v10137, v10138, v10139 });
            break :conditional10133 v10140;
        } else {
            const v10141 = try o.lookup(&s, frame, "binding9506");
            const v10142 = try o.lookup(&s, frame, "binding10120");
            const v10143 = try o.lookup(&s, frame, "binding10121");
            const v10144 = try o.lookup(&s, frame, "binding10122");
            const v10145 = try o.lookup(&s, frame, "binding10123");
            const v10146 = try s.call(v10141, c.pi_js_undefined(), &.{ v10142, v10143, v10144, v10145 });
            break :conditional10133 v10146;
        }
    };
    return c.JS_DupValue(e.context, v10134);
}
fn body10148(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v10155 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding10149", v10155);
    const v10156 = if (args.len > 1) args[1] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding10150", v10156);
    const v10157 = if (args.len > 2) args[2] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding10151", v10157);
    const v10158 = if (args.len > 3) args[3] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding10152", v10158);
    const v10159 = if (args.len > 4) args[4] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding10153", v10159);
    const v10160 = if (args.len > 5) args[5] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding10154", v10160);
    const v10161 = try o.importValue(&s, graph, "schema/types/index.mjs", "*");
    const v10162 = try s.text("IsItemsSized");
    const v10163 = try s.own(try js.getKey(e, v10161, v10162));
    const v10164 = try o.lookup(&s, frame, "binding10153");
    const v10165 = try s.call(v10163, v10161, &.{v10164});
    const v10167 = conditional10166: {
        if (s.truthy(v10165)) {
            const v10168 = try o.lookup(&s, frame, "binding9502");
            const v10169 = try o.lookup(&s, frame, "binding10149");
            const v10170 = try o.lookup(&s, frame, "binding10150");
            const v10171 = try o.lookup(&s, frame, "binding10151");
            const v10172 = try o.lookup(&s, frame, "binding10152");
            const v10173 = try o.lookup(&s, frame, "binding10153");
            const v10174 = try o.lookup(&s, frame, "binding10154");
            const v10175 = try s.call(v10168, c.pi_js_undefined(), &.{ v10169, v10170, v10171, v10172, v10173, v10174 });
            break :conditional10166 v10175;
        } else {
            const v10176 = try o.lookup(&s, frame, "binding9507");
            const v10177 = try o.lookup(&s, frame, "binding10149");
            const v10178 = try o.lookup(&s, frame, "binding10150");
            const v10179 = try o.lookup(&s, frame, "binding10151");
            const v10180 = try o.lookup(&s, frame, "binding10152");
            const v10181 = try o.lookup(&s, frame, "binding10153");
            const v10182 = try o.lookup(&s, frame, "binding10154");
            const v10183 = try s.call(v10176, c.pi_js_undefined(), &.{ v10177, v10178, v10179, v10180, v10181, v10182 });
            break :conditional10166 v10183;
        }
    };
    return c.JS_DupValue(e.context, v10167);
}
