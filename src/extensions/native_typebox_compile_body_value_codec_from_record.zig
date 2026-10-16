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
    const namespace = try s.get(modules, "value/codec/from_record.mjs");
    const frame = try o.frame(&s, c.pi_js_null());
    try s.put(frame, "@this", c.pi_js_undefined());
    try s.put(try s.get(graph, "frames"), "value/codec/from_record.mjs", frame);
    const bindings = try s.object();
    try s.put(try s.get(graph, "bindings"), "value/codec/from_record.mjs", bindings);
    const v25088 = try s.own(try ordinary.create(e, "Decode", 4, body25031, &.{ graph, frame }));
    try o.assign(&s, frame, "binding25028", v25088);
    const v25149 = try s.own(try ordinary.create(e, "Encode", 4, body25089, &.{ graph, frame }));
    try o.assign(&s, frame, "binding25029", v25149);
    const v25179 = try s.own(try ordinary.create(e, "FromRecord", 4, body25150, &.{ graph, frame }));
    try o.assign(&s, frame, "binding25030", v25179);
    const v25180 = try o.lookup(&s, frame, "binding25030");
    try s.put(namespace, "FromRecord", v25180);
    const v25181 = try o.lookup(&s, frame, "binding25030");
    try s.put(namespace, "FromRecord", v25181);
    try s.put(bindings, "FromRecord", try s.text("binding25030"));
}
fn body25031(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v25037 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding25032", v25037);
    const v25038 = if (args.len > 1) args[1] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding25033", v25038);
    const v25039 = if (args.len > 2) args[2] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding25034", v25039);
    const v25040 = if (args.len > 3) args[3] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding25035", v25040);
    const v25042 = try o.importValue(&s, graph, "guard/index.mjs", "Guard");
    const v25043 = try s.text("IsObjectNotArray");
    const v25044 = try s.own(try js.getKey(e, v25042, v25043));
    const v25045 = try o.lookup(&s, frame, "binding25035");
    const v25046 = try o.call(&s, @src(), v25044, v25042, &.{v25045});
    if (s.truthy(o.boolean(&s, !s.truthy(v25046)))) {
        const v25047 = try o.lookup(&s, frame, "binding25035");
        return c.JS_DupValue(e.context, v25047);
    }
    const v25048 = try s.global("RegExp");
    const v25049 = try o.importValue(&s, graph, "type/index.mjs", "RecordPattern");
    const v25050 = try o.lookup(&s, frame, "binding25034");
    const v25051 = try o.call(&s, @src(), v25049, c.pi_js_undefined(), &.{v25050});
    const v25052 = try o.construct(&s, v25048, &.{v25051});
    try o.assign(&s, frame, "binding25041", v25052);
    const v25053 = try o.importValue(&s, graph, "guard/index.mjs", "Guard");
    const v25054 = try s.text("Keys");
    const v25055 = try s.own(try js.getKey(e, v25053, v25054));
    const v25056 = try o.lookup(&s, frame, "binding25035");
    const v25057 = try o.call(&s, @src(), v25055, v25053, &.{v25056});
    var iterator25058 = try o.iterator(e, v25057);
    defer iterator25058.deinit();
    errdefer iterator25058.closePreserving();
    loop25060: while (try iterator25058.next()) |next25059| {
        defer e.freeValue(next25059);
        const iteration25061 = try o.frame(&s, frame);
        try o.assign(&s, iteration25061, "binding25062", next25059);
        const v25063 = try o.lookup(&s, iteration25061, "binding25041");
        const v25064 = try s.text("test");
        const v25065 = try s.own(try js.getKey(e, v25063, v25064));
        const v25066 = try o.lookup(&s, iteration25061, "binding25062");
        const v25067 = try o.call(&s, @src(), v25065, v25063, &.{v25066});
        if (s.truthy(o.boolean(&s, !s.truthy(v25067)))) {
            continue :loop25060;
        }
        const v25068 = try o.lookup(&s, iteration25061, "binding25035");
        const v25069 = try o.lookup(&s, iteration25061, "binding25062");
        const v25070 = try o.propertyKey(&s, v25069);
        const v25071 = try o.importValue(&s, graph, "value/codec/from_type.mjs", "FromType");
        const v25072 = try o.lookup(&s, iteration25061, "binding25032");
        const v25073 = try o.lookup(&s, iteration25061, "binding25033");
        const v25074 = try o.importValue(&s, graph, "type/index.mjs", "RecordValue");
        const v25075 = try o.lookup(&s, iteration25061, "binding25034");
        const v25076 = try o.call(&s, @src(), v25074, c.pi_js_undefined(), &.{v25075});
        const v25077 = try o.lookup(&s, iteration25061, "binding25035");
        const v25078 = try o.lookup(&s, iteration25061, "binding25062");
        const v25079 = try o.propertyKey(&s, v25078);
        const v25080 = try s.own(try js.getKey(e, v25077, v25079));
        const v25081 = try o.call(&s, @src(), v25071, c.pi_js_undefined(), &.{ v25072, v25073, v25076, v25080 });
        try js.setKey(e, v25068, v25070, v25081);
    }
    try iterator25058.close();
    const v25082 = try o.importValue(&s, graph, "value/codec/callback.mjs", "Callback");
    const v25083 = try o.lookup(&s, frame, "binding25032");
    const v25084 = try o.lookup(&s, frame, "binding25033");
    const v25085 = try o.lookup(&s, frame, "binding25034");
    const v25086 = try o.lookup(&s, frame, "binding25035");
    const v25087 = try o.call(&s, @src(), v25082, c.pi_js_undefined(), &.{ v25083, v25084, v25085, v25086 });
    return c.JS_DupValue(e.context, v25087);
}
fn body25089(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v25096 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding25090", v25096);
    const v25097 = if (args.len > 1) args[1] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding25091", v25097);
    const v25098 = if (args.len > 2) args[2] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding25092", v25098);
    const v25099 = if (args.len > 3) args[3] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding25093", v25099);
    const v25102 = try o.importValue(&s, graph, "value/codec/callback.mjs", "Callback");
    const v25103 = try o.lookup(&s, frame, "binding25090");
    const v25104 = try o.lookup(&s, frame, "binding25091");
    const v25105 = try o.lookup(&s, frame, "binding25092");
    const v25106 = try o.lookup(&s, frame, "binding25093");
    const v25107 = try o.call(&s, @src(), v25102, c.pi_js_undefined(), &.{ v25103, v25104, v25105, v25106 });
    try o.assign(&s, frame, "binding25100", v25107);
    const v25108 = try o.importValue(&s, graph, "guard/index.mjs", "Guard");
    const v25109 = try s.text("IsObjectNotArray");
    const v25110 = try s.own(try js.getKey(e, v25108, v25109));
    const v25111 = try o.lookup(&s, frame, "binding25100");
    const v25112 = try o.call(&s, @src(), v25110, v25108, &.{v25111});
    if (s.truthy(o.boolean(&s, !s.truthy(v25112)))) {
        const v25113 = try o.lookup(&s, frame, "binding25100");
        return c.JS_DupValue(e.context, v25113);
    }
    const v25114 = try s.global("RegExp");
    const v25115 = try o.importValue(&s, graph, "type/index.mjs", "RecordPattern");
    const v25116 = try o.lookup(&s, frame, "binding25092");
    const v25117 = try o.call(&s, @src(), v25115, c.pi_js_undefined(), &.{v25116});
    const v25118 = try o.construct(&s, v25114, &.{v25117});
    try o.assign(&s, frame, "binding25101", v25118);
    const v25119 = try o.importValue(&s, graph, "guard/index.mjs", "Guard");
    const v25120 = try s.text("Keys");
    const v25121 = try s.own(try js.getKey(e, v25119, v25120));
    const v25122 = try o.lookup(&s, frame, "binding25100");
    const v25123 = try o.call(&s, @src(), v25121, v25119, &.{v25122});
    var iterator25124 = try o.iterator(e, v25123);
    defer iterator25124.deinit();
    errdefer iterator25124.closePreserving();
    loop25126: while (try iterator25124.next()) |next25125| {
        defer e.freeValue(next25125);
        const iteration25127 = try o.frame(&s, frame);
        try o.assign(&s, iteration25127, "binding25128", next25125);
        const v25129 = try o.lookup(&s, iteration25127, "binding25101");
        const v25130 = try s.text("test");
        const v25131 = try s.own(try js.getKey(e, v25129, v25130));
        const v25132 = try o.lookup(&s, iteration25127, "binding25128");
        const v25133 = try o.call(&s, @src(), v25131, v25129, &.{v25132});
        if (s.truthy(o.boolean(&s, !s.truthy(v25133)))) {
            continue :loop25126;
        }
        const v25134 = try o.lookup(&s, iteration25127, "binding25100");
        const v25135 = try o.lookup(&s, iteration25127, "binding25128");
        const v25136 = try o.propertyKey(&s, v25135);
        const v25137 = try o.importValue(&s, graph, "value/codec/from_type.mjs", "FromType");
        const v25138 = try o.lookup(&s, iteration25127, "binding25090");
        const v25139 = try o.lookup(&s, iteration25127, "binding25091");
        const v25140 = try o.importValue(&s, graph, "type/index.mjs", "RecordValue");
        const v25141 = try o.lookup(&s, iteration25127, "binding25092");
        const v25142 = try o.call(&s, @src(), v25140, c.pi_js_undefined(), &.{v25141});
        const v25143 = try o.lookup(&s, iteration25127, "binding25100");
        const v25144 = try o.lookup(&s, iteration25127, "binding25128");
        const v25145 = try o.propertyKey(&s, v25144);
        const v25146 = try s.own(try js.getKey(e, v25143, v25145));
        const v25147 = try o.call(&s, @src(), v25137, c.pi_js_undefined(), &.{ v25138, v25139, v25142, v25146 });
        try js.setKey(e, v25134, v25136, v25147);
    }
    try iterator25124.close();
    const v25148 = try o.lookup(&s, frame, "binding25100");
    return c.JS_DupValue(e.context, v25148);
}
fn body25150(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v25155 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding25151", v25155);
    const v25156 = if (args.len > 1) args[1] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding25152", v25156);
    const v25157 = if (args.len > 2) args[2] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding25153", v25157);
    const v25158 = if (args.len > 3) args[3] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding25154", v25158);
    const v25159 = try o.importValue(&s, graph, "guard/index.mjs", "Guard");
    const v25160 = try s.text("IsEqual");
    const v25161 = try s.own(try js.getKey(e, v25159, v25160));
    const v25162 = try o.lookup(&s, frame, "binding25151");
    const v25163 = try s.text("Decode");
    const v25164 = try o.call(&s, @src(), v25161, v25159, &.{ v25162, v25163 });
    const v25166 = conditional25165: {
        if (s.truthy(v25164)) {
            const v25167 = try o.lookup(&s, frame, "binding25028");
            const v25168 = try o.lookup(&s, frame, "binding25151");
            const v25169 = try o.lookup(&s, frame, "binding25152");
            const v25170 = try o.lookup(&s, frame, "binding25153");
            const v25171 = try o.lookup(&s, frame, "binding25154");
            const v25172 = try o.call(&s, @src(), v25167, c.pi_js_undefined(), &.{ v25168, v25169, v25170, v25171 });
            break :conditional25165 v25172;
        } else {
            const v25173 = try o.lookup(&s, frame, "binding25029");
            const v25174 = try o.lookup(&s, frame, "binding25151");
            const v25175 = try o.lookup(&s, frame, "binding25152");
            const v25176 = try o.lookup(&s, frame, "binding25153");
            const v25177 = try o.lookup(&s, frame, "binding25154");
            const v25178 = try o.call(&s, @src(), v25173, c.pi_js_undefined(), &.{ v25174, v25175, v25176, v25177 });
            break :conditional25165 v25178;
        }
    };
    return c.JS_DupValue(e.context, v25166);
}
