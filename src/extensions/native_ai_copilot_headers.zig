//! Actual Source5ab Copilot initiator/vision/header bodies over live guest arrays.
const v = @import("native_ai_provider_values.zig");
const Scope = v.Scope;
const c = v.c;
pub fn initiator(scope: *Scope, messages: c.JSValue) !c.JSValue {
    const last_index = try scope.own(try @import("native_image_arithmetic.zig").binary(scope.engine, .subtract, try scope.get(messages, "length"), c.JS_NewInt32(scope.engine.context, 1)));
    const last = try scope.own(try v.js.getKey(scope.engine, messages, last_index));
    return scope.text(if (scope.truthy(last) and !try v.eq(scope, try scope.get(last, "role"), "user")) "agent" else "user");
}
pub fn hasVision(scope: *Scope, messages: c.JSValue) !c.JSValue {
    const Adapter = struct {
        fn block(engine: *v.em.Engine, _: c.JSValue, args: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
            var row: Scope = .{ .engine = engine };
            defer row.deinit();
            return c.pi_js_bool(engine.context, @intFromBool(try v.eq(&row, try row.get(if (args.len > 0) args[0] else c.pi_js_undefined(), "type"), "image")));
        }
        fn message(engine: *v.em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
            var row: Scope = .{ .engine = engine };
            defer row.deinit();
            const input = if (args.len > 0) args[0] else c.pi_js_undefined();
            if (try v.eq(&row, try row.get(input, "role"), "user") and try v.array(&row, try row.get(input, "content"))) return v.js.invoke(engine, try row.get(input, "content"), "some", &.{roots[0]});
            if (try v.eq(&row, try row.get(input, "role"), "toolResult") and try v.array(&row, try row.get(input, "content"))) return v.js.invoke(engine, try row.get(input, "content"), "some", &.{roots[0]});
            return c.pi_js_bool(engine.context, 0);
        }
    };
    const block = try scope.own(try @import("native_node_function.zig").createArrow(scope.engine, "", 1, Adapter.block, &.{}));
    const predicate = try scope.own(try @import("native_node_function.zig").createArrow(scope.engine, "", 1, Adapter.message, &.{block}));
    return scope.invoke(messages, "some", &.{predicate});
}
pub fn build(scope: *Scope, messages: c.JSValue, has_images: c.JSValue) !c.JSValue {
    const result = try scope.object();
    try scope.put(result, "X-Initiator", try initiator(scope, messages));
    try scope.put(result, "Openai-Intent", try scope.text("conversation-edits"));
    if (scope.truthy(has_images)) try scope.put(result, "Copilot-Vision-Request", try scope.text("true"));
    return result;
}
