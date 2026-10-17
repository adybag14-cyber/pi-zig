//! Used strict/default SemVer constructor/format/compare semantics from7.8.5.
const em = @import("engine.zig");
const Scope = @import("native_semver785_scope.zig").Scope;
const ops = @import("native_semver785_ops.zig");
const functions = @import("native_node_function.zig");
const c = em.c;
const max_safe: f64 = 9007199254740991;
fn typeName(engine: *em.Engine, value: c.JSValue) []const u8 {
    if (c.JS_IsUndefined(value)) return "undefined";
    if (c.JS_IsBool(value)) return "boolean";
    if (c.JS_IsNumber(value)) return "number";
    if (c.JS_IsString(value)) return "string";
    if (c.JS_IsSymbol(value)) return "symbol";
    if (c.JS_IsBigInt(value)) return "bigint";
    if (c.JS_IsFunction(engine.context, value)) return "function";
    return "object";
}
pub fn typeError(scope: *Scope, pieces: []const c.JSValue) !noreturn {
    // Source evaluates the live TypeError callee before its template argument.
    const constructor = try scope.global("TypeError");
    const message = try join(scope, pieces);
    const reason = try scope.construct(constructor, &.{message});
    return scope.raise(reason);
}
pub fn join(scope: *Scope, pieces: []const c.JSValue) !c.JSValue {
    var result = try scope.text("");
    for (pieces) |piece| result = try scope.concat(result, try scope.stringify(piece));
    return result;
}
pub fn index(scope: *Scope, value: c.JSValue, position: u32) !c.JSValue {
    return scope.at(value, position);
}
fn number(scope: *Scope, value: c.JSValue) !c.JSValue {
    return scope.number(value);
}
pub fn create(scope: *Scope, regex: c.JSValue, input: c.JSValue) !c.JSValue {
    const engine = scope.engine;
    if (!c.JS_IsString(input)) return typeError(scope, &.{ try scope.text("Invalid version. Must be a string. Got type \""), try scope.text(typeName(engine, input)), try scope.text("\".") });
    if (try scope.compare(.greater, try scope.get(input, "length"), c.JS_NewInt32(engine.context, 256))) return typeError(scope, &.{try scope.text("version is longer than 256 characters")});
    const trimmed = try scope.invoke(input, "trim", &.{});
    const matched = try scope.invoke(trimmed, "match", &.{try scope.get(regex, "FULL")});
    if (!scope.truthy(matched)) return typeError(scope, &.{ try scope.text("Invalid Version: "), input });
    const result = try scope.plain();
    inline for (.{ "major", "minor", "patch" }, 1..) |name, position| {
        const value = try number(scope, try index(scope, matched, @intCast(position)));
        try ops.put(scope, result, name, value);
    }
    inline for (.{ "major", "minor", "patch" }) |name| {
        const value = try scope.get(result, name);
        if (try scope.compare(.greater, value, c.JS_NewFloat64(engine.context, max_safe)) or try scope.compare(.less, value, c.JS_NewInt32(engine.context, 0))) return typeError(scope, &.{try scope.text("Invalid " ++ name ++ " version")});
    }
    const pre = try index(scope, matched, 4);
    var prerelease = try scope.array();
    if (scope.truthy(pre)) {
        const split = try scope.invoke(try index(scope, matched, 4), "split", &.{try scope.text(".")});
        const map = try scope.get(split, "map");
        const callback = try scope.own(try functions.createArrow(engine, "", 1, numericIdentifier, &.{regex}));
        prerelease = try scope.call(map, split, &.{callback});
    }
    try ops.put(scope, result, "prerelease", prerelease);
    const build = try index(scope, matched, 5);
    try ops.put(scope, result, "build", if (scope.truthy(build)) try scope.invoke(try index(scope, matched, 5), "split", &.{try scope.text(".")}) else try scope.array());
    var formatted = try join(scope, &.{ try scope.get(result, "major"), try scope.text("."), try scope.get(result, "minor"), try scope.text("."), try scope.get(result, "patch") });
    if (try scope.length(prerelease) > 0) formatted = try join(scope, &.{ formatted, try scope.text("-"), try scope.invoke(prerelease, "join", &.{try scope.text(".")}) });
    try ops.put(scope, result, "version", formatted);
    return result;
}
fn numericIdentifier(engine: *em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    var boundary: Scope = .{ .engine = engine };
    const returned = try numericIdentifierInner(engine, args, roots);
    return boundary.complete(returned, engine.native_allocation_generation);
}
fn numericIdentifierInner(engine: *em.Engine, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    errdefer |err| scope.failed(err);
    const id = if (args.len > 0) args[0] else c.pi_js_undefined();
    if (scope.truthy(try scope.invoke(try scope.get(roots[0], "NUMERIC"), "test", &.{id}))) {
        const value = try number(&scope, id);
        if (try scope.compare(.greater_equal, value, c.JS_NewInt32(engine.context, 0)) and try scope.compare(.less, value, c.JS_NewFloat64(engine.context, max_safe))) return c.JS_DupValue(engine.context, value);
    }
    return c.JS_DupValue(engine.context, id);
}
pub fn compareIdentifiers(scope: *Scope, regex: c.JSValue, a: c.JSValue, b: c.JSValue) !i32 {
    if (c.JS_IsNumber(a) and c.JS_IsNumber(b)) return if (scope.equal(a, b)) 0 else if (try scope.compare(.less, a, b)) -1 else 1;
    const a_numeric = scope.truthy(try scope.invoke(try scope.get(regex, "NUMERIC"), "test", &.{a}));
    const b_numeric = scope.truthy(try scope.invoke(try scope.get(regex, "NUMERIC"), "test", &.{b}));
    const left = if (a_numeric and b_numeric) try number(scope, a) else a;
    const right = if (a_numeric and b_numeric) try number(scope, b) else b;
    if (scope.equal(left, right)) return 0;
    if (a_numeric and !b_numeric) return -1;
    if (b_numeric and !a_numeric) return 1;
    return if (try scope.compare(.less, left, right)) -1 else 1;
}
pub fn compare(scope: *Scope, regex: c.JSValue, a: c.JSValue, b: c.JSValue) !i32 {
    if (scope.equal(try scope.get(a, "version"), try scope.get(b, "version"))) return 0;
    inline for (.{ "major", "minor", "patch" }) |name| {
        const left = try scope.get(a, name);
        const right = try scope.get(b, name);
        if (try scope.compare(.less, left, right)) return -1;
        if (try scope.compare(.greater, left, right)) return 1;
    }
    const left = try scope.get(a, "prerelease");
    const right = try scope.get(b, "prerelease");
    const left_len = try scope.length(left);
    const right_len = try scope.length(right);
    if (left_len > 0 and right_len == 0) return -1;
    if (left_len == 0 and right_len > 0) return 1;
    var position: u32 = 0;
    while (position < left_len or position < right_len) : (position += 1) {
        if (position >= right_len) return 1;
        if (position >= left_len) return -1;
        const one = try index(scope, left, position);
        const two = try index(scope, right, position);
        if (scope.equal(one, two)) continue;
        return compareIdentifiers(scope, regex, one, two);
    }
    return 0;
}
