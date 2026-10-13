//! Source MCP tool-name matcher for the ordinary AgentSession constructor.
//! Keeps both filter passes and every live collection/string method observable.
const em = @import("engine.zig");
const sdk = @import("native_sdk.zig");
const js = @import("native_js_values.zig");
const Scope = @import("native_sdk_prompt_scope.zig").Scope;
const functions = @import("native_node_function.zig");
const c = em.c;
pub fn create(engine: *em.Engine) !c.JSValue {
    return functions.create(engine, "createToolNameMatcher", 1, exported, &.{});
}
fn exported(engine: *em.Engine, _: c.JSValue, args: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
    return matcher(engine, if (args.len > 0) args[0] else c.pi_js_undefined());
}
pub fn matcher(engine: *em.Engine, entries: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const set = try scope.global("Set");
    const filter = try scope.get(entries, "filter");
    const exact_predicate = try scope.own(try engine.checked(c.pi_js_function_magic(engine.context, includes, "", 1, 0)));
    var arguments = [_]c.JSValue{try scope.call(filter, entries, &.{exact_predicate})};
    const names = try scope.own(try engine.checked(c.JS_CallConstructor(engine.context, set, arguments.len, &arguments)));
    const pattern_filter = try scope.get(entries, "filter");
    const pattern_predicate = try scope.own(try engine.checked(c.pi_js_function_magic(engine.context, includes, "", 1, 1)));
    const selected = try scope.call(pattern_filter, entries, &.{pattern_predicate});
    const map = try scope.get(selected, "map");
    const mapper = try scope.own(try functions.create(engine, "toolPatternRegExp", 1, pattern, &.{}));
    const patterns = try scope.call(map, selected, &.{mapper});
    var roots = [_]c.JSValue{ names, patterns };
    return engine.checked(c.JS_NewCFunctionData2(engine.context, matches, "", 1, 0, roots.len, &roots));
}
fn includes(context: ?*c.JSContext, _: c.JSValue, argc: c_int, args: [*c]c.JSValue, magic: c_int) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const entry = if (argc > 0) args[0] else c.pi_js_undefined();
    const star = scope.text("*") catch |err| return sdk.fail(engine, err);
    const result = scope.invoke(entry, "includes", &.{star}) catch |err| return sdk.fail(engine, err);
    return if (magic == 0) c.pi_js_bool(engine.context, @intFromBool(!scope.truthy(result))) else c.JS_DupValue(engine.context, result);
}
fn pattern(engine: *em.Engine, _: c.JSValue, args: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const input = if (args.len > 0) args[0] else c.pi_js_undefined();
    const parts = try scope.invoke(input, "split", &.{try scope.text("*")});
    const map = try scope.get(parts, "map");
    const mapper = try scope.own(try engine.checked(c.JS_NewCFunction(engine.context, escape, "", 1)));
    const escaped = try scope.call(map, parts, &.{mapper});
    const source = try scope.invoke(escaped, "join", &.{try scope.text(".*")});
    const constructor = try scope.global("RegExp");
    const anchored = try scope.concat(try scope.concat(try scope.text("^"), source), try scope.text("$"));
    var arguments = [_]c.JSValue{anchored};
    return engine.checked(c.JS_CallConstructor(engine.context, constructor, arguments.len, &arguments));
}
fn escape(context: ?*c.JSContext, _: c.JSValue, argc: c_int, args: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    return escapePart(engine, if (argc > 0) args[0] else c.pi_js_undefined()) catch |err| sdk.fail(engine, err);
}
fn escapePart(engine: *em.Engine, input: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const replace = try scope.get(input, "replace");
    var arguments = [_]c.JSValue{ try scope.text("[.+?^${}()|[\\]\\\\]"), try scope.text("g") };
    const expression = try scope.own(try engine.checked(c.JS_CallConstructor(engine.context, engine.intrinsic_regexp_constructor, arguments.len, &arguments)));
    return js.call(engine, replace, input, &.{ expression, try scope.text("\\$&") });
}
fn matches(context: ?*c.JSContext, _: c.JSValue, argc: c_int, args: [*c]c.JSValue, _: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    return matchesName(engine, if (argc > 0) args[0] else c.pi_js_undefined(), roots[0..2]) catch |err| sdk.fail(engine, err);
}
fn matchesName(engine: *em.Engine, name: c.JSValue, captures: []const c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const exact = try scope.invoke(captures[0], "has", &.{name});
    if (scope.truthy(exact)) return c.JS_DupValue(engine.context, exact);
    const some = try scope.get(captures[1], "some");
    var roots = [_]c.JSValue{name};
    const predicate = try scope.own(try engine.checked(c.JS_NewCFunctionData2(engine.context, testPattern, "", 1, 0, roots.len, &roots)));
    return js.call(engine, some, captures[1], &.{predicate});
}
fn testPattern(context: ?*c.JSContext, _: c.JSValue, argc: c_int, args: [*c]c.JSValue, _: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    return js.invoke(engine, if (argc > 0) args[0] else c.pi_js_undefined(), "test", &.{roots[0]}) catch |err| sdk.fail(engine, err);
}
