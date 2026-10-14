//! Original highlight.js10.7.3 compileKeywords and scoreForKeyword bodies.
//! Private grammar compiler support, not an alternative highlighter.
const em = @import("engine.zig");
const sdk = @import("native_sdk.zig");
const js = @import("native_js_values.zig");
const ordinary = @import("native_node_function.zig");
const Scope = @import("native_highlight_scope.zig").Scope;
const c = em.c;

pub fn compile(engine: *em.Engine, raw: c.JSValue, insensitive: c.JSValue, supplied_class: c.JSValue) anyerror!c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const class_name = if (c.JS_IsUndefined(supplied_class)) try scope.text("keyword") else supplied_class;
    const compiled = try scope.object();
    if (c.JS_IsString(raw)) {
        try compileList(&scope, compiled, class_name, try scope.invoke(raw, "split", &.{try scope.text(" ")}), insensitive);
    } else if (scope.truthy(try scope.invoke(try scope.global("Array"), "isArray", &.{raw}))) {
        try compileList(&scope, compiled, class_name, raw, insensitive);
    } else {
        const keys = try scope.invoke(try scope.global("Object"), "keys", &.{raw});
        const for_each = try scope.get(keys, "forEach");
        const callback = try scope.own(try ordinary.create(engine, "", 1, compileEntry, &.{ compiled, raw, insensitive }));
        _ = try scope.call(for_each, keys, &.{callback});
    }
    return c.JS_DupValue(engine.context, compiled);
}
fn compileList(scope: *Scope, compiled: c.JSValue, class_name: c.JSValue, values: c.JSValue, insensitive: c.JSValue) !void {
    var keywords = values;
    if (scope.truthy(insensitive)) {
        const map = try scope.get(keywords, "map");
        const lowercase = try scope.own(try scope.engine.checked(c.JS_NewCFunction(scope.engine.context, lowerCase, "", 1)));
        keywords = try scope.call(map, keywords, &.{lowercase});
    }
    const for_each = try scope.get(keywords, "forEach");
    const callback = try scope.own(try ordinary.create(scope.engine, "", 1, compileKeyword, &.{ compiled, class_name }));
    _ = try scope.call(for_each, keywords, &.{callback});
}
fn compileEntry(engine: *em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const class_name = if (args.len > 0) args[0] else c.pi_js_undefined();
    // Object.assign is resolved before evaluating the recursive argument.
    const object = try scope.global("Object");
    const assign = try scope.get(object, "assign");
    const raw = try scope.own(try js.getKey(engine, roots[1], class_name));
    const nested = try scope.own(try compile(engine, raw, roots[2], class_name));
    _ = try scope.call(assign, object, &.{ roots[0], nested });
    return c.pi_js_undefined();
}
fn compileKeyword(engine: *em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const keyword = if (args.len > 0) args[0] else c.pi_js_undefined();
    const pair = try scope.invoke(keyword, "split", &.{try scope.text("|")});
    const key = try scope.own(try js.getKey(engine, pair, c.JS_NewInt32(engine.context, 0)));
    const name = try js.atom(engine, key);
    defer c.JS_FreeAtom(engine.context, name);
    const value = try scope.array();
    try scope.index(value, 0, roots[1]);
    const scored_keyword = try scope.own(try js.getKey(engine, pair, c.JS_NewInt32(engine.context, 0)));
    const provided = try scope.own(try js.getKey(engine, pair, c.JS_NewInt32(engine.context, 1)));
    const score = try scope.own(try scoreForKeyword(engine, scored_keyword, provided));
    try scope.index(value, 1, score);
    if (c.JS_SetProperty(engine.context, roots[0], name, c.JS_DupValue(engine.context, value)) < 0) return js.capture(engine);
    return c.pi_js_undefined();
}
fn lowerCase(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    return js.invoke(engine, if (argc > 0) argv[0] else c.pi_js_undefined(), "toLowerCase", &.{}) catch |err| sdk.fail(engine, err);
}
pub fn scoreForKeyword(engine: *em.Engine, keyword: c.JSValue, provided: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    if (scope.truthy(provided)) return c.JS_DupValue(engine.context, try scope.call(try scope.global("Number"), c.pi_js_undefined(), &.{provided}));
    const common = try commonKeywords(&scope);
    const includes = try scope.get(common, "includes");
    const lower = try scope.invoke(keyword, "toLowerCase", &.{});
    const exists = try scope.call(includes, common, &.{lower});
    return c.JS_NewInt32(engine.context, if (scope.truthy(exists)) 0 else 1);
}
fn commonKeywords(scope: *Scope) !c.JSValue {
    const module = "pi-native:highlight-common-keywords";
    if (!scope.engine.native_module_values.contains(module)) {
        const exports = try scope.object();
        const values = try scope.array();
        inline for (.{ "of", "and", "for", "in", "not", "or", "if", "then", "parent", "list", "value" }, 0..) |word, index| try scope.index(values, index, try scope.text(word));
        try scope.put(exports, "values", values);
        try scope.engine.registerValueModule(module, exports);
    }
    return scope.get(scope.engine.native_module_values.get(module).?, "values");
}
