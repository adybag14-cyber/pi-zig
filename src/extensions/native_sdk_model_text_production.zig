//! Actual utils/text.ts stripBom and utils/json.ts stripJsonComments callbacks.
const em = @import("engine.zig");
const temp = @import("native_sdk_prompt_scope.zig");
const Scope = temp.Scope;
const functions = @import("native_node_function.zig");
const c = em.c;
fn arg(args: []const c.JSValue, index: usize) c.JSValue {
    return if (index < args.len) args[index] else c.pi_js_undefined();
}
pub fn create(engine: *em.Engine) !c.JSValue {
    try engine.checkNativeEntry();
    return @import("native_sdk_session_locals.zig").expression(engine, createBody, .{});
}
fn createBody(s: *@import("native_public_values.zig").Scope) !c.JSValue {
    const v = @import("native_public_values.zig");
    const text = try v.own(s, try @import("native_sdk_text_helpers.zig").create(s.engine));
    const namespace = try v.object(s);
    try v.put(s, namespace, "stripBom", try v.get(s, text, "stripBom"));
    try v.put(s, namespace, "stripJsonComments", try v.ordinary(s, "stripJsonComments", 1, stripComments, &.{}));
    return v.duplicate(s, namespace);
}
fn stripComments(engine: *em.Engine, _: c.JSValue, args: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    // Regular expressions are compiled by the existing captured VM intrinsic.
    const first = try regexp(&scope, "\"(?:\\\\.|[^\"\\\\])*\"|//[^\\n]*");
    const first_callback = try scope.own(try functions.createArrow(engine, "", 1, removeComment, &.{}));
    const no_comments = try scope.invoke(arg(args, 0), "replace", &.{ first, first_callback });
    const second = try regexp(&scope, "\"(?:\\\\.|[^\"\\\\])*\"|,(\\s*[}\\]])");
    const second_callback = try scope.own(try functions.createArrow(engine, "", 2, removeComma, &.{}));
    return c.JS_DupValue(engine.context, try scope.invoke(no_comments, "replace", &.{ second, second_callback }));
}
fn regexp(scope: *Scope, pattern: []const u8) !c.JSValue {
    const args = [_]c.JSValue{ try scope.text(pattern), try scope.text("g") };
    return scope.own(try scope.engine.checked(c.JS_CallConstructor(scope.engine.context, scope.engine.intrinsic_regexp_constructor, args.len, @constCast(&args))));
}
fn matched(scope: *Scope, value: c.JSValue) !c.JSValue {
    const first = try scope.own(try scope.engine.checked(c.JS_GetPropertyUint32(scope.engine.context, value, 0)));
    return if (scope.equal(first, try scope.text("\""))) value else scope.text("");
}
fn removeComment(engine: *em.Engine, _: c.JSValue, args: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    return c.JS_DupValue(engine.context, try matched(&scope, arg(args, 0)));
}
fn removeComma(engine: *em.Engine, _: c.JSValue, args: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    return c.JS_DupValue(engine.context, if (temp.nullish(arg(args, 1))) try matched(&scope, arg(args, 0)) else arg(args, 1));
}
