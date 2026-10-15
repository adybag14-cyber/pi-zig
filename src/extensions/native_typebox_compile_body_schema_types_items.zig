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
    const namespace = try s.get(modules, "schema/types/items.mjs");
    const frame = try o.frame(&s, c.pi_js_null());
    try s.put(frame, "@this", c.pi_js_undefined());
    try s.put(try s.get(graph, "frames"), "schema/types/items.mjs", frame);
    const bindings = try s.object();
    try s.put(try s.get(graph, "bindings"), "schema/types/items.mjs", bindings);
    const v21695 = try s.own(try ordinary.create(e, "IsItems", 1, body21654, &.{ graph, frame }));
    try o.assign(&s, frame, "binding21651", v21695);
    const v21711 = try s.own(try ordinary.create(e, "IsItemsSized", 1, body21696, &.{ graph, frame }));
    try o.assign(&s, frame, "binding21652", v21711);
    const v21727 = try s.own(try ordinary.create(e, "IsItemsUnsized", 1, body21712, &.{ graph, frame }));
    try o.assign(&s, frame, "binding21653", v21727);
    const v21728 = try o.lookup(&s, frame, "binding21651");
    try s.put(namespace, "IsItems", v21728);
    const v21729 = try o.lookup(&s, frame, "binding21652");
    try s.put(namespace, "IsItemsSized", v21729);
    const v21730 = try o.lookup(&s, frame, "binding21653");
    try s.put(namespace, "IsItemsUnsized", v21730);
    const v21731 = try o.lookup(&s, frame, "binding21651");
    try s.put(namespace, "IsItems", v21731);
    const v21732 = try o.lookup(&s, frame, "binding21652");
    try s.put(namespace, "IsItemsSized", v21732);
    const v21733 = try o.lookup(&s, frame, "binding21653");
    try s.put(namespace, "IsItemsUnsized", v21733);
    try s.put(bindings, "IsItems", try s.text("binding21651"));
    try s.put(bindings, "IsItemsSized", try s.text("binding21652"));
    try s.put(bindings, "IsItemsUnsized", try s.text("binding21653"));
}
fn body21686(e: *Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    _ = try o.lookup(&s, frame, "@this");
    const v21689 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding21688", v21689);
    const v21690 = try o.importValue(&s, graph, "schema/types/schema.mjs", "IsSchema");
    const v21691 = try o.lookup(&s, frame, "binding21688");
    const v21692 = try s.call(v21690, c.pi_js_undefined(), &.{v21691});
    return c.JS_DupValue(e.context, v21692);
}
fn body21686C(ctx: ?*c.JSContext, receiver: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const e = Engine.fromContext(ctx.?);
    return body21686(e, receiver, if (argc > 0) argv[0..@intCast(argc)] else &.{}, roots[0..2]) catch |err| sdk.fail(e, err);
}
fn body21654(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v21656 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding21655", v21656);
    const v21657 = try o.importValue(&s, graph, "guard/index.mjs", "Guard");
    const v21658 = try s.text("HasPropertyKey");
    const v21659 = try s.own(try js.getKey(e, v21657, v21658));
    const v21660 = try o.lookup(&s, frame, "binding21655");
    const v21661 = try s.text("items");
    const v21662 = try s.call(v21659, v21657, &.{ v21660, v21661 });
    const v21664 = logical21663: {
        if (!s.truthy(v21662)) break :logical21663 v21662;
        const v21665 = try o.importValue(&s, graph, "schema/types/schema.mjs", "IsSchema");
        const v21666 = try o.lookup(&s, frame, "binding21655");
        const v21667 = try s.text("items");
        const v21668 = try s.own(try js.getKey(e, v21666, v21667));
        const v21669 = try s.call(v21665, c.pi_js_undefined(), &.{v21668});
        const v21671 = logical21670: {
            if (s.truthy(v21669)) break :logical21670 v21669;
            const v21672 = try o.importValue(&s, graph, "guard/index.mjs", "Guard");
            const v21673 = try s.text("IsArray");
            const v21674 = try s.own(try js.getKey(e, v21672, v21673));
            const v21675 = try o.lookup(&s, frame, "binding21655");
            const v21676 = try s.text("items");
            const v21677 = try s.own(try js.getKey(e, v21675, v21676));
            const v21678 = try s.call(v21674, v21672, &.{v21677});
            const v21680 = logical21679: {
                if (!s.truthy(v21678)) break :logical21679 v21678;
                const v21681 = try o.lookup(&s, frame, "binding21655");
                const v21682 = try s.text("items");
                const v21683 = try s.own(try js.getKey(e, v21681, v21682));
                const v21684 = try s.text("every");
                const v21685 = try s.own(try js.getKey(e, v21683, v21684));
                const v21693 = try o.arrow(&s, "", 1, body21686C, &.{ graph, frame });
                const v21694 = try s.call(v21685, v21683, &.{v21693});
                break :logical21679 v21694;
            };
            break :logical21670 v21680;
        };
        break :logical21663 v21671;
    };
    return c.JS_DupValue(e.context, v21664);
}
fn body21696(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v21698 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding21697", v21698);
    const v21699 = try o.lookup(&s, frame, "binding21651");
    const v21700 = try o.lookup(&s, frame, "binding21697");
    const v21701 = try s.call(v21699, c.pi_js_undefined(), &.{v21700});
    const v21703 = logical21702: {
        if (!s.truthy(v21701)) break :logical21702 v21701;
        const v21704 = try o.importValue(&s, graph, "guard/index.mjs", "Guard");
        const v21705 = try s.text("IsArray");
        const v21706 = try s.own(try js.getKey(e, v21704, v21705));
        const v21707 = try o.lookup(&s, frame, "binding21697");
        const v21708 = try s.text("items");
        const v21709 = try s.own(try js.getKey(e, v21707, v21708));
        const v21710 = try s.call(v21706, v21704, &.{v21709});
        break :logical21702 v21710;
    };
    return c.JS_DupValue(e.context, v21703);
}
fn body21712(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v21714 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding21713", v21714);
    const v21715 = try o.lookup(&s, frame, "binding21651");
    const v21716 = try o.lookup(&s, frame, "binding21713");
    const v21717 = try s.call(v21715, c.pi_js_undefined(), &.{v21716});
    const v21719 = logical21718: {
        if (!s.truthy(v21717)) break :logical21718 v21717;
        const v21720 = try o.importValue(&s, graph, "guard/index.mjs", "Guard");
        const v21721 = try s.text("IsArray");
        const v21722 = try s.own(try js.getKey(e, v21720, v21721));
        const v21723 = try o.lookup(&s, frame, "binding21713");
        const v21724 = try s.text("items");
        const v21725 = try s.own(try js.getKey(e, v21723, v21724));
        const v21726 = try s.call(v21722, v21720, &.{v21725});
        break :logical21718 o.boolean(&s, !s.truthy(v21726));
    };
    return c.JS_DupValue(e.context, v21719);
}
