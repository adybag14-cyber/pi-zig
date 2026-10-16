//! Actual package pattern orchestration over required real minimatch and path
//! imports. This is not a replacement minimatch or ignore implementation.
const v = @import("native_ai_provider_values.zig");
const Scope = v.Scope;
const c = v.c;
const f = @import("native_node_function.zig");
pub const Inputs = struct { paths: c.JSValue, normalize_path: c.JSValue, minimatch: c.JSValue };
const Method = enum(i32) { toPosixPath, isPattern, isOverridePattern, hasGlobPattern, splitPatterns, normalizeExactPattern, matchesAnyPattern, matchesAnyExactPattern, getOverridePatterns, isEnabledByOverrides, applyPatterns, applyAutoloadDisabledPatterns };
const Callback = enum(i32) { glob, exact, override, prefix, strip, include_glob, exclude_glob, exclude_exact };
fn arg(args: []const c.JSValue, index: usize) c.JSValue { return if (index < args.len) args[index] else c.pi_js_undefined(); }
fn object(s: *Scope) !c.JSValue { return s.own(try s.engine.checked(c.JS_NewObjectProto(s.engine.context, c.pi_js_null()))); }
pub fn create(engine: *v.em.Engine, inputs: Inputs) !c.JSValue {
    var s: Scope = .{ .engine = engine }; defer s.deinit(); const imports = try object(&s);
    inline for (.{ "relative", "basename", "dirname" }) |name| { const value = try s.get(inputs.paths, name); if (!c.JS_IsFunction(engine.context, value)) return error.RequiredActualPackagePatternImport; try s.put(imports, name, value); }
    inline for (.{ .{ "normalizePath", inputs.normalize_path }, .{ "minimatch", inputs.minimatch } }) |entry| { if (!c.JS_IsFunction(engine.context, entry[1])) return error.RequiredActualPackagePatternImport; try s.put(imports, entry[0], entry[1]); }
    const sep = try s.get(inputs.paths, "sep"); if (!c.JS_IsString(sep)) return error.RequiredActualPackagePatternSeparator; try s.put(imports, "sep", sep);
    const result = try s.object();
    inline for (@typeInfo(Method).@"enum".fields) |field| { const kind: Method = @enumFromInt(field.value); const length: c_int = switch (kind) { .matchesAnyPattern, .matchesAnyExactPattern, .isEnabledByOverrides, .applyPatterns, .applyAutoloadDisabledPatterns => 3, else => 1 }; try s.put(result, field.name, try s.own(try f.create(engine, field.name, length, method, &.{ imports, c.JS_NewInt32(engine.context, field.value) }))); }
    return c.JS_DupValue(engine.context, result);
}
fn imported(s: *Scope, imports: c.JSValue, name: [*:0]const u8, args: []const c.JSValue) !c.JSValue { return s.call(try s.get(imports, name), c.pi_js_undefined(), args); }
fn starts(s: *Scope, value: c.JSValue, prefix: []const u8) !bool { return s.truthy(try s.invoke(value, "startsWith", &.{try s.text(prefix)})); }
fn contains(s: *Scope, value: c.JSValue, part: []const u8) !bool { return s.truthy(try s.invoke(value, "includes", &.{try s.text(part)})); }
fn posix(s: *Scope, imports: c.JSValue, path: c.JSValue) !c.JSValue { return s.invoke(try s.invoke(path, "split", &.{try s.get(imports, "sep")}), "join", &.{try s.text("/")}); }
fn exactPattern(s: *Scope, imports: c.JSValue, pattern: c.JSValue) !c.JSValue { const value = if (try starts(s, pattern, "./") or try starts(s, pattern, ".\\")) try s.invoke(pattern, "slice", &.{c.JS_NewInt32(s.engine.context, 2)}) else pattern; return posix(s, imports, try imported(s, imports, "normalizePath", &.{value})); }
fn override(s: *Scope, value: c.JSValue) !bool { return try starts(s, value, "!") or try starts(s, value, "+") or try starts(s, value, "-"); }
fn callback(s: *Scope, kind: Callback, roots: []const c.JSValue) !c.JSValue {
    const values = try s.engine.gpa.alloc(c.JSValue, roots.len + 1); defer s.engine.gpa.free(values); values[0] = c.JS_NewInt32(s.engine.context, @intFromEnum(kind)); @memcpy(values[1..], roots);
    return s.own(try f.createArrow(s.engine, "", 1, predicate, values));
}
fn matches(s: *Scope, imports: c.JSValue, path: c.JSValue, patterns: c.JSValue, base: c.JSValue, exact: bool) !c.JSValue {
    if (exact and s.equal(try s.get(patterns, "length"), c.JS_NewInt32(s.engine.context, 0))) return c.pi_js_bool(s.engine.context, 0);
    const state = try object(s);
    const rel = try posix(s, imports, try imported(s, imports, "relative", &.{ base, path })); try s.put(state, "relative", rel);
    const name = try imported(s, imports, "basename", &.{path}); try s.put(state, "name", name);
    try s.put(state, "absolute", try posix(s, imports, path)); const skill = try v.eq(s, name, "SKILL.md"); try s.put(state, "skill", c.pi_js_bool(s.engine.context, @intFromBool(skill)));
    const parent = if (skill) try imported(s, imports, "dirname", &.{path}) else c.pi_js_undefined();
    try s.put(state, "parentRelative", if (skill) try posix(s, imports, try imported(s, imports, "relative", &.{ base, parent })) else c.pi_js_undefined());
    if (!exact) try s.put(state, "parentName", if (skill) try imported(s, imports, "basename", &.{parent}) else c.pi_js_undefined());
    try s.put(state, "parentAbsolute", if (skill) try posix(s, imports, parent) else c.pi_js_undefined());
    const some = try s.get(patterns, "some"); return s.call(some, patterns, &.{try callback(s, if (exact) .exact else .glob, &.{ imports, state })});
}
fn predicate(engine: *v.em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine }; defer s.deinit(); var raw: i32 = 0; if (c.JS_ToInt32(engine.context, &raw, roots[0]) < 0) return v.js.capture(engine);
    const input = arg(args, 0);
    switch (@as(Callback, @enumFromInt(raw))) {
        .override => return c.pi_js_bool(engine.context, @intFromBool(try override(&s, input))),
        .prefix => return s.invoke(input, "startsWith", &.{roots[1]}),
        .strip => return s.invoke(input, "slice", &.{c.JS_NewInt32(engine.context, 1)}),
        .include_glob, .exclude_glob, .exclude_exact => |kind| { const value = try matches(&s, roots[1], input, roots[2], roots[3], kind == .exclude_exact); return c.pi_js_bool(engine.context, @intFromBool(if (kind == .include_glob) s.truthy(value) else !s.truthy(value))); },
        .glob, .exact => |kind| {
            const imports = roots[1]; const state = roots[2]; const pattern = if (kind == .exact) try exactPattern(&s, imports, input) else try posix(&s, imports, try imported(&s, imports, "normalizePath", &.{input}));
            inline for (.{ "relative", "name", "absolute" }) |field| {
                if (comptime @import("std").mem.eql(u8, field, "name")) { if (kind == .exact) continue; }
                const value = try s.get(state, field);
                if (if (kind == .exact) s.equal(pattern, value) else s.truthy(try imported(&s, imports, "minimatch", &.{ value, pattern }))) return c.pi_js_bool(engine.context, 1);
            }
            if (!s.truthy(try s.get(state, "skill"))) return c.pi_js_bool(engine.context, 0);
            inline for (.{ "parentRelative", "parentName", "parentAbsolute" }) |field| {
                if (comptime @import("std").mem.eql(u8, field, "parentName")) { if (kind == .exact) continue; }
                const value = try s.get(state, field);
                if (if (kind == .exact) s.equal(pattern, value) else s.truthy(try imported(&s, imports, "minimatch", &.{ value, pattern }))) return c.pi_js_bool(engine.context, 1);
            }
            return c.pi_js_bool(engine.context, 0);
        },
    }
}
fn filterPrefix(s: *Scope, values: c.JSValue, prefix: []const u8) !c.JSValue {
    const selected = try s.invoke(values, "filter", &.{try callback(s, .prefix, &.{try s.text(prefix)})}); return s.invoke(selected, "map", &.{try callback(s, .strip, &.{})});
}
fn overrides(s: *Scope, values: c.JSValue) !c.JSValue { return s.invoke(values, "filter", &.{try callback(s, .override, &.{})}); }
fn enabled(s: *Scope, imports: c.JSValue, path: c.JSValue, patterns: c.JSValue, base: c.JSValue) !c.JSValue {
    const all = try overrides(s, patterns); const excludes = try filterPrefix(s, all, "!"); const includes = try filterPrefix(s, all, "+"); const disabled = try filterPrefix(s, all, "-"); var value = true;
    if (try v.length(s, excludes) > 0 and s.truthy(try matches(s, imports, path, excludes, base, false))) value = false;
    if (try v.length(s, includes) > 0 and s.truthy(try matches(s, imports, path, includes, base, true))) value = true;
    if (try v.length(s, disabled) > 0 and s.truthy(try matches(s, imports, path, disabled, base, true))) value = false;
    return c.pi_js_bool(s.engine.context, @intFromBool(value));
}
fn apply(s: *Scope, imports: c.JSValue, paths: c.JSValue, patterns: c.JSValue, base: c.JSValue) !c.JSValue {
    const includes = try s.array(); const excludes = try s.array(); const forced = try s.array(); const disabled = try s.array();
    var iterator = try v.iterator(s, patterns); defer iterator.deinit(); errdefer iterator.closePreserving();
    while (try iterator.next()) |pattern| { defer s.engine.freeValue(pattern); if (try starts(s, pattern, "+")) try v.js.push(s.engine, forced, try s.invoke(pattern, "slice", &.{c.JS_NewInt32(s.engine.context, 1)})) else if (try starts(s, pattern, "-")) try v.js.push(s.engine, disabled, try s.invoke(pattern, "slice", &.{c.JS_NewInt32(s.engine.context, 1)})) else if (try starts(s, pattern, "!")) try v.js.push(s.engine, excludes, try s.invoke(pattern, "slice", &.{c.JS_NewInt32(s.engine.context, 1)})) else try v.js.push(s.engine, includes, pattern); }
    var result: c.JSValue = undefined;
    if (try v.length(s, includes) == 0) {
        result = try s.array(); var source = try v.iterator(s, paths); defer source.deinit(); errdefer source.closePreserving(); while (try source.next()) |path| { defer s.engine.freeValue(path); try s.index(result, try v.length(s, result), path); }
    } else result = try s.invoke(paths, "filter", &.{try callback(s, .include_glob, &.{ imports, includes, base })});
    if (try v.length(s, excludes) > 0) result = try s.invoke(result, "filter", &.{try callback(s, .exclude_glob, &.{ imports, excludes, base })});
    if (try v.length(s, forced) > 0) {
        var source = try v.iterator(s, paths); defer source.deinit(); errdefer source.closePreserving(); while (try source.next()) |path| { defer s.engine.freeValue(path); if (!s.truthy(try s.invoke(result, "includes", &.{path})) and s.truthy(try matches(s, imports, path, forced, base, true))) try v.js.push(s.engine, result, path); }
    }
    if (try v.length(s, disabled) > 0) result = try s.invoke(result, "filter", &.{try callback(s, .exclude_exact, &.{ imports, disabled, base })});
    return s.own(try v.js.builtin(s.engine, "Set", &.{result}));
}
fn autoload(s: *Scope, imports: c.JSValue, paths: c.JSValue, patterns: c.JSValue, base: c.JSValue) !c.JSValue {
    const result = try s.own(try v.js.builtin(s.engine, "Map", &.{})); var iterator = try v.iterator(s, patterns); defer iterator.deinit(); errdefer iterator.closePreserving();
    while (try iterator.next()) |pattern| {
        defer s.engine.freeValue(pattern); const prefixed = try starts(s, pattern, "+") or try starts(s, pattern, "-") or try starts(s, pattern, "!");
        const target = try s.invoke(pattern, "slice", &.{c.JS_NewInt32(s.engine.context, @intFromBool(prefixed))}); const value = !try starts(s, pattern, "-") and !try starts(s, pattern, "!"); const exact = try starts(s, pattern, "+") or try starts(s, pattern, "-");
        var files = try v.iterator(s, paths); defer files.deinit(); errdefer files.closePreserving(); while (try files.next()) |path| { defer s.engine.freeValue(path); const one = try s.array(); try s.index(one, 0, target); if (s.truthy(try matches(s, imports, path, one, base, exact))) _ = try s.invoke(result, "set", &.{ path, c.pi_js_bool(s.engine.context, @intFromBool(value)) }); }
    }
    return result;
}
fn method(engine: *v.em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine }; defer s.deinit(); var raw: i32 = 0; if (c.JS_ToInt32(engine.context, &raw, roots[1]) < 0) return v.js.capture(engine); const imports = roots[0]; const first = arg(args, 0);
    const result = switch (@as(Method, @enumFromInt(raw))) {
        .toPosixPath => try posix(&s, imports, first), .isPattern => c.pi_js_bool(engine.context, @intFromBool(try override(&s, first) or try contains(&s, first, "*") or try contains(&s, first, "?"))), .isOverridePattern => c.pi_js_bool(engine.context, @intFromBool(try override(&s, first))), .hasGlobPattern => c.pi_js_bool(engine.context, @intFromBool(try contains(&s, first, "*") or try contains(&s, first, "?"))),
        .splitPatterns => blk: { const plain = try s.array(); const patterns = try s.array(); var iterator = try v.iterator(&s, first); defer iterator.deinit(); errdefer iterator.closePreserving(); while (try iterator.next()) |value| { defer engine.freeValue(value); const is_pattern = try override(&s, value) or try contains(&s, value, "*") or try contains(&s, value, "?"); try v.js.push(engine, if (is_pattern) patterns else plain, value); } const value = try s.object(); try s.put(value, "plain", plain); try s.put(value, "patterns", patterns); break :blk value; },
        .normalizeExactPattern => try exactPattern(&s, imports, first), .matchesAnyPattern => try matches(&s, imports, first, arg(args, 1), arg(args, 2), false), .matchesAnyExactPattern => try matches(&s, imports, first, arg(args, 1), arg(args, 2), true), .getOverridePatterns => try overrides(&s, first), .isEnabledByOverrides => try enabled(&s, imports, first, arg(args, 1), arg(args, 2)), .applyPatterns => try apply(&s, imports, first, arg(args, 1), arg(args, 2)), .applyAutoloadDisabledPatterns => try autoload(&s, imports, first, arg(args, 1), arg(args, 2)),
    }; return c.JS_DupValue(engine.context, result);
}
