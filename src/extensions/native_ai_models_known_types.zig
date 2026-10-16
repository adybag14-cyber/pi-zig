//! One lexical hasKnownModelType declaration shared by both Source consumers.
const v = @import("native_ai_provider_values.zig");
const c = v.c;
pub fn create(engine: *v.em.Engine, get_model_type: c.JSValue, known: c.JSValue) !c.JSValue {
    return @import("native_node_function.zig").create(engine, "hasKnownModelType", 1, call, &.{ get_model_type, known });
}
fn call(engine: *v.em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    var scope: v.Scope = .{ .engine = engine };
    defer scope.deinit();
    const object = try scope.global("Object");
    const has_own = try scope.get(object, "hasOwn");
    return v.js.call(engine, has_own, object, &.{ roots[1], try scope.call(roots[0], c.pi_js_undefined(), &.{if (args.len > 0) args[0] else c.pi_js_undefined()}) });
}
