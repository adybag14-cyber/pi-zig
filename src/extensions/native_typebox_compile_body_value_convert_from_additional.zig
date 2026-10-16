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
    const namespace = try s.get(modules, "value/convert/from_additional.mjs");
    const frame = try o.frame(&s, c.pi_js_null());
    try s.put(frame, "@this", c.pi_js_undefined());
    try s.put(try s.get(graph, "frames"), "value/convert/from_additional.mjs", frame);
    const bindings = try s.object();
    try s.put(try s.get(graph, "bindings"), "value/convert/from_additional.mjs", bindings);
    const v26108 = try s.own(try ordinary.create(e, "FromAdditionalProperties", 4, body26059, &.{ graph, frame }));
    try o.assign(&s, frame, "binding26058", v26108);
    const v26109 = try o.lookup(&s, frame, "binding26058");
    try s.put(namespace, "FromAdditionalProperties", v26109);
    const v26110 = try o.lookup(&s, frame, "binding26058");
    try s.put(namespace, "FromAdditionalProperties", v26110);
    try s.put(bindings, "FromAdditionalProperties", try s.text("binding26058"));
}
fn body26059(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v26065 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding26060", v26065);
    const v26066 = if (args.len > 1) args[1] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding26061", v26066);
    const v26067 = if (args.len > 2) args[2] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding26062", v26067);
    const v26068 = if (args.len > 3) args[3] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding26063", v26068);
    const v26070 = try o.importValue(&s, graph, "guard/index.mjs", "Guard");
    const v26071 = try s.text("Keys");
    const v26072 = try s.own(try js.getKey(e, v26070, v26071));
    const v26073 = try o.lookup(&s, frame, "binding26063");
    const v26074 = try s.call(v26072, v26070, &.{v26073});
    try o.assign(&s, frame, "binding26069", v26074);
    const v26075 = try o.lookup(&s, frame, "binding26061");
    var iterator26076 = try o.iterator(e, v26075);
    defer iterator26076.deinit();
    errdefer iterator26076.closePreserving();
    while (try iterator26076.next()) |next26077| {
        defer e.freeValue(next26077);
        const iteration26079 = try o.frame(&s, frame);
        var destructure26082 = try o.iterator(e, next26077);
        defer destructure26082.deinit();
        errdefer destructure26082.closePreserving();
        const v26083 = try s.own(if (destructure26082.closed) c.pi_js_undefined() else (try destructure26082.next()) orelse c.pi_js_undefined());
        try o.assign(&s, iteration26079, "binding26080", v26083);
        const v26084 = try s.own(if (destructure26082.closed) c.pi_js_undefined() else (try destructure26082.next()) orelse c.pi_js_undefined());
        try o.assign(&s, iteration26079, "binding26081", v26084);
        try destructure26082.close();
        const v26085 = try o.lookup(&s, iteration26079, "binding26069");
        var iterator26086 = try o.iterator(e, v26085);
        defer iterator26086.deinit();
        errdefer iterator26086.closePreserving();
        while (try iterator26086.next()) |next26087| {
            defer e.freeValue(next26087);
            const iteration26089 = try o.frame(&s, iteration26079);
            try o.assign(&s, iteration26089, "binding26090", next26087);
            const v26091 = try o.lookup(&s, iteration26089, "binding26080");
            const v26092 = try s.text("test");
            const v26093 = try s.own(try js.getKey(e, v26091, v26092));
            const v26094 = try o.lookup(&s, iteration26089, "binding26090");
            const v26095 = try s.call(v26093, v26091, &.{v26094});
            if (s.truthy(o.boolean(&s, !s.truthy(v26095)))) {
                const v26096 = try o.lookup(&s, iteration26089, "binding26063");
                const v26097 = try o.lookup(&s, iteration26089, "binding26090");
                const v26098 = try o.propertyKey(&s, v26097);
                const v26099 = try o.importValue(&s, graph, "value/convert/from_type.mjs", "FromType");
                const v26100 = try o.lookup(&s, iteration26089, "binding26060");
                const v26101 = try o.lookup(&s, iteration26089, "binding26062");
                const v26102 = try o.lookup(&s, iteration26089, "binding26063");
                const v26103 = try o.lookup(&s, iteration26089, "binding26090");
                const v26104 = try o.propertyKey(&s, v26103);
                const v26105 = try s.own(try js.getKey(e, v26102, v26104));
                const v26106 = try s.call(v26099, c.pi_js_undefined(), &.{ v26100, v26101, v26105 });
                try js.setKey(e, v26096, v26098, v26106);
            }
        }
        try iterator26086.close();
    }
    try iterator26076.close();
    const v26107 = try o.lookup(&s, frame, "binding26063");
    return c.JS_DupValue(e.context, v26107);
}
