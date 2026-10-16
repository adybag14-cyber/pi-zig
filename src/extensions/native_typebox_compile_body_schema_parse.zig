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
    const namespace = try s.get(modules, "schema/parse.mjs");
    const frame = try o.frame(&s, c.pi_js_null());
    try s.put(frame, "@this", c.pi_js_undefined());
    try s.put(try s.get(graph, "frames"), "schema/parse.mjs", frame);
    const bindings = try s.object();
    try s.put(try s.get(graph, "bindings"), "schema/parse.mjs", bindings);
    const v19154 = try s.own(try ordinary.create(e, "ThrowParseError", 3, body19133, &.{ graph, frame }));
    try o.assign(&s, frame, "binding19131", v19154);
    const v19211 = try s.own(try ordinary.create(e, "Parse", 0, body19155, &.{ graph, frame }));
    try o.assign(&s, frame, "binding19132", v19211);
    const v19212 = try o.lookup(&s, frame, "binding19131");
    try s.put(namespace, "ThrowParseError", v19212);
    const v19213 = try o.lookup(&s, frame, "binding19132");
    try s.put(namespace, "Parse", v19213);
    const v19214 = try s.object();
    const v19228 = try s.own(try class.constructor(e, "ParseError", 3, v19214, constructor19215, &.{ graph, frame, c.pi_js_undefined() }));
    try o.assign(&s, frame, "binding19130", v19228);
    const v19229 = try o.lookup(&s, frame, "binding19131");
    try s.put(namespace, "ThrowParseError", v19229);
    const v19230 = try o.lookup(&s, frame, "binding19132");
    try s.put(namespace, "Parse", v19230);
    const v19231 = try o.lookup(&s, frame, "binding19130");
    try s.put(namespace, "ParseError", v19231);
    try s.put(bindings, "ThrowParseError", try s.text("binding19131"));
    try s.put(bindings, "Parse", try s.text("binding19132"));
    try s.put(bindings, "ParseError", try s.text("binding19130"));
}
fn body19133(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v19138 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding19134", v19138);
    const v19139 = if (args.len > 1) args[1] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding19135", v19139);
    const v19140 = if (args.len > 2) args[2] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding19136", v19140);
    const v19142 = try o.importValue(&s, graph, "schema/errors.mjs", "Errors");
    const v19143 = try o.lookup(&s, frame, "binding19134");
    const v19144 = try o.lookup(&s, frame, "binding19135");
    const v19145 = try o.lookup(&s, frame, "binding19136");
    const v19146 = try s.call(v19142, c.pi_js_undefined(), &.{ v19143, v19144, v19145 });
    try o.assign(&s, frame, "binding19141", v19146);
    const v19147 = try o.lookup(&s, frame, "binding19130");
    const v19148 = try o.lookup(&s, frame, "binding19135");
    const v19149 = try o.lookup(&s, frame, "binding19136");
    const v19150 = try o.lookup(&s, frame, "binding19141");
    const v19151 = try o.propertyKey(&s, c.JS_NewFloat64(e.context, 1));
    const v19152 = try s.own(try js.getKey(e, v19150, v19151));
    const v19153 = try o.construct(&s, v19147, &.{ v19148, v19149, v19152 });
    _ = c.JS_Throw(e.context, c.JS_DupValue(e.context, v19153));
    return js.capture(e);
}
fn body19170(e: *Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    _ = roots[0];
    const frame = try o.frame(&s, roots[1]);
    _ = try o.lookup(&s, frame, "@this");
    const v19175 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding19172", v19175);
    const v19176 = if (args.len > 1) args[1] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding19173", v19176);
    const v19177 = if (args.len > 2) args[2] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding19174", v19177);
    const v19178 = try s.array();
    const v19179 = try o.lookup(&s, frame, "binding19172");
    try o.append(&s, v19178, v19179);
    const v19180 = try o.lookup(&s, frame, "binding19173");
    try o.append(&s, v19178, v19180);
    const v19181 = try o.lookup(&s, frame, "binding19174");
    try o.append(&s, v19178, v19181);
    return c.JS_DupValue(e.context, v19178);
}
fn body19170C(ctx: ?*c.JSContext, receiver: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const e = Engine.fromContext(ctx.?);
    return body19170(e, receiver, if (argc > 0) argv[0..@intCast(argc)] else &.{}, roots[0..2]) catch |err| sdk.fail(e, err);
}
fn body19184(e: *Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    _ = roots[0];
    const frame = try o.frame(&s, roots[1]);
    _ = try o.lookup(&s, frame, "@this");
    const v19188 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding19186", v19188);
    const v19189 = if (args.len > 1) args[1] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding19187", v19189);
    const v19190 = try s.array();
    const v19191 = try s.object();
    try o.append(&s, v19190, v19191);
    const v19192 = try o.lookup(&s, frame, "binding19186");
    try o.append(&s, v19190, v19192);
    const v19193 = try o.lookup(&s, frame, "binding19187");
    try o.append(&s, v19190, v19193);
    return c.JS_DupValue(e.context, v19190);
}
fn body19184C(ctx: ?*c.JSContext, receiver: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const e = Engine.fromContext(ctx.?);
    return body19184(e, receiver, if (argc > 0) argv[0..@intCast(argc)] else &.{}, roots[0..2]) catch |err| sdk.fail(e, err);
}
fn body19155(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v19160 = try o.rest(&s, args, 0);
    try o.assign(&s, frame, "binding19156", v19160);
    const v19164 = try o.importValue(&s, graph, "system/arguments/index.mjs", "Arguments");
    const v19165 = try s.text("Match");
    const v19166 = try s.own(try js.getKey(e, v19164, v19165));
    const v19167 = try o.lookup(&s, frame, "binding19156");
    const v19168 = try s.object();
    const v19169 = try s.text("3");
    const v19182 = try o.arrow(&s, "3", 3, body19170C, &.{ graph, frame });
    try o.defineKey(&s, v19168, v19169, v19182);
    const v19183 = try s.text("2");
    const v19194 = try o.arrow(&s, "2", 2, body19184C, &.{ graph, frame });
    try o.defineKey(&s, v19168, v19183, v19194);
    const v19195 = try s.call(v19166, v19164, &.{ v19167, v19168 });
    var destructure19196 = try o.iterator(e, v19195);
    defer destructure19196.deinit();
    errdefer destructure19196.closePreserving();
    const v19197 = try s.own(if (destructure19196.closed) c.pi_js_undefined() else (try destructure19196.next()) orelse c.pi_js_undefined());
    try o.assign(&s, frame, "binding19161", v19197);
    const v19198 = try s.own(if (destructure19196.closed) c.pi_js_undefined() else (try destructure19196.next()) orelse c.pi_js_undefined());
    try o.assign(&s, frame, "binding19162", v19198);
    const v19199 = try s.own(if (destructure19196.closed) c.pi_js_undefined() else (try destructure19196.next()) orelse c.pi_js_undefined());
    try o.assign(&s, frame, "binding19163", v19199);
    try destructure19196.close();
    const v19200 = try o.importValue(&s, graph, "schema/check.mjs", "Check");
    const v19201 = try o.lookup(&s, frame, "binding19161");
    const v19202 = try o.lookup(&s, frame, "binding19162");
    const v19203 = try o.lookup(&s, frame, "binding19163");
    const v19204 = try s.call(v19200, c.pi_js_undefined(), &.{ v19201, v19202, v19203 });
    if (s.truthy(v19204)) {
        const v19205 = try o.lookup(&s, frame, "binding19163");
        return c.JS_DupValue(e.context, v19205);
    }
    const v19206 = try o.lookup(&s, frame, "binding19131");
    const v19207 = try o.lookup(&s, frame, "binding19161");
    const v19208 = try o.lookup(&s, frame, "binding19162");
    const v19209 = try o.lookup(&s, frame, "binding19163");
    const v19210 = try s.call(v19206, c.pi_js_undefined(), &.{ v19207, v19208, v19209 });
    _ = v19210;
    return c.pi_js_undefined();
}
fn constructor19215(e: *Engine, target: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    _ = roots[0];
    const frame = try o.frame(&s, roots[1]);
    const v19219 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding19216", v19219);
    const v19220 = if (args.len > 1) args[1] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding19217", v19220);
    const v19221 = if (args.len > 2) args[2] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding19218", v19221);
    const receiver = try s.own(try class.object(e, target));
    try s.put(frame, "@this", receiver);
    const v19222 = try s.text("schema");
    const v19223 = try o.lookup(&s, frame, "binding19216");
    try js.setKey(e, receiver, v19222, v19223);
    const v19224 = try s.text("value");
    const v19225 = try o.lookup(&s, frame, "binding19217");
    try js.setKey(e, receiver, v19224, v19225);
    const v19226 = try s.text("errors");
    const v19227 = try o.lookup(&s, frame, "binding19218");
    try js.setKey(e, receiver, v19226, v19227);
    return c.JS_DupValue(e.context, receiver);
}
