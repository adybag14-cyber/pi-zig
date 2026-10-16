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
    const namespace = try s.get(modules, "schema/engine/anyOf.mjs");
    const frame = try o.frame(&s, c.pi_js_null());
    try s.put(frame, "@this", c.pi_js_undefined());
    try s.put(try s.get(graph, "frames"), "schema/engine/anyOf.mjs", frame);
    const bindings = try s.object();
    try s.put(try s.get(graph, "bindings"), "schema/engine/anyOf.mjs", bindings);
    const v7101 = try s.own(try ordinary.create(e, "BuildAnyOfStandard", 4, body7070, &.{ graph, frame }));
    try o.assign(&s, frame, "binding7065", v7101);
    const v7132 = try s.own(try ordinary.create(e, "BuildAnyOfFast", 4, body7102, &.{ graph, frame }));
    try o.assign(&s, frame, "binding7066", v7132);
    const v7160 = try s.own(try ordinary.create(e, "BuildAnyOf", 4, body7133, &.{ graph, frame }));
    try o.assign(&s, frame, "binding7067", v7160);
    const v7216 = try s.own(try ordinary.create(e, "CheckAnyOf", 4, body7161, &.{ graph, frame }));
    try o.assign(&s, frame, "binding7068", v7216);
    const v7350 = try s.own(try ordinary.create(e, "ErrorAnyOf", 6, body7217, &.{ graph, frame }));
    try o.assign(&s, frame, "binding7069", v7350);
    const v7351 = try o.lookup(&s, frame, "binding7067");
    try s.put(namespace, "BuildAnyOf", v7351);
    const v7352 = try o.lookup(&s, frame, "binding7068");
    try s.put(namespace, "CheckAnyOf", v7352);
    const v7353 = try o.lookup(&s, frame, "binding7069");
    try s.put(namespace, "ErrorAnyOf", v7353);
    const v7354 = try o.lookup(&s, frame, "binding7067");
    try s.put(namespace, "BuildAnyOf", v7354);
    const v7355 = try o.lookup(&s, frame, "binding7068");
    try s.put(namespace, "CheckAnyOf", v7355);
    const v7356 = try o.lookup(&s, frame, "binding7069");
    try s.put(namespace, "ErrorAnyOf", v7356);
    try s.put(bindings, "BuildAnyOf", try s.text("binding7067"));
    try s.put(bindings, "CheckAnyOf", try s.text("binding7068"));
    try s.put(bindings, "ErrorAnyOf", try s.text("binding7069"));
}
fn body7070(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v7075 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding7071", v7075);
    const v7076 = if (args.len > 1) args[1] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding7072", v7076);
    const v7077 = if (args.len > 2) args[2] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding7073", v7077);
    const v7078 = if (args.len > 3) args[3] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding7074", v7078);
    const v7079 = try o.importValue(&s, graph, "schema/engine/_reducer.mjs", "Reducer");
    const v7080 = try o.lookup(&s, frame, "binding7071");
    const v7081 = try o.lookup(&s, frame, "binding7072");
    const v7082 = try o.lookup(&s, frame, "binding7073");
    const v7083 = try s.text("anyOf");
    const v7084 = try s.own(try js.getKey(e, v7082, v7083));
    const v7085 = try o.lookup(&s, frame, "binding7074");
    const v7086 = try o.importValue(&s, graph, "guard/index.mjs", "EmitGuard");
    const v7087 = try s.text("IsGreaterThan");
    const v7088 = try s.own(try js.getKey(e, v7086, v7087));
    const v7089 = try o.importValue(&s, graph, "guard/index.mjs", "EmitGuard");
    const v7090 = try s.text("Member");
    const v7091 = try s.own(try js.getKey(e, v7089, v7090));
    const v7092 = try s.text("results");
    const v7093 = try s.text("length");
    const v7094 = try s.call(v7091, v7089, &.{ v7092, v7093 });
    const v7095 = try o.importValue(&s, graph, "guard/index.mjs", "EmitGuard");
    const v7096 = try s.text("Constant");
    const v7097 = try s.own(try js.getKey(e, v7095, v7096));
    const v7098 = try s.call(v7097, v7095, &.{c.JS_NewFloat64(e.context, 0)});
    const v7099 = try s.call(v7088, v7086, &.{ v7094, v7098 });
    const v7100 = try s.call(v7079, c.pi_js_undefined(), &.{ v7080, v7081, v7084, v7085, v7099 });
    return c.JS_DupValue(e.context, v7100);
}
fn body7119(e: *Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    _ = try o.lookup(&s, frame, "@this");
    const v7122 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding7121", v7122);
    const v7123 = try o.importValue(&s, graph, "schema/engine/schema.mjs", "BuildSchema");
    const v7124 = try o.lookup(&s, frame, "binding7103");
    const v7125 = try o.lookup(&s, frame, "binding7104");
    const v7126 = try o.lookup(&s, frame, "binding7121");
    const v7127 = try o.lookup(&s, frame, "binding7106");
    const v7128 = try s.call(v7123, c.pi_js_undefined(), &.{ v7124, v7125, v7126, v7127 });
    return c.JS_DupValue(e.context, v7128);
}
fn body7119C(ctx: ?*c.JSContext, receiver: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const e = Engine.fromContext(ctx.?);
    return body7119(e, receiver, if (argc > 0) argv[0..@intCast(argc)] else &.{}, roots[0..2]) catch |err| sdk.fail(e, err);
}
fn body7102(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v7107 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding7103", v7107);
    const v7108 = if (args.len > 1) args[1] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding7104", v7108);
    const v7109 = if (args.len > 2) args[2] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding7105", v7109);
    const v7110 = if (args.len > 3) args[3] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding7106", v7110);
    const v7111 = try o.importValue(&s, graph, "guard/index.mjs", "EmitGuard");
    const v7112 = try s.text("ReduceOr");
    const v7113 = try s.own(try js.getKey(e, v7111, v7112));
    const v7114 = try o.lookup(&s, frame, "binding7105");
    const v7115 = try s.text("anyOf");
    const v7116 = try s.own(try js.getKey(e, v7114, v7115));
    const v7117 = try s.text("map");
    const v7118 = try s.own(try js.getKey(e, v7116, v7117));
    const v7129 = try o.arrow(&s, "", 1, body7119C, &.{ graph, frame });
    const v7130 = try s.call(v7118, v7116, &.{v7129});
    const v7131 = try s.call(v7113, v7111, &.{v7130});
    return c.JS_DupValue(e.context, v7131);
}
fn body7133(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    _ = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v7138 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding7134", v7138);
    const v7139 = if (args.len > 1) args[1] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding7135", v7139);
    const v7140 = if (args.len > 2) args[2] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding7136", v7140);
    const v7141 = if (args.len > 3) args[3] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding7137", v7141);
    const v7142 = try o.lookup(&s, frame, "binding7135");
    const v7143 = try s.text("UseUnevaluated");
    const v7144 = try s.own(try js.getKey(e, v7142, v7143));
    const v7145 = try s.call(v7144, v7142, &.{});
    const v7147 = conditional7146: {
        if (s.truthy(v7145)) {
            const v7148 = try o.lookup(&s, frame, "binding7065");
            const v7149 = try o.lookup(&s, frame, "binding7134");
            const v7150 = try o.lookup(&s, frame, "binding7135");
            const v7151 = try o.lookup(&s, frame, "binding7136");
            const v7152 = try o.lookup(&s, frame, "binding7137");
            const v7153 = try s.call(v7148, c.pi_js_undefined(), &.{ v7149, v7150, v7151, v7152 });
            break :conditional7146 v7153;
        } else {
            const v7154 = try o.lookup(&s, frame, "binding7066");
            const v7155 = try o.lookup(&s, frame, "binding7134");
            const v7156 = try o.lookup(&s, frame, "binding7135");
            const v7157 = try o.lookup(&s, frame, "binding7136");
            const v7158 = try o.lookup(&s, frame, "binding7137");
            const v7159 = try s.call(v7154, c.pi_js_undefined(), &.{ v7155, v7156, v7157, v7158 });
            break :conditional7146 v7159;
        }
    };
    return c.JS_DupValue(e.context, v7147);
}
fn body7177(e: *Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    _ = try o.lookup(&s, frame, "@this");
    const v7182 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding7179", v7182);
    const v7183 = if (args.len > 1) args[1] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding7180", v7183);
    const v7185 = try o.importValue(&s, graph, "schema/engine/_context.mjs", "CheckContext");
    const v7186 = try o.construct(&s, v7185, &.{});
    try o.assign(&s, frame, "binding7184", v7186);
    const v7187 = try o.importValue(&s, graph, "schema/engine/schema.mjs", "CheckSchema");
    const v7188 = try o.lookup(&s, frame, "binding7162");
    const v7189 = try o.lookup(&s, frame, "binding7184");
    const v7190 = try o.lookup(&s, frame, "binding7180");
    const v7191 = try o.lookup(&s, frame, "binding7165");
    const v7192 = try s.call(v7187, c.pi_js_undefined(), &.{ v7188, v7189, v7190, v7191 });
    const v7194 = conditional7193: {
        if (s.truthy(v7192)) {
            const v7195 = try s.array();
            const v7196 = try o.lookup(&s, frame, "binding7179");
            try o.spreadArray(&s, v7195, v7196);
            const v7197 = try o.lookup(&s, frame, "binding7184");
            try o.append(&s, v7195, v7197);
            break :conditional7193 v7195;
        } else {
            const v7198 = try o.lookup(&s, frame, "binding7179");
            break :conditional7193 v7198;
        }
    };
    return c.JS_DupValue(e.context, v7194);
}
fn body7177C(ctx: ?*c.JSContext, receiver: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const e = Engine.fromContext(ctx.?);
    return body7177(e, receiver, if (argc > 0) argv[0..@intCast(argc)] else &.{}, roots[0..2]) catch |err| sdk.fail(e, err);
}
fn body7161(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v7167 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding7162", v7167);
    const v7168 = if (args.len > 1) args[1] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding7163", v7168);
    const v7169 = if (args.len > 2) args[2] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding7164", v7169);
    const v7170 = if (args.len > 3) args[3] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding7165", v7170);
    const v7172 = try o.lookup(&s, frame, "binding7164");
    const v7173 = try s.text("anyOf");
    const v7174 = try s.own(try js.getKey(e, v7172, v7173));
    const v7175 = try s.text("reduce");
    const v7176 = try s.own(try js.getKey(e, v7174, v7175));
    const v7199 = try o.arrow(&s, "", 2, body7177C, &.{ graph, frame });
    const v7200 = try s.array();
    const v7201 = try s.call(v7176, v7174, &.{ v7199, v7200 });
    try o.assign(&s, frame, "binding7171", v7201);
    const v7202 = try o.importValue(&s, graph, "guard/index.mjs", "Guard");
    const v7203 = try s.text("IsGreaterThan");
    const v7204 = try s.own(try js.getKey(e, v7202, v7203));
    const v7205 = try o.lookup(&s, frame, "binding7171");
    const v7206 = try s.text("length");
    const v7207 = try s.own(try js.getKey(e, v7205, v7206));
    const v7208 = try s.call(v7204, v7202, &.{ v7207, c.JS_NewFloat64(e.context, 0) });
    const v7210 = logical7209: {
        if (!s.truthy(v7208)) break :logical7209 v7208;
        const v7211 = try o.lookup(&s, frame, "binding7163");
        const v7212 = try s.text("Merge");
        const v7213 = try s.own(try js.getKey(e, v7211, v7212));
        const v7214 = try o.lookup(&s, frame, "binding7171");
        const v7215 = try s.call(v7213, v7211, &.{v7214});
        break :logical7209 v7215;
    };
    return c.JS_DupValue(e.context, v7210);
}
fn body7242(e: *Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    _ = try o.lookup(&s, frame, "@this");
    const v7250 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding7244", v7250);
    const v7251 = if (args.len > 1) args[1] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding7245", v7251);
    const v7252 = if (args.len > 2) args[2] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding7246", v7252);
    const v7256 = try o.importValue(&s, graph, "schema/engine/_context.mjs", "ErrorContext");
    const v7257 = try o.construct(&s, v7256, &.{});
    try o.assign(&s, frame, "binding7253", v7257);
    const v7258 = try s.text("");
    const v7259 = try o.lookup(&s, frame, "binding7220");
    const v7260 = try s.stringify(v7259);
    const v7261 = try s.concat(v7258, v7260);
    const v7262 = try s.text("/anyOf/");
    const v7263 = try s.concat(v7261, v7262);
    const v7264 = try o.lookup(&s, frame, "binding7246");
    const v7265 = try s.stringify(v7264);
    const v7266 = try s.concat(v7263, v7265);
    const v7267 = try s.text("");
    const v7268 = try s.concat(v7266, v7267);
    try o.assign(&s, frame, "binding7254", v7268);
    const v7269 = try o.importValue(&s, graph, "schema/engine/schema.mjs", "ErrorSchema");
    const v7270 = try o.lookup(&s, frame, "binding7218");
    const v7271 = try o.lookup(&s, frame, "binding7253");
    const v7272 = try o.lookup(&s, frame, "binding7254");
    const v7273 = try o.lookup(&s, frame, "binding7221");
    const v7274 = try o.lookup(&s, frame, "binding7245");
    const v7275 = try o.lookup(&s, frame, "binding7223");
    const v7276 = try s.call(v7269, c.pi_js_undefined(), &.{ v7270, v7271, v7272, v7273, v7274, v7275 });
    try o.assign(&s, frame, "binding7255", v7276);
    const v7277 = try o.lookup(&s, frame, "binding7255");
    if (s.truthy(o.boolean(&s, !s.truthy(v7277)))) {
        const v7278 = try o.lookup(&s, frame, "binding7233");
        const v7279 = try s.text("push");
        const v7280 = try s.own(try js.getKey(e, v7278, v7279));
        const v7281 = try o.lookup(&s, frame, "binding7253");
        const v7282 = try s.call(v7280, v7278, &.{v7281});
        _ = v7282;
    }
    const v7283 = try o.lookup(&s, frame, "binding7255");
    const v7285 = conditional7284: {
        if (s.truthy(v7283)) {
            const v7286 = try s.array();
            const v7287 = try o.lookup(&s, frame, "binding7244");
            try o.spreadArray(&s, v7286, v7287);
            const v7288 = try o.lookup(&s, frame, "binding7253");
            try o.append(&s, v7286, v7288);
            break :conditional7284 v7286;
        } else {
            const v7289 = try o.lookup(&s, frame, "binding7244");
            break :conditional7284 v7289;
        }
    };
    return c.JS_DupValue(e.context, v7285);
}
fn body7242C(ctx: ?*c.JSContext, receiver: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const e = Engine.fromContext(ctx.?);
    return body7242(e, receiver, if (argc > 0) argv[0..@intCast(argc)] else &.{}, roots[0..2]) catch |err| sdk.fail(e, err);
}
fn body7321(e: *Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    _ = roots[0];
    const frame = try o.frame(&s, roots[1]);
    _ = try o.lookup(&s, frame, "@this");
    const v7324 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding7323", v7324);
    const v7325 = try o.lookup(&s, frame, "binding7219");
    const v7326 = try s.text("AddError");
    const v7327 = try s.own(try js.getKey(e, v7325, v7326));
    const v7328 = try o.lookup(&s, frame, "binding7323");
    const v7329 = try s.call(v7327, v7325, &.{v7328});
    return c.JS_DupValue(e.context, v7329);
}
fn body7321C(ctx: ?*c.JSContext, receiver: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const e = Engine.fromContext(ctx.?);
    return body7321(e, receiver, if (argc > 0) argv[0..@intCast(argc)] else &.{}, roots[0..2]) catch |err| sdk.fail(e, err);
}
fn body7311(e: *Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    _ = try o.lookup(&s, frame, "@this");
    const v7314 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding7313", v7314);
    const v7315 = try o.lookup(&s, frame, "binding7313");
    const v7316 = try s.text("GetErrors");
    const v7317 = try s.own(try js.getKey(e, v7315, v7316));
    const v7318 = try s.call(v7317, v7315, &.{});
    const v7319 = try s.text("forEach");
    const v7320 = try s.own(try js.getKey(e, v7318, v7319));
    const v7330 = try o.arrow(&s, "", 1, body7321C, &.{ graph, frame });
    const v7331 = try s.call(v7320, v7318, &.{v7330});
    return c.JS_DupValue(e.context, v7331);
}
fn body7311C(ctx: ?*c.JSContext, receiver: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const e = Engine.fromContext(ctx.?);
    return body7311(e, receiver, if (argc > 0) argv[0..@intCast(argc)] else &.{}, roots[0..2]) catch |err| sdk.fail(e, err);
}
fn body7217(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v7227 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding7218", v7227);
    const v7228 = if (args.len > 1) args[1] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding7219", v7228);
    const v7229 = if (args.len > 2) args[2] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding7220", v7229);
    const v7230 = if (args.len > 3) args[3] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding7221", v7230);
    const v7231 = if (args.len > 4) args[4] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding7222", v7231);
    const v7232 = if (args.len > 5) args[5] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding7223", v7232);
    const v7236 = try s.array();
    try o.assign(&s, frame, "binding7233", v7236);
    const v7237 = try o.lookup(&s, frame, "binding7222");
    const v7238 = try s.text("anyOf");
    const v7239 = try s.own(try js.getKey(e, v7237, v7238));
    const v7240 = try s.text("reduce");
    const v7241 = try s.own(try js.getKey(e, v7239, v7240));
    const v7290 = try o.arrow(&s, "", 3, body7242C, &.{ graph, frame });
    const v7291 = try s.array();
    const v7292 = try s.call(v7241, v7239, &.{ v7290, v7291 });
    try o.assign(&s, frame, "binding7234", v7292);
    const v7293 = try o.importValue(&s, graph, "guard/index.mjs", "Guard");
    const v7294 = try s.text("IsGreaterThan");
    const v7295 = try s.own(try js.getKey(e, v7293, v7294));
    const v7296 = try o.lookup(&s, frame, "binding7234");
    const v7297 = try s.text("length");
    const v7298 = try s.own(try js.getKey(e, v7296, v7297));
    const v7299 = try s.call(v7295, v7293, &.{ v7298, c.JS_NewFloat64(e.context, 0) });
    const v7301 = logical7300: {
        if (!s.truthy(v7299)) break :logical7300 v7299;
        const v7302 = try o.lookup(&s, frame, "binding7219");
        const v7303 = try s.text("Merge");
        const v7304 = try s.own(try js.getKey(e, v7302, v7303));
        const v7305 = try o.lookup(&s, frame, "binding7234");
        const v7306 = try s.call(v7304, v7302, &.{v7305});
        break :logical7300 v7306;
    };
    try o.assign(&s, frame, "binding7235", v7301);
    const v7307 = try o.lookup(&s, frame, "binding7235");
    if (s.truthy(o.boolean(&s, !s.truthy(v7307)))) {
        const v7308 = try o.lookup(&s, frame, "binding7233");
        const v7309 = try s.text("forEach");
        const v7310 = try s.own(try js.getKey(e, v7308, v7309));
        const v7332 = try o.arrow(&s, "", 1, body7311C, &.{ graph, frame });
        const v7333 = try s.call(v7310, v7308, &.{v7332});
        _ = v7333;
    }
    const v7334 = try o.lookup(&s, frame, "binding7235");
    const v7336 = logical7335: {
        if (s.truthy(v7334)) break :logical7335 v7334;
        const v7337 = try o.lookup(&s, frame, "binding7219");
        const v7338 = try s.text("AddError");
        const v7339 = try s.own(try js.getKey(e, v7337, v7338));
        const v7340 = try s.object();
        const v7341 = try s.text("keyword");
        const v7342 = try s.text("anyOf");
        try o.defineKey(&s, v7340, v7341, v7342);
        const v7343 = try s.text("schemaPath");
        const v7344 = try o.lookup(&s, frame, "binding7220");
        try o.defineKey(&s, v7340, v7343, v7344);
        const v7345 = try s.text("instancePath");
        const v7346 = try o.lookup(&s, frame, "binding7221");
        try o.defineKey(&s, v7340, v7345, v7346);
        const v7347 = try s.text("params");
        const v7348 = try s.object();
        try o.defineKey(&s, v7340, v7347, v7348);
        const v7349 = try s.call(v7339, v7337, &.{v7340});
        break :logical7335 v7349;
    };
    return c.JS_DupValue(e.context, v7336);
}
