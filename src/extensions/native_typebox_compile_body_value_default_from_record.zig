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
    const namespace = try s.get(modules, "value/default/from_record.mjs");
    const frame = try o.frame(&s, c.pi_js_null());
    try s.put(frame, "@this", c.pi_js_undefined());
    try s.put(try s.get(graph, "frames"), "value/default/from_record.mjs", frame);
    const bindings = try s.object();
    try s.put(try s.get(graph, "bindings"), "value/default/from_record.mjs", bindings);
    const v29689 = try s.own(try ordinary.create(e, "FromRecord", 3, body29596, &.{ graph, frame }));
    try o.assign(&s, frame, "binding29595", v29689);
    const v29690 = try o.lookup(&s, frame, "binding29595");
    try s.put(namespace, "FromRecord", v29690);
    const v29691 = try o.lookup(&s, frame, "binding29595");
    try s.put(namespace, "FromRecord", v29691);
    try s.put(bindings, "FromRecord", try s.text("binding29595"));
}
fn body29596(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v29602 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding29597", v29602);
    const v29603 = if (args.len > 1) args[1] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding29598", v29603);
    const v29604 = if (args.len > 2) args[2] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding29599", v29604);
    const v29607 = try o.importValue(&s, graph, "guard/index.mjs", "Guard");
    const v29608 = try s.text("IsObject");
    const v29609 = try s.own(try js.getKey(e, v29607, v29608));
    const v29610 = try o.lookup(&s, frame, "binding29599");
    const v29611 = try s.call(v29609, v29607, &.{v29610});
    if (s.truthy(o.boolean(&s, !s.truthy(v29611)))) {
        const v29612 = try o.lookup(&s, frame, "binding29599");
        return c.JS_DupValue(e.context, v29612);
    }
    const v29613 = try s.array();
    const v29614 = try s.global("RegExp");
    const v29615 = try o.importValue(&s, graph, "type/index.mjs", "RecordPattern");
    const v29616 = try o.lookup(&s, frame, "binding29598");
    const v29617 = try s.call(v29615, c.pi_js_undefined(), &.{v29616});
    const v29618 = try o.construct(&s, v29614, &.{v29617});
    try o.append(&s, v29613, v29618);
    const v29619 = try o.importValue(&s, graph, "type/index.mjs", "RecordValue");
    const v29620 = try o.lookup(&s, frame, "binding29598");
    const v29621 = try s.call(v29619, c.pi_js_undefined(), &.{v29620});
    try o.append(&s, v29613, v29621);
    var destructure29622 = try o.iterator(e, v29613);
    defer destructure29622.deinit();
    errdefer destructure29622.closePreserving();
    const v29623 = try s.own(if (destructure29622.closed) c.pi_js_undefined() else (try destructure29622.next()) orelse c.pi_js_undefined());
    try o.assign(&s, frame, "binding29605", v29623);
    const v29624 = try s.own(if (destructure29622.closed) c.pi_js_undefined() else (try destructure29622.next()) orelse c.pi_js_undefined());
    try o.assign(&s, frame, "binding29606", v29624);
    try destructure29622.close();
    const v29625 = try o.importValue(&s, graph, "guard/index.mjs", "Guard");
    const v29626 = try s.text("Keys");
    const v29627 = try s.own(try js.getKey(e, v29625, v29626));
    const v29628 = try o.lookup(&s, frame, "binding29599");
    const v29629 = try s.call(v29627, v29625, &.{v29628});
    var iterator29630 = try o.iterator(e, v29629);
    defer iterator29630.deinit();
    errdefer iterator29630.closePreserving();
    loop29632: while (try iterator29630.next()) |next29631| {
        defer e.freeValue(next29631);
        const iteration29633 = try o.frame(&s, frame);
        try o.assign(&s, iteration29633, "binding29634", next29631);
        const v29635 = try o.lookup(&s, iteration29633, "binding29605");
        const v29636 = try s.text("test");
        const v29637 = try s.own(try js.getKey(e, v29635, v29636));
        const v29638 = try o.lookup(&s, iteration29633, "binding29634");
        const v29639 = try s.call(v29637, v29635, &.{v29638});
        const v29641 = logical29640: {
            if (!s.truthy(v29639)) break :logical29640 v29639;
            const v29642 = try o.importValue(&s, graph, "schema/types/index.mjs", "IsDefault");
            const v29643 = try o.lookup(&s, iteration29633, "binding29606");
            const v29644 = try s.call(v29642, c.pi_js_undefined(), &.{v29643});
            break :logical29640 v29644;
        };
        if (s.truthy(o.boolean(&s, !s.truthy(v29641)))) {
            continue :loop29632;
        }
        const v29645 = try o.lookup(&s, iteration29633, "binding29599");
        const v29646 = try o.lookup(&s, iteration29633, "binding29634");
        const v29647 = try o.propertyKey(&s, v29646);
        const v29648 = try o.importValue(&s, graph, "value/default/from_type.mjs", "FromType");
        const v29649 = try o.lookup(&s, iteration29633, "binding29597");
        const v29650 = try o.lookup(&s, iteration29633, "binding29606");
        const v29651 = try o.lookup(&s, iteration29633, "binding29599");
        const v29652 = try o.lookup(&s, iteration29633, "binding29634");
        const v29653 = try o.propertyKey(&s, v29652);
        const v29654 = try s.own(try js.getKey(e, v29651, v29653));
        const v29655 = try s.call(v29648, c.pi_js_undefined(), &.{ v29649, v29650, v29654 });
        try js.setKey(e, v29645, v29647, v29655);
    }
    try iterator29630.close();
    const v29656 = try o.importValue(&s, graph, "schema/types/index.mjs", "IsAdditionalProperties");
    const v29657 = try o.lookup(&s, frame, "binding29598");
    const v29658 = try s.call(v29656, c.pi_js_undefined(), &.{v29657});
    if (s.truthy(o.boolean(&s, !s.truthy(v29658)))) {
        const v29659 = try o.lookup(&s, frame, "binding29599");
        return c.JS_DupValue(e.context, v29659);
    }
    const v29660 = try o.importValue(&s, graph, "guard/index.mjs", "Guard");
    const v29661 = try s.text("Keys");
    const v29662 = try s.own(try js.getKey(e, v29660, v29661));
    const v29663 = try o.lookup(&s, frame, "binding29599");
    const v29664 = try s.call(v29662, v29660, &.{v29663});
    var iterator29665 = try o.iterator(e, v29664);
    defer iterator29665.deinit();
    errdefer iterator29665.closePreserving();
    loop29667: while (try iterator29665.next()) |next29666| {
        defer e.freeValue(next29666);
        const iteration29668 = try o.frame(&s, frame);
        try o.assign(&s, iteration29668, "binding29669", next29666);
        const v29670 = try o.lookup(&s, iteration29668, "binding29605");
        const v29671 = try s.text("test");
        const v29672 = try s.own(try js.getKey(e, v29670, v29671));
        const v29673 = try o.lookup(&s, iteration29668, "binding29669");
        const v29674 = try s.call(v29672, v29670, &.{v29673});
        if (s.truthy(v29674)) {
            continue :loop29667;
        }
        const v29675 = try o.lookup(&s, iteration29668, "binding29599");
        const v29676 = try o.lookup(&s, iteration29668, "binding29669");
        const v29677 = try o.propertyKey(&s, v29676);
        const v29678 = try o.importValue(&s, graph, "value/default/from_type.mjs", "FromType");
        const v29679 = try o.lookup(&s, iteration29668, "binding29597");
        const v29680 = try o.lookup(&s, iteration29668, "binding29598");
        const v29681 = try s.text("additionalProperties");
        const v29682 = try s.own(try js.getKey(e, v29680, v29681));
        const v29683 = try o.lookup(&s, iteration29668, "binding29599");
        const v29684 = try o.lookup(&s, iteration29668, "binding29669");
        const v29685 = try o.propertyKey(&s, v29684);
        const v29686 = try s.own(try js.getKey(e, v29683, v29685));
        const v29687 = try s.call(v29678, c.pi_js_undefined(), &.{ v29679, v29682, v29686 });
        try js.setKey(e, v29675, v29677, v29687);
    }
    try iterator29665.close();
    const v29688 = try o.lookup(&s, frame, "binding29599");
    return c.JS_DupValue(e.context, v29688);
}
