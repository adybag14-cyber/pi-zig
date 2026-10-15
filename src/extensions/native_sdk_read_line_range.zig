//! Source b45e0eb core/tools/render-utils.ts formatReadLineRange.
//! Source-only private export; no public SDK activation or runtime qualification.
const em = @import("engine.zig");
const ordinary = @import("native_node_function.zig");
const temporary = @import("native_sdk_prompt_scope.zig");
const Scope = temporary.Scope;
const c = em.c;

fn parseLineNumber(scope: *Scope, input: c.JSValue) !c.JSValue {
    var value = input;
    if (c.JS_IsString(value) and !scope.equal(try scope.invoke(value, "trim", &.{}), try scope.text(""))) {
        value = try scope.call(try scope.global("Number"), c.pi_js_undefined(), &.{value});
    }
    if (!c.JS_IsNumber(value)) return c.pi_js_undefined();
    const number = try scope.global("Number");
    return if (scope.truthy(try scope.invoke(number, "isFinite", &.{value}))) value else c.pi_js_undefined();
}

pub fn format(scope: *Scope, offset: c.JSValue, limit: c.JSValue) !c.JSValue {
    if (temporary.nullish(offset) and temporary.nullish(limit)) return scope.text("");
    const start = if (temporary.nullish(offset)) c.JS_NewInt32(scope.engine.context, 1) else try parseLineNumber(scope, offset);
    if (c.JS_IsUndefined(start)) return scope.text("");
    if (temporary.nullish(limit)) return scope.concat(try scope.text(":"), try scope.stringify(start));
    const count = try parseLineNumber(scope, limit);
    if (c.JS_IsUndefined(count)) return scope.text("");
    const sum = try scope.own(try scope.engine.checked(c.JS_PiBinaryOperator(scope.engine.context, 0, start, count)));
    const end = try scope.own(try scope.engine.checked(c.JS_PiBinaryOperator(scope.engine.context, 1, sum, c.JS_NewInt32(scope.engine.context, 1))));
    var result = try scope.concat(try scope.text(":"), try scope.stringify(start));
    if (scope.truthy(end)) result = try scope.concat(result, try scope.concat(try scope.text("-"), try scope.stringify(end)));
    return result;
}

pub fn create(engine: *em.Engine) !c.JSValue {
    return ordinary.create(engine, "formatReadLineRange", 2, call, &.{});
}

fn call(engine: *em.Engine, _: c.JSValue, args: []const c.JSValue, _: []const c.JSValue) anyerror!c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const result = try format(&scope, if (args.len > 0) args[0] else c.pi_js_undefined(), if (args.len > 1) args[1] else c.pi_js_undefined());
    return c.JS_DupValue(engine.context, result);
}

/// Explicit b45 composition entry point; callers must qualify it before activation.
pub fn install(engine: *em.Engine, exports: c.JSValue) !void {
    try @import("native_sdk.zig").put(engine, exports, "formatReadLineRange", try create(engine));
}
