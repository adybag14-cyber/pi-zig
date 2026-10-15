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
    const namespace = try s.get(modules, "value/codec/from_union.mjs");
    const frame = try o.frame(&s, c.pi_js_null());
    try s.put(frame, "@this", c.pi_js_undefined());
    try s.put(try s.get(graph, "frames"), "value/codec/from_union.mjs", frame);
    const bindings = try s.object();
    try s.put(try s.get(graph, "bindings"), "value/codec/from_union.mjs", bindings);
    const v25574 = try s.own(try ordinary.create(e, "Decode", 4, body25538, &.{ graph, frame }));
    try o.assign(&s, frame, "binding25535", v25574);
    const v25616 = try s.own(try ordinary.create(e, "Encode", 4, body25575, &.{ graph, frame }));
    try o.assign(&s, frame, "binding25536", v25616);
    const v25646 = try s.own(try ordinary.create(e, "FromUnion", 4, body25617, &.{ graph, frame }));
    try o.assign(&s, frame, "binding25537", v25646);
    const v25647 = try o.lookup(&s, frame, "binding25537");
    try s.put(namespace, "FromUnion", v25647);
    const v25648 = try o.lookup(&s, frame, "binding25537");
    try s.put(namespace, "FromUnion", v25648);
    try s.put(bindings, "FromUnion", try s.text("binding25537"));
}
fn body25538(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v25543 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding25539", v25543);
    const v25544 = if (args.len > 1) args[1] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding25540", v25544);
    const v25545 = if (args.len > 2) args[2] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding25541", v25545);
    const v25546 = if (args.len > 3) args[3] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding25542", v25546);
    const v25547 = try o.lookup(&s, frame, "binding25541");
    const v25548 = try s.text("anyOf");
    const v25549 = try s.own(try js.getKey(e, v25547, v25548));
    var iterator25550 = try o.iterator(e, v25549);
    defer iterator25550.deinit();
    errdefer iterator25550.closePreserving();
    loop25552: while (try iterator25550.next()) |next25551| {
        defer e.freeValue(next25551);
        const iteration25553 = try o.frame(&s, frame);
        try o.assign(&s, iteration25553, "binding25554", next25551);
        const v25556 = try o.importValue(&s, graph, "value/check/index.mjs", "Check");
        const v25557 = try o.lookup(&s, iteration25553, "binding25540");
        const v25558 = try o.lookup(&s, iteration25553, "binding25554");
        const v25559 = try o.lookup(&s, iteration25553, "binding25542");
        const v25560 = try s.call(v25556, c.pi_js_undefined(), &.{ v25557, v25558, v25559 });
        if (s.truthy(o.boolean(&s, !s.truthy(v25560)))) {
            continue :loop25552;
        }
        const v25561 = try o.importValue(&s, graph, "value/codec/from_type.mjs", "FromType");
        const v25562 = try o.lookup(&s, iteration25553, "binding25539");
        const v25563 = try o.lookup(&s, iteration25553, "binding25540");
        const v25564 = try o.lookup(&s, iteration25553, "binding25554");
        const v25565 = try o.lookup(&s, iteration25553, "binding25542");
        const v25566 = try s.call(v25561, c.pi_js_undefined(), &.{ v25562, v25563, v25564, v25565 });
        try o.assign(&s, iteration25553, "binding25555", v25566);
        const v25567 = try o.importValue(&s, graph, "value/codec/callback.mjs", "Callback");
        const v25568 = try o.lookup(&s, iteration25553, "binding25539");
        const v25569 = try o.lookup(&s, iteration25553, "binding25540");
        const v25570 = try o.lookup(&s, iteration25553, "binding25541");
        const v25571 = try o.lookup(&s, iteration25553, "binding25555");
        const v25572 = try s.call(v25567, c.pi_js_undefined(), &.{ v25568, v25569, v25570, v25571 });
        try iterator25550.close();
        return c.JS_DupValue(e.context, v25572);
    }
    try iterator25550.close();
    const v25573 = try o.lookup(&s, frame, "binding25542");
    return c.JS_DupValue(e.context, v25573);
}
fn body25575(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v25581 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding25576", v25581);
    const v25582 = if (args.len > 1) args[1] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding25577", v25582);
    const v25583 = if (args.len > 2) args[2] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding25578", v25583);
    const v25584 = if (args.len > 3) args[3] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding25579", v25584);
    const v25586 = try o.importValue(&s, graph, "value/codec/callback.mjs", "Callback");
    const v25587 = try o.lookup(&s, frame, "binding25576");
    const v25588 = try o.lookup(&s, frame, "binding25577");
    const v25589 = try o.lookup(&s, frame, "binding25578");
    const v25590 = try o.lookup(&s, frame, "binding25579");
    const v25591 = try s.call(v25586, c.pi_js_undefined(), &.{ v25587, v25588, v25589, v25590 });
    try o.assign(&s, frame, "binding25585", v25591);
    const v25592 = try o.lookup(&s, frame, "binding25578");
    const v25593 = try s.text("anyOf");
    const v25594 = try s.own(try js.getKey(e, v25592, v25593));
    var iterator25595 = try o.iterator(e, v25594);
    defer iterator25595.deinit();
    errdefer iterator25595.closePreserving();
    loop25597: while (try iterator25595.next()) |next25596| {
        defer e.freeValue(next25596);
        const iteration25598 = try o.frame(&s, frame);
        try o.assign(&s, iteration25598, "binding25599", next25596);
        const v25601 = try o.importValue(&s, graph, "value/codec/from_type.mjs", "FromType");
        const v25602 = try o.lookup(&s, iteration25598, "binding25576");
        const v25603 = try o.lookup(&s, iteration25598, "binding25577");
        const v25604 = try o.lookup(&s, iteration25598, "binding25599");
        const v25605 = try o.importValue(&s, graph, "value/clone/index.mjs", "Clone");
        const v25606 = try o.lookup(&s, iteration25598, "binding25585");
        const v25607 = try s.call(v25605, c.pi_js_undefined(), &.{v25606});
        const v25608 = try s.call(v25601, c.pi_js_undefined(), &.{ v25602, v25603, v25604, v25607 });
        try o.assign(&s, iteration25598, "binding25600", v25608);
        const v25609 = try o.importValue(&s, graph, "value/check/index.mjs", "Check");
        const v25610 = try o.lookup(&s, iteration25598, "binding25577");
        const v25611 = try o.lookup(&s, iteration25598, "binding25599");
        const v25612 = try o.lookup(&s, iteration25598, "binding25600");
        const v25613 = try s.call(v25609, c.pi_js_undefined(), &.{ v25610, v25611, v25612 });
        if (s.truthy(o.boolean(&s, !s.truthy(v25613)))) {
            continue :loop25597;
        }
        const v25614 = try o.lookup(&s, iteration25598, "binding25600");
        try iterator25595.close();
        return c.JS_DupValue(e.context, v25614);
    }
    try iterator25595.close();
    const v25615 = try o.lookup(&s, frame, "binding25585");
    return c.JS_DupValue(e.context, v25615);
}
fn body25617(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v25622 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding25618", v25622);
    const v25623 = if (args.len > 1) args[1] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding25619", v25623);
    const v25624 = if (args.len > 2) args[2] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding25620", v25624);
    const v25625 = if (args.len > 3) args[3] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding25621", v25625);
    const v25626 = try o.importValue(&s, graph, "guard/index.mjs", "Guard");
    const v25627 = try s.text("IsEqual");
    const v25628 = try s.own(try js.getKey(e, v25626, v25627));
    const v25629 = try o.lookup(&s, frame, "binding25618");
    const v25630 = try s.text("Decode");
    const v25631 = try s.call(v25628, v25626, &.{ v25629, v25630 });
    const v25633 = conditional25632: {
        if (s.truthy(v25631)) {
            const v25634 = try o.lookup(&s, frame, "binding25535");
            const v25635 = try o.lookup(&s, frame, "binding25618");
            const v25636 = try o.lookup(&s, frame, "binding25619");
            const v25637 = try o.lookup(&s, frame, "binding25620");
            const v25638 = try o.lookup(&s, frame, "binding25621");
            const v25639 = try s.call(v25634, c.pi_js_undefined(), &.{ v25635, v25636, v25637, v25638 });
            break :conditional25632 v25639;
        } else {
            const v25640 = try o.lookup(&s, frame, "binding25536");
            const v25641 = try o.lookup(&s, frame, "binding25618");
            const v25642 = try o.lookup(&s, frame, "binding25619");
            const v25643 = try o.lookup(&s, frame, "binding25620");
            const v25644 = try o.lookup(&s, frame, "binding25621");
            const v25645 = try s.call(v25640, c.pi_js_undefined(), &.{ v25641, v25642, v25643, v25644 });
            break :conditional25632 v25645;
        }
    };
    return c.JS_DupValue(e.context, v25633);
}
