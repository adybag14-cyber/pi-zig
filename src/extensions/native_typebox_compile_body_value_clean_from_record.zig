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
    const namespace = try s.get(modules, "value/clean/from_record.mjs");
    const frame = try o.frame(&s, c.pi_js_null());
    try s.put(frame, "@this", c.pi_js_undefined());
    try s.put(try s.get(graph, "frames"), "value/clean/from_record.mjs", frame);
    const bindings = try s.object();
    try s.put(try s.get(graph, "bindings"), "value/clean/from_record.mjs", bindings);
    const v23708 = try s.own(try ordinary.create(e, "FromRecord", 3, body23603, &.{ graph, frame }));
    try o.assign(&s, frame, "binding23602", v23708);
    const v23709 = try o.lookup(&s, frame, "binding23602");
    try s.put(namespace, "FromRecord", v23709);
    const v23710 = try o.lookup(&s, frame, "binding23602");
    try s.put(namespace, "FromRecord", v23710);
    try s.put(bindings, "FromRecord", try s.text("binding23602"));
}
fn body23603(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v23610 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding23604", v23610);
    const v23611 = if (args.len > 1) args[1] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding23605", v23611);
    const v23612 = if (args.len > 2) args[2] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding23606", v23612);
    const v23616 = try o.importValue(&s, graph, "guard/index.mjs", "Guard");
    const v23617 = try s.text("IsObject");
    const v23618 = try s.own(try js.getKey(e, v23616, v23617));
    const v23619 = try o.lookup(&s, frame, "binding23606");
    const v23620 = try s.call(v23618, v23616, &.{v23619});
    if (s.truthy(o.boolean(&s, !s.truthy(v23620)))) {
        const v23621 = try o.lookup(&s, frame, "binding23606");
        return c.JS_DupValue(e.context, v23621);
    }
    const v23622 = try o.importValue(&s, graph, "value/clean/additional.mjs", "GetAdditionalProperties");
    const v23623 = try o.lookup(&s, frame, "binding23605");
    const v23624 = try s.call(v23622, c.pi_js_undefined(), &.{v23623});
    try o.assign(&s, frame, "binding23613", v23624);
    const v23625 = try s.array();
    const v23626 = try s.global("RegExp");
    const v23627 = try o.importValue(&s, graph, "type/index.mjs", "RecordPattern");
    const v23628 = try o.lookup(&s, frame, "binding23605");
    const v23629 = try s.call(v23627, c.pi_js_undefined(), &.{v23628});
    const v23630 = try o.construct(&s, v23626, &.{v23629});
    try o.append(&s, v23625, v23630);
    const v23631 = try o.importValue(&s, graph, "type/index.mjs", "RecordValue");
    const v23632 = try o.lookup(&s, frame, "binding23605");
    const v23633 = try s.call(v23631, c.pi_js_undefined(), &.{v23632});
    try o.append(&s, v23625, v23633);
    var destructure23634 = try o.iterator(e, v23625);
    defer destructure23634.deinit();
    errdefer destructure23634.closePreserving();
    const v23635 = try s.own(if (destructure23634.closed) c.pi_js_undefined() else (try destructure23634.next()) orelse c.pi_js_undefined());
    try o.assign(&s, frame, "binding23614", v23635);
    const v23636 = try s.own(if (destructure23634.closed) c.pi_js_undefined() else (try destructure23634.next()) orelse c.pi_js_undefined());
    try o.assign(&s, frame, "binding23615", v23636);
    try destructure23634.close();
    const v23637 = try o.importValue(&s, graph, "guard/index.mjs", "Guard");
    const v23638 = try s.text("Keys");
    const v23639 = try s.own(try js.getKey(e, v23637, v23638));
    const v23640 = try o.lookup(&s, frame, "binding23606");
    const v23641 = try s.call(v23639, v23637, &.{v23640});
    var iterator23642 = try o.iterator(e, v23641);
    defer iterator23642.deinit();
    errdefer iterator23642.closePreserving();
    loop23644: while (try iterator23642.next()) |next23643| {
        defer e.freeValue(next23643);
        const iteration23645 = try o.frame(&s, frame);
        try o.assign(&s, iteration23645, "binding23646", next23643);
        const v23648 = try o.lookup(&s, iteration23645, "binding23614");
        const v23649 = try s.text("test");
        const v23650 = try s.own(try js.getKey(e, v23648, v23649));
        const v23651 = try o.lookup(&s, iteration23645, "binding23646");
        const v23652 = try s.call(v23650, v23648, &.{v23651});
        if (s.truthy(v23652)) {
            const v23653 = try o.lookup(&s, iteration23645, "binding23606");
            const v23654 = try o.lookup(&s, iteration23645, "binding23646");
            const v23655 = try o.propertyKey(&s, v23654);
            const v23656 = try o.importValue(&s, graph, "value/clean/from_type.mjs", "FromType");
            const v23657 = try o.lookup(&s, iteration23645, "binding23604");
            const v23658 = try o.lookup(&s, iteration23645, "binding23615");
            const v23659 = try o.lookup(&s, iteration23645, "binding23606");
            const v23660 = try o.lookup(&s, iteration23645, "binding23646");
            const v23661 = try o.propertyKey(&s, v23660);
            const v23662 = try s.own(try js.getKey(e, v23659, v23661));
            const v23663 = try s.call(v23656, c.pi_js_undefined(), &.{ v23657, v23658, v23662 });
            try js.setKey(e, v23653, v23655, v23663);
            continue :loop23644;
        }
        const v23664 = try o.importValue(&s, graph, "guard/index.mjs", "Guard");
        const v23665 = try s.text("IsBoolean");
        const v23666 = try s.own(try js.getKey(e, v23664, v23665));
        const v23667 = try o.lookup(&s, iteration23645, "binding23613");
        const v23668 = try s.call(v23666, v23664, &.{v23667});
        const v23670 = logical23669: {
            if (!s.truthy(v23668)) break :logical23669 v23668;
            const v23671 = try o.importValue(&s, graph, "guard/index.mjs", "Guard");
            const v23672 = try s.text("IsEqual");
            const v23673 = try s.own(try js.getKey(e, v23671, v23672));
            const v23674 = try o.lookup(&s, iteration23645, "binding23613");
            const v23675 = try s.call(v23673, v23671, &.{ v23674, o.boolean(&s, true) });
            break :logical23669 v23675;
        };
        const v23677 = logical23676: {
            if (s.truthy(v23670)) break :logical23676 v23670;
            const v23678 = try o.importValue(&s, graph, "type/index.mjs", "IsSchema");
            const v23679 = try o.lookup(&s, iteration23645, "binding23613");
            const v23680 = try s.call(v23678, c.pi_js_undefined(), &.{v23679});
            const v23682 = logical23681: {
                if (!s.truthy(v23680)) break :logical23681 v23680;
                const v23683 = try o.importValue(&s, graph, "value/check/index.mjs", "Check");
                const v23684 = try o.lookup(&s, iteration23645, "binding23604");
                const v23685 = try o.lookup(&s, iteration23645, "binding23613");
                const v23686 = try o.lookup(&s, iteration23645, "binding23606");
                const v23687 = try o.lookup(&s, iteration23645, "binding23646");
                const v23688 = try o.propertyKey(&s, v23687);
                const v23689 = try s.own(try js.getKey(e, v23686, v23688));
                const v23690 = try s.call(v23683, c.pi_js_undefined(), &.{ v23684, v23685, v23689 });
                break :logical23681 v23690;
            };
            break :logical23676 v23682;
        };
        try o.assign(&s, iteration23645, "binding23647", v23677);
        const v23691 = try o.lookup(&s, iteration23645, "binding23647");
        if (s.truthy(v23691)) {
            const v23692 = try o.lookup(&s, iteration23645, "binding23606");
            const v23693 = try o.lookup(&s, iteration23645, "binding23646");
            const v23694 = try o.propertyKey(&s, v23693);
            const v23695 = try o.importValue(&s, graph, "value/clean/from_type.mjs", "FromType");
            const v23696 = try o.lookup(&s, iteration23645, "binding23604");
            const v23697 = try o.lookup(&s, iteration23645, "binding23613");
            const v23698 = try o.lookup(&s, iteration23645, "binding23606");
            const v23699 = try o.lookup(&s, iteration23645, "binding23646");
            const v23700 = try o.propertyKey(&s, v23699);
            const v23701 = try s.own(try js.getKey(e, v23698, v23700));
            const v23702 = try s.call(v23695, c.pi_js_undefined(), &.{ v23696, v23697, v23701 });
            try js.setKey(e, v23692, v23694, v23702);
            continue :loop23644;
        }
        const v23703 = try o.lookup(&s, iteration23645, "binding23606");
        const v23704 = try o.lookup(&s, iteration23645, "binding23646");
        const v23705 = try o.propertyKey(&s, v23704);
        const v23706 = try o.deleteKey(&s, v23703, v23705);
        _ = v23706;
    }
    try iterator23642.close();
    const v23707 = try o.lookup(&s, frame, "binding23606");
    return c.JS_DupValue(e.context, v23707);
}
