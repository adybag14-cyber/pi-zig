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
    const namespace = try s.get(modules, "value/clean/from_object.mjs");
    const frame = try o.frame(&s, c.pi_js_null());
    try s.put(frame, "@this", c.pi_js_undefined());
    try s.put(try s.get(graph, "frames"), "value/clean/from_object.mjs", frame);
    const bindings = try s.object();
    try s.put(try s.get(graph, "bindings"), "value/clean/from_object.mjs", bindings);
    const v23599 = try s.own(try ordinary.create(e, "FromObject", 3, body23495, &.{ graph, frame }));
    try o.assign(&s, frame, "binding23494", v23599);
    const v23600 = try o.lookup(&s, frame, "binding23494");
    try s.put(namespace, "FromObject", v23600);
    const v23601 = try o.lookup(&s, frame, "binding23494");
    try s.put(namespace, "FromObject", v23601);
    try s.put(bindings, "FromObject", try s.text("binding23494"));
}
fn body23495(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v23500 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding23496", v23500);
    const v23501 = if (args.len > 1) args[1] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding23497", v23501);
    const v23502 = if (args.len > 2) args[2] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding23498", v23502);
    const v23504 = try o.importValue(&s, graph, "guard/index.mjs", "Guard");
    const v23505 = try s.text("IsObject");
    const v23506 = try s.own(try js.getKey(e, v23504, v23505));
    const v23507 = try o.lookup(&s, frame, "binding23498");
    const v23508 = try s.call(v23506, v23504, &.{v23507});
    const v23510 = logical23509: {
        if (s.truthy(o.boolean(&s, !s.truthy(v23508)))) break :logical23509 o.boolean(&s, !s.truthy(v23508));
        const v23511 = try o.importValue(&s, graph, "guard/index.mjs", "Guard");
        const v23512 = try s.text("IsArray");
        const v23513 = try s.own(try js.getKey(e, v23511, v23512));
        const v23514 = try o.lookup(&s, frame, "binding23498");
        const v23515 = try s.call(v23513, v23511, &.{v23514});
        break :logical23509 v23515;
    };
    if (s.truthy(v23510)) {
        const v23516 = try o.lookup(&s, frame, "binding23498");
        return c.JS_DupValue(e.context, v23516);
    }
    const v23517 = try o.importValue(&s, graph, "value/clean/additional.mjs", "GetAdditionalProperties");
    const v23518 = try o.lookup(&s, frame, "binding23497");
    const v23519 = try s.call(v23517, c.pi_js_undefined(), &.{v23518});
    try o.assign(&s, frame, "binding23503", v23519);
    const v23520 = try o.importValue(&s, graph, "guard/index.mjs", "Guard");
    const v23521 = try s.text("Keys");
    const v23522 = try s.own(try js.getKey(e, v23520, v23521));
    const v23523 = try o.lookup(&s, frame, "binding23498");
    const v23524 = try s.call(v23522, v23520, &.{v23523});
    var iterator23525 = try o.iterator(e, v23524);
    defer iterator23525.deinit();
    errdefer iterator23525.closePreserving();
    loop23527: while (try iterator23525.next()) |next23526| {
        defer e.freeValue(next23526);
        const iteration23528 = try o.frame(&s, frame);
        try o.assign(&s, iteration23528, "binding23529", next23526);
        const v23531 = try o.importValue(&s, graph, "guard/index.mjs", "Guard");
        const v23532 = try s.text("HasPropertyKey");
        const v23533 = try s.own(try js.getKey(e, v23531, v23532));
        const v23534 = try o.lookup(&s, iteration23528, "binding23497");
        const v23535 = try s.text("properties");
        const v23536 = try s.own(try js.getKey(e, v23534, v23535));
        const v23537 = try o.lookup(&s, iteration23528, "binding23529");
        const v23538 = try s.call(v23533, v23531, &.{ v23536, v23537 });
        if (s.truthy(v23538)) {
            const v23539 = try o.lookup(&s, iteration23528, "binding23498");
            const v23540 = try o.lookup(&s, iteration23528, "binding23529");
            const v23541 = try o.propertyKey(&s, v23540);
            const v23542 = try o.importValue(&s, graph, "value/clean/from_type.mjs", "FromType");
            const v23543 = try o.lookup(&s, iteration23528, "binding23496");
            const v23544 = try o.lookup(&s, iteration23528, "binding23497");
            const v23545 = try s.text("properties");
            const v23546 = try s.own(try js.getKey(e, v23544, v23545));
            const v23547 = try o.lookup(&s, iteration23528, "binding23529");
            const v23548 = try o.propertyKey(&s, v23547);
            const v23549 = try s.own(try js.getKey(e, v23546, v23548));
            const v23550 = try o.lookup(&s, iteration23528, "binding23498");
            const v23551 = try o.lookup(&s, iteration23528, "binding23529");
            const v23552 = try o.propertyKey(&s, v23551);
            const v23553 = try s.own(try js.getKey(e, v23550, v23552));
            const v23554 = try s.call(v23542, c.pi_js_undefined(), &.{ v23543, v23549, v23553 });
            try js.setKey(e, v23539, v23541, v23554);
            continue :loop23527;
        }
        const v23555 = try o.importValue(&s, graph, "guard/index.mjs", "Guard");
        const v23556 = try s.text("IsBoolean");
        const v23557 = try s.own(try js.getKey(e, v23555, v23556));
        const v23558 = try o.lookup(&s, iteration23528, "binding23503");
        const v23559 = try s.call(v23557, v23555, &.{v23558});
        const v23561 = logical23560: {
            if (!s.truthy(v23559)) break :logical23560 v23559;
            const v23562 = try o.importValue(&s, graph, "guard/index.mjs", "Guard");
            const v23563 = try s.text("IsEqual");
            const v23564 = try s.own(try js.getKey(e, v23562, v23563));
            const v23565 = try o.lookup(&s, iteration23528, "binding23503");
            const v23566 = try s.call(v23564, v23562, &.{ v23565, o.boolean(&s, true) });
            break :logical23560 v23566;
        };
        const v23568 = logical23567: {
            if (s.truthy(v23561)) break :logical23567 v23561;
            const v23569 = try o.importValue(&s, graph, "type/index.mjs", "IsSchema");
            const v23570 = try o.lookup(&s, iteration23528, "binding23503");
            const v23571 = try s.call(v23569, c.pi_js_undefined(), &.{v23570});
            const v23573 = logical23572: {
                if (!s.truthy(v23571)) break :logical23572 v23571;
                const v23574 = try o.importValue(&s, graph, "value/check/index.mjs", "Check");
                const v23575 = try o.lookup(&s, iteration23528, "binding23496");
                const v23576 = try o.lookup(&s, iteration23528, "binding23503");
                const v23577 = try o.lookup(&s, iteration23528, "binding23498");
                const v23578 = try o.lookup(&s, iteration23528, "binding23529");
                const v23579 = try o.propertyKey(&s, v23578);
                const v23580 = try s.own(try js.getKey(e, v23577, v23579));
                const v23581 = try s.call(v23574, c.pi_js_undefined(), &.{ v23575, v23576, v23580 });
                break :logical23572 v23581;
            };
            break :logical23567 v23573;
        };
        try o.assign(&s, iteration23528, "binding23530", v23568);
        const v23582 = try o.lookup(&s, iteration23528, "binding23530");
        if (s.truthy(v23582)) {
            const v23583 = try o.lookup(&s, iteration23528, "binding23498");
            const v23584 = try o.lookup(&s, iteration23528, "binding23529");
            const v23585 = try o.propertyKey(&s, v23584);
            const v23586 = try o.importValue(&s, graph, "value/clean/from_type.mjs", "FromType");
            const v23587 = try o.lookup(&s, iteration23528, "binding23496");
            const v23588 = try o.lookup(&s, iteration23528, "binding23503");
            const v23589 = try o.lookup(&s, iteration23528, "binding23498");
            const v23590 = try o.lookup(&s, iteration23528, "binding23529");
            const v23591 = try o.propertyKey(&s, v23590);
            const v23592 = try s.own(try js.getKey(e, v23589, v23591));
            const v23593 = try s.call(v23586, c.pi_js_undefined(), &.{ v23587, v23588, v23592 });
            try js.setKey(e, v23583, v23585, v23593);
            continue :loop23527;
        }
        const v23594 = try o.lookup(&s, iteration23528, "binding23498");
        const v23595 = try o.lookup(&s, iteration23528, "binding23529");
        const v23596 = try o.propertyKey(&s, v23595);
        const v23597 = try o.deleteKey(&s, v23594, v23596);
        _ = v23597;
    }
    try iterator23525.close();
    const v23598 = try o.lookup(&s, frame, "binding23498");
    return c.JS_DupValue(e.context, v23598);
}
