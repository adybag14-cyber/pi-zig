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
    const namespace = try s.get(modules, "value/assert/assert.mjs");
    const frame = try o.frame(&s, c.pi_js_null());
    try s.put(frame, "@this", c.pi_js_undefined());
    try s.put(try s.get(graph, "frames"), "value/assert/assert.mjs", frame);
    const bindings = try s.object();
    try s.put(try s.get(graph, "bindings"), "value/assert/assert.mjs", bindings);
    const v23196 = try s.own(try ordinary.create(e, "Assert", 0, body23134, &.{ graph, frame }));
    try o.assign(&s, frame, "binding23133", v23196);
    const v23197 = try o.lookup(&s, frame, "binding23133");
    try s.put(namespace, "Assert", v23197);
    const v23198 = try s.global("Error");
    const v23199 = try o.derivedPrototype(&s, v23198);
    const v23225 = try s.own(try class.constructor(e, "AssertError", 3, v23199, constructor23200, &.{ graph, frame, v23198 }));
    try o.setPrototype(&s, v23225, v23198);
    try o.assign(&s, frame, "binding23132", v23225);
    const v23226 = try o.lookup(&s, frame, "binding23133");
    try s.put(namespace, "Assert", v23226);
    const v23227 = try o.lookup(&s, frame, "binding23132");
    try s.put(namespace, "AssertError", v23227);
    try s.put(bindings, "Assert", try s.text("binding23133"));
    try s.put(bindings, "AssertError", try s.text("binding23132"));
}
fn body23151(e: *Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    _ = roots[0];
    const frame = try o.frame(&s, roots[1]);
    _ = try o.lookup(&s, frame, "@this");
    const v23156 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding23153", v23156);
    const v23157 = if (args.len > 1) args[1] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding23154", v23157);
    const v23158 = if (args.len > 2) args[2] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding23155", v23158);
    const v23159 = try s.array();
    const v23160 = try o.lookup(&s, frame, "binding23153");
    try o.append(&s, v23159, v23160);
    const v23161 = try o.lookup(&s, frame, "binding23154");
    try o.append(&s, v23159, v23161);
    const v23162 = try o.lookup(&s, frame, "binding23155");
    try o.append(&s, v23159, v23162);
    return c.JS_DupValue(e.context, v23159);
}
fn body23151C(ctx: ?*c.JSContext, receiver: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const e = Engine.fromContext(ctx.?);
    return body23151(e, receiver, if (argc > 0) argv[0..@intCast(argc)] else &.{}, roots[0..2]) catch |err| sdk.fail(e, err);
}
fn body23165(e: *Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    _ = roots[0];
    const frame = try o.frame(&s, roots[1]);
    _ = try o.lookup(&s, frame, "@this");
    const v23169 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding23167", v23169);
    const v23170 = if (args.len > 1) args[1] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding23168", v23170);
    const v23171 = try s.array();
    const v23172 = try s.object();
    try o.append(&s, v23171, v23172);
    const v23173 = try o.lookup(&s, frame, "binding23167");
    try o.append(&s, v23171, v23173);
    const v23174 = try o.lookup(&s, frame, "binding23168");
    try o.append(&s, v23171, v23174);
    return c.JS_DupValue(e.context, v23171);
}
fn body23165C(ctx: ?*c.JSContext, receiver: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const e = Engine.fromContext(ctx.?);
    return body23165(e, receiver, if (argc > 0) argv[0..@intCast(argc)] else &.{}, roots[0..2]) catch |err| sdk.fail(e, err);
}
fn body23134(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v23140 = try o.rest(&s, args, 0);
    try o.assign(&s, frame, "binding23135", v23140);
    const v23145 = try o.importValue(&s, graph, "system/arguments/index.mjs", "Arguments");
    const v23146 = try s.text("Match");
    const v23147 = try s.own(try js.getKey(e, v23145, v23146));
    const v23148 = try o.lookup(&s, frame, "binding23135");
    const v23149 = try s.object();
    const v23150 = try s.text("3");
    const v23163 = try o.arrow(&s, "3", 3, body23151C, &.{ graph, frame });
    try o.defineKey(&s, v23149, v23150, v23163);
    const v23164 = try s.text("2");
    const v23175 = try o.arrow(&s, "2", 2, body23165C, &.{ graph, frame });
    try o.defineKey(&s, v23149, v23164, v23175);
    const v23176 = try s.call(v23147, v23145, &.{ v23148, v23149 });
    var destructure23177 = try o.iterator(e, v23176);
    defer destructure23177.deinit();
    errdefer destructure23177.closePreserving();
    const v23178 = try s.own(if (destructure23177.closed) c.pi_js_undefined() else (try destructure23177.next()) orelse c.pi_js_undefined());
    try o.assign(&s, frame, "binding23141", v23178);
    const v23179 = try s.own(if (destructure23177.closed) c.pi_js_undefined() else (try destructure23177.next()) orelse c.pi_js_undefined());
    try o.assign(&s, frame, "binding23142", v23179);
    const v23180 = try s.own(if (destructure23177.closed) c.pi_js_undefined() else (try destructure23177.next()) orelse c.pi_js_undefined());
    try o.assign(&s, frame, "binding23143", v23180);
    try destructure23177.close();
    const v23181 = try o.importValue(&s, graph, "value/check/index.mjs", "Check");
    const v23182 = try o.lookup(&s, frame, "binding23141");
    const v23183 = try o.lookup(&s, frame, "binding23142");
    const v23184 = try o.lookup(&s, frame, "binding23143");
    const v23185 = try s.call(v23181, c.pi_js_undefined(), &.{ v23182, v23183, v23184 });
    try o.assign(&s, frame, "binding23144", v23185);
    const v23186 = try o.lookup(&s, frame, "binding23144");
    if (s.truthy(o.boolean(&s, !s.truthy(v23186)))) {
        const v23187 = try o.lookup(&s, frame, "binding23132");
        const v23188 = try s.text("Assert");
        const v23189 = try o.lookup(&s, frame, "binding23143");
        const v23190 = try o.importValue(&s, graph, "value/errors/index.mjs", "Errors");
        const v23191 = try o.lookup(&s, frame, "binding23141");
        const v23192 = try o.lookup(&s, frame, "binding23142");
        const v23193 = try o.lookup(&s, frame, "binding23143");
        const v23194 = try s.call(v23190, c.pi_js_undefined(), &.{ v23191, v23192, v23193 });
        const v23195 = try o.construct(&s, v23187, &.{ v23188, v23189, v23194 });
        _ = c.JS_Throw(e.context, c.JS_DupValue(e.context, v23195));
        return js.capture(e);
    }
    return c.pi_js_undefined();
}
fn constructor23200(e: *Engine, target: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    _ = roots[0];
    const frame = try o.frame(&s, roots[1]);
    const v23204 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding23201", v23204);
    const v23205 = if (args.len > 1) args[1] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding23202", v23205);
    const v23206 = if (args.len > 2) args[2] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding23203", v23206);
    const v23207 = try o.lookup(&s, frame, "binding23201");
    const receiver = try o.constructWithTarget(&s, roots[2], target, &.{v23207});
    try s.put(frame, "@this", receiver);
    const v23208 = try s.global("Object");
    const v23209 = try s.text("defineProperty");
    const v23210 = try s.own(try js.getKey(e, v23208, v23209));
    const v23211 = try s.text("cause");
    const v23212 = try s.object();
    const v23213 = try s.text("value");
    const v23214 = try s.object();
    const v23215 = try s.text("source");
    const v23216 = try o.lookup(&s, frame, "binding23201");
    try o.defineKey(&s, v23214, v23215, v23216);
    const v23217 = try s.text("errors");
    const v23218 = try o.lookup(&s, frame, "binding23203");
    try o.defineKey(&s, v23214, v23217, v23218);
    const v23219 = try s.text("value");
    const v23220 = try o.lookup(&s, frame, "binding23202");
    try o.defineKey(&s, v23214, v23219, v23220);
    try o.defineKey(&s, v23212, v23213, v23214);
    const v23221 = try s.text("writable");
    try o.defineKey(&s, v23212, v23221, o.boolean(&s, false));
    const v23222 = try s.text("configurable");
    try o.defineKey(&s, v23212, v23222, o.boolean(&s, false));
    const v23223 = try s.text("enumerable");
    try o.defineKey(&s, v23212, v23223, o.boolean(&s, false));
    const v23224 = try s.call(v23210, v23208, &.{ receiver, v23211, v23212 });
    _ = v23224;
    return c.JS_DupValue(e.context, receiver);
}
