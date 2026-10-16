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
    const namespace = try s.get(modules, "value/convert/from_type.mjs");
    const frame = try o.frame(&s, c.pi_js_null());
    try s.put(frame, "@this", c.pi_js_undefined());
    try s.put(try s.get(graph, "frames"), "value/convert/from_type.mjs", frame);
    const bindings = try s.object();
    try s.put(try s.get(graph, "bindings"), "value/convert/from_type.mjs", bindings);
    const v27173 = try s.own(try ordinary.create(e, "FromType", 3, body26937, &.{ graph, frame }));
    try o.assign(&s, frame, "binding26936", v27173);
    const v27174 = try o.lookup(&s, frame, "binding26936");
    try s.put(namespace, "FromType", v27174);
    const v27175 = try o.lookup(&s, frame, "binding26936");
    try s.put(namespace, "FromType", v27175);
    try s.put(bindings, "FromType", try s.text("binding26936"));
}
fn body26937(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v26941 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding26938", v26941);
    const v26942 = if (args.len > 1) args[1] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding26939", v26942);
    const v26943 = if (args.len > 2) args[2] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding26940", v26943);
    const v26944 = try o.importValue(&s, graph, "type/index.mjs", "*");
    const v26945 = try s.text("IsArray");
    const v26946 = try s.own(try js.getKey(e, v26944, v26945));
    const v26947 = try o.lookup(&s, frame, "binding26939");
    const v26948 = try o.call(&s, @src(), v26946, v26944, &.{v26947});
    const v26950 = conditional26949: {
        if (s.truthy(v26948)) {
            const v26951 = try o.importValue(&s, graph, "value/convert/from_array.mjs", "FromArray");
            const v26952 = try o.lookup(&s, frame, "binding26938");
            const v26953 = try o.lookup(&s, frame, "binding26939");
            const v26954 = try o.lookup(&s, frame, "binding26940");
            const v26955 = try o.call(&s, @src(), v26951, c.pi_js_undefined(), &.{ v26952, v26953, v26954 });
            break :conditional26949 v26955;
        } else {
            const v26956 = try o.importValue(&s, graph, "type/index.mjs", "*");
            const v26957 = try s.text("IsBigInt");
            const v26958 = try s.own(try js.getKey(e, v26956, v26957));
            const v26959 = try o.lookup(&s, frame, "binding26939");
            const v26960 = try o.call(&s, @src(), v26958, v26956, &.{v26959});
            const v26962 = conditional26961: {
                if (s.truthy(v26960)) {
                    const v26963 = try o.importValue(&s, graph, "value/convert/from_bigint.mjs", "FromBigInt");
                    const v26964 = try o.lookup(&s, frame, "binding26938");
                    const v26965 = try o.lookup(&s, frame, "binding26939");
                    const v26966 = try o.lookup(&s, frame, "binding26940");
                    const v26967 = try o.call(&s, @src(), v26963, c.pi_js_undefined(), &.{ v26964, v26965, v26966 });
                    break :conditional26961 v26967;
                } else {
                    const v26968 = try o.importValue(&s, graph, "type/index.mjs", "*");
                    const v26969 = try s.text("IsBoolean");
                    const v26970 = try s.own(try js.getKey(e, v26968, v26969));
                    const v26971 = try o.lookup(&s, frame, "binding26939");
                    const v26972 = try o.call(&s, @src(), v26970, v26968, &.{v26971});
                    const v26974 = conditional26973: {
                        if (s.truthy(v26972)) {
                            const v26975 = try o.importValue(&s, graph, "value/convert/from_boolean.mjs", "FromBoolean");
                            const v26976 = try o.lookup(&s, frame, "binding26938");
                            const v26977 = try o.lookup(&s, frame, "binding26939");
                            const v26978 = try o.lookup(&s, frame, "binding26940");
                            const v26979 = try o.call(&s, @src(), v26975, c.pi_js_undefined(), &.{ v26976, v26977, v26978 });
                            break :conditional26973 v26979;
                        } else {
                            const v26980 = try o.importValue(&s, graph, "type/index.mjs", "*");
                            const v26981 = try s.text("IsCyclic");
                            const v26982 = try s.own(try js.getKey(e, v26980, v26981));
                            const v26983 = try o.lookup(&s, frame, "binding26939");
                            const v26984 = try o.call(&s, @src(), v26982, v26980, &.{v26983});
                            const v26986 = conditional26985: {
                                if (s.truthy(v26984)) {
                                    const v26987 = try o.importValue(&s, graph, "value/convert/from_cyclic.mjs", "FromCyclic");
                                    const v26988 = try o.lookup(&s, frame, "binding26938");
                                    const v26989 = try o.lookup(&s, frame, "binding26939");
                                    const v26990 = try o.lookup(&s, frame, "binding26940");
                                    const v26991 = try o.call(&s, @src(), v26987, c.pi_js_undefined(), &.{ v26988, v26989, v26990 });
                                    break :conditional26985 v26991;
                                } else {
                                    const v26992 = try o.importValue(&s, graph, "type/index.mjs", "*");
                                    const v26993 = try s.text("IsEnum");
                                    const v26994 = try s.own(try js.getKey(e, v26992, v26993));
                                    const v26995 = try o.lookup(&s, frame, "binding26939");
                                    const v26996 = try o.call(&s, @src(), v26994, v26992, &.{v26995});
                                    const v26998 = conditional26997: {
                                        if (s.truthy(v26996)) {
                                            const v26999 = try o.importValue(&s, graph, "value/convert/from_enum.mjs", "FromEnum");
                                            const v27000 = try o.lookup(&s, frame, "binding26938");
                                            const v27001 = try o.lookup(&s, frame, "binding26939");
                                            const v27002 = try o.lookup(&s, frame, "binding26940");
                                            const v27003 = try o.call(&s, @src(), v26999, c.pi_js_undefined(), &.{ v27000, v27001, v27002 });
                                            break :conditional26997 v27003;
                                        } else {
                                            const v27004 = try o.importValue(&s, graph, "type/index.mjs", "*");
                                            const v27005 = try s.text("IsInteger");
                                            const v27006 = try s.own(try js.getKey(e, v27004, v27005));
                                            const v27007 = try o.lookup(&s, frame, "binding26939");
                                            const v27008 = try o.call(&s, @src(), v27006, v27004, &.{v27007});
                                            const v27010 = conditional27009: {
                                                if (s.truthy(v27008)) {
                                                    const v27011 = try o.importValue(&s, graph, "value/convert/from_integer.mjs", "FromInteger");
                                                    const v27012 = try o.lookup(&s, frame, "binding26938");
                                                    const v27013 = try o.lookup(&s, frame, "binding26939");
                                                    const v27014 = try o.lookup(&s, frame, "binding26940");
                                                    const v27015 = try o.call(&s, @src(), v27011, c.pi_js_undefined(), &.{ v27012, v27013, v27014 });
                                                    break :conditional27009 v27015;
                                                } else {
                                                    const v27016 = try o.importValue(&s, graph, "type/index.mjs", "*");
                                                    const v27017 = try s.text("IsIntersect");
                                                    const v27018 = try s.own(try js.getKey(e, v27016, v27017));
                                                    const v27019 = try o.lookup(&s, frame, "binding26939");
                                                    const v27020 = try o.call(&s, @src(), v27018, v27016, &.{v27019});
                                                    const v27022 = conditional27021: {
                                                        if (s.truthy(v27020)) {
                                                            const v27023 = try o.importValue(&s, graph, "value/convert/from_intersect.mjs", "FromIntersect");
                                                            const v27024 = try o.lookup(&s, frame, "binding26938");
                                                            const v27025 = try o.lookup(&s, frame, "binding26939");
                                                            const v27026 = try o.lookup(&s, frame, "binding26940");
                                                            const v27027 = try o.call(&s, @src(), v27023, c.pi_js_undefined(), &.{ v27024, v27025, v27026 });
                                                            break :conditional27021 v27027;
                                                        } else {
                                                            const v27028 = try o.importValue(&s, graph, "type/index.mjs", "*");
                                                            const v27029 = try s.text("IsLiteral");
                                                            const v27030 = try s.own(try js.getKey(e, v27028, v27029));
                                                            const v27031 = try o.lookup(&s, frame, "binding26939");
                                                            const v27032 = try o.call(&s, @src(), v27030, v27028, &.{v27031});
                                                            const v27034 = conditional27033: {
                                                                if (s.truthy(v27032)) {
                                                                    const v27035 = try o.importValue(&s, graph, "value/convert/from_literal.mjs", "FromLiteral");
                                                                    const v27036 = try o.lookup(&s, frame, "binding26938");
                                                                    const v27037 = try o.lookup(&s, frame, "binding26939");
                                                                    const v27038 = try o.lookup(&s, frame, "binding26940");
                                                                    const v27039 = try o.call(&s, @src(), v27035, c.pi_js_undefined(), &.{ v27036, v27037, v27038 });
                                                                    break :conditional27033 v27039;
                                                                } else {
                                                                    const v27040 = try o.importValue(&s, graph, "type/index.mjs", "*");
                                                                    const v27041 = try s.text("IsNull");
                                                                    const v27042 = try s.own(try js.getKey(e, v27040, v27041));
                                                                    const v27043 = try o.lookup(&s, frame, "binding26939");
                                                                    const v27044 = try o.call(&s, @src(), v27042, v27040, &.{v27043});
                                                                    const v27046 = conditional27045: {
                                                                        if (s.truthy(v27044)) {
                                                                            const v27047 = try o.importValue(&s, graph, "value/convert/from_null.mjs", "FromNull");
                                                                            const v27048 = try o.lookup(&s, frame, "binding26938");
                                                                            const v27049 = try o.lookup(&s, frame, "binding26939");
                                                                            const v27050 = try o.lookup(&s, frame, "binding26940");
                                                                            const v27051 = try o.call(&s, @src(), v27047, c.pi_js_undefined(), &.{ v27048, v27049, v27050 });
                                                                            break :conditional27045 v27051;
                                                                        } else {
                                                                            const v27052 = try o.importValue(&s, graph, "type/index.mjs", "*");
                                                                            const v27053 = try s.text("IsNumber");
                                                                            const v27054 = try s.own(try js.getKey(e, v27052, v27053));
                                                                            const v27055 = try o.lookup(&s, frame, "binding26939");
                                                                            const v27056 = try o.call(&s, @src(), v27054, v27052, &.{v27055});
                                                                            const v27058 = conditional27057: {
                                                                                if (s.truthy(v27056)) {
                                                                                    const v27059 = try o.importValue(&s, graph, "value/convert/from_number.mjs", "FromNumber");
                                                                                    const v27060 = try o.lookup(&s, frame, "binding26938");
                                                                                    const v27061 = try o.lookup(&s, frame, "binding26939");
                                                                                    const v27062 = try o.lookup(&s, frame, "binding26940");
                                                                                    const v27063 = try o.call(&s, @src(), v27059, c.pi_js_undefined(), &.{ v27060, v27061, v27062 });
                                                                                    break :conditional27057 v27063;
                                                                                } else {
                                                                                    const v27064 = try o.importValue(&s, graph, "type/index.mjs", "*");
                                                                                    const v27065 = try s.text("IsObject");
                                                                                    const v27066 = try s.own(try js.getKey(e, v27064, v27065));
                                                                                    const v27067 = try o.lookup(&s, frame, "binding26939");
                                                                                    const v27068 = try o.call(&s, @src(), v27066, v27064, &.{v27067});
                                                                                    const v27070 = conditional27069: {
                                                                                        if (s.truthy(v27068)) {
                                                                                            const v27071 = try o.importValue(&s, graph, "value/convert/from_object.mjs", "FromObject");
                                                                                            const v27072 = try o.lookup(&s, frame, "binding26938");
                                                                                            const v27073 = try o.lookup(&s, frame, "binding26939");
                                                                                            const v27074 = try o.lookup(&s, frame, "binding26940");
                                                                                            const v27075 = try o.call(&s, @src(), v27071, c.pi_js_undefined(), &.{ v27072, v27073, v27074 });
                                                                                            break :conditional27069 v27075;
                                                                                        } else {
                                                                                            const v27076 = try o.importValue(&s, graph, "type/index.mjs", "*");
                                                                                            const v27077 = try s.text("IsRecord");
                                                                                            const v27078 = try s.own(try js.getKey(e, v27076, v27077));
                                                                                            const v27079 = try o.lookup(&s, frame, "binding26939");
                                                                                            const v27080 = try o.call(&s, @src(), v27078, v27076, &.{v27079});
                                                                                            const v27082 = conditional27081: {
                                                                                                if (s.truthy(v27080)) {
                                                                                                    const v27083 = try o.importValue(&s, graph, "value/convert/from_record.mjs", "FromRecord");
                                                                                                    const v27084 = try o.lookup(&s, frame, "binding26938");
                                                                                                    const v27085 = try o.lookup(&s, frame, "binding26939");
                                                                                                    const v27086 = try o.lookup(&s, frame, "binding26940");
                                                                                                    const v27087 = try o.call(&s, @src(), v27083, c.pi_js_undefined(), &.{ v27084, v27085, v27086 });
                                                                                                    break :conditional27081 v27087;
                                                                                                } else {
                                                                                                    const v27088 = try o.importValue(&s, graph, "type/index.mjs", "*");
                                                                                                    const v27089 = try s.text("IsRef");
                                                                                                    const v27090 = try s.own(try js.getKey(e, v27088, v27089));
                                                                                                    const v27091 = try o.lookup(&s, frame, "binding26939");
                                                                                                    const v27092 = try o.call(&s, @src(), v27090, v27088, &.{v27091});
                                                                                                    const v27094 = conditional27093: {
                                                                                                        if (s.truthy(v27092)) {
                                                                                                            const v27095 = try o.importValue(&s, graph, "value/convert/from_ref.mjs", "FromRef");
                                                                                                            const v27096 = try o.lookup(&s, frame, "binding26938");
                                                                                                            const v27097 = try o.lookup(&s, frame, "binding26939");
                                                                                                            const v27098 = try o.lookup(&s, frame, "binding26940");
                                                                                                            const v27099 = try o.call(&s, @src(), v27095, c.pi_js_undefined(), &.{ v27096, v27097, v27098 });
                                                                                                            break :conditional27093 v27099;
                                                                                                        } else {
                                                                                                            const v27100 = try o.importValue(&s, graph, "type/index.mjs", "*");
                                                                                                            const v27101 = try s.text("IsString");
                                                                                                            const v27102 = try s.own(try js.getKey(e, v27100, v27101));
                                                                                                            const v27103 = try o.lookup(&s, frame, "binding26939");
                                                                                                            const v27104 = try o.call(&s, @src(), v27102, v27100, &.{v27103});
                                                                                                            const v27106 = conditional27105: {
                                                                                                                if (s.truthy(v27104)) {
                                                                                                                    const v27107 = try o.importValue(&s, graph, "value/convert/from_string.mjs", "FromString");
                                                                                                                    const v27108 = try o.lookup(&s, frame, "binding26938");
                                                                                                                    const v27109 = try o.lookup(&s, frame, "binding26939");
                                                                                                                    const v27110 = try o.lookup(&s, frame, "binding26940");
                                                                                                                    const v27111 = try o.call(&s, @src(), v27107, c.pi_js_undefined(), &.{ v27108, v27109, v27110 });
                                                                                                                    break :conditional27105 v27111;
                                                                                                                } else {
                                                                                                                    const v27112 = try o.importValue(&s, graph, "type/index.mjs", "*");
                                                                                                                    const v27113 = try s.text("IsTemplateLiteral");
                                                                                                                    const v27114 = try s.own(try js.getKey(e, v27112, v27113));
                                                                                                                    const v27115 = try o.lookup(&s, frame, "binding26939");
                                                                                                                    const v27116 = try o.call(&s, @src(), v27114, v27112, &.{v27115});
                                                                                                                    const v27118 = conditional27117: {
                                                                                                                        if (s.truthy(v27116)) {
                                                                                                                            const v27119 = try o.importValue(&s, graph, "value/convert/from_template_literal.mjs", "FromTemplateLiteral");
                                                                                                                            const v27120 = try o.lookup(&s, frame, "binding26938");
                                                                                                                            const v27121 = try o.lookup(&s, frame, "binding26939");
                                                                                                                            const v27122 = try o.lookup(&s, frame, "binding26940");
                                                                                                                            const v27123 = try o.call(&s, @src(), v27119, c.pi_js_undefined(), &.{ v27120, v27121, v27122 });
                                                                                                                            break :conditional27117 v27123;
                                                                                                                        } else {
                                                                                                                            const v27124 = try o.importValue(&s, graph, "type/index.mjs", "*");
                                                                                                                            const v27125 = try s.text("IsTuple");
                                                                                                                            const v27126 = try s.own(try js.getKey(e, v27124, v27125));
                                                                                                                            const v27127 = try o.lookup(&s, frame, "binding26939");
                                                                                                                            const v27128 = try o.call(&s, @src(), v27126, v27124, &.{v27127});
                                                                                                                            const v27130 = conditional27129: {
                                                                                                                                if (s.truthy(v27128)) {
                                                                                                                                    const v27131 = try o.importValue(&s, graph, "value/convert/from_tuple.mjs", "FromTuple");
                                                                                                                                    const v27132 = try o.lookup(&s, frame, "binding26938");
                                                                                                                                    const v27133 = try o.lookup(&s, frame, "binding26939");
                                                                                                                                    const v27134 = try o.lookup(&s, frame, "binding26940");
                                                                                                                                    const v27135 = try o.call(&s, @src(), v27131, c.pi_js_undefined(), &.{ v27132, v27133, v27134 });
                                                                                                                                    break :conditional27129 v27135;
                                                                                                                                } else {
                                                                                                                                    const v27136 = try o.importValue(&s, graph, "type/index.mjs", "*");
                                                                                                                                    const v27137 = try s.text("IsUndefined");
                                                                                                                                    const v27138 = try s.own(try js.getKey(e, v27136, v27137));
                                                                                                                                    const v27139 = try o.lookup(&s, frame, "binding26939");
                                                                                                                                    const v27140 = try o.call(&s, @src(), v27138, v27136, &.{v27139});
                                                                                                                                    const v27142 = conditional27141: {
                                                                                                                                        if (s.truthy(v27140)) {
                                                                                                                                            const v27143 = try o.importValue(&s, graph, "value/convert/from_undefined.mjs", "FromUndefined");
                                                                                                                                            const v27144 = try o.lookup(&s, frame, "binding26938");
                                                                                                                                            const v27145 = try o.lookup(&s, frame, "binding26939");
                                                                                                                                            const v27146 = try o.lookup(&s, frame, "binding26940");
                                                                                                                                            const v27147 = try o.call(&s, @src(), v27143, c.pi_js_undefined(), &.{ v27144, v27145, v27146 });
                                                                                                                                            break :conditional27141 v27147;
                                                                                                                                        } else {
                                                                                                                                            const v27148 = try o.importValue(&s, graph, "type/index.mjs", "*");
                                                                                                                                            const v27149 = try s.text("IsUnion");
                                                                                                                                            const v27150 = try s.own(try js.getKey(e, v27148, v27149));
                                                                                                                                            const v27151 = try o.lookup(&s, frame, "binding26939");
                                                                                                                                            const v27152 = try o.call(&s, @src(), v27150, v27148, &.{v27151});
                                                                                                                                            const v27154 = conditional27153: {
                                                                                                                                                if (s.truthy(v27152)) {
                                                                                                                                                    const v27155 = try o.importValue(&s, graph, "value/convert/from_union.mjs", "FromUnion");
                                                                                                                                                    const v27156 = try o.lookup(&s, frame, "binding26938");
                                                                                                                                                    const v27157 = try o.lookup(&s, frame, "binding26939");
                                                                                                                                                    const v27158 = try o.lookup(&s, frame, "binding26940");
                                                                                                                                                    const v27159 = try o.call(&s, @src(), v27155, c.pi_js_undefined(), &.{ v27156, v27157, v27158 });
                                                                                                                                                    break :conditional27153 v27159;
                                                                                                                                                } else {
                                                                                                                                                    const v27160 = try o.importValue(&s, graph, "type/index.mjs", "*");
                                                                                                                                                    const v27161 = try s.text("IsVoid");
                                                                                                                                                    const v27162 = try s.own(try js.getKey(e, v27160, v27161));
                                                                                                                                                    const v27163 = try o.lookup(&s, frame, "binding26939");
                                                                                                                                                    const v27164 = try o.call(&s, @src(), v27162, v27160, &.{v27163});
                                                                                                                                                    const v27166 = conditional27165: {
                                                                                                                                                        if (s.truthy(v27164)) {
                                                                                                                                                            const v27167 = try o.importValue(&s, graph, "value/convert/from_void.mjs", "FromVoid");
                                                                                                                                                            const v27168 = try o.lookup(&s, frame, "binding26938");
                                                                                                                                                            const v27169 = try o.lookup(&s, frame, "binding26939");
                                                                                                                                                            const v27170 = try o.lookup(&s, frame, "binding26940");
                                                                                                                                                            const v27171 = try o.call(&s, @src(), v27167, c.pi_js_undefined(), &.{ v27168, v27169, v27170 });
                                                                                                                                                            break :conditional27165 v27171;
                                                                                                                                                        } else {
                                                                                                                                                            const v27172 = try o.lookup(&s, frame, "binding26940");
                                                                                                                                                            break :conditional27165 v27172;
                                                                                                                                                        }
                                                                                                                                                    };
                                                                                                                                                    break :conditional27153 v27166;
                                                                                                                                                }
                                                                                                                                            };
                                                                                                                                            break :conditional27141 v27154;
                                                                                                                                        }
                                                                                                                                    };
                                                                                                                                    break :conditional27129 v27142;
                                                                                                                                }
                                                                                                                            };
                                                                                                                            break :conditional27117 v27130;
                                                                                                                        }
                                                                                                                    };
                                                                                                                    break :conditional27105 v27118;
                                                                                                                }
                                                                                                            };
                                                                                                            break :conditional27093 v27106;
                                                                                                        }
                                                                                                    };
                                                                                                    break :conditional27081 v27094;
                                                                                                }
                                                                                            };
                                                                                            break :conditional27069 v27082;
                                                                                        }
                                                                                    };
                                                                                    break :conditional27057 v27070;
                                                                                }
                                                                            };
                                                                            break :conditional27045 v27058;
                                                                        }
                                                                    };
                                                                    break :conditional27033 v27046;
                                                                }
                                                            };
                                                            break :conditional27021 v27034;
                                                        }
                                                    };
                                                    break :conditional27009 v27022;
                                                }
                                            };
                                            break :conditional26997 v27010;
                                        }
                                    };
                                    break :conditional26985 v26998;
                                }
                            };
                            break :conditional26973 v26986;
                        }
                    };
                    break :conditional26961 v26974;
                }
            };
            break :conditional26949 v26962;
        }
    };
    return c.JS_DupValue(e.context, v26950);
}
