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
    const namespace = try s.get(modules, "value/codec/decode.mjs");
    const frame = try o.frame(&s, c.pi_js_null());
    try s.put(frame, "@this", c.pi_js_undefined());
    try s.put(try s.get(graph, "frames"), "value/codec/decode.mjs", frame);
    const bindings = try s.object();
    try s.put(try s.get(graph, "bindings"), "value/codec/decode.mjs", bindings);
    const v24061 = try s.own(try ordinary.create(e, "Assert", 3, body24040, &.{ graph, frame }));
    try o.assign(&s, frame, "binding24036", v24061);
    const v24089 = try s.own(try ordinary.create(e, "DecodeUnsafe", 3, body24062, &.{ graph, frame }));
    try o.assign(&s, frame, "binding24037", v24089);
    const v24140 = try s.own(try ordinary.create(e, "Decode", 0, body24090, &.{ graph, frame }));
    try o.assign(&s, frame, "binding24039", v24140);
    const v24141 = try o.lookup(&s, frame, "binding24037");
    try s.put(namespace, "DecodeUnsafe", v24141);
    const v24142 = try o.lookup(&s, frame, "binding24039");
    try s.put(namespace, "Decode", v24142);
    const v24143 = try o.importValue(&s, graph, "value/assert/index.mjs", "AssertError");
    const v24144 = try o.derivedPrototype(&s, v24143);
    const v24153 = try s.own(try class.constructor(e, "DecodeError", 2, v24144, constructor24145, &.{ graph, frame, v24143 }));
    try o.setPrototype(&s, v24153, v24143);
    try o.assign(&s, frame, "binding24035", v24153);
    const v24154 = try o.importValue(&s, graph, "value/pipeline/index.mjs", "Pipeline");
    const v24155 = try s.array();
    const v24167 = try o.arrow(&s, "", 3, body24156C, &.{ graph, frame });
    try o.append(&s, v24155, v24167);
    const v24181 = try o.arrow(&s, "", 3, body24168C, &.{ graph, frame });
    try o.append(&s, v24155, v24181);
    const v24195 = try o.arrow(&s, "", 3, body24182C, &.{ graph, frame });
    try o.append(&s, v24155, v24195);
    const v24209 = try o.arrow(&s, "", 3, body24196C, &.{ graph, frame });
    try o.append(&s, v24155, v24209);
    const v24223 = try o.arrow(&s, "", 3, body24210C, &.{ graph, frame });
    try o.append(&s, v24155, v24223);
    const v24237 = try o.arrow(&s, "", 3, body24224C, &.{ graph, frame });
    try o.append(&s, v24155, v24237);
    const v24238 = try s.call(v24154, c.pi_js_undefined(), &.{v24155});
    try o.assign(&s, frame, "binding24038", v24238);
    const v24239 = try o.lookup(&s, frame, "binding24037");
    try s.put(namespace, "DecodeUnsafe", v24239);
    const v24240 = try o.lookup(&s, frame, "binding24039");
    try s.put(namespace, "Decode", v24240);
    const v24241 = try o.lookup(&s, frame, "binding24035");
    try s.put(namespace, "DecodeError", v24241);
    try s.put(bindings, "DecodeUnsafe", try s.text("binding24037"));
    try s.put(bindings, "Decode", try s.text("binding24039"));
    try s.put(bindings, "DecodeError", try s.text("binding24035"));
}
fn body24040(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v24044 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding24041", v24044);
    const v24045 = if (args.len > 1) args[1] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding24042", v24045);
    const v24046 = if (args.len > 2) args[2] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding24043", v24046);
    const v24047 = try o.importValue(&s, graph, "value/check/index.mjs", "Check");
    const v24048 = try o.lookup(&s, frame, "binding24041");
    const v24049 = try o.lookup(&s, frame, "binding24042");
    const v24050 = try o.lookup(&s, frame, "binding24043");
    const v24051 = try s.call(v24047, c.pi_js_undefined(), &.{ v24048, v24049, v24050 });
    if (s.truthy(o.boolean(&s, !s.truthy(v24051)))) {
        const v24052 = try o.lookup(&s, frame, "binding24035");
        const v24053 = try o.lookup(&s, frame, "binding24043");
        const v24054 = try o.importValue(&s, graph, "value/errors/index.mjs", "Errors");
        const v24055 = try o.lookup(&s, frame, "binding24041");
        const v24056 = try o.lookup(&s, frame, "binding24042");
        const v24057 = try o.lookup(&s, frame, "binding24043");
        const v24058 = try s.call(v24054, c.pi_js_undefined(), &.{ v24055, v24056, v24057 });
        const v24059 = try o.construct(&s, v24052, &.{ v24053, v24058 });
        _ = c.JS_Throw(e.context, c.JS_DupValue(e.context, v24059));
        return js.capture(e);
    }
    const v24060 = try o.lookup(&s, frame, "binding24043");
    return c.JS_DupValue(e.context, v24060);
}
fn body24062(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v24067 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding24063", v24067);
    const v24068 = if (args.len > 1) args[1] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding24064", v24068);
    const v24069 = if (args.len > 2) args[2] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding24065", v24069);
    const v24071 = try o.importValue(&s, graph, "system/index.mjs", "Settings");
    const v24072 = try s.text("Get");
    const v24073 = try s.own(try js.getKey(e, v24071, v24072));
    const v24074 = try s.call(v24073, v24071, &.{});
    const v24075 = try s.text("unionPrioritySort");
    const v24076 = try s.own(try js.getKey(e, v24074, v24075));
    const v24078 = conditional24077: {
        if (s.truthy(v24076)) {
            const v24079 = try o.importValue(&s, graph, "value/shared/union_priority_sort.mjs", "UnionPrioritySort");
            const v24080 = try o.lookup(&s, frame, "binding24064");
            const v24081 = try s.call(v24079, c.pi_js_undefined(), &.{v24080});
            break :conditional24077 v24081;
        } else {
            const v24082 = try o.lookup(&s, frame, "binding24064");
            break :conditional24077 v24082;
        }
    };
    try o.assign(&s, frame, "binding24070", v24078);
    const v24083 = try o.importValue(&s, graph, "value/codec/from_type.mjs", "FromType");
    const v24084 = try s.text("Decode");
    const v24085 = try o.lookup(&s, frame, "binding24063");
    const v24086 = try o.lookup(&s, frame, "binding24070");
    const v24087 = try o.lookup(&s, frame, "binding24065");
    const v24088 = try s.call(v24083, c.pi_js_undefined(), &.{ v24084, v24085, v24086, v24087 });
    return c.JS_DupValue(e.context, v24088);
}
fn body24105(e: *Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    _ = roots[0];
    const frame = try o.frame(&s, roots[1]);
    _ = try o.lookup(&s, frame, "@this");
    const v24110 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding24107", v24110);
    const v24111 = if (args.len > 1) args[1] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding24108", v24111);
    const v24112 = if (args.len > 2) args[2] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding24109", v24112);
    const v24113 = try s.array();
    const v24114 = try o.lookup(&s, frame, "binding24107");
    try o.append(&s, v24113, v24114);
    const v24115 = try o.lookup(&s, frame, "binding24108");
    try o.append(&s, v24113, v24115);
    const v24116 = try o.lookup(&s, frame, "binding24109");
    try o.append(&s, v24113, v24116);
    return c.JS_DupValue(e.context, v24113);
}
fn body24105C(ctx: ?*c.JSContext, receiver: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const e = Engine.fromContext(ctx.?);
    return body24105(e, receiver, if (argc > 0) argv[0..@intCast(argc)] else &.{}, roots[0..2]) catch |err| sdk.fail(e, err);
}
fn body24119(e: *Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    _ = roots[0];
    const frame = try o.frame(&s, roots[1]);
    _ = try o.lookup(&s, frame, "@this");
    const v24123 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding24121", v24123);
    const v24124 = if (args.len > 1) args[1] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding24122", v24124);
    const v24125 = try s.array();
    const v24126 = try s.object();
    try o.append(&s, v24125, v24126);
    const v24127 = try o.lookup(&s, frame, "binding24121");
    try o.append(&s, v24125, v24127);
    const v24128 = try o.lookup(&s, frame, "binding24122");
    try o.append(&s, v24125, v24128);
    return c.JS_DupValue(e.context, v24125);
}
fn body24119C(ctx: ?*c.JSContext, receiver: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const e = Engine.fromContext(ctx.?);
    return body24119(e, receiver, if (argc > 0) argv[0..@intCast(argc)] else &.{}, roots[0..2]) catch |err| sdk.fail(e, err);
}
fn body24090(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v24095 = try o.rest(&s, args, 0);
    try o.assign(&s, frame, "binding24091", v24095);
    const v24099 = try o.importValue(&s, graph, "system/index.mjs", "Arguments");
    const v24100 = try s.text("Match");
    const v24101 = try s.own(try js.getKey(e, v24099, v24100));
    const v24102 = try o.lookup(&s, frame, "binding24091");
    const v24103 = try s.object();
    const v24104 = try s.text("3");
    const v24117 = try o.arrow(&s, "3", 3, body24105C, &.{ graph, frame });
    try o.defineKey(&s, v24103, v24104, v24117);
    const v24118 = try s.text("2");
    const v24129 = try o.arrow(&s, "2", 2, body24119C, &.{ graph, frame });
    try o.defineKey(&s, v24103, v24118, v24129);
    const v24130 = try s.call(v24101, v24099, &.{ v24102, v24103 });
    var destructure24131 = try o.iterator(e, v24130);
    defer destructure24131.deinit();
    errdefer destructure24131.closePreserving();
    const v24132 = try s.own(if (destructure24131.closed) c.pi_js_undefined() else (try destructure24131.next()) orelse c.pi_js_undefined());
    try o.assign(&s, frame, "binding24096", v24132);
    const v24133 = try s.own(if (destructure24131.closed) c.pi_js_undefined() else (try destructure24131.next()) orelse c.pi_js_undefined());
    try o.assign(&s, frame, "binding24097", v24133);
    const v24134 = try s.own(if (destructure24131.closed) c.pi_js_undefined() else (try destructure24131.next()) orelse c.pi_js_undefined());
    try o.assign(&s, frame, "binding24098", v24134);
    try destructure24131.close();
    const v24135 = try o.lookup(&s, frame, "binding24038");
    const v24136 = try o.lookup(&s, frame, "binding24096");
    const v24137 = try o.lookup(&s, frame, "binding24097");
    const v24138 = try o.lookup(&s, frame, "binding24098");
    const v24139 = try s.call(v24135, c.pi_js_undefined(), &.{ v24136, v24137, v24138 });
    return c.JS_DupValue(e.context, v24139);
}
fn constructor24145(e: *Engine, target: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    _ = roots[0];
    const frame = try o.frame(&s, roots[1]);
    const v24148 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding24146", v24148);
    const v24149 = if (args.len > 1) args[1] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding24147", v24149);
    const v24150 = try s.text("Decode");
    const v24151 = try o.lookup(&s, frame, "binding24146");
    const v24152 = try o.lookup(&s, frame, "binding24147");
    const receiver = try o.constructWithTarget(&s, roots[2], target, &.{ v24150, v24151, v24152 });
    try s.put(frame, "@this", receiver);
    return c.JS_DupValue(e.context, receiver);
}
fn body24156(e: *Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    _ = try o.lookup(&s, frame, "@this");
    const v24161 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding24158", v24161);
    const v24162 = if (args.len > 1) args[1] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding24159", v24162);
    const v24163 = if (args.len > 2) args[2] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding24160", v24163);
    const v24164 = try o.importValue(&s, graph, "value/clone/index.mjs", "Clone");
    const v24165 = try o.lookup(&s, frame, "binding24160");
    const v24166 = try s.call(v24164, c.pi_js_undefined(), &.{v24165});
    return c.JS_DupValue(e.context, v24166);
}
fn body24156C(ctx: ?*c.JSContext, receiver: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const e = Engine.fromContext(ctx.?);
    return body24156(e, receiver, if (argc > 0) argv[0..@intCast(argc)] else &.{}, roots[0..2]) catch |err| sdk.fail(e, err);
}
fn body24168(e: *Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    _ = try o.lookup(&s, frame, "@this");
    const v24173 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding24170", v24173);
    const v24174 = if (args.len > 1) args[1] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding24171", v24174);
    const v24175 = if (args.len > 2) args[2] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding24172", v24175);
    const v24176 = try o.importValue(&s, graph, "value/default/index.mjs", "Default");
    const v24177 = try o.lookup(&s, frame, "binding24170");
    const v24178 = try o.lookup(&s, frame, "binding24171");
    const v24179 = try o.lookup(&s, frame, "binding24172");
    const v24180 = try s.call(v24176, c.pi_js_undefined(), &.{ v24177, v24178, v24179 });
    return c.JS_DupValue(e.context, v24180);
}
fn body24168C(ctx: ?*c.JSContext, receiver: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const e = Engine.fromContext(ctx.?);
    return body24168(e, receiver, if (argc > 0) argv[0..@intCast(argc)] else &.{}, roots[0..2]) catch |err| sdk.fail(e, err);
}
fn body24182(e: *Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    _ = try o.lookup(&s, frame, "@this");
    const v24187 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding24184", v24187);
    const v24188 = if (args.len > 1) args[1] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding24185", v24188);
    const v24189 = if (args.len > 2) args[2] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding24186", v24189);
    const v24190 = try o.importValue(&s, graph, "value/convert/index.mjs", "Convert");
    const v24191 = try o.lookup(&s, frame, "binding24184");
    const v24192 = try o.lookup(&s, frame, "binding24185");
    const v24193 = try o.lookup(&s, frame, "binding24186");
    const v24194 = try s.call(v24190, c.pi_js_undefined(), &.{ v24191, v24192, v24193 });
    return c.JS_DupValue(e.context, v24194);
}
fn body24182C(ctx: ?*c.JSContext, receiver: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const e = Engine.fromContext(ctx.?);
    return body24182(e, receiver, if (argc > 0) argv[0..@intCast(argc)] else &.{}, roots[0..2]) catch |err| sdk.fail(e, err);
}
fn body24196(e: *Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    _ = try o.lookup(&s, frame, "@this");
    const v24201 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding24198", v24201);
    const v24202 = if (args.len > 1) args[1] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding24199", v24202);
    const v24203 = if (args.len > 2) args[2] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding24200", v24203);
    const v24204 = try o.importValue(&s, graph, "value/clean/index.mjs", "Clean");
    const v24205 = try o.lookup(&s, frame, "binding24198");
    const v24206 = try o.lookup(&s, frame, "binding24199");
    const v24207 = try o.lookup(&s, frame, "binding24200");
    const v24208 = try s.call(v24204, c.pi_js_undefined(), &.{ v24205, v24206, v24207 });
    return c.JS_DupValue(e.context, v24208);
}
fn body24196C(ctx: ?*c.JSContext, receiver: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const e = Engine.fromContext(ctx.?);
    return body24196(e, receiver, if (argc > 0) argv[0..@intCast(argc)] else &.{}, roots[0..2]) catch |err| sdk.fail(e, err);
}
fn body24210(e: *Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    _ = roots[0];
    const frame = try o.frame(&s, roots[1]);
    _ = try o.lookup(&s, frame, "@this");
    const v24215 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding24212", v24215);
    const v24216 = if (args.len > 1) args[1] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding24213", v24216);
    const v24217 = if (args.len > 2) args[2] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding24214", v24217);
    const v24218 = try o.lookup(&s, frame, "binding24036");
    const v24219 = try o.lookup(&s, frame, "binding24212");
    const v24220 = try o.lookup(&s, frame, "binding24213");
    const v24221 = try o.lookup(&s, frame, "binding24214");
    const v24222 = try s.call(v24218, c.pi_js_undefined(), &.{ v24219, v24220, v24221 });
    return c.JS_DupValue(e.context, v24222);
}
fn body24210C(ctx: ?*c.JSContext, receiver: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const e = Engine.fromContext(ctx.?);
    return body24210(e, receiver, if (argc > 0) argv[0..@intCast(argc)] else &.{}, roots[0..2]) catch |err| sdk.fail(e, err);
}
fn body24224(e: *Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    _ = roots[0];
    const frame = try o.frame(&s, roots[1]);
    _ = try o.lookup(&s, frame, "@this");
    const v24229 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding24226", v24229);
    const v24230 = if (args.len > 1) args[1] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding24227", v24230);
    const v24231 = if (args.len > 2) args[2] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding24228", v24231);
    const v24232 = try o.lookup(&s, frame, "binding24037");
    const v24233 = try o.lookup(&s, frame, "binding24226");
    const v24234 = try o.lookup(&s, frame, "binding24227");
    const v24235 = try o.lookup(&s, frame, "binding24228");
    const v24236 = try s.call(v24232, c.pi_js_undefined(), &.{ v24233, v24234, v24235 });
    return c.JS_DupValue(e.context, v24236);
}
fn body24224C(ctx: ?*c.JSContext, receiver: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const e = Engine.fromContext(ctx.?);
    return body24224(e, receiver, if (argc > 0) argv[0..@intCast(argc)] else &.{}, roots[0..2]) catch |err| sdk.fail(e, err);
}
