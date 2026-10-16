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
    const namespace = try s.get(modules, "value/convert/from_union.mjs");
    const frame = try o.frame(&s, c.pi_js_null());
    try s.put(frame, "@this", c.pi_js_undefined());
    try s.put(try s.get(graph, "frames"), "value/convert/from_union.mjs", frame);
    const bindings = try s.object();
    try s.put(try s.get(graph, "bindings"), "value/convert/from_union.mjs", bindings);
    const v27278 = try s.own(try ordinary.create(e, "FromUnion", 3, body27206, &.{ graph, frame }));
    try o.assign(&s, frame, "binding27205", v27278);
    const v27279 = try o.lookup(&s, frame, "binding27205");
    try s.put(namespace, "FromUnion", v27279);
    const v27280 = try o.lookup(&s, frame, "binding27205");
    try s.put(namespace, "FromUnion", v27280);
    try s.put(bindings, "FromUnion", try s.text("binding27205"));
}
fn body27224(e: *Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    _ = try o.lookup(&s, frame, "@this");
    const v27227 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding27226", v27227);
    const v27228 = try o.importValue(&s, graph, "value/check/index.mjs", "Check");
    const v27229 = try o.lookup(&s, frame, "binding27207");
    const v27230 = try o.lookup(&s, frame, "binding27226");
    const v27231 = try o.lookup(&s, frame, "binding27209");
    const v27232 = try s.call(v27228, c.pi_js_undefined(), &.{ v27229, v27230, v27231 });
    return c.JS_DupValue(e.context, v27232);
}
fn body27224C(ctx: ?*c.JSContext, receiver: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const e = Engine.fromContext(ctx.?);
    return body27224(e, receiver, if (argc > 0) argv[0..@intCast(argc)] else &.{}, roots[0..2]) catch |err| sdk.fail(e, err);
}
fn body27242(e: *Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    _ = try o.lookup(&s, frame, "@this");
    const v27245 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding27244", v27245);
    const v27246 = try o.importValue(&s, graph, "value/convert/from_type.mjs", "FromType");
    const v27247 = try o.lookup(&s, frame, "binding27207");
    const v27248 = try o.lookup(&s, frame, "binding27244");
    const v27249 = try o.importValue(&s, graph, "value/clone/index.mjs", "Clone");
    const v27250 = try o.lookup(&s, frame, "binding27209");
    const v27251 = try s.call(v27249, c.pi_js_undefined(), &.{v27250});
    const v27252 = try s.call(v27246, c.pi_js_undefined(), &.{ v27247, v27248, v27251 });
    return c.JS_DupValue(e.context, v27252);
}
fn body27242C(ctx: ?*c.JSContext, receiver: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const e = Engine.fromContext(ctx.?);
    return body27242(e, receiver, if (argc > 0) argv[0..@intCast(argc)] else &.{}, roots[0..2]) catch |err| sdk.fail(e, err);
}
fn body27258(e: *Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    _ = try o.lookup(&s, frame, "@this");
    const v27261 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding27260", v27261);
    const v27262 = try o.importValue(&s, graph, "value/check/index.mjs", "Check");
    const v27263 = try o.lookup(&s, frame, "binding27207");
    const v27264 = try o.lookup(&s, frame, "binding27208");
    const v27265 = try o.lookup(&s, frame, "binding27260");
    const v27266 = try s.call(v27262, c.pi_js_undefined(), &.{ v27263, v27264, v27265 });
    return c.JS_DupValue(e.context, v27266);
}
fn body27258C(ctx: ?*c.JSContext, receiver: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const e = Engine.fromContext(ctx.?);
    return body27258(e, receiver, if (argc > 0) argv[0..@intCast(argc)] else &.{}, roots[0..2]) catch |err| sdk.fail(e, err);
}
fn body27206(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v27213 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding27207", v27213);
    const v27214 = if (args.len > 1) args[1] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding27208", v27214);
    const v27215 = if (args.len > 2) args[2] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding27209", v27215);
    const v27219 = try o.lookup(&s, frame, "binding27208");
    const v27220 = try s.text("anyOf");
    const v27221 = try s.own(try js.getKey(e, v27219, v27220));
    const v27222 = try s.text("some");
    const v27223 = try s.own(try js.getKey(e, v27221, v27222));
    const v27233 = try o.arrow(&s, "", 1, body27224C, &.{ graph, frame });
    const v27234 = try s.call(v27223, v27221, &.{v27233});
    try o.assign(&s, frame, "binding27216", v27234);
    const v27235 = try o.lookup(&s, frame, "binding27216");
    if (s.truthy(v27235)) {
        const v27236 = try o.lookup(&s, frame, "binding27209");
        return c.JS_DupValue(e.context, v27236);
    }
    const v27237 = try o.lookup(&s, frame, "binding27208");
    const v27238 = try s.text("anyOf");
    const v27239 = try s.own(try js.getKey(e, v27237, v27238));
    const v27240 = try s.text("map");
    const v27241 = try s.own(try js.getKey(e, v27239, v27240));
    const v27253 = try o.arrow(&s, "", 1, body27242C, &.{ graph, frame });
    const v27254 = try s.call(v27241, v27239, &.{v27253});
    try o.assign(&s, frame, "binding27217", v27254);
    const v27255 = try o.lookup(&s, frame, "binding27217");
    const v27256 = try s.text("find");
    const v27257 = try s.own(try js.getKey(e, v27255, v27256));
    const v27267 = try o.arrow(&s, "", 1, body27258C, &.{ graph, frame });
    const v27268 = try s.call(v27257, v27255, &.{v27267});
    try o.assign(&s, frame, "binding27218", v27268);
    const v27269 = try o.importValue(&s, graph, "guard/index.mjs", "Guard");
    const v27270 = try s.text("IsUndefined");
    const v27271 = try s.own(try js.getKey(e, v27269, v27270));
    const v27272 = try o.lookup(&s, frame, "binding27218");
    const v27273 = try s.call(v27271, v27269, &.{v27272});
    const v27275 = conditional27274: {
        if (s.truthy(v27273)) {
            const v27276 = try o.lookup(&s, frame, "binding27209");
            break :conditional27274 v27276;
        } else {
            const v27277 = try o.lookup(&s, frame, "binding27218");
            break :conditional27274 v27277;
        }
    };
    return c.JS_DupValue(e.context, v27275);
}
