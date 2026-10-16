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
    const namespace = try s.get(modules, "value/default/from_object.mjs");
    const frame = try o.frame(&s, c.pi_js_null());
    try s.put(frame, "@this", c.pi_js_undefined());
    try s.put(try s.get(graph, "frames"), "value/default/from_object.mjs", frame);
    const bindings = try s.object();
    try s.put(try s.get(graph, "bindings"), "value/default/from_object.mjs", bindings);
    const v29592 = try s.own(try ordinary.create(e, "FromObject", 3, body29474, &.{ graph, frame }));
    try o.assign(&s, frame, "binding29473", v29592);
    const v29593 = try o.lookup(&s, frame, "binding29473");
    try s.put(namespace, "FromObject", v29593);
    const v29594 = try o.lookup(&s, frame, "binding29473");
    try s.put(namespace, "FromObject", v29594);
    try s.put(bindings, "FromObject", try s.text("binding29473"));
}
fn body29474(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v29479 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding29475", v29479);
    const v29480 = if (args.len > 1) args[1] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding29476", v29480);
    const v29481 = if (args.len > 2) args[2] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding29477", v29481);
    const v29483 = try o.importValue(&s, graph, "guard/index.mjs", "Guard");
    const v29484 = try s.text("IsObject");
    const v29485 = try s.own(try js.getKey(e, v29483, v29484));
    const v29486 = try o.lookup(&s, frame, "binding29477");
    const v29487 = try o.call(&s, @src(), v29485, v29483, &.{v29486});
    if (s.truthy(o.boolean(&s, !s.truthy(v29487)))) {
        const v29488 = try o.lookup(&s, frame, "binding29477");
        return c.JS_DupValue(e.context, v29488);
    }
    const v29489 = try o.importValue(&s, graph, "guard/index.mjs", "Guard");
    const v29490 = try s.text("Keys");
    const v29491 = try s.own(try js.getKey(e, v29489, v29490));
    const v29492 = try o.lookup(&s, frame, "binding29476");
    const v29493 = try s.text("properties");
    const v29494 = try s.own(try js.getKey(e, v29492, v29493));
    const v29495 = try o.call(&s, @src(), v29491, v29489, &.{v29494});
    try o.assign(&s, frame, "binding29482", v29495);
    const v29496 = try o.lookup(&s, frame, "binding29482");
    var iterator29497 = try o.iterator(e, v29496);
    defer iterator29497.deinit();
    errdefer iterator29497.closePreserving();
    loop29499: while (try iterator29497.next()) |next29498| {
        defer e.freeValue(next29498);
        const iteration29500 = try o.frame(&s, frame);
        try o.assign(&s, iteration29500, "binding29501", next29498);
        const v29504 = try o.importValue(&s, graph, "value/default/from_type.mjs", "FromType");
        const v29505 = try o.lookup(&s, iteration29500, "binding29475");
        const v29506 = try o.lookup(&s, iteration29500, "binding29476");
        const v29507 = try s.text("properties");
        const v29508 = try s.own(try js.getKey(e, v29506, v29507));
        const v29509 = try o.lookup(&s, iteration29500, "binding29501");
        const v29510 = try o.propertyKey(&s, v29509);
        const v29511 = try s.own(try js.getKey(e, v29508, v29510));
        const v29512 = try o.lookup(&s, iteration29500, "binding29477");
        const v29513 = try o.lookup(&s, iteration29500, "binding29501");
        const v29514 = try o.propertyKey(&s, v29513);
        const v29515 = try s.own(try js.getKey(e, v29512, v29514));
        const v29516 = try o.call(&s, @src(), v29504, c.pi_js_undefined(), &.{ v29505, v29511, v29515 });
        try o.assign(&s, iteration29500, "binding29502", v29516);
        const v29517 = try o.importValue(&s, graph, "guard/index.mjs", "Guard");
        const v29518 = try s.text("IsUndefined");
        const v29519 = try s.own(try js.getKey(e, v29517, v29518));
        const v29520 = try o.lookup(&s, iteration29500, "binding29502");
        const v29521 = try o.call(&s, @src(), v29519, v29517, &.{v29520});
        const v29523 = logical29522: {
            if (!s.truthy(v29521)) break :logical29522 v29521;
            const v29524 = try o.importValue(&s, graph, "type/index.mjs", "IsOptional");
            const v29525 = try o.lookup(&s, iteration29500, "binding29476");
            const v29526 = try s.text("properties");
            const v29527 = try s.own(try js.getKey(e, v29525, v29526));
            const v29528 = try o.lookup(&s, iteration29500, "binding29501");
            const v29529 = try o.propertyKey(&s, v29528);
            const v29530 = try s.own(try js.getKey(e, v29527, v29529));
            const v29531 = try o.call(&s, @src(), v29524, c.pi_js_undefined(), &.{v29530});
            const v29533 = logical29532: {
                if (s.truthy(v29531)) break :logical29532 v29531;
                const v29534 = try o.importValue(&s, graph, "guard/index.mjs", "Guard");
                const v29535 = try s.text("HasPropertyKey");
                const v29536 = try s.own(try js.getKey(e, v29534, v29535));
                const v29537 = try o.lookup(&s, iteration29500, "binding29476");
                const v29538 = try s.text("properties");
                const v29539 = try s.own(try js.getKey(e, v29537, v29538));
                const v29540 = try o.lookup(&s, iteration29500, "binding29501");
                const v29541 = try o.propertyKey(&s, v29540);
                const v29542 = try s.own(try js.getKey(e, v29539, v29541));
                const v29543 = try s.text("default");
                const v29544 = try o.call(&s, @src(), v29536, v29534, &.{ v29542, v29543 });
                break :logical29532 o.boolean(&s, !s.truthy(v29544));
            };
            break :logical29522 v29533;
        };
        try o.assign(&s, iteration29500, "binding29503", v29523);
        const v29545 = try o.lookup(&s, iteration29500, "binding29503");
        if (s.truthy(v29545)) {
            continue :loop29499;
        }
        const v29546 = try o.lookup(&s, iteration29500, "binding29477");
        const v29547 = try o.lookup(&s, iteration29500, "binding29501");
        const v29548 = try o.propertyKey(&s, v29547);
        const v29549 = try o.lookup(&s, iteration29500, "binding29502");
        try js.setKey(e, v29546, v29548, v29549);
    }
    try iterator29497.close();
    const v29550 = try o.importValue(&s, graph, "schema/types/index.mjs", "IsAdditionalProperties");
    const v29551 = try o.lookup(&s, frame, "binding29476");
    const v29552 = try o.call(&s, @src(), v29550, c.pi_js_undefined(), &.{v29551});
    const v29554 = logical29553: {
        if (s.truthy(o.boolean(&s, !s.truthy(v29552)))) break :logical29553 o.boolean(&s, !s.truthy(v29552));
        const v29555 = try o.importValue(&s, graph, "guard/index.mjs", "Guard");
        const v29556 = try s.text("IsBoolean");
        const v29557 = try s.own(try js.getKey(e, v29555, v29556));
        const v29558 = try o.lookup(&s, frame, "binding29476");
        const v29559 = try s.text("additionalProperties");
        const v29560 = try s.own(try js.getKey(e, v29558, v29559));
        const v29561 = try o.call(&s, @src(), v29557, v29555, &.{v29560});
        break :logical29553 v29561;
    };
    if (s.truthy(v29554)) {
        const v29562 = try o.lookup(&s, frame, "binding29477");
        return c.JS_DupValue(e.context, v29562);
    }
    const v29563 = try o.importValue(&s, graph, "guard/index.mjs", "Guard");
    const v29564 = try s.text("Keys");
    const v29565 = try s.own(try js.getKey(e, v29563, v29564));
    const v29566 = try o.lookup(&s, frame, "binding29477");
    const v29567 = try o.call(&s, @src(), v29565, v29563, &.{v29566});
    var iterator29568 = try o.iterator(e, v29567);
    defer iterator29568.deinit();
    errdefer iterator29568.closePreserving();
    loop29570: while (try iterator29568.next()) |next29569| {
        defer e.freeValue(next29569);
        const iteration29571 = try o.frame(&s, frame);
        try o.assign(&s, iteration29571, "binding29572", next29569);
        const v29573 = try o.lookup(&s, iteration29571, "binding29482");
        const v29574 = try s.text("includes");
        const v29575 = try s.own(try js.getKey(e, v29573, v29574));
        const v29576 = try o.lookup(&s, iteration29571, "binding29572");
        const v29577 = try o.call(&s, @src(), v29575, v29573, &.{v29576});
        if (s.truthy(v29577)) {
            continue :loop29570;
        }
        const v29578 = try o.lookup(&s, iteration29571, "binding29477");
        const v29579 = try o.lookup(&s, iteration29571, "binding29572");
        const v29580 = try o.propertyKey(&s, v29579);
        const v29581 = try o.importValue(&s, graph, "value/default/from_type.mjs", "FromType");
        const v29582 = try o.lookup(&s, iteration29571, "binding29475");
        const v29583 = try o.lookup(&s, iteration29571, "binding29476");
        const v29584 = try s.text("additionalProperties");
        const v29585 = try s.own(try js.getKey(e, v29583, v29584));
        const v29586 = try o.lookup(&s, iteration29571, "binding29477");
        const v29587 = try o.lookup(&s, iteration29571, "binding29572");
        const v29588 = try o.propertyKey(&s, v29587);
        const v29589 = try s.own(try js.getKey(e, v29586, v29588));
        const v29590 = try o.call(&s, @src(), v29581, c.pi_js_undefined(), &.{ v29582, v29585, v29589 });
        try js.setKey(e, v29578, v29580, v29590);
    }
    try iterator29568.close();
    const v29591 = try o.lookup(&s, frame, "binding29477");
    return c.JS_DupValue(e.context, v29591);
}
