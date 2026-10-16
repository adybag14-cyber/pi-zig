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
    const namespace = try s.get(modules, "schema/intern/intern.mjs");
    const frame = try o.frame(&s, c.pi_js_null());
    try s.put(frame, "@this", c.pi_js_undefined());
    try s.put(try s.get(graph, "frames"), "schema/intern/intern.mjs", frame);
    const bindings = try s.object();
    try s.put(try s.get(graph, "bindings"), "schema/intern/intern.mjs", bindings);
    const v18100 = try s.own(try ordinary.create(e, "UnsupportedKeyword", 1, body18089, &.{ graph, frame }));
    try o.assign(&s, frame, "binding18057", v18100);
    const v18112 = try s.own(try ordinary.create(e, "UnresolvableRef", 1, body18101, &.{ graph, frame }));
    try o.assign(&s, frame, "binding18058", v18112);
    const v18126 = try s.own(try ordinary.create(e, "HashKey", 1, body18113, &.{ graph, frame }));
    try o.assign(&s, frame, "binding18059", v18126);
    const v18138 = try s.own(try ordinary.create(e, "FromAdditionalItems", 2, body18127, &.{ graph, frame }));
    try o.assign(&s, frame, "binding18060", v18138);
    const v18150 = try s.own(try ordinary.create(e, "FromAdditionalProperties", 2, body18139, &.{ graph, frame }));
    try o.assign(&s, frame, "binding18061", v18150);
    const v18171 = try s.own(try ordinary.create(e, "FromAllOf", 2, body18151, &.{ graph, frame }));
    try o.assign(&s, frame, "binding18062", v18171);
    const v18192 = try s.own(try ordinary.create(e, "FromAnyOf", 2, body18172, &.{ graph, frame }));
    try o.assign(&s, frame, "binding18063", v18192);
    const v18204 = try s.own(try ordinary.create(e, "FromContains", 2, body18193, &.{ graph, frame }));
    try o.assign(&s, frame, "binding18064", v18204);
    const v18241 = try s.own(try ordinary.create(e, "FromDependentSchemas", 2, body18205, &.{ graph, frame }));
    try o.assign(&s, frame, "binding18065", v18241);
    const v18253 = try s.own(try ordinary.create(e, "FromElse", 2, body18242, &.{ graph, frame }));
    try o.assign(&s, frame, "binding18066", v18253);
    const v18265 = try s.own(try ordinary.create(e, "FromIf", 2, body18254, &.{ graph, frame }));
    try o.assign(&s, frame, "binding18067", v18265);
    const v18286 = try s.own(try ordinary.create(e, "FromItems", 2, body18266, &.{ graph, frame }));
    try o.assign(&s, frame, "binding18068", v18286);
    const v18307 = try s.own(try ordinary.create(e, "FromItemsSized", 2, body18287, &.{ graph, frame }));
    try o.assign(&s, frame, "binding18069", v18307);
    const v18319 = try s.own(try ordinary.create(e, "FromItemsUnsized", 2, body18308, &.{ graph, frame }));
    try o.assign(&s, frame, "binding18070", v18319);
    const v18331 = try s.own(try ordinary.create(e, "FromNot", 2, body18320, &.{ graph, frame }));
    try o.assign(&s, frame, "binding18071", v18331);
    const v18352 = try s.own(try ordinary.create(e, "FromOneOf", 2, body18332, &.{ graph, frame }));
    try o.assign(&s, frame, "binding18072", v18352);
    const v18389 = try s.own(try ordinary.create(e, "FromPatternProperties", 2, body18353, &.{ graph, frame }));
    try o.assign(&s, frame, "binding18073", v18389);
    const v18410 = try s.own(try ordinary.create(e, "FromPrefixItems", 2, body18390, &.{ graph, frame }));
    try o.assign(&s, frame, "binding18074", v18410);
    const v18447 = try s.own(try ordinary.create(e, "FromProperties", 2, body18411, &.{ graph, frame }));
    try o.assign(&s, frame, "binding18075", v18447);
    const v18459 = try s.own(try ordinary.create(e, "FromPropertyNames", 2, body18448, &.{ graph, frame }));
    try o.assign(&s, frame, "binding18076", v18459);
    const v18482 = try s.own(try ordinary.create(e, "ResolveRef", 3, body18460, &.{ graph, frame }));
    try o.assign(&s, frame, "binding18077", v18482);
    const v18531 = try s.own(try ordinary.create(e, "FromRef", 2, body18483, &.{ graph, frame }));
    try o.assign(&s, frame, "binding18078", v18531);
    const v18543 = try s.own(try ordinary.create(e, "FromThen", 2, body18532, &.{ graph, frame }));
    try o.assign(&s, frame, "binding18079", v18543);
    const v18555 = try s.own(try ordinary.create(e, "FromUnevaluatedItems", 2, body18544, &.{ graph, frame }));
    try o.assign(&s, frame, "binding18080", v18555);
    const v18567 = try s.own(try ordinary.create(e, "FromUnevaluatedProperties", 2, body18556, &.{ graph, frame }));
    try o.assign(&s, frame, "binding18081", v18567);
    const v18961 = try s.own(try ordinary.create(e, "FromSchemaObject", 2, body18568, &.{ graph, frame }));
    try o.assign(&s, frame, "binding18082", v18961);
    const v18995 = try s.own(try ordinary.create(e, "FromSchemaBoolean", 2, body18962, &.{ graph, frame }));
    try o.assign(&s, frame, "binding18083", v18995);
    const v19016 = try s.own(try ordinary.create(e, "FromSchema", 2, body18996, &.{ graph, frame }));
    try o.assign(&s, frame, "binding18084", v19016);
    const v19038 = try s.own(try ordinary.create(e, "BooleanEntry", 1, body19017, &.{ graph, frame }));
    try o.assign(&s, frame, "binding18085", v19038);
    const v19123 = try s.own(try ordinary.create(e, "Intern", 1, body19039, &.{ graph, frame }));
    try o.assign(&s, frame, "binding18088", v19123);
    const v19124 = try o.lookup(&s, frame, "binding18088");
    try s.put(namespace, "Intern", v19124);
    const v19125 = try s.global("Map");
    const v19126 = try o.construct(&s, v19125, &.{});
    try o.assign(&s, frame, "binding18086", v19126);
    const v19127 = try s.global("Map");
    const v19128 = try o.construct(&s, v19127, &.{});
    try o.assign(&s, frame, "binding18087", v19128);
    const v19129 = try o.lookup(&s, frame, "binding18088");
    try s.put(namespace, "Intern", v19129);
    try s.put(bindings, "Intern", try s.text("binding18088"));
}
fn body18089(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    _ = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v18091 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding18090", v18091);
    const v18092 = try s.global("Error");
    const v18093 = try s.text("UnsupportedKeyword '");
    const v18094 = try o.lookup(&s, frame, "binding18090");
    const v18095 = try s.stringify(v18094);
    const v18096 = try s.concat(v18093, v18095);
    const v18097 = try s.text("'");
    const v18098 = try s.concat(v18096, v18097);
    const v18099 = try s.call(v18092, c.pi_js_undefined(), &.{v18098});
    _ = c.JS_Throw(e.context, c.JS_DupValue(e.context, v18099));
    return js.capture(e);
}
fn body18101(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    _ = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v18103 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding18102", v18103);
    const v18104 = try s.global("Error");
    const v18105 = try s.text("UnresolvableRef '");
    const v18106 = try o.lookup(&s, frame, "binding18102");
    const v18107 = try s.stringify(v18106);
    const v18108 = try s.concat(v18105, v18107);
    const v18109 = try s.text("'");
    const v18110 = try s.concat(v18108, v18109);
    const v18111 = try s.call(v18104, c.pi_js_undefined(), &.{v18110});
    _ = c.JS_Throw(e.context, c.JS_DupValue(e.context, v18111));
    return js.capture(e);
}
fn body18113(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v18115 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding18114", v18115);
    const v18116 = try s.text("x-");
    const v18117 = try o.importValue(&s, graph, "system/index.mjs", "Hashing");
    const v18118 = try s.text("Hash");
    const v18119 = try s.own(try js.getKey(e, v18117, v18118));
    const v18120 = try o.lookup(&s, frame, "binding18114");
    const v18121 = try s.call(v18119, v18117, &.{v18120});
    const v18122 = try s.stringify(v18121);
    const v18123 = try s.concat(v18116, v18122);
    const v18124 = try s.text("");
    const v18125 = try s.concat(v18123, v18124);
    return c.JS_DupValue(e.context, v18125);
}
fn body18127(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    _ = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v18130 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding18128", v18130);
    const v18131 = if (args.len > 1) args[1] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding18129", v18131);
    const v18132 = try o.lookup(&s, frame, "binding18084");
    const v18133 = try o.lookup(&s, frame, "binding18128");
    const v18134 = try o.lookup(&s, frame, "binding18129");
    const v18135 = try s.text("additionalItems");
    const v18136 = try s.own(try js.getKey(e, v18134, v18135));
    const v18137 = try s.call(v18132, c.pi_js_undefined(), &.{ v18133, v18136 });
    return c.JS_DupValue(e.context, v18137);
}
fn body18139(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    _ = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v18142 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding18140", v18142);
    const v18143 = if (args.len > 1) args[1] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding18141", v18143);
    const v18144 = try o.lookup(&s, frame, "binding18084");
    const v18145 = try o.lookup(&s, frame, "binding18140");
    const v18146 = try o.lookup(&s, frame, "binding18141");
    const v18147 = try s.text("additionalProperties");
    const v18148 = try s.own(try js.getKey(e, v18146, v18147));
    const v18149 = try s.call(v18144, c.pi_js_undefined(), &.{ v18145, v18148 });
    return c.JS_DupValue(e.context, v18149);
}
fn body18161(e: *Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    _ = roots[0];
    const frame = try o.frame(&s, roots[1]);
    _ = try o.lookup(&s, frame, "@this");
    const v18164 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding18163", v18164);
    const v18165 = try o.lookup(&s, frame, "binding18084");
    const v18166 = try o.lookup(&s, frame, "binding18152");
    const v18167 = try o.lookup(&s, frame, "binding18163");
    const v18168 = try s.call(v18165, c.pi_js_undefined(), &.{ v18166, v18167 });
    return c.JS_DupValue(e.context, v18168);
}
fn body18161C(ctx: ?*c.JSContext, receiver: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const e = Engine.fromContext(ctx.?);
    return body18161(e, receiver, if (argc > 0) argv[0..@intCast(argc)] else &.{}, roots[0..2]) catch |err| sdk.fail(e, err);
}
fn body18151(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v18154 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding18152", v18154);
    const v18155 = if (args.len > 1) args[1] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding18153", v18155);
    const v18156 = try o.lookup(&s, frame, "binding18153");
    const v18157 = try s.text("allOf");
    const v18158 = try s.own(try js.getKey(e, v18156, v18157));
    const v18159 = try s.text("map");
    const v18160 = try s.own(try js.getKey(e, v18158, v18159));
    const v18169 = try o.arrow(&s, "", 1, body18161C, &.{ graph, frame });
    const v18170 = try s.call(v18160, v18158, &.{v18169});
    return c.JS_DupValue(e.context, v18170);
}
fn body18182(e: *Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    _ = roots[0];
    const frame = try o.frame(&s, roots[1]);
    _ = try o.lookup(&s, frame, "@this");
    const v18185 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding18184", v18185);
    const v18186 = try o.lookup(&s, frame, "binding18084");
    const v18187 = try o.lookup(&s, frame, "binding18173");
    const v18188 = try o.lookup(&s, frame, "binding18184");
    const v18189 = try s.call(v18186, c.pi_js_undefined(), &.{ v18187, v18188 });
    return c.JS_DupValue(e.context, v18189);
}
fn body18182C(ctx: ?*c.JSContext, receiver: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const e = Engine.fromContext(ctx.?);
    return body18182(e, receiver, if (argc > 0) argv[0..@intCast(argc)] else &.{}, roots[0..2]) catch |err| sdk.fail(e, err);
}
fn body18172(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v18175 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding18173", v18175);
    const v18176 = if (args.len > 1) args[1] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding18174", v18176);
    const v18177 = try o.lookup(&s, frame, "binding18174");
    const v18178 = try s.text("anyOf");
    const v18179 = try s.own(try js.getKey(e, v18177, v18178));
    const v18180 = try s.text("map");
    const v18181 = try s.own(try js.getKey(e, v18179, v18180));
    const v18190 = try o.arrow(&s, "", 1, body18182C, &.{ graph, frame });
    const v18191 = try s.call(v18181, v18179, &.{v18190});
    return c.JS_DupValue(e.context, v18191);
}
fn body18193(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    _ = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v18196 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding18194", v18196);
    const v18197 = if (args.len > 1) args[1] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding18195", v18197);
    const v18198 = try o.lookup(&s, frame, "binding18084");
    const v18199 = try o.lookup(&s, frame, "binding18194");
    const v18200 = try o.lookup(&s, frame, "binding18195");
    const v18201 = try s.text("contains");
    const v18202 = try s.own(try js.getKey(e, v18200, v18201));
    const v18203 = try s.call(v18198, c.pi_js_undefined(), &.{ v18199, v18202 });
    return c.JS_DupValue(e.context, v18203);
}
fn body18219(e: *Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    _ = roots[0];
    const frame = try o.frame(&s, roots[1]);
    _ = try o.lookup(&s, frame, "@this");
    const v18223 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding18221", v18223);
    const v18224 = if (args.len > 1) args[1] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding18222", v18224);
    const v18225 = try s.object();
    const v18226 = try o.lookup(&s, frame, "binding18221");
    try js.spreadInto(e, v18225, v18226);
    const v18227 = try o.lookup(&s, frame, "binding18222");
    const v18228 = try o.propertyKey(&s, v18227);
    const v18229 = try o.lookup(&s, frame, "binding18084");
    const v18230 = try o.lookup(&s, frame, "binding18206");
    const v18231 = try o.lookup(&s, frame, "binding18207");
    const v18232 = try s.text("dependentSchemas");
    const v18233 = try s.own(try js.getKey(e, v18231, v18232));
    const v18234 = try o.lookup(&s, frame, "binding18222");
    const v18235 = try o.propertyKey(&s, v18234);
    const v18236 = try s.own(try js.getKey(e, v18233, v18235));
    const v18237 = try s.call(v18229, c.pi_js_undefined(), &.{ v18230, v18236 });
    try o.defineKey(&s, v18225, v18228, v18237);
    return c.JS_DupValue(e.context, v18225);
}
fn body18219C(ctx: ?*c.JSContext, receiver: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const e = Engine.fromContext(ctx.?);
    return body18219(e, receiver, if (argc > 0) argv[0..@intCast(argc)] else &.{}, roots[0..2]) catch |err| sdk.fail(e, err);
}
fn body18205(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v18208 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding18206", v18208);
    const v18209 = if (args.len > 1) args[1] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding18207", v18209);
    const v18210 = try o.importValue(&s, graph, "guard/index.mjs", "Guard");
    const v18211 = try s.text("Keys");
    const v18212 = try s.own(try js.getKey(e, v18210, v18211));
    const v18213 = try o.lookup(&s, frame, "binding18207");
    const v18214 = try s.text("dependentSchemas");
    const v18215 = try s.own(try js.getKey(e, v18213, v18214));
    const v18216 = try s.call(v18212, v18210, &.{v18215});
    const v18217 = try s.text("reduce");
    const v18218 = try s.own(try js.getKey(e, v18216, v18217));
    const v18238 = try o.arrow(&s, "", 2, body18219C, &.{ graph, frame });
    const v18239 = try s.object();
    const v18240 = try s.call(v18218, v18216, &.{ v18238, v18239 });
    return c.JS_DupValue(e.context, v18240);
}
fn body18242(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    _ = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v18245 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding18243", v18245);
    const v18246 = if (args.len > 1) args[1] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding18244", v18246);
    const v18247 = try o.lookup(&s, frame, "binding18084");
    const v18248 = try o.lookup(&s, frame, "binding18243");
    const v18249 = try o.lookup(&s, frame, "binding18244");
    const v18250 = try s.text("else");
    const v18251 = try s.own(try js.getKey(e, v18249, v18250));
    const v18252 = try s.call(v18247, c.pi_js_undefined(), &.{ v18248, v18251 });
    return c.JS_DupValue(e.context, v18252);
}
fn body18254(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    _ = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v18257 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding18255", v18257);
    const v18258 = if (args.len > 1) args[1] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding18256", v18258);
    const v18259 = try o.lookup(&s, frame, "binding18084");
    const v18260 = try o.lookup(&s, frame, "binding18255");
    const v18261 = try o.lookup(&s, frame, "binding18256");
    const v18262 = try s.text("if");
    const v18263 = try s.own(try js.getKey(e, v18261, v18262));
    const v18264 = try s.call(v18259, c.pi_js_undefined(), &.{ v18260, v18263 });
    return c.JS_DupValue(e.context, v18264);
}
fn body18266(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v18269 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding18267", v18269);
    const v18270 = if (args.len > 1) args[1] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding18268", v18270);
    const v18271 = try o.importValue(&s, graph, "schema/types/index.mjs", "*");
    const v18272 = try s.text("IsItemsSized");
    const v18273 = try s.own(try js.getKey(e, v18271, v18272));
    const v18274 = try o.lookup(&s, frame, "binding18268");
    const v18275 = try s.call(v18273, v18271, &.{v18274});
    const v18277 = conditional18276: {
        if (s.truthy(v18275)) {
            const v18278 = try o.lookup(&s, frame, "binding18069");
            const v18279 = try o.lookup(&s, frame, "binding18267");
            const v18280 = try o.lookup(&s, frame, "binding18268");
            const v18281 = try s.call(v18278, c.pi_js_undefined(), &.{ v18279, v18280 });
            break :conditional18276 v18281;
        } else {
            const v18282 = try o.lookup(&s, frame, "binding18070");
            const v18283 = try o.lookup(&s, frame, "binding18267");
            const v18284 = try o.lookup(&s, frame, "binding18268");
            const v18285 = try s.call(v18282, c.pi_js_undefined(), &.{ v18283, v18284 });
            break :conditional18276 v18285;
        }
    };
    return c.JS_DupValue(e.context, v18277);
}
fn body18297(e: *Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    _ = roots[0];
    const frame = try o.frame(&s, roots[1]);
    _ = try o.lookup(&s, frame, "@this");
    const v18300 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding18299", v18300);
    const v18301 = try o.lookup(&s, frame, "binding18084");
    const v18302 = try o.lookup(&s, frame, "binding18288");
    const v18303 = try o.lookup(&s, frame, "binding18299");
    const v18304 = try s.call(v18301, c.pi_js_undefined(), &.{ v18302, v18303 });
    return c.JS_DupValue(e.context, v18304);
}
fn body18297C(ctx: ?*c.JSContext, receiver: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const e = Engine.fromContext(ctx.?);
    return body18297(e, receiver, if (argc > 0) argv[0..@intCast(argc)] else &.{}, roots[0..2]) catch |err| sdk.fail(e, err);
}
fn body18287(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v18290 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding18288", v18290);
    const v18291 = if (args.len > 1) args[1] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding18289", v18291);
    const v18292 = try o.lookup(&s, frame, "binding18289");
    const v18293 = try s.text("items");
    const v18294 = try s.own(try js.getKey(e, v18292, v18293));
    const v18295 = try s.text("map");
    const v18296 = try s.own(try js.getKey(e, v18294, v18295));
    const v18305 = try o.arrow(&s, "", 1, body18297C, &.{ graph, frame });
    const v18306 = try s.call(v18296, v18294, &.{v18305});
    return c.JS_DupValue(e.context, v18306);
}
fn body18308(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    _ = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v18311 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding18309", v18311);
    const v18312 = if (args.len > 1) args[1] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding18310", v18312);
    const v18313 = try o.lookup(&s, frame, "binding18084");
    const v18314 = try o.lookup(&s, frame, "binding18309");
    const v18315 = try o.lookup(&s, frame, "binding18310");
    const v18316 = try s.text("items");
    const v18317 = try s.own(try js.getKey(e, v18315, v18316));
    const v18318 = try s.call(v18313, c.pi_js_undefined(), &.{ v18314, v18317 });
    return c.JS_DupValue(e.context, v18318);
}
fn body18320(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    _ = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v18323 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding18321", v18323);
    const v18324 = if (args.len > 1) args[1] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding18322", v18324);
    const v18325 = try o.lookup(&s, frame, "binding18084");
    const v18326 = try o.lookup(&s, frame, "binding18321");
    const v18327 = try o.lookup(&s, frame, "binding18322");
    const v18328 = try s.text("not");
    const v18329 = try s.own(try js.getKey(e, v18327, v18328));
    const v18330 = try s.call(v18325, c.pi_js_undefined(), &.{ v18326, v18329 });
    return c.JS_DupValue(e.context, v18330);
}
fn body18342(e: *Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    _ = roots[0];
    const frame = try o.frame(&s, roots[1]);
    _ = try o.lookup(&s, frame, "@this");
    const v18345 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding18344", v18345);
    const v18346 = try o.lookup(&s, frame, "binding18084");
    const v18347 = try o.lookup(&s, frame, "binding18333");
    const v18348 = try o.lookup(&s, frame, "binding18344");
    const v18349 = try s.call(v18346, c.pi_js_undefined(), &.{ v18347, v18348 });
    return c.JS_DupValue(e.context, v18349);
}
fn body18342C(ctx: ?*c.JSContext, receiver: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const e = Engine.fromContext(ctx.?);
    return body18342(e, receiver, if (argc > 0) argv[0..@intCast(argc)] else &.{}, roots[0..2]) catch |err| sdk.fail(e, err);
}
fn body18332(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v18335 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding18333", v18335);
    const v18336 = if (args.len > 1) args[1] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding18334", v18336);
    const v18337 = try o.lookup(&s, frame, "binding18334");
    const v18338 = try s.text("oneOf");
    const v18339 = try s.own(try js.getKey(e, v18337, v18338));
    const v18340 = try s.text("map");
    const v18341 = try s.own(try js.getKey(e, v18339, v18340));
    const v18350 = try o.arrow(&s, "", 1, body18342C, &.{ graph, frame });
    const v18351 = try s.call(v18341, v18339, &.{v18350});
    return c.JS_DupValue(e.context, v18351);
}
fn body18367(e: *Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    _ = roots[0];
    const frame = try o.frame(&s, roots[1]);
    _ = try o.lookup(&s, frame, "@this");
    const v18371 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding18369", v18371);
    const v18372 = if (args.len > 1) args[1] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding18370", v18372);
    const v18373 = try s.object();
    const v18374 = try o.lookup(&s, frame, "binding18369");
    try js.spreadInto(e, v18373, v18374);
    const v18375 = try o.lookup(&s, frame, "binding18370");
    const v18376 = try o.propertyKey(&s, v18375);
    const v18377 = try o.lookup(&s, frame, "binding18084");
    const v18378 = try o.lookup(&s, frame, "binding18354");
    const v18379 = try o.lookup(&s, frame, "binding18355");
    const v18380 = try s.text("patternProperties");
    const v18381 = try s.own(try js.getKey(e, v18379, v18380));
    const v18382 = try o.lookup(&s, frame, "binding18370");
    const v18383 = try o.propertyKey(&s, v18382);
    const v18384 = try s.own(try js.getKey(e, v18381, v18383));
    const v18385 = try s.call(v18377, c.pi_js_undefined(), &.{ v18378, v18384 });
    try o.defineKey(&s, v18373, v18376, v18385);
    return c.JS_DupValue(e.context, v18373);
}
fn body18367C(ctx: ?*c.JSContext, receiver: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const e = Engine.fromContext(ctx.?);
    return body18367(e, receiver, if (argc > 0) argv[0..@intCast(argc)] else &.{}, roots[0..2]) catch |err| sdk.fail(e, err);
}
fn body18353(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v18356 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding18354", v18356);
    const v18357 = if (args.len > 1) args[1] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding18355", v18357);
    const v18358 = try o.importValue(&s, graph, "guard/index.mjs", "Guard");
    const v18359 = try s.text("Keys");
    const v18360 = try s.own(try js.getKey(e, v18358, v18359));
    const v18361 = try o.lookup(&s, frame, "binding18355");
    const v18362 = try s.text("patternProperties");
    const v18363 = try s.own(try js.getKey(e, v18361, v18362));
    const v18364 = try s.call(v18360, v18358, &.{v18363});
    const v18365 = try s.text("reduce");
    const v18366 = try s.own(try js.getKey(e, v18364, v18365));
    const v18386 = try o.arrow(&s, "", 2, body18367C, &.{ graph, frame });
    const v18387 = try s.object();
    const v18388 = try s.call(v18366, v18364, &.{ v18386, v18387 });
    return c.JS_DupValue(e.context, v18388);
}
fn body18400(e: *Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    _ = roots[0];
    const frame = try o.frame(&s, roots[1]);
    _ = try o.lookup(&s, frame, "@this");
    const v18403 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding18402", v18403);
    const v18404 = try o.lookup(&s, frame, "binding18084");
    const v18405 = try o.lookup(&s, frame, "binding18391");
    const v18406 = try o.lookup(&s, frame, "binding18402");
    const v18407 = try s.call(v18404, c.pi_js_undefined(), &.{ v18405, v18406 });
    return c.JS_DupValue(e.context, v18407);
}
fn body18400C(ctx: ?*c.JSContext, receiver: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const e = Engine.fromContext(ctx.?);
    return body18400(e, receiver, if (argc > 0) argv[0..@intCast(argc)] else &.{}, roots[0..2]) catch |err| sdk.fail(e, err);
}
fn body18390(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v18393 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding18391", v18393);
    const v18394 = if (args.len > 1) args[1] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding18392", v18394);
    const v18395 = try o.lookup(&s, frame, "binding18392");
    const v18396 = try s.text("prefixItems");
    const v18397 = try s.own(try js.getKey(e, v18395, v18396));
    const v18398 = try s.text("map");
    const v18399 = try s.own(try js.getKey(e, v18397, v18398));
    const v18408 = try o.arrow(&s, "", 1, body18400C, &.{ graph, frame });
    const v18409 = try s.call(v18399, v18397, &.{v18408});
    return c.JS_DupValue(e.context, v18409);
}
fn body18425(e: *Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    _ = roots[0];
    const frame = try o.frame(&s, roots[1]);
    _ = try o.lookup(&s, frame, "@this");
    const v18429 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding18427", v18429);
    const v18430 = if (args.len > 1) args[1] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding18428", v18430);
    const v18431 = try s.object();
    const v18432 = try o.lookup(&s, frame, "binding18427");
    try js.spreadInto(e, v18431, v18432);
    const v18433 = try o.lookup(&s, frame, "binding18428");
    const v18434 = try o.propertyKey(&s, v18433);
    const v18435 = try o.lookup(&s, frame, "binding18084");
    const v18436 = try o.lookup(&s, frame, "binding18412");
    const v18437 = try o.lookup(&s, frame, "binding18413");
    const v18438 = try s.text("properties");
    const v18439 = try s.own(try js.getKey(e, v18437, v18438));
    const v18440 = try o.lookup(&s, frame, "binding18428");
    const v18441 = try o.propertyKey(&s, v18440);
    const v18442 = try s.own(try js.getKey(e, v18439, v18441));
    const v18443 = try s.call(v18435, c.pi_js_undefined(), &.{ v18436, v18442 });
    try o.defineKey(&s, v18431, v18434, v18443);
    return c.JS_DupValue(e.context, v18431);
}
fn body18425C(ctx: ?*c.JSContext, receiver: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const e = Engine.fromContext(ctx.?);
    return body18425(e, receiver, if (argc > 0) argv[0..@intCast(argc)] else &.{}, roots[0..2]) catch |err| sdk.fail(e, err);
}
fn body18411(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v18414 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding18412", v18414);
    const v18415 = if (args.len > 1) args[1] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding18413", v18415);
    const v18416 = try o.importValue(&s, graph, "guard/index.mjs", "Guard");
    const v18417 = try s.text("Keys");
    const v18418 = try s.own(try js.getKey(e, v18416, v18417));
    const v18419 = try o.lookup(&s, frame, "binding18413");
    const v18420 = try s.text("properties");
    const v18421 = try s.own(try js.getKey(e, v18419, v18420));
    const v18422 = try s.call(v18418, v18416, &.{v18421});
    const v18423 = try s.text("reduce");
    const v18424 = try s.own(try js.getKey(e, v18422, v18423));
    const v18444 = try o.arrow(&s, "", 2, body18425C, &.{ graph, frame });
    const v18445 = try s.object();
    const v18446 = try s.call(v18424, v18422, &.{ v18444, v18445 });
    return c.JS_DupValue(e.context, v18446);
}
fn body18448(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    _ = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v18451 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding18449", v18451);
    const v18452 = if (args.len > 1) args[1] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding18450", v18452);
    const v18453 = try o.lookup(&s, frame, "binding18084");
    const v18454 = try o.lookup(&s, frame, "binding18449");
    const v18455 = try o.lookup(&s, frame, "binding18450");
    const v18456 = try s.text("propertyNames");
    const v18457 = try s.own(try js.getKey(e, v18455, v18456));
    const v18458 = try s.call(v18453, c.pi_js_undefined(), &.{ v18454, v18457 });
    return c.JS_DupValue(e.context, v18458);
}
fn body18460(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v18464 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding18461", v18464);
    const v18465 = if (args.len > 1) args[1] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding18462", v18465);
    const v18466 = if (args.len > 2) args[2] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding18463", v18466);
    const v18467 = try o.importValue(&s, graph, "schema/resolve/index.mjs", "Resolve");
    const v18468 = try s.text("Ref");
    const v18469 = try s.own(try js.getKey(e, v18467, v18468));
    const v18470 = try o.lookup(&s, frame, "binding18461");
    const v18471 = try o.lookup(&s, frame, "binding18462");
    const v18472 = try o.importValue(&s, graph, "schema/resolve/index.mjs", "Resolve");
    const v18473 = try s.text("DefaultBase");
    const v18474 = try s.own(try js.getKey(e, v18472, v18473));
    const v18475 = try o.lookup(&s, frame, "binding18463");
    const v18476 = try s.call(v18469, v18467, &.{ v18470, v18471, v18474, v18475 });
    const v18478 = logical18477: {
        if (!c.JS_IsNull(v18476) and !c.JS_IsUndefined(v18476)) break :logical18477 v18476;
        const v18479 = try o.lookup(&s, frame, "binding18058");
        const v18480 = try o.lookup(&s, frame, "binding18463");
        const v18481 = try s.call(v18479, c.pi_js_undefined(), &.{v18480});
        break :logical18477 v18481;
    };
    return c.JS_DupValue(e.context, v18478);
}
fn body18483(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v18488 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding18484", v18488);
    const v18489 = if (args.len > 1) args[1] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding18485", v18489);
    const v18492 = try o.lookup(&s, frame, "binding18077");
    const v18493 = try o.lookup(&s, frame, "binding18484");
    const v18494 = try s.text("context");
    const v18495 = try s.own(try js.getKey(e, v18493, v18494));
    const v18496 = try o.lookup(&s, frame, "binding18484");
    const v18497 = try s.text("schema");
    const v18498 = try s.own(try js.getKey(e, v18496, v18497));
    const v18499 = try o.lookup(&s, frame, "binding18485");
    const v18500 = try s.text("$ref");
    const v18501 = try s.own(try js.getKey(e, v18499, v18500));
    const v18502 = try s.call(v18492, c.pi_js_undefined(), &.{ v18495, v18498, v18501 });
    try o.assign(&s, frame, "binding18490", v18502);
    const v18503 = try o.lookup(&s, frame, "binding18484");
    const v18504 = try s.text("resolving");
    const v18505 = try s.own(try js.getKey(e, v18503, v18504));
    const v18506 = try s.text("get");
    const v18507 = try s.own(try js.getKey(e, v18505, v18506));
    const v18508 = try o.lookup(&s, frame, "binding18490");
    const v18509 = try s.call(v18507, v18505, &.{v18508});
    try o.assign(&s, frame, "binding18491", v18509);
    const v18510 = try o.importValue(&s, graph, "guard/index.mjs", "Guard");
    const v18511 = try s.text("IsUndefined");
    const v18512 = try s.own(try js.getKey(e, v18510, v18511));
    const v18513 = try o.lookup(&s, frame, "binding18491");
    const v18514 = try s.call(v18512, v18510, &.{v18513});
    if (s.truthy(v18514)) {
        const v18515 = try o.lookup(&s, frame, "binding18084");
        const v18516 = try o.lookup(&s, frame, "binding18484");
        const v18517 = try o.lookup(&s, frame, "binding18490");
        const v18518 = try s.call(v18515, c.pi_js_undefined(), &.{ v18516, v18517 });
        return c.JS_DupValue(e.context, v18518);
    }
    const v18519 = try o.lookup(&s, frame, "binding18491");
    const v18520 = try s.text("used");
    try js.setKey(e, v18519, v18520, o.boolean(&s, true));
    _ = o.boolean(&s, true);
    const v18521 = try s.object();
    const v18522 = try s.text("$ref");
    const v18523 = try s.text("#/$defs/");
    const v18524 = try o.lookup(&s, frame, "binding18491");
    const v18525 = try s.text("key");
    const v18526 = try s.own(try js.getKey(e, v18524, v18525));
    const v18527 = try s.stringify(v18526);
    const v18528 = try s.concat(v18523, v18527);
    const v18529 = try s.text("");
    const v18530 = try s.concat(v18528, v18529);
    try o.defineKey(&s, v18521, v18522, v18530);
    return c.JS_DupValue(e.context, v18521);
}
fn body18532(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    _ = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v18535 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding18533", v18535);
    const v18536 = if (args.len > 1) args[1] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding18534", v18536);
    const v18537 = try o.lookup(&s, frame, "binding18084");
    const v18538 = try o.lookup(&s, frame, "binding18533");
    const v18539 = try o.lookup(&s, frame, "binding18534");
    const v18540 = try s.text("then");
    const v18541 = try s.own(try js.getKey(e, v18539, v18540));
    const v18542 = try s.call(v18537, c.pi_js_undefined(), &.{ v18538, v18541 });
    return c.JS_DupValue(e.context, v18542);
}
fn body18544(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    _ = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v18547 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding18545", v18547);
    const v18548 = if (args.len > 1) args[1] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding18546", v18548);
    const v18549 = try o.lookup(&s, frame, "binding18084");
    const v18550 = try o.lookup(&s, frame, "binding18545");
    const v18551 = try o.lookup(&s, frame, "binding18546");
    const v18552 = try s.text("unevaluatedItems");
    const v18553 = try s.own(try js.getKey(e, v18551, v18552));
    const v18554 = try s.call(v18549, c.pi_js_undefined(), &.{ v18550, v18553 });
    return c.JS_DupValue(e.context, v18554);
}
fn body18556(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    _ = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v18559 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding18557", v18559);
    const v18560 = if (args.len > 1) args[1] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding18558", v18560);
    const v18561 = try o.lookup(&s, frame, "binding18084");
    const v18562 = try o.lookup(&s, frame, "binding18557");
    const v18563 = try o.lookup(&s, frame, "binding18558");
    const v18564 = try s.text("unevaluatedProperties");
    const v18565 = try s.own(try js.getKey(e, v18563, v18564));
    const v18566 = try s.call(v18561, c.pi_js_undefined(), &.{ v18562, v18565 });
    return c.JS_DupValue(e.context, v18566);
}
fn body18568(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v18577 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding18569", v18577);
    const v18578 = if (args.len > 1) args[1] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding18570", v18578);
    const v18585 = try o.importValue(&s, graph, "schema/types/index.mjs", "*");
    const v18586 = try s.text("IsRef");
    const v18587 = try s.own(try js.getKey(e, v18585, v18586));
    const v18588 = try o.lookup(&s, frame, "binding18570");
    const v18589 = try s.call(v18587, v18585, &.{v18588});
    if (s.truthy(v18589)) {
        const v18590 = try o.lookup(&s, frame, "binding18078");
        const v18591 = try o.lookup(&s, frame, "binding18569");
        const v18592 = try o.lookup(&s, frame, "binding18570");
        const v18593 = try s.call(v18590, c.pi_js_undefined(), &.{ v18591, v18592 });
        return c.JS_DupValue(e.context, v18593);
    }
    const v18594 = try o.lookup(&s, frame, "binding18087");
    const v18595 = try s.text("get");
    const v18596 = try s.own(try js.getKey(e, v18594, v18595));
    const v18597 = try o.lookup(&s, frame, "binding18570");
    const v18598 = try s.call(v18596, v18594, &.{v18597});
    try o.assign(&s, frame, "binding18579", v18598);
    const v18599 = try o.importValue(&s, graph, "guard/index.mjs", "Guard");
    const v18600 = try s.text("IsUndefined");
    const v18601 = try s.own(try js.getKey(e, v18599, v18600));
    const v18602 = try o.lookup(&s, frame, "binding18579");
    const v18603 = try s.call(v18601, v18599, &.{v18602});
    if (s.truthy(o.boolean(&s, !s.truthy(v18603)))) {
        const v18604 = try o.lookup(&s, frame, "binding18579");
        return c.JS_DupValue(e.context, v18604);
    }
    const v18605 = try o.importValue(&s, graph, "schema/types/index.mjs", "*");
    const v18606 = try s.text("IsDynamicRef");
    const v18607 = try s.own(try js.getKey(e, v18605, v18606));
    const v18608 = try o.lookup(&s, frame, "binding18570");
    const v18609 = try s.call(v18607, v18605, &.{v18608});
    if (s.truthy(v18609)) {
        const v18610 = try o.lookup(&s, frame, "binding18057");
        const v18611 = try s.text("$dynamicRef");
        const v18612 = try s.call(v18610, c.pi_js_undefined(), &.{v18611});
        _ = v18612;
    }
    const v18613 = try o.importValue(&s, graph, "schema/types/index.mjs", "*");
    const v18614 = try s.text("IsRecursiveRef");
    const v18615 = try s.own(try js.getKey(e, v18613, v18614));
    const v18616 = try o.lookup(&s, frame, "binding18570");
    const v18617 = try s.call(v18615, v18613, &.{v18616});
    if (s.truthy(v18617)) {
        const v18618 = try o.lookup(&s, frame, "binding18057");
        const v18619 = try s.text("$recursiveRef");
        const v18620 = try s.call(v18618, c.pi_js_undefined(), &.{v18619});
        _ = v18620;
    }
    const v18621 = try s.object();
    const v18622 = try s.text("key");
    const v18623 = try s.text("x-ref-");
    const v18624 = try o.lookup(&s, frame, "binding18569");
    const v18625 = try s.text("resolving");
    const v18626 = try s.own(try js.getKey(e, v18624, v18625));
    const v18627 = try s.text("size");
    const v18628 = try s.own(try js.getKey(e, v18626, v18627));
    const v18629 = try s.stringify(v18628);
    const v18630 = try s.concat(v18623, v18629);
    const v18631 = try s.text("");
    const v18632 = try s.concat(v18630, v18631);
    try o.defineKey(&s, v18621, v18622, v18632);
    const v18633 = try s.text("used");
    try o.defineKey(&s, v18621, v18633, o.boolean(&s, false));
    try o.assign(&s, frame, "binding18580", v18621);
    const v18634 = try o.lookup(&s, frame, "binding18569");
    const v18635 = try s.text("resolving");
    const v18636 = try s.own(try js.getKey(e, v18634, v18635));
    const v18637 = try s.text("set");
    const v18638 = try s.own(try js.getKey(e, v18636, v18637));
    const v18639 = try o.lookup(&s, frame, "binding18570");
    const v18640 = try o.lookup(&s, frame, "binding18580");
    const v18641 = try s.call(v18638, v18636, &.{ v18639, v18640 });
    _ = v18641;
    const v18642 = try s.object();
    const v18643 = try o.importValue(&s, graph, "schema/types/index.mjs", "*");
    const v18644 = try s.text("IsRefine");
    const v18645 = try s.own(try js.getKey(e, v18643, v18644));
    const v18646 = try o.lookup(&s, frame, "binding18570");
    const v18647 = try s.call(v18645, v18643, &.{v18646});
    const v18649 = conditional18648: {
        if (s.truthy(v18647)) {
            const v18650 = try s.object();
            const v18651 = try s.text("~refine");
            const v18652 = try o.propertyKey(&s, v18651);
            const v18653 = try o.lookup(&s, frame, "binding18570");
            const v18654 = try s.text("~refine");
            const v18655 = try o.propertyKey(&s, v18654);
            const v18656 = try s.own(try js.getKey(e, v18653, v18655));
            try o.defineKey(&s, v18650, v18652, v18656);
            break :conditional18648 v18650;
        } else {
            const v18657 = try s.object();
            break :conditional18648 v18657;
        }
    };
    try js.spreadInto(e, v18642, v18649);
    const v18658 = try o.importValue(&s, graph, "schema/types/index.mjs", "*");
    const v18659 = try s.text("IsAdditionalItems");
    const v18660 = try s.own(try js.getKey(e, v18658, v18659));
    const v18661 = try o.lookup(&s, frame, "binding18570");
    const v18662 = try s.call(v18660, v18658, &.{v18661});
    const v18664 = conditional18663: {
        if (s.truthy(v18662)) {
            const v18665 = try s.object();
            const v18666 = try s.text("additionalItems");
            const v18667 = try o.lookup(&s, frame, "binding18060");
            const v18668 = try o.lookup(&s, frame, "binding18569");
            const v18669 = try o.lookup(&s, frame, "binding18570");
            const v18670 = try s.call(v18667, c.pi_js_undefined(), &.{ v18668, v18669 });
            try o.defineKey(&s, v18665, v18666, v18670);
            break :conditional18663 v18665;
        } else {
            const v18671 = try s.object();
            break :conditional18663 v18671;
        }
    };
    try js.spreadInto(e, v18642, v18664);
    const v18672 = try o.importValue(&s, graph, "schema/types/index.mjs", "*");
    const v18673 = try s.text("IsAdditionalProperties");
    const v18674 = try s.own(try js.getKey(e, v18672, v18673));
    const v18675 = try o.lookup(&s, frame, "binding18570");
    const v18676 = try s.call(v18674, v18672, &.{v18675});
    const v18678 = conditional18677: {
        if (s.truthy(v18676)) {
            const v18679 = try s.object();
            const v18680 = try s.text("additionalProperties");
            const v18681 = try o.lookup(&s, frame, "binding18061");
            const v18682 = try o.lookup(&s, frame, "binding18569");
            const v18683 = try o.lookup(&s, frame, "binding18570");
            const v18684 = try s.call(v18681, c.pi_js_undefined(), &.{ v18682, v18683 });
            try o.defineKey(&s, v18679, v18680, v18684);
            break :conditional18677 v18679;
        } else {
            const v18685 = try s.object();
            break :conditional18677 v18685;
        }
    };
    try js.spreadInto(e, v18642, v18678);
    const v18686 = try o.importValue(&s, graph, "schema/types/index.mjs", "*");
    const v18687 = try s.text("IsAllOf");
    const v18688 = try s.own(try js.getKey(e, v18686, v18687));
    const v18689 = try o.lookup(&s, frame, "binding18570");
    const v18690 = try s.call(v18688, v18686, &.{v18689});
    const v18692 = conditional18691: {
        if (s.truthy(v18690)) {
            const v18693 = try s.object();
            const v18694 = try s.text("allOf");
            const v18695 = try o.lookup(&s, frame, "binding18062");
            const v18696 = try o.lookup(&s, frame, "binding18569");
            const v18697 = try o.lookup(&s, frame, "binding18570");
            const v18698 = try s.call(v18695, c.pi_js_undefined(), &.{ v18696, v18697 });
            try o.defineKey(&s, v18693, v18694, v18698);
            break :conditional18691 v18693;
        } else {
            const v18699 = try s.object();
            break :conditional18691 v18699;
        }
    };
    try js.spreadInto(e, v18642, v18692);
    const v18700 = try o.importValue(&s, graph, "schema/types/index.mjs", "*");
    const v18701 = try s.text("IsAnyOf");
    const v18702 = try s.own(try js.getKey(e, v18700, v18701));
    const v18703 = try o.lookup(&s, frame, "binding18570");
    const v18704 = try s.call(v18702, v18700, &.{v18703});
    const v18706 = conditional18705: {
        if (s.truthy(v18704)) {
            const v18707 = try s.object();
            const v18708 = try s.text("anyOf");
            const v18709 = try o.lookup(&s, frame, "binding18063");
            const v18710 = try o.lookup(&s, frame, "binding18569");
            const v18711 = try o.lookup(&s, frame, "binding18570");
            const v18712 = try s.call(v18709, c.pi_js_undefined(), &.{ v18710, v18711 });
            try o.defineKey(&s, v18707, v18708, v18712);
            break :conditional18705 v18707;
        } else {
            const v18713 = try s.object();
            break :conditional18705 v18713;
        }
    };
    try js.spreadInto(e, v18642, v18706);
    const v18714 = try o.importValue(&s, graph, "schema/types/index.mjs", "*");
    const v18715 = try s.text("IsContains");
    const v18716 = try s.own(try js.getKey(e, v18714, v18715));
    const v18717 = try o.lookup(&s, frame, "binding18570");
    const v18718 = try s.call(v18716, v18714, &.{v18717});
    const v18720 = conditional18719: {
        if (s.truthy(v18718)) {
            const v18721 = try s.object();
            const v18722 = try s.text("contains");
            const v18723 = try o.lookup(&s, frame, "binding18064");
            const v18724 = try o.lookup(&s, frame, "binding18569");
            const v18725 = try o.lookup(&s, frame, "binding18570");
            const v18726 = try s.call(v18723, c.pi_js_undefined(), &.{ v18724, v18725 });
            try o.defineKey(&s, v18721, v18722, v18726);
            break :conditional18719 v18721;
        } else {
            const v18727 = try s.object();
            break :conditional18719 v18727;
        }
    };
    try js.spreadInto(e, v18642, v18720);
    const v18728 = try o.importValue(&s, graph, "schema/types/index.mjs", "*");
    const v18729 = try s.text("IsDependentSchemas");
    const v18730 = try s.own(try js.getKey(e, v18728, v18729));
    const v18731 = try o.lookup(&s, frame, "binding18570");
    const v18732 = try s.call(v18730, v18728, &.{v18731});
    const v18734 = conditional18733: {
        if (s.truthy(v18732)) {
            const v18735 = try s.object();
            const v18736 = try s.text("dependentSchemas");
            const v18737 = try o.lookup(&s, frame, "binding18065");
            const v18738 = try o.lookup(&s, frame, "binding18569");
            const v18739 = try o.lookup(&s, frame, "binding18570");
            const v18740 = try s.call(v18737, c.pi_js_undefined(), &.{ v18738, v18739 });
            try o.defineKey(&s, v18735, v18736, v18740);
            break :conditional18733 v18735;
        } else {
            const v18741 = try s.object();
            break :conditional18733 v18741;
        }
    };
    try js.spreadInto(e, v18642, v18734);
    const v18742 = try o.importValue(&s, graph, "schema/types/index.mjs", "*");
    const v18743 = try s.text("IsElse");
    const v18744 = try s.own(try js.getKey(e, v18742, v18743));
    const v18745 = try o.lookup(&s, frame, "binding18570");
    const v18746 = try s.call(v18744, v18742, &.{v18745});
    const v18748 = conditional18747: {
        if (s.truthy(v18746)) {
            const v18749 = try s.object();
            const v18750 = try s.text("else");
            const v18751 = try o.lookup(&s, frame, "binding18066");
            const v18752 = try o.lookup(&s, frame, "binding18569");
            const v18753 = try o.lookup(&s, frame, "binding18570");
            const v18754 = try s.call(v18751, c.pi_js_undefined(), &.{ v18752, v18753 });
            try o.defineKey(&s, v18749, v18750, v18754);
            break :conditional18747 v18749;
        } else {
            const v18755 = try s.object();
            break :conditional18747 v18755;
        }
    };
    try js.spreadInto(e, v18642, v18748);
    const v18756 = try o.importValue(&s, graph, "schema/types/index.mjs", "*");
    const v18757 = try s.text("IsIf");
    const v18758 = try s.own(try js.getKey(e, v18756, v18757));
    const v18759 = try o.lookup(&s, frame, "binding18570");
    const v18760 = try s.call(v18758, v18756, &.{v18759});
    const v18762 = conditional18761: {
        if (s.truthy(v18760)) {
            const v18763 = try s.object();
            const v18764 = try s.text("if");
            const v18765 = try o.lookup(&s, frame, "binding18067");
            const v18766 = try o.lookup(&s, frame, "binding18569");
            const v18767 = try o.lookup(&s, frame, "binding18570");
            const v18768 = try s.call(v18765, c.pi_js_undefined(), &.{ v18766, v18767 });
            try o.defineKey(&s, v18763, v18764, v18768);
            break :conditional18761 v18763;
        } else {
            const v18769 = try s.object();
            break :conditional18761 v18769;
        }
    };
    try js.spreadInto(e, v18642, v18762);
    const v18770 = try o.importValue(&s, graph, "schema/types/index.mjs", "*");
    const v18771 = try s.text("IsItems");
    const v18772 = try s.own(try js.getKey(e, v18770, v18771));
    const v18773 = try o.lookup(&s, frame, "binding18570");
    const v18774 = try s.call(v18772, v18770, &.{v18773});
    const v18776 = conditional18775: {
        if (s.truthy(v18774)) {
            const v18777 = try s.object();
            const v18778 = try s.text("items");
            const v18779 = try o.lookup(&s, frame, "binding18068");
            const v18780 = try o.lookup(&s, frame, "binding18569");
            const v18781 = try o.lookup(&s, frame, "binding18570");
            const v18782 = try s.call(v18779, c.pi_js_undefined(), &.{ v18780, v18781 });
            try o.defineKey(&s, v18777, v18778, v18782);
            break :conditional18775 v18777;
        } else {
            const v18783 = try s.object();
            break :conditional18775 v18783;
        }
    };
    try js.spreadInto(e, v18642, v18776);
    const v18784 = try o.importValue(&s, graph, "schema/types/index.mjs", "*");
    const v18785 = try s.text("IsNot");
    const v18786 = try s.own(try js.getKey(e, v18784, v18785));
    const v18787 = try o.lookup(&s, frame, "binding18570");
    const v18788 = try s.call(v18786, v18784, &.{v18787});
    const v18790 = conditional18789: {
        if (s.truthy(v18788)) {
            const v18791 = try s.object();
            const v18792 = try s.text("not");
            const v18793 = try o.lookup(&s, frame, "binding18071");
            const v18794 = try o.lookup(&s, frame, "binding18569");
            const v18795 = try o.lookup(&s, frame, "binding18570");
            const v18796 = try s.call(v18793, c.pi_js_undefined(), &.{ v18794, v18795 });
            try o.defineKey(&s, v18791, v18792, v18796);
            break :conditional18789 v18791;
        } else {
            const v18797 = try s.object();
            break :conditional18789 v18797;
        }
    };
    try js.spreadInto(e, v18642, v18790);
    const v18798 = try o.importValue(&s, graph, "schema/types/index.mjs", "*");
    const v18799 = try s.text("IsOneOf");
    const v18800 = try s.own(try js.getKey(e, v18798, v18799));
    const v18801 = try o.lookup(&s, frame, "binding18570");
    const v18802 = try s.call(v18800, v18798, &.{v18801});
    const v18804 = conditional18803: {
        if (s.truthy(v18802)) {
            const v18805 = try s.object();
            const v18806 = try s.text("oneOf");
            const v18807 = try o.lookup(&s, frame, "binding18072");
            const v18808 = try o.lookup(&s, frame, "binding18569");
            const v18809 = try o.lookup(&s, frame, "binding18570");
            const v18810 = try s.call(v18807, c.pi_js_undefined(), &.{ v18808, v18809 });
            try o.defineKey(&s, v18805, v18806, v18810);
            break :conditional18803 v18805;
        } else {
            const v18811 = try s.object();
            break :conditional18803 v18811;
        }
    };
    try js.spreadInto(e, v18642, v18804);
    const v18812 = try o.importValue(&s, graph, "schema/types/index.mjs", "*");
    const v18813 = try s.text("IsPatternProperties");
    const v18814 = try s.own(try js.getKey(e, v18812, v18813));
    const v18815 = try o.lookup(&s, frame, "binding18570");
    const v18816 = try s.call(v18814, v18812, &.{v18815});
    const v18818 = conditional18817: {
        if (s.truthy(v18816)) {
            const v18819 = try s.object();
            const v18820 = try s.text("patternProperties");
            const v18821 = try o.lookup(&s, frame, "binding18073");
            const v18822 = try o.lookup(&s, frame, "binding18569");
            const v18823 = try o.lookup(&s, frame, "binding18570");
            const v18824 = try s.call(v18821, c.pi_js_undefined(), &.{ v18822, v18823 });
            try o.defineKey(&s, v18819, v18820, v18824);
            break :conditional18817 v18819;
        } else {
            const v18825 = try s.object();
            break :conditional18817 v18825;
        }
    };
    try js.spreadInto(e, v18642, v18818);
    const v18826 = try o.importValue(&s, graph, "schema/types/index.mjs", "*");
    const v18827 = try s.text("IsPrefixItems");
    const v18828 = try s.own(try js.getKey(e, v18826, v18827));
    const v18829 = try o.lookup(&s, frame, "binding18570");
    const v18830 = try s.call(v18828, v18826, &.{v18829});
    const v18832 = conditional18831: {
        if (s.truthy(v18830)) {
            const v18833 = try s.object();
            const v18834 = try s.text("prefixItems");
            const v18835 = try o.lookup(&s, frame, "binding18074");
            const v18836 = try o.lookup(&s, frame, "binding18569");
            const v18837 = try o.lookup(&s, frame, "binding18570");
            const v18838 = try s.call(v18835, c.pi_js_undefined(), &.{ v18836, v18837 });
            try o.defineKey(&s, v18833, v18834, v18838);
            break :conditional18831 v18833;
        } else {
            const v18839 = try s.object();
            break :conditional18831 v18839;
        }
    };
    try js.spreadInto(e, v18642, v18832);
    const v18840 = try o.importValue(&s, graph, "schema/types/index.mjs", "*");
    const v18841 = try s.text("IsProperties");
    const v18842 = try s.own(try js.getKey(e, v18840, v18841));
    const v18843 = try o.lookup(&s, frame, "binding18570");
    const v18844 = try s.call(v18842, v18840, &.{v18843});
    const v18846 = conditional18845: {
        if (s.truthy(v18844)) {
            const v18847 = try s.object();
            const v18848 = try s.text("properties");
            const v18849 = try o.lookup(&s, frame, "binding18075");
            const v18850 = try o.lookup(&s, frame, "binding18569");
            const v18851 = try o.lookup(&s, frame, "binding18570");
            const v18852 = try s.call(v18849, c.pi_js_undefined(), &.{ v18850, v18851 });
            try o.defineKey(&s, v18847, v18848, v18852);
            break :conditional18845 v18847;
        } else {
            const v18853 = try s.object();
            break :conditional18845 v18853;
        }
    };
    try js.spreadInto(e, v18642, v18846);
    const v18854 = try o.importValue(&s, graph, "schema/types/index.mjs", "*");
    const v18855 = try s.text("IsPropertyNames");
    const v18856 = try s.own(try js.getKey(e, v18854, v18855));
    const v18857 = try o.lookup(&s, frame, "binding18570");
    const v18858 = try s.call(v18856, v18854, &.{v18857});
    const v18860 = conditional18859: {
        if (s.truthy(v18858)) {
            const v18861 = try s.object();
            const v18862 = try s.text("propertyNames");
            const v18863 = try o.lookup(&s, frame, "binding18076");
            const v18864 = try o.lookup(&s, frame, "binding18569");
            const v18865 = try o.lookup(&s, frame, "binding18570");
            const v18866 = try s.call(v18863, c.pi_js_undefined(), &.{ v18864, v18865 });
            try o.defineKey(&s, v18861, v18862, v18866);
            break :conditional18859 v18861;
        } else {
            const v18867 = try s.object();
            break :conditional18859 v18867;
        }
    };
    try js.spreadInto(e, v18642, v18860);
    const v18868 = try o.importValue(&s, graph, "schema/types/index.mjs", "*");
    const v18869 = try s.text("IsThen");
    const v18870 = try s.own(try js.getKey(e, v18868, v18869));
    const v18871 = try o.lookup(&s, frame, "binding18570");
    const v18872 = try s.call(v18870, v18868, &.{v18871});
    const v18874 = conditional18873: {
        if (s.truthy(v18872)) {
            const v18875 = try s.object();
            const v18876 = try s.text("then");
            const v18877 = try o.lookup(&s, frame, "binding18079");
            const v18878 = try o.lookup(&s, frame, "binding18569");
            const v18879 = try o.lookup(&s, frame, "binding18570");
            const v18880 = try s.call(v18877, c.pi_js_undefined(), &.{ v18878, v18879 });
            try o.defineKey(&s, v18875, v18876, v18880);
            break :conditional18873 v18875;
        } else {
            const v18881 = try s.object();
            break :conditional18873 v18881;
        }
    };
    try js.spreadInto(e, v18642, v18874);
    const v18882 = try o.importValue(&s, graph, "schema/types/index.mjs", "*");
    const v18883 = try s.text("IsUnevaluatedItems");
    const v18884 = try s.own(try js.getKey(e, v18882, v18883));
    const v18885 = try o.lookup(&s, frame, "binding18570");
    const v18886 = try s.call(v18884, v18882, &.{v18885});
    const v18888 = conditional18887: {
        if (s.truthy(v18886)) {
            const v18889 = try s.object();
            const v18890 = try s.text("unevaluatedItems");
            const v18891 = try o.lookup(&s, frame, "binding18080");
            const v18892 = try o.lookup(&s, frame, "binding18569");
            const v18893 = try o.lookup(&s, frame, "binding18570");
            const v18894 = try s.call(v18891, c.pi_js_undefined(), &.{ v18892, v18893 });
            try o.defineKey(&s, v18889, v18890, v18894);
            break :conditional18887 v18889;
        } else {
            const v18895 = try s.object();
            break :conditional18887 v18895;
        }
    };
    try js.spreadInto(e, v18642, v18888);
    const v18896 = try o.importValue(&s, graph, "schema/types/index.mjs", "*");
    const v18897 = try s.text("IsUnevaluatedProperties");
    const v18898 = try s.own(try js.getKey(e, v18896, v18897));
    const v18899 = try o.lookup(&s, frame, "binding18570");
    const v18900 = try s.call(v18898, v18896, &.{v18899});
    const v18902 = conditional18901: {
        if (s.truthy(v18900)) {
            const v18903 = try s.object();
            const v18904 = try s.text("unevaluatedProperties");
            const v18905 = try o.lookup(&s, frame, "binding18081");
            const v18906 = try o.lookup(&s, frame, "binding18569");
            const v18907 = try o.lookup(&s, frame, "binding18570");
            const v18908 = try s.call(v18905, c.pi_js_undefined(), &.{ v18906, v18907 });
            try o.defineKey(&s, v18903, v18904, v18908);
            break :conditional18901 v18903;
        } else {
            const v18909 = try s.object();
            break :conditional18901 v18909;
        }
    };
    try js.spreadInto(e, v18642, v18902);
    try o.assign(&s, frame, "binding18581", v18642);
    const v18910 = try o.lookup(&s, frame, "binding18569");
    const v18911 = try s.text("resolving");
    const v18912 = try s.own(try js.getKey(e, v18910, v18911));
    const v18913 = try s.text("delete");
    const v18914 = try s.own(try js.getKey(e, v18912, v18913));
    const v18915 = try o.lookup(&s, frame, "binding18570");
    const v18916 = try s.call(v18914, v18912, &.{v18915});
    _ = v18916;
    const v18917 = try o.importValue(&s, graph, "system/index.mjs", "Memory");
    const v18918 = try s.text("Discard");
    const v18919 = try s.own(try js.getKey(e, v18917, v18918));
    const v18920 = try o.importValue(&s, graph, "system/index.mjs", "Memory");
    const v18921 = try s.text("Assign");
    const v18922 = try s.own(try js.getKey(e, v18920, v18921));
    const v18923 = try o.lookup(&s, frame, "binding18570");
    const v18924 = try o.lookup(&s, frame, "binding18581");
    const v18925 = try s.call(v18922, v18920, &.{ v18923, v18924 });
    const v18926 = try s.array();
    const v18927 = try s.text("$id");
    try o.append(&s, v18926, v18927);
    const v18928 = try s.call(v18919, v18917, &.{ v18925, v18926 });
    try o.assign(&s, frame, "binding18582", v18928);
    const v18929 = try o.lookup(&s, frame, "binding18580");
    const v18930 = try s.text("used");
    const v18931 = try s.own(try js.getKey(e, v18929, v18930));
    const v18933 = conditional18932: {
        if (s.truthy(v18931)) {
            const v18934 = try o.lookup(&s, frame, "binding18580");
            const v18935 = try s.text("key");
            const v18936 = try s.own(try js.getKey(e, v18934, v18935));
            break :conditional18932 v18936;
        } else {
            const v18937 = try o.lookup(&s, frame, "binding18059");
            const v18938 = try o.lookup(&s, frame, "binding18582");
            const v18939 = try s.call(v18937, c.pi_js_undefined(), &.{v18938});
            break :conditional18932 v18939;
        }
    };
    try o.assign(&s, frame, "binding18583", v18933);
    const v18940 = try o.lookup(&s, frame, "binding18086");
    const v18941 = try s.text("set");
    const v18942 = try s.own(try js.getKey(e, v18940, v18941));
    const v18943 = try o.lookup(&s, frame, "binding18583");
    const v18944 = try o.lookup(&s, frame, "binding18582");
    const v18945 = try s.call(v18942, v18940, &.{ v18943, v18944 });
    _ = v18945;
    const v18946 = try s.object();
    const v18947 = try s.text("$ref");
    const v18948 = try s.text("#/$defs/");
    const v18949 = try o.lookup(&s, frame, "binding18583");
    const v18950 = try s.stringify(v18949);
    const v18951 = try s.concat(v18948, v18950);
    const v18952 = try s.text("");
    const v18953 = try s.concat(v18951, v18952);
    try o.defineKey(&s, v18946, v18947, v18953);
    try o.assign(&s, frame, "binding18584", v18946);
    const v18954 = try o.lookup(&s, frame, "binding18087");
    const v18955 = try s.text("set");
    const v18956 = try s.own(try js.getKey(e, v18954, v18955));
    const v18957 = try o.lookup(&s, frame, "binding18570");
    const v18958 = try o.lookup(&s, frame, "binding18584");
    const v18959 = try s.call(v18956, v18954, &.{ v18957, v18958 });
    _ = v18959;
    const v18960 = try o.lookup(&s, frame, "binding18584");
    return c.JS_DupValue(e.context, v18960);
}
fn body18962(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    _ = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v18967 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding18963", v18967);
    const v18968 = if (args.len > 1) args[1] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding18964", v18968);
    const v18971 = try o.lookup(&s, frame, "binding18059");
    const v18972 = try o.lookup(&s, frame, "binding18964");
    const v18973 = try s.call(v18971, c.pi_js_undefined(), &.{v18972});
    try o.assign(&s, frame, "binding18969", v18973);
    const v18974 = try o.lookup(&s, frame, "binding18086");
    const v18975 = try s.text("set");
    const v18976 = try s.own(try js.getKey(e, v18974, v18975));
    const v18977 = try o.lookup(&s, frame, "binding18969");
    const v18978 = try o.lookup(&s, frame, "binding18964");
    const v18979 = try s.call(v18976, v18974, &.{ v18977, v18978 });
    _ = v18979;
    const v18980 = try s.object();
    const v18981 = try s.text("$ref");
    const v18982 = try s.text("#/$defs/");
    const v18983 = try o.lookup(&s, frame, "binding18969");
    const v18984 = try s.stringify(v18983);
    const v18985 = try s.concat(v18982, v18984);
    const v18986 = try s.text("");
    const v18987 = try s.concat(v18985, v18986);
    try o.defineKey(&s, v18980, v18981, v18987);
    try o.assign(&s, frame, "binding18970", v18980);
    const v18988 = try o.lookup(&s, frame, "binding18087");
    const v18989 = try s.text("set");
    const v18990 = try s.own(try js.getKey(e, v18988, v18989));
    const v18991 = try o.lookup(&s, frame, "binding18964");
    const v18992 = try o.lookup(&s, frame, "binding18970");
    const v18993 = try s.call(v18990, v18988, &.{ v18991, v18992 });
    _ = v18993;
    const v18994 = try o.lookup(&s, frame, "binding18970");
    return c.JS_DupValue(e.context, v18994);
}
fn body18996(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v18999 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding18997", v18999);
    const v19000 = if (args.len > 1) args[1] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding18998", v19000);
    const v19001 = try o.importValue(&s, graph, "schema/types/index.mjs", "*");
    const v19002 = try s.text("IsSchemaBoolean");
    const v19003 = try s.own(try js.getKey(e, v19001, v19002));
    const v19004 = try o.lookup(&s, frame, "binding18998");
    const v19005 = try s.call(v19003, v19001, &.{v19004});
    const v19007 = conditional19006: {
        if (s.truthy(v19005)) {
            const v19008 = try o.lookup(&s, frame, "binding18083");
            const v19009 = try o.lookup(&s, frame, "binding18997");
            const v19010 = try o.lookup(&s, frame, "binding18998");
            const v19011 = try s.call(v19008, c.pi_js_undefined(), &.{ v19009, v19010 });
            break :conditional19006 v19011;
        } else {
            const v19012 = try o.lookup(&s, frame, "binding18082");
            const v19013 = try o.lookup(&s, frame, "binding18997");
            const v19014 = try o.lookup(&s, frame, "binding18998");
            const v19015 = try s.call(v19012, c.pi_js_undefined(), &.{ v19013, v19014 });
            break :conditional19006 v19015;
        }
    };
    return c.JS_DupValue(e.context, v19007);
}
fn body19017(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    _ = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v19020 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding19018", v19020);
    const v19022 = try o.lookup(&s, frame, "binding18059");
    const v19023 = try o.lookup(&s, frame, "binding19018");
    const v19024 = try s.call(v19022, c.pi_js_undefined(), &.{v19023});
    try o.assign(&s, frame, "binding19021", v19024);
    const v19025 = try s.object();
    const v19026 = try s.text("$ref");
    const v19027 = try s.text("#/$defs/");
    const v19028 = try o.lookup(&s, frame, "binding19021");
    const v19029 = try s.stringify(v19028);
    const v19030 = try s.concat(v19027, v19029);
    const v19031 = try s.text("");
    const v19032 = try s.concat(v19030, v19031);
    try o.defineKey(&s, v19025, v19026, v19032);
    const v19033 = try s.text("$defs");
    const v19034 = try s.object();
    const v19035 = try o.lookup(&s, frame, "binding19021");
    const v19036 = try o.propertyKey(&s, v19035);
    const v19037 = try o.lookup(&s, frame, "binding19018");
    try o.defineKey(&s, v19034, v19036, v19037);
    try o.defineKey(&s, v19025, v19033, v19034);
    return c.JS_DupValue(e.context, v19025);
}
fn body19039(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v19045 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding19040", v19045);
    const v19050 = try o.lookup(&s, frame, "binding18086");
    const v19051 = try s.text("clear");
    const v19052 = try s.own(try js.getKey(e, v19050, v19051));
    const v19053 = try s.call(v19052, v19050, &.{});
    _ = v19053;
    const v19054 = try o.lookup(&s, frame, "binding18087");
    const v19055 = try s.text("clear");
    const v19056 = try s.own(try js.getKey(e, v19054, v19055));
    const v19057 = try s.call(v19056, v19054, &.{});
    _ = v19057;
    const v19058 = try o.importValue(&s, graph, "schema/types/index.mjs", "*");
    const v19059 = try s.text("IsSchemaBoolean");
    const v19060 = try s.own(try js.getKey(e, v19058, v19059));
    const v19061 = try o.lookup(&s, frame, "binding19040");
    const v19062 = try s.call(v19060, v19058, &.{v19061});
    if (s.truthy(v19062)) {
        const v19063 = try o.lookup(&s, frame, "binding18085");
        const v19064 = try o.lookup(&s, frame, "binding19040");
        const v19065 = try s.call(v19063, c.pi_js_undefined(), &.{v19064});
        return c.JS_DupValue(e.context, v19065);
    }
    const v19066 = try o.importValue(&s, graph, "schema/types/index.mjs", "*");
    const v19067 = try s.text("IsDefs");
    const v19068 = try s.own(try js.getKey(e, v19066, v19067));
    const v19069 = try o.lookup(&s, frame, "binding19040");
    const v19070 = try s.call(v19068, v19066, &.{v19069});
    const v19072 = conditional19071: {
        if (s.truthy(v19070)) {
            const v19073 = try o.lookup(&s, frame, "binding19040");
            const v19074 = try s.text("$defs");
            const v19075 = try s.own(try js.getKey(e, v19073, v19074));
            break :conditional19071 v19075;
        } else {
            const v19076 = try s.object();
            break :conditional19071 v19076;
        }
    };
    try o.assign(&s, frame, "binding19046", v19072);
    const v19077 = try o.importValue(&s, graph, "schema/types/index.mjs", "*");
    const v19078 = try s.text("IsRef");
    const v19079 = try s.own(try js.getKey(e, v19077, v19078));
    const v19080 = try o.lookup(&s, frame, "binding19040");
    const v19081 = try s.call(v19079, v19077, &.{v19080});
    const v19083 = conditional19082: {
        if (s.truthy(v19081)) {
            const v19084 = try o.lookup(&s, frame, "binding18077");
            const v19085 = try o.lookup(&s, frame, "binding19046");
            const v19086 = try o.lookup(&s, frame, "binding19040");
            const v19087 = try o.lookup(&s, frame, "binding19040");
            const v19088 = try s.text("$ref");
            const v19089 = try s.own(try js.getKey(e, v19087, v19088));
            const v19090 = try s.call(v19084, c.pi_js_undefined(), &.{ v19085, v19086, v19089 });
            break :conditional19082 v19090;
        } else {
            const v19091 = try o.lookup(&s, frame, "binding19040");
            break :conditional19082 v19091;
        }
    };
    try o.assign(&s, frame, "binding19047", v19083);
    const v19092 = try o.importValue(&s, graph, "schema/types/index.mjs", "*");
    const v19093 = try s.text("IsSchemaBoolean");
    const v19094 = try s.own(try js.getKey(e, v19092, v19093));
    const v19095 = try o.lookup(&s, frame, "binding19047");
    const v19096 = try s.call(v19094, v19092, &.{v19095});
    if (s.truthy(v19096)) {
        const v19097 = try o.lookup(&s, frame, "binding18085");
        const v19098 = try o.lookup(&s, frame, "binding19047");
        const v19099 = try s.call(v19097, c.pi_js_undefined(), &.{v19098});
        return c.JS_DupValue(e.context, v19099);
    }
    const v19100 = try s.object();
    const v19101 = try s.text("schema");
    const v19102 = try o.lookup(&s, frame, "binding19040");
    try o.defineKey(&s, v19100, v19101, v19102);
    const v19103 = try s.text("context");
    const v19104 = try o.lookup(&s, frame, "binding19046");
    try o.defineKey(&s, v19100, v19103, v19104);
    const v19105 = try s.text("resolving");
    const v19106 = try s.global("Map");
    const v19107 = try o.construct(&s, v19106, &.{});
    try o.defineKey(&s, v19100, v19105, v19107);
    try o.assign(&s, frame, "binding19048", v19100);
    const v19108 = try o.lookup(&s, frame, "binding18084");
    const v19109 = try o.lookup(&s, frame, "binding19048");
    const v19110 = try o.lookup(&s, frame, "binding19047");
    const v19111 = try s.call(v19108, c.pi_js_undefined(), &.{ v19109, v19110 });
    try o.assign(&s, frame, "binding19049", v19111);
    const v19112 = try s.object();
    const v19113 = try s.text("$ref");
    const v19114 = try o.lookup(&s, frame, "binding19049");
    const v19115 = try s.text("$ref");
    const v19116 = try s.own(try js.getKey(e, v19114, v19115));
    try o.defineKey(&s, v19112, v19113, v19116);
    const v19117 = try s.text("$defs");
    const v19118 = try s.global("Object");
    const v19119 = try s.text("fromEntries");
    const v19120 = try s.own(try js.getKey(e, v19118, v19119));
    const v19121 = try o.lookup(&s, frame, "binding18086");
    const v19122 = try s.call(v19120, v19118, &.{v19121});
    try o.defineKey(&s, v19112, v19117, v19122);
    return c.JS_DupValue(e.context, v19112);
}
