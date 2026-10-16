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
    const namespace = try s.get(modules, "value/create/from_type.mjs");
    const frame = try o.frame(&s, c.pi_js_null());
    try s.put(frame, "@this", c.pi_js_undefined());
    try s.put(try s.get(graph, "frames"), "value/create/from_type.mjs", frame);
    const bindings = try s.object();
    try s.put(try s.get(graph, "bindings"), "value/create/from_type.mjs", bindings);
    const v29244 = try s.own(try ordinary.create(e, "FromType", 2, body28975, &.{ graph, frame }));
    try o.assign(&s, frame, "binding28974", v29244);
    const v29245 = try o.lookup(&s, frame, "binding28974");
    try s.put(namespace, "FromType", v29245);
    const v29246 = try o.lookup(&s, frame, "binding28974");
    try s.put(namespace, "FromType", v29246);
    try s.put(bindings, "FromType", try s.text("binding28974"));
}
fn body28975(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v28978 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding28976", v28978);
    const v28979 = if (args.len > 1) args[1] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding28977", v28979);
    const v28980 = try o.importValue(&s, graph, "schema/types/index.mjs", "*");
    const v28981 = try s.text("IsDefault");
    const v28982 = try s.own(try js.getKey(e, v28980, v28981));
    const v28983 = try o.lookup(&s, frame, "binding28977");
    const v28984 = try s.call(v28982, v28980, &.{v28983});
    const v28986 = conditional28985: {
        if (s.truthy(v28984)) {
            const v28987 = try o.importValue(&s, graph, "value/create/from_default.mjs", "FromDefault");
            const v28988 = try o.lookup(&s, frame, "binding28976");
            const v28989 = try o.lookup(&s, frame, "binding28977");
            const v28990 = try s.call(v28987, c.pi_js_undefined(), &.{ v28988, v28989 });
            break :conditional28985 v28990;
        } else {
            const v28991 = try o.importValue(&s, graph, "type/index.mjs", "*");
            const v28992 = try s.text("IsArray");
            const v28993 = try s.own(try js.getKey(e, v28991, v28992));
            const v28994 = try o.lookup(&s, frame, "binding28977");
            const v28995 = try s.call(v28993, v28991, &.{v28994});
            const v28997 = conditional28996: {
                if (s.truthy(v28995)) {
                    const v28998 = try o.importValue(&s, graph, "value/create/from_array.mjs", "FromArray");
                    const v28999 = try o.lookup(&s, frame, "binding28976");
                    const v29000 = try o.lookup(&s, frame, "binding28977");
                    const v29001 = try s.call(v28998, c.pi_js_undefined(), &.{ v28999, v29000 });
                    break :conditional28996 v29001;
                } else {
                    const v29002 = try o.importValue(&s, graph, "type/index.mjs", "*");
                    const v29003 = try s.text("IsBigInt");
                    const v29004 = try s.own(try js.getKey(e, v29002, v29003));
                    const v29005 = try o.lookup(&s, frame, "binding28977");
                    const v29006 = try s.call(v29004, v29002, &.{v29005});
                    const v29008 = conditional29007: {
                        if (s.truthy(v29006)) {
                            const v29009 = try o.importValue(&s, graph, "value/create/from_bigint.mjs", "FromBigInt");
                            const v29010 = try o.lookup(&s, frame, "binding28976");
                            const v29011 = try o.lookup(&s, frame, "binding28977");
                            const v29012 = try s.call(v29009, c.pi_js_undefined(), &.{ v29010, v29011 });
                            break :conditional29007 v29012;
                        } else {
                            const v29013 = try o.importValue(&s, graph, "type/index.mjs", "*");
                            const v29014 = try s.text("IsBoolean");
                            const v29015 = try s.own(try js.getKey(e, v29013, v29014));
                            const v29016 = try o.lookup(&s, frame, "binding28977");
                            const v29017 = try s.call(v29015, v29013, &.{v29016});
                            const v29019 = conditional29018: {
                                if (s.truthy(v29017)) {
                                    const v29020 = try o.importValue(&s, graph, "value/create/from_boolean.mjs", "FromBoolean");
                                    const v29021 = try o.lookup(&s, frame, "binding28976");
                                    const v29022 = try o.lookup(&s, frame, "binding28977");
                                    const v29023 = try s.call(v29020, c.pi_js_undefined(), &.{ v29021, v29022 });
                                    break :conditional29018 v29023;
                                } else {
                                    const v29024 = try o.importValue(&s, graph, "type/index.mjs", "*");
                                    const v29025 = try s.text("IsConstructor");
                                    const v29026 = try s.own(try js.getKey(e, v29024, v29025));
                                    const v29027 = try o.lookup(&s, frame, "binding28977");
                                    const v29028 = try s.call(v29026, v29024, &.{v29027});
                                    const v29030 = conditional29029: {
                                        if (s.truthy(v29028)) {
                                            const v29031 = try o.importValue(&s, graph, "value/create/from_constructor.mjs", "FromConstructor");
                                            const v29032 = try o.lookup(&s, frame, "binding28976");
                                            const v29033 = try o.lookup(&s, frame, "binding28977");
                                            const v29034 = try s.call(v29031, c.pi_js_undefined(), &.{ v29032, v29033 });
                                            break :conditional29029 v29034;
                                        } else {
                                            const v29035 = try o.importValue(&s, graph, "type/index.mjs", "*");
                                            const v29036 = try s.text("IsCyclic");
                                            const v29037 = try s.own(try js.getKey(e, v29035, v29036));
                                            const v29038 = try o.lookup(&s, frame, "binding28977");
                                            const v29039 = try s.call(v29037, v29035, &.{v29038});
                                            const v29041 = conditional29040: {
                                                if (s.truthy(v29039)) {
                                                    const v29042 = try o.importValue(&s, graph, "value/create/from_cyclic.mjs", "FromCyclic");
                                                    const v29043 = try o.lookup(&s, frame, "binding28976");
                                                    const v29044 = try o.lookup(&s, frame, "binding28977");
                                                    const v29045 = try s.call(v29042, c.pi_js_undefined(), &.{ v29043, v29044 });
                                                    break :conditional29040 v29045;
                                                } else {
                                                    const v29046 = try o.importValue(&s, graph, "type/index.mjs", "*");
                                                    const v29047 = try s.text("IsEnum");
                                                    const v29048 = try s.own(try js.getKey(e, v29046, v29047));
                                                    const v29049 = try o.lookup(&s, frame, "binding28977");
                                                    const v29050 = try s.call(v29048, v29046, &.{v29049});
                                                    const v29052 = conditional29051: {
                                                        if (s.truthy(v29050)) {
                                                            const v29053 = try o.importValue(&s, graph, "value/create/from_enum.mjs", "FromEnum");
                                                            const v29054 = try o.lookup(&s, frame, "binding28976");
                                                            const v29055 = try o.lookup(&s, frame, "binding28977");
                                                            const v29056 = try s.call(v29053, c.pi_js_undefined(), &.{ v29054, v29055 });
                                                            break :conditional29051 v29056;
                                                        } else {
                                                            const v29057 = try o.importValue(&s, graph, "type/index.mjs", "*");
                                                            const v29058 = try s.text("IsFunction");
                                                            const v29059 = try s.own(try js.getKey(e, v29057, v29058));
                                                            const v29060 = try o.lookup(&s, frame, "binding28977");
                                                            const v29061 = try s.call(v29059, v29057, &.{v29060});
                                                            const v29063 = conditional29062: {
                                                                if (s.truthy(v29061)) {
                                                                    const v29064 = try o.importValue(&s, graph, "value/create/from_function.mjs", "FromFunction");
                                                                    const v29065 = try o.lookup(&s, frame, "binding28976");
                                                                    const v29066 = try o.lookup(&s, frame, "binding28977");
                                                                    const v29067 = try s.call(v29064, c.pi_js_undefined(), &.{ v29065, v29066 });
                                                                    break :conditional29062 v29067;
                                                                } else {
                                                                    const v29068 = try o.importValue(&s, graph, "type/index.mjs", "*");
                                                                    const v29069 = try s.text("IsInteger");
                                                                    const v29070 = try s.own(try js.getKey(e, v29068, v29069));
                                                                    const v29071 = try o.lookup(&s, frame, "binding28977");
                                                                    const v29072 = try s.call(v29070, v29068, &.{v29071});
                                                                    const v29074 = conditional29073: {
                                                                        if (s.truthy(v29072)) {
                                                                            const v29075 = try o.importValue(&s, graph, "value/create/from_integer.mjs", "FromInteger");
                                                                            const v29076 = try o.lookup(&s, frame, "binding28976");
                                                                            const v29077 = try o.lookup(&s, frame, "binding28977");
                                                                            const v29078 = try s.call(v29075, c.pi_js_undefined(), &.{ v29076, v29077 });
                                                                            break :conditional29073 v29078;
                                                                        } else {
                                                                            const v29079 = try o.importValue(&s, graph, "type/index.mjs", "*");
                                                                            const v29080 = try s.text("IsIntersect");
                                                                            const v29081 = try s.own(try js.getKey(e, v29079, v29080));
                                                                            const v29082 = try o.lookup(&s, frame, "binding28977");
                                                                            const v29083 = try s.call(v29081, v29079, &.{v29082});
                                                                            const v29085 = conditional29084: {
                                                                                if (s.truthy(v29083)) {
                                                                                    const v29086 = try o.importValue(&s, graph, "value/create/from_intersect.mjs", "FromIntersect");
                                                                                    const v29087 = try o.lookup(&s, frame, "binding28976");
                                                                                    const v29088 = try o.lookup(&s, frame, "binding28977");
                                                                                    const v29089 = try s.call(v29086, c.pi_js_undefined(), &.{ v29087, v29088 });
                                                                                    break :conditional29084 v29089;
                                                                                } else {
                                                                                    const v29090 = try o.importValue(&s, graph, "type/index.mjs", "*");
                                                                                    const v29091 = try s.text("IsLiteral");
                                                                                    const v29092 = try s.own(try js.getKey(e, v29090, v29091));
                                                                                    const v29093 = try o.lookup(&s, frame, "binding28977");
                                                                                    const v29094 = try s.call(v29092, v29090, &.{v29093});
                                                                                    const v29096 = conditional29095: {
                                                                                        if (s.truthy(v29094)) {
                                                                                            const v29097 = try o.importValue(&s, graph, "value/create/from_literal.mjs", "FromLiteral");
                                                                                            const v29098 = try o.lookup(&s, frame, "binding28976");
                                                                                            const v29099 = try o.lookup(&s, frame, "binding28977");
                                                                                            const v29100 = try s.call(v29097, c.pi_js_undefined(), &.{ v29098, v29099 });
                                                                                            break :conditional29095 v29100;
                                                                                        } else {
                                                                                            const v29101 = try o.importValue(&s, graph, "type/index.mjs", "*");
                                                                                            const v29102 = try s.text("IsNever");
                                                                                            const v29103 = try s.own(try js.getKey(e, v29101, v29102));
                                                                                            const v29104 = try o.lookup(&s, frame, "binding28977");
                                                                                            const v29105 = try s.call(v29103, v29101, &.{v29104});
                                                                                            const v29107 = conditional29106: {
                                                                                                if (s.truthy(v29105)) {
                                                                                                    const v29108 = try o.importValue(&s, graph, "value/create/from_never.mjs", "FromNever");
                                                                                                    const v29109 = try o.lookup(&s, frame, "binding28976");
                                                                                                    const v29110 = try o.lookup(&s, frame, "binding28977");
                                                                                                    const v29111 = try s.call(v29108, c.pi_js_undefined(), &.{ v29109, v29110 });
                                                                                                    break :conditional29106 v29111;
                                                                                                } else {
                                                                                                    const v29112 = try o.importValue(&s, graph, "type/index.mjs", "*");
                                                                                                    const v29113 = try s.text("IsNull");
                                                                                                    const v29114 = try s.own(try js.getKey(e, v29112, v29113));
                                                                                                    const v29115 = try o.lookup(&s, frame, "binding28977");
                                                                                                    const v29116 = try s.call(v29114, v29112, &.{v29115});
                                                                                                    const v29118 = conditional29117: {
                                                                                                        if (s.truthy(v29116)) {
                                                                                                            const v29119 = try o.importValue(&s, graph, "value/create/from_null.mjs", "FromNull");
                                                                                                            const v29120 = try o.lookup(&s, frame, "binding28976");
                                                                                                            const v29121 = try o.lookup(&s, frame, "binding28977");
                                                                                                            const v29122 = try s.call(v29119, c.pi_js_undefined(), &.{ v29120, v29121 });
                                                                                                            break :conditional29117 v29122;
                                                                                                        } else {
                                                                                                            const v29123 = try o.importValue(&s, graph, "type/index.mjs", "*");
                                                                                                            const v29124 = try s.text("IsNumber");
                                                                                                            const v29125 = try s.own(try js.getKey(e, v29123, v29124));
                                                                                                            const v29126 = try o.lookup(&s, frame, "binding28977");
                                                                                                            const v29127 = try s.call(v29125, v29123, &.{v29126});
                                                                                                            const v29129 = conditional29128: {
                                                                                                                if (s.truthy(v29127)) {
                                                                                                                    const v29130 = try o.importValue(&s, graph, "value/create/from_number.mjs", "FromNumber");
                                                                                                                    const v29131 = try o.lookup(&s, frame, "binding28976");
                                                                                                                    const v29132 = try o.lookup(&s, frame, "binding28977");
                                                                                                                    const v29133 = try s.call(v29130, c.pi_js_undefined(), &.{ v29131, v29132 });
                                                                                                                    break :conditional29128 v29133;
                                                                                                                } else {
                                                                                                                    const v29134 = try o.importValue(&s, graph, "type/index.mjs", "*");
                                                                                                                    const v29135 = try s.text("IsObject");
                                                                                                                    const v29136 = try s.own(try js.getKey(e, v29134, v29135));
                                                                                                                    const v29137 = try o.lookup(&s, frame, "binding28977");
                                                                                                                    const v29138 = try s.call(v29136, v29134, &.{v29137});
                                                                                                                    const v29140 = conditional29139: {
                                                                                                                        if (s.truthy(v29138)) {
                                                                                                                            const v29141 = try o.importValue(&s, graph, "value/create/from_object.mjs", "FromObject");
                                                                                                                            const v29142 = try o.lookup(&s, frame, "binding28976");
                                                                                                                            const v29143 = try o.lookup(&s, frame, "binding28977");
                                                                                                                            const v29144 = try s.call(v29141, c.pi_js_undefined(), &.{ v29142, v29143 });
                                                                                                                            break :conditional29139 v29144;
                                                                                                                        } else {
                                                                                                                            const v29145 = try o.importValue(&s, graph, "type/index.mjs", "*");
                                                                                                                            const v29146 = try s.text("IsRecord");
                                                                                                                            const v29147 = try s.own(try js.getKey(e, v29145, v29146));
                                                                                                                            const v29148 = try o.lookup(&s, frame, "binding28977");
                                                                                                                            const v29149 = try s.call(v29147, v29145, &.{v29148});
                                                                                                                            const v29151 = conditional29150: {
                                                                                                                                if (s.truthy(v29149)) {
                                                                                                                                    const v29152 = try o.importValue(&s, graph, "value/create/from_record.mjs", "FromRecord");
                                                                                                                                    const v29153 = try o.lookup(&s, frame, "binding28976");
                                                                                                                                    const v29154 = try o.lookup(&s, frame, "binding28977");
                                                                                                                                    const v29155 = try s.call(v29152, c.pi_js_undefined(), &.{ v29153, v29154 });
                                                                                                                                    break :conditional29150 v29155;
                                                                                                                                } else {
                                                                                                                                    const v29156 = try o.importValue(&s, graph, "type/index.mjs", "*");
                                                                                                                                    const v29157 = try s.text("IsRef");
                                                                                                                                    const v29158 = try s.own(try js.getKey(e, v29156, v29157));
                                                                                                                                    const v29159 = try o.lookup(&s, frame, "binding28977");
                                                                                                                                    const v29160 = try s.call(v29158, v29156, &.{v29159});
                                                                                                                                    const v29162 = conditional29161: {
                                                                                                                                        if (s.truthy(v29160)) {
                                                                                                                                            const v29163 = try o.importValue(&s, graph, "value/create/from_ref.mjs", "FromRef");
                                                                                                                                            const v29164 = try o.lookup(&s, frame, "binding28976");
                                                                                                                                            const v29165 = try o.lookup(&s, frame, "binding28977");
                                                                                                                                            const v29166 = try s.call(v29163, c.pi_js_undefined(), &.{ v29164, v29165 });
                                                                                                                                            break :conditional29161 v29166;
                                                                                                                                        } else {
                                                                                                                                            const v29167 = try o.importValue(&s, graph, "type/index.mjs", "*");
                                                                                                                                            const v29168 = try s.text("IsString");
                                                                                                                                            const v29169 = try s.own(try js.getKey(e, v29167, v29168));
                                                                                                                                            const v29170 = try o.lookup(&s, frame, "binding28977");
                                                                                                                                            const v29171 = try s.call(v29169, v29167, &.{v29170});
                                                                                                                                            const v29173 = conditional29172: {
                                                                                                                                                if (s.truthy(v29171)) {
                                                                                                                                                    const v29174 = try o.importValue(&s, graph, "value/create/from_string.mjs", "FromString");
                                                                                                                                                    const v29175 = try o.lookup(&s, frame, "binding28976");
                                                                                                                                                    const v29176 = try o.lookup(&s, frame, "binding28977");
                                                                                                                                                    const v29177 = try s.call(v29174, c.pi_js_undefined(), &.{ v29175, v29176 });
                                                                                                                                                    break :conditional29172 v29177;
                                                                                                                                                } else {
                                                                                                                                                    const v29178 = try o.importValue(&s, graph, "type/index.mjs", "*");
                                                                                                                                                    const v29179 = try s.text("IsSymbol");
                                                                                                                                                    const v29180 = try s.own(try js.getKey(e, v29178, v29179));
                                                                                                                                                    const v29181 = try o.lookup(&s, frame, "binding28977");
                                                                                                                                                    const v29182 = try s.call(v29180, v29178, &.{v29181});
                                                                                                                                                    const v29184 = conditional29183: {
                                                                                                                                                        if (s.truthy(v29182)) {
                                                                                                                                                            const v29185 = try o.importValue(&s, graph, "value/create/from_symbol.mjs", "FromSymbol");
                                                                                                                                                            const v29186 = try o.lookup(&s, frame, "binding28976");
                                                                                                                                                            const v29187 = try o.lookup(&s, frame, "binding28977");
                                                                                                                                                            const v29188 = try s.call(v29185, c.pi_js_undefined(), &.{ v29186, v29187 });
                                                                                                                                                            break :conditional29183 v29188;
                                                                                                                                                        } else {
                                                                                                                                                            const v29189 = try o.importValue(&s, graph, "type/index.mjs", "*");
                                                                                                                                                            const v29190 = try s.text("IsTemplateLiteral");
                                                                                                                                                            const v29191 = try s.own(try js.getKey(e, v29189, v29190));
                                                                                                                                                            const v29192 = try o.lookup(&s, frame, "binding28977");
                                                                                                                                                            const v29193 = try s.call(v29191, v29189, &.{v29192});
                                                                                                                                                            const v29195 = conditional29194: {
                                                                                                                                                                if (s.truthy(v29193)) {
                                                                                                                                                                    const v29196 = try o.importValue(&s, graph, "value/create/from_template_literal.mjs", "FromTemplateLiteral");
                                                                                                                                                                    const v29197 = try o.lookup(&s, frame, "binding28976");
                                                                                                                                                                    const v29198 = try o.lookup(&s, frame, "binding28977");
                                                                                                                                                                    const v29199 = try s.call(v29196, c.pi_js_undefined(), &.{ v29197, v29198 });
                                                                                                                                                                    break :conditional29194 v29199;
                                                                                                                                                                } else {
                                                                                                                                                                    const v29200 = try o.importValue(&s, graph, "type/index.mjs", "*");
                                                                                                                                                                    const v29201 = try s.text("IsTuple");
                                                                                                                                                                    const v29202 = try s.own(try js.getKey(e, v29200, v29201));
                                                                                                                                                                    const v29203 = try o.lookup(&s, frame, "binding28977");
                                                                                                                                                                    const v29204 = try s.call(v29202, v29200, &.{v29203});
                                                                                                                                                                    const v29206 = conditional29205: {
                                                                                                                                                                        if (s.truthy(v29204)) {
                                                                                                                                                                            const v29207 = try o.importValue(&s, graph, "value/create/from_tuple.mjs", "FromTuple");
                                                                                                                                                                            const v29208 = try o.lookup(&s, frame, "binding28976");
                                                                                                                                                                            const v29209 = try o.lookup(&s, frame, "binding28977");
                                                                                                                                                                            const v29210 = try s.call(v29207, c.pi_js_undefined(), &.{ v29208, v29209 });
                                                                                                                                                                            break :conditional29205 v29210;
                                                                                                                                                                        } else {
                                                                                                                                                                            const v29211 = try o.importValue(&s, graph, "type/index.mjs", "*");
                                                                                                                                                                            const v29212 = try s.text("IsUndefined");
                                                                                                                                                                            const v29213 = try s.own(try js.getKey(e, v29211, v29212));
                                                                                                                                                                            const v29214 = try o.lookup(&s, frame, "binding28977");
                                                                                                                                                                            const v29215 = try s.call(v29213, v29211, &.{v29214});
                                                                                                                                                                            const v29217 = conditional29216: {
                                                                                                                                                                                if (s.truthy(v29215)) {
                                                                                                                                                                                    const v29218 = try o.importValue(&s, graph, "value/create/from_undefined.mjs", "FromUndefined");
                                                                                                                                                                                    const v29219 = try o.lookup(&s, frame, "binding28976");
                                                                                                                                                                                    const v29220 = try o.lookup(&s, frame, "binding28977");
                                                                                                                                                                                    const v29221 = try s.call(v29218, c.pi_js_undefined(), &.{ v29219, v29220 });
                                                                                                                                                                                    break :conditional29216 v29221;
                                                                                                                                                                                } else {
                                                                                                                                                                                    const v29222 = try o.importValue(&s, graph, "type/index.mjs", "*");
                                                                                                                                                                                    const v29223 = try s.text("IsUnion");
                                                                                                                                                                                    const v29224 = try s.own(try js.getKey(e, v29222, v29223));
                                                                                                                                                                                    const v29225 = try o.lookup(&s, frame, "binding28977");
                                                                                                                                                                                    const v29226 = try s.call(v29224, v29222, &.{v29225});
                                                                                                                                                                                    const v29228 = conditional29227: {
                                                                                                                                                                                        if (s.truthy(v29226)) {
                                                                                                                                                                                            const v29229 = try o.importValue(&s, graph, "value/create/from_union.mjs", "FromUnion");
                                                                                                                                                                                            const v29230 = try o.lookup(&s, frame, "binding28976");
                                                                                                                                                                                            const v29231 = try o.lookup(&s, frame, "binding28977");
                                                                                                                                                                                            const v29232 = try s.call(v29229, c.pi_js_undefined(), &.{ v29230, v29231 });
                                                                                                                                                                                            break :conditional29227 v29232;
                                                                                                                                                                                        } else {
                                                                                                                                                                                            const v29233 = try o.importValue(&s, graph, "type/index.mjs", "*");
                                                                                                                                                                                            const v29234 = try s.text("IsVoid");
                                                                                                                                                                                            const v29235 = try s.own(try js.getKey(e, v29233, v29234));
                                                                                                                                                                                            const v29236 = try o.lookup(&s, frame, "binding28977");
                                                                                                                                                                                            const v29237 = try s.call(v29235, v29233, &.{v29236});
                                                                                                                                                                                            const v29239 = conditional29238: {
                                                                                                                                                                                                if (s.truthy(v29237)) {
                                                                                                                                                                                                    const v29240 = try o.importValue(&s, graph, "value/create/from_void.mjs", "FromVoid");
                                                                                                                                                                                                    const v29241 = try o.lookup(&s, frame, "binding28976");
                                                                                                                                                                                                    const v29242 = try o.lookup(&s, frame, "binding28977");
                                                                                                                                                                                                    const v29243 = try s.call(v29240, c.pi_js_undefined(), &.{ v29241, v29242 });
                                                                                                                                                                                                    break :conditional29238 v29243;
                                                                                                                                                                                                } else {
                                                                                                                                                                                                    break :conditional29238 c.pi_js_undefined();
                                                                                                                                                                                                }
                                                                                                                                                                                            };
                                                                                                                                                                                            break :conditional29227 v29239;
                                                                                                                                                                                        }
                                                                                                                                                                                    };
                                                                                                                                                                                    break :conditional29216 v29228;
                                                                                                                                                                                }
                                                                                                                                                                            };
                                                                                                                                                                            break :conditional29205 v29217;
                                                                                                                                                                        }
                                                                                                                                                                    };
                                                                                                                                                                    break :conditional29194 v29206;
                                                                                                                                                                }
                                                                                                                                                            };
                                                                                                                                                            break :conditional29183 v29195;
                                                                                                                                                        }
                                                                                                                                                    };
                                                                                                                                                    break :conditional29172 v29184;
                                                                                                                                                }
                                                                                                                                            };
                                                                                                                                            break :conditional29161 v29173;
                                                                                                                                        }
                                                                                                                                    };
                                                                                                                                    break :conditional29150 v29162;
                                                                                                                                }
                                                                                                                            };
                                                                                                                            break :conditional29139 v29151;
                                                                                                                        }
                                                                                                                    };
                                                                                                                    break :conditional29128 v29140;
                                                                                                                }
                                                                                                            };
                                                                                                            break :conditional29117 v29129;
                                                                                                        }
                                                                                                    };
                                                                                                    break :conditional29106 v29118;
                                                                                                }
                                                                                            };
                                                                                            break :conditional29095 v29107;
                                                                                        }
                                                                                    };
                                                                                    break :conditional29084 v29096;
                                                                                }
                                                                            };
                                                                            break :conditional29073 v29085;
                                                                        }
                                                                    };
                                                                    break :conditional29062 v29074;
                                                                }
                                                            };
                                                            break :conditional29051 v29063;
                                                        }
                                                    };
                                                    break :conditional29040 v29052;
                                                }
                                            };
                                            break :conditional29029 v29041;
                                        }
                                    };
                                    break :conditional29018 v29030;
                                }
                            };
                            break :conditional29007 v29019;
                        }
                    };
                    break :conditional28996 v29008;
                }
            };
            break :conditional28985 v28997;
        }
    };
    return c.JS_DupValue(e.context, v28986);
}
