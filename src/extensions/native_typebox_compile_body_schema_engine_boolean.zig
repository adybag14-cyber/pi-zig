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
    const namespace = try s.get(modules, "schema/engine/boolean.mjs");
    const frame = try o.frame(&s, c.pi_js_null());
    try s.put(frame, "@this", c.pi_js_undefined());
    try s.put(try s.get(graph, "frames"), "schema/engine/boolean.mjs", frame);
    const bindings = try s.object();
    try s.put(try s.get(graph, "bindings"), "schema/engine/boolean.mjs", bindings);
    const v7380 = try s.own(try ordinary.create(e, "BuildSchemaBoolean", 4, body7360, &.{ graph, frame }));
    try o.assign(&s, frame, "binding7357", v7380);
    const v7391 = try s.own(try ordinary.create(e, "CheckSchemaBoolean", 4, body7381, &.{ graph, frame }));
    try o.assign(&s, frame, "binding7358", v7391);
    const v7426 = try s.own(try ordinary.create(e, "ErrorSchemaBoolean", 6, body7392, &.{ graph, frame }));
    try o.assign(&s, frame, "binding7359", v7426);
    const v7427 = try o.lookup(&s, frame, "binding7357");
    try s.put(namespace, "BuildSchemaBoolean", v7427);
    const v7428 = try o.lookup(&s, frame, "binding7358");
    try s.put(namespace, "CheckSchemaBoolean", v7428);
    const v7429 = try o.lookup(&s, frame, "binding7359");
    try s.put(namespace, "ErrorSchemaBoolean", v7429);
    const v7430 = try o.lookup(&s, frame, "binding7357");
    try s.put(namespace, "BuildSchemaBoolean", v7430);
    const v7431 = try o.lookup(&s, frame, "binding7358");
    try s.put(namespace, "CheckSchemaBoolean", v7431);
    const v7432 = try o.lookup(&s, frame, "binding7359");
    try s.put(namespace, "ErrorSchemaBoolean", v7432);
    try s.put(bindings, "BuildSchemaBoolean", try s.text("binding7357"));
    try s.put(bindings, "CheckSchemaBoolean", try s.text("binding7358"));
    try s.put(bindings, "ErrorSchemaBoolean", try s.text("binding7359"));
}
fn body7360(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v7365 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding7361", v7365);
    const v7366 = if (args.len > 1) args[1] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding7362", v7366);
    const v7367 = if (args.len > 2) args[2] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding7363", v7367);
    const v7368 = if (args.len > 3) args[3] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding7364", v7368);
    const v7369 = try o.lookup(&s, frame, "binding7363");
    const v7371 = conditional7370: {
        if (s.truthy(v7369)) {
            const v7372 = try o.importValue(&s, graph, "guard/index.mjs", "EmitGuard");
            const v7373 = try s.text("Constant");
            const v7374 = try s.own(try js.getKey(e, v7372, v7373));
            const v7375 = try s.call(v7374, v7372, &.{o.boolean(&s, true)});
            break :conditional7370 v7375;
        } else {
            const v7376 = try o.importValue(&s, graph, "guard/index.mjs", "EmitGuard");
            const v7377 = try s.text("Constant");
            const v7378 = try s.own(try js.getKey(e, v7376, v7377));
            const v7379 = try s.call(v7378, v7376, &.{o.boolean(&s, false)});
            break :conditional7370 v7379;
        }
    };
    return c.JS_DupValue(e.context, v7371);
}
fn body7381(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    _ = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v7386 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding7382", v7386);
    const v7387 = if (args.len > 1) args[1] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding7383", v7387);
    const v7388 = if (args.len > 2) args[2] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding7384", v7388);
    const v7389 = if (args.len > 3) args[3] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding7385", v7389);
    const v7390 = try o.lookup(&s, frame, "binding7384");
    return c.JS_DupValue(e.context, v7390);
}
fn body7392(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    _ = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v7399 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding7393", v7399);
    const v7400 = if (args.len > 1) args[1] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding7394", v7400);
    const v7401 = if (args.len > 2) args[2] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding7395", v7401);
    const v7402 = if (args.len > 3) args[3] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding7396", v7402);
    const v7403 = if (args.len > 4) args[4] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding7397", v7403);
    const v7404 = if (args.len > 5) args[5] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding7398", v7404);
    const v7405 = try o.lookup(&s, frame, "binding7358");
    const v7406 = try o.lookup(&s, frame, "binding7393");
    const v7407 = try o.lookup(&s, frame, "binding7394");
    const v7408 = try o.lookup(&s, frame, "binding7397");
    const v7409 = try o.lookup(&s, frame, "binding7398");
    const v7410 = try s.call(v7405, c.pi_js_undefined(), &.{ v7406, v7407, v7408, v7409 });
    const v7412 = logical7411: {
        if (s.truthy(v7410)) break :logical7411 v7410;
        const v7413 = try o.lookup(&s, frame, "binding7394");
        const v7414 = try s.text("AddError");
        const v7415 = try s.own(try js.getKey(e, v7413, v7414));
        const v7416 = try s.object();
        const v7417 = try s.text("keyword");
        const v7418 = try s.text("boolean");
        try o.defineKey(&s, v7416, v7417, v7418);
        const v7419 = try s.text("schemaPath");
        const v7420 = try o.lookup(&s, frame, "binding7395");
        try o.defineKey(&s, v7416, v7419, v7420);
        const v7421 = try s.text("instancePath");
        const v7422 = try o.lookup(&s, frame, "binding7396");
        try o.defineKey(&s, v7416, v7421, v7422);
        const v7423 = try s.text("params");
        const v7424 = try s.object();
        try o.defineKey(&s, v7416, v7423, v7424);
        const v7425 = try s.call(v7415, v7413, &.{v7416});
        break :logical7411 v7425;
    };
    return c.JS_DupValue(e.context, v7412);
}
