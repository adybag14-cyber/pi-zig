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
    const namespace = try s.get(modules, "value/convert/from_object.mjs");
    const frame = try o.frame(&s, c.pi_js_null());
    try s.put(frame, "@this", c.pi_js_undefined());
    try s.put(try s.get(graph, "frames"), "value/convert/from_object.mjs", frame);
    const bindings = try s.object();
    try s.put(try s.get(graph, "bindings"), "value/convert/from_object.mjs", bindings);
    const v26673 = try s.own(try ordinary.create(e, "FromProperties", 3, body26585, &.{ graph, frame }));
    try o.assign(&s, frame, "binding26583", v26673);
    const v26694 = try s.own(try ordinary.create(e, "FromObject", 3, body26674, &.{ graph, frame }));
    try o.assign(&s, frame, "binding26584", v26694);
    const v26695 = try o.lookup(&s, frame, "binding26584");
    try s.put(namespace, "FromObject", v26695);
    const v26696 = try o.lookup(&s, frame, "binding26584");
    try s.put(namespace, "FromObject", v26696);
    try s.put(bindings, "FromObject", try s.text("binding26584"));
}
fn body26585(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v26591 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding26586", v26591);
    const v26592 = if (args.len > 1) args[1] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding26587", v26592);
    const v26593 = if (args.len > 2) args[2] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding26588", v26593);
    const v26596 = try o.importValue(&s, graph, "guard/index.mjs", "Guard");
    const v26597 = try s.text("EntriesRegExp");
    const v26598 = try s.own(try js.getKey(e, v26596, v26597));
    const v26599 = try o.lookup(&s, frame, "binding26587");
    const v26600 = try s.text("properties");
    const v26601 = try s.own(try js.getKey(e, v26599, v26600));
    const v26602 = try s.call(v26598, v26596, &.{v26601});
    try o.assign(&s, frame, "binding26594", v26602);
    const v26603 = try o.importValue(&s, graph, "guard/index.mjs", "Guard");
    const v26604 = try s.text("Keys");
    const v26605 = try s.own(try js.getKey(e, v26603, v26604));
    const v26606 = try o.lookup(&s, frame, "binding26588");
    const v26607 = try s.call(v26605, v26603, &.{v26606});
    try o.assign(&s, frame, "binding26595", v26607);
    const v26608 = try o.lookup(&s, frame, "binding26594");
    var iterator26609 = try o.iterator(e, v26608);
    defer iterator26609.deinit();
    errdefer iterator26609.closePreserving();
    while (try iterator26609.next()) |next26610| {
        defer e.freeValue(next26610);
        const iteration26612 = try o.frame(&s, frame);
        var destructure26615 = try o.iterator(e, next26610);
        defer destructure26615.deinit();
        errdefer destructure26615.closePreserving();
        const v26616 = try s.own(if (destructure26615.closed) c.pi_js_undefined() else (try destructure26615.next()) orelse c.pi_js_undefined());
        try o.assign(&s, iteration26612, "binding26613", v26616);
        const v26617 = try s.own(if (destructure26615.closed) c.pi_js_undefined() else (try destructure26615.next()) orelse c.pi_js_undefined());
        try o.assign(&s, iteration26612, "binding26614", v26617);
        try destructure26615.close();
        const v26618 = try o.lookup(&s, iteration26612, "binding26595");
        var iterator26619 = try o.iterator(e, v26618);
        defer iterator26619.deinit();
        errdefer iterator26619.closePreserving();
        loop26621: while (try iterator26619.next()) |next26620| {
            defer e.freeValue(next26620);
            const iteration26622 = try o.frame(&s, iteration26612);
            try o.assign(&s, iteration26622, "binding26623", next26620);
            const v26624 = try o.lookup(&s, iteration26622, "binding26613");
            const v26625 = try s.text("test");
            const v26626 = try s.own(try js.getKey(e, v26624, v26625));
            const v26627 = try o.lookup(&s, iteration26622, "binding26623");
            const v26628 = try s.call(v26626, v26624, &.{v26627});
            const v26630 = logical26629: {
                if (s.truthy(o.boolean(&s, !s.truthy(v26628)))) break :logical26629 o.boolean(&s, !s.truthy(v26628));
                const v26631 = try o.importValue(&s, graph, "value/shared/optional_undefined.mjs", "IsOptionalUndefined");
                const v26632 = try o.lookup(&s, iteration26622, "binding26614");
                const v26633 = try o.lookup(&s, iteration26622, "binding26623");
                const v26634 = try o.lookup(&s, iteration26622, "binding26588");
                const v26635 = try s.call(v26631, c.pi_js_undefined(), &.{ v26632, v26633, v26634 });
                break :logical26629 v26635;
            };
            if (s.truthy(v26630)) {
                continue :loop26621;
            }
            const v26636 = try o.lookup(&s, iteration26622, "binding26588");
            const v26637 = try o.lookup(&s, iteration26622, "binding26623");
            const v26638 = try o.propertyKey(&s, v26637);
            const v26639 = try o.importValue(&s, graph, "value/convert/from_type.mjs", "FromType");
            const v26640 = try o.lookup(&s, iteration26622, "binding26586");
            const v26641 = try o.lookup(&s, iteration26622, "binding26614");
            const v26642 = try o.lookup(&s, iteration26622, "binding26588");
            const v26643 = try o.lookup(&s, iteration26622, "binding26623");
            const v26644 = try o.propertyKey(&s, v26643);
            const v26645 = try s.own(try js.getKey(e, v26642, v26644));
            const v26646 = try s.call(v26639, c.pi_js_undefined(), &.{ v26640, v26641, v26645 });
            try js.setKey(e, v26636, v26638, v26646);
        }
        try iterator26619.close();
    }
    try iterator26609.close();
    const v26647 = try o.importValue(&s, graph, "guard/index.mjs", "Guard");
    const v26648 = try s.text("HasPropertyKey");
    const v26649 = try s.own(try js.getKey(e, v26647, v26648));
    const v26650 = try o.lookup(&s, frame, "binding26587");
    const v26651 = try s.text("additionalProperties");
    const v26652 = try s.call(v26649, v26647, &.{ v26650, v26651 });
    const v26654 = logical26653: {
        if (!s.truthy(v26652)) break :logical26653 v26652;
        const v26655 = try o.importValue(&s, graph, "guard/index.mjs", "Guard");
        const v26656 = try s.text("IsObject");
        const v26657 = try s.own(try js.getKey(e, v26655, v26656));
        const v26658 = try o.lookup(&s, frame, "binding26587");
        const v26659 = try s.text("additionalProperties");
        const v26660 = try s.own(try js.getKey(e, v26658, v26659));
        const v26661 = try s.call(v26657, v26655, &.{v26660});
        break :logical26653 v26661;
    };
    const v26663 = conditional26662: {
        if (s.truthy(v26654)) {
            const v26664 = try o.importValue(&s, graph, "value/convert/from_additional.mjs", "FromAdditionalProperties");
            const v26665 = try o.lookup(&s, frame, "binding26586");
            const v26666 = try o.lookup(&s, frame, "binding26594");
            const v26667 = try o.lookup(&s, frame, "binding26587");
            const v26668 = try s.text("additionalProperties");
            const v26669 = try s.own(try js.getKey(e, v26667, v26668));
            const v26670 = try o.lookup(&s, frame, "binding26588");
            const v26671 = try s.call(v26664, c.pi_js_undefined(), &.{ v26665, v26666, v26669, v26670 });
            break :conditional26662 v26671;
        } else {
            const v26672 = try o.lookup(&s, frame, "binding26588");
            break :conditional26662 v26672;
        }
    };
    return c.JS_DupValue(e.context, v26663);
}
fn body26674(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v26678 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding26675", v26678);
    const v26679 = if (args.len > 1) args[1] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding26676", v26679);
    const v26680 = if (args.len > 2) args[2] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding26677", v26680);
    const v26681 = try o.importValue(&s, graph, "guard/index.mjs", "Guard");
    const v26682 = try s.text("IsObjectNotArray");
    const v26683 = try s.own(try js.getKey(e, v26681, v26682));
    const v26684 = try o.lookup(&s, frame, "binding26677");
    const v26685 = try s.call(v26683, v26681, &.{v26684});
    const v26687 = conditional26686: {
        if (s.truthy(v26685)) {
            const v26688 = try o.lookup(&s, frame, "binding26583");
            const v26689 = try o.lookup(&s, frame, "binding26675");
            const v26690 = try o.lookup(&s, frame, "binding26676");
            const v26691 = try o.lookup(&s, frame, "binding26677");
            const v26692 = try s.call(v26688, c.pi_js_undefined(), &.{ v26689, v26690, v26691 });
            break :conditional26686 v26692;
        } else {
            const v26693 = try o.lookup(&s, frame, "binding26677");
            break :conditional26686 v26693;
        }
    };
    return c.JS_DupValue(e.context, v26687);
}
