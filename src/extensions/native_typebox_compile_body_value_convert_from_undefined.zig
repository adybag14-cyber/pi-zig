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
    const namespace = try s.get(modules, "value/convert/from_undefined.mjs");
    const frame = try o.frame(&s, c.pi_js_null());
    try s.put(frame, "@this", c.pi_js_undefined());
    try s.put(try s.get(graph, "frames"), "value/convert/from_undefined.mjs", frame);
    const bindings = try s.object();
    try s.put(try s.get(graph, "bindings"), "value/convert/from_undefined.mjs", bindings);
    const v27202 = try s.own(try ordinary.create(e, "FromUndefined", 3, body27177, &.{ graph, frame }));
    try o.assign(&s, frame, "binding27176", v27202);
    const v27203 = try o.lookup(&s, frame, "binding27176");
    try s.put(namespace, "FromUndefined", v27203);
    const v27204 = try o.lookup(&s, frame, "binding27176");
    try s.put(namespace, "FromUndefined", v27204);
    try s.put(bindings, "FromUndefined", try s.text("binding27176"));
}
fn body27177(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v27182 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding27178", v27182);
    const v27183 = if (args.len > 1) args[1] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding27179", v27183);
    const v27184 = if (args.len > 2) args[2] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding27180", v27184);
    const v27186 = try o.importValue(&s, graph, "value/convert/try/index.mjs", "Try");
    const v27187 = try s.text("TryUndefined");
    const v27188 = try s.own(try js.getKey(e, v27186, v27187));
    const v27189 = try o.lookup(&s, frame, "binding27180");
    const v27190 = try s.call(v27188, v27186, &.{v27189});
    try o.assign(&s, frame, "binding27185", v27190);
    const v27191 = try o.importValue(&s, graph, "value/convert/try/index.mjs", "Try");
    const v27192 = try s.text("IsOk");
    const v27193 = try s.own(try js.getKey(e, v27191, v27192));
    const v27194 = try o.lookup(&s, frame, "binding27185");
    const v27195 = try s.call(v27193, v27191, &.{v27194});
    const v27197 = conditional27196: {
        if (s.truthy(v27195)) {
            const v27198 = try o.lookup(&s, frame, "binding27185");
            const v27199 = try s.text("value");
            const v27200 = try s.own(try js.getKey(e, v27198, v27199));
            break :conditional27196 v27200;
        } else {
            const v27201 = try o.lookup(&s, frame, "binding27180");
            break :conditional27196 v27201;
        }
    };
    return c.JS_DupValue(e.context, v27197);
}
