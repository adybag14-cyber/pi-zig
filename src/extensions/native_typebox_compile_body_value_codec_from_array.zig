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
    const namespace = try s.get(modules, "value/codec/from_array.mjs");
    const frame = try o.frame(&s, c.pi_js_null());
    try s.put(frame, "@this", c.pi_js_undefined());
    try s.put(try s.get(graph, "frames"), "value/codec/from_array.mjs", frame);
    const bindings = try s.object();
    try s.put(try s.get(graph, "bindings"), "value/codec/from_array.mjs", bindings);
    const v24497 = try s.own(try ordinary.create(e, "Decode", 4, body24452, &.{ graph, frame }));
    try o.assign(&s, frame, "binding24449", v24497);
    const v24546 = try s.own(try ordinary.create(e, "Encode", 4, body24498, &.{ graph, frame }));
    try o.assign(&s, frame, "binding24450", v24546);
    const v24576 = try s.own(try ordinary.create(e, "FromArray", 4, body24547, &.{ graph, frame }));
    try o.assign(&s, frame, "binding24451", v24576);
    const v24577 = try o.lookup(&s, frame, "binding24451");
    try s.put(namespace, "FromArray", v24577);
    const v24578 = try o.lookup(&s, frame, "binding24451");
    try s.put(namespace, "FromArray", v24578);
    try s.put(bindings, "FromArray", try s.text("binding24451"));
}
fn body24452(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v24457 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding24453", v24457);
    const v24458 = if (args.len > 1) args[1] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding24454", v24458);
    const v24459 = if (args.len > 2) args[2] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding24455", v24459);
    const v24460 = if (args.len > 3) args[3] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding24456", v24460);
    const v24461 = try o.importValue(&s, graph, "guard/index.mjs", "Guard");
    const v24462 = try s.text("IsArray");
    const v24463 = try s.own(try js.getKey(e, v24461, v24462));
    const v24464 = try o.lookup(&s, frame, "binding24456");
    const v24465 = try o.call(&s, @src(), v24463, v24461, &.{v24464});
    if (s.truthy(o.boolean(&s, !s.truthy(v24465)))) {
        const v24466 = try o.lookup(&s, frame, "binding24456");
        return c.JS_DupValue(e.context, v24466);
    }
    try o.assign(&s, frame, "binding24467", c.JS_NewFloat64(e.context, 0));
    loop24468: while (true) {
        const v24470 = try o.lookup(&s, frame, "binding24467");
        const v24471 = try o.lookup(&s, frame, "binding24456");
        const v24472 = try s.text("length");
        const v24473 = try s.own(try js.getKey(e, v24471, v24472));
        const v24474 = try s.own(try e.checked(c.JS_PiBinaryOperator(e.context, 4, v24470, v24473)));
        if (!s.truthy(v24474)) break :loop24468;
        {
            const v24475 = try o.lookup(&s, frame, "binding24456");
            const v24476 = try o.lookup(&s, frame, "binding24467");
            const v24477 = try o.propertyKey(&s, v24476);
            const v24478 = try o.importValue(&s, graph, "value/codec/from_type.mjs", "FromType");
            const v24479 = try o.lookup(&s, frame, "binding24453");
            const v24480 = try o.lookup(&s, frame, "binding24454");
            const v24481 = try o.lookup(&s, frame, "binding24455");
            const v24482 = try s.text("items");
            const v24483 = try s.own(try js.getKey(e, v24481, v24482));
            const v24484 = try o.lookup(&s, frame, "binding24456");
            const v24485 = try o.lookup(&s, frame, "binding24467");
            const v24486 = try o.propertyKey(&s, v24485);
            const v24487 = try s.own(try js.getKey(e, v24484, v24486));
            const v24488 = try o.call(&s, @src(), v24478, c.pi_js_undefined(), &.{ v24479, v24480, v24483, v24487 });
            try js.setKey(e, v24475, v24477, v24488);
        }
        const v24489 = try o.lookup(&s, frame, "binding24467");
        const v24490 = try s.own(try e.checked(c.JS_PiIncrement(e.context, v24489)));
        try o.assign(&s, frame, "binding24467", v24490);
    }
    const v24491 = try o.importValue(&s, graph, "value/codec/callback.mjs", "Callback");
    const v24492 = try o.lookup(&s, frame, "binding24453");
    const v24493 = try o.lookup(&s, frame, "binding24454");
    const v24494 = try o.lookup(&s, frame, "binding24455");
    const v24495 = try o.lookup(&s, frame, "binding24456");
    const v24496 = try o.call(&s, @src(), v24491, c.pi_js_undefined(), &.{ v24492, v24493, v24494, v24495 });
    return c.JS_DupValue(e.context, v24496);
}
fn body24498(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v24504 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding24499", v24504);
    const v24505 = if (args.len > 1) args[1] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding24500", v24505);
    const v24506 = if (args.len > 2) args[2] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding24501", v24506);
    const v24507 = if (args.len > 3) args[3] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding24502", v24507);
    const v24509 = try o.importValue(&s, graph, "value/codec/callback.mjs", "Callback");
    const v24510 = try o.lookup(&s, frame, "binding24499");
    const v24511 = try o.lookup(&s, frame, "binding24500");
    const v24512 = try o.lookup(&s, frame, "binding24501");
    const v24513 = try o.lookup(&s, frame, "binding24502");
    const v24514 = try o.call(&s, @src(), v24509, c.pi_js_undefined(), &.{ v24510, v24511, v24512, v24513 });
    try o.assign(&s, frame, "binding24508", v24514);
    const v24515 = try o.importValue(&s, graph, "guard/index.mjs", "Guard");
    const v24516 = try s.text("IsArray");
    const v24517 = try s.own(try js.getKey(e, v24515, v24516));
    const v24518 = try o.lookup(&s, frame, "binding24508");
    const v24519 = try o.call(&s, @src(), v24517, v24515, &.{v24518});
    if (s.truthy(o.boolean(&s, !s.truthy(v24519)))) {
        const v24520 = try o.lookup(&s, frame, "binding24508");
        return c.JS_DupValue(e.context, v24520);
    }
    try o.assign(&s, frame, "binding24521", c.JS_NewFloat64(e.context, 0));
    loop24522: while (true) {
        const v24524 = try o.lookup(&s, frame, "binding24521");
        const v24525 = try o.lookup(&s, frame, "binding24508");
        const v24526 = try s.text("length");
        const v24527 = try s.own(try js.getKey(e, v24525, v24526));
        const v24528 = try s.own(try e.checked(c.JS_PiBinaryOperator(e.context, 4, v24524, v24527)));
        if (!s.truthy(v24528)) break :loop24522;
        {
            const v24529 = try o.lookup(&s, frame, "binding24508");
            const v24530 = try o.lookup(&s, frame, "binding24521");
            const v24531 = try o.propertyKey(&s, v24530);
            const v24532 = try o.importValue(&s, graph, "value/codec/from_type.mjs", "FromType");
            const v24533 = try o.lookup(&s, frame, "binding24499");
            const v24534 = try o.lookup(&s, frame, "binding24500");
            const v24535 = try o.lookup(&s, frame, "binding24501");
            const v24536 = try s.text("items");
            const v24537 = try s.own(try js.getKey(e, v24535, v24536));
            const v24538 = try o.lookup(&s, frame, "binding24508");
            const v24539 = try o.lookup(&s, frame, "binding24521");
            const v24540 = try o.propertyKey(&s, v24539);
            const v24541 = try s.own(try js.getKey(e, v24538, v24540));
            const v24542 = try o.call(&s, @src(), v24532, c.pi_js_undefined(), &.{ v24533, v24534, v24537, v24541 });
            try js.setKey(e, v24529, v24531, v24542);
        }
        const v24543 = try o.lookup(&s, frame, "binding24521");
        const v24544 = try s.own(try e.checked(c.JS_PiIncrement(e.context, v24543)));
        try o.assign(&s, frame, "binding24521", v24544);
    }
    const v24545 = try o.lookup(&s, frame, "binding24508");
    return c.JS_DupValue(e.context, v24545);
}
fn body24547(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v24552 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding24548", v24552);
    const v24553 = if (args.len > 1) args[1] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding24549", v24553);
    const v24554 = if (args.len > 2) args[2] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding24550", v24554);
    const v24555 = if (args.len > 3) args[3] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding24551", v24555);
    const v24556 = try o.importValue(&s, graph, "guard/index.mjs", "Guard");
    const v24557 = try s.text("IsEqual");
    const v24558 = try s.own(try js.getKey(e, v24556, v24557));
    const v24559 = try o.lookup(&s, frame, "binding24548");
    const v24560 = try s.text("Decode");
    const v24561 = try o.call(&s, @src(), v24558, v24556, &.{ v24559, v24560 });
    const v24563 = conditional24562: {
        if (s.truthy(v24561)) {
            const v24564 = try o.lookup(&s, frame, "binding24449");
            const v24565 = try o.lookup(&s, frame, "binding24548");
            const v24566 = try o.lookup(&s, frame, "binding24549");
            const v24567 = try o.lookup(&s, frame, "binding24550");
            const v24568 = try o.lookup(&s, frame, "binding24551");
            const v24569 = try o.call(&s, @src(), v24564, c.pi_js_undefined(), &.{ v24565, v24566, v24567, v24568 });
            break :conditional24562 v24569;
        } else {
            const v24570 = try o.lookup(&s, frame, "binding24450");
            const v24571 = try o.lookup(&s, frame, "binding24548");
            const v24572 = try o.lookup(&s, frame, "binding24549");
            const v24573 = try o.lookup(&s, frame, "binding24550");
            const v24574 = try o.lookup(&s, frame, "binding24551");
            const v24575 = try o.call(&s, @src(), v24570, c.pi_js_undefined(), &.{ v24571, v24572, v24573, v24574 });
            break :conditional24562 v24575;
        }
    };
    return c.JS_DupValue(e.context, v24563);
}
