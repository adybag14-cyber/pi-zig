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
    const namespace = try s.get(modules, "value/convert/try/try_array.mjs");
    const frame = try o.frame(&s, c.pi_js_null());
    try s.put(frame, "@this", c.pi_js_undefined());
    try s.put(try s.get(graph, "frames"), "value/convert/try/try_array.mjs", frame);
    const bindings = try s.object();
    try s.put(try s.get(graph, "bindings"), "value/convert/try/try_array.mjs", bindings);
    const v27325 = try s.own(try ordinary.create(e, "TryArray", 1, body27308, &.{ graph, frame }));
    try o.assign(&s, frame, "binding27307", v27325);
    const v27326 = try o.lookup(&s, frame, "binding27307");
    try s.put(namespace, "TryArray", v27326);
    const v27327 = try o.lookup(&s, frame, "binding27307");
    try s.put(namespace, "TryArray", v27327);
    try s.put(bindings, "TryArray", try s.text("binding27307"));
}
fn body27308(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v27310 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding27309", v27310);
    const v27311 = try o.importValue(&s, graph, "guard/index.mjs", "Guard");
    const v27312 = try s.text("IsArray");
    const v27313 = try s.own(try js.getKey(e, v27311, v27312));
    const v27314 = try o.lookup(&s, frame, "binding27309");
    const v27315 = try s.call(v27313, v27311, &.{v27314});
    const v27317 = conditional27316: {
        if (s.truthy(v27315)) {
            const v27318 = try o.importValue(&s, graph, "value/convert/try/try_result.mjs", "Ok");
            const v27319 = try o.lookup(&s, frame, "binding27309");
            const v27320 = try s.call(v27318, c.pi_js_undefined(), &.{v27319});
            break :conditional27316 v27320;
        } else {
            const v27321 = try o.importValue(&s, graph, "value/convert/try/try_result.mjs", "Ok");
            const v27322 = try s.array();
            const v27323 = try o.lookup(&s, frame, "binding27309");
            try o.append(&s, v27322, v27323);
            const v27324 = try s.call(v27321, c.pi_js_undefined(), &.{v27322});
            break :conditional27316 v27324;
        }
    };
    return c.JS_DupValue(e.context, v27317);
}
