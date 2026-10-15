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
    const namespace = try s.get(modules, "type/types/_codec.mjs");
    const frame = try o.frame(&s, c.pi_js_null());
    try s.put(frame, "@this", c.pi_js_undefined());
    try s.put(try s.get(graph, "frames"), "type/types/_codec.mjs", frame);
    const bindings = try s.object();
    try s.put(try s.get(graph, "bindings"), "type/types/_codec.mjs", bindings);
    const v22930 = try s.own(try ordinary.create(e, "Codec", 1, body22924, &.{ graph, frame }));
    try o.assign(&s, frame, "binding22920", v22930);
    const v22952 = try s.own(try ordinary.create(e, "Decode", 2, body22931, &.{ graph, frame }));
    try o.assign(&s, frame, "binding22921", v22952);
    const v22974 = try s.own(try ordinary.create(e, "Encode", 2, body22953, &.{ graph, frame }));
    try o.assign(&s, frame, "binding22922", v22974);
    const v23021 = try s.own(try ordinary.create(e, "IsCodec", 1, body22975, &.{ graph, frame }));
    try o.assign(&s, frame, "binding22923", v23021);
    const v23022 = try o.lookup(&s, frame, "binding22920");
    try s.put(namespace, "Codec", v23022);
    const v23023 = try o.lookup(&s, frame, "binding22921");
    try s.put(namespace, "Decode", v23023);
    const v23024 = try o.lookup(&s, frame, "binding22922");
    try s.put(namespace, "Encode", v23024);
    const v23025 = try o.lookup(&s, frame, "binding22923");
    try s.put(namespace, "IsCodec", v23025);
    const v23026 = try s.object();
    const v23036 = try s.own(try class.constructor(e, "EncodeBuilder", 2, v23026, constructor23027, &.{ graph, frame, c.pi_js_undefined() }));
    const v23109 = try o.arrow(&s, "Encode", 1, body23037C, &.{ graph, frame });
    try o.method(&s, v23026, "Encode", v23109);
    try o.assign(&s, frame, "binding22918", v23036);
    const v23110 = try s.object();
    const v23116 = try s.own(try class.constructor(e, "DecodeBuilder", 1, v23110, constructor23111, &.{ graph, frame, c.pi_js_undefined() }));
    const v23125 = try o.arrow(&s, "Decode", 1, body23117C, &.{ graph, frame });
    try o.method(&s, v23110, "Decode", v23125);
    try o.assign(&s, frame, "binding22919", v23116);
    const v23126 = try o.lookup(&s, frame, "binding22920");
    try s.put(namespace, "Codec", v23126);
    const v23127 = try o.lookup(&s, frame, "binding22921");
    try s.put(namespace, "Decode", v23127);
    const v23128 = try o.lookup(&s, frame, "binding22922");
    try s.put(namespace, "Encode", v23128);
    const v23129 = try o.lookup(&s, frame, "binding22923");
    try s.put(namespace, "IsCodec", v23129);
    const v23130 = try o.lookup(&s, frame, "binding22918");
    try s.put(namespace, "EncodeBuilder", v23130);
    const v23131 = try o.lookup(&s, frame, "binding22919");
    try s.put(namespace, "DecodeBuilder", v23131);
    try s.put(bindings, "Codec", try s.text("binding22920"));
    try s.put(bindings, "Decode", try s.text("binding22921"));
    try s.put(bindings, "Encode", try s.text("binding22922"));
    try s.put(bindings, "IsCodec", try s.text("binding22923"));
    try s.put(bindings, "EncodeBuilder", try s.text("binding22918"));
    try s.put(bindings, "DecodeBuilder", try s.text("binding22919"));
}
fn body22924(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    _ = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v22926 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding22925", v22926);
    const v22927 = try o.lookup(&s, frame, "binding22919");
    const v22928 = try o.lookup(&s, frame, "binding22925");
    const v22929 = try o.construct(&s, v22927, &.{v22928});
    return c.JS_DupValue(e.context, v22929);
}
fn body22945(e: *Engine, _: c.JSValue, _: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    _ = roots[0];
    const frame = try o.frame(&s, roots[1]);
    _ = try o.lookup(&s, frame, "@this");
    const v22947 = try s.global("Error");
    const v22948 = try s.text("Encode not implemented");
    const v22949 = try s.call(v22947, c.pi_js_undefined(), &.{v22948});
    _ = c.JS_Throw(e.context, c.JS_DupValue(e.context, v22949));
    return js.capture(e);
}
fn body22945C(ctx: ?*c.JSContext, receiver: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const e = Engine.fromContext(ctx.?);
    return body22945(e, receiver, if (argc > 0) argv[0..@intCast(argc)] else &.{}, roots[0..2]) catch |err| sdk.fail(e, err);
}
fn body22931(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v22934 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding22932", v22934);
    const v22935 = if (args.len > 1) args[1] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding22933", v22935);
    const v22936 = try o.lookup(&s, frame, "binding22920");
    const v22937 = try o.lookup(&s, frame, "binding22932");
    const v22938 = try s.call(v22936, c.pi_js_undefined(), &.{v22937});
    const v22939 = try s.text("Decode");
    const v22940 = try s.own(try js.getKey(e, v22938, v22939));
    const v22941 = try o.lookup(&s, frame, "binding22933");
    const v22942 = try s.call(v22940, v22938, &.{v22941});
    const v22943 = try s.text("Encode");
    const v22944 = try s.own(try js.getKey(e, v22942, v22943));
    const v22950 = try o.arrow(&s, "", 0, body22945C, &.{ graph, frame });
    const v22951 = try s.call(v22944, v22942, &.{v22950});
    return c.JS_DupValue(e.context, v22951);
}
fn body22963(e: *Engine, _: c.JSValue, _: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    _ = roots[0];
    const frame = try o.frame(&s, roots[1]);
    _ = try o.lookup(&s, frame, "@this");
    const v22965 = try s.global("Error");
    const v22966 = try s.text("Decode not implemented");
    const v22967 = try s.call(v22965, c.pi_js_undefined(), &.{v22966});
    _ = c.JS_Throw(e.context, c.JS_DupValue(e.context, v22967));
    return js.capture(e);
}
fn body22963C(ctx: ?*c.JSContext, receiver: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const e = Engine.fromContext(ctx.?);
    return body22963(e, receiver, if (argc > 0) argv[0..@intCast(argc)] else &.{}, roots[0..2]) catch |err| sdk.fail(e, err);
}
fn body22953(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v22956 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding22954", v22956);
    const v22957 = if (args.len > 1) args[1] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding22955", v22957);
    const v22958 = try o.lookup(&s, frame, "binding22920");
    const v22959 = try o.lookup(&s, frame, "binding22954");
    const v22960 = try s.call(v22958, c.pi_js_undefined(), &.{v22959});
    const v22961 = try s.text("Decode");
    const v22962 = try s.own(try js.getKey(e, v22960, v22961));
    const v22968 = try o.arrow(&s, "", 0, body22963C, &.{ graph, frame });
    const v22969 = try s.call(v22962, v22960, &.{v22968});
    const v22970 = try s.text("Encode");
    const v22971 = try s.own(try js.getKey(e, v22969, v22970));
    const v22972 = try o.lookup(&s, frame, "binding22955");
    const v22973 = try s.call(v22971, v22969, &.{v22972});
    return c.JS_DupValue(e.context, v22973);
}
fn body22975(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v22977 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding22976", v22977);
    const v22978 = try o.importValue(&s, graph, "type/types/schema.mjs", "IsSchema");
    const v22979 = try o.lookup(&s, frame, "binding22976");
    const v22980 = try s.call(v22978, c.pi_js_undefined(), &.{v22979});
    const v22982 = logical22981: {
        if (!s.truthy(v22980)) break :logical22981 v22980;
        const v22983 = try o.importValue(&s, graph, "guard/index.mjs", "Guard");
        const v22984 = try s.text("HasPropertyKey");
        const v22985 = try s.own(try js.getKey(e, v22983, v22984));
        const v22986 = try o.lookup(&s, frame, "binding22976");
        const v22987 = try s.text("~codec");
        const v22988 = try s.call(v22985, v22983, &.{ v22986, v22987 });
        break :logical22981 v22988;
    };
    const v22990 = logical22989: {
        if (!s.truthy(v22982)) break :logical22989 v22982;
        const v22991 = try o.importValue(&s, graph, "guard/index.mjs", "Guard");
        const v22992 = try s.text("IsObject");
        const v22993 = try s.own(try js.getKey(e, v22991, v22992));
        const v22994 = try o.lookup(&s, frame, "binding22976");
        const v22995 = try s.text("~codec");
        const v22996 = try o.propertyKey(&s, v22995);
        const v22997 = try s.own(try js.getKey(e, v22994, v22996));
        const v22998 = try s.call(v22993, v22991, &.{v22997});
        break :logical22989 v22998;
    };
    const v23000 = logical22999: {
        if (!s.truthy(v22990)) break :logical22999 v22990;
        const v23001 = try o.importValue(&s, graph, "guard/index.mjs", "Guard");
        const v23002 = try s.text("HasPropertyKey");
        const v23003 = try s.own(try js.getKey(e, v23001, v23002));
        const v23004 = try o.lookup(&s, frame, "binding22976");
        const v23005 = try s.text("~codec");
        const v23006 = try o.propertyKey(&s, v23005);
        const v23007 = try s.own(try js.getKey(e, v23004, v23006));
        const v23008 = try s.text("encode");
        const v23009 = try s.call(v23003, v23001, &.{ v23007, v23008 });
        break :logical22999 v23009;
    };
    const v23011 = logical23010: {
        if (!s.truthy(v23000)) break :logical23010 v23000;
        const v23012 = try o.importValue(&s, graph, "guard/index.mjs", "Guard");
        const v23013 = try s.text("HasPropertyKey");
        const v23014 = try s.own(try js.getKey(e, v23012, v23013));
        const v23015 = try o.lookup(&s, frame, "binding22976");
        const v23016 = try s.text("~codec");
        const v23017 = try o.propertyKey(&s, v23016);
        const v23018 = try s.own(try js.getKey(e, v23015, v23017));
        const v23019 = try s.text("decode");
        const v23020 = try s.call(v23014, v23012, &.{ v23018, v23019 });
        break :logical23010 v23020;
    };
    return c.JS_DupValue(e.context, v23011);
}
fn constructor23027(e: *Engine, target: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    _ = roots[0];
    const frame = try o.frame(&s, roots[1]);
    const v23030 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding23028", v23030);
    const v23031 = if (args.len > 1) args[1] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding23029", v23031);
    const receiver = try s.own(try class.object(e, target));
    try s.put(frame, "@this", receiver);
    const v23032 = try s.text("type");
    const v23033 = try o.lookup(&s, frame, "binding23028");
    try js.setKey(e, receiver, v23032, v23033);
    const v23034 = try s.text("decode");
    const v23035 = try o.lookup(&s, frame, "binding23029");
    try js.setKey(e, receiver, v23034, v23035);
    return c.JS_DupValue(e.context, receiver);
}
fn body23055(e: *Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    _ = roots[0];
    const frame = try o.frame(&s, roots[1]);
    const v23056 = try o.lookup(&s, frame, "@this");
    const v23058 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding23057", v23058);
    const v23059 = try s.text("decode");
    const v23060 = try s.own(try js.getKey(e, v23056, v23059));
    const v23061 = try o.lookup(&s, frame, "binding23044");
    const v23062 = try s.text("~codec");
    const v23063 = try o.propertyKey(&s, v23062);
    const v23064 = try s.own(try js.getKey(e, v23061, v23063));
    const v23065 = try s.text("decode");
    const v23066 = try s.own(try js.getKey(e, v23064, v23065));
    const v23067 = try o.lookup(&s, frame, "binding23057");
    const v23068 = try s.call(v23066, v23064, &.{v23067});
    const v23069 = try s.call(v23060, v23056, &.{v23068});
    return c.JS_DupValue(e.context, v23069);
}
fn body23055C(ctx: ?*c.JSContext, receiver: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const e = Engine.fromContext(ctx.?);
    return body23055(e, receiver, if (argc > 0) argv[0..@intCast(argc)] else &.{}, roots[0..2]) catch |err| sdk.fail(e, err);
}
fn body23078(e: *Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    _ = roots[0];
    const frame = try o.frame(&s, roots[1]);
    _ = try o.lookup(&s, frame, "@this");
    const v23081 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding23080", v23081);
    const v23082 = try o.lookup(&s, frame, "binding23044");
    const v23083 = try s.text("~codec");
    const v23084 = try o.propertyKey(&s, v23083);
    const v23085 = try s.own(try js.getKey(e, v23082, v23084));
    const v23086 = try s.text("encode");
    const v23087 = try s.own(try js.getKey(e, v23085, v23086));
    const v23088 = try o.lookup(&s, frame, "binding23038");
    const v23089 = try o.lookup(&s, frame, "binding23080");
    const v23090 = try s.call(v23088, c.pi_js_undefined(), &.{v23089});
    const v23091 = try s.call(v23087, v23085, &.{v23090});
    return c.JS_DupValue(e.context, v23091);
}
fn body23078C(ctx: ?*c.JSContext, receiver: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const e = Engine.fromContext(ctx.?);
    return body23078(e, receiver, if (argc > 0) argv[0..@intCast(argc)] else &.{}, roots[0..2]) catch |err| sdk.fail(e, err);
}
fn body23037(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v23043 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding23038", v23043);
    const v23048 = try s.text("type");
    const v23049 = try s.own(try js.getKey(e, receiver, v23048));
    try o.assign(&s, frame, "binding23044", v23049);
    const v23050 = try o.lookup(&s, frame, "binding22923");
    const v23051 = try o.lookup(&s, frame, "binding23044");
    const v23052 = try s.call(v23050, c.pi_js_undefined(), &.{v23051});
    const v23054 = conditional23053: {
        if (s.truthy(v23052)) {
            const v23070 = try o.arrow(&s, "", 1, body23055C, &.{ graph, frame });
            break :conditional23053 v23070;
        } else {
            const v23071 = try s.text("decode");
            const v23072 = try s.own(try js.getKey(e, receiver, v23071));
            break :conditional23053 v23072;
        }
    };
    try o.assign(&s, frame, "binding23045", v23054);
    const v23073 = try o.lookup(&s, frame, "binding22923");
    const v23074 = try o.lookup(&s, frame, "binding23044");
    const v23075 = try s.call(v23073, c.pi_js_undefined(), &.{v23074});
    const v23077 = conditional23076: {
        if (s.truthy(v23075)) {
            const v23092 = try o.arrow(&s, "", 1, body23078C, &.{ graph, frame });
            break :conditional23076 v23092;
        } else {
            const v23093 = try o.lookup(&s, frame, "binding23038");
            break :conditional23076 v23093;
        }
    };
    try o.assign(&s, frame, "binding23046", v23077);
    const v23094 = try s.object();
    const v23095 = try s.text("decode");
    const v23096 = try o.lookup(&s, frame, "binding23045");
    try o.defineKey(&s, v23094, v23095, v23096);
    const v23097 = try s.text("encode");
    const v23098 = try o.lookup(&s, frame, "binding23046");
    try o.defineKey(&s, v23094, v23097, v23098);
    try o.assign(&s, frame, "binding23047", v23094);
    const v23099 = try o.importValue(&s, graph, "system/index.mjs", "Memory");
    const v23100 = try s.text("Update");
    const v23101 = try s.own(try js.getKey(e, v23099, v23100));
    const v23102 = try s.text("type");
    const v23103 = try s.own(try js.getKey(e, receiver, v23102));
    const v23104 = try s.object();
    const v23105 = try s.text("~codec");
    const v23106 = try o.lookup(&s, frame, "binding23047");
    try o.defineKey(&s, v23104, v23105, v23106);
    const v23107 = try s.object();
    const v23108 = try s.call(v23101, v23099, &.{ v23103, v23104, v23107 });
    return c.JS_DupValue(e.context, v23108);
}
fn body23037C(ctx: ?*c.JSContext, receiver: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const e = Engine.fromContext(ctx.?);
    return body23037(e, receiver, if (argc > 0) argv[0..@intCast(argc)] else &.{}, roots[0..2]) catch |err| sdk.fail(e, err);
}
fn constructor23111(e: *Engine, target: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    _ = roots[0];
    const frame = try o.frame(&s, roots[1]);
    const v23113 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding23112", v23113);
    const receiver = try s.own(try class.object(e, target));
    try s.put(frame, "@this", receiver);
    const v23114 = try s.text("type");
    const v23115 = try o.lookup(&s, frame, "binding23112");
    try js.setKey(e, receiver, v23114, v23115);
    return c.JS_DupValue(e.context, receiver);
}
fn body23117(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    _ = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v23119 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding23118", v23119);
    const v23120 = try o.lookup(&s, frame, "binding22918");
    const v23121 = try s.text("type");
    const v23122 = try s.own(try js.getKey(e, receiver, v23121));
    const v23123 = try o.lookup(&s, frame, "binding23118");
    const v23124 = try o.construct(&s, v23120, &.{ v23122, v23123 });
    return c.JS_DupValue(e.context, v23124);
}
fn body23117C(ctx: ?*c.JSContext, receiver: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const e = Engine.fromContext(ctx.?);
    return body23117(e, receiver, if (argc > 0) argv[0..@intCast(argc)] else &.{}, roots[0..2]) catch |err| sdk.fail(e, err);
}
